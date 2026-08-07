#!/bin/bash
# ============================================================
#  XnView MP インストールスクリプト
#  antiX（runit init）向け
#  ※ XnView MP は Debian 公式リポジトリに存在しないため、
#    xnview.com 公式サイトから deb パッケージを直接ダウンロードして導入します。
#
#  インストール方法（GitHub から）:
#    1) curl -fsSL -o /tmp/antix-install-xnviewmp.sh \
#       https://raw.githubusercontent.com/hirogura/scripts/main/antix-install-xnviewmp.sh
#    2) sudo bash /tmp/antix-install-xnviewmp.sh
#    ワンライナー（パイプ実行）でも可:
#       curl -fsSL https://raw.githubusercontent.com/hirogura/scripts/main/antix-install-xnviewmp.sh \
#         | sudo bash
#  アンインストール方法は README.md を参照
#
#  使い方:
#    sudo bash antix-install-xnviewmp.sh              # インストール（既定）
#    sudo bash antix-install-xnviewmp.sh -u           # アンインストール
#    sudo bash antix-install-xnviewmp.sh -h           # ヘルプ表示
# ============================================================

set -euo pipefail

usage() {
    echo "使い方:"
    echo "  sudo bash $0              # インストール（既定）"
    echo "  sudo bash $0 -u           # アンインストール"
    echo "  sudo bash $0 -h           # このヘルプを表示"
    echo ""
    echo "インストール:"
    echo "  curl -fsSL -o /tmp/antix-install-xnviewmp.sh \\"
    echo "    https://raw.githubusercontent.com/hirogura/scripts/main/antix-install-xnviewmp.sh"
    echo "  sudo bash /tmp/antix-install-xnviewmp.sh"
    echo "アンインストール:"
    echo "  sudo bash /tmp/antix-install-xnviewmp.sh -u"
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

DEB_URL="http://download.xnview.com/XnViewMP-linux-x64.deb"
TMP_DEB="/tmp/XnViewMP-linux-x64.deb"

# ------------------------------------------------------------
# インストール
# ------------------------------------------------------------
install() {
    echo "=== antiX26 XnView MP インストール開始 ==="
    echo

    # --- 既にインストール済みか確認 ---
    if command -v xnview >/dev/null 2>&1; then
        echo "XnView MP は既にインストールされています。"
        echo "デスクトップメニューまたは 'xnview' コマンドで起動できます。"
        exit 0
    fi

    # --- debパッケージのダウンロード ---
    echo "[1/2] XnView MP の deb パッケージをダウンロードしています..."
    echo "取得元: ${DEB_URL}"
    wget -O "${TMP_DEB}" "${DEB_URL}"

    # --- インストール（依存関係も自動解決） ---
    echo "[2/2] XnView MP をインストールしています..."
    apt-get update
    apt-get install -y "${TMP_DEB}"

    # --- 後片付け ---
    rm -f "${TMP_DEB}"

    # --- デスクトップショートカット作成 ---
    create_shortcut

    echo
    echo "=== インストール完了 ==="
    if command -v xnview >/dev/null 2>&1; then
        echo "デスクトップメニュー、デスクトップのショートカット、または 'xnview' コマンドで起動できます。"
    else
        echo "警告: インストールが正常に完了していない可能性があります。"
        echo "依存関係エラーが出た場合は、以下を試してください:"
        echo "  sudo apt --fix-broken install"
        exit 1
    fi
}

# ------------------------------------------------------------
# デスクトップショートカット作成
# ------------------------------------------------------------
create_shortcut() {
    echo "=== デスクトップショートカット作成 ==="
    mkdir -p "$REAL_HOME/Desktop"

    cat > "$REAL_HOME/Desktop/xnviewmp.desktop" << 'EOF'
[Desktop Entry]
Type=Application
Name=XnView MP
Comment=画像ビューア
Exec=xnview %U
Icon=/opt/XnView/xnview.png
Terminal=false
Categories=Graphics;
EOF

    chmod +x "$REAL_HOME/Desktop/xnviewmp.desktop"
    echo "デスクトップに xnviewmp.desktop を作成しました。"
}

# ------------------------------------------------------------
# アンインストール
# ------------------------------------------------------------
uninstall() {
    echo "=== antiX26 XnView MP アンインストール開始 ==="
    echo

    # --- インストール済みか確認 ---
    if ! dpkg -l xnview >/dev/null 2>&1; then
        echo "XnView MP はインストールされていません。"
        exit 0
    fi

    # --- デスクトップショートカットの削除 ---
    echo "[1/3] デスクトップショートカットを削除しています..."
    rm -f "$REAL_HOME/Desktop/xnviewmp.desktop"

    # --- XnView MP の削除 ---
    echo "[2/3] XnView MP を削除しています..."
    dpkg -r xnview
    apt-get autoremove -y

    # --- ユーザー設定の削除 ---
    echo "[3/3] ユーザー設定（$REAL_USER）を削除しています..."
    rm -rf "$REAL_HOME/.config/xnviewmp"
    rm -rf "$REAL_HOME/.cache/xnviewmp"

    echo
    echo "=== アンインストール完了 ==="
    echo "設定（$REAL_HOME/.config/xnviewmp）は削除したため復元できません。"
}

case "$MODE" in
    install)   install ;;
    uninstall) uninstall ;;
esac
