# AITRANS 测试规范

本文只定义当前可复用的测试选择、探针边界和验收要求，不记录版本历史、CI run、某次通过结果或临时指标。此类内容统一写入 [`md/log/`](../log/)。

## 1. 基本原则

- 先根据 `git diff --name-only <base>...HEAD` 确定变更范围，再选择 `baseline + direct + optional`。
- 所有变更至少运行 `git diff --check`；只增加与修改代码直接相关的合同或运行证据。
- 没有失败、共享依赖、发布风险或用户明确要求，不运行全部历史 `scripts/test-v*.py`。
- App 源码、工程、资源或构建依赖变化，需要当前 SHA 的基础 iOS 编译证据；文档、fixture 或纯脚本变化通常不需要 Xcode。
- UI 截图、真实 GGUF、漫画探针、Speech 语料、Koharu 工件和目标设备验证默认是可选证据，只有验收目标或诊断需要时开启。
- 不得伪造结果，不得拿旧 artifact 验收新 SHA；未运行的项目必须说明原因。
- 静态合同只能证明结构和接线，不能证明真机、模型、OCR、翻译或 Speech 质量。

## 2. Task-scoped 选择

| 变更范围 | Baseline | Direct | 默认不跑 |
| --- | --- | --- | --- |
| `AGENTS.md`、`README.md`、`md/` | diff、Markdown 链接和路径 | 必要的 JSON/YAML/代码块 smoke | Xcode、App、探针 |
| SwiftUI、Store、App 入口 | diff、云端 iOS simulator build | 对应状态/UI/accessibility 合同 | 全量截图、无关 OCR/Speech |
| Vision OCR、Manga OCR、detector、layout | diff、云端 iOS simulator build | 修改符号对应的 OCR/geometry/reading-order 合同 | 翻译、Speech、全部历史 Koharu 合同 |
| 翻译、prompt、GGUF、llama runtime | diff、云端 iOS simulator build | translation/context/QA/runtime 合同 | OCR、Speech；真实模型仅按需 |
| Speech 源码或质量算法 | diff、云端 iOS simulator build | Speech run-id/取消合同、质量 evaluator、corpus validator | 无语料的 WER/CER、截图 |
| `scripts/`、`benchmarks/`、schema、fixture | diff、语法/解析 | 变更脚本及其直接输入输出 | Xcode，除非改变 App 接线 |
| workflow、Xcode target、bundle 资源 | diff、workflow/工程解析、云端 iOS build | 被影响领域的路由或资源 smoke | 无关探针和截图 |

直接依赖是被修改代码显式调用、读取，或共享同一公共协议/状态边界的测试。不能只因文件名版本相近就扩大范围。

## 3. 本地轻量检查

按任务选用，不要求每轮全部执行：

```sh
git diff --check
plutil -lint AITRANS/Resources/Info.plist AITRANS.xcodeproj/project.pbxproj
python3 -m json.tool test/1.ground_truth.json
python3 -B scripts/test-speech-recognition-contract.py
python3 -B scripts/test-speech-quality-contract.py
python3 -B scripts/validate-speech-corpus.py --root test/speech_corpus
```

对 `output/` 做解析前先确认文件来自本轮运行：

```sh
python3 -m json.tool output/probe_report.json
python3 -m json.tool output/clean_text_diagnostic.json
```

文档本地链接检查：

```sh
python3 - <<'PY'
from pathlib import Path
import re

root = Path.cwd()
errors = []
for doc in [root / "AGENTS.md", root / "README.md", *sorted((root / "md").rglob("*.md"))]:
    text = doc.read_text(encoding="utf-8")
    for target in re.findall(r"]\(([^)#]+)(?:#[^)]+)?\)", text):
        if "://" in target or target.startswith(("mailto:", "#")):
            continue
        if not (doc.parent / target).resolve().exists():
            errors.append(f"{doc.relative_to(root)} -> {target}")
if errors:
    raise SystemExit("broken markdown links:\n" + "\n".join(errors))
print("markdown links: ok")
PY
```

## 4. Xcode 构建

默认由 GitHub Actions 为 App 相关变更提供基础编译证据。人工明确要求本机构建或需要紧急定位时使用完整 Xcode：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project AITRANS.xcodeproj \
  -scheme AITRANS \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath .derivedData \
  CODE_SIGNING_ALLOWED=NO build
```

发布、签名、framework、bundle resource 或真机专属问题再增加 device/archive 验证；普通功能修改不默认本地跑第二套构建。

## 5. 云端验证

- 候选核心 SHA 使用 task-scoped `full`：基础静态检查、直接合同，以及 App 相关变更的 iOS build。
- PR/merge `fast` 只做路由和轻量检查，并复用已核对的候选 full receipt；它不是新的编译证据。
- 候选实现变化后，旧 SHA 的 receipt 和 artifact 失效。
- `probe_mode` 与 `ui_evidence_mode` 默认关闭；需要漫画输出、真实模型或视觉证据时单独触发。
- 失败后只重跑失败项和修复影响范围；扩大范围时写清共享依赖或新增风险。

最小未加密结果包应包含：

- `ci-artifact-manifest.json`：branch、commit SHA、run/attempt、profile、changed-files 和各证据路径。
- `junit.xml`、`xcodebuild.log`、`ci-failure-summary.md`。
- `xcodeBuildRequired=true` 时包含 `.xcresult` 或等价可核查的 Xcode 结果包。
- 运行漫画/Speech/模型探针时，包含对应报告、日志和必要图像。

Agent C 必须先核对 artifact 身份与候选 HEAD，再看测试结论。`xcodeBuildRequired=false` 只能证明静态/路由检查，不能写成 App 编译通过。

## 6. 语音识别质量探针

语音质量探针位于开发入口，读取 `test/speech_corpus/manifest.json`。语料格式和生成要求见 [`test/speech_corpus/README.md`](../../test/speech_corpus/README.md)。

流程：

1. validator 校验 manifest、音频路径、字节数和 SHA256。
2. 按每项 `localeIdentifier` 使用 `SFSpeechURLRecognitionRequest`，并要求设备侧识别能力。
3. Apple Speech 返回最终文本后，评估器才读取参考 transcript。
4. 生成 `Application Support/AITRANS/Output/speech_quality_report.json` 和 `.txt`。

报告包含 corpus/设备/系统身份、识别文本、延迟、分段、置信度、失败分类和汇总指标。空格分词有意义的语言可报告词级 WER 与字符级 CER；中文、日文只报告 CER，不把字符编辑率标成 WER。

硬边界：

- 参考 transcript 不得进入 Speech 请求、候选选择、纠错或生产翻译。
- 没有 manifest、真实音频、权限或目标设备时，只能报告未执行/阻塞，不能声称质量通过或提升。
- `test-speech-recognition-contract.py`、质量合同和 corpus validator 只验证状态机、算法与语料身份，不能替代真实 Apple Speech 运行。

## 7. 漫画覆盖翻译探针

漫画探针固定读取 bundle 内 `test/1.png`，由 `MangaOverlayProbeService` 执行；它不污染普通图片会话、历史或 OCR-only 工作台。

```text
test/1.png
  -> 内容区裁切
  -> OCR / 漫画区域与方向候选
  -> 文字块融合和阅读顺序
  -> 逐块翻译与质量判定
  -> 失败也保留并绘制
  -> JSON / TXT / PNG 写入 App 沙盒 Output
```

核心要求：

- 每轮先清理探针输出目录，避免混入旧文件。
- 失败块保留 `blockPassed=false`、失败原因、原始 OCR 和判定轨迹；覆盖图显示失败文本，不静默跳过。
- `test/1.ground_truth.json` 只用于事后匹配和统计，不得参与生产候选选择。
- 未匹配项保留在明细但不进入可信平均值；对话与装饰标题分开统计。
- clean-text 诊断用于区分 OCR 噪声与模型/翻译链路问题；不能靠放宽规则伪造通过。
- Koharu、TextBox、BubbleMask、SegmentMask 等报告在未晋级前保持 diagnostic/shadow-only，不替换普通图片 OCR、翻译或 renderer。

主要产物：

- `output/probe_report.json`
- `output/clean_text_diagnostic.json`
- `output/1_ocr_probe_text.txt`
- debug boxes、OCR overlay、translated overlay 和必要 contact sheet

模拟器运行后使用以下脚本从 App 沙盒导出到项目根 `output/`：

```sh
scripts/export-probe-output.sh
```

缺少固定图片、GGUF、模拟器或真实 Koharu 四件套时，应明确报告缺失边界，不得用 fixture、proxy 或旧输出冒充本轮证据。

## 8. 大版本体验验证

大版本合入后的首次使用体验是独立闸门，不替代 task-scoped full。场景、证据范围和状态转移见 [`md/flow/experience-iteration.md`](../flow/experience-iteration.md)。普通提交、文档提交和单次合同修复不重复触发。

## 9. 结果记录

- 本文不追加某次测试结果、run ID、commit、PR、当前指标或逐版合同说明。
- 有意义的实现与验证结论写入 [`md/log/update_log.md`](../log/update_log.md)；专项调查可在 `md/log/` 新建分类文件。
- `metrics/` 只追加实际运行得到的机器可读指标；未跑对应探针时不追加质量行。
- 最终回复必须区分：已运行、未运行、静态证据、运行证据和质量证据。
