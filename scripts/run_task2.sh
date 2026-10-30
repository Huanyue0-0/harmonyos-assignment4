#!/usr/bin/env bash
# Assignment 4 · 任务二：安全扫描 → 修复 → 复测 的证据采集
#
# 做的事：在真实的 Terminal 窗口里依次执行扫描/构建命令，
# 每次等命令跑完后按窗口截图（CGWindowID，不受遮挡影响），并把终端输出落到 logs/task2/。
#
# 用法：bash scripts/run_task2.sh
# 环境变量：WAIT_MAX 单阶段最长等待秒数（默认 300）
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/screenshots/task2"
LOGS="$ROOT/logs/task2"
SHOT="$ROOT/scripts/shot.sh"
WAIT_MAX="${WAIT_MAX:-300}"
mkdir -p "$OUT" "$LOGS"

stage() {
  local file="$1" dir="$2" cmd="$3"
  local log="$LOGS/${file%.png}.md"
  local tmp
  tmp="$(mktemp -t a4stage)"
  {
    echo "cd '$dir'"
    echo "clear"
    echo "($cmd) 2>&1 | tee '$log'"
  } > "$tmp"
  osascript <<AS >/dev/null
tell application "Terminal"
  activate
  do script "bash '$tmp'"
  set bounds of front window to {40, 40, 1720, 1000}
end tell
AS
  # 等命令结束（Terminal 窗口 busy=false），最多 WAIT_MAX 秒
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
  echo "已采集: screenshots/task2/$file + logs/task2/${file%.png}.md"
}

SCAN="$ROOT/task2/security/scan.sh"

stage "02-CodeLinter-修复前.png" "$ROOT/task2-vulnerable" "bash \"$SCAN\" linter \"$ROOT/task2-vulnerable\""
stage "03-Semgrep-修复前.png"     "$ROOT/task2-vulnerable" "bash \"$SCAN\" semgrep \"$ROOT/task2-vulnerable\""
stage "04-CodeLinter-修复后.png"  "$ROOT/task2" "bash \"$SCAN\" linter \"$ROOT/task2\""
stage "05-Semgrep-修复后.png"     "$ROOT/task2" "bash \"$SCAN\" semgrep \"$ROOT/task2\""
stage "06-构建通过.png" "$ROOT/task2" \
  "DEVECO_SDK_HOME=\"/Applications/DevEco-Studio.app/Contents/sdk\" \"/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw\" assembleHap --mode module -p product=default --no-daemon | tail -12"

echo "全部阶段完成。"
