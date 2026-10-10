import assert from 'node:assert/strict'
import { spawnSync } from 'node:child_process'
import { createHash } from 'node:crypto'
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, rmSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import test from 'node:test'

const root = join(dirname(fileURLToPath(import.meta.url)), '..')
const shell = process.env.OPENVIDEO_TEST_POWERSHELL || (process.platform === 'win32' ? 'powershell.exe' : 'pwsh')
const childEnv = { ...process.env }
// 模拟从 CMD 启动；避免父进程 PowerShell 7 的模块路径污染 5.1。
delete childEnv.PSModulePath
const work = join(root, '.openvideo-work', 'identity-tests')
mkdirSync(work, { recursive: true })
const temp = mkdtempSync(join(work, 'case-'))
const manifestPath = join(temp, 'latest-sidebar.json')
const commit = 'a'.repeat(40)
const version = 'v0.3.99'
const valid = () => ({ schema_version: 1, scope: 'sidebar', commit, headCommit: commit, version, package: { url: `https://raw.githubusercontent.com/Gwaky07/OpenVideo-updates/main/OpenVideo-sidebar-${version}-windows.zip`, sha256: 'b'.repeat(64), bytes: 100 } })
const check = (manifest, args = []) => {
  writeFileSync(manifestPath, JSON.stringify(manifest))
  return spawnSync(shell, ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', join(root, 'scripts', 'Assert-OpenVideoLatestJson.ps1'), '-LatestJsonPath', manifestPath, ...args], { encoding: 'utf8', env: childEnv })
}
test.after(() => rmSync(temp, { recursive: true, force: true }))
test('完整 SHA 清单通过，旧 frontend 通道保持兼容', () => {
  let result = check(valid())
  assert.equal(result.status, 0, result.stderr)
  const legacy = { ...valid(), scope: 'frontend', version: commit.slice(0, 12) }
  legacy.package.url = 'https://raw.githubusercontent.com/Gwaky07/OpenVideo-updates/main/frontend.zip'
  delete legacy.headCommit
  result = check(legacy)
  assert.equal(result.status, 0, result.stderr)
})
for (const [name, change] of [
  ['短 commit', m => { m.commit = 'f5d77993' }],
  ['短 headCommit', m => { m.headCommit = 'f5d77993' }],
  ['缺少 headCommit', m => { delete m.headCommit }],
  ['headCommit 不一致', m => { m.headCommit = 'c'.repeat(40) }],
  ['大写 SHA', m => { m.commit = 'A'.repeat(40) }],
  ['非产品版本', m => { m.version = 'f5d77993' }],
  ['前导零版本', m => { m.version = 'v0.3.099' }],
  ['字符串 bytes', m => { m.package.bytes = '100' }],
  ['负数 bytes', m => { m.package.bytes = -1 }],
  ['小数 bytes', m => { m.package.bytes = 1.5 }],
  ['缺少 package', m => { delete m.package }],
  ['公开包超过大小限制', m => { m.package.bytes = 524288000 }],
  ['错误仓库地址', m => { m.package.url = m.package.url.replace('/OpenVideo-updates/', '/Other/') }],
  ['HTTP 地址', m => { m.package.url = m.package.url.replace('https:', 'http:') }],
  ['URL 版本不一致', m => { m.package.url = m.package.url.replaceAll(version, 'v0.3.1') }],
  ['GitHub Release 入口', m => { m.package.url = `https://github.com/Gwaky07/OpenVideo-updates/releases/download/${version}/OpenVideo-sidebar-${version}-windows.zip` }],
  ['LFS media 入口', m => { m.package.url = m.package.url.replace('raw.githubusercontent.com/', 'media.githubusercontent.com/media/') }],
  ['非 main 地址', m => { m.package.url = m.package.url.replace('/main/', '/other/') }],
  ['临时 URL 参数', m => { m.package.url += '?token=temp' }],
  ['普通 Git 超限', m => { m.package.bytes = 104857600 }],
]) {
  test(`拒绝${name}`, () => {
    const m = valid(); change(m)
    const result = check(m)
    assert.notEqual(result.status, 0)
    assert.match(result.stderr, /OPENVIDEO_LATEST_JSON_SCHEMA_INVALID/)
  })
}
test('拒绝与发布源码的提交、版本不一致', () => {
  assert.notEqual(check(valid(), ['-ExpectedCommit', 'd'.repeat(40)]).status, 0)
  assert.notEqual(check(valid(), ['-ExpectedVersion', 'v0.3.1']).status, 0)
})
test('既有清单原样兼容，新清单必须严格递增', () => {
  const baseline = join(temp, 'baseline.json')
  writeFileSync(baseline, JSON.stringify(valid()))
  assert.equal(check(valid(), ['-BaselineLatestJsonPath', baseline]).status, 0)
  const changed = valid(); changed.summary = 'changed'
  assert.notEqual(check(changed, ['-BaselineLatestJsonPath', baseline]).status, 0)
  changed.version = 'v0.3.98'; changed.package.url = changed.package.url.replaceAll(version, changed.version)
  assert.notEqual(check(changed, ['-BaselineLatestJsonPath', baseline]).status, 0)
  changed.version = 'v0.3.100'; changed.package.url = valid().package.url.replaceAll(version, changed.version)
  assert.equal(check(changed, ['-BaselineLatestJsonPath', baseline]).status, 0)
})
test('地址恢复仅允许改变 URL，禁止同时更换包或元数据', () => {
  const baseline = join(temp, 'address-baseline.json')
  const old = valid()
  old.package.url = `https://github.com/Gwaky07/OpenVideo-updates/releases/download/${version}/OpenVideo-sidebar-${version}-windows.zip`
  writeFileSync(baseline, JSON.stringify(old))
  const m = valid()
  m.package.url = `https://raw.githubusercontent.com/Gwaky07/OpenVideo-updates/main/OpenVideo-sidebar-${version}-windows.zip`
  const args = ['-BaselineLatestJsonPath', baseline]
  assert.equal(check(m, args).status, 0)
  for (const mutate of [v => { v.commit = v.headCommit = 'c'.repeat(40) }, v => { v.package.sha256 = 'c'.repeat(64) }, v => { v.package.bytes++ }, v => { v.summary = 'changed' }]) {
    const changed = structuredClone(m); mutate(changed)
    assert.notEqual(check(changed, args).status, 0)
  }
})
test('检查 ZIP 的真实身份、配置版本、摘要和字节数', () => {
  const stage = join(temp, `OpenVideo-${version}`)
  mkdirSync(join(stage, 'config'), { recursive: true })
  const identity = { schema_version: 1, identity_revision: 2, scope: 'sidebar', commit, version }
  const config = { productVersion: version, headCommit: commit, releaseCommit: commit }
  writeFileSync(join(stage, 'openvideo-sidebar-package.json'), JSON.stringify(identity))
  writeFileSync(join(stage, 'config', 'product-update.json'), JSON.stringify(config))
  const zip = join(temp, 'package.zip')
  const pack = () => {
    const quote = value => `'${value.replaceAll("'", "''")}'`
    const result = spawnSync(shell, ['-NoProfile', '-Command', `Compress-Archive -LiteralPath ${quote(stage)} -DestinationPath ${quote(zip)} -Force`], { encoding: 'utf8', env: childEnv })
    assert.equal(result.status, 0, result.stderr)
    const blob = readFileSync(zip)
    const m = valid(); m.package.bytes = blob.length; m.package.sha256 = createHash('sha256').update(blob).digest('hex')
    return m
  }
  const m = pack()
  const accepted = check(m, ['-PackagePath', zip])
  assert.equal(accepted.status, 0, accepted.stderr)
  assert.match(check({ ...m, package: { ...m.package, bytes: m.package.bytes + 1 } }, ['-PackagePath', zip]).stderr, /BYTES_MISMATCH/)
  assert.match(check({ ...m, package: { ...m.package, sha256: '0'.repeat(64) } }, ['-PackagePath', zip]).stderr, /SHA256_MISMATCH/)
  writeFileSync(join(stage, 'openvideo-sidebar-package.json'), JSON.stringify({ ...identity, commit: 'c'.repeat(40) }))
  assert.match(check(pack(), ['-PackagePath', zip]).stderr, /IDENTITY_MISMATCH/)
  writeFileSync(join(stage, 'openvideo-sidebar-package.json'), JSON.stringify(identity))
  writeFileSync(join(stage, 'config', 'product-update.json'), JSON.stringify({ ...config, productVersion: 'v0.3.1' }))
  assert.match(check(pack(), ['-PackagePath', zip]).stderr, /IDENTITY_MISMATCH/)
  writeFileSync(join(stage, 'config', 'product-update.json'), JSON.stringify({ ...config, headCommit: 'c'.repeat(40) }))
  assert.match(check(pack(), ['-PackagePath', zip]).stderr, /CONFIG_COMMIT_MISMATCH/)
  writeFileSync(join(stage, 'config', 'product-update.json'), JSON.stringify({ ...config, releaseCommit: 'c'.repeat(40) }))
  assert.match(check(pack(), ['-PackagePath', zip]).stderr, /CONFIG_COMMIT_MISMATCH/)
  writeFileSync(join(stage, 'config', 'product-update.json'), JSON.stringify(config))
  writeFileSync(join(stage, 'openvideo-sidebar-package.json'), JSON.stringify({ ...identity, identity_revision: undefined }))
  assert.match(check(pack(), ['-PackagePath', zip]).stderr, /REVISION_REQUIRED/)
  writeFileSync(join(stage, 'openvideo-sidebar-package.json'), JSON.stringify(identity))
  mkdirSync(join(stage, 'runtime'))
  writeFileSync(join(stage, 'runtime', 'forbidden.txt'), 'runtime')
  assert.match(check(pack(), ['-PackagePath', zip]).stderr, /FORBIDDEN_CONTENT/)
})
