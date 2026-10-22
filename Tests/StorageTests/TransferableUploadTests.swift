#if canImport(CoreTransferable) && canImport(UniformTypeIdentifiers)
  import ConcurrencyExtras
  import CoreTransferable
  import Foundation
  import HTTPTypes
  import TestHelpers
  import Testing
  import UniformTypeIdentifiers

  @testable import Storage

  private struct Note: Transferable {
    var text: String

    static var transferRepresentation: some TransferRepresentation {
      DataRepresentation(exportedContentType: .plainText) { Data($0.text.utf8) }
    }
  }

  private struct Photo: Transferable {
    var fileURL: URL

    static var transferRepresentation: some TransferRepresentation {
      FileRepresentation(exportedContentType: .jpeg) { SentTransferredFile($0.fileURL) }
    }
  }

  @Suite
  struct TransferableUploadTests {
    private struct Sent {
      var request: HTTPRequest
      var body: Data
    }

    private func makeBucket(sent: LockIsolated<Sent?>) -> StorageBucket {
      StorageClient(
        configuration: StorageClientConfiguration(
          url: URL(string: "http://localhost:54321/storage/v1")!,
          headers: [:],
          http: .init(
            transport: ClosureTransport { request, body in
              let data = try await Data(collecting: #require(body), upTo: .max)
              sent.setValue(Sent(request: request, body: data))
              return (
                HTTPResponse(status: .ok, headerFields: [.contentType: "application/json"]),
                HTTPBody(Data(#"{"Key":"bucket/item"}"#.utf8))
              )
            }))
      )
      .from("bucket")
    }

    @Test
    func uploadsTheExportedBytesWithTheContentTypeMIMEType() async throws {
      let sent = LockIsolated<Sent?>(nil)

      let object = try await makeBucket(sent: sent).upload(
        path: "notes/hello", item: Note(text: "hello"), contentType: .plainText)

      let request = try #require(sent.value?.request)
      #expect(request.path == "/storage/v1/object/bucket/notes/hello")
      #expect(request.headerFields[.contentType] == "text/plain")
      #expect(sent.value?.body == Data("hello".utf8))
      #expect(object.fullPath == "bucket/item")
    }

    @Test
    func uploadsAFileRepresentation() async throws {
      let sent = LockIsolated<Sent?>(nil)
      let fileURL = try #require(Bundle.module.url(forResource: "sadcat", withExtension: "jpg"))

      try await makeBucket(sent: sent).upload(
        path: "cat", item: Photo(fileURL: fileURL), contentType: .jpeg)

      #expect(sent.value?.request.headerFields[.contentType] == "image/jpeg")
      #expect(sent.value?.body == (try Data(contentsOf: fileURL)))
    }

    @Test
    func explicitContentTypeOptionWins() async throws {
      let sent = LockIsolated<Sent?>(nil)

      try await makeBucket(sent: sent).upload(
        path: "notes/hello.md", item: Note(text: "# hi"), contentType: .plainText,
        options: UploadOptions(contentType: "text/markdown"))

      #expect(sent.value?.request.headerFields[.contentType] == "text/markdown")
    }

    @Test
    func aTypeTheItemCannotExportThrowsInvalidRequest() async throws {
      let sent = LockIsolated<Sent?>(nil)

      let error = await #expect(throws: StorageError.self) {
        try await makeBucket(sent: sent).upload(
          path: "notes/hello", item: Note(text: "hello"), contentType: .png)
      }

      #expect(error?.kind == .invalidRequest)
      #expect(sent.value == nil)
    }
  }
#endif
