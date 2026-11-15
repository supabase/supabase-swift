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
  func percentEncodesSemicolonsPercentSignsAndNonPrintableASCIIInValues() {
    #expect(
      clientInfo(
        library: "auth-swift",
        version: "3.0.0",
        platform: "Linux",
        platformVersion: "1;2%3 é\t",
        runtimeVersion: "6.2"
      )
        == "auth-swift/3.0.0; platform=Linux; platform-version=1%3B2%253 %C3%A9; runtime=swift; runtime-version=6.2"
    )
  }

  @Test
  func leavesOutValuesThatAreEmptyAfterTrimming() {
    #expect(
      clientInfo(
        library: "auth-swift",
        version: "3.0.0",
        platform: " ",
        platformVersion: "",
        runtimeVersion: nil
      ) == "auth-swift/3.0.0; runtime=swift"
    )
  }

  @Test
  func kernelReleaseIsTheThirdFieldOfProcVersion() {
    let procVersion = """
      Linux version 6.8.0-45-generic (builder@lcy02-amd64-075) \
      (x86_64-linux-gnu-gcc-13 (Ubuntu 13.2.0-23ubuntu4) 13.2.0) #45-Ubuntu SMP PREEMPT_DYNAMIC

      """
    #expect(kernelRelease(procVersion: procVersion) == "6.8.0-45-generic")
  }

  @Test
  func kernelReleaseIsNilForAnUnexpectedProcVersion() {
    #expect(kernelRelease(procVersion: "") == nil)
    #expect(kernelRelease(procVersion: "Linux version") == nil)
    #expect(kernelRelease(procVersion: "FreeBSD 14.1-RELEASE") == nil)
  }

  @Test
  func apikeyNameIsLowercase() {
    #expect(HTTPField.Name.apikey.canonicalName == "apikey")
  }
}
