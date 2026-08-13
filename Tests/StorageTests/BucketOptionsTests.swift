import Testing

@testable import Storage

@Suite
struct BucketOptionsTests {
  @Test
  func defaultInitialization() {
    let options = BucketOptions(isPublic: false)

    #expect(!options.isPublic)
    #expect(options.fileSizeLimit == nil)
    #expect(options.allowedMimeTypes == nil)
  }

  @Test
  func customInitialization() {
    let options = BucketOptions(
      isPublic: true,
      fileSizeLimit: "5000000",
      allowedMimeTypes: ["image/jpeg", "image/png"]
    )

    #expect(options.isPublic)
    #expect(options.fileSizeLimit == "5000000")
    #expect(options.allowedMimeTypes == ["image/jpeg", "image/png"])
  }

  @Test
  func isPublicRename() {
    let options = BucketOptions(isPublic: true)
    #expect(options.isPublic)
  }

  @Test
  func fileSizeLimitInteger() {
    let options = BucketOptions(isPublic: false, fileSizeLimit: StorageByteCount(5_000_000))
    #expect(options.fileSizeLimit == "5000000")
  }

  @Test
  func fileSizeLimitMegabytes() {
    let options = BucketOptions(isPublic: false, fileSizeLimit: .megabytes(1.5))
    #expect(options.fileSizeLimit == "1.5mb")
  }

  @Test
  func fileSizeLimitIntegerLiteral() {
    let options = BucketOptions(fileSizeLimit: 5_000_000)
    #expect(options.fileSizeLimit == "5000000")
  }

  @Test
  func stringLiteralHumanReadable() {
    let options = BucketOptions(isPublic: false, fileSizeLimit: "1mb")
    #expect(options.fileSizeLimit == "1mb")
  }

  @Test
  func stringLiteralNumeric() {
    let options = BucketOptions(isPublic: false, fileSizeLimit: "5242880")
    #expect(options.fileSizeLimit == "5242880")
  }

  @Test
  func fileSizeLimitFromStoredByteCountVariable() {
    let limit: StorageByteCount? = "1mb"
    let options = BucketOptions(fileSizeLimit: limit)
    #expect(options.fileSizeLimit == "1mb")
  }

  @Test
  func isPublicWithStoredByteCountVariable() {
    let limit: StorageByteCount? = "1mb"
    let options = BucketOptions(isPublic: true, fileSizeLimit: limit)
    #expect(options.isPublic)
    #expect(options.fileSizeLimit == "1mb")
  }

  @Test
  func allowedMimeTypesOnly() {
    let options = BucketOptions(allowedMimeTypes: ["image/png"])
    #expect(!options.isPublic)
    #expect(options.fileSizeLimit == nil)
    #expect(options.allowedMimeTypes == ["image/png"])
  }
}
