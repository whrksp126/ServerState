---
name: deploy-to-homeserver
description: Deploy ServerState to the home server — pre-flight checks, port collision handling, reverse proxy wiring
---

# 홈서버 배포 절차

## 언제 사용하는가
사용자가 "홈서버에 배포", "서버에 올려줘" 등.

## 사전 점검 (SSH 접속 후)

```bash
# (a) 호스트 포트 충돌 확인
sudo ss -tlnp | grep -E ':(3000|9090|9093|9100|8080)\b' || echo "충돌 없음"

# (b) 현재 컨테이너 포트 매핑
docker ps --format 'table {{.Names}}\t{{.Ports}}'

# (c) reverse proxy 식별
docker ps --format '{{.Names}}: {{.Image}}' | grep -iE 'nginx|traefik|caddy|proxy'

# (d) reverse proxy 설정 위치 (식별된 컨테이너명으로)
docker inspect <proxy_name> --format '{{range .Mounts}}{{.Source}} -> {{.Destination}}{{"\n"}}{{end}}'

# (e) GPU 종류
lspci | grep -iE 'vga|3d|display'

# (f) hwmon 가용성
ls /sys/class/hwmon/ 2>/dev/null && echo "OK" || echo "센서 없음"
```

결과를 사용자에게 공유하고 충돌 항목 결정.

## 충돌 시 대응

| 포트 | 대응 |
|---|---|
| 8080 (cAdvisor) | `.env.dev`에서 `CADVISOR_HOST_PORT=18080` 등 |
| 3000 (Grafana) | `GRAFANA_HOST_PORT=3300` 등 + reverse proxy upstream도 갱신 |
| 9090/9093 | 변수 변경 |
| 9100 (node-exporter) | host network라 변경 불가. 충돌 측 점검 필요 |

## 배포 순서

```bash
# 1) 코드 받기 (최초)
cd ~/services && git clone https://github.com/<user>/ServerState.git
cd ServerState

# 2) .env.dev 작성 (사전 점검 결과 반영)
cat > .env.dev <<'EOF'
GRAFANA_ADMIN_USER=admin
GRAFANA_ADMIN_PW=<강력한_비밀번호>
GRAFANA_HOST_PORT=3000
GRAFANA_ROOT_URL=https://serverstate.<도메인>
PROMETHEUS_HOST_PORT=9090
PROMETHEUS_RETENTION=15d
ALERTMANAGER_HOST_PORT=9093
CADVISOR_HOST_PORT=8080
EOF
chmod 600 .env.dev

# 3) compose 검증 + 기동
docker compose --env-file .env.dev config -q
bash scripts/up.sh dev

# 4) 헬스체크
docker compose --env-file .env.dev ps
curl -fsSL http://localhost:${GRAFANA_HOST_PORT:-3000}/api/health
curl -fsSL http://localhost:${PROMETHEUS_HOST_PORT:-9090}/-/healthy
```

## reverse proxy 라우팅 (식별된 종류에 맞춰)

### nginx (호스트 또는 컨테이너)
```nginx
server {
    listen 80;
    server_name serverstate.<도메인>;
    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```
적용: `nginx -t && nginx -s reload` (호스트면) 또는 컨테이너 재시작

### nginx-proxy-manager
GUI → "Proxy Hosts" → "Add Proxy Host"
- Domain: `serverstate.<도메인>`
- Forward Hostname: `host.docker.internal` 또는 호스트 IP
- Forward Port: `${GRAFANA_HOST_PORT}`
- Block Common Exploits: ON

### Traefik (라벨)
ServerState의 `grafana` 서비스에 라벨 추가 후 Traefik 네트워크에 join.
필요 시 별도 PR로 진행.

## Cloudflare DNS

기존 패턴 그대로:
- Type: `CNAME`
- Name: `serverstate`
- Target: `ghmate.iptime.org`
- Proxy status: Proxied

## 검증

`https://serverstate.<도메인>` 접속 → Grafana 로그인 화면 → 환경변수의 admin/PW로 진입 → 대시보드 노출 확인.

## 업데이트(이후)

```bash
cd ~/services/ServerState
git pull
docker compose --env-file .env.dev pull
bash scripts/up.sh dev
```
