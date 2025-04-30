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
==== Satki Singbox Menu ====

--- Sing-box Service Management ---
 1. Install sing-box         (Download and install sing-box binary)
 2. Uninstall sing-box       (Remove sing-box and all configs)
 3. Start sing-box           (Start the sing-box service)
 4. Check sing-box status    (Show sing-box service status)

--- Add New Protocol ---
 5. Add VLESS               (Auto-port, UUID, no TLS)
 6. Add VMess               (Auto-port, UUID, no TLS)
 7. Add Trojan              (Auto-port, password, TLS enabled)
 8. Add Shadowsocks         (Auto-port, AES-256-GCM)
 9. Add Hysteria2           (Auto-port, password, TLS enabled)

--- Config Management ---
10. List all configs        (Show all created configs and links)
11. Remove a config         (Delete a config by number)
12. Exit
13. Fix sing-box service file  (Remove duplicate ExecStart lines and restart)
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
