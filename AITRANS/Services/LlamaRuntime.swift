import Foundation
@preconcurrency import llama

enum LlamaRuntimeError: LocalizedError, Sendable {
    case couldNotLoadModel(String)
    case couldNotCreateContext
    case promptTooLong
    case decodeFailed
    case tokenizationFailed

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
        }
    }
}

final class LlamaRuntime: @unchecked Sendable {
    private var model: OpaquePointer?
    private var context: OpaquePointer?
    private var vocabulary: OpaquePointer?
    private var sampler: UnsafeMutablePointer<llama_sampler>?
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

    func generate(prompt: String, maxTokens: Int) throws -> String {
        lock.lock()
        defer { lock.unlock() }
        return try generateLocked(prompt: prompt, maxTokens: maxTokens, trimsOutput: true)
    }

    func generateRaw(prompt: String, maxTokens: Int) throws -> String {
        lock.lock()
        defer { lock.unlock() }
        return try generateLocked(prompt: prompt, maxTokens: maxTokens, trimsOutput: false)
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

        let samplingParameters = llama_sampler_chain_default_params()
        let samplingChain = llama_sampler_chain_init(samplingParameters)
        llama_sampler_chain_add(samplingChain, llama_sampler_init_top_k(40))
        llama_sampler_chain_add(samplingChain, llama_sampler_init_top_p(0.90, 1))
        llama_sampler_chain_add(samplingChain, llama_sampler_init_min_p(0.05, 1))
        llama_sampler_chain_add(samplingChain, llama_sampler_init_temp(0.2))
        llama_sampler_chain_add(samplingChain, llama_sampler_init_dist(UInt32.random(in: 1...UInt32.max)))

        model = loadedModel
        context = loadedContext
        vocabulary = llama_model_get_vocab(loadedModel)
        sampler = samplingChain
        batch = llama_batch_init(512, 0, 1)
        loadedModelPath = path
    }

    private func generateLocked(prompt: String, maxTokens: Int, trimsOutput: Bool) throws -> String {
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
