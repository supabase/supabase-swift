import Foundation

/// Advanced configuration options for enhanced storage functionality.
public struct AdvancedStorageConfiguration: Sendable {
  /// Enable streaming uploads and downloads for large files.
  public let enableStreaming: Bool
  
  /// Chunk size for streaming operations (in bytes).
  public let streamingChunkSize: Int
  
  /// Background session identifier for persistent uploads.
  public let backgroundIdentifier: String?
  
  /// Enable resumable upload capability.
  public let enableResumableUploads: Bool
  
  /// Maximum number of concurrent uploads.
  public let maxConcurrentUploads: Int
  
  /// Interval for progress update callbacks (in seconds).
  public let progressUpdateInterval: TimeInterval
  
  /// Maximum number of retry attempts for failed operations.
  public let maxRetryAttempts: Int
  
  /// Delay between retry attempts (in seconds).
  public let retryDelay: TimeInterval
  
  /// Enable automatic resume of interrupted uploads.
  public let enableAutomaticResume: Bool
  
  /// URLSession configuration for streaming operations.
  public let streamingSessionConfiguration: URLSessionConfiguration?
  
  /// URLSession configuration for resumable operations.
  public let resumableSessionConfiguration: URLSessionConfiguration?
  
  /// Creates a new advanced storage configuration.
  /// - Parameters:
  ///   - enableStreaming: Enable streaming functionality. Default is `true`.
  ///   - streamingChunkSize: Size of each streaming chunk in bytes. Default is 1MB.
  ///   - backgroundIdentifier: Unique identifier for background session. Default is `nil`.
  ///   - enableResumableUploads: Enable resumable upload functionality. Default is `true`.
  ///   - maxConcurrentUploads: Maximum concurrent upload operations. Default is `3`.
  ///   - progressUpdateInterval: How often to update progress callbacks. Default is `0.1` seconds.
  ///   - maxRetryAttempts: Maximum retry attempts for failed operations. Default is `3`.
  ///   - retryDelay: Delay between retry attempts. Default is `2.0` seconds.
  ///   - enableAutomaticResume: Automatically resume interrupted uploads. Default is `true`.
  ///   - streamingSessionConfiguration: Custom URLSession configuration for streaming. Default is `nil` (uses default).
  ///   - resumableSessionConfiguration: Custom URLSession configuration for resumable uploads. Default is `nil` (uses default).
  public init(
    enableStreaming: Bool = true,
    streamingChunkSize: Int = 1024 * 1024, // 1MB chunks
    backgroundIdentifier: String? = nil,
    enableResumableUploads: Bool = true,
    maxConcurrentUploads: Int = 3,
    progressUpdateInterval: TimeInterval = 0.1,
    maxRetryAttempts: Int = 3,
    retryDelay: TimeInterval = 2.0,
    enableAutomaticResume: Bool = true,
    streamingSessionConfiguration: URLSessionConfiguration? = nil,
    resumableSessionConfiguration: URLSessionConfiguration? = nil
  ) {
    self.enableStreaming = enableStreaming
    self.streamingChunkSize = max(1024, streamingChunkSize) // Minimum 1KB chunks
    self.backgroundIdentifier = backgroundIdentifier
    self.enableResumableUploads = enableResumableUploads
    self.maxConcurrentUploads = max(1, maxConcurrentUploads) // At least 1 concurrent upload
    self.progressUpdateInterval = max(0.01, progressUpdateInterval) // Minimum 10ms
    self.maxRetryAttempts = max(0, maxRetryAttempts)
    self.retryDelay = max(0.1, retryDelay) // Minimum 100ms delay
    self.enableAutomaticResume = enableAutomaticResume
    self.streamingSessionConfiguration = streamingSessionConfiguration
    self.resumableSessionConfiguration = resumableSessionConfiguration
  }
}

// MARK: - Preset Configurations

public extension AdvancedStorageConfiguration {
  /// Configuration optimized for large file uploads (100MB+).
  static let largeFiles = AdvancedStorageConfiguration(
    enableStreaming: true,
    streamingChunkSize: 5 * 1024 * 1024, // 5MB chunks for better throughput
    backgroundIdentifier: "com.supabase.storage.large-files",
    enableResumableUploads: true,
    maxConcurrentUploads: 2, // Reduce concurrent uploads for large files
    progressUpdateInterval: 0.5, // Less frequent updates for performance
    maxRetryAttempts: 5, // More retries for large files
    retryDelay: 3.0, // Longer delay between retries
    enableAutomaticResume: true
  )
  
  /// Configuration optimized for mobile devices with limited bandwidth.
  static let mobile = AdvancedStorageConfiguration(
    enableStreaming: true,
    streamingChunkSize: 256 * 1024, // 256KB chunks for slower connections
    backgroundIdentifier: "com.supabase.storage.mobile",
    enableResumableUploads: true,
    maxConcurrentUploads: 1, // Single upload to conserve bandwidth
    progressUpdateInterval: 0.2,
    maxRetryAttempts: 5, // More retries for unreliable connections
    retryDelay: 5.0, // Longer delays for mobile networks
    enableAutomaticResume: true
  )
  
  /// Configuration for high-throughput server environments.
  static let server = AdvancedStorageConfiguration(
    enableStreaming: true,
    streamingChunkSize: 10 * 1024 * 1024, // 10MB chunks for maximum throughput
    backgroundIdentifier: nil, // No background processing on server
    enableResumableUploads: false, // Server uploads are typically reliable
    maxConcurrentUploads: 10, // High concurrency for server use
    progressUpdateInterval: 1.0, // Less frequent progress updates
    maxRetryAttempts: 2, // Fewer retries, fail fast
    retryDelay: 1.0,
    enableAutomaticResume: false
  )
  
  /// Minimal configuration with only essential features enabled.
  static let minimal = AdvancedStorageConfiguration(
    enableStreaming: false,
    streamingChunkSize: 1024 * 1024,
    backgroundIdentifier: nil,
    enableResumableUploads: false,
    maxConcurrentUploads: 1,
    progressUpdateInterval: 0.5,
    maxRetryAttempts: 1,
    retryDelay: 1.0,
    enableAutomaticResume: false
  )
}

/// Enhanced storage client configuration combining base and advanced settings.
public struct EnhancedStorageClientConfiguration: Sendable {
  /// Base storage client configuration.
  public let base: StorageClientConfiguration
  
  /// Advanced configuration options.
  public let advanced: AdvancedStorageConfiguration
  
  /// Creates a new enhanced storage client configuration.
  /// - Parameters:
  ///   - base: The base storage client configuration.
  ///   - advanced: The advanced configuration options.
  public init(
    base: StorageClientConfiguration,
    advanced: AdvancedStorageConfiguration = AdvancedStorageConfiguration()
  ) {
    self.base = base
    self.advanced = advanced
  }
}

// MARK: - Convenience Initializers

public extension EnhancedStorageClientConfiguration {
  /// Creates an enhanced configuration for large file uploads.
  /// - Parameter base: The base storage client configuration.
  static func largeFiles(base: StorageClientConfiguration) -> EnhancedStorageClientConfiguration {
    EnhancedStorageClientConfiguration(base: base, advanced: .largeFiles)
  }
  
  /// Creates an enhanced configuration optimized for mobile devices.
  /// - Parameter base: The base storage client configuration.
  static func mobile(base: StorageClientConfiguration) -> EnhancedStorageClientConfiguration {
    EnhancedStorageClientConfiguration(base: base, advanced: .mobile)
  }
  
  /// Creates an enhanced configuration for server environments.
  /// - Parameter base: The base storage client configuration.
  static func server(base: StorageClientConfiguration) -> EnhancedStorageClientConfiguration {
    EnhancedStorageClientConfiguration(base: base, advanced: .server)
  }
  
  /// Creates a minimal enhanced configuration.
  /// - Parameter base: The base storage client configuration.
  static func minimal(base: StorageClientConfiguration) -> EnhancedStorageClientConfiguration {
    EnhancedStorageClientConfiguration(base: base, advanced: .minimal)
  }
}