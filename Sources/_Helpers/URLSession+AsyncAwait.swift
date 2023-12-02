#if canImport(FoundationNetworking)
import Foundation
import FoundationNetworking

public enum URLSessionPolyfillError: Error {
  case noDataNoErrorReturned
}

extension URLSession {
  public func data(for request: URLRequest, delegate: (URLSessionTaskDelegate)? = nil) async throws -> (Data, URLResponse) {
    try await withCheckedThrowingContinuation({ continuation in
      let task = dataTask(with: request, completionHandler: { data, response, error in
        if let error {
          continuation.resume(throwing: error)
        } else if let data, let response {
          continuation.resume(returning: (data, response))
        } else {
          continuation.resume(throwing: URLSessionPolyfillError.noDataNoErrorReturned)
        }
      })

      task.resume()
    })
  }

  public func upload(for request: URLRequest, from bodyData: Data, delegate: (URLSessionTaskDelegate)? = nil) async throws -> (Data, URLResponse) {
    try await withCheckedThrowingContinuation({ continuation in
      let task = uploadTask(with: request, from: bodyData, completionHandler: { data, response, error in
        if let error {
          continuation.resume(throwing: error)
        } else if let data, let response {
          continuation.resume(returning: (data, response))
        } else {
          continuation.resume(throwing: URLSessionPolyfillError.noDataNoErrorReturned)
        }
      })

      task.resume()
    })
  }
}

#endif
