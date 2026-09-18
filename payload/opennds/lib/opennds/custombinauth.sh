#!/bin/sh
# /usr/lib/opennds/custombinauth.sh
#
# Automatically invoked by the default /usr/lib/opennds/binauth_log.sh on
# every auth/deauth event. Do NOT set this as the 'binauth' config option
# directly — that disables openNDS's built-in auth_restore functionality.
#
# Arguments (per openNDS BinAuth spec):
#   auth_client:  $1 method  $2 mac  $3 originurl  $4 useragent  $5 clientip  $6 token  $7 customdata
#   client_auth / client_deauth / idle_deauth / timeout_deauth / downquota_deauth /
#   upquota_deauth / uprate_deauth / downrate_deauth / ndsctl_deauth / shutdown_deauth:
#                 $1 method  $2 mac  $3 incoming_bytes  $4 outgoing_bytes  $5 session_start  $6 session_end

METHOD="$1"
MAC="$2"

echo "$(date '+%F %T') INVOKED args: $*" >> /var/log/custombinauth.log

MYSQL="mysql --defaults-extra-file=/etc/portal/binauth_db.cnf portal -N -B -e"
RADIUS_SECRET_FILE="/etc/portal/binauth_radius_secret"

log() {
      echo "$(date '+%F %T') custombinauth: $*" >> /var/log/custombinauth.log
}

case "$METHOD" in
    client_auth|ndsctl_auth)
        log "client_auth confirmed for $MAC"
        ;;
    client_deauth|idle_deauth|timeout_deauth|downquota_deauth|upquota_deauth|download_quota_deauth|upload_quota_deauth|uprate_deauth|downrate_deauth|ndsctl_deauth|shutdown_deauth)
        INCOMING_BYTES="$3"
        OUTGOING_BYTES="$4"
        SESSION_START="$5"
        SESSION_END="$6"

        MAC_ESC=$(printf '%s' "$MAC" | tr 'A-F' 'a-f')

        # Look up the identifier + Acct-Session-Id the FAS recorded at grant time.
        ROW=$($MYSQL "
            SELECT CONCAT(identifier, '|', COALESCE(acct_session_id,''), '|', COALESCE(client_ip,''))
            FROM auth_log
            WHERE client_mac = '${MAC_ESC}' AND session_end IS NULL
            ORDER BY id DESC LIMIT 1;
        " 2>>/var/log/portal_binauth_errors.log)

        IDENTIFIER=$(printf '%s' "$ROW" | cut -d'|' -f1)
        ACCT_SESSION_ID=$(printf '%s' "$ROW" | cut -d'|' -f2)
        CLIENT_IP=$(printf '%s' "$ROW" | cut -d'|' -f3)

        if [ -n "$CLIENT_IP" ]; then
            /usr/lib/opennds/portal-tc-del.sh "$CLIENT_IP" >>/var/log/portal_binauth_errors.log 2>&1
        fi
                SESSION_TIME=0
        if [ -n "$SESSION_START" ] && [ -n "$SESSION_END" ] && [ "$SESSION_START" -gt 0 ] 2>/dev/null; then
            SESSION_TIME=$((SESSION_END - SESSION_START))
        fi

        case "$METHOD" in
            client_deauth)    TERMINATE_CAUSE="User-Request" ;;
            idle_deauth)      TERMINATE_CAUSE="Idle-Timeout" ;;
            timeout_deauth)   TERMINATE_CAUSE="Session-Timeout" ;;
            ndsctl_deauth)    TERMINATE_CAUSE="Admin-Reset" ;;
            downquota_deauth|upquota_deauth|download_quota_deauth|upload_quota_deauth|downrate_deauth|uprate_deauth)
                TERMINATE_CAUSE="NAS-Request"
                ;;
            shutdown_deauth)  TERMINATE_CAUSE="NAS-Reboot" ;;
            *)                TERMINATE_CAUSE="NAS-Request" ;;
        esac

        if [ -n "$IDENTIFIER" ] && [ -n "$ACCT_SESSION_ID" ] && [ -f "$RADIUS_SECRET_FILE" ]; then
            SECRET=$(cat "$RADIUS_SECRET_FILE")
            printf 'User-Name = "%s", Acct-Status-Type = Stop, Acct-Session-Id = "%s", Acct-Session-Time = %s, Acct-Input-Octets = %s, Acct-Output-Octets = %s, Acct-Terminate-Cause = %s, Calling-Station-Id = "%s", NAS-Identifier = "opennds-fas"\n' \
                "$IDENTIFIER" "$ACCT_SESSION_ID" "$SESSION_TIME" "${INCOMING_BYTES:-0}" "${OUTGOING_BYTES:-0}" "$TERMINATE_CAUSE" "$MAC" \
                | radclient -x 127.0.0.1:1813 acct "$SECRET" >>/var/log/portal_binauth_errors.log 2>&1
        fi

        $MYSQL "
            UPDATE auth_log
            SET session_end = FROM_UNIXTIME(NULLIF(${SESSION_END:-0},0)),
                upload_bytes = ${OUTGOING_BYTES:-NULL},
                download_bytes = ${INCOMING_BYTES:-NULL},
                terminate_cause = '${METHOD}'
            WHERE client_mac = '${MAC_ESC}' AND session_end IS NULL
            ORDER BY id DESC
            LIMIT 1;
        " 2>>/var/log/portal_binauth_errors.log

        log "$METHOD logged for $MAC up=$OUTGOING_BYTES down=$INCOMING_BYTES"
        ;;

    *)
        log "unhandled method $METHOD for $MAC"
        ;;
esac

return 0 2>/dev/null || exit 0
