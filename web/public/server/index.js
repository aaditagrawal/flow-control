const worker = {
  async fetch(request, env) {
    const response = await env.ASSETS.fetch(request)
    const acceptsHtml = request.headers.get('accept')?.includes('text/html') ?? false
    const resolved = response.status === 404 && acceptsHtml
      ? await env.ASSETS.fetch(new Request(new URL('/index.html', request.url), request))
      : response
    const headers = new Headers(resolved.headers)
    headers.set('Permissions-Policy', 'hid=(self)')
    headers.set('X-Content-Type-Options', 'nosniff')
    return new Response(resolved.body, {
      status: resolved.status,
      statusText: resolved.statusText,
      headers,
    })
  },
}

export default worker
