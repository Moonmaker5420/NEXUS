#!/usr/bin/env bash

set -euo pipefail

###############################################################################
# WiFi Portal Stack Installer
#
# Architecture:
#
#   Internet / Upstream Network
#            |
#      UPSTREAM_INTERFACE
#            |
#         Ubuntu Server
#            |
#      PORTAL_INTERFACE
#            |
#      192.168.50.1/24
#            |
#       DHCP Clients
#
# Components:
#   - openNDS 10.3.0
#   - dnsmasq DHCP
#   - FreeRADIUS + MariaDB
#   - Flask FAS
#   - Flask Dashboard
#   - IFB/HTB per-client shaping
###############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PAYLOAD="$SCRIPT_DIR/payload"
DATABASE="$SCRIPT_DIR/database"
SYSTEMD="$SCRIPT_DIR/systemd"

OPENNDS_VERSION="10.3.0"

###############################################################################
# FUNCTIONS
###############################################################################

log() {
    echo
    echo "[+] $*"
}

warn() {
    echo
    echo "[!] $*" >&2
}

die() {
    echo
    echo "[ERROR] $*" >&2
    exit 1
}

require_root() {

    if [[ "${EUID}" -ne 0 ]]; then
        die "Run this installer as root: sudo bash install.sh"
    fi

}

random_secret() {

    openssl rand -base64 32 | tr -d '\n'

}

escape_sed() {

    printf '%s' "$1" | sed 's/[&|\\]/\\&/g'

}

command_exists() {

    command -v "$1" >/dev/null 2>&1

}

###############################################################################
# ROOT CHECK
###############################################################################

require_root

###############################################################################
# BASIC VALIDATION
###############################################################################

[[ -d "$PAYLOAD" ]] || die "Missing payload directory: $PAYLOAD"
[[ -d "$DATABASE" ]] || die "Missing database directory: $DATABASE"
[[ -d "$SYSTEMD" ]] || die "Missing systemd directory: $SYSTEMD"

[[ -f "$PAYLOAD/requirements.txt" ]] || die "Missing payload/requirements.txt"

[[ -f "$PAYLOAD/opennds/etc/opennds/opennds.conf.template" ]] \
    || die "Missing openNDS configuration template"

[[ -f "$PAYLOAD/opennds/lib/opennds/custombinauth.sh" ]] \
    || die "Missing custombinauth.sh"

[[ -f "$PAYLOAD/opennds/lib/opennds/portal-tc-init.sh" ]] \
    || die "Missing portal-tc-init.sh"

[[ -f "$PAYLOAD/opennds/lib/opennds/portal-tc-add.sh" ]] \
    || die "Missing portal-tc-add.sh"

[[ -f "$PAYLOAD/opennds/lib/opennds/portal-tc-del.sh" ]] \
    || die "Missing portal-tc-del.sh"

[[ -f "$DATABASE/portal-schema.sql" ]] \
    || die "Missing portal-schema.sql"

[[ -f "$DATABASE/radius-schema.sql" ]] \
    || die "Missing radius-schema.sql"

###############################################################################
# OS CHECK
###############################################################################

[[ -f /etc/os-release ]] || die "/etc/os-release not found"

. /etc/os-release

case "${ID:-}" in

    ubuntu|debian)
        ;;
    *)
        die "This installer supports Ubuntu/Debian only."
        ;;

esac

###############################################################################
# INSTALLATION HEADER
###############################################################################

clear

echo "======================================================"
echo "            WiFi Portal Stack Installer"
echo "======================================================"
echo
echo "Operating System:"
echo "  ${PRETTY_NAME:-Unknown}"
echo

###############################################################################
# DETECT NETWORK INTERFACES
###############################################################################

log "Detecting network interfaces"

mapfile -t IFACES < <(
    ls /sys/class/net \
    | grep -Ev '^(lo|docker.*|br-.*|veth.*|ifb.*|tailscale.*)$'
)

[[ "${#IFACES[@]}" -gt 0 ]] || die "No usable network interfaces found."

echo
echo "Available network interfaces:"
echo

for i in "${!IFACES[@]}"; do

    IFACE="${IFACES[$i]}"

    IP_ADDR=$(
        ip -4 -o addr show dev "$IFACE" scope global 2>/dev/null \
        | awk '{print $4}' \
        | head -n 1 \
        || true
    )

    if [[ -n "$IP_ADDR" ]]; then

        echo "  $((i + 1))) $IFACE    [$IP_ADDR]"

    else

        echo "  $((i + 1))) $IFACE    [no IPv4 address]"

    fi

done

echo

###############################################################################
# SELECT PORTAL INTERFACE
###############################################################################

while true; do

    read -rp "Select captive portal interface: " IFACE_CHOICE

    if [[ "$IFACE_CHOICE" =~ ^[0-9]+$ ]]; then

        if (( IFACE_CHOICE >= 1 && IFACE_CHOICE <= ${#IFACES[@]} )); then

            PORTAL_INTERFACE="${IFACES[$((IFACE_CHOICE - 1))]}"
            break

        fi

    fi

    if ip link show "$IFACE_CHOICE" >/dev/null 2>&1; then

        PORTAL_INTERFACE="$IFACE_CHOICE"
        break

    fi

    echo "Invalid interface."

done

echo
echo "Selected portal interface: $PORTAL_INTERFACE"
echo

###############################################################################
# DETECT UPSTREAM INTERFACE
###############################################################################

UPSTREAM_INTERFACE=$(
    ip route show default \
    | awk '/default/ {print $5; exit}'
)

if [[ -z "${UPSTREAM_INTERFACE:-}" ]]; then

    warn "Unable to automatically detect upstream interface."

    echo
    echo "Available interfaces:"

    for i in "${!IFACES[@]}"; do

        echo "  $((i + 1))) ${IFACES[$i]}"

    done

    echo

    read -rp "Enter upstream interface: " UPSTREAM_INTERFACE

fi

if [[ "$PORTAL_INTERFACE" == "$UPSTREAM_INTERFACE" ]]; then

    die "Portal interface and upstream interface cannot be the same."
fi

echo "Upstream interface: $UPSTREAM_INTERFACE"

###############################################################################
# PORTAL NETWORK CONFIGURATION
###############################################################################

echo
echo "======================================================"
echo "Portal Network Configuration"
echo "======================================================"
echo

read -rp "Portal gateway IP [192.168.50.1]: " PORTAL_GATEWAY

PORTAL_GATEWAY="${PORTAL_GATEWAY:-192.168.50.1}"

read -rp "Portal subnet prefix [24]: " PORTAL_PREFIX

PORTAL_PREFIX="${PORTAL_PREFIX:-24}"

PORTAL_CIDR="${PORTAL_GATEWAY}/${PORTAL_PREFIX}"

DEFAULT_DHCP_START="192.168.50.10"
DEFAULT_DHCP_END="192.168.50.200"

read -rp "DHCP range start [$DEFAULT_DHCP_START]: " DHCP_START
DHCP_START="${DHCP_START:-$DEFAULT_DHCP_START}"

read -rp "DHCP range end [$DEFAULT_DHCP_END]: " DHCP_END
DHCP_END="${DHCP_END:-$DEFAULT_DHCP_END}"

###############################################################################
# PORTAL SETTINGS
###############################################################################

echo
echo "======================================================"
echo "Portal Application Configuration"
echo "======================================================"
echo

read -rp "Gateway name [WiFi Portal]: " GATEWAY_NAME
GATEWAY_NAME="${GATEWAY_NAME:-WiFi Portal}"

read -rp "Gateway port [2050]: " GATEWAY_PORT
GATEWAY_PORT="${GATEWAY_PORT:-2050}"

read -rp "FAS port [2080]: " FAS_PORT
FAS_PORT="${FAS_PORT:-2080}"

read -rp "Dashboard port [8090]: " DASHBOARD_PORT
DASHBOARD_PORT="${DASHBOARD_PORT:-8090}"

# By default the dashboard binds to 127.0.0.1 only (access via SSH tunnel),
# since it's an admin panel. It has its own login, so exposing it more
# broadly is a reasonable opt-in for deployments that want direct browser
# access without a tunnel.
echo "Dashboard network exposure:"
echo "  1) Localhost only -- access via SSH tunnel (most secure, default)"
echo "  2) Portal network only -- reachable at ${PORTAL_GATEWAY}:${DASHBOARD_PORT}"
echo "  3) WAN/management interface only -- reachable at this server's ${UPSTREAM_INTERFACE} address"
read -rp "Choose [1]: " DASHBOARD_EXPOSE_CHOICE
DASHBOARD_EXPOSE_CHOICE="${DASHBOARD_EXPOSE_CHOICE:-1}"

case "$DASHBOARD_EXPOSE_CHOICE" in
    2)
        DASHBOARD_BIND_IP="$PORTAL_GATEWAY"
        ;;
    3)
        # UPSTREAM_INTERFACE's address is typically DHCP-assigned, so this
        # bakes in whatever it currently is at install time. If the lease
        # changes later, the dashboard needs a restart to pick up the new
        # address -- gunicorn binds to a specific IP, not an interface.
        UPSTREAM_IP=$(
            ip -4 addr show "$UPSTREAM_INTERFACE" \
            | grep -oP '(?<=inet\s)\d+(\.\d+){3}' \
            | head -1
        )

        [[ -n "$UPSTREAM_IP" ]] \
            || die "Could not determine an IPv4 address for $UPSTREAM_INTERFACE"

        DASHBOARD_BIND_IP="$UPSTREAM_IP"
        ;;
    *)
        DASHBOARD_BIND_IP="127.0.0.1"
        ;;
esac

FAS_STATUS_DEFAULT="http://${PORTAL_GATEWAY}:${FAS_PORT}/fas/status"

read -rp "FAS status URL [$FAS_STATUS_DEFAULT]: " FAS_STATUS_URL

FAS_STATUS_URL="${FAS_STATUS_URL:-$FAS_STATUS_DEFAULT}"

read -rp "Dashboard admin username [admin]: " DASH_ADMIN

DASH_ADMIN="${DASH_ADMIN:-admin}"

while true; do

    read -rsp "Dashboard admin password: " DASH_PASSWORD
    echo

    [[ -n "$DASH_PASSWORD" ]] && break

    echo "Password cannot be empty."

done

read -rp "Upstream DNS server for Pi-hole [1.1.1.1]: " PIHOLE_UPSTREAM_DNS
PIHOLE_UPSTREAM_DNS="${PIHOLE_UPSTREAM_DNS:-1.1.1.1}"

# Both portal-fas.service and portal-dashboard.service ship with "-w 2"
# (2 sync workers) hardcoded in their unit templates. With only 2 workers,
# a couple of concurrent slow requests (each worker call to
# check_internet()/ndsctl/radius_db() forks a subprocess or opens a DB
# connection) can leave zero workers free for any other request, which then
# queues until gunicorn's 30s worker timeout kills it -- surfacing to the
# browser as an Internal Server Error, particularly under the dashboard's
# own periodic auto-refresh (index.html/sessions.html). Scale workers to
# (2 x CPU cores) + 1, gunicorn's own standard guidance.
GUNICORN_WORKERS=$(( ($(nproc) * 2) + 1 ))

# gunicorn's own default worker timeout (30s) has been observed in testing
# to be too tight for this app under real conditions -- occasional requests
# through check_internet()/radius_db() take long enough to trip it, killing
# the worker mid-request and surfacing as a 500 to the browser. 60s gives
# meaningful headroom without masking a truly hung worker for too long.
GUNICORN_TIMEOUT=60

###############################################################################
# CONFIRM
###############################################################################

echo
echo "======================================================"
echo "Installation Summary"
echo "======================================================"
echo
echo "Upstream Interface : $UPSTREAM_INTERFACE"
echo "Portal Interface   : $PORTAL_INTERFACE"
echo "Portal Gateway    : $PORTAL_CIDR"
echo "DHCP Range        : $DHCP_START - $DHCP_END"
echo "Gateway Name      : $GATEWAY_NAME"
echo "Gateway Port      : $GATEWAY_PORT"
echo "FAS Port          : $FAS_PORT"
echo "Dashboard Port    : $DASHBOARD_PORT"
echo "Pi-hole Upstream  : $PIHOLE_UPSTREAM_DNS"
echo "Gunicorn Workers  : $GUNICORN_WORKERS (per service, detected $(nproc) CPU cores)"
echo "Gunicorn Timeout  : ${GUNICORN_TIMEOUT}s"
echo
echo "IMPORTANT:"
echo "The portal interface will be configured with:"
echo
echo "  $PORTAL_INTERFACE -> $PORTAL_CIDR"
echo
echo "The existing upstream network configuration will NOT"
echo "be overwritten."
echo

read -rp "Continue installation? [y/N]: " CONFIRM

case "${CONFIRM,,}" in

    y|yes)
        ;;
    *)
        echo "Installation cancelled."
        exit 0
        ;;

esac

###############################################################################
# GENERATE SECRETS
###############################################################################

log "Generating application secrets"

FAS_KEY="$(random_secret)"
RADIUS_SECRET="$(random_secret)"

PORTAL_DB_PASS="$(random_secret)"
RADIUS_DB_PASS="$(random_secret)"
BINAUTH_DB_PASS="$(random_secret)"

DASH_SECRET="$(random_secret)"

PIHOLE_ADMIN_PASS="$(random_secret)"

###############################################################################
# PACKAGE INSTALLATION
###############################################################################

export DEBIAN_FRONTEND=noninteractive

log "Updating package lists"

apt-get update

log "Installing required packages"

apt-get install -y \
    ca-certificates \
    curl \
    wget \
    git \
    build-essential \
    cmake \
    pkg-config \
    libmicrohttpd-dev \
    libmnl-dev \
    libnftnl-dev \
    libgnutls28-dev \
    nftables \
    iproute2 \
    kmod \
    dnsmasq \
    mariadb-server \
    mariadb-client \
    freeradius \
    freeradius-mysql \
    freeradius-utils \
    python3 \
    python3-venv \
    python3-pip \
    python3-dev \
    python3-pymysql \
    python3-flask \
    python3-gunicorn \
    python3-werkzeug \
    openssl \
    rsync \
    netplan.io \
    dnsutils

###############################################################################
# ENABLE IP FORWARDING
###############################################################################

log "Configuring IP forwarding"

cat > /etc/sysctl.d/99-wifi-portal.conf <<EOF
net.ipv4.ip_forward=1
EOF

sysctl --system >/dev/null

###############################################################################
# CONFIGURE NAT / MASQUERADE
###############################################################################

# IP forwarding and openNDS's own firewall chains only decide whether a
# packet is allowed through -- they don't translate its source address.
# Without masquerade, authenticated portal clients' packets leave this box
# via $UPSTREAM_INTERFACE still carrying their private 192.168.50.x source
# address, which the upstream network has no route back to: traffic goes
# out, nothing ever comes back, and the client sees "no internet" despite
# being fully authenticated. This is a separate nftables table from the
# ones openNDS itself creates/regenerates on every restart (nds_filter,
# nds_mangle, nds_nat), so it survives independently of openNDS's own
# lifecycle and can't be wiped out by it.

log "Configuring NAT masquerade for ${UPSTREAM_INTERFACE}"

cat > /etc/systemd/system/portal-nat.service <<EOF
[Unit]
Description=Portal NAT masquerade for ${UPSTREAM_INTERFACE}
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/sbin/nft -f /etc/portal-nat.nft
ExecStop=/usr/sbin/nft delete table ip portal_nat

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/portal-nat.nft <<EOF
table ip portal_nat
delete table ip portal_nat
table ip portal_nat {
    chain postrouting {
        type nat hook postrouting priority srcnat; policy accept;
        oifname "${UPSTREAM_INTERFACE}" masquerade
    }
}
EOF

systemctl daemon-reload

systemctl enable portal-nat

systemctl restart portal-nat

sleep 1

nft list table ip portal_nat \
    || die "portal-nat masquerade table failed to load"

###############################################################################
# CONFIGURE NETPLAN
###############################################################################

log "Creating persistent Netplan configuration"

NETPLAN_BACKUP_DIR="/root/netplan-backup-$(date +%Y%m%d-%H%M%S)"

mkdir -p "$NETPLAN_BACKUP_DIR"

if compgen -G "/etc/netplan/*.yaml" > /dev/null; then

    cp -a /etc/netplan/*.yaml "$NETPLAN_BACKUP_DIR/" || true

fi

PORTAL_NETPLAN="/etc/netplan/99-wifi-portal.yaml"

cat > "$PORTAL_NETPLAN" <<EOF
network:
  version: 2
  ethernets:
    ${PORTAL_INTERFACE}:
      dhcp4: false
      addresses:
        - ${PORTAL_CIDR}
      ignore-carrier: true
EOF

chmod 600 "$PORTAL_NETPLAN"

log "Validating Netplan configuration"

netplan generate

log "Applying Netplan configuration"

netplan apply

sleep 3

PORTAL_ASSIGNED_IP=$(
    ip -4 -o addr show dev "$PORTAL_INTERFACE" \
    | awk '{print $4}' \
    | cut -d/ -f1 \
    | head -n 1
)

if [[ "$PORTAL_ASSIGNED_IP" != "$PORTAL_GATEWAY" ]]; then

    LINK_STATE=$(ip -o link show dev "$PORTAL_INTERFACE" 2>/dev/null)

    if echo "$LINK_STATE" | grep -q "NO-CARRIER"; then

        die "Portal interface did not receive expected IP address.
Expected: $PORTAL_GATEWAY
Found:    ${PORTAL_ASSIGNED_IP:-none}

$PORTAL_INTERFACE has NO-CARRIER -- this interface has no physical/virtual
link at all, which is a hypervisor or cabling issue, not a netplan config
problem. If this is a VM, check that $PORTAL_INTERFACE's virtual NIC is
actually connected to a virtual switch/network in your hypervisor (even an
isolated/host-only network is fine -- it just needs to be connected to
something). Current link state:
$LINK_STATE"

    else

        die "Portal interface did not receive expected IP address.
Expected: $PORTAL_GATEWAY
Found:    ${PORTAL_ASSIGNED_IP:-none}

Current link state:
$LINK_STATE"

    fi

fi

###############################################################################
# CONFIGURE status.client
###############################################################################

log "Configuring status.client hostname"

if ! grep -qE "^[[:space:]]*${PORTAL_GATEWAY}[[:space:]]+status\.client" /etc/hosts; then

    echo "${PORTAL_GATEWAY} status.client" >> /etc/hosts

fi

###############################################################################
# CONFIGURE DNSMASQ
###############################################################################

log "Configuring dnsmasq"

DNSMASQ_PORTAL_CONF="/etc/dnsmasq.d/wifi-portal.conf"

cat > "$DNSMASQ_PORTAL_CONF" <<EOF
# WiFi Portal DHCP configuration

interface=${PORTAL_INTERFACE}
bind-interfaces

dhcp-range=${DHCP_START},${DHCP_END},255.255.255.0,12h

# Default gateway
dhcp-option=3,${PORTAL_GATEWAY}

# DNS server advertised to clients
dhcp-option=6,${PORTAL_GATEWAY}

# DHCP only.
# DNS handling is performed by openNDS/system networking.
port=0

# Captive portal DHCP option
dhcp-option-force=114,http://status.client

# openNDS nftables integration
nftset=/4#ip#nds_filter#walledgarden
nftset=/4#ip#nds_filter#blocklist
EOF

log "Validating dnsmasq configuration"

dnsmasq --test

log "Enabling dnsmasq"

systemctl enable dnsmasq

log "Starting dnsmasq"

systemctl restart dnsmasq

sleep 2

systemctl is-active --quiet dnsmasq \
    || die "dnsmasq failed to start"

###############################################################################
# CONFIGURE PI-HOLE
###############################################################################

# dnsmasq handles DHCP only on this box (port=0 above) -- DNS for portal
# clients is served by Pi-hole instead. This also gives openNDS's walled
# garden / blocklist nftset population something to actually observe live
# queries through.

log "Freeing port 53 from systemd-resolved's stub listener"

mkdir -p /etc/systemd/resolved.conf.d

cat > /etc/systemd/resolved.conf.d/pihole.conf <<'EOF'
[Resolve]
DNSStubListener=no
EOF

systemctl restart systemd-resolved

# With the stub listener disabled, /etc/resolv.conf (usually a symlink to
# systemd-resolved's stub file) needs to point at a real resolver until
# Pi-hole takes over system-wide DNS. Pi-hole's installer manages this file
# itself once installed; this is just to unblock apt/network access during
# install if resolv.conf was pointing at the now-disabled stub.
if [[ -L /etc/resolv.conf ]] || grep -q "^nameserver 127.0.0.53" /etc/resolv.conf 2>/dev/null; then

    rm -f /etc/resolv.conf
    echo "nameserver ${PIHOLE_UPSTREAM_DNS}" > /etc/resolv.conf

fi

log "Installing Pi-hole"

mkdir -p /etc/pihole

cat > /etc/pihole/setupVars.conf <<EOF
PIHOLE_INTERFACE=${PORTAL_INTERFACE}
IPV4_ADDRESS=${PORTAL_CIDR}
IPV6_ADDRESS=
PIHOLE_DNS_1=${PIHOLE_UPSTREAM_DNS}
QUERY_LOGGING=true
INSTALL_WEB_SERVER=true
INSTALL_WEB_INTERFACE=true
LIGHTTPD_ENABLED=true
CACHE_SIZE=10000
DNS_FQDN_REQUIRED=true
DNS_BOGUS_PRIV=true
DNSMASQ_LISTENING=all
WEBPASSWORD=
BLOCKING_ENABLED=true
EOF

curl -fsSL https://install.pi-hole.net -o /tmp/pihole-install.sh

bash /tmp/pihole-install.sh --unattended \
    || die "Pi-hole installation failed"

rm -f /tmp/pihole-install.sh

log "Verifying Pi-hole DNS service"

sleep 2

systemctl is-active --quiet pihole-FTL \
    || die "pihole-FTL failed to start"

ss -lunp | grep -q ":53 " \
    || die "Nothing is listening on port 53 after Pi-hole install"

log "Setting Pi-hole admin password"

pihole -a -p "$PIHOLE_ADMIN_PASS" \
    || die "Failed to set Pi-hole admin password"

###############################################################################
# BUILD OPENNDS
###############################################################################

log "Downloading and building openNDS ${OPENNDS_VERSION}"

BUILD_ROOT="/usr/local/src"
OPENNDS_ARCHIVE="/tmp/opennds-${OPENNDS_VERSION}.tar.gz"
OPENNDS_BUILD_DIR="${BUILD_ROOT}/openNDS-${OPENNDS_VERSION}"

rm -f "$OPENNDS_ARCHIVE"

rm -rf "$OPENNDS_BUILD_DIR"

log "Downloading openNDS source"

wget -4 \
    --tries=3 \
    --timeout=30 \
    --show-progress \
    "https://codeload.github.com/openNDS/openNDS/tar.gz/v${OPENNDS_VERSION}" \
    -O "$OPENNDS_ARCHIVE"

[[ -s "$OPENNDS_ARCHIVE" ]] \
    || die "openNDS download failed or archive is empty"

log "Extracting openNDS"

tar \
    -xzf "$OPENNDS_ARCHIVE" \
    -C "$BUILD_ROOT"

if [[ ! -d "$OPENNDS_BUILD_DIR" ]]; then

    OPENNDS_BUILD_DIR=$(
        find "$BUILD_ROOT" \
            -maxdepth 1 \
            -type d \
            -name "openNDS*" \
            | sort \
            | tail -n 1
    )

fi

[[ -d "$OPENNDS_BUILD_DIR" ]] \
    || die "Unable to locate extracted openNDS source directory"

cd "$OPENNDS_BUILD_DIR"

log "Building openNDS"

if [[ -x "./build" ]]; then

    ./build

elif [[ -f "Makefile" ]]; then

    make -j"$(nproc)"

else

    cmake -B build -S .
    cmake --build build -j"$(nproc)"

fi

log "Installing openNDS"

if [[ -f "Makefile" ]]; then

    make install

else

    cmake --install build

fi

command -v opennds >/dev/null \
    || die "openNDS installation failed"

log "Installed openNDS version"

opennds -v || true

###############################################################################
# CREATE PORTAL USER
###############################################################################

log "Creating portal service account"

if ! id portal >/dev/null 2>&1; then

    useradd \
        --system \
        --home /opt/portal \
        --shell /usr/sbin/nologin \
        portal

fi

mkdir -p \
    /opt/portal \
    /etc/portal \
    /etc/portal/fas \
    /var/log/portal

###############################################################################
# INSTALL PORTAL APPLICATION
###############################################################################

log "Installing portal application files"

rsync \
    -a \
    --delete \
    "$PAYLOAD/portal/" \
    /opt/portal/

chown \
    -R \
    portal:portal \
    /opt/portal \
    /var/log/portal

###############################################################################
# PYTHON VIRTUAL ENVIRONMENT
###############################################################################

log "Creating Python virtual environment"

rm -rf /opt/portal/venv

python3 -m venv /opt/portal/venv

/opt/portal/venv/bin/pip install \
    --upgrade \
    pip \
    wheel \
    setuptools

log "Installing portal Python dependencies"

/opt/portal/venv/bin/pip install \
    -r "$PAYLOAD/requirements.txt"

chown \
    -R \
    portal:portal \
    /opt/portal/venv

###############################################################################
# CONFIGURE MARIADB
###############################################################################

log "Starting MariaDB"

systemctl enable --now mariadb

sleep 2

systemctl is-active --quiet mariadb \
    || die "MariaDB failed to start"

###############################################################################
# CREATE DATABASES AND USERS
###############################################################################

log "Creating databases and database users"

mysql <<SQL

CREATE DATABASE IF NOT EXISTS portal
CHARACTER SET utf8mb4
COLLATE utf8mb4_unicode_ci;

CREATE DATABASE IF NOT EXISTS radius
CHARACTER SET utf8mb4
COLLATE utf8mb4_unicode_ci;


CREATE USER IF NOT EXISTS
'portal_fas'@'127.0.0.1'
IDENTIFIED BY '${PORTAL_DB_PASS}';

CREATE USER IF NOT EXISTS
'portal_fas'@'localhost'
IDENTIFIED BY '${PORTAL_DB_PASS}';


CREATE USER IF NOT EXISTS
'portal_dashboard'@'127.0.0.1'
IDENTIFIED BY '${PORTAL_DB_PASS}';

CREATE USER IF NOT EXISTS
'portal_dashboard'@'localhost'
IDENTIFIED BY '${PORTAL_DB_PASS}';


CREATE USER IF NOT EXISTS
'portal_binauth'@'127.0.0.1'
IDENTIFIED BY '${BINAUTH_DB_PASS}';

CREATE USER IF NOT EXISTS
'portal_binauth'@'localhost'
IDENTIFIED BY '${BINAUTH_DB_PASS}';


CREATE USER IF NOT EXISTS
'radius'@'127.0.0.1'
IDENTIFIED BY '${RADIUS_DB_PASS}';

CREATE USER IF NOT EXISTS
'radius'@'localhost'
IDENTIFIED BY '${RADIUS_DB_PASS}';


GRANT ALL PRIVILEGES
ON portal.*
TO 'portal_fas'@'127.0.0.1';

GRANT ALL PRIVILEGES
ON portal.*
TO 'portal_fas'@'localhost';

# portal-fas also connects directly to the radius database (radius_db() in
# app.py) to look up client data usage for quota enforcement. Without this,
# login succeeds up to the quota check and then 500s with "Access denied
# for user 'portal_fas'@'localhost' to database 'radius'".
GRANT SELECT, INSERT, UPDATE
ON radius.*
TO 'portal_fas'@'127.0.0.1';

GRANT SELECT, INSERT, UPDATE
ON radius.*
TO 'portal_fas'@'localhost';


GRANT ALL PRIVILEGES
ON portal.*
TO 'portal_dashboard'@'127.0.0.1';

GRANT ALL PRIVILEGES
ON portal.*
TO 'portal_dashboard'@'localhost';

# portal-dashboard also writes directly to the radius database (radius_db()
# in app.py, e.g. upsert_radcheck_password()) to manage RADIUS login
# credentials. Without this, creating/editing a login 500s with "Access
# denied for user 'portal_dashboard'@'localhost' to database 'radius'".
GRANT SELECT, INSERT, UPDATE
ON radius.*
TO 'portal_dashboard'@'127.0.0.1';

GRANT SELECT, INSERT, UPDATE
ON radius.*
TO 'portal_dashboard'@'localhost';


GRANT SELECT, INSERT, UPDATE
ON portal.*
TO 'portal_binauth'@'127.0.0.1';

GRANT SELECT, INSERT, UPDATE
ON portal.*
TO 'portal_binauth'@'localhost';


GRANT ALL PRIVILEGES
ON radius.*
TO 'radius'@'127.0.0.1';

GRANT ALL PRIVILEGES
ON radius.*
TO 'radius'@'localhost';


FLUSH PRIVILEGES;

SQL

###############################################################################
# IMPORT DATABASE SCHEMAS
###############################################################################

log "Importing portal database schema"

mysql portal < "$DATABASE/portal-schema.sql"

log "Importing RADIUS database schema"

mysql radius < "$DATABASE/radius-schema.sql"

###############################################################################
# CONFIGURE FREERADIUS
###############################################################################

log "Configuring FreeRADIUS"

FR_BASE="/etc/freeradius/3.0"

[[ -d "$FR_BASE" ]] \
    || die "FreeRADIUS 3 configuration directory not found"

install \
    -o root -g freerad -m 640 \
    "$PAYLOAD/freeradius/mods-available/sql.template" \
    "$FR_BASE/mods-available/sql"

install \
    -o root -g freerad -m 640 \
    "$PAYLOAD/freeradius/clients.conf.template" \
    "$FR_BASE/clients.conf"

sed -i \
    "s|__RADIUS_DB_PASSWORD__|$(escape_sed "$RADIUS_DB_PASS")|g" \
    "$FR_BASE/mods-available/sql"

sed -i \
    "s|__RADIUS_SECRET__|$(escape_sed "$RADIUS_SECRET")|g" \
    "$FR_BASE/clients.conf"

ln -sf \
    ../mods-available/sql \
    "$FR_BASE/mods-enabled/sql"

install \
    -o root -g freerad -m 640 \
    "$PAYLOAD/freeradius/sites-available/default" \
    "$FR_BASE/sites-available/default"

install \
    -o root -g freerad -m 640 \
    "$PAYLOAD/freeradius/sites-available/inner-tunnel" \
    "$FR_BASE/sites-available/inner-tunnel"

log "Validating FreeRADIUS configuration"

freeradius -XC \
    || die "FreeRADIUS configuration validation failed"

log "Starting FreeRADIUS"

systemctl enable freeradius

systemctl restart freeradius

sleep 2

systemctl is-active --quiet freeradius \
    || die "FreeRADIUS failed to start"

###############################################################################
# CONFIGURE OPENNDS
###############################################################################

log "Installing openNDS configuration"

mkdir -p \
    /etc/opennds \
    /usr/lib/opennds

cp \
    "$PAYLOAD/opennds/etc/opennds/opennds.conf.template" \
    /etc/opennds/opennds.conf

sed -i \
    -e "s|__PORTAL_INTERFACE__|$(escape_sed "$PORTAL_INTERFACE")|g" \
    -e "s|__GATEWAY_NAME__|$(escape_sed "$GATEWAY_NAME")|g" \
    -e "s|__GATEWAY_PORT__|$(escape_sed "$GATEWAY_PORT")|g" \
    -e "s|__FAS_KEY__|$(escape_sed "$FAS_KEY")|g" \
    /etc/opennds/opennds.conf

###############################################################################
# CONFIGURE OPENNDS (UCI config)
###############################################################################

# This openNDS build was compiled with UCI support and reads its live
# configuration from /etc/config/opennds via libopennds.sh's
# get_option_from_config helper -- NOT from /etc/opennds/opennds.conf above.
# That file is still written for tooling/reference, but has no effect on the
# running daemon on this platform. /etc/config/opennds is created by
# "make install" with every option commented out to its OpenWrt-oriented
# default (eg. gatewayinterface defaults to 'br-lan'), so it must exist and
# be edited in place -- do not delete it.

NDS_UCI_CONF="/etc/config/opennds"

[[ -f "$NDS_UCI_CONF" ]] \
    || die "openNDS UCI configuration file not found at $NDS_UCI_CONF"

set_nds_uci_option() {

    local KEY="$1"
    local VALUE="$2"
    local ESCAPED_VALUE
    ESCAPED_VALUE="$(escape_sed "$VALUE")"

    # Delete every existing line for this key (active or commented) rather
    # than editing in place. The stock openNDS template often has multiple
    # commented example lines for the same key (e.g. faspath has 3, fasport
    # has 2) -- in-place substitution activates ALL of them, producing
    # duplicate option lines that corrupt openNDS's own config parsing
    # (confirmed root cause of the gatewayname concatenation bug seen
    # during testing). Deleting and re-appending is idempotent even across
    # repeated installer runs on the same box.
    sed -i -E \
        "/^[[:space:]]*#?[[:space:]]*option[[:space:]]+${KEY}[[:space:]]/d" \
        "$NDS_UCI_CONF"

    echo "        option ${KEY} '${ESCAPED_VALUE}'" >> "$NDS_UCI_CONF"

}

set_nds_uci_option "gatewayinterface" "$PORTAL_INTERFACE"
set_nds_uci_option "gatewayname" "$GATEWAY_NAME"
set_nds_uci_option "gatewayport" "$GATEWAY_PORT"
set_nds_uci_option "faskey" "$FAS_KEY"

# FAS (Forwarding Authentication Service) options -- point openNDS at our
# own portal-fas service instead of its built-in Click-to-Continue splash.
# These were previously only written to the inert /etc/opennds/opennds.conf
# above and never took effect; see comment at the top of this section.
set_nds_uci_option "fasport" "$FAS_PORT"
set_nds_uci_option "fasremoteip" "$PORTAL_GATEWAY"
set_nds_uci_option "faspath" "/fas/login"
set_nds_uci_option "fas_secure_enabled" "1"
set_nds_uci_option "login_option_enabled" "0"

# openNDS's built-in Preemptive Authentication feature, when left at its
# default (enabled), overrides external FAS with its own internal
# Click-to-Continue splash regardless of FAS config -- confirmed via
# startup log: "Preauth is Enabled - Overriding FAS configuration."
# Disabling this is required for external FAS to actually be used.
set_nds_uci_option "allow_preemptive_authentication" "0"

add_nds_uci_list() {

    local KEY="$1"
    local VALUE="$2"
    local ESCAPED_VALUE
    ESCAPED_VALUE="$(escape_sed "$VALUE")"

    if grep -Eq "^[[:space:]]*list[[:space:]]+${KEY}[[:space:]]+'${ESCAPED_VALUE}'" "$NDS_UCI_CONF"; then

        : # already present, nothing to do

    else

        echo "        list ${KEY} '${VALUE}'" >> "$NDS_UCI_CONF"

    fi

}

# Preauthenticated clients are blocked by openNDS's own firewall rules from
# reaching anything on the gateway except the built-in captive portal ports
# (2050, DNS, DHCP, SSH, 443) unless explicitly allowed here. Without this,
# clients can't reach portal-fas on $FAS_PORT before authenticating, which
# either times out or falls back to openNDS's internal splash page.
add_nds_uci_list "users_to_router" "allow tcp port $FAS_PORT"

# openNDS 10.3.0's libmicrohttpd version check does not correctly parse MHD
# 1.x version strings and reports a false "libmicrohttpd is out of date"
# error on startup, even though MHD 1.0+ is newer than the actual minimum
# (0.9.71). This is an upstream bug (see openNDS/openNDS#637), not a real
# outdated dependency. use_outdated_mhd simply skips that broken check.
set_nds_uci_option "use_outdated_mhd" "1"

log "Verifying openNDS UCI configuration"

grep -nE "^[[:space:]]*(option[[:space:]]+(gatewayinterface|gatewayname|gatewayport|fasport|fasremoteip|faspath|fas_secure_enabled|login_option_enabled|allow_preemptive_authentication|use_outdated_mhd)|list[[:space:]]+users_to_router)[[:space:]]" \
    "$NDS_UCI_CONF"

###############################################################################
# INSTALL BINAUTH AND TRAFFIC SHAPING SCRIPTS
###############################################################################

log "Installing openNDS helper scripts"

for FILE in \
    custombinauth.sh \
    portal-tc-init.sh \
    portal-tc-add.sh \
    portal-tc-del.sh
do

    SOURCE_FILE="$PAYLOAD/opennds/lib/opennds/$FILE"
    DEST_FILE="/usr/lib/opennds/$FILE"

    cp \
        "$SOURCE_FILE" \
        "$DEST_FILE"

    sed -i \
        "s|__PORTAL_INTERFACE__|$(escape_sed "$PORTAL_INTERFACE")|g" \
        "$DEST_FILE"

    chmod 755 "$DEST_FILE"

done

###############################################################################
# CONFIGURE BINAUTH DATABASE FILE
###############################################################################

log "Creating portal configuration files"

cat > /etc/portal/binauth_db.cnf <<EOF
[client]
user=portal_binauth
password=${BINAUTH_DB_PASS}
host=127.0.0.1
EOF

printf '%s\n' \
    "$RADIUS_SECRET" \
    > /etc/portal/binauth_radius_secret

###############################################################################
# CREATE FAS ENVIRONMENT
###############################################################################

cat > /etc/portal/fas.env <<EOF
FAS_KEY=${FAS_KEY}

NDS_GATEWAY_PORT=${GATEWAY_PORT}

PORTAL_DB_HOST=127.0.0.1
PORTAL_DB_USER=portal_fas
PORTAL_DB_PASS=${PORTAL_DB_PASS}
PORTAL_DB_NAME=portal

RADIUS_SERVER=127.0.0.1
RADIUS_SECRET=${RADIUS_SECRET}
RADIUS_NAS_IDENTIFIER=opennds-fas

FAS_STATUS_URL=${FAS_STATUS_URL}

NDSCTL_BIN=/usr/bin/ndsctl
EOF

###############################################################################
# CREATE DASHBOARD ENVIRONMENT
###############################################################################

cat > /etc/portal/dashboard.env <<EOF
DASHBOARD_SECRET_KEY=${DASH_SECRET}

PORTAL_DB_HOST=127.0.0.1
PORTAL_DB_USER=portal_dashboard
PORTAL_DB_PASS=${PORTAL_DB_PASS}

NDSCTL_BIN=/usr/bin/ndsctl
EOF

###############################################################################
# CREATE RADIUS DICTIONARY
###############################################################################

mkdir -p /etc/portal/fas

cat > /etc/portal/fas/dictionary <<EOF
ATTRIBUTE   User-Name              1   string
ATTRIBUTE   User-Password          2   string
ATTRIBUTE   Framed-IP-Address      8   ipaddr
ATTRIBUTE   NAS-IP-Address         4   ipaddr
ATTRIBUTE   NAS-Port               5   integer
ATTRIBUTE   Service-Type           6   integer
ATTRIBUTE   Calling-Station-Id     31  string
ATTRIBUTE   NAS-Identifier         32  string
ATTRIBUTE   Acct-Status-Type       40  integer
ATTRIBUTE   Acct-Input-Octets      42  integer
ATTRIBUTE   Acct-Output-Octets     43  integer
ATTRIBUTE   Acct-Session-Id        44  string
ATTRIBUTE   Acct-Session-Time      46  integer
ATTRIBUTE   Acct-Terminate-Cause   49  integer
ATTRIBUTE   Message-Authenticator  80  octets
EOF

###############################################################################
# SECURE CONFIGURATION FILES
###############################################################################

chmod 600 \
    /etc/portal/fas.env \
    /etc/portal/dashboard.env \
    /etc/portal/binauth_db.cnf \
    /etc/portal/binauth_radius_secret

chmod 644 \
    /etc/portal/fas/dictionary

chown \
    root:root \
    /etc/portal/fas.env \
    /etc/portal/dashboard.env \
    /etc/portal/binauth_db.cnf \
    /etc/portal/binauth_radius_secret

###############################################################################
# CONFIGURE DEFAULT BINAUTH LOGGER HOOK
###############################################################################

log "Configuring openNDS binauth hook"

BINAUTH_LOG="/usr/lib/opennds/binauth_log.sh"

if [[ -f "$BINAUTH_LOG" ]]; then

    if ! grep -q \
        '/usr/lib/opennds/custombinauth.sh' \
        "$BINAUTH_LOG"
    then

        cp \
            "$BINAUTH_LOG" \
            "${BINAUTH_LOG}.portal-orig"

        cat >> "$BINAUTH_LOG" <<'EOF'

# WiFi Portal accounting and traffic shaping hook
/usr/lib/opennds/custombinauth.sh "$@" || true
EOF

    fi

else

    warn "Default binauth_log.sh not found."

fi

###############################################################################
# INSTALL SYSTEMD SERVICES
###############################################################################

log "Installing systemd services"

install \
    -m 644 \
    "$SYSTEMD/opennds.service" \
    /etc/systemd/system/opennds.service

install \
    -m 644 \
    "$SYSTEMD/portal-tc-init.service" \
    /etc/systemd/system/portal-tc-init.service

###############################################################################
# INSTALL SUDOERS RULE
###############################################################################

if [[ -f "$PAYLOAD/portal-ndsctl" ]]; then

    log "Installing dashboard ndsctl sudo rule"

    install \
        -m 440 \
        "$PAYLOAD/portal-ndsctl" \
        /etc/sudoers.d/portal-ndsctl

    visudo \
        -cf \
        /etc/sudoers.d/portal-ndsctl \
        || die "Invalid sudoers configuration"

fi

###############################################################################
# CONFIGURE PORTAL SERVICES
###############################################################################

log "Configuring portal services"

FAS_SERVICE_SOURCE="$SYSTEMD/portal-fas.service"
DASH_SERVICE_SOURCE="$SYSTEMD/portal-dashboard.service"

[[ -f "$FAS_SERVICE_SOURCE" ]] \
    || die "Missing portal-fas.service"

[[ -f "$DASH_SERVICE_SOURCE" ]] \
    || die "Missing portal-dashboard.service"

sed \
    "s/0\.0\.0\.0:2080/0.0.0.0:${FAS_PORT}/g" \
    "$FAS_SERVICE_SOURCE" \
    | sed "s/-w 2/-w ${GUNICORN_WORKERS} --timeout ${GUNICORN_TIMEOUT}/" \
    > /etc/systemd/system/portal-fas.service

sed \
    "s/127\.0\.0\.1:8090/${DASHBOARD_BIND_IP}:${DASHBOARD_PORT}/g" \
    "$DASH_SERVICE_SOURCE" \
    | sed "s/-w 2/-w ${GUNICORN_WORKERS} --timeout ${GUNICORN_TIMEOUT}/" \
    > /etc/systemd/system/portal-dashboard.service

###############################################################################
# INITIALIZE DASHBOARD ADMIN
###############################################################################

log "Initializing dashboard administrator"

HASH=$(
    /opt/portal/venv/bin/python \
    - "$DASH_PASSWORD" <<'PY'
import sys
from werkzeug.security import generate_password_hash

print(generate_password_hash(sys.argv[1]))
PY
)

ESCAPED_ADMIN=$(
    printf '%s' "$DASH_ADMIN" \
    | sed "s/'/''/g"
)

ESCAPED_HASH=$(
    printf '%s' "$HASH" \
    | sed "s/'/''/g"
)

mysql portal <<SQL

INSERT INTO dashboard_admins
(
    username,
    password_hash,
    role
)
VALUES
(
    '${ESCAPED_ADMIN}',
    '${ESCAPED_HASH}',
    'admin'
)
ON DUPLICATE KEY UPDATE
    password_hash=VALUES(password_hash),
    role='admin';

SQL

###############################################################################
# CONFIGURE SYSTEMD DEPENDENCIES
###############################################################################

log "Reloading systemd"

systemctl daemon-reload

systemctl enable \
    mariadb \
    freeradius \
    dnsmasq \
    portal-tc-init \
    portal-fas \
    portal-dashboard \
    opennds

###############################################################################
# START SERVICES
###############################################################################

log "Starting MariaDB"

systemctl restart mariadb

log "Starting FreeRADIUS"

systemctl restart freeradius

log "Starting dnsmasq"

systemctl restart dnsmasq

log "Starting Portal Traffic Shaping"

systemctl restart portal-tc-init

log "Starting Portal FAS"

systemctl restart portal-fas

log "Starting Portal Dashboard"

systemctl restart portal-dashboard

log "Starting openNDS"

systemctl restart opennds

sleep 3

###############################################################################
# VERIFY SERVICES
###############################################################################

echo
echo "============================================="
echo " Service Status"
echo "============================================="
echo

SERVICES=(
    mariadb
    freeradius
    dnsmasq
    pihole-FTL
    portal-nat
    portal-tc-init
    portal-fas
    portal-dashboard
    opennds
)

for SERVICE in "${SERVICES[@]}"; do

    if systemctl is-active --quiet "$SERVICE"; then

        printf "  %-24s active\n" "$SERVICE:"

    else

        printf "  %-24s FAILED\n" "$SERVICE:"
        journalctl \
            -u "$SERVICE" \
            -n 30 \
            --no-pager || true

    fi

done

###############################################################################
# CRITICAL CHECKS
###############################################################################

echo
echo "============================================="
echo " Network Verification"
echo "============================================="
echo

ip -4 addr show "$PORTAL_INTERFACE" || true

echo

echo "dnsmasq configuration:"
echo

cat "$DNSMASQ_PORTAL_CONF"

echo

echo "Pi-hole DNS check:"
echo

ss -lunp | grep ':53 ' || echo "WARNING: nothing listening on port 53"

dig +short +time=3 example.com "@${PORTAL_GATEWAY}" \
    || echo "WARNING: Pi-hole is not resolving queries at ${PORTAL_GATEWAY}"

echo

echo "openNDS status:"
echo

if command_exists ndsctl; then

    ndsctl status || true

fi

echo

echo "Traffic shaping interface:"
echo

ip link show ifb0 2>/dev/null \
    || echo "ifb0 not currently available"

###############################################################################
# FINAL VALIDATION
###############################################################################

systemctl is-active --quiet mariadb \
    || die "MariaDB is not running"

systemctl is-active --quiet freeradius \
    || die "FreeRADIUS is not running"

systemctl is-active --quiet dnsmasq \
    || die "dnsmasq is not running"

systemctl is-active --quiet pihole-FTL \
    || die "Pi-hole is not running"

systemctl is-active --quiet portal-nat \
    || die "Portal NAT masquerade is not running"

systemctl is-active --quiet portal-fas \
    || die "Portal FAS is not running"

systemctl is-active --quiet portal-dashboard \
    || die "Portal Dashboard is not running"

systemctl is-active --quiet opennds \
    || die "openNDS is not running"

###############################################################################
# INSTALLATION COMPLETE
###############################################################################

cat <<EOF

=============================================
 Installation Complete
=============================================

Portal Interface : ${PORTAL_INTERFACE}
Portal Gateway   : ${PORTAL_CIDR}
DHCP Range       : ${DHCP_START} - ${DHCP_END}

Gateway Name     : ${GATEWAY_NAME}
Gateway Port     : ${GATEWAY_PORT}

FAS Port         : ${FAS_PORT}
FAS URL          : http://${PORTAL_GATEWAY}:${FAS_PORT}/fas/login

Dashboard Port   : ${DASHBOARD_PORT}
Dashboard Access : $(
    if [[ "$DASHBOARD_BIND_IP" == "127.0.0.1" ]]; then
        echo "http://127.0.0.1:${DASHBOARD_PORT} (localhost only -- use: ssh -L ${DASHBOARD_PORT}:127.0.0.1:${DASHBOARD_PORT} <user>@<this-server>)"
    else
        echo "http://${DASHBOARD_BIND_IP}:${DASHBOARD_PORT}"
    fi
)

Pi-hole Admin    : http://${PORTAL_GATEWAY}/admin
Pi-hole Password : ${PIHOLE_ADMIN_PASS}
Pi-hole Upstream : ${PIHOLE_UPSTREAM_DNS}

Gunicorn Workers : ${GUNICORN_WORKERS} per service (portal-fas, portal-dashboard)
Gunicorn Timeout : ${GUNICORN_TIMEOUT}s per worker

Services:

  mariadb
  freeradius
  dnsmasq
  pihole-FTL
  portal-nat
  portal-tc-init
  portal-fas
  portal-dashboard
  opennds


Run diagnostics:

  sudo bash ${SCRIPT_DIR}/diagnostics.sh


IMPORTANT:

1. Connect a test device to the portal-side network.

2. Verify it receives an IP address in:

   ${DHCP_START} - ${DHCP_END}

3. Verify gateway:

   ${PORTAL_GATEWAY}

4. Check:

   sudo ndsctl status

5. Check DHCP leases:

   cat /var/lib/misc/dnsmasq.leases


Production network architecture:

   Internet
      |
   ${UPSTREAM_INTERFACE}
      |
   Server
      |
   ${PORTAL_INTERFACE}
      |
   ${PORTAL_GATEWAY}/${PORTAL_PREFIX}
      |
   Captive Portal Clients

EOF