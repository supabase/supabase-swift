import Dependencies
import Foundation
import Testing
@testable import Helpers

@Test("Example service with controllable dependencies")
func testExampleService() async throws {
  var testDateProvider = TestDateProvider(initialTime: Date(timeIntervalSince1970: 1000))
  
  let service = withDependencies {
    $0.dateProvider = testDateProvider
  } operation: {
    ExampleService()
  }
  
  let result = service.performOperation()
  
  // Verify that the service returns the expected time
  #expect(result == Date(timeIntervalSince1970: 1000))
}

@Test("Test date provider can be advanced manually")
func testDateProviderAdvancement() async throws {
  var testDateProvider = TestDateProvider(initialTime: Date(timeIntervalSince1970: 0))
  
  #expect(testDateProvider.now() == Date(timeIntervalSince1970: 0))
  
  testDateProvider.advance(by: 5.0)
  
  #expect(testDateProvider.now() == Date(timeIntervalSince1970: 5.0))
}

@Test("Live date provider uses real time")
func testLiveDateProvider() async throws {
  let liveDateProvider = LiveDateProvider()
  let startTime = Date()
  
  let providerTime = liveDateProvider.now()
  
  // Allow for small time differences
  let timeDifference = abs(providerTime.timeIntervalSince(startTime))
  #expect(timeDifference < 1.0)
}
