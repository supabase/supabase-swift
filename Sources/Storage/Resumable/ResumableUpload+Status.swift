import Foundation

extension ResumableUpload {
  public enum Status: Sendable, Equatable {
    case queued(UUID)
    case started(UUID)
    case progress(UUID, uploaded: Int, total: Int)
    case finished(UUID)
    case cancelled(UUID)
    case failed(UUID, any Error)
    case fileError(any Error)
    case clientError(any Error)

    // TODO: more robust equatable implementation
    public static func == (lhs: Status, rhs: Status) -> Bool {
      switch (lhs, rhs) {
      case (.queued(let lhsId), .queued(let rhsId)):
        return lhsId == rhsId
      case (.started(let lhsId), .started(let rhsId)):
        return lhsId == rhsId
      case (.progress(let lhsId, _, _), .progress(let rhsId, _, _)):
        return lhsId == rhsId
      case (.finished(let lhsId), .finished(let rhsId)):
        return lhsId == rhsId
      case (.cancelled(let lhsId), .cancelled(let rhsId)):
        return lhsId == rhsId
      case (.fileError(let lhsError), .fileError(let rhsError)):
        return lhsError.localizedDescription == rhsError.localizedDescription
      case (.clientError(let lhsError), .clientError(let rhsError)):
        return lhsError.localizedDescription == rhsError.localizedDescription
      default:
        return false
      }
    }
  }
}
