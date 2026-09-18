#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PAYLOAD="$SCRIPT_DIR/payload"
DATABASE="$SCRIPT_DIR/database"
SYSTEMD="$SCRIPT_DIR/systemd"
log(){ echo -e "\n[+] $*"; }
warn(){ echo -e "\n[!] $*" >&2; }
die(){ echo -e "\n[ERROR] $*" >&2; exit 1; }
require_root(){ [[ ${EUID:-$(id -u)} -eq 0 ]] || die "Run as root: sudo bash install.sh"; }
random_secret(){ openssl rand -hex 32; }
escape_sed(){ printf '%s' "$1" | sed 's/[&|\\]/\\&/g'; }
