# 资源与工程

> 状态：current。记录 target membership、随 App 打包的模型/词表、构建依赖和测试资源；不把二进制依赖当作业务源码。

## 边界

本模块负责 Xcode 工程清单、Info.plist、Assets.xcassets、bundled Core ML 模型、Manga OCR 词表、`llama.xcframework` 和 `test/` 资源。模型推理算法由 OCR/translation 模块拥有，资源授权/identity 证据由 validation 模块拥有。

## 快速定位

| 任务 | 文件/目录 | 关键入口 |
| --- | --- | --- |
| target、源码/资源编入、版本 | [`AITRANS.xcodeproj/project.pbxproj`](../../../AITRANS.xcodeproj/project.pbxproj) | `AITRANS` target、`MARKETING_VERSION`、Sources/Resources phases |
| App bundle 配置 | [`AITRANS/Resources/Info.plist`](../../../AITRANS/Resources/Info.plist) | bundle ID、权限和资源声明 |
| 漫画文字 detector | [`AITRANS/Resources/ComicTextDetector/`](../../../AITRANS/Resources/ComicTextDetector/) | `ComicTextBubbleDetectorINT8.mlpackage`、license/notice |
| bundled Manga OCR | [`AITRANS/Resources/MangaOCR/`](../../../AITRANS/Resources/MangaOCR/) | encoder/decoder（单 crop + batch）、`MangaOCRVocab.txt`、license/notice |
| UI 颜色/图标 | [`AITRANS/Resources/Assets.xcassets/`](../../../AITRANS/Resources/Assets.xcassets/) | colorsets、AppIcon |
| llama.cpp Apple framework | [`build-apple/llama.xcframework/`](../../../build-apple/llama.xcframework/) | tracked build dependency；不在业务索引内展开 |
| 固定输入/语料 | [`test/`](../../../test/) | `1.png`、`2.png`、`jap.jpg`、ground truth、speech corpus |

## 资源数据流

```text
project.pbxproj
  -> App target membership
  -> App bundle: Info.plist + Assets + Core ML + vocab + test/
  -> Services load resources from Bundle.main
  -> validation checks identity/shape/readiness
```

## 权威边界与禁止路径

- `project.pbxproj` 是 target membership 和工程版本的权威来源；README/历史文档中的版本只作说明。
- `AITRANS/Resources/MangaOCR` 与 `ComicTextDetector` 是已打包的产品资源；`reference/koharu-main`、外部 MIT48 权重和 ignored `third_party/llama.cpp` 不得被误加入 App bundle。
- license/notice 与模型资源必须一起保留；替换模型需核对输入 shape、量化、词表、授权和云端 runtime evidence。
- `test/1.ground_truth.json` 只能用于 benchmark/probe；不能进入生产 OCR/翻译候选选择。

## 相关索引

- [`完整 App/资源/工程文件图`](index-assets-file-map.md)
- [`资源加载、授权与构建依赖`](index-assets-resources.md)
- [`图片 OCR 资源消费`](../index-image/index-image-ocr.md)
- [`翻译模型文件与下载`](../index-translation/index-translation-runtime.md)
- [`CI artifact/identity`](../index-validation/index-validation-ci.md)

## 何时更新本索引

新增/移除 target resource、Core ML package、词表、framework、bundle test input、权限或版本字段时更新；只改服务实现不改变资源边界时不用上提。
