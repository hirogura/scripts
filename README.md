# scripts

スクリプト集。GitHub から直接インストール可能なスクリプトをまとめています。

## スクリプト一覧

| スクリプト | 説明 |
|-----------|------|
| `install-codeserver.sh` | Code-Server（VS Code ブラウザ版）を Ubuntu 26.04 にインストール。localhost のみで待受し、Tailscale serve で tailnet 内のみ HTTPS 公開。Japanese Language Pack と日本語設定を自動適用 |
| `antix-install-codeserver.sh` | Code-Server を antiX（runit 環境）にインストール。root レベル runit サービスで再起動後も自動起動。Tailscale serve で tailnet 内のみ HTTPS 公開 |
| `install-immich.sh` | Immich（写真管理）を Docker でインストール。PostgreSQL / Redis / Machine Learning 込み。Tailscale serve で tailnet 内のみ HTTPS 公開 |
| `antix-ibus-mozc.sh` | 日本語入力（ibus + Mozc）を antiX（desktop-session）にセットアップ。切り替えキーに半角/全角を追加し、起動時のデフォルトをひらがなに設定 |
| `antix-install-thunderbird.sh` | メーラー Thunderbird を antiX にインストール。日本語パック（thunderbird-l10n-ja）もリポジトリにあれば導入 |
| `antix-install-vlc.sh` | メディアプレイヤー VLC を antiX にインストール。日本語パック（vlc-l10n）もリポジトリにあれば導入 |
| `antix-desktop-shortcut.sh` | LibreOffice（Calc / Writer / Impress）とシャットダウン / 再起動のショートカットを antiX のデスクトップ（`~/Desktop`）に作成 |
| `antix-install-xnviewmp.sh` | 画像ビューア XnView MP を antiX にインストール。公式サイトから deb パッケージを直接ダウンロードして導入 |
| `antix-install-chrome.sh` | ブラウザ Google Chrome を antiX にインストール。デスクトップショートカットも自動で作成 |
| `antix-install-vscode.sh` | エディター Visual Studio Code を antiX にインストール。日本語言語パック適用とデスクトップショートカット作成を自動で実行 |
| `antix-install-tailscale` | VPN サービス Tailscale を antiX にインストール。runit サービスとして登録し再起動後も自動起動 |
| `antix-install-krita.sh` | ペイントアプリ Krita を antiX にインストール。日本語パック（krita-l10n）もリポジトリにあれば導入し、デスクトップショートカットも自動で作成 |
| `antix-mouse.sh` | デスクトップアイコンのクリック動作を「シングルクリック=選択 / ダブルクリック=実行」に変更（ZzzFM / ROX-Filer / Nautilus / Caja / Nemo / Thunar / Dolphin） |

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

## antix-ibus-mozc.sh

### 前提条件

- antiX（IceWM / Fluxbox 等の desktop-session を使用）
- デスクトップセッション（`~/.desktop-session`）と gsettings を設定するため、**通常ユーザーで実行**してください（内部で必要な `sudo` は自動実行されます）
- パッケージインストールのためインターネット接続が必要

### インストール方法（GitHub から）

#### 方法1: ダウンロードして実行（推奨）

```bash
curl -fsSL -o /tmp/antix-ibus-mozc.sh \
  https://raw.githubusercontent.com/hirogura/scripts/main/antix-ibus-mozc.sh
bash /tmp/antix-ibus-mozc.sh
```

#### 方法2: ワンライナー（パイプ実行）

```bash
curl -fsSL https://raw.githubusercontent.com/hirogura/scripts/main/antix-ibus-mozc.sh \
  | bash
```

> 注意: このスクリプトは `sudo bash` ではなく**通常ユーザーで実行**してください。
> `sudo` で実行すると `/root` 以下に設定が書き込まれてしまいます。

### インストール後にできること

- 入力エンジンが **Mozc（日本語）** と **英語(US)** の 2 つだけになり、`半角/全角` キーまたは `Ctrl+Space` で切り替えられます。
- Mozc 起動時の入力モードが「ひらがな」になります。
- ログアウト → 再ログイン後にスクリプトをもう一度実行すると、gsettings によるエンジン/キー設定が反映されます。

### アンインストール方法

#### 方法1: スクリプトのアンインストールモード（推奨）

```bash
bash /tmp/antix-ibus-mozc.sh -u
```

#### 方法2: 手動

```bash
# 1. gsettings の設定をリセット
gsettings reset org.freedesktop.ibus.general preload-engines
gsettings reset org.freedesktop.ibus.general engines-order
gsettings reset org.freedesktop.ibus.general.hotkey trigger

# 2. desktop-session.conf から im_module="ibus" を含む追記ブロックを削除
# 3. startup から ibus-daemon -drx の行を削除
# 4. Mozc のユーザー設定を削除
rm -rf ~/.config/mozc

# 5. パッケージを削除
sudo apt remove --purge -y ibus-mozc fonts-noto-cjk
#    ibus 本体は他のアプリでも使う可能性があるため削除しません。
#    削除したい場合のみ: sudo apt remove --purge -y ibus ibus-gtk ibus-gtk3 ibus-gtk4
```

> アンインストール後は一度ログアウト → 再ログイン（または X の再起動）してください。

---

## antix-install-thunderbird.sh

### 前提条件

- antiX（runit 使用のシステム）
- パッケージインストールのためインターネット接続が必要
- 実行時に root 権限が必要（`sudo`）

### インストール方法（GitHub から）

#### 方法1: ダウンロードして実行（推奨）

```bash
curl -fsSL -o /tmp/antix-install-thunderbird.sh \
  https://raw.githubusercontent.com/hirogura/scripts/main/antix-install-thunderbird.sh
sudo bash /tmp/antix-install-thunderbird.sh
```

#### 方法2: ワンライナー（パイプ実行）

```bash
curl -fsSL https://raw.githubusercontent.com/hirogura/scripts/main/antix-install-thunderbird.sh \
  | sudo bash
```

### インストール後にできること

- デスクトップメニュー、デスクトップのショートカット、または `thunderbird` コマンドから起動できます。
- リポジトリにあれば日本語言語パック（`thunderbird-l10n-ja`）も自動インストールされます。
- `sudo` で実行したユーザーのデスクトップ（`~/Desktop`）に `thunderbird.desktop` のショートカットが自動で作成されます。

### アンインストール方法

```bash
sudo bash /tmp/antix-install-thunderbird.sh -u
```

> アンインストールすると、`sudo` で実行したユーザーのメールデータ（`~/.thunderbird`）も削除されます。残したい場合は事前にバックアップしてください。

---

## antix-install-vlc.sh

### 前提条件

- antiX（runit 使用のシステム）
- パッケージインストールのためインターネット接続が必要
- 実行時に root 権限が必要（`sudo`）

### インストール方法（GitHub から）

#### 方法1: ダウンロードして実行（推奨）

```bash
curl -fsSL -o /tmp/antix-install-vlc.sh \
  https://raw.githubusercontent.com/hirogura/scripts/main/antix-install-vlc.sh
sudo bash /tmp/antix-install-vlc.sh
```

#### 方法2: ワンライナー（パイプ実行）

```bash
curl -fsSL https://raw.githubusercontent.com/hirogura/scripts/main/antix-install-vlc.sh \
  | sudo bash
```

### インストール後にできること

- デスクトップメニュー、デスクトップのショートカット、または `vlc` コマンドから起動できます。
- リポジトリにあれば日本語パック（`vlc-l10n`）も自動インストールされます。
- `sudo` で実行したユーザーのデスクトップ（`~/Desktop`）に `vlc.desktop` のショートカットが自動で作成されます。

### アンインストール方法

```bash
sudo bash /tmp/antix-install-vlc.sh -u
```

> アンインストールすると、`sudo` で実行したユーザーの設定（`~/.config/vlc`）も削除されます。

---

## antix-desktop-shortcut.sh

### 前提条件

- antiX（IceWM / Fluxbox 等のデスクトップ環境）
- ショートカットを作成するユーザーで実行してください（`sudo` は不要）

### 使用方法（GitHub から）

#### 方法1: ダウンロードして実行（推奨）

```bash
curl -fsSL -o /tmp/antix-desktop-shortcut.sh \
  https://raw.githubusercontent.com/hirogura/scripts/main/antix-desktop-shortcut.sh
bash /tmp/antix-desktop-shortcut.sh
```

#### 方法2: ワンライナー（パイプ実行）

```bash
curl -fsSL https://raw.githubusercontent.com/hirogura/scripts/main/antix-desktop-shortcut.sh \
  | bash
```

> 注意: このスクリプトは `sudo` で実行せず、ショートカットを配置したいユーザーで実行してください。
> `sudo` で実行すると `/root/Desktop` に作成されてしまいます。

### 作成されるショートカット

実行ユーザーの `~/Desktop` に以下が作成されます:

| ショートカット | 説明 |
|---------------|------|
| `libreoffice-calc.desktop` | LibreOffice Calc |
| `libreoffice-writer.desktop` | LibreOffice Writer |
| `libreoffice-impress.desktop` | LibreOffice Impress |
| `shutdown.desktop` | シャットダウン |
| `reboot.desktop` | 再起動 |

> Google Chrome / Thunderbird / VLC / XnView MP / VS Code / Krita 等のアプリのショートカットは、各インストールスクリプト（`antix-install-chrome.sh` 等）がインストール時に自動で作成します。
> シャットダウン / 再起動は antiX 標準の `desktop-session-exit` を使用します。antiX には `/etc/sudoers.d/antixers` で `poweroff` / `reboot` の NOPASSWD ルールが最初から設定されているため、パスワード入力なしで実行できます。

### ショートカット削除方法

```bash
bash /tmp/antix-desktop-shortcut.sh -u
```

---

## antix-install-xnviewmp.sh

### 前提条件

- antiX（runit 使用のシステム）
- パッケージインストールのためインターネット接続が必要
- 実行時に root 権限が必要（`sudo`）

### インストール方法（GitHub から）

#### 方法1: ダウンロードして実行（推奨）

```bash
curl -fsSL -o /tmp/antix-install-xnviewmp.sh \
  https://raw.githubusercontent.com/hirogura/scripts/main/antix-install-xnviewmp.sh
sudo bash /tmp/antix-install-xnviewmp.sh
```

#### 方法2: ワンライナー（パイプ実行）

```bash
curl -fsSL https://raw.githubusercontent.com/hirogura/scripts/main/antix-install-xnviewmp.sh \
  | sudo bash
```

### インストール後にできること

- デスクトップメニュー、デスクトップのショートカット、または `xnview` コマンドから起動できます。
- XnView MP は Debian 公式リポジトリに存在しないため、xnview.com 公式サイトから deb パッケージを直接ダウンロードして導入します。
- `sudo` で実行したユーザーのデスクトップ（`~/Desktop`）に `xnviewmp.desktop` のショートカットが自動で作成されます。

### アンインストール方法

```bash
sudo bash /tmp/antix-install-xnviewmp.sh -u
```

> アンインストールすると、`sudo` で実行したユーザーの設定（`~/.config/xnviewmp`）も削除されます。

---

## antix-install-chrome.sh

### 前提条件

- antiX（runit 使用のシステム）
- パッケージインストールのためインターネット接続が必要
- 実行時に root 権限が必要（`sudo`）

### インストール方法（GitHub から）

#### 方法1: ダウンロードして実行（推奨）

```bash
curl -fsSL -o /tmp/antix-install-chrome.sh \
  https://raw.githubusercontent.com/hirogura/scripts/main/antix-install-chrome.sh
sudo bash /tmp/antix-install-chrome.sh
```

#### 方法2: ワンライナー（パイプ実行）

```bash
curl -fsSL https://raw.githubusercontent.com/hirogura/scripts/main/antix-install-chrome.sh \
  | sudo bash
```

### インストール後にできること

- デスクトップメニュー、デスクトップのショートカット、または `google-chrome-stable` コマンドから起動できます。
- `sudo` で実行したユーザーのデスクトップ（`~/Desktop`）に `google-chrome.desktop` のショートカットが自動で作成されます。

### アンインストール方法

```bash
sudo bash /tmp/antix-install-chrome.sh -u
```

> アンインストールすると、`sudo` で実行したユーザーのブラウザデータ（`~/.config/google-chrome`）も削除されます。残したい場合は事前にバックアップしてください。

---

## antix-install-vscode.sh

### 前提条件

- antiX（runit 使用のシステム）
- パッケージインストールのためインターネット接続が必要
- 実行時に root 権限が必要（`sudo`）

### インストール方法（GitHub から）

#### 方法1: ダウンロードして実行（推奨）

```bash
curl -fsSL -o /tmp/antix-install-vscode.sh \
  https://raw.githubusercontent.com/hirogura/scripts/main/antix-install-vscode.sh
sudo bash /tmp/antix-install-vscode.sh
```

#### 方法2: ワンライナー（パイプ実行）

```bash
curl -fsSL https://raw.githubusercontent.com/hirogura/scripts/main/antix-install-vscode.sh \
  | sudo bash
```

### インストール後にできること

- デスクトップメニュー、デスクトップのショートカット、または `code` コマンドから起動できます。
- 日本語言語パック（`MS-CEINTL.vscode-language-pack-ja`）が `sudo` で実行したユーザー向けに自動インストールされます。
- `sudo` で実行したユーザーのデスクトップ（`~/Desktop`）に `code.desktop` のショートカットが自動で作成されます。

### アンインストール方法

```bash
sudo bash /tmp/antix-install-vscode.sh -u
```

> アンインストールすると、`sudo` で実行したユーザーの設定・拡張機能（`~/.vscode`）も削除されます。残したい場合は事前にバックアップしてください。

---

## antix-install-tailscale

### 前提条件

- antiX（runit 使用のシステム）
- パッケージインストールのためインターネット接続が必要
- 実行時に root 権限が必要（`sudo`）

### インストール方法（GitHub から）

#### 方法1: ダウンロードして実行（推奨）

```bash
curl -fsSL -o /tmp/antix-install-tailscale \
  https://raw.githubusercontent.com/hirogura/scripts/main/antix-install-tailscale
sudo bash /tmp/antix-install-tailscale
```

#### 方法2: ワンライナー（パイプ実行）

```bash
curl -fsSL https://raw.githubusercontent.com/hirogura/scripts/main/antix-install-tailscale \
  | sudo bash
```

> 実行するとブラウザで Tailscale への認証が開きます。認証が完了すると tailnet に参加します。

### インストール後にできること

- `tailscale` / `tailscaled` コマンドが利用できます。
- tailscaled は root レベルの runit サービス（`/etc/sv/tailscaled`）として登録されるため、再起動後も自動的に起動します。
- 認証済みの状態は `/var/lib/tailscale/tailscaled.state` に保存されます。

### アンインストール方法

```bash
sudo bash /tmp/antix-install-tailscale -u
```

> アンインストールすると tailnet から退出し、状態データ（`/var/lib/tailscale`）も削除されます。再インストール時は改めて認証が必要です。必要に応じて Tailscale 管理コンソール（https://login.tailscale.com/admin）からこのマシンを削除してください。

---

## antix-install-krita.sh

### 前提条件

- antiX（runit 使用のシステム）
- パッケージインストールのためインターネット接続が必要
- 実行時に root 権限が必要（`sudo`）

### インストール方法（GitHub から）

#### 方法1: ダウンロードして実行（推奨）

```bash
curl -fsSL -o /tmp/antix-install-krita.sh \
  https://raw.githubusercontent.com/hirogura/scripts/main/antix-install-krita.sh
sudo bash /tmp/antix-install-krita.sh
```

#### 方法2: ワンライナー（パイプ実行）

```bash
curl -fsSL https://raw.githubusercontent.com/hirogura/scripts/main/antix-install-krita.sh \
  | sudo bash
```

### インストール後にできること

- デスクトップメニュー、デスクトップのショートカット、または `krita` コマンドから起動できます。
- リポジトリにあれば日本語パック（`krita-l10n`）も自動インストールされます。
- `sudo` で実行したユーザーのデスクトップ（`~/Desktop`）に `krita.desktop` のショートカットが自動で作成されます。

### アンインストール方法

```bash
sudo bash /tmp/antix-install-krita.sh -u
```

> アンインストールすると、`sudo` で実行したユーザーの設定（`~/.config/krita` 等）も削除されます。

---

## antix-mouse.sh

### 前提条件

- antiX（IceWM / Fluxbox 等のデスクトップ環境）
- 設定は実行ユーザーのホームディレクトリに書き込むため、**通常ユーザーで実行**してください（`sudo` は不要）

### インストール方法（GitHub から）

#### 方法1: ダウンロードして実行（推奨）

```bash
curl -fsSL -o /tmp/antix-mouse.sh \
  https://raw.githubusercontent.com/hirogura/scripts/main/antix-mouse.sh
bash /tmp/antix-mouse.sh
```

#### 方法2: ワンライナー（パイプ実行）

```bash
curl -fsSL https://raw.githubusercontent.com/hirogura/scripts/main/antix-mouse.sh \
  | bash
```

> 注意: このスクリプトは `sudo` で実行せず、設定を変更したいユーザーで実行してください。
> `sudo` で実行すると `/root` の設定が変更されてしまいます。

### インストール後にできること

- デスクトップアイコンが「シングルクリック=選択 / ダブルクリック=実行」になります。
- 対応環境に自動で適用されます（ZzzFM / ROX-Filer / Nautilus / Caja / Nemo / Thunar / Dolphin）。
- ドライラン（`-n`）で変更内容の確認だけができます。
- 対象ユーザー名を指定すると、そのユーザーの設定を変更できます（要 `root`）。

### アンインストール方法

```bash
bash /tmp/antix-mouse.sh -u
```

> アンインストールするとデスクトップアイコンのクリック動作が「シングルクリック=実行」のデフォルトに戻ります。

---

## 注意事項

- このリポジトリにはデータベースやパスワードなどの個人情報を **push しない**でください。
  `.gitignore` で主要なファイル（`*.db` / `*.sqlite*` / `*.key` / `*.pem` / `.env` / `config.yaml` 等）を除外済みです。
