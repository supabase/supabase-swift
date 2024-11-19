import Foundation

/// Transform the asset before serving it to the client.
public struct TransformOptions: Encodable, Sendable {
  /// The width of the image in pixels.
  public var width: Int?
  /// The height of the image in pixels.
  public var height: Int?
  /// The resize mode can be cover, contain or fill. Defaults to cover.
  /// Cover resizes the image to maintain it's aspect ratio while filling the entire width and height.
  /// Contain resizes the image to maintain it's aspect ratio while fitting the entire image within the width and height.
  /// Fill resizes the image to fill the entire width and height. If the object's aspect ratio does not match the width and height, the image will be stretched to fit.
  public var resize: String?
  /// Set the quality of the returned image. A number from 20 to 100, with 100 being the highest quality. Defaults to 80.
  public var quality: Int?
  /// Specify the format of the image requested.
  public var format: String?

  public init(
    width: Int? = nil,
    height: Int? = nil,
    resize: String? = nil,
    quality: Int? = 80,
    format: String? = nil
  ) {
    self.width = width
    self.height = height
    self.resize = resize
    self.quality = quality
    self.format = format
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
