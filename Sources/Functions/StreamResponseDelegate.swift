import Foundation
import HTTPTypes

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

final class StreamResponseDelegate: NSObject, URLSessionDataDelegate, Sendable {
  let continuation: AsyncThrowingStream<Data, any Error>.Continuation

  /// Yields the response head once, or throws when the call fails before the head arrives.
  let head: AsyncThrowingStream<HTTPURLResponse, any Error>
  private let headContinuation: AsyncThrowingStream<HTTPURLResponse, any Error>.Continuation

  init(continuation: AsyncThrowingStream<Data, any Error>.Continuation) {
    self.continuation = continuation
    (head, headContinuation) = AsyncThrowingStream<HTTPURLResponse, any Error>.makeStream()
  }

  func urlSession(_: URLSession, dataTask _: URLSessionDataTask, didReceive data: Data) {
    continuation.yield(data)
  }

  func urlSession(_: URLSession, task _: URLSessionTask, didCompleteWithError error: (any Error)?) {
    headContinuation.finish(throwing: error)
    continuation.finish(throwing: error)
  }

  func urlSession(
    _: URLSession, dataTask _: URLSessionDataTask, didReceive response: URLResponse,
    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
  ) {
    defer {
      completionHandler(.allow)
    }

    guard let httpResponse = response as? HTTPURLResponse else {
      fail(URLError(.badServerResponse))
      return
    }

    let isRelayError = httpResponse.value(forHTTPHeaderField: "x-relay-error") == "true"
    if isRelayError {
      fail(FunctionsError.relayError)
      return
    }

    guard 200..<300 ~= httpResponse.statusCode else {
      let error = FunctionsError.httpError(
        code: httpResponse.statusCode,
        data: Data()
      )
      fail(error)
      return
    }

    headContinuation.yield(httpResponse)
    headContinuation.finish()
  }

  private func fail(_ error: any Error) {
    headContinuation.finish(throwing: error)
    continuation.finish(throwing: error)
  }
}
