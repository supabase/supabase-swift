import Foundation

extension HTTPClient {

    @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
    package func downloadFile(
        to destination: URL,
        from path: String,
        query: [String: Value]? = nil,
        body: Data? = nil,
        headers: [String: String]? = nil,
        progress: Progress? = nil
    ) async throws -> URL {
        let request = try await createRequest(.get, path, query: query, body: body, headers: headers)

        let (tempURL, response) = try await session.download(
            for: request, delegate: progress.map { DownloadProgressDelegate(progress: $0) })
        _ = try validateResponse(response)

        // Create parent directory if needed
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        // Move from temporary location to final destination
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: tempURL, to: destination)

        return destination
    }
}

@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
private final class DownloadProgressDelegate: NSObject, URLSessionDownloadDelegate,
    @unchecked Sendable
{
    private let progress: Progress

    init(progress: Progress) {
        self.progress = progress
    }

    func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64
    ) {
        progress.completedUnitCount = totalBytesWritten
        progress.totalUnitCount = totalBytesExpectedToWrite
    }

    func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // The actual file handling is done in the async/await layer.
    }
}
