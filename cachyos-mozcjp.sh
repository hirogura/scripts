#!/usr/bin/env bash
#
# mozc-jp.sh — KDE Plasma Wayland で Fcitx5 + Mozc による日本語入力をセットアップするスクリプト
#
# これまで手動で行っていた以下の操作をすべてコマンドで再現します:
#   1. sudo pacman -S --noconfirm --needed fcitx5-im fcitx5-mozc
#   2. システム設定 > キーボード > 仮想キーボード > "Fcitx 5 Wayland ランチャー" を選択
#        → ~/.config/kwinrc の [Wayland] InputMethod を設定 (KWin が fcitx5 を起動)
#   3. "英語キーボード" を削除して "日本語キーボード" を追加
#        → ~/.config/kxkbrc の [Layout] を日本語 (jp) のみに設定
#   4. (おまけ) fcitx5 のプロファイルに mozc を追加
#        → ~/.config/fcitx5/profile (mozc が無いと日本語変換できません)
#
# 使い方: 通常ユーザーで実行してください (pacman の部分は sudo を使用します)
#     /opt/mozc-jp/mozc-jp.sh
#
# 注意: 反映には一度ログアウト/ログイン (または KWin の再起動) が必要です。
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

# ---- INI ファイルのヘルパー関数 ----
# set_ini <file> <section> <key> <value>
#   [section] 内の key=value を設定 (既存キーは置換、セクション/ファイルが無ければ作成)
set_ini() {
    local file="$1" section="$2" key="$3" value="$4"
    local tmp
    tmp="$(mktemp)"
    if [ ! -f "$file" ]; then
        printf '[%s]\n%s=%s\n' "$section" "$key" "$value" > "$file"
        rm -f "$tmp"
        return 0
    fi
    awk -v sec="[$section]" -v key="$key" -v val="$value" '
        BEGIN { in_sec=0; found=0; done=0 }
        /^\[/ {
            if (in_sec && !done) { print key "=" val; done=1 }
            in_sec = ($0 == sec)
            print
            next
        }
        {
            # キーは "key=" または "key[...]=" (例: InputMethod[$e]=) の両方を置換
            if (in_sec && !done && $0 ~ "^" key "[=[]") { print key "=" val; done=1; next }
            print
        }
        END {
            if (!done) {
                if (!in_sec) { print "[" sec "]" }
                print key "=" val
            }
        }
    ' "$file" > "$tmp" && mv "$tmp" "$file"
}

# ---- 2. kwinrc: Wayland 入力メソッドを Fcitx 5 Wayland ランチャーに設定 ----
# システム設定 > キーボード > 仮想キーボード > "Fcitx 5 Wayland ランチャー" に相当
# (KWin がこの .desktop ファイルの Exec 行を起動して fcitx5 を入力メソッドとして立ち上げる)
echo "[2/4] kwinrc に Fcitx 5 Wayland ランチャーを設定します"
# 複数の候補から実際にインストールされた .desktop を自動検出する
# (CachyOS/Plasma6 ではファイル名が変わることがあるため)
LAUNCHER_DESKTOP=""
if [ -d /usr/share/applications ]; then
    LAUNCHER_DESKTOP="$(grep -rl 'X-KDE-Wayland-VirtualKeyboard=true' /usr/share/applications 2>/dev/null | head -n 1 || true)"
fi
for cand in \
    /usr/share/applications/fcitx5-wayland-launcher.desktop \
    /usr/share/applications/org.fcitx.Fcitx5.desktop \
    /usr/share/applications/fcitx5.desktop; do
    if [ -z "$LAUNCHER_DESKTOP" ] && [ -f "$cand" ]; then
        LAUNCHER_DESKTOP="$cand"
    fi
done
if [ -z "$LAUNCHER_DESKTOP" ]; then
    echo "    警告: Fcitx 5 Wayland ランチャーの .desktop が見つかりませんでした" >&2
    LAUNCHER_DESKTOP="/usr/share/applications/fcitx5-wayland-launcher.desktop"
fi
set_ini "$CONF_DIR/kwinrc" "Wayland" "InputMethod" "$LAUNCHER_DESKTOP"
echo

# ---- 3. kxkbrc: キーボードレイアウトを日本語 (jp) のみに設定 ----
# システム設定で「英語キーボードを削除して日本語キーボードを追加」した状態に相当
echo "[3/4] kxkbrc のレイアウトを日本語 (jp) のみに設定します"
KXKBRC="$CONF_DIR/kxkbrc"
# 既存の [Layout] セクションを一旦除去し、日本語のみの設定を書き直す
if [ -f "$KXKBRC" ]; then
    tmp="$(mktemp)"
    awk '
        BEGIN { skip=0 }
        /^\[/ { skip = ($0 == "[Layout]"); if (!skip) print; next }
        { if (!skip) print }
    ' "$KXKBRC" > "$tmp"
    mv "$tmp" "$KXKBRC"
fi
cat >> "$KXKBRC" <<'EOF'
[Layout]
DisplayNames=Japanese
LayoutList=jp
Options=
ResetOldOptions=true
Use=true
EOF
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

# ---- 後処理: root で書いた設定ファイルの所有者を本来のユーザーに戻す ----
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

echo "=================================================="
echo "セットアップ完了。"
echo
echo "反映させるには一度ログアウトして再ログインしてください (KWin が fcitx5 を"
echo "入力メソッドとして起動します)。ターミナルで確認:"
echo "    grep InputMethod ~/.config/kwinrc"
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
