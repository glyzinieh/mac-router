#!/bin/bash

echo "=========================================="
echo "  Mac NAT Router + DHCP (macOS Fix)       "
echo "=========================================="
echo ""

# 1. 管理者権限の事前確認
sudo -v || exit 1

DNSMASQ_CONF="/etc/mac-router-dnsmasq.conf"
DNSMASQ_PID_FILE="/var/run/mac-router-dnsmasq.pid"
DNSMASQ_LOG="/tmp/mac-router-dnsmasq.log"
DNSMASQ_LEASE_FILE="/tmp/mac-router-dnsmasq.leases"
DNSMASQ_PID=""

# 終了処理（DHCPおよびNATのクリア）
cleanup() {
    echo ""
    echo "停止処理を実行中..."
    if [ -n "$DNSMASQ_PID" ] && sudo kill -0 "$DNSMASQ_PID" 2>/dev/null; then
        sudo kill "$DNSMASQ_PID" 2>/dev/null
    fi
    sudo pfctl -d 2>/dev/null
    sudo sysctl -w net.inet.ip.forwarding=0 > /dev/null
    sudo rm -f "$DNSMASQ_CONF" "$DNSMASQ_PID_FILE" "$DNSMASQ_LOG" "$DNSMASQ_LEASE_FILE" 2>/dev/null
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

DNSMASQ_DNS_SERVERS=""
if [ -z "$WAN_DNS_RAW" ]; then
    DNSMASQ_DNS_SERVERS="8.8.8.8,1.1.1.1"
    echo "⚠️ 上流DNSが取得できなかったため、パブリックDNS (8.8.8.8) を使用します。"
else
    echo "✅ 上流DNS検出成功:"
    for dns in $WAN_DNS_RAW; do
        echo "   - $dns"
        if [ -n "$DNSMASQ_DNS_SERVERS" ]; then
            DNSMASQ_DNS_SERVERS="${DNSMASQ_DNS_SERVERS},"
        fi
        DNSMASQ_DNS_SERVERS="${DNSMASQ_DNS_SERVERS}${dns}"
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

# 6. dnsmasq (DHCP専用) の設定と起動
if ! command -v dnsmasq > /dev/null 2>&1; then
    echo "エラー: dnsmasq が見つかりません。HomebrewまたはMacPortsでインストールしてください。"
    echo "       sudo port install dnsmasq"
    exit 1
fi

cat <<EOF | sudo tee "$DNSMASQ_CONF" > /dev/null
interface=${LAN_IF}
bind-interfaces
dhcp-authoritative
dhcp-range=${DHCP_START},${DHCP_END},255.255.255.0,12h
dhcp-option=3,${LAN_IP}
dhcp-option=6,${DNSMASQ_DNS_SERVERS}
no-dhcp-interface=${WAN_IF}
port=0
pid-file=${DNSMASQ_PID_FILE}
dhcp-leasefile=${DNSMASQ_LEASE_FILE}
log-dhcp
EOF

# 前回の異常終了で残った、このルーター専用のdnsmasqを停止します。
if [ -f "$DNSMASQ_PID_FILE" ]; then
    OLD_DNSMASQ_PID=$(sudo cat "$DNSMASQ_PID_FILE" 2>/dev/null)
    if [ -n "$OLD_DNSMASQ_PID" ] && sudo kill -0 "$OLD_DNSMASQ_PID" 2>/dev/null; then
        sudo kill "$OLD_DNSMASQ_PID" 2>/dev/null
        sleep 1
    fi
    sudo rm -f "$DNSMASQ_PID_FILE"
fi

sudo dnsmasq --conf-file="$DNSMASQ_CONF" --no-daemon > "$DNSMASQ_LOG" 2>&1 &
DNSMASQ_PID=$!
sleep 1
if ! sudo kill -0 "$DNSMASQ_PID" 2>/dev/null; then
    echo "エラー: DHCPサーバー (dnsmasq) の起動に失敗しました。"
    echo "----- dnsmasq のログ -----"
    sudo cat "$DNSMASQ_LOG" 2>/dev/null
    exit 1
fi

echo ""
echo "=========================================="
echo " ✅ ルーター機能 ＆ DHCP 稼働中"
echo "=========================================="
echo "  上流 (WAN) : $WAN_NAME ($WAN_IF)"
echo "  下流 (LAN) : $LAN_NAME ($LAN_IF)"
echo "  Gateway IP : $LAN_IP"
echo "  DHCP Range : $DHCP_START 〜 $DHCP_END"
echo "  DHCP Server: dnsmasq"
echo "=========================================="
echo ""
read -r -p "Enterキーを押すと停止します..."
