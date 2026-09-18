"""
Custom management dashboard for the openNDS + FreeRADIUS portal.

Covers what DaloRADIUS doesn't natively do:
  - Plans/tiers (reusable templates for session length, speed caps, data caps)
  - Voucher generation (single + bulk) and lifecycle
  - MAC allow-list management
  - Live client sessions (via `ndsctl json`)
  - Unified reporting (portal.auth_log)

RADIUS user CRUD (radcheck/radusergroup) is handled here too as a thin
convenience layer; full accounting/reporting stays in DaloRADIUS.
"""

import json
import os
import random
import re
import string
import subprocess
import uuid
from datetime import datetime, timedelta
from functools import wraps

import pymysql
import pymysql.cursors
from flask import Flask, render_template, request, redirect, url_for, session, flash
from werkzeug.security import check_password_hash

app = Flask(__name__)
app.secret_key = os.environ.get("DASHBOARD_SECRET_KEY", "CHANGE_ME_dev_only")

DB_HOST = os.environ.get("PORTAL_DB_HOST", "127.0.0.1")
DB_USER = os.environ.get("PORTAL_DB_USER", "portal_dashboard")
DB_PASS = os.environ.get("PORTAL_DB_PASS", "changeme")

NDSCTL_BIN = os.environ.get("NDSCTL_BIN", "/usr/bin/ndsctl")


def db(dbname):
    return pymysql.connect(
        host=DB_HOST, user=DB_USER, password=DB_PASS, database=dbname,
        cursorclass=pymysql.cursors.DictCursor, autocommit=True,
    )


def portal_db():
    return db("portal")


def radius_db():
    return db("radius")


# ------------------------------------------------------------ auth guard --

def login_required(f):
    @wraps(f)
    def wrapper(*args, **kwargs):
        if "admin_id" not in session:
            return redirect(url_for("login", next=request.path))
        return f(*args, **kwargs)
    return wrapper


@app.route("/login", methods=["GET", "POST"])
def login():
    if request.method == "POST":
        username = request.form.get("username", "").strip()
        password = request.form.get("password", "")
        conn = portal_db()
        with conn.cursor() as cur:
            cur.execute("SELECT * FROM dashboard_admins WHERE username=%s", (username,))
            admin = cur.fetchone()
        conn.close()
        if admin and check_password_hash(admin["password_hash"], password):
            session["admin_id"] = admin["id"]
            session["admin_username"] = admin["username"]
            session["admin_role"] = admin["role"]
            return redirect(request.args.get("next") or url_for("index"))
        flash("Invalid credentials", "error")
    return render_template("login.html")


@app.route("/logout")
def logout():
    session.clear()
    return redirect(url_for("login"))


# -------------------------------------------------------------- dashboard --

def check_internet():
    """Ping a public host to check WAN connectivity. Ubuntu's ping binary
    has cap_net_raw set by the OS package, so this works without sudo."""
    try:
        result = subprocess.run(
            ["ping", "-c", "1", "-W", "2", "8.8.8.8"],
            capture_output=True, text=True, timeout=5,
        )
        if result.returncode == 0:
            match = re.search(r"time=([\d.]+)", result.stdout)
            return {"online": True, "latency_ms": match.group(1) if match else "?"}
        return {"online": False, "latency_ms": None}
    except Exception:
        return {"online": False, "latency_ms": None}


def check_service(name):
    """systemctl is-active is a read-only status query - no privileges needed."""
    try:
        result = subprocess.run(
            ["systemctl", "is-active", name], capture_output=True, text=True, timeout=3,
        )
        return result.stdout.strip()
    except Exception:
        return "unknown"


def get_uptime():
    try:
        with open("/proc/uptime") as f:
            seconds = float(f.read().split()[0])
        days, rem = divmod(int(seconds), 86400)
        hours, rem = divmod(rem, 3600)
        minutes, _ = divmod(rem, 60)
        parts = []
        if days:
            parts.append(f"{days}d")
        if hours:
            parts.append(f"{hours}h")
        parts.append(f"{minutes}m")
        return " ".join(parts)
    except Exception:
        return "—"


def get_load_average():
    try:
        one, five, fifteen = os.getloadavg()
        return f"{one:.2f}, {five:.2f}, {fifteen:.2f}"
    except Exception:
        return "—"


def get_memory_usage():
    try:
        info = {}
        with open("/proc/meminfo") as f:
            for line in f:
                key, val = line.split(":")
                info[key.strip()] = int(val.strip().split()[0])  # kB
        total = info.get("MemTotal", 0)
        available = info.get("MemAvailable", 0)
        used = total - available
        pct = round((used / total) * 100, 1) if total else 0
        return {"pct": pct, "used_mb": used // 1024, "total_mb": total // 1024}
    except Exception:
        return {"pct": None, "used_mb": 0, "total_mb": 0}


def get_disk_usage():
    try:
        import shutil
        total, used, free = shutil.disk_usage("/")
        pct = round((used / total) * 100, 1) if total else 0
        return {"pct": pct, "used_gb": round(used / (1024 ** 3), 1), "total_gb": round(total / (1024 ** 3), 1)}
    except Exception:
        return {"pct": None, "used_gb": 0, "total_gb": 0}


@app.route("/")
@login_required
def index():
    today_start = datetime.utcnow().replace(hour=0, minute=0, second=0, microsecond=0)
    week_start = datetime.utcnow() - timedelta(days=7)

    conn = portal_db()
    with conn.cursor() as cur:
        cur.execute("SELECT COUNT(*) c FROM vouchers WHERE status='active'")
        active_vouchers = cur.fetchone()["c"]
        cur.execute("SELECT COUNT(*) c FROM vouchers WHERE status='pending'")
        pending_vouchers = cur.fetchone()["c"]
        cur.execute("SELECT COUNT(*) c FROM mac_devices WHERE status='active'")
        active_macs = cur.fetchone()["c"]
        cur.execute("SELECT COUNT(*) c FROM plans WHERE status='active'")
        active_plans = cur.fetchone()["c"]
        cur.execute("SELECT COUNT(*) c FROM radius_users WHERE status='active'")
        active_password_users = cur.fetchone()["c"]
        cur.execute(
            "SELECT COUNT(*) c FROM auth_log WHERE session_start >= %s",
            (datetime.utcnow() - timedelta(days=1),),
        )
        sessions_24h = cur.fetchone()["c"]
        cur.execute(
            """SELECT SUM(COALESCE(upload_bytes,0)) up, SUM(COALESCE(download_bytes,0)) down
               FROM auth_log WHERE session_start >= %s""",
            (today_start,),
        )
        today = cur.fetchone()
        cur.execute(
            """SELECT SUM(COALESCE(upload_bytes,0)) up, SUM(COALESCE(download_bytes,0)) down
               FROM auth_log WHERE session_start >= %s""",
            (week_start,),
        )
        week = cur.fetchone()
    conn.close()

    live = get_live_clients()
    total_logins = active_password_users + active_vouchers + active_macs

    return render_template(
        "index.html",
        active_vouchers=active_vouchers,
        pending_vouchers=pending_vouchers,
        active_macs=active_macs,
        active_plans=active_plans,
        total_logins=total_logins,
        sessions_24h=sessions_24h,
        live_count=len(live),
        internet=check_internet(),
        services={
            "openNDS": check_service("opennds"),
            "FreeRADIUS": check_service("freeradius"),
            "MariaDB": check_service("mariadb"),
            "Portal FAS": check_service("portal-fas"),
        },
        uptime=get_uptime(),
        load_avg=get_load_average(),
        memory=get_memory_usage(),
        disk=get_disk_usage(),
        today_up=today["up"] or 0,
        today_down=today["down"] or 0,
        week_up=week["up"] or 0,
        week_down=week["down"] or 0,
    )


# ------------------------------------------------------------- live view --

def get_live_clients():
    """Query openNDS's live client list via ndsctl json."""
    try:
        out = subprocess.run(["sudo", "-n", NDSCTL_BIN, "json"], capture_output=True, timeout=5, text=True)
        data = json.loads(out.stdout)
        return data.get("clients", {})
    except Exception:
        return {}


@app.route("/sessions")
@login_required
def sessions():
    live = get_live_clients()
    macs = list(live.keys())
    identifiers = {}
    if macs:
        conn = portal_db()
        with conn.cursor() as cur:
            fmt_macs = ",".join(["%s"] * len(macs))
            cur.execute(
                f"""SELECT client_mac, identifier, auth_method FROM auth_log
                    WHERE client_mac IN ({fmt_macs}) AND session_end IS NULL
                    ORDER BY id DESC""",
                macs,
            )
            for row in cur.fetchall():
                identifiers.setdefault(row["client_mac"], row)
        conn.close()
    for mac, c in live.items():
        info = identifiers.get(mac, {})
        c["identifier"] = info.get("identifier", "—")
        c["auth_method"] = info.get("auth_method", "—")
    return render_template("sessions.html", clients=live)


@app.route("/sessions/kick/<mac>", methods=["POST"])
@login_required
def kick_session(mac):
    try:
        subprocess.run(["sudo", "-n", NDSCTL_BIN, "deauth", mac], timeout=5)
        flash(f"Deauthenticated {mac}", "success")
    except Exception as e:
        flash(f"Failed to deauth {mac}: {e}", "error")
    return redirect(url_for("sessions"))


# ------------------------------------------------------------------ plans --

def get_active_plans():
    conn = portal_db()
    with conn.cursor() as cur:
        cur.execute("SELECT * FROM plans WHERE status='active' ORDER BY name")
        rows = cur.fetchall()
    conn.close()
    return rows


QUOTA_UNIT_MULTIPLIERS = {"KB": 1, "MB": 1024, "GB": 1024 * 1024}


def quota_to_kb(value_field, unit_field):
    """Read a quota value+unit pair from the form and convert to KB for storage."""
    raw = request.form.get(value_field)
    if raw in (None, ""):
        return None
    unit = request.form.get(unit_field, "KB")
    multiplier = QUOTA_UNIT_MULTIPLIERS.get(unit, 1)
    return int(float(raw) * multiplier)


def format_kb(kb):
    """Human-readable KB/MB/GB for display, picking the largest clean unit."""
    if kb is None:
        return "—"
    kb = int(kb)
    if kb >= 1024 * 1024 and kb % (1024 * 1024) == 0:
        return f"{kb // (1024 * 1024)} GB"
    if kb >= 1024 * 1024:
        return f"{kb / (1024 * 1024):.2f} GB"
    if kb >= 1024 and kb % 1024 == 0:
        return f"{kb // 1024} MB"
    if kb >= 1024:
        return f"{kb / 1024:.2f} MB"
    return f"{kb} KB"


app.jinja_env.filters["fmtkb"] = format_kb

RATE_UNIT_MULTIPLIERS = {"Kbit/s": 1, "Mbit/s": 1000}


def rate_to_kbits(value_field, unit_field):
    """Read a rate value+unit pair (Kbit/s, Mbit/s) from the form and
    convert to kbits/s for storage - matches what ndsctl/tc natively use,
    and what speed-test tools display, with no bit/byte conversion needed."""
    raw = request.form.get(value_field)
    if raw in (None, ""):
        return None
    unit = request.form.get(unit_field, "Mbit/s")
    multiplier = RATE_UNIT_MULTIPLIERS.get(unit, 1000)
    return int(float(raw) * multiplier)


def format_kbits(kbits):
    """Human-readable Kbps/Mbps for display - same units a speed test shows."""
    if kbits is None:
        return "—"
    kbits = int(kbits)
    if kbits >= 1000 and kbits % 1000 == 0:
        return f"{kbits // 1000} Mbps"
    if kbits >= 1000:
        return f"{kbits / 1000:.2f} Mbps"
    return f"{kbits} Kbps"


app.jinja_env.filters["fmtkbits"] = format_kbits


def format_bytes(b):
    """Human-readable B/KB/MB/GB for raw byte counts (ndsctl json, auth_log)."""
    if b is None:
        return "0 B"
    b = int(b)
    if b >= 1024 ** 3:
        return f"{b / 1024 ** 3:.2f} GB"
    if b >= 1024 ** 2:
        return f"{b / 1024 ** 2:.2f} MB"
    if b >= 1024:
        return f"{b / 1024:.2f} KB"
    return f"{b} B"


app.jinja_env.filters["fmtbytes"] = format_bytes

TERMINATE_CAUSE_LABELS = {
    "client_deauth": "User disconnected",
    "idle_deauth": "Idle timeout",
    "timeout_deauth": "Session timeout",
    "ndsctl_deauth": "Admin kickout",
    "downquota_deauth": "Download quota exceeded",
    "upquota_deauth": "Upload quota exceeded",
    "downrate_deauth": "Download rate exceeded",
    "uprate_deauth": "Upload rate exceeded",
    "shutdown_deauth": "Gateway restarted",
}


def format_terminate_cause(cause):
    if not cause:
        return "—"
    return TERMINATE_CAUSE_LABELS.get(cause, cause)


app.jinja_env.filters["fmtcause"] = format_terminate_cause


def format_duration(seconds):
    if not seconds:
        return "—"
    seconds = int(seconds)
    hours, remainder = divmod(seconds, 3600)
    minutes, secs = divmod(remainder, 60)
    if hours:
        return f"{hours}h {minutes}m"
    if minutes:
        return f"{minutes}m {secs}s"
    return f"{secs}s"


app.jinja_env.filters["fmtduration"] = format_duration


@app.route("/plans")
@login_required
def plans():
    conn = portal_db()
    with conn.cursor() as cur:
        cur.execute("SELECT * FROM plans ORDER BY status DESC, name")
        rows = cur.fetchall()
    conn.close()
    return render_template("plans.html", plans=rows)


@app.route("/plans/create-page")
@login_required
def plan_create_page():
    return render_template("plan_create.html")


@app.route("/plans/create", methods=["POST"])
@login_required
def create_plan():
    name = request.form.get("name", "").strip()
    if not name:
        flash("Plan name is required", "error")
        return redirect(url_for("plans"))

    description = request.form.get("description") or None
    session_minutes = request.form.get("session_minutes") or None
    upload_kbits = rate_to_kbits("upload_rate_value", "upload_rate_unit")
    download_kbits = rate_to_kbits("download_rate_value", "download_rate_unit")
    upload_quota_kb = quota_to_kb("upload_quota_value", "upload_quota_unit")
    download_quota_kb = quota_to_kb("download_quota_value", "download_quota_unit")
    price = request.form.get("price") or None
    simultaneous_use = int(
        request.form.get("simultaneous_use", 1)
    )

    if simultaneous_use < 1:
        simultaneous_use = 1

    conn = portal_db()
    with conn.cursor() as cur:
        cur.execute(
            """INSERT INTO plans
               (name, description, session_minutes, upload_kbits, download_kbits,
                upload_quota_kb, download_quota_kb, price, simultaneous_use)
               VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s)""",
            (name, description, session_minutes, upload_kbits, download_kbits,
             upload_quota_kb, download_quota_kb, price, simultaneous_use),
        )
    conn.close()
    flash(f"Plan '{name}' created", "success")
    return redirect(url_for("plans"))


@app.route("/plans/<int:plan_id>/disable", methods=["POST"])
@login_required
def disable_plan(plan_id):
    conn = portal_db()
    with conn.cursor() as cur:
        cur.execute("UPDATE plans SET status='disabled' WHERE id=%s", (plan_id,))
    conn.close()
    flash("Plan disabled", "success")
    return redirect(url_for("plans"))


@app.route("/plans/<int:plan_id>/enable", methods=["POST"])
@login_required
def enable_plan(plan_id):
    conn = portal_db()
    with conn.cursor() as cur:
        cur.execute("UPDATE plans SET status='active' WHERE id=%s", (plan_id,))
    conn.close()
    flash("Plan enabled", "success")
    return redirect(url_for("plans"))


@app.route("/plans/<int:plan_id>/delete", methods=["POST"])
@login_required
def delete_plan(plan_id):
    conn = portal_db()
    with conn.cursor() as cur:
        cur.execute("DELETE FROM plans WHERE id=%s", (plan_id,))
    conn.close()
    flash("Plan deleted", "success")
    return redirect(url_for("plans"))


def kb_to_value_unit(kb):
    """Reverse of quota_to_kb - pick the largest clean unit for form pre-fill."""
    if kb is None:
        return None, "MB"
    kb = int(kb)
    if kb >= 1024 * 1024 and kb % (1024 * 1024) == 0:
        return kb // (1024 * 1024), "GB"
    if kb >= 1024 and kb % 1024 == 0:
        return kb // 1024, "MB"
    return kb, "KB"


def kbits_to_value_unit(kbits):
    """Reverse of rate_to_kbits - pick the largest clean unit for form
    pre-fill. No conversion needed now - stored value IS kbit/s already."""
    if kbits is None:
        return None, "Mbit/s"
    kbits = int(kbits)
    if kbits >= 1000 and kbits % 1000 == 0:
        return kbits // 1000, "Mbit/s"
    return kbits, "Kbit/s"


@app.route("/plans/<int:plan_id>/edit", methods=["GET"])
@login_required
def edit_plan_form(plan_id):
    conn = portal_db()
    with conn.cursor() as cur:
        cur.execute("SELECT * FROM plans WHERE id=%s", (plan_id,))
        plan = cur.fetchone()
    conn.close()
    if not plan:
        flash("Plan not found", "error")
        return redirect(url_for("plans"))

    dl_rate_val, dl_rate_unit = kbits_to_value_unit(plan["download_kbits"])
    ul_rate_val, ul_rate_unit = kbits_to_value_unit(plan["upload_kbits"])
    dl_quota_val, dl_quota_unit = kb_to_value_unit(plan["download_quota_kb"])
    ul_quota_val, ul_quota_unit = kb_to_value_unit(plan["upload_quota_kb"])

    return render_template(
        "plan_edit.html", plan=plan,
        dl_rate_val=dl_rate_val, dl_rate_unit=dl_rate_unit,
        ul_rate_val=ul_rate_val, ul_rate_unit=ul_rate_unit,
        dl_quota_val=dl_quota_val, dl_quota_unit=dl_quota_unit,
        ul_quota_val=ul_quota_val, ul_quota_unit=ul_quota_unit,
    )


@app.route("/plans/<int:plan_id>/edit", methods=["POST"])
@login_required
def edit_plan(plan_id):
    name = request.form.get("name", "").strip()
    if not name:
        flash("Plan name is required", "error")
        return redirect(url_for("edit_plan_form", plan_id=plan_id))

    description = request.form.get("description") or None
    session_minutes = request.form.get("session_minutes") or None
    upload_kbits = rate_to_kbits("upload_rate_value", "upload_rate_unit")
    download_kbits = rate_to_kbits("download_rate_value", "download_rate_unit")
    upload_quota_kb = quota_to_kb("upload_quota_value", "upload_quota_unit")
    download_quota_kb = quota_to_kb("download_quota_value", "download_quota_unit")
    price = request.form.get("price") or None
    simultaneous_use = int(request.form.get("simultaneous_use", 1))
    if simultaneous_use < 1:
       simultaneous_use = 1

    conn = portal_db()
    with conn.cursor() as cur:
        cur.execute(
            """UPDATE plans SET
               name=%s, description=%s, session_minutes=%s, upload_kbits=%s,
               download_kbits=%s, upload_quota_kb=%s, download_quota_kb=%s, price=%s, simultaneous_use=%s
               WHERE id=%s""",
            (name, description, session_minutes, upload_kbits, download_kbits,
             upload_quota_kb, download_quota_kb, price, simultaneous_use, plan_id,),
        )
    conn.close()
    flash(f"Plan '{name}' updated", "success")
    return redirect(url_for("plans"))


# --------------------------------------------------------------- vouchers --

def generate_code(length=8):
    alphabet = string.ascii_uppercase + string.digits
    alphabet = alphabet.replace("0", "").replace("O", "").replace("1", "").replace("I", "")
    return "".join(random.choice(alphabet) for _ in range(length))


@app.route("/vouchers")
@login_required
def vouchers():
    q = request.args.get("q", "").strip()
    page = request.args.get("page", 1, type=int)
    if page < 1:
        page = 1
    per_page = 10

    where_clause = ""
    params = []
    if q:
        where_clause = "WHERE v.code LIKE %s OR v.batch_label LIKE %s"
        like = f"%{q}%"
        params = [like, like]

    conn = portal_db()
    with conn.cursor() as cur:
        cur.execute(f"SELECT COUNT(*) c FROM vouchers v {where_clause}", params)
        total = cur.fetchone()["c"]
        total_pages = max(1, (total + per_page - 1) // per_page)
        page = min(page, total_pages)
        offset = (page - 1) * per_page

        cur.execute(
            f"""SELECT v.*, p.name AS plan_name FROM vouchers v
                LEFT JOIN plans p ON p.id = v.plan_id
                {where_clause}
                ORDER BY v.created_at DESC LIMIT %s OFFSET %s""",
            params + [per_page, offset],
        )
        rows = cur.fetchall()
    conn.close()
    return render_template(
        "vouchers.html", vouchers=rows, plans=get_active_plans(),
        q=q, page=page, total_pages=total_pages, total=total,
    )


@app.route("/vouchers/create-page")
@login_required
def voucher_create_page():
    return render_template("voucher_create.html", plans=get_active_plans())


@app.route("/vouchers/issue-page")
@login_required
def voucher_issue_page():
    conn = portal_db()
    with conn.cursor() as cur:
        cur.execute(
            """SELECT v.*, p.name AS plan_name FROM vouchers v
               LEFT JOIN plans p ON p.id = v.plan_id
               WHERE v.status='pending'
               ORDER BY v.created_at DESC"""
        )
        rows = cur.fetchall()
    conn.close()
    return render_template("voucher_issue.html", vouchers=rows)


@app.route("/vouchers/create", methods=["POST"])
@login_required
def create_vouchers():
    count = int(request.form.get("count", 1))
    plan_id = request.form.get("plan_id") or None

    if not plan_id:
        flash("A plan is required", "error")
        return redirect(url_for("voucher_create_page"))

    conn = portal_db()
    with conn.cursor() as cur:
        cur.execute("SELECT * FROM plans WHERE id=%s", (plan_id,))
        plan = cur.fetchone()
    conn.close()
    if not plan:
        flash("Plan not found", "error")
        return redirect(url_for("voucher_create_page"))

    session_minutes = plan.get("session_minutes") or 60
    upload_kbits = plan.get("upload_kbits")
    download_kbits = plan.get("download_kbits")
    upload_quota_kb = plan.get("upload_quota_kb")
    download_quota_kb = plan.get("download_quota_kb")

    max_uses = int(request.form.get("max_uses", 1))
    valid_days = request.form.get("valid_days") or None
    batch_label = request.form.get("batch_label") or None

    valid_until = None
    if valid_days:
        valid_until = datetime.utcnow() + timedelta(days=int(valid_days))

    conn = portal_db()
    with conn.cursor() as cur:
        for _ in range(count):
            code = generate_code()
            cur.execute(
                """INSERT INTO vouchers
                   (plan_id, code, session_minutes, upload_kbits, download_kbits,
                    upload_quota_kb, download_quota_kb, max_uses,
                    valid_until, batch_label, created_by, status)
                   VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,'pending')""",
                (plan_id, code, session_minutes, upload_kbits, download_kbits,
                 upload_quota_kb, download_quota_kb, max_uses,
                 valid_until, batch_label, session.get("admin_username")),
            )
            # No radcheck row yet - this voucher isn't usable until an
            # admin explicitly issues it (see issue_voucher below).
    conn.close()
    flash(f"Created {count} voucher(s) as pending - issue them to activate", "success")
    return redirect(url_for("vouchers"))


@app.route("/vouchers/issue/<code>", methods=["POST"])
@login_required
def issue_voucher(code):
    conn = portal_db()
    with conn.cursor() as cur:
        cur.execute("SELECT status FROM vouchers WHERE code=%s", (code,))
        v = cur.fetchone()
        if not v or v["status"] != "pending":
            conn.close()
            flash("Only pending vouchers can be issued", "error")
            return redirect(url_for("vouchers"))
        cur.execute("UPDATE vouchers SET status='active' WHERE code=%s", (code,))
    conn.close()
    upsert_radcheck_password(code, code)
    flash(f"Voucher {code} issued and active", "success")
    return redirect(url_for("vouchers"))


@app.route("/vouchers/<int:voucher_id>/disable", methods=["POST"])
@login_required
def disable_voucher(voucher_id):
    conn = portal_db()
    with conn.cursor() as cur:
        cur.execute("SELECT code FROM vouchers WHERE id=%s", (voucher_id,))
        row = cur.fetchone()
        cur.execute("UPDATE vouchers SET status='disabled' WHERE id=%s", (voucher_id,))
    conn.close()
    if row:
        rconn = radius_db()
        with rconn.cursor() as rcur:
            rcur.execute("DELETE FROM radcheck WHERE username=%s", (row["code"],))
        rconn.close()
    flash("Voucher disabled", "success")
    return redirect(url_for("vouchers"))


# ------------------------------------------------------------- mac devices --

@app.route("/mac-devices")
@login_required
def mac_devices():
    conn = portal_db()
    with conn.cursor() as cur:
        cur.execute(
            """SELECT d.*, p.name AS plan_name FROM mac_devices d
               LEFT JOIN plans p ON p.id = d.plan_id
               ORDER BY d.created_at DESC"""
        )
        rows = cur.fetchall()
    conn.close()
    return render_template("mac_devices.html", devices=rows, plans=get_active_plans())


@app.route("/mac-devices/create-page")
@login_required
def mac_create_page():
    return render_template("mac_create.html", plans=get_active_plans())


@app.route("/mac-devices/create", methods=["POST"])
@login_required
def create_mac_device():
    mac = request.form.get("mac_address", "").strip().lower()
    if not mac:
        flash("MAC address is required", "error")
        return redirect(url_for("mac_create_page"))

    plan_id = request.form.get("plan_id") or None
    if not plan_id:
        flash("A plan is required", "error")
        return redirect(url_for("mac_create_page"))

    label = request.form.get("label") or None
    owner = request.form.get("owner_name") or None
    expires_days = request.form.get("expires_days") or None

    conn = portal_db()
    with conn.cursor() as cur:
        cur.execute("SELECT * FROM plans WHERE id=%s", (plan_id,))
        plan = cur.fetchone()
    conn.close()
    if not plan:
        flash("Plan not found", "error")
        return redirect(url_for("mac_create_page"))

    session_minutes = plan.get("session_minutes")
    upload_kbits = plan.get("upload_kbits")
    download_kbits = plan.get("download_kbits")

    expires_at = None
    if expires_days:
        expires_at = datetime.utcnow() + timedelta(days=int(expires_days))

    conn = portal_db()
    with conn.cursor() as cur:
        cur.execute(
            """INSERT INTO mac_devices
               (plan_id, mac_address, label, owner_name, session_minutes,
                upload_kbits, download_kbits, expires_at, created_by)
               VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s)
               ON DUPLICATE KEY UPDATE plan_id=VALUES(plan_id), label=VALUES(label),
                   owner_name=VALUES(owner_name), session_minutes=VALUES(session_minutes),
                   upload_kbits=VALUES(upload_kbits), download_kbits=VALUES(download_kbits),
                   expires_at=VALUES(expires_at), status='active'""",
            (plan_id, mac, label, owner, session_minutes, upload_kbits,
             download_kbits, expires_at, session.get("admin_username")),
        )
    conn.close()

    # Mirror into radcheck so RADIUS can authenticate this device
    # (username=mac, password=mac - standard MAC-auth-bypass convention).
    rconn = radius_db()
    with rconn.cursor() as rcur:
        rcur.execute(
            """INSERT INTO radcheck (username, attribute, op, value) VALUES (%s,'Cleartext-Password',':=',%s)
               ON DUPLICATE KEY UPDATE value=VALUES(value)""",
            (mac, mac),
        )
    rconn.close()

    flash(f"MAC device {mac} added/updated", "success")
    return redirect(url_for("mac_devices"))


@app.route("/mac-devices/<int:device_id>/disable", methods=["POST"])
@login_required
def disable_mac_device(device_id):
    conn = portal_db()
    with conn.cursor() as cur:
        cur.execute("SELECT mac_address FROM mac_devices WHERE id=%s", (device_id,))
        row = cur.fetchone()
        cur.execute("UPDATE mac_devices SET status='disabled' WHERE id=%s", (device_id,))
    conn.close()
    if row:
        rconn = radius_db()
        with rconn.cursor() as rcur:
            rcur.execute("DELETE FROM radcheck WHERE username=%s", (row["mac_address"],))
        rconn.close()
    flash("Device disabled", "success")
    return redirect(url_for("mac_devices"))


# ------------------------------------------------------------ radius users --

@app.route("/users")
@login_required
def users():
    conn = radius_db()
    with conn.cursor() as cur:
        cur.execute(
            """SELECT username, value AS password_attr
               FROM radcheck WHERE attribute IN ('Cleartext-Password','NT-Password')
               ORDER BY username"""
        )
        rows = cur.fetchall()
    conn.close()
    return render_template("users.html", users=rows)


@app.route("/users/create", methods=["POST"])
@login_required
def create_user():
    username = request.form.get("username", "").strip()
    password = request.form.get("password", "")
    if not username or not password:
        flash("Username and password required", "error")
        return redirect(url_for("users"))

    conn = radius_db()
    with conn.cursor() as cur:
        cur.execute(
            "INSERT INTO radcheck (username, attribute, op, value) VALUES (%s,'Cleartext-Password',':=',%s)",
            (username, password),
        )
    conn.close()
    flash(f"User {username} created", "success")
    return redirect(url_for("users"))


@app.route("/users/<username>/delete", methods=["POST"])
@login_required
def delete_user(username):
    conn = radius_db()
    with conn.cursor() as cur:
        cur.execute("DELETE FROM radcheck WHERE username=%s", (username,))
        cur.execute("DELETE FROM radusergroup WHERE username=%s", (username,))
    conn.close()
    flash(f"User {username} deleted", "success")
    return redirect(url_for("users"))


# ------------------------------------------------------------------ reports --

@app.route("/reports")
@login_required
def reports():
    since = datetime.utcnow() - timedelta(days=1)
    conn = portal_db()
    with conn.cursor() as cur:
        cur.execute(
            """SELECT auth_method, COUNT(*) AS count,
                      SUM(COALESCE(upload_bytes,0)) AS up, SUM(COALESCE(download_bytes,0)) AS down
               FROM auth_log
               WHERE session_start >= %s
               GROUP BY auth_method""",
            (since,),
        )
        by_method = cur.fetchall()
        cur.execute(
            "SELECT * FROM auth_log WHERE session_start >= %s ORDER BY session_start DESC LIMIT 200",
            (since,),
        )
        recent = cur.fetchall()
    conn.close()
    return render_template("reports.html", by_method=by_method, recent=recent)


@app.route("/reports/online-users")
@login_required
def report_online_users():
    live = get_live_clients()
    macs = list(live.keys())
    identifiers = {}
    if macs:
        conn = portal_db()
        with conn.cursor() as cur:
            fmt_macs = ",".join(["%s"] * len(macs))
            cur.execute(
                f"""SELECT client_mac, identifier, auth_method FROM auth_log
                    WHERE client_mac IN ({fmt_macs}) AND session_end IS NULL
                    ORDER BY id DESC""",
                macs,
            )
            for row in cur.fetchall():
                identifiers.setdefault(row["client_mac"], row)
        conn.close()
    rows = []
    for mac, c in live.items():
        info = identifiers.get(mac, {})
        rows.append({
            "mac": mac, "ip": c.get("ip"), "state": c.get("state"),
            "identifier": info.get("identifier", "—"),
            "auth_method": info.get("auth_method", "—"),
            "download": c.get("download_this_session", 0),
            "upload": c.get("upload_this_session", 0),
        })
    return render_template("report_online_users.html", rows=rows)


@app.route("/reports/usage")
@login_required
def report_usage():
    conn = portal_db()

    with conn.cursor() as cur:
        cur.execute(
            """SELECT username,
                      SUM(COALESCE(acctoutputoctets,0)) AS total_up,
                      SUM(COALESCE(acctinputoctets,0)) AS total_down
               FROM radius.radacct
               GROUP BY username
               ORDER BY (
                   SUM(COALESCE(acctinputoctets,0))
                   + SUM(COALESCE(acctoutputoctets,0))
               ) DESC"""
        )

        rows = cur.fetchall()

    conn.close()

    for r in rows:
        r["total_up_mb"] = round(
            (r["total_up"] or 0) / (1024 * 1024), 2
        )

        r["total_down_mb"] = round(
            (r["total_down"] or 0) / (1024 * 1024), 2
        )

        r["total_mb"] = round(
            (
                (r["total_up"] or 0)
                + (r["total_down"] or 0)
            ) / (1024 * 1024),
            2
        )

    return render_template("report_usage.html", rows=rows)


@app.route("/reports/user-accounting")
@login_required
def report_user_accounting():
    q = request.args.get("q", "").strip()
    rows = []
    if q:
        conn = portal_db()
        with conn.cursor() as cur:
            cur.execute(
                """SELECT username, framedipaddress, callingstationid,
                          acctstarttime, acctstoptime, acctsessiontime,
                          acctinputoctets, acctoutputoctets, acctterminatecause, nasipaddress
                   FROM radius.radacct
                   WHERE username = %s
                   ORDER BY acctstarttime DESC
                   LIMIT 200""",
                (q,),
            )
            rows = cur.fetchall()
        conn.close()
    return render_template("report_user_accounting.html", rows=rows, q=q)


@app.route("/reports/date-accounting")
@login_required
def report_date_accounting():
    date_from = request.args.get("from", "")
    date_to = request.args.get("to", "")
    username = request.args.get("username", "").strip()
    rows = []
    if date_from and date_to:
        where = "WHERE acctstarttime >= %s AND acctstarttime < %s"
        params = [date_from, date_to + " 23:59:59"]
        if username:
            where += " AND username = %s"
            params.append(username)
        conn = portal_db()
        with conn.cursor() as cur:
            cur.execute(
                f"""SELECT username, framedipaddress, callingstationid,
                           acctstarttime, acctstoptime, acctsessiontime,
                           acctinputoctets, acctoutputoctets, acctterminatecause, nasipaddress
                    FROM radius.radacct
                    {where}
                    ORDER BY acctstarttime DESC
                    LIMIT 500""",
                params,
            )
            rows = cur.fetchall()
        conn.close()
    return render_template("report_date_accounting.html", rows=rows,
                            date_from=date_from, date_to=date_to, username=username)


@app.route("/reports/top-users")
@login_required
def report_top_users():
    date_from = request.args.get("from", "")
    date_to = request.args.get("to", "")
    metric = request.args.get("metric", "bandwidth")
    limit = request.args.get("limit", 10, type=int)
    rows = []
    if date_from and date_to:
        order_col = "total_time" if metric == "time" else "total_bytes"
        conn = portal_db()
        with conn.cursor() as cur:
            cur.execute(
                f"""SELECT username,
                           SUM(COALESCE(acctsessiontime,0)) AS total_time,
                           SUM(COALESCE(acctinputoctets,0) + COALESCE(acctoutputoctets,0)) AS total_bytes
                    FROM radius.radacct
                    WHERE acctstarttime >= %s AND acctstarttime < %s
                    GROUP BY username
                    ORDER BY {order_col} DESC
                    LIMIT %s""",
                (date_from, date_to + " 23:59:59", limit),
            )
            rows = cur.fetchall()
        conn.close()
        for r in rows:
            r["total_mb"] = round((r["total_bytes"] or 0) / (1024 * 1024), 2)
    return render_template("report_top_users.html", rows=rows,
                            date_from=date_from, date_to=date_to, metric=metric, limit=limit)


# ------------------------------------------------------------ create login --

@app.route("/create-login")
@login_required
def create_login():
    return render_template("create_login.html", plans=get_active_plans())


def upsert_radcheck_password(username, password):
    """radcheck has no unique constraint on username (FreeRADIUS allows
    multiple check-item rows per user by design), so ON DUPLICATE KEY
    UPDATE doesn't work as an upsert here - it just never fires since `id`
    never collides. Delete then insert instead, every time."""
    rconn = radius_db()
    with rconn.cursor() as rcur:
        rcur.execute("DELETE FROM radcheck WHERE username=%s AND attribute='Cleartext-Password'", (username,))
        rcur.execute(
            "INSERT INTO radcheck (username, attribute, op, value) VALUES (%s,'Cleartext-Password',':=',%s)",
            (username, password),
        )
    rconn.close()


@app.route("/create-login/password", methods=["POST"])
@login_required
def create_login_password():
    username = request.form.get("username", "").strip()
    password = request.form.get("password", "")
    plan_id = request.form.get("plan_id") or None

    if not username or not password:
        flash("Username and password required", "error")
        return redirect(url_for("create_login"))
    if not plan_id:
        flash("A plan is required", "error")
        return redirect(url_for("create_login"))

    upsert_radcheck_password(username, password)

    conn = portal_db()
    with conn.cursor() as cur:
        cur.execute(
            """INSERT INTO radius_users (plan_id, username, password, created_by) VALUES (%s,%s,%s,%s)
               ON DUPLICATE KEY UPDATE plan_id=VALUES(plan_id), password=VALUES(password), status='active'""",
            (plan_id, username, password, session.get("admin_username")),
        )
    conn.close()

    flash(f"User {username} created", "success")
    return redirect(url_for("all_users"))


@app.route("/create-login/voucher", methods=["POST"])
@login_required
def create_login_voucher():
    plan_id = request.form.get("plan_id") or None
    if not plan_id:
        flash("A plan is required", "error")
        return redirect(url_for("create_login"))

    conn = portal_db()
    with conn.cursor() as cur:
        cur.execute("SELECT * FROM plans WHERE id=%s", (plan_id,))
        plan = cur.fetchone()
    conn.close()
    if not plan:
        flash("Plan not found", "error")
        return redirect(url_for("create_login"))

    count = int(request.form.get("count", 1))
    max_uses = int(request.form.get("max_uses", 1))
    valid_days = request.form.get("valid_days") or None
    batch_label = request.form.get("batch_label") or None

    valid_until = None
    if valid_days:
        valid_until = datetime.utcnow() + timedelta(days=int(valid_days))

    conn = portal_db()
    with conn.cursor() as cur:
        for _ in range(count):
            code = generate_code()
            cur.execute(
                """INSERT INTO vouchers
                   (plan_id, code, session_minutes, upload_kbits, download_kbits,
                    upload_quota_kb, download_quota_kb, max_uses,
                    valid_until, batch_label, created_by)
                   VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)""",
                (plan_id, code, plan["session_minutes"] or 60, plan["upload_kbits"], plan["download_kbits"],
                 plan["upload_quota_kb"], plan["download_quota_kb"], max_uses,
                 valid_until, batch_label, session.get("admin_username")),
            )
            upsert_radcheck_password(code, code)
    conn.close()
    flash(f"Created {count} voucher(s)", "success")
    return redirect(url_for("all_users"))


@app.route("/create-login/mac", methods=["POST"])
@login_required
def create_login_mac():
    plan_id = request.form.get("plan_id") or None
    if not plan_id:
        flash("A plan is required", "error")
        return redirect(url_for("create_login"))

    conn = portal_db()
    with conn.cursor() as cur:
        cur.execute("SELECT * FROM plans WHERE id=%s", (plan_id,))
        plan = cur.fetchone()
    conn.close()
    if not plan:
        flash("Plan not found", "error")
        return redirect(url_for("create_login"))

    mac = request.form.get("mac_address", "").strip().lower()
    if not mac:
        flash("MAC address is required", "error")
        return redirect(url_for("create_login"))

    label = request.form.get("label") or None
    owner = request.form.get("owner_name") or None
    expires_days = request.form.get("expires_days") or None
    expires_at = None
    if expires_days:
        expires_at = datetime.utcnow() + timedelta(days=int(expires_days))

    conn = portal_db()
    with conn.cursor() as cur:
        cur.execute(
            """INSERT INTO mac_devices
               (plan_id, mac_address, label, owner_name, session_minutes,
                upload_kbits, download_kbits, expires_at, created_by)
               VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s)
               ON DUPLICATE KEY UPDATE plan_id=VALUES(plan_id), label=VALUES(label),
                   owner_name=VALUES(owner_name), session_minutes=VALUES(session_minutes),
                   upload_kbits=VALUES(upload_kbits), download_kbits=VALUES(download_kbits),
                   expires_at=VALUES(expires_at), status='active'""",
            (plan_id, mac, label, owner, plan["session_minutes"], plan["upload_kbits"],
             plan["download_kbits"], expires_at, session.get("admin_username")),
        )
    conn.close()

    upsert_radcheck_password(mac, mac)

    flash(f"MAC device {mac} added/updated", "success")
    return redirect(url_for("all_users"))


# ------------------------------------------------------------------ all users --

@app.route("/all-users")
@login_required
def all_users():
    q = request.args.get("q", "").strip()
    type_filter = request.args.get("type", "")
    page = request.args.get("page", 1, type=int)
    if page < 1:
        page = 1
    per_page = 10

    union_sql = """
        SELECT 'password' AS type, ru.username AS identifier, p.name AS plan_name,
               '—' AS detail, ru.status AS status, ru.created_at AS created_at
        FROM radius_users ru LEFT JOIN plans p ON p.id = ru.plan_id
        UNION ALL
        SELECT 'password', rc.username, NULL,
               '—', 'active', NULL
        FROM radius.radcheck rc
        WHERE rc.attribute = 'Cleartext-Password'
          AND rc.username NOT IN (SELECT username FROM radius_users)
          AND rc.username NOT IN (SELECT code FROM vouchers)
          AND rc.username NOT IN (SELECT mac_address FROM mac_devices)
        UNION ALL
        SELECT 'voucher', v.code, p.name,
               CONCAT(v.used_count, '/', v.max_uses, ' used'), v.status, v.created_at
        FROM vouchers v LEFT JOIN plans p ON p.id = v.plan_id
        UNION ALL
        SELECT 'mac', m.mac_address, p.name,
               COALESCE(m.label, '—'), m.status, m.created_at
        FROM mac_devices m LEFT JOIN plans p ON p.id = m.plan_id
    """

    where_parts = []
    params = []
    if type_filter in ("password", "voucher", "mac"):
        where_parts.append("type = %s")
        params.append(type_filter)
    if q:
        where_parts.append("identifier LIKE %s")
        params.append(f"%{q}%")
    where_clause = ("WHERE " + " AND ".join(where_parts)) if where_parts else ""

    conn = portal_db()
    with conn.cursor() as cur:
        cur.execute(f"SELECT COUNT(*) c FROM ({union_sql}) t {where_clause}", params)
        total = cur.fetchone()["c"]
        total_pages = max(1, (total + per_page - 1) // per_page)
        page = min(page, total_pages)
        offset = (page - 1) * per_page

        cur.execute(
            f"SELECT * FROM ({union_sql}) t {where_clause} ORDER BY created_at DESC LIMIT %s OFFSET %s",
            params + [per_page, offset],
        )
        rows = cur.fetchall()
    conn.close()

    return render_template(
        "all_users.html", rows=rows, q=q, type_filter=type_filter,
        page=page, total_pages=total_pages, total=total,
    )


# --- password: edit / enable / disable / delete ---

@app.route("/all-users/edit-password/<username>", methods=["GET"])
@login_required
def edit_password_user_form(username):
    conn = portal_db()
    with conn.cursor() as cur:
        cur.execute("SELECT * FROM radius_users WHERE username=%s", (username,))
        user = cur.fetchone()
    conn.close()
    if not user:
        flash("This account predates plan-binding - set a plan by re-creating it via Create Login, or ask to extend edit support to legacy accounts.", "error")
        return redirect(url_for("all_users"))
    return render_template("edit_password_user.html", user=user, plans=get_active_plans())


@app.route("/all-users/edit-password/<username>", methods=["POST"])
@login_required
def edit_password_user(username):
    plan_id = request.form.get("plan_id") or None
    new_password = request.form.get("password") or None
    if not plan_id:
        flash("A plan is required", "error")
        return redirect(url_for("edit_password_user_form", username=username))

    conn = portal_db()
    with conn.cursor() as cur:
        if new_password:
            cur.execute("UPDATE radius_users SET plan_id=%s, password=%s WHERE username=%s",
                        (plan_id, new_password, username))
        else:
            cur.execute("UPDATE radius_users SET plan_id=%s WHERE username=%s", (plan_id, username))
    conn.close()

    if new_password:
        upsert_radcheck_password(username, new_password)

    flash(f"User {username} updated", "success")
    return redirect(url_for("all_users"))


@app.route("/all-users/disable-password/<username>", methods=["POST"])
@login_required
def disable_password_user(username):
    conn = portal_db()
    with conn.cursor() as cur:
        cur.execute(
            "INSERT INTO radius_users (username, status) VALUES (%s,'disabled') ON DUPLICATE KEY UPDATE status='disabled'",
            (username,),
        )
    conn.close()
    rconn = radius_db()
    with rconn.cursor() as rcur:
        rcur.execute("DELETE FROM radcheck WHERE username=%s", (username,))
    rconn.close()
    flash(f"User {username} disabled", "success")
    return redirect(url_for("all_users"))


@app.route("/all-users/enable-password/<username>", methods=["POST"])
@login_required
def enable_password_user(username):
    conn = portal_db()
    with conn.cursor() as cur:
        cur.execute("SELECT password FROM radius_users WHERE username=%s", (username,))
        row = cur.fetchone()
        cur.execute("UPDATE radius_users SET status='active' WHERE username=%s", (username,))
    conn.close()
    if not row or not row.get("password"):
        flash("No stored password to re-enable with - use Edit to set a new one", "error")
        return redirect(url_for("all_users"))
    upsert_radcheck_password(username, row["password"])
    flash(f"User {username} enabled", "success")
    return redirect(url_for("all_users"))


@app.route("/all-users/delete-password/<username>", methods=["POST"])
@login_required
def delete_password_user(username):
    rconn = radius_db()
    with rconn.cursor() as rcur:
        rcur.execute("DELETE FROM radcheck WHERE username=%s", (username,))
        rcur.execute("DELETE FROM radusergroup WHERE username=%s", (username,))
    rconn.close()
    conn = portal_db()
    with conn.cursor() as cur:
        cur.execute("DELETE FROM radius_users WHERE username=%s", (username,))
    conn.close()
    flash(f"User {username} deleted", "success")
    return redirect(url_for("all_users"))


# --- voucher: edit / enable / disable / delete ---

@app.route("/all-users/edit-voucher/<code>", methods=["GET"])
@login_required
def edit_voucher_form(code):
    conn = portal_db()
    with conn.cursor() as cur:
        cur.execute("SELECT * FROM vouchers WHERE code=%s", (code,))
        voucher = cur.fetchone()
    conn.close()
    if not voucher:
        flash("Voucher not found", "error")
        return redirect(url_for("all_users"))
    return render_template("edit_voucher.html", voucher=voucher, plans=get_active_plans())


@app.route("/all-users/edit-voucher/<code>", methods=["POST"])
@login_required
def edit_voucher(code):
    plan_id = request.form.get("plan_id") or None
    if not plan_id:
        flash("A plan is required", "error")
        return redirect(url_for("edit_voucher_form", code=code))

    max_uses = int(request.form.get("max_uses", 1))
    valid_days = request.form.get("valid_days") or None
    batch_label = request.form.get("batch_label") or None

    conn = portal_db()
    with conn.cursor() as cur:
        if valid_days:
            valid_until = datetime.utcnow() + timedelta(days=int(valid_days))
            cur.execute(
                "UPDATE vouchers SET plan_id=%s, max_uses=%s, valid_until=%s, batch_label=%s WHERE code=%s",
                (plan_id, max_uses, valid_until, batch_label, code),
            )
        else:
            cur.execute(
                "UPDATE vouchers SET plan_id=%s, max_uses=%s, batch_label=%s WHERE code=%s",
                (plan_id, max_uses, batch_label, code),
            )
    conn.close()
    flash(f"Voucher {code} updated", "success")
    return redirect(url_for("all_users"))


@app.route("/all-users/disable-voucher/<code>", methods=["POST"])
@login_required
def disable_voucher_by_code(code):
    conn = portal_db()
    with conn.cursor() as cur:
        cur.execute("UPDATE vouchers SET status='disabled' WHERE code=%s", (code,))
    conn.close()
    rconn = radius_db()
    with rconn.cursor() as rcur:
        rcur.execute("DELETE FROM radcheck WHERE username=%s", (code,))
    rconn.close()
    flash("Voucher disabled", "success")
    return redirect(url_for("all_users"))


@app.route("/all-users/enable-voucher/<code>", methods=["POST"])
@login_required
def enable_voucher_by_code(code):
    conn = portal_db()
    with conn.cursor() as cur:
        cur.execute("SELECT status FROM vouchers WHERE code=%s", (code,))
        v = cur.fetchone()
        if not v or v["status"] == "expired":
            conn.close()
            flash("Can't re-enable a voucher that has reached its max uses", "error")
            return redirect(url_for("all_users"))
        cur.execute("UPDATE vouchers SET status='active' WHERE code=%s", (code,))
    conn.close()
    upsert_radcheck_password(code, code)
    flash(f"Voucher {code} enabled", "success")
    return redirect(url_for("all_users"))


@app.route("/all-users/delete-voucher/<code>", methods=["POST"])
@login_required
def delete_voucher_by_code(code):
    conn = portal_db()
    with conn.cursor() as cur:
        cur.execute("DELETE FROM vouchers WHERE code=%s", (code,))
    conn.close()
    rconn = radius_db()
    with rconn.cursor() as rcur:
        rcur.execute("DELETE FROM radcheck WHERE username=%s", (code,))
    rconn.close()
    flash(f"Voucher {code} deleted", "success")
    return redirect(url_for("all_users"))


# --- mac: edit / enable / disable / delete ---

@app.route("/all-users/edit-mac/<mac>", methods=["GET"])
@login_required
def edit_mac_form(mac):
    conn = portal_db()
    with conn.cursor() as cur:
        cur.execute("SELECT * FROM mac_devices WHERE mac_address=%s", (mac,))
        device = cur.fetchone()
    conn.close()
    if not device:
        flash("Device not found", "error")
        return redirect(url_for("all_users"))
    return render_template("edit_mac.html", device=device, plans=get_active_plans())


@app.route("/all-users/edit-mac/<mac>", methods=["POST"])
@login_required
def edit_mac(mac):
    plan_id = request.form.get("plan_id") or None
    if not plan_id:
        flash("A plan is required", "error")
        return redirect(url_for("edit_mac_form", mac=mac))

    label = request.form.get("label") or None
    owner = request.form.get("owner_name") or None
    expires_days = request.form.get("expires_days") or None

    conn = portal_db()
    with conn.cursor() as cur:
        if expires_days:
            expires_at = datetime.utcnow() + timedelta(days=int(expires_days))
            cur.execute(
                "UPDATE mac_devices SET plan_id=%s, label=%s, owner_name=%s, expires_at=%s WHERE mac_address=%s",
                (plan_id, label, owner, expires_at, mac),
            )
        else:
            cur.execute(
                "UPDATE mac_devices SET plan_id=%s, label=%s, owner_name=%s WHERE mac_address=%s",
                (plan_id, label, owner, mac),
            )
    conn.close()
    flash(f"Device {mac} updated", "success")
    return redirect(url_for("all_users"))


@app.route("/all-users/disable-mac/<mac>", methods=["POST"])
@login_required
def disable_mac_by_address(mac):
    conn = portal_db()
    with conn.cursor() as cur:
        cur.execute("UPDATE mac_devices SET status='disabled' WHERE mac_address=%s", (mac,))
    conn.close()
    rconn = radius_db()
    with rconn.cursor() as rcur:
        rcur.execute("DELETE FROM radcheck WHERE username=%s", (mac,))
    rconn.close()
    flash("Device disabled", "success")
    return redirect(url_for("all_users"))


@app.route("/all-users/enable-mac/<mac>", methods=["POST"])
@login_required
def enable_mac_by_address(mac):
    conn = portal_db()
    with conn.cursor() as cur:
        cur.execute("UPDATE mac_devices SET status='active' WHERE mac_address=%s", (mac,))
    conn.close()
    upsert_radcheck_password(mac, mac)
    flash(f"Device {mac} enabled", "success")
    return redirect(url_for("all_users"))


@app.route("/all-users/delete-mac/<mac>", methods=["POST"])
@login_required
def delete_mac_by_address(mac):
    conn = portal_db()
    with conn.cursor() as cur:
        cur.execute("DELETE FROM mac_devices WHERE mac_address=%s", (mac,))
    conn.close()
    rconn = radius_db()
    with rconn.cursor() as rcur:
        rcur.execute("DELETE FROM radcheck WHERE username=%s", (mac,))
    rconn.close()
    flash(f"Device {mac} deleted", "success")
    return redirect(url_for("all_users"))


# ------------------------------------------------------------------ banners --

@app.route("/banners")
@login_required
def banners():
    conn = portal_db()
    with conn.cursor() as cur:
        cur.execute("SELECT * FROM banners ORDER BY display_order, created_at DESC")
        rows = cur.fetchall()
    conn.close()
    return render_template("banners.html", banners=rows)


@app.route("/banners/create-page")
@login_required
def banner_create_page():
    return render_template("banner_create.html")


BANNER_IMAGES_DIR = "/opt/portal/banner_images"
ALLOWED_BANNER_EXTENSIONS = {"jpg", "jpeg", "png", "gif", "webp"}


def save_banner_image(file_storage):
    """Save an uploaded banner image locally (client has no internet access
    on the splash page, so images MUST be served by the FAS itself, not an
    external URL). Returns the FAS-relative path to store in the DB, or
    None if no valid file was provided."""
    if not file_storage or not file_storage.filename:
        return None
    ext = file_storage.filename.rsplit(".", 1)[-1].lower() if "." in file_storage.filename else ""
    if ext not in ALLOWED_BANNER_EXTENSIONS:
        return None
    os.makedirs(BANNER_IMAGES_DIR, exist_ok=True)
    filename = f"{uuid.uuid4().hex}.{ext}"
    file_storage.save(os.path.join(BANNER_IMAGES_DIR, filename))
    return f"/banner-images/{filename}"


@app.route("/banner-images/<filename>")
def serve_banner_image_dashboard(filename):
    from flask import send_from_directory
    return send_from_directory(BANNER_IMAGES_DIR, filename)


@app.route("/banners/create", methods=["POST"])
@login_required
def create_banner():
    title = request.form.get("title") or None
    link_url = request.form.get("link_url") or None
    display_order = int(request.form.get("display_order", 0))

    image_url = save_banner_image(request.files.get("image_file"))
    if not image_url:
        flash("A valid image file (jpg/png/gif/webp) is required", "error")
        return redirect(url_for("banner_create_page"))

    conn = portal_db()
    with conn.cursor() as cur:
        cur.execute(
            """INSERT INTO banners (title, image_url, link_url, display_order, created_by)
               VALUES (%s,%s,%s,%s,%s)""",
            (title, image_url, link_url, display_order, session.get("admin_username")),
        )
    conn.close()
    flash("Banner created", "success")
    return redirect(url_for("banners"))


@app.route("/banners/<int:banner_id>/edit", methods=["GET"])
@login_required
def edit_banner_form(banner_id):
    conn = portal_db()
    with conn.cursor() as cur:
        cur.execute("SELECT * FROM banners WHERE id=%s", (banner_id,))
        banner = cur.fetchone()
    conn.close()
    if not banner:
        flash("Banner not found", "error")
        return redirect(url_for("banners"))
    return render_template("banner_edit.html", banner=banner)


@app.route("/banners/<int:banner_id>/edit", methods=["POST"])
@login_required
def edit_banner(banner_id):
    title = request.form.get("title") or None
    link_url = request.form.get("link_url") or None
    display_order = int(request.form.get("display_order", 0))

    new_image_url = save_banner_image(request.files.get("image_file"))

    conn = portal_db()
    with conn.cursor() as cur:
        if new_image_url:
            cur.execute(
                "UPDATE banners SET title=%s, image_url=%s, link_url=%s, display_order=%s WHERE id=%s",
                (title, new_image_url, link_url, display_order, banner_id),
            )
        else:
            cur.execute(
                "UPDATE banners SET title=%s, link_url=%s, display_order=%s WHERE id=%s",
                (title, link_url, display_order, banner_id),
            )
    conn.close()
    flash("Banner updated", "success")
    return redirect(url_for("banners"))


@app.route("/banners/<int:banner_id>/disable", methods=["POST"])
@login_required
def disable_banner(banner_id):
    conn = portal_db()
    with conn.cursor() as cur:
        cur.execute("UPDATE banners SET status='disabled' WHERE id=%s", (banner_id,))
    conn.close()
    flash("Banner disabled", "success")
    return redirect(url_for("banners"))


@app.route("/banners/<int:banner_id>/enable", methods=["POST"])
@login_required
def enable_banner(banner_id):
    conn = portal_db()
    with conn.cursor() as cur:
        cur.execute("UPDATE banners SET status='active' WHERE id=%s", (banner_id,))
    conn.close()
    flash("Banner enabled", "success")
    return redirect(url_for("banners"))


@app.route("/banners/<int:banner_id>/delete", methods=["POST"])
@login_required
def delete_banner(banner_id):
    conn = portal_db()
    with conn.cursor() as cur:
        cur.execute("DELETE FROM banners WHERE id=%s", (banner_id,))
    conn.close()
    flash("Banner deleted", "success")
    return redirect(url_for("banners"))


if __name__ == "__main__":
    app.run(host="127.0.0.1", port=8090, debug=False)
