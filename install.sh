#!/bin/bash

# بررسی دسترسی root
if [[ $EUID -ne 0 ]]; then
   echo "❌ این اسکریپت باید با دسترسی root اجرا شود"
   exit 1
fi

CONFIG_NETPLAN="/etc/netplan/pdtun.yaml"
CONFIG_SYSTEMD="/etc/systemd/network/tunel01.network"
INTERFACE="tunel01"

# تابع validation برای IP addresses
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
    # ساده‌ترین validation برای IPv6
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
    echo "📥 لطفاً اطلاعات مورد نیاز برای راه‌اندازی تونل را وارد کنید:"
    
    # دریافت و validation IP addresses
    while true; do
        read -p "🌐 IPv4 سرور خارجی (KHAREJ): " KHAREJLOCAL
        if validate_ipv4 "$KHAREJLOCAL"; then
            break
        else
            echo "❌ آدرس IPv4 نامعتبر است. مثال: 192.168.1.1"
        fi
    done
    
    while true; do
        read -p "🌐 IPv4 سرور داخلی (IRAN): " IRAN
        if validate_ipv4 "$IRAN"; then
            break
        else
            echo "❌ آدرس IPv4 نامعتبر است. مثال: 192.168.1.2"
        fi
    done
    
    while true; do
        read -p "🧭 آدرس IPv6 محلی برای سرور خارجی (مثال: fd00::1): " ipv6KHAREJ
        if validate_ipv6 "$ipv6KHAREJ"; then
            break
        else
            echo "❌ آدرس IPv6 نامعتبر است. مثال: fd00::1"
        fi
    done
    
    while true; do
        read -p "🧭 آدرس IPv6 محلی برای سرور داخلی (مثال: fd00::2): " ipv6IRAN
        if validate_ipv6 "$ipv6IRAN"; then
            break
        else
            echo "❌ آدرس IPv6 نامعتبر است. مثال: fd00::2"
        fi
    done
    
    while true; do
        read -p "🔧 مقدار MTU (پیشنهادی: 1480): " MTU
        if validate_mtu "$MTU"; then
            break
        else
            echo "❌ مقدار MTU باید بین 576 تا 9000 باشد"
        fi
    done
    
    echo
    echo "🛑 کدام سمت را پیکربندی می‌کنید؟"
    echo "1) سرور ایران"
    echo "2) سرور خارج"
    
    while true; do
        read -p "انتخاب کنید [1 یا 2]: " side
        if [[ "$side" == "1" || "$side" == "2" ]]; then
            break
        else
            echo "❌ لطفاً 1 یا 2 را انتخاب کنید"
        fi
    done
    
    if [ "$side" == "1" ]; then
        local_ip="$IRAN"
        remote_ip="$KHAREJLOCAL"
        local_ipv6="$ipv6IRAN"
        remote_ipv6="$ipv6KHAREJ"
        echo "📍 در حال پیکربندی سرور ایران..."
    else
        local_ip="$KHAREJLOCAL"
        remote_ip="$IRAN"
        local_ipv6="$ipv6KHAREJ"
        remote_ipv6="$ipv6IRAN"
        echo "📍 در حال پیکربندی سرور خارج..."
    fi
    
    echo "🔧 نصب پکیج‌های مورد نیاز..."
    if ! apt update -y; then
        echo "❌ خطا در به‌روزرسانی پکیج‌ها"
        return 1
    fi
    
    if ! apt install -y iproute2 netplan.io; then
        echo "❌ خطا در نصب پکیج‌ها"
        return 1
    fi
    
    # بک‌آپ کانفیگ قبلی اگر وجود داشته باشد
    if [ -f "$CONFIG_NETPLAN" ]; then
        cp "$CONFIG_NETPLAN" "${CONFIG_NETPLAN}.backup.$(date +%Y%m%d_%H%M%S)"
        echo "📁 بک‌آپ از کانفیگ قبلی گرفته شد"
    fi
    
    # ایجاد دایرکتوری netplan اگر وجود نداشته باشد
    mkdir -p "$(dirname "$CONFIG_NETPLAN")"
    
    echo "🛠 ایجاد کانفیگ Netplan..."
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
        echo "❌ خطا در ایجاد کانفیگ Netplan"
        return 1
    fi
    
    echo "📡 اعمال Netplan..."
    if ! netplan apply; then
        echo "❌ خطا در اعمال Netplan"
        return 1
    fi
    
    # ایجاد دایرکتوری systemd network اگر وجود نداشته باشد
    mkdir -p "$(dirname "$CONFIG_SYSTEMD")"
    
    echo "🛠 ایجاد کانفیگ systemd-networkd..."
    cat <<EOF > "$CONFIG_SYSTEMD"
[Match]
Name=$INTERFACE

[Network]
Address=$local_ipv6/64
Gateway=$remote_ipv6
EOF
    
    if [ ! -f "$CONFIG_SYSTEMD" ]; then
        echo "❌ خطا در ایجاد کانفیگ systemd-networkd"
        return 1
    fi
    
    echo "🔄 راه‌اندازی مجدد systemd-networkd..."
    systemctl enable systemd-networkd
    if ! systemctl restart systemd-networkd; then
        echo "❌ خطا در راه‌اندازی مجدد systemd-networkd"
        return 1
    fi
    
    # صبر برای اتصال
    echo "⏳ صبر برای برقراری اتصال..."
    sleep 3
    
    echo "✅ تونل با موفقیت راه‌اندازی شد!"
    echo "📊 وضعیت فعلی interface:"
    ip addr show "$INTERFACE" 2>/dev/null || echo "⚠️  Interface هنوز فعال نشده است"
}

function remove_tunnel() {
    echo "🧹 حذف پیکربندی تونل..."
    
    # متوقف کردن interface قبل از حذف
    if ip link show "$INTERFACE" &>/dev/null; then
        echo "📡 غیرفعال کردن interface $INTERFACE..."
        ip link set "$INTERFACE" down 2>/dev/null
    fi
    
    removed_any=false
    
    if [ -f "$CONFIG_NETPLAN" ]; then
        # بک‌آپ قبل از حذف
        cp "$CONFIG_NETPLAN" "${CONFIG_NETPLAN}.removed.$(date +%Y%m%d_%H%M%S)"
        rm -f "$CONFIG_NETPLAN"
        echo "✅ حذف شد: $CONFIG_NETPLAN"
        removed_any=true
    else
        echo "ℹ️  کانفیگ netplan در $CONFIG_NETPLAN یافت نشد"
    fi
    
    if [ -f "$CONFIG_SYSTEMD" ]; then
        # بک‌آپ قبل از حذف
        cp "$CONFIG_SYSTEMD" "${CONFIG_SYSTEMD}.removed.$(date +%Y%m%d_%H%M%S)"
        rm -f "$CONFIG_SYSTEMD"
        echo "✅ حذف شد: $CONFIG_SYSTEMD"
        removed_any=true
    else
        echo "ℹ️  کانفیگ systemd-networkd در $CONFIG_SYSTEMD یافت نشد"
    fi
    
    if [ "$removed_any" = true ]; then
        echo "📡 اعمال netplan برای حذف تونل..."
        netplan apply
        
        echo "🔄 راه‌اندازی مجدد systemd-networkd..."
        systemctl restart systemd-networkd
        
        echo "✅ تونل با موفقیت حذف شد!"
    else
        echo "ℹ️  هیچ کانفیگی برای حذف یافت نشد"
    fi
}

function status_tunnel() {
    echo "==============================="
    echo "📈 وضعیت تونل $INTERFACE"
    echo "==============================="
    
    # بررسی وجود interface
    if ip link show "$INTERFACE" &>/dev/null; then
        echo "✅ Interface $INTERFACE فعال است"
        echo
        echo "📊 جزئیات interface:"
        ip addr show "$INTERFACE"
        echo
        
        # بررسی routing
        echo "🛣  جدول مسیریابی IPv6:"
        ip -6 route show dev "$INTERFACE" 2>/dev/null || echo "هیچ مسیری برای این interface یافت نشد"
        echo
        
        # تست ping به gateway
        if [ -f "$CONFIG_SYSTEMD" ]; then
            GATEWAY=$(grep "^Gateway=" "$CONFIG_SYSTEMD" 2>/dev/null | cut -d'=' -f2)
            if [ -n "$GATEWAY" ]; then
                echo "🧪 تست ping به gateway ($GATEWAY):"
                if command -v ping6 &>/dev/null; then
                    ping6 -c 3 -W 2 "$GATEWAY" 2>/dev/null || echo "❌ Gateway در دسترس نیست"
                else
                    ping -6 -c 3 -W 2 "$GATEWAY" 2>/dev/null || echo "❌ Gateway در دسترس نیست"
                fi
            else
                echo "⚠️  Gateway در کانفیگ systemd تعریف نشده"
            fi
        else
            echo "⚠️  کانفیگ systemd-networkd یافت نشد"
        fi
    else
        echo "❌ Interface $INTERFACE یافت نشد یا فعال نیست"
        
        # بررسی وجود کانفیگ فایل‌ها
        if [ -f "$CONFIG_NETPLAN" ]; then
            echo "ℹ️  کانفیگ Netplan موجود است: $CONFIG_NETPLAN"
        fi
        
        if [ -f "$CONFIG_SYSTEMD" ]; then
            echo "ℹ️  کانفیگ systemd موجود است: $CONFIG_SYSTEMD"
        fi
        
        echo
        echo "💡 برای فعالسازی مجدد، دستور زیر را اجرا کنید:"
        echo "   netplan apply && systemctl restart systemd-networkd"
    fi
    
    echo
    echo "📋 وضعیت سرویس systemd-networkd:"
    systemctl is-active systemd-networkd
}

function menu() {
    clear
    echo "==============================="
    echo " 🚀 مدیر تونل IPv6 SIT"
    echo "==============================="
    echo "1) 🛠  راه‌اندازی تونل"
    echo "2) 🧹 حذف تونل"
    echo "3) 📈 نمایش وضعیت تونل"
    echo "4) 🚪 خروج"
    echo "==============================="
    echo
    read -p "گزینه مورد نظر را انتخاب کنید [1-4]: " choice
    
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
            echo "👋 خداحافظ!"
            exit 0
            ;;
        *)
            echo "❌ گزینه نامعتبر. لطفاً عددی بین 1 تا 4 انتخاب کنید"
            ;;
    esac
}

# حلقه اصلی برنامه
while true; do
    menu
    echo
    read -p "برای ادامه Enter را فشار دهید..."
done
