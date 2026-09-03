# Apple 原生翻译能力接入指南

覆盖三大场景：**文字翻译**、**图片翻译（OCR + 翻译叠加）**、**对话翻译（语音互译）**，以及贯穿全部场景的**语言选择器**。

全部基于系统自带框架：`Translation`（iOS 17.4+ / 程序化 API 需 iOS 18+）、`Vision` / `VisionKit`（OCR）、`Speech`（语音识别）、`AVFoundation`（语音合成）。**免费、无需 API Key、设备端运行**，不依赖 Apple Intelligence，国行/美版设备理论上都可用。

---

## 0. 前置条件

```
最低部署目标：iOS 18.0（要用程序化 TranslationSession；如果只用系统弹层 .translationPresentation 可以做到 iOS 17.4）
UI 框架：SwiftUI（Translation 的接口只支持 SwiftUI；纯 UIKit 项目需要用 UIHostingController 包一层）
测试环境：必须用真机，模拟器不支持翻译
```

Xcode 项目里导入：

```swift
import Translation
import Vision
import VisionKit
import Speech
import AVFoundation
```

`Info.plist` 需要加的权限（对话翻译要用到麦克风和语音识别）：

```xml
<key>NSMicrophoneUsageDescription</key>
<string>用于识别你说的话并进行翻译</string>
<key>NSSpeechRecognitionUsageDescription</key>
<string>用于将语音转换为文字以便翻译</string>
```

---

## 1. 语言选择器（三个场景通用）

Apple 的语言用 `Locale.Language` 表示，不是简单的字符串。建议做一个统一的语言选择组件，全局复用。

```swift
import Translation

struct LanguageOption: Identifiable, Hashable {
    let id = UUID()
    let language: Locale.Language
    let displayName: String
}

// 常用语言列表（也可以调用 availableLanguages 拿系统实际支持的全集，见下方）
let commonLanguages: [LanguageOption] = [
    .init(language: .init(languageCode: .chinese, region: .china), displayName: "简体中文"),
    .init(language: .init(languageCode: .english, region: .unitedStates), displayName: "English"),
    .init(language: .init(languageCode: .japanese), displayName: "日本語"),
    .init(language: .init(languageCode: .korean), displayName: "한국어"),
    .init(language: .init(languageCode: .french), displayName: "Français"),
    .init(language: .init(languageCode: .german), displayName: "Deutsch"),
    .init(language: .init(languageCode: .spanish), displayName: "Español"),
]
```

获取系统当前**已安装/支持**的语言对（更严谨，翻译前可以检查是否要下载语言包）：

```swift
import Translation

func loadAvailableLanguages() async -> [Locale.Language] {
    let availability = LanguageAvailability()
    return await availability.supportedLanguages
}

// 检查某个语言对的下载状态
func checkStatus(source: Locale.Language, target: Locale.Language) async -> LanguageAvailability.Status {
    let availability = LanguageAvailability()
    return await availability.status(from: source, to: target)
    // 返回值：.installed / .supported（需下载）/ .unsupported
}
```

一个简单的语言选择 UI：

```swift
struct LanguagePickerView: View {
    @Binding var selected: LanguageOption
    let options: [LanguageOption]

    var body: some View {
        Picker("选择语言", selection: $selected) {
            ForEach(options) { option in
                Text(option.displayName).tag(option)
            }
        }
        .pickerStyle(.menu)
    }
}
```

> 源语言建议默认给一个「自动检测」选项——`TranslationSession.Configuration` 的 `source` 传 `nil` 即可触发系统自动识别源语言，不用你自己判断。

---

## 2. 文字翻译接入

### 方式 A：系统自带浮层（最省事，iOS 17.4+）

适合"选中一段文字 → 弹出翻译"这种轻量场景，不用自己写 UI。

```swift
struct TextTranslateView: View {
    @State private var isPresented = false
    let originalText: String

    var body: some View {
        Text(originalText)
            .onTapGesture { isPresented = true }
            .translationPresentation(isPresented: $isPresented, text: originalText)
    }
}
```

### 方式 B：程序化翻译（iOS 18+，自己控制 UI 和结果）—— 推荐

这是你自己做翻译软件最需要的方式，可以拿到译文字符串，自己排版展示。

```swift
struct TranslatorView: View {
    @State private var inputText: String = ""
    @State private var outputText: String = ""
    @State private var sourceLang: LanguageOption = commonLanguages[2] // 日语
    @State private var targetLang: LanguageOption = commonLanguages[0] // 中文
    @State private var configuration: TranslationSession.Configuration?

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                LanguagePickerView(selected: $sourceLang, options: commonLanguages)
                Image(systemName: "arrow.right")
                LanguagePickerView(selected: $targetLang, options: commonLanguages)
            }

            TextEditor(text: $inputText)
                .frame(height: 120)
                .border(.gray.opacity(0.3))

            Button("翻译") {
                // 每次点击触发一次配置，驱动 translationTask 执行
                configuration = TranslationSession.Configuration(
                    source: sourceLang.language,
                    target: targetLang.language
                )
            }

            Text(outputText)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .translationTask(configuration) { session in
            do {
                let response = try await session.translate(inputText)
                outputText = response.targetText
            } catch {
                outputText = "翻译失败：\(error.localizedDescription)"
            }
        }
    }
}
```

**批量翻译**（比如翻译一个句子数组，效率更高，一次请求批处理，不用自己写循环等待）：

```swift
.translationTask(configuration) { session in
    let requests = sentences.map { TranslationSession.Request(sourceText: $0) }
    do {
        let responses = try await session.translations(from: requests)
        translatedSentences = responses.map { $0.targetText }
    } catch {
        print("批量翻译失败: \(error)")
    }
}
```

**预下载语言包**（避免用户首次翻译时卡住等下载）：

```swift
func prepareTranslation(source: Locale.Language, target: Locale.Language) async {
    let config = TranslationSession.Configuration(source: source, target: target)
    // 在某个持有 .translationTask(config) 的视图出现时，系统会自动检查并按需下载
    // 也可以引导用户去 系统设置 > 通用 > 语言与地区 > 翻译语言 手动预下载
}
```

---

## 3. 图片翻译接入（拍照 / 相册图片 → 识别文字 → 翻译 → 叠加显示）

这个场景苹果不提供"一步到位"的 API，需要自己组合两步：**Vision 做 OCR 拿到文字+坐标** → **Translation 翻译文字** → **自己把译文画回原图位置**。

### 第一步：OCR 识别文字和位置

```swift
import Vision
import UIKit

struct RecognizedTextBlock {
    let text: String
    let boundingBox: CGRect // Vision 坐标系（左下角原点，0~1 归一化）
}

func recognizeText(in image: UIImage) async throws -> [RecognizedTextBlock] {
    guard let cgImage = image.cgImage else { return [] }

    return try await withCheckedThrowingContinuation { continuation in
        let request = VNRecognizeTextRequest { request, error in
            if let error = error {
                continuation.resume(throwing: error)
                return
            }
            let observations = request.results as? [VNRecognizedTextObservation] ?? []
            let blocks = observations.compactMap { obs -> RecognizedTextBlock? in
                guard let candidate = obs.topCandidates(1).first else { return nil }
                return RecognizedTextBlock(text: candidate.string, boundingBox: obs.boundingBox)
            }
            continuation.resume(returning: blocks)
        }

        request.recognitionLevel = .accurate
        request.automaticallyDetectsLanguage = true // 自动识别原文语种，日语漫画/韩漫都能识别
        // 如果知道原文语种，也可以显式指定，识别更准：
        // request.recognitionLanguages = ["ja"]

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            continuation.resume(throwing: error)
        }
    }
}
```

### 第二步：把识别出的文字批量丢给 Translation

```swift
@State private var configuration: TranslationSession.Configuration?
@State private var blocks: [RecognizedTextBlock] = []
@State private var translatedBlocks: [(block: RecognizedTextBlock, translated: String)] = []

func translateImage(_ image: UIImage) async {
    blocks = (try? await recognizeText(in: image)) ?? []
    configuration = TranslationSession.Configuration(
        source: sourceLang.language,
        target: targetLang.language
    )
}

// 挂在视图上
.translationTask(configuration) { session in
    let requests = blocks.map { TranslationSession.Request(sourceText: $0.text) }
    guard let responses = try? await session.translations(from: requests) else { return }
    translatedBlocks = zip(blocks, responses.map { $0.targetText }).map { ($0.0, $0.1) }
}
```

### 第三步：把译文叠加画回原图对应位置

Vision 的坐标是归一化、左下角原点，需要转换成 UIKit/SwiftUI 的左上角原点坐标系：

```swift
struct ImageOverlayView: View {
    let image: UIImage
    let items: [(block: RecognizedTextBlock, translated: String)]

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack(alignment: .topLeading) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size.width, height: size.height)

                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    let box = item.block.boundingBox
                    // Vision: 左下角原点、归一化 → 转成 SwiftUI 左上角原点、实际像素
                    let x = box.origin.x * size.width
                    let y = (1 - box.origin.y - box.height) * size.height
                    let w = box.width * size.width
                    let h = box.height * size.height

                    Text(item.translated)
                        .font(.system(size: h * 0.7))
                        .foregroundColor(.black)
                        .background(Color.white.opacity(0.85))
                        .frame(width: w, height: h)
                        .position(x: x + w / 2, y: y + h / 2)
                }
            }
        }
    }
}
```

> 你截图里那种漫画对话气泡的沉浸式翻译，效果就是这一整套流程的产物：OCR 拿框 → 批量翻译 → 按框位置回贴文字。气泡形状复杂的话，建议直接用一个半透明背景块覆盖原文区域，不用真的抠图重绘气泡。

### 拍照场景：接入相机拿实时画面帧

如果要做"举起相机实时翻译"（不是拍照后处理），思路是定时对相机预览帧做 OCR，逻辑复用上面的 `recognizeText`，只是图像来源换成 `AVCaptureVideoDataOutput` 的帧，为了性能建议限流（比如每 0.5~1 秒处理一帧，而不是每帧都识别）。

---

## 4. 对话翻译接入（语音互译）

拆成三步：**语音转文字（Speech）→ 文字翻译（Translation）→ 文字转语音朗读出来（AVSpeechSynthesizer，可选）**。

### 第一步：请求权限

```swift
func requestSpeechAuthorization() async -> Bool {
    let speechStatus = await withCheckedContinuation { cont in
        SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
    }
    let micStatus = await AVAudioApplication.requestRecordPermission()
    return speechStatus == .authorized && micStatus
}
```

### 第二步：语音实时转文字

```swift
import Speech

final class SpeechRecognizerManager: ObservableObject {
    @Published var recognizedText = ""

    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    // locale 传当前"说话人"的语言，比如对方说日语就传 ja-JP
    func startListening(locale: Locale) throws {
        recognizer = SFSpeechRecognizer(locale: locale)
        request = SFSpeechAudioBufferRecognitionRequest()
        request?.shouldReportPartialResults = true

        let node = audioEngine.inputNode
        let format = node.outputFormat(forBus: 0)
        node.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        task = recognizer?.recognitionTask(with: request!) { [weak self] result, error in
            if let result = result {
                self?.recognizedText = result.bestTranscription.formattedString
            }
        }
    }

    func stopListening() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
    }
}
```

### 第三步：识别结果丢给 Translation（复用第 2 节的方式 B）

```swift
@StateObject private var speechManager = SpeechRecognizerManager()
@State private var configuration: TranslationSession.Configuration?
@State private var spokenTranslation = ""

func translateSpoken(_ text: String) {
    configuration = TranslationSession.Configuration(
        source: sourceLang.language,
        target: targetLang.language
    )
}

.translationTask(configuration) { session in
    guard !speechManager.recognizedText.isEmpty else { return }
    if let response = try? await session.translate(speechManager.recognizedText) {
        spokenTranslation = response.targetText
    }
}
```

### 第四步（可选）：把译文朗读出来，做成"双人对话互译"体验

```swift
import AVFoundation

func speak(_ text: String, languageCode: String) {
    let utterance = AVSpeechUtterance(string: text)
    utterance.voice = AVSpeechSynthesisVoice(language: languageCode) // 如 "zh-CN" / "ja-JP"
    let synthesizer = AVSpeechSynthesizer()
    synthesizer.speak(utterance)
}

// 收到译文后：
speak(spokenTranslation, languageCode: targetLang.bcp47Code) // 需要你给 LanguageOption 加个 bcp47Code 字段
```

### 对话翻译的完整交互建议

一个典型的双人对话翻译界面：两个语言选择器（我方语言 / 对方语言）+ 一个麦克风按钮（说话时按住，松开触发识别结束 → 翻译 → 朗读），类似截图里"对话"那个 Tab 的形态。核心逻辑就是把上面三步串起来，按按钮切换当前是哪一方在说话，从而决定 `recognizer` 的 `locale` 和 `TranslationSession.Configuration` 的 `source`/`target` 该互换。

---

## 5. 关键注意事项汇总

| 事项 | 说明 |
|---|---|
| 平台限制 | Translation 相关 UI 仅支持 SwiftUI；纯 UIKit 项目需 `UIHostingController` 包一层 |
| 模拟器 | 翻译功能无法在模拟器运行，必须用真机调试 |
| 语言包下载 | 某语言对首次翻译前系统会下载语言包，需要联网，建议提前用 `LanguageAvailability` 检查状态并给用户下载中的过渡 UI |
| 国行可用性 | Translation / Vision / Speech 均为系统基础框架，不依赖 Apple Intelligence，理论上国行、美版设备都可用；上线前建议在国行真机上实测语言包下载是否顺畅 |
| 合规 | 翻译类 App 在中国大陆上架，可能涉及网信办对"在线翻译/信息服务"类应用的备案要求，这块与苹果 API 无关，建议单独核实清楚 |
| 翻译质量 | Apple 官方翻译引擎在长句、专业术语、语境判断上和 DeepL / Google 翻译仍有差距，作为"系统级免费选项"使用，别指望顶尖专业翻译质量 |
| 语音识别语种 | `SFSpeechRecognizer` 支持的语言和 `Translation` 支持的语言不完全是同一份列表，接入前建议交叉核对你要支持的语言组合是否两边都覆盖 |
