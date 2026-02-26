//
//  HTTPDownloadResponse.swift
//
//
//  Created by Claude Code on 26/02/26.
//

import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// A download response containing the downloaded data and progress information.
///
/// This type is returned by `download(progress:)` methods and includes the total
/// number of bytes received, which is useful for progress tracking and debugging.
///
/// Example:
/// ```swift
/// let downloadResponse = try await httpSession.download(request) { bytesSent, totalBytes in
///   let progress = Double(bytesSent) / Double(totalBytes)
///   print("Download progress: \(progress * 100)%")
/// }
/// print("Downloaded \(downloadResponse.bytesReceived) bytes")
/// ```
package struct HTTPDownloadResponse: Sendable {
  /// The downloaded data.
  package let data: Data

  /// The HTTP response metadata (status code, headers, etc.).
  package let response: HTTPURLResponse

  /// The total number of bytes received during the download.
  ///
  /// This value matches `data.count` and is provided for convenience and consistency
  /// with the progress callback parameters.
  package let bytesReceived: Int64

  package init(data: Data, response: HTTPURLResponse, bytesReceived: Int64) {
    self.data = data
    self.response = response
    self.bytesReceived = bytesReceived
  }
}
