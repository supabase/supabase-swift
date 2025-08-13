import Foundation
import Helpers
import Logging

/// Advanced storage client with streaming, background, and resumable upload capabilities.
public class SupabaseStorageClientAdvanced: @unchecked Sendable {
  private let baseClient: SupabaseStorageClient
  private let enhancedConfiguration: EnhancedStorageClientConfiguration
  
  // Multiple HTTP clients for different use cases
  private let standardClient: Helpers.Client
  private let streamingClient: Helpers.Client?
  private let backgroundClient: Helpers.Client?
  private let resumableClient: Helpers.Client?
  
  /// Creates a new advanced storage client.
  /// - Parameter configuration: The enhanced storage client configuration.
  public init(configuration: EnhancedStorageClientConfiguration) {
    self.baseClient = SupabaseStorageClient(configuration: configuration.base)
    self.enhancedConfiguration = configuration
    
    // Standard client (existing functionality)
    self.standardClient = Helpers.Client(
      serverURL: configuration.base.url,
      transport: FetchTransportAdapter(fetch: configuration.base.session.fetch)
    )
    
    // Streaming client for large file operations
    if configuration.advanced.enableStreaming {
      self.streamingClient = Helpers.Client(
        serverURL: configuration.base.url,
        transport: StreamingURLSessionTransport(
          configuration: configuration.advanced.streamingSessionConfiguration
        )
      )
    } else {
      self.streamingClient = nil
    }
    
    // Background client for persistent uploads
    if let backgroundId = configuration.advanced.backgroundIdentifier {
      self.backgroundClient = Helpers.Client(
        serverURL: configuration.base.url,
        transport: BackgroundURLSessionTransport(identifier: backgroundId, handler: BackgroundUploadManager.shared)
      )
    } else {
      self.backgroundClient = nil
    }
    
    // Resumable client for reliable transfers
    if configuration.advanced.enableResumableUploads {
      self.resumableClient = Helpers.Client(
        serverURL: configuration.base.url,
        transport: ResumableURLSessionTransport(
          configuration: configuration.advanced.resumableSessionConfiguration
        )
      )
    } else {
      self.resumableClient = nil
    }
  }
  
  /// Access advanced file operations for a specific bucket.
  /// - Parameter id: The bucket identifier.
  /// - Returns: An advanced storage file API instance.
  public func from(_ id: String) -> StorageFileApiAdvanced {
    StorageFileApiAdvanced(
      bucketId: id,
      configuration: enhancedConfiguration,
      standardClient: standardClient,
      streamingClient: streamingClient,
      backgroundClient: backgroundClient,
      resumableClient: resumableClient
    )
  }
}

// MARK: - Bucket Operations

extension SupabaseStorageClientAdvanced {
  /// The storage client configuration.
  public var configuration: StorageClientConfiguration {
    baseClient.configuration
  }
  
  /// Retrieves the details of all Storage buckets within an existing project.
  public func listBuckets() async throws -> [Bucket] {
    try await baseClient.listBuckets()
  }
  
  /// Retrieves the details of an existing Storage bucket.
  /// - Parameter id: The unique identifier of the bucket you would like to retrieve.
  public func getBucket(_ id: String) async throws -> Bucket {
    try await baseClient.getBucket(id)
  }
  
  /// Creates a new Storage bucket.
  /// - Parameters:
  ///   - id: A unique identifier for the bucket you are creating.
  ///   - options: Options for creating the bucket.
  public func createBucket(_ id: String, options: BucketOptions = .init()) async throws {
    try await baseClient.createBucket(id, options: options)
  }
  
  /// Updates a Storage bucket.
  /// - Parameters:
  ///   - id: A unique identifier for the bucket you are updating.
  ///   - options: Options for updating the bucket.
  public func updateBucket(_ id: String, options: BucketOptions) async throws {
    try await baseClient.updateBucket(id, options: options)
  }
  
  /// Removes all objects inside a single bucket.
  /// - Parameter id: The unique identifier of the bucket you would like to empty.
  public func emptyBucket(_ id: String) async throws {
    try await baseClient.emptyBucket(id)
  }
  
  /// Deletes an existing bucket.
  /// - Parameter id: The unique identifier of the bucket you would like to delete.
  public func deleteBucket(_ id: String) async throws {
    try await baseClient.deleteBucket(id)
  }
}