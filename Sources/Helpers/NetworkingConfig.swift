import Alamofire
import Foundation

package struct SupabaseNetworkingConfig: Sendable {
  package let session: Alamofire.Session
  package let logger: (any SupabaseLogger)?
  
  package init(
    session: Alamofire.Session = .default,
    logger: (any SupabaseLogger)? = nil
  ) {
    self.session = session
    self.logger = logger
  }
}

package struct SupabaseCredential: AuthenticationCredential, Sendable {
  package let accessToken: String
  
  package init(accessToken: String) {
    self.accessToken = accessToken
  }
  
  package var requiresRefresh: Bool { false }
}

package final class SupabaseAuthenticator: Authenticator, @unchecked Sendable {
  package typealias Credential = SupabaseCredential
  
  private let getAccessToken: @Sendable () async throws -> String?
  
  package init(getAccessToken: @escaping @Sendable () async throws -> String?) {
    self.getAccessToken = getAccessToken
  }
  
  package func apply(_ credential: SupabaseCredential, to urlRequest: inout URLRequest) {
    urlRequest.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
  }
  
  package func refresh(
    _ credential: SupabaseCredential,
    for session: Alamofire.Session,
    completion: @escaping @Sendable (Result<SupabaseCredential, any Error>) -> Void
  ) {
    Task { @Sendable in
      do {
        let token = try await getAccessToken()
        if let token = token {
          completion(.success(SupabaseCredential(accessToken: token)))
        } else {
          completion(.success(credential))
        }
      } catch {
        completion(.failure(error))
      }
    }
  }
  
  package func didRequest(
    _ urlRequest: URLRequest,
    with response: HTTPURLResponse,
    failDueToAuthenticationError error: any Error
  ) -> Bool {
    response.statusCode == 401
  }
  
  package func isRequest(_ urlRequest: URLRequest, authenticatedWith credential: SupabaseCredential) -> Bool {
    urlRequest.value(forHTTPHeaderField: "Authorization") == "Bearer \(credential.accessToken)"
  }
}
