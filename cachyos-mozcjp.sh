#!/usr/bin/env bash
#
# mozc-jp.sh — KDE Plasma Wayland で Fcitx5 + Mozc による日本語入力をセットアップするスクリプト (修正版)
#
# 行うこと:
#   1. sudo pacman -S --noconfirm --needed fcitx5-im fcitx5-mozc
#   2. システム設定 > キーボード > 仮想キーボード > "Fcitx 5 Wayland ランチャー" を選択
#        → ~/.config/kwinrc の [Wayland] InputMethod を kwriteconfig6 で設定
#        → 過去の実行で壊れた [[Wayland]] / [\x5bWayland] セクションがあれば自動で掃除
#   3. "英語キーボード" を削除して "日本語キーボード" を追加
#        → ~/.config/kxkbrc の [Layout] を kwriteconfig6 で日本語 (jp) のみに設定
#   4. fcitx5 のプロファイルに mozc を追加
#        → ~/.config/fcitx5/profile
#
# 使い方: 通常ユーザーで実行してください (pacman の部分は sudo を使用します)
#     /opt/mozc-jp/mozc-jp.sh
#
# 注意: 反映には一度ログアウト/ログイン (または KWin の再起動) が必要です。
#       何度実行しても設定が重複しないようになっています (冪等)。
#
set -euo pipefail

# ---- 実行ユーザーとホームディレクトリの特定 (sudo 経由でも正しく動作させる) ----
if [ -n "${SUDO_USER:-}" ] && [ "$(id -u)" = 0 ]; then
    TARGET_USER="$SUDO_USER"
    TARGET_HOME="$(getent passwd "$SUDO_USER" | cut -d: -f6)"
else
    TARGET_USER="${USER:-$(id -un)}"
    TARGET_HOME="$HOME"
fi
[ -n "$TARGET_HOME" ] || TARGET_HOME="/home/$TARGET_USER"

CONF_DIR="$TARGET_HOME/.config"
mkdir -p "$CONF_DIR"

# 対象ユーザーとしてコマンドを実行するヘルパー (root + sudo 経由のときだけ sudo -u を使う)
run_as_user() {
    if [ "$(id -u)" = 0 ] && [ -n "${SUDO_USER:-}" ]; then
        sudo -u "$TARGET_USER" env HOME="$TARGET_HOME" "$@"
    else
        "$@"
    fi
}

echo "==> 対象ユーザー: $TARGET_USER ($TARGET_HOME)"
echo

# ---- 1. パッケージのインストール ----
echo "[1/4] fcitx5-im / fcitx5-mozc をインストールします"
if [ "$(id -u)" = 0 ]; then
    pacman -S --noconfirm --needed fcitx5-im fcitx5-mozc
else
    sudo pacman -S --noconfirm --needed fcitx5-im fcitx5-mozc
fi
echo

# ---- kwriteconfig の特定 ----
KWRITE=""
for c in kwriteconfig6 kwriteconfig5; do
    if command -v "$c" >/dev/null 2>&1; then
        KWRITE="$c"
        break
    fi
done
if [ -z "$KWRITE" ]; then
    echo "[エラー] kwriteconfig6 / kwriteconfig5 が見つかりません。KDE (kconfig) 環境で実行してください。" >&2
    exit 1
fi
KREAD="${KWRITE/kwrite/kread}"

# ---- 2. kwinrc: Wayland 入力メソッドを Fcitx 5 Wayland ランチャーに設定 ----
# システム設定 > キーボード > 仮想キーボード > "Fcitx 5 Wayland ランチャー" に相当
# (KWin がこの .desktop ファイルの Exec 行を起動して fcitx5 を入力メソッドとして立ち上げる)
echo "[2/4] kwinrc に Fcitx 5 Wayland ランチャーを設定します"

# 実在するランチャーの .desktop を探す (名前が変わることがあるため候補を複数用意)
LAUNCHER_DESKTOP=""
for cand in \
    /usr/share/applications/fcitx5-wayland-launcher.desktop \
    /usr/share/applications/org.fcitx.Fcitx5.desktop \
    /usr/share/applications/fcitx5.desktop; do
    if [ -f "$cand" ]; then
        LAUNCHER_DESKTOP="$cand"
        break
    fi
done
if [ -z "$LAUNCHER_DESKTOP" ]; then
    echo "[エラー] Fcitx 5 のランチャー .desktop が見つかりません。" >&2
    echo "        ls /usr/share/applications | grep -i fcitx で確認してください。" >&2
    exit 1
fi
echo "    使用するランチャー: $LAUNCHER_DESKTOP"

KWINRC="$CONF_DIR/kwinrc"

# 2-a. 旧バージョンのスクリプトが残した壊れたセクションを掃除
#      ([[Wayland]] と [\x5bWayland] およびその中身をまるごと削除)
if [ -f "$KWINRC" ]; then
    tmp="$(mktemp)"
    awk '
        BEGIN { skip=0 }
        /^\[/ {
            skip = ($0 == "[[Wayland]]" || $0 == "[\\x5bWayland]")
            if (!skip) print
            next
        }
        { if (!skip) print }
    ' "$KWINRC" > "$tmp"
    if ! cmp -s "$KWINRC" "$tmp"; then
        cp -a "$KWINRC" "$KWINRC.bak.$(date +%Y%m%d%H%M%S)"
        cat "$tmp" > "$KWINRC"
        echo "    壊れた [[Wayland]] セクションを削除しました (バックアップを作成済み)"
    fi
    rm -f "$tmp"
fi

# 2-b. 正しい [Wayland] InputMethod を書き込む
run_as_user "$KWRITE" --file "$KWINRC" --group Wayland --key InputMethod "$LAUNCHER_DESKTOP"
echo

# ---- 3. kxkbrc: キーボードレイアウトを日本語 (jp) のみに設定 ----
# システム設定で「英語キーボードを削除して日本語キーボードを追加」した状態に相当
echo "[3/4] kxkbrc のレイアウトを日本語 (jp) のみに設定します"
KXKBRC="$CONF_DIR/kxkbrc"
run_as_user "$KWRITE" --file "$KXKBRC" --group Layout --key Use true
run_as_user "$KWRITE" --file "$KXKBRC" --group Layout --key LayoutList jp
run_as_user "$KWRITE" --file "$KXKBRC" --group Layout --key DisplayNames Japanese
run_as_user "$KWRITE" --file "$KXKBRC" --group Layout --key Options ""
run_as_user "$KWRITE" --file "$KXKBRC" --group Layout --key ResetOldOptions true
# 以前のレイアウト数と食い違うと不整合になるため VariantList は削除
run_as_user "$KWRITE" --file "$KXKBRC" --group Layout --key VariantList --delete
echo

# ---- 4. fcitx5 profile: mozc を入力メソッドとして追加 ----
# fcitx5 の初期プロファイルには keyboard-us しか入らないため、mozc を明示的に追加する
echo "[4/4] fcitx5 のプロファイルに mozc を追加します"
PROFILE="$CONF_DIR/fcitx5/profile"
if [ -f "$PROFILE" ] && grep -q '^Name=mozc$' "$PROFILE"; then
    echo "    mozc は既に登録済みのためスキップします"
else
    if [ -f "$PROFILE" ]; then
        cp -a "$PROFILE" "$PROFILE.bak.$(date +%Y%m%d%H%M%S)"
        echo "    既存プロファイルをバックアップしました"
    fi
    mkdir -p "$(dirname "$PROFILE")"
    cat > "$PROFILE" <<'EOF'
[Groups/0]
Name=Default
Default Layout=jp
DefaultIM=keyboard-jp

[Groups/0/Items/0]
Name=keyboard-jp
Layout=

[Groups/0/Items/1]
Name=mozc
Layout=

[GroupOrder]
0=Default
EOF
fi
echo

# ---- 後処理: root で書いたファイルの所有者を本来のユーザーに戻す ----
if [ "$(id -u)" = 0 ] && [ -n "${SUDO_USER:-}" ]; then
    chown -R "$TARGET_USER" "$CONF_DIR/kwinrc" "$CONF_DIR/kxkbrc" "$CONF_DIR/fcitx5" 2>/dev/null || true
fi

# ---- 可能なら即座に反映 (KWin は kwinrc の変更を監視している) ----
if command -v qdbus6 >/dev/null 2>&1; then
    qdbus6 org.kde.KWin /KWin reconfigure >/dev/null 2>&1 || true
elif command -v qdbus >/dev/null 2>&1; then
    qdbus org.kde.KWin /KWin reconfigure >/dev/null 2>&1 || true
fi
# fcitx5 が動いていれば再起動してプロファイルを読み込み直す
if command -v fcitx5-remote >/dev/null 2>&1; then
    fcitx5-remote -r >/dev/null 2>&1 || true
fi

# ---- 設定結果の確認表示 ----
RESULT="$(run_as_user "$KREAD" --file "$KWINRC" --group Wayland --key InputMethod 2>/dev/null || true)"

echo "=================================================="
echo "セットアップ完了。"
echo
echo "kwinrc [Wayland] InputMethod = ${RESULT:-(未設定)}"
echo
echo "反映させるには一度ログアウトして再ログインしてください (KWin が fcitx5 を"
echo "入力メソッドとして起動します)。ターミナルで確認:"
echo "    grep -n -A1 'Wayland' ~/.config/kwinrc"
echo
echo "使い方:"
echo "  - Ctrl+Space または「ひらがな」キーで 日本語 (mozc) と 直接入力 を切り替え"
echo "  - mozc の詳細設定は fcitx5-configtool (または システム設定 > 地域 > 入力メソッド)"
echo
echo "トラブルシュート:"
echo "  - fcitx5 が二重起動して通知が出る場合、/etc/xdg/autostart/org.fcitx.Fcitx5.desktop"
echo "    をリネームして無効化すると直ることがあります (ArchWiki 推奨)"
echo "  - XWayland アプリで入力できない場合は XMODIFIERS=@im=fcitx を設定してください"
echo "=================================================="
