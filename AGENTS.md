# AGENTS.md

v3.132 让普通图片 OCR 在所有文字块都被忽略时提供可操作的空态：空态成为稳定 VoiceOver 上下文，读出忽略数量与恢复边界，并提供同名“恢复全部” action；同一状态只显示一个受 `canModifyImageTranslation`／导出重绘门控的可见恢复按钮，部分忽略状态仍保留下方批量入口。最后一个 block 被忽略后，View 私有焦点在 sheet 收起后交给该空态，终态也保留空态上下文；新增 `scripts/test-v3132-image-ignored-empty-state-action-contract.py`，历史 v3.330/v3.333/v3.335 合同允许这条额外合法焦点目的地。候选 full `31139110055`、PR #196 fast `31139576598`、merge fast `31139633331` 均通过；候选 SHA `012f25ffd7edc4009b33c600bb57d0d6d65005c2` Xcode/JUnit `10/10` 成功，merge SHA `df3f7ecbf59319a0c59d13164bb6b0f9cd8ab553` 复用候选 full receipt，readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不声称质量提升。
v3.131 让普通图片 OCR 的已忽略文字块区域提供带确认的“恢复全部”操作；按原始顺序恢复快照并保留修正／Vision OCR 元数据，单次重建转录和导出，受 `.translated`／导出重绘门控并把 VoiceOver 焦点交给首个恢复行。新增 `scripts/test-v3131-image-ignored-blocks-bulk-restore-contract.py`。候选 full `31090186819`、PR #195 fast `31137606603`、merge fast `31137651196` 均通过；候选 SHA `26fc6bba61c277747673f9fb29e4a6e1eb849aaf` Xcode/JUnit `10/10`，merge SHA `8514924340486fd86344298f3b9493540fe9ab4c` 复用 full receipt，readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不声称质量提升。
v3.130 让 Developer Console 漫画诊断筛选空态提供可见“显示全部诊断”按钮与同名 VoiceOver action；只改 View 私有 `diagnosticFilter`，保留无文字块探针空态。新增 `scripts/test-v3130-manga-diagnostic-filter-empty-action-contract.py`。候选 full `31088767018`、PR #194 fast `31089351045`、merge fast `31089424245` 均通过；候选 SHA `f3965b43c38b7682decec9aaf46d046cafc3f16f` Xcode/JUnit `10/10`，merge SHA `ed719558db8edca6aff02124517fb0035bc3c458` 复用 full receipt，readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不声称质量提升。
v3.129 让普通图片筛选空态提供可见“显示全部结果”按钮和同一 VoiceOver action，复用 `prepareReviewFilterChange(to: .all, focusID: nil)`；新增 `scripts/test-v3129-image-review-filter-empty-action-contract.py`。候选 full `31087461275`、PR #193 fast `31088057693`、merge fast `31088114103` 均通过；候选 SHA `b4617eacf4ff4ef0c7ccce847fe3742ff7002861` Xcode/JUnit `10/10`，merge SHA `5b2792d065fcb83ec10ccb4c2b55cb5ddab84bc8` 复用 full receipt，readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不声称质量提升。
v3.128 让普通图片复查完成空态成为稳定 VoiceOver 上下文，读出完成／总风险块与当前筛选并提供受 `canReviewImageTranslation` 保护的“重新复查”action，复用 `restartReviewQueue()`；新增 `scripts/test-v3128-image-review-completion-action-contract.py`。候选 full `31085406753`、PR #192 fast `31085987796`、merge fast `31086053876` 均通过；候选 SHA `d31745f8461ec6eeee0e8ce75e5965874a10b7b7` Xcode/JUnit `10/10`，merge SHA `14a11feff4413058f5c02348ce5d16485044702f` 复用 full receipt，readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不声称质量提升。
v3.127 让图片失败状态行按 share/export/image 优先级提供直接 VoiceOver retry action；新增 `scripts/test-v3127-image-failure-status-actions-contract.py`。候选 full `31084281958`、PR #191 fast `31084713250`、merge fast `31084803922` 均通过；候选 SHA `a7ef8ce984234bf4631f206186f70bbec3ff2b64` Xcode/JUnit `10/10`，merge SHA `03d5b82b97c102043a0c262775061401cc38ac8a` 复用 full receipt，readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不声称质量提升。
v3.126 补齐普通图片导出重绘／分享失败后的 VoiceOver 终态焦点：share/export state 进入 `.failed` 时回到图片状态行，运行中变化不抢焦点；新增 `scripts/test-v3126-image-export-share-failure-focus-contract.py`。候选 full `31082994159`、PR #190 fast `31083400009`、merge fast `31083557316` 均通过；候选 SHA `244f97435d340207c7684c3a2ab553b552b3b780` Xcode/JUnit `10/10`，merge SHA `e023e9c016c64a65596fe70151ad6f6a2d6615d9` 复用 full receipt，readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不声称质量提升。
v3.125 修复普通图片直接失败没有 VoiceOver 终态焦点：无新 revision 的文件选择／Pro 门控失败回到图片状态行，revision-scoped OCR／翻译失败保持原路径；新增 `scripts/test-v3125-image-direct-failure-focus-contract.py`。候选 full `31081494834`、PR #189 fast `31081976028`、merge fast `31082019649` 均通过；候选 SHA `1c068d538728a1195fdd08197f16f7e82d06dd4b` Xcode/JUnit `10/10`，merge SHA `9bd54490d09573d351c1e09da148393c3036a20` 复用 full receipt，readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不声称质量提升。
v3.124 修复普通图片清空后的 VoiceOver 焦点断点：仅当 revision 变化后图片数据为空且状态为 idle 时聚焦“等待图片”空态，新图片 loading 不抢焦点；新增 `scripts/test-v3124-image-clear-empty-focus-contract.py`。候选 full `31080208334`、PR #188 fast `31080768687`、merge fast `31080830286` 均通过；候选 SHA `e02b7a6d2c0f41098eb2cf82e6aa97f9b40c1ff9` Xcode/JUnit `10/10`，merge SHA `738f82384e027058ae0e53cad5f7842ce92a010f` 复用 full receipt，readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不声称质量提升。
v3.123 修复普通图片屏幕预览失败／重试后的 VoiceOver 焦点断点：预览状态使用稳定焦点 identity，失败和重试开始时回到状态行；新增 `scripts/test-v3123-image-preview-status-focus-contract.py`。候选 full `31079060685`、PR #187 fast `31079520917`、merge fast `31079590205` 均通过；候选 SHA `92e68b60e74dd61fb471584bba9cf00bf1696868` Xcode/JUnit `10/10`，merge SHA `6309370bc47974964a2aa181075469fb29e928e7` 复用 full receipt，readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不声称质量提升。
v3.122 修复普通图片读取／OCR／翻译取消后的 VoiceOver 焦点断点：仅在状态从 loading／recognizing／translating 转为 idle 时把焦点交给既有“图片翻译状态”行，初始 idle、成功、失败和清空不抢焦点。新增 `scripts/test-v3122-image-cancel-status-focus-contract.py`。候选 full `31077891466`、PR #186 fast `31078311141`、merge fast `31078359581` 均通过；候选 SHA `9c0ed87838d7eb621fb762c67230df74321f5ab6` Xcode/JUnit `10/10`，merge SHA `61401075429df063b7726037b81b91aade9178d3` 复用 full receipt，readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不声称质量提升。
v3.121 让普通图片 OCR 的失败／取消状态在源图片仍可用且没有待重试语言变更时提供受 `canRetryImageTranslation` 保护的“重试当前图片”VoiceOver action；待重试语言状态继续保留单独 action，避免重复入口。新增 `scripts/test-v3121-image-status-retry-accessibility-contract.py`。候选 full `31076710802`、PR #185 fast `31077094866`、merge fast `31077152440` 均通过；候选 SHA `9551c0c53bae0b8816d490a3da03c9472995e859` Xcode/JUnit `10/10`，merge SHA `16caff957c0252c2014750cc6c3d56dfa8463c29` 复用 full receipt，readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不声称质量提升。
v3.120 让普通图片 OCR 的待重试语言状态提供受 `canRetryImageTranslation` 保护的“重试当前图片”VoiceOver action，直接复用 Store retry；新增 `scripts/test-v3120-image-retry-language-accessibility-action-contract.py`。候选 full `31075361390`、PR #184 fast `31075697828`、merge fast `31075745893` 均通过；候选 SHA `25855f7e6b757c2ae901c794c56990215399cb68` Xcode/JUnit `10/10`，merge SHA `205e78e0f7dd39c51a9c8dbf93748c1a5ef0a090` 复用 full receipt，readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不声称质量提升。
v3.119 修复普通图片 OCR 失败／取消后的待重试语言提示 VoiceOver 焦点断点：输入或目标语言实际改变后，既有 retry-language summary 状态行获得 revision-scoped、generation 仲裁的焦点，并用 label/value/hint 说明下一次重试会使用的语言；不改变 OCR、翻译或 Store。新增 `scripts/test-v3119-image-retry-language-focus-contract.py`，候选 full `31074379707`、PR #183 fast `31074819588`、merge fast `31074863470` 均通过；候选 SHA `5248bd705fc6c0d963146060917e2a6a94a6c421` Xcode/JUnit `10/10`，merge SHA `de5ccebdeda7294a491183c53676e65caaaefb6a` 复用 full receipt，readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不声称质量提升。
v3.118 修复 Developer Console 漫画探针报告到达后的 VoiceOver 焦点优先级：既有 readiness report 阻断真实 Koharu 四件套、契约修正或真实 detector 来源声明时，先聚焦“Koharu 工件就绪状态”，筛选切换仍回到逐块结果。新增 `scripts/test-v3118-manga-koharu-readiness-focus-contract.py`，并让 v3.336 历史合同接受共享焦点 binding 的等价初始化。该 View/report-only 改动不新增 Store／持久化、不重跑探针、不读取 ground truth，不改变 OCR、翻译、renderer/export、probe_report、普通图片 OCR、Koharu active gate、metrics 或 `output`。候选 full `31073337578`、PR #182 fast `31073688262`、merge fast `31073828173` 均通过；候选 SHA `067077bcb146e2e0c8bb2e066350cac2466b7460` Xcode/JUnit `10/10` 成功，merge SHA `036bada7aebd70da50d6d31cc4e4da2cce4b8dda` 复用候选 full receipt，readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不声称质量提升。
v3.117 修复 Developer Console 漫画探针诊断筛选切换后的 stale 展开状态：筛选变化先递增 View 私有 expansion reset token，逐块行收起旧详情并抑制 reset 触发的焦点回抢，再由 generation requester 聚焦新筛选首项。新增 `scripts/test-v3117-manga-diagnostic-filter-expansion-reset-contract.py` 并接入 UI/full fail-fast。该 View/report-only 改动不新增 Store／持久化、不重跑探针、不读取 ground truth，不改变 OCR、翻译、renderer/export、probe_report、普通图片 OCR、Koharu active gate、metrics 或 `output`。候选 full `31072107788`、PR #181 fast `31072405558`、merge fast `31072447592` 均通过；候选 SHA `4bda6f5a0ea20e7d8223546d0b380758d839c253` 的 Xcode/JUnit `10/10` 成功，readiness 仍未提供真实工件，不声称质量提升。
v3.116 修复 Developer Console 漫画探针诊断焦点的多入口竞态：`MangaProbeSection` 统一用 View 私有 request generation 仲裁筛选、重跑终态和逐块展开／收起的 VoiceOver handoff，最新请求才会生效；新探针 loading 会使旧请求失效。新增 `scripts/test-v3116-manga-diagnostic-focus-generation-contract.py` 并接入 UI/full fail-fast，同时让 v3.113 历史合同接受等价共享 requester。该 View-only 改动不新增 Store／持久化、不重跑探针、不读取 ground truth，不改变 OCR、翻译、renderer/export、probe_report、普通图片 OCR、Koharu active gate、metrics 或 `output`。候选 full `31071423891`、PR #180 fast `31071714254`、merge fast `31071752236` 均通过；候选 SHA `4788bb213eeff010775a35798dc6fb28aabb7c0c` 的 Xcode/JUnit `10/10` 成功，readiness 仍未提供真实工件，不声称质量提升。
v3.115 修复普通图片 OCR VoiceOver 焦点请求竞态：View 私有 request generation 与 imageTranslationRevision 双重 guard 只允许最新焦点请求生效，新图片会使旧请求失效。新增 `scripts/test-v3115-image-focus-request-generation-contract.py` 并接入 UI/full fail-fast。该 View-only 改动不新增 Store／持久化、不改变 Vision OCR、翻译、renderer/export、探针报告、Koharu active gate、metrics 或 `output`。候选 full `31070650744` 与 `31070655111`、PR #179 fast `31070940503`、merge fast `31070976672` 均通过；候选 SHA `50029c449f86fbf4f0d43e7e35967a0c1e0ec8ce` 的 Xcode/JUnit `10/10` 成功，readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不声称质量提升。
v3.114 继续隔离漫画探针逐块诊断展开状态：新探针 loading 时由 View 私有 reset token 收起旧详情，并抑制 reset 触发的旧焦点 handoff；结果行 VoiceOver 明确展开／收起状态和下一步。新增 `scripts/test-v3114-manga-diagnostic-expansion-state-contract.py` 并接入 UI/full fail-fast。该 View-only 改动不新增 Store／持久化、不重跑探针、不读取 ground truth，不改变 OCR、翻译、renderer/export、普通图片 OCR、Koharu active gate、metrics 或 `output`。候选 full `31069913494` 与 `31069918901`、PR #178 fast `31070264175`、merge fast `31070323190` 均通过；候选 SHA `e62a168e57e2f2cbc6cb47b5a8c8dde571d73f42` 的 Xcode/JUnit `10/10` 成功，readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不声称质量提升。
v3.113 修复 Developer Console 漫画探针逐块诊断展开后的 VoiceOver 焦点断点：展开后聚焦稳定的“详细诊断”容器，收起后回到原文字块结果行；继续复用既有 report-only 风险、下一步和执行边界上下文。新增 `scripts/test-v3113-manga-diagnostic-expansion-focus-contract.py` 并接入 UI/full fail-fast。该 View-only 改动不新增 Store／持久化、不重跑探针、不读取 ground truth，不改变 OCR、翻译、renderer/export、普通图片 OCR、Koharu active gate、metrics 或 `output`。候选 full `31068769954` 与 `31068778764`、PR #177 fast `31069311041`、merge fast `31069349841` 均通过；候选 SHA `fd2cf8d32b9576dc2620ce3c281403421aa1ca02` 的 Xcode/JUnit `10/10` 成功，readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不声称质量提升。
v3.112 修复普通图片 OCR 新图／重试终态的 VoiceOver 焦点断点：新的 `imageTranslationRevision` 进入 `.translated` 或 `.failed` 后，有 blocks 时聚焦当前筛选的首个 OCR 结果，没有 blocks 时聚焦动态图片状态行；revision guard 阻止旧任务抢回焦点。既有筛选、选中项、修正 sheet 和复查焦点边界保持不变。新增 `scripts/test-v3112-image-translation-terminal-focus-contract.py` 并接入 UI/full fail-fast。该 View-only 改动不新增 Store／持久化、不改变 Vision OCR、翻译、renderer/export、探针报告、Koharu active gate、metrics 或 `output`。候选 full `31067968394`、PR #176 fast `31068324104`、merge fast `31068365757` 均通过；候选 SHA `a150982ab83dac47000bb6bce34caa9aa74ecf26` 的 Xcode/JUnit `10/10` 成功，merge SHA `f467a72a3de9d5ab6e876a51e228e19e037f4174` 复用候选 full receipt，探针默认 skip，readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不声称质量提升。
v3.111 修复 Developer Console 漫画探针重跑后的 VoiceOver 焦点断点：新报告有 blocks 时聚焦当前筛选的首个诊断结果，没有 blocks 时聚焦“未生成逐块诊断”并保留 test/1.png、Output 清理与重试边界；loading 会先清除旧诊断焦点。新增 `scripts/test-v3111-manga-probe-terminal-focus-contract.py` 并接入 UI/full fail-fast。该 View-only 改动不新增 Store／持久化、不重新运行探针、不改变 OCR、翻译、renderer/export、探针报告、Koharu active gate、metrics 或 `output`。候选 full `31067283530`、PR #175 fast `31067583454`、merge fast `31067629934` 均通过；候选 SHA `70222e95035c7cd5a71799735e11539f755b5d08` 的 Xcode/JUnit `10/10` 成功，merge SHA `9a28692cebf3360ca00b5e0b7f77463f103bdaa2` 复用候选 full receipt，探针默认 skip，readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不声称质量提升。
v3.110 修正普通图片 OCR 筛选焦点的意图竞争：用户切换筛选时仍聚焦第一个可见结果行；开始／重启复查、恢复忽略 block、预览直接选中和完成／撤销复查的程序化筛选变化保留明确的行／预览／完成态焦点，revision 重置清除旧意图并保留空态回退。新增 `scripts/test-v3110-image-filter-focus-intent-contract.py`，并同步 v3.15/v3.16/v3.17/v3.29/v3.81/v3.93 历史合同接受 helper。候选 full `31066203170`、PR #174 fast `31066589776`、merge fast `31066628727` 均通过；候选 SHA `43e75f22be1f1acc55045942f9c617bb0e4675e9` 的 Xcode/JUnit `10/10` 成功，merge SHA `08577f31c3dcd3da09ef64c6d9aa050e8d639794` 复用候选 full receipt，探针默认 skip，readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不声称质量提升。
v3.109 让普通图片 OCR 的识别结果筛选在切换类别后将 VoiceOver 焦点交给第一个可见 OCR 结果行；继续保留隐藏选中项清理、revision-scoped 焦点和无结果空态回退，焦点仍为 View 私有。新增 `scripts/test-v3109-image-filter-result-focus-contract.py`。候选 full `31064198524`、PR #173 fast `31064487760`、merge fast `31064532453` 均通过；探针默认 skip，readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不声称质量提升。

v3.108 让 Developer Console 漫画诊断筛选在切换到有结果的类别后，将 VoiceOver 焦点交给第一个可见诊断结果行；筛选仍只读既有报告，空筛选继续交给可操作空态，焦点 identity 保持 View 私有。新增 `scripts/test-v3108-manga-filter-result-focus-contract.py`，历史 v3.399 报告交接合同改为接受额外 View-only 行上下文。候选 full `31063355633`、PR #172 fast `31063761078`、merge fast `31063805810` 均通过；候选 SHA `c6bee294a7a5e59b51e39aa3b27cc09c5a913616` 的 Xcode/JUnit `10/10` 成功，merge SHA `859bac7b6e47f31ab3b14220737fe3d9c4048a07` 复用候选 full receipt，探针默认 skip，readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不声称质量提升。

v3.107 让普通图片 OCR 与 Developer Console 漫画探针筛选器在结果为空时把 VoiceOver 焦点交给可操作的空态：明确当前筛选、显示 `0 / 总数` 和恢复路径；图片筛选切换与漫画诊断筛选切换都保持 View-only，不新增 Store／持久化、不改变 OCR、翻译、renderer/export、探针报告、Koharu active gate、metrics 或 `output`。候选 full `31020576411`、PR #171 fast `31062338507`、merge fast `31062372361` 均通过；候选 full `f513bcd71f48ec34c2820941b86da7093bc86761` 的 Xcode/JUnit `10/10` 成功，merge SHA `0e7e692543aa34f8fb368cea766fb82391295929` 复用候选 full receipt，探针默认 skip，readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不声称质量提升。
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
v3.109 的普通图片 OCR 筛选焦点只使用 `AccessibilityFocusState`：筛选切换后从 `visibleImageTranslationBlocks` 取第一个 block，并通过既有 revision-scoped focus helper 聚焦其结果行；无结果时继续走 v3.107 空态，隐藏选中项清理和复查状态保持不变。该 View-only 改动不新增 Store／持久化、不改变 Vision OCR、翻译、renderer/export、Koharu active gate、metrics 或 `output`。候选 full `31064198524`、PR #173 fast `31064487760`、merge fast `31064532453` 均通过，不声称质量提升。

v3.108 的漫画诊断筛选结果焦点只使用 `AccessibilityFocusState`：筛选变为非空时在下一次主线程让渡后聚焦第一个可见 block，空筛选仍聚焦可操作空态；`MangaProbeBlockRow` 接收既有 report 与 View-only focus binding，不新增 Store／持久化、不运行探针、不改变 OCR、翻译、renderer/export、Koharu active gate、metrics 或 `output`。候选 full `31063355633`、PR #172 fast `31063761078`、merge fast `31063805810` 均通过，真实四件套仍缺失，不声称质量提升。

v3.106 让普通图片 OCR 与 Developer Console 漫画探针筛选器的 VoiceOver value 统一读出当前筛选类别、显示数量和总数量；图片筛选在有风险块时额外读出已复查／剩余数量。该 View-only 改动不新增 Store／持久化、不改变 OCR、翻译、renderer/export、探针报告或 Koharu active gate。候选 full `31017118790`、PR #170 fast `31017809552`、merge fast `31017909329` 均通过；候选 full Xcode/JUnit `10/10` 成功，PR/merge fast 复用 full receipt，探针默认 skip，真实四件套仍缺失，不声称质量提升。

v3.105 让 Developer Console 漫画探针诊断总览只读消费既有收敛报告的闭环快照：汇总开放／已闭环／要求停止工单、block path 与 work-item ledger 规模、状态 breakdown 及真实外部工件边界，并把同一快照用于状态 tone、可复制 summary 和 VoiceOver。存在开放或阻断收敛项时保持 warning/仅报告，不新增 Store／持久化、不运行第二次探针、不读取 ground truth，不改变 OCR、翻译、renderer/export、普通图片 OCR、Koharu active gate、metrics 或 `output`。候选 full `31015086472`、PR fast `31015765732`、merge fast `31015838087` 均通过；候选 full Xcode build 成功且 JUnit `10/10`，PR/merge fast 复用 full receipt，探针默认 skip，真实四件套仍缺失，不声称质量提升。

v3.104 让 Developer Console 漫画探针逐块结果只读消费既有 `MangaKoharuArtifactConvergenceReport` 的 block path、开放工单与执行边界：结果行、可复制 action summary 和 VoiceOver 共用首阻断、结构瓶颈、真实工件等待、工单状态及 CI-fast/full/外部工件边界；存在未闭环工单或 report-only 边界时统一显示 warning/仅报告，不再把收敛未完成误读为成功。该 View/report-only 改动不新增 Store／持久化、不运行第二次探针、不读取 ground truth，不改变 OCR、翻译、renderer/export、普通图片 OCR、Koharu active gate、metrics 或 `output`。候选 full `31013385953`、PR fast `31014071238`、merge fast `31014141913` 均通过；候选 full Xcode build 成功且 JUnit `10/10`，PR/merge fast 复用 full receipt，探针默认 skip，真实四件套仍缺失，不声称质量提升。

v3.103 让 Developer Console 漫画探针诊断总览只读消费既有 native promotion、artifact contract dry-run、artifact identity reconciliation 与 convergence 字段，显示晋级 verdict、dry-run/active export 边界、真实工件与 CI manifest 身份对账、停止本地调参与未闭环工单，并同步进入视觉、可复制摘要和 VoiceOver；不新增 Store／持久化、不运行探针或读取 ground truth，不改变 OCR、翻译、renderer/export、Koharu active gate、metrics 或 `output`。候选 full `31011231211`、PR fast `31011777761`、merge fast `31011846424` 均通过；探针默认 skip，真实四件套仍缺失，不声称质量提升。

v3.102 让 Developer Console 漫画探针逐块结果只读消费既有 pipeline resolver、work-order、外部工件请求包与 native replay 字段，显示执行项、首阻断、CI-fast/full/外部工件门、禁止本地调参与 shadow-only 边界，并同步进入视觉与 VoiceOver；不新增 Store／持久化、不运行探针或读取 ground truth，不改变 OCR、翻译、renderer/export、Koharu active gate、metrics 或 `output`。候选 full `31009117560`、PR fast `31009686004`、merge fast `31009749466` 均通过；探针默认 skip，真实四件套仍缺失，不声称质量提升。

v3.101 让 Developer Console 漫画探针逐块结果只读消费既有 bottleneck、model-floor、render-fit 与 artifact-DAG 字段，显示诊断依据并同步进入 VoiceOver；不新增 Store／持久化、不运行探针或读取 ground truth，不改变 OCR、翻译、renderer/export、Koharu active gate、metrics 或 `output`。候选 full `30993659770`、PR fast `30994207268`、merge fast `30994272480` 均通过；探针默认 skip，真实四件套仍缺失，不声称质量提升。

v3.100 让 Developer Console 漫画探针逐块结果只读消费既有 internal/floor/render/DAG report ledger，显示本块推荐下一步及真实 Koharu 工件门控上下文，并同步进入 VoiceOver；不新增 Store／持久化、不运行探针或读取 ground truth，不改变 OCR、翻译、renderer/export、Koharu active gate、metrics 或 `output`。候选 full `30992318412`、PR fast `30992932438`、merge fast `30993004271` 均通过；探针默认 skip，真实四件套仍缺失，不声称质量提升。

v3.99 让 Developer Console 漫画探针逐块结果接收当前只读 `MangaOverlayProbeReport`，显示共享 OCR／翻译／布局风险标签，并将同一上下文提供给 VoiceOver；不新增 Store／持久化、不运行探针或读取 ground truth，不改变 OCR、翻译、renderer/export、Koharu active gate、metrics 或 `output`。候选 full `30991030339`、PR fast `30991418709`、merge fast `30991478674` 均通过；探针默认 skip，真实四件套仍缺失，不声称质量提升。

AITRANS 是 SwiftUI iOS 本地 AI 翻译原型。当前重点是漫画截图 OCR、本地翻译、覆盖合成和探针诊断链路。

- 默认 `MockGemmaService` 用于 UI 和数据流冒烟。
- `Local` 模式通过 `GemmaLocalService` + `LlamaRuntime` + `llama.cpp` 加载 GGUF。
- 当前内置最小模型是 `Gemma 3 270M IT QAT Q4_0`，适合验证下载、加载、接口和闪退风险，不适合作为翻译质量基准。
- 更强小模型对比可以考虑 `Qwen2.5-0.5B-Instruct-GGUF q4_k_m`，但不要在没有任务要求时擅自更换模型。
- GGUF 不进仓库。云端手动探针从 Release `model-gemma-3-270m-it-qat-q4_0-v1` 下载并缓存 `gemma-3-270m-it-qat-Q4_0.gguf`，按 SHA256 校验后导入模拟器 App 沙盒。
- 当前正式版本号 `3.132`：普通图片 OCR 的 blocks 会在逐块翻译期间继续供用户查看、定位和局部预览，但所有会改变当前结果或复查进度的动作只在 `imageTranslationState == .translated` 开放。`ImageTranslationPanel` 的 `canModifyImageTranslation` 还会在导出重绘期保持禁用，统一保护 OCR 修正、Vision OCR 恢复、已忽略 block 恢复与旁贴／覆盖方式；`canReviewImageTranslation` 保护开始／继续／重启复查及行／局部预览的完成／撤销。Store 的 mark／reopen／reset 同样拒收未完成状态，成功 OCR 修正会先恢复 translated 再沿用既有自动复查，避免 blocks 在逐块翻译中已可见时提前写入会话进度。v3.42 在仍有实际 block 而操作被状态门锁住时显示 View 私有警示状态行；覆盖方式、开始／重启复查、局部预览与结果行的修正／恢复／复查及忽略 block 恢复，都会复用 `imageModificationUnavailableDetail` 或 `imageReviewUnavailableDetail` 作为 VoiceOver 的具体禁用原因。v3.43 继续保留局部预览前后按钮的 disabled 边界，并让可用状态读出“定位上一个／下一个文字块”、首尾状态读出“当前已是筛选结果中的第一个／最后一个文字块”；结果行主定位提示按 `isSelected` 在“取消此文字块在图片中的定位”和“在图片预览中定位此文字块”之间切换。v3.44 让同一对前后按钮再读出 `navigationPositionAccessibilityValue`：有位置时为“当前位置 (positionText)”（如 `1 / 3`），无位置时为“未显示筛选位置”，不新增 Store 状态。v3.45 让完整图片预览中的 OCR 覆盖块也复用结果行的定位提示：已定位时读出“取消此文字块在图片中的定位”，未定位时读出“在图片预览中定位此文字块”，保持图片入口和列表入口语义一致。v3.46 让图片预览加载与失败状态提供稳定的 VoiceOver label/value，重试提示明确只重建屏幕预览、不重新 OCR 或翻译。v3.47 让图片命令栏的照片／文件、取消、重试、重新识别、导出与清空操作提供作用域明确的 VoiceOver hint，照片选择器会按是否已有图片动态区分首次选择与替换；v3.48 让完整图片预览提供稳定的容器 label/value/hint，汇总识别块数量、待复查数量和当前定位位置，并把重复朗读的原始背景图设为无障碍隐藏；这些只是 View 语义，不新增 Store 或持久化状态。它覆盖 loading／recognizing／translating／failed 和导出重绘，并明确逐块翻译仍可查看／定位；本版不改变 Vision OCR、模型翻译、renderer/export、漫画探针、Koharu 主路径、ground truth、metrics 或 `output`，不能作为 OCR、翻译、识别或 Koharu 质量提升证据。v3.37–v3.40 的规范化无语义关闭、弃改保护、确认无误分流、键盘／滚动收起、保存期输入锁定和 revision-scoped 关闭后焦点交接继续保留。v3.36 的开发控制台 readiness 摘要仍只读已有报告；缺真实四件套时仍显示 `manifestMissing / stopUntilArtifactsProvided`。v3.26 CI receipt 传播规则不变，artifact 继续记录父 SHA、state 和元数据判定；传播路径不是新的 Swift/Xcode 编译证据。v3.49 让图片输入语言与目标语言菜单的 VoiceOver hint 按运行中、Pro 门槛、无图片、已完成和失败／取消重试状态分流：运行中明确需完成或取消，Pro 锁定说明不会污染文本页语言，已完成输入语言说明会重新识别和翻译、目标语言说明会重新翻译当前图片，失败／取消说明下一次重试使用新语言；选回当前内容语言会撤销待重试差异。v3.50 让照片与文件导入按钮在读取、OCR 或翻译进行中明确说明选择新图片会取消当前任务并开始新的本机 OCR 与翻译，同时保持有意设计的替换入口、Store run-id 隔离与现有 import controls 可用。v3.51 让图片状态行成为单一的 VoiceOver 状态元素，动态读出当前阶段、逐块进度和下一步操作，并区分载入／Vision OCR／翻译、导出重绘、分享准备、失败和完成状态。该改动只改善 View 语义，不新增 Store／持久化状态，也不改变 OCR、翻译、renderer/export、探针或质量基线。v3.52 让图片结果行的 VoiceOver value 在定位状态之外读出 OCR 置信度、低置信／方向待定、人工修正、复查进度和等待翻译，并继续沿用定位 hint；只改善 View 语义，不新增 Store／持久化或改变 OCR、翻译、renderer/export、探针和质量基线。v3.53 让已忽略 OCR 文字块恢复行成为稳定的 VoiceOver 上下文，读出不在图片预览／导出／转录、是否保留现有译文和恢复是否可用，同时保留恢复按钮的禁用原因与焦点交接；只改善 View 语义，不新增 Store／持久化或改变 OCR、翻译、renderer/export、探针和质量基线。v3.54 修复图片状态行 VoiceOver value 的实际实现回归：使用动态 `statusTitle`／`statusDetail` 插值，而不是字面量，保证当前阶段、逐块进度、失败、导出重绘和完成详情能被实时朗读；同步强化 v3.51 回归合同，仍不新增 Store／持久化或改变 OCR、翻译、renderer/export、探针和质量基线。v3.55 让开发控制台的 Koharu readiness 状态成为稳定的 VoiceOver 上下文，读出 verdict、缺失四件套、下一步和 shadow-only 边界；缺少工件时明确给出 `test/koharu_artifacts/` 与四个文件名。该改动只改善开发者操作与诊断可理解性，不新增 Store／持久化，不调用第二次探针，不改变 active artifact gate、普通图片 OCR、翻译、renderer/export、Koharu 主路径或质量基线。v3.56 让漫画覆盖翻译探针状态行成为单一、稳定的 VoiceOver 上下文，按载入、Vision OCR、翻译、绘制、完成和失败读出状态详情；运行按钮明确 bundle 内 `test/1.png`、Output 诊断文件和只影响漫画探针的边界。该改动只改善开发者操作语义，不新增 Store／持久化，不改变普通图片 OCR、翻译、renderer/export、Koharu 主路径或质量基线。v3.57 让开发控制台的漫画探针逐块结果成为稳定的 VoiceOver 诊断上下文，按 block index 读出 PASS/FAIL、OCR 原文、旋转角度、置信度、质量标签、译文与失败详情；展开提示明确只属于漫画探针，不改变普通图片 OCR、翻译或覆盖图。该改动只改善开发者操作语义，不新增 Store／持久化状态、不读取 ground truth 作为候选、不改变漫画探针诊断、renderer/export、Koharu 主路径或质量基线。v3.58 让图片复查结果行提供稳定的 VoiceOver label/value：label 明确“图片文字块 + OCR 原文”，value 在等待翻译时读出等待状态、完成后读出译文，并为空 OCR 提供稳定回退；只改善 View 语义，不新增 Store／持久化状态，不改变 Vision OCR、模型翻译、renderer/export、漫画探针、Koharu 主路径或质量基线。v3.59 让完整图片预览的覆盖文字块与图片复查结果行共用稳定的 VoiceOver label“图片文字块 + OCR 原文”，空 OCR 回退为“空”，并保留既有等待翻译／译文 value、定位 hint 和选中状态；该改动只改善 View 语义，不新增 Store／持久化状态，不改变选择、Vision OCR、模型翻译、renderer/export、漫画探针、Koharu 主路径或质量基线。 v3.60 让完整图片预览的覆盖文字块与图片复查结果行对齐 VoiceOver value：读出 OCR 置信度（clamp 到 0–100%）、人工修正、低置信／方向待定、待复查／本次已复查及等待翻译／译文；相邻与替换模式共用这套上下文，只改善 View 语义，不新增 Store／持久化状态，不改变选择、Vision OCR、模型翻译、renderer/export、漫画探针、Koharu 主路径或质量基线。 仓库尚无真实 Koharu 四件套、Speech 音频或真实竖排图片 corpus，不声称 OCR、翻译或识别质量提升。

- v3.81 结果行或完整图片覆盖块选中 OCR block 后，将 VoiceOver 焦点交给对应局部预览；取消定位时回到对应结果行。该 View-only handoff 只在 AccessibilityFocusState 中运行，不进入 Store、OCR、翻译或 renderer/export 链路。
- v3.82 修正漫画覆盖探针失败 fallback 的显式换行布局测量：`wrappedLines` 按段落保留显式换行和空行，使 fit plan 与实际绘制共享垂直预算；新增 `scripts/test-v382-manga-render-newline-contract.py`。该诊断性修复只影响漫画探针失败覆盖的布局可观测性，不改变 OCR 候选、翻译模型／prompt、ground truth、Koharu active artifact gate、普通图片 OCR 主路径、metrics 或 output，也不代表 OCR、翻译或 Koharu 质量提升。
- v3.83 让 `makeKoharuRenderSpriteFitPlannerReport` 复用 `wrappedLines` 的显式换行／空行预算，并把实际 `renderTextTruncated` 纳入失败 fallback 风险；新增 `scripts/test-v383-koharu-fit-budget-contract.py`。该 report-only 修复只校正 Koharu 诊断可观测性，不改变 OCR 候选、翻译模型／prompt、ground truth、生产 renderer/export、active artifact gate、普通图片 OCR、metrics 或 output，也不代表质量提升。full `30870546266`、同 SHA ci-fast `30870974176`、PR #147 fast 和 merge fast `30871766042` 均通过；block 5 的报告从旧误报 fit 变为 12 行 overflow/long-text risk，实际探针仍保留截断。
- v3.84 让 `makeKoharuRenderSpriteFitPlannerReport` 复用既有 `renderMinFontSizeReached` 证据：逐 block ledger、decision signal、汇总 `renderMinFontSizeReachedBlocks` 与 `G-render-sprite-fit-min-font-evidence` report-only gate 保持一致；新增 `scripts/test-v384-koharu-render-min-font-contract.py`，并同步 v3.82/v3.83 历史合同和 CI 路由接受后续正式版本。该诊断性改动不改变 OCR 候选、翻译模型／prompt、ground truth、生产 renderer/export、Koharu active artifact gate、普通图片 OCR、metrics 或 output，也不代表质量提升。full `30873895093`、同 SHA ci-fast `30874183417`、PR #148 fast `30874885165`、merge fast `30874929145` 均通过；探针报告只作为诊断证据，block 5 记录最小字号压力与实际截断。
- v3.85 让 `MangaKoharuRenderRegressionLockReport` 汇总既有 block/render lock 的 `renderMinFontSizeReached`，并把该信号写入每个 render-lock decision trace、`renderMinFontSizeReachedBlocks`、`G-render-min-font-evidence` report-only gate 和开发者摘要；新增 `scripts/test-v385-koharu-render-lock-min-font-contract.py`，同步历史 v3.82–v3.84 合同与 CI 路由接受后续正式版本。该诊断性改动不改变 OCR 候选、翻译模型／prompt、ground truth、生产 renderer/export、Koharu active artifact gate、普通图片 OCR、metrics 或 output，也不代表质量提升。full `30875436621`、同 SHA ci-fast `30875716372`、PR #149 fast `30876264990`、merge fast `30876301079` 均通过；block 5 的最小字号压力与实际截断仍只是诊断证据。
- v3.61 让图片复查结果行和完整图片预览的 VoiceOver 上下文消费既有 Vision OCR 方向证据：已判定的横排／竖排与有限方向置信度会进入 value，结果行显示已知方向，OCR 置信度显示安全夹到 0–100%；只改善 View 语义，不新增 Store／持久化状态，不改变 OCR、翻译、renderer/export、漫画探针、Koharu 主路径或质量基线。
- v3.62 让图片识别结果摘要复用既有 `ImageOCRResultSummary.horizontalBlockCount` 与 `verticalBlockCount`，在摘要中显示横排／竖排数量；不新增 Store／持久化状态，不重新运行 OCR／翻译，不改变 renderer/export、漫画探针、Koharu 主路径或质量基线。
- v3.63 让“识别结果”摘要成为单一 VoiceOver header，复用既有摘要 value，并按无图片、翻译未完成、没有待复查块和可复查状态给出下一步 hint；不新增 Store／持久化状态，不重新运行 OCR／翻译，不改变 renderer/export、漫画探针、Koharu 主路径或质量基线。
- v3.64 统一图片 OCR 置信度安全边界：`ImageOCRResultSummary`、布局引擎、结果行和覆盖层把非有限值回退为 0、越界值夹到 0–1；无效置信度继续进入低置信复查，不得污染平均值或触发百分比转换崩溃。该修复不改变 OCR 候选、翻译、renderer/export、漫画探针或 Koharu 主路径。
- v3.69 在图片结果行和完整图片预览的 VoiceOver 摘要中提前报告无效或过期 OCR 框的“定位不可用”数量；结果行保留 OCR 修正和切换文字块入口，并以位置不可用图标提供可见提示。该版本只消费 `NormalizedImageRect.normalizedToUnit()` 的既有边界，不新增 Store／持久化状态，不改变 Vision OCR、模型翻译、renderer/export、漫画探针、Koharu、ground truth、metrics 或 output；真实 Koharu 四件套、Speech corpus 与真实竖排图片 corpus 仍缺失，不声称 OCR、翻译、识别或 Koharu 质量提升。
- v3.70 让完整图片预览的 VoiceOver hint 按无效或过期 OCR 框数量分流：有效文字块才说明可打开局部放大，异常文字块明确局部预览不可用；保留 OCR 修正、切换文字块和既有状态门。该版本只消费同一 `NormalizedImageRect.normalizedToUnit()` 边界，不新增 Store／持久化状态，不改变 Vision OCR、模型翻译、renderer/export、漫画探针、Koharu、ground truth、metrics 或 output；真实 Koharu 四件套、Speech corpus 与真实竖排图片 corpus 仍缺失，不声称 OCR、翻译、识别或 Koharu 质量提升。
- v3.71 让开发控制台的 Koharu readiness 摘要显示坐标、mask payload、mask 拓扑和工件身份门控，并在 VoiceOver/可复制摘要中说明阻塞项与 CI 对账要求；只读既有 report，不创建或修改 active `test/koharu_artifacts`，不放宽 readiness gate，不改变普通图片 OCR、翻译、renderer/export、漫画探针或 Koharu 主路径。真实四件套、Speech corpus 与真实竖排图片 corpus 仍缺失，不声称 OCR、翻译、识别或 Koharu 质量提升。
- 当前 App bundle ID 是 `com.local.aitransform114`；云端探针必须从构建产物 `Info.plist` 动态读取，禁止在 workflow 再硬编码。
- 当前可信基线以 `update_log.md`、`metrics/version_history.csv`、最新 `output/probe_report.json` 和 `output/clean_text_diagnostic.json` 为准，不在本入口长篇复制指标。

- v3.65 让图片 OCR 修正 sheet 的低置信度提示复用 ImageOCRResultSummary.normalizedConfidence，非有限／越界值在百分比格式化前安全归一化；历史 v3.47–v3.64 图片合同同步接纳后续正式版本。该改动只改善 View 语义，不新增 Store／持久化状态，不改变 OCR、翻译、renderer/export、漫画探针或 Koharu 主路径。
- v3.66 对 Vision OCR bounding box 做有限、正面积、整矩形单位坐标归一化，布局引擎过滤 NaN/∞、零面积和完全越界 observation，避免异常 geometry 进入覆盖、定位或阅读排序；新增 geometry evaluator，历史 v3.47–v3.65 图片合同同步接纳后续正式版本。该安全边界不改变 OCR 候选、翻译、renderer/export、漫画探针或 Koharu 主路径。
- v3.67 将 finite／正面积／单位空间整矩形边界复用到 Codable `NormalizedImageRect` 的图片预览、局部定位和导出 renderer；旧会话或外部解码的异常框跳过显示/绘制，不新增 Store／持久化状态，不改变 OCR 候选、翻译、漫画探针或 Koharu 主路径。历史 v3.47–v3.66 图片合同同步接纳后续正式版本。
- v3.68 让无效或过期 OCR 框的局部放大明确显示“局部预览不可用”，不再把整图误作当前文字块；保留关闭、编辑 OCR 原文和切换文字块入口，并用 VoiceOver hint 说明边界。图片 OCR 修正对照仍可编辑，不新增 Store／持久化状态，不改变 Vision OCR、翻译、renderer/export、漫画探针、Koharu 主路径或质量基线。

v3.86 修正漫画探针 render-lock 输出工件 ledger 的时序误报：`probe_report.json` 在最终重写 `1_ocr_probe_text.txt` 前组装，现将两者标记为 planned final write，避免实际非空 OCR 文本被错误记录为 `presentButEmptyOrUnchecked`，并让 `coreOutputFilesNonEmpty` 与 `G-render-core-png-retained` 反映真实探针结果；失败的最终写入仍会中止成功报告持久化。新增 `scripts/test-v386-koharu-render-output-ledger-contract.py`，历史 v3.82–v3.85 合同同步接受后续正式版本。该 report-only 修复不改变 OCR 候选、翻译模型／prompt、ground truth、生产 renderer/export、普通图片 OCR、Koharu active artifact gate、metrics 或仓库 output，也不代表 OCR、翻译或 Koharu 质量提升。full `30876931497`、同 SHA ci-fast 探针 `30877262645`、PR #150 fast `30877905238`、merge fast `30877976728` 均通过；ci-fast 13 blocks 的 block 5 仍真实记录文字截断，active Koharu gate 仍为 `manifestMissing / stopUntilArtifactsProvided`。

v3.87 修正漫画探针 render-lock 输出检查的推荐动作：`plannedFinalReportWrite` 与 `plannedFinalOCRTextRewrite` 既然表示最终写入已计划且 `nonEmpty=true`，就必须显示 `keepReportOnly`；只有缺失或未检查输出才显示 `inspectRenderOutputExport`。新增 `scripts/test-v387-koharu-render-output-action-contract.py` 并接入 Koharu changed-file/full 静态路由。候选 full `30878519259`、同 SHA ci-fast `30878916261`、PR #151 fast `30879584339`、merge fast `30879645680` 均通过；这只是 report-only 诊断修正，不改变 OCR、翻译、renderer/export、Koharu active artifact gate、metrics 或 output。探针仍保留 block 5 截断，真实 Koharu 四件套、Speech corpus 与竖排图片 corpus 仍缺失。

- v3.88 对齐 Koharu render-lock 核心输出 gate：required ci-fast 输出全部 retained 且 non-empty 时，`G-render-core-png-retained` 与 `outputFileChecks` 统一为 `keepReportOnly`；缺失或空输出才使用 `inspectRenderOutputExport`。新增 `scripts/test-v388-koharu-render-core-output-gate-action-contract.py`，同步 v3.82–v3.87 历史合同与 CI 路由。该 report-only 修复不改变 OCR、翻译、renderer/export、Koharu active artifact gate、metrics 或 output。候选 full `30880132762`、同 SHA ci-fast `30880751340`、PR #152 fast `30881554748`、merge fast `30881613654` 均通过；block 5 截断仍被诚实保留，真实 Koharu 四件套、Speech corpus 与竖排图片 corpus 仍缺失，不声称质量提升。

- v3.89 让开发控制台的 `outputFiles` 摘要显示 required 输出的 `recommendedAction` breakdown，并与 `G-render-core-png-retained`／`outputFileChecks` 共用既有报告状态；新增 `scripts/test-v389-koharu-render-output-summary-action-contract.py` 与 CI 路由。该 report-only UX 不新增 Store／持久化，不改变 OCR、翻译、renderer/export、Koharu active artifact gate、metrics 或 output。候选 full `30882033347`、同 SHA ci-fast `30882428016`、PR #153 fast `30883254522`、merge fast `30883306577` 均通过；ci-fast 输出文本出现 `actionBreakdown=keepReportOnly=5`，但探针仍有 block 5 截断、`openRenderIssueDetected`，readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不得声称质量提升。

v3.90 修正漫画探针失败覆盖的显示排版：保留完整 OCR fallback 与首行 `翻译失败` 标记，仅把 OCR continuation 的显式换行压缩为空格，并让安全布局诊断、fit planner 与实际覆盖绘制共用同一显示变换。该 report/render-only 修复不改变 OCR 候选、翻译输入、Store、普通图片 renderer/export、ground truth、Koharu active artifact gate、metrics 或仓库 `output`；新增 `scripts/test-v390-koharu-render-failure-overlay-compaction-contract.py` 并接入 Koharu changed-file/full 路由。候选分支 `codeb/v3.90-koharu-failure-overlay-compaction` 的 commit `3344a8cd192684bf66e6cdff3397314c3fd8da05` 已通过 PR #154 合入，merge SHA `ee6046d491f327d6c71744876e0a4b4b6aab3947`，远端候选分支已删除，`main` 未触碰；full `30884104150`、同 SHA ci-fast 探针 `30884547044`、PR fast `30885582974`、merge fast `30885667505` 均通过。ci-fast 报告显示 `renderLockVerdict=renderStableWithProxyBoundaries`、`renderTextTruncatedBlocks=[]`，block 5 无截断且未触达最小字号，覆盖 PNG 非空；Koharu readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不声称 OCR、翻译、识别或 Koharu 质量提升。
v3.91 让 Developer Console 的漫画探针结果使用只读 `MangaProbeDiagnosticTriageSummary` 汇总既有 OCR 疑似、翻译模型／语言质量、覆盖布局和 Koharu 工件下一步，并让失败 block 行显示现有 failureCategory 的“模型输出失败／译文质量失败／OCR 疑似损坏”标签与 VoiceOver 分流上下文；新增 `scripts/test-v391-koharu-diagnostic-triage-contract.py`。该 View-only 改动不新增 Store／持久化、不运行第二次探针、不改变 OCR 候选、翻译 prompt／model、renderer/export、metrics 或 output。候选 SHA `bbb73b14a90a10438d4cacf46344881d21d6206e` 已经 PR #155 合入，merge SHA `1ab18c3e9f2d04fbd51680b5b1b606113d86d032`，远端候选分支已删除，`main` 未触碰；full `30886955217`、同 SHA ci-fast `30887582600`、PR fast `30888608909`、merge fast `30888676363` 均通过。ci-fast 仍为 13 blocks／12 failures、render lock stable、model floor variant regress、readiness `manifestMissing / stopUntilArtifactsProvided`，不声称 OCR、翻译、识别或 Koharu 质量提升。
v3.92 让普通图片 OCR 结果增加低置信／方向待定本地筛选，待复查仍保持风险并集；筛选、空态、VoiceOver 与忽略后的当前队列定位均只属于 View/复查展示，不改变 blocks、Store、Vision OCR、翻译、renderer/export 或复查门控。Developer Console 增加全部／失败／OCR／翻译／布局漫画诊断筛选，只读既有报告并在探针新运行时重置，不修改 probe_report 或主流程。新增 `scripts/test-v392-image-review-risk-filter-contract.py` 与 evaluator；候选 SHA `83a3e30d25483cb67d788babd4998f05afb42c08` 已经 PR #156 合入，merge SHA `118c8c039d752a24a6c992e8f942ec34cb43e009`，full `30889811326`、PR fast `30890241624`、merge fast `30890322575` 均通过，`main` 未触碰。探针默认 skip，Koharu readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不声称质量提升。

v3.93 修复普通图片 OCR 复查筛选跨图片残留：`imageTranslationRevision` 变化时清除 View 私有筛选、旧选中 block 与焦点，让新图默认显示全部结果；不写 Store／持久化，不改变 OCR、翻译、预览、导出或漫画探针。新增 `scripts/test-v393-image-review-filter-reset-contract.py`；候选 SHA `a3cea5a202f1de8a9b13aa4809db583b55480dcd` 已经 PR #157 合入，merge SHA `3f6565f65cc8ff965ba909f5d6e27ad0a508436c`，full `30890823578`、PR fast `30891431628`、merge fast `30891485989` 均通过，`main` 未触碰。探针默认 skip，Koharu readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不声称质量提升。

v3.94 修复漫画探针缺失 `test/1.png` 时的失败入口：新尝试先清空旧 report/blocks，随后重建 App 沙盒 `Output`；失败报告记录清理数量与成功状态，清理失败时不把旧输出冒充本轮结果。新增 `scripts/test-v394-manga-probe-failure-cleanup-contract.py` 并接入 Koharu changed-file/full 路由。该 report-only/状态隔离修复不改变 OCR 候选、翻译 prompt/model、生产 renderer/export、普通图片 OCR 或 active Koharu gate；候选 full `30893309273`、PR fast `30893920011`、merge fast `30893993759` 均通过，merge SHA `ea6be1ddacaa34953b0c7f3389c342dc6e9ff4e3`，readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不声称质量提升。

v3.95 让 Developer Console 的漫画探针结果在 `mangaOverlayProbeBlocks` 为空时显示明确的“本次探针未生成文字块”状态，隐藏诊断筛选器，并让 VoiceOver 说明当前失败上下文与重试范围；有逐块 blocks 时保持现有全部／失败／OCR／翻译／布局筛选和诊断行。新增 `scripts/test-v395-manga-probe-empty-state-contract.py` 并接入 UI/full 路由。该 View-only/诊断 UX 修复不新增 Store／持久化，不重新运行探针，不改变 OCR、翻译、renderer/export、普通图片 OCR、Koharu active gate、metrics 或 `output`。候选 SHA `802103e413261cc1632d1129362695728af45215` 已通过 PR #159 合入，merge SHA `a57e65b2c8220de39b59177ec873a394a3398781`；full `30984932342`、PR fast `30985360673`、merge fast `30985413482` 均通过，full Xcode/JUnit `10/10`，探针默认 skip，readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不声称 OCR、翻译、识别或 Koharu 质量提升。

v3.96 修正 `MangaProbeDiagnosticTriageSummary` 的状态色优先级：`artifactBlocked` 时始终使用 warning，只有 readiness 不阻断且既有 report `overallPassed` 时才显示 success，避免缺少真实四件套时误导开发者。新增 `scripts/test-v396-koharu-triage-tone-contract.py` 并接入 UI/full 路由。该 View-only/report-only 修复不新增 Store／持久化、不调用探针、不改变 OCR、翻译、renderer/export、普通图片 OCR、Koharu active artifact gate、metrics 或 `output`。候选 SHA `ab4d0ae59fbf2e0d6c6747fce331060ecfcc57ee` 已通过 PR #160 合入，merge SHA `12140ca11d3e888e74a974dffcfda41a0ca8357d`；full `30985776084`、PR fast `30986258687`、merge fast `30986307343` 均通过，full Xcode/JUnit `10/10`，探针默认 skip，readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不声称 OCR、翻译、识别或 Koharu 质量提升。

v3.97 让 Developer Console 的漫画探针布局筛选与 `MangaProbeDiagnosticTriageSummary` 共用 `mangaProbeRenderRiskBlockSet`，消费既有 fit planner 的 `fontBudgetRiskBlocks`、`spriteContainmentRiskBlocks`、`siblingOverlapRiskBlocks`、`failureOverlayRiskBlocks` 及 render-lock 的 issue/min-font/truncation 信号；只读报告，不修改 blocks、Store、探针或 renderer。新增 `scripts/test-v397-koharu-layout-triage-contract.py` 并接入 UI/full 路由。基于 ci-fast [30986469563](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/30986469563) 的 10/7/6 风险分流，候选 SHA `c552e6170cfd7b6daab4cbebd885bdb44314b007` 已通过 PR #161 合入，merge SHA `87b102cdd0d8f08bcea876cfcd08645ddc10cc58`；full `30987210261`、PR fast `30987676638`、merge fast `30987725142` 均通过，full Xcode/JUnit `10/10`，不声称 OCR、翻译、识别或 Koharu 质量提升。

v3.98 让 Developer Console 的漫画探针 OCR 与翻译筛选、triage 摘要共享只读 risk set，合并 diagnostics、model-floor、translation failureCategory 与 OCR 疑似证据，避免 floor 报告存在时丢掉 diagnostics；新增 `scripts/test-v398-koharu-diagnostic-risk-union-contract.py` 并接入 UI/full 路由。该 View-only/report-only 修复不新增 Store／持久化、不运行探针、不改变 OCR、翻译、renderer/export、Koharu active gate、metrics 或 `output`。候选 SHA `7a352a5050c8846765ad4b139e7a6a125dfb4712` 已通过 PR #162 合入，merge SHA `3b953b83d12a092df1995c974cb33522dc02331a`；full `30988262491`、PR fast `30988802078`、merge fast `30988876405` 均通过，full Xcode/JUnit `10/10`，fast 明确复用 full receipt；探针默认 skip，readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不声称质量提升。

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

v3.72 继续只读 Koharu readiness report：当 schema 为 v1 且 bubble/segment payload verdict 都是 `legacySummaryOnly` 时，Developer Console 显示“未要求（v1 summary-only）”与“未要求（v2 拓扑）”，并在 VoiceOver/可复制摘要中说明 v2 门控尚未要求；真实 v2 工件仍保留实际 payload/topology 失败与阻塞。该版本不创建或修改 active 工件、不放宽 gate、不改变 OCR、翻译、renderer/export、漫画探针或 Koharu 主路径，也不能作为质量提升证据。

v3.73 让空 OCR 的已忽略文字块在视觉行显示“空 OCR 原文”，VoiceOver label 显示“空”，避免空字符串让用户误以为行缺失；非空文本、恢复入口、焦点和 Store ownership 保持不变。该 View-only 改动不改变 Vision OCR、翻译、renderer/export、漫画探针、Koharu 主路径或质量基线。

v3.74 让普通图片 OCR 结果行与旁贴／覆盖预览在 `block.original` 为空时显示稳定“空 OCR 原文”回退；旁贴／覆盖仍保持非空译文优先。该 View-only 变化不新增 Store／持久化状态、不改变 Vision OCR、模型翻译、renderer/export、漫画探针、Koharu 主路径或质量基线。
v3.75 让 `ImageOCRCorrectionReferencePreview` 与 `ImageTranslationFocusPreview` 在 `block.original` 为空时用 View 私有 `accessibilityOriginalText` 提供“空”回退，避免参考／局部定位 VoiceOver value 变成无上下文空白；非空原文保持原样。该修复不新增 Store／持久化状态，不改变 Vision OCR、模型翻译、renderer/export、复查、漫画探针、Koharu、ground truth、metrics 或 output；真实 Koharu 四件套、Speech corpus 与竖排图片 corpus 仍缺失，不声称 OCR、翻译、识别或 Koharu 质量提升。
v3.76 隐藏 `ImageTranslationFocusPreview` 中仅用于视觉提示的“局部放大”角标，避免该装饰标签与父容器的“已定位文字块局部放大”VoiceOver label/value 重复朗读；参考预览原有装饰角标隐藏、关闭／修正／复查／前后定位与 OCR 上下文保持不变。该 View-only 修复不新增 Store／持久化状态，不改变 Vision OCR、模型翻译、renderer/export、复查、漫画探针、Koharu、ground truth、metrics 或 output；真实 Koharu 四件套、Speech corpus 与竖排图片 corpus 仍缺失，不声称 OCR、翻译、识别或 Koharu 质量提升。
v3.77 让 `ImageTranslationFocusPreview` 的无效几何状态子视图从 VoiceOver 树隐藏，父容器继续提供不可用原因和“关闭、编辑 OCR 原文或切换文字块”的统一 hint，避免 `contain` 层级重复朗读；参考预览、关闭／修正／复查／前后定位与 OCR 上下文保持不变。该 View-only 修复不新增 Store／持久化状态，不改变 Vision OCR、模型翻译、renderer/export、复查、漫画探针、Koharu、ground truth、metrics 或 output；真实 Koharu 四件套、Speech corpus 与竖排图片 corpus 仍缺失，不声称 OCR、翻译、识别或 Koharu 质量提升。

v3.78 让关闭 `ImageTranslationFocusPreview` 后的 VoiceOver 焦点回到对应 OCR 结果行，避免局部预览容器消失后焦点丢失；使用既有 View 私有 focus identity，不新增 Store／持久化状态，不改变 Vision OCR、模型翻译、renderer/export、复查、漫画探针、Koharu、ground truth、metrics 或 output。该版本只改善图片操作可理解性，不声称 OCR、翻译、识别或 Koharu 质量提升。

v3.79 让 `selectAdjacentBlock(offset:)` 在按当前筛选顺序选中目标 OCR block 后立即把 VoiceOver 焦点交给新的局部预览容器，前后导航继续保留位置 value、首尾 disabled 边界和 View 私有 focus identity；同步让 v3.14 历史合同接受等价的局部 target ID 赋值。该 View-only 改动不新增 Store／持久化状态，不改变 Vision OCR、模型翻译、renderer/export、复查、漫画探针、Koharu、ground truth、metrics 或 output，不声称 OCR、翻译、识别或 Koharu 质量提升。

v3.80 让筛选器隐藏当前选中 block 时清除失效的局部预览选择，并将 VoiceOver 焦点交给首个可见结果行；若筛选结果为空则交给复查完成状态或筛选器本身，确保焦点不留在已消失的预览容器。该 View-only 改动不新增 Store／持久化状态，不改变 Vision OCR、模型翻译、renderer/export、复查、漫画探针、Koharu、ground truth、metrics 或 output，不声称 OCR、翻译、识别或 Koharu 质量提升。

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
- 合并到 `smalldata_test` 后，workflow 读取 merge 第二父 SHA 的 full-validation status；只有 `success` 才走 fast follow-up，并把该 receipt 传播到 merge SHA，否则自动回退 full。C 退回后新的核心修复 push 必须重新产生 full 收据。
- 其后的纯 README / AGENTS / update log / `md/` / metrics `smalldata_test` 提交只有父 receipt 为 success 时可走 fast；父 receipt 缺失或失败时必须强制当前头部 Xcode build，不能用文档提交掩盖未验证代码。结果包必须保留 smalldata 父 SHA、state、元数据判定和强制 full 判定。
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
