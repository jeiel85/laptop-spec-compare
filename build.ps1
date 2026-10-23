# Builds index.html (the GitHub Pages page) from spec-compare.html and zips the whole project.
#   index.html, .nojekyll       served by GitHub Pages from the repository root
#   laptop-spec-compare.zip     this folder, to move to another PC (unzip it and push it as the repository)
# Run:  powershell -ExecutionPolicy Bypass -File .\build.ps1
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$zipName = 'laptop-spec-compare.zip'
$utf8 = New-Object System.Text.UTF8Encoding $false

# spec-compare.html is written as an Artifact page: <title>, links and <style> first, then the body.
$page = [IO.File]::ReadAllText((Join-Path $root 'spec-compare.html'), [Text.Encoding]::UTF8)
$cut = $page.IndexOf('</style>')
if ($cut -lt 0) { throw 'spec-compare.html has no </style>' }
$cut += '</style>'.Length
$head = $page.Substring(0, $cut).Trim()
$body = $page.Substring($cut).Trim()

$doc = @"
<!doctype html>
<html lang="ko">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<style>:root{padding-top:env(safe-area-inset-top,0px);padding-bottom:env(safe-area-inset-bottom,0px)}body{margin:0}img{max-width:100%}[hidden]{display:none!important}</style>
$head
</head>
<body>
$body
</body>
</html>
"@

[IO.File]::WriteAllText((Join-Path $root 'index.html'), $doc, $utf8)
[IO.File]::WriteAllText((Join-Path $root '.nojekyll'), '', $utf8)

# Zip everything except the zip itself and local-only folders.
$skip = @($zipName, '.git', '.claude', 'dist')
$zip = Join-Path $root $zipName
if (Test-Path $zip) { Remove-Item $zip -Force }
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::Open($zip, 'Create')
try {
    Get-ChildItem $root -Recurse -File -Force | ForEach-Object {
        $rel = $_.FullName.Substring($root.Length).TrimStart('\', '/')
        $top = ($rel -split '[\\/]')[0]
        if ($skip -notcontains $top) {
            [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $_.FullName, $rel.Replace('\', '/')) | Out-Null
        }
    }
} finally {
    $archive.Dispose()
}
Write-Host "Built: $(Join-Path $root 'index.html')"
Write-Host "Zip:   $zip"
