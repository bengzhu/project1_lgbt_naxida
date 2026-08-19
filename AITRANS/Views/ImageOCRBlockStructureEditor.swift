import SwiftUI

/// A review-only structure editor for a completed image session. It changes
/// block identity/order in the Store, but never runs OCR or translation while
/// the user is choosing an edit.
struct ImageOCRBlockStructureEditor: View {
    @Environment(\.dismiss) private var dismiss

    let blocks: [ImageTranslationBlock]
    let canEdit: Bool
    let split: (UUID, Int) -> Bool
    let merge: (UUID, UUID) -> Bool
    let move: (UUID, Int) -> Bool

    @State private var selectedBlockID: UUID?
    @State private var selectedMergeBlockIDs: Set<UUID> = []
    @State private var splitOffsetText = ""
    @State private var errorMessage: String?

    init(
        blocks: [ImageTranslationBlock],
        canEdit: Bool,
        split: @escaping (UUID, Int) -> Bool,
        merge: @escaping (UUID, UUID) -> Bool,
        move: @escaping (UUID, Int) -> Bool
    ) {
        self.blocks = blocks
        self.canEdit = canEdit
        self.split = split
        self.merge = merge
        self.move = move
        _selectedBlockID = State(initialValue: blocks.first?.id)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("选择文字块") {
                    if blocks.isEmpty {
                        Text("当前没有可编辑的文字块")
                            .foregroundStyle(Color.appTextSecondary)
                    } else {
                        ForEach(blocks.enumerated(), id: \.element.id) { index, block in
                            Button {
                                selectedBlockID = block.id
                            } label: {
                                HStack(spacing: AppTheme.Spacing.control) {
                                    Text("\(index + 1)")
                                        .font(.caption.monospacedDigit().bold())
                                        .foregroundStyle(Color.appTextSecondary)
                                        .frame(width: 28, alignment: .leading)
                                    VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
                                        Text(block.original.isEmpty ? "空 OCR 原文" : block.original)
                                            .lineLimit(2)
                                        Text(block.translation.isEmpty ? "译文待重新生成" : block.translation)
                                            .font(.caption)
                                            .foregroundStyle(Color.appTextSecondary)
                                            .lineLimit(2)
                                    }
                                    Spacer(minLength: AppTheme.Spacing.compact)
                                    Image(systemName: selectedBlockID == block.id
                                        ? "checkmark.circle.fill"
                                        : "circle")
                                        .foregroundStyle(
                                            selectedBlockID == block.id
                                                ? Color.appAccent
                                                : Color.appTextSecondary
                                        )
                                        .accessibilityHidden(true)
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(!canEdit)
                            .accessibilityLabel("选择文字块 \(index + 1)")
                            .accessibilityValue(blockAccessibilityValue(block, isSelected: selectedBlockID == block.id))
                            .accessibilityHint(
                                canEdit
                                    ? "选择后可拆分；合并时可另外选择相邻的两个块"
                                    : "图片结构编辑当前不可用"
                            )
                        }
                    }
                }

                Section("调整阅读顺序") {
                    ForEach(blocks.enumerated(), id: \.element.id) { index, block in
                        HStack(spacing: AppTheme.Spacing.control) {
                            Text("\(index + 1)")
                                .font(.caption.monospacedDigit().bold())
                                .foregroundStyle(Color.appTextSecondary)
                                .frame(width: 28, alignment: .leading)
                            Text(block.original.isEmpty ? "空 OCR 原文" : block.original)
                                .lineLimit(1)
                            Spacer(minLength: AppTheme.Spacing.compact)
                            Button("上移", systemImage: "arrow.up") {
                                moveBlock(block.id, to: index - 1)
                            }
                            .disabled(!canEdit || index == 0)
                            .accessibilityHint("把此文字块移到前一个阅读位置；不会重新识别或翻译")
                            Button("下移", systemImage: "arrow.down") {
                                moveBlock(block.id, to: index + 1)
                            }
                            .disabled(!canEdit || index == blocks.count - 1)
                            .accessibilityHint("把此文字块移到后一个阅读位置；不会重新识别或翻译")
                        }
                    }
                    Text("调整顺序会保留已有 OCR、译文和复查进度，只更新图片转录和导出顺序。")
                        .font(.caption)
                        .foregroundStyle(Color.appTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Section("拆分当前文字块") {
                    TextField("从第几个字符处分开", text: $splitOffsetText)
                        .keyboardType(.numberPad)
                        .accessibilityLabel("拆分字符位置")
                        .accessibilityHint("输入从左到右或从上到下的 Character 位置；不能是首尾")
                    Button("拆分文字块", systemImage: "rectangle.split.2x1") {
                        splitSelectedBlock()
                    }
                    .disabled(!canEdit || selectedBlockID == nil || parsedSplitOffset == nil)
                    Text("拆分会建立两个新文字块，清除受影响块的现有译文、自动文字框和 OCR 来源；随后可逐块重新翻译。")
                        .font(.caption)
                        .foregroundStyle(Color.appTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Section("合并相邻文字块") {
                    ForEach(blocks.enumerated(), id: \.element.id) { index, block in
                        Button {
                            toggleMergeSelection(block.id)
                        } label: {
                            HStack(spacing: AppTheme.Spacing.control) {
                                Image(systemName: selectedMergeBlockIDs.contains(block.id)
                                    ? "checkmark.square.fill"
                                    : "square")
                                    .foregroundStyle(
                                        selectedMergeBlockIDs.contains(block.id)
                                            ? Color.appAccent
                                            : Color.appTextSecondary
                                    )
                                    .accessibilityHidden(true)
                                Text("\(index + 1)：\(block.original.isEmpty ? "空 OCR 原文" : block.original)")
                                    .lineLimit(2)
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(!canEdit)
                        .accessibilityLabel("选择合并文字块 \(index + 1)")
                        .accessibilityValue(selectedMergeBlockIDs.contains(block.id) ? "已选择" : "未选择")
                        .accessibilityHint("只可合并当前阅读顺序中相邻的两个文字块")
                    }
                    Button("合并已选文字块", systemImage: "rectangle.2.group") {
                        mergeSelectedBlocks()
                    }
                    .disabled(!canEdit || !canMergeSelection)
                    Text("合并按当前阅读顺序直接拼接原文，并清除受影响块的现有译文、自动文字框和 OCR 来源；随后可重新翻译合并块。")
                        .font(.caption)
                        .foregroundStyle(Color.appTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Color.appDanger)
                    }
                }
            }
            .navigationTitle("编辑文字块结构")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", role: .cancel) {
                        dismiss()
                    }
                    .accessibilityHint("关闭结构编辑，不改变图片文字块")
                }
            }
        }
    }

    private var parsedSplitOffset: Int? {
        let normalized = splitOffsetText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, let value = Int(normalized), value > 0 else { return nil }
        return value
    }

    private var selectedMergeBlocksInOrder: [UUID] {
        blocks
            .filter { selectedMergeBlockIDs.contains($0.id) }
            .map(\.id)
    }

    private var canMergeSelection: Bool {
        let selected = selectedMergeBlocksInOrder
        guard selected.count == 2,
              let firstIndex = blocks.firstIndex(where: { $0.id == selected[0] }),
              let secondIndex = blocks.firstIndex(where: { $0.id == selected[1] }) else {
            return false
        }
        return abs(firstIndex - secondIndex) == 1
    }

    private func blockAccessibilityValue(
        _ block: ImageTranslationBlock,
        isSelected: Bool
    ) -> String {
        var parts = [isSelected ? "已选择" : "未选择"]
        parts.append(block.translation.isEmpty ? "译文待重新生成" : "已有译文")
        parts.append(ImageOCRResultSummary.requiresReview(block) ? "待复查" : "无需复查")
        return parts.joined(separator: "；")
    }

    private func moveBlock(_ blockID: UUID, to index: Int) {
        errorMessage = nil
        guard move(blockID, index) else {
            errorMessage = "阅读顺序没有改变，请重试"
            return
        }
        dismiss()
    }

    private func splitSelectedBlock() {
        errorMessage = nil
        guard let selectedBlockID,
              let parsedSplitOffset,
              split(selectedBlockID, parsedSplitOffset) else {
            errorMessage = "请选择文字块并输入有效的中间字符位置"
            return
        }
        dismiss()
    }

    private func toggleMergeSelection(_ blockID: UUID) {
        if selectedMergeBlockIDs.contains(blockID) {
            selectedMergeBlockIDs.remove(blockID)
        } else if selectedMergeBlockIDs.count < 2 {
            selectedMergeBlockIDs.insert(blockID)
        } else {
            selectedMergeBlockIDs = [blockID]
        }
    }

    private func mergeSelectedBlocks() {
        errorMessage = nil
        let selected = selectedMergeBlocksInOrder
        guard selected.count == 2, merge(selected[0], selected[1]) else {
            errorMessage = "请选择当前阅读顺序中相邻的两个文字块"
            return
        }
        dismiss()
    }
}
