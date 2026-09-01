# AITRANS

AITRANS 是一个面向 iPhone 和 iPad 的本地 AI 翻译原型。它把文本翻译、图片 OCR 翻译、独立 OCR 检测、Apple Speech 音频识别和本地 GGUF 推理放在同一个 SwiftUI App 中，尽量让内容留在设备内处理。

## 主要功能

- 文本翻译：输入或粘贴文本，使用 Mock 或本地 GGUF 模型生成译文与摘要。
- 图片翻译：从照片、相机、文件或剪贴板导入图片，识别文字块、逐块翻译、复查 OCR，并生成旁贴或覆盖效果。
- OCR 检测：只执行文字检测与识别，支持块定位、筛选、编辑、复制以及 TXT/JSON 导出，不调用翻译模型。
- 日语漫画 OCR：Apple Vision OCR 负责通用识别，漫画文字检测器和随包 Manga OCR Core ML 模型补充日语漫画、竖排和局部文字区域，再由布局引擎融合与排序。
- 音频翻译：通过 Apple Speech 识别麦克风或音频文件，再把最终文本交给当前翻译引擎。
- 历史、提示词、模型管理、Pro 占位和开发诊断入口。

## 架构概览

```text
SwiftUI Views
  -> TranslationSessionStore
     -> VisionOCRService
        -> Apple Vision OCR
        -> ComicTextBubbleDetectorService + MangaOCRService
        -> ImageOCRLayoutEngine
     -> GemmaLocalService -> LlamaRuntime -> llama.cpp / GGUF
     -> Apple Speech + Speech quality evaluator
     -> persistence / export / diagnostic reports
```

- `TranslationSessionStore` 是唯一业务状态与调度中心。
- `VisionOCRService` 统一普通图片 OCR；日语场景按需调用检测器和 Manga OCR。
- `ImageOCRLayoutEngine` 负责文字块几何、融合、阅读顺序和复查风险。
- `MangaOverlayProbeService` 是开发诊断链路，不等同普通图片产品路径。
- `MockGemmaService` 便于无模型时验证 UI；`GemmaLocalService` 和 `LlamaRuntime` 负责真实本地推理。

更细的代码入口见 [`md/index/index.md`](md/index/index.md)，跨层流程见 [`md/flow/flow.md`](md/flow/flow.md)。

## 本地模型

App 内置下载项是 `Gemma 3 270M IT QAT Q4_0`。它体积小，适合验证下载、SHA256 校验、导入、加载和 llama.cpp 接线，不适合作为翻译质量基准。

也可以在模型页导入其他 `.gguf` 文件。需要对比小模型翻译效果时，可使用与当前 runtime 兼容的 Qwen2.5 0.5B Instruct GGUF；更换模型前应先确认 chat template、上下文长度和内存预算。

模型安装后统一保存到 App 沙盒：

```text
Application Support/Models/Gemma-1.5B/model.gguf
```

GGUF 不提交到仓库。删除 App 内模型不会删除用户原始下载文件。

## 环境要求

- macOS 与完整 Xcode。
- iOS 17.0 或更高版本的模拟器/设备。
- Xcode project：`AITRANS.xcodeproj`。
- Scheme/target：`AITRANS`。
- 真机使用相机、麦克风或 Speech 时，需要系统权限和有效签名。

## 编译运行

1. 用 Xcode 打开 `AITRANS.xcodeproj`。
2. 选择 iPhone/iPad 模拟器或已连接设备。
3. 运行 `AITRANS` scheme。

命令行模拟器构建：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project AITRANS.xcodeproj \
  -scheme AITRANS \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath .derivedData \
  CODE_SIGNING_ALLOWED=NO build
```

如果需要重建随 App 使用的 iOS llama framework：

```sh
git clone --depth 1 https://github.com/ggml-org/llama.cpp.git third_party/llama.cpp
bash Tools/build-llama-ios-xcframework.sh
```

## 快速上手

1. 首次启动可先保留 Mock 引擎，确认文本、图片和历史数据流。
2. 需要真实本地翻译时，在“模型”页下载内置 Gemma 或导入兼容 GGUF，再切换到 Local。
3. 图片页适合 OCR 后直接翻译和覆盖；“OCR 检测”页适合只检查文字块、原文与几何。
4. 音频页选择实时录音或音频文件；识别完成后才进入翻译。
5. 开发诊断、固定素材和质量探针按 [`md/test/test.md`](md/test/test.md) 执行，不把探针结果当作产品质量结论。

## 数据与隐私

- 会话和设置保存在 App 沙盒 `Application Support/AITRANS/`。
- 本地 GGUF 推理、Apple Vision OCR 和可用时的 on-device Speech 都在设备侧运行。
- 清空历史、替换图片、取消任务和删除模型通过 Store 管理，异步旧任务不会覆盖新会话。
- `test/`、`output/` 和 benchmark 是开发验证边界，不存放用户正式数据。

## 文档

- [`AGENTS.md`](AGENTS.md)：协作规则与核心迭代流程。
- [`md/index/index.md`](md/index/index.md)：代码定位索引。
- [`md/flow/flow.md`](md/flow/flow.md)：当前架构与数据流。
- [`md/test/test.md`](md/test/test.md)：测试选择、Speech/漫画探针和 CI 规则。
- [`md/log/update_log.md`](md/log/update_log.md)：版本更新与验证历史。

README 只维护稳定的项目介绍、架构、模型和上手方式；版本日志、CI run、提交记录和逐版行为不写在这里。
