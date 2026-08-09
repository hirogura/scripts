#!/bin/bash
# ============================================================
#  code-server-opencode-scroll.sh
#
#  code-server（ブラウザ上の VS Code = xterm.js ターミナル）で
#  opencode TUI をマウスモード無効にして、キーボードだけで
#  スクロールできるようにするセットアップスクリプト。
#
#  やること（マウスモード無効化コマンドを含む）:
#    1. ~/.opencode/ を作成（なければ）
#    2. マウスモードを無効化（~/.opencode/tui.json の "mouse": false）
#    3. 既存の tui.json を tui.json.bak.<タイムスタンプ> にバックアップ
#    4. スクロール用のキーバインド（scrollbar_toggle 等）を書き込み
#    5. JSON を検証し、使い方を表示
#
#  インストール方法（GitHub から）:
#    1) curl -fsSL -o /tmp/code-server-opencode-scroll.sh \
#       https://raw.githubusercontent.com/hirogura/scripts/main/code-server-opencode-scroll.sh
#    2) bash /tmp/code-server-opencode-scroll.sh
#    ワンライナー（パイプ実行）でも可:
#       curl -fsSL https://raw.githubusercontent.com/hirogura/scripts/main/code-server-opencode-scroll.sh \
#         | bash
#
#    ※ 設定は実行ユーザーのホームディレクトリ（~/.opencode）に書き込むため
#       通常ユーザーで実行してください（sudo は不要）。
#       アンインストール方法は README.md を参照
#
#  使い方:
#    bash code-server-opencode-scroll.sh                        # セットアップ（既定）
#    bash code-server-opencode-scroll.sh /path/to/opencode-home  # 別の場所に設定
#    bash code-server-opencode-scroll.sh -u                     # アンインストール（設定戻し）
#    bash code-server-opencode-scroll.sh -n                     # 変更せずに実行内容のみ表示
#    bash code-server-opencode-scroll.sh -h                     # ヘルプ表示
# ============================================================

set -u

SELF=${0##*/}
case "$SELF" in
    bash|sh|dash) SELF=code-server-opencode-scroll.sh ;;
esac

DRY_RUN=0
MODE=setup
OPCODE_DIR=""

usage() {
    cat <<EOF
用法: $SELF [オプション] [opencode の設定ディレクトリ]

code-server（ブラウザ上の VS Code）で opencode のマウスモードを無効にし、
キーボードだけでスクロールできるように設定します。
設定先は ~/.opencode（既定）です。

オプション:
  -h, --help      このヘルプを表示
  -n, --dry-run   変更せずに実行内容のみ表示
  -u, --uninstall tui.json を削除し、バックアップがあれば復元する

設定ディレクトリを指定すると、その場所に tui.json を作成します。
未指定の場合は $HOME/.opencode を使用します。
EOF
}

parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help) usage; exit 0 ;;
            -n|--dry-run) DRY_RUN=1 ;;
            -u|--uninstall) MODE=uninstall ;;
            -*) echo "$SELF: 不明なオプション: $1" >&2; usage >&2; exit 1 ;;
            *) OPCODE_DIR="$1" ;;
        esac
        shift
    done
    if [ -z "$OPCODE_DIR" ]; then
        OPCODE_DIR="${HOME}/.opencode"
    fi
}

msg() { echo "$SELF: $*"; }

TUI_JSON='{
  "$schema": "https://opencode.ai/tui.json",
  "mouse": false,
  "keybinds": {
    "scrollbar_toggle": "ctrl+alt+s"
  }
}'

setup() {
    local tui_file="$OPCODE_DIR/tui.json"
    local backup=""
    local ts

    msg "opencode TUI スクロール設定（code-server 向け）を開始"
    msg "  マウスモード無効化 + スクロールキー設定: $tui_file"

    msg "設定ディレクトリを作成: $OPCODE_DIR"
    if [ "$DRY_RUN" -eq 0 ]; then
        mkdir -p "$OPCODE_DIR"
    fi

    if [ -f "$tui_file" ]; then
        ts=$(date +%Y%m%d-%H%M%S)
        backup="$tui_file.bak.$ts"
        msg "既存の設定をバックアップ: $backup"
        if [ "$DRY_RUN" -eq 0 ]; then
            cp "$tui_file" "$backup"
        fi
    fi

    msg "マウスモードを無効化し、スクロール設定を書き込み"
    if [ "$DRY_RUN" -eq 0 ]; then
        printf '%s\n' "$TUI_JSON" > "$tui_file"
    fi

    if [ "$DRY_RUN" -eq 0 ]; then
        if command -v python3 >/dev/null 2>&1; then
            python3 -m json.tool "$tui_file" >/dev/null
            msg "JSON 検証 OK"
        elif command -v jq >/dev/null 2>&1; then
            jq empty "$tui_file"
            msg "JSON 検証 OK"
        else
            msg "（JSON 検証はスキップ: python3 / jq が見つかりません）"
        fi
    fi

    echo
    echo "完了。tui.json は opencode の起動時に読み込まれます。"
    echo "開いている opencode を終了して起動し直すと反映されます。"
    echo
    echo "スクロール（マウスモード無効時）:"
    echo "  PageUp / PageDown              ページ送り"
    echo "  Ctrl+Alt+U / Ctrl+Alt+D        半ページ"
    echo "  Ctrl+Alt+Y / Ctrl+Alt+E        1 行"
    echo "  Ctrl+G / Home                  先頭 / Ctrl+Alt+G / End 末尾"
    echo "  Ctrl+Alt+S                     スクロールバー表示切替（位置のみ）"
}

uninstall() {
    local tui_file="$OPCODE_DIR/tui.json"
    local backup=""

    msg "opencode TUI スクロール設定のアンインストールを開始"
    if [ ! -f "$tui_file" ]; then
        msg "tui.json はありません（$tui_file）。終了します。"
        return 0
    fi

    backup=$(ls "$tui_file".bak.* 2>/dev/null | tail -n 1)
    if [ -n "$backup" ]; then
        msg "バックアップを復元: $backup -> $tui_file"
        if [ "$DRY_RUN" -eq 0 ]; then
            cp "$backup" "$tui_file"
        fi
    else
        msg "バックアップがないため tui.json を削除します"
        if [ "$DRY_RUN" -eq 0 ]; then
            rm -f "$tui_file"
        fi
    fi

    msg "空になった設定ディレクトリを削除（中身がある場合は残ります）"
    if [ "$DRY_RUN" -eq 0 ]; then
        rmdir "$OPCODE_DIR" 2>/dev/null || true
    fi
}

main() {
    parse_args "$@"
    if [ "$MODE" = uninstall ]; then
        uninstall
    else
        setup
    fi
}

main "$@"
