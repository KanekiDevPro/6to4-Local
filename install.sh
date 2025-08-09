#!/bin/bash
# Tunnel Manager for multiple SIT tunnels
# Requires: jq, netplan.io, iproute2, systemd-networkd

set -euo pipefail

CONFIG_FILE="/etc/tunnel_manager.conf"
NETPLAN_DIR="/etc/netplan"
SYSTEMD_NET_DIR="/etc/systemd/network"
INTERFACE_PREFIX="tunel"

# Ensure jq installed
if ! command -v jq &>/dev/null; then
    echo "❌ jq not found. Please install jq (apt install jq)"
    exit 1
fi

# Validate IPs
validate_ipv4() {
    local ip=$1
    if [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        IFS='.' read -ra octets <<< "$ip"
        for o in "${octets[@]}"; do
            (( o >= 0 && o <= 255 )) || return 1
        done
        return 0
    fi
    return 1
}

validate_ipv6() {
    local ip=$1
    # Basic IPv6 validation including compressed forms (::)
    if [[ $ip =~ ^(([0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}|(::)|(([0-9a-fA-F]{1,4}:){1,7}:)|(:([0-9a-fA-F]{1,4}:){1,6})|(([0-9a-fA-F]{1,4}:){1,6}:))$ ]]; then
        return 0
    fi
    return 1
}

validate_mtu() {
    local mtu=$1
    if [[ $mtu =~ ^[0-9]+$ ]] && (( mtu >= 576 && mtu <= 9000 )); then
        return 0
    fi
    return 1
}

load_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo '{"tunnels":[]}' > "$CONFIG_FILE"
    fi
    config=$(cat "$CONFIG_FILE")
}

save_config() {
    echo "$config" | jq '.' > "$CONFIG_FILE"
}

generate_netplan_config() {
    local name=$1 local_ip4=$2 remote_ip4=$3 local_ip6=$4 mtu=$5

    local filepath="$NETPLAN_DIR/${name}.yaml"

    # Backup if exists
    if [[ -f "$filepath" ]]; then
        cp "$filepath" "$filepath.bak.$(date +%Y%m%d_%H%M%S)"
    fi

    cat > "$filepath" <<EOF
network:
  version: 2
  tunnels:
    $name:
      mode: sit
      local: $local_ip4
      remote: $remote_ip4
      addresses:
        - $local_ip6/64
      mtu: $mtu
EOF
}

generate_systemd_config() {
    local name=$1 local_ip6=$2 remote_ip6=$3

    local filepath="$SYSTEMD_NET_DIR/${name}.network"

    if [[ -f "$filepath" ]]; then
        cp "$filepath" "$filepath.bak.$(date +%Y%m%d_%H%M%S)"
    fi

    cat > "$filepath" <<EOF
[Match]
Name=$name

[Network]
Address=$local_ip6/64
Gateway=$remote_ip6
EOF
}

apply_settings() {
    echo "🔄 Applying netplan configuration..."
    if ! netplan apply; then
        echo "❌ Failed to apply netplan"
        return 1
    fi

    echo "🔄 Restarting systemd-networkd..."
    if ! systemctl restart systemd-networkd; then
        echo "❌ Failed to restart systemd-networkd"
        return 1
    fi

    echo "⏳ Waiting 3 seconds for services to stabilize..."
    sleep 3
}

list_tunnels() {
    echo "========================"
    echo "📋 List of tunnels:"
    echo "========================"
    local len
    len=$(echo "$config" | jq '.tunnels | length')

    if (( len == 0 )); then
        echo "ℹ️  No tunnels configured."
        return
    fi

    for (( i=0; i<len; i++ )); do
        local tname role lip4 rip4 lip6 rip6 mtu
        tname=$(echo "$config" | jq -r ".tunnels[$i].name")
        role=$(echo "$config" | jq -r ".tunnels[$i].role")
        lip4=$(echo "$config" | jq -r ".tunnels[$i].local_ip4")
        rip4=$(echo "$config" | jq -r ".tunnels[$i].remote_ip4")
        lip6=$(echo "$config" | jq -r ".tunnels[$i].local_ip6")
        rip6=$(echo "$config" | jq -r ".tunnels[$i].remote_ip6")
        mtu=$(echo "$config" | jq -r ".tunnels[$i].mtu")

        echo "🔹 $tname ($role)"
        echo "  IPv4 Local: $lip4  Remote: $rip4"
        echo "  IPv6 Local: $lip6  Remote: $rip6"
        echo "  MTU: $mtu"
        echo "---------------------------"
    done
}

add_tunnel() {
    echo "🛠 Adding new tunnel"

    # Ask role
    local role=""
    while true; do
        read -rp "Choose role (1=Iran, 2=Outside): " r
        if [[ "$r" == "1" ]]; then
            role="iran"
            break
        elif [[ "$r" == "2" ]]; then
            role="outside"
            break
        else
            echo "❌ Invalid input, choose 1 or 2"
        fi
    done

    if [[ "$role" == "iran" ]]; then
        # تعداد کلاینت‌هایی که می‌خوایم بسازیم
        local count=0
        while true; do
            read -rp "How many Iran clients to add? (1-10): " count
            if [[ "$count" =~ ^[1-9]$|^10$ ]]; then
                break
            else
                echo "❌ Please enter a number between 1 and 10"
            fi
        done

        # آدرس IP سرور خارج (remote) که همه بهش وصل میشن
        local remote_ip4 remote_ip6
        while true; do
            read -rp "Outside server IPv4 (remote for all clients): " remote_ip4
            if validate_ipv4 "$remote_ip4"; then break; else echo "❌ Invalid IPv4"; fi
        done
        while true; do
            read -rp "Outside server IPv6 (remote for all clients): " remote_ip6
            if validate_ipv6 "$remote_ip6"; then break; else echo "❌ Invalid IPv6"; fi
        done

        # برای هر کلاینت ایران جداگانه ورودی بگیریم و تونل بسازیم
        for ((i=1; i<=count; i++)); do
            echo "🔹 Configuring Iran client #$i"

            local lip4 lip6 mtu
            while true; do
                read -rp "Local IPv4 for client #$i: " lip4
                if validate_ipv4 "$lip4"; then break; else echo "❌ Invalid IPv4"; fi
            done
            while true; do
                read -rp "Local IPv6 for client #$i: " lip6
                if validate_ipv6 "$lip6"; then break; else echo "❌ Invalid IPv6"; fi
            done
            while true; do
                read -rp "MTU for client #$i (default 1480): " mtu
                mtu=${mtu:-1480}
                if validate_mtu "$mtu"; then break; else echo "❌ Invalid MTU"; fi
            done

            # اسم تونل جدید
            local count_existing
            count_existing=$(echo "$config" | jq '.tunnels | length')
            local name="${INTERFACE_PREFIX}$((count_existing+1))"

            # اضافه کردن تونل به config
            config=$(echo "$config" | jq --arg name "$name" --arg role "$role" --arg lip4 "$lip4" --arg rip4 "$remote_ip4" --arg lip6 "$lip6" --arg rip6 "$remote_ip6" --arg mtu "$mtu" \
                '.tunnels += [{"name": $name, "role": $role, "local_ip4": $lip4, "remote_ip4": $rip4, "local_ip6": $lip6, "remote_ip6": $rip6, "mtu": ($mtu|tonumber)}]')

            generate_netplan_config "$name" "$lip4" "$remote_ip4" "$lip6" "$mtu"
            generate_systemd_config "$name" "$lip6" "$remote_ip6"

            echo "✅ Tunnel $name added."
        done

    else
        # نقش خارج مثل قبل

        local lip4 rip4 lip6 rip6 mtu

        while true; do
            read -rp "Local IPv4: " lip4
            if validate_ipv4 "$lip4"; then break; else echo "❌ Invalid IPv4"; fi
        done
        while true; do
            read -rp "Remote IPv4: " rip4
            if validate_ipv4 "$rip4"; then break; else echo "❌ Invalid IPv4"; fi
        done
        while true; do
            read -rp "Local IPv6: " lip6
            if validate_ipv6 "$lip6"; then break; else echo "❌ Invalid IPv6"; fi
        done
        while true; do
            read -rp "Remote IPv6: " rip6
            if validate_ipv6 "$rip6"; then break; else echo "❌ Invalid IPv6"; fi
        done
        while true; do
            read -rp "MTU (default 1480): " mtu
            mtu=${mtu:-1480}
            if validate_mtu "$mtu"; then break; else echo "❌ Invalid MTU"; fi
        done

        local count_existing
        count_existing=$(echo "$config" | jq '.tunnels | length')
        local name="${INTERFACE_PREFIX}$((count_existing+1))"

        config=$(echo "$config" | jq --arg name "$name" --arg role "$role" --arg lip4 "$lip4" --arg rip4 "$rip4" --arg lip6 "$lip6" --arg rip6 "$rip6" --arg mtu "$mtu" \
            '.tunnels += [{"name": $name, "role": $role, "local_ip4": $lip4, "remote_ip4": $rip4, "local_ip6": $lip6, "remote_ip6": $rip6, "mtu": ($mtu|tonumber)}]')

        generate_netplan_config "$name" "$lip4" "$rip4" "$lip6" "$mtu"
        generate_systemd_config "$name" "$lip6" "$rip6"

        echo "✅ Tunnel $name added."
    fi

    # پس از افزودن تونل(ها)، apply و restart کنیم
    echo "🔄 Applying netplan and restarting systemd-networkd..."
    if ! apply_settings; then
        echo "❌ Error applying settings"
    fi
}

remove_tunnel() {
    list_tunnels
    echo
    read -rp "Enter interface name to remove (e.g. tunel1): " name

    # Check if tunnel exists
    local exists
    exists=$(echo "$config" | jq --arg name "$name" '.tunnels[] | select(.name == $name) | length' || echo "")

    if [[ -z "$exists" ]]; then
        echo "❌ Tunnel $name not found."
        return
    fi

    # Remove from config JSON
    config=$(echo "$config" | jq --arg name "$name" 'del(.tunnels[] | select(.name == $name))')

    # Remove config files
    local netplan_file="$NETPLAN_DIR/${name}.yaml"
    local systemd_file="$SYSTEMD_NET_DIR/${name}.network"

    if [[ -f "$netplan_file" ]]; then
        mv "$netplan_file" "$netplan_file.removed.$(date +%Y%m%d_%H%M%S)"
    fi
    if [[ -f "$systemd_file" ]]; then
        mv "$systemd_file" "$systemd_file.removed.$(date +%Y%m%d_%H%M%S)"
    fi

    echo "✅ Tunnel $name removed (config files backed up)."

    # Apply changes after removal
    echo "🔄 Applying netplan and restarting systemd-networkd..."
    if ! apply_settings; then
        echo "❌ Error applying settings"
    fi
}

show_status() {
    list_tunnels
    echo
    echo "📡 Interface statuses:"

    local len
    len=$(echo "$config" | jq '.tunnels | length')
    for (( i=0; i<len; i++ )); do
        local name ip4 ip6
        name=$(echo "$config" | jq -r ".tunnels[$i].name")
        ip4=$(echo "$config" | jq -r ".tunnels[$i].local_ip4")
        ip6=$(echo "$config" | jq -r ".tunnels[$i].local_ip6")

        echo "---------------------------"
        echo "Interface: $name"
        if ip link show "$name" &>/dev/null; then
            echo "✅ UP"
            ip addr show "$name" | grep -E "inet |inet6 "
        else
            echo "❌ DOWN or not found"
        fi
    done
}

main_menu() {
    while true; do
        echo
        echo "=============================="
        echo "    SIT Tunnel Manager"
        echo "=============================="
        echo "1) Add new tunnel"
        echo "2) Remove tunnel"
        echo "3) Show tunnels and status"
        echo "4) Apply settings"
        echo "5) Exit"
        echo "=============================="
        read -rp "Choose an option [1-5]: " choice

        load_config

        case $choice in
            1) add_tunnel ;;
            2) remove_tunnel ;;
            3) show_status ;;
            4) 
                echo "🔄 Applying settings..."
                if ! apply_settings; then
                    echo "❌ Error applying settings"
                fi
                ;;
            5) 
                echo "👋 Goodbye!"
                exit 0
                ;;
            *)
                echo "❌ Invalid choice"
                ;;
        esac

        save_config

        echo
        read -rp "Press Enter to continue..."
    done
}

# Check root
if [[ $EUID -ne 0 ]]; then
    echo "❌ Please run as root."
    exit 1
fi

main_menu
