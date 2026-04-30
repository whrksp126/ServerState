#!/usr/bin/env bash
# 홈서버 ServerState 상태 한눈에 보기
# 사용: bash scripts/status.sh
set -euo pipefail

SSH="ssh -i ${HOME}/.ssh/ghmate_server -p 222 ghmate@ghmate.iptime.org"

${SSH} bash -se <<'REMOTE'
set -e
echo "=== 컨테이너 상태 ==="
docker ps --filter "name=serverstate_" --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'

echo ""
echo "=== 헬스 ==="
echo -n "  grafana      "
docker exec serverstate_grafana_prod wget -qO- http://localhost:3000/api/health 2>/dev/null | grep -q '"ok"' && echo OK || echo FAIL
echo -n "  prometheus   "
docker exec serverstate_prometheus_prod wget -qO- http://localhost:9090/-/healthy 2>/dev/null
echo -n "  alertmanager "
docker exec serverstate_alertmanager_prod wget -qO- http://localhost:9093/-/healthy 2>/dev/null

echo ""
echo "=== Prometheus targets ==="
docker exec serverstate_prometheus_prod wget -qO- 'http://localhost:9090/api/v1/targets?state=active' \
  | python3 -c '
import json, sys
for t in json.load(sys.stdin)["data"]["activeTargets"]:
    job = t["labels"]["job"]
    health = t["health"]
    err = t.get("lastError", "")
    print(f"  {job:12s} {health:6s}  {err}")
'

echo ""
echo "=== firing 알림 ==="
docker exec serverstate_prometheus_prod wget -qO- 'http://localhost:9090/api/v1/alerts' \
  | python3 -c '
import json, sys
data = json.load(sys.stdin)
alerts = data.get("data", {}).get("alerts", [])
firing = [a for a in alerts if a.get("state") == "firing"]
if not firing:
    print("  (없음)")
else:
    for a in firing:
        name = a["labels"].get("alertname", "?")
        sev = a["labels"].get("severity", "?")
        inst = a["labels"].get("instance", "")
        print(f"  [{sev}] {name} {inst}")
'

echo ""
echo "=== 호스트 자원 (현재값) ==="
print_metric() {
  local label="$1"; local query="$2"; local unit="$3"
  local val
  val=$(docker exec serverstate_prometheus_prod wget -qO- "http://localhost:9090/api/v1/query?query=${query}" \
    | python3 -c '
import json, sys
data = json.load(sys.stdin)
r = data["data"]["result"]
if r:
    print("{:.1f}".format(float(r[0]["value"][1])))
else:
    print("N/A")
' 2>/dev/null) || val="N/A"
  printf "  %-12s: %s%s\n" "$label" "$val" "$unit"
}
print_metric "CPU 사용률"  '100-(avg(rate(node_cpu_seconds_total%7Bmode%3D%22idle%22%7D%5B5m%5D))*100)' '%'
print_metric "Memory 사용" '(1-node_memory_MemAvailable_bytes/node_memory_MemTotal_bytes)*100' '%'
print_metric "Disk(/) 사용" '(1-node_filesystem_avail_bytes%7Bmountpoint%3D%22/%22%7D/node_filesystem_size_bytes%7Bmountpoint%3D%22/%22%7D)*100' '%'
print_metric "CPU 평균온도" 'avg(node_hwmon_temp_celsius)' '℃'
REMOTE
