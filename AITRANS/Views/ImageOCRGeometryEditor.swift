import SwiftUI

/// Accessible, review-scoped editor for one normalized OCR bbox. The editor
/// never starts work while the user is dragging; the caller decides when the
/// committed rectangle should trigger the existing scoped rerecognition task.
struct ImageOCRGeometryEditor: View {
    @Environment(\.dismiss) private var dismiss

    let block: ImageTranslationBlock
    let onCommit: (NormalizedImageRect) -> Void

    @State private var draft: NormalizedImageRect
    @State private var moveGestureStart: NormalizedImageRect?
    @State private var resizeGestureStart: NormalizedImageRect?

    init(
        block: ImageTranslationBlock,
        onCommit: @escaping (NormalizedImageRect) -> Void
    ) {
        self.block = block
        self.onCommit = onCommit
        _draft = State(initialValue: Self.clamped(
            block.boundingBox.normalizedToUnit()
                ?? NormalizedImageRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2)
        ))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.section) {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
                        Text("调整当前 OCR 文字框")
                            .font(.headline)
                        Text("拖动框体移动位置，拖动右下角调整大小；只有提交后才会只重新识别此文字块。取消或失败不会改变原框、译文或复查进度。")
                            .font(.subheadline)
                            .foregroundStyle(Color.appTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    geometryCanvas

                    VStack(alignment: .leading, spacing: AppTheme.Spacing.control) {
                        Text("归一化坐标（左上为 0，右下为 1）")
                            .font(.subheadline.bold())
                        coordinateSlider(
                            title: "左边 X",
                            binding: xBinding,
                            hint: "调整文字框左边缘，不会超出图片"
                        )
                        coordinateSlider(
                            title: "上边 Y",
                            binding: yBinding,
                            hint: "调整文字框上边缘，不会超出图片"
                        )
                        coordinateSlider(
                            title: "宽度",
                            binding: widthBinding,
                            hint: "调整文字框宽度，至少保留有效面积"
                        )
                        coordinateSlider(
                            title: "高度",
                            binding: heightBinding,
                            hint: "调整文字框高度，至少保留有效面积"
                        )
                    }
                    .padding(AppTheme.Spacing.control)
                    .background(Color.appCanvas, in: .rect(cornerRadius: AppTheme.Radius.control))

                    Text("当前文字块：\((block.original.isEmpty ? "空 OCR 原文" : block.original))")
                        .font(.caption)
                        .foregroundStyle(Color.appTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    AppPrimaryButton(
                        title: "提交并重新识别此文字块",
                        systemImage: "text.viewfinder",
                        action: commit
                    )
                    .accessibilityHint("只提交当前归一化文字框；会复用现有 scoped OCR、翻译、取消和失败恢复边界")

                    if automaticBaseline != nil {
                        AppSecondaryButton(
                            title: "恢复自动文字框",
                            systemImage: "arrow.counterclockwise",
                            action: restoreAutomaticBaseline
                        )
                        .disabled(automaticBaselineIsCurrent)
                        .accessibilityHint("把编辑值恢复为 OCR 自动生成的文字框；尚未开始 OCR，提交后才会重新识别")
                    } else {
                        Text("此历史文字块没有可恢复的 automatic baseline；当前文字框仍可继续编辑。")
                            .font(.caption)
                            .foregroundStyle(Color.appTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.page)
                .padding(.vertical, AppTheme.Spacing.section)
            }
            .navigationTitle("调整文字框")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", role: .cancel) {
                        dismiss()
                    }
                    .accessibilityHint("关闭编辑器，不改变当前文字块")
                }
            }
        }
    }

    private var geometryCanvas: some View {
        GeometryReader { geometry in
            let canvasSize = CGSize(
                width: max(geometry.size.width, 1),
                height: max(geometry.size.height, 1)
            )

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: AppTheme.Radius.control)
                    .fill(Color.appSurfaceRaised)
                    .overlay {
                        RoundedRectangle(cornerRadius: AppTheme.Radius.control)
                            .stroke(Color.appBorder, lineWidth: 1)
                    }

                Text("图片坐标预览")
                    .font(.caption)
                    .foregroundStyle(Color.appTextSecondary)
                    .padding(AppTheme.Spacing.control)

                RoundedRectangle(cornerRadius: AppTheme.Radius.control)
                    .fill(Color.appAccent.opacity(0.18))
                    .overlay {
                        RoundedRectangle(cornerRadius: AppTheme.Radius.control)
                            .stroke(Color.appAccent, lineWidth: 2)
                    }
                    .overlay(alignment: .center) {
                        Text("当前框")
                            .font(.caption.bold())
                            .foregroundStyle(Color.appAccent)
                            .accessibilityHidden(true)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        Circle()
                            .fill(Color.appAccent)
                            .frame(width: AppTheme.Layout.minimumTarget, height: AppTheme.Layout.minimumTarget)
                            .overlay {
                                Image(systemName: "arrow.up.left.and.arrow.down.right")
                                    .font(.caption.bold())
                                    .foregroundStyle(Color.appCanvas)
                            }
                            .contentShape(Circle())
                            .accessibilityLabel("文字框右下角调整柄")
                            .accessibilityValue("宽度 \(formatted(draft.width))，高度 \(formatted(draft.height))")
                            .accessibilityHint("拖动以调整文字框宽度和高度")
                            .gesture(resizeGesture(in: canvasSize))
                            .offset(x: AppTheme.Layout.minimumTarget / 2, y: AppTheme.Layout.minimumTarget / 2)
                    }
                    .frame(
                        width: canvasSize.width * CGFloat(draft.width),
                        height: canvasSize.height * CGFloat(draft.height)
                    )
                    .offset(
                        x: canvasSize.width * CGFloat(draft.x),
                        y: canvasSize.height * CGFloat(draft.y)
                    )
                    .contentShape(Rectangle())
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("当前文字框")
                    .accessibilityValue(accessibilityGeometryValue)
                    .accessibilityHint("拖动以移动文字框；也可以使用下方坐标滑块精确调整")
                    .gesture(moveGesture(in: canvasSize))
            }
        }
        .frame(height: 260)
        .clipped(antialiased: false)
    }

    private func coordinateSlider(
        title: String,
        binding: Binding<Double>,
        hint: String
    ) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
            HStack {
                Text(title)
                Spacer(minLength: AppTheme.Spacing.compact)
                Text(formatted(binding.wrappedValue))
                    .monospacedDigit()
                    .foregroundStyle(Color.appTextSecondary)
            }
            Slider(value: binding, in: 0...1, step: 0.005)
                .accessibilityLabel(title)
                .accessibilityValue(formatted(binding.wrappedValue))
                .accessibilityHint(hint)
        }
    }

    private var xBinding: Binding<Double> {
        Binding(
            get: { draft.x },
            set: { draft = Self.clamped(NormalizedImageRect(x: $0, y: draft.y, width: draft.width, height: draft.height)) }
        )
    }

    private var yBinding: Binding<Double> {
        Binding(
            get: { draft.y },
            set: { draft = Self.clamped(NormalizedImageRect(x: draft.x, y: $0, width: draft.width, height: draft.height)) }
        )
    }

    private var widthBinding: Binding<Double> {
        Binding(
            get: { draft.width },
            set: { draft = Self.clamped(NormalizedImageRect(x: draft.x, y: draft.y, width: $0, height: draft.height)) }
        )
    }

    private var heightBinding: Binding<Double> {
        Binding(
            get: { draft.height },
            set: { draft = Self.clamped(NormalizedImageRect(x: draft.x, y: draft.y, width: draft.width, height: $0)) }
        )
    }

    private var accessibilityGeometryValue: String {
        "左 \(formatted(draft.x))，上 \(formatted(draft.y))，宽 \(formatted(draft.width))，高 \(formatted(draft.height))"
    }

    private func formatted(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(3)))
    }

    private func moveGesture(in canvasSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if moveGestureStart == nil {
                    moveGestureStart = draft
                }
                guard let start = moveGestureStart else { return }
                draft = Self.clamped(
                    NormalizedImageRect(
                        x: start.x + Double(value.translation.width / canvasSize.width),
                        y: start.y + Double(value.translation.height / canvasSize.height),
                        width: start.width,
                        height: start.height
                    )
                )
            }
            .onEnded { _ in
                moveGestureStart = nil
            }
    }

    private func resizeGesture(in canvasSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if resizeGestureStart == nil {
                    resizeGestureStart = draft
                }
                guard let start = resizeGestureStart else { return }
                draft = Self.clamped(
                    NormalizedImageRect(
                        x: start.x,
                        y: start.y,
                        width: start.width + Double(value.translation.width / canvasSize.width),
                        height: start.height + Double(value.translation.height / canvasSize.height)
                    )
                )
            }
            .onEnded { _ in
                resizeGestureStart = nil
            }
    }

    private var automaticBaseline: NormalizedImageRect? {
        block.automaticBoundingBox.map(Self.clamped)
    }

    private var automaticBaselineIsCurrent: Bool {
        guard let automaticBaseline else { return true }
        return automaticBaseline == draft
    }

    private func restoreAutomaticBaseline() {
        guard let automaticBaseline else { return }
        draft = automaticBaseline
    }

    private func commit() {
        onCommit(Self.clamped(draft))
        dismiss()
    }

    private static func clamped(_ rect: NormalizedImageRect) -> NormalizedImageRect {
        let x = min(max(rect.x.isFinite ? rect.x : 0, 0), 0.99)
        let y = min(max(rect.y.isFinite ? rect.y : 0, 0), 0.99)
        let widthLimit = max(0.01, 1 - x)
        let heightLimit = max(0.01, 1 - y)
        let width = min(max(rect.width.isFinite ? rect.width : 0.01, 0.01), widthLimit)
        let height = min(max(rect.height.isFinite ? rect.height : 0.01, 0.01), heightLimit)
        return NormalizedImageRect(x: x, y: y, width: width, height: height)
    }
}
