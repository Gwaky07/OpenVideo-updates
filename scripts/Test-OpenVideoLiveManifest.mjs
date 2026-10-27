// REL-055：发布合并后，确认 raw/main 上客户端实际读到的清单就是刚合并的那份。
//
// Test-OpenVideoDirectDownload.mjs 只按本地清单下载 ZIP；如果 raw/main 的清单本身还是
// 旧版本（缓存、合并失败、合并到了别的提交），同事仍然看不到更新。这里按客户端方式
// （不跟随跳转、加防缓存参数）读取线上清单并逐字段比对，容忍 raw CDN 数分钟的缓存。
//
// 用法：node scripts/Test-OpenVideoLiveManifest.mjs <刚发布的本地 latest-sidebar.json>
import https from 'node:https'
import { readFileSync } from 'node:fs'
import { basename, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const FEED_BASE = 'https://raw.githubusercontent.com/Gwaky07/OpenVideo-updates/main/'

const field = (value, path) => path.split('.').reduce((current, key) => (current == null ? undefined : current[key]), value)

export const compareLiveManifest = (published, live) => {
  const problems = []
  for (const path of ['scope', 'version', 'commit', 'headCommit', 'summary', 'package.url', 'package.sha256', 'package.bytes']) {
    const expected = field(published, path)
    const actual = field(live, path)
    if (expected !== actual) problems.push(`${path}: expected ${JSON.stringify(expected)}, raw/main has ${JSON.stringify(actual)}`)
  }
  if (JSON.stringify(published?.notes ?? null) !== JSON.stringify(live?.notes ?? null)) {
    problems.push('notes: raw/main notes differ from the published notes')
  }
  return problems
}

const fetchManifestOnce = (manifestName) => new Promise((resolve, reject) => {
  const url = new URL(manifestName, FEED_BASE)
  url.searchParams.set('openvideo_verify', String(Date.now()))
  const request = https.get(url, { headers: { accept: 'application/json', 'cache-control': 'no-cache', pragma: 'no-cache' } }, (response) => {
    if (response.statusCode !== 200 || response.headers.location) {
      response.resume()
      reject(new Error(`OPENVIDEO_LIVE_MANIFEST_HTTP_${response.statusCode}`))
      return
    }
    const chunks = []
    let size = 0
    response.on('data', (chunk) => {
      size += chunk.length
      if (size > 1024 * 1024) { request.destroy(new Error('OPENVIDEO_LIVE_MANIFEST_TOO_LARGE')); return }
      chunks.push(chunk)
    })
    response.on('end', () => {
      try { resolve(JSON.parse(Buffer.concat(chunks).toString('utf8').replace(/^﻿/u, ''))) } catch (error) { reject(error) }
    })
    response.on('error', reject)
  })
  request.setTimeout(30_000, () => request.destroy(new Error('OPENVIDEO_LIVE_MANIFEST_TIMEOUT')))
  request.on('error', reject)
})

export const verifyLiveManifest = async (published, {
  manifestName = 'latest-sidebar.json',
  fetchManifest = () => fetchManifestOnce(manifestName),
  attempts = 20,
  delayMs = 30_000,
  log = () => {},
} = {}) => {
  let lastProblems = ['raw/main was not read']
  for (let attempt = 1; attempt <= attempts; attempt += 1) {
    try {
      const live = await fetchManifest()
      lastProblems = compareLiveManifest(published, live)
      if (lastProblems.length === 0) return { attempts: attempt }
    } catch (error) {
      lastProblems = [String(error?.message ?? error)]
    }
    log(`OPENVIDEO_LIVE_MANIFEST_WAITING attempt=${attempt}/${attempts}: ${lastProblems[0]}`)
    if (attempt < attempts && delayMs > 0) await new Promise((resolve) => setTimeout(resolve, delayMs))
  }
  throw new Error(`OPENVIDEO_LIVE_MANIFEST_MISMATCH after ${attempts} attempts: ${lastProblems.join('; ')}`)
}

const isEntryPoint = Boolean(process.argv[1]) &&
  resolve(fileURLToPath(import.meta.url)).toLowerCase() === resolve(process.argv[1]).toLowerCase()
if (isEntryPoint) {
  const manifestPath = process.argv[2]
  if (!manifestPath) {
    console.error('usage: node scripts/Test-OpenVideoLiveManifest.mjs <published latest-sidebar.json>')
    process.exit(2)
  }
  const published = JSON.parse(readFileSync(manifestPath, 'utf8').replace(/^﻿/u, ''))
  // 线上清单名由 scope 决定，不能取本地文件名（本地可能是临时副本）。
  const manifestName = published.scope === 'frontend' ? 'latest.json' : 'latest-sidebar.json'
  if (basename(manifestPath) !== manifestName) console.log(`OPENVIDEO_LIVE_MANIFEST_TARGET ${manifestName}`)
  try {
    const { attempts } = await verifyLiveManifest(published, { manifestName, log: (line) => console.log(line) })
    console.log(`OPENVIDEO_LIVE_MANIFEST_VERIFIED version=${published.version} commit=${published.commit} attempts=${attempts}`)
  } catch (error) {
    console.error(String(error?.message ?? error))
    process.exit(1)
  }
}
