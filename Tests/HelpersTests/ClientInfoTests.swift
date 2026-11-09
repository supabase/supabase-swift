import Helpers
import Testing

@Suite
struct ClientInfoTests {
  @Test
  func listsTheLibraryPlatformAndRuntime() {
    #expect(
      clientInfo(
        library: "auth-swift",
        version: "3.0.0",
        platform: "iOS",
        platformVersion: "18.1.0",
        runtimeVersion: "6.2"
      )
        == "auth-swift/3.0.0; platform=iOS; platform-version=18.1.0; runtime=swift; runtime-version=6.2"
    )
  }

  @Test
  func leavesOutTheValuesItCannotDetect() {
    #expect(
      clientInfo(
        library: "auth-swift",
        version: "3.0.0",
        platform: nil,
        platformVersion: nil,
        runtimeVersion: nil
      ) == "auth-swift/3.0.0; runtime=swift"
    )
  }

  @Test
  func defaultsToThisBuildsValues() {
    #expect(
      clientInfo(library: "storage-swift")
        == "storage-swift/0.0.0; platform=macOS; platform-version=0.0.0; runtime=swift; runtime-version=0.0.0"
    )
  }

  @Test
  func apikeyNameIsLowercase() {
    #expect(HTTPField.Name.apikey.canonicalName == "apikey")
  }
}
