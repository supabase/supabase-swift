//
//  FunctionsTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 13/03/26.
//

import Foundation
import Functions
import InlineSnapshotTesting
import Replay
import Testing

private final class TestBundleToken {}

@Suite(
    .playbackIsolated(
        replaysRootURL: URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .appendingPathComponent("Replays")
    ),
    .serialized
)
struct FunctionsTests {

    let client = FunctionsClient(
        url: URL(string: "http://127.0.0.1:54321/functions/v1")!,
        headers: [
            "apikey": "sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH"
        ],
        session: Replay.session
    )

    // MARK: - Basic Invocation Tests

    @Test(.replay("invoke_default"))
    func invokeDefault() async throws {
        let response = try await client.invoke("echo") as AnyJSON

        // Verify the request was a POST with no body
        let method = response.objectValue?["method"]?.stringValue
        #expect(method == "POST")

        let body = response.objectValue?["body"]
        #expect(body?.isNil == true)
    }

    @Test(.replay("invoke_with_json_body"))
    func invokeWithJSONBody() async throws {
        struct RequestBody: Codable {
            let message: String
            let count: Int
            let active: Bool
        }

        let response =
            try await client.invoke(
                "echo",
                options: FunctionInvokeOptions(
                    body: RequestBody(
                        message: "Hello from Swift",
                        count: 42,
                        active: true
                    )
                )
            ) as AnyJSON

        // Verify body was sent correctly
        let body = response.objectValue?["body"]?.objectValue
        #expect(body?["message"]?.stringValue == "Hello from Swift")
        #expect(body?["count"]?.intValue == 42)
        #expect(body?["active"]?.boolValue == true)

        // Verify content-type header
        let headers = response.objectValue?["headers"]?.objectValue
        #expect(headers?["content-type"]?.stringValue == "application/json")
    }

    @Test(.replay("invoke_with_json_array"))
    func invokeWithJSONArray() async throws {
        let items = ["apple", "banana", "cherry"]

        let response =
            try await client.invoke(
                "echo",
                options: FunctionInvokeOptions(body: items)
            ) as AnyJSON

        // Verify array body
        let body = response.objectValue?["body"]?.arrayValue?.compactMap {
            $0.stringValue
        }
        #expect(body == items)
    }

    @Test(.replay("invoke_with_plain_text"))
    func invokeWithPlainText() async throws {
        let text = "This is plain text content"

        let response =
            try await client.invoke(
                "echo",
                options: FunctionInvokeOptions(body: text)
            ) as AnyJSON

        // Verify text body
        let body = response.objectValue?["body"]?.stringValue
        #expect(body == text)

        // Verify content-type header
        let headers = response.objectValue?["headers"]?.objectValue
        #expect(headers?["content-type"]?.stringValue == "text/plain")
    }

    @Test(.replay("invoke_with_binary_data"))
    func invokeWithBinaryData() async throws {
        let data = Data([0x48, 0x65, 0x6C, 0x6C, 0x6F])  // "Hello" in UTF-8

        let response =
            try await client.invoke(
                "echo",
                options: FunctionInvokeOptions(body: data)
            ) as AnyJSON

        // Verify data was sent (echo will return it as string or data)
        let body = response.objectValue?["body"]
        #expect(body?.isNil == false)

        // Verify content-type header
        let headers = response.objectValue?["headers"]?.objectValue
        #expect(
            headers?["content-type"]?.stringValue == "application/octet-stream"
        )
    }

    // MARK: - HTTP Method Tests

    @Test(.replay("invoke_get_method"))
    func invokeGETMethod() async throws {
        let response =
            try await client.invoke(
                "echo",
                options: FunctionInvokeOptions(method: .get)
            ) as AnyJSON

        let method = response.objectValue?["method"]?.stringValue
        #expect(method == "GET")

        // GET requests should not have a body
        let body = response.objectValue?["body"]
        #expect(body?.isNil == true)
    }

    @Test(.replay("invoke_put_method"))
    func invokePUTMethod() async throws {
        let response =
            try await client.invoke(
                "echo",
                options: FunctionInvokeOptions(
                    method: .put,
                    body: ["update": "data"]
                )
            ) as AnyJSON

        let method = response.objectValue?["method"]?.stringValue
        #expect(method == "PUT")
    }

    @Test(.replay("invoke_patch_method"))
    func invokePATCHMethod() async throws {
        let response =
            try await client.invoke(
                "echo",
                options: FunctionInvokeOptions(
                    method: .patch,
                    body: ["field": "value"]
                )
            ) as AnyJSON

        let method = response.objectValue?["method"]?.stringValue
        #expect(method == "PATCH")
    }

    @Test(.replay("invoke_delete_method"))
    func invokeDELETEMethod() async throws {
        let response =
            try await client.invoke(
                "echo",
                options: FunctionInvokeOptions(
                    method: .delete,
                    body: ["id": "123"]
                )
            ) as AnyJSON

        let method = response.objectValue?["method"]?.stringValue
        #expect(method == "DELETE")
    }

    // MARK: - Query Parameters Tests

    // Note: These tests are disabled for replay due to non-deterministic query parameter
    // ordering from Swift Dictionary. When replaying, the URL query string order may differ
    // from recording, causing mismatches. These tests work correctly in live mode.

    // @Test(.replay("invoke_with_query_params"))
    // func invokeWithQueryParams() async throws {
    //   let response =
    //     try await client.invoke(
    //       "echo",
    //       options: FunctionInvokeOptions(
    //         query: [
    //           "search": "test",
    //           "page": "1",
    //           "limit": "10",
    //         ]
    //       )
    //     ) as AnyJSON
    //
    //   // Verify query parameters
    //   let query = response.objectValue?["query"]?.objectValue
    //   #expect(query?["search"]?.stringValue == "test")
    //   #expect(query?["page"]?.stringValue == "1")
    //   #expect(query?["limit"]?.stringValue == "10")
    // }
    //
    // @Test(.replay("invoke_with_special_chars_in_query"))
    // func invokeWithSpecialCharsInQuery() async throws {
    //   let response =
    //     try await client.invoke(
    //       "echo",
    //       options: FunctionInvokeOptions(
    //         query: [
    //           "email": "user@example.com",
    //           "filter": "name=John&age>25",
    //         ]
    //       )
    //     ) as AnyJSON
    //
    //   // Verify special characters are preserved
    //   let query = response.objectValue?["query"]?.objectValue
    //   #expect(query?["email"]?.stringValue == "user@example.com")
    // }

    // MARK: - Custom Headers Tests

    @Test(.replay("invoke_with_custom_headers"))
    func invokeWithCustomHeaders() async throws {
        let response =
            try await client.invoke(
                "echo",
                options: FunctionInvokeOptions(
                    headers: [
                        "X-Custom-Header": "custom-value",
                        "X-Request-ID": "req-123",
                        "X-Api-Version": "v1",
                    ]
                )
            ) as AnyJSON

        // Verify custom headers
        let headers = response.objectValue?["headers"]?.objectValue
        #expect(headers?["x-custom-header"]?.stringValue == "custom-value")
        #expect(headers?["x-request-id"]?.stringValue == "req-123")
        #expect(headers?["x-api-version"]?.stringValue == "v1")
    }

    @Test(.replay("invoke_with_content_type_override"))
    func invokeWithContentTypeOverride() async throws {
        let response =
            try await client.invoke(
                "echo",
                options: FunctionInvokeOptions(
                    headers: ["Content-Type": "application/xml"],
                    body: "<xml>data</xml>"
                )
            ) as AnyJSON

        // Verify content-type was overridden
        let headers = response.objectValue?["headers"]?.objectValue
        #expect(headers?["content-type"]?.stringValue == "application/xml")
    }

    // MARK: - Complex Scenarios

    @Test(.replay("invoke_with_all_options"))
    func invokeWithAllOptions() async throws {
        struct ComplexBody: Codable {
            let user: String
            let data: [String: Int]
        }

        let response =
            try await client.invoke(
                "echo",
                options: FunctionInvokeOptions(
                    method: .post,
                    query: ["debug": "true"],
                    headers: ["X-Test": "comprehensive"],
                    body: ComplexBody(
                        user: "test-user",
                        data: ["score": 100, "level": 5]
                    )
                )
            ) as AnyJSON

        // Verify all options were applied
        #expect(response.objectValue?["method"]?.stringValue == "POST")

        let query = response.objectValue?["query"]?.objectValue
        #expect(query?["debug"]?.stringValue == "true")

        let headers = response.objectValue?["headers"]?.objectValue
        #expect(headers?["x-test"]?.stringValue == "comprehensive")

        let body = response.objectValue?["body"]?.objectValue
        #expect(body?["user"]?.stringValue == "test-user")
    }

    @Test(.replay("invoke_with_nested_json"))
    func invokeWithNestedJSON() async throws {
        struct NestedData: Codable {
            let level1: Level1

            struct Level1: Codable {
                let level2: Level2
                let items: [String]

                struct Level2: Codable {
                    let name: String
                    let value: Int
                }
            }
        }

        let data = NestedData(
            level1: NestedData.Level1(
                level2: NestedData.Level1.Level2(name: "deep", value: 999),
                items: ["a", "b", "c"]
            )
        )

        let response =
            try await client.invoke(
                "echo",
                options: FunctionInvokeOptions(body: data)
            ) as AnyJSON

        // Verify nested structure
        let body = response.objectValue?["body"]?.objectValue
        let level1 = body?["level1"]?.objectValue
        let level2 = level1?["level2"]?.objectValue
        #expect(level2?["name"]?.stringValue == "deep")
        #expect(level2?["value"]?.intValue == 999)

        let items = level1?["items"]?.arrayValue?.compactMap { $0.stringValue }
        #expect(items == ["a", "b", "c"])
    }

    // MARK: - Decode Tests

    @Test(.replay("invoke_with_decode"))
    func invokeWithDecode() async throws {
        struct EchoResponse: Codable {
            let method: String
            let path: String
            let query: [String: String]
        }

        let response: EchoResponse = try await client.invoke(
            "echo",
            options: FunctionInvokeOptions(
                method: .get,
                query: ["test": "value"]
            )
        )

        #expect(response.method == "GET")
        #expect(response.path == "/echo")
        #expect(response.query["test"] == "value")
    }

    @Test(.replay("invoke_with_custom_decoder"))
    func invokeWithCustomDecoder() async throws {
        struct EchoResponse: Codable {
            let method: String
            let timestamp: Date
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let response: EchoResponse = try await client.invoke(
            "echo",
            options: FunctionInvokeOptions(method: .get),
            decoder: decoder
        )

        #expect(response.method == "GET")
        #expect(response.timestamp.timeIntervalSince1970 > 0)
    }

    // MARK: - Authentication Tests

    @Test(.replay("invoke_with_auth_token"))
    func invokeWithAuthToken() async throws {
        // Use the valid anon token from supabase
        let validToken =
            "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0"
        await client.setAuth(token: validToken)

        let response = try await client.invoke("echo") as AnyJSON

        // Verify auth token is in headers
        let headers = response.objectValue?["headers"]?.objectValue
        #expect(
            headers?["authorization"]?.stringValue == "Bearer \(validToken)"
        )
    }

    // MARK: - Empty/Nil Body Tests

    @Test(.replay("invoke_with_nil_body"))
    func invokeWithNilBody() async throws {
        let response =
            try await client.invoke(
                "echo",
                options: FunctionInvokeOptions(method: .post)
            ) as AnyJSON

        let body = response.objectValue?["body"]
        #expect(body?.isNil == true)
    }

    // MARK: - Response Metadata Tests

    @Test(.replay("invoke_verify_metadata"))
    func invokeVerifyMetadata() async throws {
        let response = try await client.invoke("echo") as AnyJSON

        // Verify all expected fields are present
        let obj = response.objectValue
        #expect(obj?["method"] != nil)
        #expect(obj?["url"] != nil)
        #expect(obj?["path"] != nil)
        #expect(obj?["query"] != nil)
        #expect(obj?["headers"] != nil)
        #expect(obj?["timestamp"] != nil)
    }

    @Test(.replay("invoke_verify_url_structure"))
    func invokeVerifyURLStructure() async throws {
        let response =
            try await client.invoke(
                "echo",
                options: FunctionInvokeOptions(
                    query: ["param1": "value1"]
                )
            ) as AnyJSON

        let url = response.objectValue?["url"]?.stringValue
        #expect(url != nil)
        #expect(url?.contains("echo") == true)

        let path = response.objectValue?["path"]?.stringValue
        #expect(path == "/echo")
    }
}
