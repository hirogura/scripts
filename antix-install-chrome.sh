#!/bin/bash
# ============================================================
#  Google Chrome インストールスクリプト
#  antiX（runit init）向け
#
#  インストール方法（GitHub から）:
#    1) curl -fsSL -o /tmp/antix-install-chrome.sh \
#       https://raw.githubusercontent.com/hirogura/scripts/main/antix-install-chrome.sh
#    2) sudo bash /tmp/antix-install-chrome.sh
#    ワンライナー（パイプ実行）でも可:
#       curl -fsSL https://raw.githubusercontent.com/hirogura/scripts/main/antix-install-chrome.sh \
#         | sudo bash
#  アンインストール方法は README.md を参照
#
#  使い方:
#    sudo bash antix-install-chrome.sh              # インストール（既定）
#    sudo bash antix-install-chrome.sh -u           # アンインストール
#    sudo bash antix-install-chrome.sh -h           # ヘルプ表示
# ============================================================

set -euo pipefail

usage() {
    echo "使い方:"
    echo "  sudo bash $0              # インストール（既定）"
    echo "  sudo bash $0 -u           # アンインストール"
    echo "  sudo bash $0 -h           # このヘルプを表示"
    echo ""
    echo "インストール:"
    echo "  curl -fsSL -o /tmp/antix-install-chrome.sh \\"
    echo "    https://raw.githubusercontent.com/hirogura/scripts/main/antix-install-chrome.sh"
    echo "  sudo bash /tmp/antix-install-chrome.sh"
    echo "アンインストール:"
    echo "  sudo bash /tmp/antix-install-chrome.sh -u"
}

MODE=install
for arg in "$@"; do
    case "$arg" in
        -h|--help)      usage; exit 0 ;;
        -u|--uninstall) MODE=uninstall ;;
        *)              echo "不明なオプション: $arg" >&2; usage; exit 1 ;;
    esac
done

# --- root権限チェック ---
if [ "$(id -u)" -ne 0 ]; then
    echo "エラー: このスクリプトは root権限で実行してください。"
    echo "例: sudo bash $0"
    exit 1
fi

# --- 実行ユーザー（sudo で実行した場合はそのユーザー） ---
REAL_USER="${SUDO_USER:-root}"
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

GPG_KEY="/etc/apt/trusted.gpg.d/google-chrome.gpg"
REPO_LIST="/etc/apt/sources.list.d/google-chrome.list"

# ------------------------------------------------------------
# インストール
# ------------------------------------------------------------
install() {
    echo "=== antiX26 Google Chrome インストール開始 ==="
    echo

    # --- 既にインストール済みか確認 ---
    if command -v google-chrome-stable >/dev/null 2>&1; then
        echo "Google Chrome は既にインストールされています。"
        google-chrome-stable --version
        exit 0
    fi

    # --- 必要なパッケージを準備 ---
    echo "[1/4] 必要なパッケージ（curl / gnupg）を準備しています..."
    apt-get update
    apt-get install -y curl gnupg

    # --- GoogleのGPGキーを追加 ---
    echo "[2/4] Google の GPG キーを追加しています..."
    curl -fsSL https://dl.google.com/linux/linux_signing_key.pub | gpg --dearmor -o "${GPG_KEY}"

    # --- リポジトリを追加 ---
    echo "[3/4] Google Chrome のリポジトリを追加しています..."
    echo "deb [arch=amd64 signed-by=${GPG_KEY}] https://dl.google.com/linux/chrome/deb/ stable main" > "${REPO_LIST}"

    # --- インストール ---
    echo "[4/4] Google Chrome をインストールしています..."
    apt-get update
    apt-get install -y google-chrome-stable

    # --- デスクトップショートカット作成 ---
    create_shortcut

    echo
    echo "=== インストール完了 ==="
    if command -v google-chrome-stable >/dev/null 2>&1; then
        google-chrome-stable --version
        echo "デスクトップメニュー、デスクトップのショートカット、または 'google-chrome-stable' コマンドで起動できます。"
    else
        echo "警告: インストールが正常に完了していない可能性があります。ログを確認してください。"
        exit 1
    fi
}

# ------------------------------------------------------------
# デスクトップショートカット作成
# ------------------------------------------------------------
create_shortcut() {
    echo "=== デスクトップショートカット作成 ==="
    mkdir -p "$REAL_HOME/Desktop"

    cat > "$REAL_HOME/Desktop/google-chrome.desktop" << 'EOF'
[Desktop Entry]
Type=Application
Name=Google Chrome
Comment=ウェブブラウザ
Exec=/usr/bin/google-chrome-stable %U
Icon=google-chrome
Terminal=false
Categories=Network;WebBrowser;
EOF

    chmod +x "$REAL_HOME/Desktop/google-chrome.desktop"
    echo "デスクトップに google-chrome.desktop を作成しました。"
}

# ------------------------------------------------------------
# アンインストール
# ------------------------------------------------------------
uninstall() {
    echo "=== antiX26 Google Chrome アンインストール開始 ==="
    echo

    # --- デスクトップショートカットの削除 ---
    echo "[1/3] デスクトップショートカットを削除しています..."
    rm -f "$REAL_HOME/Desktop/google-chrome.desktop"

    # --- リポジトリと GPG キーの削除 ---
    echo "[2/3] リポジトリと GPG キーを削除しています..."
    rm -f "${REPO_LIST}"
    rm -f "${GPG_KEY}"
    apt-get update

    # --- Google Chrome の削除 ---
    echo "[3/3] Google Chrome を削除しています..."
    apt-get purge -y google-chrome-stable
    apt-get autoremove -y

    # --- ユーザー設定の削除 ---
    echo "ユーザー設定（$REAL_USER）を削除しています..."
    rm -rf "$REAL_HOME/.config/google-chrome"
    rm -rf "$REAL_HOME/.cache/google-chrome"

    echo
    echo "=== アンインストール完了 ==="
    echo "ブラウザデータ（$REAL_HOME/.config/google-chrome）は削除したため復元できません。"
}

case "$MODE" in
    install)   install ;;
    uninstall) uninstall ;;
esac
