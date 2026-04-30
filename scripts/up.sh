#!/usr/bin/env bash
set -euo pipefail

ENV_NAME="${1:-local}"
ENV_FILE=".env.${ENV_NAME}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "${ROOT_DIR}"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "[up] ${ENV_FILE} 파일이 없습니다."
  echo "    README.md의 '환경변수' 표를 보고 ${ENV_FILE}을 먼저 작성하세요."
  exit 1
fi

COMPOSE_FILES="-f docker-compose.yml"
PROFILE_FLAG=""
if [[ "${ENV_NAME}" != "local" ]]; then
  # 홈서버: prod override(nginx_proxy 네트워크, 컨테이너 네이밍, 호스트 포트 제거) + linux 프로필
  COMPOSE_FILES="${COMPOSE_FILES} -f docker-compose.prod.yml"
  PROFILE_FLAG="--profile linux"
fi

echo "[up] using ${ENV_FILE} ${PROFILE_FLAG}"
docker compose ${COMPOSE_FILES} --env-file "${ENV_FILE}" ${PROFILE_FLAG} config >/dev/null
docker compose ${COMPOSE_FILES} --env-file "${ENV_FILE}" ${PROFILE_FLAG} up -d
docker compose ${COMPOSE_FILES} --env-file "${ENV_FILE}" ${PROFILE_FLAG} ps
