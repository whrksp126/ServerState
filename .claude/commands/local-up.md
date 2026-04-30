---
description: 로컬 맥북에서 ServerState 스택 기동 (개발/검증용)
allowed-tools: Bash
---

`bash scripts/up.sh local`을 실행하고 결과를 보여줘.

기동 후:
- `curl -fsSL http://localhost:${GRAFANA_HOST_PORT:-3600}/api/health` 한 번 호출해서 헬스 확인
- 모든 컨테이너가 running이면 접속 URL 한 줄로 안내 (Grafana / Prometheus / Alertmanager)
- macOS에선 node-exporter가 빠지므로 `node` target이 down이어도 정상 — 굳이 강조하지 마
