$version: "2"

namespace io.supabase.functions

use aws.protocols#restJson1

@restJson1
@title("Supabase Functions API")
service FunctionsService {
  version: "1.0"
  operations: [InvokeFunction]
  errors: [FunctionsError]
}

@http(method: "POST", uri: "/functions/v1/{functionName}", code: 200)
operation InvokeFunction {
  input: InvokeFunctionInput
  output: InvokeFunctionOutput
  errors: [FunctionsError]
}

structure InvokeFunctionInput {
  @required
  @httpLabel
  functionName: String

  @httpHeader("x-region")
  region: String

  @httpPayload
  body: Blob
}

structure InvokeFunctionOutput {
  @httpPayload
  body: Blob
}

@error("client")
structure FunctionsError {
  message: String
}
