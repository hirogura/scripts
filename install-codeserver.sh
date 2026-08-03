#!/bin/bash
# ============================================================
#  Code-Server インストール（Ubuntu 26.04 直接インストール版）
#  構成:
#    - code-server を localhost のみで待受
#    - tailscale serve で HTTPS化（tailnet 内のみ公開）
#    - Japanese Language Pack 自動インストール済み
#  前提:
#    - tailscale up 済み
#  インストール方法（GitHub から）:
#    1) curl -fsSL -o /tmp/install-codeserver.sh \
#       https://raw.githubusercontent.com/hirogura/scripts/main/install-codeserver.sh
#    2) sudo bash /tmp/install-codeserver.sh
#    ワンライナー（パイプ実行）でも可:
#       curl -fsSL https://raw.githubusercontent.com/hirogura/scripts/main/install-codeserver.sh \
#         | sudo bash
#  アンインストール方法は README.md を参照
# ============================================================

set -euo pipefail

GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()    { echo -e "${CYAN}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC}   $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERR]${NC}  $*"; exit 1; }

# パイプ実行（curl | bash 等）時も端末から入力できるように read をラップする
prompt() {
  if [[ -t 0 ]]; then
    read "$@"
  else
    read "$@" < /dev/tty
  fi
}

[[ $EUID -ne 0 ]] && error "root権限で実行してください: sudo bash install-codeserver.sh"

REAL_USER="${SUDO_USER:-${USER:-$(id -un)}}"
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)
CODE_SERVER_PORT=8089
PASSWORD=""

# ============================================================
# ① パスワードを最初に聞く（デフォルト: M=手動入力）
# ============================================================
prompt_password() {
  echo ""
  echo -e "${CYAN}╔══════════════════════════════════════════════════════╗${NC}"
  echo -e "${CYAN}║   Code-Server + Tailscale Serve セットアップ         ║${NC}"
  echo -e "${CYAN}║   Ubuntu 26.04 / tailnet 内 HTTPS 公開               ║${NC}"
  echo -e "${CYAN}║   日本語化セットアップ済み                            ║${NC}"
  echo -e "${CYAN}╚══════════════════════════════════════════════════════╝${NC}"
  echo ""
  echo -e "インストール対象ユーザー: ${YELLOW}${REAL_USER}${NC} (${REAL_HOME})"
  echo ""
  echo "code-server のパスワードを設定してください。"
  echo -e "  ${CYAN}[A]${NC} 自動生成する（ランダム32文字）"
  echo -e "  ${CYAN}[M]${NC} 手動で入力する"
  echo ""
  prompt -r -p "選択 [A/M] (Enterで手動入力): " choice
  case "${choice^^}" in
    A)
      PASSWORD=$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 32)
      success "パスワードを自動生成しました。（後で表示します）"
      ;;
    *)
      while true; do
        prompt -r -s -p "🔑 パスワードを入力してください: " PASSWORD
        echo ""
        prompt -r -s -p "🔑 もう一度入力してください:     " PASSWORD2
        echo ""
        if [[ "$PASSWORD" == "$PASSWORD2" && -n "$PASSWORD" ]]; then
          success "パスワードを設定しました。"
          break
        else
          warn "パスワードが一致しないか空です。もう一度入力してください。"
        fi
      done
      ;;
  esac
  echo ""
}

# ============================================================
# ② Tailscale の動作確認
# ============================================================
check_prerequisites() {
  info "前提条件を確認中..."
  command -v tailscale &>/dev/null \
    || error "tailscale がインストールされていません。先に tailscale をセットアップしてください。"
  tailscale status &>/dev/null \
    || error "tailscale が起動していません。'tailscale up' を先に実行してください。"
  success "Tailscale 動作確認OK"
}

# ============================================================
# ③ 依存パッケージのインストール
# ============================================================
install_deps() {
  info "依存パッケージをインストール中..."
  apt-get update -qq
  apt-get install -y -qq curl wget openssl
  success "依存パッケージ インストール完了"
}

# ============================================================
# ④ code-server のインストール
# ============================================================
install_code_server() {
  info "最新バージョンを確認中..."
  LATEST=$(curl -fsSL https://api.github.com/repos/coder/code-server/releases/latest \
    | grep '"tag_name"' | sed 's/.*"v\([^"]*\)".*/\1/')
  info "最新バージョン: v${LATEST}"

  DEB_URL="https://github.com/coder/code-server/releases/download/v${LATEST}/code-server_${LATEST}_amd64.deb"
  info "ダウンロード中..."
  wget -q --show-progress -O /tmp/code-server.deb "$DEB_URL"
  dpkg -i /tmp/code-server.deb
  rm /tmp/code-server.deb
  success "code-server v${LATEST} インストール完了"
}

# ============================================================
# ⑤ Japanese Language Pack のインストール
# ============================================================
install_japanese_language_pack() {
  info "Japanese Language Pack をインストール中..."

  # code-server の拡張機能ディレクトリを確保
  EXT_DIR="$REAL_HOME/.local/share/code-server/extensions"
  mkdir -p "$EXT_DIR"
  chown -R "$REAL_USER:$REAL_USER" "$REAL_HOME/.local/share/code-server"

  # 実ユーザーとして拡張機能をインストール
  sudo -u "$REAL_USER" code-server --install-extension MS-CEINTL.vscode-language-pack-ja \
    || error "Japanese Language Pack のインストールに失敗しました"

  success "Japanese Language Pack インストール完了"
}

# ============================================================
# ⑥ 設定ファイルの生成（日本語化設定込み）
# ============================================================
setup_config() {
  info "config.yaml を生成中..."
  CONFIG_DIR="$REAL_HOME/.config/code-server"
  mkdir -p "$CONFIG_DIR"
  cat > "$CONFIG_DIR/config.yaml" <<EOF
bind-addr: 127.0.0.1:${CODE_SERVER_PORT}
auth: password
password: ${PASSWORD}
cert: false
EOF
  chown -R "$REAL_USER:$REAL_USER" "$CONFIG_DIR"
  chmod 600 "$CONFIG_DIR/config.yaml"
  success "config.yaml 生成完了（127.0.0.1:${CODE_SERVER_PORT} でローカルのみ待受）"

  info "settings.json（日本語化 + 推奨設定）を配置中..."
  VSCODE_USER_DIR="$REAL_HOME/.local/share/code-server/User"
  mkdir -p "$VSCODE_USER_DIR"

  # argv.json: ロケール設定（日本語）
  cat > "$VSCODE_USER_DIR/../argv.json" <<'EOF'
{
  "locale": "ja"
}
EOF

  # locale.json: 表示言語の明示設定
  cat > "$VSCODE_USER_DIR/locale.json" <<'EOF'
{
  "locale": "ja"
}
EOF

  # settings.json: 基本的な快適設定
  cat > "$VSCODE_USER_DIR/settings.json" <<'EOF'
{
  "editor.fontSize": 14,
  "editor.tabSize": 2,
  "editor.formatOnSave": true,
  "editor.minimap.enabled": false,
  "workbench.colorTheme": "Default Dark Modern",
  "terminal.integrated.fontSize": 13,
  "files.autoSave": "afterDelay",
  "files.autoSaveDelay": 1000
}
EOF

  chown -R "$REAL_USER:$REAL_USER" "$REAL_HOME/.local/share/code-server"
  success "settings.json / argv.json / locale.json 配置完了"
}

# ============================================================
# ⑦ systemd サービスの登録・起動
# ============================================================
setup_systemd() {
  info "systemd サービスを登録中..."
  NLS_CONFIG='{"locale":"ja","osLocale":"ja","availableLanguages":{"*":"ja"}}'
  cat > /etc/systemd/system/code-server.service <<EOF
[Unit]
Description=code-server (VS Code in Browser)
After=network.target

[Service]
Type=exec
User=${REAL_USER}
WorkingDirectory=${REAL_HOME}
ExecStart=/usr/bin/code-server
Restart=always
RestartSec=5
Environment=HOME=${REAL_HOME}
Environment=VSCODE_NLS_CONFIG=${NLS_CONFIG}

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable code-server
  systemctl restart code-server

  info "起動確認中..."
  sleep 4
  systemctl is-active --quiet code-server \
    && success "code-server 正常起動" \
    || { journalctl -u code-server -n 20 --no-pager; error "code-server の起動に失敗しました"; }
}

# ============================================================
# ⑧ Tailscale serve 設定（tailnet 内のみ HTTPS 公開）
# ============================================================
setup_tailscale_serve() {
  info "Tailscale serve に code-server (port ${CODE_SERVER_PORT}) を追加中..."

  tailscale serve --bg --https=${CODE_SERVER_PORT} "http://127.0.0.1:${CODE_SERVER_PORT}"
  success "Tailscale serve 設定完了（tailnet 内 HTTPS のみ）"

  TS_HOSTNAME=$(tailscale status --json 2>/dev/null | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    s = d.get('Self', {})
    dns = s.get('DNSName', '').rstrip('.')
    print(dns if dns else s.get('HostName', 'unknown'))
except:
    print('unknown')
" 2>/dev/null || echo "unknown")

  echo ""
  echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${GREEN}  ✅ セットアップ完了！${NC}"
  echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
  echo -e "  🌐 アクセスURL（tailnet 内のデバイスからのみアクセス可）:"
  echo -e "     ${CYAN}https://${TS_HOSTNAME}:${CODE_SERVER_PORT}${NC}"
  echo ""
  echo -e "  🔑 code-server パスワード: ${YELLOW}${PASSWORD}${NC}"
  echo ""
  echo -e "  🧩 日本語化: インストール時に自動設定済み（再起動不要）"
  echo ""
  echo -e "  📋 管理コマンド:"
  echo -e "     ログ確認:       journalctl -u code-server -f"
  echo -e "     再起動:         sudo systemctl restart code-server"
  echo -e "     停止:           sudo systemctl stop code-server"
  echo -e "     serve 確認:     tailscale serve status"
  echo -e "     serve 削除:     tailscale serve --https=${CODE_SERVER_PORT} off"
  echo ""
  echo -e "  ⚠️  このパスワードを安全な場所に保管してください。"
  echo -e "     設定ファイル: ${REAL_HOME}/.config/code-server/config.yaml"
  echo ""
}

# ============================================================
# メイン
# ============================================================
main() {
  prompt_password        # ① パスワード設定（デフォルト: M）
  check_prerequisites    # ② Tailscale確認
  install_deps           # ③ 依存パッケージ
  install_code_server    # ④ code-server インストール
  install_japanese_language_pack  # ⑤ Japanese Language Pack インストール
  setup_config           # ⑥ 設定ファイル生成（日本語化込み）
  setup_systemd          # ⑦ systemd 登録・起動
  setup_tailscale_serve  # ⑧ Tailscale serve 設定
}

main "$@"
