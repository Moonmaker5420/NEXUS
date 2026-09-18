"""
Custom Forwarding Authentication Service (FAS) for openNDS.

Implements fas_secure_enabled level 1 (hashed token, local/loopback FAS).

Authentication methods:
  1. MAC allow-list
  2. Voucher code
  3. Username / password

Successful authentication sends RADIUS Accounting-Start.
Session termination is handled by openNDS BinAuth and Accounting-Stop.
"""

import json
import base64
import hashlib
import os
import subprocess
from datetime import datetime
from urllib.parse import urlencode, unquote

import pymysql
import pymysql.cursors
from flask import (
    Flask,
    request,
    render_template,
    redirect,
    abort,
    send_from_directory,
    url_for,
)

from radius_client import radius_pap_auth, radius_acct_start


app = Flask(__name__)


# ---------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------

FASKEY = os.environ.get(
    "FAS_KEY",
    "CHANGE_ME_TO_A_LONG_RANDOM_SECRET",
)

DB_HOST = os.environ.get(
    "PORTAL_DB_HOST",
    "127.0.0.1",
)

DB_USER = os.environ.get(
    "PORTAL_DB_USER",
    "portal_fas",
)

DB_PASS = os.environ.get(
    "PORTAL_DB_PASS",
    "changeme",
)

DB_NAME = os.environ.get(
    "PORTAL_DB_NAME",
    "portal",
)


RADIUS_SERVER = os.environ.get(
    "RADIUS_SERVER",
    "127.0.0.1",
)

RADIUS_SECRET = os.environ.get(
    "RADIUS_SECRET",
    "changeme",
)

RADIUS_NAS_IDENTIFIER = os.environ.get(
    "RADIUS_NAS_IDENTIFIER",
    "opennds-fas",
)


FAS_STATUS_URL = os.environ.get(
    "FAS_STATUS_URL",
    "http://192.168.1.44:2080/fas/status",
)


NDSCTL_BIN = os.environ.get(
    "NDSCTL_BIN",
    "/usr/bin/ndsctl",
)


# ---------------------------------------------------------------------
# Database
# ---------------------------------------------------------------------

def db():
    return pymysql.connect(
        host=DB_HOST,
        user=DB_USER,
        password=DB_PASS,
        database=DB_NAME,
        cursorclass=pymysql.cursors.DictCursor,
        autocommit=True,
    )


def radius_db():
    return pymysql.connect(
        host=DB_HOST,
        user=DB_USER,
        password=DB_PASS,
        database="radius",
        cursorclass=pymysql.cursors.DictCursor,
        autocommit=True,
    )


# ---------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------

def normalize_mac(mac):
    return mac.strip().lower().replace("-", ":")


def decode_fas_blob(b64_string):

    try:
        decoded = base64.b64decode(
            b64_string
        ).decode("utf-8")

    except Exception:
        abort(
            400,
            "malformed fas token",
        )

    fields = {}

    for pair in decoded.split(", "):

        if "=" in pair:

            k, v = pair.split("=", 1)

            fields[k.strip()] = unquote(
                v.strip()
            )

    return fields


def compute_rhid(hid):

    return hashlib.sha256(
        (hid + FASKEY).encode(
            "utf-8"
        )
    ).hexdigest()


def build_auth_redirect(
    gatewayaddress,
    hid,
    redir_url,
    clientip,
    gatewayname,
):

    rhid = compute_rhid(hid)

    qs = urlencode(
        {
            "clientip": clientip,
            "gatewayname": gatewayname,
            "tok": rhid,
            "redir": redir_url,
        }
    )

    return (
        f"http://{gatewayaddress}"
        f"/opennds_auth/?{qs}"
    )


# ---------------------------------------------------------------------
# RADIUS authentication
# ---------------------------------------------------------------------

def do_radius_auth_and_account(
    username,
    password,
    hid,
    clientip,
    clientmac,
):
    """
    Shared final authentication step.

    Performs RADIUS PAP authentication.

    If successful, sends RADIUS Accounting-Start.
    """

    ok = radius_pap_auth(
        username,
        password,
        server=RADIUS_SERVER,
        secret=RADIUS_SECRET,
        nas_identifier=RADIUS_NAS_IDENTIFIER,
    )

    if ok:

        radius_acct_start(
            username,
            hid,
            clientip,
            clientmac,
            server=RADIUS_SERVER,
            secret=RADIUS_SECRET,
            nas_identifier=RADIUS_NAS_IDENTIFIER,
        )

    return ok


# ---------------------------------------------------------------------
# Authentication logging
# ---------------------------------------------------------------------

def log_grant(
    gatewayname,
    client_mac,
    client_ip,
    method,
    identifier,
    acct_session_id,
):

    conn = db()

    try:

        with conn.cursor() as cur:

            cur.execute(
                """
                INSERT INTO auth_log
                (
                    gatewayname,
                    client_mac,
                    client_ip,
                    auth_method,
                    identifier,
                    acct_session_id,
                    session_start
                )
                VALUES
                (
                    %s,
                    %s,
                    %s,
                    %s,
                    %s,
                    %s,
                    %s
                )
                """,
                (
                    gatewayname,
                    client_mac,
                    client_ip,
                    method,
                    identifier,
                    acct_session_id,
                    datetime.utcnow(),
                ),
            )

    finally:

        conn.close()


# ---------------------------------------------------------------------
# Plan lookup
# ---------------------------------------------------------------------

def get_plan_for_radius_user(username):
    """
    Password logins:
    Look up the user's assigned plan through radius_users.
    """

    conn = db()

    try:

        with conn.cursor() as cur:

            cur.execute(
                """
                SELECT p.*
                FROM radius_users ru
                JOIN plans p
                    ON p.id = ru.plan_id
                WHERE ru.username=%s
                """,
                (username,),
            )

            plan = cur.fetchone()

    finally:

        conn.close()

    return plan


def get_session_usage(identifier):
    """
    Return total session usage in seconds for an identifier.

    Closed sessions use acctsessiontime. An open RADIUS session also includes
    elapsed wall-clock time so reconnecting cannot reset a total time limit.
    """
    conn = radius_db()
    try:
        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT
                    COALESCE(
                        SUM(
                            CASE
                                WHEN acctstoptime IS NULL
                                THEN GREATEST(
                                    COALESCE(acctsessiontime, 0),
                                    TIMESTAMPDIFF(
                                        SECOND,
                                        acctstarttime,
                                        NOW()
                                    )
                                )
                                ELSE COALESCE(acctsessiontime, 0)
                            END
                        ),
                        0
                    ) AS used_seconds
                FROM radacct
                WHERE username=%s
                """,
                (identifier,),
            )
            row = cur.fetchone()
    finally:
        conn.close()

    return int((row or {}).get("used_seconds") or 0)


def get_remaining_session_seconds(identifier, limits):
    """
    Return remaining cumulative session time in seconds.

    None means the plan has no cumulative session limit.
    """
    if not limits:
        return None

    try:
        session_minutes = int(
            limits.get("session_minutes") or 0
        )
    except (TypeError, ValueError):
        return None

    if session_minutes <= 0:
        return None

    return max(
        0,
        (session_minutes * 60) - get_session_usage(identifier),
    )


def session_limit_reached(identifier, limits):
    """
    Return True when all cumulative session time has been consumed.
    """
    remaining_seconds = get_remaining_session_seconds(
        identifier,
        limits,
    )

    return (
        remaining_seconds is not None
        and remaining_seconds <= 0
    )


def remaining_session_minutes(identifier, limits):
    """
    Return whole remaining minutes. None means unlimited.
    """
    remaining_seconds = get_remaining_session_seconds(
        identifier,
        limits,
    )

    if remaining_seconds is None:
        return None

    return remaining_seconds // 60



# ---------------------------------------------------------------------
# Cumulative quota enforcement
# ---------------------------------------------------------------------

def get_quota_usage(identifier):
    """
    Return cumulative traffic usage in bytes for an identifier.

    On this openNDS/RADIUS stack:
      - acctinputoctets  = client download
      - acctoutputoctets = client upload

    This mapping matches the accounting values already verified on the
    portal's Usage Report.
    """
    conn = radius_db()

    try:
        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT
                    COALESCE(
                        SUM(acctinputoctets),
                        0
                    ) AS download_bytes,

                    COALESCE(
                        SUM(acctoutputoctets),
                        0
                    ) AS upload_bytes

                FROM radacct
                WHERE username=%s
                """,
                (identifier,),
            )

            row = cur.fetchone()

    finally:
        conn.close()

    row = row or {}

    return {
        "download_bytes": int(
            row.get("download_bytes") or 0
        ),
        "upload_bytes": int(
            row.get("upload_bytes") or 0
        ),
    }


def get_remaining_quota_bytes(identifier, limits):
    """
    Return remaining cumulative quota in bytes.

    None means unlimited for that direction.
    """
    usage = get_quota_usage(identifier)

    result = {}

    quota_map = {
        "download": "download_quota_kb",
        "upload": "upload_quota_kb",
    }

    for direction, limit_key in quota_map.items():

        try:
            quota_kb = int(
                (limits or {}).get(limit_key) or 0
            )
        except (
            TypeError,
            ValueError,
        ):
            quota_kb = 0

        if quota_kb <= 0:
            result[direction] = None
            continue

        allowed_bytes = quota_kb * 1024
        used_bytes = usage[f"{direction}_bytes"]

        result[direction] = max(
            0,
            allowed_bytes - used_bytes,
        )

    return result


def quota_limit_reached(identifier, limits):
    """
    Return True when either configured upload or download quota
    has been fully consumed.
    """
    remaining = get_remaining_quota_bytes(
        identifier,
        limits,
    )

    return any(
        value is not None and value <= 0
        for value in remaining.values()
    )


def remaining_quota_kb(identifier, limits):
    """
    Return remaining quotas in KB for openNDS.

    A value of None means unlimited.

    Positive remaining byte values are rounded UP to at least 1 KB because
    openNDS uses integer KB values and 0 means unlimited.
    """
    remaining = get_remaining_quota_bytes(
        identifier,
        limits,
    )

    result = {}

    for direction, remaining_bytes in remaining.items():

        if remaining_bytes is None:
            result[direction] = 0
        else:
            result[direction] = max(
                1,
                (remaining_bytes + 1023) // 1024,
            )

    return result



def resolve_limits(row):
    """
    Vouchers and MAC devices:

    Prefer a live plan lookup through plan_id.

    If there is no plan_id, fall back to values stored
    directly on the voucher/MAC device.
    """

    if not row:
        return {}

    plan = None

    if row.get("plan_id"):

        conn = db()

        try:

            with conn.cursor() as cur:

                cur.execute(
                    """
                    SELECT *
                    FROM plans
                    WHERE id=%s
                    """,
                    (row["plan_id"],),
                )

                plan = cur.fetchone()

        finally:

            conn.close()

    source = plan if plan else row

    return {
        "session_minutes":
            source.get("session_minutes"),

        "upload_kbits":
            source.get("upload_kbits"),

        "download_kbits":
            source.get("download_kbits"),

        "upload_quota_kb":
            source.get("upload_quota_kb"),

        "download_quota_kb":
            source.get("download_quota_kb"),

        "simultaneous_use":
            source.get("simultaneous_use", 1),
    }


# ---------------------------------------------------------------------
# Simultaneous login enforcement
# ---------------------------------------------------------------------

def get_simultaneous_use(limits):
    """
    Return the simultaneous device limit.

    Always returns at least 1.
    """

    try:

        value = int(
            (limits or {}).get(
                "simultaneous_use",
                1,
            )
            or 1
        )

    except (
        TypeError,
        ValueError,
    ):

        value = 1

    return max(
        1,
        value,
    )


def get_live_nds_clients():
    """
    Return all currently visible openNDS clients.

    Returns the clients dictionary from:

        ndsctl json
    """

    try:

        result = subprocess.run(
            [
                "sudo",
                "-n",
                NDSCTL_BIN,
                "json",
            ],
            capture_output=True,
            text=True,
            timeout=5,
        )

        if result.returncode != 0:

            return {}

        data = json.loads(
            result.stdout
        )

        return data.get(
            "clients",
            {},
        )

    except Exception:

        return {}


def simultaneous_login_allowed(
    identifier,
    clientmac,
    simultaneous_use,
):
    """
    Check whether another simultaneous login is allowed.

    auth_log alone is NOT trusted because old rows may remain
    with session_end IS NULL.

    Therefore:

    1. Find unfinished auth_log sessions for this identifier.
    2. Check which of those MAC addresses are ACTUALLY live
       in openNDS.
    3. Exclude the current MAC address so re-authentication from
       the same device does not consume another slot.
    """

    clientmac = normalize_mac(
        clientmac
    )

    simultaneous_use = max(
        1,
        int(simultaneous_use or 1),
    )

    # Get actual currently active openNDS clients.
    live_clients = get_live_nds_clients()

    # Fail open if openNDS JSON cannot be read.
    #
    # This avoids locking out all users because of a temporary
    # ndsctl failure.
    if live_clients is None:

        return True

    # Normalize live MAC addresses.
    live_macs = set()

    for mac in live_clients.keys():

        live_macs.add(
            normalize_mac(mac)
        )

    # Find open auth_log sessions belonging to this identity.
    conn = db()

    try:

        with conn.cursor() as cur:

            cur.execute(
                """
                SELECT DISTINCT
                    LOWER(client_mac) AS client_mac
                FROM auth_log
                WHERE identifier=%s
                  AND session_end IS NULL
                """,
                (identifier,),
            )

            rows = cur.fetchall()

    finally:

        conn.close()

    active_macs = set()

    for row in rows:

        mac = normalize_mac(
            row.get("client_mac") or ""
        )

        if not mac:
            continue

        # Count only sessions still really present in openNDS.
        if mac in live_macs:

            active_macs.add(mac)

    # Same device re-authentication does not consume another slot.
    active_macs.discard(
        clientmac
    )

    # Example:
    #
    # simultaneous_use = 1
    #
    # active_macs contains 0 OTHER devices
    #
    # 0 < 1 -> allowed
    #
    # If active_macs contains 1 OTHER device:
    #
    # 1 < 1 -> denied

    return (
        len(active_macs)
        < simultaneous_use
    )


# ---------------------------------------------------------------------
# Apply plan limits
# ---------------------------------------------------------------------

def apply_plan_limits(
    clientmac,
    limits,
    identifier,
    clientip,
):
    """
    Push limits to openNDS.

    For cumulative session limits, only the remaining time is sent to openNDS
    so reconnecting cannot reset the user's total allowance.

    Also applies traffic shaping using portal-tc-add.sh.
    """

    if not limits:

        return

    remaining_seconds = get_remaining_session_seconds(
        identifier,
        limits,
    )

    if remaining_seconds is None:
        session_timeout_minutes = 0
    else:
        session_timeout_minutes = max(
            1,
            (remaining_seconds + 59) // 60,
        )

    quotas = remaining_quota_kb(
        identifier,
        limits,
    )

    try:

        subprocess.run(
            [
                "sudo",
                "-n",
                NDSCTL_BIN,
                "auth",
                clientmac,

                str(
                    session_timeout_minutes
                ),

                str(
                    limits.get(
                        "upload_kbits"
                    )
                    or 0
                ),

                str(
                    limits.get(
                        "download_kbits"
                    )
                    or 0
                ),

                str(
                    quotas.get(
                        "upload",
                        0,
                    )
                ),

                str(
                    quotas.get(
                        "download",
                        0,
                    )
                ),

                identifier,
            ],
            capture_output=True,
            timeout=5,
        )

    except Exception:

        pass

    try:

        subprocess.run(
            [
                "sudo",
                "-n",
                "/usr/lib/opennds/portal-tc-add.sh",
                clientip,

                str(
                    limits.get(
                        "download_kbits"
                    )
                    or 0
                ),

                str(
                    limits.get(
                        "upload_kbits"
                    )
                    or 0
                ),
            ],
            capture_output=True,
            timeout=5,
        )

    except Exception:

        pass


# ---------------------------------------------------------------------
# Login entry
# ---------------------------------------------------------------------

@app.route(
    "/fas/login",
    methods=["GET"],
)
def login_entry():

    blob = request.args.get(
        "fas"
    )

    if not blob:

        return redirect(
            url_for(
                "status"
            )
        )

    fields = decode_fas_blob(
        blob
    )

    clientmac = normalize_mac(
        fields.get(
            "clientmac",
            "",
        )
    )

    clientip = fields.get(
        "clientip",
        "",
    )

    gatewayname = fields.get(
        "gatewayname",
        "",
    )

    gatewayaddress = fields.get(
        "gatewayaddress",
        "",
    )

    originurl = fields.get(
        "originurl",
        "/",
    )

    hid = fields.get(
        "hid",
        "",
    )


    # -------------------------------------------------------------
    # MAC allow-list login
    # -------------------------------------------------------------

    conn = db()

    try:

        with conn.cursor() as cur:

            cur.execute(
                """
                SELECT *
                FROM mac_devices
                WHERE mac_address=%s
                  AND status='active'
                  AND
                  (
                      expires_at IS NULL
                      OR expires_at > NOW()
                  )
                """,
                (clientmac,),
            )

            device = cur.fetchone()

    finally:

        conn.close()


    if device:

        limits = resolve_limits(
            device
        )

        simultaneous_use = (
            get_simultaneous_use(
                limits
            )
        )

        # MAC address is the actual identity.
        identifier = clientmac


        if not simultaneous_login_allowed(
            identifier,
            clientmac,
            simultaneous_use,
        ):

            return render_template(
                "login_error.html",

                reason=(
                    f"Maximum simultaneous device limit "
                    f"({simultaneous_use}) reached. "
                f"This account is already in use on another device."
                ),

                gatewayname=gatewayname,
                hid=hid,
                clientip=clientip,
                clientmac=clientmac,
                gatewayaddress=gatewayaddress,
                originurl=originurl,
            )


        if session_limit_reached(
            identifier,
            limits,
        ):

            return render_template(
                "login_error.html",

                reason=(
                    "This device has used its allowed session time "
                    "and can no longer be used."
                ),

                gatewayname=gatewayname,
                hid=hid,
                clientip=clientip,
                clientmac=clientmac,
                gatewayaddress=gatewayaddress,
                originurl=originurl,
            )


        if quota_limit_reached(
            identifier,
            limits,
        ):

            return render_template(
                "login_error.html",

                reason=(
                    "Quota Completed. Your allowed upload or "
                    "download data limit has been fully used."
                ),

                gatewayname=gatewayname,
                hid=hid,
                clientip=clientip,
                clientmac=clientmac,
                gatewayaddress=gatewayaddress,
                originurl=originurl,
            )


        ok = do_radius_auth_and_account(
            clientmac,
            clientmac,
            hid,
            clientip,
            clientmac,
        )


        if ok:

            apply_plan_limits(
                clientmac,
                limits,
                identifier,
                clientip,
            )


            log_grant(
                gatewayname,
                clientmac,
                clientip,
                "mac",
                identifier,
                hid,
            )


            return redirect(
                build_auth_redirect(
                    gatewayaddress,
                    hid,
                    FAS_STATUS_URL,
                    clientip,
                    gatewayname,
                )
            )


        # portal.mac_devices says active but RADIUS authentication failed.
        # Fall through to normal login form.


    # -------------------------------------------------------------
    # Show login page
    # -------------------------------------------------------------

    conn = db()

    try:

        with conn.cursor() as cur:

            cur.execute(
                """
                SELECT *
                FROM banners
                WHERE status='active'
                ORDER BY display_order
                """
            )

            active_banners = cur.fetchall()

    finally:

        conn.close()


    return render_template(
        "login.html",

        gatewayname=gatewayname,
        hid=hid,
        clientip=clientip,
        clientmac=clientmac,
        gatewayaddress=gatewayaddress,
        originurl=originurl,
        banners=active_banners,
    )


# ---------------------------------------------------------------------
# Password login
# ---------------------------------------------------------------------

@app.route(
    "/fas/login/password",
    methods=["POST"],
)
def login_password():

    username = request.form.get(
        "username",
        "",
    ).strip()

    password = request.form.get(
        "password",
        "",
    )

    hid = request.form.get(
        "hid",
        "",
    )

    clientmac = normalize_mac(
        request.form.get(
            "clientmac",
            "",
        )
    )

    clientip = request.form.get(
        "clientip",
        "",
    )

    gatewayname = request.form.get(
        "gatewayname",
        "",
    )

    gatewayaddress = request.form.get(
        "gatewayaddress",
        "",
    )

    originurl = request.form.get(
        "originurl",
        "/",
    )


    # -------------------------------------------------------------
    # Get plan BEFORE allowing another simultaneous login.
    # -------------------------------------------------------------

    plan = get_plan_for_radius_user(
        username
    )

    simultaneous_use = (
        get_simultaneous_use(
            plan
        )
    )


    if not simultaneous_login_allowed(
        username,
        clientmac,
        simultaneous_use,
    ):

        return render_template(
            "login_error.html",

            reason=(
                f"Maximum simultaneous device limit "
                f"({simultaneous_use}) reached. "
                f"This account is already in use on another device."
            ),

            gatewayname=gatewayname,
            hid=hid,
            clientip=clientip,
            clientmac=clientmac,
            gatewayaddress=gatewayaddress,
            originurl=originurl,
        )


    # -------------------------------------------------------------
    # Total cumulative session limit
    # -------------------------------------------------------------

    if session_limit_reached(
        username,
        plan,
    ):

        return render_template(
            "login_error.html",

            reason=(
                "Your allowed session time has been fully used. "
                "This account can no longer be used."
            ),

            gatewayname=gatewayname,
            hid=hid,
            clientip=clientip,
            clientmac=clientmac,
            gatewayaddress=gatewayaddress,
            originurl=originurl,
        )


    # -------------------------------------------------------------
    # Total cumulative quota limit
    # -------------------------------------------------------------

    if quota_limit_reached(
        username,
        plan,
    ):

        return render_template(
            "login_error.html",

            reason=(
                "Quota Completed. Your allowed upload or "
                "download data limit has been fully used."
            ),

            gatewayname=gatewayname,
            hid=hid,
            clientip=clientip,
            clientmac=clientmac,
            gatewayaddress=gatewayaddress,
            originurl=originurl,
        )


    # -------------------------------------------------------------
    # RADIUS authentication
    # -------------------------------------------------------------

    ok = do_radius_auth_and_account(
        username,
        password,
        hid,
        clientip,
        clientmac,
    )


    if not ok:

        return render_template(
            "login_error.html",

            reason=(
                "Invalid username or password"
            ),

            gatewayname=gatewayname,
            hid=hid,
            clientip=clientip,
            clientmac=clientmac,
            gatewayaddress=gatewayaddress,
            originurl=originurl,
        )


    # -------------------------------------------------------------
    # Apply limits
    # -------------------------------------------------------------

    apply_plan_limits(
        clientmac,
        plan,
        username,
        clientip,
    )


    # -------------------------------------------------------------
    # Log session
    # -------------------------------------------------------------

    log_grant(
        gatewayname,
        clientmac,
        clientip,
        "password",
        username,
        hid,
    )


    return redirect(
        build_auth_redirect(
            gatewayaddress,
            hid,
            FAS_STATUS_URL,
            clientip,
            gatewayname,
        )
    )


# ---------------------------------------------------------------------
# Voucher login
# ---------------------------------------------------------------------

@app.route(
    "/fas/login/voucher",
    methods=["POST"],
)
def login_voucher():

    code = request.form.get(
        "code",
        "",
    ).strip().upper()

    hid = request.form.get(
        "hid",
        "",
    )

    clientmac = normalize_mac(
        request.form.get(
            "clientmac",
            "",
        )
    )

    clientip = request.form.get(
        "clientip",
        "",
    )

    gatewayname = request.form.get(
        "gatewayname",
        "",
    )

    gatewayaddress = request.form.get(
        "gatewayaddress",
        "",
    )

    originurl = request.form.get(
        "originurl",
        "/",
    )


    # -------------------------------------------------------------
    # Load voucher
    # -------------------------------------------------------------

    conn = db()

    with conn.cursor() as cur:

        cur.execute(
            """
            SELECT *
            FROM vouchers
            WHERE code=%s
            FOR UPDATE
            """,
            (code,),
        )

        voucher = cur.fetchone()


        valid = (

            voucher is not None

            and voucher["status"] == "active"

            and voucher["used_count"]
                < voucher["max_uses"]

            and (
                voucher["valid_from"] is None
                or voucher["valid_from"]
                    <= datetime.utcnow()
            )

            and (
                voucher["valid_until"] is None
                or voucher["valid_until"]
                    >= datetime.utcnow()
            )
        )


        if not valid:

            conn.close()

            return render_template(
                "login_error.html",

                reason=(
                    "Invalid or expired voucher code"
                ),

                gatewayname=gatewayname,
                hid=hid,
                clientip=clientip,
                clientmac=clientmac,
                gatewayaddress=gatewayaddress,
                originurl=originurl,
            )


        # ---------------------------------------------------------
        # Resolve voucher limits and simultaneous use
        # ---------------------------------------------------------

        limits = resolve_limits(
            voucher
        )

        simultaneous_use = (
            get_simultaneous_use(
                limits
            )
        )


        if not simultaneous_login_allowed(
            code,
            clientmac,
            simultaneous_use,
        ):

            conn.close()

            return render_template(
                "login_error.html",

                reason=(
                    f"Maximum simultaneous device limit "
                    f"({simultaneous_use}) reached. "
                f"This account is already in use on another device."
                ),

                gatewayname=gatewayname,
                hid=hid,
                clientip=clientip,
                clientmac=clientmac,
                gatewayaddress=gatewayaddress,
                originurl=originurl,
            )


        # ---------------------------------------------------------
        # Total cumulative session limit
        # ---------------------------------------------------------

        if session_limit_reached(
            code,
            limits,
        ):

            conn.close()

            return render_template(
                "login_error.html",

                reason=(
                    "This voucher has used its allowed session time "
                    "and can no longer be used."
                ),

                gatewayname=gatewayname,
                hid=hid,
                clientip=clientip,
                clientmac=clientmac,
                gatewayaddress=gatewayaddress,
                originurl=originurl,
            )


        # ---------------------------------------------------------
        # Total cumulative quota limit
        # ---------------------------------------------------------

        if quota_limit_reached(
            code,
            limits,
        ):

            conn.close()

            return render_template(
                "login_error.html",

                reason=(
                    "Quota Completed. Your allowed upload or "
                    "download data limit has been fully used."
                ),

                gatewayname=gatewayname,
                hid=hid,
                clientip=clientip,
                clientmac=clientmac,
                gatewayaddress=gatewayaddress,
                originurl=originurl,
            )


        # ---------------------------------------------------------
        # RADIUS authentication
        # ---------------------------------------------------------

        ok = do_radius_auth_and_account(
            code,
            code,
            hid,
            clientip,
            clientmac,
        )


        if not ok:

            conn.close()

            return render_template(
                "login_error.html",

                reason=(
                    "Voucher not recognized by RADIUS - "
                    "contact support"
                ),

                gatewayname=gatewayname,
                hid=hid,
                clientip=clientip,
                clientmac=clientmac,
                gatewayaddress=gatewayaddress,
                originurl=originurl,
            )


        # ---------------------------------------------------------
        # Update voucher usage
        # ---------------------------------------------------------

        cur.execute(
            """
            UPDATE vouchers
            SET used_count =
                used_count + 1
            WHERE id=%s
            """,
            (voucher["id"],),
        )


        new_used = (
            voucher["used_count"]
            + 1
        )


        if new_used >= voucher["max_uses"]:

            cur.execute(
                """
                UPDATE vouchers
                SET status='expired'
                WHERE id=%s
                """,
                (voucher["id"],),
            )


            # Remove RADIUS credentials so the voucher
            # cannot authenticate again.

            rconn = radius_db()

            try:

                with rconn.cursor() as rcur:

                    rcur.execute(
                        """
                        DELETE FROM radcheck
                        WHERE username=%s
                        """,
                        (code,),
                    )

            finally:

                rconn.close()


        cur.execute(
            """
            INSERT INTO voucher_redemptions
            (
                voucher_id,
                client_mac,
                client_ip
            )
            VALUES
            (
                %s,
                %s,
                %s
            )
            """,
            (
                voucher["id"],
                clientmac,
                clientip,
            ),
        )


    conn.close()


    # -------------------------------------------------------------
    # Apply limits
    # -------------------------------------------------------------

    apply_plan_limits(
        clientmac,
        limits,
        code,
        clientip,
    )


    # -------------------------------------------------------------
    # Log session
    # -------------------------------------------------------------

    log_grant(
        gatewayname,
        clientmac,
        clientip,
        "voucher",
        code,
        hid,
    )


    return redirect(
        build_auth_redirect(
            gatewayaddress,
            hid,
            FAS_STATUS_URL,
            clientip,
            gatewayname,
        )
    )


# ---------------------------------------------------------------------
# Banner images
# ---------------------------------------------------------------------

BANNER_IMAGES_DIR = (
    "/opt/portal/banner_images"
)


@app.route(
    "/banner-images/<filename>"
)
def serve_banner_image(filename):

    return send_from_directory(
        BANNER_IMAGES_DIR,
        filename,
    )


# ---------------------------------------------------------------------
# openNDS live client lookup
# ---------------------------------------------------------------------

def get_nds_client(
    clientmac=None,
    clientip=None,
):
    """
    Return live openNDS client information
    from ndsctl json.
    """

    try:

        result = subprocess.run(
            [
                "sudo",
                "-n",
                NDSCTL_BIN,
                "json",
            ],
            capture_output=True,
            text=True,
            timeout=5,
        )


        if result.returncode != 0:

            return None


        data = json.loads(
            result.stdout
        )


        clients = data.get(
            "clients",
            {},
        )


        normalized_mac = (

            normalize_mac(
                clientmac
            )

            if clientmac

            else None
        )


        # Prefer MAC lookup.

        if normalized_mac:

            for mac, client in clients.items():

                if (
                    normalize_mac(mac)
                    == normalized_mac
                ):

                    return client


        # Fall back to IP lookup.

        if clientip:

            for mac, client in clients.items():

                if (
                    client.get("ip")
                    == clientip
                ):

                    return client


        return None


    except Exception:

        return None


# ---------------------------------------------------------------------
# Client status
# ---------------------------------------------------------------------

@app.route(
    "/fas/status",
    methods=["GET"],
)
def status():

    clientip = request.remote_addr


    client = get_nds_client(
        clientip=clientip
    )


    if not client:

        return render_template(
            "status.html",

            client=None,

            error=(
                "No active session was found "
                "for this device."
            ),
        )


    return render_template(
        "status.html",

        client=client,

        error=None,
    )


# ---------------------------------------------------------------------
# Sign out
# ---------------------------------------------------------------------

@app.route(
    "/fas/signout",
    methods=["POST"],
)
def signout():

    clientip = request.remote_addr


    client = get_nds_client(
        clientip=clientip
    )


    if not client:

        return render_template(
            "status.html",

            client=None,

            error=(
                "No active session was found "
                "for this device."
            ),
        )


    clientmac = client.get(
        "mac"
    )


    if not clientmac:

        return render_template(
            "status.html",

            client=None,

            error=(
                "Unable to identify this device."
            ),
        )


    try:

        result = subprocess.run(
            [
                "sudo",
                "-n",
                NDSCTL_BIN,
                "deauth",
                clientmac,
            ],
            capture_output=True,
            text=True,
            timeout=5,
        )


        if result.returncode != 0:

            return render_template(
                "status.html",

                client=client,

                error=(
                    "Unable to disconnect this device."
                ),
            )


    except Exception:

        return render_template(
            "status.html",

            client=client,

            error=(
                "Unable to disconnect this device."
            ),
        )


    return render_template(
        "status.html",

        client=None,

        error=None,

        signed_out=True,
    )


# ---------------------------------------------------------------------
# Development server
# ---------------------------------------------------------------------

if __name__ == "__main__":

    app.run(
        host="127.0.0.1",
        port=2080,
    )
