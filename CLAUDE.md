# ServerState — Claude Code 작업 지침

홈서버용 Docker 기반 모니터링 시스템(Prometheus + Grafana + node-exporter + cAdvisor + Alertmanager).

## 프로젝트 목표

홈서버에서 도는 모든 Docker 컨테이너의 자원 점유와 호스트 자원 여유를
한 화면에서 보고, 임계값 초과 시 알림을 받는다.

## 워크플로우 (불변)

### 일상 개발 — 슬래시 커맨드 한 줄
| 명령 | 동작 |
|---|---|
| `/local-up` | 로컬 맥북에 ServerState 기동 (`scripts/up.sh local`) |
| `/local-down` | 로컬 중지 |
| `/deploy` | uncommitted 체크 → push → 홈서버 pull/up/nginx 동기화 → 헬스체크 |
| `/deploy --restart` | 코드 변경 없을 때도 컨테이너 강제 재기동 |
| `/status` | 홈서버 컨테이너/타겟/알림/CPU·메모리·디스크·온도 한눈에 |
| `/logs <svc> [N \| -f]` | 홈서버 컨테이너 로그 (예: `/logs grafana 200`, `/logs prometheus -f`) |

### 흐름 요약
1. 로컬에서 변경 → `/local-up`으로 검증 → http://localhost:3600 에서 확인
2. `git commit`
3. `/deploy` 한 줄로 홈서버 반영
4. `/status`로 정상 동작 확인

### 최초 1회만 (이미 완료)
- 홈서버에 `/srv/projects/serverstate/` clone, `.env.dev` 작성
- `/srv/nginx-proxy/conf.d/serverstate.conf` 배치, nginx_proxy 재시작
- Cloudflare DNS CNAME `serverstate` → `ghmate.iptime.org`

## 절대 규칙

- **`.env.local`, `.env.dev`는 절대 git에 커밋하지 않는다.** 이미 `.gitignore`에 포함.
- **호스트 포트는 hardcode 금지.** docker-compose.yml의 ports는 모두 `${VAR:-default}` 형식.
- **다른 도커 프로젝트의 포트와 충돌하면 안 된다.** 변경은 `.env.dev`에서.
- **node-exporter는 `network_mode: host` 유지.** 호스트 메트릭 정확도가 중요. 9100 충돌 시 충돌 측을 검토.

## 컨테이너 역할

| 컨테이너 | 역할 |
|---|---|
| `prometheus` | 메트릭 수집/저장. retention은 `PROMETHEUS_RETENTION`(기본 15일) |
| `grafana` | 대시보드/웹 UI. 자체 로그인 |
| `node-exporter` | 호스트 OS 메트릭 (host network, pid host) |
| `cadvisor` | Docker 컨테이너별 리소스 사용량 (`/var/run/docker.sock` 읽기 전용) |
| `alertmanager` | 알림 라우팅. 현재 receiver=null(외부 전송 안 함) |

## 작업 유형별 가이드

| 하고 싶은 일 | 참고할 skill |
|---|---|
| 새 알림 룰 추가/수정 | `.claude/skills/add-alert-rule.md` |
| 새 Grafana 대시보드 추가 | `.claude/skills/add-dashboard.md` |
| 새 exporter(GPU 등) 추가 | `.claude/skills/add-exporter.md` |
| 홈서버에 배포 | `.claude/skills/deploy-to-homeserver.md` |

## 변경 시 자동 검증 (settings.json hooks)

`.claude/settings.json`에 PostToolUse 훅이 걸려 있어 다음 파일을 편집하면 자동 검증된다:

- `docker-compose.yml` → `docker compose config`
- `prometheus/prometheus.yml`, `prometheus/rules/*.yml` → `promtool check config|rules`
- `alertmanager/alertmanager.yml` → `amtool check-config`

훅이 실패하면 커밋/배포하지 말고 실패 메시지를 따라 수정한다.

## 환경변수

전체 변수 목록과 예시 값은 `README.md`의 "환경변수" 표 참조.
새 변수를 추가할 때는 docker-compose.yml에 `${VAR:-default}` 형태로 노출하고 README 표에 1줄 추가.

## 외부 도메인

- 진입점: `https://serverstate.<도메인>`
- 흐름: Cloudflare(Proxy) → iptime DDNS(`ghmate.iptime.org`) → 홈서버 reverse proxy → Grafana
- 다른 기존 서비스(`heyvoca-back`, `dev-openday` 등)와 동일 패턴

## 절대 하지 말 것

- 알림 룰을 새로 추가할 때 `promtool check rules` 없이 commit
- `.env.local` / `.env.dev`를 README/CLAUDE.md에 예시로 박아넣기 (변수 표만 README에)
- node-exporter의 `network_mode: host` 제거 (정확도 손실)
- cadvisor의 `/var/run/docker.sock` 마운트를 read-write로 (보안)
- 기존 서비스가 쓰는 호스트 포트와 겹치는 매핑

## 자주 쓰는 명령 (셸에서 직접)

```bash
# 로컬
bash scripts/up.sh local
bash scripts/down.sh local
docker compose --env-file .env.local logs -f prometheus
curl -X POST http://localhost:9090/-/reload     # 룰 리로드

# 홈서버 자동화
bash scripts/deploy.sh                          # 표준 배포
bash scripts/deploy.sh --restart                # 강제 재기동
bash scripts/status.sh                          # 상태
bash scripts/logs.sh grafana 200                # 마지막 200줄
bash scripts/logs.sh prometheus -f              # follow

# 검증 (로컬에서 hooks가 자동 실행하지만 수동도 가능)
docker run --rm --entrypoint promtool -v "$(pwd)/prometheus":/etc/prometheus prom/prometheus:v2.54.1 check config /etc/prometheus/prometheus.yml
docker run --rm --entrypoint amtool -v "$(pwd)/alertmanager":/etc/alertmanager prom/alertmanager:v0.27.0 check-config /etc/alertmanager/alertmanager.yml
```

## 슬래시 커맨드 (Claude Code 내부)
`/deploy`, `/status`, `/logs <svc> [N|-f]`, `/local-up`, `/local-down` — 위 셸 명령을 한 줄로 트리거.
