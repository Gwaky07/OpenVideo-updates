[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$LatestJsonPath,

    # Source-of-truth allowlist mirrors apps/gateway/src/public-frontend-update.mjs
    # PORTABLE_SCOPE_ALIASES + the canonical {frontend, full} set. Keep the
    # list synchronized with the gateway alias table whenever the supported
    # scopes change. We intentionally list BOTH the canonical and the portable
    # aliases so a portable-only publish (Build-OpenVideoPortableExe.ps1) can
    # still validate locally even though the gateway will normalize the value.
    [string[]]$AllowedScopes = @('frontend', 'full', 'portable-full', 'portable', 'portable-exe', 'portable-zip', 'sidebar'),
    [string]$PackagePath,
    [string]$ExpectedCommit,
    [string]$ExpectedVersion,
    [string]$BaselineLatestJsonPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

& (Join-Path $PSScriptRoot 'Assert-OpenVideoUpdateIdentity.ps1') -LatestJsonPath $LatestJsonPath -AllowedScopes $AllowedScopes -PackagePath $PackagePath -ExpectedCommit $ExpectedCommit -ExpectedVersion $ExpectedVersion -BaselineLatestJsonPath $BaselineLatestJsonPath

if (-not (Test-Path -LiteralPath $LatestJsonPath -PathType Leaf)) {
    throw "OPENVIDEO_LATEST_JSON_MISSING path=$LatestJsonPath"
}

# Strip the UTF-8 BOM some Windows PowerShell writers emit, then parse the
# manifest with strict mode so any unknown field is reported up front.
$raw = Get-Content -LiteralPath $LatestJsonPath -Encoding UTF8 -Raw
if ($null -ne $raw -and $raw.Length -gt 0 -and $raw[0] -eq [char]0xFEFF) {
    $raw = $raw.Substring(1)
}
try {
    $manifest = $raw | ConvertFrom-Json -ErrorAction Stop
} catch {
    throw "OPENVIDEO_LATEST_JSON_PARSE_FAILED path=$LatestJsonPath error=$($_.Exception.Message)"
}

$errors = New-Object System.Collections.Generic.List[string]

if ($manifest.schema_version -ne 1) {
    $errors.Add("schema_version must be 1 (got '$($manifest.schema_version)')")
}

$scope = if ($null -eq $manifest.scope) { '' } else { [string]$manifest.scope }
if ([string]::IsNullOrWhiteSpace($scope)) {
    $errors.Add('scope is required')
} elseif (-not $AllowedScopes.Contains($scope)) {
    $errors.Add("scope '$scope' is not in allowed list [$($AllowedScopes -join ', ')]")
}

if ([string]::IsNullOrWhiteSpace([string]$manifest.commit) -or -not ([string]$manifest.commit -match '^[a-f0-9]{40}$')) {
    $errors.Add("commit must be a 40-char hex SHA (got '$($manifest.commit)')")
}

if ($null -eq $manifest.package -or $null -eq $manifest.package.url) {
    $errors.Add('package.url is required')
} elseif ($manifest.package.url -notmatch '^https://') {
    $errors.Add("package.url must be https (got '$($manifest.package.url)')")
}

if ([string]::IsNullOrWhiteSpace([string]$manifest.package.sha256) -or -not ([string]$manifest.package.sha256 -match '^[a-f0-9]{64}$')) {
    $errors.Add("package.sha256 must be a 64-char hex digest (got '$($manifest.package.sha256)')")
}

if ($errors.Count -gt 0) {
    $joined = ($errors | ForEach-Object { "  - $_" }) -join [Environment]::NewLine
    throw "OPENVIDEO_LATEST_JSON_SCHEMA_INVALID`n$joined"
}

Write-Host "OPENVIDEO_LATEST_JSON_SCHEMA_OK scope=$scope commit=$($manifest.commit.Substring(0,12))"
exit 0
