#!/usr/bin/env bash
# 任务二：鸿蒙工程静态安全扫描（Code Linter + Semgrep）
#
# 用法：
#   bash security/scan.sh semgrep <工程目录>    # 只跑 Semgrep（arkts-security.yml）
#   bash security/scan.sh linter  <工程目录>    # 只跑 DevEco Code Linter（@ohos/security）
#   bash security/scan.sh all     <工程目录>    # 两者都跑，并汇总
#
# 说明：
#   1. Semgrep 不认识 .ets 扩展名，脚本会把 .ets 镜像为 .ts 到临时目录再扫描，
#      行号保持不变（只改扩展名，所以报告行号可直接对应源码）。
#   2. Code Linter 是 DevEco Studio 自带的命令行入口（plugins/codelinter/index.js），
#      规则集取工程内 code-linter.json5。
#   3. 退出码：0 表示无问题，1 表示有问题（便于 CI 使用）。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RULES="$ROOT/security/rules/arkts-security.yml"
SEMGREP="${SEMGREP:-$HOME/.local/bin/semgrep}"
DEVECO_APP="${DEVECO_APP:-/Applications/DevEco-Studio.app}"
LINTER_JS="$DEVECO_APP/Contents/plugins/codelinter/index.js"
SDK_PATH="$DEVECO_APP/Contents/sdk"

usage() {
  echo "用法: bash security/scan.sh {semgrep|linter|all} <工程目录>" >&2
  exit 2
}

MODE="${1:-}"; PROJ="${2:-}"
[ -n "$MODE" ] && [ -n "$PROJ" ] || usage
[ -d "$PROJ" ] || { echo "工程目录不存在: $PROJ" >&2; exit 2; }
PROJ="$(cd "$PROJ" && pwd)"

# ---------- Semgrep ----------
scan_semgrep() {
  [ -x "$SEMGREP" ] || { echo "未找到 semgrep（$SEMGREP），先执行 uv tool install semgrep" >&2; exit 2; }
  local work; work="$(mktemp -d -t a4scan)"
  trap 'rm -rf "$work"' RETURN
  rsync -a --include="*/" --include="*.ets" --exclude="*" "$PROJ/entry/src/main/ets/" "$work/"
  find "$work" -name "*.ets" -exec sh -c 'mv "$1" "${1%.ets}.ts"' _ {} \;
  cp "$PROJ/entry/src/main/module.json5" "$work/module.json5" 2>/dev/null || true

  echo "[Semgrep] 工程: $PROJ"
  echo "[Semgrep] 规则: $RULES"
  set +e
  "$SEMGREP" scan --config "$RULES" --json --quiet "$work" > "$work/out.json" 2>"$work/err.txt"
  set -e
  python3 - "$work/out.json" "$work" <<'PY'
import json, sys
out, work = sys.argv[1], sys.argv[2]
d = json.load(open(out))
res = sorted(d.get('results', []), key=lambda r: (r['path'], r['start']['line']))
print(f"[Semgrep] 结果: 发现 {len(res)} 处问题，解析错误 {len(d.get('errors', []))} 个")
src = {}
for r in res:
    p = r['path'].replace(work + '/', '')
    if p.endswith('.ts'):
        p = p[:-3] + '.ets'
    if p not in src:
        src[p] = open(r['path'], encoding='utf-8', errors='ignore').read().splitlines()
    line = src[p][r['start']['line'] - 1].strip() if r['start']['line'] - 1 < len(src[p]) else ''
    print(f"  {r['extra']['severity']:7} {r['check_id'].split('.')[-1]:34} {p}:{r['start']['line']}")
    print(f"          {line[:100]}")
sys.exit(1 if res else 0)
PY
}

# ---------- Code Linter ----------
scan_linter() {
  [ -f "$LINTER_JS" ] || { echo "未找到 Code Linter: $LINTER_JS" >&2; exit 2; }
  local log; log="$(mktemp -t a4linter)"
  echo "[CodeLinter] 工程: $PROJ"
  echo "[CodeLinter] 规则集: $PROJ/code-linter.json5（@security 已启用）"
  node "$LINTER_JS" --project "$PROJ" --config "$PROJ/code-linter.json5" \
    --sdkPath "$SDK_PATH" --sdkNumberVersion "21" --sdkStringVersion "6.0.1" \
    --workdir "$DEVECO_APP/Contents/plugins/codelinter" \
    --dir '["entry/src/main/ets"]' --logPath "$log" > "$log.jsonl" 2>/dev/null || true
  python3 - "$log.jsonl" "$PROJ" <<'PY'
import json, sys
path, proj = sys.argv[1], sys.argv[2]
files, defects = 0, []
for line in open(path, encoding='utf-8', errors='ignore'):
    line = line.strip()
    if not line.startswith('{'):
        continue
    try:
        o = json.loads(line)
    except Exception:
        continue
    if 'defects' in o:
        files += 1
        for d in o['defects']:
            defects.append((o.get('filePath', '').replace(proj + '/', ''), d))
print(f"[CodeLinter] 结果: 扫描 {files} 个文件，发现 {len(defects)} 个缺陷")
for f, d in defects:
    print(f"  ERROR   {d.get('ruleId'):30} {f}:{d.get('reportLine')}  {d.get('description')}")
sys.exit(1 if defects else 0)
PY
}

case "$MODE" in
  semgrep) scan_semgrep ;;
  linter)  scan_linter ;;
  all)
    set +e
    scan_semgrep; a=$?
    echo
    scan_linter; b=$?
    set -e
    echo
    if [ "$a" -eq 0 ] && [ "$b" -eq 0 ]; then echo "== 汇总：两套扫描均未发现问题 =="; exit 0;
    else echo "== 汇总：存在待修复问题（Semgrep=$a, CodeLinter=$b）=="; exit 1; fi
    ;;
  *) usage ;;
esac
