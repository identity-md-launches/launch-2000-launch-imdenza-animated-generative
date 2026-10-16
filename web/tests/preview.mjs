import { createServer } from 'node:http'
import { readFile } from 'node:fs/promises'
import { fileURLToPath } from 'node:url'
import { dirname, resolve, extname, sep } from 'node:path'

// A bounded test-owned server: the export is intentionally mounted under a subpath.
export async function preview() {
  const root = resolve(dirname(fileURLToPath(import.meta.url)), '../../dist')
  const types = {
    '.html': 'text/html',
    '.js': 'text/javascript',
    '.css': 'text/css',
    '.json': 'application/json',
    '.svg': 'image/svg+xml',
    '.png': 'image/png',
    '.woff2': 'font/woff2',
    '.woff': 'font/woff',
  }
  const server = createServer(async (req, res) => {
    const url = new URL(req.url, 'http://localhost')
    if (!url.pathname.startsWith('/preview/')) {
      res.writeHead(404).end()
      return
    }
    const path = resolve(
      root,
      decodeURIComponent(url.pathname.slice('/preview/'.length)) ||
        'index.html',
    )
    if (path !== root && !path.startsWith(root + sep)) {
      res.writeHead(403).end()
      return
    }
    try {
      const data = await readFile(path)
      res.writeHead(200, {
        'Content-Type': types[extname(path)] ?? 'application/octet-stream',
      })
      res.end(data)
    } catch {
      res.writeHead(404).end()
    }
  })
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve))
  return {
    url: `http://127.0.0.1:${server.address().port}/preview/`,
    close: () => new Promise((resolve) => server.close(resolve)),
  }
}
