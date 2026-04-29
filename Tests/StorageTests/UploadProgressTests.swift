import Testing

@testable import Storage

@Suite
struct UploadProgressTests {

  @Test func fractionCompleted_midUpload() {
    let progress = UploadProgress(totalBytesSent: 500, totalBytesExpectedToSend: 1000)
    #expect(abs(progress.fractionCompleted - 0.5) < 0.001)
  }

  @Test func fractionCompleted_complete() {
    let progress = UploadProgress(totalBytesSent: 1000, totalBytesExpectedToSend: 1000)
    #expect(abs(progress.fractionCompleted - 1.0) < 0.001)
  }

  @Test func fractionCompleted_zeroTotal() {
    let progress = UploadProgress(totalBytesSent: 0, totalBytesExpectedToSend: 0)
    #expect(progress.fractionCompleted == 0.0)
  }

  @Test func fractionCompleted_start() {
    let progress = UploadProgress(totalBytesSent: 0, totalBytesExpectedToSend: 2048)
    #expect(progress.fractionCompleted == 0.0)
  }
}
