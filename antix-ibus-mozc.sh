#!/bin/bash
set -euo pipefail

# ============================================================
#  日本語入力（ibus + Mozc）セットアップスクリプト
#  antiX（IceWM / Fluxbox 等の desktop-session）向け
#
#  何度実行しても安全。初回はパッケージインストール＋設定ファイル生成のみ行われ、
#  再ログイン後にもう一度実行するとエンジン設定（gsettings）が反映されます。
#
#  インストール方法（GitHub から）:
#    1) curl -fsSL -o /tmp/antix-ibus-mozc.sh \
#       https://raw.githubusercontent.com/hirogura/scripts/main/antix-ibus-mozc.sh
#    2) bash /tmp/antix-ibus-mozc.sh
#    ワンライナー（パイプ実行）でも可:
#       curl -fsSL https://raw.githubusercontent.com/hirogura/scripts/main/antix-ibus-mozc.sh \
#         | bash
#
#    ※ デスクトップセッション（~/.desktop-session）を設定するため
#       通常ユーザーで実行してください（内部で必要な sudo は自動実行されます）。
#       アンインストール方法は README.md を参照
#
#  使い方:
#    bash antix-ibus-mozc.sh              # インストール（既定）
#    bash antix-ibus-mozc.sh -u           # アンインストール
#    bash antix-ibus-mozc.sh --uninstall  # アンインストール
#    bash antix-ibus-mozc.sh -h           # ヘルプ表示
# ============================================================

usage() {
    echo "使い方:"
    echo "  bash $0            # インストール（既定）"
    echo "  bash $0 -u         # アンインストール"
    echo "  bash $0 -h         # このヘルプを表示"
    echo ""
    echo "インストール: curl -fsSL -o /tmp/antix-ibus-mozc.sh \\"
    echo "  https://raw.githubusercontent.com/hirogura/scripts/main/antix-ibus-mozc.sh"
    echo "  bash /tmp/antix-ibus-mozc.sh"
    echo "アンインストール: bash /tmp/antix-ibus-mozc.sh -u"
}

MODE=install
for arg in "$@"; do
    case "$arg" in
        -h|--help)     usage; exit 0 ;;
        -u|--uninstall) MODE=uninstall ;;
        *)             echo "不明なオプション: $arg" >&2; usage; exit 1 ;;
    esac
done

# ------------------------------------------------------------
# インストール
# ------------------------------------------------------------
install() {
    echo "===== 日本語入力（ibus + Mozc）セットアップ開始 ====="

    # 1. パッケージインストール
    sudo apt update
    sudo apt install -y ibus ibus-mozc ibus-gtk ibus-gtk3 ibus-gtk4 fonts-noto-cjk

    # 2. ~/.desktop-session/desktop-session.conf に追記
    mkdir -p ~/.desktop-session
    CONF_FILE=~/.desktop-session/desktop-session.conf
    touch "$CONF_FILE"

    CONF_BLOCK='im_module="ibus"
export GTK_IM_MODULE=$im_module
export QT_IM_MODULE=$im_module
export XMODIFIERS=@im=$im_module
DBUS_SESSION_LAUNCH="false"
eval $(dbus-launch --autolaunch $(cat /var/lib/dbus/machine-id) --sh-syntax --exit-with-session)'

    if ! grep -qxF 'im_module="ibus"' "$CONF_FILE"; then
        echo "$CONF_BLOCK" >> "$CONF_FILE"
        echo "[RUN]  desktop-session.conf に追記しました"
    else
        echo "[SKIP] desktop-session.conf は既に設定済みです"
    fi

    # 3. ~/.desktop-session/startup に追記
    STARTUP_FILE=~/.desktop-session/startup
    touch "$STARTUP_FILE"

    if ! grep -qxF 'ibus-daemon -drx' "$STARTUP_FILE"; then
        echo 'ibus-daemon -drx' >> "$STARTUP_FILE"
        echo "[RUN]  startup に追記しました"
    else
        echo "[SKIP] startup は既に設定済みです"
    fi

    # 4. Mozc起動時のデフォルト入力モードを「ひらがな」に設定
    MOZC_CONF_DIR=~/.config/mozc
    MOZC_CONF_FILE="$MOZC_CONF_DIR/ibus_config.textproto"

    mkdir -p "$MOZC_CONF_DIR"

    if [ -f "$MOZC_CONF_FILE" ] && grep -q "active_on_launch: True" "$MOZC_CONF_FILE"; then
        echo "[SKIP] Mozcのひらがなデフォルト設定は既に反映済みです"
    else
        cat > "$MOZC_CONF_FILE" << 'EOF'
engines {
  name : "mozc-jp"
  longname : "Mozc"
  layout : "default"
  layout_variant : ""
  layout_option : ""
  rank : 80
}
active_on_launch: True
EOF
        echo "[RUN]  Mozcのひらがなデフォルト設定を書き込みました"
    fi

    if [ -f ~/.mozc/ibus_config.textproto ]; then
        echo "[警告] ~/.mozc/ibus_config.textproto が存在します。こちらが優先されるため、内容を確認してください"
    fi

    # 5. 入力エンジンを Mozc / 英語(US) の2つのみに設定（要dbusセッション）
    if gsettings set org.freedesktop.ibus.general preload-engines "['mozc-jp', 'xkb:us::eng']" 2>/dev/null; then
        gsettings set org.freedesktop.ibus.general engines-order "['mozc-jp', 'xkb:us::eng']"
        echo "[RUN]  入力エンジンを Mozc / 英語(US) の2つに設定しました"

        # 6. 切り替えキーに「半角/全角」を追加（Control+spaceは維持）
        CURRENT_TRIGGERS=$(gsettings get org.freedesktop.ibus.general.hotkey trigger)
        if echo "$CURRENT_TRIGGERS" | grep -q "Zenkaku_Hankaku"; then
            echo "[SKIP] 半角/全角キーは既に設定済みです"
        else
            gsettings set org.freedesktop.ibus.general.hotkey trigger "['Control+space', 'Zenkaku_Hankaku']"
            echo "[RUN]  切り替えキーに半角/全角を追加しました"
        fi

        ibus write-cache || echo "[警告] ibus write-cache に失敗しました（無視して続行）"
        ibus restart || echo "[警告] ibus restart に失敗しました（無視して続行）"
    else
        echo ""
        echo "[SKIP] gsettings によるエンジン/キー設定は今回スキップされました"
        echo "       （ibusのdbusセッションがまだ起動していないためと思われます）"
        echo "       再ログイン後、このスクリプトをもう一度実行してください"
    fi

    echo ""
    echo "=================================================="
    echo " セットアップ完了"
    echo " ・パッケージ / desktop-session設定 / Mozcひらがなデフォルト: 反映済み"
    echo " ・入力エンジン(2つ限定)とキー設定: dbusセッションが有効な場合のみ反映済み"
    echo " 反映を確実にするため、一度ログアウト→再ログイン（またはXの再起動）してください"
    echo "=================================================="
}

# ------------------------------------------------------------
# アンインストール
# ------------------------------------------------------------
uninstall() {
    echo "===== 日本語入力（ibus + Mozc）アンインストール開始 ====="

    # 1. gsettings 設定のリセット
    if gsettings set org.freedesktop.ibus.general preload-engines "['xkb:us::eng']" 2>/dev/null; then
        gsettings reset org.freedesktop.ibus.general preload-engines
        gsettings reset org.freedesktop.ibus.general engines-order
        gsettings reset org.freedesktop.ibus.general.hotkey trigger
        echo "[RUN]  gsettings の入力エンジン/キー設定をリセットしました"
        ibus write-cache || echo "[警告] ibus write-cache に失敗しました（無視して続行）"
        ibus restart || echo "[警告] ibus restart に失敗しました（無視して続行）"
    else
        echo "[SKIP] gsettings リセットをスキップしました（dbusセッションが無効）"
    fi

    # 2. desktop-session.conf から追記分を削除
    CONF_FILE=~/.desktop-session/desktop-session.conf
    if [ -f "$CONF_FILE" ] && grep -q 'im_module="ibus"' "$CONF_FILE"; then
        sed -i \
            -e '\#^im_module="ibus"$#d' \
            -e '\#^export GTK_IM_MODULE=\$im_module$#d' \
            -e '\#^export QT_IM_MODULE=\$im_module$#d' \
            -e '\#^export XMODIFIERS=@im=\$im_module$#d' \
            -e '\#^DBUS_SESSION_LAUNCH="false"$#d' \
            -e '\#^eval \$(dbus-launch --autolaunch \$(cat /var/lib/dbus/machine-id) --sh-syntax --exit-with-session)$#d' \
            "$CONF_FILE"
        echo "[RUN]  desktop-session.conf から追記分を削除しました"
    else
        echo "[SKIP] desktop-session.conf に追記分はありません"
    fi

    # 3. startup から ibus-daemon 行を削除
    STARTUP_FILE=~/.desktop-session/startup
    if [ -f "$STARTUP_FILE" ] && grep -qxF 'ibus-daemon -drx' "$STARTUP_FILE"; then
        sed -i '\#^ibus-daemon -drx$#d' "$STARTUP_FILE"
        echo "[RUN]  startup から ibus-daemon 行を削除しました"
    else
        echo "[SKIP] startup に ibus-daemon 行はありません"
    fi

    # 4. Mozc のユーザー設定を削除
    if [ -d ~/.config/mozc ]; then
        rm -rf ~/.config/mozc
        echo "[RUN]  ~/.config/mozc を削除しました"
    else
        echo "[SKIP] ~/.config/mozc は存在しません"
    fi

    # 5. パッケージの削除
    echo "[RUN]  ibus-mozc / fonts-noto-cjk を削除します"
    sudo apt remove --purge -y ibus-mozc fonts-noto-cjk
    echo "      （ibus 本体は他のアプリでも使う可能性があるため削除しません）"
    echo "       削除したい場合は手動で: sudo apt remove --purge -y ibus ibus-gtk ibus-gtk3 ibus-gtk4"

    echo ""
    echo "=================================================="
    echo " アンインストール完了"
    echo " 反映を確実にするため、一度ログアウト→再ログイン（またはXの再起動）してください"
    echo "=================================================="
}

case "$MODE" in
    install)   install ;;
    uninstall) uninstall ;;
esac
