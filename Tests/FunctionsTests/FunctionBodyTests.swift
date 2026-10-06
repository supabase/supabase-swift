//
//  FunctionBodyTests.swift
//  Functions
//
//  Created by Guilherme Souza on 05/10/26.
//

import Foundation
import Helpers
import Testing

@testable import Functions

@Suite
struct FunctionBodyTests {
  @Test
  func json() async throws {
    struct Body: Encodable {
      let userName: String
    }
    let body = try FunctionBody.json(Body(userName: "test"))

    #expect(body.contentType == "application/json")
    #expect(try await bytes(body) == #"{"userName":"test"}"#)
  }

  @Test
  func jsonWithCustomEncoder() async throws {
    struct Body: Encodable {
      let userName: String
    }
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    let body = try FunctionBody.json(Body(userName: "test"), encoder: encoder)

    #expect(try await bytes(body) == #"{"user_name":"test"}"#)
  }

  @Test
  func jsonEncodesDatesAsISO8601ByDefault() async throws {
    let body = try FunctionBody.json(["at": Date(timeIntervalSince1970: 0)])

    #expect(try await bytes(body) == #"{"at":"1970-01-01T00:00:00.000Z"}"#)
  }

  /// A value that cannot be encoded never reaches the transport: the failure is reported as
  /// `.invalidRequest` instead of a bodiless request labelled `application/json`.
  @Test
  func jsonEncodeFailureThrowsInvalidRequest() {
    struct Failing: Encodable {
      struct Reason: Error {}
      func encode(to encoder: any Encoder) throws { throw Reason() }
    }

    do {
      _ = try FunctionBody.json(Failing())
      Issue.record("Expected failure")
    } catch let error as FunctionsError {
      #expect(error.kind == .invalidRequest)
      #expect(error.response == nil)
      #expect(error.underlyingError is Failing.Reason)
    } catch {
      Issue.record("Unexpected error \(error)")
    }
  }

  @Test
  func text() async throws {
    let body = FunctionBody.text("hello")

    #expect(body.contentType == "text/plain; charset=utf-8")
    #expect(try await bytes(body) == "hello")
  }

  @Test
  func data() async throws {
    let body = FunctionBody.data(Data([0, 1, 2]))

    #expect(body.contentType == "application/octet-stream")
    #expect(try await Data(collecting: body.httpBody, upTo: .max) == Data([0, 1, 2]))
  }

  @Test
  func dataWithContentType() {
    let body = FunctionBody.data(Data(), contentType: "image/jpeg")

    #expect(body.contentType == "image/jpeg")
  }

  @Test
  func stream() async throws {
    let httpBody = HTTPBody(Data("chunk".utf8))
    let body = FunctionBody.stream(httpBody, contentType: "audio/m4a")

    #expect(body.contentType == "audio/m4a")
    #expect(body.httpBody === httpBody)
  }

  private func bytes(_ body: FunctionBody) async throws -> String {
    String(decoding: try await Data(collecting: body.httpBody, upTo: .max), as: UTF8.self)
  }
}
