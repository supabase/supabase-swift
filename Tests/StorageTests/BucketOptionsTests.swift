import Storage
import Testing

@Suite
struct BucketOptionsTests {
  @Test
  func defaultInitialization() {
    let options = BucketOptions()

    #expect(options.public == false)
    #expect(options.fileSizeLimit == nil)
    #expect(options.allowedMimeTypes == nil)
  }

  @Test
  func customInitialization() {
    let options = BucketOptions(
      public: true,
      fileSizeLimit: "5242880",
      allowedMimeTypes: ["image/jpeg", "image/png"]
    )

    #expect(options.public == true)
    #expect(options.fileSizeLimit == "5242880")
    #expect(options.allowedMimeTypes == ["image/jpeg", "image/png"])
  }
}
