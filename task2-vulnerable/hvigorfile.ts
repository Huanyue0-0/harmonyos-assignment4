// @ts-nocheck – Template file, only used when copied into a project directory
import { appTasks } from '@ohos/hvigor-ohos-plugin';
// 任务三：CI 安全门禁。注册 securityScan 任务（Code Linter + Semgrep，发现高危即阻断构建）
import { securityScanPlugin } from '../scripts/security-gate/security-gate';

export default {
  system: appTasks /* Built-in plugin of Hvigor. It cannot be modified. */,
  plugins: [securityScanPlugin()] /* Custom plugin to extend the functionality of Hvigor. */,
};
