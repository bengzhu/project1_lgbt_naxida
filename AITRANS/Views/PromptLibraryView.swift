import SwiftUI

struct PromptLibraryView: View {
    @EnvironmentObject private var store: TranslationSessionStore
    @State private var selectedDirection: PromptLanguageDirection = .englishToChinese
    @State private var editingPrompt: PromptTemplate?
    @State private var showCreateSheet = false
    @State private var pendingDeletion: PromptTemplate?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.page) {
                AppPageHeader(
                    title: "提示词",
                    subtitle: "当前：\(store.selectedPrompt.title)",
                    systemImage: "text.badge.star",
                    status: "\(store.prompts.count) 个模板",
                    statusTone: .neutral,
                    feature: .settings
                )

                Picker("翻译方向", selection: $selectedDirection) {
                    ForEach(PromptLanguageDirection.allCases) { direction in
                        Text(direction.rawValue).tag(direction)
                    }
                }
                .pickerStyle(.segmented)

                HStack {
                    AppSectionHeader(title: "模板库", subtitle: selectedDirection.rawValue, systemImage: "list.bullet.rectangle")
                    Spacer()
                    AppIconButton(title: "新建提示词", systemImage: "plus", tone: .active) { showCreateSheet = true }
                }

                LazyVStack(spacing: 0) {
                    ForEach(store.prompts) { prompt in
                        PromptRow(
                            prompt: prompt,
                            direction: selectedDirection,
                            selected: store.selectedPromptID == prompt.id,
                            select: { store.selectPrompt(prompt) },
                            edit: { editingPrompt = prompt },
                            duplicate: { store.duplicatePrompt(prompt) },
                            delete: { pendingDeletion = prompt }
                        )
                    }
                }
            }
            .enterprisePageFrame()
            .padding(.vertical, AppTheme.Spacing.section)
            .padding(.bottom, 72)
        }
        .background(Color.appCanvas)
        .sheet(item: $editingPrompt) { prompt in
            PromptEditorSheet(mode: .edit(prompt)).environmentObject(store)
        }
        .sheet(isPresented: $showCreateSheet) {
            PromptEditorSheet(mode: .create).environmentObject(store)
        }
        .confirmationDialog("删除自定义提示词？", isPresented: deletionPresented, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                if let pendingDeletion { store.deletePrompt(pendingDeletion) }
                pendingDeletion = nil
            }
            Button("取消", role: .cancel) { pendingDeletion = nil }
        } message: {
            Text("内置提示词不会被删除。")
        }
    }

    private var deletionPresented: Binding<Bool> {
        Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } })
    }
}

private struct PromptRow: View {
    let prompt: PromptTemplate
    let direction: PromptLanguageDirection
    let selected: Bool
    let select: () -> Void
    let edit: () -> Void
    let duplicate: () -> Void
    let delete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.control) {
            Button(action: select) {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
                    HStack {
                        Label(prompt.title, systemImage: selected ? "checkmark.circle.fill" : "circle")
                            .font(.body.bold())
                            .foregroundStyle(selected ? Color.appAccent : Color.appTextPrimary)
                        if prompt.isBuiltIn {
                            Label("内置", systemImage: "lock.fill")
                                .font(.caption.bold())
                                .foregroundStyle(Color.locked)
                        }
                    }
                    Text(prompt.instruction(for: direction))
                        .font(.subheadline)
                        .foregroundStyle(Color.appTextSecondary)
                        .lineLimit(3)
                    if !prompt.tone.isEmpty {
                        Text(prompt.tone).font(.caption).foregroundStyle(Color.appTextSecondary)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selected ? .isSelected : [])

            Menu("管理 \(prompt.title)", systemImage: "ellipsis.circle") {
                if !prompt.isBuiltIn { Button("编辑", systemImage: "pencil", action: edit) }
                Button("复制", systemImage: "doc.on.doc", action: duplicate)
                if !prompt.isBuiltIn { Button("删除", systemImage: "trash", role: .destructive, action: delete) }
            }
            .labelStyle(.iconOnly)
            .frame(width: AppTheme.Layout.minimumTarget, height: AppTheme.Layout.minimumTarget)
        }
        .padding(.vertical, AppTheme.Spacing.control)
        .overlay(alignment: .bottom) { Divider().overlay(Color.appBorder) }
    }
}

private enum PromptEditorMode: Identifiable {
    case create
    case edit(PromptTemplate)
    var id: String {
        switch self {
        case .create: "create"
        case .edit(let prompt): prompt.id.uuidString
        }
    }
}

private struct PromptEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: TranslationSessionStore
    let mode: PromptEditorMode
    @State private var title: String
    @State private var englishToChinese: String
    @State private var chineseToEnglish: String
    @State private var tone: String
    @State private var direction: PromptLanguageDirection = .englishToChinese

    init(mode: PromptEditorMode) {
        self.mode = mode
        switch mode {
        case .create:
            _title = State(initialValue: "")
            _englishToChinese = State(initialValue: PromptLanguageDirection.englishToChinese.fallbackInstruction)
            _chineseToEnglish = State(initialValue: PromptLanguageDirection.chineseToEnglish.fallbackInstruction)
            _tone = State(initialValue: "")
        case .edit(let prompt):
            _title = State(initialValue: prompt.title)
            _englishToChinese = State(initialValue: prompt.englishToChineseInstruction)
            _chineseToEnglish = State(initialValue: prompt.chineseToEnglishInstruction)
            _tone = State(initialValue: prompt.tone)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("标题", text: $title)
                    TextField("语气", text: $tone)
                }
                Section("翻译方向") {
                    Picker("翻译方向", selection: $direction) {
                        ForEach(PromptLanguageDirection.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    TextField("指令", text: instructionBinding, axis: .vertical)
                        .lineLimit(5...12)
                }
            }
            .navigationTitle(isCreating ? "新建提示词" : "编辑提示词")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消", action: dismiss.callAsFunction) }
                ToolbarItem(placement: .confirmationAction) { Button("保存", action: save).disabled(!canSave) }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var isCreating: Bool { if case .create = mode { true } else { false } }
    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !englishToChinese.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !chineseToEnglish.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    private var instructionBinding: Binding<String> {
        direction == .englishToChinese ? $englishToChinese : $chineseToEnglish
    }
    private func save() {
        switch mode {
        case .create:
            store.createPrompt(title: title, englishToChineseInstruction: englishToChinese, chineseToEnglishInstruction: chineseToEnglish, tone: tone)
        case .edit(let prompt):
            store.updatePrompt(prompt, title: title, englishToChineseInstruction: englishToChinese, chineseToEnglishInstruction: chineseToEnglish, tone: tone)
        }
        dismiss()
    }
}
