---
name: add-alert-rule
description: Add or modify a Prometheus alert rule and validate it before reload
---

# 알림 룰 추가/수정

## 언제 사용하는가
사용자가 "알림 추가", "알림 룰 만들어줘", "임계값 바꿔줘" 같은 요청을 했을 때.

## 절차

1. **룰 파일 편집**: `prometheus/rules/alerts.yml`
   - 기존 그룹(`host`, `service`)에 추가하거나 새 그룹을 만든다
   - PromQL 표현식, `for:`(지속 시간), `labels.severity`, `annotations.summary/description` 채운다
   - `severity`는 `warning` 또는 `critical`만 사용 (Alertmanager 라우팅과 일관)

2. **검증** (PostToolUse 훅이 자동 실행하지만, 수동 확인하려면):
   ```bash
   docker run --rm --entrypoint promtool -v "$(pwd)/prometheus":/etc/prometheus \
     prom/prometheus:v2.54.1 check rules /etc/prometheus/rules/alerts.yml
   ```

3. **반영** (실행 중이면 reload, 아니면 다음 기동 시 자동 적용):
   ```bash
   curl -X POST http://localhost:${PROMETHEUS_HOST_PORT:-9090}/-/reload
   ```

4. **확인**: `http://localhost:9090/alerts` 에서 새 룰이 보이는지

## 룰 작성 예시

```yaml
- alert: HighDiskIO
  expr: rate(node_disk_io_time_seconds_total[5m]) > 0.9
  for: 10m
  labels:
    severity: warning
  annotations:
    summary: "Disk IO saturation on {{ $labels.instance }}"
    description: "Device {{ $labels.device }} busy >90% for 10 minutes."
```

## 주의

- `for:`를 너무 짧게 잡으면 알림 폭주. 기본 5m 이상 권장
- 동일 alertname이 두 그룹에 있으면 양쪽 모두 발사됨
- 룰을 추가했다고 자동으로 알림이 가는 건 아니다. Alertmanager `receivers` 설정이 별도로 필요
