//
//  PostgrestTransportBridge.swift
//  PostgREST
//
//  Created by Guilherme Souza on 22/08/26.
//

import Foundation
import HTTPRuntime
import HTTPTypes

/// Drives a caller-supplied ``PostgrestTransport`` from the internal pipeline, which speaks
/// `HTTPRuntime`.
///
/// This exists because `HTTPRuntime` is `package`, so it cannot appear in a public protocol, while
/// the pipeline below this point is built on it. Nothing converts when no custom transport is
/// supplied — `HTTPRuntime.URLSessionTransport` is used directly, so the conversion is a cost only
/// callers who take over the transport pay.
struct PostgrestTransportBridge: HTTPRuntime.HTTPTransport {
  let transport: any PostgrestTransport

  func send(
    _ request: HTTPRuntime.HTTPRequest, uploadProgress: HTTPRuntime.ProgressHandler?
  ) async throws(HTTPRuntime.HTTPError) -> HTTPRuntime.HTTPResponse {
    // Upload progress is dropped rather than approximated. A `PostgrestTransport` has no way to
    // report it, and PostgREST never asks for it — no request it builds is large enough to need a
    // progress bar. Faking a single 100% callback would be worse than reporting nothing.
    let httpRequest: HTTPTypes.HTTPRequest
    let body: Data?
    do {
      httpRequest = try bridgedRequest(from: request)
      body = try bridgedBody(from: request.body)
    } catch let error as HTTPRuntime.HTTPError {
      throw error
    } catch {
      throw HTTPRuntime.HTTPError.transport(error)
    }

    do {
      let (data, response) = try await transport.send(httpRequest, body: body)
      return HTTPRuntime.HTTPResponse(head: bridgedHead(from: response), body: data)
    } catch {
      throw HTTPRuntime.HTTPError.transport(error)
    }
  }

  func stream(
    _ request: HTTPRuntime.HTTPRequest
  ) async throws(HTTPRuntime.HTTPError) -> HTTPRuntime.HTTPResponseStream {
    // A `PostgrestTransport` returns a buffered `(Data, HTTPResponse)`, so it cannot stream.
    // Failing loudly beats buffering the whole body and handing back a one-chunk stream, which
    // would look like streaming while defeating the point of it.
    throw HTTPRuntime.HTTPError.transport(PostgrestTransportStreamingUnsupported())
  }
}

/// Thrown when something asks a caller-supplied ``PostgrestTransport`` to stream.
struct PostgrestTransportStreamingUnsupported: Error, Sendable, CustomStringConvertible {
  var description: String {
    "A custom PostgrestTransport cannot stream a response. Nothing in PostgREST streams, so this "
      + "indicates a caller reaching the transport through an unintended path."
  }
}

private func bridgedRequest(
  from request: HTTPRuntime.HTTPRequest
) throws -> HTTPTypes.HTTPRequest {
  guard let components = URLComponents(url: request.url, resolvingAgainstBaseURL: false) else {
    throw HTTPRuntime.HTTPError.invalidURL(base: request.url, path: "")
  }

  var authority = components.host ?? ""
  if let port = components.port {
    authority += ":\(port)"
  }

  // `percentEncodedPath`, not `path`: `path` decodes, so a column or table name containing an
  // escaped character would be handed to the transport already mangled.
  var path = components.percentEncodedPath
  if let query = components.percentEncodedQuery {
    path += "?\(query)"
  }

  return HTTPTypes.HTTPRequest(
    method: postgrestHTTPMethod(from: request.method),
    scheme: components.scheme,
    authority: authority,
    path: path,
    headerFields: postgrestHeaderFields(from: request.headers)
  )
}

private func bridgedBody(from body: HTTPRuntime.HTTPBody?) throws -> Data? {
  switch body {
  case nil:
    return nil
  case .data(let data):
    return data
  case .file(let url):
    // Reading the file in would defeat the reason `.file` exists, which is streaming an upload
    // from disk without buffering it. PostgREST never produces one, so this is unreachable rather
    // than a limitation callers hit.
    throw HTTPRuntime.HTTPError.unsupportedRequestBody(
      "A custom PostgrestTransport cannot send a file-backed body (\(url.lastPathComponent)).")
  }
}

private func bridgedHead(from response: HTTPTypes.HTTPResponse) -> HTTPRuntime.HTTPResponseHead {
  HTTPRuntime.HTTPResponseHead(
    status: response.status.code,
    headers: postgrestHeaderDictionary(from: response.headerFields)
  )
}
