import CryptoKit
import Foundation

struct LocalModelDownloadService: Sendable {
    enum DownloadError: LocalizedError {
        case invalidResponse
        case invalidStatusCode(Int)
        case fileTooSmall(Int64)
        case checksumMismatch

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                "下载失败：服务器响应无效。"
            case .invalidStatusCode(let statusCode):
                "下载失败：HTTP \(statusCode)。"
            case .fileTooSmall(let size):
                "下载失败：文件过小，仅 \(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))。"
            case .checksumMismatch:
                "下载失败：SHA256 校验不匹配。"
            }
        }
    }

    func download(
        model: BuiltInLocalModel,
        to destination: URL,
        progress: @Sendable @escaping (ModelDownloadProgress) async -> Void
    ) async throws {
        let fileManager = FileManager.default
        let directory = destination.deletingLastPathComponent()
        let temporaryURL = destination.appendingPathExtension("download")

        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: temporaryURL.path) {
            try fileManager.removeItem(at: temporaryURL)
        }

        let start = Date.now
        var receivedBytes: Int64 = 0
        var lastProgressTime = start
        var lastProgressBytes: Int64 = 0

        let (bytes, response) = try await URLSession.shared.bytes(from: model.sourceURL)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DownloadError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw DownloadError.invalidStatusCode(httpResponse.statusCode)
        }

        let totalBytes = expectedLength(response: httpResponse, fallback: model.expectedSizeBytes)
        await progress(
            ModelDownloadProgress(
                phase: .downloading,
                bytesReceived: 0,
                totalBytes: totalBytes,
                speedBytesPerSecond: 0,
                message: "开始下载 \(model.displayName)"
            )
        )

        FileManager.default.createFile(atPath: temporaryURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: temporaryURL)
        var buffer: [UInt8] = []
        buffer.reserveCapacity(64 * 1_024)
        do {
            for try await byte in bytes {
                try Task.checkCancellation()
                buffer.append(byte)
                receivedBytes += 1

                if buffer.count >= 64 * 1_024 {
                    try handle.write(contentsOf: Data(buffer))
                    buffer.removeAll(keepingCapacity: true)
                }

                let now = Date.now
                if now.timeIntervalSince(lastProgressTime) >= 0.35 || receivedBytes == totalBytes {
                    let elapsed = max(now.timeIntervalSince(lastProgressTime), 0.001)
                    let speed = Int64(Double(receivedBytes - lastProgressBytes) / elapsed)
                    lastProgressTime = now
                    lastProgressBytes = receivedBytes

                    await progress(
                        ModelDownloadProgress(
                            phase: .downloading,
                            bytesReceived: receivedBytes,
                            totalBytes: totalBytes,
                            speedBytesPerSecond: speed,
                            message: "下载中"
                        )
                    )
                }
            }
            if !buffer.isEmpty {
                try handle.write(contentsOf: Data(buffer))
            }
            try handle.close()
        } catch {
            try? handle.close()
            try? fileManager.removeItem(at: temporaryURL)
            throw error
        }

        guard receivedBytes > model.expectedSizeBytes / 2 else {
            try? fileManager.removeItem(at: temporaryURL)
            throw DownloadError.fileTooSmall(receivedBytes)
        }

        let digest = try sha256Hex(for: temporaryURL)
        guard digest == model.sha256 else {
            try? fileManager.removeItem(at: temporaryURL)
            throw DownloadError.checksumMismatch
        }

        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: temporaryURL, to: destination)

        let duration = max(Date.now.timeIntervalSince(start), 0.001)
        await progress(
            ModelDownloadProgress(
                phase: .installed,
                bytesReceived: receivedBytes,
                totalBytes: totalBytes,
                speedBytesPerSecond: Int64(Double(receivedBytes) / duration),
                message: "下载完成，已安装为 model.gguf"
            )
        )
    }

    private func expectedLength(response: HTTPURLResponse, fallback: Int64) -> Int64 {
        let headerValue = response.value(forHTTPHeaderField: "Content-Length")
            ?? response.value(forHTTPHeaderField: "x-linked-size")
        guard let headerValue, let parsed = Int64(headerValue), parsed > 0 else {
            return fallback
        }
        return parsed
    }

    private func sha256Hex(for url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer {
            try? handle.close()
        }

        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            hasher.update(data: data)
        }
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
