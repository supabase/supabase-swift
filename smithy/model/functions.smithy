$version: "2"

namespace io.supabase.functions

use aws.protocols#restJson1

@restJson1
@title("Supabase Functions API")
service FunctionsService {
  version: "1.0"
  operations: [
    InvokeFunctionGet
    InvokeFunctionPost
    InvokeFunctionPut
    InvokeFunctionPatch
    InvokeFunctionDelete
  ]
  errors: [FunctionsError]
}

// ─── Shared Shapes ─────────────────────────────────────────────────────────

/// Input for methods that carry a request body (POST, PUT, PATCH, DELETE).
structure InvokeFunctionInput {
  @required
  @httpLabel
  functionName: String

  @httpHeader("x-region")
  region: String

  @httpPayload
  body: Blob
}

/// Input for GET — no body, which GET does not support.
structure InvokeFunctionGetInput {
  @required
  @httpLabel
  functionName: String

  @httpHeader("x-region")
  region: String
}

structure InvokeFunctionOutput {
  @httpPayload
  body: Blob
}

// ─── Operations (one per HTTP method) ──────────────────────────────────────
//
// Smithy requires a fixed HTTP method per operation. We model all five
// methods Supabase Edge Functions accept; FunctionsClient.invoke() dispatches
// to the appropriate generated method based on FunctionInvokeOptions.method.

@http(method: "GET", uri: "/functions/v1/{functionName}", code: 200)
@readonly
operation InvokeFunctionGet {
  input: InvokeFunctionGetInput
  output: InvokeFunctionOutput
  errors: [FunctionsError]
}

@http(method: "POST", uri: "/functions/v1/{functionName}", code: 200)
operation InvokeFunctionPost {
  input: InvokeFunctionInput
  output: InvokeFunctionOutput
  errors: [FunctionsError]
}

@http(method: "PUT", uri: "/functions/v1/{functionName}", code: 200)
@idempotent
operation InvokeFunctionPut {
  input: InvokeFunctionInput
  output: InvokeFunctionOutput
  errors: [FunctionsError]
}

@http(method: "PATCH", uri: "/functions/v1/{functionName}", code: 200)
operation InvokeFunctionPatch {
  input: InvokeFunctionInput
  output: InvokeFunctionOutput
  errors: [FunctionsError]
}

@http(method: "DELETE", uri: "/functions/v1/{functionName}", code: 200)
@idempotent
@suppress(["HttpMethodSemantics.UnexpectedPayload"])
operation InvokeFunctionDelete {
  input: InvokeFunctionInput
  output: InvokeFunctionOutput
  errors: [FunctionsError]
}

@error("client")
structure FunctionsError {
  message: String
}
