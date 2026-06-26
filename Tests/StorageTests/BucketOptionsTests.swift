import Testing

@testable import Storage

@Suite
struct BucketOptionsTests {

  @Test func defaultInitialization() {
    let options = BucketOptions()

    #expect(!options.isPublic)
    #expect(options.fileSizeLimit == nil)
    #expect(options.allowedMimeTypes == nil)
  }

  @Test func customInitialization() {
    let options = BucketOptions(
      isPublic: true,
      fileSizeLimit: .megabytes(5),
      allowedMimeTypes: ["image/jpeg", "image/png"]
    )

    #expect(options.isPublic)
    #expect(options.fileSizeLimit == .megabytes(5))
    #expect(options.fileSizeLimit?.bytes == 5_242_880)
    #expect(options.allowedMimeTypes == ["image/jpeg", "image/png"])
  }

  @Test func integerLiteralFileSizeLimit() {
    let options = BucketOptions(isPublic: false, fileSizeLimit: 5_242_880)
    #expect(options.fileSizeLimit?.bytes == 5_242_880)
  }
}
