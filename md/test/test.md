# AITRANS 测试规范

本文只定义当前可复用的测试选择、探针边界和验收要求，不记录版本历史、CI run、某次通过结果或临时指标。此类内容统一写入 [`md/log/`](../log/)。

## 1. 基本原则

- 先根据 `git diff --name-only <base>...HEAD` 确定变更范围，再选择 `baseline + direct + optional`。
- 每次提交或手动触发 CI 前，都要记录 `baseline`、`direct`、`optional` 和 `skipped + reason`；结果包或交接记录必须能看出实际跑了什么。
- `task-scoped full` 只表示当前任务的完整证据，不表示历史合同全集；版本号相近、文件名相似、`workflow_changed` 或泛化的“UI”标签都不能单独扩大范围。
- 所有变更至少运行 `git diff --check`；只增加与修改代码直接相关的合同或运行证据。
- 没有失败、共享依赖、发布风险或用户明确要求，不运行全部历史 `scripts/test-v*.py`。
- App 源码、工程、资源或构建依赖变化，需要当前 SHA 的基础 iOS 编译证据；文档、fixture 或纯脚本变化通常不需要 Xcode。
- UI 截图、真实 GGUF、漫画探针、Speech 语料、Koharu 工件和目标设备验证默认是可选证据，只有验收目标或诊断需要时开启。
- 不得伪造结果，不得拿旧 artifact 验收新 SHA；未运行的项目必须说明原因。
- 静态合同只能证明结构和接线，不能证明真机、模型、OCR、翻译或 Speech 质量。

## 2. CI profile 与成本边界

测试意图分成三层；后续 Codex 必须先选层，再配置 CI，不得用一个聚合 job 代替范围判断：

| 验证层 | 默认内容 | 明确不包含 |
| --- | --- | --- |
| `task-scoped`（默认） | `git diff --check`、直接合同、必要的云端 simulator build | 历史合同全量、无关 UI 合同、通用截图、真实 GGUF、探针 |
| `runtime-evidence`（按需） | 一个明确目标的 App/OCR/Speech/model runtime 和对应 artifact | 为取得某张截图而启动无关翻译、通用 UI 或其它 runtime |
| `full-regression`（显式） | 发布、nightly、兼容性调查或用户明确要求的历史矩阵 | 普通候选 push、PR 和单次合同修复的默认路径 |

`validation_profile=full` 在候选开发中仍表示 task-scoped full，不等于 `full-regression`。如果当前 workflow 只能提供聚合入口，应在交接记录标明 route gap 和被动执行的无关步骤，不能把聚合 job 的结果写成当前任务的直接证据。

成本护栏：

- v3.390 OCR-only 只跑 OCR 检测页合同、修改符号直接相关的 OCR/layout/Store 合同，以及 App 变更所需的 simulator build；需要结果图时单独跑 OCR overlay runtime，跳过 LLM 翻译、Speech、Koharu、通用 UI 截图和 v1.88/v1.89。
- v1.88 仅在首页/文本翻译 UI 合同或其共享边界实际变化时运行；v1.89 仅在粘贴/手动输入矩阵或其共享边界实际变化时运行。OCR-only 任务默认跳过两者。
- `ui_evidence_mode=full` 只用于明确要求通用视觉证据，不能作为 test2 或 OCR overlay 的开关。OCR overlay、普通图片翻译和通用 UI 截图是三个独立 runtime 目标。
- workflow 变化只增加 workflow/receipt 路由检查和受影响领域的直接合同；不能因为 `workflow_changed` 自动打开历史 UI 串、v1.88/v1.89、Speech、Koharu 或截图。
- 同一 SHA、同一验证意图已有可核对的 Xcode build 时，不重复构建；若 test2 与聚合 job 被迫重复构建，必须记录为 workflow route gap。
- 历史合同全量只能由显式 `full-regression`、nightly/release 或失败调查触发，并写明原因。

## 3. Task-scoped 选择

| 变更范围 | Baseline | Direct | 默认不跑 |
| --- | --- | --- | --- |
| `AGENTS.md`、`README.md`、`md/` | diff、Markdown 链接和路径 | 必要的 JSON/YAML/代码块 smoke | Xcode、App、探针 |
| SwiftUI、Store、App 入口 | diff、云端 iOS simulator build | 修改界面/状态边界对应的 UI/accessibility 合同 | 历史 UI 全量、无关截图、OCR/Speech |
| 漫画浏览器 `BrowserModel`/WKWebView/UI | diff、云端 iOS simulator build | 漫画浏览器合同（含 tabs/单 WebView/safe-area/Safari chrome）+ 根导航共享合同 | 其余历史 UI、日语 benchmark、OCR/Speech/Koharu、GGUF、截图与探针 |
| Vision OCR、Manga OCR、detector、layout | diff、云端 iOS simulator build | 修改符号对应的 OCR/geometry/reading-order 合同；OCR 页按需加 overlay runtime | 翻译、Speech、全部历史 Koharu、v1.88/v1.89 |
| 翻译、prompt、GGUF、llama runtime | diff、云端 iOS simulator build | translation/context/QA/runtime 合同 | OCR、Speech；真实模型仅按需 |
| Speech 源码或质量算法 | diff、云端 iOS simulator build | Speech run-id/取消合同、质量 evaluator、corpus validator | 无语料的 WER/CER、截图 |
| `scripts/`、`benchmarks/`、schema、fixture | diff、语法/解析 | 变更脚本及其直接输入输出 | Xcode，除非改变 App 接线 |
| workflow/CI receipt 路由 | diff、workflow/receipt 解析 | 受影响 job 的路由 smoke 和直接合同 | Xcode、历史 UI、无关探针和截图 |
| Xcode target、bundle 资源 | diff、工程解析、云端 iOS build | 被影响领域的路由或资源 smoke | 无关探针和截图 |

直接依赖是被修改代码显式调用、读取，或共享同一公共协议/状态边界的测试。版本合同是历史边界，不是自动依赖；不能只因文件名、版本号或同属 UI 就扩大范围。

## 4. 本地轻量检查

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

## 5. Xcode 构建

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

## 6. 云端验证

- 候选核心 SHA 使用 task-scoped `full`：基础静态检查、直接合同，以及 App 相关变更的 iOS build；这里的 `full` 不运行历史合同全集。
- 纯漫画浏览器 scope 使用 `[browser-only]` 候选提交和 PR 标记，CI 只执行浏览器直接合同与必要 iOS build，并跳过无依赖的日语 OCR/翻译 benchmark job；scope 出现其它业务文件时不得使用该标记。
- PR/merge `fast` 只做路由和轻量检查，并复用已核对的候选 full receipt；它不是新的编译证据。
- 候选实现变化后，旧 SHA 的 receipt 和 artifact 失效。
- `probe_mode` 与 `ui_evidence_mode` 默认关闭；需要漫画输出、真实模型或视觉证据时单独触发，且不得互相充当代理证据。
- 失败后只重跑失败项和修复影响范围；扩大范围时写清共享依赖或新增风险。

最小未加密结果包应包含：

- `ci-artifact-manifest.json`：branch、commit SHA、run/attempt、profile、changed-files 和各证据路径。
- `junit.xml`、`xcodebuild.log`、`ci-failure-summary.md`。
- `xcodeBuildRequired=true` 时包含 `.xcresult` 或等价可核查的 Xcode 结果包。
- 运行漫画/Speech/模型探针时，包含对应报告、日志和必要图像。
- 交接记录补充本轮 `baseline/direct/optional/skipped` 清单；聚合 job 中被动执行的步骤单独标为非直接证据。

Agent C 必须先核对 artifact 身份与候选 HEAD，再看测试结论。`xcodeBuildRequired=false` 只能证明静态/路由检查，不能写成 App 编译通过。

## 7. 语音识别质量探针

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

## 8. 漫画覆盖翻译探针

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

## 9. 大版本体验验证

大版本合入后的首次使用体验是独立闸门，不替代 task-scoped full。场景、证据范围和状态转移见 [`md/flow/experience-iteration.md`](../flow/experience-iteration.md)。普通提交、文档提交和单次合同修复不重复触发。

## 10. 结果记录

- 本文不追加某次测试结果、run ID、commit、PR、当前指标或逐版合同说明。
- 有意义的实现与验证结论写入 [`md/log/update_log.md`](../log/update_log.md)；专项调查可在 `md/log/` 新建分类文件。
- `metrics/` 只追加实际运行得到的机器可读指标；未跑对应探针时不追加质量行。
- 最终回复必须区分：已运行、未运行、静态证据、运行证据和质量证据。
