---
name: add-dashboard
description: Add a new Grafana dashboard via file provisioning
---

# Grafana 대시보드 추가

## 언제 사용하는가
사용자가 "대시보드 추가해줘", "X 대시보드 만들어줘", "Grafana.com에서 대시보드 받아줘" 등.

## 두 가지 방법

### A) Grafana.com 공식 대시보드 import (권장, 빠름)
1. https://grafana.com/grafana/dashboards/ 에서 대시보드 ID와 최신 revision 확인
2. JSON 다운로드:
   ```bash
   cd grafana/provisioning/dashboards
   curl -fsSL "https://grafana.com/api/dashboards/<ID>/revisions/<REV>/download" -o <name>.json
   ```
3. JSON 안에 `${DS_PROMETHEUS}` 같은 datasource 변수가 있으면 우리 datasource UID(`prometheus`)로 치환:
   ```bash
   sed -i '' 's/${DS_PROMETHEUS}/prometheus/g' <name>.json   # macOS
   sed -i    's/${DS_PROMETHEUS}/prometheus/g' <name>.json   # Linux
   ```
4. Grafana 재시작 또는 30초 대기 (file provider `updateIntervalSeconds: 30`)

### B) 직접 만든 JSON 추가
1. Grafana UI에서 대시보드 만들고 "Share → Export → Save to file"로 JSON 추출
2. `grafana/provisioning/dashboards/<name>.json`로 저장
3. JSON 최상위의 `"id": null`, `"uid": "<고유값>"` 확인 (uid 충돌 시 import 실패)

## 검증

```bash
docker compose --env-file .env.local restart grafana
# 또는 30초 대기
curl -u admin:${GRAFANA_ADMIN_PW} http://localhost:${GRAFANA_HOST_PORT:-3000}/api/search?type=dash-db | jq '.[].title'
```

## 주의

- 같은 `uid`가 두 JSON에 있으면 둘 중 하나만 등록됨
- `dashboards.yml`의 `path: /etc/grafana/provisioning/dashboards`는 **컨테이너 내부 경로**. 호스트의 `grafana/provisioning/dashboards/`가 마운트됨
- Grafana 11.x 버전 표기와 JSON `schemaVersion` 호환성 주의 (오래된 JSON은 import 시 경고)
