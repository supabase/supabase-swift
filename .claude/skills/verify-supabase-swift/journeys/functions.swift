// Journey: Edge Functions — invoke `echo` with JSON, text, and custom headers; call a missing function.
// Proof: the echo function returns what went on the wire, so the saved response is the request.
import Foundation
import Supabase

struct Echo: Decodable, Encodable, Sendable {
  let method: String
  let path: String
  let query: [String: String]
  let headers: [String: String]
  let body: String

  var decodedBody: String { String(decoding: Data(base64Encoded: body) ?? Data(), as: UTF8.self) }
}

let client = Verify.client()

Verify.step("fn-json", "invoke echo with a JSON body")
if let echo: Echo = await Verify.attempt("fn-json", {
  try await client.functions.invoke("echo", body: .json(["hello": "verify"]))
}) {
  Verify.save("fn-json.json", echo)
  Verify.check(
    "fn-json",
    echo.method == "POST" && echo.headers["content-type"] == "application/json"
      && echo.decodedBody.contains("\"hello\":\"verify\""),
    "\(echo.method) \(echo.path) content-type=\(echo.headers["content-type"] ?? "nil") body=\(echo.decodedBody)"
  )
  // A new-format publishable key is not a JWT, so with no session the SDK sends it only as
  // `apikey` and leaves `Authorization` off.
  Verify.check(
    "fn-auth-header", echo.headers["authorization"] == nil,
    "authorization header \(echo.headers["authorization"] ?? "absent")")
}

Verify.step("fn-text", "invoke echo with a text body")
if let echo: Echo = await Verify.attempt("fn-text", {
  try await client.functions.invoke("echo", body: .text("plain words"))
}) {
  Verify.save("fn-text.json", echo)
  Verify.check(
    "fn-text",
    echo.decodedBody == "plain words" && echo.headers["content-type"]?.hasPrefix("text/plain") == true,
    "body=\(echo.decodedBody) content-type=\(echo.headers["content-type"] ?? "nil")")
}

Verify.step("fn-get-query", "invoke echo/sub/path with GET, a query item, and region eu-west-1")
if let echo: Echo = await Verify.attempt("fn-get-query", {
  try await client.functions.invoke(
    "echo/sub/path",
    options: .init(
      method: .get, query: [URLQueryItem(name: "month", value: "2026-09")], region: .euWest1))
}) {
  Verify.save("fn-get-query.json", echo)
  Verify.check(
    "fn-get-query",
    echo.method == "GET" && echo.path == "/echo/sub/path" && echo.query["month"] == "2026-09"
      && echo.headers["x-region"] == "eu-west-1",
    "\(echo.method) \(echo.path) query=\(echo.query) x-region=\(echo.headers["x-region"] ?? "nil")")
}

Verify.step("fn-missing", "invoke a function that does not exist")
do {
  _ = try await client.functions.invoke("does-not-exist")
  Verify.check("fn-missing", false, "expected an error, got a response")
} catch let error as FunctionsError where error.kind == .server {
  Verify.check(
    "fn-missing", error.response?.statusCode == 404,
    "FunctionsError(server) status \(error.response?.statusCode ?? 0)")
} catch {
  Verify.check("fn-missing", false, "expected FunctionsError(server) 404, threw \(String(reflecting: error))")
}

Verify.finish()
