#!/bin/bash

# Check for root privileges
if [[ $EUID -ne 0 ]]; then
   echo "❌ This script must be run as root"
   exit 1
fi

CONFIG_NETPLAN="/etc/netplan/pdtun.yaml"
CONFIG_SYSTEMD="/etc/systemd/network/tunel01.network"
INTERFACE="tunel01"

# Validation functions for IP addresses
validate_ipv4() {
    local ip=$1
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        IFS='.' read -r -a addr <<< "$ip"
        for i in "${addr[@]}"; do
            if [[ $i -gt 255 ]]; then
                return 1
            fi
        done
        return 0
    else
        return 1
    fi
}

validate_ipv6() {
    local ipv6=$1
    # Simple IPv6 validation
    if [[ $ipv6 =~ ^[0-9a-fA-F:]+$ ]] && [[ ${#ipv6} -ge 3 ]]; then
        return 0
    else
        return 1
    fi
}

validate_mtu() {
    local mtu=$1
    if [[ $mtu =~ ^[0-9]+$ ]] && [[ $mtu -ge 576 ]] && [[ $mtu -le 9000 ]]; then
        return 0
    else
        return 1
    fi
}

function setup_tunnel() {
    echo "🛠 TUNNEL SETUP"
    echo "==============================="
    echo "Which server are you configuring?"
    echo
    echo "1) 🇮🇷 Iran Server (Inside)"
    echo "2) 🌍 Outside Server (Foreign)"
    echo "==============================="
    echo
    
    while true; do
        read -p "Choose server type [1 or 2]: " server_type
        if [[ "$server_type" == "1" || "$server_type" == "2" ]]; then
            break
        else
            echo "❌ Please choose 1 or 2"
        fi
    done
    
    echo
    echo "📥 Please enter the required information:"
    
    if [ "$server_type" == "1" ]; then
        echo "🇮🇷 Configuring Iran Server..."
        echo "=================================="
        
        # Iran server configuration
        while true; do
            read -p "🌐 This Iran server IPv4 address: " local_ip
            if validate_ipv4 "$local_ip"; then
                break
            else
                echo "❌ Invalid IPv4 address. Example: 192.168.1.1"
            fi
        done
        
        while true; do
            read -p "🌐 Outside server IPv4 address: " remote_ip
            if validate_ipv4 "$remote_ip"; then
                break
            else
                echo "❌ Invalid IPv4 address. Example: 5.6.7.8"
            fi
        done
        
        while true; do
            read -p "🧭 This Iran server IPv6 address (e.g. fd00::2): " local_ipv6
            if validate_ipv6 "$local_ipv6"; then
                break
            else
                echo "❌ Invalid IPv6 address. Example: fd00::2"
            fi
        done
        
        while true; do
            read -p "🧭 Outside server IPv6 address (e.g. fd00::1): " remote_ipv6
            if validate_ipv6 "$remote_ipv6"; then
                break
            else
                echo "❌ Invalid IPv6 address. Example: fd00::1"
            fi
        done
        
    else
        echo "🌍 Configuring Outside Server..."
        echo "=================================="
        
        # Outside server configuration
        while true; do
            read -p "🌐 This outside server IPv4 address: " local_ip
            if validate_ipv4 "$local_ip"; then
                break
            else
                echo "❌ Invalid IPv4 address. Example: 5.6.7.8"
            fi
        done
        
        while true; do
            read -p "🌐 Iran server IPv4 address: " remote_ip
            if validate_ipv4 "$remote_ip"; then
                break
            else
                echo "❌ Invalid IPv4 address. Example: 192.168.1.1"
            fi
        done
        
        while true; do
            read -p "🧭 This outside server IPv6 address (e.g. fd00::1): " local_ipv6
            if validate_ipv6 "$local_ipv6"; then
                break
            else
                echo "❌ Invalid IPv6 address. Example: fd00::1"
            fi
        done
        
        while true; do
            read -p "🧭 Iran server IPv6 address (e.g. fd00::2): " remote_ipv6
            if validate_ipv6 "$remote_ipv6"; then
                break
            else
                echo "❌ Invalid IPv6 address. Example: fd00::2"
            fi
        done
    fi
    
    # Common MTU setting
    while true; do
        read -p "🔧 MTU value (recommended: 1480): " MTU
        if validate_mtu "$MTU"; then
            break
        else
            echo "❌ MTU value must be between 576 and 9000"
        fi
    done
    
    create_tunnel_config
}

function create_tunnel_config() {
    echo "🔧 Installing required packages..."
    if ! apt update -y; then
        echo "❌ Error updating packages"
        return 1
    fi
    
    if ! apt install -y iproute2 netplan.io; then
        echo "❌ Error installing packages"
        return 1
    fi
    
    # Backup existing config if it exists
    if [ -f "$CONFIG_NETPLAN" ]; then
        cp "$CONFIG_NETPLAN" "${CONFIG_NETPLAN}.backup.$(date +%Y%m%d_%H%M%S)"
        echo "📁 Backed up existing config"
    fi
    
    # Create netplan directory if it doesn't exist
    mkdir -p "$(dirname "$CONFIG_NETPLAN")"
    
    echo "🛠 Creating Netplan configuration..."
    cat <<EOF > "$CONFIG_NETPLAN"
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
    
    if [ ! -f "$CONFIG_NETPLAN" ]; then
        echo "❌ Failed to create Netplan config"
        return 1
    fi
    
    echo "📡 Applying Netplan configuration..."
    if ! netplan apply; then
        echo "❌ Failed to apply Netplan configuration"
        return 1
    fi
    
    # Create systemd network directory if it doesn't exist
    mkdir -p "$(dirname "$CONFIG_SYSTEMD")"
    
    echo "🛠 Creating systemd-networkd configuration..."
    cat <<EOF > "$CONFIG_SYSTEMD"
[Match]
Name=$INTERFACE

[Network]
Address=$local_ipv6/64
Gateway=$remote_ipv6
EOF
    
    if [ ! -f "$CONFIG_SYSTEMD" ]; then
        echo "❌ Failed to create systemd-networkd config"
        return 1
    fi
    
    echo "🔄 Restarting systemd-networkd..."
    systemctl enable systemd-networkd
    if ! systemctl restart systemd-networkd; then
        echo "❌ Failed to restart systemd-networkd"
        return 1
    fi
    
    # Wait for connection
    echo "⏳ Waiting for connection to establish..."
    sleep 3
    
    echo "✅ Tunnel setup completed successfully!"
    echo "📊 Current interface status:"
    ip addr show "$INTERFACE" 2>/dev/null || echo "⚠️  Interface not yet active"
    
    echo ""
    echo "🔍 Configuration Summary:"
    echo "  Local IP:  $local_ip"
    echo "  Remote IP: $remote_ip" 
    echo "  Local IPv6:  $local_ipv6"
    echo "  Remote IPv6: $remote_ipv6"
    echo "  MTU: $MTU"
}

function remove_tunnel() {
    echo "🧹 REMOVING TUNNEL CONFIGURATION"
    echo "==============================="
    
    # Stop interface before removal
    if ip link show "$INTERFACE" &>/dev/null; then
        echo "📡 Disabling interface $INTERFACE..."
        ip link set "$INTERFACE" down 2>/dev/null
    fi
    
    removed_any=false
    
    if [ -f "$CONFIG_NETPLAN" ]; then
        # Backup before removal
        cp "$CONFIG_NETPLAN" "${CONFIG_NETPLAN}.removed.$(date +%Y%m%d_%H%M%S)"
        rm -f "$CONFIG_NETPLAN"
        echo "✅ Removed: $CONFIG_NETPLAN"
        removed_any=true
    else
        echo "ℹ️  No netplan config found at $CONFIG_NETPLAN"
    fi
    
    if [ -f "$CONFIG_SYSTEMD" ]; then
        # Backup before removal
        cp "$CONFIG_SYSTEMD" "${CONFIG_SYSTEMD}.removed.$(date +%Y%m%d_%H%M%S)"
        rm -f "$CONFIG_SYSTEMD"
        echo "✅ Removed: $CONFIG_SYSTEMD"
        removed_any=true
    else
        echo "ℹ️  No systemd-networkd config found at $CONFIG_SYSTEMD"
    fi
    
    if [ "$removed_any" = true ]; then
        echo "📡 Applying netplan to remove tunnel..."
        netplan apply
        
        echo "🔄 Restarting systemd-networkd..."
        systemctl restart systemd-networkd
        
        echo "✅ Tunnel removed successfully!"
        echo "📁 Configuration files have been backed up with timestamp"
    else
        echo "ℹ️  No configuration found to remove"
    fi
}

function status_tunnel() {
    clear
    echo "==============================="
    echo "📈 TUNNEL STATUS: $INTERFACE"
    echo "==============================="
    
    # Check if interface exists
    if ip link show "$INTERFACE" &>/dev/null; then
        echo "✅ Interface $INTERFACE is active"
        echo
        echo "📊 Interface details:"
        ip addr show "$INTERFACE"
        echo
        
        # Check routing
        echo "🛣  IPv6 routing table:"
        ip -6 route show dev "$INTERFACE" 2>/dev/null || echo "No routes found for this interface"
        echo
        
        # Test ping to gateway
        if [ -f "$CONFIG_SYSTEMD" ]; then
            GATEWAY=$(grep "^Gateway=" "$CONFIG_SYSTEMD" 2>/dev/null | cut -d'=' -f2)
            if [ -n "$GATEWAY" ]; then
                echo "🧪 Testing ping to gateway ($GATEWAY):"
                if command -v ping6 &>/dev/null; then
                    ping6 -c 3 -W 2 "$GATEWAY" 2>/dev/null || echo "❌ Gateway is not reachable"
                else
                    ping -6 -c 3 -W 2 "$GATEWAY" 2>/dev/null || echo "❌ Gateway is not reachable"
                fi
            else
                echo "⚠️  No gateway defined in systemd config"
            fi
        else
            echo "⚠️  systemd-networkd config not found"
        fi
        
        echo
        echo "📋 Interface statistics:"
        cat /sys/class/net/"$INTERFACE"/statistics/rx_bytes 2>/dev/null | awk '{print "  RX Bytes: " $1}' || echo "  Statistics not available"
        cat /sys/class/net/"$INTERFACE"/statistics/tx_bytes 2>/dev/null | awk '{print "  TX Bytes: " $1}' || echo ""
        
    else
        echo "❌ Interface $INTERFACE not found or not active"
        
        # Check for config files
        echo
        echo "🔍 Checking configuration files:"
        if [ -f "$CONFIG_NETPLAN" ]; then
            echo "✅ Netplan config exists: $CONFIG_NETPLAN"
        else
            echo "❌ Netplan config missing: $CONFIG_NETPLAN"
        fi
        
        if [ -f "$CONFIG_SYSTEMD" ]; then
            echo "✅ systemd config exists: $CONFIG_SYSTEMD"
        else
            echo "❌ systemd config missing: $CONFIG_SYSTEMD"
        fi
        
        echo
        echo "💡 To reactivate the tunnel, run:"
        echo "   netplan apply && systemctl restart systemd-networkd"
    fi
    
    echo
    echo "📋 systemd-networkd service status:"
    if systemctl is-active --quiet systemd-networkd; then
        echo "✅ systemd-networkd is running"
    else
        echo "❌ systemd-networkd is not running"
        echo "💡 Start it with: systemctl start systemd-networkd"
    fi
    
    echo
    echo "🗂  Recent systemd-networkd logs:"
    journalctl -u systemd-networkd --no-pager -n 5 2>/dev/null || echo "No logs available"
}



function main_menu() {
    clear
    echo "==============================="
    echo " 🚀 IPv6 SIT Tunnel Manager"
    echo "==============================="
    echo "1) 🛠  Setup Tunnel"
    echo "2) 🧹 Remove Tunnel"
    echo "3) 📈 Show Tunnel Status"
    echo "4) 🔄 Restart Services"
    echo "5) 📋 Show System Info"
    echo "6) 🚪 Exit"
    echo "==============================="
    echo
    read -p "Choose an option [1-6]: " choice
    
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
            restart_services
            ;;
        5)
            show_system_info
            ;;
        6)
            echo "👋 Goodbye!"
            exit 0
            ;;
        *)
            echo "❌ Invalid option. Please choose a number between 1-6"
            ;;
    esac
}

function restart_services() {
    echo "🔄 RESTARTING NETWORK SERVICES"
    echo "=============================="
    
    echo "🔄 Restarting systemd-networkd..."
    if systemctl restart systemd-networkd; then
        echo "✅ systemd-networkd restarted successfully"
    else
        echo "❌ Failed to restart systemd-networkd"
    fi
    
    echo "📡 Reapplying netplan configuration..."
    if netplan apply; then
        echo "✅ Netplan applied successfully"
    else
        echo "❌ Failed to apply netplan"
    fi
    
    echo "⏳ Waiting for services to stabilize..."
    sleep 3
    
    if ip link show "$INTERFACE" &>/dev/null; then
        echo "✅ Interface $INTERFACE is active"
    else
        echo "⚠️  Interface $INTERFACE is not active"
    fi
}

function show_system_info() {
    clear
    echo "==============================="
    echo "📋 SYSTEM INFORMATION"
    echo "==============================="
    
    echo "🖥  Operating System:"
    lsb_release -d 2>/dev/null || cat /etc/os-release | grep PRETTY_NAME | cut -d'=' -f2 | tr -d '"'
    
    echo
    echo "🌐 Network Interfaces:"
    ip -br addr show
    
    echo
    echo "📦 Required Packages:"
    if command -v netplan &>/dev/null; then
        echo "✅ netplan is installed"
    else
        echo "❌ netplan is not installed"
    fi
    
    if command -v ip &>/dev/null; then
        echo "✅ iproute2 is installed"
    else
        echo "❌ iproute2 is not installed"
    fi
    
    echo
    echo "🔧 IPv6 Support:"
    if [ -f /proc/net/if_inet6 ]; then
        echo "✅ IPv6 is enabled"
    else
        echo "❌ IPv6 is disabled"
    fi
    
    echo
    echo "📁 Configuration Files:"
    if [ -f "$CONFIG_NETPLAN" ]; then
        echo "✅ $CONFIG_NETPLAN exists"
    else
        echo "❌ $CONFIG_NETPLAN does not exist"
    fi
    
    if [ -f "$CONFIG_SYSTEMD" ]; then
        echo "✅ $CONFIG_SYSTEMD exists"
    else
        echo "❌ $CONFIG_SYSTEMD does not exist"
    fi
}

# Main program loop
while true; do
    main_menu
    echo
    read -p "Press Enter to continue..."
done
