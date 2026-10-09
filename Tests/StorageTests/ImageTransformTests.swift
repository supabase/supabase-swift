import Foundation
import Testing

@testable import Storage

@Suite
struct ImageTransformTests {
  @Test
  func defaultInitialization() {
    let transform = ImageTransform()

    #expect(transform.width == nil)
    #expect(transform.height == nil)
    #expect(transform.resize == nil)
    #expect(transform.quality == nil)
    #expect(transform.format == nil)
    #expect(transform.gravity == nil)
    #expect(transform.focalPoint == nil)
    #expect(transform.isEmpty)
  }

  @Test(
    arguments: [
      ImageTransform(width: 200),
      ImageTransform(height: 300),
      ImageTransform(resize: .cover),
      ImageTransform(quality: 90),
      ImageTransform(format: .webp),
      ImageTransform(gravity: .north),
      ImageTransform(focalPoint: .init(x: 0.5, y: 0.5)),
    ])
  func isNotEmptyWithAnyField(transform: ImageTransform) {
    #expect(!transform.isEmpty)
  }

  @Test
  func queryItemsCarryEveryField() {
    let transform = ImageTransform(
      width: 100,
      height: 200,
      resize: .contain,
      quality: 90,
      format: .webp,
      gravity: .focalPoint,
      focalPoint: .init(x: 0.25, y: 0.75)
    )

    let items = transform.queryItems.map { "\($0.name)=\($0.value ?? "")" }

    #expect(
      items == [
        "width=100", "height=200", "resize=contain", "quality=90", "format=webp", "gravity=fp",
        "x_offset=0.25", "y_offset=0.75",
      ])
  }

  @Test
  func queryItemsSkipNilFields() {
    let items = ImageTransform(width: 100, quality: 75).queryItems.map {
      "\($0.name)=\($0.value ?? "")"
    }

    #expect(items == ["width=100", "quality=75"])
  }

  @Test
  func bodyUsesTheWireKeys() throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let transform = ImageTransform(
      width: 100, resize: .cover, gravity: .focalPoint, focalPoint: .init(x: 0.1, y: 0.9))

    let json = try String(decoding: encoder.encode(transform.body), as: UTF8.self)

    #expect(
      json
        == #"{"gravity":"fp","resize":"cover","width":100,"x_offset":0.1,"y_offset":0.9}"#
    )
  }
}

@Suite
struct GravityTests {
  @Test
  func rawValuesMatchTheAPI() {
    #expect(Gravity.north.rawValue == "no")
    #expect(Gravity.south.rawValue == "so")
    #expect(Gravity.east.rawValue == "ea")
    #expect(Gravity.west.rawValue == "we")
    #expect(Gravity.northEast.rawValue == "noea")
    #expect(Gravity.northWest.rawValue == "nowe")
    #expect(Gravity.southEast.rawValue == "soea")
    #expect(Gravity.southWest.rawValue == "sowe")
    #expect(Gravity.center.rawValue == "ce")
    #expect(Gravity.smart.rawValue == "sm")
    #expect(Gravity.focalPoint.rawValue == "fp")
  }

  @Test
  func stringLiteral() {
    let gravity: Gravity = "no"
    #expect(gravity == .north)
  }
}
