# scripts

スクリプト集。GitHub から直接インストール可能なスクリプトをまとめています。

## スクリプト一覧

| スクリプト | 説明 |
|-----------|------|
| `install-codeserver.sh` | Code-Server（VS Code ブラウザ版）を Ubuntu 26.04 にインストール。localhost のみで待受し、Tailscale serve で tailnet 内のみ HTTPS 公開。Japanese Language Pack と日本語設定を自動適用 |

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

## 注意事項

- このリポジトリにはデータベースやパスワードなどの個人情報を **push しない**でください。
  `.gitignore` で主要なファイル（`*.db` / `*.sqlite*` / `*.key` / `*.pem` / `.env` / `config.yaml` 等）を除外済みです。
