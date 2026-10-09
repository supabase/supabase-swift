import Testing

@testable import Storage

@Suite
struct BucketOptionsTests {
  @Test
  func everyFieldDefaultsToNil() {
    let options = BucketOptions()

    #expect(options.isPublic == nil)
    #expect(options.fileSizeLimit == nil)
    #expect(options.allowedMimeTypes == nil)
  }

  @Test
  func customInitialization() {
    let options = BucketOptions(
      isPublic: true,
      fileSizeLimit: .megabytes(5),
      allowedMimeTypes: ["image/jpeg", "image/png"]
    )

    #expect(options.isPublic == true)
    #expect(options.fileSizeLimit == "5mb")
    #expect(options.allowedMimeTypes == ["image/jpeg", "image/png"])
  }

  @Test
  func fileSizeLimitFromAnIntegerLiteral() {
    #expect(BucketOptions(fileSizeLimit: 5_000_000).fileSizeLimit?.bytes == 5_000_000)
  }
}
