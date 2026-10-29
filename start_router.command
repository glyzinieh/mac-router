#!/bin/bash

echo "=========================================="
echo "  Mac NAT Router + DHCP (DNS Auto-Detect) "
echo "=========================================="
echo ""

# 1. 管理者権限の事前確認
sudo -v || exit 1

# 終了処理
cleanup() {
    echo ""
    echo "停止処理を実行中..."
    sudo killall bootpd 2>/dev/null
    sudo pfctl -d 2>/dev/null
    sudo sysctl -w net.inet.ip.forwarding=0 > /dev/null
    echo "ルーターおよびDHCPサーバーを停止しました。"
    exit 0
}
trap cleanup SIGINT SIGTERM EXIT

# 2. ポートの選択
echo "[1] 利用可能なネットワークポート一覧:"
echo "------------------------------------------"
networksetup -listallhardwareports | grep -E "(Hardware Port|Device)" | paste - - | sed 's/Hardware Port: //g' | sed 's/Device: //g' | awk '{printf "  [%d] %-30s (%s)\n", NR, $1, $2}'

mapfile -t ports < <(networksetup -listallhardwareports | grep -E "Device:" | awk '{print $2}')
mapfile -t names < <(networksetup -listallhardwareports | grep -E "Hardware Port:" | sed 's/Hardware Port: //g')

echo "------------------------------------------"
read -p "上流（WAN / 802.1X）の番号を選択: " wan_idx
WAN_IF="${ports[$((wan_idx-1))]}"
WAN_NAME="${names[$((wan_idx-1))]}"

read -p "下流（LAN / 配下側）の番号を選択: " lan_idx
LAN_IF="${ports[$((lan_idx-1))]}"
LAN_NAME="${names[$((lan_idx-1))]}"

# 3. IPサブネット自動判定
WAN_IP=$(ifconfig "$WAN_IF" | grep 'inet ' | awk '{print $2}')
LAN_SUBNET="192.168.2"

if [ -n "$WAN_IP" ]; then
    WAN_SUBNET=$(echo "$WAN_IP" | cut -d. -f1-3)
    if [ "$WAN_SUBNET" == "$LAN_SUBNET" ]; then
        LAN_SUBNET="192.168.10"
    fi
fi

LAN_IP="$LAN_SUBNET.1"
DHCP_START="$LAN_SUBNET.50"
DHCP_END="$LAN_SUBNET.150"

# 4. 上流DNSの自動検出
echo ""
echo "上流のDNSアドレスを取得中..."
WAN_DNS=$(scutil --dns | awk '/scoped DNS configuration/{flag=1} flag; /nameserver/ {if(flag) print $3}' | grep -v '^127\.' | xargs | tr ' ' ',')

if [ -z "$WAN_DNS" ]; then
    WAN_DNS="8.8.8.8,1.1.1.1"
    echo "⚠️ 上流DNSが取得できなかったため、デフォルトDNS ($WAN_DNS) を使用します。"
else
    echo "✅ 上流DNS検出成功: $WAN_DNS"
fi

# 5. NAT & IP Forwarding の有効化
sudo sysctl -w net.inet.ip.forwarding=1 > /dev/null
sudo ifconfig "$LAN_IF" "$LAN_IP" netmask 255.255.255.0 up

echo "nat on $WAN_IF from $LAN_IF:network to any -> ($WAN_IF)" | sudo tee /etc/pf.nat.conf > /dev/null
sudo pfctl -d 2>/dev/null
sudo pfctl -F all > /dev/null 2>&1
sudo pfctl -f /etc/pf.nat.conf -e > /dev/null 2>&1

# 6. DHCPサーバー (bootpd) 起動
sudo killall bootpd 2>/dev/null
sudo /usr/libexec/bootpd -D -i "$LAN_IF" -r "$DHCP_START" -e "$DHCP_END" -m 255.255.255.0 -g "$LAN_IP" -d "$WAN_DNS" &

echo ""
echo "=========================================="
echo " ルーター機能 ＆ DHCP 稼働中"
echo "=========================================="
echo "  Gateway IP  : $LAN_IP"
echo "  DHCP Range  : $DHCP_START 〜 $DHCP_END"
echo "  配布 DNS    : $WAN_DNS"
echo "=========================================="
echo ""
read -r -p "Enterキーを押すと停止します..."
