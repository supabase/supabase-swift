import Foundation

// Enhanced storage error types for advanced functionality
public extension StorageError {
  static let streamingNotEnabled = StorageError(
    message: "Streaming functionality is not enabled. Please configure your client with streaming support.",
    error: "StreamingNotEnabled"
  )
  
  static let backgroundUploadsNotEnabled = StorageError(
    message: "Background uploads are not enabled. Please configure your client with a background identifier.",
    error: "BackgroundUploadsNotEnabled"
  )
  
  static let resumableUploadsNotEnabled = StorageError(
    message: "Resumable uploads are not enabled. Please configure your client with resumable upload support.",
    error: "ResumableUploadsNotEnabled"
  )
  
  static let resumeDataUnavailable = StorageError(
    message: "Resume data is not available for this upload task.",
    error: "ResumeDataUnavailable"
  )
  
  static let invalidFileURL = StorageError(
    message: "The provided file URL is invalid or the file does not exist.",
    error: "InvalidFileURL"
  )
  
  static let backgroundTaskNotFound = StorageError(
    message: "The background task with the specified identifier was not found.",
    error: "BackgroundTaskNotFound"
  )
  
  static let uploadAlreadyInProgress = StorageError(
    message: "An upload is already in progress for this file path.",
    error: "UploadAlreadyInProgress"
  )
}