---
description: 홈서버 ServerState 컨테이너 로그 보기
allowed-tools: Bash
argument-hint: <service> [tail-lines | -f]
---

`bash scripts/logs.sh $ARGUMENTS`를 실행해서 로그를 보여줘.

- service는 prometheus | grafana | alertmanager | cadvisor | node-exporter
- 인자 없이 호출되면 사용법 안내만 하고 멈춰
- `-f` 옵션은 follow 모드라 사용자가 Ctrl+C로 끊어야 함 — 절대 자동으로 끊지 마
- 에러 라인(level=error 또는 ERROR/ERR)이 보이면 출력 끝에 "에러 N건 감지" 한 줄 짧게 추가
