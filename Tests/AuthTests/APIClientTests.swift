import ConcurrencyExtras
import Mocker
import TestHelpers
import XCTest

@testable import Auth

final class APIClientTests: XCTestCase {
  fileprivate var apiClient: APIClient!
  fileprivate var storage: InMemoryLocalStorage!
  fileprivate var sut: AuthClient!

  #if !os(Windows) && !os(Linux) && !os(Android)
    override func invokeTest() {
      withMainSerialExecutor {
        super.invokeTest()
      }
    }
  #endif

  override func setUp() {
    super.setUp()
    storage = InMemoryLocalStorage()
    sut = makeSUT()
    apiClient = APIClient(clientID: sut.clientID)
  }

  override func tearDown() {
    super.tearDown()
    Mocker.removeAll()
    sut = nil
    storage = nil
    apiClient = nil
  }

  // MARK: - Core APIClient Tests

  func testAPIClientInitialization() {
    // Given: A client ID
    let clientID = sut.clientID

    // When: Creating an API client
    let client = APIClient(clientID: clientID)

    // Then: Should be initialized
    XCTAssertNotNil(client)
  }

  func testAPIClientExecuteSuccess() async throws {
    // Given: A mock successful response
    let responseData = createValidSessionJSON()

    Mock(
      url: URL(string: "http://localhost:54321/auth/v1/token")!,
      ignoreQuery: true,
      statusCode: 200,
      data: [.post: responseData]
    ).register()

    // When: Executing a request
    let request = try apiClient.execute(
      URL(string: "http://localhost:54321/auth/v1/token")!,
      method: .post,
      headers: [:],
      query: nil,
      body: ["grant_type": "refresh_token"],
      encoder: nil
    )

    // Then: Should not throw an error and return a valid response
    do {
      let result: Session = try await request.serializingDecodable(Session.self).value
      XCTAssertNotNil(result)
      XCTAssertNotNil(result.accessToken)
      XCTAssertNotNil(result.refreshToken)
    } catch {
      XCTFail("Expected successful response, got error: \(error)")
    }
  }

  func testAPIClientExecuteFailure() async throws {
    // Given: A mock error response
    let errorResponse = """
      {
        "error": "invalid_grant",
        "error_description": "Invalid refresh token"
      }
      """.data(using: .utf8)!

    Mock(
      url: URL(string: "http://localhost:54321/auth/v1/token")!,
      ignoreQuery: true,
      statusCode: 400,
      data: [.post: errorResponse]
    ).register()

    // When: Executing a request
    let request = try apiClient.execute(
      URL(string: "http://localhost:54321/auth/v1/token")!,
      method: .post,
      headers: [:],
      query: nil,
      body: ["grant_type": "refresh_token"],
      encoder: nil
    )

    // Then: Should throw error
    do {
      let _: Session = try await request.serializingDecodable(Session.self).value
      XCTFail("Expected error to be thrown")
    } catch {
      let errorMessage = String(describing: error)
      XCTAssertTrue(
        errorMessage.contains("Invalid refresh token")
          || errorMessage.contains("invalid_grant"))
    }
  }

  func testAPIClientExecuteWithHeaders() async throws {
    // Given: A mock response
    let responseData = createValidSessionJSON()

    Mock(
      url: URL(string: "http://localhost:54321/auth/v1/token")!,
      ignoreQuery: true,
      statusCode: 200,
      data: [.post: responseData]
    ).register()

    // When: Executing a request with default headers
    let request = try apiClient.execute(
      URL(string: "http://localhost:54321/auth/v1/token")!,
      method: .post,
      headers: [:],
      query: nil,
      body: ["grant_type": "refresh_token"],
      encoder: nil
    )

    // Then: Should not throw an error
    do {
      let result: Session = try await request.serializingDecodable(Session.self).value
      XCTAssertNotNil(result)
    } catch {
      XCTFail("Expected successful response, got error: \(error)")
    }
  }

  func testAPIClientExecuteWithQueryParameters() async throws {
    // Given: A mock response
    let responseData = createValidSessionJSON()

    Mock(
      url: URL(string: "http://localhost:54321/auth/v1/token")!,
      ignoreQuery: true,
      statusCode: 200,
      data: [.post: responseData]
    ).register()

    // When: Executing a request with query parameters
    let query = ["client_id": "test_client", "response_type": "code"]
    let request = try apiClient.execute(
      URL(string: "http://localhost:54321/auth/v1/token")!,
      method: .post,
      headers: [:],
      query: query,
      body: ["grant_type": "refresh_token"],
      encoder: nil
    )

    // Then: Should not throw an error
    do {
      let result: Session = try await request.serializingDecodable(Session.self).value
      XCTAssertNotNil(result)
    } catch {
      XCTFail("Expected successful response, got error: \(error)")
    }
  }

  func testAPIClientExecuteWithDifferentMethods() async throws {
    // Given: Mock response for POST method
    let postResponse = createValidSessionJSON()

    Mock(
      url: URL(string: "http://localhost:54321/auth/v1/token")!,
      ignoreQuery: true,
      statusCode: 200,
      data: [.post: postResponse]
    ).register()

    // When: Executing POST request
    let postRequest = try apiClient.execute(
      URL(string: "http://localhost:54321/auth/v1/token")!,
      method: .post,
      headers: [:],
      query: nil,
      body: ["grant_type": "refresh_token"],
      encoder: nil
    )

    // Then: Should not throw an error
    do {
      let postResult: Session = try await postRequest.serializingDecodable(Session.self).value
      XCTAssertNotNil(postResult)
    } catch {
      XCTFail("Expected successful response, got error: \(error)")
    }
  }

  func testAPIClientExecuteWithNetworkError() async throws {
    // Given: No mock registered (will cause network error)

    // When: Executing a request
    let request = try apiClient.execute(
      URL(string: "http://localhost:54321/auth/v1/token")!,
      method: .post,
      headers: [:],
      query: nil,
      body: ["grant_type": "refresh_token"],
      encoder: nil
    )

    // Then: Should throw network error
    do {
      let _: Session = try await request.serializingDecodable(Session.self).value
      XCTFail("Expected error to be thrown")
    } catch {
      // Network error is expected
      XCTAssertNotNil(error)
    }
  }

  func testAPIClientExecuteWithTimeout() async throws {
    // Given: A mock response with delay
    let responseData = createValidSessionJSON()

    var mock = Mock(
      url: URL(string: "http://localhost:54321/auth/v1/token")!,
      ignoreQuery: true,
      statusCode: 200,
      data: [.post: responseData]
    )
    mock.delay = DispatchTimeInterval.milliseconds(100)
    mock.register()

    // When: Executing a request
    let request = try apiClient.execute(
      URL(string: "http://localhost:54321/auth/v1/token")!,
      method: .post,
      headers: [:],
      query: nil,
      body: ["grant_type": "refresh_token"],
      encoder: nil
    )

    // Then: Should not throw an error after delay
    do {
      let result: Session = try await request.serializingDecodable(Session.self).value
      XCTAssertNotNil(result)
    } catch {
      XCTFail("Expected successful response, got error: \(error)")
    }
  }

  func testAPIClientExecuteWithLargeResponse() async throws {
    // Given: A mock response with large data
    let largeResponse = String(repeating: "a", count: 10000)
    let responseData = """
      {
        "data": "\(largeResponse)",
        "access_token": "test_access_token"
      }
      """.data(using: .utf8)!

    Mock(
      url: URL(string: "http://localhost:54321/auth/v1/token")!,
      ignoreQuery: true,
      statusCode: 200,
      data: [.post: responseData]
    ).register()

    // When: Executing a request
    let request = try apiClient.execute(
      URL(string: "http://localhost:54321/auth/v1/token")!,
      method: .post,
      headers: [:],
      query: nil,
      body: ["grant_type": "refresh_token"],
      encoder: nil
    )

    struct LargeResponse: Codable {
      let data: String
      let accessToken: String

      enum CodingKeys: String, CodingKey {
        case data
        case accessToken = "access_token"
      }
    }

    let result: LargeResponse = try await request.serializingDecodable(LargeResponse.self).value

    // Then: Should handle large response
    XCTAssertEqual(result.data.count, 10000)
    XCTAssertEqual(result.accessToken, "test_access_token")
  }

  // MARK: - Integration Tests

  func testAPIClientIntegrationWithAuthClient() async throws {
    // Given: A mock response for sign in
    let responseData = createValidSessionJSON()

    Mock(
      url: URL(string: "http://localhost:54321/auth/v1/token")!,
      ignoreQuery: true,
      statusCode: 200,
      data: [.post: responseData]
    ).register()

    // When: Using auth client to sign in
    let result = try await sut.signIn(
      email: "test@example.com",
      password: "password123"
    )

    // Then: Should return session
    assertValidSession(result)
  }

  // MARK: - Helper Methods

  private func createValidSessionJSON() -> Data {
    // Use the existing session.json file which has the correct format
    return json(named: "session")
  }

  private func createValidSessionResponse() -> Session {
    // Use the existing mock session which is guaranteed to work
    return Session.validSession
  }

  private func assertValidSession(_ session: Session) {
    XCTAssertEqual(
      session.accessToken,
      "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJhdWQiOiJhdXRoZW50aWNhdGVkIiwiZXhwIjoxNjQ4NjQwMDIxLCJzdWIiOiJmMzNkM2VjOS1hMmVlLTQ3YzQtODBlMS01YmQ5MTlmM2Q4YjgiLCJlbWFpbCI6Imd1aWxoZXJtZTJAZ3Jkcy5kZXYiLCJwaG9uZSI6IiIsImFwcF9tZXRhZGF0YSI6eyJwcm92aWRlciI6ImVtYWlsIiwicHJvdmlkZXJzIjpbImVtYWlsIl19LCJ1c2VyX21ldGFkYXRhIjp7fSwicm9sZSI6ImF1dGhlbnRpY2F0ZWQifQ.4lMvmz2pJkWu1hMsBgXP98Fwz4rbvFYl4VA9joRv6kY"
    )
    XCTAssertEqual(session.refreshToken, "GGduTeu95GraIXQ56jppkw")
    XCTAssertEqual(session.expiresIn, 3600)
    XCTAssertEqual(session.tokenType, "bearer")
    XCTAssertEqual(session.user.email, "guilherme@binaryscraping.co")
  }

  private func makeSUT(flowType: AuthFlowType = .pkce) -> AuthClient {
    let sessionConfiguration = URLSessionConfiguration.default
    sessionConfiguration.protocolClasses = [MockingURLProtocol.self]

    let encoder = AuthClient.Configuration.jsonEncoder
    encoder.outputFormatting = [.sortedKeys]

    let configuration = AuthClient.Configuration(
      url: clientURL,
      headers: [
        "apikey":
          "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0"
      ],
      flowType: flowType,
      localStorage: storage,
      logger: nil,
      encoder: encoder,
      session: .init(configuration: sessionConfiguration)
    )

    let sut = AuthClient(configuration: configuration)

    Dependencies[sut.clientID].pkce.generateCodeVerifier = {
      "nt_xCJhJXUsIlTmbE_b0r3VHDKLxFTAwXYSj1xF3ZPaulO2gejNornLLiW_C3Ru4w-5lqIh1XE2LTOsSKrj7iA"
    }

    Dependencies[sut.clientID].pkce.generateCodeChallenge = { _ in
      "hgJeigklONUI1pKSS98MIAbtJGaNu0zJU1iSiFOn2lY"
    }

    return sut
  }
}
