[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$LatestJsonPath,
    [string[]]$AllowedScopes = @('frontend', 'full', 'portable-full', 'portable', 'portable-exe', 'portable-zip', 'sidebar'),
    [string]$PackagePath,
    [string]$ExpectedCommit,
    [string]$ExpectedVersion,
    [string]$BaselineLatestJsonPath
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
function Read-Field($Object, [string]$Name) {
    if ($null -ne $Object -and $null -ne $Object.PSObject.Properties[$Name]) { return $Object.$Name }
    return $null
}
function Read-ZipJson($Archive, [string]$Name, [string]$Prefix) {
    $entries = @($Archive.Entries | Where-Object { $_.FullName.Replace('\', '/') -ceq "$Prefix$Name" })
    if ($entries.Count -ne 1 -or $entries[0].Length -gt 1048576) { throw "OPENVIDEO_PACKAGE_IDENTITY_MISSING_OR_DUPLICATE: $Name" }
    $reader = [IO.StreamReader]::new($entries[0].Open())
    try { return ($reader.ReadToEnd() | ConvertFrom-Json) } finally { $reader.Dispose() }
}
if (-not (Test-Path -LiteralPath $LatestJsonPath -PathType Leaf)) { throw 'OPENVIDEO_LATEST_JSON_MISSING' }
$raw = Get-Content -LiteralPath $LatestJsonPath -Encoding UTF8 -Raw
$manifest = $raw.TrimStart([char]0xFEFF) | ConvertFrom-Json
$scope = [string](Read-Field $manifest 'scope')
$commit = [string](Read-Field $manifest 'commit')
$headCommit = [string](Read-Field $manifest 'headCommit')
$version = [string](Read-Field $manifest 'version')
$pack = Read-Field $manifest 'package'
$digest = [string](Read-Field $pack 'sha256')
$bytes = Read-Field $pack 'bytes'
$errors = [Collections.Generic.List[string]]::new()
$requiresRevision = $false
if ((Read-Field $manifest 'schema_version') -ne 1) { $errors.Add('schema_version must be 1') }
if ($AllowedScopes -cnotcontains $scope) { $errors.Add('scope is not allowed') }
if ($commit -cnotmatch '^[a-f0-9]{40}$') { $errors.Add('commit must be a 40-char lowercase hex SHA') }
# 旧 frontend 通道允许缺少 headCommit，并保留其历史双提交语义。
if ($scope -eq 'sidebar' -or $headCommit) {
    if ($headCommit -cnotmatch '^[a-f0-9]{40}$') { $errors.Add('headCommit must be a 40-char lowercase hex SHA') }
}
if ($scope -eq 'sidebar') {
    if ($headCommit -cne $commit) { $errors.Add('sidebar headCommit must equal commit') }
    if ($version -cnotmatch '^v(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)$') { $errors.Add('sidebar version must be a canonical stable product version') }
    if ($BaselineLatestJsonPath) {
        $baselineRaw = (Get-Content -LiteralPath $BaselineLatestJsonPath -Encoding UTF8 -Raw).TrimStart([char]0xFEFF)
        if ($raw.TrimStart([char]0xFEFF) -cne $baselineRaw) {
            $baseline = $baselineRaw | ConvertFrom-Json
            $previousVersion = [string](Read-Field $baseline 'version')
            if ($version -cmatch '^v(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)$' -and [version]$version.Substring(1) -le [version]$previousVersion.Substring(1)) { $errors.Add('sidebar version must increase from baseline') }
            $requiresRevision = $true
        }
    }
}
if ($ExpectedCommit -and $commit -cne $ExpectedCommit) { $errors.Add('commit does not match the release source') }
if ($ExpectedVersion -and $version -cne $ExpectedVersion) { $errors.Add('version does not match the release source') }
if ($digest -cnotmatch '^[a-f0-9]{64}$') { $errors.Add('package.sha256 must be a 64-char lowercase digest') }
if ($null -eq $bytes -or $bytes -is [string] -or $bytes -is [bool] -or $bytes -isnot [ValueType] -or $bytes -le 0 -or [math]::Floor([double]$bytes) -ne $bytes) { $errors.Add('package.bytes must be a positive integer') }
if ($scope -in @('sidebar', 'frontend') -and $bytes -ge 524288000) { $errors.Add('public package must be smaller than 500 MiB') }
try {
    $uri = [Uri]([string](Read-Field $pack 'url'))
    $prefix = if ($uri.Host -eq 'media.githubusercontent.com') { '/media/Gwaky07/OpenVideo-updates/' } else { '/Gwaky07/OpenVideo-updates/' }
    if ($uri.Scheme -ne 'https' -or $uri.Host -notin @('github.com', 'raw.githubusercontent.com', 'media.githubusercontent.com', 'objects.githubusercontent.com', 'user-images.githubusercontent.com') -or -not $uri.AbsolutePath.StartsWith($prefix, [StringComparison]::Ordinal) -or $uri.UserInfo -or -not $uri.IsDefaultPort) { throw 'invalid url' }
    if ($scope -eq 'sidebar' -and [Uri]::UnescapeDataString($uri.Segments[-1]) -cne "OpenVideo-sidebar-$version-windows.zip") { $errors.Add('sidebar URL filename does not match version') }
} catch { $errors.Add('package.url must be an approved HTTPS update URL') }
if ($errors.Count) { throw "OPENVIDEO_LATEST_JSON_SCHEMA_INVALID: $($errors -join '; ')" }
if ($PackagePath) {
    if (-not (Test-Path -LiteralPath $PackagePath -PathType Leaf)) { throw 'OPENVIDEO_UPDATE_PACKAGE_MISSING' }
    if ((Get-Item -LiteralPath $PackagePath).Length -ne $bytes) { throw 'OPENVIDEO_UPDATE_PACKAGE_BYTES_MISMATCH' }
    if ((Get-FileHash -LiteralPath $PackagePath -Algorithm SHA256).Hash.ToLowerInvariant() -cne $digest) { throw 'OPENVIDEO_UPDATE_PACKAGE_SHA256_MISMATCH' }
    if ($scope -eq 'sidebar') {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $archive = [IO.Compression.ZipFile]::OpenRead([IO.Path]::GetFullPath($PackagePath))
        try {
            $ids = @($archive.Entries | Where-Object { $_.FullName.Replace('\', '/') -match '(^|/)openvideo-sidebar-package\.json$' })
            if ($ids.Count -ne 1) { throw 'OPENVIDEO_PACKAGE_IDENTITY_MISSING_OR_DUPLICATE' }
            $idName = $ids[0].FullName.Replace('\', '/')
            $prefix = $idName.Substring(0, $idName.Length - 'openvideo-sidebar-package.json'.Length)
            foreach ($entry in $archive.Entries) {
                $name = $entry.FullName.Replace('\', '/')
                $unixType = ($entry.ExternalAttributes -shr 16) -band 0xf000
                if ($unixType -notin @(0, 0x8000, 0x4000) -or ($entry.ExternalAttributes -band 0x400) -ne 0 -or $name.Contains(':') -or $name.StartsWith('/') -or $name.Contains([char]0) -or -not $name.StartsWith($prefix, [StringComparison]::Ordinal) -or $name -match '(^|/)(\.\.?|runtime|upstream|node_modules|test|tests|\.git)(/|$)|\.map$|(^|/)\.env($|\.)|\.(key|pem|db|sqlite3?|log)$') { throw 'OPENVIDEO_SIDEBAR_PACKAGE_FORBIDDEN_CONTENT' }
            }
            $identity = Read-ZipJson $archive 'openvideo-sidebar-package.json' $prefix
            $config = Read-ZipJson $archive 'config/product-update.json' $prefix
            if ((Read-Field $identity 'schema_version') -ne 1 -or (Read-Field $identity 'scope') -cne 'sidebar' -or (Read-Field $identity 'commit') -cne $commit -or (Read-Field $identity 'version') -cne $version -or (Read-Field $config 'productVersion') -cne $version) { throw 'OPENVIDEO_PACKAGE_IDENTITY_MISMATCH' }
            # v0.3.46 及更早的历史包以包内身份为准；新发行必须校验配置提交链。
            $revision = Read-Field $identity 'identity_revision'
            $baseVersion = [version]($version.Substring(1).Split('-')[0])
            if ($null -ne $revision -and $revision -ne 2) { throw 'OPENVIDEO_PACKAGE_IDENTITY_REVISION_INVALID' }
            if (($requiresRevision -or $baseVersion -gt [version]'0.3.46') -and $revision -ne 2) { throw 'OPENVIDEO_PACKAGE_IDENTITY_REVISION_REQUIRED' }
            if ($revision -eq 2 -and ((Read-Field $config 'headCommit') -cne $commit -or (Read-Field $config 'releaseCommit') -cne $commit)) { throw 'OPENVIDEO_PACKAGE_CONFIG_COMMIT_MISMATCH' }
        } finally { $archive.Dispose() }
    }
}
