# mac-router

macOSを一時的にNATルーターとして動作させるためのスクリプトです。
上流側のネットワーク接続（WAN / 802.1Xなど）を、別のネットワークポートに接続した端末へ共有できます。

## できること

- macOSのIPパケット転送を有効化
- Packet Filter（pf）でLANからWANへのNATを設定
- `bootpd` でLAN側にDHCPサービスを提供
- 上流側のDNSを自動検出してDHCPで配布
- 停止時にDHCP、NAT、IP転送を無効化

## 必要条件

- macOS
- 管理者権限（`sudo`）
- 上流側と下流側に使えるネットワークポートが2つあること
  - 例: Wi-FiをWAN、USB EthernetをLANとして使用
- Bash、`networksetup`、`ifconfig`、`pfctl`、`bootpd` が利用できること

## 使い方

### 1. 実行権限を付与

ターミナルでリポジトリのディレクトリへ移動し、初回のみ実行します。

```bash
chmod +x start_router.command stop_router.command
```

### 2. ルーターを起動

```bash
./start_router.command
```

表示されたネットワークポート一覧から、次の順番で番号を入力します。

1. 上流（WAN / 802.1X）側のポート
2. 下流（LAN / 配下側）側のポート

起動に成功すると、ゲートウェイIP、DHCP配布範囲、配布DNSが表示されます。
起動中はスクリプトの画面でEnterキーを押すまでルーター機能が維持されます。
`Ctrl+C` でも停止処理が実行されます。

DHCPサーバーの起動に失敗した場合はエラーを表示して停止します。下流端末にIPが
割り当てられない場合は、端末側のWi-FiやEthernetを一度切断・再接続し、DHCPを
自動取得にしてください。

### 3. ルーターを停止

別途停止したい場合は、次を実行します。

```bash
./stop_router.command
```

通常は起動スクリプト終了時に停止処理が実行されるため、停止スクリプトは異常終了時や別のターミナルから停止したい場合に使用します。

## `/etc/bootptab`について

このリポジトリのスクリプトは、DHCPの配布範囲やゲートウェイ、DNSを`bootpd`の起動オプションで指定しています。そのため、通常の起動では`/etc/bootptab`を作成する必要はありません。

環境やmacOSの構成によって`bootpd`が`/etc/bootptab`を必要とする場合は、起動前に管理者権限で作成してください。

```bash
sudo cp /etc/bootptab /etc/bootptab.backup 2>/dev/null || true
sudo touch /etc/bootptab
sudo chmod 644 /etc/bootptab
```

固定IPを割り当てる場合は、macOSの`bootpd`が使用する形式でエントリを追加します。たとえば、MACアドレス`aa:bb:cc:dd:ee:ff`の端末に`192.168.2.50`を割り当てる例は次のとおりです。

```text
%%
client:\
    :ht=ethernet:ha=aa:bb:cc:dd:ee:ff:ip=192.168.2.50:
```

`/etc/bootptab`を編集した場合は、起動スクリプトを再実行して`bootpd`を再起動してください。不要になった場合は、バックアップを確認してから作成したファイルを削除するか、元のファイルへ戻してください。

## ネットワーク設定

LAN側のサブネットは次のように自動設定されます。

- 通常: `192.168.2.0/24`
- WAN側IPの先頭3オクテットが `192.168.2` の場合: `192.168.10.0/24`

デフォルトの設定値は次のとおりです。

| 項目 | 値 |
| --- | --- |
| LANゲートウェイ | `192.168.2.1` または `192.168.10.1` |
| DHCP範囲 | `.50` 〜 `.150` |
| サブネットマスク | `255.255.255.0` |
| DNS | 上流DNSを自動検出 |
| DNS検出失敗時 | `8.8.8.8`, `1.1.1.1` |

LAN側インターフェースには、スクリプトがゲートウェイIPを直接設定します。LAN側に接続する端末はDHCPを有効にしてください。

## 注意事項

- このスクリプトはmacOS専用です。LinuxやWindowsでは動作しません。
- `sudo` で実行されるため、内容を確認してから使用してください。
- 起動時に `/etc/pf.nat.conf` を作成し、既存のpfルールを無効化・フラッシュしてNATを設定します。ほかのpf設定を利用中の環境では、意図しない通信影響が出る可能性があります。
- `/etc/bootptab` はスクリプトによって自動作成・削除されません。必要な場合は、内容を確認して手動で管理してください。
- 停止スクリプトは `bootpd` のプロセスを停止します。別の用途で `bootpd` を利用している環境では実行前に確認してください。
- スクリプトはシステムのネットワーク設定を変更します。利用後に状態が戻っていることを確認してください。
- 上流DNSを検出できない場合は、公開DNS（Google Public DNS / Cloudflare DNS）を使用します。

## ファイル

- [`start_router.command`](./start_router.command): NAT、IP転送、DHCPを設定して起動
- [`stop_router.command`](./stop_router.command): DHCP、NAT、IP転送を停止して設定ファイルを削除
