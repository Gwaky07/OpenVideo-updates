# REL-055：发布说明的唯一校验规则。
#
# 由 Assert-OpenVideoUpdateIdentity.ps1（同时同步到公开更新仓的门禁）、
# Publish-OpenVideoSidebarUpdate.ps1 和 Build-OpenVideoFullUpdate.ps1 以点号引入。
# 规则对齐 Gateway 客户端 apps/gateway/src/product-update.mjs 的 asNoteObject：
# 字符串说明超过 96 字会被静默截断，没有中文或带网址/密钥特征的说明会被丢弃，
# 因此发布端必须提前拒绝，而不是让用户看到被截断、被丢弃或拼成一行的说明。
#
# 本文件只定义函数，不执行任何操作。

$script:OpenVideoNoteCjkPattern = '[㐀-鿿]'
$script:OpenVideoNoteSafePattern = '^[\p{L}\p{N}\p{P}\p{S}\p{Zs}]+$'
$script:OpenVideoNoteUnsafePattern = '(?i)https?://|github\.com|[A-Za-z]:\\|sk-|api[_-]?key|token='
$script:OpenVideoNoteMaxCount = 8
$script:OpenVideoNoteMaxLength = 96
$script:OpenVideoSummaryMaxLength = 80

function Get-OpenVideoNormalizedNoteText([string]$Value) {
    return ([regex]::Replace($Value, '\s+', ' ')).Trim()
}

function Get-OpenVideoReleaseNotesErrors {
    # 参数保持无类型：调用方必须直接传入属性值，不能经过函数返回或 if 表达式，
    # 否则 PowerShell 会把单元素数组展开成字符串，无法区分“一条说明”和“拼成一条的字符串”。
    param($Summary, $Notes)
    $errors = [Collections.Generic.List[string]]::new()

    if ($Summary -isnot [string]) {
        $errors.Add('summary must be a Chinese string')
    } else {
        $summaryText = Get-OpenVideoNormalizedNoteText $Summary
        if ($summaryText.Length -eq 0) { $errors.Add('summary must not be empty') }
        elseif ($summaryText.Length -gt $script:OpenVideoSummaryMaxLength) { $errors.Add("summary must be at most $($script:OpenVideoSummaryMaxLength) characters") }
        if ($summaryText -notmatch $script:OpenVideoNoteCjkPattern) { $errors.Add('summary must be written in Chinese') }
        if ($summaryText -match $script:OpenVideoNoteUnsafePattern) { $errors.Add("summary matches the client's unsafe-text filter (matched '$($Matches[0])': URL, drive path, 'sk-', 'api_key' or 'token='); the client would hide it, reword it") }
    }

    if ($null -eq $Notes -or $Notes -is [string] -or $Notes -isnot [Collections.IList]) {
        $errors.Add('notes must be an array of separate Chinese strings')
        return $errors
    }
    if ($Notes.Count -lt 1 -or $Notes.Count -gt $script:OpenVideoNoteMaxCount) {
        $errors.Add("notes must contain 1 to $($script:OpenVideoNoteMaxCount) entries")
    }
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    for ($index = 0; $index -lt $Notes.Count; $index++) {
        $note = $Notes[$index]
        $label = "notes[$index]"
        if ($note -isnot [string]) { $errors.Add("$label must be a string"); continue }
        $text = Get-OpenVideoNormalizedNoteText $note
        if ($text.Length -eq 0) { $errors.Add("$label must not be empty"); continue }
        if ($text.Length -gt $script:OpenVideoNoteMaxLength) { $errors.Add("$label must be at most $($script:OpenVideoNoteMaxLength) characters (the client truncates longer notes)") }
        if ($text -notmatch $script:OpenVideoNoteCjkPattern) { $errors.Add("$label must be written in Chinese (the client drops notes without Chinese)") }
        if ($text -match $script:OpenVideoNoteUnsafePattern) { $errors.Add("$label matches the client's unsafe-text filter (matched '$($Matches[0])': URL, drive path, 'sk-', 'api_key' or 'token='); the client would drop it, reword it") }
        if ($text -notmatch $script:OpenVideoNoteSafePattern) { $errors.Add("$label contains control characters or emoji; use plain text") }
        # v0.3.55：三条说明被拼成 "'a','b','c'" 一条字符串，弹窗里显示成一整行。
        if ($text -match "^\s*['""].*['""]\s*$" -or $text -match "['""]\s*,\s*['""]") { $errors.Add("$label looks like several notes joined into one quoted string; list each note separately, and use 「」 or “” for quoted words") }
        if (-not $seen.Add($text)) { $errors.Add("$label duplicates an earlier note") }
    }
    return $errors
}

function Read-OpenVideoReleaseNotesFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Version
    )
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "OPENVIDEO_RELEASE_NOTES_MISSING: $Path (write release-notes/$Version.json with a Chinese summary and notes, commit it, then publish; see release-notes/README.md)"
    }
    $raw = [IO.File]::ReadAllText([IO.Path]::GetFullPath($Path), [Text.UTF8Encoding]::new($false)).TrimStart([char]0xFEFF)
    try {
        $data = $raw | ConvertFrom-Json -ErrorAction Stop
    } catch {
        throw "OPENVIDEO_RELEASE_NOTES_INVALID: $Path is not valid JSON"
    }
    # ConvertFrom-Json 会展开 [] 并把字符串包装成 PSObject，类型判断不可靠；直接看原文。
    if (-not $raw.TrimStart().StartsWith('{') -or $null -eq $data) {
        throw "OPENVIDEO_RELEASE_NOTES_INVALID: $Path must contain a JSON object with version, summary and notes"
    }
    $errors = [Collections.Generic.List[string]]::new()
    $versionProperty = $data.PSObject.Properties['version']
    if ($null -eq $versionProperty -or [string]$versionProperty.Value -cne $Version) {
        $errors.Add("version must equal $Version")
    }
    # 直接读取属性值并赋给变量；不要用 if 表达式或函数返回，避免单元素数组被展开。
    $summary = $null
    $summaryProperty = $data.PSObject.Properties['summary']
    if ($null -ne $summaryProperty) { $summary = $summaryProperty.Value }
    $notes = $null
    $notesProperty = $data.PSObject.Properties['notes']
    if ($null -ne $notesProperty) { $notes = $notesProperty.Value }
    foreach ($problem in (Get-OpenVideoReleaseNotesErrors -Summary $summary -Notes $notes)) { $errors.Add($problem) }
    if ($errors.Count) {
        throw "OPENVIDEO_RELEASE_NOTES_INVALID: $Path - $($errors -join '; ')"
    }
    $normalized = [string[]]@($notes | ForEach-Object { Get-OpenVideoNormalizedNoteText $_ })
    return [pscustomobject]@{
        Summary = (Get-OpenVideoNormalizedNoteText $summary)
        Notes = $normalized
    }
}
