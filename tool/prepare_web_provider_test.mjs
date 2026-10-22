// Download the immutable published provider, verify npm's integrity, and extract
// only its browser bundle. The ignored fixture is never shipped in the SDK.
import { createHash } from 'node:crypto'
import { cp, mkdir, writeFile } from 'node:fs/promises'
import { execFileSync } from 'node:child_process'
import { dirname, join } from 'node:path'
import { gunzipSync } from 'node:zlib'

const version = '0.2.0'
const metadata = await fetch(`https://registry.npmjs.org/@inappifylabs/web-sdk/${version}`)
if (!metadata.ok) throw new Error(`Provider metadata: ${metadata.status}`)
const { dist } = await metadata.json()
const archive = await fetch(dist.tarball)
if (!archive.ok) throw new Error(`Provider archive: ${archive.status}`)
const bytes = Buffer.from(await archive.arrayBuffer())
const integrity = `sha512-${createHash('sha512').update(bytes).digest('base64')}`
if (integrity !== dist.integrity) throw new Error('Provider integrity mismatch')
const tar = gunzipSync(bytes)
let bundle
for (let offset = 0; offset + 512 <= tar.length;) {
  const header = tar.subarray(offset, offset + 512)
  const name = header.subarray(0, 100).toString().replace(/\0.*$/s, '')
  if (!name) break
  const size = Number.parseInt(header.subarray(124, 136).toString().replace(/\0.*$/s, '').trim(), 8)
  if (!Number.isSafeInteger(size) || size < 0) throw new Error('Invalid archive')
  if (name === 'package/dist/inappify.global.js') bundle = tar.subarray(offset + 512, offset + 512 + size)
  offset += 512 + Math.ceil(size / 512) * 512
}
if (!bundle?.length) throw new Error('Published browser bundle missing')
const path = new URL(`../test/web/fixtures/provider-${version}.local.js`, import.meta.url)
await mkdir(new URL('.', path), { recursive: true })
await writeFile(path, bundle)
console.log(`Verified @inappifylabs/web-sdk@${version}: ${integrity}`)

// Flutter 3.47's Windows test server normalizes CanvasKit URLs with backslashes
// before testing its slash-prefixed route. Its static test-file handler still
// works: supply the exact installed engine assets there, without modifying the
// Flutter installation. Browser tests remain at test/ root for the same reason.
if (process.platform === 'win32') {
  const flutterBin = process.env.FLUTTER_ROOT
    ? join(process.env.FLUTTER_ROOT, 'bin')
    : dirname(execFileSync('where.exe', ['flutter.bat'], { encoding: 'utf8' }).trim().split(/\r?\n/)[0])
  const canvasKit = join(flutterBin, 'cache', 'flutter_web_sdk', 'canvaskit')
  await cp(canvasKit, new URL('../test/canvaskit/', import.meta.url), { recursive: true })
  console.log('Prepared installed CanvasKit assets for the Windows test server')
}
