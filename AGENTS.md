# AGENTS.md
本文是 AITRANS 的核心入口记忆、项目总览、硬规则和多 Agent 工作流。保持精简；历史细节看 `update_log.md`，当前架构看 `md/flow/flow.md`，测试选择看 `md/test/test.md`。

## 0. 角色召唤和身份标识
- 用户消息以 `agenta`、`a:` 或 `A:` 开头，表示召唤 Agent A。
- 用户消息以 `agentb`、`b:` 或 `B:` 开头，表示召唤 Agent B。
- 用户消息以 `agentc`、`c:` 或 `C:` 开头，表示召唤 Agent C。
- 用户消息以 `agentx`、`x:` 或 `X:` 开头，表示召唤 Agent X；Agent X 面向大目标，自动循环调度 Agent A/B/C 和并发子 agent 协作推进、验证、修复与再迭代，单轮最多开启 6 个子 agent，并及时重分配任务以加速收口。
- 没有这些前缀时，按普通 Codex 任务处理；若任务需要 A/B/C 边界，先提醒用户指定角色或说明本轮按普通任务执行。
- Agent A 最终回复第一行必须写：`我是 Agent A。`
- Agent B 最终回复第一行必须写：`我是 Agent B。`
- Agent C 最终回复第一行必须写：`我是 Agent C。`
- Agent X 最终回复第一行必须写：`我是 Agent X。`

## 1. 项目核心事实
AITRANS 是 SwiftUI iOS 本地 AI 翻译原型。当前重点是漫画截图 OCR、本地翻译、覆盖合成和探针诊断链路。

- 默认 `MockGemmaService` 用于 UI 和数据流冒烟。
- `Local` 模式通过 `GemmaLocalService` + `LlamaRuntime` + `llama.cpp` 加载 GGUF。
- 当前内置最小模型是 `Gemma 3 270M IT QAT Q4_0`，适合验证下载、加载、接口和闪退风险，不适合作为翻译质量基准。
- 更强小模型对比可以考虑 `Qwen2.5-0.5B-Instruct-GGUF q4_k_m`，但不要在没有任务要求时擅自更换模型。
- GGUF 不进仓库。云端手动探针从 Release `model-gemma-3-270m-it-qat-q4_0-v1` 下载并缓存 `gemma-3-270m-it-qat-Q4_0.gguf`，按 SHA256 校验后导入模拟器 App 沙盒。
- 正式版本号 `3.3`：Koharu artifact contract v2 在 v3.2 有界 BubbleMask / SegmentMask RLE 载荷校验上，新增复用 external shadow OCR 稳定一对一 TextBox assignment 的 SegmentMask→BubbleMask 像素/component 拓扑 gate；foreign、orphan、重复或跨 Bubble 归属都不得关闭 gate。v3.2 载荷校验、v3.1 的图片 OCR 待复查筛选、v3.0 的 OCR 摘要与 Store-owned 重新识别，以及 v2.9-v2.2 的图片生命周期能力仍保留。仓库尚无真实 Koharu 四件套、Speech 音频或真实竖排图片 corpus，不声称 OCR、翻译或识别质量提升。
- 当前 App bundle ID 是 `com.local.aitransform114`；云端探针必须从构建产物 `Info.plist` 动态读取，禁止在 workflow 再硬编码。
- 当前可信基线以 `update_log.md`、`metrics/version_history.csv`、最新 `output/probe_report.json` 和 `output/clean_text_diagnostic.json` 为准，不在本入口长篇复制指标。

## 2. 每轮必读
每轮开始先读：

1. `README.md`
2. `AGENTS.md`
3. `git status --short`
4. `git log --oneline -5`
5. `update_log.md`
6. `md/flow/flow.md`
7. `md/flow/flowchart.md`
8. `md/test/test.md`

涉及漫画探针、OCR、覆盖绘制、翻译质量或报告模型时，继续读：

- `AITRANS/Services/MangaOverlayProbeService.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Models/TranscriptModels.swift`
- `test/1.ground_truth.json`
- 最新 `output/probe_report.json`
- 最新 `output/clean_text_diagnostic.json`
- 最新 `output/1_ocr_probe_text.txt`

README 不再承载历史基线；涉及验收时以当前代码、`update_log.md`、最新 `output/`、`metrics/version_history.csv` 和实际测试结果为准。

## 3. 架构硬边界
- `TranslationSessionStore` 是 UI 状态、模型调用、历史、诊断和持久化的统一调度中心。
- UI 层只触发 store 方法，不绕开 store 直接改持久化、模型状态或报告状态。
- Speech 授权、识别和翻译回调必须按当前 run ID 隔离；取消或重试后，旧回调不得覆盖新状态。
- Speech 质量 corpus 的参考 transcript 只能在 Apple Speech 返回最终文本后参与评估；禁止用于识别请求、候选选择、纠错或生产翻译。中日文没有稳定分词器时只报告 CER，不把字符编辑率标成 WER。
- 普通图片 OCR 使用 `VisionOCRService`；漫画覆盖探针使用 `MangaOverlayProbeService` 的独立诊断链路。
- 用户实际翻译和 summary 走 sampled 解码；漫画探针、raw 诊断、clean text、batch 对照和纠错翻译对照走 deterministic 解码。
- `test/1.ground_truth.json` 只能用于探针验证和统计，不能用于真实产品路径或生产候选选择。
- action 打包软件包当前有密码保护；不要为 Agent C 验收改动或解密该包。Agent C 只看独立未加密的 CI 结果包。

## 4. 漫画探针硬规则
漫画覆盖翻译探针固定读取 bundle 内 `test/1.png`：

```text
test/1.png
  -> 裁掉浏览器 UI / 广告 / 底部导航
  -> Vision OCR
  -> 合并 OCR observations 为逻辑文字块
  -> 极简英译中 prompt：把以下翻译成中文：
  -> 覆盖绘制译文或失败文本
  -> 输出 JSON / TXT / PNG 到 App 沙盒 Output
  -> scripts/export-probe-output.sh 导出到项目根 output/
```

必须遵守：

- 失败块必须保留在 `probe_report.json` 的 `blocks` 明细中。
- 失败块必须在覆盖图上显示 `翻译失败 + OCR 原文`，不能静默跳过。
- 失败块必须写入 `blockPassed = false`、`failureReasons`、`translationDecisionTrace`、`translationFailureDetail`。
- 输出目录每轮必须清理，不能混入旧 PNG / JSON。
- 可信匹配必须能拒绝；低于阈值写 `groundTruthMatch = "unmatched"`，且不纳入平均准确率。
- OCR 相似度使用词级 Levenshtein；保留 `ocrLegacySimilarity` 和 `wordOrderPreserved`。
- 核心对话 `dialogue` 和装饰标题 `decorative` 必须分开统计。

禁止：

- 不要用 ground truth 做生产候选选择。
- 不要把旧 `accuracyVsGroundTruth = 0.8378 / 0.8755` 当当前基线。
- 不要只看 `cjkCharacters > 0` 判定翻译成功。
- 不要因为 clean text 失败就继续盲目调 OCR。
- 不要在未证明收益前把 deterministic correction、bubble-first 或 batch translation 替换为主流程。

## 5. Git 分支和云端验证工作流
- `main`：外观展示分支。禁止 Agent B / C 把日常开发成果合并到 `main`。
- `smalldata_test`：本仓库实际工作主分支。若外部提示词写成 `samlldata_test`，以当前远端真实分支 `origin/smalldata_test` 为准。
- `codeb/vX.Y-短标题`：Agent B 候选实现分支，例如 `codeb/v2.0-cloud-ci-workflow`。
- Agent B 每轮从最新 `smalldata_test` 开 `codeb/...` 分支，完成后 push。
- Agent B push 后默认创建 Pull Request，base 为 `smalldata_test`，head 为 `codeb/...`。
- Agent C 从 PR / 远端 `codeb/...` 分支验收；通过后优先通过 PR merge 合并到 `smalldata_test`。
- 任何 Agent 在 `git push`、`git merge`、删除远端分支或改变远端状态前，都必须确认目标不是 `main`。
- Agent C 合并后必须删除远端 `codeb/...` 候选分支，或确认 GitHub PR 的 delete branch 已执行；没有权限删除时必须说明，避免候选分支无限堆积。

默认验证路径：

- 除非人工明确要求“本机测试”“本地 build”“本地跑探针”“本地 xcodebuild”，否则完整 build、Xcode 测试、漫画探针、报告生成和重验证默认交给 GitHub Actions。
- 本地仍可做 `git diff --check`、JSON 解析、YAML smoke 等轻量检查；这些不算重负载本机测试。
- Agent B 完成版本核心代码后 push `codeb/...`：`validationProfile=full`，只运行本任务涉及的领域契约；App 构建相关变更再跑一次 Xcode build。成功后 workflow 为该 SHA 写 `AITRANS CI/full-validation` status，并上传未加密结果包。
- PR 只在 opened / reopened / ready-for-review 时运行 `validationProfile=fast`；不监听 synchronize，避免修复 push 同时触发 full + PR fast。fast 只跑基础静态/路由契约并记录 skip reason，不重复 Xcode、Speech/UI/Koharu 大契约或截图。
- 合并到 `smalldata_test` 后，workflow 读取 merge 第二父 SHA 的 full-validation status；只有 `success` 才走 fast follow-up，否则自动回退 full。C 退回后新的核心修复 push 必须重新产生 full 收据。
- 已通过 full 后的纯 README / AGENTS / update log / `md/` / metrics 提交可复用父提交收据并走 fast；若父提交收据缺失或失败，workflow 会把 diff 扩展到整条候选分支，不能用文档提交掩盖失败。
- Speech 功能默认只跑 Xcode build、Speech run-id/取消/翻译链路契约、质量算法契约和 corpus validator，不采 UI 截图；缺少 `test/speech_corpus/manifest.json` 时 validator 必须写 `manifestMissing`、`qualityExecuted=false`，不能伪造质量结果。漫画/翻译改动需要结果图时手动跑 `ci-fast/full`，只验收探针输出 PNG，不等同 UI evidence。
- UI evidence 默认跳过；只有重大 UI 任务在候选核心 commit 使用 `[ui evidence]`，或手动 `workflow_dispatch ui_evidence_mode=full` 才运行。普通 UI 小改、Speech、PR 和 merge 不截图。
- Koharu artifact validator 的完整 invalid fixture 矩阵只在 Koharu validator、artifact contract 或 CI workflow 相关 full 任务中运行；其他任务不加载该领域套件。
- GitHub Actions push 默认 `probe_mode=skip`，不启动模拟器漫画探针；需要云端探针验收时手动 `workflow_dispatch` 选择 `ci-fast` 或 `full`。
- 现有加密打包 workflow 只在软件包交付时手动 `workflow_dispatch`，不再随 `smalldata_test` merge 自动 archive；Agent C 不以该包验收。
- 独立 CI 结果包必须未加密，至少包含 `junit.xml`、`xcodebuild.log`、`ci-artifact-manifest.json`、`ci-failure-summary.md`；`xcodeBuildRequired=true` 时还必须包含 `.xcresult`，手动探针运行还必须包含可用的 `output/` 报告。
- 若 `workflow_dispatch` 注入 Koharu artifact archive，Agent C 必须核对 Release / artifact / App / CI identity、validator、orientation、dry-run 与 reconciliation 证据。external shadow OCR 除 executed / candidate / OCR count sanity 外，还必须核对 TextBox ID 非空唯一、matched / succeeded / failed / skipped 分区一致、`duplicateAssignedTextBoxIDs = []`、`coverageVerdict = complete`、`successfulCoverageRatio = 1`，且 `WI/G-external-textbox-shadow-ocr-coverage` closed / passed；不得用任意一个 OCR 成功或注入步骤日志冒充完整 coverage。
- 若注入 artifact 的 TextBox 带 `sourceDirection`、`linePolygons` 或 `rotationDegrees`，Agent C 还必须核对 `orientationShadowPathPartialBlocks`、`orientationUnsupportedBlocks`、`orientationUnsupportedReasonBreakdown`、convergence 的 `WI/G-external-textbox-shadow-ocr-coverage` 和 `WI/G-external-textbox-orientation-shadow-path`，确认 no-candidate / partial / unsupported 未被误判为 `closedReportOnly` 或 passed。
- 注入 contract v2 artifact 时，Agent C 必须同时核对 validator / App / manifest 的 `maskTopologyGateReady`、`maskTopologyValidation` / `maskTopologyReport`，以及 convergence `WI/G-external-mask-topology-linkage`。assignment 必须复用 external shadow OCR 的稳定一对一 TextBox 结果；missing / duplicate block 或 TextBox、foreign / no-bubble / orphan / multiply-assigned pixels、cross-Bubble / orphan component 或 partition 不守恒时不得 passed。
- 若云端失败，Agent B 根据结果包中的失败摘要、日志路径和 manifest 修复后继续 push，不改回默认本机循环。

## 6. Agent A/B/C 职责
### Agent A
- 默认不改代码。
- 读取入口文档、历史、流程、测试规范和相关源码。
- 输出写给 Agent B 的版本化提示词，保存到 `md/prompt/vX（阶段）/vX.Y（任务）.md`。
- 提示词必须明确目标、非目标、分支名建议、测试层级、CI 期望、验收标准和禁止项。

### Agent B
- 从最新 `smalldata_test` 开 `codeb/vX.Y-短标题` 分支。
- 按 Agent A 提示词小步实现，不做无关重构。
- 默认本地只跑轻量检查；除非人工明确要求，不跑本机完整 Xcode build 或漫画探针。
- 完成后集中 push 核心候选 commit，让 GitHub Actions 运行一次 task-scoped full；通过后再创建 PR 到 `smalldata_test`，PR 只跑 fast follow-up。若 C 退回，修复 push 重新跑对应 full。
- 最终回复必须列出分支名、PR 链接、commit SHA、push 结果、CI 入口或 run 信息、本地已跑检查、未跑测试原因、artifact 名称；若 Actions 尚未完成，必须说明等待云端结果。

### Agent C
- 拉取 `codeb/...` 分支，查看实际 diff、文档同步、架构边界、GitHub Actions 结论、日志和 artifacts。
- 只能验收与当前 `codeb/...` HEAD 完全一致的 `commitSha`。
- 必须核对 `ci-artifact-manifest.json` 中的 `version`、`branch`、`commitSha`、`runId`、`runAttempt`、`workflowName`、`validationProfile`、`validationReason` 和 full-validation 收据字段，确认没有拿旧包、错包或其他分支的包。fast 结果不能单独冒充候选编译证据。
- 必须查看 `.xcresult` 或摘要、`junit.xml`、`xcodebuild.log`、`ci-failure-summary.md`；涉及探针时还必须检查云端生成或上传的 `probe_report.json`、`clean_text_diagnostic.json`、`1_ocr_probe_text.txt` 和关键 PNG。涉及 external TextBox 时，还必须检查 shadow OCR coverage、orientation partial / unsupported 摘要及 convergence gate 状态。
- 有 bug 或云端验证失败时，输出退回清单，说明应由 Agent B 修复的日志位置和失败原因，不合并。
- 通过后更新版本号和核心文档，通过 PR merge 合并到 `smalldata_test`，push。严禁合并到 `main`。
- 合并完成后删除远端 `codeb/...` 候选分支，或在最终回复说明未删除原因。

## 7. 测试选择
- 非 App 构建相关修改至少运行 `git diff --check`，可加 JSON/YAML smoke。
- 非 App 构建相关变更的云端 CI 可接受 `xcodeBuildRequired=false` 的 build-skip 结果包；Agent C 必须核对 manifest 的 skip reason，不能把它当作 Swift/Xcode 编译证据。
- Swift 或 Xcode 工程修改默认不在本机跑完整 build；按规则推分支交给 GitHub Actions 快验。
- Speech 质量算法修改至少运行 `scripts/test-speech-quality-contract.py`、纯 Swift evaluator contract 和 `scripts/validate-speech-corpus.py`；没有真实音频时只能验收算法与接线，不能给出 WER/CER 改善结论。
- 漫画探针、翻译链路或报告模型修改需要云端探针证据时，手动 `workflow_dispatch` 运行 `ci-fast` 或 `full` 生成报告；若当前云端因模拟器、GGUF、App 容器或外部 artifact 缺失不能稳定运行，必须在最终回复和文档中列明未验证范围、缺失依赖、是否影响验收和需要人工提供什么。
- 不得伪造测试结果，不得把旧 artifact 当新结果。

本地轻量命令：

```sh
git diff --check
python3 -m json.tool test/1.ground_truth.json
python3 -m json.tool output/probe_report.json
python3 -m json.tool output/clean_text_diagnostic.json
```

人工明确要求本机 build 时使用：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project AITRANS.xcodeproj \
  -scheme AITRANS \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath .derivedData \
  CODE_SIGNING_ALLOWED=NO build
```

## 8. 文档和版本收口
- `AGENTS.md` 是唯一核心入口文档。
- `update_log.md` 记录版本历史、关键决策、验证结果和遗留问题。
- `md/flow/flow.md` 只写当前真实架构和运行流程。
- `md/flow/flowchart.md` 必须与 `flow.md` 同步。
- `md/test/test.md` 是测试选择依据。
- `md/prompt/` 保存 Agent A 的版本化实现提示词。
- 功能更新或 bug 修复后，按影响同步更新 `update_log.md`、flow/test 文档和 `metrics/version_history.csv`；README 不再写更新记录，只保留项目说明、当前用法和稳定规则。
- 流程制度变更不伪装成漫画探针质量版本；未重新跑完整探针时不追加 `metrics/version_history.csv` 漫画指标行。

## 9. 最终回复格式
最终回复使用中文，至少包含：

- 改了什么。
- 关键文件。
- 当前分支名和是否触碰远端。
- 已运行的验证命令和结果。
- 未运行的测试及原因。
- 未跑本机 build / 探针时，明确写“未跑本机 build / 探针，按规则交给云端验证”。
- Agent C 通过后，说明 git commit / push / merge 结果和提交哈希；若未执行，说明原因。
- 涉及漫画探针或翻译链路时，汇总关键数字。
- 已知风险和下一步建议。
