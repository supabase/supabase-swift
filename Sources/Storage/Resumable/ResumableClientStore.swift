import ConcurrencyExtras
import Foundation

/// Creates and stores ResumableUploadClient instances by bucketId
actor ResumableClientStore {
  private let configuration: StorageClientConfiguration

  var clients = LockIsolated<[String: ResumableUploadClient]>([:])

  init(configuration: StorageClientConfiguration) {
    self.configuration = configuration
  }

  func getOrCreateClient(for bucketId: String) throws -> ResumableUploadClient {
    if let client = clients.value[bucketId] {
      return client
    } else {
      let client = try ResumableUploadClient(bucketId: bucketId, configuration: configuration)
      clients.withValue { $0[bucketId] = client }
      return client
    }
  }

  func removeClient(for bucketId: String) {
    clients.withValue { _ = $0.removeValue(forKey: bucketId) }
  }

  func removeAllClients() {
    clients.setValue([:])
  }
}
