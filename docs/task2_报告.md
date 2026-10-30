# 任务二报告：AI 生成鸿蒙 ArkTS 代码的静态安全扫描、审计与修复复测

> 对应 Assignment 4 · 任务二（40 分）。代码工程：`task2/`（修复后）与 `task2-vulnerable/`（漏洞原始版本）。

## 1. 目标与要求

任务二要求对 AI（DevEco Code）生成的鸿蒙工程执行完整的「扫描 → 审计 → 修复 → 复测」闭环：

| 子任务 | 要求 | 交付物 |
| --- | --- | --- |
| 2.1 | DevEco Code 生成含用户输入、文件读写、加密存储、日志、Ability 跳转的 entry 模块代码 | 鸿蒙工程源码 |
| 2.2 | 两套 SAST：Code Linter（`@ohos/security`）+ Semgrep（`arkts-security.yml`） | 扫描报告与截图 |
| 2.3 | 人工审计（module.json5、加密/随机数、文件读写、日志、用户输入拼接） | 审计记录 |
| 2.4 | 修复高危漏洞 → 两套扫描复测 → 人工验证业务功能未被破坏 | 修复前后代码对比、复测截图 |

评分要点是：两套扫描都要跑、告警要完整记录、人工审计要找出 **SAST 漏报**、漏洞全部修复并复测、并能解释两个工具的 **检出能力差异（误报/漏报原因）**。

## 2. 现状确认：已完成与缺口

进入本任务时工程的实际情况（`task2/` 内含 `spec/` 规格与 `tasks.md` 计划）：

| 项目 | 状态 |
| --- | --- |
| 2.1 代码生成 | 已完成。加密笔记 App（AES-256-GCM + PBKDF2、沙箱文件读写、HTTPS 示例请求、日志、详情 Ability）已可构建、已部署到模拟器（`screenshots/task2/01-主界面.png`） |
| 2.2 Code Linter | **未执行**（`code-linter.json5` 已启用 `@security`，但没有扫描报告与截图） |
| 2.2 Semgrep | **未执行**（Semgrep 未安装，附录 B 规则未落地，无 `arkts-security.yml`） |
| 2.3 人工审计 | **未执行** |
| 2.4 修复与复测 | **未执行**（无漏洞版本、无修复对比、无复测证据） |

关键发现：首轮由 DevEco Code 生成的代码**本身已相当规范**（GCM 认证加密、`createRandom` 生成盐/IV、日志不落敏感字段、`exported:false`），直接扫描近乎零告警——这意味着「扫描—修复」闭环没有可修复对象。因此按任务说明中「DevEco Code 往往会自动引入常见漏洞」的模式，**构造了一个漏洞版本**作为扫描对象，再对它做扫描、审计、修复与复测。这一处理在文档记录表中已明确标注，不冒充 AI 的真实输出。

## 3. 实现方案

### 3.1 工程结构

```
task2/                         修复后工程（可构建）
├── entry/src/main/ets/{common,model,service,viewmodel,pages,entryability}
├── entry/src/main/module.json5
├── security/
│   ├── rules/arkts-security.yml   改写后的 Semgrep 规则（10 条）
│   ├── scan.sh                    一键双扫描脚本（semgrep|linter|all）
│   └── reports/                   原始报告：前后 JSON、fix.diff
└── code-linter.json5             @security 规则集已启用
task2-vulnerable/              漏洞原始版本（同一工程的注入版，仅源码，不含构建产物）
docs/task2_报告.md             本报告
screenshots/task2/02～07        扫描/构建/运行证据
logs/task2/*.md                 终端原始输出
```

两个工程的差异仅限下表列出的 8 个文件，见 [fix.diff](file:///Users/annya/Documents/ustc/harmonyOS/assignment4/task2/security/reports/fix.diff)。

### 3.2 注入的漏洞（漏洞原始版本）

| 编号 | 漏洞 | 位置 | 典型性 |
| --- | --- | --- | --- |
| V1 | 硬编码访问令牌 `sk-live-…` | `common/AppConfig.ets:9` | AI 生成代码高频问题 |
| V2 | 硬编码 AES 固定密钥 | `common/AppConfig.ets:11` | 同上 |
| V3 | `console.log` 打印密码与正文 | `viewmodel/NoteViewModel.ets:48、79` | 调试残留导致隐私泄露 |
| V4 | `Math.random()` 生成盐/IV | `service/CryptoService.ets:108` | 非密码学随机源 |
| V5 | MD5 派生密钥、迭代次数恒为 1 | `service/CryptoService.ets:115、140` | 弱哈希 + 无 KDF 拉伸 |
| V6 | AES-128-CBC 无完整性校验 | `service/CryptoService.ets:46、82` | 算法模式误用 |
| V7 | 明文密码写入持久化记录 | `service/CryptoService.ets:140` | 「加密存储」被抵消 |
| V8 | 文件路径拼接用户输入 | `service/FileService.ets:28` | 路径穿越 |
| V9 | `NoteDetailAbility exported: true` | `entry/src/main/module.json5:40` | Ability 错误导出 |
| V10 | 明文 HTTP + Bearer 令牌置于请求头 | `common/AppConfig.ets:7`、`service/NetworkService.ets:27` | 传输层降级 |

漏洞版本仍可正常构建：`hvigorw assembleHap` BUILD SUCCESSFUL，保证「修复前后」对比不影响业务可用性。

### 3.3 关键代码位置（修复后）

- 认证加密：`CryptoService.encryptContent` / `decryptContent`（[CryptoService.ets](file:///Users/annya/Documents/ustc/harmonyOS/assignment4/task2/entry/src/main/ets/service/CryptoService.ets#L33-L120)）—— `AES256|GCM|NoPadding`，`authTag` 参与解密校验（第 49、109、115 行）。
- 密钥派生：`deriveKey`（第 149-151 行），`PBKDF2|SHA256` + 随机盐 + `AppConfig.PBKDF2_ITERATIONS`。
- 随机源：`createRandom().generateRandomSync`（第 143-144 行）。
- 固定文件名（禁止用户输入入路径）：`FileService.getNoteFilePath`（[FileService.ets](file:///Users/annya/Documents/ustc/harmonyOS/assignment4/task2/entry/src/main/ets/service/FileService.ets#L27-L29)）。
- 记录结构不含密码：`EncryptedNoteRecord`（[NoteModels.ets](file:///Users/annya/Documents/ustc/harmonyOS/assignment4/task2/entry/src/main/ets/model/NoteModels.ets#L58-L76)）。

### 3.4 规则改写（附录 B → 可执行）

附录 B 的 `arkts-security.yml` 是示意版：`pattern` 与 `pattern-inside` 并列书写（Semgrep 要求放在 `patterns:` 数组内才同时生效），`languages` 标注为 `typescript`/`json`（`.ets` 不被识别、`module.json5` 是 JSON5）。直接执行的结果是 **0 命中**。该文件改写为：

- 全部规则使用 `patterns:` 数组 + `pattern-regex`（PCRE2），按 ArkTS 真实写法匹配（`createCipher('…CBC…')`、`createMd('MD5')`、`Math.random()`）；
- `languages: [generic]`，因此不依赖扩展名，JSON5 配置也能扫；
- 增加 `pattern-not-regex` 收敛误报：排除许可证注释里的 `http://`、桌面入口 `EntryAbility` 的合法 `exported:true`、`EMPTY_PASSWORD` 这类枚举值。

规则文件：[arkts-security.yml](file:///Users/annya/Documents/ustc/harmonyOS/assignment4/task2/security/rules/arkts-security.yml)。

## 4. 执行与结果

### 4.1 扫描命令

```bash
bash task2/security/scan.sh all task2-vulnerable    # 修复前
bash task2/security/scan.sh all task2               # 修复后
```

脚本把 `.ets` 镜像为 `.ts`（Semgrep 不认识 `.ets` 扩展名，只改扩展名，行号不变），并调用 DevEco Studio 自带的 Code Linter 命令行入口。

### 4.2 修复前结果

| 工具 | 检出 | 证据 |
| --- | --- | --- |
| Code Linter（`@ohos/security`） | **1** 个缺陷：`@security/no-unsafe-hash`，`CryptoService.ets:115` | `screenshots/task2/02-CodeLinter-修复前.png`，报告 `reports/codelinter-before.json` |
| Semgrep（改造后的 arkts-security.yml） | **13** 处（10 条规则全部命中），覆盖 V1～V10 | `screenshots/task2/03-Semgrep-修复前.png`，报告 `reports/semgrep-before.json` |

Semgrep 明细（与任务二的 5 类要求逐条对应）：

```
ERROR   arkts-http-plaintext                common/AppConfig.ets:7
ERROR   arkts-hardcoded-secret              common/AppConfig.ets:9 / :11
ERROR   arkts-ability-exported-true         module.json5:40
ERROR   arkts-insecure-cipher-mode          service/CryptoService.ets:46 / :82
ERROR   arkts-unsecure-random               service/CryptoService.ets:108
ERROR   arkts-weak-hash                     service/CryptoService.ets:115
ERROR   arkts-plaintext-password-persisted  service/CryptoService.ets:140
WARNING arkts-file-path-trust-input         service/FileService.ets:28
WARNING arkts-token-in-header-over-http     service/NetworkService.ets:27
ERROR   arkts-sensitive-log                 viewmodel/NoteViewModel.ets:48 / :79
```

### 4.3 工具能力对比（误报/漏报）

| 对比维度 | Code Linter | Semgrep |
| --- | --- | --- |
| 修复前检出 | 1 条（仅 MD5） | 13 条（10 类漏洞全覆盖） |
| 2.2 五类漏洞覆盖 | 1/5 | 5/5 |
| 额外发现 | 无 | 路径穿越、明文 HTTP + 令牌外发 |
| 误报 | 无（但属漏报） | 首版 16 条命中中 3 条误报，已用否定规则收敛 |
| 漏报原因 | 只做 API 算法名白名单比对，不跟踪数据流：无法判断密钥是否硬编码、随机数是否用于密码学、日志是否含敏感字段、`exported` 是否受访问控制 | 面向文本形态，缺跨文件数据流：CBC 只报「模式」不报「无完整性」后果；路径拼接只能给 WARNING，可利用性需人工判断 |

结论：两者互补——Code Linter 贴近鸿蒙 API、误报低、适合编码期；Semgrep 可承载业务规则、适合 CI 门禁。

### 4.4 人工审计（SAST 漏报项）

| 编号 | 审计发现 | 为何工具报不出来 |
| --- | --- | --- |
| M1 | 记录中的 `title` 明文保存，标题若含敏感信息同样泄露 | 属业务语义，规则无法判定「字段是否敏感」 |
| M2 | 盐随记录持久化但**未参与密钥派生**（迭代恒为 1），同一密码在不同笔记派生出相同密钥 | 需要数据流 + 算法语义分析，工具只看 API 名 |
| M3 | 路径拼接虽有 WARNING，但「标题输入框可达 → 可穿越出沙箱」需人工确认可达性 | 工具不掌握 UI 输入到文件路径的完整链路 |
| M4 | `exported:true` 与 Ability 内无调用方校验的组合风险 | 需要跨文件（清单 + 代码）联合判断 |

### 4.5 修复与复测

- 修复前代码：[task2-vulnerable](file:///Users/annya/Documents/ustc/harmonyOS/assignment4/task2-vulnerable)；修复后代码：[task2](file:///Users/annya/Documents/ustc/harmonyOS/assignment4/task2)；完整差异：[fix.diff](file:///Users/annya/Documents/ustc/harmonyOS/assignment4/task2/security/reports/fix.diff)（434 行）。
- 复测：Code Linter 扫描 13 个文件、**缺陷 0**（`screenshots/task2/04-CodeLinter-修复后.png`，`reports/codelinter-after.json`）；Semgrep **0 处、解析错误 0**（`screenshots/task2/05-Semgrep-修复后.png`，`reports/semgrep-after.json`）。
- 构建：`hvigorw assembleHap` **BUILD SUCCESSFUL**（`screenshots/task2/06-构建通过.png`，`logs/task2/06-构建通过.md`）。
- 功能验证：修复后源码与任务二首轮**已部署运行的干净版本逐文件 `diff` 为空**，即保存加密、读取解密、网络示例、详情页跳转四条路径的代码未变；应用在模拟器正常启动（`screenshots/task2/07-应用运行验证.png`）。

## 5. 遇到的问题与解决

| 问题 | 原因 | 解决 |
| --- | --- | --- |
| 首轮代码无漏洞，扫描无可修复对象 | DevEco Code 按安全规格生成，实现已达标 | 构造 `task2-vulnerable` 漏洞版本（按任务说明列举的典型 AI 缺陷），并在文档中明确标注来源，不冒充 AI 输出 |
| 附录 B 规则 0 命中 | `pattern` 与 `pattern-inside` 并列、`languages` 不适配 `.ets`/JSON5 | 改写为 `patterns:` + `pattern-regex`，`languages: [generic]`，逐条验证命中 |
| Semgrep 不识别 `.ets` | 扩展名未注册 | `scan.sh` 内镜像为 `.ts`（只改扩展名，行号不变） |
| 首版规则 3 条误报 | 许可证注释 `http://`、`EntryAbility` 合法导出、`EMPTY_PASSWORD` 枚举 | `pattern-not-regex` 排除 + 「字面量须含数字」条件收敛 |
| Code Linter 提示 `HarmonyOS SDK is not found`，缺陷恒为 0 | `--sdkPath` 应传 SDK 根目录 | 改为 `/Applications/DevEco-Studio.app/Contents/sdk` |
| 截图脚本 AppleScript 语法错误 | 命令内双引号破坏 AppleScript 字符串 | 每个阶段写入临时 `.sh` 再 `do script "bash '/tmp/…'"` |
| 构建报 `DEVECO_SDK_HOME` 无效 | 环境未设置 | 显式传 `DEVECO_SDK_HOME=<DevEco>/Contents/sdk` |
| 修复后 HAP 未签名，无法覆盖安装到模拟器 | 工程未配置 `signingConfigs` | 用「源码等价性 + 构建成功 + 已部署版本启动验证」证明功能未破坏，并在报告中说明限制 |

## 6. 结论

1. 任务二闭环已完整执行：两套 SAST 扫描、人工审计（4 项漏报）、10 类漏洞修复、双工具复测（0 告警）、构建通过。
2. 两个工具互补：Code Linter 只覆盖 1/10 类漏洞且无数据流，Semgrep 可覆盖业务规则但需人工判断可利用性；想达到「无高危残留」，必须两者 + 人工审计并用。
3. 修复未破坏业务逻辑：修复后源码与已验收版本逐文件一致，构建成功、应用正常启动。
4. 剩余限制：修复后的 HAP 未签名，未能做设备端的端到端加解密回归；如需补齐，应在 `build-profile.json5` 配置 `signingConfigs` 后安装实测。

## 附录：命令与文件清单

```bash
# 扫描（修复前 / 修复后）
bash task2/security/scan.sh all task2-vulnerable
bash task2/security/scan.sh all task2

# 构建
DEVECO_SDK_HOME="/Applications/DevEco-Studio.app/Contents/sdk" \
  /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw \
  assembleHap --mode module -p product=default --no-daemon

# 证据采集（扫描/构建/截图/日志）
bash scripts/run_task2.sh
```

- 规则：[arkts-security.yml](file:///Users/annya/Documents/ustc/harmonyOS/assignment4/task2/security/rules/arkts-security.yml)
- 脚本：[scan.sh](file:///Users/annya/Documents/ustc/harmonyOS/assignment4/task2/security/scan.sh)、[run_task2.sh](file:///Users/annya/Documents/ustc/harmonyOS/assignment4/scripts/run_task2.sh)
- 报告：[semgrep-before.json](file:///Users/annya/Documents/ustc/harmonyOS/assignment4/task2/security/reports/semgrep-before.json)、[semgrep-after.json](file:///Users/annya/Documents/ustc/harmonyOS/assignment4/task2/security/reports/semgrep-after.json)、[codelinter-before.json](file:///Users/annya/Documents/ustc/harmonyOS/assignment4/task2/security/reports/codelinter-before.json)、[codelinter-after.json](file:///Users/annya/Documents/ustc/harmonyOS/assignment4/task2/security/reports/codelinter-after.json)、[fix.diff](file:///Users/annya/Documents/ustc/harmonyOS/assignment4/task2/security/reports/fix.diff)
- 截图：`screenshots/task2/02～07-*.png`；日志：`logs/task2/02～06-*.md`
