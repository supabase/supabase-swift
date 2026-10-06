// Emits `count` server-sent events (default 3), `delay` milliseconds apart (default 100).
// The Swift integration suite reads them as raw chunks and cancels mid-stream.

Deno.serve((req) => {
  const url = new URL(req.url)
  const count = Number(url.searchParams.get("count") ?? "3")
  const delay = Number(url.searchParams.get("delay") ?? "100")
  const encoder = new TextEncoder()
  const body = new ReadableStream({
    async start(controller) {
      for (let i = 1; i <= count; i++) {
        controller.enqueue(encoder.encode(`id: ${i}\nevent: tick\ndata: {"n":${i}}\n\n`))
        await new Promise((resolve) => setTimeout(resolve, delay))
      }
      controller.close()
    },
  })
  return new Response(body, { headers: { "Content-Type": "text/event-stream" } })
})
