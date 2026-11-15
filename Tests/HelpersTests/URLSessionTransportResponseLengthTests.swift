//
//  URLSessionTransportResponseLengthTests.swift
//  HelpersTests
//
//  Created by Guilherme Souza on 12/11/26.
//

#if !canImport(FoundationNetworking)
  import Foundation
  import HTTPTypes
  import Network
  import Testing

  @testable import Helpers

  @Suite
  struct URLSessionTransportResponseLengthTests {
    private func head(_ fields: [HTTPField.Name: String]) -> HTTPResponse {
      var headerFields = HTTPFields()
      for (name, value) in fields { headerFields[name] = value }
      return HTTPResponse(status: .ok, headerFields: headerFields)
    }

    @Test
    func reportsTheDeclaredLengthOfAnUnencodedBody() {
      let length = URLSessionTransport.responseBodyLength(
        expectedContentLength: 2, head: head([.contentLength: "2"]))
      #expect(length == .known(2))
    }

    @Test
    func reportsUnknownWhenURLSessionDoesNotKnowTheLength() {
      let length = URLSessionTransport.responseBodyLength(
        expectedContentLength: -1, head: head([.contentEncoding: "gzip", .contentLength: "133"]))
      #expect(length == .unknown)
    }

    @Test(arguments: ["gzip", "br", "deflate", " GZIP "])
    func reportsUnknownWhenTheLengthIsTheEncodedContentLength(encoding: String) {
      let length = URLSessionTransport.responseBodyLength(
        expectedContentLength: 133, head: head([.contentEncoding: encoding, .contentLength: "133"]))
      #expect(length == .unknown)
    }

    @Test
    func reportsUnknownForAnEncodedBodyWhateverURLSessionReports() {
      let length = URLSessionTransport.responseBodyLength(
        expectedContentLength: 100_000,
        head: head([.contentEncoding: "gzip", .contentLength: "133, 133"]))
      #expect(length == .unknown)
    }

    @Test
    func reportsTheDeclaredLengthOfAnIdentityEncodedBody() {
      let length = URLSessionTransport.responseBodyLength(
        expectedContentLength: 133,
        head: head([.contentEncoding: "identity", .contentLength: "133"]))
      #expect(length == .known(133))
    }

    /// Runs against the real URLSession decoder, so CI checks the OS version each runner has.
    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func gzipResponseLengthMatchesTheDecodedBody(sendsBodyInTwoParts: Bool) async throws {
      let server = try GzipLoopbackServer(sendsBodyInTwoParts: sendsBodyInTwoParts)
      defer { server.stop() }
      let port = try await server.start()
      let transport = URLSessionTransport(session: URLSession(configuration: .ephemeral))

      let (_, maybeBody) = try await transport.send(
        HTTPRequest(method: .get, url: URL(string: "http://127.0.0.1:\(port)/")!), body: nil)

      let body = try #require(maybeBody)
      let length = body.length
      let data = try await Data(collecting: body, upTo: 1_000_000)
      #expect(data == GzipLoopbackServer.decodedBody)
      #expect(length == .unknown || length == .known(Int64(data.count)))
    }
  }

  /// Serves one gzip-encoded response with the encoded `Content-Length`, as a real server does.
  private final class GzipLoopbackServer: @unchecked Sendable {
    /// `gzip.compress(b"a" * 100_000, mtime=0)`.
    static let encodedBody = Data(
      base64Encoded:
        "H4sIAAAAAAAC/+3BMQEAAADCoKzrX8IaHkABAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAArwaH+uIboIYBAA=="
    )!
    static let decodedBody = Data(repeating: UInt8(ascii: "a"), count: 100_000)

    private let listener: NWListener
    private let queue = DispatchQueue(label: "co.supabase.GzipLoopbackServer")
    private let sendsBodyInTwoParts: Bool
    private var connections: [NWConnection] = []

    init(sendsBodyInTwoParts: Bool) throws {
      self.sendsBodyInTwoParts = sendsBodyInTwoParts
      let parameters = NWParameters.tcp
      parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
      listener = try NWListener(using: parameters)
    }

    func start() async throws -> UInt16 {
      listener.newConnectionHandler = { [weak self] connection in
        guard let self else { return connection.cancel() }
        connections.append(connection)
        connection.start(queue: queue)
        receiveHead(on: connection, buffer: Data())
      }
      return try await withCheckedThrowingContinuation { continuation in
        listener.stateUpdateHandler = { [listener] state in
          switch state {
          case .ready:
            listener.stateUpdateHandler = nil
            continuation.resume(returning: listener.port!.rawValue)
          case .failed(let error):
            listener.stateUpdateHandler = nil
            continuation.resume(throwing: error)
          case .cancelled:
            listener.stateUpdateHandler = nil
            continuation.resume(throwing: CancellationError())
          default:
            break
          }
        }
        listener.start(queue: queue)
      }
    }

    func stop() {
      listener.cancel()
      queue.sync { connections.forEach { $0.cancel() } }
    }

    private func receiveHead(on connection: NWConnection, buffer: Data) {
      connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) {
        [self] content, _, isComplete, error in
        let buffer = buffer + (content ?? Data())
        if buffer.range(of: Data("\r\n\r\n".utf8)) != nil {
          respond(on: connection)
        } else if error == nil, !isComplete {
          receiveHead(on: connection, buffer: buffer)
        } else {
          connection.cancel()
        }
      }
    }

    private func respond(on connection: NWConnection) {
      let body = Self.encodedBody
      let head = Data(
        """
        HTTP/1.1 200 OK\r
        Content-Encoding: gzip\r
        Content-Length: \(body.count)\r
        Connection: close\r
        \r

        """.utf8)
      let split = sendsBodyInTwoParts ? 20 : body.count
      connection.send(content: head + body.prefix(split), completion: .idempotent)
      queue.asyncAfter(deadline: .now() + .milliseconds(sendsBodyInTwoParts ? 200 : 0)) {
        connection.send(
          content: body.dropFirst(split), isComplete: true,
          completion: .contentProcessed { _ in connection.cancel() })
      }
    }
  }
#endif
