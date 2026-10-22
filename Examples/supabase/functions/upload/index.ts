// Reads a streamed upload and reports its size, so the Examples app can send a file body.

Deno.serve(async (req) => {
  let bytes = 0
  for await (const chunk of req.body ?? new ReadableStream()) bytes += chunk.byteLength
  return Response.json({ bytes, contentType: req.headers.get("content-type") })
})
