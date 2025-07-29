#!/bin/bash

CONFIG_NETPLAN="/etc/netplan/pdtun.yaml"
CONFIG_SYSTEMD="/etc/systemd/network/tunel01.network"
INTERFACE="tunel01"

function setup_tunnel() {
    echo "📥 Please enter the required information for tunnel setup:"

    read -p "🌐 IPv4 of the external server (KHAREJLOCAL): " KHAREJLOCAL
    read -p "🌐 IPv4 of the internal server (IRAN): " IRAN
    read -p "🧭 Local IPv6 address for external server (e.g. fd00::1): " ipv6KHAREJ
    read -p "🧭 Local IPv6 address for internal server (e.g. fd00::2): " ipv6IRAN
    read -p "🔧 MTU value (e.g. 1480 or 1500): " MTU

    echo
    echo "🛑 Which side are you configuring?"
    echo "1) Iran server"
    echo "2) Outside server"
    read -p "Choose [1 or 2]: " side

    if [ "$side" == "1" ]; then
        local_ip="$IRAN"
        remote_ip="$KHAREJLOCAL"
        local_ipv6="$ipv6IRAN"
        remote_ipv6="$ipv6KHAREJ"
    elif [ "$side" == "2" ]; then
        local_ip="$KHAREJLOCAL"
        remote_ip="$IRAN"
        local_ipv6="$ipv6KHAREJ"
        remote_ipv6="$ipv6IRAN"
    else
        echo "Invalid choice. Exiting."
        exit 1
    fi

    echo "🔧 Installing required packages..."
    apt update -y
    apt install -y iproute2 netplan.io

    echo "🛠 Creating Netplan config..."
    cat <<EOF > $CONFIG_NETPLAN
network:
  version: 2
  tunnels:
    $INTERFACE:
      mode: sit
      local: $local_ip
      remote: $remote_ip
      addresses:
        - $local_ipv6/64
      mtu: $MTU
EOF

    echo "📡 Applying Netplan..."
    netplan apply

    echo "🛠 Creating systemd-networkd config..."
    cat <<EOF > $CONFIG_SYSTEMD
[Match]
Name=$INTERFACE

[Network]
Address=$local_ipv6/64
Gateway=$remote_ipv6
EOF

    echo "🔄 Restarting systemd-networkd..."
    systemctl restart systemd-networkd

    echo "✅ Tunnel setup completed successfully!"
}

function remove_tunnel() {
    echo "🧹 Removing tunnel configuration..."

    if [ -f "$CONFIG_NETPLAN" ]; then
        rm -f "$CONFIG_NETPLAN"
        echo "Removed $CONFIG_NETPLAN"
    else
        echo "No netplan config found at $CONFIG_NETPLAN"
    fi

    if [ -f "$CONFIG_SYSTEMD" ]; then
        rm -f "$CONFIG_SYSTEMD"
        echo "Removed $CONFIG_SYSTEMD"
    else
        echo "No systemd-networkd config found at $CONFIG_SYSTEMD"
    fi

    echo "📡 Applying netplan to remove tunnel..."
    netplan apply

    echo "🔄 Restarting systemd-networkd..."
    systemctl restart systemd-networkd

    echo "✅ Tunnel removed successfully!"
}

function status_tunnel() {
    echo "📈 Showing status of interface $INTERFACE:"
    ip a show $INTERFACE || echo "Interface $INTERFACE not found."

    echo "🧪 Ping test to gateway (IPv6):"
    if [ -f "$CONFIG_SYSTEMD" ]; then
        GATEWAY=$(grep Gateway $CONFIG_SYSTEMD | awk '{print $2}')
        if [ -n "$GATEWAY" ]; then
            ping6 -c 5 $GATEWAY
        else
            echo "Gateway not set in $CONFIG_SYSTEMD"
        fi
    else
        echo "Systemd network config not found."
    fi
}

function menu() {
    echo "=============================="
    echo " IPv6 SIT Tunnel Manager"
    echo "=============================="
    echo "1) Setup Tunnel"
    echo "2) Remove Tunnel"
    echo "3) Show Tunnel Status"
    echo "4) Exit"
    echo "=============================="
    read -p "Choose an option [1-4]: " choice

    case $choice in
        1)
            setup_tunnel
            ;;
        2)
            remove_tunnel
            ;;
        3)
            status_tunnel
            ;;
        4)
            echo "Exiting. Goodbye!"
            exit 0
            ;;
        *)
            echo "Invalid option."
            ;;
    esac
}

while true; do
    menu
    echo
done
