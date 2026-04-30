---
name: add-exporter
description: Add a new Prometheus exporter (e.g. GPU exporter) — compose service + scrape job + dashboard
---

# Exporter 추가 (예: GPU)

## 언제 사용하는가
사용자가 "GPU 모니터링 추가해줘", "X exporter 붙여줘" 등.

## 절차 — GPU 예시

### 1) 홈서버 GPU 종류 확인
```bash
ssh <homeserver> 'lspci | grep -iE "vga|3d|display"'
```
- `NVIDIA` 라벨 → 옵션 A (NVIDIA)
- `AMD/ATI` 라벨 → 옵션 B (AMD)
- 표시 어댑터만(예: Intel 내장) → 보통 모니터링 가치 낮음. 패스

### 2-A) NVIDIA — `nvidia-gpu-exporter`
`docker-compose.yml`에 추가:
```yaml
nvidia-exporter:
  image: utkuozdemir/nvidia_gpu_exporter:1.2.1
  container_name: serverstate-nvidia-exporter
  restart: unless-stopped
  runtime: nvidia
  environment:
    - NVIDIA_VISIBLE_DEVICES=all
  ports:
    - "${NVIDIA_EXPORTER_HOST_PORT:-9835}:9835"
  networks:
    - monitor-net
```
> 홈서버에 `nvidia-container-toolkit` 사전 설치 필요.

### 2-B) AMD — `amdgpu_exporter`
```yaml
amd-exporter:
  image: ghcr.io/joernbrandt/amdgpu_exporter:latest
  container_name: serverstate-amd-exporter
  restart: unless-stopped
  privileged: true
  volumes:
    - /sys:/sys:ro
  ports:
    - "${AMD_EXPORTER_HOST_PORT:-9610}:9610"
  networks:
    - monitor-net
```

### 3) Prometheus scrape job 추가
`prometheus/prometheus.yml`:
```yaml
- job_name: gpu
  static_configs:
    - targets: ["nvidia-exporter:9835"]   # 또는 amd-exporter:9610
```

### 4) 검증 (PostToolUse 훅이 자동 실행)
```bash
bash scripts/up.sh dev          # 또는 local에서 mock 검증
curl http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.job=="gpu")'
```

### 5) Grafana 대시보드
- NVIDIA: Grafana.com #14574 ("NVIDIA GPU")
- AMD: Grafana.com #16562 또는 직접 작성
- `add-dashboard` skill 따라 import

### 6) (선택) 알림 룰 추가
`prometheus/rules/alerts.yml`에 GPU 사용률/온도 임계값 추가. `add-alert-rule` skill 참조.

### 7) README/CLAUDE.md에 새 변수 표 추가
- `NVIDIA_EXPORTER_HOST_PORT` 또는 `AMD_EXPORTER_HOST_PORT`

## 일반화 (다른 exporter 도)
1. compose에 서비스 추가 (호스트 포트는 변수로)
2. `prometheus.yml`에 scrape job 추가
3. 대시보드 import
4. 알림 룰(선택)
5. README 변수 표 갱신
