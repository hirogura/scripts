#!/bin/bash
# ============================================================
#  Krita インストールスクリプト
#  antiX（runit init）向け
#
#  インストール方法（GitHub から）:
#    1) curl -fsSL -o /tmp/antix-install-krita.sh \
#       https://raw.githubusercontent.com/hirogura/scripts/main/antix-install-krita.sh
#    2) sudo bash /tmp/antix-install-krita.sh
#    ワンライナー（パイプ実行）でも可:
#       curl -fsSL https://raw.githubusercontent.com/hirogura/scripts/main/antix-install-krita.sh \
#         | sudo bash
#  アンインストール方法は README.md を参照
#
#  使い方:
#    sudo bash antix-install-krita.sh              # インストール（既定）
#    sudo bash antix-install-krita.sh -u           # アンインストール
#    sudo bash antix-install-krita.sh -h           # ヘルプ表示
# ============================================================

set -euo pipefail

usage() {
    echo "使い方:"
    echo "  sudo bash $0              # インストール（既定）"
    echo "  sudo bash $0 -u           # アンインストール"
    echo "  sudo bash $0 -h           # このヘルプを表示"
    echo ""
    echo "インストール:"
    echo "  curl -fsSL -o /tmp/antix-install-krita.sh \\"
    echo "    https://raw.githubusercontent.com/hirogura/scripts/main/antix-install-krita.sh"
    echo "  sudo bash /tmp/antix-install-krita.sh"
    echo "アンインストール:"
    echo "  sudo bash /tmp/antix-install-krita.sh -u"
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
    echo "=== antiX26 Krita インストール開始 ==="
    echo

    # --- 既にインストール済みか確認 ---
    if command -v krita >/dev/null 2>&1; then
        echo "Krita は既にインストールされています。"
        krita --version | head -n 1
        exit 0
    fi

    # --- パッケージリストの更新 ---
    echo "[1/3] パッケージリストを更新しています..."
    apt-get update

    # --- Krita のインストール ---
    echo "[2/3] Krita をインストールしています..."
    apt-get install -y krita

    # --- デスクトップショートカット作成 ---
    echo "[3/3] デスクトップショートカットを作成しています..."
    create_shortcut

    echo
    echo "=== インストール完了 ==="
    if command -v krita >/dev/null 2>&1; then
        krita --version | head -n 1
        echo "デスクトップメニュー、デスクトップのショートカット、または 'krita' コマンドで起動できます。"
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

    cat > "$REAL_HOME/Desktop/krita.desktop" << 'EOF'
[Desktop Entry]
Type=Application
Name=Krita
Comment=ペイントアプリ
Exec=krita %U
Icon=krita
Terminal=false
Categories=Graphics;2DGraphics;RasterGraphics;Viewer;
EOF

    chmod +x "$REAL_HOME/Desktop/krita.desktop"
    echo "デスクトップに krita.desktop を作成しました。"
}

# ------------------------------------------------------------
# アンインストール
# ------------------------------------------------------------
uninstall() {
    echo "=== antiX26 Krita アンインストール開始 ==="
    echo

    # --- インストール済みか確認 ---
    if ! command -v krita >/dev/null 2>&1; then
        echo "Krita はインストールされていません。"
        exit 0
    fi

    # --- デスクトップショートカットの削除 ---
    echo "[1/3] デスクトップショートカットを削除しています..."
    rm -f "$REAL_HOME/Desktop/krita.desktop"

    # --- Krita の削除 ---
    echo "[2/3] Krita を削除しています..."
    apt-get purge -y krita
    apt-get autoremove -y

    # --- ユーザー設定の削除 ---
    echo "[3/3] ユーザー設定（$REAL_USER）を削除しています..."
    rm -rf "$REAL_HOME/.config/krita"
    rm -rf "$REAL_HOME/.local/share/krita"
    rm -rf "$REAL_HOME/.cache/krita"

    echo
    echo "=== アンインストール完了 ==="
    echo "設定（$REAL_HOME/.config/krita 等）は削除したため復元できません。"
}

case "$MODE" in
    install)   install ;;
    uninstall) uninstall ;;
esac
