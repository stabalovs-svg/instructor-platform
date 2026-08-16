import { createReadStream, existsSync, statSync } from 'node:fs'
import { createServer } from 'node:http'
import { extname, join, normalize } from 'node:path'

const root = join(import.meta.dirname, '..', 'dist')
const port = Number(process.env.IKARS_PREVIEW_PORT || 4174)
const types = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.css': 'text/css; charset=utf-8', '.svg': 'image/svg+xml' }

createServer((request, response) => {
  const requestPath = decodeURIComponent(new URL(request.url, `http://${request.headers.host}`).pathname)
  const relative = normalize(requestPath).replace(/^(\.\.(\/|\\|$))+/, '').replace(/^[/\\]+/, '')
  let file = join(root, relative || 'index.html')
  if (!existsSync(file) || statSync(file).isDirectory()) file = join(root, 'index.html')
  response.setHeader('Content-Type', types[extname(file)] || 'application/octet-stream')
  createReadStream(file).pipe(response)
}).listen(port, '127.0.0.1', () => console.log(`IKARS preview: http://127.0.0.1:${port}`))
