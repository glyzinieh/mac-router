#!/bin/bash

echo "=========================================="
echo "    Mac NAT Router & DHCP 停止スクリプト   "
echo "=========================================="
echo ""

# 1. 管理者権限の事前確認
sudo -v || exit 1

echo "設定を初期状態に戻しています..."

# 2. DHCPサーバー (dnsmasq) の停止
DNSMASQ_PID_FILE="/var/run/mac-router-dnsmasq.pid"
DNSMASQ_LEASE_FILE="/tmp/mac-router-dnsmasq.leases"
if [ -f "$DNSMASQ_PID_FILE" ]; then
    DNSMASQ_PID=$(sudo cat "$DNSMASQ_PID_FILE" 2>/dev/null)
    if [ -n "$DNSMASQ_PID" ] && sudo kill -0 "$DNSMASQ_PID" 2>/dev/null; then
        sudo kill "$DNSMASQ_PID" 2>/dev/null
    fi
    sudo rm -f "$DNSMASQ_PID_FILE"
fi
echo "  [✓] DHCPサーバー (dnsmasq) を停止しました"

# 3. Packet Filter (pf) NAT機能の無効化
sudo pfctl -d 2>/dev/null
echo "  [✓] NAT (pf) を無効化しました"

# 4. IP Forwarding（パケット転送）の無効化
sudo sysctl -w net.inet.ip.forwarding=0 > /dev/null
echo "  [✓] IP転送 (ip.forwarding) を停止しました"

# 5. 一時作成した設定ファイルの削除
if [ -f /etc/pf.nat.conf ]; then
    sudo rm /etc/pf.nat.conf
    echo "  [✓] NAT設定ファイルを削除しました"
fi

if [ -f /etc/mac-router-dnsmasq.conf ]; then
    sudo rm /etc/mac-router-dnsmasq.conf
    echo "  [✓] dnsmasq設定ファイルを削除しました"
fi
rm -f /tmp/mac-router-dnsmasq.log
rm -f "$DNSMASQ_LEASE_FILE"

echo ""
echo "=========================================="
echo " ✅ ルーター機能・DHCPを正常に停止しました"
echo "=========================================="
echo ""
read -r -p "Enterキーを押すとウィンドウを閉じます..."
