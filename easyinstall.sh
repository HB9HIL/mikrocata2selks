#!/bin/bash
# easyinstall.sh - Install, update or uninstall Mikrocata for Clean NDR
set -euo pipefail
shopt -s nullglob

REPO_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
LIB_DIR=/usr/local/lib/mikrocata
CONF_DIR=/etc/mikrocata
UNIT_DIR=/etc/systemd/system
NETWORK_DIR=/etc/systemd/network
BASE_PORT=37008
TZSP2PCAP_COMMIT=4fb8147c15ad5fcf887a8e880d40596c955fbead

check_os() {
    . /etc/os-release
    if [[ "${ID:-}" != "debian" || ! "${VERSION_ID:-}" =~ ^(12|13)$ ]]; then
        echo "Warning: Only Debian 12 and 13 are supported, found ${PRETTY_NAME:-unknown}."
        read -r -p "Continue anyway? [y/N] " reply
        [[ $reply =~ ^[Yy]$ ]] || exit 1
    fi
}

install_dependencies() {
    echo "--- Install required package ---"
    apt-get install ca-certificates curl wget unzip tcpdump tcpreplay gnupg lsb-release build-essential python3-pyinotify python3-librouteros python3-requests git htop libpcap-dev -y
}

install_docker() {
    if ! docker -v &>/dev/null; then
        echo "--- Installing docker ---"
        curl -fsSL https://get.docker.com/ | sh
    else
        echo "--- Docker already installed ---"
    fi
}

install_tzsp2pcap() {
    if [ -x /usr/local/bin/tzsp2pcap ]; then
        echo "--- tzsp2pcap already installed ---"
        return
    fi
    echo "--- Install packet sniffer interface ---"
    wget -O /opt/tzsp2pcap.tar.gz "https://github.com/thefloweringash/tzsp2pcap/archive/$TZSP2PCAP_COMMIT.tar.gz"
    tar -xzf /opt/tzsp2pcap.tar.gz -C /opt
    make -C "/opt/tzsp2pcap-$TZSP2PCAP_COMMIT"
    make -C "/opt/tzsp2pcap-$TZSP2PCAP_COMMIT" install
}

# Code and units only, never touches the configuration in $CONF_DIR
install_files() {
    echo "--- Installing Mikrocata files ---"
    install -D -m 0755 "$REPO_DIR/mikrocata.py" "$LIB_DIR/mikrocata.py"
    install -m 0644 "$REPO_DIR/mikrocata@.service" "$REPO_DIR/tzsp-replay@.service" "$UNIT_DIR/"
    install -d -m 0700 "$CONF_DIR"
    systemctl daemon-reload
}

write_netdev() {
    local iface=$1 address=$2
    cat > "$NETWORK_DIR/$iface.netdev" <<EOF
[NetDev]
Name=$iface
Kind=dummy
EOF
    cat > "$NETWORK_DIR/$iface.network" <<EOF
[Match]
Name=$iface

[Link]
MTUBytes=2000

[Network]
Address=$address
DHCP=no
EOF
}

# set_env FILE KEY VALUE - replace the KEY= line in an env file
set_env() {
    sed -i "s|^$2=.*|$2=\"$3\"|" "$1"
}

setup_instance() {
    local iface=$1 ndr_path=$2
    local n=${iface#tzsp}
    local env="$CONF_DIR/$iface.env"

    echo "--- Creating interface $iface ---"
    write_netdev "$iface" "192.168.$((250 + n)).10/24"
    systemctl enable systemd-networkd
    systemctl restart systemd-networkd

    if [ ! -f "$env" ]; then
        install -m 0600 "$REPO_DIR/mikrocata.env.example" "$env"
        set_env "$env" TZSP_PORT "$((BASE_PORT + n))"
        set_env "$env" NDR_SURICATA_LOG_PATH "$ndr_path/config/containers-data/suricata/logs/"
    fi

    systemctl enable --now "tzsp-replay@$iface.service" "mikrocata@$iface.service"
}

# Convert the settings of a v4 script into an env file.
# legacy_env OLD_SCRIPT ENV_FILE TZSP_PORT
legacy_env() {
    python3 - "$@" <<'EOF'
import os, re, sys

src, dst, port = sys.argv[1:]
text = open(src).read()
block = text.split("START EDIT SETTINGS", 1)[1].split("END EDIT SETTINGS", 1)[0]
path = re.search(r"^(NDR_SURICATA_LOG_PATH|SELKS_CONTAINER_DATA_SURICATA_LOG)\s*=.*$", text, re.M)
s = {}
# The settings block holds only literal assignments
exec(block + "\n" + (path.group(0) if path else ""), s)

proxy = ""
if s.get("TELEGRAM_PROXY_ENABLED") and s.get("TELEGRAM_PROXY", {}).get("https") != "http://user:pass@domain:port":
    proxy = s["TELEGRAM_PROXY"].get("https", "")

def as_list(value):
    return ",".join(item for item in ((value,) if isinstance(value, str) else value) if item != "yourpublicip")

values = {
    "TZSP_PORT": port,
    "NDR_SURICATA_LOG_PATH": s.get("NDR_SURICATA_LOG_PATH", s.get("SELKS_CONTAINER_DATA_SURICATA_LOG", "/root/NDR/config/containers-data/suricata/logs/")),
    "ROUTER_IP": s.get("ROUTER_IP", ""),
    "USERNAME": s.get("USERNAME", ""),
    "PASSWORD": s.get("PASSWORD", ""),
    "USE_SSL": s.get("USE_SSL", False),
    "ALLOW_SELF_SIGNED_CERTS": s.get("ALLOW_SELF_SIGNED_CERTS", False),
    "BLOCK_LIST_NAME": s.get("BLOCK_LIST_NAME", "Suricata"),
    "TIMEOUT": s.get("TIMEOUT", "1d"),
    "SEVERITY": as_list(s.get("SEVERITY", ("1", "2"))),
    "WHITELIST_IPS": as_list(s.get("WHITELIST_IPS", ())),
    "ENABLE_IPV6": s.get("ENABLE_IPV6", False),
    "TIMEZONE_OFFSET": s.get("TIMEZONE_OFFSET", 0),
    "COMMENT_TIME_FORMAT": s.get("COMMENT_TIME_FORMAT", "%-d %b %Y %H:%M:%S.%f"),
    "ENABLE_TELEGRAM": s.get("enable_telegram", False),
    "TELEGRAM_TOKEN": s.get("TELEGRAM_TOKEN", ""),
    "TELEGRAM_CHATID": s.get("TELEGRAM_CHATID", ""),
    "TELEGRAM_HEADER": s.get("TELEGRAM_HEADER", "\U0001F43F Suricata ALERT:"),
    "TELEGRAM_PROXY_URL": proxy,
    "DEBUG_MODE": s.get("DEBUG_MODE", False),
}

def quote(value):
    if isinstance(value, bool):
        value = "true" if value else "false"
    value = str(value)
    for char in '\\"$`':
        value = value.replace(char, "\\" + char)
    return f'"{value}"'

os.umask(0o077)
with open(dst, "w") as f:
    f.write(f"# Migrated from {src} by easyinstall.sh, see mikrocata.env.example for documentation\n")
    for key, value in values.items():
        f.write(f"{key}={quote(value)}\n")
print(f"--- Settings migrated to {dst} ---")
EOF
}

# Stop and remove the per-instance copies created by installers up to v4.x
remove_legacy_instance() {
    local n=$1 port=$((BASE_PORT + $1))
    systemctl disable --now "mikrocataTZSP$n.service" "TZSPreplay$port@tzsp$n.service" || true
    rm -f "/usr/local/bin/mikrocataTZSP$n.py" "$UNIT_DIR/mikrocataTZSP$n.service" "$UNIT_DIR/TZSPreplay$port@.service"
    systemctl daemon-reload
}

migrate_legacy() {
    local old n
    for old in /usr/local/bin/mikrocataTZSP*.py; do
        n=${old#/usr/local/bin/mikrocataTZSP}
        n=${n%.py}
        echo "--- Migrating legacy instance tzsp$n ---"
        [ -f "$CONF_DIR/tzsp$n.env" ] || legacy_env "$old" "$CONF_DIR/tzsp$n.env" "$((BASE_PORT + n))"
        remove_legacy_instance "$n"
        systemctl enable --now "tzsp-replay@tzsp$n.service" "mikrocata@tzsp$n.service"
    done
}

install_clean_ndr() {
    echo "--- Clean NDR Installer ---"
    check_os

    # Validate Clean NDR installation path
    while true; do
        read -e -p "Enter the installation path for Clean NDR: " -i "/root/NDR" PATH_NDR
        if [[ -n "$PATH_NDR" && "$PATH_NDR" =~ ^[a-zA-Z0-9/_.-]+$ ]]; then
            break
        else
            echo "Error: Please enter a valid path (no spaces or special characters except /, -, ., _)"
        fi
    done
    mkdir -p "$PATH_NDR"

    echo "--- DISCLAIMER: Only one Mikrotik device is officially supported. ---"
    echo "--- Multiple Mikrotik devices can be configured manually (will be documented in future updates). ---"
    sleep 3

    install_dependencies
    install_docker
    install_tzsp2pcap
    install_files
    setup_instance tzsp0 "$PATH_NDR"

    echo "--- Installing Stamus Clean NDR ---"
    wget https://dl.clearndr.io/stamusctl-linux-amd64 -O /usr/local/bin/stamusctl
    chmod +x /usr/local/bin/stamusctl

    cd "$PATH_NDR"
    stamusctl compose init suricata.interfaces=tzsp0
    stamusctl config set suricata.interfaces=tzsp0
    stamusctl compose up -d

    echo "--- Clean NDR INSTALL COMPLETED ---"
    print_summary
}

update() {
    local legacy=(/usr/local/bin/mikrocataTZSP*.py)
    if [ ! -d "$LIB_DIR" ] && [ ${#legacy[@]} -eq 0 ]; then
        echo "Mikrocata is not installed, nothing to update."
        exit 1
    fi
    check_os

    echo "--- Updating Mikrocata ---"
    install_dependencies
    install_files
    migrate_legacy
    systemctl restart 'tzsp-replay@*.service' 'mikrocata@*.service'

    echo "--- UPDATE COMPLETED: $(grep -m1 '^VERSION' "$LIB_DIR/mikrocata.py") ---"
}

uninstall() {
    echo "--- Uninstalling all components ---"
    read -p "Are you sure you want to uninstall all components? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi

    local old n env iface
    for old in /usr/local/bin/mikrocataTZSP*.py; do
        n=${old#/usr/local/bin/mikrocataTZSP}
        n=${n%.py}
        echo "--- Removing legacy instance tzsp$n ---"
        remove_legacy_instance "$n"
        rm -f "$NETWORK_DIR/tzsp$n.netdev" "$NETWORK_DIR/tzsp$n.network"
    done

    for env in "$CONF_DIR"/*.env; do
        iface=$(basename "$env" .env)
        echo "--- Removing instance $iface ---"
        systemctl disable --now "mikrocata@$iface.service" "tzsp-replay@$iface.service" || true
        rm -f "$NETWORK_DIR/$iface.netdev" "$NETWORK_DIR/$iface.network"
    done

    rm -f "$UNIT_DIR/mikrocata@.service" "$UNIT_DIR/tzsp-replay@.service"
    rm -rf "$LIB_DIR" /var/lib/mikrocata

    read -p "Also remove the configuration in $CONF_DIR? [y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -rf "$CONF_DIR"
    fi

    # Uninstall Clean NDR with path validation
    while true; do
        read -e -p "Enter the installation path for Clean NDR that was used: " -i "/root/NDR" PATH_NDR
        if [[ -n "$PATH_NDR" && "$PATH_NDR" =~ ^[a-zA-Z0-9/_.-]+$ ]]; then
            break
        else
            echo "Error: Please enter a valid path (no spaces or special characters except /, -, ., _)"
        fi
    done
    if [ -d "$PATH_NDR" ]; then
        echo "--- Removing Clean NDR from $PATH_NDR ---"
        cd "$PATH_NDR"
        stamusctl compose down
        cd ..
        rm -rf "$PATH_NDR"
    else
        echo "--- Clean NDR directory not found at $PATH_NDR, skipping ---"
    fi

    rm -f /usr/local/bin/stamusctl

    # Remove downloaded sources, including those of installers up to v4.x
    echo "--- Removing downloaded tools ---"
    rm -rf /opt/tzsp2pcap-* /opt/tcpreplay-4.4.2
    rm -f /opt/tzsp2pcap.tar.gz /opt/master.zip /opt/tcpreplay-4.4.2.tar.gz

    # Reload systemd
    echo "--- Reloading systemd ---"
    systemctl daemon-reload
    systemctl restart systemd-networkd

    echo "--- UNINSTALL COMPLETED ---"
}

print_summary() {
    echo "--- "
    echo "--- "
    echo "#################################################################"
    echo "---            POST-INSTALLATION CONFIGURATION                ---"
    echo "#################################################################"
    echo ""
    echo "1. EDIT THE CONFIGURATION:"
    echo "   - File: $CONF_DIR/tzsp0.env"
    echo "   - Set your Mikrotik IP, Username, and Password."
    echo "   - Optionally set your Telegram Bot Token and Chat ID."
    echo ""
    echo "2. RESTART THE MIKROCATA SERVICE:"
    echo "   systemctl restart mikrocata@tzsp0.service"
    echo ""
    echo "3. CHECK SERVICE STATUS:"
    echo "   - Mikrocata: systemctl status mikrocata@tzsp0.service"
    echo "   - Interface: systemctl status tzsp-replay@tzsp0.service"
    echo ""
    echo "4. UPDATE LATER WITH:"
    echo "   git pull && ./easyinstall.sh update"
    echo ""
    echo "--- MIKROTIK ROUTER CONFIGURATION ---"
    echo "Remember to configure the following on your Mikrotik router:"
    echo "1. Enable the Sniffer to stream traffic to this server's IP on port $BASE_PORT."
    echo "2. Add the Firewall rules to block IPs found by Suricata."
    echo "3. Enable the API service and create a user for Mikrocata."
    echo "(See README.md for the exact commands)"
    echo ""
    echo "#################################################################"
    echo ""
}

case "${1:-}" in
    install) install_clean_ndr; exit 0 ;;
    update) update; exit 0 ;;
    uninstall) uninstall; exit 0 ;;
    "") ;;
    *) echo "Usage: $0 [install|update|uninstall]"; exit 1 ;;
esac

# --- Main Menu ---
while true; do
    clear
    echo "========================================"
    echo "   Mikrocata Clean NDR Installer"
    echo "========================================"
    echo "1. Install Clean NDR"
    echo "   (A free, open-source NDR solution.)"
    echo "   NOTE: SELKS repository has been removed by Stamus Networks."
    echo "   Only Clean NDR is now supported."
    echo ""
    echo "2. Update Mikrocata"
    echo "   (Keeps your configuration in $CONF_DIR.)"
    echo ""
    echo "3. Uninstall"
    echo "4. Exit"
    echo "========================================"
    read -p "Enter your choice [1-4]: " choice

    case $choice in
        1)
            install_clean_ndr
            break
            ;;
        2)
            update
            break
            ;;
        3)
            uninstall
            break
            ;;
        4)
            exit 0
            ;;
        *)
            echo "Error: Please enter a number between 1 and 4"
            sleep 2
            ;;
    esac
done
