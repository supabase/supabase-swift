import Testing

@testable import Storage

@Suite
struct TransferProgressTests {

  @Test func fractionCompleted_midUpload() {
    let progress = TransferProgress(bytesTransferred: 500, totalBytes: 1000)
    #expect(abs(progress.fractionCompleted - 0.5) < 0.001)
  }

  @Test func fractionCompleted_complete() {
    let progress = TransferProgress(bytesTransferred: 1000, totalBytes: 1000)
    #expect(abs(progress.fractionCompleted - 1.0) < 0.001)
  }

  @Test func fractionCompleted_zeroTotal() {
    let progress = TransferProgress(bytesTransferred: 0, totalBytes: 0)
    #expect(progress.fractionCompleted == 0.0)
  }

  @Test func fractionCompleted_start() {
    let progress = TransferProgress(bytesTransferred: 0, totalBytes: 2048)
    #expect(progress.fractionCompleted == 0.0)
  }
}
