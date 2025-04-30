## 🚀 One-command install
bash <(curl -fsSL https://raw.githubusercontent.com/SatkiExE808/satki-singbox/main/satki.sh)

bash <(wget -qO- https://raw.githubusercontent.com/SatkiExE808/satki-singbox/main/satki.sh)
## ✨ Features
One-command install and self-updating menu
Automatic config path detection (always writes to the config your sing-box service uses)
Multi-protocol support: VLESS, VMess, Trojan, Shadowsocks, Hysteria2
Automatic port selection (no duplicates)
TLS auto-generation for protocols that require it
Firewall port auto-allow (UFW)
Colorful, user-friendly menu
List and remove configs easily
Fix systemd service file (no more duplicate ExecStart errors)
Works on Ubuntu/Debian VPS (root required for install)
## 🖥️ Menu Preview
![satkibox](https://github.com/user-attachments/assets/26291971-062f-47ef-9077-c0a73bcf48c0)
## 📝 Usage
Install with the one-command above.
The menu will launch automatically.
After that, just run satki to open the menu.
Use the menu to add protocols, list configs, or fix the service file if needed.
## 🛠️ Requirements
Ubuntu/Debian VPS (root or sudo privileges)
curl or wget
jq (auto-installed by the script)
UFW (for firewall auto-allow, optional)
## 🧩 How it works
The script installs itself as /usr/local/bin/satki for easy access.
It always writes configs and certs to the path your sing-box service actually uses.
The menu is interactive and colorized for clarity.
## 🆘 Troubleshooting
If you see "Service has more than one ExecStart" error, use menu option 13 to fix it.
If a protocol doesn't work, use the menu to list configs and check your client settings.
For advanced debugging, check the sing-box logs
sudo journalctl -u sing-box --no-pager | tail -30
## 📢 Contributing

## 📄 License
