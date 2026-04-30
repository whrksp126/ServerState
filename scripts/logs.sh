#!/usr/bin/env bash
# 홈서버 ServerState 컨테이너 로그 조회
# 사용:
#   bash scripts/logs.sh grafana          # 마지막 50줄
#   bash scripts/logs.sh grafana 200      # 마지막 200줄
#   bash scripts/logs.sh grafana -f       # follow (Ctrl+C로 종료)
set -euo pipefail

SVC="${1:-}"
ARG="${2:-50}"

if [[ -z "${SVC}" ]]; then
  echo "사용: bash scripts/logs.sh <service> [tail-lines | -f]"
  echo "  service: prometheus | grafana | alertmanager | cadvisor | node-exporter"
  exit 1
fi

# node-exporter 만 하이픈 → 언더스코어 변환
case "${SVC}" in
  node-exporter|node_exporter) CONTAINER="serverstate_node_exporter_prod" ;;
  prometheus|grafana|alertmanager|cadvisor) CONTAINER="serverstate_${SVC}_prod" ;;
  *) echo "알 수 없는 서비스: ${SVC}"; exit 1 ;;
esac

SSH="ssh -i ${HOME}/.ssh/ghmate_server -p 222 ghmate@ghmate.iptime.org"

if [[ "${ARG}" == "-f" ]]; then
  ${SSH} -t "docker logs -f --tail 50 ${CONTAINER}"
else
  ${SSH} "docker logs --tail ${ARG} ${CONTAINER}"
fi
