import Testing

@testable import Storage

@Suite
struct StorageByteCountTests {

  @Test func bytes() {
    #expect(StorageByteCount.bytes(1024).bytes == 1024)
  }

  @Test func kilobytes() {
    #expect(StorageByteCount.kilobytes(1).bytes == 1_024)
    #expect(StorageByteCount.kilobytes(10).bytes == 10_240)
  }

  @Test func megabytes() {
    #expect(StorageByteCount.megabytes(1).bytes == 1_048_576)
    #expect(StorageByteCount.megabytes(5).bytes == 5_242_880)
  }

  @Test func gigabytes() {
    #expect(StorageByteCount.gigabytes(1).bytes == 1_073_741_824)
  }

  @Test func integerLiteral() {
    let count: StorageByteCount = 5_242_880
    #expect(count.bytes == 5_242_880)
  }

  @Test func equality() {
    #expect(StorageByteCount.megabytes(1) == StorageByteCount.kilobytes(1024))
    #expect(StorageByteCount.megabytes(1) != StorageByteCount.megabytes(2))
  }
}
