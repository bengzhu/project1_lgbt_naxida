# 项目核心流程文档
本文只记录 AITRANS 当前真实架构和运行流程，不写历史流水账。历史看 `update_log.md`。

当前 v3.345 Japanese vertical crop spatial balance：`risk-first vertical layout blocks -> multi-band over-budget round-robin -> bounded 16-block crop queue -> existing owner/line/fallback fusion`；仅在候选超过 16 且存在多个非空纵向 band 时均衡既有 block crop 名额，最终恢复原风险顺序，16/8 请求上限、质量门、owner/layout、翻译 QA、取消和持久化边界不变。
当前 v3.344 Japanese weak-block recovery spatial balance：`weak layout blocks -> existing finite-confidence priority -> multi-band over-budget round-robin -> bounded four-block scoped reread -> measurable replacement`；只在候选超过 4 且存在多个纵向 band 时均衡既有 recovery 名额，最终恢复原 weak-first 顺序，`.55`/日文质量/改善门、失败取消、OCR/layout、翻译 QA 和持久化边界不变。
当前 v3.343 Japanese Vision line owner balance：`risk-first line geometry -> owner-balanced perspective/axis queues -> bounded 24-item Vision rereads -> Manga/Vision fusion`；复用显式 owner 的确定性补齐策略，两个 Vision 队列各自仍最多 24 项，只在前缀遗漏 known vertical TextRegion owner 时替换重复 owner，ownerless、12 次 orientation fallback、16M perspective 像素预算、Manga 8/2 名额和下游翻译/取消/持久化边界不变。
当前 v3.340 Japanese line coverage source boundary：`page/line observations -> exclude block-level detector TextRegion from source-line set -> existing owner/quality/geometry one-to-one proof -> bounded block crop fallback`；块级 detector bbox 不再伪造多行完整覆盖，既有 line/block OCR 预算、阈值、crop/warp、owner/layout、翻译 QA、取消与持久化边界不变。
当前 v3.339 detector 同标签跨切片合并边界：`slice detector predictions -> existing same-label containment/IoU/adjacent geometry gates -> merge/replacement -> restart complete slice scan -> v3.338 TextRegion closure -> confidence sort/Manga OCR`；只封闭跨切片候选的遍历顺序缺口，检测阈值、confidence 合法域、12/48 请求预算、crop/warp、owner/layout、翻译 QA、取消与持久化边界不变。
当前 v3.338 detector TextRegion 合并边界：`detector predictions -> existing IoU/containment relation -> union envelope -> restart scan -> deterministic merged TextRegion -> existing confidence sort/Manga OCR`；合并后重新检查此前跳过的候选，重叠链不再因 `popLast` 顺序留下重复区域；检测阈值、confidence 合法域、12/48 请求上限、crop/warp、owner/layout、翻译 QA、取消与持久化边界不变。
当前 v3.337 Japanese line candidate 调度边界：`text-backed vertical line candidates -> weak/text/density risk gate -> risk-first bounded line queue -> non-risk length order -> reserved geometry-only slots -> Manga/Vision fusion`；短、低置信、低日文字信号或低脚本密度 line 先进入既有 text-backed 名额，同风险组按有限 confidence、日文字母数和脚本文字密度弱者优先，非风险组保留长文本优先，最多 8 个 line OCR 请求、2 个 geometry-only 保留位、detector-owned 排除、line-first、owner/coverage、翻译 QA、取消与持久化边界不变。
当前 v3.336 Japanese vertical block crop 调度边界：`vertical layout blocks -> weak/text/direction risk gate -> risk-first bounded 16-block crop queue -> existing owner/line/fallback fusion`；低置信、低日文字信号、短文本或方向不稳的 block 优先获得既有 crop 名额，同风险组按有限 confidence 弱者优先，最多 16 个 block、8 个 orientation fallback、line-first、owner/geometry、翻译 QA、取消与持久化边界不变。v3.335 Japanese line-candidate confidence 边界：`Vision text-backed vertical line candidate -> finite [0,1] gate -> bounded weak-first line OCR queue`；非法或非有限 confidence 不得占用最多 8 次 line OCR 预算，合法同长度候选仍按较弱 confidence 优先复读，geometry-only 保留位不变；v3.334 layout confidence 全序边界：`raw layout confidence -> finite closed [0,1] normalization -> finite ordering key -> observation/block/vertical reading-order tie-break`；非法或非有限值不会进入 Swift `Float` 原始比较或破坏 strict ordering，合法 confidence 的几何、文字和阅读顺序保持不变；OCR 请求预算、owner/layout 主规则、翻译 QA、取消与持久化边界不变。
当前 v3.333 detector confidence 预算边界：`raw RT-DETR logit -> finite check -> sigmoid -> [0,1] validator -> top-query -> merged TextRegion revalidation -> long-page request ranking`；非法值在占用 detector/Manga OCR 预算前 fail closed，合法 confidence、几何 tie-break、12/48 请求上限、primary precedence、翻译 QA、取消和持久化不变。
当前 v3.317 日语 OCR 可靠文字证据边界：`Vision/Manga OCR -> shared Japanese letter signal (punctuation excluded) -> owner/line-coverage/scoped-candidate quality gates`；标点-only observation 仍可作为普通 fallback，但不能单独成为可靠 detector owner、complete line coverage 或 scoped block replacement 证据，不增加请求、预算、布局、翻译 QA、取消或持久化边界。
当前 v3.318 日语 OCR scoped 复查边界：单块 Manga/Vision reread 也必须含至少一个实际日语书写字符才可替换现有 block；标点-only observation 仍保留在普通页面候选流，不改变请求预算、geometry/layout、翻译 QA、取消或持久化边界。
当前 v3.319 日语→简体中文翻译 QA 边界：`sourceLeakage` 对纯汉字日语源允许共享 Han 译文，对含假名原文和其它语言对仍拒绝原文回显；标签、数字、术语、目标语言密度、长度、OCR、取消和持久化边界不变。
当前 v3.320 日语 OCR 恢复边界：`OCR text -> actual Japanese-writing density (punctuation stays in nontechnical denominator) -> bounded orientation/weak-block/scoped/line-budget recovery -> owner/coverage/frontier proof`；标点主导结果会继续触发受控补读，mixed Latin/digit token 不被惩罚，且低密度结果不能替换现有块、占用 text-backed line OCR 名额或抑制 pixel-first/tile fallback；普通页面候选仍保留，请求上限、翻译 QA、取消和持久化不变。
当前 v3.321 日语 line OCR 提交边界：`bounded Manga line request -> cleaned/confident result -> actual Japanese letter + meaningful density -> owner match -> verticalLine observation -> existing coverage/fusion/layout`；标点-only/标点主导结果不会提交为成功 line，缺口继续由既有 Vision line 与整块 fallback 接管，请求预算、crop/warp、owner、翻译 QA、取消和持久化不变。
当前 v3.322 日语 Vision recovery 提交边界：`pixel-first/tile crop observations -> shared actual-letter + meaningful-density gate -> geometry filter/dedupe/fusion OR existing opposite/block fallback`；标点-only/标点主导 crop 输出不再残留进最终布局，primary 被过滤时仍触发现有反向补读，请求预算、crop、owner、翻译 QA、取消和持久化不变。
当前 v3.323 日语整块 crop fallback 提交边界：`block primary -> shared meaningful-density gate -> bounded opposite -> same gate -> owner coverage/replacement/fusion`；标点-only/标点主导整块结果不再提交，也不能参与 partial-line replacement，现有 16 block、8 orientation fallback、crop/owner/layout/翻译/取消/持久化边界不变。
当前 v3.324 日语 Vision line crop 提交边界：`perspective/axis primary -> shared meaningful-density gate -> bounded axis opposite -> same gate -> line fusion/coverage OR existing block fallback`；标点-only/标点主导 line 重读不再提交，也不能抑制 axis/opposite/block recovery，现有 24 perspective/24 axis、12 orientation fallback、crop/warp、owner/layout/翻译/取消/持久化边界不变。
当前 v3.325 日语 scoped one-sided 候选边界：`Manga missing -> Vision usable gate`／`Vision missing -> Manga usable gate`；唯一候选也必须满足有限 confidence `>=.55`、真实日文字母、letter/script density `>=.5` 才能替换已有 block，双候选比较、整页标点 fallback、请求/取消/翻译/持久化边界不变。
当前 v3.326 日语 scoped two-sided 候选边界：`Manga + Vision -> each candidate full usable gate -> sole usable result OR existing measurable comparator OR nil`；双候选中的标点-only、低置信、非有限或低 script-density 候选不能借 meaningful fallback 成功，整页标点 fallback、请求/取消/翻译/持久化边界不变。
当前 v3.327 日语 scoped Vision 候选池边界：`each Vision top-5 pool -> full usable filter -> existing Japanese comparator -> cross-angle usable filter -> existing observation comparator -> Manga/Vision selector`；高分标点、低置信、非有限或低 density 噪声不再遮蔽同池/其它方向的合格日文，整页标点 fallback、方向/请求预算、取消、翻译与持久化边界不变。
当前 v3.328 普通日语 recovery Vision 候选池边界：`each crop/perspective top-5 pool -> actual-letter + letter/script-density filter -> existing Japanese comparator -> existing per-path confidence/fallback policy`；高分标点或低 density alternative 不再遮蔽合格日文，page/scoped 门、请求预算、crop/owner/layout、翻译、取消与持久化边界不变。
当前 v3.329 普通日语 duplicate fusion 边界：`geometry duplicate -> ordinary Vision pair -> meaningful Japanese preference inside existing 0.14 confidence window -> existing owner/boundary inheritance -> layout`；高分长 Latin/标点噪声不再遮蔽置信度接近的有效日文，远低置信日文不能替换强标点，detector/compact 专用规则、纯标点页面 fallback、请求预算、翻译 QA、取消和持久化不变。
当前 v3.330 OCR observation best reducer 边界：`observation pool -> candidate-first descending best reduction -> scoped Vision selection / Japanese orientation fallback / synthesized vertical-line provenance / diagnostic evidence`；不再把 descending comparator 误传给 `Sequence.max(by:)` 后选到最弱项，强结果不会因同池弱项触发多余反向补读或单块弱选，合成文字、平均 confidence、rect/owner、比较分数、请求上限、布局、翻译 QA、取消和持久化不变。
当前 v3.332 OCR confidence 合法域边界：`raw OCR/detector confidence -> finite + closed [0,1] validation -> existing Japanese windows/gates/comparator -> layout/review normalization -> translation`；NaN/±∞ 与有限越界值统一 fail closed，不能独占 `.14` window、放大 observation score、通过 `.40/.48/.55` 门或在 UI 中伪装为 `1`。合法 confidence 的分数、阈值、请求预算、owner/layout、翻译 QA、取消和持久化不变。
当前 v3.333 detector confidence 预算边界：`raw RT-DETR logit -> finite check -> sigmoid -> finite closed [0,1] validation -> top-query selection -> merged TextRegion revalidation -> Vision Manga request selection`；非法 score 不能占用 detector top-query 或长页 Manga OCR 配额，合法 score 与 geometry tie-break、12/48 请求上限、primary-before-supplemental、OCR/layout、翻译 QA、取消和持久化不变。

当前 v3.331 日语 OCR confidence 全序边界：`Japanese Vision alternatives -> finite-only existing confidence window -> finite-first observation comparator -> bounded orientation/weak-block recovery -> existing fusion/layout`；NaN/∞ 不再清空候选窗口、遮蔽有限读数或逃过反向补读，非有限 weak block 在既有 4-request cap 内优先，有限分数/阈值、请求上限、翻译 QA、取消与持久化不变。
当前 v3.316 日语 OCR 比较边界：`Vision/Manga OCR -> canonical Unicode normalization -> width-aware, dakuten-preserving Japanese dedupe -> existing OCR fusion/layout`；全角/半角等价形式仍可合并，但不再用 diacritic-insensitive folding 抹掉浊音/半浊音，不增加请求、不改变候选分数、geometry/layout、翻译 QA、取消或持久化边界。
当前 v3.315 日语 OCR 文本边界：`Vision/Manga OCR -> canonical Unicode normalization -> mixed-script/period normalization -> width-aware Japanese dedupe -> existing OCR fusion/layout`；等价的组合日文字符与宽度形式在比较/去重时保持一致，不增加请求、不改变候选分数、geometry/layout、翻译 QA、取消或持久化边界。
当前 v3.314 图片翻译流程：`OCR/layout blocks -> Japanese normalization -> Vision confidence-window content gate -> stable batch identity/context -> strict ordinal + request language validation -> tagged translation QA -> scoped correction/retry/reread parity -> render/export`。Vision 日语候选在有日语字母的同一置信度窗口内优先保留文字内容，只有窗口没有文字候选时才保留符号-only fallback；不增加 OCR 请求、crop/warp、预算或翻译 QA 边界。上一批摘要仍只有在 identity、连续 ordinal、source/target language 与当前请求全部匹配时才进入 prompt/QA；request language binding 是 transient metadata，不进入 block、snapshot、Store、transcript 或导出。
当前 v3.313 图片翻译流程：`OCR/layout blocks -> Japanese normalization -> stable batch identity/context -> strict ordinal + request language validation -> tagged translation QA -> scoped correction/retry/reread parity -> render/export`。上一批摘要只有在 identity、连续 ordinal、source/target language 与当前请求全部匹配时才进入 prompt/QA；未绑定或错语言 context fail closed。request language binding 是 transient metadata，不进入 block、snapshot、Store、transcript 或导出；detector、crop/warp、OCR 请求预算、geometry/layout、取消、generation、持久化和非图片路径不变。
当前 v3.311 图片翻译流程：`OCR/layout blocks -> fullwidth-aware Japanese token normalization -> language-specific translation path -> Japanese tagged batch/context/QA or non-Japanese single-block QA -> scoped correction/retry/reread parity -> render/export`。日语技术 token 的全角拉丁字母/数字先在 Vision 与 bundled Manga OCR 共用归一化边界内转成稳定 ASCII，并保留必要 token 分隔；纯日语仍沿用既有全角标点/点号规则。detector、crop/warp、OCR 请求预算、geometry/layout、翻译 QA、取消、generation、持久化与非图片路径不变；非日语整页、人工修正、单块重试和 OCR 复读重译继续统一通过 `translateImageBlockWithQA`。
当前 v3.312 图片翻译流程：`OCR/layout blocks -> Japanese punctuation-preserving normalization -> fullwidth-aware token normalization -> language-specific translation path -> tagged batch/context/QA -> scoped correction/retry/reread parity -> render/export`。日语中点 `・` 在 Vision、bundled Manga OCR 与混合脚本边界中保持为分隔符；只有 ASCII/全角句点和省略号进入有界点号归一化。detector、crop/warp、OCR 请求预算、candidate/geometry/layout、翻译 QA、取消、generation、持久化与非图片路径不变。
当前 v3.310 图片翻译流程：`OCR/layout blocks -> language-specific translation path -> Japanese tagged batch/context/QA or non-Japanese single-block QA -> scoped correction/retry/reread parity -> render/export`。日语继续使用混合脚本候选保真、bounded Manga/Vision 复读、稳定 batch identity、completed-only 只读 context、严格标签与逐块 QA；非日语整页、人工修正、单块重试和 OCR 复读重译现在统一通过 `translateImageBlockWithQA`，复用占位答复、原文泄漏、数字、目标语言密度和长度门，并保留已完成块、取消、generation、几何/layout、请求预算、持久化与非图片路径边界。
v3.306 日语图片翻译流程：`OCR/layout blocks -> mixed-script candidate fidelity selection -> mixed-script-safe Japanese OCR normalization -> bounded Japanese OCR recovery -> reconcile conservative SFX kind hint -> stable identity batch plan -> global-ordinal read-only context -> strict tagged translation -> per-block QA/retry -> correction/retry context parity`。混合候选只在同时含日语脚本与 ASCII 字母/数字时得到有界偏好，随后保留技术 token 的 ASCII 与必要空格；历史 standalone OCR harness 与产品 target 共用 normalizer source，纯日语仍沿用既有点号/全角标点边界。人工修正、单块重试、scoped OCR 复读和忽略/恢复只更新 block 值，batch context 仍不进入 block、持久化或取消边界。
v3.305 日语图片翻译流程：`OCR/layout blocks -> mixed-script-safe Japanese OCR normalization -> bounded Japanese OCR recovery -> reconcile conservative SFX kind hint -> stable identity batch plan -> global-ordinal read-only context -> strict tagged translation -> per-block QA/retry -> correction/retry context parity`。混合日语/拉丁文字只保留技术 token 的 ASCII 与必要空格，纯日语仍沿用既有点号/全角标点边界；人工修正、单块重试、scoped OCR 复读和忽略/恢复只更新 block 值，batch context 仍不进入 block、持久化或取消边界。
v3.304 日语图片翻译流程：`OCR/layout blocks -> bounded Japanese OCR recovery -> reconcile conservative SFX kind hint -> stable identity batch plan -> global-ordinal read-only context -> strict tagged translation -> per-block QA/retry -> correction/retry context parity`。人工修正、单块重试、scoped OCR 复读和忽略/恢复只更新 block 值；active + ignored identity 按原始 page order 生成上一完整 batch 摘要，context 不进入 block、持久化或取消边界。split/merge/move 结构 mutation 会清除 plan 并按新结构重建，日语候选仍统一经过 block-level QA。

当前 v3.300 日语图片翻译流程：`OCR/layout blocks -> bounded batch -> global-ordinal read-only kind hints -> strict tagged translation -> per-block QA/retry`。类型提示与跨 batch 的 `[N]` 输入序号对齐，不进入待翻译文本、输出标签、OCR/layout、持久化或取消边界。

当前 v3.299 日语图片翻译流程：`OCR/layout blocks -> bounded batch -> read-only per-block text-kind hints -> strict tagged translation -> per-block QA/retry`。混合 batch 只把对应 block 的对白/旁白/拟声词/标题提示给模型，不改变输入标签、OCR、布局、持久化或取消边界。

当前 v3.298 日语图片翻译输出流程：`raw model output -> remove explicit prompt metadata -> preserve all remaining lines -> shared validation/QA -> accept or fail closed`。标准 Local translation 不再只取最后一行；合法多行对白和普通 bullet 行保持原顺序，拒答/泄漏/目标语言等既有质量门仍生效。

当前 v3.297 日语图片翻译质量流程：`model output -> shared placeholder policy -> batch/per-block QA -> accept or fail closed`。Gemma、本地探针与图片逐块 QA 共用同一明确拒答判定；合法“谢谢”“请提供证件”等对白不因宽泛 marker 被误拒，拒答仍不进入结果或持久化。

当前 v3.296 日语图片翻译流程：`OCR/layout blocks -> bounded tagged batch -> batch QA -> failed block single fallback with the same QA -> accept only QA-passed candidates -> partial persistence/scoped cancel`。fallback 不再绕过 placeholder、泄漏、数字、术语、目标语言密度和长度检查；取消不被吞成质量失败。

当前 v3.290 图片翻译结果流程：`completed image session -> existing rectangle overlay renderer/export -> report-only ImageTranslationRenderSafety.analyze -> accessible warning only`。预检只读检查 invalid geometry、空文字、旁贴裁切／覆盖、源块重叠和跨块碰撞；它不参与 OCR、翻译、候选选择、renderer、export、持久化或复查状态。

当前 v3.292 证据 readiness 流程：`shared corpus manifest -> split/annotation/prediction/holdout freeze gate -> blocked/readyForHoldout report -> no product-path change`；共享授权语料、四引擎同 crop 预测矩阵或 holdout 冻结条件缺失时只生成 cloud-only report，不读取 ground truth 做产品决策、不进入 OCR/翻译模型选择。

当前 v3.293 readiness 完整性流程：`canonical four-engine dev matrix -> available-row/dataset-accounting/policy-flag gate -> blocked/readyForHoldout report`；required rows 固定为四引擎 × oracle/detected/full 的 12 个 `dev` 行，缺行、failed 行、分割计数不覆盖 dataset 或 holdout/product-selection 安全 flag 违反时 fail closed，仍不进入产品 OCR/翻译选择。

当前 v3.294 readiness artifact intake 流程：`manifest declaration -> rooted regular-file/path-boundary/SHA verification -> prediction envelope/page-region coverage -> blocked/readyForHoldout report`；available dataset、source manifest 和 12 个 prediction artifact 必须在显式 artifact root 内一一对应，实际文件、payload dataset/engine/crop/split/referenceOnly、predictionCount 与 dev page/region coverage 任一不符即拒绝，不改变产品路径。

当前 v3.289 图片复查流程：`persisted block -> read-only provenance disclosure -> low-confidence/direction-uncertain scoped bbox draft -> commit -> scoped rerecognition or restore`；draft 拖动不启动 OCR，提交与 rerecognition 仍由 block identity、request/content ID、generation 和 scoped cancel 保护。图片会话快照只在受管文件的 path/type/regular-file/byte-count/SHA-256 全部匹配时恢复；split／merge 生成新 block identity 并失效受影响译文／旧 OCR evidence，order mutation 保留可用 metadata 与 review progress。

当前 v3.288 日语翻译流程：`OCR/layout blocks -> bounded Japanese batch (<=8 blocks, <=1,800 chars) -> confirmed/candidate/revoked terminology + read-only previous completed-batch summary -> strict tagged output -> per-block QA -> retry failed blocks only -> partial persistence/scoped cancel`。跨 batch summary 只作为下一批 prompt context，不能成为 pending input 或标签；QA 不重跑 OCR、检测、布局或整页翻译，已成功 block 保持不变。

当前验证边界：本机只执行无进程合同、Python AST、workflow YAML、shell/plist 与 diff 检查；Swift/Xcode/Core ML/Rust/GGUF/App/runtime 与真实模型、授权语料、目标设备证据在云端或外部提供。synthetic contract、report-only safety 和固定样图不能替代 OCR/CER、翻译盲评或 v3.289 holdout。

v3.265 Vision vertical line quad：`line polygon -> local canonical DeviceRGB crop -> shared Koharu target geometry -> direct projective bilinear sampling -> rotate270 -> Vision line reread`；direct geometry／sampling failure 才回退 Core Image natural projection，detector bbox ownership、budget、OCR／翻译／布局边界不变。

v3.264 垂直 quad crop：`canonical DeviceRGB crop -> destination-to-source projective map -> image-rs-compatible bilinear (floor/four-neighbor/constant-black border) -> bounded quad-axis canvas -> rotate270 -> Manga OCR weak fallback`；bbox primary、natural projection fallback、OCR／翻译／布局边界不变。

v3.263 图片单块复查取消：`rerecognizingBlockID != nil -> scoped cancel current block task -> retain image task/review IDs/translated session -> current request cancellation catch restores previous state + failure generation -> VoiceOver status focus`；整图 OCR／翻译、换图和全局取消继续走原 cleanup。

v3.262 detector 输入：源图 → canonical 8-bit DeviceRGB → image-rs/Koharu 等价 Triangle separable resize（pixel-centred sampling／edge normalization／最终 pass round）→ 显式 RGB→32BGRA → RT-DETR 640×640；threshold、ownership、Manga OCR、Vision fallback、12／48 budget、取消、布局、翻译、渲染与非图片路径不变。

v3.261 图片 OCR 复查交互：结果行／局部预览触发 Vision OCR 恢复 → View 记录 `.row`／`.preview` → 确认成功后按入口回焦；目标因筛选隐藏时回退可见结果、完成态或空态。恢复仍只消费既有 Store baseline，不重跑 OCR、翻译或导出流程。

v3.260 日语 Manga OCR crop：源图 → canonical 8-bit DeviceRGB → Koharu/image-rs luma floor `(2126R + 7152G + 722B) / 10_000` → 224×224 nearest floor resize → Manga OCR；decoder、batch／单 crop fallback、取消、detector ownership、布局、翻译、渲染和非图片路径不变。

v3.241 日语 detector TextRegion → 严格 quad gate → Manga OCR bbox 主 crop；仅当 bbox 结果弱时才执行 line quad fallback，且只有显式 vertical hint 的四点 quad 才按 Koharu 长短轴生成 bounded target canvas → `rotate270` → Manga OCR，通用 quad 保留自然 perspective crop，目标／旋转失败保留自然 warp，投影失败回到 bbox。layout／ownership `rect`、batch、12-48 预算、取消、Vision fallback、批翻译、竖排渲染与非日语路径不变。

v3.232 日语 detector TextRegion → Vision 字符四边形严格 coverage gate → 可选 Core Image `CIPerspectiveCorrection` line crop → Manga OCR；quad 缺失／非法／投影失败回退 v3.231 扩展 `cropRect`。`textRect`、layout／ownership 几何、batch／12-48 预算、模型失败／取消、Vision fallback、去重、批翻译、竖排渲染与非日语路径不变。

v3.231 日语 detector TextRegion `rect`（布局／ownership owner）→ Vision 字符 envelope 严格 coverage gate → 仅 Manga OCR crop 使用 tight hint，失败回退 detector bbox → 既有 batch／12-48 预算、Vision fallback、日语去重／布局／批翻译／竖排渲染；普通语言与 detector ownership 几何不变。

v3.230 日语图片 batch OCR runtime contract：harness 先读取 `batchInference`／`blocks` 元数据，再只解析带方向的 block 记录；元数据不得污染 provenance gate。v3.229 的 crop list → encoder `EnumeratedShapes(1…4)`（CLS 广播使用动态 shape `fill`，不生成动态 `tile(reps)`）→ decoder 动态 sequence → batch 输出及逐 crop fallback 保持不变。

v3.228 日语图片路径：Vision page／Koharu RT-DETR TextRegion → 有界 Manga OCR 请求选择 → 最多 4 个 crop 组成一批，若随包 flexible-batch encoder／decoder 成对可加载则执行 batch，否则回退 legacy 单 crop；批次错误按 crop 隔离回退，取消传播与 12／48 请求上限不变 → 日语去重／布局／批翻译／竖排渲染。单页与长页 harness 要求 `batchInference=true`；实际 Core ML 编译与 runtime 以云端收据为准，不把该性能路径当作 OCR 质量证明。

v3.212 普通图片日语 page reconnaissance（Vision language correction 保持开启）→ line-first／pixel detector／tile／block local crop（仅这些日语 crop 关闭 correction）→ Koharu 风格日语 post-process → 原图映射／日语去重／布局／批翻译／渲染；普通语言路径不变。request helper 显式保留 `true` 默认并允许受限 caller opt out，兼容 v3.156；本地 v3.157-v3.212 合同 `56/56` 通过，v3.157/v3.158 已合入且无活动分支；exact-SHA full `31302657064`（SHA `bd7c510b99ac78c22ca330ae2e125a5193610fe4`，Xcode/JUnit `10/10`）通过，probe `skip`，readiness `manifestMissing / stopUntilArtifactsProvided`，不声称质量提升。

v3.212 候选 metadata `31309651292`（docs SHA `174a7180d229381b41c5184e1525a2ad7651baa3`）、PR #276 fast `31309712340` 与 merge fast `31309783552` 均复用候选成功 receipt；merge SHA `ccab9e318b0c71447b59cb2b370d5778a9c68904`，后续 fast Xcode skipped，不是新的编译证据。

v3.211 日语图片 page reconnaissance 保留 `ja-JP`/`ja`/`en-US`/`en` → line/block/tile vertical reread 只用 `ja-JP`/`ja`，不支持的日语 profile 安全跳过该 reread → 原有 line-first、pixel detector、tile、block fallback → 映射／日语去重／布局／批翻译／渲染；full `31300669764`（SHA `c0c26aaddb3db641c59cb878d1434207b9879f54`，Xcode/JUnit `10/10`）通过，probe `skip`，readiness `manifestMissing / stopUntilArtifactsProvided`，不声称质量提升。

v3.210 图片翻译失败／部分失败 → 保留 OCR blocks、geometry 与已完成译文 → 仅空译文 block 单独 retry（日本語复用 `[N]` batch，其他语言复用单块翻译）→ retry/content ID 防过期写回 → 仍有空块则保持 failed，全部完成才 translated → 更新 transcript 与 overlay export；结果行／局部预览／VoiceOver 提供门控 action，不重跑 Vision OCR。exact-SHA full `31299660925`（SHA `b9ec296d0cdafbe0bfbbe0aebc90e1255a44d6d2`，Xcode/JUnit `10/10`，0 failures）通过；候选 metadata `31300023503`（docs SHA `0dc5b019e231aa35137de705a6a2b8e0a377d029`）复用成功 full，PR #274 fast `31300071078` 与 merge fast `31300107560` 均复用候选 full，merge SHA `ee7e41f0679fd999b8f9337a3bf0622742e095c3`，后续 fast Xcode skipped；v3.157/v3.158 已合入当前基线，无活动分支；readiness `manifestMissing / stopUntilArtifactsProvided`，probe `skip`，不声称质量提升。

v3.209 日语竖排 block → `verticalLine` perspective／轴对齐 reread first → 可靠 line coverage（非空、confidence `>= 0.48`、日语脚本密度 `>= 0.5`、紧 geometry 有效）→ 未覆盖区域才进入 pixel detector → 未覆盖区域再进入 tile fallback → 最后 block crop → 映射／日语去重／布局／批翻译／渲染；pixel detector 保留 `verticalLine` provenance，tile fallback 保持历史 `.crop` provenance，缺失紧 geometry 回退宽 `rect`，普通语言与其他路径不变。exact-SHA full `31297254547`（SHA `17f19bb2505d504e1255ab925d2aa7572020435a`，Xcode/JUnit `10/10`）通过；本地 v3.157–v3.209 合同 `53/53` 通过；PR #273 fast `31297894114` 与 merge fast `31297941634` 均复用候选 full，merge SHA `4e2b8fdceec51359bb923bd583687fa2e3ed9e24`，fast Xcode skipped；readiness `manifestMissing / stopUntilArtifactsProvided`，探针 skip。

v3.208 日语竖排 page／block observation → 90°／270° `VNDetectTextRectanglesRequest` pixel-first geometry 侦察 → 映射回原图、竖排比例／尺寸门控、排除已覆盖 vertical block → 最多 12 个 detector crop → grayscale／有界放大／Vision OCR，最多 4 次 opposite fallback → 日语去重／布局／批翻译／渲染；detector 不加载 Koharu 模型，普通语言与既有路径不变，exact-SHA full `31295791350`（SHA `41eff6cb86073900332d9785eea32606a5688dce`，Xcode/JUnit `10/10`）通过，PR #272 fast `31296131671` 与 merge fast `31296221789` 复用候选 full，merge SHA `7c8642af855fcbf79cfad7a3a9052a5465d83632`，后三者 Xcode skipped；readiness `manifestMissing / stopUntilArtifactsProvided`，探针 skip。

v3.207 日语竖排 block → 枚举 source line → 每条独立 `verticalLine` reread 先过 confidence／日语脚本／glyph 数量质量门控 → 只有完整可靠覆盖才跳过 block crop，弱结果回退 block crop → 映射／去重／布局／批翻译／渲染；普通语言、tile、page、探针与真实模型边界不变。本地 v3.157–v3.207 合同 51/51 通过；候选 full `31294146132`（SHA `f7a18e4c008903fd50f15183fa3b9a8629216bef`，Xcode/JUnit `10/10`，0 failures）成功，候选 metadata `31294486910`、PR fast `31294542723`、merge fast `31294614418` 均复用候选 full，merge SHA `15577b7a184f9b6a8d281f1551367b1c72231a65`；readiness `manifestMissing / stopUntilArtifactsProvided`，探针 skip。

v3.206 日语竖排 observation → Recursive XY-cut；无有效 cut 或分区失效时按 `4 × min_gap_y` 行桶从上到下、同一行右到左回退 → 同列 Cluster／批翻译／渲染；混合 block fallback 与非日语交错路径不变。新增 v3.206 observation-row fallback 合同；full `31293120347`（SHA `5aefe027e97f37aa209c09d2a9d33ecf0a1d848c`，Xcode/JUnit `10/10`）、PR #270 fast `31293135057`、merge fast `31293388944` 均成功，后两者复用 full，merge SHA `9513cd7c9d33610f0b93a4e435f9e3f1867328bb`，Xcode skipped；探针 skip，readiness `manifestMissing / stopUntilArtifactsProvided`。

v3.205 日语竖排 block → 枚举 source line → 每条独立 tight `verticalLine` 覆盖才跳过 block crop → 部分／合成／噪声结果安全回退 block crop → 映射／去重／布局／批翻译／渲染；实现 full `31292332659`（SHA `7891cfeaf3486eb6a507d1b2045a9b662b8c66ca`，Xcode/JUnit `10/10`）通过，探针 skip，readiness `manifestMissing / stopUntilArtifactsProvided`。

v3.204 日语竖排 block → 有效 line polygon proxy 先走 perspective／轴对齐 line OCR → 只有 line 无可用 observation 才回退 block crop → v3.203 tight ownership／方向 provenance／bounded fallback → 映射／去重／布局／批翻译／渲染；v3.157/v3.158 双向方向与 block crop 合同继续回归。实现 full `31290525270`（SHA `ae922bda0bf566cc14d422a6d9c9a4c042b34218`，Xcode/JUnit `10/10`）通过，候选 metadata `31290904290`、PR #268 fast `31290942391`、merge fast `31290981606` 均复用成功 receipt，merge SHA `b65653bc577ba65c51ed6cc1c2bd373b00e76aec`，后三者 Xcode skipped；探针 skip，readiness `manifestMissing / stopUntilArtifactsProvided`。

v3.203 日语竖排 line → 宽 `rect` overlap 后再以有效紧 `lineRegionRect` 校验 block ownership（缺失／非法 geometry 回退宽框）→ candidate gate／碎片合成／block envelope → perspective／轴对齐 crop → `verticalLine`／rotate270 → 映射／去重／布局／批翻译／渲染；实现 full `31287319601`（SHA `01fdaf16dde9029079231eb7c5406042fcab8cfc`，Xcode/JUnit `10/10`）通过，候选 metadata `31287648270`、PR #267 fast `31287677451`、merge fast `31287707581` 均复用成功 receipt，merge SHA `295c59a72a886cbc19cd9c3126d9e162ce525afd`，后三者 Xcode skipped；探针 skip，readiness `manifestMissing / stopUntilArtifactsProvided`。

v3.202 日语竖排 line → 用紧 `lineRegionRect`（缺失时回退 `rect`）执行高宽比／高度 candidate gate → 仍以宽 `observation.rect` 与 block 做 overlap → perspective／轴对齐 crop → `verticalLine` provenance／rotate270 → 映射／合成／去重／布局／批翻译／渲染；实现 full `31286506178`（SHA `2f198f9f12e62c5e10fe7a73b76cdc0af9d69107`，Xcode/JUnit `10/10`）通过，候选 metadata `31286843872`、PR #266 fast `31286875844`、merge fast `31286908329` 均复用成功 receipt，merge SHA `839c5e9d9f5705f50c85d65e7085157c5b876b07`，后三者 Xcode skipped，探针 skip，readiness `manifestMissing / stopUntilArtifactsProvided`。

v3.201 日语竖排 line → 标记 `verticalLine` provenance → perspective／轴对齐 crop 以 Koharu `rotate270` 主方向读取 → 原图映射／合成／去重继续保留该方向偏好 → 弱结果按预算走 90° fallback → 布局／批翻译／渲染；page、block、tile 方向边界不变。实现 full `31262554391`（SHA `97120cf38d85729f605e3d8bdbc836a0271e1c99`，Xcode/JUnit `10/10`）通过；候选 metadata `31262979444`、PR #265 fast `31263017146`、merge fast `31263072991` 均复用成功 receipt，merge SHA `3aac10326a987a47ea1786cd76c37b96b3ca9b36`，探针 skip，readiness `manifestMissing / stopUntilArtifactsProvided`。

v3.200 日语竖排 block → 收集相关 `lineRegionRect` 并与原 block 做 envelope union → 以原 `block.rect` 最小边作为 Koharu font-size anchor 计算方向感知 padding → block crop OCR／fallback → line reread／去重／布局／批翻译／渲染；避免 union envelope 变大造成过度扩边，缺失 geometry 回退旧 crop，非日语与其他路径不变。实现 full `31260969111`（SHA `c91858868cace78b846bd742f69a95f765b5737a`，Xcode/JUnit `10/10`）通过；候选 metadata `31261967648`、PR #264 fast `31261881073`、merge fast `31261995539` 均复用成功 receipt、Xcode skipped，探针 skip，readiness `manifestMissing / stopUntilArtifactsProvided`。

v3.199 日语竖排 block → 收集相关 Vision `lineRegionRect` → 与原 block 做 Koharu envelope union（不缩小原框）→ 方向感知 padding → block crop OCR／弱方向 fallback → line reread／去重／布局／批翻译／渲染；缺失 geometry 回退旧 crop，非日语与其他路径不变，候选 full `31260137161`、PR fast `31260466644`、merge fast `31260501796` 均通过，候选 SHA `b85f12389eddf1cd82d8aa2892fe5f730d4b8a56` Xcode/JUnit `10/10`，merge SHA `20d5987c245bf6768257e61d6ee030cf2324aef0` 复用候选 full；探针 skip，readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不声称质量提升。

v3.198 日语竖排 line → Koharu `warp_line_region` `rotate270` 主方向 → perspective／轴对齐 line crop OCR → 弱／空结果在 12 次预算内 90° fallback → 去重／布局／批翻译／渲染；block、tile 与非日语路径不变，候选 full `31259014271`、PR fast `31259242739`、merge fast `31259272510` 均通过，候选 SHA `24c8f9c23f3bec3e6536ad4752e99a4703ff07f4` Xcode/JUnit `10/10`，merge SHA `0b7352be9393e17fc55224269604dfc6859d2351` 复用候选 full；探针 skip，readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不声称质量提升。

v3.197 日语竖排 block → Koharu `pp_doclayout_v3` aspect `1.15`／方向置信度 `0.25`／高度 `0.035` 门控 → 最多 16 个 block crop OCR → 既有 90°／270° fallback、line/tile reread、去重、布局、批翻译与渲染；非日语与失败回退不变，候选 full `31258318641`、PR fast `31258329662`、merge fast `31258606990` 均通过，候选 SHA `e099acb375cf799d9f3d26b203eead6505b9b65c` Xcode/JUnit `10/10`，merge SHA `bd91910ccfe38b78d2827095b7e2970c1347d881` 复用候选 full；探针 skip，readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不声称质量提升。

v3.196 日语图片 OCR blocks → 全局 `[N]` 标签有界批次（最多 8 块／约 1800 字符）→ Koharu 漫画语气与顺序提示 → 严格 tag 解析 → 翻译／渲染；缺 tag、乱序或空块安全回退逐块翻译，非日语与修正 sheet 保持原路径，候选 full `31257482066`、PR fast `31257709942`、merge fast `31257752177` 均通过，候选 SHA `4282395bd982c2c6fcb92058b3cdfb8409defd01` Xcode/JUnit `10/10`，merge SHA `dd007a40705903bcc92800f30a905ead44810503` 复用候选 full；探针 skip，readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不声称质量提升。

v3.195 日语混合版面 → 横排／竖排 block 合并 → Koharu 风格递归 XY-cut（横切右侧、纵切顶部）→ `4 × min_gap_y` 行桶右到左回退 → 布局／翻译／渲染；非日语继续旧交错，候选 full `31233606259`、PR fast `31233872614`、merge fast `31234023270` 均通过，候选 SHA `52963a4c1cbe16f8662a99ae443aea36f1dbb486` Xcode/JUnit `10/10`，merge SHA `12b0217c7c56a2993986f4a42ba6e6f98c7df6a2` 复用候选 full；探针 skip，readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不声称质量提升。

v3.194 日语 OCR 紧区域去重：Koharu containment-like overlap `>= 0.85` 或 IoU `>= 0.50` → 双方 `lineRegionRect` 几何合并 → 宽 request box／缺紧区域走文本相似度 → 布局／翻译／渲染；候选 full `31232966715`、PR fast `31233259741`、merge fast `31233297104` 均通过，候选 SHA `e4388409785bc60278b819e36e8b4afdc7ec7307` Xcode/JUnit `10/10`，merge SHA `5ce315332aa6ab073e3e9733f174cbf2ccac0121` 复用候选 full；探针 skip，readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不声称质量提升。

v3.193 日语 OCR 紧区域去重：Koharu `merge_slice_regions` containment-like 规则 → 双方 `lineRegionRect` 且 overlap `>= 0.85` 时合并 → 宽 request box／缺少紧区域仍走文本相似度 → 布局／翻译／渲染；候选 full `31232333781`、PR fast `31232570686`、merge fast `31232612519` 均通过，候选 SHA `a645943b85345790309adde433344a53209bbccc` Xcode/JUnit `10/10`，merge SHA `c00ffc306a193351179e86b7fd7ad0783bd1ad4b` 复用候选 full；探针 skip，readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不声称质量提升。

v3.192 日语竖排 fallback 窗口调度：Koharu `ImageSlicer` 局部窗口 → x 坐标右到左消费、每列 y 上到下 → 最多 18 个 90° crop OCR／最多 4 次 270° fallback → 日语过滤／原图映射／去重／布局／翻译／渲染；候选 full `31231339154`、PR fast `31231689829`、merge fast `31231720315` 均通过，候选 SHA `d4a7811b634df7f300fb60a99e331a27f69287bd` Xcode/JUnit `10/10`，merge SHA `2aae0d7ff0e5394bed6a0c13edbb3a2624f67c1a` 复用候选 full；探针 skip，readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不声称质量提升。

v3.191 日语竖排切片：横向窄条 → 按 Koharu `ImageSlicer` 目标 3:1、20% 纵向 overlap、70% 尾片阈值生成局部窗口并触底 → 最多 18 个有效窗口做 90° crop OCR／最多 4 次弱结果 270° fallback → 日语过滤、原图映射、去重、block/line reread、布局、翻译与渲染；最终 full `31230729061`、PR fast `31231091935`、merge fast `31231128313` 均通过，最终 SHA `32c350c6ce4c40d90dd1d9505a830c083a62ce49` Xcode/JUnit `10/10`，merge SHA `16cce70a48afda648f045edf9d97f9a1191890cd` 复用 full；探针 skip，readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不声称质量提升。

v3.190 日语长图漏列侦察：横向重叠窄条 → 每条拆成约 58% 页面高度、18% 纵向重叠且覆盖底边的局部窗口 → 最多 12 个有效窗口做 90° crop OCR／最多 4 次弱结果 270° fallback → 日语过滤、原图映射、去重、block/line reread、布局、翻译与渲染；候选 full `31229567448`、PR fast `31229946643`、merge fast `31229977158` 均通过，候选 SHA `44e0030aa1914468fceedfc5404eaf7510e9673b` Xcode/JUnit `10/10`，merge SHA `ec8ad6333005527042fd7f13f8f203bfa36fafe5` 复用 full；探针 skip，readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不声称质量提升。

v3.189 日语单字 crop provenance：日语 block／line／tile crop → 映射回原图保留 `sourceDirectionHint=.vertical` → 只要含 CJK（单 glyph 也有效）就在日语 manga-order layout 先尊重 source direction → 再进入宽框回退、去重、翻译、渲染；页级 observation、普通语言与横排路径不变。候选 full `31228731388`、PR fast `31229051329`、merge fast `31229096792` 均通过，候选 SHA `8c89b0c0d1c0dff91efd3c115583ab5f04d14017` Xcode/JUnit `10/10`，merge SHA `6a510efece0b7ef6deeb9f1c3dd19c11f625ba1a` 复用候选 full；探针默认 skip，Koharu readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不声称质量提升。

v3.188 日语竖排 block 拼接：Koharu 同一右到左文字列内自上而下 → AITRANS 合并后的 vertical `Cluster` 显式按 y↑、同 y 时右侧 x↓、几何／文字／confidence 稳定排序 → 拼接文本 → 去重、翻译、渲染；横排换行、同列合并门控、普通语言与页级路径不变。候选 full `31227754288`、PR fast `31228156354`、merge fast `31228206021` 均通过，候选 SHA `1580a5c145efede4fefa23fd743c8170e077b1f9` Xcode/JUnit `10/10`，merge SHA `bbba2eee0a31a3bfd8b82508c77caac3677e1810` 复用候选 full；探针默认 skip，Koharu readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不声称质量提升。

v3.187 日语 crop provenance：日语 block／line／tile crop → 映射回原图并保留 `sourceDirectionHint=.vertical` → 日语 manga-order layout 先尊重 Koharu-style source direction，再回退宽框 heuristic → 去重、翻译、渲染；页级 observation、普通语言与非日语仍走原几何路径。候选 full `31226671116`、PR fast `31226855629`、merge fast `31227082382` 均通过，候选 SHA `881d2b4fe49d8adde181d8e33d210a38515fcdd8` Xcode/JUnit `10/10`，merge SHA `c1bb36ba956e5a48b583ff1e2a2214e3dcee916c` 复用候选 full；探针默认 skip，Koharu readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不声称质量提升。

v3.186 日语 tile 结果收敛：tile crop OCR → 日语脚本密度＋高竖框／受限紧凑片段过滤 → 过滤结果决定 270° fallback → 原图映射、日语去重与既有 block/line reread、布局、翻译、渲染；v3.185 的 6 tile／18% overlap／4 fallback 预算与其他语言路径不变。候选 full `31225584307`、PR fast `31225981653`、merge fast `31226027759` 均通过，候选 SHA `86cf3fd289b4d42c18658d48d5c93308e4f5f91c` Xcode/JUnit `10/10`，merge SHA `5bb34b44d0c93ab93d816a848266f65c95ad9d6c` 复用候选 full；探针默认 skip，Koharu readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不声称质量提升。

v3.185 日语竖排漏列恢复：整页／90°／270° Vision observation → 既有竖排 block 形成后，对未被覆盖的最多 6 个全高、18% 重叠 tile 做 bounded reconnaissance → 灰度／放大、90° crop OCR，弱结果最多 4 次 270° fallback → 原图映射、日语去重、既有 block/line reread、布局、翻译与渲染；普通语言与失败边界不变。候选 full `31224644168`、PR fast `31225019712`、merge fast `31225064534` 均通过，候选 SHA `0c0585a850f4a0a7a4fc4a5735c791439713c4c2` Xcode/JUnit `10/10`，merge SHA `ccd46c169ae7447d4f0485e4d982277f8ba33e46` 复用候选 full；探针默认 skip，Koharu readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不声称质量提升。

v3.184 日语 OCR 融合：Vision observation → 日语双方都有 `lineRegionRect` 时按紧 line geometry 去重，缺失时回退 `rect` → 竖排 line candidate 同样传入日语偏好 → 布局、翻译与渲染；普通语言继续 request-box 去重，文本相似度与 fallback 不变。候选 full `31223348790`、PR fast `31223808151`、merge fast `31223883384` 均通过，候选 SHA `1bc212b0cf5c8190a9aa9746fb44c0f03ae638dd` Xcode/JUnit `10/10`，merge SHA `211dab273bf9b0830b411f0586938ba77c93b46d` 复用候选 full；探针默认 skip，Koharu readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不声称质量提升。

v3.183 日语 perspective line：四点 quad → Koharu 长短轴目标画布 `(textHeight, textHeight × ratio)` → Core Image warp 后有界重采样（4096 边长／4M 像素）→ 灰度／放大、90°／270° reread、映射／去重 → 布局、翻译与渲染；几何异常回退自然 warp，24 line／16M warp 预算与其他语言路径不变。候选 full `31221970026`、PR fast `31222386728`、merge fast `31222451794` 均通过，候选 SHA `6c6c040b095aadff18eea5f9f518ce50551fa8f7` Xcode/JUnit `10/10`，merge SHA `b6410f032d36e5f9205e15327107ca8069589c20` 复用候选 full；探针默认 skip，Koharu readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不声称质量提升。

## 0. 一句话总览

v3.182 日语竖排合成 line：短日语片段 → 同列／gap 门控形成 bounded line proxy → 该 proxy 替代被其覆盖的 axis bbox reread；原始 quad 仍进入 perspective path → 方向 fallback、映射／去重、布局、翻译与渲染。最多 24 line／16M warp 像素预算与其他路径不变。候选 full `31220601488`、PR fast `31221025113`、merge fast `31221074919` 均通过，候选 SHA `42ad3abf8deba67d11b4fd3a93b16a1f09756657` Xcode/JUnit `10/10`，merge SHA `fb97ce105e5ae2d8fdda3d2acae631c86513be02` 复用候选 full；探针默认 skip，Koharu readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不声称质量提升。

v3.181 日语竖排 line reread：四点 perspective line → 成功且无需方向 fallback 的结果登记为已覆盖 → 与其重叠比 `>= 0.72` 的轴对齐 line 跳过重复 OCR；弱／失败 perspective 保留轴对齐与方向 fallback → 映射、去重、布局、翻译与渲染。最多 24 line／16M warp 像素预算与其他路径不变。候选 full `31218314967`、PR fast `31218876431`、merge fast `31218932836` 均通过，候选 SHA `e24ce08b798b1f205a4d812e626d27ba801db1de` Xcode/JUnit `10/10`，merge SHA `1107998858e3879750cba8dc8a27248ad1497589` 复用候选 full；探针默认 skip，Koharu readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不声称质量提升。

v3.180 日语 perspective line warp：四点 line polygon → 按 bbox 裁剪源图 → 四点平移到局部坐标 → `CIPerspectiveCorrection` → 灰度／放大、90°／270° reread、映射与去重 → 布局、翻译与渲染；保留 24 line／16M 像素预算，其他语言与轴对齐路径不变。候选 full `31217320435`、PR fast `31217749775`、merge fast `31217813652` 均通过，候选 SHA `eb522b28c1e9649278342f227aaef03995d67a41` Xcode/JUnit `10/10`，merge SHA `54b4cf750615efe54962f4247c72003d6d04f761` 复用候选 full；探针默认 skip，Koharu readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不声称质量提升。

v3.179 日语 OCR 后处理：Vision／crop／line reread → 去空白、统一省略号、压缩 `.`／`・` → 再将 ASCII 标点映射为全角 → 日语候选融合、布局、翻译与渲染；普通语言与识别几何不变。候选 full `31216151856`、PR fast `31216723888`、merge fast `31216783591` 均通过，候选 SHA `c16e5593ef63113e2d3ba5ef1b72d7a09ee2396a` Xcode/JUnit `10/10`，merge SHA `5f3c0aa1f45d9cee9774db4d0020370666b69273` 复用候选 full；探针默认 skip，Koharu readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不声称质量提升。

v3.178 日语紧凑竖排 block crop：v3.177 compact direction reason → 标准高竖框或受限的 compact 尺寸门控 → 最多 16 个 block 进入 `crop_text_block_bbox` 对齐的 crop／预处理／方向 fallback → 坐标映射、去重、布局、翻译与渲染；标准候选与非日语边界不变。候选 full `31214729647`、PR fast `31215410769`、merge fast `31215485897` 均通过，候选 SHA `ec80c63d1b0d25903f0d462a020dec6bca768f94` Xcode/JUnit `10/10`，merge SHA `4f6aeca133c9684c6800ec795a9f0fac4f24fdca` 复用候选 full；探针默认 skip，Koharu readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不声称质量提升。

v3.177 日语紧凑竖排：日语 manga-order 偏好传入方向判定 → CJK 多字、`verticalRatio >= 1.35`、`height >= 0.022`、同列且无同行才标记 compact vertical run → 既有 Koharu 风格 block／line crop reread → 后处理、去重、布局、翻译与渲染；简中、非日语和旧门控不变。候选 full `31213076831`、PR fast `31213569259`、merge fast `31213642909` 均通过，候选 SHA `9777d167cca71deb753f5d0f721f6c2f9f2af48f` Xcode/JUnit `10/10`，merge SHA `f2c8a33ba66666a69a941d24fb5d8d78284b1695` 复用候选 full；探针默认 skip，Koharu readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不声称质量提升。

v3.176 日语竖排 perspective line：四点 warp → 90°／270° Vision reread → 按旋转图 x 轴分别正序／逆序拼接 observation，同一位置用 y 与日语评分稳定排序 → 后处理、去重、布局、翻译与渲染；无多 observation 或 warp 失败时安全回退，其他语言与整页路径不变。候选 full `31211585649`、PR fast `31212154910`、merge fast `31212217877` 均通过，候选 SHA `6a61068f292e4e842b570a455eb357bd5b9a7c40` Xcode/JUnit `10/10`，merge SHA `eaa523f4d29f8be9e7e2f16131bbc21a9363706f` 复用候选 full；探针默认 skip，Koharu readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不声称质量提升。

v3.175 日语竖排 crop：Vision block/line → 读取源图片像素尺寸并按 Koharu 字体大小推导 padding（base 8%、竖排水平 18%、垂直 12%，最小 2px）→ 映射回归一化 crop → 既有灰度化／放大、方向 fallback、去重与布局 → 翻译／渲染；无源尺寸时安全回退，其他语言与整页路径不变。候选 full `31210073265`、PR fast `31210705708`、merge fast `31210782269` 均通过，候选 SHA `e47014bb6cc68ec70029b3000d0b84c0156fe21e` Xcode/JUnit `10/10`，merge SHA `7b7a57b4d091fc3bd10305a6997e9dd24fba42ba` 复用候选 full；探针默认 skip，Koharu readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不声称质量提升。

v3.174 日语竖排聚类：Vision 高而窄的 line box → 保留同列／重叠门控并加入有界平均高度 gap 信号 → 形成更完整的文字块 → 既有 Koharu 风格 crop／line reread → 去重、布局、翻译与渲染；横排、非日语与整页 OCR 路径不变。候选 full `31208462786`、PR fast `31209161098`、merge fast `31209248983` 均通过，候选 SHA `49b987b3765e0df0c0511e30f955aa6aa7f487bf` Xcode/JUnit `10/10`，merge SHA `5efc690d0f8c3b41282518a8bc76d12559efa114` 复用候选 full；探针默认 skip，Koharu readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不声称质量提升。

v3.173 普通图片日语 OCR 在最终布局去重、竖排 block/line 候选和弱方向选择中使用独立的 `deduplicateJapaneseObservations` 评分：在既有置信度、长度、CJK 与旋转分数上加入有界脚本／标点 evidence；普通语言继续调用原 `deduplicateObservations`。候选 full `31206796785`、PR fast `31207387731`、merge fast `31207465845` 均通过，候选 SHA `d86f875d1040d69259b62b52754c73be3ccb59dd` Xcode/JUnit `10/10`，merge SHA `3fe6e719e064fe261f97530a7f16ff3b39ea4903` 复用候选 full；探针默认 skip，Koharu readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不声称质量提升。

v3.172 日语竖排碎片 line crop：Vision 近方形短日语片段 → vertical block 内按列中心／垂直连续间隙合成最多 24 条 line-region → 既有灰度化／有界放大 → 轴对齐 reread；原始四点 geometry 仍单独进入 perspective reread → 方向 fallback → 去重／布局 → 翻译／渲染；门控失败回退，普通语言与整页路径不变。候选 full `31204989011`、PR fast `31205608084`、merge fast `31205688629` 均通过，候选 SHA `c2e7edd13818c9c46b65d1aa318e4c91c3479c09` Xcode/JUnit `10/10`，merge SHA `fab5ddb6d9ebdaa3d4a9dd34bfcdf6c0f676c84c` 复用候选 full receipt；探针默认 skip，Koharu readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不声称日语 OCR／翻译质量提升。

v3.171 日语竖排 line crop：Vision line-region → Koharu 风格灰度化 → 4M 像素上限内优先 2× 放大 → 轴对齐／透视 reread；轴对齐传递实际 `cropScale`，透视按放大后像素计入每页 16M 预算 → 方向 fallback → 去重／布局 → 翻译／渲染；失败安全回退，普通语言与整页路径不变。候选 full `31203452238`、PR fast `31204110506`、merge fast `31204194868` 均通过，候选 SHA `9968f3083f9b19e9401dd9b48d9e35a480c99e9b` Xcode/JUnit `10/10`，merge SHA `df0145f9a2cb5dc5ea4ffdd515042f84cb8de108` 复用候选 full receipt；探针默认 skip，Koharu readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不声称日语 OCR／翻译质量提升。

v3.170 日语竖排 block crop：Vision 文字块候选 → Koharu 风格灰度化 → 在最多 4M 像素内优先 2× crop → 90°／270° reread 与 `cropScale` 坐标回映射 → 弱结果的既有 opposite-orientation fallback → 去重、布局、翻译与渲染；失败安全回退，普通语言与整页路径不变。候选 full `31201978062`、PR fast `31202618966`、merge fast `31202690968` 均通过，候选 SHA `0b2f011398457e410b366d1c10d80a902eecd173` Xcode/JUnit `10/10`，merge SHA `536b21f83670220ea5364b70badfe375a0df355c` 复用候选 full receipt；探针默认 skip，Koharu readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不声称日语 OCR／翻译质量提升。

v3.169 日语竖排 crop：按当前 90°／270° 方向做文字块／line reread → 对空、低脚本密度或低置信度结果，在文字块 8 次、line 12 次页级预算内用反方向 reread → 统一后处理与坐标回映射 → 既有去重、阅读顺序、翻译与渲染；非弱结果与非日语不增加额外 pass。候选 full `31200276655`、PR fast `31200973375`、merge fast `31201060977` 均通过，候选 SHA `bbe47bd89e4413580482b07e52799867c844ec64` Xcode/JUnit `10/10`，merge SHA `a2ad829bf519a2f5cec02d82cc6d7b40168c2d62` 复用候选 full receipt；探针默认 skip，Koharu readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不声称日语 OCR／翻译质量提升。

v3.168 日语识别：Vision 候选 → 置信度窗口内最多 5 个候选 → Koharu `post_process` 等价的空白／省略号／点号串／ASCII 全角化 → 日语脚本与标点密度融合 → 既有方向布局、翻译与渲染；非日语仍为 top-1。候选 full `31197172635`、PR fast `31197811891`、merge fast `31197884476` 均通过，候选 SHA `9438e3d40ffb133073921fc4f4a0e1de36cc042d` Xcode/JUnit `10/10`，merge SHA `033d66b5c62434e5685b1e8d7d1feebdfa90c15e` 复用候选 full receipt；探针默认 skip，Koharu readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不声称日语 OCR／翻译质量提升。

v3.167 日语／横排 OCR 的横向行分组改用 scale-aware 容差：以当前 observation 的中位文字框高度乘 `0.55`，再限制在 `0.012...0.04`，让不同缩放／字体下的同一行稳定聚合并避免相邻面板塌缩；RTL/LTR 排序和 OCR、翻译、导出路径不变。候选 full `31195627325`、PR fast `31196179149`、merge fast `31196269343` 均通过，候选 SHA `6c63dd0a5170a0fb230046d7d2129b26fd8dbb4d` Xcode/JUnit `10/10`，merge SHA `a0f1e72ea36be0932dae75fe774af1186ed29b1c` 复用候选 full receipt；探针默认 skip，Koharu readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不声称日语 OCR／翻译质量提升。

v3.166 日语竖排方向计数纳入 CJK 标点／半角片假名：单独 observation 仍需列邻居与无横排行邻居门控，随后进入既有竖排聚类和 crop reread。候选 full `31193812409`、PR fast `31194473761`、merge fast `31194535297` 均通过，候选 SHA `8c6dfe278a9644dd0dc37ffa5381a968dc7748c7` Xcode/JUnit `10/10`，merge SHA `0acfd7f62c9ecbe048c7630d0358c85dce325edb` 复用候选 full receipt；探针默认 skip，Koharu readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不声称日语 OCR／翻译质量提升。

v3.165 允许竖排 CJK 的短单字 observation 只有在列邻居、无横排行邻居且尺寸达标时才进入竖排布局与局部 crop reread，保留 Vision 单字列的 Koharu TextBox→crop 证据；其他方向边界不变。候选 full `31192480905`、PR fast `31193220150`、merge fast `31193292477` 均通过，候选 SHA `5f24c4b7d2de47a095ee15b19994087ebde4dff7` Xcode/JUnit `10/10`，merge SHA `631c4d25acacb6b0497e8c95dab41f9a22e6c266` 复用候选 full receipt；探针默认 skip，Koharu readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不声称日语 OCR／翻译质量提升。

v3.164 日语源图片的混合版面横排 OCR 通过 `prefersMangaReadingOrder` 开启漫画 RTL：行仍按 y 自上而下，同一横排行内按 x 右到左；默认 false 保留非日语左到右行为。候选 full `31190984866`、PR fast `31191645282`、merge fast `31191716497` 均通过，候选 SHA `7e584045f12fefa995866b7479db4cd440d52a03` Xcode/JUnit `10/10`，merge SHA `3943843d61f331630f7c6764f5639273aea4bd90` 复用候选 full receipt；探针默认 skip，Koharu readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不声称日语 OCR／翻译质量提升。

v3.163 普通图片日语竖排布局继续迁移 Koharu `sort_manga_reading_order` 的 Recursive XY-Cut：以文字块中位宽／高中位数估计动态空白阈值，递归按最大横／纵间隙切分，右侧面板优先、竖排列自上而下，并在无法切分时稳定回退；只作用于 `ImageOCRLayoutEngine` reading order。候选 full `31189049773`、PR fast `31189799793`、merge fast `31189875449` 均通过，候选 SHA `c37808634df8d87cfb9f24c22acadc472f71d3c0` Xcode/JUnit `10/10`，merge SHA `e93f3844c359214c0cdfe09cd609fb11c51b924d` 复用候选 full receipt；探针默认 skip，Koharu readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不声称日语 OCR／翻译质量提升。

v3.162 普通图片日语竖排 OCR 在 line-region hint 上继续迁移 Koharu 四点透视校正：字符范围四角 geometry 只用于最多 24 条 line crop 的 `CIPerspectiveCorrection` 与 2× 复读，request-level box 仍负责布局／去重，单条 4M／总计 16M 像素门控，失败回到轴对齐 crop，并穿过整页／局部旋转映射。候选 full `31186264941`、PR fast `31186901253`、merge fast `31186979637` 均通过，候选 SHA `8a8e653f953c233f5b0d28249bb9b324ef0baab3` Xcode/JUnit `10/10`，merge SHA `b1c272b9fea90e07967e21db082538be50c8b516` 复用候选 full receipt；探针默认 skip，Koharu readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不声称日语 OCR／翻译质量提升。

v3.161 普通图片日语竖排 OCR 使用 Vision 字符范围 bounds 作为更紧的 line-region crop hint，request-level box 仍负责布局／去重，整页旋转和 2× crop 都传递该 hint；缺失时回退原框。候选 full `31184241208`、PR fast `31184939184`、merge fast `31185021159` 均通过，候选 SHA `9164066706faed78494384d79ec1544d46084c20` Xcode/JUnit `10/10`，merge SHA `1eb026c2ce3df861b6efcc7ae9d61a5d08fd86ea` 复用候选 full receipt；探针默认 skip，Koharu readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不声称日语 OCR／翻译质量提升。

v3.160 普通图片日语竖排 OCR 在既有 block 候选上继续对齐 Koharu `extract_text_block_regions`：按重叠与纵向条件筛选最多 24 个 line-region proxy，方向感知扩边后 2× crop 复读，结果按缩放比例映射回原图并去重；没有 line polygons 时仅为保守 Vision 过渡层，不是模型替换。候选 full `31182335743`、PR fast `31183007517`、merge fast `31183084173` 均通过，候选 SHA `68c1c1b8eb1390b808204c3c16b7b1dbc72a28b9` Xcode/JUnit `10/10`，merge SHA `19b018101a4937474e2f3b030a1e24dc58807704` 复用候选 full receipt；探针默认 skip，Koharu readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不声称日语 OCR／翻译质量提升。

v3.159 普通图片日语源语言进入 Vision OCR 时，Store 状态文案会明确说明“识别日语文字，复查竖排方向与文字块位置”；其他语言继续使用通用 OCR 状态，View 仍消费同一个 `imageTranslationMessage`，不新增管线、Store 状态或持久化。候选 full `31180141884`、PR fast `31180615748`、merge fast `31180708039` 均通过，候选 SHA `f30fbab503ff9c694af0d4f2c123113b1802648d` Xcode/JUnit `10/10`，merge SHA `9c68b5c9f7e5e5d341a3cfaec1f764964b71b9f0` 复用候选 full receipt；探针默认 skip，Koharu readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不声称 OCR／翻译质量提升。
v3.158 普通图片日语 OCR 继续对齐 Koharu 的 `TextBoxes → crop_text_block_bbox → OCR` 分层：从既有竖排布局候选中最多选 16 个文字块，按已选 90°／270° 方向裁剪复读、映射回原图并去重，再进入最终布局；新增 `scripts/test-v3158-image-japanese-crop-ocr-contract.py`。候选 full `31178774530`、PR fast `31179342519`、merge fast `31179390133` 均通过，候选 SHA `ee21c07d5175b38b41161822043b7ce1bbeea3ff` Xcode/JUnit `10/10`，merge SHA `c940815a43e300685667d8b01888e53af910ec9c` 复用候选 full receipt；探针默认 skip，Koharu readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不声称 OCR／翻译质量提升。
v3.157 普通图片日语 OCR 在 v3.156 的方向复查上比较受限的 90°／270° 两个方向：两次 Vision 结果映射回原图后统一去重，再交给既有日语竖排／右到左布局；新增 `scripts/test-v3157-image-japanese-bidirectional-orientation-ocr-contract.py`。候选 full `31177442783`、PR fast `31177914749`、merge fast `31177971252` 均通过，候选 SHA `894c7063e18a6dc40ea047dca015e7cf73af8e65` Xcode/JUnit `10/10`，merge SHA `1266de53935525c1014ec0b4cbecb9b7f20b6e86` 复用候选 full receipt；探针默认 skip，Koharu readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不声称 OCR／翻译质量提升。
v3.156 普通图片日语 OCR 参考 Koharu 的检测／布局与识别分层，增加受限 90° 方向复查：用 `ja-JP/ja/en-US/en` profile 读取旋转图、将框映射回原图、去重后交给既有日语竖排／右到左布局；新增 `scripts/test-v3156-image-japanese-orientation-ocr-contract.py` 与 `test/jap.jpg` fixture。候选 full `31176163879`、PR fast `31176662793`、merge fast `31176739499` 均通过，候选 SHA `99a333a8297faf193c8058d7f919626bb17daf80` Xcode/JUnit `10/10`，merge SHA `7750c7e62b82cb952ab302b9afd206ecf15068dd` 复用候选 full receipt；探针默认 skip，Koharu readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不声称 OCR／翻译质量提升。
v3.155 普通图片没有可显示 OCR 文字块但当前图片可重试且没有待重试语言变更时，结果空态提供就地“重试当前图片”按钮与同名 VoiceOver action，直接复用 `store.retryImageTranslation`；重试语言已更新时保留上方状态入口，避免重复 action。只属于 View，不改变 Store、OCR、翻译、renderer/export、探针、metrics 或 `output`。候选 exact-SHA full `31173412868`、PR #219 fast `31173840102`、merge fast `31173897707` 均通过，候选 SHA `a6283b1be84ec4e6b227b6d5fbf74961a4fd108f` Xcode/JUnit `10/10`，merge SHA `2c26886ee6676c549b88ad48b0447e595c636a40` 复用候选 full receipt，真实 Koharu 工件仍缺失。
v3.154 普通图片空结果状态的可见标题与说明按 idle、读取／OCR／翻译进行中、translated、failed 动态分流；VoiceOver label/value/hint、重新识别 action 与按钮门控保持不变，只属于 View，不改变 Store、OCR、翻译、renderer/export、探针、metrics 或 `output`。候选 exact-SHA full `31171837188`、PR #218 fast `31172320096`、merge fast `31172393014` 均通过，候选 SHA `11028f3de4886aad18e911dd8dc3f60e6593ba9f` Xcode/JUnit `10/10`，merge SHA `b51ab8a880f3a1998a5a4e249e6c7113e0a3c451` 复用候选 full receipt，真实 Koharu 工件仍缺失。
v3.153 普通图片翻译已完成且没有可显示 OCR 文字块时，结果空态使用稳定的 VoiceOver focus identity；保留源图片且处于 `.translated` 时聚焦可操作空态，全部忽略空态优先，否则回到图片状态行，焦点仍受 revision 与 View 私有 generation guard 约束。只属于 View，不改变 Store、OCR、翻译、renderer/export、探针、metrics 或 `output`。候选 exact-SHA full `31170387940`、PR #217 fast `31170963538`、merge fast `31171022668` 均通过，候选 SHA `6c838ef220470753cb6abf4867babc48a6ea795c` Xcode/JUnit `10/10`，真实 Koharu 工件仍缺失。
v3.152 普通图片翻译完成但没有可显示 OCR 文字块时，结果空态显示受 `store.canRerunImageRecognition` 门控的“重新识别”按钮，复用既有 `store.rerunImageRecognition`，仍只属于 View。候选 exact-SHA full `31167004721`、PR #216 fast `31170006883`、merge fast `31170055419` 均通过，候选 SHA `0c08bfda4548b996a2e3bad86d2adde950276378` Xcode/JUnit `10/10`，真实 Koharu 工件仍缺失。
v3.151 Developer Console 的漫画探针无逐块结果状态提供就地“重新运行漫画覆盖翻译探针”按钮与同名 VoiceOver action；action 只在探针未运行时暴露，复用既有 `store.runMangaOverlayProbe`，仍只更新 report-only 探针诊断。候选 exact-SHA full `31165387991`、PR #215 fast `31165964091`、merge fast `31166051842` 均通过，候选 SHA `8579bdabc8f0dbbeafe19b4804cfedcea9dfbe04` Xcode/JUnit `10/10`，真实 Koharu 工件仍缺失。
v3.150 普通图片人工修正后的文字块在局部放大预览中提供可见“恢复 Vision OCR”按钮与同名 VoiceOver action；仅在 `isManuallyCorrected && canEdit` 时暴露，直接复用面板既有确认入口，锁定时保留禁用原因，仍只属于 View。候选 exact-SHA full `31163470178`、PR #214 fast `31164127307`、merge fast `31164207376` 均通过，候选 SHA `04cef3c01b802627366587dc1a3c76eddc534e3f` Xcode/JUnit `10/10`，真实 Koharu 工件仍缺失。
v3.149 普通图片“本次复查完成”空态的 VoiceOver“重新复查” action 只在 `canReviewImageTranslation` 可用时暴露；锁定时仍读出完成上下文和 `imageReviewUnavailableDetail`，保留可见按钮禁用边界，直接复用既有 `restartReviewQueue()`，仍只属于 View。候选 exact-SHA full `31161816278`、PR #213 fast `31162344568`、merge fast `31162426726` 均通过，候选 SHA `b0fc332c565fe501c8e2e939a086b79c142c9853` Xcode/JUnit `10/10`，真实 Koharu 工件仍缺失。
v3.148 普通图片全部 OCR 文字块被忽略时，空态 VoiceOver“恢复全部” action 只在 `canModifyImageTranslation` 可用时暴露；锁定时仍读出恢复范围和状态原因，保留可见按钮禁用边界，仍只属于 View。候选 exact-SHA full `31160052402`、PR #212 fast `31160532637`、merge fast `31160619661` 均通过，候选 Xcode/JUnit `10/10`，真实 Koharu 工件仍缺失。
v3.147 普通图片 OCR 修正 sheet 的“修正后的文字”输入框新增明确 VoiceOver label/value/hint，按空文本、实际修改、确认无误和保存中的状态说明边界；保存期间同时锁定输入与忽略 action，仍只属于 View。候选 exact-SHA full `31158590713`、PR #211 fast `31159215608`、merge fast `31159309690` 均通过，候选 Xcode/JUnit `10/10`，真实 Koharu 工件仍缺失。
v3.146 普通图片“已忽略 OCR 文字块”行的父级 VoiceOver 容器在可修改状态下提供同名“恢复”action，直接复用既有恢复回调；父级 hint 说明恢复会回到图片预览、导出和当前转录，需要复查时回到待复查队列，锁定时隐藏父级 action；只属于 View。候选 exact-SHA full `31157259172`、PR #210 fast `31157792746`、merge fast `31157872257` 均通过。
v3.145 普通图片文件导入的 VoiceOver hint 与照片入口保持一致：无图片时说明从文件首次选择，已有图片时说明更换当前图片并开始新的本机 OCR 与翻译；运行中继续说明选择新图片会取消当前任务并开始新任务，文件入口保持可用。只属于 View，不改变 OCR、翻译、renderer/export、探针、Koharu active gate、metrics 或 `output`。候选 exact-SHA full `31155971109`、PR #209 fast `31156530851`、merge fast `31156622662` 均通过。
v3.144 普通图片 OCR 的“没有可显示文字块”空态在翻译完成且源图片仍可重跑时提供同名 VoiceOver“重新识别”action，直接复用 Store `rerunImageRecognition()`；源文件不可重跑时不暴露 action，提示明确只重跑当前图片 Vision OCR 与翻译。只属于 View，不改变 OCR、翻译、renderer/export、探针、Koharu active gate、metrics 或 `output`。候选 exact-SHA full `31154791726`、PR #208 fast `31155305272`、merge fast `31155356211` 均通过。
v3.143 普通图片 OCR 结果行的 VoiceOver hint 动态列出当前真正暴露的修正、恢复和复查 action；锁定或不适用时不虚构 action，保留定位与几何不可用上下文。只属于 View，不改变 OCR、翻译、renderer/export、探针、Koharu active gate、metrics 或 `output`。候选 exact-SHA full `31153705887`、PR #207 fast `31154097383`、merge fast `31154147898` 均通过。
v3.142 普通图片风险 OCR 结果行在 `isReviewRequired && canReview` 时提供同名 VoiceOver“完成并继续复查／撤销本次复查”action，直接复用既有 `toggleReviewCompletion()`；非风险或锁定时隐藏 action，保留可见复查按钮与禁用原因。只属于 View，不改变 OCR、翻译、renderer/export、探针、Koharu active gate、metrics 或 `output`。候选 exact-SHA full `31152734900`、PR #206 fast `31153171846`、merge fast `31153229469` 均通过。
v3.141 已人工修正的普通图片 OCR 结果行在 `isManuallyCorrected && canEdit` 时提供同名 VoiceOver“恢复 Vision OCR”action，直接复用既有 `restoreVisionOCR()`；未修正或锁定时隐藏 action，保留可见恢复按钮与禁用原因。只属于 View，不改变 OCR、翻译、renderer/export、探针、Koharu active gate、metrics 或 `output`。候选 exact-SHA full `31151758844`、PR #205 fast `31152271664`、merge fast `31152319773` 均通过。
v3.140 普通图片 OCR 结果行在 `canEdit` 时提供同名 VoiceOver“修正识别文字”action，直接复用既有 `edit()`；锁定时隐藏 action，保留可见修正按钮、定位／焦点语义和 `modificationUnavailableHint`。只属于 View，不改变 OCR、翻译、renderer/export、探针、Koharu active gate、metrics 或 `output`。候选 exact-SHA full `31150859808`、PR #204 fast `31151298078`、merge fast `31151339355` 均通过。
v3.139 图片局部放大容器在对应邻居存在时提供同名 VoiceOver“上一个文字块／下一个文字块”action，直接复用既有 `selectPrevious()`／`selectNext()`；首尾或单项筛选时隐藏不可用 action，保留当前位置 value 与按钮 disabled hint。只属于 View，不改变 OCR、翻译、renderer/export、探针、Koharu active gate、metrics 或 `output`。候选 exact-SHA full `31149836170`、PR #203 fast `31150269494`、merge fast `31150318388` 均通过。
v3.138 图片局部放大容器在需要复查且 `canReview` 时提供同名 VoiceOver“完成并继续复查／重新加入待复查”action，直接复用既有 `toggleReviewCompletion()`；不需要复查或复查被锁定时不暴露 action，父级 hint 说明 `reviewUnavailableHint`。只属于 View，不改变 OCR、翻译、renderer/export、探针、Koharu active gate、metrics 或 `output`。候选 exact-SHA full `31148861374`、PR #202 fast `31149234166`、merge fast `31149285259` 均通过。
v3.137 图片局部放大容器在 `canEdit` 时提供同名 VoiceOver“修正识别文字”action，直接复用既有 OCR 修正入口；锁定时不暴露该 action，父级 hint 说明修改不可用原因。只属于 View，不改变 OCR、翻译、renderer/export、探针、Koharu active gate、metrics 或 `output`。候选 exact-SHA full `31147358078`、PR #201 fast `31147793085`、merge fast `31147924273` 均通过。
v3.136 图片局部放大预览容器提供同名 VoiceOver“关闭局部放大”action，关闭按钮 hint 明确返回当前文字块结果行；复用既有 View 私有焦点交接，不改变 OCR、翻译、renderer/export、探针、Koharu active gate、metrics 或 `output`。候选 exact-SHA full `31144595687`、PR #200 fast `31144958126`、merge fast `31144998556` 均通过。
v3.135 图片预览加载／失败状态提供动态 VoiceOver hint：失败明确“重试预览”只重建屏幕预览，加载说明完成后可定位文字块；只属于 View。候选 exact-SHA full `31143646549`、PR #199 fast `31144019839`、merge fast `31144057333` 均通过。
v3.134 图片预览失败状态在当前 revision 失败时提供同名 VoiceOver“重试预览”action，并复用既有 `retryPreview()`；只属于 View，仅重建屏幕预览，不重新 OCR/翻译。候选 exact-SHA full `31142629553`、PR #198 fast `31142975439`、merge fast `31143030561` 均通过。
v3.133 普通图片空预览与识别结果空态成为稳定 VoiceOver 上下文，分别读出当前没有图片、下一步本机 OCR／翻译边界和动态结果阶段；只属于 View，不改变 OCR、翻译、renderer/export、探针报告、Koharu active gate、metrics 或 `output`。候选 exact-SHA full `31140850232`、PR #197 fast `31141276534`、merge fast `31141320676` 均通过。
v3.132 普通图片所有 OCR 文字块都被忽略时，空态提供忽略数量、恢复边界和同名 VoiceOver“恢复全部”action；只显示一个受图片翻译完成／导出重绘门控的恢复入口，最后一次忽略后的焦点与终态都回到该空态。候选 exact-SHA full `31139110055`、PR #196 fast `31139576598`、merge fast `31139633331` 均通过。
v3.131 普通图片已忽略文字块提供确认后的批量恢复，按原始顺序还原并复用既有转录／导出重建与焦点路径；只在 `.translated` 且非导出重绘时可用。候选 full `31090186819`、PR #195 fast `31137606603`、merge fast `31137651196` 均通过。
v3.130 Developer Console 漫画探针已有逐块报告但筛选为空时，可直接“显示全部诊断”，VoiceOver 同样提供 action；只改 View 私有筛选并保留无文字块空态。候选 full `31088767018`、PR #194 fast `31089351045`、merge fast `31089424245` 均通过。
v3.129 普通图片筛选空态提供“显示全部结果”按钮与 VoiceOver action，恢复到全部文字块并复用既有 View focus path；不改变 OCR、翻译或 Store。候选 full `31087461275`、PR #193 fast `31088057693`、merge fast `31088114103` 均通过。
v3.128 普通图片 OCR 的复查完成空态提供完成／总风险块与筛选上下文，并允许 VoiceOver 直接重新复查；只复用既有 View action 与 Store gate。候选 full `31085406753`、PR #192 fast `31085987796`、merge fast `31086053876` 均通过。
v3.127 图片状态行按 share/export/image 失败优先级提供直接 VoiceOver retry action；只复用既有 Store 操作，不新增业务状态。候选 full `31084281958`、PR #191 fast `31084713250`、merge fast `31084803922` 均通过。
v3.126 普通图片导出重绘／分享失败时把 VoiceOver 焦点交给图片翻译状态行，准备／渲染中的状态变化不抢焦点；只消费 View 状态。候选 full `31082994159`、PR #190 fast `31083400009`、merge fast `31083557316` 均通过。
v3.125 普通图片文件选择／Pro 门控等直接失败在没有新 revision 时将 VoiceOver 焦点回到图片状态行；有 revision-scoped 终态请求时保持既有 OCR／翻译失败焦点路径，只消费 View 状态。候选 full `31081494834`、PR #189 fast `31081976028`、merge fast `31082019649` 均通过。
v3.124 清空普通图片后，在 revision 变化确认数据为空且状态 idle 时把 VoiceOver 焦点交给“等待图片”空态；新图片 loading 不抢焦点，只消费 View 状态。候选 full `31080208334`、PR #188 fast `31080768687`、merge fast `31080830286` 均通过。
v3.123 普通图片屏幕预览失败或开始重试时，把 VoiceOver 焦点交给稳定的预览状态行；只消费 View 状态，不改变 Store、OCR、翻译、renderer/export 或 Koharu active gate。候选 full `31079060685`、PR #187 fast `31079520917`、merge fast `31079590205` 均通过。
v3.122 普通图片 OCR 在读取／识别／翻译取消并转为 idle 时，把 VoiceOver 焦点交给图片翻译状态行；只消费 View 状态，不改变 Store、OCR、翻译、renderer/export 或 Koharu active gate。候选 full `31077891466`、PR #186 fast `31078311141`、merge fast `31078359581` 均通过。
v3.121 让普通图片 OCR 的失败／取消状态在源图片可用且没有待重试语言变更时提供受门控的“重试当前图片”VoiceOver action；已有待重试语言状态继续保留唯一 action，不进入 Store、OCR、翻译、renderer/export 或 Koharu active gate。候选 full `31076710802`、PR #185 fast `31077094866`、merge fast `31077152440` 均通过。
v3.120 让普通图片 OCR 的待重试语言状态提供受 `canRetryImageTranslation` 保护的 VoiceOver custom action，直接调用既有 Store retry；只属于 View 操作语义，不进入 Store、OCR、翻译、renderer/export 或 Koharu active gate。候选 full `31075361390`、PR #184 fast `31075697828`、merge fast `31075745893` 均通过。
v3.119 的普通图片 OCR 在失败／取消后实际生成待重试语言摘要时，将 VoiceOver 焦点交给该状态行；焦点 handoff 复用既有 revision-scoped generation，只属于 View，不触发重试，也不进入 Store、OCR、翻译、renderer/export 或 Koharu active gate。候选 full `31074379707`、PR #183 fast `31074819588`、merge fast `31074863470` 均通过。
v3.118 的漫画探针报告到达时，如果既有 readiness report 明确阻断真实 Koharu 四件套、契约修正或真实 detector 来源声明，先由共享 generation requester 聚焦“Koharu 工件就绪状态”；非阻断 readiness 与筛选切换继续聚焦逐块结果。该 View-only handoff 不进入 Store、OCR、翻译、renderer/export 或 Koharu active gate。候选 full `31073337578`、PR #182 fast `31073688262`、merge fast `31073828173` 均通过。
v3.117 的漫画探针诊断筛选变化先递增 View 私有 expansion reset token，收起旧 block 详情，再由 v3.116 generation requester 聚焦新筛选结果；不进入 Store、OCR、翻译、renderer/export 或 Koharu active gate。候选 full `31072107788`、PR #181 fast `31072405558`、merge fast `31072447592` 均通过。
v3.116 的 Developer Console 漫画探针诊断焦点由 `MangaProbeSection` 的 View 私有 generation 统一仲裁：筛选、重跑终态和逐块展开／收起只保留最新 VoiceOver handoff；新 probe loading 使旧请求失效，不进入 Store、OCR、翻译、renderer/export 或 Koharu active gate。候选 full `31071423891`、PR #180 fast `31071714254`、merge fast `31071752236` 均通过。
v3.115 普通图片 OCR 的焦点 handoff 使用 View 私有 generation + revision guard，快速筛选／定位／复查时旧异步请求不会覆盖最新动作；不进入 Store、OCR、翻译或 renderer/export。候选 full `31070650744`、手动 full `31070655111`、PR #179 fast `31070940503`、merge fast `31070976672` 均通过。
v3.114 的漫画探针逐块诊断在新 loading 时用 View 私有 reset token 收起旧详情并抑制旧焦点回抢，结果行 VoiceOver 明确展开／收起状态；不进入 Store 或探针链路。候选 full `31069913494`、手动 full `31069918901`、PR #178 fast `31070264175`、merge fast `31070323190` 均通过。
v3.113 的 Developer Console 漫画探针逐块诊断在展开后把 VoiceOver 焦点交给稳定的详细诊断容器，收起后回到原结果行；详情复用既有 report-only 风险、下一步和执行边界，不进入 Store 或探针链路。候选 full `31068769954`、手动 full `31068778764`、PR #177 fast `31069311041`、merge fast `31069349841` 均通过。
v3.112 的普通图片 OCR 在新 `imageTranslationRevision` 进入 `.translated` 或 `.failed` 后恢复 VoiceOver 焦点：有 blocks 时交给当前筛选的首个结果行，没有 blocks 时交给动态图片状态行；revision guard 阻止旧任务在后续图片开始后抢焦点。该 View-only 改动不进入 Store、OCR、翻译、renderer/export 或 Koharu active gate。候选 full `31067968394`、PR #176 fast `31068324104`、merge fast `31068365757` 均通过。
v3.111 的 Developer Console 漫画探针重跑在报告写入后恢复 VoiceOver 焦点：有 blocks 时交给当前筛选的首个诊断 block，没有 blocks 时交给“未生成逐块诊断”状态；loading 仍清除旧筛选焦点。该 View-only handoff 不新增 Store、持久化、OCR、翻译、renderer/export 或探针报告状态，不改变 Koharu active gate、metrics 或 output。新增终态焦点合同；候选 full `31067283530`、PR #175 fast `31067583454`、merge fast `31067629934` 均通过。
v3.110 的普通图片 OCR 筛选焦点使用 View 私有意图仲裁：用户筛选变化聚焦首个可见结果，程序化复查／恢复／预览选择变化保留显式行、预览或完成态焦点；revision 重置清除待处理意图并保留空态回退。新增合同与历史合同兼容更新不进入 Store、OCR、翻译、renderer/export 或 Koharu active gate。候选 full `31066203170`、PR #174 fast `31066589776`、merge fast `31066628727` 均通过。

v3.108 的 Developer Console 漫画诊断筛选在切换到有结果的类别后，将 VoiceOver 焦点交给第一个可见 block；筛选只读既有报告，空筛选仍交给可操作空态，焦点 identity 只存在于 View。候选 full `31063355633`、PR #172 fast `31063761078`、merge fast `31063805810` 均通过，探针默认 skip，Koharu readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`。

v3.107 的图片 OCR 与漫画诊断筛选器在无结果时把 VoiceOver 焦点交给可操作空态：读出当前筛选、`0 / 总数` 与恢复筛选路径；焦点与空态只在 View 内处理，不进入 Store、持久化、OCR、翻译、renderer/export、探针报告或 Koharu active gate。候选 full `31020576411`、PR fast `31062338507`、merge fast `31062372361` 均通过。

v3.106 的普通图片 OCR 与漫画探针筛选器共用动态 VoiceOver 筛选上下文：当前类别、显示数／总数和图片复查已完成／剩余数只在 View 计算，不进入 Store，也不改变 OCR、翻译、renderer/export、探针报告或 Koharu active gate。候选 full `31017118790`、PR fast `31017809552`、merge fast `31017909329` 均通过。

v3.105 的 Developer Console 漫画探针诊断总览只读消费既有收敛报告的闭环快照，汇总开放／已闭环／要求停止工单、block path/work-item ledger 规模、状态 breakdown 和真实外部工件边界；快照同时用于状态 tone、可复制 summary 与 VoiceOver，不进入 Store、OCR、翻译、renderer/export 或 Koharu active gate。

v3.104 的 Developer Console 逐块漫画探针行只读消费既有 `MangaKoharuArtifactConvergenceReport` 的 block path、开放工单与执行边界，统一显示首阻断、结构瓶颈、真实工件等待、工单状态和 CI-fast/full/外部工件边界；同一上下文进入 action summary、结果行和 VoiceOver，未闭环工单或 report-only 边界保持 warning/仅报告，不进入 Store、OCR、翻译、renderer/export 或 Koharu active gate。

v3.103 的 Developer Console 漫画探针诊断总览只读消费 native promotion、artifact contract dry-run、artifact identity reconciliation 与 convergence 报告，显示晋级 verdict、dry-run/active export 边界、真实工件与 CI manifest 身份对账和未闭环工单；该摘要同时用于状态行、可复制文本和 VoiceOver，不进入 Store、OCR、翻译、renderer/export 或 Koharu active gate。

v3.102 的 Developer Console 逐块漫画探针行继续只读消费 pipeline resolver、work-order、外部工件请求包和 native replay 的执行数据，显示目标执行项、首阻断、CI-fast/full/外部工件门与禁止本地调参边界；执行边界、建议、依据和真实工件门共用视觉/VoiceOver 摘要，不进入 Store、OCR、翻译、renderer/export 或 Koharu active gate。

v3.101 的 Developer Console 逐块漫画探针行继续只读消费既有 bottleneck、model-floor、render-fit 与 artifact-DAG 证据，显示“为什么这样分流”及首阻断阶段；推荐下一步、诊断依据和真实工件门控共用视觉/VoiceOver 摘要，不进入 Store、OCR、翻译、renderer/export 或 Koharu active gate。

v3.100 的 Developer Console 逐块漫画探针行只读消费既有 internal/floor/render/DAG report ledger，显示当前 block 的推荐下一步，并在存在 readiness 阻断时同步显示真实 Koharu 工件门控；视觉与 VoiceOver 共用该摘要，不进入 Store、OCR、翻译、renderer/export 或 Koharu active gate。

v3.99 的 Developer Console 逐块漫画探针行只读消费当前 `MangaOverlayProbeReport` 的 OCR、翻译和布局风险集合；视觉标签与 VoiceOver value/hint 共用同一集合，帮助解释筛选结果，但不进入 Store、OCR、翻译、renderer/export 或 Koharu active gate。

当前项目主链路是：用户输入文本、音频或图片，`TranslationSessionStore` 统一调度本地状态、Apple OCR/Speech、Mock/Local 模型和持久化；漫画探针独立读取 `test/1.png`，生成 OCR、翻译、覆盖合成和诊断报告。

```text
用户操作 / test 固定素材
  -> SwiftUI 页面
  -> TranslationSessionStore
  -> OCR / Speech / Model Adapter
  -> 质量判定 / 诊断汇总
  -> UI 展示 / state.json / output 调试产物
```

v3.72 的 Developer Console readiness 摘要仍只读探针已有报告：v1 `summary-only` 工件显示 v2 mask payload／topology“未要求”，真实 v2 工件继续显示实际失败与阻塞；解释后的状态同时进入 VoiceOver hint 和可复制摘要。该 View-only/report-only 分支不创建 active 工件、不改变 readiness gate、普通图片 OCR、翻译、renderer/export、漫画探针或 Koharu 主路径。

v3.73 的图片复查列表对空 OCR 的已忽略 block 提供稳定显示与无障碍回退：视觉行显示“空 OCR 原文”，VoiceOver label 显示“空”，恢复 action 与焦点身份仍由既有 View/Store 边界管理，不新增业务状态或改变识别路径。

v3.74 统一普通图片 OCR 结果行与完整图片预览的旁贴／覆盖文字块空 OCR 回退：原文为空时显示“空 OCR 原文”，旁贴／覆盖仍以非空译文优先；该 View-only 变化不新增 Store／持久化状态，不改变 OCR、翻译、renderer/export、复查、探针或 Koharu 主路径。
v3.75 让 OCR 修正参考图与完整图片局部聚焦预览在原文为空时仍有稳定 VoiceOver value，统一使用“空”回退，非空原文保持原样；该 View-only 变化不新增 Store／持久化状态，不改变 OCR、翻译、renderer/export、复查、探针或 Koharu 主路径。
v3.76 将完整图片局部聚焦预览的“局部放大”视觉角标标为 accessibility hidden，避免与父容器稳定的定位 label/value 重复朗读；所有操作按钮、选择状态和 OCR 上下文不变。该 View-only 变化不新增 Store／持久化状态，不改变 OCR、翻译、renderer/export、复查、探针或 Koharu 主路径。
v3.77 在无效或过期 OCR 框的局部预览中隐藏不可用状态子视图，统一由父容器的 VoiceOver hint 说明“局部预览不可用；仍可关闭、编辑 OCR 原文或切换文字块”，避免 contain 层级重复朗读；操作和 Store ownership 不变。
v3.78 关闭完整图片局部聚焦预览时，使用既有 `reviewRowAccessibilityFocusID` 将 VoiceOver 焦点交回对应 OCR 结果行；该交接只在 View 私有状态中运行，不新增 Store／持久化状态，不改变 OCR、翻译、renderer/export、复查、探针或 Koharu 主路径。

v3.79 完整图片局部聚焦预览的上一个／下一个文字块仍只按当前筛选后的 View 顺序移动选择；选中目标后立即调用 `moveReviewAccessibilityFocus(to: reviewPreviewAccessibilityFocusID(targetBlockID))`，让 VoiceOver 焦点跟随新的预览容器。该交接不进入 Store 或产品处理链路，位置 value、首尾 disabled 边界和既有复查状态保持不变；同步的 v3.14 合同只放宽等价的局部 target ID 赋值写法。

v3.80 当 `reviewFilter` 隐藏当前选中的图片 OCR block 时，`clearHiddenReviewSelection()` 清除 View 私有选择并将焦点交给首个可见结果行；没有可见待复查 block 时，按既有完成态或筛选器焦点 identity 交接。该路径不写 Store、不重新 OCR／翻译，避免筛选切换后 VoiceOver 停留在已卸载的局部预览容器。

v3.81 结果行或完整图片覆盖块选中 OCR block 后，toggleSelection(of:) 与 selectBlockFromPreview(_:) 将 VoiceOver 焦点交给对应局部预览；取消定位时回到对应结果行。焦点 handoff 只在 View 私有 AccessibilityFocusState 中运行，不进入 Store、OCR、翻译或 renderer/export 链路。

v3.82 漫画覆盖探针在失败 fallback 含显式换行时，`wrappedLines` 按段落保留换行与空行，fit plan、碰撞检测和 CoreText 绘制共享同一行预算；该路径只改善探针诊断布局，不进入普通图片 OCR、翻译、Store、ground truth、Koharu active artifact 或质量基线。

v3.83 的 `makeKoharuRenderSpriteFitPlannerReport` 直接复用 `wrappedLines(text, fontSize:maxFontSize, maxWidth:rect.width)` 的换行结果，按真实行数计算预算，并将 block／render lock 的 `renderTextTruncated` 进入 failure fallback 风险。这样 block 5 的诊断会如实显示 `12 lines / fontBudgetOverflowRisk / failureFallbackLongTextRisk`，不再把实际截断报告为 `currentSpriteFits`。该 report-only 修复不进入普通图片 OCR、翻译、Store、ground truth、生产 renderer/export、Koharu active artifact 或质量基线。

v3.84 的 `makeKoharuRenderSpriteFitPlannerReport` 继续复用既有渲染锁证据：`renderMinFontSizeReached` 进入逐 block ledger、decision signal、`renderMinFontSizeReachedBlocks` 汇总和 `G-render-sprite-fit-min-font-evidence` report-only gate；block 5 的 ci-fast 报告因此明确记录最小字号压力与实际截断。该诊断只读并不提升或改变 OCR、翻译、Store、ground truth、生产 renderer/export、Koharu active artifact gate、metrics 或 output。

v3.85 的 `MangaKoharuRenderRegressionLockReport` 继续从既有 block/render lock 汇总 `renderMinFontSizeReached`，并把该证据贯穿逐 block decision trace、`renderMinFontSizeReachedBlocks`、report-only gate 与 Developer Console 摘要；只改善诊断可观测性，不进入 OCR、翻译、Store、ground truth、生产 renderer/export、Koharu active artifact 或质量基线。

v3.86 修正漫画探针 render-lock 输出 ledger 的构建时序：`probe_report.json` 与最终重写的 `1_ocr_probe_text.txt` 现在使用 planned-final-write 状态，避免报告在重写前把必需 OCR 文本误判为空；成功 ci-fast 报告因此同时给出 `coreOutputFilesNonEmpty=true` 与 `G-render-core-png-retained=passed`，真实 block 5 截断仍单独阻塞 `G-render-no-text-truncation`。该 report-only 路径不改变 OCR、翻译、Store、ground truth、生产 renderer/export、Koharu active artifact gate、metrics 或 output。

v3.87 让 render-lock 输出检查把 planned final write 的推荐动作与实际状态对齐：`plannedFinalReportWrite` 与 `plannedFinalOCRTextRewrite` 在 `nonEmpty=true` 时返回 `keepReportOnly`，缺失或未检查输出才返回 `inspectRenderOutputExport`；新增 v3.87 合同并接入 Koharu changed-file/full 路由。该 report-only 修复不改变 OCR、翻译、Store、ground truth、生产 renderer/export、Koharu active artifact gate、metrics 或 output。云端 ci-fast 仍保留 block 5 的实际截断与 `openRenderIssueDetected`，不能作为质量提升证据。

v3.88 将 `G-render-core-png-retained` 的成功动作与 `outputFileChecks` 对齐：完整且非空的 retained 输出只读报告，缺失/空输出才进入导出检查；新增 v3.88 合同和 CI 路由。该诊断不改变 OCR、翻译、renderer/export 或 Koharu active artifact gate，ci-fast 仍保留 block 5 截断风险。

v3.89 让 Developer Console 的 `outputFiles` 摘要直接汇总 required 输出的 `recommendedAction`（如 `keepReportOnly=5`），与核心输出 gate 共用既有 report-only 状态；新增 v3.89 合同和 CI 路由。该诊断不改变 OCR、翻译、renderer/export 或 Koharu active artifact gate，ci-fast 仍保留 block 5 截断风险和 `manifestMissing` readiness。

v3.90 漫画探针失败覆盖只在显示层压缩 OCR continuation 的显式换行，保留完整 OCR fallback 与 `翻译失败` 标记；安全布局、fit planner 和实际覆盖绘制消费同一显示变换，ci-fast 的 block 5 从截断风险变为 `renderTextTruncated=false`、`renderMinFontSizeReached=false`，render lock 为 `renderStableWithProxyBoundaries`。该 probe-render 诊断修复不改变 OCR、翻译、Store、普通图片 renderer/export、ground truth、Koharu active artifact gate 或质量基线；真实四件套仍缺失。
v3.91 Developer Console 新增只读漫画探针“诊断分流”上下文：消费既有 `MangaOverlayProbeReport` 的 OCR／翻译模型／覆盖布局／Koharu readiness 信号，展示 baseline／variant floor 与下一步，并让失败 block 显示 failureCategory 及 VoiceOver 分流。该 View-only 改动不新增 Store／持久化、不调用第二次探针、不改变 OCR、翻译 prompt／model、renderer/export、metrics 或 output；full `30886955217`、同 SHA ci-fast `30887582600`、PR fast `30888608909`、merge fast `30888676363` 对精确 SHA/receipt 均通过。ci-fast 仍保持 13 blocks／12 failures、render lock stable、model floor `promptVariantRegresses` 和 readiness `manifestMissing / stopUntilArtifactsProvided`，真实 Koharu 四件套、Speech corpus 与竖排图片 corpus 仍缺失。
v3.92 图片 OCR 复查在既有待复查并集之外提供低置信与方向待定的 View 本地筛选，且忽略文字块后沿当前筛选保持定位；Developer Console 的漫画逐块结果提供全部／失败／OCR／翻译／布局只读诊断筛选。两者均不新增 Store／持久化、不改变 OCR、翻译、renderer/export、探针报告或主流程。full `30889811326`、PR fast `30890241624`、merge fast `30890322575` 对 exact SHA/receipt 均通过；push 未运行漫画探针，真实 Koharu 四件套仍缺失。

v3.93 当 `imageTranslationRevision` 变化时，图片复查 View 将本地筛选恢复为“全部”，并清除旧 block 选择与 VoiceOver 焦点，覆盖新图、重试、重新识别和清空，避免旧风险筛选造成空结果误导。该改动只消费既有 Store revision 信号，不新增 Store／持久化或改变 OCR、翻译、预览、导出、漫画探针与质量基线；full `30890823578`、PR fast `30891431628`、merge fast `30891485989` 均通过，真实 Koharu 四件套仍缺失。

v3.94 漫画探针在每次运行前清空旧 report/blocks；缺少 bundle `test/1.png` 时重建 App 沙盒 `Output` 并把清理数量/成功状态写入失败报告，避免旧 blocks 或旧 PNG/JSON 污染当前诊断。清理失败会显式标记旧输出可能残留。该修复不改变 OCR、翻译、renderer/export、Koharu active gate 或质量基线；full `30893309273`、PR fast `30893920011`、merge fast `30893993759` 均通过，真实四件套仍缺失。

v3.95 当漫画探针报告没有逐块 OCR blocks 时，Developer Console 显示明确的无 blocks 状态并隐藏诊断筛选器；VoiceOver 复用现有探针消息并说明 `test/1.png`／Output 清理后的重试范围。存在 blocks 时保持既有只读诊断筛选和逐块上下文。该 View-only 修复不新增 Store／持久化、不重跑探针或改变 OCR、翻译、renderer/export、Koharu gate 与质量基线；full `30984932342`、PR fast `30985360673`、merge fast `30985413482` 均通过，真实 Koharu 四件套仍缺失。

v3.96 `MangaProbeDiagnosticTriageSummary` 在 active Koharu artifact gate 被阻断时优先显示 warning；即使 blocks 全部通过，也不会用 success 色暗示 shadow OCR 已就绪，只有非阻断且 report 通过才显示 success。该 View-only/report-only 修复不新增 Store／持久化、不调用探针或改变 OCR、翻译、renderer/export 与质量基线；full `30985776084`、PR fast `30986258687`、merge fast `30986307343` 均通过，真实四件套仍缺失。

v3.97 漫画探针布局筛选和 triage 摘要复用同一只读 render risk 集合，补上 fit planner 的字号预算、sprite 包含、相邻 block 重叠、失败覆盖风险及 render-lock 证据，避免顶层渲染错误为空时隐藏 report-only 压力。该改动不改变 OCR、翻译、renderer/export、Store 或 Koharu gate；ci-fast `30986469563` 观察到 10/7/6 风险，full `30987210261`、PR fast `30987676638`、merge fast `30987725142` 均通过，真实四件套仍缺失。

v3.98 漫画探针 OCR 与翻译诊断筛选、triage 摘要共享两个只读 risk set，统一消费 diagnostics、model-floor、translation failureCategory 与 OCR 疑似证据；该改动只修正报告分流一致性，不改变 OCR、翻译、renderer/export、Store 或 Koharu gate。候选 full `30988262491`、PR fast `30988802078`、merge fast `30988876405` 均通过，真实四件套仍缺失。

## 1. 核心模块
### 1.1 SwiftUI App 入口
职责：创建全局 `TranslationSessionStore` 并注入 UI。

输入：

- App 启动。

输出：

- `ContentView().environmentObject(store)`。

关键文件：

- `AITRANS/App/AITRANSApp.swift`

禁止：

- 不要在 UI 层创建第二套 store。

### 1.2 UI 层
职责：提供文本、图片、音频、历史、设置、模型、Pro 和开发调试入口。

输入：

- 用户输入文本。
- 图片或音频文件选择。
- 模型和提示词配置。
- 开发页 raw 探针和漫画探针按钮。

输出：

- 调用 `TranslationSessionStore` 方法。
- 展示翻译、历史、模型状态、OCR 块、探针报告和错误。
- 音频页展示 Apple Speech 本机识别能力、识别运行摘要、识别文本、译文和取消入口；checking、recognizing、translating 三种运行态均可取消。

关键文件：

- `AITRANS/Views/ContentView.swift`
- `AITRANS/Views/AppTheme.swift`
- `AITRANS/Views/AppComponents.swift`
- `AITRANS/Views/TextTranslationView.swift`
- `AITRANS/Views/TextWorkspaceBackground.swift`
- `AITRANS/Views/TextWorkspacePasteButton.swift`
- `AITRANS/Views/ImageTranslationViews.swift`
- `AITRANS/Views/AudioTranslationView.swift`
- `AITRANS/Views/HistoryView.swift`
- `AITRANS/Views/PromptLibraryView.swift`
- `AITRANS/Views/SettingsView.swift`
- `AITRANS/Views/ModelManagementView.swift`
- `AITRANS/Views/DeveloperConsoleView.swift`
- `AITRANS/Views/ProFeatureViews.swift`
- `AITRANS/Views/AppPreviewSupport.swift`

当前正式版本：`3.154`。普通图片的 OCR blocks 在 OCR 完成后的逐块翻译期间仍可查看、定位和显示局部预览，但改变结果或复查进度的入口必须等待 `imageTranslationState == .translated`。`canModifyImageTranslation` 还要求不在导出重绘期，统一保护 OCR 修正、恢复 Vision OCR、恢复已忽略 block 与旁贴／覆盖切换；`canReviewImageTranslation` 统一保护开始／继续／重启复查及完成／撤销。Store 的 mark／reopen／reset 会二次拒收未完成状态；成功 OCR 修正先恢复 `.translated`，再沿用既有自动复查，避免已可见的中间 blocks 提前持久化会话进度。v3.43 的局部预览前后导航继续只更新 View 私有选择：可用按钮向 VoiceOver 说明定位上一个／下一个文字块，筛选首尾的 disabled 按钮明确说明已到第一个／最后一个文字块；结果行主定位提示按当前是否已选中切换为取消定位或在图片预览中定位。v3.44 在同一对前后按钮上追加当前位置 accessibility value：有筛选位置时读出“当前位置 1 / 3”一类上下文，无位置时读出“未显示筛选位置”，仍只消费既有 `positionText`。v3.45 让完整图片预览中的 OCR 覆盖块也复用结果行的定位提示，已定位时读出取消此文字块在图片中的定位，未定位时读出在图片预览中定位此文字块，保持图片入口和列表入口语义一致。v3.46 让图片预览加载与失败卡片提供稳定的 VoiceOver label/value，重试提示明确只重建屏幕预览、不重新 OCR 或翻译。v3.47 让照片／文件、取消、重试、重新识别、导出和清空按钮说明具体影响范围，PhotosPicker 会动态说明是首次选择还是替换当前图片；v3.48 让完整图片预览容器汇总识别块数量、待复查数量和当前定位位置，并隐藏重复朗读的原始背景图；这些 hint/value 只改善 View 可理解性，不改变 Store、OCR、翻译、renderer/export、探针或质量基线。v3.49 让图片输入语言与目标语言菜单的 VoiceOver hint 按运行中、Pro 门槛、无图片、已完成和失败／取消重试状态分流：运行中明确需完成或取消，Pro 锁定说明不会污染文本页语言，已完成输入语言说明会重新识别和翻译、目标语言说明会重新翻译当前图片，失败／取消说明下一次重试使用新语言；选回当前内容语言会撤销待重试差异。v3.50 让照片与文件导入按钮在读取、OCR 或翻译进行中明确说明选择新图片会取消当前任务并开始新的本机 OCR 与翻译，同时保持有意设计的替换入口与 Store run-id 隔离。v3.51 让图片状态行成为单一的 VoiceOver 状态元素，动态读出 `statusTitle` 与 `statusDetail`，并按载入、Vision OCR、逐块翻译、导出重绘、分享准备、失败和完成分流下一步操作提示；仍只消费既有 Store 状态，不新增 Store／持久化状态，也不改变 OCR、翻译、renderer/export、探针或质量基线。v3.52 让图片结果行主 Button 的 VoiceOver value 在定位状态之外读出 OCR 置信度、低置信／方向待定、人工修正、待复查／本次已复查和等待翻译；该改动只改善 View 语义，不新增 Store／持久化状态，也不改变 OCR、翻译、renderer/export、探针或质量基线。v3.53 让已忽略 OCR 文字块恢复行成为稳定的 VoiceOver 上下文，读出不在图片预览／导出／转录、是否保留现有译文和恢复是否可用，同时保留恢复按钮的禁用原因与焦点交接；只改善 View 语义，不新增 Store／持久化或改变 OCR、翻译、renderer/export、探针和质量基线。v3.54 修复图片状态行 VoiceOver value 的实际实现回归：改用动态 `statusTitle`／`statusDetail` 插值，避免朗读字面量占位符；v3.51 合同同步锁定真实插值。该版本只改善 View 语义，不新增 Store／持久化状态，不改变 Vision OCR、模型翻译、renderer/export、漫画探针、Koharu 主路径、ground truth、metrics 或 output。v3.55 让开发控制台的 Koharu readiness 状态行提供稳定 label/value/hint：缺少真实四件套时直接提示 `test/koharu_artifacts/`、manifest/TextBoxes/BubbleMask/SegmentMask 文件名和 shadow-only 边界；只读消费既有 readiness report，不调用第二次探针、不写 Store，也不改变普通图片 OCR、翻译、renderer/export 或 active artifact gate。v3.37 的首尾空白规范化、v3.24 的弃改保护、v3.25 确认无误分流、v3.38 键盘清焦点、v3.39 滚动收起、v3.40 保存期输入锁定和 v3.30–v3.35 revision-scoped `onDismiss` 焦点交接均保持不变。本版不创建 Store／持久化状态，不改 Vision OCR、模型、renderer/export、漫画探针、Koharu 主路径或质量基线。v3.36 的 `MangaKoharuArtifactReadinessSummary` 仍只读既有 report，ready 仍只代表下次探针可尝试 shadow OCR，不是 App-side coverage、真机 UI 或质量证据。v3.26 CI receipt 传播规则不变；真实竖排图片 corpus、Speech corpus 与 Koharu 真实四件套运行态仍待提供。 v3.56 让漫画覆盖翻译探针状态行按阶段提供 VoiceOver 状态 value/hint，运行按钮明确 test/1.png、Output 和只影响探针诊断的范围，不新增 Store／持久化状态。 v3.57 让漫画探针逐块结果按 block index、PASS/FAIL、OCR 原文、置信度、译文和失败详情提供 VoiceOver 上下文，展开提示保持探针诊断边界，不新增 Store／持久化状态。 v3.58 让图片复查结果行提供稳定的 VoiceOver label/value：label 明确图片文字块与 OCR 原文，value 区分等待翻译与真实译文并处理空 OCR 回退；只改善 View 语义，不新增 Store／持久化状态，不改变 Vision OCR、模型翻译、renderer/export、漫画探针、Koharu 或质量基线。 v3.59 让完整图片预览的覆盖文字块与图片复查结果行共用稳定的 VoiceOver label“图片文字块 + OCR 原文”，空 OCR 回退为“空”，并保留既有等待翻译／译文 value、定位 hint 和选中状态；该改动只改善 View 语义，不新增 Store／持久化状态，不改变选择、Vision OCR、模型翻译、renderer/export、漫画探针、Koharu 主路径或质量基线。 v3.60 让完整图片预览的覆盖文字块与图片复查结果行对齐 VoiceOver value：读出 OCR 置信度（clamp 到 0–100%）、人工修正、低置信／方向待定、待复查／本次已复查及等待翻译／译文；相邻与替换模式共用这套上下文，只改善 View 语义，不新增 Store／持久化状态，不改变选择、Vision OCR、模型翻译、renderer/export、漫画探针、Koharu 主路径或质量基线。

v3.61 的图片复查结果行和完整图片预览继续消费 `ImageTranslationBlock` 已有的 `sourceDirection`／`directionConfidence`：已判定的横排／竖排会显示并进入 VoiceOver value，方向置信度先做有限值检查和 0–100% clamp；结果行的 OCR 置信度显示也做同样的 0–100% 边界保护。该改动只改善复查上下文和异常数据下的显示稳定性，不新增 Store／持久化状态，不改变 Vision OCR、翻译、renderer/export、漫画探针、Koharu 或质量基线。

v3.48 的完整图片预览继续遍历完整 `store.imageTranslationBlocks`，但在 ready 容器上增加 View 私有 VoiceOver label/value/hint：汇总文字块总数、风险块扣除当前图片会话 `reviewedBlockIDs` 后的待复查数和当前定位位置；原始背景 `Image` 设为 `.accessibilityHidden(true)`，避免重复朗读。该上下文只改善可操作性，不创建 Store／持久化状态，也不改变 OCR、翻译、选择、renderer/export 或探针路径。

v3.62 的图片识别结果摘要复用 `ImageOCRResultSummary.horizontalBlockCount` 与 `verticalBlockCount`，在方向风险之外显示横排／竖排 block 数，帮助用户快速判断当前图片的方向分布。该改动只改善摘要的 View 语义，不新增 Store／持久化状态，不重新运行 Vision OCR／模型翻译，也不改变 renderer/export、漫画探针、Koharu 或质量基线。

v3.63 将图片“识别结果”摘要设为一个稳定的无障碍 header：value 继续消费 `store.imageTranslationSummary`，hint 仅根据现有 blocks、翻译状态和待复查集合说明选择图片、查看定位或更新复查进度的下一步。该 View 语义不新增 Store／持久化状态，不重新运行 Vision OCR／模型翻译，也不改变 renderer/export、漫画探针、Koharu 或质量基线。

v3.64 将图片 OCR 置信度边界集中为安全归一化：布局引擎先清理 observation confidence，`ImageOCRResultSummary` 再用同一语义计算平均值与低置信集合，结果行／覆盖层也复用该边界显示百分比。非有限值按 0 处理并保留复查风险，避免 NaN 传播或 `Int` 转换崩溃；不改变 OCR 候选、翻译、renderer/export、漫画探针、Koharu 或质量基线。

v3.65 让图片 OCR 修正 sheet 的低置信度提示复用 ImageOCRResultSummary.normalizedConfidence，在百分比格式化前处理 NaN/∞ 与越界值；仍只改善 View 显示，不新增 Store／持久化状态，不改变 OCR、翻译、renderer/export、漫画探针、Koharu 或质量基线。

v3.66 在 Vision OCR 输出进入布局前统一做有限、正面积、单位坐标整矩形归一化；布局引擎再次过滤异常 observation，保证覆盖、局部定位和阅读排序只消费有效几何。该安全边界不改变 OCR 候选、翻译、renderer/export、漫画探针、Koharu 或质量基线；无效 geometry 会被安全丢弃而不是生成越界 block。

v3.67 让 `NormalizedImageRect.normalizedToUnit()` 成为旧会话／外部解码 block 的消费边界：完整图片覆盖和局部定位对无效框不生成 View，导出 renderer 对无效框返回空 rect；有效框保持既有裁剪和布局语义，不写回持久化，也不改变 OCR、翻译、漫画探针、Koharu 或质量基线。

当前布局：

- iPhone 使用文本、图片、音频、历史、设置五入口 `TabView`。
- iPad 使用 `NavigationSplitView`；宽内容优先输入/输出或主检查区/状态区并排，空间不足时通过 `ViewThatFits` 降为单列。
- 文本页头和模型状态位于工作区 `ScrollView` 外的顶部 safe-area inset；键盘自动聚焦只滚动语言栏与输入/输出工作区，页头不会进入系统状态栏区域。
- 文本首页根层使用独立 `TextWorkspaceBackground`：静态冷中性渐变、稳定技术网格和输入到译文的导向线路只服务文本页，不改变其他页面的 `AppCanvasBackground`。
- 文本输入继续直接绑定 `store.draftText`。系统 `PasteButton(payloadType: String.self)` 只在用户点击时接收纯文本：空输入直接写入，已有输入换行追加，不读取或改写剪贴板后台状态，不自动触发翻译。
- 文本页持有唯一 `FocusState`；keyboard toolbar 的“完成”、翻译、新会话和离开文本 Tab 都会先结束焦点。翻译随后仍调用 `store.submitDraft`，没有新增第二套 draft 或业务 store。
- compact-width 文本页在 XXL Dynamic Type 起或输入已聚焦时，才在根 `VStack` 中把 48pt 净空放在 `ScrollView` 之后，使大字号内容与键盘“完成”区域终止于浮动 Tab Bar 上方；标准字号且键盘关闭时不插入该净空，首屏保留完整粘贴与翻译动作。该机制不是内容尾部 padding，也不依赖会被浮动栏覆盖的 bottom safe-area inset。
- `TextWorkspacePasteButton` 内部的真实系统 `PasteButton` 继续承担纯文本粘贴、隐私授权和兼容内容禁用语义；不可点击的实底中文 `Label("粘贴", systemImage: "doc.on.clipboard")` 覆盖系统 locale 标签，不绕开系统粘贴 API。
- `AppTheme` 提供语义颜色、间距、圆角、动效、触控和宽度 token；`AppComponents` 提供页头、区段、状态、按钮、空状态、指标和页面宽度原语。
- 日间/夜间颜色来自 `Assets.xcassets` 的 luminosity variants；`AppAppearance` 通过 `AppStorage` 选择跟随系统、日间或夜间，不进入业务 `state.json`。
- 所有业务按钮只调用 store 公开方法；UI 不直接操作 `state.json`、模型 runtime、Speech task、Vision OCR 或漫画探针服务。
- OCR 修正 sheet 的首尾空白归一化仅存在于 View 私有 `normalizedCorrectedOriginal`：它把 clean dismissal、discard protection、确认无误／重译文案和 Store 输入对齐；同一 sheet 的 `correctedOriginalFocused` 也仅在 View 内控制多行输入与键盘“完成”，取消、忽略确认、保存前会清焦点。两者都不把 UI dirty／键盘 state 写入 Store，也不把无语义变化送进模型。
- 漫画探针报告生成后，开发控制台的 Koharu readiness 摘要只读取 `report.externalArtifactReadinessReport`：ready / missing / invalid 状态和可复制缺件／nextAction 用于协调真实四件套，不直接访问 artifact 目录、不触发新 probe；它始终标为 shadow-only，不改变主 OCR、翻译、覆盖图、`blockPassed`、`currentBlockSource`、metrics 或 `output/`。
- 实时录音保留触控按住手势，同时提供默认 accessibility action；VoiceOver / Voice Control 激活会在 `beginProLiveSpeechCapture` 与 `endProLiveSpeechCapture` 之间切换。
- 设置页持有显式 `NavigationPath`；`isDeveloperModeEnabled` 关闭时清空 path，开发控制台不能在权限关闭后继续停留或操作。
- `AppPreviewScenario` 通过临时 URL 和 `performsStartupWork=false` 隔离预览，不恢复或持久化生产数据。DEBUG CI 可用 `AITRANS_UI_EVIDENCE_SCENARIO` 复现 14 张运行态证据，其中两个 wide iPad 场景分别覆盖文本空态和图片成功/风险复查态；`audioRecognizing` 设置 capturing 状态覆盖 Reduce Motion，`audioTranslating` 设置非空 transcript + translating 状态覆盖取消翻译入口，生产启动不读取这些场景。
- `AITRANS/Views/ProFeatureViews.swift`
- `AITRANS/Views/AppTheme.swift`

禁止：

- 不要绕过 store 直接读写持久化 JSON 或调用模型。
- 不要把开发页 raw 输出清洗成普通译文。

### 1.3 TranslationSessionStore
职责：统一管理状态、持久化、模型选择、文本/图片/音频翻译、开发探针和漫画探针。

输入：

- UI 事件。
- OCR/Speech 结果。
- Mock 或 Local 模型输出。
- `test/` 固定素材和输出报告。

输出：

- Published UI 状态。
- `Application Support/AITRANS/state.json`。
- `output/probe_report.json` 相关报告模型。
- 诊断汇总和质量判定结果。
- `speechRecognitionRunSummary`：记录音频文件或实时麦克风识别的模式、语言、离线要求、耗时、词数、分段数、平均置信度、最终文本和失败原因。
- `speechQualityProbeReport`：记录 corpus/manifest/audio 身份、Apple Speech 最终文本、WER/CER、延迟、分段、置信度和失败分类；参考文本只在识别完成后进入纯评测器。

关键文件：

- `AITRANS/Services/TranslationSessionStore.swift`

禁止：

- 不要在其他模块重复实现模型选择、质量判定或持久化入口。
- 不要把 ground truth 引入生产候选选择。

### 1.4 模型适配层
职责：统一 Mock 和 Local 生成接口。

输入：

- `ModelGenerationRequest`
- 当前语言、提示词、采样参数和任务类型。

输出：

- `ModelGenerationResult`
- `RawModelProbeResult`

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/MockGemmaService.swift`
- `AITRANS/Services/GemmaLocalService.swift`
- `AITRANS/Services/LlamaRuntime.swift`
- `AITRANS/Services/LocalModelDownloadService.swift`

规则：

- 普通用户翻译和 summary 走 sampled 解码。
- 漫画探针、raw 诊断、clean text、batch 对照和纠错翻译对照走 deterministic 解码。
- 当前内置 Gemma 270M 不作为质量基准。

禁止：

- 不要提交 GGUF 模型文件。
- 不要把 raw 探针结果伪装成普通 UI 成功。

### 1.5 普通图片 OCR 翻译
职责：对用户选图做 Vision OCR，并按 bbox 展示译文。

输入：

- 用户选择的图片数据。
- 用户在图片页选择的输入语言和目标语言。

输出：

- `ImageTranslationBlock`
- 识别结果摘要由 `ImageOCRResultSummary` 从当前 blocks 计算：显示已翻译/总块数、夹取到 `0...1` 后的平均 Vision 置信度、低于 `50%` 的块数，以及竖排与 unknown 方向计数。空结果不虚构平均值。成功图片在 Store-owned 原图仍存在时提供“重新识别”，复用当前内容的输入/目标语言凭据并走既有 task ID、render/share 失效和源文件保留链路；View 不读文件或直接启动 OCR。
- 检查列表可在“全部 / 待复查”间切换。待复查是低于 `50%` 或方向为 nil / unknown 的并集，重叠块只计一次且保留原始顺序；行内以图标和文字展示具体原因。筛选仅是 View 私有展示状态，图片预览、覆盖、翻译、导出和分享继续使用当前活动的 `imageTranslationBlocks`；只有 v3.29 经确认的误识别忽略才会通过 Store 改变这个活动集合，绝不由筛选隐式删块。
- 检查列表行可切换 View 私有 selected block ID；选中行显示取景框标记，图片预览仅对相同 ID 的完整产品 block 增加边框。图片 revision 变化会清除选择；切到“待复查”后若选中块被隐藏也会清除。该联动不写 Store、不筛预览 blocks、不改变导出或持久化。
- OCR 完成后的逐块翻译期间，截图、blocks、选择、定位和局部预览保持可读，方便用户跟进中间结果；但 `canModifyImageTranslation` 只在 `.translated && !isRenderingExport` 时开放修正、恢复 Vision OCR、恢复已忽略 block 与覆盖方式，`canReviewImageTranslation` 只在 `.translated` 时开放开始／继续／重启、完成／撤销复查。v3.42 在存在活动 blocks 且任一动作仍锁定时显示只读警示状态行；覆盖方式、复查、局部预览、结果行和忽略恢复的禁用 VoiceOver hint 统一复用 `imageModificationUnavailableDetail`／`imageReviewUnavailableDetail`。v3.43 让局部预览前后按钮的 VoiceOver hint 随序列边界变化：可移动时说明定位上一个／下一个文字块，首尾 disabled 时说明当前已是筛选结果中的第一个／最后一个文字块；结果行主定位 hint 也随 `isSelected` 切换为取消此文字块定位或在图片预览中定位。v3.44 让这两个导航按钮的 accessibility value 同步读出既有 `positionText`（例如当前位置 1 / 3），无位置时明确说明未显示筛选位置。v3.45 让完整图片预览中的 OCR 覆盖按钮复用结果行的定位 hint，图片入口与列表入口听到同一套已定位／未定位操作语义。v3.46 让加载/失败卡片提供可访问状态 label/value，重试 hint 明确只生成屏幕预览，不会重新 OCR 或翻译。v3.47 让图片命令栏的照片／文件、取消、重试、重新识别、导出和清空按钮明确声明作用域，照片选择器还会区分首次选择与替换图片。提示按 loading／recognizing／translating／failed／export rendering 分流，逐块翻译明确仍可查看／定位但不能提交；这些 View 私有文案不写入 Store。Store 的 `markImageTranslationBlockReviewed`、`reopenImageTranslationBlockReview` 与 `resetImageTranslationReviewProgress` 也会拒收非 `.translated`，形成 UI 与业务两层边界。
- 在完整 `.translated` 时，风险结果行把定位与复查拆成两个同级 Button：主区域只切换定位，独立 44pt 图标动作直接完成并沿现有队列定位下一块，或撤销后把该块放回队列。入口在尚未完成任何块时显示“开始复查”，有进度时显示“继续复查”；风险原因与已复查状态纵向排列，避免窄 inspector 和 Dynamic Type 横向挤压。当前图片的已复查 block ID 由 Store 的内存状态统一持有，面板重建后不丢失；新图、取消和清空会重置，绝不写入持久化。View 仍只决定筛选、队列位置和展示焦点。
- 连续复查使用 View 私有 `AccessibilityFocusState<String?>`，并为结果行、局部放大和完成态分配不同 focus ID。开始/重启队列后焦点进入当前局部放大；行级快速动作保持在下一结果行，局部放大动作保持在下一块放大窗，撤销回到同来源当前块，最后一块完成则聚焦“本次复查完成”。焦点发布先 yield 一次并核对图片 revision，旧图片任务不得抢回焦点；只有焦点本身不进入 Store 或持久化。
- 每个 OCR 结果行提供独立 44pt 人工修正按钮，但只有完整 `.translated` 且未导出重绘才可打开。编辑 sheet 对空白输入前置禁用，保存时阻止重复提交和交互式关闭；View 只把 block ID 与修正文本交给 Store。Store 只调用一次目标块 sampled 翻译，并在回写前同时核对 correction ID、图片 task ID、block ID 和旧原文快照。失败时不改 block、transcript 或当前导出；成功时原子替换原文与译文、清除保存中标记、恢复 `.translated` 后再标记当前图片的人工修正状态和自动复查、同步对应 transcript，随后撤销旧 export/share 并复用 render ID 生命周期按当前覆盖模式重绘。新图片、清空和取消都会使旧 correction 失效；人工修正不写回 Vision OCR，也不进入漫画探针或 ground truth 路径。
- OCR 修正 sheet 会把当前图片的既有 `imageTranslationData` 交给 `ImagePreviewService` 生成最大边 2048px 的临时本地预览，再复用局部放大的 16:9 裁切和 bbox 几何显示当前文字块周边；黄色框、可读标签与 VoiceOver value 明确识别区域。预览 loading / unavailable 只影响这张对照图，不能阻止编辑、确认无误或现有的单块重译。低于 50% 置信度或方向 nil / unknown 时，sheet 复用 `ImageOCRResultSummary` 显示相应复查原因和“仅重译当前块”边界；该展示不新增 Store 状态、不调用 Vision OCR、不读取 Koharu artifact、不改 renderer / export / transcript / ground truth。
- 首次成功人工修正时，Store 只在当前图片内按 block ID 保存一份私有 Vision OCR 基线（原文、初始译文与几何/方向证据）；后续修正不覆盖该基线。已人工修正的结果行出现独立 44pt “恢复 Vision OCR”动作，恢复不调用模型，要求当前图片处于完成态且没有 correction in flight。成功后恢复完整基线 block、移除人工修正标记与当前图片会话的已复查标记、同步当前图片 transcript、撤销旧 export/share 并重绘；新图片和清空会丢弃基线。恢复风险块只会在确认 dialog 已关闭且 revision 仍匹配后把 VoiceOver 焦点回到结果行，避免把旧复查结论带回原 OCR。
- 点击“恢复 Vision OCR”先仅把当前 block 写入 `ImageTranslationPanel` 的 View 私有待确认状态；dialog 清楚说明会移除本次人工修正，取消不调用 Store、不改变任何图片状态。确认先核验待确认 block 仍匹配，再调用既有恢复方法；成功后只暂存结果行 focus ID 与当前 revision，保留 confirmation target 直到 `confirmationDialog` 关闭时 binding 回写。binding 清理 target 后只有 revision 一致才复用既有 yield 后焦点发布器；取消没有 pending 目标，图片 revision 变化会一并清空选择、编辑、待确认、pending 和焦点，旧 dialog 不得指向新图片。
- v3.29 的 OCR 修正 sheet 还提供“忽略此文字块”破坏性确认，明确说明未保存修正不会保存、该块会退出本次图片预览／导出／当前转录，且可在检查区恢复。忽略与检查区恢复同样只在完整 `.translated` 且未导出重绘时开放。确认后 View 只触发 Store：Store 以 block ID 保存当前完整 block、初始 OCR 顺序、人工修正标记和私有 Vision 基线，再从活动 blocks、已修正／已复查集合及基线映射中移除；同步当前图片 transcript、撤销旧 export/share 并重绘。恢复操作按初始排序插回 block，恢复原人工修正基线但不恢复“已复查”结论，风险块重新进入队列；所有活动块被忽略时移除当前图片 transcript 行并由既有 renderer 导出原图。忽略快照只在当前图片会话内保存，新图和清空会丢弃，绝不进入 `state.json`、Vision OCR、模型翻译、漫画探针或 Koharu 路径。
- v3.30 把 OCR 修正 sheet 成功后的 VoiceOver 焦点交接固定在 sheet 完整关闭之后：成功忽略保留原有“下一活动／待复查行，否则已忽略行”的目标；待复查队列中的成功修正保留原有“下一行／完成态”目标。View 私有的 pending focus 同时记录当前 `imageTranslationRevision`，`onDismiss` 只有在 revision 一致时才清空 pending 并复用既有 `moveReviewAccessibilityFocus`；图片 revision 变化会先清空 sheet、pending 与已发布焦点。该机制不新增 Store、持久化、OCR、翻译、renderer/export 或探针状态。
- v3.31 继续补齐成功人工修正的非队列返回：`completeReviewAfterCorrection` 先确认 block 仍在当前活动集合；仅当筛选为“待复查”、当前 block 属于风险集合且 Store 已标为已复查时才沿用下一行／完成态。非风险 block 和“全部”筛选下的风险 block 则保持当前选择，并通过同一个 revision-checked、sheet `onDismiss` handoff 回到已更新结果行。该 fallback 不改变 Store、复查集合、OCR、模型调用、转录、导出或探针路径。
- v3.33 补齐修正 sheet 的非成功退出：`beginCorrection` 在呈现 sheet 前先登记该 block 的结果行作为同一 View 私有 pending handoff 的回退。无修改取消、明确放弃未保存修正和允许的交互式关闭不修改 Store，因此关闭后的 revision 校验会把焦点带回发起行；成功确认／单块重译或忽略在关闭前覆盖此回退，继续使用既有下一块、完成态或忽略行。该规则不新增持久化、Vision OCR、模型、renderer/export、漫画探针或 Koharu 状态。
- 选中 block 时，预览从当前最大边 2048px 的缩略图裁切 16:9 局部放大窗；裁切范围至少覆盖 bbox 宽高的 1.8 倍，并以归一化宽 16%、高 10% 为下限，再夹取在顶左原点图片范围内。放大窗以至少 24pt 的警示色框再次标出原 bbox，提供命名明确的 44pt 关闭命令；v3.34 在关闭按钮下再提供可访问的 44pt “修正识别文字”铅笔入口。v3.41 让这个入口与结果行共享 `canModifyImageTranslation`：只有完整 translated、未导出重绘且 block 仍有效时才会登记 v3.33 的同一局部预览关闭回退并呈现既有 sheet；结果行 `beginCorrection` 保留结果行回退。快捷修正不重新解码 Store 原图、不调用 OCR / 翻译、不进入 renderer、导出或持久化；取消／放弃／无修改关闭仍经 `onDismiss` 返回对应发起位置，成功／忽略继续覆盖为既有队列或结果目标。
- 外层图片页使用单一 `ScrollViewReader`，`ImageTranslationPanel` 根部提供唯一 workspace anchor。结果行从未选中切到新 block 后才滚动到该 anchor；点击同一行取消选择不滚动。系统 Reduce Motion 开启时直接定位，否则只使用 `AppTheme.Motion.standard`。局部放大窗显示当前 block 在“全部/待复查”可见序列中的位置，并提供命名明确的 44pt 上一个/下一个按钮；导航按该序列移动，首尾按钮同时禁用和降调，不越界、不绕回、不改筛选或完整 blocks。
- 旁贴或覆盖预览与同模式 PNG 导出；Vision OCR bbox、SwiftUI 预览和导出 renderer 统一使用图片顶左原点坐标。活动文字块为空但当前图片仍存在（即 v3.29 全部块被用户忽略）时，renderer 仍必须安全绘制并发布原图，不得保留旧导出或产生空白状态。后台 render 只写 render ID 独占 staging PNG，已完成图片切换模式会使旧导出失效并按 render ID / 图片 task ID / mode 验明身份后发布 `aitrans-export-<render UUID>-<base>-translated.png` 稳定文件，旧 detached render 不得覆盖新任务。覆盖模式重渲染公开 `idle / rendering / failed` 状态；rendering 时 Store 与 Picker 双重拒绝重复切换，当前失败显示 danger 并提供同模式重试，无 staging URL 也必须进入可重试失败。新任务、清空或其他内容失效会取消 render Task、更新 render ID 并复位状态。启动时会扫描 `Application Support/ImageTranslations` 直属文件，分账接管带 Store marker 的稳定导出、`<task UUID>-<name>` 输入副本和 `.<base>-translated-<render UUID>.staging.png`，清理上次异常退出残留；普通后缀文件、wrong-kind、目录外、嵌套、escape、symlink 和 dangling symlink 一律拒绝。新任务、清空或模式重渲染会撤销公开 export URL 并删除当前 Store-owned 稳定导出；正常 input/staging 清理同样必须携带可信 workspace 与对应文件类型，删除失败也登记 orphan ownership。所有删除失败项都在后续生命周期继续重试。分享前由 Store 在 `ImageTranslationShares/<share UUID>/` 创建人类可读 `<base>-translated.png` 硬链接或副本，并公开 request-scoped `idle / preparing / failed` 状态；准备中禁用重复导出，当前请求失败覆盖翻译成功色调。Store request ID 与 View presentation ID 共同拒绝晚到结果和旧 Task 的 `nil` 回写，dismiss / export 失效 / View 离开与启动恢复统一清理分享目录并复位反馈，删除失败保留 ownership。
- 任务启动时固定输入/目标语言，并分别记录 actual-content 与 pending-Retry 凭据；只要 content 凭据尚未被 clear，从 `.loading` 到失败/取消即使图片 data/blocks 为空，结果标题和菜单回退也继续使用任务实际语言，不受跨页全局语言漂移影响。失败或取消且 Store-owned source 仍可重试时，菜单只在选择与 actual-content 不同时写入独立 pending 字段并显示“重试语言已更新”；选回 actual-content 会把对应 pending 归一化为 `nil`，两项均无差异时提示消失，不会改写或误标屏幕上保留的 OCR/译文。Retry 优先消费 pending，再回退 actual-content，任务开始即清空 pending。clear 同时清空两组凭据，cancel 保留 actual-content。已完成图片选择不同输入语言会从沙盒原图重新 OCR + 翻译，选择不同目标语言会重新翻译；运行中菜单禁用且 Store 拒绝改写本次凭据。
- 图片输入语言选择先检查 `isProUnlocked`；免费模式的非当前菜单项显示 `lock.fill`，拒绝时只更新 Store-owned 反馈并由菜单显示 Alert，不得修改跨页 `sourceLanguage`、content 或 pending。VoiceOver hint 同步说明 Pro 门槛。目标语言继续由 `selectTargetLanguage` / `canUseLanguage` 判定，英语、中文等免费目标不增加额外图片 Pro 门槛。
- 图片来源入口先调用 Store-owned `requestImageTranslationAccess()`。只有 Pro 模式才实例化 `PhotosPicker` 并提供 file importer 动作；免费模式显示两个 `lock.fill` 命令并用 Alert 展示 Store 反馈，不进入系统照片或文件选择流程。`translateImage(from:)` 与 `translateImageTransfer` 的底层 Pro guard 继续作为纵深防线。
- 图片清空命令先显示附着于 `ImageCommandBar` 的破坏性确认，明确列出当前图片、识别结果、译文和导出文件；取消不调用 Store，只有确认按钮调用一次既有 `clearImageTranslation()`，其 task/source/export/share 清理边界不变。
- 图片预览不再在 SwiftUI task 中通过 `UIImage(data:)` 解压 Store 原始 Data。`ImagePreviewService` 使用 `Task.detached` + ImageIO 生成最大边 2048px 的已缓存 `CGImage`，应用 EXIF transform 且不缓存完整 source；外层 task 取消会取消后台任务。View 同时记录 preview revision，只有与当前 `imageTranslationRevision` 一致时才显示；数据已载入但预览未就绪时显示准备状态，生成失败时可只递增本地 attempt 重试预览，不重跑 OCR / 翻译。Store 原始 Data、OCR、覆盖坐标与导出输入保持不变。
- 普通图片 OCR 对每个 observation 记录 `horizontal / vertical / unknown` 方向证据。只有日语/中文 prior、bbox 高宽比至少 `1.6`、高度至少 `0.035`，并且包含至少两个 CJK 字符或具有同列邻居且没有近同行邻居时，才进入竖排路径；孤立单字高框、同行 CJK 碎片及非 CJK 高框继续走横排/unknown fallback。横排按上到下、行内左到右聚类；竖排按列从右到左、列内上到下聚类，两种方向不会互相合并。方向、置信度与 reason 随 `ImageTranslationBlock` 保留，不改变漫画探针链路。

关键文件：

- `AITRANS/Services/VisionOCRService.swift`
- `AITRANS/Views/ImageTranslationViews.swift`
- `AITRANS/Services/TranslationSessionStore.swift`

禁止：

- 不要把漫画探针专用真值、纠错或质量统计混入普通图片生产路径。

### 1.6 音频识别和翻译
职责：通过 Apple Speech 做本机语音识别，再把识别文本交给统一模型翻译入口。

输入：

- 用户选择的音频文件。
- Pro 页长按麦克风采集的实时音频。
- 当前源语言的 Speech locale 和本机识别能力。

输出：

- `lastRecognizedSpeechText` 或 `proLiveTranscriptText`。
- 翻译后的 `TranscriptLine`。
- `speechRecognitionRunSummary`，用于 UI 展示模式、locale、本机识别要求、耗时、词数、分段数、置信度和错误。

关键文件：

- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Views/ContentView.swift`
- `AITRANS/Views/ProFeatureViews.swift`

规则：

- 文件识别和实时识别都强制 `requiresOnDeviceRecognition = true`。
- UI 只调用 store 方法，不直接创建 Speech recognizer。
- 识别中和翻译中状态分开展示；用户可取消正在检查、识别或翻译的音频任务。
- 每次识别生成独立 run ID；实时语音翻译会续接一个新的翻译 run token。授权、Speech result/error、模型翻译和 summary 回调只有在 run ID 仍匹配且 Task 未取消时才能更新 store。
- `speechTranslationTask` 由 store 持有。取消先失效 run ID，再取消 Speech recognition / translation Task；新 run 在生成新 token 前取消并清空旧翻译 Task，避免旧 defer 或旧回调污染立即重试。
- 麦克风权限 `await` 返回后必须复验 run ID 与 capture request；模型翻译 `await` 返回后必须在 transcript、summary、状态或错误写入前复验 Speech 所有权。

禁止：

- 不要把 Apple Speech 结果绕过 store 直接写入历史。
- 不要把未授权、设备不支持或空识别文本伪装成成功。

### 1.6.1 语音识别质量探针
职责：对版本化真实音频 corpus 运行 Apple 本机 Speech，并以确定性算法生成可审计质量报告，不参与产品识别候选选择。

输入：

- `test/speech_corpus/manifest.json`。
- 同目录真实音频；每项声明 SHA256、字节数、locale 和参考 transcript。

输出：

- `Output/speech_quality_report.json`。
- `Output/speech_quality_report.txt`。
- 英文等空格分词语言的词级 WER，以及所有语言的 CER、延迟、分段、平均置信度和失败 breakdown。

关键文件：

- `AITRANS/Models/SpeechQualityModels.swift`
- `AITRANS/Services/SpeechQualityEvaluator.swift`
- `AITRANS/Services/SpeechQualityProbeService.swift`
- `scripts/validate-speech-corpus.py`

规则：

- `TranslationSessionStore` 持有探针状态、run ID 和取消入口；UI 不直接调用服务。
- runner 强制 `requiresOnDeviceRecognition = true`，逐项先校验音频身份。
- 参考 transcript 只传给识别完成后的 evaluator，不传给 `SFSpeechURLRecognitionRequest`。
- 中文、日文没有稳定词分割时 `wordErrorRate = nil`，只报告 CER。
- corpus 缺失时报告 `manifestMissing` / `qualityExecuted=false`，不产生质量结论。

### 1.7 漫画覆盖翻译探针
职责：固定读取 bundle 内 `test/1.png`，跑 OCR、翻译、覆盖绘制和诊断报告。

输入：

- `test/1.png`
- `test/1.ground_truth.json`
- 当前模型引擎和英译中提示词。

输出：

- `Application Support/AITRANS/Output/`
- 项目根 `output/` 导出副本。
- `probe_report.json`
- `clean_text_diagnostic.json`
- `1_ocr_probe_text.txt`
- 核心 PNG：`1_debug_boxes.png`、`1_translated_overlay.png`。
- `full` 模式还输出多张诊断 PNG，包括 `1_probe_contact_sheet.png`。

关键文件：

- `AITRANS/Services/MangaOverlayProbeService.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Models/TranscriptModels.swift`
- `scripts/export-probe-output.sh`

当前主流程：

```text
test/1.png
  -> 裁掉浏览器 UI / 广告 / 底部导航
  -> 内容区 2x 放大
  -> 0/90/180/270 Vision OCR
  -> OCR candidates
  -> 气泡候选检测和 bubbleID 归属
  -> 同 bubble 合并，跨 bubble 拒绝
  -> whole-page OCR blocks
  -> bubble-first OCR candidates
  -> ground-truth-free 融合选择和去重
  -> fused OCR blocks
  -> post-fusion 重复/碎片清理
  -> bubble 分割审计诊断
  -> BubbleMask 轻量子区域诊断
  -> BubbleMask 实例 ID 近似、mask-safe layout 和渲染 mask collision 诊断
  -> BubbleMask 归属修正诊断和保守 split candidate
  -> pre-crop TextBox plan artifact（TextRegion crop 前生成，shadow-only）
  -> TextRegion crop OCR 候选诊断和 split / corrected bubble / subregion / bubble / content / mask coverage 审计
  -> ground-truth-free crop 护栏选择
  -> TextBox / SegmentMask crop 后派生诊断和 failure attribution
  -> 自适应 crop 二次 OCR 诊断
  -> 确定性 OCR 纠错对照
  -> 逐块 Local/Mock 翻译
  -> clean text / batch / whole-page / bubble-first / slice OCR 对照
  -> Translation Model Floor 对照矩阵（clean text baseline + strict prompt variant，report-only）
  -> glyph mask / 背景估计 / 安全布局 / 离屏碰撞检查
  -> TextRegion crop shadow 实验矩阵（control + pre-crop plan 候选，不替换主输入）
  -> TextBox plan 失败归因与晋级门槛审计（解释 blockers，不替换主输入）
  -> line-level TextBox / deskew shadow 验证（仅目标块，不替换主输入）
  -> external artifact readiness gate（真实 TextBoxes / BubbleMask / SegmentMask 输入解析、校验、App 侧 identity receipt、sourceImageSHA256 match 和阻塞报告）
  -> external TextBoxes shadow OCR（仅 readiness ready 时执行；v2.0 稳定最大基数匹配保证 block / TextBox 一对一；v2.1 把 OCR outcome 与 assignment geometry 分账，weak / Bubble unknown 可执行 shadow OCR但不能关闭 gate；每块最多 1 个 externalArtifact.textBoxCrop，不替换主输入）
  -> external TextBox orientation-aware shadow OCR（真实 artifact ready 后对竖排 / 近 90 度倍数旋转 TextBox 执行有上限 rotation OCR；v1.92 对合法凸四点 line polygon 透视校正后逐行 OCR；v1.97 隔离单行失败并保留成功行；v1.99 要求 polygon point 属于其 TextBox bbox 容差范围，partial / fallback / 全部失败与任意角度 rotation 继续进入 convergence blockers）
  -> internal structure bottleneck routing（聚合 OCR / bubble / crop / translation / render 证据，只写报告和 TXT）
  -> reading order structure audit（审计阅读顺序、气泡归属、多块气泡和结构动作，只写报告和 TXT）
  -> structure action candidate matrix（把结构建议转成 report-only work candidates）
  -> Koharu Artifact DAG（阶段账本、首次阻塞与下游影响）
  -> Koharu stage gap replication plan（canonical stage 差距、work package、promotion gate、逐块复刻计划）
  -> Koharu native replication scoreboard（stage scorecard、gate ledger、block scorecard、next work items）
  -> Native TextBox proxy ledger（质量账本、候选来源、gate、stoplist、候选冻结）
  -> BubbleMask assignment / split scoreboard（归属、分割、same-bubble sibling layout、render gate 评分板）
  -> SegmentMask proxy coverage scoreboard（glyph 清字边界、coverage、background fill、render mask 账本）
  -> Koharu Render Regression Lock（RenderedSprites / FinalRender 回归锁、失败覆盖和核心 PNG 账本）
  -> Koharu Pipeline Resolver shadow DAG（needs / produces / dependency propagation / execution queue / op preview）
  -> Koharu WorkOrder Router（执行工作单、逐块路由、预算和 gate 账本）
  -> Koharu External Artifact Request Packet（真实 TextBoxes / BubbleMask / SegmentMask 请求包、required files、逐块缺口和准入 gate）
  -> Koharu Native Algorithm Replay Matrix（本地算法复刻候选、stage matrix、逐块 route、budget gate，report-only）
  -> Koharu BubbleIndex shadow ledger（多数 mask 归属、安全区、同气泡 sibling 分区、split 风险和 render lock，report-only）
  -> Koharu DistanceField SafeArea shadow report（rounded-rect proxy ID mask 的 distance field / safe pixels / maximum safe rect / sprite containment 对照，report-only）
  -> Koharu Bubble Adjacency Seam shadow report（BubbleMask proxy adjacency graph / seam candidate / block seam ledger，report-only）
  -> Koharu RenderSprite Fit Planner report（RenderedSprites 字体预算 / layout candidate / sibling fit / failure fallback 风险账本，report-only）
  -> Koharu Native TextBox Detector-Lite report（source image 像素 / bubble geometry 生成每 bubble 预 OCR TextBox 候选池，shadow-only）
  -> Koharu Native TextBox Detector-Lite Shadow OCR report（受限 detector-lite crop OCR / vertical rotation shadow 评估，report-only）
  -> Koharu Native TextBox Detector-Lite Refinement report（detector-lite 父 bbox 二次收紧 + 受限 refinement shadow OCR，report-only）
  -> Koharu Native TextBox Detector-Lite Closed Loop report（消费 detector-lite / shadow OCR / refinement 和结构诊断做闭环裁决与结构路由，report-only）
  -> Koharu Native BubbleMask Instance-Lite report（source image 像素近白连通域实例 ID mask 账本，report-only）
  -> Koharu Native SegmentMask Refinement-Lite report（TextBox 约束文字像素掩码 refinement 账本，report-only）
  -> Koharu Native Artifact Bundle-Lite report（TextBoxes / BubbleMask / SegmentMask / OCR / Translation / Render 结构一致性闭环，report-only）
  -> Koharu Native Promotion Gate-Lite report（探针驱动 native-lite artifact 晋级门槛 / candidate export preview，report-only）
  -> Koharu Native Artifact Contract Dry-Run report（四件套 artifact contract 必需字段 / sourceImageSHA256 / 禁止来源 / App 侧 identity receipt / validator 命令干跑，report-only）
  -> Koharu Artifact Identity Reconciliation report（App runtime receipt -> CI manifest identity 字段路径 / source image SHA match / size-SHA 对账表，report-only）
  -> Koharu Artifact convergence report（canonical artifact 收敛矩阵、逐块 path、work item closure、linkage / external shadow coverage / orientation gate ledger）
  -> JSON / TXT / PNG 输出
```

探针运行模式：

- `skip`：不下载 GGUF、不启动模拟器、不跑漫画探针，manifest 必须写明 `probeSkippedReason` 和 `modelSetupSkippedReason`。候选核心 push 的 task-scoped full 仍按需跑 Xcode；PR/已验证 merge 的 fast follow-up 复用候选 full 收据并跳过 Xcode。非 App full 也可写 `xcodeBuildRequired=false` 与任务级 skip reason。
- `ci-fast`：手动 `workflow_dispatch` 快速探针模式，使用真实 simulator、Local GGUF、`test/1.png`、deterministic 解码、whole-page OCR、bubble-first 融合、逐块翻译、失败块覆盖、clean text diagnostic 和 external artifact gate；跳过 lexicon / Vision API / slice / TextRegion crop shadow / crop experiment / line shadow / tagged batch / 模型纠错 / 纠错翻译对照 / contact sheet 等高成本诊断。
- `full`：开发页按钮和人工 full 回归默认模式，运行完整 shadow-only 对照、diagnostic PNG 和 contact sheet。

CI artifact version 优先从带 `vX.Y` 的候选 ref 解析；`smalldata_test` merge 等无版本 ref 必须回退读取 Xcode 工程唯一 `MARKETING_VERSION`。工程缺版本或多个 build configuration 的值不一致时 metadata step 直接失败，不得生成 `unversioned` 结果包。

手动 workflow 可选提供 Koharu artifact Release archive：`koharu_artifact_release_tag`、`koharu_artifact_asset`、`koharu_artifact_sha256`。CI 会在 Xcode build 前下载、校验、解压并只复制 `1.manifest.json`、`1.textboxes.json`、`1.bubbles.json`、`1.segment_mask.json` 到 `test/koharu_artifacts/`，随后跑 validator；`koharu_artifact_required=true` 时任一失败都会阻断工作流。该路径只接收真实 detector / segmenter 输出，不从 examples、Vision OCR、pre-crop、line、proxy、ground truth 或手写框生成 active artifact。v1.59 起，注入 archive 后的 `ci-fast/full` 还必须在 App 侧探针产物中证明 App 真消费到 artifact。v1.64-v1.99 的 orientation、identity、line polygon warp 与所属 bbox 门槛继续保留。v2.0 起 TextBox ID 必须非空且唯一，shadow OCR 使用稳定一对一最大基数匹配并要求完整 outcome partition。v2.1 起 Bubble instance ID 同样必须非空唯一；assignment 只有中心包含或 `IoU >= 0.10` 且 block / TextBox external Bubble ID matched 才可信。最终还要求 `geometryWeakBlockIndexes=[]`、`geometryUnknownBubbleBlockIndexes=[]`、`geometryCoverageRatio=1`、`geometryCoverageVerdict=complete` 才关闭 `WI/G-external-textbox-shadow-ocr-coverage`。v1.70 的注入 archive 禁止 `probe_mode=skip` 与 v1.97 exact repo/ref/SHA handoff 规则不变。

报告会在 `configuration.probeRunMode`、`configuration.probeFastPathEnabled`、`configuration.skippedDiagnostics` 和 `manga_probe_progress.json` 中记录模式、跳过项、保留输出文件和阶段耗时。

禁止：

- 不要失败就跳过绘制。
- 不要让浏览器 UI、广告、底部导航进入 OCR。
- 不要把 ground truth 用于融合候选选择。
- 不要把确定性纠错直接切主流程。
- 不要把 `accuracyVsGroundTruth = 0.8378 / 0.8755` 当新基线。

### 1.7 持久化和输出
职责：保存用户状态、历史、提示词和探针产物。

路径：

- App 状态：`Application Support/AITRANS/state.json`
- 导出 JSON：`Application Support/AITRANS/aitrans-export.json`
- 本地模型：`Application Support/Models/Gemma-1.5B/model.gguf`
- 探针沙盒输出：`Application Support/AITRANS/Output/`
- 项目导出输出：`output/`
- 长期指标：`metrics/version_history.csv`

规则：

- 探针输出目录每轮必须清理，不能堆积旧图。
- `metrics/version_history.csv` 不随 `output/` 清理。
- 每次版本收尾追加指标，不覆盖历史行。

v3.68 的局部预览继续只消费 View 私有 crop：无效或过期 OCR 框让 crop 构造返回 `nil`，局部放大显示“局部预览不可用”，并通过 VoiceOver hint 告知仍可关闭、编辑 OCR 原文或切换文字块；OCR 修正对照仍可编辑。该边界不新增 Store／持久化状态，也不改变 Vision OCR、翻译、renderer/export、漫画探针、Koharu 或质量基线。

v3.69 在结果行和完整图片预览的 VoiceOver 摘要中复用 `NormalizedImageRect.normalizedToUnit()` 判断定位可用性：无效或过期框提前读出“定位不可用”，结果行显示位置不可用图标，同时保留 OCR 修正和切换文字块入口。该 View-only 反馈不新增 Store／持久化状态，不改变 Vision OCR、翻译、renderer/export、漫画探针、Koharu 或质量基线。

v3.70 让完整图片预览的 VoiceOver hint 根据定位不可用数量动态分流：有效文字块可打开局部放大，异常文字块明确局部预览不可用；继续保留既有状态门、OCR 修正和切换文字块入口。该 View-only 反馈不新增 Store／持久化状态，不改变 Vision OCR、翻译、renderer/export、漫画探针、Koharu 或质量基线。

v3.71 的开发控制台仍消费漫画探针返回的单一 `MangaOverlayExternalArtifactReadinessReport`，但把下游门控拆成可读的坐标、mask payload、mask 拓扑和工件身份摘要；status row、VoiceOver hint 与可复制 code block 都明确当前阻塞和 CI 对账要求。该 View-only 改动不创建/修改 active `test/koharu_artifacts`，不放宽 shadow OCR gate，不改变普通图片 OCR、翻译、renderer/export、漫画探针或 Koharu 主路径；真实四件套缺失时仍保持 `manifestMissing / stopUntilArtifactsProvided`。

## 2. 核心执行流
### 2.1 文本翻译
```text
用户键入文本，或明确点击系统纯文本 PasteButton
  -> 空 draft 直接填入 / 非空 draft 换行追加
  -> store.draftText
  -> 点击翻译，先令 inputFocused = false
  -> TranslationSessionStore.submitDraft / makeRequest
  -> selectedEngine
  -> MockGemmaService 或 GemmaLocalService
  -> cleanTranslationOutput / 质量检查
  -> transcript / history / UI
```

### 2.2 图片翻译
```text
用户点击照片或图片文件入口
  -> Store 前置检查图片翻译 Pro 权限；拒绝则显示 Alert 且不打开系统选择器
  -> 授权后从 PhotosPicker 或文件选择器选择图片
  -> 图片页显式选择输入语言和目标语言（目标语言 Pro 门控）
  -> View 只把 loader / 带 selection UUID 的 result 交给 TranslationSessionStore
  -> Store 创建图片 task ID，立即固定本次源/目标语言并进入 loading
  -> 新照片 / 文件可抢占运行中任务；取消、清空和新 task 使旧 transfer 回调失效
  -> task UUID 隔离 sandbox 输入；await 后 identity 匹配才发布 retry source
  -> 被抢占的临时输入、被替换或清空的旧源删除；取消后的当前源可保留重试
  -> Retry 只在 failed，或取消后 idle 且 source 文件仍存在时显示
  -> translated 且 Store-owned source 仍存在时显示重新识别；复用内容语言与既有 run isolation
  -> 摘要显示平均置信、低置信块、竖排与方向待定数，不使用 ground truth
  -> 新任务 / 清空删除当前稳定导出；模式重渲染先删除被替代导出
  -> 重渲染发布 rendering 并禁用模式切换；当前失败显示 danger + 重试导出
  -> success / cancel / failure 按 render ID + 图片 task ID 收口，旧结果拒收
  -> App 启动分账接管 marker + render UUID 稳定导出、task UUID 输入副本和 render UUID staging
  -> 清理上次异常退出残留；正常 input / staging 删除也校验 workspace + 文件类型并登记失败 ownership
  -> 拒绝任意文件名 / wrong-kind / 目录外 / 嵌套 / escape / symlink / dangling symlink
  -> 删除失败保留对应 ownership，后续生命周期重试
  -> 分享时 Store 发布 preparing，创建 ImageTranslationShares/share UUID/可读文件名
  -> 准备中禁用重复导出；当前失败显示 danger，旧 request 不覆盖新状态
  -> dismiss / 新任务 / 清空 / 重渲染 / 启动时清理，晚到 share request 拒收
  -> VisionOCRService.recognizeTextBlocks
  -> 保守方向证据：CJK 高框竖排，否则 horizontal / unknown fallback
  -> 横排上->下/左->右；竖排列右->左、列内上->下；方向隔离聚类
  -> 每块按固定目标语言调用 translate
  -> ImageTranslationBlock
  -> 逐块翻译中只读查看 / 定位；仅 translated 后可改结果或复查进度
  -> 风险块的完成/撤销由当前图片会话 Store 状态维护；面板重建后继续，新图、取消和清空重置且不落盘
  -> 用户可在结果行修正单块 OCR 原文
  -> Store 以 correction ID + 图片 task ID + 旧原文快照隔离，只重译目标块
  -> 首次修正私有保留 Vision OCR 基线；可无模型恢复基线并重新打开该风险块复查
  -> 成功后更新当前图片 transcript 并触发同模式导出重绘；失败保留旧 block 与导出
  -> 旁贴或覆盖 UI
  -> 同模式顶左坐标 PNG 导出
```

### 2.3 音频翻译
```text
用户选择或长按录音
  -> Apple Speech on-device recognition
  -> recognized text
  -> store-owned speechTranslationTask
  -> TranslationSessionStore.translate
  -> await 后核对 Task cancellation + Speech run ID
  -> UI 展示
```

### 2.3.1 语音质量评测
```text
开发页或 DEBUG launch flag
  -> TranslationSessionStore.runSpeechQualityProbe
  -> 读取 manifest + 校验 manifest/audio SHA256/字节数
  -> Apple Speech URL recognition（on-device required）
  -> 最终 transcript 返回
  -> SpeechQualityEvaluator（参考文本仅在此处参与）
  -> 英文等词级 WER / 全语言 CER / latency / confidence / failure category
  -> Output/speech_quality_report.json + .txt
```

### 2.4 漫画探针
```text
开发页运行漫画覆盖翻译探针
  -> TranslationSessionStore.runMangaOverlayProbe
  -> MangaOverlayProbeService.recognizeTextBlocks
  -> MangaOverlayProbeService.runBubbleFirstProbe
  -> fuse whole-page + bubble-first candidates
  -> post-fusion cleanup / bubbleAudits
  -> BubbleMask 归属修正 / split candidate 诊断
  -> TextRegion crop OCR 候选诊断和护栏选择
  -> TranslationSessionStore.translateMangaProbeBlock
  -> TextBox / SegmentMask 派生诊断和 crop experiment shadow 矩阵
  -> external artifact readiness gate / App-side identity receipt
  -> external TextBoxes shadow OCR / orientation-aware shadow path
  -> Koharu Native Artifact contract dry-run
  -> Koharu Artifact identity reconciliation
  -> Koharu Artifact convergence coverage / orientation gates
  -> internalStructureBottleneckReport
  -> routingDrivenTranslationComparisonReport / ocrCharacterDamageAuditReport
  -> readingOrderStructureAuditReport
  -> structureActionCandidateReport
  -> koharuArtifactDAGReport
  -> makeMangaOverlayProbeDiagnostics
  -> render overlays / contact sheet
  -> write JSON / TXT / PNG
  -> scripts/export-probe-output.sh 导出
```

## 3. 数据层 / 模型层 / 测试层关系
- 数据层：`TranscriptModels.swift` 定义会话、提示词、模型请求、OCR 块、漫画报告和诊断结构。
- 状态层：`TranslationSessionStore.swift` 汇总 UI 状态、持久化、翻译调用和报告生成。
- 服务层：Vision OCR、Manga probe、Local model download、Gemma local、llama runtime。
- UI 层：SwiftUI 页面只展示状态并触发 store 方法。
- 测试层：`md/test/test.md` 定义本地轻量检查、GitHub Actions 重验证、结果包和失败回传规则。
- 版本层：`update_log.md` 记录历史，`metrics/version_history.csv` 记录可量化指标。

## 4. 云端协作和验证流
当前日常开发不再把本机 Xcode build / 模拟器探针作为默认硬要求。默认流程是：

```text
人工目标
  -> Agent A 本地分析并写版本化提示词
  -> Agent B 从 smalldata_test 开 codeb/vX.Y-短标题 分支
  -> Agent B 本地只跑轻量检查
  -> Agent B 集中 push 核心 commit 到 codeb/...
  -> GitHub Actions 跑一次 task-scoped full：基础静态 + 相关领域契约 + 必要 Xcode build
  -> full 成功，为候选 SHA 写 AITRANS CI/full-validation status 并上传未加密结果包
  -> Agent B 创建 PR：base=smalldata_test, head=codeb/...
  -> PR opened/reopened/ready-for-review 只跑 fast；不监听 synchronize
  -> Agent C 通过 PR 和结果包核对 diff、日志、manifest 和 artifact
      -> 失败：C 输出退回清单，B 修复 push 并重新跑对应 full
      -> 通过：C 经 PR merge 合并回 smalldata_test
  -> merge workflow 核验第二父 full status：success 走 fast 并把 receipt 传播到 merge SHA，缺失/失败回退 full
  -> 后续 smalldata_test 纯元数据提交：父 propagated receipt=success 才 fast；缺失/失败强制当前头部 Xcode build
      -> C 删除远端 codeb/... 候选分支
```

分支规则：

- `main` 只作为外观展示分支，禁止合并日常开发成果。
- `smalldata_test` 是当前远端真实工作主分支；若旧提示词写成 `samlldata_test`，以 `origin/smalldata_test` 为准。
- `codeb/vX.Y-短标题` 是 Agent B 候选实现分支。
- Agent B push 后默认创建 PR 到 `smalldata_test`；Agent C 通过 PR merge 收口。
- Agent C 合并后必须删除远端 `codeb/...` 候选分支，或说明没有权限删除，避免长期堆积。

结果包规则：

- 加密打包 workflow 只在软件包交付时手动触发，不随 `smalldata_test` merge 自动 archive；不作为 Agent C 验收依据，不为验收改动密码或解密流程。
- Agent C 使用独立未加密 CI 结果包验收；`xcodeBuildRequired=true` 时必须核对 `.xcresult`，build-skip 快路径必须核对 skip reason，同时核对 `junit.xml`、`xcodebuild.log`、`ci-artifact-manifest.json`、`ci-failure-summary.md`。
- `ci-artifact-manifest.json` 必须能追溯 `version`、`branch`、`commitSha`、`runId`、`runAttempt`、`workflowName`、`validationProfile`、`validationReason`、复用 full SHA/status、各领域 required flags、`scheme`、`destination`、结果路径和探针报告路径。
- 云端失败时，workflow 必须保留日志和失败摘要，Agent C 按结果包指出应交回 Agent B 修复的失败阶段和日志位置。
- 手动探针 workflow 会从 Release `model-gemma-3-270m-it-qat-q4_0-v1` 下载 `gemma-3-270m-it-qat-Q4_0.gguf`，校验 SHA256 `3626e245220ca4a1c5911eb4010b3ecb7bdbf5bc53c79403c21355354d1e2dc6`，并缓存到 `.ci-models/`。
- 候选核心 push 默认 `validationProfile=full`、`probe_mode=skip`；PR fast 与有成功候选收据的 merge fast 只跑基础静态/路由契约。fast 不下载 GGUF、不创建模拟器、不安装 App、不跑 Xcode、不跑领域大契约。
- merge fast 会把已验证候选的 full receipt 传播到 merge SHA。后续 `smalldata_test` 纯 README / AGENTS / update log / `md/` / metrics 提交只有该父 receipt 为 success 时才允许 fast；artifact 记录 `smalldataParentSha`、`smalldataParentFullValidationState`、`smalldataIncrementalMetadataOnly`、`smalldataMetadataRequiresFullValidation` 和 `receiptPropagationAllowed`。父 receipt 缺失或失败时，当前头部必须执行 Xcode build；任何传播 fast 都不是新的编译证据。
- full 按 changed files 路由 Speech、UI、文本首页和 Koharu 契约。Speech 领域同时运行 run-id contract、质量算法 contract、纯 Swift evaluator 和 corpus validator；当前缺 corpus 时只记录 `manifestMissing`。UI evidence 仅由候选 commit `[ui evidence]` 或手动 `ui_evidence_mode=full` 启用；Speech 默认不截图。漫画/翻译结果图只来自手动 `ci-fast/full` 的探针 `output/`。
- 手动 `workflow_dispatch` 选择 `ci-fast` 或 `full` 时，云端 CI 单次 Debug simulator build 同时产出 `.xcresult` 和可安装 App；探针步骤只定位并复用该 App，不重复完整 `xcodebuild build`。
- 云端漫画探针会创建并启动 iPhone 模拟器，从构建 App 的 `Info.plist` 读取实际 bundle ID，安装 App，把缓存 GGUF 复制到 App sandbox `Application Support/Models/Gemma-1.5B/model.gguf`，用 `AITRANS_RUN_MANGA_PROBE=1` 和 `AITRANS_MANGA_PROBE_MODE` 启动 App，等待并导出本轮 `output/`。
- `ci-artifact-manifest.json` 必须记录 `probeMode`、`probeFastPathEnabled`、`probeSkippedDiagnostics`、`probeOutputRequiredFiles`、`probeOutputRetainedFiles`、`simulatorAppReusedFromXcodeBuild` 和 `simulatorAppPath`。
- push 快验验收静态检查通过；若 `xcodeBuildRequired=true` 还必须 Xcode build 通过，若 `xcodeBuildRequired=false` 必须在 manifest 写明 skip reason。手动探针验收 Release 模型可下载且 SHA 通过、报告可解析、`engineUsed = Local GGUF`、`totalBlocksDetected > 0` 和关键产物存在；`overallPassed=false` 不单独判 CI 失败，因为当前质量基线本身仍有失败块。
- 本阶段不提交模型文件，Release asset 是云端模型来源。

## 5. 已确认铁律
- `TranslationSessionStore` 是单一状态和调度中心。
- ground truth 只能做探针统计，不能做生产候选选择。
- 失败块必须进入报告和覆盖图。
- 可信匹配必须可拒绝，`unmatched` 不进平均准确率。
- 核心对话和装饰标题分开统计。
- 词级 Levenshtein 是当前可信 OCR 相似度口径。
- clean text 失败时优先怀疑模型质量，不继续盲调 OCR。
- bubble-first 当前参与融合主流程；whole-page 原始块和 bubble-first 原始候选仍保留为对照和回退审计。
- TextRegion crop 当前是结构化候选层；v15 会优先尝试可信 split candidate 或 corrected bubble mask，再回退到 block-local subregion、bubble bbox 或 content rect。只有通过 ground-truth-free 护栏才可替换主翻译输入，本轮 0 块采用。
- v18 `preCropTextBoxPlanReport` 是 TextRegion crop 前生成的 Koharu 式上游 TextBox plan artifact；每块最多保留 3 个 plan，只用 fused seed bbox、bubble geometry、BubbleMask majority/safe rect、subRegion、split candidate、assignment correction 和 glyph/SegmentMask proxy 等无真值信号排序。
- v18 `cropExperimentReport` 仍是 shadow-only 实验矩阵；control 使用当前 TextRegion crop，shadow 候选优先来自 `preCropTextBoxPlan.*`，`bestShadowCandidate` 和 `promotionVerdict` 不替换 `finalTextUsedForTranslation`，也不改变 `textRegionCropReport.adoptedCount`。
- v19 `textBoxPlanFailureReport` 用 `sourcePlanID` 串联 plan、candidate 和 block 级结论，只解释 promotion checks / blockers / recommended action，不改变主输入、主覆盖图或 `textRegionCropReport.adoptedCount`。
- v20 `lineTextBoxPlanReport` / `lineCropExperimentReport` 只对 `textBoxPlanFailureReport.continueGeometryResearchBlocks` 生成 line-level TextBox / deskew shadow 候选；当前目标块 `[1, 6, 10]` 共 12 个候选，全部只写报告和 TXT，不改变主输入、主覆盖图、`blockPassed` 或 `textRegionCropReport.adoptedCount`。
- v21 `externalArtifactReadinessReport` 是真实 TextBoxes / BubbleMask / SegmentMask 适配前证据闸门；它只读 `test/koharu_artifacts/` 或 manifest 指定文件，做解析、坐标校验和 block alignment。v3.2 起 contract v2 的 BubbleMask / SegmentMask 使用 `rowMajorRLE`，解码像素不得超过源图且必须精确等于 `width * height`；Bubble 重算唯一 `maskValue` 的 `pixelCount` / tight bbox，Segment 重算 glyph pixels / 四连通 components。v3.3 的 `maskTopologyReport` 与 `WI/G-external-mask-topology-linkage` 复用 `stableOneToOneExternalTextBoxShadowMatching`，要求全部 block / glyph 像素的 TextBox→SegmentMask→BubbleMask 归属唯一且 partition 守恒，foreign、no-bubble、orphan、overlap、duplicate 或 cross-Bubble component 都阻断。两个 gate 都保持 shadow-only，不改 OCR、翻译、renderer、`blockPassed` 或 `currentBlockSource`。v1 摘要仍可读取，但只标记 `legacySummaryOnly`。没有真实 artifact 时输出 `manifestMissing` / `stopUntilArtifactsProvided`，不能用现有 Vision OCR、pre-crop plan 或 line plan 伪装 detector 输出。
- v1.13 `externalTextBoxShadowOCRReport` 是 readiness 通过后的 external TextBoxes shadow OCR 层；选择只使用 IoU、center containment、confidence、bubble alignment 和面积比例，不使用 ground truth。默认缺 active artifact 时 `executed=false`、`candidateCount=0`、所有块 skipped；结果只进入 report / TXT，不改变主流程。v1.64-v1.99 的 orientation / polygon warp 与 partial blocker 继续保留。v2.0 起先构造所有合法 block / TextBox edge，再用确定性增广路径得到最大基数一对一 assignment并输出完整 outcome partition。v2.1 的 `spatialGeometryVerdict`、`bubbleAlignmentVerdict` 与 `assignmentGeometryTrusted` 记录逐 assignment 几何；report 顶层输出 trusted / weak / unknown Bubble blocks、阈值、ratio 和 verdict。OCR 与 geometry 两条 ledger 都 complete 才允许 `WI/G-external-textbox-shadow-ocr-coverage` 闭合。
- v1.18 `internalStructureBottleneckReport` 是 AITRANS 自有探针的结构瓶颈路由层；它从最终 blocks、post-fusion cleanup、TextRegion crop、TextBox plan failure、BubbleMask、assignment correction、split candidate、external readiness 和翻译失败分类现场汇总 `primaryBottleneck` / `recommendedNextAction`，不依赖外部 artifact，不改变主流程文本、覆盖图或通过判定。
- v1.19 `routingDrivenTranslationComparisonReport` 只针对 `modelTranslationQuality` 路由块做最多 5 个 strict prompt deterministic 对照，复用既有候选抽取、分类和质量判定；结果只写 JSON / TXT，不替换漫画主 prompt、主译文、`blockPassed`、失败分类或覆盖图。
- v1.19 `ocrCharacterDamageAuditReport` 只针对 `ocrCharacterDamage` / `ocrInputSuspect` / 低相似度块做 token 级损坏审计；ground truth 仅用于探针诊断，报告 damaged / missing / extra / substitution token、line break risk、TextBox / SegmentMask 证据和 crop blockers，不参与生产候选选择或文本替换。
- v1.20 `readingOrderStructureAuditReport` 是 Koharu 式页面结构计划审计层；它从最终 blocks、bbox、bubbleID / maskDominantBubbleID、safeLayoutRect、TextBox / SegmentMask proxy、post-fusion cleanup 和路由报告现场计算 proposed reading order、bubble group、same-bubble siblings、归属/分割/重复风险和结构动作建议。该报告只写 JSON / TXT，不改变 `blocks` 顺序、批量输入、翻译文本、覆盖图、cleanup、候选选择或通过判定。
- v1.21 `structureActionCandidateReport` 把 v1.20 的结构建议转成可执行 shadow 候选矩阵，候选类型覆盖阅读顺序、气泡归属、气泡拆分、同气泡 sibling layout、重复保护、TextBox/SegmentMask 证据要求、渲染 safe-area reflow 和人工复核。它输出 control/shadow metrics、delta、promotion verdict、blockers 和 next step，只使用已有报告与几何/渲染/shadow OCR 摘要，不新增 OCR / LLM 调用，不重排 `blocks`，不改变翻译输入、覆盖图、`blockPassed`、失败分类、cleanup 或 metrics；缺真实 Koharu artifact 时只输出阻塞和 `provideRealKoharuArtifact`。
- v1.22 `koharuArtifactDAGReport` 是 Koharu 式 Artifact DAG 阶段账本；它把 SourceImage、ContentCrop、OCR、BubbleMask、TextBoxes、SegmentMask、translation、render 和 v1.21 结构动作候选组织成 dependency edges、stage summaries 和逐块 trace，定位每块 `firstBlockingStage` 与 `downstreamImpact`。该报告只复用既有证据，不新增 OCR / LLM，不改变主流程；缺真实 active artifact 时只阻塞真实 TextBoxes / BubbleMask / SegmentMask promotion，不把当前主流程整体判废。
- v1.23 `koharuStageGapReplicationReport` 把 v1.22 DAG 转成 Koharu canonical stage 差距、最小 work package、promotion gate 和逐块复刻计划。它区分 `realKoharuArtifactReady`、`aitransInternalReady`、`aitransProxyOnly`、`shadowOnly`、`missingExternalArtifact` 等能力状态，标出哪些阶段可用 `ci-fast` 继续验证、哪些需要 `full` 探针、哪些必须等待真实 `test/koharu_artifacts/`。该报告仍只写 JSON / TXT，不新增 OCR / LLM，不改变主 OCR、翻译输入、覆盖图、`blockPassed`、失败分类、post-fusion cleanup 或候选选择。
- v1.24 `koharuNativeReplicationScoreboardReport` 只依赖 AITRANS 自己的 probe 输出，把 v1.23 stage gap / work package 转成 native stage scorecard、gate ledger、block scorecard 和下一轮 work items。它不要求真实 external artifact；缺 artifact 只作为 `externalOptionalMissing` 可选外部路径状态，不阻塞 native scoreboard。所有 priority、gate 和 nextAction 使用 ground-truth-free decision signals；`test/1.ground_truth.json` 相关数字只能作为 evaluation-only 指标。报告明确区分 native / proxy / shadow / stop / model-limited / render-stable 状态，并把已证伪的 crop / line / deskew 本地试参加入 stoplist；不新增 OCR / LLM，不改变主 OCR、翻译输入、覆盖图、`blockPassed`、失败分类、post-fusion cleanup 或候选选择。
- v1.25 `nativeTextBoxProxyLedgerReport` 执行 v1.24 的 `WI-native-textbox-artifact-scorecard`，把现有 TextBox / crop / line / BubbleMask / SegmentMask / OCR damage / v1.24 scoreboard 证据整理成 Native TextBox proxy 质量账本。它输出 `blockLedgers[]`、`candidateLedgers[]`、`gateLedger[]` 和 `stoplist[]`，区分 `reportOnlyStable`、`shadowOnlyEligible`、`frozenByStoplist`、word preservation / BubbleMask / SegmentMask / OCR damage / model floor 阻塞和 `manualReviewOnly`。候选冻结、排序、qualityStatus 和 nextAction 只能使用 ground-truth-free decision signals；ground truth 只进入 evaluationSignals。报告只写 JSON / TXT，不新增 OCR / LLM，不改变主 OCR、翻译输入、覆盖图、`blockPassed`、失败分类、post-fusion cleanup 或候选选择。
- v1.26 `bubbleMaskAssignmentSplitScoreboardReport` 执行 v1.24 的 `WI-bubblemask-assignment-split-scorecard`，把现有 BubbleMask proxy、归属修正、split candidate、reading order、structure action、Koharu native scoreboard 和 Native TextBox ledger 证据整理成 BubbleMask 归属 / 分割 / sibling 布局评分板。它输出 `blockScorecards[]`、`bubbleScorecards[]`、`splitCandidateLedgers[]`、`siblingLayoutScorecards[]` 和 `gateLedger[]`，区分 `consistent`、`correctionRecommendedReportOnly`、`correctionAppliedToCropClampOnly`、`maskConflict`、`splitCandidateEligibleReportOnly`、`sameBubbleSiblingLayoutStable`、`needsRealBubbleMask` 和 render mask 状态。assignment、split、sibling layout、nextAction 和 promotion blockers 只能使用 ground-truth-free decision signals；ground truth 只进入 evaluationSignals。报告只写 JSON / TXT，不新增 OCR / LLM，不改变主 OCR、翻译输入、覆盖图、`blockPassed`、失败分类、post-fusion cleanup、候选选择、`safeLayoutRect` 或 `configuration.currentBlockSource`。
- v1.27 `segmentMaskProxyCoverageScoreboardReport` 执行 v1.24 的 `WI-segmentmask-proxy-coverage-scorecard`，把现有 glyph mask、SegmentMask proxy、TextBox 覆盖、BubbleMask 覆盖、safe rect、背景填充和渲染碰撞证据整理成 SegmentMask proxy 覆盖评分板。它输出 `blockScorecards[]`、`cleanupLedgers[]` 和 `gateLedger[]`，区分 `usableProxyCoverage`、`usableForCleanupOnly`、弱 TextBox / BubbleMask / safe rect 覆盖、清字边界、background fill guardrail、render mask 状态和 `needsRealSegmentMask`。coverage、cleanup、nextAction 和 gate 只能使用 ground-truth-free decision signals；ground truth 只进入 evaluationSignals。报告只写 JSON / TXT，不新增 OCR / LLM，不改变主 OCR、翻译输入、覆盖图、`blockPassed`、失败分类、post-fusion cleanup、候选选择、`safeLayoutRect`、`glyphMaskFillRects`、背景填充行为或 `configuration.currentBlockSource`。
- v1.28 `koharuArtifactConvergenceReport` 把 v1.22 DAG、v1.23 stage gap、v1.24 native scoreboard、v1.25 TextBox、v1.26 BubbleMask、v1.27 SegmentMask、external artifact readiness、clean text model floor、diagnostics 和最终 blocks 收敛为 Koharu canonical artifact 矩阵、逐块 artifact path、work item closure ledger 和 gate ledger。它关闭前三个 native/proxy scoreboard 的 report-only 工作项，把未闭合项集中到 `WI-translation-model-floor-comparison`、`WI-render-regression-lock` 和 `WI-external-artifact-optional-handoff`；v1.58 起继续消费 v1.57 bundle-lite / promotion gate 的 TextBox -> SegmentMask linkage work item 与 convergence gate，把 weak / fallback / rejected / wrong-bubble linkage 传播到最终 path、stage、work item 和 gate；v1.64 起 `WI-external-textbox-orientation-shadow-path` / `G-external-textbox-orientation-shadow-path` 同时消费 executed / partial / notExecuted / unsupported / reason breakdown，partial 或 unsupported 不得进入 `closedReportOnly`；v1.65 起 `WI-external-textbox-shadow-ocr-coverage` / `G-external-textbox-shadow-ocr-coverage` 先检查 ready artifact 是否真的产生 external shadow OCR candidate；v1.68 起同一 coverage gate 也要求 `koharuArtifactIdentityReconciliationReport.readyForCIManifestComparison = true`，并通过 `WI-koharu-artifact-identity-reconciliation` / `G-koharu-artifact-identity-reconciliation-ready` 暴露 App receipt 与 CI manifest identity 的对账状态。该报告不新增 OCR / LLM，不改变主 OCR、翻译输入、覆盖图、`blockPassed`、失败分类、post-fusion cleanup、候选选择、`safeLayoutRect`、`glyphMaskFillRects`、背景填充行为、渲染逻辑或 `configuration.currentBlockSource`。ground truth 只进入 evaluationSignals，不参与 firstBlockingArtifact、primaryNextAction、work item status 或 gate。
- v1.69 起 convergence coverage gate 进一步要求 ready artifact 后 `externalTextBoxShadowOCRReport.executed = true`、`candidateCount > 0`、`ocrExecutedCount > 0`、`ocrSucceededCount > 0`，否则 ExternalArtifacts 不得闭合；v1.70 起 App/CI handoff strict closure 还要求 artifact archive 不得配 `probe_mode=skip`，coverage / orientation work item 与 gate ID、status 必须进入 smoke 和 TXT 证据，orientation partial / unsupported blockers 存在时 gate 不得误判 passed。
- v1.29 `translationModelFloorComparisonReport` 执行 `WI-translation-model-floor-comparison`，用 `cleanTextDiagnostic` 的 dialogue baseline 和 `strictChineseOnlyV1` deterministic 变体做同源 clean text 对照，并汇总 noisy final blocks、v1.19 routing strict prompt、tagged batch 和 v1.28 convergence work item。它只分类当前模型 / prompt 地板，不换模型、不改主 prompt、不改逐块主译文、不改覆盖图、`blockPassed`、失败分类或质量规则；clean text ground truth 只进入模型地板评估和 evaluation-only 信号。
- v1.30 `koharuRenderRegressionLockReport` 执行 `WI-render-regression-lock`，把现有 safe layout、mask-safe rect、render collision、render mask overflow、glyph mask、background fill、失败块 fallback 覆盖文本和核心输出文件状态整理成 RenderedSprites / FinalRender 回归账本。它输出逐块 `blockLocks[]`、`artifactStages[]`、`outputFileChecks[]` 和 `gateLedger[]`，并让 convergence 中的 render work item 从未执行 open 推进为 `closedReportOnly` 或 `openRenderIssueDetected`。该报告只写 JSON / TXT，不重新渲染、不新增 OCR / LLM、不解析 PNG 像素做逐块证明、不改变覆盖绘制、`safeLayoutRect`、`glyphMaskFillRects`、背景填充、主 OCR、主翻译、`blockPassed`、失败分类或 `configuration.currentBlockSource`；`proxyNotRealKoharuRenderer = true` 表示它不是 Koharu 真实 renderer / RenderedSprites / inpainting。
- v1.31 `koharuPipelineResolverReport` 在 render lock 之后、最终 convergence 刷新前生成，把现有报告组织成 Koharu 式 `needs` / `produces` / DAG resolver / Op preview 影子层。它输出 stage nodes、edges、逐块 first blocked node、downstream impact、execution queue、op previews 和 gates，并把 `WI-koharu-pipeline-resolver-shadow-dag` / `G-koharu-pipeline-resolver-executed` 联动进 convergence。该报告只写 JSON / TXT，不新增 OCR / LLM、不改变主 OCR、翻译输入、覆盖图、`blockPassed`、失败分类、post-fusion cleanup、候选选择、`safeLayoutRect`、`glyphMaskFillRects`、背景填充或 `configuration.currentBlockSource`。
- v1.32 `koharuWorkOrderRouterReport` 在 v1.31 resolver 之后、最终 convergence 刷新前生成，把 resolver execution queue、convergence、translation floor、render lock、TextBox / BubbleMask / SegmentMask scoreboards 和 external artifact gate 收束为固定 work orders、逐块 routes、budget ledger 和 gates。它输出 `workOrders[]`、`blockRoutes[]`、`budgetLedger` 和 `gateLedger[]`，并把 `WI-koharu-workorder-router` / `G-koharu-workorder-router-executed` 联动进 convergence。该报告只写 JSON / TXT，不新增 OCR / LLM、不改变主 OCR、翻译输入、覆盖图、`blockPassed`、失败分类、post-fusion cleanup、候选选择、`safeLayoutRect`、`glyphMaskFillRects`、背景填充或 `configuration.currentBlockSource`。
- v1.36 `koharuDistanceFieldSafeAreaReport` 在 v1.35 BubbleIndex 账本之后、最终 convergence 刷新前生成，只使用 AITRANS rounded-rect BubbleMask proxy ID mask，在每个 bubble bbox 内计算 two-pass chamfer 8-neighbor distance field、safe pixels、histogram maximum safe rect 和 block / sibling safe-area 对照。它输出 `bubbleLedgers[]`、`blockLedgers[]`、`siblingLedgers[]` 和 `gateLedger[]`，并把 `WI-koharu-distance-field-safe-area` / `G-koharu-distance-field-safe-area-executed` 联动进 convergence。该报告只写 JSON / TXT，不新增 OCR / LLM、不改变主 OCR、翻译输入、覆盖图、`safeLayoutRect`、`glyphMaskFillRects`、背景填充、`blockPassed`、失败分类、post-fusion cleanup、候选选择、active artifacts 或 `configuration.currentBlockSource`；ground truth 只进入 evaluation signals。
- v1.37 `koharuBubbleAdjacencySeamReport` 在 v1.36 DistanceField 账本之后、最终 convergence 刷新前生成，只使用 AITRANS 现有 rounded-rect BubbleMask proxy、BubbleIndex、DistanceField、split candidate、same-bubble sibling、OCR damage 和 render lock 证据。它输出 `pairLedgers[]`、`seamCandidateLedgers[]`、`blockLedgers[]` 和 `gateLedger[]`，并把 `WI-koharu-bubble-adjacency-seam` / `G-koharu-bubble-adjacency-seam-executed` 联动进 convergence。该报告只写 JSON / TXT，不新增 OCR / LLM、不改变主 OCR、翻译输入、覆盖图、`safeLayoutRect`、DistanceField safe rect、`glyphMaskFillRects`、背景填充、`blockPassed`、失败分类、post-fusion cleanup、候选选择、active artifacts 或 `configuration.currentBlockSource`；ground truth 只进入 evaluation signals。
- v1.38 `koharuRenderSpriteFitPlannerReport` 在 v1.37 seam 账本之后、最终 convergence 刷新前生成，只使用现有 `safeLayoutRect`、`renderFontSize`、`renderNonTransparentBounds`、render collision、失败 fallback、Render Regression Lock、BubbleIndex、DistanceField 和 seam 证据。它输出 `blockLedgers[]`、`layoutCandidateLedgers[]`、`siblingLedgers[]` 和 `gateLedger[]`，并把 `WI-koharu-render-sprite-fit-planner` / `G-koharu-render-sprite-fit-planner-executed` 联动进 convergence。该报告只写 JSON / TXT，不新增 OCR / LLM、不重新渲染 PNG、不改变主 OCR、翻译输入、覆盖图、`safeLayoutRect`、DistanceField safe rect、`renderFontSize`、`renderNonTransparentBounds`、`glyphMaskFillRects`、背景填充、`blockPassed`、失败分类、post-fusion cleanup、候选选择、active artifacts 或 `configuration.currentBlockSource`；ground truth 只进入 evaluation signals。
- v1.39 `koharuNativeTextBoxDetectorLiteReport` 在 v1.38 RenderSprite fit planner 之后、最终 convergence 刷新前生成。它只用 source image 像素、bubble geometry、BubbleMask proxy 和 glyph / SegmentMask proxy 生成 OCR 前 `nativeDetectorLite` TextBox 候选池，每个 bubble 最多 4 个 component-cluster 候选 + 1 个不参与 shadow OCR 的 diagnostic union fallback，输出 candidate、candidate->block relation、block、bubble 和 gate ledger，并把 `WI-koharu-native-textbox-detector-lite` / `G-koharu-native-textbox-detector-lite-executed` 联动进 convergence。该报告默认不执行 shadow OCR，不读取 Vision OCR 文本、ground truth、pre-crop plan、line plan 或 TextRegion crop 结果来生成 / 排序候选；不改变主 OCR、翻译输入、覆盖图、`blockPassed`、失败分类、`textRegionCropReport.adoptedCount`、active artifacts 或 `configuration.currentBlockSource`；`proxyNotRealKoharuTextBoxes = true`。
- v1.40 `koharuNativeTextBoxDetectorLiteShadowOCRReport` 在 v1.39 detector-lite 之后生成，只消费 `shadowOCREligible = true` 的 nativeDetectorLite bbox；`ci-fast` 每块最多 1 个候选、`full` 每块最多 2 个。候选按当前 block 与 bbox 的 overlap / center containment 优先排序；full 模式 block ledger 记录本块 report-only 最佳 shadow OCR 候选。`verticalCandidate` 候选会做有上限的 `[0,90]` rotation shadow OCR 对照，使用 `ja-JP/ja/en-US/en` language profile 并记录 `rotationApplied`，选择只看无真值 OCR 质量和当前文本保词率；ground truth 只进 evaluation signals。该报告不新增 LLM，不写回主 OCR、翻译输入、覆盖图、`blockPassed`、失败分类、active artifacts 或 `configuration.currentBlockSource`。
- v1.41 `koharuNativeTextBoxDetectorLiteRefinementReport` 在 v1.40 detector-lite shadow OCR 之后、最终 convergence 刷新前生成。它只用 v1.39 / v1.40 内存报告、final blocks、source image pixels、bubble geometry 和既有诊断信号选择 target 并从 detector-lite 父 bbox 生成 refined bbox；`ci-fast` 总 OCR 预算为 `<= min(6,totalBlocksDetected)`，`full` 每块最多 2 个且有总上限。refined OCR 只进 JSON / TXT，不写回主 OCR、翻译输入、覆盖图、`blockPassed`、失败分类、active artifacts 或 `configuration.currentBlockSource`；ground truth 只进 evaluation signals。
- v1.42 `koharuNativeTextBoxDetectorLiteClosedLoopReport` 在 v1.41 refinement 之后、最终 convergence 刷新前生成。它消费 v1.39 detector-lite、v1.40 shadow OCR、v1.41 refinement、final blocks、BubbleMask / SegmentMask proxy、翻译失败分类、Translation Model Floor、Render Regression Lock 和 external artifact readiness，把每块闭环路由到保留当前 fused OCR、full-probe 复核、停止 detector-lite 本地调参、等待真实 TextBoxes / BubbleMask / SegmentMask、模型地板或 render lock。该报告只写 JSON / TXT，不新增 OCR / LLM / PNG，不写回主 OCR、翻译输入、覆盖图、`blockPassed`、失败分类、`textRegionCropReport.adoptedCount`、active artifacts 或 `configuration.currentBlockSource`；ground truth 只进 evaluation signals，不参与 route、nextAction、gate 或 candidate family verdict。
- v1.43 `koharuNativeBubbleMaskInstanceLiteReport` 在 v1.42 closed-loop 之后、最终 convergence 刷新前生成。它只用 `test/1.png` 内容裁切区源像素、现有 bubble geometry、final blocks、glyph / SegmentMask proxy、BubbleIndex / DistanceField / seam / RenderSprite fit、detector-lite closed-loop 和 render lock 证据，生成 shadow-only 近白连通域 instance-lite ID mask 账本、逐块 majority assignment、由实例像素 erosion / projection 派生的 safe rect 对照、同 instance 多 block 的 block-scoped safe rect policy、block-scoped sprite containment preview、same-instance sibling sprite collision preview、sibling / adjacency 和 gate ledger。该报告不新增 OCR / LLM / PNG，不创建 active Koharu artifact，不把 instance-lite 冒充真实 Koharu `BubbleMask`，不写回 `safeLayoutRect`、DistanceField safe rect、renderer、主 OCR、翻译输入、覆盖图、`blockPassed`、失败分类或 `configuration.currentBlockSource`；ground truth 只进 evaluation signals，不参与 mask 生成、route、nextAction、verdict 或 gate。
- v1.44 `koharuNativeSegmentMaskRefinementLiteReport` 在 v1.43 instance-lite 之后、最终 convergence 刷新前生成。它只用源图像像素、detector-lite TextBox 候选、final blocks、instance-lite BubbleMask、现有 glyph / SegmentMask proxy、render lock 和翻译失败分类，生成 TextBox 约束文字像素 mask refinement 的 candidate / block / sibling / gate 账本。candidate / block ledger 记录来源 TextBox candidate verdict、block overlap、same-bubble relation、accepted/fallback/rejected linkage verdict、mask 对 TextBox / Bubble 的 containment ratio，并用 v1.43 instance-lite ledger 输出 report-only majority agreement。该报告不新增 OCR / LLM / PNG，不创建 active Koharu artifact，不把 refinement-lite 冒充真实 Koharu `SegmentMask`，不写回主 OCR、翻译输入、覆盖图、`safeLayoutRect`、`glyphMaskFillRects`、背景填充、renderer、`blockPassed`、失败分类、`textRegionCropReport.adoptedCount` 或 `configuration.currentBlockSource`；ground truth 只进 evaluation signals，不参与阈值、TextBox 选择、mask、route、nextAction、verdict 或 gate。
- v1.45 `koharuNativeArtifactBundleLiteReport` 在 v1.44 refinement-lite 之后、最终 convergence 刷新前生成。它只消费当前探针内存中的 final blocks、v1.39-v1.42 detector-lite / shadow OCR / refinement / closed-loop、v1.43 BubbleMask instance-lite、v1.44 SegmentMask refinement-lite、RenderSprite fit、Render Regression Lock、Translation Model Floor、external artifact readiness 和 diagnostics，组装每块 TextBox / BubbleMask / SegmentMask / OCR / Translation / Render 的 bundle-lite、consistency edges、primary blocking artifact、nextAction 和聚合 worklist。v1.57 起该报告还消费 v1.44 的 selected TextBox -> SegmentMask linkage，输出 `selectedTextBoxSegmentLinkVerdict`、`textBoxSegmentLinkageStatus`、`textBoxSegmentLinkageRisk`、`TextBoxSegmentMaskLinkage` edge、breakdown 和 review blocks；fallback、weak、rejected 或 wrong-bubble linkage 会阻塞 bundle readiness。该报告不新增 OCR / LLM / PNG，不创建或修改 active Koharu artifact，不把 bundle-lite 冒充真实 Koharu artifacts，不写回主 OCR、翻译输入、覆盖图、renderer、`safeLayoutRect`、`glyphMaskFillRects`、`blockPassed`、失败分类、`textRegionCropReport.adoptedCount` 或 `configuration.currentBlockSource`；ground truth 只进 evaluation signals，不参与 component 选择、edge、verdict、gate、route、nextAction 或 worklist。
- v1.46 `koharuNativePromotionGateLiteReport` 在 v1.45 bundle-lite 之后、最终 convergence 刷新前生成。它只消费当前探针内存中的 final blocks、diagnostics、v1.39-v1.45 native-lite reports、RenderSprite fit、Render Regression Lock、Translation Model Floor、clean text diagnostic 和 external artifact readiness，为每块输出 TextBoxes / BubbleMask / SegmentMask / OcrText / Translations / RenderedSprites / FinalRender 的晋级状态、stage gates、candidate export preview、work items 和 gate ledger。v1.57 起 promotion ledger 继承 bundle / SegmentMask linkage verdict，输出 `textBoxSegmentLinkVerdict`、`textBoxSegmentLinkagePromotionStatus`、breakdown 和 blocked blocks；fallback、weak、rejected 或 wrong-bubble linkage 会加入 `mustNotPromoteReasons` 并阻塞 SegmentMask promotion。该报告不新增 OCR / LLM / PNG，不更换模型，不创建或修改 active `test/koharu_artifacts/`，不把 promotion gate 冒充真实 Koharu promotion / detector / artifact，不写回主 OCR、翻译输入、覆盖图、renderer、`safeLayoutRect`、`glyphMaskFillRects`、`blockPassed`、失败分类、`textRegionCropReport.adoptedCount` 或 `configuration.currentBlockSource`；ground truth 只进 evaluation signals，不参与 promotion eligibility、stage gate、candidate preview、route、nextAction 或 worklist。
- v1.47 `koharuNativeArtifactContractDryRunReport` 在 v1.46 promotion gate 之后、最终 convergence 刷新前生成。它只消费 v1.46 candidate export preview 和 `externalArtifactReadinessReport`，把 native-lite / proxy 预览映射到 Koharu active 四件套 contract 的 required files、required fields、forbidden active sources、App 侧 identity receipt、validator commands 和 gate ledger，并把 `WI-koharu-native-artifact-contract-dry-run` / `G-koharu-native-artifact-contract-dry-run-executed` 联动进 convergence。v1.67 起 required file ledger 记录 `fileSizeBytes`、`sha256`、`identityStatus`，顶层记录 `appSideArtifactIdentityVerdict`、files present 和 hashes present；真实 active artifact ready 时，`contractDryRunVerdict = activeArtifactsReadyForShadowOCR` 还要求 App 侧 receipt 完整。该报告 `dryRunOnly = true`、`activeExportAllowed = false`，不创建、复制、修改 `test/koharu_artifacts/`，不新增 OCR / LLM / PNG，不改变主 OCR、翻译输入、覆盖图、renderer、`blockPassed`、失败分类、`safeLayoutRect`、`glyphMaskFillRects`、`textRegionCropReport.adoptedCount` 或 `configuration.currentBlockSource`；ground truth 不参与 contract verdict、file status、preview readiness、nextAction 或 gates。
- v1.68 `koharuArtifactIdentityReconciliationReport` 在 contract dry-run 后、最终 convergence 刷新前生成。它只消费 App 侧 `artifactIdentityReceipt` 和 contract dry-run required files，输出 SourceImage + manifest / TextBoxes / BubbleMask / SegmentMask 的 App size / SHA256、对应 `ci-artifact-manifest.koharuArtifactValidationIdentitySummary` 字段路径、comparison status 和 gate ledger；不读取 CI manifest、不新增 OCR / LLM / PNG、不创建或修改 active artifact、不改变主流程。Actions 在真实 artifact 注入探针后会把 validator identity 与 App rows 做 size/SHA256 比对，并在 manifest 写入 `koharuArtifactIdentityReconciliationMatch`。
- v1.18 post-fusion cleanup 新增保守 `duplicateOrFragment` 拒绝规则，只使用 bbox 强重叠/邻域、bubble 或 mask-safe 邻域、token 覆盖、信息分、OCR 错误启发和保护文本检查；不使用 ground truth，不跨气泡合并，不删除 decorative 标题。
- v1.12 / v22 外部 artifact 契约把 active 输入固定为 `test/koharu_artifacts/`，把非活动 fixture 固定为 `md/koharu研究/artifact_contract/examples/`，并用 `scripts/validate-koharu-artifacts.py` 在进入 App 探针前校验 schema、路径、坐标、bbox、confidence、source image、TextBoxes、BubbleMask 和 SegmentMask。v3.2 接受 `aitrans.koharu_artifact_contract.v1` 摘要兼容和 `v2` 像素载荷；v3.3 再输出 `maskTopologyValidation` / `maskTopologyGateReady`。云端注入验收必须为 v2，且 payload / topology 两个 gate 都为 true。manifest artifact path 必须留在 active 目录内，绝对路径和 `..` 逃逸都阻塞；既有身份、polygon 所属、TextBox / Bubble ID 唯一和 `generatedBy` 真实来源规则不变。只有 `readinessVerdict = readyForShadowOCR`、`activeArtifactsDirectory = true` 且 `contractExampleOnly = false` 时，`externalTextBoxesShadowOCRAllowed` 才能为 true；完整 mask convergence 还必须通过 `G-external-mask-pixel-payload` 和 `G-external-mask-topology-linkage`。
- v1.14 validator / CI 闭环不新增 detector 输入；缺真实 active artifact 时继续阻塞，并在 validator JSON 与 `ci-artifact-manifest.json` 中记录 `requiredFiles`、`nextAction`、`readinessBlockers`、`externalArtifactReadinessSummary` 和 `externalTextBoxShadowOCRSummary`，方便 Agent C 确认云端拿到的是缺 artifact 阻塞路径还是 executed=true 路径。v1.65 起 validator JSON 还包含 `orientationMetadataSummary`，CI manifest 透传为 `koharuArtifactValidationOrientationSummary`。v1.66 起 validator JSON 还包含 `artifactIdentitySummary`，记录 source image 与 manifest / TextBoxes / BubbleMask / SegmentMask 的存在性、size、SHA256、`generatedBy`、`generatedAt`、`contractExampleOnly`；CI manifest 透传为 `koharuArtifactValidationIdentitySummary`，failure summary 打印关键 identity，archive 注入只接受唯一一个同时包含四件套的目录。v1.67 起 App 侧探针报告也记录 `artifactIdentityReceipt`，Agent C 需要把 App runtime receipt 和 CI manifest identity 对齐。真实 artifact ready 后，convergence 的 external shadow OCR coverage gate 还要求 App 侧 identity receipt、contract dry-run verdict ready 且 `dryRunOnly=true`、`activeExportAllowed=false`，以及 external shadow OCR executed / candidate / OCR execution / OCR success 四项同时成立。
- BubbleMask 当前是 bbox/rounded-rect 近似实例 ID mask，用于 seed 归属、归属修正诊断、保守 split candidate、mask-safe layout、crop coverage 和渲染碰撞诊断；不是 Koharu 真实分割 mask，不能把布局收益冒充 OCR 提升。
- 确定性纠错当前是对照路径，不替换 `finalTextUsedForTranslation`。
- tagged batch 当前是负面诊断，不替换逐块翻译。

## 6. 当前关键基线
来自最新 `output/probe_report.json` 和 `output/clean_text_diagnostic.json`：

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
- `fusionFusedAccuracyVsGroundTruth = 0.7384`
- `frameworkComparison.consistencyPassed = true`
- `fusionComparison.consistencyPassed = true`
- `cleanTextDiagnostic.passRate = 0.4545`
- `textRegionCropReport.totalRegions = 13`
- `textRegionCropReport.cropSucceededCount = 10`
- `textRegionCropReport.adoptedCount = 0`
- `textRegionCropReport.rejectedCount = 13`
- `preCropTextBoxPlanReport.planCount = 37`
- `preCropTextBoxPlanReport.shadowOCREligiblePlanCount = 29`
- `cropExperimentReport.candidateCount = 48`
- `cropExperimentReport.controlCandidateCount = 13`
- `cropExperimentReport.ocrSucceededCount = 36`
- `cropExperimentReport.betterThanControlCount = 13`
- `cropExperimentReport.promotedShadowBlocks = []`
- `textBoxPlanFailureReport.evaluatedPlanCount = 37`
- `textBoxPlanFailureReport.evaluatedCandidateCount = 35`
- `textBoxPlanFailureReport.betterThanControlCandidateCount = 13`
- `textBoxPlanFailureReport.promotedShadowBlockCount = 0`
- `textBoxPlanFailureReport.stopRecommendedBlocks = [2, 3, 4, 5, 7, 9, 11, 12]`
- `textBoxPlanFailureReport.continueGeometryResearchBlocks = [1, 6, 10]`
- `lineTextBoxPlanReport.targetBlocks = [1, 6, 10]`
- `lineTextBoxPlanReport.planCount = 12`
- `lineTextBoxPlanReport.shadowOCREligiblePlanCount = 12`
- `lineCropExperimentReport.candidateCount = 12`
- `lineCropExperimentReport.ocrSucceededCount = 12`
- `lineCropExperimentReport.betterThanControlCount = 5`
- `lineCropExperimentReport.promotedLineShadowBlocks = []`
- `lineCropExperimentReport.stoppedAfterLineResearchBlocks = [1, 6, 10]`
- `textBoxPlanFailureReport.candidatePromotionBlockedBlocks = [1, 2, 4, 5, 6, 9, 10]`
- `passedBlocks = 1`
- `failedBlocks = 12`
- `translationFailureBreakdown = { modelOutputFailure: 2, ocrInputSuspect: 7, translationLanguageQualityFailure: 3 }`
- `likelyRuleFalseFailureBlocks = []`

## 7. 未来扩展点
- 更强小模型对比，优先 Qwen2.5-0.5B-Instruct-GGUF q4_k_m。
- 基于 `bubbleAudits` 对 `bubbleID 4/6/7` 做诊断开关下的保守气泡拆分实验。
- 更稳的气泡候选分割。
- 更强 OCR/纠错护栏，替换主流程前必须用探针证明收益。
- Share Extension 或 ReplayKit 路线，但当前不是优先级。

## 8. 不允许破坏的行为
- 不得静默隐藏翻译失败块。
- 不得让旧输出文件污染新验收。
- 不得把测试真值写入生产决策。
- 不得在报告中维护两套互相矛盾的统计。
- 不得删除 `metrics/version_history.csv` 历史行。
- 不得绕过 `LocalLanguageModeling` 协议直接耦合 UI 和 llama runtime。
