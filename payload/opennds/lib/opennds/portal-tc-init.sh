#!/bin/bash
set -e
LAN_IF="__PORTAL_INTERFACE__"
IFB_IF="ifb0"
ROOT_CEIL="1000mbit"
DEFAULT_RATE="2mbit"

echo "Cleaning up any existing shaping state..."
tc qdisc del dev "$LAN_IF" root 2>/dev/null || true
tc qdisc del dev "$LAN_IF" ingress 2>/dev/null || true
tc qdisc del dev "$IFB_IF" root 2>/dev/null || true
ip link del "$IFB_IF" 2>/dev/null || true

echo "Setting up download (egress on $LAN_IF) shaping..."
tc qdisc add dev "$LAN_IF" root handle 1: htb default 999
tc class add dev "$LAN_IF" parent 1: classid 1:1 htb rate "$ROOT_CEIL" ceil "$ROOT_CEIL"
tc class add dev "$LAN_IF" parent 1:1 classid 1:999 htb rate "$DEFAULT_RATE" ceil "$ROOT_CEIL"

echo "Setting up upload (ingress via IFB) shaping..."
modprobe ifb numifbs=1 2>/dev/null || modprobe ifb 2>/dev/null || true
ip link add "$IFB_IF" type ifb 2>/dev/null || true
ip link set dev "$IFB_IF" up

tc qdisc add dev "$LAN_IF" handle ffff: ingress
tc filter add dev "$LAN_IF" parent ffff: protocol ip u32 match u32 0 0 action mirred egress redirect dev "$IFB_IF"

tc qdisc add dev "$IFB_IF" root handle 1: htb default 999
tc class add dev "$IFB_IF" parent 1: classid 1:1 htb rate "$ROOT_CEIL" ceil "$ROOT_CEIL"
tc class add dev "$IFB_IF" parent 1:1 classid 1:999 htb rate "$DEFAULT_RATE" ceil "$ROOT_CEIL"

echo "Base shaping hierarchy ready on $LAN_IF / $IFB_IF."
