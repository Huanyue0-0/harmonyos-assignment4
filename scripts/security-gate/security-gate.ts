// @ts-nocheck
/**
 * 任务三 3.3：hvigor CI 安全门禁插件（原型实现）
 *
 * 注册 hvigor 任务 securityScan：构建配置阶段注册，执行时依次跑
 *   1) DevEco Code Linter（@ohos/security 规则集，规则集取自工程 code-linter.json5）
 *   2) Semgrep（工程 security/rules/arkts-security.yml，含 3.2 新增的硬编码 IP 规则）
 * 任一工具报出高危问题即 throw，hvigor 任务失败、CI 退出码非 0，后续打包任务不会执行。
 *
 * 用法：在工程 hvigorfile.ts 中
 *   import { securityScanPlugin } from '<相对路径>/security-gate';
 *   export default { system: appTasks, plugins: [securityScanPlugin()] };
 * 然后执行：hvigorw securityScan
 */
import { HvigorNode, HvigorPlugin } from '@ohos/hvigor';
import { spawnSync } from 'child_process';
import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';

const DEVECO_APP = process.env.DEVECO_APP || '/Applications/DevEco-Studio.app';
const SEMGREP = process.env.SEMGREP || path.join(os.homedir(), '.local/bin/semgrep');

interface Finding {
  source: string;
  severity: string;   // ERROR / WARNING
  file: string;
  line: number;
  rule: string;
  message: string;
}

const rel = (file: string, projectDir: string): string => file.replace(projectDir + path.sep, '');

/** Code Linter：@ohos/security 规则集，severity>=2 视为高危 */
function scanWithLinter(projectDir: string): { scanned: number; findings: Finding[] } {
  const linterJs = path.join(DEVECO_APP, 'Contents/plugins/codelinter/index.js');
  const sdkPath = path.join(DEVECO_APP, 'Contents/sdk');
  if (!fs.existsSync(linterJs)) {
    throw new Error(`未找到 DevEco Code Linter：${linterJs}（可通过 DEVECO_APP 指定 DevEco Studio 安装目录）`);
  }
  const logDir = fs.mkdtempSync(path.join(os.tmpdir(), 'a4-gate-lint-'));
  const logPath = path.join(logDir, 'codelinter.log');
  const args = [
    linterJs, '--project', projectDir,
    '--config', path.join(projectDir, 'code-linter.json5'),
    '--sdkPath', sdkPath, '--sdkNumberVersion', '21', '--sdkStringVersion', '6.0.1',
    '--workdir', path.join(DEVECO_APP, 'Contents/plugins/codelinter'),
    '--dir', '["entry/src/main/ets"]', '--logPath', logPath
  ];
  // Code Linter 只在 cwd 为工程目录时才解析 --dir 相对路径，缺陷 JSON 走 stdout
  const res = spawnSync('node', args, { cwd: projectDir, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
  fs.rmSync(logDir, { recursive: true, force: true });

  const findings: Finding[] = [];
  let scanned = 0;
  for (const line of (res.stdout || '').split('\n')) {
    if (!line.trim().startsWith('{')) continue;
    let report: any;
    try { report = JSON.parse(line); } catch { continue; }
    if (!Array.isArray(report.defects)) continue;
    scanned += 1;
    for (const defect of report.defects) {
      const high = Number(defect.severity) >= 2;
      findings.push({
        source: 'CodeLinter',
        severity: high ? 'ERROR' : 'WARNING',
        file: rel(report.filePath || '', projectDir),
        line: Number(defect.reportLine) || 0,
        rule: defect.ruleId || '',
        message: defect.description || ''
      });
    }
  }
  return { scanned, findings };
}

/** Semgrep：规则取自工程 security/rules/arkts-security.yml，ERROR 视为高危 */
function scanWithSemgrep(projectDir: string): Finding[] {
  const rules = path.join(projectDir, 'security/rules/arkts-security.yml');
  if (!fs.existsSync(rules)) {
    throw new Error(`未找到 Semgrep 规则：${rules}`);
  }
  if (!fs.existsSync(SEMGREP)) {
    console.log(`[securityScan] 未安装 semgrep（${SEMGREP}），本次仅执行 Code Linter 门禁`);
    return [];
  }
  // Semgrep 不识别 .ets 扩展名：镜像到临时目录并改名 .ts，行号保持不变
  const work = fs.mkdtempSync(path.join(os.tmpdir(), 'a4-gate-semgrep-'));
  const srcDir = path.join(projectDir, 'entry/src/main/ets');
  fs.cpSync(srcDir, work, { recursive: true });
  const rename = (dir: string): void => {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) { rename(full); continue; }
      if (entry.name.endsWith('.ets')) fs.renameSync(full, full.replace(/\.ets$/, '.ts'));
    }
  };
  rename(work);
  // module.json5 的 exported=true 等配置类规则同样需要纳入门禁
  const moduleJson = path.join(projectDir, 'entry/src/main/module.json5');
  if (fs.existsSync(moduleJson)) fs.copyFileSync(moduleJson, path.join(work, 'module.json5'));
  const res = spawnSync(SEMGREP, ['scan', '--config', rules, '--json', '--quiet', work],
    { encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
  fs.rmSync(work, { recursive: true, force: true });

  let out: any = {};
  try { out = JSON.parse(res.stdout || '{}'); } catch { out = {}; }
  return (out.results || []).map((r: any) => {
    const file = rel(r.path || '', work).replace(/\.ts$/, '.ets');
    const severity = (r.extra && r.extra.severity) || 'WARNING';
    return {
      source: 'Semgrep',
      severity,
      file,
      line: Number(r.start && r.start.line) || 0,
      rule: String(r.check_id || '').split('.').pop(),
      message: (r.extra && r.extra.message) || ''
    };
  });
}

export function securityScanPlugin(): HvigorPlugin {
  return {
    pluginId: 'assignment4-security-gate',
    apply(node: HvigorNode): void {
      node.registerTask({
        name: 'securityScan',
        run: (): void => {
          const projectDir: string = node.getNodePath();
          console.log(`[securityScan] 工程: ${projectDir}`);

          const linter = scanWithLinter(projectDir);
          console.log(`[securityScan] CodeLinter: 扫描 ${linter.scanned} 个文件，` +
            `缺陷 ${linter.findings.length} 个（高危 ${linter.findings.filter(f => f.severity === 'ERROR').length}）`);

          const semgrep = scanWithSemgrep(projectDir);
          console.log(`[securityScan] Semgrep: 发现 ${semgrep.length} 处问题，` +
            `ERROR ${semgrep.filter(f => f.severity === 'ERROR').length} 处`);

          const findings = [...linter.findings, ...semgrep];
          for (const f of findings) {
            console.log(`[securityScan]   ${f.severity.padEnd(7)} ${f.source.padEnd(10)} ${f.rule} ` +
              `${f.file}:${f.line}  ${f.message.slice(0, 90)}`);
          }

          const high = findings.filter(f => f.severity === 'ERROR');
          if (high.length > 0) {
            throw new Error(`安全扫描失败：发现 ${high.length} 个高危问题，请修复后再提交`);
          }
          console.log('[securityScan] 门禁结果：放行（未发现高危问题）');
        }
      });
    }
  };
}
