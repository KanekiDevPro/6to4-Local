# 6to4 SIT Tunnel Manager

A simple and interactive Bash script to **setup**, **remove**, and **monitor** an IPv6 SIT tunnel on Debian/Ubuntu-based servers using Netplan and systemd-networkd.

---

## Features

- **Interactive menu** for easy tunnel management
- Automatic installation of required packages (`iproute2`, `netplan.io`)
- Configures Netplan to establish a SIT tunnel with user-provided IPv4 and IPv6 addresses
- Creates and manages `systemd-networkd` configuration for tunnel interface
- Allows removing the tunnel configuration cleanly
- Displays tunnel interface status and performs IPv6 connectivity test (ping)
- Suitable for servers requiring IPv6 backhaul or local IPv6 tunneling between two hosts

---

## Prerequisites

- Debian/Ubuntu-based Linux distribution
- Root or sudo privileges
- Basic understanding of IPv4 and IPv6 addressing

---

## Usage

1. **Download the script:**

   ```bash
   wget https://your-repo-url/ipv6_tunnel_manager.sh
   ```

2. **Make it executable:**

   ```bash
   chmod +x ipv6_tunnel_manager.sh
   ```

3. **Run the script with sudo:**

   ```bash
   sudo ./ipv6_tunnel_manager.sh
   ```

4. **Follow the interactive menu:**

   - Setup Tunnel: Configure tunnel with your IPv4 and IPv6 details and desired MTU.
   - Remove Tunnel: Delete existing tunnel configuration and clean up.
   - Show Tunnel Status: Display tunnel interface details and ping the gateway.
   - Exit: Close the script.

---

## Configuration Details

During setup, you will be prompted for:

| Parameter                     | Description                                 | Example           |
|-------------------------------|---------------------------------------------|-------------------|
| IPv4 of the external server    | The IPv4 address of the remote (external) server | `203.0.113.10`    |
| IPv4 of the internal server    | The IPv4 address of the local (internal) server  | `198.51.100.5`    |
| Local IPv6 address for external | The ULA (Unique Local Address) IPv6 for external server | `fd00:1234:abcd::1` |
| Local IPv6 address for internal | The ULA IPv6 for internal server             | `fd00:1234:abcd::2` |
| MTU                            | MTU size for the tunnel interface            | `1480` or `1500`  |

---

## How It Works

- Installs necessary packages (`iproute2`, `netplan.io`) if missing
- Generates `/etc/netplan/pdtun.yaml` with SIT tunnel config
- Applies Netplan to bring up the tunnel interface
- Creates `/etc/systemd/network/tunel01.network` to configure IPv6 address and gateway on the tunnel interface
- Restarts `systemd-networkd` to apply changes
- Allows easy removal of configuration and status monitoring

---

## Notes

- The script assumes the use of `systemd-networkd` and `netplan` for network management.
- Ensure your system is compatible and these services are active.
- Adjust firewall settings if necessary to allow SIT protocol (protocol 41).
- IPv6 Unique Local Addresses (ULA) should be chosen carefully to avoid conflicts.

---

## Troubleshooting

- If tunnel interface does not come up, check logs:

  ```bash
  journalctl -u systemd-networkd
  ```

- Verify Netplan configuration:

  ```bash
  sudo netplan try
  sudo netplan apply
  ```

- Check interface status:

  ```bash
  ip a show tunel01
  ```

---

## License

This project is licensed under the MIT License.

---

## Author

Developed by [Your Name or Handle]

---

## Contribution

Feel free to open issues or pull requests for improvements or bug fixes.

---

## Disclaimer

Use this script at your own risk. Always backup your configurations before applying changes.

