# ServerState

홈서버(Ubuntu, Docker 기반)에서 돌아가는 모든 컨테이너의 자원 사용량과
호스트 자원(CPU, RAM, 디스크, 네트워크, 온도, GPU)을 한 화면에서 보는 모니터링 시스템.

- **로컬(맥북)**: `docker compose --env-file .env.local up -d`로 검증
- **홈서버**: `git pull` → `.env.dev` 작성 → `docker compose --env-file .env.dev up -d`
- **외부 접근**: `serverstate.<도메인>` (Cloudflare CNAME → 홈서버 reverse proxy → Grafana)

## 구성

| 컨테이너 | 역할 | 기본 포트(호스트) |
|---|---|---|
| Prometheus | 메트릭 수집/저장 (retention 15일) | `9090` |
| Grafana | 대시보드/웹 UI | `3000` |
| node-exporter | 호스트 메트릭(CPU/RAM/디스크/네트/온도) | `9100` (host network) |
| cAdvisor | 컨테이너별 리소스 사용량 | `8080` |
| Alertmanager | 알림 라우팅 (현재 receiver=null) | `9093` |

## 환경변수

`.env.local`(로컬 맥북)과 `.env.dev`(홈서버)는 **둘 다 git에 커밋되지 않음**.
환경마다 직접 작성해야 함. 변수 의미는 아래 표 참조.

| 변수 | 기본값 | 설명 |
|---|---|---|
| `GRAFANA_ADMIN_USER` | `admin` | Grafana 관리자 ID |
| `GRAFANA_ADMIN_PW` | `admin` | Grafana 관리자 비밀번호 (반드시 변경) |
| `GRAFANA_HOST_PORT` | `3000` | Grafana 호스트 노출 포트 |
| `GRAFANA_ROOT_URL` | `http://localhost:3000` | 외부 접속 URL (운영 시 도메인) |
| `PROMETHEUS_HOST_PORT` | `9090` | Prometheus 호스트 노출 포트 |
| `PROMETHEUS_RETENTION` | `15d` | 메트릭 보관 기간 |
| `ALERTMANAGER_HOST_PORT` | `9093` | Alertmanager 호스트 노출 포트 |
| `CADVISOR_HOST_PORT` | `8080` | cAdvisor 호스트 노출 포트 |

### `.env.local` 예시 (로컬 맥북 검증용)
```env
GRAFANA_ADMIN_USER=admin
GRAFANA_ADMIN_PW=changeme
GRAFANA_HOST_PORT=3000
GRAFANA_ROOT_URL=http://localhost:3000
PROMETHEUS_HOST_PORT=9090
PROMETHEUS_RETENTION=15d
ALERTMANAGER_HOST_PORT=9093
CADVISOR_HOST_PORT=8080
```

### `.env.dev` 예시 (홈서버 운영용 — ghmate 서버 패턴)
홈서버는 `docker-compose.prod.yml` override가 적용되어 **모든 호스트 포트가 제거**됨.
외부 노출은 글로벌 `nginx_proxy`(포트 80)만 담당. 따라서 `*_HOST_PORT` 변수는 사용되지 않음.
```env
GRAFANA_ADMIN_USER=admin
GRAFANA_ADMIN_PW=<강력한_비밀번호>
GRAFANA_ROOT_URL=https://serverstate.ghmate.com
PROMETHEUS_RETENTION=15d
```

## 실행

### 로컬 (맥북에서 개발/검증)
```bash
bash scripts/up.sh local        # 기동 → http://localhost:3600
bash scripts/down.sh local      # 중지
```

### 배포 (로컬에서 한 줄로 홈서버까지)
```bash
bash scripts/deploy.sh          # uncommitted 체크 → push → 홈서버 pull/up/nginx 동기화 → 헬스체크
bash scripts/deploy.sh --restart # 코드 변경 없을 때도 컨테이너 강제 재기동
```

### 홈서버 상태/로그 (로컬에서 SSH로)
```bash
bash scripts/status.sh                  # 컨테이너/타겟/알림/자원 한 줄 요약
bash scripts/logs.sh grafana            # 마지막 50줄
bash scripts/logs.sh grafana 200        # 마지막 200줄
bash scripts/logs.sh prometheus -f      # follow (Ctrl+C로 종료)
```

### Claude Code 슬래시 커맨드 (위와 동일한 동작)
| 명령 | 동작 |
|---|---|
| `/local-up`, `/local-down` | 로컬 기동/중지 |
| `/deploy [--restart]` | 홈서버 배포 |
| `/status` | 홈서버 상태 |
| `/logs <svc> [N\|-f]` | 홈서버 로그 |

## 접속

| 서비스 | URL (로컬) |
|---|---|
| Grafana | http://localhost:3000 |
| Prometheus | http://localhost:9090 |
| Alertmanager | http://localhost:9093 |
| cAdvisor | http://localhost:8080 |

Grafana 사이드바 → Dashboards → "Node Exporter Full" / "Docker Container & Host Metrics"가 자동 등록되어 있음.

## 알림 룰 (기본값)

| 룰 | 조건 |
|---|---|
| HighCPU | CPU > 80% (5m) |
| HighMemory | Memory > 85% (5m) |
| HighDisk | Disk > 85% (즉시) |
| HighCPUTemp | hwmon temp > 80℃ (2m, Linux 한정) |
| ServiceDown | scrape target down (5m) |

> 현재 Alertmanager receiver는 `null`(외부 전송 없음). 채널(이메일/디스코드/슬랙)
> 결정 후 `alertmanager/alertmanager.yml`의 `receivers`만 갱신하면 활성화.

## 홈서버 배포 시 사전 점검

기존 도커 프로젝트들과 호스트 포트가 겹치지 않는지 반드시 확인:

```bash
# 우리가 쓰려는 포트가 비어있는지
sudo ss -tlnp | grep -E ':(3000|9090|9093|9100|8080)\b' || echo "충돌 없음"
# 현재 도는 컨테이너의 포트 매핑
docker ps --format 'table {{.Names}}\t{{.Ports}}'
# reverse proxy 식별
docker ps --format '{{.Names}}: {{.Image}}' | grep -iE 'nginx|traefik|caddy|proxy'
# GPU 종류
lspci | grep -iE 'vga|3d|display'
# CPU 온도 센서 가용 여부
ls /sys/class/hwmon/
```

충돌 시 `.env.dev`에서 해당 포트 변수 변경 후 reverse proxy upstream도 같이 갱신.
자세한 절차는 `.claude/skills/deploy-to-homeserver.md` 참조.

## 외부 도메인 연결 (ghmate 서버 기준)

1. Cloudflare DNS에 `serverstate.ghmate.com` CNAME → `ghmate.iptime.org` (Proxy ON)
2. `deploy/serverstate.conf`를 `/srv/nginx-proxy/conf.d/serverstate.conf`로 복사
3. `docker exec nginx_proxy nginx -s reload`
4. `https://serverstate.ghmate.com` 접속 → Grafana 로그인

흐름: Cloudflare(HTTPS) → 공유기 → `nginx_proxy:80` → `serverstate_grafana_prod:3000`

## 폴더 구조

```
ServerState/
├── docker-compose.yml          # 베이스 (로컬 맥북용 호스트 포트 노출)
├── docker-compose.prod.yml     # 홈서버 override (nginx_proxy join, 포트 제거)
├── deploy/serverstate.conf     # /srv/nginx-proxy/conf.d/ 에 복사할 nginx 설정
├── prometheus/
│   ├── prometheus.yml          # scrape jobs
│   └── rules/alerts.yml        # 알림 룰
├── alertmanager/alertmanager.yml
├── grafana/provisioning/
│   ├── datasources/prometheus.yml
│   └── dashboards/             # JSON 대시보드 자동 등록
├── scripts/
│   ├── up.sh, down.sh          # 인자 local | dev
│   ├── deploy.sh               # 홈서버 자동 배포
│   ├── status.sh               # 홈서버 상태
│   └── logs.sh                 # 홈서버 컨테이너 로그
├── .claude/
│   ├── settings.json           # PostToolUse 훅 + 권한
│   ├── commands/               # 슬래시 커맨드 (/deploy, /status, /logs, /local-up, /local-down)
│   └── skills/                 # 자연어 트리거 작업 가이드
└── README.md, CLAUDE.md
```

## 향후 작업

- [ ] 알림 채널(이메일 SMTP / Discord / Slack) 결정 후 Alertmanager receiver 활성화
- [ ] AMD GPU exporter 추가 (홈서버 Ryzen 내장 Vega 그래픽 — `amdgpu_exporter` 또는 hwmon 기반)
- [ ] Cloudflare Access로 Grafana 이메일 인증 게이트
- [ ] Loki + Promtail 로그 수집 추가
- [ ] `prometheus_data`, `grafana_data` 정기 백업
