import Network
import Observation

/// Tells if the device has a network connection.
@MainActor
@Observable
final class NetworkMonitor {
  private(set) var isConnected = true

  /// Runs until the task is cancelled. Call it from a `.task` modifier.
  func observe() async {
    for await path in NWPathMonitor() {
      isConnected = path.status == .satisfied
    }
  }
}
