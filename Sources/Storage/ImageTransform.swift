import Foundation

/// A server-side image transformation applied before the asset is served.
///
/// Set an ``ImageTransform`` as the `transform` of the options of
/// ``StorageBucket/publicURL(path:options:)`` or
/// ``StorageBucket/createSignedURL(path:expiresIn:options:)``
/// to resize, crop, reformat, or adjust the quality of an image on the fly.
///
/// ```swift
/// let transform = ImageTransform(width: 200, height: 200, resize: .cover, quality: 80)
/// let thumbnail = storage.from("avatars").publicURL(
///   path: "user.png", options: PublicURLOptions(transform: transform))
/// ```
///
/// ## Topics
///
/// ### Creating a transform
///
/// - ``init(width:height:resize:quality:format:gravity:focalPoint:)``
///
/// ### Dimensions and format
///
/// - ``width``
/// - ``height``
/// - ``resize``
/// - ``quality``
/// - ``format``
///
/// ### Cropping
///
/// - ``gravity``
/// - ``focalPoint``
public struct ImageTransform: Hashable, Sendable {
  /// Target width in pixels.
  public var width: Int?

  /// Target height in pixels.
  public var height: Int?

  /// How the image is resized to fit the target dimensions. Defaults to ``ResizeMode/cover``.
  public var resize: ResizeMode?

  /// Output quality, from 20 to 100. Higher values produce larger files. Defaults to 80.
  public var quality: Int?

  /// Output image format. Defaults to the source format.
  public var format: ImageFormat?

  /// Which part of the image to keep when ``resize`` is ``ResizeMode/cover`` crops it.
  /// Defaults to ``Gravity/center``.
  public var gravity: Gravity?

  /// The point to keep when ``gravity`` is ``Gravity/focalPoint``.
  public var focalPoint: FocalPoint?

  /// Creates an ``ImageTransform``.
  ///
  /// - Parameters:
  ///   - width: Target width in pixels.
  ///   - height: Target height in pixels.
  ///   - resize: Resize strategy. Defaults to ``ResizeMode/cover`` when `nil`.
  ///   - quality: Output quality from 20–100. Defaults to 80 when `nil`.
  ///   - format: Output image format. Defaults to the source format when `nil`.
  ///   - gravity: Which part of the image a cover crop keeps. Defaults to the center when `nil`.
  ///   - focalPoint: The point a ``Gravity/focalPoint`` crop keeps.
  public init(
    width: Int? = nil,
    height: Int? = nil,
    resize: ResizeMode? = nil,
    quality: Int? = nil,
    format: ImageFormat? = nil,
    gravity: Gravity? = nil,
    focalPoint: FocalPoint? = nil
  ) {
    self.width = width
    self.height = height
    self.resize = resize
    self.quality = quality
    self.format = format
    self.gravity = gravity
    self.focalPoint = focalPoint
  }

  var isEmpty: Bool {
    queryItems.isEmpty
  }

  /// The transform as the `render` routes read it from the query string.
  var queryItems: [URLQueryItem] {
    var items = [URLQueryItem]()

    if let width {
      items.append(URLQueryItem(name: "width", value: String(width)))
    }

    if let height {
      items.append(URLQueryItem(name: "height", value: String(height)))
    }

    if let resize {
      items.append(URLQueryItem(name: "resize", value: resize.rawValue))
    }

    if let quality {
      items.append(URLQueryItem(name: "quality", value: String(quality)))
    }

    if let format {
      items.append(URLQueryItem(name: "format", value: format.rawValue))
    }

    if let gravity {
      items.append(URLQueryItem(name: "gravity", value: gravity.rawValue))
    }

    if let focalPoint {
      items.append(URLQueryItem(name: "x_offset", value: focalPoint.x.description))
      items.append(URLQueryItem(name: "y_offset", value: focalPoint.y.description))
    }

    return items
  }

  /// The transform as the sign route reads it from the request body.
  struct Body: Encodable {
    let width: Int?
    let height: Int?
    let resize: String?
    let quality: Int?
    let format: String?
    let gravity: String?
    let xOffset: Double?
    let yOffset: Double?

    enum CodingKeys: String, CodingKey {
      case width, height, resize, quality, format, gravity
      case xOffset = "x_offset"
      case yOffset = "y_offset"
    }
  }

  var body: Body {
    Body(
      width: width, height: height, resize: resize?.rawValue, quality: quality,
      format: format?.rawValue, gravity: gravity?.rawValue, xOffset: focalPoint?.x,
      yOffset: focalPoint?.y)
  }
}

/// Which part of an image a ``ResizeMode/cover`` crop keeps.
///
/// ```swift
/// ImageTransform(width: 200, height: 200, resize: .cover, gravity: .north)
/// ImageTransform(width: 200, height: 200, gravity: .focalPoint, focalPoint: .init(x: 0.3, y: 0.7))
/// ```
///
/// ## Topics
///
/// ### Edges and corners
///
/// - ``north``
/// - ``south``
/// - ``east``
/// - ``west``
/// - ``northEast``
/// - ``northWest``
/// - ``southEast``
/// - ``southWest``
///
/// ### Content-based
///
/// - ``center``
/// - ``smart``
/// - ``focalPoint``
public struct Gravity: RawRepresentable, Hashable, Sendable {
  /// The raw string value sent to the API.
  public let rawValue: String

  /// Creates a ``Gravity`` from a raw string value.
  ///
  /// - Parameter rawValue: The gravity string understood by the Storage image API.
  public init(rawValue: String) { self.rawValue = rawValue }

  /// Keep the top edge.
  public static let north = Gravity(rawValue: "no")

  /// Keep the bottom edge.
  public static let south = Gravity(rawValue: "so")

  /// Keep the right edge.
  public static let east = Gravity(rawValue: "ea")

  /// Keep the left edge.
  public static let west = Gravity(rawValue: "we")

  /// Keep the top-right corner.
  public static let northEast = Gravity(rawValue: "noea")

  /// Keep the top-left corner.
  public static let northWest = Gravity(rawValue: "nowe")

  /// Keep the bottom-right corner.
  public static let southEast = Gravity(rawValue: "soea")

  /// Keep the bottom-left corner.
  public static let southWest = Gravity(rawValue: "sowe")

  /// Keep the center. The default.
  public static let center = Gravity(rawValue: "ce")

  /// Let the server pick the most interesting region.
  public static let smart = Gravity(rawValue: "sm")

  /// Keep the point given by ``ImageTransform/focalPoint``.
  public static let focalPoint = Gravity(rawValue: "fp")
}

extension Gravity: ExpressibleByStringLiteral {
  /// Creates a ``Gravity`` from a string literal.
  public init(stringLiteral value: String) { self.init(rawValue: value) }
}

/// The point of an image a ``Gravity/focalPoint`` crop keeps, as fractions of the width and
/// height from the top-left corner, each in `0...1`.
public struct FocalPoint: Hashable, Sendable {
  /// Horizontal position, `0` at the left edge and `1` at the right edge.
  public var x: Double

  /// Vertical position, `0` at the top edge and `1` at the bottom edge.
  public var y: Double

  /// Creates a ``FocalPoint``.
  ///
  /// - Parameters:
  ///   - x: Horizontal position in `0...1`.
  ///   - y: Vertical position in `0...1`.
  public init(x: Double, y: Double) {
    self.x = x
    self.y = y
  }
}
