import Foundation

/// Options for ``StorageFileApi/createSignedURL(path:expiresIn:options:)``.
///
/// ```swift
/// let url = try await bucket.createSignedURL(
///   path: "report.pdf",
///   expiresIn: .seconds(60),
///   options: SignedURLOptions(download: .withOriginalName)
/// )
/// ```
public struct SignedURLOptions: Sendable {
  /// Controls whether the URL triggers a file download. `nil` (the default) displays the file
  /// inline.
  public var download: DownloadBehavior?

  /// An image transformation that Storage applies before delivery.
  public var transform: ImageTransform?

  /// The version the URL serves. `nil` (the default) serves the current version.
  public var versionID: String?

  /// A nonce appended as a `cacheNonce` query parameter, so a CDN serves a fresh copy instead
  /// of a cached one.
  public var cacheNonce: String?

  /// Creates a ``SignedURLOptions`` value.
  ///
  /// - Parameters:
  ///   - download: Controls whether the URL triggers a file download. Pass `.withOriginalName`
  ///     to download with the file's original name, or `.named("custom.pdf")` for a custom name.
  ///   - transform: An image transformation that Storage applies before delivery.
  ///   - versionID: The version the URL serves.
  ///   - cacheNonce: A cache-busting nonce sent as the `cacheNonce` query parameter.
  public init(
    download: DownloadBehavior? = nil,
    transform: ImageTransform? = nil,
    versionID: String? = nil,
    cacheNonce: String? = nil
  ) {
    self.download = download
    self.transform = transform
    self.versionID = versionID
    self.cacheNonce = cacheNonce
  }
}

/// Options for ``StorageFileApi/createSignedURLs(paths:expiresIn:options:)``.
public struct SignedURLsOptions: Sendable {
  /// Controls whether the URLs trigger a file download. `nil` (the default) displays the files
  /// inline.
  public var download: DownloadBehavior?

  /// A nonce appended as a `cacheNonce` query parameter, so a CDN serves a fresh copy instead
  /// of a cached one.
  public var cacheNonce: String?

  /// Creates a ``SignedURLsOptions`` value.
  ///
  /// - Parameters:
  ///   - download: Controls whether the URLs trigger a file download. Pass `.withOriginalName`
  ///     to download with each file's original name, or `.named("custom")` for a custom name.
  ///   - cacheNonce: A cache-busting nonce sent as the `cacheNonce` query parameter.
  public init(download: DownloadBehavior? = nil, cacheNonce: String? = nil) {
    self.download = download
    self.cacheNonce = cacheNonce
  }
}

/// Options for ``StorageFileApi/publicURL(path:options:)``.
///
/// ```swift
/// let url = bucket.publicURL(path: "report.pdf", options: PublicURLOptions(download: .withOriginalName))
/// ```
public struct PublicURLOptions: Sendable {
  /// Controls whether the URL triggers a file download. `nil` (the default) displays the file
  /// inline.
  public var download: DownloadBehavior?

  /// An image transformation that Storage applies before delivery.
  public var transform: ImageTransform?

  /// The version the URL serves. `nil` (the default) serves the current version.
  public var versionID: String?

  /// A nonce appended as a `cacheNonce` query parameter, so a CDN serves a fresh copy instead
  /// of a cached one.
  public var cacheNonce: String?

  /// Creates a ``PublicURLOptions`` value.
  ///
  /// - Parameters:
  ///   - download: Controls whether the URL triggers a file download. Pass `.withOriginalName`
  ///     to download with the file's original name, or `.named("custom.pdf")` for a custom name.
  ///   - transform: An image transformation that Storage applies before delivery.
  ///   - versionID: The version the URL serves.
  ///   - cacheNonce: A cache-busting nonce sent as the `cacheNonce` query parameter.
  public init(
    download: DownloadBehavior? = nil,
    transform: ImageTransform? = nil,
    versionID: String? = nil,
    cacheNonce: String? = nil
  ) {
    self.download = download
    self.transform = transform
    self.versionID = versionID
    self.cacheNonce = cacheNonce
  }
}
