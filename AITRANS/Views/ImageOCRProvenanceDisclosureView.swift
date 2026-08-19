import SwiftUI

/// Read-only provenance details for blocks already marked for review. This
/// view never selects a candidate, changes Store state, or exposes the
/// ephemeral owner/benchmark identity used by the OCR pipeline.
struct ImageOCRProvenanceDisclosureView: View {
    let block: ImageTranslationBlock

    @State private var isExpanded = false

    var body: some View {
        if shouldDisplay,
           let provenance = block.ocrProvenance {
            DisclosureGroup(isExpanded: $isExpanded) {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
                    LabeledContent("记录状态", value: "只读；不改变 OCR、翻译或复查")
                    LabeledContent("融合语义", value: selectionReasonLabel(provenance.selectionReason))

                    ForEach(Array(provenance.candidates.enumerated()), id: \.offset) { index, candidate in
                        candidateRow(index: index, candidate: candidate)
                    }
                }
                .font(.caption)
                .padding(.top, AppTheme.Spacing.compact)
            } label: {
                Label("识别来源（只读）", systemImage: "info.circle")
                    .font(.caption.bold())
            }
            .foregroundStyle(Color.appTextSecondary)
            .accessibilityLabel("识别来源，只读")
            .accessibilityValue(accessibilityValue(for: provenance))
            .accessibilityHint("仅查看当前低置信或方向待定文字块的 OCR 来源；不会选择候选或改变复查状态")
        }
    }

    private var shouldDisplay: Bool {
        ImageOCRResultSummary.requiresReview(block)
            && block.ocrProvenance?.candidates.isEmpty == false
    }

    private func candidateRow(
        index: Int,
        candidate: ImageOCRCandidateProvenance
    ) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
            Text("候选 \(index + 1)：\(engineLabel(candidate.engine)) · \(roleLabel(candidate.role))")
                .bold()
            Text("裁剪：\(cropLabel(candidate.cropVariant))；几何：\(geometryLabel(candidate.geometrySource))")
            Text("引擎内部置信度：\(Double(candidate.rawConfidence), format: .number.precision(.fractionLength(0...3)))（不跨引擎比较）")
            if let detectorConfidence = candidate.detectorConfidence {
                Text("检测器置信度：\(Double(detectorConfidence), format: .number.precision(.fractionLength(0...3)))")
            }
            if candidate.rotationApplied != 0 {
                Text("识别方向变换：\(candidate.rotationApplied)°")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppTheme.Spacing.compact)
        .background(Color.appCanvas, in: .rect(cornerRadius: AppTheme.Radius.control))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("候选 \(index + 1)")
        .accessibilityValue(candidateAccessibilityValue(candidate))
    }

    private func accessibilityValue(
        for provenance: ImageOCRBlockProvenance
    ) -> String {
        "\(provenance.candidates.count) 条候选记录；\(selectionReasonLabel(provenance.selectionReason))"
    }

    private func candidateAccessibilityValue(
        _ candidate: ImageOCRCandidateProvenance
    ) -> String {
        "\(engineLabel(candidate.engine))，\(roleLabel(candidate.role))，裁剪 \(cropLabel(candidate.cropVariant))，几何 \(geometryLabel(candidate.geometrySource))"
    }

    private func engineLabel(_ engine: ImageOCREngineID) -> String {
        switch engine {
        case .vision: "Vision"
        case .bundledMangaOCR: "Bundled Manga OCR"
        case .fusion: "既有融合"
        }
    }

    private func roleLabel(_ role: ImageOCRCandidateRole) -> String {
        switch role {
        case .page: "整页"
        case .crop: "文字块裁剪"
        case .verticalLine: "竖排行"
        case .detectorTextRegion: "检测文字区"
        case .geometryOnly: "几何候选"
        case .tileFallback: "分片回退"
        case .blockFallback: "整块回退"
        case .layoutBlock: "布局文字块"
        }
    }

    private func cropLabel(_ crop: ImageOCRCropVariant) -> String {
        switch crop {
        case .page: "整页"
        case .detectorBBox: "检测框"
        case .blockBBox: "文字块框"
        case .lineBBox: "行框"
        case .lineQuad: "行四边形"
        case .tile: "分片"
        case .none: "无"
        }
    }

    private func geometryLabel(_ geometry: ImageOCRGeometrySource) -> String {
        switch geometry {
        case .none: "无"
        case .bbox: "矩形框"
        case .lineQuad: "行四边形"
        }
    }

    private func selectionReasonLabel(
        _ reason: ImageOCRSelectionReason
    ) -> String {
        switch reason {
        case .shadowOnly: "仅影子记录"
        case .selectedByExistingFusion: "沿用既有融合"
        case .existingLayoutFusion: "沿用既有布局融合"
        case .scopedRerecognition: "单块重新识别"
        }
    }
}
