#!/bin/bash
set -e
LAN_IF="__PORTAL_INTERFACE__"
IFB_IF="ifb0"

CLIENT_IP="$1"
DOWNLOAD_KBIT="${2:-0}"
UPLOAD_KBIT="${3:-0}"

LAST_OCTET=$(echo "$CLIENT_IP" | awk -F. '{print $4}')
CLASSID=$(printf "1%03d" "$LAST_OCTET")
FILTER_HANDLE="800::${LAST_OCTET}"

tc filter del dev "$LAN_IF" parent 1:0 prio 1 handle "$FILTER_HANDLE" u32 2>/dev/null || true
tc class del dev "$LAN_IF" classid 1:"$CLASSID" 2>/dev/null || true
tc filter del dev "$IFB_IF" parent 1:0 prio 1 handle "$FILTER_HANDLE" u32 2>/dev/null || true
tc class del dev "$IFB_IF" classid 1:"$CLASSID" 2>/dev/null || true

if [ "$DOWNLOAD_KBIT" -gt 0 ] 2>/dev/null; then
    tc class add dev "$LAN_IF" parent 1:1 classid 1:"$CLASSID" htb rate "${DOWNLOAD_KBIT}kbit" ceil "${DOWNLOAD_KBIT}kbit"
    tc filter add dev "$LAN_IF" protocol ip parent 1:0 prio 1 handle "$FILTER_HANDLE" u32 match ip dst "$CLIENT_IP/32" flowid 1:"$CLASSID"
fi

if [ "$UPLOAD_KBIT" -gt 0 ] 2>/dev/null; then
    tc class add dev "$IFB_IF" parent 1:1 classid 1:"$CLASSID" htb rate "${UPLOAD_KBIT}kbit" ceil "${UPLOAD_KBIT}kbit"
    tc filter add dev "$IFB_IF" protocol ip parent 1:0 prio 1 handle "$FILTER_HANDLE" u32 match ip src "$CLIENT_IP/32" flowid 1:"$CLASSID"
fi

exit 0
