#!/usr/bin/env bash
# ServerState 배포: 로컬에서 한 번 실행하면 push → 홈서버 pull → 기동/재기동 → nginx 동기화 → 헬스체크
# 사용:
#   bash scripts/deploy.sh           # 표준 배포 (변경 없으면 컨테이너 기동 생략)
#   bash scripts/deploy.sh --restart # 컨테이너 강제 재기동
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

SSH="ssh -i ${HOME}/.ssh/ghmate_server -p 222 ghmate@ghmate.iptime.org"
REMOTE_DIR="/srv/projects/serverstate"

FORCE_RESTART=0
[[ "${1:-}" == "--restart" ]] && FORCE_RESTART=1

# ---------- 1) 로컬 사전 체크 ----------
echo "[deploy] 1/5 로컬 사전 체크"
if [[ -n "$(git status --porcelain)" ]]; then
  echo "  ✗ uncommitted 변경 있음. 먼저 커밋하세요:"
  git status --short
  exit 1
fi

CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
if [[ "${CURRENT_BRANCH}" != "main" ]]; then
  echo "  ✗ 현재 브랜치가 main이 아닙니다 (${CURRENT_BRANCH}). main에서만 배포 가능."
  exit 1
fi
echo "  ✓ clean / branch=main"

# ---------- 2) push ----------
echo "[deploy] 2/5 git push origin main"
git push origin main 2>&1 | tail -2

# ---------- 3) 원격: pull + 변경 감지 + 재기동 ----------
echo "[deploy] 3/5 홈서버 pull + 적용"
${SSH} env FORCE_RESTART="${FORCE_RESTART}" REMOTE_DIR="${REMOTE_DIR}" bash -se <<'REMOTE'
set -euo pipefail
cd "${REMOTE_DIR}"

BEFORE=$(git rev-parse HEAD)
git pull --quiet
AFTER=$(git rev-parse HEAD)

if [[ "${BEFORE}" == "${AFTER}" ]]; then
  CHANGED=""
  echo "  pull: 변경 없음 (HEAD ${BEFORE:0:7})"
else
  CHANGED=$(git diff --name-only "${BEFORE}" "${AFTER}")
  echo "  pull: ${BEFORE:0:7} → ${AFTER:0:7}"
  echo "${CHANGED}" | sed 's/^/    /'
fi

# compose / prom / grafana provisioning / scripts 중 하나라도 바뀌었거나 --restart면 up
if [[ "${FORCE_RESTART}" == "1" ]] || echo "${CHANGED}" | grep -qE '(docker-compose.*\.yml|prometheus/|grafana/provisioning/|alertmanager/|scripts/)'; then
  echo "  컨테이너 재기동..."
  bash scripts/up.sh dev > /tmp/serverstate_up.log 2>&1 || { cat /tmp/serverstate_up.log; exit 1; }
  echo "  ✓ up done"
else
  echo "  컨테이너 기동 생략"
fi

# nginx conf 변경 감지
if ! diff -q deploy/serverstate.conf /srv/nginx-proxy/conf.d/serverstate.conf >/dev/null 2>&1; then
  echo "  nginx conf 갱신..."
  cp deploy/serverstate.conf /srv/nginx-proxy/conf.d/serverstate.conf
  docker exec nginx_proxy nginx -t >/dev/null 2>&1
  docker restart nginx_proxy >/dev/null
  echo "  ✓ nginx restart"
fi
REMOTE

# ---------- 4) 헬스체크 ----------
echo "[deploy] 4/5 헬스체크"
${SSH} bash -se <<'REMOTE'
set -e
echo -n "  grafana       "
docker exec serverstate_grafana_prod wget -qO- http://localhost:3000/api/health | grep -o '"database":"ok"' && echo "" || echo "FAIL"
echo -n "  prometheus    "
docker exec serverstate_prometheus_prod wget -qO- http://localhost:9090/-/healthy
echo -n "  alertmanager  "
docker exec serverstate_alertmanager_prod wget -qO- http://localhost:9093/-/healthy
echo "  targets:"
docker exec serverstate_prometheus_prod wget -qO- 'http://localhost:9090/api/v1/targets?state=active' \
  | python3 -c '
import json, sys
for t in json.load(sys.stdin)["data"]["activeTargets"]:
    print(f"    {t[\"labels\"][\"job\"]:12s} {t[\"health\"]}")
'
REMOTE

# ---------- 5) 외부 도메인 검증 ----------
echo "[deploy] 5/5 외부 도메인 검증"
if curl -fsSL -o /dev/null -w "  https://serverstate.ghmate.com/api/health → %{http_code}\n" --max-time 10 https://serverstate.ghmate.com/api/health; then
  echo "[deploy] ✅ 완료"
else
  echo "[deploy] ⚠️ 외부 접근 실패. Cloudflare/DNS는 별도 점검 필요."
fi
