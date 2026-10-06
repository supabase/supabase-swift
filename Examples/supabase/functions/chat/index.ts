// Streams a canned reply word by word as server-sent events, ending with `[DONE]`.
// Stands in for an AI proxy so the Examples app needs no API key.

Deno.serve(async (req) => {
  const { prompt } = await req.json()
  const words = `You said: "${prompt}". This reply arrives one word at a time over a streamed response.`
    .split(" ")
  const encoder = new TextEncoder()
  const body = new ReadableStream({
    async start(controller) {
      for (const word of words) {
        controller.enqueue(encoder.encode(`data: ${JSON.stringify({ delta: word + " " })}\n\n`))
        await new Promise((resolve) => setTimeout(resolve, 80))
      }
      controller.enqueue(encoder.encode("data: [DONE]\n\n"))
      controller.close()
    },
  })
  return new Response(body, { headers: { "Content-Type": "text/event-stream" } })
})
