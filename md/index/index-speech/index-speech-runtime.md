# 语音运行、授权与取消

> 状态：current。主题是 App 内 Apple Speech 的生命周期和翻译接线。

## 快速定位

| 任务/符号 | 文件路径 | 说明 |
| --- | --- | --- |
| live speech 开始/结束 | [`AITRANS/Services/TranslationSessionStore.swift`](../../../AITRANS/Services/TranslationSessionStore.swift) | `beginProLiveSpeechCapture`、`endProLiveSpeechCapture` |
| 文件识别并翻译 | 同上 | `recognizeAudioFileAndTranslate`、`startAudioFileTranslation` |
| run 状态更新 | 同上 | `beginSpeechRecognitionRun`、`updateSpeechRecognitionRun`、`finishSpeechRecognitionRun`、`failSpeechRecognitionRun` |
| 取消/失效 | 同上 | `cancelAudioRecognition`、`invalidateSpeechRecognitionRun` |
| 音频 UI | [`AITRANS/Views/AudioTranslationView.swift`](../../../AITRANS/Views/AudioTranslationView.swift) | `AudioTranslationView`、`LiveSpeechPanel`、`AudioFilePanel` |
| 运行摘要 | [`AITRANS/Models/TranscriptModels.swift`](../../../AITRANS/Models/TranscriptModels.swift) | `SpeechRecognitionRunSummary` |

## 数据流

```text
microphone / audio URL
  -> authorization + SFSpeechRecognizer
  -> current run ID guarded callbacks
  -> final transcript
  -> GemmaLocalService translation
  -> Store transcript/audio state
  -> AudioTranslationView
```

## 权威边界

- Store 拥有 `isCapturingProSpeech`、recognition state、run summary、live transcript 和错误消息；View 不拥有识别事实。
- 新 run 先失效旧 run，再接受回调；取消必须清理当前 request/task，但不能清除不相关历史会话。
- Speech 质量 probe 是诊断 task，与产品 live/file recognition 的 run state 分开。

## 相关测试

- [`test-speech-recognition-contract.py`](../../../scripts/test-speech-recognition-contract.py)：授权、run-id、回调隔离。
- [`test-speech-quality-contract.py`](../../../scripts/test-speech-quality-contract.py)：质量 probe 接线。
- [`test-v203-image-cancel-retry-contract.py`](../../../scripts/test-v203-image-cancel-retry-contract.py) 等图片合同仅在变更跨越 Store 取消基础设施时才联动，不作为 Speech 专项替代。

## 何时更新本索引

修改 SFSpeech request、授权、run generation、取消、音频文件 sandbox 或 Store→translation handoff 时更新。
