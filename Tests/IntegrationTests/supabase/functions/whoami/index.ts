// Returns the `role` and `sub` claims of the bearer token that reached the function, so the Swift
// integration suite can prove which token a client sent. The gateway checks the signature
// (`verify_jwt` is on), so this only decodes the payload.

function claims(req: Request): Record<string, unknown> {
  const token = req.headers.get("authorization")?.replace(/^Bearer /, "") ?? ""
  const payload = token.split(".")[1]
  if (!payload) return {}
  try {
    const base64 = payload.replace(/-/g, "+").replace(/_/g, "/")
    return JSON.parse(atob(base64 + "=".repeat((4 - (base64.length % 4)) % 4)))
  } catch {
    return {}
  }
}

Deno.serve((req) => {
  const { role, sub } = claims(req)
  return Response.json({ role: role ?? null, sub: sub ?? null })
})
