import Foundation

public struct File: Hashable, Equatable {
  public var name: String
  public var data: Data
  public var fileName: String?
  public var contentType: String?

  public init(name: String, data: Data, fileName: String?, contentType: String?) {
    self.name = name
    self.data = data
    self.fileName = fileName
    self.contentType = contentType
  }
}

public class FormData {
  var files: [File] = []
  var boundary: String

  public init(boundary: String = UUID().uuidString) {
    self.boundary = boundary
  }

  public func append(file: File) {
    files.append(file)
  }

  public var contentType: String {
    "multipart/form-data; boundary=\(boundary)"
  }

  public var data: Data {
    var data = Data()

    for file in files {
      data.append("--\(boundary)\r\n")
      data.append("Content-Disposition: form-data; name=\"\(file.name)\"")
      if let filename = file.fileName?.replacingOccurrences(of: "\"", with: "_") {
        data.append("; filename=\"\(filename)\"")
      }
      data.append("\r\n")
      if let contentType = file.contentType {
        data.append("Content-Type: \(contentType)\r\n")
      }
      data.append("\r\n")
      data.append(file.data)
      data.append("\r\n")
    }

    data.append("--\(boundary)--\r\n")
    return data
  }
}

extension Data {
  mutating func append(_ string: String) {
    let data = string.data(
      using: String.Encoding.utf8,
      allowLossyConversion: true
    )
    append(data!)
  }
}
