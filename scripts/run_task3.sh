#!/usr/bin/env bash
# Assignment 4 · 任务三：CI 安全门禁 证据采集
#
# 在真实 Terminal 窗口依次执行：
#   01 单独验证新增硬编码 IPv4 规则（3.2）
#   02 漏洞版工程执行 hvigor securityScan（应阻断）
#   03 修复版工程执行 hvigor securityScan（应放行）
# 每次命令结束后按窗口截图，输出同时落 logs/task3/。
#
# 用法：bash scripts/run_task3.sh
# 环境变量：WAIT_MAX 单阶段最长等待秒数（默认 300）
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/screenshots/task3"
LOGS="$ROOT/logs/task3"
SHOT="$ROOT/scripts/shot.sh"
WAIT_MAX="${WAIT_MAX:-300}"
HVIGOR="/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw"
mkdir -p "$OUT" "$LOGS"

stage() {
  local file="$1" dir="$2" cmd="$3"
  local log="$LOGS/${file%.png}.md"
  local tmp
  tmp="$(mktemp -t a4stage)"
  {
    echo "cd '$dir'"
    echo "clear"
    echo "echo '[命令] $cmd'"
    echo "($cmd) 2>&1 | tee '$log'"
  } > "$tmp"
  osascript <<AS >/dev/null
tell application "Terminal"
  activate
  do script "bash '$tmp'"
  set bounds of front window to {40, 40, 1720, 1000}
end tell
AS
  local i=0
  while [ $i -lt "$WAIT_MAX" ]; do
    local busy
    busy="$(osascript -e 'tell application "Terminal" to get busy of front window' 2>/dev/null || echo true)"
    [ "$busy" = "false" ] && break
    sleep 2
    i=$((i + 2))
  done
  sleep 1
  SHOT_QUIET=1 SHOT_APP=Terminal bash "$SHOT" "$OUT/$file" --window || true
  osascript -e 'tell application "Terminal" to close front window saving no' >/dev/null 2>&1 || true
  echo "已采集: screenshots/task3/$file + logs/task3/${file%.png}.md"
}

stage "01-IP规则命中样例.png" "$ROOT" "bash \"$ROOT/scripts/test_ip_rule.sh\""

stage "02-门禁阻断-漏洞版.png" "$ROOT/task2-vulnerable" \
  "set -o pipefail; DEVECO_SDK_HOME=\"/Applications/DevEco-Studio.app/Contents/sdk\" \"$HVIGOR\" securityScan --no-daemon 2>&1 | tail -28; echo \"[hvigor 退出码] \$?\""

stage "03-门禁放行-修复版.png" "$ROOT/task2" \
  "set -o pipefail; DEVECO_SDK_HOME=\"/Applications/DevEco-Studio.app/Contents/sdk\" \"$HVIGOR\" securityScan --no-daemon 2>&1 | tail -10; echo \"[hvigor 退出码] \$?\""

echo "全部阶段完成。"
