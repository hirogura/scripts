#!/bin/bash
# ============================================================
#  デスクトップショートカット作成スクリプト
#  antiX（IceWM / Fluxbox 等）向け
#
#  Google Chrome / LibreOffice（Calc, Writer, Impress）/
#  Thunderbird / VLC のショートカットをデスクトップに作成します。
#
#  インストール方法（GitHub から）:
#    1) curl -fsSL -o /tmp/antix-desktop-shortcut.sh \
#       https://raw.githubusercontent.com/hirogura/scripts/main/antix-desktop-shortcut.sh
#    2) bash /tmp/antix-desktop-shortcut.sh
#    ワンライナー（パイプ実行）でも可:
#       curl -fsSL https://raw.githubusercontent.com/hirogura/scripts/main/antix-desktop-shortcut.sh \
#         | bash
#
#    ※ ショートカットは実行ユーザーのデスクトップ（~/Desktop）に作成するため
#       通常ユーザーで実行してください（sudo は不要）。
#       アンインストール方法は README.md を参照
#
#  使い方:
#    bash antix-desktop-shortcut.sh              # ショートカット作成（既定）
#    bash antix-desktop-shortcut.sh -u           # ショートカット削除
#    bash antix-desktop-shortcut.sh -h           # ヘルプ表示
# ============================================================

set -euo pipefail

usage() {
    echo "使い方:"
    echo "  bash $0              # ショートカット作成（既定）"
    echo "  bash $0 -u           # ショートカット削除"
    echo "  bash $0 -h           # このヘルプを表示"
    echo ""
    echo "作成:"
    echo "  curl -fsSL -o /tmp/antix-desktop-shortcut.sh \\"
    echo "    https://raw.githubusercontent.com/hirogura/scripts/main/antix-desktop-shortcut.sh"
    echo "  bash /tmp/antix-desktop-shortcut.sh"
    echo "削除:"
    echo "  bash /tmp/antix-desktop-shortcut.sh -u"
}

MODE=create
for arg in "$@"; do
    case "$arg" in
        -h|--help)  usage; exit 0 ;;
        -u|--uninstall) MODE=uninstall ;;
        *)          echo "不明なオプション: $arg" >&2; usage; exit 1 ;;
    esac
done

# ------------------------------------------------------------
# ショートカット作成
# ------------------------------------------------------------
create() {
    echo "=== デスクトップショートカット作成開始 ==="
    mkdir -p ~/Desktop

    cat > ~/Desktop/google-chrome.desktop << 'EOF'
[Desktop Entry]
Type=Application
Name=Google Chrome
Comment=ウェブブラウザ
Exec=/usr/bin/google-chrome-stable %U
Icon=google-chrome
Terminal=false
Categories=Network;WebBrowser;
EOF

    cat > ~/Desktop/libreoffice-calc.desktop << 'EOF'
[Desktop Entry]
Type=Application
Name=LibreOffice Calc
Comment=スプレッドシート
Exec=libreoffice --calc %U
Icon=libreoffice-calc
Terminal=false
Categories=Office;Spreadsheet;
EOF

    cat > ~/Desktop/libreoffice-writer.desktop << 'EOF'
[Desktop Entry]
Type=Application
Name=LibreOffice Writer
Comment=文書作成
Exec=libreoffice --writer %U
Icon=libreoffice-writer
Terminal=false
Categories=Office;WordProcessor;
EOF

    cat > ~/Desktop/libreoffice-impress.desktop << 'EOF'
[Desktop Entry]
Type=Application
Name=LibreOffice Impress
Comment=プレゼンテーション
Exec=libreoffice --impress %U
Icon=libreoffice-impress
Terminal=false
Categories=Office;Presentation;
EOF

    cat > ~/Desktop/thunderbird.desktop << 'EOF'
[Desktop Entry]
Type=Application
Name=Thunderbird
Comment=メーラー
Exec=thunderbird %U
Icon=thunderbird
Terminal=false
Categories=Network;Email;
EOF

    cat > ~/Desktop/vlc.desktop << 'EOF'
[Desktop Entry]
Type=Application
Name=VLC media player
Comment=メディアプレイヤー
Exec=vlc %U
Icon=vlc
Terminal=false
Categories=AudioVideo;Player;
EOF

    chmod +x \
        ~/Desktop/google-chrome.desktop \
        ~/Desktop/libreoffice-calc.desktop \
        ~/Desktop/libreoffice-writer.desktop \
        ~/Desktop/libreoffice-impress.desktop \
        ~/Desktop/thunderbird.desktop \
        ~/Desktop/vlc.desktop

    echo "=== 完了 ==="
    echo "デスクトップにショートカットを作成しました:"
    echo "  google-chrome.desktop / libreoffice-calc.desktop / libreoffice-writer.desktop"
    echo "  libreoffice-impress.desktop / thunderbird.desktop / vlc.desktop"
}

# ------------------------------------------------------------
# ショートカット削除
# ------------------------------------------------------------
uninstall() {
    echo "=== デスクトップショートカット削除開始 ==="
    rm -f ~/Desktop/google-chrome.desktop
    rm -f ~/Desktop/libreoffice-calc.desktop
    rm -f ~/Desktop/libreoffice-writer.desktop
    rm -f ~/Desktop/libreoffice-impress.desktop
    rm -f ~/Desktop/thunderbird.desktop
    rm -f ~/Desktop/vlc.desktop
    echo "=== 完了 ==="
    echo "デスクトップショートカットを削除しました。"
}

case "$MODE" in
    create)     create ;;
    uninstall)  uninstall ;;
esac
