// Echo Edge Function
// Echoes back the request details for testing purposes

import "@supabase/functions-js/edge-runtime.d.ts"

console.log("Echo function started")

Deno.serve(async (req) => {
  try {
    // Extract request details
    const url = new URL(req.url)
    const method = req.method
    const headers: Record<string, string> = {}

    // Convert headers to plain object
    req.headers.forEach((value, key) => {
      headers[key] = value
    })

    // Read body if present
    let body: any = null
    let bodyText: string | null = null

    if (method !== "GET" && method !== "HEAD") {
      const contentType = req.headers.get("content-type") || ""
      bodyText = await req.text()

      if (bodyText) {
        if (contentType.includes("application/json")) {
          try {
            body = JSON.parse(bodyText)
          } catch {
            body = bodyText
          }
        } else {
          body = bodyText
        }
      }
    }

    // Build echo response with sorted query params for deterministic testing
    const sortedQuery = Object.fromEntries(
      Array.from(url.searchParams.entries()).sort((a, b) => a[0].localeCompare(b[0]))
    )

    const echoResponse = {
      method,
      url: url.toString(),
      path: url.pathname,
      query: sortedQuery,
      headers,
      body,
      timestamp: new Date().toISOString(),
    }

    return new Response(
      JSON.stringify(echoResponse, null, 2),
      {
        headers: {
          "Content-Type": "application/json",
          "X-Echo-Method": method,
        },
        status: 200,
      }
    )
  } catch (error) {
    console.error("Error in echo function:", error)

    return new Response(
      JSON.stringify({
        error: "Internal server error",
        message: error instanceof Error ? error.message : String(error),
      }),
      {
        headers: { "Content-Type": "application/json" },
        status: 500,
      }
    )
  }
})

/* To invoke locally:

  1. Run `supabase start` (see: https://supabase.com/docs/reference/cli/supabase-start)
  2. Make HTTP requests:

  # POST request with JSON body
  curl -i --location --request POST 'http://127.0.0.1:54321/functions/v1/echo' \
    --header 'Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0' \
    --header 'Content-Type: application/json' \
    --data '{"message":"Hello from test"}'

  # GET request with query params
  curl -i 'http://127.0.0.1:54321/functions/v1/echo?foo=bar&test=123' \
    --header 'Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0'

  # PUT request
  curl -i --location --request PUT 'http://127.0.0.1:54321/functions/v1/echo' \
    --header 'Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0' \
    --header 'Content-Type: application/json' \
    --data '{"update":"data"}'

*/
