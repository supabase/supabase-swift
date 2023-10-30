import Foundation

public struct TransformOptions {
  public var width: Int?
  public var height: Int?
  public var resize: String?
  public var quality: Int?
  public var format: String?

  public init(
    width: Int? = nil,
    height: Int? = nil,
    resize: String? = "cover",
    quality: Int? = 80,
    format: String? = "origin"
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
