# CI profile、证据与未运行边界

> 状态：current。主题是如何选择和验收 CI，不记录具体版本流水账。

## 快速定位

| 任务 | 文件路径 | 关键入口 |
| --- | --- | --- |
| profile/changed-file 分流 | [`.github/workflows/ci-results.yml`](../../../.github/workflows/ci-results.yml) | `ci_scope`、`validation_profile`、`expected_commit_sha` |
| Python benchmark job | 同上 | `japanese_benchmark` |
| App result bundle/receipt | 同上 | `ci-results`、manifest/failure summary steps |
| test2 real UI | 同上 | `test2_image_translation_ui` |
| 手动 test2 UI | [`.github/workflows/test2-image-translation-ui.yml`](../../../.github/workflows/test2-image-translation-ui.yml) | workflow dispatch inputs |
| Koharu parity | [`.github/workflows/koharu-mit48-parity.yml`](../../../.github/workflows/koharu-mit48-parity.yml) | artifact/quality smoke |
| 构建/IPA | [`.github/workflows/build.yml`](../../../.github/workflows/build.yml) | `build`/`package` |
| 大版本体验闸门 | [`experience-iteration.md`](../../flow/experience-iteration.md)、[`experience_state.md`](../../../experience_state.md) | post-merge 首次使用、操作日志、latest 产物 |

## 当前验证规则

```text
core code push -> task-scoped full + exact commit SHA
PR            -> fast（不能代替 full）
merge         -> 读取第二父 full receipt，再 fast follow-up 或回退 full
docs-only     -> 父 receipt 成功时可传播；否则不能掩盖代码未验证
```

- `expected_commit_sha` 必须与 checkout 的真实 HEAD 相等。
- 结果包至少看 `junit.xml`、`xcodebuild.log`、`ci-artifact-manifest.json`、`ci-failure-summary.md`；涉及 Xcode/探针时再看 `.xcresult`、`output/` 和关键 PNG/JSON/TXT。
- `ui_evidence_mode=full`、`probe_mode=ci-fast/full`、Koharu artifact 注入和 test2 workflow 都是显式成本边界；默认 push 不启动探针。
- 本机默认不跑 `xcodebuild`、`swiftc`/Swift evaluator、Core ML、Rust/Cargo、GGUF 或 App runtime；除非人工明确要求。

## 按本次改动选择范围

这里是给 Agent 的 task-scoped 路由，不是对 workflow 的修改。先计算 `git diff --name-only <base>...HEAD`，再生成唯一的 `baseline + direct + optional` 清单：

- 所有变更：`git diff --check`；需要云端路由/版本身份时加 v1.94/v1.97 合同。
- App Swift、Xcode 工程、Info.plist、bundle 资源或构建依赖：基础 simulator `xcodebuild` + 变更所属领域的直接合同。
- OCR/layout、翻译/context/QA、Speech、UI/Store：只跑对应主题合同和一个最近共享边界合同；共享状态/协议变更才向相邻主题扩展。
- `scripts/`、`benchmarks/`、schema/fixture：只跑本次修改脚本、直接依赖和对应 evaluator/schema smoke；没有 App 接线变化就跳过 Xcode。
- `md/`、README、AGENTS、update_log、metrics：做链接/路径/必要格式检查；父 full receipt 成功才允许 metadata fast，缺失或失败则不能掩盖代码验证缺口。
- `test/2.png` OCR/翻译截图、test2 UI、Koharu/GGUF、授权语料和目标设备都是显式 `optional`，不因普通 OCR/翻译代码变更自动开启。
- 大版本用户视角体验验证是独立的 post-merge gate；它使用 `test/experience/latest/`，不读取旧轮次 artifact，也不把静态合同、旧截图或旧 build 当作体验证据。

候选核心代码仍使用 `full`，但 full 只包含上述必要范围；PR/merge fast 只复用 exact-SHA full receipt。失败后只重跑失败项与修复影响范围，不恢复历史全量合同。

## 相关维护文档

- [`AGENTS.md`](../../../AGENTS.md) 的分支、Agent A/B/C、测试选择和结果包规则。
- [`md/test/test.md`](../../test/test.md) 的测试制度与历史合同路由。
- [`md/flow/flow.md`](../../flow/flow.md) 的完整验证流；日常先用本页。

## 何时更新本索引

增加/删除 job、改变 profile 选择、receipt 字段、artifact 保留清单、SHA gate 或本机禁止/允许的验证入口时更新，并同步 `AGENTS.md`。
