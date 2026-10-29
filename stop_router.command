#!/bin/bash

echo "=========================================="
echo "    Mac NAT Router & DHCP 停止スクリプト   "
echo "=========================================="
echo ""

# 1. 管理者権限の事前確認
sudo -v || exit 1

echo "設定を初期状態に戻しています..."

# 2. DHCPサーバー (bootpd) の停止
sudo killall bootpd 2>/dev/null
echo "  [✓] DHCPサーバー (bootpd) を停止しました"

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

echo ""
echo "=========================================="
echo " ✅ ルーター機能・DHCPを正常に停止しました"
echo "=========================================="
echo ""
read -r -p "Enterキーを押すとウィンドウを閉じます..."
