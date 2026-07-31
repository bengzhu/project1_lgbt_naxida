# AITRANS iOS Prototype

这是一个基于 SwiftUI 的 iOS 本地 AI 翻译原型。默认使用 `MockGemmaService` 做界面和数据流冒烟；切换到 `Local` 并导入 GGUF 后，App 会通过 `llama.cpp` 加载本地模型生成翻译或总结。

当前正式版本：`3.43`（普通图片 OCR 的文字块在逐块翻译期间仍可查看和定位，但会改变当前图片结果或复查进度的动作只在最终 `.translated` 状态开放：OCR 修正、恢复 Vision OCR、恢复已忽略 block、旁贴／覆盖切换还会在导出重绘期间保持禁用；开始／继续／重启复查及完成／撤销复查同样等待完整翻译。v3.42 会在仍有实际文字块但操作被锁住时显示状态行，并让覆盖方式、复查、局部预览、结果行和忽略恢复的 VoiceOver 提示复用 loading／translating／failed／export-rendering 的具体原因；v3.43 继续让图片局部预览的前后导航在筛选首尾给出“第一个／最后一个文字块”的边界提示，并让结果行定位提示随当前选中状态切换为“取消定位”或“在图片预览中定位”。逐块翻译会明确仍可查看和定位，失败会引导重试。View 的状态门和 Store 的 mark／reopen／reset 二次校验共同防止逐块翻译中提前写入复查进度；成功 OCR 修正先恢复 translated 再沿用既有自动复查。v3.37–v3.40 的文本规范化、弃改保护、键盘收起、滚动收起、保存期输入锁定和 revision-scoped 焦点交接继续保留）。仓库仍没有真实 Koharu 四件套、Speech corpus 或真实竖排图片 corpus，因此不声称 OCR、翻译或识别质量提升。云端 receipt 传播规则（v3.26）仍适用；日常开发合入 `smalldata_test`，不合并到 `main`。

## 运行

1. 用 Xcode 打开 `AITRANS.xcodeproj`。
2. 选择 iPhone 模拟器或已连接的 iPhone。
3. 运行 `AITRANS` target。

如果命令行构建提示当前开发目录不是完整 Xcode，可以临时这样构建：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project AITRANS.xcodeproj \
  -scheme AITRANS \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath .derivedData \
  CODE_SIGNING_ALLOWED=NO build
```

`Assets.xcassets` 已进入 target 的 Resources build phase，包含 AppIcon、AccentColor 和日间/夜间语义色。设置页可选择跟随系统、日间或夜间；默认跟随系统。

项目根目录的 `test/` 已作为 folder resource 打进 App bundle。往 `test/` 放入音频或 OCR 图片后，需要重新构建安装 App，开发控制台的测试按钮才会扫描到新文件。

## 协作与云端验证

- 日常工作主分支是 `smalldata_test`；`main` 只作外观展示，不合并日常开发成果。
- Agent B 候选实现分支使用 `codeb/vX.Y-短标题`。核心代码 push 执行一次 task-scoped full；成功 SHA 获得 `AITRANS CI/full-validation` status，随后 PR 和已验证 merge 只做 fast follow-up。
- 本机默认只跑轻量检查；除非人工明确要求，不默认跑本机 Xcode build 或漫画探针。
- Agent C 验收使用未加密的 `AITRANS CI Results` artifact；`xcodeBuildRequired=true` 时核对 `.xcresult`，build-skip 快路径则核对 skip reason，同时核对 `junit.xml`、`xcodebuild.log`、`ci-artifact-manifest.json` 和失败摘要。
- 云端验证必须先用 `gh auth login` 拿到 GitHub 权限，Agent C 才能下载 Actions 结果包。
- Agent C 下载的云端测试缓存默认放在 `/private/tmp/aitrans-c-review-<run_id>/`，由人工确认后删除。
- Agent C 通过 PR 合并后必须删除远端 `codeb/...` 候选分支，避免分支无限堆积；无权限删除时要明确说明。
- 现有加密软件包 artifact 只用于软件包交付，workflow 仅手动触发，不再随 merge 自动 archive，也不作为 Agent C 验收依据。
- `AITRANS CI Results` 对 `codeb/**` 核心 push 默认 `validationProfile=full`、`probe_mode=skip`：按变更领域运行契约，App 相关任务跑一次 Xcode build，不下载 GGUF、不启动漫画探针。
- PR 只在 opened / reopened / ready-for-review 时执行 fast，不监听 synchronize；merge 只有核验第二父 SHA 的 full-validation status 成功后才执行 fast，否则自动回退 full。
- fast follow-up 跳过 Xcode、Speech/UI/Koharu 领域大契约和 UI evidence，manifest 必须写明复用 SHA、status、profile、reason 和 skip reason；Agent C 仍需验收候选 full 结果，不能只看 fast 包。
- 版本整合分支 `1.*` 也会触发同一快验；云端探针从构建出的 App `Info.plist` 动态读取 bundle ID，当前工程值为 `com.local.aitransform114`。
- full CI 会按变更范围选择 Speech、UI、文本首页或 Koharu 契约；非 App 构建相关 full 仍可跳过 Xcode。父提交 full 成功后的纯文档/metrics follow-up 可传播收据；父收据缺失或失败时自动扩展到整条候选 diff。
- UI evidence 默认不运行。重大 UI 任务在候选 commit 标记 `[ui evidence]` 或手动选择 `ui_evidence_mode=full`；Speech 和普通 PR/merge 不截图。漫画/翻译结果图由手动 `ci-fast/full` 的 `output/` 产物提供。
- 手动 `workflow_dispatch` 可选填 `koharu_artifact_release_tag`、`koharu_artifact_asset`、`koharu_artifact_sha256`，从 Release 下载真实 Koharu 四件套 archive 并在 Xcode build 前注入 `test/koharu_artifacts/`；archive 必须只有一个目录同时包含四件套，CI 结果包会记录 source image 和四件套文件的 SHA256 / size identity；`koharu_artifact_required=true` 时下载、SHA、解压、唯一目录检查或 validator 失败会直接失败。
- 注入 Koharu artifact 且运行 `ci-fast` / `full` 时，云端探针 smoke 必须证明 App receipt、source image / 四件套 size + SHA256、CI manifest identity、dry-run 和 reconciliation 全部匹配。external shadow OCR 除 executed / candidate / OCR count sanity 外，还必须证明 TextBox ID 非空唯一、一对一 assignment、matched / succeeded / failed / skipped 分区一致、`duplicateAssignedTextBoxIDs = []`、`coverageVerdict = complete`、`successfulCoverageRatio = 1`；不能只看下载、validator、`readyForShadowOCR` 或局部 OCR 成功。
- 手动 `ci-fast` / `full` 探针会从 Release `model-gemma-3-270m-it-qat-q4_0-v1` 下载 `gemma-3-270m-it-qat-Q4_0.gguf`，校验 SHA256 `3626e245220ca4a1c5911eb4010b3ecb7bdbf5bc53c79403c21355354d1e2dc6`，用 Actions cache 复用 `.ci-models/`，并把模型导入模拟器 App 沙盒。
- 需要探针验收时，手动 `workflow_dispatch` 选择 `ci-fast` 或 `full`。探针复用同一次 Debug simulator build 产物安装 App，把缓存模型复制到 App sandbox 的 `Application Support/Models/Gemma-1.5B/model.gguf`，用 `AITRANS_RUN_MANGA_PROBE=1` 和 `AITRANS_MANGA_PROBE_MODE` 启动 App，导出本轮 `output/` 到未加密结果包。`Gemma-1.5B` 是历史目录名；实际文件必须用 Release asset 名、字节数和 SHA256 校验确认。
- `ci-fast` 仍是真模拟器、Local GGUF、真实 `test/1.png`、deterministic 解码、whole-page OCR、bubble-first 融合、逐块翻译、失败块覆盖、`probe_report.json`、`clean_text_diagnostic.json`、`1_ocr_probe_text.txt`、`1_debug_boxes.png`、`1_translated_overlay.png`、Koharu external artifact gate，以及 v1.18+ 必需的 report-only / detector-lite 受限 shadow 报告；只跳过 lexicon / Vision API / slice / crop experiment / line shadow / batch / 纠错翻译对照 / contact sheet 等高成本对照和诊断 PNG。Agent C 通过 manifest 的 `probeMode`、`probeSkippedReason`、`probeFastPathEnabled`、`probeSkippedDiagnostics`、`probeOutputRetainedFiles` 和 `probeReportSummary` 区分快验、快速探针与全量探针。
- v1.57 起 bundle-lite / promotion gate 会消费 TextBox -> SegmentMask linkage，输出 linkage breakdown、review / blocked blocks 和 TXT 摘要；v1.58 起 convergence 继续消费这些 linkage work item / gate，使最终收敛层能阻塞弱 linkage。v1.64 起 external TextBox shadow OCR 会在真实 artifact ready 后对竖排或接近 90/180/270 度的 TextBox 执行有上限的 orientation-aware rotation OCR，并记录 `orientationShadowPathPartialBlocks`、`orientationUnsupportedBlocks`、`orientationUnsupportedReasonBreakdown`、attempted rotations、selected rotation、Vision language profile 和 unsupported reason；line polygon warp 与任意角度 deskew 继续进入 `WI-external-textbox-orientation-shadow-path` / `G-external-textbox-orientation-shadow-path` convergence blockers，不能误判 `closedReportOnly`。v1.65 起 validator 会输出 `orientationMetadataSummary`，CI manifest 会透传 `koharuArtifactValidationOrientationSummary`；v1.66 起 validator / CI 还会透传 `artifactIdentitySummary` / `koharuArtifactValidationIdentitySummary`；v1.67 起 App 探针 runtime 也会在 `externalArtifactReadinessReport.artifactIdentityReceipt` 和 contract dry-run 中记录 source image / 四件套 size 与 SHA256；v1.68 起 `koharuArtifactIdentityReconciliationReport` 把 App receipt 规范化为 CI manifest 字段路径，Actions 会输出 `koharuArtifactIdentityReconciliationMatch.matchVerdict`。v1.69 起真实 artifact ready 后 `WI/G-external-textbox-shadow-ocr-coverage` 同时要求 App 侧 identity receipt、identity reconciliation ready、contract dry-run ready、dry-run 边界安全、shadow OCR 已执行、`candidateCount > 0`、`ocrExecutedCount > 0` 且 `ocrSucceededCount > 0`，未闭合时 gate 为 blocked。v1.80 起 App runtime readiness 与 identity reconciliation 也会解析并强制 manifest `sourceImageSHA256` 匹配 runtime 可见的 bundle `test/1.png` SHA256，CI 摘要会透传 declared / expected / matches。该路径仍是 report-only gate，不新增 LLM / PNG，也不改变主 OCR、翻译、覆盖图或 active artifact。
- v1.70 起只要 workflow 填写 Koharu artifact archive，就必须使用 `ci-fast` 或 `full`，不能用 `probe_mode=skip`；云端 smoke 会核对 coverage / orientation work item 与 gate ID、status、App-side identity 摘要和 `ocrSucceededCount`，orientation blockers 未清空时不得误判 passed。
- v1.92 更新 v1.64 的 orientation 边界：合法、非退化的凸四点 `linePolygons` 会用有上限的透视校正生成逐行 shadow OCR crop，只有 warp OCR 输出被选中时才标记 `deskewExecuted`；bbox fallback、warp 失败和任意角度 deskew 继续作为 convergence blockers。该能力仍只消费真实四件套，保持 shadow-only，不改变主 OCR、翻译或覆盖图。
- v1.74 起 `ci-fast/full` 的未加密 manifest 和 failure summary 也会直接汇总 v1.39-v1.46 native-lite detector / shadow OCR / refinement / closed-loop / instance-lite / SegmentMask refinement / bundle / promotion gate 的 verdict、counts、linkage blockers 和 convergence work item / gate 状态，避免 Agent C 为了确认 native-lite 阻塞再深挖完整 `probe_report.json`。
- 云端探针验收口径是报告可解析、`engineUsed = Local GGUF`、`totalBlocksDetected > 0`、关键 JSON/TXT/PNG 可用；`overallPassed=false` 仍可能是当前模型质量基线，不单独作为 CI 失败。若探针超时，结果包会保留 `manga-probe.log`、`app-console.log` 和 `output/manga_probe_progress.json`；`ci-fast` 启动后 180 秒未创建 progress 会提前失败、progress 300 秒不更新会提前收束，`full` 分别为 300 秒和 600 秒。
- 显式启用 UI evidence 的 App 候选 CI 会复用当前 Debug simulator build，生成 14 张 `ui-evidence/`（12 张 compact iPhone + 2 张 wide iPad）和 manifest；wide iPad 同时覆盖文本空态和图片成功/风险复查态，音频矩阵分别覆盖 recognizing + Reduce Motion 与 translating + 取消入口。v1.87 全 App interaction contract 与 v1.88 文本首页 contract 分别作为独立 testcase，截图或任一契约失败都会阻塞候选分支；当前不采集 Mac 运行态证据。

## 当前界面

- `文本`：首页使用静态技术网格与输入到译文的导向线路承托工作区，语言、粘贴、Prompt、翻译、模型状态和译文保持清晰动作层级。系统纯文本“粘贴”只在点击时读取剪贴板；空输入直接填入，已有输入换行追加且不自动翻译。软件键盘提供“完成”按钮，翻译、新会话或离开文本页前会先结束输入焦点。iPad 宽屏使用输入/输出并排，iPhone 自动降为单列。
- `图片`：图片检查区保持主视觉，有低置信或方向待定块时显示本次复查完成/总数/剩余进度；进度仅由当前图片会话的 Store 内存状态持有，界面重建后仍可继续，新图、取消和清空会重置。入口按进度明确显示开始或继续；每个风险结果行可直接完成并定位下一块，也可撤销，主行点击仍只负责图片定位与局部放大。打开“修正识别文字”后，sheet 会显示带黄色框的当前文字块局部图；局部图无法生成时明确提示但不阻止手工修正，低置信/方向待定时还会说明复查原因。`trim` 后仍等于当前原文的编辑不再被误当成未保存修改：按钮仍为“确认无误”，取消或下滑关闭不会额外要求放弃；真正改字时才保留既有确认和只重译该 block。多行修正输入的键盘工具栏提供可访问“完成”动作，滚动 sheet 时也会交互式收起键盘；取消、打开忽略确认或保存前仍会先收起键盘。开始“保存并重译”后，当前 OCR 输入会锁定至这一次翻译完成或失败，避免异步完成覆盖刚保存后的新增输入。上述行为都不改变校验、discard protection、Store 输入或关闭后焦点交接。取消、放弃未保存修正或无修改时下滑关闭该 sheet，会在完全关闭后回到发起位置：结果行入口回到结果行，局部放大铅笔入口回到同一局部预览；成功修正或忽略仍沿用下一结果行、下一块局部放大、完成态或忽略行等更具体目的地。局部放大保留完成/撤销及前后切换，全部完成后可重新开始；v3.43 让筛选首尾的前后按钮在 disabled 时读出“当前已是第一个／最后一个文字块”，可用时读出定位上一个／下一个文字块，结果行主操作也会按是否已定位读出取消定位或在图片预览中定位。完整预览中的 OCR 覆盖块可直接点选或取消；点击 OCR 结果行会把图片工作区带回视口并高亮对应块。目标语言菜单与旁贴/覆盖 segmented control 位于工具区，照片、文件、取消、重试、导出和 OCR 块状态集中展示。任务从 loading 起冻结内容语言；失败或取消后修改输入/目标语言只更新下次 Retry 选择，选回当前内容语言会撤销对应待重试更改，菜单和状态不会继续显示无效差异；免费模式的图片输入语言菜单显示锁定图标，尝试修改时明确提示 Pro 且不污染文本页语言；结果标题始终显示当前内容实际语言，已完成图片选择不同语言后会重新识别或翻译。
- `图片操作状态边界`：OCR 结束后的逐块翻译仍保留截图、文字块、选中定位和局部预览，方便确认进度；不过 loading／recognizing／translating、失败或不完整状态都不会开放修正、恢复、忽略恢复、覆盖方式切换、开始／重启复查或完成／撤销复查。只有完整 `.translated` 才能写入这些变更；导出重绘期间还会继续锁住改变结果的操作，避免用户在中间态看到 block 就提前提交复查结论。v3.42 在当前仍有文字块且锁定存在时显示一条警示状态行；每个禁用的改变结果或复查入口也会给 VoiceOver 复用相同的状态化原因。逐块翻译明确可继续查看／定位但不可提交，失败明确提示先重试，导出重绘只说明图片编辑暂时锁定。
- `图片局部修正快捷入口`：选中 OCR block 后，局部放大窗在关闭按钮下提供 44pt 铅笔入口；仅当当前图片已完整翻译、未在导出重绘且 block 仍在当前活动集合时才会打开修正页。它复用既有修正 sheet 和 revision-checked 关闭后焦点交接；取消、放弃未保存修正或无修改关闭会回到同一局部预览，结果行入口仍回到结果行。
- `音频`：实时长按识别与音频文件识别分区展示，保留取消入口和 locale、离线要求、耗时、词数、片段、置信度与失败原因。
- `历史`：搜索、恢复、删除、归档、导入、导出和清空使用一致命令层级；空历史和无搜索结果使用系统空状态。
- `设置`：集中管理 Pro、提示词、模型、本地数据和受保护的开发者入口。提示词支持方向、新建、复制、编辑、删除和内置锁定；模型页支持 Mock/Local、GGUF 下载/导入/移除、自检和生成参数。
- `开发`：仅在开发者模式开启后显示。raw prompt/output、批量 raw probe、固定素材测试和漫画探针报告采用高密度、可选择的等宽文本布局；漫画报告存在时会额外只读展示 Koharu 四件套 readiness、缺件和 nextAction，便于复制给工件提供方，不触发新 probe、不改变任何探针字段或执行语义。
- 音频识别页会显示本次运行的输入名、locale、本机识别要求、耗时、词数、分段数、平均置信度、文本或失败原因；识别和翻译状态分开，检查中、识别中或翻译中均可取消。取消会先失效当前 run，再取消识别与模型翻译 Task；旧授权、识别、翻译或摘要回调不会覆盖立即重试后的新状态。

## Pro / 内购占位

当前已接入 StoreKit 2 订阅骨架，但还没有 App Store Connect 线上商品。发布前需要在 App Store Connect 创建同 ID 自动续期订阅，并把价格配置为约 1 美元/月：

- 预留商品 ID：`com.local.aitrans.pro.monthly`。
- 展示价格：`$0.99/月`。
- `开通 Pro` 会尝试读取 StoreKit 商品并购买；如果 App Store Connect 未配置商品，会显示未找到商品。
- `校验订阅` 会读取 `Transaction.currentEntitlements` 并同步 Pro 状态。
- `开发解锁` 仍保留为本地调试开关，便于真机测试未上架功能。
- 免费：中文、英语文本翻译。
- Pro：解锁日语、法语、德语目标语言。
- Pro：解锁同声传译入口。同声传译在音频页长按麦克风开始采集，松手结束，Apple Speech 本机识别结果先进入文本框，再点击按钮交给当前 Mock/Local 翻译接口。识别侧使用 `requiresOnDeviceRecognition = true`，支持情况取决于设备、系统和语言包。
- Pro：音频文件断网识别测试入口。选择音频后，App 会复制到沙盒，用 `SFSpeechURLRecognitionRequest` 和 `requiresOnDeviceRecognition = true` 做 Apple 本机识别，成功后自动交给当前大模型翻译。
- Pro：`test/` 音频/OCR 测试入口。App 会扫描 bundle 内 `test/` 的首个匹配文件；音频支持 `.m4a`、`.wav`、`.mp3`、`.caf`，图片支持 `.png`、`.jpg`、`.jpeg`、`.heic`。未找到文件时会显示 `test/ 未找到可测试音频/图片`。
- Pro：后台一键翻译入口已做开发占位。iOS 普通 App 不能像 Android 一样常驻覆盖其他 App 的任意悬浮窗；可行路线是 Share Extension 处理截图/文本，或 ReplayKit Broadcast Upload Extension 在用户显式启动屏幕广播后处理屏幕帧。
- Pro：图片翻译已接入开发版流程。选择图片后，App 使用 Apple Vision `VNRecognizeTextRequest` 本机 OCR 得到文字块和 `boundingBox`，逐块交给当前本地模型翻译，并在图片预览上提供“旁贴”和“覆盖”两种定位展示模式。

## 离线 OCR / 屏幕翻译方案

当前结论基于 Xcode 26.5 SDK 头文件能力：

- 图片翻译不一定需要额外 OCR 模型。Apple Vision 提供 `VNRecognizeTextRequest`，能返回 `VNRecognizedTextObservation`，包含识别文本和位置框；这适合断网本机 OCR。
- 当前图片翻译流水线是：图片输入 -> Vision OCR 得到文字块和 `boundingBox` -> 按行/块送入本地 Gemma 翻译 -> 在图片预览层按原坐标旁贴译文，或用半透明译文块覆盖原文区域。
- 如果后续需要更强的漫画/竖排/复杂版面能力，可以增加本地 OCR/版面分析模型，但第一版优先用 Vision，减少模型体积和部署风险。
- 后台一键屏幕翻译不能依赖普通 App 悬浮窗覆盖全系统页面。iOS 可考虑两条合规路线：用户分享截图到 App/Share Extension；或用 ReplayKit Broadcast Upload Extension 获取屏幕帧，再在扩展或主 App 协作里跑 OCR/翻译。

## 本地数据

数据保存在 App sandbox 的 Application Support 目录：

```text
Application Support/AITRANS/state.json
```

`state.json` 保存：

- 当前会话：转录行、摘要、语言、模式、提示词、模型引擎、会话时长。
- 历史记录：最多保留 60 个会话。
- 提示词模板：内置模板和用户新增模板；新版本同时保存 `英译中` 和 `中译英` 两套指令。旧 JSON 只有单个 `instruction` 时会自动迁移为两个方向，不丢自定义提示词。
- App 设置：当前引擎、语言、选中的提示词、temperature、max tokens、开发期 Pro 开关。

历史页的 `导出 JSON` 会先额外写出：

```text
Application Support/AITRANS/aitrans-export.json
```

随后会打开系统文件导出面板，方便把同一份 JSON 保存到 Files、iCloud Drive 或其他位置。

历史页的 `导入 JSON` 可以选择同结构的 `aitrans-export.json` 或 `state.json`。导入时会先归档当前会话，再合并历史和提示词；内置提示词会保留，同 ID 的会话或提示词不会重复导入。

模型页的 `运行自检` 会检查：

- 本地 JSON 是否可写入并解码。
- Gemma 1.5B Mock 是否能生成非空输出。
- LLM 接口是否能收到模拟输入，并从当前适配器回传非空输出。
- Local 模式是否已经安装 GGUF 模型。

模型页的 `运行接口自测` 会按当前语言方向构造翻译输入，要求输出非空、不能等于原文、不能包含原文、不能是占位答复，并且要像目标语言。英译中曾出现模型原样返回英文的问题，后续排查必须优先使用接口自测和开发页 raw 探针，不要只看 UI 结果猜测。

开发页 raw 探针用于定位这几类问题：

- “运行原始接口”：按当前语言方向测试单条输入。Local 模式下这是送入 `llama.cpp` 的真实字符串和 raw 输出；Mock 模式只展示模拟请求预览。
- “运行批量探针”：依次跑 `Keep the model on device.`、`The meeting starts at 9:30 tomorrow.`、`Save the transcript locally.`、`请把会议记录保存在本地。`、`明天九点半开始会议。`，覆盖英译中和中译英。
- “大模型实际输入”：完整展示 app 当前送给模型的 prompt，包括语言方向、输入文本和当前方向提示词。Local 模式下这是送入 `llama.cpp` 的真实字符串。
- “大模型实际输出”：展示 `llama.cpp` raw 输出，不做 trim、clean、重试或 fallback；批量探针会逐条显示 prompt、raw output/error 和判定。
- “错误代码”：模型缺失、加载失败、上下文过长、分词失败或 decode 失败时直接显示错误类型和 `localizedDescription`。
- 如果 raw 输出正常但普通翻译失败，优先查 `GemmaLocalService.cleanTranslationOutput` 和目标语言校验；如果 raw 输出已经复读原文，优先查 prompt、采样和模型质量。

当前默认提示词是极简模板：

- 英译中：`把以下翻译成中文：`
- 中译英：`Translate the following into English:`

Local prompt 现在只拼当前方向指令和输入文本，减少长预设污染模型 raw 输出。JA/FR/DE Pro 翻译仍走通用 fallback。

## 语音 / OCR 测试规范

`test/` 用于固定测试素材，不用于保存用户数据或模型文件：

```text
test/
  sample.m4a
  sample.png
```

测试流程：

1. 把语音或图片放进项目根目录 `test/`。
2. 重新构建安装 App，因为 `test/` 是 bundle resource。
3. 在 App 内打开 `设置`，使用有效订阅或开发者模式下的 `开发解锁` 解锁 Pro。
4. 点击 `运行 test/ 音频` 或 `运行 test/ OCR`。
5. 音频会走 `SFSpeechURLRecognitionRequest` + `requiresOnDeviceRecognition = true`，识别文本再交给当前 Mock/Local 翻译接口。
6. 图片会走 `VNRecognizeTextRequest`，识别文字块和 `boundingBox` 后逐块翻译。

### 语音识别质量探针

开发页的语音质量探针读取 `test/speech_corpus/manifest.json`，逐项校验音频 SHA256 和字节数，再按每项 `localeIdentifier` 使用 `SFSpeechURLRecognitionRequest` 与 `requiresOnDeviceRecognition = true` 识别。最终文本返回后才与参考 transcript 计算指标，并写入 `Application Support/AITRANS/Output/speech_quality_report.json` 和 `.txt`。

- 英文等空格分词语言报告词级 WER 和字符级 CER；中文、日文只报告 CER。
- 报告包含 corpus/manifest 身份、设备与系统、识别文本、延迟、分段、平均置信度、失败分类和加权汇总。
- 参考 transcript 只用于事后评估，不进入 Speech 请求、候选选择、纠错或产品路径。
- v1.95 未提交或生成占位音频。当前 validator 输出 `manifestMissing` 和 `qualityExecuted=false`；这不是质量失败，也不是质量通过。
- v1.96 上传真实文件后按 `test/speech_corpus/README.md` 生成 manifest，再在目标设备运行并保留报告，才能比较实际 WER/CER 和延迟。

### 漫画覆盖翻译探针

开发页新增 `运行漫画覆盖翻译探针`，固定读取 bundle 内 `test/1.png`，不污染当前会话、历史或普通图片翻译状态。流程：

1. 读取 `test/1.png`。
2. 先按可配置比例裁掉浏览器 UI / 广告 / 底部导航，本次默认 `topRatio = 0.235`、`bottomRatio = 0.14`。
3. 对裁切后的漫画内容做 2x 放大，再做 0°、90°、180°、270° 四次 Apple Vision OCR，识别英文文字块。
4. 将旋转图坐标还原成原图像素 bbox，坐标约定为左上角原点 `[x, y, width, height]`；输出绘制同样使用左上角坐标，避免上下翻转。
5. 对 OCR 候选按 bbox 重叠、文本相似度、相邻行/段落空间关系合并，目标是一个对话框对应一个逻辑块。
6. 对每个合并块复用当前英译中极简提示词 `把以下翻译成中文：` 和当前引擎翻译；Local 模式记录真实 `llama.cpp` prompt/raw output，Mock 模式标记为模拟。
7. 质量判定失败时也会绘制覆盖层，文本为 `翻译失败` + OCR 原文，并在报告写入失败原因，避免静默跳过。
8. 生成 `Application Support/AITRANS/Output/1_debug_boxes.png`、`1_translated_overlay.png` 和 `probe_report.json`。

探针报告字段：

- `sourceImage`：固定 `test/1.png`。
- `engineUsed`：实际适配器显示名。
- `totalBlocksDetected`：最终保留文本块数。
- `blocks[].bbox`：原图像素坐标，左上角原点。
- `blocks[].rotationAngleUsed`：该块来自 0/90/180/270 哪个 OCR 角度。
- `blocks[].prompt` / `rawOutput` / `errorCode`：真实输入输出或错误。
- `blocks[].checks`：`ocrNotEmpty`、`translationNotEmpty`、`translationNotEqualOriginal`、`translationNotContainOriginal`、`looksLikeChinese`。
- `blocks[].translationCandidate`：从 raw output 中抽取出来用于质量判定和覆盖绘制的候选译文。
- `blocks[].rawOutputClassification` / `candidateClassification` / `failureCategory`：分别记录模型 raw 输出类型、候选译文类型和失败归因。常见值包括 `chinese`、`nonChinese`、`placeholder`、`repeatedOriginal`、`symbolsOnly`、`modelOutputFailure`、`ocrInputSuspect`、`ruleFalseFailureSuspected`。
- `blocks[].bestGroundTruthText` / `ocrGroundTruthSimilarity` / `ocrQualityLabel`：把当前 OCR 文本和 `test/1.ground_truth.json` 的人工真值做相似度对照，用于判断翻译差是否先由 OCR 输入错误导致。
- `blocks[].bestGroundTruthType` / `groundTruthMatch` / `groundTruthMatchThreshold`：人工真值匹配类型与是否可信匹配。低于阈值的块会标为 `unmatched`，不再强行配一个错误真值，也不纳入准确率统计。
- `blocks[].ocrLegacySimilarity` / `wordOrderPreserved`：保留旧相似度作对照，同时新增词级编辑距离相似度和词序信号。词序错乱的 OCR 会明显降分，避免旧算法把乱序文本算成高准确。
- `blocks[].failureReasons`：失败块的具体原因，例如 `翻译等于原文`、`翻译是占位答复`、`中文字符不足`、`翻译不像中文`。
- `blocks[].qualityNotes`：非硬失败排查线索，例如 `translationContainsFullOCRText`、`latinLetters=27`、`cjkCharacters=4`。
- `blocks[].translationDecisionTrace` / `translationFailureDetail`：逐块记录 raw 分类、候选分类、每条硬判定布尔值和失败归因；用于确认失败来自模型 raw 输出、OCR 输入、候选抽取，还是规则误伤。
- `blocks[].ocrProbeNotes`：逐块记录 OCR 和人工真值的相似度、质量标签、已知 OCR 混淆提示。
- `diagnostics`：本轮整体排查汇总，统计通过/失败块、空候选、占位输出、复读原文、非中文输出、raw 输出类型、候选抽取丢弃、平均 OCR 真值相似度、疑似 OCR 问题块、疑似规则误伤块、失败分类分布、中文候选失败原因分布、翻译语言质量通过/失败块、硬通过但质量可疑块。
- `diagnostics.averageCoreDialogueOCRSimilarity` / `averageDecorativeOCRSimilarity` / `groundTruthMatchedBlocks` / `groundTruthUnmatchedBlocks` / `wordOrderFailedBlocks` / `repeatedKeywordFailures`：可信匹配后的核心对话/装饰文字分开统计、未匹配块计数、词序失败块和高频专有名词损坏追踪。
- `configuration.currentBlockSource`：记录当前块来源。当前是 `fusedWholePageBubble`，即 whole-page OCR 与 bubble-first OCR 的无真值融合主流程。
- `configuration.preprocessing`：记录本轮预处理增强开关，包含灰度、对比亮度、自适应二值化、裁切放大、锐化和放大倍数。
- `configuration.customLexiconEnabled` / `customLexicon`：记录 Vision `customWords` 是否启用和本轮词表。
- `blocks[].rawOcrText` / `afterPreprocessingOcrText` / `finalTextUsedForTranslation`：记录原始 OCR、裁切预处理后二次 OCR、最终送翻译文本。当前预处理结果只用于对比展示，不替换整图 OCR 主流程。
- `blocks[].correctionEnabled` / `afterCorrectionText` / `correctionRejectedReason` / `correctionPrompt` / `correctionRawOutput` / `correctionErrorCode`：记录 OCR 纠错后处理链路。护栏拒绝时 `afterCorrectionText` 保留原文，`correctionRejectedReason` 写明长度、词数、新词或空输出原因。
- `blocks[].deterministicCorrectionText` / `deterministicCorrectionAppliedRules` / `deterministicCorrectionSimilarity`：记录探针专用确定性 OCR 纠错候选。当前只做量化对比，不替换 `finalTextUsedForTranslation`，避免半修正文本污染翻译链路。
- `blocks[].deterministicCorrectionTranslationCandidate` / `deterministicCorrectionTranslationRawOutput` / `deterministicCorrectionTranslationPassed` / `deterministicCorrectionTranslationFailureDetail`：仅对确定性纠错相似度确有提升的块，额外跑一次纠错文本翻译对照。该结果只用于探针，不替换主覆盖图和主翻译输入。
- `correctionGuardrailTest`：固定构造 `XQZ 12 ///` -> `The City Battler Tournament starts in a few days.` 的过度纠错测试，用来证明护栏会拒绝模型瞎猜。
- `lexiconComparison`：同图同参数下 Vision `customWords` 开/关对比，记录总块数和发生变化的块编号。
- `visionAPIComparison`：旧 `VNRecognizeTextRequest` 与 iOS 18+ Swift 原生 `RecognizeTextRequest` 的 0° OCR 对比。当前只作为独立探针，不替换主流程。
- `frameworkComparison`：整页 OCR 与 bubble-first 对照。差集列表、交集数量和汇总准确率都从最终明细现场计算，`consistencyPassed` 必须为 `true`；如果计数和列表不一致，会写入 `consistencyWarnings`。
- `fusionComparison` / `fusionResults`：whole-page 与 bubble-first 的融合主流程审计。候选选择只用 bbox、bubbleID、文本相似度、OCR 置信度和文本质量等无真值信号；ground truth 只用于事后评估。报告会记录被选来源、竞争候选、替换原因和拒绝原因。
- `internalStructureBottleneckReport`：v1.18 新增的内部结构瓶颈路由报告。它聚合 OCR 相似度、bubble / TextBox / SegmentMask proxy、post-fusion cleanup、crop / line blockers、翻译失败分类和渲染状态，为每块写出 `primaryBottleneck`、`secondaryBottlenecks`、`recommendedNextAction`、`evidence` 和 `mustNotPromoteReasons`；只做诊断路由，不替换主流程文本。
- `routingDrivenTranslationComparisonReport`：v1.19 新增的路由驱动 strict prompt 对照报告。它只从 `internalStructureBottleneckReport.primaryBottleneck = modelTranslationQuality` 的块中最多选择 5 个，额外用 deterministic `strictChineseOnlyV1` prompt 生成诊断译文，复用主质量判定 helper，记录 improvement / failure；不替换主流程 prompt、译文、`blockPassed`、失败分类或覆盖图。
- `ocrCharacterDamageAuditReport`：v1.19 新增的 OCR 字符损坏审计报告。它只分析 `ocrCharacterDamage`、`ocrInputSuspect` 或低相似度块，使用 ground truth 做探针诊断，输出 damaged / missing / extra / substitution token、line break risk、TextBox / SegmentMask 证据、crop blockers 和 recommended action；不替换 `finalTextUsedForTranslation`，也不参与生产候选排序。
- `readingOrderStructureAuditReport`：v1.20 新增的阅读顺序与结构计划审计报告。它用最终 blocks、bbox、bubbleID、BubbleMask、TextBox / SegmentMask proxy、post-fusion cleanup 和路由证据生成 `proposedReadingOrderIndex`、同气泡 sibling、归属/分割/重复风险、保护标记和 `recommendedStructureAction`；只写 JSON / TXT，不改变 `blocks` 顺序、翻译输入、覆盖图、`blockPassed` 或候选选择。
- `structureActionCandidateReport`：v1.21 新增的结构动作候选矩阵和 shadow 执行评估报告。它把 v1.20 的结构建议转成 `readingOrderReindex`、`bubbleAssignmentReview`、`bubbleSplitShadow`、`sameBubbleSiblingLayout`、`duplicateFragmentProtection`、`textBoxEvidenceRequired`、`segmentMaskEvidenceRequired`、`renderSafeAreaReflow` 和 `manualReviewOnly` 候选，记录 control/shadow metrics、delta、promotion verdict、blockers 和 next step；只复用已有几何、渲染和 shadow OCR 摘要，不新增昂贵 OCR / LLM，不改变主 OCR、翻译输入、覆盖图、`blockPassed`、失败分类、post-fusion cleanup 或候选选择。缺真实 Koharu artifact 时只输出 `blockedByMissingRealArtifact` / `provideRealKoharuArtifact`，不能用内部 proxy 冒充 detector。
- `koharuArtifactDAGReport`：v1.22 新增的 Koharu 式 Artifact DAG 阶段账本。它把 SourceImage / ContentCrop / OCR / BubbleMask / TextBoxes / SegmentMask / Translation / Render / v1.21 结构动作候选组织成 dependency edges、stage summaries 和逐块 trace，定位 `firstBlockingStage` 与 `downstreamImpact`；只复用既有探针证据，不新增 OCR / LLM 调用，不改变主 OCR、翻译输入、覆盖图、`blockPassed`、失败分类、post-fusion cleanup 或候选选择。缺真实 active artifact 时只阻塞真实 TextBoxes / BubbleMask / SegmentMask promotion，不把当前主流程整体判废。
- `koharuStageGapReplicationReport`：v1.23 新增的 Koharu canonical stage 差距复刻计划层。它把 v1.22 DAG 阶段账本转成 `SourceImage` / `TextBoxes` / `SegmentMask` / `BubbleMask` / `OcrText` / `Translations` / `Inpainted` / `RenderedSprites` / `FinalRender` 等阶段的当前能力、差距、work package、promotion gate 和逐块复刻计划；只写 JSON / TXT，不新增 OCR / LLM 调用，不改变主 OCR、翻译输入、覆盖图、`blockPassed`、失败分类或 cleanup。缺真实 `test/koharu_artifacts/` 时，真实 TextBoxes / BubbleMask / SegmentMask 仍保持 `manifestMissing` / `stopUntilArtifactsProvided` 阻塞，不能用 Vision OCR、pre-crop plan、line plan 或内部 proxy 冒充。
- `koharuNativeReplicationScoreboardReport`：v1.24 新增的 Koharu 本地复刻评分层。它只使用 AITRANS 自己的探针输出，把 v1.23 stage gap / work package 转成 stage scorecard、gate ledger、block scorecard 和 next work items；真实 external artifact 缺失只记为 `externalOptionalMissing`，不阻塞 native scoreboard。该报告区分 ground-truth-free decision signals 与 evaluation-only ground truth metrics，明确 native / proxy / shadow / stop / model-limited / render-stable 状态，并把已证伪的 crop / line / deskew 本地试参加入 stoplist；不新增 OCR / LLM 调用，不改变主 OCR、翻译输入、覆盖图、`blockPassed`、失败分类、post-fusion cleanup 或候选选择。
- `nativeTextBoxProxyLedgerReport`：v1.25 新增的 Native TextBox proxy 质量账本。它执行 v1.24 的 `WI-native-textbox-artifact-scorecard`，聚合现有 TextBox / crop / line / BubbleMask / SegmentMask / OCR damage / scoreboard 证据，输出逐块质量状态、候选来源、word preservation / protected keyword / bubble / segment / OCR damage / model floor / render gate、stoplist 和下一步动作；ground truth 只进 evaluation signals，不参与候选排序、冻结或晋级。该报告冻结已证伪的 crop / line / deskew 试参，只允许证据完整的候选进入未来 shadow-only 复核；不新增 OCR / LLM，不改变主 OCR、翻译输入、覆盖图、`blockPassed`、失败分类、post-fusion cleanup 或候选选择。
- `bubbleMaskAssignmentSplitScoreboardReport`：v1.26 新增的 BubbleMask 归属分割评分板。它执行 v1.24 的 `WI-bubblemask-assignment-split-scorecard`，聚合现有 BubbleMask proxy、assignment correction、split candidate、reading order、structure action、native scoreboard 和 Native TextBox ledger 证据，输出逐块归属状态、split risk、same-bubble sibling layout、mask safe rect、render gate、实例级 bubble scorecard、split candidate ledger、sibling layout scorecard 和 gate ledger。该报告只做 report-only 诊断；ground truth 只进 evaluation signals，不参与 assignment / split / sibling layout / nextAction / promotion 决策；不新增 OCR / LLM，不改变主 OCR、翻译输入、覆盖图、`blockPassed`、失败分类、post-fusion cleanup、候选选择、`safeLayoutRect` 或 `configuration.currentBlockSource`。
- `segmentMaskProxyCoverageScoreboardReport`：v1.27 新增的 SegmentMask proxy 覆盖评分板。它执行 v1.24 的 `WI-segmentmask-proxy-coverage-scorecard`，聚合现有 glyph mask、SegmentMask proxy、TextBox 覆盖、BubbleMask 覆盖、safe rect、背景填充和渲染碰撞证据，输出逐块 coverage / cleanup / render mask 状态、glyph 清字边界账本、gate ledger 和下一步动作。该报告明确 `proxyNotRealSegmentMask = true`，只做 report-only 诊断；ground truth 只进 evaluation signals，不参与 coverage / cleanup / nextAction / gate 决策；不新增 OCR / LLM，不改变主 OCR、翻译输入、覆盖图、`blockPassed`、失败分类、post-fusion cleanup、候选选择、`safeLayoutRect`、`glyphMaskFillRects`、背景填充行为或 `configuration.currentBlockSource`。
- `koharuArtifactConvergenceReport`：v1.28 新增的 Koharu artifact 收敛矩阵与下一步决策账本。它聚合 v1.22 DAG、v1.23 stage gap、v1.24 native scoreboard、v1.25 TextBox、v1.26 BubbleMask、v1.27 SegmentMask、external artifact gate、clean text model floor、diagnostics 和最终 blocks，输出 canonical stage convergence matrix、逐块 artifact path、work item closure ledger 和 gate ledger；v1.58 起还消费 bundle-lite / promotion gate 的 TextBox -> SegmentMask linkage work item 与 gate。该报告只做 report-only 诊断；ground truth 只进 evaluation signals，不参与 firstBlockingArtifact、nextAction、work item status 或 gate 决策；不新增 OCR / LLM，不改变主 OCR、翻译输入、覆盖图、`blockPassed`、失败分类、post-fusion cleanup、候选选择、`safeLayoutRect`、`glyphMaskFillRects`、背景填充行为、渲染逻辑或 `configuration.currentBlockSource`。
- `translationModelFloorComparisonReport`：v1.29 新增的 Translation Model Floor 对照矩阵。它复用 `cleanTextDiagnostic` 的 dialogue 真值输入，额外用 deterministic `strictChineseOnlyV1` prompt 生成 clean text 变体对照，并汇总 noisy final blocks、routing strict prompt、tagged batch 和 Koharu convergence work item，输出模型 / prompt 地板判断、gate ledger、clean case 和 noisy block 摘要。该报告只做 report-only 诊断；clean text ground truth 只用于模型地板评估，不参与 noisy OCR 候选选择、主 prompt、主译文、覆盖图、`blockPassed` 或失败分类。
- `koharuRenderRegressionLockReport`：v1.30 新增的 Koharu RenderedSprites / FinalRender 回归锁账本。它聚合现有 `safeLayoutRect`、mask-safe rect、render collision、render mask overflow、glyph mask、background fill、失败块 fallback 覆盖文本和核心输出文件状态，输出逐块 `blockLocks[]`、`artifactStages[]`、`outputFileChecks[]` 和 `gateLedger[]`，并把 `WI-render-regression-lock` 联动进 convergence work item。该报告只做 report-only 诊断；不重新渲染、不解析 PNG 像素证明逐块文字、不改变覆盖绘制、`safeLayoutRect`、`glyphMaskFillRects`、背景填充、主 OCR、主翻译、`blockPassed` 或失败分类，并明确 `proxyNotRealKoharuRenderer = true`。
- `koharuPipelineResolverReport`：v1.31 新增的 Koharu Pipeline Resolver 影子 DAG。它用 `needs` / `produces` / DAG resolver / Op preview 的形式组织现有 SourceImage、ContentCrop、Vision OCR、Bubble/TextBox/SegmentMask proxy、OCR text、Translations、RenderedSprites proxy、FinalRender 和 ExternalArtifacts 证据，输出 `nodes[]`、`edges[]`、逐块 `blockTraces[]`、`executionQueue[]`、`opPreviews[]` 和 `gateLedger[]`。该报告只做 report-only 诊断；不新增 OCR / LLM，不改变主 OCR、翻译、覆盖、候选选择或失败分类，ground truth 只进 evaluation signals。
- `koharuWorkOrderRouterReport`：v1.32 新增的 Koharu WorkOrder Router 执行工作单与收益预算账本。它从 v1.31 resolver 派生固定 work orders、逐块 routes、CI/full/external 预算、stoplist、模型地板和 render lock gate，并把 `WI-koharu-workorder-router` / `G-koharu-workorder-router-executed` 联动进 convergence。该报告只做 report-only 诊断；不新增 OCR / LLM，不改变主 OCR、翻译、覆盖、候选选择或失败分类，ground truth 只进 evaluation signals。
- `koharuExternalArtifactRequestPacketReport`：v1.33 新增的 Koharu 外部 Artifact 请求包与准入缺口账本。它从 v1.32 router、external readiness gate、external TextBox shadow OCR、TextBox / BubbleMask / SegmentMask scoreboards、render lock、translation floor 和 convergence 聚合真实 `test/koharu_artifacts/` 交付需求，固定枚举 `1.manifest.json`、`1.textboxes.json`、`1.bubbles.json`、`1.segment_mask.json`，输出 required files、artifact requirements、逐块 request、validator commands、forbidden active sources 和 gate ledger。缺 active artifact 时稳定输出 blocked / missing，不创建、不复制、不伪造 `test/koharu_artifacts/`；ready 后只允许进入 external shadow OCR gate。该报告只做 report-only 诊断；不新增 OCR / LLM，不改变主 OCR、翻译、覆盖、候选选择、失败分类、safe layout、glyph mask、背景填充或 `configuration.currentBlockSource`，ground truth 只进 evaluation signals。
- `koharuNativeAlgorithmReplayMatrixReport`：v1.34 新增的 Koharu 本地算法复刻执行矩阵与探针评估账本。它从 resolver、router、request packet、convergence、TextBox / BubbleMask / SegmentMask scoreboards、translation floor、render lock、diagnostics 和最终 blocks 聚合 canonical stage matrix、固定 native replay candidate queue、逐块 route 和 budget / promotion gates，把候选分成 nativeExecutableNow、shadowOnly、stoplisted、externalArtifactBlocked、modelFloorBlocked、renderLocked 等状态。该报告只做 report-only 诊断；不新增 OCR / LLM，不改变主 OCR、翻译、覆盖、候选选择、失败分类、safe layout、glyph mask、背景填充、active artifacts 或 `configuration.currentBlockSource`，ground truth 只进 evaluation signals。
- `koharuBubbleIndexShadowLedgerReport`：v1.35 新增的 Koharu BubbleIndex 影子账本。它从现有 BubbleMask proxy、归属修正、split candidate、reading order、BubbleMask assignment / split scoreboard、render lock、native replay matrix 和最终 blocks 聚合 block / bubble / same-bubble sibling ledger，审计 majority mask 归属、mask-safe rect 对照、同气泡 sibling 分区、split 风险和 render lock。该报告只做 report-only 诊断；不新增 OCR / LLM，不改变主 OCR、翻译输入、覆盖图、`safeLayoutRect`、`blockPassed`、失败分类、候选选择、active artifacts 或 `configuration.currentBlockSource`，ground truth 只进 evaluation signals，`proxyNotRealBubbleMask = true`。
- `koharuDistanceFieldSafeAreaReport`：v1.36 新增的 Koharu BubbleIndex distance-field 安全区影子复刻。它只在现有 rounded-rect BubbleMask proxy ID mask 的 bubble bbox 内计算 chamfer distance field、safe pixels、最大安全矩形，并对 block / sibling 比较当前 `safeLayoutRect`、v1.35 shadow safe rect、distance-field safe rect 和 render sprite containment。该报告只做 report-only 诊断；不新增 OCR / LLM，不改变主 OCR、翻译输入、覆盖图、`safeLayoutRect`、`glyphMaskFillRects`、背景填充、`blockPassed`、失败分类、候选选择、active artifacts 或 `configuration.currentBlockSource`，ground truth 只进 evaluation signals，`proxyNotRealBubbleMask = true` 且 `usesRoundedRectProxyMask = true`。
- `koharuBubbleAdjacencySeamReport`：v1.37 新增的 Koharu BubbleMask instance adjacency / seam partition 影子账本。它基于现有 rounded-rect BubbleMask proxy、BubbleIndex、DistanceField、split candidate、same-bubble sibling、OCR damage 和 render lock 证据，输出 bubble pair、seam candidate 和 block seam ledger，解释邻接、切缝候选、归属/分割风险和真实 BubbleMask 需求。该报告只做 report-only 诊断；不新增 OCR / LLM，不改变主 OCR、翻译输入、覆盖图、`safeLayoutRect`、DistanceField safe rect、`glyphMaskFillRects`、背景填充、`blockPassed`、失败分类、候选选择、active artifacts 或 `configuration.currentBlockSource`，ground truth 只进 evaluation signals，`proxyNotRealBubbleMask = true` 且 `usesRoundedRectProxyMask = true`。
- `koharuRenderSpriteFitPlannerReport`：v1.38 新增的 Koharu RenderedSprites 字体 / 换行 / sprite fit 影子账本。它复用现有 `safeLayoutRect`、render diagnostics、Render Regression Lock、BubbleIndex、DistanceField 和 Bubble adjacency seam 证据，输出逐块 fit、layout candidate 和 same-bubble sibling fit ledger，并联动 convergence。该报告只做 report-only 诊断；不新增 OCR / LLM，不重新渲染 PNG，不改变主 OCR、翻译输入、覆盖图、`safeLayoutRect`、DistanceField safe rect、`renderFontSize`、`renderNonTransparentBounds`、`glyphMaskFillRects`、背景填充、`blockPassed`、失败分类、候选选择、active artifacts 或 `configuration.currentBlockSource`，ground truth 只进 evaluation signals，`proxyNotRealKoharuRenderer = true` 且 `proxyNotRealBubbleMask = true`。
- `koharuNativeTextBoxDetectorLiteReport`：v1.39 新增的 Koharu Native TextBox Detector-Lite 预 OCR 影子复刻。它只用 source image 像素、bubble geometry、BubbleMask proxy 和 glyph / SegmentMask proxy 为每个 bubble 生成有上限的 `nativeDetectorLite` TextBox 候选池（最多 4 个 component-cluster 候选 + 1 个不参与 shadow OCR 的 diagnostic union fallback），记录 bbox、方向、暗像素密度、连通域、投影峰、bubble coverage、glyph overlap、候选与当前 block 的 overlap / center / same-bubble relation、block / bubble ledger 和 gate，并联动 convergence。该报告默认不执行 shadow OCR，不使用 Vision OCR 文本、ground truth、pre-crop plan、line plan 或 TextRegion crop 结果生成 / 排序候选；不改变主 OCR、翻译输入、覆盖图、`blockPassed`、失败分类、`textRegionCropReport.adoptedCount`、active artifacts 或 `configuration.currentBlockSource`，`proxyNotRealKoharuTextBoxes = true`。
- `koharuNativeTextBoxDetectorLiteShadowOCRReport`：v1.40 新增的 detector-lite TextBoxes -> OCR 最小闭环评估。它只消费 v1.39 `shadowOCREligible = true` 的 `nativeDetectorLite` 候选，`ci-fast` 每块最多 1 个、`full` 每块最多 2 个，按当前 block 与候选 bbox 的 overlap / center containment 优先排序，调用受限 Vision crop OCR 并输出 raw / normalized text、empty / failed / better / worse / same、quality delta、word preservation、evaluation-only ground truth similarity、block ledger 和 gate。`verticalCandidate` 会额外做有上限的 `[0,90]` rotation shadow OCR 对照，使用 `ja-JP/ja/en-US/en` 的受限 Vision language profile 并记录 `rotationApplied`，只用无真值 OCR 质量和保词率选择 report-only 最佳结果。该报告不新增 LLM 调用，不使用 ground truth 决定候选、排序、OCR 执行、nextAction 或 gate；不替换主 OCR、`finalTextUsedForTranslation`、翻译输入、覆盖图、`blockPassed`、失败分类、`textRegionCropReport.adoptedCount`、active artifacts 或 `configuration.currentBlockSource`，`proxyNotRealKoharuTextBoxes = true` 且 `proxyNotRealKoharuOCR = true`。
- `koharuNativeTextBoxDetectorLiteRefinementReport`：v1.41 新增的 detector-lite 闭环二次候选与 refinement shadow OCR。它只消费 v1.39 detector-lite 候选和 v1.40 shadow OCR ledger，用 v1.40 outcome、失败分类、模型地板和渲染锁等无真值信号选择 target，从 detector-lite 父 bbox 内用暗像素 envelope、projection band、directional padding 和保守 bubble clip 生成 refined bbox，并在预算内执行 Vision crop OCR。该报告只写 JSON / TXT，不新增 LLM，不使用 ground truth 决定 target、bbox、排序、OCR 执行、nextAction 或 gate；不替换主 OCR、`finalTextUsedForTranslation`、翻译输入、覆盖图、`blockPassed`、失败分类、`textRegionCropReport.adoptedCount`、active artifacts 或 `configuration.currentBlockSource`，`proxyNotRealKoharuTextBoxes = true` 且 `proxyNotRealKoharuOCR = true`。
- `koharuNativeTextBoxDetectorLiteClosedLoopReport`：v1.42 新增的 detector-lite 闭环裁决与结构路由账本。它消费 v1.39 detector-lite、v1.40 shadow OCR、v1.41 refinement、final blocks、BubbleMask / SegmentMask proxy、翻译失败分类、translation model floor、render lock 和 external artifact readiness，把每块路由到保留主 fused OCR、report-only full probe 复核、停止本地 detector-lite 调参、等待真实 TextBoxes / BubbleMask / SegmentMask、模型地板或渲染锁。该报告不新增 OCR / LLM / PNG，不使用 ground truth 决定 route / nextAction / gate / candidate family verdict，不替换主 OCR、`finalTextUsedForTranslation`、翻译输入、覆盖图、`blockPassed`、失败分类、`textRegionCropReport.adoptedCount`、active artifacts 或 `configuration.currentBlockSource`，`proxyNotRealKoharuTextBoxes = true` 且 `proxyNotRealKoharuOCR = true`。
- `koharuNativeBubbleMaskInstanceLiteReport`：v1.43 新增的 Koharu Native BubbleMask Instance-Lite 像素实例掩码影子复刻。它在 v1.42 closed-loop 后、最终 convergence 前运行，只用源图像内容裁切区像素、现有 bubble geometry、final blocks、glyph / SegmentMask proxy、BubbleIndex / DistanceField / seam / RenderSprite / detector-lite closed-loop 证据生成近白连通域 instance-lite mask 账本，输出实例、逐块 majority ID 归属、由实例像素 erosion / projection 派生的 safe rect 对照、同 instance 多 block 的 block-scoped safe rect policy、block-scoped sprite containment preview、same-instance sibling sprite collision preview、sibling / adjacency 和 nextAction。单块可使用 mask-derived safe rect；同 instance 多块只在报告里保留各自 seed rect，避免把一个最大 safe rect 共享给 siblings；render non-transparent bounds 用于检查是否落在 block-scoped safe rect 内，并统计同 instance 多块 sprite bounds 是否互相重叠。该报告不新增 OCR / LLM / PNG，不创建 active `test/koharu_artifacts/`，不把 instance-lite 冒充真实 Koharu `BubbleMask`，不写回主 OCR、翻译输入、覆盖图、`safeLayoutRect`、DistanceField safe rect、`blockPassed`、失败分类、renderer 或 `configuration.currentBlockSource`，`proxyNotRealKoharuBubbleMask = true` 且 `nativeInstanceLite = true`。
- `koharuNativeSegmentMaskRefinementLiteReport`：v1.44 新增的 Koharu Native SegmentMask Refinement-Lite 文字像素掩码影子复刻。它在 v1.43 instance-lite 后、最终 convergence 前运行，只用源图像像素、detector-lite TextBox 候选、final blocks、v1.43 instance-lite BubbleMask、现有 glyph / SegmentMask proxy、render lock 和翻译失败分类，生成 TextBox 约束的文字像素 mask refinement 账本。报告输出 candidate ledger、逐块 block ledger、same-bubble sibling overlap ledger 和 gate；candidate / block ledger 记录来源 TextBox candidate verdict、shadow eligibility、block overlap、same-bubble relation、accepted/fallback/rejected linkage verdict、mask 对 TextBox / Bubble 的 containment ratio，以及基于 v1.43 instance-lite ledger 的 majority agreement。它不新增 OCR / LLM / PNG，不接 active artifact，不把 refinement-lite 冒充真实 Koharu `SegmentMask`，不写回主 OCR、翻译输入、覆盖图、`safeLayoutRect`、`glyphMaskFillRects`、背景填充、renderer、`blockPassed`、失败分类、`textRegionCropReport.adoptedCount` 或 `configuration.currentBlockSource`，`proxyNotRealKoharuSegmentMask = true` 且 `nativeRefinementLite = true`。
- `koharuNativeArtifactBundleLiteReport`：v1.45 新增的 Koharu Native Artifact Bundle-Lite 结构一致性闭环。它在 v1.44 refinement-lite 后、最终 convergence 前运行，只消费 final blocks、detector-lite / shadow OCR / refinement / closed-loop、BubbleMask instance-lite、SegmentMask refinement-lite、render fit / render lock、translation model floor 和 external readiness，组装每块 TextBox / BubbleMask / SegmentMask / OCR / Translation / Render 的 report-only bundle、consistency edges 和 worklist。该报告不新增 OCR / LLM / PNG，不接 active artifact，不替换主 OCR、翻译输入、覆盖图、`blockPassed`、失败分类、renderer 或 `configuration.currentBlockSource`；ground truth 只进入 evaluation signals，`nativeBundleLite = true`，且 TextBoxes / BubbleMask / SegmentMask 均明确标记为 proxy-not-real Koharu artifacts。
- `koharuNativePromotionGateLiteReport`：v1.46 新增的 Koharu Native Promotion Gate-Lite 探针驱动晋级门槛。它在 v1.45 bundle-lite 后、最终 convergence 前运行，只消费当前探针内存中的 final blocks、diagnostics、v1.39-v1.45 native-lite reports、render lock、render fit、translation model floor、clean text diagnostic 和 external readiness，为每块输出 TextBoxes / BubbleMask / SegmentMask / OcrText / Translations / RenderedSprites / FinalRender 的 report-only 晋级状态、stage gates、candidate export preview、work items 和 gate ledger。该报告不新增 OCR / LLM / PNG，不更换模型，不创建或修改 active `test/koharu_artifacts/`，不替换主 OCR、翻译输入、覆盖图、`blockPassed`、失败分类、renderer 或 `configuration.currentBlockSource`；ground truth 只进入 evaluation signals，candidate export 只是 JSON/TXT 预览，不能写出 active artifact。
- `koharuNativeArtifactContractDryRunReport`：v1.47 新增的 Koharu 四件套 artifact contract dry-run。它在 v1.46 promotion gate 后生成，把 candidate export preview 映射到 `test/koharu_artifacts/1.manifest.json`、`1.textboxes.json`、`1.bubbles.json`、`1.segment_mask.json` 的必需字段、禁止来源和 validator 命令，并联动 `koharuArtifactConvergenceReport` 的 reference report、work item 和 gate；v1.80 起 required manifest 字段包含 `sourceImageSHA256=<runtime test/1.png sha256>`，App-side identity gate 也要求 `sourceImageSHA256Matches=true`；只写 JSON / TXT，不创建或修改 active artifact，不新增 OCR / LLM / PNG，不把 native-lite / proxy 预览导出为真实 Koharu artifact，`activeExportAllowed = false`。
- `koharuArtifactIdentityReconciliationReport`：v1.68 新增的 artifact identity reconciliation 账本。它只消费 App 侧 `artifactIdentityReceipt` 和 contract dry-run required files，把 SourceImage + 四件套的 App size / SHA256 对齐到 `ci-artifact-manifest.koharuArtifactValidationIdentitySummary` 字段路径，并联动 convergence 的 `WI-koharu-artifact-identity-reconciliation` / `G-koharu-artifact-identity-reconciliation-ready`；v1.80 起顶层还输出 `sourceImageSHA256Declared`、`sourceImageSHA256Expected`、`sourceImageSHA256Matches`，且只有 match 为 true 才允许 `readyForCIManifestComparison=true`；不读取 CI manifest、不创建或修改 active artifact、不新增 OCR / LLM / PNG、不改变主流程。Actions 在真实 artifact 注入探针后会把 validator identity 与 App rows 做 size/SHA256 比对并写入 `koharuArtifactIdentityReconciliationMatch`。
- `preCropTextBoxPlanReport`：TextRegion crop 前生成的 Koharu 式上游 TextBox plan artifact。每块最多保留 3 个 plan，使用 fused seed bbox、BubbleMask majority、subRegion、split candidate、safe rect 和 glyph/SegmentMask proxy 等无真值信号排序；只用于 shadow OCR，不替换 `finalTextUsedForTranslation`。
- `cropExperimentReport`：TextRegion crop 的 shadow-only 实验矩阵。control 使用当前 TextRegion crop，每块最多额外跑 3 个候选；v18 起优先使用 `preCropTextBoxPlan.*` 作为 shadow 来源。`bestShadowCandidate` 只进入 JSON/TXT 报告，不替换 `finalTextUsedForTranslation`，也不放宽 `textRegionCropReport.adoptedCount`。
- `textBoxPlanFailureReport`：v19 新增的 plan / candidate / block 三级失败归因和晋级门槛审计。它用 `sourcePlanID` 关联 pre-crop plan 与 shadow OCR candidate，记录 promotion checks、blockers、primary failure category 和 recommended action；只解释为什么 `betterThanControl` 未晋级，不改变 `finalTextUsedForTranslation`、主覆盖图或 `adoptedCount`。
- `lineTextBoxPlanReport` / `lineCropExperimentReport`：v20 新增的 Koharu 式行级 TextBox / deskew shadow 验证层。目标块动态来自 `textBoxPlanFailureReport.continueGeometryResearchBlocks`，当前为 `[1, 6, 10]`；每块最多 4 个 line-level plan，候选变体以 `lineTextBoxPlan.*` 开头，只进 shadow OCR 和报告，不写回 `finalTextUsedForTranslation`、主覆盖图、`blockPassed` 或 `textRegionCropReport.adoptedCount`。
- `externalArtifactReadinessReport`：v21 / v1.11 新增的真实 TextBoxes / BubbleMask / SegmentMask artifact 适配前证据闸门。它只解析 `test/koharu_artifacts/` 下 manifest 和外部 JSON，做 schema、坐标、bbox 和 block alignment 校验；没有真实 artifact 时必须输出明确阻塞，不把现有 Vision OCR、pre-crop plan 或 line plan 伪装成 detector 输出。v1.12 新增 `md/koharu研究/artifact_contract/` 契约、非活动 examples 和 `scripts/validate-koharu-artifacts.py` 离线 validator；v1.14 validator 额外输出 `requiredFiles`、`nextAction` 和 `readinessBlockers`，CI 结果包 manifest 会汇总 active artifact validation、App 侧 readiness 和 shadow OCR 状态；v1.65 validator 额外输出 `orientationMetadataSummary`。示例 manifest 必须带 `contractExampleOnly=true`，即使误放到 active 目录也不能得到 `readyForShadowOCR`。当前 validator 和 Swift readiness 会硬拦 `schemaVersion` 缺失/不匹配、manifest path 使用绝对路径或 `..` 逃逸 active 目录、缺 `sourceImage`、缺 / 非 64 位 hex / 不匹配 runtime `test/1.png` 的 `sourceImageSHA256`、缺或非布尔 `contractExampleOnly`、TextBox 可选方向元数据非法，以及 active manifest 的 `generatedBy` 缺失或声明为 manual / fixture / Vision OCR / proxy / ground truth / handwritten 来源。
- `externalTextBoxShadowOCRReport`：v1.13 新增的 external TextBoxes shadow-only OCR 接入口。只有 readiness 完整时才执行，选择只使用 bbox IoU、中心点包含、confidence、bubble alignment 和面积比例等无真值信号。v2.0 使用稳定最大基数二分匹配保证 block / TextBox 一对一并记录完整 outcome partition；v2.1 再把 assignment geometry 与 OCR outcome 分账，只有中心包含或 `IoU >= 0.10` 且 block / TextBox external Bubble ID 相同才计入 trusted geometry。weak overlap 和缺 Bubble 的 unknown assignment 可继续 shadow OCR，但不得关闭 coverage gate。结果仍只写报告 / TXT，不替换 `finalTextUsedForTranslation`、主覆盖图、`blockPassed` 或 promotion。
- `fusionComparison.postFusionCleanup.rejectedBlocks[]`：v1.18 起会为保守重复/碎片拒绝记录 `reason`、`relatedKeptBlockIndex`、`qualityScore`、`protectedTextMatched` 和 ground-truth-free `evidence`。保护文本和 decorative 标题不能因为短或像碎片被误删。
- `cleanTextDiagnostic` / `output/clean_text_diagnostic.json`：跳过 OCR，直接把 `test/1.ground_truth.json` 中的 dialogue 真值送入当前翻译链路，用于判断失败来自 OCR 噪声还是当前 Local 模型/判定链路。v1.29 起 `translationModelFloorComparisonReport` 会在其后运行 strict clean text 变体对照，但不替换 clean text baseline 或主流程 prompt。
- `overallPassed`：至少 1 个块、所有块通过质量判定、两张 PNG 非空才为 `true`。
- `outputDirectoryCleaned` / `retainedOutputFiles` / `outputCleanupPolicy`：记录本轮输出目录是否按清理策略重建，以及本轮最终保留的 PNG/JSON 文件名。

探针验收重点：

- `probe_report.json` 不应包含广告横幅、地址栏、翻页导航、系统状态栏等浏览器 UI 文本。
- `1_debug_boxes.png` 中同一对话框不应出现密集堆叠红框；一个气泡通常对应一个块。
- `1_translated_overlay.png` 中所有绘制文本必须正向可读；即使某块来自旋转 OCR，也不允许倒置或镜像。
- `blockPassed = false` 的块也必须出现在覆盖图上，并保留失败原因，不能静默隐藏。
- 每次运行会先清空 App 沙盒 `Application Support/AITRANS/Output/`，`scripts/export-probe-output.sh` 也会先清空项目根 `output/`，避免新旧 PNG / JSON 混在一起。
- 输出包括 `1_debug_boxes.png`、`1_translated_overlay.png`、`1_ocr_text_overlay.png`、`1_deterministic_correction_overlay.png`、`1_deterministic_translation_overlay.png`、`1_block_crops.png`、`1_preprocessed_content.png`、`1_bubble_debug.png`、`1_bubble_seed_debug.png`、`1_bubble_crops.png`、`1_bubble_text_overlay.png`、`1_probe_contact_sheet.png`、`1_ocr_probe_text.txt`。其中 `1_block_crops.png` 是块裁切放大预处理拼图，用于目测二值化/锐化是否过激；`1_deterministic_correction_overlay.png` 用于直接对比原 OCR 和确定性纠错候选；`1_deterministic_translation_overlay.png` 用于查看“纠错后再翻译”是否通过；`1_bubble_text_overlay.png` 把 bubble-first OCR 文本贴回原图，方便和全图 OCR overlay 并排看；`1_probe_contact_sheet.png` 把全图 OCR、气泡 OCR、气泡裁切、翻译覆盖和纠错对照拼成 2 列总览；`1_ocr_probe_text.txt` 是每块 OCR、纠错候选、raw output、候选译文、失败原因、质量备注和判定轨迹的纯文本快照，便于不用 `jq` 也能排查 OCR 原句。
- 翻译失败排查规范：先看 `failureCategory`，再看 `rawOutputClassification` 和 `candidateClassification`。如果 `failureCategory = ocrInputSuspect`，优先修 OCR/合并/裁切；如果是 `modelOutputFailure`，优先换模型、调采样或 prompt；如果是 `translationLanguageQualityFailure`，说明模型给了中文或半中文，但候选本身过短、混入未翻译英文或像解释文本；如果是 `ruleFalseFailureSuspected`，才优先放宽判定规则。不要只看覆盖图猜测失败原因。
- 翻译规则排查规范：如果 `likelyRuleFalseFailureBlocks = []`，说明本轮没有发现“真实中文译文被规则误杀”。`cjkButFailedCandidates` 只表示“候选含中文但未过端到端质量门”，需继续看 `cjkFailureBreakdown`；中文候选存在不等于通过，硬通过前还会检查解释/列表型输出、长原文短译文、中英混排和 OCR 输入质量。
- OCR 质量排查规范：先按 `ocrGroundTruthSimilarity` 从低到高看 `blocks[].finalTextUsedForTranslation`。本探针用 `test/1.ground_truth.json` 做真值；换测试图时应同步更新真值文件，否则相似度只作参考。
- 可信准确率规范：只看 `groundTruthMatch = matched` 的块；核心对话和 `decorative` 装饰标题分开统计。`unmatched` 块必须保留在明细里，但不能混进平均准确率。旧版 `accuracyVsGroundTruth = 0.8378 / 0.8755` 使用了不完整真值和过宽相似度，只能作为历史对照，不能再作为验收数字。
- 干净文本诊断规范：如果 `cleanTextDiagnostic.passRate` 仍低，说明即使没有 OCR 噪声，当前翻译模型/输出风格也不稳定；这时不要只调 OCR 或放宽质量规则。
- 解码规范：用户实际翻译仍使用 `sampled` 路径，llama.cpp 采样链为 top-k/top-p/min-p + `temperature = 0.2` + 随机 seed；漫画探针、`clean_text_diagnostic`、逐块 raw 翻译、确定性纠错翻译对照和 tagged batch 诊断使用 `deterministic` 路径，固定 `seed = 42` 并走 `temperature = 0` + greedy 解码。`probe_report.json` 顶层、`configuration`、`cleanTextDiagnostic` 和 `batchTranslationComparison` 会记录 `decodingMode` / `decodingSeed`。
- 跨版本指标规范：版本历史、关键决策和验证结果统一写入 `update_log.md`。涉及漫画探针或翻译链路的可量化版本，推荐先跑完整探针并导出 `output/`，再执行 `python3 scripts/append-version-metrics.py --version vN --notes "..."`。`metrics/version_history.csv` 不放在 `output/`，不会被 `scripts/export-probe-output.sh` 清理；不要覆盖或删除历史行。

模拟器跑完后，把沙盒输出导出到项目根 `output/`：

```sh
scripts/export-probe-output.sh
```

如需指定设备：

```sh
scripts/export-probe-output.sh booted
```

也可用 DEBUG 环境变量自动触发，适合命令行探针：

```sh
AITRANS_RUN_MANGA_PROBE=1
```

空目录预期结果：

- `运行 test/ 音频`：显示 `test/ 未找到可测试音频`。
- `运行 test/ OCR`：显示 `test/ 未找到可测试图片`。

模型文件不放进仓库。模型页可以直接下载内置最小模型，也可以手动 `导入 GGUF`。内置模型固定为：

- `Gemma 3 270M IT QAT Q4_0`
- 下载地址：[`ggml-org/gemma-3-270m-it-qat-GGUF`](https://huggingface.co/ggml-org/gemma-3-270m-it-qat-GGUF)
- 文件：`gemma-3-270m-it-qat-Q4_0.gguf`
- 大小：`241,410,624 bytes`，约 230 MB
- SHA256：`3626e245220ca4a1c5911eb4010b3ecb7bdbf5bc53c79403c21355354d1e2dc6`

App 下载时会写入临时 `model.gguf.download`，成功校验后原子替换为 `model.gguf`。同名模型只保留一个；如果已安装，点击下载不会重复保存。`移除模型` 会删除 `model.gguf` 和未完成的临时下载文件。

无论内置下载还是手动导入，模型都会复制到 App 沙盒内并统一命名为：

```text
Application Support/Models/Gemma-1.5B/model.gguf
```

如果没有这个文件，界面会显示 Local 未就绪。普通翻译会临时回退 Mock，避免界面卡死；LLM 接口自测和诊断会明确提示缺少模型。`移除模型` 只删除 App 沙盒中的 `model.gguf` 和临时下载，不影响原始文件或远程模型。

## 本地 LLM 模型准备

当前项目先按 `llama.cpp + GGUF` 方向接入。原因是 `llama.cpp` 官方仓库带有 `examples/llama.swiftui`，说明它是一个在 iPhone 上运行本地推理的 SwiftUI 示例；而本项目的模型导入器已经限制 `.gguf` 文件。MLC LLM 的 iOS 路线也可行，但它需要 `mlc_llm package` 生成 runtime、tokenizer 和已转换/编译的 MLC 权重，不是直接导入 `.gguf`。

先下载其中一个 `.gguf` 到 Mac：

- 首推翻译冒烟：[`Qwen/Qwen2.5-0.5B-Instruct-GGUF`](https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF)，文件选 `qwen2.5-0.5b-instruct-q4_k_m.gguf`，约 469 MB。体积仍小，中文/英文测试更稳。
- 极小体积冒烟：[`unsloth/SmolLM2-135M-Instruct-GGUF`](https://huggingface.co/unsloth/SmolLM2-135M-Instruct-GGUF)，文件选 `SmolLM2-135M-Instruct-Q4_K_M.gguf`，约 101 MB。适合测加载和接口，不适合判断翻译质量。
- 最小 Gemma 路线：[`ggml-org/gemma-3-270m-it-qat-GGUF`](https://huggingface.co/ggml-org/gemma-3-270m-it-qat-GGUF)，文件选 `gemma-3-270m-it-qat-Q4_0.gguf`，约 230 MB；或 [`ggml-org/gemma-3-270m-it-GGUF`](https://huggingface.co/ggml-org/gemma-3-270m-it-GGUF) 的 `Q8_0` 版本。

Mac 机外先测：

```sh
brew install llama.cpp

llama-cli \
  -m ~/Downloads/qwen2.5-0.5b-instruct-q4_k_m.gguf \
  -p "Translate to Simplified Chinese: Keep the model on device." \
  -n 128
```

如果想让 `llama.cpp` 直接从 Hugging Face 拉模型，也可以先试：

```sh
brew install llama.cpp
llama-cli -hf Qwen/Qwen2.5-0.5B-Instruct-GGUF:Q4_K_M \
  -p "Translate to Simplified Chinese: Keep the model on device." \
  -n 128
```

放进 App 测试时，不需要手工改名。运行 App 后进 `模型` -> `下载 Gemma`，或 `导入 GGUF` 选择下载好的 `.gguf`，App 会复制并命名为 `model.gguf`。

当前已用 `gemma-3-270m-it-qat-Q4_0.gguf` 做过命令行冒烟：

```sh
llama-cli -m llm/gemma-3-270m-it-qat-Q4_0.gguf \
  -st --no-display-prompt --no-warmup --no-perf \
  -n 80 --temp 0.1 \
  -p "Translate to Simplified Chinese. Output only the translation: Keep the model on device so private meeting content never leaves the phone."
```

结果：模型能正常加载并生成，速度约 130 tokens/s，但输出容易复读英文原句或 prompt，不稳定翻译成中文。因此它适合验证 GGUF 下载、加载、App 接口和闪退风险，不适合作为翻译质量测试模型。要验证翻译质量，优先换 `Qwen2.5-0.5B-Instruct-GGUF` 的 `q4_k_m` 文件。

如果本地需要重建 iOS `llama.xcframework`：

```sh
git clone --depth 1 https://github.com/ggml-org/llama.cpp.git third_party/llama.cpp
bash Tools/build-llama-ios-xcframework.sh
```

## 大模型接入点

- `AITRANS/Models/TranscriptModels.swift`
  - `LocalLanguageModeling` 是统一模型协议。
  - `ModelGenerationRequest` 包含任务类型、语言、提示词、上下文和采样参数。
  - `ModelGenerationResult` 返回文本、摘要、引擎名、token 数和耗时。
  - `ModelStreamEvent` 和 `LocalLanguageModeling.stream(_:)` 预留逐 token 流式输出接口；默认实现会把一次性生成结果包装成流式事件，真实推理层可覆写。
- `AITRANS/Services/MockGemmaService.swift`
  - 当前模拟输出，用于没有 GGUF 时测试 UI、历史和回退路径。
- `AITRANS/Services/GemmaLocalService.swift`
  - 真实本地模型层，使用 `llama.cpp` 的 `llama.xcframework` 加载沙盒中的 `model.gguf` 并生成。
- `AITRANS/Services/LlamaRuntime.swift`
  - 封装 llama.cpp C API，负责加载 GGUF、分词、逐 token 生成、UTF-8 拼接和运行时锁。
- `AITRANS/Services/TranslationSessionStore.swift`
  - 负责页面共享状态、本地 JSON 存储、导入/导出、历史清理、自检、Mock/Local 回退和生成请求组装。

真实模型替换时，优先换 `model.gguf` 或调整 `GemmaLocalService` 的 prompt/采样参数，不需要改 UI 和历史数据结构。

## 后续对话指引

- 新开对话时，先读本 README，再读 `git status --short` 和最近 5 条 `git log --oneline`。
- 排查翻译问题时，先用模型页 `运行接口自测` 和开发页 raw 探针确认输入、输出、错误，再改 prompt 或清洗逻辑。
- 英译中优先用这些探针句测试：`The meeting starts at 9:30 tomorrow.`、`Keep the model on device.`、`Save the transcript locally.`。
- 中译英优先用这些探针句测试：`请把会议记录保存在本地。`、`明天九点半开始会议。`。
- 当前内置 Gemma 270M 适合验证下载、加载、接口和闪退风险，不适合作为翻译质量基准；质量验证优先换 `Qwen2.5-0.5B-Instruct-GGUF` 的 `q4_k_m`。
- 每次功能更新或 bug 修复后，都要在 `update_log.md` 追加简短记录，写清改了什么、验证了什么、还有什么风险；涉及漫画探针或翻译链路的可量化版本，再 append-only 追加 `metrics/version_history.csv`，便于后续对话继承上下文和画趋势。

## 当前验证

- `plutil -lint AITRANS/Resources/Info.plist AITRANS.xcodeproj/project.pbxproj` 通过。
- `jq empty AITRANS/Resources/Assets.xcassets/.../Contents.json` 通过。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild ... generic/platform=iOS Simulator ... CODE_SIGNING_ALLOWED=NO build` 通过。本次构建日志里 CoreSimulatorService 有沙盒警告，但构建最终成功。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild ... generic/platform=iOS ... CODE_SIGNING_ALLOWED=NO build` 通过。
- 已确认 Debug iOS Simulator app bundle 内嵌 `llama.framework`。
- `git diff --check` 通过。
- `test/1.png` 漫画覆盖探针已在 iPhone 17 Pro 模拟器运行并导出：`output/probe_report.json`、`output/1_debug_boxes.png`、`output/1_translated_overlay.png` 均非空。调试图框线明显；覆盖图能盖住部分原文并绘制译文，但受 OCR 小块切分和当前 Local GGUF 翻译质量影响，结果仍不适合作为最终产品效果。
