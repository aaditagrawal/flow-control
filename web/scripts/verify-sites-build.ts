import { access, readFile } from 'node:fs/promises'
import { resolve } from 'node:path'

const root = resolve(import.meta.dir, '..')
const hostingPath = resolve(root, '.openai/hosting.json')
const workerPath = resolve(root, 'dist/server/index.js')
const indexPath = resolve(root, 'dist/index.html')

await Promise.all([access(indexPath), access(workerPath), access(hostingPath)])

const hosting = JSON.parse(await readFile(hostingPath, 'utf8')) as {
  project_id?: unknown
  d1?: unknown
  r2?: unknown
}

if (typeof hosting.project_id !== 'string' || hosting.project_id.length === 0) {
  throw new Error('Sites hosting metadata is missing a project_id.')
}

if (hosting.d1 !== null || hosting.r2 !== null) {
  throw new Error('This client-only build must not declare D1 or R2 bindings.')
}

const worker = await readFile(workerPath, 'utf8')
if (!worker.includes("Permissions-Policy', 'hid=(self)'")) {
  throw new Error('The Sites worker must explicitly permit same-origin WebHID.')
}

console.log('Sites build is ready: static assets, worker entry, and hosting metadata are present.')
