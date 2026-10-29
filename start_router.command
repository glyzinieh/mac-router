#!/bin/bash

echo "=========================================="
echo "  Mac NAT Router + DHCP (macOS Fix)       "
echo "=========================================="
echo ""

# 1. 管理者権限の事前確認
sudo -v || exit 1

# 終了処理（DHCPおよびNATのクリア）
cleanup() {
    echo ""
    echo "停止処理を実行中..."
    sudo killall bootpd 2>/dev/null
    sudo pfctl -d 2>/dev/null
    sudo sysctl -w net.inet.ip.forwarding=0 > /dev/null
    sudo rm -f /etc/bootpd.plist 2>/dev/null
    echo "ルーターおよびDHCPサーバーを停止しました。"
    exit 0
}
trap cleanup SIGINT SIGTERM EXIT

# 2. 利用可能なネットワークポートの抽出
echo "[1] 利用可能なネットワークポート一覧:"
echo "------------------------------------------"

# ポート名とデバイスIDを配列に格納（macOS互換の読み込み方式）
ports=()
names=()
idx=1

while IFS= read -r line; do
    if [[ $line == "Hardware Port:"* ]]; then
        name="${line#Hardware Port: }"
    elif [[ $line == "Device:"* ]]; then
        dev="${line#Device: }"
        ports+=("$dev")
        names+=("$name")
        printf "  [%d] %-30s (%s)\n" "$idx" "$name" "$dev"
        ((idx++))
    fi
done < <(networksetup -listallhardwareports)

echo "------------------------------------------"
read -r -p "上流（WAN / 802.1X）の番号を選択: " wan_idx
WAN_IF="${ports[$((wan_idx-1))]}"
WAN_NAME="${names[$((wan_idx-1))]}"

read -r -p "下流（LAN / 配下側）の番号を選択: " lan_idx
LAN_IF="${ports[$((lan_idx-1))]}"
LAN_NAME="${names[$((lan_idx-1))]}"

if [ -z "$WAN_IF" ] || [ -z "$LAN_IF" ]; then
    echo "エラー: 正しい番号が選択されませんでした。"
    exit 1
fi

if [ "$WAN_IF" == "$LAN_IF" ]; then
    echo "エラー: 上流と下流に同じポートは選択できません。"
    exit 1
fi

# 3. IPサブネット自動判定
WAN_IP=$(ifconfig "$WAN_IF" | awk '/inet / {print $2}')
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
WAN_DNS_RAW=$(scutil --dns | awk '/scoped DNS configuration/{flag=1} flag; /nameserver/ {if(flag) print $3}' | grep -v '^127\.' | head -n 2)

DNS_XML=""
if [ -z "$WAN_DNS_RAW" ]; then
    DNS_XML="<string>8.8.8.8</string><string>1.1.1.1</string>"
    echo "⚠️ 上流DNSが取得できなかったため、パブリックDNS (8.8.8.8) を使用します。"
else
    echo "✅ 上流DNS検出成功:"
    for dns in $WAN_DNS_RAW; do
        echo "   - $dns"
        DNS_XML="${DNS_XML}<string>${dns}</string>"
    done
fi

# 5. NAT & IP Forwarding の有効化
echo ""
echo "ネットワーク転送とNATを設定中..."
sudo sysctl -w net.inet.ip.forwarding=1 > /dev/null
sudo ifconfig "$LAN_IF" "$LAN_IP" netmask 255.255.255.0 up

echo "nat on $WAN_IF from $LAN_IF:network to any -> ($WAN_IF)" | sudo tee /etc/pf.nat.conf > /dev/null
sudo pfctl -d 2>/dev/null
sudo pfctl -F all > /dev/null 2>&1
sudo pfctl -f /etc/pf.nat.conf -e > /dev/null 2>&1

# 6. macOS標準 DHCP (bootpd.plist) 設定ファイルの生成と起動
sudo killall bootpd 2>/dev/null

cat <<EOF | sudo tee /etc/bootpd.plist > /dev/null
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Subnets</key>
	<array>
		<dict>
			<key>_name</key>
			<string>MacRouterLAN</string>
			<key>net_mask</key>
			<string>255.255.255.0</string>
			<key>net_address</key>
			<string>${LAN_SUBNET}.0</string>
			<key>net_range</key>
			<array>
				<string>${DHCP_START}</string>
				<string>${DHCP_END}</string>
			</array>
			<key>router</key>
			<string>${LAN_IP}</string>
			<key>dhcp_dns_server</key>
			<array>
				${DNS_XML}
			</array>
		</dict>
	</array>
	<key>bootp_enabled</key>
	<false/>
	<key>dhcp_enabled</key>
	<array>
		<string>${LAN_IF}</string>
	</array>
</dict>
</plist>
EOF

# DHCPサーバー起動
sudo /usr/libexec/bootpd -v -c /etc/bootpd.plist &

echo ""
echo "=========================================="
echo " ✅ ルーター機能 ＆ DHCP 稼働中"
echo "=========================================="
echo "  上流 (WAN) : $WAN_NAME ($WAN_IF)"
echo "  下流 (LAN) : $LAN_NAME ($LAN_IF)"
echo "  Gateway IP : $LAN_IP"
echo "  DHCP Range : $DHCP_START 〜 $DHCP_END"
echo "=========================================="
echo ""
read -r -p "Enterキーを押すと停止します..."