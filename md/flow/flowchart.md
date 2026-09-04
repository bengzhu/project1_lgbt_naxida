# 项目流程图

## 1. 项目核心逻辑图
这张图描述 App 从用户入口到状态调度、OCR/模型服务、持久化和探针输出的关系。

```mermaid
flowchart TD
  %% 用户入口：文本、图片、漫画网页、音频、开发页探针
  A["用户操作 / test 固定素材"] --> NAV{"设备布局"}
  NAV -->|"iPhone"| TAB["六项 TabView<br/>紧凑宽度由系统承载 More"]
  NAV -->|"iPad"| SPLIT["NavigationSplitView"]
  TAB --> B["拆分的 SwiftUI feature views<br/>文本 / 图片 / 漫画 / OCR / 音频 / 资料库"]
  SPLIT --> B
  B --> BROWSER["MangaBrowserView<br/>Safari 胶囊 / 标签切换 / 一键与框选翻译"]
  BROWSER --> BMODEL["BrowserModel<br/>tabs / activeTabID / 页面与视口世代"]
  BMODEL --> WEB["唯一活动 WKWebView<br/>后台标签释放 / 不持久化"]
  BROWSER --> BCAP["稳定内容区抓图<br/>排除原生导航与安全区"]
  BCAP --> C
  DS["AppTheme + AppComponents<br/>语义 token / 状态 / 44pt / 响应式布局"] --> B
  TWB["TextWorkspaceBackground<br/>静态网格 / 导向线路 / 文本页专属"] --> B
  SH["文本页顶部 safe-area inset<br/>页头 + 模型状态"] --> B
  SH -. "不参与键盘自动滚动" .-> D

  %% 状态中心：所有业务动作统一进入 store
  B --> C["TranslationSessionStore<br/>统一状态、调度、持久化、诊断"]

  %% 文本翻译分支：普通用户输入
  PASTE["用户点击纯文本 PasteButton"] --> APPEND{"draftText 是否为空?"}
  APPEND -->|"是"| FILL["直接写入 store.draftText"]
  APPEND -->|"否"| ADD["换行追加，不覆盖"]
  FILL --> C
  ADD --> C
  DONE["键盘完成 / 翻译 / 新会话 / 离开文本页"] --> FOCUS["inputFocused = false"]
  FOCUS --> C
  C --> D["submitDraft<br/>ModelGenerationRequest"]
  D --> E{"当前翻译引擎"}
  E --> F["AppleTranslationService<br/>SwiftUI translationTask / TranslationSession"]
  E --> G["GemmaLocalService<br/>GGUF 本地模型适配"]
  E --> GM["MockGemmaService<br/>Preview / UI 数据流冒烟"]
  E --> GR["浑元 / 通义千问<br/>预留且明确失败"]
  G --> H["LlamaRuntime<br/>llama.cpp C API 封装"]

  %% 图片 OCR 分支：普通图片翻译
  IMG_LANGUAGE["图片输入 / 目标语言菜单<br/>输入先验 Pro / 拒绝无跨页副作用<br/>actual content 与 pending Retry 分账<br/>选回 actual 清除 pending<br/>运行态冻结 / 完成态重跑"] --> C
  C --> IACCESS{"Store-owned 图片入口 Pro 授权?"}
  IACCESS -->|否| ILOCK["lock.fill + Pro Alert<br/>不打开系统选择器"]
  IACCESS -->|是| IT["PhotosPicker / 文件 importer<br/>Store-owned 图片 transfer<br/>task ID + 文件 selection UUID"]
  IT --> IG{"transfer / sandbox await 后<br/>task ID 仍匹配?"}
  IG -->|否| IDROP["丢弃旧回调并清理未采用输入<br/>不恢复旧 retry source"]
  IG -->|是| I["普通图片翻译<br/>VisionOCRService + 输入/目标语言快照"]
  ICANCEL["取消图片任务"] --> IRETRY{"sandbox source 已发布且仍存在?"}
  IRETRY -->|是| IR["idle + 显示重试"]
  IRETRY -->|否| IDROP
  ICLEAR["点击清空图片翻译"] --> ICONFIRM{"确认删除图片与结果?"}
  ICONFIRM -->|取消| IRETAIN["保留当前图片与结果"]
  ICONFIRM -->|确认| ICLEARED["Store 清理 task / source / export / share"]
  I --> ILAYOUT{"CJK + 明确高宽几何证据?"}
  ILAYOUT -->|是| IV["竖排列右到左<br/>列内上到下"]
  ILAYOUT -->|否| IH["横排 / unknown fallback<br/>上到下、行内左到右"]
  IV --> J["ImageTranslationBlock<br/>bbox + OCR + 方向证据 + 译文"]
  IH --> J
  J --> IQUALITY["OCR 结果摘要<br/>平均/低置信 + 竖排/方向待定<br/>全部 / 待复查筛选 + 行级快速复查<br/>逐块翻译中只读定位；锁定时状态行 / VoiceOver 说明原因<br/>仅 translated 后开放复查/修改<br/>当前图片会话复查进度由 Store 内存持有<br/>误识别忽略快照也仅当前会话保存<br/>新图 / 取消 / 清空按各自语义复位、不落盘<br/>Store-owned 重新识别"]
  IQUALITY --> ISELECT["View 私有 block 选择<br/>结果行取景框 + 预览覆盖高亮<br/>revision / 隐藏筛选清除"]
  IQUALITY --> IA11Y["VoiceOver 连续复查焦点<br/>行 / 局部放大 / 完成态分流<br/>图片覆盖与结果行复用定位提示<br/>加载/失败卡片读出状态与重试边界<br/>命令栏提示操作影响范围<br/>revision 拒收旧焦点"]
  IQUALITY --> ICORRECT["44pt 人工修正<br/>仅 translated + 非导出重绘开放<br/>非空校验 + 保存中锁定<br/>首尾空白规范化 + View 私有键盘焦点"]
  ICORRECT -. "打开修正页：结果行入口登记结果行回退；局部预览入口登记同一局部预览回退" .-> IA11YHANDOFF
  ICORRECT --> ICORRECTCONTEXT["修正 sheet 局部对照<br/>既有 2048px 预览裁切 + 黄色 bbox<br/>低置信 / 方向待定提示；失败不阻止编辑"]
  ICORRECTCONTEXT -. "语义修改才放弃确认；无修改 / trim 后仍等于原文可关闭" .-> IA11YHANDOFF
  ICORRECTCONTEXT --> IKEYBOARD["多行 OCR 输入<br/>键盘“完成” / 滚动时交互收起 / 取消 / 忽略确认 / 保存前清焦点<br/>保存中锁定输入；只改 View 键盘焦点／可见性"]
  ICORRECTCONTEXT --> IIGNORECONFIRM["识别有误？<br/>忽略文字块的明确确认<br/>未保存修正不会保存"]
  IIGNORECONFIRM -->|"确认"| IIGNORED["Store 当前会话快照<br/>原始顺序 + 人工修正 / Vision 基线<br/>移除 active block / preview / export / transcript<br/>不重新 OCR 或翻译"]
  IIGNORECONFIRM -->|"继续编辑"| ICORRECTCONTEXT
  IIGNORED --> IIGNOREDRESTORE["检查区已忽略列表<br/>仅 translated + 非导出重绘的 44pt 恢复动作<br/>可访问焦点；按原顺序插回，风险块重回待复查"]
  IIGNORED --> IRENDER
  IIGNOREDRESTORE --> IRENDER
  IKEYBOARD --> INORMALIZE{"trim 后原文改变?"}
  INORMALIZE -->|"否"| INOOP["确认无误<br/>Store no-op 标记复查<br/>不调用模型"]
  INOOP -. "sheet 关闭后复用既有成功焦点交接" .-> IA11YHANDOFF
  INORMALIZE -->|"是"| ICORRECTGATE{"correction ID + 图片 task ID<br/>block ID + 旧原文快照仍匹配?"}
  ICORRECTGATE -->|"否 / 翻译失败"| ICORRECTKEEP["保留旧 block / transcript / export"]
  ICORRECTGATE -->|"是"| ICORRECTCOMMIT["只重译目标 block<br/>成功确认风险块加入当前会话复查进度<br/>更新当前图片 transcript<br/>撤销旧 export/share"]
  ICORRECTCOMMIT --> IRENDER
  IIGNORED -. "sheet 关闭后（若有后继焦点）" .-> IA11YHANDOFF["View 私有焦点交接<br/>记录目标 focus ID + image revision<br/>onDismiss 核对后才发布"]
  ICORRECTCOMMIT -. "成功后覆盖回退；sheet 关闭后队列前进或回到已更新行" .-> IA11YHANDOFF
  IA11YHANDOFF -. "复用既有 revision/yield 焦点发布" .-> IA11Y
  ICORRECTCOMMIT --> IRESTORECONFIRM["已修正 block 的 44pt 恢复动作<br/>先确认移除本次人工修正；关闭后才交接焦点"]
  IRESTORECONFIRM -->|"确认"| IRESTORE["恢复 Vision OCR 原文 + 初始译文<br/>移除当前会话复查标记<br/>不调用模型，重新打开风险复查"]
  IRESTORECONFIRM -->|"取消 / 图片 revision 已变化"| IRESTOREKEEP["保留当前人工修正"]
  IRESTORE --> IRENDER
  IRESTORE --> IRESTOREA11Y["View 私有确认框关闭后焦点交接<br/>isPresented 关闭 + revision 核对后才发布"]
  IRESTOREA11Y -. "复用既有 revision/yield 焦点发布" .-> IA11Y
  ISELECT --> IFOCUS["已下采样预览局部裁切<br/>保留上下文 + bbox 再标记<br/>44pt 关闭 + 修正命令"]
  IFOCUS -->|"44pt 直接修正；仅 translated + 非导出重绘<br/>忙碌 / stale 时拒绝；非成功 onDismiss 回到同一局部预览"| ICORRECT
  ISELECT --> ISCROLL["唯一 workspace anchor<br/>新选择滚回图片工作区<br/>Reduce Motion 立即定位"]
  IFOCUS --> INAV["当前筛选序列前后导航<br/>位置值 + 首尾禁用<br/>可用/首尾分别说明定位与边界<br/>44pt 命名按钮"]
  IFOCUS -. "只联动展示；完整 blocks 不变" .-> IPREVIEW
  INAV -. "只更新 View 私有选择" .-> IPREVIEW
  IA11Y -. "只更新 View 私有焦点" .-> IPREVIEW
  IQUALITY -. "仅筛检查列表；完整 blocks 不变" .-> IPREVIEW
  J --> IPREVIEW["后台 ImageIO 预览下采样<br/>最大边 2048px + EXIF transform<br/>revision / cancellation 拒收旧结果<br/>准备 / 失败 / 本地重试反馈<br/>VoiceOver 容器汇总块数 / 待复查 / 定位；背景图隐藏"]
  IPREVIEW --> K["图片旁贴 / 覆盖 UI<br/>同模式顶左坐标 PNG 导出"]
  K --> IRENDER["覆盖模式重渲染<br/>rendering / failed / retry<br/>render ID 拒收晚到结果"]
  K --> IEXPORT["Store-owned 稳定导出<br/>新任务 / 清空 / 重渲染时清理"]
  ISTART["App 启动 workspace reconciliation<br/>marker + render UUID 导出 / task UUID 输入 / render UUID staging"] --> IEXPORT
  IEXPORT --> IGUARD{"直属 aitrans-export-renderUUID-*<br/>常规文件?"}
  IGUARD -->|是| IDELETE["删除被替代导出"]
  IGUARD -->|否| IREJECT["拒绝任意文件名 / wrong-kind / escape<br/>symlink / dangling symlink"]
  IDELETE --> IFAIL{"删除成功或已不存在?"}
  IFAIL -->|否| IKEEP["保留私有 ownership<br/>后续生命周期重试"]
  IEXPORT --> ISHARE["Store-owned 分享目录<br/>preparing / failed 反馈<br/>share UUID / 可读 leaf filename"]
  ISHARE --> ISHAREEND["dismiss / export 失效 / 启动<br/>request ID 拒收晚到并清理"]

  %% 音频分支：Apple 本机语音识别
  C --> LR["Speech run ID + store-owned translation Task<br/>取消 / 重试使旧回调失效"]
  LR --> L["音频识别<br/>Apple Speech on-device / requiresOnDeviceRecognition"]
  L --> LA{"授权 / 翻译 await 后<br/>run ID 与冻结配置仍有效?"}
  LA -->|否| LD["丢弃旧回调<br/>不写 state / transcript / summary"]
  LA -->|是| D
  L --> LV["speechRecognitionRunSummary<br/>输入 / locale / 耗时 / 词数 / 片段 / 置信度 / 失败原因"]
  AX["录音默认 accessibility action<br/>开始 / 停止"] --> L
  LC["checking / recognizing / translating<br/>均可取消"] --> LR

  %% Speech 质量分支：真实 corpus 事后评估
  C --> SQ["Speech quality probe<br/>versioned corpus + audio identity"]
  SQ --> SQR["Apple Speech URL recognition<br/>on-device required"]
  SQR --> SQE["事后 evaluator<br/>WER / CER / latency / confidence"]
  REF["reference transcript"] -. "只在最终识别文本返回后参与评估" .-> SQE
  SQE --> SQO["speech_quality_report.json / .txt<br/>failure breakdown + runtime identity"]

  SETTINGS["Settings NavigationPath"] --> DEVRESET{"开发模式仍开启?"}
  DEVRESET -->|"否"| SETTINGSROOT["清空 path / 返回设置根页"]

  %% 漫画探针分支：固定 test/1.png
  C --> M["漫画覆盖翻译探针<br/>test/1.png"]
  M --> N["MangaOverlayProbeService<br/>裁切、多角度 OCR、气泡归属、合并"]
  N --> O["逐块翻译和质量判定<br/>失败块仍写报告和绘制"]
  O --> P["探针模式门控<br/>ci-fast / full / skip"]
  P --> Q["覆盖渲染<br/>safeLayoutRect / glyph mask / 核心 PNG"]

  %% 输出：持久化和调试产物
  C --> R["state.json<br/>会话、历史、提示词、设置"]
  PREVIEW["隔离 Preview / DEBUG UI evidence 场景"] -. "仅展示状态，不执行业务服务" .-> B
  CONTRACT["v1.87 UI interaction contract<br/>动作接线 / AX / 导航 / Reduce Motion"] -. "CI 独立 testcase" .-> B
  HOME_CONTRACT["v1.88 home UI contract<br/>paste / keyboard / 背景 / 首页动作"] -. "CI 独立 testcase" .-> B
  Q --> S["App 沙盒 Output<br/>JSON / TXT / PNG"]
  M -. "报告已生成后仅读取 existing readiness" .-> DEVREADY["开发控制台 Koharu 就绪摘要<br/>ready / missing / invalid<br/>可复制缺件与 nextAction；shadow-only"]
  S --> T["scripts/export-probe-output.sh<br/>导出到项目根 output/"]
  T --> U["metrics/version_history.csv<br/>长期指标 append-only"]
```

## 2. Agent 迭代流程图
这张图描述以后每轮任务如何从人工目标进入 Agent A、Agent B、GitHub Actions 和 Agent C。默认重验证在云端，本机只做轻量检查；`main` 不参与日常开发合并。

大版本合入后还必须执行一次首次使用体验闸门；具体日志字段、100 ms 底线、截图/产物清理和状态转移见 [`experience-iteration.md`](experience-iteration.md)。

范围选择先读取 `git diff --name-only <base>...HEAD`：所有任务保留 diff/路由基线；App 代码、工程或资源再保留基础 iOS simulator build；其余只跑本次命中的直接合同。`test/2.png`、截图、探针、GGUF、授权语料和目标设备属于显式可选证据。

```mermaid
flowchart TD
  %% 人工输入：目标和约束
  H["人工提出目标<br/>功能、边界、禁止项、验收标准"] --> A1["Agent A<br/>读入口文档、历史、flow、test 和相关源码"]

  %% 先按 changed-files 选择范围
  A1 --> S0["读取 diff<br/>baseline + direct + optional"]

  %% Agent A 输出版本化提示词
  S0 --> A2["Agent A 分析<br/>目标、非目标、风险、测试、验收"]
  A2 --> P["md/prompt/vX（阶段）/vX.Y（任务）.md<br/>写给 Agent B 的实现提示词"]

  %% Agent B 实现、轻量检查和推送
  P --> B0["从 smalldata_test 开分支<br/>codeb/vX.Y-短标题"]
  B0 --> B1["Agent B<br/>按提示词小步实现"]
  B1 --> B2["本地轻量检查<br/>git diff --check / JSON / YAML smoke"]
  B2 --> B3["集中 push 候选核心 commit<br/>codeb/... / 不合并 main"]

  %% 云端验证和结果包
  B3 --> GF["Task-scoped full（一次）<br/>基础静态 + 相关领域契约 + 必要 Xcode build"]
  GF --> RCP["full-validation status<br/>绑定候选 SHA"]
  RCP --> B4["创建 PR<br/>base=smalldata_test / head=codeb/..."]
  B4 --> GFAST["PR fast follow-up<br/>opened / reopened / ready<br/>不监听 synchronize"]
  G0["workflow_dispatch<br/>full / fast / ci-fast / UI evidence"] --> G1["GitHub Actions task router"]
  GF --> G1
  GFAST --> G1
  G1 --> G2["未加密 CI 结果包<br/>profile / reuse receipt / required flags / logs / manifest"]
  PKG["手动 workflow_dispatch"] --> G3["加密 IPA 打包<br/>仅软件包交付，Agent C 不以此验收"]

  %% Agent C 验收和文档同步
  G2 --> C1["Agent C<br/>核对 HEAD commit、diff、Actions 结论、日志和 artifact"]
  C1 --> CFail{"是否通过"}
  CFail -- "失败" --> R["退回清单<br/>B 修复 push 后重新跑对应 full"]
  R --> B1
  CFail -- "通过" --> C2["更新核心文档<br/>flow.md / flowchart.md / update_log.md"]
  C2 --> C3["PR merge 到 smalldata_test<br/>禁止合并到 main"]
  C3 --> MR{"第二父 SHA<br/>full status = success?"}
  MR -- "是" --> MF["merge fast follow-up<br/>不重复 Xcode / 大契约 / 截图<br/>传播 full receipt 到 merge SHA"]
  MR -- "否" --> MFULL["自动回退 task-scoped full"]
  MF --> C4
  MFULL --> C4
  C4["删除远端 codeb/...<br/>避免候选分支堆积"]
  C4 -. "后续 smalldata_test 纯元数据 push" .-> DM{"父 propagated receipt<br/>是否为 success?"}
  DM -- "是" --> DFAST["fast follow-up<br/>记录父 receipt / 非新编译证据"]
  DM -- "否" --> DFULL["full + 当前 HEAD Xcode build"]

  %% 回到人工
  C4 --> H2["人工复核<br/>确认后进入下一轮"]
  DFAST --> H2
  DFULL --> H2
  H2 --> H
```

# AITRANS 流程图

本文件只提供与 [`flow.md`](flow.md) 对齐的当前流程图，不记录版本演进、测试结果或 CI 日志。

## 1. App 架构

```mermaid
flowchart TD
  APP["AITRANSApp"] --> UI["SwiftUI Views\n七个功能入口"]
  UI --> STORE["TranslationSessionStore\n唯一翻译业务状态与调度中心"]
  UI --> BROWSER2["MangaBrowserView\nBrowserModel tabs -> 当前 WKWebView"]
  BROWSER2 --> BCAP2["可视区/框选抓图 -> Store OCR/翻译 -> 覆盖层"]
  BCAP2 -. "不进入普通图片 / OCR-only / 历史持久化" .-> END_BROWSER["浏览器翻译与安全独立链路"]

  STORE --> TEXT["文本翻译"]
  STORE --> IMAGE["图片翻译"]
  STORE --> OCR["OCR 检测\nOCR-only"]
  STORE --> SPEECH["Apple Speech"]
  STORE --> HISTORY["历史 / 设置 / 持久化"]
  STORE --> PROBE["漫画覆盖诊断"]

  TEXT --> MODEL["MockGemmaService\n或 GemmaLocalService"]
  IMAGE --> VISION["VisionOCRService"]
  OCR --> VISION
  VISION --> APPLE["Apple Vision OCR"]
  VISION --> DETECTOR["Comic text detector"]
  VISION --> MANGA["Bundled Manga OCR"]
  VISION --> LAYOUT["ImageOCRLayoutEngine"]
  LAYOUT --> MODEL
  SPEECH --> MODEL
  MODEL --> LLAMA["LlamaRuntime / llama.cpp / GGUF"]

  STORE --> STATE["state.json"]
  PROBE --> OUTPUT["JSON / TXT / PNG\nApp Output -> repository output/"]
```

## 2. 图片与 OCR

```mermaid
flowchart TD
  INPUT["照片 / 相机 / 文件 / 剪贴板"] --> TASK["Store 建立 task + revision"]
  TASK --> VISION["Apple Vision OCR"]
  VISION --> JAPANESE{"日语漫画或竖排场景?"}
  JAPANESE -- "是" --> DETECT["文字区域检测"]
  DETECT --> MANGA["Bundled Manga OCR\n受控局部补读"]
  JAPANESE -- "否" --> MERGE["候选集合"]
  MANGA --> MERGE
  MERGE --> LAYOUT["几何校验 / 融合 / 阅读顺序"]
  LAYOUT --> BLOCKS["ImageTranslationBlock"]

  BLOCKS --> MODE{"入口"}
  MODE -- "图片翻译" --> TRANSLATE["逐块本地翻译"]
  TRANSLATE --> REVIEW["复查 / 修正 / 忽略与恢复"]
  REVIEW --> RENDER["旁贴 / 覆盖 / 导出"]

  MODE -- "OCR 检测" --> OCRONLY["定位 / 筛选 / 编辑 / 复制 / TXT / JSON"]
  OCRONLY -. "不调用 LLM\n不写普通图片会话" .-> END["结束"]

  TASK -. "取消、替换或重试" .-> INVALIDATE["旧 revision 失效"]
  INVALIDATE -. "晚到结果拒收" .-> BLOCKS
```

## 3. 音频

```mermaid
flowchart TD
  AUDIO["麦克风或音频文件"] --> RUN["Store 建立 Speech run ID"]
  RUN --> AUTH["权限与设备侧识别能力"]
  AUTH --> RECOGNIZE["Apple Speech recognition"]
  RECOGNIZE --> CHECK{"run ID 仍有效?"}
  CHECK -- "否" --> DROP["丢弃旧回调"]
  CHECK -- "是" --> TRANSCRIPT["最终 transcript"]
  TRANSCRIPT --> TRANSLATE["任务开始时冻结的翻译配置<br/>Apple Translation / Gemma / 预留"]
  TRANSLATE --> RESULT["识别文本 / 译文 / 运行摘要"]

  TRANSCRIPT -. "质量探针时，识别完成后才读取" .-> REF["reference transcript"]
  REF --> EVAL["WER/CER / latency / confidence"]
  EVAL --> REPORT["speech quality report"]
```

## 4. 漫画覆盖诊断

```mermaid
flowchart TD
  SOURCE["test/1.png"] --> CROP["内容区裁切"]
  CROP --> OCR["OCR / 漫画区域 / 方向候选"]
  OCR --> FUSION["逻辑文字块融合与阅读顺序"]
  FUSION --> TRANSLATION["逐块翻译与质量判定"]
  TRANSLATION --> FAIL["失败块仍保留原文和原因"]
  FAIL --> RENDER["debug / OCR / translated overlay"]
  FAIL --> REPORT["probe_report / clean text / text snapshot"]
  RENDER --> SANDBOX["App 沙盒 Output"]
  REPORT --> SANDBOX
  SANDBOX --> EXPORT["export-probe-output.sh"]
  EXPORT --> ROOT["repository output/"]

  SHADOW["Koharu / TextBox / Mask / benchmark"] -. "diagnostic / shadow-only\n明确晋级前不改产品路径" .-> REPORT
  GT["ground truth"] -. "仅事后匹配与统计" .-> REPORT
```

## 5. Agent 迭代

```mermaid
flowchart TD
  GOAL["用户目标与边界"] --> READ["读 AGENTS / status / index / 相关源码"]
  READ --> SCOPE["确定 changed-files\nbaseline + direct + optional"]
  SCOPE --> ROLE{"角色"}

  ROLE -- "Agent A" --> PROMPT["生成版本化实施提示词"]
  PROMPT --> B["Agent B 从 smalldata_test 建 codeb/... 分支"]
  ROLE -- "普通任务 / Agent B" --> B
  B --> IMPLEMENT["小步实现，保留用户改动"]
  IMPLEMENT --> LIGHT["本地轻量检查"]
  LIGHT --> FULL["候选 SHA task-scoped full"]
  FULL --> REVIEW["Agent C 核对 diff、SHA、CI、artifact"]
  REVIEW --> PASS{"通过?"}
  PASS -- "否" --> FIX["退回具体失败与日志位置"]
  FIX --> IMPLEMENT
  PASS -- "是" --> MERGE["合并到 smalldata_test\n禁止 main"]
  MERGE --> CLEAN["清理候选分支"]
  CLEAN --> DOCS["仅按职责更新稳定文档\n历史与验证写 md/log/"]
  DOCS --> DONE["交付结果与未验证范围"]
```

流程图只在架构、ownership 或长期工作流变化时修改；单次版本、合同、CI 或指标变化只写入 `md/log/`。
