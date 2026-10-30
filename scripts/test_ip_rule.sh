#!/usr/bin/env bash
# 任务三 3.2：单独验证新增的硬编码 IPv4 规则（arkts-hardcoded-ip，见附录 D）
#
# Semgrep 不识别 .ets 扩展名，故把样例复制为 .ts 后再扫描（行号不变）。
# 用法：bash scripts/test_ip_rule.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RULES="$ROOT/task2/security/rules/arkts-security.yml"
SAMPLE="$ROOT/task2/security/rules/tests/hardcoded-ip-sample.ets"
SEMGREP="${SEMGREP:-$HOME/.local/bin/semgrep}"

[ -x "$SEMGREP" ] || { echo "未找到 semgrep：$SEMGREP" >&2; exit 2; }
[ -f "$SAMPLE" ] || { echo "未找到样例：$SAMPLE" >&2; exit 2; }

WORK="$(mktemp -d -t a4iprule)"
trap 'rm -rf "$WORK"' EXIT
cp "$SAMPLE" "$WORK/hardcoded-ip-sample.ts"

echo "[规则] ${RULES}（共 $(grep -c '^  - id:' "$RULES") 条）"
echo "[样例] $SAMPLE"
"$SEMGREP" scan --config "$RULES" --json --quiet "$WORK" > "$WORK/out.json" 2>/dev/null || true

python3 - "$WORK/out.json" "$SAMPLE" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
src = open(sys.argv[2], encoding='utf-8').read().splitlines()
res = d.get('results', [])
print(f"[结果] 命中 {len(res)} 处，解析错误 {len(d.get('errors', []))} 个")
for r in res:
    print(f"  {r['extra']['severity']:7} {r['check_id'].split('.')[-1]:20} "
          f"hardcoded-ip-sample.ets:{r['start']['line']}")
    print(f"          {src[r['start']['line'] - 1].strip()}")
    print(f"          {r['extra']['message']}")
sys.exit(0 if res else 1)
PY
