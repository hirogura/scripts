#!/bin/bash
# ============================================================
#  Visual Studio Code インストールスクリプト
#  antiX（runit init）向け
#
#  インストール方法（GitHub から）:
#    1) curl -fsSL -o /tmp/antix-install-vscode.sh \
#       https://raw.githubusercontent.com/hirogura/scripts/main/antix-install-vscode.sh
#    2) sudo bash /tmp/antix-install-vscode.sh
#    ワンライナー（パイプ実行）でも可:
#       curl -fsSL https://raw.githubusercontent.com/hirogura/scripts/main/antix-install-vscode.sh \
#         | sudo bash
#  アンインストール方法は README.md を参照
#
#  使い方:
#    sudo bash antix-install-vscode.sh              # インストール（既定）
#    sudo bash antix-install-vscode.sh -u           # アンインストール
#    sudo bash antix-install-vscode.sh -h           # ヘルプ表示
# ============================================================

set -euo pipefail

usage() {
    echo "使い方:"
    echo "  sudo bash $0              # インストール（既定）"
    echo "  sudo bash $0 -u           # アンインストール"
    echo "  sudo bash $0 -h           # このヘルプを表示"
    echo ""
    echo "インストール:"
    echo "  curl -fsSL -o /tmp/antix-install-vscode.sh \\"
    echo "    https://raw.githubusercontent.com/hirogura/scripts/main/antix-install-vscode.sh"
    echo "  sudo bash /tmp/antix-install-vscode.sh"
    echo "アンインストール:"
    echo "  sudo bash /tmp/antix-install-vscode.sh -u"
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

GPG_KEY="/usr/share/keyrings/microsoft.gpg"
REPO_LIST="/etc/apt/sources.list.d/vscode.list"

# ------------------------------------------------------------
# インストール
# ------------------------------------------------------------
install() {
    echo "=== antiX26 Visual Studio Code インストール開始 ==="
    echo

    # --- 既にインストール済みか確認 ---
    if command -v code >/dev/null 2>&1; then
        echo "Visual Studio Code は既にインストールされています。"
        code --version | head -n 1
        exit 0
    fi

    # --- 必要なパッケージを準備 ---
    echo "[1/4] 必要なパッケージ（wget / gpg / apt-transport-https）を準備しています..."
    apt-get update
    apt-get install -y wget gpg apt-transport-https

    # --- MicrosoftのGPGキーを登録 ---
    echo "[2/4] Microsoft の GPG キーを登録しています..."
    wget -qO- https://packages.microsoft.com/keys/microsoft.asc \
        | gpg --dearmor -o "${GPG_KEY}"

    # --- リポジトリを追加 ---
    echo "[3/4] VS Code のリポジトリを追加しています..."
    echo "deb [arch=amd64 signed-by=${GPG_KEY}] https://packages.microsoft.com/repos/code stable main" > "${REPO_LIST}"

    # --- インストール ---
    echo "[4/4] Visual Studio Code をインストールしています..."
    apt-get update
    apt-get install -y code

    # --- 日本語言語パック（実行ユーザー向け） ---
    echo "日本語言語パックをインストールしています..."
    sudo -u "$REAL_USER" code --install-extension MS-CEINTL.vscode-language-pack-ja || true

    # --- 表示言語を日本語に固定（~/.vscode/argv.json） ---
    echo "表示言語を日本語に設定しています..."
    mkdir -p "$REAL_HOME/.vscode"
    cat > "$REAL_HOME/.vscode/argv.json" <<'EOF'
{
  "locale": "ja"
}
EOF
    chown -R "$REAL_USER:$REAL_USER" "$REAL_HOME/.vscode"

    # --- デスクトップショートカット作成 ---
    create_shortcut

    echo
    echo "=== インストール完了 ==="
    if command -v code >/dev/null 2>&1; then
        code --version | head -n 1
        echo "デスクトップメニュー、デスクトップのショートカット、または 'code' コマンドで起動できます。"
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

    cat > "$REAL_HOME/Desktop/code.desktop" << 'EOF'
[Desktop Entry]
Type=Application
Name=VSCode
Comment=エディター
Exec=/usr/share/code/code %F
Icon=/usr/share/pixmaps/vscode.png
Terminal=false
Categories=Development;IDE;
EOF

    chmod +x "$REAL_HOME/Desktop/code.desktop"
    echo "デスクトップに code.desktop を作成しました。"
}

# ------------------------------------------------------------
# アンインストール
# ------------------------------------------------------------
uninstall() {
    echo "=== antiX26 Visual Studio Code アンインストール開始 ==="
    echo

    # --- デスクトップショートカットの削除 ---
    echo "[1/4] デスクトップショートカットを削除しています..."
    rm -f "$REAL_HOME/Desktop/code.desktop"

    # --- リポジトリと GPG キーの削除 ---
    echo "[2/4] リポジトリと GPG キーを削除しています..."
    rm -f "${REPO_LIST}"
    rm -f "${GPG_KEY}"
    apt-get update

    # --- Visual Studio Code の削除 ---
    echo "[3/4] Visual Studio Code を削除しています..."
    apt-get purge -y code
    apt-get autoremove -y

    # --- ユーザー設定の削除 ---
    echo "[4/4] ユーザー設定（$REAL_USER）を削除しています..."
    rm -rf "$REAL_HOME/.vscode"
    rm -rf "$REAL_HOME/.config/Code"

    echo
    echo "=== アンインストール完了 ==="
    echo "設定・拡張機能（$REAL_HOME/.vscode）は削除したため復元できません。"
}

case "$MODE" in
    install)   install ;;
    uninstall) uninstall ;;
esac
