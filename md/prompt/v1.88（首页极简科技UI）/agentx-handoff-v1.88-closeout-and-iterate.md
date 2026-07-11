# Agent X 接手提示词：收口 v1.88 后持续优化迭代

## 0. 身份与目标

你是 AITRANS 的 **Agent X**。

- 面向大目标：先把 **v1.88（文本首页极简科技工作台）** 完整收口并合并到 `smalldata_test`，再进入持续优化迭代。
- 可自动循环调度 Agent A / B / C 与并发子 agent；单轮最多 6 个子 agent；及时重分配以加速收口。
- 最终回复第一行必须写：`我是 Agent X。`
- 严禁触碰或合并到 `main`。工作主分支永远是 `smalldata_test`。

本文件是上一任 Agent C 的真实状态交接，不是历史臆测。先读完再行动。

## 1. 当前唯一真相（截至交接）

| 项 | 值 |
|---|---|
| PR | [#41](https://github.com/bengzhu/project1_lgbt_naxida/pull/41) `feat(ui): v1.88 文本首页科技工作台` |
| 分支 | `codeb/v1.88-home-translation-ui` |
| HEAD（必须对齐验收） | `c8326bb068e512dbd8139271e65b38ddb3235b9c` |
| base | `smalldata_test` |
| mergeable | MERGEABLE / CLEAN |
| 云端 run | `29104261998` attempt 1 **SUCCESS** |
| 正式版本号 | 工程仍是 **1.87**；v1.88 未由 Agent C 收口 |
| main | 未触碰 |

### 云端已通过（可复用，勿重造）

- `.xcresult`：0 errors / 0 warnings
- JUnit 7/7；v1.87 contract 6/6；v1.88 contract 7/7；Speech 5/5
- 11 张 UI evidence 完整（均 >135KB）
- Artifact：`aitrans-ci-v1.88-codeb-v1.88-home-translation-ui--c8326bb068e5-run29104261998-attempt1`
- 大小 2,772,091 bytes
- SHA256：`f15c2ad59fcaba0eec3ae5795d9adc060bd3e06405374ce7e747a172cc87983e`
- Agent B 已人工看过关键截图：标准空态可见中文「粘贴」+「翻译」；键盘态可见「完成」；XXL / Accessibility 无 Tab 覆盖

### 产品契约（已锁定，禁止回退）

1. **标准字号 + 键盘关闭**：不预留 48pt 外部净空，首屏完整显示中文「粘贴」与带图标/文字的「翻译」。
2. **XXL 及以上 Dynamic Type，或输入已聚焦**：保留 48pt 外部净空，防浮动 Tab Bar 覆盖，并保证键盘「完成」可见。
3. 真实系统 `PasteButton` 保留为交互层；透明前景 + 不接收触摸的中文 `Label("粘贴", systemImage: "doc.on.clipboard")` 覆盖系统英文标签。
4. 粘贴语义：空输入填入；非空换行追加；不自动翻译；不后台读剪贴板。
5. 其他页面 / 业务链路 / 漫画探针 / metrics 本轮未改，收口时不要误扩 scope。

### 本地工作树污染（合并前必须清掉）

当前 worktree **不干净**，全是 Agent C 临时验收 harness，**禁止 commit / push 进 PR**：

- `?? AITRANSAgentCUITests/`（临时 XCUITest）
- `M AITRANS.xcodeproj/project.pbxproj`（临时 target `AITRANSAgentCUITests`）

清理命令意图：

```sh
git checkout -- AITRANS.xcodeproj/project.pbxproj
rm -rf AITRANSAgentCUITests
git status --short   # 应干净
```

`git show HEAD:AITRANS.xcodeproj/project.pbxproj` 上 **没有** `AITRANSAgentCUITests`，远端 HEAD 本身干净。

### 本机交互验收半绿状态（阻塞合并的原因）

环境：

- Simulator UDID：`71065CA6-4340-4B28-95BF-E82D752E6D93`
- 名称：AITRANS Agent C v1.88 Acceptance（iPhone 17e / iOS 26.5）
- Bundle：`com.local.aitransform114`
- DerivedData：`/private/tmp/aitrans-v188-c8326bb-derivedData`
- App 产物：`/private/tmp/aitrans-v188-c8326bb-derivedData/Build/Products/Debug-iphonesimulator/AITRANS.app`
- 临时结果包：`/private/tmp/aitrans-v188-agent-c-*.xcresult`

| 项 | 结果 | 证据 |
|---|---|---|
| 空剪贴板不破坏已有输入 | **PASS** | `...-empty4.xcresult` |
| 关键 a11y 动作存在（粘贴/翻译/交换/完成） | **PASS** | direct suite |
| 键盘 Done + 再聚焦 + 翻译收起键盘 | **PASS**（需 `-parallel-testing-enabled NO`） | direct suite |
| 纯文本粘贴填入 + 换行追加 + 不自动翻译 | **FAIL** | `testPasteFillsThenAppendsWithoutTranslating` |

失败根因（已定位，不是产品逻辑必然坏）：

1. **macOS Accessibility / AppleScript 仍拒权**：`osascript` → System Events `-25211`「不允许辅助访问」。GUI 脚本注入 Simulator 不可靠。
2. **UITest 剪贴板隔离**：runner 的 `UIPasteboard.general` ≠ app；Xcode 可能跑在 Clone sim；host `simctl pbcopy` 对 clone 无效。即使 `-parallel-testing-enabled NO` 仍可能喂不进系统 `PasteButton`。
3. **iOS 26.5 + SwiftUI 多行输入**：自动化类型 `TextField` / `TextView` / `SwiftUI.VerticalTextView` 不稳定；取值请用  
   `app.descendants(matching: .any).matching(NSPredicate(format: "value == %@", value)).firstMatch`
4. 空剪贴板时系统 `PasteButton` 的 `enabled` 仍可能为 `true`——**不要**把 `isEnabled == false` 当验收标准；产品标准是「点了不清空、不崩」。

### 临时测试文件骨架（仅本地，合并前删除）

路径：`AITRANSAgentCUITests/AgentCAcceptanceUITests.swift`

- `testEmptyClipboardPreservesInput` → PASS
- `testPasteFillsThenAppendsWithoutTranslating` → FAIL（粘贴按钮能点，内容不出现）
- `testDoneAndTranslationDismissKeyboard` → PASS（parallel off）
- `testKeyActionsExistInAccessibilityTree` → PASS

可用命令模板：

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcrun simctl boot 71065CA6-4340-4B28-95BF-E82D752E6D93 || true
xcrun simctl bootstatus 71065CA6-4340-4B28-95BF-E82D752E6D93 -b
printf 'Clipboard validation' | xcrun simctl pbcopy 71065CA6-4340-4B28-95BF-E82D752E6D93

xcodebuild -project AITRANS.xcodeproj -scheme AITRANS \
  -destination 'platform=iOS Simulator,id=71065CA6-4340-4B28-95BF-E82D752E6D93' \
  -parallel-testing-enabled NO \
  -derivedDataPath /private/tmp/aitrans-v188-c8326bb-derivedData \
  -resultBundlePath /private/tmp/aitrans-v188-agent-c-final.xcresult \
  -only-testing:AITRANSAgentCUITests test
```

## 2. 你本轮必须完成的关闭条件（v1.88 Done Definition）

你走b流程，把这些能测的上传github云端测试，禁止本地测试！
云端测试结果通过就先合并，文档可以记录下1.88未做的本地测试，后面我再来看，然后你直接1.89

1. **工作树干净**：无临时 UITest target / 无无关本地改动。
2. **验收 HEAD ==** `c8326bb068e512dbd8139271e65b38ddb3235b9c`（若为修粘贴再 push，则新 HEAD 必须重新跑云端 CI + 新 artifact，禁止拿旧包）。
3. **交互证据闭环**（任选其一，按优先级）：
   - **P0 推荐**：在同一 booted 非 clone sim 上，人工或脚本真实点「粘贴」，证明：
     - 空剪贴板：已有输入保留；
     - 有文本：空框填入 → 再贴换行追加 → 仍显示「等待翻译」；
     - Done 收键盘；翻译前失焦；VoiceOver 标签可读。
   - **P1 可接受**：若系统 `PasteButton` 在 XCUITest 下确认无法注入剪贴板，则：
     - 文档写明「XCUITest 无法验证系统 PasteButton 剪贴板投递」；
     - **不要**为了测试去改生产粘贴语义，除非产品确实有 bug。
4. **Agent C 式收口文档与版本号**（仅在交互过关后）：
   - `MARKETING_VERSION` / 相关 version → **1.88**
   - `update_log.md`：v1.88 从「候选」改为正式通过，写清验证与遗留
   - 按需同步 `md/flow/flow.md`、`md/flow/flowchart.md`、`md/test/test.md`、`README` 稳定用法（若已同步则只补验收结论）
   - **不要**改 `metrics/version_history.csv` 漫画指标（本轮无探针）
5. **Git 收口**：
   - 在候选分支提交收口 commit（仅版本/文档，无 harness）
   - 确认 CI 绿（若只改 md/version 且 build-skip，按 AGENTS.md 核对 skip 规则）
   - **PR #41 merge → `smalldata_test`**
   - 删除远端 `codeb/v1.88-home-translation-ui`
   - 严禁 merge 到 `main`

## 3. 建议调度节奏（Agent X 循环）

### Phase 0 — 恢复现场（你自己，5–15min）

1. 读：`README.md`、`AGENTS.md`、`update_log.md`、`md/flow/flow.md`、`md/test/test.md`、本 handoff、`md/prompt/v1.88.../v1.88（文本首页...）.md`
2. `git fetch`；checkout `codeb/v1.88-home-translation-ui`；确认 `HEAD == c8326bb...`
3. **立即清掉**临时 `AITRANSAgentCUITests` 与 pbxproj 脏改（或 stash 到 `/private/tmp` 备份后再清）
4. `gh pr view 41` 确认仍 OPEN / CLEAN

### Phase 1 — 解开粘贴验收（可派 1 个 builder / investigator）

目标：证明真实粘贴路径，而不是死磕失败的 XCUITest。

优先尝试顺序：

1. 安装已构建的 `AITRANS.app` 到固定 UDID，**人工** `simctl pbcopy` + 点粘贴（最快闭环）。
2. 若坚持自动化：禁用 clone / parallel；**app 启动后再** `simctl pbcopy`；必要时 `simctl openurl` / 调试 launch 参数（仅 debug，勿污染 release 语义）。
3. 读 `TextWorkspacePasteButton.swift` + `TextTranslationView.pasteText`，确认 callback 是否收到空数组（权限/隔离）。
4. **禁止**：为通过测试而改成非系统 PasteButton 或后台轮询剪贴板。

派工建议：

- 子 agent **investigator**：定位 paste 为何拿不到 payload（系统 PasteButton + UITest isolation）。
- 子 agent **builder**：仅当确认产品 bug 时改 1–2 个文件；否则只整理验收脚本到 `/private/tmp`，不进仓。

### Phase 2 — 正式收口（派 Agent C 或自任 C 职责）

通过后执行 §2 的版本号 + 文档 + merge + 删分支。

收口 commit 建议信息风格：

```text
chore(release): close out v1.88 home translation UI

Accept PR #41 on c8326bb (or new SHA if product fix).
Record interactive paste/keyboard/a11y evidence and bump marketing version.
```

### Phase 3 — 合并后进入持续优化（大循环）

v1.88 合并完成后，**不要停**。按下方 backlog 开新候选分支迭代。每轮仍：A 写提示词 → B 实现/PR → 云端 CI → C 验收 merge → 删 `codeb/...`。

## 4. 合并后持续优化 backlog（按优先级）

### P0 体验债（紧接 v1.88）

1. **真实设备 / 人工交互清单固化**：把粘贴、空剪贴板、键盘 Done、VoiceOver、Tab 遮挡回归写成 `md/test/test.md` 可勾选人工矩阵（CI 截图无法替代）。
2. **系统 PasteButton 可测性**：评估 debug-only 注入或 UITest host app pasteboard API；保持隐私模型（仅用户点击时读文本）。
3. **宽屏证据**：iPad / 横屏运行态截图进 evidence 门控（当前仅 compact iPhone 11 张）。

### P1 首页与工作台

4. 最近翻译 / 会话命令在首屏信息密度与可达性再平衡。
5. 错误态、加载态、模型未就绪时主按钮与状态条文案一致性。
6. Dynamic Type 从 XS→AX5 全谱扫描，防止净空策略在中间档位抖动。

### P2 工程与 CI

7. UI evidence 分支门控通用化（不要每版本硬编码 branch 名）。
8. 评估是否引入**正式**轻量 UI smoke target（与临时 AgentC harness 区分，合入需契约与稳定 selector）。
9. CI 结果包与 PR 评论自动贴关键截图链接，减少人工下载 artifact。

### P3 产品主线（漫画 / 本地模型，勿与 UI 小版本混做）

10. 漫画探针 clean-text / 覆盖质量主线（见 `update_log` 基线与 `output/`）。
11. 本地 GGUF 质量与稳定性（270M 仅冒烟；更强小模型对照需独立任务）。
12. Koharu external artifact / orientation shadow 路径的未闭合 work item。

**规则**：UI 收口版本不要伪装成漫画质量版本；未跑探针不写 `metrics/version_history.csv` 漫画行。

## 5. 硬禁止

- 禁止 merge 到 `main`
- 禁止把 `AITRANSAgentCUITests` 或临时 pbxproj 带进正式 commit
- 禁止用旧 run / 旧 artifact 验收新 HEAD
- 禁止伪造粘贴通过；未证明就写「已验证」
- 禁止为测通而破坏 `PasteButton` 隐私模型或自动翻译
- 禁止在未授权时本机跑全量漫画探针并当作云端替代（除非用户明确要求）
- 禁止 reset / 覆盖用户其他未关联改动

## 6. 关键路径速查

```text
PR:            https://github.com/bengzhu/project1_lgbt_naxida/pull/41
Branch:        codeb/v1.88-home-translation-ui
HEAD:          c8326bb068e512dbd8139271e65b38ddb3235b9c
Prompt:        md/prompt/v1.88（首页极简科技UI）/v1.88（文本首页极简科技工作台与剪贴板键盘交互）.md
Handoff:       md/prompt/v1.88（首页极简科技UI）/agentx-handoff-v1.88-closeout-and-iterate.md
UI code:       AITRANS/Views/TextTranslationView.swift
               AITRANS/Views/TextWorkspacePasteButton.swift
               AITRANS/Views/TextWorkspaceBackground.swift
Contract:      scripts/test-v188-home-ui-contract.py
Cloud run:     29104261998
Local app:     /private/tmp/aitrans-v188-c8326bb-derivedData/Build/Products/Debug-iphonesimulator/AITRANS.app
Sim UDID:      71065CA6-4340-4B28-95BF-E82D752E6D93
```

## 7. 第一回合建议输出格式（Agent X）

1. 我是 Agent X。
2. 现场确认：HEAD、PR 状态、工作树是否已清临时 harness。
3. 本轮计划：Phase1 粘贴闭环策略 + 是否需要改代码。
4. 子 agent 分配（若启用）与预计产出。
5. 明确：在粘贴证据闭环前 **不 merge**。

---

交接人：Agent C（本机交互验收未完成）  
交接原因：用户要求转 Agent X 循环迭代；先收口 v1.88，再持续优化。  
用户偏好：要快；可以本机装模拟器实测；不要把无关本地编译变成默认流程，但本轮用户已明确要求本机验证与合并。
