# 测试规范
本文指导 Agent B 和 Agent C 选择 AITRANS 的验证层级。默认云端快验、本机只做轻量检查；只有人工明确要求“本机测试 / 本地 build / 本地跑探针 / 本地 xcodebuild”时，才把本机 Xcode build 或漫画探针作为默认验证路径。

## 0. 默认验证策略
- Agent B 默认本地只跑 `git diff --check`、JSON 解析、YAML smoke 等轻量检查。
- Swift / Xcode / 漫画探针相关任务完成后，默认集中 push 到 `codeb/vX.Y-短标题`，由 GitHub Actions 对核心 commit 执行一次 task-scoped full；需要探针重验证时手动 `workflow_dispatch` 选择 `ci-fast` 或 `full`。
- Agent C 只验收与 `codeb/...` HEAD commit 完全一致的云端结果包，不只看 Agent B 的文字说明。
- 加密打包 workflow 只在软件包交付时手动触发，不随 merge 自动 archive，也不作为 Agent C 验收依据；Agent C 使用独立未加密 CI 结果包。
- 如果云端验证失败，Agent C 按 `ci-failure-summary.md`、`xcodebuild.log`、`junit.xml`、`.xcresult` 和 manifest 输出退回清单，Agent B 修复后继续 push。
- 如果云端环境缺少模拟器、GGUF、App 容器权限或外部 artifact，必须说明哪个测试未运行、缺什么依赖、是否影响验收、需要人工提供什么。
- GGUF 云端模型只在手动 `ci-fast` / `full` 探针中通过 GitHub Release `model-gemma-3-270m-it-qat-q4_0-v1` 下载，并用 SHA256 `3626e245220ca4a1c5911eb4010b3ecb7bdbf5bc53c79403c21355354d1e2dc6` 校验后缓存到 `.ci-models/`；本规范不要求提交 GGUF。
- 云端漫画探针复用同一次 Debug simulator build 产物安装 App，把 `.ci-models/gemma-3-270m-it-qat-Q4_0.gguf` 复制为 App sandbox `Application Support/Models/Gemma-1.5B/model.gguf`，再用 `AITRANS_RUN_MANGA_PROBE=1` 和 `AITRANS_MANGA_PROBE_MODE` 启动 App 并导出 `output/`。`Gemma-1.5B` 是历史目录名；验收实际模型时看 asset 名、字节数和 SHA256。
- `AITRANS CI Results` 的候选核心 push 默认 `validationProfile=full`、`probe_mode=skip`，按任务运行基础静态、相关领域契约与必要 Xcode build；不下载 GGUF、不创建模拟器、不安装 App、不跑漫画探针。PR/已验证 merge 使用 `validationProfile=fast`，跳过 Xcode 和领域大套件。例外：只要填写 Koharu artifact archive，`probe_mode` 必须为 `ci-fast` 或 `full`。
- `probe_mode=skip` 或云端探针失败时，CI 结果包不得复制仓库里已有的旧 `output/probe_report.json` / `clean_text_diagnostic.json` / `1_ocr_probe_text.txt` 当成本次产物；只能保留 `output/probe-not-run.txt` 和 manifest skip / failure reason。只有 `probe_mode != skip` 且 `manga_probe` 成功时才复制本轮 `output/`。
- full CI 先按 changed files 路由 Speech、UI、文本首页和 Koharu 契约；Speech 领域包含 run-id contract、v1.95 质量 contract、纯 Swift evaluator 和 corpus validator。App 相关 full 才跑 Xcode，非 App full 可写 `xcodeBuildRequired=false`。fast 必须写 `fast_followup_reuses_candidate_full_validation` skip reason，不能当作新的编译证据。
- `AITRANS CI Results` checkout 至少保留最近 2 个提交，确保普通单提交 push 能 diff 到 `github.event.before`；若一次 push 含多提交导致 before commit 不在浅克隆内，workflow 必须先定向 fetch `github.event.before` 再 diff。只有 checkout 和 targeted fetch 都拿不到 before commit 时，才允许把 `changed-files.txt` 回退成全仓列表；manifest / failure summary 必须记录 `scopeDiffMethod`、`scopeDiffBaseSha` 和 `scopeDiffFallbackUsed`。
- Koharu artifact validator 只在 Koharu 领域 full 中运行；完整 invalid fixture 矩阵限 validator、artifact contract、artifact injection 或 CI workflow 相关 full。Speech、普通 UI、PR 和 merge fast 不运行该套件。
- 手动注入 Koharu artifact archive 且运行 `ci-fast/full` 时，云端 smoke 必须核对 archive / App / CI 的四件套 identity、source image SHA、dry-run 和 reconciliation 完整匹配。external shadow OCR 除旧的 executed / candidate / OCR count sanity 外，还必须满足 TextBox 与 Bubble ID 非空唯一、matched / succeeded / failed / skipped 分区一致、`duplicateAssignedTextBoxIDs=[]`、`coverageVerdict=complete`、`successfulCoverageRatio=1`，以及 `minimumTrustedIoU>=0.10`、geometry weak/unknown Bubble blocks 为空、`geometryCoverageRatio=1`、`geometryCoverageVerdict=complete`；否则 convergence 的 `WI/G-external-textbox-shadow-ocr-coverage` 不得 closed / passed。不能只用 Release 下载、SHA、validator 日志、`readyForShadowOCR` 或任意一个 OCR 成功作为 App 已完整消费 artifact 的证据。
- 若注入的真实 TextBox 带 `sourceDirection`、`linePolygons` 或 `rotationDegrees`，还必须核对 validator / manifest 的 `koharuArtifactValidationOrientationSummary`，以及 `externalTextBoxShadowOCRReport.orientationReadinessVerdict`、`orientationShadowPathNeededBlocks`、`orientationShadowPathExecutedBlocks`、`orientationShadowPathPartialBlocks`、`orientationShadowPathNotExecutedBlocks`、`orientationUnsupportedBlocks`、`orientationUnsupportedReasonBreakdown`、候选 `orientationAttemptedRotations`、`orientationSelectedRotation`、`orientationRecognitionLanguages`、`orientationUnsupportedReason`、`deskewExecuted`、`riskFlags/blockers`、`koharuArtifactConvergenceReport` 的 `WI-external-textbox-shadow-ocr-coverage` / `G-external-textbox-shadow-ocr-coverage` 和 `WI-external-textbox-orientation-shadow-path` / `G-external-textbox-orientation-shadow-path`，以及 `1_ocr_probe_text.txt` 的 coverage / orientation / app-side identity 摘要。v1.64 支持竖排或接近 90/180/270 度 TextBox 的有上限 rotation shadow OCR；v1.92 候选支持合法四点 line polygon 透视校正，只有 warp 成功执行才允许移除 line polygon blocker；任意角度 deskew 与 warp 失败仍必须作为 unsupported / convergence blockers。v1.69 要求 ready artifact 后有 executed shadow OCR、`candidateCount > 0`、`ocrExecutedCount > 0`、`ocrSucceededCount > 0` 且未闭合时 coverage gate 为 blocked；v1.66 要求 coverage gate 同时拿到 contract dry-run ready 与 CI identity；v1.67 要求 App 侧 runtime identity receipt 完整。
- v1.97 额外要求多行 polygon 逐行隔离：partial 成功必须保留逐行失败原因、`linePolygonWarpPartialFailure` 与 `externalArtifact.linePolygonWarpPartial`，可供 shadow 对照但不得 promotion；只有全部行失败才整块 bbox fallback。`scripts/test-v192-koharu-line-polygon-warp-contract.py` 必须锁定这些边界。
- v1.99 候选要求 Python validator 与 Swift readiness 都验证每个 line polygon point 属于其 TextBox bbox，统一容差为 `min(8px, max(2px, bbox 短边 2%))`；容差外写 `linePolygonOutsideTextBoxBBox:<polygon>:<point>` 并阻止 `readyForShadowOCR`。`scripts/test-v199-koharu-line-polygon-containment-contract.py` 必须覆盖 bbox 内、容差边缘、部分越界、完全脱离、invalid fixture 和 CI 接线。
- v2.0 候选要求 external TextBox shadow OCR 使用稳定最大基数一对一匹配；TextBox ID 缺失/重复必须在 validator 与 App readiness 阻塞。报告的 succeeded / failed / skipped 必须互斥并覆盖全部 block，最终不得有重复 TextBox assignment；只有全部 block 成功且 `successfulCoverageRatio=1` 才允许 coverage gate passed。`scripts/test-v200-koharu-shadow-coverage-contract.py` 必须编译并执行 `scripts/test-v200-koharu-shadow-coverage-evaluator.swift`，覆盖增广重分配、单 TextBox 争用、complete / partial / no-success / duplicate / invalid partition、旧报告 Codable 兼容、ID 门槛和 CI/TXT 接线。
- v2.1 候选在 v2.0 outcome coverage 之外增加 geometry coverage。`scripts/test-v201-koharu-geometry-coverage-contract.py` 必须编译执行真实 Swift evaluator，覆盖 `IoU=0.009` 拒绝、`0.011` weak、`0.10` trusted、center-contained trusted、Bubble conflict / unknown、OCR 与 geometry ledger 正交、全 strong complete、旧报告 Codable、Bubble ID Python/Swift reason parity、invalid fixture、TXT 与 CI manifest/gate 接线。
- v2.2 候选要求 PhotosPicker transfer 从选择开始即由 Store 的图片 task ID 持有，新照片和文件导入可抢占运行中任务；取消、清空、新选择和文件 selection UUID 必须拒绝旧成功、旧失败与 nil 回调。`scripts/test-v202-image-import-run-isolation-contract.py` 必须编译执行纯 Swift evaluator，覆盖 A/B 反序完成、照片/文件交错、nil 显式失败、task identity 后置校验、同名 sandbox 隔离、未采用输入清理、新任务不继承旧 retry source、取消后当前源可重试，以及 View 不创建 transfer Task 或直接写业务状态。该契约与 v1.87 UI interaction contract 必须写入同一 CI 日志并共同阻塞候选 full。
- v2.3 候选要求图片取消后的 Retry 与实际 source 生命周期一致。`scripts/test-v203-image-cancel-retry-contract.py` 必须编译执行纯 Swift evaluator，证明 source 已发布后的取消可重试、尚未发布 source 的取消不可重试、pipeline failure 只有保留 source 才可重试、clear / translated 不显示 Retry，并锁定 cancel 不删除 source、clear 必须删除 source。v1.87 / v2.2 / v2.3 三套 UI contract 必须在 `set -euo pipefail` 的同一步中共同阻塞候选 full。
- v2.4 候选要求普通图片稳定导出与 Store 状态同生命周期。`scripts/test-v204-image-export-lifecycle-contract.py` 必须编译执行纯 Swift evaluator，覆盖新 Store 启动清理、新任务替换、clear、cancel、retry、模式重渲染、A/B stale staging、当前 render failure、删除失败重试，以及同目录 source / staging / 目录外 / 嵌套 / `..` escape / symlink / dangling symlink 拒绝。启动时必须接管上次进程遗留的稳定导出；新任务、clear 和重渲染必须通过统一 discard 立即撤销公开 export URL；两个真实 publish 点都必须经过 ownership wrapper，只有 wrapper / discard 可写公开 URL。只有直属、非隐藏 `*-translated.png` 常规文件可删，删除失败必须保留私有 ownership 供后续重试；cancel 仍保留 retry source。v1.87 / v2.2 / v2.3 / v2.4 四套 UI contract 必须在 `set -euo pipefail` 的同一步中共同阻塞候选 full。
- v2.5 候选要求图片 workspace 在 App 异常退出后可安全恢复。`scripts/test-v205-image-workspace-recovery-contract.py` 必须编译执行纯 Swift evaluator，覆盖 task UUID input、render UUID staging 和 `aitrans-export-<render UUID>-<base>-translated.png` 稳定 export 的启动清理、普通 `*-translated.png` 与 task UUID source 不误删、任意文件名 / wrong-kind / nested / outside / symlink / dangling symlink 拒绝，以及启动和运行期删除失败 ownership 重试。`performsStartupWork=false` 不得扫描 workspace；正常 input/staging 清理的每个调用点必须传入 Store 的 `imageTranslationDirectory` 或同一捕获目录，不得从待删 URL 反推可信根。v2.4 无 marker 的 legacy export 不允许用模糊后缀自动迁移；其升级残留必须显式记录。v1.87 / v2.2 / v2.3 / v2.4 / v2.5 五套 UI contract 必须在 `set -euo pipefail` 的同一步中共同阻塞候选 full。
- v2.6 候选要求系统分享使用人类可读文件名，同时不暴露内部 export marker / render UUID。`scripts/test-v206-image-share-lifecycle-contract.py` 必须编译执行纯 Swift evaluator，覆盖专用 `ImageTranslationShares/<share UUID>/<base>-translated.png` 创建、hard-link + copy fallback、dismiss 清理、启动恢复、A/B 反序拒收、outside / nested / 任意目录 / symlink / dangling symlink 拒绝和删除失败重试。View 只能调用 Store prepare/finish，不得直接使用 FileManager；Store request ID 必须拒绝旧文件结果，View presentation ID 必须拒绝旧 Task 用 `nil` 关闭新 sheet；新任务、clear、重渲染和 export URL 失效必须清理分享目录。v1.87 / v2.2 / v2.3 / v2.4 / v2.5 / v2.6 六套 UI contract 必须在同一 fail-fast step 阻塞候选 full。
- v2.7 候选要求普通图片页显式提供输入语言，并把输入/目标语言作为 task-scoped 内容凭据；跨页全局修改不能污染在途、失败或取消内容，清空才重置，已完成图片改输入语言必须从 Store-owned source 重跑 OCR + 翻译，失败/取消保留态改输入语言只更新下次 Retry 凭据，源文件缺失时不得重标旧内容。`scripts/test-v207-image-ocr-direction-contract.py` 必须编译并直接链接产品 `ImageOCRLayoutEngine` 执行纯 Swift evaluator，覆盖乱序横排、交错双栏横排回并、两列竖排右到左/列内上到下、mixed direction 不互并、比较器链输入乱序确定性、同行单字 CJK 碎片不误升竖排、孤立单字/近方形 unknown 和非 CJK 高框 fallback；所有小型 fixture 应穷举输入排列。产品路径只有 CJK prior + bbox 高宽比 `>=1.6` + 高度 `>=0.035`，并包含多字 CJK run 或存在同列邻居且没有近同行邻居时才走 vertical；低证据保持 horizontal/unknown fallback。`ImageTranslationBlock` 的方向字段必须可选以兼容旧 Codable 数据。本版不改漫画探针、renderer 或 metrics，不凭合成 fixture 声称 OCR 字符准确率提升。布局引擎文件本身必须命中 UI contract changed-files 路由；v1.87 / v2.2-v2.7 图片合同必须在同一 fail-fast step 阻塞候选 full。
- v2.8 候选要求图片分享准备状态归 Store 所有：开始异步 link/copy 前发布 `preparing`，准备中拒绝并禁用重复导出；只有当前 request 成功才能复位 idle，只有当前 request 失败才能发布独立失败消息并覆盖翻译成功色调。dismiss、新任务、清空、重渲染、export 失效和页面离开继续通过统一 discard 使 request 失效、清理分享目录并复位反馈；不得把分享失败写成图片翻译失败或绕过 Store 文件边界。`scripts/test-v208-image-share-feedback-contract.py` 必须编译执行状态 evaluator，锁定 duplicate/current/stale/failure/discard 转换、View 按钮和 danger 反馈，并与 v1.87 / v2.2-v2.8 图片合同在同一 fail-fast step 运行。
- v2.9 候选要求覆盖模式重渲染状态归 Store 所有：发布 `idle / rendering / failed`，rendering 时 Store 和 Picker 双重拒绝重复模式切换；只有匹配 render ID、图片 task ID 和 mode 的当前成功结果才能复位并发布导出，当前取消复位 idle，当前失败保留 danger 消息。新任务、清空和其他内容失效必须取消 Task、更新 render ID 并复位状态；失败后提供 Store-owned 同模式“重试导出”，无 staging URL 也必须明确失败，不能永久卡在 rendering。`scripts/test-v209-image-render-feedback-contract.py` 必须编译执行状态 evaluator，并与 v1.87 / v2.2-v2.9 图片合同在同一 fail-fast step 运行。
- v3.0 候选要求图片 OCR 汇总与重新识别入口保持 Store-owned。`ImageOCRResultSummary` 必须夹取异常 confidence 后计算平均值，以 `<50%` 而非 `<=50%` 统计低置信块，并把 horizontal / vertical / nil-or-unknown 完整分账；空 blocks 不生成虚假平均值。只有 `.translated` 且当前 Store-owned source 文件仍存在时才能显示并执行“重新识别”，动作必须复用内容输入/目标语言与 `retryImageTranslation()` 的 task ID、源文件保留、render/share 失效链路，View 不得读文件或直调 OCR service。`scripts/test-v300-image-ocr-rerun-contract.py` 必须直接编译产品汇总器执行 evaluator，并与 v1.87 / v2.2-v3.0 图片合同在同一 fail-fast step 运行。本版不改 Vision 请求、OCR layout、漫画探针、翻译或 metrics，不把可观测性描述为识别质量提升。
- v3.1 候选要求图片 OCR 检查列表提供“全部 / 待复查”筛选。待复查必须是 confidence `<50%` 与 sourceDirection nil / unknown 的并集，重叠块只计一次、恰好 `50%` 不纳入且原始顺序不变。筛选为 View 私有状态，只影响检查列表；预览、覆盖、翻译、导出、分享和持久化必须继续使用完整 `imageTranslationBlocks`。低置信与方向待定原因必须以图标加文字显示，不能只靠颜色；零结果显示明确空态。`scripts/test-v310-image-ocr-review-filter-contract.py` 必须直接编译产品 summary/filter 执行 evaluator，并与 v1.87 / v2.2-v3.1 图片合同在同一 fail-fast step 运行。本版不改 Vision 请求、OCR layout、漫画探针、翻译、ground truth、metrics 或 output，不描述为识别准确率提升。
- v3.4 候选要求图片目标语言与输入语言使用相同的 task-scoped Retry 边界：已完成且 Store-owned source 存在时更新凭据并立即重译；失败或取消且 `canRetryImageTranslation` 时只更新下次 Retry 选择；运行中拒绝改写；无 source 时不得重标旧内容。语言可用性只由 `selectTargetLanguage` / `canUseLanguage` 决定，不能用额外 `isProUnlocked` 阻断英语、中文等免费目标。`retryImageTranslation()` 必须使用 Store-owned 选择，cancel 保留、clear 重置。`scripts/test-v34-image-retry-language-contract.py` 与 v1.87 / v2.2-v3.1 图片合同在同一 fail-fast step 运行。本版不改 Vision OCR、layout、翻译实现、renderer、漫画探针、ground truth、metrics 或 output。
- v3.5 候选要求 actual-content 与 pending-Retry 输入/目标语言使用独立字段。`imageTranslationDisplayed*Language` 只能描述当前内容，不得读取 pending；菜单使用 `imageTranslationSelected*Language` 优先显示 pending；有 pending 时必须显示明确状态。failed/idle selector 只能写 pending，不能改 content 或立即 Retry；Retry 依次选择 pending、content、全局语言，`beginImageTranslationTask` 消费后清空 pending，clear 清空两组，cancel 不抹除 content。`scripts/test-v35-image-retry-credential-display-contract.py` 与全部既有图片合同在同一 fail-fast step 运行。本版不改 Vision OCR、layout、翻译实现、renderer、漫画探针、ground truth、metrics 或 output。
- v3.6 候选要求 `imageTranslationDisplayed*Language` 只要 task-scoped content 凭据存在就优先使用，不得再以 data/blocks 是否已产出作为门槛；failed/idle 图片语言菜单在改变全局选择前先快照 actual-content 语言，选择不同语言时写 pending，选回 actual-content 时把对应 pending 归一化为 `nil`，源/目标两项都无差异后不再显示“重试语言已更新”。目标语言继续通过 `selectTargetLanguage` / `canUseLanguage` 授权，运行态、完成态、Retry、clear、cancel 与 v3.5 边界不变。`scripts/test-v36-image-retry-language-reset-contract.py` 与全部既有图片合同在同一 fail-fast step 运行。本版不改 Vision OCR、layout、翻译实现、renderer、漫画探针、ground truth、metrics 或 output。
- v3.7 候选要求 `selectImageSourceLanguage` 在读取 actual-content、修改全局 `sourceLanguage` 或写 content/pending 前先检查 `isProUnlocked`；拒绝时写 Store-owned Pro 消息并立即返回。图片输入语言菜单必须以 `lock.fill` 预示锁定状态，并显示该拒绝 Alert 和 VoiceOver Pro 提示，不能静默改变文本页语言。`selectImageTargetLanguage` 继续只通过 `selectTargetLanguage` / `canUseLanguage` 维持 v3.4 免费目标规则。`scripts/test-v37-image-source-pro-feedback-contract.py` 与全部既有图片合同在同一 fail-fast step 运行。本版不改 Vision OCR、layout、翻译实现、renderer、漫画探针、ground truth、metrics 或 output。
- v3.8 候选要求图片来源入口在打开系统照片或文件选择器前调用 Store-owned `requestImageTranslationAccess()`。只有 `isProUnlocked` 分支可实例化 `PhotoPickerCommand` 或提供 `openImporter` 动作；免费分支必须显示两个 `lock.fill` 命令并通过 Store-owned `dataTransferMessage` Alert 反馈，不进入无效选择流程。`translateImage(from:)` 与 `translateImageTransfer` 仍须在 `beginImageTranslationTask` 前保留 Pro guard。`scripts/test-v38-image-entry-pro-gate-contract.py` 与全部既有图片合同在同一 fail-fast step 运行。本版不改授权后的 transfer/run isolation、Retry、语言策略、Vision OCR、翻译、renderer、漫画探针、Koharu 报告、metrics 或 output。
- v3.9 候选要求图片垃圾桶命令只设置 View 私有 confirmation 状态，不得直接调用 `clearImageTranslation()`。`confirmationDialog` 必须附着于触发命令所在的 `ImageCommandBar`，标题可见，正文明确会删除图片、识别结果、译文和导出文件；取消无动作，只有 destructive 确认按钮调用 Store 清理且只出现一次。`scripts/test-v39-image-clear-confirmation-contract.py` 与全部既有图片合同在同一 fail-fast step 运行。本版不改 Store 清理实现、文件 ownership、Retry、OCR、翻译、renderer、漫画探针、Koharu 报告、metrics 或 output。
- v3.10 候选要求图片预览通过独立 `ImagePreviewService` 在后台 ImageIO 下采样，source 禁止完整缓存，thumbnail 最大边固定为 2048px、立即缓存解码并应用 EXIF transform。SwiftUI task 必须在加载前清空旧 preview，取消时传播到后台任务，发布前核对 `Task.isCancelled` 与捕获的 `imageTranslationRevision`；不得再对 Store 原始 Data 调用 `UIImage(data:)`。`scripts/test-v310-image-preview-downsample-contract.py` 必须编译产品服务并执行尺寸/方向 evaluator，与全部既有图片合同在同一 fail-fast step 运行。本版不改变 Store 原始 Data、OCR、翻译、renderer、坐标、漫画探针、Koharu 报告、metrics 或 output。
- v3.11 候选要求图片预览另存已发布 revision，只有它与 Store 当前 `imageTranslationRevision` 一致时才可显示。图片 Data 非空但预览未就绪时必须展示准备态而不是“选择图片”；ImageIO 返回 nil 时只有未取消且 revision 仍匹配的 task 可发布失败态，失败按钮只递增 View 私有 attempt 重试预览，不得调用 OCR / 翻译 Retry。`scripts/test-v311-image-preview-state-contract.py` 与全部既有图片合同在同一 fail-fast step 运行。本版不改变 Store 原始 Data、OCR、翻译、renderer、坐标、漫画探针、Koharu 报告、metrics 或 output。
- v3.12 候选要求 OCR 结果行通过 View 私有 UUID 选择状态联动预览；行必须是 plain button，并用取景框图标、背景和 accessibility value 表达选中，不能只靠颜色。预览仍遍历完整 `store.imageTranslationBlocks`，只给 matching ID 的覆盖块增加边框；图片 revision 变化或筛选隐藏选中块时清除选择。`scripts/test-v312-image-block-selection-contract.py` 与全部既有图片合同在同一 fail-fast step 运行。本版不改变 Store blocks、OCR、翻译、renderer、导出、漫画探针、Koharu 报告、metrics 或 output。
- v3.13 候选要求选中 OCR block 后使用当前已下采样 preview 生成 16:9 局部放大窗，不重新读取或解码 Store 原图。焦点 block 必须从完整 `store.imageTranslationBlocks` 按 View 私有 ID 查找；裁切至少覆盖 bbox 宽高的 1.8 倍、以归一化宽 16% / 高 10% 为下限并夹取到图片范围，放大窗用非纯颜色标签和至少 24pt 的边框再次标记 bbox。关闭命令必须有可访问名称与 44pt 点击区，只清除 View 私有选择。`scripts/test-v313-image-block-focus-contract.py` 与全部既有图片合同在同一 fail-fast step 运行。本版不改变 Store blocks、Vision OCR、layout、翻译、renderer、导出、漫画探针、Koharu 报告、metrics 或 output。
- v3.14 候选要求图片页只有一个 `ScrollViewReader` 和一个位于 `ImageTranslationPanel` 根部的 workspace anchor，避免 `ViewThatFits` 两个候选布局产生重复 ID。结果行只有从未选中/其他块切到新 block 时才滚到 workspace，点击同一行取消不滚动；Reduce Motion 下不得调用动画。局部放大窗按当前筛选后的 `visibleImageTranslationBlocks` 顺序提供上一个/下一个命名按钮，按钮至少 44pt、首尾禁用且不绕回；位置文字同时进入 accessibility value。`scripts/test-v314-image-review-navigation-contract.py` 与全部既有图片合同在同一 fail-fast step 运行。本版不改变 Store blocks、Vision OCR、layout、翻译、renderer、导出、漫画探针、Koharu 报告、metrics 或 output。
- v3.15 候选要求完整图片预览仍遍历全部 `store.imageTranslationBlocks`，两种覆盖模式的每个 block 都必须是 plain Button，提供 OCR 原文、译文、选中状态和动作提示的 accessibility 语义，点击区至少 44pt。点同一块取消，点其他块直接打开局部放大；若当前“待复查”筛选隐藏被点块，必须先切回 `.all` 再发布 View 私有选择。`scripts/test-v315-image-preview-direct-selection-contract.py` 与全部既有图片合同在同一 fail-fast step 运行。本版不改变 Store blocks、Vision OCR、layout、翻译、renderer、导出、漫画探针、Koharu 报告、metrics 或 output。
- v3.16 候选要求待复查队列入口只在 `reviewRequiredBlocks` 非空时出现，必须复用 `ImageOCRReviewFilter.needsReview.blocks(from:)` 的共享风险定义。入口使用至少 44pt 命名命令；点击后切换 `.needsReview`，保留仍属于队列的选中 ID，否则选首块，且只调用一次现有 `revealPreview()`。`scripts/test-v316-image-review-queue-entry-contract.py` 与全部既有图片合同在同一 fail-fast step 运行。本版不创建已复查业务状态，不改变 Store blocks、Vision OCR、layout、翻译、renderer、导出、漫画探针、Koharu 报告、metrics 或 output。
- v3.17 建立了复查进度、自动前进、撤销和完成态的队列行为。v3.28 将已复查 block ID 从 `ImageTranslationPanel` 迁入当前图片会话的 Store 内存状态，避免面板重建丢失进度；队列仍先复用 `ImageOCRReviewFilter.needsReview.blocks(from:)`，再排除本次已复查 ID，完成后优先定位其后的未复查块、否则回到前一个，队列为空时显示完成态。该状态不写入持久化，新图、取消和清空必须重置。`scripts/test-v317-image-review-progress-contract.py` 与全部既有图片合同在同一 fail-fast step 运行。
- v3.18 候选要求只在共享风险集合非空时显示 `ProgressView`，数值必须复用本次完成数和完整风险总数，并通过文字与 accessibility value 同时报告完成、总数和剩余数；pending / complete 色调不能成为唯一状态表达。DEBUG `imageSuccess` fixture 必须显式覆盖低置信横排与方向待定两类风险，wide iPad UI evidence 必须新增图片成功态。`scripts/test-v318-image-review-progress-evidence-contract.py` 在 v3.17 后接入同一图片/UI fail-fast step。本版不写 Store 或持久化，不改变完整 blocks、Vision OCR、layout、翻译、renderer、导出、漫画探针、Koharu 报告、metrics 或 output。
- v3.19 候选要求风险结果行把定位与复查拆成两个同级 Button，不得嵌套；快速复查只在共享风险定义为 true 时出现，使用 44pt 命名完成并继续/撤销动作，并复用既有 `toggleReviewCompletion` 的自动前进与撤销状态机。入口必须按完成数区分“开始复查 N”和“继续复查 N”；风险原因与已复查标签纵向排列以适配窄 inspector 和 Dynamic Type。`scripts/test-v319-image-review-quick-action-contract.py` 在 v3.18 后接入同一图片/UI fail-fast step。本版不新增 Store 状态，不改变完整 blocks、Vision OCR、layout、翻译、renderer、导出、漫画探针、Koharu 报告、metrics 或 output。
- v3.20 候选要求连续复查使用 View 私有 `AccessibilityFocusState<String?>`，结果行、局部放大和完成态必须有不同 focus ID。开始/重启进入当前局部放大；行级完成/撤销回到结果行序列；局部放大完成/撤销留在局部放大序列；队列结束聚焦完成态。延迟焦点发布必须核对当前图片 revision，图片变化同步清空焦点。`scripts/test-v320-image-review-voiceover-focus-contract.py` 在 v3.19 后接入同一图片/UI fail-fast step。本版不新增 Store 或持久化状态，不改变完整 blocks、Vision OCR、layout、翻译、renderer、导出、漫画探针、Koharu 报告、metrics 或 output；源码合同不能冒充真实 VoiceOver 回放。
- v3.21 候选要求每个普通图片 OCR 结果行提供独立 44pt 人工修正入口，sheet 禁止空白保存，并在目标块重译期间禁用重复提交、取消和交互式关闭。UI 只调用 Store 方法；Store 必须只翻译目标 block，并在回写前同时核对 correction ID、图片 task ID、block ID 和旧原文快照。失败不得修改 block、transcript 或旧导出；成功必须更新当前 block 与对应图片 transcript，随后撤销旧 export/share 并复用既有 render ID 生命周期按当前覆盖模式重绘。新图片、清空和取消必须使旧 correction 回调失效。`scripts/test-v321-image-ocr-correction-contract.py` 在 v3.20 后接入同一图片/UI fail-fast step。本版不修改 Vision OCR、方向/layout、漫画探针、Koharu 报告、ground truth、metrics 或 output，不声称 OCR/翻译质量提升。
- v3.22 正式要求首次成功人工修正时由 Store 私有保存该 block 的 Vision OCR 基线，后续修正不得覆盖它。已修正行必须提供独立命名 44pt “恢复 Vision OCR”动作，恢复只在完成态、没有 correction in flight、基线与当前 block ID 都存在时可用，且不得调用模型。恢复必须替换完整基线 block、清除人工修正标记、更新当前图片 transcript、撤销旧 export/share 并复用既有 render 生命周期；新图片与清空必须丢弃私有基线。v3.28 起恢复风险 block 后由 Store 移除当前图片会话复查标记，并把 VoiceOver 焦点返回该行。`scripts/test-v322-image-ocr-correction-restore-contract.py` 在 v3.21 后接入同一图片/UI fail-fast step。本版不修改 Vision OCR、方向/layout、漫画探针、Koharu 报告、ground truth、metrics 或 output，不声称 OCR/翻译质量提升。
- v3.23 正式要求“恢复 Vision OCR”图标动作先写入 View 私有的 `ImageTranslationBlock` 待确认值，而不是直接调用 Store；confirmation dialog 必须可读地说明会移除本次人工修正，提供 destructive 确认与取消。取消不得改变 block、transcript、export、渲染、选择或复查状态；确认才可调用 v3.22 既有恢复路径。待确认值必须在图片 revision 变化时清空，避免旧 dialog 指向新图片。`scripts/test-v323-image-ocr-restore-confirmation-contract.py` 在 v3.22 后接入同一图片/UI fail-fast step。本版不修改 Vision OCR、方向/layout、漫画探针、Koharu 报告、ground truth、metrics 或 output，不声称 OCR/翻译质量提升。
- v3.24 正式要求普通图片 OCR 修正 sheet 以本地 `correctedOriginal` 与当前 block 原文判断是否有未保存改动；无改动取消可直接关闭，有改动取消必须显示可读的 destructive “放弃修正”确认，选择“继续编辑”不得清空输入。交互式下拉在保存中或有未保存改动时均必须阻止，保存成功继续直接关闭而不经过放弃流程。该状态仅属 View，禁止复制到 Store、transcript、export、渲染、图片 revision 或持久化；`scripts/test-v324-image-ocr-correction-discard-confirmation-contract.py` 在 v3.23 后接入同一图片/UI fail-fast step。本版不修改 Vision OCR、方向/layout、漫画探针、Koharu 报告、ground truth、metrics 或 output，不声称 OCR/翻译质量提升。
- v3.25 正式要求普通图片 OCR 修正 sheet 的确认动作使用与 `TranslationSessionStore` 相同的 `trimmed input != block.original` 决策：规范化文本未变时，按钮与无障碍提示必须明确“确认无误”且不声称重译；实际变化时才显示“保存并重译”，仍只调用既有目标 block correction。Store 的无模型 early-success 必须位于 correction ID、状态切换和 `translate` 前；UI 不得新增 Store、持久化、transcript、export、渲染或图片 revision 状态。`scripts/test-v325-image-ocr-correction-confirmation-action-contract.py` 在 v3.24 后接入同一图片/UI fail-fast step。本版不修改 Vision OCR、方向/layout、漫画探针、Koharu 报告、ground truth、metrics 或 output，不声称 OCR/翻译质量提升。
- v3.27 正式要求普通图片 OCR 修正 sheet 接收当前图片 data，但只能经既有 `ImagePreviewService` 生成最大边 2048px 的本地预览；局部图必须复用已验证的 16:9 裁切与黄色 bbox 几何，提供“当前文字块”可读标签和 OCR 原文的 VoiceOver value。loading / unavailable 状态必须明确、不得阻止手工修正，也不得调用 `VisionOCRService` 或 Store correction 方法。低置信与方向待定提示必须复用 `ImageOCRResultSummary`；保存边界继续是仅重译当前 block。`scripts/test-v327-image-ocr-correction-reference-context-contract.py` 在 v3.25 后接入同一图片/UI fail-fast step。本版不改 Vision OCR、layout、翻译、renderer、export、漫画探针、Koharu artifact、metrics 或 output，不声称质量提升。
- v3.28 正式要求当前图片会话的复查集合只由 `TranslationSessionStore` 读写：面板重建不能清空它，`beginImageTranslationTask`、取消和清空必须重置它；完成/撤销/重新开始复查均通过 Store 风险范围 API，成功人工修正（含“确认无误”）自动标记风险 block，恢复 Vision OCR 自动移除该标记。View 继续只负责筛选、顺序、选择和 VoiceOver 焦点；该集合不进入持久化、OCR、翻译、renderer、export、漫画探针、Koharu、metrics 或 output。`scripts/test-v328-image-review-session-continuity-contract.py` 在 v3.27 后接入同一图片/UI fail-fast step。
- v3.29 正式要求 OCR 修正 sheet 仅经明确 destructive confirmation 才能忽略“不是文字”的当前 block；未保存修正不得保存，取消必须继续编辑。Store 只在 `.translated`、没有 correction in flight 且 block 仍活动时接收忽略：它从当前活动 blocks、已修正／已复查集合和 Vision 基线映射移除 block，同时在当前图片会话私有快照保存完整 block、初始 OCR 顺序、人工修正标记与 Vision 基线；随后同步当前图片 transcript、撤销 export/share 并复用 render 生命周期。检查区必须展示可访问的“已忽略的文字块”恢复列表；恢复按初始顺序插回，恢复既有人工修正基线但不得恢复已复查结论，风险块重新进入队列。活动 blocks 全空时，当前图片 transcript 行必须移除且 renderer 仍生成原图；新图和清空丢弃忽略快照，不写持久化。忽略／恢复不得调用 Vision OCR 或模型翻译，也不改漫画探针、Koharu、ground truth、metrics 或 output，不能声称 OCR／翻译质量提升。`scripts/test-v329-image-ocr-false-positive-dismissal-contract.py` 在 v3.28 后接入同一图片/UI fail-fast step。
- v3.30 正式要求 OCR 修正 sheet 的成功忽略，以及待复查队列中的成功修正，不得在 sheet 遮罩仍存在时直接发布 VoiceOver 焦点。`ImageTranslationPanel` 必须只在 View 私有 state 暂存既有目标 focus ID 与当前 `imageTranslationRevision`，并用 `sheet(item:onDismiss:)` 在关闭后核对 revision 后才复用既有焦点发布器；新图 revision 必须同时清空 sheet、pending handoff 与已发布焦点。忽略仍使用既有下一活动／待复查行或已忽略行，修正仍使用既有下一行／完成态；本版不新增 Store、持久化、OCR、翻译、renderer/export、漫画探针、Koharu、metrics 或 output 状态。`scripts/test-v330-image-ocr-correction-sheet-focus-handoff-contract.py` 在 v3.29 后接入同一图片/UI fail-fast step，源码合同不能冒充真实 VoiceOver 回放。
- v3.31 正式要求普通图片 OCR 修正 sheet 的任何成功结果都有关闭后的上下文返回：只有 `reviewFilter == .needsReview`、block 仍是风险 block 且 Store 已将其标为已复查时，才沿用 v3.30 的下一待复查行／完成态；非风险 block 与“全部”筛选下的风险 block 必须经同一个 pending `onDismiss` handoff 回到已更新结果行。helper 首先确认 block 仍在当前活动集合，不能向新图片或失效 block 发布焦点；不得新增 Store、持久化、OCR、翻译、renderer/export、漫画探针、Koharu、metrics 或 output 状态。`scripts/test-v331-image-ocr-correction-return-focus-contract.py` 在 v3.30 后接入同一图片/UI fail-fast step，源码合同不能冒充真实 VoiceOver 回放。
- v3.32 正式要求“恢复 Vision OCR”的 destructive confirmation 不得在 dialog 仍呈现时直接发布 VoiceOver 焦点。确认动作必须先核验待确认 block，再走既有无模型恢复；成功后只由 `ImageTranslationPanel` 暂存结果行 focus ID 与 `imageTranslationRevision`。`confirmationDialog` 的 `isPresented` binding 收到关闭回写后，先清空待确认 block，再仅在 revision 一致时发布焦点；取消没有 pending 目标，新图必须清空待确认、pending 与已发布焦点。该状态不得进入 Store、持久化、OCR、翻译、renderer/export、漫画探针、Koharu、metrics 或 output；v3.22/v3.23 合同须同时保持恢复所有权和 destructive-confirmation 边界。`scripts/test-v332-image-ocr-restore-focus-handoff-contract.py` 在 v3.31 后接入同一图片/UI fail-fast step，源码合同不能冒充真实 VoiceOver 回放。
- v3.33 正式要求普通图片 OCR 修正 sheet 的非成功退出也有确定的上下文返回：`beginCorrection` 必须在设置 sheet item 前，把发起 block 的结果行写成 View 私有、revision-scoped 的 pending fallback。无修改取消、确认放弃未保存修正和无修改时允许的交互式关闭只可通过既有 `sheet(item:onDismiss:)` 发布该 fallback；不得在 sheet 仍呈现时直接移动焦点。成功修正／确认无误或忽略必须在关闭前覆盖 fallback，继续使用既有下一块、完成态或忽略行目标；图片 revision 改变必须清空 sheet、pending 与已发布焦点。状态不得进入 Store、持久化、OCR、翻译、renderer/export、漫画探针、Koharu、metrics 或 output。`scripts/test-v333-image-ocr-correction-cancel-focus-contract.py` 在 v3.32 后接入同一图片/UI fail-fast step，源码合同不能冒充真实 VoiceOver 回放。
- v3.34 正式要求选中 OCR block 的局部放大窗在关闭命令下提供命名明确的 44pt “修正识别文字”铅笔入口，并与结果行严格共享 `!isRunning && !isRenderingExport` 可用条件。入口只能把当前完整活动 block 交给 View 私有的修正入口；不得直接调用 Store correction、Vision OCR、翻译、renderer/export 或创建新的持久化状态。`scripts/test-v334-image-focus-preview-correction-contract.py` 在 v3.33 后接入同一图片/UI fail-fast step，源码合同不能替代真机／模拟器的实际 VoiceOver 或紧凑布局回放。
- v3.35 正式要求从局部预览铅笔入口进入修正 sheet 时，先以同一 busy / active-block guard 把 v3.33 的 revision-scoped `onDismiss` fallback 设置为 `reviewPreviewAccessibilityFocusID(block.id)`；取消、放弃或无修改关闭只在 sheet 完全关闭后回到同一局部预览。结果行 `beginCorrection` 必须继续使用 row focus，成功／忽略继续覆盖 fallback 为既有队列、完成或忽略目标；新图清空 pending。`scripts/test-v335-image-focus-preview-return-focus-contract.py` 必须在 v3.34 后接入同一图片/UI fail-fast step；源码合同不能替代真机／模拟器 VoiceOver 回放或紧凑布局验证。
- v3.36 正式要求开发控制台仅在 `mangaOverlayProbeReport.externalArtifactReadinessReport` 已存在时显示 Koharu readiness；摘要必须复用 `MangaOverlayExternalArtifactReadinessReport`，以 `readyForShadowOCR && externalTextBoxesShadowOCRAllowed`、`manifestMissing` / `artifactFilesMissing` 和其他无效状态区分 status，并显示 missing artifacts、nextAction、四件套存在性、parse errors、source / generatedBy / counts，继续复用 `DeveloperCodeBlock` 的复制／分享。摘要不得新增 Store 或 probe state、再次调用 `runMangaOverlayProbe`、读取／写入 active artifact、调用 Vision OCR／模型／renderer，不得改变普通图片 OCR、翻译、覆盖图、`blockPassed`、`currentBlockSource`、ground truth、metrics 或 output。`scripts/test-v336-koharu-readiness-developer-summary-contract.py` 必须在 v3.35 后接入图片/UI fail-fast；源码合同和页面状态不能替代真实 artifact、shadow OCR coverage 或真机／模拟器实际渲染证据。
- v1.98 候选要求普通图片的 Vision OCR bbox、SwiftUI 预览和 PNG 导出统一使用顶左原点；export renderer 必须显式消费 `旁贴/覆盖` mode。后台 renderer 只能写 render ID 独占的 staging PNG；模式切换后旧 export URL 立即失效并重绘，只有同时核对 render ID、图片 task ID 和 mode 后才能原子发布稳定 export，过期 staging 必须清理；运行中模式控制禁用。`scripts/test-v187-ui-interaction-contract.py` 锁定这些边界。
- 需要探针验收时，手动 `workflow_dispatch` 选择 `ci-fast` 或 `full`。`ci-fast` 仍跑真实模拟器、Local GGUF、真实 `test/1.png`、deterministic 解码、主 OCR / bubble-first 融合 / 逐块翻译 / 失败块覆盖 / clean text / external artifact gate，以及 v1.18+ 必需的 report-only / detector-lite 受限 shadow 报告；只跳过明确列出的高成本对照和诊断 PNG。`ci-fast` 必须保留 `probe_report.json`、`clean_text_diagnostic.json`、`1_ocr_probe_text.txt`、`1_debug_boxes.png`、`1_translated_overlay.png`、`manga_probe_progress.json`。`full` 额外要求 contact sheet 等完整关键 PNG。
- 探针模式等待期间 `ci-fast` 每 30 秒打印 `output/manga_probe_progress.json` 和输出目录快照，1800 秒总超时、启动后 180 秒未创建 progress 提前失败、进度 300 秒不更新提前失败；`full` 为 3600 秒总超时、300 秒 no-progress 阈值、600 秒停滞阈值。失败时仍复制已有 `output/`，并在结果包保留 `manga-probe.log`、`app-console.log`、manifest 和失败摘要。

### 0.1 v1.87 UI 视觉与交互矩阵

v1.87 原始验收曾在候选 push 的 Xcode build 后运行 `scripts/capture-ui-evidence.sh`。v1.94 起不再按版本分支名自动截图；只有重大 UI 核心 commit 标记 `[ui evidence]`，或手动 `ui_evidence_mode=full` 才运行。该步骤复用当前 Debug app，不下载 GGUF、不运行漫画探针；输出 `ci-results/ui-evidence/`、manifest 和日志。

当前最低截图矩阵为 14 张证据：同一台紧凑 iPhone 上 12 张竖屏，覆盖文本空态、图片空态、历史有数据、Pro 锁定、文本成功 XXL、键盘显示、Accessibility 失败态、Reduce Motion 音频 recognizing、音频 translating 取消入口、提示词库、Local 模型缺失和开发控制台；另有 2 张 wide iPad，分别覆盖文本空态和图片成功/风险复查态。矩阵必须同时包含日间和夜间外观，manifest 记录 `appearance`；截图步骤失败必须使候选分支 CI 失败。Mac 视觉证据仍未覆盖，不得描述为已验证。

截图脚本必须等待模拟器完整启动，关闭键盘首次使用教程干扰，并拒绝小于 50 KB 的疑似空白 PNG。键盘证据必须显示实际软件键盘，不得以 QuickPath / 输入法教学遮罩代替；文件存在、方向和尺寸检查通过仍不能替代 Agent B / C 逐张视觉审查。

文本输入自动聚焦或键盘显示时，页头和模型状态必须留在顶部安全区内，不得随输入区域自动滚动到系统状态栏下方；`TextTranslationView` 的页头应位于工作区 `ScrollView` 外侧的顶部 safe-area inset。键盘证据必须能同时看到未遮挡的页头、模型状态和输入区。

Agent C 逐张检查：文字和控件不重叠、不越界、不被底栏或键盘遮挡；页面没有卡片套卡片；主操作层级唯一；颜色之外仍有图标和文字状态；44pt 触控、最长状态文案、Dynamic Type 和安全区可用。Preview matrix 只用于复现状态和开发检查，不得当作当前 HEAD 运行截图。

交互回归至少覆盖：文本翻译/交换语言/目标语言/提示词；新会话与历史恢复/搜索/删除/导入/导出/清空；提示词新建/编辑/复制/删除/选择；Mock/Local、GGUF 下载/导入/移除和失败；图片导入/OCR/运行中更换照片或文件/A-B 反序回调/目标语言选择/loading 且图片数据为空时仍显示任务语言/跨页面改语言后仍显示实际结果语言/失败与取消后可见内容仍保留语言凭据/清空后重置凭据/新照片失败后不重试旧源/取消后当前源可重试/全局语言已相同时的已完成图片重译/旁贴/覆盖/导出；音频导入/识别/取消/翻译/摘要；Pro 锁定/解锁/订阅校验；开发 raw probe、批量探针和漫画报告入口。

`scripts/test-v187-ui-interaction-contract.py` 是独立源码契约检查，必须验证：录音按钮有默认 accessibility action 且能开始/停止、`SettingsView` 绑定 `NavigationPath` 并在关闭开发模式后清空、Reduce Motion 场景进入 `isCapturingProSpeech=true`、`audioTranslating` 进入 translating + 非空 transcript 状态、文本页头位于自动滚动区外的顶部 safe-area inset、上述八类页面的关键 store action 仍接线、14 张运行态证据至少覆盖八类页面，以及普通图片导出的顶左坐标、mode 消费和 stale render 拒收。CI 必须把结果写入 `ui-interaction-contract.log`、manifest 的 `uiInteractionContractOutcome` 和 JUnit 的独立 testcase。该契约和运行态截图不冒充 XCUITest 点击；Agent C 仍按本段交互清单抽查高风险操作。

### 0.2 v1.88 文本首页视觉与交互契约

v1.88 原始验收复用了 v1.87 运行态矩阵。后续重大文本 UI 任务若显式启用 UI evidence，文本相关证据仍至少覆盖日间空输入、夜间键盘/安全区、XXL 成功态和 Accessibility 失败态；截图 `commitSha` 必须等于候选 full HEAD。PR/merge fast 不重复该矩阵。

`scripts/test-v188-home-ui-contract.py` 独立验证：显式纯文本 `PasteButton`、空输入填入与非空换行追加、不在生命周期读取剪贴板、不自动翻译、keyboard toolbar“完成”、翻译前失焦、safe-area 页头仍位于 `ScrollView` 外、首页专属非纯色背景不进入其他页面、首页关键 store action 与非颜色身份仍接线。CI 必须把结果写入 `v188-home-ui-contract.log`、manifest 的 `v188HomeUIContractOutcome` 和 JUnit 独立 testcase，失败阻塞候选分支。

Agent C 多轮视觉退回后，v1.88 contract 还必须锁定两项回归：compact-width 根 `VStack` 只能在 XXL Dynamic Type 起或输入已聚焦时把 `floatingTabBarClearance` 放在 `ScrollView` 之后；标准字号且键盘关闭时不得插入该净空，源码仍须保留“翻译”主按钮；不得退回所有字号固定净空、内容尾部 padding 或 bottom `safeAreaInset`。真实 `PasteButton` 必须保留为交互层，并以透明前景加不接收触摸的实底中文 `Label("粘贴", systemImage: "doc.on.clipboard")` 覆盖系统 locale 标签。新 HEAD 的空输入截图必须同时完整显示中文“粘贴”和带图标/文字的“翻译”，键盘截图必须显示“完成”，XXL 与 Accessibility 截图必须证明 Tab Bar 不再遮挡输入文字或主按钮。

人工交互必须另行核对：无兼容剪贴板内容不清空输入；空输入粘贴直接填入；非空输入粘贴换行追加；粘贴不自动翻译；“完成”一次收起键盘；翻译前键盘先收起；交换语言、Prompt、新会话和归档仍可用；VoiceOver 能读出粘贴、翻译、交换语言、完成和状态。当前 CI 没有 XCUITest 点击回放，也仍只采集紧凑 iPhone，iPad / Mac 运行态和真实剪贴板点击不得描述为已验证。v1.88 正式收口以云端 run `29104261998` 的 build / contract / 11 张 UI evidence 为准；真实粘贴路径与 VoiceOver 回放列入 v1.89 人工矩阵，不得回写为 v1.88 已验证。

### 0.3 v1.89 人工交互与 a11y 矩阵

v1.89 当时把 v1.88 遗留的真实点击与无障碍路径固化为可勾选人工矩阵。该版本 CI 的 v1.88 home UI contract、v1.89 paste/matrix contract 与当时 12 张 UI evidence（11 张 compact-iPhone + 1 张 wide-iPad）**不能**替代本矩阵的 M1–M6；Agent C 不得把未勾选项写成已验证。

| ID | 场景 | 期望 | 人工勾选 |
|---|---|---|---|
| M1 | 空剪贴板点「粘贴」 | 已有输入保留，不崩，不自动翻译；不得以 `isEnabled == false` 作为唯一标准 | [ ] |
| M2 | 空输入 + 有文本剪贴板 | 直接填入，状态仍等待翻译 / 不自动 `submitDraft` | [ ] |
| M3 | 非空输入再粘贴 | 换行追加，不覆盖已有内容 | [ ] |
| M4 | keyboard toolbar「完成」 | 一次点击收起键盘 | [ ] |
| M5 | 点「翻译」 | 先失焦再 `store.submitDraft()` | [ ] |
| M6 | VoiceOver / 标签 | 粘贴、翻译、交换语言、完成与关键状态可读 | [ ] |
| M7 | 标准字号 + 键盘关闭 | 首屏完整可见中文「粘贴」与「翻译」，无固定 48pt 外部净空 | [ ] |
| M8 | XXL / Accessibility 或输入聚焦 | 48pt 外部净空，浮动 Tab 不遮挡输入与主按钮；键盘「完成」可见 | [ ] |

宽屏证据：`scripts/capture-ui-evidence.sh` 必须产出 `wide-iPad` / `text-empty-wide-ipad-day.png` 与 `image-success-wide-ipad-day.png` 两张运行态截图；后者必须显示图片成功态、风险入口和本次复查进度。Preview 的 iPad landscape 状态不冒充运行态。

DEBUG 可测性：仅在用户点击粘贴时，若系统 `PasteButton` payload 为空，DEBUG 构建可回退 `AITRANS_UI_TEST_PASTE_TEXT` 环境变量或 `-AITRANS_UI_TEST_PASTE_TEXT <text>` launch argument。Release 无注入；禁止 lifecycle / 后台读剪贴板；禁止把系统 `PasteButton` 换成普通 Button。

`scripts/test-v189-paste-manual-matrix-contract.py` 校验人工矩阵文档、debug 注入边界、wide-iPad evidence 与 CI wiring；结果写入 `v189-paste-manual-matrix-contract.log`、manifest `v189PasteManualMatrixContractOutcome` 与 JUnit testcase。

### 0.4 v1.90 Speech 诊断契约

`scripts/test-speech-recognition-contract.py` 除既有状态机与 run-id 隔离外，还必须验证：

- `cancelAudioRecognition` 先 `invalidateSpeechRecognitionRun()` 再置 idle，并写入取消失败摘要
- 运行摘要 UI 展示离线强制、本机能力、终态与 `runToken`
- `SpeechRecognitionRunSummary` 含 `runToken`

该契约由云端独立 `Speech recognition contract` step 执行，并写入 JUnit、manifest 和独立日志；不得在 static checks 重复执行，也不冒充真机录音点击验收。

### 0.5 v1.91 Speech 人工交互矩阵

v1.90 已用静态契约锁定 run-id 隔离与摘要字段。下列人工矩阵**不能**被 CI 截图替代；未勾选不得写成已验证。

| ID | 场景 | 期望 | 人工勾选 |
|---|---|---|---|
| S1 | 授权拒绝 | 状态 failed/可恢复提示，不崩，不覆盖其他 Tab | [ ] |
| S2 | 文件识别成功 | 识别文本非空；摘要显示 locale、强制本机、耗时、词数、片段、置信度、runToken | [ ] |
| S3 | 识别中取消 | 先 invalidate run；UI「已取消」；旧回调不覆盖新状态 | [ ] |
| S4 | 取消后立即重试 | 新 runToken 不同于上一轮；状态机从 checking/recognizing 正常前进 | [ ] |
| S5 | 识别后翻译 | 识别态与翻译态分离；translating 期间可取消 | [ ] |
| S6 | 长按实时采集（Pro） | accessibility action 可 toggle；松手结束；摘要更新 | [ ] |
| S7 | 无离线语音包 | supportsOnDevice 与失败原因可读，不静默成功 | [ ] |
| S8 | Reduce Motion | 采集动画降级；capturing 状态仍正确 | [ ] |

`scripts/test-speech-recognition-contract.py` 只证明源码接线；真机麦克风/权限/质量必须走本矩阵或后续专用云端 UI smoke。

### 0.6 v1.93 Speech 取消与立即重试竞态契约

`scripts/test-speech-recognition-contract.py` 必须按函数体与语句顺序验证下列边界，而不是只统计 guard 字符串：

- 麦克风权限 `await` 返回后，先核对 `speechRecognitionRunID == runID` 和 capture request，再处理授权结果或启动录音。
- 文件识别后的 `submit` 在模型 `await` 返回后、`transcript.insert` 前核对当前 Speech run；summary `await` 返回后、`summary` 写入前再次核对。
- 实时语音翻译在模型 `await` 返回后、写入译文 / transcript / state 前核对 Task cancellation 与 run ID。
- `cancelAudioRecognition` 先 invalidate run，再取消 `speechTranslationTask`，最后回到 idle；新 run 在生成新 run ID 前取消并清空旧翻译 Task。
- 文件面板与实时语音面板都在 `.translating` 暴露取消入口；文件运行态的取消按钮必须排在两个已禁用的启动按钮之前，不能落到 compact iPhone 浮动 Tab Bar 后方。
- workflow 中 Speech contract 命令只出现一次，但 failure summary 与最终 fail-job 都把该独立 step 的非 success 作为硬失败。

本契约证明的是源码所有权和云端接线，不证明 Apple Speech 的实际识别质量。S1-S8 仍需真机；后续固定语料必须另行报告音频 SHA、locale、参考 transcript、WER/CER、延迟和设备/系统信息。GitHub-hosted simulator 没有真实麦克风输入，不能作为 WER/CER 或权限弹窗证据。

### 0.7 v1.94 云端验证分层契约

`scripts/test-v194-ci-validation-tier-contract.py` 必须锁定以下行为：

- `codeb/**` 核心 push 自动选择 `validationProfile=full`，只跑 changed-files 命中的领域契约；App 相关 full 执行 Xcode build，成功后为精确 SHA 写 `AITRANS CI/full-validation` status。
- PR 只监听 opened / reopened / ready-for-review，不监听 synchronize。PR fast 只做基础静态与路由检查，不能冒充候选 full/Xcode 证据。
- PR fast 必须查询当前候选 head 的 `AITRANS CI/full-validation` status，并把 exact SHA 与 state 写入 manifest；只有 state 为 `success` 才能使用 `fast_followup_reuses_candidate_full_validation`，否则必须写明缺少成功收据，供验收拒绝而不是伪造复用。
- `smalldata_test` merge 读取第二父 SHA 的 full-validation status；`success` 才可 fast，missing / failure / lookup failure 必须回退 full。
- full 成功后的纯 `README.md`、`AGENTS.md`、`update_log.md`、`md/`、`metrics/` follow-up 可复用并传播父收据；父收据失败或缺失时必须扩展到整条候选 diff，不能只测最后一个文档 commit。
- v3.26 正式要求成功候选 receipt 在 merge fast 时传播到 merge SHA。其后的 `smalldata_test` 纯元数据提交只有当前父 SHA 的 propagated receipt 为 `success` 时才可 `fast`，并必须记录 `smalldataParentSha`、`smalldataParentFullValidationState`、`smalldataIncrementalMetadataOnly`、`smalldataMetadataRequiresFullValidation` 与 `receiptPropagationAllowed`；非元数据变更、workflow 变更或 missing / failure / lookup failure 一律不得复用，纯元数据但父 receipt 不可信时必须强制当前头部 Xcode build。该快验只能证明路由与静态检查，不是新的 Swift/Xcode 编译证据。
- Speech full 跑 Speech 契约与必要 Xcode，不自动截图；UI evidence 默认 skip，只能由非 PR 候选 commit 的 `[ui evidence]` 或手动 `ui_evidence_mode=full` 启用。
- `AITRANS - Build IPA` 不监听 push，只允许手动 `workflow_dispatch`。日常 merge 不做 Release archive/fakesign/package。
- manifest / failure summary 必须记录 `validationProfile`、reason、复用 SHA/status、领域 required flags、UI evidence reason 和 Xcode skip reason。fast artifact 仍可审计，但 Agent C 必须同时核对候选 full artifact/status。
- `smalldata_test` merge 或其他不含 `vX.Y` 的 ref 必须通过 `scripts/resolve-project-version.py` 从 Xcode 工程唯一 `MARKETING_VERSION` 解析 artifact version；缺失、格式非法或 Debug/Release 值冲突必须硬失败，禁止输出 `unversioned`。由 `scripts/test-v197-ci-version-identity-contract.py` 锁定。

任何 C 退回后的核心修复都会产生新 SHA，必须重新跑对应 full。不要为“记录 CI 已通过”追加无功能文档 commit；结果以 GitHub status、run 和 artifact 为准。

### 0.8 v1.95 Speech 质量算法与 corpus 契约

v1.95 验收算法和接线，不验收不存在的真实音频质量提升：

- `scripts/test-speech-quality-evaluator.swift` 必须锁定 Levenshtein、英文词级 WER、CER 和加权 aggregate；中文、日文 `wordErrorRate` 必须为 `nil`。
- `scripts/test-speech-quality-contract.py` 必须锁定参考 transcript 不进入 recognition request、音频 SHA256/字节硬门控、`requiresOnDeviceRecognition=true`、store run ID/取消、Xcode 工程和 CI 接线。
- `scripts/validate-speech-corpus.py` 在没有 `manifest.json` 时返回成功但明确输出 `verdict=manifestMissing`、`qualityExecuted=false`；使用 `--require-manifest` 时缺失必须失败。manifest 存在时，任何路径逃逸、重复 ID、缺字段、字节数或 SHA 漂移都必须失败。
- 真实报告必须记录 corpus/manifest/audio 身份、设备/系统、locale、参考与识别文本、WER/CER、延迟、segment、confidence、失败分类，并固定 `referenceUsedForEvaluationOnly=true`、`referenceUsedForRecognitionDecision=false`。
- GitHub-hosted simulator full 只证明编译和无设备算法契约；没有人工上传的真实 corpus 和目标设备运行报告时，不得给出 WER/CER 提升结论。
- v1.96 上传真实音频后，先用 `--require-manifest` 校验，再运行开发页或 `AITRANS_RUN_SPEECH_QUALITY_PROBE=1`，验收 `Output/speech_quality_report.json` / `.txt`。Speech 功能不采 UI 截图。

## 1. 固定前缀 / 环境要求
人工明确要求本机命令行构建时，固定使用完整 Xcode：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
```

常用构建命令：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project AITRANS.xcodeproj \
  -scheme AITRANS \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath .derivedData \
  CODE_SIGNING_ALLOWED=NO build
```

漫画探针运行依赖：

- `test/1.png` 已打入 App bundle。
- `test/1.ground_truth.json` 可解析。
- Local 模式需要沙盒内存在 GGUF 模型，默认内置下载模型只适合接口冒烟。
- 导出模拟器 App 容器通常需要读取 CoreSimulator 容器，受限环境下要请求批准。

当前仓库没有独立 XCTest 目标作为主要验收入口。日常核心验证由 GitHub Actions 快验产出 build 结果包、日志、manifest 和失败摘要；探针 JSON/PNG artifact 只在手动 `ci-fast` / `full` 运行中要求。本地命令保留为人工要求或紧急排查路径。

## 2. 测试分层
### 2.1 Local Light / Fast
最快发现主链路断点。

触发条件：

- 非 App 构建相关修改。
- JSON、脚本、指标读取或报告字段整理。
- 不影响 Swift 编译路径的小改动。

命令：

```sh
git diff --check
python3 -m json.tool test/1.ground_truth.json
python3 -m json.tool output/probe_report.json
python3 -m json.tool output/clean_text_diagnostic.json
python3 -B scripts/test-speech-recognition-contract.py
python3 -B scripts/test-speech-quality-contract.py
python3 -B scripts/validate-speech-corpus.py --root test/speech_corpus
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun --sdk macosx swiftc -module-cache-path /private/tmp/aitrans-swift-module-cache AITRANS/Models/SpeechQualityModels.swift AITRANS/Services/SpeechQualityEvaluator.swift scripts/test-speech-quality-evaluator.swift -o /private/tmp/aitrans-speech-quality-contract
/private/tmp/aitrans-speech-quality-contract
python3 -B scripts/test-v194-ci-validation-tier-contract.py
python3 -B scripts/test-v197-ci-version-identity-contract.py
python3 -B scripts/test-v192-koharu-line-polygon-warp-contract.py
python3 -B scripts/test-v32-koharu-mask-payload-contract.py
python3 -B scripts/test-v187-ui-interaction-contract.py
python3 -B scripts/test-v188-home-ui-contract.py
python3 scripts/make-koharu-native-draft-artifacts.py --out build/koharu_native_draft
python3 scripts/validate-koharu-artifacts.py --root build/koharu_native_draft
python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/valid
python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/valid_orientation_partial_unsupported
python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/coordinate_mismatch --expect-fail
python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/invalid_bbox --expect-fail
python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/missing_textboxes --expect-fail
python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/schema_mismatch --expect-fail
python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/path_escape --expect-fail
python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/generated_by_forbidden --expect-fail
python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/textbox_metadata_invalid --expect-fail
python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/source_image_missing --expect-fail
python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/source_image_sha_missing --expect-fail
python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/source_image_sha_mismatch --expect-fail
python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/contract_example_only_missing --expect-fail
python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/contract_example_only_invalid --expect-fail
python3 scripts/validate-koharu-artifacts.py --root test/koharu_artifacts --allow-missing --print-required-files
python3 scripts/validate-koharu-artifacts.py --root test/koharu_artifacts --allow-missing
python3 scripts/validate-koharu-artifacts.py --root test/koharu_artifacts --allow-missing --emit-handoff-packet
```

`build/koharu_native_draft/` 是 `scripts/make-koharu-native-draft-artifacts.py` 生成的非 active 四件套草稿，只用于 contract shape / validator smoke。它必须保持 `contractExampleOnly=true`，validator 应输出 `verdict = contractExampleOnly`、`readyForShadowOCR = false`、`externalTextBoxesShadowOCRAllowed = false`；不得复制到 `test/koharu_artifacts/`，不得作为真实 detector / SegmentMask / BubbleMask 验收证据。

`scripts/test-speech-recognition-contract.py` 是无设备依赖的源代码契约测试，覆盖 v1.86 状态枚举、运行摘要字段、异步 run ID 隔离、UI 取消/翻译状态和 CI 动态 bundle ID。它不能代替真机 Speech 权限、麦克风采集或识别质量测试。

`scripts/test-speech-quality-evaluator.swift` 和 `scripts/test-speech-quality-contract.py` 证明评分算法、隐私边界和 App/CI 接线；`scripts/validate-speech-corpus.py` 证明 manifest 与音频身份。三者都不能代替 v1.96 的真实 Apple Speech 运行报告。

当前基线：

- `output/probe_report.json` 可解析。
- `output/clean_text_diagnostic.json` 可解析。
- `test/1.ground_truth.json` 可解析。
- 最新 `configuration.currentBlockSource = fusedWholePageBubble`。
- 最新 `totalBlocksDetected = 13`，`frameworkComparison.consistencyPassed = true`，`fusionComparison.consistencyPassed = true`。

### 2.2 Cloud Smoke
验证主要集成路径，默认在 GitHub Actions 运行。

触发条件：

- Swift 代码或 Xcode 工程文件改变。
- `TranslationSessionStore`、模型接口、OCR 服务、SwiftUI 入口或 Info.plist 改变。
- 需要确认 target 能编译。
- Speech 状态机或 bundle ID / simulator launch 工作流改变。

默认动作：

```text
Agent B 集中 push codeb/vX.Y-短标题 的核心 commit
  -> task-scoped full：基础静态 + 相关领域契约 + 必要 xcodebuild
  -> 成功后写 full-validation status 并上传未加密 full 结果包
  -> 创建 PR；opened/reopened/ready-for-review 只跑 fast，不监听 synchronize
  -> Agent C 按 manifest 核对 exact SHA、profile、required flags、full status 和 artifact
  -> C 退回：B 修复 push，新 SHA 重新跑对应 full
  -> C 通过：PR merge；第二父 full status success 才走 merge fast，否则回退 full
  -> 删除远端 codeb/... 候选分支
```

云端最低命令等价于：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project AITRANS.xcodeproj \
  -scheme AITRANS \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath .derivedData \
  CODE_SIGNING_ALLOWED=NO build
```

当前基线：

- 近期多轮该 build 通过。
- 构建日志可能出现 CoreSimulator 沙盒警告，只要最终 `BUILD SUCCEEDED` 即可作为 build 通过。

### 2.3 Stage Regression
覆盖当前阶段核心模块。

触发条件：

- 修改漫画探针、OCR 合并、覆盖绘制、报告模型、clean text diagnostic、translation quality gate、Local/Mock 模型适配。
- 修改会影响 `probe_report.json` 结构或 `output/` 产物。

默认动作：push 先由 GitHub Actions 跑静态检查、JSON 检查、Xcode build 和结果包生成；需要探针产物时再手动 `workflow_dispatch` 运行 `ci-fast` 或 `full`。若完整漫画探针因 GitHub-hosted macOS runner、GGUF、模拟器容器或 App 沙盒访问不稳定而不能运行，workflow 必须生成失败摘要或跳过说明，不能伪造新 `output/`。

人工明确要求本机运行时命令：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project AITRANS.xcodeproj \
  -scheme AITRANS \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath .derivedData \
  CODE_SIGNING_ALLOWED=NO build
```

运行 App 内开发页 `运行漫画覆盖翻译探针`，或用 DEBUG 环境变量触发：

```sh
AITRANS_RUN_MANGA_PROBE=1
```

导出输出：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer scripts/export-probe-output.sh booted
```

检查报告：

```sh
python3 -m json.tool output/probe_report.json
python3 -m json.tool output/clean_text_diagnostic.json
python3 -m json.tool test/1.ground_truth.json
```

当前基线：

- `configuration.currentBlockSource = fusedWholePageBubble`
- `totalBlocksDetected = 13`
- `postFusionCleanup.blockCountBeforeCleanup = 16`
- `postFusionCleanup.blockCountAfterCleanup = 13`
- `postFusionCleanup.rejectedBlockCount = 3`
- `groundTruthMatchedBlocks = 13`
- `groundTruthUnmatchedBlocks = 0`
- `averageCoreDialogueOCRSimilarity = 0.7106`
- `averageDecorativeOCRSimilarity = 0.8000`
- `wholePageAccuracyVsGroundTruth = 0.5972`
- `bubbleFirstAccuracyVsGroundTruth = 0.7300`
- `fusion.fused.accuracyVsGroundTruth = 0.7384`
- `frameworkComparison.consistencyPassed = true`
- `fusionComparison.consistencyPassed = true`
- `textRegionCropReport.totalRegions = 13`
- `textRegionCropReport.cropSucceededCount = 10`
- `textRegionCropReport.adoptedCount = 0`
- `textRegionCropReport.rejectedCount = 13`
- `bubbleSubRegionReport.totalSubRegions = 11`
- `bubbleSubRegionReport.clampEligibleCount = 2`
- `bubbleSubRegionReport.oversizedBubbleIDs = [4, 6, 7]`
- `textRegionCropReport.clampSources = { bubbleBBox: 9, contentRect: 2, subRegion: 2 }`
- `subRegion` clamp 实际用于块 `[6, 8]`
- `bubbleMaskReport.instanceCount = 8`
- `bubbleMaskReport.maskSafeLayoutBlocks = 13`
- `bubbleMaskReport.bboxFallbackBlocks = 0`
- `bubbleMaskReport.inconsistentBubbleAssignmentBlocks = [4, 5, 11, 12]`
- `bubbleMaskReport.renderMaskOverflowBlocks = []`
- `cropMaskCoverage` 低的块 `[4, 5, 9, 12]`
- `bubbleAssignmentCorrectionReport.recommendedCorrectionBlocks = [5, 11]`
- `bubbleAssignmentCorrectionReport.appliedToCropClampBlocks = [5]`
- `bubbleAssignmentCorrectionReport.rejectedCorrectionBlocks = [4, 11, 12]`
- `bubbleSplitCandidateReport.parentBubbleIDs = [4, 6, 7]`
- `bubbleSplitCandidateReport.candidateCount = 6`
- `bubbleSplitCandidateReport.clampEligibleCount = 3`
- `bubbleSplitCandidateReport.appliedToCropClampBlocks = [5, 9, 10]`
- `textBoxCandidateReport.usedForCropBlocks = []`
- `preCropTextBoxPlanReport.planCount = 37`
- `preCropTextBoxPlanReport.shadowOCREligiblePlanCount = 29`
- `preCropTextBoxPlanReport.selectedForShadowOCRBlocks = [0, 1, 2, 3, 5, 6, 7, 8, 9, 10, 11]`
- `preCropTextBoxPlanReport.stoppedBlocks = [4, 12]`
- `cropExperimentReport.candidateCount = 48`
- `cropExperimentReport.controlCandidateCount = 13`
- `cropExperimentReport.ocrSucceededCount = 36`
- `cropExperimentReport.betterThanControlCount = 13`
- `cropExperimentReport.promotedShadowBlocks = []`
- `cropExperimentReport.stoppedBlocks = [2, 3, 4, 5, 7, 9, 11, 12]`
- `cropExperimentReport` 每块候选数最大为 4，即 control + 最多 3 个 shadow 候选；v18 shadow 候选优先来自 `preCropTextBoxPlan.*`
- `textBoxPlanFailureReport.evaluatedBlockCount = 13`
- `textBoxPlanFailureReport.evaluatedPlanCount = 37`
- `textBoxPlanFailureReport.evaluatedCandidateCount = 35`
- `textBoxPlanFailureReport.betterThanControlCandidateCount = 13`
- `textBoxPlanFailureReport.promotedShadowBlockCount = 0`
- `textBoxPlanFailureReport.stopRecommendedBlocks = [2, 3, 4, 5, 7, 9, 11, 12]`
- `textBoxPlanFailureReport.continueGeometryResearchBlocks = [1, 6, 10]`
- `textBoxPlanFailureReport.candidatePromotionBlockedBlocks = [1, 2, 4, 5, 6, 9, 10]`
- `lineTextBoxPlanReport.targetBlocks = [1, 6, 10]`
- `lineTextBoxPlanReport.planCount = 12`
- `lineTextBoxPlanReport.shadowOCREligiblePlanCount = 12`
- `lineCropExperimentReport.candidateCount = 12`
- `lineCropExperimentReport.ocrSucceededCount = 12`
- `lineCropExperimentReport.betterThanControlCount = 5`
- `lineCropExperimentReport.promotedLineShadowBlocks = []`
- `lineCropExperimentReport.stoppedAfterLineResearchBlocks = [1, 6, 10]`
- `externalArtifactReadinessReport.manifestFound = false`
- `externalArtifactReadinessReport.textBoxesFound = false`
- `externalArtifactReadinessReport.bubbleMaskFound = false`
- `externalArtifactReadinessReport.segmentMaskFound = false`
- `externalArtifactReadinessReport.readinessVerdict = manifestMissing`
- `externalArtifactReadinessReport.nextAction = stopUntilArtifactsProvided`
- `externalArtifactReadinessReport.missingArtifacts = [manifest, TextBoxes, BubbleMask, SegmentMask]`
- `externalArtifactReadinessReport.blockAlignment.count = 13`
- 默认缺 active artifact 时，`externalTextBoxShadowOCRReport.executed = false`、`gateVerdict = manifestMissing`、`candidateCount = 0`、`ocrExecutedCount = 0`、`promotedExternalShadowBlocks = []`、`skippedBlocks = [0...12]`。
- 若真实 `test/koharu_artifacts/` readiness 通过，`externalTextBoxShadowOCRReport` 每块最多生成 1 个 `externalArtifact.textBoxCrop` candidate；选择和 report-only promotion 不能读取 `test/1.ground_truth.json`，且不得改变 `finalTextUsedForTranslation`、主覆盖图、`blockPassed`、`configuration.currentBlockSource` 或 `textRegionCropReport.adoptedCount`。
- v1.18 起云端 `ci-fast` 也必须产出 `internalStructureBottleneckReport`；`evaluatedBlockCount` 必须等于 `totalBlocksDetected`，`primaryBottleneckBreakdown` 和 `recommendedActionBreakdown` 必须非空，`1_ocr_probe_text.txt` 必须包含 `internalStructureBottleneck` 逐块摘要。
- v1.19 起云端 `ci-fast` 也必须产出 `routingDrivenTranslationComparisonReport` 和 `ocrCharacterDamageAuditReport`；前者 `enabled = true`、`evaluatedCaseCount <= 5`，target 只能来自 `modelTranslationQuality` 路由块，后者 `enabled = true`、`evaluatedBlockCount > 0`，并写出 damaged / missing / extra / substitution token 证据。`1_ocr_probe_text.txt` 必须包含两个新报告的逐块摘要。
- v1.20 起云端 `ci-fast` 也必须产出 `readingOrderStructureAuditReport`；`enabled = true`、`evaluatedBlockCount == totalBlocksDetected`、`cases.count == totalBlocksDetected`，`recommendedStructureActionBreakdown`、`bubbleAssignmentRiskBreakdown`、`textBoxEvidenceBreakdown`、`segmentMaskEvidenceBreakdown` 必须非空。`1_ocr_probe_text.txt` 必须包含报告级 `readingOrderStructureAuditReport` summary 和每块 `readingOrderStructureAudit` 摘要；该报告不得改变 `blocks` 顺序、`finalTextUsedForTranslation`、主覆盖图、`blockPassed` 或失败分类。
- v1.21 起云端 `ci-fast` 也必须产出 `structureActionCandidateReport`；`enabled = true`、`evaluatedBlockCount == totalBlocksDetected`、`candidateCount >= 1`，`candidateTypeBreakdown`、`promotionVerdictBreakdown`、`recommendedNextStepBreakdown` 必须非空。每个 candidate 必须保持 `diagnosticOnly = true`、`groundTruthUsedForPlanning = false`、`wouldChangeMainFlow = false`；`1_ocr_probe_text.txt` 必须包含报告级 `structureActionCandidateReport` summary 和每块 `structureActionCandidates` 摘要。该报告只复用已有 shadow / geometry / render 证据，不新增昂贵 OCR / LLM，不改变 `blocks` 顺序、`finalTextUsedForTranslation`、主覆盖图、`blockPassed`、失败分类或 post-fusion cleanup。
- v1.22 起云端 `ci-fast` 也必须产出 `koharuArtifactDAGReport`；`enabled = true`、`evaluatedBlockCount == totalBlocksDetected`、`stageCount >= 8`、`edgeCount >= 8`，`stageStatusBreakdown`、`artifactKindBreakdown`、`firstBlockingStageBreakdown`、`downstreamImpactBreakdown` 必须非空。每个 `dependencyEdges[]` 必须保持 `diagnosticOnly = true`、`wouldChangeMainFlow = false`；每个 `blockTraces[]` 必须含关键阶段 trace，至少覆盖 `bubbleMask`、`textBoxes`、`segmentMask`、`ocrText`、`translation`、`renderLayout` 中 4 个。`1_ocr_probe_text.txt` 必须包含报告级 `koharuArtifactDAGReport` summary 和逐块 `koharuArtifactTrace` 摘要；该报告只复用既有证据，不新增 OCR / LLM，不改变主 OCR、翻译输入、覆盖图、`blockPassed`、失败分类、post-fusion cleanup 或候选选择。
- v1.23 起云端 `ci-fast` 也必须产出 `koharuStageGapReplicationReport`；`enabled = true`、`evaluatedBlockCount == totalBlocksDetected`、`canonicalStageCount >= 9`、`workPackageCount >= 1`，`stageCapabilityBreakdown`、`gapCategoryBreakdown`、`replicationReadinessBreakdown` 必须非空。每个 `stageGaps[]` 必须保持 `diagnosticOnly = true`、`wouldChangeMainFlow = false`、`groundTruthUsedForPlanning = false`；每个 promotion gate 的 `groundTruthUsedForDecision = false`；`workPackages[]` 至少包含一个 `requiresRealExternalArtifact = true` 的包；`blockPlans.count == totalBlocksDetected` 且含 `firstBlockingStageFromDAG`、`primaryGapCategory`、`recommendedWorkPackageID`、`nextAction`。`1_ocr_probe_text.txt` 必须包含报告级 `koharuStageGapReplicationReport` summary 和逐块 `koharuStageGapPlan` 摘要；该报告只把 v1.22 DAG 和既有诊断转成复刻计划，不新增 OCR / LLM，不改变主 OCR、翻译输入、覆盖图、`blockPassed`、失败分类、post-fusion cleanup 或候选选择。
- v1.24 起云端 `ci-fast` 也必须产出 `koharuNativeReplicationScoreboardReport`；`enabled = true`、`source = AITRANSProbe`、`evaluatedBlockCount == totalBlocksDetected`、`stageScorecardCount >= 9`、`gateCount >= 8`、`workItemCount >= 1`，`externalArtifactsRequiredForThisReport = false`、`groundTruthUsedForDecision = false`、`groundTruthUsedForEvaluationOnly = true`。`stageStatusBreakdown`、`gateStatusBreakdown`、`blockPrimaryBottleneckBreakdown`、`recommendedPriorityBreakdown` 必须非空；每个 `stageScorecards[]` 必须保持 `diagnosticOnly = true`、`wouldChangeMainFlow = false`、`groundTruthUsedForDecision = false`；每个 `gateLedger[]` 的 `groundTruthUsedForDecision = false`；`blockScorecards.count == totalBlocksDetected` 且每块包含 `primaryNativeStage`、`primaryBottleneck`、`recommendedPriority`、`priorityUsedGroundTruth = false`、`recommendedWorkItemID`、`nextAction`；`recommendedNextWorkItems[]` 至少包含 `P0` 或 `stop` 的 stoplist / native scoreboard 工作项。`1_ocr_probe_text.txt` 必须包含报告级 `koharuNativeReplicationScoreboardReport` summary 和逐块 `koharuNativeBlockScorecard` 摘要。该报告只复用现有 probe 证据，不新增 OCR / LLM，不改变主 OCR、翻译输入、覆盖图、`blockPassed`、失败分类、post-fusion cleanup 或候选选择；缺真实 artifact 只能记为 optional external path，不阻塞 native scoreboard。
- v1.25 起云端 `ci-fast` 也必须产出 `nativeTextBoxProxyLedgerReport`；`enabled = true`、`source = AITRANSProbe`、`referenceWorkItemID = WI-native-textbox-artifact-scorecard`、`evaluatedBlockCount == totalBlocksDetected`、`groundTruthUsedForDecision = false`、`groundTruthUsedForEvaluationOnly = true`、`wouldChangeMainFlow = false`、`diagnosticOnly = true`。`blockLedgers.count == totalBlocksDetected`，`gateLedger.count >= 10`，`qualityStatusBreakdown`、`candidateSourceBreakdown`、`freezeReasonBreakdown`、`nextActionBreakdown` 必须非空；`stoplist[]` 应覆盖 `textBoxPlanFailureReport.stopRecommendedBlocks` 和 `lineCropExperimentReport.stoppedAfterLineResearchBlocks` 的并集，除非上游报告为空。每个 block ledger 必须保持 `groundTruthUsedForDecision = false`、`diagnosticOnly = true`、`wouldChangeMainFlow = false`；`1_ocr_probe_text.txt` 必须包含报告级 `nativeTextBoxProxyLedgerReport` summary 和逐块 `nativeTextBoxProxyLedger` 摘要。该报告只聚合现有 TextBox / crop / line / BubbleMask / SegmentMask / OCR damage / scoreboard 证据，不新增 OCR / LLM，不改变主 OCR、翻译输入、覆盖图、`blockPassed`、失败分类、post-fusion cleanup 或候选选择。
- v1.26 起云端 `ci-fast` 也必须产出 `bubbleMaskAssignmentSplitScoreboardReport`；`enabled = true`、`source = AITRANSProbe`、`referenceWorkItemID = WI-bubblemask-assignment-split-scorecard`、`referenceKoharuArtifact = BubbleMask`、`evaluatedBlockCount == totalBlocksDetected`、`evaluatedBubbleCount == bubbleMaskReport.instanceCount`、`groundTruthUsedForDecision = false`、`groundTruthUsedForEvaluationOnly = true`、`wouldChangeMainFlow = false`、`diagnosticOnly = true`。`blockScorecards.count == totalBlocksDetected`，`bubbleScorecards.count == bubbleMaskReport.instanceCount`，`splitCandidateLedgers.count == bubbleSplitCandidateReport.candidateCount`，`gateLedger.count >= 10`，`assignmentStatusBreakdown`、`splitRiskBreakdown`、`siblingLayoutStatusBreakdown`、`renderMaskStatusBreakdown`、`nextActionBreakdown` 必须非空；`conflictBlocks` 应覆盖 `bubbleMaskReport.inconsistentBubbleAssignmentBlocks`，除非上游为空；每个 block scorecard 必须保持 `groundTruthUsedForDecision = false`、`diagnosticOnly = true`、`wouldChangeMainFlow = false`；`1_ocr_probe_text.txt` 必须包含报告级 `bubbleMaskAssignmentSplitScoreboardReport` summary 和逐块 `bubbleMaskScoreboard` 摘要。该报告只聚合现有 BubbleMask proxy / assignment / split / sibling layout / render / Native TextBox ledger 证据，不新增 OCR / LLM，不改变主 OCR、翻译输入、覆盖图、`blockPassed`、失败分类、post-fusion cleanup、候选选择、`safeLayoutRect` 或 `configuration.currentBlockSource`。
- v1.27 起云端 `ci-fast` 也必须产出 `segmentMaskProxyCoverageScoreboardReport`；`enabled = true`、`source = AITRANSProbe`、`referenceWorkItemID = WI-segmentmask-proxy-coverage-scorecard`、`referenceKoharuArtifact = SegmentMask`、`evaluatedBlockCount == totalBlocksDetected`、`glyphMaskBlockCount == segmentMaskReport.glyphMaskBlocks`、`groundTruthUsedForDecision = false`、`groundTruthUsedForEvaluationOnly = true`、`wouldChangeMainFlow = false`、`diagnosticOnly = true`、`proxyNotRealSegmentMask = true`。`blockScorecards.count == totalBlocksDetected`，`cleanupLedgerCount >= glyphMaskBlockCount`，`gateLedger.count >= 12`，`coverageStatusBreakdown`、`cleanupStatusBreakdown`、`renderMaskStatusBreakdown`、`backgroundFillStatusBreakdown`、`nextActionBreakdown` 必须非空；`usableForCleanupBlocks` / `usableForCropEvidenceBlocks` / `weakSegmentBlocks` 应覆盖 `segmentMaskReport` 对应列表，除非上游为空。每个 block scorecard 必须保持 `groundTruthUsedForDecision = false`、`diagnosticOnly = true`、`wouldChangeMainFlow = false`；`1_ocr_probe_text.txt` 必须包含报告级 `segmentMaskProxyCoverageScoreboardReport` summary 和逐块 `segmentMaskProxyScoreboard` 摘要。该报告只聚合现有 glyph mask / SegmentMask proxy / TextBox / BubbleMask / background fill / render 证据，不新增 OCR / LLM，不改变主 OCR、翻译输入、覆盖图、`blockPassed`、失败分类、post-fusion cleanup、候选选择、`safeLayoutRect`、`glyphMaskFillRects`、背景填充行为或 `configuration.currentBlockSource`。
- v1.28 起云端 `ci-fast` 也必须产出 `koharuArtifactConvergenceReport`；`enabled = true`、`source = AITRANSProbe`、`referencePipeline = Koharu`、`evaluatedBlockCount == totalBlocksDetected`、`stageCount >= 9`、`blockPathCount == totalBlocksDetected`、`workItemLedgerCount >= 6`、`gateCount >= 10`、`groundTruthUsedForDecision = false`、`groundTruthUsedForEvaluationOnly = true`、`wouldChangeMainFlow = false`、`diagnosticOnly = true`、`externalArtifactsRequiredForThisReport = false`。`convergenceStatusBreakdown`、`firstBlockingArtifactBreakdown`、`primaryNextActionBreakdown`、`workItemStatusBreakdown` 必须非空；`closedWorkItems` 至少包含 `WI-native-textbox-artifact-scorecard`、`WI-bubblemask-assignment-split-scorecard`、`WI-segmentmask-proxy-coverage-scorecard`；v1.29 起 `referenceReports` 必须包含 `translationModelFloorComparisonReport`，且 `WI-translation-model-floor-comparison` 不再只是 v1.28 的未执行 open 状态；v1.58 起 `workItemLedger` 必须包含 `WI-koharu-native-artifact-bundle-lite-textbox-segment-linkage` 和 `WI-koharu-native-promotion-gate-lite-textbox-segment-linkage`，`gateLedger` 必须包含 `G-koharu-convergence-bundle-lite-textbox-segment-linkage` 和 `G-koharu-convergence-promotion-lite-textbox-segment-linkage`，`stages[]` / `blockPaths[]` 必须能把 weak / fallback / rejected / wrong-bubble linkage 传播为 TextBoxes / SegmentMask 阻塞；v1.64 起 `workItemLedger` 必须包含 `WI-external-textbox-orientation-shadow-path`，`gateLedger` 必须包含 `G-external-textbox-orientation-shadow-path`，并核对 `orientationShadowPathPartialBlocks`、`orientationUnsupportedBlocks`、`orientationUnsupportedReasonBreakdown` 已进入 decision signals；partial 或 unsupported 块不得被判为 `closedReportOnly` 或 passed；v1.69 起 `workItemLedger` 必须包含 `WI-external-textbox-shadow-ocr-coverage`，`gateLedger` 必须包含 `G-external-textbox-shadow-ocr-coverage`，ready artifact 后若 shadow OCR report 缺失、`executed=false`、`candidateCount=0`、`ocrExecutedCount=0` 或 `ocrSucceededCount=0`，ExternalArtifacts stage 不得为 `nativeReady`，coverage gate status 必须为 `blocked` 而不是 warning；v1.68 起 `referenceReports` 必须包含 `koharuArtifactIdentityReconciliationReport`，`workItemLedger` 必须包含 `WI-koharu-artifact-identity-reconciliation`，`gateLedger` 必须包含 `G-koharu-artifact-identity-reconciliation-ready`，同一 coverage work item / gate 必须消费 `identityReconciliationVerdict`、`readyForCIManifestComparison` 和 App 侧 identity receipt verdict / files / hashes。v1.69 起 `G-ci-fast-report-availability` 的 threshold / decision signals 必须覆盖当前 v1.24-v1.70 convergence dependency set，并写出 `missingReportCount`、`missingReports` 和 `requiredReportSpan`，不得继续只描述 v1.24-v1.27 旧依赖。每个 `stages[]`、`blockPaths[]`、`workItemLedger[]`、`gateLedger[]` 必须保持 `groundTruthUsedForDecision = false`；`1_ocr_probe_text.txt` 必须包含报告级 `koharuArtifactConvergenceReport` summary、逐块 `koharuArtifactPath` 摘要、`convergenceBundleTextBoxSegmentLinkage`、`convergencePromotionTextBoxSegmentLinkage`、`convergenceExternalShadowOCRCoverage`、`convergenceExternalTextBoxOrientation` 和 `convergenceArtifactIdentityReconciliation`。该报告只聚合既有 DAG / stage gap / native scoreboard / TextBox / BubbleMask / SegmentMask / external gate / clean text / diagnostics / blocks，不新增 OCR / LLM，不改变主 OCR、翻译输入、覆盖图、`blockPassed`、失败分类、post-fusion cleanup、候选选择、`safeLayoutRect`、`glyphMaskFillRects`、背景填充行为、渲染逻辑或 `configuration.currentBlockSource`。
- v1.70 起同一 convergence 验收还必须覆盖 App/CI handoff strict closure：artifact archive 不能配 `probe_mode=skip`，coverage work item / gate ID 与 status 必须出现在 smoke 证据里，orientation work item / gate 在 partial 或 unsupported blockers 存在时不得 passed，TXT 摘要必须能让 Agent C 快速看到 coverage / orientation / App-side identity 状态。
- v1.29 起云端 `ci-fast` 也必须产出 `translationModelFloorComparisonReport`；`enabled = true`、`source = AITRANSProbe`、`referenceWorkItemID = WI-translation-model-floor-comparison`、`evaluatedCleanCaseCount == cleanTextDiagnostic.totalCases`、`evaluatedNoisyBlockCount == totalBlocksDetected`、`baselinePassRate == cleanTextDiagnostic.passRate`、`variantPassRate` 和 `passRateDelta` 可解析、`floorVerdict` 非空、`floorVerdictBreakdown`、`promptVariantOutcomeBreakdown`、`failureReasonBreakdown` 非空、`groundTruthUsedForDecision = false`、`groundTruthUsedForEvaluationOnly = true`、`cleanTextGroundTruthUsedForModelFloorOnly = true`、`wouldChangeMainFlow = false`、`diagnosticOnly = true`。`cleanCases.count == cleanTextDiagnostic.totalCases`、`noisyBlockSummaries.count == totalBlocksDetected`、每个 clean case / noisy summary 的 `groundTruthUsedForDecision = false`、`gateLedger.count >= 9`；`1_ocr_probe_text.txt` 必须包含报告级 `translationModelFloorComparisonReport` summary、`translationFloorCleanCase` 和逐块 `translationFloorNoisyBlock` 摘要。该报告允许新增 deterministic strict clean text LLM 诊断调用，但不得替换主 prompt、主译文、覆盖图、`blockPassed`、失败分类、质量规则或模型。
- v1.30 起云端 `ci-fast` 也必须产出 `koharuRenderRegressionLockReport`；`enabled = true`、`source = AITRANSProbe`、`referenceWorkItemID = WI-render-regression-lock`、`referencePipeline = Koharu`、`evaluatedBlockCount == totalBlocksDetected`、`renderLockVerdict` 非空、`renderLockVerdictBreakdown`、`renderStatusBreakdown`、`safeLayoutSourceBreakdown`、`outputFileStatusBreakdown` 非空、`groundTruthUsedForDecision = false`、`groundTruthUsedForEvaluationOnly = true`、`wouldChangeMainFlow = false`、`diagnosticOnly = true`、`proxyNotRealKoharuRenderer = true`。`blockLocks.count == totalBlocksDetected`、`artifactStages.count >= 5`、`gateLedger.count >= 13`、`outputFileChecks` 覆盖 `probe_report.json`、`clean_text_diagnostic.json`、`1_ocr_probe_text.txt`、`1_debug_boxes.png`、`1_translated_overlay.png`；`failureOverlayRequiredBlocks` 必须覆盖所有 `blockPassed = false` 的块。v1.30 起 `koharuArtifactConvergenceReport.referenceReports` 必须包含 `koharuRenderRegressionLockReport`，且 `WI-render-regression-lock` 不再只是 v1.28 的未执行 open 状态；`1_ocr_probe_text.txt` 必须包含报告级 `koharuRenderRegressionLockReport` summary、逐块 `renderLock` 摘要和 convergence render work item 摘要。该报告只聚合现有渲染和输出证据，不新增 OCR / LLM，不改 renderer、safe layout、glyph mask、背景填充、主 OCR、主翻译、`blockPassed` 或失败分类。Agent C 还必须直接核对未加密结果包里的 `output/1_debug_boxes.png` 和 `output/1_translated_overlay.png` 非空。
- v1.31 起云端 `ci-fast` 也必须产出 `koharuPipelineResolverReport`；`enabled = true`、`source = AITRANSProbe`、`referencePipeline = Koharu`、`referenceConcept = EngineInfo.needsProduces.DAGResolver.OpPreview`、`evaluatedBlockCount == totalBlocksDetected`、`nodeCount >= 12`、`edgeCount >= 12`、`blockTraceCount == totalBlocksDetected`、`executionQueueCount >= 6`、`opPreviewCount >= 4`、`gateCount >= 8`、`groundTruthUsedForDecision = false`、`wouldChangeMainFlow = false`、`diagnosticOnly = true`。`nodes[]` 必须包含 `sourceImage`、`contentCrop`、`visionOCRCandidates`、`bubbleCandidates`、`bubbleMaskProxy`、`textBoxProxy`、`segmentMaskProxy`、`ocrText`、`fusionCleanup`、`translations`、`renderedSpritesProxy`、`finalRender`、`externalArtifacts`；`nodeStatusBreakdown`、`artifactAvailabilityBreakdown`、`firstBlockedNodeBreakdown`、`executionItemStatusBreakdown`、`nextActionBreakdown` 必须非空。缺 active `test/koharu_artifacts/` 时，`externalArtifacts` 节点必须保持 missing / blocked，不能把 proxy 冒充真实 artifact；`koharuArtifactConvergenceReport.referenceReports` 必须包含 `koharuPipelineResolverReport`，并且 `workItemLedger` 或 `gateLedger` 必须包含 `WI-koharu-pipeline-resolver-shadow-dag` / `G-koharu-pipeline-resolver-executed`。`1_ocr_probe_text.txt` 必须包含 `koharuPipelineResolverReport` summary、`resolverExecutionQueue` 摘要和逐块 `koharuPipelineResolverTrace`。该报告只聚合现有报告，不新增 OCR / LLM，不改变主 OCR、翻译输入、覆盖图、`blockPassed`、失败分类、post-fusion cleanup、候选选择或渲染行为。
- v1.32 起云端 `ci-fast` 也必须产出 `koharuWorkOrderRouterReport`；`enabled = true`、`source = AITRANSProbe`、`referencePipeline = Koharu`、`referenceConcept = ResolverExecutionQueue.WorkOrderRouter.BudgetGate`、`evaluatedBlockCount == totalBlocksDetected`、`workOrderCount >= 7`、`blockRouteCount == totalBlocksDetected`、`gateCount >= 10`、`groundTruthUsedForDecision = false`、`wouldChangeMainFlow = false`、`diagnosticOnly = true`、`externalArtifactsRequiredForThisReport = false`。`workOrderStatusBreakdown`、`workOrderPriorityBreakdown`、`targetStageBreakdown`、`nextActionBreakdown`、`budgetClassBreakdown` 必须非空；`budgetLedger.ciFastRunnableWorkOrderIDs.count >= 1`；缺 active `test/koharu_artifacts/` 时，external artifact work orders 必须保持 `blockedMissingExternalArtifact` 或等价阻塞状态，不能把 proxy 变成真实 artifact ready。`WO-v132-stop-local-crop-line-deskew`、`WO-v132-request-real-textboxes`、`WO-v132-external-artifact-package-handoff` 必须存在；`WO-v132-stop-local-crop-line-deskew` 不得建议继续 crop / line / deskew 调参。`koharuArtifactConvergenceReport.referenceReports` 必须包含 `koharuWorkOrderRouterReport`，并且 `workItemLedger` 或 `gateLedger` 必须包含 `WI-koharu-workorder-router` / `G-koharu-workorder-router-executed`。`1_ocr_probe_text.txt` 必须包含 `koharuWorkOrderRouterReport` summary、`workOrderQueue` 和逐块 `koharuWorkOrderRoute`。该报告只聚合现有报告，不新增 OCR / LLM，不改变主 OCR、翻译输入、覆盖图、`blockPassed`、失败分类、post-fusion cleanup、候选选择或渲染行为。
- v1.33 起云端 `ci-fast` 也必须产出 `koharuExternalArtifactRequestPacketReport`；`enabled = true`、`source = AITRANSProbe`、`referencePipeline = Koharu`、`referenceConcept = ExternalArtifacts.ContractReadiness.RequestPacket`、`evaluatedBlockCount == totalBlocksDetected`、`requiredFileCount >= 4`、`artifactRequirementCount >= 3`、`blockRequestCount == totalBlocksDetected`、`gateCount >= 13`、`groundTruthUsedForDecision = false`、`wouldChangeMainFlow = false`、`diagnosticOnly = true`、`externalArtifactsRequiredForThisReport = false`。`requiredFiles[]` 必须覆盖 `test/koharu_artifacts/1.manifest.json`、`1.textboxes.json`、`1.bubbles.json`、`1.segment_mask.json`；`artifactRequirements[]` 必须覆盖 `TextBoxes`、`BubbleMask`、`SegmentMask`；缺 active artifact 时 `requestPacketVerdict` 必须是 missing / waiting / blocked 类状态，不能 ready；`forbiddenActiveSources` 必须包含 contract examples、Vision OCR blocks、pre-crop plan、line plan、BubbleMask proxy、SegmentMask proxy、ground truth 和 handwritten ideal boxes 或等价项。`blockRequests.count == totalBlocksDetected`，每块要有 primary work order、needs artifact flags、stoplist / model floor / render lock 信号。`koharuArtifactConvergenceReport.referenceReports` 必须包含 `koharuExternalArtifactRequestPacketReport`，并且 `workItemLedger` 或 `gateLedger` 必须包含 `WI-koharu-external-artifact-request-packet` / `G-koharu-external-artifact-request-packet-executed`。`1_ocr_probe_text.txt` 必须包含 `koharuExternalArtifactRequestPacketReport` summary、`requiredFiles`、`artifactRequirements` 和逐块 `koharuExternalArtifactRequest`。该报告只聚合现有报告，不新增 OCR / LLM，不创建、复制、修改或提交 active `test/koharu_artifacts/`，不改变主 OCR、翻译输入、覆盖图、`blockPassed`、失败分类、post-fusion cleanup、候选选择、safe layout、glyph mask、背景填充或渲染行为。
- v1.34 起云端 `ci-fast` 也必须产出 `koharuNativeAlgorithmReplayMatrixReport`；`enabled = true`、`source = AITRANSProbe`、`referencePipeline = Koharu`、`referenceConcept = NativeAlgorithmReplayMatrix.ProbeEvidenceBudgetGate`、`evaluatedBlockCount == totalBlocksDetected`、`stageCount >= 10`、`candidateCount >= 9`、`blockRouteCount == totalBlocksDetected`、`gateCount >= 14`、`groundTruthUsedForDecision = false`、`wouldChangeMainFlow = false`、`diagnosticOnly = true`、`externalArtifactsRequiredForThisReport = false`。固定 candidates 必须包含 `C-v134-preserve-fused-mainflow-audit`、`C-v134-stop-local-crop-line-deskew`、`C-v134-textbox-proxy-replay-ledger`、`C-v134-bubblemask-assignment-split-replay`、`C-v134-segmentmask-coverage-replay`、`C-v134-ocr-quality-bottleneck-replay`、`C-v134-translation-floor-replay`、`C-v134-render-lock-replay`、`C-v134-external-artifact-handoff-replay`。缺 active artifact 时 external candidate 必须保持 blocked；crop / line / deskew stoplist 必须继续阻止本地调参；model floor、OCR 输入问题和 render lock 必须分开路由。`koharuArtifactConvergenceReport.referenceReports` 必须包含 `koharuNativeAlgorithmReplayMatrixReport`，并且 `workItemLedger` 或 `gateLedger` 必须包含 `WI-koharu-native-algorithm-replay-matrix` / `G-koharu-native-algorithm-replay-matrix-executed`。`1_ocr_probe_text.txt` 必须包含 report summary、`candidateQueue`、`stageMatrix` 和逐块 `koharuNativeReplayRoute`。该报告只聚合现有报告，不新增 OCR / LLM，不改变主 OCR、翻译输入、覆盖图、`blockPassed`、失败分类、post-fusion cleanup、候选选择、safe layout、glyph mask、背景填充、active artifacts 或 `configuration.currentBlockSource`。
- v1.35 起云端 `ci-fast` 也必须产出 `koharuBubbleIndexShadowLedgerReport`；`enabled = true`、`source = AITRANSProbe`、`referencePipeline = Koharu`、`referenceConcept = BubbleIndex.MajorityMaskSafeAreaSiblingPartition`、`evaluatedBlockCount == totalBlocksDetected`、`blockLedgerCount == totalBlocksDetected`、`evaluatedBubbleCount == bubbleMaskReport.instanceCount`、`bubbleLedgerCount == bubbleMaskReport.instanceCount`、`gateCount >= 12`、`groundTruthUsedForDecision = false`、`wouldChangeMainFlow = false`、`diagnosticOnly = true`、`proxyNotRealBubbleMask = true`、`externalArtifactsRequiredForThisReport = false`。`assignmentVerdictBreakdown`、`safeAreaVerdictBreakdown`、`siblingPartitionVerdictBreakdown`、`renderLockVerdictBreakdown`、`bubbleLayoutVerdictBreakdown`、`nextActionBreakdown` 必须非空；每个 block ledger 必须保持 `groundTruthUsedForDecision = false`、`wouldChangeMainFlow = false`、`diagnosticOnly = true`，并写出当前 `bubbleID`、shadow bubble、assignment、safe-area、sibling partition、render lock 和 next action。`koharuArtifactConvergenceReport.referenceReports` 必须包含 `koharuBubbleIndexShadowLedgerReport`，并且 `workItemLedger` 或 `gateLedger` 必须包含 `WI-koharu-bubble-index-shadow-ledger` / `G-koharu-bubble-index-shadow-ledger-executed`。`1_ocr_probe_text.txt` 必须包含 `koharuBubbleIndexShadowLedgerReport` summary、`bubbleIndexBubbleLedger`、`bubbleIndexSiblingLedger` 和逐块 `koharuBubbleIndexBlockLedger`。该报告只聚合现有报告，不新增 OCR / LLM，不改变主 OCR、翻译输入、覆盖图、`safeLayoutRect`、`blockPassed`、失败分类、post-fusion cleanup、候选选择、glyph mask、背景填充、active artifacts 或 `configuration.currentBlockSource`。
- v1.36 起云端 `ci-fast` 也必须产出 `koharuDistanceFieldSafeAreaReport`；`enabled = true`、`source = AITRANSProbe`、`referencePipeline = Koharu`、`referenceConcept = BubbleIndex.DistanceFieldSafePixels.MaximumSafeRect`、`evaluatedBlockCount == totalBlocksDetected`、`bubbleLedgerCount == bubbleMaskReport.instanceCount`、`blockLedgerCount == totalBlocksDetected`、`gateCount >= 10`、`groundTruthUsedForDecision = false`、`groundTruthUsedForEvaluationOnly = true`、`wouldChangeMainFlow = false`、`diagnosticOnly = true`、`proxyNotRealBubbleMask = true`、`usesRoundedRectProxyMask = true`、`externalArtifactsRequiredForThisReport = false`。`safePixelVerdictBreakdown`、`safeRectComparisonBreakdown`、`spriteContainmentBreakdown`、`nextActionBreakdown` 必须非空；每个 block ledger 必须包含当前 `safeLayoutRect`、v1.35 `bubbleIndexShadowSafeRect`、distance-field safe rect 或明确 fallback source、sprite containment、render lock 和 report-only next action。`koharuArtifactConvergenceReport.referenceReports` 必须包含 `koharuDistanceFieldSafeAreaReport`，并且 `workItemLedger` / `gateLedger` 必须包含 `WI-koharu-distance-field-safe-area` / `G-koharu-distance-field-safe-area-executed`。`1_ocr_probe_text.txt` 必须包含 `koharuDistanceFieldSafeAreaReport` summary、`distanceFieldBubbleLedger`、逐块 `distanceFieldBlockLedger` 和 `distanceFieldSiblingLedger`。该报告只在 rounded-rect proxy ID mask 的 bubble bbox 内计算 distance field / safe pixels / maximum safe rect，不新增 OCR / LLM，不改变主 OCR、翻译输入、覆盖图、`safeLayoutRect`、`glyphMaskFillRects`、背景填充、`blockPassed`、失败分类、post-fusion cleanup、候选选择、active artifacts 或 `configuration.currentBlockSource`。
- v1.37 起云端 `ci-fast` 也必须产出 `koharuBubbleAdjacencySeamReport`；`enabled = true`、`source = AITRANSProbe`、`referencePipeline = Koharu`、`referenceConcept = BubbleMask.InstanceAdjacency.SeamPartition`、`evaluatedBlockCount == totalBlocksDetected`、`evaluatedBubbleCount == bubbleMaskReport.instanceCount`、`blockLedgerCount == totalBlocksDetected`、`pairLedgerCount >= 1`、`seamCandidateCount >= bubbleSplitCandidateReport.candidateCount`（若上游为空，必须有明确 warning / fallback note）、`gateCount >= 10`、`groundTruthUsedForDecision = false`、`groundTruthUsedForEvaluationOnly = true`、`wouldChangeMainFlow = false`、`diagnosticOnly = true`、`proxyNotRealBubbleMask = true`、`usesRoundedRectProxyMask = true`、`externalArtifactsRequiredForThisReport = false`。`pairVerdictBreakdown`、`seamCandidateVerdictBreakdown`、`blockSeamRiskBreakdown`、`nextActionBreakdown` 必须非空；block ledgers 必须覆盖 assignment conflict、same-bubble sibling、split candidate、needs real BubbleMask 和 render lock 信号。`koharuArtifactConvergenceReport.referenceReports` 必须包含 `koharuBubbleAdjacencySeamReport`，并且 `workItemLedger` / `gateLedger` 必须包含 `WI-koharu-bubble-adjacency-seam` / `G-koharu-bubble-adjacency-seam-executed`。`1_ocr_probe_text.txt` 必须包含 `koharuBubbleAdjacencySeamReport` summary、`bubbleAdjacencyPair`、`bubbleSeamCandidate` 和逐块 `bubbleSeamBlockLedger`。该报告只聚合现有 proxy / BubbleIndex / DistanceField / split / sibling / OCR damage / render lock 证据，不新增 OCR / LLM，不改变主 OCR、翻译输入、覆盖图、`safeLayoutRect`、DistanceField safe rect、`glyphMaskFillRects`、背景填充、`blockPassed`、失败分类、post-fusion cleanup、候选选择、active artifacts 或 `configuration.currentBlockSource`。
- v1.38 起云端 `ci-fast` 也必须产出 `koharuRenderSpriteFitPlannerReport`；`enabled = true`、`source = AITRANSProbe`、`referencePipeline = Koharu`、`referenceConcept = RenderedSprites.FontSizeSearch.SpriteFitBudget`、`referenceWorkItemID = WI-koharu-render-sprite-fit-planner`、`evaluatedBlockCount == totalBlocksDetected`、`blockLedgerCount == totalBlocksDetected`、`layoutCandidateCount >= totalBlocksDetected`、`gateCount >= 10`、`groundTruthUsedForDecision = false`、`groundTruthUsedForEvaluationOnly = true`、`wouldChangeMainFlow = false`、`diagnosticOnly = true`、`proxyNotRealKoharuRenderer = true`、`proxyNotRealBubbleMask = true`、`externalArtifactsRequiredForThisReport = false`。`fitVerdictBreakdown`、`fontBudgetBreakdown`、`spriteContainmentBreakdown`、`failureOverlayFitBreakdown`、`nextActionBreakdown` 必须非空；block ledgers 必须覆盖当前 safe rect、DistanceField safe rect、BubbleIndex shadow safe rect、render font / sprite bounds、failure overlay fit、seam / sibling / render lock 信号。`koharuArtifactConvergenceReport.referenceReports` 必须包含 `koharuRenderSpriteFitPlannerReport`，并且 `workItemLedger` / `gateLedger` 必须包含 `WI-koharu-render-sprite-fit-planner` / `G-koharu-render-sprite-fit-planner-executed`。`1_ocr_probe_text.txt` 必须包含 `koharuRenderSpriteFitPlannerReport` summary、逐块 `renderSpriteFit`、`renderSpriteLayoutCandidate` 和 `renderSpriteSiblingFit`。该报告只聚合现有 render / BubbleIndex / DistanceField / seam 证据，不新增 OCR / LLM，不重新渲染 PNG，不改变主 OCR、翻译输入、覆盖图、`safeLayoutRect`、DistanceField safe rect、`renderFontSize`、`renderNonTransparentBounds`、`glyphMaskFillRects`、背景填充、`blockPassed`、失败分类、post-fusion cleanup、候选选择、active artifacts 或 `configuration.currentBlockSource`。
- v1.39 起云端 `ci-fast` 也必须产出 `koharuNativeTextBoxDetectorLiteReport`；`enabled = true`、`source = AITRANSProbe`、`referencePipeline = Koharu`、`referenceConcept = TextBoxes.NativeDetectorLite.PreOCRArtifact`、`referenceWorkItemID = WI-koharu-native-textbox-detector-lite`、`evaluatedBlockCount == totalBlocksDetected`、`evaluatedBubbleCount > 0`、`blockLedgerCount == totalBlocksDetected`、`bubbleLedgerCount == evaluatedBubbleCount`、`candidateCount >= 1`、`gateCount >= 8`、`groundTruthUsedForDecision = false`、`groundTruthUsedForEvaluationOnly = true`、`wouldChangeMainFlow = false`、`diagnosticOnly = true`、`proxyNotRealKoharuTextBoxes = true`、`externalArtifactsRequiredForThisReport = false`。`candidateSourceBreakdown`、`candidateVerdictBreakdown`、`blockRelationBreakdown`、`primaryBottleneckBreakdown`、`nextActionBreakdown` 必须非空；candidates 必须标记 `source = nativeDetectorLite`，并记录 bbox、direction、dark pixel density、component count、projection peak、bubble coverage、glyph overlap、`relatedBlockRelations[]` 的 block index / overlap / center-contained / same-bubble / relation reason、`componentCluster` / `singleUnion` / `unionFallback` generation signal 和有上限的 per-bubble candidate pool（最多 4 个 component-cluster + 1 个 diagnostic union fallback，fallback 必须 `shadowOCREligible = false`）。每个 block ledger 必须记录 best candidate 的 coverage ratio、center-contained、same-bubble、candidate verdict 和 shadow eligibility。`koharuArtifactConvergenceReport.referenceReports` 必须包含 `koharuNativeTextBoxDetectorLiteReport`，并且 `workItemLedger` / `gateLedger` 必须包含 `WI-koharu-native-textbox-detector-lite` / `G-koharu-native-textbox-detector-lite-executed`。`1_ocr_probe_text.txt` 必须包含 `koharuNativeTextBoxDetectorLiteReport` summary、带 relation 的 `nativeTextBoxDetectorLiteCandidateLedger`、逐块 `nativeTextBoxDetectorLiteBlockLedger` 和 bubble ledger。该报告默认不执行 shadow OCR，不使用 Vision OCR 文本、ground truth、pre-crop plan、line plan 或 TextRegion crop 结果生成 / 排序候选，不改变主 OCR、翻译输入、覆盖图、`blockPassed`、失败分类、`textRegionCropReport.adoptedCount`、active artifacts 或 `configuration.currentBlockSource`。
- v1.40 起云端 `ci-fast` 也必须产出 `koharuNativeTextBoxDetectorLiteShadowOCRReport`；`enabled = true`、`source = AITRANSProbe`、`referencePipeline = Koharu`、`referenceConcept = TextBoxes.NativeDetectorLite.ShadowOCR`、`referenceWorkItemID = WI-koharu-native-textbox-detector-lite-shadow-ocr`、`evaluatedBlockCount == totalBlocksDetected`、`blockLedgerCount == totalBlocksDetected`、`selectedCandidateCount <= totalBlocksDetected`、`ocrExecutedCount == selectedCandidateCount`、`gateCount >= 9`、`groundTruthUsedForDecision = false`、`groundTruthUsedForEvaluationOnly = true`、`wouldChangeMainFlow = false`、`diagnosticOnly = true`、`proxyNotRealKoharuTextBoxes = true`、`proxyNotRealKoharuOCR = true`、`externalArtifactsRequiredForThisReport = false`。`ocrOutcomeBreakdown`、`qualityDeltaBreakdown`、`candidateSourceBreakdown`、`primaryBottleneckBreakdown`、`nextActionBreakdown` 必须非空或在无候选时明确 blocked ledger；candidates 必须标记 `source = nativeDetectorLite.shadowOCR`，只来自 v1.39 `shadowOCREligible` detector-lite bbox，并按当前 block overlap / center containment 优先，避免同 bubble sibling 共享错误高分候选；full 模式 block ledger 必须记录本块 report-only 最佳 shadow OCR 候选。`verticalCandidate` candidates 必须只做有上限的 `[0,90]` rotation shadow OCR 对照，使用 `ja-JP/ja/en-US/en` 受限 language profile，记录 `rotationApplied`，并由无真值 OCR 质量和当前文本保词率选择 report-only 最佳结果；`G-native-textbox-detector-lite-shadow-ocr-vertical-rotation-budget` 必须存在。`koharuArtifactConvergenceReport.referenceReports` 必须包含 `koharuNativeTextBoxDetectorLiteShadowOCRReport`，并且 `workItemLedger` / `gateLedger` 必须包含 `WI-koharu-native-textbox-detector-lite-shadow-ocr` / `G-koharu-native-textbox-detector-lite-shadow-ocr-executed`。`1_ocr_probe_text.txt` 必须包含 report summary、`nativeTextBoxDetectorLiteShadowOCRRotation`、`nativeTextBoxDetectorLiteShadowOCRCandidate` 和逐块 `nativeTextBoxDetectorLiteShadowOCRBlockLedger`。该报告允许新增受限 Vision crop OCR 调用，不新增 LLM，不用 ground truth 决定候选、排序、OCR 执行、nextAction 或 gate，不改变主 OCR、翻译输入、覆盖图、`finalTextUsedForTranslation`、`blockPassed`、失败分类、`textRegionCropReport.adoptedCount`、active artifacts 或 `configuration.currentBlockSource`。
- v1.41 起云端 `ci-fast` 也必须产出 `koharuNativeTextBoxDetectorLiteRefinementReport`；`enabled = true`、`source = AITRANSProbe`、`referencePipeline = Koharu`、`referenceConcept = TextBoxes.NativeDetectorLite.ClosedLoopRefinement`、`referenceWorkItemID = WI-koharu-native-textbox-detector-lite-refinement`、`evaluatedBlockCount == totalBlocksDetected`、`blockLedgerCount == totalBlocksDetected`、`ocrExecutedCount <= min(6,totalBlocksDetected)` 或报告明确当前 budget、`gateCount >= 8`、`groundTruthUsedForDecision = false`、`groundTruthUsedForEvaluationOnly = true`、`wouldChangeMainFlow = false`、`diagnosticOnly = true`、`proxyNotRealKoharuTextBoxes = true`、`proxyNotRealKoharuOCR = true`、`externalArtifactsRequiredForThisReport = false`。`targetReasonBreakdown`、`refinementStrategyBreakdown`、`ocrOutcomeBreakdown`、`primaryBottleneckBreakdown`、`nextActionBreakdown` 必须非空或在无 eligible target 时明确 `blockedByNoEligibleTargets`；candidates 必须标记 `source = nativeDetectorLite.refinementShadowOCR`，refined bbox 必须从 v1.39 detector-lite 父 bbox 派生。`koharuArtifactConvergenceReport.referenceReports` 必须包含 `koharuNativeTextBoxDetectorLiteRefinementReport`，并且 `workItemLedger` / `gateLedger` 必须包含 `WI-koharu-native-textbox-detector-lite-refinement` / `G-koharu-native-textbox-detector-lite-refinement-executed`。`1_ocr_probe_text.txt` 必须包含 report summary、`nativeTextBoxDetectorLiteRefinementCandidate` 和逐块 `nativeTextBoxDetectorLiteRefinementBlockLedger`。该报告允许新增受限 Vision crop OCR 调用，不新增 LLM，不用 ground truth 决定 target、bbox、排序、OCR 执行、nextAction 或 gate，不改变主 OCR、翻译输入、覆盖图、`finalTextUsedForTranslation`、`blockPassed`、失败分类、`textRegionCropReport.adoptedCount`、active artifacts 或 `configuration.currentBlockSource`。
- v1.42 起云端 `ci-fast` 也必须产出 `koharuNativeTextBoxDetectorLiteClosedLoopReport`；`enabled = true`、`source = AITRANSProbe`、`referencePipeline = Koharu`、`referenceConcept = TextBoxes.NativeDetectorLite.ClosedLoopRouter`、`referenceWorkItemID = WI-koharu-native-textbox-detector-lite-closed-loop-router`、`evaluatedBlockCount == totalBlocksDetected`、`blockLedgerCount == totalBlocksDetected`、`candidateFamilyCount == totalBlocksDetected`、`gateCount >= 8`、`groundTruthUsedForDecision = false`、`groundTruthUsedForEvaluationOnly = true`、`wouldChangeMainFlow = false`、`diagnosticOnly = true`、`proxyNotRealKoharuTextBoxes = true`、`proxyNotRealKoharuOCR = true`、`externalArtifactsRequiredForThisReport = false`。`routeBreakdown`、`candidateFamilyVerdictBreakdown`、`ocrOutcomeRollup`、`primaryBottleneckBreakdown`、`nextActionBreakdown` 必须非空，或在上游 v1.39-v1.41 报告缺失时明确 `blockedByMissingUpstreamReports`。`stopBlockIndexes`、`fullProbeReviewBlockIndexes`、`realTextBoxesNeededBlocks`、`realBubbleMaskNeededBlocks`、`realSegmentMaskNeededBlocks`、`modelFloorRoutedBlocks`、`renderLockRoutedBlocks` 字段必须存在；每个 block ledger 必须保留 `finalTextUsedForTranslation` 原值、route、nextAction、failureCategory、BubbleMask / SegmentMask / translation / render 证据、decisionSignals 和 evaluationSignals。`koharuArtifactConvergenceReport.referenceReports` 必须包含 `koharuNativeTextBoxDetectorLiteClosedLoopReport`，并且 `workItemLedger` / `gateLedger` 必须包含 `WI-koharu-native-textbox-detector-lite-closed-loop-router` / `G-koharu-native-textbox-detector-lite-closed-loop-router-executed`。`1_ocr_probe_text.txt` 必须包含 `koharuNativeTextBoxDetectorLiteClosedLoopReport` summary、`nativeTextBoxDetectorLiteCandidateFamily` 和逐块 `nativeTextBoxDetectorLiteClosedLoopBlockLedger`。该报告不新增 OCR / LLM / PNG，不使用 ground truth 决定 route、nextAction、gate 或 candidate family verdict，不改变主 OCR、翻译输入、覆盖图、`finalTextUsedForTranslation`、`blockPassed`、失败分类、`textRegionCropReport.adoptedCount`、active artifacts 或 `configuration.currentBlockSource`。
- v1.43 起云端 `ci-fast` 也必须产出 `koharuNativeBubbleMaskInstanceLiteReport`；`enabled = true`、`source = AITRANSProbe`、`referencePipeline = Koharu`、`referenceConcept = BubbleMask.NativeInstanceLite.PixelIDMask`、`referenceWorkItemID = WI-koharu-native-bubblemask-instance-lite`、`evaluatedBlockCount == totalBlocksDetected`、`blockLedgerCount == totalBlocksDetected`、`gateCount >= 8`、`groundTruthUsedForDecision = false`、`groundTruthUsedForEvaluationOnly = true`、`wouldChangeMainFlow = false`、`diagnosticOnly = true`、`nativeInstanceLite = true`、`proxyNotRealKoharuBubbleMask = true`、`usesSourceImagePixels = true`、`externalArtifactsRequiredForThisReport = false`。`instanceCount >= 1`，若像素证据不足则必须写 `instanceLiteVerdict = blockedByInsufficientPixelEvidence`，不能静默空报告；`assignmentAgreementBreakdown`、`splitRiskBreakdown`、`siblingPartitionBreakdown`、`safeRectComparisonBreakdown`、`safeRectPolicyBreakdown`、`spriteBlockScopedContainmentBreakdown`、`spriteSiblingCollisionBreakdown`、`primaryBottleneckBreakdown`、`nextActionBreakdown` 必须非空或有明确 warning / blocked gate。每个 block ledger 必须包含 current bubble、instance-lite majority、由实例像素 erosion / projection 派生的 `instanceLiteSafeRect`、实际 report-only `instanceLiteBlockScopedSafeRect`、`instanceLiteSafeRectPolicy`、`spriteBlockScopedSafeRectContainmentRatio`、`spriteContainedByBlockScopedSafeRect`、`spriteContainmentPolicy`、`sameInstanceRenderSpriteOverlapCount`、`spriteSiblingCollisionPolicy`、render lock、translation failure route、detector-lite closed-loop route 和 nextAction；同 instance 多 block 时 policy 必须避免共享同一个最大 safe rect，并输出 sibling render sprite overlap / collision policy。`koharuArtifactConvergenceReport.referenceReports` 必须包含 `koharuNativeBubbleMaskInstanceLiteReport`，并且 `workItemLedger` / `gateLedger` 必须包含 `WI-koharu-native-bubblemask-instance-lite` / `G-koharu-native-bubblemask-instance-lite-executed`。`1_ocr_probe_text.txt` 必须包含 `koharuNativeBubbleMaskInstanceLiteReport` summary、`nativeBubbleMaskInstanceLiteSafeRectPolicy`、`nativeBubbleMaskInstanceLiteBlockScopedSpriteContainment`、`nativeBubbleMaskInstanceLiteSiblingSpriteCollision`、`nativeBubbleMaskInstanceLiteInstance`、逐块 `nativeBubbleMaskInstanceLiteBlockLedger`、`nativeBubbleMaskInstanceLiteSiblingLedger` 和 `nativeBubbleMaskInstanceLiteAdjacencyLedger`。该报告不新增 OCR / LLM / PNG，不创建或修改 active `test/koharu_artifacts/`，不把 instance-lite mask 冒充真实 Koharu `BubbleMask`，不改变主 OCR、翻译输入、覆盖图、`safeLayoutRect`、DistanceField safe rect、renderer、`blockPassed`、失败分类、`textRegionCropReport.adoptedCount`、active artifacts 或 `configuration.currentBlockSource`。
- v1.44 起云端 `ci-fast` 也必须产出 `koharuNativeSegmentMaskRefinementLiteReport`；`enabled = true`、`source = AITRANSProbe`、`referencePipeline = Koharu`、`referenceConcept = SegmentMask.NativeRefinementLite.TextBoxConstrainedGlyphMask`、`referenceWorkItemID = WI-koharu-native-segmentmask-refinement-lite`、`evaluatedBlockCount == totalBlocksDetected`、`blockLedgerCount == totalBlocksDetected`、`candidateLedgerCount >= totalBlocksDetected`、`gateCount >= 8`、`groundTruthUsedForDecision = false`、`groundTruthUsedForEvaluationOnly = true`、`wouldChangeMainFlow = false`、`diagnosticOnly = true`、`nativeRefinementLite = true`、`proxyNotRealKoharuSegmentMask = true`、`usesSourceImagePixels = true`、`usesTextBoxConstraints = true`、`usesBubbleMaskConstraints = true`、`externalArtifactsRequiredForThisReport = false`。若像素证据不足必须写 `refinementLiteVerdict = blockedByInsufficientPixelEvidence`，不能静默空报告；`candidateSourceBreakdown`、`candidateVerdictBreakdown`、`pixelEvidenceBreakdown`、`textboxClampBreakdown`、`textBoxSegmentLinkBreakdown`、`bubbleClampBreakdown`、`componentFilteringBreakdown`、`maskContainmentBreakdown`、`maskMajorityAgreementBreakdown`、`primaryBottleneckBreakdown`、`nextActionBreakdown` 必须非空或有明确 warning / blocked gate。每个 candidate ledger 必须包含 source TextBox candidate verdict、shadow eligibility、block overlap ratio、same-bubble、accepted-for-SegmentMask 和 link verdict；每个 block ledger 必须包含 selected candidate、selected source TextBox candidate ID / link verdict、pixel counts、TextBox / BubbleMask clamp、`maskContainedByTextBoxRatio`、`maskContainedByBubbleRatio`、`maskMajorityAgreement`、glyph overlap、SegmentMask proxy agreement、clear-text / OCR crop / render containment 可用性、primary bottleneck 和 nextAction。报告必须输出 `segmentFromAcceptedTextBoxCount`、`segmentFromRejectedTextBoxCount`、`segmentFromFallbackBBoxCount`，并包含 `G-native-segmentmask-refinement-lite-textbox-linkage-audited` 和 `G-native-segmentmask-refinement-lite-no-rejected-textbox-silent-selection` gates。`koharuArtifactConvergenceReport.referenceReports` 必须包含 `koharuNativeSegmentMaskRefinementLiteReport`，并且 `workItemLedger` / `gateLedger` 必须包含 `WI-koharu-native-segmentmask-refinement-lite` / `G-koharu-native-segmentmask-refinement-lite-executed`。`1_ocr_probe_text.txt` 必须包含 `koharuNativeSegmentMaskRefinementLiteReport` summary、`nativeSegmentMaskRefinementLiteTextBoxLink`、`nativeSegmentMaskRefinementLiteMajorityAgreement`、`nativeSegmentMaskRefinementLiteCandidate`、逐块 `nativeSegmentMaskRefinementLiteBlockLedger` 和 `nativeSegmentMaskRefinementLiteSiblingLedger`。该报告不新增 OCR / LLM / PNG，不创建或修改 active `test/koharu_artifacts/`，不把 refinement-lite mask 冒充真实 Koharu `SegmentMask`，不改变主 OCR、翻译输入、覆盖图、`safeLayoutRect`、`glyphMaskFillRects`、背景填充、renderer、`blockPassed`、失败分类、`textRegionCropReport.adoptedCount`、active artifacts 或 `configuration.currentBlockSource`。
- v1.45 起云端 `ci-fast` 也必须产出 `koharuNativeArtifactBundleLiteReport`；`enabled = true`、`source = AITRANSProbe`、`referencePipeline = Koharu`、`referenceConcept = ArtifactBundle.NativeLite.TextBoxesBubbleMaskSegmentMaskConsistency`、`referenceWorkItemID = WI-koharu-native-artifact-bundle-lite`、`evaluatedBlockCount == totalBlocksDetected`、`bundleLedgerCount == totalBlocksDetected`、`consistencyEdgeCount >= totalBlocksDetected`、`workItemCount >= 1`、`gateCount >= 8`、`groundTruthUsedForDecision = false`、`groundTruthUsedForEvaluationOnly = true`、`wouldChangeMainFlow = false`、`diagnosticOnly = true`、`nativeBundleLite = true`、`proxyNotRealKoharuTextBoxes = true`、`proxyNotRealKoharuBubbleMask = true`、`proxyNotRealKoharuSegmentMask = true`、`externalArtifactsRequiredForThisReport = false`。每个 final block 必须有 bundle ledger，至少包含 selected TextBox / Bubble / Segment component、OCR evidence、translation route、render evidence、artifact consistency verdict、primary blocking artifact 和 nextAction；v1.57 起每块 ledger 还必须包含 `selectedTextBoxSegmentLinkVerdict`、`textBoxSegmentLinkageStatus`、`textBoxSegmentLinkageRisk`，consistency edges 必须包含 `TextBoxSegmentMaskLinkage`，报告必须包含 `textBoxSegmentLinkBreakdown` 和 `textBoxSegmentLinkageReviewBlocks`。consistency edges 必须覆盖 TextBox/Bubble、Segment/TextBox、Segment/Bubble、final OCR bbox/TextBox、same-bubble sibling non-overlap、seam/split risk、render sprite containment、model-floor separation 和 TextBox -> SegmentMask linkage。`componentReadinessBreakdown`、`artifactConsistencyBreakdown`、`textBoxSegmentLinkBreakdown`、`primaryBlockingArtifactBreakdown`、`nextActionBreakdown` 必须非空或有明确 warning / blocked gate。`koharuArtifactConvergenceReport.referenceReports` 必须包含 `koharuNativeArtifactBundleLiteReport`，并且 `workItemLedger` / `gateLedger` 必须包含 `WI-koharu-native-artifact-bundle-lite` / `G-koharu-native-artifact-bundle-lite-executed`；v1.57 起还必须包含 `WI-koharu-native-artifact-bundle-lite-textbox-segment-linkage` / `G-native-artifact-bundle-lite-textbox-segment-linkage`。`1_ocr_probe_text.txt` 必须包含 report summary、`nativeArtifactBundleLiteTextBoxSegmentLink`、逐块 `nativeArtifactBundleLiteBlockLedger` 的 `textBoxSegmentLink=`、`nativeArtifactBundleLiteConsistencyEdge` 和 `nativeArtifactBundleLiteWorkItem`。该报告不新增 OCR / LLM / PNG，不创建或修改 active `test/koharu_artifacts/`，不把 bundle-lite 冒充真实 Koharu artifacts，不改变主 OCR、翻译输入、覆盖图、renderer、`blockPassed`、失败分类、`safeLayoutRect`、`glyphMaskFillRects`、`textRegionCropReport.adoptedCount` 或 `configuration.currentBlockSource`。
- v1.46 起云端 `ci-fast` 也必须产出 `koharuNativePromotionGateLiteReport`；`enabled = true`、`source = AITRANSProbe`、`referencePipeline = Koharu`、`referenceConcept = NativePromotionGateLite.ProbeDrivenArtifactReadiness`、`referenceWorkItemID = WI-koharu-native-promotion-gate-lite`、`evaluatedBlockCount == totalBlocksDetected`、`blockLedgerCount == totalBlocksDetected`、`stageGateCount >= 8`、`candidateExportPreviewCount >= 1` 或明确 blocked / warning reason、`workItemCount >= 1`、`gateCount >= 8`、`promotionGateLite = true`、`nativePromotionPreviewOnly = true`、`groundTruthUsedForDecision = false`、`groundTruthUsedForEvaluationOnly = true`、`wouldChangeMainFlow = false`、`diagnosticOnly = true`、`externalArtifactsRequiredForThisReport = false`、`proxyNotRealKoharuTextBoxes = true`、`proxyNotRealKoharuBubbleMask = true`、`proxyNotRealKoharuSegmentMask = true`、`proxyNotRealKoharuOCR = true`、`proxyNotRealKoharuRenderer = true`。每个 final block 必须有 promotion ledger，至少包含 TextBoxes / BubbleMask / SegmentMask / OcrText / Translations / Render promotion status、primary blocking artifact、probe bottleneck、promotion eligibility、nextAction 和 `mustNotPromoteReasons`；v1.57 起每块 ledger 还必须包含 `textBoxSegmentLinkVerdict` 和 `textBoxSegmentLinkagePromotionStatus`，报告必须包含 `textBoxSegmentLinkBreakdown` 和 `textBoxSegmentLinkageBlockedBlocks`，weak / fallback / rejected / wrong-bubble linkage 必须进入 `mustNotPromoteReasons`。`stageGates[]` 必须覆盖 TextBoxes、BubbleMask、SegmentMask、OcrText、Translations、RenderedSprites、FinalRender、ExternalArtifacts；`candidateExportPreviews[]` 必须保持 `canBeExportedNow = false`、`wouldCreateActiveArtifact = false`。`stageReadinessBreakdown`、`promotionEligibilityBreakdown`、`primaryBlockingArtifactBreakdown`、`probeBottleneckBreakdown`、`textBoxSegmentLinkBreakdown`、`nextActionBreakdown` 必须非空或有明确 warning / blocked gate。`koharuArtifactConvergenceReport.referenceReports` 必须包含 `koharuNativePromotionGateLiteReport`，并且 `workItemLedger` / `gateLedger` 必须包含 `WI-koharu-native-promotion-gate-lite` / `G-koharu-native-promotion-gate-lite-executed`；v1.57 起还必须包含 `WI-koharu-native-promotion-gate-lite-textbox-segment-linkage` / `G-native-promotion-gate-lite-textbox-segment-linkage`。`1_ocr_probe_text.txt` 必须包含 report summary、`nativePromotionTextBoxSegmentLink`、`nativePromotionStageGate`、逐块 `nativePromotionBlockLedger` 的 `textBoxSegmentLink=`、`nativeCandidateExportPreview` 和 `nativePromotionWorkItem`。该报告不新增 OCR / LLM / PNG，不更换模型，不创建或修改 active `test/koharu_artifacts/`，不把 native-lite proxy 冒充真实 Koharu promotion / detector / artifact，不改变主 OCR、翻译输入、覆盖图、renderer、`blockPassed`、失败分类、`safeLayoutRect`、`glyphMaskFillRects`、`textRegionCropReport.adoptedCount` 或 `configuration.currentBlockSource`；ground truth 只进 evaluation signals。
- v1.47 起云端 `ci-fast` 也必须产出 `koharuNativeArtifactContractDryRunReport`；`enabled = true`、`source = AITRANSProbe`、`referencePipeline = Koharu`、`referenceConcept = NativeArtifactContractDryRun.FourFileReadiness`、`referenceWorkItemID = WI-koharu-native-artifact-contract-dry-run`、`sourceImage = test/1.png`、`coordinateSpace = originalImageTopLeftPixels`、`activeInputDirectory = test/koharu_artifacts`、`examplesDirectory = md/koharu研究/artifact_contract/examples`、`evaluatedBlockCount == totalBlocksDetected`、`requiredFileCount >= 4`、`contractGateCount >= 6`、`groundTruthUsedForDecision = false`、`groundTruthUsedForEvaluationOnly = true`、`wouldChangeMainFlow = false`、`diagnosticOnly = true`、`dryRunOnly = true`、`activeExportAllowed = false`、`externalArtifactsRequiredForThisReport = false`。`requiredFiles[]` 必须覆盖 `1.manifest.json`、`1.textboxes.json`、`1.bubbles.json`、`1.segment_mask.json`，且 manifest required fields 必须包含 `sourceImageSHA256=<expected runtime test/1.png sha256>`；v1.67 起每个 required file 还必须写出 `identityStatus`，有 active 文件时写出 `fileSizeBytes` 和 `sha256`，顶层必须写 `appSideArtifactIdentityVerdict`、`appSideArtifactIdentityFilesPresent`、`appSideArtifactIdentityHashesPresent`；v1.80 起 App-side identity ready 还必须要求 `externalArtifactReadinessReport.artifactIdentityReceipt.sourceImageSHA256Matches = true`。真实 artifact ready 后 `contractDryRunVerdict = activeArtifactsReadyForShadowOCR` 必须要求 App 侧 identity ready。`validatorCommands[]` 必须包含 `scripts/validate-koharu-artifacts.py --root test/koharu_artifacts --print-required-files` 和 `--allow-missing`；`forbiddenActiveSources[]` 必须包含 contract examples、Vision OCR blocks、pre-crop plan、line plan、BubbleMask proxy、SegmentMask proxy、ground truth、handwritten ideal boxes。`previews[]` 必须保持 `activeExportAllowed = false`、`wouldCreateActiveArtifact = false`，并写出 required / missing fields 与 forbidden source reasons。`koharuArtifactConvergenceReport.referenceReports` 必须包含 `koharuNativeArtifactContractDryRunReport`，并且 `workItemLedger` / `gateLedger` 必须包含 `WI-koharu-native-artifact-contract-dry-run` / `G-koharu-native-artifact-contract-dry-run-executed`；缺 active 四件套时该 work item 应为 `blockedByMissingRealArtifact`，禁止把 proxy preview 当成真实 artifact readiness。`1_ocr_probe_text.txt` 必须包含 `koharuNativeArtifactContractDryRunReport` summary、App-side identity summary、`nativeArtifactContractDryRunRequiredFile` 的 size / SHA、`nativeArtifactContractDryRunPreview`、validator commands 和 forbidden active sources。该报告只做四件套 contract dry-run，不创建、复制、修改 active `test/koharu_artifacts/`，不新增 OCR / LLM / PNG，不改变主 OCR、翻译输入、覆盖图、renderer、`blockPassed`、失败分类、`safeLayoutRect`、`glyphMaskFillRects`、`textRegionCropReport.adoptedCount` 或 `configuration.currentBlockSource`。
- v1.68 起云端 `ci-fast` 也必须产出 `koharuArtifactIdentityReconciliationReport`；`enabled = true`、`source = AITRANSProbe`、`referencePipeline = Koharu`、`referenceConcept = ArtifactIdentityReconciliation.CIManifestAppReceipt`、`referenceWorkItemID = WI-koharu-artifact-identity-reconciliation`、`evaluatedBlockCount == totalBlocksDetected`、`fileRowCount >= 5`、`gateCount >= 3`、`groundTruthUsedForDecision = false`、`wouldChangeMainFlow = false`、`diagnosticOnly = true`、`dryRunOnly = true`、`activeExportAllowed = false`、`externalArtifactsRequiredForThisReport = false`。`fileRows[]` 必须覆盖 `SourceImage`、`manifest`、`TextBoxes`、`BubbleMask`、`SegmentMask`，每行必须包含 App size / SHA256、`ciManifestFieldPathForSize`、`ciManifestFieldPathForSHA256` 和 `comparisonStatus`；v1.80 起顶层还必须包含 `sourceImageSHA256Declared`、`sourceImageSHA256Expected`、`sourceImageSHA256Matches`，真实 artifact ready 后 `readyForCIManifestComparison = true` 必须要求每行 `comparisonStatus = appReceiptReady` 且 `sourceImageSHA256Matches = true`。`koharuArtifactConvergenceReport.referenceReports` 必须包含该报告，`workItemLedger` / `gateLedger` 必须包含 `WI-koharu-artifact-identity-reconciliation` / `G-koharu-artifact-identity-reconciliation-ready`；`1_ocr_probe_text.txt` 必须包含 `koharuArtifactIdentityReconciliationReport`、逐行 `artifactIdentityReconciliationFile`、source image SHA declared / expected / matches 和 `convergenceArtifactIdentityReconciliation`。Actions 注入真实 artifact 后还必须在 `ci-artifact-manifest.json` 写出 `koharuArtifactIdentityReconciliationMatch.matchVerdict = matched`，否则不得把 artifact handoff 当作通过。该报告不读取 CI manifest、不创建或修改 active artifact、不新增 OCR / LLM / PNG、不改变主 OCR、翻译输入、覆盖图或 renderer。
- 若 post-fusion cleanup 新增拒绝块，`fusionComparison.postFusionCleanup.rejectedBlocks[]` 必须写出 ground-truth-free 的 `reason`、`relatedKeptBlockIndex`、`qualityScore`、`protectedTextMatched` 和 `evidence`；保护文本与 decorative 标题不能被清理掉。
- 外部 Koharu artifact validator 对 `md/koharu研究/artifact_contract/examples/valid` 应返回 `validationPassed = true`、`verdict = contractExampleOnly`、`externalTextBoxesShadowOCRAllowed = false`，且 `artifactIdentitySummary.sourceImageSHA256Declared` 等于 `artifactIdentitySummary.sourceImage.sha256`、`sourceImageSHA256Matches = true`；对 `examples/valid_orientation_partial_unsupported` 还必须输出 `orientationMetadataSummary`，其中 `orientationLinePolygonWarpSupportedTextBoxIDs` 包含合法竖排 + line polygon fixture，`currentShadowOCRSupport.linePolygonWarp = true`，unsupported 只保留 `arbitraryRotationUnsupported`，不得继续输出 `linePolygonWarpUnsupported`。对 invalid fixtures 应在 `--expect-fail` 下成功，至少覆盖 coordinate mismatch、invalid bbox、missing textboxes、schema mismatch、manifest path escape、forbidden `generatedBy` source、TextBox 方向元数据非法、line polygon 脱离所属 TextBox bbox、manifest 缺 `sourceImage`、manifest 缺 / 错 `sourceImageSHA256` 和 manifest 缺 `contractExampleOnly`。v1.79 起 active manifest 缺 `sourceImageSHA256` 必须输出 `sourceImageSHA256Missing`，SHA 格式非法输出 `sourceImageSHA256Invalid`，与当前仓库 `test/1.png` 不一致输出 `sourceImageSHA256Mismatch`，并阻止 `readyForShadowOCR`；v1.80 起 Swift readiness、App identity receipt 和 identity reconciliation 也必须输出同等 missing / invalid / mismatch 阻塞，不能只由 Python validator 拦截。v1.81 起 `--emit-handoff-packet` 必须输出 Release upload / `workflow_dispatch` 输入，`--package-release-archive` 生成的 zip 必须只有一个目录且包含四个标准 JSON，并输出 archive SHA256；默认不得把 `contractExampleOnly` examples 标记为 handoff ready，云端 static checks 也必须覆盖 fixture 默认拒绝打包、允许 fixture 打包后的 zip 布局和带空格 dispatch 参数 shell quote。v1.82 起 `--inspect-release-archive` 必须按 CI 同口径拒绝 0 个或多个四件套 candidate directory 的 archive，成功时输出 archive size/SHA、members、candidate directory 和 validation verdict；handoff packet 必须输出带 `--repo` 的 `ghReleaseUploadCommand`、`ghWorkflowDispatchCommand` 和 `ghRunListCommand`。v1.83 起 `--package-release-archive` 的 handoff packet 还必须包含 `releaseArchive.inspection`、`releaseArchiveInspectionPassed`、`releaseArchiveInspectionVerdict`、`inspectReleaseArchiveCommand` 和 `expectedCIManifestEcho`，static checks 必须断言 fixture package 的 inspection proof 存在且 candidate directory count 为 1；v1.84 起 handoff packet 还必须包含 `ghRunWatchCommand`、`ghRunDownloadCommand`、`ciResultReview`、`expectedCIManifestAssertions`、`expectedAppRuntimeAssertions`、`expectedReconciliationAssertions`、`expectedExternalShadowOCRAssertions`、`expectedConvergenceAssertions`、`expectedCloudIdentityRows`、`expectedProbeTextNeedles` 和 `staleRunRejectionAssertions`，static checks 只断言这些结构化 review 字段的 shape 和关键路径存在，不增加真实 GitHub 下载或 App 探针负载；云端注入真实 archive 时仍以 Release 下载 SHA、唯一目录解包、active validator identity / orientation 摘要、App runtime readiness、identity reconciliation、external shadow OCR coverage 和 orientation gates 为验收证据。v1.69 起 active manifest 缺 `sourceImage` 必须输出 `sourceImageMissing`，缺或非布尔 `contractExampleOnly` 必须输出 source policy 错误并阻止 `readyForShadowOCR`。TextBox 可选 `sourceDirection`、`rotationDegrees` / `rotationDeg`、`linePolygons` 一旦提供，validator 和 Swift readiness 必须校验方向枚举、旋转范围、源图点位范围和 bbox 所属关系；`--print-required-files` 应输出 active 目录四件套和 forbidden active sources；对缺失的 `test/koharu_artifacts` 应在 `--allow-missing` 下返回 `manifestMissing`、`readyForShadowOCR = false`、`externalTextBoxesShadowOCRAllowed = false`、`nextAction = stopUntilArtifactsProvided` 和缺失文件 blockers，不应额外混入 schema / coordinate 缺失噪音。
- v3.2 mask payload contract 由 `scripts/test-v32-koharu-mask-payload-contract.py` 统一验收 Python validator、Swift evaluator、Store / report / Xcode target / CI 接线。v1 fixture 必须继续 `validationPassed = true` 但 `maskPayloadGateReady = false`；v2 BubbleMask / SegmentMask 必须声明 `width`、`height`、`encoding = rowMajorRLE` 和 `runs`，解码总长精确等于源图像素且不得越界。Bubble label 只能为 0 或唯一正 `maskValue`，并精确重算 `pixelCount` 与 tight bbox；Segment label 只能为 0/1，并重算 `glyphPixelCount` 与四连通 component。App readiness 必须输出两个 payload verdict、gate ready 和逐块 majority / coverage / TextBox containment；`WI/G-external-mask-pixel-payload` 只有 active 非 fixture v2 payload 与全部块空间证据可信时才能 `closedReportOnly / passed`。该 gate 保持 shadow-only，不改变 OCR、翻译、renderer、`blockPassed` 或 `currentBlockSource`。
- v3.3 mask topology contract 由 `scripts/test-v33-koharu-mask-topology-contract.py` 和纯 Swift `scripts/test-v33-koharu-mask-topology-evaluator.swift` 验收。Python valid fixture 必须做到 TextBox 的 expected Bubble label 唯一、每个 glyph component 只归属一个 TextBox、无 foreign / orphan 像素且 partition 守恒；cross-assignment invalid fixture 在 v3.2 payload 仍有效时必须单独令 `maskTopologyGateReady = false`。App 必须复用 `stableOneToOneExternalTextBoxShadowMatching`，不得为 topology 再独立选 best TextBox；缺 block、duplicate TextBox/block、invalid expected Bubble、empty glyph、overlap、foreign / no-bubble / orphan 像素、cross-Bubble component 或分区不守恒都阻止 `WI/G-external-mask-topology-linkage`。该 gate 只是 shadow 证据，不改 OCR、翻译、renderer、`blockPassed` 或 `currentBlockSource`。
- v1.97 要求 handoff packet 使用单一 `targetIdentity`；repo / workflow ref / expected commit SHA 由显式参数或 GitHub / git 环境解析，upload、dispatch、run list、manifest assertions、review 和 stale-run rules 必须全部使用同一组值，workflow 入口必须在验证前拒绝 `expected_commit_sha != GITHUB_SHA`。CI fixture 必须显式传测试 identity，并运行 `scripts/test-v197-koharu-handoff-target-contract.py`。
- `1_ocr_probe_text.txt` 每块包含 `textBoxPlanFailure` 和 `promotionChecks`；目标块 `[1, 6, 10]` 还包含 `lineTextBoxPlans`、`lineCropExperiment`、`linePromotionChecks` 和 `lineResearchDecision`；每块还包含 `externalArtifacts` 与 `externalTextBoxShadowOCR` 摘要。
- `cleanTextDiagnostic.passRate = 0.4545`
- `passedBlocks = 1`
- `failedBlocks = 12`
- `translationFailureBreakdown = { modelOutputFailure: 2, ocrInputSuspect: 7, translationLanguageQualityFailure: 3 }`
- `likelyRuleFalseFailureBlocks = []`

### 2.4 Full
全量验证。

触发条件：

- 修改 llama.cpp 封装、模型下载/导入、Xcode framework、bundle resource、持久化迁移、Pro 权限或发布相关配置。
- 版本收尾或准备提交时需要高置信度。

默认动作：由 GitHub Actions 负责 build/test/report/artifact 重验证。人工明确要求本机全量时命令：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project AITRANS.xcodeproj \
  -scheme AITRANS \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath .derivedData \
  CODE_SIGNING_ALLOWED=NO build
```

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project AITRANS.xcodeproj \
  -scheme AITRANS \
  -destination 'generic/platform=iOS' \
  -derivedDataPath .derivedDataDevice \
  CODE_SIGNING_ALLOWED=NO build
```

然后运行 Stage Regression 的完整漫画探针、导出和 JSON 检查。

当前基线：

- generic iOS Simulator build 近期通过。
- generic iOS device build 在 README 当前验证中记录通过。
- Debug iOS Simulator app bundle 曾确认内嵌 `llama.framework`。

## 3. 云端结果包要求
Agent B 的云端结果必须可下载、可追溯、未加密，供 Agent C 验收。最低内容：

- `.xcresult`：当 `xcodeBuildRequired = true` 时必须包含 Xcode 结果包，例如 `TestResults/AITRANS-${version}-${short_sha}.xcresult`；文档 / 元数据快路径允许缺省，但必须在 manifest 写明 skip reason。
- `junit.xml`：CI 可读摘要。当前没有 XCTest 时，至少生成 build smoke 的 JUnit 摘要。
- `xcodebuild.log`：完整构建日志；build-skip 快路径时该文件保留 skip 说明。
- `ci-artifact-manifest.json`：结果包索引，包含 `version`、`branch`、`commitSha`、`runId`、`runAttempt`、`workflowName`、`createdAt`、`xcodeVersion`、`scheme`、`destination`、`resultBundlePath`、`junitPath`、`xcodebuildLogPath`、`failureSummaryPath`、`probeReportPath`。v1.14 起还包含 `koharuActiveArtifactValidationPath`、`koharuArtifactValidation`、`externalArtifactReadinessSummary` 和 `externalTextBoxShadowOCRSummary`，用于区分缺 artifact 阻塞路径和 ready/executed=true 路径；v1.65 起还包含 `koharuArtifactValidationOrientationSummary`，`externalTextBoxShadowOCRSummary` 透传 orientation 与 coverage 相关字段；v1.66 起还必须包含 `koharuArtifactValidationIdentitySummary`、App 侧 identity receipt / reconciliation summary 和 `koharuArtifactIdentityReconciliationMatch`；v1.69 起 ready artifact 的 shadow OCR coverage 还必须核对 `ocrExecutedCount > 0`、`ocrSucceededCount > 0`，并在 convergence report 的 report availability gate 里保留 `missingReportCount`、`missingReports` 和 `requiredReportSpan`；v1.72 起还包含 `koharuNativeArtifactContractDryRunSummary` 和 `koharuArtifactConvergenceGateSummary`，直接汇总 contract dry-run、coverage/orientation work item、gate status、blocks 和 `G-ci-fast-report-availability` decision signals；v1.74 起还包含 `koharuNativeLiteReportSummary` 与 `koharuNativeLiteConvergenceGateSummary`，直接汇总 v1.39-v1.46 detector-lite、shadow OCR、refinement、closed-loop、instance-lite、SegmentMask refinement-lite、bundle-lite 和 promotion gate-lite 的 verdict、counts、work item / gate status、blocks 和 nextAction；v1.77 起还包含 `artifactName`、`eventName`、`repository`、`ref`、`refName`、`runUrl`、`changedFilesCount`、`changedFilesSHA256` 和 `changedFiles`，用于 Agent C 直接核对结果包来源、GitHub run URL 和本次变更范围；v1.78 起还包含 `scopeDiffMethod`、`scopeDiffBaseSha` 和 `scopeDiffFallbackUsed`，用于判断 changed-files 是 checkout diff、targeted fetch diff 还是全仓 fallback；v1.79 起 `koharuArtifactValidationIdentitySummary` 还必须透传 manifest 声明的 `sourceImageSHA256Declared`、实际 `sourceImageSHA256Expected` 和 `sourceImageSHA256Matches`；v1.80 起 App receipt summary 和 `koharuArtifactIdentityReconciliationSummary` 也必须透传 source image SHA declared / expected / matches。
- v1.70 起 artifact requested 的云端结果还必须证明 `probe_mode != skip`，smoke 已硬核对 coverage work item / gate ID 与 status、orientation work item / gate ID 与 status、coverage gate passed、orientation blockers 存在时不得 passed，且 `1_ocr_probe_text.txt` 包含 coverage / orientation / App-side identity 摘要。
- `xcodeBuildRequired` / `xcodeBuildSkippedReason`：仅文档 / 元数据快路径允许 `xcodeBuildRequired = false`；Agent C 必须把它视作“未提供 Swift/Xcode 编译证据”，不能用于验收代码改动。
- `ci-failure-summary.md`：无论成功或失败都生成；失败时写清失败阶段、关键日志位置、建议 Agent B 先看哪些文件。
- `model-download.log` / `model-verify.log`：仅 `ci-fast` / `full` 探针模式要求，记录 Release 下载、cache 命中和 SHA256 校验；`probe_mode=skip` 必须在 manifest 写 `modelSetupSkippedReason`。
- `simulator-build.log` / `manga-probe.log`：仅 `ci-fast` / `full` 探针模式要求，记录 Debug simulator app 复用、安装、模型导入、探针启动、报告等待和导出；`probe_mode=skip` 必须保留 `probe-not-run.txt` 或 manifest skip reason。
- 若运行漫画探针：上传 `output/probe_report.json`、`output/clean_text_diagnostic.json`、`output/1_ocr_probe_text.txt` 和关键 PNG。

artifact 命名建议：

```text
aitrans-ci-${version}-${branch_slug}-${short_sha}-run${run_id}-attempt${run_attempt}
```

Agent C 取用规则：

- 只看当前 `codeb/...` HEAD 对应的 `commitSha`。
- 必须核对 manifest 的 `branch`、`commitSha`、`runId`、`runAttempt`。
- 涉及 external artifact 时，必须核对 manifest 内 `koharuArtifactValidation.verdict`、payload / topology 两组 gate ready 与 summary、identity / orientation summary、`externalArtifactReadinessSummary` 的 readiness / payload / topology / block alignment、App 侧 identity receipt / reconciliation、`koharuArtifactIdentityReconciliationMatch.matchVerdict`、`externalTextBoxShadowOCRSummary`，以及 convergence 中 `WI/G-external-mask-pixel-payload` 和 `WI/G-external-mask-topology-linkage`，并确认这些值来自当前 `commitSha` 的结果包。
- B 再次 push 后，旧 run 结果废弃。
- Actions 重跑时，记录实际验收的 `runAttempt`。
- C 验收通过后默认通过 PR merge 收口，并删除远端 `codeb/...` 候选分支；无权限删除时必须说明。

## 4. 静态检查
常用命令：

```sh
git diff --check
plutil -lint AITRANS/Resources/Info.plist AITRANS.xcodeproj/project.pbxproj
python3 -m json.tool test/1.ground_truth.json
python3 -m json.tool output/probe_report.json
python3 -m json.tool output/clean_text_diagnostic.json
```

版本指标追加：

```sh
python3 scripts/append-version-metrics.py --version vN --notes "简短说明"
```

## 5. 规则
- 每次实现前先读本文件。
- 默认从本地轻量检查开始，重负载验证交给 GitHub Actions。
- 不得伪造测试结果。
- 未跑测试必须说明原因。
- 非 App 构建相关修改可只跑 `git diff --check` 和必要 JSON/YAML smoke，但要说明未跑 build 和探针的原因。
- 未经人工明确要求，不因为 Swift 代码变化就在本机默认跑 Xcode build 或完整漫画探针。
- 漫画探针或翻译链路修改后，最终回复必须汇总关键数字。
- 如果 clean text 仍失败，优先讨论模型质量，不要继续盲目调 OCR 或放宽规则。
