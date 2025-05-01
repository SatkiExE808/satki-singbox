#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

CONFIG_DIR="/etc/sing-box"
INBOUNDS_DIR="$CONFIG_DIR/inbounds"
CLIENT_DIR="$CONFIG_DIR/clients"
mkdir -p "$INBOUNDS_DIR" "$CLIENT_DIR"

CERT_PATH=""
KEY_PATH=""

install_singbox() {
    echo "Installing sing-box..."
    if ! command -v sing-box &>/dev/null; then
        curl -L https://github.com/SagerNet/sing-box/releases/latest/download/sing-box-linux-amd64.zip -o /tmp/sing-box.zip
        unzip -o /tmp/sing-box.zip -d /usr/local/bin/
        chmod +x /usr/local/bin/sing-box
        sudo tee /etc/systemd/system/sing-box.service > /dev/null <<EOF
[Unit]
Description=sing-box Service
After=network.target

[Service]
ExecStart=/usr/local/bin/sing-box run -c $CONFIG_DIR/config.json
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
        sudo systemctl daemon-reload
        sudo systemctl enable sing-box
        echo "sing-box installed."
    else
        echo "sing-box already installed."
    fi
}

uninstall_singbox() {
    echo "Uninstalling sing-box..."
    sudo systemctl stop sing-box
    sudo systemctl disable sing-box
    sudo rm -f /etc/systemd/system/sing-box.service
    sudo rm -rf "$CONFIG_DIR"
    sudo rm -f /usr/local/bin/sing-box
    sudo systemctl daemon-reload
    echo "sing-box uninstalled."
}

start_singbox() {
    sudo systemctl start sing-box
    echo "sing-box started."
}

check_status() {
    sudo systemctl status sing-box --no-pager
}

fix_service_file() {
    echo "Fixing sing-box service file..."
    # Remove duplicate ExecStart lines, keep only the first
    sudo sed -i '/^ExecStart=/!b;n;d' /etc/systemd/system/sing-box.service
    sudo systemctl daemon-reload
    sudo systemctl restart sing-box
    echo "Service file fixed and sing-box restarted."
}

get_next_port() {
    local base_port=30000
    local port=$base_port
    while ss -ltn | grep -q ":$port "; do
        ((port++))
    done
    echo "$port"
}

allow_port() {
    local port=$1
    if command -v ufw &>/dev/null; then
        sudo ufw allow "$port"/tcp
        echo "Port $port allowed through ufw."
    elif command -v firewall-cmd &>/dev/null; then
        sudo firewall-cmd --add-port=${port}/tcp --permanent
        sudo firewall-cmd --reload
        echo "Port $port allowed through firewalld."
    else
        echo "No recognized firewall found. Please allow port $port manually."
    fi
}

generate_config() {
    local protocol="$1"
    local port="$2"
    local uuid
    uuid=$(cat /proc/sys/kernel/random/uuid)

    local config_file="$INBOUNDS_DIR/${protocol}_${port}.json"

    case "$protocol" in
        vless)
            cat > "$config_file" <<EOF
{
  "inbounds": [{
    "type": "vless",
    "listen": "0.0.0.0",
    "listen_port": $port,
    "users": [{
      "id": "$uuid"
    }],
    "transport": {
      "type": "ws",
      "path": "/vless"
    },
    "tls": {
      "enabled": false
    }
  }]
}
EOF
            ;;
        vmess)
            cat > "$config_file" <<EOF
{
  "inbounds": [{
    "type": "vmess",
    "listen": "0.0.0.0",
    "listen_port": $port,
    "users": [{
      "id": "$uuid"
    }],
    "tls": {
      "enabled": false
    }
  }]
}
EOF
            ;;
        shadowsocks)
            local password
            password=$(openssl rand -hex 8)
            cat > "$config_file" <<EOF
{
  "inbounds": [{
    "type": "shadowsocks",
    "listen": "0.0.0.0",
    "listen_port": $port,
    "method": "AES-256-GCM",
    "password": "$password",
    "tls": {
      "enabled": false
    }
  }]
}
EOF
            ;;
        *)
            echo "Unsupported protocol for generate_config: $protocol"
            return 1
            ;;
    esac

    echo "Config generated at $config_file"
    merge_configs
    echo "Restarting sing-box to apply changes..."
    sudo systemctl restart sing-box
}

add_inbound() {
    local inbound_json="$1"
    local filename="inbound_$(date +%s)_$RANDOM.json"
    local filepath="$INBOUNDS_DIR/$filename"

    echo "$inbound_json" > "$filepath"
    echo "Inbound config saved to $filepath"

    merge_configs

    echo "Restarting sing-box to apply changes..."
    sudo systemctl restart sing-box
}

merge_configs() {
    local merged_file="$CONFIG_DIR/config.json"
    local inbounds_json

    if compgen -G "$INBOUNDS_DIR/*.json" > /dev/null; then
        inbounds_json=$(jq -s '[.[][]]' "$INBOUNDS_DIR"/*.json)
        echo "{\"inbounds\":$inbounds_json}" > "$merged_file"
    else
        echo '{"inbounds":[]}' > "$merged_file"
    fi
}

list_inbounds() {
    echo "Listing all connection links with client configs and QR codes:"
    local i=1
    local ip
    ip=$(curl -4s ifconfig.me)

    mkdir -p "$CLIENT_DIR"

    if ! compgen -G "$INBOUNDS_DIR/*.json" > /dev/null; then
        echo "No inbound configs found."
        return
    fi

    for file in "$INBOUNDS_DIR"/*.json; do
        local type port id password method userinfo link client_file qr_file
        type=$(jq -r '.inbounds[0].type' "$file")
        port=$(jq -r '.inbounds[0].listen_port' "$file")

        case "$type" in
            vless)
                id=$(jq -r '.inbounds[0].users[0].id' "$file")
                link="vless://${id}@${ip}:${port}?type=ws&path=/vless#${type}_${port}"

                client_file="$CLIENT_DIR/vless_${port}_client.json"
                cat > "$client_file" <<EOF
{
  "outbounds": [{
    "type": "vless",
    "tag": "out-vless",
    "server": "${ip}",
    "server_port": ${port},
    "uuid": "${id}",
    "transport": {
      "type": "ws",
      "path": "/vless"
    },
    "tls": {
      "enabled": false
    }
  }]
}
EOF
                ;;
            vmess)
                id=$(jq -r '.inbounds[0].users[0].id' "$file")
                link="vmess://${id}@${ip}:${port}#${type}_${port}"

                client_file="$CLIENT_DIR/vmess_${port}_client.json"
                cat > "$client_file" <<EOF
{
  "outbounds": [{
    "type": "vmess",
    "tag": "out-vmess",
    "server": "${ip}",
    "server_port": ${port},
    "uuid": "${id}",
    "tls": {
      "enabled": false
    }
  }]
}
EOF
                ;;
            trojan|trojan-gfw)
                password=$(jq -r '.inbounds[0].users[0].password' "$file")
                link="trojan://${password}@${ip}:${port}#${type}_${port}"

                client_file="$CLIENT_DIR/${type}_${port}_client.json"
                cat > "$client_file" <<EOF
{
  "outbounds": [{
    "type": "${type}",
    "tag": "out-${type}",
    "server": "${ip}",
    "server_port": ${port},
    "password": "${password}",
    "tls": {
      "enabled": true
    }
  }]
}
EOF
                ;;
            shadowsocks)
                method=$(jq -r '.inbounds[0].method' "$file")
                password=$(jq -r '.inbounds[0].password' "$file")
                userinfo=$(echo -n "${method}:${password}" | base64 -w0)
                link="ss://${userinfo}@${ip}:${port}#${type}_${port}"

                client_file="$CLIENT_DIR/shadowsocks_${port}_client.json"
                cat > "$client_file" <<EOF
{
  "outbounds": [{
    "type": "shadowsocks",
    "tag": "out-ss",
    "server": "${ip}",
    "server_port": ${port},
    "method": "${method}",
    "password": "${password}",
    "udp": true
  }]
}
EOF
                ;;
            hysteria2)
                password=$(jq -r '.inbounds[0].users[0].password' "$file")
                link="hy2://${password}@${ip}:${port}#${type}_${port}"

                client_file="$CLIENT_DIR/hysteria2_${port}_client.json"
                cat > "$client_file" <<EOF
{
  "outbounds": [{
    "type": "hysteria2",
    "tag": "out-hysteria2",
    "server": "${ip}",
    "server_port": ${port},
    "password": "${password}",
    "tls": {
      "enabled": true
    }
  }]
}
EOF
                ;;
            socks)
                link="socks5://${ip}:${port}#${type}_${port}"

                client_file="$CLIENT_DIR/socks5_${port}_client.json"
                cat > "$client_file" <<EOF
{
  "outbounds": [{
    "type": "socks",
    "tag": "out-socks5",
    "server": "${ip}",
    "server_port": ${port},
    "udp": true
  }]
}
EOF
                ;;
            *)
                link="Unknown protocol in $file"
                client_file=""
                ;;
        esac

        echo -e "${YELLOW}$i)${NC} $link"

        # Generate QR code if qrencode is installed and link is valid
        if command -v qrencode &>/dev/null && [[ -n "$link" && "$link" != Unknown* ]]; then
            qr_file="$CLIENT_DIR/${type}_${port}_qrcode.png"
            qrencode -o "$qr_file" -t PNG "$link"
            echo "    Client config: $client_file"
            echo "    QR code saved to: $qr_file"
        else
            echo "    Client config: $client_file"
            echo "    QR code generation skipped (qrencode not installed or invalid link)."
        fi

        ((i++))
        echo
    done
}

remove_inbound() {
    list_inbounds
    read -p "Enter the number of the inbound to remove: " num
    local files=("$INBOUNDS_DIR"/*.json)
    if [[ -z "${files[$((num-1))]}" ]]; then
        echo "Invalid selection."
        return
    fi
    rm -f "${files[$((num-1))]}"
    echo "Inbound config removed."
    merge_configs
    sudo systemctl restart sing-box
}

ensure_certbot() {
    if ! command -v certbot &>/dev/null; then
        echo "Certbot not found. Installing..."
        if command -v apt &>/dev/null; then
            sudo apt update && sudo apt install -y certbot
        elif command -v yum &>/dev/null; then
            sudo yum install -y certbot
        else
            echo "Unsupported package manager. Please install certbot manually."
            exit 1
        fi

        if [[ $? -ne 0 ]]; then
            echo "Failed to install certbot. Please install it manually."
            exit 1
        fi
    fi
}

generate_selfsigned_cert() {
    CERT_PATH="$CONFIG_DIR/singbox_cert.pem"
    KEY_PATH="$CONFIG_DIR/singbox_key.pem"

    if [[ ! -f "$CERT_PATH" || ! -f "$KEY_PATH" ]]; then
        echo "Generating self-signed certificate for TLS protocols..."
        sudo openssl req -x509 -newkey rsa:2048 -days 365 -nodes \
            -keyout "$KEY_PATH" -out "$CERT_PATH" \
            -subj "/CN=localhost"
        if [[ $? -ne 0 ]]; then
            echo "Failed to generate self-signed certificate."
            exit 1
        fi
    else
        echo "Self-signed certificate already exists."
    fi
}

ensure_cert() {
    local TLS_MODE="$1"
    local LE_DOMAIN="$2"
    local LE_CERT_PATH=""
    local LE_KEY_PATH=""

    if [[ "$TLS_MODE" == "letsencrypt" ]]; then
        if [[ -z "$LE_DOMAIN" ]]; then
            echo "Error: Domain name cannot be empty for Let's Encrypt."
            echo "Falling back to self-signed certificate."
            generate_selfsigned_cert
            return
        fi

        LE_CERT_PATH="/etc/letsencrypt/live/$LE_DOMAIN/fullchain.pem"
        LE_KEY_PATH="/etc/letsencrypt/live/$LE_DOMAIN/privkey.pem"

        if [[ ! -f "$LE_CERT_PATH" || ! -f "$LE_KEY_PATH" ]]; then
            ensure_certbot
            echo "Attempting to obtain Let's Encrypt certificate for $LE_DOMAIN ..."
            sudo systemctl stop sing-box 2>/dev/null

            sudo certbot certonly --standalone --non-interactive --agree-tos \
                --register-unsafely-without-email -d "$LE_DOMAIN"
            local certbot_status=$?

            sudo systemctl start sing-box 2>/dev/null

            if [[ $certbot_status -ne 0 ]]; then
                echo "Certbot failed to obtain certificate. Falling back to self-signed."
                generate_selfsigned_cert
                return
            fi
        fi

        if [[ -f "$LE_CERT_PATH" && -f "$LE_KEY_PATH" ]]; then
            CERT_PATH="$LE_CERT_PATH"
            KEY_PATH="$LE_KEY_PATH"
            echo "Using Let's Encrypt certificate for TLS."
        else
            echo "Let's Encrypt certificate not found after attempt. Falling back to self-signed."
            generate_selfsigned_cert
        fi
    else
        generate_selfsigned_cert
    fi
}

add_trojan() {
    echo "Choose TLS certificate method for Trojan:"
    echo "1) Let's Encrypt (automated)"
    echo "2) Self-signed (auto-generated)"
    read -p "Enter your choice [1-2]: " tls_choice
    if [[ "$tls_choice" == "1" ]]; then
        TLS_MODE="letsencrypt"
        read -p "Enter your domain (e.g. example.com): " LE_DOMAIN
    else
        TLS_MODE="selfsigned"
        LE_DOMAIN=""
    fi
    port=$(get_next_port)
    echo "Auto-selected port: $port"
    ensure_cert "$TLS_MODE" "$LE_DOMAIN"
    password=$(openssl rand -hex 8)
    inbound_json=$(cat <<EOF
{
  "inbounds": [{
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
  }]
}
EOF
)
    add_inbound "$inbound_json"
    echo "Connection link:"
    echo "trojan://$password@$(curl -4s ifconfig.me):$port"
    allow_port "$port"
}

add_hysteria2() {
    echo "Choose TLS certificate method for Hysteria2:"
    echo "1) Let's Encrypt (automated)"
    echo "2) Self-signed (auto-generated)"
    read -p "Enter your choice [1-2]: " tls_choice
    if [[ "$tls_choice" == "1" ]]; then
        TLS_MODE="letsencrypt"
        read -p "Enter your domain (e.g. example.com): " LE_DOMAIN
    else
        TLS_MODE="selfsigned"
        LE_DOMAIN=""
    fi
    port=$(get_next_port)
    echo "Auto-selected port: $port"
    ensure_cert "$TLS_MODE" "$LE_DOMAIN"
    password=$(openssl rand -hex 8)
    inbound_json=$(cat <<EOF
{
  "inbounds": [{
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
  }]
}
EOF
)
    add_inbound "$inbound_json"
    echo "Connection link:"
    echo "hy2://$password@$(curl -4s ifconfig.me):$port"
    allow_port "$port"
}

add_trojan_gfw() {
    echo "Choose TLS certificate method for Trojan-GFW:"
    echo "1) Let's Encrypt (automated)"
    echo "2) Self-signed (auto-generated)"
    read -p "Enter your choice [1-2]: " tls_choice
    if [[ "$tls_choice" == "1" ]]; then
        TLS_MODE="letsencrypt"
        read -p "Enter your domain (e.g. example.com): " LE_DOMAIN
    else
        TLS_MODE="selfsigned"
        LE_DOMAIN=""
    fi

    port=$(get_next_port)
    echo "Auto-selected port: $port"
    ensure_cert "$TLS_MODE" "$LE_DOMAIN"
    password=$(openssl rand -hex 8)

    inbound_json=$(cat <<EOF
{
  "inbounds": [{
    "type": "trojan-gfw",
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
  }]
}
EOF
)
    add_inbound "$inbound_json"
    echo "Connection link:"
    echo "trojan://$password@$(curl -4s ifconfig.me):$port"
    allow_port "$port"
}

add_socks5() {
    port=$(get_next_port)
    echo "Auto-selected port: $port"
    inbound_json=$(cat <<EOF
{
  "inbounds": [{
    "type": "socks",
    "listen": "0.0.0.0",
    "listen_port": $port,
    "users": [],
    "udp": true
  }]
}
EOF
)
    add_inbound "$inbound_json"
    echo "Socks5 proxy added on port $port"
    allow_port "$port"
}

# Main menu loop
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
    echo -e "${CYAN} 5.${NC} Add VLESS               ${CYAN}(Auto-port, UUID, no TLS, WebSocket)"
    echo -e "${CYAN} 6.${NC} Add VMess               ${CYAN}(Auto-port, UUID, no TLS)"
    echo -e "${CYAN} 7.${NC} Add Trojan              ${CYAN}(Auto-port, password, TLS enabled)"
    echo -e "${CYAN} 8.${NC} Add Shadowsocks         ${CYAN}(Auto-port, AES-256-GCM)"
    echo -e "${CYAN} 9.${NC} Add Hysteria2           ${CYAN}(Auto-port, password, TLS enabled)"
    echo -e "${CYAN}14.${NC} Add Trojan-GFW          ${CYAN}(Auto-port, password, TLS enabled)"
    echo -e "${CYAN}15.${NC} Add Socks5 Proxy        ${CYAN}(Auto-port, no auth, UDP support)"
    echo

    echo -e "${YELLOW}--- Config Management ---${NC}"
    echo -e "${CYAN}10.${NC} List all configs        ${CYAN}(Show all created links, client configs, and QR codes)"
    echo -e "${CYAN}11.${NC} Remove a config         ${CYAN}(Delete a config by number)"
    echo

    echo -e "${CYAN}12.${NC} Exit"
    echo
    echo -e "${CYAN}13.${NC} Fix sing-box service file  ${CYAN}(Remove duplicate ExecStart lines and restart)"
    echo

    read -p "Select an option [1-15]: " choice

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
            generate_config "$protocol" "$port"
            allow_port "$port"
            ;;
        6)
            protocol="vmess"
            port=$(get_next_port)
            echo "Auto-selected port: $port"
            generate_config "$protocol" "$port"
            allow_port "$port"
            ;;
        7)
            add_trojan
            ;;
        8)
            protocol="shadowsocks"
            port=$(get_next_port)
            echo "Auto-selected port: $port"
            generate_config "$protocol" "$port"
            allow_port "$port"
            ;;
        9)
            add_hysteria2
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
        13)
            fix_service_file
            ;;
        14)
            add_trojan_gfw
            ;;
        15)
            add_socks5
            ;;
        *)
            echo "Invalid option."
            ;;
    esac
    echo
    read -p "Press Enter to return to the main menu..."
done
