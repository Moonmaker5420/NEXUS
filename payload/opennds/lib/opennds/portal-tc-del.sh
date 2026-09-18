#!/bin/bash
LAN_IF="__PORTAL_INTERFACE__"
IFB_IF="ifb0"

CLIENT_IP="$1"
LAST_OCTET=$(echo "$CLIENT_IP" | awk -F. '{print $4}')
CLASSID=$(printf "1%03d" "$LAST_OCTET")
FILTER_HANDLE="800::${LAST_OCTET}"

tc filter del dev "$LAN_IF" parent 1:0 prio 1 handle "$FILTER_HANDLE" u32 2>/dev/null || true
tc class del dev "$LAN_IF" classid 1:"$CLASSID" 2>/dev/null || true
tc filter del dev "$IFB_IF" parent 1:0 prio 1 handle "$FILTER_HANDLE" u32 2>/dev/null || true
tc class del dev "$IFB_IF" classid 1:"$CLASSID" 2>/dev/null || true

exit 0
