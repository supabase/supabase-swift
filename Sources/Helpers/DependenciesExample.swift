import Dependencies
import Foundation

// MARK: - Example Dependencies

/// A simple date provider dependency for demonstration
package struct DateProviderDependency: DependencyKey {
  package static let liveValue: any DateProvider = LiveDateProvider()
  package static let testValue: any DateProvider = TestDateProvider()
}

extension DependencyValues {
  package var dateProvider: any DateProvider {
    get { self[DateProviderDependency.self] }
    set { self[DateProviderDependency.self] = newValue }
  }
}

// MARK: - DateProvider Protocol

package protocol DateProvider: Sendable {
  func now() -> Date
}

// MARK: - Live Implementation

package struct LiveDateProvider: DateProvider {
  package func now() -> Date {
    Date()
  }
}

// MARK: - Test Implementation

package struct TestDateProvider: DateProvider {
  package private(set) var currentTime: Date
  
  package init(initialTime: Date = Date(timeIntervalSince1970: 0)) {
    self.currentTime = initialTime
  }
  
  package func now() -> Date {
    currentTime
  }
  
  package mutating func advance(by duration: TimeInterval) {
    currentTime = currentTime.addingTimeInterval(duration)
  }
}

// MARK: - Example Usage

package struct ExampleService {
  @Dependency(\.dateProvider) private var dateProvider
  
  package func performOperation() -> Date {
    let currentTime = dateProvider.now()
    
    // In tests, this will be controllable
    // In live code, this will use real time
    return currentTime
  }
}
