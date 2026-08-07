## v3.172：日语竖排碎片 line-region 合成

日期：2026-08-08

状态：Agent X 继续参考 Koharu `extract_text_block_regions` 的“检测文字块后按 line-region crop 再 OCR”边界，补齐 Vision 把竖排日语拆成近方形单字时的缺口。对既有 vertical block 内满足短日语文本、脚本密度、列中心接近与垂直 gap 门控的片段按列合成 line crop，最多 24 条；合成候选只替换被覆盖的轴对齐碎片 reread，原始四点 quad 仍保留给 perspective path。工程正式版本为 `MARKETING_VERSION=3.172`。候选 commit `c2e7edd13818c9c46b65d1aa318e4c91c3479c09` 已通过 PR [#236](https://github.com/bengzhu/project1_lgbt_naxida/pull/236) 合入，merge SHA `fab5ddb6d9ebdaa3d4a9dd34bfcdf6c0f676c84c`；`main` 未触碰。

核心变更：

- `recognizeJapaneseVerticalLineCrops` 保留原始 `perspectiveCandidates`，新增 `synthesizeJapaneseVerticalLineCandidates`：只接收最多两个 scalar、日语脚本密度至少 `0.5`、高度至少 `0.012` 且近方形的片段；在每个 vertical block 内按动态列中心容差分组，按 y 排列并检查最大垂直 gap。
- 合成 rect 要求最小高度与 `1.25` 高宽比，文本按列内 y 顺序拼接，confidence 取片段平均，`lineRegionQuad=nil`；与原候选统一去重并受 24 条轴对齐 line 上限，仍复用 v3.171 的灰度化／有界放大、v3.169 opposite-orientation fallback 与既有坐标映射。
- 新增 `scripts/test-v3172-image-japanese-vertical-fragment-line-contract.py` 并接入显式 CI 路由。该迁移不加载 Manga OCR/PaddleOCR 权重、不伪造 detector quad，不改变普通语言、整页 OCR、翻译、renderer/export、Store、探针、Koharu active gate、metrics 或 `output`。

边界：候选、PR、merge 均为 `probe_mode=skip`；真实 `test/koharu_artifacts/` 四件套、Speech corpus 与真实竖排图片质量 corpus 仍缺失，active readiness 为 `manifestMissing / stopUntilArtifactsProvided`。没有新的 OCR／翻译／Koharu 指标，不更新 `metrics/version_history.csv` 或仓库 `output/`，不得据此声称日语 OCR、翻译、识别或 Koharu 质量提升。

云端证据：

- 候选 exact-SHA full [31204989011](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31204989011)：`validationProfile=full`、`validationReason=candidate_development_push`，commit `c2e7edd13818c9c46b65d1aa318e4c91c3479c09`，Xcode build、静态、UI、Speech、home、paste 均成功，JUnit `10/10` 且 0 failures；Koharu active artifact verdict `manifestMissing`，nextAction `stopUntilArtifactsProvided`。
- PR #236 fast [31205608084](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31205608084)：`validationProfile=fast`，`validationReason=pull_request_followup_no_synchronize`，`reusedFullValidationSha=c2e7edd13818c9c46b65d1aa318e4c91c3479c09`、state `success`；Xcode/UI/Speech 跳过，不是新的编译证据。
- merge fast [31205688629](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31205688629)：`validationProfile=fast`、`validationReason=merge_reuses_successful_candidate_full_validation`，merge SHA `fab5ddb6d9ebdaa3d4a9dd34bfcdf6c0f676c84c` 复用候选 full，`receiptPropagationAllowed=true`；Xcode/UI/Speech 跳过，不是新的编译证据。
- 文档提交后的 metadata follow-up [31205881850](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31205881850)：`validationProfile=fast`、`validationReason=smalldata_metadata_followup_reuses_parent_full_validation`，`smalldataIncrementalMetadataOnly=true`，复用 merge SHA `fab5ddb6d9ebdaa3d4a9dd34bfcdf6c0f676c84c / success`，`receiptPropagationAllowed=true`，JUnit `10/10`；Xcode、UI、Speech 与漫画探针跳过，不作为新的编译证据。

## v3.171：日语竖排 line crop 统一 Koharu 风格预处理

日期：2026-08-08

状态：Agent X 继续参考 `reference/koharu-main/koharu-ml/src/manga_ocr/mod.rs` 的 `preprocess_single_image` 与 `extract_text_block_regions` 边界，把 v3.170 的模型无关 crop 预处理从 block reread 统一扩展到普通图片日语竖排 line reread：轴对齐 line 与四点透视 line 都先灰度化，再在最多 4M 像素内优先 2× 放大；轴对齐主／反方向 pass 传递真实 `cropScale` 回映射，透视 path 按放大后像素计入每页 16M 预算。工程正式版本为 `MARKETING_VERSION=3.171`。候选 commit `9968f3083f9b19e9401dd9b48d9e35a480c99e9b` 已通过 PR [#235](https://github.com/bengzhu/project1_lgbt_naxida/pull/235) 合入，merge SHA `df0145f9a2cb5dc5ea4ffdd515042f84cb8de108`；`main` 未触碰。

核心变更：

- `recognizeJapaneseVerticalLineCrops` 移除裸 `resizedImage(..., scale: 2)`，改用共享 `prepareJapaneseCropForVision(crop.image)`；主方向与 v3.169 opposite-orientation fallback 共用灰度 crop 与实际 `preparedCrop.scale`。
- `recognizeJapanesePerspectiveLineCrop` 同样经过共享预处理，并以 `preparedPixels` 代替未放大的 warp 像素计入现有每页 16M 上限；保留单条 4M 上限、透视失败回退和 request-level box／line geometry 边界。
- 新增 `scripts/test-v3171-image-japanese-line-crop-preprocess-contract.py`；v3.160、v3.162、v3.169 历史合同改为接受旧裸 2× 或新的共享 helper，避免后续安全预处理升级破坏历史回归。该迁移仍只作用于普通图片日语 line reread，不加载 Manga OCR/PaddleOCR 权重，不伪造 Tensor normalization，不改变整页 OCR、非日语、翻译、renderer/export、Store、探针、Koharu active gate、metrics 或 `output`。

边界：候选、PR、merge 均为 `probe_mode=skip`；真实 `test/koharu_artifacts/` 四件套、Speech corpus 与真实竖排图片质量 corpus 仍缺失，active readiness 为 `manifestMissing / stopUntilArtifactsProvided`。没有新的 OCR／翻译／Koharu 指标，不更新 `metrics/version_history.csv` 或仓库 `output/`，不得据此声称日语 OCR、翻译、识别或 Koharu 质量提升。

云端证据：

- 候选 exact-SHA full [31203452238](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31203452238)：`validationProfile=full`、`validationReason=candidate_development_push`，commit `9968f3083f9b19e9401dd9b48d9e35a480c99e9b`，Xcode build、静态、UI、Speech、home、paste 均成功，JUnit `10/10` 且 0 failures；Koharu active artifact verdict `manifestMissing`，nextAction `stopUntilArtifactsProvided`。
- PR #235 fast [31204110506](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31204110506)：`validationProfile=fast`，`validationReason=pull_request_followup_no_synchronize`，`reusedFullValidationSha=9968f3083f9b19e9401dd9b48d9e35a480c99e9b`、state `success`；Xcode/UI/Speech 跳过，不是新的编译证据。
- merge fast [31204194868](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31204194868)：`validationProfile=fast`、`validationReason=merge_reuses_successful_candidate_full_validation`，merge SHA `df0145f9a2cb5dc5ea4ffdd515042f84cb8de108` 复用候选 full，`receiptPropagationAllowed=true`；Xcode/UI/Speech 跳过，不是新的编译证据。
- 文档提交后的 metadata follow-up [31204401848](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31204401848)：`validationProfile=fast`、`validationReason=smalldata_metadata_followup_reuses_parent_full_validation`，`smalldataIncrementalMetadataOnly=true`，复用 merge SHA `df0145f9a2cb5dc5ea4ffdd515042f84cb8de108 / success`，`receiptPropagationAllowed=true`，JUnit `10/10`；Xcode、UI、Speech 与漫画探针跳过，不作为新的编译证据。

## v3.170：日语竖排 crop Koharu 风格预处理

日期：2026-08-08

状态：Agent X 继续参考 `reference/koharu-main/koharu-ml/src/manga_ocr/mod.rs` 的 `preprocess_single_image`，把模型无关的 crop 预处理边界迁入普通图片日语竖排文字块 reread：crop 先灰度化，再在最多 4M 像素内优先 2× 放大；Vision 自己负责模型 Tensor normalization，实际放大比例由 `cropScale` 传入既有旋转框映射。Core Image 或 resize 失败安全回退原 crop，避免影响整张图片 OCR。工程正式版本为 `MARKETING_VERSION=3.170`。候选 commit `0b2f011398457e410b366d1c10d80a902eecd173` 已通过 PR [#234](https://github.com/bengzhu/project1_lgbt_naxida/pull/234) 合入，merge SHA `536b21f83670220ea5364b70badfe375a0df355c`；`main` 未触碰。

核心变更：

- `recognizeJapaneseVerticalCrops` 在每个竖排文字块 crop 上调用 `prepareJapaneseCropForVision`：`CIColorControls` saturation=0 灰度化，按 `maximumPixels=4_000_000` 与 `preferredScale=2` 计算安全比例，再复用 `resizedImage`。
- 主方向与 v3.169 opposite-orientation fallback 共享同一预处理 crop 和实际 `cropScale`；`mapRotatedCropObservation`、lineRegionRect／Quad 和既有去重边界不变。
- 该迁移只覆盖 Koharu Manga OCR 的模型无关输入边界，不加载 `manga-ocr` 权重，不伪造 Tensor normalization；普通语言、整页 OCR、line／perspective reread、翻译、renderer/export、Store、探针、metrics、`output` 均不变。新增 `scripts/test-v3170-image-japanese-crop-preprocess-contract.py` 并接入显式 CI 路由。

边界：候选、PR、merge 均为 `probe_mode=skip`；真实 `test/koharu_artifacts/` 四件套、Speech corpus 与真实竖排图片质量 corpus 仍缺失，active readiness 为 `manifestMissing / stopUntilArtifactsProvided`。没有新的 OCR／翻译／Koharu 指标，不更新 `metrics/version_history.csv` 或仓库 `output/`，不得据此声称日语 OCR、翻译、识别或 Koharu 质量提升。

云端证据：

- 候选 exact-SHA full [31201978062](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31201978062)：`validationProfile=full`、`validationReason=candidate_development_push`，commit `0b2f011398457e410b366d1c10d80a902eecd173`，Xcode build、静态、UI、Speech、home、paste 均成功，JUnit `10/10` 且 0 failures；Koharu active artifact readiness 为 `manifestMissing / stopUntilArtifactsProvided`。
- PR #234 fast [31202618966](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31202618966)：`validationProfile=fast`，`reusedFullValidationSha=0b2f011398457e410b366d1c10d80a902eecd173`、state `success`，`validationReason=pull_request_followup_no_synchronize`，Xcode/UI/Speech 跳过，不是新的编译证据。
- merge fast [31202690968](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31202690968)：`validationProfile=fast`、`validationReason=merge_reuses_successful_candidate_full_validation`，merge SHA `536b21f83670220ea5364b70badfe375a0df355c` 复用候选 full，`receiptPropagationAllowed=true`，Xcode/UI/Speech 跳过，不是新的编译证据。
- 文档提交后的 metadata follow-up [31202878230](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31202878230)：`validationProfile=fast`、`validationReason=smalldata_metadata_followup_reuses_parent_full_validation`，`smalldataIncrementalMetadataOnly=true`，复用 merge SHA `536b21f83670220ea5364b70badfe375a0df355c / success` 的 full receipt，`receiptPropagationAllowed=true`，JUnit `10/10`；Xcode、UI、Speech 与漫画探针跳过，不作为新的编译证据。

## v3.169：日语竖排 crop 反方向复读

日期：2026-08-08

状态：Agent X 继续参考 `reference/koharu-main` 的 TextBox→crop 边界，补齐 Vision 日语竖排局部 crop 的方向容错：文字块与 line crop 先按已有 90°／270° 方向复读，只有结果为空、日语脚本密度低或最佳置信度偏弱时，才在有限预算内改用反方向复读。文字块页级最多 8 次、line 页级最多 12 次；所有 crop pass 共用同一 helper，保持日语后处理、rotation metadata、坐标回映射、cropScale 和既有去重边界。工程正式版本为 `MARKETING_VERSION=3.169`。候选 commit `bbe47bd89e4413580482b07e52799867c844ec64` 已通过 PR [#233](https://github.com/bengzhu/project1_lgbt_naxida/pull/233) 合入，merge SHA `a2ad829bf519a2f5cec02d82cc6d7b40168c2d62`；`main` 未触碰。

核心变更：

- `recognizeJapaneseVerticalCrops` 对弱／空文字块 crop 受 8 次页级预算保护地尝试 `oppositeJapaneseOrientation`；主方向和反方向都经 `recognizeJapaneseCropPass` 完成旋转、Vision 识别、Koharu 风格后处理与原图坐标映射。
- `recognizeJapaneseVerticalLineCrops` 对弱／空 line crop 受 12 次页级预算保护地复读 opposite orientation，保留 `minimumTextHeight=0.002` 与 line crop 的 `cropScale`；文字块路径保持 `0.004` 最低文字高度。既有 perspective／整页方向、翻译、renderer/export 与非日语路径不变。
- 新增 `scripts/test-v3169-image-japanese-crop-orientation-fallback-contract.py`，并让 v3.158、v3.160、v3.168 历史合同接受共享 helper 的等价实现；不新增 OCR 模型、Store、持久化、探针输入、Koharu active gate、metrics 或 `output`。

边界：候选、PR、merge 均为 `probe_mode=skip`；真实 `test/koharu_artifacts/` 四件套、Speech corpus 与真实竖排图片质量 corpus 仍缺失，active readiness 为 `manifestMissing / stopUntilArtifactsProvided`。没有新的 OCR／翻译／Koharu 指标，不更新 `metrics/version_history.csv` 或仓库 `output/`，不得据此声称日语 OCR、翻译、识别或 Koharu 质量提升。

云端证据：

- 候选 exact-SHA full [31200276655](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31200276655)：`validationProfile=full`、`validationReason=candidate_development_push`，commit `bbe47bd89e4413580482b07e52799867c844ec64`，Xcode build、静态、UI、Speech、home、paste 均成功，JUnit `10/10` 且 0 failures；Koharu active artifact readiness 为 `manifestMissing / stopUntilArtifactsProvided`。
- PR #233 fast [31200973375](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31200973375)：`validationProfile=fast`，`reusedFullValidationSha=bbe47bd89e4413580482b07e52799867c844ec64`、state `success`，`validationReason=pull_request_followup_no_synchronize`，Xcode/UI/Speech 跳过，不是新的编译证据。
- merge fast [31201060977](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31201060977)：`validationProfile=fast`、`validationReason=merge_reuses_successful_candidate_full_validation`，merge SHA `a2ad829bf519a2f5cec02d82cc6d7b40168c2d62` 复用候选 full，`receiptPropagationAllowed=true`，Xcode/UI/Speech 跳过，不是新的编译证据。
- 文档提交后的 metadata follow-up [31201378270](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31201378270)：`validationProfile=fast`、`validationReason=smalldata_metadata_followup_reuses_parent_full_validation`，`smalldataIncrementalMetadataOnly=true`，复用 merge SHA `a2ad829bf519a2f5cec02d82cc6d7b40168c2d62 / success` 的 full receipt，`receiptPropagationAllowed=true`，JUnit `10/10`；Xcode、UI、Speech 与漫画探针跳过，不作为新的编译证据。

## v3.168：日语 OCR Koharu 风格后处理与候选融合

日期：2026-08-08

状态：Agent X 继续参考 `reference/koharu-main` 的识别后处理边界，将 `manga_ocr.rs` 的 `post_process` 语义迁入普通图片日语 Vision OCR：删除空白、统一 `…` 与点号／中点串、把 ASCII 可打印字符转为全角；在最佳置信度 0.14 窗口内读取最多 5 个 Vision 候选，以日语脚本／标点密度做保守融合。非日语保持既有 top-1，日语整页 90°／270°、文字块 crop、line 与 perspective reread 共用 helper。工程正式版本为 `MARKETING_VERSION=3.168`。候选 commit `9438e3d40ffb133073921fc4f4a0e1de36cc042d` 已通过 PR [#232](https://github.com/bengzhu/project1_lgbt_naxida/pull/232) 合入，merge SHA `033d66b5c62434e5685b1e8d7d1feebdfa90c15e`；`main` 未触碰。

核心变更：

- `VisionOCRService` 新增日语文本后处理与候选选择 helper；空白／省略号／点号串／ASCII 全角化与 Koharu `post_process` 边界对齐，但不声称已加载 Manga OCR/PaddleOCR 模型。
- 日语只在置信度窗口内扩大到 top-5 并按脚本／标点证据择优，非日语维持 top-1；不改变 TranslationSessionStore、翻译、renderer/export、漫画探针、Koharu active gate、metrics 或 `output`。
- 新增 `scripts/test-v3168-image-japanese-ocr-postprocess-contract.py`、`test/jap.jpg` fixture 继续只作合同输入，并接入显式 CI 路由；v3.167 及更早合同均回归通过。

边界：候选、PR、merge 均为 `probe_mode=skip`；真实 `test/koharu_artifacts/` 四件套、Speech corpus 与真实竖排图片质量 corpus 仍缺失，active readiness 为 `manifestMissing / stopUntilArtifactsProvided`。没有新的 OCR／翻译／Koharu 指标，不更新 `metrics/version_history.csv` 或仓库 `output/`，不得据此声称日语 OCR、翻译、识别或 Koharu 质量提升。

云端证据：

- 候选 exact-SHA full [31197172635](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31197172635)：`validationProfile=full`、`validationReason=candidate_development_push`，commit `9438e3d40ffb133073921fc4f4a0e1de36cc042d`，Xcode build、静态、UI、Speech、home、paste 均成功，JUnit `10/10` 且 0 failures；Koharu active artifact readiness 为 `manifestMissing / stopUntilArtifactsProvided`。
- PR #232 fast [31197811891](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31197811891)：`validationProfile=fast`，`reusedFullValidationSha=9438e3d40ffb133073921fc4f4a0e1de36cc042d`、state `success`，`validationReason=pull_request_followup_no_synchronize`，Xcode/UI/Speech 跳过，不是新的编译证据。
- merge fast [31197884476](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31197884476)：`validationProfile=fast`、`validationReason=merge_reuses_successful_candidate_full_validation`，merge SHA `033d66b5c62434e5685b1e8d7d1feebdfa90c15e` 复用候选 full，`receiptPropagationAllowed=true`，Xcode/UI/Speech 跳过，不是新的编译证据。
- 文档提交后的 metadata follow-up [31198317740](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31198317740)：`validationProfile=fast`、`validationReason=smalldata_metadata_followup_reuses_parent_full_validation`，`smalldataIncrementalMetadataOnly=true`，复用 merge SHA `033d66b5c62434e5685b1e8d7d1feebdfa90c15e / success` 的 full receipt，`receiptPropagationAllowed=true`，JUnit `10/10`；不作为新的编译证据。

## v3.167：日语／横排 OCR 横向行动态容差

日期：2026-08-08

状态：Agent X 将 `ImageOCRLayoutEngine.orderedHorizontalBands` 的固定 `0.02` 行分组容差替换为 scale-aware 计算：`median(observation.rect.height) * 0.55`，并限制在 `0.012...0.04`。这样同一行在不同图片缩放／字体下仍能聚合，同时避免相邻面板因容差过大被合并；RTL/LTR 排序和后续 OCR、翻译、renderer/export 路径不变。工程正式版本为 `MARKETING_VERSION=3.167`。候选 commit `6c63dd0a5170a0fb230046d7d2129b26fd8dbb4d` 已通过 PR [#231](https://github.com/bengzhu/project1_lgbt_naxida/pull/231) 合入，merge SHA `a0f1e72ea36be0932dae75fe774af1186ed29b1c`；`main` 未触碰。

核心变更：

- `orderedHorizontalBands` 先求当前 observations 的高度中位数，再用 `min(max(median * 0.55, 0.012), 0.04)` 作为同一横排行的 y 轴容差；上下限用于避免小字被拆行或相邻 panel 被吞并。
- 该层只改 `ImageOCRLayoutEngine` 的布局分组，保留既有日语右到左、其他语言左到右排序和后续 OCR／翻译／渲染流程；不新增 OCR 模型、Store、持久化、探针工件读取、metrics 或 `output`。
- 新增 `scripts/test-v3167-image-horizontal-band-dynamic-tolerance-contract.py` 并接入显式 UI/full fail-fast；同时让 v3.164 历史合同接受动态容差 marker。

边界：候选、PR、merge 均为 `probe_mode=skip`；真实 `test/koharu_artifacts/` 四件套、Speech corpus 与真实竖排图片质量 corpus 仍缺失，active readiness 为 `manifestMissing / stopUntilArtifactsProvided`。没有新的 OCR／翻译／Koharu 指标，不更新 `metrics/version_history.csv` 或仓库 `output/`，不得据此声称日语 OCR、翻译、识别或 Koharu 质量提升。

云端证据：

- 候选 exact-SHA full [31195627325](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31195627325)：`validationProfile=full`、`validationReason=candidate_development_push`，commit `6c63dd0a5170a0fb230046d7d2129b26fd8dbb4d`，Xcode build、静态、UI、Speech、home、paste 均成功，JUnit `10/10` 且 0 failures；Koharu active artifact readiness 为 `manifestMissing / stopUntilArtifactsProvided`。
- PR #231 fast [31196179149](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31196179149)：`validationProfile=fast`，`reusedFullValidationSha=6c63dd0a5170a0fb230046d7d2129b26fd8dbb4d`、state `success`，`validationReason=pull_request_followup_no_synchronize`，Xcode/UI/Speech 跳过，不是新的编译证据。
- merge fast [31196269343](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31196269343)：`validationProfile=fast`、`validationReason=merge_reuses_successful_candidate_full_validation`，merge SHA `a0f1e72ea36be0932dae75fe774af1186ed29b1c` 复用候选 full，`receiptPropagationAllowed=true`，Xcode/UI/Speech 跳过，不是新的编译证据。
- 文档提交后的 metadata follow-up [31196544294](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31196544294)：`validationProfile=fast`、`validationReason=smalldata_metadata_followup_reuses_parent_full_validation`，`smalldataIncrementalMetadataOnly=true`，复用 merge SHA `a0f1e72ea36be0932dae75fe774af1186ed29b1c / success` 的 full receipt，`receiptPropagationAllowed=true`，JUnit `10/10`；不作为新的编译证据。

## v3.166：日语竖排 CJK 标点列证据

日期：2026-08-07

状态：Agent X 继续贴近 Koharu 的 TextBox 方向证据边界：`ImageOCRLayoutEngine.cjkCharacterCount` 现在把日语竖排常见 CJK 标点（`U+3000–U+303F`）与半角片假名（`U+FF61–U+FF9F`）计入短 observation 的 CJK 证据，使「、。」等单独 Vision 结果在存在列邻居、没有横排行邻居时可进入既有竖排聚类和 crop／line reread。工程正式版本为 `MARKETING_VERSION=3.166`。候选 commit `8c6dfe278a9644dd0dc37ffa5381a968dc7748c7` 已通过 PR [#230](https://github.com/bengzhu/project1_lgbt_naxida/pull/230) 合入，merge SHA `0acfd7f62c9ecbe048c7630d0358c85dce325edb`；`main` 未触碰。

核心变更：

- `cjkCharacterCount` 新增 `0x3000...0x303F` 与 `0xFF61...0xFF9F`，但方向改变仍受短文本、列邻居、无横排行邻居和原有尺寸比率门控，不会把孤立标点自动当成竖排。
- 该层只改布局方向证据，让现有日语／简体中文竖排 block、方向感知 crop、line crop 与透视 fallback 保留标点列；不新增 OCR 模型、翻译、探针／工件读取，不改变 renderer/export、Store、持久化、metrics 或 `output`。
- 新增 `scripts/test-v3166-image-japanese-punctuation-column-contract.py`，并接入 UI/full fail-fast；v3.165 及更早合同继续回归。

边界：候选、PR、merge 均为 `probe_mode=skip`；真实 `test/koharu_artifacts/` 四件套、Speech corpus 与真实竖排图片质量 corpus 仍缺失，active readiness 为 `manifestMissing / stopUntilArtifactsProvided`。没有新的 OCR／翻译／Koharu 指标，不更新 `metrics/version_history.csv` 或仓库 `output/`，不得据此声称日语 OCR、翻译、识别或 Koharu 质量提升。

云端证据：

- 候选 exact-SHA full [31193812409](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31193812409)：`validationProfile=full`、`validationReason=candidate_development_push`，commit `8c6dfe278a9644dd0dc37ffa5381a968dc7748c7`，Xcode build、静态、UI、Speech、home、paste 均成功，JUnit `10/10` 且 0 failures；Koharu active artifact readiness 为 `manifestMissing / stopUntilArtifactsProvided`。
- PR #230 fast [31194473761](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31194473761)：`validationProfile=fast`，`reusedFullValidationSha=8c6dfe278a9644dd0dc37ffa5381a968dc7748c7`、state `success`，Xcode/UI/Speech 跳过，不是新的编译证据。
- merge fast [31194535297](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31194535297)：`validationProfile=fast`、`validationReason=merge_reuses_successful_candidate_full_validation`，merge SHA `0acfd7f62c9ecbe048c7630d0358c85dce325edb` 复用候选 full，`receiptPropagationAllowed=true`，Xcode/UI/Speech 跳过，不是新的编译证据。
- 文档提交后的 metadata follow-up [31194700807](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31194700807)：`validationProfile=fast`、`validationReason=smalldata_metadata_followup_reuses_parent_full_validation`，`smalldataIncrementalMetadataOnly=true`，复用 merge SHA `0acfd7f62c9ecbe048c7630d0358c85dce325edb` 的成功 full receipt，`receiptPropagationAllowed=true`，JUnit `10/10`；不作为新的编译证据。

## v3.165：日语单字列竖排方向门控

日期：2026-08-07

状态：Agent X 继续把 Koharu `TextBox → crop → OCR` 的方向证据边界迁入普通图片：当允许竖排的 CJK Vision observation 是短单字、接近方形、存在列邻居且没有横排行邻居时，`ImageOCRLayoutEngine.resolveDirection` 将其标为 `cjkGlyphColumnNeighbors`，使既有竖排聚类与局部 crop／line reread 不会因单字拆分而完全丢掉列。工程正式版本为 `MARKETING_VERSION=3.165`。候选 commit `5f24c4b7d2de47a095ee15b19994087ebde4dff7` 已通过 PR [#229](https://github.com/bengzhu/project1_lgbt_naxida/pull/229) 合入，merge SHA `631c4d25acacb6b0497e8c95dab41f9a22e6c266`；`main` 未触碰。

核心变更：

- 新增短 CJK 列邻居门控：`cjkCount > 0`、最多两个字符、`verticalRatio >= 1.05`、`height >= 0.015`、列邻居存在且横排行邻居不存在；宽框横排、孤立高框、横排碎片继续走原有边界。
- 该层只改布局方向判定，让已有日语／简体中文竖排 block 聚类、方向感知 crop、line crop 与透视 fallback 有机会消费单字列；不新增 OCR 模型、翻译、探针／工件读取，不改变 renderer/export、Store、持久化、metrics 或 `output`。
- 新增 `scripts/test-v3165-image-japanese-glyph-column-contract.py`，并接入 UI/full fail-fast；v3.164 及更早合同继续回归。

边界：候选、PR、merge 均为 `probe_mode=skip`；真实 `test/koharu_artifacts/` 四件套、Speech corpus 与真实竖排图片质量 corpus 仍缺失，active readiness 为 `manifestMissing / stopUntilArtifactsProvided`。没有新的 OCR／翻译／Koharu 指标，不更新 `metrics/version_history.csv` 或仓库 `output/`，不得据此声称日语 OCR、翻译、识别或 Koharu 质量提升。

云端证据：

- 候选 exact-SHA full [31192480905](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31192480905)：`validationProfile=full`、`validationReason=candidate_development_push`，commit `5f24c4b7d2de47a095ee15b19994087ebde4dff7`，Xcode build、静态、UI、Speech、home、paste 均成功，JUnit `10/10` 且 0 failures；Koharu active artifact readiness 为 `manifestMissing / stopUntilArtifactsProvided`。
- PR #229 fast [31193220150](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31193220150)：`validationProfile=fast`，`reusedFullValidationSha=5f24c4b7d2de47a095ee15b19994087ebde4dff7`、state `success`，Xcode/UI/Speech 跳过，不是新的编译证据。
- merge fast [31193292477](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31193292477)：`validationProfile=fast`、`validationReason=merge_reuses_successful_candidate_full_validation`，merge SHA `631c4d25acacb6b0497e8c95dab41f9a22e6c266` 复用候选 full，`receiptPropagationAllowed=true`，Xcode/UI/Speech 跳过，不是新的编译证据。
- 文档提交后的 metadata follow-up [31193558071](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31193558071)：`validationProfile=fast`、`validationReason=smalldata_metadata_followup_reuses_parent_full_validation`，`smalldataIncrementalMetadataOnly=true`，复用 merge SHA `631c4d25acacb6b0497e8c95dab41f9a22e6c266` 的成功 full receipt，`receiptPropagationAllowed=true`，JUnit `10/10`；不作为新的编译证据。

## v3.164：日语混合版面横排 RTL reading order

日期：2026-08-07

状态：Agent X 继续把 Koharu 漫画阅读方向迁入普通图片日语混合版面：`ImageOCRLayoutEngine.layout` 新增默认关闭的 `prefersMangaReadingOrder`，仅日语 Vision 主路径与受限 crop layout 开启横排行内右到左排序，并完成候选 full、PR fast、merge fast 云端验收合入 `smalldata_test`。工程正式版本为 `MARKETING_VERSION=3.164`。候选 commit `7e584045f12fefa995866b7479db4cd440d52a03` 已通过 PR [#228](https://github.com/bengzhu/project1_lgbt_naxida/pull/228) 合入，merge SHA `3943843d61f331630f7c6764f5639273aea4bd90`；`main` 未触碰。

核心变更：

- 横排 helper 保留 y 行分组与上到下行序；日语 manga flag 为 true 时只把同一行的 x 主键取负，实现右到左列序；默认 false 的普通语言路径不变。
- Vision OCR 主路径按 `sourceLanguage == .japanese` 开启该 flag，日语垂直 crop layout 同样显式开启；不新增 OCR 模型、翻译、探针／工件读取，不改变 renderer/export、Store、持久化、metrics 或 `output`。
- 新增 `scripts/test-v3164-image-japanese-horizontal-reading-order-contract.py`，并接入 UI/full fail-fast；v3.163 及更早合同继续回归。

边界：候选、PR、merge 均为 `probe_mode=skip`；真实 `test/koharu_artifacts/` 四件套、Speech corpus 与真实竖排图片质量 corpus 仍缺失，active readiness 为 `manifestMissing / stopUntilArtifactsProvided`。没有新的 OCR／翻译／Koharu 指标，不更新 `metrics/version_history.csv` 或仓库 `output/`，不得据此声称日语 OCR、翻译、识别或 Koharu 质量提升。

云端证据：

- 候选 exact-SHA full [31190984866](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31190984866)：`validationProfile=full`、`validationReason=candidate_development_push`，commit `7e584045f12fefa995866b7479db4cd440d52a03`，Xcode build、静态、UI、Speech、home、paste 均成功，JUnit `10/10` 且 0 failures；Koharu active artifact readiness 为 `manifestMissing / stopUntilArtifactsProvided`。
- PR #228 fast [31191645282](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31191645282)：`validationProfile=fast`，`reusedFullValidationSha=7e584045f12fefa995866b7479db4cd440d52a03`、state `success`，Xcode/UI/Speech 跳过，不是新的编译证据。
- merge fast [31191716497](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31191716497)：`validationProfile=fast`、`validationReason=merge_reuses_successful_candidate_full_validation`，merge SHA `3943843d61f331630f7c6764f5639273aea4bd90` 复用候选 full，`receiptPropagationAllowed=true`，Xcode/UI/Speech 跳过，不是新的编译证据。
- 文档提交后的 metadata follow-up [31192018448](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31192018448)：`validationProfile=fast`、`validationReason=smalldata_metadata_followup_reuses_parent_full_validation`，`smalldataIncrementalMetadataOnly=true`，复用 merge SHA `3943843d61f331630f7c6764f5639273aea4bd90` 的成功 full receipt，`receiptPropagationAllowed=true`，JUnit `10/10`；不作为新的编译证据。

## v3.163：日语竖排 Recursive XY-Cut reading order

日期：2026-08-07

状态：Agent X 继续对照 `reference/koharu-main/koharu-app/src/pipeline/engines/support.rs` 的 `sort_manga_reading_order`，把 Recursive XY-Cut 读取顺序迁入普通图片日语竖排布局，并完成候选 full、PR fast、merge fast 云端验收合入 `smalldata_test`。工程正式版本为 `MARKETING_VERSION=3.163`。候选 commit `c37808634df8d87cfb9f24c22acadc472f71d3c0` 已通过 PR [#227](https://github.com/bengzhu/project1_lgbt_naxida/pull/227) 合入，merge SHA `e93f3844c359214c0cdfe09cd609fb11c51b924d`；`main` 未触碰。

核心变更：

- `ImageOCRLayoutEngine` 的日语竖排 reading order 用文字块中位宽／高中位数估计动态空白阈值，递归选择最大的横向／纵向 whitespace cut；横向切分右侧组先读，纵向切分顶部组先读，符合 Koharu 漫画 panel 方向。
- 无合法切分时保留稳定右到左、上到下排序；改动只作用于布局顺序，不新增 OCR／翻译／探针／工件读取，不改变 renderer/export、Store、持久化、metrics 或 `output`。
- 新增 `scripts/test-v3163-image-japanese-reading-order-contract.py`，并接入 UI/full fail-fast；v3.162 及更早合同继续回归。

边界：候选、PR、merge 均为 `probe_mode=skip`；真实 `test/koharu_artifacts/` 四件套、Speech corpus 与真实竖排图片质量 corpus 仍缺失，active readiness 为 `manifestMissing / stopUntilArtifactsProvided`。没有新的 OCR／翻译／Koharu 指标，不更新 `metrics/version_history.csv` 或仓库 `output/`，不得据此声称日语 OCR、翻译、识别或 Koharu 质量提升。

云端证据：

- 候选 exact-SHA full [31189049773](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31189049773)：`validationProfile=full`、`validationReason=candidate_development_push`，commit `c37808634df8d87cfb9f24c22acadc472f71d3c0`，Xcode build、静态、UI、Speech、home、paste 均成功，JUnit `10/10` 且 0 failures；Koharu active artifact readiness 为 `manifestMissing / stopUntilArtifactsProvided`。
- PR #227 fast [31189799793](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31189799793)：`validationProfile=fast`，`reusedFullValidationSha=c37808634df8d87cfb9f24c22acadc472f71d3c0`、state `success`，Xcode/UI/Speech 跳过，不是新的编译证据。
- merge fast [31189875449](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31189875449)：`validationProfile=fast`、`validationReason=merge_reuses_successful_candidate_full_validation`，merge SHA `e93f3844c359214c0cdfe09cd609fb11c51b924d` 复用候选 full，`receiptPropagationAllowed=true`，Xcode/UI/Speech 跳过，不是新的编译证据。
- 文档 metadata follow-up [31190328506](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31190328506)：`validationProfile=fast`、`validationReason=smalldata_metadata_followup_reuses_parent_full_validation`，仅 v3.163 文档增量，复用 merge SHA `e93f3844c359214c0cdfe09cd609fb11c51b924d / success`，`receiptPropagationAllowed=true`、`smalldataIncrementalMetadataOnly=true`，Xcode/UI/Speech 跳过，不是新的编译证据。

## v3.162：日语竖排 line-region perspective OCR

日期：2026-08-07

状态：Agent X 继续按 Koharu `extract_text_block_regions` 的四点 line-region 透视校正边界改进普通图片日语竖排 OCR，并完成候选 full、PR fast、merge fast 云端验收合入 `smalldata_test`。工程正式版本为 `MARKETING_VERSION=3.162`。候选 commit `8a8e653f953c233f5b0d28249bb9b324ef0baab3` 已通过 PR [#226](https://github.com/bengzhu/project1_lgbt_naxida/pull/226) 合入，merge SHA `b1c272b9fea90e07967e21db082538be50c8b516`；`main` 未触碰。

核心变更：

- 读取 Vision `VNRecognizedText.boundingBox(for:)` 返回的 `VNRectangleObservation` 四角，和 request-level observation box 分开保存；只有有限、凸、有效边长的四点 geometry 才作为 line-region crop hint。
- 日语竖排最多处理 24 条 line crop；每条 `CIPerspectiveCorrection` 输出限制 4M 像素、总计限制 16M 像素，随后 2× Vision 复读；透视校正、resize、rotate 或局部 OCR 失败时保留并回到既有轴对齐 crop。
- 四角 geometry 在整页 90°／270° 与局部 crop 的坐标回映射中同步传播，但 request-level box 继续负责布局／去重；这是 Koharu line polygon warp 的 Vision 过渡层，不是已加载 Manga OCR、PaddleOCR-VL 或 MIT 48px 模型。
- 新增 `scripts/test-v3162-image-japanese-line-perspective-ocr-contract.py`，并让 v3.161 历史合同接受 `recognizedTextGeometry` 等价 helper；不读取探针报告、ground truth 或 Koharu active artifacts，不改变翻译、renderer/export、Store、持久化、metrics 或 `output`。

边界：候选、PR、merge 均为 `probe_mode=skip`；真实 `test/koharu_artifacts/` 四件套、Speech corpus 与真实竖排图片质量 corpus 仍缺失，active readiness 为 `manifestMissing / stopUntilArtifactsProvided`。没有新的 OCR／翻译／Koharu 指标，不更新 `metrics/version_history.csv` 或仓库 `output/`，不得据此声称日语 OCR、翻译、识别或 Koharu 质量提升。

云端证据：

- 候选 exact-SHA full [31186264941](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31186264941)：`validationProfile=full`、`validationReason=candidate_development_push`，commit `8a8e653f953c233f5b0d28249bb9b324ef0baab3`，Xcode build、静态、UI、Speech、home、paste 均成功，JUnit `10/10` 且 0 failures；Koharu active artifact readiness 为 `manifestMissing / stopUntilArtifactsProvided`。
- PR #226 fast [31186901253](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31186901253)：`validationProfile=fast`，`reusedFullValidationSha=8a8e653f953c233f5b0d28249bb9b324ef0baab3`、state `success`，Xcode/UI/Speech 跳过，不是新的编译证据。
- merge fast [31186979637](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31186979637)：`validationProfile=fast`、`validationReason=merge_reuses_successful_candidate_full_validation`，merge SHA `b1c272b9fea90e07967e21db082538be50c8b516` 复用候选 full，Xcode/UI/Speech 跳过，不是新的编译证据。
- 文档 metadata follow-up [31187213167](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31187213167)：`validationProfile=fast`、`validationReason=smalldata_metadata_followup_reuses_parent_full_validation`，复用 merge SHA `b1c272b9fea90e07967e21db082538be50c8b516 / success`，`receiptPropagationAllowed=true`、`smalldataIncrementalMetadataOnly=true`，仅上述 6 个文档文件变化，Xcode/UI/Speech 跳过，不是新的编译证据。

## v3.161：日语竖排 line-region geometry hint

日期：2026-08-07

状态：Agent X 继续按 Koharu 的 line-region 几何边界改进普通图片日语竖排 OCR，并完成候选 full、PR fast、merge fast 云端验收合入 `smalldata_test`。工程正式版本为 `MARKETING_VERSION=3.161`。候选 commit `9164066706faed78494384d79ec1544d46084c20` 已通过 PR [#225](https://github.com/bengzhu/project1_lgbt_naxida/pull/225) 合入，merge SHA `1eb026c2ce3df861b6efcc7ae9d61a5d08fd86ea`；`main` 未触碰。

核心变更：

- 读取 Vision `VNRecognizedText.boundingBox(for:)` 的整段字符范围 bounds，作为更紧的日语 line-region crop hint；request-level box 继续作为布局／去重的稳定几何。
- 该 hint 在整页 90°／270° 方向复查与局部 2× crop 的坐标回映射中同步传播；字符范围调用失败、几何重叠／面积比例不合格时回退原框，不影响整张图片 OCR。
- 这是在缺少 Koharu 真实 `line_polygons` 时对 line-region 几何的渐进迁移，不是已加载 Manga OCR、PaddleOCR-VL 或 MIT 48px 模型；不读取探针报告、ground truth 或 Koharu active artifacts，不改变翻译、renderer/export、Store、持久化、metrics 或 `output`。

边界：候选、PR、merge 均为 `probe_mode=skip`；真实 `test/koharu_artifacts/` 四件套、Speech corpus 与真实竖排图片质量 corpus 仍缺失，active readiness 为 `manifestMissing / stopUntilArtifactsProvided`。没有新的 OCR／翻译／Koharu 指标，不更新 `metrics/version_history.csv` 或仓库 `output/`，不得据此声称日语 OCR、翻译、识别或 Koharu 质量提升。

云端证据：

- 候选 exact-SHA full [31184241208](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31184241208)：`validationProfile=full`、`validationReason=candidate_development_push`，commit `9164066706faed78494384d79ec1544d46084c20`，Xcode build、静态、UI、Speech、home、paste 均成功，JUnit `10/10` 且 0 failures；Koharu active artifact readiness 为 `manifestMissing / stopUntilArtifactsProvided`。
- PR #225 fast [31184939184](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31184939184)：`validationProfile=fast`，`reusedFullValidationSha=9164066706faed78494384d79ec1544d46084c20`、state `success`，Xcode/UI/Speech 跳过，不是新的编译证据。
- merge fast [31185021159](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31185021159)：`validationProfile=fast`、`validationReason=merge_reuses_successful_candidate_full_validation`，merge SHA `1eb026c2ce3df861b6efcc7ae9d61a5d08fd86ea` 复用候选 full，Xcode/UI/Speech 跳过，不是新的编译证据。
- 文档 metadata follow-up [31185267006](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31185267006)：`validationProfile=fast`、`validationReason=smalldata_metadata_followup_reuses_parent_full_validation`，复用 merge SHA `1eb026c2ce3df861b6efcc7ae9d61a5d08fd86ea / success`，`receiptPropagationAllowed=true`、`smalldataIncrementalMetadataOnly=true`，仅上述 6 个文档文件变化，Xcode/UI/Speech 跳过，不是新的编译证据。

## v3.160：日语竖排 line-region OCR 过渡层

日期：2026-08-07

状态：Agent X 继续按 Koharu `extract_text_block_regions` 的检测／布局与识别分层改进普通图片日语竖排 OCR，并已完成候选 full、PR fast、merge fast 云端验收合入 `smalldata_test`。工程正式版本为 `MARKETING_VERSION=3.160`。候选 commit `68c1c1b8eb1390b808204c3c16b7b1dbc72a28b9` 已通过 PR [#224](https://github.com/bengzhu/project1_lgbt_naxida/pull/224) 合入，merge SHA `19b018101a4937474e2f3b030a1e24dc58807704`；`main` 未触碰。

核心变更：

- 在既有日语竖排 block 中按 observation 与 block 的重叠和纵向比例筛选最多 24 个 line-region proxy，按方向感知规则扩边，使用 2× crop 复读 Vision OCR（`minimumTextHeight=0.002`、关闭自动语言检测）。
- 局部 OCR 结果按缩放比例映射回原图，再与既有观察去重后进入现有布局；crop、resize、rotate 或局部 OCR 失败均安全跳过，不使整张图片 OCR 失败。
- 当前 Vision observations 没有 Koharu 的真实 line polygons，因此这是保守的 line-region 过渡层，不是 Manga OCR/PaddleOCR 模型替换；不读取探针报告、ground truth 或 Koharu active artifacts，不改变翻译、renderer/export、Store、持久化、metrics 或 `output`。

边界：候选、PR、merge 均为 `probe_mode=skip`；真实 `test/koharu_artifacts/` 四件套、Speech corpus 与真实竖排图片质量 corpus 仍缺失，active readiness 为 `manifestMissing / stopUntilArtifactsProvided`。没有新的 OCR／翻译／Koharu 指标，不更新 `metrics/version_history.csv` 或仓库 `output/`，不得据此声称日语 OCR、翻译、识别或 Koharu 质量提升。

云端证据：

- 候选 exact-SHA full [31182335743](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31182335743)：`validationProfile=full`、`validationReason=candidate_development_push`，commit `68c1c1b8eb1390b808204c3c16b7b1dbc72a28b9`，Xcode build、静态、UI、Speech、home、paste 均成功，JUnit `10/10` 且 0 failures；Koharu active artifact readiness 为 `manifestMissing / stopUntilArtifactsProvided`。
- PR #224 fast [31183007517](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31183007517)：`validationProfile=fast`，`reusedFullValidationSha=68c1c1b8eb1390b808204c3c16b7b1dbc72a28b9`、state `success`，Xcode/UI/Speech 跳过，不是新的编译证据。
- merge fast [31183084173](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31183084173)：`validationProfile=fast`、`validationReason=merge_reuses_successful_candidate_full_validation`，merge SHA `19b018101a4937474e2f3b030a1e24dc58807704` 复用候选 full，Xcode/UI/Speech 跳过，不是新的编译证据。
- 文档 metadata follow-up [31183425478](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31183425478)：`validationProfile=fast`、`validationReason=smalldata_metadata_followup_reuses_parent_full_validation`，复用 merge SHA `19b018101a4937474e2f3b030a1e24dc58807704 / success`，`receiptPropagationAllowed=true`、`smalldataIncrementalMetadataOnly=true`，仅上述 6 个文档文件变化，Xcode/UI/Speech 跳过，不是新的编译证据。

## v3.159：日语图片 OCR 进度上下文

日期：2026-08-07

状态：Agent X 继续收敛普通图片日语 OCR 的可理解性：当源语言为日语且进入 `.recognizing` 时，`TranslationSessionStore` 通过私有 helper 将既有 `imageTranslationMessage` 设置为“正在用 Vision 本机 OCR 识别日语文字，复查竖排方向与文字块位置”；其他语言保持通用“识别文字和位置”文案。图片状态行与结果空态继续读取同一 Store message，因此 VoiceOver 能说明当前日语竖排／文字块复查边界；不新增 OCR、翻译、持久化、renderer/export 或探针流程。

核心变更：

- 新增 `scripts/test-v3159-image-japanese-ocr-status-context-contract.py`，锁定日语／通用两条文案、`.recognizing` 写入顺序、View 消费路径以及不调用 OCR／Store 持久化的边界。
- `MARKETING_VERSION` 更新为 `3.159`，CI scope 正则与 UI/full fail-fast 路由接入 v3.159；v3.158 及更早合同继续回归。

边界：该版本只改善图片 OCR 进行中的状态与无障碍上下文，不读取 ground truth、Koharu artifact 或探针 report，不创建模型工件，不更新 `metrics/version_history.csv` 或仓库 `output/`。真实 `test/koharu_artifacts/` 四件套、Speech corpus 与真实竖排图片质量 corpus 仍缺失，不得据此声称 OCR、翻译、识别或 Koharu 质量提升。

云端证据：

- 候选 exact-SHA full [31180141884](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31180141884)：`validationProfile=full`、`validationReason=candidate_development_push`，候选 SHA `f30fbab503ff9c694af0d4f2c123113b1802648d`，Xcode/static/UI/Speech/home/paste 全部成功，JUnit `10/10`；active Koharu artifact readiness 为 `manifestMissing / stopUntilArtifactsProvided`。
- PR #223 fast [31180615748](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31180615748)：`validationProfile=fast`，`reusedFullValidationSha=f30fbab503ff9c694af0d4f2c123113b1802648d`、state `success`，Xcode/UI/Speech 跳过，不是新的编译证据。
- merge fast [31180708039](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31180708039)：`validationProfile=fast`、`validationReason=merge_reuses_successful_candidate_full_validation`，merge SHA `9c68b5c9f7e5e5d341a3cfaec1f764964b71b9f0` 复用候选 full，Xcode/UI/Speech 跳过，不是新的编译证据。
- 文档 metadata follow-up [31181089617](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31181089617)：`validationProfile=fast`、`validationReason=smalldata_metadata_followup_reuses_parent_full_validation`，复用 merge SHA `9c68b5c9f7e5e5d341a3cfaec1f764964b71b9f0 / success`，`receiptPropagationAllowed=true`、`smalldataIncrementalMetadataOnly=true`，仅上述 6 个文档文件变化；Xcode/UI/Speech 跳过，不是新的编译证据。

## v3.158：日语竖排文字块裁剪复读 OCR

日期：2026-08-07

状态：Agent X 继续按 Koharu 的 `TextBoxes → crop_text_block_bbox → OCR` 分层，在 v3.157 双向方向复查后，从既有竖排布局候选中最多选择 16 个文字块做 Vision 裁剪复读；候选 full、PR fast、merge fast 已完成云端验收并合入 `smalldata_test`。工程正式版本为 `MARKETING_VERSION=3.158`。候选 commit `ee21c07d5175b38b41161822043b7ce1bbeea3ff` 已通过 PR [#222](https://github.com/bengzhu/project1_lgbt_naxida/pull/222) 合入，merge SHA `c940815a43e300685667d8b01888e53af910ec9c`；`main` 未触碰。

核心变更：

- 日语源语言保留整页 Vision OCR 与 90°／270° 方向复查，先用既有 `ImageOCRLayoutEngine` 得到竖排 block，再对最多 16 个候选按 Koharu 风格扩展裁剪边界，使用候选方向重新 OCR。
- 裁剪结果的 bounding box 通过局部裁剪坐标、旋转坐标映射回原图，与原始／整页方向观察一起去重后才进入最终布局；局部裁剪、旋转或 OCR 失败均安全跳过，不使整张图片 OCR 失败。
- 新增 `scripts/test-v3158-image-japanese-crop-ocr-contract.py` 并扩展 CI 路由。该步只迁移 crop-before-OCR 的检测／裁剪／识别边界，不调用 Manga OCR、PaddleOCR-VL 或第二套模型，不读取探针报告、ground truth、Koharu active artifacts，不改变翻译、renderer/export、Store、持久化、metrics 或 `output`。

边界：仓库仍缺少真实 `test/koharu_artifacts/` 四件套、Speech corpus 与可用于质量评估的真实竖排图片 corpus；候选、PR、merge 均为 `probe_mode=skip`，没有新的 OCR／翻译／Koharu 指标，不更新 `metrics/version_history.csv` 或仓库 `output/`。Vision 裁剪复读是模型工件到位前的过渡层，不得据此声称日语 OCR、翻译、识别或 Koharu 质量提升。

云端证据：

- 候选 exact-SHA full [31178774530](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31178774530)：`validationProfile=full`、`validationReason=candidate_development_push`，commit `ee21c07d5175b38b41161822043b7ce1bbeea3ff`，Xcode build、静态、UI、Speech、home、paste 均成功，JUnit `10/10` 且 0 failures/errors；Koharu active artifact validator 为 `manifestMissing / stopUntilArtifactsProvided`。
- PR #222 fast [31179342519](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31179342519)：`validationProfile=fast`，复用候选 full `ee21c07d5175b38b41161822043b7ce1bbeea3ff / success`，Xcode/UI/Speech skipped，JUnit `10/10`；不是新的编译证据。
- merge fast [31179390133](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31179390133)：`validationProfile=fast`、`validationReason=merge_reuses_successful_candidate_full_validation`，merge SHA `c940815a43e300685667d8b01888e53af910ec9c` 复用候选 full `ee21c07d5175b38b41161822043b7ce1bbeea3ff / success`，Xcode/UI/Speech skipped，JUnit `10/10`；不是新的编译证据。
- 文档 metadata follow-up [31179585052](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31179585052)：`validationProfile=fast`、`validationReason=smalldata_metadata_followup_reuses_parent_full_validation`，复用 merge SHA `c940815a43e300685667d8b01888e53af910ec9c / success`，`receiptPropagationAllowed=true`，`smalldataIncrementalMetadataOnly=true`，仅上述 6 个文档文件变化，Xcode/UI/Speech skipped，`probe_mode=skip`；不是新的编译证据。
- receipt follow-up [31179650804](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31179650804)：`validationProfile=fast`、`validationReason=smalldata_metadata_followup_reuses_parent_full_validation`，复用父文档 SHA `e9680b7bc8af74fc57160bdaa7c241d0be51e12c / success`，`receiptPropagationAllowed=true`，`smalldataIncrementalMetadataOnly=true`，仅 `update_log.md` 变化，Xcode/UI/Speech skipped，`probe_mode=skip`；不是新的编译证据。

## v3.157：日语竖排双向方向 OCR 复查

日期：2026-08-07

状态：Agent X 在 v3.156 的日语方向复查上补齐受限 90°／270° 双向比较：两次 Vision 结果映射回原图后统一去重，再交给既有日语竖排／右到左布局；候选 full、PR fast、merge fast 已完成云端验收并合入 `smalldata_test`。工程正式版本为 `MARKETING_VERSION=3.157`。候选 commit `894c7063e18a6dc40ea047dca015e7cf73af8e65` 已通过 PR [#221](https://github.com/bengzhu/project1_lgbt_naxida/pull/221) 合入，merge SHA `1266de53935525c1014ec0b4cbecb9b7f20b6e86`；`main` 未触碰。

核心变更：

- 日语源语言保留原图 Vision OCR，并在同一受限路径比较 90° 与 270° 两个方向；两次复查都使用 `ja-JP`／`ja`／`en-US`／`en` profile、`minimumTextHeight=0.006` 与关闭自动语言检测。
- 每次旋转结果的 bounding box 映射回原图后，与原始及另一方向观察一起去重，再交给既有 `ImageOCRLayoutEngine`；既有日语／简体中文竖排判断、列邻居证据、垂直列右到左及块内自上而下排序保持不变。
- 新增 `scripts/test-v3157-image-japanese-bidirectional-orientation-ocr-contract.py` 并扩展历史 v3.156 合同与 CI 路由；该步不读取探针报告、ground truth 或 Koharu active artifacts，不调用第二套模型，不改变翻译、renderer/export、Store、持久化、metrics 或 `output`。

边界：本阶段仍只迁移 Koharu 的方向比较与检测／布局／识别分层边界，不是将 Manga OCR、PaddleOCR-VL 或 MIT 48px 模型直接打包进 iOS。仓库仍缺少真实 `test/koharu_artifacts/` 四件套、Speech corpus 与可用于质量评估的真实竖排图片 corpus；候选、PR、merge 均为 `probe_mode=skip`，没有新的 OCR／翻译／Koharu 指标，不更新 `metrics/version_history.csv` 或仓库 `output/`，不得据此声称日语 OCR、翻译、识别或 Koharu 质量提升。

云端证据：

- 候选 exact-SHA full [31177442783](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31177442783)：`validationProfile=full`、`validationReason=candidate_development_push`，commit `894c7063e18a6dc40ea047dca015e7cf73af8e65`，Xcode build、静态、UI、Speech、home、paste 均成功，JUnit `10/10` 且 0 failures/errors；Koharu active artifact validator 为 `manifestMissing / stopUntilArtifactsProvided`。
- PR #221 fast [31177914749](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31177914749)：`validationProfile=fast`，复用候选 full `894c7063e18a6dc40ea047dca015e7cf73af8e65 / success`，Xcode/UI/Speech skipped，JUnit `10/10`；不是新的编译证据。
- merge fast [31177971252](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31177971252)：`validationProfile=fast`、`validationReason=merge_reuses_successful_candidate_full_validation`，merge SHA `1266de53935525c1014ec0b4cbecb9b7f20b6e86` 复用候选 full `894c7063e18a6dc40ea047dca015e7cf73af8e65 / success`，Xcode/UI/Speech skipped，JUnit `10/10`；不是新的编译证据。
- 文档 metadata follow-up [31178184628](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31178184628)：`validationProfile=fast`、`validationReason=smalldata_metadata_followup_reuses_parent_full_validation`，复用 merge SHA `1266de53935525c1014ec0b4cbecb9b7f20b6e86 / success`，`receiptPropagationAllowed=true`，`smalldataIncrementalMetadataOnly=true`，仅上述 6 个文档文件变化，Xcode/UI/Speech skipped，`probe_mode=skip`；不是新的编译证据。
- receipt follow-up [31178246288](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31178246288)：`validationProfile=fast`、`validationReason=smalldata_metadata_followup_reuses_parent_full_validation`，复用父文档 SHA `6aeed9ab941653f4f3654e41f3444a9eb7cf801c / success`，`receiptPropagationAllowed=true`，`smalldataIncrementalMetadataOnly=true`，仅 `update_log.md` 变化，Xcode/UI/Speech skipped，`probe_mode=skip`；不是新的编译证据。

## v3.156：日语竖排方向 OCR 第一阶段迁移

日期：2026-08-07

状态：Agent X 已将 Koharu 的“检测／布局与识别分层、方向比较后再进入布局”边界迁入普通图片 Vision OCR 的第一阶段，并完成候选 full、PR fast、merge fast 云端验收；工程正式版本为 `MARKETING_VERSION=3.156`。候选 commit `99a333a8297faf193c8058d7f919626bb17daf80` 已通过 PR [#220](https://github.com/bengzhu/project1_lgbt_naxida/pull/220) 合入，merge SHA `7750c7e62b82cb952ab302b9afd206ecf15068dd`；`main` 未触碰。

核心变更：

- `VisionOCRService` 在保留原图 Vision OCR 的前提下，日语源语言追加一次受限 90° 方向 OCR：使用 `ja-JP`／`ja`／`en-US`／`en` profile、`minimumTextHeight=0.006` 与关闭自动语言检测；旋转结果的 bounding box 映射回原图后，与原始观察去重，再交给既有 `ImageOCRLayoutEngine`。
- 继续复用既有日语／简体中文竖排判断、列邻居证据、垂直列右到左及块内自上而下排序；方向复查只改变普通图片 OCR 的观察候选，不读取探针报告、ground truth 或 Koharu active artifacts，不调用第二套模型，不改变翻译、renderer/export、Store、持久化、metrics 或 `output`。
- 新增 `scripts/test-v3156-image-japanese-orientation-ocr-contract.py` 与真实日语竖排参考图片 `test/jap.jpg`。合同检查方向 pass、框映射／去重／布局边界、历史方向合同、CI 路由及 fixture JPEG 边界；参考目录仅作为开发阅读材料，不成为 CI 运行时依赖。

边界：本阶段迁移的是 Koharu 的方向比较与分层边界，不是将 Manga OCR、PaddleOCR-VL 或 MIT 48px 模型直接打包进 iOS。仓库仍缺少真实 `test/koharu_artifacts/` 四件套、Speech corpus 与可用于质量评估的真实竖排图片 corpus；候选、PR、merge 均为 `probe_mode=skip`，没有新的 OCR／翻译／Koharu 指标，不更新 `metrics/version_history.csv` 或仓库 `output/`，不得据此声称日语 OCR、翻译、识别或 Koharu 质量提升。

云端证据：

- 候选 exact-SHA full [31176163879](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31176163879)：`validationProfile=full`、`validationReason=candidate_development_push`，Xcode build、静态、UI、Speech、home、paste 均成功，JUnit `10/10` 且 0 failures/errors；Koharu active artifact readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`。
- PR #220 fast [31176662793](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31176662793)：`validationProfile=fast`，复用候选 full `99a333a8297faf193c8058d7f919626bb17daf80 / success`，Xcode/UI/Speech skipped，JUnit `10/10`；不是新的编译证据。
- merge fast [31176739499](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31176739499)：`validationProfile=fast`、`validationReason=merge_reuses_successful_candidate_full_validation`，merge SHA `7750c7e62b82cb952ab302b9afd206ecf15068dd` 复用候选 full `99a333a8297faf193c8058d7f919626bb17daf80 / success`，Xcode/UI/Speech skipped，JUnit `10/10`；不是新的编译证据。
- 文档 metadata follow-up [31176953484](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31176953484)：`validationProfile=fast`、`validationReason=smalldata_metadata_followup_reuses_parent_full_validation`，复用 merge SHA `7750c7e62b82cb952ab302b9afd206ecf15068dd / success`，`receiptPropagationAllowed=true`，`smalldataIncrementalMetadataOnly=true`，仅文档 metadata 变化，Xcode/UI/Speech skipped，`probe_mode=skip`；不是新的编译证据。

## v3.155：普通图片空结果就地重试 action

日期：2026-08-07

状态：Agent X 已完成普通图片无可显示 OCR 文字块时的就地重试入口、候选 exact-SHA full、PR fast、merge fast 云端验收并合入 `smalldata_test`；工程正式版本为 `MARKETING_VERSION=3.155`。候选 commit `a6283b1be84ec4e6b227b6d5fbf74961a4fd108f` 已通过 PR [#219](https://github.com/bengzhu/project1_lgbt_naxida/pull/219) 合入，merge SHA `2c26886ee6676c549b88ad48b0447e595c636a40`；`main` 未触碰。

核心变更：

- 当普通图片 `imageTranslationBlocks` 为空、当前图片源文件仍可用、状态允许重试，且没有待重试语言变更时，结果空态新增可见“重试当前图片”按钮；按钮直接复用 `store.retryImageTranslation`，让用户不必离开结果区寻找上方状态入口。
- 结果空态的 VoiceOver 同样提供“重试当前图片” action，并由 `canRetryFromImageStatus` 同时检查 `store.canRetryImageTranslation` 与 `store.imageTranslationRetryLanguageSummary == nil`；重试语言已更新时保留既有上方状态行 action，避免重复入口，锁定／处理中／源图片不可用时不暴露无效 action。
- 按钮 hint 与空态 label/value 说明使用当前图片语言重新识别并翻译；新增 `scripts/test-v3155-image-empty-result-retry-action-contract.py` 并接入 UI/full fail-fast。改动只属于 View，未新增 Store、持久化、Vision OCR、翻译、renderer/export、探针或 metrics/output 管线。

边界：候选、PR、merge 使用 `probe_mode=skip`，没有新的 OCR／翻译／Koharu 指标，也没有更新 `metrics/version_history.csv` 或仓库 `output/`。真实 `test/koharu_artifacts/` 四件套、Speech corpus 与真实竖排图片 corpus 仍缺失，active readiness 为 `manifestMissing / stopUntilArtifactsProvided`；不得据此声称 OCR、翻译、识别或 Koharu 质量提升。PR/merge fast 与后续文档 follow-up 只属于 receipt 复用或 metadata 传播，不是新的编译证据。

云端证据：

- 候选 exact-SHA full [31173412868](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31173412868)：`validationProfile=full`、`validationReason=candidate_development_push`，commit `a6283b1be84ec4e6b227b6d5fbf74961a4fd108f`，Xcode build、静态、UI、Speech、home、paste 均成功，JUnit `10/10` 且 0 failures/errors，`probe_mode=skip`；Koharu active artifact validator 仍为 `manifestMissing / stopUntilArtifactsProvided`。
- PR #219 fast [31173840102](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31173840102)：`validationProfile=fast`，复用候选 full `a6283b1be84ec4e6b227b6d5fbf74961a4fd108f / success`，Xcode/UI/Speech skipped，JUnit `10/10`；不是新的编译证据。
- merge fast [31173897707](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31173897707)：`validationProfile=fast`、`validationReason=merge_reuses_successful_candidate_full_validation`，merge SHA `2c26886ee6676c549b88ad48b0447e595c636a40` 复用候选 full `a6283b1be84ec4e6b227b6d5fbf74961a4fd108f / success`，`receiptPropagationAllowed=true`，Xcode/UI/Speech skipped，JUnit `10/10`；不是新的编译证据。
- 文档 metadata follow-up [31174097256](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31174097256)：`validationProfile=fast`、`validationReason=smalldata_metadata_followup_reuses_parent_full_validation`，复用 merge SHA `2c26886ee6676c549b88ad48b0447e595c636a40 / success`，`receiptPropagationAllowed=true`，`smalldataIncrementalMetadataOnly=true`，仅上述 6 个文档文件变化，Xcode skipped，JUnit `10/10`；不是新的编译证据。
- receipt follow-up [31174159740](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31174159740)：`validationProfile=fast`、`validationReason=smalldata_metadata_followup_reuses_parent_full_validation`，复用父文档 SHA `a00df1a3860c61d9d08ab6df5d0da8f8a33514bc / success`，`receiptPropagationAllowed=true`，`smalldataIncrementalMetadataOnly=true`，仅 `update_log.md` 变化，Xcode skipped，JUnit `10/10`；不是新的编译证据。

## v3.154：普通图片空结果状态文案动态化

日期：2026-08-07

状态：Agent X 已完成普通图片识别结果空态的状态化可见标题／说明优化、候选 exact-SHA full、PR fast、merge fast 云端验收并合入 `smalldata_test`；工程正式版本为 `MARKETING_VERSION=3.154`。候选 commit `11028f3de4886aad18e911dd8dc3f60e6593ba9f` 已通过 PR [#218](https://github.com/bengzhu/project1_lgbt_naxida/pull/218) 合入，merge SHA `b51ab8a880f3a1998a5a4e249e6c7113e0a3c451`；`main` 未触碰。

核心变更：

- 普通图片 `imageTranslationBlocks` 为空时，结果空态的可见标题与说明不再固定为“正在准备识别结果”，而是由 View 私有 `imageResultEmptyStateTitle`／`imageResultEmptyStateDetail` 按 idle、读取／Vision OCR／翻译进行中、translated 与 failed 分流；translated 明确说明没有可显示 OCR 文字块与重新识别边界，处理中保留 Store 的阶段消息，失败保留失败原因。
- 既有 VoiceOver label/value/hint、稳定空态焦点 identity、受 `store.canRerunImageRecognition` 门控的“重新识别” action 与可见按钮保持不变；helper 只改变显示文案，不新增 Store、OCR、翻译、持久化或重跑管线。
- 新增 `scripts/test-v3154-image-empty-result-state-contract.py` 并接入 UI/full fail-fast；同步 v3.133、v3.152、v3.153 历史合同接受动态标题／说明，继续锁定 View-only 与单一 Store 入口。

边界：候选、PR、merge 使用 `probe_mode=skip`，没有新的 OCR／翻译／Koharu 指标，也没有更新 `metrics/version_history.csv` 或仓库 `output/`。真实 `test/koharu_artifacts/` 四件套、Speech corpus 与真实竖排图片 corpus 仍缺失，active readiness 为 `manifestMissing / stopUntilArtifactsProvided`；不得据此声称 OCR、翻译、识别或 Koharu 质量提升。文档 follow-up 只属于 metadata receipt 传播，不是新的编译证据。

云端证据：

- 候选 exact-SHA full [31171837188](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31171837188)：`validationProfile=full`、`validationReason=candidate_development_push`，commit `11028f3de4886aad18e911dd8dc3f60e6593ba9f`，Xcode build、静态、UI、Speech、home、paste 均成功，JUnit `10/10` 且 0 failures/errors，`probe_mode=skip`；Koharu active artifact validator 仍为 `manifestMissing / stopUntilArtifactsProvided`。
- PR #218 fast [31172320096](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31172320096)：`validationProfile=fast`，复用候选 full `11028f3de4886aad18e911dd8dc3f60e6593ba9f / success`，Xcode/UI/Speech skipped，JUnit `10/10`；不是新的编译证据。
- merge fast [31172393014](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31172393014)：`validationProfile=fast`、`validationReason=merge_reuses_successful_candidate_full_validation`，merge SHA `b51ab8a880f3a1998a5a4e249e6c7113e0a3c451` 复用候选 full `11028f3de4886aad18e911dd8dc3f60e6593ba9f / success`，`receiptPropagationAllowed=true`，Xcode/UI/Speech skipped，JUnit `10/10`；不是新的编译证据。
- 文档 metadata follow-up [31172809735](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31172809735)：`validationProfile=fast`、`validationReason=smalldata_metadata_followup_reuses_parent_full_validation`，复用 merge SHA `b51ab8a880f3a1998a5a4e249e6c7113e0a3c451 / success`，`receiptPropagationAllowed=true`，`smalldataIncrementalMetadataOnly=true`，仅 6 个文档文件变化，Xcode skipped，JUnit `10/10`；不是新的编译证据。
- metadata receipt follow-up [31172885422](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31172885422)：`validationProfile=fast`、`validationReason=smalldata_metadata_followup_reuses_parent_full_validation`，复用父文档 SHA `ed571a676555e9af2afa70725a91136f548d0340 / success`，`receiptPropagationAllowed=true`，`smalldataIncrementalMetadataOnly=true`，仅 `update_log.md` 变化，Xcode skipped，JUnit `10/10`；不是新的编译证据。

## v3.153：普通图片空结果 VoiceOver 焦点稳定化

日期：2026-08-07

状态：Agent X 已完成普通图片翻译完成但没有可显示 OCR 文字块时的终态 VoiceOver 焦点修复、候选 exact-SHA full、PR fast、merge fast 云端验收并合入 `smalldata_test`；工程正式版本为 `MARKETING_VERSION=3.153`。候选 commit `6c838ef220470753cb6abf4867babc48a6ea795c` 已通过 PR [#217](https://github.com/bengzhu/project1_lgbt_naxida/pull/217) 合入，merge SHA `a938b8b73803e0570e0ec9bb8e6ec354e3cf85b0`；`main` 未触碰。

核心变更：

- 普通图片在翻译已完成、源图片仍保留且没有可显示 OCR 文字块时，结果空态使用稳定 `imageResultEmptyAccessibilityFocusID`，让可操作的空态成为终态 VoiceOver 焦点，而不是回到泛化状态行。
- `focusImageTranslationTerminalStateIfNeeded()` 保留全部忽略空态优先级；非忽略的 `.translated` 无 blocks 聚焦空态，失败、取消、初始 idle 或其他状态继续回到图片状态行。焦点请求继续受 revision 与 View 私有 generation guard 约束。
- v3.144 的 VoiceOver“重新识别” action 与 v3.152 的可见按钮及其源图片门控保持不变；本次不新增 Store、OCR、翻译或持久化管线。

边界：候选、PR、merge 使用 `probe_mode=skip`，没有新的 OCR／翻译／Koharu 指标，也没有更新 `metrics/version_history.csv` 或仓库 `output/`。真实 `test/koharu_artifacts/` 四件套、Speech corpus 与真实竖排图片 corpus 仍缺失，active readiness 为 `manifestMissing / stopUntilArtifactsProvided`；不得据此声称 OCR、翻译、识别或 Koharu 质量提升。后续云端文档跟进只属于元数据传播，不是新的编译证据。

云端证据：

- 候选 exact-SHA full [31170387940](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31170387940)：`validationProfile=full`、`validationReason=candidate_development_push`，commit `6c838ef220470753cb6abf4867babc48a6ea795c`，Xcode build、静态、UI、Speech、home、paste 均成功，JUnit `10/10` 且 0 failures/errors，`probe_mode=skip`；Koharu active artifact validator 仍为 `manifestMissing / stopUntilArtifactsProvided`。
- PR #217 fast [31170963538](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31170963538)：`validationProfile=fast`，复用候选 full `6c838ef220470753cb6abf4867babc48a6ea795c / success`，Xcode/UI/Speech skipped，JUnit `10/10`；不是新的编译证据。
- merge fast [31171022668](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31171022668)：`validationProfile=fast`、`validationReason=merge_reuses_successful_candidate_full_validation`，merge SHA `a938b8b73803e0570e0ec9bb8e6ec354e3cf85b0` 复用候选 full `6c838ef220470753cb6abf4867babc48a6ea795c / success`，`receiptPropagationAllowed=true`，Xcode/UI/Speech skipped，JUnit `10/10`；不是新的编译证据。
- 文档 metadata follow-up [31171243756](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31171243756)：`validationProfile=fast`、`validationReason=smalldata_metadata_followup_reuses_parent_full_validation`，复用 merge SHA `a938b8b73803e0570e0ec9bb8e6ec354e3cf85b0 / success`，`receiptPropagationAllowed=true`，`smalldataIncrementalMetadataOnly=true`，仅 6 个文档文件变化，Xcode skipped，JUnit `10/10`；不是新的编译证据。

## v3.152：普通图片空结果可见重新识别

日期：2026-08-07

状态：Agent X 已完成普通图片翻译完成但没有可显示 OCR 文字块时的可见重新识别入口、候选 exact-SHA full、PR fast、merge fast 云端验收并合入 `smalldata_test`；工程正式版本为 `MARKETING_VERSION=3.152`。候选 commit `0c08bfda4548b996a2e3bad86d2adde950276378` 已通过 PR [#216](https://github.com/bengzhu/project1_lgbt_naxida/pull/216) 合入，merge SHA `29b42e3d839b5d9f225658fb24e4f88e4ec4d69d`；`main` 未触碰。

核心变更：

- 普通图片翻译已完成但没有可显示 OCR 文字块时，结果空态新增可见“重新识别”按钮；只有 `store.canRerunImageRecognition` 为真（当前图片仍有可用源文件）才显示，避免在源图片已失效时留下无效入口。
- 按钮直接复用 `store.rerunImageRecognition`，由 Store 既有 guard 进入当前图片的 Vision OCR 与翻译重跑；v3.144 的 VoiceOver action、label/value/hint 和源文件门控继续保持，不新增 Store／持久化／OCR／翻译管线。
- 新增 `scripts/test-v3152-image-empty-result-rerun-button-contract.py` 并接入 UI/full fail-fast，历史 v3.144/v3.313 空结果上下文合同继续通过；改动只属于 View、静态合同和 CI 路由。

边界：候选、PR、merge 使用 `probe_mode=skip`，没有新的 OCR／翻译／Koharu 指标，也没有更新 `metrics/version_history.csv` 或仓库 `output/`。真实 `test/koharu_artifacts/` 四件套、Speech corpus 与真实竖排图片 corpus 仍缺失，active readiness 为 `manifestMissing / stopUntilArtifactsProvided`；不得据此声称 OCR、翻译、识别或 Koharu 质量提升。后续云端文档跟进只属于元数据传播，不是新的编译证据。

云端证据：

- 候选 exact-SHA full [31167004721](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31167004721)：`validationProfile=full`、`validationReason=candidate_development_push`，commit `0c08bfda4548b996a2e3bad86d2adde950276378`，Xcode build、静态、UI、Speech、home、paste 均成功，JUnit `10/10` 且 0 failures/errors，`probe_mode=skip`；Koharu active artifact validator 仍报告 `manifestMissing / stopUntilArtifactsProvided`。
- PR #216 fast [31170006883](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31170006883)：`validationProfile=fast`，复用候选 full `0c08bfda4548b996a2e3bad86d2adde950276378 / success`，Xcode/UI/Speech skipped，JUnit `10/10`；不是新的编译证据。
- merge fast [31170055419](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31170055419)：`validationProfile=fast`、`validationReason=merge_reuses_successful_candidate_full_validation`，复用候选 full `0c08bfda4548b996a2e3bad86d2adde950276378 / success`，`receiptPropagationAllowed=true`，Xcode/UI/Speech skipped，JUnit `10/10`；不是新的编译证据。

## v3.151：漫画探针无逐块结果就地重试 action

日期：2026-08-07

状态：Agent X 已完成 Developer Console 漫画探针无逐块结果空态的就地重试入口、候选 exact-SHA full、PR fast、merge fast 云端验收并合入 `smalldata_test`；工程正式版本为 `MARKETING_VERSION=3.151`。候选 commit `8579bdabc8f0dbbeafe19b4804cfedcea9dfbe04` 已通过 PR [#215](https://github.com/bengzhu/project1_lgbt_naxida/pull/215) 合入，merge SHA `79f92aad2a12e682eba609a1f49814025e9920a7`；`main` 未触碰。

核心变更：

- 当漫画探针已有报告但没有逐块文字块时，空态同时提供可见“重新运行漫画覆盖翻译探针”按钮与同名 VoiceOver action；只在 `!store.isRunningMangaOverlayProbe` 时暴露，运行中保留 disabled 边界，不暴露只会被 Store guard 拒绝的无效 action。
- 可见按钮与 VoiceOver action 均复用既有 `store.runMangaOverlayProbe`，hint 明确会重新读取 bundle 内 `test/1.png`、清理 Output 并只更新漫画探针诊断，不改变普通图片 OCR、翻译或覆盖图；不新增 Store／持久化／OCR／翻译管线。
- 新增 `scripts/test-v3151-manga-probe-empty-retry-action-contract.py` 并接入 UI/full fail-fast；同步让 v3.56 历史状态合同接受这条受门控的第二入口，继续锁定 report-only 和单一 Store 入口边界。

边界：候选、PR、merge 使用 `probe_mode=skip`，没有新的 OCR／翻译／Koharu 指标，也没有更新 `metrics/version_history.csv` 或仓库 `output/`。真实 `test/koharu_artifacts/` 四件套、Speech corpus 与真实竖排图片 corpus 仍缺失，active readiness 为 `manifestMissing / stopUntilArtifactsProvided`；不得据此声称 OCR、翻译、识别或 Koharu 质量提升。后续云端文档跟进只属于元数据传播，不是新的编译证据。

云端证据：

- 候选 exact-SHA full [31165387991](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31165387991)：`validationProfile=full`、`validationReason=candidate_development_push`，commit `8579bdabc8f0dbbeafe19b4804cfedcea9dfbe04`，Xcode build、静态、UI、Speech、home、paste 均成功，JUnit `10/10` 且 0 failures/errors，`probe_mode=skip`；manifest 的 Koharu active artifact validator 为 `manifestMissing / stopUntilArtifactsProvided`。
- PR #215 fast [31165964091](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31165964091)：`validationProfile=fast`，复用候选 full `8579bdabc8f0dbbeafe19b4804cfedcea9dfbe04 / success`，Xcode/UI/Speech skipped，JUnit `10/10`；不是新的编译证据。
- merge fast [31166051842](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31166051842)：`validationProfile=fast`、`validationReason=merge_reuses_successful_candidate_full_validation`，复用候选 full `8579bdabc8f0dbbeafe19b4804cfedcea9dfbe04 / success`，`receiptPropagationAllowed=true`，Xcode/UI/Speech skipped，JUnit `10/10`；不是新的编译证据。

## v3.150：普通图片局部放大恢复 Vision OCR action

日期：2026-08-07

状态：Agent X 已完成 v3.150 普通图片局部放大预览恢复 Vision OCR 的可见按钮与 VoiceOver action、候选 exact-SHA full、PR fast、merge fast 云端验收并合入 `smalldata_test`；工程正式版本为 `MARKETING_VERSION=3.150`。候选 commit `04cef3c01b802627366587dc1a3c76eddc534e3f` 已通过 PR [#214](https://github.com/bengzhu/project1_lgbt_naxida/pull/214) 合入，merge SHA `b52dabc245f0d140115074b37c34975ce0b743c9`；`main` 未触碰。

核心变更：

- 普通图片人工修正后的文字块在局部放大预览中新增可见“恢复 Vision OCR”按钮与同名 VoiceOver action，且仅在 `isManuallyCorrected && canEdit` 时提供；未修正或锁定状态不暴露父级 action，保留 `modificationUnavailableHint` 和禁用按钮边界。
- 局部放大预览通过 `ImageTranslationPanel` 注入的 closure 进入既有 `requestVisionOCRRestore` 确认对话框，恢复流程仍由 Store 的现有 Vision OCR 恢复入口完成；不新增 OCR、翻译、Store 或 Koharu 管线。
- 新增 `scripts/test-v3150-image-focus-restore-action-contract.py`，并扩展 UI/full fail-fast 路由。改动只属于 View、静态合同和 CI 路由，不改变 Vision OCR、模型翻译、renderer/export、漫画探针、Koharu active gate、metrics 或 `output`。

边界：候选、PR、merge 使用 `probe_mode=skip`，没有新的 OCR／翻译／Koharu 指标，也没有更新 `metrics/version_history.csv` 或仓库 `output/`。真实 `test/koharu_artifacts/` 四件套、Speech corpus 与真实竖排图片 corpus 仍缺失，readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不得据此声称 OCR、翻译、识别或 Koharu 质量提升。

云端证据：

- 候选 exact-SHA full [31163470178](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31163470178)：`validationProfile=full`、`validationReason=candidate_development_push`，commit `04cef3c01b802627366587dc1a3c76eddc534e3f`，Xcode build success，静态、UI、Speech、home、paste 合同 success，JUnit `10/10` 且 0 failures/errors，`probe_mode=skip`；Koharu active readiness 为 `manifestMissing / stopUntilArtifactsProvided`。
- PR #214 fast [31164127307](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31164127307)：`validationProfile=fast`，复用候选 full `04cef3c01b802627366587dc1a3c76eddc534e3f / success`，Xcode/UI/Speech skipped，JUnit `10/10`；不是新的编译证据。
- merge fast [31164207376](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31164207376)：`validationProfile=fast`，`validationReason=merge_reuses_successful_candidate_full_validation`，复用候选 full `04cef3c01b802627366587dc1a3c76eddc534e3f / success`，`receiptPropagationAllowed=true`，Xcode/UI/Speech skipped，JUnit `10/10`；不是新的编译证据。

## v3.149：普通图片复查完成空态 VoiceOver action 门控

日期：2026-08-07

状态：Agent X 已完成 v3.149 普通图片“本次复查完成”空态的 VoiceOver action 门控优化、候选 exact-SHA full、PR fast、merge fast 云端验收并合入 `smalldata_test`；工程正式版本为 `MARKETING_VERSION=3.149`。候选 commit `b0fc332c565fe501c8e2e939a086b79c142c9853` 已通过 PR [#213](https://github.com/bengzhu/project1_lgbt_naxida/pull/213) 合入，merge SHA `137d8d61a4c6b10d4126b3ae07e9163edbf07878`；`main` 未触碰。

核心变更：

- 普通图片筛选到 `.needsReview` 且所有风险块都已完成时，完成空态通过 View 私有 `reviewCompletionEmptyStateAccessibility` helper 暴露 VoiceOver“重新复查” action，且仅在 `canReviewImageTranslation` 为真时提供；可用时直接复用既有 `restartReviewQueue()`，不会新增 Store 或重跑 OCR。
- 翻译未完成或导出重绘期间保留“本次复查完成”的稳定 label/value、`imageReviewUnavailableDetail` 具体原因、可见按钮的 disabled 边界和既有完成空态焦点；锁定时不把只会被 guard 拒绝的 action 暴露给 VoiceOver。
- 新增 `scripts/test-v3149-image-review-completion-action-gate-contract.py`，并让 v3.128/v3.129/v3.148 历史合同接受同一 View-only helper 形式。改动只属于 View、静态合同和 CI 路由，不新增 Store／持久化状态，不改变 Vision OCR、模型翻译、renderer/export、漫画探针、Koharu active gate、metrics 或 `output`。

边界：候选、PR、merge 使用 `probe_mode=skip`，没有新的 OCR／翻译／Koharu 指标，也没有更新 `metrics/version_history.csv` 或仓库 `output/`。真实 `test/koharu_artifacts/` 四件套、Speech corpus 与真实竖排图片 corpus 仍缺失，readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不得据此声称 OCR、翻译、识别或 Koharu 质量提升。

云端证据：

- 候选 exact-SHA full [31161816278](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31161816278)：`validationProfile=full`、`validationReason=candidate_development_push`，commit `b0fc332c565fe501c8e2e939a086b79c142c9853`，Xcode build success，静态、UI、Speech、home、paste 合同 success，JUnit `10/10` 且 0 failures/errors，`probe_mode=skip`；Koharu active readiness 为 `manifestMissing / stopUntilArtifactsProvided`。
- PR #213 fast [31162344568](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31162344568)：`validationProfile=fast`，复用候选 full `b0fc332c565fe501c8e2e939a086b79c142c9853 / success`，Xcode/UI/Speech skipped，JUnit `10/10`；不是新的编译证据。
- merge fast [31162426726](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31162426726)：`validationProfile=fast`，`validationReason=merge_reuses_successful_candidate_full_validation`，复用候选 full `b0fc332c565fe501c8e2e939a086b79c142c9853 / success`，`receiptPropagationAllowed=true`，Xcode/UI/Speech skipped，JUnit `10/10`；不是新的编译证据。

## v3.148：普通图片全部忽略空态 VoiceOver action 门控

日期：2026-08-07

状态：Agent X 已完成 v3.148 普通图片全部 OCR 文字块被忽略时的 VoiceOver action 门控优化、候选 exact-SHA full、PR fast、merge fast 云端验收并合入 `smalldata_test`；工程正式版本为 `MARKETING_VERSION=3.148`。候选 commit `01231917a86696cfc3a864d9a6382119b8c13455` 已通过 PR [#212](https://github.com/bengzhu/project1_lgbt_naxida/pull/212) 合入，merge SHA `dc55005a501c4a2f59036de27312cc1163c84b3e`；`main` 未触碰。

核心变更：

- 全部 OCR 文字块被忽略的空态现在通过 View 私有 `allIgnoredBlocksEmptyStateAccessibility` helper 暴露 VoiceOver“恢复全部” action，且仅在 `canModifyImageTranslation` 为真时提供；翻译未完成或导出重绘期间不再暴露只会被 guard 拒绝的无效入口。
- 锁定时继续保留空态 label/value、`imageModificationUnavailableDetail` 具体原因和可见“恢复全部”按钮的 disabled 边界；可用时仍复用既有 `requestRestoreAllIgnoredImageTranslationBlocks()`、确认对话框、恢复顺序、焦点交接与 Store 门控。
- 新增 `scripts/test-v3148-image-ignored-empty-state-action-gate-contract.py`，并同步 v3.132 历史合同。改动只属于 View、静态合同和 CI 路由，不新增 Store／持久化状态，不改变 Vision OCR、模型翻译、renderer/export、漫画探针、Koharu active gate、metrics 或 `output`。

边界：候选、PR、merge 使用 `probe_mode=skip`，没有新的 OCR／翻译／Koharu 指标，也没有更新 `metrics/version_history.csv` 或仓库 `output/`。真实 `test/koharu_artifacts/` 四件套、Speech corpus 与真实竖排图片 corpus 仍缺失，readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不得据此声称 OCR、翻译、识别或 Koharu 质量提升。

云端证据：

- 候选 exact-SHA full [31160052402](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31160052402)：`validationProfile=full`、`validationReason=candidate_development_push`，commit `01231917a86696cfc3a864d9a6382119b8c13455`，Xcode build success，静态、UI、Speech、home、paste 合同 success，JUnit `10/10` 且 0 failures/errors，`probe_mode=skip`；Koharu active readiness 为 `manifestMissing / stopUntilArtifactsProvided`。
- PR #212 fast [31160532637](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31160532637)：`validationProfile=fast`，复用候选 full `01231917a86696cfc3a864d9a6382119b8c13455 / success`，Xcode/UI/Speech skipped，JUnit `10/10`；不是新的编译证据。
- merge fast [31160619661](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31160619661)：merge SHA `dc55005a501c4a2f59036de27312cc1163c84b3e`，`validationReason=merge_reuses_successful_candidate_full_validation`、`receiptPropagationAllowed=true`，复用候选 full，Xcode/UI/Speech skipped，JUnit `10/10`；不是新的编译证据。

## v3.147：普通图片 OCR 修正输入 VoiceOver 上下文

日期：2026-08-07

状态：Agent X 已完成 v3.147 普通图片 OCR 修正 sheet 输入上下文与保存锁定提示的 View-only UX 优化、候选 exact-SHA full、PR fast、merge fast 云端验收并合入 `smalldata_test`；工程正式版本为 `MARKETING_VERSION=3.147`。候选 commit `3a60ad6b431acfc11f2296ec59ec86609d107546` 已通过 PR [#211](https://github.com/bengzhu/project1_lgbt_naxida/pull/211) 合入，merge SHA `7e0bb80e4c3d077d56143d7375b34b6e6ef5ee61`；`main` 未触碰。

核心变更：

- `ImageOCRCorrectionSheet` 的“修正后的文字”输入框新增明确的 VoiceOver label、实时 value 与 View 私有动态 hint：空文本提示必须输入非空 OCR 原文；文本变化时说明只重新翻译当前文字块；未变化时说明“确认无误”不会重新翻译；保存期间说明暂不能编辑或忽略。
- “忽略此文字块”继续复用既有 `requestIgnoreConfirmation` 与 `requestIgnore`，仅把保存中的不可用边界加入动态 hint；未保存修正、确认对话框、当前图片会话范围和图片检查区恢复路径保持不变。
- 新增 `scripts/test-v3147-image-ocr-correction-input-accessibility-contract.py`，并让 v3.146 合同对未来正式版本保持回归兼容。该改动只属于 View 与静态合同，不新增 Store／持久化状态，不改变 Vision OCR、模型翻译、renderer/export、漫画探针、Koharu active gate、metrics 或 `output`。

边界：候选、PR、merge 使用 `probe_mode=skip`，没有新的 OCR／翻译／Koharu 指标，也没有更新 `metrics/version_history.csv` 或仓库 `output/`。真实 `test/koharu_artifacts/` 四件套、Speech corpus 与真实竖排图片 corpus 仍缺失，readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不得据此声称 OCR、翻译、识别或 Koharu 质量提升。

云端证据：

- 候选 exact-SHA full [31158590713](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31158590713)：`validationProfile=full`、`validationReason=candidate_development_push`，commit `3a60ad6b431acfc11f2296ec59ec86609d107546`，Xcode build success，静态、UI、Speech、home、paste 合同 success，JUnit `10/10` 且 0 failures/errors，`probe_mode=skip`；Koharu active readiness 为 `manifestMissing / stopUntilArtifactsProvided`。
- PR #211 fast [31159215608](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31159215608)：`validationProfile=fast`，复用候选 full `3a60ad6b431acfc11f2296ec59ec86609d107546 / success`，Xcode/UI/Speech skipped，JUnit `10/10`；不是新的编译证据。
- merge fast [31159309690](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31159309690)：merge SHA `7e0bb80e4c3d077d56143d7375b34b6e6ef5ee61`，`validationReason=merge_reuses_successful_candidate_full_validation`、`receiptPropagationAllowed=true`，复用候选 full，Xcode/UI/Speech skipped，JUnit `10/10`；不是新的编译证据。

## v3.146：普通图片已忽略 OCR 行直接恢复 action

日期：2026-08-07

状态：Agent X 已完成 v3.146 普通图片已忽略 OCR 文字块行的 VoiceOver 直接恢复 UX 优化、候选 exact-SHA full、PR fast、merge fast 云端验收并合入 `smalldata_test`；工程正式版本为 `MARKETING_VERSION=3.146`。候选 commit `21768ac2c9a9cd5efdb87aebae62def5f1e20071` 已通过 PR [#210](https://github.com/bengzhu/project1_lgbt_naxida/pull/210) 合入，merge SHA `f850351e67734fb28d1f5672cd55bfd4de28e87f`；`main` 未触碰。

核心变更：

- `ImageTranslationIgnoredBlockRow` 的父级 VoiceOver 容器在 `canRestore` 为真时提供同名“恢复” action，直接调用传入的既有 `restore` 回调，让 VoiceOver 用户无需先下钻到行内按钮即可恢复该 OCR 文字块。
- 父级 hint 明确恢复会回到图片预览、导出和当前转录，需要复查的文字块会重新进入待复查队列；锁定时不暴露父级 action，并继续显示 `modificationUnavailableHint`。
- 现有 44pt 子按钮、disabled 原因、`image-ignored-row-<UUID>` 焦点 identity、行 label/value 与恢复后的既有焦点交接保持不变；新增 `scripts/test-v3146-image-ignored-row-restore-action-contract.py` 并接入 UI/full fail-fast。该 View-only 改动不新增 Store／持久化，不改变 OCR、翻译、renderer/export、探针报告、Koharu active gate、metrics 或 `output`。

边界：候选、PR、merge 使用 `probe_mode=skip`，没有新的 OCR／翻译／Koharu 指标，也没有更新 `metrics/version_history.csv` 或仓库 `output/`。真实 `test/koharu_artifacts/` 四件套、Speech corpus 与真实竖排图片 corpus 仍缺失，readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不得据此声称 OCR、翻译、识别或 Koharu 质量提升。

云端证据：

- 候选 exact-SHA full [31157259172](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31157259172)：`validationProfile=full`、`validationReason=candidate_development_push`，commit `21768ac2c9a9cd5efdb87aebae62def5f1e20071`，Xcode build success，静态、UI、Speech、home、paste 合同 success，JUnit `10/10` 且 0 failures/errors，`probe_mode=skip`；Koharu active 工件目录缺失。
- PR #210 fast [31157792746](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31157792746)：`validationProfile=fast`，复用候选 full `21768ac2c9a9cd5efdb87aebae62def5f1e20071 / success`，Xcode/UI/Speech skipped，JUnit `10/10`；不是新的编译证据。
- merge fast [31157872257](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31157872257)：merge SHA `f850351e67734fb28d1f5672cd55bfd4de28e87f`，`validationReason=merge_reuses_successful_candidate_full_validation`、`receiptPropagationAllowed=true`，复用候选 full，Xcode/UI/Speech skipped，JUnit `10/10`；不是新的编译证据。

## v3.145：普通图片文件导入替换提示

日期：2026-08-07

状态：Agent X 已完成 v3.145 普通图片文件导入 VoiceOver 替换语义的 View-only UX 优化、候选 exact-SHA full、PR fast、merge fast 云端验收并合入 `smalldata_test`；工程正式版本为 `MARKETING_VERSION=3.145`。候选 commit `92f495212a40910be1540c06f28cf4402c0b956f` 已通过 PR [#209](https://github.com/bengzhu/project1_lgbt_naxida/pull/209) 合入，merge SHA `f66f6e2fa7877a212e057648ec18663ae8ba9c83`；`main` 未触碰。

核心变更：

- 文件导入入口现在与照片入口共享首次／替换语义：无图片时 VoiceOver 说明从文件选择并开始本机 OCR 与翻译，已有图片时说明更换当前图片并开始新的本机 OCR 与翻译。
- 图片读取、Vision OCR 或逐块翻译进行中继续保留 supersession 提示，明确从文件选择新图片会取消当前任务并开始新任务；文件入口仍保持可用，不新增 `.disabled(isRunning)`。
- 新增 `scripts/test-v3145-image-file-selection-replacement-hint-contract.py` 并接入 UI/full fail-fast；只读取既有 Store 状态并改善 View 文案，不新增 Store／持久化，不改变 OCR、翻译、renderer/export、探针报告、Koharu active gate、metrics 或 `output`。

边界：候选、PR、merge 使用 `probe_mode=skip`，没有新的 OCR／翻译／Koharu 指标，也没有更新 `metrics/version_history.csv` 或仓库 `output/`。真实 `test/koharu_artifacts/` 四件套、Speech corpus 与真实竖排图片 corpus 仍缺失，readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不得据此声称 OCR、翻译、识别或 Koharu 质量提升。

云端证据：

- 候选 exact-SHA full [31155971109](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31155971109)：`validationProfile=full`、`validationReason=candidate_development_push`，commit `92f495212a40910be1540c06f28cf4402c0b956f`，Xcode build success，静态、UI、Speech、home、paste 合同 success，JUnit `10/10` 且 0 failures/errors，`probe_mode=skip`；Koharu active 工件目录缺失。
- PR #209 fast [31156530851](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31156530851)：`validationProfile=fast`，复用候选 full `92f495212a40910be1540c06f28cf4402c0b956f / success`，Xcode/UI/Speech skipped，JUnit `10/10`；不是新的编译证据。
- merge fast [31156622662](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31156622662)：merge SHA `f66f6e2fa7877a212e057648ec18663ae8ba9c83`，`validationReason=merge_reuses_successful_candidate_full_validation`、`receiptPropagationAllowed=true`，复用候选 full，Xcode/UI/Speech skipped，JUnit `10/10`；不是新的编译证据。

## v3.144：普通图片 OCR 空结果直接重新识别 VoiceOver action

日期：2026-08-07

状态：Agent X 已完成 v3.144 普通图片 OCR 空结果直接重新识别的 View-only UX 优化、候选 exact-SHA full、PR fast、merge fast 云端验收并合入 `smalldata_test`；工程正式版本为 `MARKETING_VERSION=3.144`。候选 commit `ff31f66f71698c6f34a7e1b7e52a940485984eea` 已通过 PR [#208](https://github.com/bengzhu/project1_lgbt_naxida/pull/208) 合入，merge SHA `914bf3d5c35354ce4e23e5f6bc470d6e2ba886f0`；`main` 未触碰。

核心变更：

- 当普通图片翻译已完成、当前没有可显示 OCR 文字块且源图片仍由 Store 保留时，结果空态通过 View-only helper 提供同名“重新识别” VoiceOver action，直接复用既有 `store.rerunImageRecognition()`。
- action 受既有 `store.canRerunImageRecognition` 门控；源图片文件缺失或状态不是 `.translated` 时不暴露 action。提示明确该操作只重跑当前图片的 Vision OCR 与翻译，不把空态恢复误解为新图片选择或漫画探针。
- 新增 `scripts/test-v3144-image-empty-result-rerun-action-contract.py` 并接入 UI/full fail-fast；未新增 Store／持久化状态，不改变 OCR、翻译、renderer/export、探针报告、Koharu active gate、metrics 或 `output`。

边界：候选、PR、merge 使用 `probe_mode=skip`，没有新的 OCR／翻译／Koharu 指标，也没有更新 `metrics/version_history.csv` 或仓库 `output/`。真实 `test/koharu_artifacts/` 四件套、Speech corpus 与真实竖排图片 corpus 仍缺失，readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不得据此声称 OCR、翻译、识别或 Koharu 质量提升。

云端证据：

- 候选 exact-SHA full [31154791726](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31154791726)：`validationProfile=full`、`validationReason=candidate_development_push`，commit `ff31f66f71698c6f34a7e1b7e52a940485984eea`，Xcode build success，静态、UI、Speech、home、paste 合同 success，JUnit `10/10` 且 0 failures/errors，`probe_mode=skip`；Koharu readiness 为 `manifestMissing / stopUntilArtifactsProvided`。
- PR #208 fast [31155305272](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31155305272)：`validationProfile=fast`，复用候选 full `ff31f66f71698c6f34a7e1b7e52a940485984eea / success`，Xcode/UI/Speech skipped，JUnit `10/10`；不是新的编译证据。
- merge fast [31155356211](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31155356211)：merge SHA `914bf3d5c35354ce4e23e5f6bc470d6e2ba886f0`，`validationReason=merge_reuses_successful_candidate_full_validation`、`receiptPropagationAllowed=true`，复用候选 full，Xcode/UI/Speech skipped，JUnit `10/10`；不是新的编译证据。

## v3.143：普通图片 OCR 结果行 VoiceOver action hint

日期：2026-08-07

状态：Agent X 已完成 v3.143 普通图片 OCR 结果行动态 VoiceOver 操作提示的 View-only UX 优化、候选 exact-SHA full、PR fast、merge fast 云端验收并合入 `smalldata_test`；工程正式版本为 `MARKETING_VERSION=3.143`。候选 commit `3a6da4be92c3275c2efb31dab550b5a227af5da8` 已通过 PR [#207](https://github.com/bengzhu/project1_lgbt_naxida/pull/207) 合入，merge SHA `6bd71ae8ed1e34f2ad4ce0675c6b05e2c9e8b936`；`main` 未触碰。

核心变更：

- `ImageTranslationBlockRow` 的主 VoiceOver hint 现在复用当前行真实门控，动态列出“修正识别文字”“恢复 Vision OCR”以及“完成并继续复查／撤销本次复查”等已暴露 action，让用户在定位提示之外知道可执行操作。
- `canEdit`、`isManuallyCorrected`、风险块与 `canReview` 任一条件不满足时，不把对应 action 写入 hint；定位状态、几何不可用提示、`.accessibilityElement(children: .combine)`、动态 value、focus identity 和可见按钮保持不变。
- 新增 `scripts/test-v3143-image-review-row-action-hint-contract.py` 并接入 UI/full fail-fast；改动只属于 View，不新增 Store／持久化，不改变 OCR、翻译、renderer/export、探针报告、Koharu active gate、metrics 或 `output`。

边界：候选、PR、merge 使用 `probe_mode=skip`，没有新的 OCR／翻译／Koharu 指标，也没有更新 `metrics/version_history.csv` 或仓库 `output/`。真实 `test/koharu_artifacts/` 四件套、Speech corpus 与真实竖排图片 corpus 仍缺失，readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不得据此声称 OCR、翻译、识别或 Koharu 质量提升。

云端证据：

- 候选 exact-SHA full [31153705887](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31153705887)：`validationProfile=full`、`validationReason=manual_full`，commit `3a6da4be92c3275c2efb31dab550b5a227af5da8`，Xcode build success，UI／Speech／home／paste 合同 success，JUnit `10/10` 且 0 failures，`probe_mode=skip`；Koharu readiness 为 `manifestMissing / stopUntilArtifactsProvided`。
- PR #207 fast [31154097383](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31154097383)：`validationProfile=fast`，复用候选 full `3a6da4be92c3275c2efb31dab550b5a227af5da8 / success`，Xcode/UI/Speech skipped，JUnit `10/10`；不是新的编译证据。
- merge fast [31154147898](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31154147898)：merge SHA `6bd71ae8ed1e34f2ad4ce0675c6b05e2c9e8b936`，`validationReason=merge_reuses_successful_candidate_full_validation`、`receiptPropagationAllowed=true`，复用候选 full，Xcode/UI/Speech skipped，JUnit `10/10`；不是新的编译证据。
- 文档 metadata follow-up [31154278384](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31154278384)：commit `7b5b7d7b79eb5e03acb36bd2625d59d27eaf9a74`，`smalldataIncrementalMetadataOnly=true`，`validationReason=smalldata_metadata_followup_reuses_parent_full_validation`，复用父 merge `6bd71ae8ed1e34f2ad4ce0675c6b05e2c9e8b936 / success`，`receiptPropagationAllowed=true`，Xcode/UI/Speech skipped，JUnit `10/10`；不是新的编译证据。

## v3.142：普通图片 OCR 结果行 VoiceOver review action

日期：2026-08-07

状态：Agent X 已完成 v3.142 普通图片风险 OCR 结果行直接复查操作的 View-only UX 优化、候选 exact-SHA full、PR fast、merge fast 云端验收并合入 `smalldata_test`；工程正式版本为 `MARKETING_VERSION=3.142`。候选 commit `e94fb6a1fdfbeaddd64a0995dda5d1e872e91d84` 已通过 PR [#206](https://github.com/bengzhu/project1_lgbt_naxida/pull/206) 合入，merge SHA `28101601c1ed455950736bcc7ae010ff580f5636`；`main` 未触碰。

核心变更：

- `ImageTranslationBlockRow` 对需要复查且 `canReview` 为真的风险结果行，通过 View-only `ImageReviewRowReviewAccessibilityModifier` 提供同名“完成并继续复查／撤销本次复查” VoiceOver action，直接复用既有 `toggleReviewCompletion()`，让 VoiceOver 用户无需先下钻到行内复查按钮即可沿用当前复查队列。
- 非风险或 `canReview` 为假时不暴露该 action；可见“完成并继续复查／撤销本次复查”按钮、`.disabled(!canReview)`、现有 `reviewUnavailableHint`、结果行定位 label/value/hint 与 `image-review-row-*` focus identity 保持不变。
- 新增 `scripts/test-v3142-image-review-row-review-action-contract.py` 并接入 UI/full fail-fast；改动只属于 View，不新增 Store／持久化，不改变 OCR、翻译、renderer/export、探针报告、Koharu active gate、metrics 或 `output`。

边界：候选、PR、merge 使用 `probe_mode=skip`，没有新的 OCR／翻译／Koharu 指标，也没有更新 `metrics/version_history.csv` 或仓库 `output/`。真实 `test/koharu_artifacts/` 四件套、Speech corpus 与真实竖排图片 corpus 仍缺失，readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不得据此声称 OCR、翻译、识别或 Koharu 质量提升。

云端证据：

- 候选 exact-SHA full [31152734900](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31152734900)：`validationProfile=full`、`validationReason=manual_full`，commit `e94fb6a1fdfbeaddd64a0995dda5d1e872e91d84`，Xcode build success，UI／Speech／home／paste 合同 success，JUnit `10/10` 且 0 failures，`probe_mode=skip`；Koharu readiness 为 `manifestMissing / stopUntilArtifactsProvided`。
- PR #206 fast [31153171846](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31153171846)：`validationProfile=fast`，复用候选 full `e94fb6a1fdfbeaddd64a0995dda5d1e872e91d84 / success`，Xcode/UI/Speech skipped，JUnit `10/10`；不是新的编译证据。
- merge fast [31153229469](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31153229469)：merge SHA `28101601c1ed455950736bcc7ae010ff580f5636`，`validationReason=merge_reuses_successful_candidate_full_validation`、`receiptPropagationAllowed=true`，复用候选 full，Xcode/UI/Speech skipped，JUnit `10/10`；不是新的编译证据。
- 文档 metadata follow-up [31153329054](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31153329054)：commit `9a0fea04baf61bc79987be05a438aa6ceb06113c`，`smalldataIncrementalMetadataOnly=true`，`validationReason=smalldata_metadata_followup_reuses_parent_full_validation`，复用父 merge `28101601c1ed455950736bcc7ae010ff580f5636 / success`，`receiptPropagationAllowed=true`，Xcode/UI/Speech skipped，JUnit `10/10`；不是新的编译证据。

## v3.141：普通图片 OCR 结果行 VoiceOver restore action

日期：2026-08-07

状态：Agent X 已完成 v3.141 普通图片 OCR 结果行直接恢复 Vision OCR 操作的 View-only UX 优化、候选 exact-SHA full、PR fast、merge fast 云端验收并合入 `smalldata_test`；工程正式版本为 `MARKETING_VERSION=3.141`。候选 commit `3a98ecb36bcfef8dfc77823b0eae26b06f0980bd` 已通过 PR [#205](https://github.com/bengzhu/project1_lgbt_naxida/pull/205) 合入，merge SHA `7b0684765acdf7f79ae01b462b8a0eb1ddaee674`；`main` 未触碰。

核心变更：

- `ImageTranslationBlockRow` 对已人工修正且 `canEdit` 为真的结果行，通过 View-only `ImageReviewRowRestoreAccessibilityModifier` 提供同名“恢复 Vision OCR” VoiceOver action，直接复用既有 `restoreVisionOCR()`，让 VoiceOver 用户无需先下钻到行内恢复按钮即可回到 Vision OCR 原文与初始译文。
- 未人工修正或 `canEdit` 为假时不暴露该 action；可见“恢复 Vision OCR”按钮、`.disabled(!canEdit)`、现有 `modificationUnavailableHint`、结果行定位 label/value/hint 与 `image-review-row-*` focus identity 保持不变。
- 新增 `scripts/test-v3141-image-review-row-restore-action-contract.py` 并接入 UI/full fail-fast；改动只属于 View，不新增 Store／持久化，不改变 OCR、翻译、renderer/export、探针报告、Koharu active gate、metrics 或 `output`。

边界：候选、PR、merge 使用 `probe_mode=skip`，没有新的 OCR／翻译／Koharu 指标，也没有更新 `metrics/version_history.csv` 或仓库 `output/`。真实 `test/koharu_artifacts/` 四件套、Speech corpus 与真实竖排图片 corpus 仍缺失，readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不得据此声称 OCR、翻译、识别或 Koharu 质量提升。

云端证据：

- 候选 exact-SHA full [31151758844](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31151758844)：`validationProfile=full`、`validationReason=manual_full`，commit `3a98ecb36bcfef8dfc77823b0eae26b06f0980bd`，Xcode build success，UI／Speech／home／paste 合同 success，JUnit `10/10` 且 0 failures，`probe_mode=skip`；Koharu readiness 为 `manifestMissing / stopUntilArtifactsProvided`。
- PR #205 fast [31152271664](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31152271664)：`validationProfile=fast`，复用候选 full `3a98ecb36bcfef8dfc77823b0eae26b06f0980bd / success`，Xcode/UI/Speech skipped，JUnit `10/10`；不是新的编译证据。
- merge fast [31152319773](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31152319773)：merge SHA `7b0684765acdf7f79ae01b462b8a0eb1ddaee674`，`validationReason=merge_reuses_successful_candidate_full_validation`、`receiptPropagationAllowed=true`，复用候选 full，Xcode/UI/Speech skipped，JUnit `10/10`；不是新的编译证据。
- 文档 metadata follow-up [31152425498](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31152425498)：commit `b3b18e2d9eaf3f59879a813ca71e1c85a47a3e26`，`smalldataIncrementalMetadataOnly=true`，`validationReason=smalldata_metadata_followup_reuses_parent_full_validation`，复用父 merge `7b0684765acdf7f79ae01b462b8a0eb1ddaee674 / success`，`receiptPropagationAllowed=true`，Xcode/UI/Speech skipped，JUnit `10/10`；不是新的编译证据。

## v3.140：普通图片 OCR 结果行 VoiceOver edit action

日期：2026-08-07

状态：Agent X 已完成 v3.140 普通图片 OCR 结果行直接修正操作的 View-only UX 优化、候选 exact-SHA full、PR fast、merge fast 云端验收并合入 `smalldata_test`；工程正式版本为 `MARKETING_VERSION=3.140`。候选 commit `9571f142b35193cc86151b4e2971ccd6becfafbc` 已通过 PR [#204](https://github.com/bengzhu/project1_lgbt_naxida/pull/204) 合入，merge SHA `44394ba2068f7e173a7ba72223fc4210eda89239`；`main` 未触碰。

核心变更：

- `ImageTranslationBlockRow` 的主结果行在 `canEdit` 为真时通过 View-only `ImageReviewRowEditAccessibilityModifier` 提供同名“修正识别文字” VoiceOver action，直接复用既有 `edit()`，让 VoiceOver 用户无需先下钻到行内可见铅笔按钮即可打开 OCR 修正入口。
- `canEdit` 为假时不暴露该 action；可见“修正识别文字”按钮、`.disabled(!canEdit)`、现有 `modificationUnavailableHint`、结果行定位 label/value/hint 与 `image-review-row-*` focus identity 保持不变。
- 新增 `scripts/test-v3140-image-review-row-edit-action-contract.py` 并接入 UI/full fail-fast；改动只属于 View，不新增 Store／持久化，不改变 OCR、翻译、renderer/export、探针报告、Koharu active gate、metrics 或 `output`。

边界：候选、PR、merge 使用 `probe_mode=skip`，没有新的 OCR／翻译／Koharu 指标，也没有更新 `metrics/version_history.csv` 或仓库 `output/`。真实 `test/koharu_artifacts/` 四件套、Speech corpus 与真实竖排图片 corpus 仍缺失，readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不得据此声称 OCR、翻译、识别或 Koharu 质量提升。

云端证据：

- 候选 exact-SHA full [31150859808](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31150859808)：`validationProfile=full`、`validationReason=manual_full`，commit `9571f142b35193cc86151b4e2971ccd6becfafbc`，Xcode build success，UI／Speech／home／paste 合同 success，JUnit `10/10` 且 0 failures，`probe_mode=skip`；Koharu readiness 为 `manifestMissing / stopUntilArtifactsProvided`。
- PR #204 fast [31151298078](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31151298078)：`validationProfile=fast`，复用候选 full `9571f142b35193cc86151b4e2971ccd6becfafbc / success`，Xcode/UI/Speech skipped，JUnit `10/10`；不是新的编译证据。
- merge fast [31151339355](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31151339355)：merge SHA `44394ba2068f7e173a7ba72223fc4210eda89239`，`validationReason=merge_reuses_successful_candidate_full_validation`、`receiptPropagationAllowed=true`，复用候选 full，Xcode/UI/Speech skipped，JUnit `10/10`；不是新的编译证据。
- 文档 metadata follow-up [31151469822](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31151469822)：commit `295a69f252095cd7fe14330067eb55abdea50328`，`smalldataIncrementalMetadataOnly=true`，`validationReason=smalldata_metadata_followup_reuses_parent_full_validation`，复用父 merge `44394ba2068f7e173a7ba72223fc4210eda89239 / success`，`receiptPropagationAllowed=true`，Xcode/UI/Speech skipped，JUnit `10/10`；不是新的编译证据。

## v3.139：图片局部放大 VoiceOver navigation actions

日期：2026-08-07

状态：Agent X 已完成 v3.139 图片局部放大导航操作的 View-only UX 优化、候选 exact-SHA full、PR fast、merge fast 云端验收并合入 `smalldata_test`；工程正式版本为 `MARKETING_VERSION=3.139`。候选 commit `044e137c1fae3ca08bccbfd2ab37422bdce95c40` 已通过 PR [#203](https://github.com/bengzhu/project1_lgbt_naxida/pull/203) 合入，merge SHA `8a337da354936c3e7b0327cd154f7519b64fbed3`；候选远端分支已清理，`main` 未触碰。

核心变更：

- `ImageTranslationFocusPreview` 在 `canSelectPrevious`／`canSelectNext` 为真时通过 View-only accessibility modifier 提供同名“上一个文字块”／“下一个文字块” action，直接复用既有 `selectPrevious()`／`selectNext()`，让 VoiceOver 用户在父级局部预览上下文中直接切换筛选结果。
- 首尾或单项筛选时分别隐藏不可用 action；可见导航按钮、当前位置 value、首尾 disabled hint、筛选顺序和既有焦点交接保持不变。
- 新增 `scripts/test-v3139-image-focus-navigation-action-contract.py` 并接入 UI/full fail-fast；历史 v3.132–v3.138 合同继续接受 `13[0-9]` 路由。改动只属于 View，不新增 Store／持久化，不改变 OCR、翻译、renderer/export、探针报告、Koharu active gate、metrics 或 `output`。

边界：候选、PR、merge 使用 `probe_mode=skip`，没有新的 OCR／翻译／Koharu 指标，也没有更新 `metrics/version_history.csv` 或仓库 `output/`。真实 `test/koharu_artifacts/` 四件套、Speech corpus 与真实竖排图片 corpus 仍缺失，readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不得据此声称 OCR、翻译、识别或 Koharu 质量提升。

云端证据：

- 候选 exact-SHA full [31149836170](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31149836170)：`validationProfile=full`、`validationReason=manual_full`，commit `044e137c1fae3ca08bccbfd2ab37422bdce95c40`，Xcode build success，UI／Speech／home／paste 合同 success，JUnit `10/10` 且 0 failures，`probe_mode=skip`；Koharu readiness 为 `manifestMissing / stopUntilArtifactsProvided`。
- PR #203 fast [31150269494](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31150269494)：`validationProfile=fast`，复用候选 full `044e137c1fae3ca08bccbfd2ab37422bdce95c40 / success`，Xcode/UI/Speech skipped，JUnit `10/10`；不是新的编译证据。
- merge fast [31150318388](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31150318388)：merge SHA `8a337da354936c3e7b0327cd154f7519b64fbed3`，`validationReason=merge_reuses_successful_candidate_full_validation`、`receiptPropagationAllowed=true`，复用候选 full，Xcode/UI/Speech skipped，JUnit `10/10`；不是新的编译证据。
- 文档 metadata follow-up [31150421037](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31150421037)：commit `f96f018200ac4f428ea8dabfa5f7103dfd0a637d`，`smalldataIncrementalMetadataOnly=true`，`validationReason=smalldata_metadata_followup_reuses_parent_full_validation`，复用父 merge `8a337da354936c3e7b0327cd154f7519b64fbed3 / success`，`receiptPropagationAllowed=true`，Xcode/UI/Speech skipped，JUnit `10/10`；不是新的编译证据。

## v3.138：图片局部放大 VoiceOver review action

日期：2026-08-07

状态：Agent X 已完成 v3.138 图片局部放大复查操作的 View-only UX 优化、候选 exact-SHA full、PR fast、merge fast 云端验收并合入 `smalldata_test`；工程正式版本为 `MARKETING_VERSION=3.138`。候选 commit `52e78935232cff22ef4bb45285a45218e6bd1b85` 已通过 PR [#202](https://github.com/bengzhu/project1_lgbt_naxida/pull/202) 合入，merge SHA `490c98062bd989f09334e202b73942f684c7c5f2`；候选远端分支已清理，`main` 未触碰。

核心变更：

- `ImageTranslationFocusPreview` 在 `isReviewRequired && canReview` 时通过 View-only accessibility modifier 提供与可见按钮同名的“完成并继续复查／重新加入待复查” action，直接复用既有 `toggleReviewCompletion()`，让 VoiceOver 用户无需先下钻到局部预览底部按钮即可更新当前复查进度。
- 不需要复查或复查被锁定时不暴露该 action；局部预览父级 hint 继续保留关闭／修正／切换上下文，并在锁定状态说明现有 `reviewUnavailableHint`；可见复查按钮、焦点 identity 与既有 Store 门控保持不变。
- 新增 `scripts/test-v3138-image-focus-review-action-contract.py` 并接入 UI/full fail-fast；为兼容新 CI 正则，历史 v3.132–v3.137 合同接受 `13[0-8]` 路由。改动只属于 View，不新增 Store／持久化，不改变 OCR、翻译、renderer/export、探针报告、Koharu active gate、metrics 或 `output`。

边界：候选、PR、merge 使用 `probe_mode=skip`，没有新的 OCR／翻译／Koharu 指标，也没有更新 `metrics/version_history.csv` 或仓库 `output/`。真实 `test/koharu_artifacts/` 四件套、Speech corpus 与真实竖排图片 corpus 仍缺失，readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不得据此声称 OCR、翻译、识别或 Koharu 质量提升。

云端证据：

- 候选 exact-SHA full [31148861374](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31148861374)：`validationProfile=full`、`validationReason=manual_full`，commit `52e78935232cff22ef4bb45285a45218e6bd1b85`，Xcode build success，UI／Speech／home／paste 合同 success，JUnit `10/10` 且 0 failures，`probe_mode=skip`；Koharu readiness 为 `manifestMissing / stopUntilArtifactsProvided`。
- PR #202 fast [31149234166](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31149234166)：`validationProfile=fast`，复用候选 full `52e78935232cff22ef4bb45285a45218e6bd1b85 / success`，Xcode/UI/Speech skipped，JUnit `10/10`；不是新的编译证据。
- merge fast [31149285259](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31149285259)：merge SHA `490c98062bd989f09334e202b73942f684c7c5f2`，`validationReason=merge_reuses_successful_candidate_full_validation`、`receiptPropagationAllowed=true`，复用候选 full，Xcode/UI/Speech skipped，JUnit `10/10`；不是新的编译证据。
- 文档 metadata follow-up [31149572310](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31149572310)：commit `66476fe1764b9e9b842b570ba96aeb0bba5ae899`，`smalldataIncrementalMetadataOnly=true`，`validationReason=smalldata_metadata_followup_reuses_parent_full_validation`，复用父 merge `490c98062bd989f09334e202b73942f684c7c5f2 / success`，`receiptPropagationAllowed=true`，Xcode/UI/Speech skipped，JUnit `10/10`；不是新的编译证据。

## v3.137：图片局部放大 VoiceOver edit action

日期：2026-08-07

状态：Agent X 已完成 v3.137 图片局部放大容器直接修正 OCR 操作的 View-only UX 优化、候选 exact-SHA full、PR fast、merge fast 云端验收并合入 `smalldata_test`；工程正式版本为 `MARKETING_VERSION=3.137`。候选 commit `46f617f8ce9a78628c4bdef54a800e4a4dc4e5a3` 已通过 PR [#201](https://github.com/bengzhu/project1_lgbt_naxida/pull/201) 合入，merge SHA `9f8a05bd0b6001e8cfc0a94213cfee8a5f2e3583`；候选远端分支已清理，`main` 未触碰。

核心变更：

- `ImageTranslationFocusPreview` 在 `canEdit` 为真时通过 View-only accessibility modifier 提供同名“修正识别文字” action，直接复用既有 `edit()`，让 VoiceOver 用户无需先下钻到可见按钮即可进入 OCR 修正。
- `canEdit` 为假时不暴露该 action；局部预览可用／不可用两条父级 hint 分别说明可执行操作或现有 `modificationUnavailableHint`，可见修正按钮、close action、focus identity 与 OCR 修正 sheet 入口保持不变。
- 新增 `scripts/test-v3137-image-focus-edit-action-contract.py` 并接入 UI/full fail-fast；历史 v3.68/v3.77 合同放宽为接受这条等价的 gated hint 语义。改动只属于 View，不新增 Store／持久化，不改变 OCR、翻译、renderer/export、探针报告、Koharu active gate、metrics 或 `output`。

边界：候选、PR、merge 使用 `probe_mode=skip`，没有新的 OCR／翻译／Koharu 指标，也没有更新 `metrics/version_history.csv` 或仓库 `output/`。真实 `test/koharu_artifacts/` 四件套、Speech corpus 与真实竖排图片 corpus 仍缺失，readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不得据此声称 OCR、翻译、识别或 Koharu 质量提升。

云端证据：

- 候选 exact-SHA full [31147358078](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31147358078)：`validationReason=candidate_development_push`，commit `46f617f8ce9a78628c4bdef54a800e4a4dc4e5a3`，Xcode build success，UI／Speech／home／paste 合同 success，JUnit `10/10` 且 0 failures，`probe_mode=skip`；active Koharu validator 为 `manifestMissing / stopUntilArtifactsProvided`。
- PR #201 fast [31147793085](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31147793085)：`validationProfile=fast`，复用候选 full `46f617f8ce9a78628c4bdef54a800e4a4dc4e5a3 / success`，Xcode skipped，JUnit `10/10`；不是新的编译证据。
- merge fast [31147924273](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31147924273)：merge SHA `9f8a05bd0b6001e8cfc0a94213cfee8a5f2e3583`，`validationReason=merge_reuses_successful_candidate_full_validation`、`receiptPropagationAllowed=true`，复用候选 full，Xcode skipped，JUnit `10/10`；不是新的编译证据。
- 文档 metadata follow-up [31148236214](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31148236214)：commit `f43df97fd2bde13925bb4e8180dcfac98d2401f0`，`smalldataIncrementalMetadataOnly=true`，`validationReason=smalldata_metadata_followup_reuses_parent_full_validation`，复用父 merge `9f8a05bd0b6001e8cfc0a94213cfee8a5f2e3583 / success`，`receiptPropagationAllowed=true`，Xcode/UI/Speech skipped，JUnit `10/10`；不是新的编译证据。

## v3.136：图片局部放大 VoiceOver close action

日期：2026-08-07

状态：Agent X 已完成 v3.136 图片局部放大预览关闭操作的 View-only UX 优化、候选 exact-SHA full、PR fast、merge fast 云端验收并合入 `smalldata_test`；工程正式版本为 `MARKETING_VERSION=3.136`。候选 commit `0c4bddf96354989d9d2efc445987de3e8a3eafb4` 已通过 PR [#200](https://github.com/bengzhu/project1_lgbt_naxida/pull/200) 合入，merge SHA `321f0fbcdcea704455174772da486a0a00f04754`；候选远端分支已清理，`main` 未触碰。

核心变更：

- `ImageTranslationFocusPreview` 父容器新增同名“关闭局部放大” VoiceOver action，直接复用既有 `close()`，让无障碍用户无需依赖可见按钮即可退出局部放大。
- 可见关闭按钮 hint 明确“关闭局部放大并返回当前文字块结果行”；稳定 label/value/hint、focus identity 及 `ImageTranslationPanel.closeImageTranslationFocusPreview()` 的清除选中／回焦点路径保持不变。
- 新增 `scripts/test-v3136-image-focus-close-action-contract.py` 并接入 UI/full fail-fast；改动只属于 View，不新增 Store／持久化，不改变 OCR、翻译、renderer/export、探针报告、Koharu active gate、metrics 或 `output`。

边界：候选、PR、merge 使用 `probe_mode=skip`，没有新的 OCR／翻译／Koharu 指标，也没有更新 `metrics/version_history.csv` 或仓库 `output/`。真实 `test/koharu_artifacts/` 四件套、Speech corpus 与真实竖排图片 corpus 仍缺失，readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不得据此声称 OCR、翻译、识别或 Koharu 质量提升。

云端证据：

- 候选 exact-SHA full [31144595687](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31144595687)：`validationReason=candidate_development_push`，commit `0c4bddf96354989d9d2efc445987de3e8a3eafb4`，Xcode build success，UI／Speech／home／paste 合同 success，JUnit `10/10` 且 0 failures，`probe_mode=skip`；active Koharu validator 为 `manifestMissing / stopUntilArtifactsProvided`。
- PR #200 fast [31144958126](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31144958126)：`validationProfile=fast`，复用候选 full `0c4bddf96354989d9d2efc445987de3e8a3eafb4 / success`，Xcode skipped，JUnit `10/10`；不是新的编译证据。
- merge fast [31144998556](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31144998556)：merge SHA `321f0fbcdcea704455174772da486a0a00f04754`，`validationReason=merge_reuses_successful_candidate_full_validation`、`receiptPropagationAllowed=true`，复用候选 full，Xcode skipped，JUnit `10/10`；不是新的编译证据。
- 文档 metadata follow-up [31145213978](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31145213978)：commit `ad420bc25847f46396e0a5689975d09d14a40372`，`smalldataIncrementalMetadataOnly=true`，`validationReason=smalldata_metadata_followup_reuses_parent_full_validation`，复用父 merge `321f0fbcdcea704455174772da486a0a00f04754 / success`，`receiptPropagationAllowed=true`，Xcode/UI/Speech skipped，JUnit `10/10`；不是新的编译证据。

## v3.135：图片预览状态 VoiceOver hint

日期：2026-08-07

状态：Agent X 已完成 v3.135 图片预览加载／失败状态的动态 VoiceOver hint、候选 exact-SHA full、PR fast、merge fast 云端验收并合入 `smalldata_test`；工程正式版本为 `MARKETING_VERSION=3.135`。候选 commit `728b96a06491f41f5a8809fc2649486bdae81444` 已通过 PR [#199](https://github.com/bengzhu/project1_lgbt_naxida/pull/199) 合入，merge SHA `b45bd83b24a7d021e3f414990ad85be60b494312`；候选远端分支已清理，`main` 未触碰。

核心变更：

- `ImageTranslationPreview` 预览状态容器新增动态 `previewStatusAccessibilityHint`：失败当前 revision 时明确可执行“重试预览”，只重建屏幕预览，不重新识别或翻译图片。
- loading 状态说明屏幕预览生成中、完成后可定位文字块及失败恢复边界；v3.134 的 retry action、可见按钮、label/value 和稳定 focus 保持不变。
- 新增 `scripts/test-v3135-image-preview-status-hint-contract.py` 并接入 UI/full fail-fast；改动只属于 View，不新增 Store／持久化，不改变 OCR、翻译、renderer/export、探针报告、Koharu active gate、metrics 或 `output`。

边界：候选、PR、merge 使用 `probe_mode=skip`，没有新的 OCR／翻译／Koharu 指标，也没有更新 `metrics/version_history.csv` 或仓库 `output/`。真实 `test/koharu_artifacts/` 四件套、Speech corpus 与真实竖排图片 corpus 仍缺失，readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不得据此声称 OCR、翻译、识别或 Koharu 质量提升。

云端证据：

- 候选 exact-SHA full [31143646549](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31143646549)：`validationReason=candidate_development_push`，commit `728b96a06491f41f5a8809fc2649486bdae81444`，Xcode build success，UI／Speech／home／paste 合同 success，JUnit `10/10` 且 0 failures，`probe_mode=skip`；active Koharu validator 为 `manifestMissing / stopUntilArtifactsProvided`。
- PR #199 fast [31144019839](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31144019839)：`validationProfile=fast`，复用候选 full `728b96a06491f41f5a8809fc2649486bdae81444 / success`，Xcode skipped，JUnit `10/10`；不是新的编译证据。
- merge fast [31144057333](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31144057333)：merge SHA `b45bd83b24a7d021e3f414990ad85be60b494312`，`validationReason=merge_reuses_successful_candidate_full_validation`、`receiptPropagationAllowed=true`，复用候选 full，Xcode skipped，JUnit `10/10`；不是新的编译证据。
- 文档 metadata follow-up [31144359776](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31144359776)：commit `ad33a380bf73b4f04608fea842191cad753b0b0b`，`validationReason=smalldata_metadata_followup_reuses_parent_full_validation`，复用父 merge `b45bd83b24a7d021e3f414990ad85be60b494312 / success`，`receiptPropagationAllowed=true`，Xcode/UI/Speech skipped，JUnit `10/10`；不是新的编译证据。

## v3.134：图片预览失败状态 VoiceOver retry action

日期：2026-08-07

状态：Agent X 已完成 v3.134 图片预览失败状态的可执行 VoiceOver 上下文、候选 exact-SHA full、PR fast、merge fast 云端验收并合入 `smalldata_test`；工程正式版本为 `MARKETING_VERSION=3.134`。候选 commit `94e26b435226a966a3c866fa222da92e7eff69c3` 已通过 PR [#198](https://github.com/bengzhu/project1_lgbt_naxida/pull/198) 合入，merge SHA `730312af21e2bc081d8d414f3d6b28acd0e3277b`；候选远端分支已清理，`main` 未触碰。

核心变更：

- `ImageTranslationPreview` 的预览状态在当前 `imageTranslationRevision` 失败时成为可执行 VoiceOver 上下文，提供同名“重试预览” action；loading 状态不暴露 action。
- action、可见“重试预览”按钮与状态 label/value/hint 共用既有 `retryPreview()`，只重建屏幕预览，不重新 OCR 或翻译；稳定 preview status focus 与 revision guard 保持不变。
- 新增 `scripts/test-v3134-image-preview-status-retry-action-contract.py` 并接入 UI/full fail-fast；改动只属于 View，不新增 Store／持久化，不改变 OCR、翻译、renderer/export、探针报告、Koharu active gate、metrics 或 `output`。

边界：候选、PR、merge 使用 `probe_mode=skip`，没有新的 OCR／翻译／Koharu 指标，也没有更新 `metrics/version_history.csv` 或仓库 `output/`。真实 `test/koharu_artifacts/` 四件套、Speech corpus 与真实竖排图片 corpus 仍缺失，readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不得据此声称 OCR、翻译、识别或 Koharu 质量提升。

云端证据：

- 候选 exact-SHA full [31142629553](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31142629553)：`validationReason=manual_full`，commit `94e26b435226a966a3c866fa222da92e7eff69c3`，Xcode build success，UI／Speech／home／paste 合同 success，JUnit `10/10` 且 0 failures，`probe_mode=skip`；active Koharu validator 为 `manifestMissing / stopUntilArtifactsProvided`。
- PR #198 fast [31142975439](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31142975439)：`validationProfile=fast`，复用候选 full `94e26b435226a966a3c866fa222da92e7eff69c3 / success`，Xcode skipped，JUnit `10/10`；不是新的编译证据。
- merge fast [31143030561](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31143030561)：merge SHA `730312af21e2bc081d8d414f3d6b28acd0e3277b`，`validationReason=merge_reuses_successful_candidate_full_validation`、`receiptPropagationAllowed=true`，复用候选 full，Xcode skipped，JUnit `10/10`；不是新的编译证据。
- 文档 metadata follow-up [31143296041](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31143296041)：commit `a22fdfc876cb3afad46788f6a45aae36a9a47dbe`，`validationReason=smalldata_metadata_followup_reuses_parent_full_validation`，复用父 merge `730312af21e2bc081d8d414f3d6b28acd0e3277b / success`，`receiptPropagationAllowed=true`，Xcode/UI/Speech skipped，JUnit `10/10`；不是新的编译证据。

## v3.133：图片空预览与识别结果空态 VoiceOver 上下文

日期：2026-08-07

状态：Agent X 已完成 v3.133 普通图片空预览与识别结果空态的 VoiceOver 语义优化、候选 exact-SHA full、PR fast、merge fast 云端验收并合入 `smalldata_test`；工程正式版本为 `MARKETING_VERSION=3.133`。候选 commit `a1bc1ba4a73d4337e83c2a99f911ce3f709dc207` 已通过 PR [#197](https://github.com/bengzhu/project1_lgbt_naxida/pull/197) 合入，merge SHA `30678f089d5764b06bdf2d459c55ba2677d872cb`；候选远端分支已清理，`main` 未触碰。

核心变更：

- `ImageTranslationPreview` 无图片分支现在是稳定的 VoiceOver 上下文，读出“图片翻译预览”“当前没有图片”和从照片／文件开始本机 OCR、翻译与屏幕预览的下一步。
- `ImageTranslationPanel` 的空识别结果分支按 idle、载入／识别／翻译、完成和失败动态读出阶段、结果缺失与恢复边界；失败时仅在既有 `canRetryImageTranslation` 可用时说明重试当前图片。
- 新增 `scripts/test-v3133-image-empty-result-accessibility-context-contract.py` 并接入 UI/full fail-fast；改动只属于 View，不新增 Store／持久化，不改变 OCR、翻译、renderer/export、探针报告、Koharu active gate、metrics 或 `output`。

边界：候选、PR、merge 使用 `probe_mode=skip`，没有新的 OCR／翻译／Koharu 指标，也没有更新 `metrics/version_history.csv` 或仓库 `output/`。真实 `test/koharu_artifacts/` 四件套、Speech corpus 与真实竖排图片 corpus 仍缺失，readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不得据此声称 OCR、翻译、识别或 Koharu 质量提升。

云端证据：

- 候选 exact-SHA full [31140850232](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31140850232)：`validationReason=manual_full`，commit `a1bc1ba4a73d4337e83c2a99f911ce3f709dc207`，Xcode build success，UI／Speech／home／paste 合同 success，JUnit `10/10` 且 0 failures，`probe_mode=skip`；active Koharu validator 为 `manifestMissing / stopUntilArtifactsProvided`。
- PR #197 fast [31141276534](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31141276534)：`validationProfile=fast`，复用候选 full `a1bc1ba4a73d4337e83c2a99f911ce3f709dc207 / success`，Xcode skipped，JUnit `10/10`；不是新的编译证据。
- merge fast [31141320676](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31141320676)：merge SHA `30678f089d5764b06bdf2d459c55ba2677d872cb`，`validationReason=merge_reuses_successful_candidate_full_validation`、`receiptPropagationAllowed=true`，复用候选 full，Xcode skipped，JUnit `10/10`；不是新的编译证据。
- 文档 metadata follow-up [31141581510](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31141581510)：commit `9116888536cb3f4e2fe2e7e255bb7bf18e7110fd`，`validationReason=smalldata_metadata_followup_reuses_parent_full_validation`，复用父 merge `30678f089d5764b06bdf2d459c55ba2677d872cb / success`，`receiptPropagationAllowed=true`，Xcode/UI/Speech skipped，JUnit `10/10`；不是新的编译证据。

## v3.132：图片已忽略文字块空态 action

日期：2026-08-07

状态：Agent X 已完成 v3.132 普通图片 OCR 全部文字块被忽略时的可操作空态、候选 exact-SHA full、PR fast、merge fast 云端验收并合入 `smalldata_test`；工程正式版本为 `MARKETING_VERSION=3.132`。候选 commit `012f25ffd7edc4009b33c600bb57d0d6d65005c2` 已通过 PR [#196](https://github.com/bengzhu/project1_lgbt_naxida/pull/196) 合入，merge SHA `df3f7ecbf59319a0c59d13164bb6b0f9cd8ab553`；候选远端分支已清理，`main` 未触碰。

核心变更：

- 当普通图片的所有 OCR 文字块都被忽略时，空态成为稳定 VoiceOver 上下文，读出忽略数量、原始导出与恢复边界，并提供同名“恢复全部”action。
- 同一全忽略状态只显示一个可见 `恢复全部 N` 按钮，继续受 `canModifyImageTranslation` 与导出重绘门控；部分忽略状态保留下方批量恢复入口，避免重复按钮。
- 最后一个 block 被忽略后，sheet 收起后的 View 私有焦点交给空态；translated 终态、有效图片数据与 ignored snapshots 同样把焦点保留在空态；不新增 Store／持久化字段，不改变 OCR、翻译、renderer/export、探针、metrics 或 `output`。
- 新增 `scripts/test-v3132-image-ignored-empty-state-action-contract.py`；历史 v3.330/v3.333/v3.335 合同放宽为至少两个合法焦点目的地，同时继续锁定原有 row/completion handoff。

边界：候选、PR、merge 使用 `probe_mode=skip`，没有新的 OCR／翻译／Koharu 指标，也没有更新 `metrics/version_history.csv` 或仓库 `output/`。真实 `test/koharu_artifacts/` 四件套、Speech corpus 与真实竖排图片 corpus 仍缺失，readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不得据此声称 OCR、翻译、识别或 Koharu 质量提升。

云端证据：

- 候选 exact-SHA full [31139110055](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31139110055)：commit `012f25ffd7edc4009b33c600bb57d0d6d65005c2`，`validationReason=manual_full`，Xcode build success，UI／Speech 合同 success，JUnit `10/10` 且 0 failures，`probe_mode=skip`；active Koharu validator 为 `manifestMissing / stopUntilArtifactsProvided`。
- PR #196 fast [31139576598](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31139576598)：`validationProfile=fast`，复用候选 full `012f25ffd7edc4009b33c600bb57d0d6d65005c2 / success`，Xcode skipped，JUnit `10/10`；不是新的编译证据。
- merge fast [31139633331](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31139633331)：merge SHA `df3f7ecbf59319a0c59d13164bb6b0f9cd8ab553`，`validationReason=merge_reuses_successful_candidate_full_validation`、`receiptPropagationAllowed=true`，复用候选 full，Xcode skipped，JUnit `10/10`；不是新的编译证据。
- 文档 metadata follow-up [31140034700](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31140034700)：commit `5e4c1dda348f174b22ffd0d3d412fa140a690bcb`，`smalldataIncrementalMetadataOnly=true`，`validationReason=smalldata_metadata_followup_reuses_parent_full_validation`，复用父 merge `df3f7ecbf59319a0c59d13164bb6b0f9cd8ab553 / success`，`receiptPropagationAllowed=true`，Xcode/UI/Speech skipped，JUnit `10/10`；不是新的编译证据。

## v3.131：图片已忽略文字块批量恢复

日期：2026-08-07

状态：Agent X 已完成 v3.131 普通图片已忽略文字块批量恢复入口、候选 full、PR fast、merge fast 云端验收并合入 `smalldata_test`；工程正式版本为 `MARKETING_VERSION=3.131`。候选 commit `26fc6bba61c277747673f9fb29e4a6e1eb849aaf` 已通过 PR [#195](https://github.com/bengzhu/project1_lgbt_naxida/pull/195) 合入，merge SHA `8514924340486fd86344298f3b9493540fe9ab4c`；候选远端分支已清理，`main` 未触碰。

核心变更：

- 普通图片 OCR 的“已忽略文字块”区域提供带确认的可见“恢复全部 N”操作，用户不必逐行恢复。
- Store 按 `originalOrder` 一次性恢复忽略快照，保留人工修正与 Vision OCR 元数据，清除恢复块的复查完成状态，只同步一次转录并作废／重建导出；View 受 `.translated` 与导出重绘门控，revision 变化会关闭 stale confirmation，确认后把 VoiceOver 焦点交给首个恢复结果行。
- 新增 `scripts/test-v3131-image-ignored-blocks-bulk-restore-contract.py` 并接入 UI/full fail-fast；不新增持久化字段，不重新运行 OCR／翻译，不读取探针或 ground truth。

边界：候选、PR、merge 使用 `probe_mode=skip`，没有新的 OCR／翻译／Koharu 指标，也没有更新 `metrics/version_history.csv` 或仓库 `output/`。真实 `test/koharu_artifacts/` 四件套、Speech corpus 与真实竖排图片 corpus 仍缺失，readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不得据此声称 OCR、翻译、识别或 Koharu 质量提升。

云端证据：

- 候选自动 full [31090174114](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31090174114)：候选 SHA `26fc6bba61c277747673f9fb29e4a6e1eb849aaf`，`validationProfile=full`，Xcode build success，相关静态／Speech／UI 合同与 JUnit `10/10` 通过，`probe_mode=skip`。
- 候选 exact-SHA full [31090186819](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31090186819)：`validationReason=manual_full`、exact SHA 一致，Xcode build success，UI／Speech 合同 success，JUnit `10/10` 且 0 failures；active Koharu validator 为 `manifestMissing / stopUntilArtifactsProvided`。
- PR #195 fast [31137606603](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31137606603)：`validationProfile=fast`，复用候选 full `26fc6bba61c277747673f9fb29e4a6e1eb849aaf / success`，Xcode skipped，JUnit `10/10`；不是新的编译证据。
- merge fast [31137651196](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31137651196)：merge SHA `8514924340486fd86344298f3b9493540fe9ab4c`，`validationReason=merge_reuses_successful_candidate_full_validation`、`receiptPropagationAllowed=true`，复用候选 full，Xcode skipped，JUnit `10/10`；不是新的编译证据。
- 文档 metadata follow-up [31137895984](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31137895984)：commit `4c5c2615a37e1846c2a19389135b0e3c2379ffca`，`smalldataIncrementalMetadataOnly=true`，`validationReason=smalldata_metadata_followup_reuses_parent_full_validation`，复用父 merge `8514924340486fd86344298f3b9493540fe9ab4c / success`，`receiptPropagationAllowed=true`，Xcode/UI/Speech skipped，JUnit `10/10`；不是新的编译证据。

## v3.130：漫画诊断筛选空态恢复 action

日期：2026-08-06

状态：Agent X 已完成 v3.130 Developer Console 漫画诊断筛选空态恢复入口、候选 full、PR fast、merge fast 云端验收并合入 `smalldata_test`；工程正式版本为 `MARKETING_VERSION=3.130`。候选 commit `f3965b43c38b7682decec9aaf46d046cafc3f16f` 已通过 PR [#194](https://github.com/bengzhu/project1_lgbt_naxida/pull/194) 合入，merge SHA `ed719558db8edca6aff02124517fb0035bc3c458`；候选远端分支已清理，`main` 未触碰。

核心变更：

- Developer Console 漫画探针已有逐块报告但当前诊断筛选没有结果时，空态现在同时提供可见“显示全部诊断”按钮与同名 VoiceOver action，用户无需回到上方筛选器即可恢复逐块结果。
- 恢复操作只改 View 私有 `diagnosticFilter` 为 `.all`，复用既有筛选变化的展开重置、首项聚焦和 generation 仲裁；不写 Store／持久化，不重新运行探针，不读取 ground truth。
- `mangaOverlayProbeBlocks.isEmpty` 的“本次探针未生成文字块”空态保持独立，避免把本轮没有结果误读为筛选造成的空结果；新增 `scripts/test-v3130-manga-diagnostic-filter-empty-action-contract.py` 并接入 UI/full fail-fast。

边界：候选、PR、merge 使用 `probe_mode=skip`，没有新的 OCR／翻译／Koharu 指标，也没有更新 `metrics/version_history.csv` 或仓库 `output/`。真实 `test/koharu_artifacts/` 四件套、Speech corpus 与真实竖排图片 corpus 仍缺失，readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不得据此声称 OCR、翻译、识别或 Koharu 质量提升。

云端证据：

- 候选 push full [31088751113](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31088751113)：提交 SHA `f3965b43c38b7682decec9aaf46d046cafc3f16f`，Xcode build success，静态／Speech／UI／home／paste 合同 success，JUnit `10/10`，`probe_mode=skip`。
- 候选 exact-SHA full [31088767018](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31088767018)：`validationReason=manual_full`、exact SHA 一致，Xcode build success，静态／Speech／UI／home／paste 合同 success，JUnit `10/10` 且 0 failures；active Koharu validator 为 `manifestMissing / stopUntilArtifactsProvided`。
- PR #194 fast [31089351045](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31089351045)：`validationProfile=fast`，复用候选 full `f3965b43c38b7682decec9aaf46d046cafc3f16f / success`，Xcode skipped，JUnit `10/10`；不是新的编译证据。
- merge fast [31089424245](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31089424245)：merge SHA `ed719558db8edca6aff02124517fb0035bc3c458`，`validationReason=merge_reuses_successful_candidate_full_validation`、`receiptPropagationAllowed=true`，复用候选 full，Xcode skipped，JUnit `10/10`；不是新的编译证据。
- 文档 metadata follow-up [31089635112](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31089635112)：commit `ce1e27db4072a5e95a7305fbc131f5192f1a38d9`，`validationReason=smalldata_metadata_followup_reuses_parent_full_validation`，复用父 merge `ed719558db8edca6aff02124517fb0035bc3c458 / success`，`receiptPropagationAllowed=true`，Xcode skipped，JUnit `10/10`；不是新的编译证据。

## v3.129：图片复查筛选空态恢复 action

日期：2026-08-06

状态：Agent X 已完成 v3.129 普通图片 OCR 筛选空态恢复入口、候选 full、PR fast、merge fast 云端验收并合入 `smalldata_test`；工程正式版本为 `MARKETING_VERSION=3.129`。候选 commit `b4617eacf4ff4ef0c7ccce847fe3742ff7002861` 已通过 PR [#193](https://github.com/bengzhu/project1_lgbt_naxida/pull/193) 合入，merge SHA `5b2792d065fcb83ec10ccb4c2b55cb5ddab84bc8`；候选远端分支已清理，`main` 未触碰。

核心变更：

- 普通图片的低置信、方向待定和待复查筛选在没有结果时，空态现在同时提供可见“显示全部结果”按钮和同名 VoiceOver action；用户无需返回分段筛选器即可恢复完整文字块列表。
- 恢复操作只复用既有 View 私有 `showAllReviewResults()` 与 `prepareReviewFilterChange(to: .all, focusID: nil)`，沿用既有筛选变化、隐藏选择清理和结果焦点 handoff，不写 Store／持久化，不重新运行 OCR／翻译。
- 新增 `scripts/test-v3129-image-review-filter-empty-action-contract.py`，并把 v3.129 接入 UI/full fail-fast；历史 v3.107 空态 hint 合同保持兼容。

边界：候选、PR、merge 使用 `probe_mode=skip`，没有新的 OCR／翻译／Koharu 指标，也没有更新 `metrics/version_history.csv` 或仓库 `output/`。真实 `test/koharu_artifacts/` 四件套、Speech corpus 与真实竖排图片 corpus 仍缺失，readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不得据此声称 OCR、翻译、识别或 Koharu 质量提升。

云端证据：

- 候选 push full [31087455725](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31087455725)：提交 SHA `b4617eacf4ff4ef0c7ccce847fe3742ff7002861`，Xcode build success，静态／Speech／UI／home／paste 合同 success，JUnit `10/10`，`probe_mode=skip`。
- 候选 exact-SHA full [31087461275](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31087461275)：`validationReason=manual_full`、exact SHA 一致，Xcode build success，静态／Speech／UI／home／paste 合同 success，JUnit `10/10` 且 0 failures；active Koharu validator 为 `manifestMissing / stopUntilArtifactsProvided`。
- PR #193 fast [31088057693](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31088057693)：`validationProfile=fast`，复用候选 full `b4617eacf4ff4ef0c7ccce847fe3742ff7002861 / success`，Xcode skipped，JUnit `10/10`；不是新的编译证据。
- merge fast [31088114103](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31088114103)：merge SHA `5b2792d065fcb83ec10ccb4c2b55cb5ddab84bc8`，`validationReason=merge_reuses_successful_candidate_full_validation`、`receiptPropagationAllowed=true`，复用候选 full，Xcode skipped，JUnit `10/10`；不是新的编译证据。
- 文档 metadata follow-up [31088311295](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31088311295)：commit `a7d43ef66b8492cc9c49c0fe330199535e5608fc`，`validationReason=smalldata_metadata_followup_reuses_parent_full_validation`，复用父 merge `5b2792d065fcb83ec10ccb4c2b55cb5ddab84bc8 / success`，`receiptPropagationAllowed=true`，Xcode skipped，JUnit `10/10`；不是新的编译证据。

## v3.128：图片复查完成态可操作 VoiceOver 上下文

日期：2026-08-06

状态：Agent X 已完成 v3.128 普通图片复查完成空态的 VoiceOver action、候选 full、PR fast、merge fast 云端验收并合入 `smalldata_test`；工程正式版本为 `MARKETING_VERSION=3.128`。候选 commit `d31745f8461ec6eeee0e8ce75e5965874a10b7b7` 已通过 PR [#192](https://github.com/bengzhu/project1_lgbt_naxida/pull/192) 合入，merge SHA `14a11feff4413058f5c02348ce5d16485044702f`；候选远端分支已清理，`main` 未触碰。

核心变更：

- 当图片筛选处于“待复查”且本次已完成至少一个风险块时，完成空态成为单一、稳定的 VoiceOver 上下文，读出已完成数量、总风险块数量和当前筛选，避免只听到静态标题而缺少进度闭环。
- 完成空态提供直接“重新复查”无障碍 action，复用既有 `restartReviewQueue()`；操作仍受 `canReviewImageTranslation` 保护，未改变 Store、复查进度、OCR、翻译或 renderer/export 业务路径。
- 新增 `scripts/test-v3128-image-review-completion-action-contract.py`，验证稳定 focus identity、label/value/hint、action 和既有状态门；CI 路由接入 UI/full fail-fast。

边界：候选、PR、merge 使用 `probe_mode=skip`，没有新的 OCR／翻译／Koharu 指标，也没有更新 `metrics/version_history.csv` 或仓库 `output/`。真实 `test/koharu_artifacts/` 四件套、Speech corpus 与真实竖排图片 corpus 仍缺失，readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不得据此声称 OCR、翻译、识别或 Koharu 质量提升。

云端证据：

- 候选 push full [31085386019](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31085386019)：提交 SHA `d31745f8461ec6eeee0e8ce75e5965874a10b7b7`，Xcode build success，静态／Speech／UI／home／paste 合同 success，JUnit `10/10`，`probe_mode=skip`。
- 候选 exact-SHA full [31085406753](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31085406753)：`validationReason=manual_full`、exact SHA 一致，Xcode build success，静态／Speech／UI／home／paste 合同 success，JUnit `10/10` 且 0 failures；active Koharu validator 为 `manifestMissing / stopUntilArtifactsProvided`。
- PR #192 fast [31085987796](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31085987796)：`validationProfile=fast`，复用候选 full `d31745f8461ec6eeee0e8ce75e5965874a10b7b7 / success`，Xcode skipped，JUnit `10/10`；不是新的编译证据。
- merge fast [31086053876](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31086053876)：merge SHA `14a11feff4413058f5c02348ce5d16485044702f`，`validationReason=merge_reuses_successful_candidate_full_validation`、`receiptPropagationAllowed=true`，复用候选 full，Xcode skipped，JUnit `10/10`；不是新的编译证据。
- 文档 metadata follow-up [31086468069](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31086468069)：commit `367cb70545d130714d7c9ac494bf106ab7902667`，`validationReason=smalldata_metadata_followup_reuses_parent_full_validation`，复用父 merge `14a11feff4413058f5c02348ce5d16485044702f / success`，`receiptPropagationAllowed=true`，Xcode skipped，JUnit `10/10`；不是新的编译证据。

## v3.127：图片失败状态直接 retry action

日期：2026-08-06

状态：Agent X 已完成 v3.127 普通图片失败状态行直接 VoiceOver retry action、候选 full、PR fast、merge fast 云端验收并合入 `smalldata_test`；工程正式版本为 `MARKETING_VERSION=3.127`。候选 commit `a7ef8ce984234bf4631f206186f70bbec3ff2b64` 已通过 PR [#191](https://github.com/bengzhu/project1_lgbt_naxida/pull/191) 合入，merge SHA `03d5b82b97c102043a0c262775061401cc38ac8a`；候选远端分支已清理，`main` 未触碰。

核心变更：

- `ImageTranslationPanel` 的图片状态行按现有显示优先级提供 direct action：分享准备 `.failed` 时提供“重试分享”，导出重绘 `.failed` 时提供“重试导出”，两者都没有失败时才提供既有“重试当前图片”。这样 VoiceOver 用户无需回到命令栏即可从当前失败上下文恢复操作。
- 分享 action 复用既有 `shareResult()`；导出 action 复用 `store.retryImageTranslationExportRender()`。状态 helper、优先级和 hint 均为 View 私有，不新增 Store／持久化，不改变 OCR、翻译、renderer/export、探针报告或 Koharu active gate。
- 新增 `scripts/test-v3127-image-failure-status-actions-contract.py`；v3.127 合同接入 UI/full fail-fast，CI 路由保持在 GitHub Actions 表达式长度限制内。

边界：候选、PR、merge 使用 `probe_mode=skip`，没有新的 OCR／翻译／Koharu 指标，也没有更新 `metrics/version_history.csv` 或仓库 `output/`。真实 `test/koharu_artifacts/` 四件套、Speech corpus 与真实竖排图片 corpus 仍缺失，readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不得据此声称 OCR、翻译、识别或 Koharu 质量提升。

云端证据：

- 候选 push full [31084259880](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31084259880)：提交 SHA `a7ef8ce984234bf4631f206186f70bbec3ff2b64`，`validationProfile=full`、Xcode build success，静态／Speech／UI／home／paste 合同 success，JUnit `10/10` 且 0 failures，`probe_mode=skip`。
- 候选 exact-SHA full [31084281958](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31084281958)：`validationProfile=full`、`validationReason=manual_full`，exact SHA 与候选一致，Xcode build success，静态／Speech／UI／home／paste 合同 success，JUnit `10/10`，probe skip；active Koharu validator 明确为 `manifestMissing / stopUntilArtifactsProvided`。
- PR #191 fast [31084713250](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31084713250)：exact head SHA，`validationProfile=fast`，复用候选 full `a7ef8ce984234bf4631f206186f70bbec3ff2b64 / success`，Xcode skipped，JUnit `10/10`；不是新的编译证据。
- merge fast [31084803922](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31084803922)：merge SHA `03d5b82b97c102043a0c262775061401cc38ac8a`，`validationReason=merge_reuses_successful_candidate_full_validation`、`receiptPropagationAllowed=true`，复用候选 full / `success`，Xcode skipped，JUnit `10/10`；不是新的编译证据。
- 文档 metadata follow-up [31085005992](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31085005992)：commit `d1275b606f277fc6677615c9dda462501a05f306`，`validationReason=smalldata_metadata_followup_reuses_parent_full_validation`，复用父 merge `03d5b82b97c102043a0c262775061401cc38ac8a / success`，`receiptPropagationAllowed=true`，Xcode skipped，JUnit `10/10`；不是新的编译证据。

## v3.126：图片导出／分享失败后的状态焦点

日期：2026-08-06

状态：Agent X 已完成 v3.126 普通图片导出重绘／分享失败后的 VoiceOver 焦点修复、候选 full、PR fast、merge fast 云端验收并合入 `smalldata_test`；工程正式版本为 `MARKETING_VERSION=3.126`。候选 commit `244f97435d340207c7684c3a2ab553b552b3b780` 已通过 PR [#190](https://github.com/bengzhu/project1_lgbt_naxida/pull/190) 合入，merge SHA `e023e9c016c64a65596fe70151ad6f6a2d6615d9`；候选远端分支已清理，`main` 未触碰。

核心变更：

- `ImageTranslationPanel` 继续复用既有 `imageTranslationStatusAccessibilityFocusID` 与 `moveReviewAccessibilityFocus`；当 `imageTranslationShareState` 或 `imageTranslationExportRenderState` 从运行中状态变化到 `.failed` 时，把 VoiceOver 焦点交给图片翻译状态行，用户会立即听到分享／导出失败详情与既有重试边界。
- 仅对实际的 `.failed` transition 执行 handoff；`.preparing`／`.rendering` 等运行中状态不抢焦点。焦点、old/new 状态比较与 generation 仍是 View 私有状态，不新增 Store／持久化，不改变 OCR、翻译、renderer/export、探针报告或 Koharu active gate。
- 新增 `scripts/test-v3126-image-export-share-failure-focus-contract.py`；同时将 v3.126 合同接入 UI/full fail-fast，并保持 CI 路由在 GitHub Actions 表达式长度限制内。

边界：候选、PR、merge 使用 `probe_mode=skip`，没有新的 OCR／翻译／Koharu 指标，也没有更新 `metrics/version_history.csv` 或仓库 `output/`。真实 `test/koharu_artifacts/` 四件套、Speech corpus 与真实竖排图片 corpus 仍缺失，readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不得据此声称 OCR、翻译、识别或 Koharu 质量提升。

云端证据：

- 候选 push full [31082859426](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31082859426)：提交 SHA `244f97435d340207c7684c3a2ab553b552b3b780`，`validationProfile=full`、Xcode build success，静态／Speech／UI／home／paste 合同 success，JUnit `10/10` 且 0 failures，`probe_mode=skip`；该 run 也验证了 v3.126 CI 路由调整。
- 候选 exact-SHA full [31082994159](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31082994159)：`validationProfile=full`、`validationReason=manual_full`，exact SHA 与候选一致，Xcode build success，静态／Speech／UI／home／paste 合同 success，JUnit `10/10`，probe skip；active Koharu validator 明确为 `manifestMissing / stopUntilArtifactsProvided`。
- PR #190 fast [31083400009](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31083400009)：exact head SHA，`validationProfile=fast`，复用候选 full `244f97435d340207c7684c3a2ab553b552b3b780 / success`，Xcode skipped，JUnit `10/10`；不是新的编译证据。
- merge fast [31083557316](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31083557316)：merge SHA `e023e9c016c64a65596fe70151ad6f6a2d6615d9`，`validationReason=merge_reuses_successful_candidate_full_validation`、`receiptPropagationAllowed=true`，复用候选 full / `success`，Xcode skipped，JUnit `10/10`；不是新的编译证据。
- 文档 metadata follow-up [31083836291](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31083836291)：commit `9c3a974b6f2b3836c701ae750fc5df98c3a5c5db`，`validationReason=smalldata_metadata_followup_reuses_parent_full_validation`，复用父 merge `e023e9c016c64a65596fe70151ad6f6a2d6615d9 / success`，`receiptPropagationAllowed=true`，Xcode skipped，JUnit `10/10`；不是新的编译证据。

## v3.125：图片直接失败后的状态焦点

日期：2026-08-06

状态：Agent X 已完成 v3.125 普通图片导入／Pro 门控等直接失败状态的 VoiceOver 焦点修复、候选 full、PR fast、merge fast 云端验收并合入 `smalldata_test`；工程正式版本为 `MARKETING_VERSION=3.125`。候选 commit `1c068d538728a1195fdd08197f16f7e82d06dd4b` 已通过 PR [#189](https://github.com/bengzhu/project1_lgbt_naxida/pull/189) 合入，merge SHA `9bd54490d09573d351c1e09da148393c3036a20`；候选远端分支按合入流程清理，`main` 未触碰。

核心变更：

- `ImageTranslationPanel` 的图片状态监听保留 revision-scoped 终态请求；当状态进入 `.failed` 但没有当前 `imageTranslationRevision` 对应的 pending 终态焦点时，清除 stale pending revision，并通过既有 `moveReviewAccessibilityFocus` 聚焦稳定的“图片翻译状态”行。
- 文件选择失败、Pro／目标语言门控等直接失败路径可以不创建新 revision，VoiceOver 现在会立即读出失败详情与“重试当前图片／选择新图片”边界；正常读取／Vision OCR／逐块翻译 revision 失败仍沿用 `focusImageTranslationTerminalStateIfNeeded()`，不会被 fallback 重复抢焦点。
- 新增 `scripts/test-v3125-image-direct-failure-focus-contract.py` 并接入 UI/full fail-fast。该 View-only 改动不新增 Store／持久化，不改变 OCR、翻译、renderer/export、探针报告、Koharu active gate、metrics 或 `output`。

边界：候选、PR、merge 使用 `probe_mode=skip`，没有新的 OCR／翻译／Koharu 指标，也没有更新 `metrics/version_history.csv` 或仓库 `output/`。真实 `test/koharu_artifacts/` 四件套、Speech corpus 与真实竖排图片 corpus 仍缺失，readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不得据此声称 OCR、翻译、识别或 Koharu 质量提升。

云端证据：

- 候选 push full [31081494834](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31081494834)：exact SHA `1c068d538728a1195fdd08197f16f7e82d06dd4b`，`validationProfile=full`、`validationReason=candidate_development_push`，Xcode build success，静态/Speech/UI/home/paste 合同 success，JUnit `10/10` 且 0 failures、0 errors/warnings，`probe_mode=skip`；manifest 为 v3.125，active Koharu validator 记录 `manifestMissing / stopUntilArtifactsProvided`。
- PR #189 fast [31081976028](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31081976028)：exact head SHA，`validationProfile=fast`，复用候选 full `1c068d538728a1195fdd08197f16f7e82d06dd4b / success`，Xcode skipped，JUnit `10/10`；不是新的编译证据。
- merge fast [31082019649](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31082019649)：merge SHA `9bd54490d09573d351c1e09da148393c3036a20`，`validationReason=merge_reuses_successful_candidate_full_validation`，`receiptPropagationAllowed=true`，复用候选 full / `success`，Xcode skipped，JUnit `10/10`；不是新的编译证据。
- 文档 metadata follow-up [31082331067](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31082331067)：commit `954c74e6ea1a27339677a636fd9ebccd90fcd0d2`，`smalldataIncrementalMetadataOnly=true`，`validationReason=smalldata_metadata_followup_reuses_parent_full_validation`，复用父 merge `9bd54490d09573d351c1e09da148393c3036a20 / success`，`receiptPropagationAllowed=true`，Xcode skipped，JUnit `10/10`；不是新的编译证据。

## v3.124：图片清空后的空态焦点

日期：2026-08-06

状态：Agent X 已完成 v3.124 普通图片清空后的 VoiceOver 空态焦点修复、候选 full、PR fast、merge fast 云端验收并合入 `smalldata_test`；工程正式版本为 `MARKETING_VERSION=3.124`。候选 commit `e02b7a6d2c0f41098eb2cf82e6aa97f9b40c1ff9` 已通过 PR [#188](https://github.com/bengzhu/project1_lgbt_naxida/pull/188) 合入，merge SHA `738f82384e027058ae0e53cad5f7842ce92a010f`；候选远端分支已清理，`main` 未触碰。

核心变更：

- `ImageTranslationPanel` 在 `imageTranslationRevision` 变化时保留既有筛选／选择／焦点清理；仅当新状态确认为 `imageTranslationData == nil` 且 `imageTranslationState == .idle`（清空路径）时，才通过既有 `moveReviewAccessibilityFocus` 聚焦稳定的 `imageEmptyAccessibilityFocusID = "image-empty-state"`。
- “等待图片”空态成为单一 VoiceOver 上下文，读出“当前没有图片”，并提示从上方照片或文件按钮开始本机 OCR 与翻译。新图片进入 loading、recognizing 或 translating 时不触发该空态焦点，避免清空与换图操作竞态。
- 新增 `scripts/test-v3124-image-clear-empty-focus-contract.py` 并接入 UI/full fail-fast。该 View-only 改动不新增 Store／持久化，不改变 OCR、翻译、renderer/export、探针报告、Koharu active gate、metrics 或 `output`。

边界：候选、PR、merge 使用 `probe_mode=skip`，没有新的 OCR／翻译／Koharu 指标，也没有更新 `metrics/version_history.csv` 或仓库 `output/`。真实 `test/koharu_artifacts/` 四件套、Speech corpus 与真实竖排图片 corpus 仍缺失，readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不得据此声称 OCR、翻译、识别或 Koharu 质量提升。

云端证据：

- 候选 push full [31080208334](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31080208334)：exact SHA `e02b7a6d2c0f41098eb2cf82e6aa97f9b40c1ff9`，`validationProfile=full`、`validationReason=candidate_development_push`，Xcode build success，静态/Speech/UI/home/paste 合同 success，JUnit `10/10` 且 0 failures，`probe_mode=skip`；manifest 为 v3.124，active Koharu validator 记录 `manifestMissing / stopUntilArtifactsProvided`。
- PR #188 fast [31080768687](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31080768687)：exact head SHA，`validationProfile=fast`，复用候选 full `e02b7a6d2c0f41098eb2cf82e6aa97f9b40c1ff9 / success`，Xcode skipped，JUnit `10/10`；不是新的编译证据。
- merge fast [31080830286](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31080830286)：merge SHA `738f82384e027058ae0e53cad5f7842ce92a010f`，`validationReason=merge_reuses_successful_candidate_full_validation`，`receiptPropagationAllowed=true`，复用候选 full / `success`，Xcode skipped，JUnit `10/10`；不是新的编译证据。
- 文档 metadata follow-up [31080984681](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31080984681)：commit `558df76e3f409bd3e97b2007fc601a7da7624d07`，`smaldataIncrementalMetadataOnly=true`，`validationReason=smalldata_metadata_followup_reuses_parent_full_validation`，复用父 merge `738f82384e027058ae0e53cad5f7842ce92a010f / success`，`receiptPropagationAllowed=true`，Xcode skipped，JUnit `10/10`；不是新的编译证据。

## v3.123：图片屏幕预览失败／重试后的状态焦点

日期：2026-08-06

状态：Agent X 已完成 v3.123 普通图片屏幕预览失败／重试后的 VoiceOver 焦点连续性修复、候选 full、PR fast、merge fast 云端验收并合入 `smalldata_test`；工程正式版本为 `MARKETING_VERSION=3.123`。候选最终 commit `92e68b60e74dd61fb471584bba9cf00bf1696868` 已通过 PR [#187](https://github.com/bengzhu/project1_lgbt_naxida/pull/187) 合入，merge SHA `6309370bc47974964a2aa181075469fb29e928e7`；候选远端分支已清理，`main` 未触碰。

核心变更：

- `ImageTranslationPanel` 为屏幕预览状态提供稳定的 `imagePreviewStatusAccessibilityFocusID`，将既有 `moveReviewAccessibilityFocus` 封装为 View 私有 `focusPreviewStatus` closure 传给 `ImageTranslationPreview`；状态容器使用 `.accessibilityFocused`，保持预览状态 label/value/hint 的单一上下文。
- 预览生成失败时，在 revision 与 Task cancellation guard 通过后立即调用 `focusPreviewStatus()`；点击“重试预览”进入 loading 并递增 attempt 后同样回到状态行，VoiceOver 用户会连续听到失败详情、重试加载和“只重建屏幕预览”的边界。该 handoff 不新增 Store／持久化，不改变 OCR、翻译、renderer/export、probe_report 或 Koharu active gate。
- 新增 `scripts/test-v3123-image-preview-status-focus-contract.py` 并接入 UI/full fail-fast；CI 路由将 v3.122/v3.123 纳入既有正则，并保留顶层兼容标记以避开 GitHub Actions 表达式长度上限。

边界：候选、PR、merge 使用 `probe_mode=skip`，没有新的 OCR／翻译／Koharu 指标，也没有更新 `metrics/version_history.csv` 或仓库 `output/`。真实 `test/koharu_artifacts/` 四件套、Speech corpus 与真实竖排图片 corpus 仍缺失，readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不得据此声称 OCR、翻译、识别或 Koharu 质量提升。

云端证据：

- 候选 push full [31079060685](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31079060685)：exact SHA `92e68b60e74dd61fb471584bba9cf00bf1696868`，`validationProfile=full`、`validationReason=candidate_development_push`，Xcode build success，静态/Speech/UI/home/paste 合同 success，JUnit `10/10` 且 0 failures，`probe_mode=skip`；manifest 为 v3.123，active Koharu validator 记录 `manifestMissing / stopUntilArtifactsProvided`。
- PR #187 fast [31079520917](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31079520917)：exact head SHA，`validationProfile=fast`，复用候选 full `92e68b60e74dd61fb471584bba9cf00bf1696868 / success`，Xcode skipped，JUnit `10/10`；不是新的编译证据。
- merge fast [31079590205](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31079590205)：merge SHA `6309370bc47974964a2aa181075469fb29e928e7`，`validationReason=merge_reuses_successful_candidate_full_validation`，`receiptPropagationAllowed=true`，复用候选 full / `success`，Xcode skipped，JUnit `10/10`；不是新的编译证据。
- 文档 metadata follow-up [31079856722](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31079856722)：commit `9b533ca5cb92153ee15fe997cb837d937720dc7d`，`smaldataIncrementalMetadataOnly=true`，`validationReason=smalldata_metadata_followup_reuses_parent_full_validation`，复用父 merge `6309370bc47974964a2aa181075469fb29e928e7 / success`，`receiptPropagationAllowed=true`，Xcode skipped，JUnit `10/10`；不是新的编译证据。

## v3.122：图片 OCR 取消后的状态焦点

日期：2026-08-06

状态：Agent X 已完成 v3.122 普通图片读取／Vision OCR／逐块翻译取消后的 VoiceOver 焦点修复、候选 full、PR fast、merge fast 云端验收并合入 `smalldata_test`；工程正式版本为 `MARKETING_VERSION=3.122`。候选 commit `9c0ed87838d7eb621fb762c67230df74321f5ab6` 已通过 PR [#186](https://github.com/bengzhu/project1_lgbt_naxida/pull/186) 合入，merge SHA `61401075429df063b7726037b81b91aade9178d3`；候选远端分支已清理，`main` 未触碰。

核心变更：

- `ImageTranslationPanel` 的状态监听现在接收 `oldState`；仅当 `.loading`、`.recognizing` 或 `.translating` 转为 `.idle` 时，清除尚未完成的终态焦点 revision，并通过既有 `moveReviewAccessibilityFocus` 将 VoiceOver 焦点交给单一“图片翻译状态”行。用户取消图片读取／OCR／翻译后会立即听到“图片翻译已取消”及可重试边界。
- 初始 `.idle`、清空导致的非运行中 `.idle`、`.translated` 与 `.failed` 不抢焦点；原有 revision-scoped 终态 focus、待重试语言 focus 和状态 action 保持不变。焦点、generation 和 pending revision 仍是 View 私有状态。
- 新增 `scripts/test-v3122-image-cancel-status-focus-contract.py` 并接入 changed-file UI/full fail-fast。该 View-only 改动不新增 Store／持久化，不改变 Vision OCR、翻译、renderer/export、探针报告、Koharu active gate、metrics 或 `output`。

边界：候选、PR、merge 使用 `probe_mode=skip`，没有新的 OCR／翻译／Koharu 指标，也没有更新 `metrics/version_history.csv` 或仓库 `output/`。真实 `test/koharu_artifacts/` 四件套、Speech corpus 与真实竖排图片 corpus 仍缺失，readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不得据此声称 OCR、翻译、识别或 Koharu 质量提升。

云端证据：

- 候选 push full [31077891466](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31077891466)：exact SHA `9c0ed87838d7eb621fb762c67230df74321f5ab6`，`validationProfile=full`、`validationReason=candidate_development_push`，Xcode build success，静态/Speech/UI/home/paste 合同 success，JUnit `10/10` 且 0 failures，`probe_mode=skip`；manifest 为 v3.122，active Koharu validator 记录 `manifestMissing / stopUntilArtifactsProvided`。
- PR #186 fast [31078311141](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31078311141)：exact head SHA，`validationProfile=fast`，复用候选 full `9c0ed87838d7eb621fb762c67230df74321f5ab6 / success`，Xcode skipped，JUnit `10/10`；不是新的编译证据。
- merge fast [31078359581](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31078359581)：merge SHA `61401075429df063b7726037b81b91aade9178d3`，`validationReason=merge_reuses_successful_candidate_full_validation`，`receiptPropagationAllowed=true`，复用候选 full / `success`，Xcode skipped，JUnit `10/10`；不是新的编译证据。
- 文档 metadata follow-up [31078512071](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31078512071)：commit `4f50148deaae9b3256739a4d908ce91f3d4da30d`，`smalldataIncrementalMetadataOnly=true`，`validationReason=smalldata_metadata_followup_reuses_parent_full_validation`，复用父 merge `61401075429df063b7726037b81b91aade9178d3 / success`，`receiptPropagationAllowed=true`，Xcode skipped，JUnit `10/10`；不是新的编译证据。

## v3.121：图片 OCR 状态行失败／取消重试 action

日期：2026-08-06

状态：Agent X 已完成 v3.121 普通图片 OCR 失败／取消状态行的 VoiceOver 重试 action、候选 full、PR fast、merge fast 云端验收并合入 `smalldata_test`；工程正式版本为 `MARKETING_VERSION=3.121`。候选 commit `9551c0c53bae0b8816d490a3da03c9472995e859` 已通过 PR [#185](https://github.com/bengzhu/project1_lgbt_naxida/pull/185) 合入，merge SHA `16caff957c0252c2014750cc6c3d56dfa8463c29`；候选远端分支按合入流程清理，`main` 未触碰。

核心变更：

- 失败／取消且没有待重试语言变更、源图片仍可用时，`ImageTranslationPanel` 的单一“图片翻译状态”VoiceOver 元素提供命名为“重试当前图片”的 custom action；action 先复用 `store.canRetryImageTranslation` 与无 pending-language summary 的 View 门控，再调用既有 `store.retryImageTranslation()`。
- 源图片已不存在时，状态 hint 明确要求重新选择图片；已有待重试语言摘要继续保留唯一的语言变更 action，避免状态行出现重复重试入口。原有 label/value/hint/accessibility focus 锚点保持内联，兼容 v3.51/v3.54 历史合同。
- 新增 `scripts/test-v3121-image-status-retry-accessibility-contract.py` 并接入 changed-file UI/full fail-fast 路由。该改动只属于 View 操作语义，不新增 Store／持久化，不改变 OCR、翻译、renderer/export、探针报告或 Koharu active gate。

边界：候选、PR、merge 使用 `probe_mode=skip`，没有新的 OCR／翻译／Koharu 指标，也没有更新 `metrics/version_history.csv` 或仓库 `output/`。真实 `test/koharu_artifacts/` 四件套、Speech corpus 与真实竖排图片 corpus 仍缺失，readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不得据此声称 OCR、翻译、识别或 Koharu 质量提升。

云端证据：

- 候选 push full [31076710802](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31076710802)：exact SHA `9551c0c53bae0b8816d490a3da03c9472995e859`，`validationProfile=full`、`validationReason=manual_full`，Xcode build success，静态/Speech/UI/home/paste 合同 success，JUnit `10/10` 且 0 failures，`probe_mode=skip`；manifest 为 v3.121，readiness validator 记录 `manifestMissing / stopUntilArtifactsProvided`。
- PR #185 fast [31077094866](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31077094866)：exact head SHA，`validationProfile=fast`，复用候选 full `9551c0c53bae0b8816d490a3da03c9472995e859 / success`，Xcode skipped，JUnit `10/10`；不是新的编译证据。
- merge fast [31077152440](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31077152440)：merge SHA `16caff957c0252c2014750cc6c3d56dfa8463c29`，`validationReason=merge_reuses_successful_candidate_full_validation`，`receiptPropagationAllowed=true`，复用候选 full / `success`，Xcode skipped，JUnit `10/10`；不是新的编译证据。
- 文档 metadata follow-up [31077474262](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31077474262)：commit `54cb2762ac05b9017f2d939c954626f85559c8dc`，`smalldataIncrementalMetadataOnly=true`，`validationReason=smalldata_metadata_followup_reuses_parent_full_validation`，复用父 merge `16caff957c0252c2014750cc6c3d56dfa8463c29 / success`，`receiptPropagationAllowed=true`，Xcode skipped，JUnit `10/10`；不是新的编译证据。

## v3.120：图片 OCR 待重试语言可操作焦点

日期：2026-08-06

状态：Agent X 已完成 v3.120 普通图片 OCR 待重试语言状态的 VoiceOver 可操作 action、候选 full、PR fast、merge fast 云端验收并合入 `smalldata_test`；工程正式版本为 `MARKETING_VERSION=3.120`。候选 commit `25855f7e6b757c2ae901c794c56990215399cb68` 已通过 PR [#184](https://github.com/bengzhu/project1_lgbt_naxida/pull/184) 合入，merge SHA `205e78e0f7dd39c51a9c8dbf93748c1a5ef0a090`；候选远端分支已删除，`main` 未触碰。

核心变更：

- v3.119 已将焦点交给“重试语言已更新”状态；本版让该状态提供命名为“重试当前图片”的 VoiceOver custom action，先检查既有 `store.canRetryImageTranslation`，再调用 `store.retryImageTranslation()`，VoiceOver 用户无需再次导航到命令栏即可重试。
- action 复用现有 Store retry 生命周期和 v3.119 的 summary/focus 语义；不可重试时安全无效，不新增 Store／持久化，不改变 Vision OCR、翻译、renderer/export、probe_report 或 Koharu active gate。
- 新增 `scripts/test-v3120-image-retry-language-accessibility-action-contract.py`，接入 UI/full fail-fast，锁定 action 名称、retry guard、既有 Store 调用和版本/CI 路由。

边界：本版只缩短失败／取消图片在待重试语言已更新后的 VoiceOver 操作链，不重新运行 OCR／翻译，不改变 OCR 候选、翻译模型、renderer/export、探针报告、metrics 或仓库 `output/`。候选、PR、merge 默认 `probe_mode=skip`，没有新的 OCR／翻译／Koharu 指标；真实 `test/koharu_artifacts/` 四件套、Speech corpus 与真实竖排图片 corpus 仍缺失，Koharu readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不声称 OCR、翻译、识别或 Koharu 质量提升。

云端证据：

- 候选 push full [31075361390](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31075361390)：exact SHA `25855f7e6b757c2ae901c794c56990215399cb68`，`validationProfile=full`、`validationReason=candidate_development_push`，Xcode build success，静态/Speech/UI/home/paste 合同 success，JUnit `10/10` 且 0 failures，`probe_mode=skip`；manifest 版本 `v3.120`，readiness validator 记录 `manifestMissing / stopUntilArtifactsProvided`。
- PR #184 fast [31075697828](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31075697828)：exact head SHA，`validationProfile=fast`，复用候选 full `25855f7e6b757c2ae901c794c56990215399cb68 / success`，Xcode skipped，JUnit `10/10`；不是新的编译证据。
- merge fast [31075745893](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31075745893)：merge SHA `205e78e0f7dd39c51a9c8dbf93748c1a5ef0a090`，`validationReason=merge_reuses_successful_candidate_full_validation`，`receiptPropagationAllowed=true`，复用候选 full / `success`，Xcode skipped，JUnit `10/10`。
- 文档 metadata follow-up [31075866659](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31075866659)：commit `30bf304cad741ab2cd7a21278a61b41ee9464157`，`smalldataIncrementalMetadataOnly=true`，复用父 merge full `205e78e0f7dd39c51a9c8dbf93748c1a5ef0a090 / success`，Xcode skipped，JUnit `10/10`；不是新的编译证据。

## v3.119：图片 OCR 待重试语言焦点

日期：2026-08-06

状态：Agent X 已完成 v3.119 普通图片 OCR 失败／取消后的待重试语言 VoiceOver 焦点修复、候选 full、PR fast、merge fast 云端验收并合入 `smalldata_test`；工程正式版本为 `MARKETING_VERSION=3.119`。候选 commit `5248bd705fc6c0d963146060917e2a6a94a6c421` 已通过 PR [#183](https://github.com/bengzhu/project1_lgbt_naxida/pull/183) 合入，merge SHA `de5ccebdeda7294a491183c53676e65caaaefb6a`；候选远端分支已删除，`main` 未触碰。

核心变更：

- `ImageTranslationPanel` 在既有 `imageTranslationRetryLanguageSummary` 真实变化后，将 VoiceOver 焦点交给稳定的“重试语言已更新”状态行；label/value/hint 说明当前待重试语言、下一次会重新识别／翻译的范围，未发生真实变化时不抢焦点，也不调用重试。
- 焦点 handoff 复用既有 `moveReviewAccessibilityFocus` 的 request generation 与 `imageTranslationRevision` guard；状态、焦点 identity 和 generation 继续只属于 View，不新增 Store／持久化，不改变 Vision OCR、翻译、renderer/export、probe_report 或 Koharu active gate。
- 新增 `scripts/test-v3119-image-retry-language-focus-contract.py`，接入 UI/full fail-fast，锁定 summary change guard、稳定 accessibility label/value/hint、revision-scoped generation 与 View-only 边界。

边界：本版改善失败／取消后的图片语言选择操作连续性，使用户选语言后立刻知道下一次重试会使用什么语言；不重新运行 OCR／翻译，不改变 OCR 候选、翻译模型、renderer/export、探针报告、metrics 或仓库 `output/`。候选、PR、merge 默认 `probe_mode=skip`，没有新的 OCR／翻译／Koharu 指标；真实 `test/koharu_artifacts/` 四件套、Speech corpus 与真实竖排图片 corpus 仍缺失，Koharu readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不声称 OCR、翻译、识别或 Koharu 质量提升。

云端证据：

- 候选 push full [31074379707](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31074379707)：exact SHA `5248bd705fc6c0d963146060917e2a6a94a6c421`，`validationProfile=full`、`validationReason=candidate_development_push`，Xcode build success，静态/Speech/UI/home/paste 合同 success，JUnit `10/10` 且 0 failures，`probe_mode=skip`；manifest 版本 `v3.119`，readiness validator 诚实记录 `manifestMissing / stopUntilArtifactsProvided`。
- PR #183 fast [31074819588](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31074819588)：exact head SHA，`validationProfile=fast`，复用候选 full `5248bd705fc6c0d963146060917e2a6a94a6c421 / success`，Xcode skipped，JUnit `10/10`；不是新的编译证据。
- merge fast [31074863470](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31074863470)：merge SHA `de5ccebdeda7294a491183c53676e65caaaefb6a`，`validationReason=merge_reuses_successful_candidate_full_validation`，`receiptPropagationAllowed=true`，复用候选 full / `success`，Xcode skipped，JUnit `10/10`。
- 文档 metadata follow-up [31075058218](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31075058218)：commit `ff3e8fcae44b51e6724ab53cb770cbacf18d5a8c`，`smalldataIncrementalMetadataOnly=true`，复用父 merge full `de5ccebdeda7294a491183c53676e65caaaefb6a / success`，Xcode skipped，JUnit `10/10`；不是新的编译证据。

## v3.118：漫画探针阻断 Koharu readiness 焦点

日期：2026-08-06

状态：Agent X 已完成 v3.118 Developer Console 漫画探针报告到达后的 readiness VoiceOver 焦点优先级修复、历史合同兼容、候选 full、PR fast、merge fast 云端验收并合入 `smalldata_test`；工程正式版本为 `MARKETING_VERSION=3.118`。候选最终 commit `067077bcb146e2e0c8bb2e066350cac2466b7460` 已通过 PR [#182](https://github.com/bengzhu/project1_lgbt_naxida/pull/182) 合入，merge SHA `036bada7aebd70da50d6d31cc4e4da2cce4b8dda`；候选远端分支已删除，`main` 未触碰。

核心变更：

- `MangaProbeSection` 在报告终态发现既有 `externalArtifactReadinessReport` 的 `nextAction` 为 `stopUntilArtifactsProvided`、`stopUntilArtifactContractFixed` 或 `stopUntilRealDetectorSourceDeclared` 时，优先把同一 generation requester 的焦点交给稳定 `diagnosticKoharuReadinessAccessibilityFocusID`；非阻断 readiness 仍按当前筛选首 block、筛选空态或未生成逐块状态处理。
- `MangaKoharuArtifactReadinessSummary` 只接收父级现有 `@AccessibilityFocusState` binding 和 View identity，并在状态行上复用既有 readiness label/value/hint；筛选变化仍回到逐块结果，loading 仍使旧请求失效。
- 新增 `scripts/test-v3118-manga-koharu-readiness-focus-contract.py` 并接入 UI/full fail-fast；v3.336 历史合同放宽为验证同一 initializer 与 `readiness: readiness` 参数的等价多行写法。

边界：本版只改善阻断 readiness 的开发者 VoiceOver 操作顺序，仍只读既有漫画探针报告，不新增 Store／持久化、不重跑探针、不读取 ground truth，不改变 OCR 候选、翻译 prompt/model、普通图片 OCR、renderer/export、`probe_report`、Koharu active artifact gate、metrics 或仓库 `output/`。候选、PR、merge 默认 `probe_mode=skip`，没有新的 OCR／翻译／Koharu 指标；真实 `test/koharu_artifacts/` 四件套、Speech corpus 与真实竖排图片 corpus 仍缺失，不声称 OCR、翻译、识别或 Koharu 质量提升。

云端证据：

- 候选 push full [31073337578](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31073337578)：exact SHA `067077bcb146e2e0c8bb2e066350cac2466b7460`，`validationProfile=full`、`validationReason=candidate_development_push`，Xcode build success，静态/Speech/UI/home/paste 合同 success，JUnit `10/10` 且 0 failures，`probe_mode=skip`；manifest 版本 `v3.118`。readiness validator 诚实记录 `manifestMissing / stopUntilArtifactsProvided`。
- PR #182 fast [31073688262](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31073688262)：exact head SHA，`validationProfile=fast`，复用候选 full `067077bcb146e2e0c8bb2e066350cac2466b7460` / `success`，Xcode skipped，JUnit `10/10`；不是新的编译证据。
- merge fast [31073828173](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31073828173)：merge SHA `036bada7aebd70da50d6d31cc4e4da2cce4b8dda`，`validationReason=merge_reuses_successful_candidate_full_validation`，`receiptPropagationAllowed=true`，复用候选 full / `success`，Xcode skipped，JUnit `10/10`。
- 文档 metadata follow-up [31074059262](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31074059262)：commit `0aa60a9ca9911ae6741063e142ad2afa70556174`，`smalldataIncrementalMetadataOnly=true`，复用父 merge full `036bada7aebd70da50d6d31cc4e4da2cce4b8dda / success`，Xcode skipped，JUnit `10/10`；不是新的编译证据。

## v3.117：漫画探针筛选展开状态 reset

日期：2026-08-06

状态：Agent X 已完成 v3.117 Developer Console 漫画探针筛选切换后的展开状态隔离、候选 full、PR fast、merge fast 云端验收并合入 `smalldata_test`；工程正式版本为 `MARKETING_VERSION=3.117`。候选 commit `4bda6f5a0ea20e7d8223546d0b380758d839c253` 已通过 PR [#181](https://github.com/bengzhu/project1_lgbt_naxida/pull/181) 合入，merge SHA `b209880723b3d82c7df3d78240ad8d05a16d48e3`；候选远端分支已删除，`main` 未触碰。

核心变更：

- `MangaProbeSection` 在 `diagnosticFilter` 变化时先递增既有 `diagnosticExpansionResetID`，让所有仍在视图中的 `MangaProbeBlockRow` 收起 stale 详情，再调用 v3.116 的 generation requester 聚焦新筛选首个结果或空态。
- 逐块行继续用 `suppressNextExpansionFocusHandoff` 抑制 reset 引发的旧焦点回抢；筛选 reset、展开状态、焦点 identity 与 generation 都留在 View/report-only，不新增 Store／持久化。
- 新增 `scripts/test-v3117-manga-diagnostic-filter-expansion-reset-contract.py` 并接入 UI/full fail-fast；不重跑探针、不读取 ground truth、不改变 OCR、翻译、renderer/export、`probe_report` 或 Koharu active gate。

边界：本版只改善漫画探针诊断筛选切换的视觉与 VoiceOver 操作连续性。候选、PR、merge 默认 `probe_mode=skip`，没有新的 OCR／翻译／Koharu 指标；真实 `test/koharu_artifacts/` 四件套、Speech corpus 与真实竖排图片 corpus 仍缺失，不声称 OCR、翻译、识别或 Koharu 质量提升。

云端证据：

- 候选 push full [31072107788](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31072107788)：exact SHA `4bda6f5a0ea20e7d8223546d0b380758d839c253`，`validationProfile=full`、`validationReason=candidate_development_push`，Xcode build success，静态/Speech/UI/home/paste 合同 success，JUnit `10/10` 且 0 failures，`probe_mode=skip`；manifest 版本 `v3.117`。
- PR #181 fast [31072405558](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31072405558)：exact head SHA，`validationProfile=fast`，`reusedFullValidationSha=4bda6f5a0ea20e7d8223546d0b380758d839c253`、`reusedFullValidationState=success`，Xcode skipped，JUnit `10/10`；不是新的编译证据。
- merge fast [31072447592](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31072447592)：merge SHA `b209880723b3d82c7df3d78240ad8d05a16d48e3`，`validationReason=merge_reuses_successful_candidate_full_validation`，复用候选 full `4bda6f5a0ea20e7d8223546d0b380758d839c253` / `success`，`receiptPropagationAllowed=true`，Xcode skipped，JUnit `10/10` 且 0 failures。
- 文档 metadata follow-up [31072550177](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31072550177)：commit `a7015cd14d58c0c29dd57359c1a0df086e91b801`，`smalldataIncrementalMetadataOnly=true`，复用父 merge full receipt `b209880723b3d82c7df3d78240ad8d05a16d48e3 / success`，Xcode skipped，JUnit `10/10`；不是新的编译证据。

## v3.116：漫画探针诊断焦点请求 generation 仲裁

日期：2026-08-06

状态：Agent X 已完成 v3.116 Developer Console 漫画探针诊断焦点的 View-only 改进、候选 full、PR fast、merge fast 云端验收并合入 `smalldata_test`；工程正式版本为 `MARKETING_VERSION=3.116`。候选 commit `4788bb213eeff010775a35798dc6fb28aabb7c0c` 已通过 PR [#180](https://github.com/bengzhu/project1_lgbt_naxida/pull/180) 合入，merge SHA `b9607e246b070222e4ef4cc4dbd78b8ee925b8ea`；候选远端分支已删除，`main` 未触碰。

核心变更：

- `MangaProbeSection` 新增 View 私有 `diagnosticAccessibilityFocusRequestID`，筛选结果、报告终态和逐块展开／收起的焦点 handoff 共用 `moveDiagnosticAccessibilityFocus(to:)`；每次请求递增 generation，异步 `Task.yield()` 后只有仍为最新请求才写入 `@AccessibilityFocusState`。
- 新探针进入 loading 时递增 generation、清除旧焦点；`MangaProbeBlockRow` 通过父级 requester 交接展开详情与收起回结果行，避免逐块行直接写焦点而抢回筛选或重跑后的最新目的地。该状态继续只存在 View，不新增 Store／持久化。
- 新增 `scripts/test-v3116-manga-diagnostic-focus-generation-contract.py` 并接入 UI/full fail-fast；v3.113 历史合同同步接受等价的共享 requester。

边界：本版只改善 Developer Console 漫画探针诊断的 VoiceOver 操作确定性，不重跑探针、不读取 ground truth、不改变 OCR 候选、翻译 prompt/model、普通图片 OCR、renderer/export、`probe_report`、Koharu active artifact gate、metrics 或仓库 `output/`。候选、PR、merge 默认 `probe_mode=skip`，没有新的 OCR／翻译／Koharu 指标。真实 `test/koharu_artifacts/` 四件套、Speech corpus 与真实竖排图片 corpus 仍缺失，不声称 OCR、翻译、识别或 Koharu 质量提升。

云端证据：

- 候选 push full [31071423891](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31071423891)：exact SHA `4788bb213eeff010775a35798dc6fb28aabb7c0c`，`validationProfile=full`、`validationReason=candidate_development_push`，Xcode build success，静态/Speech/UI/home/paste 合同 success，JUnit `10/10` 且 0 failures，`probe_mode=skip`；manifest 版本 `v3.116`。
- PR #180 fast [31071714254](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31071714254)：exact head SHA，`validationProfile=fast`，`reusedFullValidationSha=4788bb213eeff010775a35798dc6fb28aabb7c0c`、`reusedFullValidationState=success`，Xcode skipped，JUnit `10/10`；不是新的编译证据。
- merge fast [31071752236](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31071752236)：merge SHA `b9607e246b070222e4ef4cc4dbd78b8ee925b8ea`，`validationReason=merge_reuses_successful_candidate_full_validation`，复用候选 full `4788bb213eeff010775a35798dc6fb28aabb7c0c` / `success`，`receiptPropagationAllowed=true`，Xcode skipped，JUnit `10/10` 且 0 failures。
- 文档 metadata follow-up [31071915701](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31071915701)：commit `de1b70b64cec9faa46b5b2904079a508b6816e15`，`smalldataIncrementalMetadataOnly=true`，复用父 merge full receipt `b9607e246b070222e4ef4cc4dbd78b8ee925b8ea / success`，Xcode skipped，JUnit `10/10`；不是新的编译证据。

## v3.115：图片 OCR 焦点请求 generation 仲裁

日期：2026-08-06

状态：Agent X 已完成 v3.115 普通图片 OCR 多入口 VoiceOver 焦点请求仲裁的 View-only 改进、候选 full、PR fast、merge fast 云端验收并合入 `smalldata_test`；工程正式版本为 `MARKETING_VERSION=3.115`。候选 commit `50029c449f86fbf4f0d43e7e35967a0c1e0ec8ce` 已通过 PR [#179](https://github.com/bengzhu/project1_lgbt_naxida/pull/179) 合入，merge SHA `b4d3acd1c6bdaf51429ae5acdfed05013a2b37c6`；候选远端分支已删除，`main` 未触碰。

核心变更：

- `ImageTranslationPanel` 新增 View 私有 `reviewAccessibilityFocusRequestID`；每次 `moveReviewAccessibilityFocus(to:)` 递增 generation，异步 handoff 只有在 generation 与当前 `imageTranslationRevision` 同时匹配时才写入 VoiceOver focus。
- 新图片 revision 开始时先递增 generation 并清除旧 focus，失效筛选、定位、复查、修正 sheet、局部预览关闭等旧任务留下的 pending handoff；不改变既有 focus destination 或状态门。
- 新增 `scripts/test-v3115-image-focus-request-generation-contract.py`，锁定 latest-request-wins、revision invalidation 和 View-only 边界；未新增 Store／持久化，不改变 OCR、翻译、renderer/export、探针报告或 Koharu active gate。

边界：本版只改善普通图片 OCR 多入口操作的 VoiceOver 焦点确定性，不改变 Vision OCR 候选、翻译 prompt/model、普通图片 renderer/export、probe_report、Koharu active artifact gate、metrics 或仓库 `output/`。候选、PR、merge 默认 `probe_mode=skip`，没有新的 OCR／翻译指标。真实 `test/koharu_artifacts/` 四件套、Speech corpus 与真实竖排图片 corpus 仍缺失，Koharu readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不声称 OCR、翻译、识别或 Koharu 质量提升。

云端证据：

- 候选 push full [31070650744](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31070650744)：exact SHA `50029c449f86fbf4f0d43e7e35967a0c1e0ec8ce`，`validationProfile=full`、`validationReason=candidate_development_push`，Xcode build success，静态/Speech/UI/home/paste 合同 success，JUnit `10/10` 且 0 failures，`probe_mode=skip`；manifest 版本 `v3.115`，readiness 为 `manifestMissing / stopUntilArtifactsProvided`。
- 手动候选 full [31070655111](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31070655111)：同 exact SHA，`validationProfile=full`、`validationReason=manual_full`，Xcode build success，JUnit `10/10` 且 0 failures；与 push full 交叉确认，不产生探针指标。
- PR #179 fast [31070940503](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31070940503)：exact head SHA，`validationProfile=fast`，`reusedFullValidationSha=50029c449f86fbf4f0d43e7e35967a0c1e0ec8ce`、`reusedFullValidationState=success`，Xcode skipped，JUnit `10/10`；不是新的编译证据。
- merge fast [31070976672](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31070976672)：merge SHA `b4d3acd1c6bdaf51429ae5acdfed05013a2b37c6`，`validationReason=merge_reuses_successful_candidate_full_validation`，复用候选 full `50029c449f86fbf4f0d43e7e35967a0c1e0ec8ce` / `success`，`receiptPropagationAllowed=true`，Xcode skipped，JUnit `10/10` 且 0 failures。

## v3.114：漫画探针诊断展开状态隔离

日期：2026-08-06

状态：Agent X 已完成 v3.114 Developer Console 漫画探针逐块诊断展开状态隔离、候选 full、PR fast、merge fast 云端验收并合入 `smalldata_test`；工程正式版本为 `MARKETING_VERSION=3.114`。候选 commit `e62a168e57e2f2cbc6cb47b5a8c8dde571d73f42` 已通过 PR [#178](https://github.com/bengzhu/project1_lgbt_naxida/pull/178) 合入，merge SHA `118afee6e096f73e6ab97d71c23af189d997f6ca`；候选远端分支已删除，`main` 未触碰。

核心变更：

- `MangaProbeSection` 在探针进入 loading 时递增 View 私有 `diagnosticExpansionResetID` 并传给每个 `MangaProbeBlockRow`；逐块行在 token 变化且详情已展开时收起旧内容。
- reset 收起通过 `suppressNextExpansionFocusHandoff` 抑制一次 `isExpanded` 的旧焦点回调，避免清理上一轮报告时把 VoiceOver 焦点抢回旧结果；正常用户展开／收起仍交给详细诊断容器或原结果行。
- `blockAccessibilityValue` 与 `blockAccessibilityHint` 读出“详细诊断已展开／已收起”及收起／展开动作；新增 `scripts/test-v3114-manga-diagnostic-expansion-state-contract.py`，未新增 Store／持久化，不重跑探针，不读取 ground truth。

边界：本版只改善 Developer Console 漫画探针逐块诊断的新报告状态隔离与 VoiceOver 可理解性，不改变 OCR 候选、翻译 prompt/model、普通图片 OCR、renderer/export、probe_report、Koharu active artifact gate、metrics 或仓库 `output/`。候选、PR、merge 默认 `probe_mode=skip`，没有新的 OCR／翻译指标。真实 `test/koharu_artifacts/` 四件套、Speech corpus 与真实竖排图片 corpus 仍缺失，Koharu readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不声称 OCR、翻译、识别或 Koharu 质量提升。

云端证据：

- 候选 push full [31069913494](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31069913494)：exact SHA `e62a168e57e2f2cbc6cb47b5a8c8dde571d73f42`，`validationProfile=full`、`validationReason=candidate_development_push`，Xcode build success，静态/Speech/UI/home/paste 合同 success，JUnit `10/10` 且 0 failures，`probe_mode=skip`；manifest 版本 `v3.114`，readiness 为 `manifestMissing / stopUntilArtifactsProvided`。
- 手动候选 full [31069918901](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31069918901)：同 exact SHA，`validationProfile=full`、`validationReason=manual_full`，Xcode build success，JUnit `10/10` 且 0 failures；与 push full 交叉确认，不产生探针指标。
- PR #178 fast [31070264175](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31070264175)：exact head SHA，`validationProfile=fast`，`reusedFullValidationSha=e62a168e57e2f2cbc6cb47b5a8c8dde571d73f42`、`reusedFullValidationState=success`，Xcode skipped，JUnit `10/10`；不是新的编译证据。
- merge fast [31070323190](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31070323190)：merge SHA `118afee6e096f73e6ab97d71c23af189d997f6ca`，`validationReason=merge_reuses_successful_candidate_full_validation`，复用候选 full `e62a168e57e2f2cbc6cb47b5a8c8dde571d73f42` / `success`，`receiptPropagationAllowed=true`，Xcode skipped，JUnit `10/10` 且 0 failures。

## v3.113：漫画探针诊断展开 VoiceOver 焦点交接

日期：2026-08-06

状态：Agent X 已完成 v3.113 Developer Console 漫画探针逐块诊断展开／收起焦点的 View-only 改进、候选 full、PR fast、merge fast 云端验收并合入 `smalldata_test`；工程正式版本为 `MARKETING_VERSION=3.113`。候选 commit `fd2cf8d32b9576dc2620ce3c281403421aa1ca02` 已通过 PR [#177](https://github.com/bengzhu/project1_lgbt_naxida/pull/177) 合入，merge SHA `1f3612f54410aef39ea8c5a34195f9d9f9296573`；候选远端分支已删除，`main` 未触碰。

核心变更：

- `MangaProbeBlockRow` 将 DisclosureGroup 改为绑定 View 私有 `isExpanded`；展开后在主线程让渡一次，将 VoiceOver 焦点交给稳定的 `manga-diagnostic-detail-\(block.index)` 详细诊断容器，收起后回到原 `manga-diagnostic-block-\(block.index)` 结果行。
- 详细诊断容器继续复用 `blockAccessibilityValue` 与既有 OCR／翻译／布局风险、报告下一步和执行边界上下文，并以 `.accessibilityElement(children: .contain)` 保留可复制的诊断字段；焦点 identity、展开状态和 handoff 均留在 View。
- 新增 `scripts/test-v3113-manga-diagnostic-expansion-focus-contract.py`，锁定展开／收起焦点、report-only 边界、版本和 CI 路由；未新增 Store／持久化，不运行第二次探针，不读取 ground truth。

边界：本版只改善 Developer Console 漫画探针逐块诊断的 VoiceOver 操作连续性，不改变 OCR 候选、翻译 prompt/model、普通图片 OCR、renderer/export、probe_report、Koharu active artifact gate、metrics 或仓库 `output/`。候选、PR、merge 默认 `probe_mode=skip`，没有新的 OCR／翻译指标。真实 `test/koharu_artifacts/` 四件套、Speech corpus 与真实竖排图片 corpus 仍缺失，Koharu readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不声称 OCR、翻译、识别或 Koharu 质量提升。

云端证据：

- 候选 push full [31068769954](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31068769954)：exact SHA `fd2cf8d32b9576dc2620ce3c281403421aa1ca02`，`validationProfile=full`、`validationReason=candidate_development_push`，Xcode build success，静态/Speech/UI/home/paste 合同 success，JUnit `10/10` 且 0 failures，`probe_mode=skip`；manifest 版本 `v3.113`，readiness 为 `manifestMissing / stopUntilArtifactsProvided`。
- 手动候选 full [31068778764](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31068778764)：同 exact SHA，`validationProfile=full`、`validationReason=manual_full`，Xcode build success，JUnit `10/10` 且 0 failures；该 run 与 push full 互相交叉确认，均不产生探针指标。
- PR #177 fast [31069311041](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31069311041)：exact head SHA，`validationProfile=fast`，`reusedFullValidationSha=fd2cf8d32b9576dc2620ce3c281403421aa1ca02`、`reusedFullValidationState=success`，Xcode skipped，JUnit `10/10`；不是新的编译证据。
- merge fast [31069349841](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31069349841)：merge SHA `1f3612f54410aef39ea8c5a34195f9d9f9296573`，`validationReason=merge_reuses_successful_candidate_full_validation`，复用候选 full `fd2cf8d32b9576dc2620ce3c281403421aa1ca02` / `success`，`receiptPropagationAllowed=true`，Xcode skipped，JUnit `10/10` 且 0 failures。
## v3.112：图片 OCR 终态 VoiceOver 焦点交接

日期：2026-08-06

状态：Agent X 已完成 v3.112 普通图片 OCR 新图／重试终态焦点的 View-only 改进、候选 full、PR fast、merge fast 云端验收并合入 `smalldata_test`；工程正式版本为 `MARKETING_VERSION=3.112`。候选 commit `a150982ab83dac47000bb6bce34caa9aa74ecf26` 已通过 PR [#176](https://github.com/bengzhu/project1_lgbt_naxida/pull/176) 合入，merge SHA `f467a72a3de9d5ab6e876a51e228e19e037f4174`；候选远端分支已删除，`main` 未触碰。

核心变更：

- 普通图片 OCR 的新 `imageTranslationRevision` 进入 `.translated` 或 `.failed` 后恢复 VoiceOver 焦点：有 blocks 时交给当前筛选的首个 OCR 结果行，无 blocks 时交给动态“图片翻译状态”行，状态行继续读出实时阶段、详情和下一步边界。
- revision 变化时保留既有筛选意图清理、选中 block 清除、修正／恢复 sheet 关闭和旧 accessibility focus 清空；pending terminal revision 只存在于 `ImageTranslationPanel` 的 View `@State`，终态 Task 用 revision guard 防止旧图片任务抢焦点。
- 非新 revision 的人工修正、复查、导出重绘和分享状态变化不会触发终态焦点交接；新增 `scripts/test-v3112-image-translation-terminal-focus-contract.py` 并接入 UI/full fail-fast。

边界：本版只改善普通图片 OCR 完成／失败后的 VoiceOver 操作连续性，不改变 Vision OCR 候选、翻译 prompt/model、Store／持久化、renderer/export、漫画探针、probe_report、Koharu active artifact gate、metrics 或仓库 `output`。候选、PR、merge 默认 `probe_mode=skip`，没有新的 OCR／翻译指标。真实 `test/koharu_artifacts/` 四件套、Speech corpus 与真实竖排图片 corpus 仍缺失，Koharu readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不声称 OCR、翻译、识别或 Koharu 质量提升。

云端证据：

- 候选 full [31067968394](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31067968394)：exact SHA `a150982ab83dac47000bb6bce34caa9aa74ecf26`，`validationProfile=full`、`validationReason=manual_full`，Xcode build success，静态/Speech/UI/home/paste 合同 success，JUnit `10/10` 且 0 failures，`probe_mode=skip`；manifest 版本 `v3.112`，readiness 为 `manifestMissing / stopUntilArtifactsProvided`。
- PR #176 fast [31068324104](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31068324104)：exact head SHA，`validationProfile=fast`，`reusedFullValidationSha=a150982ab83dac47000bb6bce34caa9aa74ecf26`、`reusedFullValidationState=success`，Xcode 与领域大套件按 fast 规则跳过，JUnit `10/10`；不是新的编译证据。
- merge fast [31068365757](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31068365757)：merge SHA `f467a72a3de9d5ab6e876a51e228e19e037f4174`，`validationReason=merge_reuses_successful_candidate_full_validation`，复用候选 full `a150982ab83dac47000bb6bce34caa9aa74ecf26` / `success`，`receiptPropagationAllowed=true`，Xcode skipped，JUnit `10/10` 且 0 failures。

## v3.111：漫画探针报告终态 VoiceOver 焦点交接

日期：2026-08-06

状态：Agent X 已完成 v3.111 Developer Console 漫画探针报告终态焦点的 View-only 改进、候选 full、PR fast、merge fast 云端验收并合入 `smalldata_test`；工程正式版本为 `MARKETING_VERSION=3.111`。候选 commit `70222e95035c7cd5a71799735e11539f755b5d08` 已通过 PR [#175](https://github.com/bengzhu/project1_lgbt_naxida/pull/175) 合入，merge SHA `9a28692cebf3360ca00b5e0b7f77463f103bdaa2`；候选远端分支已删除，`main` 未触碰。

核心变更：

- Developer Console 的漫画探针在既有 `MangaOverlayProbeReport` 写入后恢复 VoiceOver 焦点：报告存在 blocks 时交给当前诊断筛选的首个结果行，报告没有 blocks 时交给“未生成逐块诊断”状态；空报告状态继续说明 `test/1.png`、Output 清理和重试范围。
- 探针进入 loading 时仍先重置 `diagnosticFilter` 并清除旧焦点，避免上一轮结果或筛选残留；终态焦点只保存在 `MangaProbeSection` 的 `@AccessibilityFocusState`，不进入 Store／持久化，不触发第二次探针。
- 新增 `scripts/test-v3111-manga-probe-terminal-focus-contract.py` 并接入 UI/full fail-fast；该合同验证 blocks、空报告、筛选空态、loading 清理和 View-only 边界。

边界：本版只改善漫画探针重跑后的 VoiceOver 操作连续性及失败重试可发现性，不改变普通图片 OCR、Vision OCR、翻译 prompt/model、renderer/export、probe_report、Koharu active artifact gate、metrics 或仓库 `output`。候选、PR、merge 默认 `probe_mode=skip`，没有新的 OCR／翻译指标。真实 `test/koharu_artifacts/` 四件套、Speech corpus 与真实竖排图片 corpus 仍缺失，Koharu readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不声称 OCR、翻译、识别或 Koharu 质量提升。

云端证据：

- 候选 full [31067283530](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31067283530)：exact SHA `70222e95035c7cd5a71799735e11539f755b5d08`，`validationProfile=full`、`validationReason=manual_full`，Xcode build success，静态/Speech/UI/home/paste 合同 success，JUnit `10/10` 且 0 failures，`probe_mode=skip`；manifest 版本 `v3.111`，readiness 为 `manifestMissing / stopUntilArtifactsProvided`。
- PR #175 fast [31067583454](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31067583454)：exact head SHA，`validationProfile=fast`，`reusedFullValidationSha=70222e95035c7cd5a71799735e11539f755b5d08`、`reusedFullValidationState=success`，Xcode 与领域大套件按 fast 规则跳过，JUnit `10/10`；不是新的编译证据。
- merge fast [31067629934](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31067629934)：merge SHA `9a28692cebf3360ca00b5e0b7f77463f103bdaa2`，`validationReason=merge_reuses_successful_candidate_full_validation`，复用候选 full `70222e95035c7cd5a71799735e11539f755b5d08` / `success`，`receiptPropagationAllowed=true`，Xcode skipped，JUnit `10/10` 且 0 failures。

## v3.110：图片 OCR 筛选焦点意图仲裁

日期：2026-08-06

状态：Agent X 已完成 v3.110 普通图片 OCR 筛选焦点意图仲裁的 View-only 改进、候选 full、PR fast、merge fast 云端验收并合入 `smalldata_test`；工程正式版本为 `MARKETING_VERSION=3.110`。候选 commit `43e75f22be1f1acc55045942f9c617bb0e4675e9` 已通过 PR [#174](https://github.com/bengzhu/project1_lgbt_naxida/pull/174) 合入，merge SHA `08577f31c3dcd3da09ef64c6d9aa050e8d639794`；候选远端分支已删除，`main` 未触碰。

核心变更：

- 用户切换普通图片 OCR 的 `reviewFilter` 时，继续把 VoiceOver 焦点交给第一个可见结果行；开始／重启复查、恢复忽略 block、预览直接选中和完成／撤销复查等程序化筛选变化通过 `prepareReviewFilterChange(to:focusID:suppressResultFocus:)` 声明显式的结果行、局部预览或复查完成态焦点，避免自动首结果焦点覆盖用户当前操作意图。
- 图片 revision 重置会清除 pending focus 与 suppression 标记，再由既有隐藏选中清理、空筛选／复查完成态回退和 revision-scoped `moveReviewAccessibilityFocus` 处理焦点；意图状态只存在于 `ImageTranslationPanel` 的 View `@State`，不进入 Store／持久化，不改变 OCR、翻译、renderer/export、探针报告或 Koharu active gate。
- 新增 `scripts/test-v3110-image-filter-focus-intent-contract.py` 并接入 UI/full fail-fast；同步让 v3.15、v3.16、v3.17、v3.29、v3.81、v3.93 历史合同接受该 helper 的等价语义，防止合法 View-only 重构被旧直接赋值字符串误报。

边界：本版只改善图片筛选与复查操作的 VoiceOver 焦点连续性及源码合同鲁棒性；候选、PR、merge 默认 `probe_mode=skip`，没有新的 OCR／翻译指标或 `metrics/version_history.csv`、仓库 `output/` 变更。真实 `test/koharu_artifacts/` 四件套、Speech corpus 与真实竖排图片 corpus 仍缺失，Koharu readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不声称 OCR、翻译、识别或 Koharu 质量提升。

云端证据：

- 候选 full [31066203170](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31066203170)：exact SHA `43e75f22be1f1acc55045942f9c617bb0e4675e9`，`validationProfile=full`、`validationReason=manual_full`，Xcode build success，静态/Speech/UI/home/paste 合同 success，JUnit `10/10` 且 0 failures，`probe_mode=skip`；候选 parent 的历史失败只影响 scope fallback，不影响本次 full receipt，readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`。
- PR #174 fast [31066589776](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31066589776)：exact head SHA，`validationProfile=fast`，`reusedFullValidationSha=43e75f22be1f1acc55045942f9c617bb0e4675e9`、`reusedFullValidationState=success`，Xcode 与领域大套件按 fast 规则跳过，JUnit `10/10`；不是新的编译证据。
- merge fast [31066628727](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31066628727)：merge SHA `08577f31c3dcd3da09ef64c6d9aa050e8d639794`，`validationReason=merge_reuses_successful_candidate_full_validation`，复用候选 full `43e75f22be1f1acc55045942f9c617bb0e4675e9` / `success`，`receiptPropagationAllowed=true`，Xcode skipped，JUnit `10/10` 且 0 failures。

## v3.109：图片 OCR 筛选结果焦点交接

日期：2026-08-06

状态：Agent X 已完成 v3.109 普通图片 OCR 识别结果筛选焦点的 View-only 改进、候选 full、PR fast、merge fast 云端验收并合入 `smalldata_test`；工程正式版本为 `MARKETING_VERSION=3.109`。候选 commit `b3a58afda5cbc0ffddfd337d1787a306a8ba2f36` 已通过 PR [#173](https://github.com/bengzhu/project1_lgbt_naxida/pull/173) 合入，merge SHA `1a422b2cd90f955895acea644e435fe86899a328`；候选远端分支已删除，`main` 未触碰。

核心变更：

- 普通图片 OCR 的 `reviewFilter` 切换到有结果的类别后，在保留隐藏选中项清理的前提下，将 VoiceOver 焦点交给 `visibleImageTranslationBlocks.first` 对应的 OCR 结果行；用户切换“全部／待复查／低置信／方向待定”后可以直接继续阅读和操作首个结果。
- 无结果时仍由 v3.107 的复查完成态或筛选空态接管焦点；焦点只使用既有 revision-scoped `moveReviewAccessibilityFocus`，不进入 Store／持久化，不改变选择、复查进度、Vision OCR、翻译、renderer/export、漫画探针、Koharu active gate、metrics 或 `output`。
- 新增 `scripts/test-v3109-image-filter-result-focus-contract.py`，接入 UI/full fail-fast；历史 v3.106–v3.108 与 v3.399 合同继续保留。

边界：本版只改善普通图片 OCR 筛选后的 VoiceOver 操作连续性；候选、PR、merge 默认 `probe_mode=skip`，没有新的 OCR／翻译指标或 `metrics/version_history.csv`、仓库 `output/` 变更。真实 `test/koharu_artifacts/` 四件套、Speech corpus 与真实竖排图片 corpus 仍缺失，Koharu readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不声称 OCR、翻译、识别或 Koharu 质量提升。

云端证据：

- 候选 full [31064198524](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31064198524)：exact SHA `b3a58afd...`，`validationProfile=full`、`validationReason=candidate_development_push`、Xcode build success，静态/Speech/UI/home/paste 合同 success，JUnit `10/10` 且 0 failures，`probe_mode=skip`；Koharu readiness 为 `manifestMissing / stopUntilArtifactsProvided`。
- PR #173 fast [31064487760](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31064487760)：exact head SHA，`validationProfile=fast`，复用候选 full `b3a58afd.../success`，Xcode 与领域大套件按 fast 规则跳过，JUnit `10/10`；不是新的编译证据。
- merge fast [31064532453](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31064532453)：merge SHA `1a422b2c...`，`validationReason=merge_reuses_successful_candidate_full_validation`，复用候选 full `b3a58afd.../success`，`receiptPropagationAllowed=true`，Xcode skipped，JUnit `10/10` 且 0 failures。

## v3.108：漫画诊断筛选结果焦点交接

日期：2026-08-06

状态：Agent X 已完成 v3.108 Developer Console 漫画诊断筛选结果焦点的 View-only 改进、候选 full、PR fast、merge fast 云端验收并合入 `smalldata_test`；工程正式版本为 `MARKETING_VERSION=3.108`。候选 commit `c6bee294a7a5e59b51e39aa3b27cc09c5a913616` 已通过 PR [#172](https://github.com/bengzhu/project1_lgbt_naxida/pull/172) 合入，merge SHA `859bac7b6e47f31ab3b14220737fe3d9c4048a07`；候选远端分支已删除，`main` 未触碰。

核心变更：

- Developer Console 漫画诊断筛选从空结果或其他类别切换到有结果时，在一次主线程让渡后把 VoiceOver 焦点交给 `filteredProbeBlocks[0]` 对应的结果行；结果行使用稳定的 block accessibility identity，保持筛选结果可继续操作。
- 空筛选继续复用 v3.107 的可操作空态焦点；焦点状态只存在于 `MangaProbeSection` 的 `AccessibilityFocusState`，`MangaProbeBlockRow` 只接收既有 report 和 View-only binding/id，不新增 Store／持久化、不运行第二次探针、不改变 OCR、翻译、renderer/export、Koharu active gate、metrics 或 `output`。
- 新增 `scripts/test-v3108-manga-filter-result-focus-contract.py`，并让 v3.399 历史报告交接合同接受额外的 View-only 行上下文而不绑定旧初始化器排版；CI 路由接在 v3.107 后进入 UI/full fail-fast。

边界：本版只改善漫画诊断筛选后的 VoiceOver 焦点与源码合同鲁棒性；候选、PR、merge 默认 `probe_mode=skip`，没有新的 OCR／翻译指标或 `metrics/version_history.csv`、仓库 `output/` 变更。真实 `test/koharu_artifacts/` 四件套、Speech corpus 与真实竖排图片 corpus 仍缺失，Koharu readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`，不声称 OCR、翻译、识别或 Koharu 质量提升。

云端证据：

- 候选 full [31063355633](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31063355633)：exact SHA `c6bee294...`，`validationProfile=full`、`validationReason=candidate_development_push`、Xcode build success，静态/Speech/UI/home/paste 合同 success，JUnit `10/10` 且 0 failures，`probe_mode=skip`；Koharu readiness 为 `manifestMissing / stopUntilArtifactsProvided`。
- PR #172 fast [31063761078](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31063761078)：exact head SHA，`validationProfile=fast`，复用候选 full `c6bee294.../success`，Xcode 与领域大套件按 fast 规则跳过，JUnit `10/10`；不是新的编译证据。
- merge fast [31063805810](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31063805810)：merge SHA `859bac7b...`，`validationReason=merge_reuses_successful_candidate_full_validation`，复用候选 full `c6bee294.../success`，`receiptPropagationAllowed=true`，Xcode skipped，JUnit `10/10` 且 0 failures。

## v3.107：筛选空态 VoiceOver 焦点交接

日期：2026-08-06

状态：Agent X 已完成 v3.107 图片 OCR／漫画诊断筛选空态的 View-only 改进、候选 full、PR fast、merge fast 云端验收并合入 `smalldata_test`；工程正式版本为 `MARKETING_VERSION=3.107`。候选 commit `f513bcd71f48ec34c2820941b86da7093bc86761` 已通过 PR [#171](https://github.com/bengzhu/project1_lgbt_naxida/pull/171) 合入，merge SHA `0e7e692543aa34f8fb368cea766fb82391295929`；`main` 未触碰。

核心变更：

- 普通图片 OCR 筛选无结果时显示稳定空态 VoiceOver label/value/hint，读出当前筛选、`0 / 总数` 和切换筛选路径；筛选切换会清除隐藏选择，并将焦点交给空筛选态或已有复查完成态。
- Developer Console 漫画诊断筛选无结果时提供同样的只读空态上下文和焦点 identity；探针加载／新运行时清除旧诊断焦点，避免焦点停留在已卸载的结果行。
- 新增 `scripts/test-v3107-filter-empty-state-focus-contract.py`，接在 v3.106 后进入 UI/full fail-fast；workflow 历史路由锚点移到 YAML 顶层注释，保持可执行路由并避开 GitHub Actions run block 的 21k 表达式上限。

边界：本版只改善 VoiceOver 与空态操作语义，不新增 Store／持久化、不运行第二次探针、不改变 OCR、翻译、renderer/export、Koharu active gate、metrics 或仓库 `output`。候选默认 `probe_mode=skip`；真实 Koharu 四件套、Speech corpus 与真实竖排图片 corpus 仍缺失，不声称 OCR、翻译、识别或 Koharu 质量提升。

云端证据：

- 候选 full [31020576411](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31020576411)：exact SHA `f513bcd7...`，`validationProfile=full`、Xcode build success、静态/Speech/UI/home/paste 合同 success，JUnit `10/10` 且 0 failures，`probe_mode=skip`；Koharu readiness 为 `manifestMissing / stopUntilArtifactsProvided`。
- PR #171 fast [31062338507](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31062338507)：`validationProfile=fast`，复用候选 full `f513bcd7.../success`，Xcode 与领域大套件按 fast 规则跳过，JUnit `10/10`；不是新的编译证据。
- merge fast [31062372361](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31062372361)：merge SHA `0e7e6925...`，`validationReason=merge_reuses_successful_candidate_full_validation`，复用候选 full `f513bcd7.../success`，`receiptPropagationAllowed=true`，Xcode skipped，JUnit `10/10` 且 0 failures。

## v3.106：统一筛选器 VoiceOver 数量上下文

日期：2026-08-05

状态：Agent X 已完成 v3.106 View-only 筛选器上下文、候选 full、PR fast、merge fast 云端验收并合入 `smalldata_test`；工程正式版本为 `MARKETING_VERSION=3.106`。候选 commit `fd0eef26e5df6fd346b0f98612a87446aa951c25` 已通过 PR [#170](https://github.com/bengzhu/project1_lgbt_naxida/pull/170) 合入，merge SHA `a181c52e0d1500775885cec90c03269b51009acc`，候选远端分支已删除，`main` 未触碰。

核心变更：

- 普通图片 OCR 的 `识别结果筛选` Picker 现在通过 `reviewFilterAccessibilityValue` 读出当前筛选类别、显示数量／总数量；存在低置信或方向待定风险块时，同时读出已完成与剩余复查数量。
- Developer Console 漫画探针筛选器现在读出当前诊断类别、筛选结果数和总文字块数；视觉筛选范围仍只属于逐块诊断展示。
- 新增 `scripts/test-v3106-filter-accessibility-context-contract.py` 并接入 UI interaction/full fail-fast。改动不新增 Store／持久化、不改变 OCR、翻译、renderer/export、探针报告、Koharu active gate、metrics 或仓库 `output`。

限制：候选默认 `probe_mode=skip`，不产生新的 OCR／翻译指标；真实 Koharu 四件套、Speech corpus 与真实竖排图片 corpus 仍缺失，不声称 OCR、翻译、识别或 Koharu 质量提升。

云端证据：

- 候选 full [31017118790](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31017118790)：exact SHA `fd0eef26...`，`validationProfile=full`、Xcode build success、静态/Speech/UI/home/paste 合同 success，JUnit `10/10` 且 0 failures，`probe_mode=skip`；Koharu readiness 仍为 `manifestMissing / stopUntilArtifactsProvided`。
- PR #170 fast [31017809552](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31017809552)：exact head SHA，`validationProfile=fast`，`reusedFullValidationSha=fd0eef26...`、`reusedFullValidationState=success`，Xcode/领域大套件按 fast 规则跳过，JUnit `10/10`；不是新的编译证据。
- merge fast [31017909329](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31017909329)：merge SHA `a181c52e...`，`validationReason=merge_reuses_successful_candidate_full_validation`，复用候选 full `fd0eef26.../success`，`receiptPropagationAllowed=true`，Xcode skipped，JUnit `10/10` 且 0 failures。

## v3.105：暴露漫画探针收敛总览快照

日期：2026-08-05

状态：Agent X 已完成 v3.105 Developer Console 漫画探针诊断总览的 report-only 收敛快照、候选 full、PR fast、merge fast 云端验收并合入 `smalldata_test`；工程正式版本为 `MARKETING_VERSION=3.105`。候选 commit `5e6bee9f22e6c5ba754b2f4cae9083d0965f8580` 已通过 PR [#169](https://github.com/bengzhu/project1_lgbt_naxida/pull/169) 合入，merge SHA `35e36b4c67ea15333594b03e0500b79b32995667`，远端候选分支已删除，`main` 未触碰。

核心变更：

- `MangaProbeDiagnosticTriageSummary` 只读消费既有 `MangaKoharuArtifactConvergenceReport` 的开放／已闭环／要求停止工单、`workItemStatusBreakdown`、block path/work-item ledger 规模、需真实工件 block 和外部工件边界，形成可读的收敛闭环快照。
- 收敛快照同时进入状态标题/tone、status detail、`diagnostic triage` 可复制 summary 和 VoiceOver value；开放、停止、阻断或 report-only 状态保持 warning/仅报告，避免总览在未闭环时显示成功。改动不新增 Store／持久化、不运行第二次探针、不读取 ground truth，不改变 OCR、翻译 prompt/model、renderer/export、普通图片 OCR、Koharu active gate、metrics 或 `output`。
- 新增 `scripts/test-v3105-koharu-convergence-overview-contract.py`，接入 UI interaction/full fail-fast；项目 marketing version 与 CI 路由同步到 3.105。

云端证据：

- 候选 full [31015086472](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31015086472)：exact candidate SHA `5e6bee9f...`，`validationProfile=full`、`validationReason=candidate_development_push`、Xcode build success；静态/Speech/UI/home/paste 合同 success，JUnit `10/10`、0 failures，`probe_mode=skip`。
- PR #169 fast [31015765732](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31015765732)：exact head SHA，`validationProfile=fast`、Xcode skipped，`reusedFullValidationSha=5e6bee9f...`、`reusedFullValidationState=success`，JUnit `10/10`；该包不是新的编译证据。
- merge fast [31015838087](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31015838087)：merge SHA `35e36b4c...`，`validationReason=merge_reuses_successful_candidate_full_validation`，复用候选 full `5e6bee9f.../success`，`receiptPropagationAllowed=true`，Xcode skipped，JUnit `10/10` 且 0 failures。

本轮没有更新 `metrics/version_history.csv` 或仓库 `output/`；候选/PR/merge 默认跳过漫画探针，没有新的 OCR/翻译指标。Koharu active artifact gate 仍为 `manifestMissing / stopUntilArtifactsProvided`，真实 `test/koharu_artifacts/` 四件套、Speech corpus 与真实竖排图片 corpus 仍缺失；本版只改善 report-only 收敛可理解性，不声称 OCR、翻译、识别或 Koharu 质量提升。

## v3.104：暴露漫画探针收敛 block 上下文

日期：2026-08-05

状态：Agent X 已完成 v3.104 Developer Console 漫画探针逐块 report-only 收敛上下文、候选 full、PR fast、merge fast 云端验收并合入 `smalldata_test`；工程正式版本为 `MARKETING_VERSION=3.104`。候选 commit `1fc0015275091e50433262d0cdd3215e6d6d41a8` 已通过 PR [#168](https://github.com/bengzhu/project1_lgbt_naxida/pull/168) 合入，merge SHA `c1156bf707a97538daf062c5c8afd81cec674794`，远端候选分支已删除，`main` 未触碰。

核心变更：

- `MangaProbeBlockRow` 只读消费既有 `MangaKoharuArtifactConvergenceReport.blockPaths` 与 `workItemLedger`，按 block 显示首阻断工件、结构瓶颈、真实工件等待、开放工单、工单状态和 CI-fast/full/外部工件执行边界。
- 同一收敛上下文进入 action summary、结果行可见文本和 VoiceOver；`diagnosticOnly`、`wouldChangeMainFlow` 或开放工单会保持 warning/仅报告，避免把尚未闭环的 report-only 路径误读为成功晋级。改动不新增 Store／持久化、不运行第二次探针、不读取 ground truth，不改变 OCR、翻译 prompt/model、renderer/export、普通图片 OCR、Koharu active gate、metrics 或 `output`。
- 新增 `scripts/test-v3104-koharu-convergence-context-contract.py`，接入 UI interaction/full fail-fast；项目 marketing version 与 CI 路由同步到 3.104。

云端证据：

- 候选 full [31013385953](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31013385953)：exact candidate SHA `1fc00152...`，`validationProfile=full`、`validationReason=candidate_development_push`、Xcode build success；静态/Speech/UI/home/paste 合同 success，JUnit `10/10`、0 failures，`probe_mode=skip`。
- PR #168 fast [31014071238](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31014071238)：exact head SHA，`validationProfile=fast`、Xcode skipped，`reusedFullValidationSha=1fc00152...`、`reusedFullValidationState=success`，JUnit `10/10`；该包不是新的编译证据。
- merge fast [31014141913](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31014141913)：merge SHA `c1156bf7...`，`validationReason=merge_reuses_successful_candidate_full_validation`，复用候选 full `1fc00152.../success`，`receiptPropagationAllowed=true`，Xcode skipped，JUnit `10/10` 且 0 failures。

本轮没有更新 `metrics/version_history.csv` 或仓库 `output/`；候选/PR/merge 默认跳过漫画探针，没有新的 OCR/翻译指标。Koharu active artifact gate 仍为 `manifestMissing / stopUntilArtifactsProvided`，真实 `test/koharu_artifacts/` 四件套、Speech corpus 与真实竖排图片 corpus 仍缺失；本版只改善 report-only 收敛诊断与用户体验，不声称 OCR、翻译、识别或 Koharu 质量提升。

## v3.103：暴露漫画探针晋级边界上下文

日期：2026-08-05

状态：Agent X 已完成 v3.103 Developer Console 漫画探针诊断总览的 report-only 晋级边界上下文、候选 full、PR fast、merge fast 云端验收并合入 `smalldata_test`；工程正式版本为 `MARKETING_VERSION=3.103`。候选 commit `4705641bd23e447e9c4b438bbc6d37c5036a1155` 已通过 PR [#167](https://github.com/bengzhu/project1_lgbt_naxida/pull/167) 合入，merge SHA `3975dfa1353a9c9d812cc5c9b3f662128aa709a8`，远端候选分支已删除，`main` 未触碰。

核心变更：

- `MangaProbeDiagnosticTriageSummary` 只读消费既有 `koharuNativePromotionGateLiteReport`、`koharuNativeArtifactContractDryRunReport`、`koharuArtifactIdentityReconciliationReport` 与 `koharuArtifactConvergenceReport`，汇总 native promotion verdict、候选预览/active export 边界、真实工件与 CI manifest 身份对账、停止本地调参与未闭环工单。
- 同一晋级边界进入状态标题/详情、`diagnostic triage` 可复制摘要和 VoiceOver value/hint；缺少报告安全回退，proxy、preview 和 dry-run 不会显示为 active 晋级。该 View-only 改动不新增 Store／持久化、不运行第二次探针、不读取 ground truth，不改变 OCR、翻译 prompt/model、renderer/export、普通图片 OCR、Koharu active gate、metrics 或 `output`。
- 新增 `scripts/test-v3103-koharu-promotion-boundary-context-contract.py`，接入 UI interaction/full fail-fast；项目 marketing version 与 CI 路由同步到 3.103。首次候选 full `31010607288` 暴露 v3.96 历史合同的精确 warning 分支锚点，已恢复兼容并以 exact SHA 重跑。

云端证据：

- 候选 full [31011231211](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31011231211)：exact candidate SHA `4705641b...`，`validationProfile=full`、Xcode build success，静态/Speech/UI 合同 success，JUnit `10/10` 且 0 failures，`probe_mode=skip`。
- PR #167 fast [31011777761](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31011777761)：exact head SHA，`validationProfile=fast`，复用候选 full `4705641b.../success`，Xcode 与领域大套件按 fast 规则跳过，JUnit `10/10`；不作为新的编译证据。
- merge fast [31011846424](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31011846424)：merge SHA `3975dfa1...`，`validationReason=merge_reuses_successful_candidate_full_validation`，复用 `4705641b.../success`，`receiptPropagationAllowed=true`，Xcode 跳过，JUnit `10/10` 且 0 failures。

本轮没有更新 `metrics/version_history.csv` 或仓库 `output/`；候选、PR/merge 默认跳过漫画探针，没有新的 OCR/翻译指标。Koharu active artifact gate 仍为 `manifestMissing / stopUntilArtifactsProvided`，真实 `test/koharu_artifacts/` 四件套、Speech corpus 与真实竖排图片 corpus 仍缺失；本版只改善诊断可理解性，不声称 OCR、翻译、识别或 Koharu 质量提升。

## v3.102：暴露漫画探针逐块执行边界

日期：2026-08-05

状态：Agent X 已完成 v3.102 Developer Console 漫画探针逐块 report-only 执行边界上下文、候选 full、PR fast、merge fast 云端验收并合入 `smalldata_test`；工程正式版本为 `MARKETING_VERSION=3.102`。候选 commit `ac5210b1ef6bf89e095bc6fde743cfbcb96aa1b6` 已通过 PR [#166](https://github.com/bengzhu/project1_lgbt_naxida/pull/166) 合入，merge SHA `9df791928b1a9ef6e6cb3c93af0d535673b40cf1`，远端候选分支已删除，`main` 未触碰。

核心变更：

- `MangaProbeBlockRow` 只读消费既有 `MangaKoharuPipelineResolverBlockTrace`、`MangaKoharuWorkOrderBlockRoute`、`MangaKoharuExternalArtifactBlockRequest` 与 `MangaKoharuNativeReplayBlockRoute`，把目标执行项、首阻断、CI-fast/full/外部工件门、预算、目标工件、禁止本地调参与 shadow-only 状态归纳为“执行边界”。
- 执行边界与 v3.101 诊断依据、v3.100 推荐下一步、Koharu 工件门共用视觉与 VoiceOver summary；若没有传统 action/gate 仍会显示已有执行报告上下文。改动不新增 Store／持久化、不运行第二次探针、不读取 ground truth，不改变 OCR 候选、翻译 prompt/model、renderer/export、普通图片 OCR、Koharu active gate、metrics 或 `output`。
- 新增 `scripts/test-v3102-koharu-block-execution-boundary-contract.py` 并接入 UI interaction/full fail-fast。

云端证据：

- 候选 full [31009117560](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31009117560)：exact candidate SHA，`validationProfile=full`，Xcode build success，static/Speech/UI/home/paste contracts success，JUnit `10/10` 且 0 failures，`probe_mode=skip`。
- PR fast [31009686004](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31009686004)：exact head SHA，`validationProfile=fast`，复用候选 full `ac5210b1.../success`，Xcode 与领域合同按 fast 规则跳过，JUnit `10/10` 且 0 failures；不作为新的编译证据。
- merge fast [31009749466](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31009749466)：merge SHA `9df79192...`，`validationReason=merge_reuses_successful_candidate_full_validation`，复用 `ac5210b1.../success`，`receiptPropagationAllowed=true`，Xcode 跳过，JUnit `10/10` 且 0 failures，`probe_mode=skip`。

本版没有新的漫画探针指标或仓库 `output` 更新；真实 Koharu 四件套、Speech corpus 与真实竖排图片 corpus 仍缺失，readiness 仍不能作为 OCR、翻译、识别或 Koharu 质量提升证据。

## v3.101：暴露漫画探针逐块诊断依据上下文

日期：2026-08-05

状态：Agent X 已完成 v3.101 Developer Console 漫画探针逐块 report-only 诊断依据上下文、候选 full、PR fast、merge fast 云端验收并合入 `smalldata_test`；工程正式版本为 `MARKETING_VERSION=3.101`。候选 commit `69de7d9617413aa90be506d2cc8baa1ba4c31a2d` 已通过 PR [#165](https://github.com/bengzhu/project1_lgbt_naxida/pull/165) 合入，merge SHA `e088e4396d232c99a7fb013b02e95eec6d87dbf7`，远端候选分支已删除，`main` 未触碰。

核心变更：

- `MangaProbeBlockRow` 只读消费 `MangaOverlayInternalStructureBottleneckBlock`、`MangaTranslationModelFloorNoisyBlockSummary`、`MangaKoharuRenderSpriteFitBlockLedger` 和 `MangaKoharuArtifactBlockTrace` 的既有字段，将 OCR 字符损伤、气泡拆分/归属、模型底线、字号预算与首阻断阶段归纳为“依据”。
- 诊断依据、v3.100 推荐下一步和真实 Koharu 工件门控共用视觉与 VoiceOver summary；未知值安全回退，空阶段不伪造依据。改动不新增 Store／持久化、不运行第二次探针、不读取 ground truth，不改变 OCR 候选、翻译 prompt/model、renderer/export、普通图片 OCR、Koharu active gate、metrics 或 `output`。
- 新增 `scripts/test-v3101-koharu-block-diagnostic-evidence-context-contract.py` 并接入 UI interaction/full fail-fast。

云端证据：

- 候选 full [30993659770](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/30993659770)：exact candidate SHA，`validationProfile=full`，Xcode build success，static/Speech/UI/home/paste contracts success，JUnit `10/10` 且 0 failures，`probe_mode=skip`。
- PR fast [30994207268](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/30994207268)：exact head SHA，`validationProfile=fast`，复用候选 full `69de7d96.../success`，Xcode 与领域合同按 fast 规则跳过，JUnit `10/10` 且 0 failures；不作为新的编译证据。
- merge fast [30994272480](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/30994272480)：merge SHA `e088e439...`，`validationReason=merge_reuses_successful_candidate_full_validation`，复用 `69de7d96.../success`，`receiptPropagationAllowed=true`，Xcode 跳过，JUnit `10/10` 且 0 failures，`probe_mode=skip`。

本版没有新的漫画探针指标或仓库 `output` 更新；真实 Koharu 四件套、Speech corpus 与真实竖排图片 corpus 仍缺失，readiness 仍不能作为 OCR、翻译、识别或 Koharu 质量提升证据。

## v3.100：暴露漫画探针逐块推荐下一步上下文

日期：2026-08-05

状态：Agent X 已完成 v3.100 Developer Console 漫画探针逐块 report-only 推荐下一步上下文、候选 full、PR fast、merge fast 云端验收并合入 `smalldata_test`；工程正式版本为 `MARKETING_VERSION=3.100`。候选 commit `1009b4cbb522a3fb8b7077c0788870b6951d4d45` 已通过 PR [#164](https://github.com/bengzhu/project1_lgbt_naxida/pull/164) 合入，merge SHA `4764dea3b9ee5547b6d11d6f5b5c57c7bb45e3d2`，远端候选分支已删除，`main` 未触碰。

核心变更：

- `MangaProbeBlockRow` 只读消费 `MangaOverlayProbeReport` 既有 internal structure bottleneck、translation model-floor、Koharu render fit 和 artifact DAG block ledger，按优先级在逐块行显示“比较提示词或模型”“补充文本框/segment 证据”“复核气泡拆分/归属”“先确认模型底线”或“保留布局报告”等推荐下一步。
- 同一推荐动作进入 VoiceOver value/hint；若 block 有 artifact DAG trace，视觉与无障碍上下文继续显示“提供真实 Koharu 工件”门控，避免把 report-only 建议误解为已可推广的主流程改动。
- 新增 `scripts/test-v3100-koharu-block-next-action-context-contract.py` 并接入 UI interaction/full fail-fast；不新增 Store／持久化、不运行第二次探针、不读取 ground truth，不改变 OCR 候选、翻译 prompt/model、renderer/export、普通图片 OCR、Koharu active gate、metrics 或 `output`。

云端证据：

- 候选 full [30992318412](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/30992318412)：exact candidate SHA，`validationProfile=full`，Xcode build success，static/Speech/UI/home/paste contracts success，JUnit `10/10` 且 0 failures，`probe_mode=skip`。
- PR fast [30992932438](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/30992932438)：exact head SHA，`validationProfile=fast`，复用候选 full `1009b4cb.../success`，Xcode 与领域合同按 fast 规则跳过，JUnit `10/10` 且 0 failures；不作为新的编译证据。
- merge fast [30993004271](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/30993004271)：merge SHA `4764dea3...`，`validationReason=merge_reuses_successful_candidate_full_validation`，复用 `1009b4cb.../success`，`receiptPropagationAllowed=true`，Xcode 跳过，JUnit `10/10` 且 0 failures，`probe_mode=skip`。

本版没有新的漫画探针指标或仓库 `output` 更新；真实 Koharu 四件套、Speech corpus 与真实竖排图片 corpus 仍缺失，readiness 仍不能作为 OCR、翻译、识别或 Koharu 质量提升证据。

## v3.99：暴露漫画探针逐块风险上下文

日期：2026-08-05

状态：Agent X 已完成 v3.99 Developer Console 漫画探针逐块 OCR／翻译／布局风险上下文、候选 full、PR fast、merge fast 云端验收并合入 `smalldata_test`；工程正式版本为 `MARKETING_VERSION=3.99`。候选 commit `02ec1de4520208a6d83d69ea782a4dc15fadc1c3` 已通过 PR [#163](https://github.com/bengzhu/project1_lgbt_naxida/pull/163) 合入，merge SHA `330716f3cde30cd03f4f4ab1c0281bfcad00648b`，远端候选分支已删除，`main` 未触碰。

核心变更：

- `MangaProbeSection` 将当前只读 `MangaOverlayProbeReport` 传给逐块 `MangaProbeBlockRow`；行复用 `mangaProbeOCRRiskBlockSet`、`mangaProbeTranslationRiskBlockSet` 与 `mangaProbeRenderRiskBlockSet`，在失败行旁显示“风险：OCR／翻译／布局”标签。
- 同一 `reportRiskSummary` 进入逐块 VoiceOver value/hint；无报告时回退为“无额外风险”，避免筛选结果缺少解释。所有上下文仅消费 report，不写 Store／持久化，不运行第二次探针，不读取 ground truth，不改变 OCR 候选、翻译 prompt/model、renderer/export、普通图片 OCR、Koharu active gate、metrics 或 `output`。
- 新增 `scripts/test-v399-koharu-block-risk-context-contract.py`，接入 UI interaction/full fail-fast；项目 marketing version 与 CI 路由同步到 3.99。

验证：

- 本地轻量检查：v3.99 合同、v3.98–v3.91 相关合同、Swift `-parse`、版本解析、workflow/ground-truth JSON smoke 与 `git diff --check` 通过；第一次云端 full 暴露并修复缺少显式 `return` 的 Swift 类型检查问题。
- 候选 full [30991030339](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/30991030339)：exact candidate SHA，`validationProfile=full`、`validationReason=candidate_development_push`、Xcode build success；静态/Speech/UI/home/paste 合同 success，JUnit `10/10`、0 failures；`probeMode=skip`。
- PR #163 fast [30991418709](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/30991418709)：exact head SHA，`validationProfile=fast`、Xcode skipped，`reusedFullValidationSha=02ec1de4`、state `success`，JUnit `10/10`；该包不是新的编译证据。
- merge fast [30991478674](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/30991478674)：exact merge SHA，`validationReason=merge_reuses_successful_candidate_full_validation`，复用候选 full `02ec1de4`/`success`，`receiptPropagationAllowed=true`，Xcode skipped，JUnit `10/10`。

限制与遗留：

本轮未更新 `metrics/version_history.csv` 或仓库 `output/`；候选/PR/merge 默认跳过漫画探针，没有新的 OCR/翻译指标。Koharu active artifact gate 仍为 `manifestMissing / stopUntilArtifactsProvided`，真实 `test/koharu_artifacts/` 四件套、Speech corpus 与真实竖排图片 corpus 仍缺失；本版只改善 report-only 诊断可理解性，不声称 OCR、翻译、识别或 Koharu 质量提升。

## v3.98：统一漫画探针 OCR/翻译诊断风险集合

日期：2026-08-05

状态：Agent X 已完成 v3.98 Developer Console 漫画探针 OCR/翻译筛选与 triage 摘要对齐、候选 full、PR fast、merge fast 云端验收并合入 `smalldata_test`；工程正式版本为 `MARKETING_VERSION=3.98`。候选 commit `7a352a5050c8846765ad4b139e7a6a125dfb4712` 已通过 PR [#162](https://github.com/bengzhu/project1_lgbt_naxida/pull/162) 合入，merge SHA `3b953b83d12a092df1995c974cb33522dc02331a`，远端候选分支已删除，`main` 未触碰。

核心变更：

- `MangaProbeDiagnosticFilter.ocr` 与 `MangaProbeDiagnosticTriageSummary.ocrBlocks` 共享 `mangaProbeOCRRiskBlockSet`，并集既有 diagnostics 的 OCR 疑似/可用译文但 OCR 疑似、model-floor OCR 疑似和 `ocrInputSuspect` category，避免 floor 报告存在时使用 `??` 丢掉 diagnostics。
- `MangaProbeDiagnosticFilter.translation` 与 `MangaProbeDiagnosticTriageSummary.translationBlocks` 共享 `mangaProbeTranslationRiskBlockSet`，并集既有 diagnostics translation-language failures、model-floor model/language blocks 与 `modelOutputFailure`/`translationLanguageQualityFailure` category；筛选与摘要现在消费同一口径。
- 新增 `scripts/test-v398-koharu-diagnostic-risk-union-contract.py`，接入 CI UI/full 路由；改动只读 `MangaOverlayProbeReport`，不新增 Store／持久化、不运行探针、不改变 OCR 候选、翻译 prompt/model、renderer/export、普通图片 OCR、Koharu active gate、metrics 或仓库 `output`。

验证：

- 本地轻量检查：v3.98 合同、v3.97–v3.92 相关合同、Swift `-parse`、项目版本解析、workflow/ground-truth JSON smoke、CI tier/version contracts 与 `git diff --check` 通过；未跑本机完整 build 或漫画探针。
- 候选 full [30988262491](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/30988262491)：exact candidate SHA，`validationProfile=full`、`validationReason=candidate_development_push`、Xcode build success；静态/Speech/UI/home/paste 合同 success，JUnit `10/10`、0 failures；`probeMode=skip`。
- PR #162 fast [30988802078](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/30988802078)：exact head SHA，`validationProfile=fast`、Xcode skipped，`reusedFullValidationSha=7a352a50`、state `success`，JUnit `10/10`；该包不是新的编译证据。
- merge fast [30988876405](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/30988876405)：exact merge SHA，`validationReason=merge_reuses_successful_candidate_full_validation`，复用候选 full `7a352a50`/`success`，`receiptPropagationAllowed=true`，Xcode skipped，JUnit `10/10`。

限制与遗留：

本轮未更新 `metrics/version_history.csv` 或仓库 `output/`；候选/PR/merge fast 默认跳过漫画探针，没有新的 OCR/翻译指标。Koharu active artifact gate 仍为 `manifestMissing / stopUntilArtifactsProvided`，真实 `test/koharu_artifacts/` 四件套、Speech corpus 与真实竖排图片 corpus 仍缺失；本版只改善 report-only 分流一致性，不声称 OCR、翻译、识别或 Koharu 质量提升。

## v3.97：补齐漫画探针布局风险分流

日期：2026-08-05

状态：Agent X 已完成 v3.97 漫画探针布局风险筛选/triage 对齐、候选 full、PR fast、merge fast 云端验收并合入 `smalldata_test`；工程正式版本为 `MARKETING_VERSION=3.97`。候选 commit `c552e6170cfd7b6daab4cbebd885bdb44314b007` 已通过 PR [#161](https://github.com/bengzhu/project1_lgbt_naxida/pull/161) 合入，merge SHA 为 `87b102cdd0d8f08bcea876cfcd08645ddc10cc58`；远端候选分支已删除，`main` 未触碰。

核心变更：

- 新增 View 私有 `mangaProbeRenderRiskBlockSet(_:)`，让布局筛选与 `MangaProbeDiagnosticTriageSummary.renderBlocks` 共享既有顶层 diagnostics、fit planner 与 render-lock 风险信号；纳入字号预算紧张、sprite containment、sibling overlap、failure overlay、render issue/min-font/truncation blocks。
- v3.97 修复前，fresh ci-fast [30986469563](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/30986469563) 的 report 已标出 `fontBudgetRiskBlocks=10`、`spriteContainmentRiskBlocks=7`、`siblingOverlapRiskBlocks=6`，但顶层 unresolved/truncated 数组为空，Developer Console 的布局 triage/筛选会显示 0；本版只修正报告可理解性，不提升或改变 OCR/翻译/渲染质量。
- 新增 `scripts/test-v397-koharu-layout-triage-contract.py`，接入 UI interaction/full fail-fast；不新增 Store／持久化、不调用探针、不读取 ground truth。

验证：

- 本地轻量检查：v3.97 合同（3 tests）、v3.96/v3.95/v3.94/v3.93/v3.92 相关合同、版本解析、workflow/ground-truth JSON smoke、`git diff --check` 通过；未跑本机完整 Xcode build 或漫画探针。
- 候选 full [30987210261](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/30987210261)：exact candidate SHA，`validationProfile=full`、`validationReason=candidate_development_push`、`xcodeBuildRequired=true`，Xcode build success；static/UI/Speech/home/paste/Koharu 合同通过，JUnit `10/10`、0 failures；`probeMode=skip`，结果包保存在 `/private/tmp/aitrans-c-review-30987210261`。
- PR #161 fast [30987676638](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/30987676638)：exact head SHA，`validationProfile=fast`、`xcodeBuildRequired=false`，复用候选 full receipt `c552e617 / success`，JUnit `10/10`；该 fast 包不是新的编译证据，结果包保存在 `/private/tmp/aitrans-c-review-30987676638`。
- merge fast [30987725142](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/30987725142)：exact merge SHA `87b102cd`，`validationReason=merge_reuses_successful_candidate_full_validation`，复用候选 full `c552e617 / success`，`receiptPropagationAllowed=true`，Xcode skipped，JUnit `10/10`；结果包保存在 `/private/tmp/aitrans-c-review-30987725142`。

限制与遗留：

本轮未更新 `metrics/version_history.csv` 或仓库 `output/`；v3.97 候选/PR/merge fast 默认 `probe_mode=skip`，ci-fast `30986469563` 仅作为新鲜诊断依据，不替代质量基线。Koharu active artifact gate 仍为 `manifestMissing / stopUntilArtifactsProvided`，真实 `test/koharu_artifacts/` 四件套、Speech corpus 与真实竖排图片 corpus 仍缺失；本版只改善布局风险分流可见性，不声称 OCR、翻译、识别或 Koharu 质量提升。

## v3.96：对齐 Koharu readiness 分流状态色

日期：2026-08-05

状态：Agent X 已完成 v3.96 Developer Console Koharu readiness 状态色修复、候选 full、PR fast、merge fast 云端验收并合入 `smalldata_test`；工程正式版本为 `MARKETING_VERSION=3.96`。候选 commit `ab4d0ae59fbf2e0d6c6747fce331060ecfcc57ee` 已通过 PR [#160](https://github.com/bengzhu/project1_lgbt_naxida/pull/160) 合入，merge SHA 为 `12140ca11d3e888e74a974dffcfda41a0ca8357d`；远端候选分支已删除，`main` 未触碰。

核心变更：

- `MangaProbeDiagnosticTriageSummary.statusTone` 先判断既有 `artifactBlocked`，阻断时固定使用 warning；只有 readiness 不阻断且既有 `report.overallPassed` 时才显示 success，避免缺少真实 Koharu 四件套时把“等待真实 Koharu 工件”误显示成成功色。
- 新增 `scripts/test-v396-koharu-triage-tone-contract.py`，验证 warning 优先级、View-only/report-only 边界和 CI/version 路由；不新增 Store／持久化、不调用探针、不读取 ground truth，不改变 OCR、翻译 prompt/model、renderer/export、普通图片 OCR 或 active artifact gate。

验证：

- 本地轻量检查：v3.96 合同（3 tests）、v3.95/v3.94/v3.91 相关合同、版本解析、workflow/ground-truth JSON smoke、`git diff --check` 通过；未跑本机完整 Xcode build 或漫画探针。
- 候选 full [30985776084](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/30985776084)：exact candidate SHA，`validationProfile=full`、`validationReason=candidate_development_push`、`xcodeBuildRequired=true`，Xcode build success；static/UI/Speech/home/paste/Koharu 合同通过，JUnit `10/10`、0 failures；`probeMode=skip`，结果包保存在 `/private/tmp/aitrans-c-review-30985776084`。
- PR #160 fast [30986258687](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/30986258687)：exact head SHA，`validationProfile=fast`、`xcodeBuildRequired=false`，复用候选 full receipt `ab4d0ae5 / success`，JUnit `10/10`；该 fast 包不是新的编译证据，结果包保存在 `/private/tmp/aitrans-c-review-30986258687`。
- merge fast [30986307343](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/30986307343)：exact merge SHA `12140ca1`，`validationReason=merge_reuses_successful_candidate_full_validation`，复用候选 full `ab4d0ae5 / success`，`receiptPropagationAllowed=true`，Xcode skipped，JUnit `10/10`；结果包保存在 `/private/tmp/aitrans-c-review-30986307343`。

限制与遗留：

本轮未更新 `metrics/version_history.csv` 或仓库 `output/`；候选、PR/merge fast 默认 `probe_mode=skip`，没有新的 OCR/翻译指标。Koharu active artifact gate 仍为 `manifestMissing / stopUntilArtifactsProvided`，真实 `test/koharu_artifacts/` 四件套、Speech corpus 与真实竖排图片 corpus 仍缺失；本版只修正诊断状态色语义，不声称 OCR、翻译、识别或 Koharu 质量提升。

## v3.95：明确漫画探针无 blocks 的诊断空态

日期：2026-08-05

状态：Agent X 已完成 v3.95 漫画探针空 blocks 诊断 UX、候选 full、PR fast、merge fast 云端验收并合入 `smalldata_test`；工程正式版本为 `MARKETING_VERSION=3.95`。候选 commit `802103e413261cc1632d1129362695728af45215` 已通过 PR [#159](https://github.com/bengzhu/project1_lgbt_naxida/pull/159) 合入，merge SHA 为 `a57e65b2c8220de39b59177ec873a394a3398781`；远端候选分支已删除，`main` 未触碰。

核心变更：

- `MangaProbeSection` 在已有探针报告但 `mangaOverlayProbeBlocks` 为空时显示明确的“本次探针未生成文字块”状态和空态，不再把结果误报为“当前诊断筛选没有结果”，并隐藏不适用的全部／失败／OCR／翻译／布局筛选器；存在 blocks 时保留既有只读筛选与逐块诊断。
- 空 blocks 状态通过 View 私有详情复用现有 `mangaOverlayProbeMessage`，并以 VoiceOver label/value/hint 说明没有可展示的逐块 OCR 结果和重试范围（bundle `test/1.png`、App 沙盒 `Output`）；不新增 Store／持久化，不运行第二次探针，不读取 ground truth。
- 新增 `scripts/test-v395-manga-probe-empty-state-contract.py`，接入 UI interaction/full fail-fast；项目 marketing version 与 CI changed-file route 同步到 3.95。

验证：

- 本地轻量检查：v3.95 合同（3 tests）、v3.94/v3.93/v3.92 相关合同、版本解析、workflow/ground-truth JSON smoke、`git diff --check` 通过；未跑本机完整 Xcode build 或漫画探针。
- 候选 full [30984932342](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/30984932342)：exact candidate SHA，`validationProfile=full`、`validationReason=candidate_development_push`、`xcodeBuildRequired=true`，Xcode build success；static/UI/Speech/home/paste/Koharu 合同通过，JUnit `10/10`、0 failures；`probeMode=skip`，结果包保存在 `/private/tmp/aitrans-c-review-30984932342`。
- PR #159 fast [30985360673](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/30985360673)：exact head SHA，`validationProfile=fast`、`xcodeBuildRequired=false`，复用候选 full receipt `802103e4 / success`，JUnit `10/10`；该 fast 包不是新的编译证据，结果包保存在 `/private/tmp/aitrans-c-review-30985360673`。
- merge fast [30985413482](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/30985413482)：exact merge SHA `a57e65b2`，`validationReason=merge_reuses_successful_candidate_full_validation`，复用候选 full `802103e4 / success`，`receiptPropagationAllowed=true`，Xcode skipped，JUnit `10/10`；结果包保存在 `/private/tmp/aitrans-c-review-30985413482`。

限制与遗留：

本轮未更新 `metrics/version_history.csv` 或仓库 `output/`；候选、PR/merge fast 默认 `probe_mode=skip`，没有新的 OCR/翻译指标。Koharu active artifact gate 仍为 `manifestMissing / stopUntilArtifactsProvided`，真实 `test/koharu_artifacts/` 四件套、Speech corpus 与真实竖排图片 corpus 仍缺失；本版只改善无 blocks 时的诊断可理解性，不声称 OCR、翻译、识别或 Koharu 质量提升。

## v3.94：隔离漫画探针失败入口的旧状态与旧输出

日期：2026-08-05

状态：Agent X 已完成 v3.94 漫画探针失败入口修复、候选 full、PR fast、merge fast 云端验收并合入 `smalldata_test`；工程正式版本为 `MARKETING_VERSION=3.94`。候选 commit `31c61bf0a682d8a0e28376a123285f037272a60e` 已通过 PR [#158](https://github.com/bengzhu/project1_lgbt_naxida/pull/158) 合入，merge SHA 为 `ea6be1ddacaa34953b0c7f3389c342dc6e9ff4e3`；远端候选分支已删除，`main` 未触碰。

核心变更：

- `runMangaOverlayProbe()` 把每次调用视为新尝试：在查找 bundle 内 `test/1.png` 前清空上一轮 `mangaOverlayProbeReport` 与 `mangaOverlayProbeBlocks`，让缺失图片、读取错误或新运行不会继续展示旧 blocks。
- 缺失 `test/1.png` 时先重建 App 沙盒 `Output`，失败报告传播 `outputCleanupRemovedItemCount` 与 `outputDirectoryCleaned`；清理失败时 `outputCleanupPolicy` 明确旧输出可能残留，不能被当成本轮 PNG/JSON。正常异步失败也传播同一清理状态。
- 新增 `scripts/test-v394-manga-probe-failure-cleanup-contract.py`，并接入 Koharu changed-file/full 路由；不新增 OCR/LLM 调用，不改变 OCR 候选、翻译 prompt/model、ground truth、生产 renderer/export、普通图片 OCR、Koharu active artifact gate、metrics 或仓库 `output`。

验证：

- 本地轻量检查：v3.94 新合同、v3.92/v3.93 风险与筛选合同、v3.82–v3.91 相关 Koharu 合同、`git diff --check`、项目版本解析、ground-truth JSON 和 workflow YAML smoke 通过；未跑本机完整 Xcode build 或漫画探针。
- 候选 full [30893309273](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/30893309273)：exact candidate SHA，`validationProfile=full`、`xcodeBuildRequired=true`、Xcode success，静态/UI/Speech/home/paste/Koharu 合同通过，JUnit `10/10`、0 failures；`probeMode=skip`，结果包保存在 `/private/tmp/aitrans-c-review-30893309273`。
- PR #158 fast [30893920011](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/30893920011)：exact head SHA，`validationProfile=fast`、`xcodeBuildRequired=false`，复用 full receipt `31c61bf0 / success`，JUnit `10/10`；该 fast 包不是新的编译证据，结果包保存在 `/private/tmp/aitrans-c-review-30893920011`。
- merge fast [30893993759](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/30893993759)：exact merge SHA `ea6be1dd`，`validationReason=merge_reuses_successful_candidate_full_validation`，复用候选 full `31c61bf0 / success`，`receiptPropagationAllowed=true`，Xcode skipped，JUnit `10/10`；结果包保存在 `/private/tmp/aitrans-c-review-30893993759`。

限制与遗留：

本轮未更新 `metrics/version_history.csv` 或仓库 `output/`；候选、PR/merge fast 默认 `probe_mode=skip`。Koharu active artifact gate 仍为 `manifestMissing / stopUntilArtifactsProvided`，真实 `test/koharu_artifacts/` 四件套、Speech corpus 与真实竖排图片 corpus 仍缺失；本版只改善失败入口的状态/输出隔离，不声称 OCR、翻译、识别或 Koharu 质量提升。

## v3.93：重置跨图片残留的 OCR 复查筛选
日期：2026-08-04

状态：Agent X 已完成普通图片复查筛选的 revision-scoped UX 修复，完成候选 full、PR fast、merge fast 云端验收并合入 `smalldata_test`；工程正式版本为 `MARKETING_VERSION=3.93`。候选分支 `codeb/v3.93-image-filter-reset` 的最终 SHA `a3cea5a202f1de8a9b13aa4809db583b55480dcd` 已通过 PR [#157](https://github.com/bengzhu/project1_lgbt_naxida/pull/157) 合入，merge SHA 为 `3f6565f65cc8ff965ba909f5d6e27ad0a508436c`；远端候选分支已删除，`main` 未触碰。

核心变更：

- `ImageTranslationPanel` 在既有 Store `imageTranslationRevision` 变化时将 View 私有 `reviewFilter` 恢复为 `.all`，同时沿用已有 revision handler 清除旧 selected block、编辑/恢复状态和 VoiceOver focus。新图片、重试、重新识别和清空不会继承上一张图片的低置信／方向待定筛选，避免新结果误显示为空。
- 该修复不把筛选写入 Store／持久化，不改变 `imageTranslationBlocks`、Vision OCR、模型翻译、预览、renderer/export、漫画探针、Koharu readiness、metrics 或 output；新增 `scripts/test-v393-image-review-filter-reset-contract.py`，并将 v3.92 合同版本门升级为接受后续正式版本。

验证：

- 本地轻量检查：v3.93/v3.92/v3.10/v3.80/v1.87 合同、`git diff --check`、项目版本解析和 workflow YAML smoke 通过；未跑本机完整 Xcode build 或漫画探针。
- 候选 full run [30890823578](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/30890823578)：manifest 精确匹配 v3.93、候选 branch、SHA、run/attempt/workflow，`validationProfile=full`、`xcodeBuildRequired=true`、Xcode success、UI/Speech/home/paste/Koharu 合同通过，JUnit `10/10`、0 failures，并发布 `AITRANS CI/full-validation=success`；`probeMode=skip`，结果包保存在 `/private/tmp/aitrans-c-review-30890823578`。
- PR #157 fast run [30891431628](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/30891431628)：精确 head SHA，`validationProfile=fast`、`xcodeBuildRequired=false`，复用候选 full receipt `a3cea5a2 / success`，JUnit `10/10`；该 fast 包不是新的编译证据，结果包保存在 `/private/tmp/aitrans-c-review-30891431628`。
- merge fast run [30891485989](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/30891485989)：精确 merge SHA `3f6565f6`，`validationReason=merge_reuses_successful_candidate_full_validation`，复用候选 full receipt `a3cea5a2 / success`，`receiptPropagationAllowed=true`，Xcode skipped，JUnit `10/10`；结果包保存在 `/private/tmp/aitrans-c-review-30891485989`。

限制与遗留：

本轮未更新 `metrics/version_history.csv` 或仓库 `output/`；push 与 fast 均按默认跳过漫画探针。Koharu active artifact gate 仍为 `manifestMissing / stopUntilArtifactsProvided`，真实 `test/koharu_artifacts/` 四件套、Speech corpus 与真实竖排图片 corpus 仍缺失；本版不声称 OCR、翻译、识别或 Koharu 质量提升。

## v3.92：图片 OCR 风险筛选与漫画诊断筛选
日期：2026-08-04

状态：Agent X 已完成图片复查风险分层与漫画探针只读诊断筛选，完成候选 full、PR fast、merge fast 云端验收并合入 `smalldata_test`；工程正式版本为 `MARKETING_VERSION=3.92`。候选分支 `codeb/v3.92-image-risk-triage` 的最终 SHA `83a3e30d25483cb67d788babd4998f05afb42c08` 已通过 PR [#156](https://github.com/bengzhu/project1_lgbt_naxida/pull/156) 合入，merge SHA 为 `118c8c039d752a24a6c992e8f942ec34cb43e009`；远端候选分支已删除，`main` 未触碰。

核心变更：

- `ImageOCRReviewFilter` 增加 `lowConfidence` 与 `unknownDirection`，复用 `ImageOCRResultSummary.hasLowConfidence`／`hasUnknownDirection`；`needsReview` 仍是两类风险的并集。筛选、具体 VoiceOver hint、无结果空态和忽略文字块后的当前筛选定位属于 View/本地复查展示，不新增 Store／持久化，不改变 `ImageTranslationBlock`、图片预览、导出、Vision OCR 或翻译链路。
- Developer Console 增加 `MangaProbeDiagnosticFilter` 与窄屏 Menu fallback，按全部／失败／OCR／翻译／布局筛选逐块探针结果；只读消费既有 `MangaOverlayProbeReport` 的 diagnostics、failureCategory 与 render flags，探针进入载入阶段时重置筛选，不修改报告、OCR 候选、翻译 prompt／model、renderer/export、metrics 或 output。
- 新增 `scripts/test-v392-image-review-risk-filter-contract.py` 和 `scripts/test-v392-image-review-risk-filter-evaluator.swift`，接入 UI interaction/full 路由。

验证：

- 本地轻量检查：v3.92 evaluator/contract、v3.91、v3.10、v3.80、v1.87 合同，`git diff --check`、ground-truth JSON 和 workflow YAML 通过；未跑本机完整 Xcode build 或漫画探针。
- 候选 full run [30889811326](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/30889811326)：manifest 精确匹配 v3.92、候选 branch、SHA、run/attempt/workflow，`validationProfile=full`、`xcodeBuildRequired=true`、Xcode success、JUnit `10/10`、全量 UI 合同通过，并发布 `AITRANS CI/full-validation=success`；push `probeMode=skip`，结果包保存在 `/private/tmp/aitrans-c-review-30889811326`。
- PR #156 fast run [30890241624](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/30890241624)：精确 head SHA，`validationProfile=fast`、`xcodeBuildRequired=false`，复用 full receipt `83a3e30d / success`，JUnit `10/10`；该 fast 包不是新的编译证据，结果包保存在 `/private/tmp/aitrans-c-review-30890241624`。
- merge fast run [30890322575](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/30890322575)：精确 merge SHA `118c8c03`，`validationReason=merge_reuses_successful_candidate_full_validation`，复用候选 full receipt `83a3e30d / success`，`receiptPropagationAllowed=true`，Xcode skipped，JUnit `10/10`；结果包保存在 `/private/tmp/aitrans-c-review-30890322575`。

限制与遗留：

本轮未更新 `metrics/version_history.csv` 或仓库 `output/`；push 与 fast 均按默认跳过漫画探针。Koharu active artifact gate 仍为 `manifestMissing / stopUntilArtifactsProvided`，真实 `test/koharu_artifacts/` 四件套、Speech corpus 与真实竖排图片 corpus 仍缺失；本版不声称 OCR、翻译、识别或 Koharu 质量提升。

# 项目版本更新记录
本文记录 AITRANS 的正式版本、重要维护事项、关键决策和遗留问题。README 不再写更新记录；细节证据优先看本日志、`metrics/version_history.csv`、最新 `output/` 和 git 提交。

## 维护规则
- 每完成一个正式版本或重要任务后追加记录。
- 记录必须包含：版本或任务名、日期、核心变更、关键文件、验证结果、遗留事项。
- 文档整理、目录迁移、回滚、打捞等不伪装成新版本，写入“历史维护记录”。
- 若核心逻辑、测试规范或项目行为变化，必须同步更新本日志、`md/flow/flow.md`、`md/flow/flowchart.md` 或 `md/test/test.md`。
- 涉及漫画探针或翻译链路的可量化版本时，`metrics/version_history.csv` 必须 append-only 更新；README 不再追加近期记录。

## v3.91：开发控制台漫画探针诊断分流
日期：2026-08-04

状态：Agent X 已完成 report-only 诊断 UX、云端 full/ci-fast/PR fast/merge fast 验收、PR 合并和 `smalldata_test` 文档收口；工程正式版本为 `MARKETING_VERSION=3.91`。候选分支 `codeb/v3.91-koharu-diagnostic-triage` 的最终 SHA `bbb73b14a90a10438d4cacf46344881d21d6206e` 已通过 PR [#155](https://github.com/bengzhu/project1_lgbt_naxida/pull/155) 合入 `smalldata_test`，merge SHA 为 `1ab18c3e9f2d04fbd51680b5b1b606113d86d032`，远端候选分支已删除，`main` 未触碰。

核心变更：

- Developer Console 新增 `MangaProbeDiagnosticTriageSummary`，只读消费既有 `MangaOverlayProbeReport`：按 OCR 疑似、翻译模型／语言质量、覆盖布局异常和 Koharu 工件 readiness 汇总状态与下一步，并复制 baseline／variant pass rate、floor verdict、`diagnosticOnly` 与 `wouldChangeMainFlow` 边界。
- `MangaProbeBlockRow` 在失败行显示既有 `failureCategory` 的“模型输出失败／译文质量失败／OCR 疑似损坏”标签，并让 VoiceOver 读出相同诊断分流；不新增 Store／持久化，不调用第二次探针，不改变 OCR 候选、翻译 prompt／model、renderer/export、metrics 或 output。
- 新增 `scripts/test-v391-koharu-diagnostic-triage-contract.py`，并接入 Koharu changed-file/full 静态路由；v3.88/v3.89 历史版本合同同步接受 3.91 及后续版本。

验证：

- 本地轻量检查：v3.82–v3.91 渲染/探针合同、既有 DeveloperConsole 无障碍合同、`git diff --check`、JSON/YAML smoke 通过；未跑本机 build / 探针，按规则交给云端。
- 候选 full run [30886955217](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/30886955217)：manifest 精确匹配 v3.91、候选 branch、SHA、run/attempt/workflow，`validationProfile=full`、`xcodeBuildRequired=true`；Xcode success，JUnit `10/10`、0 failures，`AITRANS CI/full-validation=success`；结果包保存在 `/private/tmp/aitrans-c-review-30886955217`。
- 同 SHA ci-fast 探针 run [30887582600](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/30887582600)：`probeMode=ci-fast`、GGUF SHA 校验、模拟器 build、漫画探针与 Output 导出成功，JUnit `10/10`；报告保持 13 blocks／12 failures、`renderLockVerdict=renderStableWithProxyBoundaries`、render issue/truncation/min-font 列表为空，model floor 为 `promptVariantRegresses`（baseline `0.4545`、variant `0`），`1_translated_overlay.png` 非空；结果包保存在 `/private/tmp/aitrans-c-review-30887582600`。
- PR #155 fast run [30888608909](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/30888608909)：精确 head SHA，`validationProfile=fast`、`xcodeBuildRequired=false`，复用 full receipt `bbb73b14 / success`，JUnit `10/10`；该 fast 包不是新的编译证据，结果包保存在 `/private/tmp/aitrans-c-review-30888608909`。
- merge fast run [30888676363](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/30888676363)：精确 merge SHA `1ab18c3e`，`validationReason=merge_reuses_successful_candidate_full_validation`，复用候选 full receipt `bbb73b14 / success`，`receiptPropagationAllowed=true`，Xcode skipped，JUnit `10/10`；结果包保存在 `/private/tmp/aitrans-c-review-30888676363`。

限制与遗留：

本轮未更新 `metrics/version_history.csv` 或仓库 `output/`；ci-fast 报告与 PNG 只用于验证探针输出和诊断摘要消费。Koharu active artifact gate 仍为 `manifestMissing / stopUntilArtifactsProvided`，真实 `test/koharu_artifacts/` 四件套、Speech corpus 与真实竖排图片 corpus 仍缺失；本版不声称 OCR、翻译、识别或 Koharu 质量提升。

## v3.90：压缩失败覆盖的 OCR fallback 换行
日期：2026-08-04

状态：Agent X 已完成 probe-render 显示修复、云端 full/ci-fast/PR fast/merge fast 验收、PR 合并和 `smalldata_test` 文档收口；工程正式版本为 `MARKETING_VERSION=3.90`。候选分支 `codeb/v3.90-koharu-failure-overlay-compaction` 的 commit `3344a8cd192684bf66e6cdff3397314c3fd8da05` 已通过 PR [#154](https://github.com/bengzhu/project1_lgbt_naxida/pull/154) 合入 `smalldata_test`，merge SHA 为 `ee6046d491f327d6c71744876e0a4b4b6aab3947`，远端候选分支已删除，`main` 未触碰。

核心变更：

- 漫画探针失败块仍保留完整 `翻译失败\nOCR 原文` fallback；新增 `failureOverlayDisplayText` 仅把 OCR continuation 的显式换行压缩为空格，保留失败标记与所有 OCR 内容。
- safe-layout diagnostics、`makeKoharuRenderSpriteFitPlannerReport` 和 `drawCollisionCheckedText` 共用该显示变换，使 fit plan 与实际覆盖绘制一致；不修改 OCR block、翻译输入、Store、普通图片 renderer/export 或 Koharu active artifact gate。
- 新增 `scripts/test-v390-koharu-render-failure-overlay-compaction-contract.py`，并同步 v3.82–v3.89 合同的版本兼容与 Koharu changed-file/full 路由。

验证：

- 本地轻量检查：v3.82–v3.90 合同、`git diff --check`、Swift `-parse`、项目版本解析、ground-truth JSON 与 CI YAML smoke 通过；未跑本机 build / 探针，按规则交给云端。
- 候选 full run [30884104150](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/30884104150)：manifest 精确匹配 v3.90、候选 branch、commit、run/attempt/workflow，`validationProfile=full`、`xcodeBuildRequired=true`；Xcode build success，JUnit `10/10`、0 failures，静态、Speech、UI、home、paste 与 Koharu 合同通过；结果包保存在 `/private/tmp/aitrans-c-review-30884104150`。
- 同 SHA ci-fast 探针 run [30884547044](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/30884547044)：manifest 精确匹配同一 SHA，`probeMode=ci-fast`、模拟器 build、Local GGUF 漫画探针与 Output 导出成功，JUnit `10/10`；`renderLockVerdict=renderStableWithProxyBoundaries`、`renderTextTruncatedBlocks=[]`，block 5 为 `renderTextTruncated=false`、`renderMinFontSizeReached=false`、`failureOverlayFitVerdict=failureFallbackAccounted`，`1_translated_overlay.png` 非空；结果包保存在 `/private/tmp/aitrans-c-review-30884547044`。
- PR #154 fast run [30885582974](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/30885582974)：精确 head SHA，`validationProfile=fast`、`xcodeBuildRequired=false`，复用候选 full receipt `3344a8cd / success`，JUnit `10/10`；该 fast 包不是新的编译证据，结果包保存在 `/private/tmp/aitrans-c-review-30885582974`。
- merge fast run [30885667505](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/30885667505)：精确 merge SHA `ee6046d4`，`validationReason=merge_reuses_successful_candidate_full_validation`，复用候选 full receipt `3344a8cd / success`，`receiptPropagationAllowed=true`，Xcode skipped，JUnit `10/10`；结果包保存在 `/private/tmp/aitrans-c-review-30885667505`。

限制与遗留：

本轮未更新 `metrics/version_history.csv` 或仓库 `output/`；ci-fast 报告和 PNG 仅用于 probe-render 诊断。Koharu active artifact gate 仍为 `manifestMissing / stopUntilArtifactsProvided`，真实 `test/koharu_artifacts/` 四件套、Speech corpus 与真实竖排图片 corpus 仍缺失；无论 block 5 的渲染锁改善如何，均不能据此声称 OCR、翻译、识别或 Koharu 质量提升。

## v3.89：暴露 render-lock 输出动作摘要
日期：2026-08-04

状态：Agent X 已完成 report-only 诊断 UX 修正、云端 full/ci-fast/PR fast/merge fast 验收、PR 合并和 `smalldata_test` 文档收口；工程正式版本为 `MARKETING_VERSION=3.89`。候选分支 `codeb/v3.89-render-output-summary-action` 的候选 HEAD 为 `6c51c33d873e4241faf04a5419501ebf9cfaa118`，PR [#153](https://github.com/bengzhu/project1_lgbt_naxida/pull/153) 已合入 `smalldata_test`，merge SHA 为 `fe6e373994706714c4d25312cc2a1dd600f91060`，远端候选分支已删除，`main` 未触碰。

核心变更：

- Developer Console 的 `outputFiles` 摘要现在按 required 输出分组汇总 `recommendedAction`，直接显示 `actionBreakdown=keepReportOnly=5` 等诊断动作；它只消费既有 `koharuRenderRegressionLockReport.outputFileChecks`，不改变 OCR 候选、翻译、生产 renderer/export、Store、Koharu active artifact gate、metrics 或仓库 `output/`。
- 新增 `scripts/test-v389-koharu-render-output-summary-action-contract.py`，同步 v3.82–v3.88 历史合同的版本兼容和 Koharu changed-file/full CI 路由；工程版本推进到 3.89。

验证：

- 本地轻量检查：v3.82–v3.89 合同、`git diff --check`、Swift `-parse`、项目版本解析、ground-truth JSON 与 CI YAML smoke 通过；未跑本机 build / 探针，按规则交给云端。
- 候选 full run [30882033347](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/30882033347)：manifest 精确匹配候选 branch、SHA、run/attempt/workflow，`validationProfile=full`、`xcodeBuildRequired=true`；Xcode build success，JUnit `10/10`、0 failures，静态、Speech、UI、home、paste 与 Koharu 合同通过；结果包保存在 `/private/tmp/aitrans-c-review-30882033347`。
- 同 SHA ci-fast 探针 run [30882428016](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/30882428016)：manifest 精确匹配同一 SHA，`probeMode=ci-fast`、`mangaProbeOutcome=success`，Xcode build success；输出 `1_ocr_probe_text.txt` 明确记录 `outputFiles: corePresent=true coreNonEmpty=true actionBreakdown=keepReportOnly=5 missing=none`。报告仍为 13 blocks，`renderLockVerdict=openRenderIssueDetected`，block 5 保留 `renderTextTruncated`／`G-render-no-text-truncation=blocked`；结果包保存在 `/private/tmp/aitrans-c-review-30882428016`。
- PR #153 fast run [30883254522](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/30883254522)：精确 head SHA，`validationProfile=fast`、`xcodeBuildRequired=false`，复用候选 full receipt `6c51c33d / success`，JUnit `10/10`；该 fast 包不是新的编译证据，结果包保存在 `/private/tmp/aitrans-c-review-30883254522`。
- merge fast run [30883306577](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/30883306577)：精确 merge SHA `fe6e3739`，`validationReason=merge_reuses_successful_candidate_full_validation`，复用候选 full receipt `6c51c33d / success`，`receiptPropagationAllowed=true`，Xcode skipped，JUnit `10/10`；结果包保存在 `/private/tmp/aitrans-c-review-30883306577`。

限制与遗留：

候选 push 默认 `probe_mode=skip`，本轮另有同 SHA ci-fast 生成报告与 PNG，未更新 `metrics/version_history.csv` 或仓库 `output/`。Koharu active artifact gate 仍为 `manifestMissing / stopUntilArtifactsProvided`，缺少真实 `test/koharu_artifacts/` 四件套；Speech corpus 与真实竖排图片 corpus 仍缺失。动作摘要与 block 5 截断诊断不能被描述为 OCR、翻译、识别或 Koharu 质量提升。

## v3.88：对齐 Koharu 核心输出 gate 的推荐动作
日期：2026-08-04

状态：Agent X 已完成 report-only 诊断对齐、云端 full/ci-fast/PR fast/merge fast 验收、PR 合并和 `smalldata_test` 文档收口；工程正式版本为 `MARKETING_VERSION=3.88`。候选分支 `codeb/v3.88-render-core-gate-action` 的候选 HEAD 为 `6a6e637cbe3e4a0d688e0e7f9f5b3a3142c14567`，PR [#152](https://github.com/bengzhu/project1_lgbt_naxida/pull/152) 已合入 `smalldata_test`，merge SHA 为 `5f6872cac575421d21ecd5670df97cb920423f95`，远端候选分支已删除，`main` 未触碰。

核心变更：

- `makeKoharuRenderRegressionLockReport` 新增 `coreOutputRecommendedAction`：required ci-fast 输出全部 retained 且 non-empty 时，`G-render-core-png-retained` 使用 `keepReportOnly`；只有缺失/空 required 输出才使用 `inspectRenderOutputExport`。这使 gate 与 v3.87 已修正的 `outputFileChecks` 动作一致，不放宽输出存在性、失败写入或成功报告门槛。
- 新增 `scripts/test-v388-koharu-render-core-output-gate-action-contract.py`，并把 v3.82–v3.87 历史合同、Koharu changed-file 路由和 full 静态检查同步到 v3.88。该 report-only 修复不触碰 OCR 候选、翻译模型／prompt、ground truth、生产 renderer/export、普通图片 OCR、Koharu active artifact gate、`metrics/version_history.csv` 或仓库 `output/`。

验证：

- 本地轻量检查：v3.82/v3.83/v3.84/v3.85/v3.86/v3.87/v3.88 合同、`git diff --check`、Swift `-parse`、项目版本解析、ground-truth JSON 与 CI YAML smoke 通过；未跑本机 build / 探针，按规则交给云端。
- 候选 full run [30880132762](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/30880132762)：manifest 精确匹配 v3.88、候选 branch、SHA `6a6e637c`、run/attempt/workflow，`validationProfile=full`、`xcodeBuildRequired=true`；Xcode build success，JUnit `10/10`、0 failures，`.xcresult`、静态、Speech、UI、home、paste 与 Koharu 合同通过；结果包保存在 `/private/tmp/aitrans-c-review-30880132762`。
- 同 SHA ci-fast 探针 run [30880751340](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/30880751340)：manifest 精确匹配同一 SHA，模拟器 build、Local GGUF 漫画探针与 Output 导出成功；`G-render-core-png-retained` 为 `passed / keepReportOnly`，6 个 output checks 均为 `keepReportOnly`。报告为 13 blocks、`renderLockVerdict=openRenderIssueDetected`，block 5 仍在 `renderTextTruncatedBlocks` 与 `G-render-no-text-truncation=blocked` 中；结果包保存在 `/private/tmp/aitrans-c-review-30880751340`。这是诊断证据，不是 OCR/翻译/Koharu 质量基线。
- PR #152 fast run [30881554748](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/30881554748)：精确 head `6a6e637c`，`validationProfile=fast`、`xcodeBuildRequired=false`，复用候选 full receipt `6a6e637c / success`，JUnit `10/10`；该 fast 包不是新的编译证据，结果包保存在 `/private/tmp/aitrans-c-review-30881554748`。
- merge fast run [30881613654](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/30881613654)：精确 merge SHA `5f6872ca`，`validationReason=merge_reuses_successful_candidate_full_validation`，复用候选 full receipt `6a6e637c / success`，`receiptPropagationAllowed=true`，Xcode skipped，JUnit `10/10`；结果包保存在 `/private/tmp/aitrans-c-review-30881613654`。

限制与遗留：

候选 push 默认 `probe_mode=skip`，本轮另有同 SHA ci-fast 生成报告与 PNG，未更新 `metrics/version_history.csv` 或仓库 `output/`。Koharu active artifact gate 仍为 `manifestMissing / stopUntilArtifactsProvided`，缺少真实 `test/koharu_artifacts/` 四件套；Speech corpus 与真实竖排图片 corpus 仍缺失。推荐动作对齐和 block 5 截断诊断不能被描述为 OCR、翻译、识别或 Koharu 质量提升。

## v3.87：修正 planned render 输出的推荐动作误报
日期：2026-08-04

状态：Agent X 已完成 report-only 输出诊断修正、云端 full/ci-fast/PR fast/merge fast 验收、PR 合并和 `smalldata_test` 文档收口；工程正式版本为 `MARKETING_VERSION=3.87`。候选分支 `codeb/v3.87-render-output-action` 的候选 HEAD 为 `9835ac1a94bd1c3317a91f991ba5101bd5b84ded`，PR [#151](https://github.com/bengzhu/project1_lgbt_naxida/pull/151) 已合入 `smalldata_test`，merge SHA 为 `21b1b4f3a32ce17ff28e2d3949085d3cf9f24c88`，远端候选分支已删除，`main` 未触碰。

核心变更：

- `makeKoharuRenderRegressionLockReport` 的 `outputCheck` 现在把 `status == "presentNonEmpty" || plannedFinalWrite` 统一映射为 `recommendedAction=keepReportOnly`；`plannedFinalReportWrite` 和 `plannedFinalOCRTextRewrite` 继续保留 planned 状态，只有 missing 或 present-but-empty/unchecked 才建议 `inspectRenderOutputExport`。这修正报告 UX，不放宽 `nonEmpty`、缺失文件或成功报告写入门槛。
- 新增 `scripts/test-v387-koharu-render-output-action-contract.py`，并把 v3.82–v3.86 历史合同与 Koharu changed-file/full 静态路由同步到 v3.87。该改动不触碰 OCR 候选、翻译模型／prompt、ground truth、生产 renderer/export、普通图片 OCR、Koharu active artifact gate、`metrics/version_history.csv` 或仓库 `output/`。

验证：

- 本地轻量检查：v3.82/v3.83/v3.84/v3.85/v3.86/v3.87 合同、`git diff --check`、Swift `-parse`、项目版本解析、ground-truth JSON 与 CI YAML smoke 通过；未跑本机 build / 探针，按规则交给云端。
- 候选 full run [30878519259](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/30878519259)：manifest 精确匹配 v3.87、候选 branch、SHA `9835ac1a`、run/attempt/workflow，`validationProfile=full`、`xcodeBuildRequired=true`；Xcode build success，JUnit `10/10`、0 failures，`.xcresult`、静态、Speech、UI、home、paste 与 Koharu 合同通过；结果包保存在 `/private/tmp/aitrans-c-review-30878519259`。
- 同 SHA ci-fast 探针 run [30878916261](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/30878916261)：manifest 精确匹配同一 SHA，模拟器 build、Local GGUF 漫画探针与 Output 导出成功；`probe_report.json` 的 `coreOutputFilesPresent=true`、`coreOutputFilesNonEmpty=true`，`probe_report.json` 为 `plannedFinalReportWrite / keepReportOnly`，`1_ocr_probe_text.txt` 为 `plannedFinalOCRTextRewrite / keepReportOnly`，其余保留输出同样为 `keepReportOnly`。报告仍为 13 blocks，`renderLockVerdict=openRenderIssueDetected`，block 5 保留 `renderTextTruncated` / `G-render-no-text-truncation=blocked`；结果包保存在 `/private/tmp/aitrans-c-review-30878916261`。这只是诊断证据，不是 OCR/翻译/Koharu 质量基线。
- PR #151 fast run [30879584339](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/30879584339)：精确 head `9835ac1a`，`validationProfile=fast`、`xcodeBuildRequired=false`，复用候选 full receipt `9835ac1a / success`，JUnit `10/10`；该 fast 包不是新的编译证据，结果包保存在 `/private/tmp/aitrans-c-review-30879584339`。
- merge fast run [30879645680](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/30879645680)：精确 merge SHA `21b1b4f3`，`validationReason=merge_reuses_successful_candidate_full_validation`，复用候选 full receipt `9835ac1a / success`，`receiptPropagationAllowed=true`，Xcode skipped，JUnit `10/10`；结果包保存在 `/private/tmp/aitrans-c-review-30879645680`。

限制与遗留：

候选 push 默认 `probe_mode=skip`，本轮另有同 SHA ci-fast 生成报告与 PNG，未更新 `metrics/version_history.csv` 或仓库 `output/`。Koharu active artifact gate 仍为 `manifestMissing / stopUntilArtifactsProvided`，缺少真实 `test/koharu_artifacts/` 四件套；Speech corpus 与真实竖排图片 corpus 仍缺失。推荐动作修正和 block 5 截断诊断不能被描述为 OCR、翻译、识别或 Koharu 质量提升。

## v3.86：修正 Koharu render-lock 输出工件时序误报
日期：2026-08-04

状态：Agent X 已完成 report-only 输出 ledger 修复、云端 full/ci-fast/PR fast/merge fast 验收、PR 合并和 `smalldata_test` 文档收口；工程正式版本为 `MARKETING_VERSION=3.86`。候选分支 `codeb/v3.86-render-output-ledger` 的候选 HEAD 为 `1fabaf55f82ae7f5110582983476887a8816745b`，PR [#150](https://github.com/bengzhu/project1_lgbt_naxida/pull/150) 已合入 `smalldata_test`，merge SHA 为 `83190d4a129e0af55b498f2bc253dabaee2cf372`，远端候选分支已删除，`main` 未触碰。

核心变更：

- `makeKoharuRenderRegressionLockReport` 的输出检查现在把 `probe_report.json` 和最终重写的 `1_ocr_probe_text.txt` 明确标记为 planned final write；重写前的短暂缺文件窗口不会再把必需 OCR 文本误记为 `presentButEmptyOrUnchecked`，新增 `plannedFinalOCRTextRewrite` 状态，成功报告的 `coreOutputFilesNonEmpty` 与 `G-render-core-png-retained` 因而反映真实探针输出。
- 失败的最终 OCR 文本写入仍会抛错并走失败报告，不放宽 CI artifact 要求；该修复只校正报告时序，不改变 OCR 候选、翻译模型／prompt、ground truth 决策、生产 renderer/export、普通图片 OCR、Koharu active artifact gate、`metrics/version_history.csv` 或仓库 `output/`。
- 新增 `scripts/test-v386-koharu-render-output-ledger-contract.py`，并把 v3.82–v3.85 历史合同与 Koharu changed-file/full 静态路由更新为接受后续正式版本。

验证：

- 本地轻量检查：v3.82/v3.83/v3.84/v3.85/v3.86 合同、`git diff --check`、Swift `-parse`、项目版本解析和 CI YAML smoke 通过；未跑本机 build / 探针，按规则交给云端。
- 候选 full run [30876931497](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/30876931497)：manifest 精确匹配 v3.86、候选 branch、SHA `1fabaf55`、run/attempt/workflow，`validationProfile=full`、`xcodeBuildRequired=true`；Xcode build success，JUnit `10/10`、0 failures，`.xcresult`、静态、Speech、UI、home、paste 与 Koharu 合同通过；结果包保存在 `/private/tmp/aitrans-c-review-30876931497`。
- 同 SHA ci-fast 探针 run [30877262645](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/30877262645)：manifest 精确匹配同一 SHA，模拟器 build、Local GGUF 漫画探针与 Output 导出成功，`mangaProbeOutcome=success`；13 blocks 的 `coreOutputFilesPresent=true`、`coreOutputFilesNonEmpty=true`，`G-render-core-png-retained=passed`，`1_ocr_probe_text.txt` 状态为 `plannedFinalOCRTextRewrite` 且实际非空；`renderLockVerdict=openRenderIssueDetected` 只保留 block 5 的真实 `renderTextTruncated` / `G-render-no-text-truncation=blocked`，不再被缺文件误报覆盖。该报告是诊断证据，不是 OCR/翻译/Koharu 质量基线；结果包保存在 `/private/tmp/aitrans-c-review-30877262645`。
- PR #150 fast run [30877905238](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/30877905238)：精确 head `1fabaf55`，`validationProfile=fast`、`xcodeBuildRequired=false`，复用候选 full receipt `1fabaf55 / success`，JUnit `10/10`；该 fast 包不是新的编译证据，结果包保存在 `/private/tmp/aitrans-c-review-30877905238`。
- merge fast run [30877976728](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/30877976728)：精确 merge SHA `83190d4a`，`validationReason=merge_reuses_successful_candidate_full_validation`，复用候选 full receipt `1fabaf55 / success`，`receiptPropagationAllowed=true`，Xcode skipped，JUnit `10/10`；结果包保存在 `/private/tmp/aitrans-c-review-30877976728`。

限制与遗留：

候选 push 默认 `probe_mode=skip`，本轮另有同 SHA ci-fast 生成报告与 PNG，未更新 `metrics/version_history.csv` 或仓库 `output/`。Koharu active artifact gate 仍为 `manifestMissing / stopUntilArtifactsProvided`，缺少真实 `test/koharu_artifacts/` 四件套；Speech corpus 与真实竖排图片 corpus 仍缺失。输出 ledger 修复与 block 5 截断诊断不能被描述为 OCR、翻译、识别或 Koharu 质量提升。

## v3.85：汇总 Koharu render-lock 最小字号证据
日期：2026-08-04

状态：Agent X 已完成 report-only 诊断增强、云端 full/ci-fast/PR fast/merge fast 验收、PR 合并和 `smalldata_test` 文档 follow-up；工程正式版本为 `MARKETING_VERSION=3.85`。候选分支 `codeb/v3.85-koharu-render-lock-min-font-summary` 的最终候选 HEAD 为 `f227dd64438900744dc05aa9102e693edbc6fda5`，PR [#149](https://github.com/bengzhu/project1_lgbt_naxida/pull/149) 已合入 `smalldata_test`，merge SHA 为 `bfefffd6ce2fd670300920af17551e19baa9131a`，远端候选分支已删除，`main` 未触碰。

核心变更：

- `MangaKoharuRenderRegressionLockReport` 新增 `renderMinFontSizeReachedBlocks` 顶层汇总；每个 `MangaKoharuRenderBlockLock` 的 decision trace 同步显式记录 `renderMinFontSizeReached`。
- 新增 `G-render-min-font-evidence` report-only gate，并让 `MangaOverlayProbeService` 的开发者诊断摘要输出 `minFont=`，使 render lock、fit planner 与摘要消费同一既有证据。
- 新增 `scripts/test-v385-koharu-render-lock-min-font-contract.py`，接入 Koharu changed-file/full 静态路由；v3.82–v3.84 历史合同同步接受后续正式版本。`MARKETING_VERSION` 推进到 3.85。
- 该改动只补齐报告传播，不改变 OCR 候选、翻译模型／prompt、ground truth 决策、生产 renderer/export、Koharu active artifact gate、普通图片 OCR 主路径、`metrics/version_history.csv` 或仓库 `output/`。

验证：

- 本地轻量检查：v3.82/v3.83/v3.84/v3.85 合同、`git diff --check`、Swift `-parse`、项目版本解析和 CI YAML smoke 通过；未跑本机 build / 探针，按规则交给云端。
- 候选 full run [30875436621](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/30875436621)：manifest 精确匹配 v3.85、候选 branch、SHA `f227dd64`、run/attempt/workflow，`validationProfile=full`、`xcodeBuildRequired=true`；Xcode 26.6 build success，JUnit `10/10`、0 failures，UI/Speech/home/paste/Koharu 合同通过；结果包保存在 `/private/tmp/aitrans-c-review-30875436621`。
- 同 SHA ci-fast 探针 run [30875716372](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/30875716372)：Xcode、模拟器构建、Local GGUF 漫画探针与 Output 导出成功，`mangaProbeOutcome=success`；`probe_report.json` 的 `koharuRenderRegressionLockReport.renderMinFontSizeReachedBlocks=[5]`，block 5 同时为 `renderMinFontSizeReached=true`、`renderTextTruncated=true`、`renderStatus=textTruncated`，新 gate 为 passed/report-only，`wouldChangeMainFlow=false`；结果包保存在 `/private/tmp/aitrans-c-review-30875716372`。该报告是诊断证据，不是 OCR/翻译/Koharu 质量基线。
- PR #149 fast run [30876264990](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/30876264990)：精确 head `f227dd64`，`validationProfile=fast`，复用候选 full receipt `f227dd64 / success`，`xcodeBuildRequired=false`、skip reason 为 `fast_followup_reuses_candidate_full_validation`，JUnit `10/10`；该 fast 包不是新的编译证据，结果包保存在 `/private/tmp/aitrans-c-review-30876264990`。
- merge fast run [30876301079](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/30876301079)：精确 merge SHA `bfefffd6`，`validationReason=merge_reuses_successful_candidate_full_validation`，复用候选 full receipt `f227dd64 / success`，`receiptPropagationAllowed=true`，Xcode skipped，JUnit `10/10`；结果包保存在 `/private/tmp/aitrans-c-review-30876301079`。
- 文档 follow-up run [30876417492](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/30876417492)：精确文档 SHA `bf83d0ac`，`validationProfile=fast`、`validationReason=smalldata_metadata_followup_reuses_parent_full_validation`，复用 merge SHA `bfefffd6 / success`，`smalldataIncrementalMetadataOnly=true`、`receiptPropagationAllowed=true`，Xcode skipped，静态检查与 JUnit `10/10` 通过；该包只传播既有 full receipt，不是新的 Swift/Xcode 编译证据。结果包保存在 `/private/tmp/aitrans-c-review-30876417492`。

限制与遗留：

候选、PR fast 和 merge fast 的探针默认路径为 skip；本轮 ci-fast 只提供诊断报告与 PNG，未更新 `metrics/version_history.csv` 或仓库 `output/`。Koharu active artifact gate 仍为 `manifestMissing / stopUntilArtifactsProvided`，缺少真实 `test/koharu_artifacts/` 四件套；Speech corpus 与真实竖排图片 corpus 仍缺失。最小字号压力与实际截断仍只是诊断证据，不是 OCR、翻译、识别或 Koharu 质量提升结论。

## v3.84：保留 Koharu 最小字号渲染证据
日期：2026-08-04

状态：Agent X 已完成 report-only 诊断增强、云端 full/ci-fast/PR fast/merge fast 验收和 PR 合并；文档在 `smalldata_test` 完成正式版本收口，工程正式版本为 `MARKETING_VERSION=3.84`。候选分支 `codeb/v3.84-koharu-min-font-evidence` 的最终候选 HEAD 为 `4a71de06a2fc4a6702f4d5fb878901a16d01589f`，PR [#148](https://github.com/bengzhu/project1_lgbt_naxida/pull/148) 已合入 `smalldata_test`，merge SHA 为 `2c904b3d06f5dedaef7829daad36ea939e1093a0`，远端候选分支已删除，`main` 未触碰。

核心变更：

- `MangaKoharuRenderSpriteFitBlockLedger` 现在保留既有 block/render lock 的 `renderMinFontSizeReached`；`MangaKoharuRenderSpriteFitPlannerReport` 汇总 `renderMinFontSizeReachedBlocks`，decision trace 与 block ledger 使用同一信号。
- 新增 `G-render-sprite-fit-min-font-evidence` report-only gate，明确最小字号压力已从渲染锁传播到 fit planner；`wouldChangeMainFlow=false`、`groundTruthUsedForDecision=false`、`diagnosticOnly=true` 和 proxy 边界保持不变。
- 新增 `scripts/test-v384-koharu-render-min-font-contract.py`，接入 Koharu changed-file/full 静态路由；v3.82/v3.83 历史合同同步接受后续正式版本。`MARKETING_VERSION` 推进到 3.84。
- 该改动只补齐诊断证据链，不改变 OCR 候选、翻译模型／prompt、ground truth 决策、生产 renderer/export、Koharu active artifact gate、普通图片 OCR 主路径、`metrics/version_history.csv` 或仓库 `output/`。

验证：

- 本地轻量检查：v3.81/v3.82/v3.83/v3.84 合同、`git diff --check`、Swift `-parse`、项目版本解析和 CI YAML smoke 通过；未跑本机 build / 探针，按规则交给云端。
- 候选 full run [30873895093](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/30873895093)：manifest 精确匹配 v3.84、候选 branch、SHA `4a71de06`、run/attempt/workflow，`validationProfile=full`、`xcodeBuildRequired=true`；Xcode 26.6 build success，JUnit `10/10`、0 failures，UI/Speech/home/paste/Koharu 合同通过；结果包保存在 `/private/tmp/aitrans-c-review-30873895093`。
- 同 SHA ci-fast 探针 run [30874183417](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/30874183417)：模拟器构建、Local GGUF 漫画探针与 Output 导出成功，`mangaProbeOutcome=success`；`probe_report.json` 的 `renderMinFontSizeReachedBlocks=[5]`，block 5 为 `renderMinFontSizeReached=true`、`renderTextTruncated=true`、`failureFallbackLongTextRisk`，并保留 `wouldChangeMainFlow=false` 与 ground-truth-free 诊断边界；结果包保存在 `/private/tmp/aitrans-c-review-30874183417`。
- PR #148 fast run [30874885165](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/30874885165)：精确 head `4a71de06`，`validationProfile=fast`，复用候选 full receipt `4a71de06 / success`，`xcodeBuildRequired=false`、skip reason 为 `fast_followup_reuses_candidate_full_validation`，JUnit `10/10`；该 fast 包不是新的编译证据，结果包保存在 `/private/tmp/aitrans-c-review-30874885165`。
- merge fast run [30874929145](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/30874929145)：精确 merge SHA `2c904b3d`，`validationReason=merge_reuses_successful_candidate_full_validation`，复用候选 full receipt `4a71de06 / success`，`receiptPropagationAllowed=true`，Xcode skipped，JUnit `10/10`；结果包保存在 `/private/tmp/aitrans-c-review-30874929145`。
- 文档 follow-up run [30875160582](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/30875160582)：精确文档 SHA `0009f4f7`，`validationProfile=fast`、`validationReason=smalldata_metadata_followup_reuses_parent_full_validation`，复用 merge SHA `2c904b3d / success`，`smalldataIncrementalMetadataOnly=true`、`receiptPropagationAllowed=true`，Xcode skipped，静态检查与 JUnit `10/10` 通过；该包只传播既有 full receipt，不是新的 Swift/Xcode 编译证据。结果包保存在 `/private/tmp/aitrans-c-review-30875160582`。

限制与遗留：

候选、PR fast 和 merge fast 的探针默认路径为 skip；本轮 ci-fast 只提供诊断报告与 PNG，未更新 `metrics/version_history.csv` 或仓库 `output/`。Koharu active artifact gate 仍为 `manifestMissing / stopUntilArtifactsProvided`，缺少真实 `test/koharu_artifacts/` 四件套；Speech corpus 与真实竖排图片 corpus 仍缺失。block 5 的最小字号压力和截断是当前诊断证据，不是 OCR、翻译、识别或 Koharu 质量提升结论。

## v3.83：Koharu fit planner 与实际渲染预算对齐
日期：2026-08-04

状态：Agent X 已完成 report-only 诊断修复、云端 full/ci-fast/PR fast/merge fast 验收和 PR 合并；文档在 `smalldata_test` 完成正式版本收口，工程正式版本为 `MARKETING_VERSION=3.83`。候选分支 `codeb/v3.83-koharu-fit-budget` 的最终候选 HEAD 为 `54eafc65b202f92d5e4dc44e2bc46ff14e6f44c5`，PR [#147](https://github.com/bengzhu/project1_lgbt_naxida/pull/147) 已合入 `smalldata_test`，merge SHA 为 `02c36903824cef14c9ec7935954c3813e4dda2e4`，远端候选分支已删除，`main` 未触碰。

核心变更：

- `makeKoharuRenderSpriteFitPlannerReport` 的 `estimateTextBudget` 复用 `Self.wrappedLines`，保留显式换行与空行，并按实际 wrapped lines 计算 line count/max chars，避免用 `text.count` 低估失败 fallback 的垂直预算。
- 失败覆盖诊断把 `block.renderTextTruncated` 与 `renderLock.renderTextTruncated` 合并为 report-only 信号；实际截断时 `failureOverlayFitVerdict` 与 `fitVerdict` 会报告 `failureFallbackLongTextRisk`，并保留 `wouldChangeMainFlow=false`、`groundTruthUsedForDecision=false`。
- 新增 `scripts/test-v383-koharu-fit-budget-contract.py`，接入 Koharu changed-file 路由与 full 静态检查；v3.82 历史合同改为接受后续正式版本。`MARKETING_VERSION` 推进到 3.83。
- 该修复只校正 Koharu fit 诊断与实际渲染证据的一致性，不改变 OCR 候选、翻译模型／prompt、ground truth 决策、生产 renderer/export、Koharu active artifact gate、普通图片 OCR 主路径、`metrics/version_history.csv` 或仓库 `output/`。

验证：

- 本地轻量检查：v3.81/v3.82/v3.83 合同、`git diff --check`、`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc -parse AITRANS/Services/MangaOverlayProbeService.swift`、项目版本解析、ground-truth JSON 解析和 CI YAML 行长 smoke 通过；未跑本机 build / 探针，按规则交给云端验证。
- 候选 full run [30870546266](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/30870546266) / job 91871484041：manifest 精确匹配 v3.83、branch、commit、run、attempt、workflow，`validationProfile=full`、`xcodeBuildRequired=true`，Xcode 26.6 build success，JUnit `10/10`、0 failures，静态、Speech、UI、home、paste 与 Koharu 合同通过；结果包保存在 `/private/tmp/aitrans-c-review-30870546266`。
- 同一 SHA 的 ci-fast 探针 run [30870974176](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/30870974176) / job 91872741483：Xcode、模拟器构建、Local GGUF 漫画探针与 Output 导出成功，`probe_report.json` 为 13 blocks、`overallPassed=false`，`renderTextTruncatedBlocks=[5]`；block 5 从 v3.82 报告的 `estimatedLineCount=2 / fontBudgetComfortable / currentSpriteFits` 变为 `12 / fontBudgetOverflowRisk / failureFallbackLongTextRisk`，实际截断继续如实保留。结果包保存在 `/private/tmp/aitrans-c-review-30870974176`；该报告与覆盖 PNG 仍是诊断证据，不是 OCR、翻译或 Koharu 质量基线。
- PR #147 fast run [30871715717](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/30871715717)：精确 head `54eafc65`，`validationProfile=fast`，复用候选 full receipt `54eafc65 / success`，`xcodeBuildRequired=false`、skip reason 为 `fast_followup_reuses_candidate_full_validation`，JUnit `10/10`；该 fast 包不是新的编译证据。结果包保存在 `/private/tmp/aitrans-c-review-30871715717`。
- merge fast run [30871766042](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/30871766042)：精确 merge SHA `02c36903`，`validationReason=merge_reuses_successful_candidate_full_validation`，复用候选 full receipt `54eafc65 / success`，`receiptPropagationAllowed=true`，Xcode skipped，JUnit `10/10`；结果包保存在 `/private/tmp/aitrans-c-review-30871766042`。
- 文档 follow-up run [30872018278](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/30872018278)：精确文档 SHA `dbe9dab8`，`validationProfile=fast`、`validationReason=smalldata_metadata_followup_reuses_parent_full_validation`，复用 merge SHA `02c36903 / success`，`smalldataIncrementalMetadataOnly=true`、`receiptPropagationAllowed=true`，Xcode skipped，静态检查与 JUnit `10/10` 通过；该包只传播既有 full receipt，不是新的 Swift/Xcode 编译证据。结果包保存在 `/private/tmp/aitrans-c-review-30872018278`。

限制与遗留：

候选 push 与 PR/merge fast 默认 `probe_mode=skip`；本轮另有同 SHA ci-fast 生成报告与 PNG，但未更新 `metrics/version_history.csv` 或仓库 `output/`。Koharu active artifact gate 仍为 `manifestMissing / stopUntilArtifactsProvided`，缺少真实 `test/koharu_artifacts/` 四件套；Speech corpus 与真实竖排图片 corpus 仍缺失。现有覆盖图仍能看到既有重叠/失败覆盖问题；本版只让诊断如实暴露 block 5 的超长截断，不声称 OCR、翻译、识别或 Koharu 质量提升。

## v3.82：漫画失败覆盖显式换行布局安全
日期：2026-08-04

状态：Agent X 已完成探针布局修复、云端 full/ci-fast/PR fast/merge fast 验收和 PR 合并；文档在 `smalldata_test` 完成正式版本收口，工程正式版本为 `MARKETING_VERSION=3.82`。候选分支 `codeb/v3.82-render-newline-safety` 的最终候选 HEAD 为 `996cb3fcceadd25b778d079dbec04d7b72accac5`，PR [#146](https://github.com/bengzhu/project1_lgbt_naxida/pull/146) 已合入 `smalldata_test`，merge SHA 为 `8ff612269bb9c57691284179ad09ce281dd20a7c`，远端候选分支已删除，`main` 未触碰。

核心变更：

- `MangaOverlayProbeService.wrappedLines` 现在按显式换行拆分段落并保留空行，再在段内按宽度换行；失败 fallback 的 fit plan、碰撞检查和 CoreText 绘制因此共享同一垂直行预算，不再把换行符当成普通字符吞掉。
- 新增 `scripts/test-v382-manga-render-newline-contract.py`，接入 full 静态检查和 Manga service changed-file 路由；同步把 `MARKETING_VERSION` 推进到 3.82，并让 v3.81 历史合同接受后续正式版本。
- 该修复只改善漫画探针失败覆盖的布局测量与诊断可观测性，不改变 OCR 候选、翻译模型／prompt、ground truth 决策、Koharu active artifact gate、普通图片 OCR、renderer/export 主路径、`metrics/version_history.csv` 或仓库 `output/` 质量基线。

验证：

- 本地轻量检查：v3.82/v3.81 合同、v3.192/v3.199/v3.200/v3.201/v3.32/v3.33/v3.194、v3.197 handoff/version identity 等定向 Koharu/图片合同通过；`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc -parse AITRANS/Services/MangaOverlayProbeService.swift`、`git diff --check`、项目版本解析和 YAML 行长 smoke 通过。
- 候选 full run [30868588679](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/30868588679) / job 91865639512：精确匹配 version/branch/commit/run/attempt/workflow，`validationProfile=full`、`xcodeBuildRequired=true`，Xcode build success，JUnit `10/10`、0 failures，静态、Speech、UI、home、paste 与 Koharu 合同通过；结果包保存在 `/private/tmp/aitrans-c-review-30868588679`。
- 同一 SHA 的 ci-fast 探针 run [30868948454](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/30868948454) / job 91866714984：Xcode、模拟器构建、Local GGUF 漫画探针和 Output 导出成功；`probe_report.json` 保留 13 blocks、12 failed/1 passed、`renderCollisionUnresolvedBlocks=[]`，只有超长失败 block 5 诚实记录 `renderTextTruncated=true`。报告仍为诊断证据，不是 OCR/翻译质量基线；结果包保存在 `/private/tmp/aitrans-c-review-30868948454`。
- PR #146 fast run [30869682081](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/30869682081)：精确 head `996cb3fc`，`validationProfile=fast`，复用候选 full receipt `996cb3fc` / `success`，Xcode skip reason 为 `fast_followup_reuses_candidate_full_validation`，JUnit `10/10`；结果包保存在 `/private/tmp/aitrans-c-review-30869682081`。
- merge fast run [30869756072](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/30869756072)：精确 merge SHA `8ff61226`，`validationReason=merge_reuses_successful_candidate_full_validation`，复用候选 full receipt，`receiptPropagationAllowed=true`，Xcode skipped，JUnit `10/10`；结果包保存在 `/private/tmp/aitrans-c-review-30869756072`。

- 文档 follow-up run [30870035192](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/30870035192) / job 91869972036：精确文档 SHA `d6fbdd93`，`validationProfile=fast`、`validationReason=smalldata_metadata_followup_reuses_parent_full_validation`，复用 merge SHA `8ff61226` / `success`，`smalldataIncrementalMetadataOnly=true`、`receiptPropagationAllowed=true`，Xcode skipped，静态检查和 JUnit `10/10` 通过；该包只传播既有 full receipt，不是新的 Swift/Xcode 编译证据。结果包保存在 `/private/tmp/aitrans-c-review-30870035192`。

限制与遗留：

候选 push 与 PR/merge fast 默认 `probe_mode=skip`；只有手动 ci-fast 生成了本轮探针图和报告，未更新 `metrics/version_history.csv` 或仓库 `output/`。Koharu active artifact gate 仍为 `manifestMissing / stopUntilArtifactsProvided`，缺少真实 `test/koharu_artifacts/` 四件套；Speech corpus 与真实竖排图片 corpus 仍缺失。未跑本机 build / 探针，按规则交给云端验证；本版只改善失败覆盖布局测量与可观测性，不声称 OCR、翻译、识别或 Koharu 质量提升。

## v3.81：直接选择图片文字块后的 VoiceOver 焦点回交
日期：2026-08-04

状态：Agent X 已完成实现、修复 GitHub Actions 表达式长度问题、云端 full/PR fast/merge fast 验收和 PR 合并；文档在 `smalldata_test` 完成正式版本收口，工程正式版本为 `MARKETING_VERSION=3.81`。候选分支 `codeb/v3.81-image-selection-focus` 的最终候选 HEAD 为 `95003c0a902994e474abaa18415f3ce08e713de0`，PR [#145](https://github.com/bengzhu/project1_lgbt_naxida/pull/145) 已合入 `smalldata_test`，merge SHA 为 `491ef5f3`，远端候选分支已删除，`main` 未触碰。

核心变更：

- `ImageTranslationPanel.toggleSelection(of:)` 在结果行选中 OCR block 后立即把 VoiceOver 焦点交给对应局部预览；取消定位时回到对应结果行。
- `selectBlockFromPreview(_:)` 在完整图片覆盖块入口复用同一套局部预览／结果行焦点 handoff，保持图片入口与列表入口的定位上下文连续。
- 新增 `scripts/test-v381-image-selection-focus-contract.py`，锁定两条入口、取消定位、View-only ownership、版本解析和 CI 路由；v3.47–v3.80 历史图片合同统一接受后续版本。同步压缩历史图片合同路由正则，避免 GitHub Actions 表达式超过 21000 字符上限。
- 该改动只使用 View 私有 `AccessibilityFocusState`，不新增 Store／持久化状态，不改变 Vision OCR、模型翻译、renderer/export、复查、漫画探针、Koharu 主路径或质量基线。

关键文件：

- `AITRANS/Views/ImageTranslationViews.swift`
- `AITRANS.xcodeproj/project.pbxproj`
- `.github/workflows/ci-results.yml`
- `scripts/test-v381-image-selection-focus-contract.py` 及 v3.47–v3.80 历史合同路由兼容修正
- `README.md`、`AGENTS.md`、`md/flow/flow.md`、`md/flow/flowchart.md`、`md/test/test.md`

验证：

- 候选首次 full `30706399843` 在任何 job 启动前因 workflow 表达式超过 GitHub Actions 21000 字符上限失败；`95003c0a` 将路由压缩为等价正则后重新验证，不把该解析失败包作为代码验收证据。
- 最终候选 full `30706561881` / job `91386592004`：artifact manifest 精确匹配 version/branch/commit/run/attempt/workflow，`validationProfile=full`、`validationReason=candidate_development_push`、`xcodeBuildRequired=true`；Xcode build success，`.xcresult` `status=succeeded`、`errorCount=0`、`warningCount=0`，JUnit `10/10`、0 failures，UI/Speech/home/paste 合同全部通过。结果包保存在 `/private/tmp/aitrans-c-review-30706561881`。
- PR #145 fast `30706829461` / job `91387285759`：exact head `95003c0a`，`validationProfile=fast`，复用 full SHA `95003c0a902994e474abaa18415f3ce08e713de0` 且 state `success`，Xcode skip reason 为 `fast_followup_reuses_candidate_full_validation`，JUnit `10/10`；结果包保存在 `/private/tmp/aitrans-c-review-30706829461`。
- merge fast `30706860840`：exact merge SHA `491ef5f3`，`validationReason=merge_reuses_successful_candidate_full_validation`，复用候选 full 成功收据，`receiptPropagationAllowed=true`，Xcode skipped，JUnit `10/10`；结果包保存在 `/private/tmp/aitrans-c-review-30706860840`。

限制与遗留：

候选、PR fast 和 merge fast 均使用 `probe_mode=skip`，未生成新的漫画探针指标、`output/` 报告或 `metrics/version_history.csv` 行。full artifact 的 Koharu active gate 仍为 `manifestMissing / stopUntilArtifactsProvided`，缺少真实 `test/koharu_artifacts/` 四件套（manifest、TextBoxes、BubbleMask、SegmentMask）；Speech corpus 仍为 `manifestMissing` 且 `qualityExecuted=false`，真实竖排图片 corpus 也仍缺失。本版只改善图片 View-only 焦点连续性，不声称 OCR、翻译、识别或 Koharu 质量提升；源码合同和云端 Xcode build 不能替代真实设备 VoiceOver、Dynamic Type、真实四件套或漫画探针。

## v3.80：筛选隐藏选中 block 后的 VoiceOver 焦点回交
日期：2026-08-01

状态：Agent X 已完成实现、历史合同路由兼容、云端 full/PR fast/merge fast 验收和 PR 合并；文档已在 `smalldata_test` 完成正式版本收口，工程正式版本为 `MARKETING_VERSION=3.80`。候选分支 `codeb/v3.80-image-review-filter-focus` 的最终候选 HEAD 为 `1e5b301516fcdf7acca3bcfbd7f2a7d2f8535720`，PR #144 已合入 `smalldata_test`，merge SHA 为 `4f72fc4960983fd3431b2aec236d9c06d90cfdae`，远端候选分支已删除，`main` 未触碰。

核心变更：

- `ImageTranslationPanel.clearHiddenReviewSelection()` 在 `reviewFilter` 隐藏当前选中的 OCR block 时，先清除失效的 `selectedImageTranslationBlockID`，再按“首个可见结果行 → 本次复查完成状态 → 筛选器”顺序选择真实存在的 VoiceOver focus destination；筛选器增加稳定的 `reviewFilterAccessibilityFocusID`，避免焦点停留在已卸载的局部预览容器。
- 新增 `scripts/test-v380-image-review-filter-focus-contract.py`，锁定筛选变化、空结果 fallback、View-only ownership、版本与 CI 路由；历史 v3.47–v3.79 合同路由同步接受 v3.80。该版本不新增 Store／持久化状态，不重新 OCR／翻译，不改变 renderer/export、图片复查、漫画探针或 Koharu 主路径。

关键文件：

- `AITRANS/Views/ImageTranslationViews.swift`
- `AITRANS.xcodeproj/project.pbxproj`
- `.github/workflows/ci-results.yml`
- `scripts/test-v380-image-review-filter-focus-contract.py`
- `scripts/test-v379-image-focus-preview-navigation-focus-contract.py` 及 v3.47–v3.78 图片合同路由兼容修正
- `README.md`、`AGENTS.md`、`md/flow/flow.md`、`md/flow/flowchart.md`、`md/test/test.md`

验证：

- 本地轻量检查：v3.312、v3.314、v3.320、v3.378、v3.379、v3.380 定向合同通过；`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc -parse AITRANS/Views/ImageTranslationViews.swift`、`git diff --check` 通过。完整本机 UI 合同执行至已知会卡住的 v3.367 Swift evaluator 后停止，未把本机结果当作完整证据；未跑本机 build / 探针，按规则交给云端验证。
- 候选 full `30705693148` / job `91384280336`：manifest 精确匹配 version/branch/commit/run/attempt/workflow，`validationProfile=full`、`validationReason=candidate_development_push`、`xcodeBuildRequired=true`；完整 UI interaction、Speech、home、paste contracts 成功，Xcode build success，JUnit `10/10`、0 failures。结果包保存在 `/private/tmp/aitrans-c-review-30705693148`。
- PR #144 fast `30706005235` / job `91385130394`：exact head `1e5b3015`，`validationProfile=fast`，`reusedFullValidationSha=1e5b301516fcdf7acca3bcfbd7f2a7d2f8535720`、state `success`，Xcode skip reason 为 `fast_followup_reuses_candidate_full_validation`，JUnit `10/10`；结果包保存在 `/private/tmp/aitrans-c-review-30706005235`。
- merge fast `30706032968` / job `91385205099`：exact merge SHA `4f72fc4960983fd3431b2aec236d9c06d90cfdae`，`validationReason=merge_reuses_successful_candidate_full_validation`，复用候选 full SHA `1e5b301516fcdf7acca3bcfbd7f2a7d2f8535720` / state `success`，`receiptPropagationAllowed=true`，Xcode skipped，JUnit `10/10`；结果包保存在 `/private/tmp/aitrans-c-review-30706032968`。

限制与遗留：

候选、PR fast 和 merge fast 均使用 `probe_mode=skip`，未生成新的漫画探针指标、`output/` 报告或 `metrics/version_history.csv` 行。full artifact 的 Koharu active gate 仍为 `manifestMissing / stopUntilArtifactsProvided`，缺少真实 manifest、TextBoxes、BubbleMask、SegmentMask；Speech corpus 仍为 `manifestMissing` 且 `qualityExecuted=false`。真实 Koharu 四件套、Speech 音频和真实竖排图片 corpus 仍缺失，本版只改善筛选切换后的 View-only 焦点连续性，不声称 OCR、翻译、识别或 Koharu 质量提升。源码合同与云端 Xcode build 不能替代真实设备 VoiceOver、Dynamic Type、真实四件套或漫画探针。

## v3.79：相邻图片预览导航的 VoiceOver 焦点跟随
日期：2026-08-01

状态：Agent X 已完成实现、历史合同兼容修正、云端 full/PR fast/merge fast 验收和 PR 合并；文档已在 `smalldata_test` 完成正式版本收口，工程正式版本为 `MARKETING_VERSION=3.79`。候选分支 `codeb/v3.79-focus-preview-navigation-focus` 的最终候选 HEAD 为 `bc72295a4214de8046b5ef46af00c394f1d973a4`，PR #143 已合入 `smalldata_test`，merge SHA 为 `51313101e7db5252183b329b148f949d2eb1c55e`，远端候选分支已删除，`main` 未触碰。

核心变更：

- `ImageTranslationPanel.selectAdjacentBlock(offset:)` 仍按当前筛选后的 `visibleImageTranslationBlocks` 顺序和边界选择目标 block；现在先保存 `targetBlockID`，更新 `selectedImageTranslationBlockID` 后立即调用 `moveReviewAccessibilityFocus(to: reviewPreviewAccessibilityFocusID(targetBlockID))`，让 VoiceOver 焦点跟随新的局部预览容器，而不是停留在旧 block 或失去焦点。
- 新增 `scripts/test-v379-image-focus-preview-navigation-focus-contract.py`，锁定目标选择、预览焦点 handoff、前后按钮 position/boundary 语义、View-only 边界和 v3.78 后 CI 路由；同步把 v3.14 历史合同改为接受直接赋值或等价的局部 target ID 写法。该版本不新增 Store／持久化状态，不改变 Vision OCR、模型翻译、renderer/export、图片复查、漫画探针或 Koharu 主路径。

关键文件：

- `AITRANS/Views/ImageTranslationViews.swift`
- `AITRANS.xcodeproj/project.pbxproj`
- `.github/workflows/ci-results.yml`
- `scripts/test-v379-image-focus-preview-navigation-focus-contract.py`
- `scripts/test-v314-image-review-navigation-contract.py` 及 v3.47–v3.78 图片合同路由兼容修正
- `README.md`、`AGENTS.md`、`md/flow/flow.md`、`md/flow/flowchart.md`、`md/test/test.md`

验证：

- 本地轻量检查：v3.313、v3.377、v3.378、v3.379 定向合同通过；`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc -parse AITRANS/Views/ImageTranslationViews.swift`、`git diff --check` 通过。未跑本机 build / 探针，按规则交给云端验证。
- 候选 full `30703881906` / job `91379503002`：manifest 精确匹配 version/branch/commit/run/attempt/workflow，`validationProfile=full`、`validationReason=candidate_development_push`、`xcodeBuildRequired=true`；Xcode build success，JUnit `10/10`、0 failures，UI interaction、Speech、home、paste contracts 全部成功。结果包保存在 `/private/tmp/aitrans-c-review-30703881906`。首次候选 full `30703609147` 仅因 v3.14 历史断言仍要求旧直接赋值而失败，Xcode 本身成功；修复合同后不把旧包作为最终证据。
- PR #143 fast `30705194695` / job `91382991198`：exact head `bc72295a`，`validationProfile=fast`，`reusedFullValidationSha=bc72295a4214de8046b5ef46af00c394f1d973a4`、state `success`，Xcode skip reason 为 `fast_followup_reuses_candidate_full_validation`，JUnit `10/10`；结果包保存在 `/private/tmp/aitrans-c-review-30705194695`。
- merge fast `30705222609` / job `91383064653`：exact merge SHA `51313101e7db5252183b329b148f949d2eb1c55e`，`validationReason=merge_reuses_successful_candidate_full_validation`，复用候选 full SHA `bc72295a4214de8046b5ef46af00c394f1d973a4` / state `success`，`receiptPropagationAllowed=true`，Xcode skipped，JUnit `10/10`；结果包保存在 `/private/tmp/aitrans-c-review-30705222609`。

限制与遗留：

候选、PR fast 和 merge fast 均使用 `probe_mode=skip`，未生成新的漫画探针指标、`output/` 报告或 `metrics/version_history.csv` 行。full artifact 的 Koharu active gate 仍为 `manifestMissing / stopUntilArtifactsProvided`，缺少真实 manifest、TextBoxes、BubbleMask、SegmentMask；Speech corpus 仍为 `manifestMissing` 且 `qualityExecuted=false`。真实 Koharu 四件套、Speech 音频和真实竖排图片 corpus 仍缺失，本版只改善 View-only 的 VoiceOver 焦点连续性，不声称 OCR、翻译、识别或 Koharu 质量提升。源码合同与云端 Xcode build 不能替代真实设备 VoiceOver、Dynamic Type、真实四件套或漫画探针。

## v3.78：关闭局部预览后的 VoiceOver 焦点回交
日期：2026-08-01

状态：Agent X 已完成实现、历史合同兼容修正、云端 full/PR fast 验收和 PR 合并；工程正式版本为 `MARKETING_VERSION=3.78`。候选分支 `codeb/v3.78-focus-preview-close-focus` 的最终候选 HEAD 为 `e79269ca9e74650f98d99f9f4c535548292ba6f3`，PR #142 已合入 `smalldata_test`，merge SHA 为 `83b6b31df5ae9224a55c9381f87cb018f908024c`，远端候选分支已删除，`main` 未触碰。

核心变更：

- `ImageTranslationPanel` 关闭 `ImageTranslationFocusPreview` 时改用 `closeImageTranslationFocusPreview`：先清除 View 私有的 `selectedImageTranslationBlockID`，再通过既有 `reviewRowAccessibilityFocusID` 将 VoiceOver 焦点交回对应 OCR 结果行，避免局部预览容器消失后焦点丢失。
- 新增 `scripts/test-v378-image-focus-preview-close-focus-contract.py`，锁定关闭入口、焦点 handoff、View-only 边界、版本解析和 CI 路由；同步让历史 v3.13 闭包断言及 v3.47–v3.77 图片合同接受当前 v3.78。该版本不新增 Store／持久化状态，不改变 Vision OCR、模型翻译、renderer/export、图片复查、漫画探针或 Koharu 主路径。

关键文件：

- `AITRANS/Views/ImageTranslationViews.swift`
- `AITRANS.xcodeproj/project.pbxproj`
- `.github/workflows/ci-results.yml`
- `scripts/test-v378-image-focus-preview-close-focus-contract.py`、`scripts/test-v313-image-block-focus-contract.py`、v3.47–v3.77 图片合同路由兼容修正
- `README.md`、`AGENTS.md`、`md/flow/flow.md`、`md/flow/flowchart.md`、`md/test/test.md`

验证：

- 本地轻量检查：v3.47–v3.66、v3.68–v3.78 图片合同通过；v3.67 的 Swift evaluator 在当前本机环境未能返回结果，未将其本地结果作为证据；`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc -parse AITRANS/Views/ImageTranslationViews.swift`、项目版本解析 `v3.78`、ground truth/probe/clean-text JSON、CI YAML smoke 和 `git diff --check` 通过。v3.13 与 v3.78 定向合同在历史断言兼容修正后通过。
- 首次候选 full `30702773157` 因 v3.13 历史合同仍要求旧 `clearSelection` 闭包而失败，Xcode 本身成功；修正历史合同后 push `e79269ca`，不把该旧包作为最终验收证据。
- 最终候选 full `30703023530` / job `91377230913`：manifest 精确匹配 version/branch/commit/run/attempt/workflow，`validationProfile=full`、`validationReason=candidate_development_push`、`xcodeBuildRequired=true`；Xcode `buildResult.status=succeeded`，`.xcresult` build/root issues 为空，JUnit `10/10`、0 failures，UI/Speech/home/paste contracts 全部成功。结果包保存在 `/private/tmp/aitrans-c-review-30703023530`。
- PR #142 fast `30703289667` / job `91377936382`：精确候选 SHA，`validationProfile=fast`，`xcodeBuildRequired=false`，复用 full SHA `e79269ca9e74650f98d99f9f4c535548292ba6f3` 且 state `success`，skip reason 为 `fast_followup_reuses_candidate_full_validation`，JUnit `10/10`；结果包保存在 `/private/tmp/aitrans-c-review-30703289667`。
- merge fast `30703327543`：精确 merge SHA `83b6b31df5ae9224a55c9381f87cb018f908024c`，`validationReason=merge_reuses_successful_candidate_full_validation`，复用候选 full SHA `e79269ca9e74650f98d99f9f4c535548292ba6f3` / state `success`，`receiptPropagationAllowed=true`，Xcode skipped，JUnit `10/10`；结果包保存在 `/private/tmp/aitrans-c-review-30703327543`。
- 正式文档 follow-up `30703449646`：精确文档 SHA `e4eea8c45ac4782df010147f689e7bb5e1b49965`，`validationProfile=fast`、`validationReason=smalldata_metadata_followup_reuses_parent_full_validation`，父 merge SHA `83b6b31df5ae9224a55c9381f87cb018f908024c` / state `success`，`smalldataIncrementalMetadataOnly=true`、`receiptPropagationAllowed=true`，Xcode skipped，JUnit `10/10`；结果包保存在 `/private/tmp/aitrans-c-review-30703449646`。该 follow-up 只传播既有收据，不是新的 Swift/Xcode 编译证据。

未跑本机 build / 探针，按规则交给云端验证。候选 full、PR fast 均使用 `probe_mode=skip`，未生成新的漫画探针指标、`output/` 报告或 `metrics/version_history.csv` 行。full artifact 的 Koharu active gate 仍为 `manifestMissing / stopUntilArtifactsProvided`，缺少真实 manifest、TextBoxes、BubbleMask、SegmentMask；Speech corpus 为 `manifestMissing` 且 `qualityExecuted=false`。真实 Koharu 四件套、Speech 音频和真实竖排图片 corpus 仍缺失，本版只改善 VoiceOver 焦点交接，不声称 OCR、翻译、识别或 Koharu 质量提升。源码合同与云端 Xcode build 不能替代真实设备 VoiceOver、Dynamic Type、真实四件套或漫画探针。

## v3.77：无效局部预览状态的 VoiceOver 去重
日期：2026-08-01

状态：Agent X 已完成实现、合同与历史路由同步、云端 full/PR fast/merge fast 验收和合并收口；工程正式版本为 `MARKETING_VERSION=3.77`。候选分支 `codeb/v3.77-focus-preview-unavailable-voiceover` 的最终候选 HEAD 为 `4a39fbe279981e40ba13c3885aa839ce469219cb`，PR #141 已合入 `smalldata_test`，merge SHA 为 `98e69b46fe641a7099e0785a7e785bf07c4a10d5`，远端候选分支已删除，`main` 未触碰。

核心变更：

- `ImageTranslationFocusPreview.unavailableFocusState` 在 `contain` 容器内增加 `.accessibilityHidden(true)`，避免不可用状态子视图和父容器重复朗读；父容器继续通过 `focusPreviewAccessibilityHint` 统一说明局部预览不可用及关闭、编辑 OCR 原文、切换文字块的替代操作，所有按钮与 OCR context 保持不变。
- 新增 `scripts/test-v377-image-focus-preview-unavailable-voiceover-contract.py`，锁定隐藏状态、父容器提示、操作入口、View-only 边界、版本解析和 CI 路由；历史 v3.47–v3.76 图片合同同步接受 v3.77。该版本不新增 Store／持久化状态，不改变 Vision OCR、模型翻译、renderer/export、图片复查、漫画探针或 Koharu 主路径。

关键文件：

- `AITRANS/Views/ImageTranslationViews.swift`
- `AITRANS.xcodeproj/project.pbxproj`
- `.github/workflows/ci-results.yml`
- `scripts/test-v377-image-focus-preview-unavailable-voiceover-contract.py`、v3.47–v3.76 合同路由
- `README.md`、`AGENTS.md`、`md/flow/flow.md`、`md/flow/flowchart.md`、`md/test/test.md`

验证：

- 本地轻量检查：v3.13、v3.14、v3.68、v3.75–v3.77 定向合同通过；`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc -parse AITRANS/Views/ImageTranslationViews.swift`、项目版本解析 `v3.77`、ground truth/probe/clean-text JSON、CI YAML smoke 和 `git diff --check` 通过。
- 候选 full run `30702137092` / job `91374887814`：manifest 精确匹配 version/branch/commit/run/attempt/workflow，`validationProfile=full`、`validationReason=candidate_development_push`、`xcodeBuildRequired=true`；Xcode `buildResult.status=succeeded`，`.xcresult` build/root issues 为空，JUnit `10/10`、0 failures，v3.77 合同 4/4。结果包保存在 `/private/tmp/aitrans-c-review-30702137092`。
- PR #141 fast run `30702323549` / job `91375384896`：精确候选 SHA，`validationProfile=fast`，复用 full SHA `4a39fbe279981e40ba13c3885aa839ce469219cb` 且 state `success`，Xcode skipped reason 为 `fast_followup_reuses_candidate_full_validation`；JUnit `10/10`。结果包保存在 `/private/tmp/aitrans-c-review-30702323549`。
- merge fast run `30702348744`：精确 merge SHA `98e69b46fe641a7099e0785a7e785bf07c4a10d5`，`validationReason=merge_reuses_successful_candidate_full_validation`，复用候选 full 成功收据且 `receiptPropagationAllowed=true`，Xcode skipped；JUnit `10/10`。结果包保存在 `/private/tmp/aitrans-c-review-30702348744`。

未跑本机 build / 探针，按规则交给云端验证。候选、PR fast 和 merge fast 均使用 `probe_mode=skip`，未生成新的漫画探针指标、`output/` 报告或 `metrics/version_history.csv` 行。full artifact 的 Koharu gate 仍为 `manifestMissing / stopUntilArtifactsProvided`，Speech corpus 为 `manifestMissing` 且 `qualityExecuted=false`；真实 Koharu 四件套、Speech 音频和真实竖排图片 corpus 仍缺失，本版不声称 OCR、翻译、识别或 Koharu 质量提升。源码合同不能替代真实设备／模拟器 VoiceOver、Dynamic Type、真实四件套或探针。

## v3.76：局部聚焦预览装饰角标去重
日期：2026-08-01

状态：Agent X 已完成实现、合同与历史路由同步、云端 full/PR fast/merge fast 验收和合并收口；工程正式版本为 `MARKETING_VERSION=3.76`。候选分支 `codeb/v3.76-focus-preview-decorative-label` 的最终候选 HEAD 为 `1c3d7e4f404c584d633eefc3822a441df6c7f6fb`，PR #140 已合入 `smalldata_test`，merge SHA 为 `2ef5be10118d7f9edfcdbdd7a2b9bbd1ed29bff8`，远端候选分支已删除，`main` 未触碰。

核心变更：

- `ImageTranslationFocusPreview` 的“局部放大”装饰 `Label` 增加 `.accessibilityHidden(true)`；父容器继续提供“已定位文字块局部放大”label、位置／OCR value、操作 hint，关闭、OCR 修正、复查及前后定位按钮保持可访问，避免 VoiceOver 重复朗读。
- 新增 `scripts/test-v376-image-focus-preview-decorative-label-contract.py`，锁定装饰标签隐藏、父容器上下文、View-only 边界、版本解析和 CI 路由；历史 v3.47–v3.75 图片合同同步接受 v3.76。该版本不新增 Store／持久化状态，不改变 Vision OCR、模型翻译、renderer/export、图片复查、漫画探针或 Koharu 主路径。

关键文件：

- `AITRANS/Views/ImageTranslationViews.swift`
- `AITRANS.xcodeproj/project.pbxproj`
- `.github/workflows/ci-results.yml`
- `scripts/test-v376-image-focus-preview-decorative-label-contract.py`、v3.47–v3.75 合同路由
- `README.md`、`AGENTS.md`、`md/flow/flow.md`、`md/flow/flowchart.md`、`md/test/test.md`

验证：

- 本地轻量检查：v3.13、v3.14、v3.68、v3.74–v3.76 定向合同通过；`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc -parse AITRANS/Views/ImageTranslationViews.swift`、项目版本解析 `v3.76`、ground truth/probe/clean-text JSON、CI YAML smoke 和 `git diff --check` 通过。
- 候选 full run `30701702865` / job `91373719205`：manifest 精确匹配 version/branch/commit/run/attempt/workflow，`validationProfile=full`、`validationReason=candidate_development_push`、`xcodeBuildRequired=true`；Xcode `buildResult.status=succeeded`，`.xcresult` build/root issues 为空，JUnit `10/10`、0 failures，v3.76 合同 4/4。结果包保存在 `/private/tmp/aitrans-c-review-30701702865`。
- PR #140 fast run `30701897639` / job `91374240896`：精确候选 SHA，`validationProfile=fast`，复用 full SHA `1c3d7e4f404c584d633eefc3822a441df6c7f6fb` 且 state `success`，Xcode skipped reason 为 `fast_followup_reuses_candidate_full_validation`；JUnit `10/10`。结果包保存在 `/private/tmp/aitrans-c-review-30701897639`。
- merge fast run `30701926101`：精确 merge SHA `2ef5be10118d7f9edfcdbdd7a2b9bbd1ed29bff8`，`validationReason=merge_reuses_successful_candidate_full_validation`，复用候选 full 成功收据且 `receiptPropagationAllowed=true`，Xcode skipped；JUnit `10/10`。结果包保存在 `/private/tmp/aitrans-c-review-30701926101`。

未跑本机 build / 探针，按规则交给云端验证。候选、PR fast 和 merge fast 均使用 `probe_mode=skip`，未生成新的漫画探针指标、`output/` 报告或 `metrics/version_history.csv` 行。full artifact 的 Koharu gate 仍为 `manifestMissing / stopUntilArtifactsProvided`，Speech corpus 为 `manifestMissing` 且 `qualityExecuted=false`；真实 Koharu 四件套、Speech 音频和真实竖排图片 corpus 仍缺失，本版不声称 OCR、翻译、识别或 Koharu 质量提升。源码合同不能替代真实设备／模拟器 VoiceOver、Dynamic Type、真实四件套或探针。

## v3.75：图片 OCR 参考与局部聚焦空原文无障碍上下文
日期：2026-08-01

状态：Agent X 已完成实现、历史合同兼容修复、云端 full/PR fast/merge fast 验收和合并收口；工程正式版本为 `MARKETING_VERSION=3.75`。候选分支 `codeb/v3.75-image-focus-empty-ocr-context` 的最终候选 HEAD 为 `3b8a48e1d52212d6c8e29c5ae466ada76257dd85`，PR #139 已合入 `smalldata_test`，merge SHA 为 `10680d1abefd5dee4b11b2813ea6d78cf8e1b17c`，远端候选分支已删除，`main` 未触碰。

核心变更：

- `ImageOCRCorrectionReferencePreview` 与 `ImageTranslationFocusPreview` 的 VoiceOver value 统一消费 View 私有 `accessibilityOriginalText`；`block.original` 为空时读出“空”，非空 OCR 原文保持原样，避免参考图和局部定位入口出现无上下文空白。
- 新增 `scripts/test-v375-image-focus-empty-ocr-context-contract.py`，锁定 reference/focus 两条 value 回退、View-only 边界、版本解析和 CI 路由；同步让 v3.13、v3.14、v3.68 历史合同接受当前稳定回退。该版本不新增 Store／持久化状态，不改变 Vision OCR、模型翻译、renderer/export、图片复查、漫画探针或 Koharu 主路径。

关键文件：

- `AITRANS/Views/ImageTranslationViews.swift`
- `AITRANS.xcodeproj/project.pbxproj`
- `.github/workflows/ci-results.yml`
- `scripts/test-v375-image-focus-empty-ocr-context-contract.py`、v3.13/v3.14/v3.68 兼容合同
- `README.md`、`AGENTS.md`、`md/flow/flow.md`、`md/flow/flowchart.md`、`md/test/test.md`

验证：

- 本地轻量检查：v3.13、v3.14、v3.68–v3.75 定向合同通过；`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc -parse AITRANS/Views/ImageTranslationViews.swift`、项目版本解析 `v3.75`、ground truth/probe/clean-text JSON、CI YAML smoke 和 `git diff --check` 通过。
- 候选 full run `30701053975` / job `91372015128`：manifest 精确匹配 version/branch/commit/run/attempt/workflow，`validationProfile=full`、`validationReason=candidate_development_push`、`xcodeBuildRequired=true`；Xcode `buildResult.status=succeeded`，`.xcresult` build/root issue 为空，JUnit `10/10`、0 failures，v3.75 合同 4/4。结果包保存在 `/private/tmp/aitrans-c-review-30701053975`。
- PR #139 fast run `30701307339` / job `91372681264`：精确候选 SHA，`validationProfile=fast`，复用 full SHA `3b8a48e1d52212d6c8e29c5ae466ada76257dd85` 且 state `success`，Xcode skipped reason 为 `fast_followup_reuses_candidate_full_validation`；JUnit `10/10`。结果包保存在 `/private/tmp/aitrans-c-review-30701307339`。
- merge fast run `30701342492`：精确 merge SHA `10680d1abefd5dee4b11b2813ea6d78cf8e1b17c`，`validationReason=merge_reuses_successful_candidate_full_validation`，复用候选 full 成功收据且 `receiptPropagationAllowed=true`，Xcode skipped；JUnit `10/10`。结果包保存在 `/private/tmp/aitrans-c-review-30701342492`。
- 早期 full 运行 `30700322133`、`30700591153`、`30700790855` 的 Xcode 均成功，失败原因仅为历史 v3.13/v3.14/v3.68 合同仍硬编码旧 VoiceOver value；已在后续提交中修正，最终 full 运行通过，不把这些早期包作为验收证据。

未跑本机 build / 探针，按规则交给云端验证。候选、PR fast 和 merge fast 均使用 `probe_mode=skip`，未生成新的漫画探针指标、`output/` 报告或 `metrics/version_history.csv` 行。full artifact 的 Koharu gate 仍为 `manifestMissing / stopUntilArtifactsProvided`，Speech corpus 为 `manifestMissing` 且 `qualityExecuted=false`；真实 Koharu 四件套、Speech 音频和真实竖排图片 corpus 仍缺失，本版不声称 OCR、翻译、识别或 Koharu 质量提升。源码合同不能替代真实设备／模拟器 VoiceOver、Dynamic Type、真实四件套或探针。

## v3.74：普通结果行与图片覆盖的空 OCR 回退一致性
日期：2026-08-01

状态：Agent X 已完成实现、云端验收和合并收口；工程正式版本为 `MARKETING_VERSION=3.74`。候选分支 `codeb/v3.74-image-empty-ocr-consistency` 的最终候选 HEAD 为 `62f41ffe2efddfcae6f0d501ab1b259ffcf37c05`，PR #138 已合入 `smalldata_test`，merge SHA 为 `b7d874a9470cb6bc8977d2f5b1177a3a12520d9b`，远端候选分支已删除，`main` 未触碰。

核心变更：

- 普通 `ImageTranslationBlockRow` 在 `block.original` 为空时显示“空 OCR 原文”，避免 OCR 原文与译文同时为空时留下无上下文空白。
- `ImageTranslationOverlayBlock` 的旁贴与覆盖两种模式共用空 OCR 回退；译文非空时仍保持译文优先，只有译文也为空时显示“空 OCR 原文”。选择、定位、复查、Store ownership、renderer/export 和既有无障碍边界不变。
- 新增 `scripts/test-v374-image-empty-ocr-consistency-contract.py`，并将 v3.47–v3.73 历史图片合同及 CI 路由推进到 v3.74。该版本只改善 View 语义，不新增 Store／持久化状态，不改变 Vision OCR、模型翻译、漫画探针、Koharu 主路径或质量基线。

关键文件：

- `AITRANS/Views/ImageTranslationViews.swift`
- `AITRANS.xcodeproj/project.pbxproj`
- `.github/workflows/ci-results.yml`
- `scripts/test-v374-image-empty-ocr-consistency-contract.py`、v3.73 合同及 v3.47–v3.72 图片合同路由
- `README.md`、`AGENTS.md`、`md/flow/flow.md`、`md/flow/flowchart.md`、`md/test/test.md`

验证：

- 本地轻量检查：v3.58、v3.59、v3.60、v3.73、v3.74 定向合同通过；`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc -parse AITRANS/Views/ImageTranslationViews.swift`、版本解析 `v3.74` 和 `git diff --check` 通过。
- 候选 full run `30699495962` / job `91367853529`：manifest 精确匹配 version/branch/commit/run/attempt/workflow，`validationProfile=full`、`validationReason=candidate_development_push`、`xcodeBuildRequired=true`；Xcode `buildResult.status=succeeded`，`.xcresult` 无 issue，JUnit `10/10`、0 failures，v3.74 合同 4/4。结果包保存在 `/private/tmp/aitrans-c-review-30699495962`。
- PR #138 fast run `30699776161` / job `91368630418`：精确候选 SHA，`validationProfile=fast`，复用 full SHA `62f41ffe2efddfcae6f0d501ab1b259ffcf37c05` 且 state `success`，Xcode skipped reason 为 `fast_followup_reuses_candidate_full_validation`；JUnit `10/10`。结果包保存在 `/private/tmp/aitrans-c-review-30699776161`。
- merge fast run `30699876976` / job `91368898157`：精确 merge SHA `b7d874a9470cb6bc8977d2f5b1177a3a12520d9b`，second parent 为候选 SHA，`validationReason=merge_reuses_successful_candidate_full_validation`，复用候选 full 成功收据且 `receiptPropagationAllowed=true`，Xcode skipped；JUnit `10/10`。该 run 以同一 merge SHA 的 `workflow_dispatch validation_profile=auto` 触发，结果包保存在 `/private/tmp/aitrans-c-review-30699876976`。

未跑本机 build / 探针，按规则交给云端验证。full、PR fast 和 merge fast 均使用 `probe_mode=skip`，未生成新的漫画探针指标、`output/` 报告或 `metrics/version_history.csv` 行。full artifact 的 Koharu gate 仍为 `manifestMissing / stopUntilArtifactsProvided`，Speech corpus 为 `manifestMissing` 且 `qualityExecuted=false`；真实 Koharu 四件套、Speech 音频和真实竖排图片 corpus 仍缺失，本版不声称 OCR、翻译、识别或 Koharu 质量提升。源码合同不能替代真实设备／模拟器 VoiceOver、Dynamic Type、真实四件套或探针。

## v3.73：空 OCR ignored row 的可见与无障碍回退
日期：2026-08-01

状态：Agent X 已完成实现、云端验收和合并收口；工程正式版本为 `MARKETING_VERSION=3.73`。候选分支 `codeb/v3.73-ignored-ocr-empty-context` 的最终候选 HEAD 为 `c771572f7cf9cb31da67f05660d8682fefe7485d`，PR #137 已合入 `smalldata_test`，merge SHA 为 `fb7b3acd8b2f76a7cb92ac29fbdfc154a8481505`，远端候选分支已删除，`main` 未触碰。

核心变更：

- `ImageTranslationIgnoredBlockRow` 对空 `block.original` 显示“空 OCR 原文”，并让稳定 VoiceOver label 使用“空”回退；非空原文仍原样显示。
- 恢复按钮、disabled 原因、焦点 identity、译文保留说明和恢复到图片预览／导出／转录的范围保持不变。该改动仅改善 View/无障碍语义，不新增 Store／持久化状态，不改变 Vision OCR、模型翻译、renderer/export、漫画探针或 Koharu 主路径。
- 新增 `scripts/test-v373-image-ignored-empty-context-contract.py`；历史 v3.47–v3.72 UI 合同与 `.github/workflows/ci-results.yml` 路由同步接受 v3.73，v3.53 合同更新为共享稳定 label。

关键文件：

- `AITRANS/Views/ImageTranslationViews.swift`
- `AITRANS.xcodeproj/project.pbxproj`
- `.github/workflows/ci-results.yml`
- `scripts/test-v373-image-ignored-empty-context-contract.py`、v3.53 合同及 v3.47–v3.72 图片合同路由
- `README.md`、`AGENTS.md`、`md/flow/flow.md`、`md/flow/flowchart.md`、`md/test/test.md`

验证：

- 本地轻量检查：v3.47–v3.73 合同循环无失败；v3.53、v3.72、v3.73 定向合同通过，v3.73 为 5/5；`xcrun swiftc -parse AITRANS/Views/ImageTranslationViews.swift`、版本解析 `v3.73` 和 `git diff --check` 通过。
- 候选 full run `30699003755` / job `91366582157`：manifest 精确匹配 version/branch/commit/run/attempt/workflow，`validationProfile=full`、`validationReason=candidate_development_push`、`xcodeBuildRequired=true`；Xcode `buildResult.status=succeeded`，`.xcresult` 0 warnings/0 errors，JUnit `10/10`、0 failures，v3.73 UI 合同通过。结果包保存在 `/private/tmp/aitrans-c-review-30699003755`。
- PR #137 fast run `30699290015` / job `91367300396`：精确候选 SHA，`validationProfile=fast`，复用 full SHA `c771572f7cf9cb31da67f05660d8682fefe7485d` 且 state `success`，Xcode skipped reason 为 `fast_followup_reuses_candidate_full_validation`；JUnit `10/10`。结果包保存在 `/private/tmp/aitrans-c-review-30699290015`。
- merge fast run `30699316600` / job `91367364868`：精确 merge SHA `fb7b3acd8b2f76a7cb92ac29fbdfc154a8481505`，second parent 为候选 SHA，`validationReason=merge_reuses_successful_candidate_full_validation`，复用候选 full 成功收据且 `receiptPropagationAllowed=true`，Xcode skipped；JUnit `10/10`。结果包保存在 `/private/tmp/aitrans-c-review-30699316600`。

未跑本机 build / 探针，按规则交给云端验证。full、PR fast 和 merge fast 均使用 `probe_mode=skip`，未生成新的漫画探针指标、`output/` 报告或 `metrics/version_history.csv` 行。full artifact 的 Koharu gate 仍为 `manifestMissing / stopUntilArtifactsProvided`，Speech corpus 为 `manifestMissing` 且 `qualityExecuted=false`；真实 Koharu 四件套、Speech 音频和真实竖排图片 corpus 仍缺失，本版不声称 OCR、翻译、识别或 Koharu 质量提升。源码合同不能替代真实设备／模拟器 VoiceOver、Dynamic Type、真实四件套或探针。

## v3.72：区分 Koharu v1 summary-only 与 v2 门控失败
日期：2026-08-01

状态：Agent X 已完成实现、警告修复、云端验收和合并收口；工程正式版本为 `MARKETING_VERSION=3.72`。候选分支 `codeb/v3.72-koharu-v1-readiness-clarity` 的最终候选 HEAD 为 `a70daa379959dc9772b8bd5776036c24419964c8`，PR #136 已合入 `smalldata_test`，merge SHA 为 `02e5b8bc2c1894bf866dd3a64f7f6f6b867cc99d`，远端候选分支已删除，`main` 未触碰。

核心变更：

- `MangaKoharuArtifactReadinessSummary` 识别 schema v1、bubble/segment payload verdict 均为 `legacySummaryOnly` 的旧工件；这类工件的 payload 状态显示为“未要求（v1 summary-only）”，topology 状态显示为“未要求（v2 拓扑）”，不再把尚未要求的 v2 门控朗读成失败。
- VoiceOver hint 与可复制 summary 共享解释后的门控状态，同时保留非 legacy v2 工件的真实 payload/topology 失败、blocker 和 CI 对账信息。变更仅为 View/report-only，不创建或修改 active `test/koharu_artifacts`，不放宽 readiness gate，不改变普通图片 OCR、模型翻译、renderer/export、漫画探针或 Koharu 主路径。
- 新增 `scripts/test-v372-koharu-v1-readiness-clarity-contract.py`；历史 v3.47–v3.71 UI 合同与 `.github/workflows/ci-results.yml` 路由同步接受 v3.72。

关键文件：

- `AITRANS/Views/DeveloperConsoleView.swift`
- `AITRANS.xcodeproj/project.pbxproj`
- `.github/workflows/ci-results.yml`
- `scripts/test-v372-koharu-v1-readiness-clarity-contract.py`、`scripts/test-v371-koharu-readiness-gate-detail-contract.py` 及 v3.47–v3.71 图片合同
- `README.md`、`AGENTS.md`、`md/flow/flow.md`、`md/flow/flowchart.md`、`md/test/test.md`

验证：

- 本地轻量检查：v3.71 合同 6/6、v3.72 合同 5/5，通过 `xcrun swiftc -parse AITRANS/Views/DeveloperConsoleView.swift`、版本解析 `v3.72` 和 `git diff --check`。候选 full 前的 v3.47–v3.72 合同循环无失败输出。
- 初始实现 full run `30698079526` / job `91364232077` 的 Xcode build 虽成功，但 `.xcresult` 记录 `DeveloperConsoleView.swift` 不可达重复 `return` 警告；该结果包保存在 `/private/tmp/aitrans-c-review-30698079526`，不作为最终候选证据。修复 commit 为 `a70daa379959dc9772b8bd5776036c24419964c8`。
- 最终候选 full run `30698413436` / job `91365079616`：manifest 精确匹配 version/branch/commit/run/attempt/workflow，`validationProfile=full`、`validationReason=candidate_development_push`、`xcodeBuildRequired=true`；Xcode `buildResult.status=succeeded`，`.xcresult` 0 warnings/0 errors，JUnit `10/10`、0 failures，v3.72 UI 合同通过。结果包保存在 `/private/tmp/aitrans-c-review-30698413436`。
- PR #136 fast run `30698654858` / job `91365691955`：精确候选 SHA，`validationProfile=fast`，复用 full SHA `a70daa379959dc9772b8bd5776036c24419964c8` 且 state `success`，Xcode skipped reason 为 `fast_followup_reuses_candidate_full_validation`；JUnit `10/10`。结果包保存在 `/private/tmp/aitrans-c-review-30698654858`。
- merge fast run `30698685445` / job `91365768370`：精确 merge SHA `02e5b8bc2c1894bf866dd3a64f7f6f6b867cc99d`，second parent 为候选 SHA，`validationReason=merge_reuses_successful_candidate_full_validation`，复用候选 full 成功收据且 `receiptPropagationAllowed=true`，Xcode skipped；JUnit `10/10`。结果包保存在 `/private/tmp/aitrans-c-review-30698685445`。

未跑本机 build / 探针，按规则交给云端验证。full、PR fast 和 merge fast 均使用 `probe_mode=skip`，未生成新的漫画探针指标、`output/` 报告或 `metrics/version_history.csv` 行。最终 full artifact 未要求 Koharu extended validator（变更后的提交只修正可达性），但初始核心 full 已通过 v3.72 合同与 Koharu validator 路由；当前 Koharu active gate 仍为 `manifestMissing / stopUntilArtifactsProvided`，Speech corpus 为 `manifestMissing` 且 `qualityExecuted=false`。真实 Koharu 四件套、Speech 音频和真实竖排图片 corpus 仍缺失，本版不声称 OCR、翻译、识别或 Koharu 质量提升。源码合同不能替代真实设备／模拟器 VoiceOver、Dynamic Type、真实四件套或探针。

## v3.71：Koharu readiness 下游门控摘要
日期：2026-08-01

状态：Agent X 已完成实现、失败修复、云端验收和合并收口；工程正式版本为 `MARKETING_VERSION=3.71`。候选分支 `codeb/v3.71-koharu-readiness-gates` 的最终候选 HEAD 为 `43f050b60246f0921bb48dafceb9a7bf3e42fcbf`，PR #135 已合入 `smalldata_test`，merge SHA 为 `5a3dd7a9dab8efb2862be881702c034558ac9f44`，远端候选分支已删除，`main` 未触碰。

核心变更：

- `MangaKoharuArtifactReadinessSummary` 继续只读漫画探针返回的 `MangaOverlayExternalArtifactReadinessReport`，并在状态行、VoiceOver hint 与可复制 code block 中汇总坐标验证、mask payload verdict/gate、mask topology verdict/blockers 和 artifact identity receipt。
- readiness gate、shadow OCR 边界和 active `test/koharu_artifacts` 政策保持不变；缺少真实四件套时仍显示 `manifestMissing / stopUntilArtifactsProvided`，proxy 与 contract example 仍不得晋级为真实 Koharu 工件。
- 新增 `scripts/test-v371-koharu-readiness-gate-detail-contract.py`；历史 v3.47–v3.70 UI 合同与 `.github/workflows/ci-results.yml` 路由同步接受 v3.71。该版本只改善开发者诊断和 VoiceOver/可复制摘要语义，不改变普通图片 OCR、模型翻译、renderer/export、漫画探针、Koharu 主路径、ground truth、metrics 或 output。

关键文件：

- `AITRANS/Views/DeveloperConsoleView.swift`
- `AITRANS.xcodeproj/project.pbxproj`
- `.github/workflows/ci-results.yml`
- `scripts/test-v371-koharu-readiness-gate-detail-contract.py` 及 v3.47–v3.70 图片合同
- `README.md`、`AGENTS.md`、`md/flow/flow.md`、`md/flow/flowchart.md`、`md/test/test.md`

验证：

- 本地轻量检查：v3.47–v3.71 图片/探针 UI 合同 25 个全部通过；全量 Python v* 合同套件通过；`xcrun swiftc -parse AITRANS/Views/DeveloperConsoleView.swift`、JSON smoke、版本解析 `v3.71` 和 `git diff --check` 通过。
- 首次候选 full run `30697293960` / job `91362222932` 曾因新 getter 缺少显式 `return` 导致 Xcode exit 65；结果包保存在 `/private/tmp/aitrans-c-review-30697293960`，不作为验收证据。修复 commit 为 `43f050b60246f0921bb48dafceb9a7bf3e42fcbf`。
- 修复后候选 full run `30697411218` / job `91362524455`：manifest 精确匹配 version/branch/commit/run/attempt/workflow，`validationProfile=full`、`validationReason=candidate_development_push`、`xcodeBuildRequired=true`；Xcode `buildResult.status=succeeded`，JUnit `10/10`、0 failures，static、Speech、UI、home/paste 合同均通过。结果包保存在 `/private/tmp/aitrans-c-review-30697411218`。
- PR #135 fast run `30697630421`：精确候选 SHA，`validationProfile=fast`，复用 full SHA `43f050b60246f0921bb48dafceb9a7bf3e42fcbf` 且 state `success`，Xcode skipped reason 为 `fast_followup_reuses_candidate_full_validation`；JUnit `10/10`。结果包保存在 `/private/tmp/aitrans-c-review-30697630421`。
- merge fast run `30697672316`：精确 merge SHA `5a3dd7a9dab8efb2862be881702c034558ac9f44`，second parent 为候选 SHA，`validationReason=merge_reuses_successful_candidate_full_validation`，复用候选 full 成功收据且 `receiptPropagationAllowed=true`，Xcode skipped；JUnit `10/10`。结果包保存在 `/private/tmp/aitrans-c-review-30697672316`。

未跑本机 build / 探针，按规则交给云端验证。full、PR fast 和 merge fast 均使用 `probe_mode=skip`，未生成新的漫画探针指标、`output/` 报告或 `metrics/version_history.csv` 行。full artifact 的 Koharu gate 为 `manifestMissing / stopUntilArtifactsProvided`，`maskPayloadGateReady=false`、`maskTopologyGateReady=false`；Speech corpus 为 `manifestMissing` 且 `qualityExecuted=false`。真实 Koharu 四件套、Speech 音频和真实竖排图片 corpus 仍缺失，本版不声称 OCR、翻译、识别或 Koharu 质量提升。源码合同不能替代真实设备／模拟器 VoiceOver、Dynamic Type、真实四件套或探针。

## v3.70：图片预览几何 hint 分流
日期：2026-08-01

状态：Agent X 已完成实现、云端验收和合并收口；工程正式版本为 `MARKETING_VERSION=3.70`。候选分支 `codeb/v3.70-image-preview-geometry-hint` 的候选 HEAD 为 `502e6c763e537cacc84300915c0a841ce1d130e7`，PR #134 已合入 `smalldata_test`，merge SHA 为 `294b74259cb934b731db981ad8f9245c36081555`，远端候选分支已删除，`main` 未触碰。

核心变更：

- `ImageTranslationPreview.previewAccessibilityHint` 根据既有 block 的几何可用性动态分流：全部有效时保留“点按文字块可定位并打开局部放大”，存在无效或过期框时说明有效文字块可打开局部放大、异常文字块局部预览不可用。
- 继续保留 v3.69 的定位不可用摘要、结果行图标、OCR 修正和切换文字块入口；该版本只消费 `NormalizedImageRect.normalizedToUnit()`，不新增 Store／持久化状态，不改变 Vision OCR、模型翻译、renderer/export、漫画探针、Koharu 主路径、ground truth、metrics 或 output。
- 新增 `scripts/test-v370-image-preview-geometry-hint-contract.py`；历史 v3.47–v3.69 图片合同的版本路由同步接受 v3.70。

关键文件：

- `AITRANS/Views/ImageTranslationViews.swift`
- `AITRANS.xcodeproj/project.pbxproj`
- `.github/workflows/ci-results.yml`
- `scripts/test-v370-image-preview-geometry-hint-contract.py` 及 v3.47–v3.69 图片合同
- `README.md`、`AGENTS.md`、`md/flow/flow.md`、`md/flow/flowchart.md`、`md/test/test.md`

验证：

- 本地轻量检查：v3.47–v3.70 图片合同、v3.13 focus 回归、v3.10 预览/筛选回归、v1.94/v1.97 CI 合同、Swift parse、JSON smoke、版本解析和 `git diff --check` 通过。
- 候选 full run `30696508365` / job `91360218281`：manifest 精确匹配 version/branch/commit/run/attempt/workflow，`validationProfile=full`、`validationReason=candidate_development_push`、`xcodeBuildRequired=true`；Xcode build succeeded，`.xcresult` build status 为 `succeeded`、issues 为空，JUnit `10/10`、0 failures，static、Speech、UI、home/paste 合同均通过。结果包保存在 `/private/tmp/aitrans-c-review-30696508365`。
- PR #134 fast run `30696739339`：精确候选 SHA，`validationProfile=fast`，复用 full SHA `502e6c763e537cacc84300915c0a841ce1d130e7` 且 state `success`，Xcode skipped；JUnit `10/10`。结果包保存在 `/private/tmp/aitrans-c-review-30696739339`。
- merge fast run `30696776714`：精确 merge SHA `294b74259cb934b731db981ad8f9245c36081555`，`validationReason=merge_reuses_successful_candidate_full_validation`，复用候选 full 成功收据，`receiptPropagationAllowed=true`，Xcode skipped；JUnit `10/10`。结果包保存在 `/private/tmp/aitrans-c-review-30696776714`。

未跑本机 build / 探针，按规则交给云端验证。候选 full、PR fast 和 merge fast 均使用 `probe_mode=skip`，未生成新的漫画探针指标、`output/` 报告或 `metrics/version_history.csv` 行。真实 Koharu 四件套、Speech corpus 与真实竖排图片 corpus 仍缺失；full artifact 的 active Koharu gate 为 `manifestMissing / stopUntilArtifactsProvided`，本版不声称 OCR、翻译、识别或 Koharu 质量提升。源码合同不能替代真实设备／模拟器 VoiceOver、Dynamic Type 和真实图片 corpus。

## v3.69：图片几何定位可用性提前反馈
日期：2026-08-01

状态：Agent X 已完成实现、云端验收和合并收口；工程正式版本为 `MARKETING_VERSION=3.69`。候选分支 `codeb/v3.69-image-geometry-availability` 的候选 HEAD 为 `bd13c008176f7033afcda4ac8cb1bc3ee55c6720`，PR #133 已合入 `smalldata_test`，merge SHA 为 `6a8b5a8d37e9897c108f13f7ea526496a1caae6b`，远端候选分支已删除，`main` 未触碰。

核心变更：

- `ImageTranslationPreview` 的 VoiceOver value 统计既有完整 block 中定位不可用的数量，避免用户必须逐个打开局部放大才发现异常几何。
- `ImageTranslationBlockRow` 对无效或过期 `NormalizedImageRect` 显示“图片定位不可用”图标，并在 accessibility value/hint 中说明局部预览边界；OCR 修正和切换文字块入口保持可用（受既有状态门约束）。
- 新增 `scripts/test-v369-image-geometry-availability-contract.py`；历史 v3.47–v3.68 图片合同的版本路由同步接受 v3.69。该版本只复用 `NormalizedImageRect.normalizedToUnit()`，不新增 Store／持久化状态，不改变 Vision OCR 候选、模型翻译、renderer/export、漫画探针、Koharu 主路径、ground truth、metrics 或 output。

关键文件：

- `AITRANS/Views/ImageTranslationViews.swift`
- `AITRANS.xcodeproj/project.pbxproj`
- `.github/workflows/ci-results.yml`
- `scripts/test-v369-image-geometry-availability-contract.py` 及 v3.47–v3.68 图片合同
- `README.md`、`AGENTS.md`、`md/flow/flow.md`、`md/flow/flowchart.md`、`md/test/test.md`

验证：

- 本地轻量检查：v3.47–v3.69 图片合同、v3.13 focus 回归、v3.10 预览/筛选回归、v1.94/v1.97 CI 合同、Swift parse、JSON smoke、版本解析和 `git diff --check` 通过。
- 候选 full run `30695999718` / job `91358890272`：manifest 精确匹配 version/branch/commit/run/attempt/workflow，`validationProfile=full`、`validationReason=candidate_development_push`、`xcodeBuildRequired=true`；Xcode build succeeded，`.xcresult` build status 为 `succeeded`、issues 为空，JUnit `10/10`、0 failures，static、Speech、UI、home/paste 合同均通过。结果包保存在 `/private/tmp/aitrans-c-review-30695999718`。
- PR #133 fast run `30696236137`：精确候选 SHA，`validationProfile=fast`，复用 full SHA `bd13c008176f7033afcda4ac8cb1bc3ee55c6720` 且 state `success`，Xcode skipped；JUnit `10/10`。结果包保存在 `/private/tmp/aitrans-c-review-30696236137`。
- merge fast run `30696275548`：精确 merge SHA `6a8b5a8d37e9897c108f13f7ea526496a1caae6b`，`validationReason=merge_reuses_successful_candidate_full_validation`，复用候选 full 成功收据，`receiptPropagationAllowed=true`，Xcode skipped；JUnit `10/10`。结果包保存在 `/private/tmp/aitrans-c-review-30696275548`。

未跑本机 build / 探针，按规则交给云端验证。候选 full、PR fast 和 merge fast 均使用 `probe_mode=skip`，未生成新的漫画探针指标、`output/` 报告或 `metrics/version_history.csv` 行。真实 Koharu 四件套、Speech corpus 与真实竖排图片 corpus 仍缺失；full artifact 的 active Koharu gate 为 `manifestMissing / stopUntilArtifactsProvided`，本版不声称 OCR、翻译、识别或 Koharu 质量提升。源码合同不能替代真实设备／模拟器 VoiceOver、Dynamic Type 和真实图片 corpus。

## v3.68：无效图片局部预览明确反馈
日期：2026-08-01

状态：Agent X 已完成实现、失败修复、云端验收和合并收口；工程正式版本为 `MARKETING_VERSION=3.68`。候选分支 `codeb/v3.68-image-preview-invalid-geometry` 的最终候选 HEAD 为 `1f6a778b6f51a34f96358baa5a32af384f947d34`，PR #132 已合入 `smalldata_test`，merge SHA 为 `5bf5731f479d1a768988f2ff23a4fde4480342e8`，远端候选分支已删除，`main` 未触碰。

核心变更：

- `ImageTranslationBlockFocusCrop.normalizedFocusRect(for:)` 现在返回可选矩形；无效或过期 `NormalizedImageRect` 不再回退为整图，crop 构造直接返回 `nil`。
- `ImageTranslationFocusPreview` 在 crop 不可用时显示“当前文字块局部预览不可用”，保留关闭、编辑 OCR 原文和切换文字块入口，并以 VoiceOver hint 说明仍可执行的替代操作；已有 accessibility value 保持不变，避免回归历史 UI 合同。
- OCR 修正 sheet 的局部对照仍复用同一 crop 边界，异常框只显示“图片局部预览不可用，仍可编辑 OCR 原文”；新增 `scripts/test-v368-image-preview-invalid-geometry-contract.py`，历史 v3.47–v3.67 图片合同路由同步接受 v3.68。
- 该版本只改善异常恢复数据下的 View 反馈，不新增 Store／持久化状态，不改变 Vision OCR 候选、翻译、renderer/export、漫画探针、Koharu 主路径、ground truth、metrics 或 output。

关键文件：

- `AITRANS/Views/ImageTranslationViews.swift`
- `AITRANS.xcodeproj/project.pbxproj`
- `.github/workflows/ci-results.yml`
- `scripts/test-v368-image-preview-invalid-geometry-contract.py`
- v3.47–v3.67 图片合同与 `README.md`、`AGENTS.md`、flow/test 文档

验证：

- 本地轻量检查：v3.47–v3.68 图片合同套件（含 v3.67 model evaluator）、v3.13 focus 回归合同、JSON smoke、版本解析、Swift parse 和 `git diff --check` 通过；未跑本机完整 Xcode build / 漫画探针。
- 早期候选 full run `30695061047` / job `91356406477`（SHA `c6a2cc7e65e88d8d1c56fde3133fd4233566a825`）的 Xcode build 成功，但历史 v1.87 focus 合同因 accessibility value 被替换而失败；该 run 不作为验收证据，结果包保存在 `/private/tmp/aitrans-c-review-30695061047`。
- 修复后最终候选 full run `30695264077` / job `91356938808`：manifest 精确匹配 version/branch/commit/run/attempt/workflow，`validationProfile=full`、`validationReason=candidate_development_push`、`xcodeBuildRequired=true`；Xcode build success，`.xcresult` 与 `xcodebuild.log` 已上传，JUnit `10/10`、0 failures，static、Speech、UI、home/paste 合同均通过。结果包保存在 `/private/tmp/aitrans-c-review-30695264077`。
- PR #132 fast run `30695564579`：精确候选 SHA，`validationProfile=fast`，复用 full SHA `1f6a778b6f51a34f96358baa5a32af384f947d34` 且 state `success`，Xcode skipped；JUnit `10/10`。结果包保存在 `/private/tmp/aitrans-c-review-30695564579`。
- merge fast run `30695598256`：精确 merge SHA `5bf5731f479d1a768988f2ff23a4fde4480342e8`，`validationReason=merge_reuses_successful_candidate_full_validation`，复用候选 full 成功收据、`receiptPropagationAllowed=true`，Xcode skipped；JUnit `10/10`。结果包保存在 `/private/tmp/aitrans-c-review-30695598256`。

未跑本机 build / 探针，按规则交给云端验证。候选 full、PR fast 和 merge fast 均使用 `probe_mode=skip`，未生成新的漫画探针指标、`output/` 报告或 `metrics/version_history.csv` 行。真实 Koharu 四件套、Speech corpus 与真实竖排图片 corpus 仍缺失；full artifact 的 active Koharu gate 为 `manifestMissing / stopUntilArtifactsProvided`，本版不声称 OCR、翻译、识别或 Koharu 质量提升。源码合同不能替代真实设备／模拟器 VoiceOver、Dynamic Type 和真实图片 corpus。

## v3.67：恢复图片 block 几何安全
日期：2026-08-01

状态：Agent X 已完成实现、失败修复、云端验收和合并收口；工程正式版本为 `MARKETING_VERSION=3.67`。候选分支 `codeb/v3.67-image-block-geometry-safety` 的最终候选 HEAD 为 `bdf9d6303bf27296f7ed435b2e5daaf7c212502b`，PR #131 已合入 `smalldata_test`，merge SHA 为 `9684b3d736fc647bdb244cb01e5f8f0c48ec5c55`，远端候选分支已删除，`main` 未触碰。

核心变更：

- `NormalizedImageRect.normalizedToUnit()` 复用 finite、正面积、单位坐标整矩形边界；旧会话或外部解码的 NaN/∞、零面积和完全越界框不会进入完整图片覆盖、局部定位或导出 renderer，且不会写回持久化。
- 图片覆盖 View 对无效框跳过 overlay，局部 focus crop 返回安全回退，导出 `imageTranslationPixelRect` 对无效框返回空 rect；有效框保持既有裁剪、定位和旁贴／覆盖语义。
- 新增 `scripts/test-v367-image-block-geometry-safety-contract.py` 与纯 Swift model evaluator；历史 v3.47–v3.66 图片合同和 CI 路由同步接受后续正式版本。该版本不改变 OCR 候选、翻译、renderer/export 的有效框语义、漫画探针、Koharu 主路径、ground truth、metrics 或 output。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Views/ImageTranslationViews.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS.xcodeproj/project.pbxproj`
- `.github/workflows/ci-results.yml`
- `scripts/test-v367-image-block-geometry-safety-contract.py`
- `scripts/test-v367-image-block-geometry-safety-evaluator.swift`
- v3.47–v3.66 图片合同与 `README.md`、`AGENTS.md`、flow/test 文档

验证：

- 本地轻量检查：v3.47–v3.67 图片合同套件、v2.7/v3.0/v3.1/v3.10–v3.17 图片回归、v3.67 model evaluator、Swift parse、JSON/YAML smoke、版本解析和 `git diff --check` 通过。
- 早期候选 full run `30694149039` / job `91353972337`（SHA `8f970799bc241a44f348173554744d1dae4674ae`）的 static/Speech/UI/home/paste 合同通过，但 Xcode 因 `TranslationSessionStore.imageTranslationPixelRect` guard 后缺少 `return` 失败；该 run 不作为验收证据，结果包保存在 `/private/tmp/aitrans-c-review-30694149039`。
- 修复后最终候选 full run `30694372445` / job `91354558827`：manifest exact 匹配 version/branch/commit/run/attempt/workflow，`validationProfile=full`、`validationReason=candidate_development_push`、`xcodeBuildRequired=true`；Xcode build 成功，xcresult 与 `xcodebuild.log` 已上传，JUnit `10/10`、0 failures，static、Speech、UI、home/paste 合同均通过。结果包保存在 `/private/tmp/aitrans-c-review-30694372445`。
- PR #131 fast run `30694565661`：exact candidate SHA，`validationProfile=fast`，复用候选 full SHA `bdf9d6303bf27296f7ed435b2e5daaf7c212502b` 且 state `success`，Xcode skipped；JUnit `10/10`。结果包保存在 `/private/tmp/aitrans-c-review-30694565661`。
- merge fast run `30694602373`：exact merge SHA `9684b3d736fc647bdb244cb01e5f8f0c48ec5c55`，`validationReason=merge_reuses_successful_candidate_full_validation`，`reusedFullValidationState=success`、`receiptPropagationAllowed=true`，Xcode skipped；JUnit `10/10`。结果包保存在 `/private/tmp/aitrans-c-review-30694602373`。

未跑本机 build / 探针，按规则交给云端验证。候选、PR 和 merge 均使用 `probe_mode=skip`，未生成新的漫画探针指标、`output/` 报告或 `metrics/version_history.csv` 行。真实 Koharu 四件套、Speech corpus 与真实竖排图片 corpus 仍缺失；full artifact 的 active Koharu gate 为 `manifestMissing / stopUntilArtifactsProvided`，本版不声称 OCR、翻译、识别或 Koharu 质量提升。源码合同不能替代真实设备／模拟器 VoiceOver、Dynamic Type 和真实图片 corpus。

## v3.66：图片 OCR 几何边界安全
日期：2026-08-01

状态：Agent X 已完成实现、云端验收和合并收口；工程正式版本为 `MARKETING_VERSION=3.66`。候选分支 `codeb/v3.66-image-ocr-geometry-safety` 的最终候选 HEAD 为 `6ebfaec853b5a02fd5f8db49e7748fadafac61d9`，PR #130 已合入 `smalldata_test`，merge SHA 为 `00839ee4bcfd9b36caf90520fe01b403d70a0028`，远端候选分支已删除，`main` 未触碰。

核心变更：

- `ImageOCRLayoutRect.normalizedToUnit()` 统一拒绝非有限／非正面积几何，并把部分可见矩形按整矩形裁到 `[0,1]`；布局引擎在方向判定和聚类前过滤无效 observation，保证覆盖、局部定位和阅读排序不接收 NaN/∞ 或越界矩形。
- `VisionOCRService` 在 Vision observation 进入布局前使用同一整矩形边界；异常 bounding box 被丢弃，不再只逐字段 clamp 后生成可能超出图片的 block。
- 新增 `scripts/test-v366-image-ocr-geometry-safety-contract.py` 与纯 Swift evaluator；历史 v3.47–v3.65 图片合同和 CI 路由同步接受后续正式版本。该版本不改变 OCR 候选、翻译、renderer/export、漫画探针、Koharu 主路径、ground truth、metrics 或 output。

关键文件：

- `AITRANS/Services/ImageOCRLayoutEngine.swift`
- `AITRANS/Services/VisionOCRService.swift`
- `AITRANS.xcodeproj/project.pbxproj`
- `.github/workflows/ci-results.yml`
- `scripts/test-v366-image-ocr-geometry-safety-contract.py`
- `scripts/test-v366-image-ocr-geometry-safety-evaluator.swift`
- v3.47–v3.65 图片合同与 `README.md`、`AGENTS.md`、flow/test 文档

验证：

- 本地轻量检查：v3.47–v3.66 图片合同套件、v2.7 OCR direction evaluator、v3.64/v3.65 兼容合同、v3.66 geometry evaluator、Swift parse、JSON/YAML smoke、版本解析和 `git diff --check` 通过。
- 候选 full run `30693549176` / job `91352415895`：manifest exact 匹配 version/branch/commit/run/attempt/workflow，`validationProfile=full`、`validationReason=candidate_development_push`、`xcodeBuildRequired=true`；Xcode build 成功（Xcode 26.6），xcresult 与 `xcodebuild.log` 已上传，JUnit `10/10`、0 failures，static、Speech、UI、home/paste 合同均通过。未加密结果包保存在 `/private/tmp/aitrans-c-review-30693549176`。
- PR #130 fast run `30693771312`：exact candidate SHA，`validationProfile=fast`，复用候选 full SHA `6ebfaec853b5a02fd5f8db49e7748fadafac61d9` 且 state `success`，Xcode skipped；JUnit `10/10`。结果包保存在 `/private/tmp/aitrans-c-review-30693771312`。
- merge fast run `30693800748`：exact merge SHA `00839ee4bcfd9b36caf90520fe01b403d70a0028`，`validationReason=merge_reuses_successful_candidate_full_validation`，`reusedFullValidationState=success`、`receiptPropagationAllowed=true`，Xcode skipped；JUnit `10/10`。结果包保存在 `/private/tmp/aitrans-c-review-30693800748`。

未跑本机 build / 探针，按规则交给云端验证。候选、PR 和 merge 均使用 `probe_mode=skip`，未生成新的漫画探针指标、`output/` 报告或 `metrics/version_history.csv` 行。真实 Koharu 四件套、Speech corpus 与真实竖排图片 corpus 仍缺失；full artifact 的 active Koharu gate 为 `manifestMissing / stopUntilArtifactsProvided`，本版不声称 OCR、翻译、识别或 Koharu 质量提升。源码合同不能替代真实设备／模拟器 VoiceOver、Dynamic Type 和真实图片 corpus。

## v3.65：图片 OCR 修正 sheet 置信度显示安全
日期：2026-08-01

状态：Agent X 已完成实现、云端验收和合并收口；工程正式版本为 MARKETING_VERSION=3.65。候选分支 codeb/v3.65-image-confidence-display 的最终候选 HEAD 为 d28fc547e15e8e157b1cfa428bd297c4dd795f00，PR #129 已合入 smalldata_test，merge SHA 为 d1816f46202ad7ce76ffc409dfb4f944b8cc73d1，远端候选分支已删除，main 未触碰。

核心变更：

- ImageOCRCorrectionSheet 的低置信度提示使用 ImageOCRResultSummary.normalizedConfidence 后再进入百分比格式化，和结果行／覆盖层保持同一 NaN/∞ 回退为 0、有限值夹到 0...1 边界。
- 新增 scripts/test-v365-image-confidence-display-contract.py；历史 v3.47–v3.64 图片合同的 CI 路由同步接受 v3.65，避免版本推进触发错误回归。
- 该版本只改善异常 OCR 数据下的 View 显示稳定性，不新增 Store／持久化状态，不改变 OCR 候选、翻译、renderer/export、漫画探针、Koharu 主路径、metrics 或 output。

关键文件：

- AITRANS/Views/ImageTranslationViews.swift
- AITRANS.xcodeproj/project.pbxproj
- .github/workflows/ci-results.yml
- scripts/test-v347...test-v365... 图片 UI 合同

验证：

- 本地轻量检查：v3.47–v3.65 图片合同套件、v3.64 纯 Swift evaluator、Swift parse、版本解析和 git diff --check 通过。
- 首次候选 full run 30692448700 / job 91349466576 的 Xcode build 成功，但 v3.47 历史合同仍锁定 ...|64 路由字符串，UI interaction contract 失败，不作为验收证据；修复后以最终 HEAD 重跑。
- 最终候选 full run 30692664461 / job 91350085549：manifest exact 匹配 version/branch/commit/run/attempt/workflow，validationProfile=full、validationReason=candidate_development_push、xcodeBuildRequired=true；Xcode build 成功，xcresult 已上传，JUnit 10/10、0 failures，static、Speech、UI、home/paste 合同均通过。
- PR #129 fast run 30692910035：exact candidate SHA，validationProfile=fast，复用 full SHA d28fc547e15e8e157b1cfa428bd297c4dd795f00 且 state success，Xcode skipped；JUnit 10/10。merge fast run 30692946391：exact merge SHA，validationReason=merge_reuses_successful_candidate_full_validation，复用候选 full 成功收据，receiptPropagationAllowed=true，Xcode skipped；JUnit 10/10。

未跑本机 build / 探针，按规则交给云端验证。候选、PR 和 merge 均使用 probe_mode=skip，未生成新的漫画探针指标、output/ 报告或 metrics/version_history.csv 行。真实 Koharu 四件套、Speech corpus 与真实竖排图片 corpus 仍缺失；full artifact 的 active Koharu gate 为 manifestMissing / stopUntilArtifactsProvided，本版不声称 OCR、翻译、识别或 Koharu 质量提升。源码合同不能替代真实设备／模拟器 VoiceOver、Dynamic Type 和真实图片 corpus。

## v3.64：图片 OCR 置信度安全边界
日期：2026-08-01

状态：Agent X 已完成实现、云端验收和合并收口；工程正式版本为 `MARKETING_VERSION=3.64`。候选分支 `codeb/v3.64-image-confidence-safety` 的最终候选 HEAD 为 `58ec8912c340a89ff397b9f2be806a342202002c`，PR #128 已合入 `smalldata_test`，merge SHA 为 `122d753de9c3e6cd9ad868b805c4a7b8c012932a`，远端候选分支已删除，`main` 未触碰。

核心变更：

- `ImageOCRResultSummary.normalizedConfidence` 统一将 NaN/∞ 归一化为 0、有限值夹到 `0...1`；平均置信度、低置信复查判定与方向统计不再被非有限输入污染，无效值仍进入可解释的低置信风险。
- `ImageOCRLayoutEngine` 在布局前清理 observation confidence，结果行和完整图片预览覆盖层复用同一产品归一化边界，避免 VoiceOver 百分比的 `Int` 转换崩溃。
- 新增 `scripts/test-v364-image-confidence-safety-contract.py` 与 `scripts/test-v364-image-confidence-safety-evaluator.swift`；历史 v3.52/v3.60/v3.61 合同同步允许共享归一化实现。

关键文件：

- `AITRANS/Models/ImageOCRResultSummary.swift`
- `AITRANS/Services/ImageOCRLayoutEngine.swift`
- `AITRANS/Views/ImageTranslationViews.swift`
- `AITRANS.xcodeproj/project.pbxproj`、`.github/workflows/ci-results.yml`
- v3.47–v3.64 图片 UI/置信度合同与 evaluator

验证：

- 本地轻量检查：全量 Python v* 合同、v3.64 纯 Swift evaluator、JSON/YAML smoke、`xcrun swiftc -parse`、版本解析和 `git diff --check` 通过。
- 早期候选 runs `30691484588`、`30691701474` 的 Xcode build 均成功，但历史 v3.52/v3.61 合同仍锁定旧的内联 clamp/finite 写法，均不作为验收证据；随后修复合同并以最终 HEAD 重跑。
- 最终候选 full run `30691931925` / job `91348073467`：manifest exact 匹配 version/branch/commit/run/attempt/workflow，`validationProfile=full`、`validationReason=candidate_development_push`、`xcodeBuildRequired=true`；Xcode build 成功，xcresult 已上传，JUnit `10/10`、0 failures，static、Speech、UI、home/paste 契约均通过。
- PR #128 fast run `30692134870`：exact candidate SHA，`validationProfile=fast`，复用 full SHA `58ec8912c340a89ff397b9f2be806a342202002c` 且 state `success`，Xcode skipped；JUnit `10/10`。merge fast run `30692173820`：exact merge SHA，`validationReason=merge_reuses_successful_candidate_full_validation`，复用候选 full 成功收据，`receiptPropagationAllowed=true`，Xcode skipped；JUnit `10/10`。

未跑本机 build / 探针，按规则交给云端验证。候选与 merge 均使用 `probe_mode=skip`，未生成新的漫画探针指标、`output/` 报告或 `metrics/version_history.csv` 行。真实 Koharu 四件套、Speech corpus 与真实竖排图片 corpus 仍缺失；full artifact 的 active Koharu gate 为 `manifestMissing / stopUntilArtifactsProvided`，本版不声称 OCR、翻译、识别或 Koharu 质量提升。源码合同不能替代真实设备／模拟器 VoiceOver、Dynamic Type 和真实图片 corpus。

## v3.63：图片识别摘要无障碍上下文
日期：2026-08-01

状态：Agent X 已完成实现、云端验收和合并收口；工程正式版本为 `MARKETING_VERSION=3.63`。候选分支 `codeb/v3.63-image-summary-accessibility-context` 的实现 commit 为 `edac8201fce5d209fb662445b1c62397679deaa4`；PR #127 已合入 `smalldata_test`，merge SHA 为 `f2c30a329f7f47a08d1e50e6f57287bf09af7d40`，远端候选分支已删除，`main` 未触碰。

核心变更：

- 图片“识别结果”摘要现在是单一 VoiceOver header，value 复用既有 `store.imageTranslationSummary`，hint 按无图片、翻译未完成、无待复查块和可复查状态说明下一步；不新增 Store／持久化状态，不重跑 Vision OCR／翻译，不改变 renderer/export、漫画探针、Koharu 主路径或质量基线。
- 新增 `scripts/test-v363-image-summary-accessibility-context-contract.py`，并把历史 v3.47–v3.62 图片 UI 合同路由推进到 v3.63；v3.62 合同同步允许后续正式版本回归。

关键文件：

- `AITRANS/Views/ImageTranslationViews.swift`
- `AITRANS.xcodeproj/project.pbxproj`
- `.github/workflows/ci-results.yml`
- `scripts/test-v363-image-summary-accessibility-context-contract.py` 及历史图片 UI 合同
- `README.md`、`AGENTS.md`、`md/flow/flow.md`、`md/flow/flowchart.md`、`md/test/test.md`

验证：

- 本地轻量检查：全量 Python v* 合同、v3.62/v3.63 图片摘要合同、JSON/YAML smoke、`xcrun swiftc -parse`、版本解析和 `git diff --check` 通过。
- 候选 full run `30690924829` / job `91345382260`：manifest exact 匹配 version/branch/commit/run/attempt/workflow，`validationProfile=full`、`validationReason=candidate_development_push`、`xcodeBuildRequired=true`；Xcode build 成功，xcresult 已上传，JUnit `10/10`、0 failures，静态、Speech、UI、home/paste 契约均通过。
- PR #127 fast run `30691154991`：exact candidate SHA，`validationProfile=fast`，复用 full SHA `edac8201fce5d209fb662445b1c62397679deaa4` 且 state `success`，Xcode skipped；JUnit `10/10`。merge fast run `30691193890`：exact merge SHA，`validationReason=merge_reuses_successful_candidate_full_validation`，复用候选 full 成功收据，`receiptPropagationAllowed=true`，Xcode skipped；JUnit `10/10`。

未跑本机 build / 探针，按规则交给云端验证。候选与 merge 均使用 `probe_mode=skip`，未生成新的漫画探针指标、`output/` 报告或 `metrics/version_history.csv` 行。真实 Koharu 四件套、Speech corpus 与真实竖排图片 corpus 仍缺失；full artifact 的 active Koharu gate 为 `manifestMissing / stopUntilArtifactsProvided`，本版不声称 OCR、翻译、识别或 Koharu 质量提升。源码合同不能替代真实设备／模拟器 VoiceOver、Dynamic Type 和完整图片复查回放。

## v3.62：图片识别摘要方向分布
日期：2026-08-01

状态：Agent X 已完成实现、云端验收和合并收口；工程正式版本为 `MARKETING_VERSION=3.62`。候选分支 `codeb/v3.62-image-summary-direction-breakdown` 的实现 commit 为 `e2c417fc53ddeda972a172fca432d0482a2434e7`；PR #126 已合入 `smalldata_test`，merge SHA 为 `dde6fe1da9c9470d409ed614adb7f2c2a362bc30`，远端候选分支已删除，`main` 未触碰。

核心变更：

- `TranslationSessionStore.imageTranslationSummary` 在既有摘要字段基础上显示横排与竖排 block 数，让用户在图片复查入口快速了解方向分布；不新增 Store／持久化状态，不重跑 Vision OCR／翻译，不改变 renderer/export、漫画探针、Koharu 主路径或质量基线。
- 新增 `scripts/test-v362-image-summary-direction-breakdown-contract.py`，并把 CI changed-files UI 路由推进到 v3.62；历史 v3.47–v3.61 合同保持后续正式版本兼容。

关键文件：

- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS.xcodeproj/project.pbxproj`
- `.github/workflows/ci-results.yml`
- `scripts/test-v362-image-summary-direction-breakdown-contract.py` 及历史图片 UI 合同
- `README.md`、`AGENTS.md`、`md/flow/flow.md`、`md/flow/flowchart.md`、`md/test/test.md`

验证：

- 本地轻量检查：v3.00、v3.61、v3.62 合同，UI interaction contracts（69 个），JSON/YAML smoke、`xcrun swiftc -parse`、版本解析和 `git diff --check` 通过。
- 候选 full run `30690298616` / job `91343695477`：manifest exact 匹配 version/branch/commit/run/attempt/workflow，`validationProfile=full`、`validationReason=candidate_development_push`、`xcodeBuildRequired=true`；Xcode build 成功，xcresult 已上传，JUnit `10/10`、0 failures，静态、Speech、UI、home/paste 契约均通过。
- PR #126 fast run `30690585838`：exact candidate SHA，`validationProfile=fast`，复用 full SHA `e2c417fc53ddeda972a172fca432d0482a2434e7` 且 state `success`，Xcode skipped；JUnit `10/10`。merge fast run `30690628008`：exact merge SHA，`validationReason=merge_reuses_successful_candidate_full_validation`，复用候选 full 成功收据，`receiptPropagationAllowed=true`，Xcode skipped；JUnit `10/10`。

未跑本机 build / 探针，按规则交给云端验证。候选与 merge 均使用 `probe_mode=skip`，未生成新的漫画探针指标、`output/` 报告或 `metrics/version_history.csv` 行。真实 Koharu 四件套、Speech corpus 与真实竖排图片 corpus 仍缺失；full artifact 的 active Koharu gate 为 `manifestMissing / stopUntilArtifactsProvided`，本版不声称 OCR、翻译、识别或 Koharu 质量提升。源码合同不能替代真实设备／模拟器 VoiceOver、Dynamic Type 和完整图片复查回放。

## v3.61：图片复查方向上下文与置信度边界
日期：2026-08-01

状态：Agent X 已完成实现、云端验收和合并收口；工程正式版本为 `MARKETING_VERSION=3.61`。候选分支 `codeb/v3.61-image-direction-review-context` 的实现 commit 为 `ca6031416ea4c69d7a3c523c69d8c23b51e25fff`；PR #125 已合入 `smalldata_test`，merge SHA 为 `5be4efb76de2303cbdd4d240dade930cc5e9fea5`，远端候选分支已删除，`main` 未触碰。

核心变更：

- `ImageTranslationBlockRow` 在已有 Vision OCR 方向证据为横排／竖排时显示方向标签，并把方向与有限、clamp 到 0–100% 的方向置信度加入 View 私有 VoiceOver value；未知方向继续由既有“方向待定／待复查”路径表达。
- `ImageTranslationOverlayBlock` 的 adjacent 与 replace 两种完整图片预览覆盖模式复用同一方向上下文；结果行的 OCR 置信度显示对非有限或越界值安全回退／夹紧到 0–100%。不新增 Store／持久化状态，不改变 Vision OCR、模型翻译、选择、renderer/export、漫画探针、Koharu 主路径或质量基线。
- 新增 `scripts/test-v361-image-direction-review-context-contract.py`，并让历史 v3.47–v3.60 图片 UI 合同接受后续正式 `3.x` 版本，避免版本推进造成回归误报。

关键文件：

- `AITRANS/Views/ImageTranslationViews.swift`
- `AITRANS.xcodeproj/project.pbxproj`
- `.github/workflows/ci-results.yml`
- `scripts/test-v361-image-direction-review-context-contract.py` 及 v3.47–v3.60 历史 UI 合同
- `README.md`、`AGENTS.md`、`md/flow/flow.md`、`md/flow/flowchart.md`、`md/test/test.md`

验证：

- 本地轻量检查：UI interaction 合同 68 个全部通过，v3.00 evaluator、v3.61 合同、ImageOCRResultSummary/ImageTranslationViews Swift parse、CI YAML/JSON smoke、版本解析（`v3.61`）和 `git diff --check` 通过。
- 候选 full run `30689857010` / job `91342531205`：manifest exact 匹配 version/branch/commit/run/attempt/workflow，`validationProfile=full`、`validationReason=candidate_development_push`、`xcodeBuildRequired=true`；Xcode build 成功，xcresult 已上传，JUnit `10/10`、0 failures，静态、Speech、UI、home/paste 契约均通过。
- PR #125 fast run `30690056870`：exact candidate SHA，`validationProfile=fast`，`reusedFullValidationSha=ca6031416ea4c69d7a3c523c69d8c23b51e25fff`、state `success`，Xcode skip；JUnit `10/10`。该 fast 包不是新的编译证据。

边界与遗留：

- 未跑本机 build / 探针，按规则交给云端验证。候选和 PR 均为 `probe_mode=skip`，没有新漫画 `output/` 报告、PNG 或 `metrics/version_history.csv` 指标行；仓库既有 output 仍是历史基线。
- 云端 active Koharu validator 仍为 `manifestMissing / stopUntilArtifactsProvided`，真实四件套、Speech corpus 和真实竖排图片 corpus 均未提供；本版不能作为 OCR、翻译、识别或 Koharu 质量提升证据。
- 真实设备／模拟器仍需人工回放横排／竖排／未知方向、异常置信度、长 OCR、VoiceOver 连续定位和 Dynamic Type；源码合同与云端 build 不能替代该回放。

## v3.60：完整图片预览覆盖块的复查上下文
日期：2026-08-01

状态：Agent X 已完成实现、云端验收和合并收口；工程正式版本为 `MARKETING_VERSION=3.60`。候选分支 `codeb/v3.60-image-overlay-review-context` 的核心实现 commit 为 `dfe72bed23dee1998eeeaef062f9a80bb6ce7824`，历史合同兼容修复 commit 为 `17f6dec888f6daf56e42b474f66e8eb0b2aa48f7`；PR #124 已合入 `smalldata_test`，merge SHA 为 `7b729d05ab8eb3bf1dbff0569e112ca9ba833ff2`，远端候选分支已删除，`main` 未触碰。

核心变更：

- 完整图片预览的 adjacent 与 replace 覆盖块现在向 VoiceOver value 提供与复查结果行一致的上下文：OCR 置信度（clamp 到 0–100%）、人工修正、低置信／方向待定、待复查／本次已复查和等待翻译／译文。
- 复查完成集合与人工修正集合只由父 View 读取既有状态并传入覆盖 View；覆盖仍只执行定位选择，稳定 label、定位 hint、选中状态和现有视觉／渲染行为保持不变。该改动不新增 Store／持久化状态，不改变选择、Vision OCR、模型翻译、renderer/export、漫画探针、Koharu 主路径或质量基线。
- 首次 full run `30689000319` 只因历史 v3.45 合同仍锁定旧 overlay value 而失败；随后扩展该回归合同并以 `17f6dec8` 重跑，未放宽产品行为边界。

关键文件：

- `AITRANS/Views/ImageTranslationViews.swift`
- `scripts/test-v345-image-overlay-accessibility-contract.py`
- `scripts/test-v359-image-overlay-block-context-accessibility-contract.py`
- `scripts/test-v360-image-overlay-review-context-accessibility-contract.py`
- `.github/workflows/ci-results.yml`
- `AITRANS.xcodeproj/project.pbxproj`
- `README.md`、`AGENTS.md`、`md/flow/flow.md`、`md/flow/flowchart.md`、`md/test/test.md`

验证：

- 本地轻量检查：v3.15 + v3.47–v3.60 图片/UI 合同通过，ImageTranslationViews Swift parse、CI YAML/JSON smoke、版本解析（`v3.60`）和 `git diff --check` 通过。
- 候选最终 full run `30689206966` / job `91340813801`：manifest exact 匹配 version/branch/commit/run/attempt/workflow，`validationProfile=full`、`validationReason=candidate_development_push`、`xcodeBuildRequired=true`；Xcode build 成功，`.xcresult` 为 `succeeded`、0 errors、0 warnings，JUnit `10/10`，静态、Speech、UI、home/paste 契约均通过；active Koharu validator 为 `manifestMissing / stopUntilArtifactsProvided`。
- PR #124 fast run `30689436322`：exact candidate SHA，`validationProfile=fast`，`reusedFullValidationSha=17f6dec888f6daf56e42b474f66e8eb0b2aa48f7`、state `success`，Xcode skip；JUnit `10/10`。该 fast 包不是新的编译证据。
- merge fast run `30689464537`：merge SHA exact，`validationReason=merge_reuses_successful_candidate_full_validation`，复用候选 full SHA，父 SHA `4b662377179a58ad6ead1749462ee70f4c94ebad` 的 receipt 为 success，`receiptPropagationAllowed=true`，Xcode skip；JUnit `10/10`。

边界与遗留：

- 未跑本机 build / 探针，按规则交给云端验证。候选、PR 与 merge 均为 `probe_mode=skip`，没有新漫画 `output/` 报告、PNG 或 `metrics/version_history.csv` 指标行；仓库既有 output 仍是历史基线。
- 云端 active Koharu validator 仍为 `manifestMissing / stopUntilArtifactsProvided`，真实四件套、Speech corpus 和真实竖排图片 corpus 均未提供；本版不能作为 OCR、翻译、识别或 Koharu 质量提升证据。
- 真实设备／模拟器仍需人工回放相邻与替换覆盖模式、低置信／方向待定、人工修正、待复查／已复查、等待翻译、长 OCR、空 OCR 和 VoiceOver 连续定位；源码合同和云端 build 不能替代该回放。


## v3.59：完整图片预览覆盖块的语音身份对齐
日期：2026-08-01

状态：Agent X 已完成实现、云端验收和合并收口；工程正式版本为 `MARKETING_VERSION=3.59`。候选分支 `codeb/v3.59-image-overlay-block-context` 的实现 commit 为 `40e6ee5afa4cee447ea8d00ee690edab5eea8439`，修复合同回归的 commit 为 `ecfe01a10f6666527d9c20cd49c97734bb5b37ac`；PR #123 已合入 `smalldata_test`，merge SHA 为 `de2ffbbbb295c3abd120f8d9da634bca12d122c4`，远端候选分支已删除，`main` 未触碰。

核心变更：

- `ImageTranslationOverlayBlock` 的 adjacent 与 replace 两种覆盖模式统一使用稳定 VoiceOver label“图片文字块 + OCR 原文”，空 OCR 回退为“空”。
- 既有等待翻译／译文 value、定位 hint、选中状态和覆盖点击行为保持不变；该改动只改善 View 语义，不新增 Store／持久化状态，不改变选择、Vision OCR、模型翻译、renderer/export、漫画探针、Koharu 主路径或质量基线。
- 首次 full run `30688128010` 只因历史 v3.15 合同仍锁定旧 label 而失败；随后更新回归合同并以 `ecfe01a1` 重跑，未放宽产品行为边界。

关键文件：

- `AITRANS/Views/ImageTranslationViews.swift`
- `scripts/test-v315-image-preview-direct-selection-contract.py`
- `scripts/test-v359-image-overlay-block-context-accessibility-contract.py`
- `.github/workflows/ci-results.yml`
- `AITRANS.xcodeproj/project.pbxproj`
- `README.md`、`AGENTS.md`、`md/flow/flow.md`、`md/flow/flowchart.md`、`md/test/test.md`

验证：

- 本地轻量检查：v3.47–v3.59 图片/UI 合同与 v3.15 回归合同通过，ImageTranslationViews Swift parse、CI YAML/JSON smoke、版本解析（`v3.59`）和 `git diff --check` 通过。
- 候选 full run `30688366529` / job `91338491005`：manifest exact 匹配 version/branch/commit/run/attempt/workflow，`validationProfile=full`、`validationReason=candidate_development_push`、`xcodeBuildRequired=true`；Xcode build 成功，`.xcresult` 为 `succeeded`、0 errors、0 warnings，JUnit `10/10`，静态、Speech、UI、home/paste 契约均通过；active Koharu validator 为 `manifestMissing / stopUntilArtifactsProvided`。
- PR #123 fast run `30688596306`：exact candidate SHA，`validationProfile=fast`，`reusedFullValidationSha=ecfe01a10f6666527d9c20cd49c97734bb5b37ac`、state `success`，Xcode skip；JUnit `10/10`。该 fast 包不是新的编译证据。
- merge fast run `30688623155`：merge SHA exact，`validationReason=merge_reuses_successful_candidate_full_validation`，复用候选 full SHA，父 SHA `5e30830eb39771fbfb6fa10dc408b5df6672af71` 的 receipt 为 success，`receiptPropagationAllowed=true`，Xcode skip；JUnit `10/10`。
- 文档提交 `39e9e0de8bedf18a271cdd15173d89c9d10efd68` 的 metadata follow-up run `30688815074`：exact docs SHA，`validationProfile=fast`，`validationReason=smalldata_metadata_followup_reuses_parent_full_validation`，复用 merge full `de2ffbbbb295c3abd120f8d9da634bca12d122c4`，`smalldataIncrementalMetadataOnly=true`、`smalldataMetadataRequiresFullValidation=false`、`receiptPropagationAllowed=true`，Xcode skip；JUnit `10/10`。该包是文档收据，不是新的编译证据。

边界与遗留：

- 未跑本机 build / 探针，按规则交给云端验证。候选、PR 与 merge 均为 `probe_mode=skip`，没有新漫画 `output/` 报告、PNG 或 `metrics/version_history.csv` 指标行；仓库既有 output 仍是历史基线。
- 云端 active Koharu validator 仍为 `manifestMissing / stopUntilArtifactsProvided`，真实四件套、Speech corpus 和真实竖排图片 corpus 均未提供；本版不能作为 OCR、翻译、识别或 Koharu 质量提升证据。
- 真实设备／模拟器仍需人工回放相邻与替换覆盖模式、长 OCR、空 OCR、等待翻译、定位／选中和 VoiceOver 连续操作；源码合同和云端 build 不能替代该回放。

## v3.58：图片复查结果行的语音身份与译文上下文
日期：2026-08-01

状态：Agent X 已完成实现、云端验收和合并收口；工程正式版本为 `MARKETING_VERSION=3.58`。候选分支 `codeb/v3.58-image-review-row-context` 的核心 commit 为 `0236a17e197a36b53251ca17fd0b82eee65aae91`；PR #122 已合入 `smalldata_test`，merge SHA 为 `f6a78daebcabf2c5c6fecd3f8c64dd652edc3422`，远端候选分支待本轮 prune 后确认删除，`main` 未触碰。

核心变更：

- `ImageTranslationBlockRow` 的主定位 Button 现在有稳定 VoiceOver label：明确这是“图片文字块”，并读出 OCR 原文；空 OCR 使用“空”回退。
- VoiceOver value 在翻译未完成时读出“等待翻译”，有译文时读出实际译文，同时保留定位、OCR 置信度、低置信／方向待定和复查状态；该改动只改善 View 语义，不新增 Store／持久化状态，不重新运行 OCR 或翻译。

关键文件：

- `AITRANS/Views/ImageTranslationViews.swift`
- `scripts/test-v358-image-review-row-context-accessibility-contract.py`
- `AITRANS.xcodeproj/project.pbxproj`
- `.github/workflows/ci-results.yml`
- `scripts/test-v347-image-command-accessibility-contract.py` 至 `scripts/test-v358-image-review-row-context-accessibility-contract.py`

验证：

- 本地轻量检查：v3.47–v3.58 图片/UI 合同 46 项通过、ImageTranslationViews Swift parse、CI YAML 解析、版本解析（`v3.58`）和 `git diff --check` 均通过。
- 候选 full run `30687639688` / job `91336515173`：manifest exact 匹配 version/branch/commit/run/attempt/workflow，`validationProfile=full`、`validationReason=candidate_development_push`、`xcodeBuildRequired=true`；Xcode build 成功，`.xcresult` 为 `succeeded`、0 errors、0 warnings，JUnit `10/10`，静态、Speech、UI、home/paste 和扩展 Koharu validator 通过；active Koharu validator 为 `manifestMissing / stopUntilArtifactsProvided`。
- PR #122 fast run `30687867104`：exact candidate SHA，`validationProfile=fast`，`reusedFullValidationSha=0236a17e...`、state `success`，Xcode skip reason 为复用候选 full；JUnit `10/10`。该 fast 包不是新的编译证据。
- merge fast run `30687892830`：merge SHA exact，`validationReason=merge_reuses_successful_candidate_full_validation`，复用候选 full SHA，父 SHA `bead19326b1d205c2179904598febe6905b3b8f0` 的 receipt 为 success，`receiptPropagationAllowed=true`，Xcode skip reason 为复用候选 full；JUnit `10/10`。

边界与遗留：

- 未跑本机 build / 探针，按规则交给云端验证。候选、PR 与 merge 均为 `probe_mode=skip`，没有新漫画 `output/` 报告、PNG 或 `metrics/version_history.csv` 指标行；仓库既有 output 仍是历史基线。
- 云端 active Koharu validator 仍为 `manifestMissing / stopUntilArtifactsProvided`，真实四件套、Speech corpus 和真实竖排图片 corpus 均未提供；本版不能作为 OCR、翻译、识别或 Koharu 质量提升证据。
- 真实设备／模拟器仍需人工回放长 OCR 原文、空 OCR、长译文、等待翻译和定位／复查按钮；源码合同和云端 build 不能替代该回放。

## v3.57：漫画探针逐块诊断操作反馈
日期：2026-08-01

状态：Agent X 已完成实现、云端验收和合并收口；工程正式版本为 `MARKETING_VERSION=3.57`。候选分支 `codeb/v3.57-manga-probe-block-a11y` 的核心 commit 为 `f8806570eb255fba67f27e5c8ffd7d4bf58ce7ba`；PR #121 已合入 `smalldata_test`，merge SHA 为 `3c4b4083440fe16bb743b38879b6d68922dc61e9`，远端候选分支已删除，`main` 未触碰。

核心变更：

- `MangaProbeBlockRow` 的每个逐块结果现在提供稳定 VoiceOver label/value/hint：按 block index 读出 PASS/FAIL、OCR 原文、旋转角度、OCR 置信度、质量标签、译文和失败／翻译失败详情。
- 展开提示明确结果只属于漫画探针诊断，不会改变普通图片 OCR、翻译或覆盖图；该 View 私有语义不读取 ground truth 作为候选、不运行第二次探针、不写 Store，不改变漫画探针诊断、renderer/export、Koharu 主路径、metrics 或 output。

关键文件：

- `AITRANS/Views/DeveloperConsoleView.swift`
- `scripts/test-v357-manga-probe-block-accessibility-contract.py`
- `AITRANS.xcodeproj/project.pbxproj`
- `.github/workflows/ci-results.yml`
- `scripts/test-v347-image-command-accessibility-contract.py` 至 `scripts/test-v357-manga-probe-block-accessibility-contract.py`

验证：

- 本地轻量检查：v3.47–v3.57 图片/UI 合同 42 项通过、DeveloperConsoleView Swift parse、CI YAML 解析、版本解析（`v3.57`）和 `git diff --check` 均通过。
- 候选 full run `30687130624` / job `91335075646`：manifest exact 匹配 version/branch/commit/run/attempt/workflow，`validationProfile=full`、`validationReason=candidate_development_push`、`xcodeBuildRequired=true`；Xcode build 成功，`.xcresult` 为 `succeeded`、0 errors、0 warnings，JUnit `10/10`，静态、Speech、UI、home/paste 和扩展 Koharu validator 通过；active Koharu validator 为 `manifestMissing / stopUntilArtifactsProvided`。
- PR #121 fast run `30687313392`：exact candidate SHA，`validationProfile=fast`，`reusedFullValidationSha=f8806570...`、state `success`，Xcode skip reason 为复用候选 full；JUnit `10/10`。该 fast 包不是新的编译证据。
- merge fast run `30687341479`：merge SHA exact，`validationReason=merge_reuses_successful_candidate_full_validation`，复用候选 full SHA，父 SHA `1c4d7b5722152eb153a958b834d9fcaf28c3e95d` 的 receipt 为 success，`receiptPropagationAllowed=true`，Xcode skip reason 为复用候选 full；JUnit `10/10`。

边界与遗留：

- 未跑本机 build / 探针，按规则交给云端验证。候选、PR 与 merge 均为 `probe_mode=skip`，没有新漫画 `output/` 报告、PNG 或 `metrics/version_history.csv` 指标行；仓库既有 output 仍是历史基线。
- 云端 active Koharu validator 仍为 `manifestMissing / stopUntilArtifactsProvided`，真实四件套、Speech corpus 和真实竖排图片 corpus 均未提供；本版不能作为 OCR、翻译、识别或 Koharu 质量提升证据。
- 真实设备／模拟器仍需人工回放长 OCR 原文、置信度边界、失败详情和 DisclosureGroup 展开状态；源码合同和云端 build 不能替代该回放。


## v3.56：漫画探针状态的开发者操作反馈
日期：2026-08-01

状态：Agent X 已完成实现、云端验收和合并收口；工程正式版本为 `MARKETING_VERSION=3.56`。候选分支 `codeb/v3.56-manga-probe-status-a11y` 的核心 commit 为 `2198686a523da9d5fdc4e39f63967fb970947a3f`；PR #120 已合入 `smalldata_test`，merge SHA 为 `dc48b59457cfd00773af61b373d438e6e6a9d2aa`，远端候选分支已删除，`main` 未触碰。

核心变更：

- `MangaProbeSection` 的既有探针状态行现在是稳定的 VoiceOver 上下文：固定 label 为“漫画覆盖翻译探针状态”，value 组合阶段标题与实时探针详情，hint 按等待、载入、Vision OCR、翻译、绘制、完成和失败分流。
- 运行漫画覆盖翻译探针按钮明确说明会读取 bundle `test/1.png`、生成 Output 诊断文件，并且不会改变普通图片 OCR、翻译或覆盖图。该版本只消费既有 `TranslationSessionStore` 探针状态，不新增 Store／持久化状态、不调用第二次探针，不改变漫画探针失败 block 保留、renderer/export、Koharu 主路径、ground truth、metrics 或 output。

关键文件：

- `AITRANS/Views/DeveloperConsoleView.swift`
- `scripts/test-v356-manga-probe-status-accessibility-contract.py`
- `AITRANS.xcodeproj/project.pbxproj`
- `.github/workflows/ci-results.yml`
- `scripts/test-v347-image-command-accessibility-contract.py` 至 `scripts/test-v356-manga-probe-status-accessibility-contract.py`

验证：

- 本地轻量检查：v3.47–v3.56 图片/UI 合同 38 项通过、DeveloperConsoleView Swift parse、CI YAML 解析、版本解析（`v3.56`）和 `git diff --check` 均通过。
- 候选 full run `30686574508` / job `91333484523`：manifest exact 匹配 version/branch/commit/run/attempt/workflow，`validationProfile=full`、`validationReason=candidate_development_push`、`xcodeBuildRequired=true`；Xcode build 成功，`.xcresult` 为 `succeeded`、0 errors、0 warnings，JUnit `10/10`，静态、Speech、UI、home/paste 和扩展 Koharu validator 通过；active Koharu validator 为 `manifestMissing / stopUntilArtifactsProvided`。
- PR #120 fast run `30686820522`：exact candidate SHA，`validationProfile=fast`，`reusedFullValidationSha=2198686a...`、state `success`，Xcode skip reason 为复用候选 full；JUnit `10/10`。该 fast 包不是新的编译证据。
- merge fast run `30686846333`：merge SHA exact，`validationReason=merge_reuses_successful_candidate_full_validation`，复用候选 full SHA，父 SHA `8aab00750c75bf599abcda170b352f033cd3e5af` 的 receipt 为 success，`receiptPropagationAllowed=true`，Xcode skip reason 为复用候选 full；JUnit `10/10`。

边界与遗留：

- 未跑本机 build / 探针，按规则交给云端验证。候选、PR 与 merge 均为 `probe_mode=skip`，没有新漫画 `output/` 报告、PNG 或 `metrics/version_history.csv` 指标行；仓库既有 output 仍是历史基线。
- 云端 active Koharu validator 仍为 `manifestMissing / stopUntilArtifactsProvided`，真实四件套、Speech corpus 和真实竖排图片 corpus 均未提供；本版不能作为 OCR、翻译、识别或 Koharu 质量提升证据。
- 真实设备／模拟器仍需人工回放漫画探针状态的 label/value/hint、运行按钮边界和失败重试状态变化；源码合同和云端 build 不能替代该回放。


## v3.55：Koharu readiness 开发者操作反馈
日期：2026-08-01

状态：Agent X 已完成实现、云端验收和合并收口；工程正式版本为 `MARKETING_VERSION=3.55`。候选分支 `codeb/v3.55-koharu-readiness-a11y` 的核心 commit 为 `f29e7a1d830b93ededec51fddb45bf22695f0795`；PR #119 已合入 `smalldata_test`，merge SHA 为 `e24a7a4223b1f16113cecf5e8189788107c7befa`，远端候选分支已删除，`main` 未触碰。

核心变更：

- `MangaKoharuArtifactReadinessSummary` 的既有状态行现在提供稳定 VoiceOver label/value/hint：读出 readiness verdict、缺失四件套、下一步和 shadow-only 诊断边界。
- `stopUntilArtifactsProvided` 明确提示真实工件目录 `test/koharu_artifacts/` 以及 `1.manifest.json`、`1.textboxes.json`、`1.bubbles.json`、`1.segment_mask.json`；可复制的 readiness summary 也记录 `artifactRoot`。该版本只消费既有 report，不调用第二次探针、不写 Store、不改变 active artifact gate、普通图片 OCR、翻译、renderer/export、Koharu 主路径、ground truth、metrics 或 output。

关键文件：

- `AITRANS/Views/DeveloperConsoleView.swift`
- `scripts/test-v355-koharu-readiness-accessibility-contract.py`
- `AITRANS.xcodeproj/project.pbxproj`
- `.github/workflows/ci-results.yml`
- `scripts/test-v347-image-command-accessibility-contract.py` 至 `scripts/test-v355-koharu-readiness-accessibility-contract.py`

验证：

- 本地轻量检查：v3.47–v3.55 图片/UI 合同 35 项通过、DeveloperConsoleView Swift parse、CI YAML 解析、版本解析（`v3.55`）和 `git diff --check` 均通过。
- 候选 full run `30686038492` / job `91331890483`：manifest exact 匹配 version/branch/commit/run/attempt/workflow，`validationProfile=full`、`validationReason=candidate_development_push`、`xcodeBuildRequired=true`；Xcode build 成功，`.xcresult` 为 `succeeded`、0 errors、0 warnings，JUnit `10/10`，UI interaction、Speech、home/paste 与静态检查通过；active Koharu validator 为 `manifestMissing`。
- PR #119 fast run `30686296231`：exact candidate SHA，`validationProfile=fast`，`reusedFullValidationSha=f29e7a1d...`、state `success`，Xcode skip reason 为复用候选 full；JUnit `10/10`。该 fast 包不是新的编译证据。
- merge fast run `30686324425`：merge SHA exact，`validationReason=merge_reuses_successful_candidate_full_validation`，复用候选 full SHA，父 SHA `5c38648899ea30ad19f4f34a7270cc98ee302fd3` 的 receipt 为 success，`receiptPropagationAllowed=true`，Xcode skip reason 为复用候选 full；JUnit `10/10`。

边界与遗留：

- 未跑本机 build / 探针，按规则交给云端验证。候选、PR 与 merge 均为 `probe_mode=skip`，没有新漫画 `output/` 报告、PNG 或 `metrics/version_history.csv` 指标行；仓库既有 output 仍是历史基线。
- 云端 active Koharu validator 仍为 `manifestMissing / stopUntilArtifactsProvided`，真实四件套、Speech corpus 和真实竖排图片 corpus 均未提供；本版不能作为 OCR、翻译、识别或 Koharu 质量提升证据。
- 真实设备／模拟器仍需人工回放开发控制台 readiness 的 label/value/hint，以及提供真实工件后的 ready/invalid/blocked 状态变化；源码合同和云端 build 不能替代该回放。


## v3.54：修复图片状态 VoiceOver value 的动态播报回归
日期：2026-08-01

状态：Agent X 已完成实现、云端验收和合并收口；工程正式版本为 `MARKETING_VERSION=3.54`。候选分支 `codeb/v3.54-image-status-value-fix` 的核心 commit 为 `fa2920bedf4aa9ba9661f48471d929b880480466`；PR #118 已合入 `smalldata_test`，merge SHA 为 `cfd6214c1325a46f4e544cebf5d514b8f467b2e6`，远端候选分支已删除，`main` 未触碰。

核心变更：

- 修复 `ImageTranslationPanel.imageStatusAccessibilityValue` 的实际实现回归：源码此前返回字面量 `(statusTitle)：(statusDetail)`，现在使用 \(statusTitle)：\(statusDetail) 的 Swift 字符串插值，VoiceOver 会随状态实际读出阶段、逐块进度、失败、导出重绘和完成详情。
- 新增 `scripts/test-v354-image-status-value-contract.py`，并强化 v3.51 合同以拒绝字面量实现；v3.47–v3.53 合同的后续版本路由同步允许 v3.54。该版本不新增 Store／持久化状态，不改变 OCR、翻译、renderer/export、漫画探针、Koharu、ground truth、metrics 或 output。

关键文件：

- `AITRANS/Views/ImageTranslationViews.swift`
- `AITRANS.xcodeproj/project.pbxproj`
- `.github/workflows/ci-results.yml`
- `scripts/test-v347-image-command-accessibility-contract.py` 至 `scripts/test-v354-image-status-value-contract.py`
- `README.md`、`AGENTS.md`、`md/flow/flow.md`、`md/flow/flowchart.md`、`md/test/test.md`

验证：

- 本地轻量检查：v3.47–v3.54 图片/UI 合同全部通过（31 项）、Swift parse、CI YAML 解析、`python3 scripts/resolve-project-version.py`（`v3.54`）和 `git diff --check` 均通过。
- 候选 full run `30685471079` / job `91330239345`：manifest exact 匹配 version/branch/commit/run/attempt/workflow，`validationProfile=full`、`validationReason=candidate_development_push`、`xcodeBuildRequired=true`；Xcode build 成功，`.xcresult` 为 `succeeded`、0 errors、0 warnings，JUnit `10/10`，UI interaction、Speech、home/paste 与静态检查通过；`AITRANS CI/full-validation=success`。
- PR #118 fast run `30685682394`：exact candidate SHA，`validationProfile=fast`，`reusedFullValidationSha=fa2920be...`、state `success`，Xcode skip reason 为复用候选 full；JUnit `10/10`。该 fast 包不是新的编译证据。
- merge fast run `30685708141`：merge SHA exact，`validationReason=merge_reuses_successful_candidate_full_validation`，复用候选 full SHA，父 SHA `f77778d7435b752a85097bbe88326ac34c4f56df` 的 receipt 为 success，`receiptPropagationAllowed=true`，Xcode skip reason 为复用候选 full；JUnit `10/10`。

边界与遗留：

- 未跑本机 build / 探针，按规则交给云端验证。候选、PR 与 merge 均为 `probe_mode=skip`，没有新漫画 `output/` 报告、PNG 或 `metrics/version_history.csv` 指标行；仓库既有 output 仍是历史基线。
- 云端 active Koharu validator 仍为 `manifestMissing / stopUntilArtifactsProvided`，四件套、Speech corpus 和真实竖排图片 corpus 均未提供；本版不能作为 OCR、翻译、识别或 Koharu 质量提升证据。
- 真实设备／模拟器仍需人工回放图片状态在各生命周期变化时的 VoiceOver 动态朗读；源码合同和云端 build 不能替代该回放。


## v3.53：已忽略 OCR 文字块恢复行的 VoiceOver 上下文
日期：2026-08-01

状态：Agent X 已完成实现、云端验收和合并收口；工程正式版本为 `MARKETING_VERSION=3.53`。候选分支 `codeb/v3.53-image-ignored-row-a11y` 的核心 commit 为 `65050427993988adb57e6e8cae6d83466a51d71f`；PR #117 已合入 `smalldata_test`，merge SHA 为 `e376feb94208f233f791494db56f61df2492abc4`，远端候选分支已删除，`main` 未触碰。

核心变更：

- 已忽略 OCR 文字块恢复行现在是一个包含子元素的 VoiceOver 上下文元素，label 明确包含“已忽略 OCR 文字块”和原文，value 说明该 block 不在当前图片预览、导出和转录中、是否保留已有译文以及恢复是否可用。
- 恢复按钮仍是独立的 44pt 操作，继续保留 `canRestore` disabled 边界、`modificationUnavailableHint` 禁用原因和 `image-ignored-row-<UUID>` focus ID；忽略／恢复业务状态、Store、OCR、翻译、renderer/export、探针和持久化均未改变。

关键文件：

- `AITRANS/Views/ImageTranslationViews.swift`
- `scripts/test-v353-image-ignored-row-accessibility-contract.py`
- `.github/workflows/ci-results.yml`
- `AITRANS.xcodeproj/project.pbxproj`
- `scripts/test-v347-image-command-accessibility-contract.py`、`scripts/test-v348-image-preview-context-accessibility-contract.py`、`scripts/test-v349-image-language-accessibility-contract.py`、`scripts/test-v350-image-selection-supersession-accessibility-contract.py`、`scripts/test-v351-image-status-accessibility-contract.py`、`scripts/test-v352-image-review-row-accessibility-contract.py`
- `README.md`、`AGENTS.md`、`md/flow/flow.md`、`md/flow/flowchart.md`、`md/test/test.md`

验证：

- 本地轻量检查：v3.29 `8/8`、v3.42 `4/4`、v3.47 `4/4`、v3.48 `4/4`、v3.49 `4/4`、v3.50 `4/4`、v3.51 `4/4`、v3.52 `4/4`、v3.53 `4/4`；`v1.87`、`v2.02`、`v2.03`、`v2.04`、`v2.07`、`v2.09` 回归仍通过；JSON smoke、`git diff --check`、`swiftc -parse` 和版本解析均通过。
- 候选 full run `30685009093` / job `91328929775`：manifest exact 匹配 version/branch/commit/run/attempt/workflow，`validationProfile=full`、`validationReason=candidate_development_push`、`xcodeBuildRequired=true`；Xcode build 成功，`.xcresult` 为 `succeeded`、0 errors、0 warnings，JUnit `10/10`，UI interaction、Speech、home/paste 与静态检查通过；`AITRANS CI/full-validation=success`。
- PR fast run `30685192767`：exact candidate SHA，`validationProfile=fast`，`reusedFullValidationSha=65050427...`、state `success`，Xcode skip reason 为复用候选 full；JUnit `10/10`。该 fast 包不是新的编译证据。
- merge fast run `30685222969`：merge SHA exact，`validationReason=merge_reuses_successful_candidate_full_validation`，父 SHA `fabf19e9af6f473f09f320c29ff14a4e2326e0d4` 的 receipt 为 success，`receiptPropagationAllowed=true`，复用候选 full SHA，JUnit `10/10`。

边界与遗留：

- 未跑本机 build / 探针，按规则交给云端验证。候选与 merge 均为 `probe_mode=skip`，没有新漫画 `output/` 报告、PNG 或 `metrics/version_history.csv` 指标行；仓库既有 output 仍是历史基线。
- 云端 active Koharu validator 仍为 `manifestMissing / stopUntilArtifactsProvided`，四件套、Speech corpus 和真实竖排图片 corpus 均未提供；本版不能作为 OCR、翻译、识别或 Koharu 质量提升证据。
- 真实设备／模拟器仍需人工回放已忽略行的 VoiceOver label/value、Dynamic Type、恢复按钮禁用边界和恢复后的焦点交接；源码合同和云端 build 不能替代该回放。

## v3.52：图片 OCR 结果行的 VoiceOver 状态摘要
日期：2026-08-01

状态：Agent X 已完成实现、云端验收和合并收口；工程正式版本为 `MARKETING_VERSION=3.52`。候选分支 `codeb/v3.52-image-review-row-a11y` 的核心 commit 为 `35826cdb23b001eb18cbc5699cfb53e98f4b4453`；PR #116 已合入 `smalldata_test`，merge SHA 为 `28b38d184954ca1a6dbda1a4a78d7e0e30cc43e2`，远端候选分支已删除，`main` 未触碰。

核心变更：

- `ImageTranslationBlockRow` 的主定位 Button 继续保留原有选中／未选中 hint，但 VoiceOver value 现在同时汇总定位状态、OCR 置信度、低置信、方向待定、人工修正、待复查／本次已复查和等待翻译。置信度先 clamp 到 0–100% 并四舍五入，避免异常输入导致无意义的朗读值。
- 该版本只改善 View 私有可访问语义；没有新增 Store、持久化、图片 task、Vision OCR、模型翻译、renderer/export、漫画探针、Koharu、ground truth、metrics 或 `output` 状态。历史 v3.12/v3.43 定位合同同步改为验证动态值，同时保留定位文案和 hint 边界。

关键文件：

- `AITRANS/Views/ImageTranslationViews.swift`
- `scripts/test-v352-image-review-row-accessibility-contract.py`
- `.github/workflows/ci-results.yml`
- `AITRANS.xcodeproj/project.pbxproj`
- `scripts/test-v312-image-block-selection-contract.py`
- `scripts/test-v343-image-navigation-accessibility-contract.py`
- `scripts/test-v347-image-command-accessibility-contract.py`
- `scripts/test-v348-image-preview-context-accessibility-contract.py`
- `scripts/test-v349-image-language-accessibility-contract.py`
- `scripts/test-v350-image-selection-supersession-accessibility-contract.py`
- `scripts/test-v351-image-status-accessibility-contract.py`
- `README.md`、`AGENTS.md`、`md/flow/flow.md`、`md/flow/flowchart.md`、`md/test/test.md`

验证：

- 本地轻量检查：v3.12 `5/5`、v3.43 `4/4`、v3.47 `4/4`、v3.48 `4/4`、v3.49 `4/4`、v3.50 `4/4`、v3.51 `4/4`、v3.52 `4/4`；v1.87 `12/12`、v2.02 `10/10`、v2.03 `4/4`、v2.04 `9/9`、v2.07 `9/9`、v2.09 `6/6`；JSON smoke、`git diff --check`、`swiftc -parse` 和版本解析均通过。
- 候选 full run `30684477700` / job `91327539807`：manifest exact 匹配 version/branch/commit/run/attempt/workflow，`validationProfile=full`、`validationReason=candidate_development_push`、`xcodeBuildRequired=true`；Xcode build 成功，`.xcresult` 为 `succeeded`、0 errors、0 warnings，JUnit `10/10`，UI interaction、Speech、home/paste 与静态检查通过；`AITRANS CI/full-validation=success`。
- PR fast run `30684670025`：exact candidate SHA，`validationProfile=fast`，`reusedFullValidationSha=35826cdb...`、state `success`，Xcode skip reason 为复用候选 full；JUnit `10/10`。该 fast 包不是新的编译证据。
- merge fast run `30684700643`：merge SHA exact，`validationReason=merge_reuses_successful_candidate_full_validation`，父 SHA `1db30ed201d31b418e383aaed343903875a96958` 的 receipt 为 success，`receiptPropagationAllowed=true`，复用候选 full SHA，JUnit `10/10`。

边界与遗留：

- 未跑本机 build / 探针，按规则交给云端验证。候选与 merge 均为 `probe_mode=skip`，没有新漫画 `output/` 报告、PNG 或 `metrics/version_history.csv` 指标行；仓库既有 output 仍是历史基线。
- 云端 active Koharu validator 仍为 `manifestMissing / stopUntilArtifactsProvided`，四件套、Speech corpus 和真实竖排图片 corpus 均未提供；本版不能作为 OCR、翻译、识别或 Koharu 质量提升证据。
- 真实设备／模拟器仍需人工回放 VoiceOver 结果行动态朗读、Dynamic Type、异常置信度边界与连续定位／复查操作；源码合同和云端 build 不能替代该回放。

## v3.51：图片处理状态的统一 VoiceOver 上下文
日期：2026-08-01

状态：Agent X 已完成实现、云端验收和合并收口；工程正式版本为 `MARKETING_VERSION=3.51`。PR #115 已合入 `smalldata_test`，merge SHA `b6e8c88e74ff3fa9c8d78618d3f2f624480d4b43`；远端 `codeb/v3.51-image-status-a11y` 已删除，未触碰 `main`。

核心变更：

- 审查图片页状态反馈时发现，状态标题和详情虽然会随图片读取、Vision OCR、逐块翻译、导出重绘和分享准备变化，但 VoiceOver 只能把它们当作普通组合文本读取，缺少稳定的“这是图片翻译状态”身份，也没有告诉用户当前阶段可执行的下一步。
- v3.51 将 `ImageTranslationPanel` 的状态行收敛为单一 VoiceOver 元素：label 固定为“图片翻译状态”，value 组合既有 `statusTitle` 与 `statusDetail`，hint 按载入、Vision OCR、逐块翻译、导出重绘、分享准备、失败、取消／待重试和完成分流。逐块翻译提示保留“仍可查看和定位”，完成提示说明修正文字、更新复查、切换覆盖方式和导出，失败与导出失败提示说明重试边界。
- 该版本只改善 View 的可理解性，不新增 Store／持久化状态，不改变图片 task、Vision OCR、模型翻译、renderer/export、漫画探针、Koharu、ground truth、metrics 或 `output`。

关键文件：

- `AITRANS/Views/ImageTranslationViews.swift`
- `AITRANS.xcodeproj/project.pbxproj`
- `.github/workflows/ci-results.yml`
- `scripts/test-v351-image-status-accessibility-contract.py`
- `scripts/test-v347-image-command-accessibility-contract.py`
- `scripts/test-v348-image-preview-context-accessibility-contract.py`
- `scripts/test-v349-image-language-accessibility-contract.py`
- `scripts/test-v350-image-selection-supersession-accessibility-contract.py`

验证与遗留：

- 本地轻量检查通过：v3.47 4/4、v3.48 4/4、v3.49 4/4、v3.50 4/4、v3.51 4/4、v1.87 UI interaction 12/12、v2.02 import isolation 10/10、v2.03 cancel/retry 4/4、v2.04 export lifecycle 9/9、v2.07 OCR direction 9/9、v2.09 render feedback 6/6，`xcrun swiftc -parse AITRANS/Views/ImageTranslationViews.swift`、版本解析、JSON smoke 与 `git diff --check` 均通过。源码合同不能替代真实设备／模拟器 VoiceOver、Dynamic Type、状态更新朗读和连续操作回放。
- 候选 SHA `878508f9c28c86aee46e3c3df85d4f267e3ea77a` 的 full run `30683946332` 成功并写入 `AITRANS CI/full-validation=success`。未加密 artifact 的 version、branch、commitSha、runId、runAttempt、workflowName、`validationProfile=full`、`validationReason=candidate_development_push` 均精确匹配；`xcodeBuildRequired=true`，`.xcresult` build summary 为 `status=succeeded`、0 errors、0 warnings；JUnit `10/10`、0 failures；静态、Speech、图片/UI（含 v3.51）、首页、粘贴和扩展 Koharu fixture matrix 均通过。
- PR #115 fast run `30684137767` 成功，精确记录 `reusedFullValidationSha=878508f9c28c86aee46e3c3df85d4f267e3ea77a`、`reusedFullValidationState=success`、`xcodeBuildRequired=false` 与 `fast_followup_reuses_candidate_full_validation`。合并后 fast run `30684165445` 成功，精确匹配 merge SHA `b6e8c88e74ff3fa9c8d78618d3f2f624480d4b43`，`validationReason=merge_reuses_successful_candidate_full_validation`、`receiptPropagationAllowed=true`、`smalldataParentFullValidationState=success`，复用同一候选 full receipt；两者均是 fast 路由／静态跟踪，不替代候选 full 的 Swift/Xcode 编译证据。
- 未跑本机 build / 探针，按规则交给云端验证。候选 full 使用 `probe_mode=skip`，UI evidence 为 `not_requested`，未生成新的漫画探针数字、`output/` 报告或 `metrics/version_history.csv` 行。真实 Koharu 四件套、Speech corpus 与真实竖排图片 corpus 仍缺失；active Koharu validator 仍为 `manifestMissing / stopUntilArtifactsProvided`，本版不声称 OCR、翻译、识别或 Koharu 质量提升。

## v3.50：图片导入运行中替换的 VoiceOver 范围提示
日期：2026-08-01

状态：Agent X 已完成实现、云端验收和合并收口；工程正式版本为 `MARKETING_VERSION=3.50`。PR #114 已合入 `smalldata_test`，merge SHA `6d9d7e211e00990eac7e7910abe51c0830a4b0fc`；远端 `codeb/v3.50-image-selection-a11y` 已删除，未触碰 `main`。

核心变更：

- 审查图片命令栏时发现，照片与文件入口在图片读取、Vision OCR 或逐块翻译进行中仍有意允许替换当前任务，但 VoiceOver 只会说“选择图片并开始 OCR 与翻译”，没有告知新选择会 supersede 当前任务，容易让用户误以为两次导入会排队或保留旧结果。
- v3.50 为照片入口增加运行中分支，为文件入口增加对应的 View 私有 `fileSelectionAccessibilityHint`：运行中明确说明选择新图片会取消当前读取、OCR 或翻译并开始新的本机 OCR 与翻译；非运行态保留首次选择、替换当前图片和文件导入语义。两个导入入口继续可用，不新增 `.disabled(isRunning)`，因为现有 `TranslationSessionStore.beginImageTranslationTask` 会取消旧 task、更新 task ID、清理旧输入并由回调隔离防止 stale result 覆盖。
- 该版本只改善 VoiceOver 文案与操作预期，不新增 Store／持久化状态，不改变图片 task、Vision OCR、模型翻译、renderer/export、漫画探针、Koharu、ground truth、metrics 或 `output`。

关键文件：

- `AITRANS/Views/ImageTranslationViews.swift`
- `AITRANS.xcodeproj/project.pbxproj`
- `.github/workflows/ci-results.yml`
- `scripts/test-v350-image-selection-supersession-accessibility-contract.py`
- `scripts/test-v347-image-command-accessibility-contract.py`
- `scripts/test-v348-image-preview-context-accessibility-contract.py`
- `scripts/test-v349-image-language-accessibility-contract.py`

验证与遗留：

- 本地轻量检查通过：v3.47 4/4、v3.48 4/4、v3.49 4/4、v3.50 4/4、v1.87 UI interaction 12/12、v2.02 import isolation 10/10、v2.03 cancel/retry 4/4、v2.07 OCR direction 9/9，`xcrun swiftc -parse AITRANS/Views/ImageTranslationViews.swift`、版本解析与 `git diff --check` 均通过。源码合同不能替代真实设备／模拟器 VoiceOver、Dynamic Type、PhotosPicker／fileImporter 取消与替换手势回放。
- 候选 SHA `f4900c8e51771625884bbc15984e401d8a466387` 的 full run `30683386394` 成功并写入 `AITRANS CI/full-validation=success`。未加密 artifact 的 version、branch、commitSha、runId、runAttempt、workflowName、`validationProfile=full`、`validationReason=candidate_development_push` 均精确匹配；`xcodeBuildRequired=true`，`.xcresult` build summary 为 `status=succeeded`、0 errors、0 warnings；JUnit `10/10`、0 failures；静态、Speech、图片/UI（含 v3.50）、首页、粘贴和扩展 Koharu fixture matrix 均通过。
- PR #114 fast run `30683624455` 成功，精确记录 `reusedFullValidationSha=f4900c8e51771625884bbc15984e401d8a466387`、`reusedFullValidationState=success`、`xcodeBuildRequired=false` 与 `fast_followup_reuses_candidate_full_validation`。合并后 fast run `30683653755` 成功，精确匹配 merge SHA `6d9d7e211e00990eac7e7910abe51c0830a4b0fc`，`validationReason=merge_reuses_successful_candidate_full_validation`、`receiptPropagationAllowed=true`、`smalldataParentFullValidationState=success`，复用同一候选 full receipt；两者均是 fast 路由／静态跟踪，不替代候选 full 的 Swift/Xcode 编译证据。
- 未跑本机 build / 探针，按规则交给云端验证。候选 full 使用 `probe_mode=skip`，UI evidence 为 `not_requested`，未生成新的漫画探针数字、`output/` 报告或 `metrics/version_history.csv` 行。真实 Koharu 四件套、Speech corpus 与真实竖排图片 corpus 仍缺失；active Koharu validator 仍为 `manifestMissing / stopUntilArtifactsProvided`，本版不声称 OCR、翻译、识别或 Koharu 质量提升。

## v3.49：图片语言菜单的状态化 VoiceOver 提示
日期：2026-08-01

状态：Agent X 已完成实现、云端验收和合并收口；工程正式版本为 `MARKETING_VERSION=3.49`。PR #113 已合入 `smalldata_test`，merge SHA `bbcf68edccb9009440e0738c5f92a94ec3eefee4`；远端 `codeb/v3.49-image-language-a11y` 已删除，未触碰 `main`。

核心变更：

- 审查图片翻译设置时发现，输入／目标语言菜单虽然已有 Pro 和运行态限制，但 VoiceOver 提示没有说明“什么时候可改、会影响什么、失败或取消后会怎样”，且静态 Pro 文案在已解锁时仍会误导用户。
- v3.49 为 `ImageSourceLanguageControl` 与 `ImageTargetLanguageControl` 增加 View 私有的状态化 accessibility hint：运行中明确要先完成或取消；输入语言区分 Pro 锁定、无图片、已完成重新识别／翻译和失败／取消后的下次重试；目标语言区分无图片、已完成重新翻译和失败／取消后的下次重试。两者继续保留 `.disabled(isRunning)`，选回当前内容语言的撤销语义也在提示中说明。
- 该版本只改善 VoiceOver 文案与用户操作预期，不新增 Store／持久化状态，不改变图片 task、Vision OCR、模型翻译、renderer/export、漫画探针、Koharu、ground truth、metrics 或 `output`。

关键文件：

- `AITRANS/Views/ImageTranslationViews.swift`
- `AITRANS.xcodeproj/project.pbxproj`
- `.github/workflows/ci-results.yml`
- `scripts/test-v349-image-language-accessibility-contract.py`
- `scripts/test-v34-image-retry-language-contract.py`
- `scripts/test-v347-image-command-accessibility-contract.py`
- `scripts/test-v348-image-preview-context-accessibility-contract.py`

验证与遗留：

- 本地轻量检查通过：v2.07 OCR direction 9/9、v1.87 UI interaction 12/12、v3.4 5/5、v3.5 5/5、v3.6 5/5、v3.7 4/4、v3.46 4/4、v3.47 4/4、v3.48 4/4、v3.49 4/4，`xcrun swiftc -parse AITRANS/Views/ImageTranslationViews.swift`、版本解析、JSON/YAML smoke 与 `git diff --check` 均通过。源码合同不能替代真实设备／模拟器 VoiceOver、Dynamic Type 或语言切换回放。
- 候选 SHA `46d8eb9d3a04aa07ff5e34d0daa001bb77c8343b` 的 full run `30645171049` 因 v1.87 历史合同要求保留“已完成的图片会重新翻译”而失败；修复后的 `43c75563ee59801fbddcbe872bc5fd7d8927d019` 的 run `30682569934` 又因 v2.07 历史合同要求“已完成的图片会重新识别和翻译”而失败；两次均不作最终收据。最终候选 SHA `aac788e371e918820efb3d3875039ae871ece5e0` 的 full run `30682755735` 成功并写入 `AITRANS CI/full-validation=success`。未加密 artifact 的 version、branch、commitSha、runId、runAttempt、workflowName、`validationProfile=full`、`validationReason=candidate_development_push` 均精确匹配；`xcodeBuildRequired=true`，`xcresult` build summary 为 `status=succeeded`、0 errors、0 warnings；JUnit `10/10`、0 failures；UI interaction（含 v3.49 4/4）、Speech、首页、粘贴和扩展 Koharu fixture matrix 均通过。
- PR #113 fast run `30682982193` 成功，精确记录 `reusedFullValidationSha=aac788e371e918820efb3d3875039ae871ece5e0`、`reusedFullValidationState=success`、`xcodeBuildRequired=false` 与 `fast_followup_reuses_candidate_full_validation`。合并后 fast run `30683016098` 成功，精确匹配 merge SHA `bbcf68edccb9009440e0738c5f92a94ec3eefee4`，`validationReason=merge_reuses_successful_candidate_full_validation`、`receiptPropagationAllowed=true`、`smalldataParentFullValidationState=success`，复用同一候选 full receipt；两者均是 fast 路由／静态跟踪，不替代候选 full 的 Swift/Xcode 编译证据。
- 未跑本机 build / 探针，按规则交给云端验证。候选 full 使用 `probe_mode=skip`，UI evidence 为 `not_requested`，未生成新的漫画探针数字、`output/` 报告或 `metrics/version_history.csv` 行。真实 Koharu 四件套、Speech corpus 与真实竖排图片 corpus 仍缺失；active Koharu validator 仍为 `manifestMissing / stopUntilArtifactsProvided`，本版不声称 OCR、翻译、识别或 Koharu 质量提升。

## v3.48：图片预览识别上下文的 VoiceOver 汇总
日期：2026-07-31

状态：Agent X 已完成实现、云端验收和合并收口；工程正式版本为 `MARKETING_VERSION=3.48`。PR #112 已合入 `smalldata_test`，merge SHA `d01bd851084ab12ff1f4a81e0150f6e4a053d7ad`；远端 `codeb/v3.48-image-preview-context` 已删除，未触碰 `main`。

核心变更：

- 审查完整图片预览的屏幕阅读器上下文时发现，用户可以逐块点按并打开局部放大，但预览容器没有稳定说明当前识别块总数、待复查数量、筛选定位位置或当前可用操作；原始背景图片还可能与 OCR 覆盖重复朗读。
- v3.48 让 ready 分支的 `ImageTranslationPreview` 使用 View 私有 `previewAccessibilityValue` / `previewAccessibilityHint`：value 汇总完整 `store.imageTranslationBlocks`、风险块和 `reviewedBlockIDs` 的待复查剩余量，并说明当前 `positionText`；空 blocks、无风险块和未选中状态也有明确读法。预览容器使用“图片翻译预览” label，原始 `Image(uiImage:)` `.accessibilityHidden(true)`，hint 保留“点按文字块可定位并打开局部放大”，并在修正／复查被状态门锁住时复用既有 `modificationUnavailableHint` / `reviewUnavailableHint`。没有新增 Store、持久化、OCR、翻译、renderer/export 或 Koharu 状态。
- 新增 `scripts/test-v348-image-preview-context-accessibility-contract.py`（4 项）并接入 UI interaction fail-fast；v3.47 合同改为允许后续正式 `3.x` 版本回归。为避免 GitHub Actions workflow expression 长度超过上限，v3.47/v3.48 changed-file route 合并为一条正则，相关合同同步校验该路由。

验证与遗留：

- 本地轻量检查通过：v2.7 OCR direction 9/9、v3.0 5/5、v3.1 6/6、v3.15 5/5、v3.27 6/6、v3.34 6/6、v3.41 5/5、v3.42 4/4、v3.43 4/4、v3.44 4/4、v3.45 4/4、v3.46 4/4、v3.47 4/4、v3.48 4/4，`xcrun swiftc -parse AITRANS/Views/ImageTranslationViews.swift`、版本解析 `v3.48`、JSON/YAML smoke、`git diff --check` 均通过。源码合同不能替代真实设备／模拟器 VoiceOver、Dynamic Type、覆盖命中区域或连续手势回放。
- 首次候选 SHA `6dd6df90adc00d56b4a7bd0e8ee0d75fb45f327a` 的 run `30643437015` 因 workflow expression 长度预解析失败且没有 jobs/artifact，不作验证证据；压缩路由后的最终候选 SHA `ebab7d7b2b36c1fa2037aaa8ae02dc55b7ecbc84` 的 full run `30643759446` 成功，`AITRANS CI/full-validation` 为 success。未加密 artifact 的 version、branch、commitSha、runId、runAttempt、workflowName、`validationProfile=full`、`validationReason=candidate_development_push` 精确匹配；`xcodeBuildRequired=true`、Xcode build 成功、`.xcresult` 已附带；JUnit `10/10`、0 failures；静态、Speech、图片/UI（含 v3.48）、首页、粘贴和扩展 Koharu validator fixture 矩阵均通过。
- PR #112 fast run `30644368091` 成功，精确记录 `reusedFullValidationSha=ebab7d7b2b36c1fa2037aaa8ae02dc55b7ecbc84`、`reusedFullValidationState=success`、`xcodeBuildRequired=false` 和 `fast_followup_reuses_candidate_full_validation`。合并后 fast run `30644443143` 成功，精确匹配 merge SHA，`validationReason=merge_reuses_successful_candidate_full_validation`、`receiptPropagationAllowed=true`、`smalldataParentFullValidationState=success`，复用同一候选 full receipt；两者均是 fast 路由／静态跟踪，不替代候选 full 的 Swift/Xcode 编译证据。
- 未跑本机 build / 探针，按规则交给云端验证。候选 full 使用 `probe_mode=skip`，UI evidence 为 `not_requested`，未生成新的漫画探针数字、`output/` 报告或 `metrics/version_history.csv` 行。真实 Koharu 四件套、Speech corpus 与真实竖排图片 corpus 仍缺失；active Koharu validator 仍为 `manifestMissing / stopUntilArtifactsProvided`，本版不声称 OCR、翻译、识别或 Koharu 质量提升。

## v3.47：图片命令栏操作范围的 VoiceOver 提示
日期：2026-07-31

状态：Agent X 已完成实现、云端验收和合并收口；工程正式版本为 `MARKETING_VERSION=3.47`。PR #111 已合入 `smalldata_test`，merge SHA `66f9857b9784ffef956d3a6bf74c1e86643c6fbf`；远端 `codeb/v3.47-image-command-a11y` 已删除，未触碰 `main`。

核心变更：

- 审查图片页的高频命令时发现，“重试”和“重新识别”虽有不同按钮名，但 VoiceOver 不知道它们分别会重跑整张图片还是只生成导出图；照片选择、取消、导出和清空也没有声明是否影响当前图片、OCR／翻译或导出文件。
- v3.47 为 `ImageCommandBar` 的照片／文件、取消、重试、重新识别、重试导出、导出／分享和清空命令补充作用域明确的 accessibility hint；免费入口继续说明需要 Pro。`PhotoPickerCommand` 接收动态选择提示：无当前图片时为首次选择，已有图片时为替换当前图片。所有提示仅是 View 语义，不新增 Store／持久化状态，不改变图片 task、Vision OCR、模型翻译、renderer/export 或命令行为。
- 新增 `scripts/test-v347-image-command-accessibility-contract.py`（4 项），接入 UI interaction fail-fast，并让 v3.46 版本合同继续允许后续 `3.x` 回归。

验证与遗留：

- 本地轻量检查通过：v3.44–v3.47 图片 VoiceOver 合同、v3.15 图片预览选择回归、`xcrun swiftc -parse AITRANS/Views/ImageTranslationViews.swift`、版本解析 `v3.47`、workflow YAML 与 `git diff --check`。源码合同不能替代真实设备／模拟器 VoiceOver、Dynamic Type、分享面板、取消手势或导出失败回放。
- 候选 SHA `35fd6d36a97d4c95906ec9c6ff9c3a454082a479` 的 full run `30641925259` 成功，`AITRANS CI/full-validation` status 为 success；未加密 artifact `aitrans-ci-v3.47-codeb-v3.47-image-command-a11y--35fd6d36a97d-run30641925259-attempt1` 的 version、branch、commitSha、runId、runAttempt、workflowName、`validationProfile=full`、`validationReason=candidate_development_push` 均精确匹配。`xcodeBuildRequired=true`、云端 Xcode build 成功，`.xcresult` 已附带；JUnit `10/10`、0 failures；静态、Speech、图片/UI（含 v3.47）、首页、粘贴和扩展 Koharu validator fixture 矩阵均通过。
- PR #111 fast run `30642581419` 成功，精确记录 `reusedFullValidationSha=35fd6d36a97d4c95906ec9c6ff9c3a454082a479`、`reusedFullValidationState=success`、`xcodeBuildRequired=false` 和 `fast_followup_reuses_candidate_full_validation`。合并后 fast run `30642651520` 成功，精确匹配 merge SHA，`validationReason=merge_reuses_successful_candidate_full_validation`、`receiptPropagationAllowed=true`，复用同一候选 full receipt；两者均是 fast 路由／静态跟踪，不替代候选 full 的 Swift/Xcode 编译证据。
- 未跑本机 build / 探针，按规则交给云端验证。候选 full 使用 `probe_mode=skip`，UI evidence 为 `not_requested`，未生成新的漫画探针数字、`output/` 报告或 `metrics/version_history.csv` 行。真实 Koharu 四件套、Speech corpus 与真实竖排图片 corpus 仍缺失；active Koharu validator 仍为 `manifestMissing / stopUntilArtifactsProvided`，本版不声称 OCR、翻译、识别或 Koharu 质量提升。

## v3.46：图片预览加载与失败状态的 VoiceOver 反馈
日期：2026-07-31

状态：Agent X 已完成实现、云端验收和合并收口；工程正式版本为 `MARKETING_VERSION=3.46`。PR #110 已合入 `smalldata_test`，merge SHA `1ed986098c47ec4b732fe2b894273f0bdc63057e`；远端 `codeb/v3.46-image-preview-status-a11y` 已删除，未触碰 `main`。

核心变更：

- 审查图片页的异步预览状态时发现，视觉上虽然显示“正在准备预览／预览生成失败”，但 VoiceOver 没有稳定的状态 label/value；失败后的“重试预览”也没有明确说明它不会重新 OCR 或翻译，用户容易误判操作成本和影响范围。
- v3.46 为 `ImageTranslationPreview` 的 loading／failure 卡片增加 View 私有的状态 accessibility label/value：加载时说明图片已载入、正在后台生成屏幕预览；失败时说明原图仍保留用于 OCR 与导出。失败按钮增加“重新生成屏幕预览；不会重新识别或翻译图片”的 hint，仍只递增既有 `previewAttempt`，不改变 revision、`ImagePreviewService`、OCR、翻译、renderer/export 或 Store。
- 新增 `scripts/test-v346-image-preview-status-accessibility-contract.py`（4 项），并让 v3.45 合同继续兼容后续 `3.x` 版本。没有新增 Store、持久化、漫画探针、Koharu、ground truth、metrics 或 `output/` 行为。

验证与遗留：

- 本地轻量检查通过：v3.15 回归、v3.43–v3.46 图片 VoiceOver 合同，`xcrun swiftc -parse AITRANS/Views/ImageTranslationViews.swift`、版本解析 `v3.46`、workflow YAML 与 `git diff --check`。源码合同不能替代真实设备／模拟器 VoiceOver、Dynamic Type、预览失败恢复或连续手势回放。
- 候选 SHA `dd0ac6d96723fcc9531bd85cd35da226f05ae3d9` 的 full run `30640658564` 成功，`AITRANS CI/full-validation` status 为 success；未加密 artifact `aitrans-ci-v3.46-codeb-v3.46-image-preview-status-a11y--dd0ac6d96723-run30640658564-attempt1` 的 version、branch、commitSha、runId、runAttempt、workflowName、`validationProfile=full`、`validationReason=candidate_development_push` 均精确匹配。`xcodeBuildRequired=true`、Xcode build 成功、xcodebuild log 无 error/warning；`.xcresult` 已附带；JUnit `10/10`、0 failures；UI interaction、Speech、首页、粘贴和扩展 Koharu validator fixture 矩阵均通过。
- PR #110 fast run `30641294092` 成功，精确记录 `reusedFullValidationSha=dd0ac6d96723fcc9531bd85cd35da226f05ae3d9`、`reusedFullValidationState=success`、`xcodeBuildRequired=false` 和 `fast_followup_reuses_candidate_full_validation`。合并后 fast run `30641380308` 成功，精确匹配 merge SHA，`validationReason=merge_reuses_successful_candidate_full_validation`、`receiptPropagationAllowed=true`，复用同一候选 full receipt；两者均是 fast 路由／静态跟踪，不替代候选 full 的 Swift/Xcode 编译证据。
- 未跑本机 build / 探针，按规则交给云端验证。候选 full 使用 `probe_mode=skip`，UI evidence 为 `not_requested`，未生成新的漫画探针数字、`output/` 报告或 `metrics/version_history.csv` 行。真实 Koharu 四件套、Speech corpus 与真实竖排图片 corpus 仍缺失；active Koharu validator 仍为 `manifestMissing / stopUntilArtifactsProvided`，本版不声称 OCR、翻译、识别或 Koharu 质量提升。

## v3.45：图片覆盖入口与结果行的 VoiceOver 操作语义统一
日期：2026-07-31

状态：Agent X 已完成实现、云端验收和合并收口；工程正式版本为 `MARKETING_VERSION=3.45`。PR #109 已合入 `smalldata_test`，merge SHA `cb18b04a2a9e5eaf0726116f83e715fd047b6eef`；远端 `codeb/v3.45-image-overlay-a11y` 已删除，未触碰 `main`。

核心变更：

- 审查图片翻译页时发现，结果行主定位动作已经按 `isSelected` 提示“取消此文字块在图片中的定位”或“在图片预览中定位此文字块”，但完整图片预览中的 `ImageTranslationOverlayBlock` 仍使用旧的“取消图片中的定位／在图片中定位并打开局部放大”。同一文字块从图片入口和列表入口进入时，VoiceOver 会听到不一致的动作语义。
- v3.45 让两种覆盖模式的图片按钮复用与结果行一致的 View 私有 `accessibilityHint`：已定位时读出“取消此文字块在图片中的定位”，未定位时读出“在图片预览中定位此文字块”。既有 `accessibilityLabel`、翻译／定位 `accessibilityValue`、44pt 点击区、选择回调、局部预览和 Store 边界均不变。
- 新增 `scripts/test-v345-image-overlay-accessibility-contract.py`（4 项）并接入 UI interaction fail-fast。云端首次 full 发现历史 `scripts/test-v315-image-preview-direct-selection-contract.py` 仍硬编码已废弃的旧文案；该合同现改为验证 hint 接线、状态分流和可访问结构，不再阻断后续合法文案迭代。没有新增 Store、持久化、Vision OCR、模型、renderer/export、漫画探针、Koharu、ground truth、metrics 或 `output/` 行为。

验证与遗留：

- 本地轻量检查通过：v3.42、v3.43、v3.44、v3.45 合同，v3.15 覆盖选择回归合同（修复后），`xcrun swiftc -parse AITRANS/Views/ImageTranslationViews.swift`、版本解析 `v3.45`、workflow YAML 与 `git diff --check`。源码合同不能替代真实设备／模拟器 VoiceOver、Dynamic Type、覆盖按钮命中区域或连续手势回放。
- 候选首个 SHA `34d00a7d0ada90b30acdab03a76e29e16b3ab7f5` 的 full run `30638887106` 仅因 v3.15 历史合同硬编码旧 hint 而失败，Xcode build 与其余契约均成功；该 run 不作最终验收证据。修复后的候选 SHA `cdb2fbc201d5aa8affb7f43578895ce5ce404195` 的 full run `30639454988` 成功，`AITRANS CI/full-validation` status 为 success；未加密 artifact `aitrans-ci-v3.45-codeb-v3.45-image-overlay-a11y--cdb2fbc201d5-run30639454988-attempt1` 的 version、branch、commitSha、runId、runAttempt、workflowName、`validationProfile=full`、`validationReason=candidate_development_push` 均精确匹配。`xcodeBuildRequired=true`、Xcode build 成功、xcodebuild log 无 error/warning；`.xcresult` 已附带；JUnit `10/10`、0 failures；UI interaction、Speech、首页、粘贴和扩展 Koharu validator fixture 矩阵均通过。
- PR #109 fast run `30640000286` 成功，精确记录 `reusedFullValidationSha=cdb2fbc201d5aa8affb7f43578895ce5ce404195`、`reusedFullValidationState=success`、`xcodeBuildRequired=false` 和 `fast_followup_reuses_candidate_full_validation`。合并后 fast run `30640078255` 成功，精确匹配 merge SHA，`validationReason=merge_reuses_successful_candidate_full_validation`、`receiptPropagationAllowed=true`，复用同一候选 full receipt；两者均是 fast 路由／静态跟踪，不替代候选 full 的 Swift/Xcode 编译证据。
- 未跑本机 build / 探针，按规则交给云端验证。候选 full 使用 `probe_mode=skip`，UI evidence 为 `not_requested`，未生成新的漫画探针数字、`output/` 报告或 `metrics/version_history.csv` 行。真实 Koharu 四件套、Speech corpus 与真实竖排图片 corpus 仍缺失；active Koharu validator 仍为 `manifestMissing / stopUntilArtifactsProvided`，本版不声称 OCR、翻译、识别或 Koharu 质量提升。真实 VoiceOver、动态字体和覆盖按钮在设备上的体验仍需人工回放。

## v3.44：图片导航当前位置的 VoiceOver 上下文
日期：2026-07-31

状态：Agent X 已完成实现、云端验收和合并收口；工程正式版本为 `MARKETING_VERSION=3.44`。PR #108 已合入 `smalldata_test`，merge SHA `eaa48e6258e3185136e16d0aebb378c370d41098`；远端 `codeb/v3.44-image-navigation-position-a11y` 已删除，未触碰 `main`。

核心变更：

- v3.43 已让图片局部预览的前后按钮在筛选首尾读出边界原因，但用户仍只能听到“上一个／下一个”及首尾提示，不一定知道当前位于筛选序列的第几个 block。
- `ImageTranslationFocusPreview` 新增 View 私有 `navigationPositionAccessibilityValue`，由既有 `positionText` 生成“当前位置 1 / 3”一类 accessibility value；没有位置时明确读出“未显示筛选位置”。前后两个导航按钮共享该 value，同时保留 v3.43 的 disabled 边界与动态 hint。该 value 不创建 Store／持久化／选择状态，也不改变导航 action、OCR、翻译、renderer/export 或焦点交接。
- 新增 `scripts/test-v344-image-navigation-position-accessibility-contract.py`（4 项）并接入 UI interaction fail-fast；历史 v3.43 版本合同改为拒绝旧版本 literal、允许后续 `3.x` 版本继续回归。

验证与遗留：

- 本地轻量检查通过：v3.41 `5/5`、v3.42 `4/4`、v3.43 `4/4`、v3.44 `4/4`、`xcrun swiftc -parse AITRANS/Views/ImageTranslationViews.swift`、版本解析 `v3.44`、workflow YAML 与 `git diff --check`。源码合同不能替代真实设备／模拟器 VoiceOver、Dynamic Type、焦点边界或连续手势回放。
- 候选 SHA `fef1f344c47fd5e2cbd3d3cfa3f9fd863ea4cdb6` 的 full run `30637695406` 成功，`AITRANS CI/full-validation` status 为 success；未加密 artifact 的 version、branch、commitSha、runId、runAttempt、workflowName、`validationProfile=full` 与 `validationReason=candidate_development_push` 均精确匹配。`xcodeBuildRequired=true`、Xcode build 成功，`.xcresult` 已附带；JUnit `10/10`、0 failures，UI interaction contract 成功，新 v3.44 合同 `4/4`。
- PR #108 fast `30638258336` 成功，精确记录 `reusedFullValidationSha=fef1f344c47fd5e2cbd3d3cfa3f9fd863ea4cdb6`、`reusedFullValidationState=success` 与 `xcodeBuildSkippedReason=fast_followup_reuses_candidate_full_validation`。合并后 fast `30638309096` 成功，精确匹配 merge SHA，`validationReason=merge_reuses_successful_candidate_full_validation`、`receiptPropagationAllowed=true` 并复用同一候选 full receipt；两者均是 fast 路由／静态跟踪，不替代候选 full 的 Swift/Xcode 编译证据。
- 未跑本机 build / 探针，按规则交给云端验证。候选 full 使用 `probe_mode=skip`，UI evidence 为 `not_requested`，未生成新的漫画探针数字、`output/` 报告或 `metrics/version_history.csv` 行。真实 Koharu 四件套、Speech corpus 与真实竖排图片 corpus 仍缺失；active Koharu validator 为 `manifestMissing / stopUntilArtifactsProvided`，本版不声称 OCR、翻译、识别或 Koharu 质量提升。

## v3.43：图片导航边界与定位状态的 VoiceOver 反馈
日期：2026-07-31

状态：Agent X 已完成实现、云端验收和合并收口；工程正式版本为 `MARKETING_VERSION=3.43`。PR #107 已合入 `smalldata_test`，merge SHA `dd3da99dcfe0f4384d0ee0ce4575958e75d96c67`；远端 `codeb/v3.43-image-navigation-a11y` 已删除，未触碰 `main`。

核心变更：

- 审查图片局部预览时发现，前后导航按钮虽然在筛选序列首尾正确禁用，但 VoiceOver 只能听到按钮名称，无法知道“为什么不能继续”；结果行主操作也始终读成“在图片预览中定位”，已选中时无法得知再次操作会取消定位。
- `ImageTranslationFocusPreview` 现在让可用的前后按钮分别提示“定位上一个文字块／定位下一个文字块”，首尾 disabled 状态分别提示“当前已是筛选结果中的第一个文字块／最后一个文字块”。`ImageTranslationBlockRow` 的主选择 hint 按 `isSelected` 在“取消此文字块在图片中的定位”和“在图片预览中定位此文字块”之间切换；选择、筛选、Store、图片 task、OCR、翻译和焦点交接语义不变。
- 新增 `scripts/test-v343-image-navigation-accessibility-contract.py`（4 项）并接入 UI interaction fail-fast；历史 v3.42 版本合同改为拒绝旧版本 literal、同时允许后续 `3.x` 版本继续验证。没有新增 Store／持久化、Vision OCR、模型、renderer/export、漫画探针、Koharu、ground truth、metrics 或 `output/` 行为。

验证与遗留：

- 本地轻量检查通过：v3.42 `4/4`、v3.43 `4/4`、v3.41 `5/5`、`xcrun swiftc -parse AITRANS/Views/ImageTranslationViews.swift`、版本解析 `v3.43`、workflow YAML 与 `git diff --check`。源码合同不能替代真实设备／模拟器 VoiceOver、Dynamic Type、焦点边界或连续手势回放。
- 候选 SHA `6ad32c2ef7ad1790de99fecb99bf600729e1cdcf` 的 full run `30636513626` 成功，`AITRANS CI/full-validation` status 为 success；未加密 artifact 的 version、branch、commitSha、runId、runAttempt、workflowName、`validationProfile=full` 与 `validationReason=candidate_development_push` 均精确匹配。`xcodeBuildRequired=true`、Xcode build 成功，`.xcresult` 已附带；JUnit `10/10`、0 failures，UI interaction contract 成功，新 v3.43 合同 `4/4`。
- PR #107 fast `30637099003` 成功，精确记录 `reusedFullValidationSha=6ad32c2ef7ad1790de99fecb99bf600729e1cdcf`、`reusedFullValidationState=success` 与 `xcodeBuildSkippedReason=fast_followup_reuses_candidate_full_validation`。合并后 fast `30637158511` 成功，精确匹配 merge SHA，`validationReason=merge_reuses_successful_candidate_full_validation`、`receiptPropagationAllowed=true` 并复用同一候选 full receipt；两者均是 fast 路由／静态跟踪，不替代候选 full 的 Swift/Xcode 编译证据。
- 未跑本机 build / 探针，按规则交给云端验证。候选 full 使用 `probe_mode=skip`，UI evidence 为 `not_requested`，未生成新的漫画探针数字、`output/` 报告或 `metrics/version_history.csv` 行。真实 Koharu 四件套、Speech corpus 与真实竖排图片 corpus 仍缺失；active Koharu validator 为 `manifestMissing / stopUntilArtifactsProvided`，本版不声称 OCR、翻译、识别或 Koharu 质量提升。

## v3.42：图片操作锁定的状态化反馈
日期：2026-07-31

状态：Agent X 已完成实现、云端验收和合并收口；工程正式版本为 `MARKETING_VERSION=3.42`。PR #106 已合入 `smalldata_test`，merge SHA `6b5c0ab8e74a7b1605dad05b43ad6986213a582b`；远端 `codeb/v3.42-image-action-lock-feedback` 已删除，未触碰 `main`。

核心变更：

- v3.41 让仍在逐块翻译的 OCR blocks 可查看／定位，同时锁住会改变图片结果或复查进度的入口；审查发现这些入口中的一部分虽已禁用，却只给出泛化提示，用户和 VoiceOver 无法区分“正在逐块翻译”“翻译失败需重试”与“正在更新导出图”。
- `ImageTranslationPanel` 新增 View 私有 `imageModificationUnavailableDetail`、`imageReviewUnavailableDetail`、`imageActionLockTitle` 与 `imageActionLockDetail`。当前 blocks 非空且任一操作被锁定时显示警示状态行；覆盖方式、开始／继续／重启复查、局部预览、结果行的修正／Vision OCR 恢复／完成复查、以及已忽略 block 恢复，都复用相同的状态化 VoiceOver 禁用原因。逐块翻译明确仍可查看和定位，失败明确引导重试，导出重绘仅锁住图片编辑而保留已完成翻译后的复查。
- 后续审查补齐局部预览、结果行和忽略列表的同一提示传递，避免局部入口回退为旧泛化文案。没有改变 `canModifyImageTranslation`／`canReviewImageTranslation`、`TranslationSessionStore` finalized-state guard、Vision OCR、模型翻译、renderer/export、持久化、漫画探针、Koharu、ground truth、metrics 或 `output/`；不能把此体验改进描述为 OCR、翻译、识别或 Koharu 质量提升。
- 关键文件为 `AITRANS/Views/ImageTranslationViews.swift`、`AITRANS.xcodeproj/project.pbxproj`、`.github/workflows/ci-results.yml`、`scripts/test-v316-image-review-queue-entry-contract.py`、`scripts/test-v341-image-review-final-state-lock-contract.py` 与新增 `scripts/test-v342-image-action-lock-feedback-contract.py`。

验证与遗留：

- 本地轻量检查通过：v3.16 `5/5`、v3.41 `5/5`、v3.42 `4/4`、v1.87 `12/12`、v1.94 `10/10`、v1.97 `5/5`、图片 import／share 回归合同、`xcrun swiftc -parse AITRANS/Views/ImageTranslationViews.swift`、版本解析 `v3.42`、workflow YAML 与 `git diff --check`。这些源码／静态检查不能替代真实逐块翻译、失败后重试、VoiceOver、Dynamic Type 或连续手势回放。
- 初始候选 SHA `65ab4cf2447b929112c7546bc2c135d20eec3ef3` 的 full `30634260280` 只因 v3.16 静态合同仍期待已删除的旧泛化 literal 而失败；该合同已随状态化实现更新，不能作为最终验收证据。最终候选 SHA `98e9667db7d3364a9c54c5dda666945a1077e40e` 的 full run `30635545111` 成功，`AITRANS CI/full-validation` 为 success；未加密 artifact `aitrans-ci-v3.42-codeb-v3.42-image-action-lock-feedback--98e9667db7d3-run30635545111-attempt1` 的 version、branch、commitSha、runId、runAttempt、workflowName、`validationProfile=full` 与 `validationReason=candidate_development_push` 均精确匹配。`xcodeBuildRequired=true`、`xcodeBuildOutcome=success`，`.xcresult` 已附带；JUnit `10/10`、0 failures，UI interaction contract 成功，v3.42 合同 `4/4`。这是本版 Swift/Xcode 编译证据。
- PR #106 fast `30635953184` 成功，精确记录 `reusedFullValidationSha=98e9667db7d3364a9c54c5dda666945a1077e40e`、`reusedFullValidationState=success` 与 `xcodeBuildSkippedReason=fast_followup_reuses_candidate_full_validation`。合并后 fast `30636021103` 成功，精确匹配 merge SHA，`validationReason=merge_reuses_successful_candidate_full_validation`、`receiptPropagationAllowed=true` 并复用同一 full receipt；两者均是 fast 路由／静态跟踪，不替代候选 full 的 Swift/Xcode 编译证据。
- 未跑本机 build / 探针，按规则交给云端验证。候选 full 使用 `probe_mode=skip`，UI evidence 为 `not_requested`，未生成新的漫画探针数字、`output/` 报告或 `metrics/version_history.csv` 行。真实 Koharu 四件套、Speech corpus 与真实竖排图片 corpus 仍缺失；active Koharu validator 仍为 `manifestMissing / stopUntilArtifactsProvided`。真实设备／模拟器仍需人工回放逐块翻译、失败后重试、VoiceOver 与紧凑布局。

## v3.41：图片复查仅在最终翻译结果开放
日期：2026-07-31

状态：Agent X 已完成实现、云端验收和合并收口；工程正式版本为 `MARKETING_VERSION=3.41`。PR #105 已合入 `smalldata_test`，merge SHA `595ff7a9e035f54ba38b9bd6c6bcd52ebc6e6162`；远端 `codeb/v3.41-image-review-final-state-lock` 已删除，未触碰 `main`。

核心变更：

- 审查普通图片流水线发现，OCR 完成后 Store 会先发布 blocks、再逐块翻译；旧 UI 在 `.translating` 时已经能看到 block，却仍能开始／重启复查、完成／撤销复查，失败或不完整状态也可能进入修正、恢复和覆盖方式入口。这会把中间态的复查结论写入当前图片会话，并在后续翻译完成后继续保留。
- `ImageTranslationPanel` 新增 View 私有 `canModifyImageTranslation` 与 `canReviewImageTranslation`：修正 OCR、恢复 Vision OCR、恢复已忽略 block 和旁贴／覆盖切换要求 `.translated && !isRenderingExport`；开始／继续／重启、结果行与局部预览的完成／撤销要求 `.translated`。中间 blocks、选中定位和局部预览仍保持可见，禁用入口明确说明须等待图片翻译完成。
- `TranslationSessionStore` 的 `markImageTranslationBlockReviewed`、`reopenImageTranslationBlockReview` 与 `resetImageTranslationReviewProgress` 加入同一 finalized-state 防线。成功 OCR 修正会先清除 correction ID、恢复 `.translated`，再复用既有自动标记复查，避免 Store guard 误拦截成功路径。没有改变 OCR、模型翻译、renderer/export、持久化、漫画探针、Koharu、ground truth、metrics 或 `output/`；不能把此操作体验修复描述为识别或翻译质量提升。
- 关键文件为 `AITRANS/Views/ImageTranslationViews.swift`、`AITRANS/Services/TranslationSessionStore.swift`、`AITRANS.xcodeproj/project.pbxproj`、`.github/workflows/ci-results.yml`，新增 `scripts/test-v341-image-review-final-state-lock-contract.py`，并更新既有 UI／图片源码合同以锁定最终状态 predicate。

验证与遗留：

- 本地轻量检查通过：42 个与 CI 同组的图片／UI 合同（新 v3.41 `5/5`，以及 v1.87 `12/12`、v1.94 `10/10`、v1.97 `5/5`）、两个修改 Swift 文件的 `xcrun swiftc -parse`、版本解析 `v3.41`、workflow YAML、ground truth／既有 output JSON smoke 与 `git diff --check`。这些源码／静态检查不能替代实际逐块翻译、失败态、VoiceOver 或连续手势回放。
- 候选 SHA `937d1f909514e198019365b1f1b244caa571fef6` 的 full run `30632420558` 成功，`AITRANS CI/full-validation` status 为 success；未加密 artifact `aitrans-ci-v3.41-codeb-v3.41-image-review-final-state-lock--937d1f909514-run30632420558-attempt1` 的 version、branch、commitSha、runId、runAttempt、workflowName、`validationProfile=full` 与 `validationReason=candidate_development_push` 均精确匹配。`xcodeBuildRequired=true`，`.xcresult` Build 为 succeeded、0 errors、0 warnings；JUnit `10/10`、0 failures，UI、Speech、首页、粘贴与 Koharu contract 均通过。这是本版 Swift/Xcode 编译证据。
- PR #105 fast `30632835705` 成功，精确记录 `reusedFullValidationSha=937d1f909514e198019365b1f1b244caa571fef6` 与 `reusedFullValidationState=success`；合并后 fast `30632919414` 成功，精确匹配 merge SHA，`validationReason=merge_reuses_successful_candidate_full_validation`，`receiptPropagationAllowed=true`。两者均为 fast 路由／静态跟踪，不替代候选 full 的 Swift/Xcode 编译证据。
- 未跑本机 build / 探针，按规则交给云端验证。候选 full 使用 `probe_mode=skip`，UI evidence 为 `not_requested`，未生成新的漫画探针数字、`output/` 报告或 `metrics/version_history.csv` 行。真实 Koharu 四件套、Speech corpus 与真实竖排图片 corpus 仍缺失；active Koharu validator 仍为 `manifestMissing / stopUntilArtifactsProvided`。真实设备／模拟器仍需人工回放逐块翻译、失败后重试、VoiceOver 与紧凑布局。

## v3.40：OCR 修正保存期间的输入锁定
日期：2026-07-31

状态：Agent X 已完成实现、云端验收和合并收口；工程正式版本为 `MARKETING_VERSION=3.40`。PR #104 已合入 `smalldata_test`，merge SHA `9373a6065274a38d88d50995e1a5bd6cb46f6a8a`；远端 `codeb/v3.40-image-correction-save-lock` 已删除，未触碰 `main`。

核心变更：

- 审查 OCR 修正的异步保存链路发现，保存、取消和忽略按钮虽已在 `isSaving` 时锁定，`TextField` 本身仍可重新获取焦点并修改。若旧请求随后成功，sheet 会关闭，用户保存后新增的输入可能没有被采用也没有保留。
- `ImageOCRCorrectionSheet` 现在把既有多行 OCR `TextField` 也绑定 `.disabled(isSaving)`。保存开始时 v3.38 继续先收起键盘，输入在当前 block 的 `imageTranslationCorrectionBlockID` 非空期间锁定；成功或失败清除既有 Store state 后自动恢复既有可编辑状态。
- 没有扩展 Store、持久化或请求状态：仍只调用既有 `correctImageTranslationBlock(block.id, original: normalizedCorrectedOriginal)`，保持 v3.37 规范化、v3.24 弃改保护、v3.25 “确认无误／保存并重译”、v3.38 明确键盘收起、v3.39 滚动收起以及 v3.30–v3.35 revision-scoped 关闭后焦点交接。Vision OCR、模型请求、renderer/export、漫画探针、Koharu、ground truth、metrics 与 `output/` 均未改变。
- 新增 `scripts/test-v340-image-ocr-correction-save-lock-contract.py`（4 项）并接入图片/UI fail-fast，锁定文本框保存期禁用、block-scoped 既有 Store 状态、既有键盘／mutation guard 和 CI 路由。

验证与遗留：

- 本地轻量检查通过：v3.40 合同 `4/4`，v3.39 `4/4`、v3.38 `4/4`、v3.37 `5/5`、v3.24 `6/6`、v3.25 `5/5`、v3.30／v3.33／v3.35 焦点回归合同、v1.87 UI 合同 `12/12`、v1.94 CI 分层 `10/10`、v1.97 版本身份 `5/5`、`xcrun swiftc -parse AITRANS/Views/ImageTranslationViews.swift`、workflow YAML、版本解析 `v3.40` 与 `git diff --check`。源码合同不能替代真实异步翻译、第三方输入法、VoiceOver 或紧凑布局回放。
- 候选 SHA `6e655d69076653a21086d303ee75b7248f8ab0bf` 的 full run `30600277215` 成功，`AITRANS CI/full-validation` status 为 success；未加密 artifact `aitrans-ci-v3.40-codeb-v3.40-image-correction-save-lock--6e655d690766-run30600277215-attempt1` 的 version、branch、commitSha、runId、runAttempt、workflowName、`validationProfile=full`、`validationReason=candidate_development_push` 均精确匹配。`xcodeBuildRequired=true`，`.xcresult` Build 为 succeeded、0 errors、0 warnings；JUnit `10/10`、0 failures；图片/UI、Speech、首页、粘贴与扩展 Koharu validator fixture 矩阵均通过，新 v3.40 合同 `4/4`。
- PR #104 fast `30600543676` 成功，精确记录 `reusedFullValidationSha=6e655d69076653a21086d303ee75b7248f8ab0bf` 与 `reusedFullValidationState=success`，并写明 `xcodeBuildRequired=false`、`fast_followup_reuses_candidate_full_validation`。合并后 fast `30600589242` 成功，精确匹配 merge SHA，`validationReason=merge_reuses_successful_candidate_full_validation`，`receiptPropagationAllowed=true`，复用同一候选 full receipt；两者均只作路由跟踪，不替代候选 full 的 Swift/Xcode 编译证据。
- 未跑本机 build / 探针，按规则交给云端验证。候选 full 使用 `probe_mode=skip`，UI evidence 为 `not_requested`，未生成新的漫画探针数字、`output/` 报告或 `metrics/version_history.csv` 行。真实 Koharu 四件套、Speech corpus 与真实竖排图片 corpus 仍缺失；active Koharu validator 仍为 `manifestMissing / stopUntilArtifactsProvided`，本版不声称 OCR、翻译、识别或 Koharu 质量提升。真实异步翻译、第三方输入法和 VoiceOver 行为仍需在设备／模拟器手工回放。

## v3.39：OCR 修正输入的滚动收起键盘
日期：2026-07-31

状态：Agent X 已完成实现、云端验收和合并收口；工程正式版本为 `MARKETING_VERSION=3.39`。PR #103 已合入 `smalldata_test`，merge SHA `718dad537a3a1c989e58d0de663d235018768982`；远端 `codeb/v3.39-image-correction-scroll-dismiss` 已删除，未触碰 `main`。

核心变更：

- 审查 v3.38 的键盘控制后发现，虽然用户可用键盘工具栏“完成”或操作按钮收起键盘，但在较长的 OCR 修正内容中，向下滚动仍没有同文本页一致的交互式收起行为，可能遮挡下方保存／忽略操作。
- `ImageOCRCorrectionSheet` 的既有 `Form` 新增 `.scrollDismissesKeyboard(.interactively)`；用户开始滚动时可渐进收起软件键盘。v3.38 的明确“完成”动作，以及取消、打开忽略确认、保存前的 `dismissKeyboard()` 均保留，形成互补而非替换。
- 该改动仅作用于 View 键盘可见性：v3.37 的 `normalizedCorrectedOriginal`、v3.24 的语义修改弃改保护、v3.25 的“确认无误／保存并重译”分流、既有 Store correction 参数、图片 task／revision、v3.30–v3.35 的关闭后焦点交接和忽略／恢复路径均未改变。没有新增 Store、持久化、Vision OCR、模型、renderer/export、漫画探针、Koharu、ground truth、metrics 或 `output/` 行为。
- 新增 `scripts/test-v339-image-ocr-correction-scroll-dismiss-contract.py`（4 项）并接入图片/UI fail-fast，锁定 `Form` 的滚动收起顺序、v3.38 既有显式收起入口、View-only 边界和 CI 路由。

验证与遗留：

- 本地轻量检查通过：v3.39 合同 `4/4`，v3.38 `4/4`、v3.37 `5/5`、v3.24 `6/6`、v3.25 `5/5`、v3.30／v3.33／v3.35 焦点回归合同、v1.87 UI 合同 `12/12`、v1.94 CI 分层 `10/10`、v1.97 版本身份 `5/5`、`xcrun swiftc -parse AITRANS/Views/ImageTranslationViews.swift`、workflow YAML、版本解析 `v3.39` 与 `git diff --check`。源码合同不能替代真实滚动手势、第三方输入法、VoiceOver 或紧凑布局回放。
- 候选 SHA `2bc3a0addd1293e88f0142b6657ef0490c99a769` 的 full run `30599440729` 成功，`AITRANS CI/full-validation` status 为 success；未加密 artifact `aitrans-ci-v3.39-codeb-v3.39-image-correction-scroll-dismiss--2bc3a0addd12-run30599440729-attempt1` 的 version、branch、commitSha、runId、runAttempt、workflowName、`validationProfile=full`、`validationReason=candidate_development_push` 均精确匹配。`xcodeBuildRequired=true`，`.xcresult` Build 为 succeeded、0 errors、0 warnings；JUnit `10/10`、0 failures；图片/UI、Speech、首页、粘贴与扩展 Koharu validator fixture 矩阵均通过，新 v3.39 合同 `4/4`。
- PR #103 fast `30599720090` 成功，精确记录 `reusedFullValidationSha=2bc3a0addd1293e88f0142b6657ef0490c99a769` 与 `reusedFullValidationState=success`，并写明 `xcodeBuildRequired=false`、`fast_followup_reuses_candidate_full_validation`。合并后 fast `30599823729` 成功，精确匹配 merge SHA，`validationReason=merge_reuses_successful_candidate_full_validation`，`receiptPropagationAllowed=true`，复用同一候选 full receipt；两者均只作路由跟踪，不替代候选 full 的 Swift/Xcode 编译证据。
- 未跑本机 build / 探针，按规则交给云端验证。候选 full 使用 `probe_mode=skip`，UI evidence 为 `not_requested`，未生成新的漫画探针数字、`output/` 报告或 `metrics/version_history.csv` 行。真实 Koharu 四件套、Speech corpus 与真实竖排图片 corpus 仍缺失；active Koharu validator 仍为 `manifestMissing / stopUntilArtifactsProvided`，本版不声称 OCR、翻译、识别或 Koharu 质量提升。真实滚动、第三方输入法和 VoiceOver 行为仍需在设备／模拟器手工回放。

## v3.38：OCR 修正输入的键盘收起操作
日期：2026-07-31

状态：Agent X 已完成实现、云端验收和合并收口；工程正式版本为 `MARKETING_VERSION=3.38`。PR #102 已合入 `smalldata_test`，merge SHA `40340ae71cf46271aaef5c130e8fd21bc3e799e7`；远端 `codeb/v3.38-image-correction-keyboard` 已删除，未触碰 `main`。

核心变更：

- 审查发现普通图片 OCR 修正 sheet 的多行 `TextField` 没有与文本页一致的键盘“完成”动作。软件键盘打开后，页面没有在键盘附件中提供明确的收起入口，且打开忽略确认或保存时 sheet 不会明确清除输入焦点。
- `ImageOCRCorrectionSheet` 新增 View 私有 `@FocusState correctedOriginalFocused` 并绑定既有多行输入；keyboard toolbar 现在提供可访问的“完成 OCR 原文输入并收起键盘”。取消、打开“忽略此文字块”确认及保存前均复用 `dismissKeyboard()` 清焦点，确保确认／保存后的操作层不被软件键盘遮挡。
- 文本、业务和关闭语义保持不变：v3.37 的 `normalizedCorrectedOriginal` 仍是唯一 Store-equivalent 输入，v3.24 的语义修改弃改保护、v3.25 的“确认无误／保存并重译”分流、只重译当前 block、v3.30–v3.35 revision-scoped sheet 关闭后焦点交接及既有忽略／恢复路径都没有修改。没有新增 Store、持久化、Vision OCR、模型、renderer/export、漫画探针、Koharu、ground truth、metrics 或 `output/` 行为。
- 新增 `scripts/test-v338-image-ocr-correction-keyboard-contract.py`（4 项）并接入图片/UI fail-fast，锁定 View 私有焦点、可访问键盘“完成”、取消／忽略确认／保存收起键盘，以及既有规范化／dirty 语义继续生效。

验证与遗留：

- 本地轻量检查通过：v3.38 合同 `4/4`，v3.37 `5/5`、v3.24 `6/6`、v3.25 `5/5`、v3.30–v3.36 焦点与修正回归合同、v1.87 UI 合同 `12/12`、v1.94 CI 分层 `10/10`、v1.97 版本身份 `5/5`、`xcrun swiftc -parse AITRANS/Views/ImageTranslationViews.swift`、workflow YAML、版本解析 `v3.38` 与 `git diff --check`。源码合同不能替代真实键盘附件、第三方输入法、VoiceOver、confirmationDialog 或 sheet 连续手势回放。
- 候选 SHA `b6d718566217951430868706d134ea2b1d7075ce` 的 full run `30598870227` 成功，`AITRANS CI/full-validation` status 为 success；未加密 artifact `aitrans-ci-v3.38-codeb-v3.38-image-correction-keyboard--b6d718566217-run30598870227-attempt1` 的 version、branch、commitSha、runId、runAttempt、workflowName、`validationProfile=full`、`validationReason=candidate_development_push` 均精确匹配。`xcodeBuildRequired=true`，`.xcresult` Build 为 succeeded、0 errors、0 warnings；JUnit `10/10`、0 failures；图片/UI、Speech、首页、粘贴与扩展 Koharu validator fixture 矩阵均通过，新 v3.38 合同 `4/4`。
- PR #102 fast `30599139079` 成功，精确记录 `reusedFullValidationSha=b6d718566217951430868706d134ea2b1d7075ce` 与 `reusedFullValidationState=success`，并写明 `xcodeBuildRequired=false`、`fast_followup_reuses_candidate_full_validation`。合并后 fast `30599180814` 成功，精确匹配 merge SHA，`validationReason=merge_reuses_successful_candidate_full_validation`，`receiptPropagationAllowed=true`，复用同一候选 full receipt；两者均只作路由跟踪，不替代候选 full 的 Swift/Xcode 编译证据。
- 未跑本机 build / 探针，按规则交给云端验证。候选 full 使用 `probe_mode=skip`，UI evidence 为 `not_requested`，未生成新的漫画探针数字、`output/` 报告或 `metrics/version_history.csv` 行。真实 Koharu 四件套、Speech corpus 与真实竖排图片 corpus 仍缺失；active Koharu validator 仍为 `manifestMissing / stopUntilArtifactsProvided`，本版不声称 OCR、翻译、识别或 Koharu 质量提升。

## v3.37：规范化无语义 OCR 修正的关闭体验
日期：2026-07-31

状态：Agent X 已完成实现、云端验收和合并收口；工程正式版本为 `MARKETING_VERSION=3.37`。PR #101 已合入 `smalldata_test`，merge SHA `7bf0fc3fe9a83df7c8bd3c7981e2600ddc3b91d8`；远端 `codeb/v3.37-image-correction-normalized-dismissal` 已删除，未触碰 `main`。

核心变更：

- 审查图片 OCR 修正 sheet 时发现 UI 的三个语义并不一致：Store 已先 `trim` 再判定“无需重译”，`requiresRetranslation` 也做了 trim，但 `hasUnsavedChanges` 用原始字符串比较。因此只增加首尾空白时，保存动作显示“确认无误”，却仍会禁用下滑关闭并要求 destructive “放弃修正”。
- `ImageOCRCorrectionSheet` 新增 View 私有 `normalizedCorrectedOriginal`，并让 `canSave`、`hasUnsavedChanges`、`requiresRetranslation` 和交给既有 `correctImageTranslationBlock` 的参数全部复用它。trim 后仍等于当前原文的输入现在是 clean：可以直接取消／交互式关闭，确认无误走 Store 既有 no-op 分支，不启动模型翻译。
- 真正改变文字的路径不变：空文本仍不能保存；未保存的语义修改仍显示 v3.24 放弃确认并阻止交互式关闭；保存只重译目标 block；v3.25 的“保存并重译／确认无误”文案、v3.30–v3.35 的 revision-scoped 关闭后焦点交接、成功／忽略的既有目标仍保留。
- 更新 v3.24 / v3.25 合同以锁定同一规范化来源，新增 `scripts/test-v337-image-ocr-correction-normalized-dismissal-contract.py`（5 项）并接入图片/UI fail-fast。没有新增 Store、持久化、Vision OCR、模型、renderer/export、漫画探针、Koharu、ground truth、metrics 或 `output/` 状态。

验证与遗留：

- 本地轻量检查通过：v3.37 合同 `5/5`，v3.24 `6/6`、v3.25 `5/5`、v3.30–v3.36 回归合同，v1.87 UI 合同 `12/12`、v3.00 / v3.10 图片合同、v1.94 CI 分层 `10/10`、v1.97 版本身份 `5/5`、`xcrun swiftc -parse AITRANS/Views/ImageTranslationViews.swift`、workflow YAML、版本解析 `v3.37`、ground truth / 既有 output JSON smoke 与 `git diff --check`。源码合同不能替代真实键盘、VoiceOver、输入法、sheet 下滑或连续手势回放。
- 候选 SHA `7c6c538cb7e831a5a97602a1de1576c16eeb4b8e` 的 full run `30597966890` 成功，`AITRANS CI/full-validation` status 为 success；未加密 artifact `aitrans-ci-v3.37-codeb-v3.37-image-correction-normalized-dismissal--7c6c538cb7e8-run30597966890-attempt1` 的 version、branch、commitSha、runId、runAttempt、workflowName、`validationProfile=full`、`validationReason=candidate_development_push` 均精确匹配。`xcodeBuildRequired=true`，`.xcresult` Build 为 succeeded、0 errors、0 warnings；JUnit `10/10`、0 failures；新 v3.37 合同 `5/5` 和全套图片/UI、Speech、首页、粘贴与扩展 Koharu validator fixture 矩阵均通过。
- PR #101 fast `30598319928` 成功，精确记录 `reusedFullValidationSha=7c6c538cb7e831a5a97602a1de1576c16eeb4b8e` 与 `reusedFullValidationState=success`，并写明 `xcodeBuildRequired=false`、`fast_followup_reuses_candidate_full_validation`。合并后 fast `30598383448` 成功，精确匹配 merge SHA，`validationReason=merge_reuses_successful_candidate_full_validation`，`receiptPropagationAllowed=true`，复用同一候选 full receipt；两者均只作路由跟踪，不替代候选 full 的 Swift/Xcode 编译证据。
- 未跑本机 build / 探针，按规则交给云端验证。候选 full 使用 `probe_mode=skip`，UI evidence 为 `not_requested`，未生成新的漫画探针数字、`output/` 报告或 `metrics/version_history.csv` 行。真实 Koharu 四件套、Speech corpus 与真实竖排图片 corpus 仍缺失；active Koharu validator 仍为 `manifestMissing / stopUntilArtifactsProvided`，本版不声称 OCR、翻译、识别或 Koharu 质量提升。

## v3.36：开发控制台 Koharu 工件就绪摘要
日期：2026-07-31

状态：Agent X 已完成实现、云端验收和合并收口；工程正式版本为 `MARKETING_VERSION=3.36`。PR #100 已合入 `smalldata_test`，merge SHA `b2e93fd9d22dfbc1f93cbab1372e75dac8eb433a`；远端 `codeb/v3.36-koharu-readiness-summary` 已删除，未触碰 `main`。

核心变更：

- 审查发现开发控制台原先只汇总漫画探针的 block、engine 与 warnings；尽管报告已计算真实 Koharu artifact 的 readiness、缺件和 `nextAction`，开发者仍要导出 JSON 才能判断该给工件提供方什么信息。
- `MangaProbeSection` 在既有 `mangaOverlayProbeReport` 存在且其中带有 `externalArtifactReadinessReport` 时，新增 View 私有 `MangaKoharuArtifactReadinessSummary`。它只消费报告，不创建 Store／probe state、不运行新 probe、不读取或写入 `test/koharu_artifacts/`，也不改变普通图片 OCR、模型翻译、renderer/export、覆盖图、`blockPassed`、`currentBlockSource`、ground truth、metrics 或 `output/`。
- 摘要以可访问 `AppStatusRow` 明确区分 `readyForShadowOCR && externalTextBoxesShadowOCRAllowed` 的“真实 Koharu 工件已就绪（仅 shadow OCR）”、`manifestMissing` / `artifactFilesMissing` 的“等待真实 Koharu 四件套”，以及其他无效状态的“需要修正”；中文 next step 覆盖提供四件套、修正契约／坐标／身份、声明真实 detector / segmenter 来源，或继续 external TextBoxes shadow OCR 诊断。
- 既有可复制／分享的 `DeveloperCodeBlock` 展示 source、verdict、nextAction、active directory、fixture 标记、shadow gate、四件套 presence、missing artifacts、parse errors、generatedBy、TextBox / Bubble / glyph 计数、notes 与显式 `shadowOnly=true` / `mainFlowChanged=false`。它使真实 artifact 协作更直接，但 readiness 本身不是 shadow OCR coverage、App 主路径消费、真机 UI 或 OCR/翻译质量证据。
- 新增 `scripts/test-v336-koharu-readiness-developer-summary-contract.py`（6 项）并接到图片/UI fail-fast 路由；Koharu workflow 变更仍在候选 full 中跑扩展 validator fixture 矩阵。

验证与遗留：

- 本地轻量检查通过：v3.36 合同 `6/6`、v3.35 合同 `6/6`、v1.94 CI 分层合同 `10/10`、v1.97 版本身份合同 `5/5`、`xcrun swiftc -parse AITRANS/Views/DeveloperConsoleView.swift`、workflow YAML、版本解析 `v3.36` 与 `git diff --check`。这些源码／静态检查不替代实际 artifact、shadow OCR coverage 或真机渲染。
- 候选 SHA `646f5b9d6c8094c598bdcc37f3b4cd8f6dcc05e5` 的 full run `30596936426` 成功，`AITRANS CI/full-validation` status 为 success；未加密 artifact `aitrans-ci-v3.36-codeb-v3.36-koharu-readiness-summary--646f5b9d6c80-run30596936426-attempt1` 的 version、branch、commitSha、runId、runAttempt、workflowName、`validationProfile=full`、`validationReason=candidate_development_push` 均精确匹配。`xcodeBuildRequired=true`，`.xcresult` Build 为 succeeded、0 errors、0 warnings；JUnit `10/10`、0 failures；v3.36 UI 合同、相关静态合同和 Koharu 扩展 validator fixture 矩阵均通过。active Koharu validator 按当前真实状态报告 `manifestMissing`、四件套均缺、`externalTextBoxesShadowOCRAllowed=false`、`nextAction=stopUntilArtifactsProvided`。
- PR #100 fast `30597239074` 成功，精确记录 `reusedFullValidationSha=646f5b9d6c8094c598bdcc37f3b4cd8f6dcc05e5` 与 `reusedFullValidationState=success`，并写明 `xcodeBuildRequired=false`、`fast_followup_reuses_candidate_full_validation`。合并后 fast `30597283805` 成功，精确匹配 merge SHA，`validationReason=merge_reuses_successful_candidate_full_validation`，`receiptPropagationAllowed=true`，复用同一候选 full receipt；两者均只作路由跟踪，不替代候选 full 的 Swift/Xcode 编译证据。
- 未跑本机 build / 探针，按规则交给云端验证。候选 full 使用 `probe_mode=skip`，UI evidence 为 `not_requested`，未生成新的漫画探针数字、`output/` 报告或 `metrics/version_history.csv` 行。真实 Koharu 四件套、Speech corpus 与真实竖排图片 corpus 仍缺失；本版不声称 OCR、翻译、识别或 Koharu 质量提升，真实 artifact 注入后仍须手动 `ci-fast` / `full` 验收 identity、shadow OCR coverage、orientation 与 mask topology gates。

## v3.35：局部 OCR 修正后的原位焦点返回
日期：2026-07-31

状态：Agent X 已完成实现、云端验收和合并收口；工程正式版本为 `MARKETING_VERSION=3.35`。PR #99 已合入 `smalldata_test`，merge SHA `f85edddd2582f4de70767da9838155721211a9a4`；远端 `codeb/v3.35-image-focus-preview-return` 已删除，未触碰 `main`。

核心变更：

- 审查 v3.34 的局部 OCR 修正入口后发现，取消、放弃未保存修正或无修改关闭虽然安全地等待 sheet 完整关闭，却统一把焦点带回结果行，丢失了用户从局部预览发起编辑的上下文。
- `ImageTranslationPanel` 新增 View 私有 `beginCorrectionFromFocusPreview(of:)`。它与结果行 `beginCorrection(of:)` 共享 `!isRunning`、`!isRenderingExport` 和当前活动 block guard，却在呈现既有 sheet 前登记 `reviewPreviewAccessibilityFocusID(block.id)`；结果行入口保持登记 `reviewRowAccessibilityFocusID(block.id)`。
- 非成功关闭仍只通过既有 revision-checked `sheet(item:onDismiss:)` 发布 fallback；成功修正、确认无误或忽略继续在 sheet 关闭前覆盖为既有下一块、完成态或忽略行目标，图片 revision 改变继续清空 sheet、pending 与已发布焦点。本版不改 Store、Vision OCR、模型翻译、renderer/export、漫画探针、Koharu 主路径、ground truth、metrics 或 `output/`。
- 新增 v3.35 图片/UI 源码合同并接入 CI 路由；v3.34 合同同步改为只锁定局部入口、共享 guard 与 View 私有转交，不再把已过时的结果行 fallback 当作局部入口行为。源码合同验证所有权与静态路径，不声称 OCR、翻译、识别或 Koharu 质量提升。

验证与遗留：

- 本地轻量检查通过：v3.30-v3.35 图片/UI 合同分别为 6/6、5/5、6/6、6/6、6/6、6/6（共 35 项），v1.94 CI 分层合同 10/10、v1.97 版本身份合同 5/5、`git diff --check`、`xcrun swiftc -parse AITRANS/Views/ImageTranslationViews.swift`、workflow YAML 与 ground truth / 既有 output JSON smoke。
- 候选 SHA `f9bd49206fbe9f97f6f5b988c6abdaf8d8fcf34f` 的 full run `30595866325` 成功，`AITRANS CI/full-validation` status 为 success；未加密 artifact `aitrans-ci-v3.35-codeb-v3.35-image-focus-preview-return--f9bd49206fbe-run30595866325-attempt1` 的 version、branch、commitSha、runId、runAttempt、workflowName、`validationProfile=full` 和 `validationReason=candidate_development_push` 均精确匹配。`.xcresult` Build 为 succeeded、0 errors、0 warnings；JUnit `10/10`、0 failures；图片/UI 合同（含 v3.35）与所需静态、Speech、首页、粘贴和 Koharu contract 均通过。
- PR #99 fast `30596172257` 成功，精确记录 `reusedFullValidationSha=f9bd49206fbe9f97f6f5b988c6abdaf8d8fcf34f` 与 `reusedFullValidationState=success`；合并后 fast `30596224218` 成功，精确匹配 merge SHA，`validationReason=merge_reuses_successful_candidate_full_validation`，以 `receiptPropagationAllowed=true` 传播候选 successful receipt。两者均只作路由跟踪，不替代候选 full 的 Swift/Xcode 编译证据。
- 未跑本机 build / 探针，按规则交给云端验证。候选 full 使用 `probe_mode=skip`，UI evidence 为 `not_requested`，未生成新的漫画探针指标或 `metrics/version_history.csv` 行。真实 Koharu 四件套、Speech corpus 与真实竖排图片 corpus 仍缺失；full artifact 的 active Koharu gate 为 `manifestMissing / stopUntilArtifactsProvided`。源码合同不能替代真机／模拟器的实际 VoiceOver、局部窗紧凑布局或连续手势回放。

## v3.34：局部 OCR 放大窗直接修正
日期：2026-07-31

状态：Agent X 已完成实现、云端验收和合并收口；工程正式版本为 `MARKETING_VERSION=3.34`。PR #98 已合入 `smalldata_test`，merge SHA `df94d695c42786fae2defbaf05b9f2e7b42abd77`；远端 `codeb/v3.34-image-focus-preview-correction` 已删除，未触碰 `main`。

核心变更：

- 审查发现局部放大窗虽已有关闭、前后切换和风险复查，却没有直接进入 OCR 修正的入口；在窄 iPhone 布局中，用户必须离开图片工作区或滚到结果行才能编辑当前框。
- `ImageTranslationPreview` 现将当前完整活动 block 和既有修正回调交给 `ImageTranslationFocusPreview`。局部窗在关闭按钮下提供命名明确、可访问的 44pt “修正识别文字”铅笔入口；它与结果行共享 `!isRunning && !isRenderingExport` gate。
- `beginCorrection` 先拒绝忙碌或已从当前活动集合移除的 block，再设置选择、登记 v3.33 的 View 私有 revision-scoped 结果行关闭回退并呈现原有 sheet。局部入口不直接调用 Store correction、Vision OCR、翻译、renderer/export 或持久化；取消、放弃未保存修正或无修改关闭仍在 sheet 完全关闭后回到结果行，而非伪造新的局部窗焦点目的地。
- 新增 v3.34 源码合同并接入图片/UI fail-fast CI 路由，锁定入口位置与 44pt 语义、同一 availability gate、当前 block 转交、stale/busy 拒收、既有 sheet/onDismiss 复用和 CI 顺序。本版不改 ground truth、metrics 或 `output/`，不能声称 OCR、翻译、识别或 Koharu 质量提升。

验证与遗留：

- 本地通过 40 个与 CI 同组的图片/UI 合同（含 v3.34 6/6 和既有回归）、v1.94 CI 分层合同 10/10、v1.97 版本身份合同 5/5、`git diff --check`、`xcrun swiftc -parse`、YAML / ground truth 与既有 output JSON smoke，以及版本解析 `v3.34`。
- 候选 SHA `8ec3ec25767808ec3555b2ab4a0841a2b21b0a6e` 的 full run `30555909210` 成功，`AITRANS CI/full-validation` status 为 success；未加密 artifact `aitrans-ci-v3.34-codeb-v3.34-image-focus-preview-correction--8ec3ec257678-run30555909210-attempt1` 的 version、branch、commitSha、runId、runAttempt、workflowName、`validationProfile=full` 和 `validationReason=candidate_development_push` 均精确匹配。`.xcresult` Build 为 succeeded、0 errors、0 warnings；JUnit `10/10`、0 failures；静态、Speech、图片/UI（含 v3.34）、首页、粘贴和 Koharu contract 均通过。
- PR #98 fast `30595179924` 成功，明确 `xcodeBuildRequired=false`，精确记录 `reusedFullValidationSha=8ec3ec25767808ec3555b2ab4a0841a2b21b0a6e` 和 `reusedFullValidationState=success`。合并后 fast `30595245334` 成功，精确匹配 merge SHA，`validationReason=merge_reuses_successful_candidate_full_validation`，并以 `receiptPropagationAllowed=true` 将同一 successful receipt 传播到 merge SHA；两者均只作路由跟踪，不替代候选 full 的 Swift/Xcode 编译证据。
- 未跑本机 build / 探针，按规则交给云端验证。候选 full 使用 `probe_mode=skip`，UI evidence 为 `not_requested`，未生成新的漫画探针指标或 `metrics/version_history.csv` 行。真实 Koharu 四件套、Speech corpus 与真实竖排图片 corpus 仍缺失；full artifact 的 active Koharu gate 为 `manifestMissing / stopUntilArtifactsProvided`。源码合同不能替代真机／模拟器的实际 VoiceOver、局部窗紧凑布局或连续手势回放。

## v3.33：OCR 修正取消后的结果行焦点回退
日期：2026-07-30

状态：Agent X 已完成实现、云端验收和合并收口；工程正式版本为 `MARKETING_VERSION=3.33`。PR #97 已合入 `smalldata_test`，merge SHA `ec9af4a69a8ce78bf398a50a906664602aed2f3f`；远端 `codeb/v3.33-image-ocr-correction-cancel-focus` 已删除，未触碰 `main`。

核心变更：

- 审查发现 v3.30/v3.31 只为保存、确认无误和忽略等成功路径安排 sheet 关闭后的 VoiceOver 目的地；直接取消、放弃未保存修正或无修改时的交互式关闭没有确定回退，可能丢失当前 OCR block 上下文。
- `beginCorrection` 现在在呈现 `ImageOCRCorrectionSheet` 前，只在 `ImageTranslationPanel` 的 View 私有、revision-scoped pending state 登记发起 block 的结果行。非成功关闭沿既有 `sheet(item:onDismiss:)` 在 revision 一致时才发布它；保存／确认无误和忽略会在关闭前覆盖为既有下一块、完成态或忽略行目的地。新图片仍清空 sheet、pending 与已发布焦点；不改 Store、持久化、Vision OCR、模型翻译、renderer/export、漫画探针或 Koharu 路径。
- 新增 v3.33 合同并接入图片/UI fail-fast CI 路由，锁定回退登记先于 sheet item、关闭后发布、取消／放弃／无修改交互式关闭、成功路径覆盖与 revision 清理。本版不改 ground truth、metrics 或 `output/`，不能声称 OCR、翻译或识别质量提升。

验证与遗留：

- 本地通过 39 个与 CI 同组的图片/UI 合同（含 v3.33 6/6 和既有回归）、v1.94 CI 分层合同 10/10、v1.97 版本身份合同 5/5、`git diff --check`、`xcrun swiftc -parse`、YAML / ground truth 与既有 output JSON smoke，以及版本解析 `v3.33`。
- 候选 SHA `bdbaccb62389d4f900698014ec95b1e36a9267dc` 的 full run `30554084348` 成功，`AITRANS CI/full-validation` status 为 success；未加密 artifact `aitrans-ci-v3.33-codeb-v3.33-image-ocr-correction-cancel-focus--bdbaccb62389-run30554084348-attempt1` 的 version、branch、commitSha、runId、runAttempt、workflowName、`validationProfile=full` 和 `validationReason=candidate_development_push` 均精确匹配。`.xcresult` Build 为 succeeded、0 errors、0 warnings；JUnit `10/10`、0 failures；静态、Speech、图片/UI（含 v3.33）、首页、粘贴和 Koharu contract 均通过。
- PR #97 fast `30554790309` 成功，明确 `xcodeBuildRequired=false`，精确记录 `reusedFullValidationSha=bdbaccb62389d4f900698014ec95b1e36a9267dc` 和 `reusedFullValidationState=success`。合并后 fast `30554893227` 成功，精确匹配 merge SHA，`validationReason=merge_reuses_successful_candidate_full_validation`，并以 `receiptPropagationAllowed=true` 将同一 successful receipt 传播到 merge SHA；两者均只作路由跟踪，不替代候选 full 的 Swift/Xcode 编译证据。
- 未跑本机 build / 探针，按规则交给云端验证。候选 full 使用 `probe_mode=skip`，未生成新的漫画探针指标或 `metrics/version_history.csv` 行。真实 Koharu 四件套、Speech corpus 与真实竖排图片 corpus 仍缺失；full artifact 的 active Koharu gate 为 `manifestMissing / stopUntilArtifactsProvided`。源码合同不能替代真实 VoiceOver 取消、放弃修改或下滑关闭的设备／模拟器回放。

## v3.32：恢复 Vision OCR 确认后的焦点交接
日期：2026-07-30

状态：Agent X 已完成实现、云端验收和合并收口；工程正式版本为 `MARKETING_VERSION=3.32`。PR #96 已合入 `smalldata_test`，merge SHA `c306e7796159b799dd86e5123fd8df0ddbaf4ca0`；远端 `codeb/v3.32-image-ocr-restore-focus-handoff` 已删除，未触碰 `main`。

核心变更：

- 审查发现已人工修正 block 的“恢复 Vision OCR”确认动作会在 `confirmationDialog` 仍处于关闭动画时直接安排结果行 VoiceOver 焦点，和 v3.30 的 sheet 关闭交接相比缺少确定的呈现生命周期边界。
- 恢复成功后，`ImageTranslationPanel` 现在只在 View 私有 state 暂存结果行 focus ID 与当前 `imageTranslationRevision`；确认 target 保留到 `isPresented` binding 收到关闭回写。binding 先清理 target，只有 revision 仍一致才复用既有 yield 后焦点发布器；取消无 pending 目标，新图清空 confirmation/pending/已发布焦点。既有 Store 恢复、基线、transcript、export/share 与 render 生命周期保持不变。
- 新增 v3.32 合同，更新 v3.22/v3.23 合同以锁定恢复所有权、destructive confirmation 和关闭后交接的共同边界，并接入图片/UI fail-fast CI 路由。本版不改 Vision OCR、模型翻译、renderer/export、漫画探针、Koharu、ground truth、metrics 或 `output/`，不能声称 OCR、翻译或识别质量提升。

验证与遗留：

- 候选 SHA `9d257c114cf425f40288189e04985afc2c824f2a` 的 full run `30551770338` 成功，`AITRANS CI/full-validation` status 为 success；未加密 artifact `aitrans-ci-v3.32-codeb-v3.32-image-ocr-restore-focus-handoff--9d257c114cf4-run30551770338-attempt1` 的 version、branch、commitSha、runId、runAttempt、workflowName、`validationProfile=full` 和 `validationReason=candidate_development_push` 均精确匹配。`.xcresult` Build 为 succeeded、0 errors、0 warnings；JUnit `10/10`、0 failures，静态、Speech、图片/UI（含 v3.32）、首页、粘贴与 Koharu contract 均通过。
- PR #96 fast `30552790644` 成功，明确 `xcodeBuildRequired=false`，精确记录 `reusedFullValidationSha=9d257c114cf425f40288189e04985afc2c824f2a` 和 `reusedFullValidationState=success`。合并后 fast `30552912602` 成功，精确匹配 merge SHA，`validationReason=merge_reuses_successful_candidate_full_validation`，并以 `receiptPropagationAllowed=true` 将同一 successful receipt 传播到 merge SHA；两者均只作路由跟踪，不替代候选 full 的 Swift/Xcode 编译证据。
- 本地通过 39 个与 CI 同组的图片/UI 合同（含 v3.32 6/6 与 v3.22/v3.23 回归）、v1.94 CI 分层合同、v1.97 版本身份合同、`git diff --check`、`xcrun swiftc -parse`、YAML / plist / ground truth 与既有 output JSON smoke，以及版本解析 `v3.32`。未跑本机 build / 探针，按规则交给云端验证；候选 full 使用 `probe_mode=skip`，未生成新的漫画探针指标或 `metrics/version_history.csv` 行。
- 真实 Koharu 四件套、Speech corpus 与真实竖排图片 corpus 仍缺失；full artifact 的 active Koharu gate 为 `manifestMissing / stopUntilArtifactsProvided`。源码合同不能替代真实 VoiceOver 关闭动画、连续扫动或快速确认的设备／模拟器回放。

## v3.31：OCR 修正成功后的结果行返回焦点
日期：2026-07-30

状态：Agent X 已完成实现、云端验收与合并收口；工程正式版本为 `MARKETING_VERSION=3.31`。PR #95 已合入 `smalldata_test`，merge SHA `34a1dd555ca9772a2ffbd758055060d68f96e396`；远端 `codeb/v3.31-image-ocr-correction-return-focus` 已删除，未触碰 `main`。

核心变更：

- 审查发现 v3.30 只为“待复查”筛选内的成功修正安排关闭后的下一行／完成态；非风险 block 与“全部”筛选下的风险 block 成功“确认无误／保存并重译”后没有明确的 VoiceOver 返回目的地。
- `completeReviewAfterCorrection` 现在先确认目标 block 仍在当前活动集合。只有筛选仍为“待复查”、block 仍属风险集合且 Store 已标为已复查时才前进既有队列；所有其他成功修正保持当前选择，并通过既有 View 私有、revision-checked 的 sheet `onDismiss` handoff 回到已更新结果行。
- 新增 v3.31 源码合同并接入图片/UI fail-fast CI 路由，锁定分流、失效 block 拒收、复用 v3.30 handoff 与 Store 边界。本版不改 Store、持久化、Vision OCR、模型翻译、renderer/export、漫画探针、Koharu、ground truth、metrics 或 `output/`，不能声称 OCR、翻译或识别质量提升。

验证与遗留：

- 本地已通过 38 个与 CI 同组的图片/UI 合同（含新 v3.31 合同 5/5 与 v3.20/v3.21/v3.29/v3.30 回归）、v1.94 CI 分层合同、v1.97 版本身份合同、`git diff --check`、`xcrun swiftc -parse`、YAML / 工程实际 plist / ground truth 与既有 output JSON smoke，以及版本解析。
- 候选 SHA `e22d35e58c16ea8e21d253941bd89aa76e1a4deb` 的 full run `30549781618` 成功，`AITRANS CI/full-validation` status 为 success；未加密 artifact `aitrans-ci-v3.31-codeb-v3.31-image-ocr-correction-return-focus--e22d35e58c16-run30549781618-attempt1` 精确匹配 version、branch、commitSha、runId、runAttempt 和 workflowName，`validationProfile=full`、`validationReason=candidate_development_push`、`xcodeBuildRequired=true`。`.xcresult` Build 为 succeeded，0 errors、0 warnings；JUnit `10/10`、0 failures/errors；静态、Speech、图片/UI（含 v3.31）、首页、粘贴和 Koharu contract 均成功。
- PR #95 fast `30550329514` 与 merge fast `30550436541` 均成功；后者精确匹配 merge SHA、`validationReason=merge_reuses_successful_candidate_full_validation`、`reusedFullValidationSha=e22d35e5... / success`，并以 `receiptPropagationAllowed=true` 将 `AITRANS CI/full-validation=success` 传播到 `34a1dd55...`。两者均只作路由追踪，不能替代候选 full 的 Swift/Xcode 编译证据。
- 未跑本机 build / 探针，按规则交给云端验证。候选 full 使用 `probe_mode=skip`，未生成新的漫画探针指标或 `metrics/version_history.csv` 行。
- 真实 Koharu 四件套、Speech corpus 和真实竖排图片 corpus 仍缺失；full artifact 的 active Koharu gate 为 `manifestMissing / stopUntilArtifactsProvided`，本版不改变这些受限路径。

## v3.30：OCR 修正 sheet 关闭后的确定性焦点交接
日期：2026-07-30

状态：Agent X 已完成实现、云端验收与合并收口；工程正式版本为 `MARKETING_VERSION=3.30`。PR #94 已合入 `smalldata_test`，merge SHA `408d45b3300ae469a1fc4a2ebdc33da24cba62e1`；远端 `codeb/v3.30-image-ocr-focus-handoff` 已删除，未触碰 `main`。

核心变更：

- `ImageTranslationPanel` 在 OCR 修正 sheet 的成功忽略时保留既有“下一活动／待复查行，否则已忽略行”焦点目标；待复查队列中的成功修正保留既有“下一行／完成态”目标。两者不再在 sheet 遮罩仍存在时直接发布 VoiceOver 焦点。
- pending handoff 仅是 View 私有 `@State`：同时保存目标 focus ID 和 `imageTranslationRevision`；sheet `onDismiss` 后只有 revision 仍一致才清空 pending 并复用已有 `moveReviewAccessibilityFocus`。图片切换会清空 sheet、pending 与当前已发布焦点，旧图片不能抢回焦点。
- 新增 v3.30 源码合同并接入图片/UI fail-fast CI 路由，锁定 View 私有边界、onDismiss 接线、原有焦点目的地、revision 校验和新图清理。本版不改 Store、持久化、Vision OCR、模型翻译、renderer/export、漫画探针、Koharu、ground truth、metrics 或 `output/`，不能声称 OCR、翻译或识别质量提升。

验证与遗留：

- 本地已通过 37 个与 CI 同组的图片/UI 合同（含新 v3.30 合同 6/6 与 v3.20/v3.21/v3.29 回归）、v1.94 CI 分层合同、v1.97 版本身份合同、`git diff --check`、`xcrun swiftc -parse`、YAML / 工程实际 plist / ground truth 与既有 output JSON smoke，以及版本解析。
- 候选 SHA `b73b1383f3942548caf0e0ad3e167abe9552ac6c` 的 full run `30547927321` 成功，`AITRANS CI/full-validation` status 为 success；未加密 artifact `aitrans-ci-v3.30-codeb-v3.30-image-ocr-focus-handoff--b73b1383f394-run30547927321-attempt1` 精确匹配 version、branch、commitSha、runId、runAttempt 和 workflowName，`validationProfile=full`、`validationReason=candidate_development_push`、`xcodeBuildRequired=true`。`.xcresult` Build 为 succeeded，0 errors、0 warnings；JUnit `10/10`、0 failures/errors；静态、Speech、图片/UI（含 v3.30）、首页、粘贴和 Koharu contract 均成功。
- PR #94 fast `30548623007` 与 merge fast `30548739625` 均成功；后者精确匹配 merge SHA、`validationReason=merge_reuses_successful_candidate_full_validation`、`reusedFullValidationSha=b73b1383... / success`，并以 `receiptPropagationAllowed=true` 将 `AITRANS CI/full-validation=success` 传播到 `408d45b3...`。两者均只作路由追踪，不能替代候选 full 的 Swift/Xcode 编译证据。
- 未跑本机 build / 探针，按规则交给云端验证。候选 full 使用 `probe_mode=skip`，未生成新的漫画探针指标或 `metrics/version_history.csv` 行。
- 真实 Koharu 四件套、Speech corpus 与真实竖排图片 corpus 仍缺失；本候选没有改变这些受限路径。

## v3.29：可恢复的 OCR 误识别文字块忽略
日期：2026-07-30

状态：Agent X 已完成实现、云端验收和合并收口；工程正式版本为 `MARKETING_VERSION=3.29`。PR #93 已合入 `smalldata_test`，merge SHA `e1c84fd8649e121d7f146012cce0f83db574d4c0`；远端 `codeb/v3.29-image-ocr-false-positive-dismissal` 已删除，未触碰 `main`。

核心变更：

- 图片 OCR 修正 sheet 新增“识别有误？”区段和明确 destructive confirmation。确认后只忽略当前 block：未保存的修正不会保存，用户可以从检查区“已忽略的文字块”列表恢复。该入口不会重新识别图片或调用模型翻译。
- `TranslationSessionStore` 现在为当前图片会话保存被忽略 block 的完整值、初始 OCR 顺序、人工修正状态和私有 Vision OCR 基线；忽略会从当前活动 blocks、预览、导出、当前图片 transcript、人工修正/复查集合及基线映射移除，恢复则按初始顺序插回并恢复修正基线。风险 block 恢复后不沿用旧“已复查”结论，重新进入待复查队列；View 只负责筛选、选择和 VoiceOver 焦点。
- 若用户忽略全部活动 block，既有 renderer 仍从当前图片安全发布原图 export，当前图片 transcript 行移除，避免保留失效导出或空白转录。新图和清空会丢弃忽略快照；它不进入持久化、Vision OCR、模型翻译、漫画探针或 Koharu artifact 路径。
- 新增 v3.29 源码合同并接入图片/UI fail-fast CI 路由，锁定状态门控、快照、原始排序恢复、transcript/export 同步、原图导出、确认文案、恢复入口与无障碍焦点。本版不改 OCR 算法、方向/layout、翻译采样、漫画探针、ground truth、metrics 或 `output/`，不能声称 OCR、翻译或识别质量提升。

验证与遗留：

- 本地已通过 36 个与 CI 同组的图片/UI 合同（含新 v3.29 合同 8/8 和既有 v3.21/v3.24/v3.25/v3.27/v3.28 回归）、v1.94 CI 分层合同、v1.97 版本身份合同、`git diff --check`、两个修改 Swift 文件的 `xcrun swiftc -parse`、YAML / 工程实际 plist / ground truth 与既有 output JSON smoke，以及版本解析。
- 候选 SHA `55cfbcf1cc5d616aab9cb22b240118d6db77c0ed` 的 full run `30546261144` 成功，`AITRANS CI/full-validation` status 为 success；未加密 artifact `aitrans-ci-v3.29-codeb-v3.29-image-ocr-false-positive-dismissal--55cfbcf1cc5d-run30546261144-attempt1` 精确匹配 version、branch、commitSha、runId、runAttempt 和 workflowName，`validationProfile=full`、`validationReason=candidate_development_push`、`xcodeBuildRequired=true`。`.xcresult` Build 为 succeeded，0 errors、0 warnings；JUnit `10/10`、0 failures/errors；静态、Speech、图片/UI、首页、粘贴和 Koharu 合同均成功。
- PR #93 fast `30546759442` 与 merge fast `30546839144` 均成功；后者精确匹配 merge SHA、`validationReason=merge_reuses_successful_candidate_full_validation`、`reusedFullValidationSha=55cfbcf1... / success`，并以 `receiptPropagationAllowed=true` 将 `AITRANS CI/full-validation=success` 传播到 `e1c84fd8...`。两者均只作路由追踪，不能替代候选 full 的 Swift/Xcode 编译证据。
- 未跑本机 build / 探针，按规则交给云端验证。候选 full 使用 `probe_mode=skip`，未生成新的漫画探针指标或 `metrics/version_history.csv` 行。真实 Koharu 四件套、Speech corpus 和真实竖排图片 corpus 仍缺失；不得把本次操作体验改进描述为质量提升。

## v3.28：图片复查会话连续性
日期：2026-07-30

状态：Agent X 已完成实现、云端验收和合并收口；工程正式版本为 `MARKETING_VERSION=3.28`。PR #92 已合入 `smalldata_test`，merge SHA `a7ae8dbc49642179e3f6b21e77846704f127a157`；远端 `codeb/v3.28-image-review-session-continuity` 已删除，未触碰 `main`。

核心变更：

- 原先只附着在 `ImageTranslationPanel` 的本次复查 ID 集合改由 `TranslationSessionStore` 的 `imageTranslationReviewedBlockIDs` 在内存中统一持有。这样当图片面板被 SwiftUI 重建时，已完成的风险块仍能继续复查；该集合不进入持久化，也不改变完整 OCR blocks。
- 新图 task、清空和取消会安全清空当前图片会话的复查集合。完成/撤销/重新开始复查均通过 Store 的风险范围 API；View 保留筛选、自动前进顺序、选择和 VoiceOver 焦点，不再直接改业务状态。
- 成功人工修正（包括原文未变的“确认无误”）会自动把风险 block 记为已复查；恢复 Vision OCR 会由 Store 移除该标记，避免把针对人工修正的复查结论错误带回原始 OCR。
- 新增 v3.28 源码合同，并更新 v3.17、v3.19、v3.21、v3.22 回归合同与图片/UI CI 路由。本版不改 Vision OCR、方向/layout、翻译采样、renderer、export、漫画探针或 Koharu artifact 路径。

验证与遗留：

- 本地已通过 35 个图片/UI 合同（含 v3.17、v3.19、v3.21、v3.22、v3.27 与新 v3.28）、`xcrun swiftc -parse` 两个修改 Swift 文件、CI 路由/版本合同、YAML / plist / JSON smoke 和 `git diff --check`。
- 候选 SHA `59e4fb6519f722943866bb576932ff6036c80e54` 的 full run `30526775311` 成功，`AITRANS CI/full-validation` status 为 success；未加密 artifact `aitrans-ci-v3.28-codeb-v3.28-image-review-session-continuity--59e4fb6519f7-run30526775311-attempt1` 精确匹配 version、branch、commitSha、runId、runAttempt 和 workflowName，`validationProfile=full`、`validationReason=candidate_development_push`、`xcodeBuildRequired=true`。`.xcresult` Build 为 succeeded，0 errors、0 warnings；JUnit `10/10`、0 failures/errors；静态、Speech、UI、首页、粘贴与 Koharu 合同均成功。
- PR #92 fast `30544627423` 与 merge fast `30544698475` 均成功；后者精确匹配 merge SHA、`validationReason=merge_reuses_successful_candidate_full_validation`、`reusedFullValidationSha=59e4fb65... / success`，并以 `receiptPropagationAllowed=true` 将 `AITRANS CI/full-validation=success` 传播到 `a7ae8dbc...`。两者均只作路由追踪，不能替代候选 full 的 Swift/Xcode 编译证据。
- 未跑本机 build / 探针，按规则交给云端验证。候选 full 使用 `probe_mode=skip`，未生成新的漫画探针指标或 `metrics/version_history.csv` 行。真实 Koharu 四件套、Speech corpus 和真实竖排图片 corpus 仍缺失，不能据本次会话连续性改进声称 OCR、翻译或识别质量提升。

## v3.27：OCR 修正局部对照与复查上下文
日期：2026-07-30

状态：Agent X 已完成实现、云端验收和合并收口；工程正式版本为 `MARKETING_VERSION=3.27`。PR #91 已合入 `smalldata_test`，merge SHA `a9111769917157f5f391565e68779230e6d6dbf4`；远端 `codeb/v3.27-image-ocr-correction-context` 已删除，未触碰 `main`。

核心变更：

- 普通图片 OCR 修正 sheet 现在接收当前图片 data，并通过既有 `ImagePreviewService` 生成最大边 2048px 的临时本地预览。它复用原有 16:9 局部裁切和黄色 bbox 几何，让用户在编辑 OCR 原文时能直接对照当前文字块；loading 或不可用时给出可读反馈，仍允许继续编辑。
- 低于 50% 置信度或方向待定的 block 会在 sheet 内复用 `ImageOCRResultSummary` 显示复查原因，明确“保存只会重新翻译当前文字块，不会重新识别整张图片”。该上下文不新增 Store / 持久化状态，不调用 Vision OCR，不改变单块 correction、transcript、export、renderer、漫画探针或 Koharu artifact 路径。
- 新增 v3.27 源码合同并接入图片/UI fail-fast 路由；共享局部裁切 helper 同时保留既有局部放大的 16:9、边界夹取和 bbox 再标记行为。

验证与遗留：

- 本地已通过 34 个图片/UI 源码合同（含 v3.27 6/6）、`xcrun swiftc -parse AITRANS/Views/ImageTranslationViews.swift`、YAML / plist / JSON smoke、v1.94 路由合同和 v1.97 版本身份合同。
- 候选 SHA `e70c8dc67b42a27d02ee4e48cbb9e9da19b0eeff` 的 full run `30525239987` 成功，`AITRANS CI/full-validation` status 为 success；未加密 artifact `aitrans-ci-v3.27-codeb-v3.27-image-ocr-correction-context--e70c8dc67b42-run30525239987-attempt1` 精确匹配 version、branch、commitSha、runId、runAttempt 和 workflowName，`validationProfile=full`、`validationReason=candidate_development_push`、`xcodeBuildRequired=true`。`.xcresult` Build 为 succeeded，0 errors、0 warnings；JUnit `10/10`、0 failures/errors；静态、Speech、UI、首页、粘贴和 Koharu 合同均成功。
- PR #91 fast `30525729028` 与 merge fast `30525808471` 均成功，后者精确匹配 merge SHA、`validationReason=merge_reuses_successful_candidate_full_validation`、`reusedFullValidationSha=e70c8dc... / success`，并以 `receiptPropagationAllowed=true` 将 `AITRANS CI/full-validation=success` 传播到 `a9111769...`；两者均只作路由追踪，不能替代候选 full 的 Swift/Xcode 编译证据。
- 未跑本机 build / 探针，按规则交给云端验证。候选 full 使用 `probe_mode=skip`，未生成新的漫画探针指标或 `metrics/version_history.csv` 行。真实 Koharu 四件套、Speech corpus 和真实竖排图片 corpus 仍缺失，不能据本次 UI 上下文改进声称 OCR、翻译或识别质量提升。

## v3.26：合并后 CI receipt 传播
日期：2026-07-30

状态：Agent X 已完成实现、云端验收和合并收口；工程正式版本为 `MARKETING_VERSION=3.26`。PR #90 已合入 `smalldata_test`，merge SHA `9047f276c3a63099e58de1dfedb8d07ff452d1fe`；远端 `codeb/v3.26-ci-merge-receipt-propagation` 已删除，未触碰 `main`。

核心变更：

- 成功候选 full receipt 在 `smalldata_test` merge fast 后会传播到 merge SHA；后续纯 README / AGENTS / update log / `md/` / metrics direct push 只在父 receipt 为 success 时走 fast，非元数据和未知/失败父 receipt 不得复用，且纯元数据不可信时强制当前头部 Xcode build。
- `ci-artifact-manifest.json` 与 failure summary 新增 `smalldataParentSha`、`smalldataParentFullValidationState`、`smalldataIncrementalMetadataOnly`、`smalldataMetadataRequiresFullValidation` 审计字段，结合既有 `reusedFullValidationSha/state` 和 `receiptPropagationAllowed` 区分传播 receipt 与新的编译证据。
- 扩展 v1.94 路由契约，锁定 merge 传播与 `smalldata_test` 纯元数据限制；本版只改 CI workflow、合同、版本和文档，不改变 App 业务、Vision OCR、翻译、导出、渲染、漫画探针、Koharu artifact 路径、ground truth、metrics 或 output。

验证与遗留：

- 候选 SHA `6e9b1ab4c79c9af3c297976bd54de712872e1677` 的 full run `30519929953` 成功，`AITRANS CI/full-validation` status 为 success，Xcode build 成功、JUnit `10/10`、0 failures；未加密 artifact 为 `aitrans-ci-v3.26-codeb-v3.26-ci-merge-receipt-propagation--6e9b1ab4c79c-run30519929953-attempt1`。artifact 的 version、branch、commitSha、runId、runAttempt、workflowName、`validationProfile=full`、`validationReason=candidate_development_push` 与候选一致，`.xcresult` 已上传；静态、Speech、UI、首页、粘贴和 Koharu 合同均成功。
- PR #90 的 fast follow-up `30520387081` 成功，明确 `xcodeBuildRequired=false`，并记录 `reusedFullValidationSha=6e9b1ab4c79c9af3c297976bd54de712872e1677`、`reusedFullValidationState=success`。合并后的 fast follow-up `30520484320` 成功，复用同一候选 full，并以 `receiptPropagationAllowed=true` 将 `AITRANS CI/full-validation=success` 传播到 merge SHA `9047f276c3a63099e58de1dfedb8d07ff452d1fe`；其 status 描述为 `Reused successful parent full validation`。两者均只作路由跟踪，不作为新的 Swift/Xcode 编译证据。
- v3.26 正式文档提交 `f8653809ca7c6e2e3f0e022abb293798136ac47a` 的 direct follow-up `30524346995` 成功，artifact 精确匹配 `v3.26 / smalldata_test / f8653809...`，并记录 `validationProfile=fast`、`validationReason=smalldata_metadata_followup_reuses_parent_full_validation`、父 SHA `9047f276... / success`、`smalldataIncrementalMetadataOnly=true`、`receiptPropagationAllowed=true`。该 SHA 同样获得 `Reused successful parent full validation` status；JUnit `10/10`、0 failures，但 Xcode 明确 skipped，因此它只证明传播和路由，不替代候选 full 编译证据。
- 按规则未跑本机 build / 探针；候选 full 使用 `probe_mode=skip`，未生成新的漫画探针指标或 `metrics/version_history.csv` 行。真实 Koharu 四件套、Speech corpus 和真实竖排图片 corpus 仍缺失；full artifact 明确报告 `manifestMissing` / `stopUntilArtifactsProvided`，不得据此声称 OCR、翻译或识别质量提升。

## v3.25：OCR 原文确认动作语义
日期：2026-07-30

状态：Agent X 已完成实现、云端验收和合并收口；工程正式版本为 `MARKETING_VERSION=3.25`。PR #89 已合入 `smalldata_test`，merge SHA `f812dc35e69c8122d1d963f2b57cf83c0cc6f7fd`；远端 `codeb/v3.25-image-ocr-correction-confirmation-action` 已删除，未触碰 `main`。

核心变更：

- `TranslationSessionStore` 既有的 trim 后同文短路会在调用模型前返回成功；修正 sheet 现在以同一判断决定动作名称，避免把无重译确认错误标成“保存并重译”。
- 规范化文本未变化时显示“确认无误”并通过无障碍提示说明不会重新翻译；实际变化时仍显示“保存并重译”，继续只走既有目标 block correction 和成功后的复查完成路径。
- 新增 v3.25 源码合同并接入图片/UI fail-fast 路由；本版不新增 Store 或持久化状态，不改变 Vision OCR、翻译、导出、渲染、漫画探针或 Koharu artifact 路径。
- 候选初次 PR fast 结果包暴露 `reusedFullValidationSha/state` 未记录的工作流元数据缺口；同一候选补写当前 PR head 的 full-validation receipt，缺失成功收据时不再声称复用，随后以新 SHA 重新 full 验证。

验证与遗留：

- 候选 SHA `6b6ec0fcea42bd6569c1d0fd33ee7f3ef80928de` 的 full run `30518414492` 成功，`AITRANS CI/full-validation` status 为 success，Xcode build 成功、JUnit `10/10`、0 failures；未加密 artifact 为 `aitrans-ci-v3.25-codeb-v3.25-image-ocr-correction-confirmation-action--6b6ec0fcea42-run30518414492-attempt1`。artifact 的 version、branch、commitSha、runId、runAttempt、workflowName、`validationProfile=full`、`validationReason=candidate_development_push` 与候选一致；`.xcresult` 已随结果包上传，failure summary 记录静态检查、图片/UI 合同和 Xcode build 均成功。
- PR #89 的 fast follow-up `30518851872` 成功，明确 `xcodeBuildRequired=false`，并记录 `reusedFullValidationSha=6b6ec0fcea42bd6569c1d0fd33ee7f3ef80928de`、`reusedFullValidationState=success`。合并后的 fast follow-up `30518938777` 成功，以同一 receipt 和 `validationReason=merge_reuses_successful_candidate_full_validation` 复用候选 full；两者均只作路由跟踪，不作为新的 Swift/Xcode 编译证据。
- 按规则未跑本机 build / 探针；候选 full 使用 `probe_mode=skip`，未生成新的漫画探针指标或 `metrics/version_history.csv` 行。真实 Koharu 四件套、Speech corpus 和真实竖排图片 corpus 仍缺失；full artifact 明确报告 `manifestMissing` / `stopUntilArtifactsProvided`，不得据此声称 OCR、翻译或识别质量提升。

## v3.24：保护未保存 OCR 修正
日期：2026-07-30

状态：Agent X 已完成实现、云端验收和合并收口；工程正式版本为 `MARKETING_VERSION=3.24`。PR #88 已合入 `smalldata_test`，merge SHA `3a001ec7cbc8e9906963294071d9fa53e8d3f053`；远端 `codeb/v3.24-image-ocr-correction-discard-confirmation` 已删除，未触碰 `main`。

核心变更：

- 普通图片 OCR 修正 sheet 在本地比较编辑文本与当前 block 原文；无改动取消直接关闭，有改动取消先显示 destructive “放弃修正”确认，继续编辑保留输入。
- 交互式关闭在保存中或存在未保存改动时均被阻止；成功保存沿用 v3.21 的 `didSave()` 后直接关闭，不经过放弃确认。
- 新增 v3.24 源码合同并接入图片/UI fail-fast 路由；该状态不进入 `TranslationSessionStore`、transcript、export、渲染、图片 revision 或持久化。
- 本版不改 Vision OCR、方向/layout、漫画探针、Koharu artifact 契约、ground truth、metrics 或 output，不声称 OCR/翻译质量提升。

验证与遗留：

- 候选 SHA `5f4db4a203730750bf94e1c0adaa541142a62787` 的 full run `30516085420` 成功，`AITRANS CI/full-validation` status 为 success，Xcode build 成功、JUnit `10/10`、0 failures，未加密 artifact 为 `aitrans-ci-v3.24-codeb-v3.24-image-ocr-correction-discard-confirmation--5f4db4a20373-run30516085420-attempt1`。artifact 的 version、branch、commitSha、runId、runAttempt、workflowName、`validationProfile=full`、`validationReason=candidate_development_push` 与候选一致；`.xcresult` 的 Build 为 `succeeded` 且 root issues 为空。
- PR #88 的 fast follow-up `30516579680` 成功，明确 `xcodeBuildRequired=false`、`fast_followup_reuses_candidate_full_validation`，仅作路由跟踪。合并后的 fast follow-up `30516689572` 成功，manifest 复用第二父 `5f4db4a203730750bf94e1c0adaa541142a62787` 的 full receipt，`reusedFullValidationState=success`；两者均不作为新的 Swift/Xcode 编译证据。
- 本地运行 `git diff --check`、32 个图片/UI 合同、`xcrun swiftc -parse AITRANS/Views/ImageTranslationViews.swift`、v1.94 CI 分层合同、v1.97 版本身份合同、plist/YAML/JSON smoke 均通过。按规则未跑本机 build / 探针；本次 push `probe_mode=skip`，未生成新的漫画探针指标或 `metrics/version_history.csv` 行。
- 真实 Koharu 四件套、Speech corpus 和真实竖排图片 corpus 仍缺失；full artifact 明确报告 `manifestMissing` / `stopUntilArtifactsProvided`，不得据此声称 OCR、翻译或识别质量提升。

## v3.23：恢复人工修正前确认
日期：2026-07-30

状态：Agent X 已完成实现、云端验收和合并收口；工程正式版本为 `MARKETING_VERSION=3.23`。PR #87 已合入 `smalldata_test`，merge SHA `7be0691368ccc0be8df39468c8c96cf316715b53`；远端 `codeb/v3.23-image-ocr-restore-confirmation` 已删除，未触碰 `main`。

核心变更：

- 恢复人工修正过的图片 OCR block 前，View 私有 confirmation dialog 先明确说明会移除本次人工修正；取消保持当前 block、图片 transcript、导出、渲染、选择和复查状态不变。
- 只有 destructive 确认动作会清除待确认 block 并调用 v3.22 既有 Store 恢复路径；Store 继续无模型恢复 Vision OCR 基线、同步 transcript、撤销旧 export/share 并重绘。
- 图片 revision 变化会清空待确认 block，防止旧 dialog 对新图片操作；新增 v3.23 源码合同并接入图片/UI fail-fast 路由。
- 本版不改 Vision OCR、方向/layout、漫画探针、Koharu artifact 契约、ground truth、metrics 或 output，不声称 OCR/翻译质量提升。

验证与遗留：

- 首个候选 SHA `9faffd3c9fe97c95f2769175d5a6b864f2662f8f` 的 full run `30514540746` 由 Xcode 捕获不支持的 `confirmationDialog(item:)` 调用而失败；该 SHA 未创建 PR。随后以 `isPresented` 绑定修复并补强合同，最终候选 SHA `de5948d29383b038a06c48c994f752ba1fdff40d` 的 full run `30514876023` 成功，`AITRANS CI/full-validation` status 为 success，Xcode build 成功、JUnit `10/10`、0 failures，未加密 artifact 为 `aitrans-ci-v3.23-codeb-v3.23-image-ocr-restore-confirmation--de5948d29383-run30514876023-attempt1`。
- PR #87 的 fast follow-up `30515313637` 与合并后的 fast follow-up `30515376757` 均成功；前者明确 `xcodeBuildRequired=false`、`fast_followup_reuses_candidate_full_validation`，不作为 Swift/Xcode 编译证据。按规则未跑本机 build / 探针；本次 push `probe_mode=skip`，未生成新的漫画探针指标或 `metrics/version_history.csv` 行。
- 本地运行 `git diff --check`、31 个图片/UI 合同、`xcrun swiftc -parse AITRANS/Views/ImageTranslationViews.swift`、v1.94 CI 分层合同、v1.97 版本身份合同、plist/YAML/JSON smoke 均通过。真实 Koharu 四件套、Speech corpus 和真实竖排图片 corpus 仍缺失；artifact 明确报告 `manifestMissing` / `stopUntilArtifactsProvided`，不得据此声称 OCR、翻译或识别质量提升。

## v3.22：恢复图片 Vision OCR 基线
日期：2026-07-30

状态：Agent X 已完成核心实现、本地轻量回归、exact-SHA 云端 full、PR 和合并收口；工程正式版本为 `MARKETING_VERSION=3.22`。PR #86 已合入 `smalldata_test`，merge SHA `301b7b52a8bf2744d627f830eff519e5748c494a`；远端 `codeb/v3.22-image-ocr-correction-restore` 已删除，未触碰 `main`。

核心变更：

- 首次成功人工修正时，Store 私有保存当前图片该 block 的完整 Vision OCR 基线；同一 block 后续修正保持首次基线，新图片或清空会丢弃该非持久化快照。
- 已修正结果行新增独立 44pt 回转箭头动作，恢复 Vision OCR 原文和初始译文时不调用模型；成功后同步当前图片 transcript，撤销旧 export/share 并复用既有 render 生命周期重绘。
- 恢复风险 block 会清除本次已复查标记、保留该 block 定位并把 VoiceOver 焦点返回结果行，避免把旧复查结论带到恢复后的 OCR。
- 新增 v3.22 源码合同并接入图片/UI fail-fast 路由。本版不改 Vision OCR、方向/layout、漫画探针、Koharu 报告或 ground truth，不刷新 `output/` 与 `metrics/version_history.csv`，不声称识别或翻译质量提升。

验证与遗留：

- 本机轻量回归：30 个图片/UI 合同脚本通过（含 v3.21 8/8、v3.22 6/6），Swift 变更文件与全量 App parse、CI 分层 9/9、版本身份 5/5、YAML/JSON 解析和 `git diff --check` 均通过；未跑本机 build / 探针，按规则交给云端验证。
- exact-SHA full `30513465295` 对候选 `48332ceee1cf9be2ef46f5890a05fb11aab895c4` 成功：未加密 artifact 的 version/branch/commitSha/runId/runAttempt 均匹配，`validationProfile=full`、`xcodeBuildRequired=true`；`.xcresult` 为 succeeded、0 errors/0 warnings，JUnit 10/10、0 failures/errors，图片/UI 合同通过。PR fast `30513908959` 与 merge fast `30513965865` 均成功；fast 仅作 follow-up，不作为编译证据。
- 云端漫画探针在这次默认 push full 中仍为 `probe_mode=skip`，未生成新的 OCR/翻译质量数字或 `output/` 基线；真实 Koharu 四件套、Speech corpus 和真实竖排图片 corpus 仍缺失。

## v3.21：普通图片 OCR 单块人工修正
日期：2026-07-30

状态：Agent X 已完成核心实现、本地轻量回归、exact-SHA 云端 full、PR 和合并收口；工程正式版本为 `MARKETING_VERSION=3.21`。PR #85 已合入 `smalldata_test`，merge SHA `620290ec5a56c2d9fa5be97a7eec494c946f1f68`；远端 `codeb/v3.21-image-ocr-correction` 已删除，未触碰 `main`。

核心变更：

- 普通图片每个 OCR 结果行新增独立 44pt 编辑动作和人工修正 sheet；空文本不可保存，重译期间锁定重复提交、取消和交互式关闭，并提供明确进度与失败反馈。
- `TranslationSessionStore` 只重新翻译目标 block，回写前核对 correction ID、图片 task ID、block ID 和旧原文快照。新图片、清空或取消会使旧 correction 失效，晚到结果不得覆盖新内容。
- 修正失败保留旧 block、当前图片 transcript 与旧导出；成功后原子更新原文/译文与当前图片 transcript，撤销旧 export/share，再复用既有 render ID 生命周期按当前覆盖模式重绘。成功修正风险块后，本次复查队列继续前进。
- 新增 v3.21 源码合同并接入图片/UI fail-fast 路由。本版不改 Vision OCR、方向/layout、漫画探针、Koharu 报告或 ground truth，不刷新 `output/` 与 `metrics/version_history.csv`，不声称识别或翻译质量提升。

验证与遗留：

- v3.21 新合同 8/8、29 个图片/UI 合同脚本共 185/185 通过；Swift 全量 parse、workflow YAML、CI 分层 9/9、版本身份 5/5、工程版本解析（`v3.21`）、3 份 JSON 基线和 `git diff --check` 均通过。
- 候选 exact SHA `a7ad2684341c145e86c290166736723f2b7c5782` 的云端 full run `30512490423` attempt 1 成功；artifact `aitrans-ci-v3.21-codeb-v3.21-image-ocr-correction--a7ad2684341c-run30512490423-attempt1` 与 version / branch / SHA / run / attempt / profile 完全一致，图片/UI 185/185、Speech/home/paste、extended Koharu validator matrix 和 Xcode build 均通过，JUnit 10/10，`.xcresult` 为 succeeded、0 error / 0 warning，commit status `AITRANS CI/full-validation=success`。UI evidence 按 `not_requested` 跳过；静态截图不能验证异步翻译回调隔离或真实文本输入体验。
- PR #85 exact HEAD fast run `30512770595` 成功后合并；merge follow-up run `30512808423` 成功，artifact 与 merge HEAD `620290ec5a56c2d9fa5be97a7eec494c946f1f68` 一致，`validationProfile=fast`、`validationReason=merge_reuses_successful_candidate_full_validation`，精确复用候选 SHA `a7ad2684341c145e86c290166736723f2b7c5782` 的成功 full 收据，Xcode skip reason 为 `fast_followup_reuses_candidate_full_validation`。
- 未跑本机 build / 探针，按规则交给云端验证。本版未改变漫画探针，push 默认 `probe_mode=skip`；真实 Koharu 四件套、Speech corpus 和真实竖排图片 corpus 仍缺失，不声称 OCR 或翻译质量提升。真实设备上的长文本输入法、VoiceOver sheet 操作和连续快速修正仍需人工回放。

## v3.20：图片连续复查 VoiceOver 焦点
日期：2026-07-29

状态：Agent X 已完成核心实现、本地轻量回归、exact-SHA 云端 full 和 PR 收口；工程正式版本为 `MARKETING_VERSION=3.20`。PR #84 已合入 `smalldata_test`，merge SHA `ef1816b4770f51d92341c71a010b57a6a2fc2707`；远端 `codeb/v3.20-image-review-voiceover-focus` 已删除，未触碰 `main`。

核心变更：

- 图片复查新增 View 私有 `AccessibilityFocusState<String?>`，用不同 focus ID 区分结果行、局部放大和“本次复查完成”，避免风险行出队后 VoiceOver 失去上下文。
- 开始或重启队列后聚焦当前局部放大；结果行快速完成/撤销后聚焦下一行或当前行；局部放大完成/撤销后聚焦下一块或当前块放大窗；最后一块完成后聚焦完成态。
- 焦点发布先让出一次主线程更新，并核对捕获的图片 revision；新图片会同步清除选择、复查进度与无障碍焦点，旧任务不得抢回焦点。
- 新增 v3.20 源码合同并接入图片/UI fail-fast 路由。本版不写 Store 或持久化，不改变 OCR、翻译、renderer、导出或漫画探针，也不刷新 `output/` 或 `metrics/version_history.csv`。

验证与遗留：

- v3.20 新合同 7/7、28 个图片/UI 合同脚本共 177/177 通过；Swift 全量 parse、workflow YAML、CI 分层 9/9、版本身份 5/5、工程版本解析（`v3.20`）、工程 plist、3 份 JSON 基线和 `git diff --check` 均通过。
- 候选 exact SHA `03a008e0a882cb69127894fd14b493708db185fd` 的云端 full run `30425666348` attempt 1 成功；artifact `aitrans-ci-v3.20-codeb-v3.20-image-review-voiceover-focus--03a008e0a882-run30425666348-attempt1` 与 version / branch / SHA / run / attempt / profile 完全一致，图片/UI 177 项、Speech/home/paste、extended Koharu validator matrix 和 Xcode build 均通过，JUnit 10/10，`.xcresult` 存在，commit status `AITRANS CI/full-validation=success`。UI evidence 按 `not_requested` 跳过，因为静态截图不能证明 VoiceOver 焦点迁移。
- PR #84 exact HEAD fast run `30426160146` 成功后合并；merge follow-up run `30426221026` 成功，artifact 与 merge HEAD `ef1816b4770f51d92341c71a010b57a6a2fc2707` 一致，`validationProfile=fast`、`validationReason=merge_reuses_successful_candidate_full_validation`，精确复用候选 SHA `03a008e0a882cb69127894fd14b493708db185fd` 的成功 full 收据，Xcode skip reason 为 `fast_followup_reuses_candidate_full_validation`，JUnit 10/10。
- 真实 VoiceOver 左右扫动、Rotor 和快速连续点击仍需人工在模拟器或真机回放，源码合同只验证接线和 revision isolation。
- 未跑本机 build / 探针，按规则交给云端验证。真实 Koharu 四件套、Speech corpus 和真实竖排图片 corpus 仍缺失，不声称 OCR、翻译或识别质量提升。

## v3.19：图片结果行快速复查
日期：2026-07-28

状态：Agent X 已完成核心实现、本地轻量回归、exact-SHA 云端 full / UI evidence 和 PR 收口；工程正式版本为 `MARKETING_VERSION=3.19`。PR #83 已合入 `smalldata_test`，merge SHA `a2a921603365cf811ba2e04fb2943b5c00c29d26`；远端 `codeb/v3.19-image-review-quick-action` 已删除，未触碰 `main`。

核心变更：

- 每个低置信或方向待定结果行新增独立 44pt 完成并继续/撤销复查动作；主行 Button 仍只负责图片定位与局部放大，避免嵌套交互和误触职责混合。
- 快速动作复用既有 View 私有 `toggleReviewCompletion`：完成后按未复查顺序定位下一块，撤销后把该块放回队列并定位；不新增 Store 或持久化状态。
- 队列入口在尚无完成项时显示“开始复查 N”，已有进度时显示“继续复查 N”；风险原因和已复查标签改为纵向排列，降低 360pt inspector 与 Dynamic Type 下的横向拥挤。
- 局部放大动作同步命名为“完成并继续复查”；新增 v3.19 源码合同并接入图片/UI fail-fast 路由。本版不刷新 `output/` 或 `metrics/version_history.csv`，不声称 OCR、翻译或识别质量提升。

验证与遗留：

- v3.19 新合同 6/6、27 个图片/UI 合同脚本共 170/170 通过；Swift parse、workflow YAML、CI 分层 9/9、版本身份 5/5、工程版本解析（`v3.19`）、工程 plist、3 份 JSON 基线和 `git diff --check` 均通过。
- 候选 exact SHA `88e1b8d8b425d75a64afcd60b9877fab22833cae` 的云端 full run `30345511411`：attempt 1 的 Xcode build、静态/领域合同均成功，但第 6 个 UI 场景 `text-success-compact-xxl-day.png` 得到瞬时空白截图，UI evidence 正确拒绝并使 JUnit 9/10；同一 SHA 的 attempt 2 重跑成功。attempt 2 artifact `aitrans-ci-v3.19-codeb-v3.19-image-review-quick-action--88e1b8d8b425-run30345511411-attempt2` 与 version / branch / SHA / run / attempt / profile 完全一致，图片/UI 170 项、Speech/home/paste、extended Koharu validator matrix、Xcode build 和 UI evidence 均通过，JUnit 10/10，commit status `AITRANS CI/full-validation=success`。
- attempt 2 UI evidence manifest 精确包含同一候选 SHA 的 14 张截图（12 compact iPhone + 2 wide iPad）。人工检查 `image-success-wide-ipad-day.png`，确认图片成功态、低置信/方向待定汇总、“本次复查 0/2”和“开始复查 2”入口清晰可见，无文字、控件重叠或越界。
- PR #83 exact HEAD fast run `30347861288` 成功后合并；merge follow-up run `30347911608` 成功，artifact 与 merge HEAD `a2a921603365cf811ba2e04fb2943b5c00c29d26` 一致，`validationProfile=fast`、`validationReason=merge_reuses_successful_candidate_full_validation`，精确复用候选 SHA `88e1b8d8b425d75a64afcd60b9877fab22833cae` 的成功 full 收据，Xcode skip reason 为 `fast_followup_reuses_candidate_full_validation`，JUnit 10/10。
- 未跑本机 build / 探针，按规则交给云端验证。真实 Koharu 四件套、Speech corpus 和真实竖排图片 corpus 仍缺失；本版没有真实 OCR/翻译质量新数据，不刷新 `output/` 或 `metrics/version_history.csv`，不声称识别质量提升。

## v3.18：图片复查汇总进度与运行态证据
日期：2026-07-28

状态：Agent X 已完成核心实现、本地轻量回归、exact-SHA 云端 full / UI evidence 和 PR 收口；工程正式版本为 `MARKETING_VERSION=3.18`。PR #82 已合入 `smalldata_test`，merge SHA `1a4d321f73842852b9d77d1b50e8c51f56478a47`；远端 `codeb/v3.18-image-review-progress-evidence` 已删除，未触碰 `main`。

核心变更：

- 图片识别结果存在低置信或方向待定块时，在筛选器下方显示紧凑的“本次复查”进度，文字与 VoiceOver 同时报告已完成、总数和剩余数；待处理与全部完成分别使用 warning / success 色调，但不以颜色作为唯一状态表达。
- 进度只消费 `ImageTranslationPanel` 既有 View 私有复查集合，不写 Store 或持久化，不改变 OCR、翻译、renderer、导出或漫画探针。
- DEBUG `imageSuccess` fixture 固定包含一个低置信横排块和一个方向待定块；UI evidence 增加 wide iPad 图片成功态，当前矩阵扩为 14 张（12 compact iPhone + 2 wide iPad）。
- 新增 v3.18 源码/证据合同并接入图片/UI fail-fast 路由；本版不刷新 `output/` 或 `metrics/version_history.csv`，不声称 OCR、翻译或识别质量提升。

验证与遗留：

- v3.18 新合同 7/7、26 个图片/UI 合同脚本共 164/164 通过；Swift parse、workflow YAML、CI 分层 9/9、版本身份 5/5、工程版本解析（`v3.18`）、工程 plist、3 份 JSON 基线和 `git diff --check` 均通过。
- 候选 exact SHA `596af740d4e1d1ce426446e9e2a6201f0ba3372b` 的云端 full run `30343297952` attempt 1 成功；artifact `aitrans-ci-v3.18-codeb-v3.18-image-review-progress-evidence--596af740d4e1-run30343297952-attempt1` 与 version / branch / SHA / run / profile 完全一致，图片/UI 164 项、Speech/home/paste、extended Koharu validator matrix 和 Xcode build 均通过，JUnit 10/10，`.xcresult` 0 error / 0 warning，commit status `AITRANS CI/full-validation=success`。
- UI evidence 因候选 commit marker 实际执行成功，manifest 精确包含同一 SHA 的 14 张截图（12 compact iPhone + 2 wide iPad）。新增 `image-success-wide-ipad-day.png` 为 1640×2360、979430 bytes；人工检查确认图片成功态、低置信/方向待定汇总、“本次复查 0/2”进度和队列入口清晰可见，无文字、控件重叠或越界。
- PR #82 exact HEAD fast run `30344483424` 成功后合并；merge follow-up run `30344554549` 成功，artifact 与 merge HEAD `1a4d321f73842852b9d77d1b50e8c51f56478a47` 一致，`validationProfile=fast`、`validationReason=merge_reuses_successful_candidate_full_validation`，精确复用候选 SHA `596af740d4e1d1ce426446e9e2a6201f0ba3372b` 的成功 full 收据，Xcode skip reason 为 `fast_followup_reuses_candidate_full_validation`，JUnit 10/10。
- 未跑本机 build / 探针，按规则交给云端验证。真实 Koharu 四件套、Speech corpus 和真实竖排图片 corpus 仍缺失；本版没有真实 OCR/翻译质量新数据，不刷新 `output/` 或 `metrics/version_history.csv`，不声称识别质量提升。

## v3.17：图片待复查进度与自动出队
日期：2026-07-28

状态：Agent X 已完成核心实现、本地轻量回归、exact-SHA 云端 full 和 PR 收口；工程正式版本为 `MARKETING_VERSION=3.17`。PR #81 已合入 `smalldata_test`，merge SHA `9dbd2d0b17752b3bd34cde8e2d84404c5eacb58e`；远端 `codeb/v3.17-image-review-progress` 已删除，未触碰 `main`。

核心变更：

- 图片页用 View 私有 block ID 集合记录当前图片 revision 的本次复查进度；风险集合仍先由 `ImageOCRReviewFilter.needsReview` 统一判定，再排除已复查项，图片 revision 变化时进度和选择一起清零。
- 局部放大新增 44pt 命名完成/撤销命令。完成当前块后优先定位队列中其后的未复查块；没有后项时回到前一个，最后一块完成后关闭局部放大并显示“本次复查完成”。
- “待复查”计数与一键入口改为剩余数量；“全部”列表用文字和图标显示本次已复查项。全部完成后可一键清除进度、重新进入首个风险块；从“全部”选择已复查风险块时也可撤销并放回队列。
- 进度只属于当前界面会话，不写 Store 或持久化，不改变完整 blocks、OCR、翻译、renderer、导出或漫画探针。新增 v3.17 源码合同并接入图片/UI fail-fast 路由；本版不刷新 `output/` 或 `metrics/version_history.csv`，不声称 OCR、翻译或识别质量提升。

验证与遗留：

- v3.17 新合同 7/7、25 个图片/UI 合同脚本共 157/157 通过；Swift parse、workflow YAML、CI 分层 9/9、版本身份 5/5、工程版本解析（`v3.17`）、工程 plist、3 份 JSON 基线和 `git diff --check` 均通过。
- 候选 exact SHA `4503098653be4173caa599ddc41be5a112ae3270` 的云端 full run `30341582698` attempt 1 成功；artifact `aitrans-ci-v3.17-codeb-v3.17-image-review-progress--4503098653be-run30341582698-attempt1` 与 version / branch / SHA / run / profile 完全一致，图片/UI 157 项、Speech/home/paste、extended Koharu validator matrix 和 Xcode build 均通过，JUnit 10/10，`.xcresult` succeeded、0 error / 0 warning，commit status `AITRANS CI/full-validation=success`。
- PR #81 exact HEAD fast run `30342065431` 成功后合并；merge follow-up run `30342139610` 成功，artifact 与 merge HEAD `9dbd2d0b17752b3bd34cde8e2d84404c5eacb58e` 一致，`validationProfile=fast`、`validationReason=merge_reuses_successful_candidate_full_validation`，精确复用候选 SHA `4503098653be4173caa599ddc41be5a112ae3270` 的成功 full 收据，Xcode skip reason 为 `fast_followup_reuses_candidate_full_validation`，JUnit 10/10。
- 未跑本机 build / 探针，按规则交给云端验证。本版未运行 UI evidence；局部放大底部三按钮在极窄宽度、Dynamic Type、VoiceOver 完成/撤销后的焦点转移和真实多块操作仍需后续人工运行态检查。真实 Koharu 四件套、Speech corpus 和真实竖排图片 corpus 仍缺失，不刷新 `output/` 或 `metrics/version_history.csv`，不声称 OCR、翻译或识别质量提升。

## v3.16：一键进入图片待复查队列
日期：2026-07-28

状态：Agent X 已完成核心实现、本地轻量回归、exact-SHA 云端 full 和 PR 收口；工程正式版本为 `MARKETING_VERSION=3.16`。PR #80 已合入 `smalldata_test`，merge SHA `336e367c1a05bcd86843b28c03ec8eb191990f18`；远端 `codeb/v3.16-image-review-queue-entry` 已删除，未触碰 `main`。

核心变更：

- “识别结果”在确有低置信或方向待定块时显示“定位待复查 N”命名命令，空队列不显示无效入口。
- 点击后复用 `ImageOCRReviewFilter.needsReview` 切到共享风险集合；当前选择仍属于队列时保留，否则选中首个风险块，再调用一次现有 workspace 定位，直接进入局部放大与前后导航。
- 入口复用 `AppSecondaryButton` 的 44pt 点击区，并说明会定位当前或首个文字块。队列、筛选和选择仍是 View 私有展示状态，不创建“已复查”业务状态，不进入 Store、OCR、翻译、renderer、导出或持久化。
- 新增 v3.16 源码合同并接入图片/UI fail-fast 路由。本版不刷新 `output/` 或 `metrics/version_history.csv`，不声称 OCR、翻译或识别质量提升。

验证与遗留：

- v3.16 新合同 5/5、24 个图片/UI 合同脚本共 150/150 通过；Swift parse、workflow YAML、CI 分层 9/9、版本身份 5/5、工程版本解析（`v3.16`）、工程 plist、3 份 JSON 基线和 `git diff --check` 均通过。
- 候选 exact SHA `11a46beedcc2c4f5562a000b08931e36cdee1946` 的云端 full run `30339824675` attempt 1 成功；artifact `aitrans-ci-v3.16-codeb-v3.16-image-review-queue-entry--11a46beedcc2-run30339824675-attempt1` 与 version / branch / SHA / run / profile 完全一致，图片/UI 150 项、Speech/home/paste、extended Koharu validator matrix 和 Xcode build 均通过，JUnit 10/10，`.xcresult` succeeded、0 error / 0 warning，commit status `AITRANS CI/full-validation=success`。
- PR #80 exact HEAD fast run `30340452255` 成功后合并；merge follow-up run `30340570024` 成功，artifact 与 merge HEAD `336e367c1a05bcd86843b28c03ec8eb191990f18` 一致，`validationProfile=fast`、`validationReason=merge_reuses_successful_candidate_full_validation`，精确复用候选 SHA `11a46beedcc2c4f5562a000b08931e36cdee1946` 的成功 full 收据，Xcode skip reason 为 `fast_followup_reuses_candidate_full_validation`，JUnit 10/10。
- 未跑本机 build / 探针，按规则交给云端验证。本版未运行 UI evidence；紧凑宽度按钮文字、Dynamic Type、VoiceOver 进入队列后的顺序与真实多块操作仍需后续人工运行态检查。真实 Koharu 四件套、Speech corpus 和真实竖排图片 corpus 仍缺失，不刷新 `output/` 或 `metrics/version_history.csv`，不声称 OCR、翻译或识别质量提升。

## v3.15：图片预览文字块直接点选
日期：2026-07-28

状态：Agent X 已完成核心实现、本地轻量回归、exact-SHA 云端 full 和 PR 收口；工程正式版本为 `MARKETING_VERSION=3.15`。PR #79 已合入 `smalldata_test`，merge SHA `595fa31dcf62c77880a7ef819511c827b876aca3`；远端 `codeb/v3.15-image-preview-direct-selection` 已删除，未触碰 `main`。

核心变更：

- 完整图片预览中的旁贴/覆盖 OCR block 改为 plain Button，用户可在图片上直接点选文字块并打开既有局部放大，无需先在结果列表寻找。
- 点击已选块会取消选择；点击当前“待复查”筛选不可见的块时先回到“全部”，使结果列表、位置文字与前后导航仍共享同一可见顺序。
- 两种覆盖模式都提供至少 44pt 点击区，VoiceOver 可读取 OCR 原文、译文、定位状态和下一步动作。选择与筛选协调仍是 View 私有状态，不进入 Store、OCR、翻译、renderer、导出或持久化。
- 新增 v3.15 源码合同并接入图片/UI fail-fast 路由。本版不刷新 `output/` 或 `metrics/version_history.csv`，不声称 OCR、翻译或识别质量提升。

验证与遗留：

- v3.15 新合同 5/5，v1.87 与 v2.2-v3.15 全部图片/UI 合同合计 145 项通过；完整 Xcode toolchain Swift parse、workflow YAML、CI 分层 9/9、版本身份 5/5、工程版本解析 `v3.15`、工程 plist、三份基线 JSON 和 `git diff --check` 均通过。
- 候选 exact SHA `b15a9dd3a03b7b6346f3b4d448397337c29f71ad` 的云端 full run `30338387675` attempt 1 成功；artifact `aitrans-ci-v3.15-codeb-v3.15-image-preview-direct-selection--b15a9dd3a03b-run30338387675-attempt1` 与 version / branch / SHA / run / profile 完全一致，图片/UI 145 项、Speech/home/paste、extended Koharu validator matrix 和 Xcode build 均通过，JUnit 10/10，`.xcresult` succeeded、0 error / 0 warning，commit status `AITRANS CI/full-validation=success`。
- PR #79 exact HEAD fast run `30338949455` 成功后合并；merge follow-up run `30339006117` 成功，artifact 与 merge HEAD `595fa31dcf62c77880a7ef819511c827b876aca3` 一致，`validationProfile=fast`、`validationReason=merge_reuses_successful_candidate_full_validation`，精确复用候选 SHA `b15a9dd3a03b7b6346f3b4d448397337c29f71ad` 的成功 full 收据，Xcode skip reason 为 `fast_followup_reuses_candidate_full_validation`，JUnit 10/10。
- 未跑本机 build / 探针，按规则交给云端验证。本版未运行 UI evidence；小 bbox 的实机点击容错、覆盖块重叠时的目标选择、Dynamic Type 和 VoiceOver 顺序仍需后续人工运行态检查。真实 Koharu 四件套、Speech corpus 和真实竖排图片 corpus 仍缺失，不刷新 `output/` 或 `metrics/version_history.csv`，不声称 OCR、翻译或识别质量提升。

## v3.14：图片复查定位与连续导航
日期：2026-07-28

状态：Agent X 已完成核心实现、本地轻量回归、exact-SHA 云端 full 和 PR 收口；工程正式版本为 `MARKETING_VERSION=3.14`。PR #78 已合入 `smalldata_test`，merge SHA `862c405c8ad5b15dec729df05fffec3011496ee7`；远端 `codeb/v3.14-image-review-navigation` 已删除，未触碰 `main`。

核心变更：

- 图片页外层增加单一 `ScrollViewReader`，并把唯一 workspace anchor 放在 `ImageTranslationPanel` 根部，避免 `ViewThatFits` 宽/窄候选布局复制滚动 ID。
- 结果行切到新 block 后将图片工作区带回视口；点击同一行取消选择不滚动。系统 Reduce Motion 开启时立即定位，否则使用现有标准动效。
- 局部放大窗显示选中 block 在当前“全部/待复查”序列中的位置，并提供命名明确的 44pt 上一个/下一个按钮；首尾按钮禁用并降调，导航不越界、不绕回。
- 滚动、位置和导航继续只消费 View 私有选择与当前筛选结果，不写 Store，不改变完整 blocks、OCR、翻译、renderer、导出或持久化。
- 新增 v3.14 源码合同并接入图片/UI fail-fast 路由；v3.13 合同适配新增位置前缀但继续锁定 OCR 原文可访问。本版不刷新 `output/` 或 `metrics/version_history.csv`，不声称 OCR、翻译或识别质量提升。

验证与遗留：

- v3.14 新合同 7/7，v1.87 与 v2.2-v3.14 全部图片/UI 合同合计 140 项通过；完整 Xcode toolchain Swift parse、实际 workflow YAML、CI 分层 9/9、版本身份 5/5、工程版本解析 `v3.14`、工程 plist、三份基线 JSON 和 `git diff --check` 均通过。
- 候选 exact SHA `a6156b05069d61f15604cb30391598edb53b1895` 的云端 full run `30336902810` attempt 1 成功；artifact `aitrans-ci-v3.14-codeb-v3.14-image-review-navigation--a6156b05069d-run30336902810-attempt1` 与 version / branch / SHA / run / profile 完全一致，图片/UI 140 项、Speech/home/paste、extended Koharu validator matrix 和 Xcode build 均通过，JUnit 10/10，`.xcresult` succeeded、0 error / 0 warning，commit status `AITRANS CI/full-validation=success`。
- PR #78 exact HEAD fast run `30337375615` 成功后合并；merge follow-up run `30337452798` 成功，artifact 与 merge HEAD `862c405c8ad5b15dec729df05fffec3011496ee7` 一致，`validationProfile=fast`、`validationReason=merge_reuses_successful_candidate_full_validation`，精确复用候选 SHA `a6156b05069d61f15604cb30391598edb53b1895` 的成功 full 收据，Xcode skip reason 为 `fast_followup_reuses_candidate_full_validation`，JUnit 10/10。
- 未跑本机 build / 探针，按规则交给云端验证。本版未运行 UI evidence；真实设备上的自动滚动落点、紧凑宽度按钮遮挡、Dynamic Type 和 VoiceOver 顺序仍需后续人工运行态检查。真实 Koharu 四件套、Speech corpus 和真实竖排图片 corpus 仍缺失，不刷新 `output/` 或 `metrics/version_history.csv`，不声称 OCR、翻译或识别质量提升。

## v3.13：选中文字块局部放大复查
日期：2026-07-28

状态：Agent X 已完成核心实现、本地轻量回归、exact-SHA 云端 full 和 PR 收口；工程正式版本为 `MARKETING_VERSION=3.13`。PR #77 已合入 `smalldata_test`，merge SHA `97fcd4174621494e7756fed31a30b7304bae6d73`；远端 `codeb/v3.13-image-block-focus` 已删除，未触碰 `main`。

核心变更：

- 选中 OCR 结果行后，完整预览继续高亮对应 block，同时从当前最大边 2048px 的已下采样预览裁切局部放大窗，改善小 bbox 的可检查性，不重新解码 Store 原图。
- 局部裁切以 block 中心为基准，至少覆盖 bbox 宽高的 1.8 倍，以归一化宽 16%、高 10% 为下限并扩展到 16:9；裁切夹取在图片范围内，放大窗用至少 24pt 的警示色边框再次标出原 bbox。
- 放大窗提供带可访问名称的 44pt 关闭命令，清除同一 View 私有选择。选择、裁切和关闭均不进入 Store、OCR、翻译、renderer、导出或持久化。
- 新增 v3.13 源码合同并接入图片/UI fail-fast 路由；为新增预览参数更新 v3.12 字符串合同，但不放松其完整 blocks、高亮和状态隔离约束。本版不刷新 `output/` 或 `metrics/version_history.csv`，不声称 OCR、翻译或识别质量提升。

验证与遗留：

- v3.13 新合同 6/6，v1.87 与 v2.2-v3.13 全部图片/UI 合同合计 133 项通过；完整 Xcode toolchain Swift parse、实际 workflow YAML、CI 分层 9/9、版本身份 5/5、工程版本解析 `v3.13`、工程 plist、三份基线 JSON 和 `git diff --check` 均通过。
- 候选 exact SHA `86d91084f908adfd4f69a73d0e55568d36276d52` 的云端 full run `30335627953` attempt 1 成功；artifact `aitrans-ci-v3.13-codeb-v3.13-image-block-focus--86d91084f908-run30335627953-attempt1` 与 version / branch / SHA / run / profile 完全一致，图片/UI 133 项、Speech/home/paste、extended Koharu validator matrix 和 Xcode build 均通过，JUnit 10/10，`.xcresult` succeeded、0 error / 0 warning，commit status `AITRANS CI/full-validation=success`。
- PR #77 exact HEAD fast run `30336122541` 成功后合并；merge follow-up run `30336180421` 成功，artifact 与 merge HEAD `97fcd4174621494e7756fed31a30b7304bae6d73` 一致，`validationProfile=fast`、`validationReason=merge_reuses_successful_candidate_full_validation`，精确复用候选 SHA `86d91084f908adfd4f69a73d0e55568d36276d52` 的成功 full 收据，JUnit 10/10。
- 未跑本机 build / 探针，按规则交给云端验证。本版未运行 UI evidence；真实设备上的裁切方向、紧凑宽度遮挡、Dynamic Type 和 VoiceOver 顺序仍需后续人工运行态检查。真实 Koharu 四件套、Speech corpus 和真实竖排图片 corpus 仍缺失，不刷新 `output/` 或 `metrics/version_history.csv`，不声称 OCR、翻译或识别质量提升。

## v3.12：OCR 结果与预览定位联动
日期：2026-07-28

状态：Agent X 已完成核心实现、本地轻量回归、exact-SHA 云端 full 和 PR 收口；工程正式版本为 `MARKETING_VERSION=3.12`。PR #76 已合入 `smalldata_test`，merge SHA `45b0b57180a7cababdcc55e1c77134a342efa352`；远端 `codeb/v3.12-image-block-selection` 已删除，未触碰 `main`。

核心变更：

- 图片检查列表新增 View 私有 selected block UUID；点击同一行可选择或取消，选中行显示取景框图标、背景与无障碍 value。
- 预览继续遍历完整产品 blocks，只给 ID 匹配的旁贴/覆盖块增加 3pt 边框，筛选不进入产品路径。
- 图片 revision 变化时清除选择；切换“全部 / 待复查”后，若选中行不再可见也清除，避免预览保留无列表上下文的高亮。
- 新增 v3.12 源码合同并接入图片/UI fail-fast 路由。本版不刷新 `output/` 或 `metrics/version_history.csv`，不声称 OCR、翻译或识别质量提升。

验证与遗留：

- v3.12 新合同 5/5，v1.87 与 v2.2-v3.12 全部图片/UI 合同合计 127 项通过；改动 Swift 文件以完整 Xcode toolchain parse 通过，实际 workflow YAML、CI 分层 9/9、版本身份 5/5、工程版本解析 `v3.12`、工程 plist、三份基线 JSON 和 `git diff --check` 均通过。
- 候选 exact SHA `f1ccdc097b8a1e8eff2fc7687b1c0e463f7a3dee` 的云端 full run `30334267143` attempt 1 成功；artifact `aitrans-ci-v3.12-codeb-v3.12-image-block-selection--f1ccdc097b8a-run30334267143-attempt1` 与 version / branch / SHA / run / profile 完全一致，图片/UI 127 项、Speech/home/paste、extended Koharu validator matrix 和 Xcode build 均通过，JUnit 10/10，`.xcresult` succeeded、0 error / 0 warning，commit status `AITRANS CI/full-validation=success`。
- PR #76 exact HEAD fast run `30334677992` 成功后合并；merge follow-up run `30334744315` 成功，artifact 与 merge HEAD `45b0b57180a7cababdcc55e1c77134a342efa352` 一致，`validationProfile=fast`、`validationReason=merge_reuses_successful_candidate_full_validation`，精确复用候选 SHA `f1ccdc097b8a1e8eff2fc7687b1c0e463f7a3dee` 的成功 full 收据，Xcode skip reason 为 `fast_followup_reuses_candidate_full_validation`，JUnit 10/10。
- 未跑本机 build / 探针，按规则交给云端验证。本版不刷新 `output/` 或 `metrics/version_history.csv`，不声称 OCR、翻译或识别质量提升。真实小 bbox 的高亮可见性、Dynamic Type 和 VoiceOver 点击顺序仍需模拟器或真机人工验证。

## v3.11：图片预览状态与独立重试
日期：2026-07-28

状态：Agent X 已完成核心实现、本地轻量回归、exact-SHA 云端 full 和 PR 收口；工程正式版本为 `MARKETING_VERSION=3.11`。PR #75 已合入 `smalldata_test`，merge SHA `c784419f1f6c04f35186f94e245344e12a073561`；远端 `codeb/v3.11-image-preview-state` 已删除，未触碰 `main`。

核心变更：

- 图片预览另存已发布 revision，只有与 Store 当前 `imageTranslationRevision` 一致的缩略图才显示，避免新任务首帧短暂回显旧图。
- 图片 Data 已载入而缩略图未就绪时显示“正在准备预览”，ImageIO 生成失败时显示独立失败反馈，不再误导为“选择图片”。
- 失败态提供“重试预览”，只递增 View 私有 attempt 并重跑下采样，不调用 Store OCR / 翻译 Retry，不改变原图 ownership。
- 新增 v3.11 源码合同并接入图片/UI fail-fast 路由。本版不刷新 `output/` 或 `metrics/version_history.csv`，不声称 OCR、翻译或识别质量提升。

验证与遗留：

- v3.11 新合同 5/5，v1.87 与 v2.2-v3.11 全部图片/UI 合同合计 122 项通过；改动 Swift 文件以完整 Xcode toolchain parse 通过，实际 workflow YAML、CI 分层 9/9、版本身份 5/5、工程版本解析 `v3.11`、工程 plist、三份基线 JSON 和 `git diff --check` 均通过。
- 候选 exact SHA `721041d99529e6222fa9c00b669bdd9be7feae58` 的云端 full run `30333358372` attempt 1 成功；artifact `aitrans-ci-v3.11-codeb-v3.11-image-preview-state--721041d99529-run30333358372-attempt1` 与 version / branch / SHA / run / profile 完全一致，图片/UI 122 项、Speech/home/paste、extended Koharu validator matrix 和 Xcode build 均通过，JUnit 10/10，`.xcresult` succeeded、0 error / 0 warning，commit status `AITRANS CI/full-validation=success`。
- PR #75 exact HEAD fast run `30333750486` 成功后合并；merge follow-up run `30333813351` 成功，artifact 与 merge HEAD `c784419f1f6c04f35186f94e245344e12a073561` 一致，`validationProfile=fast`、`validationReason=merge_reuses_successful_candidate_full_validation`，精确复用候选 SHA `721041d99529e6222fa9c00b669bdd9be7feae58` 的成功 full 收据，Xcode skip reason 为 `fast_followup_reuses_candidate_full_validation`，JUnit 10/10。
- 未跑本机 build / 探针，按规则交给云端验证。本版不刷新 `output/` 或 `metrics/version_history.csv`，不声称 OCR、翻译或识别质量提升。真实慢速解码与失败格式的运行态按钮点击仍需模拟器或真机人工验证。

## v3.10：图片预览有界后台下采样
日期：2026-07-28

状态：Agent X 已完成核心实现、本地轻量回归、exact-SHA 云端 full 和 PR 收口；工程正式版本为 `MARKETING_VERSION=3.10`。PR #74 已合入 `smalldata_test`，merge SHA `a4a60a7edafe046c6047f6e7e27b05fcbffd652e`；远端 `codeb/v3.10-image-preview-downsample` 已删除，未触碰 `main`。

核心变更：

- 新增 `ImagePreviewService`，在后台用 ImageIO 将预览最大边限制为 2048px，应用 EXIF transform，并通过 immediate cache 在后台完成缩略图解码。
- SwiftUI 预览 task 在新 revision 开始时清空旧图，取消会传播给后台任务；只有未取消且 revision 仍匹配的结果才能发布。
- Store 继续持有原始 Data 供 OCR 与导出；不改变 OCR、翻译、bbox、renderer、漫画探针或 Koharu 报告。
- 新增可执行 v3.10 ImageIO evaluator 与合同，并接入图片/UI fail-fast 路由。本版不刷新 `output/` 或 `metrics/version_history.csv`，不声称 OCR、翻译或识别质量提升。

验证与遗留：

- v3.10 新合同 5/5，v1.87 与 v2.2-v3.10 全部图片/UI 合同合计 117 项通过；ImageIO evaluator 验证横图 100x50、EXIF 旋转图 50x100、非法输入与非正上限拒绝。两个改动 Swift 文件以完整 Xcode toolchain parse 通过，两个 workflow YAML、CI 分层 9/9、版本身份 5/5、工程版本解析 `v3.10`、plist/project、三份基线 JSON 和 `git diff --check` 均通过。
- 候选 exact SHA `273a7ff32f63217477fe97744b0b38cd08dc3c1a` 的云端 full run `30332278786` attempt 1 成功；artifact `aitrans-ci-v3.10-codeb-v3.10-image-preview-downsample--273a7ff32f63-run30332278786-attempt1` 与 version / branch / SHA / run / profile 完全一致，图片/UI、Speech/home/paste、extended Koharu validator matrix 和 Xcode build 均通过，JUnit 10/10，`.xcresult` succeeded、0 error / 0 warning，commit status `AITRANS CI/full-validation=success`。
- PR #74 exact HEAD fast run `30332666081` 成功后合并；merge follow-up run `30332762927` 成功，artifact 与 merge HEAD `a4a60a7edafe046c6047f6e7e27b05fcbffd652e` 一致，`validationProfile=fast`、`validationReason=merge_reuses_successful_candidate_full_validation`，精确复用候选 SHA `273a7ff32f63217477fe97744b0b38cd08dc3c1a` 的成功 full 收据，Xcode skip reason 为 `fast_followup_reuses_candidate_full_validation`，JUnit 10/10。
- 未跑本机 build / 探针，按规则交给云端验证。本版不刷新 `output/` 或 `metrics/version_history.csv`，不声称 OCR、翻译或识别质量提升。真实超大 HEIC/JPEG 设备内存峰值仍需 Instruments 人工量测。

## v3.9：图片清空破坏性确认
日期：2026-07-28

状态：Agent X 已完成核心实现、本地轻量回归、exact-SHA 云端 full 和 PR 收口；工程正式版本为 `MARKETING_VERSION=3.9`。PR #73 已合入 `smalldata_test`，merge SHA `c9b84a1fde587bcaad15fe04235fba3021870d9d`；远端 `codeb/v3.9-image-clear-confirmation` 已删除，未触碰 `main`。

核心变更：

- 图片垃圾桶按钮不再直接调用 Store 清理，只打开 View 私有 confirmation dialog。
- 对话框明确说明会删除当前图片、识别结果、译文和导出文件；取消无副作用，只有 destructive 确认按钮调用一次既有 `clearImageTranslation()`。
- 新增 v3.9 contract 并接入图片/UI fail-fast 路由。Store task/source/export/share 清理、OCR、翻译、renderer、漫画探针和 Koharu 报告保持不变。

验证与遗留：

- v3.9 新合同 4/4，v1.87 与 v2.2-v3.9 全部图片/UI 合同合计 112 项通过；改动 Swift 文件以完整 Xcode toolchain parse 通过，两个 workflow YAML、CI 分层 9/9、版本身份 5/5、工程版本解析 `v3.9`、plist/project、三份基线 JSON 和 `git diff --check` 均通过。
- 候选 exact SHA `7adf5edaed883a72b280ed8d183c39e3a7073691` 的云端 full run `30331243876` attempt 1 成功；artifact `aitrans-ci-v3.9-codeb-v3.9-image-clear-confirmation--7adf5edaed88-run30331243876-attempt1` 与 version / branch / SHA / run / profile 完全一致，图片/UI、Speech/home/paste、extended Koharu validator matrix 和 Xcode build 均通过，JUnit 10/10，`.xcresult` succeeded、0 error / 0 warning，commit status `AITRANS CI/full-validation=success`。
- PR #73 exact HEAD fast run `30331626559` 成功后合并；merge follow-up run `30331669084` 成功，artifact 与 merge HEAD `c9b84a1fde587bcaad15fe04235fba3021870d9d` 一致，`validationProfile=fast`、`validationReason=merge_reuses_successful_candidate_full_validation`，精确复用候选 SHA `7adf5edaed883a72b280ed8d183c39e3a7073691` 的成功 full 收据，Xcode skip reason 为 `fast_followup_reuses_candidate_full_validation`。
- 未跑本机 build / 探针，按规则交给云端验证。本版不刷新 `output/` 或 `metrics/version_history.csv`，不声称 OCR、翻译或识别质量提升。

## v3.8：图片来源选择前置 Pro 门控
日期：2026-07-28

状态：Agent X 已完成核心实现、本地轻量回归、exact-SHA 云端 full 和 PR 收口；工程正式版本为 `MARKETING_VERSION=3.8`。PR #72 已合入 `smalldata_test`，merge SHA `140dbab256033348e9984f1b3e4a516cd14ff69a`；远端 `codeb/v3.8-image-entry-pro-gate` 已删除，未触碰 `main`。

核心变更：

- 新增 Store-owned `requestImageTranslationAccess()`，免费模式统一写入“图片翻译需要 Pro”并拒绝进入来源选择流程。
- `ImageCommandBar` 只有在 Pro 模式才实例化真实 `PhotosPicker` 和 file importer 动作；免费模式改为两个 `lock.fill` 命令并展示 Store 反馈 Alert。
- `translateImage(from:)` 与 `translateImageTransfer` 原有底层 Pro guard 保留；授权后的 selection UUID、task ID、source ownership、late callback isolation、Retry、语言、OCR、翻译和 renderer 行为不变。
- 新增 v3.8 contract 并接入图片/UI fail-fast 路由。本版不刷新 `output/` 或 `metrics/version_history.csv`，不声称 OCR、翻译或识别质量提升。

验证与遗留：

- v3.8 新合同 5/5，v1.87 与 v2.2-v3.8 全部图片/UI 合同合计 108 项通过；两个改动 Swift 文件以完整 Xcode toolchain parse 通过，两个 workflow YAML、CI 分层 9/9、版本身份 5/5、工程版本解析 `v3.8`、plist/project、三份基线 JSON 和 `git diff --check` 均通过。
- 候选 exact SHA `93852703c141d617a09e5c753faccb6b6bc6bd64` 的云端 full run `30330438412` attempt 1 成功；artifact `aitrans-ci-v3.8-codeb-v3.8-image-entry-pro-gate--93852703c141-run30330438412-attempt1` 与 version / branch / SHA / run / profile 完全一致，图片/UI、Speech/home/paste、extended Koharu validator matrix 和 Xcode build 均通过，JUnit 10/10，`.xcresult` succeeded、0 error / 0 warning，commit status `AITRANS CI/full-validation=success`。
- PR #72 exact HEAD fast run `30330808106` 成功后合并；merge follow-up run `30330859847` 成功，artifact 与 merge HEAD `140dbab256033348e9984f1b3e4a516cd14ff69a` 一致，`validationProfile=fast`、`validationReason=merge_reuses_successful_candidate_full_validation`，精确复用候选 SHA `93852703c141d617a09e5c753faccb6b6bc6bd64` 的成功 full 收据，Xcode skip reason 为 `fast_followup_reuses_candidate_full_validation`。
- 未跑本机 build / 探针，按规则交给云端验证。仓库仍无真实 Koharu 四件套、Speech corpus 或真实竖排图片 corpus。

## v3.7：图片输入语言 Pro 拒绝无副作用
日期：2026-07-28

状态：Agent X 已完成核心实现、本地轻量回归、exact-SHA 云端 full 和 PR 收口；工程正式版本为 `MARKETING_VERSION=3.7`。PR #71 已合入 `smalldata_test`，merge SHA `b8cb6a298e05756a7d4c574765f1ec80e9444282`；远端 `codeb/v3.7-image-source-pro-feedback` 已删除，未触碰 `main`。

核心变更：

- `selectImageSourceLanguage` 把 `isProUnlocked` 提升到任何读取/写入图片语言状态之前；免费模式拒绝时不再先改全局 `sourceLanguage`，因此不会从图片页静默污染文本页语言。
- Store 写入明确的“图片输入语言设置需要 Pro”反馈，免费模式的非当前菜单项显示 `lock.fill`，图片输入语言菜单用 Alert 展示拒绝，VoiceOver hint 同步说明门槛；授权通过后的完成态重跑、失败/取消 pending 与 v3.6 撤销语义不变。
- v3.4 的目标语言政策保持不变：目标仍由 `selectTargetLanguage` / `canUseLanguage` 判定，不额外阻断英语、中文等免费目标。
- 新增 v3.7 contract 并接入图片/UI fail-fast 路由。不修改 Vision OCR、布局、翻译、renderer、漫画探针或 Koharu 报告。

验证与遗留：

- v3.7 新契约 4/4，v1.87 与 v2.2-v3.6 全部图片/UI 契约合计 103 项通过；两个改动 Swift 文件以完整 Xcode toolchain parse 通过，workflow YAML、CI 分层 9/9、版本身份 5/5、工程版本解析 `v3.7` 和 `git diff --check` 均通过。
- 候选 exact SHA `a29a11fa3e515d8a719ccc3a6691eb6f89cd82fe` 的云端 full run `30329585960` attempt 1 成功；artifact `aitrans-ci-v3.7-codeb-v3.7-image-source-pro-feedback--a29a11fa3e51-run30329585960-attempt1` 与 version / branch / SHA / run / profile 完全一致，图片/UI、Speech/home/paste、extended Koharu validator matrix 和 Xcode build 均通过，JUnit 10/10，`.xcresult` succeeded、0 error / 0 warning，commit status `AITRANS CI/full-validation=success`。
- PR #71 exact HEAD fast run `30329833172` 成功后合并；merge follow-up run `30329885452` 成功，artifact 与 merge HEAD `b8cb6a298e05756a7d4c574765f1ec80e9444282` 一致，`validationProfile=fast`、`validationReason=merge_reuses_successful_candidate_full_validation`，精确复用候选 SHA `a29a11fa3e515d8a719ccc3a6691eb6f89cd82fe` 的成功 full 收据，JUnit 10/10。
- 未跑本机 build / 探针，按规则交给云端验证。本版是授权拒绝与跨页状态一致性修复，不刷新 `output/` 或 `metrics/version_history.csv`，不声称 OCR、翻译或识别质量提升。

## v3.6：图片待重试语言可撤销
日期：2026-07-28

状态：Agent X 已完成核心实现、本地轻量回归、exact-SHA 云端 full 和 PR 收口；工程正式版本为 `MARKETING_VERSION=3.6`。PR #70 已合入 `smalldata_test`，merge SHA `80f80502997833914a528daa284a4bd4daeab43c`；远端 `codeb/v3.6-image-retry-language-reset` 已删除，未触碰 `main`。

核心变更：

- failed/cancelled 图片先选择新的输入或目标语言、再选回 actual-content 语言时，对应 pending Retry 字段归一化为 `nil`；源/目标都没有实际差异后，“重试语言已更新”状态自动消失。
- `imageTranslationDisplayed*Language` 不再以 data/blocks 已产出为前提；Store-owned source 已发布但后续读图失败时，标题、菜单和实际 Retry 仍统一使用 task-scoped content 凭据。选择器在修改全局语言前快照该比较基准，避免目标语言全局更新掩盖差异。
- 完成态即时重跑、运行态冻结、目标语言 Pro 授权、Retry/clear/cancel 与 v3.5 的凭据边界保持不变。
- VoiceOver 提示同步说明可撤销行为；新增 v3.6 contract 并接入图片/UI fail-fast 路由。不修改 Vision OCR、布局、翻译、renderer、漫画探针或 Koharu 报告。

验证与遗留：

- v3.6 新契约 5/5，v1.87 与 v2.2-v3.5 全部图片/UI 契约合计 99 项通过；两个改动 Swift 文件以完整 Xcode toolchain parse 通过，workflow YAML、三份基线 JSON、CI 分层 9/9、版本身份 5/5、工程版本解析 `v3.6` 和 `git diff --check` 均通过。
- 候选 exact SHA `5fc9d6e3c3f232df0b1c4f68b50a741145ad3bd6` 的云端 full run `30328786522` attempt 1 成功；artifact `aitrans-ci-v3.6-codeb-v3.6-image-retry-language-reset--5fc9d6e3c3f2-run30328786522-attempt1` 与 version / branch / SHA / run / profile 完全一致，图片/UI、Speech/home/paste、extended Koharu validator matrix 和 Xcode build 均通过，JUnit 10/10，`.xcresult` succeeded、0 error / 0 warning，commit status `AITRANS CI/full-validation=success`。
- PR #70 exact HEAD fast run `30329087730` 成功后合并；merge follow-up run `30329144284` 成功，artifact 与 merge HEAD `80f80502997833914a528daa284a4bd4daeab43c` 一致，`validationProfile=fast`、`validationReason=merge_reuses_successful_candidate_full_validation`，精确复用候选 SHA `5fc9d6e3c3f232df0b1c4f68b50a741145ad3bd6` 的成功 full 收据，JUnit 10/10。
- 未跑本机 build / 探针，按规则交给云端验证。本版是图片操作与状态反馈一致性修复，不刷新 `output/` 或 `metrics/version_history.csv`，不声称 OCR、翻译或识别质量提升。

## v3.5：图片内容与 Retry 语言分账
日期：2026-07-28

状态：Agent X 已完成核心实现、本地轻量回归、exact-SHA 云端 full 和 PR 收口；工程正式版本为 `MARKETING_VERSION=3.5`。PR #69 已合入 `smalldata_test`，merge SHA `685006272a5a777a19eb21bb036cd9799a3f1365`；远端 `codeb/v3.5-image-retry-credentials` 已删除，未触碰 `main`。

核心变更：

- 新增独立 pending Retry 输入/目标语言。失败或取消后修改菜单不再覆盖 actual-content 凭据，因此已保留的 OCR 块或部分旧译文不会被新选择误标。
- 图片结果区副标题继续显示实际内容语言；输入/目标菜单显示下一次 Retry 选择，并以“重试语言已更新”状态明确区分。完成态仍即时重新识别/翻译，运行态仍冻结。
- Retry 按 pending -> actual-content -> global 顺序选择语言，新任务开始后清空 pending；clear 清空两组，cancel 保留实际内容。v2.2 起的 source ownership、task ID、render/share 失效和晚到回调拒收保持不变。
- 新增 v3.5 contract，并收紧 v1.87/v2.7/v3.0/v3.4 历史契约；不修改 Vision OCR、布局算法、翻译实现、renderer、漫画探针或 Koharu 报告。

验证与遗留：

- v3.5 新契约 5/5，v1.87 与 v2.2-v3.4 全部图片/UI 契约合计 94 项通过；两个改动 Swift 文件以完整 Xcode 工具链 parse 通过，workflow YAML、pbxproj、CI 分层 9/9、版本身份 5/5、工程版本解析 `v3.5` 和 `git diff --check` 均通过。
- 候选 exact SHA `f7603f60f59444ac13938b95c296dbfe859ee033` 的云端 full run `30327978367` attempt 1 成功；artifact `aitrans-ci-v3.5-codeb-v3.5-image-retry-credentials--f7603f60f594-run30327978367-attempt1` 与 version / branch / SHA / run / profile 完全一致，图片/UI、Speech/home/paste、extended Koharu validator matrix 和 Xcode build 均通过，JUnit 10/10，`.xcresult` 可用，commit status `AITRANS CI/full-validation=success`。
- PR #69 exact HEAD fast run `30328253451` 成功后合并；merge follow-up run `30328283787` 成功，artifact 与 merge HEAD `685006272a5a777a19eb21bb036cd9799a3f1365` 一致，`validationProfile=fast`、`validationReason=merge_reuses_successful_candidate_full_validation`，精确复用候选 SHA `f7603f60f59444ac13938b95c296dbfe859ee033` 的成功 full 收据，JUnit 10/10。
- 未跑本机 build / 探针，按规则交给云端验证。本版是图片状态与显示一致性修复，不刷新 `output/` 或 `metrics/version_history.csv`，不声称 OCR、翻译或识别质量提升。

## v3.4：图片 Retry 目标语言凭据
日期：2026-07-28

状态：Agent X 已完成核心实现、本地轻量验证、exact-SHA 云端 full 和 PR 收口；工程正式版本为 `MARKETING_VERSION=3.4`。PR #68 已合入 `smalldata_test`，merge SHA `8f71922b39a1bd2b6d3947bc79fbecd8d1f7385d`；远端 `codeb/v3.4-image-retry-language` 已删除，未触碰 `main`。

核心变更：

- `selectImageTargetLanguage` 改为与输入语言一致的 Store-owned 状态机：完成态先确认 source 文件存在，再更新内容目标并即时重译；失败或取消保留态只在 `canRetryImageTranslation` 时更新下次 Retry 凭据；运行态拒绝改写。
- 移除图片目标语言路径多余的 `isProUnlocked` 硬门槛。Pro 可用性仍由 `selectTargetLanguage` / `canUseLanguage` 统一判定，英语、中文等免费目标不会再被图片完成态额外阻断。
- 新增 v3.4 contract，锁定 source ownership、Retry/clear/cancel 凭据边界、辅助说明与 CI 路由；不修改 Vision OCR、布局、翻译实现、renderer、漫画探针或 Koharu 报告。

验证与遗留：

- v3.4 新契约 5/5、v1.87 与 v2.2-v3.1 既有图片/UI 契约合计 89 项全部通过；两个改动 Swift 文件以完整 Xcode 工具链 parse 通过，workflow YAML、pbxproj、CI 分层 9/9、版本身份 5/5、工程版本解析 `v3.4` 和 `git diff --check` 均通过。
- 候选 exact SHA `8fa0b203fc5090f042b2c99499a7f8e26d6fc236` 的云端 full run `30327280611` attempt 1 成功；artifact `aitrans-ci-v3.4-codeb-v3.4-image-retry-language--8fa0b203fc50-run30327280611-attempt1` 与 version / branch / SHA / run / profile 完全一致，图片/UI、Speech/home/paste、extended Koharu validator matrix 和 Xcode build 均通过，JUnit 10/10，`.xcresult` 可用，commit status `AITRANS CI/full-validation=success`。
- PR #68 exact HEAD fast run `30327602710` 成功后合并；merge follow-up run `30327633420` 成功，artifact 与 merge HEAD `8f71922b39a1bd2b6d3947bc79fbecd8d1f7385d` 一致，`validationProfile=fast`、`validationReason=merge_reuses_successful_candidate_full_validation`，精确复用候选 SHA `8fa0b203fc5090f042b2c99499a7f8e26d6fc236` 的成功 full 收据，JUnit 10/10。
- 未跑本机 build / 探针，按规则交给云端验证。本版是图片操作一致性修复，不刷新 `output/` 或 `metrics/version_history.csv`，不声称 OCR、翻译或识别质量提升。

## v3.3：Koharu mask 拓扑与稳定 assignment
日期：2026-07-28

状态：Agent X 已完成候选实现、本地轻量验证、exact-SHA 云端 full 和 PR 收口；工程正式版本为 `MARKETING_VERSION=3.3`。PR #67 已合入 `smalldata_test`，merge SHA `42be9e1751d1f06d007e15197b5078235c661284`；远端 `codeb/v3.3-koharu-mask-topology` 已删除，未触碰 `main`。

核心变更：

- 新增纯 Swift `evaluateTopology`，在 v3.2 已验证 BubbleMask / SegmentMask 载荷上，统计 expected / foreign / no-bubble / orphan / multiply-assigned glyph pixels，并生成四连通 component 的 Bubble label、TextBox owner、cross-Bubble 和 partition ledger。重复 block / TextBox、重叠 claim、无效 expected Bubble、空 glyph、孤儿或分区不守恒均阻止。
- App `maskTopologyReport` 直接复用 external shadow OCR 的 `stableOneToOneExternalTextBoxShadowMatching`，逐块 block alignment 也改用同一 assignment，不再独立选最大 IoU TextBox / Bubble。新增 `WI-external-mask-topology-linkage` / `G-external-mask-topology-linkage`，探针 JSON / TXT 与 CI manifest 透传逐块、component 和 convergence 证据。
- Python validator 新增独立 `maskTopologyValidation` / `maskTopologyGateReady`，v3.2 payload gate 与 topology gate 分开报告；新 valid fixture 验证两个 TextBox / Bubble 和四个 component 的唯一归属，cross-assignment invalid fixture 验证 payload 仍有效时 topology 仍能拒绝 ambiguity、foreign pixels 和 duplicate components。云端注入真实 v2 archive 时强制 validator / App / convergence 三层 topology 闭环。
- 所有新证据保持 shadow-only，不改 OCR 请求、候选选择、翻译、renderer、`blockPassed`、`failureCategory` 或 `currentBlockSource`；不使用 ground truth 做决策。

验证与遗留：

- v3.3 topology contract 8/8（含 Swift evaluator `-warnings-as-errors`）、v3.2 payload contract 7/7 与 v3.2 evaluator 回归已通过；相关 Swift parse 与 `git diff --check` 通过。
- 候选 exact SHA `83c0bd3335168a8ca7f9ef5af26991f822dffdb8` 的云端 full run `30326605788` attempt 1 成功；artifact `aitrans-ci-v3.3-codeb-v3.3-koharu-mask-topology--83c0bd333516-run30326605788-attempt1` 与 version / branch / SHA / run / profile 完全一致，Koharu topology / payload 及相关静态契约、Speech/home/paste/UI contract 和 Xcode build 均通过，JUnit 10/10，`.xcresult` 可用，commit status `AITRANS CI/full-validation=success`。
- PR #67 exact HEAD fast run `30326937331` 成功后合并；merge follow-up run `30326964832` 成功，artifact 与 merge HEAD `42be9e1751d1f06d007e15197b5078235c661284` 一致，`validationProfile=fast`、`validationReason=merge_reuses_successful_candidate_full_validation`，精确复用候选 SHA `83c0bd3335168a8ca7f9ef5af26991f822dffdb8` 的成功 full 收据，JUnit 10/10。
- 未跑本机 build / 探针，按规则交给云端验证。仓库仍无真实 Koharu 四件套，因此本轮只验收算法、报告、CI 和编译接线，不刷新 `output/` 或 `metrics/version_history.csv`，不声称 OCR、翻译、覆盖或识别质量提升。

## v3.2：Koharu mask 像素载荷契约
日期：2026-07-28

状态：Agent X 已完成候选实现、并行审计、exact-SHA 云端 full 和 PR 收口；工程正式版本为 `MARKETING_VERSION=3.2`。PR #66 已合入 `smalldata_test`，merge SHA `d172d8d171b80ce753eaaf5bf61079ae32b54898`；远端 `codeb/v3.2-koharu-mask-payload` 已删除，未触碰 `main`。

核心变更：

- 外部 artifact contract 新增 v2：BubbleMask / SegmentMask 以内嵌 `rowMajorRLE` 提供真实像素载荷。Python validator 和 Swift evaluator 都限制解码不超过源图像素且总长必须精确匹配；Bubble 重算唯一正 `maskValue` 的 pixel count / tight bbox，Segment 重算 glyph pixels / 四连通 components。v1 摘要继续兼容，但 `maskPayloadGateReady = false`。
- App readiness 一次解码后按 block bbox 输出 Bubble majority mask value、Bubble / Segment pixel coverage 和匹配 TextBox 对块内 Segment pixels 的 containment。v2 payload 无效时返回 `maskPayloadValidationFailed`；所有统计保持 shadow-only。
- convergence 新增 `WI-external-mask-pixel-payload` / `G-external-mask-pixel-payload`。只有 active 非 fixture v2 payload 有效、每块 majority label 与 bbox-selected Bubble 一致、Bubble / Segment 非零且 TextBox containment 至少 `0.5` 时才关闭；ExternalArtifacts stage 消费该 gate。
- CI changed-files 路由、注入 archive hard gate、未加密 manifest 和探针 TXT 同步透传 validator / App / convergence 三层证据；新增 v2 valid / invalid fixtures 和组合契约。

验证与遗留：

- `scripts/test-v32-koharu-mask-payload-contract.py` 7/7 通过，内部真实执行 Swift evaluator `-warnings-as-errors` 编译；相关 Swift 文件 parse、workflow YAML、pbxproj、fixture JSON 和 `git diff --check` 通过。
- 候选 exact SHA `ac822b6186f39de3c73216047ed1126d5596cea4` 的云端 full run `30324330547` 成功；artifact `aitrans-ci-v3.2-codeb-v3.2-koharu-mask-payload--ac822b6186f3-run30324330547-attempt1` 与 version / branch / SHA / run / profile 完全一致，JUnit 10/10，`.xcresult` build succeeded 且 0 error / 0 warning，mask payload contract 7/7，commit status `AITRANS CI/full-validation=success`。
- PR #66 exact HEAD fast run `30324725260` 成功后合并；merge follow-up run `30324971434` 成功，artifact `aitrans-ci-v3.2-smalldata_test--d172d8d171b8-run30324971434-attempt1` 以 `validationProfile=fast`、`validationReason=merge_reuses_successful_candidate_full_validation` 精确复用候选 SHA `ac822b6186f39de3c73216047ed1126d5596cea4` 的成功 full 收据。
- 未跑本机 build / 探针，按规则交给云端验证。仓库没有真实 Koharu 四件套，当前 `output/` 仍是旧 `manifestMissing / stopUntilArtifactsProvided` 证据；本轮不刷新 `output/` 或 `metrics/version_history.csv`，不声称 OCR、翻译、覆盖或识别质量提升。

## v3.1：图片 OCR 待复查筛选
日期：2026-07-28

状态：Agent X 已完成核心候选实现、本地轻量回归、独立复审、核心与版本收口 exact-SHA 云端 full；工程正式版本为 `MARKETING_VERSION=3.1`。PR #65 已合入 `smalldata_test`，merge SHA `54c6ad5b548b093406c1a8387d4e35519290e627`；远端 `codeb/v3.1-image-ocr-review-filter` 已删除，未触碰 `main`。

核心变更：

- 图片识别结果新增“全部 / 待复查”分段筛选，并显示各自数量；待复查严格定义为 confidence 低于 `50%`，或方向证据为 nil / unknown，重叠原因只计一个 block，原始顺序不变。
- 筛选状态只属于 `ImageTranslationPanel` 的本地展示状态。预览、覆盖渲染、稳定导出、分享、翻译和持久化仍消费完整 `imageTranslationBlocks`，不会因列表筛选丢失内容。
- 待复查行以图标和文字分别显示“低置信”“方向待定”；筛选为空时显示“无需复查”。共享判定由 `ImageOCRResultSummary` 持有，confidence 与阈值均夹取到 `0...1`，恰好 `0.5` 不算低置信。
- 新增 `ImageOCRReviewFilter`、纯 Swift 产品模型 evaluator 和 v3.1 Python 契约，并接入 v1.87 / v2.2-v3.1 fail-fast 图片 UI CI step；同步修正 v3.0 契约，使其接受共享 helper 与分组 changed-files 路由，同时继续锁定严格阈值语义。独立复审后将列表、预览与 Store 重渲染断言收紧到各自源码作用域，避免全文件 substring 对错误接线产生假绿。

验证与遗留：

- v1.87、v2.2-v3.1 图片/UI 契约共 84 项通过；CI validation tier / version identity 契约 14 项通过。四份改动 Swift 源码 parse、Xcode 工程 plist、workflow YAML、ground truth 与现有 output JSON 解析、工程版本唯一解析为 `v3.0` 和 `git diff --check` 均通过。
- 核心 SHA `281c74ea9c8b00c522dec6edc9682e1f46e51b4f` 的云端 full run `30321376115` attempt 1 成功；artifact `aitrans-ci-v3.1-codeb-v3.1-image-ocr-review-filter--281c74ea9c8b-run30321376115-attempt1` 与 version / branch / SHA / run / profile 完全一致，图片/UI 84 项、Speech/home/paste、extended Koharu validator matrix 和 Xcode build 均通过，JUnit 10/10，`.xcresult` build succeeded，commit status `AITRANS CI/full-validation=success`。
- 版本收口 SHA `88da91e050928a42164233d75d9b12f696f4eb9b` 的云端 full run `30321736785` attempt 1 成功；artifact `aitrans-ci-v3.1-codeb-v3.1-image-ocr-review-filter--88da91e05092-run30321736785-attempt1` 与 identity 完全一致，`MARKETING_VERSION=3.1`、Xcode build success、JUnit 10/10、`.xcresult` 0 error / 0 warning，commit status `AITRANS CI/full-validation=success`。本次只改工程版本和入口文档，领域合同按 changed-files 路由跳过，由核心 full 提供证据。
- 独立复审发现全文件 substring 可能让错误预览接线假绿；加固 HEAD `1bb8ee258667240e705a5ba2311e9eae4417f0a5` 将列表、预览与 Store 重渲染断言限定到各自源码作用域。云端 full run `30322310824` attempt 1 成功，artifact identity 完全一致，图片/UI 84 项通过，JUnit 10/10；manifest 明确 `xcodeBuildRequired=false`、`xcodeBuildSkippedReason=non_app_build_related_full_validation`，不冒充编译证据，编译继续由版本 SHA 的成功 `.xcresult` 证明。
- PR #65 exact HEAD fast run `30322411646` 成功后合并；merge follow-up run `30322449624` 成功，artifact `aitrans-ci-v3.1-smalldata_test--54c6ad5b548b-run30322449624-attempt1` 以 `validationProfile=fast`、`validationReason=merge_reuses_successful_candidate_full_validation` 精确复用候选 HEAD `1bb8ee258667240e705a5ba2311e9eae4417f0a5` 的成功 full 收据，JUnit 10/10。
- 未跑本机 build / 探针，按规则交给云端验证。本版不修改 Vision 请求、OCR layout、漫画探针、翻译、ground truth、`metrics/version_history.csv` 或 `output/`，不声称 OCR 字符准确率提升。

## v3.0：图片 OCR 复查与重新识别
日期：2026-07-27

状态：Agent X 已完成核心候选实现、本地轻量回归、核心与版本收口 exact-SHA 云端 full；工程正式版本为 `MARKETING_VERSION=3.0`。PR #64 已合入 `smalldata_test`，merge SHA `89b295c46ed84529db144ee2f104c2390f9612a6`；远端 `codeb/v3.0-image-ocr-rerun` 已删除，未触碰 `main`。

核心变更：

- 新增纯模型 `ImageOCRResultSummary`，从当前图片 blocks 计算翻译覆盖、平均 Vision confidence、低于 `50%` 的块数，以及 horizontal / vertical / unknown 方向分账；confidence 先夹取到 `0...1`，空结果不虚构平均值。
- 图片识别结果标题显示平均置信、低置信块、竖排与方向待定数量，帮助用户定位需要复查的 OCR 结果；不读取 ground truth，不改变 OCR 候选或排序。
- `.translated` 且 Store-owned 原图仍存在时显示“重新识别”。View 只调用 Store API；Store 复用内容输入/目标语言和既有 `retryImageTranslation()`，因此保留 task ID 隔离、源文件 ownership、render/share 失效和晚到结果拒收。
- 新增 v3.0 真实产品 summary evaluator 与 Python 源码合同，并接入 v1.87 / v2.2-v3.0 fail-fast UI interaction CI step。

验证与遗留：

- v1.87、v2.2-v3.0 图片/UI 契约共 78 项通过；CI validation tier / version identity 契约 14 项通过。三份改动 Swift 源码 parse、工程 plist、workflow YAML、ground truth 与现有 output JSON 解析、工程版本唯一解析为 `v2.9` 和 `git diff --check` 均通过；尚待云端 exact-SHA full。
- 核心 SHA `2169eb9cb156406c524f57583ae79cb300d4919f` 的云端 full run `30234737017` attempt 1 成功；artifact `aitrans-ci-v3.0-codeb-v3.0-image-ocr-rerun--2169eb9cb156-run30234737017-attempt1` 与 version / branch / SHA / run / profile 完全一致，图片/UI、Speech/home/paste、extended Koharu validator matrix 和 Xcode build 均通过，JUnit 10/10，`.xcresult` build succeeded，commit status `AITRANS CI/full-validation=success`。
- 版本收口 SHA `c2886c10ee2c19079df7234cbf224db9c8dd8df2` 的云端 full run `30234997262` attempt 1 成功；artifact `aitrans-ci-v3.0-codeb-v3.0-image-ocr-rerun--c2886c10ee2c-run30234997262-attempt1` 与 identity 完全一致，`MARKETING_VERSION=3.0`、Xcode build success、JUnit 10/10、`.xcresult` build succeeded，commit status `AITRANS CI/full-validation=success`。本次仅改工程版本和入口文档，领域合同按 changed-files 路由跳过，由核心 full 提供证据。
- PR #64 exact HEAD fast run `30235306860` 成功后合并；merge follow-up run `30235344391` 成功，artifact `aitrans-ci-v3.0-smalldata_test--89b295c46ed8-run30235344391-attempt1` 以 `validationProfile=fast`、`validationReason=merge_reuses_successful_candidate_full_validation` 复用候选 HEAD `ffbe2eca571f99e9ac85a25c9a743609a27c096b` 的成功 full 收据，JUnit 10/10。
- 未跑本机 build / 探针，按规则交给云端验证。本版不改 Vision 请求、OCR layout、漫画探针、翻译或 metrics，不声称 OCR 字符准确率提升，也不刷新 output。

## v2.9：图片重渲染状态与重试
日期：2026-07-27

状态：Agent X 已完成核心候选实现、本地轻量回归、核心与版本收口 exact-SHA 云端 full；工程正式版本为 `MARKETING_VERSION=2.9`。PR #63 已合入 `smalldata_test`，merge SHA `1154e474627084544d52a5230340c56b986f2824`；远端 `codeb/v2.9-image-render-feedback` 已删除，未触碰 `main`。

核心变更：

- Store 新增图片导出重渲染 `idle / rendering / failed` 状态；覆盖模式切换开始前发布 rendering，成功、取消、失败和内容失效均按 render ID / task ID 收口，旧 render 不覆盖新内容。
- rendering 时 segmented Picker 和 Store API 双重拒绝重复模式切换；当前失败使用 danger 状态并显示具体消息，提供 Store-owned“重试导出”入口。
- 无 staging URL 不再静默 return 并永久停留在活动态，而是进入可重试失败；既有稳定导出 ownership、staging 清理、分享状态、OCR、翻译、Koharu 和探针不变。
- 新增 v2.9 纯 Swift 状态 evaluator 与 Python 源码合同，并接入 v1.87 / v2.2-v2.9 fail-fast UI interaction CI step。

验证与遗留：

- v1.87、v2.2-v2.9 图片/UI 契约共 73 项通过；CI validation tier / version identity 契约 14 项通过。三份改动 Swift 源码 parse、工程 plist、workflow YAML、ground truth 与现有 output JSON 解析、`git diff --check` 均通过。
- 核心 SHA `42eac84cdbf111e948ff32296d1fa73d1d7938c9` 的云端 full run `30233705540` attempt 1 成功；artifact `aitrans-ci-v2.9-codeb-v2.9-image-render-feedback--42eac84cdbf1-run30233705540-attempt1` 与 version / branch / SHA / run / profile 完全一致，图片/UI、Speech/home/paste、extended Koharu validator matrix 和 Xcode build 均通过，JUnit 10/10，`.xcresult` build succeeded，commit status `AITRANS CI/full-validation=success`。
- 版本收口 SHA `37ea55b4c75597852a87163ac67ee9c77daeaaed` 的云端 full run `30234070675` attempt 1 成功；artifact `aitrans-ci-v2.9-codeb-v2.9-image-render-feedback--37ea55b4c755-run30234070675-attempt1` 与 identity 完全一致，`MARKETING_VERSION=2.9`、Xcode build success、JUnit 10/10、`.xcresult` build succeeded，commit status `AITRANS CI/full-validation=success`。本次仅改工程版本和入口文档，领域合同按 changed-files 路由跳过，由核心 full 提供证据。
- PR #63 exact HEAD fast run `30234308535` 成功后合并；merge follow-up run `30234339482` 成功，artifact `aitrans-ci-v2.9-smalldata_test--1154e4746270-run30234339482-attempt1` 以 `validationProfile=fast`、`validationReason=merge_reuses_successful_candidate_full_validation` 复用候选 HEAD `c9f0b55e4ae9d8e6a786917fd2be63740598d6dc` 的成功 full 收据，JUnit 10/10。
- 未跑本机 build / 探针，按规则交给云端验证；`probe_mode=skip`，没有刷新 output 或漫画指标。真实 Koharu 四件套仍缺失，validator 正确报告 `manifestMissing` / `stopUntilArtifactsProvided`。

## v2.8：图片分享准备反馈
日期：2026-07-27

状态：Agent X 已完成核心候选实现、本地轻量回归，以及核心和版本收口 exact-SHA 云端 full；工程正式版本为 `MARKETING_VERSION=2.8`。PR #62 已合入 `smalldata_test`，merge SHA `9ec7ef02febc7a4dc62556a1019f1afa2cd7b57c`；远端 `codeb/v2.8-image-share-feedback` 已删除，未触碰 `main`。

核心变更：

- Store 新增 request-scoped `idle / preparing / failed` 图片分享状态；异步硬链接/复制开始前发布 preparing，当前请求成功复位，当前请求失败保留独立消息，旧请求不得覆盖新状态。
- 图片页准备分享时将导出按钮切换为“准备中”并禁用重复点击；页面标题和状态行优先显示分享进度/失败，失败使用 danger，不再让已翻译状态掩盖分享错误。
- 既有 share request、View presentation identity、可读文件名、目录 ownership 和删除失败重试保持不变；dismiss、内容失效和页面离开继续统一清理并复位反馈。本版不修改 OCR、Koharu、翻译、renderer、探针或 metrics。
- 新增 v2.8 纯 Swift 状态 evaluator 与 Python 源码合同，并接入 v1.87 / v2.2-v2.8 fail-fast UI interaction CI step。

验证与遗留：

- v2.8 6/6、v2.7 9/9、v2.6 7/7、v2.5 10/10、v2.4 9/9、v2.3 4/4、v2.2 10/10、v1.87 12/12、CI 分层 9/9、版本身份 5/5，以及三份修改 Swift parse、Xcode 工程 lint、YAML 解析、三份 JSON 解析和 `git diff --check` 已通过。未跑本机 build / 探针，按规则交给云端验证。
- 首个核心 SHA `4442166e026c846ae004be753851cf08d913807e` 的云端 full run `30232563563` 中全部合同通过，但 Xcode build 因两个 `statusTone` getter 在多语句函数中继续使用无上下文隐式 enum member 而失败；已按结果包 `xcodebuild.log` 改为显式 return，并加入合同防回归。该失败 run 不作为编译收据。
- 修复后核心 SHA `c9ce5681532289c905fd4d5b3cecdac89be922a7` 的云端 full run `30232677854` attempt 1 成功；artifact `aitrans-ci-v2.8-codeb-v2.8-image-share-feedback--c9ce56815322-run30232677854-attempt1` 与 version / branch / SHA / run / profile 完全一致，v2.8 与既有图片合同、Speech/home/paste、extended Koharu validator matrix 和 Xcode build 均通过，JUnit 10/10，`.xcresult` 0 error / 0 warning，commit status `AITRANS CI/full-validation=success`。
- 版本收口 SHA `f43e957d89ad2ad2716641ee61697e2ed855cf65` 的云端 full run `30233086479` attempt 1 成功；artifact `aitrans-ci-v2.8-codeb-v2.8-image-share-feedback--f43e957d89ad-run30233086479-attempt1` 与 identity 完全一致，`MARKETING_VERSION=2.8`、Xcode build success、JUnit 10/10、`.xcresult` 0 error / 0 warning，commit status `AITRANS CI/full-validation=success`。本次只改工程版本和入口文档，领域合同按 changed-files 路由跳过，由核心 full 提供证据。
- 纯文档 follow-up fast run `30233244480` 正确复用父 SHA `f43e957d89ad2ad2716641ee61697e2ed855cf65` 的 full-validation success；PR fast run `30233276603` 成功。merge fast run `30233308760` 的 artifact 与 merge HEAD `9ec7ef02febc7a4dc62556a1019f1afa2cd7b57c` 一致，`validationReason=merge_reuses_successful_candidate_full_validation`，精确复用第二父候选 SHA `aa6c8a4b636741ea5334bc2aec1d132df012fd65` 的 propagated success。

## v2.7：图片 OCR 输入语言与方向闭环
日期：2026-07-27

状态：Agent X 已完成核心候选实现、本地轻量回归、两轮独立复审，以及核心和版本收口 exact-SHA 云端 full；工程正式版本为 `MARKETING_VERSION=2.7`。PR #61 已合入 `smalldata_test`，merge SHA `f98426f17ae8bfc2a6c2937008ca4f4f6436aaf4`；远端 `codeb/v2.7-image-ocr-direction` 已删除，未触碰 `main`。

核心变更：

- 图片页新增显式输入语言菜单，不再要求用户回到文本页猜测当前 Vision OCR 语言。Store 从 `.loading` 前同时冻结图片输入/目标语言；失败、取消和跨页全局语言修改不覆盖当前内容凭据，清空才重置，已完成图片改输入语言会从 Store-owned source 重跑 OCR 和翻译。
- `VisionOCRService` 增加保守方向证据。只有日语/中文 prior、bbox 高宽比至少 `1.6`、高度至少 `0.035`，并包含多字 CJK run 或具有同列邻居且没有近同行邻居时才判 vertical；同行单字 CJK 碎片、孤立单字、非 CJK 高框和近方形 CJK 保持 unknown / 原横排 fallback。横排上到下、行内左到右；竖排列右到左、列内上到下；两类 observation 分开聚类。
- `ImageTranslationBlock` 新增可选 `sourceDirection`、`directionConfidence` 和 `directionReason`，保留后续 Koharu 风格布局证据，同时兼容旧 Codable 数据。本版不修改覆盖 renderer、漫画探针、ground truth、模型或翻译 prompt。
- 新增 v2.7 纯 Swift 几何 evaluator 与 Python 源码合同，并接入 v1.87 / v2.2-v2.7 fail-fast UI interaction CI step。
- 两轮独立复审发现并修复：带容差的成对比较器可能形成排序环；行优先输入只检查最后 cluster 会拆散交错双栏；同行单字 CJK 高框可能误升竖排；失败/取消保留态不能为下次 Retry 更新输入凭据；evaluator 重复实现产品算法；布局引擎文件未命中 CI 合同路由。当前 evaluator 直接链接产品引擎，并穷举 mixed、比较器链和双栏 fixture 的输入排列。

验证与遗留：

- v2.7 9/9、v2.6 7/7、v2.5 10/10、v2.4 9/9、v2.3 4/4、v2.2 10/10、v1.87 12/12、CI 分层 9/9、版本身份 5/5，以及五份修改 Swift parse、Xcode 工程 lint、YAML 解析、三份 JSON 解析和 `git diff --check` 已通过。独立复审的实现与合同问题均已修复。
- 核心 SHA `61168f3f81a3bd1b87cfa724134eefdc47f1d289` 的云端 full run `30231620821` attempt 1 成功；artifact `aitrans-ci-v2.7-codeb-v2.7-image-ocr-direction--61168f3f81a3-run30231620821-attempt1` 与 version / branch / SHA / run / profile 完全一致，v2.7 9/9、既有图片合同、Speech/home/paste、extended Koharu validator matrix 和 Xcode build 均通过，JUnit 10/10，`.xcresult` 无 error / warning summary，commit status `AITRANS CI/full-validation=success`。
- 版本收口 SHA `41e9a1df4591752de13d5cd37a16addd35fa7793` 的云端 full run `30231918177` attempt 1 成功；artifact `aitrans-ci-v2.7-codeb-v2.7-image-ocr-direction--41e9a1df4591-run30231918177-attempt1` 与 identity 完全一致，`MARKETING_VERSION=2.7`、Xcode build success、JUnit 10/10、`.xcresult` 0 error / 0 warning，commit status `AITRANS CI/full-validation=success`。本次只改工程版本和入口文档，领域合同按 changed-files 路由跳过，由核心 full 提供证据。
- 纯文档 follow-up fast run `30232087193` 正确复用父 SHA `41e9a1df4591752de13d5cd37a16addd35fa7793` 的 full-validation success；PR fast run `30232132423` 成功。merge fast run `30232173778` 的 artifact 与 merge HEAD `f98426f17ae8bfc2a6c2937008ca4f4f6436aaf4` 一致，`validationReason=merge_reuses_successful_candidate_full_validation`，精确复用第二父候选 SHA `8122de32ecf2fbec69b36b77b8831567a6325025` 的 propagated success，JUnit 10/10。
- 合成 bbox fixture 只证明排序、聚类和 fallback 契约，不证明真实日文 OCR 字符准确率提升。本轮不刷新 `output/`，不追加 `metrics/version_history.csv`；真实竖排收益需要后续合法日文图片 corpus 或人工图像验收。
- 未跑本机 build / 探针，按规则交给云端验证。

## v2.6：图片分享文件生命周期
日期：2026-07-26

状态：Agent X 已完成候选实现、本地轻量验证、独立复审，以及核心和版本收口 exact-SHA 云端 full；工程正式版本为 `MARKETING_VERSION=2.6`。PR #60 已合入 `smalldata_test`，merge SHA `b4c35299212c3948d0e2b3e3f6d7da6395107d11`；远端 `codeb/v2.6-image-share-lifecycle` 已删除，未触碰 `main`。

核心变更：

- 内部稳定导出继续保留 v2.5 的 Store marker + render UUID 安全格式；用户点击“导出”时，Store 在专用 `ImageTranslationShares/<share UUID>/` 中异步创建 `<base>-translated.png` 硬链接，硬链接不可用时回退复制，系统分享只看到人类可读 leaf filename。
- Store share request ID 同时核对当前 export URL，View presentation ID 另行阻止旧 Task 用 `nil` 关闭较新的 sheet；重复点击、dismiss、新任务、clear、模式重渲染或 View 离开都会失效旧请求并清理 Store-owned 分享目录，晚到 A 不得覆盖 B 或重新发布已失效 URL。
- 启动时只接管分享根目录直属、名称为真实 UUID 的常规目录；outside、nested、任意目录名、symlink 和 dangling symlink 拒绝。删除失败保留私有 ownership，后续生命周期重试。
- 新增 v2.6 纯 Swift share lifecycle evaluator 与 Python 源码合同，并接入 v1.87 / v2.2 / v2.3 / v2.4 / v2.5 / v2.6 fail-fast UI interaction CI step。

验证与遗留：

- v2.6 7/7、v2.5 10/10、v2.4 9/9、v2.3 4/4、v2.2 10/10、v1.87 12/12、Store/View Swift parse 与 `git diff --check` 通过。
- 核心 SHA `dfe459a9a5be265422c9d4bfd80dc0b0db6dc914` 的云端 full run `30229667313` attempt 1 成功；artifact `aitrans-ci-v2.6-codeb-v2.6-image-share-lifecycle--dfe459a9a5be-run30229667313-attempt1` 与 version / branch / SHA / run / profile 完全一致，v2.6 7/7、v2.5 10/10、v2.4 9/9、v2.3 4/4、v2.2 10/10、v1.87 12/12、Speech/home/paste、extended Koharu validator matrix 和 Xcode build 均通过，JUnit 10/10，`.xcresult` 可用，commit status `AITRANS CI/full-validation=success`。独立复审未发现 P1/P2/P3 问题。
- 版本收口 SHA `e6e9e0405151cfcf26c305ba18949ebc5b363051` 的云端 full run `30230077269` attempt 1 成功；artifact `aitrans-ci-v2.6-codeb-v2.6-image-share-lifecycle--e6e9e0405151-run30230077269-attempt1` 与 identity 完全一致，`MARKETING_VERSION=2.6`、Xcode build success、JUnit 10/10，commit status `AITRANS CI/full-validation=success`。本次只改工程版本和入口文档，领域合同按 changed-files 路由跳过，由父核心 full 提供证据。
- 纯文档 follow-up fast run `30230251036` 正确复用父 SHA `e6e9e0405151cfcf26c305ba18949ebc5b363051` 的 full-validation success；PR fast run `30230285101` 成功。merge fast run `30230317879` 的 artifact 与 merge HEAD `b4c35299212c3948d0e2b3e3f6d7da6395107d11` 一致，`validationReason=merge_reuses_successful_candidate_full_validation`，精确复用第二父候选 SHA `f030428f5c0d0657c5dbbfcf1e610308204999e3` 的 success，静态检查成功且 Xcode 按规则跳过。
- 未跑本机 build / 探针，按规则交给云端验证。本轮不改变 Vision OCR、Koharu、翻译或覆盖算法，不声称质量指标提升，不刷新 `output/`，不追加 `metrics/version_history.csv`。

## v2.5：图片 workspace 异常恢复
日期：2026-07-26

状态：Agent X 已完成候选实现、本地轻量验证、两轮独立复审，以及核心与版本收口 exact-SHA 云端 full；工程正式版本为 `MARKETING_VERSION=2.5`。PR #59 已合入 `smalldata_test`，merge SHA `322296e2bb8a664706a332bc65c610c917557dbc`；远端 `codeb/v2.5-image-workspace-recovery` 已删除，未触碰 `main`。

核心变更：

- App 正常启动时扫描 `ImageTranslations` 直属文件，分账接管 `aitrans-export-<render UUID>-<base>-translated.png` 稳定导出、`<task UUID>-<name>` 输入副本和 `.<base>-translated-<render UUID>.staging.png`，清理上次崩溃、强退或升级遗留的不可恢复文件；`performsStartupWork=false` 的 Preview / 测试 Store 不扫描。
- input、staging 与 stable export 共享目录、文件名 kind、regular-file 和 symlink 安全门槛；正常运行中的 input/staging 删除也必须显式传入可信 workspace，wrong-kind、任意文件名、目录外、嵌套、`..` escape、symlink 和 dangling symlink 均拒绝。
- 启动或正常运行清理失败的 input/staging 进入独立 orphan ownership 集合，后续新任务、clear 或重渲染继续重试；稳定导出必须带 Store marker 与真实 render UUID，普通 `*-translated.png` 和 task UUID source 不再被误认。v2.3 Retry source 边界保持不变。
- 新增 v2.5 纯 Swift workspace recovery evaluator 与 Python 源码合同，并接入 v1.87 / v2.2 / v2.3 / v2.4 / v2.5 fail-fast UI interaction CI step；旧合同同步要求可信 workspace 参数。

验证与遗留：

- v2.5 10/10、v2.4 9/9、v2.3 4/4、v2.2 10/10、v1.87 12/12、CI 分层 9/9、版本身份 5/5、Swift parse 与 `git diff --check` 通过；v1.87 旧 staging 断言已升级为可信 workspace 签名，并保留发布身份门控与初始 staging 清理约束。
- 核心 SHA `8626c9c3799b3e4a6b65249c9fc28ac993b448e4` 的云端 full run `30205285339` attempt 1 成功；artifact `aitrans-ci-v2.5-codeb-v2.5-image-workspace-recovery--8626c9c3799b-run30205285339-attempt1` 与 version / branch / SHA / run / profile 完全一致，v2.5 10/10、v2.4 9/9、v2.3 4/4、v2.2 10/10、v1.87 12/12、Speech/home/paste、extended Koharu validator matrix 和 Xcode build 均通过，JUnit 10/10，`.xcresult` build succeeded 且 issue summaries 为空，commit status `AITRANS CI/full-validation=success`。
- 版本收口 SHA `efba55b0d59644801fd995207fbd33a3e41fdedb` 的云端 full run `30205587693` attempt 1 成功；artifact `aitrans-ci-v2.5-codeb-v2.5-image-workspace-recovery--efba55b0d596-run30205587693-attempt1` 与 identity 完全一致，`MARKETING_VERSION=2.5`、Xcode build success、JUnit 10/10、`.xcresult` succeeded 且 0 error / 0 warning，commit status `AITRANS CI/full-validation=success`。本次仅改工程版本和入口文档，领域合同按 changed-files 路由跳过，由父核心 full 提供证据。
- 纯文档 follow-up fast run `30205758867` 正确复用父 SHA `efba55b0d59644801fd995207fbd33a3e41fdedb` 的 full-validation success；PR fast run `30205796901` 成功。merge fast run `30205833063` 的 artifact `aitrans-ci-v2.5-smalldata_test--322296e2bb8a-run30205833063-attempt1` 与 merge HEAD 一致，`validationReason=merge_reuses_successful_candidate_full_validation`，精确复用第二父候选 SHA `bab9b050ab99c31a154f02781aa71c14ef5bf834` 的 success，JUnit 10/10。
- 未跑本机 build / 探针，按规则交给云端验证。本轮不改变 Vision OCR、Koharu、翻译或覆盖算法，不声称质量指标提升，不刷新 `output/`，不追加 `metrics/version_history.csv`。
- 已知升级遗留：v2.4 的 `<base>-translated.png` 没有 marker 或 receipt，无法与同后缀用户源文件无歧义区分；v2.5 为避免误删不自动接管这批 legacy 文件。新 marker 中的 render UUID 会出现在系统分享文件名，后续版本应在 Store-owned 分享层提供人类可读建议文件名，不在 View 直接创建临时副本。

## v2.4：图片稳定导出生命周期
日期：2026-07-26

状态：Agent X 已完成候选实现、两轮独立复审、核心与版本收口 exact-SHA 云端 full，工程正式版本为 `MARKETING_VERSION=2.4`。PR #58 已合入 `smalldata_test`，merge SHA `63f6f109703c31207dd4b8027cdecf73994e8b32`；远端 `codeb/v2.4-image-export-lifecycle` 已删除，未触碰 `main`。

核心变更：

- 新图片任务、清空和模式重渲染开始时，删除当前 Store-owned 稳定导出 PNG，避免 UI 清空 URL 后不同文件名的旧导出继续在 `Application Support/ImageTranslations` 累积。
- 稳定导出使用独立私有 ownership 集合；两个真实 publish 点统一登记 ownership。App 启动时接管并清理上次进程遗留的稳定导出，避免重启或升级后旧 PNG 永久不可达。
- 统一 discard 会立即撤销公开 share URL，只允许删除 `ImageTranslations` 直属、非隐藏 `*-translated.png` 常规文件；同目录 source、staging、目录外、嵌套、`..` escape、symlink 和 dangling symlink 均拒绝。删除失败项保留 ownership，后续新任务、clear 或重渲染继续重试。
- 取消仍保留已发布 source 和 v2.3 Retry 边界；stale renderer 仍只清理自己的 staging 文件，A/B 反序或当前 render failure 不得发布过期 export。
- 新增 v2.4 纯 Swift 文件生命周期 evaluator 与 Python 源码合同，并接入 v1.87 / v2.2 / v2.3 / v2.4 fail-fast UI interaction CI step。

验证与遗留：

- v2.4 9/9、v2.3 4/4、v2.2 10/10、v1.87 12/12、Swift parse、workflow YAML 与 `git diff --check` 通过。
- 核心 SHA `a48fb2a461160ebd4445347dcb5c094dcc16e400` 的云端 full run `30203732662` attempt 1 成功；artifact `aitrans-ci-v2.4-codeb-v2.4-image-export-lifecycle--a48fb2a46116-run30203732662-attempt1` 与 version / branch / SHA / run / profile 完全一致，v2.4 9/9、v2.3 4/4、v2.2 10/10、v1.87 12/12、Speech/home/paste、extended Koharu validator matrix 和 Xcode build 均通过，JUnit 10/10，`.xcresult` succeeded 且 0 error / 0 warning，commit status `AITRANS CI/full-validation=success`。
- 版本收口 SHA `cac60468310d2a287b26a07ea42f840292002f89` 的云端 full run `30204029328` attempt 1 成功；artifact `aitrans-ci-v2.4-codeb-v2.4-image-export-lifecycle--cac60468310d-run30204029328-attempt1` 与 version / branch / SHA / run / profile 完全一致，Xcode build succeeded、JUnit 10/10、`.xcresult` 0 error / 0 warning，commit status `AITRANS CI/full-validation=success`。本次仅改工程版本和入口文档，领域契约按 changed-files 路由跳过，由父核心 full 提供证据。
- 纯文档 follow-up fast run `30204223555` 正确复用父 SHA `cac60468310d2a287b26a07ea42f840292002f89` 的 full-validation success；PR fast run `30204270154` 成功。merge fast run `30204295914` 的 artifact `aitrans-ci-v2.4-smalldata_test--63f6f109703c-run30204295914-attempt1` 与 merge HEAD 一致，`validationReason=merge_reuses_successful_candidate_full_validation`，精确复用第二父候选 SHA `1fc7d229be72e01a22f02e4b83c04d441d651fe3` 的 success，JUnit 10/10。
- 未跑本机 build / 探针，按规则交给云端验证。本轮不改变 Vision OCR、Koharu、翻译或覆盖算法，不声称质量指标提升，不刷新 `output/`，不追加 `metrics/version_history.csv`。

## v2.3：图片取消后重试一致性
日期：2026-07-26

状态：Agent X 已完成候选实现、独立审计、核心与版本收口 exact-SHA 云端 full，工程正式版本为 `MARKETING_VERSION=2.3`。PR #57 已合入 `smalldata_test`，merge SHA `4159251340375aec9f518ea03222f7a81d79b8d7`；远端 `codeb/v2.3-image-cancel-retry` 已删除，未触碰 `main`。

核心变更：

- v2.2 已在取消后保留完成 sandbox 发布的当前 source，但 retry 门槛只接受 `.failed`，导致取消后的 `.idle` 没有可见重试入口。v2.3 在 source 文件真实存在时允许 `.idle` / `.failed` 显示重试；transfer 尚未落盘的取消仍无重试，translated 结果继续走重译控制而不是 Retry，clear 继续删除 source。
- 新增独立 v2.3 纯 Swift evaluator 与 Python contract，并接入 fail-fast UI interaction CI step；任一 v1.87 / v2.2 / v2.3 契约失败都会阻塞候选 full。

验证与遗留：

- v2.3 4/4、v2.2 10/10、v1.87 12/12、Swift parse、workflow YAML 和 `git diff --check` 通过。未跑本机 build / 探针，按规则交给云端验证。
- 核心 SHA `ec41f72c0fc53ccf2a52100e1806888641910857` 的云端 full run `30202633449` attempt 1 成功；artifact `aitrans-ci-v2.3-codeb-v2.3-image-cancel-retry--ec41f72c0fc5-run30202633449-attempt1` 与 version / branch / SHA / run / profile 完全一致，v2.3 4/4、v2.2 10/10、v1.87 12/12、Speech/home/paste 和 Xcode build 均通过，JUnit 10/10，`.xcresult` succeeded 且 0 error / 0 warning，commit status `AITRANS CI/full-validation=success`。
- 版本收口 SHA `9367267260bb879a56a52c1c85804f638ad13dd9` 的云端 full run `30202806922` attempt 1 成功；artifact `aitrans-ci-v2.3-codeb-v2.3-image-cancel-retry--9367267260bb-run30202806922-attempt1` 与 version / branch / SHA / run / profile 完全一致，Xcode build succeeded、JUnit 10/10、`.xcresult` 0 error / 0 warning，commit status `AITRANS CI/full-validation=success`。本次仅改工程版本和入口文档，领域契约按 changed-files 路由跳过，由父核心 full 提供证据。
- 纯文档 follow-up fast run `30203035151` 正确复用父 SHA `9367267260bb879a56a52c1c85804f638ad13dd9` 的 full-validation success；PR fast run `30203070611` 成功。merge fast run `30203092489` 的 artifact `aitrans-ci-v2.3-smalldata_test--415925134037-run30203092489-attempt1` 与 merge HEAD 一致，`validationReason=merge_reuses_successful_candidate_full_validation`，精确复用第二父候选 SHA `7a148081b4bb7e53384b8882ebeaa5ebfd751d1b` 的 success，JUnit 10/10。
- 本轮不改变 Vision OCR、Koharu、翻译或覆盖算法，不声称质量指标提升，不刷新 `output/`，不追加 `metrics/version_history.csv`。

## v2.2：图片导入 run isolation
日期：2026-07-26

状态：Agent X 已完成候选实现、独立复审和两个 exact-SHA 云端 full，工程正式版本为 `MARKETING_VERSION=2.2`。PR #56 已合入 `smalldata_test`，merge SHA `eb18519d5d4e1629f79835beb37e8005e6dd8a81`；远端 `codeb/v2.2-image-import-run-isolation` 已删除，未触碰 `main`。

核心变更：

- PhotosPicker 的 `loadTransferable` 不再由 View 创建未持有的 `Task`；Store 从选择发生时即创建 task ID、固定源/目标语言、进入 loading，并持有 transfer、sandbox 写入、OCR、翻译和导出完整任务。旧照片的成功、失败或 nil 回调在新选择、文件导入、取消或清空后都不能覆盖当前状态。
- 新照片或图片文件可以在 OCR / 翻译运行中直接抢占旧任务。文件选择 completion 使用独立 UUID 精确匹配；View 只传 loader / result，不直接写业务状态。nil transferable 明确进入“照片读取失败”，新任务开始即清除旧 retry source。
- sandbox 输入使用 task UUID 隔离同名文件；helper 只返回 URL，只有 await 后 task identity 仍匹配才发布 source。被抢占的 detached 写入、被替换的旧源和清空的当前源会删除；取消后仍允许保留当前源并立即重试。

验证与遗留：

- 新增 `scripts/test-v202-image-import-run-isolation-contract.py` 与纯 Swift evaluator，当前 10/10 通过；覆盖 A/B 反序完成、nil、取消、清空、照片/文件交错、source 发布门槛、同名 sandbox 隔离、文件选择 UUID、选择器失败保留现有任务、旧源清理、retry source 门槛和组合 CI fail-fast。v1.87 UI interaction 回归 12/12、Swift parse、workflow YAML 与 `git diff --check` 通过。
- 核心 SHA `e59bc4fc13946ff91383a9c3a128cc55f7ca2108` 的云端 full run `30202007400` attempt 1 成功；artifact `aitrans-ci-v2.2-codeb-v2.2-image-import-run-isolation--e59bc4fc1394-run30202007400-attempt1` 与 version / branch / SHA / run / profile 完全一致，v2.2 10/10、v1.87 12/12、Speech/home/paste、extended Koharu validator matrix 和 Xcode build 均通过，JUnit 10/10，`.xcresult` succeeded 且 0 error / 0 warning，commit status `AITRANS CI/full-validation=success`。父 SHA 的 superseded run `30201926721` 已取消，不作为证据；scope 因父收据失败安全回退全仓并记录 `candidate_full_repo_fallback`。
- 版本收口 SHA `6086c24af42d629937ae61bf8a3d01e9ce3f684d` 的云端 full run `30202239509` attempt 1 成功；artifact `aitrans-ci-v2.2-codeb-v2.2-image-import-run-isolation--6086c24af42d-run30202239509-attempt1` 与 identity 完全一致，`MARKETING_VERSION=2.2`、Xcode build success、JUnit 10/10、`.xcresult` succeeded 且 0 error / 0 warning，commit status `AITRANS CI/full-validation=success`。本次仅改版本与入口文档，领域契约按 changed-files 路由跳过，由父核心 full 提供证据。
- 纯文档 follow-up fast run `30202386858` 正确复用父 SHA `6086c24af42d629937ae61bf8a3d01e9ce3f684d` 的 full-validation success；PR fast run `30202421300` 成功。merge fast run `30202456969` 的 artifact `aitrans-ci-v2.2-smalldata_test--eb18519d5d4e-run30202456969-attempt1` 与 merge HEAD 一致，`validationReason=merge_reuses_successful_candidate_full_validation`，精确复用第二父候选 SHA `04d20baeb74603ab0778f8ce09b87023526ca364` 的 success。
- v2.2 contract 已接入 UI interaction CI 路由。未跑本机 build / 探针，按规则交给云端验证。
- 本轮不改变 Vision OCR 算法、漫画探针、Koharu shadow OCR、翻译 prompt 或模型，不声称 OCR 指标提升，不刷新 `output/`，不追加 `metrics/version_history.csv`。

## v2.1：Koharu assignment geometry coverage
日期：2026-07-26

状态：Agent X 已完成核心候选实现、独立复审和两个 exact-SHA 云端 full 验证，工程正式版本为 `MARKETING_VERSION=2.1`。PR #55 已合入 `smalldata_test`，merge SHA `9d92ab7c3c74c4a78b266bf5bb7c5531e96040c9`；远端 `codeb/v2.1-koharu-geometry-coverage` 已删除，未触碰 `main`。

核心变更：

- external TextBox shadow OCR 将 OCR outcome 与 assignment geometry 分账。空间可信标准统一为中心包含或 `IoU >= 0.10`；弱 overlap 仍可执行 shadow OCR，但写入 `geometryWeakBlockIndexes` 并不得关闭 coverage gate。
- Bubble alignment 从旧的缺失即 matched 改为 `matched / unknown / conflict`：双方 external Bubble ID 相同才 matched，任一侧缺失为 unknown 且不获得 score bonus，双方不同继续拒绝 edge。
- Bubble instance ID 与 TextBox ID 同样强制非空唯一；缺失、空白或非字符串输出 `bubbleIDMissing:<index>`，重复输出 `duplicateBubbleID:<id>`。Swift 解码不再为缺 ID 生成随机 UUID。
- 报告、TXT、handoff、convergence 和 CI manifest 新增 `minimumTrustedIoU`、trusted / weak / unknown Bubble block arrays、geometry ratio / verdict；只有 OCR 与 geometry 两条 ledger 都完整才允许 `WI/G-external-textbox-shadow-ocr-coverage` closed / passed。

验证与遗留：

- 新增 v2.1 Python contract 与真实 Swift evaluator，覆盖弱/强阈值、center containment、Bubble conflict / unknown、OCR/geometry 正交、完整/阻塞 verdict、旧 JSON 解码和 Bubble invalid fixture；v2.1 6/6、v2.0 6/6、v1.99 5/5、v1.92 5/5、v1.97 handoff 6/6、CI tier 9/9、version identity 5/5 均通过。
- 核心 SHA `b9a3ebcdd49e7329511d750e005ce7452e27b047` 的云端 full run `30200743723` attempt 1 成功；artifact `aitrans-ci-v2.1-codeb-v2.1-koharu-geometry-coverage--b9a3ebcdd49e-run30200743723-attempt1` 与 SHA / branch / run / profile 完全一致，JUnit 10/10、Xcode build success、Koharu extended validator matrix 与 Speech/UI/home/paste 契约通过，commit status `AITRANS CI/full-validation=success`。
- 版本收口 SHA `e555916f4c5db3db1711231a807390bb26b178de` 的云端 full run `30201087646` attempt 1 成功；artifact `aitrans-ci-v2.1-codeb-v2.1-koharu-geometry-coverage--e555916f4c5d-run30201087646-attempt1` 与 SHA / branch / run / profile 完全一致，Xcode build success、JUnit 10/10、`.xcresult` build status succeeded 且 0 error / 0 warning，commit status `AITRANS CI/full-validation=success`。本次仅改版本与文档，领域契约按 changed-files 路由跳过，并由父核心 SHA `b9a3ebcdd49e7329511d750e005ce7452e27b047` 的 full 收据提供证据。
- 纯文档 follow-up fast run `30201329109` 正确复用父 SHA `e555916f4c5db3db1711231a807390bb26b178de` 的 full-validation success；PR fast run `30201362562` 成功。merge fast run `30201394710` 的 artifact `aitrans-ci-v2.1-smalldata_test--9d92ab7c3c74-run30201394710-attempt1` 与 merge HEAD 一致，`validationReason=merge_reuses_successful_candidate_full_validation`，精确复用第二父候选 SHA `54ce9e1218b85c4509361214ec1f8c5970eddf60` 的 success。
- 本轮保持 shadow-only，不改变主 OCR、翻译、覆盖图、`blockPassed` 或 promotion。默认 push 使用 `probe_mode=skip`，artifact 仅含 `probe-not-run.txt`；仓库仍无真实四件套，不声称 OCR 数字提升，不刷新 `output/`，不追加 `metrics/version_history.csv`。
- 未跑本机 build / 探针，按规则交给云端验证。

## v2.0：Koharu external TextBox 一对一 coverage
日期：2026-07-26

状态：Agent X 已完成核心候选复审和版本收口，工程正式版本为 `MARKETING_VERSION=2.0`。PR #54 已合入 `smalldata_test`，merge SHA `88c6b303d619a8234054865d4a735bc1de7c76a7`；远端 `codeb/v2.0-koharu-shadow-coverage` 已删除，未触碰 `main`。

核心变更：

- external TextBox shadow OCR 从逐块独立取最佳候选改为确定性的最大基数二分匹配；block 与 TextBox 都最多消费一次，增广路径避免多候选 block 抢占单候选 block，最终以 TextBox ID 稳定 tie-break。
- active TextBox ID 必须是非空唯一字符串；Python validator 与 App readiness 同步拒绝缺失/重复 ID，避免随机 UUID 参与匹配身份。
- `externalTextBoxShadowOCRReport` 新增逐块 matched / succeeded / failed / skipped partition、争用账本、最终 duplicate ledger、matched / successful / matched-OCR-success ratios 和 `coverageVerdict`。
- convergence 与 injected-artifact CI smoke 只有在分区一致、最终无重复 TextBox、所有 block OCR 成功且 `successfulCoverageRatio = 1` 时才允许 coverage gate passed；局部成功只阻塞 failed + skipped blocks，不再以任意一个成功块伪装整体闭合。

验证与遗留：

- 新增 `scripts/test-v200-koharu-shadow-coverage-contract.py` 与纯 Swift fixture `scripts/test-v200-koharu-shadow-coverage-evaluator.swift`，实际编译并执行增广重分配、单 TextBox 争用、complete / partial / no-success / duplicate / invalid partition、旧报告 Codable 兼容、ID 门槛和 CI/TXT 接线；保留旧 counts 与 `skippedBlocks` 便于报告消费者渐进迁移。
- 核心候选 SHA `9a4ad74e2c0d41b7b09f7a57a41d2b211082ce4d` 的云端 full run `30199459993` attempt 1 成功；artifact `aitrans-ci-v2.0-codeb-v2.0-koharu-shadow-coverage--9a4ad74e2c0d-run30199459993-attempt1` 与候选 HEAD 一致，v2.0 contract 6/6、extended Koharu validator matrix、Speech/UI/home/paste 契约和 Xcode build 均成功，JUnit 10/10，`.xcresult` 0 error / 0 warning，commit status `AITRANS CI/full-validation=success`。
- 版本收口 SHA `dd894c667d157aa5b2ef762b838143b88052ae66` 的云端 full run `30199669320` attempt 1 成功；artifact `aitrans-ci-v2.0-codeb-v2.0-koharu-shadow-coverage--dd894c667d15-run30199669320-attempt1` 与收口 HEAD 一致，`validationProfile=full`、`xcodeBuildRequired=true`、Xcode build success、JUnit 10/10、`.xcresult` 0 error / 0 warning，commit status `AITRANS CI/full-validation=success`。本次只改工程版本与文档，Koharu 领域契约按 changed-files 路由跳过，并由父核心 full 提供领域证据。
- 纯文档 follow-up fast run `30199855503` 正确复用父 SHA `dd894c667d157aa5b2ef762b838143b88052ae66` 的 full-validation success；PR fast run `30199891233` 成功。merge fast run `30199913442` 的 artifact 与 merge HEAD `88c6b303d619a8234054865d4a735bc1de7c76a7` 一致，`validationReason=merge_reuses_successful_candidate_full_validation`，精确复用第二父 SHA `c58bd3fe9ad819bbc9a4df950bdebbb97507befe` 的 success。
- 首次核心 push SHA `a22f7cab40b5711ffcdbddf203fec0f02d3766a6` 的 run `30199283447` 在创建 job 前因漫画探针长 `run` block 超过 GitHub 21000 字符表达式上限失败；后续把 Actions 表达式移至 step env，并顺带消除 `github.head_ref` shell 注入 lint 警告。该失败 run 无 jobs / artifact，不作为验证收据。
- 本轮保持 shadow-only，不改变主 OCR、翻译、覆盖图、`blockPassed` 或 promotion；仓库仍无真实四件套，不声称 OCR 数字提升，不刷新 `output/`，不追加 `metrics/version_history.csv`。
- 未跑本机 build / 探针，按规则交给云端验证。

## v1.99：Koharu line polygon 所属关系校验
日期：2026-07-26

状态：Agent X 已完成核心候选复审和版本收口，工程正式版本为 `MARKETING_VERSION=1.99`。PR #53 已合入 `smalldata_test`，merge SHA `832e29abc9f9bde8ba1698bd5dfe353814337194`；远端 `codeb/v1.99-koharu-polygon-containment` 已删除，未触碰 `main`。核心候选 SHA `1be5b53d7593932ab203dce4304f6eb0a577dec6` 与版本收口 SHA `8fdfc41b26f2b91cc4db284f321b967196f1ee9c` 的 task-scoped full 均已通过。

核心变更：

- Python artifact validator 与 App runtime readiness 不再只验证 `linePolygons` 位于整张源图内；每个 point 还必须属于对应 TextBox bbox，统一允许 `min(8px, max(2px, bbox 短边 2%))` 的舍入容差。
- 超出所属 bbox 容差的点写入 `linePolygonOutsideTextBoxBBox:<polygon>:<point>`，对应 TextBox 进入 invalid ledger，artifact verdict 为 `coordinateValidationFailed`，不能进入 external shadow OCR。
- invalid metadata fixture 新增“bbox 在一个区域、polygon 完全位于源图另一处”的样本，避免错误区域 warp OCR 被当作合法 TextBox 证据。

验证与遗留：

- 新增 `scripts/test-v199-koharu-line-polygon-containment-contract.py`，覆盖 bbox 内、容差边缘、部分越界、完全脱离、Python/Swift 同口径与 CI 接线，当前 5/5 通过；v1.92 warp contract 5/5、Swift parse、YAML parse、fixture JSON 与 `git diff --check` 通过。
- 核心候选云端 full run `30197944841` attempt 1 成功；artifact `aitrans-ci-v1.99-codeb-v1.99-koharu-polygon-containment--1be5b53d7593-run30197944841-attempt1` 与候选 HEAD 一致，extended Koharu validator matrix、v1.99 contract 5/5、Speech/UI/home/paste 契约和 Xcode build 均成功；JUnit 10/10，`.xcresult` build status succeeded、0 error、0 warning，commit status `AITRANS CI/full-validation=success`。
- 版本收口云端 full run `30198122722` attempt 1 成功；artifact `aitrans-ci-v1.99-codeb-v1.99-koharu-polygon-containment--8fdfc41b26f2-run30198122722-attempt1` 的 version、branch、commit、run 和 workflow identity 与收口 HEAD 一致，`validationProfile=full`、`xcodeBuildRequired=true`、Xcode build success、JUnit 10/10，commit status `AITRANS CI/full-validation=success`。本次 push 使用默认 `probe_mode=skip`，结果包仅保留 `probe-not-run.txt`，没有伪装为真实 Koharu 运行态证据。
- 纯文档 follow-up fast run `30198338709` 正确复用父 SHA `8fdfc41b26f2b91cc4db284f321b967196f1ee9c` 的 full-validation success；PR fast run `30198372211` 成功。merge fast run `30198404428` 的 artifact `aitrans-ci-v1.99-smalldata_test--832e29abc9f9-run30198404428-attempt1` 与 merge HEAD 一致，`validationReason=merge_reuses_successful_candidate_full_validation`，复用第二父 SHA `58dac079fc13ba309a10083ff03a0ef11d47cd09` 的成功状态。
- 本轮只加固真实 external artifact 的准入证据，保持 shadow-only，不改变主 OCR、翻译、覆盖图、`blockPassed` 或 promotion；仓库仍无真实四件套，不声称 OCR 数字提升，不刷新 `output/`，不追加 `metrics/version_history.csv`。
- 未跑本机 build / 探针，按规则交给云端验证。

## v1.98：图片预览与导出一致性
日期：2026-07-26

状态：Agent X 已完成核心候选独立复审与版本收口，工程 `MARKETING_VERSION=1.98`。PR #52 已合入 `smalldata_test`，merge SHA `28836f2d935828d30f1f187cf6706c387b00cb41`；远端 `codeb/v1.98-image-export-consistency` 已删除，未触碰 `main`。核心候选 SHA `87de0cd9503146f08c149a77ef99b4570813b6f4` 与版本收口 SHA `3dbb5d5bc2b683dc0505c86a9589c6fad960116b` 的 task-scoped full 均已通过。

核心变更：

- 普通图片导出从默认 Core Graphics 坐标改为顶左原点的 `UIGraphicsImageRenderer`，直接消费 Vision OCR 的 normalized top-left bbox，并由 `UIImage` 绘制处理源图方向，避免预览在顶部而导出落到垂直镜像位置。
- 导出 renderer 显式消费 `ImageTranslationOverlayMode`：`旁贴` 在原文字块侧边生成译文/原文气泡，`覆盖` 才在原 bbox 上绘制译文，不再出现预览切模式但导出固定覆盖。
- 已完成图片切换模式时立即清除旧 export URL 并异步重绘；后台 renderer 每次只写 render ID 独占的 staging PNG，独立 render ID、图片 task ID 与 mode 三重核对通过后才原子发布稳定 export，避免已拒收的旧 detached render 反向覆盖新文件。新任务、清空、取消都会取消并失效旧 render，过期 staging 会清理。
- 图片 OCR/翻译运行中禁用模式选择；最终 render 后再次核对图片 task ID。若程序化模式切换与最终 render 交错，完成翻译后按当前模式重绘。

验证与遗留：

- `scripts/test-v187-ui-interaction-contract.py` 新增顶左坐标、mode renderer、模式重绘、先验身份后发布和 staging 清理契约，当前 12/12 通过；两份修改 Swift 源码通过完整 Xcode toolchain `swiftc -frontend -parse`，`git diff --check` 通过。
- 核心候选云端 full run `30196905125` attempt 1 成功；artifact `aitrans-ci-v1.98-codeb-v1.98-image-export-consistency--87de0cd95031-run30196905125-attempt1` 的 version、branch、commit、run、workflow 和 changed-files identity 与候选 HEAD 一致。JUnit 10/10、UI interaction 12/12、Speech 14/14，Xcode `.xcresult` build status succeeded、0 error、0 warning，commit status `AITRANS CI/full-validation=success`。
- 版本收口云端 full run `30197163124` attempt 1 成功；artifact `aitrans-ci-v1.98-codeb-v1.98-image-export-consistency--3dbb5d5bc2b6-run30197163124-attempt1` 与收口 HEAD 一致，`MARKETING_VERSION=1.98`，JUnit 10/10，Xcode `.xcresult` build status succeeded、0 error、0 warning，commit status `AITRANS CI/full-validation=success`；Speech/UI 大契约按纯版本与文档 scope 跳过，仍以上一核心 SHA 的 exact artifact 为证据。
- PR fast run `30197360465` 与 merge fast run `30197407724` 均成功；merge artifact `aitrans-ci-v1.98-smalldata_test--28836f2d9358-run30197407724-attempt1` 的 version、branch、commit、run identity 正确，`validationReason=merge_reuses_successful_candidate_full_validation`，复用第二父候选 SHA `dfca6563c0b3e9105a23de194d7b0f11e5086825` 的成功 full-validation status。
- 本轮没有修改 Vision OCR 识别/聚类、翻译 prompt、模型或漫画探针，不声称 OCR/翻译质量数字提升，不刷新 `output/`，不追加 `metrics/version_history.csv`。
- 未跑本机 build / 探针，按规则交给云端验证。

## v1.97：Koharu 真实路径加固
日期：2026-07-26

状态：Agent X 已完成核心候选独立复审与版本收口，工程 `MARKETING_VERSION=1.97`。核心 PR #50 已合入 `smalldata_test` merge `326a160596edc36051d8e345cb3311ed6715cb73`；CI 版本身份 maintenance PR #51 已合入 merge `5566b2bff8f7f1afef4a98a1fdbe96da0c8813be`，均未触碰 `main`。

核心变更：

- external TextBox 的多条 `linePolygons` 改为逐行隔离 warp / OCR 失败。单行异常不再丢弃同一 TextBox 内已成功的行；只有全部行失败才整块回退 bbox OCR。
- 部分成功使用 `linePolygonPerspectiveWarpPartial` / `externalArtifact.linePolygonWarpPartial`，保留逐行失败原因并加入 `linePolygonWarpPartialFailure`。该结果可进入 shadow OCR 对照，但不得通过既有 promotion gate，orientation convergence 必须保持 partial / blocked。
- Koharu handoff packet 不再默认指向旧仓库。repo、workflow ref 和 expected commit SHA 由显式参数或 GitHub / 当前 git 环境解析为同一 `targetIdentity`，并统一驱动 upload、dispatch、run list、manifest assertions、review 清单和 stale-run rejection；workflow 入口在任何验证前硬核对 expected SHA，ref 已移动时立即失败。
- CI fixture 改为显式假 repo/ref/SHA，新增 v1.97 独立契约，避免再次把本机默认或错误远端锁成“测试通过”。
- PR #50 merge fast follow-up run `30195296033` 暴露 `smalldata_test` 不含版本号时 artifact 被标为 `unversioned`。后续维护分支 `codeb/v1.97-ci-version-identity` 增加工程版本解析器：无版本 ref 回退到唯一 `MARKETING_VERSION`，缺失或配置冲突直接失败；Speech recognition / quality 接线契约也不再硬编码旧 `1.96`。

验证与遗留：

- 本地轻量验证包括 v1.92 line polygon contract、v1.97 handoff target contract、v1.94 CI tier contract、validator fixture 矩阵、JSON/YAML parse、Swift parse 和 `git diff --check`。
- 核心候选云端 full run `30194847103` attempt 1 成功；artifact `aitrans-ci-v1.97-codeb-v1.97-koharu-real-path-hardening--d6d6fcc82aaf-run30194847103-attempt1` 的 version、branch、commit、run、workflow 和 changed-files identity 与候选 HEAD 一致。JUnit 10/10、Xcode `.xcresult` build status succeeded、0 error、0 warning，commit status `AITRANS CI/full-validation=success`。
- 当前仓库仍无真实 `test/koharu_artifacts/` 或 Release 四件套，根 `output/` 仍是 `manifestMissing` 基线。因此本轮不声称 OCR 数字、翻译通过率或覆盖质量提升，不刷新 `output/`，不追加 `metrics/version_history.csv`。
- 未跑本机 build / 探针，按规则交给云端验证。核心候选云端 `probe_mode=skip`，没有真实四件套注入；真实四件套到位后，使用 packet 的 exact repo/ref/SHA 手动 dispatch `ci-fast`，再核对 App runtime identity、partial orientation blocker、external shadow OCR coverage 和 reconciliation。

## v1.96：图片翻译目标语言一致性
日期：2026-07-26

状态：Agent C 已完成核心候选验收并执行版本收口，工程 `MARKETING_VERSION=1.96`。核心候选 HEAD `03f6f731f79e7345abf69ca01f9ad8583e273705`；PR #49 仅在收口提交的 exact-SHA CI 通过后合并到 `smalldata_test`，不触碰 `main`。

核心变更：

- 图片页新增目标语言菜单，复用 `TranslationSessionStore.targetLanguage`、既有 Pro 门控和锁定提示；不新增独立持久化状态，也不改变漫画探针固定英译中路径。
- 图片翻译任务在开始时固定源语言和目标语言。逐块 OCR/翻译期间，即使其他页面修改全局语言，当前任务也不会混用不同语言方向。
- 已完成的图片切换为新的可用目标语言时，从沙盒原图重新执行 OCR、翻译和覆盖导出；运行态菜单禁用，防止同一任务内改写目标语言。
- 图片任务单独记录当前内容实际使用的目标语言。其他页面修改全局目标语言后，图片页的标题、菜单、选中标记和 VoiceOver 仍显示实际译文语言；再次选择全局已选但与图片结果不同的语言时仍会触发重译。
- Agent C 首轮退回后补齐失败/取消生命周期：只要图片数据或部分 OCR/译文仍可见，就保留对应目标语言；只有清空图片或新任务替换内容时才重置，避免错误态和取消态重新按全局语言错标。
- Agent C 二次退回后补齐 loading 空窗：任务运行状态无条件使用已固定的任务语言，即使图片数据与 blocks 尚为空，跨页面修改全局语言也不会短暂错标标题、菜单或 VoiceOver。

关键文件：

- `AITRANS/Views/ImageTranslationViews.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `scripts/test-v187-ui-interaction-contract.py`

验证与遗留：

- 已通过 `python3 -B scripts/test-v187-ui-interaction-contract.py`（10 项）、`python3 -B scripts/test-speech-recognition-contract.py`（14 项）、`git diff --check` 和三份现有 JSON 解析；独立契约验证任务语言先于 `.loading` 发布且 running 分支不依赖图片数据/blocks，并继续覆盖跨页面改语言、同值重译及无 OCR/错误/取消/清空状态转换。
- 核心候选云端 full run `30193309626` attempt 1 成功；artifact `aitrans-ci-v1.96-codeb-v1.96-image-language-consistency--03f6f731f79e-run30193309626-attempt1` 的 version、branch、commit、run、workflow 和 changed-files identity 与候选 HEAD 一致，Xcode build、JUnit 10/10、UI interaction 10/10、Speech 14/14 均通过，`.xcresult`、日志和失败摘要可用。
- 未跑本机 build / 探针，按规则交给云端验证；本轮没有修改漫画算法或报告模型，因此未更新 `metrics/version_history.csv`。

## 当前漫画指标基线
日期：2026-06-29

当前项目是 SwiftUI iOS 本地翻译原型，主线已从普通翻译 UI 转到漫画截图 OCR、本地翻译、覆盖合成和探针诊断。最新可用基线来自当前 `output/probe_report.json`、`output/clean_text_diagnostic.json` 和 `metrics/version_history.csv` 的 v21 行：

- `sourceImage = test/1.png`
- `engineUsed = Local GGUF`
- `decodingMode = deterministic`
- `decodingSeed = 42`
- `configuration.currentBlockSource = fusedWholePageBubble`
- `totalBlocksDetected = 13`
- `postFusionCleanup.blockCountBeforeCleanup = 16`
- `postFusionCleanup.blockCountAfterCleanup = 13`
- `postFusionCleanup.rejectedBlockCount = 3`
- `groundTruthMatchedBlocks = 13`
- `groundTruthUnmatchedBlocks = 0`
- `averageCoreDialogueOCRSimilarity = 0.7106`
- `averageDecorativeOCRSimilarity = 0.8000`
- `wholePageAccuracyVsGroundTruth = 0.5972`
- `bubbleFirstAccuracyVsGroundTruth = 0.7300`
- `frameworkComparison.consistencyPassed = true`
- `fusionComparison.consistencyPassed = true`
- `fusion.fused.accuracyVsGroundTruth = 0.7384`
- `cleanTextDiagnostic.passRate = 0.4545`
- `textRegionCropReport.totalRegions = 13`
- `textRegionCropReport.cropSucceededCount = 10`
- `textRegionCropReport.adoptedCount = 0`
- `textRegionCropReport.rejectedCount = 13`
- `bubbleSubRegionReport.totalSubRegions = 11`
- `bubbleSubRegionReport.clampEligibleCount = 2`
- `bubbleSubRegionReport.oversizedBubbleIDs = [4, 6, 7]`
- `textRegionCropReport.clampSources = { bubbleBBox: 9, contentRect: 2, subRegion: 2 }`
- `bubbleMaskReport.instanceCount = 8`
- `bubbleMaskReport.maskSafeLayoutBlocks = 13`
- `bubbleMaskReport.bboxFallbackBlocks = 0`
- `bubbleMaskReport.inconsistentBubbleAssignmentBlocks = [4, 5, 11, 12]`
- `bubbleMaskReport.renderMaskOverflowBlocks = []`
- `bubbleAssignmentCorrectionReport.recommendedCorrectionBlocks = [5, 11]`
- `bubbleAssignmentCorrectionReport.appliedToCropClampBlocks = [5]`
- `bubbleAssignmentCorrectionReport.rejectedCorrectionBlocks = [4, 11, 12]`
- `bubbleSplitCandidateReport.parentBubbleIDs = [4, 6, 7]`
- `bubbleSplitCandidateReport.candidateCount = 6`
- `bubbleSplitCandidateReport.clampEligibleCount = 3`
- `bubbleSplitCandidateReport.appliedToCropClampBlocks = [5, 9, 10]`
- `textBoxCandidateReport.candidateCount = 13`
- `textBoxCandidateReport.cropEligibleCount = 6`
- `textBoxCandidateReport.usedForCropBlocks = []`
- `textBoxCandidateReport.rejectedBlocks = [2, 4, 5, 7, 9, 11, 12]`
- `segmentMaskReport.glyphMaskBlocks = 11`
- `segmentMaskReport.usableForCropEvidenceBlocks = [0, 1, 2, 3, 6, 7, 8, 9, 10, 11]`
- `segmentMaskReport.weakSegmentBlocks = [4, 5, 12]`
- `preCropTextBoxPlanReport.planCount = 37`
- `preCropTextBoxPlanReport.shadowOCREligiblePlanCount = 29`
- `preCropTextBoxPlanReport.selectedForShadowOCRBlocks = [0, 1, 2, 3, 5, 6, 7, 8, 9, 10, 11]`
- `preCropTextBoxPlanReport.stoppedBlocks = [4, 12]`
- `cropExperimentReport.candidateCount = 48`
- `cropExperimentReport.controlCandidateCount = 13`
- `cropExperimentReport.ocrSucceededCount = 36`
- `cropExperimentReport.betterThanControlCount = 13`
- `cropExperimentReport.promotedShadowBlocks = []`
- `cropExperimentReport.stoppedBlocks = [2, 3, 4, 5, 7, 9, 11, 12]`
- `textBoxPlanFailureReport.evaluatedBlockCount = 13`
- `textBoxPlanFailureReport.evaluatedPlanCount = 37`
- `textBoxPlanFailureReport.evaluatedCandidateCount = 35`
- `textBoxPlanFailureReport.betterThanControlCandidateCount = 13`
- `textBoxPlanFailureReport.promotedShadowBlockCount = 0`
- `textBoxPlanFailureReport.stopRecommendedBlocks = [2, 3, 4, 5, 7, 9, 11, 12]`
- `textBoxPlanFailureReport.continueGeometryResearchBlocks = [1, 6, 10]`
- `textBoxPlanFailureReport.candidatePromotionBlockedBlocks = [1, 2, 4, 5, 6, 9, 10]`
- `lineTextBoxPlanReport.targetBlocks = [1, 6, 10]`

- `lineTextBoxPlanReport.planCount = 12`
- `lineTextBoxPlanReport.shadowOCREligiblePlanCount = 12`
- `lineCropExperimentReport.candidateCount = 12`
- `lineCropExperimentReport.ocrSucceededCount = 12`
- `lineCropExperimentReport.betterThanControlCount = 5`
- `lineCropExperimentReport.promotedLineShadowBlocks = []`
- `lineCropExperimentReport.stoppedAfterLineResearchBlocks = [1, 6, 10]`
- `externalArtifactReadinessReport.manifestFound = false`
- `externalArtifactReadinessReport.textBoxesFound = false`
- `externalArtifactReadinessReport.bubbleMaskFound = false`
- `externalArtifactReadinessReport.segmentMaskFound = false`
- `externalArtifactReadinessReport.readinessVerdict = manifestMissing`
- `externalArtifactReadinessReport.nextAction = stopUntilArtifactsProvided`
- `externalArtifactReadinessReport.missingArtifacts = [manifest, TextBoxes, BubbleMask, SegmentMask]`
- `externalArtifactReadinessReport.blockAlignment.count = 13`
- v1.13 新增 `externalTextBoxShadowOCRReport` 后，云端 run `28381772143` 已验证默认缺 active artifact 时 `executed = false`、`gateVerdict = manifestMissing`、`candidateCount = 0`、`ocrExecutedCount = 0`、`promotedExternalShadowBlocks = []`、`skippedBlocks = [0...12]`。
- `textRegionCropReport.failureAttributionBreakdown = { localVisionRegression: 6, rawWordsLost: 5, bubbleMaskConflict: 3, emptyLocalOCR: 3, segmentMaskWeak: 3, textBoxTooWide: 2, introducedLikelyOCRError: 2, wordCountRegression: 2, sameAsFusedText: 2, insufficientQualityGain: 2 }`
- `passedBlocks = 1`
- `failedBlocks = 12`
- `translationFailureBreakdown = { modelOutputFailure: 2, ocrInputSuspect: 7, translationLanguageQualityFailure: 3 }`
- `likelyRuleFalseFailureBlocks = []`

当前结论：

- 当前瓶颈是 OCR 文本质量和 Gemma 270M 翻译能力，不是覆盖绘制，也不是规则过严。
- 主流程已切到 whole-page + bubble-first 融合；`Let's Battle!` 保留，bubble-first 独有两条真实内容也进入融合结果。
- post-fusion cleanup 已把 16 个融合块压到 13 个，拒绝重复/碎片块但保留关键真实内容。
- TextRegion crop OCR 候选层已接入报告和 `1_ocr_probe_text.txt`，本轮 13 个块全部被护栏回退，没有替换主翻译输入。
- `bubbleAudits` 标出 `bubbleID 4/6/7` 的分割风险；v13 新增轻量 `bubbleSubRegionReport`，v14 新增 `bubbleMaskReport`，v15 新增归属修正报告和保守 split candidate 报告，v16 新增轻量 `textBoxCandidateReport`、`segmentMaskReport` 和 crop failure attribution，v17 新增 shadow-only `cropExperimentReport`，v18 新增 TextRegion crop 前生成的 `preCropTextBoxPlanReport`，v19 新增 `textBoxPlanFailureReport`，v20 新增 `lineTextBoxPlanReport` / `lineCropExperimentReport`。当前只有 block 5 的归属修正用于 crop clamp，split candidate 用于块 `[5, 9, 10]` 的 crop clamp；TextBox 候选是 TextRegion crop 之后派生的诊断层，`usedForCropBlocks = []`；pre-crop plan、crop experiment、line crop experiment 的 best shadow candidate 和 failure attribution 都不替换 `finalTextUsedForTranslation`；crop 采用护栏未放宽。
- v20 证明 block `[1, 6, 10]` 的 line-level / deskew shadow 候选仍不能通过既有 promotion gate，应停止继续在这条 crop/line/deskew 试参线上消耗。
- v21 新增真实 TextBoxes / BubbleMask / SegmentMask artifact 适配前证据闸门；当前 `test/koharu_artifacts/` 不存在，报告明确阻塞在 `manifestMissing`，不得伪造 detector 接入。
- v1.13 新增 external TextBoxes shadow OCR 接入口，完全由 `externalArtifactReadinessReport.externalTextBoxesShadowOCRAllowed` 门控；ready 前只写阻塞报告，ready 后每块最多 1 个 `externalArtifact.textBoxCrop` 候选，只进 JSON / TXT，不替换主 OCR、翻译、覆盖或通过判定。
- Vision `customWords` 对当前图最终合并文本无变化，`changedBlockIndexes = []`。
- 确定性 OCR 纠错能提升部分相似度，但翻译收益不稳定，仍只做探针对照。
- tagged batch 翻译分支格式崩坏，不替换逐块翻译。

## 历史记录
### v1.95：Speech 真实语料质量算法与探针接线
日期：2026-07-13

状态：候选实现中，分支 `codeb/v1.95-speech-quality-corpus`，基于 v1.94 merge `aa829bc14bedc91fe1c54b629a8ac50dda0e4833`；工程 `MARKETING_VERSION=1.95`。本轮不生成 TTS 或占位音频，不声称 Apple Speech 识别质量已经提升；v1.96 等人工上传真实音频后再产生 WER/CER 和延迟证据。

核心变更：

- 新增 `aitrans.speech_corpus.v1` manifest：每项固定 ID、文件名、SHA256、字节数、locale、参考 transcript 和来源说明；Python validator 拒绝路径逃逸、重复 ID、缺字段和音频身份漂移。仓库缺 manifest 时输出 `manifestMissing` / `qualityExecuted=false`，不会把“未执行”伪装成质量通过或失败。
- 新增纯 `SpeechQualityEvaluator`：兼容大小写/宽度/标点规范化、通用 Levenshtein、词级 WER、字符级 CER 和按 reference token 加权 aggregate。中日文在没有稳定分词器时 `wordErrorRate=nil`，不把字符指标伪装成 WER。
- 新增独立 `SpeechQualityProbeService`：逐项校验音频身份，强制 `SFSpeechURLRecognitionRequest.requiresOnDeviceRecognition=true`，记录最终 transcript、延迟、segment、平均 confidence、on-device 能力和失败分类；120 秒超时与取消会终止当前 Speech task。
- 参考 transcript 只在 Apple Speech 返回最终文本后传给 evaluator；报告固定 `referenceUsedForEvaluationOnly=true`、`referenceUsedForRecognitionDecision=false`，不参与请求、候选、纠错或产品翻译。
- `TranslationSessionStore` 持有质量探针 Published 状态、独立 run ID/Task、取消与 DEBUG `AITRANS_RUN_SPEECH_QUALITY_PROBE` 入口；开发控制台只调用 store，展示报告摘要，不新增截图流程。
- JSON/TXT 写入既有 `Application Support/AITRANS/Output/`；报告包含 corpus/manifest/audio 身份、runtime、逐项指标、加权 WER/CER、平均延迟和 failure breakdown。磁盘写入错误必须附加 `outputWriteFailed` warning 并把 UI 置为失败，不能把只有内存报告的运行显示为已写出。
- Speech full CI 增加质量源码契约、纯 Swift evaluator、corpus validator 和新文件 changed-scope routing；候选核心 push 仍只跑一次 full + Xcode，不采 UI evidence，PR/merge 复用 v1.94 fast follow-up。

本地轻量验证：Speech 旧 contract 14/14、v1.95 quality contract 7/7、缺 corpus validator 的 `manifestMissing` 审计结果、纯 Swift evaluator contract、Swift 6 iOS Simulator 目标三文件 typecheck 均通过。未跑本机 build / 探针，按规则交给云端验证；未运行真实 WER/CER，因为仓库没有用户提供的音频和 manifest。

关键文件：`AITRANS/Models/SpeechQualityModels.swift`、`AITRANS/Services/SpeechQualityEvaluator.swift`、`AITRANS/Services/SpeechQualityProbeService.swift`、`AITRANS/Services/TranslationSessionStore.swift`、`AITRANS/Views/DeveloperConsoleView.swift`、`scripts/validate-speech-corpus.py`、`test/speech_corpus/README.md`、`.github/workflows/ci-results.yml`。

非目标与遗留：不更换 Apple Speech、不引入第三方 ASR、不改产品识别候选、不做 UI 重构或截图；真实语音质量必须等 v1.96 音频后在目标设备运行。漫画图像链路仍缺真实 Koharu manifest/TextBoxes/BubbleMask/SegmentMask 四件套和 `ci-fast` 对照，detector/mask/renderer 的 report-only proxy 不能描述为已完成 Koharu 复刻；本轮未改漫画算法、未跑漫画探针、不追加 `metrics/version_history.csv`。

### v1.94：云端 Full-Once / Fast-Follow-Up 验证分层
日期：2026-07-13

状态：已合入 `smalldata_test`。最终候选 `6864bd889fbab60f0c70d9df5d7b43e9440b594b`，PR #47，merge `aa829bc14bedc91fe1c54b629a8ac50dda0e4833`，远端候选分支已删除，`main` 未触碰；工程 `MARKETING_VERSION=1.94`。本轮是 CI 制度与验证路由优化，不改变 App 业务主链、漫画 OCR/翻译/覆盖结果或 Speech 运行语义。

核心变更：

- `codeb/**` 核心 push 进入 task-scoped full：基础静态检查始终运行，Speech、UI、文本首页、Koharu 契约按 changed files 启用；App 相关变更只在该 full 执行 Xcode build。成功后 workflow 为 exact SHA 写 `AITRANS CI/full-validation` commit status。
- PR 新增 opened / reopened / ready-for-review fast follow-up，但不监听 synchronize，避免同一修复 push 同时运行 full 和 PR fast。PR fast 跳过 Xcode、领域大契约、GGUF/探针和 UI evidence，只保留静态/CI 路由与可审计结果包。
- `smalldata_test` merge 读取第二父候选 SHA 的 full-validation status；success 才复用并走 fast，missing / failure / lookup failure 自动回退 full。C 退回后的新修复 SHA 必须重新 full。
- full 成功后的纯 README / AGENTS / update log / `md/` / metrics follow-up 可传播父提交收据；若父收据缺失或失败，workflow 会把 changed-files 扩展到完整候选 diff，防止失败代码被最后一个文档 commit 掩盖。
- UI evidence 不再按 `codeb/v1.9*` / `v2.*` 分支族自动跑。只有非 PR 候选 commit 的 `[ui evidence]` 或手动 `ui_evidence_mode=full` 启用；Speech 功能默认只验编译、run-id/取消/翻译链路契约，不截图。漫画/翻译需要图像证据时仍使用手动 `ci-fast/full` 的探针 output PNG。
- `AITRANS - Build IPA` 移除 `smalldata_test` push trigger，仅在软件包交付时手动 dispatch，日常 merge 不再重复 Release archive、加密、fakesign 和 IPA package。
- `ci-artifact-manifest.json`、JUnit、failure summary 与最终 gate 记录/消费 validation profile、reason、复用 receipt、领域 required flags、UI evidence reason 和 Xcode skip reason。新增 `scripts/test-v194-ci-validation-tier-contract.py` 锁定分层行为。

本地轻量验证：v1.94 CI tier contract 9/9、Speech contract 14/14、UI interaction 7/7、v1.88 home UI 7/7、v1.89 paste matrix 4/4 通过；两个 workflow YAML 可解析，所有内嵌 bash block `bash -n` 通过，`capture-ui-evidence.sh` syntax、三个基线 JSON、`MARKETING_VERSION=1.94` 唯一值与 `git diff --check` 通过。未跑本机 build / 探针，按规则交给云端验证；候选核心 commit 只触发一次 full，PR 与 merge 用 fast 验证分层本身。

首轮云端 run `29231418192` 在 job 创建前失败，GitHub annotation 明确为 `.github/workflows/ci-results.yml` manifest step `Exceeded max expression length 21000`；没有 jobs、日志或 artifact，且没有触发 Build IPA。修复将超大 manifest `run:` 内的 Actions expressions 全部移到 step `env`，Python 只读环境变量，并由 v1.94 contract 锁定 manifest script 不再内联 `${{ ... }}`，防止字段增长再次越过 GitHub 表达式上限。该失败属于 CI 配置，按规则修复 SHA 必须重新 full。

第二轮 run `29231948576` 在 SHA `aac5f8dc10bd89445cba70330dcca56b3702dd1b` 上 17 秒绿色结束，full-validation status 也写入成功，但验收发现它只比较失败提交到修复提交的增量 diff，未把首提交的工程版本变化纳入 changed-files，`xcodeBuildRequired=false`。该 run 只证明 expression-limit 修复能启动，不能作为 v1.94 候选 full/Xcode 证据。路由继续收紧：只要候选父 SHA 没有成功 full 收据，或本次修改 CI routing workflow，就必须从 `smalldata_test` merge-base 重新计算完整候选 diff，再决定 Xcode 与领域契约；因此下一 SHA 必须重新 full。

最终候选 full run `29232147877` 成功，耗时约 3 分 9 秒，Xcode success、JUnit 10/10、`.xcresult` 存在且 UI evidence skipped。PR fast run `29232478137` 约 19 秒，Xcode/领域大契约/UI 均 skipped。merge fast run `29233489356` 约 12 秒，manifest 为 `validationProfile=fast`、`validationReason=merge_reuses_successful_candidate_full_validation`、`reusedFullValidationSha=6864bd88...`、`reusedFullValidationState=success`、`xcodeBuildRequired=false`；merge 未触发 Build IPA。

非目标与遗留：不改变 Koharu report-only/active artifact 边界，不伪造真实四件套，不改善 WER/CER，不调整 App UI；本轮未跑漫画探针，不追加 `metrics/version_history.csv`。

### v1.93：Speech Run 取消与旧回调隔离
日期：2026-07-13

状态：Agent C / Agent X 验收通过。候选分支 `codeb/v1.93-speech-run-cancellation` 最终 HEAD `1b4f13ecab375387823428ebe6b305503eaa38c8`；PR #46 已合入 `smalldata_test`，merge `efd9c56a1001c6fcb9d2e6e4f153d4fe6f7fe184`，远端候选分支已删除。工程 `MARKETING_VERSION=1.93`；`main` 未触碰。

核心变更：

- store 持有独立 `speechTranslationTask`；取消先失效 Speech run ID，再取消 Speech recognition / translation Task 并回到 idle。新 run 在生成新 token 前取消并清理旧翻译 Task，支持取消后立即重试。
- 实时麦克风授权在 `requestMicrophoneAccess()` 的 `await` 返回后重新核对 run ID 与 capture request，旧授权回调不能把已取消或已重试的 run 写成失败或重新启动录音。
- 文件识别后的模型翻译与实时语音翻译都在 `await` 返回后核对 Task cancellation + run ID；`submit` 在 transcript 写入、summary 回写和错误状态写入前核对 Speech 所有权，旧翻译不会覆盖新 run。
- 音频文件和实时语音的 `.translating` 状态都提供取消入口；Speech contract 从 8 项增强为 14 项，按函数体顺序锁定授权、翻译、摘要、取消和立即重试边界。
- 第一轮 exact-SHA UI evidence 暴露 compact iPhone 运行态取消按钮被浮动 Tab Bar 遮挡；文件面板已把取消提升为运行态第一操作，并按状态显示“取消识别/取消翻译”，旧 run `29224663327` 因此不作为最终 UI 验收证据。
- Speech contract 从 static checks 去重，只保留独立 step，并进入 failure summary / fail-job 硬门控；失败仍会写入 JUnit、manifest 和独立日志。
- 最终证据矩阵新增 `audioTranslating` compact 场景，直接渲染非空实时 transcript、`.translating` 和“取消翻译”；总矩阵为 13 张（12 compact + 1 wide），不再只用 recognizing 截图间接证明 S5。

本地轻量验证：Speech contract 14/14、两个变更 Swift 文件 `swiftc -parse`、workflow YAML 解析和 `git diff --check` 通过。未跑本机 build / 探针，按规则交给云端验证；GitHub-hosted simulator 不能冒充真机麦克风、权限弹窗或 Apple Speech 识别质量证据。

云端实现验收：run `29225409696` attempt 1，artifact `aitrans-ci-v1.93-codeb-v1.93-speech-run-cancellation--dd77fe76bb35-run29225409696-attempt1`（2,780,359 bytes）。manifest 的 version / branch / commit / run / workflow 精确匹配；Xcode build、Speech 14/14、JUnit 8/8、v1.87-v1.89 contracts 和 12 张 current-HEAD UI evidence 全部通过。音频运行态截图 SHA256 `6bae5cac562a0de183d1cb794aa4010a4a9df1b093f543709f6b831228aebe3f`，取消按钮完整位于浮动 Tab Bar 上方。`probe_mode=skip`，符合本轮不改漫画路径的范围；本机缺 `xcresulttool`，但 `.xcresult` 结构、Info.plist、CI step 与 manifest 均可用。

版本收口验收：run `29226081679` attempt 1，artifact `aitrans-ci-v1.93-codeb-v1.93-speech-run-cancellation--891803630686-run29226081679-attempt1`（3,816,472 bytes）。manifest exact SHA / version / branch / run / workflow 对齐，`xcodeBuildRequired=true`，Xcode build、Speech 14/14、JUnit 8/8、v1.87-v1.89 contracts 和 12 张 current-HEAD UI evidence 通过；最终音频截图 SHA256 `ef627a294d056c03b5a380f73c9966740ee0c0a78c453cd54d1102431b1770ed`，取消动作仍完整可见。`probe_mode=skip`，未运行漫画探针或真实语音质量测试。

最终候选验收：run `29227415411` attempt 1，artifact `aitrans-ci-v1.93-codeb-v1.93-speech-run-cancellation--1b4f13ecab37-run29227415411-attempt1`（4,053,954 bytes）。manifest 精确匹配最终 HEAD；Xcode build、Speech 14/14、UI interaction 7/7、JUnit 8/8 与 13 张 current-HEAD UI evidence 成功，新增 `audioTranslating` 图证明“取消翻译”在 compact 夜间状态可见。`probe_mode=skip`。

post-merge 验收：CI Results run `29229554065` 与 Build IPA run `29229554033` 均 SUCCESS，head SHA 均为 `efd9c56a1001c6fcb9d2e6e4f153d4fe6f7fe184`。未加密 artifact `aitrans-ci-unversioned-smalldata_test--efd9c56a1001-run29229554065-attempt1` 的 manifest 匹配 branch / commit / run / workflow，`xcodeBuildRequired=true`、Xcode success、Speech success、JUnit 8/8、`.xcresult` 结构存在；UI evidence 与 manga probe 按 merge 范围跳过。IPA archive / fakesign / package 同 SHA 成功。

非目标与遗留：不更换 Apple Speech / 模型、不引入第三方 ASR、不声称改善 WER/CER；固定多语言音频 corpus、WER/CER/延迟报告和真机 S1-S8 人工矩阵仍是后续 Speech 质量阶段。漫画路径与 v1.92 指标均未改变，因此不追加 `metrics/version_history.csv`。

### v1.92：External TextBox Line Polygon Warp Shadow OCR
日期：2026-07-13

状态：Agent C / Agent X 已正式收口。PR #45 已合入 `smalldata_test`，merge `b374c19e99c784c5a933302a317a62572ba26355`，工程 `MARKETING_VERSION=1.92`。实现 HEAD `a514b2c8ffd99463859b7c715e1b5708f444d3fd` 与版本收口 HEAD `90b750821809f66b799e223919807a4fd4668940` 的云端 run 均 SUCCESS；未触碰 `main`。

核心变更：

- 对真实 external TextBox 的合法四点 `linePolygons` 使用 Core Image perspective correction 生成规整 line crop，逐行执行 Vision OCR 后合并；bbox + 0/90/180/270 rotation 路径继续作为 fallback。
- 只有 warp OCR 输出被最终候选选中时才写 `deskewExecuted = true`；bbox fallback 写独立 variant 并由 `linePolygonWarpOutputNotSelected` 阻止 report-only promotion，warp 失败或任意角度 rotation 继续阻塞 orientation convergence。
- validator / CI orientation fixture 改为声明 `linePolygonWarp = true`，新增 `orientationLinePolygonWarpSupportedTextBoxIDs`；`arbitraryRotationUnsupported` 仍保留。
- 仍为 shadow-only，不改 `finalTextUsedForTranslation`、主 OCR、翻译、覆盖图、`blockPassed` 或 active artifact；仓库仍没有真实四件套，不能声称完成 Koharu handoff。

云端实现验收：run `29219563408` attempt 1、artifact `aitrans-ci-v1.92-codeb-v1.92-koharu-line-polygon-warp--a514b2c8ffd9-run29219563408-attempt1`（3,869,756 bytes；SHA256 `5ffbc56b39057fde69e25e90f4fd562b028d6fbf07695005d208e61d72fd4f8c`）。manifest branch/commit/run/workflow 对齐，Xcode build / static / Speech / v1.87-v1.89 contracts / 12 张 UI evidence success，JUnit 8/8。`probe_mode=skip`，active artifact 仍为 `manifestMissing`；未跑真实四件套 Core Image/Vision runtime，不能声称 warp 已获 `ci-fast` 运行态证据。

版本收口验收：run `29220142240` SUCCESS，artifact `aitrans-ci-v1.92-codeb-v1.92-koharu-line-polygon-warp--90b750821809-run29220142240-attempt1`（3,871,273 bytes；SHA256 `8a3869af62d3f3b1516e4b01a3e0cab14c18189fbf69b3ccd335439b0742389e`），manifest exact SHA / branch / run / workflow 对齐，Xcode build、JUnit 8/8、v1.92 contract 5/5、Speech 8/8 和 12 张 UI evidence 通过。合并后 CI Results run `29220977461` 与 Build IPA run `29220977459` 均 SUCCESS；远端候选分支已删除。

本地轻量验证：Swift parse、v1.92 5/5、Speech 8/8、v1.87 6/6、v1.88 7/7、v1.89 4/4、validator/YAML/JSON/shell/`git diff --check` 通过。未跑本机 build / 探针，按规则交给云端验证。

### v1.91：Speech 人工矩阵与 Speech CI 契约独立门控
日期：2026-07-12

状态：Agent X 正式收口。PR #44 合入 `smalldata_test`。验收 HEAD `8d9145ae`，云端 run `29167471696` SUCCESS。`MARKETING_VERSION=1.91`。未触碰 `main`。

核心变更：

- `md/test/test.md` §0.5 Speech 人工矩阵 S1–S8（授权/取消/重试/runToken/离线包等），明确不可被 CI 冒充。
- CI：Speech contract 独立 step + JUnit/manifest 字段 + fail-job 硬失败；UI evidence 门控覆盖 `codeb/v1.9*` / `codeb/v2.*`。
- Koharu gap 文档状态更新到 v1.90；重申下一步是真实四件套 + ci-fast，禁止伪造 ready。

未跑本机 build / 探针；交给云端。无真实 Koharu artifact 时不触发 ci-fast 注入。

### v1.90：Speech 运行摘要增强与契约
日期：2026-07-12

状态：Agent X 正式收口。PR #43 合入 `smalldata_test`。验收 HEAD `69a86eb1`，云端 run `29167025229` SUCCESS。`MARKETING_VERSION=1.90`。未触碰 `main`。

核心变更：

- `SpeechRecognitionRunSummary` 增加 `runToken` 诊断字段，begin run 写入 UUID 前 8 位。
- 音频页运行摘要展示本机能力、终态与 Run token，保留离线强制/耗时/词数/置信度。
- Speech contract 增补：cancel 必须先 `invalidateSpeechRecognitionRun` 再 idle；UI 接线本机能力/终态/runToken。
- 不改 ASR 引擎、不引入第三方语音、不改漫画探针。

验证：本地 light contracts only；未跑本机 build / 探针，交给云端。

### v1.89 修复候选：wide-iPad UI evidence 串行 boot + CI 硬失败
日期：2026-07-12

状态：修复 push 至 `codeb/v1.89-paste-manual-matrix-wide-evidence`。run `29165244349` 中 contracts/Xcode 通过，但 `uiEvidenceOutcome=failure`：第二台 iPad 与 iPhone 并行迁移导致超时，11 张 compact 已有、缺 `text-empty-wide-ipad-day.png`；且 fail-job 未把 `codeb/v1.89-*` 的 UI evidence 失败计为硬失败（job 仍 SUCCESS）。

修复：

- `scripts/capture-ui-evidence.sh`：iPhone 矩阵完成后关机，再 create/boot iPad，避免双机 Data Migration 争用。
- `.github/workflows/ci-results.yml`：UI evidence timeout 15→25；`codeb/v1.89-*` UI evidence 失败硬失败；v1.89 contract 失败硬失败。

### v1.89：人工交互矩阵、Paste 可测性与 wide-iPad 证据
日期：2026-07-12

状态：Agent X 正式收口。PR #42 已合入 `smalldata_test`（merge `07b3e34b`）。验收 HEAD `3c8528d0`，云端 run `29166136570` SUCCESS。工程 `MARKETING_VERSION=1.89`。未触碰 `main`。

云端验收证据：

- artifact：`aitrans-ci-v1.89-codeb-v1.89-paste-manual-matrix-wide-evidence--3c8528d047f5-run29166136570-attempt1`
- JUnit 7/7；v1.87/v1.88/v1.89 contracts success
- UI evidence 12 张（11 compact-iPhone + 1 wide-iPad `text-empty-wide-ipad-day.png`），均 >135KB，commitSha 对齐 `3c8528d0`
- 真实系统 PasteButton 点击 / VoiceOver 回放仍属人工矩阵遗留，不得写成已验证

核心变更：

- `md/test/test.md` 新增 §0.3 可勾选人工交互与 a11y 矩阵（M1–M8），明确 CI 截图不能替代真实粘贴点击。
- DEBUG-only 粘贴注入：用户点击 `PasteButton` 且系统 payload 为空时，可读 `AITRANS_UI_TEST_PASTE_TEXT` 或 `-AITRANS_UI_TEST_PASTE_TEXT`；Release 无注入，lifecycle 不读剪贴板，系统 PasteButton 保留。
- `scripts/capture-ui-evidence.sh` 在 11 张 compact-iPhone 之外新增 1 张 `wide-iPad` 文本空态运行态证据（共 12 张）。
- 新增 `scripts/test-v189-paste-manual-matrix-contract.py`；CI 对 `codeb/v1.89-*` 开启 UI evidence，JUnit / manifest 增加 v1.89 contract 字段。

关键文件：

- `AITRANS/Views/TextTranslationView.swift`
- `scripts/capture-ui-evidence.sh`
- `scripts/test-v189-paste-manual-matrix-contract.py`
- `scripts/test-v188-home-ui-contract.py`
- `.github/workflows/ci-results.yml`
- `md/test/test.md`
- `md/prompt/v1.89（首页持续优化）/v1.89（人工交互矩阵与Paste可测性及宽屏证据）.md`

本地轻量验证：Speech 5/5、v1.87 6/6、v1.88 7/7、v1.89 4/4、workflow YAML parse、`git diff --check`；未跑本机 build / 探针，按规则交给云端验证。

遗留事项：

- 真实剪贴板与 VoiceOver 仍依赖人工矩阵勾选；DEBUG 注入不能冒充 Release 隐私路径已点通。
- 网络不可达时无法 push / 创建 PR / 合并 v1.88。
- 未改漫画探针与 `metrics/version_history.csv`。

### v1.88：文本首页极简科技工作台与剪贴板键盘交互
日期：2026-07-12

状态：Agent C / Agent X 正式收口。工程 `MARKETING_VERSION = 1.88`。PR #41 基于 `codeb/v1.88-home-translation-ui` HEAD `c8326bb068e512dbd8139271e65b38ddb3235b9c` 验收；云端 run `29104261998` attempt 1 SUCCESS 作为 build / contract / UI evidence 依据。本轮未做本机 Xcode / Simulator 交互点击验收，按用户约束只认云端结果；真实剪贴板点击、VoiceOver 回放与 iPad/Mac 运行态仍属遗留人工清单。合并目标仅为 `smalldata_test`，严禁触碰 `main`。

核心变更：

- 只重做文本翻译首页；新增独立 `TextWorkspaceBackground`，用静态冷中性层次、技术网格、导向线路和矩形节点替代旧纯色首页，不修改其他页面的全局背景。
- 首页保留安全区页头、语言、输入、输出、Prompt、翻译、会话和最近翻译；青蓝翻译、青绿粘贴、琥珀 Prompt、小面积紫红交换和中性会话命令同时使用图标、文字、描边与层级，不只依赖颜色。
- 新增系统纯文本 `PasteButton`。只有用户点击时读取兼容文本；空输入直接填入，非空输入以换行追加，不覆盖、不自动翻译、不记录剪贴板内容。
- 文本页统一持有输入焦点；keyboard toolbar 新增“完成”，翻译、新会话、Prompt 跳转和离开文本 Tab 前先失焦，翻译随后仍调用 `store.submitDraft`。
- 新增 `scripts/test-v188-home-ui-contract.py` 六项静态契约，并作为独立 CI step、JUnit testcase、manifest 字段和失败门控；v1.88 分支同时进入现有 current HEAD UI evidence 门控。
- Preview 新增 iPad 横屏文本页状态，但当前 CI 仍按既有约束只生成 11 张紧凑 iPhone 运行态证据；Preview 不冒充运行态截图或点击测试。

关键文件：

- `AITRANS/Views/TextTranslationView.swift`
- `AITRANS/Views/TextWorkspaceBackground.swift`
- `AITRANS/Views/TextWorkspacePasteButton.swift`
- `AITRANS/Views/AppTheme.swift`
- `AITRANS/Views/AppPreviewSupport.swift`
- `scripts/test-v188-home-ui-contract.py`
- `.github/workflows/ci-results.yml`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`

本地轻量验证：Swift parse 与无产物全工程 typecheck、`git diff --check`、PBX/plist lint、shell syntax、workflow YAML parse、Speech contract 5/5、v1.87 UI interaction contract 6/6、v1.88 home UI contract 7/7 和三个 JSON parse 已通过；未跑本机 build / 探针，按规则交给云端验证。

Agent C 多轮退回及 Agent B 截图复核：run `29092032857` 证明 72pt 内容尾部 padding 无法阻止浮动 Tab Bar 覆盖，run `29098058258` 又证明 bottom `safeAreaInset` + 88pt clearance 仍会被浮动栏覆盖，且 `ButtonStyle` 不能替换 `PasteButton` 的系统英文标签。run `29099734744` 已证明中文覆盖生效，但 96pt 外部净空压缩了标准字号首屏，且第四张设置截图被空白检测拦截。run `29100584989` 的完整证据证明固定 48pt 已解决大字号覆盖，却仍把标准字号“翻译”主按钮裁成一条色带。run `29102934707` 证明标准键盘关闭时取消净空可完整恢复“翻译”，但输入聚焦后键盘“完成”区域不可见。当前候选仅在 compact-width 且 Dynamic Type 为 XXL 或更大、或输入已聚焦时，于根 `VStack` 的 `ScrollView` 外预留 48pt；标准字号且键盘关闭时不插入净空，以同时满足首屏动作层级、大字号防遮挡和键盘附件可见。真实 `PasteButton` 继续使用透明前景并由不接收触摸的实底中文标签覆盖。上述旧 run 都只作为失败证据，新 HEAD 必须重新生成 build、JUnit、manifest 和 UI evidence，并由 Agent B 先逐张查看后再交给 Agent C。

云端验收证据（正式收口）：

- 产品 UI evidence HEAD：`c8326bb068e512dbd8139271e65b38ddb3235b9c`（`fix(ui): keep keyboard toolbar visible`）。
- 收口 commit：版本号/文档/contract assert 升到 1.88；merge 前以 push 后新 HEAD 的 CI manifest `commitSha` 核对。
- GitHub Actions run：`29104261998` attempt 1 SUCCESS。
- 结果包：`aitrans-ci-v1.88-codeb-v1.88-home-translation-ui--c8326bb068e5-run29104261998-attempt1`（2,772,091 bytes；SHA256 `f15c2ad59fcaba0eec3ae5795d9adc060bd3e06405374ce7e747a172cc87983e`）。
- `.xcresult`：0 errors / 0 warnings；JUnit 7/7；Speech contract 5/5；v1.87 UI interaction contract 6/6；v1.88 home UI contract 7/7。
- UI evidence：11 张紧凑 iPhone 运行态截图均 >135KB，覆盖空态中文“粘贴/翻译”、键盘“完成”、XXL / Accessibility Tab 净空。
- 本轮收口额外把 `MARKETING_VERSION` 从 `1.87` 升到 `1.88`，并将候选记录改为正式通过。

遗留事项：

- 真实系统 `PasteButton` 剪贴板投递、空剪贴板保留输入、换行追加、VoiceOver 标签与键盘“完成”点击回放未在本机 Simulator/真机重跑；XCUITest 在 iOS 26.5 上难以稳定注入 runner/app 隔离剪贴板。按用户约束不改生产粘贴语义仅为可测性让步；后续可用人工清单或 debug-only 注入补闭环。
- 当前 UI evidence 仍没有 iPad / Mac 运行态截图；宽屏并排只有源码和 Preview 状态，不能当作运行态验收结论。
- 模型、OCR、Speech、StoreKit、持久化、漫画探针、ground truth、仓库根 `output/` 和 `metrics/version_history.csv` 均未修改；本轮不追加漫画指标。
- 收口后进入 v1.89：固化人工交互矩阵、PasteButton 可测性、宽屏证据与首页信息密度再平衡。

### v1.87：企业级视觉系统与核心体验重构
日期：2026-07-10

状态：Agent C 已验收通过，工程正式版本号收口为 `1.87`；PR #40 负责合并到 `smalldata_test`，不触碰 `main`。

核心变更：

- 建立炭灰、冷白、电光青的语义设计 token，统一 canvas、surface、border、状态色、间距、8pt 以内圆角、44pt 触控目标和 Reduce Motion 行为。
- 语义色迁入 Asset Catalog 的日间/夜间变体；设置页提供跟随系统、日间、夜间选择，外观偏好独立保存在 `AppStorage`，不改变 `state.json` schema。
- `ContentView.swift` 从 3277 行缩减为根路由；文本、图片、音频、历史、提示词、设置、模型、Pro 和开发控制台拆为独立文件，继续共享唯一 `TranslationSessionStore`。
- 重做 iPhone 五入口 Tab 和 iPad `NavigationSplitView`；文本工作台、图片检查区、音频运行摘要、历史命令、提示词编辑、模型管理和开发报告使用一致的状态组件与响应式布局。
- 新增隔离 `AppPreviewScenario`，preview 不恢复、不写入生产 `state.json`，覆盖多设备、Dynamic Type、Reduce Motion 及代表性成功/失败/锁定状态。
- 新增 `scripts/capture-ui-evidence.sh` 与候选分支 CI 步骤，复用当前 Debug build 生成带设备、方向、Dynamic Type、状态、Reduce Motion 和 commit SHA 的截图 manifest；当前按人工要求收敛为同一台紧凑 iPhone 上的 11 张竖屏证据，新增提示词、模型和开发路径，iPad / Mac 视觉证据延期，证据步骤失败仍会阻塞 CI。
- 优化云端验证：单台紧凑 iPhone 通过 `bootstatus -b` 等待完整启动，避免“设备已标记 booted 但系统迁移未完成”导致首张截图阻塞，并消除两台新模拟器并行迁移的资源争用；文档-only push 可走 build-skip，UI evidence workflow 变化仍强制 build，Koharu 完整 invalid-fixture 矩阵仅在真实 validator / artifact contract 相关变化时运行。
- Speech contract 仅更新 UI 文件定位，保留取消、`translating` 和运行摘要断言强度。
- Agent C 在 `a925f944` 退回四项：录音按钮缺默认无障碍动作、关闭开发模式未退出开发控制台、Reduce Motion 场景未进入 capturing 分支、八类页面缺独立交互回归证据。当前修复为录音默认 accessibility toggle、`SettingsView` 显式 `NavigationPath` reset、`audioRecognizing.isCapturingProSpeech=true`，并新增 5 项 `test-v187-ui-interaction-contract.py`、独立 CI step / log / manifest 字段 / JUnit testcase。
- Agent C 在 `4a6c05c3` 的键盘截图发现模型状态随整页 `ScrollView` 自动滚动到系统状态栏。当前把文本页头和模型状态移到顶部 safe-area inset，仅让语言栏与翻译工作区参与键盘滚动，并新增对应源码契约，防止页头重新进入自动滚动区。

本地轻量验证：Swift parse、`git diff --check`、PBX/plist lint、shell syntax、workflow YAML parse、5 项 Speech contract、6 项 v1.87 UI interaction contract 和三个 JSON parse；未跑本机 build / 探针，按规则交给云端验证。

Agent C 验收证据：`d2b6ab32` 对应 run `29082220409` attempt 1，manifest 的 branch / commitSha / runId / runAttempt 与 PR HEAD 一致；`.xcresult` 为 `succeeded`、0 errors、0 warnings，JUnit 6/6，UI interaction contract 6/6，11 张紧凑 iPhone 运行态截图全部匹配当前 commit。Agent C 逐张复核日夜、键盘、XXL、Accessibility Dynamic Type、Reduce Motion、提示词、Local 缺模型和开发控制台状态；最终键盘证据中系统状态栏、页头、模型状态、输入区与软件键盘清楚分离。漫画探针为 `probe_mode=skip`，iPad / Mac 视觉证据与 XCUITest 点击回放不在本轮范围；未重跑漫画质量探针，因此不追加 `metrics/version_history.csv` 指标行。

### v1.86：Speech Recognition Insight and Audio UI Polish
日期：2026-07-08

依据：v1.85 已补齐 Koharu draft artifact contract 工具，但用户目标继续扩展到语音识别、云端测试和更精致的 UI。本轮先把音频识别从“只有一条状态文案”升级为可观察的本机识别运行摘要，并改善音频页操作反馈。

核心变更：

- 新增 `SpeechRecognitionRunSummary` 和 `SpeechRecognitionRunMode`，记录音频文件或实时麦克风识别的模式、输入名、locale、本机识别要求、设备支持状态、耗时、词数、分段数、平均置信度、最终文本和失败原因。
- `AudioRecognitionState` 新增 `translating`，区分 Apple Speech 识别中和识别文本交给模型翻译中。
- 文件音频识别和同声传译都会维护 `speechRecognitionRunSummary`；识别失败、权限拒绝、设备不支持、空文本、用户取消都会留下明确失败原因。
- 长按同声传译松手后，主动结束导致的 recognition task cancel error 不再覆盖为失败状态。
- 音频页新增识别质量摘要面板和识别取消入口，展示 locale、强制本机、耗时、词数、片段和置信度，让语音链路更可诊断、UI 信息层次更完整。
- 合并验收补强用 run UUID 隔离授权、Speech 和翻译回调，避免取消/重试后旧任务污染新摘要；当前翻译任务未结束时不启动实时语音采集。
- App bundle ID 统一为 `com.local.aitransform114`；CI 改为从构建 App `Info.plist` 动态读取 bundle ID，并让 `1.*` 版本分支触发合并前快验。
- Xcode `MARKETING_VERSION` 从 `0.1.0` 收口为 `1.86`，CI 也会把纯数字 `1.86` 分支记录为 artifact version `v1.86`。
- 新增 `scripts/test-speech-recognition-contract.py` 并接入 CI static checks；完整 v1.47-v1.86 汇总见 `md/prompt/v1.47-to-v1.86-update-notes.md`。
- 同步 `md/flow/flow.md` 和 `md/flow/flowchart.md` 的音频识别流程。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Views/ContentView.swift`
- `AITRANS/Views/ProFeatureViews.swift`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `.github/workflows/ci-results.yml`
- `scripts/test-speech-recognition-contract.py`
- `md/prompt/v1.47-to-v1.86-update-notes.md`
- `update_log.md`

验证结果：

- 本地轻量验证通过：`git diff --check`、`python3 -m json.tool test/1.ground_truth.json`、`python3 -m json.tool output/clean_text_diagnostic.json`、`python3 -m json.tool output/probe_report.json`。
- 合并验收补强通过：5 个 speech/CI contract tests、plist lint、workflow YAML parse、Swift parse、Python compile、Koharu draft/valid/orientation/missing/invalid fixture smoke。
- Swift / Xcode build 按项目规则交给 GitHub Actions；本轮 push 后需核对 `AITRANS CI Results` 和 `AITRANS - Build IPA`。

遗留事项：

- 本轮不引入第三方语音模型，不改变 Apple Speech 的 on-device 约束；真正“AI 语音识别”质量提升仍需要后续接入更强 ASR 或增加固定音频样本基准。
- 语音 UI 已改善诊断和反馈，但还未做整站级视觉重设计；后续可继续升级工作台、图片页和 Pro 页视觉系统。

### v1.85：Koharu Native Draft Artifact Tool
日期：2026-07-07

依据：v1.84 已把真实 Koharu handoff 后的 CI 结果核对清单补齐，但本地仍缺一个低风险工具，把 AITRANS 当前 probe block / bubble / glyph-mask proxy 以四件套 contract 形状导出，供外部 detector / handoff 开发快速对齐字段。该工具必须保持非 active、非真实 detector 输出，避免把 proxy 冒充为 `test/koharu_artifacts/`。

核心变更：

- 新增 `scripts/make-koharu-native-draft-artifacts.py`，从 `output/probe_report.json` 生成 `build/koharu_native_draft/1.manifest.json`、`1.textboxes.json`、`1.bubbles.json`、`1.segment_mask.json`。
- draft manifest 固定 `contractExampleOnly=true`，记录当前 `test/1.png` SHA256、生成来源、TextBox / Bubble / SegmentMask 来源和 count；当前旧 probe_report 缺 detector-lite 字段时，TextBoxes / BubbleMask 会从最终 probe blocks fallback 生成。
- 生成的草稿目录只用于 contract shape / validator smoke，validator 正确结果是 `verdict = contractExampleOnly`、`readyForShadowOCR = false`、`externalTextBoxesShadowOCRAllowed = false`，不得复制到 active `test/koharu_artifacts/`。
- artifact contract README 和测试规范同步该工具的用途、命令和禁止项。

关键文件：

- `scripts/make-koharu-native-draft-artifacts.py`
- `md/koharu研究/artifact_contract/README.md`
- `md/test/test.md`
- `update_log.md`

验证结果：

- 本地轻量验证通过：`python3 -B -m py_compile scripts/make-koharu-native-draft-artifacts.py`、`python3 scripts/make-koharu-native-draft-artifacts.py --out build/koharu_native_draft`、`python3 scripts/validate-koharu-artifacts.py --root build/koharu_native_draft`。草稿生成 13 个 TextBox、10 个 bubble summary、`segmentGlyphPixelCount = 92827`，validator 输出 `verdict = contractExampleOnly`、`sourceImageSHA256Matches = true`、`readyForShadowOCR = false`、`externalTextBoxesShadowOCRAllowed = false`。

遗留事项：

- 本版本不生成真实 Koharu 四件套、不写入 `test/koharu_artifacts/`、不上传 Release、不触发手动 `ci-fast/full`，不改变 OCR / LLM / renderer / 漫画指标，不追加 `metrics/version_history.csv`。
- 真正复刻效果仍需要外部 detector / Koharu 真实 TextBoxes、BubbleMask、SegmentMask 注入后跑 `ci-fast/full`；后续编译提速建议单独拆 `writeOCRProbeText` 到扩展文件，再云端 Xcode build 验证。

### v1.84：Koharu Handoff CI Result Review Packet
日期：2026-07-07

依据：v1.83 已把 Release archive 本地 inspection proof 写入 handoff packet，但真实 handoff 仍要等 GitHub Actions 手动 `ci-fast/full` 结果包证明 App runtime 实际读取同一组四件套。继续补交付后 Agent C 的云端结果包核对清单，避免错 run、旧包、错 commit 或只凭本地 inspection 放行。

核心变更：

- `handoffPacket` 新增 `ghRunWatchCommand` 和 `ghRunDownloadCommand`，用 `<run-id>` 占位指导人工在 workflow dispatch 后等待并下载 `AITRANS CI Results` 未加密结果包。
- `handoffPacket.ciResultReview` 和 `expected*Assertions` 新增机器可读核对清单，覆盖必需结果文件、探针输出文件、manifest identity、Release tag / asset / SHA 回显、Koharu validator identity / orientation、逐文件 cloud identity rows、App runtime readiness、identity reconciliation、external shadow OCR coverage、orientation blockers、TXT 摘要 needles 和旧包拒收规则。
- CI static package smoke 只断言这些 review / assertion 字段的 shape 和关键语义，不访问 GitHub、不下载 run、不启动模拟器、不把本地 `releaseArchive.inspection` 写成云端 runtime proof。
- artifact contract README 和测试规范同步 v1.84 handoff 后置 review 口径。

关键文件：

- `scripts/validate-koharu-artifacts.py`
- `.github/workflows/ci-results.yml`
- `md/koharu研究/artifact_contract/README.md`
- `md/test/test.md`
- `update_log.md`

验证结果：

- 本地轻量验证通过：`git diff --check`、`python3 -B -m py_compile scripts/validate-koharu-artifacts.py`、workflow YAML parse、JSON parse、Koharu valid / orientation / invalid fixture 矩阵、`test/koharu_artifacts --allow-missing`、fixture package handoff packet、`python3 -m json.tool /tmp/koharu-handoff-v184.json` 和新增 `ciResultReview` / structured assertions 字段 smoke。
- 云端 `AITRANS CI Results` run `28864811074` 通过，artifact `aitrans-ci-unversioned-smalldata_test--13591a80d066-run28864811074-attempt1` 已核对：`branch = smalldata_test`、`commitSha = 13591a80d0663fb3fed83f74e2cb03ddf851a05e`、`runId = 28864811074`、`runAttempt = 1`、`workflowName = AITRANS CI Results`、`xcodeBuildRequired = false`、`xcodeBuildSkippedReason = non_app_build_related_fast_path`、`probeMode = skip`、`scopeDiffMethod = checkout_before`、`scopeDiffFallbackUsed = false`、`koharuValidatorExtendedRequired = true`；`junit.xml` 为 5 tests / 0 failures；fixture package smoke 证明 `releaseArchiveInspectionPassed = true`、`releaseArchiveInspectionVerdict = contractExampleOnly`、`candidateDirectoryCount = 1`、`ghRunWatchCommand` / `ghRunDownloadCommand` 存在、`ciResultReview.requiredResultFiles` 覆盖四个必需文件、`expectedCloudIdentityRows = 5`、`expectedCIManifestAssertions = 14`、`expectedAppRuntimeAssertions = 10`、`expectedExternalShadowOCRAssertions = 8`、`expectedConvergenceAssertions = 6`、`staleRunRejectionAssertions = 5`。
- 同轮 `AITRANS - Build IPA` run `28864811123` 通过，archive 10m45s，IPA package 6s。

遗留事项：

- 本版本仍不生成真实 Koharu 四件套、不上传 Release、不触发手动 `ci-fast/full`，不改变 OCR / LLM / renderer / 漫画指标，不追加 `metrics/version_history.csv`。
- 真实验收仍必须由人工提供外部 detector 输出，按 handoff packet 上传 Release、dispatch `ci-fast/full`，再用 `ciResultReview` 核对云端 App runtime readiness、identity reconciliation、external shadow OCR coverage 和 orientation gates。

### v1.83：Koharu Handoff Archive Inspection Proof
日期：2026-07-07

依据：v1.82 已提供 `--inspect-release-archive` 和带 repo 的 Release upload / workflow dispatch 命令，但 handoff packet 本身还没有把“将上传的 archive 已按 CI 唯一四件套目录规则复验”作为结构化 proof 带给人工和 Agent C。继续补真实 artifact handoff 交付闭环，不新增 report-only 探针层，不改 Swift 主链路。

核心变更：

- `--package-release-archive` 生成 zip 后会立即用 `inspect_release_archive()` 复验该 zip，并把结果写入 `handoffPacket.releaseArchive.inspection`，包含 validation verdict、candidate directory、member count、artifact identity summary 和 orientation summary。
- `handoffPacket` 新增 `releaseArchiveInspectionPassed`、`releaseArchiveInspectionVerdict`、`inspectReleaseArchiveCommand` 和 `expectedCIManifestEcho`，让上传前 proof、Release asset SHA、workflow dispatch 参数和 Agent C 云端 manifest 核对点在同一个 JSON 中闭合。
- handoff ready 现在要求真实 validator verdict、archive SHA 和本地 archive inspection proof 同时成立；`contractExampleOnly` fixture 仍可用于 smoke，但不会被标记为 release / dispatch ready。
- `AITRANS CI Results` static checks 只在 fixture package smoke 中断言 handoff inspection proof，不把 inspection 重新塞回真实 Release 注入主路径，避免增加 workflow 启动风险。

关键文件：

- `scripts/validate-koharu-artifacts.py`
- `.github/workflows/ci-results.yml`
- `md/koharu研究/artifact_contract/README.md`
- `md/test/test.md`
- `update_log.md`

验证结果：

- 本地轻量验证通过：`git diff --check`、`python3 -B -m py_compile scripts/validate-koharu-artifacts.py`、workflow YAML parse、JSON parse、Koharu valid / orientation / invalid fixture 矩阵、`test/koharu_artifacts --allow-missing`、handoff packet、package 拒绝 / 成功 zip 布局、`--inspect-release-archive` 成功 / 空 archive / 双 candidate archive 失败路径、fixture handoff inspection proof、active-like handoff ready + inspection proof。
- 云端 `AITRANS CI Results` run `28861251800` 通过，artifact `aitrans-ci-unversioned-smalldata_test--642c1e2d5683-run28861251800-attempt1` 已核对：`branch = smalldata_test`、`commitSha = 642c1e2d5683339c6c8ae33fc0ff1437bdf17bb7`、`runId = 28861251800`、`runAttempt = 1`、`workflowName = AITRANS CI Results`、`xcodeBuildRequired = false`、`xcodeBuildSkippedReason = non_app_build_related_fast_path`、`probeMode = skip`、`scopeDiffMethod = checkout_before`、`scopeDiffFallbackUsed = false`、`koharuValidatorExtendedRequired = true`；package smoke 证明 `releaseArchiveInspectionPassed = true`、`releaseArchiveInspectionVerdict = contractExampleOnly`、`candidateDirectoryCount = 1`、`expectedCIManifestEcho` 存在，`junit.xml` 为 5 tests / 0 failures。
- 同轮 `AITRANS - Build IPA` run `28861251831` 通过。

遗留事项：

- 本版本仍不生成真实 Koharu 四件套、不上传 Release、不触发手动 `ci-fast/full`，不改变 OCR / LLM / renderer / 漫画指标，不追加 `metrics/version_history.csv`。
- 真实验收仍必须由人工提供外部 detector 输出，按 handoff packet 上传 Release 并 dispatch `ci-fast/full` 后，核对云端 App runtime readiness、identity reconciliation、external shadow OCR coverage 和 orientation gates。

### v1.82：Koharu Release Archive Inspect and Upload Commands
日期：2026-07-07

依据：v1.81 已能从本地四件套生成 Release zip 和 `workflow_dispatch` 参数，但真实 P0 handoff 仍有两个易错点：上传前本地 archive 是否符合 CI 唯一目录规则，以及上传到 GitHub Release / 触发 workflow 是否指向正确 repo。继续补这段交付闭环，比新增 report-only 探针层更接近 `v1.38-current-gap-to-koharu.md` 要求的真实 artifact 注入。

核心变更：

- `scripts/validate-koharu-artifacts.py` 新增 `--inspect-release-archive <zip|tar>`，用 CI 同口径安全解包并检查 archive 中是否恰好有一个包含四个标准 JSON 的目录，输出 archive size/SHA、members、candidate directory 和 validator verdict。
- handoff packet 新增 `--repo`、`--probe-mode` 参数，输出结构化 `releaseUpload`，并生成带 `--repo` 的 `ghReleaseUploadCommand`、`ghWorkflowDispatchCommand` 和 `ghRunListCommand`；默认不加 `--clobber`，避免误覆盖 Release asset。
- `AITRANS CI Results` 继续沿用既有 Release archive 下载、SHA 校验、唯一四件套目录解包、active validator identity / orientation 摘要和 App runtime 证据链；`--inspect-release-archive` 定位为上传前本地 preflight，不作为本轮云端 manifest 新字段。
- CI static checks 保留 package smoke 和 handoff 命令 repo / quote 检查；archive inspect 的 0 / 多 candidate 失败路径由本地轻量验证覆盖，避免在 workflow 内增加容易破坏 GitHub job 启动的复杂脚本块。
- artifact contract README 和测试规范同步 upload / inspect / dispatch / run list 的交付步骤和验收口径。

关键文件：

- `scripts/validate-koharu-artifacts.py`
- `.github/workflows/ci-results.yml`
- `md/koharu研究/artifact_contract/README.md`
- `md/test/test.md`
- `update_log.md`

验证结果：

- 初次提交 `b0c643e` 的 `AITRANS CI Results` run `28855767837` 未能创建 job；后续修复移除 workflow 内 release archive inspection 注入、manifest 和 failure summary 钩子，只保留本地 validator / handoff 能力。
- 本地轻量验证通过：`git diff --check`、`python3 -B -m py_compile scripts/validate-koharu-artifacts.py`、workflow YAML parse、JSON parse、Koharu valid / orientation / invalid fixture 矩阵、`test/koharu_artifacts --allow-missing`、handoff packet、package 拒绝 / 成功 zip 布局、`--inspect-release-archive` 成功 / 空 archive / 双 candidate archive 失败路径、active-like handoff ready smoke。
- 云端结果包待本修复 commit push 后确认：本版本只改 Python validator、workflow static checks 和文档，预期 push CI 走 build-skip；workflow / validator 变化会触发 extended Koharu validator matrix 和 package smoke。

遗留事项：

- 本版本仍不生成真实 Koharu 四件套、不上传 Release、不触发手动 `ci-fast/full`，不改变 OCR / LLM / renderer / 漫画指标，不追加 `metrics/version_history.csv`。
- 真实验收仍必须由人工提供外部 detector 输出，运行 package / inspect / upload / dispatch 命令后，核对云端 App runtime readiness、identity reconciliation、external shadow OCR coverage 和 orientation gates。

### v1.81：Koharu Release Handoff Packet Preflight
日期：2026-07-07

依据：`md/koharu研究/v1.38-current-gap-to-koharu.md` 已明确当前下一步仍是 P0：拿真实 `TextBoxes / BubbleMask / SegmentMask` 四件套，通过 Release archive 注入手动 `ci-fast/full`，看 App runtime readiness、identity reconciliation、external shadow OCR coverage 和 orientation gates。v1.79-v1.80 已收紧 source image SHA contract，但外部 detector 输出到 GitHub Release / workflow_dispatch 的交付路径仍需要人工拼 zip、算 SHA、填参数，容易错包或漏填。

核心变更：

- `scripts/validate-koharu-artifacts.py` 新增 `--emit-handoff-packet`，在 validator 摘要外输出 Release upload / `workflow_dispatch` handoff 清单，包含 source image SHA、四件套 size/SHA、orientation summary、建议的 `probe_mode=ci-fast`、`koharu_artifact_release_tag`、`koharu_artifact_asset`、`koharu_artifact_sha256`、`koharu_artifact_required=true` 和 `gh workflow run` 模板。
- 新增 `--package-release-archive <zip>`，把当前 root 下解析出的四件套打成一个 zip；zip 内只包含一个目录和四个标准 JSON，贴合 CI 的唯一目录检查。
- 打包默认只接受 `verdict = readyForShadowOCR`；`contractExampleOnly` examples 不会被标记为 handoff ready，`--allow-fixture-package` 仅用于本地 smoke。
- handoff packet 区分当前离线 root 的 `externalTextBoxesShadowOCRAllowed` 与 CI 注入 active 目录后的 expected readiness，避免把非 active 路径误读成 App 已消费 artifact。
- 打包路径增加源文件覆盖保护，`ghWorkflowDispatchCommand` 对 tag / asset / SHA 参数做 shell quote。
- `AITRANS CI Results` static checks 增加 package smoke：验证 `contractExampleOnly` fixture 默认拒绝打包、`--allow-fixture-package` 生成单目录四标准 JSON，并检查带空格 dispatch 参数 quote。
- artifact contract README 和测试规范同步新的 preflight / package 命令与 CI package smoke 预期。

关键文件：

- `scripts/validate-koharu-artifacts.py`
- `.github/workflows/ci-results.yml`
- `md/koharu研究/artifact_contract/README.md`
- `md/test/test.md`
- `update_log.md`

验证结果：

- 本地轻量验证通过：`git diff --check`、`python3 -m py_compile scripts/validate-koharu-artifacts.py`、workflow YAML parse、JSON parse、Koharu valid / orientation / invalid fixture 矩阵、`test/koharu_artifacts --allow-missing`、handoff packet、package 拒绝 / 成功 zip 布局和 quote smoke。
- 云端 `AITRANS CI Results` run `28854050132` 通过，artifact `aitrans-ci-unversioned-smalldata_test--54a94b6e992f-run28854050132-attempt1` 已核对：`branch = smalldata_test`、`commitSha = 54a94b6e992f06d5e7d1704d1634d87aca3dffb6`、`xcodeBuildRequired = false`、`xcodeBuildSkippedReason = non_app_build_related_fast_path`、`probeMode = skip`、`scopeDiffMethod = checkout_before`、`scopeDiffFallbackUsed = false`、`koharuValidatorExtendedRequired = true`、`probeOutputRetainedFiles = ["probe-not-run.txt"]`，package fixture smoke 产物存在且 verdict 为 `contractExampleOnly`。
- 同轮 `AITRANS - Build IPA` run `28854050100` 通过。

遗留事项：

- 本版本不生成真实 Koharu 四件套，不上传 Release，不触发手动 `ci-fast/full`，不改变 OCR / LLM / renderer / 漫画指标，不追加 `metrics/version_history.csv`。
- 真实验收仍必须由人工提供外部 detector 输出，运行 handoff packet 生成 zip，上传 Release 后手动 dispatch，并核对云端 App runtime 证据。

### v1.80：App Runtime Source Image SHA Gate
日期：2026-07-07

依据：v1.79 已让 Python validator / CI static smoke 要求 Koharu active manifest 声明 `sourceImageSHA256` 并匹配当前仓库 `test/1.png`，但 Swift App runtime readiness 仍主要核对 source image 路径和 App 可见文件 size / SHA256。如果外部 artifact manifest 在 App 探针内缺失、格式错误或声明了旧图 SHA，必须由 App 侧 readiness、identity receipt、contract dry-run 和 identity reconciliation 同步阻塞，避免 validator 与 runtime handoff 口径分叉。

核心变更：

- `MangaOverlayExternalArtifactManifest` 解析 `sourceImageSHA256`，并记录字段存在性、类型有效性和标准化 SHA。
- `externalArtifactReadinessReport.coordinateValidation` 新增 declared / expected / fieldPresent / typeValid / matches 字段；Swift readiness 现在对缺失、非 64 位 hex 或不匹配 runtime bundle `test/1.png` SHA 的 manifest 输出 `sourceImageSHA256Missing` / `sourceImageSHA256Invalid` / `sourceImageSHA256Mismatch`，并阻止 `readyForShadowOCR`。
- `externalArtifactReadinessReport.artifactIdentityReceipt` 新增 `sourceImageSHA256Declared`、`sourceImageSHA256Expected`、`sourceImageSHA256Matches`；`identityVerdict = activeArtifactIdentityRecorded` 现在要求 manifest SHA 与 App runtime 可见 source image SHA 匹配。
- `koharuNativeArtifactContractDryRunReport` 的 manifest required fields 增加 `sourceImageSHA256=<expected>`，App-side identity gate 也消费 `sourceImageSHA256Matches`。
- `koharuArtifactIdentityReconciliationReport` 顶层新增 declared / expected / matches，`readyForCIManifestComparison` 只有在 source image SHA match 为 true 时才能通过。
- `1_ocr_probe_text.txt` 摘要、CI post-export smoke、`ci-artifact-manifest.json` 的 App receipt / identity reconciliation summaries 和 failure summary 都透传 App runtime source image SHA declared / expected / matches。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `.github/workflows/ci-results.yml`
- `README.md`
- `md/test/test.md`
- `update_log.md`

验证结果：

- 本地轻量验证通过：`git diff --check`、JSON 解析、workflow YAML parse、workflow Python heredoc 编译、Koharu validator valid / invalid fixture 矩阵。
- 云端 `AITRANS CI Results` run `28851345305` 通过，artifact `aitrans-ci-unversioned-smalldata_test--5668ab847c01-run28851345305-attempt1` 已核对：`branch = smalldata_test`、`commitSha = 5668ab847c0148201e26010a95de2a92306a92a4`、`xcodeBuildRequired = true`、`xcode build = success`、`probeMode = skip`、`scopeDiffMethod = checkout_before`、`scopeDiffFallbackUsed = false`、`changedFiles = ["AITRANS/Models/TranscriptModels.swift"]`。
- 同轮 `AITRANS - Build IPA` archive 编译阶段已成功，但上传 archive log 时 GitHub artifact service 多次 timeout，属于打包 artifact 上传失败，不是 Swift 编译失败。

遗留事项：

- 本版本不新增真实 Koharu 四件套，不改变 OCR / LLM / renderer / 覆盖图 / active artifact，不追加 `metrics/version_history.csv`。
- 需要真实 handoff 验收时，仍需手动 `workflow_dispatch` 选择 `ci-fast` 或 `full` 并注入 Koharu artifact archive，核对 App receipt 与 reconciliation 的 `sourceImageSHA256Matches = true`。

### v1.79：Koharu Source Image SHA Contract Gate
日期：2026-07-07

依据：v1.66-v1.78 已让 CI / App 侧记录 source image 和四件套 size / SHA256 identity，但 Koharu active manifest 仍只声明 `sourceImage = test/1.png`，没有强制声明“本 artifact 是基于当前仓库这张 `test/1.png` 生成”。如果外部 detector 用旧图、裁切图或错图导出，路径和尺寸可能看似正确，后续云端 handoff 仍有误接风险。

核心变更：

- `scripts/validate-koharu-artifacts.py` 要求 manifest 声明 `sourceImageSHA256`，并校验它必须匹配当前仓库 `test/1.png` 的实际 SHA256：`9c3dc0ee9dfc4a6b664c4b4dd32e5b74b214f6f0d16f32ef97ef02ce47c2ed21`。
- validator 输出新增 `sourceImageSHA256`、`expectedSourceImageSHA256`、`sourceImageSHA256Matches`，`artifactIdentitySummary` 新增 `sourceImageSHA256Declared`、`sourceImageSHA256Expected`、`sourceImageSHA256Matches`，并新增 `sourceImageSHA256Missing` / `sourceImageSHA256Invalid` / `sourceImageSHA256Mismatch` verdict。
- CI 注入真实 Koharu artifact 和 valid fixture smoke 都会断言 manifest 声明 SHA 与仓库 source image SHA 一致；完整 invalid fixture 矩阵新增 `source_image_sha_missing` 和 `source_image_sha_mismatch`。
- artifact contract README、`md/test/test.md` 和示例 manifests 同步新的 source image SHA contract。

关键文件：

- `scripts/validate-koharu-artifacts.py`
- `.github/workflows/ci-results.yml`
- `md/koharu研究/artifact_contract/README.md`
- `md/koharu研究/artifact_contract/examples/**/1.manifest.json`
- `md/test/test.md`
- `update_log.md`

验证结果：

- 待本轮本地轻量验证与 push 后云端结果包确认：预期 workflow / validator / contract 变更会触发 extended Koharu invalid fixture matrix，且本轮仍不涉及 Swift / Xcode 工程 / `test/` 素材，预期 `xcodeBuildRequired = false`。

遗留事项：

- 本版本不新增真实 Koharu 四件套，不改变 OCR / LLM / renderer / 漫画指标，不追加 `metrics/version_history.csv`。
- 如果未来 `test/1.png` 变更，所有 active artifact 和 contract fixtures 必须同步新的 `sourceImageSHA256`，否则 validator 应阻塞 handoff。

### v1.78：CI Scope Targeted Fetch Closure
日期：2026-07-07

依据：v1.76 用 `fetch-depth: 2` 修复了普通单提交 push 的 scope diff，但遗留事项仍指出：如果一次 push 包含多提交且 `github.event.before` 不在最近 2 个提交内，`Detect CI scope` 仍会回退 `git ls-files`，把 `changed-files.txt` 变成全仓列表，进而误触发 Xcode build 和 extended Koharu validator。v1.77 已让结果包可追溯，本轮继续把 scope diff 方法本身变成可审计证据。

核心变更：

- `Detect CI scope` 在 checkout 内找不到 `github.event.before` 时，先执行定向 `git fetch --no-tags --depth=1 origin <before>`，成功后继续按真实 before SHA diff。
- 只有 checkout 和 targeted fetch 都无法拿到 before commit 时，才回退 `git ls-files` 全仓列表。
- CI 输出、manifest 和 failure summary 新增 `scopeDiffMethod`、`scopeDiffBaseSha`、`scopeDiffFallbackUsed`，Agent C 可判断 changed-files 是否来自 `checkout_before`、`targeted_fetch` 或 `full_repo_fallback`。
- `md/test/test.md` 同步多提交 push 的 scope diff 验收口径。

关键文件：

- `.github/workflows/ci-results.yml`
- `md/test/test.md`
- `update_log.md`

验证结果：

- 待本轮本地轻量验证与 push 后云端结果包确认：普通单提交 push 预期 `scopeDiffMethod = checkout_before`、`scopeDiffFallbackUsed = false`；若后续出现多提交 push 且 before 不在浅克隆内，预期使用 `targeted_fetch` 而不是全仓 fallback。

遗留事项：

- 本版本不新增真实 Koharu 四件套，不改变 OCR / LLM / renderer / 漫画指标，不追加 `metrics/version_history.csv`。
- 若极端情况下 GitHub 不允许按 SHA 定向 fetch，workflow 仍会显式记录 `full_repo_fallback`，避免 Agent C 把全仓 changed-files 误认为精确 diff。

### v1.77：CI Artifact Provenance Self-Trace
日期：2026-07-07

依据：v1.76 已让 build-skip 结果包更干净，但 Agent C 下载未加密 artifact 后仍需要从 GitHub UI 或 `gh run view` 反查 run URL、artifact name、event/ref/repository 和变更范围。后续真实 Koharu artifact handoff 会更依赖“拿到的包就是目标 run / 目标提交 / 目标变更”的机器可核对证据，因此本轮继续增强 CI 结果包可追溯性。

核心变更：

- `ci-artifact-manifest.json` 新增 `artifactName`、`eventName`、`repository`、`ref`、`refName` 和 `runUrl`，让结果包自带 GitHub run 与 artifact identity。
- `ci-artifact-manifest.json` 新增 `changedFilesCount`、`changedFilesSHA256` 和 `changedFiles`，直接记录本轮 scope detection 的文件列表和稳定哈希。
- `ci-failure-summary.md` 同步打印 run URL、event/ref/repository、artifact name、changed files count 和 changed files SHA256，便于失败时快速定位。
- `md/test/test.md` 补充 v1.77 结果包 provenance 字段验收口径。

关键文件：

- `.github/workflows/ci-results.yml`
- `md/test/test.md`
- `update_log.md`

验证结果：

- 待本轮本地轻量验证与 push 后云端结果包确认：预期 manifest 能解析并包含 self-trace 字段；failure summary 顶部能直接看到 run URL、artifact name 和 changed-files 摘要。本轮仍是 CI / 文档变更，预期 `xcodeBuildRequired = false`。

遗留事项：

- 本版本不新增真实 Koharu 四件套，不改变 OCR / LLM / renderer / 漫画指标，不追加 `metrics/version_history.csv`。
- 若未来需要限制 manifest 体积，可保留 `changedFilesSHA256` 和 count，将完整 `changedFiles` 迁移为单独文件引用；当前普通 push 变更列表很小，直接内嵌更利于验收。

### v1.76：CI Scope Diff Accuracy / Skip Probe Artifact Hygiene
日期：2026-07-07

依据：v1.75 云端 push run `28844582258` 虽然只改 workflow 和日志，但 `changed-files.txt` 回退成全仓列表，导致 `xcodeBuildRequired = true` 并额外跑 Xcode build。原因是 `actions/checkout` 默认浅克隆只含当前提交，`Detect CI scope` 找不到 `github.event.before` 时只能回退 `git ls-files`。这会削弱非 App 改动的 build-skip 加速路径。同轮审计还发现 `probe_mode=skip` 会把仓库中已有的旧 `output/` 复制进结果包，容易让 Agent C 误读为本次云端探针产物。

核心变更：

- `AITRANS CI Results` 的 checkout 增加 `fetch-depth: 2`，让普通单提交 push 能 diff 到 `github.event.before`，避免浅克隆缺 before commit 时误判全仓变化。
- `Copy available probe outputs` 只在 `probe_mode != skip` 且 `manga_probe` 成功时复制本轮 `output/`；skip 或探针失败时只写 `output/probe-not-run.txt`，不再把 checked-in 旧 JSON / TXT / PNG 混入本次 CI artifact。
- `md/test/test.md` 补充 scope detection 和 skip probe artifact hygiene 要求，明确 build-skip 结果包不能被旧探针输出污染。

关键文件：

- `.github/workflows/ci-results.yml`
- `md/test/test.md`
- `update_log.md`

验证结果：

- 待本轮本地轻量验证与 push 后云端结果包确认：预期本次仅 workflow / 文档变更时 `xcodeBuildRequired = false`，`xcodeBuildSkippedReason = non_app_build_related_fast_path`，`changed-files.txt` 只列本次变更文件；`probeMode = skip` 时 `probeReportPath` 为空，`probeOutputRetainedFiles = ["probe-not-run.txt"]`。

遗留事项：

- `fetch-depth: 2` 覆盖普通单提交 push；若后续一次 push 包含多提交且 `before` 不在最近 2 个提交内，仍可能回退全仓列表。需要时再升级为按 SHA 定向 fetch，而不是直接全量 checkout。
- 本版本不新增真实 Koharu 四件套，不改变 OCR / LLM / renderer / 漫画指标，不追加 `metrics/version_history.csv`。

### v1.75：CI Manifest Step Split / Workflow Startup Fix
日期：2026-07-07

依据：v1.74 把 native-lite manifest 摘要直接塞进 `Write manifest`，使该 GitHub Actions 单步脚本从上一版约 20k 字符增长到约 26k 字符。最新 push 的 `AITRANS CI Results` run `28844255398` 在 0 秒失败且没有 job/log，`gh run view` 明确提示 workflow file issue；这符合单步 `run:` 脚本过大导致 workflow 启动前被拒绝的风险。

核心变更：

- `AITRANS CI Results` 保留 v1.74 的 `koharuNativeLiteReportSummary` 与 `koharuNativeLiteConvergenceGateSummary` manifest 字段，但改由独立 `Append native-lite manifest summary` step 读取已生成的 `ci-artifact-manifest.json` 和可用 `probe_report.json` 后追加。
- `Write manifest` step 恢复到上一轮成功版本的脚本体积，避免继续触发 workflow 启动阶段失败；native-lite 追加 step 在 `probe_mode=skip` 时仍写出字段，值来自空 probe summary，便于 Agent C 看到字段存在。
- 产物结构、字段名、probe 路径、Swift 逻辑、OCR / LLM / renderer 和 active artifact gate 不变。

关键文件：

- `.github/workflows/ci-results.yml`
- `update_log.md`

验证结果：

- 本地轻量验证通过：`git diff --check`、`.github/workflows/ci-results.yml` YAML parse、workflow Python heredoc 语法编译、`python3 -m json.tool` 解析 `test/1.ground_truth.json` / `output/probe_report.json` / `output/clean_text_diagnostic.json`。
- 拆分后 workflow 单步脚本体积：`Write manifest = 20176 chars`，`Append native-lite manifest summary = 5996 chars`。

遗留事项：

- 需要 push 后重新触发 `AITRANS CI Results`，下载结果包确认 manifest 字段存在且本次 run 不再 0 秒失败。
- 本版本不新增真实 Koharu 四件套，不改变漫画质量指标，不追加 `metrics/version_history.csv`。

### v1.74：Native-Lite CI Summary / Gap Roadmap Refresh
日期：2026-07-07

依据：v1.39-v1.46 的 detector-lite、shadow OCR、refinement、closed-loop、BubbleMask instance-lite、SegmentMask refinement-lite、bundle-lite 和 promotion gate-lite 已进入 Swift 报告与 convergence，但云端 `ci-artifact-manifest.json` / `ci-failure-summary.md` 仍主要汇总 external artifact handoff、contract dry-run、identity 和 external shadow OCR。Agent C 若要判断 native-lite 阻塞，仍需深挖完整 `probe_report.json`；同时 `md/koharu研究/v1.38-current-gap-to-koharu.md` 的推荐路线仍把部分已完成 report-only 层写成未来任务。

核心变更：

- `AITRANS CI Results` manifest 新增 `koharuNativeLiteReportSummary`，直接汇总 v1.39-v1.46 native-lite report 的 verdict、关键 count、TextBox -> SegmentMask linkage breakdown、needs-real-artifact blocks 和 promotion preview 状态。
- manifest 新增 `koharuNativeLiteConvergenceGateSummary`，直接摘出 detector-lite、shadow OCR、refinement、closed-loop、BubbleMask instance-lite、SegmentMask refinement-lite、bundle-lite、promotion gate-lite 及 linkage work item / gate 的 status、blocks、nextAction 和 decision signals。
- `ci-failure-summary.md` 的 Koharu artifact gate 区块新增 native-lite report / convergence gate 摘要，方便 Agent C 在失败摘要里直接看到 native-lite 阻塞位置。
- `ci-fast/full` smoke 扩展 `1_ocr_probe_text.txt` needles，要求 native-lite report summary 存在，防止 TXT 快照悄悄丢失 v1.39-v1.46 证据。
- `md/koharu研究/v1.38-current-gap-to-koharu.md` 标注原推荐版本路线为历史判断，说明 v1.39-v1.46 已以 report-only / proxy 形式完成；当前下一步仍是注入真实四件套跑 `ci-fast/full`，不是重复实现同名 detector-lite / promotion gate。
- README 与测试规范同步 v1.74 manifest 字段和验收口径。

关键文件：

- `.github/workflows/ci-results.yml`
- `README.md`
- `md/test/test.md`
- `md/koharu研究/v1.38-current-gap-to-koharu.md`
- `update_log.md`

验证结果：

- 本地轻量验证通过：`git diff --check`、`.github/workflows/ci-results.yml` YAML parse、workflow 内 11 个 Python heredoc 语法编译、`python3 -m json.tool` 解析 `test/1.ground_truth.json` / `output/probe_report.json` / `output/clean_text_diagnostic.json`、基于云端 `ci-fast` run `28842227463` artifact 的 native-lite manifest summary helper 离线 smoke。

遗留事项：

- 本版本不新增 detector、OCR、LLM、PNG、renderer 或 active Koharu artifact，不改变主 OCR、翻译、覆盖图、report-only 账本语义或漫画质量指标，不追加 `metrics/version_history.csv`。
- 缺真实 `test/koharu_artifacts/` 时，native-lite 仍是 proxy / report-only；真实收益仍必须等外部四件套注入后看 external shadow OCR、orientation 和 identity handoff。

### v1.73：Cloud ci-fast Evidence / Swift Warning Cleanup
日期：2026-07-07

依据：v1.72 新增 CI manifest 的 Koharu contract dry-run 与 convergence gate summary 后，需要用真实云端 `ci-fast` 探针确认这些字段在非 skip 路径可用；同一轮 Xcode 日志显示 4 处 Swift unused-value warning，虽不影响构建，但会增加后续 Agent C 读日志噪声。

核心变更：

- 云端手动 `ci-fast` run `28842227463` 已验证 commit `599443891e780155ba62773a6e1bdc7090b3ee6c` 的未加密 CI 结果包可用：GGUF 下载 / SHA 校验、静态检查、Xcode build、模拟器 build、漫画探针和 artifact 上传均成功。
- 结果包 `aitrans-ci-unversioned-smalldata_test--599443891e78-run28842227463-attempt1` 的 manifest 匹配 `branch = smalldata_test`、`runAttempt = 1`、`workflowName = AITRANS CI Results`、`probeMode = ci-fast`、`mangaProbeOutcome = success`；`junit.xml` 为 5 tests / 0 failures，并包含 `.xcresult`、`probe_report.json`、`clean_text_diagnostic.json`、`1_ocr_probe_text.txt` 和核心 PNG。
- 真实探针路径已填充 `koharuNativeArtifactContractDryRunSummary` 与 `koharuArtifactConvergenceGateSummary`；缺 active artifact 时 contract dry-run 正确为 `blockedByMissingActiveArtifacts`，coverage / orientation gate 保持 open / not evaluated，`G-ci-fast-report-availability` 为 passed 且 `requiredReportSpan = v1.24-v1.70`。
- 清理 `MangaOverlayProbeService` 与 `TranslationSessionStore` 中不参与逻辑的 unused-value 绑定，减少 Xcode build 日志噪声，不改变主 OCR、翻译、覆盖图、report-only 账本或 active artifact gate。

关键文件：

- `AITRANS/Services/MangaOverlayProbeService.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `update_log.md`

验证结果：

- 云端 `ci-fast` 探针：run `28842227463` 成功，`engineUsed = Local GGUF`、`decodingMode = deterministic`、`totalBlocksDetected = 13`、`passedBlocks = 1`、`failedBlocks = 12`、clean text `5 / 11` 通过，缺 active artifact 的 external shadow OCR 正确阻塞在 `manifestMissing`。

遗留事项：

- 本版本不新增 detector、OCR、LLM、PNG、renderer 或 active Koharu artifact，不改变漫画质量指标，不追加 `metrics/version_history.csv`。
- 缺真实 `test/koharu_artifacts/` 时，external TextBox shadow OCR / orientation path 仍只能验证阻塞和报告完整性；真实 artifact handoff 仍需后续注入四件套后再跑 `ci-fast` / `full`。

### v1.72：CI Artifact Convergence Gate Summary Closure
日期：2026-07-07

依据：v1.70-v1.71 已要求 Agent C 核对 coverage / orientation convergence gate、contract dry-run 和 App-side identity，但 `ci-artifact-manifest.json` 与 `ci-failure-summary.md` 仍主要打印 validator / readiness / shadow OCR 原始摘要，Agent C 需要深挖 `probe_report.json` 才能看到 work item / gate status、blocks 和 `G-ci-fast-report-availability` decision signals。

核心变更：

- `AITRANS CI Results` manifest 新增 `koharuNativeArtifactContractDryRunSummary` 和 `koharuArtifactConvergenceGateSummary`，直接汇总 contract dry-run、App-side identity、coverage / orientation work item 与 gate、identity reconciliation gate、`G-ci-fast-report-availability` 的 decision signals。
- artifact-requested smoke 新增 `G-ci-fast-report-availability.requiredReportSpan = v1.24-v1.70`、`missingReportCount`、`missingReports` 断言，并扩展 TXT needles，确保 coverage / orientation / OCR success / App-side identity 摘要存在。
- `ci-failure-summary.md` 的 Koharu artifact gate 区块补充 external shadow OCR counts、contract dry-run safety、coverage / orientation convergence work item / gate 状态和 report availability signals，降低 Agent C 找错包或漏看 blocker 的概率。
- README、flow、测试规范同步 build-skip 快路径口径：只有 `xcodeBuildRequired=true` 时 `.xcresult` 是必需编译证据，build-skip 必须看 manifest skip reason。

关键文件：

- `.github/workflows/ci-results.yml`
- `README.md`
- `md/flow/flow.md`
- `md/test/test.md`
- `md/koharu研究/v1.38-current-gap-to-koharu.md`
- `update_log.md`

验证结果：

- 本地轻量验证通过：`git diff --check`、`.github/workflows/ci-results.yml` YAML parse、workflow 内 6 个 Python heredoc 语法编译、`python3 -m json.tool` 解析 `test/1.ground_truth.json` / `output/probe_report.json` / `output/clean_text_diagnostic.json`、Koharu validator allow-missing、`contract_example_only_invalid --expect-fail`、新增 manifest summary helper 离线 smoke。

遗留事项：

- 该版本不新增 detector、OCR、LLM、PNG、renderer 或 active Koharu artifact；未重新跑完整漫画探针，不改变漫画质量指标，不追加 `metrics/version_history.csv`。

### v1.71：Convergence Dependency Span / CI Handoff Documentation Closure
日期：2026-07-07

依据：v1.70 已完成 App/CI artifact handoff strict closure 并通过云端 push 快验，但 `koharuArtifactConvergenceReport`、测试规范和 artifact contract README 仍有少量 v1.68 / v1.69 口径残留，容易让后续 Agent C 按旧 dependency span 或 validator-only preflight 验收。

核心变更：

- `G-ci-fast-report-availability` 的 threshold、`requiredReportSpan` 和 notes 从 `v1.24-v1.68` 更新为 `v1.24-v1.70`，纳入 shadow OCR coverage closure 与 App/CI handoff strict closure。
- `README.md`、`md/flow/flow.md`、`md/test/test.md` 明确：填写 Koharu artifact archive 时必须跑 `ci-fast` 或 `full`，不能用 `probe_mode=skip`；coverage / orientation work item 与 gate ID、status、TXT 摘要和 App-side identity 都是验收证据。
- `md/koharu研究/artifact_contract/README.md` 将旧 v1.15 清单改成 v1.70+ active artifact / validator preflight 清单，并明确 validator 通过不等于 Agent C 可验收，云端闭环还必须核对 contract dry-run、identity reconciliation、shadow OCR coverage 和 orientation blockers。
- `md/koharu研究/v1.38-current-gap-to-koharu.md` 补 v1.70 云端 run 证据和 v1.71 后补充。

关键文件：

- `AITRANS/Services/TranslationSessionStore.swift`
- `README.md`
- `md/flow/flow.md`
- `md/test/test.md`
- `md/koharu研究/artifact_contract/README.md`
- `md/koharu研究/v1.38-current-gap-to-koharu.md`
- `update_log.md`

验证结果：

- 本地轻量验证通过：`git diff --check`、`python3 -m json.tool test/1.ground_truth.json`、`python3 -m json.tool output/probe_report.json`、`python3 -m json.tool output/clean_text_diagnostic.json`、`swiftc -parse $(rg --files AITRANS -g '*.swift')`、`scripts/validate-koharu-artifacts.py --root test/koharu_artifacts --allow-missing`、valid fixture validator、`contract_example_only_invalid --expect-fail`。

遗留事项：

- 该版本不新增 detector、OCR、LLM、PNG、renderer 或 active Koharu artifact；未重新跑完整漫画探针，不改变漫画质量指标，不追加 `metrics/version_history.csv`。

### v1.70：Koharu Artifact App / CI Handoff Strict Closure
日期：2026-07-07

依据：v1.69 已把 validator manifest 显式字段和 external shadow OCR coverage gate 收紧，但 App 侧仍需要显式保留 manifest 字段缺失 / 类型错误证据；CI smoke 也需要核对 `ocrSucceededCount`、coverage / orientation work item 与 gate ID；同时 “填写 Koharu artifact archive 但 `probe_mode=skip`” 会导致只验证下载和 validator，不能证明 App 实际消费 artifact。

核心变更：

- `MangaOverlayExternalArtifactManifest` 新增 `sourceImageFieldPresent`、`sourceImageTypeValid`、`contractExampleOnlyFieldPresent`、`contractExampleOnlyTypeValid`，让 Swift readiness 能区分缺字段、类型错误和真实值。
- `externalArtifactReadinessReport` / `externalArtifactIdentityReceipt` / nextAction 新增 `sourceImageMissing`、`contractExampleOnlyMissing`、`contractExampleOnlyInvalid` 分支；ready artifact 的 orientation gate 未闭合时从 warning 收紧为 blocked。
- `1_ocr_probe_text.txt` 的 external TextBox shadow OCR 行补出 `ocrSucceeded`，convergence 摘要补出 coverage / orientation work item status、gate status 和 gate blocks。
- GitHub Actions extended validator matrix 新增 `contract_example_only_invalid`；artifact requested 的探针 smoke 硬核对 `ocrSucceededCount > 0`、coverage / orientation work item 与 gate ID、coverage gate passed，以及 orientation gate 不得在仍有 blockers 时 passed。
- CI metadata 禁止 Koharu artifact archive 与 `probe_mode=skip` 组合；真实四件套注入必须用 `ci-fast` 或 `full` 产生 App 侧证据。
- 同步更新 Koharu contract README、流程文档、流程图和测试规范；新增 invalid fixture `contract_example_only_invalid`。

关键文件：

- `.github/workflows/ci-results.yml`
- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `md/koharu研究/v1.38-current-gap-to-koharu.md`
- `md/koharu研究/artifact_contract/README.md`
- `md/koharu研究/artifact_contract/examples/invalid/contract_example_only_invalid/*`
- `update_log.md`

验证结果：

- 本地轻量验证通过：`git diff --check`、YAML smoke、JSON 解析、Swift `swiftc -parse`、Koharu validator matrix。
- 云端 push 快验通过：commit `6b53da9bb3005afbc9bc4bd5d1a8d05e06ca37cf`；`AITRANS CI Results` run `28840108595` 成功，manifest 匹配 `branch = smalldata_test`、`commitSha = 6b53da9bb3005afbc9bc4bd5d1a8d05e06ca37cf`、`xcodeBuildRequired = true`、`xcodeBuildOutcome = success`、`.xcresult` 存在，JUnit `5` tests / `0` failures，默认 push `probeMode = skip`、`mangaProbeOutcome = skipped`，extended validator required 并正确拒绝 `contract_example_only_invalid`。
- 云端打包通过：`Build IPA` run `28840108614` 成功。
- 未跑本机 Xcode build / 模拟器漫画探针；按规则交给 GitHub Actions build 和手动 `ci-fast` / `full` 探针验证。

遗留事项：

- 该版本不提供真实 Koharu artifact，也不创建 active `test/koharu_artifacts/`；缺真实 artifact 时仍只输出 readiness blocked / identity missing。
- 该版本不新增 detector、OCR、LLM、PNG 或 renderer 算法，不改变主 OCR、`finalTextUsedForTranslation`、翻译、覆盖图、`blockPassed`、active artifact 或 `configuration.currentBlockSource`。
- 未重新跑完整探针，不改变漫画质量指标，不追加 `metrics/version_history.csv`。

### v1.69：External Artifact Validator / Shadow OCR Coverage Closure Gate
日期：2026-07-07

依据：v1.65-v1.68 已把真实 Koharu artifact 的 validator identity、App-side receipt、identity reconciliation 和 external shadow OCR coverage 接进 CI / convergence，但仍有两个闭环风险：一是 validator 对 active manifest 缺 `sourceImage` 或缺 `contractExampleOnly` 会走默认值，可能放宽真实 artifact 准入；二是 convergence 的 external shadow OCR coverage 只要求 `executed = true` 和 `candidateCount > 0`，没有把实际 crop OCR 执行数 / 成功数纳入闭合条件，且 ready artifact 未闭合时 gate status 仍是 warning。

核心变更：

- `scripts/validate-koharu-artifacts.py` 现在要求 manifest 显式声明 `sourceImage = test/1.png` 和布尔型 `contractExampleOnly`；缺失分别输出 `sourceImageMissing` / `contractExampleOnlyMissing`，非布尔 `contractExampleOnly` 输出 `contractExampleOnlyInvalid:*`，均阻止 `readyForShadowOCR`。
- 新增 invalid fixtures：`source_image_missing` 与 `contract_example_only_missing`，并接入 GitHub Actions extended Koharu validator matrix。
- `koharuArtifactConvergenceReport` 的 `WI/G-external-textbox-shadow-ocr-coverage` 在真实 artifact ready 后新增 `ocrExecutedCount > 0` 和 `ocrSucceededCount > 0` 闭合条件；未闭合时 gate status 从 warning 升为 blocked。
- `G-ci-fast-report-availability` 的 threshold / decision signals 更新为当前 v1.24-v1.68 依赖集合，并写出 `missingReportCount`、`missingReports` 和 `requiredReportSpan`，避免旧 v1.24-v1.27 文案误导 Agent C。

关键文件：

- `scripts/validate-koharu-artifacts.py`
- `.github/workflows/ci-results.yml`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AGENTS.md`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `md/koharu研究/artifact_contract/README.md`
- `md/koharu研究/artifact_contract/examples/invalid/source_image_missing/*`
- `md/koharu研究/artifact_contract/examples/invalid/contract_example_only_missing/*`
- `update_log.md`

验证结果：

- 本地轻量验证已通过；云端 commit `c1d5990df733d5593de57b4631c8e4120658dcb7` 的 `AITRANS CI Results` run `28839023072` 成功，`Build IPA` run `28839023071` 成功。默认 push 探针为 `skip`，未生成新的漫画探针报告。

未跑本机 Xcode build / 模拟器漫画探针；按规则交给 GitHub Actions build 和手动 `ci-fast` / `full` 探针验证。

遗留事项：

- 该版本不提供真实 Koharu artifact，也不创建 active `test/koharu_artifacts/`；缺真实 artifact 时仍只输出 readiness blocked / identity missing。
- 该版本不新增 OCR / LLM / PNG，不改变主 OCR、`finalTextUsedForTranslation`、翻译、覆盖图、`blockPassed`、active artifact 或 `configuration.currentBlockSource`。
- 未重新跑完整探针，不改变漫画质量指标，不追加 `metrics/version_history.csv`。

### v1.68：Koharu Artifact Identity Reconciliation Gate
日期：2026-07-06

依据：v1.67 已把 App 探针 runtime 可见的 source image 与四件套 size / SHA256 写入 `artifactIdentityReceipt`，但 Agent C 仍需要手工把这些值与 `ci-artifact-manifest.koharuArtifactValidationIdentitySummary` 对齐。真实 artifact handoff 需要一个可机器核对的对账表和 CI match verdict，防止 validator 校验的是一组文件、App 消费的是另一组文件。

核心变更：

- 新增 `koharuArtifactIdentityReconciliationReport`，把 App receipt 规范化为 SourceImage + manifest / TextBoxes / BubbleMask / SegmentMask 五行 ledger，逐行写出 App size / SHA256、receipt 状态、contract dry-run identity status，以及 CI manifest identity 的 size / SHA 字段路径。
- `koharuArtifactConvergenceReport` 新增 `WI-koharu-artifact-identity-reconciliation` / `G-koharu-artifact-identity-reconciliation-ready`，并让 external shadow OCR coverage gate 在真实 artifact ready 后同时要求 reconciliation ready。
- GitHub Actions 在注入真实 Koharu artifact 并跑 `ci-fast/full` 后，会比较 validator identity 与 App reconciliation rows 的 size / SHA256，失败时阻断；`ci-artifact-manifest.json` 新增 App receipt summary、reconciliation summary 和 `koharuArtifactIdentityReconciliationMatch`。
- `1_ocr_probe_text.txt` 新增 reconciliation report、逐文件对账行和 convergence work item 摘要，方便 Agent C 直接核对。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `.github/workflows/ci-results.yml`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `md/koharu研究/v1.38-current-gap-to-koharu.md`
- `update_log.md`

验证结果：

- 本轮本地轻量验证见最终回复。

未跑本机 Xcode build / 模拟器漫画探针；按规则交给 GitHub Actions build 和手动 `ci-fast` / `full` 探针验证。

遗留事项：

- 该版本不提供真实 Koharu artifact，也不创建 active `test/koharu_artifacts/`；缺真实 artifact 时 reconciliation 会保持 App receipt incomplete / not ready。
- 该版本不新增 OCR / LLM / PNG，不改变主 OCR、`finalTextUsedForTranslation`、翻译、覆盖图、`blockPassed`、active artifact 或 `configuration.currentBlockSource`。
- 未重新跑完整探针，不改变漫画质量指标，不追加 `metrics/version_history.csv`。

### v1.67：App-Side Koharu Artifact Identity Receipt
日期：2026-07-06

依据：v1.66 已在 validator / CI manifest 中记录 Release archive 注入的四件套 identity，但 App 侧探针报告仍缺少运行时实际可见文件的 size / SHA256 receipt。Agent C 需要同时核对 CI manifest identity 与 `probe_report.json` 中 App runtime receipt，才能确认不是只下载 / 校验了 archive，而是 App 探针确实消费到同一组 active artifact 文件。

核心变更：

- `externalArtifactReadinessReport` 新增 `artifactIdentityReceipt`，记录 App bundle / runtime 中 `test/1.png`、manifest、TextBoxes、BubbleMask、SegmentMask 的存在性、size、SHA256、manifest schema / coordinate space / generatedBy / generatedAt / contractExampleOnly 和 `identityVerdict`。
- `koharuNativeArtifactContractDryRunReport` 新增 App 侧 identity 顶层摘要，并把每个 required file 的 `fileSizeBytes`、`sha256`、`identityStatus` 写入 dry-run file ledger；真实 artifact ready 时，contract dry-run ready 现在要求 App 侧 receipt 完整。
- `koharuArtifactConvergenceReport` 的 external shadow OCR coverage decision signals 透传 App 侧 identity verdict / files / hashes，`1_ocr_probe_text.txt` 同步打印 App 侧 identity 摘要和 required file SHA，方便 Agent C 对齐 `ci-artifact-manifest.koharuArtifactValidationIdentitySummary`。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `AGENTS.md`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `md/koharu研究/v1.38-current-gap-to-koharu.md`
- `update_log.md`

验证结果：

- 本轮本地轻量验证见最终回复。

未跑本机 Xcode build / 模拟器漫画探针；按规则交给 GitHub Actions build 和手动 `ci-fast` / `full` 探针验证。

遗留事项：

- 该版本不提供真实 Koharu artifact，也不创建 active `test/koharu_artifacts/`；缺真实 artifact 时 App 侧 receipt 会稳定记录 active 目录缺失 / required identity files missing。
- 该版本不新增 OCR / LLM / PNG，不改变主 OCR、`finalTextUsedForTranslation`、翻译、覆盖图、`blockPassed`、active artifact 或 `configuration.currentBlockSource`。
- 未重新跑完整探针，不改变漫画质量指标，不追加 `metrics/version_history.csv`。

### v1.66：Koharu Artifact Identity / Contract Dry-Run Coverage Gate
日期：2026-07-06

依据：v1.65 已把 orientation summary 和 external shadow OCR coverage gate 接进 CI / convergence，但真实 Koharu archive 注入仍缺少两个验收细节：一是 Agent C 不能快速核对 active 四件套的文件身份是否与本轮 Release archive / source image 对齐；二是 `WI/G-external-textbox-shadow-ocr-coverage` 只要求 readiness 与 shadow OCR executed / candidateCount，还没有把 contract dry-run verdict 和 dry-run 边界安全纳入同一个闭环。

核心变更：

- `scripts/validate-koharu-artifacts.py` 新增 `artifactIdentitySummary`，输出 source image、manifest、TextBoxes、BubbleMask、SegmentMask 的路径、存在性、size、SHA256，并透传 `generatedBy`、`generatedAt`、`contractExampleOnly`、schema、source image 和 coordinate space。
- GitHub Actions 注入 Koharu artifact archive 时只接受唯一一个同时包含四件套的目录，避免从多个目录各取一个 `rglob()[0]` 拼出错包；`ci-artifact-manifest.json` 透传 `koharuArtifactValidationIdentitySummary`，`ci-failure-summary.md` 打印 identity 摘要。
- `koharuArtifactConvergenceReport` 的 `WI-external-textbox-shadow-ocr-coverage` / `G-external-textbox-shadow-ocr-coverage` 在真实 artifact ready 后新增 contract dry-run 前置条件：`contractDryRunVerdict = activeArtifactsReadyForShadowOCR`、`dryRunOnly = true`、`activeExportAllowed = false`，再要求 `externalTextBoxShadowOCRReport.executed = true` 且 `candidateCount > 0`。

关键文件：

- `scripts/validate-koharu-artifacts.py`
- `.github/workflows/ci-results.yml`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AGENTS.md`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `md/koharu研究/artifact_contract/README.md`
- `md/koharu研究/v1.38-current-gap-to-koharu.md`
- `update_log.md`

验证结果：

- 本轮本地轻量验证见最终回复。

未跑本机 Xcode build / 模拟器漫画探针；按规则交给 GitHub Actions build 和手动 `ci-fast` / `full` 探针验证。

遗留事项：

- 该版本不提供真实 Koharu artifact，也不创建 active `test/koharu_artifacts/`；缺真实 artifact 时仍只输出 readiness blocked / identity empty-or-missing / orientation summary。
- 该版本不新增 OCR / LLM / PNG，不改变主 OCR、`finalTextUsedForTranslation`、翻译、覆盖图、`blockPassed`、active artifact 或 `configuration.currentBlockSource`。
- 未重新跑完整探针，不改变漫画质量指标，不追加 `metrics/version_history.csv`。

### v1.65：External TextBox Shadow OCR Coverage / Validator Orientation Summary
日期：2026-07-06

依据：v1.64 已能防止 external TextBox orientation partial / unsupported path 被 convergence 误判为闭环，但仍有两类证据缺口：一是 validator 只校验方向元数据是否合法，没有在 CI 结果包中汇总 TextBox 的竖排、旋转、line polygon 与 unsupported 风险；二是 artifact `readyForShadowOCR` 只证明四件套可解析，不证明 App 侧 external shadow OCR 已执行并产生 block-matched candidate。

核心变更：

- `scripts/validate-koharu-artifacts.py` 新增 `orientationMetadataSummary`，汇总 sourceDirection / orientation category / rotation plan / line polygon / vertical / right-angle rotation / arbitrary rotation / unsupported reason，缺 active artifact 时也稳定输出空摘要。
- `ci-artifact-manifest.json` 新增 `koharuArtifactValidationOrientationSummary`，`ci-failure-summary.md` 的 Koharu artifact gate 区块同步打印 validator orientation 摘要，方便 Agent C 在模拟器探针前核对外部 TextBox 方向风险。
- `koharuArtifactConvergenceReport` 新增 `WI-external-textbox-shadow-ocr-coverage` / `G-external-textbox-shadow-ocr-coverage`。真实 artifact ready 后，若 `externalTextBoxShadowOCRReport` 缺失、`executed=false` 或 `candidateCount=0`，ExternalArtifacts stage 会进入 `externalShadowOCRCoverageBlocked`，orientation gate 也不会被误判为 passed / closed。
- `1_ocr_probe_text.txt` 追加 `convergenceExternalShadowOCRCoverage` 和 `convergenceExternalTextBoxOrientation` 摘要。

关键文件：

- `scripts/validate-koharu-artifacts.py`
- `.github/workflows/ci-results.yml`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `AGENTS.md`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `md/koharu研究/artifact_contract/README.md`
- `update_log.md`

验证结果：

- 本轮本地轻量验证见最终回复。

未跑本机 Xcode build / 模拟器漫画探针；按规则交给 GitHub Actions build 和手动 `ci-fast` / `full` 探针验证。

遗留事项：

- 该版本不提供真实 Koharu artifact，也不创建 active `test/koharu_artifacts/`；缺真实 artifact 时仍只输出 readiness blocked / validator empty orientation summary。
- 该版本不新增 OCR / LLM / PNG，不改变主 OCR、`finalTextUsedForTranslation`、翻译、覆盖图、`blockPassed`、active artifact 或 `configuration.currentBlockSource`。
- 未重新跑完整探针，不改变漫画质量指标，不追加 `metrics/version_history.csv`。

### v1.64：External TextBox Orientation Partial / Unsupported Convergence Gate
日期：2026-07-06

依据：v1.63 已能在真实 artifact ready 后对竖排或接近 90/180/270 度的 external TextBox 执行有上限 rotation shadow OCR，并在候选 / block summary 写出 unsupported reason。但 `koharuArtifactConvergenceReport` 仍主要消费 `orientationShadowPathNotExecutedBlocks`，存在“orientation path 已部分执行但仍因 line polygon warp 或任意角度 deskew unsupported 而未闭环，却被 convergence 看成 closed/passed”的风险。

核心变更：

- `externalTextBoxShadowOCRReport` 新增 `orientationShadowPathPartialBlocks`、`orientationUnsupportedBlocks`、`orientationUnsupportedReasonBreakdown`，把“已执行 rotation OCR 但仍有 unsupported orientation feature”的块提升到 report 级摘要。
- `orientationReadinessVerdict = orientationShadowPathExecuted` 现在要求无 not-executed blocks 且无 unsupported blocks；部分执行会保持 `orientationShadowPathPartiallyExecuted`。
- `koharuArtifactConvergenceReport` 的 ExternalArtifacts stage、`WI-external-textbox-orientation-shadow-path` 和 `G-external-textbox-orientation-shadow-path` 改为同时消费 executed / partial / notExecuted / unsupported / unsupported reason breakdown，line polygon warp 与任意角度 deskew 会继续作为 convergence blockers 暴露。
- `1_ocr_probe_text.txt` 的 external TextBox shadow OCR 汇总追加 `orientationPartial`、`orientationUnsupported` 和 `orientationUnsupportedReasons`。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `AGENTS.md`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`

验证结果：

- `swiftc -parse $(rg --files AITRANS -g '*.swift')`
- `git diff --check`
- `ruby -e 'require "yaml"; YAML.load_file(".github/workflows/ci-results.yml"); puts "yaml ok"'`
- `python3 -m json.tool test/1.ground_truth.json`
- `python3 -m json.tool output/probe_report.json`
- `python3 -m json.tool output/clean_text_diagnostic.json`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/valid`
- `python3 scripts/validate-koharu-artifacts.py --root test/koharu_artifacts --allow-missing --print-required-files`
- `python3 scripts/validate-koharu-artifacts.py --root test/koharu_artifacts --allow-missing`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/coordinate_mismatch --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/invalid_bbox --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/missing_textboxes --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/schema_mismatch --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/path_escape --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/generated_by_forbidden --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/textbox_metadata_invalid --expect-fail`

未跑本机 Xcode build / 模拟器漫画探针；按规则交给 GitHub Actions build 和手动 `ci-fast` / `full` 探针验证。

遗留事项：

- 该版本不提供真实 Koharu artifact，也不创建 active `test/koharu_artifacts/`；缺真实 artifact 时仍只输出 readiness blocked 报告。
- 该版本仍不实现 line polygon crop / warp 或任意角度 deskew，只防止这类 unsupported orientation path 被 convergence 误判为已闭环。
- 该版本不改变主 OCR、`finalTextUsedForTranslation`、翻译、覆盖图、`blockPassed` 或 active artifact，不改变漫画质量指标，不追加 `metrics/version_history.csv`。

### v1.63：External TextBox Orientation Rotation Shadow OCR
日期：2026-07-06

依据：v1.62 已把 external TextBox 的 `sourceDirection`、`linePolygons` 和 `rotationDegrees` 纳入 orientation ledger，并阻止需要 orientation-aware path 但未执行的候选进入 would-promote 预览。`md/koharu研究/v1.38-current-gap-to-koharu.md` 要求从报告堆叠转向真实 TextBox / 竖排方向 shadow path。当前可安全复用的 OCR 能力是 crop 后 0/90/180/270 旋转，不具备任意角度 deskew 或 line polygon warp。

核心变更：

- `externalTextBoxShadowOCRReport` 在真实 `test/koharu_artifacts/` readiness 通过后，对竖排 TextBox 和接近 90/180/270 度的 rotation TextBox 执行有上限的 rotation shadow OCR；竖排使用 `ja-JP/ja/en-US/en` Vision language profile。
- 候选和逐块 summary 新增 `orientationAttemptedRotations`、`orientationSelectedRotation`、`orientationRecognitionLanguages`、`orientationUnsupportedReason`，让 JSON / TXT 能证明 orientation path 是否真的执行、选了哪个旋转、以及为何仍阻塞。
- `orientationReadinessVerdict` 区分 `orientationShadowPathExecuted`、`orientationShadowPathPartiallyExecuted`、`orientationShadowPathNeededNotExecuted`；line polygon warp 和任意角度 deskew 仍以 blocker 阻止 would-promote 预览。
- `1_ocr_probe_text.txt` 的 external TextBox shadow OCR 逐块摘要和报告汇总追加 rotation / language / unsupported 证据。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`

验证结果：

- `swiftc -parse $(rg --files AITRANS -g '*.swift')`
- `git diff --check`
- `ruby -e 'require "yaml"; YAML.load_file(".github/workflows/ci-results.yml"); puts "yaml ok"'`
- `python3 -m json.tool test/1.ground_truth.json`
- `python3 -m json.tool output/probe_report.json`
- `python3 -m json.tool output/clean_text_diagnostic.json`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/valid`
- `python3 scripts/validate-koharu-artifacts.py --root test/koharu_artifacts --allow-missing --print-required-files`
- `python3 scripts/validate-koharu-artifacts.py --root test/koharu_artifacts --allow-missing`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/coordinate_mismatch --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/invalid_bbox --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/missing_textboxes --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/schema_mismatch --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/path_escape --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/generated_by_forbidden --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/textbox_metadata_invalid --expect-fail`

未跑本机 Xcode build / 模拟器漫画探针；按规则交给 GitHub Actions build 和手动 `ci-fast` / `full` 探针验证。

遗留事项：

- 该版本不提供真实 Koharu artifact，也不创建 active `test/koharu_artifacts/`；缺真实 artifact 时仍只输出 readiness blocked 报告。
- 该版本只支持 90 度倍数 rotation shadow OCR，不实现任意角度 deskew 或 line polygon crop / warp。
- 该版本不改变主 OCR、`finalTextUsedForTranslation`、翻译、覆盖图、`blockPassed` 或 active artifact，不改变漫画质量指标，不追加 `metrics/version_history.csv`。

### v1.62：External TextBox Orientation Shadow Ledger
日期：2026-07-06

依据：v1.61 已把 external TextBox 可选 `sourceDirection`、`rotationDegrees` / `rotationDeg`、`linePolygons` 纳入 validator 和 Swift readiness，但 ready 后的 `externalTextBoxShadowOCRReport` 仍只透传少量 metadata，未把“竖排 / line polygon / rotation 需要 orientation-aware shadow path，而当前未执行”作为可审计 gate。`md/koharu研究/v1.38-current-gap-to-koharu.md` 明确 line polygon 和竖排方向主路径是 AITRANS 距 Koharu 的关键差距。

核心变更：

- `MangaOverlayExternalTextBoxShadowOCRCandidate`、`BlockSummary` 和 `Report` 新增 external TextBox orientation ledger：规范化 `sourceDirection`、orientation 分类、line polygon 数量、rotation blocks、vertical blocks、orientation shadow path needed / executed / not executed blocks 和 report verdict。
- `makeExternalTextBoxShadowOCRReport` 在选择 external TextBox 后记录方向元数据；当 TextBox 声明 vertical / linePolygons / non-zero rotation 时，写入 `orientationShadowPathNeededNotExecuted` blocker，阻止其进入 `wouldPromoteByExistingGateReportOnly`。
- `koharuArtifactConvergenceReport` 新增 `WI-external-textbox-orientation-shadow-path` 和 `G-external-textbox-orientation-shadow-path`，把缺失 orientation-aware shadow OCR 路径暴露到 convergence work item / gate。
- `1_ocr_probe_text.txt` external shadow OCR 明细和汇总追加 sourceDirection、orientation、linePolygons、rotation、orientation shadow needed / executed / verdict。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`

验证结果：

- `swiftc -parse $(rg --files AITRANS -g '*.swift')`
- `git diff --check`
- `ruby -e 'require "yaml"; YAML.load_file(".github/workflows/ci-results.yml"); puts "yaml ok"'`
- `python3 -m json.tool test/1.ground_truth.json`
- `python3 -m json.tool output/probe_report.json`
- `python3 -m json.tool output/clean_text_diagnostic.json`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/valid`
- `python3 scripts/validate-koharu-artifacts.py --root test/koharu_artifacts --allow-missing --print-required-files`
- `python3 scripts/validate-koharu-artifacts.py --root test/koharu_artifacts --allow-missing`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/coordinate_mismatch --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/invalid_bbox --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/missing_textboxes --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/schema_mismatch --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/path_escape --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/generated_by_forbidden --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/textbox_metadata_invalid --expect-fail`

未跑本机 Xcode build / 模拟器漫画探针；按规则交给 GitHub Actions build 和手动 `ci-fast` / `full` 探针验证。

遗留事项：

- 该版本不执行 rotation / deskew / line polygon crop OCR，只记录 orientation shadow path 缺口并阻止 report-only promote 预览误判。
- 该版本不提供真实 Koharu artifact，也不创建 active `test/koharu_artifacts/`。
- 该版本不改变漫画质量指标，不追加 `metrics/version_history.csv`。

### v1.61：Koharu TextBox Direction Metadata Gate
日期：2026-07-06

依据：`md/koharu研究/v1.38-current-gap-to-koharu.md` 明确 AITRANS 距 Koharu 的关键差距包括真实 TextBoxes、line polygon 和竖排方向主路径。v1.60 已拦住伪造来源，但 TextBox 可选 `sourceDirection`、`rotationDegrees` / `rotationDeg`、`linePolygons` 仍主要是透传或浅校验，真实四件套即使带坏方向元数据也可能进入 App readiness。

核心变更：

- `scripts/validate-koharu-artifacts.py` 新增 TextBox 可选方向元数据校验：`sourceDirection` 必须落在 horizontal / vertical / vertical-rl / vertical-lr / unknown 等枚举内，`rotationDegrees` / `rotationDeg` 必须是有限数值且在 `[-360, 360]`，`linePolygons` 必须是非空 polygon 数组且点位在 `test/1.png` 原图范围内。
- Swift `externalArtifactReadinessReport` 使用同类校验，把 TextBox metadata 错误并入 coordinate validation，阻止离线 validator 和 App readiness 口径分叉。
- 新增 invalid fixture `md/koharu研究/artifact_contract/examples/invalid/textbox_metadata_invalid/`，并加入 CI extended validator matrix。
- artifact contract README、README、flow 和 test 文档同步说明：方向/旋转/line polygon 仍是可选字段，但提供时必须有效，供后续竖排 / line polygon shadow path 使用。

关键文件：

- `scripts/validate-koharu-artifacts.py`
- `AITRANS/Services/TranslationSessionStore.swift`
- `.github/workflows/ci-results.yml`
- `md/koharu研究/artifact_contract/examples/invalid/textbox_metadata_invalid/`
- `md/koharu研究/artifact_contract/README.md`
- `README.md`
- `md/flow/flow.md`
- `md/test/test.md`
- `update_log.md`

验证结果：

- `ruby -e 'require "yaml"; YAML.load_file(".github/workflows/ci-results.yml"); puts "yaml ok"'`
- `git diff --check`
- `swiftc -parse $(rg --files AITRANS -g '*.swift')`
- `python3 -m py_compile scripts/validate-koharu-artifacts.py`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/valid`
- `python3 scripts/validate-koharu-artifacts.py --root test/koharu_artifacts --allow-missing --print-required-files`
- `python3 scripts/validate-koharu-artifacts.py --root test/koharu_artifacts --allow-missing`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/coordinate_mismatch --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/invalid_bbox --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/missing_textboxes --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/schema_mismatch --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/path_escape --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/generated_by_forbidden --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/textbox_metadata_invalid --expect-fail`

未跑本机 Xcode build / 模拟器漫画探针；按规则交给 GitHub Actions build 和手动 `ci-fast` / `full` 探针验证。

遗留事项：

- 该版本不提供真实 Koharu artifact，也不创建 active `test/koharu_artifacts/`；只加强真实四件套方向元数据准入。
- 该版本不执行 rotation / deskew / line polygon crop OCR；下一步可在 `externalTextBoxShadowOCRReport` 中做 report-only vertical / line polygon shadow path。
- 该版本不改变漫画质量指标，不追加 `metrics/version_history.csv`。

### CI 维护：Build IPA archive artifact handoff
日期：2026-07-06

依据：`AITRANS - Build IPA` workflow 在 `Build using xcodebuild` job 已成功归档并上传 xcarchive，但 `Fakesign and package IPA` job 固定下载 `archive.xcarchive.tar.zip`，当 `IPA_PASSWORD` 为空或 secret 不可用导致上游实际上传 `archive.xcarchive.tar` 时，下游会报 `Artifact not found for name: archive.xcarchive.tar.zip`。

核心变更：

- `.github/workflows/build.yml` 将上游实际生成的 xcarchive artifact 文件名写入 step output，并作为 build job output 传给 package job。
- `Download xcarchive` 不再固定下载 `.zip`，而是使用 `needs.build.outputs.archive_artifact`。
- `Extract xcarchive` 同时支持 `.tar.zip` 和 `.tar`，保持有密码和无密码两种打包路径。

关键文件：

- `.github/workflows/build.yml`
- `update_log.md`

验证结果：

- `ruby -e 'require "yaml"; YAML.load_file(".github/workflows/build.yml"); puts "yaml ok"'`
- `git diff --check`

未跑本机 Xcode build / 模拟器漫画探针；该维护只修 GitHub Actions 打包 artifact 交接，按规则交给云端 workflow 验证。

遗留事项：

- 该维护项不改变未加密 `AITRANS CI Results` 验收口径，不改变漫画探针质量，不追加 `metrics/version_history.csv`。

### v1.60：Koharu Artifact GeneratedBy Source Policy Gate
日期：2026-07-06

依据：`md/koharu研究/v1.38-current-gap-to-koharu.md` 明确 P0 是真实 Koharu artifact 输入。v1.59 已强化注入后 App 侧消费证明，但 active package 仍需要防止“格式正确、来源却是 manual / fixture / Vision OCR / proxy / ground truth”的四件套通过到 shadow OCR。

核心变更：

- `scripts/validate-koharu-artifacts.py` 新增 active manifest `generatedBy` source policy：`contractExampleOnly=false` 时必须声明真实 detector / segmenter 来源；缺失返回 `generatedByMissing`，命中 `manual`、`fixture`、`Vision OCR`、`pre-crop`、`line plan`、`BubbleMask proxy`、`SegmentMask proxy`、`ground truth`、`handwritten` 等禁用来源词返回 `forbiddenGeneratedBy`。
- Swift `externalArtifactReadinessReport` 使用同一 source policy，把 `generatedByMissing` / `forbiddenGeneratedBy` 阻塞在 `readyForShadowOCR` 之前，并给出 `stopUntilRealDetectorSourceDeclared`。
- 新增 invalid fixture `md/koharu研究/artifact_contract/examples/invalid/generated_by_forbidden/`，并加入 CI extended validator matrix。
- `README.md`、`md/flow/flow.md`、`md/test/test.md` 和 artifact contract README 同步说明：Agent C 验收真实四件套时必须核对 `generatedBy` 不是禁用来源。

关键文件：

- `scripts/validate-koharu-artifacts.py`
- `AITRANS/Services/TranslationSessionStore.swift`
- `.github/workflows/ci-results.yml`
- `md/koharu研究/artifact_contract/examples/invalid/generated_by_forbidden/`
- `README.md`
- `md/flow/flow.md`
- `md/test/test.md`
- `md/koharu研究/artifact_contract/README.md`
- `update_log.md`

验证结果：

- `ruby -e 'require "yaml"; YAML.load_file(".github/workflows/ci-results.yml"); puts "yaml ok"'`
- `git diff --check`
- `swiftc -parse $(rg --files AITRANS -g '*.swift')`
- `python3 -m json.tool test/1.ground_truth.json`
- `python3 -m json.tool output/probe_report.json`
- `python3 -m json.tool output/clean_text_diagnostic.json`
- `python3 -m py_compile scripts/validate-koharu-artifacts.py`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/valid`
- `python3 scripts/validate-koharu-artifacts.py --root test/koharu_artifacts --allow-missing --print-required-files`
- `python3 scripts/validate-koharu-artifacts.py --root test/koharu_artifacts --allow-missing`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/coordinate_mismatch --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/invalid_bbox --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/missing_textboxes --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/schema_mismatch --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/path_escape --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/generated_by_forbidden --expect-fail`

未跑本机 Xcode build / 模拟器漫画探针；按规则交给 GitHub Actions build 和手动 `ci-fast` / `full` 探针验证。

遗留事项：

- 该版本不提供真实 Koharu artifact，也不创建 active `test/koharu_artifacts/`；只加强真实四件套来源准入。
- 该版本不改变漫画质量指标，不追加 `metrics/version_history.csv`。

### CI 维护：push 快验范围检测与 validator 精简
日期：2026-07-06

依据：人工要求精简当前测试，让云端 CI 加速，避免每次非 App 构建相关调整都跑完整 Xcode build 或完整 artifact invalid fixture 矩阵。

核心变更：

- `AITRANS CI Results` 新增变更范围检测：非 App 构建相关 push 可跳过 Xcode build，结果包保留 `xcodebuild.log` skip 说明，并在 manifest 写入 `xcodeBuildRequired`、`xcodeBuildSkippedReason`、`changedFilesPath`。
- Swift、Xcode 工程、`build-apple/`、资源、`test/` 素材、手动 `ci-fast/full` 或 Koharu artifact 注入仍强制 Xcode build。
- Xcode build 步骤增加 20 分钟上限，启用 `COMPILER_INDEX_STORE_ENABLE=NO` 并使用 quiet build log，减少默认云端耗时和日志体积。
- Koharu artifact validator 完整 invalid fixture 矩阵只在 validator、artifact contract 或 workflow 相关文件变化时运行；普通 push 只跑 valid example、active allow-missing 和 required-files 核心校验。
- `AGENTS.md`、`README.md`、`md/flow/flow.md`、`md/flow/flowchart.md`、`md/test/test.md` 同步新 CI 口径；非 App 构建相关 build-skip 不能当作 Swift/Xcode 编译证据。

关键文件：

- `.github/workflows/ci-results.yml`
- `AGENTS.md`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`

验证结果：

- `ruby -e 'require "yaml"; YAML.load_file(".github/workflows/ci-results.yml"); puts "yaml ok"'`
- `git diff --check`
- `python3 -m json.tool test/1.ground_truth.json`
- `python3 -m json.tool output/probe_report.json`
- `python3 -m json.tool output/clean_text_diagnostic.json`
- `python3 -m py_compile scripts/validate-koharu-artifacts.py`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/valid`
- `python3 scripts/validate-koharu-artifacts.py --root test/koharu_artifacts --allow-missing --print-required-files`
- `python3 scripts/validate-koharu-artifacts.py --root test/koharu_artifacts --allow-missing`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/coordinate_mismatch --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/invalid_bbox --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/missing_textboxes --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/schema_mismatch --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/path_escape --expect-fail`

遗留事项：

- 该维护项不改变漫画探针质量，不追加 `metrics/version_history.csv`。
- Swift / Xcode 代码改动仍需要云端 Xcode build；手动探针仍需 `workflow_dispatch` 选择 `ci-fast` 或 `full`。

### v1.59：Injected Koharu Artifact App-Readiness Smoke
日期：2026-07-06

依据：`md/koharu研究/v1.38-current-gap-to-koharu.md` 把 P0 定为真实 Koharu artifact 输入。此前 workflow 已能下载、校验、解压并 validator 检查四件套，但手动探针的 smoke 仍可能只证明 CI 注入步骤成功，未强制证明 App 内 `externalArtifactReadinessReport` 和 external TextBox shadow OCR 真消费到了 active artifact。

核心变更：

- 手动 `workflow_dispatch` 注入 Koharu artifact 且运行 `ci-fast/full` 时，`manga-probe.log` 的 post-export smoke 会读取 `output/probe_report.json`，强制核对 App 侧 `externalArtifactReadinessReport.readinessVerdict = readyForShadowOCR`、`activeArtifactsDirectory = true`、`contractExampleOnly = false`、`externalTextBoxesShadowOCRAllowed = true`，以及 manifest / TextBoxes / BubbleMask / SegmentMask 全部 found。
- 同一 smoke 会核对 `externalTextBoxShadowOCRReport.executed = true` 且 `candidateCount > 0`，避免只验证静态四件套存在却没有进入 shadow OCR。
- 同一 smoke 会核对 `koharuNativeArtifactContractDryRunReport.contractDryRunVerdict = activeArtifactsReadyForShadowOCR`，并确认 `dryRunOnly = true`、`activeExportAllowed = false`，保持 active artifact 写入边界。
- TXT smoke 新增注入路径 needle：`externalArtifacts: readiness=readyForShadowOCR`、`shadowOCRAllowed=true`、`nativeArtifactContractDryRunReport`、`nativeArtifactContractDryRunPreview`。
- `README.md`、`md/flow/flow.md`、`md/test/test.md` 同步说明：Agent C 不能只看 Release 下载、SHA、解压或 validator 日志，必须看 App 侧探针报告。

关键文件：

- `.github/workflows/ci-results.yml`
- `README.md`
- `md/flow/flow.md`
- `md/test/test.md`
- `update_log.md`

验证结果：

- `ruby -e 'require "yaml"; YAML.load_file(".github/workflows/ci-results.yml"); puts "yaml ok"'`
- `git diff --check`
- `swiftc -parse $(rg --files AITRANS -g '*.swift')`
- `python3 -m json.tool test/1.ground_truth.json`
- `python3 -m json.tool output/probe_report.json`
- `python3 -m json.tool output/clean_text_diagnostic.json`
- `python3 -m py_compile scripts/validate-koharu-artifacts.py`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/valid`
- `python3 scripts/validate-koharu-artifacts.py --root test/koharu_artifacts --allow-missing --print-required-files`
- `python3 scripts/validate-koharu-artifacts.py --root test/koharu_artifacts --allow-missing`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/coordinate_mismatch --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/invalid_bbox --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/missing_textboxes --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/schema_mismatch --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/path_escape --expect-fail`

未跑本机 Xcode build / 模拟器漫画探针；按规则交给 GitHub Actions build 和手动 `ci-fast` / `full` 探针验证。

遗留事项：

- 该版本不提供真实 Koharu artifact，也不创建 active `test/koharu_artifacts/`；只强化注入后云端验收证据。
- 该版本不改变漫画质量指标，不追加 `metrics/version_history.csv`。

### v1.58：TextBox Segment Linkage Reaches Convergence
日期：2026-07-06

依据：v1.57 已把 TextBox -> SegmentMask linkage 传播到 bundle-lite 和 promotion gate，但最终 `koharuArtifactConvergenceReport` 仍需要显式消费这些 work item / gate，避免 bundle / promotion 层已经阻塞弱 linkage、收敛层却只按旧 artifact stage 给出下一步。

核心变更：

- `koharuArtifactConvergenceReport` 新增 bundle / promotion linkage review 聚合，把 v1.57 的 review / blocked blocks 继续传播到 convergence stage、block path、work item closure ledger 和 gate ledger。
- TextBoxes / SegmentMask convergence stage 会在 weak、fallback、rejected 或 wrong-bubble linkage 存在时输出 linkage-blocked status、affected blocks、decision signals 和 blocked work items。
- 逐块 artifact path 会把 `primaryStructuralBottleneck` 收束到 `textBoxSegmentMaskLinkage`，并优先给出 `auditTextBoxSegmentLinkageBeforeBundleReadiness` 或 `auditTextBoxSegmentLinkageBeforePromotion`。
- 新增 convergence work items / gates：`WI-koharu-native-artifact-bundle-lite-textbox-segment-linkage`、`WI-koharu-native-promotion-gate-lite-textbox-segment-linkage`、`G-koharu-convergence-bundle-lite-textbox-segment-linkage`、`G-koharu-convergence-promotion-lite-textbox-segment-linkage`。
- `1_ocr_probe_text.txt` 新增 `convergenceBundleTextBoxSegmentLinkage` 和 `convergencePromotionTextBoxSegmentLinkage` 摘要，云端 `ci-fast` smoke 会检查 JSON 字段和 TXT needle。
- 本轮仍是 report-only：不新增 OCR / LLM / PNG，不创建或修改 active `test/koharu_artifacts/`，不改变主 OCR、翻译输入、覆盖图、renderer、`safeLayoutRect`、`glyphMaskFillRects`、`blockPassed`、失败分类、`textRegionCropReport.adoptedCount` 或 `configuration.currentBlockSource`。

关键文件：

- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `.github/workflows/ci-results.yml`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`

验证结果：

- `swiftc -parse $(rg --files AITRANS -g '*.swift')`
- `ruby -e 'require "yaml"; YAML.load_file(".github/workflows/ci-results.yml"); puts "yaml ok"'`
- `git diff --check`
- `python3 -m json.tool test/1.ground_truth.json`
- `python3 -m json.tool output/probe_report.json`
- `python3 -m json.tool output/clean_text_diagnostic.json`
- `python3 -m py_compile scripts/validate-koharu-artifacts.py`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/valid`
- `python3 scripts/validate-koharu-artifacts.py --root test/koharu_artifacts --allow-missing --print-required-files`
- `python3 scripts/validate-koharu-artifacts.py --root test/koharu_artifacts --allow-missing`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/coordinate_mismatch --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/invalid_bbox --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/missing_textboxes --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/schema_mismatch --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/path_escape --expect-fail`

未跑本机 Xcode build / 模拟器漫画探针；按规则交给 GitHub Actions build 和手动 `ci-fast` / `full` 探针验证。

遗留事项：

- 该版本不改变漫画质量指标，不追加 `metrics/version_history.csv`。
- 真正的 Koharu 能力仍依赖真实 TextBoxes / BubbleMask / SegmentMask 四件套或模型级 detector 输出；native-lite linkage 只作为 report-only gate。

### v1.57：TextBox Segment Linkage Propagates to Bundle / Promotion
日期：2026-07-06

依据：v1.56 已在 SegmentMask refinement-lite 中记录 selected TextBox -> SegmentMask linkage，但 v1.45 bundle-lite 和 v1.46 promotion gate 仍主要看组件可用性，缺少把 rejected / fallback / wrong-bubble TextBox linkage 继续向 bundle readiness 和 promotion eligibility 传播的阻塞口径。

核心变更：

- `MangaKoharuNativeArtifactBundleLiteBlockLedger` 新增 `selectedTextBoxSegmentLinkVerdict`、`textBoxSegmentLinkageStatus`、`textBoxSegmentLinkageRisk`；报告新增 `textBoxSegmentLinkBreakdown` 和 `textBoxSegmentLinkageReviewBlocks`。
- `koharuNativeArtifactBundleLiteReport` 新增 `TextBoxSegmentMaskLinkage` consistency edge；fallback、weak、rejected 或 wrong-bubble linkage 会把 `primaryBlockingArtifact` 指向 `TextBoxes`，并把 `nextAction` 收束到 `auditTextBoxSegmentLinkageBeforeBundleReadiness`。
- `MangaKoharuNativePromotionBlockLedger` 新增 `textBoxSegmentLinkVerdict` 和 `textBoxSegmentLinkagePromotionStatus`；报告新增 `textBoxSegmentLinkBreakdown` 和 `textBoxSegmentLinkageBlockedBlocks`。
- `koharuNativePromotionGateLiteReport` 会把弱 linkage 写入 TextBoxes / SegmentMask promotion status、`mustNotPromoteReasons`、probe bottleneck 和 `auditTextBoxSegmentLinkageBeforePromotion`，防止 SegmentMask proxy 因局部可用而被误判可晋级。
- 新增 linkage work items / gates：`WI-koharu-native-artifact-bundle-lite-textbox-segment-linkage`、`G-native-artifact-bundle-lite-textbox-segment-linkage`、`WI-koharu-native-promotion-gate-lite-textbox-segment-linkage`、`G-native-promotion-gate-lite-textbox-segment-linkage`。
- `1_ocr_probe_text.txt` 新增 bundle / promotion 的 `textBoxSegmentLink=` 逐块摘要，以及报告级 `nativeArtifactBundleLiteTextBoxSegmentLink`、`nativePromotionTextBoxSegmentLink` 汇总。
- 本轮仍是 report-only：不新增 OCR / LLM / PNG，不创建或修改 active `test/koharu_artifacts/`，不改变主 OCR、翻译输入、覆盖图、renderer、`safeLayoutRect`、`glyphMaskFillRects`、`blockPassed`、失败分类、`textRegionCropReport.adoptedCount` 或 `configuration.currentBlockSource`。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`

验证结果：

- `swiftc -parse $(rg --files AITRANS -g '*.swift')`
- `ruby -e 'require "yaml"; YAML.load_file(".github/workflows/ci-results.yml"); puts "yaml ok"'`
- `git diff --check`
- `python3 -m json.tool test/1.ground_truth.json`
- `python3 -m json.tool output/probe_report.json`
- `python3 -m json.tool output/clean_text_diagnostic.json`
- `python3 -m py_compile scripts/validate-koharu-artifacts.py`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/valid`
- `python3 scripts/validate-koharu-artifacts.py --root test/koharu_artifacts --allow-missing --print-required-files`
- `python3 scripts/validate-koharu-artifacts.py --root test/koharu_artifacts --allow-missing`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/coordinate_mismatch --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/invalid_bbox --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/missing_textboxes --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/schema_mismatch --expect-fail`
- `python3 scripts/validate-koharu-artifacts.py --root md/koharu研究/artifact_contract/examples/invalid/path_escape --expect-fail`

遗留事项：

- 未跑本机 Xcode build / 模拟器漫画探针；按规则交给 GitHub Actions build 和手动 `ci-fast` / `full` 探针验证。
- 该版本不改变漫画质量指标，不追加 `metrics/version_history.csv`。

### v1.56：TextBox -> SegmentMask Linkage Gate
日期：2026-07-06

依据：`md/koharu研究/v1.38-current-gap-to-koharu.md` 的 TextBoxes / SegmentMask 差距：Koharu 是 TextBoxes 先产出，再约束 SegmentMask；AITRANS 已有 detector-lite 和 SegmentMask refinement-lite，但两者之间缺少可审计 linkage，容易出现 SegmentMask 看似可用、实际来自弱 TextBox / rejected TextBox / fallback bbox 的假闭环。

核心变更：

- `MangaKoharuNativeTextBoxDetectorLiteCandidate` 新增 `relatedBlockRelations[]`，记录 candidate 与 block 的 overlap、center containment、same-bubble 和 relation reason。
- `MangaKoharuNativeTextBoxDetectorLiteBlockLedger` 新增 best candidate relation 字段：coverage ratio、center-contained、same-bubble、candidate verdict 和 shadow OCR eligibility。
- `koharuNativeTextBoxDetectorLiteReport` 新增 `blockRelationBreakdown`。
- `MangaKoharuNativeSegmentMaskRefinementLiteCandidateLedger` 新增来源 TextBox linkage 字段：source TextBox verdict、shadow eligibility、block overlap、same-bubble、accepted-for-SegmentMask 和 link verdict。
- `MangaKoharuNativeSegmentMaskRefinementLiteBlockLedger` 新增 selected source TextBox candidate ID / link verdict。
- `koharuNativeSegmentMaskRefinementLiteReport` 新增 `textBoxSegmentLinkBreakdown`、`segmentFromAcceptedTextBoxCount`、`segmentFromRejectedTextBoxCount`、`segmentFromFallbackBBoxCount`。
- 新增 gates：`G-native-segmentmask-refinement-lite-textbox-linkage-audited` 和 `G-native-segmentmask-refinement-lite-no-rejected-textbox-silent-selection`。
- `1_ocr_probe_text.txt` 的 TextBox / SegmentMask native-lite summary 输出 candidate relation、selected link verdict、accepted/rejected/fallback 计数。
- 本轮不新增 OCR / LLM / PNG，不创建或修改 active `test/koharu_artifacts/`，不替换主 OCR、翻译输入、覆盖图、`safeLayoutRect`、`glyphMaskFillRects`、renderer、`blockPassed`、失败分类、`textRegionCropReport.adoptedCount` 或 `configuration.currentBlockSource`。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`

验证结果：

- `swiftc -parse $(rg --files AITRANS -g '*.swift')`

遗留事项：

- Linkage gate 仍只审计 native-lite proxy TextBoxes；真实能力需要 active Koharu TextBoxes / SegmentMask 四件套或模型级 detector 输出。
- 后续可把该 linkage 接入 `koharuNativeArtifactBundleLiteReport` / promotion gate 的 consistency edges，使 rejected / fallback TextBox 约束直接影响 artifact readiness。

### v1.55：BubbleMask Sibling Sprite Collision Preview
日期：2026-07-06

依据：`md/koharu研究/v1.38-current-gap-to-koharu.md` 的 P5 渲染方向和 Koharu renderer 的 same-bubble sprite collision 思路：v1.54 已检查单块 sprite bounds 是否落在 block-scoped safe rect 内，本轮继续 report-only 检查同一个 instance-lite bubble 下多个 rendered sprite bounds 是否互相重叠。

核心变更：

- `MangaKoharuNativeBubbleMaskInstanceLiteBlockLedger` 新增 `sameInstanceRenderSpriteOverlapCount` 和 `spriteSiblingCollisionPolicy`。
- `MangaKoharuNativeBubbleMaskInstanceLiteSiblingLedger` 新增 `renderSpriteOverlapCount` 和 `sameBubbleSpriteCollisionPolicy`。
- `koharuNativeBubbleMaskInstanceLiteReport` 新增 `spriteSiblingCollisionBreakdown`。
- `makeKoharuNativeBubbleMaskInstanceLiteReport` 现在对 same-instance sibling blocks 的 `renderNonTransparentBounds` 做 bounded overlap 计数，并输出 `sameInstanceSpritesSeparated`、`sameInstanceSpriteOverlapManualReview`、`missingRenderSpriteBounds` 或 `singleBlockOrNoInstance`。
- 新增 gate `G-native-bubblemask-instance-lite-sibling-sprite-collision`，只证明同 instance sprite collision 已进入账本，不写回 renderer。
- `1_ocr_probe_text.txt` 的 block / sibling / summary 行输出 sibling sprite overlap 和 collision policy。
- CI 维护：Koharu artifact archive 注入前会清空 `test/koharu_artifacts/`，避免残留 active 文件影响四件套 validator；测试文档同步 schema/path invalid fixtures 和 skip/探针结果包口径。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `.github/workflows/ci-results.yml`
- `README.md`
- `AGENTS.md`
- `md/test/test.md`
- `update_log.md`

验证结果：

- `swiftc -parse $(rg --files AITRANS -g '*.swift')`

遗留事项：

- 这仍是 bounds-level sibling collision preview，不是 Koharu renderer 的逐像素 alpha mask collision；真实能力需要 active BubbleMask 或 renderer-side sprite alpha gate。
- Rawls 子 agent 建议的 TextBox -> SegmentMask linkage gate 是下一轮高收益候选；本轮先收窄在 P5 sibling sprite collision，避免一次改动跨太多报告结构。

### v1.54：BubbleMask Block-Scoped Sprite Containment Preview
日期：2026-07-06

依据：`md/koharu研究/v1.38-current-gap-to-koharu.md` 的 P5 渲染方向和 Koharu renderer 的 mask collision 思路：先 report-only 检查 rendered sprite 非透明 bounds 是否落在所属 block 的 scoped safe rect 内，再考虑未来是否接入真实 renderer gate。

核心变更：

- `MangaKoharuNativeBubbleMaskInstanceLiteBlockLedger` 新增 `spriteBlockScopedSafeRectContainmentRatio`、`spriteContainedByBlockScopedSafeRect`、`spriteContainmentPolicy`。
- `koharuNativeBubbleMaskInstanceLiteReport` 新增 `spriteBlockScopedContainmentBreakdown`，保留旧 `spriteContainmentBreakdown` 的 instance-lite mask coverage 语义。
- v1.43 block ledger 现在用现有 `renderNonTransparentBounds` 和 `instanceLiteBlockScopedSafeRect` 计算 report-only containment ratio；`>= 0.995` 视为 `spriteWithinBlockScopedSafeRect`，缺 bounds / 缺 scoped safe rect 时明确记录 missing 状态。
- `1_ocr_probe_text.txt` 的 `nativeBubbleMaskInstanceLiteBlockLedger` 行输出 `spriteScopedContainmentRatio`、`spriteContainedByScopedSafeRect`、`spriteContainmentPolicy`；summary 输出 `nativeBubbleMaskInstanceLiteBlockScopedSpriteContainment`。
- 本轮不新增 OCR / LLM / PNG，不创建或修改 active `test/koharu_artifacts/`，不重新渲染，不写回主 OCR、翻译输入、覆盖图、`safeLayoutRect`、DistanceField 报告、renderer、`blockPassed`、失败分类、`textRegionCropReport.adoptedCount` 或 `configuration.currentBlockSource`。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`

验证结果：

- `swiftc -parse $(rg --files AITRANS -g '*.swift')`

遗留事项：

- 这仍是 bounds-level preview，不是 Koharu 逐像素 alpha mask collision；真实能力需要 active BubbleMask 或 renderer-side sprite alpha gate。
- 当前本地 `output/` 不含 v1.43+ 新字段；真实 JSON / TXT 结果以后续手动 GitHub Actions `ci-fast/full` 结果包为准。

### v1.53：BubbleMask Instance-Lite Sibling Safe Rect Policy
日期：2026-07-06

依据：`md/koharu研究/v1.38-current-gap-to-koharu.md` 的 P3 方向，以及 Koharu renderer 行为：同一个 bubble ID 下多个 text block 不应全部扩展到同一个最大 safe rect，否则会制造 sibling layout collision。

核心变更：

- `MangaKoharuNativeBubbleMaskInstanceLiteBlockLedger` 新增 `instanceLiteBlockScopedSafeRect` 和 `instanceLiteSafeRectPolicy`。
- `MangaKoharuNativeBubbleMaskInstanceLiteSiblingLedger` 新增 `blockScopedSafeRectOverlapCount` 和 `sameBubbleSafeRectPolicy`。
- `koharuNativeBubbleMaskInstanceLiteReport` 新增 `safeRectPolicyBreakdown`。
- 单 block instance 继续使用 v1.51 的 mask-derived instance safe rect；同 instance 多 block 时，report-only `instanceLiteBlockScopedSafeRect` 使用 block seed rect，避免把同一个最大 safe rect 复制给 siblings。
- `distanceFieldSafeRectFromInstanceLite` 在同 instance 多 block 场景写入 block-scoped rect，并把 `distanceFieldSafeRectSource` 标为 `nativeBubbleMaskInstanceLiteBlockScopedSeedRect`。
- 新增 gate `G-native-bubblemask-instance-lite-sibling-safe-rect-policy`，只证明 policy report-only，不写回主流程。
- `1_ocr_probe_text.txt` 的 block / sibling / summary 行新增 safe rect policy 和 block-scoped overlap 输出。
- 本轮不新增 OCR / LLM / PNG，不创建或修改 active `test/koharu_artifacts/`，不写回主 OCR、翻译输入、覆盖图、`safeLayoutRect`、DistanceField 报告、renderer、`blockPassed`、失败分类或 `configuration.currentBlockSource`。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`

验证结果：

- `swiftc -parse $(rg --files AITRANS -g '*.swift')`

遗留事项：

- 仍是 native-lite report-only 近似；真实 Koharu BubbleMask 仍需要 active artifact 或更强 detector 输出。
- 当前本地 `output/` 不含 v1.43+ 新字段；真实 JSON / TXT 结果以后续手动 GitHub Actions `ci-fast/full` 结果包为准。

### v1.52：SegmentMask Refinement-Lite Containment Ratio Gate
日期：2026-07-06

依据：`md/koharu研究/v1.38-current-gap-to-koharu.md` 的 P3 / SegmentMask 差距，以及子 agent 对 v1.44 的只读复核：已有 TextBox-constrained glyph mask，但 `maskContainedByTextBox` / `maskContainedByBubble` 只是弱布尔，不能表达 Koharu-like mask containment 证据。

核心变更：

- `MangaKoharuNativeSegmentMaskRefinementLiteCandidateLedger` / `BlockLedger` 新增 `maskContainedByTextBoxRatio`、`maskContainedByBubbleRatio`、`maskMajorityInstanceLiteID`、`maskMajorityBubbleID`、`maskMajorityCoverage`、`maskMajorityAgreement`。
- `koharuNativeSegmentMaskRefinementLiteReport` 新增 `maskMajorityAgreementBreakdown`。
- v1.44 正常候选在 `maskBBox` 生成后用 `rectContainmentRatio` 计算 TextBox / Bubble containment ratio；block ledger 的 `maskContainedByTextBox` / `maskContainedByBubble` 改为 ratio 阈值判定，而不是只看是否缺 constraint。
- majority agreement 使用 v1.43 instance-lite ledger / instance bbox / bubble ID 做 report-only 一致性判断；不重算真实 SegmentMask 像素多数票，不把它冒充真实 Koharu SegmentMask。
- `1_ocr_probe_text.txt` summary 追加 `nativeSegmentMaskRefinementLiteMajorityAgreement`，candidate / block ledger 行输出 containment ratio 与 majority agreement。
- 本轮仍不新增 OCR / LLM / PNG，不创建或修改 active `test/koharu_artifacts/`，不写回主 OCR、翻译输入、覆盖图、`safeLayoutRect`、`glyphMaskFillRects`、背景填充、renderer、`blockPassed`、失败分类、`textRegionCropReport.adoptedCount` 或 `configuration.currentBlockSource`。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`

验证结果：

- `swiftc -parse $(rg --files AITRANS -g '*.swift')`

遗留事项：

- v1.52 仍是 native-lite report-only 近似；真实 SegmentMask 还需要 active artifact 或 detector 输出。
- 当前本地 `output/` 不含 v1.44+ 新字段；真实 TXT / JSON 输出以后续手动 GitHub Actions `ci-fast/full` 结果包为准。

### v1.51：BubbleMask Instance-Lite 像素派生 Safe Rect
日期：2026-07-06

依据：`md/koharu研究/v1.38-current-gap-to-koharu.md` 的 P3 方向，继续把 BubbleMask instance-lite 从 bbox 代理推向像素 ID mask / safe area 证据；本轮仍不接 active Koharu artifact、不新增 OCR / LLM / PNG、不替换主 OCR / 翻译 / 覆盖 / 通过判定。

核心变更：

- `koharuNativeBubbleMaskInstanceLiteReport` 的 `instanceLiteSafeRect` / `distanceFieldSafeRectFromInstanceLite` 不再由 instance bbox 简单内缩生成，改为从对应 instance 的源图像像素 offset 派生。
- 新增轻量 mask-derived safe rect 逻辑：先按 row / column run 估计到 mask 边界的内侧距离并做 erosion；若实例太薄无法形成 eroded core，则回退到高覆盖 row / column projection core。
- same-bubble sibling overlap 和逐块 block ledger 共用同一份 `instanceSafeRectsByID`，避免 block 与 sibling ledger 使用不同 safe rect 口径。
- block decision signals 新增 `safeRectSource = maskDerivedInstanceLitePixels` / `nil`，保持 schema 不变。
- 所有结果仍是 report-only；不写回 `safeLayoutRect`、DistanceField 报告、renderer、OCR 输入、翻译输入、active artifacts 或 `configuration.currentBlockSource`。

关键文件：

- `AITRANS/Services/MangaOverlayProbeService.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`

验证结果：

- `swiftc -parse $(rg --files AITRANS -g '*.swift')`
- `git diff --check`

遗留事项：

- 该 safe rect 仍是 AITRANS native-lite report-only 近似，不代表真实 Koharu `BubbleMask` distance field 已接入。
- 真实 P3 收益仍需手动 GitHub Actions `ci-fast/full` 结果包检查 `koharuNativeBubbleMaskInstanceLiteReport` 的 block / sibling ledger。

### v1.50：Detector-Lite 竖排 Rotation Shadow OCR
日期：2026-07-06

依据：`md/koharu研究/v1.38-current-gap-to-koharu.md` 的 P2 方向，向 Koharu 的竖排 / 方向处理能力靠近；本轮不新建 active artifact、不新增 LLM、不替换主 OCR / 翻译 / 覆盖 / 通过判定。

核心变更：

- `koharuNativeTextBoxDetectorLiteShadowOCRReport` 复用既有 `directionHint` / `rotationApplied` 字段，对 v1.39 `verticalCandidate` 做有上限的 `[0,90]` crop OCR shadow 对照。
- `verticalCandidate` crop OCR 使用受限 `ja-JP/ja/en-US/en` Vision language profile；横排候选保留默认 0 度 / 英语路径。
- v1.40 候选选择按当前 block 与 bbox 的 overlap / center containment 优先于全局 detector score，降低 same-bubble sibling 共享错误高分候选的风险。
- full 模式每块最多跑 2 个候选时，block ledger 的 `selectedCandidateID` 现在记录本块 report-only 最佳 shadow OCR 候选，v1.41 refinement 跟随该最佳 ID。
- rotation 对照仍按候选计入既有每块选择预算：`ci-fast` 每块最多 1 个 detector-lite 候选、`full` 每块最多 2 个；不会新增候选池或 promotion 路径。
- 旋转结果选择只使用无真值 OCR 质量分和当前文本 word preservation；ground truth 仍只写 evaluation signals，不参与候选选择、OCR 执行、gate 或 nextAction。
- 新增 gate `G-native-textbox-detector-lite-shadow-ocr-vertical-rotation-budget`，记录 vertical candidate 数、实际采用 rotation 数和 rotation breakdown。
- `1_ocr_probe_text.txt` summary 新增 `nativeTextBoxDetectorLiteShadowOCRRotation`，每个 `nativeTextBoxDetectorLiteShadowOCRCandidate` 输出 `rotation=`。

关键文件：

- `AITRANS/Services/MangaOverlayProbeService.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`

验证计划：

- 本地运行 Swift parse、workflow YAML parse、`git diff --check`、JSON smoke 和 Koharu artifact validator smoke。
- 本轮不跑本地 Xcode build 或模拟器漫画探针；真实 v1.50 `rotationApplied` 结果以手动 GitHub Actions `ci-fast/full` 输出为准。

遗留事项：

- 当前 `test/1.png` 是英文横排样例，可能不会稳定触发大量 `verticalCandidate`；P2 真正收益仍需要竖排日语样例或云端结果包证明。
- 该路径仍是 detector-lite shadow OCR，不代表真实 Koharu TextBoxes / OCR 已接入，也不替换主流程。

### v1.49：Detector-Lite 每 Bubble 多候选池
日期：2026-07-06

依据：`md/koharu研究/v1.38-current-gap-to-koharu.md` 的 P1 要求，在没有真实 Koharu artifact 时继续改进 native TextBoxes detector-lite；本轮仍不伪造 active artifact、不使用 Vision OCR 文本 / ground truth / pre-crop / line / TextRegion crop 结果生成候选，不改变主 OCR、翻译、覆盖或通过判定。

核心变更：

- `koharuNativeTextBoxDetectorLiteReport` 从每个 bubble 单一暗连通域 union 候选，改为每个 bubble 有上限的预 OCR candidate pool：最多 4 个 component-cluster TextBox 候选 + 1 个 diagnostic union fallback。
- component-cluster 候选按 bubble 内连通域 gap / projection split 生成；union fallback 仅用于诊断，固定 `shadowOCREligible = false`，避免在 v1.40 `ci-fast` 每块 1 个候选预算下抢占 shadow OCR。
- detector-lite candidate ID 改为稳定零填充序号 `NTBDL-<bubbleID>-<NN>`，并按 bubble、shadow OCR eligibility、score、ID 稳定排序。
- 多候选到 current block 的关系改为 bbox overlap / center containment 优先；component-cluster 无匹配时才回退同 bubble 最近块，避免同 bubble sibling 全部共享同一高分候选。
- `G-native-textbox-detector-lite-candidate-pool-cap` gate 记录候选池上限，文档和测试口径同步要求 `bubbleLedgerCount == evaluatedBubbleCount`、candidate pool 有上限且 union fallback 不参与 shadow OCR。

关键文件：

- `AITRANS/Services/MangaOverlayProbeService.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`

验证计划：

- 本地运行 Swift parse、workflow YAML parse、`git diff --check`、JSON smoke 和 Koharu artifact validator valid / invalid / active-missing smoke。
- 本轮不跑本地 Xcode build 或模拟器漫画探针；完整 build 和真实 `ci-fast/full` 探针仍交给 GitHub Actions。

遗留事项：

- 多候选池仍是 proxy-not-real Koharu TextBoxes；真实晋级仍需要 Release 注入真实 Koharu artifact archive 并通过 active artifact validator。
- 手动 `ci-fast/full` 才会运行 v1.40/v1.41 shadow OCR / refinement OCR；push 默认快验仍保持 probe skip 以控制云端耗时。

### v1.48 Koharu active artifact CI intake 与契约硬化
日期：2026-07-06

依据：`md/koharu研究/v1.38-current-gap-to-koharu.md` 的 P0 要求从 report-only 转向真实 `test/koharu_artifacts/` 输入。本轮不伪造 active artifact、不复制 examples、不使用 Vision OCR / pre-crop / line / proxy / ground truth / 手写框生成四件套。

核心变更：

- `AITRANS CI Results` 新增手动 `workflow_dispatch` 输入 `koharu_artifact_release_tag`、`koharu_artifact_asset`、`koharu_artifact_sha256`、`koharu_artifact_required`。
- 当提供真实 Koharu artifact archive 时，CI 在 Xcode build 前从 Release 下载、校验 SHA256、解压，并只复制 `1.manifest.json`、`1.textboxes.json`、`1.bubbles.json`、`1.segment_mask.json` 到 `test/koharu_artifacts/`，随后运行 validator。`koharu_artifact_required=true` 时注入或 validator 失败会阻断工作流。
- `ci-artifact-manifest.json` 新增 Koharu artifact 注入来源、required 状态、注入结果、Release tag、asset、SHA 和注入日志路径，Agent C 可区分缺 artifact 阻塞路径与真实 artifact 注入路径。
- `scripts/validate-koharu-artifacts.py` 将 `schemaVersion` 缺失 / 不匹配变成 readiness 阻塞，`schemaVersion` 必须为 `aitrans.koharu_artifact_contract.v1`。
- Python validator 和 Swift readiness 都拒绝 manifest artifact path 使用绝对路径或 `..` 逃逸 active artifact root，避免 active manifest 指向目录外文件。
- 新增 invalid fixtures：`schema_mismatch` 和 `path_escape`，并加入 CI 静态检查 `--expect-fail`。

关键文件：

- `.github/workflows/ci-results.yml`
- `scripts/validate-koharu-artifacts.py`
- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `md/koharu研究/artifact_contract/README.md`
- `md/test/test.md`
- `md/flow/flow.md`
- `README.md`

验证结果：

- 本轮应通过轻量检查：Swift parse、workflow YAML parse、`git diff --check`、JSON parse、validator valid / invalid / active missing。
- 本轮不跑本地 Xcode build 或模拟器漫画探针；完整 build 和 `ci-fast/full` 仍交给 GitHub Actions。

遗留事项：

- 当前仓库默认仍没有真实 active `test/koharu_artifacts/`，因此不能声称 `externalTextBoxShadowOCRReport.executed = true` 已验证。
- 下一步若有真实 Koharu archive，手动 `workflow_dispatch` 填写 Koharu artifact 输入并选择 `ci-fast`，验收 `koharuArtifactValidation.verdict = readyForShadowOCR`、Swift readiness ready、external shadow OCR executed。
- 若短期仍无真实 artifact，下一步按 v1.38 P1 改进 native TextBoxes detector-lite：每个 bubble 生成多个 OCR 前 TextBox 候选，而不是将全部暗连通域 union 成单一大框。

### 维护：AITRANS CI Results 默认快验加速
日期：2026-07-06

本轮根据 Agent X 目标和云端 CI 速度要求，精简默认云端验证路径；不修改漫画探针算法、不刷新仓库根 `output/`，不追加 `metrics/version_history.csv`。

核心变更：

- `AITRANS CI Results` 增加 `concurrency`，同一 ref 新 run 会取消旧 run，避免连续 push 堆积 macOS runner。
- `push` 到 `smalldata_test` / `codeb/**` 默认 `probe_mode=skip`，只跑静态检查、Xcode build、manifest 和未加密结果包；不下载 GGUF、不创建模拟器、不安装 App、不跑漫画探针。
- 手动 `workflow_dispatch` 仍可选择 `ci-fast` 或 `full` 跑真实 simulator + Local GGUF 漫画探针。
- `probe_mode=skip` 时 JUnit 把 GGUF model / simulator / manga probe 跳过视为快验成功，并在 manifest 写 `probeSkippedReason = default_push_fast_ci_or_manual_skip` 与 `modelSetupSkippedReason = probe_mode_skip_fast_ci_does_not_need_model`。
- 手动探针模式下，GGUF cache 只在 SHA 校验成功后保存；build 或模型校验失败时不再继续定位 App 或启动模拟器。
- 手动探针导入模型到 App sandbox 时优先使用 APFS clone `cp -c`，失败再回退普通复制。
- 手动探针新增 `probeNoProgressTimeoutSeconds`，`ci-fast` 180 秒、`full` 300 秒内若没有生成 progress 文件会提前失败，避免 App 未启动时等满总超时。

关键文件：

- `.github/workflows/ci-results.yml`
- `README.md`
- `AGENTS.md`
- `md/flow/flow.md`
- `md/test/test.md`
- `update_log.md`

验证计划：

- 本地运行 YAML 解析、`git diff --check` 和现有 JSON smoke。
- 未跑本机 build / 探针；push 后默认云端快验应只检查静态项和 Xcode build。需要漫画探针结果时手动触发 `workflow_dispatch` 的 `ci-fast` 或 `full`。

遗留事项：

- 手动 `ci-fast` 内部仍会运行 v1.40 / v1.41 detector-lite shadow OCR / refinement OCR 等额外 Vision crop OCR；若后续还嫌手动探针慢，需要在 Swift run options 中新增更细粒度门控并同步 v1.29-v1.46 验收口径。

### v1.47：Koharu Native Artifact Contract Dry-Run 四件套准入干跑
日期：2026-07-06

依据：Agent X 继续沿 `md/koharu研究/v1.38-current-gap-to-koharu.md` 推进，避免继续只堆抽象报告，转向真实 Koharu artifact 四件套准入的机器可验 dry-run。本轮修改 Swift 探针报告模型、TXT 摘要和核心文档；不刷新仓库根 `output/`，不追加 `metrics/version_history.csv`，完整 build / 探针交给 GitHub Actions。

核心变更：

- 新增 `koharuNativeArtifactContractDryRunReport`，在 v1.46 `koharuNativePromotionGateLiteReport` 后生成。
- 报告把 v1.46 `candidateExportPreviews[]` 映射到 active 四件套 contract：`test/koharu_artifacts/1.manifest.json`、`1.textboxes.json`、`1.bubbles.json`、`1.segment_mask.json`。
- 报告写出 `sourceImage = test/1.png`、`coordinateSpace = originalImageTopLeftPixels`、`activeInputDirectory`、`examplesDirectory`、required files、required fields、missing fields、forbidden source breakdown、validator commands 和 gate ledger。
- `koharuArtifactConvergenceReport` 现在把 v1.47 纳入 `referenceReports`、`workItemLedger` 和 `gateLedger`，用 `WI-koharu-native-artifact-contract-dry-run` / `G-koharu-native-artifact-contract-dry-run-executed` 明确记录真实四件套 intake 仍阻塞或 ready。
- `activeExportAllowed = false`、`dryRunOnly = true`，native-lite / proxy preview 只做 contract dry-run，不创建、复制或修改 active `test/koharu_artifacts/`。
- `1_ocr_probe_text.txt` 新增 dry-run summary、required file、preview、gate、validator command 和 forbidden active source 摘要。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`

验证计划：

- 本地运行 Swift parse、YAML 解析、`git diff --check`、JSON smoke 和 Koharu artifact validator 正反例。
- 云端手动 `workflow_dispatch` 的 `ci-fast` 应证明 `koharuNativeArtifactContractDryRunReport.enabled = true`、`evaluatedBlockCount == totalBlocksDetected`、`requiredFileCount >= 4`、`contractGateCount >= 6`、`dryRunOnly = true`、`activeExportAllowed = false`、`groundTruthUsedForDecision = false`、`wouldChangeMainFlow = false`，`koharuArtifactConvergenceReport.referenceReports` 包含该报告，`workItemLedger` / `gateLedger` 包含 `WI-koharu-native-artifact-contract-dry-run` / `G-koharu-native-artifact-contract-dry-run-executed`，且 `1_ocr_probe_text.txt` 包含 `nativeArtifactContractDryRunRequiredFile` 和 `nativeArtifactContractDryRunPreview`。

遗留事项：

- 旧仓库根 `output/` 不含 v1.47 新字段；以 PR 后云端结果包为准。
- v1.47 仍不代表真实 Koharu `TextBoxes` / `BubbleMask` / `SegmentMask` 已接入；下一步仍需要真实 active 四件套或更强 detector 输出通过 validator。

### v1.46：Koharu Native Promotion Gate-Lite 探针驱动晋级门槛
日期：2026-07-03
依据：`md/prompt/v1（漫画探针）/v1.46（KoharuNativePromotionGateLite探针驱动晋级门槛）.md`。本轮修改 Swift 探针报告模型、native-lite promotion gate 聚合账本、Koharu convergence 联动、TXT 快照和核心文档；不刷新仓库根 `output/`，不追加 `metrics/version_history.csv`，完整 build / 探针交给 GitHub Actions。

核心变更：

- 新增 `koharuNativePromotionGateLiteReport`，在 v1.45 Native Artifact Bundle-Lite 后、最终 convergence 刷新前生成。
- 报告只消费 final blocks、diagnostics、v1.39-v1.45 native-lite reports、RenderSprite fit、Render Regression Lock、Translation Model Floor、clean text diagnostic 和 external artifact readiness。
- 每个 final block 输出 report-only promotion ledger，覆盖 TextBoxes / BubbleMask / SegmentMask / OcrText / Translations / RenderedSprites / FinalRender 的晋级状态、primary blocking artifact、probe bottleneck、promotion eligibility、nextAction 和 `mustNotPromoteReasons`。
- 新增 canonical stage gates，覆盖 TextBoxes、BubbleMask、SegmentMask、OcrText、Translations、RenderedSprites、FinalRender 和 ExternalArtifacts。
- 新增 `nativeCandidateExportPreview`，只在 JSON / TXT 中预览未来 AITRANS-native candidate artifact 可能需要的字段、来源、bbox、风险和 validator 要求；本轮不创建、不复制、不修改 active `test/koharu_artifacts/`。
- `koharuArtifactConvergenceReport.referenceReports` 新增 `koharuNativePromotionGateLiteReport`；convergence 新增 `WI-koharu-native-promotion-gate-lite` 和 `G-koharu-native-promotion-gate-lite-executed`。
- `1_ocr_probe_text.txt` 新增 promotion gate summary、stage gate、逐块 block ledger、candidate export preview 和 work item 摘要。
- 本轮不新增 OCR / LLM / PNG，不更换模型，不接 active artifact，不改变主 OCR、翻译输入、覆盖图、renderer、`safeLayoutRect`、`glyphMaskFillRects`、背景填充、`blockPassed`、失败分类、`textRegionCropReport.adoptedCount`、active artifacts 或 `configuration.currentBlockSource`；ground truth 只进 evaluation signals。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`
- `md/prompt/v1（漫画探针）/v1.46（KoharuNativePromotionGateLite探针驱动晋级门槛）.md`

验证计划：

- 本轮 Agent B 本地运行轻量 Swift 语法检查、`git diff --check`、JSON 解析和 Koharu validator smoke。
- 未跑本机 build / 探针，按规则交给云端验证。
- 云端 `AITRANS CI Results` `ci-fast` 应证明 `koharuNativePromotionGateLiteReport.enabled = true`、`evaluatedBlockCount == totalBlocksDetected`、`blockLedgerCount == totalBlocksDetected`、`stageGateCount >= 8`、`candidateExportPreviewCount >= 1` 或明确 blocked / warning reason、`workItemCount >= 1`、`gateCount >= 8`、`promotionGateLite = true`、`nativePromotionPreviewOnly = true`、所有 proxy-not-real 边界为 true、`externalArtifactsRequiredForThisReport = false`、`groundTruthUsedForDecision = false`，核心 breakdown 非空或上游缺失时明确 warning / blocked gate，convergence 包含 v1.46 reference / work item / gate，且 `1_ocr_probe_text.txt` 包含 summary、stage gate、逐块 promotion ledger、candidate preview 和 work item。

遗留事项：

- 旧仓库根 `output/` 不含 v1.46 新字段；以 PR 后云端结果包为准。
- v1.46 仍是 native promotion gate-lite report-only 晋级门槛层，不代表真实 Koharu `TextBoxes` / `BubbleMask` / `SegmentMask` / `OcrText` / `RenderedSprites` 已接入，也不代表 OCR 或翻译质量改善。
- 本轮未重新跑完整漫画探针，不追加 `metrics/version_history.csv` 漫画指标行。

### v1.45：Koharu Native Artifact Bundle-Lite 结构一致性闭环
日期：2026-07-03
依据：`md/prompt/v1（漫画探针）/v1.45（KoharuNativeArtifactBundleLite结构一致性闭环）.md`。本轮修改 Swift 探针报告模型、native-lite artifact bundle 聚合账本、Koharu convergence 联动、TXT 快照和核心文档；不刷新仓库根 `output/`，不追加 `metrics/version_history.csv`，完整 build / 探针交给 GitHub Actions。

核心变更：

- 新增 `koharuNativeArtifactBundleLiteReport`，在 v1.44 SegmentMask refinement-lite 后、最终 convergence 刷新前生成。
- 报告只消费 final blocks、v1.39-v1.42 detector-lite / shadow OCR / refinement / closed-loop、v1.43 BubbleMask instance-lite、v1.44 SegmentMask refinement-lite、RenderSprite fit、Render Regression Lock、Translation Model Floor、external artifact readiness 和 diagnostics。
- 每个 final block 组装 report-only bundle：selected TextBox / Bubble / Segment component、OCR evidence、translation route、render evidence、artifact consistency verdict、primary blocking artifact 和 nextAction。
- 新增逐块 consistency edges，覆盖 TextBoxWithinBubble、SegmentMaskWithinTextBox、SegmentMaskWithinBubble、FinalOCRBBoxAlignedWithTextBox、SameBubbleSiblingMaskNonOverlap、SeamOrSplitRiskExplainsConflict、RenderSpriteContainedByBundleSafeArea 和 ModelFloorSeparatesGeometryFromTranslation。
- `koharuArtifactConvergenceReport.referenceReports` 新增 `koharuNativeArtifactBundleLiteReport`；convergence 新增 `WI-koharu-native-artifact-bundle-lite` 和 `G-koharu-native-artifact-bundle-lite-executed`。
- `1_ocr_probe_text.txt` 新增 bundle-lite summary、逐块 block ledger、consistency edge 和 work item 摘要。
- 本轮不新增 OCR / LLM / PNG，不更换模型，不创建或接入 active Koharu artifact，不改变主 OCR、翻译输入、覆盖图、renderer、`safeLayoutRect`、`glyphMaskFillRects`、背景填充、`blockPassed`、失败分类、`textRegionCropReport.adoptedCount`、active artifacts 或 `configuration.currentBlockSource`。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`
- `md/prompt/v1（漫画探针）/v1.45（KoharuNativeArtifactBundleLite结构一致性闭环）.md`

验证计划：

- 本轮 Agent B 本地运行 `swiftc -parse` 轻量 Swift 语法检查、`git diff --check`、JSON 解析和 Koharu validator smoke。
- 未跑本机 build / 探针，按规则交给云端验证。
- 云端 `AITRANS CI Results` `ci-fast` 应证明 `koharuNativeArtifactBundleLiteReport.enabled = true`、`evaluatedBlockCount == totalBlocksDetected`、`bundleLedgerCount == totalBlocksDetected`、`consistencyEdgeCount >= totalBlocksDetected`、`workItemCount >= 1`、`gateCount >= 8`、`nativeBundleLite = true`、TextBoxes / BubbleMask / SegmentMask proxy 边界为 true、`externalArtifactsRequiredForThisReport = false`、`groundTruthUsedForDecision = false`，核心 breakdown 非空或上游缺失时明确 warning / blocked gate，convergence 包含 v1.45 reference / work item / gate，且 `1_ocr_probe_text.txt` 包含 summary、逐块 block ledger、consistency edge 和 work item。

遗留事项：

- 旧仓库根 `output/` 不含 v1.45 新字段；以 PR 后云端结果包为准。
- v1.45 仍是 native artifact bundle-lite report-only 结构一致性闭环，不代表真实 Koharu `TextBoxes` / `BubbleMask` / `SegmentMask` / `RenderedSprites` 已接入，也不代表 OCR 或翻译质量改善。
- 本轮未重新跑完整漫画探针，不追加 `metrics/version_history.csv` 漫画指标行。

### v1.44：Koharu Native SegmentMask Refinement-Lite 文字像素掩码影子复刻
日期：2026-07-03
依据：`md/prompt/v1（漫画探针）/v1.44（KoharuNativeSegmentMaskRefinementLite文字像素掩码影子复刻）.md`。本轮修改 Swift 探针报告模型、TextBox 约束文字像素 mask refinement-lite 账本、Koharu convergence 联动、TXT 快照和核心文档；不刷新仓库根 `output/`，不追加 `metrics/version_history.csv`，完整 build / 探针交给 GitHub Actions。

核心变更：

- 新增 `koharuNativeSegmentMaskRefinementLiteReport`，在 v1.43 instance-lite BubbleMask 之后、最终 convergence 刷新前生成。
- 报告只使用源图像像素、detector-lite TextBox 候选、final blocks、v1.43 instance-lite BubbleMask、现有 glyph / SegmentMask proxy、render lock 和翻译失败分类，生成 TextBox-constrained glyph pixel mask 的 candidate / block / sibling / gate 账本。
- `groundTruthUsedForDecision = false`，ground truth 只进入 evaluation signals；像素阈值、TextBox 选择、mask 生成、route、nextAction、verdict 和 gate 都不使用真值。
- `koharuArtifactConvergenceReport.referenceReports` 新增 `koharuNativeSegmentMaskRefinementLiteReport`；convergence 新增 `WI-koharu-native-segmentmask-refinement-lite` 和 `G-koharu-native-segmentmask-refinement-lite-executed`。
- `1_ocr_probe_text.txt` 新增 SegmentMask refinement-lite report summary、candidate ledger、逐块 block ledger 和 same-bubble sibling ledger 摘要。
- 本轮不新增 OCR / LLM / PNG，不更换模型，不创建 active Koharu artifact，不改变主 OCR、翻译输入、覆盖图、`safeLayoutRect`、`glyphMaskFillRects`、背景填充、renderer、`blockPassed`、失败分类、`textRegionCropReport.adoptedCount`、active artifacts 或 `configuration.currentBlockSource`。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`
- `md/prompt/v1（漫画探针）/v1.44（KoharuNativeSegmentMaskRefinementLite文字像素掩码影子复刻）.md`

验证计划：

- 本轮 Agent B 本地运行 `git diff --check`、JSON 解析、Koharu validator smoke，并用轻量 Swift parse 检查新增 Swift 语法。
- 未跑本机 build / 探针，按规则交给云端验证。
- 云端 `AITRANS CI Results` `ci-fast` 应证明 `koharuNativeSegmentMaskRefinementLiteReport.enabled = true`、`evaluatedBlockCount == totalBlocksDetected`、`blockLedgerCount == totalBlocksDetected`、`candidateLedgerCount >= totalBlocksDetected`、`gateCount >= 8`、`nativeRefinementLite = true`、`proxyNotRealKoharuSegmentMask = true`、`usesSourceImagePixels = true`、`usesTextBoxConstraints = true`、`usesBubbleMaskConstraints = true`、`groundTruthUsedForDecision = false`，核心 breakdown 非空或像素证据不足时明确 blocked / warning gate，convergence 包含 v1.44 reference / work item / gate，且 `1_ocr_probe_text.txt` 包含 summary、candidate ledger、逐块 block ledger 和 sibling ledger。

遗留事项：

- 旧仓库根 `output/` 不含 v1.44 新字段；以 PR 后云端结果包为准。
- v1.44 仍是 native SegmentMask refinement-lite report-only 影子复刻，不代表真实 Koharu `SegmentMask` / `TextBoxes` / `BubbleMask` 已接入，也不代表 OCR 或翻译质量改善。
- 本轮未重新跑完整漫画探针，不追加 `metrics/version_history.csv` 漫画指标行。

### v1.43：Koharu Native BubbleMask Instance-Lite 像素实例掩码影子复刻
日期：2026-07-03
依据：`md/prompt/v1（漫画探针）/v1.43（KoharuNativeBubbleMaskInstanceLite像素实例掩码影子复刻）.md`。本轮修改 Swift 探针报告模型、像素 instance-lite BubbleMask 账本、Koharu convergence 联动、TXT 快照和核心文档；不刷新仓库根 `output/`，不追加 `metrics/version_history.csv`，完整 build / 探针交给 GitHub Actions。

核心变更：

- 新增 `koharuNativeBubbleMaskInstanceLiteReport`，在 v1.42 detector-lite closed-loop 之后、最终 convergence 刷新前生成。
- 报告只使用源图像内容裁切区像素、现有 bubble geometry、final blocks、glyph / SegmentMask proxy、BubbleIndex / DistanceField / seam / RenderSprite fit、detector-lite closed-loop 和 render lock 证据，生成近白连通域 instance-lite ID mask 账本。
- 输出 `instances[]`、`blockLedgers[]`、`siblingLedgers[]`、`adjacencyLedgers[]` 和 `gateLedger[]`，逐块记录 current bubble、instance-lite majority、safe rect 对照、sprite containment、translation failure route、detector-lite route、primary bottleneck 和 nextAction。
- `groundTruthUsedForDecision = false`，ground truth 只进入 evaluation signals；mask 生成、majority assignment、route、nextAction、verdict 和 gate 都不使用真值。
- `koharuArtifactConvergenceReport.referenceReports` 新增 `koharuNativeBubbleMaskInstanceLiteReport`；convergence 新增 `WI-koharu-native-bubblemask-instance-lite` 和 `G-koharu-native-bubblemask-instance-lite-executed`。
- `1_ocr_probe_text.txt` 新增 instance-lite report summary、实例账本、逐块 majority assignment、sibling / adjacency 和 convergence v1.43 work item / gate 摘要。
- 本轮不新增 OCR / LLM / PNG，不更换模型，不创建 active Koharu artifact，不改变主 OCR、翻译输入、覆盖图、`safeLayoutRect`、DistanceField safe rect、renderer、`blockPassed`、失败分类、`textRegionCropReport.adoptedCount`、active artifacts 或 `configuration.currentBlockSource`。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`
- `md/prompt/v1（漫画探针）/v1.43（KoharuNativeBubbleMaskInstanceLite像素实例掩码影子复刻）.md`

验证计划：

- 本轮 Agent B 本地运行 `git diff --check`、JSON 解析、Koharu validator smoke，并用轻量 Swift parse 检查新增 Swift 语法。
- 未跑本机 build / 探针，按规则交给云端验证。
- 云端 `AITRANS CI Results` `ci-fast` 应证明 `koharuNativeBubbleMaskInstanceLiteReport.enabled = true`、`evaluatedBlockCount == totalBlocksDetected`、`blockLedgerCount == totalBlocksDetected`、`gateCount >= 8`、`nativeInstanceLite = true`、`proxyNotRealKoharuBubbleMask = true`、`usesSourceImagePixels = true`、`groundTruthUsedForDecision = false`、核心 breakdown 非空或像素证据不足时明确 blocked / warning gate，convergence 包含 v1.43 reference / work item / gate，且 `1_ocr_probe_text.txt` 包含 summary、instance ledger、逐块 block ledger、sibling 和 adjacency ledger。

遗留事项：

- 旧仓库根 `output/` 不含 v1.43 新字段；以 PR 后云端结果包为准。
- v1.43 仍是 native BubbleMask instance-lite report-only 影子复刻，不代表真实 Koharu `BubbleMask` / `TextBoxes` / `SegmentMask` 已接入，也不代表 OCR 或翻译质量改善。
- 本轮未重新跑完整漫画探针，不追加 `metrics/version_history.csv` 漫画指标行。

### v1.42：Native TextBox Detector-Lite 闭环裁决与结构路由
日期：2026-07-03
依据：`md/prompt/v1（漫画探针）/v1.42（NativeTextBoxDetectorLite闭环裁决与结构路由）.md`。本轮修改 Swift 探针报告模型、detector-lite 闭环裁决与结构路由账本、Koharu convergence 联动、TXT 快照和核心文档；不刷新仓库根 `output/`，不追加 `metrics/version_history.csv`，完整 build / 探针交给 GitHub Actions。

核心变更：

- 新增 `koharuNativeTextBoxDetectorLiteClosedLoopReport`，在 v1.41 refinement 之后、最终 convergence 刷新前生成。
- 报告消费 v1.39 detector-lite、v1.40 shadow OCR、v1.41 refinement、final blocks、BubbleMask / SegmentMask proxy、翻译失败分类、Translation Model Floor、Render Regression Lock 和 external artifact readiness，产出 candidate family ledger、逐块 closed-loop route、stoplist、full-probe review、真实 artifact 需求、模型地板和 render lock 路由。
- route / nextAction / gate / candidate family verdict 只使用 ground-truth-free decision signals；ground truth 只写入 evaluationSignals。
- `koharuArtifactConvergenceReport.referenceReports` 新增 `koharuNativeTextBoxDetectorLiteClosedLoopReport`；convergence 新增 `WI-koharu-native-textbox-detector-lite-closed-loop-router` 和 `G-koharu-native-textbox-detector-lite-closed-loop-router-executed`。
- `1_ocr_probe_text.txt` 新增 detector-lite closed-loop report summary、candidate family rollup 和逐块 `nativeTextBoxDetectorLiteClosedLoopBlockLedger`。
- 本轮不新增 OCR / LLM / PNG，不更换模型，不接入外部 artifact，不改变主 OCR、翻译输入、覆盖图、`finalTextUsedForTranslation`、`blockPassed`、失败分类、`textRegionCropReport.adoptedCount`、active artifacts 或 `configuration.currentBlockSource`。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`
- `md/prompt/v1（漫画探针）/v1.42（NativeTextBoxDetectorLite闭环裁决与结构路由）.md`

验证计划：

- 本轮 Agent B 本地运行 `git diff --check`、JSON 解析、Koharu validator smoke，并用轻量 Swift 解析检查新增 Swift 语法。
- 未跑本机 build / 探针，按规则交给云端验证。
- 云端 `AITRANS CI Results` `ci-fast` 应证明 `koharuNativeTextBoxDetectorLiteClosedLoopReport.enabled = true`、`evaluatedBlockCount == totalBlocksDetected`、`blockLedgerCount == totalBlocksDetected`、`candidateFamilyCount == totalBlocksDetected`、`gateCount >= 8`，核心 route / verdict / bottleneck / nextAction breakdown 非空或上游缺失时明确 `blockedByMissingUpstreamReports`，convergence 包含 v1.42 reference / work item / gate，且 `1_ocr_probe_text.txt` 包含 summary、candidate family 和逐块 block ledger。

遗留事项：

- 旧仓库根 `output/` 不含 v1.42 新字段；以 PR 后云端结果包为准。
- v1.42 仍是 detector-lite report-only 路由，不代表真实 Koharu TextBoxes / BubbleMask / SegmentMask 已接入，也不代表模型质量改善。
- 本轮未重新跑完整漫画探针，不追加 `metrics/version_history.csv` 漫画指标行。

### v1.41：Native TextBox Detector-Lite 闭环二次候选与 Refinement Shadow OCR
日期：2026-07-02
依据：`md/prompt/v1（漫画探针）/v1.41（NativeTextBoxDetectorLite闭环二次候选与RefinementShadowOCR）.md`。本轮修改 Swift 探针报告模型、detector-lite refinement shadow OCR 链路、Koharu convergence 联动、TXT 快照和核心文档；不刷新仓库根 `output/`，不追加 `metrics/version_history.csv`，完整 build / 探针交给 GitHub Actions。

核心变更：

- 新增 `koharuNativeTextBoxDetectorLiteRefinementReport`，执行顺序在 v1.40 `koharuNativeTextBoxDetectorLiteShadowOCRReport` 之后、最终 `koharuArtifactConvergenceReport` refresh 之前。
- target selection 只使用 v1.40 shadow OCR outcome、block failure category、模型地板、渲染锁和 detector-lite relation 等 ground-truth-free 信号；ground truth 只写入 evaluation signals。
- refined candidate bbox 只从 v1.39 `nativeDetectorLite` 父候选出发，用 source image 暗像素 envelope、projection band、directional padding 和 bubble ID 一致时的保守 bubble clip 二次收紧。
- `ci-fast` 总 refinement OCR 预算限制为 `<= min(6,totalBlocksDetected)`，每块最多 1 个；`full` 每块最多 2 个且仍有总上限。
- candidate / block ledger 输出 base bbox、refined bbox、refinement strategy、target reason、OCR raw / normalized text、quality delta vs current / detector-lite shadow、word preservation、evaluation-only ground truth similarity delta、outcome 和 report-only rejection reasons。
- `koharuArtifactConvergenceReport.referenceReports` 新增 `koharuNativeTextBoxDetectorLiteRefinementReport`；convergence 新增 `WI-koharu-native-textbox-detector-lite-refinement` 和 `G-koharu-native-textbox-detector-lite-refinement-executed`。
- `1_ocr_probe_text.txt` 新增 detector-lite refinement report summary、refined candidate ledger 和逐块 `nativeTextBoxDetectorLiteRefinementBlockLedger`。
- 本轮不新增 LLM 调用，不更换模型，不接入外部 artifact，不改变主 OCR、翻译输入、覆盖图、`finalTextUsedForTranslation`、`blockPassed`、失败分类、`textRegionCropReport.adoptedCount`、active artifacts 或 `configuration.currentBlockSource`。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`
- `md/prompt/v1（漫画探针）/v1.41（NativeTextBoxDetectorLite闭环二次候选与RefinementShadowOCR）.md`

验证计划：

- 本轮 Agent B 本地运行 `git diff --check`、JSON 解析、Koharu validator smoke，并用轻量 Swift parse 检查新增 Swift 语法。
- 未跑本机 build / 探针，按规则交给云端验证。
- 云端 `AITRANS CI Results` `ci-fast` 应证明 `koharuNativeTextBoxDetectorLiteRefinementReport.enabled = true`、`evaluatedBlockCount == totalBlocksDetected`、`blockLedgerCount == totalBlocksDetected`、`ocrExecutedCount <= min(6,totalBlocksDetected)`、`gateCount >= 8`，核心 breakdown 非空或无 target 时明确 blocked ledger，convergence 包含 v1.41 reference / work item / gate，且 `1_ocr_probe_text.txt` 包含 summary、candidate ledger 和逐块 block ledger。

遗留事项：

- 旧仓库根 `output/` 不含 v1.35-v1.41 新字段；以 PR 后云端结果包为准。
- v1.41 仍是 detector-lite refinement shadow-only，不代表真实 Koharu TextBoxes / BubbleMask / SegmentMask 已接入，也不代表模型质量改善。
- 本轮未重新跑完整漫画探针，不追加 `metrics/version_history.csv` 漫画指标行。

### v1.40：Native TextBox Detector-Lite Shadow OCR 评估闭环
日期：2026-07-02
依据：`md/prompt/v1（漫画探针）/v1.40（NativeTextBoxDetectorLiteShadowOCR评估闭环）.md`。本轮修改 Swift 探针报告模型、受限 detector-lite crop OCR 评估链路、Koharu convergence 联动、TXT 快照和核心文档；不刷新仓库根 `output/`，不追加 `metrics/version_history.csv`，完整 build / 探针交给 GitHub Actions。

核心变更：

- 新增 `koharuNativeTextBoxDetectorLiteShadowOCRReport`，只消费 v1.39 `koharuNativeTextBoxDetectorLiteReport.candidates` 中 `shadowOCREligible = true` 的 `nativeDetectorLite` 候选。
- `ci-fast` 每块最多执行 1 个 detector-lite bbox OCR，`full` 每块最多 2 个；候选选择只使用 detector-lite score、bubble / glyph / block 关系、direction hint 和 ledger 信号。
- candidate ledger 输出 source candidate、bbox、crop padding、scale、OCR raw / normalized text、empty / failed / succeeded、word preservation、quality delta、evaluation-only ground truth similarity delta、outcome 和 report-only rejection reasons。
- block ledger 覆盖所有最终 blocks，记录 selected candidate、shadow OCR text、当前 / shadow OCR quality、better / worse / same / empty / failed / notSelected、primary bottleneck、nextAction 和 whyNotPromoted。
- 报告明确 `groundTruthUsedForDecision = false`、`groundTruthUsedForEvaluationOnly = true`、`wouldChangeMainFlow = false`、`diagnosticOnly = true`、`proxyNotRealKoharuTextBoxes = true`、`proxyNotRealKoharuOCR = true`；ground truth 只进 evaluation signals。
- `koharuArtifactConvergenceReport.referenceReports` 新增 `koharuNativeTextBoxDetectorLiteShadowOCRReport`；convergence 新增 `WI-koharu-native-textbox-detector-lite-shadow-ocr` 和 `G-koharu-native-textbox-detector-lite-shadow-ocr-executed`。
- `1_ocr_probe_text.txt` 新增 detector-lite shadow OCR report summary、candidate OCR ledger 和逐块 `nativeTextBoxDetectorLiteShadowOCRBlockLedger`。
- 本轮不新增 LLM 调用，不更换模型，不使用 ground truth 决定候选、排序、OCR 执行、nextAction 或 gate，不改变主 OCR、翻译输入、覆盖图、`finalTextUsedForTranslation`、`blockPassed`、失败分类、`textRegionCropReport.adoptedCount`、active artifacts 或 `configuration.currentBlockSource`。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`
- `md/prompt/v1（漫画探针）/v1.40（NativeTextBoxDetectorLiteShadowOCR评估闭环）.md`

验证计划：

- 本轮 Agent B 本地运行 `git diff --check`、JSON 解析、Koharu validator smoke，并用轻量 Swift 解析检查新增 Swift 语法。
- 未跑本机 build / 探针，按规则交给云端验证。
- 云端 `AITRANS CI Results` `ci-fast` 应证明 `koharuNativeTextBoxDetectorLiteShadowOCRReport.enabled = true`、`evaluatedBlockCount == totalBlocksDetected`、`blockLedgerCount == totalBlocksDetected`、`selectedCandidateCount <= totalBlocksDetected`、`ocrExecutedCount == selectedCandidateCount`、`gateCount >= 8`，核心 breakdown 非空或无候选时明确 blocked ledger，convergence 包含 v1.40 reference / work item / gate，且 `1_ocr_probe_text.txt` 包含 summary、candidate ledger 和逐块 block ledger。

遗留事项：

- 旧仓库根 `output/` 不含 v1.35-v1.40 新字段；以 PR 后云端结果包为准。
- shadow OCR 可能全部 empty / worse；这属于本轮要显式记录的评估结果，不能静默跳过，也不能因此替换主流程。
- 本轮未重新跑完整漫画探针，不追加 `metrics/version_history.csv` 漫画指标行。

### v1.39：Koharu Native TextBox Detector-Lite 预 OCR 影子复刻
日期：2026-07-02
依据：`md/prompt/v1（漫画探针）/v1.39（KoharuNativeTextBoxDetectorLite预OCR影子复刻）.md`。本轮修改 Swift 探针报告模型、像素 / 几何候选层、Koharu convergence 联动、TXT 快照和核心文档；不刷新仓库根 `output/`，不追加 `metrics/version_history.csv`，完整 build / 探针交给 GitHub Actions。

核心变更：

- 新增 `koharuNativeTextBoxDetectorLiteReport`，只用 source image 像素、bubble geometry、BubbleMask proxy 和 glyph / SegmentMask proxy 生成 OCR 前 `nativeDetectorLite` TextBox 候选。
- 候选输出 `candidateID`、bbox、sourceBubbleID、directionHint、dark pixel density、connected component count、projection peak count、bubble coverage、glyph overlap、score、verdict、shadow OCR eligibility、matched / related block indexes、decision / evaluation signals 和 rejection reasons。
- 新增 block / bubble / gate ledger，逐块记录 best candidate、coverage verdict、bubble assignment risk、segment evidence、OCR input risk、model floor、render lock、primary bottleneck 和 next action；逐 bubble 记录 coverage、split / sibling risk 和 real BubbleMask 需求。
- 报告明确 `groundTruthUsedForDecision = false`、`wouldChangeMainFlow = false`、`diagnosticOnly = true`、`proxyNotRealKoharuTextBoxes = true`、`externalArtifactsRequiredForThisReport = false`；ground truth 只进入 evaluation signals。
- 默认不执行 detector-lite shadow OCR，不新增 LLM 调用；不使用 Vision OCR 文本、`test/1.ground_truth.json`、pre-crop plan、line plan 或 TextRegion crop 结果生成 / 排序候选。
- `koharuArtifactConvergenceReport.referenceReports` 新增 `koharuNativeTextBoxDetectorLiteReport`；convergence 新增 `WI-koharu-native-textbox-detector-lite` 和 `G-koharu-native-textbox-detector-lite-executed`。
- `1_ocr_probe_text.txt` 新增 detector-lite report summary、candidate ledger、bubble ledger 和逐块 `nativeTextBoxDetectorLiteBlockLedger`。
- 本轮不改变主 OCR、whole-page / bubble-first 融合、post-fusion cleanup、翻译输入、translation prompt、模型、`blockPassed`、失败分类、覆盖绘制、`safeLayoutRect`、`textRegionCropReport.adoptedCount`、active artifacts 或 `configuration.currentBlockSource`。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`
- `md/prompt/v1（漫画探针）/v1.39（KoharuNativeTextBoxDetectorLite预OCR影子复刻）.md`

验证计划：

- 本轮 Agent B 本地运行 `swiftc -parse`、`git diff --check`、JSON 解析和 Koharu validator smoke。
- 未跑本机 build / 探针，按规则交给云端验证。
- 云端 `AITRANS CI Results` `ci-fast` 应证明 `koharuNativeTextBoxDetectorLiteReport.enabled = true`、`evaluatedBlockCount == totalBlocksDetected`、`blockLedgerCount == totalBlocksDetected`、`candidateCount >= 1`、`gateCount >= 8`，breakdown 非空，`groundTruthUsedForDecision = false`、`wouldChangeMainFlow = false`、`diagnosticOnly = true`、`proxyNotRealKoharuTextBoxes = true`，convergence 包含 detector-lite reference / work item / gate，且 `1_ocr_probe_text.txt` 包含 summary、candidate ledger、bubble ledger 和逐块 block ledger。

遗留事项：

- 旧仓库根 `output/` 不含 v1.35-v1.39 新字段；以 PR 后云端结果包为准。
- 本轮未重新跑完整漫画探针，不追加 `metrics/version_history.csv` 漫画指标行。

### v1.38：Koharu RenderSprite 排版适配影子复刻
日期：2026-07-02
依据：`md/prompt/v1（漫画探针）/v1.38（KoharuRenderSprite排版适配影子复刻）.md`。本轮修改 Swift 探针报告模型、Koharu convergence 联动、TXT 快照和核心文档；不刷新仓库根 `output/`，不追加 `metrics/version_history.csv`，完整 build / 探针交给 GitHub Actions。

退回修复：

- PR #28 云端 run `28571459833` 在 Xcode build 阶段失败，`xcodebuild.log` 指向 `MangaOverlayProbeService.swift` 中 `MangaKoharuRenderSpriteLayoutCandidateLedger(...)` 大表达式 type-check 超时，后续模拟器安装因缺 bundle ID 连带失败，探针未运行且结果包只保留 `output/probe-not-run.txt`。
- 修复方式是把 RenderSprite layout candidate ledger 的嵌套 `flatMap` / `map` / struct 初始化拆成显式局部 helper 和 `for` 循环，先落地 `candidateID`、`candidateArea`、`areaDeltaVsCurrent`、`decisionSignals`、`evaluationSignals` 等中间变量；字段语义和 report-only 输出不变。
- 本修复不改主 OCR、翻译输入、覆盖绘制、`safeLayoutRect`、DistanceField safe rect、`renderFontSize`、`renderNonTransparentBounds`、`blockPassed`、失败分类、active artifacts 或 `configuration.currentBlockSource`。
- Build IPA #94 run `28574373590` 在合并 commit `902e836` 的 Release archive / `iphoneos` / whole-module optimization 阶段失败，`xcodebuild-archive.log` 指向 `MangaOverlayProbeService.swift:1744` 的 `Task.detached` 大闭包 type-check 超时，并提示该 `await` 内没有 async 操作。本次修复移除 `makeKoharuBubbleAdjacencySeamReport` 外层无必要 `Task.detached` / `.value` 包装，保留原报告计算、字段和 report-only 语义；不改主 OCR、翻译输入、覆盖绘制、`safeLayoutRect`、DistanceField safe rect、RenderSprite fit planner、`blockPassed`、失败分类、active artifacts 或 `configuration.currentBlockSource`。

核心变更：

- 新增 `koharuRenderSpriteFitPlannerReport`，只基于 AITRANS 现有 `safeLayoutRect`、`renderFontSize`、`renderNonTransparentBounds`、render collision、失败 fallback 文本、v1.30 Render Regression Lock、v1.35 BubbleIndex、v1.36 DistanceField 和 v1.37 seam 证据，构建 RenderedSprites 字体预算、换行压力、sprite containment、layout candidate、same-bubble sibling fit 和 failure overlay fit 账本。
- 报告输出 `blockLedgers[]`、`layoutCandidateLedgers[]`、`siblingLedgers[]` 和 `gateLedger[]`，记录 `translationCandidate` / `failureFallback` 渲染文本来源、字符统计、候选 rect、字体预算、seam / sibling / render lock 风险、proxy boundary 和 report-only next action。
- 报告明确 `groundTruthUsedForDecision = false`、`wouldChangeMainFlow = false`、`diagnosticOnly = true`、`proxyNotRealKoharuRenderer = true`、`proxyNotRealBubbleMask = true`；ground truth 只进入 evaluation signals。
- `koharuArtifactConvergenceReport.referenceReports` 新增 `koharuRenderSpriteFitPlannerReport`；convergence 新增 `WI-koharu-render-sprite-fit-planner` 和 `G-koharu-render-sprite-fit-planner-executed`。
- `1_ocr_probe_text.txt` 新增 RenderSprite fit planner summary、layout candidate、sibling fit group 和逐块 `renderSpriteFit`。
- 报告只做 report-only 诊断；不新增 OCR / LLM，不重新渲染 PNG，不改变主 OCR、翻译输入、覆盖图、`safeLayoutRect`、DistanceField safe rect、`renderFontSize`、`renderNonTransparentBounds`、`glyphMaskFillRects`、背景填充、`blockPassed`、失败分类、post-fusion cleanup、候选选择、active artifacts 或 `configuration.currentBlockSource`。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`
- `md/prompt/v1（漫画探针）/v1.38（KoharuRenderSprite排版适配影子复刻）.md`

验证计划：

- 本轮 Agent B 本地运行 `swiftc -parse`、`git diff --check`、JSON 解析和 Koharu validator smoke。
- 未跑本机 build / 探针，按规则交给云端验证。
- 云端 `AITRANS CI Results` `ci-fast` 应证明 `koharuRenderSpriteFitPlannerReport.enabled = true`、`evaluatedBlockCount == totalBlocksDetected`、`blockLedgerCount == totalBlocksDetected`、`layoutCandidateCount >= totalBlocksDetected`、`gateCount >= 10`，breakdown 非空，`proxyNotRealKoharuRenderer = true`、`proxyNotRealBubbleMask = true`，convergence 包含 RenderSprite fit planner reference / work item / gate，且 `1_ocr_probe_text.txt` 包含 summary、layout candidate、sibling fit 和逐块 block ledger。

遗留事项：

- 旧仓库根 `output/` 不含 v1.35-v1.38 新字段；以 PR 后云端结果包为准。
- 本轮未重新跑完整漫画探针，不追加 `metrics/version_history.csv` 漫画指标行。

### v1.37：Koharu 气泡邻接切缝影子复刻
日期：2026-07-02
依据：`md/prompt/v1（漫画探针）/v1.37（Koharu气泡邻接切缝影子复刻）.md`。本轮修改 Swift 探针报告模型、Koharu convergence 联动、TXT 快照和核心文档；不刷新仓库根 `output/`，不追加 `metrics/version_history.csv`，完整 build / 探针交给 GitHub Actions。

退回修复：

- PR #27 云端 run `28564459237` 中 static checks、Xcode build 和 simulator build 通过，但 `mangaProbeOutcome=failure`；`manga-probe.log` 停在 `render-output-start` 后，最终未生成 `probe_report.json`。
- 修复 `koharuBubbleAdjacencySeamReport` 的 proxy mask gap 计算：从整图 mask 像素全量收集 + 双重循环，改为 bubble bbox 内边界采样、样本上限和远距离 bbox gap 近似，保持 report-only 语义和字段含义。
- 在 render 后 Koharu 后置报告链新增进度点，覆盖 BubbleIndex、DistanceField、Bubble adjacency seam、最终 convergence refresh、TXT 重写和 `probe_report` 写入起点，便于云端失败时定位具体卡点。

核心变更：

- 新增 `koharuBubbleAdjacencySeamReport`，只基于 AITRANS 现有 rounded-rect BubbleMask proxy、BubbleIndex、DistanceField、split candidate、same-bubble sibling、OCR damage 和 render lock 证据，构建 bubble adjacency graph、seam candidate ledger 和逐块 seam 风险账本。
- 报告输出 `pairLedgers[]`、`seamCandidateLedgers[]`、`blockLedgers[]` 和 `gateLedger[]`，记录 bbox gap / overlap、proxy mask gap、shared split / sibling / conflict 信号、seam orientation / corridor、assignment conflict、safe-area risk、render lock 和 report-only next action。
- 报告明确 `proxyNotRealBubbleMask = true`、`usesRoundedRectProxyMask = true`、`groundTruthUsedForDecision = false`、`wouldChangeMainFlow = false` 和 `diagnosticOnly = true`；ground truth 只进入 evaluation signals。
- `koharuArtifactConvergenceReport.referenceReports` 新增 `koharuBubbleAdjacencySeamReport`；convergence 新增 `WI-koharu-bubble-adjacency-seam` 和 `G-koharu-bubble-adjacency-seam-executed`。
- `1_ocr_probe_text.txt` 新增 Bubble adjacency seam summary、pair ledger、seam candidate ledger 和逐块 `bubbleSeamBlockLedger`。
- 报告只做 report-only 诊断；不新增 OCR / LLM，不改变主 OCR、翻译输入、覆盖图、`safeLayoutRect`、DistanceField safe rect、`glyphMaskFillRects`、背景填充、`blockPassed`、失败分类、post-fusion cleanup、候选选择、active artifacts 或 `configuration.currentBlockSource`。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`
- `md/prompt/v1（漫画探针）/v1.37（Koharu气泡邻接切缝影子复刻）.md`

验证计划：

- 本轮 Agent B 本地运行 `swiftc -parse`、`git diff --check`、JSON 解析和 Koharu validator smoke。
- 未跑本机 build / 探针，按规则交给云端验证。
- 云端 `AITRANS CI Results` `ci-fast` 应证明 `koharuBubbleAdjacencySeamReport.enabled = true`、`evaluatedBlockCount == totalBlocksDetected`、`evaluatedBubbleCount == bubbleMaskReport.instanceCount`、`blockLedgerCount == totalBlocksDetected`、`pairLedgerCount >= 1`、`seamCandidateCount >= bubbleSplitCandidateReport.candidateCount`、`gateCount >= 10`，breakdown 非空，`proxyNotRealBubbleMask = true`、`usesRoundedRectProxyMask = true`，convergence 包含 Bubble adjacency seam reference / work item / gate，且 `1_ocr_probe_text.txt` 包含 summary、pair ledger、seam candidate 和逐块 block ledger。

遗留事项：

- 旧仓库根 `output/` 不含 v1.37 新字段；以 PR 后云端结果包为准。
- 本轮未重新跑完整漫画探针，不追加 `metrics/version_history.csv` 漫画指标行。

### v1.36：Koharu DistanceField 安全区影子复刻
日期：2026-07-02
依据：`md/prompt/v1（漫画探针）/v1.36（KoharuDistanceField安全区影子复刻）.md`。本轮修改 Swift 探针报告模型、Koharu convergence 联动、TXT 快照和核心文档；不刷新仓库根 `output/`，不追加 `metrics/version_history.csv`，完整 build / 探针交给 GitHub Actions。

核心变更：

- 新增 `koharuDistanceFieldSafeAreaReport`，只基于 AITRANS 现有 rounded-rect BubbleMask proxy ID mask，在每个 bubble bbox 内计算 two-pass chamfer 8-neighbor distance field、safe pixels、safe pixel bbox 和 histogram maximum safe rect。
- 报告输出 bubble / block / same-bubble sibling 三层 ledger，对比当前 `safeLayoutRect`、v1.35 `koharuBubbleIndexShadowLedgerReport` 的 shadow safe rect、distance-field safe rect、render sprite containment、render lock 和 split / sibling 风险。
- 报告明确 `proxyNotRealBubbleMask = true`、`usesRoundedRectProxyMask = true`、`groundTruthUsedForDecision = false`、`wouldChangeMainFlow = false` 和 `diagnosticOnly = true`；ground truth 只进入 evaluation signals。
- `koharuArtifactConvergenceReport.referenceReports` 新增 `koharuDistanceFieldSafeAreaReport`；convergence 新增 `WI-koharu-distance-field-safe-area` 和 `G-koharu-distance-field-safe-area-executed`。
- `1_ocr_probe_text.txt` 新增 DistanceField summary、safe pixel / safe rect / sprite containment breakdown、bubble ledger、sibling ledger 和逐块 `distanceFieldBlockLedger`。
- 报告只做 report-only 诊断；不新增 OCR / LLM，不改变主 OCR、翻译输入、覆盖图、`safeLayoutRect`、`glyphMaskFillRects`、背景填充、`blockPassed`、失败分类、post-fusion cleanup、候选选择、active artifacts 或 `configuration.currentBlockSource`。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`
- `md/prompt/v1（漫画探针）/v1.36（KoharuDistanceField安全区影子复刻）.md`

验证计划：

- 本轮 Agent B 本地运行 `swiftc -parse`、`git diff --check`、JSON 解析和 Koharu validator smoke。
- 未跑本机 build / 探针，按规则交给云端验证。
- 云端 `AITRANS CI Results` `ci-fast` 应证明 `koharuDistanceFieldSafeAreaReport.enabled = true`、`evaluatedBlockCount == totalBlocksDetected`、`bubbleLedgerCount == bubbleMaskReport.instanceCount`、`blockLedgerCount == totalBlocksDetected`、`gateCount >= 10`，breakdown 非空，`proxyNotRealBubbleMask = true`、`usesRoundedRectProxyMask = true`，convergence 包含 DistanceField reference / work item / gate，且 `1_ocr_probe_text.txt` 包含 summary、bubble ledger、sibling ledger 和逐块 block ledger。

遗留事项：

- 旧仓库根 `output/` 不含 v1.36 新字段；以 PR 后云端结果包为准。
- 本轮未重新跑完整漫画探针，不追加 `metrics/version_history.csv` 漫画指标行。

### v1.35：Koharu BubbleIndex 影子账本与安全区复刻
日期：2026-07-01
依据：`md/prompt/v1（漫画探针）/v1.35（KoharuBubbleIndex影子账本与安全区复刻）.md`。本轮修改 Swift 探针报告模型、Koharu convergence 联动、TXT 快照和核心文档；不刷新仓库根 `output/`，不追加 `metrics/version_history.csv`，完整 build / 探针交给 GitHub Actions。

核心变更：

- 新增 `koharuBubbleIndexShadowLedgerReport`，从现有 BubbleMask proxy、BubbleMask 归属修正、split candidate、reading order、BubbleMask assignment / split scoreboard、render lock、native replay matrix 和最终 blocks 聚合 Koharu BubbleIndex 影子账本。
- 报告输出 block / bubble / same-bubble sibling 三层 ledger，审计当前 `bubbleID`、shadow majority bubble、mask-safe rect 对照、同气泡 sibling 分区、split 风险、render lock、primary bottleneck 和 next action。
- 报告明确 `proxyNotRealBubbleMask = true`，ground truth 只进 evaluation signals，不参与 assignment、safe area、sibling partition、gate 或 next action 决策。
- `koharuArtifactConvergenceReport.referenceReports` 新增 `koharuBubbleIndexShadowLedgerReport`；convergence 新增 `WI-koharu-bubble-index-shadow-ledger` 和 `G-koharu-bubble-index-shadow-ledger-executed`。
- `1_ocr_probe_text.txt` 新增 BubbleIndex summary、assignment / safe-area / sibling breakdown、bubble ledger、sibling ledger 和逐块 `koharuBubbleIndexBlockLedger`。
- 报告只做 report-only 诊断；不新增 OCR / LLM，不改变主 OCR、翻译输入、覆盖图、`safeLayoutRect`、`blockPassed`、失败分类、post-fusion cleanup、候选选择、glyph mask、背景填充、active artifacts 或 `configuration.currentBlockSource`。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`
- `md/prompt/v1（漫画探针）/v1.35（KoharuBubbleIndex影子账本与安全区复刻）.md`

验证计划：

- 本轮 Agent B 本地运行 `swiftc -parse`、`git diff --check`、JSON 解析和 Koharu validator smoke。
- 退回修复：PR #25 云端 run `28523199970` 在 `TranslationSessionStore.swift` 的 `MangaKoharuWorkOrderBlockRoute` 大表达式 type-check 超时；本轮拆分 work order route 与 BubbleIndex block ledger 的 signal / evaluation / mustNotPromote 子表达式，保持 report-only 语义不变。
- 未跑本机 build / 探针，按规则交给云端验证。
- 云端 `AITRANS CI Results` `ci-fast` 应证明 `koharuBubbleIndexShadowLedgerReport.enabled = true`、`evaluatedBlockCount == totalBlocksDetected`、`blockLedgerCount == totalBlocksDetected`、`evaluatedBubbleCount == bubbleMaskReport.instanceCount`、`bubbleLedgerCount == bubbleMaskReport.instanceCount`、`gateCount >= 12`，breakdown 非空，`proxyNotRealBubbleMask = true`，convergence 包含 BubbleIndex reference / work item / gate，且 `1_ocr_probe_text.txt` 包含 summary、bubble ledger、sibling ledger 和逐块 block ledger。

遗留事项：

- 旧仓库根 `output/` 不含 v1.35 新字段；以 PR 后云端结果包为准。
- 本轮未重新跑完整漫画探针，不追加 `metrics/version_history.csv` 漫画指标行。

### v1.34：Koharu 本地算法复刻执行矩阵与探针评估账本
日期：2026-07-01
依据：`md/prompt/v1（漫画探针）/v1.34（Koharu本地算法复刻执行矩阵与探针评估账本）.md`。本轮修改 Swift 探针报告模型、Koharu convergence 联动、TXT 快照和核心文档；不刷新仓库根 `output/`，不追加 `metrics/version_history.csv`，完整 build / 探针交给 GitHub Actions。

核心变更：

- 新增 `koharuNativeAlgorithmReplayMatrixReport`，从 resolver、work order router、external artifact request packet、convergence、TextBox / BubbleMask / SegmentMask scoreboards、translation floor、render lock、diagnostics 和最终 blocks 聚合 Koharu 本地算法复刻执行矩阵。
- 报告固定输出 canonical stage matrix，覆盖 `SourceImage`、`ContentCrop`、`TextBoxes`、`BubbleMask`、`SegmentMask`、`OcrText`、`Translations`、`RenderedSprites`、`FinalRender` 和 `ExternalArtifacts`。
- 报告固定输出 replay candidates，覆盖融合主流程审计、post-fusion / OCR 质量路由、TextBox stoplist、BubbleMask 归属 / 分割、SegmentMask 覆盖、translation model floor、render lock 和 external artifact handoff。
- 每块新增 replay route，记录 primary candidate、primary Koharu stage、bottleneck、external / model floor / render lock / stoplist 状态和 next action。
- `koharuArtifactConvergenceReport.referenceReports` 新增 `koharuNativeAlgorithmReplayMatrixReport`；convergence 新增 `WI-koharu-native-algorithm-replay-matrix` 和 `G-koharu-native-algorithm-replay-matrix-executed`。
- `1_ocr_probe_text.txt` 新增 replay matrix summary、`candidateQueue`、`stageMatrix` 和逐块 `koharuNativeReplayRoute`。
- 报告只做 report-only 诊断；不新增 OCR / LLM，不改变主 OCR、翻译输入、覆盖图、`blockPassed`、失败分类、post-fusion cleanup、候选选择、safe layout、glyph mask、背景填充、active artifacts 或 `configuration.currentBlockSource`。ground truth 只进入 evaluation signals，不参与 candidate status、budget、gate、route 或 next action。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`
- `md/prompt/v1（漫画探针）/v1.34（Koharu本地算法复刻执行矩阵与探针评估账本）.md`

验证计划：

- 本轮 Agent B 本地运行 `swiftc -parse`、`git diff --check`、JSON 解析和 Koharu validator smoke。
- 未跑本机 build / 探针，按规则交给云端验证。
- 云端 `AITRANS CI Results` `ci-fast` 应证明 `koharuNativeAlgorithmReplayMatrixReport.enabled = true`、`evaluatedBlockCount == totalBlocksDetected`、`stageCount >= 10`、`candidateCount >= 9`、`blockRouteCount == totalBlocksDetected`、`gateCount >= 14`，固定 candidate queue 存在，缺 active artifact 时 external candidate blocked，crop / line / deskew stoplist 仍关闭，model floor / OCR / render lock 分开路由，convergence 包含 replay matrix reference / work item / gate，且 `1_ocr_probe_text.txt` 包含 summary、candidate queue、stage matrix 和逐块 route。

遗留事项：

- 旧仓库根 `output/` 不含 v1.34 新字段；以 PR 后云端结果包为准。
- 本轮未重新跑完整漫画探针，不追加 `metrics/version_history.csv` 漫画指标行。

### v1.33：Koharu 外部 Artifact 请求包与准入缺口账本
日期：2026-07-01
依据：`md/prompt/v1（漫画探针）/v1.33（Koharu外部Artifact请求包与准入缺口账本）.md`。本轮修改 Swift 探针报告模型、Koharu convergence 联动、TXT 快照和核心文档；不刷新仓库根 `output/`，不追加 `metrics/version_history.csv`，完整 build / 探针交给 GitHub Actions。

核心变更：

- 新增 `koharuExternalArtifactRequestPacketReport`，从 v1.32 `koharuWorkOrderRouterReport`、external readiness gate、external TextBox shadow OCR、TextBox / BubbleMask / SegmentMask scoreboards、render lock、translation floor、convergence 和最终 blocks 聚合真实外部 artifact 请求包。
- 固定枚举 active `test/koharu_artifacts/` 四件套：`1.manifest.json`、`1.textboxes.json`、`1.bubbles.json`、`1.segment_mask.json`，并为每个 required file 写出 schema 字段、坐标系、解析/契约状态、validator command、blocked reason、next action 和 forbidden sources。
- 新增 `artifactRequirements[]` 覆盖真实 `TextBoxes`、`BubbleMask`、`SegmentMask`，明确当前 proxy 只能作为 why-needed / current limitation 证据，不能冒充 Koharu detector artifact。
- 新增逐块 `blockRequests[]`，每块记录 primary work order、primary bottleneck、needs TextBoxes / BubbleMask / SegmentMask、external readiness、external shadow OCR gate、stoplist、model floor、render lock、manual review、current proxy evidence、missing real artifact reasons、forbidden local actions 和 next action。
- `koharuArtifactConvergenceReport.referenceReports` 新增 `koharuExternalArtifactRequestPacketReport`；convergence 新增 `WI-koharu-external-artifact-request-packet` 和 `G-koharu-external-artifact-request-packet-executed`。
- `1_ocr_probe_text.txt` 新增 request packet summary、`requiredFiles` 摘要、`artifactRequirements` 摘要和逐块 `koharuExternalArtifactRequest` 行。
- 报告只做 report-only 诊断；不创建、复制、修改或提交 active `test/koharu_artifacts/`，不新增 OCR / LLM，不改变主 OCR、翻译输入、覆盖图、`blockPassed`、失败分类、post-fusion cleanup、候选选择、safe layout、glyph mask、背景填充、渲染逻辑或 `configuration.currentBlockSource`。ground truth 只进入 evaluation signals，不参与 request、gate、next action 或 promotion 决策。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`
- `md/prompt/v1（漫画探针）/v1.33（Koharu外部Artifact请求包与准入缺口账本）.md`

验证计划：

- 本轮 Agent B 本地运行 `swiftc -parse`、`git diff --check`、JSON 解析和 Koharu validator smoke。
- 未跑本机 build / 探针，按规则交给云端验证。
- 云端 `AITRANS CI Results` `ci-fast` 应证明 `koharuExternalArtifactRequestPacketReport.enabled = true`、`evaluatedBlockCount == totalBlocksDetected`、`requiredFileCount >= 4`、`artifactRequirementCount >= 3`、`blockRequestCount == totalBlocksDetected`、`gateCount >= 13`，缺 active artifact 时 verdict 为 missing / waiting / blocked 类状态，required files 覆盖四件套，requirements 覆盖 TextBoxes / BubbleMask / SegmentMask，forbidden sources 非空，convergence 包含 request packet reference / work item / gate，且 `1_ocr_probe_text.txt` 包含 request packet summary、required files、artifact requirements 和逐块 request。

遗留事项：

- 旧仓库根 `output/` 不含 v1.33 新字段；以 PR 后云端结果包为准。
- 本轮未重新跑完整漫画探针，不追加 `metrics/version_history.csv` 漫画指标行。

### v1.32：Koharu WorkOrder Router 执行工作单与收益预算
日期：2026-07-01
依据：`md/prompt/v1（漫画探针）/v1.32（KoharuWorkOrderRouter执行工作单与收益预算）.md`。本轮修改 Swift 探针报告模型、Koharu convergence 联动、TXT 快照和核心文档；不刷新仓库根 `output/`，不追加 `metrics/version_history.csv`，完整 build / 探针交给 GitHub Actions。

核心变更：

- 新增 `koharuWorkOrderRouterReport`，从 v1.31 `koharuPipelineResolverReport` 派生固定 work orders、逐块 routes、budget ledger 和 gate ledger。
- 固定 work order 覆盖 resolver ledger 收口、本地 crop / line / deskew stoplist、真实 TextBoxes / BubbleMask / SegmentMask 请求、render lock 保持、translation model floor handoff、external artifact package handoff 和 manual review。
- 逐块 route 输出 primary / secondary work order、primary bottleneck、模型地板、render lock、stoplist、真实 artifact 需求、CI/full/external 预算和下一步动作。
- `koharuArtifactConvergenceReport.referenceReports` 新增 `koharuWorkOrderRouterReport`；convergence 新增 `WI-koharu-workorder-router` 和 `G-koharu-workorder-router-executed`。
- `1_ocr_probe_text.txt` 新增 router report summary、`workOrderQueue` 摘要和逐块 `koharuWorkOrderRoute` 行。
- 报告只做 report-only 诊断；不新增 OCR / LLM、不改变主 OCR、翻译输入、覆盖图、`blockPassed`、失败分类、post-fusion cleanup、候选选择、safe layout、glyph mask、背景填充或 `configuration.currentBlockSource`。ground truth 只进入 evaluation signals，不参与 work order routing、priority、budget 或 next action。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`
- `md/prompt/v1（漫画探针）/v1.32（KoharuWorkOrderRouter执行工作单与收益预算）.md`

验证计划：

- 本轮 Agent B 本地运行 `swiftc -parse`、`git diff --check`、JSON 解析和 Koharu validator smoke。
- 未跑本机 build / 探针，按规则交给云端验证。
- 云端 `AITRANS CI Results` `ci-fast` 应证明 `koharuWorkOrderRouterReport.enabled = true`、`evaluatedBlockCount == totalBlocksDetected`、`workOrderCount >= 7`、`blockRouteCount == totalBlocksDetected`、`gateCount >= 10`，breakdown 非空，缺 active artifact 时 external work orders 保持 blocked/missing，convergence 包含 router reference / work item / gate，且 `1_ocr_probe_text.txt` 包含 router summary、work order queue 和逐块 route。

遗留事项：

- 旧仓库根 `output/` 不含 v1.32 新字段；以 PR 后云端结果包为准。
- 本轮未重新跑完整漫画探针，不追加 `metrics/version_history.csv` 漫画指标行。

### v1.31：Koharu Pipeline Resolver 影子 DAG 阶段调度与阻塞传播
日期：2026-07-01
依据：`md/prompt/v1（漫画探针）/v1.31（KoharuPipelineResolver影子DAG阶段调度与阻塞传播）.md`。本轮修改 Swift 探针报告模型、Koharu convergence 联动、TXT 快照和核心文档；不刷新仓库根 `output/`，不追加 `metrics/version_history.csv`，完整 build / 探针交给 GitHub Actions。

核心变更：

- 新增 `koharuPipelineResolverReport`，用 Koharu `EngineInfo.needs / produces`、DAG resolver 和 Op preview 的结构组织现有 AITRANS 探针证据。
- 报告输出 `nodes[]`、`edges[]`、逐块 `blockTraces[]`、`executionQueue[]`、`opPreviews[]` 和 `gateLedger[]`，覆盖 SourceImage、ContentCrop、Vision OCR、BubbleCandidates、BubbleMask/TextBox/SegmentMask proxy、OcrText、FusionCleanup、Translations、GlyphErase proxy、RenderedSprites proxy、FinalRender 和 ExternalArtifacts。
- 逐块 trace 输出 `firstBlockedNodeID`、`firstBlockedReason`、downstream blocked nodes、recommended execution item、next action、requires external artifact 和 stoplisted local tuning 状态。
- `koharuArtifactConvergenceReport.referenceReports` 新增 `koharuPipelineResolverReport`；convergence 新增 `WI-koharu-pipeline-resolver-shadow-dag` 和 `G-koharu-pipeline-resolver-executed`。
- `1_ocr_probe_text.txt` 新增 resolver report summary、`resolverExecutionQueue` 摘要和逐块 `koharuPipelineResolverTrace` 行。
- 报告只做 report-only 诊断；不新增 OCR / LLM、不改变主 OCR、翻译输入、覆盖图、`blockPassed`、失败分类、post-fusion cleanup、候选选择、safe layout、glyph mask、背景填充或 `configuration.currentBlockSource`。ground truth 只进入 evaluation signals，不参与 resolver 决策。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`
- `md/prompt/v1（漫画探针）/v1.31（KoharuPipelineResolver影子DAG阶段调度与阻塞传播）.md`

验证计划：

- 本轮 Agent B 本地运行 `swiftc -parse`、`git diff --check`、JSON 解析和 Koharu validator smoke。
- 未跑本机 build / 探针，按规则交给云端验证。
- 云端 `AITRANS CI Results` `ci-fast` 应证明 `koharuPipelineResolverReport.enabled = true`、`evaluatedBlockCount == totalBlocksDetected`、`nodeCount >= 12`、`edgeCount >= 12`、`blockTraceCount == totalBlocksDetected`、`executionQueueCount >= 6`、`opPreviewCount >= 4`、`gateCount >= 8`，breakdown 非空，`externalArtifacts` 缺 active artifact 时保持 blocked/missing，convergence 包含 resolver reference / work item / gate，且 `1_ocr_probe_text.txt` 包含 resolver summary、execution queue 和逐块 trace。

遗留事项：

- 旧仓库根 `output/` 不含 v1.31 新字段；以 PR 后云端结果包为准。
- 本轮未重新跑完整漫画探针，不追加 `metrics/version_history.csv` 漫画指标行。

### v1.30：Koharu Render Regression Lock 覆盖渲染回归锁与 FinalRender 账本
日期：2026-07-01
依据：`md/prompt/v1（漫画探针）/v1.30（KoharuRenderRegressionLock覆盖渲染回归锁与FinalRender账本）.md`。本轮修改 Swift 探针报告模型、Koharu convergence 联动、TXT 快照和核心文档；不刷新仓库根 `output/`，不追加 `metrics/version_history.csv`，完整 build / 探针交给 GitHub Actions。

核心变更：

- 新增 `koharuRenderRegressionLockReport`，执行 v1.28 未闭合的 `WI-render-regression-lock`。
- 报告聚合现有 final blocks、`safeLayoutRect`、mask-safe rect、render collision、render mask overflow、glyph mask、background fill、失败块 fallback 覆盖文本和 App 沙盒输出文件状态，输出 RenderedSprites / FinalRender 回归锁。
- 顶层输出 `renderLockVerdict`、render / safe layout / background fill / glyph mask / failure overlay / output file breakdown、核心输出文件状态、逐块 `blockLocks[]`、`artifactStages[]`、`outputFileChecks[]` 和 `gateLedger[]`。
- `koharuArtifactConvergenceReport.referenceReports` 新增 `koharuRenderRegressionLockReport`；`WI-render-regression-lock` 可从 v1.28 的未执行 open 状态推进为 `closedReportOnly` 或 `openRenderIssueDetected`，并同步 `G-render-regression-lock-executed` gate。
- `1_ocr_probe_text.txt` 新增报告级 render lock summary、render issue / output file 摘要、convergence render work item 摘要和逐块 `renderLock` 行。
- 报告只做 report-only 诊断；不重新渲染、不解析 PNG 像素证明逐块文字、不新增 OCR / LLM、不改变主 OCR、主翻译、覆盖图、`blockPassed`、失败分类、post-fusion cleanup、候选选择、`safeLayoutRect`、`glyphMaskFillRects`、背景填充行为、渲染逻辑或 `configuration.currentBlockSource`。`proxyNotRealKoharuRenderer = true` 表示 AITRANS 当前不是 Koharu 真实 renderer、RenderedSprites artifact 或 inpainting。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`
- `md/prompt/v1（漫画探针）/v1.30（KoharuRenderRegressionLock覆盖渲染回归锁与FinalRender账本）.md`

验证计划：

- 本轮 Agent B 本地运行 `swiftc -parse`、`git diff --check`、JSON 解析和 Koharu validator smoke。
- 未跑本机 build / 探针，按规则交给云端验证。
- 云端 `AITRANS CI Results` `ci-fast` 应证明 `koharuRenderRegressionLockReport.enabled = true`、`evaluatedBlockCount == totalBlocksDetected`、`blockLocks.count == totalBlocksDetected`、`artifactStages.count >= 5`、`gateLedger.count >= 13`、`outputFileChecks` 覆盖核心 JSON/TXT/PNG，`failureOverlayRequiredBlocks` 覆盖所有失败块，`koharuArtifactConvergenceReport.referenceReports` 包含新 report，`WI-render-regression-lock` 不再只是 v1.28 未执行 open 状态，且 `1_ocr_probe_text.txt` 包含新 summary、逐块 `renderLock` 和 convergence render work item 摘要。

遗留事项：

- 旧仓库根 `output/` 不含 v1.30 新字段；以 PR 后云端结果包为准。
- 本轮未重新跑完整漫画探针，不追加 `metrics/version_history.csv` 漫画指标行。

### v1.29：Translation Model Floor 对照矩阵与 Koharu 翻译地板账本
日期：2026-07-01
依据：`md/prompt/v1（漫画探针）/v1.29（TranslationModelFloor对照矩阵与Koharu翻译地板账本）.md`。本轮修改 Swift 探针报告模型、deterministic clean text strict prompt 诊断、Koharu convergence work item 联动、TXT 快照和核心文档；不刷新仓库根 `output/`，不追加 `metrics/version_history.csv`，完整 build / 探针交给 GitHub Actions。

核心变更：

- 新增 `translationModelFloorComparisonReport`，执行 v1.28 未闭合的 `WI-translation-model-floor-comparison`。
- 报告复用 `cleanTextDiagnostic` 的 dialogue baseline cases，额外运行 deterministic `strictChineseOnlyV1` prompt 变体，记录 baseline / variant prompt、raw output、candidate、raw / candidate classification、failure reasons、pass state 和 prompt variant outcome。
- 报告聚合 noisy final blocks、v1.19 `routingDrivenTranslationComparisonReport`、`batchTranslationComparison` 和 `koharuArtifactConvergenceReport` work item，输出 `floorVerdict`、clean/noisy 计数、prompt outcome breakdown、failure reason breakdown 和 gate ledger。
- `koharuArtifactConvergenceReport.referenceReports` 新增 `translationModelFloorComparisonReport`，`WI-translation-model-floor-comparison` 可从 v1.28 的未执行 open 状态推进为 `closedReportOnly` 或 `openModelFloorConfirmed`；这只表示对照账本已执行，不表示模型质量问题已解决。
- `1_ocr_probe_text.txt` 新增报告级 `translationModelFloorComparisonReport` summary、逐条 `translationFloorCleanCase` 和逐块 `translationFloorNoisyBlock` 摘要。
- 报告只做 report-only 诊断；clean text ground truth 只用于模型地板评估，不参与 noisy OCR 候选选择、主 prompt、主译文、覆盖图、`blockPassed`、失败分类、质量规则、模型选择或 metrics history。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`
- `md/prompt/v1（漫画探针）/v1.29（TranslationModelFloor对照矩阵与Koharu翻译地板账本）.md`

验证计划：

- 本轮 Agent B 本地运行 `swiftc -parse`、`git diff --check`、JSON 解析和 Koharu validator smoke。
- 未跑本机 build / 探针，按规则交给云端验证。
- 云端 `AITRANS CI Results` `ci-fast` 应证明 `translationModelFloorComparisonReport.enabled = true`、`evaluatedCleanCaseCount == cleanTextDiagnostic.totalCases`、`evaluatedNoisyBlockCount == totalBlocksDetected`、`baselinePassRate == cleanTextDiagnostic.passRate`、`floorVerdict` 和 breakdown 非空、`gateLedger.count >= 9`、`koharuArtifactConvergenceReport.referenceReports` 包含新 report、`WI-translation-model-floor-comparison` 不再只是 v1.28 未执行 open 状态，且 `1_ocr_probe_text.txt` 包含新 summary、clean case 摘要和逐块 noisy block 摘要。

遗留事项：

- 旧仓库根 `output/` 不含 v1.29 新字段；以 PR 后云端结果包为准。
- 本轮未重新跑完整漫画探针，不追加 `metrics/version_history.csv` 漫画指标行。

### v1.28：Koharu Artifact 收敛矩阵与下一步决策账本
日期：2026-07-01
依据：`md/prompt/v1（漫画探针）/v1.28（KoharuArtifact收敛矩阵与下一步决策账本）.md`。本轮修改 Swift 探针报告模型、诊断 TXT 和核心文档；不刷新仓库根 `output/`，不追加 `metrics/version_history.csv`，完整 build / 探针交给 GitHub Actions。

核心变更：

- 新增 `koharuArtifactConvergenceReport`，聚合 v1.22 `koharuArtifactDAGReport`、v1.23 `koharuStageGapReplicationReport`、v1.24 `koharuNativeReplicationScoreboardReport`、v1.25 `nativeTextBoxProxyLedgerReport`、v1.26 `bubbleMaskAssignmentSplitScoreboardReport`、v1.27 `segmentMaskProxyCoverageScoreboardReport`、external artifact readiness、clean text diagnostic、diagnostics 和最终 blocks。
- 报告顶层输出 `source = AITRANSProbe`、`referencePipeline = Koharu`、`groundTruthUsedForDecision = false`、`groundTruthUsedForEvaluationOnly = true`、`wouldChangeMainFlow = false`、`diagnosticOnly = true` 和 `externalArtifactsRequiredForThisReport = false`。
- `stages[]` 输出 SourceImage、ContentCrop、TextBoxes、BubbleMask、SegmentMask、OcrText、Translations、Inpainted、RenderedSprites、FinalRender 和 ExternalArtifacts 的 convergence matrix。
- `blockPaths[]` 为每个最终块输出 TextBox / BubbleMask / SegmentMask / OCR / translation / render 状态、`firstBlockingArtifact`、`primaryStructuralBottleneck`、model floor、render lock、real artifact 需求和下一步 action。
- `workItemLedger[]` 固定收束 `WI-native-textbox-artifact-scorecard`、`WI-bubblemask-assignment-split-scorecard`、`WI-segmentmask-proxy-coverage-scorecard`，并把未闭合项集中到 `WI-translation-model-floor-comparison`、`WI-render-regression-lock` 和 `WI-external-artifact-optional-handoff`。
- `gateLedger[]` 固定包含 no-main-flow-mutation、no-ground-truth-decision、v1.25 / v1.26 / v1.27 work item closure、translation model floor open、render regression lock open、external artifact optional、proxy boundary 和 ci-fast report availability。
- `1_ocr_probe_text.txt` 新增报告级 `koharuArtifactConvergenceReport` summary 和逐块 `koharuArtifactPath` 摘要。
- 报告只复用既有探针证据，不新增 OCR / LLM 调用；不改变主 OCR、翻译输入、覆盖图、`blockPassed`、失败分类、post-fusion cleanup、候选选择、`safeLayoutRect`、`glyphMaskFillRects`、背景填充行为、渲染逻辑或 `configuration.currentBlockSource`。ground truth 只进入 evaluationSignals，不参与 firstBlockingArtifact、primaryNextAction、work item status 或 gate。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`
- `md/prompt/v1（漫画探针）/v1.28（KoharuArtifact收敛矩阵与下一步决策账本）.md`

验证计划：

- 本轮 Agent B 本地运行 `swiftc -parse`、`git diff --check`、JSON 解析和 Koharu validator smoke。
- 未跑本机 build / 探针，按规则交给云端验证。
- 云端 `AITRANS CI Results` `ci-fast` 应证明 `koharuArtifactConvergenceReport.enabled = true`、`evaluatedBlockCount == totalBlocksDetected`、`stageCount >= 9`、`blockPathCount == totalBlocksDetected`、`workItemLedgerCount >= 6`、`gateCount >= 10`，关键 breakdown 非空，前三个 proxy work item 在 `closedWorkItems` 中，open work items 至少包含 translation model floor、render regression lock 或 external optional handoff，且 `1_ocr_probe_text.txt` 包含新 summary 和逐块 `koharuArtifactPath`。

遗留事项：

- 旧仓库根 `output/` 不含 v1.28 新字段；以 PR 后云端结果包为准。
- 本轮未重新跑完整漫画探针，不追加 `metrics/version_history.csv` 漫画指标行。

### v1.27：SegmentMask Proxy 覆盖评分板与 Glyph 清字边界账本
日期：2026-07-01
依据：`md/prompt/v1（漫画探针）/v1.27（SegmentMaskProxy覆盖评分板与Glyph清字边界账本）.md`。本轮修改 Swift 探针报告模型、诊断 TXT 和核心文档；不刷新仓库根 `output/`，不追加 `metrics/version_history.csv`，完整 build / 探针交给 GitHub Actions。

核心变更：

- 新增 `segmentMaskProxyCoverageScoreboardReport`，执行 v1.24 的 `WI-segmentmask-proxy-coverage-scorecard`，聚合现有 glyph mask、SegmentMask proxy、TextBox 覆盖、BubbleMask 覆盖、safe rect、背景填充和渲染碰撞证据。
- 报告顶层输出 `source = AITRANSProbe`、`referenceWorkItemID = WI-segmentmask-proxy-coverage-scorecard`、`referenceKoharuArtifact = SegmentMask`、`groundTruthUsedForDecision = false`、`groundTruthUsedForEvaluationOnly = true`、`wouldChangeMainFlow = false`、`diagnosticOnly = true` 和 `proxyNotRealSegmentMask = true`。
- `blockScorecards[]` 为每个最终块输出 coverage status、cleanup status、render mask status、glyph / TextBox / BubbleMask / safe rect 覆盖、background fill、render collision、TextBox / BubbleMask ledger 状态、must-not-promote reasons 和 nextAction。
- `cleanupLedgers[]` 采用每个最终块一条的稳定计数规则，记录 glyph 清字边界、background fill guardrail、allowed cleanup use、blocked cleanup reasons、`inpaintingImplemented = false` 和 `proxyOnly = true`。
- `gateLedger[]` 固定包含 no-main-flow-mutation、no-ground-truth-decision、proxy boundary、glyph available、TextBox / BubbleMask / safe rect coverage、background fill guardrail、render mask collision、TextBox ledger boundary、BubbleMask boundary 和 real SegmentMask artifact boundary。
- `1_ocr_probe_text.txt` 新增报告级 `segmentMaskProxyCoverageScoreboardReport` summary 和逐块 `segmentMaskProxyScoreboard` 摘要。
- 报告只复用既有探针证据，不新增 OCR / LLM 调用；不改变主 OCR、翻译输入、覆盖图、`blockPassed`、失败分类、post-fusion cleanup、候选选择、`safeLayoutRect`、`glyphMaskFillRects`、背景填充行为、`textRegionCropReport.adoptedCount` 或 `configuration.currentBlockSource`。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`
- `md/prompt/v1（漫画探针）/v1.27（SegmentMaskProxy覆盖评分板与Glyph清字边界账本）.md`

验证计划：

- 本轮 Agent B 本地运行 `swiftc -parse`、`git diff --check`、JSON 解析和 Koharu validator smoke。
- 未跑本机 build / 探针，按规则交给云端验证。
- 云端 `AITRANS CI Results` `ci-fast` 应证明 `segmentMaskProxyCoverageScoreboardReport.enabled = true`、`evaluatedBlockCount == totalBlocksDetected`、`glyphMaskBlockCount == segmentMaskReport.glyphMaskBlocks`、`blockScorecards.count == totalBlocksDetected`、`cleanupLedgerCount >= glyphMaskBlockCount`、`gateLedger.count >= 12`，关键 breakdown 非空，`proxyNotRealSegmentMask = true`，且 `1_ocr_probe_text.txt` 包含新 summary 和逐块 `segmentMaskProxyScoreboard`。

遗留事项：

- 旧仓库根 `output/` 不含 v1.27 新字段；以 PR 后云端结果包为准。
- 本轮未重新跑完整漫画探针，不追加 `metrics/version_history.csv` 漫画指标行。

### v1.26：BubbleMask 归属分割评分板与 Sibling 布局账本
日期：2026-07-01
依据：`md/prompt/v1（漫画探针）/v1.26（BubbleMask归属分割评分板与Sibling布局账本）.md`。本轮修改 Swift 探针报告模型、诊断 TXT 和核心文档；不刷新仓库根 `output/`，不追加 `metrics/version_history.csv`，完整 build / 探针交给 GitHub Actions。

核心变更：

- 新增 `bubbleMaskAssignmentSplitScoreboardReport`，执行 v1.24 的 `WI-bubblemask-assignment-split-scorecard`，聚合现有 BubbleMask proxy、归属修正、split candidate、reading order、structure action、Koharu native scoreboard 和 Native TextBox ledger 证据。
- 报告顶层输出 `source = AITRANSProbe`、`referenceWorkItemID = WI-bubblemask-assignment-split-scorecard`、`referenceKoharuArtifact = BubbleMask`、`groundTruthUsedForDecision = false`、`groundTruthUsedForEvaluationOnly = true`、`wouldChangeMainFlow = false` 和 `diagnosticOnly = true`。
- `blockScorecards[]` 为每个最终块输出 assignment status、split risk、same-bubble sibling layout、mask safe rect、render mask status、TextBox ledger status、decision / evaluation signals、must-not-promote reasons 和 nextAction。
- `bubbleScorecards[]` 为每个 BubbleMask proxy 实例输出 blocks、冲突块、归属修正块、split candidate、same-bubble sibling groups、render overflow、instance status 和 primary risk。
- `splitCandidateLedgers[]` 和 `siblingLayoutScorecards[]` 把既有 split candidate 与同气泡 sibling 布局整理成 report-only 账本，不扩大 crop clamp，不改 `safeLayoutRect`。
- `gateLedger[]` 固定包含 no-main-flow-mutation、no-ground-truth-decision、assignment consistency、correction report-only、split report-only、sibling layout、render mask collision、protected text、TextBox ledger boundary 和 real artifact boundary。
- `1_ocr_probe_text.txt` 新增报告级 `bubbleMaskAssignmentSplitScoreboardReport` summary 和逐块 `bubbleMaskScoreboard` 摘要。
- 报告只复用既有探针证据，不新增 OCR / LLM 调用；不改变主 OCR、翻译输入、覆盖图、`blockPassed`、失败分类、post-fusion cleanup、候选选择、`safeLayoutRect` 或 `configuration.currentBlockSource`。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`
- `md/prompt/v1（漫画探针）/v1.26（BubbleMask归属分割评分板与Sibling布局账本）.md`

验证计划：

- 本轮 Agent B 本地运行 `swiftc -parse`、`git diff --check`、JSON 解析和 Koharu validator smoke。
- 退回修复：云端 run `28489045515` 在 `TranslationSessionStore.swift` 触发 Swift 编译失败，原因是 v1.26 scoreboard helper 对 `Bool` 字段 `bubbleIDConsistent` 调用了 `map`；已改为对可选 mask 本身转换为 `"true"` / `"false"` / `"nil"`，不改变报告语义或主流程。
- 未跑本机 build / 探针，按规则交给云端验证。
- 云端 `AITRANS CI Results` `ci-fast` 应证明 `bubbleMaskAssignmentSplitScoreboardReport.enabled = true`、`evaluatedBlockCount == totalBlocksDetected`、`evaluatedBubbleCount == bubbleMaskReport.instanceCount`、`blockScorecards.count == totalBlocksDetected`、`bubbleScorecards.count == bubbleMaskReport.instanceCount`、`splitCandidateLedgers.count == bubbleSplitCandidateReport.candidateCount`、`gateLedger.count >= 10`，关键 breakdown 非空，且 `1_ocr_probe_text.txt` 包含新 summary 和逐块 `bubbleMaskScoreboard`。

遗留事项：

- 旧仓库根 `output/` 不含 v1.26 新字段；以 PR 后云端结果包为准。
- 本轮未重新跑完整漫画探针，不追加 `metrics/version_history.csv` 漫画指标行。

### v1.25：Native TextBox Proxy 质量账本与候选冻结
日期：2026-06-30
依据：`md/prompt/v1（漫画探针）/v1.25（NativeTextBoxProxy质量账本与候选冻结）.md`。本轮修改 Swift 探针报告模型、诊断 TXT 和核心文档；不刷新仓库根 `output/`，不追加 `metrics/version_history.csv`，完整 build / 探针交给 GitHub Actions。

核心变更：

- 新增 `nativeTextBoxProxyLedgerReport`，执行 v1.24 的 `WI-native-textbox-artifact-scorecard`，聚合现有 TextBox / crop / line / BubbleMask / SegmentMask / OCR damage / v1.24 scoreboard 证据。
- 报告顶层输出 `source = AITRANSProbe`、`referenceWorkItemID = WI-native-textbox-artifact-scorecard`、`groundTruthUsedForDecision = false`、`groundTruthUsedForEvaluationOnly = true`、`wouldChangeMainFlow = false` 和 `diagnosticOnly = true`。
- `blockLedgers[]` 为每个最终块输出 qualityStatus、candidateSources、word preservation、protected keyword、bubble / segment / OCR damage / translation model / render gate、stoplist 命中、mustNotPromoteReasons 和 nextAction。
- `candidateLedgers[]` 汇总 fused seed bbox、TextRegion crop control、pre-crop TextBox plan、crop experiment shadow、line TextBox plan、line crop shadow 等既有候选证据；候选只做 report-only 账本，不写回主流程。
- `gateLedger[]` 固定包含 no-main-flow-mutation、no-ground-truth-decision、word preservation、protected keywords、stoplist freeze、bubble containment、segment support、OCR damage、model floor 和 render stability。
- `stoplist[]` 冻结已证伪的 crop / line / deskew 本地试参，过期条件只能是未来证据条件，不通过降低阈值解冻。
- `1_ocr_probe_text.txt` 新增报告级 `nativeTextBoxProxyLedgerReport` summary 和逐块 `nativeTextBoxProxyLedger` 摘要。
- 报告只复用既有探针证据，不新增 OCR / LLM 调用；不改变主 OCR、翻译输入、覆盖图、`blockPassed`、失败分类、post-fusion cleanup、候选选择或 `configuration.currentBlockSource`。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`
- `md/prompt/v1（漫画探针）/v1.25（NativeTextBoxProxy质量账本与候选冻结）.md`

验证计划：

- 本轮 Agent B 本地运行 `swiftc -parse`、`git diff --check`、JSON 解析和 Koharu validator smoke。
- 退回修复：云端 run `28452180814` 在 `TranslationSessionStore.swift` 触发 Swift 编译失败，原因是 v1.25 ledger helper 误读不存在的 `MangaOverlayTextRegionCropDiagnostic.candidatePreservesRawWords` 字段；已改为使用现有 `rawWordPreservationRatio >= 0.72` 推导，并移除同 helper 未使用的 BubbleMask 字典，不改变报告语义或主流程。
- 退回修复：云端 run `28453929047` 在 `makeNativeTextBoxProxyLedgerReport` 的 `blockLedgers` 大闭包触发 Swift 类型检查超时；已拆为显式 helper / 子表达式并改用显式循环生成 block ledger，同时清理 v1.24 scoreboard helper 未使用的 `mask` 变量，不改变报告语义或主流程。
- 未跑本机 build / 探针，按规则交给云端验证。
- 云端 `AITRANS CI Results` `ci-fast` 应证明 `nativeTextBoxProxyLedgerReport.enabled = true`、`evaluatedBlockCount == totalBlocksDetected`、`blockLedgers.count == totalBlocksDetected`、`gateLedger.count >= 10`，关键 breakdown 非空，stoplist 覆盖既有 crop / line stop blocks，且 `1_ocr_probe_text.txt` 包含新 summary 和逐块 `nativeTextBoxProxyLedger`。

遗留事项：

- 旧仓库根 `output/` 不含 v1.25 新字段；以 PR 后云端结果包为准。
- 本轮未重新跑完整漫画探针，不追加 `metrics/version_history.csv` 漫画指标行。

### v1.24：Koharu 本地复刻 Scoreboard 与 Gate Ledger
日期：2026-06-30
依据：`md/prompt/v1（漫画探针）/v1.24（Koharu本地复刻Scoreboard与GateLedger）.md`。本轮修改 Swift 探针报告模型、诊断 TXT 和核心文档；不刷新仓库根 `output/`，不追加 `metrics/version_history.csv`，完整 build / 探针交给 GitHub Actions。

核心变更：

- 新增 `koharuNativeReplicationScoreboardReport`，只用 AITRANS 自己的 probe 输出，把 v1.23 stage gap / work package 转成 stage scorecard、gate ledger、block scorecard 和下一轮 work items。
- 报告顶层输出 `source = AITRANSProbe`、`referencePipeline = Koharu`、`externalArtifactsRequiredForThisReport = false`、`groundTruthUsedForDecision = false` 和 `groundTruthUsedForEvaluationOnly = true`。
- `stageScorecards[]` 覆盖 `sourceImage`、`contentCrop`、`nativeTextBoxes`、`nativeBubbleMask`、`nativeSegmentMask`、`ocrText`、`translations`、`glyphEraseOrInpaintProxy`、`renderedSprites` 和 `finalRender`，区分 native / proxy / shadow / stop / model-limited / render-stable 状态。
- `gateLedger[]` 新增 no-main-flow-mutation、no-ground-truth-decision、native TextBox word preservation / stoplist、bubble conflict、SegmentMask inside bubble、clean text model floor、failure overlay、render no-overflow 和 external artifact optional 等 gate。
- `blockScorecards[]` 为每个最终块输出 OCR / bubble / segment / translation / render gate 状态、stoplist 证据、推荐 work item 和 next action；priority 和 nextAction 不读取 ground truth。
- `recommendedNextWorkItems[]` 明确把已证伪的 crop / line / deskew 本地试参加入 stoplist，下一步转向 native TextBox / BubbleMask / SegmentMask 评分、translation model floor 对照和 render regression lock。
- `1_ocr_probe_text.txt` 新增报告级 `koharuNativeReplicationScoreboardReport` summary 和逐块 `koharuNativeBlockScorecard` 摘要。
- 缺真实 `test/koharu_artifacts/` 只记为 `externalOptionalMissing` 可选外部路径，不阻塞 native scoreboard；但仍不能把 Vision OCR、pre-crop plan、line plan、BubbleMask proxy 或 SegmentMask proxy 冒充成真实 Koharu artifact。
- 报告只复用既有探针证据，不新增 OCR / LLM 调用；不改变主 OCR、翻译输入、覆盖图、`blockPassed`、失败分类、post-fusion cleanup、候选选择或 `configuration.currentBlockSource`。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`
- `md/prompt/v1（漫画探针）/v1.24（Koharu本地复刻Scoreboard与GateLedger）.md`

验证计划：

- 本轮 Agent B 本地运行 `swiftc -parse`、`git diff --check`、JSON 解析和 Koharu validator smoke。
- 未跑本机 build / 探针，按规则交给云端验证。
- 云端 `AITRANS CI Results` `ci-fast` 应证明 `koharuNativeReplicationScoreboardReport.enabled = true`、`evaluatedBlockCount == totalBlocksDetected`、`stageScorecardCount >= 9`、`gateCount >= 8`、`workItemCount >= 1`，关键 breakdown 非空，`externalArtifactsRequiredForThisReport = false`、`groundTruthUsedForDecision = false`、`groundTruthUsedForEvaluationOnly = true`，每个 `stageScorecards[]` / `gateLedger[]` 的决策字段不使用 ground truth，且 `1_ocr_probe_text.txt` 包含新 summary 和逐块 `koharuNativeBlockScorecard`。

遗留事项：

- 旧仓库根 `output/` 不含 v1.24 新字段；以 PR 后云端结果包为准。
- 本轮未重新跑完整漫画探针，不追加 `metrics/version_history.csv` 漫画指标行。

### v1.23：Koharu 阶段差距复刻计划与晋级门槛
日期：2026-06-30
依据：`md/prompt/v1（漫画探针）/v1.23（Koharu阶段差距复刻计划与晋级门槛）.md`。本轮修改 Swift 探针报告模型、诊断 TXT 和核心文档；不刷新仓库根 `output/`，不追加 `metrics/version_history.csv`，完整 build / 探针交给 GitHub Actions。

核心变更：

- 新增 `koharuStageGapReplicationReport`，把 v1.22 `koharuArtifactDAGReport` 转成 Koharu canonical stage 差距、work package、promotion gate 和逐块复刻计划。
- 报告覆盖 `sourceImage`、`contentCrop`、`textBoxes`、`bubbleMask`、`segmentMask`、`ocrText`、`translations`、`cleanTextDiagnostic`、`inpaintOrGlyphErase`、`renderedSprites` 和 `finalRender`。
- 每个 stage gap 写出当前 AITRANS 能力、artifact kind、source reports、gap category、replication readiness、最小输入、现有/缺失证据、受影响块、promotion gates、stop conditions 和推荐 work package。
- 每个 work package 写出优先级、目标阶段/块、是否可在 `ci-fast` 验证、是否需要 full probe、是否必须真实 external artifact、预期指标移动、rollback / stop 条件和非目标。
- 每个 block 输出 `firstBlockingStageFromDAG`、`primaryGapCategory`、目标 canonical stage、推荐 work package、最小证据、禁止晋级原因、是否需要 full / real artifact 和下一步动作。
- `1_ocr_probe_text.txt` 新增报告级 `koharuStageGapReplicationReport` summary 和逐块 `koharuStageGapPlan` 摘要。
- 报告只复用既有探针证据，不新增 OCR / LLM 调用；不改变主 OCR、翻译输入、覆盖图、`blockPassed`、失败分类、post-fusion cleanup、候选选择或 `configuration.currentBlockSource`。
- 缺真实 active `test/koharu_artifacts/` 时，真实 TextBoxes / BubbleMask / SegmentMask 仍保持 `manifestMissing` / `stopUntilArtifactsProvided` 阻塞，不能把 Vision OCR、pre-crop plan、line plan、BubbleMask proxy 或 SegmentMask proxy 冒充成 Koharu artifact。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`
- `md/prompt/v1（漫画探针）/v1.23（Koharu阶段差距复刻计划与晋级门槛）.md`

验证计划：

- 本轮 Agent B 本地运行 `swiftc -parse`、`git diff --check`、JSON 解析和 Koharu validator smoke。
- 未跑本机 build / 探针，按规则交给云端验证。
- 云端 `AITRANS CI Results` `ci-fast` 应证明 `koharuStageGapReplicationReport.enabled = true`、`evaluatedBlockCount == totalBlocksDetected`、`canonicalStageCount >= 9`、`workPackageCount >= 1`，关键 breakdown 非空，`stageGaps[].diagnosticOnly = true`、`stageGaps[].groundTruthUsedForPlanning = false`、`stageGaps[].wouldChangeMainFlow = false`，每个 promotion gate 的 `groundTruthUsedForDecision = false`，且 `1_ocr_probe_text.txt` 包含新 summary 和逐块 `koharuStageGapPlan`。

遗留事项：

- 旧仓库根 `output/` 不含 v1.23 新字段；以 PR 后云端结果包为准。
- 本轮未重新跑完整漫画探针，不追加 `metrics/version_history.csv` 漫画指标行。

### v1.22：Koharu 式 Artifact DAG 阶段账本与瓶颈闭环
日期：2026-06-30
依据：`md/prompt/v1（漫画探针）/v1.22（Koharu式ArtifactDAG阶段账本与瓶颈闭环）.md`。本轮修改 Swift 探针报告模型、诊断 TXT 和核心文档；不刷新仓库根 `output/`，不追加 `metrics/version_history.csv`，完整 build / 探针交给 GitHub Actions。

核心变更：

- 新增 `koharuArtifactDAGReport`，把 SourceImage、ContentCrop、Vision OCR、BubbleMask、TextBoxes、SegmentMask、OCR text、shadow crop、external artifact gate、translation、render layout 和 v1.21 结构动作候选组织成 Koharu 式 Artifact DAG 阶段账本。
- 报告级输出 dependency edges、stage summaries、stage status / artifact kind / first blocking stage / downstream impact breakdown，以及真实 artifact gate verdict / next action。
- 每块输出 `blockTraces[]`，包含 `firstBlockingStage`、`firstBlockingReason`、`downstreamImpacts`、关键 `stageTraces`、v1.21 候选 verdict 和 `recommendedNextAction`。
- 缺真实 active `test/koharu_artifacts/` 时，只把需要真实 TextBoxes / BubbleMask / SegmentMask 的 promotion 标为 `missingRequiredArtifact`，不把当前主流程整体判废。
- `1_ocr_probe_text.txt` 新增报告级 `koharuArtifactDAGReport` summary 和逐块 `koharuArtifactTrace` 摘要，便于不打开巨大 JSON 时定位首次阻塞阶段。
- 该报告只复用既有探针证据，不新增 OCR / LLM 调用；不改变主 OCR、翻译输入、覆盖图、`blockPassed`、失败分类、post-fusion cleanup 或候选选择。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`
- `md/prompt/v1（漫画探针）/v1.22（Koharu式ArtifactDAG阶段账本与瓶颈闭环）.md`

验证计划：

- 本轮 Agent B 本地运行 `swiftc -parse`、`git diff --check`、JSON 解析和 Koharu validator smoke。
- 退回修复：云端 run `28433914248` 在 `TranslationSessionStore.swift` 的 v1.22 DAG 报告构建处触发 Swift 6 编译失败；已改为显式 optional Bool 字符串转换、显式 closure 和多步局部统计，降低 type-check 压力，不改变报告语义或主流程。
- 未跑本机 build / 探针，按规则交给云端验证。
- 云端 `AITRANS CI Results` `ci-fast` 应证明 `koharuArtifactDAGReport.enabled = true`、`evaluatedBlockCount == totalBlocksDetected`、`stageCount >= 8`、`edgeCount >= 8`，关键 breakdown 非空，每条 dependency edge 的 `diagnosticOnly = true`、`wouldChangeMainFlow = false`，且 `1_ocr_probe_text.txt` 包含新 summary 和逐块 `koharuArtifactTrace`。

遗留事项：

- 旧仓库根 `output/` 不含 v1.22 新字段；以 PR 后云端结果包为准。
- 本轮未重新跑完整漫画探针，不追加 `metrics/version_history.csv` 漫画指标行。

### v1.21：结构动作候选矩阵与 Shadow 执行评估
日期：2026-06-30
依据：`md/prompt/v1（漫画探针）/v1.21（结构动作候选矩阵与Shadow执行评估）.md`。本轮修改 Swift 探针报告模型、诊断 TXT 和核心文档；不刷新仓库根 `output/`，不追加 `metrics/version_history.csv`，完整 build / 探针交给 GitHub Actions。

核心变更：

- 新增 `structureActionCandidateReport`，把 v1.20 `readingOrderStructureAuditReport` 的结构建议转成 shadow-only 候选矩阵。
- 候选类型覆盖 `readingOrderReindex`、`bubbleAssignmentReview`、`bubbleSplitShadow`、`sameBubbleSiblingLayout`、`duplicateFragmentProtection`、`textBoxEvidenceRequired`、`segmentMaskEvidenceRequired`、`renderSafeAreaReflow` 和 `manualReviewOnly`。
- 每个候选写出 `plannedOperation`、`expectedBenefit`、`executionMode`、control/shadow metrics、delta、`promotionVerdict`、`promotionBlockers` 和 `recommendedNextStep`。
- 报告级汇总 candidate type、promotion verdict、next step、report-only would improve、blocked、needs real artifact、render reflow、bubble split / assignment、duplicate protection 和 manual review blocks。
- `1_ocr_probe_text.txt` 新增报告级 `structureActionCandidateReport` summary 和每块 `structureActionCandidates` 摘要，包含跳过原因和 delta summary。
- 报告只复用已有几何、渲染和 shadow OCR 摘要，不新增 OCR / LLM 调用；不改变 `blocks` 顺序、batch 输入、`finalTextUsedForTranslation`、覆盖图、`blockPassed`、失败分类、post-fusion cleanup 或候选选择。
- 缺真实 Koharu TextBoxes / BubbleMask / SegmentMask artifact 时只输出阻塞和 `provideRealKoharuArtifact`，不得用 Vision OCR、pre-crop plan、line plan、BubbleMask proxy 或 SegmentMask proxy 冒充 detector 输出。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`
- `md/prompt/v1（漫画探针）/v1.21（结构动作候选矩阵与Shadow执行评估）.md`

验证计划：

- 本轮 Agent B 本地运行 `swiftc -parse`、`git diff --check`、JSON 解析和 Koharu validator smoke。
- 未跑本机 build / 探针，按规则交给云端验证。
- 云端 `AITRANS CI Results` `ci-fast` 应证明 `structureActionCandidateReport.enabled = true`、`evaluatedBlockCount == totalBlocksDetected`、`candidateCount >= 1`，关键 breakdown 非空，每个 candidate 的 `diagnosticOnly = true`、`groundTruthUsedForPlanning = false`、`wouldChangeMainFlow = false`，且 `1_ocr_probe_text.txt` 包含新 summary 和逐块摘要。

遗留事项：

- 旧仓库根 `output/` 不含 v1.21 新字段；以 PR 后云端结果包为准。
- 本轮未重新跑完整漫画探针，不追加 `metrics/version_history.csv` 漫画指标行。

### v1.20：阅读顺序与气泡归属结构计划审计
日期：2026-06-30
依据：`md/prompt/v1（漫画探针）/v1.20（阅读顺序与气泡归属结构计划审计）.md`。本轮修改 Swift 探针报告模型、诊断 TXT 和核心文档；不刷新仓库根 `output/`，不追加 `metrics/version_history.csv`，完整 build / 探针交给 GitHub Actions。

核心变更：

- 新增 `readingOrderStructureAuditReport`，从最终 blocks、bbox、safe layout、bubbleID、BubbleMask、TextBox / SegmentMask proxy、post-fusion cleanup 和 v1.18 / v1.19 路由证据现场计算阅读顺序与结构计划审计。
- 每块写出 `currentOrderIndex`、`proposedReadingOrderIndex`、`orderConfidence`、`bubbleGroupID`、同气泡 sibling、气泡归属风险、分割/合并风险、重复/碎片风险、保护标记、结构动作建议和 `mustNotPromoteReasons`。
- 报告级汇总 `orderChangedBlocks`、`lowConfidenceOrderBlocks`、`multiBlockBubbleGroups`、`maskConflictBlocks`、`splitRiskBlocks`、`duplicateOrFragmentRiskBlocks` 以及 TextBox / SegmentMask / 风险 / 动作 breakdown。
- `1_ocr_probe_text.txt` 新增报告级 `readingOrderStructureAuditReport` summary 和每块 `readingOrderStructureAudit` 摘要。
- 报告只做诊断，不改变 `blocks` 顺序、batch 输入、`finalTextUsedForTranslation`、翻译候选、`blockPassed`、失败分类、post-fusion cleanup 或覆盖图。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`
- `md/prompt/v1（漫画探针）/v1.20（阅读顺序与气泡归属结构计划审计）.md`

验证计划：

- 本轮 Agent B 本地运行 `swiftc -parse`、`git diff --check`、JSON 解析和 Koharu validator smoke。
- 未跑本机 build / 探针，按规则交给云端验证。
- 云端 `AITRANS CI Results` `ci-fast` 应证明 `readingOrderStructureAuditReport.enabled = true`、`evaluatedBlockCount == totalBlocksDetected`、`cases.count == totalBlocksDetected`，关键 breakdown 非空，`1_ocr_probe_text.txt` 包含新 summary 和逐块摘要，且 v1.18 / v1.19 报告仍存在。

遗留事项：

- 旧仓库根 `output/` 不含 v1.20 新字段；以 PR 后云端结果包为准。
- 阅读顺序启发式可能和漫画叙事顺序不一致，本轮只输出 report-only 风险和建议，不应用到主流程。

### v1.19：路由驱动翻译对照与 OCR 损坏审计
日期：2026-06-30
依据：`md/prompt/v1（漫画探针）/v1.19（路由驱动翻译对照与OCR损坏审计）.md`。本轮修改 Swift 探针报告模型和诊断 TXT；不刷新仓库根 `output/`，不追加 `metrics/version_history.csv`，完整 build / 探针交给 GitHub Actions。

核心变更：

- 新增 `routingDrivenTranslationComparisonReport`，从 v1.18 `internalStructureBottleneckReport` 中选择最多 5 个 `modelTranslationQuality` 块，运行 deterministic `strictChineseOnlyV1` prompt 对照。
- strict prompt 对照复用现有候选抽取、raw / candidate 分类、质量 checks、failure reasons 和 language quality gate，只记录 control / variant / improvement / blockers，不替换主流程 prompt、译文、`blockPassed`、失败分类或覆盖图。
- 新增 `ocrCharacterDamageAuditReport`，只审计 `ocrCharacterDamage`、`ocrInputSuspect` 或 `ocrGroundTruthSimilarity < 0.72` 的块，输出 damaged / missing / extra / substitution token、重复关键词损坏、line break risk、TextBox / SegmentMask 证据、crop blockers 和 recommended action。
- OCR 损坏审计允许使用 `test/1.ground_truth.json` 做探针诊断，但不参与生产候选选择、排序、cleanup、promotion 或文本替换。
- `1_ocr_probe_text.txt` 新增两个 report 的逐块摘要和报告级 summary。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`
- `md/prompt/v1（漫画探针）/v1.19（路由驱动翻译对照与OCR损坏审计）.md`

验证计划：

- 本轮 Agent B 本地运行 `swiftc -parse`、`git diff --check`、JSON 解析和 Koharu validator smoke。
- 未跑本机 build / 探针，按规则交给云端验证。
- 云端 `AITRANS CI Results` `ci-fast` 应证明两个新 report 都存在，`routingDrivenTranslationComparisonReport.evaluatedCaseCount <= 5`，`ocrCharacterDamageAuditReport.evaluatedBlockCount > 0`，`1_ocr_probe_text.txt` 包含逐块摘要，且 `configuration.currentBlockSource` 仍为 `fusedWholePageBubble`。

遗留事项：

- 旧仓库根 `output/` 不含 v1.19 新字段；以 PR 后云端结果包为准。
- strict prompt 对照可能变好、变差或无变化，均只作为诊断信号，不代表本轮主流程质量提升。

### v2.3：云端导入 GGUF 并运行漫画探针
日期：2026-06-29
依据：云端验证基础设施改造；本轮修改 CI 和 DEBUG 启动逻辑，不刷新仓库根 `output/`，不追加 `metrics/version_history.csv` 漫画指标行。

核心变更：

- `AITRANS CI Results` workflow 在下载并校验 Release GGUF 后，构建 Debug simulator app。
- workflow 动态选择可用 iOS runtime 和 iPhone simulator device type，创建临时模拟器并安装 `com.local.aitrans`。
- workflow 把 `.ci-models/gemma-3-270m-it-qat-Q4_0.gguf` 复制到 App sandbox `Application Support/Models/Gemma-1.5B/model.gguf`，并校验 SHA256。
- workflow 用 `AITRANS_RUN_MANGA_PROBE=1` 启动 App，等待 `probe_report.json`，校验 `engineUsed = Local GGUF`、`totalBlocksDetected > 0` 和 `blocks` 非空，然后导出本轮 `output/` 到未加密 CI 结果包。
- DEBUG 启动探针逻辑在发现本地模型已安装时自动切换 `selectedEngine = .local`，避免 CI 误用 Mock。
- workflow 将云端探针等待上限提高到 3600 秒，每分钟打印 App 沙盒 `Output` 快照和 `manga_probe_progress.json`，失败时也复制已有 `output/` 到结果包。
- workflow 若发现 `manga_probe_progress.json` 连续 10 分钟不更新，会提前收束日志并失败，避免 App 已启动但探针主任务未推进时空等 3600 秒。
- DEBUG 漫画探针会在 `Output/manga_probe_progress.json` 写入当前阶段、耗时和块数，便于判断卡在 OCR、翻译、渲染还是报告写入。
- DEBUG 启动探针现在会写入 `launch-task-start`、`probe-entry`、`probe-task-start` 等阶段；缺 `test/1.png`、重复运行和运行异常都会写入进度或失败报告，避免只有 `launch-trigger-received` 而没有后续证据。
- workflow 同时通过 `SIMCTL_CHILD_*`、`launchctl setenv`、普通 argv 和 `-AITRANS_RUN_MANGA_PROBE 1` UserDefaults 参数触发 DEBUG 探针；App 侧同时识别环境变量、启动参数和 UserDefaults，并在收到触发后立即写入 `launch-trigger-received` 进度。
- DEBUG 漫画探针启动时跳过 `refreshSpeechRecognitionCapabilities()`，避免云端启动先查询多语言 Speech asset，延迟或干扰探针触发。
- workflow 在开始探针前清空仓库根 `output/`，成功后必须从 App 沙盒导出新 `output/`，并强制校验 `probe_report.json`、`clean_text_diagnostic.json`、`1_ocr_probe_text.txt` 和关键 PNG，避免把 checkout 自带旧报告误当云端结果。
- workflow 在导入模型时打印 Release asset、历史目录路径、SHA256 校验和字节数，避免把 `Models/Gemma-1.5B` 目录名误判为 1.5B 模型。
- 结果包新增 `simulator-build.log`、`manga-probe.log`、`app-console.log`、`probe-device-id.txt`、`probe-app-container.txt`、`output/manga_probe_progress.json` 等排查线索。

关键文件：

- `.github/workflows/ci-results.yml`
- `AITRANS/Services/TranslationSessionStore.swift`
- `README.md`
- `md/test/test.md`
- `md/flow/flow.md`
- `update_log.md`

验证结果：

- 本轮应运行 `git diff --check`、`python3 -m json.tool test/1.ground_truth.json`、workflow smoke 和 YAML 解析。
- 本机不运行 Xcode build / 漫画探针；完整探针由推送后的 GitHub Actions 验证。

验收口径：

- 云端探针报告可解析。
- `engineUsed = Local GGUF`。
- `totalBlocksDetected > 0` 且 `blocks` 非空。
- `probe_report.json`、`clean_text_diagnostic.json`、`1_ocr_probe_text.txt` 和关键 PNG 上传到结果包。
- `overallPassed=false` 不单独视为 CI 失败，因为当前模型质量基线仍包含失败块。

已知云端尝试：

- run `28360252442` 在 commit `161383946abb1edcc5929b72df748aa3d5a7d44e` 上完成模型校验、静态检查、Xcode build 和 simulator build，但 `manga-probe.log` 显示 900 秒内未生成 `probe_report.json`，因此不作为通过结果。
- run `28361773796` 在 commit `0c22574dd060a3623e793e314648a4ca6ec55805` 上进入 `Run cloud manga probe` 后 App 已启动但 `Output` 目录持续为空；该现象指向启动触发未进入 App 探针入口，已取消并改为多触发。
- run `28363254764` 在 commit `0c3140b9960061083cec50e17a7538acfa900b49` 上因 workflow 内 `simctl spawn ps` 在 iOS 模拟器中不可用而提前失败；artifact 里的 `output/` 来自 checkout 旧文件，不作为云端探针通过结果。后续已改为清空旧 `output/` 并要求从 App 沙盒导出新结果。
- run `28363769439` 在 commit `5728c14b3dfb26570ff9e5fcbf9eb13cdd631a73` 上清空旧 `output/` 后仍未生成沙盒报告，已取消；App 日志显示启动早期在查询 Speech assets，因此后续跳过云端探针启动时的 Speech capability refresh。
- run `28364280623` 在 commit `3075339a63dad07e887a61c383268d2653c69eb5` 上模型下载、SHA256 校验、Xcode build 和 simulator build 均成功；`manga_probe_progress.json` 停在 `launch-trigger-received`，说明 App 已收到触发但未进入探针主任务。该 run 的模型文件位于历史目录 `Gemma-1.5B`，但 SHA256 和 `241410624` 字节大小确认实际是 Release 的 Gemma 270M GGUF，不是模型传错。
- `AITRANS - Build IPA` run `28364280582` 同 commit 的 archive 失败为 exit 65，GitHub step 只保留 `xcpretty` 摘要，缺少具体 Swift/link/sign 原始错误；workflow 已改为使用 latest stable Xcode、显式 `generic/platform=iOS` destination，并上传 `xcodebuild-archive.log`，同时不改变加密打包密码流程。
- 后续修复把等待上限、App 侧进度文件、停滞检测和日志收集补齐；验收必须看新 run 的 manifest 和 artifact。

遗留事项：

- 若 GitHub-hosted runner 的模拟器启动、App 容器读取或探针耗时不稳定，应优先查看 `manga-probe.log`、`app-console.log`、`output/manga_probe_progress.json` 和 `simulator-build.log`，再决定是否拆分成独立 probe workflow 或继续削减探针云端耗时。

### v1.13 / v22：外部 TextBoxes shadow OCR 候选接入
日期：2026-06-30
依据：`md/prompt/v1（漫画探针）/v1.13（外部TextBoxes Shadow OCR候选接入）.md`、PR #3、`AITRANS CI Results` run `28381772143`。本轮修改 Swift 报告模型和探针诊断链路；完整 build / 探针已由 GitHub Actions 验证，仓库根 `output/` 未刷新，长期指标追加到 `metrics/version_history.csv` v22 行。

核心变更：

- 新增 `MangaOverlayExternalTextBoxShadowOCRReport`、block summary 和 candidate report 模型。
- 探针在生成 `externalArtifactReadinessReport` 后运行 external TextBoxes shadow OCR gate；只有 `readinessVerdict = readyForShadowOCR`、`activeArtifactsDirectory = true`、`contractExampleOnly = false` 且 `externalTextBoxesShadowOCRAllowed = true` 才执行 OCR。
- 默认缺 `test/koharu_artifacts/` 时新 report 明确写 `executed = false`、`candidateCount = 0`、`ocrExecutedCount = 0`、所有块 skipped，阻塞原因来自 readiness verdict。
- readiness 通过时，每个 fused block 最多选择 1 个 `externalArtifact.textBoxCrop` candidate；选择只使用 external TextBox 与 block 的 IoU、中心点包含、confidence、bubble alignment 和面积比例等无真值信号。
- external TextBox crop 复用本地 Vision OCR，只把 OCR 文本、quality delta、word preservation、promotion blockers 和 report-only verdict 写入 `probe_report.json` 与 `1_ocr_probe_text.txt`。
- `promotedExternalShadowBlocks` 保持空；若候选满足既有 gate，只写 `wouldPromoteByExistingGateBlocks`，不替换 `finalTextUsedForTranslation`、主覆盖图、`blockPassed`、`configuration.currentBlockSource` 或 `textRegionCropReport.adoptedCount`。
- README、flow、flowchart 和 test 文档同步说明 real detector artifact、contract fixture、readiness gate、external shadow OCR report 和主流程之间的边界。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`

验证结果：

- Agent B 本地轻量检查通过：`git diff --check`、`python3 -m json.tool test/1.ground_truth.json`、`python3 -m json.tool output/probe_report.json`、`python3 -m json.tool output/clean_text_diagnostic.json`，以及 Koharu artifact validator valid / invalid / allow-missing。
- Agent C 核对 PR #3：base `smalldata_test`、head `codeb/v1.13-external-textbox-shadow-ocr`、head commit `790f72cfc05e354d65351827694748b5db3de0a3`。
- 云端 `AITRANS CI Results` run `28381772143` / attempt `1` 通过；manifest 匹配 `version = v1.13`、`branch = codeb/v1.13-external-textbox-shadow-ocr`、`commitSha = 790f72cfc05e354d65351827694748b5db3de0a3`、`workflowName = AITRANS CI Results`。
- 结果包 `aitrans-ci-v1.13-codeb-v1.13-external-textbox-shadow-ocr--790f72cfc05e-run28381772143-attempt1` 包含 `.xcresult`、`junit.xml`、`xcodebuild.log`、`simulator-build.log`、`manga-probe.log`、`app-console.log`、`ci-artifact-manifest.json`、`ci-failure-summary.md` 和 `output/`。
- `junit.xml`：5 tests、0 failures；GGUF download / verify、static checks、Xcode build、simulator build、manga probe 全部 success。
- 云端探针：`engineUsed = Local GGUF`、`decodingMode = deterministic`、`decodingSeed = 42`、`totalBlocksDetected = 13`、`outputDirectoryCleaned = true`、`overallPassed = false`。
- v1.13 gate 结果：`externalArtifactReadinessReport.readinessVerdict = manifestMissing`、`externalTextBoxesShadowOCRReport.executed = false`、`candidateCount = 0`、`ocrExecutedCount = 0`、`promotedExternalShadowBlocks = []`、`skippedBlocks = [0...12]`。
- 质量数字未因本轮 shadow-only gate 改变：`groundTruthMatchedBlocks = 13`、`groundTruthUnmatchedBlocks = 0`、`averageCoreDialogueOCRSimilarity = 0.7106`、`averageDecorativeOCRSimilarity = 0.8000`、`cleanTextDiagnostic.passRate = 0.4545`、`passedBlocks = 1`、`failedBlocks = 12`。
- `overallPassed = false` 仍来自当前 Gemma 270M / OCR 质量基线，不作为本轮 v1.13 gate 失败。

验收口径：

- 缺 active artifact 时 shadow OCR 不执行，不新增 `externalArtifact.*` OCR candidate。
- `contractExampleOnly = true` 时 shadow OCR 不执行。
- 真实 active artifact ready 时才允许 external TextBoxes shadow OCR，且每块最多 1 个 candidate。
- candidate 选择和 report-only promotion 不使用 ground truth。
- external OCR 结果只进 report / TXT，不改变主输入、主覆盖图、通过判定或 TextRegion crop adopted 数。

遗留事项：

- 当前仓库默认仍没有真实 active `test/koharu_artifacts/`；若 Koharu 或人工提供 artifact，必须先跑 validator，再由云端探针验证新 report 的 `executed=true` 路径。

### v1.14：Koharu artifact 注入校验与 CI 摘要闭环
日期：2026-06-30
依据：`md/prompt/v1（漫画探针）/v1.14（真实KoharuArtifact注入与ShadowOCR验证闭环）.md`。当前没有真实 `test/koharu_artifacts/` active artifact，因此本轮走缺 artifact 路径 B；不创建 active artifact，不刷新漫画指标，不追加 `metrics/version_history.csv`。

核心变更：

- `scripts/validate-koharu-artifacts.py` 新增 `--print-required-files`，可直接打印 Koharu / 外部 detector 侧需要交付的 active 四件套。
- validator 摘要新增 `readyForShadowOCR`、`nextAction`、`readinessBlockers`、`requiredFiles` 和 `activeArtifactPolicy`，缺 active artifact 时明确返回 `manifestMissing`、`externalTextBoxesShadowOCRAllowed = false`、`nextAction = stopUntilArtifactsProvided`。
- `AITRANS CI Results` 静态检查会把 `test/koharu_artifacts` validator 摘要写入 `ci-results/koharu-active-artifacts-validation.json`。
- `ci-artifact-manifest.json` 新增 `koharuActiveArtifactValidationPath`、`koharuArtifactValidation`、`externalArtifactReadinessSummary` 和 `externalTextBoxShadowOCRSummary`，Agent C 可直接核对缺 artifact 阻塞路径或未来 executed=true 路径。
- `ci-failure-summary.md` 新增 Koharu artifact gate 小节，列出 active directory、verdict、shadow OCR allowed、nextAction 和 blockers。
- `md/koharu研究/artifact_contract/README.md` 新增从 Koharu 导出到 AITRANS contract 的最小转换要求，继续禁止 examples、Vision、pre-crop plan、line plan、proxy mask、ground truth 或手写理想框冒充真实 detector 输出。
- README、flow、flowchart 和 test 文档同步 v1.14 validator / CI 闭环边界。

关键文件：

- `scripts/validate-koharu-artifacts.py`
- `.github/workflows/ci-results.yml`
- `md/koharu研究/artifact_contract/README.md`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`
- `md/prompt/v1（漫画探针）/v1.14（真实KoharuArtifact注入与ShadowOCR验证闭环）.md`

验证结果：

- Agent B 本地轻量检查通过：`git diff --check`、`python3 -m json.tool test/1.ground_truth.json`、`python3 -m json.tool output/probe_report.json`、`python3 -m json.tool output/clean_text_diagnostic.json`、validator valid / invalid `--expect-fail`、`--print-required-files` 和 `test/koharu_artifacts --allow-missing`。
- Agent C 核对 PR #4：base `smalldata_test`、head `codeb/v1.14-koharu-artifact-validation-loop`、head commit `2cf9ed0e2db39152006f257236e7e63ad51828da`。
- 云端 `AITRANS CI Results` run `28417554480` / attempt `1` 通过；manifest 匹配 `version = v1.14`、`branch = codeb/v1.14-koharu-artifact-validation-loop`、`commitSha = 2cf9ed0e2db39152006f257236e7e63ad51828da`、`workflowName = AITRANS CI Results`。
- 结果包 `aitrans-ci-v1.14-codeb-v1.14-koharu-artifact-validation-loop--2cf9ed0e2db3-run28417554480-attempt1` 包含 `.xcresult`、`junit.xml`、`xcodebuild.log`、`simulator-build.log`、`manga-probe.log`、`app-console.log`、`ci-artifact-manifest.json`、`ci-failure-summary.md`、`koharu-active-artifacts-validation.json` 和 `output/`。
- `junit.xml`：5 tests、0 failures；GGUF download / verify、static checks、Xcode build、simulator build、manga probe 全部 success。
- `koharu-active-artifacts-validation.json`：`verdict = manifestMissing`、`readyForShadowOCR = false`、`externalTextBoxesShadowOCRAllowed = false`、`nextAction = stopUntilArtifactsProvided`、`missingArtifacts = [manifest, TextBoxes, BubbleMask, SegmentMask]`，并列出 active 四件套 `requiredFiles`。
- 云端探针：`engineUsed = Local GGUF`、`decodingMode = deterministic`、`decodingSeed = 42`、`totalBlocksDetected = 13`、`outputDirectoryCleaned = true`、`overallPassed = false`。
- App 侧 gate 摘要：`externalArtifactReadinessReport.readinessVerdict = manifestMissing`、`activeArtifactsDirectory = false`、`externalTextBoxesShadowOCRAllowed = false`、`nextAction = stopUntilArtifactsProvided`。
- Shadow OCR 摘要：`externalTextBoxShadowOCRReport.executed = false`、`candidateCount = 0`、`ocrExecutedCount = 0`、`ocrSucceededCount = 0`、`promotedExternalShadowBlocks = []`、`wouldPromoteByExistingGateBlocks = []`、`skippedBlocks = [0...12]`。
- 质量数字未因本轮 CI 可见性改造改变：`groundTruthMatchedBlocks = 13`、`groundTruthUnmatchedBlocks = 0`、`averageCoreDialogueOCRSimilarity = 0.7106`、`averageDecorativeOCRSimilarity = 0.8000`、`cleanTextDiagnostic.passRate = 0.4545`、`passedBlocks = 1`、`failedBlocks = 12`。
- Agent C 已通过 PR #4 merge 到 `smalldata_test`，merge commit `a758117`；远端 `codeb/v1.14-koharu-artifact-validation-loop` 已由 PR merge 命令请求删除。

遗留事项：

- 当前仍没有真实 active `test/koharu_artifacts/`，因此不能验证 `externalTextBoxShadowOCRReport.executed = true` 或 OCR 收益。
- 下一步需要 Koharu 或人工提供 `1.manifest.json`、`1.textboxes.json`、`1.bubbles.json`、`1.segment_mask.json`，先由 validator 达到 `readyForShadowOCR`，再通过云端探针核对 executed=true。

### v1.15：Koharu 真实 artifact 交付包 handoff
日期：2026-06-30
依据：`md/prompt/v1（漫画探针）/v1.15（Koharu真实Artifact交付包与executed验证）.md`。当前仍没有真实 `test/koharu_artifacts/` active artifact，因此本轮走路径 B；不创建 fake active artifact，不调 Vision crop / line deskew，不刷新漫画指标，不追加 `metrics/version_history.csv`。

核心变更：

- 新增 Agent A v1.15 提示词，明确下一步只验证真实 Koharu / 外部 detector 四件套的 `readyForShadowOCR` 与 `externalTextBoxShadowOCRReport.executed=true`。
- 在 `md/koharu研究/artifact_contract/README.md` 新增 v1.15 真实交付包清单，面向 Koharu / 人工列出四个必需文件、每个文件最低字段、坐标系、图像尺寸、禁止来源、validator 命令和 ready 后的云端验收字段。
- 确认当前 active 目录不存在，validator 阻塞仍是 `manifestMissing`、`nextAction = stopUntilArtifactsProvided`，缺 `manifest`、`TextBoxes`、`BubbleMask`、`SegmentMask`。

关键文件：

- `md/prompt/v1（漫画探针）/v1.15（Koharu真实Artifact交付包与executed验证）.md`
- `md/koharu研究/artifact_contract/README.md`
- `update_log.md`

验证结果：

- 本轮应运行 `git diff --check`、JSON 解析和 Koharu artifact validator valid / invalid / allow-missing / print-required-files。
- 当前 `test/koharu_artifacts` 不存在；`python3 scripts/validate-koharu-artifacts.py --root test/koharu_artifacts --allow-missing` 返回 `verdict = manifestMissing`、`readyForShadowOCR = false`、`externalTextBoxesShadowOCRAllowed = false`、`nextAction = stopUntilArtifactsProvided`。
- 未跑本机 build / 探针；本轮是文档和交付清单收口，不涉及 Swift 代码或探针产物刷新。

验收口径：

- 没有真实 active artifact 时，v1.15 不能声称已验证 `executed=true`。
- 不得把 contract examples、Vision OCR、pre-crop plan、line plan、BubbleMask proxy、SegmentMask proxy、ground truth 或手写框复制到 `test/koharu_artifacts/`。
- Koharu / 人工交付真实四件套后，必须先通过 validator，再由云端探针验证 `readyForShadowOCR` 与 `externalTextBoxShadowOCRReport.executed = true`。

遗留事项：

- 下一步需要 Koharu / 人工提供 `test/1.png` 对应的真实 detector / segmenter 四件套：`1.manifest.json`、`1.textboxes.json`、`1.bubbles.json`、`1.segment_mask.json`。

### v1.16：云端 CI 分层加速与探针快模式
日期：2026-06-30
依据：`md/prompt/v1（漫画探针）/v1.16（云端CI分层加速与探针快模式）.md`。本轮是 CI / DEBUG 探针运行制度改造，不刷新漫画质量指标，不追加 `metrics/version_history.csv`。

核心变更：

- `AITRANS CI Results` 新增 `workflow_dispatch` 输入 `probe_mode = ci-fast / full / skip`；`codeb/**` 和 `smalldata_test` push 默认 `ci-fast`。
- 云端 CI 改为单次 Debug simulator build：`Xcode build` 产出 `.xcresult` 和可安装 app，后续步骤只定位并复用 app，不再重复完整 simulator build。
- `ci-fast` 仍安装真实 simulator app、导入 Release GGUF、读取真实 `test/1.png`、使用 deterministic 解码，保留 whole-page OCR、bubble-first 融合、post-fusion cleanup、逐块 Local GGUF 翻译、失败块覆盖、核心 PNG、`probe_report.json`、`clean_text_diagnostic.json`、`1_ocr_probe_text.txt`、Koharu readiness gate 和 external TextBoxes shadow OCR gate。
- `ci-fast` 跳过高成本 shadow-only / 对照层：lexicon comparison、Vision API comparison、synthetic slice、TextRegion crop shadow、crop experiment、TextBox plan failure、line crop、模型 OCR 纠错、确定性纠错翻译、tagged batch、contact sheet 和诊断 PNG。
- DEBUG 探针新增 `AITRANS_MANGA_PROBE_MODE` 读取；报告配置新增 `probeRunMode`、`probeFastPathEnabled`、`skippedDiagnostics`。
- `manga_probe_progress.json` 新增 mode、fast path、跳过项、已保留输出文件和阶段耗时字段。
- manifest 新增 `probeMode`、`probeFastPathEnabled`、`probeSkippedReason`、`probeTimeoutSeconds`、`probeStallTimeoutSeconds`、`probeDurationSeconds`、`probeSkippedDiagnostics`、`probeOutputRequiredFiles`、`probeOutputRetainedFiles`、`probeReportSummary`、`simulatorAppReusedFromXcodeBuild` 和 `simulatorAppPath`。
- `ci-fast` 等待上限为 1800 秒，停滞阈值 300 秒，每 30 秒打印进度；`full` 保留 3600 秒和 600 秒停滞阈值。
- README、flow、flowchart 和 test 文档同步说明 fast / full / skip 边界和 Agent C 验收字段。

关键文件：

- `.github/workflows/ci-results.yml`
- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`
- `md/prompt/v1（漫画探针）/v1.16（云端CI分层加速与探针快模式）.md`

验证结果：

- 本轮 Agent B 本地应运行轻量检查、Koharu validator valid / invalid / allow-missing / print-required-files，以及 workflow YAML smoke。
- 未跑本机 Xcode build / 漫画探针；按规则推送 `codeb/v1.16-ci-probe-fastpath` 后交给 GitHub Actions 验证。
- Agent C 核对 PR #6：base `smalldata_test`、head `codeb/v1.16-ci-probe-fastpath`、head commit `ccd57e4906bf14eaa5b27253fae2d82fa24b581a`。
- 云端 `AITRANS CI Results` run `28420791001` / attempt `1` 通过；manifest 匹配 `version = v1.16`、`branch = codeb/v1.16-ci-probe-fastpath`、`commitSha = ccd57e4906bf14eaa5b27253fae2d82fa24b581a`、`workflowName = AITRANS CI Results`。
- 结果包 `aitrans-ci-v1.16-codeb-v1.16-ci-probe-fastpath--ccd57e4906bf-run28420791001-attempt1` 包含 `.xcresult`、`junit.xml`、`xcodebuild.log`、`simulator-build.log`、`manga-probe.log`、`app-console.log`、`ci-artifact-manifest.json`、`ci-failure-summary.md`、`koharu-active-artifacts-validation.json` 和 `output/`。
- `junit.xml`：5 tests、0 failures；GGUF download / verify、static checks、Xcode build、simulator app locate、manga probe 全部 success。
- manifest：`probeMode = ci-fast`、`probeFastPathEnabled = true`、`simulatorAppReusedFromXcodeBuild = true`、`probeTimeoutSeconds = 1800`、`probeStallTimeoutSeconds = 300`、`probeDurationSeconds = 150`。
- 云端探针：`engineUsed = Local GGUF`、`decodingMode = deterministic`、`decodingSeed = 42`、`totalBlocksDetected = 13`、`outputDirectoryCleaned = true`、`overallPassed = false`。
- `ci-fast` 保留输出满足要求：`probe_report.json`、`clean_text_diagnostic.json`、`1_ocr_probe_text.txt`、`1_debug_boxes.png`、`1_translated_overlay.png`、`manga_probe_progress.json`；额外保留 bubble debug PNG。
- `configuration.probeRunMode = ci-fast`、`probeFastPathEnabled = true`，`skippedDiagnostics` 包含 lexicon / Vision API / synthetic slice / TextRegion crop / crop experiment / line crop / tagged batch / correction / contact sheet / diagnostic PNG 等高成本诊断。
- 质量数字：`passedBlocks = 1`、`failedBlocks = 12`、`groundTruthMatchedBlocks = 13`、`groundTruthUnmatchedBlocks = 0`、`averageCoreDialogueOCRSimilarity = 0.6987`、`averageDecorativeOCRSimilarity = 0.8000`、`cleanTextDiagnostic.passRate = 0.4545`。
- Koharu gate：`externalArtifactReadinessReport.readinessVerdict = manifestMissing`、`externalTextBoxesShadowOCRAllowed = false`、`externalTextBoxShadowOCRReport.executed = false`、`candidateCount = 0`、`ocrExecutedCount = 0`、`promotedExternalShadowBlocks = []`、`skippedBlocks = [0...12]`。
- PR #6 已通过 GitHub merge 合并到 `smalldata_test`，merge commit `226de189e1cec63c23130eaf1389c112068ee68e`。

验收口径：

- PR base 必须是 `smalldata_test`，不能指向 `main`。
- `ci-results.yml` 不再重复完整 simulator build。
- 默认云端结果包 manifest 应显示 `probeMode = ci-fast`、`probeFastPathEnabled = true`、`simulatorAppReusedFromXcodeBuild = true`、`engineUsed = Local GGUF`、`totalBlocksDetected > 0` 和关键输出文件。
- `full` 仍可由手动 workflow_dispatch 触发；`skip` 只能用于文档-only 或人工明确跳过，并必须写 `probeSkippedReason`。

遗留事项：

- v1.16 仍不提供真实 active `test/koharu_artifacts/`，因此不能声称验证了 `externalTextBoxShadowOCRReport.executed = true`。

### v1.17：Koharu 真实 artifact 首包缺失退回
日期：2026-06-30
依据：`md/prompt/v1（漫画探针）/v1.17（Koharu真实Artifact首包接入与收益归因）.md`。当前仍没有真实 `test/koharu_artifacts/` active artifact，因此本轮走路径 B；不创建 fake active artifact，不改 Swift / CI / 探针主流程，不刷新漫画指标，不追加 `metrics/version_history.csv`。

核心变更：

- 新增 Agent A v1.17 提示词，明确下一步只在真实 Koharu / 外部 detector 四件套到位后验证 `readyForShadowOCR`、云端 `executed=true` 和 shadow OCR 收益归因。
- 新增 `md/koharu研究/v1.17-artifact-first-pass.md`，记录当前第一事实：仓库没有真实 active artifact，因此不能验证 `externalTextBoxShadowOCRReport.executed = true`，也不能判断 Koharu OCR 收益。
- 面向 Koharu / 人工列出首包必须回答的问题：detector 来源、原图坐标转换、bbox 越界、核心对话覆盖、Bubble instance 覆盖、SegmentMask 尺寸、`contractExampleOnly=false`、validator ready 和云端 App bundle 可读。
- 确认本轮不创建 `test/koharu_artifacts/`，不复制 examples，不用 Vision OCR、pre-crop plan、line plan、BubbleMask proxy、SegmentMask proxy、ground truth 或手写框生成 active artifact。

关键文件：

- `md/prompt/v1（漫画探针）/v1.17（Koharu真实Artifact首包接入与收益归因）.md`
- `md/koharu研究/v1.17-artifact-first-pass.md`
- `update_log.md`

验证结果：

- Agent B 本地轻量检查通过：`git diff --check`、`python3 -m json.tool test/1.ground_truth.json`、`python3 -m json.tool output/probe_report.json`、`python3 -m json.tool output/clean_text_diagnostic.json`，以及 Koharu artifact validator valid / invalid / allow-missing / print-required-files。
- Agent C 核对 PR #7：base `smalldata_test`、head `codeb/v1.17-koharu-artifact-first-pass`、head commit `9e467bd089a74f5ced7858a0a243bf5a4ab76d14`。
- 云端 `AITRANS CI Results` run `28422226573` / attempt `1` 通过；manifest 匹配 `version = v1.17`、`branch = codeb/v1.17-koharu-artifact-first-pass`、`commitSha = 9e467bd089a74f5ced7858a0a243bf5a4ab76d14`、`workflowName = AITRANS CI Results`。
- 结果包 `aitrans-ci-v1.17-codeb-v1.17-koharu-artifact-first-pass--9e467bd089a7-run28422226573-attempt1` 包含 `.xcresult`、`junit.xml`、`xcodebuild.log`、`simulator-build.log`、`manga-probe.log`、`app-console.log`、`ci-artifact-manifest.json`、`ci-failure-summary.md`、`koharu-active-artifacts-validation.json` 和 `output/`。
- `junit.xml`：5 tests、0 failures；GGUF download / verify、static checks、Xcode build、simulator build、manga probe 全部 success。
- 云端探针：`probeMode = ci-fast`、`engineUsed = Local GGUF`、`decodingMode = deterministic`、`decodingSeed = 42`、`totalBlocksDetected = 13`、`outputDirectoryCleaned = true`、`overallPassed = false`。
- 质量数字：`passedBlocks = 1`、`failedBlocks = 12`、`groundTruthMatchedBlocks = 13`、`groundTruthUnmatchedBlocks = 0`、`averageCoreDialogueOCRSimilarity = 0.6987`、`averageDecorativeOCRSimilarity = 0.8000`、`cleanTextDiagnostic.passRate = 0.4545`。
- Koharu gate：`koharuActiveArtifactsDirectoryPresent = false`、`externalArtifactReadinessReport.readinessVerdict = manifestMissing`、`externalTextBoxesShadowOCRAllowed = false`、`externalTextBoxShadowOCRReport.executed = false`、`candidateCount = 0`、`ocrExecutedCount = 0`、`promotedExternalShadowBlocks = []`、`skippedBlocks = [0...12]`。
- 本轮未跑本机 build / 探针；文档-only 修改按规则交给云端验证。没有真实 active artifact，因此仍不能触发云端 `executed=true` 收益验证。

验收口径：

- 没有真实 active artifact 时，v1.17 不能声称已验证 `executed=true` 或 Koharu OCR 收益。
- 若下一轮提供真实四件套，必须先通过 validator，再由云端 `ci-fast` 证明 `activeArtifactsDirectory = true`、`externalTextBoxesShadowOCRAllowed = true`、`externalTextBoxShadowOCRReport.executed = true`、`candidateCount > 0`、`ocrExecutedCount > 0`。
- 即使 external OCR 有收益，也仍是 shadow-only；不得替换 `finalTextUsedForTranslation`、主覆盖图、`blockPassed`、`configuration.currentBlockSource` 或 `textRegionCropReport.adoptedCount`。

遗留事项：

- 下一步仍需要 Koharu / 人工提供 `test/1.png` 对应的真实 detector / segmenter 四件套：`1.manifest.json`、`1.textboxes.json`、`1.bubbles.json`、`1.segment_mask.json`。

### 方向修正：Koharu 作为算法参考，不再等待外部 artifact
日期：2026-06-30
依据：人工确认“真实 Koharu artifact 没办法跑；不管 Koharu 的结果，只向它的算法和框架靠近，用 AITRANS 自己跑出的图片结果分析 OCR 准确率、气泡、翻译情况，并继续优化算法结构”。本记录是项目方向修正，不是漫画探针质量版本；不刷新 `output/`，不追加 `metrics/version_history.csv`。

核心决策：

- 不再把真实 `test/koharu_artifacts/` 四件套作为后续主线阻塞项。
- 保留现有 external artifact contract、validator、App readiness gate 和 `externalTextBoxShadowOCRReport`，作为将来如果有人提供真实 detector 输出时的可选防伪/诊断入口；但日常优化不等待它。
- Koharu 后续定位调整为算法和框架参考，而不是外部运行依赖。可借鉴的方向包括 TextBoxes 思想、BubbleMask / SegmentMask 中间层、气泡实例归属、mask-safe layout、crop / OCR 候选晋级门槛、失败归因、清字/覆盖结构和 artifact DAG 式诊断。
- 后续主要使用 AITRANS 自己的 `test/1.png` 探针、云端 `ci-fast` / `full` 输出、`probe_report.json`、`clean_text_diagnostic.json`、`1_ocr_probe_text.txt`、关键 PNG 和 `metrics/version_history.csv` 来分析 OCR 准确率、气泡归属/分割、翻译失败分类、覆盖渲染和结构性瓶颈。
- 真实外部 artifact 仍不得伪造；不要用 contract examples、Vision OCR、pre-crop plan、line plan、BubbleMask proxy、SegmentMask proxy、ground truth 或手写框冒充 detector 输出。
- 后续 Agent A 提示词应优先围绕本项目可执行的算法结构优化：例如 OCR block 合并/去重、bubble-first 与 whole-page 融合、气泡分割与归属修正、TextBox/SegmentMask proxy 质量归因、crop 候选晋级、翻译 prompt / 模型对照、报告摘要和可视化排查，而不是继续要求 Koharu / 人工交付四件套。

关键文件：

- `update_log.md`
- `md/koharu研究/koharu图像识别链路研究.md`
- `md/koharu研究/v6～9work.md`
- `md/koharu研究/v1.17-artifact-first-pass.md`
- `md/prompt/v1（漫画探针）/v1.17（Koharu真实Artifact首包接入与收益归因）.md`

验证结果：

- 本轮应运行 `git diff --check`。
- 本轮只改方向记录，不涉及 Swift 代码、CI workflow、探针报告模型或 `output/` 产物。
- 未跑本机 build / 探针；按规则，后续涉及 Swift / 漫画探针改动时仍交给云端验证。

后续执行口径：

- Agent A 下一版提示词不再以“缺真实 Koharu artifact”为阻塞结论。
- Agent B 不应再围绕 `manifestMissing` 做重复文档或 fake artifact 工作。
- Agent C 验收后续算法优化时，重点看当前分支 HEAD 的云端结果包、报告字段、关键 PNG、OCR/气泡/翻译指标和是否保持主流程边界。
- external artifact gate 可以保留在报告中显示 `manifestMissing`，这只是可选外部输入缺失，不再代表主线无法继续。

### v1.18：内部结构瓶颈路由与保守碎片清理
日期：2026-06-30
依据：`md/prompt/v1（漫画探针）/v1.18（Koharu式内部结构瓶颈路由与保守清理）.md`。本轮修改 Swift 探针报告模型、post-fusion cleanup 和核心文档；不刷新仓库根 `output/`，不追加 `metrics/version_history.csv`，完整 build / 探针交给 GitHub Actions。

核心变更：

- 新增 `internalStructureBottleneckReport`，从最终 blocks、post-fusion cleanup、TextRegion crop、TextBox plan failure、BubbleMask、assignment correction、split candidate、external readiness 和翻译失败分类聚合结构瓶颈路由。
- 每块写出 `primaryBottleneck`、`secondaryBottlenecks`、`recommendedNextAction`、`evidence` 和 `mustNotPromoteReasons`；报告级汇总 primary breakdown、recommended action breakdown、dialogue / decorative breakdown 和关键 block 列表。
- `1_ocr_probe_text.txt` 增加 `internalStructureBottleneck` 逐块摘要；`ci-fast` 也生成该报告，不只在 full 模式生成。
- post-fusion cleanup 新增保守 `duplicateOrFragment` 规则，使用 bbox 强重叠/邻域、bubble 或 mask-safe 邻域、token 覆盖、信息分、OCR 错误启发和保护文本检查清理低信息碎片。
- `fusionComparison.postFusionCleanup.rejectedBlocks[]` 增加 `relatedKeptBlockIndex`、`qualityScore`、`protectedTextMatched` 和 ground-truth-free `evidence`，便于 Agent C 审计拒绝原因。
- 保护文本扩展包含 `The City Battler Tournament starts in a few days.`；external artifact 缺失只作为 optional note，不再作为主线阻塞。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `update_log.md`

验证计划：

- 本轮 Agent B 本地运行轻量检查：`swiftc -parse` 目标 Swift 文件、`git diff --check`、JSON 解析和 Koharu validator smoke。
- 未跑本机 build / 探针，按规则交给云端验证。
- 云端 `AITRANS CI Results` `ci-fast` 应证明 `internalStructureBottleneckReport.evaluatedBlockCount = totalBlocksDetected`，breakdown 非空，`1_ocr_probe_text.txt` 含 `internalStructureBottleneck`，且 `configuration.currentBlockSource` 仍为 `fusedWholePageBubble`。

遗留事项：

- 旧仓库根 `output/` 不含 v1.18 新字段；以 PR 后云端结果包为准。
- 若云端 OCR 波动导致新 duplicate/fragment cleanup no-op，本轮仍应通过瓶颈路由报告提供可审计价值；不得为了让 block 数变化而硬编码 block index 或使用 ground truth。

Agent C 退回复修：

- PR #8 初次云端 run `28424308991` 虽然 CI success，但 artifact 显示 post-fusion cleanup 从 `16 -> 11`，误删了远距离真实文本，并产生 `post-fusion cleanup reduced block count below target floor: 11` warning，因此未通过验收。
- 根因 1：`duplicateOrFragment` 的 `sameDominantNeighborhood` 把两个 `nil` 的 `safeLayoutRect` / `maskSafeRect` 当成同邻域证据。修复后只有非空且相等的 safe / mask rect，或真实 same bubble / bbox 重叠 / bbox 邻近，才算邻域证据。
- 根因 2：`internalStructureBottleneckReport` 用 rejected 的 `originalFusedBlockIndex` 去匹配 cleanup 后已重编号的 `block.index`，导致保留块被误标为 `duplicateOrFragment`。修复后保留块写入 `postFusionCleanupOriginalFusedBlockIndex` note，rejected 原始索引只用于报告汇总；逐块 primary / secondary 不再用 rejected 原始索引误判最终保留块。
- 本修复不刷新仓库根 `output/`，不追加 `metrics/version_history.csv`；重新 push 后仍由 GitHub Actions 生成新的 ci-fast artifact 供 Agent C 验收。

Agent C 最终验收：

- PR #8 base 为 `smalldata_test`，head 为 `codeb/v1.18-internal-structure-routing`，最终验收 commit 为 `74d81dce9d90af57058575428c71721e3fd7534f`。
- 云端 `AITRANS CI Results` run `28425069180` / attempt `1` 通过；artifact `aitrans-ci-v1.18-codeb-v1.18-internal-structure-routing--74d81dce9d90-run28425069180-attempt1` 的 manifest 匹配 `version = v1.18`、`branch = codeb/v1.18-internal-structure-routing`、`commitSha = 74d81dce9d90af57058575428c71721e3fd7534f`、`workflowName = AITRANS CI Results`。
- 结果包包含 `.xcresult`、`junit.xml`、`xcodebuild.log`、`ci-failure-summary.md`、`ci-artifact-manifest.json`、`output/probe_report.json`、`output/clean_text_diagnostic.json`、`output/1_ocr_probe_text.txt` 和关键 PNG。
- `junit.xml`：5 tests、0 failures；GGUF verify、static checks、Xcode build、simulator build、manga probe 均为 success。
- 云端探针：`engineUsed = Local GGUF`、`decodingMode = deterministic`、`decodingSeed = 42`、`configuration.currentBlockSource = fusedWholePageBubble`、`probeRunMode = ci-fast`、`totalBlocksDetected = 13`、`outputDirectoryCleaned = true`、`overallPassed = false`。
- post-fusion cleanup 复验通过：`blockCountBeforeCleanup = 16`、`blockCountAfterCleanup = 13`、`rejectedBlockCount = 3`、`warnings = []`、`missingKeyTexts = []`；`THAT'S RIGHT...` 和 `IVE ARRIVED...` 真实文本保留，初次 run 的远距离误删已消失。
- `internalStructureBottleneckReport` 复验通过：`evaluatedBlockCount = 13`，`primaryBottleneckBreakdown = { bubbleAssignmentOrSplit: 2, modelTranslationQuality: 5, ocrCharacterDamage: 5, passed: 1 }`，`recommendedActionBreakdown` 非空，`duplicateOrFragmentBlocks = []`，`postFusionRejectedDuplicateOrFragmentBlocks = []`，`1_ocr_probe_text.txt` 含逐块 `internalStructureBottleneck` 摘要和 `postFusionCleanupOriginalFusedBlockIndex` 证据。
- 质量数字：`groundTruthMatchedBlocks = 13`、`groundTruthUnmatchedBlocks = 0`、`averageCoreDialogueOCRSimilarity = 0.6987`、`averageDecorativeOCRSimilarity = 0.8000`、`passedBlocks = 1`、`failedBlocks = 12`、`translationFailureBreakdown = { modelOutputFailure: 3, ocrInputSuspect: 7, translationLanguageQualityFailure: 2 }`、`likelyRuleFalseFailureBlocks = []`、`cleanTextDiagnostic.passRate = 0.4545`。
- `overallPassed = false` 仍来自当前 Gemma 270M / OCR 质量基线，不作为本轮结构路由和 cleanup 修复失败。

### v2.2：GitHub Release GGUF 下载与 Actions 缓存
日期：2026-06-29
依据：云端验证基础设施改造；未刷新 `output/`，未追加 `metrics/version_history.csv` 漫画指标行。

核心变更：

- `AITRANS CI Results` workflow 新增 Release 模型下载、SHA256 校验和 Actions cache。
- 模型来源固定为 Release `model-gemma-3-270m-it-qat-q4_0-v1` 的 `gemma-3-270m-it-qat-Q4_0.gguf`。
- SHA256 固定为 `3626e245220ca4a1c5911eb4010b3ecb7bdbf5bc53c79403c21355354d1e2dc6`。
- 结果包 manifest 新增 `modelReleaseTag`、`modelAsset`、`modelSha256`、`modelCacheKey`、`modelCacheHit`、`modelLocalPath`、`modelDownloadOutcome`、`modelVerifyOutcome`。
- 结果包新增或保留 `model-download.log`、`model-verify.log`，失败摘要中列出模型下载和校验状态。

关键文件：

- `.github/workflows/ci-results.yml`
- `README.md`
- `md/test/test.md`
- `md/flow/flow.md`
- `update_log.md`

验证结果：

- 本轮应运行 `git diff --check`、`python3 -m json.tool test/1.ground_truth.json`、workflow smoke 和 YAML 解析。
- 未运行本机 Xcode build / 漫画探针；按规则交给云端验证。

遗留事项：

- v2.2 只解决模型下载、校验和缓存；下一步才把 `.ci-models/gemma-3-270m-it-qat-Q4_0.gguf` 导入模拟器 App 沙盒的 `Application Support/Models/Gemma-1.5B/model.gguf`，再运行完整漫画探针和导出 `output/`。

### 协作流程维护：云端验证和结果包制度
日期：2026-06-29
依据：流程制度变更，不是漫画探针质量版本；未刷新 `output/`，未追加 `metrics/version_history.csv` 漫画指标行。

核心变更：

- 将日常重验证默认迁移到 GitHub Actions；本机默认只做 `git diff --check`、JSON/YAML smoke 等轻量检查。
- 明确当前真实工作主分支为 `smalldata_test`，Agent B 候选分支为 `codeb/vX.Y-短标题`，Agent C 通过后合并回 `smalldata_test`，禁止合并到 `main`。
- 增加 `agenta` / `a:`、`agentb` / `b:`、`agentc` / `c:` 召唤规则和最终回复身份标识。
- 保留现有带密码的软件包打包流程，不为 Agent C 验收改动或解密；Agent C 只使用独立未加密 CI 结果包。
- 要求云端失败时保留 `.xcresult`、`junit.xml`、`xcodebuild.log`、`ci-artifact-manifest.json` 和 `ci-failure-summary.md`，由 Agent C 指明失败阶段和日志位置后退回 Agent B 修复。
- 记录 GGUF 云端模型依赖为已知后续事项：未来通过 GitHub Release + workflow 下载 + 缓存解决，本轮不提交模型、不处理 Release asset。

关键文件：

- `AGENTS.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `md/prompt/README.md`
- `.github/workflows/ci-results.yml`

验证结果：

- 本轮应运行文档/JSON/YAML 静态检查。
- 未运行本机 Xcode build / 漫画探针；按新规则交给云端验证。

遗留事项：

- 云端完整漫画探针仍受 GGUF、模拟器容器、App 沙盒输出导出和外部 artifact 依赖影响；能稳定运行后必须由 workflow 生成新报告。
- 旧文档 `md/云端协作流程/云端改造.md` 是原始提示词归档，其中 `samlldata_test` 拼写与当前远端真实分支不一致；执行时以 `smalldata_test` 为准。

### 项目初始与多页 SwiftUI 原型
日期：2026-06 中旬
依据提交：`c988066` 到 `b7376d8`、`2b1a4f7`、`9a1a456`、`43f6890`、`ae7fe12`

核心变更：

- 建立 SwiftUI iOS App 骨架和 Xcode 工程。
- 形成文本翻译、历史、提示词、模型、Pro、开发调试等多页结构。
- `TranslationSessionStore` 成为状态和持久化中心。
- 本地状态落到 `Application Support/AITRANS/state.json`。
- 引入 Apple Vision OCR、Speech、StoreKit 2 占位和本地模型目录概念。

关键文件：

- `AITRANS/App/AITRANSApp.swift`
- `AITRANS/Views/ContentView.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/VisionOCRService.swift`
- `README.md`

验证结果：

- 历史记录显示 `plutil`、asset JSON 检查、iOS Simulator build 和 generic iOS build 曾通过。
- 当时 CoreSimulator service 不稳定，未完成完整点击交互测试。

遗留事项：

- UI 已可用，但主线质量依赖后续 OCR、模型和探针。

### LLM 接口、自测和 Local 模型路径
日期：2026-06 中旬
依据提交：`92f2a8c`、`84d00bb`、`c529c6b`

核心变更：

- 新增 LLM 接口自测和更严格的翻译探针。
- 确认本地模型路线优先走 `llama.cpp + GGUF`。
- 英译中自测开始拒绝返回原文、包含完整原文和不像目标语言的输出。
- 模型导入后统一复制为 `Application Support/Models/Gemma-1.5B/model.gguf`。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Views/ContentView.swift`
- `README.md`

验证结果：

- `git diff --check` 通过。
- `plutil -lint` 通过。
- iOS Simulator build 和 generic iOS build 通过。

遗留事项：

- 当时 Local 仍偏接口接入和冒烟，真实翻译质量还需 raw 探针和模型对比。

### Developer Console、Pro 页和测试入口
日期：2026-06 中旬
依据提交：`6b7df35`、`7e552ed`、`9adb9a0`

核心变更：

- 新增开发者调试界面，展示真实 prompt、raw output 和错误。
- Pro 从首页迁移到独立底部 Tab。
- Pro 页新增 StoreKit 2 订阅骨架、长按麦克风同声传译、音频和 OCR 测试入口。
- 修复缺少 `test/` 空文件夹导致的编译失败。

关键文件：

- `AITRANS/Views/ContentView.swift`
- `AITRANS/Views/ProFeatureViews.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `test/.gitkeep`
- `README.md`

验证结果：

- README 记录了相关功能和入口。
- 编译失败由 `test/.gitkeep` 修复。

遗留事项：

- StoreKit 商品仍未上线，购买链路只能作为骨架。
- 语音和权限行为需要真机验证。

### 普通图片 OCR 翻译与漫画探针起步
日期：2026-06 中旬
依据提交：`f6f22e7`、`b95b97f`、`1daddcd`、`b5811b7`、`4a9eab4`、`4288e32`、`103d773`、`51fa18d`

核心变更：

- 普通图片翻译接入 Apple Vision OCR，支持按 bbox 旁贴或覆盖译文。
- 漫画截图 `test/1.png` 进入固定探针链路。
- 探针开始记录 OCR 坐标、逐块 prompt/raw output、debug boxes、translated overlay 和 JSON 报告。
- 引入内容裁切、2x 放大、多角度 OCR、空间聚类、预处理对照、OCR 纠错护栏、iOS 18+ RecognizeTextRequest 对比、customWords 和 bubble-first 初版对照。

关键文件：

- `AITRANS/Services/VisionOCRService.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Models/TranscriptModels.swift`
- `scripts/export-probe-output.sh`
- `test/1.png`
- `README.md`

验证结果：

- 多轮在 iPhone 17 Pro 模拟器运行 `test/1.png` 探针并导出 `output/`。
- 初期旧指标 `0.8378 / 0.8755` 后来被确认因真值不完整、强行匹配和旧相似度过宽而不可信。

遗留事项：

- OCR 已能定位文字区域，但文本误识别严重。
- Gemma 270M raw 输出常复读英文、空输出、占位或解释。

### v13-v20：失败诊断、质量门槛、纠错对照和总览输出
日期：2026-06 下旬
依据提交：`382d8ee` 到 `b5be534`

核心变更：

- 报告新增输出清理证明、`translationDecisionTrace`、`translationFailureDetail`、`translationFailureBreakdown`、`ocrProbeNotes`。
- `blockPassed` 质量门槛收紧，不再只凭含中文判定成功。
- 引入确定性 OCR 纠错候选、纠错覆盖图、纠错后翻译对照和 `1_ocr_probe_text.txt`。
- 新增 `1_bubble_text_overlay.png` 和 `1_probe_contact_sheet.png`，便于优先看总览图。
- `outputCleanupRemovedItemCount`、`outputFileCountAfterCleanup` 等字段证明输出目录每轮重建。

关键文件：

- `AITRANS/Services/MangaOverlayProbeService.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Models/TranscriptModels.swift`
- `output/probe_report.json`
- `output/1_ocr_probe_text.txt`
- `README.md`

验证结果：

- 多轮 `xcodebuild ... CODE_SIGNING_ALLOWED=NO build` 通过。
- 多轮模拟器探针导出。
- `git diff --check` 通过。
- v20 时 `totalBlocksDetected = 12`、`passedBlocks = 0`、`failedBlocks = 12`，输出目录保留 14 个本轮文件。

遗留事项：

- 当前未完成的是翻译质量可用。
- Local Gemma 270M raw 输出不稳和 OCR 原句错误仍是主因。

### v21：结构化真值、可信匹配和新基线
日期：2026-06 下旬
依据：`README.md` 近期记录

核心变更：

- `test/1.ground_truth.json` 改为 12 条结构化真值：11 条 `dialogue`、1 条 `decorative`。
- 真值匹配改为可拒绝匹配，低于阈值标记 `unmatched`。
- 相似度改用词级 Levenshtein，保留旧 `ocrLegacySimilarity` 作对照。
- 核心对话和装饰标题分开统计。
- 新增 clean text diagnostic，直接把 dialogue 真值送入翻译链路。

关键文件：

- `test/1.ground_truth.json`
- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `README.md`

验证结果：

- 当轮可信基线为 `totalBlocksDetected = 12`、`10 matched / 2 unmatched`、核心对话 `0.6196`、装饰标题 `0.8000`、bubble-first `0.7397`、clean text `4/11`。

遗留事项：

- README 中旧 `0.8378 / 0.8755` 只能作为历史对照，不再用于验收。

### Agent 1-2：气泡几何约束和长图 slice OCR 诊断
日期：2026-06 下旬
依据提交：`ad56eae`、README Agent 1-2 记录

核心变更：

- 引入气泡候选几何约束，把 OCR candidate 分配到 `bubbleID`。
- 同一 bubble 内合并，跨 bubble 合并被拒绝。
- 新增长图竖向 slice OCR 诊断，长宽比超过阈值时分片 OCR、坐标还原和重叠去重。
- 合成长图机制测试验证 3 个竖向切片和 20% 重叠去重。

关键文件：

- `AITRANS/Services/MangaOverlayProbeService.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Models/TranscriptModels.swift`
- `md/koharu研究/v5work.md`
- `README.md`

验证结果：

- `test/1.png` 默认不触发 slice，主图结果保持 `14` 块、`10 matched / 4 unmatched`、核心 OCR `0.6131`、装饰 `0.8000`。
- 合成长图触发 3 个竖向切片，重叠去重链路跑通。

遗留事项：

- 块数从 12 增至 14，是气泡边界拒绝旧跨气泡合并导致，不是 OCR 阈值变激进。
- 底部相邻气泡仍有分割问题。

### v10：whole-page + bubble-first 融合主流程
日期：2026-06-28
依据：`md/prompt/v1（漫画探针）/v1.0（bubble融合主流程）.md`、当前 `output/probe_report.json`

核心变更：

- 新增融合候选模型、`fusionResults` 和 `fusionComparison`。
- 融合选择只用 bbox、bubbleID、文本相似度、OCR 置信度、文本长度和疑似 OCR 损坏等无真值信号。
- 主翻译输入切到 `fusedWholePageBubble`；whole-page 和 bubble-first 原始对比仍保留用于回退审计。
- 保留 whole-page 独有 `Let's Battle!`，并纳入 bubble-first 独有的两条真实内容。
- `renderOutputs` 不再二次清空沙盒 Output，避免提前生成的 bubble 调试图被本轮主渲染删除；目录清理由探针开始和导出脚本负责。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `output/probe_report.json`
- `metrics/version_history.csv`

验证结果：

- iPhone 17 Pro 模拟器重新跑 `test/1.png` 并导出。
- `totalBlocksDetected = 16`、可信匹配 `13`、未匹配 `3`。
- `averageCoreDialogueOCRSimilarity = 0.7106`、`averageDecorativeOCRSimilarity = 0.8000`。
- `frameworkComparison.consistencyPassed = true`、`fusionComparison.consistencyPassed = true`。
- `fusion.fused.accuracyVsGroundTruth = 0.7384`。
- `cleanTextDiagnostic.passRate = 0.4545`。
- `translationFailureBreakdown = { modelOutputFailure: 2, ocrInputSuspect: 10, translationLanguageQualityFailure: 3 }`。
- `likelyRuleFalseFailureBlocks = []`。

遗留事项：

- 融合提高了 OCR 覆盖和可信匹配，但翻译通过仍只有 1 块，瓶颈仍在 OCR 噪声和 Gemma 270M 翻译能力。
- `totalBlocksDetected = 16` 是纳入真实 bubble-only 内容后的结果；后续仍需继续压重复/碎片块。

### v11：融合后重复碎片压缩与气泡分割审计
日期：2026-06-28
依据：`md/prompt/v1（漫画探针）/v1.1（重复碎片压缩与气泡分割审计）.md`、当前 `output/probe_report.json`

核心变更：

- 在 `fusedWholePageBubble` 后新增 post-fusion cleanup，拒绝明显重复、被包含、低信息或与更完整候选重叠的碎片块。
- 清理逻辑只用 bbox、bubbleID、source、文本长度、词覆盖、候选间覆盖关系和 OCR 质量启发，不用 ground truth 做生产选择。
- `probe_report.json` 新增 `fusionComparison.postFusionCleanup`，记录清理前后块数、拒绝块、拒绝原因、关联块和保护内容。
- `bubbleGeometry` 新增 `bubbleAudits`，诊断每个 bubble 的文本区数量、selected block 数、重叠风险、过大 bubble 风险和 `bubbleSplitCandidate`；本轮不默认拆分主流程。

关键文件：

- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `AITRANS/Models/TranscriptModels.swift`
- `README.md`
- `metrics/version_history.csv`
- `md/flow/flow.md`
- `md/flow/flowchart.md`

验证结果：

- iPhone 17 Pro 模拟器重新跑 `test/1.png` 并导出最新 `output/`。
- `totalBlocksDetected = 13`，清理前 `16`，清理后 `13`，拒绝 `3` 块。
- 被拒绝块：`THE SUGSESTION WAS OVERPULED...`、`PLAY ONLING...`、`JUST`。
- 三条保护内容 `Let's Battle!`、`What are you even talking about?`、`We need to get results...` 均保留。
- `groundTruthMatchedBlocks = 13`，`groundTruthUnmatchedBlocks = 0`。
- `averageCoreDialogueOCRSimilarity = 0.7106`，`averageDecorativeOCRSimilarity = 0.8000`。
- `frameworkComparison.consistencyPassed = true`，`fusionComparison.consistencyPassed = true`。
- `fusion.fused.accuracyVsGroundTruth = 0.7384`，`cleanTextDiagnostic.passRate = 0.4545`。
- `passedBlocks = 1`，`failedBlocks = 12`，`translationFailureBreakdown = { modelOutputFailure: 2, ocrInputSuspect: 7, translationLanguageQualityFailure: 3 }`。
- `likelyRuleFalseFailureBlocks = []`。

遗留事项：

- `-02 AT / LEAST... 2EN-` 残片被保守保留，避免跨 bubble 误删真实内容；后续应在气泡分割层处理。
- `bubbleAudits` 标出 `bubbleID 4/6/7` 有多块同 bubble 或过大 bubble 风险，下一轮可做诊断开关下的保守拆分实验。

### v12：TextRegion crop 候选与结构化中间层
日期：2026-06-28
依据：`md/prompt/v1（漫画探针）/v1.2（TextRegion crop候选与Koharu结构化中间层）.md`、当前 `output/probe_report.json`

核心变更：

- 新增 TextRegion crop OCR 候选层，为每个 post-fusion 主块记录 seed bbox、region bbox、crop bbox、bubble clamp、padding、方向、whole-page/fused/adaptive/crop 文本和选择决策。
- `probe_report.json` 新增 `textRegionCropReport`，`1_ocr_probe_text.txt` 同步写入每块 crop 文本、selected 文本、拒绝理由、词保留率和质量分。
- crop 采用逻辑只用 ground-truth-free 信号：词数、词保留率、文本相似度、拉丁/符号比例、疑似 OCR 错误、bubble clamp 和质量分；真值只在选择后用于报告评估。

关键文件：

- `AITRANS/Services/MangaOverlayProbeService.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Models/TranscriptModels.swift`
- `README.md`
- `metrics/version_history.csv`
- `output/probe_report.json`
- `output/1_ocr_probe_text.txt`

验证结果：

- build、模拟器真探针、导出、JSON 解析、`git diff --check` 均通过。
- `textRegionCropReport.totalRegions = 13`，`cropSucceededCount = 10`，`adoptedCount = 0`，`rejectedCount = 13`。
- 主要拒绝原因：`rawWordsLost = 5`、`emptyCropText = 3`、`wordCountRegression = 2`、`sameAsFusedText = 2`、`insufficientQualityGain = 2`、`introducedLikelyOCRError = 1`。
- 主指标无回归：`totalBlocksDetected = 13`、`groundTruthMatchedBlocks = 13`、`groundTruthUnmatchedBlocks = 0`、核心 OCR `0.7106`、装饰 `0.8000`、`fusion.fused.accuracyVsGroundTruth = 0.7384`、`cleanTextDiagnostic.passRate = 0.4545`、`passedBlocks = 1`、`failedBlocks = 12`。
- 三条保护内容 `Let's Battle!`、`What are you even talking about?`、`We need to get results...` 均保留。

遗留事项：

- 当前 crop 候选没有足够收益，不能为了指标强行替换主翻译输入。
- 后续应优先改进 TextRegion 检测/气泡分割质量，再重新评估 crop 采用收益。

### v13：BubbleMask 子区域诊断与 TextRegion clamp
日期：2026-06-28
依据：`md/prompt/v1（漫画探针）/v1.3（BubbleMask子区域与TextRegion clamp优化）.md`、当前 `output/probe_report.json`

核心变更：

- 新增轻量 `bubbleSubRegionReport`，用 fused block seed bbox、parent bubble bbox、oversized bubble audit 和几何覆盖率生成 block-local subregion 诊断。
- TextRegion crop OCR 优先使用 `clampEligible` 的 subregion 作为 clamp 边界；无可信 subregion 时继续回退到 bubble bbox 或 content rect。
- `textRegionCropReport.diagnostics` 新增 `clampSource`、`subRegionID`、`subRegionBBox`、`subRegionCoverageRatio`、`subRegionRejectedReason`、subregion clamp 前后 crop bbox。
- `1_ocr_probe_text.txt` 同步写入每块 subregion/clamp 证据。
- crop 采用护栏保持 v12 口径，不放宽 adopted 条件，不用 ground truth 做 subregion 生成、crop clamp 或候选选择。

关键文件：

- `AITRANS/Services/MangaOverlayProbeService.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Models/TranscriptModels.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `metrics/version_history.csv`
- `output/probe_report.json`
- `output/1_ocr_probe_text.txt`

验证结果：

- build、模拟器真探针、导出、JSON 解析、`git diff --check` 均通过。
- `bubbleSubRegionReport.totalSubRegions = 11`，`clampEligibleCount = 2`，`oversizedBubbleIDs = [4, 6, 7]`。
- `textRegionCropReport.clampSources = { bubbleBBox: 9, contentRect: 2, subRegion: 2 }`，subregion clamp 实际用于块 `[6, 8]`。
- `textRegionCropReport.totalRegions = 13`，`cropSucceededCount = 10`，`adoptedCount = 0`，`rejectedCount = 13`；主要拒绝原因未因 clamp 变化被放宽。
- 主指标无回归：`totalBlocksDetected = 13`、`groundTruthMatchedBlocks = 13`、`groundTruthUnmatchedBlocks = 0`、核心 OCR `0.7106`、装饰 `0.8000`、`fusion.fused.accuracyVsGroundTruth = 0.7384`、`cleanTextDiagnostic.passRate = 0.4545`、`passedBlocks = 1`、`failedBlocks = 12`。
- 三条保护内容 `Let's Battle!`、`What are you even talking about?`、`We need to get results...` 均保留。

遗留事项：

- 轻量 subregion 仍是传统几何近似，不是真正 Koharu 实例 mask。
- 当前 `adoptedCount = 0`，说明 subregion clamp 只提供了更清楚的 crop 串扰证据，尚未证明可替换主翻译输入。
- 下一步应继续观察 `bubbleID 4/6/7` 的 sibling overlap 和 subregion 失败原因，再决定是否引入更强的 bubble/text region 检测。

### v14：BubbleMask 实例 ID 与 mask 安全区诊断
日期：2026-06-28
依据：`md/prompt/v1（漫画探针）/v1.4（BubbleMask实例ID与mask安全区诊断）.md`、当前 `output/probe_report.json`

核心变更：

- 新增 `bubbleMaskReport`，用现有 bubble bbox 生成轻量实例 ID mask 近似，背景为 0，内部栅格值为 `bubbleID + 1`。
- 逐块记录 `maskDominantBubbleID`、`maskDominantCoverageRatio`、`maskIDsUnderSeed`、mask-safe rect、渲染 mask collision 和 crop mask coverage。
- safe layout 优先使用可信 mask-safe rect；不可用时回退既有 bbox safe rect。
- TextRegion crop 只新增 mask 覆盖诊断，不放宽 adopted 护栏，不用 ground truth 做 mask、crop 或布局选择。

关键文件：

- `AITRANS/Services/MangaOverlayProbeService.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Models/TranscriptModels.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `metrics/version_history.csv`
- `output/probe_report.json`
- `output/1_ocr_probe_text.txt`

验证结果：

- build、模拟器真探针、导出、JSON 解析、`git diff --check` 均通过。
- `bubbleMaskReport.instanceCount = 8`，`maskSafeLayoutBlocks = 13`，`bboxFallbackBlocks = 0`。
- `bubbleMaskReport.inconsistentBubbleAssignmentBlocks = [4, 5, 11, 12]`，`renderMaskOverflowBlocks = []`。
- TextRegion crop 仍为 `13 regions / 10 succeeded / 0 adopted / 13 rejected`；mask coverage 低的 crop 块为 `[4, 5, 9, 12]`。
- 主指标无回归：`totalBlocksDetected = 13`、`groundTruthMatchedBlocks = 13`、`groundTruthUnmatchedBlocks = 0`、核心 OCR `0.7106`、装饰 `0.8000`、`fusion.fused.accuracyVsGroundTruth = 0.7384`、`cleanTextDiagnostic.passRate = 0.4545`、`passedBlocks = 1`、`failedBlocks = 12`。
- 三条保护内容 `Let's Battle!`、`What are you even talking about?`、`We need to get results...` 均保留。

遗留事项：

- 当前 BubbleMask 是 bbox/rounded-rect 近似，不是真正 Koharu 实例分割 mask。
- mask-safe layout 改善的是覆盖布局和诊断证据，不代表 OCR 分数提升。
- 下一步应继续围绕 `bubbleID 4/6/7` 的实例分割可信度、TextRegion 检测和 crop 低 mask 覆盖块做诊断。

### v15：BubbleMask 归属修正与保守气泡拆分候选
日期：2026-06-28
依据：`md/prompt/v1（漫画探针）/v1.5（BubbleMask归属修正与保守气泡拆分候选）.md`、当前 `output/probe_report.json`

核心变更：

- 新增 `bubbleAssignmentCorrectionReport`，逐块记录 current bubble、mask dominant bubble、coverage、修正建议、采用状态、拒绝原因和风险标记。
- 新增 `bubbleSplitCandidateReport`，只对 oversized `bubbleID 4/6/7` 生成保守 split candidate，记录 parent bubble、seed block、bbox、coverage、sibling overlap、clamp eligibility 和采用块。
- TextRegion crop clamp 顺序扩展为 split candidate、corrected bubble mask、subregion、bubble bbox、content rect；原有 adopted 护栏不放宽。
- `1_ocr_probe_text.txt` 同步输出 bubble 修正决策、split candidate、assignment/split clamp 证据和拒绝原因。

关键文件：

- `AITRANS/Services/MangaOverlayProbeService.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Models/TranscriptModels.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `metrics/version_history.csv`
- `output/probe_report.json`
- `output/1_ocr_probe_text.txt`

验证结果：

- build、模拟器真探针、导出、JSON 解析、`git diff --check` 均通过。
- `bubbleAssignmentCorrectionReport = { evaluatedBlockCount: 13, inconsistentBlockIndexes: [4, 5, 11, 12], recommendedCorrectionBlocks: [5, 11], appliedToCropClampBlocks: [5], rejectedCorrectionBlocks: [4, 11, 12] }`。
- `bubbleSplitCandidateReport = { parentBubbleIDs: [4, 6, 7], candidateCount: 6, clampEligibleCount: 3, appliedToCropClampBlocks: [5, 9, 10] }`。
- TextRegion crop 仍为 `13 regions / 10 succeeded / 0 adopted / 13 rejected`。
- 主指标无回归：`totalBlocksDetected = 13`、`groundTruthMatchedBlocks = 13`、`groundTruthUnmatchedBlocks = 0`、核心 OCR `0.7106`、装饰 `0.8000`、`fusion.fused.accuracyVsGroundTruth = 0.7384`、`cleanTextDiagnostic.passRate = 0.4545`、`passedBlocks = 1`、`failedBlocks = 12`。
- 三条保护内容 `Let's Battle!`、`What are you even talking about?`、`We need to get results...` 均保留。

遗留事项：

- 当前 BubbleMask 和 split candidate 仍是 bbox/rounded-rect 近似，不是真正 Koharu 实例分割。
- block 11 只推荐修正到 `bubbleID 7`，因 coverage 未达 clamp 阈值未采用；block 4/12 因保护短文本或 decorative 标题保持诊断-only。
- TextRegion crop adopted 仍为 0，下一步应继续改进真实 TextRegion/BubbleMask 检测质量，而不是放宽采用护栏。

### v16：TextBoxes 与 SegmentMask 轻量证据层
日期：2026-06-28
依据：`md/prompt/v1（漫画探针）/v1.6（TextBoxes与SegmentMask轻量证据层）.md`、当前 `output/probe_report.json`

核心变更：

- 新增 `textBoxCandidateReport`，逐块记录 TextBox 候选来源、bbox、clamp source、padding、glyph overlap、BubbleMask coverage、safe rect overlap、证据分、是否可用于 crop 和拒绝/风险原因。
- 新增 `segmentMaskReport`，把现有 glyph mask 与 BubbleMask/safe rect/TextBox overlap 聚合成轻量 SegmentMask 诊断，标注 cleanup/crop evidence 可用块和弱证据块。
- `textRegionCropReport.diagnostics` 新增 `textBoxCandidateID`、`segmentMaskUsableForCropEvidence` 和 `failureAttribution`；报告级新增 `failureAttributionBreakdown`。
- `1_ocr_probe_text.txt` 同步输出每块 TextBox candidate、SegmentMask 和 crop failure attribution 摘要。
- TextBoxes / SegmentMask 均是传统图像处理和现有 bbox/mask 字段的轻量证据层，不是真模型；本轮不改变主输入、不放宽 TextRegion crop adopted 护栏。

关键文件：

- `AITRANS/Services/MangaOverlayProbeService.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Models/TranscriptModels.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `metrics/version_history.csv`
- `output/probe_report.json`
- `output/1_ocr_probe_text.txt`

验证结果：

- build、模拟器真探针、导出、JSON 解析、`git diff --check` 均通过。
- `textBoxCandidateReport = { candidateCount: 13, cropEligibleCount: 6, usedForCropBlocks: [], rejectedBlocks: [2, 4, 5, 7, 9, 11, 12] }`，TextBox 候选本轮只从既有 TextRegion crop 诊断派生，没有作为上游 crop clamp 输入。
- `segmentMaskReport = { glyphMaskBlocks: 11, usableForCleanupBlocks: [0, 1, 2, 3, 6, 7, 8, 9, 10, 11], usableForCropEvidenceBlocks: [0, 1, 2, 3, 6, 7, 8, 9, 10, 11], weakSegmentBlocks: [4, 5, 12] }`。
- `failureAttributionBreakdown = { localVisionRegression: 6, rawWordsLost: 5, bubbleMaskConflict: 3, emptyLocalOCR: 3, segmentMaskWeak: 3, textBoxTooWide: 2, introducedLikelyOCRError: 2, wordCountRegression: 2, sameAsFusedText: 2, insufficientQualityGain: 2 }`。
- TextRegion crop 仍为 `13 regions / 10 succeeded / 0 adopted / 13 rejected`。
- 主指标无回归：`totalBlocksDetected = 13`、`groundTruthMatchedBlocks = 13`、`groundTruthUnmatchedBlocks = 0`、核心 OCR `0.7106`、装饰 `0.8000`、`fusion.fused.accuracyVsGroundTruth = 0.7384`、`cleanTextDiagnostic.passRate = 0.4545`、`passedBlocks = 1`、`failedBlocks = 12`。
- 三条保护内容 `Let's Battle!`、`What are you even talking about?`、`We need to get results...` 均保留。

遗留事项：

- 本轮只输出 JSON/TXT 证据，没有新增 PNG 边框可视化；原因是现有 `1_bubble_debug.png` 生成早于 v16 的 TextBox/SegmentMask 汇总，直接改图会扩大耦合。
- 当前主要归因仍是局部 Vision OCR 退化、raw words 丢失和近似 mask 冲突；下一步应提升真实 TextRegion/BubbleMask/SegmentMask 检测质量，而不是放宽 crop 采用护栏。

### v17：TextRegion crop shadow 实验矩阵
日期：2026-06-29
依据：`md/prompt/v1（漫画探针）/v1.7（TextRegion crop实验矩阵与候选晋级门槛）.md`、当前 `output/probe_report.json`

核心变更：

- 新增 `cropExperimentReport`，以当前 TextRegion crop 为 control，对每个 fused block 运行受控 shadow candidate 矩阵。
- 候选来源限定在现有结构证据：TextBox、SegmentMask/glyph、BubbleMask mask-safe rect、split candidate、corrected bubble 和 subregion；每块最多 control + 3 个额外候选。
- 新增逐候选 `candidateID`、`variantName`、source stack、bbox、OCR 文本、词保留率、质量分、risk flags、rejection reasons。
- 新增逐块 `bestShadowCandidate`、`promotionVerdict` 和 `stopReasons`；这些字段只做诊断，不写回 `finalTextUsedForTranslation`。
- `1_ocr_probe_text.txt` 同步输出每块 `cropExperiment` 摘要，便于直接比较 control 与 best shadow。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `metrics/version_history.csv`
- `output/probe_report.json`
- `output/1_ocr_probe_text.txt`

验证结果：

- build、模拟器真探针、导出、JSON 解析、`git diff --check` 均通过。
- `cropExperimentReport = { candidateCount: 52, controlCandidateCount: 13, ocrSucceededCount: 43, betterThanControlCount: 15, promotedShadowBlocks: [], stoppedBlocks: [2, 4, 5, 6, 7, 9, 11, 12] }`。
- 每块候选数最大为 4，未出现指数级矩阵。
- variant 尝试数：`currentTextRegionCrop=13`、`textBoxTight=13`、`maskSafeRectConstrained=13`、`glyphMaskExpanded=10`、`conservativeSeedBBox=2`、`splitCandidateClamp=1`。
- TextRegion crop 仍为 `13 regions / 10 succeeded / 0 adopted / 13 rejected`；TextBox `usedForCropBlocks=[]`。
- 主指标无回归：`totalBlocksDetected = 13`、`groundTruthMatchedBlocks = 13`、`groundTruthUnmatchedBlocks = 0`、核心 OCR `0.7106`、装饰 `0.8000`、`fusion.fused.accuracyVsGroundTruth = 0.7384`、`cleanTextDiagnostic.passRate = 0.4545`、`passedBlocks = 1`、`failedBlocks = 12`。
- 融合清理 `missingKeyTexts = []`，三条保护内容仍保留。

遗留事项：

- 本轮没有 shadow candidate 达到晋级门槛，说明当前轻量候选还不足以上游化。
- `betterThanControlCount = 15` 只表示局部质量分高于 control，不表示可采用；多数候选仍有 raw words lost、local Vision regression、bubble mask conflict 或 protected diagnostic only 风险。
- 下一步应停止在 `[2, 4, 5, 6, 7, 9, 11, 12]` 继续盲目局部 crop 调参，优先补真正 TextBoxes/BubbleMask/SegmentMask 检测质量或更强 OCR。

### v18：TextRegion crop 前 TextBox plan artifact
日期：2026-06-29
依据：`md/prompt/v1（漫画探针）/v1.8（Koharu式上游TextBoxes候选规划与shadow验证）.md`、当前 `output/probe_report.json`

核心变更：

- 新增 `preCropTextBoxPlanReport`，在 TextRegion crop OCR 之前为每个 fused block 生成 Koharu 式 TextBox plan。
- plan 来源限定在生产可用结构信号：fused seed bbox、bubble geometry、BubbleMask majority / safe rect、subRegion、split candidate、assignment correction、glyph / SegmentMask proxy。
- 每块最多保留 3 个 plan；`evidenceScore`、`eligibleForShadowOCR`、`riskFlags`、`rejectionReasons` 均为 ground-truth-free。
- `cropExperimentReport` 优先使用 `preCropTextBoxPlan.*` 变体作为 shadow OCR 来源；control 仍是当前 TextRegion crop。
- `1_ocr_probe_text.txt` 新增逐块 `preCropTextBoxPlans` 摘要，并明确 `shadowOnly=true`、`groundTruthNotUsed=true`、`notWrittenToFinalTextUsedForTranslation=true`。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `README.md`
- `AGENTS.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `metrics/version_history.csv`
- `output/probe_report.json`
- `output/1_ocr_probe_text.txt`

验证结果：

- build、模拟器真探针、导出、JSON 解析、`git diff --check` 均通过。
- `preCropTextBoxPlanReport = { planCount: 37, shadowOCREligiblePlanCount: 29, selectedForShadowOCRBlocks: [0, 1, 2, 3, 5, 6, 7, 8, 9, 10, 11], stoppedBlocks: [4, 12] }`。
- `cropExperimentReport = { candidateCount: 48, controlCandidateCount: 13, ocrSucceededCount: 36, betterThanControlCount: 13, promotedShadowBlocks: [], stoppedBlocks: [2, 3, 4, 5, 7, 9, 11, 12] }`。
- `cropExperimentReport.variantBreakdown` 新增 `preCropTextBoxPlan.seedTightTextBox`、`preCropTextBoxPlan.bubbleContainedTextBox`、`preCropTextBoxPlan.maskMajorityTextBox`。
- TextRegion crop 仍为 `13 regions / 10 succeeded / 0 adopted / 13 rejected`；`finalTextUsedForTranslation` 未由 plan 或 shadow OCR 写回。
- 主指标无回归：`totalBlocksDetected = 13`、`groundTruthMatchedBlocks = 13`、`groundTruthUnmatchedBlocks = 0`、核心 OCR `0.7106`、装饰 `0.8000`、`fusion.fused.accuracyVsGroundTruth = 0.7384`、`cleanTextDiagnostic.passRate = 0.4545`、`passedBlocks = 1`、`failedBlocks = 12`。
- 三条保护内容仍可信匹配：`Let's Battle!`、`What are you even talking about?`、`We need to get results...`。

遗留事项：

- `promotedShadowBlocks` 仍为空；本轮证明上游 plan artifact 可审计，但没有证明可直接替换主输入。
- 局部 Vision OCR 仍会在多个 pre-crop plan 上出现空输出、raw words lost 或质量退化；下一步应继续改善真实 TextBoxes/BubbleMask/SegmentMask 生成质量，而不是放宽 adopted 护栏。

### v19：TextBox plan 失败归因与晋级门槛审计
日期：2026-06-29
依据：`md/prompt/v1（漫画探针）/v1.9（TextBox计划失败归因与晋级门槛收敛）.md`、当前 `output/probe_report.json`

核心变更：

- 新增 `textBoxPlanFailureReport`，把 pre-crop plan、shadow OCR candidate 和 block 级结论串成三级失败归因。
- `MangaOverlayCropExperimentCandidate` 新增 `sourcePlanID`，稳定关联 `preCropTextBoxPlanReport.plans[].planID` 和 `cropExperimentReport.candidates[]`。
- 每个 best shadow candidate 输出 ground-truth-free promotion checks，包括 OCR 成功、`wordPreservationRatio >= 0.80`、`qualityDelta > 0.08`、raw words lost、OCR 错误、same-as-fused、BubbleMask / SegmentMask 风险和 protected block。
- `1_ocr_probe_text.txt` 每块新增 `textBoxPlanFailure` 和 `promotionChecks` 摘要，直接说明为什么停止、继续几何研究或需要审计晋级门槛。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `metrics/version_history.csv`
- `output/probe_report.json`
- `output/1_ocr_probe_text.txt`

验证结果：

- build、模拟器真探针、导出、JSON 解析、`git diff --check` 均通过。
- `textBoxPlanFailureReport = { evaluatedBlockCount: 13, evaluatedPlanCount: 37, evaluatedCandidateCount: 35, betterThanControlCandidateCount: 13, promotedShadowBlockCount: 0 }`。
- `stopRecommendedBlocks = [2, 3, 4, 5, 7, 9, 11, 12]`，`continueGeometryResearchBlocks = [1, 6, 10]`，`candidatePromotionBlockedBlocks = [1, 2, 4, 5, 6, 9, 10]`。
- `promotionBlockerBreakdown` 主要为 `qualityDeltaBelowOrEqual0.08: 31`、`wordPreservationRatioBelow0.80: 29`、`notBetterThanControl: 22`、`rawWordsLost: 19`、`emptyLocalOCR: 9`、`noShadowCandidate: 8`。
- `cropExperimentReport` 仍为 `48 candidates / 13 controls / 36 OCR succeeded / 13 betterThanControl / 0 promoted`；TextRegion crop 仍为 `13 regions / 10 succeeded / 0 adopted / 13 rejected`。
- 主指标无回归：`totalBlocksDetected = 13`、`groundTruthMatchedBlocks = 13`、`groundTruthUnmatchedBlocks = 0`、核心 OCR `0.7106`、装饰 `0.8000`、`fusion.fused.accuracyVsGroundTruth = 0.7384`、`cleanTextDiagnostic.passRate = 0.4545`、`passedBlocks = 1`、`failedBlocks = 12`。
- 三条保护内容仍可信匹配：`Let's Battle!`、`What are you even talking about?`、`We need to get results...`。

遗留事项：

- `betterThanControl = 13` 仍全部未晋级；主要原因是质量增益不足、词保留不足、raw words lost、空 OCR 或保护块，不是 adopted 护栏过严。
- 下一步应优先改善真实 TextBoxes / BubbleMask / SegmentMask 的几何证据，停止在已标记 stop 的块上继续盲目枚举局部 crop 变体。

### v20：行级 TextBox 与 deskew shadow 验证
日期：2026-06-29
依据：`md/prompt/v1（漫画探针）/v1.10（Koharu式行级TextBox与deskew shadow验证）.md`、当前 `output/probe_report.json`

核心变更：

- 新增 `lineTextBoxPlanReport`，目标块动态来自 `textBoxPlanFailureReport.continueGeometryResearchBlocks`，当前为 `[1, 6, 10]`。
- 每个目标块最多生成 4 个 line-level plan，覆盖 `lineTightTextBox`、`lineBandTextBox` 和保守 `deskewProbeTextBox`；deskew 角度只作为诊断记录，不做昂贵全局搜索。
- 新增 `lineCropExperimentReport`，复用现有 TextRegion crop OCR 和 v19 promotion gate，候选变体以 `lineTextBoxPlan.*` 开头。
- `1_ocr_probe_text.txt` 为目标块输出 line-level 计划、best line candidate、promotion checks 和带原因的 `lineResearchDecision`。
- 所有 line-level 结果均为 shadow-only，不改变 `finalTextUsedForTranslation`、主覆盖图、`blockPassed`、post-fusion cleanup 或 `textRegionCropReport.adoptedCount`。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `metrics/version_history.csv`
- `output/probe_report.json`
- `output/1_ocr_probe_text.txt`

验证结果：

- build、模拟器真探针、导出、JSON 解析、`git diff --check` 均通过。
- `lineTextBoxPlanReport = { targetBlocks: [1, 6, 10], planCount: 12, shadowOCREligiblePlanCount: 12 }`。
- `lineCropExperimentReport = { candidateCount: 12, ocrSucceededCount: 12, betterThanControlCount: 5, promotedLineShadowBlocks: [], stoppedAfterLineResearchBlocks: [1, 6, 10] }`。
- block 1 best line candidate 为 `lineBandTextBox`，`qualityDelta = 0.095`，但 `wordPreservationRatio = 0.571`，未过 `wordPreservationRatio >= 0.80`。
- block 6 best line candidate 为 `lineTightTextBox`，`qualityDelta = -0.053`，且有 `introducedLikelyOCRError`、`notBetterThanControl` 和词保留不足。
- block 10 best line candidate 为 `lineTightTextBox`，`qualityDelta = 0.046`，低于 `qualityDelta > 0.08`，且 `wordPreservationRatio = 0.583`。
- 主指标无回归：`totalBlocksDetected = 13`、`groundTruthMatchedBlocks = 13`、`groundTruthUnmatchedBlocks = 0`、核心 OCR `0.7106`、装饰 `0.8000`、`cleanTextDiagnostic.passRate = 0.4545`、`frameworkComparison.consistencyPassed = true`、`fusionComparison.consistencyPassed = true`。
- `Let's Battle!`、`What are you even talking about?`、`We need to get results...` 仍在明细中可信匹配。

遗留事项：

- line-level / deskew shadow 对 block `[1, 6, 10]` 有 5 个 better-than-control 候选，但没有任何候选通过既有 promotion gate。
- 当前证据支持停止继续在这 3 块上堆 crop / line / deskew 变体；下一步应转向真实 TextBoxes detector、真实 BubbleMask / SegmentMask，或更强 OCR / 翻译模型质量基准。

### v21：真实 TextBoxes 与 Mask 适配前证据闸门
日期：2026-06-29
依据：`md/prompt/v1（漫画探针）/v1.11（真实TextBoxes与Mask适配前证据闸门）.md`、当前 `output/probe_report.json`

核心变更：

- 新增 `externalArtifactReadinessReport`，覆盖真实或外部导出的 `TextBoxes`、`BubbleMask`、`SegmentMask` 三类 artifact。
- 支持读取 bundle 内 `test/koharu_artifacts/1.manifest.json`、`1.textboxes.json`、`1.bubbles.json`、`1.segment_mask.json`，或 manifest 指定的等价路径。
- parser 校验 manifest、schema、坐标系、source image、bbox 越界、confidence 和 SegmentMask 尺寸，并把外部 TextBoxes / Bubble instances 与当前 fused blocks 做 IoU / center containment 对齐。
- `1_ocr_probe_text.txt` 顶部新增 `externalArtifactReadiness` 摘要，每块新增 `externalArtifacts` 行。
- 所有 external artifact 结果均为 shadow-only，不改变 `configuration.currentBlockSource`、`finalTextUsedForTranslation`、主覆盖图、`blockPassed`、post-fusion cleanup 或 `textRegionCropReport.adoptedCount`。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `README.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `metrics/version_history.csv`
- `output/probe_report.json`
- `output/1_ocr_probe_text.txt`

验证结果：

- build、模拟器真探针、导出、JSON 解析、`git diff --check` 均通过。
- 当前仓库没有 `test/koharu_artifacts/`，因此 `externalArtifactReadinessReport = { manifestFound: false, textBoxesFound: false, bubbleMaskFound: false, segmentMaskFound: false, readinessVerdict: manifestMissing, nextAction: stopUntilArtifactsProvided, missingArtifacts: [manifest, TextBoxes, BubbleMask, SegmentMask], blockAlignmentCount: 13 }`。
- 主指标无回归：`totalBlocksDetected = 13`、`groundTruthMatchedBlocks = 13`、`groundTruthUnmatchedBlocks = 0`、核心 OCR `0.7106`、装饰 `0.8000`、`frameworkComparison.consistencyPassed = true`、`fusionComparison.consistencyPassed = true`。
- TextRegion crop 仍为 `13 regions / 10 succeeded / 0 adopted / 13 rejected`。
- line-level research 仍为 `targetBlocks = [1, 6, 10]`、`promotedLineShadowBlocks = []`、`stoppedAfterLineResearchBlocks = [1, 6, 10]`。

遗留事项：

- 当前正确结论是缺少真实 detector / mask artifact，下一步必须先提供或生成真实 TextBoxes / BubbleMask / SegmentMask 输出。
- 不得把 reference/koharu-main 源码存在、现有 Vision OCR blocks、pre-crop plan 或 line plan 写成“真实 detector 已接入”。
- 不应继续在 v20 已判停的 block / line / deskew crop 变体上试参。

### v22：Koharu 外部 Artifact 契约与离线 Validator
日期：2026-06-29
依据：`md/prompt/v1（漫画探针）/v1.12（Koharu外部Artifact契约与Shadow OCR入口）.md`

核心变更：

- 新增 `md/koharu研究/artifact_contract/README.md`，明确 active 输入目录是 `test/koharu_artifacts/`，非活动 fixture 目录是 `md/koharu研究/artifact_contract/examples/`。
- 新增 valid / invalid contract fixtures；valid fixture 标记 `contractExampleOnly=true`，只用于 schema / parser smoke，不代表真实 detector 输出。
- 新增 `scripts/validate-koharu-artifacts.py`，用 Python 标准库校验 manifest、fallback 路径、TextBoxes、Bubble instances、SegmentMask summary、source image、坐标系、bbox、confidence 和图片尺寸。当前 `test/1.png` 文件名为 `.png`，实际 header 是 JPEG，validator 同时支持 PNG / JPEG header。
- Swift `externalArtifactReadinessReport` 新增 active/example 区分、manifest / artifact 路径、`generatedBy` 和 `externalTextBoxesShadowOCRAllowed`；`contractExampleOnly`、坐标缺失、坐标不匹配、source image 不匹配、bbox / SegmentMask 尺寸错误现在有更明确的 verdict / nextAction。
- GitHub Actions 静态检查加入 artifact validator，并在 `ci-artifact-manifest.json` 记录 validator 日志路径、是否运行和 active artifact 目录是否存在。

关键文件：

- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Services/MangaOverlayProbeService.swift`
- `.github/workflows/ci-results.yml`
- `scripts/validate-koharu-artifacts.py`
- `md/koharu研究/artifact_contract/README.md`
- `md/koharu研究/artifact_contract/examples/`
- `README.md`
- `md/flow/flow.md`
- `md/test/test.md`
- `update_log.md`

验证结果：

- 本轮应运行 `git diff --check`、JSON 解析和 artifact validator smoke。
- 本轮不跑本机 Xcode build / 漫画探针；Swift build、云端探针和结果包由 PR 后 GitHub Actions 验证。
- 这是 contract / validator 版本，不刷新 `output/`，不追加 `metrics/version_history.csv` 漫画指标行。

遗留事项：

- 当前仓库仍没有真实 `test/koharu_artifacts/` active artifact；没有真实 detector / segmenter 输出时，App 探针应继续阻塞在 `manifestMissing` 或 `artifactFilesMissing`。
- 下一轮只有在人工或外部 Koharu 侧提供真实 TextBoxes / BubbleMask / SegmentMask artifact 后，才允许准备 `externalArtifact.*` shadow OCR candidate；仍不得替换主输入或放宽 promotion gate。

### Agent 3：自适应 crop 与回退自测
日期：2026-06 下旬
依据提交：`da9d574`

核心变更：

- OCR 二次 crop 从固定比例扩张改为自适应 padding。
- 横排文本 y padding 大于 x padding，竖排相反。
- crop clamp 到所属气泡 bbox。
- 新增固定 crop 对照、自适应 crop 字段和人为超窄 crop 回退自测。

关键文件：

- `AITRANS/Services/MangaOverlayProbeService.swift`
- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `README.md`

验证结果：

- build、模拟器探针、JSON 解析、`git diff --check` 通过。
- `totalBlocksDetected = 14`、`10 matched / 4 unmatched`、核心 OCR `0.6131`、装饰 `0.8000`、clean text `0.5455`。
- `cropFallbackSelfTest.triggered = true`。

遗留事项：

- 真实 `test/1.png` 未触发实际 fallback。
- 自适应 crop 有提升块也有变差块，不能按真值驱动生产选择。

### Agent 4-5：安全布局区和离屏碰撞检查
日期：2026-06 下旬
依据提交：`b65d904`

核心变更：

- 新增 `safeLayoutRect` 和 `safeLayoutSource`。
- 单块气泡使用气泡 bbox inset，多块同气泡使用分区安全区。
- 覆盖绘制前用离屏 alpha mask 检查文字越界，通过字号回退解决。

关键文件：

- `AITRANS/Services/MangaOverlayProbeService.swift`
- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `README.md`

验证结果：

- build、完整探针、导出、JSON 解析、`git diff --check` 通过。
- `safeLayoutRectBlocks = 14`、`renderCollisionCheckedBlocks = 14`。
- `renderCollisionUnresolvedBlocks = []`、`renderTextTruncatedBlocks = []`。

遗留事项：

- 该轮改善渲染布局，不改变 OCR 准确率。

### Agent 6-7：glyph mask 和纯色背景填充
日期：2026-06 下旬
依据提交：`0ab70d0`、`08438e9`

核心变更：

- 对已归属气泡块生成轻量 glyph mask。
- mask 使用局部阈值、连通域过滤、OCR bbox 重叠约束和膨胀。
- 低纹理背景区域使用 RGB 中位数做纯色填充，高纹理或插画区域保留半透明覆盖。
- 未归属气泡块不生成 mask。

关键文件：

- `AITRANS/Services/MangaOverlayProbeService.swift`
- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `README.md`

验证结果：

- build、完整探针、导出、JSON 解析、`git diff --check` 通过。
- `glyphMaskBlocks = 11`。
- 纯色填充触发块 `[2, 4, 6, 7]`。
- 未归属块 `5/11/13` 的 mask 为 0，符合气泡内约束。

遗留事项：

- glyph mask 和背景填充只影响覆盖可读性，不修 OCR 文本。

### Agent 8-9：tagged batch 诊断和 v5 汇总
日期：2026-06 下旬
依据提交：`6e1aa7f`、`613ca14`

核心变更：

- 新增 `batchTranslationComparison` tagged 批量翻译诊断。
- 批量分支只写报告，不替换逐块翻译、`blockPassed`、raw output 或 fallback。
- 完成 Agent 1-9 汇总，确认几何约束改善归属、裁切、渲染和跨气泡隔离。

关键文件：

- `AITRANS/Services/TranslationSessionStore.swift`
- `AITRANS/Models/TranscriptModels.swift`
- `README.md`
- `output/probe_report.json`

验证结果：

- batch 诊断负面：`parsedCases = 0`、`missingTags = [0...13]`、`unexpectedTags = [14...24]`。
- 逐块通过率 `0.0714`，批量通过率 `0`。
- 完整探针基线仍为 `14` 块、`10 matched / 4 unmatched`、核心 OCR `0.6131`。

遗留事项：

- Gemma 270M 不适合 tagged batch 翻译主流程。
- 几何约束不能根治专有名词和 OCR 字符损坏。

### v6：确定性诊断解码和跨版本指标
日期：2026-06-27
依据提交：`d316ab2`、`metrics/version_history.csv`

核心变更：

- `LlamaRuntime` 支持按调用切换 sampled 和 deterministic 解码。
- 用户实际翻译和 summary 保持 sampled。
- raw 诊断、漫画探针、clean text、batch 和纠错翻译对照使用 deterministic，固定 `seed = 42`。
- 新增 `metrics/version_history.csv` 和 `scripts/append-version-metrics.py`。

关键文件：

- `AITRANS/Services/LlamaRuntime.swift`
- `AITRANS/Services/GemmaLocalService.swift`
- `AITRANS/Models/TranscriptModels.swift`
- `AITRANS/Services/TranslationSessionStore.swift`
- `metrics/version_history.csv`
- `scripts/append-version-metrics.py`

验证结果：

- build、探针、导出、JSON 解析、`git diff --check` 通过。
- `deterministicDecodingCheck.outputsIdentical = true`。
- v6 指标：`14` 块、`10 matched / 4 unmatched`、核心 OCR `0.6131`、clean text `0.4545`。

遗留事项：

- v4 缺完整逐块 OCR 快照，无法字符级回溯 `0.6196 -> 0.6131`。

### v7：底部气泡串扰诊断和保守 crop 修复
日期：2026-06-27
依据提交：`c5bd626`、`metrics/version_history.csv`

核心变更：

- 专项排查 `GET PESULTE...` 和 `What Whet...`。
- 当 OCR bbox 只覆盖合理气泡的一部分时，二次预处理 OCR 使用所属气泡 bbox 做 adaptive crop。
- 检测层 seed 分裂和小框优先实验因回归被回退。

关键文件：

- `AITRANS/Services/MangaOverlayProbeService.swift`
- `README.md`
- `metrics/version_history.csv`

验证结果：

- build、完整探针、导出、JSON 解析、`git diff --check` 通过。
- 指标保持 `14` 块、`10 matched / 4 unmatched`、核心 OCR `0.6131`、clean text `0.4545`。

遗留事项：

- 目标 OCR 没有实质改善。
- 后续应改气泡候选分割，而不是放宽跨气泡合并。

### v8：bubble-first 主流程切换评估
日期：2026-06-28
依据提交：`ce577b7`、`metrics/version_history.csv`

核心变更：

- 重新评估 bubble-first 能否替换整页主候选源。
- 结论是不推进架构改造，本轮只做证据收集和决策。

关键文件：

- `README.md`
- `metrics/version_history.csv`
- `output/probe_report.json`

验证结果：

- build、模拟器探针、导出、JSON 解析、`git diff --check` 通过。
- `blocksFoundByBoth = 8`。
- `blocksOnlyInWholePage = ["Let's Battle!"]`。
- `blocksOnlyInBubbleFirst = ["What are you even talking about?", "We need to get results at this tournament to save the gaming club from being disbanded."]`。
- `frameworkComparison.consistencyPassed = true`。

遗留事项：

- bubble-first 可作为未来融合候选，但不能直接独占主流程。
- 未来若推进，需要 whole-page 真实内容兜底和去重报告字段。

### v9：词表、确定性纠错和 OCR 错误结构复盘
日期：2026-06-28
依据提交：`d3080c4`、`metrics/version_history.csv`、`md/koharu研究/v6～9work.md`

核心变更：

- 复测 Vision `customWords`：开关词表最终文本无变化。
- 复盘确定性 OCR 纠错候选：只保留诊断对照，不进入主流程。
- 总结低相似和未匹配块结构，确认问题不是 `Senpai` 单点，而是专有名词和常见词混淆共同存在。

关键文件：

- `README.md`
- `metrics/version_history.csv`
- `output/probe_report.json`
- `md/koharu研究/v6～9work.md`

验证结果：

- 最新指标：`totalBlocksDetected = 14`、`10 matched / 4 unmatched`、核心 OCR `0.6131`、装饰 `0.8000`、whole-page `0.6131`、bubble-first `0.7397`、clean text `0.4545`、`passedBlocks = 1`、`failedBlocks = 13`。
- `translationFailureBreakdown = { ocrInputSuspect: 10, translationLanguageQualityFailure: 3 }`。
- `likelyRuleFalseFailureBlocks = []`。

遗留事项：

- 文字区域检测和 OCR 文本质量仍是核心瓶颈。
- 下一轮优先做更强小模型对比，如 Qwen2.5-0.5B-Instruct-GGUF q4_k_m，或推进 bubble-first + whole-page 融合，而不是继续放宽质量规则。

## 历史维护记录
### README 更新记录收口到 update_log
日期：2026-06-29

核心变更：

- 删除 README 中的“近期优化记录”长段落，README 改为只保留项目说明、当前用法和稳定规则。
- 明确版本历史、关键决策、验证结果和遗留问题统一写入 `update_log.md`。
- 同步修正 `AGENTS.md` 和 README 中“更新 README 近期记录”的旧维护规则。
- 保留 `metrics/version_history.csv` 作为漫画探针和翻译链路可量化版本的 append-only 指标表。

关键文件：

- `README.md`
- `AGENTS.md`
- `update_log.md`

验证结果：

- 本轮是文档-only 流程收口，按规则运行轻量静态检查。

遗留事项：

- 历史条目已在 `update_log.md` 汇总；后续不要再向 README 追加更新记录。

### 建立多 Agent 迭代文档体系
日期：2026-06-28

核心变更：

- 整合标准入口为 `AGENTS.md`，作为项目唯一核心入口文档。
- 新增 `md/prompt/README.md`、`md/test/test.md`、`md/flow/flow.md`、`md/flow/flowchart.md`。
- 根据 git 记录、README 和指标 CSV 整理本 `update_log.md`。

关键文件：

- `AGENTS.md`
- `update_log.md`
- `md/prompt/README.md`
- `md/test/test.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`

验证结果：

- 本轮为文档-only 任务，按 `md/test/test.md` 只需静态检查。

遗留事项：

- 后续每轮由 Agent A 按 `md/prompt/README.md` 的命名规则写入具体实现提示词。
## v3.173：日语 observation 语言专用融合

日期：2026-08-08

状态：Agent X 继续按 Koharu 的“语言识别后再做候选融合”边界收紧普通图片日语 OCR。Vision 的 90°／270°、文字块、line 与 perspective reread 结果会进入日语专用 `deduplicateJapaneseObservations`：保留原有文本长度、置信度、CJK 与旋转分数，只额外加入上限为 `1.1` 的 `japaneseScriptDensity`／标点 evidence，并对无日语证据候选施加 `-0.65` 轻微 tie-breaker。日语竖排 block/line 候选排序、合成 line 的代表 observation 和弱方向 fallback 统一使用该 helper；普通语言仍走原 `deduplicateObservations`，不新增硬语言 gate。

核心变更：

- `recognizeTextBlocks` 在日语与非日语最终布局前分流去重；`recognizeJapaneseVerticalCrops`、`recognizeJapaneseVerticalLineCrops`、碎片合成与 orientation fallback 使用日语专用排序。
- 新增 `japanesePunctuationDensity` 与有界 `japaneseObservationEvidence`；保留 v3.172 合成 line 的几何、24 条预算、预处理、映射和 perspective 边界。
- 新增 `scripts/test-v3173-image-japanese-observation-fusion-contract.py`；v3.172 历史合同接受 `deduplicateJapaneseObservations` 的等价共享 helper。

边界：该改动只影响普通图片日语 OCR 的重复 observation 选择，不加载 Manga OCR/PaddleOCR 权重，不改变翻译、renderer/export、Store、探针、Koharu active gate、metrics 或 `output`。`test/jap.jpg` 继续只作合同 fixture；真实竖排图片质量 corpus、Speech corpus 与 Koharu 四件套仍缺失，不能据此声称日语 OCR、翻译、识别或 Koharu 质量提升。

云端证据：

- 候选 exact-SHA full [31206796785](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31206796785)：`validationProfile=full`、`validationReason=candidate_development_push`，commit `d86f875d1040d69259b62b52754c73be3ccb59dd`，Xcode build、静态、UI、Speech、home、paste 均成功，JUnit `10/10` 且 0 failures；`probe_mode=skip`，Koharu active artifact verdict `manifestMissing`，nextAction `stopUntilArtifactsProvided`。
- PR #237 fast [31207387731](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31207387731)：`validationProfile=fast`、`validationReason=pull_request_followup_no_synchronize`，`reusedFullValidationSha=d86f875d1040d69259b62b52754c73be3ccb59dd`、state `success`；Xcode skipped，不是新的编译证据。
- merge fast [31207465845](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31207465845)：merge SHA `3fe6e719e064fe261f97530a7f16ff3b39ea4903`，`validationReason=merge_reuses_successful_candidate_full_validation`、`receiptPropagationAllowed=true`，复用候选 full，Xcode skipped，不是新的编译证据。
- 文档 metadata follow-up [31207769023](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31207769023)：commit `395a162db4c0db3b5245f0487b2ecffa8025fb9a`，`smaldataIncrementalMetadataOnly=true`、`validationReason=smalldata_metadata_followup_reuses_parent_full_validation`，复用父 merge `3fe6e719e064fe261f97530a7f16ff3b39ea4903 / success`，`receiptPropagationAllowed=true`，仅 6 个文档文件变化，Xcode/UI/Speech 与漫画探针跳过，不是新的编译证据。
- receipt follow-up [31207848694](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31207848694)：commit `9de21ce1b10c01163c811b2df65edf8a022a7cf8`，`validationReason=smalldata_metadata_followup_reuses_parent_full_validation`，复用父文档 SHA `395a162db4c0db3b5245f0487b2ecffa8025fb9a / success`，`receiptPropagationAllowed=true`，仅 `update_log.md` 变化，Xcode/UI/Speech 与漫画探针跳过，不是新的编译证据。

## v3.174：日语竖排聚类间距收敛

日期：2026-08-08

状态：Agent X 延续 Koharu 的“先形成文字块再交给 crop/OCR”边界，修正 Vision 对日语竖排高而窄 line box 的聚类间距：`ImageOCRLayoutEngine.shouldMergeVertically` 保留原宽度信号与同列／重叠门控，增加两框平均高度的有界 gap 信号并设置上限，避免在既有 Japanese line-region reread 之前过早拆开同一列。候选 full、PR fast、merge fast 已完成云端验收并合入 `smalldata_test`。工程正式版本为 `MARKETING_VERSION=3.174`。候选 commit `49b987b3765e0df0c0511e30f955aa6aa7f487bf` 已通过 PR [#238](https://github.com/bengzhu/project1_lgbt_naxida/pull/238) 合入，merge SHA `5efc690d0f8c3b41282518a8bc76d12559efa114`；`main` 未触碰。

核心变更：

- 竖直 block 合并继续要求同列／水平重叠且 gap 不为负；宽度阈值保留原行为，新增平均高度 `heightLimit`，并把 `verticalGapLimit` 限制在 `0.08` 以内，降低高而窄 Vision line box 被提前拆列的机会。
- 横向合并、普通语言、整页 OCR、日语 crop／line reread、翻译与 renderer/export 入口保持既有边界；新增 `scripts/test-v3174-image-japanese-vertical-cluster-gap-contract.py` 并接入显式 CI 路由。
- 合同同时检查布局引擎与 Vision 的 block→crop 调用边界，禁止引入探针、Store、ground truth、active artifacts、metrics 或 `output` 依赖。

边界：该改动只调整普通图片日语竖排候选的 block 聚类间距，不加载 Manga OCR/PaddleOCR 权重，不读取真实 Koharu 工件或探针结果，不更新 `metrics/version_history.csv` 或仓库 `output/`。真实竖排图片质量 corpus、Speech corpus 与 Koharu 四件套仍缺失，不能据此声称日语 OCR、翻译、识别或 Koharu 质量提升。

云端证据：

- 候选 exact-SHA full [31208462786](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31208462786)：`validationProfile=full`、`validationReason=candidate_development_push`，commit `49b987b3765e0df0c0511e30f955aa6aa7f487bf`，Xcode build、静态、UI、Speech、home、paste 均成功，JUnit `10/10` 且 0 failures；`probe_mode=skip`，Koharu active artifact verdict `manifestMissing`，nextAction `stopUntilArtifactsProvided`。
- PR #238 fast [31209161098](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31209161098)：`validationProfile=fast`、`reusedFullValidationSha=49b987b3765e0df0c0511e30f955aa6aa7f487bf`、state `success`；Xcode skipped，不是新的编译证据。
- merge fast [31209248983](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31209248983)：merge SHA `5efc690d0f8c3b41282518a8bc76d12559efa114`，`validationReason=merge_reuses_successful_candidate_full_validation`、`receiptPropagationAllowed=true`，复用候选 full，Xcode skipped，不是新的编译证据。
- 文档 metadata follow-up [31209502813](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31209502813)：commit `7ee490368d6ae72c52399a1a02e609245b3cd378`，`validationReason=smalldata_metadata_followup_reuses_parent_full_validation`，复用 merge SHA `5efc690d0f8c3b41282518a8bc76d12559efa114 / success`，`receiptPropagationAllowed=true`，仅上述 6 个文档文件变化，Xcode/UI/Speech 与漫画探针跳过，JUnit `10/10`；不是新的编译证据。

## v3.175：日语竖排字体尺寸 crop padding

日期：2026-08-08

状态：Agent X 按 Koharu `detected_font_size_px` 的 crop 边界继续收敛普通图片日语竖排 reread。日语文字块与 line crop 现在读取源图片像素尺寸，以 `min(widthPixels, heightPixels)` 作为保守字体大小，计算 `base=max(font×0.08, 2px)`、竖排水平 padding `max(font×0.18, base)`、垂直 padding `max(font×0.12, base)`，再映射回归一化 Vision 坐标；缺少或非法尺寸时回退既有安全常量。工程正式版本为 `MARKETING_VERSION=3.175`。候选 commit `e47014bb6cc68ec70029b3000d0b84c0156fe21e` 已通过 PR [#239](https://github.com/bengzhu/project1_lgbt_naxida/pull/239) 合入，merge SHA `7b7a57b4d091fc3bd10305a6997e9dd24fba42ba`；`main` 未触碰。

核心变更：

- `recognizeJapaneseVerticalCrops` 与 `recognizeJapaneseVerticalLineCrops` 将源图片 `imageSize` 传入共享 `koharuVerticalCropPadding`，block／line reread 使用同一字体尺寸与方向 padding 公式，并保留归一化单轴上限和无源尺寸 fallback。
- 新增 `scripts/test-v3175-image-japanese-font-size-padding-contract.py` 并接入显式 UI/full fail-fast；v3.160、v3.161、v3.162、v3.174 与更早合同继续回归，历史合同接受共享 helper 的等价调用。

边界：该改动只调整普通图片日语 block／line crop 的边界估计，不加载 Manga OCR/PaddleOCR 权重，不改变普通语言、整页 OCR、翻译、renderer/export、Store、探针、Koharu active gate、metrics 或 `output`。`test/jap.jpg` 仍只作合同 fixture；真实竖排图片质量 corpus、Speech corpus 与 Koharu 四件套仍缺失，readiness 必须保持 `manifestMissing / stopUntilArtifactsProvided`，不能据此声称日语 OCR、翻译、识别或 Koharu 质量提升。

云端证据：

- 候选 exact-SHA full [31210073265](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31210073265)：`validationProfile=full`、`validationReason=candidate_development_push`，commit `e47014bb6cc68ec70029b3000d0b84c0156fe21e`，Xcode build、静态、UI、Speech、home、paste 均成功，JUnit `10/10` 且 0 failures；`probe_mode=skip`，Koharu active artifact verdict `manifestMissing`，nextAction `stopUntilArtifactsProvided`。
- PR #239 fast [31210705708](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31210705708)：`validationProfile=fast`、`validationReason=pull_request_followup_no_synchronize`，`reusedFullValidationSha=e47014bb6cc68ec70029b3000d0b84c0156fe21e`、state `success`；Xcode skipped，不是新的编译证据。
- merge fast [31210782269](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31210782269)：merge SHA `7b7a57b4d091fc3bd10305a6997e9dd24fba42ba`，`validationReason=merge_reuses_successful_candidate_full_validation`、`receiptPropagationAllowed=true`，复用候选 full，Xcode skipped，不是新的编译证据。
- 文档 metadata follow-up [31211090597](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31211090597)：commit `cabb3aefe5af8840006207d793bdee5efe823276`，`validationProfile=fast`、`validationReason=smalldata_metadata_followup_reuses_parent_full_validation`，复用父 merge `7b7a57b4d091fc3bd10305a6997e9dd24fba42ba / success`，`receiptPropagationAllowed=true`，仅上述 6 个文档文件变化，Xcode/UI/Speech 与漫画探针跳过，不是新的编译证据。

## v3.176：日语竖排 perspective line reading order

日期：2026-08-08

状态：Agent X 继续按 Koharu `extract_text_block_regions`／`warp_line_region` 的“先得到一个 line region，再交给 OCR”边界，修正普通图片日语竖排四点 perspective line crop 的多 observation 拼接方向。Koharu 的竖排 line 会先 `rotate270` 成可识别的横向 crop；AITRANS 现在把 90° pass 的旋转图 x 轴视为正向，把 270° pass 的 x 轴视为反向，同一 x 位置才用 y 与既有日语 observation score 稳定排序，避免 Vision 拆分一条 line 后把文字顺序反转。候选 commit `6a61068f292e4e842b570a455eb357bd5b9a7c40` 已通过 PR [#240](https://github.com/bengzhu/project1_lgbt_naxida/pull/240) 合入，merge SHA `eaa523f4d29f8be9e7e2f16131bbc21a9363706f`；工程正式版本为 `MARKETING_VERSION=3.176`，`main` 未触碰。

核心变更：

- `recognizeJapanesePerspectiveLineCrop` 改用共享 `orderedJapanesePerspectiveLineObservations`：90° 读取 x 递增、270° 读取 x 递减，接近同一 x 时以 y 递增和 `isBetterJapaneseObservation` 做稳定 tie-breaker；单 observation 保持原样返回。
- 新增 `scripts/test-v3176-image-japanese-line-reading-order-contract.py` 并接入显式 UI/full fail-fast；v3.162、v3.175 与更早合同继续回归，四点 warp、像素预算、语言后处理、坐标映射与失败 fallback 未改变。

边界：该改动只影响普通图片日语 perspective line reread 的文字组装顺序，不加载 Manga OCR/PaddleOCR 权重，不改变普通语言、整页 OCR、翻译、renderer/export、Store、探针、Koharu active gate、metrics 或 `output`。`test/jap.jpg` 继续只作合同 fixture；真实竖排图片质量 corpus、Speech corpus 与 Koharu 四件套仍缺失，readiness 必须保持 `manifestMissing / stopUntilArtifactsProvided`，不能据此声称日语 OCR、翻译、识别或 Koharu 质量提升。

云端证据：

- 候选 exact-SHA full [31211585649](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31211585649)：`validationProfile=full`、`validationReason=candidate_development_push`，commit `6a61068f292e4e842b570a455eb357bd5b9a7c40`，Xcode build、静态、UI、Speech、home、paste 均成功，JUnit `10/10` 且 0 failures；`probe_mode=skip`，Koharu active artifact verdict `manifestMissing`，nextAction `stopUntilArtifactsProvided`。
- PR #240 fast [31212154910](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31212154910)：`validationProfile=fast`、`validationReason=pull_request_followup_no_synchronize`，`reusedFullValidationSha=6a61068f292e4e842b570a455eb357bd5b9a7c40`、state `success`；Xcode skipped，不是新的编译证据。
- merge fast [31212217877](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31212217877)：merge SHA `eaa523f4d29f8be9e7e2f16131bbc21a9363706f`，`validationReason=merge_reuses_successful_candidate_full_validation`、`receiptPropagationAllowed=true`，复用候选 full，Xcode skipped，不是新的编译证据。
- 文档 metadata follow-up [31212395806](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31212395806)：commit `f128627345a68dff5c36fcc50bfa7e1d1c2ba0ed`，`smaldataIncrementalMetadataOnly=true`、`validationReason=smalldata_metadata_followup_reuses_parent_full_validation`，复用父 merge `eaa523f4d29f8be9e7e2f16131bbc21a9363706f / success`，`receiptPropagationAllowed=true`，仅上述 6 个文档文件变化，Xcode/UI/Speech 与漫画探针跳过，不是新的编译证据。

## v3.177：日语紧凑竖排文字列方向判定

日期：2026-08-08

状态：Agent X 继续按 Koharu 的“检测／方向信息先形成文字块，再进入 crop 与 OCR”分层，补齐 Vision 在小尺寸日语截图中把多字竖排列压成紧凑框时的方向缺口。`ImageOCRLayoutEngine.layout` 现在把 `prefersMangaReadingOrder` 传给 `resolveDirection`；仅当日语 manga-order、CJK 字符至少 2 个、`verticalRatio >= 1.35`、`height >= 0.022`、存在列邻居且不存在横排行邻居时，标记 `cjkCompactColumnTextRun`，让该候选继续进入既有 Koharu 风格 block／line crop reread。简中、非日语、宽框横排、短单字列、孤立高框和原有高框 fallback 保持边界。候选 commit `9777d167cca71deb753f5d0f721f6c2f9f2af48f` 已通过 PR [#241](https://github.com/bengzhu/project1_lgbt_naxida/pull/241) 合入，merge SHA `f2c8a33ba66666a69a941d24fb5d8d78284b1695`；工程正式版本为 `MARKETING_VERSION=3.177`，`main` 未触碰。

核心变更：

- `resolveDirection` 新增日语偏好参数并保留默认调用链；compact gate 只在 `prefersMangaReadingOrder` 为真时生效，复用已有 CJK 字符统计、列／同行几何邻居和布局 confidence，最终仍由现有 vertical clustering、Koharu 风格 block／line crop、去重与翻译路径消费。
- 新增 `scripts/test-v3177-image-japanese-compact-vertical-direction-contract.py` 并接入显式 UI/full fail-fast；v3.176 及更早合同继续回归。该 layout-only 改动不加载 OCR 新模型、不读取探针报告、ground truth 或 `test/koharu_artifacts`，不改变普通语言、整页 OCR、翻译、renderer/export、Store、Koharu active gate、metrics 或 `output`。

边界：候选、PR、merge 均为 `probe_mode=skip`；真实 `test/koharu_artifacts/` 四件套、Speech corpus 与真实竖排图片质量 corpus 仍缺失，readiness 为 `manifestMissing / stopUntilArtifactsProvided`。没有新的 OCR／翻译／Koharu 指标，不更新 `metrics/version_history.csv` 或仓库 `output/`，不得据此声称日语 OCR、翻译、识别或 Koharu 质量提升。

云端证据：

- 候选 exact-SHA full [31213076831](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31213076831)：`validationProfile=full`、`validationReason=candidate_development_push`，commit `9777d167cca71deb753f5d0f721f6c2f9f2af48f`，Xcode build、静态、UI、Speech、home、paste 均成功，JUnit `10/10` 且 0 failures；`probe_mode=skip`，Koharu active artifact verdict `manifestMissing`，nextAction `stopUntilArtifactsProvided`。
- PR #241 fast [31213569259](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31213569259)：`validationProfile=fast`、`validationReason=pull_request_followup_no_synchronize`，`reusedFullValidationSha=9777d167cca71deb753f5d0f721f6c2f9f2af48f`、state `success`；Xcode/UI/Speech skipped，不是新的编译证据。
- merge fast [31213642909](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31213642909)：merge SHA `f2c8a33ba66666a69a941d24fb5d8d78284b1695`，`validationReason=merge_reuses_successful_candidate_full_validation`、`receiptPropagationAllowed=true`，复用候选 full，Xcode/UI/Speech skipped，不是新的编译证据。
- 文档 metadata follow-up [31213886681](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31213886681)：commit `f2512d4b9bbd9b6c016bafd0ec0c3970228ff612`，`validationProfile=fast`、`validationReason=smalldata_metadata_followup_reuses_parent_full_validation`，复用父 merge `f2c8a33ba66666a69a941d24fb5d8d78284b1695 / success`，`receiptPropagationAllowed=true`，仅上述 6 个文档文件变化，Xcode/UI/Speech 与漫画探针跳过，不是新的编译证据。

## v3.178：日语紧凑竖排文字块 crop 门控

日期：2026-08-08

状态：Agent X 延续 Koharu 的 `TextRegion → crop_text_block_bbox → OCR` 分层，把 v3.177 已识别出的 `cjkCompactColumnTextRun` 紧凑日语竖排文字块接入普通图片的既有 block crop／OCR 复读。标准高竖候选仍要求 `aspectRatio >= 1.45`、`height >= 0.04`；只有方向原因为 `cjkCompactColumnTextRun` 的日语竖排块才受限放宽到 `aspectRatio >= 1.20`、`height >= 0.022`，总预算仍为最多 16 个 block，继续沿用裁剪扩展、预处理、90°／270° fallback、坐标映射与去重。候选 commit `ec80c63d1b0d25903f0d462a020dec6bca768f94` 已通过 PR [#242](https://github.com/bengzhu/project1_lgbt_naxida/pull/242) 合入，merge SHA `4f6aeca133c9684c6800ec795a9f0fac4f24fdca`；工程正式版本为 `MARKETING_VERSION=3.178`，`main` 未触碰。

核心变更：

- `recognizeJapaneseVerticalCrops` 保留原标准候选，并读取 `directionReason` 的 `cjkCompactColumnTextRun` 标记；compact gate 只放宽尺寸，不放宽 `.vertical` 方向、日语路径或 16 块预算。
- compact 与标准 block 都继续进入 `expandedVerticalCropRect`、`prepareJapaneseCropForVision`、既有方向 fallback、原图坐标映射和 observation 去重；Swift crop 入口保持与 Koharu `crop_text_block_bbox` 的边界对应。
- 新增 `scripts/test-v3178-image-japanese-compact-block-crop-contract.py` 并接入显式 UI/full fail-fast；v3.177 及更早合同继续回归。合同只检查仓库内 Swift／CI／fixture，不依赖云端不存在的 `reference/koharu-main` 路径。

边界：该改动只扩大普通图片日语紧凑竖排 block crop 的受限候选范围，不加载 Manga OCR/PaddleOCR 权重，不读取探针报告、ground truth 或真实 Koharu 工件，不改变普通语言、整页 OCR、翻译、renderer/export、Store、Koharu active gate、metrics 或 `output`。`test/jap.jpg` 仍只作合同 fixture；真实竖排图片质量 corpus、Speech corpus 与 Koharu 四件套仍缺失，readiness 必须保持 `manifestMissing / stopUntilArtifactsProvided`，不能据此声称日语 OCR、翻译、识别或 Koharu 质量提升。

云端证据：

- 候选 exact-SHA full [31214729647](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31214729647)：`validationProfile=full`、`validationReason=candidate_development_push`，commit `ec80c63d1b0d25903f0d462a020dec6bca768f94`，Xcode build、静态、UI、Speech、home、paste 均成功，JUnit `10/10` 且 0 failures；`probe_mode=skip`，Koharu active artifact verdict `manifestMissing`，nextAction `stopUntilArtifactsProvided`。
- PR #242 fast [31215410769](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31215410769)：`validationProfile=fast`、`validationReason=pull_request_followup_no_synchronize`，`reusedFullValidationSha=ec80c63d1b0d25903f0d462a020dec6bca768f94`、state `success`；Xcode/UI/Speech skipped，不是新的编译证据。
- merge fast [31215485897](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31215485897)：merge SHA `4f6aeca133c9684c6800ec795a9f0fac4f24fdca`，`validationReason=merge_reuses_successful_candidate_full_validation`、`receiptPropagationAllowed=true`，复用候选 full，Xcode/UI/Speech skipped，不是新的编译证据。
- 文档 metadata follow-up [31215692968](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31215692968)：commit `5a5727dc918d7f9a17aabeab9c10809a9cb877f1`，`validationProfile=fast`、`validationReason=smalldata_metadata_followup_reuses_parent_full_validation`，复用父 merge `4f6aeca133c9684c6800ec795a9f0fac4f24fdca / success`，`receiptPropagationAllowed=true`，仅上述 6 个文档文件变化，Xcode/UI/Speech 与漫画探针跳过，JUnit `10/10`；不是新的编译证据。

## v3.179：日语 Koharu 后处理顺序对齐

日期：2026-08-08

状态：Agent X 对齐 `reference/koharu-main/koharu-ml/src/manga_ocr/mod.rs` 的 `post_process` 顺序，修正普通图片日语 OCR 在压缩点号／中点串后的全角化边界。AITRANS 现在先移除空白、把省略号统一成 `...`、将连续 `.`／`・` 压缩到中间字符串，再将该中间字符串中的 ASCII 标点统一映射为全角；压缩点号不再直接留在半角形态。候选 commit `c16e5593ef63113e2d3ba5ef1b72d7a09ee2396a` 已通过 PR [#243](https://github.com/bengzhu/project1_lgbt_naxida/pull/243) 合入，merge SHA `5f3c0aa1f45d9cee9774db4d0020370666b69273`；工程正式版本为 `MARKETING_VERSION=3.179`，`main` 未触碰。

核心变更：

- `postProcessJapaneseOCRText` 显式拆成 collapse 与 halfwidth-to-fullwidth 两阶段，整页、90°／270°、block crop、axis line 与 perspective line reread 均继续使用同一 helper；普通语言保留 top-1 与原后处理路径。
- 新增 `scripts/test-v3179-image-japanese-koharu-postprocess-order-contract.py` 并接入显式 UI/full fail-fast；v3.178 及更早合同继续回归。

边界：该改动只修正普通图片日语 OCR 文本归一化顺序，不加载 Manga OCR/PaddleOCR 权重，不读取探针报告、ground truth 或真实 Koharu 工件，不改变识别几何、布局、翻译、renderer/export、Store、Koharu active gate、metrics 或 `output`。`test/jap.jpg` 仍只作合同 fixture；真实竖排图片质量 corpus、Speech corpus 与 Koharu 四件套仍缺失，readiness 必须保持 `manifestMissing / stopUntilArtifactsProvided`，不能据此声称日语 OCR、翻译、识别或 Koharu 质量提升。

云端证据：

- 候选 exact-SHA full [31216151856](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31216151856)：`validationProfile=full`、`validationReason=candidate_development_push`，commit `c16e5593ef63113e2d3ba5ef1b72d7a09ee2396a`，Xcode build、静态、UI、Speech、home、paste 均成功，JUnit `10/10` 且 0 failures；`probe_mode=skip`，Koharu active artifact verdict `manifestMissing`，nextAction `stopUntilArtifactsProvided`。
- PR #243 fast [31216723888](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31216723888)：`validationProfile=fast`、`validationReason=pull_request_followup_no_synchronize`，`reusedFullValidationSha=c16e5593ef63113e2d3ba5ef1b72d7a09ee2396a`、state `success`；Xcode/UI/Speech skipped，不是新的编译证据。
- merge fast [31216783591](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31216783591)：merge SHA `5f3c0aa1f45d9cee9774db4d0020370666b69273`，`validationReason=merge_reuses_successful_candidate_full_validation`、`receiptPropagationAllowed=true`，复用候选 full，Xcode/UI/Speech skipped，不是新的编译证据。
- 文档 metadata follow-up [31216962165](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31216962165)：commit `3d345da6c3559f4964258c6088679d4b297c3af3`，`validationProfile=fast`、`validationReason=smalldata_metadata_followup_reuses_parent_full_validation`，复用父 merge `5f3c0aa1f45d9cee9774db4d0020370666b69273 / success`，`receiptPropagationAllowed=true`，仅上述 6 个文档文件变化，Xcode/UI/Speech 与漫画探针跳过，JUnit `10/10`；不是新的编译证据。

## v3.180：日语 perspective line warp 局部 bbox

日期：2026-08-08

状态：Agent X 继续迁移 Koharu `TextRegion.line_polygons → warp_line_region → OCR` 的几何边界，修正普通图片日语竖排 perspective line reread 直接对整张源图执行 `CIPerspectiveCorrection` 的缺口。AITRANS 现在先按四点 line polygon 求与源图相交的 bbox，裁出局部源图，再把四点平移到局部坐标进行透视校正；保留最多 24 个 line 候选、每页 16M warp 像素预算、既有灰度／放大、方向 fallback、原图映射与去重。候选 commit `eb522b28c1e9649278342f227aaef03995d67a41` 已通过 PR [#244](https://github.com/bengzhu/project1_lgbt_naxida/pull/244) 合入，merge SHA `54b4cf750615efe54962f4247c72003d6d04f761`；工程正式版本为 `MARKETING_VERSION=3.180`，`main` 未触碰。

核心变更：

- `perspectiveCorrectedLineImage` 保留四点凸性、尺寸和失败 guard，新增 `imageBounds`／`cropBounds`／`croppedImage`，所有 `inputTop*`／`inputBottom*` 点改用相对局部图的 `localPoints`，让透视输入与 Koharu `warp_line_region` 先 crop 再 warp 的边界一致。
- perspective line 仍只作为日语 line-region reread 候选，轴对齐 line、block crop、普通语言、布局、翻译、renderer/export、Store 与探针路径不变；新增 `scripts/test-v3180-image-japanese-line-warp-bbox-contract.py` 并接入显式 UI/full fail-fast。

边界：该改动只缩小普通图片日语 perspective line 的输入像素范围，不加载 Manga OCR/PaddleOCR 权重，不读取探针报告、ground truth 或真实 Koharu 工件，不改变 OCR 模型、识别语言、翻译、renderer/export、Koharu active gate、metrics 或 `output`。`test/jap.jpg` 仍只作合同 fixture；真实竖排图片质量 corpus、Speech corpus 与 Koharu 四件套仍缺失，readiness 必须保持 `manifestMissing / stopUntilArtifactsProvided`，不能据此声称日语 OCR、翻译、识别或 Koharu 质量提升。

云端证据：

- 候选 exact-SHA full [31217320435](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31217320435)：`validationProfile=full`、`validationReason=candidate_development_push`，commit `eb522b28c1e9649278342f227aaef03995d67a41`，Xcode build、静态、UI、Speech、home、paste 均成功，JUnit `10/10` 且 0 failures；`probe_mode=skip`，Koharu active artifact verdict `manifestMissing`，nextAction `stopUntilArtifactsProvided`。
- PR #244 fast [31217749775](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31217749775)：`validationProfile=fast`、`validationReason=pull_request_followup_no_synchronize`，`reusedFullValidationSha=eb522b28c1e9649278342f227aaef03995d67a41`、state `success`；Xcode/UI/Speech skipped，不是新的编译证据。
- merge fast [31217813652](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31217813652)：merge SHA `54b4cf750615efe54962f4247c72003d6d04f761`，`validationReason=merge_reuses_successful_candidate_full_validation`、`receiptPropagationAllowed=true`，复用候选 full，Xcode/UI/Speech skipped，不是新的编译证据。
- 文档 metadata follow-up [31217999166](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31217999166)：commit `ca0232db3a59fcac8149e7e84099459c2d936371`，`validationProfile=fast`、`validationReason=smalldata_metadata_followup_reuses_parent_full_validation`，复用父 merge `54b4cf750615efe54962f4247c72003d6d04f761 / success`，`receiptPropagationAllowed=true`，仅上述 6 个文档文件变化，Xcode/UI/Speech 与漫画探针跳过，JUnit `10/10`；不是新的编译证据。

## v3.181：日语竖排 perspective line 路径去重

日期：2026-08-08

状态：Agent X 继续对齐 Koharu `warp_line_region` 的 line-region 边界，修正普通图片日语竖排 reread 同时执行 perspective 与轴对齐路径而造成重复 Vision OCR 的缺口。AITRANS 现在仅在 perspective line 结果成功且不需要方向 fallback 时记录该候选已覆盖；与其 `lineRegionRect`／`rect` 重叠比达到 `0.72` 的轴对齐候选跳过，弱或失败的 perspective 仍保留轴对齐与方向 fallback。最多 24 个 line 候选、每页 16M warp 像素预算、灰度／放大、坐标映射、日语后处理与去重保持不变。候选 commit `e24ce08b798b1f205a4d812e626d27ba801db1de` 已通过 PR [#245](https://github.com/bengzhu/project1_lgbt_naxida/pull/245) 合入，merge SHA `1107998858e3879750cba8dc8a27248ad1497589`；工程正式版本为 `MARKETING_VERSION=3.181`，`main` 未触碰。

核心变更：

- `recognizeJapaneseVerticalLineCrops` 新增 `perspectiveCoveredCandidates`，仅收集 `recognizeJapanesePerspectiveLineCrop` 返回且 `needsJapaneseOrientationFallback([perspective])` 为假的强 perspective 结果；轴对齐循环使用 `isSameJapaneseLineRegion`，重叠比达到 `0.72` 即跳过重复读取。
- perspective 失败、空结果、低日语脚本／低置信度而需方向 fallback 时不登记覆盖，既有 axis reread 与 90°／270° fallback 继续运行；候选上限、warp 像素预算、原图 mapping、最终布局与翻译／渲染路径未改变。
- 新增 `scripts/test-v3181-image-japanese-line-path-dedupe-contract.py` 并接入显式 UI/full fail-fast；v3.180 及更早合同继续回归。

边界：该改动只影响普通图片日语 perspective／轴对齐 line reread 的候选融合，不加载 Manga OCR/PaddleOCR 权重，不读取探针报告、ground truth 或真实 Koharu 工件，不改变普通语言、block crop、整页 OCR、布局、翻译、renderer/export、Store、Koharu active gate、metrics 或 `output`。`test/jap.jpg` 仍只作合同 fixture；真实竖排图片质量 corpus、Speech corpus 与 Koharu 四件套仍缺失，readiness 必须保持 `manifestMissing / stopUntilArtifactsProvided`，不能据此声称日语 OCR、翻译、识别或 Koharu 质量提升。

云端证据：

- 候选 exact-SHA full [31218314967](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31218314967)：`validationProfile=full`、`validationReason=candidate_development_push`，commit `e24ce08b798b1f205a4d812e626d27ba801db1de`，Xcode build、静态、UI、Speech、home、paste 均成功，JUnit `10/10` 且 0 failures；`probe_mode=skip`，Koharu active artifact verdict `manifestMissing`，nextAction `stopUntilArtifactsProvided`。
- PR #245 fast [31218876431](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31218876431)：`validationProfile=fast`、`validationReason=pull_request_followup_no_synchronize`，`reusedFullValidationSha=e24ce08b798b1f205a4d812e626d27ba801db1de`、state `success`；Xcode/UI/Speech skipped，不是新的编译证据。
- merge fast [31218932836](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31218932836)：merge SHA `1107998858e3879750cba8dc8a27248ad1497589`，`validationReason=merge_reuses_successful_candidate_full_validation`、`receiptPropagationAllowed=true`，复用候选 full，Xcode/UI/Speech skipped，不是新的编译证据。
- 文档 metadata follow-up [31219219340](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31219219340)：commit `dd050bb20debf514898f129db8eeccb61cbe3c2d`，`validationProfile=fast`、`validationReason=smalldata_metadata_followup_reuses_parent_full_validation`，复用父 merge `1107998858e3879750cba8dc8a27248ad1497589 / success`，`receiptPropagationAllowed=true`，仅六份项目文档变化（`AGENTS.md`、`README.md`、`md/flow/flow.md`、`md/flow/flowchart.md`、`md/test/test.md`、`update_log.md`），Xcode/UI/Speech 与漫画探针跳过，JUnit `10/10`；不是新的编译证据。

## v3.182：日语竖排合成 line 替代 axis reread

日期：2026-08-08

状态：Agent X 继续按 Koharu `TextRegion → extract_text_block_regions → OCR` 分层，修正 v3.172 合成日语竖排 line proxy 仍与原始 axis candidate 并行读取的缺口。AITRANS 现在先形成满足短日语片段、同列、bounded gap 与竖排形状门控的 `synthesizedCandidates`，再建立 `axisSeeds`：若原始候选与合成 line 的 `lineRegionRect`／`rect` 重叠比达到 `0.72`，只从 axis bbox reread 中移除它；原始 `uniqueCandidates.prefix(24)` 仍保留在 perspective quad path，弱／失败 perspective 的方向 fallback、每页 16M warp 像素预算、灰度／放大、坐标映射与最终去重保持不变。候选 commit `42ad3abf8deba67d11b4fd3a93b16a1f09756657` 已通过 PR [#246](https://github.com/bengzhu/project1_lgbt_naxida/pull/246) 合入，merge SHA `fb97ce105e5ae2d8fdda3d2acae631c86513be02`；工程正式版本为 `MARKETING_VERSION=3.182`，`main` 未触碰。

核心变更：

- `recognizeJapaneseVerticalLineCrops` 保留 `perspectiveCandidates = uniqueCandidates.prefix(24)`，合成候选之后使用几何覆盖过滤构成 `axisSeeds`，再以最多 24 条 axis line 进入方向感知 crop／OCR；这使合成 line 真正承担 Koharu line-region 的 bbox reread，同时不丢失原始四点 geometry。
- v3.172 与 v3.173 历史合同改为接受 `axisSeeds` 的等价共享 helper，避免把实现重构误判为缺失日语候选融合；新增 `scripts/test-v3182-image-japanese-synthetic-line-replacement-contract.py` 并接入显式 UI/full fail-fast。

边界：该改动只影响普通图片日语竖排 line reread 的 axis candidate 选择，不加载 Manga OCR/PaddleOCR 权重，不读取探针报告、ground truth 或真实 Koharu 工件，不改变普通语言、block crop、整页 OCR、布局、翻译、renderer/export、Store、Koharu active gate、metrics 或 `output`。`test/jap.jpg` 仍只作合同 fixture；真实竖排图片质量 corpus、Speech corpus 与 Koharu 四件套仍缺失，readiness 必须保持 `manifestMissing / stopUntilArtifactsProvided`，不能据此声称日语 OCR、翻译、识别或 Koharu 质量提升。

云端证据：

- 候选 exact-SHA full [31220601488](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31220601488)：最终验收 commit `42ad3abf8deba67d11b4fd3a93b16a1f09756657`，`validationProfile=full`、`validationReason=candidate_development_push`，Xcode build、静态、UI、Speech、home、paste 均成功，JUnit `10/10` 且 0 failures；`probe_mode=skip`，Koharu active artifact verdict `manifestMissing`，nextAction `stopUntilArtifactsProvided`。此前 `31219636547`、`31220164501` 仅因历史合同未接受 `axisSeeds` 而失败，不作为验收证据。
- PR #246 fast [31221025113](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31221025113)：`validationProfile=fast`、`validationReason=pull_request_followup_no_synchronize`，`reusedFullValidationSha=42ad3abf8deba67d11b4fd3a93b16a1f09756657`、state `success`；Xcode/UI/Speech skipped，不是新的编译证据。
- merge fast [31221074919](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31221074919)：merge SHA `fb97ce105e5ae2d8fdda3d2acae631c86513be02`，`validationReason=merge_reuses_successful_candidate_full_validation`、`receiptPropagationAllowed=true`，复用候选 full，Xcode/UI/Speech skipped，不是新的编译证据。
- 文档 metadata follow-up [31221262235](https://github.com/bengzhu/project1_lgbt_naxida/actions/runs/31221262235)：commit `c3acf5b57bd8b3a6306b8fc69b92e1490cb0bcc1`，`validationProfile=fast`、`validationReason=smaldata_metadata_followup_reuses_parent_full_validation`，复用父 merge `fb97ce105e5ae2d8fdda3d2acae631c86513be02 / success`，`receiptPropagationAllowed=true`，仅六份项目文档变化（`AGENTS.md`、`README.md`、`md/flow/flow.md`、`md/flow/flowchart.md`、`md/test/test.md`、`update_log.md`），Xcode/UI/Speech 与漫画探针跳过，JUnit `10/10`；不是新的编译证据。
