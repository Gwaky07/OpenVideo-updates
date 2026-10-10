import assert from 'node:assert/strict'
import { createHash } from 'node:crypto'
import { readFileSync } from 'node:fs'
import https from 'node:https'

// 使用与旧客户端相同的不跟随跳转请求；只读下载到内存摘要，不安装、不写用户文件。
const manifest = JSON.parse(readFileSync(process.argv[2], 'utf8').replace(/^\uFEFF/, ''))
assert.ok(['sidebar', 'frontend'].includes(manifest.scope))
const name = manifest.scope === 'sidebar' ? `OpenVideo-sidebar-${manifest.version}-windows.zip` : 'frontend.zip'
assert.equal(manifest.package.url, `https://raw.githubusercontent.com/Gwaky07/OpenVideo-updates/main/${name}`)
assert.ok(Number.isSafeInteger(manifest.package.bytes) && manifest.package.bytes > 0 && manifest.package.bytes < 104857600)
assert.match(manifest.package.sha256, /^[a-f0-9]{64}$/)
const candidate = process.env.OPENVIDEO_CANDIDATE_REF
if (candidate) assert.match(candidate, /^[a-f0-9]{40}$/)
const url = candidate ? manifest.package.url.replace('/main/', `/${candidate}/`) : manifest.package.url
await new Promise((resolve, reject) => {
  let request
  let stream
  let settled = false
  const fail = error => {
    if (settled) return
    settled = true
    clearTimeout(timeout)
    reject(error)
    stream?.destroy()
    request?.destroy()
  }
  // 与产品下载器相同的 15 分钟上限；慢网络不能被 3 分钟诊断限额误判。
  const timeout = setTimeout(() => fail(new Error('DIRECT_DOWNLOAD_TIMEOUT')), 15 * 60000)
  request = https.get(url, { headers: { accept: 'application/octet-stream' } }, response => {
    stream = response
    if (response.statusCode !== 200 || response.headers.location) return fail(new Error(`DIRECT_DOWNLOAD_HTTP_${response.statusCode}`))
    console.log('DIRECT_DOWNLOAD_HTTP_200_NO_REDIRECT')
    const hash = createHash('sha256')
    let bytes = 0
    let nextReport = 4 * 1024 * 1024
    response.on('data', chunk => {
      bytes += chunk.length
      if (bytes > manifest.package.bytes) return fail(new Error('DIRECT_DOWNLOAD_OVERFLOW'))
      hash.update(chunk)
      if (bytes >= nextReport) {
        console.log(`DIRECT_DOWNLOAD_PROGRESS bytes=${bytes} total=${manifest.package.bytes}`)
        nextReport = bytes + 4 * 1024 * 1024
      }
    })
    response.on('error', fail)
    response.on('aborted', () => fail(new Error('DIRECT_DOWNLOAD_ABORTED')))
    response.on('end', () => {
      if (settled) return
      settled = true
      clearTimeout(timeout)
      try {
        assert.equal(bytes, manifest.package.bytes)
        assert.equal(hash.digest('hex'), manifest.package.sha256)
        console.log(`DIRECT_DOWNLOAD_VERIFIED bytes=${bytes}`)
        resolve()
      } catch (error) { reject(error) }
    })
  })
  request.on('error', fail)
})
