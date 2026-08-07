#!/bin/bash
# ============================================================
#  Thunderbird インストールスクリプト
#  antiX（runit init）向け
#
#  インストール方法（GitHub から）:
#    1) curl -fsSL -o /tmp/antix-install-thunderbird.sh \
#       https://raw.githubusercontent.com/hirogura/scripts/main/antix-install-thunderbird.sh
#    2) sudo bash /tmp/antix-install-thunderbird.sh
#    ワンライナー（パイプ実行）でも可:
#       curl -fsSL https://raw.githubusercontent.com/hirogura/scripts/main/antix-install-thunderbird.sh \
#         | sudo bash
#  アンインストール方法は README.md を参照
#
#  使い方:
#    sudo bash antix-install-thunderbird.sh              # インストール（既定）
#    sudo bash antix-install-thunderbird.sh -u           # アンインストール
#    sudo bash antix-install-thunderbird.sh -h           # ヘルプ表示
# ============================================================

set -euo pipefail

usage() {
    echo "使い方:"
    echo "  sudo bash $0              # インストール（既定）"
    echo "  sudo bash $0 -u           # アンインストール"
    echo "  sudo bash $0 -h           # このヘルプを表示"
    echo ""
    echo "インストール:"
    echo "  curl -fsSL -o /tmp/antix-install-thunderbird.sh \\"
    echo "    https://raw.githubusercontent.com/hirogura/scripts/main/antix-install-thunderbird.sh"
    echo "  sudo bash /tmp/antix-install-thunderbird.sh"
    echo "アンインストール:"
    echo "  sudo bash /tmp/antix-install-thunderbird.sh -u"
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

# ------------------------------------------------------------
# インストール
# ------------------------------------------------------------
install() {
    echo "=== antiX26 Thunderbird インストール開始 ==="
    echo

    # --- 既にインストール済みか確認 ---
    if command -v thunderbird >/dev/null 2>&1; then
        echo "Thunderbird は既にインストールされています。"
        thunderbird --version
        exit 0
    fi

    # --- パッケージリストの更新 ---
    echo "[1/3] パッケージリストを更新しています..."
    apt-get update

    # --- Thunderbird のインストール ---
    echo "[2/3] Thunderbird をインストールしています..."
    apt-get install -y thunderbird

    # --- 日本語言語パック（任意・存在すれば導入） ---
    echo "[3/3] 日本語言語パックを確認しています..."
    if apt-cache show thunderbird-l10n-ja >/dev/null 2>&1; then
        apt-get install -y thunderbird-l10n-ja
        echo "日本語言語パックをインストールしました。"
    else
        echo "日本語言語パック（thunderbird-l10n-ja）はリポジトリに見つかりませんでした。スキップします。"
    fi

    # --- デスクトップショートカット作成 ---
    create_shortcut

    echo
    echo "=== インストール完了 ==="
    if command -v thunderbird >/dev/null 2>&1; then
        thunderbird --version
        echo "デスクトップメニュー、デスクトップのショートカット、または 'thunderbird' コマンドで起動できます。"
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

    cat > "$REAL_HOME/Desktop/thunderbird.desktop" << 'EOF'
[Desktop Entry]
Type=Application
Name=Thunderbird
Comment=メーラー
Exec=thunderbird %U
Icon=thunderbird
Terminal=false
Categories=Network;Email;
EOF

    chmod +x "$REAL_HOME/Desktop/thunderbird.desktop"
    echo "デスクトップに thunderbird.desktop を作成しました。"
}

# ------------------------------------------------------------
# アンインストール
# ------------------------------------------------------------
uninstall() {
    echo "=== antiX26 Thunderbird アンインストール開始 ==="
    echo

    # --- インストール済みか確認 ---
    if ! command -v thunderbird >/dev/null 2>&1; then
        echo "Thunderbird はインストールされていません。"
        exit 0
    fi

    # --- デスクトップショートカットの削除 ---
    echo "[1/3] デスクトップショートカットを削除しています..."
    rm -f "$REAL_HOME/Desktop/thunderbird.desktop"

    # --- Thunderbird の削除 ---
    echo "[2/3] Thunderbird を削除しています..."
    apt-get purge -y thunderbird thunderbird-l10n-ja
    apt-get autoremove -y

    # --- ユーザー設定の削除 ---
    echo "[3/3] ユーザー設定（$REAL_USER）を削除しています..."
    rm -rf "$REAL_HOME/.thunderbird"
    rm -rf "$REAL_HOME/.config/thunderbird"
    rm -rf "$REAL_HOME/.cache/thunderbird"

    echo
    echo "=== アンインストール完了 ==="
    echo "メールデータ（$REAL_HOME/.thunderbird）は削除したため復元できません。"
}

case "$MODE" in
    install)   install ;;
    uninstall) uninstall ;;
esac
