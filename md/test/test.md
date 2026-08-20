### v3.295 普通图片 OCR 弱日语文字块恢复合同

- 页级日语 OCR 与布局完成后，只对已有弱日语 block 做最多 4 个有界复读；候选按原 confidence 稳定排序，复用现有 block crop reader，不重新跑 detector/layout，也不重新编码图片。
- 复读结果必须非空、confidence `>=.55`、日语脚本密度 `>=.5`，并以更多日语文字或至少 `+.04` confidence 证明优于原结果；失败、取消、模型不可用或不满足 gate 时保留原 block。
- 该路径服务普通 `test/jap.jpg` 图片 OCR，不读取 Koharu artifact、授权 corpus、ground truth 或 GGUF，不改翻译、持久化、UI、renderer、非日语路径或 block geometry。Koharu 仅是可选研究/质量证明；CI `koharu_parity_required` 默认 `false`，本合同称“弱日语 block”恢复，不把静态合同当作通用 OCR/CER 证据。
- 新合同：`scripts/test-v3295-image-japanese-weak-block-recovery-contract.py`；本地只做该纯 Python 合同、静态 AST/YAML/shell/plist 与 diff 检查，未运行本地 Xcode、Swift、Core ML、Rust、GGUF 或 App/runtime。

### v3.294 共享语料 artifact intake 完整性合同

- readiness schema 升级为 `1.1.0`；`--artifact-root` 只接受 root 内的 regular、非 symlink 文件，并核验 dataset/source manifest 与 12 个 prediction artifact 的实际 SHA-256、payload identity、唯一 prediction ID、`predictionCount` 及 `dev` page/region coverage。
- 新合同：`scripts/test-v3294-japanese-corpus-artifact-intake-contract.py`；覆盖成功 materialization、缺 root、SHA 篡改、路径越界、symlink、payload dataset/count 不匹配和 page/region coverage 不完整。contract-only fixture 仍无真实 artifact，readiness 为 `blocked`、`artifactIntakeStatus=notRequired`。
- 本轮只收口证据文件物化与 fail-closed 身份边界，不修改产品 OCR、翻译、selector、UI、renderer、持久化、请求/像素预算或模型路径；未运行本地 Xcode/Swift/Core ML/Rust/GGUF/App runtime，也未使用真实授权 corpus、prediction artifact、目标设备证据或 holdout。
- 本地结果：v3.294 合同 `8/8`；全量安全回归 `293` 个无进程入口合同、`1,454` 个测试通过，`27` 个实际导入 `subprocess` 的合同按约束跳过；`339` 个 tracked Python AST、`144` 个 JSON、`3` 个 YAML、`32` 个 shell、`4` 个 plist 与 `git diff --check` 通过。
- exact-SHA full [32311133176](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/32311133176) 精确对应候选 `db20203a72880e606c48dd85084f57a1eccc4366`：benchmark `96254177073`、Koharu parity `96254177322`、主 bundle `96255495225` 成功；Xcode 26.6、UI interaction、JUnit `10/10`（0 failures）和 `AITRANS CI/full-validation=success` receipt 通过，`probe_mode=skip`。
- 云端 corpus readiness report 的 manifest SHA 为 `c3163a95b46a40396f66874bbeac815198a716c5f091f6b5baa43e8383af51d8`，`status=blocked`、`artifactIntakeStatus=notRequired`，`productPathEnabled=false`、`productSelectionChanged=false`、`groundTruthUsedForDecision=false`；这不是 OCR/CER、翻译盲评、设备或 holdout 证据。
- PR [#364](https://github.com/bengzhu/project1_lgbt_naxida/pull/364) fast CI [32312669866](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/32312669866) 成功后，以 merge SHA `a4ffb3cf9867be39f7f37e7183efe5bd9fe9b071` 合入 `smalldata_test`；合入后 push CI [32312752741](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/32312752741) 的 benchmark `96258905284`、主 bundle `96258978383`、JUnit `10/10` 与 readiness report 均通过，Koharu 按父链复用。`main` 未修改。

### v3.293 共享语料四引擎矩阵完整性合同

- readiness evaluator 固定要求 4 engine × 3 crop level 的 12 个 `dev` rows，canonical artifact ID 与 reference-only 角色锁定；缺 row、failed/missing row、dataset split 计数不一致或 holdout/product-selection safety flag 违反均 fail closed。
- 新合同：`scripts/test-v3293-japanese-corpus-matrix-integrity-contract.py`；只验证 schema/evaluator/route 边界，不读取 ground truth，不运行模型，不改变产品 OCR/翻译路径。真实授权语料、预测 artifact、目标设备 evidence、OCR/CER、翻译盲评与 holdout 仍未提供。
- 本地结果：v3.293 `6/6`、v3.292 `8/8`；`319` 个 tracked `scripts/test-v*.py` 中 `292` 个无进程入口合同通过、`27` 个实际调用 `subprocess` 的合同跳过；`338` 个 Python AST、`3` 个 workflow YAML、`32` 个 shell、`4` 个 plist 与 `git diff --check` 通过。未运行本地 Xcode/Swift/Core ML/Rust/GGUF/App runtime，readiness fixture 仍为 `blocked`。
- exact-SHA full [32304497238](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/32304497238) 精确对应 `1de9c297834200233c19b9491f253bb9ba8c1bbe`：Koharu parity `96234590642`、Japanese benchmark/readiness `96234590825`、主 bundle `96236313725` 成功；Xcode 26.6、UI interaction、Speech/Home/Paste、JUnit `10/10` 与 `AITRANS CI/full-validation=success` receipt 通过，`ui_evidence_mode=skip`、`probe_mode=skip`。readiness report 为 `blocked`，manifest SHA `8a761ecdb2ac96f4a3781800638807d62ba2f96a4c71bc6d26fdd09384127cbd`，12 个矩阵 row、真实授权 corpus、目标设备 evidence、OCR/CER、翻译盲评和 holdout 均缺失，三个安全 flag 均为 `false`；这不是质量或 holdout 证据。
- PR [#363](https://github.com/bengzhu/project1_lgbt_naxida/pull/363) fast CI [32307053195](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/32307053195) 成功后以 merge SHA `0a9b4cb0ba0433bd7081436a9a7dbd74b32a0934` 合入 `smalldata_test`；合入后 push CI [32307181272](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/32307181272) 的 benchmark `96242352595`、主 bundle `96242423222` 成功，Xcode 26.6、UI interaction、Speech/Home/Paste、JUnit `10/10` 与 full-validation receipt 通过，readiness 仍为 `blocked`，三个安全 flag 均为 `false`，main 未动。

### v3.292 共享日语 OCR/translation corpus 与 holdout readiness 合同

- 新增严格 corpus manifest/report schema、contract-only 缺证据 manifest、纯 Python fail-closed evaluator、cloud-only wrapper 和 `scripts/test-v3292-japanese-corpus-readiness-contract.py`；真实授权 dataset、20 页/150 TextRegion、三分割、四引擎同 crop 预测矩阵和 holdout freeze 均显式为 missing。
- readiness 只允许 `blocked` 或 `readyForHoldout`，固定 `productPathEnabled=false`、`productSelectionChanged=false`、`groundTruthUsedForDecision=false`；不选择 OCR/翻译模型，不接入产品路径，不把 contract fixture 当作质量证据。
- 本地结果：v3.292 合同 `8/8`；`318` 个 tracked `scripts/test-v*.py` 全部 AST 解析成功，290 个无 `subprocess` 入口合同通过、27 个实际调用 `subprocess` 的历史合同跳过；3 个 workflow YAML、31 个 shell、4 个 plist、工程版本两处 `3.292` 与 `git diff --check` 通过。contract-only evaluator 为 `blocked`；即使未来输出 `readyForHoldout`，也不等于真实 holdout、OCR/CER、翻译盲评或目标设备性能证据。
- 短 SHA dispatch [32296949158](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/32296949158) 因 workflow 要求完整 40 位 commit 而失败，不计入证据；随后 exact-SHA full [32297366464](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/32297366464) 对 `05995e907d21b6301e4ffd5279b8d7748cecd97d` 成功：Koharu parity `96211707766`、benchmark `96211707973`、主 full `96213641670`、Xcode 26.6、UI interaction、Speech/Home/Paste、JUnit `10/10` 与 receipt 全部通过。`ui_evidence_mode=skip`、`probe_mode=skip`；corpus readiness report 为 `blocked`，manifest SHA `8a761ecdb2ac96f4a3781800638807d62ba2f96a4c71bc6d26fdd09384127cbd`，三个 product/ground-truth flags 均为 `false`。这只证明 cloud contract/reference parity/编译边界，不证明真实 corpus、OCR/CER、翻译质量、设备性能或 holdout。
- PR [#362](https://github.com/bengzhu/project1_lgbt_naxida/pull/362) 已以 merge SHA `395a488c46c7c1bced3eb9338d2511aded1038f1` 合入 `smalldata_test`；合入后 push CI [32299829133](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/32299829133) 的 benchmark `96219590599`、主 bundle `96219705330`、Xcode 26.6、UI interaction、Speech/Home/Paste、JUnit `10/10` 与 receipt 成功，Koharu parity 按父链 skip，UI evidence/manga probe 按配置 skip。新 readiness report 仍为 `blocked`，三个 flags 均为 `false`；这只证明 v3.292 evidence layer 已合入，不证明真实 OCR/CER、翻译质量、设备性能或 holdout。

### v3.291 BubbleMask / SegmentMask artifact readiness 合同

- 新增 `benchmarks/japanese_render/` 的严格 manifest/report schema、缺证据 contract-only manifest、纯 Python evaluator、cloud-only wrapper 和 `scripts/test-v3291-mask-artifact-readiness-contract.py`；BubbleMask、SegmentMask、授权语料、license review 与 target-device runs 均显式 missing，报告状态固定为 `blocked`。
- v3.291 合同锁定 canonical manifest SHA、双 artifact role、model/runtime/file/size/SHA/quantization/license/distribution 身份，以及 `referenceOnly`、`defaultEnabled`、`productPathEnabled`、`productSelectionChanged`、`groundTruthUsedForDecision` 的安全边界；CI Japanese benchmark artifact 同时包含 `japanese-render-mask-artifact-report.json`。
- 本轮仅允许 Python 合同、AST、workflow YAML、shell/plist 与 `git diff --check`；不运行本地 Swift/Xcode/Core ML/Rust/GGUF/App runtime。即使 cloud readiness evaluator 成功，也不代表真实 mask、inpainting、shaped renderer、OCR/CER、翻译质量或设备性能已验证。
- 本地结果：v3.291 合同 `10/10`；317 个 `scripts/test-v*.py` AST 全部成功，290 个无进程入口合同通过、27 个实际调用 `subprocess` 的合同跳过；3 个 workflow YAML、31 个 shell、4 个 plist、工程版本两处 `3.291` 与 `git diff --check` 通过。纯 evaluator 报告 `blocked`，cloud-only wrapper、Xcode/Swift/Core ML/Rust/GGUF/App runtime 和真实外部 artifact/corpus/device 证据仍未在本地执行或提供。
- 合入后补跑：`python3 scripts/test-v3288-japanese-translation-context-qa-contract.py` `9/9`，最新跨批次泄漏、撤销术语、数字/专名、长度、tag 顺序及取消/部分持久化 fail-closed mutation 均通过；`python3 scripts/test-v3291-mask-artifact-readiness-contract.py` `10/10`。两项只运行纯 Python 合同，不构成真实 GGUF、授权语料、目标设备或 holdout 证据。
- exact-SHA full [32289021728](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/32289021728) 对 SHA `d801f69c306716d7d5e60823d790b8a0e28b4def` 成功：Koharu parity `96185284954`、Japanese benchmark/readiness `96185285045`、主 full `96187425952` 均通过，Xcode/UI interaction/Speech/Home/Paste、JUnit `10/10` 与 `AITRANS CI/full-validation=success` receipt 成功；UI evidence、simulator/manga probe 按配置 skip。云端 readiness report 为 `blocked`，BubbleMask/SegmentMask、授权语料和 target-device evidence 均缺失，三个 product/ground-truth flags 均为 `false`。这只证明 readiness contract/report-only 边界；真实 mask artifact、native mask/inpainting/shaped renderer、OCR/CER、翻译质量和设备性能仍未验证，v3.291 尚未合入 `smalldata_test`。
- 文档 receipt SHA `4ced9fe203410aa7ea7906f58640dce9f1172859` 的最新 exact-SHA full [32292249313](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/32292249313) 也成功：Koharu parity `96195515343`、Japanese benchmark/readiness `96195515791`、主 full `96197364348` 全部通过，JUnit `10/10` 与 receipt 成功；因仅改文档，Xcode、UI interaction/UI evidence、simulator/manga probe 按 scope skip。新 readiness report 仍为 `blocked`，BubbleMask/SegmentMask、授权语料和 target-device evidence 缺失，三个 flags 均为 `false`；v3.291 尚未合入 `smalldata_test`。
- 随后 PR [#361](https://github.com/bengzhu/project1_lgbt_naxida/pull/361) 已以 merge SHA `dbec9488763153c609d3f192657c9473b464575f` 合入 `smalldata_test`；合入后 push CI [32293394134](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/32293394134) 的 benchmark 与主 bundle 成功，JUnit `10/10`、`AITRANS CI/full-validation=success` receipt 通过。v3.290 仍在目标分支父链，readiness 继续为 `blocked`，真实 mask artifact、授权语料和 target-device evidence 仍缺失。

### v3.290 矩形 overlay 渲染安全预检合同

- 已完成图片会话在 `adjacent`／`replace` overlay 导出前只生成 report-only `ImageTranslationRenderSafety.Report`：检查 invalid geometry、空文字、旁贴裁切、旁贴覆盖原块、源块重叠和跨块 collision；结果面板只提供 VoiceOver 可读 warning，不改 OCR、翻译、renderer、export、持久化或复查状态。
- `scripts/test-v3290-image-translation-render-safety-contract.py` 与 cloud-only `scripts/test-v3290-image-translation-render-safety-runtime.sh` 覆盖 clear、invalid、edge clipping、source overlap 与 cross-block collision；新合同 `7/7` 通过。工程版本为 `3.290`，新 model 已归入 Models group。首个 exact-SHA CI [32258069825](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/32258069825) 的 benchmark job 成功，但主 job 因 iOS 17 deployment 下 raw `EnumeratedSequence` 的 SwiftUI collection availability，以及 standalone evaluator 缺失 provenance/layout/context dependency closure 而失败；两类边界均已修复并加合同。
- 本地只允许安全合同、AST/YAML/shell/plist 与 `git diff --check`：全量 `316` 个 Python 合同中 `289` 个通过、`27` 个含 `subprocess` 入口跳过、`0` 失败；v3.288 context 合同因新增 prompt 插值/evaluator closure 断言为 `9/9`，AST `334`、workflow `3`、tracked shell `30`、plist `4`、工程版本两处 `3.290`。未运行 Xcode／Swift／Core ML／Rust／GGUF／App runtime；修复后的 cloud evaluator/Xcode/JUnit receipt 仍待下一次 exact-SHA full，该预检不证明 mask、清字、OCR/CER、翻译或设备性能改善。
- 第二个 exact-SHA CI [32261112799](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/32261112799) 已确认 raw `EnumeratedSequence` 错误消失，但进一步发现 v3.288 out-of-order QA 的 `guard` body 缺少 `continue`，以及多语句 `makeRequest` 缺少显式 `return`；两处均已修复并纳入合同。standalone Swift evaluators 统一采用 `-parse-as-library`，v200/v201/v367 会在失败时回传编译 stderr。该 run 仍为 JUnit `7/10`，不能作为 v3.290 receipt。
- 第三个 exact-SHA CI [32263359545](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/32263359545) 的 benchmark/static/Xcode 已成功，JUnit `9/10`；唯一失败是历史 v3.264 quad-warp runtime 编译 `MangaOCRService.swift` 时漏带 v3.281 provenance 类型。第四个 CI [32266041339](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/32266041339) 显示首次同时加入完整 layout engine 会与 harness 自有轻量 `ImageOCRLayoutRect` 冲突；最终 runtime 只加入 `ImageOCRProvenance.swift`，harness rect 增加 `Codable`，合同禁止完整 layout engine。warp 产品实现与 checksum 不变，仍待下一 SHA 的完整 UI/JUnit receipt。
- 第五个 exact-SHA CI [32268208057](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/32268208057) 的 benchmark/static 成功，但 UI interaction contract 在 v3.281 provenance runtime 失败：standalone `TranscriptModels.swift` 编译闭包缺少三个历史 probe-only payload 类型。v3.281 与 v3.290 fixture 已各自补入 `MangaOverlayBubbleGeometryDiagnostics`、`MangaOverlaySliceOCRDiagnostics`、`MangaOverlayCropFallbackSelfTest` 的 `Equatable/Codable/Sendable` 空 stub，v3.288 合同同时锁定该最小闭包；不进入产品 target，仍待下一 SHA 的完整 UI/Xcode/JUnit receipt。
- 第六个强制 UI evidence full [32272593193](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/32272593193) 的 Koharu parity `96132362772`、benchmark `96132363000`、Xcode 与 UI evidence 成功，但 UI interaction contract 仍失败；主 job `96134348013` 为 JUnit `10` 项 `1` 失败。根因是 v3.285 selector runtime 漏编 `ImageOCRLayoutEngine.swift`，导致 `ImageOCRProvenance.swift` 中的 `ImageOCRLayoutRect` 未定义；当前修复补入该最小依赖，并由 v3.285 合同锁定 `provenance -> layout -> fixture` 顺序且排除 `TranscriptModels.swift`。仍待下一 exact-SHA full 的 UI interaction、Xcode、JUnit `10/10` 与 receipt。
- 第七个 exact-SHA full [32277233442](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/32277233442) 的 Koharu parity `96147655198`、benchmark `96147654855`、Xcode 与 UI evidence 成功，但 v3.285 Swift evaluator 因把 throwing encode/decode 放入 `precondition` autoclosure 而编译失败；主 job `96149631229` 为 JUnit `10` 项 `1` 失败。当前修复先绑定 `encodedPolicy`/`decodedPolicy`，再执行等价断言，合同同步锁定该边界，仍待下一 exact-SHA full receipt。

- 第八个 exact-SHA full [32280583163](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/32280583163) 的 benchmark `96158153691`、Koharu parity `96158154043`、Xcode 与 UI evidence 成功，但主 job `96160258529` 的 JUnit `10` 项有 `1` 项失败。唯一错误是 v3.286 evaluator 将 `JSONDecoder.decode` 放进 `precondition` autoclosure；当前修复先绑定 `decoded` 再执行断言，合同新增 `precondition(try ...)` 禁止项，仍待新 SHA 的完整 receipt。
- 第九个 exact-SHA full [32284079603](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/32284079603) 对最终 SHA `c14096954ef2f9aa75d7a6ba58482a9baf2cc973` 成功：Koharu parity `96169412154`、benchmark `96169412411`、主 macOS `96170995494` 的 UI interaction、Xcode、14 张 UI evidence、JUnit、manifest、artifact 与 `AITRANS CI/full-validation=success` receipt 全部通过；合入后的 push CI [32284048360](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/32284048360) 也成功。v3.290 已在 `smalldata_test`，`main` 未修改；真实 GGUF、授权语料、目标设备证据和 v3.289 holdout 仍缺失。

### v3.289 图片复查、会话快照与结构 mutation 合同

- 只读 provenance disclosure、低置信／方向待定 block 的 scoped bbox 编辑与 automatic baseline 均不得改变已有候选选择、整页 OCR/翻译、布局、预算或复查状态；拖动只改 draft，提交后才写回，scoped rerecognition 仍只取消当前 block task。
- 受管图片会话快照只在路径、regular/non-symlink 文件、类型、字节数和 SHA-256 全部匹配时恢复；旧 JSON 缺失新字段继续兼容，临时 shadow ledger 不持久化，失败／取消／换图清理 orphan。split／merge 创建 fresh block identity 并清除受影响译文／旧 OCR evidence，order mutation 保留有效 metadata 与 reviewed progress。
- 合同边界为 provenance `4/4`、bbox editor `5/5`、automatic baseline `5/5`、session persistence `9/9`、structure mutation `7/7`。这些是静态／状态协议证据，不是真实图片几何、OCR/CER、翻译、Koharu parity、holdout 或目标设备性能证据；真实 GGUF、授权语料、盲评、设备测量、exact-SHA full、Xcode/JUnit 与 receipt 仍缺失。

### v3.288 术语记忆、跨 batch context 与 block-level translation QA 合同

- 项目术语／人名／称呼记忆显式区分 `confirmed`、`candidate`、`revoked`；上一批只读 completed summary 只进入下一批 prompt context，禁止进入待翻译标签或包含 pending input。严格检查 tags、原文泄漏、数字、确认术语、目标语言密度和长度，只生成失败 block 集合。
- 图片日语 batch 继续受最多 `8` blocks／`1,800` chars 约束；QA 失败只补译失败 block，保留已完成译文、OCR/layout、部分持久化与 scoped cancel，不重跑 OCR、检测、布局或整页。最新合同 `9/9` 通过，除 `previousContextLeakage`、撤销术语、数字、长度、duplicate/out-of-order tags 与取消／持久化 fail-closed mutation 外，也锁定类型、确认术语、上一批摘要和长度限制必须以真实 Swift 插值进入 prompt，并锁定 standalone model evaluator dependency closure。
- evaluator 与 fixture 固定 `blocked`／`promotion=notEligible`／`productSelectionChanged=false`；不选择模型、不证明 Gemma/Qwen/Sakura 或 Koharu 翻译质量。真实 GGUF/template、授权 clean-text corpus、盲评和 target-device evidence 仍是进入 holdout 的前置条件。

### v3.265 Vision Koharu 垂直 line quad 共享采样合同

- Vision `perspectiveCorrectedLineImage` 必须先复用 `MangaOCRService` 的 Koharu target geometry 与 direct projective bilinear sampler；成功后用 Vision `rotatedImage(..., angle: 270)`，不得把 Core Image natural projection + Core Graphics `.high` resize 作为正常 vertical line 路径。
- direct geometry／采样失败保留自然投影 fallback；detector bbox／line overlap ownership、24 个 perspective candidate、16M perspective pixel budget、Vision OCR、去重、布局、翻译、渲染与非图片路径不变。
- `scripts/test-v3265-koharu-vision-vertical-quad-warp-contract.py` 锁定共享 helper、fallback、预算、CI route 与 `3.265` 版本；runtime 复用 4×4→5×7 像素 oracle，checksum `e0288a1c4c38d1f8`。固定 `test/jap.jpg` 只作既有 OCR/runtime 回归，不外推通用日语 OCR／翻译质量；Koharu artifact readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`。

### v3.264 Koharu 垂直 line quad bilinear warp 合同

- vertical quad fallback 必须保留 detector bbox primary；只有弱 bbox recognition 才执行 `cropQuad` fallback。Koharu axis target 继续由 quad 长短轴、4096 dimension 与 4,000,000 pixels bound 决定。
- vertical path 必须从 canonical DeviceRGB crop 直接求 destination-to-source projective map，并按 image-rs `Interpolation::Bilinear` 语义做 floor 四邻域、常量黑边采样；不得退回“Core Image natural extent + Core Graphics `.high` 二次 resize”作为 vertical warp 实现。采样结果再 rotate270；无效／失败和 generic quad 保留 natural projection fallback。
- `scripts/test-v3264-koharu-vertical-quad-warp-contract.py` 锁定 geometry、采样、channel、CI route 与 `3.264` 版本；`scripts/test-v3264-koharu-vertical-quad-warp-runtime.sh` 锁定 4×4→5×7 checksum `e0288a1c4c38d1f8`。
- exact-SHA full [31559883595](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31559883595)（实现 SHA `a8816fd2a11a64317625f0970c9eeace7ea72d1f`，Xcode/JUnit `10/10`）通过；PR #343 merge SHA `d19f0c9e715d0856f80c4d2a906caa6eb5a193d5`，合入后 push CI [31560465371](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31560465371) 通过。
- 本版只改善垂直 quad 的像素采样一致性，不声称通用日语 OCR／翻译质量提升；Koharu artifact readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`。

### v3.263 图片 OCR 单块重新识别 scoped cancel 合同

- `imageTranslationRerecognizingBlockID != nil` 时必须显示专用“取消重新识别”，只调用 `cancelImageTranslationBlockRerecognition()`；不得调用全局 `cancelImageTranslation()`，不得清空 reviewed block IDs、替换 image task ID、invalidate scoped request 或把整图状态强制设为 idle。
- scoped `CancellationError` 必须继续校验 request/content identity，清理 scoped block/task、恢复 `previousState`、写入取消消息并递增 `imageTranslationBlockRerecognitionFailureGeneration`；旧 block、其它译文和复查进度保持不变。全局取消路径仍保留原有整图 cleanup。
- `scripts/test-v3263-image-ocr-scoped-rerecognition-cancel-contract.py` 锁定 Store、命令栏、状态 VoiceOver、全局边界、CI route 和 `3.263` 版本；本地与云端 full 均通过。
- exact-SHA full [31557987897](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31557987897)（SHA `92b64f404eb3cf82ad033bfedfd59b4740ab367c`，Xcode/JUnit `10/10`）通过并发布 `AITRANS CI/full-validation=success`；PR #341 merge SHA `540f24fbc39a716ecac06fe11a01080c9421bb3b`，合入后 push CI [31558745662](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31558745662) 通过。
- 本版只改善取消操作与辅助功能反馈，不外推通用日语 OCR／翻译质量；Koharu artifact readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`。

### v3.262 Koharu detector Triangle resize 合同

- `ComicTextBubbleDetectorService` 的 detector 640×640 输入必须先从 canonical 8-bit DeviceRGB 生成 RGB plane，再执行 image-rs/Koharu 等价的 separable Triangle sampling；不得继续使用 Core Graphics `.high` 作为等价实现。下采样 support、edge weight normalization、vertical pass 保留 Float、horizontal pass 后统一 round 均属于契约。
- RGB plane 只在最后显式复制为 32BGRA，alpha 固定为 255；detector threshold、ownership bbox／quad、Manga OCR、Vision fallback、12／48 请求预算、取消、布局、翻译、渲染和非图片路径不变。
- `scripts/test-v3262-koharu-detector-triangle-contract.py` 锁定源代码边界、RGB/BGRA 顺序、checksum harness、项目版本与 CI route；`scripts/test-v3262-koharu-detector-triangle-runtime.sh` 以 synthetic 2×2 fixture（checksum `e7e9d1fe4bb47c45`）和 `test/jap.jpg` detector runtime 验证真实 Core ML 路径。历史 v3.254 长页诊断只允许已实测的 `0.940558`、`0.940838`、`0.940873` host geometry values。
- exact-SHA full [31556290782](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31556290782)（SHA `2fd53c4a555b5fe2d41f82a9860b3e3e55c7dc61`，Xcode/JUnit `10/10`）通过并发布 `AITRANS CI/full-validation=success`；PR #339 merge SHA `c7517492a66b3b095bc6e12f8e50d8090d558328`，合入后 push CI [31557042896](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31557042896) 通过。
- 固定样图只证明预处理、detector geometry 与既有 OCR/runtime 回归，不外推通用日语 OCR、翻译或识别质量；Koharu artifact readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`。

### v3.261 图片 OCR Vision 恢复焦点来源合同

- 局部预览触发恢复时必须记录 `.preview`，结果行触发时保留 `.row`；确认成功后按来源分别聚焦预览文字块或结果行。若 restored block 不在当前筛选中，必须清理隐藏 selection 并回退到可见结果、完成态、筛选控件或空态。
- origin 是 View-only state，不进入 `TranslationSessionStore`、持久化或 OCR pipeline；新图片 revision、取消／关闭确认框会清理 pending origin。现有 Store Vision baseline 恢复、OCR、翻译、布局、导出与非图片路径不变。
- 新增 `scripts/test-v3261-image-ocr-restore-focus-origin-contract.py` 并更新 v3.322/v3.332/v3.341 等历史合同以接受等价 helper；本地全量 `281` 个 `scripts/test-v*.py` 合同和既有 Core ML runtime 通过。
- exact-SHA full [31505154226](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31505154226)（SHA `c74205dbae3549b151ec536e9556c05b7a639207`，Xcode/JUnit `10/10`，0 failures）通过并发布 `AITRANS CI/full-validation=success`；PR #337 merge SHA `1fa5ddaf2127946d817734da03565390515fa99a`，合入后 push CI [31506507801](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31506507801) 通过。probe 为 `skip`，readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不声称固定样图代表通用 OCR／翻译质量。

### v3.260 Koharu Manga OCR RGB luma contract

- Manga OCR 预处理必须先用 32-bit canonical DeviceRGB 读取像素，再按 image-rs/Koharu 的 `(2126R + 7152G + 722B) / 10_000` 整数 floor 写入 luma；224×224 nearest floor coordinate mapping 保持不变。不得把隐式 DeviceGray 或四舍五入当作等价实现。
- 新增 `scripts/test-v3260-koharu-manga-ocr-rgb-luma-contract.py` 与 `scripts/test-v3260-koharu-manga-ocr-rgb-luma-runtime.sh`，锁定 RGB 权重、floor probe、校验和与 CI 路由；本地 `280` 个 `scripts/test-v*.py` 合同和既有 Core ML runtime 通过。
- exact-SHA full [31501763083](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31501763083)（SHA `a2963ff338a065a78112b451c37f3e1558f3e2a0`，Xcode/JUnit `10/10`，0 failures）通过并发布 `AITRANS CI/full-validation=success`；PR #335 merge SHA `68657d18ca192cd52c793064203f519d8d5c770e`，合入后 push CI [31503137128](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31503137128) 通过。probe 为 `skip`，readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不声称固定样图代表通用 OCR／翻译质量。

### v3.208 日语 pixel-first detector 合同

- 普通图片源语言为日语时，`VisionOCRService` 在既有 page／block observation 之外，对 90°／270° 旋转图执行系统 `VNDetectTextRectanglesRequest`，只把映射回原图且满足竖排比例／尺寸门控、未被已有 vertical block 覆盖的最多 12 个矩形交给既有 crop/OCR helper。
- detector 结果继续使用 Koharu 风格 grayscale／有界放大、crop 映射与日语去重，最多 4 次 opposite orientation fallback；detector 只提供 geometry，不加载 Manga OCR/PaddleOCR 模型，不读取探针、ground truth 或 artifact。
- 新增 `scripts/test-v3208-image-japanese-koharu-pixel-detector-contract.py` 并接入 UI/full fail-fast；exact-SHA full [31295791350](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31295791350)（SHA `41eff6cb86073900332d9785eea32606a5688dce`）Xcode/JUnit `10/10` 通过；PR #272 fast [31296131671](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31296131671) 与 merge fast [31296221789](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31296221789) 复用候选 full，merge SHA `7c8642af855fcbf79cfad7a3a9052a5465d83632`，后三者 Xcode skipped；探针默认 skip，readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不得声称 OCR／翻译／识别质量提升。

# 测试规范
本文指导 Agent B 和 Agent C 选择 AITRANS 的验证层级。默认云端快验、本机只做轻量检查；只有人工明确要求“本机测试 / 本地 build / 本地跑探针 / 本地 xcodebuild”时，才把本机 Xcode build 或漫画探针作为默认验证路径。

### v3.241 Manga OCR 竖排 quad warp 合同

- 上述 bounded warp 仅由 `MangaOCRRequest.cropQuadIsVertical == true` 的严格日语竖排 hint 触发；未标记的通用 quad 保留自然 projection，以维持历史兼容回退。

- `MangaOCRService` 必须继续先把 `request.cropRect` 作为 `primaryBoundingBoxCrop`，只把严格门控的 `request.cropQuad` 保存为 `lineQuadFallbackCrop`，并仅在 bbox 结果弱时调用 quad reread；不得改变 detector `textRect` ownership、batch／单 crop 故障隔离、取消传播或 12／48 请求预算。
- `perspectiveCorrectedCrop` 在 Core Image projection 成功后，按四点中点轴长计算 Koharu `textHeight` 与 `ratio`，把竖排 quad 有界重采样到 `(textHeight, textHeight × ratio)`（最长边 `4096`、单条最多 `4_000_000` 像素），随后以 `rotate270` 进入 Manga OCR；target／resize／rotation 失败保留自然 warp，projection 失败继续由 bbox crop 兜底。
- 新增 `scripts/test-v3241-image-japanese-manga-ocr-vertical-quad-warp-contract.py` 并接入 UI/full fail-fast；只验证源代码边界和既有单页／长页 runtime 回归，不把 `test/jap.jpg` 外推为通用日语 OCR／翻译质量，也不加载外部 Koharu artifact。

### v3.232 detector line quad Manga OCR crop

- Vision 字符框只有在至少两个字符、与 detector `rect` 和候选 envelope 的 overlap／coverage、面积比、横向／纵向支持以及宽度收窄门控全部通过时，才形成可选 `ImageOCRLayoutQuad`；它只作为 Manga OCR 的 recognition-only crop geometry，`textRect`、layout、去重与 detector ownership 继续使用 detector `rect`。
- `MangaOCRService` 使用 Core Image `CIPerspectiveCorrection` 执行 bounded line crop；quad 缺失、退化、投影失败或模型／单 crop 错误时回退既有扩展 `cropRect`。batch、12／48 预算、取消传播、Vision fallback、翻译、渲染与非日语路径不变。
- 新增 `scripts/test-v3232-image-japanese-koharu-line-quad-manga-ocr-contract.py` 并接入 UI/full fail-fast；工程版本为 `3.232`。本地 v3 合同共 `232` 份，单页继续精确返回 `5` 个 vertical blocks，四页长图继续返回 `17` blocks／`16` vertical／底部 y 约 `0.940558`；exact-SHA full [31379487189](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31379487189) 对 SHA `f030b9582d1eadb45a3c73acdf8c24219b35ba20` 完成 Xcode `26.6 (17F113)`、JUnit `10/10` 与 `AITRANS CI/full-validation=success`，probe 按配置为 `skip`。固定 fixture 只验证 line crop geometry 与既有 runtime 回归，不声称通用日语 OCR、翻译或识别质量，Koharu artifact readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`。

### v3.231 detector-owned tight crop hint

- `japaneseDetectorCropHint` 只从 Vision 字符框生成 Manga OCR 的 crop-only hint；RT-DETR `rect` 继续作为布局、去重和 detector ownership 几何。至少两个字符、竖排候选以及 overlap `>=0.80`、detector coverage `>=0.55`、candidate coverage `>=0.80`、面积比 `0.35...1.05`、横向 coverage `>=0.45`、纵向 coverage `>=0.85`、宽度收窄 `>=10%` 全部通过时才使用 hint，否则回退 detector bbox。
- 新增 `scripts/test-v3231-image-japanese-detector-tight-crop-hint-contract.py` 并接入 UI/full fail-fast；工程版本为 `3.231`。模型加载／单 crop 故障／取消传播、Vision fallback、长页预算、布局、翻译、渲染和非日语路径不变。
- 本地 `249` 份合同和单页／长页真实 Core ML runtime 通过；exact-SHA full [31372501552](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31372501552) 对 SHA `bb579e97f9ded42d7b0352dcccc5592194610e20` 使用 Xcode `26.6 (17F113)` 完成 UI/Speech/home/paste、JUnit `10/10` 与 `AITRANS CI/full-validation=success`，probe `skip`。本版本只验证固定 fixture 的 detector crop 几何边界，不新增 OCR accuracy、ground-truth、metrics 或 output 声明；Koharu artifact readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`。v3.157/v3.158 已合入当前基线，无本地／origin 活动分支或 stale ref。

### v3.230 batch runtime provenance parser

- `scripts/test-v3214-image-japanese-manga-ocr-runtime.sh` 的 harness 输出先包含 `batchInference=true`、`blocks=5` 等元数据，再输出带方向的 block 记录；parser 只消费 `horizontal|vertical|unknown` 制表符记录，不能把元数据当作 provenance。
- `scripts/test-v3230-image-japanese-batch-runtime-parser-contract.py` 锁定该解析边界、v3.229→v3.230 CI 顺序和工程版本。exact-SHA full [31370139122](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31370139122) 对 SHA `064810987125742b31ff0e5cc422d35b576a37f3` 已完成 Xcode、单页 batch runtime、长页 batch runtime 与 JUnit `10/10`（0 failures）；不能把旧 run 的 parser 误报当成模型失败或以 Vision fallback 冒充 batch 成功。
- 该修复只纠正验证器边界，不新增 OCR accuracy 或 ground-truth 指标；Koharu artifact readiness 仍独立门控。

### v3.229 flexible-batch encoder shape fix

- `scripts/test-v3229-image-japanese-batch-model-shape-contract.py`：锁定 encoder `EnumeratedShapes(1…4)`、CLS `fill` 广播、encoder 模型规格 SHA，以及 decoder 动态 sequence／legacy fallback 边界。
- v3.228 云端 run `31366707811` 的 Xcode build 通过，但实际 encoder runtime 报 `tile` shape inference 错误并被 contract 拒绝；本版本必须重新完成 Xcode、单页和长页 Core ML runtime，不能以 capability 或 Vision fallback 冒充 batch 成功。
- 本版本不新增 OCR accuracy 或 ground-truth 指标；`test/jap.jpg` 只验证 batch 执行和既有几何／布局回归，Koharu artifact readiness 仍单独门控。

### v3.228 flexible-batch Manga OCR

- `scripts/test-v3228-image-japanese-bundled-batch-runtime-contract.py`：验证两个 batch Core ML 包的 hash、Manifest、Xcode Resources、`1…4` shape provenance、legacy fallback、CI 路由以及单页／长页 harness 的 `batchInference=true` 断言。
- `scripts/test-v3214-image-japanese-manga-ocr-runtime.sh` 与 `scripts/test-v3218-image-japanese-long-page-manga-ocr-runtime.sh`：在完整 Xcode 环境编译 batch 包并运行真实 Core ML；batch 编译或 capability 失败时不得以 Vision fallback 冒充通过。
- 本版本不新增 OCR accuracy 或 ground-truth 指标；固定 `test/jap.jpg` 只验证模型执行与既有几何／布局回归，Koharu artifact readiness 仍单独门控。

### v3.221 Koharu detector-owned 日语 OCR supplement 合同

- 成功 bundled Manga OCR 的 `verticalLine` 且 `preservesDetectorTextRegionBoundary` 结果是该 TextRegion 的 owner；最终日语 layout 前只过滤 `.page`／旋转 Vision observation，且要求日语脚本密度 `>= 0.5`、与 owner 的最小面积覆盖 `>= 0.60`。line、block、tile crop 与未重叠横排音效继续保留。
- detector 返回空结果时过滤 helper 原样返回全部 observation，因此模型加载／推理失败、取消、Vision fallback、普通语言、翻译、渲染、Store、探针、ground truth、metrics 与 `output` 边界不变。
- 新增 `scripts/test-v3221-image-japanese-detector-owned-vision-noise-contract.py`，并把既有长页真实 runtime 提升为重叠几何 gate。`test/jap.jpg` 单页保持 5 个 vertical blocks；四页长图要求至少 16 个 blocks、每个季度至少 4 个 vertical blocks，本地保持 16 个 vertical blocks，重叠 `やがってま` 消失，未重叠 `ニコッ` 保留；固定样图不作为通用 OCR 质量声明。

### v3.212 Koharu 日语 crop raw recognition 合同

- `recognizeObservations` 默认必须显式保持 `request.usesLanguageCorrection = true`，仅在受限 caller 传入 `false` 时关闭；page reconnaissance 与非日语路径不得传入 `false`。日语 `recognizeJapaneseCropPass` 和 `recognizeJapanesePerspectiveLineCrop` 必须同时保留日语 post-process、language-specific gate 与 raw correction 边界。
- 新增 `scripts/test-v3212-image-japanese-koharu-raw-crop-recognition-contract.py` 并接入 UI/full fail-fast；本地 v3.157-v3.212 共 `56/56` 个合同通过，v3.157/v3.158 已合入当前基线、无活动分支。exact-SHA full [31302657064](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31302657064)（SHA `bd7c510b99ac78c22ca330ae2e125a5193610fe4`）Xcode/static/UI/Speech/home/paste 成功，JUnit `10/10` 且 0 failures；probe `skip`，readiness `manifestMissing / stopUntilArtifactsProvided`，不得声称日语 OCR、翻译、识别或 Koharu 质量提升。
- 候选 metadata [31309651292](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31309651292)、PR #276 fast [31309712340](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31309712340) 与 merge fast [31309783552](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31309783552) 均成功复用候选 receipt；merge SHA `ccab9e318b0c71447b59cb2b370d5778a9c68904`，后三者 Xcode skipped，不是新的编译证据。

### v3.211 日语竖排 Vision 语言门控合同

- line/block/tile reread 使用 `ja-JP`/`ja`，页级 reconnaissance 保留混合日语／拉丁集合；缺少语言 profile 时只跳过 language-specific reread，不影响页级结果。新增 `scripts/test-v3211-image-japanese-vertical-language-gate-contract.py` 并接入 UI/full fail-fast；exact-SHA full [31300669764](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31300669764)（SHA `c0c26aaddb3db641c59cb878d1434207b9879f54`）Xcode/JUnit `10/10` 通过。probe `skip`，readiness `manifestMissing / stopUntilArtifactsProvided`，不声称日语 OCR、翻译或识别质量提升。

### v3.210 图片翻译文字块单独重试合同

- `.failed`／可恢复的 `.translated` 图片结果只允许原文非空且译文为空的文字块重试；已完成译文、block geometry 与 OCR 原文保留，不重新调用 `visionOCRService` 或 `recognizeTextBlocks`。
- 日语单块继续走既有 `translateJapaneseImageBatch` 的 `[N]` 协议，非日语走既有单块 `translate`；retry ID、content task ID 与原文一致性共同阻止过期结果写回。部分成功保持 `.failed` 并允许继续重试，全部译文完成后才恢复 `.translated`、更新转录并重绘导出。
- 结果行和局部预览提供图标按钮、状态 value、动态 hint 与 VoiceOver action；新增 `scripts/test-v3210-image-translation-block-retry-contract.py` 并接入 UI/full fail-fast。本地 v3.157–v3.210 共 54 个合同通过；exact-SHA full [31299660925](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31299660925)（SHA `b9ec296d0cdafbe0bfbbe0aebc90e1255a44d6d2`）Xcode/JUnit `10/10` 且 0 failures；候选 metadata [31300023503](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31300023503) 对 docs SHA `0dc5b019e231aa35137de705a6a2b8e0a377d029` 复用成功 full，PR #274 fast [31300071078](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31300071078) 与 merge fast [31300107560](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31300107560) 均复用候选 full，merge SHA `ee7e41f0679fd999b8f9337a3bf0622742e095c3`；后三者 Xcode skipped，不是新的编译证据。v3.157/v3.158 已合入当前基线，无活动分支，probe `skip`，readiness `manifestMissing / stopUntilArtifactsProvided`，不得声称日语 OCR、翻译、识别或 Koharu 质量提升。

### v3.209 Koharu 日语竖排 line-first dispatch 合同

- `recognizeJapaneseVerticalCrops` 先运行 `recognizeJapaneseVerticalLineCrops`，pixel detector 与 tile fallback 接收 line observations，只跳过被可靠 line reread 覆盖至少 `0.60` 的区域，block crop 仍是最后兜底；pixel detector OCR 结果使用 `.verticalLine` provenance，tile fallback 保持历史 `.crop` provenance。
- 可靠 line coverage 仅接受非空文本、`confidence >= 0.48`、日语脚本密度 `>= 0.5` 和有效 `lineRegionRect ?? rect`；弱、空、非日语或非法 geometry 不抑制更宽 recovery。普通语言、布局、翻译、渲染、Store、探针、ground truth、metrics 与 `output` 边界不变。
- 新增 `scripts/test-v3209-image-japanese-koharu-line-first-dispatch-contract.py` 并接入 UI/full fail-fast；本地 v3.157–v3.209 共 53 个合同通过；exact-SHA full [31297254547](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31297254547)（SHA `17f19bb2505d504e1255ab925d2aa7572020435a`）Xcode/JUnit `10/10` 且 0 failures；PR #273 fast [31297894114](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31297894114) 与 merge fast [31297941634](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31297941634) 均复用候选 full，merge SHA `4e2b8fdceec51359bb923bd583687fa2e3ed9e24`，fast Xcode skipped。探针 `skip`，真实 Koharu readiness `manifestMissing / stopUntilArtifactsProvided`，不得声称日语 OCR、翻译、识别或 Koharu 质量提升。

### v3.207 Koharu 日语竖排 line coverage quality 合同

- `hasCompleteJapaneseLineCoverage` 在 tight geometry 与一对一 source-line 匹配之外，要求 `isReliableJapaneseLineCoverageResult`：结果非空、`confidence >= 0.48`、日语脚本密度 `>= 0.5`；多 glyph source line 不接受单 glyph 结果，避免弱 OCR 被误当成完整覆盖。
- 质量门控失败时继续执行既有 block crop fallback；line perspective／axis、方向 fallback、去重、布局、翻译、渲染、Store、探针、真实 Koharu artifact 边界不变。新增 `scripts/test-v3207-image-japanese-koharu-line-coverage-quality-contract.py` 并接入 UI/full fail-fast；本地 v3.157–v3.207 共 51 个合同通过。候选 exact-SHA full [31294146132](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31294146132)（`f7a18e4c008903fd50f15183fa3b9a8629216bef`）Xcode/JUnit `10/10` 且 0 failures；候选 metadata [31294486910](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31294486910)、PR fast [31294542723](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31294542723)、merge fast [31294614418](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31294614418) 均复用候选 full，merge SHA `15577b7a184f9b6a8d281f1551367b1c72231a65`；后三者 Xcode skipped，不是新的编译证据。`probe_mode=skip`，readiness `manifestMissing / stopUntilArtifactsProvided`，不得声称日语 OCR、翻译、识别或 Koharu 质量提升。

### v3.206 Koharu 日语竖排 observation 行桶回退合同

- `ImageOCRLayoutEngine.recursiveMangaReadingOrder` 在没有有效 XY-cut 或切分失效时调用 `fallbackMangaObservationReadingOrder`；按 `4 × minimumGapY` 行桶先读上方，同一行按 `midX` 从右到左，再以 y、宽高、文字、confidence 稳定 tie-breaker，避免重叠竖排列全局 x-first 交错。
- 混合 block 的既有 `fallbackMangaBlockReadingOrder`、普通语言 `interleaveReadingOrder`、OCR/翻译/渲染/Store/探针/真实 Koharu artifact 边界不变。新增 `scripts/test-v3206-image-japanese-koharu-observation-row-fallback-contract.py` 并接入 UI/full fail-fast；实现 full [31293120347](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31293120347)（`5aefe027e97f37aa209c09d2a9d33ecf0a1d848c`）Xcode/JUnit `10/10` 且 0 failures；PR #270 fast [31293135057](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31293135057) 与 merge fast [31293388944](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31293388944) 复用成功 full，merge SHA `9513cd7c9d33610f0b93a4e435f9e3f1867328bb`，后两者 Xcode skipped，不是新的编译证据。v3.157/v3.158 已合入当前基线并继续回归；`probe_mode=skip`，readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不得声称日语 OCR、翻译、识别或 Koharu 质量提升。

### v3.205 Koharu 日语竖排 line coverage fallback 合同

- 普通图片源语言为日语时，block crop 只有在每个可枚举 source line 都被独立、有效、紧 geometry 对齐的 `verticalLine` reread 覆盖后才跳过；部分 line 成功、合成 envelope、噪声结果、缺失或非法 geometry 继续走 block fallback，避免多行 TextRegion 丢失未读文字。
- 新增 `scripts/test-v3205-image-japanese-koharu-line-coverage-fallback-contract.py` 并接入 UI/full fail-fast；v3.157/v3.158、v3.194–v3.204 合同继续回归。实现 exact-SHA full [31292332659](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31292332659)（`7891cfeaf3486eb6a507d1b2045a9b662b8c66ca`）Xcode/JUnit `10/10` 且 0 failures；`probe_mode=skip`，readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不得声称日语 OCR、翻译、识别或 Koharu 质量提升。

### v3.204 Koharu 日语竖排 line-first OCR 合同

- 普通图片源语言为日语时，`recognizeJapaneseVerticalLineCrops` 先消费与 vertical block 归属相符的 line-region proxy；只有 line perspective／轴对齐 reread 没有可用 observation 时，才执行原 block crop fallback，避免同一 TextRegion 被宽 block 重复读取。
- line path 继续复用 v3.203 tight ownership、`verticalLine`／rotate270 provenance、既有方向 fallback、原图映射、去重与有界预算；block、tile、page、非日语、翻译、渲染、Store、探针、ground truth、metrics 与 `output` 边界不变。
- 新增 `scripts/test-v3204-image-japanese-koharu-line-first-ocr-contract.py` 并接入 UI/full fail-fast；v3.157/v3.158、v3.159/v3.160 与 v3.201–v3.203 合同继续回归。实现 exact-SHA full [31290525270](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31290525270)（`ae922bda0bf566cc14d422a6d9c9a4c042b34218`）Xcode/JUnit `10/10` 且 0 failures；候选 metadata [31290904290](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31290904290)、PR #268 fast [31290942391](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31290942391) 与 merge fast [31290981606](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31290981606) 均复用成功 receipt，merge SHA `b65653bc577ba65c51ed6cc1c2bd373b00e76aec`；后三者 Xcode skipped，不是新的编译证据。探针 `skip`，真实 Koharu readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不得声称日语 OCR、翻译、识别或 Koharu 质量提升。

### v3.203 Koharu 日语竖排 line-block ownership 合同

- 普通图片源语言为日语时，line candidate、`synthesizeJapaneseVerticalLineCandidates` 与 `koharuVerticalBlockCropRect` 在宽 `observation.rect` overlap 之外，若存在有效 `lineRegionRect`，必须要求紧区域与当前 vertical block 的 overlap `>= 0.25`；缺失／非法紧 geometry 回退宽框，避免相邻列污染当前 TextRegion。
- 该 ownership gate 只作用于日语 line candidate／碎片合成／block envelope，不改变布局使用的宽 request box、`isVerticalLineCandidate` 的 `1.25`／`0.018` 门控、perspective／axis crop、`verticalLine` provenance、rotate270 主方向与 opposite fallback；其他语言、翻译、渲染、Store、探针、ground truth、metrics 与 `output` 不变。
- 新增 `scripts/test-v3203-image-japanese-koharu-line-block-ownership-contract.py` 并接入 UI/full fail-fast；v3.202、v3.201、v3.200、v3.199 及更早合同继续回归。实现 exact-SHA full [31287319601](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31287319601)（`01fdaf16dde9029079231eb7c5406042fcab8cfc`）Xcode/JUnit `10/10` 且 0 failures；候选 metadata [31287648270](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31287648270)、PR #267 fast [31287677451](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31287677451) 与 merge fast [31287707581](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31287707581) 均复用成功 receipt，merge SHA `295c59a72a886cbc19cd9c3126d9e162ce525afd`；后三者 Xcode skipped，不是新的编译证据。探针 `skip`，真实 Koharu readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不得声称日语 OCR、翻译、识别或 Koharu 质量提升。

### v3.202 Koharu 日语竖排紧 line-region candidate gate 合同

- 普通图片源语言为日语且进入 `recognizeJapaneseVerticalLineCrops` 时，`isVerticalLineCandidate` 必须接收 `observation.lineRegionRect ?? observation.rect`；Vision 字符范围缺失时回退 request-level box。与 vertical block 的 `overlapRatio` 仍必须使用宽 `observation.rect`，避免紧 line geometry 改写布局／去重外框。
- 该 gate 只作用于日语 line candidate 的高宽比／高度筛选，保留既有 `1.25`、`0.018`、最多 24 条、perspective／axis crop、`verticalLine` provenance、rotate270 主方向与 opposite fallback；page、block、tile、非日语、翻译、渲染、Store、探针、ground truth、metrics 与 `output` 不变。
- 新增 `scripts/test-v3202-image-japanese-koharu-tight-line-candidate-gate-contract.py` 并接入 UI/full fail-fast；v3.201、v3.200、v3.199、v3.160 及更早合同继续回归。实现 exact-SHA full [31286506178](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31286506178)（`2f198f9f12e62c5e10fe7a73b76cdc0af9d69107`）Xcode/JUnit `10/10` 且 0 failures；候选 metadata [31286843872](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31286843872)、PR #266 fast [31286875844](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31286875844) 与 merge fast [31286908329](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31286908329) 均复用成功 receipt，merge SHA `839c5e9d9f5705f50c85d65e7085157c5b876b07`；后续 fast 跳过 Xcode，不是新的编译证据。探针 `skip`，真实 Koharu readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不得声称日语 OCR、翻译、识别或 Koharu 质量提升。

### v3.201 Koharu 日语竖排 line orientation provenance 合同

- 普通图片源语言为日语且进入 `recognizeJapaneseVerticalLineCrops` 时，perspective／轴对齐 line pass 必须标记 `VisionOCRObservationRole.verticalLine`；该角色要随 Vision observation、crop mapper、perspective result、合成候选和最终 dedupe 保留，使 `rotate270` 成为 line 专用的有界主方向偏好，弱／空结果仍按既有预算 fallback 到 90°。
- page、block、tile 与非日语 observation 不得被该角色改写：page／block 继续 90° tie-breaker，tile 继续 90° 主／270° fallback；不改变整页 OCR、布局、翻译、渲染、Store、探针、ground truth、metrics 与 `output`，不加载 Manga OCR/PaddleOCR 权重，也不把 `test/jap.jpg` 当质量指标。
- 新增 `scripts/test-v3201-image-japanese-koharu-line-orientation-provenance-contract.py` 并接入 UI/full fail-fast；v3.200、v3.199、v3.198 及更早合同继续回归。实现 full [31262554391](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31262554391)（`97120cf38d85729f605e3d8bdbc836a0271e1c99`）Xcode/static/UI/Speech/home/paste 成功，JUnit `10/10` 且 0 failures；候选 metadata [31262979444](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31262979444)、PR #265 fast [31263017146](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31263017146) 与 merge fast [31263072991](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31263072991) 均复用成功 receipt，merge SHA `3aac10326a987a47ea1786cd76c37b96b3ca9b36`；后两者跳过 Xcode，不是新的编译证据。三次均为 `probe_mode=skip`，真实 Koharu readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不得声称日语 OCR、翻译、识别或 Koharu 质量提升。

### v3.200 Koharu 日语竖排 block font-size anchor 合同

- 普通图片源语言为日语且 block 为竖排时，`recognizeJapaneseVerticalCrops` 先通过 v3.199 的 `lineRegionRect` union 形成 envelope，再调用 `expandedKoharuVerticalBlockEnvelopeCropRect(envelope, fontSizeReference: block.rect, imageSize:)`；padding 必须由原始 `block.rect` 的最小边计算（Koharu `detected_font_size_px` 语义），而不是由多行 union envelope 的最小边重新估算，之后将同一方向感知 padding 应用于 envelope。
- 缺少或非法紧 geometry 时继续回退旧 `expandedVerticalCropRect`；line、tile、非日语、整页 OCR、翻译、渲染、Store、探针、ground truth、metrics 与 `output` 路径不变，不加载 Manga OCR/PaddleOCR 权重，也不把 `test/jap.jpg` 当质量指标。
- 新增 `scripts/test-v3200-image-japanese-koharu-font-anchor-contract.py` 并接入 UI/full fail-fast；v3.199、v3.198、v3.178、v3.175 及更早合同继续回归。实现 exact-SHA full [31260969111](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31260969111)（`c91858868cace78b846bd742f69a95f765b5737a`）Xcode/static/UI/Speech/home/paste 成功，JUnit `10/10` 且 0 failures；候选 metadata [31261967648](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31261967648) 复用 full，PR #264 fast [31261881073](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31261881073) 与 merge fast [31261995539](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31261995539) 均复用成功 receipt，后两者跳过 Xcode，不是新的编译证据。三次均为 `probe_mode=skip`；真实 Koharu readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，无新 metrics/output，不得声称日语 OCR、翻译、识别或 Koharu 质量提升。

### v3.199 Koharu 日语竖排 block line envelope 合同

- 普通图片源语言为日语且 block 为竖排时，`recognizeJapaneseVerticalCrops` 通过 `koharuVerticalBlockCropRect` 收集与 block 有 `overlap >= 0.25` 的有效 `lineRegionRect`，归一化后与原 `block.rect` 做 union，再交给既有方向感知 padding；因此紧 line geometry 可扩展 block crop，但绝不缩小 detector/layout block。
- 缺少或非法 line geometry 时必须回退 `expandedVerticalCropRect(block.rect, imageSize: imageSize)`；非日语、整页 OCR、line/tile reread、翻译、渲染、Store、探针、ground truth、metrics 与 `output` 路径不变，不加载 Manga OCR/PaddleOCR 权重。v3.175/v3.178 历史合同接受等价 helper，但仍验证原有 padding 与 compact block 边界。
- 新增 `scripts/test-v3199-image-japanese-koharu-block-line-envelope-contract.py` 并接入 UI/full fail-fast；v3.198 及更早合同继续回归。候选 exact-SHA full [31260137161](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31260137161)（`b85f12389eddf1cd82d8aa2892fe5f730d4b8a56`）Xcode/static/UI/Speech/home/paste 均成功，JUnit `10/10` 且 0 failures；PR #263 fast [31260466644](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31260466644) 复用候选 full，merge fast [31260501796](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31260501796) 以 `merge_reuses_successful_candidate_full_validation` 复用候选 full（merge SHA `20d5987c245bf6768257e61d6ee030cf2324aef0`，`receiptPropagationAllowed=true`），后两者跳过 Xcode，不是新的编译证据。三次均为 `probe_mode=skip`；真实 Koharu readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，无新 metrics/output，不得声称日语 OCR、翻译、识别或 Koharu 质量提升。

### v3.198 Koharu 日语竖排 line 方向合同

- 普通图片源语言为日语时，`recognizeJapaneseVerticalLineCrops` 的 perspective 与轴对齐 line reread 必须通过共享 helper 以 Koharu `warp_line_region` 的 `rotate270`（270°）作为主方向；结果为空、日语脚本密度低、置信度弱或单字时，仍只在既有 12 次页级预算内使用 90° opposite fallback。block crop 保留候选自身方向，tile fallback 保留 90° 主／270° 弱结果回退。
- 该方向迁移只作用于普通图片日语 line crop，不改变非日语、整页 OCR、block/tile、翻译、渲染、Store、探针、ground truth、metrics 或 `output`，不加载 Manga OCR/PaddleOCR 权重，也不把 `test/jap.jpg` 当质量指标。
- 新增 `scripts/test-v3198-image-japanese-koharu-vertical-line-orientation-contract.py` 并接入 UI/full fail-fast；v3.197 及更早合同继续回归。候选 exact-SHA full [31259014271](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31259014271)（`24c8f9c23f3bec3e6536ad4752e99a4703ff07f4`）Xcode/static/UI/Speech/home/paste 均成功，JUnit `10/10` 且 0 failures；PR #262 fast [31259242739](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31259242739) 复用候选 full，merge fast [31259272510](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31259272510) 复用候选 full（merge SHA `0b7352be9393e17fc55224269604dfc6859d2351`，`receiptPropagationAllowed=true`），后两者跳过 Xcode，不是新的编译证据。三次均为 `probe_mode=skip`；真实 Koharu readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，无新 metrics/output，不得声称日语 OCR、翻译、识别或 Koharu 质量提升。

### v3.197 Koharu 日语竖排 block 检测门控合同

- 普通图片源语言为日语时，既有 `ImageOCRLayoutEngine` 竖排 block 只有在高宽比 `>= 1.15`、方向置信度 `>= 0.25`、归一化高度 `>= 0.035` 时进入 Koharu 风格 block crop；原有 `1.45` 标准门控、`cjkCompactColumnTextRun` 紧凑门控、最多 16 个 block、90°／270° fallback 与失败安全回退继续保留。
- 该门控只位于日语 block crop reread，非日语、整页 OCR、line/tile reread、翻译、渲染、Store、探针、ground truth、metrics 与 `output` 边界不变；不加载 Manga OCR/PaddleOCR 权重，也不把 `test/jap.jpg` 当质量指标。
- 新增 `scripts/test-v3197-image-japanese-koharu-vertical-threshold-contract.py` 并接入 UI/full fail-fast；v3.196 及更早合同继续回归。候选 exact-SHA full [31258318641](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31258318641)（`e099acb375cf799d9f3d26b203eead6505b9b65c`）Xcode/static/UI/Speech/home/paste 均成功，JUnit `10/10` 且 0 failures；PR #261 fast [31258329662](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31258329662) 重跑后复用候选 full，`reusedFullValidationState=success`；merge fast [31258606990](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31258606990) 复用候选 full（merge SHA `bd91910ccfe38b78d2827095b7e2970c1347d881`，`receiptPropagationAllowed=true`），后两者跳过 Xcode，不是新的编译证据。三次均为 `probe_mode=skip`；真实 Koharu readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，无新 metrics/output，不得声称日语 OCR、翻译、识别或 Koharu 质量提升。

### v3.196 日语漫画编号块批翻译合同

- 日语图片翻译在 OCR blocks 上按全局 `[N]` 标签组成最多 8 块、约 1800 字符的有界批次；提示词要求只翻译标签后的文本、保持标签与输入顺序，保留角色语气、情绪、关系、强调和拟声词，不合并／拆分／遗漏／重排。非日语图片和修正 sheet 继续逐块翻译。
- 批输出必须完整覆盖期望 tag、保持稳定顺序且每块非空；缺 tag、乱序、空块或生成错误时回退既有逐块翻译，并在 UI 状态中提示安全回退。Local 与 Mock 适配器都使用同一编号协议；不读取探针、ground truth、真实 Koharu 工件，不更新 metrics/output。
- 新增 `scripts/test-v3196-image-japanese-koharu-batch-translation-contract.py` 并接入 UI/full fail-fast；v3.195 及更早合同继续回归。候选 exact-SHA full [31257482066](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31257482066)（`4282395bd982c2c6fcb92058b3cdfb8409defd01`）Xcode/static/UI/Speech/home/paste 均成功，JUnit `10/10` 且 0 failures；PR #260 fast [31257709942](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31257709942) 复用候选 full，merge fast [31257752177](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31257752177) 复用候选 full（merge SHA `dd007a40705903bcc92800f30a905ead44810503`，`receiptPropagationAllowed=true`），后两者跳过 Xcode，不是新的编译证据。三次均为 `probe_mode=skip`；真实 Koharu readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，无新 metrics/output，不得把此协议迁移描述为日语 OCR、翻译或识别质量提升。

### v3.195 日语混合版面递归阅读顺序合同

- `ImageOCRLayoutEngine.layout` 在 `prefersMangaReadingOrder` 下必须把横排与竖排 block 放入同一集合，按动态中位宽／高中位数阈值递归选择 XY-cut；横向切分右组先读、纵向切分顶部先读，无法切分时按 `4 × min_gap_y` 行桶从右到左稳定回退。
- 非日语调用必须保留既有横／竖交错路径；合同只验证 View-independent layout ordering，不读取探针报告、ground truth 或 `test/koharu_artifacts`，不改变 Vision OCR、翻译、renderer/export、Store、metrics 或 `output`。
- 新增 `scripts/test-v3195-image-japanese-mixed-layout-reading-order-contract.py` 并接入 UI/full fail-fast；v3.194 及更早合同继续回归。候选 exact-SHA full [31233606259](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31233606259)（`52963a4c1cbe16f8662a99ae443aea36f1dbb486`）Xcode/static/UI/Speech/home/paste 均成功，JUnit `10/10` 且 0 failures；PR #259 fast [31233872614](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31233872614) 复用候选 full，merge fast [31234023270](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31234023270) 以 `merge_reuses_successful_candidate_full_validation` 复用候选 full（merge SHA `12b0217c7c56a2993986f4a42ba6e6f98c7df6a2`），后两者跳过 Xcode/UI/Speech，不是新的编译证据。三次均为 `probe_mode=skip`；真实 Koharu 四件套 readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，无新 metrics/output，不得把混合版面排序迁移描述为日语 OCR、翻译或识别质量提升。

### v3.194 日语紧字符区域 IoU 去重合同

- `isDuplicateObservation` 只有在 `prefersJapanese` 且双方都带 `lineRegionRect` 时，才允许把 minimum-area overlap `>= 0.85` 或紧区域 IoU `>= 0.50` 的候选按 Koharu `merge_slice_regions` 几何规则视为重复；IoU 使用交集除以并集并在零面积时安全回退。
- 宽 request-level box、非日语路径与低重叠候选仍要求原有非空文本相等／包含或 `overlap >= 0.72 && textSimilarity >= 0.62`，避免相邻日语竖排列被宽 crop 或普通路径误合并。只影响普通图片日语 OCR fusion，不改变 OCR 模型、布局、翻译、renderer/export、Store、探针、Koharu gate、metrics 或 `output`。
- 新增 `scripts/test-v3194-image-japanese-tight-region-iou-dedupe-contract.py` 并接入 UI/full fail-fast；v3.156–v3.193 日语合同继续回归。候选 exact-SHA full [31232966715](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31232966715)（`e4388409785bc60278b819e36e8b4afdc7ec7307`）Xcode/static/UI/Speech/home/paste 均成功，JUnit `10/10` 且 0 failures；PR #258 fast [31233259741](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31233259741) 复用候选 full，merge fast [31233297104](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31233297104) 以 `merge_reuses_successful_candidate_full_validation` 复用候选 full（merge SHA `5ce315332aa6ab073e3e9733f174cbf2ccac0121`，`receiptPropagationAllowed=true`），后两者跳过 Xcode，不是新的编译证据。三次均为 `probe_mode=skip`；readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，`test/jap.jpg` 只作合同 fixture，无新 metrics/output，不得据此声称日语 OCR、翻译、识别或 Koharu 质量提升。

### v3.193 日语紧字符区域去重合同

- `isDuplicateObservation` 只有在 `prefersJapanese` 且双方都带 `lineRegionRect` 时，才允许把 minimum-area overlap `>= 0.85` 的紧字符区域按 Koharu `merge_slice_regions` 的 containment-like 规则直接视为重复；缺少任一 hint 时继续使用 request-level `rect`。
- 宽 request-level box、非日语路径与低重叠候选仍要求原有非空文本相等／包含或 `overlap >= 0.72 && textSimilarity >= 0.62`，避免相邻日语竖排列被宽 crop 或几何偶合误合并。只影响普通图片日语 OCR fusion，不改变 OCR 模型、布局、翻译、renderer/export、Store、探针、Koharu gate、metrics 或 `output`。
- 新增 `scripts/test-v3193-image-japanese-tight-region-dedupe-contract.py` 并接入 UI/full fail-fast；v3.156–v3.192 日语合同继续回归。候选 exact-SHA full [31232333781](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31232333781)（`a645943b85345790309adde433344a53209bbccc`）Xcode/static/UI/Speech/home/paste 均成功，JUnit `10/10` 且 0 failures；PR #257 fast [31232570686](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31232570686) 复用候选 full，merge fast [31232612519](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31232612519) 以 `merge_reuses_successful_candidate_full_validation` 复用候选 full（merge SHA `c00ffc306a193351179e86b7fd7ad0783bd1ad4b`，`receiptPropagationAllowed=true`），后两者跳过 Xcode，不是新的编译证据。三次均为 `probe_mode=skip`；readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，`test/jap.jpg` 只作合同 fixture，无新 metrics/output，不得据此声称日语 OCR、翻译、识别或 Koharu 质量提升。

### v3.192 日语漫画窗口阅读顺序合同

- `recognizeJapaneseVerticalTileFallback` 必须在消费 `japaneseVerticalSliceWindows` 后先按窗口 `start` 从大到小排序（x 右到左），再在每个窗口内按 `verticalWindows` 的 y 上到下读取；最多 18 个有效窗口预算、覆盖抑制、90° 主读取、最多 4 次 270° fallback、日语过滤、灰度／放大、原图映射与去重边界保持不变。
- 该调度只作用于普通图片日语竖排 fallback，避免预算不足时先消耗漫画右侧阅读前沿；不改变普通语言、整页／block／line OCR、翻译、renderer/export、Store、探针、Koharu active gate、metrics 或 `output`。
- 新增 `scripts/test-v3192-image-japanese-manga-window-order-contract.py` 并接入 UI/full fail-fast；v3.156–v3.191 日语合同继续回归。候选 exact-SHA full [31231339154](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31231339154)（`d4a7811b634df7f300fb60a99e331a27f69287bd`）Xcode/static/UI/Speech/home/paste 均成功，JUnit `10/10` 且 0 failures；PR #256 fast [31231689829](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31231689829) 复用候选 full，merge fast [31231720315](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31231720315) 以 `merge_reuses_successful_candidate_full_validation` 复用候选 full（merge SHA `2aae0d7ff0e5394bed6a0c13edbb3a2624f67c1a`，`receiptPropagationAllowed=true`），后两者跳过 Xcode，不是新的编译证据。三次均为 `probe_mode=skip`；readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，无新 metrics/output，不得声称日语 OCR、翻译、识别或 Koharu 质量提升。

### v3.191 Koharu ImageSlicer 迁移合同

- `japaneseVerticalSliceWindows` 必须使用 Koharu 的目标比例 `3.0`、纵向 overlap `0.20` 与最小尾片比例 `0.70`；目标高度以窄条宽度推导，最后一个窗口必须到达源图底边，尾片过小时并入最后窗口。
- `recognizeJapaneseVerticalTileFallback` 必须从该 helper 消费窗口并保留最多 `18` 个有效窗口预算；窗口的归一化 `y/height` 必须映射回原图，既有覆盖抑制、90° 主读取、最多 4 次 270° fallback、日语脚本／几何过滤、灰度／放大与去重保持不变。
- 新增 `scripts/test-v3191-image-japanese-koharu-slicer-contract.py` 并接入 UI/full fail-fast；v3.156–v3.190 日语合同继续回归。最终 exact-SHA full [31230729061](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31230729061)（`32c350c6ce4c40d90dd1d9505a830c083a62ce49`）Xcode/static/UI/Speech/home/paste 均成功，JUnit `10/10` 且 0 failures；PR #255 fast [31231091935](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31231091935) 复用最终 full，merge fast [31231128313](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31231128313) 以 `merge_reuses_successful_candidate_full_validation` 复用最终 full（merge SHA `16cce70a48afda648f045edf9d97f9a1191890cd`，`receiptPropagationAllowed=true`），后两者跳过 Xcode，不是新的编译证据。三次均为 `probe_mode=skip`；readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，无新 metrics/output，不得声称日语 OCR、翻译、识别或 Koharu 质量提升。

### v3.190 日语局部 tile-window 合同

- `recognizeJapaneseVerticalTileFallback` 必须把横向窄条拆成局部纵向窗口：优先高度为页面的 `0.58`，同时至少覆盖 `tileWidth * 3`；相邻窗口保留 `0.18` overlap，并强制覆盖页面底边，避免长漫画页中的文字在全高 crop 内占比过小。
- 只对未被既有竖排 block 覆盖且成功裁剪的窗口计入预算，总有效窗口最多 `12`；每个窗口的归一化 `y/height` 必须映射回原图。已有 90° 主读取、最多 4 次 270° 弱结果 fallback、灰度／放大、日语脚本与竖排几何过滤、坐标映射和最终去重保持不变。
- 新增 `scripts/test-v3190-image-japanese-localized-tile-window-contract.py` 并接入 UI/full fail-fast；v3.156–v3.189 日语合同继续回归。候选 exact-SHA full [31229567448](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31229567448)（`44e0030aa1914468fceedfc5404eaf7510e9673b`）Xcode/static/UI/Speech/home/paste 均成功，JUnit `10/10` 且 0 failures；PR #254 fast [31229946643](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31229946643) 与 merge fast [31229977158](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31229977158) 均复用候选 full（merge SHA `ec8ad6333005527042fd7f13f8f203bfa36fafe5`，`receiptPropagationAllowed=true`），后两者跳过 Xcode，不是新的编译证据。三次均为 `probe_mode=skip`；readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，无新 metrics/output，不得声称日语 OCR、翻译、识别或 Koharu 质量提升。

### v3.189 日语单字 crop direction-hint 合同

- `resolveDirection` 必须在日语 manga-order、允许竖排且 `sourceDirectionHint == .vertical` 时接受任意含 CJK 的 crop 文本；不得再要求 `containsTextRun`（至少两个 CJK），这样 Vision 拆出的单 glyph 仍保持 Koharu `TextBox.source_direction`。
- hint 仍须位于 `wideBox` 回退之前；只有明确的日语竖排 block／line／tile crop／合成结果设置 hint，页级 `mapRotatedObservation`、普通语言、横排与非日语路径不受影响。该 layout-only 门控不读取探针、ground truth 或真实 Koharu 工件，不改变 OCR 模型、翻译、renderer/export、Store、Koharu gate、metrics 或 `output`。
- 新增 `scripts/test-v3189-image-japanese-single-glyph-direction-hint-contract.py` 并接入显式 UI/full fail-fast；v3.156–v3.188 日语合同继续回归。候选 exact-SHA full [31228731388](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31228731388)（`8c89b0c0d1c0dff91efd3c115583ab5f04d14017`）Xcode/static/UI/Speech/home/paste 均成功，JUnit `10/10` 且 0 failures；PR #253 fast [31229051329](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31229051329) 复用候选 full，merge fast [31229096792](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31229096792) 以 `merge_reuses_successful_candidate_full_validation` 复用候选 full（merge SHA `6a510efece0b7ef6deeb9f1c3dd19c11f625ba1a`，`receiptPropagationAllowed=true`），后两者跳过 Xcode，不是新的编译证据。三次均为 `probe_mode=skip`；真实 Koharu readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，`test/jap.jpg` 只作 fixture，无新 metrics/output，不得声称日语 OCR、翻译、识别或 Koharu 质量提升。

### v3.188 日语竖排 Cluster reading-order 合同

- `Cluster.block` 在方向为 `.vertical` 时必须先对已形成的同列 observation 显式排序：`rect.y` 上到下；同 y 以 `midX` 右到左；再以宽高、文本和 confidence 做确定性 tie-breaker 后拼接。不得依赖 block merge 的到达顺序；横排 `observations.enumerated().reduce` 换行逻辑保持不变。
- `shouldMergeVertically` 仍必须保留同列、有限纵向 gap 与重叠／中心距离门控；排序只修正同一 vertical cluster 的文字顺序，不扩大候选、改变普通语言、翻译、renderer/export、Store、Koharu gate、metrics 或 `output` 边界。
- 新增 `scripts/test-v3188-image-japanese-vertical-cluster-reading-order-contract.py` 并接入显式 UI/full fail-fast；v3.156–v3.187 日语合同继续回归。候选 exact-SHA full [31227754288](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31227754288)（`1580a5c145efede4fefa23fd743c8170e077b1f9`）Xcode/static/UI/Speech/home/paste 均成功，JUnit `10/10` 且 0 failures；PR #252 fast [31228156354](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31228156354) 复用候选 full，merge fast [31228206021](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31228206021) 以 `merge_reuses_successful_candidate_full_validation` 复用候选 full（merge SHA `bbba2eee0a31a3bfd8b82508c77caac3677e1810`），后两者跳过 Xcode，不是新的编译证据。三次均为 `probe_mode=skip`；真实 Koharu readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，`test/jap.jpg` 只作 fixture，无新 metrics/output，不得声称日语 OCR、翻译、识别或 Koharu 质量提升。

### v3.187 日语 crop direction provenance 合同

- `ImageOCRLayoutObservation` 必须提供可选 `sourceDirectionHint`；`resolveDirection` 仅在允许竖排、日语 manga-order、hint 为 `.vertical` 且文本含至少两个 CJK scalar 时，以 `koharuVerticalCropHint` 先于 `wideBox` 回退标记竖排。页级 observation 未设置 hint，普通语言与非日语路径继续使用原几何启发式。
- 只有日语竖排 block／line／tile crop reread 的映射／合成结果设置 `.vertical` hint；整页 `mapRotatedObservation` 不设置，避免把任意页级 90°／270° observation 当成可信 detector source direction。hint 只影响布局方向，不读取模型、探针、ground truth 或真实 Koharu 工件，不改变 OCR、翻译、renderer/export、Store、Koharu gate、metrics 或 `output`。
- 新增 `scripts/test-v3187-image-japanese-crop-direction-hint-contract.py` 并接入显式 UI/full fail-fast；v3.156–v3.186 合同继续回归。候选 exact-SHA full [31226671116](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31226671116)（`881d2b4fe49d8adde181d8e33d210a38515fcdd8`）Xcode/static/UI/Speech/home/paste 均成功，JUnit `10/10` 且 0 failures；PR #251 fast [31226855629](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31226855629) 重跑后复用候选 full，merge fast [31227082382](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31227082382) 以 `merge_reuses_successful_candidate_full_validation` 复用候选 full（merge SHA `c1bb36ba956e5a48b583ff1e2a2214e3dcee916c`），后两者跳过 Xcode，不是新的编译证据。三次均为 `probe_mode=skip`；真实 Koharu readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，`test/jap.jpg` 只作 fixture，无新 metrics/output，不得声称日语 OCR、翻译、识别或 Koharu 质量提升。

### v3.186 日语竖排 tile 结果过滤合同

- `recognizeJapaneseVerticalTileFallback` 必须先对 90° tile pass 的结果调用 `filterJapaneseVerticalTileObservations`，再以过滤后的结果决定 `needsJapaneseOrientationFallback`；270° pass 结果也必须经过同一过滤，避免全高 tile 把横排日语噪声并入最终观察。
- 过滤器必须要求日语脚本密度至少 `0.5`，保留高度至少 `0.022` 且高宽比至少 `1.18` 的高竖框；一／二字紧凑片段只有在高度至少 `0.018`、高宽比至少 `0.90` 时保留。该步只影响 v3.185 日语 tile fallback，不改变 6 tile、18% overlap、4 次方向预算、block/line crop、普通语言、翻译、renderer/export、Store、探针、Koharu active gate、metrics 或 `output`。
- 新增 `scripts/test-v3186-image-japanese-vertical-tile-filter-contract.py`，并让 v3.185 历史合同接受等价 filtered-primary helper；接入显式 UI/full fail-fast。候选 exact-SHA full [31225584307](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31225584307)（`86cf3fd289b4d42c18658d48d5c93308e4f5f91c`）Xcode/static/UI/Speech/home/paste 均成功，JUnit `10/10` 且 0 failures；PR #250 fast [31225981653](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31225981653) 复用候选 full，merge fast [31226027759](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31226027759) 以 `merge_reuses_successful_candidate_full_validation` 复用候选 full（merge SHA `5bb34b44d0c93ab93d816a848266f65c95ad9d6c`），后两者跳过 Xcode，不是新的编译证据。三次均为 `probe_mode=skip`；真实 Koharu readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，`test/jap.jpg` 只作 fixture，无新 metrics/output，不得声称日语 OCR、翻译、识别或 Koharu 质量提升。

### v3.185 日语竖排 tile reconnaissance 合同

- `recognizeJapaneseVerticalCrops` 必须在既有竖排 block 形成后调用 `recognizeJapaneseVerticalTileFallback`，且在后续 block crop 前完成；该 helper 只属于日语分支，用于 Vision 未产出整列 TextBox 时的 bounded detector fallback。
- tile fallback 最多 6 个全高 tile，tile 宽约为图片宽度四分之一、相邻 tile 保留 18% overlap，并强制覆盖右边缘；若既有竖排 block 对 tile 的水平覆盖至少 `0.45` 且垂直覆盖至少 `0.30`，必须跳过该 tile。每个未覆盖 tile 复用 `cropImage`、`prepareJapaneseCropForVision` 与原图坐标映射。
- 每个 tile 先走 90° `recognizeJapaneseCropPass`，弱／空结果按页级最多 4 次再走 270° fallback，`minimumTextHeight=0.003` 且传递 `cropScale`，最后使用 `deduplicateJapaneseObservations`；不得加载 Manga OCR/PaddleOCR 权重、读取探针／ground truth／真实工件或改变普通语言、翻译、renderer/export、Store、Koharu active gate、metrics 与 `output`。
- 新增 `scripts/test-v3185-image-japanese-vertical-tile-fallback-contract.py` 并接入显式 UI/full fail-fast；v3.184 及更早合同继续回归。候选 exact-SHA full [31224644168](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31224644168)（`0c0585a850f4a0a7a4fc4a5735c791439713c4c2`）Xcode/static/UI/Speech/home/paste 均成功，JUnit `10/10` 且 0 failures；PR #249 fast [31225019712](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31225019712) 复用候选 full，merge fast [31225064534](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31225064534) 以 `merge_reuses_successful_candidate_full_validation` 复用候选 full（merge SHA `ccd46c169ae7447d4f0485e4d982277f8ba33e46`），后两者跳过 Xcode，不是新的编译证据。三次均为 `probe_mode=skip`；真实 Koharu readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，`test/jap.jpg` 只作 fixture，无新 metrics/output，不得声称日语 OCR、翻译、识别或 Koharu 质量提升。

### v3.184 日语 line-region 几何去重合同

- 日语 `isDuplicateObservation` 必须只在 `prefersJapanese` 且双方都有 `lineRegionRect` 时使用紧 character-range geometry；缺少任一 hint 时回退 `lhs.rect`／`rhs.rect`，继续使用原 overlap、文本相似度和空文本边界。
- `deduplicateObservations` 与日语竖排 line candidate 去重必须显式传递 `prefersJapanese`；普通语言最终路径继续调用 `Self.deduplicateObservations(observations)`，不改变普通图片非日语 OCR、布局、翻译、renderer/export、Store、探针、Koharu active gate、metrics 或 `output`。
- 新增 `scripts/test-v3184-image-japanese-line-geometry-dedupe-contract.py` 并接入显式 UI/full fail-fast；v3.183 及更早合同继续回归。候选 exact-SHA full [31223348790](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31223348790)（`1bc212b0cf5c8190a9aa9746fb44c0f03ae638dd`）Xcode/static/UI/Speech/home/paste 均成功，JUnit `10/10` 且 0 failures；PR #248 fast [31223808151](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31223808151) 复用候选 full，merge fast [31223883384](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31223883384) 以 `merge_reuses_successful_candidate_full_validation` 复用候选 full（merge SHA `211dab273bf9b0830b411f0586938ba77c93b46d`），后两者跳过 Xcode，不是新的编译证据。三次均为 `probe_mode=skip`；真实 Koharu readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，`test/jap.jpg` 只作 fixture，无新 metrics/output，不得据此声称日语 OCR、翻译、识别或 Koharu 质量提升。

### v3.183 日语 perspective line 目标几何合同

- `perspectiveCorrectedLineImage` 必须按四点 quad 的中点轴长计算 Koharu vertical `textHeight` 与 `ratio`，并将自然透视结果有界重采样到 `(textHeight, textHeight × ratio)`；目标边长不超过 `4096`、面积不超过 `4_000_000`，非法或失败时保留自然 warp 安全回退。
- 该目标画布只作用于普通图片日语 perspective line reread；既有局部 bbox、最多 24 条 line、每页 16M warp 像素预算、灰度／放大、90°／270° fallback、坐标映射与去重保持不变，不加载 Manga OCR/PaddleOCR 权重，不改变普通语言、翻译、renderer/export、Store、探针、Koharu active gate、metrics 或 `output`。`test/jap.jpg` 只作合同 fixture，不生成质量指标。
- 新增 `scripts/test-v3183-image-japanese-line-warp-target-contract.py` 并接入显式 UI/full fail-fast；v3.182 及更早合同继续回归。候选 exact-SHA full [31221970026](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31221970026)（`6c6c040b095aadff18eea5f9f518ce50551fa8f7`）Xcode/static/UI/Speech/home/paste 均成功，JUnit `10/10` 且 0 failures；PR #247 fast [31222386728](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31222386728) 复用候选 full，merge fast [31222451794](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31222451794) 以 `merge_reuses_successful_candidate_full_validation` 复用候选 full（merge SHA `b6410f032d36e5f9205e15327107ca8069589c20`），后两者跳过 Xcode，不是新的编译证据。三次均为 `probe_mode=skip`；真实 Koharu readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，无新 metrics/output，不得声称日语 OCR、翻译、识别或 Koharu 质量提升。

## 0. 默认验证策略
- Agent B 默认本地只跑 `git diff --check`、JSON 解析、YAML smoke 等轻量检查。
- Swift / Xcode / 漫画探针相关任务完成后，默认集中 push 到 `codeb/vX.Y-短标题`，由 GitHub Actions 对核心 commit 执行一次 task-scoped full；需要探针重验证时手动 `workflow_dispatch` 选择 `ci-fast` 或 `full`。
- Agent C 只验收与 `codeb/...` HEAD commit 完全一致的云端结果包，不只看 Agent B 的文字说明。
- 加密打包 workflow 只在软件包交付时手动触发，不随 merge 自动 archive，也不作为 Agent C 验收依据；Agent C 使用独立未加密 CI 结果包。

### v3.182 日语合成 line 替代合同

- `synthesizeJapaneseVerticalLineCandidates` 形成的 bounded line proxy 必须先进入 `axisSeeds`，再从 `uniqueCandidates` 中过滤被其 `lineRegionRect`／`rect` 重叠比 `>= 0.72` 覆盖的原始 axis 候选；原始 `uniqueCandidates.prefix(24)` 仍必须保留给 perspective quad path，不能因为 axis 替代而丢失透视几何。
- 合成仍只允许短日语片段、同列、有限 gap、日语脚本密度和竖排形状门控；最多 24 个 axis line、最多 24 个 perspective line、16M warp 像素预算、方向 fallback、坐标映射与最终去重保持边界。只改普通图片日语 line reread，不改变普通语言、block crop、布局、翻译、renderer/export、Store、探针、Koharu active gate、metrics 或 `output`，不得把路径去重描述为已测得质量提升。
- 新增 `scripts/test-v3182-image-japanese-synthetic-line-replacement-contract.py` 并接入显式 UI/full fail-fast；同步让 v3.172/v3.173 历史合同接受等价 `axisSeeds` helper。候选 exact-SHA full [31220601488](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31220601488)（`42ad3abf8deba67d11b4fd3a93b16a1f09756657`）Xcode/static/UI/Speech/home/paste 均成功，JUnit `10/10` 且 0 failures；PR #246 fast [31221025113](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31221025113) 复用候选 full，merge fast [31221074919](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31221074919) 以 `merge_reuses_successful_candidate_full_validation` 复用候选 full（merge SHA `fb97ce105e5ae2d8fdda3d2acae631c86513be02`），后两者跳过 Xcode，不是新的编译证据。三次均为 `probe_mode=skip`；真实 Koharu readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，无新 metrics/output，不得声称日语 OCR、翻译、识别或 Koharu 质量提升。

### v3.181 日语 line path 去重合同

- `recognizeJapaneseVerticalLineCrops` 必须只在 perspective line 结果成功且 `needsJapaneseOrientationFallback([perspective])` 为假时记录 `perspectiveCoveredCandidates`；轴对齐候选若与已覆盖 line 的 `lineRegionRect`／`rect` 重叠比达到 `0.72` 必须跳过，弱或失败 perspective 必须保留轴对齐与方向 fallback，避免重复 OCR 又不丢失恢复路径。
- 仍最多选择 24 个 line 候选并遵守每页 16M warp 像素预算；只影响普通图片日语 perspective／axis line reread 的候选融合，不改变 block crop、普通语言、整页 OCR、布局、翻译、renderer/export、Store、探针、Koharu active gate、metrics 或 `output`，不得把去重描述为已测得质量提升。
- 新增 `scripts/test-v3181-image-japanese-line-path-dedupe-contract.py` 并接入显式 UI/full fail-fast；v3.180 及更早合同继续回归。候选 exact-SHA full [31218314967](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31218314967)（`e24ce08b798b1f205a4d812e626d27ba801db1de`）Xcode/static/UI/Speech/home/paste 均成功，JUnit `10/10` 且 0 failures；PR #245 fast [31218876431](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31218876431) 复用候选 full，merge fast [31218932836](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31218932836) 以 `merge_reuses_successful_candidate_full_validation` 复用候选 full（merge SHA `1107998858e3879750cba8dc8a27248ad1497589`），后两者跳过 Xcode，不是新的编译证据。三次均为 `probe_mode=skip`；真实 Koharu readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，无新 metrics/output，不得声称日语 OCR、翻译、识别或 Koharu 质量提升。

### v3.180 日语 line warp bbox 合同

- `perspectiveCorrectedLineImage` 必须先用四点 line polygon 的 bbox 与源图边界求交，裁出 `croppedImage`，再将四点平移为 `localPoints` 并交给 `CIPerspectiveCorrection`；不能把整张源图作为小日语 line 的透视输入。
- `recognizeJapaneseVerticalLineCrops` 继续最多选 24 个 perspective 候选，保留 `prepareJapaneseCropForVision`、每页 16M warp 像素预算、90°／270° reread、坐标映射和安全失败回退；仅作用于普通图片日语 perspective line，不改变轴对齐 crop、普通语言、布局、翻译、renderer/export、Store、探针、Koharu active gate、metrics 或 `output`，不得把局部裁剪描述为已测得质量提升。
- 新增 `scripts/test-v3180-image-japanese-line-warp-bbox-contract.py` 并接入显式 UI/full fail-fast；v3.179 及更早合同继续回归。候选 exact-SHA full [31217320435](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31217320435)（`eb522b28c1e9649278342f227aaef03995d67a41`）Xcode/static/UI/Speech/home/paste 均成功，JUnit `10/10` 且 0 failures；PR #244 fast [31217749775](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31217749775) 复用候选 full，merge fast [31217813652](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31217813652) 以 `merge_reuses_successful_candidate_full_validation` 复用候选 full（merge SHA `54b4cf750615efe54962f4247c72003d6d04f761`），后两者跳过 Xcode，不是新的编译证据。三次均为 `probe_mode=skip`；真实 Koharu readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，无新 metrics/output，不得声称日语 OCR、翻译、识别或 Koharu 质量提升。

### v3.179 日语 Koharu 后处理顺序合同

- `postProcessJapaneseOCRText` 必须先移除空白、把 `…` 统一为 `...` 并压缩连续 `.`／`・` 到中间字符串，再遍历该压缩结果执行 ASCII 到全角映射；压缩后的点号不能直接写入最终输出，否则会偏离 Koharu `post_process`。
- 日语整页、90°／270°、block crop、axis line 与 perspective line reread 继续复用同一后处理边界；普通语言仍只取 top-1 且不走该 Japanese helper，不改变 OCR 几何、布局、翻译、renderer/export、Store、探针、Koharu active gate、metrics 或 `output`，不得把格式归一化描述为已测得质量提升。
- 新增 `scripts/test-v3179-image-japanese-koharu-postprocess-order-contract.py` 并接入显式 UI/full fail-fast；v3.178 及更早合同继续回归。候选 exact-SHA full [31216151856](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31216151856)（`c16e5593ef63113e2d3ba5ef1b72d7a09ee2396a`）Xcode/static/UI/Speech/home/paste 均成功，JUnit `10/10` 且 0 failures；PR #243 fast [31216723888](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31216723888) 复用候选 full，merge fast [31216783591](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31216783591) 以 `merge_reuses_successful_candidate_full_validation` 复用候选 full（merge SHA `5f3c0aa1f45d9cee9774db4d0020370666b69273`），后两者跳过 Xcode，不是新的编译证据。三次均为 `probe_mode=skip`；真实 Koharu readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，无新 metrics/output，不得声称日语 OCR、翻译、识别或 Koharu 质量提升。

### v3.178 日语紧凑竖排 block crop 合同

- `recognizeJapaneseVerticalCrops` 必须保留原标准候选门控（`aspectRatio >= 1.45` 且 `height >= 0.04`），并且只对 `directionReason` 含 `cjkCompactColumnTextRun` 的日语竖排块受限放宽到 `aspectRatio >= 1.20`、`height >= 0.022`；最终仍要求 `.vertical`、最多 `.prefix(16)`，不得把一般矮框或其他方向原因带入 crop reread。
- 紧凑与标准候选继续沿用 `expandedVerticalCropRect`、`prepareJapaneseCropForVision`、90°／270° 方向 fallback、原图坐标映射和既有去重；Swift 入口与 Koharu `crop_text_block_bbox` 语义对齐，但不加载真实 Manga OCR/PaddleOCR 权重、不读取探针或 ground truth，不改变普通语言、整页 OCR、翻译、renderer/export、Store、Koharu active gate、metrics 或 `output`，不得把受限候选放宽描述为已测得质量提升。
- 新增 `scripts/test-v3178-image-japanese-compact-block-crop-contract.py` 并接入显式 UI/full fail-fast；v3.177 及更早合同继续回归。候选 exact-SHA full [31214729647](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31214729647)（`ec80c63d1b0d25903f0d462a020dec6bca768f94`）Xcode/static/UI/Speech/home/paste 均成功，JUnit `10/10` 且 0 failures；PR #242 fast [31215410769](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31215410769) 复用候选 full，merge fast [31215485897](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31215485897) 以 `merge_reuses_successful_candidate_full_validation` 复用候选 full（merge SHA `4f6aeca133c9684c6800ec795a9f0fac4f24fdca`），后两者跳过 Xcode，不是新的编译证据。三次均为 `probe_mode=skip`；真实 Koharu readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，无新 metrics/output，不得声称日语 OCR、翻译、识别或 Koharu 质量提升。

### v3.177 日语紧凑竖排方向合同

- `ImageOCRLayoutEngine.layout` 必须把 `prefersMangaReadingOrder` 传入 `resolveDirection`；紧凑门控只在该日语偏好、`cjkCount >= 2`、`verticalRatio >= 1.35`、`height >= 0.022`、存在 `hasColumnNeighbor` 且不存在 `hasRowNeighbor` 时标记 `cjkCompactColumnTextRun`，使小尺寸多字列能进入既有 Koharu 风格 block／line crop reread；宽框横排、单字列、孤立高框、同行碎片、简中和非日语边界保持不变。
- 新增 `scripts/test-v3177-image-japanese-compact-vertical-direction-contract.py` 并接入显式 UI/full fail-fast；v3.176 及更早合同继续回归。该 layout-only 改动不读取探针报告、ground truth 或 `test/koharu_artifacts`，不改变 Vision OCR、翻译、renderer/export、Store、Koharu active gate、metrics 或 `output`，不得把方向门控描述为已测得 OCR 质量提升。
- 候选 exact-SHA full [31213076831](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31213076831)（`9777d167cca71deb753f5d0f721f6c2f9f2af48f`）Xcode/static/UI/Speech/home/paste 均成功，JUnit `10/10` 且 0 failures；PR #241 fast [31213569259](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31213569259) 复用候选 full，merge fast [31213642909](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31213642909) 以 `merge_reuses_successful_candidate_full_validation` 复用候选 full（merge SHA `f2c8a33ba66666a69a941d24fb5d8d78284b1695`），后两者跳过 Xcode，不是新的编译证据。三次均为 `probe_mode=skip`；真实 Koharu readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，无新 metrics/output，不得声称日语 OCR、翻译、识别或 Koharu 质量提升。

### v3.176 日语竖排 perspective line reading order 合同

- `recognizeJapanesePerspectiveLineCrop` 必须把同一四点 warp 后的 Vision observations 交给共享 `orderedJapanesePerspectiveLineObservations`；90° pass 按旋转图 x 轴正序，270° pass 按 x 轴逆序，x 位置接近时才使用 y 与 `isBetterJapaneseObservation` 稳定 tie-breaker，避免一条竖排 line 被拆分后文字顺序反转。
- 单 observation 直接返回；四点 warp、Vision reread、语言后处理、坐标／布局 box、像素预算与失败回退边界保持既有行为。该改动只作用于普通图片日语 perspective line reread，不改变普通语言、整页 OCR、翻译、renderer/export、Store、探针、Koharu active gate、metrics 或 `output`，不得把顺序修正描述为已测得质量提升。
- 新增 `scripts/test-v3176-image-japanese-line-reading-order-contract.py` 并接入显式 UI/full fail-fast；v3.162/v3.175 及更早合同继续回归。候选 exact-SHA full [31211585649](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31211585649)、PR #240 fast [31212154910](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31212154910)、merge fast [31212217877](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31212217877) 均通过；候选 SHA `6a61068f292e4e842b570a455eb357bd5b9a7c40` Xcode/JUnit `10/10`，merge SHA `eaa523f4d29f8be9e7e2f16131bbc21a9363706f` 复用候选 full，三次均为 `probe_mode=skip`、readiness `manifestMissing / stopUntilArtifactsProvided`。

### v3.175 日语竖排字体尺寸 crop padding 合同

- `VisionOCRService` 的日语 block/line crop 必须从源图片像素宽高推导 `fontSizePixels = min(widthPixels, heightPixels)`，按 Koharu 规则计算 `base = max(font × 0.08, 2px)`、竖排 `horizontal = max(font × 0.18, base)`、`vertical = max(font × 0.12, base)`，映射回归一化坐标并保留单轴 `0.08` 上限；block 与 line 入口必须传递同一 `imageSize` 并共享 helper。
- 缺少或非法源尺寸时必须安全回退既有常量；仅作用于普通图片日语 block/line reread，不改变普通语言、整页 OCR、翻译、renderer/export、Store、探针、Koharu active gate、metrics 或 `output`，不得把 padding 变化描述为已测得质量提升。
- 新增 `scripts/test-v3175-image-japanese-font-size-padding-contract.py` 并接入显式 UI/full fail-fast；v3.160/v3.161/v3.162/v3.174 及更早合同继续回归。候选 exact-SHA full [31210073265](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31210073265)、PR #239 fast [31210705708](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31210705708)、merge fast [31210782269](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31210782269) 均通过；候选 SHA `e47014bb6cc68ec70029b3000d0b84c0156fe21e` Xcode/JUnit `10/10`，merge SHA `7b7a57b4d091fc3bd10305a6997e9dd24fba42ba` 复用候选 full，三次均为 `probe_mode=skip`、readiness `manifestMissing / stopUntilArtifactsProvided`。

### v3.174 日语竖排聚类间距合同

- `ImageOCRLayoutEngine.shouldMergeVertically` 必须保留同列／水平重叠门控与原有 `widthLimit`，并以两框平均高度产生有界 `heightLimit`；最终 `verticalGapLimit` 取不超过 `0.08` 的宽度／高度信号，避免高而窄的同列 Vision line box 在日语 line-region reread 前被过早拆开。
- 该修正只作用于竖直 block 聚类，横向合并、普通语言、整页 OCR、翻译、renderer/export、Store、探针、Koharu active gate、metrics 与 `output` 边界保持不变；日语 crop／line 入口仍由既有 `ImageOCRLayoutEngine.layout` 与 `recognizeJapaneseVerticalCrops`／`recognizeJapaneseVerticalLineCrops` 消费，不伪装成已加载 Manga OCR/PaddleOCR 模型，也不声称质量提升。
- 新增 `scripts/test-v3174-image-japanese-vertical-cluster-gap-contract.py` 并接入显式 UI/full fail-fast；v3.173 及更早合同继续回归。候选 exact-SHA full [31208462786](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31208462786)（`49b987b3765e0df0c0511e30f955aa6aa7f487bf`）Xcode/static/UI/Speech/home/paste 均成功，JUnit `10/10` 且 0 failures；PR #238 fast [31209161098](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31209161098) 复用候选 full，merge fast [31209248983](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31209248983) 以 `merge_reuses_successful_candidate_full_validation` 复用候选 full（merge SHA `5efc690d0f8c3b41282518a8bc76d12559efa114`），后两者跳过 Xcode，不是新的编译证据。三次均为 `probe_mode=skip`；真实 Koharu readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，无新 metrics/output，不得声称日语 OCR、翻译、识别或 Koharu 质量提升。

### v3.173 日语 observation 融合合同

- 日语最终布局、竖排 block/line 候选和弱方向 fallback 必须调用 `deduplicateJapaneseObservations`／`isBetterJapaneseObservation`；该 helper 在原 observation score 上只增加有界 `japaneseScriptDensity`／标点 evidence，并对无日语证据候选施加轻微 tie-breaker。普通语言必须保留 `deduplicateObservations(observations)` 原路径。
- 新增 `scripts/test-v3173-image-japanese-observation-fusion-contract.py` 并接入显式 UI/full fail-fast；v3.172 合同改为接受共享日语去重 helper。该改动只作用于普通图片日语 OCR 候选融合，不改变翻译、renderer/export、Store、探针、Koharu active gate、metrics 或 `output`；没有真实竖排质量 corpus，不得声称质量提升。
- 候选 exact-SHA full [31206796785](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31206796785)（`d86f875d1040d69259b62b52754c73be3ccb59dd`）Xcode/static/UI/Speech/home/paste 均成功，JUnit `10/10` 且 0 failures；PR #237 fast [31207387731](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31207387731) 复用候选 full，merge fast [31207465845](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31207465845) 以 `merge_reuses_successful_candidate_full_validation` 复用候选 full（merge SHA `3fe6e719e064fe261f97530a7f16ff3b39ea4903`），后两者跳过 Xcode，不是新的编译证据。三次均为 `probe_mode=skip`；真实 Koharu readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`。

### v3.172 日语竖排碎片 line-region 合同

- `recognizeJapaneseVerticalLineCrops` 必须保留原始最多 24 条 quad 候选给 `recognizeJapanesePerspectiveLineCrop`，并可从同一 vertical block 内满足短日语文本（最多 2 个 scalar、脚本密度至少 `0.5`）、列中心接近、垂直间隙受限的近方形片段合成 line-region；合成 path 只替换被覆盖的轴对齐 reread，最终仍受 `.prefix(24)`、既有预处理、方向 fallback、坐标映射与去重门控。
- 合成 line 需按列中心分组、检查相邻垂直 gap、保持最小高宽比；`lineRegionQuad` 置空，避免伪造透视几何。该迁移只作用于普通图片日语 OCR，不改变整页/非日语、翻译、renderer/export、Store、探针、Koharu active gate、metrics 或 `output`；没有真实竖排质量 corpus，不得声称质量提升。
- 新增 `scripts/test-v3172-image-japanese-vertical-fragment-line-contract.py` 并接入显式 UI/full fail-fast；v3.171 及更早合同继续回归。候选 exact-SHA full [31204989011](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31204989011)（`c2e7edd13818c9c46b65d1aa318e4c91c3479c09`）Xcode/static/UI/Speech/home/paste 均成功，JUnit `10/10` 且 0 failures；PR #236 fast [31205608084](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31205608084) 复用候选 full，merge fast [31205688629](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31205688629) 以 `merge_reuses_successful_candidate_full_validation` 复用候选 full（merge SHA `fab5ddb6d9ebdaa3d4a9dd34bfcdf6c0f676c84c`），后两者跳过 Xcode，不是新的编译证据。三次均为 `probe_mode=skip`；真实 Koharu 四件套 readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`。

### v3.171 日语竖排 line crop 预处理合同

- 日语 `recognizeJapaneseVerticalLineCrops` 的轴对齐 line crop 与 `recognizeJapanesePerspectiveLineCrop` 的透视 line crop 都必须先调用 `prepareJapaneseCropForVision`：安全灰度化，在 `maximumPixels=4_000_000` 内优先 `preferredScale=2`；轴对齐主／反方向 pass 继续传实际 `preparedCrop.scale` 做原图映射，透视 path 按放大后 `preparedPixels` 计入每页 `16_000_000` 上限。
- 预处理或透视校正失败安全回退，不改变普通语言整页 OCR、日语整页方向、翻译、renderer/export、TranslationSessionStore、探针、Koharu active gate、metrics 与 `output`；`test/jap.jpg` 只作合同 fixture，不生成质量指标，也不声称 OCR/Koharu 质量提升。
- 新增 `scripts/test-v3171-image-japanese-line-crop-preprocess-contract.py` 并接入显式 UI/full fail-fast；v3.160/v3.162/v3.169 历史合同接受共享 helper，v3.170 及更早合同继续回归。候选 exact-SHA full [31203452238](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31203452238)（`9968f3083f9b19e9401dd9b48d9e35a480c99e9b`）Xcode/static/UI/Speech/home/paste 均成功，JUnit `10/10` 且 0 failures；PR #235 fast [31204110506](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31204110506) 复用候选 full，merge fast [31204194868](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31204194868) 以 `merge_reuses_successful_candidate_full_validation` 复用候选 full（merge SHA `df0145f9a2cb5dc5ea4ffdd515042f84cb8de108`），后两者跳过 Xcode，不是新的编译证据。三次均为 `probe_mode=skip`；真实 Koharu 四件套 readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`。

### v3.170 日语竖排 crop 预处理合同

- 日语 `recognizeJapaneseVerticalCrops` 的文字块 crop 必须先通过 `prepareJapaneseCropForVision` 灰度化；在 `maximumPixels=4_000_000` 内优先 `preferredScale=2`，放大失败或超出预算时返回原尺寸安全输入，并把实际 `cropScale` 同时传给主方向与 opposite-orientation `recognizeJapaneseCropPass`。
- 该预处理只迁移 Koharu `MangaOcr::preprocess_single_image` 的模型无关边界，不伪造 Manga OCR 权重或 Tensor normalization；普通语言整页路径、日语 line／perspective reread、翻译、renderer/export、TranslationSessionStore、探针、Koharu active gate、metrics 与 `output` 不变。`test/jap.jpg` 只作合同 fixture，不生成质量指标。
- 新增 `scripts/test-v3170-image-japanese-crop-preprocess-contract.py` 并接入显式 UI/full fail-fast；v3.169 及更早合同继续回归。候选 exact-SHA full [31201978062](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31201978062)（`0b2f011398457e410b366d1c10d80a902eecd173`）Xcode/static/UI/Speech/home/paste 均成功，JUnit `10/10` 且 0 failures；PR #234 fast [31202618966](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31202618966) 复用候选 full，merge fast [31202690968](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31202690968) 以 `merge_reuses_successful_candidate_full_validation` 复用候选 full（merge SHA `536b21f83670220ea5364b70badfe375a0df355c`），后两者跳过 Xcode，不是新的编译证据。三次均为 `probe_mode=skip`；真实 Koharu 四件套 readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不得把灰度化／放大描述为日语 OCR、翻译或识别质量提升。

### v3.169 日语竖排 crop 反方向复读合同

- `recognizeJapaneseVerticalCrops` 与 `recognizeJapaneseVerticalLineCrops` 必须先用当前 90°／270° 方向通过共享 `recognizeJapaneseCropPass` 完成 crop、后处理与坐标回映射；结果为空、日语脚本密度低或最佳置信度弱时，才在页级预算内调用 `oppositeJapaneseOrientation`。文字块最多 8 次 fallback，最低文字高度 `0.004`；line 最多 12 次 fallback，最低文字高度 `0.002`，并保留 line crop 的 `cropScale` 映射与既有去重／布局。
- 共享 helper 必须继续使用 `automaticallyDetectsLanguage: false`、当前日语语言列表、`rotationApplied` 与 `postProcessJapaneseText: true`；反方向只服务弱／空 crop，不改变整页 OCR、普通翻译、renderer/export、TranslationSessionStore、探针、Koharu active gate、metrics 或 `output`。`test/jap.jpg` 仍只作合同 fixture，不生成质量指标。
- 新增 `scripts/test-v3169-image-japanese-crop-orientation-fallback-contract.py` 并接入显式 UI/full fail-fast；v3.168 及更早合同继续回归。候选 exact-SHA full [31200276655](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31200276655)（`bbe47bd89e4413580482b07e52799867c844ec64`）Xcode/static/UI/Speech/home/paste 均成功，JUnit `10/10` 且 0 failures；PR #233 fast [31200973375](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31200973375) 复用候选 full，merge fast [31201060977](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31201060977) 以 `merge_reuses_successful_candidate_full_validation` 复用候选 full（merge SHA `a2ad829bf519a2f5cec02d82cc6d7b40168c2d62`），后两者跳过 Xcode，不是新的编译证据。三次均为 `probe_mode=skip`；真实 Koharu 四件套 readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不得把方向 fallback 描述为日语 OCR、翻译或识别质量提升。

### v3.168 日语 OCR Koharu 后处理与候选融合合同

- 日语 `VisionOCRService` 必须在既有旋转、文字块 crop、line 与 perspective reread 结果上使用 `postProcessJapaneseOCRText`：去除空白、将 `…` 变为 `...`、把连续 `.`／`・` 折叠为同长度点号，并将 ASCII 可打印字符映射为全角；非日语继续走原有 trim/top-1 路径。
- 日语候选从 `topCandidates(5)` 取值，只保留不低于最佳置信度 `0.14` 窗口的候选，再以置信度、日语脚本密度和标点密度做保守选择；该层不加载 Manga OCR/PaddleOCR 模型、不改变 TranslationSessionStore、翻译、renderer/export、探针、metrics 或 `output`，`test/jap.jpg` 只作合同 fixture。
- 新增 `scripts/test-v3168-image-japanese-ocr-postprocess-contract.py` 并接入显式 UI/full 路由；v3.167 及更早合同继续回归。候选 exact-SHA full [31197172635](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31197172635)（`9438e3d40ffb133073921fc4f4a0e1de36cc042d`）Xcode/static/UI/Speech/home/paste 均成功，JUnit `10/10` 且 0 failures；PR #232 fast [31197811891](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31197811891) 复用候选 full，merge fast [31197884476](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31197884476) 以 `merge_reuses_successful_candidate_full_validation` 复用候选 full（merge SHA `033d66b5c62434e5685b1e8d7d1feebdfa90c15e`），后两者跳过 Xcode，不是新的编译证据。三次均为 `probe_mode=skip`；真实 Koharu 四件套 readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，无新 metrics/output，不得把后处理或候选融合描述为日语 OCR、翻译或识别质量提升。

### v3.167 日语／横排 OCR 横向行动态容差合同

- `ImageOCRLayoutEngine.orderedHorizontalBands` 必须从当前 observations 的 `rect.height` 中位数计算 `rowTolerance = min(max(median * 0.55, 0.012), 0.04)`，再用于 y 轴行分组；不得回到固定 `0.02`，也不得改变既有 RTL/LTR 横排排序、竖排布局、OCR、翻译或导出路径。
- 该改动只属于 layout-only；不读取探针报告、ground truth 或 `test/koharu_artifacts`，不新增 Store、持久化、OCR 模型、翻译、renderer/export、metrics 或 `output` 行为。`test/jap.jpg` 仍只作合同 fixture，不生成质量指标。
- 新增 `scripts/test-v3167-image-horizontal-band-dynamic-tolerance-contract.py` 并接入显式 UI/full CI 路由；v3.166 及更早合同继续回归。候选 exact-SHA full [31195627325](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31195627325)（`6c63dd0a5170a0fb230046d7d2129b26fd8dbb4d`）Xcode/static/UI/Speech/home/paste 均成功，JUnit `10/10` 且 0 failures；PR #231 fast [31196179149](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31196179149) 复用候选 full，merge fast [31196269343](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31196269343) 以 `merge_reuses_successful_candidate_full_validation` 复用候选 full（merge SHA `a0f1e72ea36be0932dae75fe774af1186ed29b1c`），后两者跳过 Xcode，不是新的编译证据。三次均为 `probe_mode=skip`；真实 Koharu 四件套 readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，无新 metrics/output，不得把动态行容差描述为日语 OCR、翻译或识别质量提升。

### v3.166 日语竖排 CJK 标点方向合同

- `cjkCharacterCount` 必须同时覆盖 `U+3000–U+303F` CJK 标点和 `U+FF61–U+FF9F` 半角片假名；短 observation 仍必须通过 `verticalRatio >= 1.05`、`height >= 0.015`、列邻居存在且横排行邻居不存在的门控，不能仅凭标点字符改变方向。
- 该改动只增强已有竖排方向证据，让「、。」等单独 Vision observation 能进入既有竖排 block／crop reread；不新增 OCR 模型，不读取探针报告、ground truth 或 `test/koharu_artifacts`，不改变翻译、renderer/export、Store、metrics 或 `output`。
- 新增 `scripts/test-v3166-image-japanese-punctuation-column-contract.py` 并接入 UI/full fail-fast；v3.165 及更早合同继续回归。候选 exact-SHA full [31193812409](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31193812409)（`8c6dfe278a9644dd0dc37ffa5381a968dc7748c7`）Xcode/static/UI/Speech/home/paste 均成功，JUnit `10/10` 且 0 failures；PR #230 fast [31194473761](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31194473761) 复用候选 full，merge fast [31194535297](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31194535297) 以 `merge_reuses_successful_candidate_full_validation` 复用候选 full（merge SHA `0acfd7f62c9ecbe048c7630d0358c85dce325edb`），后两者跳过 Xcode/UI/Speech，不是新的编译证据。三次均为 `probe_mode=skip`；真实 Koharu 四件套 readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，无新 metrics/output，不得把标点方向证据描述为日语 OCR、翻译或识别质量提升。

### v3.165 日语单字列竖排方向合同

- `resolveDirection` 保留原有宽框横排与高框竖排门控；额外的短 CJK observation 只有在 `verticalRatio >= 1.05`、`height >= 0.015`、存在 `isColumnNeighbor` 且不存在 `isCloseRowNeighbor` 时标为 `cjkGlyphColumnNeighbors`，避免把横排行碎片或孤立图形送入竖排 crop。
- 该门控只消费 Vision observation 的文字与几何，直接让既有竖排 block 聚类、Koharu 风格局部 crop／line reread 看到单字列；不新增 OCR 模型，不读取探针报告、ground truth 或 `test/koharu_artifacts`，不改变翻译、renderer/export、Store、metrics 或 `output`。
- 新增 `scripts/test-v3165-image-japanese-glyph-column-contract.py` 并接入 UI/full fail-fast；v3.164 及更早合同继续回归。候选 exact-SHA full [31192480905](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31192480905)（`5f24c4b7d2de47a095ee15b19994087ebde4dff7`）Xcode/static/UI/Speech/home/paste 均成功，JUnit `10/10` 且 0 failures；PR #229 fast [31193220150](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31193220150) 复用候选 full，merge fast [31193292477](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31193292477) 以 `merge_reuses_successful_candidate_full_validation` 复用候选 full（merge SHA `631c4d25acacb6b0497e8c95dab41f9a22e6c266`），后两者跳过 Xcode/UI/Speech，不是新的编译证据。三次均为 `probe_mode=skip`；真实 Koharu 四件套 readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，无新 metrics/output，不得把该方向门控描述为日语 OCR、翻译或识别质量提升。

### v3.164 日语混合版面横排 RTL reading-order 合同

- `ImageOCRLayoutEngine.layout` 的 `prefersMangaReadingOrder` 必须默认 false；只有日语 Vision 主 OCR 与日语 crop layout 显式传 true，非日语调用保持原有左到右横排行为。
- 横排 helper 在 true 时保留 y 行分组和上到下行序，只把同一行的 x 主键变为负值以右到左排序；不读取探针报告、ground truth 或 `test/koharu_artifacts`，不改变翻译、renderer/export、Store、metrics 或 `output`。
- 新增 `scripts/test-v3164-image-japanese-horizontal-reading-order-contract.py`，并接入 UI/full fail-fast；v3.163 及更早合同继续回归。候选 exact-SHA full [31190984866](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31190984866)（`7e584045f12fefa995866b7479db4cd440d52a03`）Xcode/static/UI/Speech/home/paste 均成功，JUnit `10/10` 且 0 failures；PR #228 fast [31191645282](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31191645282) 复用候选 full，merge fast [31191716497](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31191716497) 以 `merge_reuses_successful_candidate_full_validation` 复用候选 full（merge SHA `3943843d61f331630f7c6764f5639273aea4bd90`），后两者跳过 Xcode/UI/Speech，不是新的编译证据。三次均为 `probe_mode=skip`；真实 Koharu 四件套 readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，无新 metrics/output，不得把横排 RTL 迁移描述为日语 OCR、翻译或识别质量提升。

### v3.163 日语竖排 Recursive XY-Cut reading-order 合同

- `ImageOCRLayoutEngine` 的日语竖排路径必须按文字块中位宽／高中位数计算动态空白阈值，并递归选择横向／纵向最大间隙；横向切分右侧组先读，纵向切分顶部组先读，无法切分时使用稳定右到左／上到下回退。
- 该迁移只改 reading order，不读取探针报告、ground truth 或 `test/koharu_artifacts`，不改变 Vision OCR、翻译、renderer/export、Store、metrics 或 `output`；新增 `scripts/test-v3163-image-japanese-reading-order-contract.py`，v3.162 及更早合同继续回归。
- 候选 exact-SHA full [31189049773](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31189049773)（`c37808634df8d87cfb9f24c22acadc472f71d3c0`）Xcode/static/UI/Speech/home/paste 均成功，JUnit `10/10` 且 0 failures；PR #227 fast [31189799793](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31189799793) 复用候选 full，merge fast [31189875449](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31189875449) 以 `merge_reuses_successful_candidate_full_validation` 复用候选 full（merge SHA `e93f3844c359214c0cdfe09cd609fb11c51b924d`），后两者跳过 Xcode/UI/Speech，不是新的编译证据。三次均为 `probe_mode=skip`；真实 Koharu 四件套 readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，无新 metrics/output，不得把 Recursive XY-Cut 迁移描述为日语 OCR、翻译或识别质量提升。

### v3.162 日语竖排 line-region perspective OCR 合同

- `VisionOCRService` 必须从 `VNRecognizedText.boundingBox(for:)` 保留字符范围的四角 geometry，同时维持 request-level observation box 作为布局／去重几何；只有有效、凸且有限的四点 geometry 才能进入 line crop hint。
- 日语竖排 line crop 最多处理 24 条；可选的 Core Image `CIPerspectiveCorrection` 每条输出不超过 4M、总计不超过 16M 像素，随后做 2× Vision 复读；透视过滤器、resize、rotate 或局部 OCR 失败时必须回到既有轴对齐 crop，不得使整张图片 OCR 失败。
- 四角 geometry 必须在整页 90°／270° 与局部 crop 的回映射中同步传播，但不能替换稳定布局 box；不得读取漫画探针 report、ground truth、`test/koharu_artifacts`、FileManager 或 TranslationSessionStore，也不得描述为真实 Manga OCR/PaddleOCR 模型或质量提升。
- 新增 `scripts/test-v3162-image-japanese-line-perspective-ocr-contract.py`，并接入 UI/full fail-fast；v3.161 及更早合同继续回归。候选 exact-SHA full [31186264941](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31186264941)（`8a8e653f953c233f5b0d28249bb9b324ef0baab3`）Xcode/static/UI/Speech/home/paste 均成功，JUnit `10/10` 且 0 failures；PR #226 fast [31186901253](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31186901253) 复用候选 full，merge fast [31186979637](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31186979637) 以 `merge_reuses_successful_candidate_full_validation` 复用候选 full（merge SHA `b1c272b9fea90e07967e21db082538be50c8b516`），后两者跳过 Xcode/UI/Speech，不是新的编译证据。三次均为 `probe_mode=skip`；真实 Koharu 四件套 readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，无新 metrics/output，不得把透视 geometry 迁移描述为日语 OCR、翻译或 Koharu 质量提升。

### v3.161 日语竖排 line-region geometry 合同

- `VisionOCRService` 必须读取 `VNRecognizedText.boundingBox(for:)` 的整段字符范围作为可选 line-region crop hint；request-level observation box 仍保留给布局与去重，避免更紧的 crop 几何改变最终 block identity。
- 字符范围 geometry 必须经过有效重叠／面积比例门控，并在整页 90°／270° 与局部 2× crop 的坐标回映射中同步传播；Vision 未提供范围 bounds 或调用失败时回退 request-level box，不得让整张图片 OCR 失败。
- 新增 `scripts/test-v3161-image-japanese-line-geometry-contract.py` 并接入 UI/full fail-fast；v3.160 及更早合同继续回归。候选 exact-SHA full [31184241208](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31184241208)（`9164066706faed78494384d79ec1544d46084c20`）Xcode/static/UI/Speech/home/paste 均成功，JUnit `10/10` 且 0 failures；PR #225 fast [31184939184](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31184939184) 复用候选 full，merge fast [31185021159](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31185021159) 以 `merge_reuses_successful_candidate_full_validation` 复用候选 full（merge SHA `1eb026c2ce3df861b6efcc7ae9d61a5d08fd86ea`），后两者跳过 Xcode/UI/Speech，不是新的编译证据。三次均为 `probe_mode=skip`；真实 Koharu 四件套 readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，无新 metrics/output，不得把 Vision geometry hint 描述为已加载 Manga OCR/PaddleOCR 模型或质量提升。

### v3.160 日语竖排 line-region OCR 合同

- 普通图片源语言为日语时，`VisionOCRService` 在既有竖排 block 上筛选最多 24 个与 block 重叠且纵向比例足够的 line-region proxy；按 Koharu 风格做方向感知扩边、2× crop 复读，使用 `minimumTextHeight=0.002` 与关闭自动语言，并按 crop 缩放比例把结果框映射回原图后去重。
- 当前 Vision observations 不提供 Koharu 的真实 `line_polygons`，因此该 helper 只能是保守 proxy；crop／resize／rotate／局部 OCR 任一失败安全跳过，不能把该过渡层描述为 Manga OCR/PaddleOCR 模型或质量提升，也不得读取 `groundTruth`、`test/koharu_artifacts`、FileManager、TranslationSessionStore 或漫画探针 report-only 状态。
- 新增 `scripts/test-v3160-image-japanese-line-region-ocr-contract.py` 并接入 UI/full fail-fast；v3.159 及更早合同继续回归。候选 exact-SHA full [31182335743](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31182335743)（`68c1c1b8eb1390b808204c3c16b7b1dbc72a28b9`）Xcode/static/UI/Speech/home/paste 均成功，JUnit `10/10` 且 0 failures；PR #224 fast [31183007517](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31183007517) 复用候选 full，merge fast [31183084173](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31183084173) 以 `merge_reuses_successful_candidate_full_validation` 复用候选 full（merge SHA `19b018101a4937474e2f3b030a1e24dc58807704`），后两者跳过 Xcode/UI/Speech，不是新的编译证据。三次均为 `probe_mode=skip`；真实 Koharu 四件套 readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，无新 metrics/output，不得声称日语 OCR、翻译、识别或 Koharu 质量提升。

### v3.159 日语图片 OCR 进度上下文合同

- `TranslationSessionStore` 的图片 OCR 阶段必须通过 View／Store 私有 helper 按源语言分流：日语显示“正在用 Vision 本机 OCR 识别日语文字，复查竖排方向与文字块位置”，其他语言保留“正在用 Vision 本机 OCR 识别文字和位置”。
- helper 只能产生既有 `imageTranslationMessage` 文案，并由 `.recognizing` 阶段继续写入同一状态；图片状态行和结果空态继续消费 Store message，不得新增 OCR、翻译、持久化或第二条管线。
- 新增 `scripts/test-v3159-image-japanese-ocr-status-context-contract.py` 并接入 UI/full fail-fast；合同同时检查 v3.158 路由顺序、版本号和无效的 helper 依赖。
- 候选 exact-SHA full [31180141884](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31180141884)（`f30fbab503ff9c694af0d4f2c123113b1802648d`）Xcode/static/UI/Speech/home/paste 均成功，JUnit `10/10` 且 0 failures；PR #223 fast [31180615748](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31180615748) 复用候选 full，merge fast [31180708039](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31180708039) 复用候选 full（merge SHA `9c68b5c9f7e5e5d341a3cfaec1f764964b71b9f0`），后两者跳过 Xcode/UI/Speech，不是新的编译证据。三次均为 `probe_mode=skip`；真实 Koharu 四件套 readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，无新 metrics/output，不得声称日语 OCR、翻译、识别或 Koharu 质量提升。

### v3.158 日语竖排裁剪复读 OCR 合同

- 普通图片源语言为日语时，`VisionOCRService` 必须在保留整页 Vision OCR 与 90°／270° 方向复查后，从既有 `ImageOCRLayoutEngine` 竖排 block 中最多选择 16 个候选文字块；每个候选按 Koharu 的文字块裁剪边界扩展后再执行一次 Vision OCR。
- 裁剪复读必须使用候选关联的 90°／270° 方向、`ja-JP`／`ja`／`en-US`／`en` profile、较低 `minimumTextHeight` 且关闭自动语言检测；裁剪框结果必须映射回原图，并与既有观察一起去重后才可进入最终布局。
- 裁剪失败、旋转失败或局部 OCR 失败不得让整张图片 OCR 失败；该步只迁移 Koharu 的 crop-before-OCR 边界，不得伪装成已加载 Manga OCR/PaddleOCR 模型，也不得读取 `groundTruth`、`test/koharu_artifacts`、FileManager、TranslationSessionStore 或漫画探针 report-only 状态。
- 新增 `scripts/test-v3158-image-japanese-crop-ocr-contract.py` 并接入 UI/full fail-fast。候选 exact-SHA full [31178774530](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31178774530)（`ee21c07d5175b38b41161822043b7ce1bbeea3ff`）Xcode/static/UI/Speech/home/paste 均成功，JUnit `10/10` 且 0 failures；PR #222 fast [31179342519](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31179342519) 复用候选 full，merge fast [31179390133](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31179390133) 复用候选 full（merge SHA `c940815a43e300685667d8b01888e53af910ec9c`），后两者跳过 Xcode，不是新的编译证据。三次均为 `probe_mode=skip`；真实 Koharu 四件套 readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，无新 metrics/output，不得声称日语 OCR、翻译、识别或 Koharu 质量提升。

### v3.157 日语竖排双向方向 OCR 合同

- 普通图片源语言为日语时，`VisionOCRService` 必须保留原图 Vision OCR，并在同一受限路径比较恰好 90° 与 270° 两个方向；两次复查使用 `ja-JP`／`ja`／`en-US`／`en` profile、较低 `minimumTextHeight` 且关闭自动语言检测，结果框映射回原图后统一去重。
- 双向复查结果必须继续进入既有 `ImageOCRLayoutEngine`，由现有日语／简体中文竖排证据、列邻居和右到左阅读顺序决定最终 block；不得读取 `groundTruth`、`test/koharu_artifacts`、FileManager 或 TranslationSessionStore，也不得把漫画探针 report-only 路径变成普通图片 OCR 依赖。
- 新增 `scripts/test-v3157-image-japanese-bidirectional-orientation-ocr-contract.py` 并接入 UI/full fail-fast；该步仍只是 Koharu 方向比较边界迁移，不是 Manga OCR/PaddleOCR 模型替换，`test/jap.jpg` 只作真实 JPEG fixture，不生成质量指标。
- 候选 exact-SHA full [31177442783](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31177442783)（`894c7063e18a6dc40ea047dca015e7cf73af8e65`）Xcode/static/UI/Speech/home/paste 均成功，JUnit `10/10` 且 0 failures；PR #221 fast [31177914749](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31177914749) 复用候选 full，merge fast [31177971252](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31177971252) 复用候选 full（merge SHA `1266de53935525c1014ec0b4cbecb9b7f20b6e86`），后两者跳过 Xcode，不是新的编译证据。三次均为 `probe_mode=skip`；真实 Koharu 四件套 readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，无新 metrics/output，不得声称日语 OCR、翻译、识别或 Koharu 质量提升。

### v3.156 日语竖排方向 OCR 合同

- 普通图片源语言为日语时，`VisionOCRService` 必须保留原图 Vision OCR，并追加受限的 90° 方向复查；复查使用 `ja-JP`／`ja`／`en-US`／`en` profile、较低 `minimumTextHeight` 且关闭自动语言检测，结果框映射回原图后再去重与布局。
- 旋转结果必须继续进入既有 `ImageOCRLayoutEngine`，由现有日语／简体中文竖排证据、列邻居和右到左阅读顺序决定最终 block；不得读取 `groundTruth`、`test/koharu_artifacts`、FileManager 或 TranslationSessionStore，也不得把漫画探针 report-only 路径变成普通图片 OCR 依赖。
- 该步只迁移 Koharu 的方向比较与分层边界；仓库没有可供 iOS 主路径直接加载的 Manga OCR/PaddleOCR 模型工件，不得把方向复查描述成模型替换或质量提升。`test/jap.jpg` 是真实日语竖排参考 fixture，合同只验证其存在与 JPEG 边界，不生成质量指标。
- 新增 `scripts/test-v3156-image-japanese-orientation-ocr-contract.py` 并接入 UI/full fail-fast。候选 exact-SHA full [31176163879](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31176163879)（`99a333a8297faf193c8058d7f919626bb17daf80`）Xcode/static/UI/Speech/home/paste 均成功，JUnit `10/10` 且 0 failures；PR #220 fast [31176662793](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31176662793) 复用候选 full，merge fast [31176739499](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31176739499) 复用候选 full（merge SHA `7750c7e62b82cb952ab302b9afd206ecf15068dd`），后两者跳过 Xcode，不是新的编译证据。三次均为 `probe_mode=skip`；真实 Koharu 四件套 readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，无新 metrics/output，不得声称日语 OCR、翻译、识别或 Koharu 质量提升。

### v3.155 普通图片空结果就地重试 action 合同

- 普通图片 `imageTranslationBlocks` 为空、保留当前图片且 Store 允许当前图片重试时，结果空态必须提供可见“重试当前图片”按钮；仅在 `canRetryFromImageStatus` 为真时显示，该 View helper 必须同时要求 `store.canRetryImageTranslation` 且 `store.imageTranslationRetryLanguageSummary == nil`，避免与“重试语言已更新”状态行重复入口。
- 可见按钮与空态 VoiceOver 必须暴露同名“重试当前图片” action，直接复用 `store.retryImageTranslation`，hint 明确使用当前图片语言重新识别并翻译；源图片不可用、处理进行中或待重试语言已变更时不得暴露这条局部 action，保留既有状态行或选择新图片的恢复边界。
- 新增 `scripts/test-v3155-image-empty-result-retry-action-contract.py` 并接入 UI/full fail-fast；helper 只能消费既有 View／Store gate，不得新增 Store、持久化、Vision OCR、翻译、renderer/export、探针或 metrics/output 行为。
- 候选 exact-SHA full [31173412868](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31173412868)（`a6283b1be84ec4e6b227b6d5fbf74961a4fd108f`）Xcode/static/UI/Speech/home/paste 均成功，JUnit `10/10` 且 0 failures；PR #219 fast [31173840102](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31173840102) 复用候选 full，merge fast [31173897707](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31173897707) 复用候选 full（merge SHA `2c26886ee6676c549b88ad48b0447e595c636a40`），后两者跳过 Xcode，不是新的编译证据。三次均为 `probe_mode=skip`；真实 Koharu 四件套 readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，无新 metrics/output，不得声称 OCR、翻译、识别或 Koharu 质量提升。

### v3.154 普通图片空结果状态文案合同

- 普通图片 `imageTranslationBlocks` 为空且保留当前结果空态时，`AppEmptyState` 的可见标题与说明必须通过 View 私有 `imageResultEmptyStateTitle`／`imageResultEmptyStateDetail` 按 `.idle`、读取／OCR／翻译进行中、`.translated`、`.failed` 分流；translated 必须说明没有可显示 OCR 文字块及当前是否可重新识别，处理中保留 Store 的阶段消息，失败保留失败原因。
- 现有 VoiceOver label/value/hint、稳定 `imageResultEmptyAccessibilityFocusID`、受 `store.canRerunImageRecognition` 门控的“重新识别” action 与可见按钮必须保持；不得在状态文案 helper 中新增 Store、OCR、翻译、持久化或重跑管线。
- 新增 `scripts/test-v3154-image-empty-result-state-contract.py` 并接入 UI/full fail-fast；同步 v3.133/v3.152/v3.153 历史合同接受动态标题／说明。
- 候选 exact-SHA full [31171837188](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31171837188)（`11028f3de4886aad18e911dd8dc3f60e6593ba9f`）Xcode/static/UI/Speech/home/paste 均成功，JUnit `10/10` 且 0 failures；PR #218 fast [31172320096](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31172320096) 复用候选 full，merge fast [31172393014](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31172393014) 复用候选 full（merge SHA `b51ab8a880f3a1998a5a4e249e6c7113e0a3c451`），后两者跳过 Xcode，不是新的编译证据。三次均为 `probe_mode=skip`；真实 Koharu 四件套 readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，无新 metrics/output，不得声称 OCR、翻译、识别或 Koharu 质量提升。

### v3.153 普通图片空结果 VoiceOver 焦点合同

- 普通图片翻译已完成、保留源图片且没有可显示 OCR 文字块时，结果空态必须使用稳定的 `imageResultEmptyAccessibilityFocusID`；`focusImageTranslationTerminalStateIfNeeded()` 的优先级保持“全部忽略空态 → 翻译完成空态 → 图片状态行”，避免终态焦点落回不可操作或失效的上下文。
- 现有 v3.144 的“重新识别” action 与 v3.152 可见按钮门控保持不变；只增加 View 私有焦点 identity，不新增 Store／OCR／翻译／持久化管线。焦点仍受 `imageTranslationRevision` 与 request generation guard 约束，旧图片任务不得抢回焦点。
- 新增 `scripts/test-v3153-image-empty-result-focus-contract.py` 并接入 UI/full fail-fast；候选 exact-SHA full [31170387940](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31170387940)（`6c838ef220470753cb6abf4867babc48a6ea795c`）Xcode/static/UI/Speech/home/paste 均成功，JUnit `10/10` 且 0 failures；PR #217 fast [31170963538](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31170963538) 复用候选 full，merge fast [31171022668](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31171022668) 复用候选 full（merge SHA `a938b8b73803e0570e0ec9bb8e6ec354e3cf85b0`），后两者跳过 Xcode，不是新的编译证据。三次均为 `probe_mode=skip`；真实 Koharu 四件套 readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，无新 metrics/output，不得声称 OCR、翻译、识别或 Koharu 质量提升。

### v3.152 普通图片空结果可见重新识别合同

- 普通图片翻译已完成但 `imageTranslationBlocks` 为空且仍保留源图片时，结果空态必须提供可见“重新识别”按钮；按钮仅在既有 `store.canRerunImageRecognition` 为真时显示，复用 `store.rerunImageRecognition`，不得新增 OCR、翻译、Store 或持久化管线。
- VoiceOver 继续由 v3.144 helper 提供同名“重新识别” action；可见按钮 hint 必须明确使用当前图片语言重新运行 Vision OCR 并重新翻译识别到的文字，源图片不可重跑时不显示按钮或 action。
- 新增 `scripts/test-v3152-image-empty-result-rerun-button-contract.py` 并接入 UI/full fail-fast；历史 v3.144/v3.313 空结果上下文合同继续通过。
- 候选 exact-SHA full [31167004721](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31167004721)（`0c08bfda4548b996a2e3bad86d2adde950276378`）Xcode/static/UI/Speech/home/paste 均成功，JUnit `10/10` 且 0 failures；PR #216 fast [31170006883](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31170006883) 复用候选 full，merge fast [31170055419](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31170055419) 复用候选 full，后两者跳过 Xcode，不是新的编译证据。三次均为 `probe_mode=skip`；真实 Koharu 四件套 readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，无新 metrics/output，不得声称 OCR、翻译、识别或 Koharu 质量提升。

### v3.151 漫画探针无逐块结果就地重试合同

- Developer Console 的漫画探针报告存在但没有逐块文字块时，空态必须同时提供可见“重新运行漫画覆盖翻译探针”按钮和同名 VoiceOver action；两者复用既有 `store.runMangaOverlayProbe`，不创建第二条探针、OCR、翻译或 Store 管线。
- `canRetryEmptyMangaProbe` 只在 `!store.isRunningMangaOverlayProbe` 时为真；探针运行中按钮保持 `.disabled(true)`，不向 VoiceOver 暴露只会被 Store guard 拒绝的 action。hint 必须说明会重新读取 `test/1.png`、清理 Output、只更新漫画探针诊断，不改变普通图片 OCR、翻译或覆盖图。
- 新增 `scripts/test-v3151-manga-probe-empty-retry-action-contract.py` 并接入 UI/full fail-fast；v3.56 历史状态合同接受这条受门控的第二入口，同时继续锁定 report-only 和单一 Store 入口边界。
- 候选 exact-SHA full [31165387991](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31165387991)（`8579bdabc8f0dbbeafe19b4804cfedcea9dfbe04`）Xcode/static/UI/Speech/home/paste 均成功，JUnit `10/10` 且 0 failures；PR #215 fast [31165964091](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31165964091) 复用候选 full，merge fast [31166051842](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31166051842) 复用候选 full，后两者跳过 Xcode，不是新的编译证据。三次均为 `probe_mode=skip`；真实 Koharu 四件套 readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，无新 metrics/output，不得声称 OCR、翻译、识别或 Koharu 质量提升。

### v3.150 普通图片局部放大恢复 Vision OCR action 合同

- 人工修正后的图片文字块在局部放大预览中提供可见“恢复 Vision OCR”按钮与同名 VoiceOver action；只有 `isManuallyCorrected && canEdit` 时暴露，锁定时保留 `modificationUnavailableHint` 和禁用按钮，不虚构恢复入口。
- 局部预览通过面板现有 `requestVisionOCRRestore` 确认入口恢复原始 OCR 原文与初始译文；不在 focus View 中新增 Store、Vision OCR 或翻译管线，恢复后的既有焦点交接保持不变。
- 新增 `scripts/test-v3150-image-focus-restore-action-contract.py`，并同步 UI/full fail-fast 路由。候选 exact-SHA full `31163470178`（`04cef3c01b802627366587dc1a3c76eddc534e3f`）Xcode/JUnit `10/10` 成功；PR #214 fast `31164127307`、merge fast `31164207376` 复用候选 full，Xcode/UI/Speech skipped，JUnit `10/10`。探针默认 `probe_mode=skip`，readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不得据此声称 OCR、翻译、识别或 Koharu 质量提升。


### v3.149 普通图片复查完成空态 action 门控合同

- 普通图片筛选到 `.needsReview` 且所有风险块已完成时，完成空态只在 `canReviewImageTranslation` 为真时提供 VoiceOver“重新复查” action，并复用既有 `restartReviewQueue()`；翻译未完成或导出重绘期间不得暴露一个只会被 guard 拒绝的无效 action。
- 锁定状态继续保留“本次复查完成”的稳定 label/value、`imageReviewUnavailableDetail` hint、可见“重新复查”按钮及 `.disabled(!canReviewImageTranslation)`；焦点仍回到 View 私有完成空态 identity。
- 新增 `scripts/test-v3149-image-review-completion-action-gate-contract.py`，并让 v3.128/v3.129/v3.148 历史合同接受同一 View-only helper 形式。候选 exact-SHA full `31161816278`（`b0fc332c565fe501c8e2e939a086b79c142c9853`）Xcode/JUnit `10/10` 成功；PR #213 fast `31162344568`、merge fast `31162426726` 复用候选 full，Xcode/UI/Speech skipped，JUnit `10/10`。探针默认 `probe_mode=skip`，readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不得据此声称 OCR、翻译、识别或 Koharu 质量提升。


### v3.148 普通图片全部忽略空态 action 门控合同

- 全部 OCR 文字块被忽略时，空态父级仅在 `canModifyImageTranslation` 为真时提供 VoiceOver“恢复全部” action；翻译未完成或导出重绘期间不得暴露一个只会被 guard 拒绝的无效 action。
- 锁定状态继续保留“当前没有保留文字块”的 label/value、`imageModificationUnavailableDetail` hint、可见批量恢复按钮及 `.disabled(!canModifyImageTranslation)`；恢复仍经既有确认对话框和 View 回调进入 Store。
- 新增 `scripts/test-v3148-image-ignored-empty-state-action-gate-contract.py`，并同步 v3.132 历史合同与 UI/full fail-fast 路由。候选 exact-SHA full `31160052402`（`01231917a86696cfc3a864d9a6382119b8c13455`）Xcode/JUnit `10/10` 成功；PR #212 fast `31160532637`、merge fast `31160619661` 复用候选 full，Xcode/UI/Speech skipped，JUnit `10/10`。探针默认 `probe_mode=skip`，readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不得据此声称 OCR、翻译、识别或 Koharu 质量提升。


### v3.147 普通图片 OCR 修正输入无障碍上下文合同

- `ImageOCRCorrectionSheet` 的“修正后的文字”输入必须提供明确 label、当前 value 和基于空文本／实际修改／确认无误／保存中的动态 hint；保存／重译进行中，输入与“忽略此文字块”均不可用，忽略 hint 继续说明当前图片会话范围和图片检查区恢复路径。
- helper 只能消费既有 View 状态，不得新增 Store／持久化／OCR／翻译／renderer/export／探针或 metrics/output 行为；既有规范化保存、当前文字块单独重译、取消保护与忽略确认必须保持。
- 新增 `scripts/test-v3147-image-ocr-correction-input-accessibility-contract.py` 并接入 UI/full fail-fast。候选 exact-SHA full `31158590713`（`3a60ad6b431acfc11f2296ec59ec86609d107546`）Xcode/JUnit `10/10` 成功；PR #211 fast `31159215608`、merge fast `31159309690` 复用候选 full，Xcode/UI/Speech skipped，JUnit `10/10`。探针默认 `probe_mode=skip`，readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不得据此声称 OCR、翻译、识别或 Koharu 质量提升。

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
- v3.37 正式要求 `ImageOCRCorrectionSheet` 用唯一的 `normalizedCorrectedOriginal`（`trimmingCharacters(in: .whitespacesAndNewlines)`）同时决定 `canSave`、`hasUnsavedChanges`、`requiresRetranslation` 和既有 Store correction 参数，以和 `TranslationSessionStore.correctImageTranslationBlock` 的 trim-before-no-op 行为相同。`trim` 后仍等于当前原文的编辑必须保持 clean：取消／下滑关闭不触发 v3.24 的放弃确认，确认无误不调用模型；真正改变文字时，v3.24 弃改保护、v3.25 文案与无重译分流、v3.30–v3.35 关闭后焦点交接仍保留。该状态只在 View 内，不新增 Store／持久化／OCR／翻译／renderer/export／漫画探针／Koharu／metrics／output 行为。`scripts/test-v337-image-ocr-correction-normalized-dismissal-contract.py` 必须在 v3.36 后接入图片/UI fail-fast，并同步增强 v3.24 / v3.25 合同；源码合同不能替代真机／模拟器的键盘、VoiceOver、sheet 下滑或文本输入回放。
- v3.38 正式要求同一 `ImageOCRCorrectionSheet` 以 View 私有 `@FocusState correctedOriginalFocused` 绑定多行 `TextField`，并在 keyboard toolbar 提供命名且可访问的“完成”动作。取消、打开“忽略此文字块”确认和保存前必须先调用同一 `dismissKeyboard` 清焦点；这只能改变键盘可见性，不能改变 v3.37 的文本规范化、v3.24 discard protection、v3.25 确认无误分流、Store correction 参数、图片 task／revision 或 v3.30–v3.35 关闭后焦点交接。`scripts/test-v338-image-ocr-correction-keyboard-contract.py` 必须在 v3.37 后接入图片/UI fail-fast；源码合同不能替代真实设备／模拟器的输入法、键盘附件、VoiceOver 或 confirmationDialog 回放。
- v3.39 正式要求同一 `ImageOCRCorrectionSheet` 的既有 `Form` 设置 `.scrollDismissesKeyboard(.interactively)`，以便在长文本或下方操作区滚动时交互式收起软件键盘。v3.38 的 keyboard toolbar“完成”及取消、打开忽略确认、保存前的 `dismissKeyboard` 必须保留，三种途径都只能改变 View 的键盘焦点／可见性；不得改变 v3.37 的文本规范化、v3.24 discard protection、v3.25 确认无误分流、Store correction 参数、图片 task／revision 或 v3.30–v3.35 关闭后焦点交接。`scripts/test-v339-image-ocr-correction-scroll-dismiss-contract.py` 必须在 v3.38 后接入图片/UI fail-fast；源码合同不能替代真实设备／模拟器的滚动手势、第三方输入法、VoiceOver 或紧凑布局回放。
- v3.40 正式要求 `ImageOCRCorrectionSheet` 的“修正后的文字”多行 `TextField` 在且仅在既有 `isSaving`（`imageTranslationCorrectionBlockID == block.id`）时禁用；在异步“保存并重译”完成前，不得允许新的输入被 success dismissal 静默丢弃。v3.38 的键盘清焦点、v3.39 的滚动收起、v3.37 规范化、v3.24 discard protection、v3.25 确认无误分流、Store correction 参数、图片 task／revision 和 v3.30–v3.35 关闭后焦点交接都必须保持不变。`scripts/test-v340-image-ocr-correction-save-lock-contract.py` 必须在 v3.39 后接入图片/UI fail-fast；源码合同不能替代真实设备／模拟器的异步翻译、屏幕阅读器或输入法回放。
- v3.41 正式要求 OCR blocks 在逐块翻译时可继续查看和定位，但 `ImageTranslationPanel` 的修正、恢复 Vision OCR、恢复已忽略 block、旁贴／覆盖切换只能在 `.translated && !isRenderingExport` 时开放；开始／继续／重启复查、行级与局部预览的完成／撤销只能在 `.translated` 时开放。`TranslationSessionStore` 的 mark／reopen／reset 必须以同一 finalized-state guard 二次拒收，成功 OCR 修正必须先恢复 `.translated` 再自动标记已复查，不能因防线新增而丢失既有成功路径。`scripts/test-v341-image-review-final-state-lock-contract.py` 必须在 v3.40 后接入图片/UI fail-fast，并与 v3.16、v3.17、v3.19、v3.21、v3.23、v3.34、v3.35、v1.87 回归合同共同运行；源码合同不能替代真实逐块翻译、失败态、VoiceOver 或连续触摸回放。
- v3.42 正式要求 v3.41 的最终状态门在实际 blocks 仍可见时给出可理解反馈：`ImageTranslationPanel` 只在 blocks 非空且 mutation／review 任一锁住时显示只读警示状态行；覆盖方式、开始／继续／重启复查、局部预览、结果行、Vision OCR 恢复与已忽略 block 恢复的禁用提示必须复用 `imageModificationUnavailableDetail` 或 `imageReviewUnavailableDetail`，区分 loading／recognizing／translating／failed／export-rendering，逐块翻译明确保留查看／定位。不得改变 `canModifyImageTranslation`／`canReviewImageTranslation`、Store finalized-state guard、OCR、翻译、renderer/export、持久化或 Koharu 主路径。`scripts/test-v342-image-action-lock-feedback-contract.py` 必须在 v3.41 后接入图片/UI fail-fast，v3.16 与 v3.41 合同也必须锁定该状态化提示的传递；源码合同不能替代真实逐块翻译、VoiceOver、Dynamic Type 或连续触摸回放。
- v3.43 正式要求图片局部预览的前后导航继续保留 `.disabled(!canSelectPrevious)` / `.disabled(!canSelectNext)`，并按状态提供可访问提示：可移动时为“定位上一个／下一个文字块”，筛选首尾为“当前已是筛选结果中的第一个／最后一个文字块”。结果行主操作的 hint 必须随 `isSelected` 在“取消此文字块在图片中的定位”和“在图片预览中定位此文字块”之间切换。该改动只增加 View 的状态化 VoiceOver 反馈，不改变选择、OCR、翻译、renderer/export、Store、持久化、漫画探针、Koharu、metrics 或 output；`scripts/test-v343-image-navigation-accessibility-contract.py` 必须在 v3.42 后接入图片/UI fail-fast，源码合同不能替代真实设备／模拟器的 VoiceOver、Dynamic Type 或连续手势回放。
- v3.44 正式要求上述前后导航按钮继续保留 v3.43 的边界 disabled 与动态 hint，并各自附带同一个 View 私有 `navigationPositionAccessibilityValue`：有 `positionText` 时读出“当前位置 (positionText)”，无位置时读出“未显示筛选位置”。该 value 只消费已有筛选位置，不新增 Store／持久化／选择状态；`scripts/test-v344-image-navigation-position-accessibility-contract.py` 必须在 v3.43 后接入图片/UI fail-fast，源码合同不能替代真实设备／模拟器 VoiceOver、Dynamic Type 或连续手势回放。
- v3.45 正式要求完整图片预览的 `ImageTranslationOverlayBlock` 两种覆盖模式继续提供可访问 label、translation/selection value 和至少 44pt 点击区，并让其 View 私有 `accessibilityHint` 与结果行主定位 hint 复用同一状态分流：已定位时为“取消此文字块在图片中的定位”，未定位时为“在图片预览中定位此文字块”。该改动只统一图片入口与列表入口的操作语义，不改变选择、OCR、翻译、Store、持久化、renderer/export、漫画探针、Koharu、metrics 或 output；`scripts/test-v345-image-overlay-accessibility-contract.py` 必须在 v3.44 后接入图片/UI fail-fast。历史 v3.15 合同只验证 hint 接线与可访问结构，不得硬编码已废弃的旧文案；源码合同不能替代真实设备／模拟器 VoiceOver、Dynamic Type 或连续触摸回放。
- v3.46 正式要求 `ImageTranslationPreview` 的加载／失败卡片以 View 私有状态提供稳定的 accessibility label/value：加载时说明正在准备图片预览，失败时说明原图仍可用于 OCR 与导出；失败分支的“重试预览”必须附带“只重新生成屏幕预览、不重新识别或翻译”的操作提示，并继续只递增 View 私有 `previewAttempt`。该改动只改善状态可理解性，不改变 `ImagePreviewService`、图片 revision、OCR、翻译、renderer/export、Store、持久化、漫画探针、Koharu、metrics 或 output；`scripts/test-v346-image-preview-status-accessibility-contract.py` 必须在 v3.45 后接入图片/UI fail-fast。源码合同不能替代真实设备／模拟器 VoiceOver、Dynamic Type、预览失败恢复或连续手势回放。
- v3.47 正式要求图片命令栏的高频操作提供作用域明确的 VoiceOver hint：照片／文件选择说明会开始本机 OCR 与翻译，首次选择与替换当前图片动态区分；取消说明保留已载入图片以便重试；重试与重新识别说明使用当前语言重新处理；重试导出说明只重建旁贴／覆盖导出图；导出／分享说明准备当前导出图；清空说明会在确认后删除图片、识别结果、译文和导出文件。免费入口仍只显示 Pro 锁定提示，所有 hint 只改善 UI 语义，不改变 Store、OCR、翻译、renderer/export、探针或持久化。`scripts/test-v347-image-command-accessibility-contract.py` 必须在 v3.46 后接入图片/UI fail-fast；源码合同不能替代真实设备／模拟器 VoiceOver、Dynamic Type 或实际分享／取消手势回放。
- v3.48 正式要求完整 `ImageTranslationPreview` 在 ready 分支提供 View 私有的 VoiceOver 容器 label/value/hint：value 必须汇总当前完整 `store.imageTranslationBlocks` 的文字块总数、`ImageOCRResultSummary.requiresReview` 风险块扣除 `reviewedBlockIDs` 后的待复查数量，以及当前筛选位置；没有 blocks 或没有风险块时也要给出明确空态。容器内的原始背景 `Image` 必须 `.accessibilityHidden(true)`，避免与可点选 OCR 覆盖重复朗读；hint 继续说明点按文字块可定位并打开局部放大，并复用既有 `canEdit`／`canReview` 禁用原因，不得伪造可用操作。该改动只改善 View 的可操作上下文，不新增 Store／持久化状态，不改变选择、OCR、翻译、renderer/export、漫画探针、Koharu、metrics 或 output。`scripts/test-v348-image-preview-context-accessibility-contract.py` 必须在 v3.47 后接入同一图片/UI fail-fast；v3.47 合同须允许后续正式 `3.x` 版本回归；源码合同不能替代真实设备／模拟器 VoiceOver、Dynamic Type、覆盖命中区域或连续手势回放。
- v1.98 候选要求普通图片的 Vision OCR bbox、SwiftUI 预览和 PNG 导出统一使用顶左原点；export renderer 必须显式消费 `旁贴/覆盖` mode。后台 renderer 只能写 render ID 独占的 staging PNG；模式切换后旧 export URL 立即失效并重绘，只有同时核对 render ID、图片 task ID 和 mode 后才能原子发布稳定 export，过期 staging 必须清理；运行中模式控制禁用。`scripts/test-v187-ui-interaction-contract.py` 锁定这些边界。
- 需要探针验收时，手动 `workflow_dispatch` 选择 `ci-fast` 或 `full`。`ci-fast` 仍跑真实模拟器、Local GGUF、真实 `test/1.png`、deterministic 解码、主 OCR / bubble-first 融合 / 逐块翻译 / 失败块覆盖 / clean text / external artifact gate，以及 v1.18+ 必需的 report-only / detector-lite 受限 shadow 报告；只跳过明确列出的高成本对照和诊断 PNG。`ci-fast` 必须保留 `probe_report.json`、`clean_text_diagnostic.json`、`1_ocr_probe_text.txt`、`1_debug_boxes.png`、`1_translated_overlay.png`、`manga_probe_progress.json`。`full` 额外要求 contact sheet 等完整关键 PNG。
- 探针模式等待期间 `ci-fast` 每 30 秒打印 `output/manga_probe_progress.json` 和输出目录快照，1800 秒总超时、启动后 180 秒未创建 progress 提前失败、进度 300 秒不更新提前失败；`full` 为 3600 秒总超时、300 秒 no-progress 阈值、600 秒停滞阈值。失败时仍复制已有 `output/`，并在结果包保留 `manga-probe.log`、`app-console.log`、manifest 和失败摘要。

- v3.49 正式要求图片输入语言与目标语言控制的 VoiceOver hint 按运行中、Pro 锁定、无图片、已完成、失败／取消重试分流；两套菜单继续保留 `.disabled(isRunning)`，已完成输入语言提示说明会重新识别和翻译，目标语言提示说明会重新翻译当前图片，选回当前内容语言撤销 pending retry 差异。该改动只改善 View 私有语义，不新增 Store／持久化状态，不改变图片 task、OCR、翻译、renderer/export、探针、Koharu、metrics 或 output。`scripts/test-v349-image-language-accessibility-contract.py` 必须在 v3.48 后接入 UI interaction fail-fast；源码合同不能替代真实设备／模拟器 VoiceOver、Dynamic Type 或语言切换回放。
- v3.50 正式要求照片与文件导入按钮在读取、OCR 或翻译进行中提供明确的 VoiceOver supersession 提示：选择新图片会取消当前图片读取、OCR 或翻译并开始新的本机 OCR 与翻译；空态／非运行态继续说明首次选择、替换当前图片或文件导入，Pro 锁定入口不变，且两个导入入口保持可用，不得擅自新增 `.disabled(isRunning)`。该改动只改善 View 私有语义，不新增 Store／持久化状态，不改变已有 `TranslationSessionStore` task-id 隔离、OCR、翻译、renderer/export、探针、Koharu、metrics 或 output。`scripts/test-v350-image-selection-supersession-accessibility-contract.py` 必须在 v3.49 后接入同一图片/UI fail-fast；v3.47–v3.49 合同须允许后续正式 `3.x` 版本回归；源码合同不能替代真实设备／模拟器 VoiceOver、Dynamic Type、PhotosPicker／fileImporter 取消与替换手势回放。
- v3.51 正式要求图片状态行成为单一、稳定的 VoiceOver 状态元素：label 固定为“图片翻译状态”，value 同时包含既有 `statusTitle` 与 `statusDetail`（包括逐块进度），hint 必须按载入、Vision OCR、逐块翻译、导出重绘、分享准备、失败、取消／待重试和完成状态说明可取消、换图、重试、修正、复查、覆盖或导出边界。该改动只改善 View 私有语义，不新增 Store／持久化状态，不改变 `TranslationSessionStore`、OCR、翻译、renderer/export、探针、Koharu、metrics 或 output。`scripts/test-v351-image-status-accessibility-contract.py` 必须在 v3.50 后接入同一图片/UI fail-fast；v3.47–v3.50 合同须允许后续正式 `3.x` 版本回归；源码合同不能替代真实设备／模拟器 VoiceOver、Dynamic Type、状态更新朗读和连续操作回放。
- v3.52 正式要求图片 OCR 结果行的主 Button 使用 View 私有动态 accessibility value：除定位状态外还要读出 OCR 置信度（先 clamp 到 0–100%）、低置信／方向待定、人工修正、待复查／本次已复查与等待翻译；定位 hint 和现有独立修正／复查按钮保持不变。该改动只改善 View 语义，不新增 Store／持久化状态，不改变 OCR、翻译、renderer/export、探针、Koharu、metrics 或 output。`scripts/test-v352-image-review-row-accessibility-contract.py` 必须在 v3.51 后接入同一图片/UI fail-fast；源码合同不能替代真实设备／模拟器 VoiceOver、Dynamic Type、置信度边界或连续操作回放。
- v3.53 正式要求已忽略 OCR 文字块恢复行使用 View 私有稳定 accessibility label/value：label 必须包含 OCR 原文，value 必须说明该 block 已从图片预览、导出和当前转录移除、是否保留现有译文以及恢复是否可用；恢复按钮继续保留 44pt 点击区、disabled 原因和 `image-ignored-row-<UUID>` 焦点 ID。该改动只改善 View 语义，不新增 Store／持久化状态，不改变忽略／恢复、OCR、翻译、renderer/export、探针、Koharu、metrics 或 output；`scripts/test-v353-image-ignored-row-accessibility-contract.py` 必须在 v3.52 后接入同一图片/UI fail-fast；源码合同不能替代真实设备／模拟器 VoiceOver、Dynamic Type、恢复禁用边界或连续操作回放。
- v3.54 正式要求图片状态行的 VoiceOver value 必须使用动态 `statusTitle`／`statusDetail` 字符串插值，不能退化为字面量 `(statusTitle)：(statusDetail)`；该 value 继续与固定 label“图片翻译状态”和既有 lifecycle hint 组合，确保载入、Vision OCR、逐块翻译进度、导出重绘、分享准备、失败、取消／待重试和完成详情会随状态实际更新。该修复只改善 View 私有语义，不新增 Store／持久化状态，不改变 `TranslationSessionStore`、OCR、翻译、renderer/export、探针、Koharu、metrics 或 output；`scripts/test-v354-image-status-value-contract.py` 必须在 v3.53 后接入同一图片/UI fail-fast，且 v3.51 合同须同步拒绝字面量实现；源码合同不能替代真实设备／模拟器 VoiceOver、Dynamic Type、状态更新朗读和连续操作回放。
- v3.55 正式要求开发控制台 `MangaKoharuArtifactReadinessSummary` 的状态行成为稳定 VoiceOver 上下文：固定 label 为“Koharu 工件就绪状态”，value 必须组合既有 `statusTitle`／`statusDetail`，hint 按缺失四件套、契约错误、真实 detector 来源未声明和可执行 shadow OCR 分流；缺失状态必须明确 `test/koharu_artifacts/` 及 `1.manifest.json`、`1.textboxes.json`、`1.bubbles.json`、`1.segment_mask.json`，并继续声明 shadow-only、不会影响普通图片 OCR／翻译／覆盖图。该改动只消费既有 readiness report，不调用第二次探针、不新增 Store／持久化、不改变 active artifact gate、OCR、翻译、renderer/export、Koharu 主路径、metrics 或 output；`scripts/test-v355-koharu-readiness-accessibility-contract.py` 必须在 v3.54 后接入同一图片/UI fail-fast；源码合同不能替代真实设备／模拟器 VoiceOver、Dynamic Type、artifact 提供后的实际 readiness 回放。
- v3.56 正式要求漫画覆盖翻译探针状态行成为单一、稳定的 VoiceOver 上下文：固定 label 为“漫画覆盖翻译探针状态”，value 必须组合既有 `probeStatusTitle` 与探针详情，hint 按等待、载入、Vision OCR、翻译、绘制、完成和失败分流；运行按钮必须说明 bundle `test/1.png`、Output 诊断文件和“不会改变普通图片 OCR、翻译或覆盖图”的边界。该改动只改善开发者操作语义，不新增 Store／持久化、不调用第二次探针，不改变漫画探针诊断契约、普通图片 OCR、翻译、renderer/export、Koharu、metrics 或 output；`scripts/test-v356-manga-probe-status-accessibility-contract.py` 必须在 v3.55 后接入同一 UI fail-fast；源码合同不能替代真实设备／模拟器 VoiceOver、Dynamic Type、探针状态更新和失败重试回放。
- v3.57 正式要求开发控制台 `MangaProbeBlockRow` 为每个漫画探针文字块提供稳定 VoiceOver label/value/hint：label 必须包含 block index，value 必须读出 PASS/FAIL、OCR 原文、旋转角度、可用的 OCR 置信度（clamp 到 0–100%）、质量标签、译文与失败/翻译失败详情，hint 必须说明展开范围和“不会改变普通图片 OCR、翻译或覆盖图”；该 View 私有语义不得读取 ground truth、运行第二次探针或修改 Store，不改变漫画探针诊断、renderer/export、Koharu、metrics 或 output；`scripts/test-v357-manga-probe-block-accessibility-contract.py` 必须在 v3.56 后接入同一 UI fail-fast；源码合同不能替代真实设备／模拟器 VoiceOver、Dynamic Type、长 OCR 文本和失败 block 回放。
- v3.58 正式要求图片复查结果行 `ImageTranslationBlockRow` 提供稳定 VoiceOver label/value：label 必须明确图片文字块并包含 OCR 原文，空 OCR 使用稳定回退；value 必须区分等待翻译与真实译文，同时保留定位、置信度和复查状态；该 View 私有语义不得读取或修改 Store、重新运行 Vision OCR/翻译或改变 renderer/export、漫画探针、Koharu、metrics 或 output；`scripts/test-v358-image-review-row-context-accessibility-contract.py` 必须在 v3.57 后接入同一 UI fail-fast；源码合同不能替代真实设备／模拟器 VoiceOver、Dynamic Type、长 OCR/译文和复查操作回放。
- v3.59 正式要求完整图片预览的相邻与替换两种覆盖模式复用稳定 VoiceOver label“图片文字块 + OCR 原文”，空 OCR 回退为“空”，保留等待翻译／译文 value、定位 hint 和选中状态；该 View 私有语义不得读取或修改 Store、重新运行 Vision OCR/翻译或改变 renderer/export、漫画探针、Koharu、metrics 或 output；`scripts/test-v359-image-overlay-block-context-accessibility-contract.py` 必须在 v3.58 后接入同一 UI fail-fast；源码合同不能替代真实设备／模拟器 VoiceOver、Dynamic Type、长 OCR/译文和覆盖定位回放。
- v3.60 正式要求完整图片预览覆盖块的相邻与替换模式复用复查结果行的 VoiceOver value：包含 clamp 到 0–100% 的 OCR 置信度、人工修正、低置信／方向待定、待复查／本次已复查及等待翻译／译文；不得读取或修改 Store 业务状态、重新运行 Vision OCR/翻译或改变 renderer/export、漫画探针、Koharu、metrics 或 output；`scripts/test-v360-image-overlay-review-context-accessibility-contract.py` 必须在 v3.59 后接入同一 UI fail-fast；源码合同不能替代真实设备／模拟器 VoiceOver、Dynamic Type、长文本、空 OCR、等待翻译和连续复查回放。
- v3.61 正式要求图片复查结果行和完整图片预览消费既有 `sourceDirection`／`directionConfidence`：已判定的横排／竖排进入 VoiceOver value，有限方向置信度 clamp 到 0–100%，结果行显示已知方向，OCR 置信度显示对非有限值和越界值安全回退；不得读取或修改 Store 业务状态、重新运行 Vision OCR/翻译或改变 renderer/export、漫画探针、Koharu、metrics 或 output；`scripts/test-v361-image-direction-review-context-contract.py` 必须在 v3.60 后接入同一 UI fail-fast；源码合同不能替代真实设备／模拟器 VoiceOver、Dynamic Type、未知／竖排方向、异常置信度和连续复查回放。

- v3.62 正式要求图片识别结果摘要展示已有 `ImageOCRResultSummary` 的横排与竖排 block 计数，并保留平均置信度、低置信与方向待定信息；合同必须只读摘要字段，不调用 Vision OCR／翻译、不写 Store／持久化、不改变 renderer/export、漫画探针、Koharu、metrics 或 output。`scripts/test-v362-image-summary-direction-breakdown-contract.py` 必须在 v3.61 后接入同一 UI fail-fast，并允许后续正式 `3.x` 版本；源码合同不能替代真实设备／模拟器上的长文本、VoiceOver、Dynamic Type 和完整图片复查回放。
- v3.63 正式要求图片“识别结果”摘要合并为单一 VoiceOver header：label 必须为“识别结果”，value 必须复用 `store.imageTranslationSummary`，hint 按无图片、翻译未完成、无待复查块和可复查状态分流；合同不得读取或修改 Store 业务状态、重新运行 OCR／翻译或改变 renderer/export、漫画探针、Koharu、metrics 或 output。`scripts/test-v363-image-summary-accessibility-context-contract.py` 必须在 v3.62 后接入同一 UI fail-fast，并允许后续正式 `3.x` 版本；源码合同不能替代真实设备／模拟器 VoiceOver、Dynamic Type 和完整图片复查回放。
- v3.64 正式要求图片 OCR 置信度在布局、摘要、低置信复查、结果行和覆盖层使用同一安全边界：非有限值回退为 0，有限值夹到 `0...1`，无效值仍可进入低置信复查；不得出现 NaN 平均值或百分比 `Int` 转换崩溃。`scripts/test-v364-image-confidence-safety-contract.py` 与纯 Swift evaluator 必须在 v3.63 后接入同一 UI fail-fast；不得借此声称 OCR 字符质量提升，源码合同不能替代真实图片 corpus、设备 VoiceOver 或完整探针。

- v3.65 正式要求图片 OCR 修正 sheet 的低置信度提示复用 ImageOCRResultSummary.normalizedConfidence，非有限／越界值在百分比格式化前安全归一化；合同必须保持 View-only，不新增 Store／持久化、不重跑 OCR／翻译或改变 renderer/export、漫画探针、Koharu、metrics 或 output。scripts/test-v365-image-confidence-display-contract.py 必须在 v3.64 后接入同一 UI fail-fast，历史 v3.47–v3.64 合同须接受后续正式版本；源码合同不能替代真实设备／模拟器 VoiceOver、Dynamic Type、真实图片 corpus 或完整探针。
- v3.66 正式要求 Vision OCR bounding box 在进入布局前通过统一的 finite／positive-area／unit-space 整矩形边界；布局引擎必须过滤 NaN/∞、零面积与完全越界 observation，并保持有效矩形与已有阅读顺序不变。scripts/test-v366-image-ocr-geometry-safety-contract.py 及纯 Swift evaluator 必须在 v3.65 后接入同一 UI fail-fast，历史 v3.47–v3.65 合同须接受后续正式版本；该安全边界不得被描述为 OCR 字符质量提升，源码合同不能替代真实图片 corpus、设备 VoiceOver 或完整探针。
- v3.67 正式要求 Codable `NormalizedImageRect` 在图片覆盖、局部定位和导出 renderer 前复用 finite／positive-area／unit-space 整矩形边界；无效恢复框必须跳过 View/绘制，不能把异常几何写回持久化或冒充 OCR 质量提升。`scripts/test-v367-image-block-geometry-safety-contract.py` 及纯 Swift evaluator 必须在 v3.66 后接入同一 UI fail-fast，历史 v3.47–v3.66 合同须接受后续正式版本；源码合同不能替代真实图片 corpus、设备 VoiceOver 或完整探针。
- v3.68 正式要求局部放大对无效或过期 OCR 框返回不可用状态，禁止整图回退造成误导；关闭、编辑和切换文字块入口必须保留，VoiceOver hint 必须说明“局部预览不可用”及可执行的替代操作，图片 OCR 修正对照仍可编辑。`scripts/test-v368-image-preview-invalid-geometry-contract.py` 必须在 v3.67 后接入同一 UI fail-fast；该 View-only 边界不代表 OCR、翻译或 Koharu 质量提升，源码合同不能替代真实图片 corpus、设备 VoiceOver 或完整探针。
- v3.69 正式要求结果行与完整图片预览的 VoiceOver 摘要复用 `NormalizedImageRect.normalizedToUnit()` 的定位可用性边界：无效或过期框必须读出“定位不可用”数量，结果行显示位置不可用图标并保留 OCR 修正和切换文字块入口。`scripts/test-v369-image-geometry-availability-contract.py` 必须在 v3.68 后接入同一 UI fail-fast，历史 v3.47–v3.68 图片合同须接受后续正式版本；该 View-only 反馈不代表 OCR、翻译或 Koharu 质量提升，源码合同不能替代真实图片 corpus、设备 VoiceOver 或完整探针。
- v3.70 正式要求完整图片预览的 VoiceOver hint 根据定位不可用数量分流：有效文字块可打开局部放大，异常文字块必须明确局部预览不可用；既有 OCR 修正、切换文字块与状态门保持不变。`scripts/test-v370-image-preview-geometry-hint-contract.py` 必须在 v3.69 后接入同一 UI fail-fast，历史 v3.47–v3.69 图片合同须接受后续正式版本；该 View-only 反馈不代表 OCR、翻译或 Koharu 质量提升，源码合同不能替代真实图片 corpus、设备 VoiceOver 或完整探针。
- v3.71 正式要求 `MangaKoharuArtifactReadinessSummary` 继续只读既有 readiness report，并在 status detail、VoiceOver hint 与可复制 summary 中显示坐标验证、mask payload verdict/gate、mask topology verdict/blockers 和 artifact identity receipt；阻塞时必须说明稳定一对一/像素分区复核或 CI 哈希对账要求，且不得创建/修改 active artifacts、放宽 shadow OCR gate 或声称 OCR/Koharu 质量提升。`scripts/test-v371-koharu-readiness-gate-detail-contract.py` 必须在 v3.70 后接入同一 UI fail-fast；历史 v3.47–v3.70 图片合同须接受后续正式版本，源码合同不能替代真实设备 VoiceOver、Koharu 四件套或探针。
- v3.72 正式要求 Developer Console 对 schema v1 且 bubble/segment payload verdict 为 `legacySummaryOnly` 的工件显示“未要求（v1 summary-only）”与“未要求（v2 拓扑）”，不得把尚未要求的 v2 门控朗读成失败；真实 v2 工件仍必须保留 payload/topology 的实际失败与 blocker。可复制 summary 与 VoiceOver hint 必须共享解释后的状态，且该 View-only/report-only 改动不得创建 active artifacts、写 Store、调用探针或改变 OCR、翻译、renderer/export、Koharu 主路径与质量基线。`scripts/test-v372-koharu-v1-readiness-clarity-contract.py` 必须在 v3.71 后接入 UI fail-fast，并保留 v3.47–v3.71 历史合同对后续正式版本的兼容；源码合同不能替代真实四件套、设备 VoiceOver 或探针。
- v3.73 正式要求 `ImageTranslationIgnoredBlockRow` 对空 `block.original` 显示“空 OCR 原文”，并让稳定 VoiceOver label 显示“已忽略 OCR 文字块 空”；非空原文、恢复按钮、disabled 原因、焦点 identity 和恢复范围必须保持不变。`scripts/test-v373-image-ignored-empty-context-contract.py` 必须在 v3.72 后接入同一 UI fail-fast，并允许历史 v3.47–v3.72 合同继续接受后续正式版本；该 View-only 改动不代表 OCR、翻译或 Koharu 质量提升，源码合同不能替代真实图片 corpus、设备 VoiceOver 或探针。
- v3.74 正式要求普通 `ImageTranslationBlockRow` 与 `ImageTranslationOverlayBlock` 在 `block.original` 为空时提供稳定的“空 OCR 原文”可见回退；旁贴／覆盖在译文非空时必须保持译文优先，空译文才显示回退。不得改变 OCR、翻译、选择、复查、Store、持久化或 renderer/export 边界。`scripts/test-v374-image-empty-ocr-consistency-contract.py` 必须在 v3.73 后接入同一 UI fail-fast，并允许历史 v3.47–v3.73 合同继续接受后续正式版本；该 View-only 改动不代表 OCR、翻译或 Koharu 质量提升，源码合同不能替代真实图片 corpus、设备 VoiceOver 或探针。
- v3.75 正式要求 `ImageOCRCorrectionReferencePreview` 与 `ImageTranslationFocusPreview` 在 `block.original` 为空时让 accessibility value 使用稳定“空”回退，非空原文仍原样读出；不得新增 Store／Vision OCR／FileManager／探针调用或改变 OCR、翻译、renderer/export、复查和 Koharu 边界。`scripts/test-v375-image-focus-empty-ocr-context-contract.py` 必须在 v3.74 后接入同一 UI fail-fast，并同步修正 v3.13、v3.14、v3.68 的历史文案断言以接受当前实现；该 View-only 改动不代表 OCR、翻译或 Koharu 质量提升，源码合同不能替代真实图片 corpus、设备 VoiceOver 或探针。
- v3.76 正式要求 `ImageTranslationFocusPreview` 的“局部放大”装饰 `Label` 使用 `.accessibilityHidden(true)`，父容器仍提供稳定 label/value/hint，关闭、OCR 修正、复查和前后定位按钮保持可访问；不得新增 Store／Vision OCR／FileManager／探针调用或改变 OCR、翻译、renderer/export、复查和 Koharu 边界。`scripts/test-v376-image-focus-preview-decorative-label-contract.py` 必须在 v3.75 后接入同一 UI fail-fast，并允许历史 v3.47–v3.75 合同继续接受后续正式版本；该 View-only 改动不代表 OCR、翻译或 Koharu 质量提升，源码合同不能替代真实图片 corpus、设备 VoiceOver 或探针。
- v3.77 正式要求 `ImageTranslationFocusPreview` 的 `unavailableFocusState` 在 `contain` 容器内使用 `.accessibilityHidden(true)`，父容器的 `focusPreviewAccessibilityHint` 必须继续读出局部预览不可用及关闭、OCR 编辑、切换文字块替代操作；关闭、OCR 修正、复查和前后定位按钮保持可访问。`scripts/test-v377-image-focus-preview-unavailable-voiceover-contract.py` 必须在 v3.76 后接入同一 UI fail-fast，并允许历史 v3.47–v3.76 合同继续接受后续正式版本；该 View-only 改动不代表 OCR、翻译或 Koharu 质量提升，源码合同不能替代真实图片 corpus、设备 VoiceOver 或探针。
- v3.78 正式要求关闭 `ImageTranslationFocusPreview` 后将 VoiceOver 焦点交回对应 OCR 结果行，使用既有 `reviewRowAccessibilityFocusID`，不得把焦点状态写入 Store 或产品 pipeline。`scripts/test-v378-image-focus-preview-close-focus-contract.py` 必须在 v3.77 后接入同一 UI fail-fast，并允许历史图片合同继续接受后续正式版本；该 View-only 改动不代表 OCR、翻译或 Koharu 质量提升，源码合同不能替代真实图片 corpus、设备 VoiceOver 或探针。
- v3.79 正式要求 `selectAdjacentBlock(offset:)` 在当前筛选顺序中选中目标 block 后，调用 `moveReviewAccessibilityFocus(to: reviewPreviewAccessibilityFocusID(targetBlockID))`，让 VoiceOver 焦点跟随新的局部预览容器；前后按钮的 position value、首尾 disabled 边界和 View-only ownership 必须保持。`scripts/test-v379-image-focus-preview-navigation-focus-contract.py` 必须在 v3.78 后接入同一 UI fail-fast；同步的 v3.14 历史合同可接受直接赋值或等价的局部 target ID 写法。该 View-only 改动不代表 OCR、翻译或 Koharu 质量提升，源码合同不能替代真实图片 corpus、设备 VoiceOver 或探针。
- v3.80 正式要求筛选器隐藏当前选中 block 时，`clearHiddenReviewSelection()` 清除旧选择并将 VoiceOver 焦点交给首个可见结果行；若没有可见行，必须交给复查完成状态或筛选器本身。`scripts/test-v380-image-review-filter-focus-contract.py` 必须在 v3.79 后接入同一 UI fail-fast，并允许历史图片合同继续接受后续正式版本；该 View-only 改动不代表 OCR、翻译或 Koharu 质量提升，源码合同不能替代真实图片 corpus、设备 VoiceOver 或探针。

- v3.81 正式要求结果行与完整图片覆盖块选中 OCR block 后，将 VoiceOver 焦点交给对应局部预览；取消定位时回到对应结果行。scripts/test-v381-image-selection-focus-contract.py 必须在 v3.80 后接入同一 UI fail-fast，历史 v3.47–v3.80 合同须接受后续正式版本；该 View-only 改动不代表 OCR、翻译或 Koharu 质量提升，源码合同不能替代真实图片 corpus、设备 VoiceOver 或探针。
- v3.82 正式要求漫画覆盖探针失败 fallback 的显式换行必须进入统一的 `wrappedLines` fit plan：按段落保留换行与空行，禁止旧的逐字符整串测量；`makeRenderTextPlan`、碰撞检测和实际绘制必须共享该结果。新增 `scripts/test-v382-manga-render-newline-contract.py`，接入 full 静态检查与 Manga service changed-file 路由。该修复只改善诊断覆盖的布局可观测性，不改变 OCR、翻译、ground truth、Koharu、普通图片主路径、metrics 或 output；云端 probe 报告中的真实截断仍必须保留，源码合同不能冒充质量提升。
- v3.83 正式要求 Koharu fit planner 与实际 `wrappedLines` 共享显式换行／空行预算，并将 `renderTextTruncated` 纳入失败 fallback 风险；新增 `scripts/test-v383-koharu-fit-budget-contract.py`，接入 full 静态检查与 Manga service changed-file 路由。该 report-only 修复只改善诊断一致性，不改变 OCR、翻译、ground truth、renderer/export、Koharu、普通图片主路径、metrics 或 output；云端 probe 报告仍必须保留真实截断，源码合同不能冒充质量提升。
- v3.84 正式要求 Koharu fit planner 将既有 `renderMinFontSizeReached` 从 block/render lock 传播到逐 block ledger、decision signal、汇总 `renderMinFontSizeReachedBlocks` 和 `G-render-sprite-fit-min-font-evidence` report-only gate；`scripts/test-v384-koharu-render-min-font-contract.py` 必须在 v3.83 后接入 Koharu changed-file/full 静态路由，并允许 v3.82/v3.83 历史合同接受后续正式版本。该诊断性改动不改变 OCR、翻译、ground truth、生产 renderer/export、Koharu active artifact gate、普通图片 OCR、metrics 或 output；云端 ci-fast 报告可证明最小字号压力与实际截断，但不能替代质量证据。

- v3.85 正式要求 `MangaKoharuRenderRegressionLockReport` 从既有 block/render lock 传播 `renderMinFontSizeReached` 到逐 block decision trace、顶层 `renderMinFontSizeReachedBlocks`、`G-render-min-font-evidence` report-only gate 与 Developer Console 摘要；`scripts/test-v385-koharu-render-lock-min-font-contract.py` 必须在 v3.84 后接入 Koharu changed-file/full 静态路由，并允许 v3.82–v3.84 历史合同接受后续正式版本。该诊断性改动不改变 OCR、翻译、ground truth、生产 renderer/export、Koharu active artifact gate、普通图片 OCR、metrics 或 output；云端 ci-fast 报告可证明最小字号压力与实际截断，但不能替代质量证据。

- v3.86 正式要求 render-lock 输出文件检查识别最终报告与最终 OCR 文本重写的 planned-final-write 时序：`probe_report.json` 和 `1_ocr_probe_text.txt` 在报告组装前尚未落盘时不得被记为 `presentButEmptyOrUnchecked`，成功探针必须让 `coreOutputFilesNonEmpty=true`、`G-render-core-png-retained=passed`，并保留真实 `G-render-no-text-truncation` 阻塞。新增 `scripts/test-v386-koharu-render-output-ledger-contract.py`，接入 Koharu changed-file/full 静态路由并让 v3.82–v3.85 历史合同接受后续正式版本；失败写入仍不能生成成功报告。该 report-only 修复不改变 OCR、翻译、ground truth、renderer/export、Koharu active artifact gate、普通图片 OCR、metrics 或 output，源码合同不能代替真实探针/PNG/设备证据或真实 Koharu 四件套。

- v3.87 正式要求 render-lock 输出检查把 planned final write 的推荐动作与状态一致化：`plannedFinalReportWrite` 与 `plannedFinalOCRTextRewrite` 在 `nonEmpty=true` 时必须为 `recommendedAction=keepReportOnly`，只有缺失或未检查输出才允许 `inspectRenderOutputExport`。新增 `scripts/test-v387-koharu-render-output-action-contract.py`，接入 Koharu changed-file/full 静态路由，并让 v3.82–v3.86 历史合同接受后续正式版本；失败写入仍不能生成成功报告。该 report-only 修复不改变 OCR、翻译、ground truth、renderer/export、Koharu active artifact gate、普通图片 OCR、metrics 或 output，源码合同不能代替真实探针/PNG/设备证据或真实 Koharu 四件套。

- v3.88 正式要求 `G-render-core-png-retained` 的推荐动作与 required output 状态一致：`coreOutputFilesNonEmpty=true` 时必须为 `keepReportOnly`，否则为 `inspectRenderOutputExport`；新增 `scripts/test-v388-koharu-render-core-output-gate-action-contract.py` 并接入 Koharu changed-file/full 静态路由，历史 v3.82–v3.87 合同须接受后续正式版本。该 report-only 修复不改变 OCR、翻译、ground truth、renderer/export、Koharu active artifact gate、普通图片 OCR、metrics 或 output，源码合同不能代替真实探针/PNG/设备证据或真实 Koharu 四件套。

- v3.89 正式要求 Developer Console 的 `outputFiles` 摘要显示 required 输出的 `recommendedAction` breakdown，并与 `G-render-core-png-retained`／`outputFileChecks` 共用既有 report-only 状态；新增 `scripts/test-v389-koharu-render-output-summary-action-contract.py`，接入 Koharu changed-file/full 静态路由，历史 v3.82–v3.88 合同须接受后续正式版本。ci-fast 应能在输出文本看到类似 `actionBreakdown=keepReportOnly=5`；该 UX 不改变 OCR、翻译、ground truth、renderer/export、Koharu active artifact gate、普通图片 OCR、metrics 或 output，源码合同不能代替真实探针/PNG/设备证据或真实 Koharu 四件套。

- v3.90 正式要求漫画探针失败覆盖保留完整 OCR fallback 和首行 `翻译失败` 标记，同时仅在显示层把 OCR continuation 的显式换行压缩为空格；安全布局诊断、Koharu fit planner 与实际覆盖绘制必须共用该变换，不能修改 OCR 候选、翻译输入、Store、普通图片 renderer/export 或 active artifact gate。新增 `scripts/test-v390-koharu-render-failure-overlay-compaction-contract.py`，接入 Koharu changed-file/full 静态路由，并让 v3.82–v3.89 历史合同接受后续正式版本。full/ci-fast/PR fast/merge fast 必须核对 exact SHA、manifest、JUnit、Xcode 结果和探针输出；ci-fast 应能证明 `renderTextTruncatedBlocks=[]`、block 5 无截断/最小字号锁且覆盖 PNG 非空，但这只是渲染诊断证据，不是 OCR、翻译或 Koharu 质量证据。缺少真实 `test/koharu_artifacts/` 四件套时 readiness 仍必须为 `manifestMissing / stopUntilArtifactsProvided`。
- v3.91 正式要求 Developer Console 在既有漫画 `probe_report` 下渲染只读 `MangaProbeDiagnosticTriageSummary`：必须消费 `translationModelFloorComparisonReport`、`diagnostics`、`externalArtifactReadinessReport` 与 render issue 列表，显示 floor verdict、baseline／variant pass rate、下一步、`diagnosticOnly`／`wouldChangeMainFlow`，并让失败 block 行按现有 failureCategory 显示“模型输出失败／译文质量失败／OCR 疑似损坏”及 VoiceOver 分流上下文。合同 `scripts/test-v391-koharu-diagnostic-triage-contract.py` 必须接入 Koharu changed-file/full 静态路由；历史 v3.82–v3.90 合同须接受后续正式版本。该 View-only/report-only 改动不得新增 Store／持久化、调用第二次探针、使用 ground truth 作为候选、改变 OCR、翻译 prompt／model、renderer/export、metrics 或 output。full/ci-fast/PR fast/merge fast 必须核对 exact SHA、manifest、JUnit、Xcode receipt 和探针输出；ci-fast 仅证明报告与 PNG 导出成功，缺少真实 `test/koharu_artifacts/` 四件套时 readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不得声称 OCR、翻译、识别或 Koharu 质量提升。
- v3.92 正式要求普通图片 OCR 复查筛选包含 `all`、`needsReview`、`lowConfidence`、`unknownDirection` 四类：低置信和方向待定必须复用 `ImageOCRResultSummary` 判定，待复查必须保持两类风险的未完成并集；筛选为 View/模型展示状态，不得写 Store、改变 `ImageTranslationBlock`、预览、导出、OCR 或翻译。无结果空态、VoiceOver hint、筛选变化后的焦点和忽略文字块后的当前筛选定位必须明确。Developer Console 必须提供漫画诊断全部／失败／OCR／翻译／布局筛选，只消费既有 `MangaOverlayProbeReport`，探针新运行时重置筛选，不能改变 `probe_report` 或主流程。新增 `scripts/test-v392-image-review-risk-filter-contract.py` 与 evaluator，接入 UI/full 路由；历史 v3.82–v3.91 合同须接受后续版本。full/PR fast/merge fast 必须核对 exact SHA、manifest、JUnit 和 Xcode receipt；push 默认 probe skip，缺少真实 Koharu 四件套时 readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不得声称 OCR、翻译、识别或 Koharu 质量提升。

- v3.93 正式要求 `imageTranslationRevision` 变化时，图片复查 View 将 `reviewFilter` 恢复为 `.all`，并清除旧选择、编辑/恢复状态与 VoiceOver 焦点；该筛选仍为 View 私有状态，不得写 Store／持久化或改变 `imageTranslationBlocks`、OCR、翻译、预览、导出。新增 `scripts/test-v393-image-review-filter-reset-contract.py`，接入 UI/full 路由；历史 v3.92 合同须接受后续版本。full/PR fast/merge fast 必须核对 exact SHA、manifest、JUnit 和 Xcode receipt；push 默认 probe skip，缺少真实 Koharu 四件套时 readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不得声称 OCR、翻译、识别或 Koharu 质量提升。

### v3.94 漫画探针失败入口清理合同

- 每次漫画探针尝试必须在查找 bundle `test/1.png` 前清空上一轮 `mangaOverlayProbeReport` 与 `mangaOverlayProbeBlocks`，避免失败入口继续展示旧诊断。
- 缺失 `test/1.png` 的失败入口必须重建 App 沙盒 `Output`，记录 `outputCleanupRemovedItemCount` 和 `outputDirectoryCleaned`；若清理失败，`outputCleanupPolicy` 必须明确旧输出可能残留，不得冒充本轮输出。
- 正常异步失败也必须传播清理计数和清理状态；新增 `scripts/test-v394-manga-probe-failure-cleanup-contract.py`，接入 Koharu changed-file/full 静态路由。
- 该合同只验证状态/输出隔离，不改变 OCR 候选、翻译 prompt/model、ground truth、renderer/export、普通图片 OCR、Koharu active artifact gate、metrics 或仓库 `output`。full/PR fast/merge fast 需要核对 exact SHA、manifest、JUnit 与 Xcode receipt；push 默认 `probe_mode=skip`，缺少真实四件套时 readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`。

### v3.121 图片 OCR 状态行重试 action 合同

- `scripts/test-v3121-image-status-retry-accessibility-contract.py` 必须验证：当普通图片处于失败／取消后的可重试状态且没有待重试语言摘要时，图片翻译状态行才附加命名为“重试当前图片”的 VoiceOver action；action 必须受既有 `store.canRetryImageTranslation` guard 保护并复用 `store.retryImageTranslation()`。
- 状态行必须继续在 inspector 内提供单一 label/value/hint 和稳定 focus identity；hint 必须区分源图片可重试与文件不可用。已有“重试语言已更新”状态保留唯一 action，避免重复入口。该 View-only 合同不得新增 Store／持久化、OCR、翻译、renderer/export、probe_report 或 Koharu active gate 路径。
- 合同接在 v3.120 后进入 UI/full fail-fast。候选 full `31076710802`（exact SHA `9551c0c53bae0b8816d490a3da03c9472995e859`）Xcode/JUnit `10/10` 成功；PR #185 fast `31077094866`、merge fast `31077152440` 复用候选 full，Xcode skipped，JUnit `10/10`。探针默认 `probe_mode=skip`，readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不声称 OCR、翻译、识别或 Koharu 质量提升。

### v3.125 图片直接失败状态焦点合同

- `scripts/test-v3125-image-direct-failure-focus-contract.py` 必须验证 `ImageTranslationPanel` 在图片状态进入 `.failed` 且没有当前 `imageTranslationRevision` 对应的终态焦点请求时，清除 stale pending revision 并通过既有 `moveReviewAccessibilityFocus(to: Self.imageTranslationStatusAccessibilityFocusID)` 聚焦图片翻译状态行；正常 revision-scoped OCR／翻译失败继续走 `focusImageTranslationTerminalStateIfNeeded()`，不能被 fallback 重复抢焦点。
- 文件选择失败等直接失败路径可以保持 Store 的既有状态更新且不新增 revision；该合同只补 View 的状态焦点，不得新增 Store／持久化、OCR、翻译、renderer/export、probe_report 或 Koharu active gate 路径。
- 合同接在 v3.124 后进入 UI/full fail-fast，CI 路由将 v3.125 纳入既有正则与顶层兼容标记。候选 full `31081494834`（exact SHA `1c068d538728a1195fdd08197f16f7e82d06dd4b`）Xcode/JUnit `10/10` 成功；PR #189 fast `31081976028`、merge fast `31082019649` 复用候选 full，Xcode skipped，JUnit `10/10`。探针默认 `probe_mode=skip`，readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，真实 Koharu 四件套缺失，不声称 OCR、翻译、识别或 Koharu 质量提升。

### v3.126 图片导出／分享失败状态焦点合同

- `scripts/test-v3126-image-export-share-failure-focus-contract.py` 必须验证 `ImageTranslationPanel` 监听既有 `imageTranslationShareState` 与 `imageTranslationExportRenderState`；只有状态发生变化并进入 `.failed` 时，才通过既有 `moveReviewAccessibilityFocus(to: Self.imageTranslationStatusAccessibilityFocusID)` 将 VoiceOver 焦点交给图片翻译状态行。
- `.preparing`／`.rendering` 等运行中状态不得抢焦点；焦点与失败分流必须保持 View 私有，不新增 Store／持久化，不改变 OCR、翻译、renderer/export、probe_report 或 Koharu active gate。
- 合同接在 v3.125 后进入 UI/full fail-fast，并沿用表达式长度安全的既有 UI 路由。候选 full `31082994159`（exact SHA `244f97435d340207c7684c3a2ab553b552b3b780`）Xcode/JUnit `10/10` 成功；PR #190 fast `31083400009`、merge fast `31083557316` 复用候选 full，Xcode skipped，JUnit `10/10`。探针默认 `probe_mode=skip`，readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，真实 Koharu 四件套缺失，不声称 OCR、翻译、识别或 Koharu 质量提升。

### v3.146 普通图片已忽略 OCR 行直接恢复 action 合同

- `scripts/test-v3146-image-ignored-row-restore-action-contract.py` 必须验证 `ImageTranslationIgnoredBlockRow` 在 `canRestore` 为真时通过父级 VoiceOver 容器提供同名“恢复” action，并复用传入的既有 `restore` 回调；父级 hint 必须说明恢复到图片预览、导出和当前转录，以及需要复查时重新回到待复查队列。`canRestore` 为假时不得暴露父级 action，必须保留 `modificationUnavailableHint`。
- 现有“恢复”子按钮、44pt 点击区、`.disabled(!canRestore)`、`image-ignored-row-<UUID>` focus identity、子按钮 hint 和行的 label/value 必须保持；改动只属于 View，不新增 Store／持久化、OCR、翻译、renderer/export、探针、Koharu、metrics 或 `output`。
- 合同接在 v3.145 后进入 UI/full fail-fast。候选 exact-SHA full `31157259172`（`21768ac2c9a9cd5efdb87aebae62def5f1e20071`）Xcode/JUnit `10/10` 成功；PR #210 fast `31157792746`、merge fast `31157872257` 复用候选 full，Xcode/UI/Speech skipped，JUnit `10/10`。探针默认 `probe_mode=skip`，readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不得据此声称 OCR、翻译、识别或 Koharu 质量提升。

### v3.145 普通图片文件导入替换提示合同

- `scripts/test-v3145-image-file-selection-replacement-hint-contract.py` 必须验证文件导入入口的 VoiceOver hint 在无图片时说明首次选择、已有图片时说明更换当前图片并开始新的本机 OCR 与翻译；读取／Vision OCR／翻译运行中继续说明新选择会取消当前任务并开始新任务，且文件入口不得被 `.disabled(isRunning)` 锁住。
- 合同只允许读取既有 `TranslationSessionStore` 状态并接线到现有 `openImporter`，不得新增 Store／持久化、OCR、翻译、renderer/export、探针、Koharu、metrics 或 `output` 行为。历史 v3.347、v3.350 入口合同须允许后续正式版本，保留照片入口与文件入口的首次／替换／运行中 supersession 语义。
- 合同接在 v3.144 后进入 UI/full fail-fast。候选 exact-SHA full `31155971109`（`92f495212a40910be1540c06f28cf4402c0b956f`）Xcode/JUnit `10/10` 成功；PR #209 fast `31156530851`、merge fast `31156622662` 复用候选 full，Xcode/UI/Speech skipped，JUnit `10/10`。探针默认 `probe_mode=skip`，readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不得据此声称 OCR、翻译、识别或 Koharu 质量提升。

### v3.144 普通图片 OCR 空结果 VoiceOver 重新识别 action 合同

- `scripts/test-v3144-image-empty-result-rerun-action-contract.py` 必须验证已完成且没有可显示 OCR 文字块的结果空态，在源图片仍可重跑时通过 View-only helper 暴露同名“重新识别” VoiceOver action，并直接复用 Store `rerunImageRecognition()`；`canRerunImageRecognition` 为假时不得暴露 action。
- 空态 hint 必须说明“只重跑当前图片的 Vision OCR 与翻译”，保留不可重跑时的换图恢复边界；不得新增 Store／持久化或改变 OCR、翻译、renderer/export、探针、Koharu、metrics、`output`。
- 合同接在 v3.143 后进入 UI/full fail-fast。候选 exact-SHA full `31154791726`（`ff31f66f71698c6f34a7e1b7e52a940485984eea`）Xcode/JUnit `10/10` 成功；PR #208 fast `31155305272`、merge fast `31155356211` 复用候选 full，Xcode/UI/Speech skipped，JUnit `10/10`。探针默认 `probe_mode=skip`，readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不声称 OCR、翻译、识别或 Koharu 质量提升。

### v3.143 普通图片 OCR 结果行 VoiceOver action hint 合同

- `scripts/test-v3143-image-review-row-action-hint-contract.py` 必须验证 `ImageTranslationBlockRow` 的 hint 保留定位和几何不可用语义，并只列出当前真正暴露的“修正识别文字／恢复 Vision OCR／完成并继续复查或撤销本次复查” action；锁定、非人工修正或非风险状态不得虚构 action。
- 结果行现有 `.accessibilityElement(children: .combine)`、动态 value、稳定 focus identity、三个 gated action modifier、可见按钮与既有禁用原因必须保持；改动不得新增 Store／持久化或改变 OCR、翻译、renderer/export、探针、Koharu、metrics、`output`。
- 合同接在 v3.142 后进入 UI/full fail-fast。候选 exact-SHA full `31153705887`（`3a6da4be92c3275c2efb31dab550b5a227af5da8`）Xcode/JUnit `10/10` 成功；PR #207 fast `31154097383`、merge fast `31154147898` 复用候选 full，Xcode/UI/Speech skipped，JUnit `10/10`。探针默认 `probe_mode=skip`，readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不声称 OCR、翻译、识别或 Koharu 质量提升。

### v3.142 普通图片 OCR 结果行 VoiceOver review action 合同

- `scripts/test-v3142-image-review-row-review-action-contract.py` 必须验证 `ImageTranslationBlockRow` 在 `isReviewRequired && canReview` 时通过 View-only modifier 暴露同名“完成并继续复查／撤销本次复查” VoiceOver action，并直接复用既有 `toggleReviewCompletion()`；非风险或 `canReview` 为假时不得暴露 action。
- 结果行原有定位 label/value/hint、稳定 `image-review-row-*` focus identity、可见复查按钮及其 `reviewUnavailableHint` 必须保持；改动不得新增 Store／持久化或改变 OCR、翻译、renderer/export、探针、Koharu、metrics、`output`。
- 合同接在 v3.141 后进入 UI/full fail-fast。候选 exact-SHA full `31152734900`（`e94fb6a1fdfbeaddd64a0995dda5d1e872e91d84`）Xcode/JUnit `10/10` 成功；PR #206 fast `31153171846`、merge fast `31153229469` 复用候选 full，Xcode/UI/Speech skipped，JUnit `10/10`。探针默认 `probe_mode=skip`，readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不声称 OCR、翻译、识别或 Koharu 质量提升。

### v3.141 普通图片 OCR 结果行 VoiceOver restore action 合同

- `scripts/test-v3141-image-review-row-restore-action-contract.py` 必须验证 `ImageTranslationBlockRow` 在 `isManuallyCorrected && canEdit` 时通过 View-only modifier 暴露同名“恢复 Vision OCR” VoiceOver action，并直接复用既有 `restoreVisionOCR()`；未修正或 `canEdit` 为假时不得暴露 action。
- 结果行原有定位 label/value/hint、稳定 `image-review-row-*` focus identity、可见“恢复 Vision OCR”按钮及其 `modificationUnavailableHint` 必须保持；改动不得新增 Store／持久化或改变 OCR、翻译、renderer/export、探针、Koharu、metrics、`output`。
- 合同接在 v3.140 后进入 UI/full fail-fast。候选 exact-SHA full `31151758844`（`3a98ecb36bcfef8dfc77823b0eae26b06f0980bd`）Xcode/JUnit `10/10` 成功；PR #205 fast `31152271664`、merge fast `31152319773` 复用候选 full，Xcode/UI/Speech skipped，JUnit `10/10`。探针默认 `probe_mode=skip`，readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不声称 OCR、翻译、识别或 Koharu 质量提升。

### v3.140 普通图片 OCR 结果行 VoiceOver edit action 合同

- `scripts/test-v3140-image-review-row-edit-action-contract.py` 必须验证 `ImageTranslationBlockRow` 在 `canEdit` 为真时通过 View-only modifier 暴露同名“修正识别文字” VoiceOver action，并直接复用既有 `edit()`；`canEdit` 为假时不得暴露 action。
- 结果行原有定位 label/value/hint、稳定 `image-review-row-*` focus identity、可见修正按钮及其 `modificationUnavailableHint` 必须保持；改动不得新增 Store／持久化或改变 OCR、翻译、renderer/export、探针、Koharu、metrics、`output`。
- 合同接在 v3.139 后进入 UI/full fail-fast。候选 exact-SHA full `31150859808`（`9571f142b35193cc86151b4e2971ccd6becfafbc`）Xcode/JUnit `10/10` 成功；PR #204 fast `31151298078`、merge fast `31151339355` 复用候选 full，Xcode/UI/Speech skipped，JUnit `10/10`。探针默认 `probe_mode=skip`，readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不声称 OCR、翻译、识别或 Koharu 质量提升。

### v3.139 图片局部放大 VoiceOver navigation action 合同

- `scripts/test-v3139-image-focus-navigation-action-contract.py` 必须验证 `ImageTranslationFocusPreview` 在 `canSelectPrevious`／`canSelectNext` 对应为真时通过 View-only modifier 暴露同名“上一个文字块”／“下一个文字块” VoiceOver action，并直接复用既有 `selectPrevious()`／`selectNext()`；对应邻居不存在时不得暴露该 action。
- 稳定的局部预览 label/value/hint、focus identity、当前位置 value、可见导航按钮与首尾 disabled hint 必须保持；改动不得新增 Store／持久化或改变筛选、选择、OCR、翻译、renderer/export、探针、Koharu、metrics、`output`。
- 合同接在 v3.138 后进入 UI/full fail-fast。候选 exact-SHA full `31149836170`（`044e137c1fae3ca08bccbfd2ab37422bdce95c40`）Xcode/JUnit `10/10` 成功；PR #203 fast `31150269494`、merge fast `31150318388` 复用候选 full，Xcode skipped，JUnit `10/10`。探针默认 `probe_mode=skip`，readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不声称 OCR、翻译、识别或 Koharu 质量提升。

### v3.138 图片局部放大 VoiceOver review action 合同

- `scripts/test-v3138-image-focus-review-action-contract.py` 必须验证 `ImageTranslationFocusPreview` 在 `isReviewRequired && canReview` 时通过 View-only modifier 暴露与可见按钮同名的“完成并继续复查／重新加入待复查” VoiceOver action，并直接复用既有 `toggleReviewCompletion()`；不需要复查或 `canReview` 为假时不得暴露该 action，父级 hint 必须说明现有 `reviewUnavailableHint`。
- 稳定的局部预览 label/value/hint、close/edit action、focus identity、可见复查按钮和 Store 复查门控保持；改动不得新增 Store／持久化或改变 OCR、翻译、renderer/export、探针、Koharu、metrics、`output`。
- 合同接在 v3.137 后进入 UI/full fail-fast。候选 exact-SHA full `31148861374`（`52e78935232cff22ef4bb45285a45218e6bd1b85`）Xcode/JUnit `10/10` 成功；PR #202 fast `31149234166`、merge fast `31149285259` 复用候选 full，Xcode skipped，JUnit `10/10`。探针默认 `probe_mode=skip`，readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不声称 OCR、翻译、识别或 Koharu 质量提升。

### v3.137 图片局部放大 VoiceOver edit action 合同

- `scripts/test-v3137-image-focus-edit-action-contract.py` 必须验证 `ImageTranslationFocusPreview` 在 `canEdit` 为真时通过 View-only modifier 暴露同名“修正识别文字” VoiceOver action，并直接复用既有 `edit()`；`canEdit` 为假时不得暴露该 action，父级 hint 必须说明现有 `modificationUnavailableHint`。
- 稳定的局部预览 label/value/hint、close action、focus identity、可见修正按钮和 OCR 修正 sheet 入口必须保持；改动不得新增 Store／持久化或改变 OCR、翻译、renderer/export、探针、Koharu、metrics、`output`。
- 合同接在 v3.136 后进入 UI/full fail-fast。候选 exact-SHA full `31147358078`（`46f617f8ce9a78628c4bdef54a800e4a4dc4e5a3`）Xcode/JUnit `10/10` 成功；PR #201 fast `31147793085`、merge fast `31147924273` 复用候选 full，Xcode skipped，JUnit `10/10`。探针默认 `probe_mode=skip`，readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不声称 OCR、翻译、识别或 Koharu 质量提升。

### v3.136 图片局部放大 VoiceOver close action 合同

- `scripts/test-v3136-image-focus-close-action-contract.py` 必须验证 `ImageTranslationFocusPreview` 的父容器提供同名“关闭局部放大” action 且直接复用既有 `close()`；可见关闭按钮 hint 必须说明返回当前文字块结果行。
- 稳定的 focus identity、label/value/hint 与 `ImageTranslationPanel.closeImageTranslationFocusPreview()` 的清除选中／回焦点路径必须保持；改动只能是 View 私有 accessibility 语义，不得新增 Store／持久化或改变 OCR、翻译、renderer/export、探针、Koharu、metrics、`output`。
- 合同接在 v3.135 后进入 UI/full fail-fast。候选 exact-SHA full `31144595687`（`0c4bddf96354989d9d2efc445987de3e8a3eafb4`）Xcode/JUnit `10/10` 成功；PR #200 fast `31144958126`、merge fast `31144998556` 复用候选 full，Xcode skipped，JUnit `10/10`。探针默认 `probe_mode=skip`，readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不声称 OCR、翻译、识别或 Koharu 质量提升。

### v3.135 图片预览状态 VoiceOver hint 合同

- `scripts/test-v3135-image-preview-status-hint-contract.py` 必须验证 `ImageTranslationPreview` 的预览状态容器同时提供动态 label/value/hint 与稳定 focus：失败当前 revision 时说明可执行“重试预览”且只重建屏幕预览、不重新识别或翻译；loading 时说明预览生成中、完成后可定位文字块和失败恢复边界。
- hint 必须保持 View 私有并复用既有 `previewFailedForCurrentRevision`，不得新增 Store／持久化、OCR、翻译、renderer/export、probe、Koharu、metrics 或 `output` 路径；v3.134 的同名 VoiceOver retry action 与可见按钮边界继续有效。
- 合同接在 v3.134 后进入 UI/full fail-fast。候选 exact-SHA full `31143646549`（`728b96a06491f41f5a8809fc2649486bdae81444`）Xcode/JUnit `10/10` 成功；PR #199 fast `31144019839`、merge fast `31144057333` 复用候选 full，Xcode skipped，JUnit `10/10`。探针默认 `probe_mode=skip`，readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不声称 OCR、翻译、识别或 Koharu 质量提升。

### v3.134 图片预览失败状态 retry action 合同

- `scripts/test-v3134-image-preview-status-retry-action-contract.py` 必须验证 `ImageTranslationPreview` 的预览失败状态容器仅在 `previewFailedForCurrentRevision` 为真时附加同名“重试预览” VoiceOver action；action 必须复用既有 `retryPreview()`，并与可见 retry button 共用仅重建屏幕预览的边界。
- loading 状态不得暴露该 action；稳定 preview status focus、label、value、hint 必须保留。改动只能是 View 私有 accessibility 语义，不得新增 Store／持久化／OCR／翻译／renderer/export／probe／Koharu／metrics／output 路径。
- 合同接在 v3.133 后进入 UI/full fail-fast。候选 exact-SHA full `31142629553`（`94e26b435226a966a3c866fa222da92e7eff69c3`）Xcode/JUnit `10/10` 成功；PR #198 fast `31142975439`、merge fast `31143030561` 复用候选 full，Xcode skipped，JUnit `10/10`。探针默认 `probe_mode=skip`，readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不声称 OCR、翻译、识别或 Koharu 质量提升。

### v3.133 图片空预览与识别结果空态 VoiceOver 合同

- `scripts/test-v3133-image-empty-result-accessibility-context-contract.py` 必须验证 `ImageTranslationPreview` 无图片分支成为稳定 VoiceOver element，label/value/hint 分别说明“图片翻译预览”“当前没有图片”和从照片／文件开始本机 OCR、翻译与屏幕预览；`ImageTranslationPanel` 的空结果分支必须使用动态 `imageResultEmptyStateAccessibilityLabel`／`imageResultEmptyStateAccessibilityHint`，按 idle、载入／识别／翻译、完成和失败说明阶段、结果缺失和 `canRetryImageTranslation` 恢复边界。
- 该合同只允许 View 私有 accessibility 语义与既有 Store 状态读取，不得新增 Store／持久化、OCR、翻译、renderer/export、probe_report、Koharu active gate、metrics 或 `output` 路径。
- 合同接在 v3.132 后进入 UI/full fail-fast。候选 exact-SHA full `31140850232`（`a1bc1ba4a73d4337e83c2a99f911ce3f709dc207`）Xcode/JUnit `10/10` 成功；PR #197 fast `31141276534`、merge fast `31141320676` 复用候选 full，Xcode skipped，JUnit `10/10`。探针默认 `probe_mode=skip`，readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不声称 OCR、翻译、识别或 Koharu 质量提升。

### v3.132 图片已忽略文字块空态 action 合同

- `scripts/test-v3132-image-ignored-empty-state-action-contract.py` 必须验证当普通图片所有 OCR 文字块已被忽略时，空态提供 label/value/hint、稳定 `imageIgnoredBlocksEmptyAccessibilityFocusID`、同名 VoiceOver“恢复全部”action 和唯一可见 `恢复全部 N` 按钮；恢复仍受 `canModifyImageTranslation` 与导出重绘门控，部分忽略状态保留下方批量入口，避免重复显示。
- 最后一个 block 被忽略后，View 私有 sheet-dismissal focus handoff 必须指向该空态；终态空 blocks + translated + data + ignored snapshots 也必须保留该焦点上下文；不得新增 Store/持久化/OCR/翻译/探针/metrics/output。
- 历史 v3.330/v3.333/v3.335 合同允许额外合法 focus destination（至少两个），并继续锁定原有 row/completion handoff。
- 合同接在 v3.131 后进入 UI/full fail-fast。候选 exact-SHA full `31139110055`（`012f25ffd7edc4009b33c600bb57d0d6d65005c2`）Xcode/JUnit `10/10`；PR #196 fast `31139576598`、merge fast `31139633331` 复用候选 full，Xcode skipped，JUnit `10/10`。探针默认 `probe_mode=skip`，readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不声称 OCR、翻译、识别或 Koharu 质量提升。

### v3.131 图片已忽略文字块批量恢复合同

- `scripts/test-v3131-image-ignored-blocks-bulk-restore-contract.py` 必须验证已忽略 OCR 文字块区域提供带确认的可见 `AppSecondaryButton(title: "恢复全部 \(store.imageTranslationIgnoredBlocks.count)")`，并在恢复期间受 `canModifyImageTranslation` 锁定、读出具体禁用原因；revision 变化会关闭 stale confirmation。
- Store 的 `restoreAllIgnoredImageTranslationBlocks()` 必须只在 `.translated` 且无 correction 进行时恢复，按 `originalOrder` 还原快照，保留人工修正／Vision OCR 元数据，清除恢复块的复查完成状态，并一次性同步转录、作废旧导出后重新绘制；不得重新 OCR／翻译、读取 Koharu 或增加持久化字段。确认后 View 将筛选恢复为 `.all` 并把 VoiceOver 焦点交给首个恢复行。
- 合同接在 v3.130 后进入 UI/full fail-fast。候选 exact-SHA full `31090186819`（`26fc6bba61c277747673f9fb29e4a6e1eb849aaf`）Xcode/JUnit `10/10` 成功；PR #195 fast `31137606603`、merge fast `31137651196` 复用候选 full，Xcode skipped，JUnit `10/10`。探针默认 `probe_mode=skip`，readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不声称 OCR、翻译、识别或 Koharu 质量提升。

### v3.130 漫画诊断筛选空态恢复 action 合同

- `scripts/test-v3130-manga-diagnostic-filter-empty-action-contract.py` 必须验证已有 `mangaOverlayProbeReport` 与非空 blocks 在当前 `filteredProbeBlocks` 为空时，空态同时提供可见 `AppSecondaryButton(title: "显示全部诊断")` 与同名 VoiceOver action，保留 `diagnosticFilterEmptyAccessibilityFocusID` 和历史“切换到全部或其他诊断类别查看逐块报告”上下文。
- “显示全部诊断”必须只调用 View 私有 `showAllDiagnosticResults()`，将本地 `diagnosticFilter` 恢复为 `.all`，复用既有 `.onChange(of: diagnosticFilter)` 的展开重置和焦点路径；不得写 Store／持久化、重新运行探针、读取 ground truth 或改变 OCR、翻译、renderer/export、Koharu active gate。`mangaOverlayProbeBlocks.isEmpty` 的“本次探针未生成文字块”空态必须保持独立。
- 合同接在 v3.129 后进入 UI/full fail-fast。候选 exact-SHA full `31088767018`（`f3965b43c38b7682decec9aaf46d046cafc3f16f`）Xcode/JUnit `10/10` 成功；PR #194 fast `31089351045`、merge fast `31089424245` 复用候选 full，Xcode skipped，JUnit `10/10`。探针默认 `probe_mode=skip`，readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，真实 Koharu 四件套缺失，不声称 OCR、翻译、识别或 Koharu 质量提升。

### v3.129 图片复查筛选空态恢复 action 合同

- `scripts/test-v3129-image-review-filter-empty-action-contract.py` 必须验证低置信／方向待定／待复查筛选为空时，空态同时提供可见 `AppSecondaryButton(title: "显示全部结果")` 与同名 VoiceOver action，并保留 `reviewFilterEmptyAccessibilityFocusID`、当前筛选 value 与恢复提示。
- “显示全部结果”必须复用 View 私有 `showAllReviewResults()`，只调用既有 `prepareReviewFilterChange(to: .all, focusID: nil)`；不得写 Store／持久化、重新运行 OCR／翻译、调用探针或改变 renderer/export/Koharu active gate。已完成待复查块继续显示 v3.128 的“重新复查”上下文。
- 合同接入 UI/full fail-fast。候选 exact-SHA full `31087461275`（`b4617eacf4ff4ef0c7ccce847fe3742ff7002861`）Xcode/JUnit `10/10` 成功；PR #193 fast `31088057693`、merge fast `31088114103` 复用候选 full，Xcode skipped，JUnit `10/10`。探针默认 `probe_mode=skip`，readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，真实 Koharu 四件套缺失，不声称 OCR、翻译、识别或 Koharu 质量提升。

### v3.128 图片复查完成态 VoiceOver action 合同

- `scripts/test-v3128-image-review-completion-action-contract.py` 必须验证 `reviewFilter == .needsReview` 且 `reviewCompletedBlockCount > 0` 的完成空态成为单一 VoiceOver element，label 为“本次复查完成”，value 读出完成／总风险块数量与当前筛选，并保留稳定 `reviewCompletionAccessibilityFocusID`。
- 完成空态必须提供命名为“重新复查”的 VoiceOver action，直接复用既有 `restartReviewQueue()`；action 受 `canReviewImageTranslation` 与 Store 的 translated 状态门保护。该 View-only 合同不得新增 Store／持久化、OCR、翻译、renderer/export、probe_report 或 Koharu active gate 路径。
- 合同接在 v3.127 后进入 UI/full fail-fast。候选 exact-SHA full `31085406753`（`d31745f8461ec6eeee0e8ce75e5965874a10b7b7`）Xcode/JUnit `10/10` 成功；PR #192 fast `31085987796`、merge fast `31086053876` 复用候选 full，Xcode skipped，JUnit `10/10`。探针默认 `probe_mode=skip`，readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，真实 Koharu 四件套缺失，不声称 OCR、翻译、识别或 Koharu 质量提升。

### v3.127 图片失败状态直接 retry action 合同

- `scripts/test-v3127-image-failure-status-actions-contract.py` 必须验证图片状态行按现有状态显示优先级提供直接 VoiceOver action：`imageTranslationShareState == .failed` 时提供“重试分享”并复用 `shareResult()`；否则 `imageTranslationExportRenderState == .failed` 时提供“重试导出”并复用 `store.retryImageTranslationExportRender()`；只有两者都没有失败时才保留“重试当前图片”。
- 分享／导出失败的 VoiceOver hint 必须说明对应 action；action、优先级 helper 和 hint 必须保持 View 私有，不新增 Store／持久化，不改变 OCR、翻译、renderer/export、probe_report 或 Koharu active gate。
- 合同接在 v3.126 后进入 UI/full fail-fast，并沿用表达式长度安全的既有 UI 路由。候选 full `31084281958`（exact SHA `a7ef8ce984234bf4631f206186f70bbec3ff2b64`）Xcode/JUnit `10/10` 成功；PR #191 fast `31084713250`、merge fast `31084803922` 复用候选 full，Xcode skipped，JUnit `10/10`。探针默认 `probe_mode=skip`，readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，真实 Koharu 四件套缺失，不声称 OCR、翻译、识别或 Koharu 质量提升。

### v3.124 图片清空后空态焦点合同

- `scripts/test-v3124-image-clear-empty-focus-contract.py` 必须验证 `ImageTranslationPanel` 在 `imageTranslationRevision` 变化后，仅当 `store.imageTranslationData == nil` 且 `store.imageTranslationState == .idle` 时，通过既有 `moveReviewAccessibilityFocus` 将焦点交给稳定 `imageEmptyAccessibilityFocusID`；新图片 loading、recognizing 或 translating 不得抢走状态焦点。
- “等待图片”空态必须成为单一 VoiceOver 上下文，提供“当前没有图片” value 和从照片／文件开始本机 OCR 与翻译的下一步 hint，并使用同一 View 私有 focus identity；不得新增 Store／持久化、OCR、翻译、renderer/export、probe_report 或 Koharu active gate 路径。
- 合同接在 v3.123 后进入 UI/full fail-fast，CI 路由将 v3.124 纳入既有正则。候选 full `31080208334`（exact SHA `e02b7a6d2c0f41098eb2cf82e6aa97f9b40c1ff9`）Xcode/JUnit `10/10` 成功；PR #188 fast `31080768687`、merge fast `31080830286` 复用候选 full，Xcode skipped，JUnit `10/10`。探针默认 `probe_mode=skip`，readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，真实 Koharu 四件套缺失，不声称 OCR、翻译、识别或 Koharu 质量提升。

### v3.123 图片屏幕预览失败／重试状态焦点合同

- `scripts/test-v3123-image-preview-status-focus-contract.py` 必须验证 `ImageTranslationPanel` 为预览状态提供稳定 `imagePreviewStatusAccessibilityFocusID`，并把既有 `moveReviewAccessibilityFocus` 封装为 View 私有 `focusPreviewStatus` handoff 传入 `ImageTranslationPreview`。
- `ImageTranslationPreview` 的状态容器必须使用 `.accessibilityFocused`；预览生成失败时和 `retryPreview()` 开始 loading 时都必须调用 `focusPreviewStatus()`，让 VoiceOver 焦点连续落在失败／重试详情上。该状态、焦点 identity 和 closure 不得进入 Store／持久化，不得调用探针或改变 OCR、翻译、renderer/export、probe_report 或 Koharu active gate。
- 合同接在 v3.122 后进入 UI/full fail-fast；CI 路由将 v3.122/v3.123 纳入现有正则并保留顶层兼容标记。候选 full `31079060685`（exact SHA `92e68b60e74dd61fb471584bba9cf00bf1696868`）Xcode/JUnit `10/10` 成功；PR #187 fast `31079520917`、merge fast `31079590205` 复用候选 full，Xcode skipped，JUnit `10/10`。探针默认 `probe_mode=skip`，readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，真实 Koharu 四件套缺失，不声称 OCR、翻译、识别或 Koharu 质量提升。

### v3.122 图片 OCR 取消后状态焦点合同

- `scripts/test-v3122-image-cancel-status-focus-contract.py` 必须验证 `ImageTranslationPanel` 的状态监听接收 `oldState`，仅当 `.loading`、`.recognizing` 或 `.translating` 转为 `.idle` 时清除待终态焦点 revision，并通过既有 `moveReviewAccessibilityFocus(to: Self.imageTranslationStatusAccessibilityFocusID)` 将焦点交给图片翻译状态行。
- 初始 `.idle`、`.translated`、`.failed` 或清空引起的非运行中 `.idle` 不得抢焦点；`.translated`／`.failed` 的既有 revision-scoped 终态焦点路径必须继续保留。焦点、generation 和 pending revision 仍为 View 私有，不新增 Store／持久化、不改变 OCR、翻译、renderer/export、probe_report 或 Koharu active gate。
- 合同接在 v3.121 后进入 UI/full fail-fast。候选 full `31077891466`（exact SHA `9c0ed87838d7eb621fb762c67230df74321f5ab6`）Xcode/JUnit `10/10` 成功；PR #186 fast `31078311141`、merge fast `31078359581` 复用候选 full，Xcode skipped，JUnit `10/10`。探针默认 `probe_mode=skip`，readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不声称 OCR、翻译、识别或 Koharu 质量提升。

### v3.120 图片 OCR 待重试语言可操作焦点合同

- `scripts/test-v3120-image-retry-language-accessibility-action-contract.py` 必须验证 v3.119 聚焦的“重试语言已更新”状态提供命名为“重试当前图片”的 VoiceOver action；action 必须先检查 `store.canRetryImageTranslation`，再调用既有 `store.retryImageTranslation()`，不得创建新的 Store 状态或绕过 retry 生命周期。
- 状态行的 hint/value 必须继续说明待重试语言与重新识别／翻译边界；不可重试时 action 安全无效。合同接在 v3.119 后进入 UI/full fail-fast，不改变 Vision OCR、翻译、renderer/export、probe_report 或 Koharu active gate。
- 候选 full `31075361390`（exact SHA `25855f7e6b757c2ae901c794c56990215399cb68`）Xcode/JUnit `10/10` 成功；PR #184 fast `31075697828`、merge fast `31075745893` 复用候选 full，Xcode skipped，JUnit `10/10`。探针默认 `probe_mode=skip`，readiness 为 `manifestMissing / stopUntilArtifactsProvided`，真实 Koharu 四件套缺失，不得声称 OCR、翻译、识别或 Koharu 质量提升。

### v3.119 图片 OCR 待重试语言焦点合同

- `scripts/test-v3119-image-retry-language-focus-contract.py` 必须验证输入／目标语言实际改变并生成 `imageTranslationRetryLanguageSummary` 后，`ImageTranslationPanel` 将 VoiceOver 焦点交给稳定的“重试语言已更新”状态行；label/value/hint 必须说明下一次重试语言和重新识别／翻译边界，summary 未变化时不得抢焦点或调用重试。
- 焦点必须复用既有 `moveReviewAccessibilityFocus` 的 request generation 与 `imageTranslationRevision` guard，不新增 Store／持久化、不改变 Vision OCR、翻译、renderer/export、probe_report 或 Koharu active gate；合同接在 v3.118 后进入 UI/full fail-fast。
- 候选 full `31074379707`（exact SHA `5248bd705fc6c0d963146060917e2a6a94a6c421`）Xcode/JUnit `10/10` 成功；PR #183 fast `31074819588`、merge fast `31074863470` 复用候选 full，Xcode skipped，JUnit `10/10`。探针默认 `probe_mode=skip`，readiness 为 `manifestMissing / stopUntilArtifactsProvided`，真实 Koharu 四件套缺失，不得声称 OCR、翻译、识别或 Koharu 质量提升。

### v3.118 漫画探针阻断 readiness 焦点合同

- `scripts/test-v3118-manga-koharu-readiness-focus-contract.py` 必须验证漫画探针报告到达时，`stopUntilArtifactsProvided`、`stopUntilArtifactContractFixed` 或 `stopUntilRealDetectorSourceDeclared` 会优先把共享 generation focus 交给 `MangaKoharuArtifactReadinessSummary` 的稳定状态行；非阻断 readiness、筛选切换、空筛选和逐块展开继续沿用既有焦点路径。
- readiness summary 只注入现有 `@AccessibilityFocusState` binding 和稳定 View identity，不新增 Store／持久化、不重跑探针、不读取 ground truth，不改变 OCR、翻译、renderer/export、probe_report 或 Koharu active gate；v3.336 历史合同接受多行 initializer 的等价写法。
- 合同接在 v3.117 后进入 UI/full fail-fast。候选 full `31073337578`（exact SHA `067077bcb146e2e0c8bb2e066350cac2466b7460`）Xcode/JUnit `10/10` 成功；PR #182 fast `31073688262`、merge fast `31073828173` 均复用候选 full，Xcode skipped，JUnit `10/10`。探针默认 `probe_mode=skip`，readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，真实 Koharu 四件套缺失，不得声称 OCR、翻译、识别或 Koharu 质量提升。

### v3.117 漫画探针筛选展开状态 reset 合同

- `scripts/test-v3117-manga-diagnostic-filter-expansion-reset-contract.py` 必须验证诊断筛选变化先递增 `diagnosticExpansionResetID`，再触发共享 generation requester；筛选切换不能让旧 block 的展开详情或旧焦点上下文残留。
- reset 必须继续复用 `MangaProbeBlockRow` 的 suppression guard 收起详情且不直接写焦点；reset token、筛选状态与焦点仍为 View/report-only，不进入 Store／持久化、不重跑探针、不读取 ground truth，不改变 OCR、翻译、renderer/export、probe_report 或 Koharu active gate。
- 合同接在 v3.116 后进入 UI/full fail-fast。候选 full `31072107788`（exact SHA `4bda6f5a0ea20e7d8223546d0b380758d839c253`）Xcode/JUnit `10/10` 成功；PR #181 fast `31072405558`、merge fast `31072447592` 均复用候选 full，Xcode skipped，JUnit `10/10`。探针默认 `probe_mode=skip`，真实 Koharu 四件套仍缺失，不得声称 OCR、翻译、识别或 Koharu 质量提升。

### v3.116 漫画探针诊断焦点请求 generation 合同

- `scripts/test-v3116-manga-diagnostic-focus-generation-contract.py` 必须验证 `MangaProbeSection` 的筛选、报告终态和 `MangaProbeBlockRow` 展开／收起都通过同一个 View 私有 request generation；异步 `Task.yield()` 后只允许最新请求写入 `@AccessibilityFocusState`。
- 新探针进入 loading 时必须递增 generation 并清除旧焦点；逐块行不得直接绕过共享 requester 写焦点。generation、焦点 identity 和展开状态不得进入 Store／持久化、探针运行、ground truth 或 OCR／翻译／renderer/export；既有 v3.111–v3.115 合同继续通过。
- 合同接在 v3.115 后进入 UI/full fail-fast。候选 full `31071423891`（exact SHA `4788bb213eeff010775a35798dc6fb28aabb7c0c`）Xcode/JUnit `10/10` 成功；PR #180 fast `31071714254`、merge fast `31071752236` 均复用候选 full，Xcode skipped，JUnit `10/10`。探针默认 `probe_mode=skip`，真实 Koharu 四件套仍缺失，不得声称 OCR、翻译、识别或 Koharu 质量提升。

### v3.115 图片 OCR 焦点请求 generation 合同

- `scripts/test-v3115-image-focus-request-generation-contract.py` 必须验证普通图片 OCR 的 `moveReviewAccessibilityFocus` 为每次 handoff 递增 View 私有 request generation，并在异步 `Task.yield()` 后同时检查 generation 与 `imageTranslationRevision`；旧请求不得覆盖同 revision 内更新的筛选、定位、复查或关闭预览动作。
- revision 变化必须递增 generation、清除旧 accessibility focus；generation 不得进入 Store／持久化或改变 OCR、翻译、renderer/export、探针报告和 Koharu active gate。既有 v3.109–v3.112 图片焦点合同继续通过。
- 合同接在 v3.114 后进入 UI/full fail-fast。候选 full `31070650744` 与手动 full `31070655111`（exact SHA `50029c449f86fbf4f0d43e7e35967a0c1e0ec8ce`）Xcode/JUnit `10/10` 成功；PR #179 fast `31070940503`、merge fast `31070976672` 均复用候选 full，Xcode skipped，JUnit `10/10`。探针默认 probe_mode=skip，Koharu readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不得声称 OCR、翻译、识别或 Koharu 质量提升。

### v3.114 漫画诊断展开状态隔离合同

- `scripts/test-v3114-manga-diagnostic-expansion-state-contract.py` 必须验证新探针 loading 时递增 View 私有 expansion reset token，逐块行收起旧详情且抑制 reset 触发的旧 VoiceOver focus handoff；结果行 value/hint 必须读出详细诊断已展开／已收起及对应动作。
- reset token、展开状态和 suppression guard 不得进入 Store／持久化、探针运行、ground truth 或 OCR／翻译／renderer/export；既有 v3.113 展开后聚焦详情、收起后回到结果行合同继续通过。
- 合同接在 v3.113 后进入 UI/full fail-fast。候选 full `31069913494` 与手动 full `31069918901`（exact SHA `e62a168e57e2f2cbc6cb47b5a8c8dde571d73f42`）Xcode/JUnit `10/10` 成功；PR #178 fast `31070264175`、merge fast `31070323190` 均复用候选 full，Xcode skipped，JUnit `10/10`。探针默认 probe_mode=skip，Koharu readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不得声称 OCR、翻译、识别或 Koharu 质量提升。

### v3.113 漫画诊断展开焦点合同

- `scripts/test-v3113-manga-diagnostic-expansion-focus-contract.py` 必须验证 MangaProbeBlockRow 的 DisclosureGroup 展开后将 VoiceOver 焦点交给稳定的详细诊断容器，收起后回到原 block 结果行；详情保留 OCR、译文、失败原因、报告风险、下一步和 report-only 边界。
- 展开状态、detail focus identity、异步 Task.yield() handoff 和 collapse 回退只能存在于 View 私有状态；合同不得看到 Store、持久化、探针重跑、ground truth 或普通图片 OCR／翻译／renderer/export 改动。
- 合同接在 v3.112 后进入 UI/full fail-fast。候选 full `31068769954` 与手动 full `31068778764`（exact SHA `fd2cf8d32b9576dc2620ce3c281403421aa1ca02`）Xcode/JUnit `10/10` 成功；PR #177 fast `31069311041`、merge fast `31069349841` 均复用候选 full，Xcode skipped，JUnit `10/10`。探针默认 probe_mode=skip，Koharu readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不得声称 OCR、翻译、识别或 Koharu 质量提升。

### v3.112 图片 OCR 终态焦点合同

- `scripts/test-v3112-image-translation-terminal-focus-contract.py` 必须验证新的 `imageTranslationRevision` 进入 `.translated` 或 `.failed` 后，普通图片 OCR 有 blocks 时将 VoiceOver 焦点交给当前筛选首个结果行；无 blocks 时交给动态图片翻译状态行，并继续保留既有状态 value/hint。终态焦点必须经过 revision guard，旧任务不得在后续图片开始后抢回焦点。
- revision 变化时必须继续清除 `reviewFilter` 的程序化意图、选中 block、编辑/恢复 sheet 和旧 accessibility focus；新增 pending terminal revision 只能存在于 `ImageTranslationPanel` 的 `@State`，不得进入 Store／持久化或改变 OCR、翻译、renderer/export、探针报告、Koharu active gate、metrics 与 `output`。非新 revision 的人工修正、复查和导出重绘状态变化不得抢走既有焦点。
- 候选 full `31067968394`（exact SHA `a150982ab83dac47000bb6bce34caa9aa74ecf26`）、PR #176 fast `31068324104`、merge fast `31068365757` 均通过；候选 full 提供 Xcode/JUnit `10/10`，PR fast 复用候选 full 且不作为新的编译证据，merge fast 记录 `reusedFullValidationSha=a150982ab83dac47000bb6bce34caa9aa74ecf26`、`reusedFullValidationState=success` 和 `receiptPropagationAllowed=true`。本版默认 `probe_mode=skip`，不更新 `metrics/version_history.csv` 或仓库 `output/`；Koharu readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不得声称 OCR、翻译、识别或 Koharu 质量提升。

### v3.111 漫画探针报告终态焦点合同

- `scripts/test-v3111-manga-probe-terminal-focus-contract.py` 必须验证 Developer Console 在既有 `MangaOverlayProbeReport` 写入后让 VoiceOver 焦点回到当前报告：有 blocks 时聚焦当前筛选的首个结果行，没有 blocks 时聚焦带有 `test/1.png`、Output 清理和重试边界的“未生成逐块诊断”状态；筛选无结果时继续回到现有可操作筛选空态。
- 漫画探针进入 loading 时仍必须重置 View 私有诊断筛选并清除旧焦点；终态焦点只能存在于 `MangaProbeSection` 的 `@AccessibilityFocusState`，不得进入 Store／持久化，不得触发第二次探针或改变 OCR、翻译、renderer/export、probe_report、Koharu active gate、metrics 或 `output`。
- 候选 full `31067283530`（exact SHA `70222e95035c7cd5a71799735e11539f755b5d08`）、PR #175 fast `31067583454`、merge fast `31067629934` 均通过；候选 full 提供 Xcode/JUnit `10/10`，PR fast 复用候选 full 且不作为新的编译证据，merge fast 记录 `reusedFullValidationSha=70222e95035c7cd5a71799735e11539f755b5d08`、`reusedFullValidationState=success` 和 `receiptPropagationAllowed=true`。本版默认 `probe_mode=skip`，不更新 `metrics/version_history.csv` 或仓库 `output/`；Koharu readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不得声称 OCR、翻译、识别或 Koharu 质量提升。

### v3.110 图片 OCR 筛选焦点意图仲裁合同

- `scripts/test-v3110-image-filter-focus-intent-contract.py` 必须验证用户驱动的 `reviewFilter` 变化仍在有结果时聚焦 `visibleImageTranslationBlocks.first`，而程序化筛选变化通过 View 私有 `prepareReviewFilterChange(to:focusID:suppressResultFocus:)` 声明行／局部预览／完成态焦点；`clearHiddenReviewSelection()` 与空筛选／复查完成态回退必须继续执行。
- revision 重置必须清除待处理焦点意图和抑制标记；意图状态只能存在于 `ImageTranslationPanel` 的 `@State`，不得进入 Store／持久化、OCR、翻译、renderer/export、探针报告或 Koharu active gate。v3.15/v3.16/v3.17/v3.29/v3.81/v3.93 历史合同须接受该 helper 的等价语义。
- 候选 full `31066203170`（exact SHA `43e75f22be1f1acc55045942f9c617bb0e4675e9`）、PR #174 fast `31066589776`、merge fast `31066628727` 均通过；候选 full 提供 Xcode/JUnit `10/10`，PR fast 复用候选 full 且不作为新的编译证据，merge fast 记录 `reusedFullValidationSha=43e75f22be1f1acc55045942f9c617bb0e4675e9`、`reusedFullValidationState=success` 和 `receiptPropagationAllowed=true`。本版默认 `probe_mode=skip`，不更新 `metrics/version_history.csv` 或仓库 `output/`；Koharu readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不得声称 OCR、翻译、识别或 Koharu 质量提升。

### v3.109 图片 OCR 筛选结果焦点合同

- `scripts/test-v3109-image-filter-result-focus-contract.py` 必须验证普通图片 OCR 的 `reviewFilter` 变化在存在可见结果时将 VoiceOver 焦点交给 `visibleImageTranslationBlocks.first` 对应的结果行，并复用既有 `reviewRowAccessibilityFocusID` 与 revision-scoped `moveReviewAccessibilityFocus`；该焦点只属于 View，不改变图片选择、复查进度、Vision OCR、翻译、renderer/export、Store 或持久化。
- 筛选切换仍必须先保留 `clearHiddenReviewSelection()` 的隐藏选中清理，再执行首结果焦点，最后保留 v3.107 的空态/复查完成态回退；无结果时不得尝试访问首结果。新增合同接在 v3.108 后进入 UI/full fail-fast，历史 v3.108 及更早合同须继续接受后续正式 `3.x` 版本。
- 候选 full `31064198524`（exact SHA `b3a58afd...`）、PR #173 fast `31064487760`、merge fast `31064532453` 均已通过；候选 full 提供 Xcode/JUnit `10/10`，PR fast 复用候选 full，merge fast 必须记录 `reusedFullValidationSha=b3a58afd...`、`reusedFullValidationState=success` 和 `receiptPropagationAllowed=true`。本版默认 `probe_mode=skip`，不更新 `metrics/version_history.csv` 或仓库 `output/`；Koharu readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不得声称 OCR、翻译、识别或 Koharu 质量提升。

### v3.108 漫画诊断筛选结果焦点合同

- `scripts/test-v3108-manga-filter-result-focus-contract.py` 必须验证 Developer Console 漫画诊断筛选从空结果或其他筛选切换到有结果时，在主线程让渡后将 `AccessibilityFocusState` 交给 `filteredProbeBlocks[0]` 对应的结果行；结果行必须接收 View-only focus binding/id 并使用稳定 block identity。筛选无结果时仍必须复用 v3.107 的可操作空态焦点，焦点不得进入 Store／持久化、探针运行、OCR、翻译、renderer/export 或报告写入。
- 历史 v3.399 报告交接合同必须只约束当前 `MangaOverlayProbeReport` 已传入结果行，不得因新增 View-only 行上下文而绑定旧初始化器排版；本版新增合同接在 v3.107 后进入 UI/full fail-fast，并允许 v3.107 及更早合同继续接受后续正式 `3.x` 版本。
- 候选 full `31063355633`（exact SHA `c6bee294...`）、PR #172 fast `31063761078`、merge fast `31063805810` 均已通过；候选 full 提供 Xcode/JUnit `10/10`，PR fast 复用候选 full，merge fast 必须记录 `reusedFullValidationSha=c6bee294...`、`reusedFullValidationState=success` 和 `receiptPropagationAllowed=true`。本版默认 `probe_mode=skip`，不更新 `metrics/version_history.csv` 或仓库 `output/`；Koharu readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不得声称 OCR、翻译、识别或 Koharu 质量提升。

### v3.107 筛选空态 VoiceOver 焦点合同

- `scripts/test-v3107-filter-empty-state-focus-contract.py` 必须验证普通图片 OCR 与漫画诊断筛选无结果时的 accessibility focus identity、label/value/hint、`0 / 总数` 上下文和切换筛选恢复路径；图片筛选切换后必须清除隐藏选择并优先交接空态或复查完成态，漫画探针新运行／加载时必须清除旧诊断焦点。合同只允许 View 私有状态，不得新增 Store／持久化或改变 OCR、翻译、renderer/export、探针报告、Koharu gate、metrics 与 output；必须接在 v3.106 后进入 UI/full fail-fast。云端候选 full `31020576411`、PR fast `31062338507`、merge fast `31062372361` 均通过，探针默认 skip，真实 Koharu 四件套仍缺失。

### v3.106 筛选器 VoiceOver 数量上下文合同

- 普通图片 OCR 的 `识别结果筛选` Picker 必须用 View 私有 `reviewFilterAccessibilityValue` 读出当前类别、当前显示数量／总数量；存在风险块时还要读出本次复查已完成与剩余数量。该值必须复用现有 `visibleImageTranslationBlocks`、`reviewCompletedBlockCount` 和 `reviewRequiredBlocks`，不得新增 Store 状态或重新运行 OCR／翻译。
- Developer Console 的漫画探针筛选器必须用同一只读上下文读出当前类别、筛选结果数和总文字块数；继续保持只筛选逐块诊断结果、不修改 `probe_report`、普通图片 OCR、翻译或覆盖图。
- 新增 `scripts/test-v3106-filter-accessibility-context-contract.py`，接入 UI interaction/full fail-fast；历史 v3.92–v3.105 合同须继续接受后续正式 `3.x` 版本。该 View-only 改动不改变 renderer/export、Koharu active gate、metrics 或仓库 `output`。
- 候选 full `31017118790`（exact SHA `fd0eef26...`）、PR #170 fast `31017809552`、merge fast `31017909329` 均已通过；候选 full 提供 Xcode/JUnit `10/10`，PR/merge fast 复用成功 full receipt，默认 `probe_mode=skip`。真实 Koharu 四件套、Speech corpus 与真实竖排图片 corpus 仍缺失，不得声称 OCR、翻译、识别或 Koharu 质量提升。

### v3.105 Koharu 收敛总览快照合同

- `MangaProbeDiagnosticTriageSummary` 必须只读消费既有 `MangaKoharuArtifactConvergenceReport` 的开放／已闭环／要求停止工单、`workItemStatusBreakdown`、`blockPathCount`、`workItemLedgerCount`、`needsRealArtifactBlocks` 和真实外部工件边界；不得重跑探针、重新推导 OCR/翻译候选或修改报告。
- 收敛快照必须同时进入状态标题/tone、status detail、可复制 `diagnostic triage` summary 和 VoiceOver value；开放、停止、阻断或 report-only 状态不得显示为成功。该 View/report-only 改动不新增 Store／持久化、不读取 ground truth，不改变 OCR、翻译、renderer/export、普通图片 OCR、Koharu active gate、metrics 或 output。
- 新增 `scripts/test-v3105-koharu-convergence-overview-contract.py`，接入 UI interaction/full fail-fast，并要求 v3.104 及更早合同继续接受后续正式 `3.x` 版本。
- 候选 full `31015086472` 必须提供 exact SHA `5e6bee9f...`、Xcode receipt、JUnit `10/10` 与合同结果；PR #169 fast `31015765732` 可复用候选 full且不作为新的编译证据；merge fast `31015838087` 必须记录 `reusedFullValidationSha=5e6bee9f...`、`reusedFullValidationState=success` 和 `receiptPropagationAllowed=true`。本版默认 `probe_mode=skip`，不更新 `metrics/version_history.csv` 或仓库 `output/`；真实四件套、Speech corpus 与真实竖排图片 corpus 仍缺失，不得声称 OCR、翻译、识别或 Koharu 质量提升。

### v3.104 Koharu 收敛 block 上下文合同

- `MangaProbeBlockRow` 必须只读消费既有 `MangaKoharuArtifactConvergenceReport.blockPaths` 与 `workItemLedger`，显示 block 首阻断工件、结构瓶颈、真实工件等待、开放工单、状态和 CI-fast/full/外部工件执行边界；不得重跑探针、重新推导 OCR/翻译候选或修改报告。
- 同一收敛上下文必须进入 action summary、结果行可见文本和 VoiceOver；`diagnosticOnly`、`wouldChangeMainFlow` 或开放工单必须保持 warning/仅报告，不得显示为成功晋级。该 View/report-only 改动不新增 Store／持久化、不读取 ground truth，不改变 OCR、翻译、renderer/export、普通图片 OCR、Koharu active gate、metrics 或 output。
- 新增 `scripts/test-v3104-koharu-convergence-context-contract.py`，接入 UI interaction/full fail-fast，并要求 v3.103 及更早合同继续接受后续正式 `3.x` 版本。
- 候选 full `31013385953` 必须提供 exact SHA `1fc00152...`、Xcode receipt、JUnit `10/10` 与合同结果；PR #168 fast `31014071238` 可复用候选 full 且不作为新的编译证据；merge fast `31014141913` 必须记录 `reusedFullValidationSha=1fc00152...`、`reusedFullValidationState=success` 和 `receiptPropagationAllowed=true`。本版默认 `probe_mode=skip`，不更新 `metrics/version_history.csv` 或仓库 `output/`；真实四件套、Speech corpus 与真实竖排图片 corpus 仍缺失，不得声称 OCR、翻译、识别或 Koharu 质量提升。

### v3.103 Koharu 晋级边界上下文合同

- `MangaProbeDiagnosticTriageSummary` 必须只读消费既有 `koharuNativePromotionGateLiteReport`、`koharuNativeArtifactContractDryRunReport`、`koharuArtifactIdentityReconciliationReport` 与 `koharuArtifactConvergenceReport`，显示晋级 verdict、候选预览/active export 边界、真实工件与 CI manifest 身份对账、停止本地调参与未闭环工单；不得运行第二次探针、修改 Store、OCR、翻译、renderer/export 或 active 工件。
- 晋级边界必须同时进入状态标题/详情、可复制 `diagnostic triage` 摘要和 VoiceOver value/hint；缺失报告安全回退为未提供，report-only/dry-run 仍使用 warning，不得把 proxy 或 preview 误报为 active 晋级。
- 新增 `scripts/test-v3103-koharu-promotion-boundary-context-contract.py`，接入 UI interaction/full fail-fast，并要求 v3.102 及更早合同继续接受后续正式 `3.x` 版本。
- 候选 full `31011231211` 必须提供 exact SHA `4705641b...`、Xcode receipt、JUnit `10/10` 与合同结果；PR fast `31011777761` 可复用候选 full 且不作为新的编译证据；merge fast `31011846424` 必须记录 `reusedFullValidationSha=4705641b...`、`reusedFullValidationState=success` 和 `receiptPropagationAllowed=true`。本版默认 `probe_mode=skip`，不更新 `metrics/version_history.csv` 或仓库 `output/`；真实四件套、Speech corpus 与真实竖排图片 corpus 仍缺失，不得声称 OCR、翻译、识别或 Koharu 质量提升。

### v3.102 Koharu 逐块执行边界上下文合同

- `MangaProbeBlockRow` 必须只读消费现有 pipeline resolver、work-order router、external artifact request packet 与 native replay matrix 的 block 级字段，显示目标执行项、首阻断阶段/原因、预算与目标工件，以及 CI-fast、full probe、真实外部工件和 shadow-only 边界；不得重新运行 OCR/翻译、修改候选或执行报告动作。
- 执行边界、v3.101 诊断依据、v3.100 推荐下一步和真实 Koharu 工件门控必须进入同一视觉与 VoiceOver summary；必须保留 forbidden local actions、remaining blockers 和本版本不可晋级提示，未知字符串安全回退为空/原值。该上下文不新增 Store／持久化、不运行探针、不读取 ground truth、不改变 OCR、翻译 prompt/model、renderer/export、普通图片 OCR 或 active Koharu gate。
- 新增 `scripts/test-v3102-koharu-block-execution-boundary-contract.py`，接入 UI interaction/full fail-fast，并要求 v3.101 及更早合同继续接受后续正式 `3.x` 版本。
- 候选 full `31009117560` 必须提供 exact SHA、Xcode receipt、JUnit 与合同结果；PR fast `31009686004` 可复用候选 full 且不作为新的编译证据；merge fast `31009749466` 必须记录 `reusedFullValidationSha=ac5210b1...`、`reusedFullValidationState=success` 和 `receiptPropagationAllowed=true`。本版默认 `probe_mode=skip`，不更新 `metrics/version_history.csv` 或仓库 `output/`；真实四件套、Speech corpus 与真实竖排图片 corpus 仍缺失，不得声称 OCR、翻译、识别或 Koharu 质量提升。

### v3.101 Koharu 逐块诊断依据上下文合同

- `MangaProbeBlockRow` 必须只读消费现有 internal bottleneck、translation model-floor、render fit 和 artifact DAG 的 block 级字段，显示 OCR 字符损伤、气泡拆分/归属、模型底线、字号预算或首阻断阶段等诊断依据；不得重新运行 OCR/翻译或改变报告判定。
- 诊断依据、推荐下一步和真实 Koharu 工件门控必须进入同一视觉与 VoiceOver 上下文；未知字符串安全回退为原值，空 ledger 不得显示伪造的“依据”。该上下文不新增 Store／持久化、不运行探针、不读取 ground truth、不改变 OCR 候选、翻译 prompt/model、renderer/export、普通图片 OCR 或 active Koharu gate。
- 新增 `scripts/test-v3101-koharu-block-diagnostic-evidence-context-contract.py`，接入 UI interaction/full fail-fast，并要求 v3.100 及更早合同继续接受后续正式 `3.x` 版本。
- 候选 full `30993659770` 必须提供 exact SHA、Xcode receipt、JUnit 与合同结果；PR fast `30994207268` 可复用候选 full 且不作为新的编译证据；merge fast `30994272480` 必须记录 `reusedFullValidationSha=69de7d96...`、`reusedFullValidationState=success` 和 `receiptPropagationAllowed=true`。本版默认 `probe_mode=skip`，不更新 `metrics/version_history.csv` 或仓库 `output/`；真实四件套、Speech corpus 与真实竖排图片 corpus 仍缺失，不得声称 OCR、翻译、识别或 Koharu 质量提升。

### v3.100 Koharu 逐块推荐下一步上下文合同

- `MangaProbeBlockRow` 必须只读消费当前 `MangaOverlayProbeReport` 的 `internalStructureBottleneckReport.blockSummaries`、`translationModelFloorComparisonReport.noisyBlockSummaries`、`koharuRenderSpriteFitPlannerReport.blockLedgers` 与 `koharuArtifactDAGReport.blockTraces`，按既有报告动作显示本块推荐下一步；不得重新推导 OCR 候选、翻译结果或生产布局。
- 逐块视觉建议、VoiceOver value/hint 必须共享该推荐动作；若存在 artifact DAG trace，必须同时说明真实 Koharu 工件门控。上下文仅为 report-only，不新增 Store／持久化、不运行第二次探针、不读取 ground truth、不改变 OCR、翻译 prompt/model、renderer/export、普通图片 OCR 或 active Koharu gate。
- 新增 `scripts/test-v3100-koharu-block-next-action-context-contract.py`，接入 UI interaction/full fail-fast，并要求历史 v3.99 及更早合同继续接受后续正式 `3.x` 版本。
- 候选 full `30992318412` 必须提供 exact SHA、Xcode receipt、JUnit 与合同结果；PR fast `30992932438` 可复用候选 full 且不作为新的编译证据；merge fast `30993004271` 必须记录 `reusedFullValidationSha=1009b4cb...`、`reusedFullValidationState=success` 和 `receiptPropagationAllowed=true`。本版默认 `probe_mode=skip`，不更新 `metrics/version_history.csv` 或仓库 `output/`；真实四件套、Speech corpus 与真实竖排图片 corpus 仍缺失，不得声称 OCR、翻译、识别或 Koharu 质量提升。

### v3.99 Koharu 逐块风险上下文合同

- `MangaProbeSection` 将当前 `MangaOverlayProbeReport` 传给每个 `MangaProbeBlockRow`；逐块行只读复用 `mangaProbeOCRRiskBlockSet`、`mangaProbeTranslationRiskBlockSet` 和 `mangaProbeRenderRiskBlockSet`，显示 OCR／翻译／布局风险标签。
- 视觉标签、VoiceOver value/hint 必须消费同一 `reportRiskSummary`，且没有报告时安全回退为“无额外风险”；该上下文不新增 Store／持久化、不运行探针、不读取 ground truth、不改变 OCR 候选、翻译 prompt/model、renderer/export 或 active Koharu gate。
- 新增 `scripts/test-v399-koharu-block-risk-context-contract.py`，接入 UI interaction/full fail-fast；候选 full/PR fast/merge fast 必须核对 exact SHA、manifest、JUnit 与 Xcode receipt，PR/merge fast 不作为新的编译证据。
- v3.99 默认 `probe_mode=skip`，不更新 `metrics/version_history.csv` 或仓库 `output/`；真实 Koharu 四件套、Speech corpus 与真实竖排图片 corpus 仍缺失，不得声称 OCR、翻译、识别或 Koharu 质量提升。

### v3.98 Koharu OCR/翻译诊断风险并集合合同

- `MangaProbeDiagnosticFilter.ocr` 与 `MangaProbeDiagnosticTriageSummary.ocrBlocks` 必须共享 `mangaProbeOCRRiskBlockSet`，并集既有 `diagnostics.likelyOCRIssueBlocks`、`translationUsableButOCRSuspectBlocks`、model-floor 的 `noisyOCRSuspectBlocks` 和 `ocrInputSuspect` block category。
- `MangaProbeDiagnosticFilter.translation` 与 `MangaProbeDiagnosticTriageSummary.translationBlocks` 必须共享 `mangaProbeTranslationRiskBlockSet`，并集既有 `diagnostics.translationLanguageQualityFailedBlocks`、model-floor 的 `noisyModelFloorBlocks`/`noisyTranslationLanguageQualityBlocks` 和 `modelOutputFailure`/`translationLanguageQualityFailure` category。
- 两个集合只能只读消费 `MangaOverlayProbeReport`，不得新增 Store／持久化、调用探针、读取 ground truth、修改 OCR 候选、翻译 prompt/model、生产 renderer/export 或 active Koharu gate；新增 `scripts/test-v398-koharu-diagnostic-risk-union-contract.py` 并接入 UI/full fail-fast。
- 候选 full/PR fast/merge fast 必须核对 exact SHA、manifest、JUnit 与 Xcode receipt；本版默认 `probe_mode=skip`，真实四件套仍为 `manifestMissing / stopUntilArtifactsProvided`，不得声称 OCR、翻译、识别或 Koharu 质量提升。

### v3.97 Koharu 布局风险分流合同

- 漫画探针 `MangaProbeDiagnosticFilter.render` 与 `MangaProbeDiagnosticTriageSummary.renderBlocks` 必须共享一个只读 risk set，至少合并既有顶层 diagnostics、fit planner 的 `fontBudgetRiskBlocks`、`renderMinFontSizeReachedBlocks`、`spriteContainmentRiskBlocks`、`siblingOverlapRiskBlocks`、`failureOverlayRiskBlocks`，以及 render-lock 的 `renderIssueBlocks`、min-font 和 truncation blocks。
- 该集合只消费 `MangaOverlayProbeReport` 已有 report-only 字段；不得新增 Store／持久化、调用漫画探针、读取 ground truth、修改 OCR 候选、翻译 prompt/model、生产 renderer/export 或 active Koharu gate。
- 新增 `scripts/test-v397-koharu-layout-triage-contract.py`，接入 UI interaction/full fail-fast，并允许后续正式 `3.x` 版本；v3.95 空 blocks 和 v3.96 readiness tone 合同继续保留。
- ci-fast 观察到 10 个 font-budget tight、7 个 sprite-containment、6 个 sibling-overlap 风险；候选 full/PR fast/merge fast 必须核对 exact SHA、manifest、Xcode receipt 和 JUnit，默认 probe skip，不得声称 OCR、翻译、识别或 Koharu 质量提升。

### v3.96 Koharu readiness 分流状态色合同

- `MangaProbeDiagnosticTriageSummary` 必须先判断既有 `artifactBlocked`：阻断时固定使用 warning；只有 readiness 不阻断且 `report.overallPassed` 时才使用 success，避免缺少真实 Koharu 四件套时把 shadow OCR 门控显示为成功。
- 该合同只检查 View 私有、只读的状态色优先级，不得新增 Store／持久化、调用漫画探针、读取 ground truth 或改变 OCR、翻译、renderer/export、active artifact gate。
- 新增 `scripts/test-v396-koharu-triage-tone-contract.py`，接入 UI interaction/full fail-fast，并允许后续正式 `3.x` 版本；v3.95 空 blocks 合同继续保留。
- 候选 full/PR fast/merge fast 必须核对 exact SHA、manifest、Xcode receipt 和 JUnit；本版默认 `probe_mode=skip`，readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不得声称 OCR、翻译、识别或 Koharu 质量提升。

### v3.95 漫画探针空 blocks 状态合同

- 当 Developer Console 已有漫画探针报告但 `mangaOverlayProbeBlocks` 为空时，必须显示明确的“本次探针未生成文字块”空态与 warning 状态行；不得显示“当前诊断筛选没有结果”或无意义的诊断筛选器。
- 空 blocks 状态的 VoiceOver label/value/hint 必须解释没有可展示的逐块 OCR 结果，并说明重试只针对 bundle 内 `test/1.png` 与 App 沙盒 `Output` 诊断；不得新增 Store／持久化、第二次探针或 ground-truth 读取。
- 有 blocks 时既有全部／失败／OCR／翻译／布局筛选和逐块诊断行必须保持；新增 `scripts/test-v395-manga-probe-empty-state-contract.py`，接入 UI interaction/full fail-fast，并允许后续正式 `3.x` 版本。
- 候选 full/PR fast/merge fast 必须核对 exact SHA、manifest、Xcode receipt 和 JUnit；本版默认 `probe_mode=skip`，Koharu readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不得声称 OCR、翻译、识别或 Koharu 质量提升。

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
