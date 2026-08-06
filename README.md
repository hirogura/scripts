# scripts

スクリプト集。GitHub から直接インストール可能なスクリプトをまとめています。

## スクリプト一覧

| スクリプト | 説明 |
|-----------|------|
| `install-codeserver.sh` | Code-Server（VS Code ブラウザ版）を Ubuntu 26.04 にインストール。localhost のみで待受し、Tailscale serve で tailnet 内のみ HTTPS 公開。Japanese Language Pack と日本語設定を自動適用 |
| `antix-install-codeserver.sh` | Code-Server を antiX（runit 環境）にインストール。root レベル runit サービスで再起動後も自動起動。Tailscale serve で tailnet 内のみ HTTPS 公開 |
| `install-immich.sh` | Immich（写真管理）を Docker でインストール。PostgreSQL / Redis / Machine Learning 込み。Tailscale serve で tailnet 内のみ HTTPS 公開 |

---

## install-immich.sh

### 前提条件

- Docker がインストール済み
- Tailscale が `up` 済み（tailnet 内のみ HTTPS 公開するため）
- Tailscale 管理コンソールで HTTPS Certificates を有効化済み（https://login.tailscale.com/admin/dns）
- 実行時に root 権限が必要（`sudo`）

### インストール方法（GitHub から）

#### 方法1: ダウンロードして実行（推奨）

```bash
curl -fsSL -o /tmp/install-immich.sh \
  https://raw.githubusercontent.com/hirogura/scripts/main/install-immich.sh
sudo bash /tmp/install-immich.sh
```

#### 方法2: ワンライナー（パイプ実行）

```bash
curl -fsSL https://raw.githubusercontent.com/hirogura/scripts/main/install-immich.sh \
  | sudo bash
```

### インストール後にできること

- ブラウザから `https://<Tailscaleのマシン名>:3307` にアクセスすると Immich が開きます（tailnet 内のデバイスからのみ）。
- 初回アクセス時に管理者アカウントを作成します。
- 写真データは `/opt/lxd-data/immich-library/`（ユーザー名フォルダ直下）に保存されます。

### アンインストール方法

```bash
# 1. コンテナを停止・削除（データボリュームも削除）
cd /opt/docker/immich
sudo docker compose down -v

# 2. Tailscale serve の設定を削除
sudo tailscale serve --https=3307 off

# 3. 設定ファイル・DBデータ・キャッシュを削除
sudo rm -rf /opt/docker/immich

# 4. 写真データを削除（残したい場合はスキップ）
sudo rm -rf /opt/lxd-data/immich-library
```

> 手順 4 の写真データは削除すると復元できません。残したい場合はスキップしてください。

---

## install-codeserver.sh

### 前提条件

- Ubuntu 26.04
- Tailscale が `up` 済み（tailnet 内のみ HTTPS 公開するため）
- 実行時に root 権限が必要（`sudo`）

### インストール方法（GitHub から）

#### 方法1: ダウンロードして実行（推奨）

```bash
curl -fsSL -o /tmp/install-codeserver.sh \
  https://raw.githubusercontent.com/hirogura/scripts/main/install-codeserver.sh
sudo bash /tmp/install-codeserver.sh
```

#### 方法2: ワンライナー（パイプ実行）

```bash
curl -fsSL https://raw.githubusercontent.com/hirogura/scripts/main/install-codeserver.sh \
  | sudo bash
```

> 実行中に code-server のパスワードを尋ねられます。
> `[A]` でランダム自動生成（32文字）、`[M]` で手動入力。

### インストール後にできること

- ブラウザから `https://<Tailscaleのマシン名>:8089` にアクセスすると VS Code が開きます（tailnet 内のデバイスからのみ）。
- ログイン時に入力したパスワードでログインします（`~/.config/code-server/config.yaml` にも保存されています）。
- 日本語 UI は上のバーで下記を入力して「日本語」を選択。

```bash
>Configure Display Language
```
### アンインストール方法

```bash
# 1. systemd サービスを停止・無効化・削除
sudo systemctl stop code-server
sudo systemctl disable code-server
sudo rm -f /etc/systemd/system/code-server.service
sudo systemctl daemon-reload

# 2. Tailscale serve の設定を削除
sudo tailscale serve --https=8089 off

# 3. code-server 本体を削除
sudo apt-get remove --purge -y code-server

# 4. 設定・拡張機能・データを削除（必要に応じて）
rm -rf ~/.config/code-server
rm -rf ~/.local/share/code-server
rm -rf ~/.cache/code-server
```

> `~/.config/code-server/config.yaml` にはパスワードが含まれているため、削除前に安全な場所へ保管するか、ログアウト等の準備をしてください。

---

## antix-install-codeserver.sh

### 前提条件

- antiX（runit 使用のシステム）
- Tailscale が `up` 済み（tailnet 内のみ HTTPS 公開するため）
- 実行時に root 権限が必要（`sudo`）

### インストール方法（GitHub から）

#### 方法1: ダウンロードして実行（推奨）

```bash
curl -fsSL -o /tmp/antix-install-codeserver.sh \
  https://raw.githubusercontent.com/hirogura/scripts/main/antix-install-codeserver.sh
sudo bash /tmp/antix-install-codeserver.sh
```

#### 方法2: ワンライナー（パイプ実行）

```bash
curl -fsSL https://raw.githubusercontent.com/hirogura/scripts/main/antix-install-codeserver.sh \
  | sudo bash
```

> 実行中に code-server のパスワードを尋ねられます。
> `[A]` でランダム自動生成（32文字）、`[M]` で手動入力。

オプションも指定できます:

```bash
sudo bash /tmp/antix-install-codeserver.sh -p mypass        # パスワード指定
sudo bash /tmp/antix-install-codeserver.sh -a -y            # 自動生成・確認なし
sudo bash /tmp/antix-install-codeserver.sh -p pass -P 9090  # ポート変更
```

### インストール後にできること

- ブラウザから `https://<Tailscaleのマシン名>:8089` にアクセスすると VS Code が開きます（tailnet 内のデバイスからのみ）。
- code-server は root レベルの runit サービスとして登録されるため、再起動後も自動的に起動します。
- ログイン時に入力したパスワードでログインします（`~/.config/code-server/config.yaml` にも保存されています）。
- 日本語 UI は自動設定済みです。

### アンインストール方法

```bash
# 1. runit サービスを停止・削除
sudo sv stop code-server
sudo rm -f /etc/service/code-server
sudo rm -rf /etc/sv/code-server
sudo rm -f /usr/local/bin/code-server-wrapper

# 2. Tailscale serve の設定を削除
sudo tailscale serve --https=8089 off

# 3. code-server 本体を削除
sudo dpkg -r code-server

# 4. 設定・拡張機能・データを削除（必要に応じて）
rm -rf ~/.config/code-server
rm -rf ~/.local/share/code-server
rm -rf ~/.cache/code-server
```

> `~/.config/code-server/config.yaml` にはパスワードが含まれているため、削除前に安全な場所へ保管するか、ログアウト等の準備をしてください。

---

## 注意事項

- このリポジトリにはデータベースやパスワードなどの個人情報を **push しない**でください。
  `.gitignore` で主要なファイル（`*.db` / `*.sqlite*` / `*.key` / `*.pem` / `.env` / `config.yaml` 等）を除外済みです。
