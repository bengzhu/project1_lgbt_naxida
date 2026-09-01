# 音频与语音质量

> 状态：current。按“产品音频运行”和“离线质量报告”分开；质量语料不能反向进入生产识别或翻译。

## 边界

本模块负责 Apple Speech 授权/录音/文件识别、run-id 与取消隔离、音频翻译接线，以及语音 corpus validator、CER/WER 计算和云端报告。文本/图片翻译模型由翻译模块拥有。

## 快速定位

| 任务/符号 | 文件 | 入口 |
| --- | --- | --- |
| 音频 UI | [`AITRANS/Views/AudioTranslationView.swift`](../../../AITRANS/Views/AudioTranslationView.swift) | `AudioTranslationView`、`LiveSpeechPanel`、`AudioFilePanel` |
| 语音运行状态/回调隔离 | [`AITRANS/Services/TranslationSessionStore.swift`](../../../AITRANS/Services/TranslationSessionStore.swift) | `beginProLiveSpeechCapture`、`endProLiveSpeechCapture`、`recognizeAudioFileAndTranslate`、`cancelAudioRecognition` |
| 语音质量探针 | [`AITRANS/Services/SpeechQualityProbeService.swift`](../../../AITRANS/Services/SpeechQualityProbeService.swift) | `run(...)`、`cancel()` |
| 质量算法 | [`AITRANS/Services/SpeechQualityEvaluator.swift`](../../../AITRANS/Services/SpeechQualityEvaluator.swift) | `evaluate(...)`、`aggregate(...)`、`editDistance(...)` |
| 质量模型 | [`AITRANS/Models/SpeechQualityModels.swift`](../../../AITRANS/Models/SpeechQualityModels.swift) | `SpeechQualityCorpusManifest`、`SpeechQualityProbeReport` |
| 产品领域模型 | [`AITRANS/Models/TranscriptModels.swift`](../../../AITRANS/Models/TranscriptModels.swift) | `SpeechRecognitionCapability`、`SpeechRecognitionRunSummary` |

## 相关索引

- [`语音运行、授权与取消`](index-speech-runtime.md)
- [`语音 corpus 与质量报告`](index-speech-quality.md)
- [`Store 状态 ownership`](../index-app/index-app-state.md)
- [`验证/CI profile`](../index-validation/index-validation-ci.md)

## 高风险边界

- Speech 回调必须携带当前 run identity；取消/重试后的旧回调不能覆盖新 transcript 或翻译状态。
- 参考 transcript 只在 Apple Speech 返回最终文本后用于评估，不得参与识别请求、候选选择、纠错或产品翻译。
- 中/日文没有稳定 whitespace tokenizer 时报告 CER，不把字符编辑率标记为 WER。
- 缺少真实语音语料时只能报告 `manifestMissing`/未执行，不能伪造质量改善。

## 何时更新本索引

新增 Speech locale、run 状态、授权/取消入口、质量指标、corpus schema 或报告字段时更新；仅改音频 UI 文案转到应用 UI 索引。
