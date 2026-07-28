# 项目版本更新记录
本文记录 AITRANS 的正式版本、重要维护事项、关键决策和遗留问题。README 不再写更新记录；细节证据优先看本日志、`metrics/version_history.csv`、最新 `output/` 和 git 提交。

## 维护规则
- 每完成一个正式版本或重要任务后追加记录。
- 记录必须包含：版本或任务名、日期、核心变更、关键文件、验证结果、遗留事项。
- 文档整理、目录迁移、回滚、打捞等不伪装成新版本，写入“历史维护记录”。
- 若核心逻辑、测试规范或项目行为变化，必须同步更新本日志、`md/flow/flow.md`、`md/flow/flowchart.md` 或 `md/test/test.md`。
- 涉及漫画探针或翻译链路的可量化版本时，`metrics/version_history.csv` 必须 append-only 更新；README 不再追加近期记录。

## v3.7：图片输入语言 Pro 拒绝无副作用
日期：2026-07-28

状态：Agent X 已完成核心实现、本地轻量回归、exact-SHA 云端 full 和 PR 收口；工程正式版本为 `MARKETING_VERSION=3.7`。PR #71 已合入 `smalldata_test`，merge SHA `b8cb6a298e05756a7d4c574765f1ec80e9444282`；远端 `codeb/v3.7-image-source-pro-feedback` 已删除，未触碰 `main`。

核心变更：

- `selectImageSourceLanguage` 把 `isProUnlocked` 提升到任何读取/写入图片语言状态之前；免费模式拒绝时不再先改全局 `sourceLanguage`，因此不会从图片页静默污染文本页语言。
- Store 写入明确的“图片输入语言设置需要 Pro”反馈，免费模式的非当前菜单项显示 `lock.fill`，图片输入语言菜单用 Alert 展示拒绝，VoiceOver hint 同步说明门槛；授权通过后的完成态重跑、失败/取消 pending 与 v3.6 撤销语义不变。
- v3.4 的目标语言政策保持不变：目标仍由 `selectTargetLanguage` / `canUseLanguage` 判定，不额外阻断英语、中文等免费目标。
- 新增 v3.7 contract 并接入图片/UI fail-fast 路由。不修改 Vision OCR、布局、翻译、renderer、漫画探针或 Koharu 报告。

验证与遗留：

- v3.7 新契约 4/4，v1.87 与 v2.2-v3.6 全部图片/UI 契约合计 103 项通过；两个改动 Swift 文件以完整 Xcode toolchain parse 通过，workflow YAML、CI 分层 9/9、版本身份 5/5、工程版本解析 `v3.7` 和 `git diff --check` 均通过。
- 候选 exact SHA `a29a11fa3e515d8a719ccc3a6691eb6f89cd82fe` 的云端 full run `30329585960` attempt 1 成功；artifact `aitrans-ci-v3.7-codeb-v3.7-image-source-pro-feedback--a29a11fa3e51-run30329585960-attempt1` 与 version / branch / SHA / run / profile 完全一致，图片/UI、Speech/home/paste、extended Koharu validator matrix 和 Xcode build 均通过，JUnit 10/10，`.xcresult` succeeded、0 error / 0 warning，commit status `AITRANS CI/full-validation=success`。
- PR #71 exact HEAD fast run `30329833172` 成功后合并；merge follow-up run `30329885452` 成功，artifact 与 merge HEAD `b8cb6a298e05756a7d4c574765f1ec80e9444282` 一致，`validationProfile=fast`、`validationReason=merge_reuses_successful_candidate_full_validation`，精确复用候选 SHA `a29a11fa3e515d8a719ccc3a6691eb6f89cd82fe` 的成功 full 收据，JUnit 10/10。
- 未跑本机 build / 探针，按规则交给云端验证。本版是授权拒绝与跨页状态一致性修复，不刷新 `output/` 或 `metrics/version_history.csv`，不声称 OCR、翻译或识别质量提升。

## v3.6：图片待重试语言可撤销
日期：2026-07-28

状态：Agent X 已完成核心实现、本地轻量回归、exact-SHA 云端 full 和 PR 收口；工程正式版本为 `MARKETING_VERSION=3.6`。PR #70 已合入 `smalldata_test`，merge SHA `80f80502997833914a528daa284a4bd4daeab43c`；远端 `codeb/v3.6-image-retry-language-reset` 已删除，未触碰 `main`。

核心变更：

- failed/cancelled 图片先选择新的输入或目标语言、再选回 actual-content 语言时，对应 pending Retry 字段归一化为 `nil`；源/目标都没有实际差异后，“重试语言已更新”状态自动消失。
- `imageTranslationDisplayed*Language` 不再以 data/blocks 已产出为前提；Store-owned source 已发布但后续读图失败时，标题、菜单和实际 Retry 仍统一使用 task-scoped content 凭据。选择器在修改全局语言前快照该比较基准，避免目标语言全局更新掩盖差异。
- 完成态即时重跑、运行态冻结、目标语言 Pro 授权、Retry/clear/cancel 与 v3.5 的凭据边界保持不变。
- VoiceOver 提示同步说明可撤销行为；新增 v3.6 contract 并接入图片/UI fail-fast 路由。不修改 Vision OCR、布局、翻译、renderer、漫画探针或 Koharu 报告。

验证与遗留：

- v3.6 新契约 5/5，v1.87 与 v2.2-v3.5 全部图片/UI 契约合计 99 项通过；两个改动 Swift 文件以完整 Xcode toolchain parse 通过，workflow YAML、三份基线 JSON、CI 分层 9/9、版本身份 5/5、工程版本解析 `v3.6` 和 `git diff --check` 均通过。
- 候选 exact SHA `5fc9d6e3c3f232df0b1c4f68b50a741145ad3bd6` 的云端 full run `30328786522` attempt 1 成功；artifact `aitrans-ci-v3.6-codeb-v3.6-image-retry-language-reset--5fc9d6e3c3f2-run30328786522-attempt1` 与 version / branch / SHA / run / profile 完全一致，图片/UI、Speech/home/paste、extended Koharu validator matrix 和 Xcode build 均通过，JUnit 10/10，`.xcresult` succeeded、0 error / 0 warning，commit status `AITRANS CI/full-validation=success`。
- PR #70 exact HEAD fast run `30329087730` 成功后合并；merge follow-up run `30329144284` 成功，artifact 与 merge HEAD `80f80502997833914a528daa284a4bd4daeab43c` 一致，`validationProfile=fast`、`validationReason=merge_reuses_successful_candidate_full_validation`，精确复用候选 SHA `5fc9d6e3c3f232df0b1c4f68b50a741145ad3bd6` 的成功 full 收据，JUnit 10/10。
- 未跑本机 build / 探针，按规则交给云端验证。本版是图片操作与状态反馈一致性修复，不刷新 `output/` 或 `metrics/version_history.csv`，不声称 OCR、翻译或识别质量提升。

## v3.5：图片内容与 Retry 语言分账
日期：2026-07-28

状态：Agent X 已完成核心实现、本地轻量回归、exact-SHA 云端 full 和 PR 收口；工程正式版本为 `MARKETING_VERSION=3.5`。PR #69 已合入 `smalldata_test`，merge SHA `685006272a5a777a19eb21bb036cd9799a3f1365`；远端 `codeb/v3.5-image-retry-credentials` 已删除，未触碰 `main`。

核心变更：

- 新增独立 pending Retry 输入/目标语言。失败或取消后修改菜单不再覆盖 actual-content 凭据，因此已保留的 OCR 块或部分旧译文不会被新选择误标。
- 图片结果区副标题继续显示实际内容语言；输入/目标菜单显示下一次 Retry 选择，并以“重试语言已更新”状态明确区分。完成态仍即时重新识别/翻译，运行态仍冻结。
- Retry 按 pending -> actual-content -> global 顺序选择语言，新任务开始后清空 pending；clear 清空两组，cancel 保留实际内容。v2.2 起的 source ownership、task ID、render/share 失效和晚到回调拒收保持不变。
- 新增 v3.5 contract，并收紧 v1.87/v2.7/v3.0/v3.4 历史契约；不修改 Vision OCR、布局算法、翻译实现、renderer、漫画探针或 Koharu 报告。

验证与遗留：

- v3.5 新契约 5/5，v1.87 与 v2.2-v3.4 全部图片/UI 契约合计 94 项通过；两个改动 Swift 文件以完整 Xcode 工具链 parse 通过，workflow YAML、pbxproj、CI 分层 9/9、版本身份 5/5、工程版本解析 `v3.5` 和 `git diff --check` 均通过。
- 候选 exact SHA `f7603f60f59444ac13938b95c296dbfe859ee033` 的云端 full run `30327978367` attempt 1 成功；artifact `aitrans-ci-v3.5-codeb-v3.5-image-retry-credentials--f7603f60f594-run30327978367-attempt1` 与 version / branch / SHA / run / profile 完全一致，图片/UI、Speech/home/paste、extended Koharu validator matrix 和 Xcode build 均通过，JUnit 10/10，`.xcresult` 可用，commit status `AITRANS CI/full-validation=success`。
- PR #69 exact HEAD fast run `30328253451` 成功后合并；merge follow-up run `30328283787` 成功，artifact 与 merge HEAD `685006272a5a777a19eb21bb036cd9799a3f1365` 一致，`validationProfile=fast`、`validationReason=merge_reuses_successful_candidate_full_validation`，精确复用候选 SHA `f7603f60f59444ac13938b95c296dbfe859ee033` 的成功 full 收据，JUnit 10/10。
- 未跑本机 build / 探针，按规则交给云端验证。本版是图片状态与显示一致性修复，不刷新 `output/` 或 `metrics/version_history.csv`，不声称 OCR、翻译或识别质量提升。

## v3.4：图片 Retry 目标语言凭据
日期：2026-07-28

状态：Agent X 已完成核心实现、本地轻量验证、exact-SHA 云端 full 和 PR 收口；工程正式版本为 `MARKETING_VERSION=3.4`。PR #68 已合入 `smalldata_test`，merge SHA `8f71922b39a1bd2b6d3947bc79fbecd8d1f7385d`；远端 `codeb/v3.4-image-retry-language` 已删除，未触碰 `main`。

核心变更：

- `selectImageTargetLanguage` 改为与输入语言一致的 Store-owned 状态机：完成态先确认 source 文件存在，再更新内容目标并即时重译；失败或取消保留态只在 `canRetryImageTranslation` 时更新下次 Retry 凭据；运行态拒绝改写。
- 移除图片目标语言路径多余的 `isProUnlocked` 硬门槛。Pro 可用性仍由 `selectTargetLanguage` / `canUseLanguage` 统一判定，英语、中文等免费目标不会再被图片完成态额外阻断。
- 新增 v3.4 contract，锁定 source ownership、Retry/clear/cancel 凭据边界、辅助说明与 CI 路由；不修改 Vision OCR、布局、翻译实现、renderer、漫画探针或 Koharu 报告。

验证与遗留：

- v3.4 新契约 5/5、v1.87 与 v2.2-v3.1 既有图片/UI 契约合计 89 项全部通过；两个改动 Swift 文件以完整 Xcode 工具链 parse 通过，workflow YAML、pbxproj、CI 分层 9/9、版本身份 5/5、工程版本解析 `v3.4` 和 `git diff --check` 均通过。
- 候选 exact SHA `8fa0b203fc5090f042b2c99499a7f8e26d6fc236` 的云端 full run `30327280611` attempt 1 成功；artifact `aitrans-ci-v3.4-codeb-v3.4-image-retry-language--8fa0b203fc50-run30327280611-attempt1` 与 version / branch / SHA / run / profile 完全一致，图片/UI、Speech/home/paste、extended Koharu validator matrix 和 Xcode build 均通过，JUnit 10/10，`.xcresult` 可用，commit status `AITRANS CI/full-validation=success`。
- PR #68 exact HEAD fast run `30327602710` 成功后合并；merge follow-up run `30327633420` 成功，artifact 与 merge HEAD `8f71922b39a1bd2b6d3947bc79fbecd8d1f7385d` 一致，`validationProfile=fast`、`validationReason=merge_reuses_successful_candidate_full_validation`，精确复用候选 SHA `8fa0b203fc5090f042b2c99499a7f8e26d6fc236` 的成功 full 收据，JUnit 10/10。
- 未跑本机 build / 探针，按规则交给云端验证。本版是图片操作一致性修复，不刷新 `output/` 或 `metrics/version_history.csv`，不声称 OCR、翻译或识别质量提升。

## v3.3：Koharu mask 拓扑与稳定 assignment
日期：2026-07-28

状态：Agent X 已完成候选实现、本地轻量验证、exact-SHA 云端 full 和 PR 收口；工程正式版本为 `MARKETING_VERSION=3.3`。PR #67 已合入 `smalldata_test`，merge SHA `42be9e1751d1f06d007e15197b5078235c661284`；远端 `codeb/v3.3-koharu-mask-topology` 已删除，未触碰 `main`。

核心变更：

- 新增纯 Swift `evaluateTopology`，在 v3.2 已验证 BubbleMask / SegmentMask 载荷上，统计 expected / foreign / no-bubble / orphan / multiply-assigned glyph pixels，并生成四连通 component 的 Bubble label、TextBox owner、cross-Bubble 和 partition ledger。重复 block / TextBox、重叠 claim、无效 expected Bubble、空 glyph、孤儿或分区不守恒均阻止。
- App `maskTopologyReport` 直接复用 external shadow OCR 的 `stableOneToOneExternalTextBoxShadowMatching`，逐块 block alignment 也改用同一 assignment，不再独立选最大 IoU TextBox / Bubble。新增 `WI-external-mask-topology-linkage` / `G-external-mask-topology-linkage`，探针 JSON / TXT 与 CI manifest 透传逐块、component 和 convergence 证据。
- Python validator 新增独立 `maskTopologyValidation` / `maskTopologyGateReady`，v3.2 payload gate 与 topology gate 分开报告；新 valid fixture 验证两个 TextBox / Bubble 和四个 component 的唯一归属，cross-assignment invalid fixture 验证 payload 仍有效时 topology 仍能拒绝 ambiguity、foreign pixels 和 duplicate components。云端注入真实 v2 archive 时强制 validator / App / convergence 三层 topology 闭环。
- 所有新证据保持 shadow-only，不改 OCR 请求、候选选择、翻译、renderer、`blockPassed`、`failureCategory` 或 `currentBlockSource`；不使用 ground truth 做决策。

验证与遗留：

- v3.3 topology contract 8/8（含 Swift evaluator `-warnings-as-errors`）、v3.2 payload contract 7/7 与 v3.2 evaluator 回归已通过；相关 Swift parse 与 `git diff --check` 通过。
- 候选 exact SHA `83c0bd3335168a8ca7f9ef5af26991f822dffdb8` 的云端 full run `30326605788` attempt 1 成功；artifact `aitrans-ci-v3.3-codeb-v3.3-koharu-mask-topology--83c0bd333516-run30326605788-attempt1` 与 version / branch / SHA / run / profile 完全一致，Koharu topology / payload 及相关静态契约、Speech/home/paste/UI contract 和 Xcode build 均通过，JUnit 10/10，`.xcresult` 可用，commit status `AITRANS CI/full-validation=success`。
- PR #67 exact HEAD fast run `30326937331` 成功后合并；merge follow-up run `30326964832` 成功，artifact 与 merge HEAD `42be9e1751d1f06d007e15197b5078235c661284` 一致，`validationProfile=fast`、`validationReason=merge_reuses_successful_candidate_full_validation`，精确复用候选 SHA `83c0bd3335168a8ca7f9ef5af26991f822dffdb8` 的成功 full 收据，JUnit 10/10。
- 未跑本机 build / 探针，按规则交给云端验证。仓库仍无真实 Koharu 四件套，因此本轮只验收算法、报告、CI 和编译接线，不刷新 `output/` 或 `metrics/version_history.csv`，不声称 OCR、翻译、覆盖或识别质量提升。

## v3.2：Koharu mask 像素载荷契约
日期：2026-07-28

状态：Agent X 已完成候选实现、并行审计、exact-SHA 云端 full 和 PR 收口；工程正式版本为 `MARKETING_VERSION=3.2`。PR #66 已合入 `smalldata_test`，merge SHA `d172d8d171b80ce753eaaf5bf61079ae32b54898`；远端 `codeb/v3.2-koharu-mask-payload` 已删除，未触碰 `main`。

核心变更：

- 外部 artifact contract 新增 v2：BubbleMask / SegmentMask 以内嵌 `rowMajorRLE` 提供真实像素载荷。Python validator 和 Swift evaluator 都限制解码不超过源图像素且总长必须精确匹配；Bubble 重算唯一正 `maskValue` 的 pixel count / tight bbox，Segment 重算 glyph pixels / 四连通 components。v1 摘要继续兼容，但 `maskPayloadGateReady = false`。
- App readiness 一次解码后按 block bbox 输出 Bubble majority mask value、Bubble / Segment pixel coverage 和匹配 TextBox 对块内 Segment pixels 的 containment。v2 payload 无效时返回 `maskPayloadValidationFailed`；所有统计保持 shadow-only。
- convergence 新增 `WI-external-mask-pixel-payload` / `G-external-mask-pixel-payload`。只有 active 非 fixture v2 payload 有效、每块 majority label 与 bbox-selected Bubble 一致、Bubble / Segment 非零且 TextBox containment 至少 `0.5` 时才关闭；ExternalArtifacts stage 消费该 gate。
- CI changed-files 路由、注入 archive hard gate、未加密 manifest 和探针 TXT 同步透传 validator / App / convergence 三层证据；新增 v2 valid / invalid fixtures 和组合契约。

验证与遗留：

- `scripts/test-v32-koharu-mask-payload-contract.py` 7/7 通过，内部真实执行 Swift evaluator `-warnings-as-errors` 编译；相关 Swift 文件 parse、workflow YAML、pbxproj、fixture JSON 和 `git diff --check` 通过。
- 候选 exact SHA `ac822b6186f39de3c73216047ed1126d5596cea4` 的云端 full run `30324330547` 成功；artifact `aitrans-ci-v3.2-codeb-v3.2-koharu-mask-payload--ac822b6186f3-run30324330547-attempt1` 与 version / branch / SHA / run / profile 完全一致，JUnit 10/10，`.xcresult` build succeeded 且 0 error / 0 warning，mask payload contract 7/7，commit status `AITRANS CI/full-validation=success`。
- PR #66 exact HEAD fast run `30324725260` 成功后合并；merge follow-up run `30324971434` 成功，artifact `aitrans-ci-v3.2-smalldata_test--d172d8d171b8-run30324971434-attempt1` 以 `validationProfile=fast`、`validationReason=merge_reuses_successful_candidate_full_validation` 精确复用候选 SHA `ac822b6186f39de3c73216047ed1126d5596cea4` 的成功 full 收据。
- 未跑本机 build / 探针，按规则交给云端验证。仓库没有真实 Koharu 四件套，当前 `output/` 仍是旧 `manifestMissing / stopUntilArtifactsProvided` 证据；本轮不刷新 `output/` 或 `metrics/version_history.csv`，不声称 OCR、翻译、覆盖或识别质量提升。

## v3.1：图片 OCR 待复查筛选
日期：2026-07-28

状态：Agent X 已完成核心候选实现、本地轻量回归、独立复审、核心与版本收口 exact-SHA 云端 full；工程正式版本为 `MARKETING_VERSION=3.1`。PR #65 已合入 `smalldata_test`，merge SHA `54c6ad5b548b093406c1a8387d4e35519290e627`；远端 `codeb/v3.1-image-ocr-review-filter` 已删除，未触碰 `main`。

核心变更：

- 图片识别结果新增“全部 / 待复查”分段筛选，并显示各自数量；待复查严格定义为 confidence 低于 `50%`，或方向证据为 nil / unknown，重叠原因只计一个 block，原始顺序不变。
- 筛选状态只属于 `ImageTranslationPanel` 的本地展示状态。预览、覆盖渲染、稳定导出、分享、翻译和持久化仍消费完整 `imageTranslationBlocks`，不会因列表筛选丢失内容。
- 待复查行以图标和文字分别显示“低置信”“方向待定”；筛选为空时显示“无需复查”。共享判定由 `ImageOCRResultSummary` 持有，confidence 与阈值均夹取到 `0...1`，恰好 `0.5` 不算低置信。
- 新增 `ImageOCRReviewFilter`、纯 Swift 产品模型 evaluator 和 v3.1 Python 契约，并接入 v1.87 / v2.2-v3.1 fail-fast 图片 UI CI step；同步修正 v3.0 契约，使其接受共享 helper 与分组 changed-files 路由，同时继续锁定严格阈值语义。独立复审后将列表、预览与 Store 重渲染断言收紧到各自源码作用域，避免全文件 substring 对错误接线产生假绿。

验证与遗留：

- v1.87、v2.2-v3.1 图片/UI 契约共 84 项通过；CI validation tier / version identity 契约 14 项通过。四份改动 Swift 源码 parse、Xcode 工程 plist、workflow YAML、ground truth 与现有 output JSON 解析、工程版本唯一解析为 `v3.0` 和 `git diff --check` 均通过。
- 核心 SHA `281c74ea9c8b00c522dec6edc9682e1f46e51b4f` 的云端 full run `30321376115` attempt 1 成功；artifact `aitrans-ci-v3.1-codeb-v3.1-image-ocr-review-filter--281c74ea9c8b-run30321376115-attempt1` 与 version / branch / SHA / run / profile 完全一致，图片/UI 84 项、Speech/home/paste、extended Koharu validator matrix 和 Xcode build 均通过，JUnit 10/10，`.xcresult` build succeeded，commit status `AITRANS CI/full-validation=success`。
- 版本收口 SHA `88da91e050928a42164233d75d9b12f696f4eb9b` 的云端 full run `30321736785` attempt 1 成功；artifact `aitrans-ci-v3.1-codeb-v3.1-image-ocr-review-filter--88da91e05092-run30321736785-attempt1` 与 identity 完全一致，`MARKETING_VERSION=3.1`、Xcode build success、JUnit 10/10、`.xcresult` 0 error / 0 warning，commit status `AITRANS CI/full-validation=success`。本次只改工程版本和入口文档，领域合同按 changed-files 路由跳过，由核心 full 提供证据。
- 独立复审发现全文件 substring 可能让错误预览接线假绿；加固 HEAD `1bb8ee258667240e705a5ba2311e9eae4417f0a5` 将列表、预览与 Store 重渲染断言限定到各自源码作用域。云端 full run `30322310824` attempt 1 成功，artifact identity 完全一致，图片/UI 84 项通过，JUnit 10/10；manifest 明确 `xcodeBuildRequired=false`、`xcodeBuildSkippedReason=non_app_build_related_full_validation`，不冒充编译证据，编译继续由版本 SHA 的成功 `.xcresult` 证明。
- PR #65 exact HEAD fast run `30322411646` 成功后合并；merge follow-up run `30322449624` 成功，artifact `aitrans-ci-v3.1-smalldata_test--54c6ad5b548b-run30322449624-attempt1` 以 `validationProfile=fast`、`validationReason=merge_reuses_successful_candidate_full_validation` 精确复用候选 HEAD `1bb8ee258667240e705a5ba2311e9eae4417f0a5` 的成功 full 收据，JUnit 10/10。
- 未跑本机 build / 探针，按规则交给云端验证。本版不修改 Vision 请求、OCR layout、漫画探针、翻译、ground truth、`metrics/version_history.csv` 或 `output/`，不声称 OCR 字符准确率提升。

## v3.0：图片 OCR 复查与重新识别
日期：2026-07-27

状态：Agent X 已完成核心候选实现、本地轻量回归、核心与版本收口 exact-SHA 云端 full；工程正式版本为 `MARKETING_VERSION=3.0`。PR #64 已合入 `smalldata_test`，merge SHA `89b295c46ed84529db144ee2f104c2390f9612a6`；远端 `codeb/v3.0-image-ocr-rerun` 已删除，未触碰 `main`。

核心变更：

- 新增纯模型 `ImageOCRResultSummary`，从当前图片 blocks 计算翻译覆盖、平均 Vision confidence、低于 `50%` 的块数，以及 horizontal / vertical / unknown 方向分账；confidence 先夹取到 `0...1`，空结果不虚构平均值。
- 图片识别结果标题显示平均置信、低置信块、竖排与方向待定数量，帮助用户定位需要复查的 OCR 结果；不读取 ground truth，不改变 OCR 候选或排序。
- `.translated` 且 Store-owned 原图仍存在时显示“重新识别”。View 只调用 Store API；Store 复用内容输入/目标语言和既有 `retryImageTranslation()`，因此保留 task ID 隔离、源文件 ownership、render/share 失效和晚到结果拒收。
- 新增 v3.0 真实产品 summary evaluator 与 Python 源码合同，并接入 v1.87 / v2.2-v3.0 fail-fast UI interaction CI step。

验证与遗留：

- v1.87、v2.2-v3.0 图片/UI 契约共 78 项通过；CI validation tier / version identity 契约 14 项通过。三份改动 Swift 源码 parse、工程 plist、workflow YAML、ground truth 与现有 output JSON 解析、工程版本唯一解析为 `v2.9` 和 `git diff --check` 均通过；尚待云端 exact-SHA full。
- 核心 SHA `2169eb9cb156406c524f57583ae79cb300d4919f` 的云端 full run `30234737017` attempt 1 成功；artifact `aitrans-ci-v3.0-codeb-v3.0-image-ocr-rerun--2169eb9cb156-run30234737017-attempt1` 与 version / branch / SHA / run / profile 完全一致，图片/UI、Speech/home/paste、extended Koharu validator matrix 和 Xcode build 均通过，JUnit 10/10，`.xcresult` build succeeded，commit status `AITRANS CI/full-validation=success`。
- 版本收口 SHA `c2886c10ee2c19079df7234cbf224db9c8dd8df2` 的云端 full run `30234997262` attempt 1 成功；artifact `aitrans-ci-v3.0-codeb-v3.0-image-ocr-rerun--c2886c10ee2c-run30234997262-attempt1` 与 identity 完全一致，`MARKETING_VERSION=3.0`、Xcode build success、JUnit 10/10、`.xcresult` build succeeded，commit status `AITRANS CI/full-validation=success`。本次仅改工程版本和入口文档，领域合同按 changed-files 路由跳过，由核心 full 提供证据。
- PR #64 exact HEAD fast run `30235306860` 成功后合并；merge follow-up run `30235344391` 成功，artifact `aitrans-ci-v3.0-smalldata_test--89b295c46ed8-run30235344391-attempt1` 以 `validationProfile=fast`、`validationReason=merge_reuses_successful_candidate_full_validation` 复用候选 HEAD `ffbe2eca571f99e9ac85a25c9a743609a27c096b` 的成功 full 收据，JUnit 10/10。
- 未跑本机 build / 探针，按规则交给云端验证。本版不改 Vision 请求、OCR layout、漫画探针、翻译或 metrics，不声称 OCR 字符准确率提升，也不刷新 output。

## v2.9：图片重渲染状态与重试
日期：2026-07-27

状态：Agent X 已完成核心候选实现、本地轻量回归、核心与版本收口 exact-SHA 云端 full；工程正式版本为 `MARKETING_VERSION=2.9`。PR #63 已合入 `smalldata_test`，merge SHA `1154e474627084544d52a5230340c56b986f2824`；远端 `codeb/v2.9-image-render-feedback` 已删除，未触碰 `main`。

核心变更：

- Store 新增图片导出重渲染 `idle / rendering / failed` 状态；覆盖模式切换开始前发布 rendering，成功、取消、失败和内容失效均按 render ID / task ID 收口，旧 render 不覆盖新内容。
- rendering 时 segmented Picker 和 Store API 双重拒绝重复模式切换；当前失败使用 danger 状态并显示具体消息，提供 Store-owned“重试导出”入口。
- 无 staging URL 不再静默 return 并永久停留在活动态，而是进入可重试失败；既有稳定导出 ownership、staging 清理、分享状态、OCR、翻译、Koharu 和探针不变。
- 新增 v2.9 纯 Swift 状态 evaluator 与 Python 源码合同，并接入 v1.87 / v2.2-v2.9 fail-fast UI interaction CI step。

验证与遗留：

- v1.87、v2.2-v2.9 图片/UI 契约共 73 项通过；CI validation tier / version identity 契约 14 项通过。三份改动 Swift 源码 parse、工程 plist、workflow YAML、ground truth 与现有 output JSON 解析、`git diff --check` 均通过。
- 核心 SHA `42eac84cdbf111e948ff32296d1fa73d1d7938c9` 的云端 full run `30233705540` attempt 1 成功；artifact `aitrans-ci-v2.9-codeb-v2.9-image-render-feedback--42eac84cdbf1-run30233705540-attempt1` 与 version / branch / SHA / run / profile 完全一致，图片/UI、Speech/home/paste、extended Koharu validator matrix 和 Xcode build 均通过，JUnit 10/10，`.xcresult` build succeeded，commit status `AITRANS CI/full-validation=success`。
- 版本收口 SHA `37ea55b4c75597852a87163ac67ee9c77daeaaed` 的云端 full run `30234070675` attempt 1 成功；artifact `aitrans-ci-v2.9-codeb-v2.9-image-render-feedback--37ea55b4c755-run30234070675-attempt1` 与 identity 完全一致，`MARKETING_VERSION=2.9`、Xcode build success、JUnit 10/10、`.xcresult` build succeeded，commit status `AITRANS CI/full-validation=success`。本次仅改工程版本和入口文档，领域合同按 changed-files 路由跳过，由核心 full 提供证据。
- PR #63 exact HEAD fast run `30234308535` 成功后合并；merge follow-up run `30234339482` 成功，artifact `aitrans-ci-v2.9-smalldata_test--1154e4746270-run30234339482-attempt1` 以 `validationProfile=fast`、`validationReason=merge_reuses_successful_candidate_full_validation` 复用候选 HEAD `c9f0b55e4ae9d8e6a786917fd2be63740598d6dc` 的成功 full 收据，JUnit 10/10。
- 未跑本机 build / 探针，按规则交给云端验证；`probe_mode=skip`，没有刷新 output 或漫画指标。真实 Koharu 四件套仍缺失，validator 正确报告 `manifestMissing` / `stopUntilArtifactsProvided`。

## v2.8：图片分享准备反馈
日期：2026-07-27

状态：Agent X 已完成核心候选实现、本地轻量回归，以及核心和版本收口 exact-SHA 云端 full；工程正式版本为 `MARKETING_VERSION=2.8`。PR #62 已合入 `smalldata_test`，merge SHA `9ec7ef02febc7a4dc62556a1019f1afa2cd7b57c`；远端 `codeb/v2.8-image-share-feedback` 已删除，未触碰 `main`。

核心变更：

- Store 新增 request-scoped `idle / preparing / failed` 图片分享状态；异步硬链接/复制开始前发布 preparing，当前请求成功复位，当前请求失败保留独立消息，旧请求不得覆盖新状态。
- 图片页准备分享时将导出按钮切换为“准备中”并禁用重复点击；页面标题和状态行优先显示分享进度/失败，失败使用 danger，不再让已翻译状态掩盖分享错误。
- 既有 share request、View presentation identity、可读文件名、目录 ownership 和删除失败重试保持不变；dismiss、内容失效和页面离开继续统一清理并复位反馈。本版不修改 OCR、Koharu、翻译、renderer、探针或 metrics。
- 新增 v2.8 纯 Swift 状态 evaluator 与 Python 源码合同，并接入 v1.87 / v2.2-v2.8 fail-fast UI interaction CI step。

验证与遗留：

- v2.8 6/6、v2.7 9/9、v2.6 7/7、v2.5 10/10、v2.4 9/9、v2.3 4/4、v2.2 10/10、v1.87 12/12、CI 分层 9/9、版本身份 5/5，以及三份修改 Swift parse、Xcode 工程 lint、YAML 解析、三份 JSON 解析和 `git diff --check` 已通过。未跑本机 build / 探针，按规则交给云端验证。
- 首个核心 SHA `4442166e026c846ae004be753851cf08d913807e` 的云端 full run `30232563563` 中全部合同通过，但 Xcode build 因两个 `statusTone` getter 在多语句函数中继续使用无上下文隐式 enum member 而失败；已按结果包 `xcodebuild.log` 改为显式 return，并加入合同防回归。该失败 run 不作为编译收据。
- 修复后核心 SHA `c9ce5681532289c905fd4d5b3cecdac89be922a7` 的云端 full run `30232677854` attempt 1 成功；artifact `aitrans-ci-v2.8-codeb-v2.8-image-share-feedback--c9ce56815322-run30232677854-attempt1` 与 version / branch / SHA / run / profile 完全一致，v2.8 与既有图片合同、Speech/home/paste、extended Koharu validator matrix 和 Xcode build 均通过，JUnit 10/10，`.xcresult` 0 error / 0 warning，commit status `AITRANS CI/full-validation=success`。
- 版本收口 SHA `f43e957d89ad2ad2716641ee61697e2ed855cf65` 的云端 full run `30233086479` attempt 1 成功；artifact `aitrans-ci-v2.8-codeb-v2.8-image-share-feedback--f43e957d89ad-run30233086479-attempt1` 与 identity 完全一致，`MARKETING_VERSION=2.8`、Xcode build success、JUnit 10/10、`.xcresult` 0 error / 0 warning，commit status `AITRANS CI/full-validation=success`。本次只改工程版本和入口文档，领域合同按 changed-files 路由跳过，由核心 full 提供证据。
- 纯文档 follow-up fast run `30233244480` 正确复用父 SHA `f43e957d89ad2ad2716641ee61697e2ed855cf65` 的 full-validation success；PR fast run `30233276603` 成功。merge fast run `30233308760` 的 artifact 与 merge HEAD `9ec7ef02febc7a4dc62556a1019f1afa2cd7b57c` 一致，`validationReason=merge_reuses_successful_candidate_full_validation`，精确复用第二父候选 SHA `aa6c8a4b636741ea5334bc2aec1d132df012fd65` 的 propagated success。

## v2.7：图片 OCR 输入语言与方向闭环
日期：2026-07-27

状态：Agent X 已完成核心候选实现、本地轻量回归、两轮独立复审，以及核心和版本收口 exact-SHA 云端 full；工程正式版本为 `MARKETING_VERSION=2.7`。PR #61 已合入 `smalldata_test`，merge SHA `f98426f17ae8bfc2a6c2937008ca4f4f6436aaf4`；远端 `codeb/v2.7-image-ocr-direction` 已删除，未触碰 `main`。

核心变更：

- 图片页新增显式输入语言菜单，不再要求用户回到文本页猜测当前 Vision OCR 语言。Store 从 `.loading` 前同时冻结图片输入/目标语言；失败、取消和跨页全局语言修改不覆盖当前内容凭据，清空才重置，已完成图片改输入语言会从 Store-owned source 重跑 OCR 和翻译。
- `VisionOCRService` 增加保守方向证据。只有日语/中文 prior、bbox 高宽比至少 `1.6`、高度至少 `0.035`，并包含多字 CJK run 或具有同列邻居且没有近同行邻居时才判 vertical；同行单字 CJK 碎片、孤立单字、非 CJK 高框和近方形 CJK 保持 unknown / 原横排 fallback。横排上到下、行内左到右；竖排列右到左、列内上到下；两类 observation 分开聚类。
- `ImageTranslationBlock` 新增可选 `sourceDirection`、`directionConfidence` 和 `directionReason`，保留后续 Koharu 风格布局证据，同时兼容旧 Codable 数据。本版不修改覆盖 renderer、漫画探针、ground truth、模型或翻译 prompt。
- 新增 v2.7 纯 Swift 几何 evaluator 与 Python 源码合同，并接入 v1.87 / v2.2-v2.7 fail-fast UI interaction CI step。
- 两轮独立复审发现并修复：带容差的成对比较器可能形成排序环；行优先输入只检查最后 cluster 会拆散交错双栏；同行单字 CJK 高框可能误升竖排；失败/取消保留态不能为下次 Retry 更新输入凭据；evaluator 重复实现产品算法；布局引擎文件未命中 CI 合同路由。当前 evaluator 直接链接产品引擎，并穷举 mixed、比较器链和双栏 fixture 的输入排列。

验证与遗留：

- v2.7 9/9、v2.6 7/7、v2.5 10/10、v2.4 9/9、v2.3 4/4、v2.2 10/10、v1.87 12/12、CI 分层 9/9、版本身份 5/5，以及五份修改 Swift parse、Xcode 工程 lint、YAML 解析、三份 JSON 解析和 `git diff --check` 已通过。独立复审的实现与合同问题均已修复。
- 核心 SHA `61168f3f81a3bd1b87cfa724134eefdc47f1d289` 的云端 full run `30231620821` attempt 1 成功；artifact `aitrans-ci-v2.7-codeb-v2.7-image-ocr-direction--61168f3f81a3-run30231620821-attempt1` 与 version / branch / SHA / run / profile 完全一致，v2.7 9/9、既有图片合同、Speech/home/paste、extended Koharu validator matrix 和 Xcode build 均通过，JUnit 10/10，`.xcresult` 无 error / warning summary，commit status `AITRANS CI/full-validation=success`。
- 版本收口 SHA `41e9a1df4591752de13d5cd37a16addd35fa7793` 的云端 full run `30231918177` attempt 1 成功；artifact `aitrans-ci-v2.7-codeb-v2.7-image-ocr-direction--41e9a1df4591-run30231918177-attempt1` 与 identity 完全一致，`MARKETING_VERSION=2.7`、Xcode build success、JUnit 10/10、`.xcresult` 0 error / 0 warning，commit status `AITRANS CI/full-validation=success`。本次只改工程版本和入口文档，领域合同按 changed-files 路由跳过，由核心 full 提供证据。
- 纯文档 follow-up fast run `30232087193` 正确复用父 SHA `41e9a1df4591752de13d5cd37a16addd35fa7793` 的 full-validation success；PR fast run `30232132423` 成功。merge fast run `30232173778` 的 artifact 与 merge HEAD `f98426f17ae8bfc2a6c2937008ca4f4f6436aaf4` 一致，`validationReason=merge_reuses_successful_candidate_full_validation`，精确复用第二父候选 SHA `8122de32ecf2fbec69b36b77b8831567a6325025` 的 propagated success，JUnit 10/10。
- 合成 bbox fixture 只证明排序、聚类和 fallback 契约，不证明真实日文 OCR 字符准确率提升。本轮不刷新 `output/`，不追加 `metrics/version_history.csv`；真实竖排收益需要后续合法日文图片 corpus 或人工图像验收。
- 未跑本机 build / 探针，按规则交给云端验证。

## v2.6：图片分享文件生命周期
日期：2026-07-26

状态：Agent X 已完成候选实现、本地轻量验证、独立复审，以及核心和版本收口 exact-SHA 云端 full；工程正式版本为 `MARKETING_VERSION=2.6`。PR #60 已合入 `smalldata_test`，merge SHA `b4c35299212c3948d0e2b3e3f6d7da6395107d11`；远端 `codeb/v2.6-image-share-lifecycle` 已删除，未触碰 `main`。

核心变更：

- 内部稳定导出继续保留 v2.5 的 Store marker + render UUID 安全格式；用户点击“导出”时，Store 在专用 `ImageTranslationShares/<share UUID>/` 中异步创建 `<base>-translated.png` 硬链接，硬链接不可用时回退复制，系统分享只看到人类可读 leaf filename。
- Store share request ID 同时核对当前 export URL，View presentation ID 另行阻止旧 Task 用 `nil` 关闭较新的 sheet；重复点击、dismiss、新任务、clear、模式重渲染或 View 离开都会失效旧请求并清理 Store-owned 分享目录，晚到 A 不得覆盖 B 或重新发布已失效 URL。
- 启动时只接管分享根目录直属、名称为真实 UUID 的常规目录；outside、nested、任意目录名、symlink 和 dangling symlink 拒绝。删除失败保留私有 ownership，后续生命周期重试。
- 新增 v2.6 纯 Swift share lifecycle evaluator 与 Python 源码合同，并接入 v1.87 / v2.2 / v2.3 / v2.4 / v2.5 / v2.6 fail-fast UI interaction CI step。

验证与遗留：

- v2.6 7/7、v2.5 10/10、v2.4 9/9、v2.3 4/4、v2.2 10/10、v1.87 12/12、Store/View Swift parse 与 `git diff --check` 通过。
- 核心 SHA `dfe459a9a5be265422c9d4bfd80dc0b0db6dc914` 的云端 full run `30229667313` attempt 1 成功；artifact `aitrans-ci-v2.6-codeb-v2.6-image-share-lifecycle--dfe459a9a5be-run30229667313-attempt1` 与 version / branch / SHA / run / profile 完全一致，v2.6 7/7、v2.5 10/10、v2.4 9/9、v2.3 4/4、v2.2 10/10、v1.87 12/12、Speech/home/paste、extended Koharu validator matrix 和 Xcode build 均通过，JUnit 10/10，`.xcresult` 可用，commit status `AITRANS CI/full-validation=success`。独立复审未发现 P1/P2/P3 问题。
- 版本收口 SHA `e6e9e0405151cfcf26c305ba18949ebc5b363051` 的云端 full run `30230077269` attempt 1 成功；artifact `aitrans-ci-v2.6-codeb-v2.6-image-share-lifecycle--e6e9e0405151-run30230077269-attempt1` 与 identity 完全一致，`MARKETING_VERSION=2.6`、Xcode build success、JUnit 10/10，commit status `AITRANS CI/full-validation=success`。本次只改工程版本和入口文档，领域合同按 changed-files 路由跳过，由父核心 full 提供证据。
- 纯文档 follow-up fast run `30230251036` 正确复用父 SHA `e6e9e0405151cfcf26c305ba18949ebc5b363051` 的 full-validation success；PR fast run `30230285101` 成功。merge fast run `30230317879` 的 artifact 与 merge HEAD `b4c35299212c3948d0e2b3e3f6d7da6395107d11` 一致，`validationReason=merge_reuses_successful_candidate_full_validation`，精确复用第二父候选 SHA `f030428f5c0d0657c5dbbfcf1e610308204999e3` 的 success，静态检查成功且 Xcode 按规则跳过。
- 未跑本机 build / 探针，按规则交给云端验证。本轮不改变 Vision OCR、Koharu、翻译或覆盖算法，不声称质量指标提升，不刷新 `output/`，不追加 `metrics/version_history.csv`。

## v2.5：图片 workspace 异常恢复
日期：2026-07-26

状态：Agent X 已完成候选实现、本地轻量验证、两轮独立复审，以及核心与版本收口 exact-SHA 云端 full；工程正式版本为 `MARKETING_VERSION=2.5`。PR #59 已合入 `smalldata_test`，merge SHA `322296e2bb8a664706a332bc65c610c917557dbc`；远端 `codeb/v2.5-image-workspace-recovery` 已删除，未触碰 `main`。

核心变更：

- App 正常启动时扫描 `ImageTranslations` 直属文件，分账接管 `aitrans-export-<render UUID>-<base>-translated.png` 稳定导出、`<task UUID>-<name>` 输入副本和 `.<base>-translated-<render UUID>.staging.png`，清理上次崩溃、强退或升级遗留的不可恢复文件；`performsStartupWork=false` 的 Preview / 测试 Store 不扫描。
- input、staging 与 stable export 共享目录、文件名 kind、regular-file 和 symlink 安全门槛；正常运行中的 input/staging 删除也必须显式传入可信 workspace，wrong-kind、任意文件名、目录外、嵌套、`..` escape、symlink 和 dangling symlink 均拒绝。
- 启动或正常运行清理失败的 input/staging 进入独立 orphan ownership 集合，后续新任务、clear 或重渲染继续重试；稳定导出必须带 Store marker 与真实 render UUID，普通 `*-translated.png` 和 task UUID source 不再被误认。v2.3 Retry source 边界保持不变。
- 新增 v2.5 纯 Swift workspace recovery evaluator 与 Python 源码合同，并接入 v1.87 / v2.2 / v2.3 / v2.4 / v2.5 fail-fast UI interaction CI step；旧合同同步要求可信 workspace 参数。

验证与遗留：

- v2.5 10/10、v2.4 9/9、v2.3 4/4、v2.2 10/10、v1.87 12/12、CI 分层 9/9、版本身份 5/5、Swift parse 与 `git diff --check` 通过；v1.87 旧 staging 断言已升级为可信 workspace 签名，并保留发布身份门控与初始 staging 清理约束。
- 核心 SHA `8626c9c3799b3e4a6b65249c9fc28ac993b448e4` 的云端 full run `30205285339` attempt 1 成功；artifact `aitrans-ci-v2.5-codeb-v2.5-image-workspace-recovery--8626c9c3799b-run30205285339-attempt1` 与 version / branch / SHA / run / profile 完全一致，v2.5 10/10、v2.4 9/9、v2.3 4/4、v2.2 10/10、v1.87 12/12、Speech/home/paste、extended Koharu validator matrix 和 Xcode build 均通过，JUnit 10/10，`.xcresult` build succeeded 且 issue summaries 为空，commit status `AITRANS CI/full-validation=success`。
- 版本收口 SHA `efba55b0d59644801fd995207fbd33a3e41fdedb` 的云端 full run `30205587693` attempt 1 成功；artifact `aitrans-ci-v2.5-codeb-v2.5-image-workspace-recovery--efba55b0d596-run30205587693-attempt1` 与 identity 完全一致，`MARKETING_VERSION=2.5`、Xcode build success、JUnit 10/10、`.xcresult` succeeded 且 0 error / 0 warning，commit status `AITRANS CI/full-validation=success`。本次仅改工程版本和入口文档，领域合同按 changed-files 路由跳过，由父核心 full 提供证据。
- 纯文档 follow-up fast run `30205758867` 正确复用父 SHA `efba55b0d59644801fd995207fbd33a3e41fdedb` 的 full-validation success；PR fast run `30205796901` 成功。merge fast run `30205833063` 的 artifact `aitrans-ci-v2.5-smalldata_test--322296e2bb8a-run30205833063-attempt1` 与 merge HEAD 一致，`validationReason=merge_reuses_successful_candidate_full_validation`，精确复用第二父候选 SHA `bab9b050ab99c31a154f02781aa71c14ef5bf834` 的 success，JUnit 10/10。
- 未跑本机 build / 探针，按规则交给云端验证。本轮不改变 Vision OCR、Koharu、翻译或覆盖算法，不声称质量指标提升，不刷新 `output/`，不追加 `metrics/version_history.csv`。
- 已知升级遗留：v2.4 的 `<base>-translated.png` 没有 marker 或 receipt，无法与同后缀用户源文件无歧义区分；v2.5 为避免误删不自动接管这批 legacy 文件。新 marker 中的 render UUID 会出现在系统分享文件名，后续版本应在 Store-owned 分享层提供人类可读建议文件名，不在 View 直接创建临时副本。

## v2.4：图片稳定导出生命周期
日期：2026-07-26

状态：Agent X 已完成候选实现、两轮独立复审、核心与版本收口 exact-SHA 云端 full，工程正式版本为 `MARKETING_VERSION=2.4`。PR #58 已合入 `smalldata_test`，merge SHA `63f6f109703c31207dd4b8027cdecf73994e8b32`；远端 `codeb/v2.4-image-export-lifecycle` 已删除，未触碰 `main`。

核心变更：

- 新图片任务、清空和模式重渲染开始时，删除当前 Store-owned 稳定导出 PNG，避免 UI 清空 URL 后不同文件名的旧导出继续在 `Application Support/ImageTranslations` 累积。
- 稳定导出使用独立私有 ownership 集合；两个真实 publish 点统一登记 ownership。App 启动时接管并清理上次进程遗留的稳定导出，避免重启或升级后旧 PNG 永久不可达。
- 统一 discard 会立即撤销公开 share URL，只允许删除 `ImageTranslations` 直属、非隐藏 `*-translated.png` 常规文件；同目录 source、staging、目录外、嵌套、`..` escape、symlink 和 dangling symlink 均拒绝。删除失败项保留 ownership，后续新任务、clear 或重渲染继续重试。
- 取消仍保留已发布 source 和 v2.3 Retry 边界；stale renderer 仍只清理自己的 staging 文件，A/B 反序或当前 render failure 不得发布过期 export。
- 新增 v2.4 纯 Swift 文件生命周期 evaluator 与 Python 源码合同，并接入 v1.87 / v2.2 / v2.3 / v2.4 fail-fast UI interaction CI step。

验证与遗留：

- v2.4 9/9、v2.3 4/4、v2.2 10/10、v1.87 12/12、Swift parse、workflow YAML 与 `git diff --check` 通过。
- 核心 SHA `a48fb2a461160ebd4445347dcb5c094dcc16e400` 的云端 full run `30203732662` attempt 1 成功；artifact `aitrans-ci-v2.4-codeb-v2.4-image-export-lifecycle--a48fb2a46116-run30203732662-attempt1` 与 version / branch / SHA / run / profile 完全一致，v2.4 9/9、v2.3 4/4、v2.2 10/10、v1.87 12/12、Speech/home/paste、extended Koharu validator matrix 和 Xcode build 均通过，JUnit 10/10，`.xcresult` succeeded 且 0 error / 0 warning，commit status `AITRANS CI/full-validation=success`。
- 版本收口 SHA `cac60468310d2a287b26a07ea42f840292002f89` 的云端 full run `30204029328` attempt 1 成功；artifact `aitrans-ci-v2.4-codeb-v2.4-image-export-lifecycle--cac60468310d-run30204029328-attempt1` 与 version / branch / SHA / run / profile 完全一致，Xcode build succeeded、JUnit 10/10、`.xcresult` 0 error / 0 warning，commit status `AITRANS CI/full-validation=success`。本次仅改工程版本和入口文档，领域契约按 changed-files 路由跳过，由父核心 full 提供证据。
- 纯文档 follow-up fast run `30204223555` 正确复用父 SHA `cac60468310d2a287b26a07ea42f840292002f89` 的 full-validation success；PR fast run `30204270154` 成功。merge fast run `30204295914` 的 artifact `aitrans-ci-v2.4-smalldata_test--63f6f109703c-run30204295914-attempt1` 与 merge HEAD 一致，`validationReason=merge_reuses_successful_candidate_full_validation`，精确复用第二父候选 SHA `1fc7d229be72e01a22f02e4b83c04d441d651fe3` 的 success，JUnit 10/10。
- 未跑本机 build / 探针，按规则交给云端验证。本轮不改变 Vision OCR、Koharu、翻译或覆盖算法，不声称质量指标提升，不刷新 `output/`，不追加 `metrics/version_history.csv`。

## v2.3：图片取消后重试一致性
日期：2026-07-26

状态：Agent X 已完成候选实现、独立审计、核心与版本收口 exact-SHA 云端 full，工程正式版本为 `MARKETING_VERSION=2.3`。PR #57 已合入 `smalldata_test`，merge SHA `4159251340375aec9f518ea03222f7a81d79b8d7`；远端 `codeb/v2.3-image-cancel-retry` 已删除，未触碰 `main`。

核心变更：

- v2.2 已在取消后保留完成 sandbox 发布的当前 source，但 retry 门槛只接受 `.failed`，导致取消后的 `.idle` 没有可见重试入口。v2.3 在 source 文件真实存在时允许 `.idle` / `.failed` 显示重试；transfer 尚未落盘的取消仍无重试，translated 结果继续走重译控制而不是 Retry，clear 继续删除 source。
- 新增独立 v2.3 纯 Swift evaluator 与 Python contract，并接入 fail-fast UI interaction CI step；任一 v1.87 / v2.2 / v2.3 契约失败都会阻塞候选 full。

验证与遗留：

- v2.3 4/4、v2.2 10/10、v1.87 12/12、Swift parse、workflow YAML 和 `git diff --check` 通过。未跑本机 build / 探针，按规则交给云端验证。
- 核心 SHA `ec41f72c0fc53ccf2a52100e1806888641910857` 的云端 full run `30202633449` attempt 1 成功；artifact `aitrans-ci-v2.3-codeb-v2.3-image-cancel-retry--ec41f72c0fc5-run30202633449-attempt1` 与 version / branch / SHA / run / profile 完全一致，v2.3 4/4、v2.2 10/10、v1.87 12/12、Speech/home/paste 和 Xcode build 均通过，JUnit 10/10，`.xcresult` succeeded 且 0 error / 0 warning，commit status `AITRANS CI/full-validation=success`。
- 版本收口 SHA `9367267260bb879a56a52c1c85804f638ad13dd9` 的云端 full run `30202806922` attempt 1 成功；artifact `aitrans-ci-v2.3-codeb-v2.3-image-cancel-retry--9367267260bb-run30202806922-attempt1` 与 version / branch / SHA / run / profile 完全一致，Xcode build succeeded、JUnit 10/10、`.xcresult` 0 error / 0 warning，commit status `AITRANS CI/full-validation=success`。本次仅改工程版本和入口文档，领域契约按 changed-files 路由跳过，由父核心 full 提供证据。
- 纯文档 follow-up fast run `30203035151` 正确复用父 SHA `9367267260bb879a56a52c1c85804f638ad13dd9` 的 full-validation success；PR fast run `30203070611` 成功。merge fast run `30203092489` 的 artifact `aitrans-ci-v2.3-smalldata_test--415925134037-run30203092489-attempt1` 与 merge HEAD 一致，`validationReason=merge_reuses_successful_candidate_full_validation`，精确复用第二父候选 SHA `7a148081b4bb7e53384b8882ebeaa5ebfd751d1b` 的 success，JUnit 10/10。
- 本轮不改变 Vision OCR、Koharu、翻译或覆盖算法，不声称质量指标提升，不刷新 `output/`，不追加 `metrics/version_history.csv`。

## v2.2：图片导入 run isolation
日期：2026-07-26

状态：Agent X 已完成候选实现、独立复审和两个 exact-SHA 云端 full，工程正式版本为 `MARKETING_VERSION=2.2`。PR #56 已合入 `smalldata_test`，merge SHA `eb18519d5d4e1629f79835beb37e8005e6dd8a81`；远端 `codeb/v2.2-image-import-run-isolation` 已删除，未触碰 `main`。

核心变更：

- PhotosPicker 的 `loadTransferable` 不再由 View 创建未持有的 `Task`；Store 从选择发生时即创建 task ID、固定源/目标语言、进入 loading，并持有 transfer、sandbox 写入、OCR、翻译和导出完整任务。旧照片的成功、失败或 nil 回调在新选择、文件导入、取消或清空后都不能覆盖当前状态。
- 新照片或图片文件可以在 OCR / 翻译运行中直接抢占旧任务。文件选择 completion 使用独立 UUID 精确匹配；View 只传 loader / result，不直接写业务状态。nil transferable 明确进入“照片读取失败”，新任务开始即清除旧 retry source。
- sandbox 输入使用 task UUID 隔离同名文件；helper 只返回 URL，只有 await 后 task identity 仍匹配才发布 source。被抢占的 detached 写入、被替换的旧源和清空的当前源会删除；取消后仍允许保留当前源并立即重试。

验证与遗留：

- 新增 `scripts/test-v202-image-import-run-isolation-contract.py` 与纯 Swift evaluator，当前 10/10 通过；覆盖 A/B 反序完成、nil、取消、清空、照片/文件交错、source 发布门槛、同名 sandbox 隔离、文件选择 UUID、选择器失败保留现有任务、旧源清理、retry source 门槛和组合 CI fail-fast。v1.87 UI interaction 回归 12/12、Swift parse、workflow YAML 与 `git diff --check` 通过。
- 核心 SHA `e59bc4fc13946ff91383a9c3a128cc55f7ca2108` 的云端 full run `30202007400` attempt 1 成功；artifact `aitrans-ci-v2.2-codeb-v2.2-image-import-run-isolation--e59bc4fc1394-run30202007400-attempt1` 与 version / branch / SHA / run / profile 完全一致，v2.2 10/10、v1.87 12/12、Speech/home/paste、extended Koharu validator matrix 和 Xcode build 均通过，JUnit 10/10，`.xcresult` succeeded 且 0 error / 0 warning，commit status `AITRANS CI/full-validation=success`。父 SHA 的 superseded run `30201926721` 已取消，不作为证据；scope 因父收据失败安全回退全仓并记录 `candidate_full_repo_fallback`。
- 版本收口 SHA `6086c24af42d629937ae61bf8a3d01e9ce3f684d` 的云端 full run `30202239509` attempt 1 成功；artifact `aitrans-ci-v2.2-codeb-v2.2-image-import-run-isolation--6086c24af42d-run30202239509-attempt1` 与 identity 完全一致，`MARKETING_VERSION=2.2`、Xcode build success、JUnit 10/10、`.xcresult` succeeded 且 0 error / 0 warning，commit status `AITRANS CI/full-validation=success`。本次仅改版本与入口文档，领域契约按 changed-files 路由跳过，由父核心 full 提供证据。
- 纯文档 follow-up fast run `30202386858` 正确复用父 SHA `6086c24af42d629937ae61bf8a3d01e9ce3f684d` 的 full-validation success；PR fast run `30202421300` 成功。merge fast run `30202456969` 的 artifact `aitrans-ci-v2.2-smalldata_test--eb18519d5d4e-run30202456969-attempt1` 与 merge HEAD 一致，`validationReason=merge_reuses_successful_candidate_full_validation`，精确复用第二父候选 SHA `04d20baeb74603ab0778f8ce09b87023526ca364` 的 success。
- v2.2 contract 已接入 UI interaction CI 路由。未跑本机 build / 探针，按规则交给云端验证。
- 本轮不改变 Vision OCR 算法、漫画探针、Koharu shadow OCR、翻译 prompt 或模型，不声称 OCR 指标提升，不刷新 `output/`，不追加 `metrics/version_history.csv`。

## v2.1：Koharu assignment geometry coverage
日期：2026-07-26

状态：Agent X 已完成核心候选实现、独立复审和两个 exact-SHA 云端 full 验证，工程正式版本为 `MARKETING_VERSION=2.1`。PR #55 已合入 `smalldata_test`，merge SHA `9d92ab7c3c74c4a78b266bf5bb7c5531e96040c9`；远端 `codeb/v2.1-koharu-geometry-coverage` 已删除，未触碰 `main`。

核心变更：

- external TextBox shadow OCR 将 OCR outcome 与 assignment geometry 分账。空间可信标准统一为中心包含或 `IoU >= 0.10`；弱 overlap 仍可执行 shadow OCR，但写入 `geometryWeakBlockIndexes` 并不得关闭 coverage gate。
- Bubble alignment 从旧的缺失即 matched 改为 `matched / unknown / conflict`：双方 external Bubble ID 相同才 matched，任一侧缺失为 unknown 且不获得 score bonus，双方不同继续拒绝 edge。
- Bubble instance ID 与 TextBox ID 同样强制非空唯一；缺失、空白或非字符串输出 `bubbleIDMissing:<index>`，重复输出 `duplicateBubbleID:<id>`。Swift 解码不再为缺 ID 生成随机 UUID。
- 报告、TXT、handoff、convergence 和 CI manifest 新增 `minimumTrustedIoU`、trusted / weak / unknown Bubble block arrays、geometry ratio / verdict；只有 OCR 与 geometry 两条 ledger 都完整才允许 `WI/G-external-textbox-shadow-ocr-coverage` closed / passed。

验证与遗留：

- 新增 v2.1 Python contract 与真实 Swift evaluator，覆盖弱/强阈值、center containment、Bubble conflict / unknown、OCR/geometry 正交、完整/阻塞 verdict、旧 JSON 解码和 Bubble invalid fixture；v2.1 6/6、v2.0 6/6、v1.99 5/5、v1.92 5/5、v1.97 handoff 6/6、CI tier 9/9、version identity 5/5 均通过。
- 核心 SHA `b9a3ebcdd49e7329511d750e005ce7452e27b047` 的云端 full run `30200743723` attempt 1 成功；artifact `aitrans-ci-v2.1-codeb-v2.1-koharu-geometry-coverage--b9a3ebcdd49e-run30200743723-attempt1` 与 SHA / branch / run / profile 完全一致，JUnit 10/10、Xcode build success、Koharu extended validator matrix 与 Speech/UI/home/paste 契约通过，commit status `AITRANS CI/full-validation=success`。
- 版本收口 SHA `e555916f4c5db3db1711231a807390bb26b178de` 的云端 full run `30201087646` attempt 1 成功；artifact `aitrans-ci-v2.1-codeb-v2.1-koharu-geometry-coverage--e555916f4c5d-run30201087646-attempt1` 与 SHA / branch / run / profile 完全一致，Xcode build success、JUnit 10/10、`.xcresult` build status succeeded 且 0 error / 0 warning，commit status `AITRANS CI/full-validation=success`。本次仅改版本与文档，领域契约按 changed-files 路由跳过，并由父核心 SHA `b9a3ebcdd49e7329511d750e005ce7452e27b047` 的 full 收据提供证据。
- 纯文档 follow-up fast run `30201329109` 正确复用父 SHA `e555916f4c5db3db1711231a807390bb26b178de` 的 full-validation success；PR fast run `30201362562` 成功。merge fast run `30201394710` 的 artifact `aitrans-ci-v2.1-smalldata_test--9d92ab7c3c74-run30201394710-attempt1` 与 merge HEAD 一致，`validationReason=merge_reuses_successful_candidate_full_validation`，精确复用第二父候选 SHA `54ce9e1218b85c4509361214ec1f8c5970eddf60` 的 success。
- 本轮保持 shadow-only，不改变主 OCR、翻译、覆盖图、`blockPassed` 或 promotion。默认 push 使用 `probe_mode=skip`，artifact 仅含 `probe-not-run.txt`；仓库仍无真实四件套，不声称 OCR 数字提升，不刷新 `output/`，不追加 `metrics/version_history.csv`。
- 未跑本机 build / 探针，按规则交给云端验证。

## v2.0：Koharu external TextBox 一对一 coverage
日期：2026-07-26

状态：Agent X 已完成核心候选复审和版本收口，工程正式版本为 `MARKETING_VERSION=2.0`。PR #54 已合入 `smalldata_test`，merge SHA `88c6b303d619a8234054865d4a735bc1de7c76a7`；远端 `codeb/v2.0-koharu-shadow-coverage` 已删除，未触碰 `main`。

核心变更：

- external TextBox shadow OCR 从逐块独立取最佳候选改为确定性的最大基数二分匹配；block 与 TextBox 都最多消费一次，增广路径避免多候选 block 抢占单候选 block，最终以 TextBox ID 稳定 tie-break。
- active TextBox ID 必须是非空唯一字符串；Python validator 与 App readiness 同步拒绝缺失/重复 ID，避免随机 UUID 参与匹配身份。
- `externalTextBoxShadowOCRReport` 新增逐块 matched / succeeded / failed / skipped partition、争用账本、最终 duplicate ledger、matched / successful / matched-OCR-success ratios 和 `coverageVerdict`。
- convergence 与 injected-artifact CI smoke 只有在分区一致、最终无重复 TextBox、所有 block OCR 成功且 `successfulCoverageRatio = 1` 时才允许 coverage gate passed；局部成功只阻塞 failed + skipped blocks，不再以任意一个成功块伪装整体闭合。

验证与遗留：

- 新增 `scripts/test-v200-koharu-shadow-coverage-contract.py` 与纯 Swift fixture `scripts/test-v200-koharu-shadow-coverage-evaluator.swift`，实际编译并执行增广重分配、单 TextBox 争用、complete / partial / no-success / duplicate / invalid partition、旧报告 Codable 兼容、ID 门槛和 CI/TXT 接线；保留旧 counts 与 `skippedBlocks` 便于报告消费者渐进迁移。
- 核心候选 SHA `9a4ad74e2c0d41b7b09f7a57a41d2b211082ce4d` 的云端 full run `30199459993` attempt 1 成功；artifact `aitrans-ci-v2.0-codeb-v2.0-koharu-shadow-coverage--9a4ad74e2c0d-run30199459993-attempt1` 与候选 HEAD 一致，v2.0 contract 6/6、extended Koharu validator matrix、Speech/UI/home/paste 契约和 Xcode build 均成功，JUnit 10/10，`.xcresult` 0 error / 0 warning，commit status `AITRANS CI/full-validation=success`。
- 版本收口 SHA `dd894c667d157aa5b2ef762b838143b88052ae66` 的云端 full run `30199669320` attempt 1 成功；artifact `aitrans-ci-v2.0-codeb-v2.0-koharu-shadow-coverage--dd894c667d15-run30199669320-attempt1` 与收口 HEAD 一致，`validationProfile=full`、`xcodeBuildRequired=true`、Xcode build success、JUnit 10/10、`.xcresult` 0 error / 0 warning，commit status `AITRANS CI/full-validation=success`。本次只改工程版本与文档，Koharu 领域契约按 changed-files 路由跳过，并由父核心 full 提供领域证据。
- 纯文档 follow-up fast run `30199855503` 正确复用父 SHA `dd894c667d157aa5b2ef762b838143b88052ae66` 的 full-validation success；PR fast run `30199891233` 成功。merge fast run `30199913442` 的 artifact 与 merge HEAD `88c6b303d619a8234054865d4a735bc1de7c76a7` 一致，`validationReason=merge_reuses_successful_candidate_full_validation`，精确复用第二父 SHA `c58bd3fe9ad819bbc9a4df950bdebbb97507befe` 的 success。
- 首次核心 push SHA `a22f7cab40b5711ffcdbddf203fec0f02d3766a6` 的 run `30199283447` 在创建 job 前因漫画探针长 `run` block 超过 GitHub 21000 字符表达式上限失败；后续把 Actions 表达式移至 step env，并顺带消除 `github.head_ref` shell 注入 lint 警告。该失败 run 无 jobs / artifact，不作为验证收据。
- 本轮保持 shadow-only，不改变主 OCR、翻译、覆盖图、`blockPassed` 或 promotion；仓库仍无真实四件套，不声称 OCR 数字提升，不刷新 `output/`，不追加 `metrics/version_history.csv`。
- 未跑本机 build / 探针，按规则交给云端验证。

## v1.99：Koharu line polygon 所属关系校验
日期：2026-07-26

状态：Agent X 已完成核心候选复审和版本收口，工程正式版本为 `MARKETING_VERSION=1.99`。PR #53 已合入 `smalldata_test`，merge SHA `832e29abc9f9bde8ba1698bd5dfe353814337194`；远端 `codeb/v1.99-koharu-polygon-containment` 已删除，未触碰 `main`。核心候选 SHA `1be5b53d7593932ab203dce4304f6eb0a577dec6` 与版本收口 SHA `8fdfc41b26f2b91cc4db284f321b967196f1ee9c` 的 task-scoped full 均已通过。

核心变更：

- Python artifact validator 与 App runtime readiness 不再只验证 `linePolygons` 位于整张源图内；每个 point 还必须属于对应 TextBox bbox，统一允许 `min(8px, max(2px, bbox 短边 2%))` 的舍入容差。
- 超出所属 bbox 容差的点写入 `linePolygonOutsideTextBoxBBox:<polygon>:<point>`，对应 TextBox 进入 invalid ledger，artifact verdict 为 `coordinateValidationFailed`，不能进入 external shadow OCR。
- invalid metadata fixture 新增“bbox 在一个区域、polygon 完全位于源图另一处”的样本，避免错误区域 warp OCR 被当作合法 TextBox 证据。

验证与遗留：

- 新增 `scripts/test-v199-koharu-line-polygon-containment-contract.py`，覆盖 bbox 内、容差边缘、部分越界、完全脱离、Python/Swift 同口径与 CI 接线，当前 5/5 通过；v1.92 warp contract 5/5、Swift parse、YAML parse、fixture JSON 与 `git diff --check` 通过。
- 核心候选云端 full run `30197944841` attempt 1 成功；artifact `aitrans-ci-v1.99-codeb-v1.99-koharu-polygon-containment--1be5b53d7593-run30197944841-attempt1` 与候选 HEAD 一致，extended Koharu validator matrix、v1.99 contract 5/5、Speech/UI/home/paste 契约和 Xcode build 均成功；JUnit 10/10，`.xcresult` build status succeeded、0 error、0 warning，commit status `AITRANS CI/full-validation=success`。
- 版本收口云端 full run `30198122722` attempt 1 成功；artifact `aitrans-ci-v1.99-codeb-v1.99-koharu-polygon-containment--8fdfc41b26f2-run30198122722-attempt1` 的 version、branch、commit、run 和 workflow identity 与收口 HEAD 一致，`validationProfile=full`、`xcodeBuildRequired=true`、Xcode build success、JUnit 10/10，commit status `AITRANS CI/full-validation=success`。本次 push 使用默认 `probe_mode=skip`，结果包仅保留 `probe-not-run.txt`，没有伪装为真实 Koharu 运行态证据。
- 纯文档 follow-up fast run `30198338709` 正确复用父 SHA `8fdfc41b26f2b91cc4db284f321b967196f1ee9c` 的 full-validation success；PR fast run `30198372211` 成功。merge fast run `30198404428` 的 artifact `aitrans-ci-v1.99-smalldata_test--832e29abc9f9-run30198404428-attempt1` 与 merge HEAD 一致，`validationReason=merge_reuses_successful_candidate_full_validation`，复用第二父 SHA `58dac079fc13ba309a10083ff03a0ef11d47cd09` 的成功状态。
- 本轮只加固真实 external artifact 的准入证据，保持 shadow-only，不改变主 OCR、翻译、覆盖图、`blockPassed` 或 promotion；仓库仍无真实四件套，不声称 OCR 数字提升，不刷新 `output/`，不追加 `metrics/version_history.csv`。
- 未跑本机 build / 探针，按规则交给云端验证。

## v1.98：图片预览与导出一致性
日期：2026-07-26

状态：Agent X 已完成核心候选独立复审与版本收口，工程 `MARKETING_VERSION=1.98`。PR #52 已合入 `smalldata_test`，merge SHA `28836f2d935828d30f1f187cf6706c387b00cb41`；远端 `codeb/v1.98-image-export-consistency` 已删除，未触碰 `main`。核心候选 SHA `87de0cd9503146f08c149a77ef99b4570813b6f4` 与版本收口 SHA `3dbb5d5bc2b683dc0505c86a9589c6fad960116b` 的 task-scoped full 均已通过。

核心变更：

- 普通图片导出从默认 Core Graphics 坐标改为顶左原点的 `UIGraphicsImageRenderer`，直接消费 Vision OCR 的 normalized top-left bbox，并由 `UIImage` 绘制处理源图方向，避免预览在顶部而导出落到垂直镜像位置。
- 导出 renderer 显式消费 `ImageTranslationOverlayMode`：`旁贴` 在原文字块侧边生成译文/原文气泡，`覆盖` 才在原 bbox 上绘制译文，不再出现预览切模式但导出固定覆盖。
- 已完成图片切换模式时立即清除旧 export URL 并异步重绘；后台 renderer 每次只写 render ID 独占的 staging PNG，独立 render ID、图片 task ID 与 mode 三重核对通过后才原子发布稳定 export，避免已拒收的旧 detached render 反向覆盖新文件。新任务、清空、取消都会取消并失效旧 render，过期 staging 会清理。
- 图片 OCR/翻译运行中禁用模式选择；最终 render 后再次核对图片 task ID。若程序化模式切换与最终 render 交错，完成翻译后按当前模式重绘。

验证与遗留：

- `scripts/test-v187-ui-interaction-contract.py` 新增顶左坐标、mode renderer、模式重绘、先验身份后发布和 staging 清理契约，当前 12/12 通过；两份修改 Swift 源码通过完整 Xcode toolchain `swiftc -frontend -parse`，`git diff --check` 通过。
- 核心候选云端 full run `30196905125` attempt 1 成功；artifact `aitrans-ci-v1.98-codeb-v1.98-image-export-consistency--87de0cd95031-run30196905125-attempt1` 的 version、branch、commit、run、workflow 和 changed-files identity 与候选 HEAD 一致。JUnit 10/10、UI interaction 12/12、Speech 14/14，Xcode `.xcresult` build status succeeded、0 error、0 warning，commit status `AITRANS CI/full-validation=success`。
- 版本收口云端 full run `30197163124` attempt 1 成功；artifact `aitrans-ci-v1.98-codeb-v1.98-image-export-consistency--3dbb5d5bc2b6-run30197163124-attempt1` 与收口 HEAD 一致，`MARKETING_VERSION=1.98`，JUnit 10/10，Xcode `.xcresult` build status succeeded、0 error、0 warning，commit status `AITRANS CI/full-validation=success`；Speech/UI 大契约按纯版本与文档 scope 跳过，仍以上一核心 SHA 的 exact artifact 为证据。
- PR fast run `30197360465` 与 merge fast run `30197407724` 均成功；merge artifact `aitrans-ci-v1.98-smalldata_test--28836f2d9358-run30197407724-attempt1` 的 version、branch、commit、run identity 正确，`validationReason=merge_reuses_successful_candidate_full_validation`，复用第二父候选 SHA `dfca6563c0b3e9105a23de194d7b0f11e5086825` 的成功 full-validation status。
- 本轮没有修改 Vision OCR 识别/聚类、翻译 prompt、模型或漫画探针，不声称 OCR/翻译质量数字提升，不刷新 `output/`，不追加 `metrics/version_history.csv`。
- 未跑本机 build / 探针，按规则交给云端验证。

## v1.97：Koharu 真实路径加固
日期：2026-07-26

状态：Agent X 已完成核心候选独立复审与版本收口，工程 `MARKETING_VERSION=1.97`。核心 PR #50 已合入 `smalldata_test` merge `326a160596edc36051d8e345cb3311ed6715cb73`；CI 版本身份 maintenance PR #51 已合入 merge `5566b2bff8f7f1afef4a98a1fdbe96da0c8813be`，均未触碰 `main`。

核心变更：

- external TextBox 的多条 `linePolygons` 改为逐行隔离 warp / OCR 失败。单行异常不再丢弃同一 TextBox 内已成功的行；只有全部行失败才整块回退 bbox OCR。
- 部分成功使用 `linePolygonPerspectiveWarpPartial` / `externalArtifact.linePolygonWarpPartial`，保留逐行失败原因并加入 `linePolygonWarpPartialFailure`。该结果可进入 shadow OCR 对照，但不得通过既有 promotion gate，orientation convergence 必须保持 partial / blocked。
- Koharu handoff packet 不再默认指向旧仓库。repo、workflow ref 和 expected commit SHA 由显式参数或 GitHub / 当前 git 环境解析为同一 `targetIdentity`，并统一驱动 upload、dispatch、run list、manifest assertions、review 清单和 stale-run rejection；workflow 入口在任何验证前硬核对 expected SHA，ref 已移动时立即失败。
- CI fixture 改为显式假 repo/ref/SHA，新增 v1.97 独立契约，避免再次把本机默认或错误远端锁成“测试通过”。
- PR #50 merge fast follow-up run `30195296033` 暴露 `smalldata_test` 不含版本号时 artifact 被标为 `unversioned`。后续维护分支 `codeb/v1.97-ci-version-identity` 增加工程版本解析器：无版本 ref 回退到唯一 `MARKETING_VERSION`，缺失或配置冲突直接失败；Speech recognition / quality 接线契约也不再硬编码旧 `1.96`。

验证与遗留：

- 本地轻量验证包括 v1.92 line polygon contract、v1.97 handoff target contract、v1.94 CI tier contract、validator fixture 矩阵、JSON/YAML parse、Swift parse 和 `git diff --check`。
- 核心候选云端 full run `30194847103` attempt 1 成功；artifact `aitrans-ci-v1.97-codeb-v1.97-koharu-real-path-hardening--d6d6fcc82aaf-run30194847103-attempt1` 的 version、branch、commit、run、workflow 和 changed-files identity 与候选 HEAD 一致。JUnit 10/10、Xcode `.xcresult` build status succeeded、0 error、0 warning，commit status `AITRANS CI/full-validation=success`。
- 当前仓库仍无真实 `test/koharu_artifacts/` 或 Release 四件套，根 `output/` 仍是 `manifestMissing` 基线。因此本轮不声称 OCR 数字、翻译通过率或覆盖质量提升，不刷新 `output/`，不追加 `metrics/version_history.csv`。
- 未跑本机 build / 探针，按规则交给云端验证。核心候选云端 `probe_mode=skip`，没有真实四件套注入；真实四件套到位后，使用 packet 的 exact repo/ref/SHA 手动 dispatch `ci-fast`，再核对 App runtime identity、partial orientation blocker、external shadow OCR coverage 和 reconciliation。

## v1.96：图片翻译目标语言一致性
日期：2026-07-26

状态：Agent C 已完成核心候选验收并执行版本收口，工程 `MARKETING_VERSION=1.96`。核心候选 HEAD `03f6f731f79e7345abf69ca01f9ad8583e273705`；PR #49 仅在收口提交的 exact-SHA CI 通过后合并到 `smalldata_test`，不触碰 `main`。

核心变更：

- 图片页新增目标语言菜单，复用 `TranslationSessionStore.targetLanguage`、既有 Pro 门控和锁定提示；不新增独立持久化状态，也不改变漫画探针固定英译中路径。
- 图片翻译任务在开始时固定源语言和目标语言。逐块 OCR/翻译期间，即使其他页面修改全局语言，当前任务也不会混用不同语言方向。
- 已完成的图片切换为新的可用目标语言时，从沙盒原图重新执行 OCR、翻译和覆盖导出；运行态菜单禁用，防止同一任务内改写目标语言。
- 图片任务单独记录当前内容实际使用的目标语言。其他页面修改全局目标语言后，图片页的标题、菜单、选中标记和 VoiceOver 仍显示实际译文语言；再次选择全局已选但与图片结果不同的语言时仍会触发重译。
- Agent C 首轮退回后补齐失败/取消生命周期：只要图片数据或部分 OCR/译文仍可见，就保留对应目标语言；只有清空图片或新任务替换内容时才重置，避免错误态和取消态重新按全局语言错标。
- Agent C 二次退回后补齐 loading 空窗：任务运行状态无条件使用已固定的任务语言，即使图片数据与 blocks 尚为空，跨页面修改全局语言也不会短暂错标标题、菜单或 VoiceOver。

关键文件：

- `AITRANS/Views/ImageTranslationViews.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `scripts/test-v187-ui-interaction-contract.py`

验证与遗留：

- 已通过 `python3 -B scripts/test-v187-ui-interaction-contract.py`（10 项）、`python3 -B scripts/test-speech-recognition-contract.py`（14 项）、`git diff --check` 和三份现有 JSON 解析；独立契约验证任务语言先于 `.loading` 发布且 running 分支不依赖图片数据/blocks，并继续覆盖跨页面改语言、同值重译及无 OCR/错误/取消/清空状态转换。
- 核心候选云端 full run `30193309626` attempt 1 成功；artifact `aitrans-ci-v1.96-codeb-v1.96-image-language-consistency--03f6f731f79e-run30193309626-attempt1` 的 version、branch、commit、run、workflow 和 changed-files identity 与候选 HEAD 一致，Xcode build、JUnit 10/10、UI interaction 10/10、Speech 14/14 均通过，`.xcresult`、日志和失败摘要可用。
- 未跑本机 build / 探针，按规则交给云端验证；本轮没有修改漫画算法或报告模型，因此未更新 `metrics/version_history.csv`。

## 当前漫画指标基线
日期：2026-06-29

当前项目是 SwiftUI iOS 本地翻译原型，主线已从普通翻译 UI 转到漫画截图 OCR、本地翻译、覆盖合成和探针诊断。最新可用基线来自当前 `output/probe_report.json`、`output/clean_text_diagnostic.json` 和 `metrics/version_history.csv` 的 v21 行：

- `sourceImage = test/1.png`
- `engineUsed = Local GGUF`
- `decodingMode = deterministic`
- `decodingSeed = 42`
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
- `frameworkComparison.consistencyPassed = true`
- `fusionComparison.consistencyPassed = true`
- `fusion.fused.accuracyVsGroundTruth = 0.7384`
- `cleanTextDiagnostic.passRate = 0.4545`
- `textRegionCropReport.totalRegions = 13`
- `textRegionCropReport.cropSucceededCount = 10`
- `textRegionCropReport.adoptedCount = 0`
- `textRegionCropReport.rejectedCount = 13`
- `bubbleSubRegionReport.totalSubRegions = 11`
- `bubbleSubRegionReport.clampEligibleCount = 2`
- `bubbleSubRegionReport.oversizedBubbleIDs = [4, 6, 7]`
- `textRegionCropReport.clampSources = { bubbleBBox: 9, contentRect: 2, subRegion: 2 }`
- `bubbleMaskReport.instanceCount = 8`
- `bubbleMaskReport.maskSafeLayoutBlocks = 13`
- `bubbleMaskReport.bboxFallbackBlocks = 0`
- `bubbleMaskReport.inconsistentBubbleAssignmentBlocks = [4, 5, 11, 12]`
- `bubbleMaskReport.renderMaskOverflowBlocks = []`
- `bubbleAssignmentCorrectionReport.recommendedCorrectionBlocks = [5, 11]`
- `bubbleAssignmentCorrectionReport.appliedToCropClampBlocks = [5]`
- `bubbleAssignmentCorrectionReport.rejectedCorrectionBlocks = [4, 11, 12]`
- `bubbleSplitCandidateReport.parentBubbleIDs = [4, 6, 7]`
- `bubbleSplitCandidateReport.candidateCount = 6`
- `bubbleSplitCandidateReport.clampEligibleCount = 3`
- `bubbleSplitCandidateReport.appliedToCropClampBlocks = [5, 9, 10]`
- `textBoxCandidateReport.candidateCount = 13`
- `textBoxCandidateReport.cropEligibleCount = 6`
- `textBoxCandidateReport.usedForCropBlocks = []`
- `textBoxCandidateReport.rejectedBlocks = [2, 4, 5, 7, 9, 11, 12]`
- `segmentMaskReport.glyphMaskBlocks = 11`
- `segmentMaskReport.usableForCropEvidenceBlocks = [0, 1, 2, 3, 6, 7, 8, 9, 10, 11]`
- `segmentMaskReport.weakSegmentBlocks = [4, 5, 12]`
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
- v1.13 新增 `externalTextBoxShadowOCRReport` 后，云端 run `28381772143` 已验证默认缺 active artifact 时 `executed = false`、`gateVerdict = manifestMissing`、`candidateCount = 0`、`ocrExecutedCount = 0`、`promotedExternalShadowBlocks = []`、`skippedBlocks = [0...12]`。
- `textRegionCropReport.failureAttributionBreakdown = { localVisionRegression: 6, rawWordsLost: 5, bubbleMaskConflict: 3, emptyLocalOCR: 3, segmentMaskWeak: 3, textBoxTooWide: 2, introducedLikelyOCRError: 2, wordCountRegression: 2, sameAsFusedText: 2, insufficientQualityGain: 2 }`
- `passedBlocks = 1`
- `failedBlocks = 12`
- `translationFailureBreakdown = { modelOutputFailure: 2, ocrInputSuspect: 7, translationLanguageQualityFailure: 3 }`
- `likelyRuleFalseFailureBlocks = []`

当前结论：

- 当前瓶颈是 OCR 文本质量和 Gemma 270M 翻译能力，不是覆盖绘制，也不是规则过严。
- 主流程已切到 whole-page + bubble-first 融合；`Let's Battle!` 保留，bubble-first 独有两条真实内容也进入融合结果。
- post-fusion cleanup 已把 16 个融合块压到 13 个，拒绝重复/碎片块但保留关键真实内容。
- TextRegion crop OCR 候选层已接入报告和 `1_ocr_probe_text.txt`，本轮 13 个块全部被护栏回退，没有替换主翻译输入。
- `bubbleAudits` 标出 `bubbleID 4/6/7` 的分割风险；v13 新增轻量 `bubbleSubRegionReport`，v14 新增 `bubbleMaskReport`，v15 新增归属修正报告和保守 split candidate 报告，v16 新增轻量 `textBoxCandidateReport`、`segmentMaskReport` 和 crop failure attribution，v17 新增 shadow-only `cropExperimentReport`，v18 新增 TextRegion crop 前生成的 `preCropTextBoxPlanReport`，v19 新增 `textBoxPlanFailureReport`，v20 新增 `lineTextBoxPlanReport` / `lineCropExperimentReport`。当前只有 block 5 的归属修正用于 crop clamp，split candidate 用于块 `[5, 9, 10]` 的 crop clamp；TextBox 候选是 TextRegion crop 之后派生的诊断层，`usedForCropBlocks = []`；pre-crop plan、crop experiment、line crop experiment 的 best shadow candidate 和 failure attribution 都不替换 `finalTextUsedForTranslation`；crop 采用护栏未放宽。
- v20 证明 block `[1, 6, 10]` 的 line-level / deskew shadow 候选仍不能通过既有 promotion gate，应停止继续在这条 crop/line/deskew 试参线上消耗。
- v21 新增真实 TextBoxes / BubbleMask / SegmentMask artifact 适配前证据闸门；当前 `test/koharu_artifacts/` 不存在，报告明确阻塞在 `manifestMissing`，不得伪造 detector 接入。
- v1.13 新增 external TextBoxes shadow OCR 接入口，完全由 `externalArtifactReadinessReport.externalTextBoxesShadowOCRAllowed` 门控；ready 前只写阻塞报告，ready 后每块最多 1 个 `externalArtifact.textBoxCrop` 候选，只进 JSON / TXT，不替换主 OCR、翻译、覆盖或通过判定。
- Vision `customWords` 对当前图最终合并文本无变化，`changedBlockIndexes = []`。
- 确定性 OCR 纠错能提升部分相似度，但翻译收益不稳定，仍只做探针对照。
- tagged batch 翻译分支格式崩坏，不替换逐块翻译。

## 历史记录
### v1.95：Speech 真实语料质量算法与探针接线
日期：2026-07-13

状态：候选实现中，分支 `codeb/v1.95-speech-quality-corpus`，基于 v1.94 merge `aa829bc14bedc91fe1c54b629a8ac50dda0e4833`；工程 `MARKETING_VERSION=1.95`。本轮不生成 TTS 或占位音频，不声称 Apple Speech 识别质量已经提升；v1.96 等人工上传真实音频后再产生 WER/CER 和延迟证据。

核心变更：

- 新增 `aitrans.speech_corpus.v1` manifest：每项固定 ID、文件名、SHA256、字节数、locale、参考 transcript 和来源说明；Python validator 拒绝路径逃逸、重复 ID、缺字段和音频身份漂移。仓库缺 manifest 时输出 `manifestMissing` / `qualityExecuted=false`，不会把“未执行”伪装成质量通过或失败。
- 新增纯 `SpeechQualityEvaluator`：兼容大小写/宽度/标点规范化、通用 Levenshtein、词级 WER、字符级 CER 和按 reference token 加权 aggregate。中日文在没有稳定分词器时 `wordErrorRate=nil`，不把字符指标伪装成 WER。
- 新增独立 `SpeechQualityProbeService`：逐项校验音频身份，强制 `SFSpeechURLRecognitionRequest.requiresOnDeviceRecognition=true`，记录最终 transcript、延迟、segment、平均 confidence、on-device 能力和失败分类；120 秒超时与取消会终止当前 Speech task。
- 参考 transcript 只在 Apple Speech 返回最终文本后传给 evaluator；报告固定 `referenceUsedForEvaluationOnly=true`、`referenceUsedForRecognitionDecision=false`，不参与请求、候选、纠错或产品翻译。
- `TranslationSessionStore` 持有质量探针 Published 状态、独立 run ID/Task、取消与 DEBUG `AITRANS_RUN_SPEECH_QUALITY_PROBE` 入口；开发控制台只调用 store，展示报告摘要，不新增截图流程。
- JSON/TXT 写入既有 `Application Support/AITRANS/Output/`；报告包含 corpus/manifest/audio 身份、runtime、逐项指标、加权 WER/CER、平均延迟和 failure breakdown。磁盘写入错误必须附加 `outputWriteFailed` warning 并把 UI 置为失败，不能把只有内存报告的运行显示为已写出。
- Speech full CI 增加质量源码契约、纯 Swift evaluator、corpus validator 和新文件 changed-scope routing；候选核心 push 仍只跑一次 full + Xcode，不采 UI evidence，PR/merge 复用 v1.94 fast follow-up。

本地轻量验证：Speech 旧 contract 14/14、v1.95 quality contract 7/7、缺 corpus validator 的 `manifestMissing` 审计结果、纯 Swift evaluator contract、Swift 6 iOS Simulator 目标三文件 typecheck 均通过。未跑本机 build / 探针，按规则交给云端验证；未运行真实 WER/CER，因为仓库没有用户提供的音频和 manifest。

关键文件：`AITRANS/Models/SpeechQualityModels.swift`、`AITRANS/Services/SpeechQualityEvaluator.swift`、`AITRANS/Services/SpeechQualityProbeService.swift`、`AITRANS/Services/TranslationSessionStore.swift`、`AITRANS/Views/DeveloperConsoleView.swift`、`scripts/validate-speech-corpus.py`、`test/speech_corpus/README.md`、`.github/workflows/ci-results.yml`。

非目标与遗留：不更换 Apple Speech、不引入第三方 ASR、不改产品识别候选、不做 UI 重构或截图；真实语音质量必须等 v1.96 音频后在目标设备运行。漫画图像链路仍缺真实 Koharu manifest/TextBoxes/BubbleMask/SegmentMask 四件套和 `ci-fast` 对照，detector/mask/renderer 的 report-only proxy 不能描述为已完成 Koharu 复刻；本轮未改漫画算法、未跑漫画探针、不追加 `metrics/version_history.csv`。

### v1.94：云端 Full-Once / Fast-Follow-Up 验证分层
日期：2026-07-13

状态：已合入 `smalldata_test`。最终候选 `6864bd889fbab60f0c70d9df5d7b43e9440b594b`，PR #47，merge `aa829bc14bedc91fe1c54b629a8ac50dda0e4833`，远端候选分支已删除，`main` 未触碰；工程 `MARKETING_VERSION=1.94`。本轮是 CI 制度与验证路由优化，不改变 App 业务主链、漫画 OCR/翻译/覆盖结果或 Speech 运行语义。

核心变更：

- `codeb/**` 核心 push 进入 task-scoped full：基础静态检查始终运行，Speech、UI、文本首页、Koharu 契约按 changed files 启用；App 相关变更只在该 full 执行 Xcode build。成功后 workflow 为 exact SHA 写 `AITRANS CI/full-validation` commit status。
- PR 新增 opened / reopened / ready-for-review fast follow-up，但不监听 synchronize，避免同一修复 push 同时运行 full 和 PR fast。PR fast 跳过 Xcode、领域大契约、GGUF/探针和 UI evidence，只保留静态/CI 路由与可审计结果包。
- `smalldata_test` merge 读取第二父候选 SHA 的 full-validation status；success 才复用并走 fast，missing / failure / lookup failure 自动回退 full。C 退回后的新修复 SHA 必须重新 full。
- full 成功后的纯 README / AGENTS / update log / `md/` / metrics follow-up 可传播父提交收据；若父收据缺失或失败，workflow 会把 changed-files 扩展到完整候选 diff，防止失败代码被最后一个文档 commit 掩盖。
- UI evidence 不再按 `codeb/v1.9*` / `v2.*` 分支族自动跑。只有非 PR 候选 commit 的 `[ui evidence]` 或手动 `ui_evidence_mode=full` 启用；Speech 功能默认只验编译、run-id/取消/翻译链路契约，不截图。漫画/翻译需要图像证据时仍使用手动 `ci-fast/full` 的探针 output PNG。
- `AITRANS - Build IPA` 移除 `smalldata_test` push trigger，仅在软件包交付时手动 dispatch，日常 merge 不再重复 Release archive、加密、fakesign 和 IPA package。
- `ci-artifact-manifest.json`、JUnit、failure summary 与最终 gate 记录/消费 validation profile、reason、复用 receipt、领域 required flags、UI evidence reason 和 Xcode skip reason。新增 `scripts/test-v194-ci-validation-tier-contract.py` 锁定分层行为。

本地轻量验证：v1.94 CI tier contract 9/9、Speech contract 14/14、UI interaction 7/7、v1.88 home UI 7/7、v1.89 paste matrix 4/4 通过；两个 workflow YAML 可解析，所有内嵌 bash block `bash -n` 通过，`capture-ui-evidence.sh` syntax、三个基线 JSON、`MARKETING_VERSION=1.94` 唯一值与 `git diff --check` 通过。未跑本机 build / 探针，按规则交给云端验证；候选核心 commit 只触发一次 full，PR 与 merge 用 fast 验证分层本身。

首轮云端 run `29231418192` 在 job 创建前失败，GitHub annotation 明确为 `.github/workflows/ci-results.yml` manifest step `Exceeded max expression length 21000`；没有 jobs、日志或 artifact，且没有触发 Build IPA。修复将超大 manifest `run:` 内的 Actions expressions 全部移到 step `env`，Python 只读环境变量，并由 v1.94 contract 锁定 manifest script 不再内联 `${{ ... }}`，防止字段增长再次越过 GitHub 表达式上限。该失败属于 CI 配置，按规则修复 SHA 必须重新 full。

第二轮 run `29231948576` 在 SHA `aac5f8dc10bd89445cba70330dcca56b3702dd1b` 上 17 秒绿色结束，full-validation status 也写入成功，但验收发现它只比较失败提交到修复提交的增量 diff，未把首提交的工程版本变化纳入 changed-files，`xcodeBuildRequired=false`。该 run 只证明 expression-limit 修复能启动，不能作为 v1.94 候选 full/Xcode 证据。路由继续收紧：只要候选父 SHA 没有成功 full 收据，或本次修改 CI routing workflow，就必须从 `smalldata_test` merge-base 重新计算完整候选 diff，再决定 Xcode 与领域契约；因此下一 SHA 必须重新 full。

最终候选 full run `29232147877` 成功，耗时约 3 分 9 秒，Xcode success、JUnit 10/10、`.xcresult` 存在且 UI evidence skipped。PR fast run `29232478137` 约 19 秒，Xcode/领域大契约/UI 均 skipped。merge fast run `29233489356` 约 12 秒，manifest 为 `validationProfile=fast`、`validationReason=merge_reuses_successful_candidate_full_validation`、`reusedFullValidationSha=6864bd88...`、`reusedFullValidationState=success`、`xcodeBuildRequired=false`；merge 未触发 Build IPA。

非目标与遗留：不改变 Koharu report-only/active artifact 边界，不伪造真实四件套，不改善 WER/CER，不调整 App UI；本轮未跑漫画探针，不追加 `metrics/version_history.csv`。

### v1.93：Speech Run 取消与旧回调隔离
日期：2026-07-13

状态：Agent C / Agent X 验收通过。候选分支 `codeb/v1.93-speech-run-cancellation` 最终 HEAD `1b4f13ecab375387823428ebe6b305503eaa38c8`；PR #46 已合入 `smalldata_test`，merge `efd9c56a1001c6fcb9d2e6e4f153d4fe6f7fe184`，远端候选分支已删除。工程 `MARKETING_VERSION=1.93`；`main` 未触碰。

核心变更：

- store 持有独立 `speechTranslationTask`；取消先失效 Speech run ID，再取消 Speech recognition / translation Task 并回到 idle。新 run 在生成新 token 前取消并清理旧翻译 Task，支持取消后立即重试。
- 实时麦克风授权在 `requestMicrophoneAccess()` 的 `await` 返回后重新核对 run ID 与 capture request，旧授权回调不能把已取消或已重试的 run 写成失败或重新启动录音。
- 文件识别后的模型翻译与实时语音翻译都在 `await` 返回后核对 Task cancellation + run ID；`submit` 在 transcript 写入、summary 回写和错误状态写入前核对 Speech 所有权，旧翻译不会覆盖新 run。
- 音频文件和实时语音的 `.translating` 状态都提供取消入口；Speech contract 从 8 项增强为 14 项，按函数体顺序锁定授权、翻译、摘要、取消和立即重试边界。
- 第一轮 exact-SHA UI evidence 暴露 compact iPhone 运行态取消按钮被浮动 Tab Bar 遮挡；文件面板已把取消提升为运行态第一操作，并按状态显示“取消识别/取消翻译”，旧 run `29224663327` 因此不作为最终 UI 验收证据。
- Speech contract 从 static checks 去重，只保留独立 step，并进入 failure summary / fail-job 硬门控；失败仍会写入 JUnit、manifest 和独立日志。
- 最终证据矩阵新增 `audioTranslating` compact 场景，直接渲染非空实时 transcript、`.translating` 和“取消翻译”；总矩阵为 13 张（12 compact + 1 wide），不再只用 recognizing 截图间接证明 S5。

本地轻量验证：Speech contract 14/14、两个变更 Swift 文件 `swiftc -parse`、workflow YAML 解析和 `git diff --check` 通过。未跑本机 build / 探针，按规则交给云端验证；GitHub-hosted simulator 不能冒充真机麦克风、权限弹窗或 Apple Speech 识别质量证据。

云端实现验收：run `29225409696` attempt 1，artifact `aitrans-ci-v1.93-codeb-v1.93-speech-run-cancellation--dd77fe76bb35-run29225409696-attempt1`（2,780,359 bytes）。manifest 的 version / branch / commit / run / workflow 精确匹配；Xcode build、Speech 14/14、JUnit 8/8、v1.87-v1.89 contracts 和 12 张 current-HEAD UI evidence 全部通过。音频运行态截图 SHA256 `6bae5cac562a0de183d1cb794aa4010a4a9df1b093f543709f6b831228aebe3f`，取消按钮完整位于浮动 Tab Bar 上方。`probe_mode=skip`，符合本轮不改漫画路径的范围；本机缺 `xcresulttool`，但 `.xcresult` 结构、Info.plist、CI step 与 manifest 均可用。

版本收口验收：run `29226081679` attempt 1，artifact `aitrans-ci-v1.93-codeb-v1.93-speech-run-cancellation--891803630686-run29226081679-attempt1`（3,816,472 bytes）。manifest exact SHA / version / branch / run / workflow 对齐，`xcodeBuildRequired=true`，Xcode build、Speech 14/14、JUnit 8/8、v1.87-v1.89 contracts 和 12 张 current-HEAD UI evidence 通过；最终音频截图 SHA256 `ef627a294d056c03b5a380f73c9966740ee0c0a78c453cd54d1102431b1770ed`，取消动作仍完整可见。`probe_mode=skip`，未运行漫画探针或真实语音质量测试。

最终候选验收：run `29227415411` attempt 1，artifact `aitrans-ci-v1.93-codeb-v1.93-speech-run-cancellation--1b4f13ecab37-run29227415411-attempt1`（4,053,954 bytes）。manifest 精确匹配最终 HEAD；Xcode build、Speech 14/14、UI interaction 7/7、JUnit 8/8 与 13 张 current-HEAD UI evidence 成功，新增 `audioTranslating` 图证明“取消翻译”在 compact 夜间状态可见。`probe_mode=skip`。

post-merge 验收：CI Results run `29229554065` 与 Build IPA run `29229554033` 均 SUCCESS，head SHA 均为 `efd9c56a1001c6fcb9d2e6e4f153d4fe6f7fe184`。未加密 artifact `aitrans-ci-unversioned-smalldata_test--efd9c56a1001-run29229554065-attempt1` 的 manifest 匹配 branch / commit / run / workflow，`xcodeBuildRequired=true`、Xcode success、Speech success、JUnit 8/8、`.xcresult` 结构存在；UI evidence 与 manga probe 按 merge 范围跳过。IPA archive / fakesign / package 同 SHA 成功。

非目标与遗留：不更换 Apple Speech / 模型、不引入第三方 ASR、不声称改善 WER/CER；固定多语言音频 corpus、WER/CER/延迟报告和真机 S1-S8 人工矩阵仍是后续 Speech 质量阶段。漫画路径与 v1.92 指标均未改变，因此不追加 `metrics/version_history.csv`。

### v1.92：External TextBox Line Polygon Warp Shadow OCR
日期：2026-07-13

状态：Agent C / Agent X 已正式收口。PR #45 已合入 `smalldata_test`，merge `b374c19e99c784c5a933302a317a62572ba26355`，工程 `MARKETING_VERSION=1.92`。实现 HEAD `a514b2c8ffd99463859b7c715e1b5708f444d3fd` 与版本收口 HEAD `90b750821809f66b799e223919807a4fd4668940` 的云端 run 均 SUCCESS；未触碰 `main`。

核心变更：

- 对真实 external TextBox 的合法四点 `linePolygons` 使用 Core Image perspective correction 生成规整 line crop，逐行执行 Vision OCR 后合并；bbox + 0/90/180/270 rotation 路径继续作为 fallback。
- 只有 warp OCR 输出被最终候选选中时才写 `deskewExecuted = true`；bbox fallback 写独立 variant 并由 `linePolygonWarpOutputNotSelected` 阻止 report-only promotion，warp 失败或任意角度 rotation 继续阻塞 orientation convergence。
- validator / CI orientation fixture 改为声明 `linePolygonWarp = true`，新增 `orientationLinePolygonWarpSupportedTextBoxIDs`；`arbitraryRotationUnsupported` 仍保留。
- 仍为 shadow-only，不改 `finalTextUsedForTranslation`、主 OCR、翻译、覆盖图、`blockPassed` 或 active artifact；仓库仍没有真实四件套，不能声称完成 Koharu handoff。

云端实现验收：run `29219563408` attempt 1、artifact `aitrans-ci-v1.92-codeb-v1.92-koharu-line-polygon-warp--a514b2c8ffd9-run29219563408-attempt1`（3,869,756 bytes；SHA256 `5ffbc56b39057fde69e25e90f4fd562b028d6fbf07695005d208e61d72fd4f8c`）。manifest branch/commit/run/workflow 对齐，Xcode build / static / Speech / v1.87-v1.89 contracts / 12 张 UI evidence success，JUnit 8/8。`probe_mode=skip`，active artifact 仍为 `manifestMissing`；未跑真实四件套 Core Image/Vision runtime，不能声称 warp 已获 `ci-fast` 运行态证据。

版本收口验收：run `29220142240` SUCCESS，artifact `aitrans-ci-v1.92-codeb-v1.92-koharu-line-polygon-warp--90b750821809-run29220142240-attempt1`（3,871,273 bytes；SHA256 `8a3869af62d3f3b1516e4b01a3e0cab14c18189fbf69b3ccd335439b0742389e`），manifest exact SHA / branch / run / workflow 对齐，Xcode build、JUnit 8/8、v1.92 contract 5/5、Speech 8/8 和 12 张 UI evidence 通过。合并后 CI Results run `29220977461` 与 Build IPA run `29220977459` 均 SUCCESS；远端候选分支已删除。

本地轻量验证：Swift parse、v1.92 5/5、Speech 8/8、v1.87 6/6、v1.88 7/7、v1.89 4/4、validator/YAML/JSON/shell/`git diff --check` 通过。未跑本机 build / 探针，按规则交给云端验证。

### v1.91：Speech 人工矩阵与 Speech CI 契约独立门控
日期：2026-07-12

状态：Agent X 正式收口。PR #44 合入 `smalldata_test`。验收 HEAD `8d9145ae`，云端 run `29167471696` SUCCESS。`MARKETING_VERSION=1.91`。未触碰 `main`。

核心变更：

- `md/test/test.md` §0.5 Speech 人工矩阵 S1–S8（授权/取消/重试/runToken/离线包等），明确不可被 CI 冒充。
- CI：Speech contract 独立 step + JUnit/manifest 字段 + fail-job 硬失败；UI evidence 门控覆盖 `codeb/v1.9*` / `codeb/v2.*`。
- Koharu gap 文档状态更新到 v1.90；重申下一步是真实四件套 + ci-fast，禁止伪造 ready。

未跑本机 build / 探针；交给云端。无真实 Koharu artifact 时不触发 ci-fast 注入。

### v1.90：Speech 运行摘要增强与契约
日期：2026-07-12

状态：Agent X 正式收口。PR #43 合入 `smalldata_test`。验收 HEAD `69a86eb1`，云端 run `29167025229` SUCCESS。`MARKETING_VERSION=1.90`。未触碰 `main`。

核心变更：

- `SpeechRecognitionRunSummary` 增加 `runToken` 诊断字段，begin run 写入 UUID 前 8 位。
- 音频页运行摘要展示本机能力、终态与 Run token，保留离线强制/耗时/词数/置信度。
- Speech contract 增补：cancel 必须先 `invalidateSpeechRecognitionRun` 再 idle；UI 接线本机能力/终态/runToken。
- 不改 ASR 引擎、不引入第三方语音、不改漫画探针。

验证：本地 light contracts only；未跑本机 build / 探针，交给云端。

### v1.89 修复候选：wide-iPad UI evidence 串行 boot + CI 硬失败
日期：2026-07-12

状态：修复 push 至 `codeb/v1.89-paste-manual-matrix-wide-evidence`。run `29165244349` 中 contracts/Xcode 通过，但 `uiEvidenceOutcome=failure`：第二台 iPad 与 iPhone 并行迁移导致超时，11 张 compact 已有、缺 `text-empty-wide-ipad-day.png`；且 fail-job 未把 `codeb/v1.89-*` 的 UI evidence 失败计为硬失败（job 仍 SUCCESS）。

修复：

- `scripts/capture-ui-evidence.sh`：iPhone 矩阵完成后关机，再 create/boot iPad，避免双机 Data Migration 争用。
- `.github/workflows/ci-results.yml`：UI evidence timeout 15→25；`codeb/v1.89-*` UI evidence 失败硬失败；v1.89 contract 失败硬失败。

### v1.89：人工交互矩阵、Paste 可测性与 wide-iPad 证据
日期：2026-07-12

状态：Agent X 正式收口。PR #42 已合入 `smalldata_test`（merge `07b3e34b`）。验收 HEAD `3c8528d0`，云端 run `29166136570` SUCCESS。工程 `MARKETING_VERSION=1.89`。未触碰 `main`。

云端验收证据：

- artifact：`aitrans-ci-v1.89-codeb-v1.89-paste-manual-matrix-wide-evidence--3c8528d047f5-run29166136570-attempt1`
- JUnit 7/7；v1.87/v1.88/v1.89 contracts success
- UI evidence 12 张（11 compact-iPhone + 1 wide-iPad `text-empty-wide-ipad-day.png`），均 >135KB，commitSha 对齐 `3c8528d0`
- 真实系统 PasteButton 点击 / VoiceOver 回放仍属人工矩阵遗留，不得写成已验证

核心变更：

- `md/test/test.md` 新增 §0.3 可勾选人工交互与 a11y 矩阵（M1–M8），明确 CI 截图不能替代真实粘贴点击。
- DEBUG-only 粘贴注入：用户点击 `PasteButton` 且系统 payload 为空时，可读 `AITRANS_UI_TEST_PASTE_TEXT` 或 `-AITRANS_UI_TEST_PASTE_TEXT`；Release 无注入，lifecycle 不读剪贴板，系统 PasteButton 保留。
- `scripts/capture-ui-evidence.sh` 在 11 张 compact-iPhone 之外新增 1 张 `wide-iPad` 文本空态运行态证据（共 12 张）。
- 新增 `scripts/test-v189-paste-manual-matrix-contract.py`；CI 对 `codeb/v1.89-*` 开启 UI evidence，JUnit / manifest 增加 v1.89 contract 字段。

关键文件：

- `AITRANS/Views/TextTranslationView.swift`
- `scripts/capture-ui-evidence.sh`
- `scripts/test-v189-paste-manual-matrix-contract.py`
- `scripts/test-v188-home-ui-contract.py`
- `.github/workflows/ci-results.yml`
- `md/test/test.md`
- `md/prompt/v1.89（首页持续优化）/v1.89（人工交互矩阵与Paste可测性及宽屏证据）.md`

本地轻量验证：Speech 5/5、v1.87 6/6、v1.88 7/7、v1.89 4/4、workflow YAML parse、`git diff --check`；未跑本机 build / 探针，按规则交给云端验证。

遗留事项：

- 真实剪贴板与 VoiceOver 仍依赖人工矩阵勾选；DEBUG 注入不能冒充 Release 隐私路径已点通。
- 网络不可达时无法 push / 创建 PR / 合并 v1.88。
- 未改漫画探针与 `metrics/version_history.csv`。

### v1.88：文本首页极简科技工作台与剪贴板键盘交互
日期：2026-07-12

状态：Agent C / Agent X 正式收口。工程 `MARKETING_VERSION = 1.88`。PR #41 基于 `codeb/v1.88-home-translation-ui` HEAD `c8326bb068e512dbd8139271e65b38ddb3235b9c` 验收；云端 run `29104261998` attempt 1 SUCCESS 作为 build / contract / UI evidence 依据。本轮未做本机 Xcode / Simulator 交互点击验收，按用户约束只认云端结果；真实剪贴板点击、VoiceOver 回放与 iPad/Mac 运行态仍属遗留人工清单。合并目标仅为 `smalldata_test`，严禁触碰 `main`。

核心变更：

- 只重做文本翻译首页；新增独立 `TextWorkspaceBackground`，用静态冷中性层次、技术网格、导向线路和矩形节点替代旧纯色首页，不修改其他页面的全局背景。
- 首页保留安全区页头、语言、输入、输出、Prompt、翻译、会话和最近翻译；青蓝翻译、青绿粘贴、琥珀 Prompt、小面积紫红交换和中性会话命令同时使用图标、文字、描边与层级，不只依赖颜色。
- 新增系统纯文本 `PasteButton`。只有用户点击时读取兼容文本；空输入直接填入，非空输入以换行追加，不覆盖、不自动翻译、不记录剪贴板内容。
- 文本页统一持有输入焦点；keyboard toolbar 新增“完成”，翻译、新会话、Prompt 跳转和离开文本 Tab 前先失焦，翻译随后仍调用 `store.submitDraft`。
- 新增 `scripts/test-v188-home-ui-contract.py` 六项静态契约，并作为独立 CI step、JUnit testcase、manifest 字段和失败门控；v1.88 分支同时进入现有 current HEAD UI evidence 门控。
- Preview 新增 iPad 横屏文本页状态，但当前 CI 仍按既有约束只生成 11 张紧凑 iPhone 运行态证据；Preview 不冒充运行态截图或点击测试。

关键文件：

- `AITRANS/Views/TextTranslationView.swift`
- `AITRANS/Views/TextWorkspaceBackground.swift`
- `AITRANS/Views/TextWorkspacePasteButton.swift`
- `AITRANS/Views/AppTheme.swift`
- `AITRANS/Views/AppPreviewSupport.swift`
- `scripts/test-v188-home-ui-contract.py`
- `.github/workflows/ci-results.yml`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`

本地轻量验证：Swift parse 与无产物全工程 typecheck、`git diff --check`、PBX/plist lint、shell syntax、workflow YAML parse、Speech contract 5/5、v1.87 UI interaction contract 6/6、v1.88 home UI contract 7/7 和三个 JSON parse 已通过；未跑本机 build / 探针，按规则交给云端验证。

Agent C 多轮退回及 Agent B 截图复核：run `29092032857` 证明 72pt 内容尾部 padding 无法阻止浮动 Tab Bar 覆盖，run `29098058258` 又证明 bottom `safeAreaInset` + 88pt clearance 仍会被浮动栏覆盖，且 `ButtonStyle` 不能替换 `PasteButton` 的系统英文标签。run `29099734744` 已证明中文覆盖生效，但 96pt 外部净空压缩了标准字号首屏，且第四张设置截图被空白检测拦截。run `29100584989` 的完整证据证明固定 48pt 已解决大字号覆盖，却仍把标准字号“翻译”主按钮裁成一条色带。run `29102934707` 证明标准键盘关闭时取消净空可完整恢复“翻译”，但输入聚焦后键盘“完成”区域不可见。当前候选仅在 compact-width 且 Dynamic Type 为 XXL 或更大、或输入已聚焦时，于根 `VStack` 的 `ScrollView` 外预留 48pt；标准字号且键盘关闭时不插入净空，以同时满足首屏动作层级、大字号防遮挡和键盘附件可见。真实 `PasteButton` 继续使用透明前景并由不接收触摸的实底中文标签覆盖。上述旧 run 都只作为失败证据，新 HEAD 必须重新生成 build、JUnit、manifest 和 UI evidence，并由 Agent B 先逐张查看后再交给 Agent C。

云端验收证据（正式收口）：

- 产品 UI evidence HEAD：`c8326bb068e512dbd8139271e65b38ddb3235b9c`（`fix(ui): keep keyboard toolbar visible`）。
- 收口 commit：版本号/文档/contract assert 升到 1.88；merge 前以 push 后新 HEAD 的 CI manifest `commitSha` 核对。
- GitHub Actions run：`29104261998` attempt 1 SUCCESS。
- 结果包：`aitrans-ci-v1.88-codeb-v1.88-home-translation-ui--c8326bb068e5-run29104261998-attempt1`（2,772,091 bytes；SHA256 `f15c2ad59fcaba0eec3ae5795d9adc060bd3e06405374ce7e747a172cc87983e`）。
- `.xcresult`：0 errors / 0 warnings；JUnit 7/7；Speech contract 5/5；v1.87 UI interaction contract 6/6；v1.88 home UI contract 7/7。
- UI evidence：11 张紧凑 iPhone 运行态截图均 >135KB，覆盖空态中文“粘贴/翻译”、键盘“完成”、XXL / Accessibility Tab 净空。
- 本轮收口额外把 `MARKETING_VERSION` 从 `1.87` 升到 `1.88`，并将候选记录改为正式通过。

遗留事项：

- 真实系统 `PasteButton` 剪贴板投递、空剪贴板保留输入、换行追加、VoiceOver 标签与键盘“完成”点击回放未在本机 Simulator/真机重跑；XCUITest 在 iOS 26.5 上难以稳定注入 runner/app 隔离剪贴板。按用户约束不改生产粘贴语义仅为可测性让步；后续可用人工清单或 debug-only 注入补闭环。
- 当前 UI evidence 仍没有 iPad / Mac 运行态截图；宽屏并排只有源码和 Preview 状态，不能当作运行态验收结论。
- 模型、OCR、Speech、StoreKit、持久化、漫画探针、ground truth、仓库根 `output/` 和 `metrics/version_history.csv` 均未修改；本轮不追加漫画指标。
- 收口后进入 v1.89：固化人工交互矩阵、PasteButton 可测性、宽屏证据与首页信息密度再平衡。

### v1.87：企业级视觉系统与核心体验重构
日期：2026-07-10

状态：Agent C 已验收通过，工程正式版本号收口为 `1.87`；PR #40 负责合并到 `smalldata_test`，不触碰 `main`。

核心变更：

- 建立炭灰、冷白、电光青的语义设计 token，统一 canvas、surface、border、状态色、间距、8pt 以内圆角、44pt 触控目标和 Reduce Motion 行为。
- 语义色迁入 Asset Catalog 的日间/夜间变体；设置页提供跟随系统、日间、夜间选择，外观偏好独立保存在 `AppStorage`，不改变 `state.json` schema。
- `ContentView.swift` 从 3277 行缩减为根路由；文本、图片、音频、历史、提示词、设置、模型、Pro 和开发控制台拆为独立文件，继续共享唯一 `TranslationSessionStore`。
- 重做 iPhone 五入口 Tab 和 iPad `NavigationSplitView`；文本工作台、图片检查区、音频运行摘要、历史命令、提示词编辑、模型管理和开发报告使用一致的状态组件与响应式布局。
- 新增隔离 `AppPreviewScenario`，preview 不恢复、不写入生产 `state.json`，覆盖多设备、Dynamic Type、Reduce Motion 及代表性成功/失败/锁定状态。
- 新增 `scripts/capture-ui-evidence.sh` 与候选分支 CI 步骤，复用当前 Debug build 生成带设备、方向、Dynamic Type、状态、Reduce Motion 和 commit SHA 的截图 manifest；当前按人工要求收敛为同一台紧凑 iPhone 上的 11 张竖屏证据，新增提示词、模型和开发路径，iPad / Mac 视觉证据延期，证据步骤失败仍会阻塞 CI。
- 优化云端验证：单台紧凑 iPhone 通过 `bootstatus -b` 等待完整启动，避免“设备已标记 booted 但系统迁移未完成”导致首张截图阻塞，并消除两台新模拟器并行迁移的资源争用；文档-only push 可走 build-skip，UI evidence workflow 变化仍强制 build，Koharu 完整 invalid-fixture 矩阵仅在真实 validator / artifact contract 相关变化时运行。
- Speech contract 仅更新 UI 文件定位，保留取消、`translating` 和运行摘要断言强度。
- Agent C 在 `a925f944` 退回四项：录音按钮缺默认无障碍动作、关闭开发模式未退出开发控制台、Reduce Motion 场景未进入 capturing 分支、八类页面缺独立交互回归证据。当前修复为录音默认 accessibility toggle、`SettingsView` 显式 `NavigationPath` reset、`audioRecognizing.isCapturingProSpeech=true`，并新增 5 项 `test-v187-ui-interaction-contract.py`、独立 CI step / log / manifest 字段 / JUnit testcase。
- Agent C 在 `4a6c05c3` 的键盘截图发现模型状态随整页 `ScrollView` 自动滚动到系统状态栏。当前把文本页头和模型状态移到顶部 safe-area inset，仅让语言栏与翻译工作区参与键盘滚动，并新增对应源码契约，防止页头重新进入自动滚动区。

本地轻量验证：Swift parse、`git diff --check`、PBX/plist lint、shell syntax、workflow YAML parse、5 项 Speech contract、6 项 v1.87 UI interaction contract 和三个 JSON parse；未跑本机 build / 探针，按规则交给云端验证。

Agent C 验收证据：`d2b6ab32` 对应 run `29082220409` attempt 1，manifest 的 branch / commitSha / runId / runAttempt 与 PR HEAD 一致；`.xcresult` 为 `succeeded`、0 errors、0 warnings，JUnit 6/6，UI interaction contract 6/6，11 张紧凑 iPhone 运行态截图全部匹配当前 commit。Agent C 逐张复核日夜、键盘、XXL、Accessibility Dynamic Type、Reduce Motion、提示词、Local 缺模型和开发控制台状态；最终键盘证据中系统状态栏、页头、模型状态、输入区与软件键盘清楚分离。漫画探针为 `probe_mode=skip`，iPad / Mac 视觉证据与 XCUITest 点击回放不在本轮范围；未重跑漫画质量探针，因此不追加 `metrics/version_history.csv` 指标行。

### v1.86：Speech Recognition Insight and Audio UI Polish
日期：2026-07-08

依据：v1.85 已补齐 Koharu draft artifact contract 工具，但用户目标继续扩展到语音识别、云端测试和更精致的 UI。本轮先把音频识别从“只有一条状态文案”升级为可观察的本机识别运行摘要，并改善音频页操作反馈。

核心变更：

- 新增 `SpeechRecognitionRunSummary` 和 `SpeechRecognitionRunMode`，记录音频文件或实时麦克风识别的模式、输入名、locale、本机识别要求、设备支持状态、耗时、词数、分段数、平均置信度、最终文本和失败原因。
- `AudioRecognitionState` 新增 `translating`，区分 Apple Speech 识别中和识别文本交给模型翻译中。
- 文件音频识别和同声传译都会维护 `speechRecognitionRunSummary`；识别失败、权限拒绝、设备不支持、空文本、用户取消都会留下明确失败原因。
- 长按同声传译松手后，主动结束导致的 recognition task cancel error 不再覆盖为失败状态。
- 音频页新增识别质量摘要面板和识别取消入口，展示 locale、强制本机、耗时、词数、片段和置信度，让语音链路更可诊断、UI 信息层次更完整。
- 合并验收补强用 run UUID 隔离授权、Speech 和翻译回调，避免取消/重试后旧任务污染新摘要；当前翻译任务未结束时不启动实时语音采集。
- App bundle ID 统一为 `com.local.aitransform114`；CI 改为从构建 App `Info.plist` 动态读取 bundle ID，并让 `1.*` 版本分支触发合并前快验。
- Xcode `MARKETING_VERSION` 从 `0.1.0` 收口为 `1.86`，CI 也会把纯数字 `1.86` 分支记录为 artifact version `v1.86`。
- 新增 `scripts/test-speech-recognition-contract.py` 并接入 CI static checks；完整 v1.47-v1.86 汇总见 `md/prompt/v1.47-to-v1.86-update-notes.md`。
- 同步 `md/flow/flow.md` 和 `md/flow/flowchart.md` 的音频识别流程。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Views/ContentView.swift`
- `AITRANS/Views/ProFeatureViews.swift`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `.github/workflows/ci-results.yml`
- `scripts/test-speech-recognition-contract.py`
- `md/prompt/v1.47-to-v1.86-update-notes.md`
- `update_log.md`

验证结果：

- 本地轻量验证通过：`git diff --check`、`python3 -m json.tool test/1.ground_truth.json`、`python3 -m json.tool output/clean_text_diagnostic.json`、`python3 -m json.tool output/probe_report.json`。
- 合并验收补强通过：5 个 speech/CI contract tests、plist lint、workflow YAML parse、Swift parse、Python compile、Koharu draft/valid/orientation/missing/invalid fixture smoke。
- Swift / Xcode build 按项目规则交给 GitHub Actions；本轮 push 后需核对 `AITRANS CI Results` 和 `AITRANS - Build IPA`。

遗留事项：

- 本轮不引入第三方语音模型，不改变 Apple Speech 的 on-device 约束；真正“AI 语音识别”质量提升仍需要后续接入更强 ASR 或增加固定音频样本基准。
- 语音 UI 已改善诊断和反馈，但还未做整站级视觉重设计；后续可继续升级工作台、图片页和 Pro 页视觉系统。

### v1.85：Koharu Native Draft Artifact Tool
日期：2026-07-07

依据：v1.84 已把真实 Koharu handoff 后的 CI 结果核对清单补齐，但本地仍缺一个低风险工具，把 AITRANS 当前 probe block / bubble / glyph-mask proxy 以四件套 contract 形状导出，供外部 detector / handoff 开发快速对齐字段。该工具必须保持非 active、非真实 detector 输出，避免把 proxy 冒充为 `test/koharu_artifacts/`。

核心变更：

- 新增 `scripts/make-koharu-native-draft-artifacts.py`，从 `output/probe_report.json` 生成 `build/koharu_native_draft/1.manifest.json`、`1.textboxes.json`、`1.bubbles.json`、`1.segment_mask.json`。
- draft manifest 固定 `contractExampleOnly=true`，记录当前 `test/1.png` SHA256、生成来源、TextBox / Bubble / SegmentMask 来源和 count；当前旧 probe_report 缺 detector-lite 字段时，TextBoxes / BubbleMask 会从最终 probe blocks fallback 生成。
- 生成的草稿目录只用于 contract shape / validator smoke，validator 正确结果是 `verdict = contractExampleOnly`、`readyForShadowOCR = false`、`externalTextBoxesShadowOCRAllowed = false`，不得复制到 active `test/koharu_artifacts/`。
- artifact contract README 和测试规范同步该工具的用途、命令和禁止项。

关键文件：

- `scripts/make-koharu-native-draft-artifacts.py`
- `md/koharu研究/artifact_contract/README.md`
- `md/test/test.md`
- `update_log.md`

验证结果：

- 本地轻量验证通过：`python3 -B -m py_compile scripts/make-koharu-native-draft-artifacts.py`、`python3 scripts/make-koharu-native-draft-artifacts.py --out build/koharu_native_draft`、`python3 scripts/validate-koharu-artifacts.py --root build/koharu_native_draft`。草稿生成 13 个 TextBox、10 个 bubble summary、`segmentGlyphPixelCount = 92827`，validator 输出 `verdict = contractExampleOnly`、`sourceImageSHA256Matches = true`、`readyForShadowOCR = false`、`externalTextBoxesShadowOCRAllowed = false`。

遗留事项：

- 本版本不生成真实 Koharu 四件套、不写入 `test/koharu_artifacts/`、不上传 Release、不触发手动 `ci-fast/full`，不改变 OCR / LLM / renderer / 漫画指标，不追加 `metrics/version_history.csv`。
- 真正复刻效果仍需要外部 detector / Koharu 真实 TextBoxes、BubbleMask、SegmentMask 注入后跑 `ci-fast/full`；后续编译提速建议单独拆 `writeOCRProbeText` 到扩展文件，再云端 Xcode build 验证。

### v1.84：Koharu Handoff CI Result Review Packet
日期：2026-07-07

依据：v1.83 已把 Release archive 本地 inspection proof 写入 handoff packet，但真实 handoff 仍要等 GitHub Actions 手动 `ci-fast/full` 结果包证明 App runtime 实际读取同一组四件套。继续补交付后 Agent C 的云端结果包核对清单，避免错 run、旧包、错 commit 或只凭本地 inspection 放行。

核心变更：

- `handoffPacket` 新增 `ghRunWatchCommand` 和 `ghRunDownloadCommand`，用 `<run-id>` 占位指导人工在 workflow dispatch 后等待并下载 `AITRANS CI Results` 未加密结果包。
- `handoffPacket.ciResultReview` 和 `expected*Assertions` 新增机器可读核对清单，覆盖必需结果文件、探针输出文件、manifest identity、Release tag / asset / SHA 回显、Koharu validator identity / orientation、逐文件 cloud identity rows、App runtime readiness、identity reconciliation、external shadow OCR coverage、orientation blockers、TXT 摘要 needles 和旧包拒收规则。
- CI static package smoke 只断言这些 review / assertion 字段的 shape 和关键语义，不访问 GitHub、不下载 run、不启动模拟器、不把本地 `releaseArchive.inspection` 写成云端 runtime proof。
- artifact contract README 和测试规范同步 v1.84 handoff 后置 review 口径。

关键文件：

- `scripts/validate-koharu-artifacts.py`
- `.github/workflows/ci-results.yml`
- `md/koharu研究/artifact_contract/README.md`
- `md/test/test.md`
- `update_log.md`

验证结果：

- 本地轻量验证通过：`git diff --check`、`python3 -B -m py_compile scripts/validate-koharu-artifacts.py`、workflow YAML parse、JSON parse、Koharu valid / orientation / invalid fixture 矩阵、`test/koharu_artifacts --allow-missing`、fixture package handoff packet、`python3 -m json.tool /tmp/koharu-handoff-v184.json` 和新增 `ciResultReview` / structured assertions 字段 smoke。
- 云端 `AITRANS CI Results` run `28864811074` 通过，artifact `aitrans-ci-unversioned-smalldata_test--13591a80d066-run28864811074-attempt1` 已核对：`branch = smalldata_test`、`commitSha = 13591a80d0663fb3fed83f74e2cb03ddf851a05e`、`runId = 28864811074`、`runAttempt = 1`、`workflowName = AITRANS CI Results`、`xcodeBuildRequired = false`、`xcodeBuildSkippedReason = non_app_build_related_fast_path`、`probeMode = skip`、`scopeDiffMethod = checkout_before`、`scopeDiffFallbackUsed = false`、`koharuValidatorExtendedRequired = true`；`junit.xml` 为 5 tests / 0 failures；fixture package smoke 证明 `releaseArchiveInspectionPassed = true`、`releaseArchiveInspectionVerdict = contractExampleOnly`、`candidateDirectoryCount = 1`、`ghRunWatchCommand` / `ghRunDownloadCommand` 存在、`ciResultReview.requiredResultFiles` 覆盖四个必需文件、`expectedCloudIdentityRows = 5`、`expectedCIManifestAssertions = 14`、`expectedAppRuntimeAssertions = 10`、`expectedExternalShadowOCRAssertions = 8`、`expectedConvergenceAssertions = 6`、`staleRunRejectionAssertions = 5`。
- 同轮 `AITRANS - Build IPA` run `28864811123` 通过，archive 10m45s，IPA package 6s。

遗留事项：

- 本版本仍不生成真实 Koharu 四件套、不上传 Release、不触发手动 `ci-fast/full`，不改变 OCR / LLM / renderer / 漫画指标，不追加 `metrics/version_history.csv`。
- 真实验收仍必须由人工提供外部 detector 输出，按 handoff packet 上传 Release、dispatch `ci-fast/full`，再用 `ciResultReview` 核对云端 App runtime readiness、identity reconciliation、external shadow OCR coverage 和 orientation gates。

### v1.83：Koharu Handoff Archive Inspection Proof
日期：2026-07-07

依据：v1.82 已提供 `--inspect-release-archive` 和带 repo 的 Release upload / workflow dispatch 命令，但 handoff packet 本身还没有把“将上传的 archive 已按 CI 唯一四件套目录规则复验”作为结构化 proof 带给人工和 Agent C。继续补真实 artifact handoff 交付闭环，不新增 report-only 探针层，不改 Swift 主链路。

核心变更：

- `--package-release-archive` 生成 zip 后会立即用 `inspect_release_archive()` 复验该 zip，并把结果写入 `handoffPacket.releaseArchive.inspection`，包含 validation verdict、candidate directory、member count、artifact identity summary 和 orientation summary。
- `handoffPacket` 新增 `releaseArchiveInspectionPassed`、`releaseArchiveInspectionVerdict`、`inspectReleaseArchiveCommand` 和 `expectedCIManifestEcho`，让上传前 proof、Release asset SHA、workflow dispatch 参数和 Agent C 云端 manifest 核对点在同一个 JSON 中闭合。
- handoff ready 现在要求真实 validator verdict、archive SHA 和本地 archive inspection proof 同时成立；`contractExampleOnly` fixture 仍可用于 smoke，但不会被标记为 release / dispatch ready。
- `AITRANS CI Results` static checks 只在 fixture package smoke 中断言 handoff inspection proof，不把 inspection 重新塞回真实 Release 注入主路径，避免增加 workflow 启动风险。

关键文件：

- `scripts/validate-koharu-artifacts.py`
- `.github/workflows/ci-results.yml`
- `md/koharu研究/artifact_contract/README.md`
- `md/test/test.md`
- `update_log.md`

验证结果：

- 本地轻量验证通过：`git diff --check`、`python3 -B -m py_compile scripts/validate-koharu-artifacts.py`、workflow YAML parse、JSON parse、Koharu valid / orientation / invalid fixture 矩阵、`test/koharu_artifacts --allow-missing`、handoff packet、package 拒绝 / 成功 zip 布局、`--inspect-release-archive` 成功 / 空 archive / 双 candidate archive 失败路径、fixture handoff inspection proof、active-like handoff ready + inspection proof。
- 云端 `AITRANS CI Results` run `28861251800` 通过，artifact `aitrans-ci-unversioned-smalldata_test--642c1e2d5683-run28861251800-attempt1` 已核对：`branch = smalldata_test`、`commitSha = 642c1e2d5683339c6c8ae33fc0ff1437bdf17bb7`、`runId = 28861251800`、`runAttempt = 1`、`workflowName = AITRANS CI Results`、`xcodeBuildRequired = false`、`xcodeBuildSkippedReason = non_app_build_related_fast_path`、`probeMode = skip`、`scopeDiffMethod = checkout_before`、`scopeDiffFallbackUsed = false`、`koharuValidatorExtendedRequired = true`；package smoke 证明 `releaseArchiveInspectionPassed = true`、`releaseArchiveInspectionVerdict = contractExampleOnly`、`candidateDirectoryCount = 1`、`expectedCIManifestEcho` 存在，`junit.xml` 为 5 tests / 0 failures。
- 同轮 `AITRANS - Build IPA` run `28861251831` 通过。

遗留事项：

- 本版本仍不生成真实 Koharu 四件套、不上传 Release、不触发手动 `ci-fast/full`，不改变 OCR / LLM / renderer / 漫画指标，不追加 `metrics/version_history.csv`。
- 真实验收仍必须由人工提供外部 detector 输出，按 handoff packet 上传 Release 并 dispatch `ci-fast/full` 后，核对云端 App runtime readiness、identity reconciliation、external shadow OCR coverage 和 orientation gates。

### v1.82：Koharu Release Archive Inspect and Upload Commands
日期：2026-07-07

依据：v1.81 已能从本地四件套生成 Release zip 和 `workflow_dispatch` 参数，但真实 P0 handoff 仍有两个易错点：上传前本地 archive 是否符合 CI 唯一目录规则，以及上传到 GitHub Release / 触发 workflow 是否指向正确 repo。继续补这段交付闭环，比新增 report-only 探针层更接近 `v1.38-current-gap-to-koharu.md` 要求的真实 artifact 注入。

核心变更：

- `scripts/validate-koharu-artifacts.py` 新增 `--inspect-release-archive <zip|tar>`，用 CI 同口径安全解包并检查 archive 中是否恰好有一个包含四个标准 JSON 的目录，输出 archive size/SHA、members、candidate directory 和 validator verdict。
- handoff packet 新增 `--repo`、`--probe-mode` 参数，输出结构化 `releaseUpload`，并生成带 `--repo` 的 `ghReleaseUploadCommand`、`ghWorkflowDispatchCommand` 和 `ghRunListCommand`；默认不加 `--clobber`，避免误覆盖 Release asset。
- `AITRANS CI Results` 继续沿用既有 Release archive 下载、SHA 校验、唯一四件套目录解包、active validator identity / orientation 摘要和 App runtime 证据链；`--inspect-release-archive` 定位为上传前本地 preflight，不作为本轮云端 manifest 新字段。
- CI static checks 保留 package smoke 和 handoff 命令 repo / quote 检查；archive inspect 的 0 / 多 candidate 失败路径由本地轻量验证覆盖，避免在 workflow 内增加容易破坏 GitHub job 启动的复杂脚本块。
- artifact contract README 和测试规范同步 upload / inspect / dispatch / run list 的交付步骤和验收口径。

关键文件：

- `scripts/validate-koharu-artifacts.py`
- `.github/workflows/ci-results.yml`
- `md/koharu研究/artifact_contract/README.md`
- `md/test/test.md`
- `update_log.md`

验证结果：

- 初次提交 `b0c643e` 的 `AITRANS CI Results` run `28855767837` 未能创建 job；后续修复移除 workflow 内 release archive inspection 注入、manifest 和 failure summary 钩子，只保留本地 validator / handoff 能力。
- 本地轻量验证通过：`git diff --check`、`python3 -B -m py_compile scripts/validate-koharu-artifacts.py`、workflow YAML parse、JSON parse、Koharu valid / orientation / invalid fixture 矩阵、`test/koharu_artifacts --allow-missing`、handoff packet、package 拒绝 / 成功 zip 布局、`--inspect-release-archive` 成功 / 空 archive / 双 candidate archive 失败路径、active-like handoff ready smoke。
- 云端结果包待本修复 commit push 后确认：本版本只改 Python validator、workflow static checks 和文档，预期 push CI 走 build-skip；workflow / validator 变化会触发 extended Koharu validator matrix 和 package smoke。

遗留事项：

- 本版本仍不生成真实 Koharu 四件套、不上传 Release、不触发手动 `ci-fast/full`，不改变 OCR / LLM / renderer / 漫画指标，不追加 `metrics/version_history.csv`。
- 真实验收仍必须由人工提供外部 detector 输出，运行 package / inspect / upload / dispatch 命令后，核对云端 App runtime readiness、identity reconciliation、external shadow OCR coverage 和 orientation gates。

### v1.81：Koharu Release Handoff Packet Preflight
日期：2026-07-07

依据：`md/koharu研究/v1.38-current-gap-to-koharu.md` 已明确当前下一步仍是 P0：拿真实 `TextBoxes / BubbleMask / SegmentMask` 四件套，通过 Release archive 注入手动 `ci-fast/full`，看 App runtime readiness、identity reconciliation、external shadow OCR coverage 和 orientation gates。v1.79-v1.80 已收紧 source image SHA contract，但外部 detector 输出到 GitHub Release / workflow_dispatch 的交付路径仍需要人工拼 zip、算 SHA、填参数，容易错包或漏填。

核心变更：

- `scripts/validate-koharu-artifacts.py` 新增 `--emit-handoff-packet`，在 validator 摘要外输出 Release upload / `workflow_dispatch` handoff 清单，包含 source image SHA、四件套 size/SHA、orientation summary、建议的 `probe_mode=ci-fast`、`koharu_artifact_release_tag`、`koharu_artifact_asset`、`koharu_artifact_sha256`、`koharu_artifact_required=true` 和 `gh workflow run` 模板。
- 新增 `--package-release-archive <zip>`，把当前 root 下解析出的四件套打成一个 zip；zip 内只包含一个目录和四个标准 JSON，贴合 CI 的唯一目录检查。
- 打包默认只接受 `verdict = readyForShadowOCR`；`contractExampleOnly` examples 不会被标记为 handoff ready，`--allow-fixture-package` 仅用于本地 smoke。
- handoff packet 区分当前离线 root 的 `externalTextBoxesShadowOCRAllowed` 与 CI 注入 active 目录后的 expected readiness，避免把非 active 路径误读成 App 已消费 artifact。
- 打包路径增加源文件覆盖保护，`ghWorkflowDispatchCommand` 对 tag / asset / SHA 参数做 shell quote。
- `AITRANS CI Results` static checks 增加 package smoke：验证 `contractExampleOnly` fixture 默认拒绝打包、`--allow-fixture-package` 生成单目录四标准 JSON，并检查带空格 dispatch 参数 quote。
- artifact contract README 和测试规范同步新的 preflight / package 命令与 CI package smoke 预期。

关键文件：

- `scripts/validate-koharu-artifacts.py`
- `.github/workflows/ci-results.yml`
- `md/koharu研究/artifact_contract/README.md`
- `md/test/test.md`
- `update_log.md`

验证结果：

- 本地轻量验证通过：`git diff --check`、`python3 -m py_compile scripts/validate-koharu-artifacts.py`、workflow YAML parse、JSON parse、Koharu valid / orientation / invalid fixture 矩阵、`test/koharu_artifacts --allow-missing`、handoff packet、package 拒绝 / 成功 zip 布局和 quote smoke。
- 云端 `AITRANS CI Results` run `28854050132` 通过，artifact `aitrans-ci-unversioned-smalldata_test--54a94b6e992f-run28854050132-attempt1` 已核对：`branch = smalldata_test`、`commitSha = 54a94b6e992f06d5e7d1704d1634d87aca3dffb6`、`xcodeBuildRequired = false`、`xcodeBuildSkippedReason = non_app_build_related_fast_path`、`probeMode = skip`、`scopeDiffMethod = checkout_before`、`scopeDiffFallbackUsed = false`、`koharuValidatorExtendedRequired = true`、`probeOutputRetainedFiles = ["probe-not-run.txt"]`，package fixture smoke 产物存在且 verdict 为 `contractExampleOnly`。
- 同轮 `AITRANS - Build IPA` run `28854050100` 通过。

遗留事项：

- 本版本不生成真实 Koharu 四件套，不上传 Release，不触发手动 `ci-fast/full`，不改变 OCR / LLM / renderer / 漫画指标，不追加 `metrics/version_history.csv`。
- 真实验收仍必须由人工提供外部 detector 输出，运行 handoff packet 生成 zip，上传 Release 后手动 dispatch，并核对云端 App runtime 证据。

### v1.80：App Runtime Source Image SHA Gate
日期：2026-07-07

依据：v1.79 已让 Python validator / CI static smoke 要求 Koharu active manifest 声明 `sourceImageSHA256` 并匹配当前仓库 `test/1.png`，但 Swift App runtime readiness 仍主要核对 source image 路径和 App 可见文件 size / SHA256。如果外部 artifact manifest 在 App 探针内缺失、格式错误或声明了旧图 SHA，必须由 App 侧 readiness、identity receipt、contract dry-run 和 identity reconciliation 同步阻塞，避免 validator 与 runtime handoff 口径分叉。

核心变更：

- `MangaOverlayExternalArtifactManifest` 解析 `sourceImageSHA256`，并记录字段存在性、类型有效性和标准化 SHA。
- `externalArtifactReadinessReport.coordinateValidation` 新增 declared / expected / fieldPresent / typeValid / matches 字段；Swift readiness 现在对缺失、非 64 位 hex 或不匹配 runtime bundle `test/1.png` SHA 的 manifest 输出 `sourceImageSHA256Missing` / `sourceImageSHA256Invalid` / `sourceImageSHA256Mismatch`，并阻止 `readyForShadowOCR`。
- `externalArtifactReadinessReport.artifactIdentityReceipt` 新增 `sourceImageSHA256Declared`、`sourceImageSHA256Expected`、`sourceImageSHA256Matches`；`identityVerdict = activeArtifactIdentityRecorded` 现在要求 manifest SHA 与 App runtime 可见 source image SHA 匹配。
- `koharuNativeArtifactContractDryRunReport` 的 manifest required fields 增加 `sourceImageSHA256=<expected>`，App-side identity gate 也消费 `sourceImageSHA256Matches`。
- `koharuArtifactIdentityReconciliationReport` 顶层新增 declared / expected / matches，`readyForCIManifestComparison` 只有在 source image SHA match 为 true 时才能通过。
- `1_ocr_probe_text.txt` 摘要、CI post-export smoke、`ci-artifact-manifest.json` 的 App receipt / identity reconciliation summaries 和 failure summary 都透传 App runtime source image SHA declared / expected / matches。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `.github/workflows/ci-results.yml`
- `README.md`
- `md/test/test.md`
- `update_log.md`

验证结果：

- 本地轻量验证通过：`git diff --check`、JSON 解析、workflow YAML parse、workflow Python heredoc 编译、Koharu validator valid / invalid fixture 矩阵。
- 云端 `AITRANS CI Results` run `28851345305` 通过，artifact `aitrans-ci-unversioned-smalldata_test--5668ab847c01-run28851345305-attempt1` 已核对：`branch = smalldata_test`、`commitSha = 5668ab847c0148201e26010a95de2a92306a92a4`、`xcodeBuildRequired = true`、`xcode build = success`、`probeMode = skip`、`scopeDiffMethod = checkout_before`、`scopeDiffFallbackUsed = false`、`changedFiles = ["AITRANS/Models/TranscriptModels.swift"]`。
- 同轮 `AITRANS - Build IPA` archive 编译阶段已成功，但上传 archive log 时 GitHub artifact service 多次 timeout，属于打包 artifact 上传失败，不是 Swift 编译失败。

遗留事项：

- 本版本不新增真实 Koharu 四件套，不改变 OCR / LLM / renderer / 覆盖图 / active artifact，不追加 `metrics/version_history.csv`。
- 需要真实 handoff 验收时，仍需手动 `workflow_dispatch` 选择 `ci-fast` 或 `full` 并注入 Koharu artifact archive，核对 App receipt 与 reconciliation 的 `sourceImageSHA256Matches = true`。

### v1.79：Koharu Source Image SHA Contract Gate
日期：2026-07-07

依据：v1.66-v1.78 已让 CI / App 侧记录 source image 和四件套 size / SHA256 identity，但 Koharu active manifest 仍只声明 `sourceImage = test/1.png`，没有强制声明“本 artifact 是基于当前仓库这张 `test/1.png` 生成”。如果外部 detector 用旧图、裁切图或错图导出，路径和尺寸可能看似正确，后续云端 handoff 仍有误接风险。

核心变更：

- `scripts/validate-koharu-artifacts.py` 要求 manifest 声明 `sourceImageSHA256`，并校验它必须匹配当前仓库 `test/1.png` 的实际 SHA256：`9c3dc0ee9dfc4a6b664c4b4dd32e5b74b214f6f0d16f32ef97ef02ce47c2ed21`。
- validator 输出新增 `sourceImageSHA256`、`expectedSourceImageSHA256`、`sourceImageSHA256Matches`，`artifactIdentitySummary` 新增 `sourceImageSHA256Declared`、`sourceImageSHA256Expected`、`sourceImageSHA256Matches`，并新增 `sourceImageSHA256Missing` / `sourceImageSHA256Invalid` / `sourceImageSHA256Mismatch` verdict。
- CI 注入真实 Koharu artifact 和 valid fixture smoke 都会断言 manifest 声明 SHA 与仓库 source image SHA 一致；完整 invalid fixture 矩阵新增 `source_image_sha_missing` 和 `source_image_sha_mismatch`。
- artifact contract README、`md/test/test.md` 和示例 manifests 同步新的 source image SHA contract。

关键文件：

- `scripts/validate-koharu-artifacts.py`
- `.github/workflows/ci-results.yml`
- `md/koharu研究/artifact_contract/README.md`
- `md/koharu研究/artifact_contract/examples/**/1.manifest.json`
- `md/test/test.md`
- `update_log.md`

验证结果：

- 待本轮本地轻量验证与 push 后云端结果包确认：预期 workflow / validator / contract 变更会触发 extended Koharu invalid fixture matrix，且本轮仍不涉及 Swift / Xcode 工程 / `test/` 素材，预期 `xcodeBuildRequired = false`。

遗留事项：

- 本版本不新增真实 Koharu 四件套，不改变 OCR / LLM / renderer / 漫画指标，不追加 `metrics/version_history.csv`。
- 如果未来 `test/1.png` 变更，所有 active artifact 和 contract fixtures 必须同步新的 `sourceImageSHA256`，否则 validator 应阻塞 handoff。

### v1.78：CI Scope Targeted Fetch Closure
日期：2026-07-07

依据：v1.76 用 `fetch-depth: 2` 修复了普通单提交 push 的 scope diff，但遗留事项仍指出：如果一次 push 包含多提交且 `github.event.before` 不在最近 2 个提交内，`Detect CI scope` 仍会回退 `git ls-files`，把 `changed-files.txt` 变成全仓列表，进而误触发 Xcode build 和 extended Koharu validator。v1.77 已让结果包可追溯，本轮继续把 scope diff 方法本身变成可审计证据。

核心变更：

- `Detect CI scope` 在 checkout 内找不到 `github.event.before` 时，先执行定向 `git fetch --no-tags --depth=1 origin <before>`，成功后继续按真实 before SHA diff。
- 只有 checkout 和 targeted fetch 都无法拿到 before commit 时，才回退 `git ls-files` 全仓列表。
- CI 输出、manifest 和 failure summary 新增 `scopeDiffMethod`、`scopeDiffBaseSha`、`scopeDiffFallbackUsed`，Agent C 可判断 changed-files 是否来自 `checkout_before`、`targeted_fetch` 或 `full_repo_fallback`。
- `md/test/test.md` 同步多提交 push 的 scope diff 验收口径。

关键文件：

- `.github/workflows/ci-results.yml`
- `md/test/test.md`
- `update_log.md`

验证结果：

- 待本轮本地轻量验证与 push 后云端结果包确认：普通单提交 push 预期 `scopeDiffMethod = checkout_before`、`scopeDiffFallbackUsed = false`；若后续出现多提交 push 且 before 不在浅克隆内，预期使用 `targeted_fetch` 而不是全仓 fallback。

遗留事项：

- 本版本不新增真实 Koharu 四件套，不改变 OCR / LLM / renderer / 漫画指标，不追加 `metrics/version_history.csv`。
- 若极端情况下 GitHub 不允许按 SHA 定向 fetch，workflow 仍会显式记录 `full_repo_fallback`，避免 Agent C 把全仓 changed-files 误认为精确 diff。

### v1.77：CI Artifact Provenance Self-Trace
日期：2026-07-07

依据：v1.76 已让 build-skip 结果包更干净，但 Agent C 下载未加密 artifact 后仍需要从 GitHub UI 或 `gh run view` 反查 run URL、artifact name、event/ref/repository 和变更范围。后续真实 Koharu artifact handoff 会更依赖“拿到的包就是目标 run / 目标提交 / 目标变更”的机器可核对证据，因此本轮继续增强 CI 结果包可追溯性。

核心变更：

- `ci-artifact-manifest.json` 新增 `artifactName`、`eventName`、`repository`、`ref`、`refName` 和 `runUrl`，让结果包自带 GitHub run 与 artifact identity。
- `ci-artifact-manifest.json` 新增 `changedFilesCount`、`changedFilesSHA256` 和 `changedFiles`，直接记录本轮 scope detection 的文件列表和稳定哈希。
- `ci-failure-summary.md` 同步打印 run URL、event/ref/repository、artifact name、changed files count 和 changed files SHA256，便于失败时快速定位。
- `md/test/test.md` 补充 v1.77 结果包 provenance 字段验收口径。

关键文件：

- `.github/workflows/ci-results.yml`
- `md/test/test.md`
- `update_log.md`

验证结果：

- 待本轮本地轻量验证与 push 后云端结果包确认：预期 manifest 能解析并包含 self-trace 字段；failure summary 顶部能直接看到 run URL、artifact name 和 changed-files 摘要。本轮仍是 CI / 文档变更，预期 `xcodeBuildRequired = false`。

遗留事项：

- 本版本不新增真实 Koharu 四件套，不改变 OCR / LLM / renderer / 漫画指标，不追加 `metrics/version_history.csv`。
- 若未来需要限制 manifest 体积，可保留 `changedFilesSHA256` 和 count，将完整 `changedFiles` 迁移为单独文件引用；当前普通 push 变更列表很小，直接内嵌更利于验收。

### v1.76：CI Scope Diff Accuracy / Skip Probe Artifact Hygiene
日期：2026-07-07

依据：v1.75 云端 push run `28844582258` 虽然只改 workflow 和日志，但 `changed-files.txt` 回退成全仓列表，导致 `xcodeBuildRequired = true` 并额外跑 Xcode build。原因是 `actions/checkout` 默认浅克隆只含当前提交，`Detect CI scope` 找不到 `github.event.before` 时只能回退 `git ls-files`。这会削弱非 App 改动的 build-skip 加速路径。同轮审计还发现 `probe_mode=skip` 会把仓库中已有的旧 `output/` 复制进结果包，容易让 Agent C 误读为本次云端探针产物。

核心变更：

- `AITRANS CI Results` 的 checkout 增加 `fetch-depth: 2`，让普通单提交 push 能 diff 到 `github.event.before`，避免浅克隆缺 before commit 时误判全仓变化。
- `Copy available probe outputs` 只在 `probe_mode != skip` 且 `manga_probe` 成功时复制本轮 `output/`；skip 或探针失败时只写 `output/probe-not-run.txt`，不再把 checked-in 旧 JSON / TXT / PNG 混入本次 CI artifact。
- `md/test/test.md` 补充 scope detection 和 skip probe artifact hygiene 要求，明确 build-skip 结果包不能被旧探针输出污染。

关键文件：

- `.github/workflows/ci-results.yml`
- `md/test/test.md`
- `update_log.md`

验证结果：

- 待本轮本地轻量验证与 push 后云端结果包确认：预期本次仅 workflow / 文档变更时 `xcodeBuildRequired = false`，`xcodeBuildSkippedReason = non_app_build_related_fast_path`，`changed-files.txt` 只列本次变更文件；`probeMode = skip` 时 `probeReportPath` 为空，`probeOutputRetainedFiles = ["probe-not-run.txt"]`。

遗留事项：

- `fetch-depth: 2` 覆盖普通单提交 push；若后续一次 push 包含多提交且 `before` 不在最近 2 个提交内，仍可能回退全仓列表。需要时再升级为按 SHA 定向 fetch，而不是直接全量 checkout。
- 本版本不新增真实 Koharu 四件套，不改变 OCR / LLM / renderer / 漫画指标，不追加 `metrics/version_history.csv`。

### v1.75：CI Manifest Step Split / Workflow Startup Fix
日期：2026-07-07

依据：v1.74 把 native-lite manifest 摘要直接塞进 `Write manifest`，使该 GitHub Actions 单步脚本从上一版约 20k 字符增长到约 26k 字符。最新 push 的 `AITRANS CI Results` run `28844255398` 在 0 秒失败且没有 job/log，`gh run view` 明确提示 workflow file issue；这符合单步 `run:` 脚本过大导致 workflow 启动前被拒绝的风险。

核心变更：

- `AITRANS CI Results` 保留 v1.74 的 `koharuNativeLiteReportSummary` 与 `koharuNativeLiteConvergenceGateSummary` manifest 字段，但改由独立 `Append native-lite manifest summary` step 读取已生成的 `ci-artifact-manifest.json` 和可用 `probe_report.json` 后追加。
- `Write manifest` step 恢复到上一轮成功版本的脚本体积，避免继续触发 workflow 启动阶段失败；native-lite 追加 step 在 `probe_mode=skip` 时仍写出字段，值来自空 probe summary，便于 Agent C 看到字段存在。
- 产物结构、字段名、probe 路径、Swift 逻辑、OCR / LLM / renderer 和 active artifact gate 不变。

关键文件：

- `.github/workflows/ci-results.yml`
- `update_log.md`

验证结果：

- 本地轻量验证通过：`git diff --check`、`.github/workflows/ci-results.yml` YAML parse、workflow Python heredoc 语法编译、`python3 -m json.tool` 解析 `test/1.ground_truth.json` / `output/probe_report.json` / `output/clean_text_diagnostic.json`。
- 拆分后 workflow 单步脚本体积：`Write manifest = 20176 chars`，`Append native-lite manifest summary = 5996 chars`。

遗留事项：

- 需要 push 后重新触发 `AITRANS CI Results`，下载结果包确认 manifest 字段存在且本次 run 不再 0 秒失败。
- 本版本不新增真实 Koharu 四件套，不改变漫画质量指标，不追加 `metrics/version_history.csv`。

### v1.74：Native-Lite CI Summary / Gap Roadmap Refresh
日期：2026-07-07

依据：v1.39-v1.46 的 detector-lite、shadow OCR、refinement、closed-loop、BubbleMask instance-lite、SegmentMask refinement-lite、bundle-lite 和 promotion gate-lite 已进入 Swift 报告与 convergence，但云端 `ci-artifact-manifest.json` / `ci-failure-summary.md` 仍主要汇总 external artifact handoff、contract dry-run、identity 和 external shadow OCR。Agent C 若要判断 native-lite 阻塞，仍需深挖完整 `probe_report.json`；同时 `md/koharu研究/v1.38-current-gap-to-koharu.md` 的推荐路线仍把部分已完成 report-only 层写成未来任务。

核心变更：

- `AITRANS CI Results` manifest 新增 `koharuNativeLiteReportSummary`，直接汇总 v1.39-v1.46 native-lite report 的 verdict、关键 count、TextBox -> SegmentMask linkage breakdown、needs-real-artifact blocks 和 promotion preview 状态。
- manifest 新增 `koharuNativeLiteConvergenceGateSummary`，直接摘出 detector-lite、shadow OCR、refinement、closed-loop、BubbleMask instance-lite、SegmentMask refinement-lite、bundle-lite、promotion gate-lite 及 linkage work item / gate 的 status、blocks、nextAction 和 decision signals。
- `ci-failure-summary.md` 的 Koharu artifact gate 区块新增 native-lite report / convergence gate 摘要，方便 Agent C 在失败摘要里直接看到 native-lite 阻塞位置。
- `ci-fast/full` smoke 扩展 `1_ocr_probe_text.txt` needles，要求 native-lite report summary 存在，防止 TXT 快照悄悄丢失 v1.39-v1.46 证据。
- `md/koharu研究/v1.38-current-gap-to-koharu.md` 标注原推荐版本路线为历史判断，说明 v1.39-v1.46 已以 report-only / proxy 形式完成；当前下一步仍是注入真实四件套跑 `ci-fast/full`，不是重复实现同名 detector-lite / promotion gate。
- README 与测试规范同步 v1.74 manifest 字段和验收口径。

关键文件：

- `.github/workflows/ci-results.yml`
- `README.md`
- `md/test/test.md`
- `md/koharu研究/v1.38-current-gap-to-koharu.md`
- `update_log.md`

验证结果：

- 本地轻量验证通过：`git diff --check`、`.github/workflows/ci-results.yml` YAML parse、workflow 内 11 个 Python heredoc 语法编译、`python3 -m json.tool` 解析 `test/1.ground_truth.json` / `output/probe_report.json` / `output/clean_text_diagnostic.json`、基于云端 `ci-fast` run `28842227463` artifact 的 native-lite manifest summary helper 离线 smoke。

遗留事项：

- 本版本不新增 detector、OCR、LLM、PNG、renderer 或 active Koharu artifact，不改变主 OCR、翻译、覆盖图、report-only 账本语义或漫画质量指标，不追加 `metrics/version_history.csv`。
- 缺真实 `test/koharu_artifacts/` 时，native-lite 仍是 proxy / report-only；真实收益仍必须等外部四件套注入后看 external shadow OCR、orientation 和 identity handoff。

### v1.73：Cloud ci-fast Evidence / Swift Warning Cleanup
日期：2026-07-07

依据：v1.72 新增 CI manifest 的 Koharu contract dry-run 与 convergence gate summary 后，需要用真实云端 `ci-fast` 探针确认这些字段在非 skip 路径可用；同一轮 Xcode 日志显示 4 处 Swift unused-value warning，虽不影响构建，但会增加后续 Agent C 读日志噪声。

核心变更：

- 云端手动 `ci-fast` run `28842227463` 已验证 commit `599443891e780155ba62773a6e1bdc7090b3ee6c` 的未加密 CI 结果包可用：GGUF 下载 / SHA 校验、静态检查、Xcode build、模拟器 build、漫画探针和 artifact 上传均成功。
- 结果包 `aitrans-ci-unversioned-smalldata_test--599443891e78-run28842227463-attempt1` 的 manifest 匹配 `branch = smalldata_test`、`runAttempt = 1`、`workflowName = AITRANS CI Results`、`probeMode = ci-fast`、`mangaProbeOutcome = success`；`junit.xml` 为 5 tests / 0 failures，并包含 `.xcresult`、`probe_report.json`、`clean_text_diagnostic.json`、`1_ocr_probe_text.txt` 和核心 PNG。
- 真实探针路径已填充 `koharuNativeArtifactContractDryRunSummary` 与 `koharuArtifactConvergenceGateSummary`；缺 active artifact 时 contract dry-run 正确为 `blockedByMissingActiveArtifacts`，coverage / orientation gate 保持 open / not evaluated，`G-ci-fast-report-availability` 为 passed 且 `requiredReportSpan = v1.24-v1.70`。
- 清理 `MangaOverlayProbeService` 与 `TranslationSessionStore` 中不参与逻辑的 unused-value 绑定，减少 Xcode build 日志噪声，不改变主 OCR、翻译、覆盖图、report-only 账本或 active artifact gate。

关键文件：

- `AITRANS/Services/MangaOverlayProbeService.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `update_log.md`

验证结果：

- 云端 `ci-fast` 探针：run `28842227463` 成功，`engineUsed = Local GGUF`、`decodingMode = deterministic`、`totalBlocksDetected = 13`、`passedBlocks = 1`、`failedBlocks = 12`、clean text `5 / 11` 通过，缺 active artifact 的 external shadow OCR 正确阻塞在 `manifestMissing`。

遗留事项：

- 本版本不新增 detector、OCR、LLM、PNG、renderer 或 active Koharu artifact，不改变漫画质量指标，不追加 `metrics/version_history.csv`。
- 缺真实 `test/koharu_artifacts/` 时，external TextBox shadow OCR / orientation path 仍只能验证阻塞和报告完整性；真实 artifact handoff 仍需后续注入四件套后再跑 `ci-fast` / `full`。

### v1.72：CI Artifact Convergence Gate Summary Closure
日期：2026-07-07

依据：v1.70-v1.71 已要求 Agent C 核对 coverage / orientation convergence gate、contract dry-run 和 App-side identity，但 `ci-artifact-manifest.json` 与 `ci-failure-summary.md` 仍主要打印 validator / readiness / shadow OCR 原始摘要，Agent C 需要深挖 `probe_report.json` 才能看到 work item / gate status、blocks 和 `G-ci-fast-report-availability` decision signals。

核心变更：

- `AITRANS CI Results` manifest 新增 `koharuNativeArtifactContractDryRunSummary` 和 `koharuArtifactConvergenceGateSummary`，直接汇总 contract dry-run、App-side identity、coverage / orientation work item 与 gate、identity reconciliation gate、`G-ci-fast-report-availability` 的 decision signals。
- artifact-requested smoke 新增 `G-ci-fast-report-availability.requiredReportSpan = v1.24-v1.70`、`missingReportCount`、`missingReports` 断言，并扩展 TXT needles，确保 coverage / orientation / OCR success / App-side identity 摘要存在。
- `ci-failure-summary.md` 的 Koharu artifact gate 区块补充 external shadow OCR counts、contract dry-run safety、coverage / orientation convergence work item / gate 状态和 report availability signals，降低 Agent C 找错包或漏看 blocker 的概率。
- README、flow、测试规范同步 build-skip 快路径口径：只有 `xcodeBuildRequired=true` 时 `.xcresult` 是必需编译证据，build-skip 必须看 manifest skip reason。

关键文件：

- `.github/workflows/ci-results.yml`
- `README.md`
- `md/flow/flow.md`
- `md/test/test.md`
- `md/koharu研究/v1.38-current-gap-to-koharu.md`
- `update_log.md`

验证结果：

- 本地轻量验证通过：`git diff --check`、`.github/workflows/ci-results.yml` YAML parse、workflow 内 6 个 Python heredoc 语法编译、`python3 -m json.tool` 解析 `test/1.ground_truth.json` / `output/probe_report.json` / `output/clean_text_diagnostic.json`、Koharu validator allow-missing、`contract_example_only_invalid --expect-fail`、新增 manifest summary helper 离线 smoke。

遗留事项：

- 该版本不新增 detector、OCR、LLM、PNG、renderer 或 active Koharu artifact；未重新跑完整漫画探针，不改变漫画质量指标，不追加 `metrics/version_history.csv`。

### v1.71：Convergence Dependency Span / CI Handoff Documentation Closure
日期：2026-07-07

依据：v1.70 已完成 App/CI artifact handoff strict closure 并通过云端 push 快验，但 `koharuArtifactConvergenceReport`、测试规范和 artifact contract README 仍有少量 v1.68 / v1.69 口径残留，容易让后续 Agent C 按旧 dependency span 或 validator-only preflight 验收。

核心变更：

- `G-ci-fast-report-availability` 的 threshold、`requiredReportSpan` 和 notes 从 `v1.24-v1.68` 更新为 `v1.24-v1.70`，纳入 shadow OCR coverage closure 与 App/CI handoff strict closure。
- `README.md`、`md/flow/flow.md`、`md/test/test.md` 明确：填写 Koharu artifact archive 时必须跑 `ci-fast` 或 `full`，不能用 `probe_mode=skip`；coverage / orientation work item 与 gate ID、status、TXT 摘要和 App-side identity 都是验收证据。
- `md/koharu研究/artifact_contract/README.md` 将旧 v1.15 清单改成 v1.70+ active artifact / validator preflight 清单，并明确 validator 通过不等于 Agent C 可验收，云端闭环还必须核对 contract dry-run、identity reconciliation、shadow OCR coverage 和 orientation blockers。
- `md/koharu研究/v1.38-current-gap-to-koharu.md` 补 v1.70 云端 run 证据和 v1.71 后补充。

关键文件：

- `AITRANS/Services/TranslationSessionStore.swift`
- `README.md`
- `md/flow/flow.md`
- `md/test/test.md`
- `md/koharu研究/artifact_contract/README.md`
- `md/koharu研究/v1.38-current-gap-to-koharu.md`
- `update_log.md`

验证结果：

- 本地轻量验证通过：`git diff --check`、`python3 -m json.tool test/1.ground_truth.json`、`python3 -m json.tool output/probe_report.json`、`python3 -m json.tool output/clean_text_diagnostic.json`、`swiftc -parse $(rg --files AITRANS -g '*.swift')`、`scripts/validate-koharu-artifacts.py --root test/koharu_artifacts --allow-missing`、valid fixture validator、`contract_example_only_invalid --expect-fail`。

遗留事项：

- 该版本不新增 detector、OCR、LLM、PNG、renderer 或 active Koharu artifact；未重新跑完整漫画探针，不改变漫画质量指标，不追加 `metrics/version_history.csv`。

### v1.70：Koharu Artifact App / CI Handoff Strict Closure
日期：2026-07-07

依据：v1.69 已把 validator manifest 显式字段和 external shadow OCR coverage gate 收紧，但 App 侧仍需要显式保留 manifest 字段缺失 / 类型错误证据；CI smoke 也需要核对 `ocrSucceededCount`、coverage / orientation work item 与 gate ID；同时 “填写 Koharu artifact archive 但 `probe_mode=skip`” 会导致只验证下载和 validator，不能证明 App 实际消费 artifact。

核心变更：

- `MangaOverlayExternalArtifactManifest` 新增 `sourceImageFieldPresent`、`sourceImageTypeValid`、`contractExampleOnlyFieldPresent`、`contractExampleOnlyTypeValid`，让 Swift readiness 能区分缺字段、类型错误和真实值。
- `externalArtifactReadinessReport` / `externalArtifactIdentityReceipt` / nextAction 新增 `sourceImageMissing`、`contractExampleOnlyMissing`、`contractExampleOnlyInvalid` 分支；ready artifact 的 orientation gate 未闭合时从 warning 收紧为 blocked。
- `1_ocr_probe_text.txt` 的 external TextBox shadow OCR 行补出 `ocrSucceeded`，convergence 摘要补出 coverage / orientation work item status、gate status 和 gate blocks。
- GitHub Actions extended validator matrix 新增 `contract_example_only_invalid`；artifact requested 的探针 smoke 硬核对 `ocrSucceededCount > 0`、coverage / orientation work item 与 gate ID、coverage gate passed，以及 orientation gate 不得在仍有 blockers 时 passed。
- CI metadata 禁止 Koharu artifact archive 与 `probe_mode=skip` 组合；真实四件套注入必须用 `ci-fast` 或 `full` 产生 App 侧证据。
- 同步更新 Koharu contract README、流程文档、流程图和测试规范；新增 invalid fixture `contract_example_only_invalid`。

关键文件：

- `.github/workflows/ci-results.yml`
- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `md/koharu研究/v1.38-current-gap-to-koharu.md`
- `md/koharu研究/artifact_contract/README.md`
- `md/koharu研究/artifact_contract/examples/invalid/contract_example_only_invalid/*`
- `update_log.md`

验证结果：

- 本地轻量验证通过：`git diff --check`、YAML smoke、JSON 解析、Swift `swiftc -parse`、Koharu validator matrix。
- 云端 push 快验通过：commit `6b53da9bb3005afbc9bc4bd5d1a8d05e06ca37cf`；`AITRANS CI Results` run `28840108595` 成功，manifest 匹配 `branch = smalldata_test`、`commitSha = 6b53da9bb3005afbc9bc4bd5d1a8d05e06ca37cf`、`xcodeBuildRequired = true`、`xcodeBuildOutcome = success`、`.xcresult` 存在，JUnit `5` tests / `0` failures，默认 push `probeMode = skip`、`mangaProbeOutcome = skipped`，extended validator required 并正确拒绝 `contract_example_only_invalid`。
- 云端打包通过：`Build IPA` run `28840108614` 成功。
- 未跑本机 Xcode build / 模拟器漫画探针；按规则交给 GitHub Actions build 和手动 `ci-fast` / `full` 探针验证。

遗留事项：

- 该版本不提供真实 Koharu artifact，也不创建 active `test/koharu_artifacts/`；缺真实 artifact 时仍只输出 readiness blocked / identity missing。
- 该版本不新增 detector、OCR、LLM、PNG 或 renderer 算法，不改变主 OCR、`finalTextUsedForTranslation`、翻译、覆盖图、`blockPassed`、active artifact 或 `configuration.currentBlockSource`。
- 未重新跑完整探针，不改变漫画质量指标，不追加 `metrics/version_history.csv`。

### v1.69：External Artifact Validator / Shadow OCR Coverage Closure Gate
日期：2026-07-07

依据：v1.65-v1.68 已把真实 Koharu artifact 的 validator identity、App-side receipt、identity reconciliation 和 external shadow OCR coverage 接进 CI / convergence，但仍有两个闭环风险：一是 validator 对 active manifest 缺 `sourceImage` 或缺 `contractExampleOnly` 会走默认值，可能放宽真实 artifact 准入；二是 convergence 的 external shadow OCR coverage 只要求 `executed = true` 和 `candidateCount > 0`，没有把实际 crop OCR 执行数 / 成功数纳入闭合条件，且 ready artifact 未闭合时 gate status 仍是 warning。

核心变更：

- `scripts/validate-koharu-artifacts.py` 现在要求 manifest 显式声明 `sourceImage = test/1.png` 和布尔型 `contractExampleOnly`；缺失分别输出 `sourceImageMissing` / `contractExampleOnlyMissing`，非布尔 `contractExampleOnly` 输出 `contractExampleOnlyInvalid:*`，均阻止 `readyForShadowOCR`。
- 新增 invalid fixtures：`source_image_missing` 与 `contract_example_only_missing`，并接入 GitHub Actions extended Koharu validator matrix。
- `koharuArtifactConvergenceReport` 的 `WI/G-external-textbox-shadow-ocr-coverage` 在真实 artifact ready 后新增 `ocrExecutedCount > 0` 和 `ocrSucceededCount > 0` 闭合条件；未闭合时 gate status 从 warning 升为 blocked。
- `G-ci-fast-report-availability` 的 threshold / decision signals 更新为当前 v1.24-v1.68 依赖集合，并写出 `missingReportCount`、`missingReports` 和 `requiredReportSpan`，避免旧 v1.24-v1.27 文案误导 Agent C。

关键文件：

- `scripts/validate-koharu-artifacts.py`
- `.github/workflows/ci-results.yml`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AGENTS.md`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `md/koharu研究/artifact_contract/README.md`
- `md/koharu研究/artifact_contract/examples/invalid/source_image_missing/*`
- `md/koharu研究/artifact_contract/examples/invalid/contract_example_only_missing/*`
- `update_log.md`

验证结果：

- 本地轻量验证已通过；云端 commit `c1d5990df733d5593de57b4631c8e4120658dcb7` 的 `AITRANS CI Results` run `28839023072` 成功，`Build IPA` run `28839023071` 成功。默认 push 探针为 `skip`，未生成新的漫画探针报告。

未跑本机 Xcode build / 模拟器漫画探针；按规则交给 GitHub Actions build 和手动 `ci-fast` / `full` 探针验证。

遗留事项：

- 该版本不提供真实 Koharu artifact，也不创建 active `test/koharu_artifacts/`；缺真实 artifact 时仍只输出 readiness blocked / identity missing。
- 该版本不新增 OCR / LLM / PNG，不改变主 OCR、`finalTextUsedForTranslation`、翻译、覆盖图、`blockPassed`、active artifact 或 `configuration.currentBlockSource`。
- 未重新跑完整探针，不改变漫画质量指标，不追加 `metrics/version_history.csv`。

### v1.68：Koharu Artifact Identity Reconciliation Gate
日期：2026-07-06

依据：v1.67 已把 App 探针 runtime 可见的 source image 与四件套 size / SHA256 写入 `artifactIdentityReceipt`，但 Agent C 仍需要手工把这些值与 `ci-artifact-manifest.koharuArtifactValidationIdentitySummary` 对齐。真实 artifact handoff 需要一个可机器核对的对账表和 CI match verdict，防止 validator 校验的是一组文件、App 消费的是另一组文件。

核心变更：

- 新增 `koharuArtifactIdentityReconciliationReport`，把 App receipt 规范化为 SourceImage + manifest / TextBoxes / BubbleMask / SegmentMask 五行 ledger，逐行写出 App size / SHA256、receipt 状态、contract dry-run identity status，以及 CI manifest identity 的 size / SHA 字段路径。
- `koharuArtifactConvergenceReport` 新增 `WI-koharu-artifact-identity-reconciliation` / `G-koharu-artifact-identity-reconciliation-ready`，并让 external shadow OCR coverage gate 在真实 artifact ready 后同时要求 reconciliation ready。
- GitHub Actions 在注入真实 Koharu artifact 并跑 `ci-fast/full` 后，会比较 validator identity 与 App reconciliation rows 的 size / SHA256，失败时阻断；`ci-artifact-manifest.json` 新增 App receipt summary、reconciliation summary 和 `koharuArtifactIdentityReconciliationMatch`。
- `1_ocr_probe_text.txt` 新增 reconciliation report、逐文件对账行和 convergence work item 摘要，方便 Agent C 直接核对。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `.github/workflows/ci-results.yml`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `md/koharu研究/v1.38-current-gap-to-koharu.md`
- `update_log.md`

验证结果：

- 本轮本地轻量验证见最终回复。

未跑本机 Xcode build / 模拟器漫画探针；按规则交给 GitHub Actions build 和手动 `ci-fast` / `full` 探针验证。

遗留事项：

- 该版本不提供真实 Koharu artifact，也不创建 active `test/koharu_artifacts/`；缺真实 artifact 时 reconciliation 会保持 App receipt incomplete / not ready。
- 该版本不新增 OCR / LLM / PNG，不改变主 OCR、`finalTextUsedForTranslation`、翻译、覆盖图、`blockPassed`、active artifact 或 `configuration.currentBlockSource`。
- 未重新跑完整探针，不改变漫画质量指标，不追加 `metrics/version_history.csv`。

### v1.67：App-Side Koharu Artifact Identity Receipt
日期：2026-07-06

依据：v1.66 已在 validator / CI manifest 中记录 Release archive 注入的四件套 identity，但 App 侧探针报告仍缺少运行时实际可见文件的 size / SHA256 receipt。Agent C 需要同时核对 CI manifest identity 与 `probe_report.json` 中 App runtime receipt，才能确认不是只下载 / 校验了 archive，而是 App 探针确实消费到同一组 active artifact 文件。

核心变更：

- `externalArtifactReadinessReport` 新增 `artifactIdentityReceipt`，记录 App bundle / runtime 中 `test/1.png`、manifest、TextBoxes、BubbleMask、SegmentMask 的存在性、size、SHA256、manifest schema / coordinate space / generatedBy / generatedAt / contractExampleOnly 和 `identityVerdict`。
- `koharuNativeArtifactContractDryRunReport` 新增 App 侧 identity 顶层摘要，并把每个 required file 的 `fileSizeBytes`、`sha256`、`identityStatus` 写入 dry-run file ledger；真实 artifact ready 时，contract dry-run ready 现在要求 App 侧 receipt 完整。
- `koharuArtifactConvergenceReport` 的 external shadow OCR coverage decision signals 透传 App 侧 identity verdict / files / hashes，`1_ocr_probe_text.txt` 同步打印 App 侧 identity 摘要和 required file SHA，方便 Agent C 对齐 `ci-artifact-manifest.koharuArtifactValidationIdentitySummary`。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `AGENTS.md`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `md/koharu研究/v1.38-current-gap-to-koharu.md`
- `update_log.md`

验证结果：

- 本轮本地轻量验证见最终回复。

未跑本机 Xcode build / 模拟器漫画探针；按规则交给 GitHub Actions build 和手动 `ci-fast` / `full` 探针验证。

遗留事项：

- 该版本不提供真实 Koharu artifact，也不创建 active `test/koharu_artifacts/`；缺真实 artifact 时 App 侧 receipt 会稳定记录 active 目录缺失 / required identity files missing。
- 该版本不新增 OCR / LLM / PNG，不改变主 OCR、`finalTextUsedForTranslation`、翻译、覆盖图、`blockPassed`、active artifact 或 `configuration.currentBlockSource`。
- 未重新跑完整探针，不改变漫画质量指标，不追加 `metrics/version_history.csv`。

### v1.66：Koharu Artifact Identity / Contract Dry-Run Coverage Gate
日期：2026-07-06

依据：v1.65 已把 orientation summary 和 external shadow OCR coverage gate 接进 CI / convergence，但真实 Koharu archive 注入仍缺少两个验收细节：一是 Agent C 不能快速核对 active 四件套的文件身份是否与本轮 Release archive / source image 对齐；二是 `WI/G-external-textbox-shadow-ocr-coverage` 只要求 readiness 与 shadow OCR executed / candidateCount，还没有把 contract dry-run verdict 和 dry-run 边界安全纳入同一个闭环。

核心变更：

- `scripts/validate-koharu-artifacts.py` 新增 `artifactIdentitySummary`，输出 source image、manifest、TextBoxes、BubbleMask、SegmentMask 的路径、存在性、size、SHA256，并透传 `generatedBy`、`generatedAt`、`contractExampleOnly`、schema、source image 和 coordinate space。
- GitHub Actions 注入 Koharu artifact archive 时只接受唯一一个同时包含四件套的目录，避免从多个目录各取一个 `rglob()[0]` 拼出错包；`ci-artifact-manifest.json` 透传 `koharuArtifactValidationIdentitySummary`，`ci-failure-summary.md` 打印 identity 摘要。
- `koharuArtifactConvergenceReport` 的 `WI-external-textbox-shadow-ocr-coverage` / `G-external-textbox-shadow-ocr-coverage` 在真实 artifact ready 后新增 contract dry-run 前置条件：`contractDryRunVerdict = activeArtifactsReadyForShadowOCR`、`dryRunOnly = true`、`activeExportAllowed = false`，再要求 `externalTextBoxShadowOCRReport.executed = true` 且 `candidateCount > 0`。

关键文件：

- `scripts/validate-koharu-artifacts.py`
- `.github/workflows/ci-results.yml`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AGENTS.md`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `md/koharu研究/artifact_contract/README.md`
- `md/koharu研究/v1.38-current-gap-to-koharu.md`
- `update_log.md`

验证结果：

- 本轮本地轻量验证见最终回复。

未跑本机 Xcode build / 模拟器漫画探针；按规则交给 GitHub Actions build 和手动 `ci-fast` / `full` 探针验证。

遗留事项：

- 该版本不提供真实 Koharu artifact，也不创建 active `test/koharu_artifacts/`；缺真实 artifact 时仍只输出 readiness blocked / identity empty-or-missing / orientation summary。
- 该版本不新增 OCR / LLM / PNG，不改变主 OCR、`finalTextUsedForTranslation`、翻译、覆盖图、`blockPassed`、active artifact 或 `configuration.currentBlockSource`。
- 未重新跑完整探针，不改变漫画质量指标，不追加 `metrics/version_history.csv`。

### v1.65：External TextBox Shadow OCR Coverage / Validator Orientation Summary
日期：2026-07-06

依据：v1.64 已能防止 external TextBox orientation partial / unsupported path 被 convergence 误判为闭环，但仍有两类证据缺口：一是 validator 只校验方向元数据是否合法，没有在 CI 结果包中汇总 TextBox 的竖排、旋转、line polygon 与 unsupported 风险；二是 artifact `readyForShadowOCR` 只证明四件套可解析，不证明 App 侧 external shadow OCR 已执行并产生 block-matched candidate。

核心变更：

- `scripts/validate-koharu-artifacts.py` 新增 `orientationMetadataSummary`，汇总 sourceDirection / orientation category / rotation plan / line polygon / vertical / right-angle rotation / arbitrary rotation / unsupported reason，缺 active artifact 时也稳定输出空摘要。
- `ci-artifact-manifest.json` 新增 `koharuArtifactValidationOrientationSummary`，`ci-failure-summary.md` 的 Koharu artifact gate 区块同步打印 validator orientation 摘要，方便 Agent C 在模拟器探针前核对外部 TextBox 方向风险。
- `koharuArtifactConvergenceReport` 新增 `WI-external-textbox-shadow-ocr-coverage` / `G-external-textbox-shadow-ocr-coverage`。真实 artifact ready 后，若 `externalTextBoxShadowOCRReport` 缺失、`executed=false` 或 `candidateCount=0`，ExternalArtifacts stage 会进入 `externalShadowOCRCoverageBlocked`，orientation gate 也不会被误判为 passed / closed。
- `1_ocr_probe_text.txt` 追加 `convergenceExternalShadowOCRCoverage` 和 `convergenceExternalTextBoxOrientation` 摘要。

关键文件：

- `scripts/validate-koharu-artifacts.py`
- `.github/workflows/ci-results.yml`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `AGENTS.md`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `md/koharu研究/artifact_contract/README.md`
- `update_log.md`

验证结果：

- 本轮本地轻量验证见最终回复。

未跑本机 Xcode build / 模拟器漫画探针；按规则交给 GitHub Actions build 和手动 `ci-fast` / `full` 探针验证。

遗留事项：

- 该版本不提供真实 Koharu artifact，也不创建 active `test/koharu_artifacts/`；缺真实 artifact 时仍只输出 readiness blocked / validator empty orientation summary。
- 该版本不新增 OCR / LLM / PNG，不改变主 OCR、`finalTextUsedForTranslation`、翻译、覆盖图、`blockPassed`、active artifact 或 `configuration.currentBlockSource`。
- 未重新跑完整探针，不改变漫画质量指标，不追加 `metrics/version_history.csv`。

### v1.64：External TextBox Orientation Partial / Unsupported Convergence Gate
日期：2026-07-06

依据：v1.63 已能在真实 artifact ready 后对竖排或接近 90/180/270 度的 external TextBox 执行有上限 rotation shadow OCR，并在候选 / block summary 写出 unsupported reason。但 `koharuArtifactConvergenceReport` 仍主要消费 `orientationShadowPathNotExecutedBlocks`，存在“orientation path 已部分执行但仍因 line polygon warp 或任意角度 deskew unsupported 而未闭环，却被 convergence 看成 closed/passed”的风险。

核心变更：

- `externalTextBoxShadowOCRReport` 新增 `orientationShadowPathPartialBlocks`、`orientationUnsupportedBlocks`、`orientationUnsupportedReasonBreakdown`，把“已执行 rotation OCR 但仍有 unsupported orientation feature”的块提升到 report 级摘要。
- `orientationReadinessVerdict = orientationShadowPathExecuted` 现在要求无 not-executed blocks 且无 unsupported blocks；部分执行会保持 `orientationShadowPathPartiallyExecuted`。
- `koharuArtifactConvergenceReport` 的 ExternalArtifacts stage、`WI-external-textbox-orientation-shadow-path` 和 `G-external-textbox-orientation-shadow-path` 改为同时消费 executed / partial / notExecuted / unsupported / unsupported reason breakdown，line polygon warp 与任意角度 deskew 会继续作为 convergence blockers 暴露。
- `1_ocr_probe_text.txt` 的 external TextBox shadow OCR 汇总追加 `orientationPartial`、`orientationUnsupported` 和 `orientationUnsupportedReasons`。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `AGENTS.md`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`

验证结果：

- `swiftc -parse $(rg --files AITRANS -g '*.swift')`
- `git diff --check`
- `ruby -e 'require "yaml"; YAML.load_file(".github/workflows/ci-results.yml"); puts "yaml ok"'`
- `python3 -m json.tool test/1.ground_truth.json`
- `python3 -m json.tool output/probe_report.json`
- `python3 -m json.tool output/clean_text_diagnostic.json`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/valid`
- `python3 scripts/validate-koharu-artifacts.py --root test/koharu_artifacts --allow-missing --print-required-files`
- `python3 scripts/validate-koharu-artifacts.py --root test/koharu_artifacts --allow-missing`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/coordinate_mismatch --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/invalid_bbox --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/missing_textboxes --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/schema_mismatch --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/path_escape --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/generated_by_forbidden --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/textbox_metadata_invalid --expect-fail`

未跑本机 Xcode build / 模拟器漫画探针；按规则交给 GitHub Actions build 和手动 `ci-fast` / `full` 探针验证。

遗留事项：

- 该版本不提供真实 Koharu artifact，也不创建 active `test/koharu_artifacts/`；缺真实 artifact 时仍只输出 readiness blocked 报告。
- 该版本仍不实现 line polygon crop / warp 或任意角度 deskew，只防止这类 unsupported orientation path 被 convergence 误判为已闭环。
- 该版本不改变主 OCR、`finalTextUsedForTranslation`、翻译、覆盖图、`blockPassed` 或 active artifact，不改变漫画质量指标，不追加 `metrics/version_history.csv`。

### v1.63：External TextBox Orientation Rotation Shadow OCR
日期：2026-07-06

依据：v1.62 已把 external TextBox 的 `sourceDirection`、`linePolygons` 和 `rotationDegrees` 纳入 orientation ledger，并阻止需要 orientation-aware path 但未执行的候选进入 would-promote 预览。`md/koharu研究/v1.38-current-gap-to-koharu.md` 要求从报告堆叠转向真实 TextBox / 竖排方向 shadow path。当前可安全复用的 OCR 能力是 crop 后 0/90/180/270 旋转，不具备任意角度 deskew 或 line polygon warp。

核心变更：

- `externalTextBoxShadowOCRReport` 在真实 `test/koharu_artifacts/` readiness 通过后，对竖排 TextBox 和接近 90/180/270 度的 rotation TextBox 执行有上限的 rotation shadow OCR；竖排使用 `ja-JP/ja/en-US/en` Vision language profile。
- 候选和逐块 summary 新增 `orientationAttemptedRotations`、`orientationSelectedRotation`、`orientationRecognitionLanguages`、`orientationUnsupportedReason`，让 JSON / TXT 能证明 orientation path 是否真的执行、选了哪个旋转、以及为何仍阻塞。
- `orientationReadinessVerdict` 区分 `orientationShadowPathExecuted`、`orientationShadowPathPartiallyExecuted`、`orientationShadowPathNeededNotExecuted`；line polygon warp 和任意角度 deskew 仍以 blocker 阻止 would-promote 预览。
- `1_ocr_probe_text.txt` 的 external TextBox shadow OCR 逐块摘要和报告汇总追加 rotation / language / unsupported 证据。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`

验证结果：

- `swiftc -parse $(rg --files AITRANS -g '*.swift')`
- `git diff --check`
- `ruby -e 'require "yaml"; YAML.load_file(".github/workflows/ci-results.yml"); puts "yaml ok"'`
- `python3 -m json.tool test/1.ground_truth.json`
- `python3 -m json.tool output/probe_report.json`
- `python3 -m json.tool output/clean_text_diagnostic.json`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/valid`
- `python3 scripts/validate-koharu-artifacts.py --root test/koharu_artifacts --allow-missing --print-required-files`
- `python3 scripts/validate-koharu-artifacts.py --root test/koharu_artifacts --allow-missing`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/coordinate_mismatch --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/invalid_bbox --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/missing_textboxes --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/schema_mismatch --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/path_escape --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/generated_by_forbidden --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/textbox_metadata_invalid --expect-fail`

未跑本机 Xcode build / 模拟器漫画探针；按规则交给 GitHub Actions build 和手动 `ci-fast` / `full` 探针验证。

遗留事项：

- 该版本不提供真实 Koharu artifact，也不创建 active `test/koharu_artifacts/`；缺真实 artifact 时仍只输出 readiness blocked 报告。
- 该版本只支持 90 度倍数 rotation shadow OCR，不实现任意角度 deskew 或 line polygon crop / warp。
- 该版本不改变主 OCR、`finalTextUsedForTranslation`、翻译、覆盖图、`blockPassed` 或 active artifact，不改变漫画质量指标，不追加 `metrics/version_history.csv`。

### v1.62：External TextBox Orientation Shadow Ledger
日期：2026-07-06

依据：v1.61 已把 external TextBox 可选 `sourceDirection`、`rotationDegrees` / `rotationDeg`、`linePolygons` 纳入 validator 和 Swift readiness，但 ready 后的 `externalTextBoxShadowOCRReport` 仍只透传少量 metadata，未把“竖排 / line polygon / rotation 需要 orientation-aware shadow path，而当前未执行”作为可审计 gate。`md/koharu研究/v1.38-current-gap-to-koharu.md` 明确 line polygon 和竖排方向主路径是 AITRANS 距 Koharu 的关键差距。

核心变更：

- `MangaOverlayExternalTextBoxShadowOCRCandidate`、`BlockSummary` 和 `Report` 新增 external TextBox orientation ledger：规范化 `sourceDirection`、orientation 分类、line polygon 数量、rotation blocks、vertical blocks、orientation shadow path needed / executed / not executed blocks 和 report verdict。
- `makeExternalTextBoxShadowOCRReport` 在选择 external TextBox 后记录方向元数据；当 TextBox 声明 vertical / linePolygons / non-zero rotation 时，写入 `orientationShadowPathNeededNotExecuted` blocker，阻止其进入 `wouldPromoteByExistingGateReportOnly`。
- `koharuArtifactConvergenceReport` 新增 `WI-external-textbox-orientation-shadow-path` 和 `G-external-textbox-orientation-shadow-path`，把缺失 orientation-aware shadow OCR 路径暴露到 convergence work item / gate。
- `1_ocr_probe_text.txt` external shadow OCR 明细和汇总追加 sourceDirection、orientation、linePolygons、rotation、orientation shadow needed / executed / verdict。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`

验证结果：

- `swiftc -parse $(rg --files AITRANS -g '*.swift')`
- `git diff --check`
- `ruby -e 'require "yaml"; YAML.load_file(".github/workflows/ci-results.yml"); puts "yaml ok"'`
- `python3 -m json.tool test/1.ground_truth.json`
- `python3 -m json.tool output/probe_report.json`
- `python3 -m json.tool output/clean_text_diagnostic.json`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/valid`
- `python3 scripts/validate-koharu-artifacts.py --root test/koharu_artifacts --allow-missing --print-required-files`
- `python3 scripts/validate-koharu-artifacts.py --root test/koharu_artifacts --allow-missing`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/coordinate_mismatch --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/invalid_bbox --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/missing_textboxes --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/schema_mismatch --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/path_escape --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/generated_by_forbidden --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/textbox_metadata_invalid --expect-fail`

未跑本机 Xcode build / 模拟器漫画探针；按规则交给 GitHub Actions build 和手动 `ci-fast` / `full` 探针验证。

遗留事项：

- 该版本不执行 rotation / deskew / line polygon crop OCR，只记录 orientation shadow path 缺口并阻止 report-only promote 预览误判。
- 该版本不提供真实 Koharu artifact，也不创建 active `test/koharu_artifacts/`。
- 该版本不改变漫画质量指标，不追加 `metrics/version_history.csv`。

### v1.61：Koharu TextBox Direction Metadata Gate
日期：2026-07-06

依据：`md/koharu研究/v1.38-current-gap-to-koharu.md` 明确 AITRANS 距 Koharu 的关键差距包括真实 TextBoxes、line polygon 和竖排方向主路径。v1.60 已拦住伪造来源，但 TextBox 可选 `sourceDirection`、`rotationDegrees` / `rotationDeg`、`linePolygons` 仍主要是透传或浅校验，真实四件套即使带坏方向元数据也可能进入 App readiness。

核心变更：

- `scripts/validate-koharu-artifacts.py` 新增 TextBox 可选方向元数据校验：`sourceDirection` 必须落在 horizontal / vertical / vertical-rl / vertical-lr / unknown 等枚举内，`rotationDegrees` / `rotationDeg` 必须是有限数值且在 `[-360, 360]`，`linePolygons` 必须是非空 polygon 数组且点位在 `test/1.png` 原图范围内。
- Swift `externalArtifactReadinessReport` 使用同类校验，把 TextBox metadata 错误并入 coordinate validation，阻止离线 validator 和 App readiness 口径分叉。
- 新增 invalid fixture `md/koharu研究/artifact_contract/examples/invalid/textbox_metadata_invalid/`，并加入 CI extended validator matrix。
- artifact contract README、README、flow 和 test 文档同步说明：方向/旋转/line polygon 仍是可选字段，但提供时必须有效，供后续竖排 / line polygon shadow path 使用。

关键文件：

- `scripts/validate-koharu-artifacts.py`
- `AITRANS/Services/TranslationSessionStore.swift`
- `.github/workflows/ci-results.yml`
- `md/koharu研究/artifact_contract/examples/invalid/textbox_metadata_invalid/`
- `md/koharu研究/artifact_contract/README.md`
- `README.md`
- `md/flow/flow.md`
- `md/test/test.md`
- `update_log.md`

验证结果：

- `ruby -e 'require "yaml"; YAML.load_file(".github/workflows/ci-results.yml"); puts "yaml ok"'`
- `git diff --check`
- `swiftc -parse $(rg --files AITRANS -g '*.swift')`
- `python3 -m py_compile scripts/validate-koharu-artifacts.py`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/valid`
- `python3 scripts/validate-koharu-artifacts.py --root test/koharu_artifacts --allow-missing --print-required-files`
- `python3 scripts/validate-koharu-artifacts.py --root test/koharu_artifacts --allow-missing`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/coordinate_mismatch --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/invalid_bbox --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/missing_textboxes --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/schema_mismatch --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/path_escape --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/generated_by_forbidden --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/textbox_metadata_invalid --expect-fail`

未跑本机 Xcode build / 模拟器漫画探针；按规则交给 GitHub Actions build 和手动 `ci-fast` / `full` 探针验证。

遗留事项：

- 该版本不提供真实 Koharu artifact，也不创建 active `test/koharu_artifacts/`；只加强真实四件套方向元数据准入。
- 该版本不执行 rotation / deskew / line polygon crop OCR；下一步可在 `externalTextBoxShadowOCRReport` 中做 report-only vertical / line polygon shadow path。
- 该版本不改变漫画质量指标，不追加 `metrics/version_history.csv`。

### CI 维护：Build IPA archive artifact handoff
日期：2026-07-06

依据：`AITRANS - Build IPA` workflow 在 `Build using xcodebuild` job 已成功归档并上传 xcarchive，但 `Fakesign and package IPA` job 固定下载 `archive.xcarchive.tar.zip`，当 `IPA_PASSWORD` 为空或 secret 不可用导致上游实际上传 `archive.xcarchive.tar` 时，下游会报 `Artifact not found for name: archive.xcarchive.tar.zip`。

核心变更：

- `.github/workflows/build.yml` 将上游实际生成的 xcarchive artifact 文件名写入 step output，并作为 build job output 传给 package job。
- `Download xcarchive` 不再固定下载 `.zip`，而是使用 `needs.build.outputs.archive_artifact`。
- `Extract xcarchive` 同时支持 `.tar.zip` 和 `.tar`，保持有密码和无密码两种打包路径。

关键文件：

- `.github/workflows/build.yml`
- `update_log.md`

验证结果：

- `ruby -e 'require "yaml"; YAML.load_file(".github/workflows/build.yml"); puts "yaml ok"'`
- `git diff --check`

未跑本机 Xcode build / 模拟器漫画探针；该维护只修 GitHub Actions 打包 artifact 交接，按规则交给云端 workflow 验证。

遗留事项：

- 该维护项不改变未加密 `AITRANS CI Results` 验收口径，不改变漫画探针质量，不追加 `metrics/version_history.csv`。

### v1.60：Koharu Artifact GeneratedBy Source Policy Gate
日期：2026-07-06

依据：`md/koharu研究/v1.38-current-gap-to-koharu.md` 明确 P0 是真实 Koharu artifact 输入。v1.59 已强化注入后 App 侧消费证明，但 active package 仍需要防止“格式正确、来源却是 manual / fixture / Vision OCR / proxy / ground truth”的四件套通过到 shadow OCR。

核心变更：

- `scripts/validate-koharu-artifacts.py` 新增 active manifest `generatedBy` source policy：`contractExampleOnly=false` 时必须声明真实 detector / segmenter 来源；缺失返回 `generatedByMissing`，命中 `manual`、`fixture`、`Vision OCR`、`pre-crop`、`line plan`、`BubbleMask proxy`、`SegmentMask proxy`、`ground truth`、`handwritten` 等禁用来源词返回 `forbiddenGeneratedBy`。
- Swift `externalArtifactReadinessReport` 使用同一 source policy，把 `generatedByMissing` / `forbiddenGeneratedBy` 阻塞在 `readyForShadowOCR` 之前，并给出 `stopUntilRealDetectorSourceDeclared`。
- 新增 invalid fixture `md/koharu研究/artifact_contract/examples/invalid/generated_by_forbidden/`，并加入 CI extended validator matrix。
- `README.md`、`md/flow/flow.md`、`md/test/test.md` 和 artifact contract README 同步说明：Agent C 验收真实四件套时必须核对 `generatedBy` 不是禁用来源。

关键文件：

- `scripts/validate-koharu-artifacts.py`
- `AITRANS/Services/TranslationSessionStore.swift`
- `.github/workflows/ci-results.yml`
- `md/koharu研究/artifact_contract/examples/invalid/generated_by_forbidden/`
- `README.md`
- `md/flow/flow.md`
- `md/test/test.md`
- `md/koharu研究/artifact_contract/README.md`
- `update_log.md`

验证结果：

- `ruby -e 'require "yaml"; YAML.load_file(".github/workflows/ci-results.yml"); puts "yaml ok"'`
- `git diff --check`
- `swiftc -parse $(rg --files AITRANS -g '*.swift')`
- `python3 -m json.tool test/1.ground_truth.json`
- `python3 -m json.tool output/probe_report.json`
- `python3 -m json.tool output/clean_text_diagnostic.json`
- `python3 -m py_compile scripts/validate-koharu-artifacts.py`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/valid`
- `python3 scripts/validate-koharu-artifacts.py --root test/koharu_artifacts --allow-missing --print-required-files`
- `python3 scripts/validate-koharu-artifacts.py --root test/koharu_artifacts --allow-missing`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/coordinate_mismatch --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/invalid_bbox --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/missing_textboxes --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/schema_mismatch --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/path_escape --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/generated_by_forbidden --expect-fail`

未跑本机 Xcode build / 模拟器漫画探针；按规则交给 GitHub Actions build 和手动 `ci-fast` / `full` 探针验证。

遗留事项：

- 该版本不提供真实 Koharu artifact，也不创建 active `test/koharu_artifacts/`；只加强真实四件套来源准入。
- 该版本不改变漫画质量指标，不追加 `metrics/version_history.csv`。

### CI 维护：push 快验范围检测与 validator 精简
日期：2026-07-06

依据：人工要求精简当前测试，让云端 CI 加速，避免每次非 App 构建相关调整都跑完整 Xcode build 或完整 artifact invalid fixture 矩阵。

核心变更：

- `AITRANS CI Results` 新增变更范围检测：非 App 构建相关 push 可跳过 Xcode build，结果包保留 `xcodebuild.log` skip 说明，并在 manifest 写入 `xcodeBuildRequired`、`xcodeBuildSkippedReason`、`changedFilesPath`。
- Swift、Xcode 工程、`build-apple/`、资源、`test/` 素材、手动 `ci-fast/full` 或 Koharu artifact 注入仍强制 Xcode build。
- Xcode build 步骤增加 20 分钟上限，启用 `COMPILER_INDEX_STORE_ENABLE=NO` 并使用 quiet build log，减少默认云端耗时和日志体积。
- Koharu artifact validator 完整 invalid fixture 矩阵只在 validator、artifact contract 或 workflow 相关文件变化时运行；普通 push 只跑 valid example、active allow-missing 和 required-files 核心校验。
- `AGENTS.md`、`README.md`、`md/flow/flow.md`、`md/flow/flowchart.md`、`md/test/test.md` 同步新 CI 口径；非 App 构建相关 build-skip 不能当作 Swift/Xcode 编译证据。

关键文件：

- `.github/workflows/ci-results.yml`
- `AGENTS.md`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`

验证结果：

- `ruby -e 'require "yaml"; YAML.load_file(".github/workflows/ci-results.yml"); puts "yaml ok"'`
- `git diff --check`
- `python3 -m json.tool test/1.ground_truth.json`
- `python3 -m json.tool output/probe_report.json`
- `python3 -m json.tool output/clean_text_diagnostic.json`
- `python3 -m py_compile scripts/validate-koharu-artifacts.py`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/valid`
- `python3 scripts/validate-koharu-artifacts.py --root test/koharu_artifacts --allow-missing --print-required-files`
- `python3 scripts/validate-koharu-artifacts.py --root test/koharu_artifacts --allow-missing`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/coordinate_mismatch --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/invalid_bbox --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/missing_textboxes --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/schema_mismatch --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/path_escape --expect-fail`

遗留事项：

- 该维护项不改变漫画探针质量，不追加 `metrics/version_history.csv`。
- Swift / Xcode 代码改动仍需要云端 Xcode build；手动探针仍需 `workflow_dispatch` 选择 `ci-fast` 或 `full`。

### v1.59：Injected Koharu Artifact App-Readiness Smoke
日期：2026-07-06

依据：`md/koharu研究/v1.38-current-gap-to-koharu.md` 把 P0 定为真实 Koharu artifact 输入。此前 workflow 已能下载、校验、解压并 validator 检查四件套，但手动探针的 smoke 仍可能只证明 CI 注入步骤成功，未强制证明 App 内 `externalArtifactReadinessReport` 和 external TextBox shadow OCR 真消费到了 active artifact。

核心变更：

- 手动 `workflow_dispatch` 注入 Koharu artifact 且运行 `ci-fast/full` 时，`manga-probe.log` 的 post-export smoke 会读取 `output/probe_report.json`，强制核对 App 侧 `externalArtifactReadinessReport.readinessVerdict = readyForShadowOCR`、`activeArtifactsDirectory = true`、`contractExampleOnly = false`、`externalTextBoxesShadowOCRAllowed = true`，以及 manifest / TextBoxes / BubbleMask / SegmentMask 全部 found。
- 同一 smoke 会核对 `externalTextBoxShadowOCRReport.executed = true` 且 `candidateCount > 0`，避免只验证静态四件套存在却没有进入 shadow OCR。
- 同一 smoke 会核对 `koharuNativeArtifactContractDryRunReport.contractDryRunVerdict = activeArtifactsReadyForShadowOCR`，并确认 `dryRunOnly = true`、`activeExportAllowed = false`，保持 active artifact 写入边界。
- TXT smoke 新增注入路径 needle：`externalArtifacts: readiness=readyForShadowOCR`、`shadowOCRAllowed=true`、`nativeArtifactContractDryRunReport`、`nativeArtifactContractDryRunPreview`。
- `README.md`、`md/flow/flow.md`、`md/test/test.md` 同步说明：Agent C 不能只看 Release 下载、SHA、解压或 validator 日志，必须看 App 侧探针报告。

关键文件：

- `.github/workflows/ci-results.yml`
- `README.md`
- `md/flow/flow.md`
- `md/test/test.md`
- `update_log.md`

验证结果：

- `ruby -e 'require "yaml"; YAML.load_file(".github/workflows/ci-results.yml"); puts "yaml ok"'`
- `git diff --check`
- `swiftc -parse $(rg --files AITRANS -g '*.swift')`
- `python3 -m json.tool test/1.ground_truth.json`
- `python3 -m json.tool output/probe_report.json`
- `python3 -m json.tool output/clean_text_diagnostic.json`
- `python3 -m py_compile scripts/validate-koharu-artifacts.py`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/valid`
- `python3 scripts/validate-koharu-artifacts.py --root test/koharu_artifacts --allow-missing --print-required-files`
- `python3 scripts/validate-koharu-artifacts.py --root test/koharu_artifacts --allow-missing`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/coordinate_mismatch --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/invalid_bbox --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/missing_textboxes --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/schema_mismatch --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/path_escape --expect-fail`

未跑本机 Xcode build / 模拟器漫画探针；按规则交给 GitHub Actions build 和手动 `ci-fast` / `full` 探针验证。

遗留事项：

- 该版本不提供真实 Koharu artifact，也不创建 active `test/koharu_artifacts/`；只强化注入后云端验收证据。
- 该版本不改变漫画质量指标，不追加 `metrics/version_history.csv`。

### v1.58：TextBox Segment Linkage Reaches Convergence
日期：2026-07-06

依据：v1.57 已把 TextBox -> SegmentMask linkage 传播到 bundle-lite 和 promotion gate，但最终 `koharuArtifactConvergenceReport` 仍需要显式消费这些 work item / gate，避免 bundle / promotion 层已经阻塞弱 linkage、收敛层却只按旧 artifact stage 给出下一步。

核心变更：

- `koharuArtifactConvergenceReport` 新增 bundle / promotion linkage review 聚合，把 v1.57 的 review / blocked blocks 继续传播到 convergence stage、block path、work item closure ledger 和 gate ledger。
- TextBoxes / SegmentMask convergence stage 会在 weak、fallback、rejected 或 wrong-bubble linkage 存在时输出 linkage-blocked status、affected blocks、decision signals 和 blocked work items。
- 逐块 artifact path 会把 `primaryStructuralBottleneck` 收束到 `textBoxSegmentMaskLinkage`，并优先给出 `auditTextBoxSegmentLinkageBeforeBundleReadiness` 或 `auditTextBoxSegmentLinkageBeforePromotion`。
- 新增 convergence work items / gates：`WI-koharu-native-artifact-bundle-lite-textbox-segment-linkage`、`WI-koharu-native-promotion-gate-lite-textbox-segment-linkage`、`G-koharu-convergence-bundle-lite-textbox-segment-linkage`、`G-koharu-convergence-promotion-lite-textbox-segment-linkage`。
- `1_ocr_probe_text.txt` 新增 `convergenceBundleTextBoxSegmentLinkage` 和 `convergencePromotionTextBoxSegmentLinkage` 摘要，云端 `ci-fast` smoke 会检查 JSON 字段和 TXT needle。
- 本轮仍是 report-only：不新增 OCR / LLM / PNG，不创建或修改 active `test/koharu_artifacts/`，不改变主 OCR、翻译输入、覆盖图、renderer、`safeLayoutRect`、`glyphMaskFillRects`、`blockPassed`、失败分类、`textRegionCropReport.adoptedCount` 或 `configuration.currentBlockSource`。

关键文件：

- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `.github/workflows/ci-results.yml`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`

验证结果：

- `swiftc -parse $(rg --files AITRANS -g '*.swift')`
- `ruby -e 'require "yaml"; YAML.load_file(".github/workflows/ci-results.yml"); puts "yaml ok"'`
- `git diff --check`
- `python3 -m json.tool test/1.ground_truth.json`
- `python3 -m json.tool output/probe_report.json`
- `python3 -m json.tool output/clean_text_diagnostic.json`
- `python3 -m py_compile scripts/validate-koharu-artifacts.py`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/valid`
- `python3 scripts/validate-koharu-artifacts.py --root test/koharu_artifacts --allow-missing --print-required-files`
- `python3 scripts/validate-koharu-artifacts.py --root test/koharu_artifacts --allow-missing`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/coordinate_mismatch --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/invalid_bbox --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/missing_textboxes --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/schema_mismatch --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/path_escape --expect-fail`

未跑本机 Xcode build / 模拟器漫画探针；按规则交给 GitHub Actions build 和手动 `ci-fast` / `full` 探针验证。

遗留事项：

- 该版本不改变漫画质量指标，不追加 `metrics/version_history.csv`。
- 真正的 Koharu 能力仍依赖真实 TextBoxes / BubbleMask / SegmentMask 四件套或模型级 detector 输出；native-lite linkage 只作为 report-only gate。

### v1.57：TextBox Segment Linkage Propagates to Bundle / Promotion
日期：2026-07-06

依据：v1.56 已在 SegmentMask refinement-lite 中记录 selected TextBox -> SegmentMask linkage，但 v1.45 bundle-lite 和 v1.46 promotion gate 仍主要看组件可用性，缺少把 rejected / fallback / wrong-bubble TextBox linkage 继续向 bundle readiness 和 promotion eligibility 传播的阻塞口径。

核心变更：

- `MangaKoharuNativeArtifactBundleLiteBlockLedger` 新增 `selectedTextBoxSegmentLinkVerdict`、`textBoxSegmentLinkageStatus`、`textBoxSegmentLinkageRisk`；报告新增 `textBoxSegmentLinkBreakdown` 和 `textBoxSegmentLinkageReviewBlocks`。
- `koharuNativeArtifactBundleLiteReport` 新增 `TextBoxSegmentMaskLinkage` consistency edge；fallback、weak、rejected 或 wrong-bubble linkage 会把 `primaryBlockingArtifact` 指向 `TextBoxes`，并把 `nextAction` 收束到 `auditTextBoxSegmentLinkageBeforeBundleReadiness`。
- `MangaKoharuNativePromotionBlockLedger` 新增 `textBoxSegmentLinkVerdict` 和 `textBoxSegmentLinkagePromotionStatus`；报告新增 `textBoxSegmentLinkBreakdown` 和 `textBoxSegmentLinkageBlockedBlocks`。
- `koharuNativePromotionGateLiteReport` 会把弱 linkage 写入 TextBoxes / SegmentMask promotion status、`mustNotPromoteReasons`、probe bottleneck 和 `auditTextBoxSegmentLinkageBeforePromotion`，防止 SegmentMask proxy 因局部可用而被误判可晋级。
- 新增 linkage work items / gates：`WI-koharu-native-artifact-bundle-lite-textbox-segment-linkage`、`G-native-artifact-bundle-lite-textbox-segment-linkage`、`WI-koharu-native-promotion-gate-lite-textbox-segment-linkage`、`G-native-promotion-gate-lite-textbox-segment-linkage`。
- `1_ocr_probe_text.txt` 新增 bundle / promotion 的 `textBoxSegmentLink=` 逐块摘要，以及报告级 `nativeArtifactBundleLiteTextBoxSegmentLink`、`nativePromotionTextBoxSegmentLink` 汇总。
- 本轮仍是 report-only：不新增 OCR / LLM / PNG，不创建或修改 active `test/koharu_artifacts/`，不改变主 OCR、翻译输入、覆盖图、renderer、`safeLayoutRect`、`glyphMaskFillRects`、`blockPassed`、失败分类、`textRegionCropReport.adoptedCount` 或 `configuration.currentBlockSource`。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`

验证结果：

- `swiftc -parse $(rg --files AITRANS -g '*.swift')`
- `ruby -e 'require "yaml"; YAML.load_file(".github/workflows/ci-results.yml"); puts "yaml ok"'`
- `git diff --check`
- `python3 -m json.tool test/1.ground_truth.json`
- `python3 -m json.tool output/probe_report.json`
- `python3 -m json.tool output/clean_text_diagnostic.json`
- `python3 -m py_compile scripts/validate-koharu-artifacts.py`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/valid`
- `python3 scripts/validate-koharu-artifacts.py --root test/koharu_artifacts --allow-missing --print-required-files`
- `python3 scripts/validate-koharu-artifacts.py --root test/koharu_artifacts --allow-missing`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/coordinate_mismatch --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/invalid_bbox --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/missing_textboxes --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/schema_mismatch --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/path_escape --expect-fail`

遗留事项：

- 未跑本机 Xcode build / 模拟器漫画探针；按规则交给 GitHub Actions build 和手动 `ci-fast` / `full` 探针验证。
- 该版本不改变漫画质量指标，不追加 `metrics/version_history.csv`。

### v1.56：TextBox -> SegmentMask Linkage Gate
日期：2026-07-06

依据：`md/koharu研究/v1.38-current-gap-to-koharu.md` 的 TextBoxes / SegmentMask 差距：Koharu 是 TextBoxes 先产出，再约束 SegmentMask；AITRANS 已有 detector-lite 和 SegmentMask refinement-lite，但两者之间缺少可审计 linkage，容易出现 SegmentMask 看似可用、实际来自弱 TextBox / rejected TextBox / fallback bbox 的假闭环。

核心变更：

- `MangaKoharuNativeTextBoxDetectorLiteCandidate` 新增 `relatedBlockRelations[]`，记录 candidate 与 block 的 overlap、center containment、same-bubble 和 relation reason。
- `MangaKoharuNativeTextBoxDetectorLiteBlockLedger` 新增 best candidate relation 字段：coverage ratio、center-contained、same-bubble、candidate verdict 和 shadow OCR eligibility。
- `koharuNativeTextBoxDetectorLiteReport` 新增 `blockRelationBreakdown`。
- `MangaKoharuNativeSegmentMaskRefinementLiteCandidateLedger` 新增来源 TextBox linkage 字段：source TextBox verdict、shadow eligibility、block overlap、same-bubble、accepted-for-SegmentMask 和 link verdict。
- `MangaKoharuNativeSegmentMaskRefinementLiteBlockLedger` 新增 selected source TextBox candidate ID / link verdict。
- `koharuNativeSegmentMaskRefinementLiteReport` 新增 `textBoxSegmentLinkBreakdown`、`segmentFromAcceptedTextBoxCount`、`segmentFromRejectedTextBoxCount`、`segmentFromFallbackBBoxCount`。
- 新增 gates：`G-native-segmentmask-refinement-lite-textbox-linkage-audited` 和 `G-native-segmentmask-refinement-lite-no-rejected-textbox-silent-selection`。
- `1_ocr_probe_text.txt` 的 TextBox / SegmentMask native-lite summary 输出 candidate relation、selected link verdict、accepted/rejected/fallback 计数。
- 本轮不新增 OCR / LLM / PNG，不创建或修改 active `test/koharu_artifacts/`，不替换主 OCR、翻译输入、覆盖图、`safeLayoutRect`、`glyphMaskFillRects`、renderer、`blockPassed`、失败分类、`textRegionCropReport.adoptedCount` 或 `configuration.currentBlockSource`。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`

验证结果：

- `swiftc -parse $(rg --files AITRANS -g '*.swift')`

遗留事项：

- Linkage gate 仍只审计 native-lite proxy TextBoxes；真实能力需要 active Koharu TextBoxes / SegmentMask 四件套或模型级 detector 输出。
- 后续可把该 linkage 接入 `koharuNativeArtifactBundleLiteReport` / promotion gate 的 consistency edges，使 rejected / fallback TextBox 约束直接影响 artifact readiness。

### v1.55：BubbleMask Sibling Sprite Collision Preview
日期：2026-07-06

依据：`md/koharu研究/v1.38-current-gap-to-koharu.md` 的 P5 渲染方向和 Koharu renderer 的 same-bubble sprite collision 思路：v1.54 已检查单块 sprite bounds 是否落在 block-scoped safe rect 内，本轮继续 report-only 检查同一个 instance-lite bubble 下多个 rendered sprite bounds 是否互相重叠。

核心变更：

- `MangaKoharuNativeBubbleMaskInstanceLiteBlockLedger` 新增 `sameInstanceRenderSpriteOverlapCount` 和 `spriteSiblingCollisionPolicy`。
- `MangaKoharuNativeBubbleMaskInstanceLiteSiblingLedger` 新增 `renderSpriteOverlapCount` 和 `sameBubbleSpriteCollisionPolicy`。
- `koharuNativeBubbleMaskInstanceLiteReport` 新增 `spriteSiblingCollisionBreakdown`。
- `makeKoharuNativeBubbleMaskInstanceLiteReport` 现在对 same-instance sibling blocks 的 `renderNonTransparentBounds` 做 bounded overlap 计数，并输出 `sameInstanceSpritesSeparated`、`sameInstanceSpriteOverlapManualReview`、`missingRenderSpriteBounds` 或 `singleBlockOrNoInstance`。
- 新增 gate `G-native-bubblemask-instance-lite-sibling-sprite-collision`，只证明同 instance sprite collision 已进入账本，不写回 renderer。
- `1_ocr_probe_text.txt` 的 block / sibling / summary 行输出 sibling sprite overlap 和 collision policy。
- CI 维护：Koharu artifact archive 注入前会清空 `test/koharu_artifacts/`，避免残留 active 文件影响四件套 validator；测试文档同步 schema/path invalid fixtures 和 skip/探针结果包口径。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `.github/workflows/ci-results.yml`
- `README.md`
- `AGENTS.md`
- `md/test/test.md`
- `update_log.md`

验证结果：

- `swiftc -parse $(rg --files AITRANS -g '*.swift')`

遗留事项：

- 这仍是 bounds-level sibling collision preview，不是 Koharu renderer 的逐像素 alpha mask collision；真实能力需要 active BubbleMask 或 renderer-side sprite alpha gate。
- Rawls 子 agent 建议的 TextBox -> SegmentMask linkage gate 是下一轮高收益候选；本轮先收窄在 P5 sibling sprite collision，避免一次改动跨太多报告结构。

### v1.54：BubbleMask Block-Scoped Sprite Containment Preview
日期：2026-07-06

依据：`md/koharu研究/v1.38-current-gap-to-koharu.md` 的 P5 渲染方向和 Koharu renderer 的 mask collision 思路：先 report-only 检查 rendered sprite 非透明 bounds 是否落在所属 block 的 scoped safe rect 内，再考虑未来是否接入真实 renderer gate。

核心变更：

- `MangaKoharuNativeBubbleMaskInstanceLiteBlockLedger` 新增 `spriteBlockScopedSafeRectContainmentRatio`、`spriteContainedByBlockScopedSafeRect`、`spriteContainmentPolicy`。
- `koharuNativeBubbleMaskInstanceLiteReport` 新增 `spriteBlockScopedContainmentBreakdown`，保留旧 `spriteContainmentBreakdown` 的 instance-lite mask coverage 语义。
- v1.43 block ledger 现在用现有 `renderNonTransparentBounds` 和 `instanceLiteBlockScopedSafeRect` 计算 report-only containment ratio；`>= 0.995` 视为 `spriteWithinBlockScopedSafeRect`，缺 bounds / 缺 scoped safe rect 时明确记录 missing 状态。
- `1_ocr_probe_text.txt` 的 `nativeBubbleMaskInstanceLiteBlockLedger` 行输出 `spriteScopedContainmentRatio`、`spriteContainedByScopedSafeRect`、`spriteContainmentPolicy`；summary 输出 `nativeBubbleMaskInstanceLiteBlockScopedSpriteContainment`。
- 本轮不新增 OCR / LLM / PNG，不创建或修改 active `test/koharu_artifacts/`，不重新渲染，不写回主 OCR、翻译输入、覆盖图、`safeLayoutRect`、DistanceField 报告、renderer、`blockPassed`、失败分类、`textRegionCropReport.adoptedCount` 或 `configuration.currentBlockSource`。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`

验证结果：

- `swiftc -parse $(rg --files AITRANS -g '*.swift')`

遗留事项：

- 这仍是 bounds-level preview，不是 Koharu 逐像素 alpha mask collision；真实能力需要 active BubbleMask 或 renderer-side sprite alpha gate。
- 当前本地 `output/` 不含 v1.43+ 新字段；真实 JSON / TXT 结果以后续手动 GitHub Actions `ci-fast/full` 结果包为准。

### v1.53：BubbleMask Instance-Lite Sibling Safe Rect Policy
日期：2026-07-06

依据：`md/koharu研究/v1.38-current-gap-to-koharu.md` 的 P3 方向，以及 Koharu renderer 行为：同一个 bubble ID 下多个 text block 不应全部扩展到同一个最大 safe rect，否则会制造 sibling layout collision。

核心变更：

- `MangaKoharuNativeBubbleMaskInstanceLiteBlockLedger` 新增 `instanceLiteBlockScopedSafeRect` 和 `instanceLiteSafeRectPolicy`。
- `MangaKoharuNativeBubbleMaskInstanceLiteSiblingLedger` 新增 `blockScopedSafeRectOverlapCount` 和 `sameBubbleSafeRectPolicy`。
- `koharuNativeBubbleMaskInstanceLiteReport` 新增 `safeRectPolicyBreakdown`。
- 单 block instance 继续使用 v1.51 的 mask-derived instance safe rect；同 instance 多 block 时，report-only `instanceLiteBlockScopedSafeRect` 使用 block seed rect，避免把同一个最大 safe rect 复制给 siblings。
- `distanceFieldSafeRectFromInstanceLite` 在同 instance 多 block 场景写入 block-scoped rect，并把 `distanceFieldSafeRectSource` 标为 `nativeBubbleMaskInstanceLiteBlockScopedSeedRect`。
- 新增 gate `G-native-bubblemask-instance-lite-sibling-safe-rect-policy`，只证明 policy report-only，不写回主流程。
- `1_ocr_probe_text.txt` 的 block / sibling / summary 行新增 safe rect policy 和 block-scoped overlap 输出。
- 本轮不新增 OCR / LLM / PNG，不创建或修改 active `test/koharu_artifacts/`，不写回主 OCR、翻译输入、覆盖图、`safeLayoutRect`、DistanceField 报告、renderer、`blockPassed`、失败分类或 `configuration.currentBlockSource`。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`

验证结果：

- `swiftc -parse $(rg --files AITRANS -g '*.swift')`

遗留事项：

- 仍是 native-lite report-only 近似；真实 Koharu BubbleMask 仍需要 active artifact 或更强 detector 输出。
- 当前本地 `output/` 不含 v1.43+ 新字段；真实 JSON / TXT 结果以后续手动 GitHub Actions `ci-fast/full` 结果包为准。

### v1.52：SegmentMask Refinement-Lite Containment Ratio Gate
日期：2026-07-06

依据：`md/koharu研究/v1.38-current-gap-to-koharu.md` 的 P3 / SegmentMask 差距，以及子 agent 对 v1.44 的只读复核：已有 TextBox-constrained glyph mask，但 `maskContainedByTextBox` / `maskContainedByBubble` 只是弱布尔，不能表达 Koharu-like mask containment 证据。

核心变更：

- `MangaKoharuNativeSegmentMaskRefinementLiteCandidateLedger` / `BlockLedger` 新增 `maskContainedByTextBoxRatio`、`maskContainedByBubbleRatio`、`maskMajorityInstanceLiteID`、`maskMajorityBubbleID`、`maskMajorityCoverage`、`maskMajorityAgreement`。
- `koharuNativeSegmentMaskRefinementLiteReport` 新增 `maskMajorityAgreementBreakdown`。
- v1.44 正常候选在 `maskBBox` 生成后用 `rectContainmentRatio` 计算 TextBox / Bubble containment ratio；block ledger 的 `maskContainedByTextBox` / `maskContainedByBubble` 改为 ratio 阈值判定，而不是只看是否缺 constraint。
- majority agreement 使用 v1.43 instance-lite ledger / instance bbox / bubble ID 做 report-only 一致性判断；不重算真实 SegmentMask 像素多数票，不把它冒充真实 Koharu SegmentMask。
- `1_ocr_probe_text.txt` summary 追加 `nativeSegmentMaskRefinementLiteMajorityAgreement`，candidate / block ledger 行输出 containment ratio 与 majority agreement。
- 本轮仍不新增 OCR / LLM / PNG，不创建或修改 active `test/koharu_artifacts/`，不写回主 OCR、翻译输入、覆盖图、`safeLayoutRect`、`glyphMaskFillRects`、背景填充、renderer、`blockPassed`、失败分类、`textRegionCropReport.adoptedCount` 或 `configuration.currentBlockSource`。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`

验证结果：

- `swiftc -parse $(rg --files AITRANS -g '*.swift')`

遗留事项：

- v1.52 仍是 native-lite report-only 近似；真实 SegmentMask 还需要 active artifact 或 detector 输出。
- 当前本地 `output/` 不含 v1.44+ 新字段；真实 TXT / JSON 输出以后续手动 GitHub Actions `ci-fast/full` 结果包为准。

### v1.51：BubbleMask Instance-Lite 像素派生 Safe Rect
日期：2026-07-06

依据：`md/koharu研究/v1.38-current-gap-to-koharu.md` 的 P3 方向，继续把 BubbleMask instance-lite 从 bbox 代理推向像素 ID mask / safe area 证据；本轮仍不接 active Koharu artifact、不新增 OCR / LLM / PNG、不替换主 OCR / 翻译 / 覆盖 / 通过判定。

核心变更：

- `koharuNativeBubbleMaskInstanceLiteReport` 的 `instanceLiteSafeRect` / `distanceFieldSafeRectFromInstanceLite` 不再由 instance bbox 简单内缩生成，改为从对应 instance 的源图像像素 offset 派生。
- 新增轻量 mask-derived safe rect 逻辑：先按 row / column run 估计到 mask 边界的内侧距离并做 erosion；若实例太薄无法形成 eroded core，则回退到高覆盖 row / column projection core。
- same-bubble sibling overlap 和逐块 block ledger 共用同一份 `instanceSafeRectsByID`，避免 block 与 sibling ledger 使用不同 safe rect 口径。
- block decision signals 新增 `safeRectSource = maskDerivedInstanceLitePixels` / `nil`，保持 schema 不变。
- 所有结果仍是 report-only；不写回 `safeLayoutRect`、DistanceField 报告、renderer、OCR 输入、翻译输入、active artifacts 或 `configuration.currentBlockSource`。

关键文件：

- `AITRANS/Services/MangaOverlayProbeService.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`

验证结果：

- `swiftc -parse $(rg --files AITRANS -g '*.swift')`
- `git diff --check`

遗留事项：

- 该 safe rect 仍是 AITRANS native-lite report-only 近似，不代表真实 Koharu `BubbleMask` distance field 已接入。
- 真实 P3 收益仍需手动 GitHub Actions `ci-fast/full` 结果包检查 `koharuNativeBubbleMaskInstanceLiteReport` 的 block / sibling ledger。

### v1.50：Detector-Lite 竖排 Rotation Shadow OCR
日期：2026-07-06

依据：`md/koharu研究/v1.38-current-gap-to-koharu.md` 的 P2 方向，向 Koharu 的竖排 / 方向处理能力靠近；本轮不新建 active artifact、不新增 LLM、不替换主 OCR / 翻译 / 覆盖 / 通过判定。

核心变更：

- `koharuNativeTextBoxDetectorLiteShadowOCRReport` 复用既有 `directionHint` / `rotationApplied` 字段，对 v1.39 `verticalCandidate` 做有上限的 `[0,90]` crop OCR shadow 对照。
- `verticalCandidate` crop OCR 使用受限 `ja-JP/ja/en-US/en` Vision language profile；横排候选保留默认 0 度 / 英语路径。
- v1.40 候选选择按当前 block 与 bbox 的 overlap / center containment 优先于全局 detector score，降低 same-bubble sibling 共享错误高分候选的风险。
- full 模式每块最多跑 2 个候选时，block ledger 的 `selectedCandidateID` 现在记录本块 report-only 最佳 shadow OCR 候选，v1.41 refinement 跟随该最佳 ID。
- rotation 对照仍按候选计入既有每块选择预算：`ci-fast` 每块最多 1 个 detector-lite 候选、`full` 每块最多 2 个；不会新增候选池或 promotion 路径。
- 旋转结果选择只使用无真值 OCR 质量分和当前文本 word preservation；ground truth 仍只写 evaluation signals，不参与候选选择、OCR 执行、gate 或 nextAction。
- 新增 gate `G-native-textbox-detector-lite-shadow-ocr-vertical-rotation-budget`，记录 vertical candidate 数、实际采用 rotation 数和 rotation breakdown。
- `1_ocr_probe_text.txt` summary 新增 `nativeTextBoxDetectorLiteShadowOCRRotation`，每个 `nativeTextBoxDetectorLiteShadowOCRCandidate` 输出 `rotation=`。

关键文件：

- `AITRANS/Services/MangaOverlayProbeService.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`

验证计划：

- 本地运行 Swift parse、workflow YAML parse、`git diff --check`、JSON smoke 和 Koharu artifact validator smoke。
- 本轮不跑本地 Xcode build 或模拟器漫画探针；真实 v1.50 `rotationApplied` 结果以手动 GitHub Actions `ci-fast/full` 输出为准。

遗留事项：

- 当前 `test/1.png` 是英文横排样例，可能不会稳定触发大量 `verticalCandidate`；P2 真正收益仍需要竖排日语样例或云端结果包证明。
- 该路径仍是 detector-lite shadow OCR，不代表真实 Koharu TextBoxes / OCR 已接入，也不替换主流程。

### v1.49：Detector-Lite 每 Bubble 多候选池
日期：2026-07-06

依据：`md/koharu研究/v1.38-current-gap-to-koharu.md` 的 P1 要求，在没有真实 Koharu artifact 时继续改进 native TextBoxes detector-lite；本轮仍不伪造 active artifact、不使用 Vision OCR 文本 / ground truth / pre-crop / line / TextRegion crop 结果生成候选，不改变主 OCR、翻译、覆盖或通过判定。

核心变更：

- `koharuNativeTextBoxDetectorLiteReport` 从每个 bubble 单一暗连通域 union 候选，改为每个 bubble 有上限的预 OCR candidate pool：最多 4 个 component-cluster TextBox 候选 + 1 个 diagnostic union fallback。
- component-cluster 候选按 bubble 内连通域 gap / projection split 生成；union fallback 仅用于诊断，固定 `shadowOCREligible = false`，避免在 v1.40 `ci-fast` 每块 1 个候选预算下抢占 shadow OCR。
- detector-lite candidate ID 改为稳定零填充序号 `NTBDL-<bubbleID>-<NN>`，并按 bubble、shadow OCR eligibility、score、ID 稳定排序。
- 多候选到 current block 的关系改为 bbox overlap / center containment 优先；component-cluster 无匹配时才回退同 bubble 最近块，避免同 bubble sibling 全部共享同一高分候选。
- `G-native-textbox-detector-lite-candidate-pool-cap` gate 记录候选池上限，文档和测试口径同步要求 `bubbleLedgerCount == evaluatedBubbleCount`、candidate pool 有上限且 union fallback 不参与 shadow OCR。

关键文件：

- `AITRANS/Services/MangaOverlayProbeService.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`

验证计划：

- 本地运行 Swift parse、workflow YAML parse、`git diff --check`、JSON smoke 和 Koharu artifact validator valid / invalid / active-missing smoke。
- 本轮不跑本地 Xcode build 或模拟器漫画探针；完整 build 和真实 `ci-fast/full` 探针仍交给 GitHub Actions。

遗留事项：

- 多候选池仍是 proxy-not-real Koharu TextBoxes；真实晋级仍需要 Release 注入真实 Koharu artifact archive 并通过 active artifact validator。
- 手动 `ci-fast/full` 才会运行 v1.40/v1.41 shadow OCR / refinement OCR；push 默认快验仍保持 probe skip 以控制云端耗时。

### v1.48 Koharu active artifact CI intake 与契约硬化
日期：2026-07-06

依据：`md/koharu研究/v1.38-current-gap-to-koharu.md` 的 P0 要求从 report-only 转向真实 `test/koharu_artifacts/` 输入。本轮不伪造 active artifact、不复制 examples、不使用 Vision OCR / pre-crop / line / proxy / ground truth / 手写框生成四件套。

核心变更：

- `AITRANS CI Results` 新增手动 `workflow_dispatch` 输入 `koharu_artifact_release_tag`、`koharu_artifact_asset`、`koharu_artifact_sha256`、`koharu_artifact_required`。
- 当提供真实 Koharu artifact archive 时，CI 在 Xcode build 前从 Release 下载、校验 SHA256、解压，并只复制 `1.manifest.json`、`1.textboxes.json`、`1.bubbles.json`、`1.segment_mask.json` 到 `test/koharu_artifacts/`，随后运行 validator。`koharu_artifact_required=true` 时注入或 validator 失败会阻断工作流。
- `ci-artifact-manifest.json` 新增 Koharu artifact 注入来源、required 状态、注入结果、Release tag、asset、SHA 和注入日志路径，Agent C 可区分缺 artifact 阻塞路径与真实 artifact 注入路径。
- `scripts/validate-koharu-artifacts.py` 将 `schemaVersion` 缺失 / 不匹配变成 readiness 阻塞，`schemaVersion` 必须为 `aitrans.koharu_artifact_contract.v1`。
- Python validator 和 Swift readiness 都拒绝 manifest artifact path 使用绝对路径或 `..` 逃逸 active artifact root，避免 active manifest 指向目录外文件。
- 新增 invalid fixtures：`schema_mismatch` 和 `path_escape`，并加入 CI 静态检查 `--expect-fail`。

关键文件：

- `.github/workflows/ci-results.yml`
- `scripts/validate-koharu-artifacts.py`
- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `md/koharu研究/artifact_contract/README.md`
- `md/test/test.md`
- `md/flow/flow.md`
- `README.md`

验证结果：

- 本轮应通过轻量检查：Swift parse、workflow YAML parse、`git diff --check`、JSON parse、validator valid / invalid / active missing。
- 本轮不跑本地 Xcode build 或模拟器漫画探针；完整 build 和 `ci-fast/full` 仍交给 GitHub Actions。

遗留事项：

- 当前仓库默认仍没有真实 active `test/koharu_artifacts/`，因此不能声称 `externalTextBoxShadowOCRReport.executed = true` 已验证。
- 下一步若有真实 Koharu archive，手动 `workflow_dispatch` 填写 Koharu artifact 输入并选择 `ci-fast`，验收 `koharuArtifactValidation.verdict = readyForShadowOCR`、Swift readiness ready、external shadow OCR executed。
- 若短期仍无真实 artifact，下一步按 v1.38 P1 改进 native TextBoxes detector-lite：每个 bubble 生成多个 OCR 前 TextBox 候选，而不是将全部暗连通域 union 成单一大框。

### 维护：AITRANS CI Results 默认快验加速
日期：2026-07-06

本轮根据 Agent X 目标和云端 CI 速度要求，精简默认云端验证路径；不修改漫画探针算法、不刷新仓库根 `output/`，不追加 `metrics/version_history.csv`。

核心变更：

- `AITRANS CI Results` 增加 `concurrency`，同一 ref 新 run 会取消旧 run，避免连续 push 堆积 macOS runner。
- `push` 到 `smalldata_test` / `codeb/**` 默认 `probe_mode=skip`，只跑静态检查、Xcode build、manifest 和未加密结果包；不下载 GGUF、不创建模拟器、不安装 App、不跑漫画探针。
- 手动 `workflow_dispatch` 仍可选择 `ci-fast` 或 `full` 跑真实 simulator + Local GGUF 漫画探针。
- `probe_mode=skip` 时 JUnit 把 GGUF model / simulator / manga probe 跳过视为快验成功，并在 manifest 写 `probeSkippedReason = default_push_fast_ci_or_manual_skip` 与 `modelSetupSkippedReason = probe_mode_skip_fast_ci_does_not_need_model`。
- 手动探针模式下，GGUF cache 只在 SHA 校验成功后保存；build 或模型校验失败时不再继续定位 App 或启动模拟器。
- 手动探针导入模型到 App sandbox 时优先使用 APFS clone `cp -c`，失败再回退普通复制。
- 手动探针新增 `probeNoProgressTimeoutSeconds`，`ci-fast` 180 秒、`full` 300 秒内若没有生成 progress 文件会提前失败，避免 App 未启动时等满总超时。

关键文件：

- `.github/workflows/ci-results.yml`
- `README.md`
- `AGENTS.md`
- `md/flow/flow.md`
- `md/test/test.md`
- `update_log.md`

验证计划：

- 本地运行 YAML 解析、`git diff --check` 和现有 JSON smoke。
- 未跑本机 build / 探针；push 后默认云端快验应只检查静态项和 Xcode build。需要漫画探针结果时手动触发 `workflow_dispatch` 的 `ci-fast` 或 `full`。

遗留事项：

- 手动 `ci-fast` 内部仍会运行 v1.40 / v1.41 detector-lite shadow OCR / refinement OCR 等额外 Vision crop OCR；若后续还嫌手动探针慢，需要在 Swift run options 中新增更细粒度门控并同步 v1.29-v1.46 验收口径。

### v1.47：Koharu Native Artifact Contract Dry-Run 四件套准入干跑
日期：2026-07-06

依据：Agent X 继续沿 `md/koharu研究/v1.38-current-gap-to-koharu.md` 推进，避免继续只堆抽象报告，转向真实 Koharu artifact 四件套准入的机器可验 dry-run。本轮修改 Swift 探针报告模型、TXT 摘要和核心文档；不刷新仓库根 `output/`，不追加 `metrics/version_history.csv`，完整 build / 探针交给 GitHub Actions。

核心变更：

- 新增 `koharuNativeArtifactContractDryRunReport`，在 v1.46 `koharuNativePromotionGateLiteReport` 后生成。
- 报告把 v1.46 `candidateExportPreviews[]` 映射到 active 四件套 contract：`test/koharu_artifacts/1.manifest.json`、`1.textboxes.json`、`1.bubbles.json`、`1.segment_mask.json`。
- 报告写出 `sourceImage = test/1.png`、`coordinateSpace = originalImageTopLeftPixels`、`activeInputDirectory`、`examplesDirectory`、required files、required fields、missing fields、forbidden source breakdown、validator commands 和 gate ledger。
- `koharuArtifactConvergenceReport` 现在把 v1.47 纳入 `referenceReports`、`workItemLedger` 和 `gateLedger`，用 `WI-koharu-native-artifact-contract-dry-run` / `G-koharu-native-artifact-contract-dry-run-executed` 明确记录真实四件套 intake 仍阻塞或 ready。
- `activeExportAllowed = false`、`dryRunOnly = true`，native-lite / proxy preview 只做 contract dry-run，不创建、复制或修改 active `test/koharu_artifacts/`。
- `1_ocr_probe_text.txt` 新增 dry-run summary、required file、preview、gate、validator command 和 forbidden active source 摘要。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`

验证计划：

- 本地运行 Swift parse、YAML 解析、`git diff --check`、JSON smoke 和 Koharu artifact validator 正反例。
- 云端手动 `workflow_dispatch` 的 `ci-fast` 应证明 `koharuNativeArtifactContractDryRunReport.enabled = true`、`evaluatedBlockCount == totalBlocksDetected`、`requiredFileCount >= 4`、`contractGateCount >= 6`、`dryRunOnly = true`、`activeExportAllowed = false`、`groundTruthUsedForDecision = false`、`wouldChangeMainFlow = false`，`koharuArtifactConvergenceReport.referenceReports` 包含该报告，`workItemLedger` / `gateLedger` 包含 `WI-koharu-native-artifact-contract-dry-run` / `G-koharu-native-artifact-contract-dry-run-executed`，且 `1_ocr_probe_text.txt` 包含 `nativeArtifactContractDryRunRequiredFile` 和 `nativeArtifactContractDryRunPreview`。

遗留事项：

- 旧仓库根 `output/` 不含 v1.47 新字段；以 PR 后云端结果包为准。
- v1.47 仍不代表真实 Koharu `TextBoxes` / `BubbleMask` / `SegmentMask` 已接入；下一步仍需要真实 active 四件套或更强 detector 输出通过 validator。

### v1.46：Koharu Native Promotion Gate-Lite 探针驱动晋级门槛
日期：2026-07-03
依据：`md/prompt/v1（漫画探针）/v1.46（KoharuNativePromotionGateLite探针驱动晋级门槛）.md`。本轮修改 Swift 探针报告模型、native-lite promotion gate 聚合账本、Koharu convergence 联动、TXT 快照和核心文档；不刷新仓库根 `output/`，不追加 `metrics/version_history.csv`，完整 build / 探针交给 GitHub Actions。

核心变更：

- 新增 `koharuNativePromotionGateLiteReport`，在 v1.45 Native Artifact Bundle-Lite 后、最终 convergence 刷新前生成。
- 报告只消费 final blocks、diagnostics、v1.39-v1.45 native-lite reports、RenderSprite fit、Render Regression Lock、Translation Model Floor、clean text diagnostic 和 external artifact readiness。
- 每个 final block 输出 report-only promotion ledger，覆盖 TextBoxes / BubbleMask / SegmentMask / OcrText / Translations / RenderedSprites / FinalRender 的晋级状态、primary blocking artifact、probe bottleneck、promotion eligibility、nextAction 和 `mustNotPromoteReasons`。
- 新增 canonical stage gates，覆盖 TextBoxes、BubbleMask、SegmentMask、OcrText、Translations、RenderedSprites、FinalRender 和 ExternalArtifacts。
- 新增 `nativeCandidateExportPreview`，只在 JSON / TXT 中预览未来 AITRANS-native candidate artifact 可能需要的字段、来源、bbox、风险和 validator 要求；本轮不创建、不复制、不修改 active `test/koharu_artifacts/`。
- `koharuArtifactConvergenceReport.referenceReports` 新增 `koharuNativePromotionGateLiteReport`；convergence 新增 `WI-koharu-native-promotion-gate-lite` 和 `G-koharu-native-promotion-gate-lite-executed`。
- `1_ocr_probe_text.txt` 新增 promotion gate summary、stage gate、逐块 block ledger、candidate export preview 和 work item 摘要。
- 本轮不新增 OCR / LLM / PNG，不更换模型，不接 active artifact，不改变主 OCR、翻译输入、覆盖图、renderer、`safeLayoutRect`、`glyphMaskFillRects`、背景填充、`blockPassed`、失败分类、`textRegionCropReport.adoptedCount`、active artifacts 或 `configuration.currentBlockSource`；ground truth 只进 evaluation signals。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`
- `md/prompt/v1（漫画探针）/v1.46（KoharuNativePromotionGateLite探针驱动晋级门槛）.md`

验证计划：

- 本轮 Agent B 本地运行轻量 Swift 语法检查、`git diff --check`、JSON 解析和 Koharu validator smoke。
- 未跑本机 build / 探针，按规则交给云端验证。
- 云端 `AITRANS CI Results` `ci-fast` 应证明 `koharuNativePromotionGateLiteReport.enabled = true`、`evaluatedBlockCount == totalBlocksDetected`、`blockLedgerCount == totalBlocksDetected`、`stageGateCount >= 8`、`candidateExportPreviewCount >= 1` 或明确 blocked / warning reason、`workItemCount >= 1`、`gateCount >= 8`、`promotionGateLite = true`、`nativePromotionPreviewOnly = true`、所有 proxy-not-real 边界为 true、`externalArtifactsRequiredForThisReport = false`、`groundTruthUsedForDecision = false`，核心 breakdown 非空或上游缺失时明确 warning / blocked gate，convergence 包含 v1.46 reference / work item / gate，且 `1_ocr_probe_text.txt` 包含 summary、stage gate、逐块 promotion ledger、candidate preview 和 work item。

遗留事项：

- 旧仓库根 `output/` 不含 v1.46 新字段；以 PR 后云端结果包为准。
- v1.46 仍是 native promotion gate-lite report-only 晋级门槛层，不代表真实 Koharu `TextBoxes` / `BubbleMask` / `SegmentMask` / `OcrText` / `RenderedSprites` 已接入，也不代表 OCR 或翻译质量改善。
- 本轮未重新跑完整漫画探针，不追加 `metrics/version_history.csv` 漫画指标行。

### v1.45：Koharu Native Artifact Bundle-Lite 结构一致性闭环
日期：2026-07-03
依据：`md/prompt/v1（漫画探针）/v1.45（KoharuNativeArtifactBundleLite结构一致性闭环）.md`。本轮修改 Swift 探针报告模型、native-lite artifact bundle 聚合账本、Koharu convergence 联动、TXT 快照和核心文档；不刷新仓库根 `output/`，不追加 `metrics/version_history.csv`，完整 build / 探针交给 GitHub Actions。

核心变更：

- 新增 `koharuNativeArtifactBundleLiteReport`，在 v1.44 SegmentMask refinement-lite 后、最终 convergence 刷新前生成。
- 报告只消费 final blocks、v1.39-v1.42 detector-lite / shadow OCR / refinement / closed-loop、v1.43 BubbleMask instance-lite、v1.44 SegmentMask refinement-lite、RenderSprite fit、Render Regression Lock、Translation Model Floor、external artifact readiness 和 diagnostics。
- 每个 final block 组装 report-only bundle：selected TextBox / Bubble / Segment component、OCR evidence、translation route、render evidence、artifact consistency verdict、primary blocking artifact 和 nextAction。
- 新增逐块 consistency edges，覆盖 TextBoxWithinBubble、SegmentMaskWithinTextBox、SegmentMaskWithinBubble、FinalOCRBBoxAlignedWithTextBox、SameBubbleSiblingMaskNonOverlap、SeamOrSplitRiskExplainsConflict、RenderSpriteContainedByBundleSafeArea 和 ModelFloorSeparatesGeometryFromTranslation。
- `koharuArtifactConvergenceReport.referenceReports` 新增 `koharuNativeArtifactBundleLiteReport`；convergence 新增 `WI-koharu-native-artifact-bundle-lite` 和 `G-koharu-native-artifact-bundle-lite-executed`。
- `1_ocr_probe_text.txt` 新增 bundle-lite summary、逐块 block ledger、consistency edge 和 work item 摘要。
- 本轮不新增 OCR / LLM / PNG，不更换模型，不创建或接入 active Koharu artifact，不改变主 OCR、翻译输入、覆盖图、renderer、`safeLayoutRect`、`glyphMaskFillRects`、背景填充、`blockPassed`、失败分类、`textRegionCropReport.adoptedCount`、active artifacts 或 `configuration.currentBlockSource`。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`
- `md/prompt/v1（漫画探针）/v1.45（KoharuNativeArtifactBundleLite结构一致性闭环）.md`

验证计划：

- 本轮 Agent B 本地运行 `swiftc -parse` 轻量 Swift 语法检查、`git diff --check`、JSON 解析和 Koharu validator smoke。
- 未跑本机 build / 探针，按规则交给云端验证。
- 云端 `AITRANS CI Results` `ci-fast` 应证明 `koharuNativeArtifactBundleLiteReport.enabled = true`、`evaluatedBlockCount == totalBlocksDetected`、`bundleLedgerCount == totalBlocksDetected`、`consistencyEdgeCount >= totalBlocksDetected`、`workItemCount >= 1`、`gateCount >= 8`、`nativeBundleLite = true`、TextBoxes / BubbleMask / SegmentMask proxy 边界为 true、`externalArtifactsRequiredForThisReport = false`、`groundTruthUsedForDecision = false`，核心 breakdown 非空或上游缺失时明确 warning / blocked gate，convergence 包含 v1.45 reference / work item / gate，且 `1_ocr_probe_text.txt` 包含 summary、逐块 block ledger、consistency edge 和 work item。

遗留事项：

- 旧仓库根 `output/` 不含 v1.45 新字段；以 PR 后云端结果包为准。
- v1.45 仍是 native artifact bundle-lite report-only 结构一致性闭环，不代表真实 Koharu `TextBoxes` / `BubbleMask` / `SegmentMask` / `RenderedSprites` 已接入，也不代表 OCR 或翻译质量改善。
- 本轮未重新跑完整漫画探针，不追加 `metrics/version_history.csv` 漫画指标行。

### v1.44：Koharu Native SegmentMask Refinement-Lite 文字像素掩码影子复刻
日期：2026-07-03
依据：`md/prompt/v1（漫画探针）/v1.44（KoharuNativeSegmentMaskRefinementLite文字像素掩码影子复刻）.md`。本轮修改 Swift 探针报告模型、TextBox 约束文字像素 mask refinement-lite 账本、Koharu convergence 联动、TXT 快照和核心文档；不刷新仓库根 `output/`，不追加 `metrics/version_history.csv`，完整 build / 探针交给 GitHub Actions。

核心变更：

- 新增 `koharuNativeSegmentMaskRefinementLiteReport`，在 v1.43 instance-lite BubbleMask 之后、最终 convergence 刷新前生成。
- 报告只使用源图像像素、detector-lite TextBox 候选、final blocks、v1.43 instance-lite BubbleMask、现有 glyph / SegmentMask proxy、render lock 和翻译失败分类，生成 TextBox-constrained glyph pixel mask 的 candidate / block / sibling / gate 账本。
- `groundTruthUsedForDecision = false`，ground truth 只进入 evaluation signals；像素阈值、TextBox 选择、mask 生成、route、nextAction、verdict 和 gate 都不使用真值。
- `koharuArtifactConvergenceReport.referenceReports` 新增 `koharuNativeSegmentMaskRefinementLiteReport`；convergence 新增 `WI-koharu-native-segmentmask-refinement-lite` 和 `G-koharu-native-segmentmask-refinement-lite-executed`。
- `1_ocr_probe_text.txt` 新增 SegmentMask refinement-lite report summary、candidate ledger、逐块 block ledger 和 same-bubble sibling ledger 摘要。
- 本轮不新增 OCR / LLM / PNG，不更换模型，不创建 active Koharu artifact，不改变主 OCR、翻译输入、覆盖图、`safeLayoutRect`、`glyphMaskFillRects`、背景填充、renderer、`blockPassed`、失败分类、`textRegionCropReport.adoptedCount`、active artifacts 或 `configuration.currentBlockSource`。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`
- `md/prompt/v1（漫画探针）/v1.44（KoharuNativeSegmentMaskRefinementLite文字像素掩码影子复刻）.md`

验证计划：

- 本轮 Agent B 本地运行 `git diff --check`、JSON 解析、Koharu validator smoke，并用轻量 Swift parse 检查新增 Swift 语法。
- 未跑本机 build / 探针，按规则交给云端验证。
- 云端 `AITRANS CI Results` `ci-fast` 应证明 `koharuNativeSegmentMaskRefinementLiteReport.enabled = true`、`evaluatedBlockCount == totalBlocksDetected`、`blockLedgerCount == totalBlocksDetected`、`candidateLedgerCount >= totalBlocksDetected`、`gateCount >= 8`、`nativeRefinementLite = true`、`proxyNotRealKoharuSegmentMask = true`、`usesSourceImagePixels = true`、`usesTextBoxConstraints = true`、`usesBubbleMaskConstraints = true`、`groundTruthUsedForDecision = false`，核心 breakdown 非空或像素证据不足时明确 blocked / warning gate，convergence 包含 v1.44 reference / work item / gate，且 `1_ocr_probe_text.txt` 包含 summary、candidate ledger、逐块 block ledger 和 sibling ledger。

遗留事项：

- 旧仓库根 `output/` 不含 v1.44 新字段；以 PR 后云端结果包为准。
- v1.44 仍是 native SegmentMask refinement-lite report-only 影子复刻，不代表真实 Koharu `SegmentMask` / `TextBoxes` / `BubbleMask` 已接入，也不代表 OCR 或翻译质量改善。
- 本轮未重新跑完整漫画探针，不追加 `metrics/version_history.csv` 漫画指标行。

### v1.43：Koharu Native BubbleMask Instance-Lite 像素实例掩码影子复刻
日期：2026-07-03
依据：`md/prompt/v1（漫画探针）/v1.43（KoharuNativeBubbleMaskInstanceLite像素实例掩码影子复刻）.md`。本轮修改 Swift 探针报告模型、像素 instance-lite BubbleMask 账本、Koharu convergence 联动、TXT 快照和核心文档；不刷新仓库根 `output/`，不追加 `metrics/version_history.csv`，完整 build / 探针交给 GitHub Actions。

核心变更：

- 新增 `koharuNativeBubbleMaskInstanceLiteReport`，在 v1.42 detector-lite closed-loop 之后、最终 convergence 刷新前生成。
- 报告只使用源图像内容裁切区像素、现有 bubble geometry、final blocks、glyph / SegmentMask proxy、BubbleIndex / DistanceField / seam / RenderSprite fit、detector-lite closed-loop 和 render lock 证据，生成近白连通域 instance-lite ID mask 账本。
- 输出 `instances[]`、`blockLedgers[]`、`siblingLedgers[]`、`adjacencyLedgers[]` 和 `gateLedger[]`，逐块记录 current bubble、instance-lite majority、safe rect 对照、sprite containment、translation failure route、detector-lite route、primary bottleneck 和 nextAction。
- `groundTruthUsedForDecision = false`，ground truth 只进入 evaluation signals；mask 生成、majority assignment、route、nextAction、verdict 和 gate 都不使用真值。
- `koharuArtifactConvergenceReport.referenceReports` 新增 `koharuNativeBubbleMaskInstanceLiteReport`；convergence 新增 `WI-koharu-native-bubblemask-instance-lite` 和 `G-koharu-native-bubblemask-instance-lite-executed`。
- `1_ocr_probe_text.txt` 新增 instance-lite report summary、实例账本、逐块 majority assignment、sibling / adjacency 和 convergence v1.43 work item / gate 摘要。
- 本轮不新增 OCR / LLM / PNG，不更换模型，不创建 active Koharu artifact，不改变主 OCR、翻译输入、覆盖图、`safeLayoutRect`、DistanceField safe rect、renderer、`blockPassed`、失败分类、`textRegionCropReport.adoptedCount`、active artifacts 或 `configuration.currentBlockSource`。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`
- `md/prompt/v1（漫画探针）/v1.43（KoharuNativeBubbleMaskInstanceLite像素实例掩码影子复刻）.md`

验证计划：

- 本轮 Agent B 本地运行 `git diff --check`、JSON 解析、Koharu validator smoke，并用轻量 Swift parse 检查新增 Swift 语法。
- 未跑本机 build / 探针，按规则交给云端验证。
- 云端 `AITRANS CI Results` `ci-fast` 应证明 `koharuNativeBubbleMaskInstanceLiteReport.enabled = true`、`evaluatedBlockCount == totalBlocksDetected`、`blockLedgerCount == totalBlocksDetected`、`gateCount >= 8`、`nativeInstanceLite = true`、`proxyNotRealKoharuBubbleMask = true`、`usesSourceImagePixels = true`、`groundTruthUsedForDecision = false`、核心 breakdown 非空或像素证据不足时明确 blocked / warning gate，convergence 包含 v1.43 reference / work item / gate，且 `1_ocr_probe_text.txt` 包含 summary、instance ledger、逐块 block ledger、sibling 和 adjacency ledger。

遗留事项：

- 旧仓库根 `output/` 不含 v1.43 新字段；以 PR 后云端结果包为准。
- v1.43 仍是 native BubbleMask instance-lite report-only 影子复刻，不代表真实 Koharu `BubbleMask` / `TextBoxes` / `SegmentMask` 已接入，也不代表 OCR 或翻译质量改善。
- 本轮未重新跑完整漫画探针，不追加 `metrics/version_history.csv` 漫画指标行。

### v1.42：Native TextBox Detector-Lite 闭环裁决与结构路由
日期：2026-07-03
依据：`md/prompt/v1（漫画探针）/v1.42（NativeTextBoxDetectorLite闭环裁决与结构路由）.md`。本轮修改 Swift 探针报告模型、detector-lite 闭环裁决与结构路由账本、Koharu convergence 联动、TXT 快照和核心文档；不刷新仓库根 `output/`，不追加 `metrics/version_history.csv`，完整 build / 探针交给 GitHub Actions。

核心变更：

- 新增 `koharuNativeTextBoxDetectorLiteClosedLoopReport`，在 v1.41 refinement 之后、最终 convergence 刷新前生成。
- 报告消费 v1.39 detector-lite、v1.40 shadow OCR、v1.41 refinement、final blocks、BubbleMask / SegmentMask proxy、翻译失败分类、Translation Model Floor、Render Regression Lock 和 external artifact readiness，产出 candidate family ledger、逐块 closed-loop route、stoplist、full-probe review、真实 artifact 需求、模型地板和 render lock 路由。
- route / nextAction / gate / candidate family verdict 只使用 ground-truth-free decision signals；ground truth 只写入 evaluationSignals。
- `koharuArtifactConvergenceReport.referenceReports` 新增 `koharuNativeTextBoxDetectorLiteClosedLoopReport`；convergence 新增 `WI-koharu-native-textbox-detector-lite-closed-loop-router` 和 `G-koharu-native-textbox-detector-lite-closed-loop-router-executed`。
- `1_ocr_probe_text.txt` 新增 detector-lite closed-loop report summary、candidate family rollup 和逐块 `nativeTextBoxDetectorLiteClosedLoopBlockLedger`。
- 本轮不新增 OCR / LLM / PNG，不更换模型，不接入外部 artifact，不改变主 OCR、翻译输入、覆盖图、`finalTextUsedForTranslation`、`blockPassed`、失败分类、`textRegionCropReport.adoptedCount`、active artifacts 或 `configuration.currentBlockSource`。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`
- `md/prompt/v1（漫画探针）/v1.42（NativeTextBoxDetectorLite闭环裁决与结构路由）.md`

验证计划：

- 本轮 Agent B 本地运行 `git diff --check`、JSON 解析、Koharu validator smoke，并用轻量 Swift 解析检查新增 Swift 语法。
- 未跑本机 build / 探针，按规则交给云端验证。
- 云端 `AITRANS CI Results` `ci-fast` 应证明 `koharuNativeTextBoxDetectorLiteClosedLoopReport.enabled = true`、`evaluatedBlockCount == totalBlocksDetected`、`blockLedgerCount == totalBlocksDetected`、`candidateFamilyCount == totalBlocksDetected`、`gateCount >= 8`，核心 route / verdict / bottleneck / nextAction breakdown 非空或上游缺失时明确 `blockedByMissingUpstreamReports`，convergence 包含 v1.42 reference / work item / gate，且 `1_ocr_probe_text.txt` 包含 summary、candidate family 和逐块 block ledger。

遗留事项：

- 旧仓库根 `output/` 不含 v1.42 新字段；以 PR 后云端结果包为准。
- v1.42 仍是 detector-lite report-only 路由，不代表真实 Koharu TextBoxes / BubbleMask / SegmentMask 已接入，也不代表模型质量改善。
- 本轮未重新跑完整漫画探针，不追加 `metrics/version_history.csv` 漫画指标行。

### v1.41：Native TextBox Detector-Lite 闭环二次候选与 Refinement Shadow OCR
日期：2026-07-02
依据：`md/prompt/v1（漫画探针）/v1.41（NativeTextBoxDetectorLite闭环二次候选与RefinementShadowOCR）.md`。本轮修改 Swift 探针报告模型、detector-lite refinement shadow OCR 链路、Koharu convergence 联动、TXT 快照和核心文档；不刷新仓库根 `output/`，不追加 `metrics/version_history.csv`，完整 build / 探针交给 GitHub Actions。

核心变更：

- 新增 `koharuNativeTextBoxDetectorLiteRefinementReport`，执行顺序在 v1.40 `koharuNativeTextBoxDetectorLiteShadowOCRReport` 之后、最终 `koharuArtifactConvergenceReport` refresh 之前。
- target selection 只使用 v1.40 shadow OCR outcome、block failure category、模型地板、渲染锁和 detector-lite relation 等 ground-truth-free 信号；ground truth 只写入 evaluation signals。
- refined candidate bbox 只从 v1.39 `nativeDetectorLite` 父候选出发，用 source image 暗像素 envelope、projection band、directional padding 和 bubble ID 一致时的保守 bubble clip 二次收紧。
- `ci-fast` 总 refinement OCR 预算限制为 `<= min(6,totalBlocksDetected)`，每块最多 1 个；`full` 每块最多 2 个且仍有总上限。
- candidate / block ledger 输出 base bbox、refined bbox、refinement strategy、target reason、OCR raw / normalized text、quality delta vs current / detector-lite shadow、word preservation、evaluation-only ground truth similarity delta、outcome 和 report-only rejection reasons。
- `koharuArtifactConvergenceReport.referenceReports` 新增 `koharuNativeTextBoxDetectorLiteRefinementReport`；convergence 新增 `WI-koharu-native-textbox-detector-lite-refinement` 和 `G-koharu-native-textbox-detector-lite-refinement-executed`。
- `1_ocr_probe_text.txt` 新增 detector-lite refinement report summary、refined candidate ledger 和逐块 `nativeTextBoxDetectorLiteRefinementBlockLedger`。
- 本轮不新增 LLM 调用，不更换模型，不接入外部 artifact，不改变主 OCR、翻译输入、覆盖图、`finalTextUsedForTranslation`、`blockPassed`、失败分类、`textRegionCropReport.adoptedCount`、active artifacts 或 `configuration.currentBlockSource`。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`
- `md/prompt/v1（漫画探针）/v1.41（NativeTextBoxDetectorLite闭环二次候选与RefinementShadowOCR）.md`

验证计划：

- 本轮 Agent B 本地运行 `git diff --check`、JSON 解析、Koharu validator smoke，并用轻量 Swift parse 检查新增 Swift 语法。
- 未跑本机 build / 探针，按规则交给云端验证。
- 云端 `AITRANS CI Results` `ci-fast` 应证明 `koharuNativeTextBoxDetectorLiteRefinementReport.enabled = true`、`evaluatedBlockCount == totalBlocksDetected`、`blockLedgerCount == totalBlocksDetected`、`ocrExecutedCount <= min(6,totalBlocksDetected)`、`gateCount >= 8`，核心 breakdown 非空或无 target 时明确 blocked ledger，convergence 包含 v1.41 reference / work item / gate，且 `1_ocr_probe_text.txt` 包含 summary、candidate ledger 和逐块 block ledger。

遗留事项：

- 旧仓库根 `output/` 不含 v1.35-v1.41 新字段；以 PR 后云端结果包为准。
- v1.41 仍是 detector-lite refinement shadow-only，不代表真实 Koharu TextBoxes / BubbleMask / SegmentMask 已接入，也不代表模型质量改善。
- 本轮未重新跑完整漫画探针，不追加 `metrics/version_history.csv` 漫画指标行。

### v1.40：Native TextBox Detector-Lite Shadow OCR 评估闭环
日期：2026-07-02
依据：`md/prompt/v1（漫画探针）/v1.40（NativeTextBoxDetectorLiteShadowOCR评估闭环）.md`。本轮修改 Swift 探针报告模型、受限 detector-lite crop OCR 评估链路、Koharu convergence 联动、TXT 快照和核心文档；不刷新仓库根 `output/`，不追加 `metrics/version_history.csv`，完整 build / 探针交给 GitHub Actions。

核心变更：

- 新增 `koharuNativeTextBoxDetectorLiteShadowOCRReport`，只消费 v1.39 `koharuNativeTextBoxDetectorLiteReport.candidates` 中 `shadowOCREligible = true` 的 `nativeDetectorLite` 候选。
- `ci-fast` 每块最多执行 1 个 detector-lite bbox OCR，`full` 每块最多 2 个；候选选择只使用 detector-lite score、bubble / glyph / block 关系、direction hint 和 ledger 信号。
- candidate ledger 输出 source candidate、bbox、crop padding、scale、OCR raw / normalized text、empty / failed / succeeded、word preservation、quality delta、evaluation-only ground truth similarity delta、outcome 和 report-only rejection reasons。
- block ledger 覆盖所有最终 blocks，记录 selected candidate、shadow OCR text、当前 / shadow OCR quality、better / worse / same / empty / failed / notSelected、primary bottleneck、nextAction 和 whyNotPromoted。
- 报告明确 `groundTruthUsedForDecision = false`、`groundTruthUsedForEvaluationOnly = true`、`wouldChangeMainFlow = false`、`diagnosticOnly = true`、`proxyNotRealKoharuTextBoxes = true`、`proxyNotRealKoharuOCR = true`；ground truth 只进 evaluation signals。
- `koharuArtifactConvergenceReport.referenceReports` 新增 `koharuNativeTextBoxDetectorLiteShadowOCRReport`；convergence 新增 `WI-koharu-native-textbox-detector-lite-shadow-ocr` 和 `G-koharu-native-textbox-detector-lite-shadow-ocr-executed`。
- `1_ocr_probe_text.txt` 新增 detector-lite shadow OCR report summary、candidate OCR ledger 和逐块 `nativeTextBoxDetectorLiteShadowOCRBlockLedger`。
- 本轮不新增 LLM 调用，不更换模型，不使用 ground truth 决定候选、排序、OCR 执行、nextAction 或 gate，不改变主 OCR、翻译输入、覆盖图、`finalTextUsedForTranslation`、`blockPassed`、失败分类、`textRegionCropReport.adoptedCount`、active artifacts 或 `configuration.currentBlockSource`。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`
- `md/prompt/v1（漫画探针）/v1.40（NativeTextBoxDetectorLiteShadowOCR评估闭环）.md`

验证计划：

- 本轮 Agent B 本地运行 `git diff --check`、JSON 解析、Koharu validator smoke，并用轻量 Swift 解析检查新增 Swift 语法。
- 未跑本机 build / 探针，按规则交给云端验证。
- 云端 `AITRANS CI Results` `ci-fast` 应证明 `koharuNativeTextBoxDetectorLiteShadowOCRReport.enabled = true`、`evaluatedBlockCount == totalBlocksDetected`、`blockLedgerCount == totalBlocksDetected`、`selectedCandidateCount <= totalBlocksDetected`、`ocrExecutedCount == selectedCandidateCount`、`gateCount >= 8`，核心 breakdown 非空或无候选时明确 blocked ledger，convergence 包含 v1.40 reference / work item / gate，且 `1_ocr_probe_text.txt` 包含 summary、candidate ledger 和逐块 block ledger。

遗留事项：

- 旧仓库根 `output/` 不含 v1.35-v1.40 新字段；以 PR 后云端结果包为准。
- shadow OCR 可能全部 empty / worse；这属于本轮要显式记录的评估结果，不能静默跳过，也不能因此替换主流程。
- 本轮未重新跑完整漫画探针，不追加 `metrics/version_history.csv` 漫画指标行。

### v1.39：Koharu Native TextBox Detector-Lite 预 OCR 影子复刻
日期：2026-07-02
依据：`md/prompt/v1（漫画探针）/v1.39（KoharuNativeTextBoxDetectorLite预OCR影子复刻）.md`。本轮修改 Swift 探针报告模型、像素 / 几何候选层、Koharu convergence 联动、TXT 快照和核心文档；不刷新仓库根 `output/`，不追加 `metrics/version_history.csv`，完整 build / 探针交给 GitHub Actions。

核心变更：

- 新增 `koharuNativeTextBoxDetectorLiteReport`，只用 source image 像素、bubble geometry、BubbleMask proxy 和 glyph / SegmentMask proxy 生成 OCR 前 `nativeDetectorLite` TextBox 候选。
- 候选输出 `candidateID`、bbox、sourceBubbleID、directionHint、dark pixel density、connected component count、projection peak count、bubble coverage、glyph overlap、score、verdict、shadow OCR eligibility、matched / related block indexes、decision / evaluation signals 和 rejection reasons。
- 新增 block / bubble / gate ledger，逐块记录 best candidate、coverage verdict、bubble assignment risk、segment evidence、OCR input risk、model floor、render lock、primary bottleneck 和 next action；逐 bubble 记录 coverage、split / sibling risk 和 real BubbleMask 需求。
- 报告明确 `groundTruthUsedForDecision = false`、`wouldChangeMainFlow = false`、`diagnosticOnly = true`、`proxyNotRealKoharuTextBoxes = true`、`externalArtifactsRequiredForThisReport = false`；ground truth 只进入 evaluation signals。
- 默认不执行 detector-lite shadow OCR，不新增 LLM 调用；不使用 Vision OCR 文本、`test/1.ground_truth.json`、pre-crop plan、line plan 或 TextRegion crop 结果生成 / 排序候选。
- `koharuArtifactConvergenceReport.referenceReports` 新增 `koharuNativeTextBoxDetectorLiteReport`；convergence 新增 `WI-koharu-native-textbox-detector-lite` 和 `G-koharu-native-textbox-detector-lite-executed`。
- `1_ocr_probe_text.txt` 新增 detector-lite report summary、candidate ledger、bubble ledger 和逐块 `nativeTextBoxDetectorLiteBlockLedger`。
- 本轮不改变主 OCR、whole-page / bubble-first 融合、post-fusion cleanup、翻译输入、translation prompt、模型、`blockPassed`、失败分类、覆盖绘制、`safeLayoutRect`、`textRegionCropReport.adoptedCount`、active artifacts 或 `configuration.currentBlockSource`。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`
- `md/prompt/v1（漫画探针）/v1.39（KoharuNativeTextBoxDetectorLite预OCR影子复刻）.md`

验证计划：

- 本轮 Agent B 本地运行 `swiftc -parse`、`git diff --check`、JSON 解析和 Koharu validator smoke。
- 未跑本机 build / 探针，按规则交给云端验证。
- 云端 `AITRANS CI Results` `ci-fast` 应证明 `koharuNativeTextBoxDetectorLiteReport.enabled = true`、`evaluatedBlockCount == totalBlocksDetected`、`blockLedgerCount == totalBlocksDetected`、`candidateCount >= 1`、`gateCount >= 8`，breakdown 非空，`groundTruthUsedForDecision = false`、`wouldChangeMainFlow = false`、`diagnosticOnly = true`、`proxyNotRealKoharuTextBoxes = true`，convergence 包含 detector-lite reference / work item / gate，且 `1_ocr_probe_text.txt` 包含 summary、candidate ledger、bubble ledger 和逐块 block ledger。

遗留事项：

- 旧仓库根 `output/` 不含 v1.35-v1.39 新字段；以 PR 后云端结果包为准。
- 本轮未重新跑完整漫画探针，不追加 `metrics/version_history.csv` 漫画指标行。

### v1.38：Koharu RenderSprite 排版适配影子复刻
日期：2026-07-02
依据：`md/prompt/v1（漫画探针）/v1.38（KoharuRenderSprite排版适配影子复刻）.md`。本轮修改 Swift 探针报告模型、Koharu convergence 联动、TXT 快照和核心文档；不刷新仓库根 `output/`，不追加 `metrics/version_history.csv`，完整 build / 探针交给 GitHub Actions。

退回修复：

- PR #28 云端 run `28571459833` 在 Xcode build 阶段失败，`xcodebuild.log` 指向 `MangaOverlayProbeService.swift` 中 `MangaKoharuRenderSpriteLayoutCandidateLedger(...)` 大表达式 type-check 超时，后续模拟器安装因缺 bundle ID 连带失败，探针未运行且结果包只保留 `output/probe-not-run.txt`。
- 修复方式是把 RenderSprite layout candidate ledger 的嵌套 `flatMap` / `map` / struct 初始化拆成显式局部 helper 和 `for` 循环，先落地 `candidateID`、`candidateArea`、`areaDeltaVsCurrent`、`decisionSignals`、`evaluationSignals` 等中间变量；字段语义和 report-only 输出不变。
- 本修复不改主 OCR、翻译输入、覆盖绘制、`safeLayoutRect`、DistanceField safe rect、`renderFontSize`、`renderNonTransparentBounds`、`blockPassed`、失败分类、active artifacts 或 `configuration.currentBlockSource`。
- Build IPA #94 run `28574373590` 在合并 commit `902e836` 的 Release archive / `iphoneos` / whole-module optimization 阶段失败，`xcodebuild-archive.log` 指向 `MangaOverlayProbeService.swift:1744` 的 `Task.detached` 大闭包 type-check 超时，并提示该 `await` 内没有 async 操作。本次修复移除 `makeKoharuBubbleAdjacencySeamReport` 外层无必要 `Task.detached` / `.value` 包装，保留原报告计算、字段和 report-only 语义；不改主 OCR、翻译输入、覆盖绘制、`safeLayoutRect`、DistanceField safe rect、RenderSprite fit planner、`blockPassed`、失败分类、active artifacts 或 `configuration.currentBlockSource`。

核心变更：

- 新增 `koharuRenderSpriteFitPlannerReport`，只基于 AITRANS 现有 `safeLayoutRect`、`renderFontSize`、`renderNonTransparentBounds`、render collision、失败 fallback 文本、v1.30 Render Regression Lock、v1.35 BubbleIndex、v1.36 DistanceField 和 v1.37 seam 证据，构建 RenderedSprites 字体预算、换行压力、sprite containment、layout candidate、same-bubble sibling fit 和 failure overlay fit 账本。
- 报告输出 `blockLedgers[]`、`layoutCandidateLedgers[]`、`siblingLedgers[]` 和 `gateLedger[]`，记录 `translationCandidate` / `failureFallback` 渲染文本来源、字符统计、候选 rect、字体预算、seam / sibling / render lock 风险、proxy boundary 和 report-only next action。
- 报告明确 `groundTruthUsedForDecision = false`、`wouldChangeMainFlow = false`、`diagnosticOnly = true`、`proxyNotRealKoharuRenderer = true`、`proxyNotRealBubbleMask = true`；ground truth 只进入 evaluation signals。
- `koharuArtifactConvergenceReport.referenceReports` 新增 `koharuRenderSpriteFitPlannerReport`；convergence 新增 `WI-koharu-render-sprite-fit-planner` 和 `G-koharu-render-sprite-fit-planner-executed`。
- `1_ocr_probe_text.txt` 新增 RenderSprite fit planner summary、layout candidate、sibling fit group 和逐块 `renderSpriteFit`。
- 报告只做 report-only 诊断；不新增 OCR / LLM，不重新渲染 PNG，不改变主 OCR、翻译输入、覆盖图、`safeLayoutRect`、DistanceField safe rect、`renderFontSize`、`renderNonTransparentBounds`、`glyphMaskFillRects`、背景填充、`blockPassed`、失败分类、post-fusion cleanup、候选选择、active artifacts 或 `configuration.currentBlockSource`。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`
- `md/prompt/v1（漫画探针）/v1.38（KoharuRenderSprite排版适配影子复刻）.md`

验证计划：

- 本轮 Agent B 本地运行 `swiftc -parse`、`git diff --check`、JSON 解析和 Koharu validator smoke。
- 未跑本机 build / 探针，按规则交给云端验证。
- 云端 `AITRANS CI Results` `ci-fast` 应证明 `koharuRenderSpriteFitPlannerReport.enabled = true`、`evaluatedBlockCount == totalBlocksDetected`、`blockLedgerCount == totalBlocksDetected`、`layoutCandidateCount >= totalBlocksDetected`、`gateCount >= 10`，breakdown 非空，`proxyNotRealKoharuRenderer = true`、`proxyNotRealBubbleMask = true`，convergence 包含 RenderSprite fit planner reference / work item / gate，且 `1_ocr_probe_text.txt` 包含 summary、layout candidate、sibling fit 和逐块 block ledger。

遗留事项：

- 旧仓库根 `output/` 不含 v1.35-v1.38 新字段；以 PR 后云端结果包为准。
- 本轮未重新跑完整漫画探针，不追加 `metrics/version_history.csv` 漫画指标行。

### v1.37：Koharu 气泡邻接切缝影子复刻
日期：2026-07-02
依据：`md/prompt/v1（漫画探针）/v1.37（Koharu气泡邻接切缝影子复刻）.md`。本轮修改 Swift 探针报告模型、Koharu convergence 联动、TXT 快照和核心文档；不刷新仓库根 `output/`，不追加 `metrics/version_history.csv`，完整 build / 探针交给 GitHub Actions。

退回修复：

- PR #27 云端 run `28564459237` 中 static checks、Xcode build 和 simulator build 通过，但 `mangaProbeOutcome=failure`；`manga-probe.log` 停在 `render-output-start` 后，最终未生成 `probe_report.json`。
- 修复 `koharuBubbleAdjacencySeamReport` 的 proxy mask gap 计算：从整图 mask 像素全量收集 + 双重循环，改为 bubble bbox 内边界采样、样本上限和远距离 bbox gap 近似，保持 report-only 语义和字段含义。
- 在 render 后 Koharu 后置报告链新增进度点，覆盖 BubbleIndex、DistanceField、Bubble adjacency seam、最终 convergence refresh、TXT 重写和 `probe_report` 写入起点，便于云端失败时定位具体卡点。

核心变更：

- 新增 `koharuBubbleAdjacencySeamReport`，只基于 AITRANS 现有 rounded-rect BubbleMask proxy、BubbleIndex、DistanceField、split candidate、same-bubble sibling、OCR damage 和 render lock 证据，构建 bubble adjacency graph、seam candidate ledger 和逐块 seam 风险账本。
- 报告输出 `pairLedgers[]`、`seamCandidateLedgers[]`、`blockLedgers[]` 和 `gateLedger[]`，记录 bbox gap / overlap、proxy mask gap、shared split / sibling / conflict 信号、seam orientation / corridor、assignment conflict、safe-area risk、render lock 和 report-only next action。
- 报告明确 `proxyNotRealBubbleMask = true`、`usesRoundedRectProxyMask = true`、`groundTruthUsedForDecision = false`、`wouldChangeMainFlow = false` 和 `diagnosticOnly = true`；ground truth 只进入 evaluation signals。
- `koharuArtifactConvergenceReport.referenceReports` 新增 `koharuBubbleAdjacencySeamReport`；convergence 新增 `WI-koharu-bubble-adjacency-seam` 和 `G-koharu-bubble-adjacency-seam-executed`。
- `1_ocr_probe_text.txt` 新增 Bubble adjacency seam summary、pair ledger、seam candidate ledger 和逐块 `bubbleSeamBlockLedger`。
- 报告只做 report-only 诊断；不新增 OCR / LLM，不改变主 OCR、翻译输入、覆盖图、`safeLayoutRect`、DistanceField safe rect、`glyphMaskFillRects`、背景填充、`blockPassed`、失败分类、post-fusion cleanup、候选选择、active artifacts 或 `configuration.currentBlockSource`。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`
- `md/prompt/v1（漫画探针）/v1.37（Koharu气泡邻接切缝影子复刻）.md`

验证计划：

- 本轮 Agent B 本地运行 `swiftc -parse`、`git diff --check`、JSON 解析和 Koharu validator smoke。
- 未跑本机 build / 探针，按规则交给云端验证。
- 云端 `AITRANS CI Results` `ci-fast` 应证明 `koharuBubbleAdjacencySeamReport.enabled = true`、`evaluatedBlockCount == totalBlocksDetected`、`evaluatedBubbleCount == bubbleMaskReport.instanceCount`、`blockLedgerCount == totalBlocksDetected`、`pairLedgerCount >= 1`、`seamCandidateCount >= bubbleSplitCandidateReport.candidateCount`、`gateCount >= 10`，breakdown 非空，`proxyNotRealBubbleMask = true`、`usesRoundedRectProxyMask = true`，convergence 包含 Bubble adjacency seam reference / work item / gate，且 `1_ocr_probe_text.txt` 包含 summary、pair ledger、seam candidate 和逐块 block ledger。

遗留事项：

- 旧仓库根 `output/` 不含 v1.37 新字段；以 PR 后云端结果包为准。
- 本轮未重新跑完整漫画探针，不追加 `metrics/version_history.csv` 漫画指标行。

### v1.36：Koharu DistanceField 安全区影子复刻
日期：2026-07-02
依据：`md/prompt/v1（漫画探针）/v1.36（KoharuDistanceField安全区影子复刻）.md`。本轮修改 Swift 探针报告模型、Koharu convergence 联动、TXT 快照和核心文档；不刷新仓库根 `output/`，不追加 `metrics/version_history.csv`，完整 build / 探针交给 GitHub Actions。

核心变更：

- 新增 `koharuDistanceFieldSafeAreaReport`，只基于 AITRANS 现有 rounded-rect BubbleMask proxy ID mask，在每个 bubble bbox 内计算 two-pass chamfer 8-neighbor distance field、safe pixels、safe pixel bbox 和 histogram maximum safe rect。
- 报告输出 bubble / block / same-bubble sibling 三层 ledger，对比当前 `safeLayoutRect`、v1.35 `koharuBubbleIndexShadowLedgerReport` 的 shadow safe rect、distance-field safe rect、render sprite containment、render lock 和 split / sibling 风险。
- 报告明确 `proxyNotRealBubbleMask = true`、`usesRoundedRectProxyMask = true`、`groundTruthUsedForDecision = false`、`wouldChangeMainFlow = false` 和 `diagnosticOnly = true`；ground truth 只进入 evaluation signals。
- `koharuArtifactConvergenceReport.referenceReports` 新增 `koharuDistanceFieldSafeAreaReport`；convergence 新增 `WI-koharu-distance-field-safe-area` 和 `G-koharu-distance-field-safe-area-executed`。
- `1_ocr_probe_text.txt` 新增 DistanceField summary、safe pixel / safe rect / sprite containment breakdown、bubble ledger、sibling ledger 和逐块 `distanceFieldBlockLedger`。
- 报告只做 report-only 诊断；不新增 OCR / LLM，不改变主 OCR、翻译输入、覆盖图、`safeLayoutRect`、`glyphMaskFillRects`、背景填充、`blockPassed`、失败分类、post-fusion cleanup、候选选择、active artifacts 或 `configuration.currentBlockSource`。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`
- `md/prompt/v1（漫画探针）/v1.36（KoharuDistanceField安全区影子复刻）.md`

验证计划：

- 本轮 Agent B 本地运行 `swiftc -parse`、`git diff --check`、JSON 解析和 Koharu validator smoke。
- 未跑本机 build / 探针，按规则交给云端验证。
- 云端 `AITRANS CI Results` `ci-fast` 应证明 `koharuDistanceFieldSafeAreaReport.enabled = true`、`evaluatedBlockCount == totalBlocksDetected`、`bubbleLedgerCount == bubbleMaskReport.instanceCount`、`blockLedgerCount == totalBlocksDetected`、`gateCount >= 10`，breakdown 非空，`proxyNotRealBubbleMask = true`、`usesRoundedRectProxyMask = true`，convergence 包含 DistanceField reference / work item / gate，且 `1_ocr_probe_text.txt` 包含 summary、bubble ledger、sibling ledger 和逐块 block ledger。

遗留事项：

- 旧仓库根 `output/` 不含 v1.36 新字段；以 PR 后云端结果包为准。
- 本轮未重新跑完整漫画探针，不追加 `metrics/version_history.csv` 漫画指标行。

### v1.35：Koharu BubbleIndex 影子账本与安全区复刻
日期：2026-07-01
依据：`md/prompt/v1（漫画探针）/v1.35（KoharuBubbleIndex影子账本与安全区复刻）.md`。本轮修改 Swift 探针报告模型、Koharu convergence 联动、TXT 快照和核心文档；不刷新仓库根 `output/`，不追加 `metrics/version_history.csv`，完整 build / 探针交给 GitHub Actions。

核心变更：

- 新增 `koharuBubbleIndexShadowLedgerReport`，从现有 BubbleMask proxy、BubbleMask 归属修正、split candidate、reading order、BubbleMask assignment / split scoreboard、render lock、native replay matrix 和最终 blocks 聚合 Koharu BubbleIndex 影子账本。
- 报告输出 block / bubble / same-bubble sibling 三层 ledger，审计当前 `bubbleID`、shadow majority bubble、mask-safe rect 对照、同气泡 sibling 分区、split 风险、render lock、primary bottleneck 和 next action。
- 报告明确 `proxyNotRealBubbleMask = true`，ground truth 只进 evaluation signals，不参与 assignment、safe area、sibling partition、gate 或 next action 决策。
- `koharuArtifactConvergenceReport.referenceReports` 新增 `koharuBubbleIndexShadowLedgerReport`；convergence 新增 `WI-koharu-bubble-index-shadow-ledger` 和 `G-koharu-bubble-index-shadow-ledger-executed`。
- `1_ocr_probe_text.txt` 新增 BubbleIndex summary、assignment / safe-area / sibling breakdown、bubble ledger、sibling ledger 和逐块 `koharuBubbleIndexBlockLedger`。
- 报告只做 report-only 诊断；不新增 OCR / LLM，不改变主 OCR、翻译输入、覆盖图、`safeLayoutRect`、`blockPassed`、失败分类、post-fusion cleanup、候选选择、glyph mask、背景填充、active artifacts 或 `configuration.currentBlockSource`。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`
- `md/prompt/v1（漫画探针）/v1.35（KoharuBubbleIndex影子账本与安全区复刻）.md`

验证计划：

- 本轮 Agent B 本地运行 `swiftc -parse`、`git diff --check`、JSON 解析和 Koharu validator smoke。
- 退回修复：PR #25 云端 run `28523199970` 在 `TranslationSessionStore.swift` 的 `MangaKoharuWorkOrderBlockRoute` 大表达式 type-check 超时；本轮拆分 work order route 与 BubbleIndex block ledger 的 signal / evaluation / mustNotPromote 子表达式，保持 report-only 语义不变。
- 未跑本机 build / 探针，按规则交给云端验证。
- 云端 `AITRANS CI Results` `ci-fast` 应证明 `koharuBubbleIndexShadowLedgerReport.enabled = true`、`evaluatedBlockCount == totalBlocksDetected`、`blockLedgerCount == totalBlocksDetected`、`evaluatedBubbleCount == bubbleMaskReport.instanceCount`、`bubbleLedgerCount == bubbleMaskReport.instanceCount`、`gateCount >= 12`，breakdown 非空，`proxyNotRealBubbleMask = true`，convergence 包含 BubbleIndex reference / work item / gate，且 `1_ocr_probe_text.txt` 包含 summary、bubble ledger、sibling ledger 和逐块 block ledger。

遗留事项：

- 旧仓库根 `output/` 不含 v1.35 新字段；以 PR 后云端结果包为准。
- 本轮未重新跑完整漫画探针，不追加 `metrics/version_history.csv` 漫画指标行。

### v1.34：Koharu 本地算法复刻执行矩阵与探针评估账本
日期：2026-07-01
依据：`md/prompt/v1（漫画探针）/v1.34（Koharu本地算法复刻执行矩阵与探针评估账本）.md`。本轮修改 Swift 探针报告模型、Koharu convergence 联动、TXT 快照和核心文档；不刷新仓库根 `output/`，不追加 `metrics/version_history.csv`，完整 build / 探针交给 GitHub Actions。

核心变更：

- 新增 `koharuNativeAlgorithmReplayMatrixReport`，从 resolver、work order router、external artifact request packet、convergence、TextBox / BubbleMask / SegmentMask scoreboards、translation floor、render lock、diagnostics 和最终 blocks 聚合 Koharu 本地算法复刻执行矩阵。
- 报告固定输出 canonical stage matrix，覆盖 `SourceImage`、`ContentCrop`、`TextBoxes`、`BubbleMask`、`SegmentMask`、`OcrText`、`Translations`、`RenderedSprites`、`FinalRender` 和 `ExternalArtifacts`。
- 报告固定输出 replay candidates，覆盖融合主流程审计、post-fusion / OCR 质量路由、TextBox stoplist、BubbleMask 归属 / 分割、SegmentMask 覆盖、translation model floor、render lock 和 external artifact handoff。
- 每块新增 replay route，记录 primary candidate、primary Koharu stage、bottleneck、external / model floor / render lock / stoplist 状态和 next action。
- `koharuArtifactConvergenceReport.referenceReports` 新增 `koharuNativeAlgorithmReplayMatrixReport`；convergence 新增 `WI-koharu-native-algorithm-replay-matrix` 和 `G-koharu-native-algorithm-replay-matrix-executed`。
- `1_ocr_probe_text.txt` 新增 replay matrix summary、`candidateQueue`、`stageMatrix` 和逐块 `koharuNativeReplayRoute`。
- 报告只做 report-only 诊断；不新增 OCR / LLM，不改变主 OCR、翻译输入、覆盖图、`blockPassed`、失败分类、post-fusion cleanup、候选选择、safe layout、glyph mask、背景填充、active artifacts 或 `configuration.currentBlockSource`。ground truth 只进入 evaluation signals，不参与 candidate status、budget、gate、route 或 next action。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`
- `md/prompt/v1（漫画探针）/v1.34（Koharu本地算法复刻执行矩阵与探针评估账本）.md`

验证计划：

- 本轮 Agent B 本地运行 `swiftc -parse`、`git diff --check`、JSON 解析和 Koharu validator smoke。
- 未跑本机 build / 探针，按规则交给云端验证。
- 云端 `AITRANS CI Results` `ci-fast` 应证明 `koharuNativeAlgorithmReplayMatrixReport.enabled = true`、`evaluatedBlockCount == totalBlocksDetected`、`stageCount >= 10`、`candidateCount >= 9`、`blockRouteCount == totalBlocksDetected`、`gateCount >= 14`，固定 candidate queue 存在，缺 active artifact 时 external candidate blocked，crop / line / deskew stoplist 仍关闭，model floor / OCR / render lock 分开路由，convergence 包含 replay matrix reference / work item / gate，且 `1_ocr_probe_text.txt` 包含 summary、candidate queue、stage matrix 和逐块 route。

遗留事项：

- 旧仓库根 `output/` 不含 v1.34 新字段；以 PR 后云端结果包为准。
- 本轮未重新跑完整漫画探针，不追加 `metrics/version_history.csv` 漫画指标行。

### v1.33：Koharu 外部 Artifact 请求包与准入缺口账本
日期：2026-07-01
依据：`md/prompt/v1（漫画探针）/v1.33（Koharu外部Artifact请求包与准入缺口账本）.md`。本轮修改 Swift 探针报告模型、Koharu convergence 联动、TXT 快照和核心文档；不刷新仓库根 `output/`，不追加 `metrics/version_history.csv`，完整 build / 探针交给 GitHub Actions。

核心变更：

- 新增 `koharuExternalArtifactRequestPacketReport`，从 v1.32 `koharuWorkOrderRouterReport`、external readiness gate、external TextBox shadow OCR、TextBox / BubbleMask / SegmentMask scoreboards、render lock、translation floor、convergence 和最终 blocks 聚合真实外部 artifact 请求包。
- 固定枚举 active `test/koharu_artifacts/` 四件套：`1.manifest.json`、`1.textboxes.json`、`1.bubbles.json`、`1.segment_mask.json`，并为每个 required file 写出 schema 字段、坐标系、解析/契约状态、validator command、blocked reason、next action 和 forbidden sources。
- 新增 `artifactRequirements[]` 覆盖真实 `TextBoxes`、`BubbleMask`、`SegmentMask`，明确当前 proxy 只能作为 why-needed / current limitation 证据，不能冒充 Koharu detector artifact。
- 新增逐块 `blockRequests[]`，每块记录 primary work order、primary bottleneck、needs TextBoxes / BubbleMask / SegmentMask、external readiness、external shadow OCR gate、stoplist、model floor、render lock、manual review、current proxy evidence、missing real artifact reasons、forbidden local actions 和 next action。
- `koharuArtifactConvergenceReport.referenceReports` 新增 `koharuExternalArtifactRequestPacketReport`；convergence 新增 `WI-koharu-external-artifact-request-packet` 和 `G-koharu-external-artifact-request-packet-executed`。
- `1_ocr_probe_text.txt` 新增 request packet summary、`requiredFiles` 摘要、`artifactRequirements` 摘要和逐块 `koharuExternalArtifactRequest` 行。
- 报告只做 report-only 诊断；不创建、复制、修改或提交 active `test/koharu_artifacts/`，不新增 OCR / LLM，不改变主 OCR、翻译输入、覆盖图、`blockPassed`、失败分类、post-fusion cleanup、候选选择、safe layout、glyph mask、背景填充、渲染逻辑或 `configuration.currentBlockSource`。ground truth 只进入 evaluation signals，不参与 request、gate、next action 或 promotion 决策。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`
- `md/prompt/v1（漫画探针）/v1.33（Koharu外部Artifact请求包与准入缺口账本）.md`

验证计划：

- 本轮 Agent B 本地运行 `swiftc -parse`、`git diff --check`、JSON 解析和 Koharu validator smoke。
- 未跑本机 build / 探针，按规则交给云端验证。
- 云端 `AITRANS CI Results` `ci-fast` 应证明 `koharuExternalArtifactRequestPacketReport.enabled = true`、`evaluatedBlockCount == totalBlocksDetected`、`requiredFileCount >= 4`、`artifactRequirementCount >= 3`、`blockRequestCount == totalBlocksDetected`、`gateCount >= 13`，缺 active artifact 时 verdict 为 missing / waiting / blocked 类状态，required files 覆盖四件套，requirements 覆盖 TextBoxes / BubbleMask / SegmentMask，forbidden sources 非空，convergence 包含 request packet reference / work item / gate，且 `1_ocr_probe_text.txt` 包含 request packet summary、required files、artifact requirements 和逐块 request。

遗留事项：

- 旧仓库根 `output/` 不含 v1.33 新字段；以 PR 后云端结果包为准。
- 本轮未重新跑完整漫画探针，不追加 `metrics/version_history.csv` 漫画指标行。

### v1.32：Koharu WorkOrder Router 执行工作单与收益预算
日期：2026-07-01
依据：`md/prompt/v1（漫画探针）/v1.32（KoharuWorkOrderRouter执行工作单与收益预算）.md`。本轮修改 Swift 探针报告模型、Koharu convergence 联动、TXT 快照和核心文档；不刷新仓库根 `output/`，不追加 `metrics/version_history.csv`，完整 build / 探针交给 GitHub Actions。

核心变更：

- 新增 `koharuWorkOrderRouterReport`，从 v1.31 `koharuPipelineResolverReport` 派生固定 work orders、逐块 routes、budget ledger 和 gate ledger。
- 固定 work order 覆盖 resolver ledger 收口、本地 crop / line / deskew stoplist、真实 TextBoxes / BubbleMask / SegmentMask 请求、render lock 保持、translation model floor handoff、external artifact package handoff 和 manual review。
- 逐块 route 输出 primary / secondary work order、primary bottleneck、模型地板、render lock、stoplist、真实 artifact 需求、CI/full/external 预算和下一步动作。
- `koharuArtifactConvergenceReport.referenceReports` 新增 `koharuWorkOrderRouterReport`；convergence 新增 `WI-koharu-workorder-router` 和 `G-koharu-workorder-router-executed`。
- `1_ocr_probe_text.txt` 新增 router report summary、`workOrderQueue` 摘要和逐块 `koharuWorkOrderRoute` 行。
- 报告只做 report-only 诊断；不新增 OCR / LLM、不改变主 OCR、翻译输入、覆盖图、`blockPassed`、失败分类、post-fusion cleanup、候选选择、safe layout、glyph mask、背景填充或 `configuration.currentBlockSource`。ground truth 只进入 evaluation signals，不参与 work order routing、priority、budget 或 next action。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`
- `md/prompt/v1（漫画探针）/v1.32（KoharuWorkOrderRouter执行工作单与收益预算）.md`

验证计划：

- 本轮 Agent B 本地运行 `swiftc -parse`、`git diff --check`、JSON 解析和 Koharu validator smoke。
- 未跑本机 build / 探针，按规则交给云端验证。
- 云端 `AITRANS CI Results` `ci-fast` 应证明 `koharuWorkOrderRouterReport.enabled = true`、`evaluatedBlockCount == totalBlocksDetected`、`workOrderCount >= 7`、`blockRouteCount == totalBlocksDetected`、`gateCount >= 10`，breakdown 非空，缺 active artifact 时 external work orders 保持 blocked/missing，convergence 包含 router reference / work item / gate，且 `1_ocr_probe_text.txt` 包含 router summary、work order queue 和逐块 route。

遗留事项：

- 旧仓库根 `output/` 不含 v1.32 新字段；以 PR 后云端结果包为准。
- 本轮未重新跑完整漫画探针，不追加 `metrics/version_history.csv` 漫画指标行。

### v1.31：Koharu Pipeline Resolver 影子 DAG 阶段调度与阻塞传播
日期：2026-07-01
依据：`md/prompt/v1（漫画探针）/v1.31（KoharuPipelineResolver影子DAG阶段调度与阻塞传播）.md`。本轮修改 Swift 探针报告模型、Koharu convergence 联动、TXT 快照和核心文档；不刷新仓库根 `output/`，不追加 `metrics/version_history.csv`，完整 build / 探针交给 GitHub Actions。

核心变更：

- 新增 `koharuPipelineResolverReport`，用 Koharu `EngineInfo.needs / produces`、DAG resolver 和 Op preview 的结构组织现有 AITRANS 探针证据。
- 报告输出 `nodes[]`、`edges[]`、逐块 `blockTraces[]`、`executionQueue[]`、`opPreviews[]` 和 `gateLedger[]`，覆盖 SourceImage、ContentCrop、Vision OCR、BubbleCandidates、BubbleMask/TextBox/SegmentMask proxy、OcrText、FusionCleanup、Translations、GlyphErase proxy、RenderedSprites proxy、FinalRender 和 ExternalArtifacts。
- 逐块 trace 输出 `firstBlockedNodeID`、`firstBlockedReason`、downstream blocked nodes、recommended execution item、next action、requires external artifact 和 stoplisted local tuning 状态。
- `koharuArtifactConvergenceReport.referenceReports` 新增 `koharuPipelineResolverReport`；convergence 新增 `WI-koharu-pipeline-resolver-shadow-dag` 和 `G-koharu-pipeline-resolver-executed`。
- `1_ocr_probe_text.txt` 新增 resolver report summary、`resolverExecutionQueue` 摘要和逐块 `koharuPipelineResolverTrace` 行。
- 报告只做 report-only 诊断；不新增 OCR / LLM、不改变主 OCR、翻译输入、覆盖图、`blockPassed`、失败分类、post-fusion cleanup、候选选择、safe layout、glyph mask、背景填充或 `configuration.currentBlockSource`。ground truth 只进入 evaluation signals，不参与 resolver 决策。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`
- `md/prompt/v1（漫画探针）/v1.31（KoharuPipelineResolver影子DAG阶段调度与阻塞传播）.md`

验证计划：

- 本轮 Agent B 本地运行 `swiftc -parse`、`git diff --check`、JSON 解析和 Koharu validator smoke。
- 未跑本机 build / 探针，按规则交给云端验证。
- 云端 `AITRANS CI Results` `ci-fast` 应证明 `koharuPipelineResolverReport.enabled = true`、`evaluatedBlockCount == totalBlocksDetected`、`nodeCount >= 12`、`edgeCount >= 12`、`blockTraceCount == totalBlocksDetected`、`executionQueueCount >= 6`、`opPreviewCount >= 4`、`gateCount >= 8`，breakdown 非空，`externalArtifacts` 缺 active artifact 时保持 blocked/missing，convergence 包含 resolver reference / work item / gate，且 `1_ocr_probe_text.txt` 包含 resolver summary、execution queue 和逐块 trace。

遗留事项：

- 旧仓库根 `output/` 不含 v1.31 新字段；以 PR 后云端结果包为准。
- 本轮未重新跑完整漫画探针，不追加 `metrics/version_history.csv` 漫画指标行。

### v1.30：Koharu Render Regression Lock 覆盖渲染回归锁与 FinalRender 账本
日期：2026-07-01
依据：`md/prompt/v1（漫画探针）/v1.30（KoharuRenderRegressionLock覆盖渲染回归锁与FinalRender账本）.md`。本轮修改 Swift 探针报告模型、Koharu convergence 联动、TXT 快照和核心文档；不刷新仓库根 `output/`，不追加 `metrics/version_history.csv`，完整 build / 探针交给 GitHub Actions。

核心变更：

- 新增 `koharuRenderRegressionLockReport`，执行 v1.28 未闭合的 `WI-render-regression-lock`。
- 报告聚合现有 final blocks、`safeLayoutRect`、mask-safe rect、render collision、render mask overflow、glyph mask、background fill、失败块 fallback 覆盖文本和 App 沙盒输出文件状态，输出 RenderedSprites / FinalRender 回归锁。
- 顶层输出 `renderLockVerdict`、render / safe layout / background fill / glyph mask / failure overlay / output file breakdown、核心输出文件状态、逐块 `blockLocks[]`、`artifactStages[]`、`outputFileChecks[]` 和 `gateLedger[]`。
- `koharuArtifactConvergenceReport.referenceReports` 新增 `koharuRenderRegressionLockReport`；`WI-render-regression-lock` 可从 v1.28 的未执行 open 状态推进为 `closedReportOnly` 或 `openRenderIssueDetected`，并同步 `G-render-regression-lock-executed` gate。
- `1_ocr_probe_text.txt` 新增报告级 render lock summary、render issue / output file 摘要、convergence render work item 摘要和逐块 `renderLock` 行。
- 报告只做 report-only 诊断；不重新渲染、不解析 PNG 像素证明逐块文字、不新增 OCR / LLM、不改变主 OCR、主翻译、覆盖图、`blockPassed`、失败分类、post-fusion cleanup、候选选择、`safeLayoutRect`、`glyphMaskFillRects`、背景填充行为、渲染逻辑或 `configuration.currentBlockSource`。`proxyNotRealKoharuRenderer = true` 表示 AITRANS 当前不是 Koharu 真实 renderer、RenderedSprites artifact 或 inpainting。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`
- `md/prompt/v1（漫画探针）/v1.30（KoharuRenderRegressionLock覆盖渲染回归锁与FinalRender账本）.md`

验证计划：

- 本轮 Agent B 本地运行 `swiftc -parse`、`git diff --check`、JSON 解析和 Koharu validator smoke。
- 未跑本机 build / 探针，按规则交给云端验证。
- 云端 `AITRANS CI Results` `ci-fast` 应证明 `koharuRenderRegressionLockReport.enabled = true`、`evaluatedBlockCount == totalBlocksDetected`、`blockLocks.count == totalBlocksDetected`、`artifactStages.count >= 5`、`gateLedger.count >= 13`、`outputFileChecks` 覆盖核心 JSON/TXT/PNG，`failureOverlayRequiredBlocks` 覆盖所有失败块，`koharuArtifactConvergenceReport.referenceReports` 包含新 report，`WI-render-regression-lock` 不再只是 v1.28 未执行 open 状态，且 `1_ocr_probe_text.txt` 包含新 summary、逐块 `renderLock` 和 convergence render work item 摘要。

遗留事项：

- 旧仓库根 `output/` 不含 v1.30 新字段；以 PR 后云端结果包为准。
- 本轮未重新跑完整漫画探针，不追加 `metrics/version_history.csv` 漫画指标行。

### v1.29：Translation Model Floor 对照矩阵与 Koharu 翻译地板账本
日期：2026-07-01
依据：`md/prompt/v1（漫画探针）/v1.29（TranslationModelFloor对照矩阵与Koharu翻译地板账本）.md`。本轮修改 Swift 探针报告模型、deterministic clean text strict prompt 诊断、Koharu convergence work item 联动、TXT 快照和核心文档；不刷新仓库根 `output/`，不追加 `metrics/version_history.csv`，完整 build / 探针交给 GitHub Actions。

核心变更：

- 新增 `translationModelFloorComparisonReport`，执行 v1.28 未闭合的 `WI-translation-model-floor-comparison`。
- 报告复用 `cleanTextDiagnostic` 的 dialogue baseline cases，额外运行 deterministic `strictChineseOnlyV1` prompt 变体，记录 baseline / variant prompt、raw output、candidate、raw / candidate classification、failure reasons、pass state 和 prompt variant outcome。
- 报告聚合 noisy final blocks、v1.19 `routingDrivenTranslationComparisonReport`、`batchTranslationComparison` 和 `koharuArtifactConvergenceReport` work item，输出 `floorVerdict`、clean/noisy 计数、prompt outcome breakdown、failure reason breakdown 和 gate ledger。
- `koharuArtifactConvergenceReport.referenceReports` 新增 `translationModelFloorComparisonReport`，`WI-translation-model-floor-comparison` 可从 v1.28 的未执行 open 状态推进为 `closedReportOnly` 或 `openModelFloorConfirmed`；这只表示对照账本已执行，不表示模型质量问题已解决。
- `1_ocr_probe_text.txt` 新增报告级 `translationModelFloorComparisonReport` summary、逐条 `translationFloorCleanCase` 和逐块 `translationFloorNoisyBlock` 摘要。
- 报告只做 report-only 诊断；clean text ground truth 只用于模型地板评估，不参与 noisy OCR 候选选择、主 prompt、主译文、覆盖图、`blockPassed`、失败分类、质量规则、模型选择或 metrics history。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`
- `md/prompt/v1（漫画探针）/v1.29（TranslationModelFloor对照矩阵与Koharu翻译地板账本）.md`

验证计划：

- 本轮 Agent B 本地运行 `swiftc -parse`、`git diff --check`、JSON 解析和 Koharu validator smoke。
- 未跑本机 build / 探针，按规则交给云端验证。
- 云端 `AITRANS CI Results` `ci-fast` 应证明 `translationModelFloorComparisonReport.enabled = true`、`evaluatedCleanCaseCount == cleanTextDiagnostic.totalCases`、`evaluatedNoisyBlockCount == totalBlocksDetected`、`baselinePassRate == cleanTextDiagnostic.passRate`、`floorVerdict` 和 breakdown 非空、`gateLedger.count >= 9`、`koharuArtifactConvergenceReport.referenceReports` 包含新 report、`WI-translation-model-floor-comparison` 不再只是 v1.28 未执行 open 状态，且 `1_ocr_probe_text.txt` 包含新 summary、clean case 摘要和逐块 noisy block 摘要。

遗留事项：

- 旧仓库根 `output/` 不含 v1.29 新字段；以 PR 后云端结果包为准。
- 本轮未重新跑完整漫画探针，不追加 `metrics/version_history.csv` 漫画指标行。

### v1.28：Koharu Artifact 收敛矩阵与下一步决策账本
日期：2026-07-01
依据：`md/prompt/v1（漫画探针）/v1.28（KoharuArtifact收敛矩阵与下一步决策账本）.md`。本轮修改 Swift 探针报告模型、诊断 TXT 和核心文档；不刷新仓库根 `output/`，不追加 `metrics/version_history.csv`，完整 build / 探针交给 GitHub Actions。

核心变更：

- 新增 `koharuArtifactConvergenceReport`，聚合 v1.22 `koharuArtifactDAGReport`、v1.23 `koharuStageGapReplicationReport`、v1.24 `koharuNativeReplicationScoreboardReport`、v1.25 `nativeTextBoxProxyLedgerReport`、v1.26 `bubbleMaskAssignmentSplitScoreboardReport`、v1.27 `segmentMaskProxyCoverageScoreboardReport`、external artifact readiness、clean text diagnostic、diagnostics 和最终 blocks。
- 报告顶层输出 `source = AITRANSProbe`、`referencePipeline = Koharu`、`groundTruthUsedForDecision = false`、`groundTruthUsedForEvaluationOnly = true`、`wouldChangeMainFlow = false`、`diagnosticOnly = true` 和 `externalArtifactsRequiredForThisReport = false`。
- `stages[]` 输出 SourceImage、ContentCrop、TextBoxes、BubbleMask、SegmentMask、OcrText、Translations、Inpainted、RenderedSprites、FinalRender 和 ExternalArtifacts 的 convergence matrix。
- `blockPaths[]` 为每个最终块输出 TextBox / BubbleMask / SegmentMask / OCR / translation / render 状态、`firstBlockingArtifact`、`primaryStructuralBottleneck`、model floor、render lock、real artifact 需求和下一步 action。
- `workItemLedger[]` 固定收束 `WI-native-textbox-artifact-scorecard`、`WI-bubblemask-assignment-split-scorecard`、`WI-segmentmask-proxy-coverage-scorecard`，并把未闭合项集中到 `WI-translation-model-floor-comparison`、`WI-render-regression-lock` 和 `WI-external-artifact-optional-handoff`。
- `gateLedger[]` 固定包含 no-main-flow-mutation、no-ground-truth-decision、v1.25 / v1.26 / v1.27 work item closure、translation model floor open、render regression lock open、external artifact optional、proxy boundary 和 ci-fast report availability。
- `1_ocr_probe_text.txt` 新增报告级 `koharuArtifactConvergenceReport` summary 和逐块 `koharuArtifactPath` 摘要。
- 报告只复用既有探针证据，不新增 OCR / LLM 调用；不改变主 OCR、翻译输入、覆盖图、`blockPassed`、失败分类、post-fusion cleanup、候选选择、`safeLayoutRect`、`glyphMaskFillRects`、背景填充行为、渲染逻辑或 `configuration.currentBlockSource`。ground truth 只进入 evaluationSignals，不参与 firstBlockingArtifact、primaryNextAction、work item status 或 gate。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`
- `md/prompt/v1（漫画探针）/v1.28（KoharuArtifact收敛矩阵与下一步决策账本）.md`

验证计划：

- 本轮 Agent B 本地运行 `swiftc -parse`、`git diff --check`、JSON 解析和 Koharu validator smoke。
- 未跑本机 build / 探针，按规则交给云端验证。
- 云端 `AITRANS CI Results` `ci-fast` 应证明 `koharuArtifactConvergenceReport.enabled = true`、`evaluatedBlockCount == totalBlocksDetected`、`stageCount >= 9`、`blockPathCount == totalBlocksDetected`、`workItemLedgerCount >= 6`、`gateCount >= 10`，关键 breakdown 非空，前三个 proxy work item 在 `closedWorkItems` 中，open work items 至少包含 translation model floor、render regression lock 或 external optional handoff，且 `1_ocr_probe_text.txt` 包含新 summary 和逐块 `koharuArtifactPath`。

遗留事项：

- 旧仓库根 `output/` 不含 v1.28 新字段；以 PR 后云端结果包为准。
- 本轮未重新跑完整漫画探针，不追加 `metrics/version_history.csv` 漫画指标行。

### v1.27：SegmentMask Proxy 覆盖评分板与 Glyph 清字边界账本
日期：2026-07-01
依据：`md/prompt/v1（漫画探针）/v1.27（SegmentMaskProxy覆盖评分板与Glyph清字边界账本）.md`。本轮修改 Swift 探针报告模型、诊断 TXT 和核心文档；不刷新仓库根 `output/`，不追加 `metrics/version_history.csv`，完整 build / 探针交给 GitHub Actions。

核心变更：

- 新增 `segmentMaskProxyCoverageScoreboardReport`，执行 v1.24 的 `WI-segmentmask-proxy-coverage-scorecard`，聚合现有 glyph mask、SegmentMask proxy、TextBox 覆盖、BubbleMask 覆盖、safe rect、背景填充和渲染碰撞证据。
- 报告顶层输出 `source = AITRANSProbe`、`referenceWorkItemID = WI-segmentmask-proxy-coverage-scorecard`、`referenceKoharuArtifact = SegmentMask`、`groundTruthUsedForDecision = false`、`groundTruthUsedForEvaluationOnly = true`、`wouldChangeMainFlow = false`、`diagnosticOnly = true` 和 `proxyNotRealSegmentMask = true`。
- `blockScorecards[]` 为每个最终块输出 coverage status、cleanup status、render mask status、glyph / TextBox / BubbleMask / safe rect 覆盖、background fill、render collision、TextBox / BubbleMask ledger 状态、must-not-promote reasons 和 nextAction。
- `cleanupLedgers[]` 采用每个最终块一条的稳定计数规则，记录 glyph 清字边界、background fill guardrail、allowed cleanup use、blocked cleanup reasons、`inpaintingImplemented = false` 和 `proxyOnly = true`。
- `gateLedger[]` 固定包含 no-main-flow-mutation、no-ground-truth-decision、proxy boundary、glyph available、TextBox / BubbleMask / safe rect coverage、background fill guardrail、render mask collision、TextBox ledger boundary、BubbleMask boundary 和 real SegmentMask artifact boundary。
- `1_ocr_probe_text.txt` 新增报告级 `segmentMaskProxyCoverageScoreboardReport` summary 和逐块 `segmentMaskProxyScoreboard` 摘要。
- 报告只复用既有探针证据，不新增 OCR / LLM 调用；不改变主 OCR、翻译输入、覆盖图、`blockPassed`、失败分类、post-fusion cleanup、候选选择、`safeLayoutRect`、`glyphMaskFillRects`、背景填充行为、`textRegionCropReport.adoptedCount` 或 `configuration.currentBlockSource`。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`
- `md/prompt/v1（漫画探针）/v1.27（SegmentMaskProxy覆盖评分板与Glyph清字边界账本）.md`

验证计划：

- 本轮 Agent B 本地运行 `swiftc -parse`、`git diff --check`、JSON 解析和 Koharu validator smoke。
- 未跑本机 build / 探针，按规则交给云端验证。
- 云端 `AITRANS CI Results` `ci-fast` 应证明 `segmentMaskProxyCoverageScoreboardReport.enabled = true`、`evaluatedBlockCount == totalBlocksDetected`、`glyphMaskBlockCount == segmentMaskReport.glyphMaskBlocks`、`blockScorecards.count == totalBlocksDetected`、`cleanupLedgerCount >= glyphMaskBlockCount`、`gateLedger.count >= 12`，关键 breakdown 非空，`proxyNotRealSegmentMask = true`，且 `1_ocr_probe_text.txt` 包含新 summary 和逐块 `segmentMaskProxyScoreboard`。

遗留事项：

- 旧仓库根 `output/` 不含 v1.27 新字段；以 PR 后云端结果包为准。
- 本轮未重新跑完整漫画探针，不追加 `metrics/version_history.csv` 漫画指标行。

### v1.26：BubbleMask 归属分割评分板与 Sibling 布局账本
日期：2026-07-01
依据：`md/prompt/v1（漫画探针）/v1.26（BubbleMask归属分割评分板与Sibling布局账本）.md`。本轮修改 Swift 探针报告模型、诊断 TXT 和核心文档；不刷新仓库根 `output/`，不追加 `metrics/version_history.csv`，完整 build / 探针交给 GitHub Actions。

核心变更：

- 新增 `bubbleMaskAssignmentSplitScoreboardReport`，执行 v1.24 的 `WI-bubblemask-assignment-split-scorecard`，聚合现有 BubbleMask proxy、归属修正、split candidate、reading order、structure action、Koharu native scoreboard 和 Native TextBox ledger 证据。
- 报告顶层输出 `source = AITRANSProbe`、`referenceWorkItemID = WI-bubblemask-assignment-split-scorecard`、`referenceKoharuArtifact = BubbleMask`、`groundTruthUsedForDecision = false`、`groundTruthUsedForEvaluationOnly = true`、`wouldChangeMainFlow = false` 和 `diagnosticOnly = true`。
- `blockScorecards[]` 为每个最终块输出 assignment status、split risk、same-bubble sibling layout、mask safe rect、render mask status、TextBox ledger status、decision / evaluation signals、must-not-promote reasons 和 nextAction。
- `bubbleScorecards[]` 为每个 BubbleMask proxy 实例输出 blocks、冲突块、归属修正块、split candidate、same-bubble sibling groups、render overflow、instance status 和 primary risk。
- `splitCandidateLedgers[]` 和 `siblingLayoutScorecards[]` 把既有 split candidate 与同气泡 sibling 布局整理成 report-only 账本，不扩大 crop clamp，不改 `safeLayoutRect`。
- `gateLedger[]` 固定包含 no-main-flow-mutation、no-ground-truth-decision、assignment consistency、correction report-only、split report-only、sibling layout、render mask collision、protected text、TextBox ledger boundary 和 real artifact boundary。
- `1_ocr_probe_text.txt` 新增报告级 `bubbleMaskAssignmentSplitScoreboardReport` summary 和逐块 `bubbleMaskScoreboard` 摘要。
- 报告只复用既有探针证据，不新增 OCR / LLM 调用；不改变主 OCR、翻译输入、覆盖图、`blockPassed`、失败分类、post-fusion cleanup、候选选择、`safeLayoutRect` 或 `configuration.currentBlockSource`。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`
- `md/prompt/v1（漫画探针）/v1.26（BubbleMask归属分割评分板与Sibling布局账本）.md`

验证计划：

- 本轮 Agent B 本地运行 `swiftc -parse`、`git diff --check`、JSON 解析和 Koharu validator smoke。
- 退回修复：云端 run `28489045515` 在 `TranslationSessionStore.swift` 触发 Swift 编译失败，原因是 v1.26 scoreboard helper 对 `Bool` 字段 `bubbleIDConsistent` 调用了 `map`；已改为对可选 mask 本身转换为 `"true"` / `"false"` / `"nil"`，不改变报告语义或主流程。
- 未跑本机 build / 探针，按规则交给云端验证。
- 云端 `AITRANS CI Results` `ci-fast` 应证明 `bubbleMaskAssignmentSplitScoreboardReport.enabled = true`、`evaluatedBlockCount == totalBlocksDetected`、`evaluatedBubbleCount == bubbleMaskReport.instanceCount`、`blockScorecards.count == totalBlocksDetected`、`bubbleScorecards.count == bubbleMaskReport.instanceCount`、`splitCandidateLedgers.count == bubbleSplitCandidateReport.candidateCount`、`gateLedger.count >= 10`，关键 breakdown 非空，且 `1_ocr_probe_text.txt` 包含新 summary 和逐块 `bubbleMaskScoreboard`。

遗留事项：

- 旧仓库根 `output/` 不含 v1.26 新字段；以 PR 后云端结果包为准。
- 本轮未重新跑完整漫画探针，不追加 `metrics/version_history.csv` 漫画指标行。

### v1.25：Native TextBox Proxy 质量账本与候选冻结
日期：2026-06-30
依据：`md/prompt/v1（漫画探针）/v1.25（NativeTextBoxProxy质量账本与候选冻结）.md`。本轮修改 Swift 探针报告模型、诊断 TXT 和核心文档；不刷新仓库根 `output/`，不追加 `metrics/version_history.csv`，完整 build / 探针交给 GitHub Actions。

核心变更：

- 新增 `nativeTextBoxProxyLedgerReport`，执行 v1.24 的 `WI-native-textbox-artifact-scorecard`，聚合现有 TextBox / crop / line / BubbleMask / SegmentMask / OCR damage / v1.24 scoreboard 证据。
- 报告顶层输出 `source = AITRANSProbe`、`referenceWorkItemID = WI-native-textbox-artifact-scorecard`、`groundTruthUsedForDecision = false`、`groundTruthUsedForEvaluationOnly = true`、`wouldChangeMainFlow = false` 和 `diagnosticOnly = true`。
- `blockLedgers[]` 为每个最终块输出 qualityStatus、candidateSources、word preservation、protected keyword、bubble / segment / OCR damage / translation model / render gate、stoplist 命中、mustNotPromoteReasons 和 nextAction。
- `candidateLedgers[]` 汇总 fused seed bbox、TextRegion crop control、pre-crop TextBox plan、crop experiment shadow、line TextBox plan、line crop shadow 等既有候选证据；候选只做 report-only 账本，不写回主流程。
- `gateLedger[]` 固定包含 no-main-flow-mutation、no-ground-truth-decision、word preservation、protected keywords、stoplist freeze、bubble containment、segment support、OCR damage、model floor 和 render stability。
- `stoplist[]` 冻结已证伪的 crop / line / deskew 本地试参，过期条件只能是未来证据条件，不通过降低阈值解冻。
- `1_ocr_probe_text.txt` 新增报告级 `nativeTextBoxProxyLedgerReport` summary 和逐块 `nativeTextBoxProxyLedger` 摘要。
- 报告只复用既有探针证据，不新增 OCR / LLM 调用；不改变主 OCR、翻译输入、覆盖图、`blockPassed`、失败分类、post-fusion cleanup、候选选择或 `configuration.currentBlockSource`。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`
- `md/prompt/v1（漫画探针）/v1.25（NativeTextBoxProxy质量账本与候选冻结）.md`

验证计划：

- 本轮 Agent B 本地运行 `swiftc -parse`、`git diff --check`、JSON 解析和 Koharu validator smoke。
- 退回修复：云端 run `28452180814` 在 `TranslationSessionStore.swift` 触发 Swift 编译失败，原因是 v1.25 ledger helper 误读不存在的 `MangaOverlayTextRegionCropDiagnostic.candidatePreservesRawWords` 字段；已改为使用现有 `rawWordPreservationRatio >= 0.72` 推导，并移除同 helper 未使用的 BubbleMask 字典，不改变报告语义或主流程。
- 退回修复：云端 run `28453929047` 在 `makeNativeTextBoxProxyLedgerReport` 的 `blockLedgers` 大闭包触发 Swift 类型检查超时；已拆为显式 helper / 子表达式并改用显式循环生成 block ledger，同时清理 v1.24 scoreboard helper 未使用的 `mask` 变量，不改变报告语义或主流程。
- 未跑本机 build / 探针，按规则交给云端验证。
- 云端 `AITRANS CI Results` `ci-fast` 应证明 `nativeTextBoxProxyLedgerReport.enabled = true`、`evaluatedBlockCount == totalBlocksDetected`、`blockLedgers.count == totalBlocksDetected`、`gateLedger.count >= 10`，关键 breakdown 非空，stoplist 覆盖既有 crop / line stop blocks，且 `1_ocr_probe_text.txt` 包含新 summary 和逐块 `nativeTextBoxProxyLedger`。

遗留事项：

- 旧仓库根 `output/` 不含 v1.25 新字段；以 PR 后云端结果包为准。
- 本轮未重新跑完整漫画探针，不追加 `metrics/version_history.csv` 漫画指标行。

### v1.24：Koharu 本地复刻 Scoreboard 与 Gate Ledger
日期：2026-06-30
依据：`md/prompt/v1（漫画探针）/v1.24（Koharu本地复刻Scoreboard与GateLedger）.md`。本轮修改 Swift 探针报告模型、诊断 TXT 和核心文档；不刷新仓库根 `output/`，不追加 `metrics/version_history.csv`，完整 build / 探针交给 GitHub Actions。

核心变更：

- 新增 `koharuNativeReplicationScoreboardReport`，只用 AITRANS 自己的 probe 输出，把 v1.23 stage gap / work package 转成 stage scorecard、gate ledger、block scorecard 和下一轮 work items。
- 报告顶层输出 `source = AITRANSProbe`、`referencePipeline = Koharu`、`externalArtifactsRequiredForThisReport = false`、`groundTruthUsedForDecision = false` 和 `groundTruthUsedForEvaluationOnly = true`。
- `stageScorecards[]` 覆盖 `sourceImage`、`contentCrop`、`nativeTextBoxes`、`nativeBubbleMask`、`nativeSegmentMask`、`ocrText`、`translations`、`glyphEraseOrInpaintProxy`、`renderedSprites` 和 `finalRender`，区分 native / proxy / shadow / stop / model-limited / render-stable 状态。
- `gateLedger[]` 新增 no-main-flow-mutation、no-ground-truth-decision、native TextBox word preservation / stoplist、bubble conflict、SegmentMask inside bubble、clean text model floor、failure overlay、render no-overflow 和 external artifact optional 等 gate。
- `blockScorecards[]` 为每个最终块输出 OCR / bubble / segment / translation / render gate 状态、stoplist 证据、推荐 work item 和 next action；priority 和 nextAction 不读取 ground truth。
- `recommendedNextWorkItems[]` 明确把已证伪的 crop / line / deskew 本地试参加入 stoplist，下一步转向 native TextBox / BubbleMask / SegmentMask 评分、translation model floor 对照和 render regression lock。
- `1_ocr_probe_text.txt` 新增报告级 `koharuNativeReplicationScoreboardReport` summary 和逐块 `koharuNativeBlockScorecard` 摘要。
- 缺真实 `test/koharu_artifacts/` 只记为 `externalOptionalMissing` 可选外部路径，不阻塞 native scoreboard；但仍不能把 Vision OCR、pre-crop plan、line plan、BubbleMask proxy 或 SegmentMask proxy 冒充成真实 Koharu artifact。
- 报告只复用既有探针证据，不新增 OCR / LLM 调用；不改变主 OCR、翻译输入、覆盖图、`blockPassed`、失败分类、post-fusion cleanup、候选选择或 `configuration.currentBlockSource`。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`
- `md/prompt/v1（漫画探针）/v1.24（Koharu本地复刻Scoreboard与GateLedger）.md`

验证计划：

- 本轮 Agent B 本地运行 `swiftc -parse`、`git diff --check`、JSON 解析和 Koharu validator smoke。
- 未跑本机 build / 探针，按规则交给云端验证。
- 云端 `AITRANS CI Results` `ci-fast` 应证明 `koharuNativeReplicationScoreboardReport.enabled = true`、`evaluatedBlockCount == totalBlocksDetected`、`stageScorecardCount >= 9`、`gateCount >= 8`、`workItemCount >= 1`，关键 breakdown 非空，`externalArtifactsRequiredForThisReport = false`、`groundTruthUsedForDecision = false`、`groundTruthUsedForEvaluationOnly = true`，每个 `stageScorecards[]` / `gateLedger[]` 的决策字段不使用 ground truth，且 `1_ocr_probe_text.txt` 包含新 summary 和逐块 `koharuNativeBlockScorecard`。

遗留事项：

- 旧仓库根 `output/` 不含 v1.24 新字段；以 PR 后云端结果包为准。
- 本轮未重新跑完整漫画探针，不追加 `metrics/version_history.csv` 漫画指标行。

### v1.23：Koharu 阶段差距复刻计划与晋级门槛
日期：2026-06-30
依据：`md/prompt/v1（漫画探针）/v1.23（Koharu阶段差距复刻计划与晋级门槛）.md`。本轮修改 Swift 探针报告模型、诊断 TXT 和核心文档；不刷新仓库根 `output/`，不追加 `metrics/version_history.csv`，完整 build / 探针交给 GitHub Actions。

核心变更：

- 新增 `koharuStageGapReplicationReport`，把 v1.22 `koharuArtifactDAGReport` 转成 Koharu canonical stage 差距、work package、promotion gate 和逐块复刻计划。
- 报告覆盖 `sourceImage`、`contentCrop`、`textBoxes`、`bubbleMask`、`segmentMask`、`ocrText`、`translations`、`cleanTextDiagnostic`、`inpaintOrGlyphErase`、`renderedSprites` 和 `finalRender`。
- 每个 stage gap 写出当前 AITRANS 能力、artifact kind、source reports、gap category、replication readiness、最小输入、现有/缺失证据、受影响块、promotion gates、stop conditions 和推荐 work package。
- 每个 work package 写出优先级、目标阶段/块、是否可在 `ci-fast` 验证、是否需要 full probe、是否必须真实 external artifact、预期指标移动、rollback / stop 条件和非目标。
- 每个 block 输出 `firstBlockingStageFromDAG`、`primaryGapCategory`、目标 canonical stage、推荐 work package、最小证据、禁止晋级原因、是否需要 full / real artifact 和下一步动作。
- `1_ocr_probe_text.txt` 新增报告级 `koharuStageGapReplicationReport` summary 和逐块 `koharuStageGapPlan` 摘要。
- 报告只复用既有探针证据，不新增 OCR / LLM 调用；不改变主 OCR、翻译输入、覆盖图、`blockPassed`、失败分类、post-fusion cleanup、候选选择或 `configuration.currentBlockSource`。
- 缺真实 active `test/koharu_artifacts/` 时，真实 TextBoxes / BubbleMask / SegmentMask 仍保持 `manifestMissing` / `stopUntilArtifactsProvided` 阻塞，不能把 Vision OCR、pre-crop plan、line plan、BubbleMask proxy 或 SegmentMask proxy 冒充成 Koharu artifact。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`
- `md/prompt/v1（漫画探针）/v1.23（Koharu阶段差距复刻计划与晋级门槛）.md`

验证计划：

- 本轮 Agent B 本地运行 `swiftc -parse`、`git diff --check`、JSON 解析和 Koharu validator smoke。
- 未跑本机 build / 探针，按规则交给云端验证。
- 云端 `AITRANS CI Results` `ci-fast` 应证明 `koharuStageGapReplicationReport.enabled = true`、`evaluatedBlockCount == totalBlocksDetected`、`canonicalStageCount >= 9`、`workPackageCount >= 1`，关键 breakdown 非空，`stageGaps[].diagnosticOnly = true`、`stageGaps[].groundTruthUsedForPlanning = false`、`stageGaps[].wouldChangeMainFlow = false`，每个 promotion gate 的 `groundTruthUsedForDecision = false`，且 `1_ocr_probe_text.txt` 包含新 summary 和逐块 `koharuStageGapPlan`。

遗留事项：

- 旧仓库根 `output/` 不含 v1.23 新字段；以 PR 后云端结果包为准。
- 本轮未重新跑完整漫画探针，不追加 `metrics/version_history.csv` 漫画指标行。

### v1.22：Koharu 式 Artifact DAG 阶段账本与瓶颈闭环
日期：2026-06-30
依据：`md/prompt/v1（漫画探针）/v1.22（Koharu式ArtifactDAG阶段账本与瓶颈闭环）.md`。本轮修改 Swift 探针报告模型、诊断 TXT 和核心文档；不刷新仓库根 `output/`，不追加 `metrics/version_history.csv`，完整 build / 探针交给 GitHub Actions。

核心变更：

- 新增 `koharuArtifactDAGReport`，把 SourceImage、ContentCrop、Vision OCR、BubbleMask、TextBoxes、SegmentMask、OCR text、shadow crop、external artifact gate、translation、render layout 和 v1.21 结构动作候选组织成 Koharu 式 Artifact DAG 阶段账本。
- 报告级输出 dependency edges、stage summaries、stage status / artifact kind / first blocking stage / downstream impact breakdown，以及真实 artifact gate verdict / next action。
- 每块输出 `blockTraces[]`，包含 `firstBlockingStage`、`firstBlockingReason`、`downstreamImpacts`、关键 `stageTraces`、v1.21 候选 verdict 和 `recommendedNextAction`。
- 缺真实 active `test/koharu_artifacts/` 时，只把需要真实 TextBoxes / BubbleMask / SegmentMask 的 promotion 标为 `missingRequiredArtifact`，不把当前主流程整体判废。
- `1_ocr_probe_text.txt` 新增报告级 `koharuArtifactDAGReport` summary 和逐块 `koharuArtifactTrace` 摘要，便于不打开巨大 JSON 时定位首次阻塞阶段。
- 该报告只复用既有探针证据，不新增 OCR / LLM 调用；不改变主 OCR、翻译输入、覆盖图、`blockPassed`、失败分类、post-fusion cleanup 或候选选择。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`
- `md/prompt/v1（漫画探针）/v1.22（Koharu式ArtifactDAG阶段账本与瓶颈闭环）.md`

验证计划：

- 本轮 Agent B 本地运行 `swiftc -parse`、`git diff --check`、JSON 解析和 Koharu validator smoke。
- 退回修复：云端 run `28433914248` 在 `TranslationSessionStore.swift` 的 v1.22 DAG 报告构建处触发 Swift 6 编译失败；已改为显式 optional Bool 字符串转换、显式 closure 和多步局部统计，降低 type-check 压力，不改变报告语义或主流程。
- 未跑本机 build / 探针，按规则交给云端验证。
- 云端 `AITRANS CI Results` `ci-fast` 应证明 `koharuArtifactDAGReport.enabled = true`、`evaluatedBlockCount == totalBlocksDetected`、`stageCount >= 8`、`edgeCount >= 8`，关键 breakdown 非空，每条 dependency edge 的 `diagnosticOnly = true`、`wouldChangeMainFlow = false`，且 `1_ocr_probe_text.txt` 包含新 summary 和逐块 `koharuArtifactTrace`。

遗留事项：

- 旧仓库根 `output/` 不含 v1.22 新字段；以 PR 后云端结果包为准。
- 本轮未重新跑完整漫画探针，不追加 `metrics/version_history.csv` 漫画指标行。

### v1.21：结构动作候选矩阵与 Shadow 执行评估
日期：2026-06-30
依据：`md/prompt/v1（漫画探针）/v1.21（结构动作候选矩阵与Shadow执行评估）.md`。本轮修改 Swift 探针报告模型、诊断 TXT 和核心文档；不刷新仓库根 `output/`，不追加 `metrics/version_history.csv`，完整 build / 探针交给 GitHub Actions。

核心变更：

- 新增 `structureActionCandidateReport`，把 v1.20 `readingOrderStructureAuditReport` 的结构建议转成 shadow-only 候选矩阵。
- 候选类型覆盖 `readingOrderReindex`、`bubbleAssignmentReview`、`bubbleSplitShadow`、`sameBubbleSiblingLayout`、`duplicateFragmentProtection`、`textBoxEvidenceRequired`、`segmentMaskEvidenceRequired`、`renderSafeAreaReflow` 和 `manualReviewOnly`。
- 每个候选写出 `plannedOperation`、`expectedBenefit`、`executionMode`、control/shadow metrics、delta、`promotionVerdict`、`promotionBlockers` 和 `recommendedNextStep`。
- 报告级汇总 candidate type、promotion verdict、next step、report-only would improve、blocked、needs real artifact、render reflow、bubble split / assignment、duplicate protection 和 manual review blocks。
- `1_ocr_probe_text.txt` 新增报告级 `structureActionCandidateReport` summary 和每块 `structureActionCandidates` 摘要，包含跳过原因和 delta summary。
- 报告只复用已有几何、渲染和 shadow OCR 摘要，不新增 OCR / LLM 调用；不改变 `blocks` 顺序、batch 输入、`finalTextUsedForTranslation`、覆盖图、`blockPassed`、失败分类、post-fusion cleanup 或候选选择。
- 缺真实 Koharu TextBoxes / BubbleMask / SegmentMask artifact 时只输出阻塞和 `provideRealKoharuArtifact`，不得用 Vision OCR、pre-crop plan、line plan、BubbleMask proxy 或 SegmentMask proxy 冒充 detector 输出。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`
- `md/prompt/v1（漫画探针）/v1.21（结构动作候选矩阵与Shadow执行评估）.md`

验证计划：

- 本轮 Agent B 本地运行 `swiftc -parse`、`git diff --check`、JSON 解析和 Koharu validator smoke。
- 未跑本机 build / 探针，按规则交给云端验证。
- 云端 `AITRANS CI Results` `ci-fast` 应证明 `structureActionCandidateReport.enabled = true`、`evaluatedBlockCount == totalBlocksDetected`、`candidateCount >= 1`，关键 breakdown 非空，每个 candidate 的 `diagnosticOnly = true`、`groundTruthUsedForPlanning = false`、`wouldChangeMainFlow = false`，且 `1_ocr_probe_text.txt` 包含新 summary 和逐块摘要。

遗留事项：

- 旧仓库根 `output/` 不含 v1.21 新字段；以 PR 后云端结果包为准。
- 本轮未重新跑完整漫画探针，不追加 `metrics/version_history.csv` 漫画指标行。

### v1.20：阅读顺序与气泡归属结构计划审计
日期：2026-06-30
依据：`md/prompt/v1（漫画探针）/v1.20（阅读顺序与气泡归属结构计划审计）.md`。本轮修改 Swift 探针报告模型、诊断 TXT 和核心文档；不刷新仓库根 `output/`，不追加 `metrics/version_history.csv`，完整 build / 探针交给 GitHub Actions。

核心变更：

- 新增 `readingOrderStructureAuditReport`，从最终 blocks、bbox、safe layout、bubbleID、BubbleMask、TextBox / SegmentMask proxy、post-fusion cleanup 和 v1.18 / v1.19 路由证据现场计算阅读顺序与结构计划审计。
- 每块写出 `currentOrderIndex`、`proposedReadingOrderIndex`、`orderConfidence`、`bubbleGroupID`、同气泡 sibling、气泡归属风险、分割/合并风险、重复/碎片风险、保护标记、结构动作建议和 `mustNotPromoteReasons`。
- 报告级汇总 `orderChangedBlocks`、`lowConfidenceOrderBlocks`、`multiBlockBubbleGroups`、`maskConflictBlocks`、`splitRiskBlocks`、`duplicateOrFragmentRiskBlocks` 以及 TextBox / SegmentMask / 风险 / 动作 breakdown。
- `1_ocr_probe_text.txt` 新增报告级 `readingOrderStructureAuditReport` summary 和每块 `readingOrderStructureAudit` 摘要。
- 报告只做诊断，不改变 `blocks` 顺序、batch 输入、`finalTextUsedForTranslation`、翻译候选、`blockPassed`、失败分类、post-fusion cleanup 或覆盖图。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`
- `md/prompt/v1（漫画探针）/v1.20（阅读顺序与气泡归属结构计划审计）.md`

验证计划：

- 本轮 Agent B 本地运行 `swiftc -parse`、`git diff --check`、JSON 解析和 Koharu validator smoke。
- 未跑本机 build / 探针，按规则交给云端验证。
- 云端 `AITRANS CI Results` `ci-fast` 应证明 `readingOrderStructureAuditReport.enabled = true`、`evaluatedBlockCount == totalBlocksDetected`、`cases.count == totalBlocksDetected`，关键 breakdown 非空，`1_ocr_probe_text.txt` 包含新 summary 和逐块摘要，且 v1.18 / v1.19 报告仍存在。

遗留事项：

- 旧仓库根 `output/` 不含 v1.20 新字段；以 PR 后云端结果包为准。
- 阅读顺序启发式可能和漫画叙事顺序不一致，本轮只输出 report-only 风险和建议，不应用到主流程。

### v1.19：路由驱动翻译对照与 OCR 损坏审计
日期：2026-06-30
依据：`md/prompt/v1（漫画探针）/v1.19（路由驱动翻译对照与OCR损坏审计）.md`。本轮修改 Swift 探针报告模型和诊断 TXT；不刷新仓库根 `output/`，不追加 `metrics/version_history.csv`，完整 build / 探针交给 GitHub Actions。

核心变更：

- 新增 `routingDrivenTranslationComparisonReport`，从 v1.18 `internalStructureBottleneckReport` 中选择最多 5 个 `modelTranslationQuality` 块，运行 deterministic `strictChineseOnlyV1` prompt 对照。
- strict prompt 对照复用现有候选抽取、raw / candidate 分类、质量 checks、failure reasons 和 language quality gate，只记录 control / variant / improvement / blockers，不替换主流程 prompt、译文、`blockPassed`、失败分类或覆盖图。
- 新增 `ocrCharacterDamageAuditReport`，只审计 `ocrCharacterDamage`、`ocrInputSuspect` 或 `ocrGroundTruthSimilarity < 0.72` 的块，输出 damaged / missing / extra / substitution token、重复关键词损坏、line break risk、TextBox / SegmentMask 证据、crop blockers 和 recommended action。
- OCR 损坏审计允许使用 `test/1.ground_truth.json` 做探针诊断，但不参与生产候选选择、排序、cleanup、promotion 或文本替换。
- `1_ocr_probe_text.txt` 新增两个 report 的逐块摘要和报告级 summary。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`
- `md/prompt/v1（漫画探针）/v1.19（路由驱动翻译对照与OCR损坏审计）.md`

验证计划：

- 本轮 Agent B 本地运行 `swiftc -parse`、`git diff --check`、JSON 解析和 Koharu validator smoke。
- 未跑本机 build / 探针，按规则交给云端验证。
- 云端 `AITRANS CI Results` `ci-fast` 应证明两个新 report 都存在，`routingDrivenTranslationComparisonReport.evaluatedCaseCount <= 5`，`ocrCharacterDamageAuditReport.evaluatedBlockCount > 0`，`1_ocr_probe_text.txt` 包含逐块摘要，且 `configuration.currentBlockSource` 仍为 `fusedWholePageBubble`。

遗留事项：

- 旧仓库根 `output/` 不含 v1.19 新字段；以 PR 后云端结果包为准。
- strict prompt 对照可能变好、变差或无变化，均只作为诊断信号，不代表本轮主流程质量提升。

### v2.3：云端导入 GGUF 并运行漫画探针
日期：2026-06-29
依据：云端验证基础设施改造；本轮修改 CI 和 DEBUG 启动逻辑，不刷新仓库根 `output/`，不追加 `metrics/version_history.csv` 漫画指标行。

核心变更：

- `AITRANS CI Results` workflow 在下载并校验 Release GGUF 后，构建 Debug simulator app。
- workflow 动态选择可用 iOS runtime 和 iPhone simulator device type，创建临时模拟器并安装 `com.local.aitrans`。
- workflow 把 `.ci-models/gemma-3-270m-it-qat-Q4_0.gguf` 复制到 App sandbox `Application Support/Models/Gemma-1.5B/model.gguf`，并校验 SHA256。
- workflow 用 `AITRANS_RUN_MANGA_PROBE=1` 启动 App，等待 `probe_report.json`，校验 `engineUsed = Local GGUF`、`totalBlocksDetected > 0` 和 `blocks` 非空，然后导出本轮 `output/` 到未加密 CI 结果包。
- DEBUG 启动探针逻辑在发现本地模型已安装时自动切换 `selectedEngine = .local`，避免 CI 误用 Mock。
- workflow 将云端探针等待上限提高到 3600 秒，每分钟打印 App 沙盒 `Output` 快照和 `manga_probe_progress.json`，失败时也复制已有 `output/` 到结果包。
- workflow 若发现 `manga_probe_progress.json` 连续 10 分钟不更新，会提前收束日志并失败，避免 App 已启动但探针主任务未推进时空等 3600 秒。
- DEBUG 漫画探针会在 `Output/manga_probe_progress.json` 写入当前阶段、耗时和块数，便于判断卡在 OCR、翻译、渲染还是报告写入。
- DEBUG 启动探针现在会写入 `launch-task-start`、`probe-entry`、`probe-task-start` 等阶段；缺 `test/1.png`、重复运行和运行异常都会写入进度或失败报告，避免只有 `launch-trigger-received` 而没有后续证据。
- workflow 同时通过 `SIMCTL_CHILD_*`、`launchctl setenv`、普通 argv 和 `-AITRANS_RUN_MANGA_PROBE 1` UserDefaults 参数触发 DEBUG 探针；App 侧同时识别环境变量、启动参数和 UserDefaults，并在收到触发后立即写入 `launch-trigger-received` 进度。
- DEBUG 漫画探针启动时跳过 `refreshSpeechRecognitionCapabilities()`，避免云端启动先查询多语言 Speech asset，延迟或干扰探针触发。
- workflow 在开始探针前清空仓库根 `output/`，成功后必须从 App 沙盒导出新 `output/`，并强制校验 `probe_report.json`、`clean_text_diagnostic.json`、`1_ocr_probe_text.txt` 和关键 PNG，避免把 checkout 自带旧报告误当云端结果。
- workflow 在导入模型时打印 Release asset、历史目录路径、SHA256 校验和字节数，避免把 `Models/Gemma-1.5B` 目录名误判为 1.5B 模型。
- 结果包新增 `simulator-build.log`、`manga-probe.log`、`app-console.log`、`probe-device-id.txt`、`probe-app-container.txt`、`output/manga_probe_progress.json` 等排查线索。

关键文件：

- `.github/workflows/ci-results.yml`
- `AITRANS/Services/TranslationSessionStore.swift`
- `README.md`
- `md/test/test.md`
- `md/flow/flow.md`
- `update_log.md`

验证结果：

- 本轮应运行 `git diff --check`、`python3 -m json.tool test/1.ground_truth.json`、workflow smoke 和 YAML 解析。
- 本机不运行 Xcode build / 漫画探针；完整探针由推送后的 GitHub Actions 验证。

验收口径：

- 云端探针报告可解析。
- `engineUsed = Local GGUF`。
- `totalBlocksDetected > 0` 且 `blocks` 非空。
- `probe_report.json`、`clean_text_diagnostic.json`、`1_ocr_probe_text.txt` 和关键 PNG 上传到结果包。
- `overallPassed=false` 不单独视为 CI 失败，因为当前模型质量基线仍包含失败块。

已知云端尝试：

- run `28360252442` 在 commit `161383946abb1edcc5929b72df748aa3d5a7d44e` 上完成模型校验、静态检查、Xcode build 和 simulator build，但 `manga-probe.log` 显示 900 秒内未生成 `probe_report.json`，因此不作为通过结果。
- run `28361773796` 在 commit `0c22574dd060a3623e793e314648a4ca6ec55805` 上进入 `Run cloud manga probe` 后 App 已启动但 `Output` 目录持续为空；该现象指向启动触发未进入 App 探针入口，已取消并改为多触发。
- run `28363254764` 在 commit `0c3140b9960061083cec50e17a7538acfa900b49` 上因 workflow 内 `simctl spawn ps` 在 iOS 模拟器中不可用而提前失败；artifact 里的 `output/` 来自 checkout 旧文件，不作为云端探针通过结果。后续已改为清空旧 `output/` 并要求从 App 沙盒导出新结果。
- run `28363769439` 在 commit `5728c14b3dfb26570ff9e5fcbf9eb13cdd631a73` 上清空旧 `output/` 后仍未生成沙盒报告，已取消；App 日志显示启动早期在查询 Speech assets，因此后续跳过云端探针启动时的 Speech capability refresh。
- run `28364280623` 在 commit `3075339a63dad07e887a61c383268d2653c69eb5` 上模型下载、SHA256 校验、Xcode build 和 simulator build 均成功；`manga_probe_progress.json` 停在 `launch-trigger-received`，说明 App 已收到触发但未进入探针主任务。该 run 的模型文件位于历史目录 `Gemma-1.5B`，但 SHA256 和 `241410624` 字节大小确认实际是 Release 的 Gemma 270M GGUF，不是模型传错。
- `AITRANS - Build IPA` run `28364280582` 同 commit 的 archive 失败为 exit 65，GitHub step 只保留 `xcpretty` 摘要，缺少具体 Swift/link/sign 原始错误；workflow 已改为使用 latest stable Xcode、显式 `generic/platform=iOS` destination，并上传 `xcodebuild-archive.log`，同时不改变加密打包密码流程。
- 后续修复把等待上限、App 侧进度文件、停滞检测和日志收集补齐；验收必须看新 run 的 manifest 和 artifact。

遗留事项：

- 若 GitHub-hosted runner 的模拟器启动、App 容器读取或探针耗时不稳定，应优先查看 `manga-probe.log`、`app-console.log`、`output/manga_probe_progress.json` 和 `simulator-build.log`，再决定是否拆分成独立 probe workflow 或继续削减探针云端耗时。

### v1.13 / v22：外部 TextBoxes shadow OCR 候选接入
日期：2026-06-30
依据：`md/prompt/v1（漫画探针）/v1.13（外部TextBoxes Shadow OCR候选接入）.md`、PR #3、`AITRANS CI Results` run `28381772143`。本轮修改 Swift 报告模型和探针诊断链路；完整 build / 探针已由 GitHub Actions 验证，仓库根 `output/` 未刷新，长期指标追加到 `metrics/version_history.csv` v22 行。

核心变更：

- 新增 `MangaOverlayExternalTextBoxShadowOCRReport`、block summary 和 candidate report 模型。
- 探针在生成 `externalArtifactReadinessReport` 后运行 external TextBoxes shadow OCR gate；只有 `readinessVerdict = readyForShadowOCR`、`activeArtifactsDirectory = true`、`contractExampleOnly = false` 且 `externalTextBoxesShadowOCRAllowed = true` 才执行 OCR。
- 默认缺 `test/koharu_artifacts/` 时新 report 明确写 `executed = false`、`candidateCount = 0`、`ocrExecutedCount = 0`、所有块 skipped，阻塞原因来自 readiness verdict。
- readiness 通过时，每个 fused block 最多选择 1 个 `externalArtifact.textBoxCrop` candidate；选择只使用 external TextBox 与 block 的 IoU、中心点包含、confidence、bubble alignment 和面积比例等无真值信号。
- external TextBox crop 复用本地 Vision OCR，只把 OCR 文本、quality delta、word preservation、promotion blockers 和 report-only verdict 写入 `probe_report.json` 与 `1_ocr_probe_text.txt`。
- `promotedExternalShadowBlocks` 保持空；若候选满足既有 gate，只写 `wouldPromoteByExistingGateBlocks`，不替换 `finalTextUsedForTranslation`、主覆盖图、`blockPassed`、`configuration.currentBlockSource` 或 `textRegionCropReport.adoptedCount`。
- README、flow、flowchart 和 test 文档同步说明 real detector artifact、contract fixture、readiness gate、external shadow OCR report 和主流程之间的边界。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`

验证结果：

- Agent B 本地轻量检查通过：`git diff --check`、`python3 -m json.tool test/1.ground_truth.json`、`python3 -m json.tool output/probe_report.json`、`python3 -m json.tool output/clean_text_diagnostic.json`，以及 Koharu artifact validator valid / invalid / allow-missing。
- Agent C 核对 PR #3：base `smalldata_test`、head `codeb/v1.13-external-textbox-shadow-ocr`、head commit `790f72cfc05e354d65351827694748b5db3de0a3`。
- 云端 `AITRANS CI Results` run `28381772143` / attempt `1` 通过；manifest 匹配 `version = v1.13`、`branch = codeb/v1.13-external-textbox-shadow-ocr`、`commitSha = 790f72cfc05e354d65351827694748b5db3de0a3`、`workflowName = AITRANS CI Results`。
- 结果包 `aitrans-ci-v1.13-codeb-v1.13-external-textbox-shadow-ocr--790f72cfc05e-run28381772143-attempt1` 包含 `.xcresult`、`junit.xml`、`xcodebuild.log`、`simulator-build.log`、`manga-probe.log`、`app-console.log`、`ci-artifact-manifest.json`、`ci-failure-summary.md` 和 `output/`。
- `junit.xml`：5 tests、0 failures；GGUF download / verify、static checks、Xcode build、simulator build、manga probe 全部 success。
- 云端探针：`engineUsed = Local GGUF`、`decodingMode = deterministic`、`decodingSeed = 42`、`totalBlocksDetected = 13`、`outputDirectoryCleaned = true`、`overallPassed = false`。
- v1.13 gate 结果：`externalArtifactReadinessReport.readinessVerdict = manifestMissing`、`externalTextBoxesShadowOCRReport.executed = false`、`candidateCount = 0`、`ocrExecutedCount = 0`、`promotedExternalShadowBlocks = []`、`skippedBlocks = [0...12]`。
- 质量数字未因本轮 shadow-only gate 改变：`groundTruthMatchedBlocks = 13`、`groundTruthUnmatchedBlocks = 0`、`averageCoreDialogueOCRSimilarity = 0.7106`、`averageDecorativeOCRSimilarity = 0.8000`、`cleanTextDiagnostic.passRate = 0.4545`、`passedBlocks = 1`、`failedBlocks = 12`。
- `overallPassed = false` 仍来自当前 Gemma 270M / OCR 质量基线，不作为本轮 v1.13 gate 失败。

验收口径：

- 缺 active artifact 时 shadow OCR 不执行，不新增 `externalArtifact.*` OCR candidate。
- `contractExampleOnly = true` 时 shadow OCR 不执行。
- 真实 active artifact ready 时才允许 external TextBoxes shadow OCR，且每块最多 1 个 candidate。
- candidate 选择和 report-only promotion 不使用 ground truth。
- external OCR 结果只进 report / TXT，不改变主输入、主覆盖图、通过判定或 TextRegion crop adopted 数。

遗留事项：

- 当前仓库默认仍没有真实 active `test/koharu_artifacts/`；若 Koharu 或人工提供 artifact，必须先跑 validator，再由云端探针验证新 report 的 `executed=true` 路径。

### v1.14：Koharu artifact 注入校验与 CI 摘要闭环
日期：2026-06-30
依据：`md/prompt/v1（漫画探针）/v1.14（真实KoharuArtifact注入与ShadowOCR验证闭环）.md`。当前没有真实 `test/koharu_artifacts/` active artifact，因此本轮走缺 artifact 路径 B；不创建 active artifact，不刷新漫画指标，不追加 `metrics/version_history.csv`。

核心变更：

- `scripts/validate-koharu-artifacts.py` 新增 `--print-required-files`，可直接打印 Koharu / 外部 detector 侧需要交付的 active 四件套。
- validator 摘要新增 `readyForShadowOCR`、`nextAction`、`readinessBlockers`、`requiredFiles` 和 `activeArtifactPolicy`，缺 active artifact 时明确返回 `manifestMissing`、`externalTextBoxesShadowOCRAllowed = false`、`nextAction = stopUntilArtifactsProvided`。
- `AITRANS CI Results` 静态检查会把 `test/koharu_artifacts` validator 摘要写入 `ci-results/koharu-active-artifacts-validation.json`。
- `ci-artifact-manifest.json` 新增 `koharuActiveArtifactValidationPath`、`koharuArtifactValidation`、`externalArtifactReadinessSummary` 和 `externalTextBoxShadowOCRSummary`，Agent C 可直接核对缺 artifact 阻塞路径或未来 executed=true 路径。
- `ci-failure-summary.md` 新增 Koharu artifact gate 小节，列出 active directory、verdict、shadow OCR allowed、nextAction 和 blockers。
- `md/koharu研究/artifact_contract/README.md` 新增从 Koharu 导出到 AITRANS contract 的最小转换要求，继续禁止 examples、Vision、pre-crop plan、line plan、proxy mask、ground truth 或手写理想框冒充真实 detector 输出。
- README、flow、flowchart 和 test 文档同步 v1.14 validator / CI 闭环边界。

关键文件：

- `scripts/validate-koharu-artifacts.py`
- `.github/workflows/ci-results.yml`
- `md/koharu研究/artifact_contract/README.md`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`
- `md/prompt/v1（漫画探针）/v1.14（真实KoharuArtifact注入与ShadowOCR验证闭环）.md`

验证结果：

- Agent B 本地轻量检查通过：`git diff --check`、`python3 -m json.tool test/1.ground_truth.json`、`python3 -m json.tool output/probe_report.json`、`python3 -m json.tool output/clean_text_diagnostic.json`、validator valid / invalid `--expect-fail`、`--print-required-files` 和 `test/koharu_artifacts --allow-missing`。
- Agent C 核对 PR #4：base `smalldata_test`、head `codeb/v1.14-koharu-artifact-validation-loop`、head commit `2cf9ed0e2db39152006f257236e7e63ad51828da`。
- 云端 `AITRANS CI Results` run `28417554480` / attempt `1` 通过；manifest 匹配 `version = v1.14`、`branch = codeb/v1.14-koharu-artifact-validation-loop`、`commitSha = 2cf9ed0e2db39152006f257236e7e63ad51828da`、`workflowName = AITRANS CI Results`。
- 结果包 `aitrans-ci-v1.14-codeb-v1.14-koharu-artifact-validation-loop--2cf9ed0e2db3-run28417554480-attempt1` 包含 `.xcresult`、`junit.xml`、`xcodebuild.log`、`simulator-build.log`、`manga-probe.log`、`app-console.log`、`ci-artifact-manifest.json`、`ci-failure-summary.md`、`koharu-active-artifacts-validation.json` 和 `output/`。
- `junit.xml`：5 tests、0 failures；GGUF download / verify、static checks、Xcode build、simulator build、manga probe 全部 success。
- `koharu-active-artifacts-validation.json`：`verdict = manifestMissing`、`readyForShadowOCR = false`、`externalTextBoxesShadowOCRAllowed = false`、`nextAction = stopUntilArtifactsProvided`、`missingArtifacts = [manifest, TextBoxes, BubbleMask, SegmentMask]`，并列出 active 四件套 `requiredFiles`。
- 云端探针：`engineUsed = Local GGUF`、`decodingMode = deterministic`、`decodingSeed = 42`、`totalBlocksDetected = 13`、`outputDirectoryCleaned = true`、`overallPassed = false`。
- App 侧 gate 摘要：`externalArtifactReadinessReport.readinessVerdict = manifestMissing`、`activeArtifactsDirectory = false`、`externalTextBoxesShadowOCRAllowed = false`、`nextAction = stopUntilArtifactsProvided`。
- Shadow OCR 摘要：`externalTextBoxShadowOCRReport.executed = false`、`candidateCount = 0`、`ocrExecutedCount = 0`、`ocrSucceededCount = 0`、`promotedExternalShadowBlocks = []`、`wouldPromoteByExistingGateBlocks = []`、`skippedBlocks = [0...12]`。
- 质量数字未因本轮 CI 可见性改造改变：`groundTruthMatchedBlocks = 13`、`groundTruthUnmatchedBlocks = 0`、`averageCoreDialogueOCRSimilarity = 0.7106`、`averageDecorativeOCRSimilarity = 0.8000`、`cleanTextDiagnostic.passRate = 0.4545`、`passedBlocks = 1`、`failedBlocks = 12`。
- Agent C 已通过 PR #4 merge 到 `smalldata_test`，merge commit `a758117`；远端 `codeb/v1.14-koharu-artifact-validation-loop` 已由 PR merge 命令请求删除。

遗留事项：

- 当前仍没有真实 active `test/koharu_artifacts/`，因此不能验证 `externalTextBoxShadowOCRReport.executed = true` 或 OCR 收益。
- 下一步需要 Koharu 或人工提供 `1.manifest.json`、`1.textboxes.json`、`1.bubbles.json`、`1.segment_mask.json`，先由 validator 达到 `readyForShadowOCR`，再通过云端探针核对 executed=true。

### v1.15：Koharu 真实 artifact 交付包 handoff
日期：2026-06-30
依据：`md/prompt/v1（漫画探针）/v1.15（Koharu真实Artifact交付包与executed验证）.md`。当前仍没有真实 `test/koharu_artifacts/` active artifact，因此本轮走路径 B；不创建 fake active artifact，不调 Vision crop / line deskew，不刷新漫画指标，不追加 `metrics/version_history.csv`。

核心变更：

- 新增 Agent A v1.15 提示词，明确下一步只验证真实 Koharu / 外部 detector 四件套的 `readyForShadowOCR` 与 `externalTextBoxShadowOCRReport.executed=true`。
- 在 `md/koharu研究/artifact_contract/README.md` 新增 v1.15 真实交付包清单，面向 Koharu / 人工列出四个必需文件、每个文件最低字段、坐标系、图像尺寸、禁止来源、validator 命令和 ready 后的云端验收字段。
- 确认当前 active 目录不存在，validator 阻塞仍是 `manifestMissing`、`nextAction = stopUntilArtifactsProvided`，缺 `manifest`、`TextBoxes`、`BubbleMask`、`SegmentMask`。

关键文件：

- `md/prompt/v1（漫画探针）/v1.15（Koharu真实Artifact交付包与executed验证）.md`
- `md/koharu研究/artifact_contract/README.md`
- `update_log.md`

验证结果：

- 本轮应运行 `git diff --check`、JSON 解析和 Koharu artifact validator valid / invalid / allow-missing / print-required-files。
- 当前 `test/koharu_artifacts` 不存在；`python3 scripts/validate-koharu-artifacts.py --root test/koharu_artifacts --allow-missing` 返回 `verdict = manifestMissing`、`readyForShadowOCR = false`、`externalTextBoxesShadowOCRAllowed = false`、`nextAction = stopUntilArtifactsProvided`。
- 未跑本机 build / 探针；本轮是文档和交付清单收口，不涉及 Swift 代码或探针产物刷新。

验收口径：

- 没有真实 active artifact 时，v1.15 不能声称已验证 `executed=true`。
- 不得把 contract examples、Vision OCR、pre-crop plan、line plan、BubbleMask proxy、SegmentMask proxy、ground truth 或手写框复制到 `test/koharu_artifacts/`。
- Koharu / 人工交付真实四件套后，必须先通过 validator，再由云端探针验证 `readyForShadowOCR` 与 `externalTextBoxShadowOCRReport.executed = true`。

遗留事项：

- 下一步需要 Koharu / 人工提供 `test/1.png` 对应的真实 detector / segmenter 四件套：`1.manifest.json`、`1.textboxes.json`、`1.bubbles.json`、`1.segment_mask.json`。

### v1.16：云端 CI 分层加速与探针快模式
日期：2026-06-30
依据：`md/prompt/v1（漫画探针）/v1.16（云端CI分层加速与探针快模式）.md`。本轮是 CI / DEBUG 探针运行制度改造，不刷新漫画质量指标，不追加 `metrics/version_history.csv`。

核心变更：

- `AITRANS CI Results` 新增 `workflow_dispatch` 输入 `probe_mode = ci-fast / full / skip`；`codeb/**` 和 `smalldata_test` push 默认 `ci-fast`。
- 云端 CI 改为单次 Debug simulator build：`Xcode build` 产出 `.xcresult` 和可安装 app，后续步骤只定位并复用 app，不再重复完整 simulator build。
- `ci-fast` 仍安装真实 simulator app、导入 Release GGUF、读取真实 `test/1.png`、使用 deterministic 解码，保留 whole-page OCR、bubble-first 融合、post-fusion cleanup、逐块 Local GGUF 翻译、失败块覆盖、核心 PNG、`probe_report.json`、`clean_text_diagnostic.json`、`1_ocr_probe_text.txt`、Koharu readiness gate 和 external TextBoxes shadow OCR gate。
- `ci-fast` 跳过高成本 shadow-only / 对照层：lexicon comparison、Vision API comparison、synthetic slice、TextRegion crop shadow、crop experiment、TextBox plan failure、line crop、模型 OCR 纠错、确定性纠错翻译、tagged batch、contact sheet 和诊断 PNG。
- DEBUG 探针新增 `AITRANS_MANGA_PROBE_MODE` 读取；报告配置新增 `probeRunMode`、`probeFastPathEnabled`、`skippedDiagnostics`。
- `manga_probe_progress.json` 新增 mode、fast path、跳过项、已保留输出文件和阶段耗时字段。
- manifest 新增 `probeMode`、`probeFastPathEnabled`、`probeSkippedReason`、`probeTimeoutSeconds`、`probeStallTimeoutSeconds`、`probeDurationSeconds`、`probeSkippedDiagnostics`、`probeOutputRequiredFiles`、`probeOutputRetainedFiles`、`probeReportSummary`、`simulatorAppReusedFromXcodeBuild` 和 `simulatorAppPath`。
- `ci-fast` 等待上限为 1800 秒，停滞阈值 300 秒，每 30 秒打印进度；`full` 保留 3600 秒和 600 秒停滞阈值。
- README、flow、flowchart 和 test 文档同步说明 fast / full / skip 边界和 Agent C 验收字段。

关键文件：

- `.github/workflows/ci-results.yml`
- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`
- `md/prompt/v1（漫画探针）/v1.16（云端CI分层加速与探针快模式）.md`

验证结果：

- 本轮 Agent B 本地应运行轻量检查、Koharu validator valid / invalid / allow-missing / print-required-files，以及 workflow YAML smoke。
- 未跑本机 Xcode build / 漫画探针；按规则推送 `codeb/v1.16-ci-probe-fastpath` 后交给 GitHub Actions 验证。
- Agent C 核对 PR #6：base `smalldata_test`、head `codeb/v1.16-ci-probe-fastpath`、head commit `ccd57e4906bf14eaa5b27253fae2d82fa24b581a`。
- 云端 `AITRANS CI Results` run `28420791001` / attempt `1` 通过；manifest 匹配 `version = v1.16`、`branch = codeb/v1.16-ci-probe-fastpath`、`commitSha = ccd57e4906bf14eaa5b27253fae2d82fa24b581a`、`workflowName = AITRANS CI Results`。
- 结果包 `aitrans-ci-v1.16-codeb-v1.16-ci-probe-fastpath--ccd57e4906bf-run28420791001-attempt1` 包含 `.xcresult`、`junit.xml`、`xcodebuild.log`、`simulator-build.log`、`manga-probe.log`、`app-console.log`、`ci-artifact-manifest.json`、`ci-failure-summary.md`、`koharu-active-artifacts-validation.json` 和 `output/`。
- `junit.xml`：5 tests、0 failures；GGUF download / verify、static checks、Xcode build、simulator app locate、manga probe 全部 success。
- manifest：`probeMode = ci-fast`、`probeFastPathEnabled = true`、`simulatorAppReusedFromXcodeBuild = true`、`probeTimeoutSeconds = 1800`、`probeStallTimeoutSeconds = 300`、`probeDurationSeconds = 150`。
- 云端探针：`engineUsed = Local GGUF`、`decodingMode = deterministic`、`decodingSeed = 42`、`totalBlocksDetected = 13`、`outputDirectoryCleaned = true`、`overallPassed = false`。
- `ci-fast` 保留输出满足要求：`probe_report.json`、`clean_text_diagnostic.json`、`1_ocr_probe_text.txt`、`1_debug_boxes.png`、`1_translated_overlay.png`、`manga_probe_progress.json`；额外保留 bubble debug PNG。
- `configuration.probeRunMode = ci-fast`、`probeFastPathEnabled = true`，`skippedDiagnostics` 包含 lexicon / Vision API / synthetic slice / TextRegion crop / crop experiment / line crop / tagged batch / correction / contact sheet / diagnostic PNG 等高成本诊断。
- 质量数字：`passedBlocks = 1`、`failedBlocks = 12`、`groundTruthMatchedBlocks = 13`、`groundTruthUnmatchedBlocks = 0`、`averageCoreDialogueOCRSimilarity = 0.6987`、`averageDecorativeOCRSimilarity = 0.8000`、`cleanTextDiagnostic.passRate = 0.4545`。
- Koharu gate：`externalArtifactReadinessReport.readinessVerdict = manifestMissing`、`externalTextBoxesShadowOCRAllowed = false`、`externalTextBoxShadowOCRReport.executed = false`、`candidateCount = 0`、`ocrExecutedCount = 0`、`promotedExternalShadowBlocks = []`、`skippedBlocks = [0...12]`。
- PR #6 已通过 GitHub merge 合并到 `smalldata_test`，merge commit `226de189e1cec63c23130eaf1389c112068ee68e`。

验收口径：

- PR base 必须是 `smalldata_test`，不能指向 `main`。
- `ci-results.yml` 不再重复完整 simulator build。
- 默认云端结果包 manifest 应显示 `probeMode = ci-fast`、`probeFastPathEnabled = true`、`simulatorAppReusedFromXcodeBuild = true`、`engineUsed = Local GGUF`、`totalBlocksDetected > 0` 和关键输出文件。
- `full` 仍可由手动 workflow_dispatch 触发；`skip` 只能用于文档-only 或人工明确跳过，并必须写 `probeSkippedReason`。

遗留事项：

- v1.16 仍不提供真实 active `test/koharu_artifacts/`，因此不能声称验证了 `externalTextBoxShadowOCRReport.executed = true`。

### v1.17：Koharu 真实 artifact 首包缺失退回
日期：2026-06-30
依据：`md/prompt/v1（漫画探针）/v1.17（Koharu真实Artifact首包接入与收益归因）.md`。当前仍没有真实 `test/koharu_artifacts/` active artifact，因此本轮走路径 B；不创建 fake active artifact，不改 Swift / CI / 探针主流程，不刷新漫画指标，不追加 `metrics/version_history.csv`。

核心变更：

- 新增 Agent A v1.17 提示词，明确下一步只在真实 Koharu / 外部 detector 四件套到位后验证 `readyForShadowOCR`、云端 `executed=true` 和 shadow OCR 收益归因。
- 新增 `md/koharu研究/v1.17-artifact-first-pass.md`，记录当前第一事实：仓库没有真实 active artifact，因此不能验证 `externalTextBoxShadowOCRReport.executed = true`，也不能判断 Koharu OCR 收益。
- 面向 Koharu / 人工列出首包必须回答的问题：detector 来源、原图坐标转换、bbox 越界、核心对话覆盖、Bubble instance 覆盖、SegmentMask 尺寸、`contractExampleOnly=false`、validator ready 和云端 App bundle 可读。
- 确认本轮不创建 `test/koharu_artifacts/`，不复制 examples，不用 Vision OCR、pre-crop plan、line plan、BubbleMask proxy、SegmentMask proxy、ground truth 或手写框生成 active artifact。

关键文件：

- `md/prompt/v1（漫画探针）/v1.17（Koharu真实Artifact首包接入与收益归因）.md`
- `md/koharu研究/v1.17-artifact-first-pass.md`
- `update_log.md`

验证结果：

- Agent B 本地轻量检查通过：`git diff --check`、`python3 -m json.tool test/1.ground_truth.json`、`python3 -m json.tool output/probe_report.json`、`python3 -m json.tool output/clean_text_diagnostic.json`，以及 Koharu artifact validator valid / invalid / allow-missing / print-required-files。
- Agent C 核对 PR #7：base `smalldata_test`、head `codeb/v1.17-koharu-artifact-first-pass`、head commit `9e467bd089a74f5ced7858a0a243bf5a4ab76d14`。
- 云端 `AITRANS CI Results` run `28422226573` / attempt `1` 通过；manifest 匹配 `version = v1.17`、`branch = codeb/v1.17-koharu-artifact-first-pass`、`commitSha = 9e467bd089a74f5ced7858a0a243bf5a4ab76d14`、`workflowName = AITRANS CI Results`。
- 结果包 `aitrans-ci-v1.17-codeb-v1.17-koharu-artifact-first-pass--9e467bd089a7-run28422226573-attempt1` 包含 `.xcresult`、`junit.xml`、`xcodebuild.log`、`simulator-build.log`、`manga-probe.log`、`app-console.log`、`ci-artifact-manifest.json`、`ci-failure-summary.md`、`koharu-active-artifacts-validation.json` 和 `output/`。
- `junit.xml`：5 tests、0 failures；GGUF download / verify、static checks、Xcode build、simulator build、manga probe 全部 success。
- 云端探针：`probeMode = ci-fast`、`engineUsed = Local GGUF`、`decodingMode = deterministic`、`decodingSeed = 42`、`totalBlocksDetected = 13`、`outputDirectoryCleaned = true`、`overallPassed = false`。
- 质量数字：`passedBlocks = 1`、`failedBlocks = 12`、`groundTruthMatchedBlocks = 13`、`groundTruthUnmatchedBlocks = 0`、`averageCoreDialogueOCRSimilarity = 0.6987`、`averageDecorativeOCRSimilarity = 0.8000`、`cleanTextDiagnostic.passRate = 0.4545`。
- Koharu gate：`koharuActiveArtifactsDirectoryPresent = false`、`externalArtifactReadinessReport.readinessVerdict = manifestMissing`、`externalTextBoxesShadowOCRAllowed = false`、`externalTextBoxShadowOCRReport.executed = false`、`candidateCount = 0`、`ocrExecutedCount = 0`、`promotedExternalShadowBlocks = []`、`skippedBlocks = [0...12]`。
- 本轮未跑本机 build / 探针；文档-only 修改按规则交给云端验证。没有真实 active artifact，因此仍不能触发云端 `executed=true` 收益验证。

验收口径：

- 没有真实 active artifact 时，v1.17 不能声称已验证 `executed=true` 或 Koharu OCR 收益。
- 若下一轮提供真实四件套，必须先通过 validator，再由云端 `ci-fast` 证明 `activeArtifactsDirectory = true`、`externalTextBoxesShadowOCRAllowed = true`、`externalTextBoxShadowOCRReport.executed = true`、`candidateCount > 0`、`ocrExecutedCount > 0`。
- 即使 external OCR 有收益，也仍是 shadow-only；不得替换 `finalTextUsedForTranslation`、主覆盖图、`blockPassed`、`configuration.currentBlockSource` 或 `textRegionCropReport.adoptedCount`。

遗留事项：

- 下一步仍需要 Koharu / 人工提供 `test/1.png` 对应的真实 detector / segmenter 四件套：`1.manifest.json`、`1.textboxes.json`、`1.bubbles.json`、`1.segment_mask.json`。

### 方向修正：Koharu 作为算法参考，不再等待外部 artifact
日期：2026-06-30
依据：人工确认“真实 Koharu artifact 没办法跑；不管 Koharu 的结果，只向它的算法和框架靠近，用 AITRANS 自己跑出的图片结果分析 OCR 准确率、气泡、翻译情况，并继续优化算法结构”。本记录是项目方向修正，不是漫画探针质量版本；不刷新 `output/`，不追加 `metrics/version_history.csv`。

核心决策：

- 不再把真实 `test/koharu_artifacts/` 四件套作为后续主线阻塞项。
- 保留现有 external artifact contract、validator、App readiness gate 和 `externalTextBoxShadowOCRReport`，作为将来如果有人提供真实 detector 输出时的可选防伪/诊断入口；但日常优化不等待它。
- Koharu 后续定位调整为算法和框架参考，而不是外部运行依赖。可借鉴的方向包括 TextBoxes 思想、BubbleMask / SegmentMask 中间层、气泡实例归属、mask-safe layout、crop / OCR 候选晋级门槛、失败归因、清字/覆盖结构和 artifact DAG 式诊断。
- 后续主要使用 AITRANS 自己的 `test/1.png` 探针、云端 `ci-fast` / `full` 输出、`probe_report.json`、`clean_text_diagnostic.json`、`1_ocr_probe_text.txt`、关键 PNG 和 `metrics/version_history.csv` 来分析 OCR 准确率、气泡归属/分割、翻译失败分类、覆盖渲染和结构性瓶颈。
- 真实外部 artifact 仍不得伪造；不要用 contract examples、Vision OCR、pre-crop plan、line plan、BubbleMask proxy、SegmentMask proxy、ground truth 或手写框冒充 detector 输出。
- 后续 Agent A 提示词应优先围绕本项目可执行的算法结构优化：例如 OCR block 合并/去重、bubble-first 与 whole-page 融合、气泡分割与归属修正、TextBox/SegmentMask proxy 质量归因、crop 候选晋级、翻译 prompt / 模型对照、报告摘要和可视化排查，而不是继续要求 Koharu / 人工交付四件套。

关键文件：

- `update_log.md`
- `md/koharu研究/koharu图像识别链路研究.md`
- `md/koharu研究/v6～9work.md`
- `md/koharu研究/v1.17-artifact-first-pass.md`
- `md/prompt/v1（漫画探针）/v1.17（Koharu真实Artifact首包接入与收益归因）.md`

验证结果：

- 本轮应运行 `git diff --check`。
- 本轮只改方向记录，不涉及 Swift 代码、CI workflow、探针报告模型或 `output/` 产物。
- 未跑本机 build / 探针；按规则，后续涉及 Swift / 漫画探针改动时仍交给云端验证。

后续执行口径：

- Agent A 下一版提示词不再以“缺真实 Koharu artifact”为阻塞结论。
- Agent B 不应再围绕 `manifestMissing` 做重复文档或 fake artifact 工作。
- Agent C 验收后续算法优化时，重点看当前分支 HEAD 的云端结果包、报告字段、关键 PNG、OCR/气泡/翻译指标和是否保持主流程边界。
- external artifact gate 可以保留在报告中显示 `manifestMissing`，这只是可选外部输入缺失，不再代表主线无法继续。

### v1.18：内部结构瓶颈路由与保守碎片清理
日期：2026-06-30
依据：`md/prompt/v1（漫画探针）/v1.18（Koharu式内部结构瓶颈路由与保守清理）.md`。本轮修改 Swift 探针报告模型、post-fusion cleanup 和核心文档；不刷新仓库根 `output/`，不追加 `metrics/version_history.csv`，完整 build / 探针交给 GitHub Actions。

核心变更：

- 新增 `internalStructureBottleneckReport`，从最终 blocks、post-fusion cleanup、TextRegion crop、TextBox plan failure、BubbleMask、assignment correction、split candidate、external readiness 和翻译失败分类聚合结构瓶颈路由。
- 每块写出 `primaryBottleneck`、`secondaryBottlenecks`、`recommendedNextAction`、`evidence` 和 `mustNotPromoteReasons`；报告级汇总 primary breakdown、recommended action breakdown、dialogue / decorative breakdown 和关键 block 列表。
- `1_ocr_probe_text.txt` 增加 `internalStructureBottleneck` 逐块摘要；`ci-fast` 也生成该报告，不只在 full 模式生成。
- post-fusion cleanup 新增保守 `duplicateOrFragment` 规则，使用 bbox 强重叠/邻域、bubble 或 mask-safe 邻域、token 覆盖、信息分、OCR 错误启发和保护文本检查清理低信息碎片。
- `fusionComparison.postFusionCleanup.rejectedBlocks[]` 增加 `relatedKeptBlockIndex`、`qualityScore`、`protectedTextMatched` 和 ground-truth-free `evidence`，便于 Agent C 审计拒绝原因。
- 保护文本扩展包含 `The City Battler Tournament starts in a few days.`；external artifact 缺失只作为 optional note，不再作为主线阻塞。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`

验证计划：

- 本轮 Agent B 本地运行轻量检查：`swiftc -parse` 目标 Swift 文件、`git diff --check`、JSON 解析和 Koharu validator smoke。
- 未跑本机 build / 探针，按规则交给云端验证。
- 云端 `AITRANS CI Results` `ci-fast` 应证明 `internalStructureBottleneckReport.evaluatedBlockCount = totalBlocksDetected`，breakdown 非空，`1_ocr_probe_text.txt` 含 `internalStructureBottleneck`，且 `configuration.currentBlockSource` 仍为 `fusedWholePageBubble`。

遗留事项：

- 旧仓库根 `output/` 不含 v1.18 新字段；以 PR 后云端结果包为准。
- 若云端 OCR 波动导致新 duplicate/fragment cleanup no-op，本轮仍应通过瓶颈路由报告提供可审计价值；不得为了让 block 数变化而硬编码 block index 或使用 ground truth。

Agent C 退回复修：

- PR #8 初次云端 run `28424308991` 虽然 CI success，但 artifact 显示 post-fusion cleanup 从 `16 -> 11`，误删了远距离真实文本，并产生 `post-fusion cleanup reduced block count below target floor: 11` warning，因此未通过验收。
- 根因 1：`duplicateOrFragment` 的 `sameDominantNeighborhood` 把两个 `nil` 的 `safeLayoutRect` / `maskSafeRect` 当成同邻域证据。修复后只有非空且相等的 safe / mask rect，或真实 same bubble / bbox 重叠 / bbox 邻近，才算邻域证据。
- 根因 2：`internalStructureBottleneckReport` 用 rejected 的 `originalFusedBlockIndex` 去匹配 cleanup 后已重编号的 `block.index`，导致保留块被误标为 `duplicateOrFragment`。修复后保留块写入 `postFusionCleanupOriginalFusedBlockIndex` note，rejected 原始索引只用于报告汇总；逐块 primary / secondary 不再用 rejected 原始索引误判最终保留块。
- 本修复不刷新仓库根 `output/`，不追加 `metrics/version_history.csv`；重新 push 后仍由 GitHub Actions 生成新的 ci-fast artifact 供 Agent C 验收。

Agent C 最终验收：

- PR #8 base 为 `smalldata_test`，head 为 `codeb/v1.18-internal-structure-routing`，最终验收 commit 为 `74d81dce9d90af57058575428c71721e3fd7534f`。
- 云端 `AITRANS CI Results` run `28425069180` / attempt `1` 通过；artifact `aitrans-ci-v1.18-codeb-v1.18-internal-structure-routing--74d81dce9d90-run28425069180-attempt1` 的 manifest 匹配 `version = v1.18`、`branch = codeb/v1.18-internal-structure-routing`、`commitSha = 74d81dce9d90af57058575428c71721e3fd7534f`、`workflowName = AITRANS CI Results`。
- 结果包包含 `.xcresult`、`junit.xml`、`xcodebuild.log`、`ci-failure-summary.md`、`ci-artifact-manifest.json`、`output/probe_report.json`、`output/clean_text_diagnostic.json`、`output/1_ocr_probe_text.txt` 和关键 PNG。
- `junit.xml`：5 tests、0 failures；GGUF verify、static checks、Xcode build、simulator build、manga probe 均为 success。
- 云端探针：`engineUsed = Local GGUF`、`decodingMode = deterministic`、`decodingSeed = 42`、`configuration.currentBlockSource = fusedWholePageBubble`、`probeRunMode = ci-fast`、`totalBlocksDetected = 13`、`outputDirectoryCleaned = true`、`overallPassed = false`。
- post-fusion cleanup 复验通过：`blockCountBeforeCleanup = 16`、`blockCountAfterCleanup = 13`、`rejectedBlockCount = 3`、`warnings = []`、`missingKeyTexts = []`；`THAT'S RIGHT...` 和 `IVE ARRIVED...` 真实文本保留，初次 run 的远距离误删已消失。
- `internalStructureBottleneckReport` 复验通过：`evaluatedBlockCount = 13`，`primaryBottleneckBreakdown = { bubbleAssignmentOrSplit: 2, modelTranslationQuality: 5, ocrCharacterDamage: 5, passed: 1 }`，`recommendedActionBreakdown` 非空，`duplicateOrFragmentBlocks = []`，`postFusionRejectedDuplicateOrFragmentBlocks = []`，`1_ocr_probe_text.txt` 含逐块 `internalStructureBottleneck` 摘要和 `postFusionCleanupOriginalFusedBlockIndex` 证据。
- 质量数字：`groundTruthMatchedBlocks = 13`、`groundTruthUnmatchedBlocks = 0`、`averageCoreDialogueOCRSimilarity = 0.6987`、`averageDecorativeOCRSimilarity = 0.8000`、`passedBlocks = 1`、`failedBlocks = 12`、`translationFailureBreakdown = { modelOutputFailure: 3, ocrInputSuspect: 7, translationLanguageQualityFailure: 2 }`、`likelyRuleFalseFailureBlocks = []`、`cleanTextDiagnostic.passRate = 0.4545`。
- `overallPassed = false` 仍来自当前 Gemma 270M / OCR 质量基线，不作为本轮结构路由和 cleanup 修复失败。

### v2.2：GitHub Release GGUF 下载与 Actions 缓存
日期：2026-06-29
依据：云端验证基础设施改造；未刷新 `output/`，未追加 `metrics/version_history.csv` 漫画指标行。

核心变更：

- `AITRANS CI Results` workflow 新增 Release 模型下载、SHA256 校验和 Actions cache。
- 模型来源固定为 Release `model-gemma-3-270m-it-qat-q4_0-v1` 的 `gemma-3-270m-it-qat-Q4_0.gguf`。
- SHA256 固定为 `3626e245220ca4a1c5911eb4010b3ecb7bdbf5bc53c79403c21355354d1e2dc6`。
- 结果包 manifest 新增 `modelReleaseTag`、`modelAsset`、`modelSha256`、`modelCacheKey`、`modelCacheHit`、`modelLocalPath`、`modelDownloadOutcome`、`modelVerifyOutcome`。
- 结果包新增或保留 `model-download.log`、`model-verify.log`，失败摘要中列出模型下载和校验状态。

关键文件：

- `.github/workflows/ci-results.yml`
- `README.md`
- `md/test/test.md`
- `md/flow/flow.md`
- `update_log.md`

验证结果：

- 本轮应运行 `git diff --check`、`python3 -m json.tool test/1.ground_truth.json`、workflow smoke 和 YAML 解析。
- 未运行本机 Xcode build / 漫画探针；按规则交给云端验证。

遗留事项：

- v2.2 只解决模型下载、校验和缓存；下一步才把 `.ci-models/gemma-3-270m-it-qat-Q4_0.gguf` 导入模拟器 App 沙盒的 `Application Support/Models/Gemma-1.5B/model.gguf`，再运行完整漫画探针和导出 `output/`。

### 协作流程维护：云端验证和结果包制度
日期：2026-06-29
依据：流程制度变更，不是漫画探针质量版本；未刷新 `output/`，未追加 `metrics/version_history.csv` 漫画指标行。

核心变更：

- 将日常重验证默认迁移到 GitHub Actions；本机默认只做 `git diff --check`、JSON/YAML smoke 等轻量检查。
- 明确当前真实工作主分支为 `smalldata_test`，Agent B 候选分支为 `codeb/vX.Y-短标题`，Agent C 通过后合并回 `smalldata_test`，禁止合并到 `main`。
- 增加 `agenta` / `a:`、`agentb` / `b:`、`agentc` / `c:` 召唤规则和最终回复身份标识。
- 保留现有带密码的软件包打包流程，不为 Agent C 验收改动或解密；Agent C 只使用独立未加密 CI 结果包。
- 要求云端失败时保留 `.xcresult`、`junit.xml`、`xcodebuild.log`、`ci-artifact-manifest.json` 和 `ci-failure-summary.md`，由 Agent C 指明失败阶段和日志位置后退回 Agent B 修复。
- 记录 GGUF 云端模型依赖为已知后续事项：未来通过 GitHub Release + workflow 下载 + 缓存解决，本轮不提交模型、不处理 Release asset。

关键文件：

- `AGENTS.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `md/prompt/README.md`
- `.github/workflows/ci-results.yml`

验证结果：

- 本轮应运行文档/JSON/YAML 静态检查。
- 未运行本机 Xcode build / 漫画探针；按新规则交给云端验证。

遗留事项：

- 云端完整漫画探针仍受 GGUF、模拟器容器、App 沙盒输出导出和外部 artifact 依赖影响；能稳定运行后必须由 workflow 生成新报告。
- 旧文档 `md/云端协作流程/云端改造.md` 是原始提示词归档，其中 `samlldata_test` 拼写与当前远端真实分支不一致；执行时以 `smalldata_test` 为准。

### 项目初始与多页 SwiftUI 原型
日期：2026-06 中旬
依据提交：`c988066` 到 `b7376d8`、`2b1a4f7`、`9a1a456`、`43f6890`、`ae7fe12`

核心变更：

- 建立 SwiftUI iOS App 骨架和 Xcode 工程。
- 形成文本翻译、历史、提示词、模型、Pro、开发调试等多页结构。
- `TranslationSessionStore` 成为状态和持久化中心。
- 本地状态落到 `Application Support/AITRANS/state.json`。
- 引入 Apple Vision OCR、Speech、StoreKit 2 占位和本地模型目录概念。

关键文件：

- `AITRANS/App/AITRANSApp.swift`
- `AITRANS/Views/ContentView.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/VisionOCRService.swift`
- `README.md`

验证结果：

- 历史记录显示 `plutil`、asset JSON 检查、iOS Simulator build 和 generic iOS build 曾通过。
- 当时 CoreSimulator service 不稳定，未完成完整点击交互测试。

遗留事项：

- UI 已可用，但主线质量依赖后续 OCR、模型和探针。

### LLM 接口、自测和 Local 模型路径
日期：2026-06 中旬
依据提交：`92f2a8c`、`84d00bb`、`c529c6b`

核心变更：

- 新增 LLM 接口自测和更严格的翻译探针。
- 确认本地模型路线优先走 `llama.cpp + GGUF`。
- 英译中自测开始拒绝返回原文、包含完整原文和不像目标语言的输出。
- 模型导入后统一复制为 `Application Support/Models/Gemma-1.5B/model.gguf`。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Views/ContentView.swift`
- `README.md`

验证结果：

- `git diff --check` 通过。
- `plutil -lint` 通过。
- iOS Simulator build 和 generic iOS build 通过。

遗留事项：

- 当时 Local 仍偏接口接入和冒烟，真实翻译质量还需 raw 探针和模型对比。

### Developer Console、Pro 页和测试入口
日期：2026-06 中旬
依据提交：`6b7df35`、`7e552ed`、`9adb9a0`

核心变更：

- 新增开发者调试界面，展示真实 prompt、raw output 和错误。
- Pro 从首页迁移到独立底部 Tab。
- Pro 页新增 StoreKit 2 订阅骨架、长按麦克风同声传译、音频和 OCR 测试入口。
- 修复缺少 `test/` 空文件夹导致的编译失败。

关键文件：

- `AITRANS/Views/ContentView.swift`
- `AITRANS/Views/ProFeatureViews.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `test/.gitkeep`
- `README.md`

验证结果：

- README 记录了相关功能和入口。
- 编译失败由 `test/.gitkeep` 修复。

遗留事项：

- StoreKit 商品仍未上线，购买链路只能作为骨架。
- 语音和权限行为需要真机验证。

### 普通图片 OCR 翻译与漫画探针起步
日期：2026-06 中旬
依据提交：`f6f22e7`、`b95b97f`、`1daddcd`、`b5811b7`、`4a9eab4`、`4288e32`、`103d773`、`51fa18d`

核心变更：

- 普通图片翻译接入 Apple Vision OCR，支持按 bbox 旁贴或覆盖译文。
- 漫画截图 `test/1.png` 进入固定探针链路。
- 探针开始记录 OCR 坐标、逐块 prompt/raw output、debug boxes、translated overlay 和 JSON 报告。
- 引入内容裁切、2x 放大、多角度 OCR、空间聚类、预处理对照、OCR 纠错护栏、iOS 18+ RecognizeTextRequest 对比、customWords 和 bubble-first 初版对照。

关键文件：

- `AITRANS/Services/VisionOCRService.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Models/TranscriptModels.swift`
- `scripts/export-probe-output.sh`
- `test/1.png`
- `README.md`

验证结果：

- 多轮在 iPhone 17 Pro 模拟器运行 `test/1.png` 探针并导出 `output/`。
- 初期旧指标 `0.8378 / 0.8755` 后来被确认因真值不完整、强行匹配和旧相似度过宽而不可信。

遗留事项：

- OCR 已能定位文字区域，但文本误识别严重。
- Gemma 270M raw 输出常复读英文、空输出、占位或解释。

### v13-v20：失败诊断、质量门槛、纠错对照和总览输出
日期：2026-06 下旬
依据提交：`382d8ee` 到 `b5be534`

核心变更：

- 报告新增输出清理证明、`translationDecisionTrace`、`translationFailureDetail`、`translationFailureBreakdown`、`ocrProbeNotes`。
- `blockPassed` 质量门槛收紧，不再只凭含中文判定成功。
- 引入确定性 OCR 纠错候选、纠错覆盖图、纠错后翻译对照和 `1_ocr_probe_text.txt`。
- 新增 `1_bubble_text_overlay.png` 和 `1_probe_contact_sheet.png`，便于优先看总览图。
- `outputCleanupRemovedItemCount`、`outputFileCountAfterCleanup` 等字段证明输出目录每轮重建。

关键文件：

- `AITRANS/Services/MangaOverlayProbeService.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Models/TranscriptModels.swift`
- `output/probe_report.json`
- `output/1_ocr_probe_text.txt`
- `README.md`

验证结果：

- 多轮 `xcodebuild ... CODE_SIGNING_ALLOWED=NO build` 通过。
- 多轮模拟器探针导出。
- `git diff --check` 通过。
- v20 时 `totalBlocksDetected = 12`、`passedBlocks = 0`、`failedBlocks = 12`，输出目录保留 14 个本轮文件。

遗留事项：

- 当前未完成的是翻译质量可用。
- Local Gemma 270M raw 输出不稳和 OCR 原句错误仍是主因。

### v21：结构化真值、可信匹配和新基线
日期：2026-06 下旬
依据：`README.md` 近期记录

核心变更：

- `test/1.ground_truth.json` 改为 12 条结构化真值：11 条 `dialogue`、1 条 `decorative`。
- 真值匹配改为可拒绝匹配，低于阈值标记 `unmatched`。
- 相似度改用词级 Levenshtein，保留旧 `ocrLegacySimilarity` 作对照。
- 核心对话和装饰标题分开统计。
- 新增 clean text diagnostic，直接把 dialogue 真值送入翻译链路。

关键文件：

- `test/1.ground_truth.json`
- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `README.md`

验证结果：

- 当轮可信基线为 `totalBlocksDetected = 12`、`10 matched / 2 unmatched`、核心对话 `0.6196`、装饰标题 `0.8000`、bubble-first `0.7397`、clean text `4/11`。

遗留事项：

- README 中旧 `0.8378 / 0.8755` 只能作为历史对照，不再用于验收。

### Agent 1-2：气泡几何约束和长图 slice OCR 诊断
日期：2026-06 下旬
依据提交：`ad56eae`、README Agent 1-2 记录

核心变更：

- 引入气泡候选几何约束，把 OCR candidate 分配到 `bubbleID`。
- 同一 bubble 内合并，跨 bubble 合并被拒绝。
- 新增长图竖向 slice OCR 诊断，长宽比超过阈值时分片 OCR、坐标还原和重叠去重。
- 合成长图机制测试验证 3 个竖向切片和 20% 重叠去重。

关键文件：

- `AITRANS/Services/MangaOverlayProbeService.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Models/TranscriptModels.swift`
- `md/koharu研究/v5work.md`
- `README.md`

验证结果：

- `test/1.png` 默认不触发 slice，主图结果保持 `14` 块、`10 matched / 4 unmatched`、核心 OCR `0.6131`、装饰 `0.8000`。
- 合成长图触发 3 个竖向切片，重叠去重链路跑通。

遗留事项：

- 块数从 12 增至 14，是气泡边界拒绝旧跨气泡合并导致，不是 OCR 阈值变激进。
- 底部相邻气泡仍有分割问题。

### v10：whole-page + bubble-first 融合主流程
日期：2026-06-28
依据：`md/prompt/v1（漫画探针）/v1.0（bubble融合主流程）.md`、当前 `output/probe_report.json`

核心变更：

- 新增融合候选模型、`fusionResults` 和 `fusionComparison`。
- 融合选择只用 bbox、bubbleID、文本相似度、OCR 置信度、文本长度和疑似 OCR 损坏等无真值信号。
- 主翻译输入切到 `fusedWholePageBubble`；whole-page 和 bubble-first 原始对比仍保留用于回退审计。
- 保留 whole-page 独有 `Let's Battle!`，并纳入 bubble-first 独有的两条真实内容。
- `renderOutputs` 不再二次清空沙盒 Output，避免提前生成的 bubble 调试图被本轮主渲染删除；目录清理由探针开始和导出脚本负责。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `output/probe_report.json`
- `metrics/version_history.csv`

验证结果：

- iPhone 17 Pro 模拟器重新跑 `test/1.png` 并导出。
- `totalBlocksDetected = 16`、可信匹配 `13`、未匹配 `3`。
- `averageCoreDialogueOCRSimilarity = 0.7106`、`averageDecorativeOCRSimilarity = 0.8000`。
- `frameworkComparison.consistencyPassed = true`、`fusionComparison.consistencyPassed = true`。
- `fusion.fused.accuracyVsGroundTruth = 0.7384`。
- `cleanTextDiagnostic.passRate = 0.4545`。
- `translationFailureBreakdown = { modelOutputFailure: 2, ocrInputSuspect: 10, translationLanguageQualityFailure: 3 }`。
- `likelyRuleFalseFailureBlocks = []`。

遗留事项：

- 融合提高了 OCR 覆盖和可信匹配，但翻译通过仍只有 1 块，瓶颈仍在 OCR 噪声和 Gemma 270M 翻译能力。
- `totalBlocksDetected = 16` 是纳入真实 bubble-only 内容后的结果；后续仍需继续压重复/碎片块。

### v11：融合后重复碎片压缩与气泡分割审计
日期：2026-06-28
依据：`md/prompt/v1（漫画探针）/v1.1（重复碎片压缩与气泡分割审计）.md`、当前 `output/probe_report.json`

核心变更：

- 在 `fusedWholePageBubble` 后新增 post-fusion cleanup，拒绝明显重复、被包含、低信息或与更完整候选重叠的碎片块。
- 清理逻辑只用 bbox、bubbleID、source、文本长度、词覆盖、候选间覆盖关系和 OCR 质量启发，不用 ground truth 做生产选择。
- `probe_report.json` 新增 `fusionComparison.postFusionCleanup`，记录清理前后块数、拒绝块、拒绝原因、关联块和保护内容。
- `bubbleGeometry` 新增 `bubbleAudits`，诊断每个 bubble 的文本区数量、selected block 数、重叠风险、过大 bubble 风险和 `bubbleSplitCandidate`；本轮不默认拆分主流程。

关键文件：

- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `AITRANS/Models/TranscriptModels.swift`
- `README.md`
- `metrics/version_history.csv`
- `md/flow/flow.md`
- `md/flow/flowchart.md`

验证结果：

- iPhone 17 Pro 模拟器重新跑 `test/1.png` 并导出最新 `output/`。
- `totalBlocksDetected = 13`，清理前 `16`，清理后 `13`，拒绝 `3` 块。
- 被拒绝块：`THE SUGSESTION WAS OVERPULED...`、`PLAY ONLING...`、`JUST`。
- 三条保护内容 `Let's Battle!`、`What are you even talking about?`、`We need to get results...` 均保留。
- `groundTruthMatchedBlocks = 13`，`groundTruthUnmatchedBlocks = 0`。
- `averageCoreDialogueOCRSimilarity = 0.7106`，`averageDecorativeOCRSimilarity = 0.8000`。
- `frameworkComparison.consistencyPassed = true`，`fusionComparison.consistencyPassed = true`。
- `fusion.fused.accuracyVsGroundTruth = 0.7384`，`cleanTextDiagnostic.passRate = 0.4545`。
- `passedBlocks = 1`，`failedBlocks = 12`，`translationFailureBreakdown = { modelOutputFailure: 2, ocrInputSuspect: 7, translationLanguageQualityFailure: 3 }`。
- `likelyRuleFalseFailureBlocks = []`。

遗留事项：

- `-02 AT / LEAST... 2EN-` 残片被保守保留，避免跨 bubble 误删真实内容；后续应在气泡分割层处理。
- `bubbleAudits` 标出 `bubbleID 4/6/7` 有多块同 bubble 或过大 bubble 风险，下一轮可做诊断开关下的保守拆分实验。

### v12：TextRegion crop 候选与结构化中间层
日期：2026-06-28
依据：`md/prompt/v1（漫画探针）/v1.2（TextRegion crop候选与Koharu结构化中间层）.md`、当前 `output/probe_report.json`

核心变更：

- 新增 TextRegion crop OCR 候选层，为每个 post-fusion 主块记录 seed bbox、region bbox、crop bbox、bubble clamp、padding、方向、whole-page/fused/adaptive/crop 文本和选择决策。
- `probe_report.json` 新增 `textRegionCropReport`，`1_ocr_probe_text.txt` 同步写入每块 crop 文本、selected 文本、拒绝理由、词保留率和质量分。
- crop 采用逻辑只用 ground-truth-free 信号：词数、词保留率、文本相似度、拉丁/符号比例、疑似 OCR 错误、bubble clamp 和质量分；真值只在选择后用于报告评估。

关键文件：

- `AITRANS/Services/MangaOverlayProbeService.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Models/TranscriptModels.swift`
- `README.md`
- `metrics/version_history.csv`
- `output/probe_report.json`
- `output/1_ocr_probe_text.txt`

验证结果：

- build、模拟器真探针、导出、JSON 解析、`git diff --check` 均通过。
- `textRegionCropReport.totalRegions = 13`，`cropSucceededCount = 10`，`adoptedCount = 0`，`rejectedCount = 13`。
- 主要拒绝原因：`rawWordsLost = 5`、`emptyCropText = 3`、`wordCountRegression = 2`、`sameAsFusedText = 2`、`insufficientQualityGain = 2`、`introducedLikelyOCRError = 1`。
- 主指标无回归：`totalBlocksDetected = 13`、`groundTruthMatchedBlocks = 13`、`groundTruthUnmatchedBlocks = 0`、核心 OCR `0.7106`、装饰 `0.8000`、`fusion.fused.accuracyVsGroundTruth = 0.7384`、`cleanTextDiagnostic.passRate = 0.4545`、`passedBlocks = 1`、`failedBlocks = 12`。
- 三条保护内容 `Let's Battle!`、`What are you even talking about?`、`We need to get results...` 均保留。

遗留事项：

- 当前 crop 候选没有足够收益，不能为了指标强行替换主翻译输入。
- 后续应优先改进 TextRegion 检测/气泡分割质量，再重新评估 crop 采用收益。

### v13：BubbleMask 子区域诊断与 TextRegion clamp
日期：2026-06-28
依据：`md/prompt/v1（漫画探针）/v1.3（BubbleMask子区域与TextRegion clamp优化）.md`、当前 `output/probe_report.json`

核心变更：

- 新增轻量 `bubbleSubRegionReport`，用 fused block seed bbox、parent bubble bbox、oversized bubble audit 和几何覆盖率生成 block-local subregion 诊断。
- TextRegion crop OCR 优先使用 `clampEligible` 的 subregion 作为 clamp 边界；无可信 subregion 时继续回退到 bubble bbox 或 content rect。
- `textRegionCropReport.diagnostics` 新增 `clampSource`、`subRegionID`、`subRegionBBox`、`subRegionCoverageRatio`、`subRegionRejectedReason`、subregion clamp 前后 crop bbox。
- `1_ocr_probe_text.txt` 同步写入每块 subregion/clamp 证据。
- crop 采用护栏保持 v12 口径，不放宽 adopted 条件，不用 ground truth 做 subregion 生成、crop clamp 或候选选择。

关键文件：

- `AITRANS/Services/MangaOverlayProbeService.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Models/TranscriptModels.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `metrics/version_history.csv`
- `output/probe_report.json`
- `output/1_ocr_probe_text.txt`

验证结果：

- build、模拟器真探针、导出、JSON 解析、`git diff --check` 均通过。
- `bubbleSubRegionReport.totalSubRegions = 11`，`clampEligibleCount = 2`，`oversizedBubbleIDs = [4, 6, 7]`。
- `textRegionCropReport.clampSources = { bubbleBBox: 9, contentRect: 2, subRegion: 2 }`，subregion clamp 实际用于块 `[6, 8]`。
- `textRegionCropReport.totalRegions = 13`，`cropSucceededCount = 10`，`adoptedCount = 0`，`rejectedCount = 13`；主要拒绝原因未因 clamp 变化被放宽。
- 主指标无回归：`totalBlocksDetected = 13`、`groundTruthMatchedBlocks = 13`、`groundTruthUnmatchedBlocks = 0`、核心 OCR `0.7106`、装饰 `0.8000`、`fusion.fused.accuracyVsGroundTruth = 0.7384`、`cleanTextDiagnostic.passRate = 0.4545`、`passedBlocks = 1`、`failedBlocks = 12`。
- 三条保护内容 `Let's Battle!`、`What are you even talking about?`、`We need to get results...` 均保留。

遗留事项：

- 轻量 subregion 仍是传统几何近似，不是真正 Koharu 实例 mask。
- 当前 `adoptedCount = 0`，说明 subregion clamp 只提供了更清楚的 crop 串扰证据，尚未证明可替换主翻译输入。
- 下一步应继续观察 `bubbleID 4/6/7` 的 sibling overlap 和 subregion 失败原因，再决定是否引入更强的 bubble/text region 检测。

### v14：BubbleMask 实例 ID 与 mask 安全区诊断
日期：2026-06-28
依据：`md/prompt/v1（漫画探针）/v1.4（BubbleMask实例ID与mask安全区诊断）.md`、当前 `output/probe_report.json`

核心变更：

- 新增 `bubbleMaskReport`，用现有 bubble bbox 生成轻量实例 ID mask 近似，背景为 0，内部栅格值为 `bubbleID + 1`。
- 逐块记录 `maskDominantBubbleID`、`maskDominantCoverageRatio`、`maskIDsUnderSeed`、mask-safe rect、渲染 mask collision 和 crop mask coverage。
- safe layout 优先使用可信 mask-safe rect；不可用时回退既有 bbox safe rect。
- TextRegion crop 只新增 mask 覆盖诊断，不放宽 adopted 护栏，不用 ground truth 做 mask、crop 或布局选择。

关键文件：

- `AITRANS/Services/MangaOverlayProbeService.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Models/TranscriptModels.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `metrics/version_history.csv`
- `output/probe_report.json`
- `output/1_ocr_probe_text.txt`

验证结果：

- build、模拟器真探针、导出、JSON 解析、`git diff --check` 均通过。
- `bubbleMaskReport.instanceCount = 8`，`maskSafeLayoutBlocks = 13`，`bboxFallbackBlocks = 0`。
- `bubbleMaskReport.inconsistentBubbleAssignmentBlocks = [4, 5, 11, 12]`，`renderMaskOverflowBlocks = []`。
- TextRegion crop 仍为 `13 regions / 10 succeeded / 0 adopted / 13 rejected`；mask coverage 低的 crop 块为 `[4, 5, 9, 12]`。
- 主指标无回归：`totalBlocksDetected = 13`、`groundTruthMatchedBlocks = 13`、`groundTruthUnmatchedBlocks = 0`、核心 OCR `0.7106`、装饰 `0.8000`、`fusion.fused.accuracyVsGroundTruth = 0.7384`、`cleanTextDiagnostic.passRate = 0.4545`、`passedBlocks = 1`、`failedBlocks = 12`。
- 三条保护内容 `Let's Battle!`、`What are you even talking about?`、`We need to get results...` 均保留。

遗留事项：

- 当前 BubbleMask 是 bbox/rounded-rect 近似，不是真正 Koharu 实例分割 mask。
- mask-safe layout 改善的是覆盖布局和诊断证据，不代表 OCR 分数提升。
- 下一步应继续围绕 `bubbleID 4/6/7` 的实例分割可信度、TextRegion 检测和 crop 低 mask 覆盖块做诊断。

### v15：BubbleMask 归属修正与保守气泡拆分候选
日期：2026-06-28
依据：`md/prompt/v1（漫画探针）/v1.5（BubbleMask归属修正与保守气泡拆分候选）.md`、当前 `output/probe_report.json`

核心变更：

- 新增 `bubbleAssignmentCorrectionReport`，逐块记录 current bubble、mask dominant bubble、coverage、修正建议、采用状态、拒绝原因和风险标记。
- 新增 `bubbleSplitCandidateReport`，只对 oversized `bubbleID 4/6/7` 生成保守 split candidate，记录 parent bubble、seed block、bbox、coverage、sibling overlap、clamp eligibility 和采用块。
- TextRegion crop clamp 顺序扩展为 split candidate、corrected bubble mask、subregion、bubble bbox、content rect；原有 adopted 护栏不放宽。
- `1_ocr_probe_text.txt` 同步输出 bubble 修正决策、split candidate、assignment/split clamp 证据和拒绝原因。

关键文件：

- `AITRANS/Services/MangaOverlayProbeService.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Models/TranscriptModels.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `metrics/version_history.csv`
- `output/probe_report.json`
- `output/1_ocr_probe_text.txt`

验证结果：

- build、模拟器真探针、导出、JSON 解析、`git diff --check` 均通过。
- `bubbleAssignmentCorrectionReport = { evaluatedBlockCount: 13, inconsistentBlockIndexes: [4, 5, 11, 12], recommendedCorrectionBlocks: [5, 11], appliedToCropClampBlocks: [5], rejectedCorrectionBlocks: [4, 11, 12] }`。
- `bubbleSplitCandidateReport = { parentBubbleIDs: [4, 6, 7], candidateCount: 6, clampEligibleCount: 3, appliedToCropClampBlocks: [5, 9, 10] }`。
- TextRegion crop 仍为 `13 regions / 10 succeeded / 0 adopted / 13 rejected`。
- 主指标无回归：`totalBlocksDetected = 13`、`groundTruthMatchedBlocks = 13`、`groundTruthUnmatchedBlocks = 0`、核心 OCR `0.7106`、装饰 `0.8000`、`fusion.fused.accuracyVsGroundTruth = 0.7384`、`cleanTextDiagnostic.passRate = 0.4545`、`passedBlocks = 1`、`failedBlocks = 12`。
- 三条保护内容 `Let's Battle!`、`What are you even talking about?`、`We need to get results...` 均保留。

遗留事项：

- 当前 BubbleMask 和 split candidate 仍是 bbox/rounded-rect 近似，不是真正 Koharu 实例分割。
- block 11 只推荐修正到 `bubbleID 7`，因 coverage 未达 clamp 阈值未采用；block 4/12 因保护短文本或 decorative 标题保持诊断-only。
- TextRegion crop adopted 仍为 0，下一步应继续改进真实 TextRegion/BubbleMask 检测质量，而不是放宽采用护栏。

### v16：TextBoxes 与 SegmentMask 轻量证据层
日期：2026-06-28
依据：`md/prompt/v1（漫画探针）/v1.6（TextBoxes与SegmentMask轻量证据层）.md`、当前 `output/probe_report.json`

核心变更：

- 新增 `textBoxCandidateReport`，逐块记录 TextBox 候选来源、bbox、clamp source、padding、glyph overlap、BubbleMask coverage、safe rect overlap、证据分、是否可用于 crop 和拒绝/风险原因。
- 新增 `segmentMaskReport`，把现有 glyph mask 与 BubbleMask/safe rect/TextBox overlap 聚合成轻量 SegmentMask 诊断，标注 cleanup/crop evidence 可用块和弱证据块。
- `textRegionCropReport.diagnostics` 新增 `textBoxCandidateID`、`segmentMaskUsableForCropEvidence` 和 `failureAttribution`；报告级新增 `failureAttributionBreakdown`。
- `1_ocr_probe_text.txt` 同步输出每块 TextBox candidate、SegmentMask 和 crop failure attribution 摘要。
- TextBoxes / SegmentMask 均是传统图像处理和现有 bbox/mask 字段的轻量证据层，不是真模型；本轮不改变主输入、不放宽 TextRegion crop adopted 护栏。

关键文件：

- `AITRANS/Services/MangaOverlayProbeService.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Models/TranscriptModels.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `metrics/version_history.csv`
- `output/probe_report.json`
- `output/1_ocr_probe_text.txt`

验证结果：

- build、模拟器真探针、导出、JSON 解析、`git diff --check` 均通过。
- `textBoxCandidateReport = { candidateCount: 13, cropEligibleCount: 6, usedForCropBlocks: [], rejectedBlocks: [2, 4, 5, 7, 9, 11, 12] }`，TextBox 候选本轮只从既有 TextRegion crop 诊断派生，没有作为上游 crop clamp 输入。
- `segmentMaskReport = { glyphMaskBlocks: 11, usableForCleanupBlocks: [0, 1, 2, 3, 6, 7, 8, 9, 10, 11], usableForCropEvidenceBlocks: [0, 1, 2, 3, 6, 7, 8, 9, 10, 11], weakSegmentBlocks: [4, 5, 12] }`。
- `failureAttributionBreakdown = { localVisionRegression: 6, rawWordsLost: 5, bubbleMaskConflict: 3, emptyLocalOCR: 3, segmentMaskWeak: 3, textBoxTooWide: 2, introducedLikelyOCRError: 2, wordCountRegression: 2, sameAsFusedText: 2, insufficientQualityGain: 2 }`。
- TextRegion crop 仍为 `13 regions / 10 succeeded / 0 adopted / 13 rejected`。
- 主指标无回归：`totalBlocksDetected = 13`、`groundTruthMatchedBlocks = 13`、`groundTruthUnmatchedBlocks = 0`、核心 OCR `0.7106`、装饰 `0.8000`、`fusion.fused.accuracyVsGroundTruth = 0.7384`、`cleanTextDiagnostic.passRate = 0.4545`、`passedBlocks = 1`、`failedBlocks = 12`。
- 三条保护内容 `Let's Battle!`、`What are you even talking about?`、`We need to get results...` 均保留。

遗留事项：

- 本轮只输出 JSON/TXT 证据，没有新增 PNG 边框可视化；原因是现有 `1_bubble_debug.png` 生成早于 v16 的 TextBox/SegmentMask 汇总，直接改图会扩大耦合。
- 当前主要归因仍是局部 Vision OCR 退化、raw words 丢失和近似 mask 冲突；下一步应提升真实 TextRegion/BubbleMask/SegmentMask 检测质量，而不是放宽 crop 采用护栏。

### v17：TextRegion crop shadow 实验矩阵
日期：2026-06-29
依据：`md/prompt/v1（漫画探针）/v1.7（TextRegion crop实验矩阵与候选晋级门槛）.md`、当前 `output/probe_report.json`

核心变更：

- 新增 `cropExperimentReport`，以当前 TextRegion crop 为 control，对每个 fused block 运行受控 shadow candidate 矩阵。
- 候选来源限定在现有结构证据：TextBox、SegmentMask/glyph、BubbleMask mask-safe rect、split candidate、corrected bubble 和 subregion；每块最多 control + 3 个额外候选。
- 新增逐候选 `candidateID`、`variantName`、source stack、bbox、OCR 文本、词保留率、质量分、risk flags、rejection reasons。
- 新增逐块 `bestShadowCandidate`、`promotionVerdict` 和 `stopReasons`；这些字段只做诊断，不写回 `finalTextUsedForTranslation`。
- `1_ocr_probe_text.txt` 同步输出每块 `cropExperiment` 摘要，便于直接比较 control 与 best shadow。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `metrics/version_history.csv`
- `output/probe_report.json`
- `output/1_ocr_probe_text.txt`

验证结果：

- build、模拟器真探针、导出、JSON 解析、`git diff --check` 均通过。
- `cropExperimentReport = { candidateCount: 52, controlCandidateCount: 13, ocrSucceededCount: 43, betterThanControlCount: 15, promotedShadowBlocks: [], stoppedBlocks: [2, 4, 5, 6, 7, 9, 11, 12] }`。
- 每块候选数最大为 4，未出现指数级矩阵。
- variant 尝试数：`currentTextRegionCrop=13`、`textBoxTight=13`、`maskSafeRectConstrained=13`、`glyphMaskExpanded=10`、`conservativeSeedBBox=2`、`splitCandidateClamp=1`。
- TextRegion crop 仍为 `13 regions / 10 succeeded / 0 adopted / 13 rejected`；TextBox `usedForCropBlocks=[]`。
- 主指标无回归：`totalBlocksDetected = 13`、`groundTruthMatchedBlocks = 13`、`groundTruthUnmatchedBlocks = 0`、核心 OCR `0.7106`、装饰 `0.8000`、`fusion.fused.accuracyVsGroundTruth = 0.7384`、`cleanTextDiagnostic.passRate = 0.4545`、`passedBlocks = 1`、`failedBlocks = 12`。
- 融合清理 `missingKeyTexts = []`，三条保护内容仍保留。

遗留事项：

- 本轮没有 shadow candidate 达到晋级门槛，说明当前轻量候选还不足以上游化。
- `betterThanControlCount = 15` 只表示局部质量分高于 control，不表示可采用；多数候选仍有 raw words lost、local Vision regression、bubble mask conflict 或 protected diagnostic only 风险。
- 下一步应停止在 `[2, 4, 5, 6, 7, 9, 11, 12]` 继续盲目局部 crop 调参，优先补真正 TextBoxes/BubbleMask/SegmentMask 检测质量或更强 OCR。

### v18：TextRegion crop 前 TextBox plan artifact
日期：2026-06-29
依据：`md/prompt/v1（漫画探针）/v1.8（Koharu式上游TextBoxes候选规划与shadow验证）.md`、当前 `output/probe_report.json`

核心变更：

- 新增 `preCropTextBoxPlanReport`，在 TextRegion crop OCR 之前为每个 fused block 生成 Koharu 式 TextBox plan。
- plan 来源限定在生产可用结构信号：fused seed bbox、bubble geometry、BubbleMask majority / safe rect、subRegion、split candidate、assignment correction、glyph / SegmentMask proxy。
- 每块最多保留 3 个 plan；`evidenceScore`、`eligibleForShadowOCR`、`riskFlags`、`rejectionReasons` 均为 ground-truth-free。
- `cropExperimentReport` 优先使用 `preCropTextBoxPlan.*` 变体作为 shadow OCR 来源；control 仍是当前 TextRegion crop。
- `1_ocr_probe_text.txt` 新增逐块 `preCropTextBoxPlans` 摘要，并明确 `shadowOnly=true`、`groundTruthNotUsed=true`、`notWrittenToFinalTextUsedForTranslation=true`。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `README.md`
- `AGENTS.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `metrics/version_history.csv`
- `output/probe_report.json`
- `output/1_ocr_probe_text.txt`

验证结果：

- build、模拟器真探针、导出、JSON 解析、`git diff --check` 均通过。
- `preCropTextBoxPlanReport = { planCount: 37, shadowOCREligiblePlanCount: 29, selectedForShadowOCRBlocks: [0, 1, 2, 3, 5, 6, 7, 8, 9, 10, 11], stoppedBlocks: [4, 12] }`。
- `cropExperimentReport = { candidateCount: 48, controlCandidateCount: 13, ocrSucceededCount: 36, betterThanControlCount: 13, promotedShadowBlocks: [], stoppedBlocks: [2, 3, 4, 5, 7, 9, 11, 12] }`。
- `cropExperimentReport.variantBreakdown` 新增 `preCropTextBoxPlan.seedTightTextBox`、`preCropTextBoxPlan.bubbleContainedTextBox`、`preCropTextBoxPlan.maskMajorityTextBox`。
- TextRegion crop 仍为 `13 regions / 10 succeeded / 0 adopted / 13 rejected`；`finalTextUsedForTranslation` 未由 plan 或 shadow OCR 写回。
- 主指标无回归：`totalBlocksDetected = 13`、`groundTruthMatchedBlocks = 13`、`groundTruthUnmatchedBlocks = 0`、核心 OCR `0.7106`、装饰 `0.8000`、`fusion.fused.accuracyVsGroundTruth = 0.7384`、`cleanTextDiagnostic.passRate = 0.4545`、`passedBlocks = 1`、`failedBlocks = 12`。
- 三条保护内容仍可信匹配：`Let's Battle!`、`What are you even talking about?`、`We need to get results...`。

遗留事项：

- `promotedShadowBlocks` 仍为空；本轮证明上游 plan artifact 可审计，但没有证明可直接替换主输入。
- 局部 Vision OCR 仍会在多个 pre-crop plan 上出现空输出、raw words lost 或质量退化；下一步应继续改善真实 TextBoxes/BubbleMask/SegmentMask 生成质量，而不是放宽 adopted 护栏。

### v19：TextBox plan 失败归因与晋级门槛审计
日期：2026-06-29
依据：`md/prompt/v1（漫画探针）/v1.9（TextBox计划失败归因与晋级门槛收敛）.md`、当前 `output/probe_report.json`

核心变更：

- 新增 `textBoxPlanFailureReport`，把 pre-crop plan、shadow OCR candidate 和 block 级结论串成三级失败归因。
- `MangaOverlayCropExperimentCandidate` 新增 `sourcePlanID`，稳定关联 `preCropTextBoxPlanReport.plans[].planID` 和 `cropExperimentReport.candidates[]`。
- 每个 best shadow candidate 输出 ground-truth-free promotion checks，包括 OCR 成功、`wordPreservationRatio >= 0.80`、`qualityDelta > 0.08`、raw words lost、OCR 错误、same-as-fused、BubbleMask / SegmentMask 风险和 protected block。
- `1_ocr_probe_text.txt` 每块新增 `textBoxPlanFailure` 和 `promotionChecks` 摘要，直接说明为什么停止、继续几何研究或需要审计晋级门槛。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `metrics/version_history.csv`
- `output/probe_report.json`
- `output/1_ocr_probe_text.txt`

验证结果：

- build、模拟器真探针、导出、JSON 解析、`git diff --check` 均通过。
- `textBoxPlanFailureReport = { evaluatedBlockCount: 13, evaluatedPlanCount: 37, evaluatedCandidateCount: 35, betterThanControlCandidateCount: 13, promotedShadowBlockCount: 0 }`。
- `stopRecommendedBlocks = [2, 3, 4, 5, 7, 9, 11, 12]`，`continueGeometryResearchBlocks = [1, 6, 10]`，`candidatePromotionBlockedBlocks = [1, 2, 4, 5, 6, 9, 10]`。
- `promotionBlockerBreakdown` 主要为 `qualityDeltaBelowOrEqual0.08: 31`、`wordPreservationRatioBelow0.80: 29`、`notBetterThanControl: 22`、`rawWordsLost: 19`、`emptyLocalOCR: 9`、`noShadowCandidate: 8`。
- `cropExperimentReport` 仍为 `48 candidates / 13 controls / 36 OCR succeeded / 13 betterThanControl / 0 promoted`；TextRegion crop 仍为 `13 regions / 10 succeeded / 0 adopted / 13 rejected`。
- 主指标无回归：`totalBlocksDetected = 13`、`groundTruthMatchedBlocks = 13`、`groundTruthUnmatchedBlocks = 0`、核心 OCR `0.7106`、装饰 `0.8000`、`fusion.fused.accuracyVsGroundTruth = 0.7384`、`cleanTextDiagnostic.passRate = 0.4545`、`passedBlocks = 1`、`failedBlocks = 12`。
- 三条保护内容仍可信匹配：`Let's Battle!`、`What are you even talking about?`、`We need to get results...`。

遗留事项：

- `betterThanControl = 13` 仍全部未晋级；主要原因是质量增益不足、词保留不足、raw words lost、空 OCR 或保护块，不是 adopted 护栏过严。
- 下一步应优先改善真实 TextBoxes / BubbleMask / SegmentMask 的几何证据，停止在已标记 stop 的块上继续盲目枚举局部 crop 变体。

### v20：行级 TextBox 与 deskew shadow 验证
日期：2026-06-29
依据：`md/prompt/v1（漫画探针）/v1.10（Koharu式行级TextBox与deskew shadow验证）.md`、当前 `output/probe_report.json`

核心变更：

- 新增 `lineTextBoxPlanReport`，目标块动态来自 `textBoxPlanFailureReport.continueGeometryResearchBlocks`，当前为 `[1, 6, 10]`。
- 每个目标块最多生成 4 个 line-level plan，覆盖 `lineTightTextBox`、`lineBandTextBox` 和保守 `deskewProbeTextBox`；deskew 角度只作为诊断记录，不做昂贵全局搜索。
- 新增 `lineCropExperimentReport`，复用现有 TextRegion crop OCR 和 v19 promotion gate，候选变体以 `lineTextBoxPlan.*` 开头。
- `1_ocr_probe_text.txt` 为目标块输出 line-level 计划、best line candidate、promotion checks 和带原因的 `lineResearchDecision`。
- 所有 line-level 结果均为 shadow-only，不改变 `finalTextUsedForTranslation`、主覆盖图、`blockPassed`、post-fusion cleanup 或 `textRegionCropReport.adoptedCount`。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `metrics/version_history.csv`
- `output/probe_report.json`
- `output/1_ocr_probe_text.txt`

验证结果：

- build、模拟器真探针、导出、JSON 解析、`git diff --check` 均通过。
- `lineTextBoxPlanReport = { targetBlocks: [1, 6, 10], planCount: 12, shadowOCREligiblePlanCount: 12 }`。
- `lineCropExperimentReport = { candidateCount: 12, ocrSucceededCount: 12, betterThanControlCount: 5, promotedLineShadowBlocks: [], stoppedAfterLineResearchBlocks: [1, 6, 10] }`。
- block 1 best line candidate 为 `lineBandTextBox`，`qualityDelta = 0.095`，但 `wordPreservationRatio = 0.571`，未过 `wordPreservationRatio >= 0.80`。
- block 6 best line candidate 为 `lineTightTextBox`，`qualityDelta = -0.053`，且有 `introducedLikelyOCRError`、`notBetterThanControl` 和词保留不足。
- block 10 best line candidate 为 `lineTightTextBox`，`qualityDelta = 0.046`，低于 `qualityDelta > 0.08`，且 `wordPreservationRatio = 0.583`。
- 主指标无回归：`totalBlocksDetected = 13`、`groundTruthMatchedBlocks = 13`、`groundTruthUnmatchedBlocks = 0`、核心 OCR `0.7106`、装饰 `0.8000`、`cleanTextDiagnostic.passRate = 0.4545`、`frameworkComparison.consistencyPassed = true`、`fusionComparison.consistencyPassed = true`。
- `Let's Battle!`、`What are you even talking about?`、`We need to get results...` 仍在明细中可信匹配。

遗留事项：

- line-level / deskew shadow 对 block `[1, 6, 10]` 有 5 个 better-than-control 候选，但没有任何候选通过既有 promotion gate。
- 当前证据支持停止继续在这 3 块上堆 crop / line / deskew 变体；下一步应转向真实 TextBoxes detector、真实 BubbleMask / SegmentMask，或更强 OCR / 翻译模型质量基准。

### v21：真实 TextBoxes 与 Mask 适配前证据闸门
日期：2026-06-29
依据：`md/prompt/v1（漫画探针）/v1.11（真实TextBoxes与Mask适配前证据闸门）.md`、当前 `output/probe_report.json`

核心变更：

- 新增 `externalArtifactReadinessReport`，覆盖真实或外部导出的 `TextBoxes`、`BubbleMask`、`SegmentMask` 三类 artifact。
- 支持读取 bundle 内 `test/koharu_artifacts/1.manifest.json`、`1.textboxes.json`、`1.bubbles.json`、`1.segment_mask.json`，或 manifest 指定的等价路径。
- parser 校验 manifest、schema、坐标系、source image、bbox 越界、confidence 和 SegmentMask 尺寸，并把外部 TextBoxes / Bubble instances 与当前 fused blocks 做 IoU / center containment 对齐。
- `1_ocr_probe_text.txt` 顶部新增 `externalArtifactReadiness` 摘要，每块新增 `externalArtifacts` 行。
- 所有 external artifact 结果均为 shadow-only，不改变 `configuration.currentBlockSource`、`finalTextUsedForTranslation`、主覆盖图、`blockPassed`、post-fusion cleanup 或 `textRegionCropReport.adoptedCount`。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `metrics/version_history.csv`
- `output/probe_report.json`
- `output/1_ocr_probe_text.txt`

验证结果：

- build、模拟器真探针、导出、JSON 解析、`git diff --check` 均通过。
- 当前仓库没有 `test/koharu_artifacts/`，因此 `externalArtifactReadinessReport = { manifestFound: false, textBoxesFound: false, bubbleMaskFound: false, segmentMaskFound: false, readinessVerdict: manifestMissing, nextAction: stopUntilArtifactsProvided, missingArtifacts: [manifest, TextBoxes, BubbleMask, SegmentMask], blockAlignmentCount: 13 }`。
- 主指标无回归：`totalBlocksDetected = 13`、`groundTruthMatchedBlocks = 13`、`groundTruthUnmatchedBlocks = 0`、核心 OCR `0.7106`、装饰 `0.8000`、`frameworkComparison.consistencyPassed = true`、`fusionComparison.consistencyPassed = true`。
- TextRegion crop 仍为 `13 regions / 10 succeeded / 0 adopted / 13 rejected`。
- line-level research 仍为 `targetBlocks = [1, 6, 10]`、`promotedLineShadowBlocks = []`、`stoppedAfterLineResearchBlocks = [1, 6, 10]`。

遗留事项：

- 当前正确结论是缺少真实 detector / mask artifact，下一步必须先提供或生成真实 TextBoxes / BubbleMask / SegmentMask 输出。
- 不得把 reference/koharu-main 源码存在、现有 Vision OCR blocks、pre-crop plan 或 line plan 写成“真实 detector 已接入”。
- 不应继续在 v20 已判停的 block / line / deskew crop 变体上试参。

### v22：Koharu 外部 Artifact 契约与离线 Validator
日期：2026-06-29
依据：`md/prompt/v1（漫画探针）/v1.12（Koharu外部Artifact契约与Shadow OCR入口）.md`

核心变更：

- 新增 `md/koharu研究/artifact_contract/README.md`，明确 active 输入目录是 `test/koharu_artifacts/`，非活动 fixture 目录是 `md/koharu研究/artifact_contract/examples/`。
- 新增 valid / invalid contract fixtures；valid fixture 标记 `contractExampleOnly=true`，只用于 schema / parser smoke，不代表真实 detector 输出。
- 新增 `scripts/validate-koharu-artifacts.py`，用 Python 标准库校验 manifest、fallback 路径、TextBoxes、Bubble instances、SegmentMask summary、source image、坐标系、bbox、confidence 和图片尺寸。当前 `test/1.png` 文件名为 `.png`，实际 header 是 JPEG，validator 同时支持 PNG / JPEG header。
- Swift `externalArtifactReadinessReport` 新增 active/example 区分、manifest / artifact 路径、`generatedBy` 和 `externalTextBoxesShadowOCRAllowed`；`contractExampleOnly`、坐标缺失、坐标不匹配、source image 不匹配、bbox / SegmentMask 尺寸错误现在有更明确的 verdict / nextAction。
- GitHub Actions 静态检查加入 artifact validator，并在 `ci-artifact-manifest.json` 记录 validator 日志路径、是否运行和 active artifact 目录是否存在。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `.github/workflows/ci-results.yml`
- `scripts/validate-koharu-artifacts.py`
- `md/koharu研究/artifact_contract/README.md`
- `md/koharu研究/artifact_contract/examples/`
- `README.md`
- `md/flow/flow.md`
- `md/test/test.md`
- `update_log.md`

验证结果：

- 本轮应运行 `git diff --check`、JSON 解析和 artifact validator smoke。
- 本轮不跑本机 Xcode build / 漫画探针；Swift build、云端探针和结果包由 PR 后 GitHub Actions 验证。
- 这是 contract / validator 版本，不刷新 `output/`，不追加 `metrics/version_history.csv` 漫画指标行。

遗留事项：

- 当前仓库仍没有真实 `test/koharu_artifacts/` active artifact；没有真实 detector / segmenter 输出时，App 探针应继续阻塞在 `manifestMissing` 或 `artifactFilesMissing`。
- 下一轮只有在人工或外部 Koharu 侧提供真实 TextBoxes / BubbleMask / SegmentMask artifact 后，才允许准备 `externalArtifact.*` shadow OCR candidate；仍不得替换主输入或放宽 promotion gate。

### Agent 3：自适应 crop 与回退自测
日期：2026-06 下旬
依据提交：`da9d574`

核心变更：

- OCR 二次 crop 从固定比例扩张改为自适应 padding。
- 横排文本 y padding 大于 x padding，竖排相反。
- crop clamp 到所属气泡 bbox。
- 新增固定 crop 对照、自适应 crop 字段和人为超窄 crop 回退自测。

关键文件：

- `AITRANS/Services/MangaOverlayProbeService.swift`
- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `README.md`

验证结果：

- build、模拟器探针、JSON 解析、`git diff --check` 通过。
- `totalBlocksDetected = 14`、`10 matched / 4 unmatched`、核心 OCR `0.6131`、装饰 `0.8000`、clean text `0.5455`。
- `cropFallbackSelfTest.triggered = true`。

遗留事项：

- 真实 `test/1.png` 未触发实际 fallback。
- 自适应 crop 有提升块也有变差块，不能按真值驱动生产选择。

### Agent 4-5：安全布局区和离屏碰撞检查
日期：2026-06 下旬
依据提交：`b65d904`

核心变更：

- 新增 `safeLayoutRect` 和 `safeLayoutSource`。
- 单块气泡使用气泡 bbox inset，多块同气泡使用分区安全区。
- 覆盖绘制前用离屏 alpha mask 检查文字越界，通过字号回退解决。

关键文件：

- `AITRANS/Services/MangaOverlayProbeService.swift`
- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `README.md`

验证结果：

- build、完整探针、导出、JSON 解析、`git diff --check` 通过。
- `safeLayoutRectBlocks = 14`、`renderCollisionCheckedBlocks = 14`。
- `renderCollisionUnresolvedBlocks = []`、`renderTextTruncatedBlocks = []`。

遗留事项：

- 该轮改善渲染布局，不改变 OCR 准确率。

### Agent 6-7：glyph mask 和纯色背景填充
日期：2026-06 下旬
依据提交：`0ab70d0`、`08438e9`

核心变更：

- 对已归属气泡块生成轻量 glyph mask。
- mask 使用局部阈值、连通域过滤、OCR bbox 重叠约束和膨胀。
- 低纹理背景区域使用 RGB 中位数做纯色填充，高纹理或插画区域保留半透明覆盖。
- 未归属气泡块不生成 mask。

关键文件：

- `AITRANS/Services/MangaOverlayProbeService.swift`
- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `README.md`

验证结果：

- build、完整探针、导出、JSON 解析、`git diff --check` 通过。
- `glyphMaskBlocks = 11`。
- 纯色填充触发块 `[2, 4, 6, 7]`。
- 未归属块 `5/11/13` 的 mask 为 0，符合气泡内约束。

遗留事项：

- glyph mask 和背景填充只影响覆盖可读性，不修 OCR 文本。

### Agent 8-9：tagged batch 诊断和 v5 汇总
日期：2026-06 下旬
依据提交：`6e1aa7f`、`613ca14`

核心变更：

- 新增 `batchTranslationComparison` tagged 批量翻译诊断。
- 批量分支只写报告，不替换逐块翻译、`blockPassed`、raw output 或 fallback。
- 完成 Agent 1-9 汇总，确认几何约束改善归属、裁切、渲染和跨气泡隔离。

关键文件：

- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Models/TranscriptModels.swift`
- `README.md`
- `output/probe_report.json`

验证结果：

- batch 诊断负面：`parsedCases = 0`、`missingTags = [0...13]`、`unexpectedTags = [14...24]`。
- 逐块通过率 `0.0714`，批量通过率 `0`。
- 完整探针基线仍为 `14` 块、`10 matched / 4 unmatched`、核心 OCR `0.6131`。

遗留事项：

- Gemma 270M 不适合 tagged batch 翻译主流程。
- 几何约束不能根治专有名词和 OCR 字符损坏。

### v6：确定性诊断解码和跨版本指标
日期：2026-06-27
依据提交：`d316ab2`、`metrics/version_history.csv`

核心变更：

- `LlamaRuntime` 支持按调用切换 sampled 和 deterministic 解码。
- 用户实际翻译和 summary 保持 sampled。
- raw 诊断、漫画探针、clean text、batch 和纠错翻译对照使用 deterministic，固定 `seed = 42`。
- 新增 `metrics/version_history.csv` 和 `scripts/append-version-metrics.py`。

关键文件：

- `AITRANS/Services/LlamaRuntime.swift`
- `AITRANS/Services/GemmaLocalService.swift`
- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `metrics/version_history.csv`
- `scripts/append-version-metrics.py`

验证结果：

- build、探针、导出、JSON 解析、`git diff --check` 通过。
- `deterministicDecodingCheck.outputsIdentical = true`。
- v6 指标：`14` 块、`10 matched / 4 unmatched`、核心 OCR `0.6131`、clean text `0.4545`。

遗留事项：

- v4 缺完整逐块 OCR 快照，无法字符级回溯 `0.6196 -> 0.6131`。

### v7：底部气泡串扰诊断和保守 crop 修复
日期：2026-06-27
依据提交：`c5bd626`、`metrics/version_history.csv`

核心变更：

- 专项排查 `GET PESULTE...` 和 `What Whet...`。
- 当 OCR bbox 只覆盖合理气泡的一部分时，二次预处理 OCR 使用所属气泡 bbox 做 adaptive crop。
- 检测层 seed 分裂和小框优先实验因回归被回退。

关键文件：

- `AITRANS/Services/MangaOverlayProbeService.swift`
- `README.md`
- `metrics/version_history.csv`

验证结果：

- build、完整探针、导出、JSON 解析、`git diff --check` 通过。
- 指标保持 `14` 块、`10 matched / 4 unmatched`、核心 OCR `0.6131`、clean text `0.4545`。

遗留事项：

- 目标 OCR 没有实质改善。
- 后续应改气泡候选分割，而不是放宽跨气泡合并。

### v8：bubble-first 主流程切换评估
日期：2026-06-28
依据提交：`ce577b7`、`metrics/version_history.csv`

核心变更：

- 重新评估 bubble-first 能否替换整页主候选源。
- 结论是不推进架构改造，本轮只做证据收集和决策。

关键文件：

- `README.md`
- `metrics/version_history.csv`
- `output/probe_report.json`

验证结果：

- build、模拟器探针、导出、JSON 解析、`git diff --check` 通过。
- `blocksFoundByBoth = 8`。
- `blocksOnlyInWholePage = ["Let's Battle!"]`。
- `blocksOnlyInBubbleFirst = ["What are you even talking about?", "We need to get results at this tournament to save the gaming club from being disbanded."]`。
- `frameworkComparison.consistencyPassed = true`。

遗留事项：

- bubble-first 可作为未来融合候选，但不能直接独占主流程。
- 未来若推进，需要 whole-page 真实内容兜底和去重报告字段。

### v9：词表、确定性纠错和 OCR 错误结构复盘
日期：2026-06-28
依据提交：`d3080c4`、`metrics/version_history.csv`、`md/koharu研究/v6～9work.md`

核心变更：

- 复测 Vision `customWords`：开关词表最终文本无变化。
- 复盘确定性 OCR 纠错候选：只保留诊断对照，不进入主流程。
- 总结低相似和未匹配块结构，确认问题不是 `Senpai` 单点，而是专有名词和常见词混淆共同存在。

关键文件：

- `README.md`
- `metrics/version_history.csv`
- `output/probe_report.json`
- `md/koharu研究/v6～9work.md`

验证结果：

- 最新指标：`totalBlocksDetected = 14`、`10 matched / 4 unmatched`、核心 OCR `0.6131`、装饰 `0.8000`、whole-page `0.6131`、bubble-first `0.7397`、clean text `0.4545`、`passedBlocks = 1`、`failedBlocks = 13`。
- `translationFailureBreakdown = { ocrInputSuspect: 10, translationLanguageQualityFailure: 3 }`。
- `likelyRuleFalseFailureBlocks = []`。

遗留事项：

- 文字区域检测和 OCR 文本质量仍是核心瓶颈。
- 下一轮优先做更强小模型对比，如 Qwen2.5-0.5B-Instruct-GGUF q4_k_m，或推进 bubble-first + whole-page 融合，而不是继续放宽质量规则。

## 历史维护记录
### README 更新记录收口到 update_log
日期：2026-06-29

核心变更：

- 删除 README 中的“近期优化记录”长段落，README 改为只保留项目说明、当前用法和稳定规则。
- 明确版本历史、关键决策、验证结果和遗留问题统一写入 `update_log.md`。
- 同步修正 `AGENTS.md` 和 README 中“更新 README 近期记录”的旧维护规则。
- 保留 `metrics/version_history.csv` 作为漫画探针和翻译链路可量化版本的 append-only 指标表。

关键文件：

- `README.md`
- `AGENTS.md`
- `update_log.md`

验证结果：

- 本轮是文档-only 流程收口，按规则运行轻量静态检查。

遗留事项：

- 历史条目已在 `update_log.md` 汇总；后续不要再向 README 追加更新记录。

### 建立多 Agent 迭代文档体系
日期：2026-06-28

核心变更：

- 整合标准入口为 `AGENTS.md`，作为项目唯一核心入口文档。
- 新增 `md/prompt/README.md`、`md/test/test.md`、`md/flow/flow.md`、`md/flow/flowchart.md`。
- 根据 git 记录、README 和指标 CSV 整理本 `update_log.md`。

关键文件：

- `AGENTS.md`
- `update_log.md`
- `md/prompt/README.md`
- `md/test/test.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`

验证结果：

- 本轮为文档-only 任务，按 `md/test/test.md` 只需静态检查。

遗留事项：

- 后续每轮由 Agent A 按 `md/prompt/README.md` 的命名规则写入具体实现提示词。
