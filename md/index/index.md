# AITRANS 代码索引

> 状态：current。这里是 Agent 的日常代码定位入口；完整流程、版本历史和测试制度由各自权威文档负责。

## 使用顺序

1. 先根据任务关键词查本页的路由。
2. 进入对应二级模块索引，再只读相关三级主题。
3. 按三级索引中的符号、调用方和最小测试集合打开源码。
4. 如果实际 diff 与索引不一致，以源码为准，并在同轮修正索引。

## 代码根、测试根与范围

| 根目录/入口 | 作用 | 日常索引范围 |
| --- | --- | --- |
| [`AITRANS/`](../../AITRANS/) | SwiftUI App、状态模型、服务和随 App 打包的资源 | 当前源码与产品资源 |
| [`test/`](../../test/) | 固定图片、ground truth 和语音语料入口 | 手工/云端验证输入；不当作生产代码 |
| [`scripts/`](../../scripts/) | 静态合同、评估器、云端 smoke、runtime harness | 按主题路由；版本合同不逐篇通读 |
| [`benchmarks/`](../../benchmarks/) | OCR、翻译、渲染 benchmark 的 schema、fixture 和 README | 基准协议与 artifact 输入 |
| [`.github/workflows/`](../../.github/workflows/) | CI、结果包、test2 UI 和手动 parity workflow | 验证入口与条件 |
| [`AITRANS.xcodeproj/project.pbxproj`](../../AITRANS.xcodeproj/project.pbxproj) | 单 App target 的源码/资源编入和工程版本 | 工程边界 |
| [`md/`](../) 与根目录文档 | flow、测试规范、prompt、历史记录和协作规则 | 只按主题读取 |

下列内容不进入日常源码索引：`.build/`、`.derivedData*` 等 ignored 构建缓存，`reference/koharu-main/` 的外部 checkout，`third_party/llama.cpp/` 的 ignored 第三方源码，以及 `output/` 中由探针产生的结果文件。已跟踪的 [`build-apple/llama.xcframework/`](../../build-apple/llama.xcframework/) 属于构建依赖，保留在资源/工程索引中但不当作业务源码；`AITRANS.xcodeproj/xcuserdata/` 同样不作为稳定入口。

## 二级模块路由

| 模块 | 边界 | 二级索引 |
| --- | --- | --- |
| 应用状态与界面 | App 入口、`TranslationSessionStore`、SwiftUI 屏幕、复查操作和持久化投影 | [`index-app/`](index-app/index-app.md) |
| 图片 OCR 与版面 | Vision OCR、漫画文字检测、bundled Manga OCR、几何融合和日语阅读顺序 | [`index-image/`](index-image/index-image.md) |
| 本地翻译与模型运行时 | GGUF 下载、chat/raw 推理、prompt profile、翻译清洗和批量 QA | [`index-translation/`](index-translation/index-translation.md) |
| 音频与语音质量 | Apple Speech 运行、run-id/取消、质量评估与语料报告 | [`index-speech/`](index-speech/index-speech.md) |
| 验证、基准与 CI | 静态合同、benchmark schema、云端评估、结果包和 workflow 分流 | [`index-validation/`](index-validation/index-validation.md) |
| 资源与工程 | Xcode target、Info.plist、Core ML/词表、llama.xcframework 和测试资源 | [`index-assets/`](index-assets/index-assets.md) |

## 按任务关键词快速路由

| 任务关键词 | 先读 |
| --- | --- |
| 文本首页、图片页、复查、焦点、VoiceOver、导出 | [`应用/UI`](index-app/index-app-ui.md)、[`应用状态`](index-app/index-app-state.md) |
| 漫画浏览器、WKWebView、地址栏、网页失败、翻译悬浮球 | [`应用/UI`](index-app/index-app-ui.md) |
| `test/2.png`、普通图片 OCR、竖排日语、Vision、Manga OCR、bbox/quad | [`OCR 主路径`](index-image/index-image-ocr.md)、[`布局与融合`](index-image/index-image-layout.md) |
| OCR block 合并、owner、reading order、confidence、重复文本 | [`布局与融合`](index-image/index-image-layout.md) |
| 翻译 prompt、GGUF、chat template、raw completion、模型下载 | [`模型运行时`](index-translation/index-translation-runtime.md) |
| 术语记忆、跨 batch context、标签、逐块翻译 QA、源文泄漏 | [`翻译 QA/context`](index-translation/index-translation-qa.md) |
| 音频录音、Apple Speech、取消、CER/WER、corpus | [`语音运行`](index-speech/index-speech-runtime.md)、[`语音质量`](index-speech/index-speech-quality.md) |
| 合同、评估器、fixture、benchmark、holdout、CI profile | [`合同目录`](index-validation/index-validation-contracts.md)、[`基准`](index-validation/index-validation-benchmarks.md)、[`CI`](index-validation/index-validation-ci.md) |
| 大版本体验验证、自迭代、首次使用、操作日志 | [`体验验证流程`](../flow/experience-iteration.md)、[`体验状态`](../../experience_state.md) |
| Core ML 资源、词表、工程版本、target membership、bundle | [`资源与工程`](index-assets/index-assets.md)、[`完整文件图`](index-assets/index-assets-file-map.md) |

## 当前主数据流

```text
AITRANSApp
  -> ContentView / AppTabRouter
  -> 漫画浏览器：MangaBrowserView -> BrowserModel -> WKWebView（不进入翻译/持久化）
  -> TranslationSessionStore（唯一运行时状态与调度边界）
     -> OCR 检测：ImageOCRDetectionView
        -> 图片/相册/拍照/粘贴 -> VisionOCRService
        -> ImageTranslationBlock（OCR-only，不进入翻译/LLM）
        -> 原图 bbox overlay -> 复查/编辑/复制/TXT/JSON
     -> 普通图片：VisionOCRService
        -> 日语时的 detector / bundled MangaOCR 补充
        -> ImageOCRLayoutEngine
        -> ImageTranslationBlock
        -> GemmaLocalService / TranslationBatchQualityEvaluator
     -> 文本/图片翻译：GemmaLocalService -> LlamaRuntime -> Store
     -> 音频：Apple Speech -> Store -> GemmaLocalService
  -> SwiftUI Views（只读 Store 投影并调用 Store 方法）
```

`MangaOverlayProbeService` 是独立的漫画覆盖诊断链路，不等同普通图片主路径；它的报告、外部 artifact 和探针输出由验证索引管理。

## 文档职责边界

- 本索引：短路由、源码符号、调用关系、权威状态和最小验证入口。
- [`md/flow/flow.md`](../flow/flow.md)：当前完整架构、跨层流程和时序关系。
- [`md/flow/flowchart.md`](../flow/flowchart.md)：人工查看的流程图；不替代源码索引。
- [`md/test/test.md`](../test/test.md)：测试制度、探针边界和验证选择依据。
- [`md/flow/experience-iteration.md`](../flow/experience-iteration.md)：大版本首次使用体验闸门和证据边界。
- [`experience_state.md`](../../experience_state.md)：当前版本、上轮体验结论、未解决问题和下一步；只保留一份精简状态。
- [`md/log/update_log.md`](../log/update_log.md)：版本决策、证据和遗留问题；不复制到索引。
- [`md/prompt/`](../prompt/)：版本化 Agent A 任务 prompt；不作为当前源码结构的权威来源。
- [`README.md`](../../README.md)：简明项目介绍、架构、模型和上手说明，不承担代码路由。

## 长期维护规则

- 新增稳定职责模块先建二级目录，再建至少一个三级主题索引。
- 新增 Swift 源码、测试入口、资源或 workflow 必须能在本索引或对应三级“完整文件图/合同目录”中检索到。
- 局部变化只更新相关三级索引；只有权威状态、主数据流、target 或模块边界变化才上提二级/一级。
- 索引不记录版本流水账；历史证据放 `md/log/`，真实源码和实际验证结果优先于旧文档。
- 维护时排除 ignored、第三方、缓存、生成物和外部 reference；若 tracked 依赖有入口，标明“依赖”而不是“业务源码”。
- 结构变化后至少执行：`git diff --check`、索引 Markdown 链接检查、源码/测试路径存在性检查；涉及工程/配置时再执行对应 JSON/YAML/plist 解析。

### 不新增维护脚本的轻量自检

在仓库根目录执行以下命令即可完成索引自检；Python 片段只读取文件，不启动 App、Xcode、Core ML、Rust 或外部 runtime：

```sh
git diff --check
rg --files md/index | sort
python3 - <<'PY'
from pathlib import Path
import re

root = Path.cwd()
index_root = root / "md" / "index"
errors = []
for doc in index_root.rglob("*.md"):
    text = doc.read_text(encoding="utf-8")
    for target in re.findall(r"\]\(([^)#]+)(?:#[^)]+)?\)", text):
        if "://" in target or target.startswith("mailto:"):
            continue
        path = (doc.parent / target).resolve()
        if not path.exists():
            errors.append(f"{doc.relative_to(root)} -> {target}")
if errors:
    raise SystemExit("broken index links:\n" + "\n".join(errors))
print("index markdown links: ok")
PY
```
