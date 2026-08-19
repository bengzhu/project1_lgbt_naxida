import Foundation
@preconcurrency import llama

enum LlamaRuntimeError: LocalizedError, Sendable {
    case couldNotLoadModel(String)
    case couldNotCreateContext
    case promptTooLong
    case decodeFailed
    case tokenizationFailed
    case missingChatTemplate
    case unsupportedChatTemplate
    case chatTemplateBufferSizingFailed
    case invalidRenderedPrompt

    var errorDescription: String? {
        switch self {
        case .couldNotLoadModel(let path):
            "无法加载 GGUF 模型：\(path)"
        case .couldNotCreateContext:
            "无法创建 llama.cpp 推理上下文。"
        case .promptTooLong:
            "输入超过当前上下文长度。"
        case .decodeFailed:
            "llama.cpp 解码失败。"
        case .tokenizationFailed:
            "提示词分词失败。"
        case .missingChatTemplate:
            "GGUF 没有内嵌 chat template，且当前模型 profile 没有获批准的 fallback。"
        case .unsupportedChatTemplate:
            "GGUF 的 chat template 不是当前 llama.cpp 支持的模板。"
        case .chatTemplateBufferSizingFailed:
            "chat template 输出缓冲区无法安全扩容。"
        case .invalidRenderedPrompt:
            "chat template 生成了无效的 UTF-8 prompt。"
        }
    }
}

final class LlamaRuntime: @unchecked Sendable {
    private var model: OpaquePointer?
    private var context: OpaquePointer?
    private var vocabulary: OpaquePointer?
    private var sampler: UnsafeMutablePointer<llama_sampler>?
    private var samplerProfile: ModelDecodingProfile = .sampled
    private var batch: llama_batch?
    private var loadedModelPath = ""
    private var temporaryInvalidBytes: [CChar] = []
    private let lock = NSLock()

    deinit {
        if let sampler {
            llama_sampler_free(sampler)
        }
        if let batch {
            llama_batch_free(batch)
        }
        if let model {
            llama_model_free(model)
        }
        if let context {
            llama_free(context)
        }
        var hadBackend = false
        if model != nil {
            hadBackend = true
        }
        if context != nil {
            hadBackend = true
        }
        if hadBackend {
            llama_backend_free()
        }
    }

    func loadModelIfNeeded(at path: String) throws {
        lock.lock()
        defer { lock.unlock() }
        try loadModelIfNeededLocked(at: path)
    }

    func generate(prompt: String, maxTokens: Int, decodingProfile: ModelDecodingProfile = .sampled) throws -> String {
        lock.lock()
        defer { lock.unlock() }
        return try generateLocked(prompt: prompt, maxTokens: maxTokens, trimsOutput: true, decodingProfile: decodingProfile)
    }

    func generate(
        messages: [LocalModelChatMessage],
        fallbackProfile: LocalModelPromptProfile,
        maxTokens: Int,
        decodingProfile: ModelDecodingProfile = .sampled
    ) throws -> String {
        lock.lock()
        defer { lock.unlock() }
        let rendered = try renderChatMessagesLocked(
            messages,
            fallbackProfile: fallbackProfile
        )
        return try generateLocked(
            prompt: rendered.prompt,
            maxTokens: maxTokens,
            trimsOutput: true,
            decodingProfile: decodingProfile
        )
    }

    func generateRaw(prompt: String, maxTokens: Int, decodingProfile: ModelDecodingProfile = .deterministic) throws -> String {
        lock.lock()
        defer { lock.unlock() }
        return try generateLocked(prompt: prompt, maxTokens: maxTokens, trimsOutput: false, decodingProfile: decodingProfile)
    }

    func renderPrompt(
        messages: [LocalModelChatMessage],
        fallbackProfile: LocalModelPromptProfile
    ) throws -> LocalModelRenderedPrompt {
        lock.lock()
        defer { lock.unlock() }
        return try renderChatMessagesLocked(
            messages,
            fallbackProfile: fallbackProfile
        )
    }

    private func loadModelIfNeededLocked(at path: String) throws {
        guard loadedModelPath != path || model == nil || context == nil else { return }

        unload()
        llama_backend_init()

        var modelParameters = llama_model_default_params()
#if targetEnvironment(simulator)
        modelParameters.n_gpu_layers = 0
#else
        modelParameters.n_gpu_layers = 99
#endif

        guard let loadedModel = llama_model_load_from_file(path, modelParameters) else {
            throw LlamaRuntimeError.couldNotLoadModel(path)
        }

        let threadCount = max(1, min(6, ProcessInfo.processInfo.processorCount - 2))
        var contextParameters = llama_context_default_params()
        contextParameters.n_ctx = 1_024
        contextParameters.n_threads = Int32(threadCount)
        contextParameters.n_threads_batch = Int32(threadCount)

        guard let loadedContext = llama_init_from_model(loadedModel, contextParameters) else {
            llama_model_free(loadedModel)
            throw LlamaRuntimeError.couldNotCreateContext
        }

        model = loadedModel
        context = loadedContext
        vocabulary = llama_model_get_vocab(loadedModel)
        sampler = Self.makeSampler(for: samplerProfile)
        batch = llama_batch_init(512, 0, 1)
        loadedModelPath = path
    }

    private func generateLocked(
        prompt: String,
        maxTokens: Int,
        trimsOutput: Bool,
        decodingProfile: ModelDecodingProfile
    ) throws -> String {
        try ensureSamplerProfile(decodingProfile)
        guard let context, let vocabulary, let sampler, var currentBatch = batch else {
            throw LlamaRuntimeError.couldNotCreateContext
        }

        temporaryInvalidBytes.removeAll()
        llama_memory_clear(llama_get_memory(context), true)
        llama_sampler_reset(sampler)

        let promptTokens = try tokenize(prompt, addBOS: true)
        guard !promptTokens.isEmpty else {
            throw LlamaRuntimeError.tokenizationFailed
        }

        let contextSize = Int(llama_n_ctx(context))
        guard promptTokens.count + maxTokens <= contextSize else {
            throw LlamaRuntimeError.promptTooLong
        }

        clear(&currentBatch)
        for (index, token) in promptTokens.enumerated() {
            add(&currentBatch, token, Int32(index), [0], false)
            llama_sampler_accept(sampler, token)
        }
        currentBatch.logits[Int(currentBatch.n_tokens) - 1] = 1

        guard llama_decode(context, currentBatch) == 0 else {
            batch = currentBatch
            throw LlamaRuntimeError.decodeFailed
        }

        var cursor = Int32(currentBatch.n_tokens)
        var generatedText = ""

        for _ in 0..<maxTokens {
            let token = llama_sampler_sample(sampler, context, currentBatch.n_tokens - 1)
            if llama_vocab_is_eog(vocabulary, token) {
                generatedText += flushTemporaryBytes()
                break
            }

            generatedText += decode(token: token)

            clear(&currentBatch)
            add(&currentBatch, token, cursor, [0], true)
            cursor += 1

            guard llama_decode(context, currentBatch) == 0 else {
                batch = currentBatch
                throw LlamaRuntimeError.decodeFailed
            }
        }

        batch = currentBatch
        return trimsOutput ? generatedText.trimmingCharacters(in: .whitespacesAndNewlines) : generatedText
    }

    private func renderChatMessagesLocked(
        _ messages: [LocalModelChatMessage],
        fallbackProfile: LocalModelPromptProfile
    ) throws -> LocalModelRenderedPrompt {
        guard !messages.isEmpty else {
            throw LocalModelPromptProfileError.emptyMessage
        }
        guard let model else {
            throw LlamaRuntimeError.couldNotCreateContext
        }

        if let templatePointer = llama_model_chat_template(model, nil) {
            let template = String(cString: templatePointer)
            if !template.isEmpty {
                let prompt = try withCChatMessages(messages) { chat, count in
                    try applyChatTemplate(
                        template,
                        chat: chat,
                        count: count
                    )
                }
                return LocalModelRenderedPrompt(
                    prompt: prompt,
                    source: .embedded,
                    embeddedTemplate: template
                )
            }
        }

        do {
            let prompt = try fallbackProfile.fallbackPrompt(for: messages)
            return LocalModelRenderedPrompt(
                prompt: prompt,
                source: .explicitKnownFallback,
                embeddedTemplate: nil
            )
        } catch let error as LocalModelPromptProfileError {
            if case .fallbackUnavailable = error {
                throw LlamaRuntimeError.missingChatTemplate
            }
            throw error
        }
    }

    private func withCChatMessages<T>(
        _ messages: [LocalModelChatMessage],
        body: (UnsafePointer<llama_chat_message>?, Int) throws -> T
    ) rethrows -> T {
        var cMessages: [llama_chat_message] = []
        cMessages.reserveCapacity(messages.count)

        func appendMessage(at index: Int) throws -> T {
            if index == messages.count {
                return try cMessages.withUnsafeBufferPointer { buffer in
                    try body(buffer.baseAddress, buffer.count)
                }
            }

            let message = messages[index]
            return try message.role.rawValue.withCString { role in
                try message.content.withCString { content in
                    cMessages.append(llama_chat_message(role: role, content: content))
                    return try appendMessage(at: index + 1)
                }
            }
        }

        return try appendMessage(at: 0)
    }

    private func applyChatTemplate(
        _ template: String,
        chat: UnsafePointer<llama_chat_message>?,
        count: Int
    ) throws -> String {
        guard let count32 = Int32(exactly: count) else {
            throw LlamaRuntimeError.chatTemplateBufferSizingFailed
        }

        return try template.withCString { templatePointer in
            let required = llama_chat_apply_template(
                templatePointer,
                chat,
                count,
                true,
                nil,
                0
            )
            guard required >= 0 else {
                throw LlamaRuntimeError.unsupportedChatTemplate
            }
            guard required < Int32.max else {
                throw LlamaRuntimeError.chatTemplateBufferSizingFailed
            }

            var capacity = max(1, Int(required) + 1)
            for _ in 0..<3 {
                var buffer = [CChar](repeating: 0, count: capacity)
                let written = buffer.withUnsafeMutableBufferPointer { buffer in
                    llama_chat_apply_template(
                        templatePointer,
                        chat,
                        count,
                        true,
                        buffer.baseAddress,
                        Int32(buffer.count)
                    )
                }
                guard written >= 0 else {
                    throw LlamaRuntimeError.unsupportedChatTemplate
                }
                guard written < Int32.max else {
                    throw LlamaRuntimeError.chatTemplateBufferSizingFailed
                }
                if Int(written) < buffer.count {
                    let bytes = buffer.prefix(Int(written)).map { UInt8(bitPattern: $0) }
                    guard let prompt = String(data: Data(bytes), encoding: .utf8) else {
                        throw LlamaRuntimeError.invalidRenderedPrompt
                    }
                    guard !prompt.isEmpty else {
                        throw LlamaRuntimeError.invalidRenderedPrompt
                    }
                    return prompt
                }
                capacity = Int(written) + 1
            }
            throw LlamaRuntimeError.chatTemplateBufferSizingFailed
        }
    }

    private func unload() {
        if let sampler {
            llama_sampler_free(sampler)
        }
        if let batch {
            llama_batch_free(batch)
        }
        if let model {
            llama_model_free(model)
        }
        if let context {
            llama_free(context)
        }
        if model != nil || context != nil {
            llama_backend_free()
        }

        model = nil
        context = nil
        vocabulary = nil
        sampler = nil
        batch = nil
        loadedModelPath = ""
        temporaryInvalidBytes.removeAll()
    }

    private func ensureSamplerProfile(_ profile: ModelDecodingProfile) throws {
        guard sampler != nil else {
            samplerProfile = profile
            sampler = Self.makeSampler(for: profile)
            return
        }
        guard samplerProfile != profile else { return }
        if let sampler {
            llama_sampler_free(sampler)
        }
        samplerProfile = profile
        sampler = Self.makeSampler(for: profile)
    }

    private static func makeSampler(for profile: ModelDecodingProfile) -> UnsafeMutablePointer<llama_sampler>? {
        let samplingParameters = llama_sampler_chain_default_params()
        let samplingChain = llama_sampler_chain_init(samplingParameters)
        if profile.mode == ModelDecodingProfile.deterministic.mode {
            llama_sampler_chain_add(samplingChain, llama_sampler_init_temp(0))
            llama_sampler_chain_add(samplingChain, llama_sampler_init_greedy())
            return samplingChain
        }
        if let topK = profile.topK {
            llama_sampler_chain_add(samplingChain, llama_sampler_init_top_k(topK))
        }
        if let topP = profile.topP {
            llama_sampler_chain_add(samplingChain, llama_sampler_init_top_p(Float(topP), 1))
        }
        if let minP = profile.minP {
            llama_sampler_chain_add(samplingChain, llama_sampler_init_min_p(Float(minP), 1))
        }
        llama_sampler_chain_add(samplingChain, llama_sampler_init_temp(Float(profile.temperature)))
        llama_sampler_chain_add(samplingChain, llama_sampler_init_dist(profile.seed ?? UInt32.random(in: 1...UInt32.max)))
        return samplingChain
    }

    private func tokenize(_ text: String, addBOS: Bool) throws -> [llama_token] {
        guard let vocabulary else {
            throw LlamaRuntimeError.couldNotCreateContext
        }

        let utf8Count = text.utf8.count
        let capacity = utf8Count + (addBOS ? 1 : 0) + 1
        let tokens = UnsafeMutablePointer<llama_token>.allocate(capacity: capacity)
        defer { tokens.deallocate() }

        let tokenCount = llama_tokenize(vocabulary, text, Int32(utf8Count), tokens, Int32(capacity), addBOS, true)
        guard tokenCount > 0 else {
            throw LlamaRuntimeError.tokenizationFailed
        }

        return (0..<Int(tokenCount)).map { tokens[$0] }
    }

    private func decode(token: llama_token) -> String {
        let stackCapacity = 8
        let buffer = UnsafeMutablePointer<CChar>.allocate(capacity: stackCapacity)
        buffer.initialize(repeating: 0, count: stackCapacity)
        defer { buffer.deallocate() }

        let count = llama_token_to_piece(vocabulary, token, buffer, Int32(stackCapacity), 0, false)
        let bytes: [CChar]
        if count < 0 {
            let expandedCapacity = Int(-count)
            let expanded = UnsafeMutablePointer<CChar>.allocate(capacity: expandedCapacity)
            expanded.initialize(repeating: 0, count: expandedCapacity)
            defer { expanded.deallocate() }

            let expandedCount = llama_token_to_piece(vocabulary, token, expanded, Int32(expandedCapacity), 0, false)
            bytes = Array(UnsafeBufferPointer(start: expanded, count: max(0, Int(expandedCount))))
        } else {
            bytes = Array(UnsafeBufferPointer(start: buffer, count: Int(count)))
        }

        temporaryInvalidBytes.append(contentsOf: bytes)
        if let string = stringFromUTF8Bytes(temporaryInvalidBytes) {
            temporaryInvalidBytes.removeAll()
            return string
        }

        return ""
    }

    private func flushTemporaryBytes() -> String {
        defer { temporaryInvalidBytes.removeAll() }
        guard !temporaryInvalidBytes.isEmpty else { return "" }
        return stringFromUTF8Bytes(temporaryInvalidBytes) ?? ""
    }

    private func stringFromUTF8Bytes(_ bytes: [CChar]) -> String? {
        let unsignedBytes = bytes.map { UInt8(bitPattern: $0) }
        return String(data: Data(unsignedBytes), encoding: .utf8)
    }

    private func clear(_ batch: inout llama_batch) {
        batch.n_tokens = 0
    }

    private func add(
        _ batch: inout llama_batch,
        _ token: llama_token,
        _ position: llama_pos,
        _ sequenceIDs: [llama_seq_id],
        _ logits: Bool
    ) {
        let index = Int(batch.n_tokens)
        batch.token[index] = token
        batch.pos[index] = position
        batch.n_seq_id[index] = Int32(sequenceIDs.count)
        for sequenceIndex in sequenceIDs.indices {
            batch.seq_id[index]![sequenceIndex] = sequenceIDs[sequenceIndex]
        }
        batch.logits[index] = logits ? 1 : 0
        batch.n_tokens += 1
    }
}
