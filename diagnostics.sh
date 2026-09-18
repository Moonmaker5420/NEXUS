#!/usr/bin/env bash
set -u
echo '=== WiFi Portal Diagnostics ==='
echo
echo '-- Versions --'
opennds -v 2>&1 || true
freeradius -v 2>&1 || true
python3 --version || true
echo
echo '-- Services --'
for s in mariadb freeradius portal-fas portal-dashboard portal-tc-init opennds; do printf '%-22s' "$s"; systemctl is-active "$s" 2>/dev/null || true; done
echo
echo '-- Ports --'
ss -lntup | grep -E ':(1812|1813|2050|2080|8090)\b' || true
echo
echo '-- openNDS status --'
ndsctl status 2>&1 || true
echo
echo '-- openNDS config --'
grep -E '^(gatewayinterface|gatewayname|gatewayport|fasport|faspath)' /etc/opennds/opennds.conf 2>/dev/null || true
echo
echo '-- Recent errors --'
journalctl -u opennds -u freeradius -u portal-fas -u portal-dashboard -p warning -n 40 --no-pager 2>/dev/null || true
