import Foundation

/// Options for on-the-fly image transformation via the Supabase Storage image transformation API.
///
/// Use `TransformOptions` when calling
/// ``StorageFileAPI/download(path:options:query:cacheNonce:)`` or
/// ``StorageFileAPI/getPublicURL(path:download:options:cacheNonce:)`` to resize, reformat, or
/// adjust the quality of images before they are served to the client.
///
/// ## Example
///
/// ```swift
/// // Serve a 200×200 thumbnail, retaining aspect ratio, at 75% quality
/// let url = try storage.from("avatars").getPublicURL(
///   path: "user-123/avatar.png",
///   options: TransformOptions(width: 200, height: 200, resize: "contain", quality: 75)
/// )
/// ```
public struct TransformOptions: Encodable, Sendable {
  /// The target width of the transformed image in pixels.
  public var width: Int?

  /// The target height of the transformed image in pixels.
  public var height: Int?

  /// Controls how the image is resized to fit the target dimensions.
  ///
  /// Supported values:
  /// - `"cover"` — Resizes to fill the target dimensions while maintaining the aspect ratio.
  ///   Portions of the image that overflow the bounds are cropped. This is the default.
  /// - `"contain"` — Resizes so the entire image fits within the target dimensions while
  ///   maintaining the aspect ratio. May leave empty space around the image.
  /// - `"fill"` — Stretches the image to exactly fill the target dimensions, ignoring the
  ///   original aspect ratio.
  public var resize: String?

  /// The quality of the returned image, from `20` (lowest) to `100` (highest).
  ///
  /// Applies to lossy formats such as JPEG and WebP. Defaults to `80`.
  public var quality: Int?

  /// The output format for the transformed image (e.g. `"origin"`, `"webp"`).
  ///
  /// Passing `"origin"` preserves the original format of the file. Leave `nil` to let the
  /// server choose an appropriate format.
  public var format: String?

  public init(
    width: Int? = nil,
    height: Int? = nil,
    resize: String? = nil,
    quality: Int? = nil,
    format: String? = nil
  ) {
    self.width = width
    self.height = height
    self.resize = resize
    self.quality = quality
    self.format = format
  }

  var isEmpty: Bool {
    queryItems.isEmpty
  }

  var queryItems: [URLQueryItem] {
    var items = [URLQueryItem]()

    if let width {
      items.append(URLQueryItem(name: "width", value: String(width)))
    }

    if let height {
      items.append(URLQueryItem(name: "height", value: String(height)))
    }

    if let resize {
      items.append(URLQueryItem(name: "resize", value: resize))
    }

    if let quality {
      items.append(URLQueryItem(name: "quality", value: String(quality)))
    }

    if let format {
      items.append(URLQueryItem(name: "format", value: format))
    }

    return items
  }
}
