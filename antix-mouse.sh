#!/bin/bash
# ============================================================
#  antix-mouse.sh
#
#  デスクトップアイコンのクリック動作を変更するスクリプト
#   シングルクリック = 選択
#   ダブルクリック   = 実行/起動
#
#  対応環境(存在するものに順に適用):
#    * ZzzFM      (antiX 標準のデスクトップアイコン管理)
#    * ROX-Filer  (antiX の代替アイコン管理 / オプション変更は即時反映)
#    * Nautilus   (GNOME)          gsettings
#    * Caja       (MATE)           gsettings
#    * Nemo       (Cinnamon)       gsettings
#    * Thunar     (XFCE / LXQt)    xfconf-query
#    * Dolphin    (KDE Plasma)     kwriteconfig5/6
#
#  インストール方法（GitHub から）:
#    1) curl -fsSL -o /tmp/antix-mouse.sh \
#       https://raw.githubusercontent.com/hirogura/scripts/main/antix-mouse.sh
#    2) bash /tmp/antix-mouse.sh
#    ワンライナー（パイプ実行）でも可:
#       curl -fsSL https://raw.githubusercontent.com/hirogura/scripts/main/antix-mouse.sh \
#         | bash
#
#    ※ 設定は実行ユーザーのホームディレクトリに書き込むため
#       通常ユーザーで実行してください（sudo は不要）。
#       アンインストール方法は README.md を参照
#
#  使い方:
#    bash antix-mouse.sh                     # 適用（既定）
#    bash antix-mouse.sh -u                  # デフォルト（シングルクリック=実行）に戻す
#    bash antix-mouse.sh -n                  # 変更せずに実行内容のみ表示
#    bash antix-mouse.sh [ユーザー名]        # 指定ユーザーの設定を変更（要 root）
#    bash antix-mouse.sh -h                  # ヘルプ表示
# ============================================================

set -u

SELF=${0##*/}
case "$SELF" in
    bash|sh|dash) SELF=antix-mouse.sh ;;
esac
DRY_RUN=0
TARGET_USER=""
MODE=apply

usage() {
    cat <<EOF
用法: $SELF [オプション] [ユーザー名]

デスクトップアイコンを「シングルクリック=選択 / ダブルクリック=実行」に設定します。
-u を付けるとデフォルト（シングルクリック=実行）に戻します。

オプション:
  -h, --help      このヘルプを表示
  -n, --dry-run   変更せずに実行内容のみ表示
  -u, --uninstall クリック動作をデフォルト（シングルクリック=実行）に戻す

ユーザー名を指定すると、そのユーザーの設定を変更します(要 root)。
未指定の場合は現在のユーザーを対象にします。
EOF
}

parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help) usage; exit 0 ;;
            -n|--dry-run) DRY_RUN=1 ;;
            -u|--uninstall) MODE=uninstall ;;
            -*) echo "$SELF: 不明なオプション: $1" >&2; usage >&2; exit 1 ;;
            *) TARGET_USER="$1" ;;
        esac
        shift
    done
}

resolve_user() {
    if [ -n "$TARGET_USER" ]; then
        if ! id "$TARGET_USER" >/dev/null 2>&1; then
            echo "$SELF: ユーザー '$TARGET_USER' は存在しません" >&2
            exit 1
        fi
        HOME_DIR=$(getent passwd "$TARGET_USER" | cut -d: -f6)
    else
        TARGET_USER=${USER:-$(id -un)}
        HOME_DIR=${HOME:-$(getent passwd "$TARGET_USER" | cut -d: -f6)}
    fi
    echo "$SELF: 対象ユーザー: $TARGET_USER (HOME=$HOME_DIR)"
}

msg() { echo "$SELF: $*"; }
is_root() { [ "$(id -u)" = 0 ]; }

run_as_user() {
    if ! is_root || [ "$TARGET_USER" = "$(id -un)" ]; then
        "$@"
    else
        runuser -u "$TARGET_USER" -- env HOME="$HOME_DIR" "$@"
    fi
}

fix_owner() {
    if is_root; then
        chown "$TARGET_USER" "$@" 2>/dev/null || true
    fi
}

running_pid() {
    pgrep -u "$TARGET_USER" -f "$1" 2>/dev/null | head -n1
}

get_display_of() {
    tr '\0' '\n' < "/proc/$1/environ" 2>/dev/null | sed -n 's/^DISPLAY=//p'
}

# --- ZzzFM ---------------------------------------------------------------
apply_zzzfm() {
    local cfg="$HOME_DIR/.config/zzzfm/session"
    local dir
    dir=$(dirname "$cfg")

    msg "ZzzFM の設定を変更: desk_single_click = 0"
    if [ "$DRY_RUN" -eq 1 ]; then return 0; fi

    mkdir -p "$dir"
    if [ ! -f "$cfg" ]; then
        printf '# zzzFM Session File\n\n[Desktop]\ndesk_single_click=0\n' > "$cfg"
    elif grep -q '^desk_single_click=1$' "$cfg"; then
        sed -i 's/^desk_single_click=1$/desk_single_click=0/' "$cfg"
    elif ! grep -q '^desk_single_click=' "$cfg"; then
        if grep -q '^\[Desktop\]' "$cfg"; then
            sed -i '/^\[Desktop\]/a desk_single_click=0' "$cfg"
        else
            printf '\n[Desktop]\ndesk_single_click=0\n' >> "$cfg"
        fi
    fi
    fix_owner "$cfg"
}

restore_zzzfm() {
    local cfg="$HOME_DIR/.config/zzzfm/session"
    local dir
    dir=$(dirname "$cfg")

    msg "ZzzFM の設定を戻す: desk_single_click = 1"
    if [ "$DRY_RUN" -eq 1 ]; then return 0; fi

    mkdir -p "$dir"
    if [ ! -f "$cfg" ]; then
        printf '# zzzFM Session File\n\n[Desktop]\ndesk_single_click=1\n' > "$cfg"
    elif grep -q '^desk_single_click=0$' "$cfg"; then
        sed -i 's/^desk_single_click=0$/desk_single_click=1/' "$cfg"
    elif ! grep -q '^desk_single_click=' "$cfg"; then
        if grep -q '^\[Desktop\]' "$cfg"; then
            sed -i '/^\[Desktop\]/a desk_single_click=1' "$cfg"
        else
            printf '\n[Desktop]\ndesk_single_click=1\n' >> "$cfg"
        fi
    fi
    fix_owner "$cfg"
}

restart_zzzfm() {
    local pid cmd display
    pid=$(running_pid 'zzzfm --desktop')
    [ -n "$pid" ] || return 0

    msg "zzzfm デスクトップデーモン(PID $pid)を再起動して設定を適用"
    [ "$DRY_RUN" -eq 1 ] && return 0

    display=$(get_display_of "$pid")
    [ -n "$display" ] || display=${DISPLAY:-}
    [ -n "$display" ] || { msg "DISPLAY が不明なため再起動をスキップ(次回ログイン時に反映)"; return 0; }

    kill -9 "$pid" 2>/dev/null
    sleep 1
    if is_root; then
        runuser -u "$TARGET_USER" -- env DISPLAY="$display" HOME="$HOME_DIR" \
            nohup zzzfm --desktop >/dev/null 2>&1 &
    else
        DISPLAY="$display" nohup zzzfm --desktop >/dev/null 2>&1 &
    fi
    sleep 1
    if [ -n "$(running_pid 'zzzfm --desktop')" ]; then
        msg "zzzfm 再起動完了"
    else
        msg "警告: zzzfm の再起動に失敗しました"
    fi
}

# --- ROX-Filer ------------------------------------------------------------
apply_rox() {
    local d="$HOME_DIR/.config/rox.sourceforge.net/ROX-Filer"
    local f
    [ -d "$d" ] || return 0

    msg "ROX-Filer の設定を変更: bind_single_click / bind_single_pinboard = 0"
    [ "$DRY_RUN" -eq 1 ] && return 0

    for f in "$d/Options" "$d/Options.dark" "$d/Options.light"; do
        [ -f "$f" ] || continue
        sed -i \
            -e 's#<Option name="bind_single_click">[^<]*</Option>#<Option name="bind_single_click">0</Option>#' \
            -e 's#<Option name="bind_single_pinboard">[^<]*</Option>#<Option name="bind_single_pinboard">0</Option>#' \
            "$f"
        grep -q 'bind_single_click' "$f" || \
            sed -i '/<Options>/a\  <Option name="bind_single_click">0</Option>' "$f"
        grep -q 'bind_single_pinboard' "$f" || \
            sed -i '/<Options>/a\  <Option name="bind_single_pinboard">0</Option>' "$f"
        fix_owner "$f"
    done
}

restore_rox() {
    local d="$HOME_DIR/.config/rox.sourceforge.net/ROX-Filer"
    local f
    [ -d "$d" ] || return 0

    msg "ROX-Filer の設定を戻す: bind_single_click / bind_single_pinboard = 1"
    [ "$DRY_RUN" -eq 1 ] && return 0

    for f in "$d/Options" "$d/Options.dark" "$d/Options.light"; do
        [ -f "$f" ] || continue
        sed -i \
            -e 's#<Option name="bind_single_click">[^<]*</Option>#<Option name="bind_single_click">1</Option>#' \
            -e 's#<Option name="bind_single_pinboard">[^<]*</Option>#<Option name="bind_single_pinboard">1</Option>#' \
            "$f"
        fix_owner "$f"
    done
}

# --- 汎用デスクトップ環境 --------------------------------------------------
apply_gsettings() {
    local schema="$1" key="$2"
    if run_as_user gsettings list-schemas 2>/dev/null | grep -qx "$schema"; then
        msg "gsettings: $schema $key = double"
        [ "$DRY_RUN" -eq 1 ] || run_as_user gsettings set "$schema" "$key" double
    fi
}

restore_gsettings() {
    local schema="$1" key="$2"
    if run_as_user gsettings list-schemas 2>/dev/null | grep -qx "$schema"; then
        msg "gsettings: $schema $key = single"
        [ "$DRY_RUN" -eq 1 ] || run_as_user gsettings set "$schema" "$key" single
    fi
}

apply_thunar() {
    local has_session
    has_session=${DISPLAY:-}${DBUS_SESSION_BUS_ADDRESS:-}
    if command -v xfconf-query >/dev/null 2>&1 && [ -n "$has_session" ]; then
        if run_as_user xfconf-query -c thunar -p /misc-single-click 2>/dev/null; then
            msg "xfconf: thunar /misc-single-click = false"
            [ "$DRY_RUN" -eq 1 ] || run_as_user xfconf-query -c thunar -p /misc-single-click -s false
        fi
    fi
}

restore_thunar() {
    local has_session
    has_session=${DISPLAY:-}${DBUS_SESSION_BUS_ADDRESS:-}
    if command -v xfconf-query >/dev/null 2>&1 && [ -n "$has_session" ]; then
        if run_as_user xfconf-query -c thunar -p /misc-single-click 2>/dev/null; then
            msg "xfconf: thunar /misc-single-click = true"
            [ "$DRY_RUN" -eq 1 ] || run_as_user xfconf-query -c thunar -p /misc-single-click -s true
        fi
    fi
}

apply_kde() {
    local cmd
    for cmd in kwriteconfig6 kwriteconfig5; do
        if command -v "$cmd" >/dev/null 2>&1; then
            msg "$cmd: kdeglobals General SingleClick = false"
            [ "$DRY_RUN" -eq 1 ] || run_as_user "$cmd" --file kdeglobals --group General --key SingleClick false
            return 0
        fi
    done
}

restore_kde() {
    local cmd
    for cmd in kwriteconfig6 kwriteconfig5; do
        if command -v "$cmd" >/dev/null 2>&1; then
            msg "$cmd: kdeglobals General SingleClick = true"
            [ "$DRY_RUN" -eq 1 ] || run_as_user "$cmd" --file kdeglobals --group General --key SingleClick true
            return 0
        fi
    done
}

apply_generic() {
    apply_gsettings org.gnome.nautilus.preferences click-policy
    apply_gsettings org.mate.caja.preferences click-policy
    apply_gsettings org.nemo.preferences click-policy
    apply_thunar
    apply_kde
}

restore_generic() {
    restore_gsettings org.gnome.nautilus.preferences click-policy
    restore_gsettings org.mate.caja.preferences click-policy
    restore_gsettings org.nemo.preferences click-policy
    restore_thunar
    restore_kde
}

# --- main -----------------------------------------------------------------
main() {
    parse_args "$@"
    resolve_user

    if [ -f "$HOME_DIR/.config/zzzfm/session" ] || [ -n "$(running_pid 'zzzfm --desktop')" ]; then
        if [ "$MODE" = uninstall ]; then
            restore_zzzfm
        else
            apply_zzzfm
        fi
        restart_zzzfm
    else
        msg "ZzzFM の設定は見つかりません(スキップ)"
    fi

    if [ -d "$HOME_DIR/.config/rox.sourceforge.net/ROX-Filer" ] || [ -n "$(running_pid 'rox.*--pinboard')" ]; then
        if [ "$MODE" = uninstall ]; then
            restore_rox
        else
            apply_rox
        fi
    fi

    if [ "$MODE" = uninstall ]; then
        restore_generic
        msg "完了: デフォルト（シングルクリック=実行）に戻しました"
    else
        apply_generic
        msg "完了: シングルクリックで選択 / ダブルクリックで実行"
    fi
}

main "$@"
