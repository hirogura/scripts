#!/bin/bash
# ============================================================
#  Code-Server インストールスクリプト v3
#  antiX / runit / Tailscale HTTPS 対応
#
#  改善点（v2 から）:
#    - root レベル runit サービスで再起動後も確実に起動
#    - 既存インストール検出 & 上書き確認
#    - サービス起動の自動リトライ
#    - ロールバック機能（失敗時クリーンアップ）
#
#  構成:
#    - code-server を 127.0.0.1:8089 で待受
#    - Tailscale serve で tailnet 内 HTTPS 公開
#    - Japanese Language Pack 自動インストール
#
#  前提:
#    - tailscale up 済み
#
#  インストール方法（GitHub から）:
#    1) curl -fsSL -o /tmp/antix-install-codeserver.sh \
#       https://raw.githubusercontent.com/hirogura/scripts/main/antix-install-codeserver.sh
#    2) sudo bash /tmp/antix-install-codeserver.sh
#    ワンライナー（パイプ実行）でも可:
#       curl -fsSL https://raw.githubusercontent.com/hirogura/scripts/main/antix-install-codeserver.sh \
#         | sudo bash
#  アンインストール方法は README.md を参照
#
#  使い方:
#    sudo bash antix-install-codeserver.sh              # 対話モード
#    sudo bash antix-install-codeserver.sh -p mypass   # パスワード指定
#    sudo bash antix-install-codeserver.sh -a          # 自動生成
#    sudo bash antix-install-codeserver.sh -y          # 確認なし
#    sudo bash antix-install-codeserver.sh -p mypass -P 9090 -u vscode
# ============================================================

set -euo pipefail

# --- 定数 ---
VERSION="3.0.0"
SV_DIR="/etc/sv/code-server"
SVC_LINK="/etc/service/code-server"
WRAPPER="/usr/local/bin/code-server-wrapper"
CODE_SERVER_BIN="/usr/bin/code-server"
LOG_FILE="/var/log/codeserver-install.log"

# --- カラー ---
GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'
RED='\033[0;31m'; DIM='\033[2m'; NC='\033[0m'
info()    { echo -e "${CYAN}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC}   $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERR]${NC}  $*" >&2; exit 1; }
log()     { echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"; }

# パイプ実行（curl | sudo bash 等）時も端末から入力できるように read をラップする
prompt() {
  if [[ -t 0 ]]; then
    read "$@"
  else
    read "$@" < /dev/tty
  fi
}

# --- オプション解析 ---
PASSWORD=""
CODE_SERVER_PORT=8089
REAL_USER=""
AUTO_PASS=false
YES_MODE=false

usage() {
  cat <<EOF
Usage: sudo bash $0 [OPTIONS]

Options:
  -p, --password PASS   code-server のパスワードを指定
  -P, --port PORT       待受ポート（デフォルト: 8089）
  -u, --user USER       対象ユーザー（デフォルト: 実行ユーザー）
  -a, --auto-password   パスワードを自動生成
  -y, --yes             確認プロンプトをスキップ
  -h, --help            ヘルプ表示

Examples:
  sudo bash $0                          # 対話モード
  sudo bash $0 -a                       # パスワード自動生成
  sudo bash $0 -p mypassword            # パスワード指定
  sudo bash $0 -p pass -P 9090 -u bob   # 全パラメータ指定
  sudo bash $0 -a -y                    # 自動生成・確認なし
EOF
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -p|--password)   PASSWORD="$2"; shift 2 ;;
    -P|--port)       CODE_SERVER_PORT="$2"; shift 2 ;;
    -u|--user)       REAL_USER="$2"; shift 2 ;;
    -a|--auto-password) AUTO_PASS=true; shift ;;
    -y|--yes)        YES_MODE=true; shift ;;
    -h|--help)       usage ;;
    *) error "不明なオプション: $1（--help で確認）" ;;
  esac
done

# --- 前処理 ---
[[ $EUID -ne 0 ]] && error "root権限で実行してください: sudo bash $0"

REAL_USER="${REAL_USER:-${SUDO_USER:-${USER:-$(id -un)}}}"
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

# ログファイル初期化
: > "$LOG_FILE"
log "Installation started (v${VERSION})"

# ============================================================
# ロールバック: 失敗時にクリーンアップ
# ============================================================
cleanup_on_error() {
  local exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    warn "インストール中にエラーが発生しました（終了コード: ${exit_code}）"
    log "ERROR: Installation failed with exit code ${exit_code}"

    # 部分的に作成されたサービスを停止
    sv stop code-server 2>/dev/null || true
    rm -f "$SVC_LINK" 2>/dev/null || true

    error "インストールに失敗しました。ログ: ${LOG_FILE}"
  fi
}
trap cleanup_on_error EXIT

# ============================================================
# 0. 既存インストールの確認
# ============================================================
check_existing() {
  if command -v code-server &>/dev/null; then
    EXISTING_VER=$(code-server --version 2>/dev/null | head -1 || echo "unknown")
    info "code-server が既にインストールされています: ${EXISTING_VER}"

    if sv status code-server 2>/dev/null | grep -q "^run:"; then
      info "現在稼働中です。"
    fi

    if [[ "$YES_MODE" == false ]]; then
      echo -e "  ${YELLOW}[R]${NC} 再インストール（上書き）"
      echo -e "  ${YELLOW}[K]${NC} キャンセル"
      echo ""
      prompt -r -p "選択 [R/K] (Enterでキャンセル): " choice
      case "${choice^^}" in
        R) info "再インストールを実行します..." ;;
        *) info "キャンセルしました。"; exit 0 ;;
      esac
    fi

    # 既存サービスを停止
    sv stop code-server 2>/dev/null || true
    rm -f "$SVC_LINK" 2>/dev/null || true
    log "Existing installation detected, reinstalling"
  fi
}

# ============================================================
# 1. パスワード設定
# ============================================================
prompt_password() {
  if [[ -n "$PASSWORD" ]]; then
    success "コマンドライン引数でパスワードを指定しました"
    return
  fi

  if [[ "$AUTO_PASS" == true ]]; then
    PASSWORD=$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 32)
    success "パスワードを自動生成しました"
    return
  fi

  echo ""
  echo -e "${CYAN}╔══════════════════════════════════════════════════════╗${NC}"
  echo -e "${CYAN}║   Code-Server + Tailscale Serve セットアップ         ║${NC}"
  echo -e "${CYAN}║   v${VERSION}  antiX / runit / tailnet 内 HTTPS 公開    ║${NC}"
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
        prompt -r -s -p "パスワードを入力してください: " PASSWORD
        echo ""
        prompt -r -s -p "もう一度入力してください:     " PASSWORD2
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
# 2. 前提条件チェック
# ============================================================
check_prerequisites() {
  info "前提条件を確認中..."
  command -v tailscale &>/dev/null \
    || error "tailscale がインストールされていません。先に tailscale をセットアップしてください。"
  tailscale status &>/dev/null \
    || error "tailscale が起動していません。'tailscale up' を先に実行してください。"
  command -v apt-get &>/dev/null \
    || error "apt-get が見つかりません。Debian/Ubuntu 系のシステムが必要です。"
  success "前提条件 OK"
}

# ============================================================
# 3. 依存パッケージ
# ============================================================
install_deps() {
  info "依存パッケージをインストール中..."
  apt-get update -qq
  apt-get install -y -qq curl wget openssl
  success "依存パッケージ完了"
}

# ============================================================
# 4. code-server インストール
# ============================================================
install_code_server() {
  info "最新バージョンを確認中..."
  LATEST=$(curl -fsSL https://api.github.com/repos/coder/code-server/releases/latest \
    | grep '"tag_name"' | sed 's/.*"v\([^"]*\)".*/\1/')
  info "最新バージョン: v${LATEST}"

  DEB_URL="https://github.com/coder/code-server/releases/download/v${LATEST}/code-server_${LATEST}_amd64.deb"
  info "ダウンロード中..."
  wget -q --show-progress -O /tmp/code-server.deb "$DEB_URL"
  dpkg -i /tmp/code-server.deb || apt-get -f install -y
  rm -f /tmp/code-server.deb
  success "code-server v${LATEST} インストール完了"
  log "Installed code-server v${LATEST}"
}

# ============================================================
# 5. Japanese Language Pack
# ============================================================
install_japanese_language_pack() {
  info "Japanese Language Pack をインストール中..."
  EXT_DIR="$REAL_HOME/.local/share/code-server/extensions"
  mkdir -p "$EXT_DIR"
  chown -R "$REAL_USER:$REAL_USER" "$REAL_HOME/.local/share/code-server"

  sudo -u "$REAL_USER" code-server --install-extension MS-CEINTL.vscode-language-pack-ja \
    || warn "Japanese Language Pack のインストールに失敗しました（後で手動インストール可能）"

  success "Japanese Language Pack 完了"
}

# ============================================================
# 6. 設定ファイル生成
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
  success "config.yaml 生成完了（127.0.0.1:${CODE_SERVER_PORT}）"

  info "settings.json（日本語化 + 推奨設定）を配置中..."
  VSCODE_USER_DIR="$REAL_HOME/.local/share/code-server/User"
  mkdir -p "$VSCODE_USER_DIR"

  cat > "$REAL_HOME/.local/share/code-server/argv.json" <<'EOF'
{
  "locale": "ja"
}
EOF

  cat > "$VSCODE_USER_DIR/locale.json" <<'EOF'
{
  "locale": "ja"
}
EOF

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
# 7. runit サービス（root レベル）
# ============================================================
setup_runit() {
  info "runit サービスを登録中（root レベル）..."
  NLS_CONFIG='{"locale":"ja","osLocale":"ja","availableLanguages":{"*":"ja"}}'

  cat > "$WRAPPER" <<WEOF
#!/bin/bash
export HOME="${REAL_HOME}"
export VSCODE_NLS_CONFIG='${NLS_CONFIG}'
exec ${CODE_SERVER_BIN} "\$@"
WEOF
  chmod +x "$WRAPPER"

  mkdir -p "$SV_DIR"
  cat > "$SV_DIR/run" <<'EOF'
#!/bin/bash
exec 2>&1
exec /usr/local/bin/code-server-wrapper
EOF
  chmod +x "$SV_DIR/run"

  ln -sfn "$SV_DIR" "$SVC_LINK"

  # 既存の user レベルサービスを削除
  rm -rf "$REAL_HOME/.runit/service/code-server" "$REAL_HOME/.runit/usersv/code-server" 2>/dev/null || true

  # 起動確認 with リトライ
  info "サービス起動確認中..."
  local retry=0
  local max_retry=5
  while [[ $retry -lt $max_retry ]]; do
    sleep 2
    if sv status code-server 2>/dev/null | grep -q "^run:"; then
      success "code-server 正常起動（root レベル runit）"
      log "runit service started successfully"
      return 0
    fi
    retry=$((retry + 1))
    if [[ $retry -lt $max_retry ]]; then
      warn "起動確認リトライ (${retry}/${max_retry})..."
      sv start code-server 2>/dev/null || true
    fi
  done

  warn "自動起動確認に失敗しました。手動で起動してください: sv start code-server"
  warn "ログ確認: sv status code-server -v"
}

# ============================================================
# 8. Tailscale serve 設定
# ============================================================
get_ts_hostname() {
  tailscale status --json 2>/dev/null | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    s = d.get('Self', {})
    dns = s.get('DNSName', '').rstrip('.')
    print(dns if dns else s.get('HostName', 'unknown'))
except:
    print('unknown')
" 2>/dev/null || echo "unknown"
}

setup_tailscale_serve() {
  info "Tailscale serve に code-server (port ${CODE_SERVER_PORT}) を追加中..."

  # 既存の serve 設定があれば削除してから再設定
  tailscale serve --https="${CODE_SERVER_PORT}" off 2>/dev/null || true
  tailscale serve --bg --https=${CODE_SERVER_PORT} "http://127.0.0.1:${CODE_SERVER_PORT}"
  success "Tailscale serve 設定完了"

  TS_HOSTNAME=$(get_ts_hostname)

  echo ""
  echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${GREEN}  [OK] セットアップ完了！ (v${VERSION})${NC}"
  echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
  echo -e "  アクセスURL（tailnet 内のデバイスからのみアクセス可）:"
  echo -e "     ${CYAN}https://${TS_HOSTNAME}:${CODE_SERVER_PORT}${NC}"
  echo ""
  echo -e "  code-server パスワード: ${YELLOW}${PASSWORD}${NC}"
  echo ""
  echo -e "  日本語化: インストール時に自動設定済み（再起動不要）"
  echo ""
  echo -e "  管理コマンド:"
  echo -e "     再起動:         sv restart code-server"
  echo -e "     停止:           sv stop code-server"
  echo -e "     ステータス:     sv status code-server"
  echo -e "     ログ:           tail -f /var/log/code-server/current"
  echo -e "     serve 確認:     tailscale serve status"
  echo -e "     serve 削除:     tailscale serve --https=${CODE_SERVER_PORT} off"
  echo ""
  echo -e "  [!] このパスワードを安全な場所に保管してください。"
  echo -e "     設定ファイル: ${REAL_HOME}/.config/code-server/config.yaml"
  echo ""

  log "Installation completed successfully"
}

# ============================================================
# 9. デスクトップショートカット作成
# ============================================================
create_shortcut() {
  info "デスクトップショートカットを作成中..."
  mkdir -p "$REAL_HOME/Desktop"

  TS_HOSTNAME=$(get_ts_hostname)

  cat > "$REAL_HOME/Desktop/code-server.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Code-Server
Comment=VS Code（ブラウザ版）
Exec=google-chrome-stable --app=https://${TS_HOSTNAME}:${CODE_SERVER_PORT}
Icon=vscode
Terminal=false
Categories=Development;IDE;
EOF

  chmod +x "$REAL_HOME/Desktop/code-server.desktop"
  success "デスクトップに code-server.desktop を作成しました（https://${TS_HOSTNAME}:${CODE_SERVER_PORT}）"
}

# ============================================================
# メイン
# ============================================================
main() {
  check_existing           # 既存インストール確認
  prompt_password          # ① パスワード設定
  check_prerequisites      # ② Tailscale確認
  install_deps             # ③ 依存パッケージ
  install_code_server      # ④ code-server インストール
  install_japanese_language_pack  # ⑤ 日本語パック
  setup_config             # ⑥ 設定ファイル
  setup_runit              # ⑦ runit 登録（root レベル）
  setup_tailscale_serve    # ⑧ Tailscale serve 設定
  create_shortcut          # ⑨ デスクトップショートカット作成
}

main "$@"
