# 语音 corpus 与质量报告

> 状态：current。主题是只读质量评估和报告产物。

## 快速定位

| 任务/符号 | 文件路径 | 关键入口 |
| --- | --- | --- |
| 归一化、编辑距离、WER/CER | [`AITRANS/Services/SpeechQualityEvaluator.swift`](../../../AITRANS/Services/SpeechQualityEvaluator.swift) | `normalize`、`editDistance`、`evaluate`、`aggregate` |
| corpus 读取、音频 identity、报告写入 | [`AITRANS/Services/SpeechQualityProbeService.swift`](../../../AITRANS/Services/SpeechQualityProbeService.swift) | `run`、`validate`、`persist` |
| manifest/case/report schema | [`AITRANS/Models/SpeechQualityModels.swift`](../../../AITRANS/Models/SpeechQualityModels.swift) | `SpeechQualityCorpusManifest`、`SpeechQualityCaseReport`、`SpeechQualityProbeReport` |
| 语料入口 | [`test/speech_corpus/`](../../../test/speech_corpus/) | 当前可用 manifest/音频边界 |
| 云端评估脚本 | [`scripts/validate-speech-corpus.py`](../../../scripts/validate-speech-corpus.py) | corpus 静态校验 |

## 质量边界

```text
manifest + audio identity
  -> Apple Speech final transcript
  -> normalize / tokenizer capability check
  -> case metrics -> aggregate -> JSON/TXT report
```

参考文本只能在 final transcript 已产生后参与 evaluator；报告要保留 runtime identity、音频字节数/SHA 和失败类别，缺失 manifest 时明确 `manifestMissing` 而不是空的“通过”。

## 相关测试与验证路由

- [`scripts/test-speech-quality-contract.py`](../../../scripts/test-speech-quality-contract.py)。
- [`scripts/test-speech-quality-evaluator.swift`](../../../scripts/test-speech-quality-evaluator.swift)：纯 Swift evaluator contract；按当前规则不在本机主动编译。
- [`scripts/validate-speech-corpus.py`](../../../scripts/validate-speech-corpus.py)：有真实 corpus 时运行；无 corpus 只验证缺失状态。
- `.github/workflows/ci-results.yml` 的 Speech scope：由 CI 按 changed-file/profile 选择。

## 何时更新本索引

修改 tokenizer、指标定义、manifest schema、identity receipt、失败分类或报告文件时更新；产品识别 lifecycle 变化转到 [`语音运行、授权与取消`](index-speech-runtime.md)。
