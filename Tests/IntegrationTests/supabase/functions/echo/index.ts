// Echoes the request back so the Swift integration suite can assert what went on the wire.
// The body comes back base64-encoded so binary payloads survive the JSON round trip.

const echoedHeaders = ["content-type", "x-region", "x-custom", "authorization"]

function base64(bytes: Uint8Array): string {
  let binary = ""
  for (const byte of bytes) binary += String.fromCharCode(byte)
  return btoa(binary)
}

Deno.serve(async (req) => {
  const url = new URL(req.url)
  const headers: Record<string, string> = {}
  for (const name of echoedHeaders) {
    const value = req.headers.get(name)
    if (value !== null) headers[name] = value
  }
  // Only the scheme: the suite asserts that a bearer went out, not which one.
  if (headers.authorization) headers.authorization = headers.authorization.split(" ")[0]
  const body = new Uint8Array(await req.arrayBuffer())
  return Response.json({
    method: req.method,
    path: url.pathname,
    query: Object.fromEntries(url.searchParams),
    headers,
    body: base64(body),
  })
})
