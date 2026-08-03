#!/bin/bash
set -euo pipefail
# =============================================================
#  Immich セットアップスクリプト (tailscale serve版)
#
#  構成:
#   - Immich : https://<hostname>.<tailnet>.ts.net:3307 (tailscale serve 3307)
#
#  ディレクトリ構成:
#   /opt/docker/immich/
#     docker-compose.yml
#     .env                 ← DBパスワード等の永続化
#     postgres/            ← PostgreSQLデータ
#     upload/               ← thumbs/upload/profile/backups/encoded-video等
#   /opt/lxd-data/immich-library/   ← ユーザーごとの写真本体（例: admin/）
#
#  前提条件:
#   - Docker がインストール済みであること
#   - tailscale up 済みであること
#   - Tailscale管理コンソールでHTTPS Certificatesを有効化済み
#     https://login.tailscale.com/admin/dns
#
#  インストール方法（GitHub から）:
#    1) curl -fsSL -o /tmp/install-immich.sh \
#       https://raw.githubusercontent.com/hirogura/scripts/main/install-immich.sh
#    2) sudo bash /tmp/install-immich.sh
#    ワンライナー（パイプ実行）でも可:
#       curl -fsSL https://raw.githubusercontent.com/hirogura/scripts/main/install-immich.sh \
#         | sudo bash
#  アンインストール方法は README.md を参照
# =============================================================

IMMICH_DIR="/opt/docker/immich"
LIBRARY_DIR="/opt/lxd-data/immich-library"   # ユーザー写真データのみ（/library配下を直接ここに）
UPLOAD_SUBDIR="${IMMICH_DIR}/upload"          # thumbs/upload/profile/backups等の残り
IMMICH_PORT=2283         # ホスト内部ポート（127.0.0.1バインド・元のまま）
TAILSCALE_PORT=3307      # tailscale serveで公開するポート

# ── カラー出力 ────────────────────────────────────
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo ""
echo "════════════════════════════════════════"
echo "  Immich セットアップ (tailscale serve版)"
echo "════════════════════════════════════════"
echo ""

# ── root権限確認 ─────────────────────────────────
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}ERROR: root権限で実行してください: sudo bash install-immich.sh${NC}"
    exit 1
fi

# ── 前提ツール確認 ───────────────────────────────
for cmd in docker openssl curl python3; do
    if ! command -v "$cmd" &>/dev/null; then
        echo -e "${RED}ERROR: ${cmd} がインストールされていません${NC}"
        exit 1
    fi
done

# ── Tailscale確認 ─────────────────────────────────
if ! command -v tailscale &>/dev/null; then
    echo -e "${RED}ERROR: tailscaleがインストールされていません${NC}"
    exit 1
fi

if ! tailscale status &>/dev/null 2>&1; then
    echo -e "${RED}ERROR: tailscaleが接続されていません。tailscale up を実行してください${NC}"
    exit 1
fi

# ── tailnetドメイン取得 ───────────────────────────
echo "==> [1/5] Tailscaleドメインを取得..."
sudo tailscale set --operator=$USER 2>/dev/null || true

TAILSCALE_DOMAIN=$(tailscale status --json | python3 -c "
import json, sys
d = json.load(sys.stdin)
print(d.get('Self', {}).get('DNSName', '').rstrip('.'))
" 2>/dev/null)

if [ -z "$TAILSCALE_DOMAIN" ]; then
    echo -e "${RED}ERROR: Tailscaleドメインを取得できませんでした${NC}"
    echo "Tailscale管理コンソールでMagicDNSが有効になっているか確認してください"
    exit 1
fi

echo -e "  ${GREEN}ドメイン: ${TAILSCALE_DOMAIN}${NC}"
echo -e "  ${GREEN}Immich : https://${TAILSCALE_DOMAIN}:${TAILSCALE_PORT}${NC}"

# ── ディレクトリ作成 ──────────────────────────────
echo ""
echo "==> [2/5] ディレクトリを準備..."
mkdir -p "${IMMICH_DIR}/postgres"
mkdir -p "${UPLOAD_SUBDIR}"
mkdir -p "${LIBRARY_DIR}"
echo -e "  ${GREEN}✓ ${IMMICH_DIR}/postgres${NC}"
echo -e "  ${GREEN}✓ ${UPLOAD_SUBDIR}${NC}"
echo -e "  ${GREEN}✓ ${LIBRARY_DIR}（写真本体）${NC}"

# ── .env 生成 or 既存を使用 ───────────────────────
echo ""
echo "==> [3/5] .env を確認..."

if [ -f "${IMMICH_DIR}/.env" ]; then
    source "${IMMICH_DIR}/.env"
    echo -e "  ${GREEN}✓ 既存の .env を使用${NC}"
else
    if [ "$(find "${IMMICH_DIR}/postgres" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l)" -gt 0 ]; then
        echo -e "${RED}ERROR: DBデータが存在しますが .env が見つかりません${NC}"
        echo -e "${RED}       ${IMMICH_DIR}/.env が必要です${NC}"
        echo ""
        echo "  対処法: DBデータを削除して再セットアップ:"
        echo "    docker compose -f ${IMMICH_DIR}/docker-compose.yml down -v"
        echo "    rm -rf ${IMMICH_DIR}/postgres/*"
        exit 1
    fi

    DB_PASSWORD=$(openssl rand -hex 16)

    cat > "${IMMICH_DIR}/.env" <<EOF
UPLOAD_LOCATION=${UPLOAD_SUBDIR}
LIBRARY_LOCATION=${LIBRARY_DIR}
DB_DATA_LOCATION=${IMMICH_DIR}/postgres
IMMICH_VERSION=release
DB_PASSWORD=${DB_PASSWORD}
DB_USERNAME=postgres
DB_DATABASE_NAME=immich
EOF
    chmod 600 "${IMMICH_DIR}/.env"
    echo -e "  ${GREEN}✓ 新しい .env を生成${NC}"
fi

# ── docker-compose.yml 生成 ───────────────────────
echo ""
echo "==> [4/5] 設定ファイルを生成..."

cat > "${IMMICH_DIR}/docker-compose.yml" <<'EOF'
name: immich

services:
  immich-server:
    container_name: immich_server
    image: ghcr.io/immich-app/immich-server:${IMMICH_VERSION:-release}
    volumes:
      - ${UPLOAD_LOCATION}:/data
      - ${LIBRARY_LOCATION}:/data/library
      - /etc/localtime:/etc/localtime:ro
    env_file:
      - .env
    ports:
      - '127.0.0.1:2283:2283'
    depends_on:
      - redis
      - database
    restart: always
    healthcheck:
      disable: false

  immich-machine-learning:
    container_name: immich_machine_learning
    image: ghcr.io/immich-app/immich-machine-learning:${IMMICH_VERSION:-release}
    volumes:
      - model-cache:/cache
    env_file:
      - .env
    restart: always
    healthcheck:
      disable: false

  redis:
    container_name: immich_redis
    image: docker.io/valkey/valkey:9
    healthcheck:
      test: redis-cli ping || exit 1
    restart: always

  database:
    container_name: immich_postgres
    image: ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0
    environment:
      POSTGRES_PASSWORD: ${DB_PASSWORD}
      POSTGRES_USER: ${DB_USERNAME}
      POSTGRES_DB: ${DB_DATABASE_NAME}
      POSTGRES_INITDB_ARGS: '--data-checksums'
    volumes:
      - ${DB_DATA_LOCATION}:/var/lib/postgresql/data
    shm_size: 128mb
    healthcheck:
      disable: false
    restart: always

volumes:
  model-cache:
EOF

echo -e "  ${GREEN}✓ ${IMMICH_DIR}/docker-compose.yml${NC}"

# ── Docker起動 & tailscale serve設定 ─────────────
echo ""
echo "==> [5/5] コンテナを起動..."

cd "${IMMICH_DIR}"
docker compose pull
docker compose up -d

echo "  ⏳ Immich serverの起動を待機中（最大180秒）..."
for i in $(seq 1 36); do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:${IMMICH_PORT}/" 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" != "000" ]; then
        echo -e "\n  ${GREEN}✓ Immich server 起動完了 (HTTP ${HTTP_CODE})${NC}"
        break
    fi
    if [ "$i" -eq 36 ]; then
        echo -e "\n${RED}ERROR: Immich serverがタイムアウトしました${NC}"
        docker logs immich_server --tail=20
        exit 1
    fi
    sleep 5
    echo -n "."
done

# 既存のserve設定を残しつつImmichのポートのみ追加（冪等対応）
tailscale serve --https=${TAILSCALE_PORT} off 2>/dev/null || true
tailscale serve --bg --https=${TAILSCALE_PORT} http://localhost:${IMMICH_PORT}
echo -e "  ${GREEN}✓ tailscale serve 設定完了${NC}"

echo ""
tailscale serve status

# ── 完了メッセージ ────────────────────────────────
echo ""
echo "════════════════════════════════════════"
echo -e "  ${GREEN}✅  起動完了！${NC}"
echo "════════════════════════════════════════"
echo ""
echo "  🌐 URL         : https://${TAILSCALE_DOMAIN}:${TAILSCALE_PORT}"
echo "  🗄️  DBパスワード : ${DB_PASSWORD}"
echo ""
echo "  📁 ディレクトリ構成:"
echo "    設定    : ${IMMICH_DIR}/.env"
echo "    写真    : ${LIBRARY_DIR}/（ユーザー名フォルダ直下）"
echo "    その他  : ${UPLOAD_SUBDIR}/（thumbs, upload, profile, backups等）"
echo "    DB      : ${IMMICH_DIR}/postgres/"
echo ""
echo "════════════════════════════════════════"
echo "  🔧 アップデート手順"
echo "════════════════════════════════════════"
echo ""
echo "  cd ${IMMICH_DIR} && docker compose pull && docker compose up -d"
echo ""
echo "════════════════════════════════════════"
echo ""
