#!/usr/bin/env bash
set -euo pipefail

ENV_NAME="${1:-local}"
ENV_FILE=".env.${ENV_NAME}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "${ROOT_DIR}"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "[down] ${ENV_FILE} 파일이 없습니다. (그냥 docker compose down 만 실행)"
  docker compose down
  exit 0
fi

PROFILE_FLAG=""
if [[ "${ENV_NAME}" != "local" ]]; then
  PROFILE_FLAG="--profile linux"
fi

echo "[down] using ${ENV_FILE} ${PROFILE_FLAG}"
docker compose --env-file "${ENV_FILE}" ${PROFILE_FLAG} down
