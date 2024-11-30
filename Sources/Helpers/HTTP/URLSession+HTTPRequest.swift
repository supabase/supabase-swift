import Foundation
import HTTPTypes

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

#if !os(WASI)

  extension URLSessionTask {
    /// The original HTTP request this task was created with.
    public var originalHTTPRequest: HTTPRequest? {
      self.originalRequest?.httpRequest
    }

    /// The current HTTP request -- may differ from the `originalHTTPRequest` due to HTTP redirection.
    public var currentHTTPRequest: HTTPRequest? {
      self.currentRequest?.httpRequest
    }

    /// The HTTP response received from the server.
    public var httpResponse: HTTPResponse? {
      (self.response as? HTTPURLResponse)?.httpResponse
    }
  }

  private enum HTTPTypeConversionError: Error {
    case failedToConvertHTTPRequestToURLRequest
    case failedToConvertURLResponseToHTTPResponse
  }

#endif

#if canImport(FoundationNetworking) && compiler(<6)

  @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
  extension URLSession {
    /// Convenience method to load data using an `HTTPRequest`; creates and resumes a `URLSessionDataTask` internally.
    ///
    /// - Parameter request: The `HTTPRequest` for which to load data.
    /// - Parameter delegate: Task-specific delegate.
    /// - Returns: Data and response.
    public func data(
      for request: HTTPRequest,
      delegate: (any URLSessionTaskDelegate)? = nil
    ) async throws -> (Data, HTTPResponse) {
      guard let urlRequest = URLRequest(httpRequest: request) else {
        throw HTTPTypeConversionError.failedToConvertHTTPRequestToURLRequest
      }
      let (data, urlResponse) = try await self.data(for: urlRequest, delegate: delegate)
      guard let response = (urlResponse as? HTTPURLResponse)?.httpResponse else {
        throw HTTPTypeConversionError.failedToConvertURLResponseToHTTPResponse
      }
      return (data, response)
    }

    /// Convenience method to upload data using an `HTTPRequest`, creates and resumes a `URLSessionUploadTask` internally.
    ///
    /// - Parameter request: The `HTTPRequest` for which to upload data.
    /// - Parameter bodyData: Data to upload.
    /// - Parameter delegate: Task-specific delegate.
    /// - Returns: Data and response.
    public func upload(
      for request: HTTPRequest,
      from bodyData: Data,
      delegate: (any URLSessionTaskDelegate)? = nil
    ) async throws -> (Data, HTTPResponse) {
      guard let urlRequest = URLRequest(httpRequest: request) else {
        throw HTTPTypeConversionError.failedToConvertHTTPRequestToURLRequest
      }
      let (data, urlResponse) = try await self.upload(
        for: urlRequest, from: bodyData, delegate: delegate)
      guard let response = (urlResponse as? HTTPURLResponse)?.httpResponse else {
        throw HTTPTypeConversionError.failedToConvertURLResponseToHTTPResponse
      }
      return (data, response)
    }
  }

  @available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
  extension URLSession {
    /// Convenience method to load data using an `HTTPRequest`; creates and resumes a `URLSessionDataTask` internally.
    ///
    /// - Parameter request: The `HTTPRequest` for which to load data.
    /// - Returns: Data and response.
    public func data(for request: HTTPRequest) async throws -> (Data, HTTPResponse) {
      guard let urlRequest = URLRequest(httpRequest: request) else {
        throw HTTPTypeConversionError.failedToConvertHTTPRequestToURLRequest
      }
      let (data, urlResponse) = try await self.data(for: urlRequest)
      guard let response = (urlResponse as? HTTPURLResponse)?.httpResponse else {
        throw HTTPTypeConversionError.failedToConvertURLResponseToHTTPResponse
      }
      return (data, response)
    }

    /// Convenience method to upload data using an `HTTPRequest`, creates and resumes a `URLSessionUploadTask` internally.
    ///
    /// - Parameter request: The `HTTPRequest` for which to upload data.
    /// - Parameter bodyData: Data to upload.
    /// - Returns: Data and response.
    public func upload(for request: HTTPRequest, from bodyData: Data) async throws -> (
      Data, HTTPResponse
    ) {
      guard let urlRequest = URLRequest(httpRequest: request) else {
        throw HTTPTypeConversionError.failedToConvertHTTPRequestToURLRequest
      }
      let (data, urlResponse) = try await self.upload(for: urlRequest, from: bodyData)
      guard let response = (urlResponse as? HTTPURLResponse)?.httpResponse else {
        throw HTTPTypeConversionError.failedToConvertURLResponseToHTTPResponse
      }
      return (data, response)
    }
  }

#endif
