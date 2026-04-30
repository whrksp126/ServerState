---
description: ServerState 변경사항을 홈서버에 배포 (push → 홈서버 pull → 재기동 → nginx 동기화 → 헬스체크)
allowed-tools: Bash
argument-hint: [--restart]
---

`scripts/deploy.sh $ARGUMENTS`를 실행하고, 출력 그대로 사용자에게 보여줘.

배포 후:
- 5단계가 모두 ✅로 끝났으면 한 줄로 "배포 성공" 보고
- 어느 단계에서 실패했으면 그 단계 직전까지의 로그를 보여주고 어디서 막혔는지 한 줄 진단
- "uncommitted 변경 있음" 이라고 멈췄으면 사용자에게 "먼저 커밋해야 한다"고 알리고 `git status`만 보여줘 (대신 커밋해주지 말 것 — 사용자가 의도하지 않은 파일이 섞일 수 있음)

자주 쓰이는 옵션:
- `--restart`: 코드 변경이 없을 때도 컨테이너 강제 재기동
