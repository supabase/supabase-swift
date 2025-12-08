import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

@available(macOS 10.15.4, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
/// Builder for constructing multipart/form-data payloads
struct MultipartBuilder {
    private let boundary: String
    private var parts: [Part] = []

    enum Part {
        case text(name: String, value: String)
        case file(name: String, fileURL: URL, mimeType: String?)
    }

    init(boundary: String) {
        self.boundary = boundary
    }

    /// Add a text field to the multipart payload
    func addText(name: String, value: String) -> MultipartBuilder {
        var builder = self
        builder.parts.append(.text(name: name, value: value))
        return builder
    }

    /// Add an optional text field (only adds if value is non-nil)
    func addOptionalText(name: String, value: String?) -> MultipartBuilder {
        if let value = value {
            return addText(name: name, value: value)
        }
        return self
    }

    /// Add a file field to the multipart payload (loads entire file into memory)
    func addFile(name: String, fileURL: URL, mimeType: String?) -> MultipartBuilder {
        var builder = self
        builder.parts.append(.file(name: name, fileURL: fileURL, mimeType: mimeType))
        return builder
    }

    /// Add a file field to the multipart payload (for streamed output)
    func addFileStreamed(name: String, fileURL: URL, mimeType: String?) -> MultipartBuilder {
        // For now, same as addFile - streaming happens in buildToTempFile
        var builder = self
        builder.parts.append(.file(name: name, fileURL: fileURL, mimeType: mimeType))
        return builder
    }

    /// Build the multipart payload in memory
    /// - Note: Only suitable for small payloads. Use `buildToTempFile()` for large files.
    /// - Returns: Complete multipart body data
    func buildInMemory() throws -> Data {
        var body = Data()

        for part in parts {
            switch part {
            case .text(let name, let value):
                body.append(textPart(name: name, value: value))
            case .file(let name, let fileURL, let mimeType):
                body.append(try filePart(name: name, fileURL: fileURL, mimeType: mimeType))
            }
        }

        body.append(closingBoundary())
        return body
    }

    /// Build the multipart payload to a temporary file
    /// - Note: Streams file contents to avoid memory pressure on large files
    /// - Returns: URL of temporary file containing multipart body
    func buildToTempFile() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent(UUID().uuidString)

        // Create temp file
        FileManager.default.createFile(atPath: tempFile.path, contents: nil)

        guard let handle = FileHandle(forWritingAtPath: tempFile.path) else {
            throw NSError(
                domain: "MultipartBuilder",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to create temp file"]
            )
        }

        defer { try? handle.close() }

        // Write parts
        for part in parts {
            switch part {
            case .text(let name, let value):
                let data = textPart(name: name, value: value)
                try handle.write(contentsOf: data)

            case .file(let name, let fileURL, let mimeType):
                // Write file part header
                let header = filePartHeader(
                    name: name,
                    fileName: fileURL.lastPathComponent,
                    mimeType: mimeType
                )
                try handle.write(contentsOf: header)

                // Stream file contents in chunks
                try streamFile(from: fileURL, to: handle)

                // Write trailing newline
                try handle.write(contentsOf: Data("\r\n".utf8))
            }
        }

        // Write closing boundary
        try handle.write(contentsOf: closingBoundary())

        return tempFile
    }

    // MARK: - Private Helpers

    private func textPart(name: String, value: String) -> Data {
        var data = Data()
        data.append(Data("--\(boundary)\r\n".utf8))
        data.append(Data("Content-Disposition: form-data; name=\"\(name)\"\r\n".utf8))
        data.append(Data("\r\n".utf8))
        data.append(Data("\(value)\r\n".utf8))
        return data
    }

    private func filePart(name: String, fileURL: URL, mimeType: String?) throws -> Data {
        var data = Data()

        // Header
        data.append(
            filePartHeader(name: name, fileName: fileURL.lastPathComponent, mimeType: mimeType))

        // File content
        let fileData = try Data(contentsOf: fileURL)
        data.append(fileData)

        // Trailing newline
        data.append(Data("\r\n".utf8))

        return data
    }

    private func filePartHeader(name: String, fileName: String, mimeType: String?) -> Data {
        var header = Data()
        header.append(Data("--\(boundary)\r\n".utf8))
        header.append(
            Data(
                "Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(fileName)\"\r\n"
                    .utf8
            )
        )

        if let mimeType = mimeType {
            header.append(Data("Content-Type: \(mimeType)\r\n".utf8))
        }

        header.append(Data("\r\n".utf8))
        return header
    }

    private func closingBoundary() -> Data {
        return Data("--\(boundary)--\r\n".utf8)
    }

    private func streamFile(from url: URL, to handle: FileHandle) throws {
        guard let input = InputStream(url: url) else {
            throw NSError(
                domain: "MultipartBuilder",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Failed to open file for reading"]
            )
        }

        input.open()
        defer { input.close() }

        let bufferSize = 64 * 1024  // 64KB chunks
        var buffer = [UInt8](repeating: 0, count: bufferSize)

        while input.hasBytesAvailable {
            let bytesRead = input.read(&buffer, maxLength: bufferSize)
            if bytesRead > 0 {
                let data = Data(bytes: buffer, count: bytesRead)
                try handle.write(contentsOf: data)
            } else if bytesRead < 0 {
                throw input.streamError
                    ?? NSError(
                        domain: "MultipartBuilder",
                        code: 3,
                        userInfo: [NSLocalizedDescriptionKey: "Error reading file"]
                    )
            }
        }
    }
}
