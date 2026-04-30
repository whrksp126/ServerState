---
name: deploy-to-homeserver
description: ServerState를 ghmate 홈서버에 배포 — 일반적으로 scripts/deploy.sh 한 줄이면 끝
---

# 홈서버(ghmate) 배포

## 언제 사용하는가
사용자가 "배포", "서버에 올려줘", "푸시 해줘" 등.

## 90%의 경우 — 한 줄

```bash
bash scripts/deploy.sh
```

또는 슬래시 커맨드 `/deploy`. 다음을 자동으로 한다:
1. 로컬 사전 체크 (uncommitted 없음 / branch=main)
2. `git push origin main`
3. 홈서버 SSH → `git pull` → 변경 감지
4. compose/prom/grafana/alertmanager 변경 시 `scripts/up.sh dev` 자동 실행
5. `deploy/serverstate.conf` 변경 시 `/srv/nginx-proxy/conf.d/`에 복사 + `docker restart nginx_proxy`
6. 헬스체크 (grafana/prometheus/alertmanager + targets)
7. 외부 도메인 검증 (`https://serverstate.ghmate.com/api/health`)

코드 변경 없이도 컨테이너만 재기동하고 싶으면 `bash scripts/deploy.sh --restart`.

## 처음 한 번만 — 초기 셋업 (이미 완료된 상태)

이 단계는 한 번만 하면 됨. 두 번 할 일 거의 없음. 기록 보존용.

### 서버 컨벤션
- 동적 프로젝트: `/srv/projects/<name>/` (이 프로젝트는 `/srv/projects/serverstate/`)
- 글로벌 nginx: 컨테이너 `nginx_proxy`, 80/443 단일 진입점
- 컨테이너 네이밍: `<project>_<service>_<env>` (예: `serverstate_grafana_prod`)
- 호스트 포트 노출 금지 — 외부 통신은 `nginx_proxy` 네트워크(`external: true`) join
- 자세한 컨벤션: `~/other/project/GHMATE_SERVER_GUIDE.md`

### SSH
```
ssh -i ~/.ssh/ghmate_server -p 222 ghmate@ghmate.iptime.org
```

### 최초 셋업 절차
```bash
# 1) 코드 받기
ssh -i ~/.ssh/ghmate_server -p 222 ghmate@ghmate.iptime.org \
  'mkdir -p /srv/projects/serverstate && cd /srv/projects/serverstate && git clone https://github.com/whrksp126/ServerState.git .'

# 2) .env.dev 작성 (서버에서 직접)
ssh -i ~/.ssh/ghmate_server -p 222 ghmate@ghmate.iptime.org \
  "cat > /srv/projects/serverstate/.env.dev <<EOF
GRAFANA_ADMIN_USER=ghmate
GRAFANA_ADMIN_PW=<강한_비밀번호>
GRAFANA_ROOT_URL=https://serverstate.ghmate.com
PROMETHEUS_RETENTION=15d
EOF
chmod 600 /srv/projects/serverstate/.env.dev"

# 3) 기동
ssh -i ~/.ssh/ghmate_server -p 222 ghmate@ghmate.iptime.org \
  'cd /srv/projects/serverstate && bash scripts/up.sh dev'

# 4) nginx 라우팅
ssh -i ~/.ssh/ghmate_server -p 222 ghmate@ghmate.iptime.org \
  'cp /srv/projects/serverstate/deploy/serverstate.conf /srv/nginx-proxy/conf.d/ && docker exec nginx_proxy nginx -t && docker restart nginx_proxy'

# 5) Cloudflare DNS — 사용자 직접 (CNAME serverstate → ghmate.iptime.org, Proxied)
```

### ⚠️ 알아두어야 할 함정
- **nginx 갱신은 `nginx -s reload`(graceful)가 아니라 `docker restart nginx_proxy`** — graceful은 새 server 블록의 SSL 매칭이 active connection에 안 잡혀 502 발생 (실측).
- **Cloudflare가 origin에 HTTPS(443)로 연결**하므로 nginx conf에 `listen 443 ssl;` + `ssl_certificate /etc/nginx/certs/cloudflare_chain.crt;` + `ssl_certificate_key /etc/nginx/certs/cloudflare.key;`가 반드시 있어야 한다. 없으면 default_server에 빨려들어가 502.
- **`.env.dev`는 서버에서만, gitignore**. 비번 변경은 UI 또는 `grafana cli admin reset-admin-password`로. username 변경은 SQLite 직접 (login 변경은 grafana CLI 미지원):
  ```bash
  docker exec --user root serverstate_grafana_prod apk add --no-cache sqlite
  docker exec serverstate_grafana_prod sqlite3 /var/lib/grafana/grafana.db "UPDATE user SET login='새이름' WHERE id=1;"
  ```
