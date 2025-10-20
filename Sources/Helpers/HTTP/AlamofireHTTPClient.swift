import Alamofire
import ConcurrencyExtras
import Foundation
import HTTPTypesFoundation

extension HTTPRequest: URLRequestConvertible {
//    package func asURLRequest() throws -> URLRequest {
//        guard let urlRequest = self.urlRequest else {
//            throw AFError.invalidURL(url: self.url.absoluteString)
//        }
//        return urlRequest
//    }
}

package struct AlamofireHTTPClient: HTTPClientType {
    let session: Session

    package init(session: Session = .default) {
        self.session = session
    }

    package func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        let response = await session.request(request).serializingData().response

        guard let httpResponse = response.response else {
            throw URLError(.badServerResponse)
        }

        return HTTPResponse(data: response.data ?? Data(), response: httpResponse)
    }

    package func stream(
        _ request: HTTPRequest
    ) -> AsyncThrowingStream<Data, any Error> {
        let stream =
            session
            .streamRequest(request)
            .streamTask()
            .streamingData()
            .compactMap {
                switch $0.event {
                case .stream(let result):
                    return result.get()

                case .complete(let completion):
                    if let error = completion.error {
                        throw error
                    }
                    // If the stream is complete, return nil
                    return nil
                }
            }

        return AsyncThrowingStream(UncheckedSendable(stream))
    }
}
