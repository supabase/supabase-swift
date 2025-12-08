import Foundation
import UniformTypeIdentifiers

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

extension HTTPClient {
    @available(macOS 10.15.4, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
    package func uploadFile(
        _ fileURL: URL,
        to path: String,
        query: [String: Value]? = nil,
        body: Data? = nil,
        headers: [String: String]? = nil,
        progress: Progress? = nil
    ) async throws -> Data {
        var request = try await createRequest(.post, path, query: query, body: body, headers: headers)

        let boundary = "---sb-\(UUID().uuidString)"
        request.setValue(
            "multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let fileSize = try fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        let threshold = 10 * 1024 * 1024  // 10MB
        let shouldStream = fileSize >= threshold

        let mimeType: String? =
            if #available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *) {
                fileURL.mimeType
            } else {
                nil
            }

        if shouldStream {
            // Large file: stream from disk using URLSession.uploadTask
            let tempFile = try MultipartBuilder(boundary: boundary)
                .addFileStreamed(name: "file", fileURL: fileURL, mimeType: mimeType)
                .buildToTempFile()

            defer { try? FileManager.default.removeItem(at: tempFile) }

            let (data, response) = try await session.upload(for: request, fromFile: tempFile)
            _ = try validateResponse(response)
            return data
        } else {
            // Small file: build in memory
            let body = try MultipartBuilder(boundary: boundary)
                .addFile(name: "file", fileURL: fileURL, mimeType: mimeType)
                .buildInMemory()

            let (data, response) = try await session.upload(for: request, from: body)
            _ = try validateResponse(response, data: data)
            return data
        }
    }
}

extension URL {
    @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
    fileprivate var mimeType: String? {
        guard let uti = UTType(filenameExtension: pathExtension) else {
            return nil
        }
        return uti.preferredMIMEType
    }
}
