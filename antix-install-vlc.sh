#!/bin/bash
# ============================================================
#  VLC インストールスクリプト
#  antiX（runit init）向け
#
#  インストール方法（GitHub から）:
#    1) curl -fsSL -o /tmp/antix-install-vlc.sh \
#       https://raw.githubusercontent.com/hirogura/scripts/main/antix-install-vlc.sh
#    2) sudo bash /tmp/antix-install-vlc.sh
#    ワンライナー（パイプ実行）でも可:
#       curl -fsSL https://raw.githubusercontent.com/hirogura/scripts/main/antix-install-vlc.sh \
#         | sudo bash
#  アンインストール方法は README.md を参照
#
#  使い方:
#    sudo bash antix-install-vlc.sh              # インストール（既定）
#    sudo bash antix-install-vlc.sh -u           # アンインストール
#    sudo bash antix-install-vlc.sh -h           # ヘルプ表示
# ============================================================

set -euo pipefail

usage() {
    echo "使い方:"
    echo "  sudo bash $0              # インストール（既定）"
    echo "  sudo bash $0 -u           # アンインストール"
    echo "  sudo bash $0 -h           # このヘルプを表示"
    echo ""
    echo "インストール:"
    echo "  curl -fsSL -o /tmp/antix-install-vlc.sh \\"
    echo "    https://raw.githubusercontent.com/hirogura/scripts/main/antix-install-vlc.sh"
    echo "  sudo bash /tmp/antix-install-vlc.sh"
    echo "アンインストール:"
    echo "  sudo bash /tmp/antix-install-vlc.sh -u"
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
    echo "=== antiX26 VLC インストール開始 ==="
    echo

    # --- 既にインストール済みか確認 ---
    if command -v vlc >/dev/null 2>&1; then
        echo "VLC は既にインストールされています。"
        vlc --version | head -n 1
        exit 0
    fi

    # --- パッケージリストの更新 ---
    echo "[1/3] パッケージリストを更新しています..."
    apt-get update

    # --- VLC のインストール ---
    echo "[2/3] VLC をインストールしています..."
    apt-get install -y vlc

    # --- 日本語言語パック（任意・存在すれば導入） ---
    echo "[3/3] 日本語言語パックを確認しています..."
    if apt-cache show vlc-l10n >/dev/null 2>&1; then
        apt-get install -y vlc-l10n
        echo "言語パック（vlc-l10n）をインストールしました。"
    else
        echo "言語パック（vlc-l10n）はリポジトリに見つかりませんでした。スキップします。"
    fi

    echo
    echo "=== インストール完了 ==="
    if command -v vlc >/dev/null 2>&1; then
        vlc --version | head -n 1
        echo "デスクトップメニューまたは 'vlc' コマンドで起動できます。"
    else
        echo "警告: インストールが正常に完了していない可能性があります。ログを確認してください。"
        exit 1
    fi
}

# ------------------------------------------------------------
# アンインストール
# ------------------------------------------------------------
uninstall() {
    echo "=== antiX26 VLC アンインストール開始 ==="
    echo

    # --- インストール済みか確認 ---
    if ! command -v vlc >/dev/null 2>&1; then
        echo "VLC はインストールされていません。"
        exit 0
    fi

    # --- VLC の削除 ---
    echo "[1/2] VLC を削除しています..."
    apt-get purge -y vlc vlc-l10n
    apt-get autoremove -y

    # --- ユーザー設定の削除 ---
    echo "[2/2] ユーザー設定（$REAL_USER）を削除しています..."
    rm -rf "$REAL_HOME/.config/vlc"
    rm -rf "$REAL_HOME/.cache/vlc"

    echo
    echo "=== アンインストール完了 ==="
    echo "設定（$REAL_HOME/.config/vlc）は削除したため復元できません。"
}

case "$MODE" in
    install)   install ;;
    uninstall) uninstall ;;
esac
