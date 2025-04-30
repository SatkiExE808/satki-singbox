#!/bin/bash

# Self-install as /usr/local/bin/satki if not already running as that
if [[ "$0" != "/usr/local/bin/satki" ]]; then
    echo "Installing as /usr/local/bin/satki..."
    sudo cp "$0" /usr/local/bin/satki
    sudo chmod +x /usr/local/bin/satki
    echo "Launching satki..."
    exec /usr/local/bin/satki
    exit 0
fi

SINGBOX_BIN="/usr/local/bin/sing-box"
SERVICE_FILE="/etc/systemd/system/sing-box.service"
CONFIG_DIR="/usr/local/etc/sing-box"
CONFIG_PATH="$CONFIG_DIR/config.json"
CERT_PATH="$CONFIG_DIR/singbox_cert.pem"
KEY_PATH="$CONFIG_DIR/singbox_key.pem"

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Ensure jq is installed
if ! command -v jq &>/dev/null; then
    echo "jq is required for this script. Installing..."
    sudo apt-get update && sudo apt-get install -y jq
fi

# Function to install sing-box
install_singbox() {
    echo "Installing sing-box..."
    latest_url=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest | grep browser_download_url | grep linux-amd64 | grep -v .sig | cut -d '"' -f 4 | head -n 1)
    if [ -z "$latest_url" ]; then
        echo "Failed to fetch sing-box download URL."
        return
    fi
    tmpdir=$(mktemp -d)
    cd "$tmpdir"
    wget "$latest_url" -O sing-box.tar.gz
    tar -xzf sing-box.tar.gz
    chmod +x sing-box*/sing-box
    sudo mv sing-box*/sing-box $SINGBOX_BIN
    sudo chmod +x $SINGBOX_BIN
    cd ~
    rm -rf "$tmpdir"
    echo "sing-box installed at $SINGBOX_BIN"

    # Create a basic systemd service if not exists
    if [ ! -f "$SERVICE_FILE" ]; then
        sudo bash -c "cat > $SERVICE_FILE" <<EOF
[Unit]
Description=sing-box Service
After=network.target

[Service]
Type=simple
ExecStart=$SINGBOX_BIN run -c $CONFIG_PATH
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
        sudo systemctl daemon-reload
        echo "Systemd service created at $SERVICE_FILE"
    fi
}

# Function to uninstall sing-box
uninstall_singbox() {
    echo "Uninstalling sing-box..."
    sudo systemctl stop sing-box 2>/dev/null
    sudo systemctl disable sing-box 2>/dev/null
    sudo rm -f $SINGBOX_BIN
    sudo rm -f $SERVICE_FILE
    sudo rm -rf $CONFIG_DIR
    sudo systemctl daemon-reload
    echo "sing-box and its service have been removed."
}

# Function to check sing-box status
check_status() {
    if [ -f "$SERVICE_FILE" ]; then
        sudo systemctl status sing-box
    else
        echo "sing-box service is not installed."
    fi
}

# Function to start sing-box
start_singbox() {
    if [ -f "$SERVICE_FILE" ]; then
        sudo systemctl start sing-box
        echo "sing-box service started."
    else
        echo "sing-box service is not installed."
    fi
}

# Function to allow port in UFW
allow_port() {
    local port=$1
    sudo ufw allow $port/tcp
    sudo ufw allow $port/udp
    echo "Port $port (TCP/UDP) allowed in UFW."
}

# Function to ensure config exists and is valid JSON
ensure_config() {
    sudo mkdir -p "$CONFIG_DIR"
    if [ ! -f "$CONFIG_PATH" ]; then
        echo '{"inbounds":[],"outbounds":[{"type":"direct"}]}' | sudo tee "$CONFIG_PATH" >/dev/null
    fi
}

# Function to get the next available port
get_next_port() {
    local start_port=30000
    local end_port=40000
    ensure_config
    # Get all used ports
    local used_ports
    used_ports=$(sudo jq '.inbounds[].listen_port' "$CONFIG_PATH" 2>/dev/null | sort -n)
    for ((port=$start_port; port<=$end_port; port++)); do
        if ! echo "$used_ports" | grep -q "^$port$"; then
            echo "$port"
            return
        fi
    done
    echo "No available ports in range $start_port-$end_port!" >&2
    exit 1
}

# Function to generate a self-signed certificate if not exists
ensure_cert() {
    if [ ! -f "$CERT_PATH" ] || [ ! -f "$KEY_PATH" ]; then
        echo "Generating self-signed certificate for TLS protocols..."
        sudo openssl req -x509 -newkey rsa:2048 -days 365 -nodes \
            -keyout "$KEY_PATH" -out "$CERT_PATH" \
            -subj "/CN=localhost"
    fi
}

# Function to add inbound to config.json
add_inbound() {
    local inbound_json="$1"
    ensure_config
    # Use jq to append the inbound to the inbounds array
    sudo jq --argjson inbound "$inbound_json" '.inbounds += [$inbound]' "$CONFIG_PATH" | \
        sudo tee "$CONFIG_PATH.tmp" >/dev/null
    sudo mv "$CONFIG_PATH.tmp" "$CONFIG_PATH"
}

# Function to generate sing-box config and show link
generate_config() {
    local protocol=$1
    local port=$2
    local uuid password method link inbound_json
    local ipaddr
    ipaddr=$(curl -4s ifconfig.me)

    case $protocol in
        vless)
            uuid=$(uuidgen)
            inbound_json=$(cat <<EOF
{
    "type": "vless",
    "listen": "0.0.0.0",
    "listen_port": $port,
    "users": [{
        "uuid": "$uuid"
    }]
}
EOF
)
            link="vless://$uuid@$ipaddr:$port"
            ;;
        vmess)
            uuid=$(uuidgen)
            inbound_json=$(cat <<EOF
{
    "type": "vmess",
    "listen": "0.0.0.0",
    "listen_port": $port,
    "users": [{
        "uuid": "$uuid"
    }]
}
EOF
)
            link="vmess://$uuid@$ipaddr:$port"
            ;;
        trojan)
            password=$(openssl rand -hex 8)
            ensure_cert
            inbound_json=$(cat <<EOF
{
    "type": "trojan",
    "listen": "0.0.0.0",
    "listen_port": $port,
    "users": [{
        "password": "$password"
    }],
    "tls": {
        "enabled": true,
        "certificate_path": "$CERT_PATH",
        "key_path": "$KEY_PATH"
    }
}
EOF
)
            link="trojan://$password@$ipaddr:$port"
            ;;
        shadowsocks)
            password=$(openssl rand -hex 16)
            method="aes-256-gcm"
            inbound_json=$(cat <<EOF
{
    "type": "shadowsocks",
    "listen": "0.0.0.0",
    "listen_port": $port,
    "method": "$method",
    "password": "$password"
}
EOF
)
            base64link=$(echo -n "$method:$password@$ipaddr:$port" | base64 -w 0)
            link="ss://$base64link"
            ;;
        hysteria)
            password=$(openssl rand -hex 8)
            ensure_cert
            inbound_json=$(cat <<EOF
{
    "type": "hysteria2",
    "listen": "0.0.0.0",
    "listen_port": $port,
    "users": [{
        "password": "$password"
    }],
    "tls": {
        "enabled": true,
        "certificate_path": "$CERT_PATH",
        "key_path": "$KEY_PATH"
    }
}
EOF
)
            link="hy2://$password@$ipaddr:$port"
            ;;
        *)
            echo "Unsupported protocol."
            return 1
            ;;
    esac

    echo "Adding config to $CONFIG_PATH and restarting sing-box service..."
    add_inbound "$inbound_json"
    sudo systemctl restart sing-box
    sleep 1
    sudo systemctl status sing-box --no-pager

    echo "Connection link:"
    echo "$link"
}

# Function to list all configs with links
list_inbounds() {
    ensure_config
    local ipaddr
    ipaddr=$(curl -4s ifconfig.me)
    echo "==== List of All Created Configs ===="
    sudo jq -r --arg ip "$ipaddr" '
        .inbounds[] |
        "Protocol: \(.type)\nPort: \(.listen_port)\n" +
        (if .type == "vless" then
            "UUID: \(.users[0].uuid)\nLink: vless://\(.users[0].uuid)@" + $ip + ":" + (.listen_port|tostring) + "\n"
         elif .type == "vmess" then
            "UUID: \(.users[0].uuid)\nLink: vmess://\(.users[0].uuid)@" + $ip + ":" + (.listen_port|tostring) + "\n"
         elif .type == "trojan" then
            "Password: \(.users[0].password)\nLink: trojan://\(.users[0].password)@" + $ip + ":" + (.listen_port|tostring) + "\n"
         elif .type == "shadowsocks" then
            "Method: \(.method)\nPassword: \(.password)\nLink: ss://" +
            (("\(.method):\(.password)@" + $ip + ":" + (.listen_port|tostring)) | @base64) + "\n"
         elif .type == "hysteria2" then
            "Password: \(.users[0].password)\nLink: hy2://\(.users[0].password)@" + $ip + ":" + (.listen_port|tostring) + "\n"
         else
            ""
         end) + "------------------------"
    ' "$CONFIG_PATH"
}

# Function to remove a config
remove_inbound() {
    ensure_config
    local count
    count=$(sudo jq '.inbounds | length' "$CONFIG_PATH")
    if [ "$count" -eq 0 ]; then
        echo "No configs to remove."
        return
    fi

    echo "==== List of Configs ===="
    sudo jq -r '
        .inbounds
        | to_entries[]
        | "\(.key): Protocol: \(.value.type), Port: \(.value.listen_port)" +
          (if .value.type == "vless" or .value.type == "vmess" then
              ", UUID: \(.value.users[0].uuid)"
           elif .value.type == "trojan" then
              ", Password: \(.value.users[0].password)"
           elif .value.type == "shadowsocks" then
              ", Method: \(.value.method), Password: \(.value.password)"
           elif .value.type == "hysteria2" then
              ", Password: \(.value.users[0].password)"
           else
              ""
           end)
    ' "$CONFIG_PATH"

    read -p "Enter the number of the config to remove: " idx
    if ! [[ "$idx" =~ ^[0-9]+$ ]] || [ "$idx" -ge "$count" ]; then
        echo "Invalid selection."
        return
    fi

    sudo jq "del(.inbounds[$idx])" "$CONFIG_PATH" | sudo tee "$CONFIG_PATH.tmp" >/dev/null
    sudo mv "$CONFIG_PATH.tmp" "$CONFIG_PATH"
    echo "Config removed."
    sudo systemctl restart sing-box
    sleep 1
    sudo systemctl status sing-box --no-pager
}

# Main menu
while true; do
    clear
    echo -e "${GREEN}==== Satki Singbox Menu ====${NC}"

    echo -e "${YELLOW}--- Sing-box Service Management ---${NC}"
    echo -e "${CYAN} 1.${NC} Install sing-box         ${CYAN}(Download and install sing-box binary)"
    echo -e "${CYAN} 2.${NC} Uninstall sing-box       ${CYAN}(Remove sing-box and all configs)"
    echo -e "${CYAN} 3.${NC} Start sing-box           ${CYAN}(Start the sing-box service)"
    echo -e "${CYAN} 4.${NC} Check sing-box status    ${CYAN}(Show sing-box service status)"
    echo

    echo -e "${YELLOW}--- Add New Protocol ---${NC}"
    echo -e "${CYAN} 5.${NC} Add VLESS               ${CYAN}(Auto-port, UUID, no TLS)"
    echo -e "${CYAN} 6.${NC} Add VMess               ${CYAN}(Auto-port, UUID, no TLS)"
    echo -e "${CYAN} 7.${NC} Add Trojan              ${CYAN}(Auto-port, password, TLS enabled)"
    echo -e "${CYAN} 8.${NC} Add Shadowsocks         ${CYAN}(Auto-port, AES-256-GCM)"
    echo -e "${CYAN} 9.${NC} Add Hysteria2           ${CYAN}(Auto-port, password, TLS enabled)"
    echo

    echo -e "${YELLOW}--- Config Management ---${NC}"
    echo -e "${CYAN}10.${NC} List all configs        ${CYAN}(Show all created configs and links)"
    echo -e "${CYAN}11.${NC} Remove a config         ${CYAN}(Delete a config by number)"
    echo

    echo -e "${CYAN}12.${NC} Exit"
    echo

    read -p "Select an option [1-12]: " choice

    case $choice in
        1)
            install_singbox
            ;;
        2)
            uninstall_singbox
            ;;
        3)
            start_singbox
            ;;
        4)
            check_status
            ;;
        5)
            protocol="vless"
            port=$(get_next_port)
            echo "Auto-selected port: $port"
            generate_config $protocol $port
            allow_port $port
            ;;
        6)
            protocol="vmess"
            port=$(get_next_port)
            echo "Auto-selected port: $port"
            generate_config $protocol $port
            allow_port $port
            ;;
        7)
            protocol="trojan"
            port=$(get_next_port)
            echo "Auto-selected port: $port"
            generate_config $protocol $port
            allow_port $port
            ;;
        8)
            protocol="shadowsocks"
            port=$(get_next_port)
            echo "Auto-selected port: $port"
            generate_config $protocol $port
            allow_port $port
            ;;
        9)
            protocol="hysteria"
            port=$(get_next_port)
            echo "Auto-selected port: $port"
            generate_config $protocol $port
            allow_port $port
            ;;
        10)
            list_inbounds
            ;;
        11)
            remove_inbound
            ;;
        12)
            echo "Goodbye!"
            exit 0
            ;;
        *)
            echo "Invalid option."
            ;;
    esac
    echo
    read -p "Press Enter to return to the main menu..."
done