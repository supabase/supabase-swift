import Alamofire
import Foundation

extension Alamofire.Session {
    /// Returns a new session with the authentication adapter added.
    /// - Parameter getAccessToken: A closure that returns the access token.
    /// - Returns: A new session with the authentication adapter added.
    func authenticated(
        getAccessToken: @escaping @Sendable () async throws -> String?
    ) -> Alamofire.Session {
        let interceptor =
            self.interceptor != nil
            ? Interceptor(
                adapters: [AuthenticationAdapter(getAccessToken: getAccessToken)],
                interceptors: [self.interceptor!])
            : Interceptor(adapters: [AuthenticationAdapter(getAccessToken: getAccessToken)])
        return Alamofire.Session(
            configuration: self.sessionConfiguration,
            delegate: self.delegate,
            rootQueue: self.rootQueue,
            startRequestsImmediately: self.startRequestsImmediately,
            requestQueue: self.requestQueue,
            serializationQueue: self.serializationQueue,
            interceptor: interceptor,
            serverTrustManager: self.serverTrustManager,
            redirectHandler: self.redirectHandler,
            cachedResponseHandler: self.cachedResponseHandler,
            eventMonitors: [self.eventMonitor]
        )
    }
}

private struct AuthenticationAdapter: RequestAdapter {

    let getAccessToken: @Sendable () async throws -> String?

    func adapt(
        _ urlRequest: URLRequest,
        for session: Alamofire.Session,
        completion: @escaping @Sendable (Result<URLRequest, any Error>) -> Void
    ) {
        Task {
            let token = try? await getAccessToken()

            var request = urlRequest
            if let token {
                request.headers.add(.authorization(bearerToken: token))
            }

            completion(.success(request))
        }
    }
}
