---
name: deploy-to-homeserver
description: Deploy ServerState to ghmate home server following the GHMATE_SERVER_GUIDE pattern
---

# 홈서버(ghmate) 배포 절차

## 언제 사용하는가
사용자가 "홈서버에 배포", "서버에 올려줘" 등.

## 서버 컨벤션 (반드시 따른다)
- 모든 동적 프로젝트: `/srv/projects/<name>/`
- 글로벌 nginx: `/srv/nginx-proxy/` (컨테이너 `nginx_proxy`, 포트 80 단일 진입점)
- 도메인 라우팅: `/srv/nginx-proxy/conf.d/<project>.conf` 추가 후 nginx reload
- **호스트 포트 노출 금지** (글로벌 nginx가 80 담당)
- 컨테이너 네이밍: `<project>_<service>_<env>` (예: `serverstate_grafana_prod`)
- 외부 통신 컨테이너만 `nginx_proxy` 네트워크에 join (`external: true`)
- 자세한 건 `~/other/project/GHMATE_SERVER_GUIDE.md` 참조

## SSH 접속

```bash
ssh -i ~/.ssh/ghmate_server -p 222 ghmate@ghmate.iptime.org
```

## 배포 절차

### 1) 사전 점검 (충돌 검사)
```bash
ssh -i ~/.ssh/ghmate_server -p 222 ghmate@ghmate.iptime.org \
  'sudo ss -tlnp | grep -E ":(3000|9090|9093|9100|8080)\b" || echo "충돌 없음"; docker ps --format "table {{.Names}}\t{{.Ports}}"'
```

### 2) 코드 받기 (최초 한 번)
```bash
ssh -i ~/.ssh/ghmate_server -p 222 ghmate@ghmate.iptime.org \
  'mkdir -p /srv/projects/serverstate && cd /srv/projects/serverstate && git clone https://github.com/whrksp126/ServerState.git .'
```

### 3) `.env.dev` 작성 (서버에서)
```bash
ssh -i ~/.ssh/ghmate_server -p 222 ghmate@ghmate.iptime.org \
  'cat > /srv/projects/serverstate/.env.dev <<EOF
GRAFANA_ADMIN_USER=admin
GRAFANA_ADMIN_PW=<강력한_비밀번호>
GRAFANA_ROOT_URL=https://serverstate.ghmate.com
PROMETHEUS_RETENTION=15d
EOF
chmod 600 /srv/projects/serverstate/.env.dev'
```

### 4) 기동
```bash
ssh -i ~/.ssh/ghmate_server -p 222 ghmate@ghmate.iptime.org \
  'cd /srv/projects/serverstate && bash scripts/up.sh dev'
```
> `scripts/up.sh dev`는 `docker-compose.yml + docker-compose.prod.yml` + `--profile linux` 자동 적용
> = node-exporter 활성화, 호스트 포트 제거, nginx_proxy 네트워크 join, 컨테이너 네이밍 `_prod`

### 5) nginx 라우팅 추가
```bash
ssh -i ~/.ssh/ghmate_server -p 222 ghmate@ghmate.iptime.org \
  'cp /srv/projects/serverstate/deploy/serverstate.conf /srv/nginx-proxy/conf.d/ && docker exec nginx_proxy nginx -t && docker restart nginx_proxy'
```
> ⚠️ `nginx -s reload`(graceful) 대신 **`docker restart nginx_proxy`** 사용. graceful reload는 새 server 블록 SSL 매칭이 active connection에서 안 잡혀 502가 발생할 수 있음 (실측).
>
> ⚠️ Cloudflare가 Proxied 모드에서 origin에 HTTPS(443)로 연결하므로, conf에 `listen 443 ssl;` + `ssl_certificate /etc/nginx/certs/cloudflare_chain.crt;` + `ssl_certificate_key /etc/nginx/certs/cloudflare.key;`가 반드시 있어야 함. 80만 listen하면 default_server에 빨려들어가 502.

### 6) Cloudflare DNS 등록 (사용자 직접)
- Type: `CNAME`
- Name: `serverstate`
- Target: `ghmate.iptime.org`
- Proxy: ON (Proxied)

### 7) 검증
```bash
# 컨테이너 내부 헬스체크
ssh -i ~/.ssh/ghmate_server -p 222 ghmate@ghmate.iptime.org \
  'docker exec serverstate_grafana_prod wget -qO- http://localhost:3000/api/health'

# nginx 경유 (ghmate.com 호스트 헤더로 시뮬레이션)
ssh -i ~/.ssh/ghmate_server -p 222 ghmate@ghmate.iptime.org \
  'curl -fsSL -H "Host: serverstate.ghmate.com" http://localhost/api/health'

# 외부 도메인 (DNS 전파 후)
curl -fsSL https://serverstate.ghmate.com/api/health
```

## 업데이트 (이후 변경 사항 반영)
```bash
ssh -i ~/.ssh/ghmate_server -p 222 ghmate@ghmate.iptime.org \
  'cd /srv/projects/serverstate && git pull && bash scripts/up.sh dev'
```

## 주의

- **`.env.dev`는 서버에서 직접 작성**하고 git에 커밋하지 않는다 (`.gitignore`에 포함)
- Grafana 비밀번호는 **첫 로그인 후 반드시 변경** (또는 `.env.dev`에 강력한 값으로 설정)
- nginx conf 변경 후 `docker exec nginx_proxy nginx -t`로 문법 검사 후 reload
- nginx_proxy 네트워크는 `external: true`로 참조만 함 (생성/삭제 금지)
