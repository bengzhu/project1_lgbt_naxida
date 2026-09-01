# 资源加载、授权与构建依赖

> 状态：current。主题是“资源如何进入 bundle、由谁加载、哪些依赖只用于构建/云端”；不重复 OCR/翻译算法细节。

## 快速定位

| 资源/边界 | 路径 | 消费方 |
| --- | --- | --- |
| App bundle 与权限 | [`AITRANS/Resources/Info.plist`](../../../AITRANS/Resources/Info.plist) | `AITRANSApp`、系统权限/资源查找 |
| 颜色与图标 | [`AITRANS/Resources/Assets.xcassets/`](../../../AITRANS/Resources/Assets.xcassets/) | `AppTheme`、共用 UI components |
| 文字 detector Core ML | [`AITRANS/Resources/ComicTextDetector/`](../../../AITRANS/Resources/ComicTextDetector/) | `ComicTextBubbleDetectorService` 从 `Bundle.main` 加载 |
| Manga OCR Core ML/词表 | [`AITRANS/Resources/MangaOCR/`](../../../AITRANS/Resources/MangaOCR/) | `MangaOCRService` 从 `Bundle.main` 加载 |
| llama.cpp framework | [`build-apple/llama.xcframework/`](../../../build-apple/llama.xcframework/) | `LlamaRuntime` 的模块链接；tracked build dependency |
| App 测试输入 | [`test/`](../../../test/) | `TranslationSessionStore` 启动测试、benchmark/test2 workflow |

## 加载与授权边界

- Core ML package、词表和 `test/` 是否进 App bundle，以 [`AITRANS.xcodeproj/project.pbxproj`](../../../AITRANS.xcodeproj/project.pbxproj) 的 Resources build phase 为准；服务中的资源名必须与 bundle 名一致。
- detector/Manga OCR 的 Apache notice/license 与模型文件属于同一资源边界，替换或移动模型时同步核对授权、输入 shape 和 conversion metadata。
- `build-apple/llama.xcframework` 是本地 Apple 构建依赖；`third_party/llama.cpp` 和 `reference/koharu-main` 是 ignored/external 范围，不应被索引成当前产品源码或打包资源。
- `test/1.ground_truth.json`、benchmark examples 和 `output/` 报告属于验证数据；它们不能绕过 Store/OCR/translation 的生产 ownership。

## 相关验证

- [`test-v3214-image-japanese-bundled-manga-ocr-contract.py`](../../../scripts/test-v3214-image-japanese-bundled-manga-ocr-contract.py)、[`test-v3216-image-japanese-comic-text-detector-contract.py`](../../../scripts/test-v3216-image-japanese-comic-text-detector-contract.py)：bundle 模型资源与调用边界。
- [`test-v3290-image-translation-render-safety-contract.py`](../../../scripts/test-v3290-image-translation-render-safety-contract.py)：资源/渲染输出安全的相邻边界。
- 工程/资源变更至少做 plist/project 静态解析、`git diff --check`，实际 App/Core ML 运行按 [`CI profile`](../index-validation/index-validation-ci.md) 交给云端。

## 何时更新本索引

新增资源目录、模型 package、词表、framework、license/notice、bundle lookup 或 target membership 时更新；只有算法实现变化时更新对应服务索引。
