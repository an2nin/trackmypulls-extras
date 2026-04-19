<#
.SYNOPSIS
Extracts the latest token value from PlatformProcess cache data_1.

.DESCRIPTION
Copies %LocalAppData%\PlatformProcess\Cache\data_1 to a temporary file,
reads the copy from the end to find the latest token occurrence,
outputs the token, optionally copies it to clipboard, then removes the temp copy.

.EXAMPLE
powershell -ExecutionPolicy Bypass -File .\endfield.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

function Write-Banner {
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Arknights Endfield Token Extractor" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
}

function Copy-ToClipboard {
    param([string]$Text)

    function Test-ExternalClipboardCopy {
        param(
            [string]$CommandName,
            [string[]]$Arguments
        )

        $command = Get-Command $CommandName -ErrorAction SilentlyContinue
        if ($null -eq $command) {
            return $false
        }

        try {
            $Text | & $command.Source @Arguments
            return (($null -eq $LASTEXITCODE) -or ($LASTEXITCODE -eq 0))
        }
        catch {
            return $false
        }
    }

    if ($IsLinux) {
        if (Test-ExternalClipboardCopy -CommandName "wl-copy" -Arguments @()) { return $true }
        if (Test-ExternalClipboardCopy -CommandName "xclip" -Arguments @("-selection", "clipboard")) { return $true }
        if (Test-ExternalClipboardCopy -CommandName "xsel" -Arguments @("--clipboard", "--input")) { return $true }
        return $false
    }

    if ($IsMacOS) {
        if (Test-ExternalClipboardCopy -CommandName "pbcopy" -Arguments @()) { return $true }
    }

    if ($IsWindows) {
        if (Test-ExternalClipboardCopy -CommandName "clip" -Arguments @()) { return $true }
    }

    try {
        Set-Clipboard -Value $Text -ErrorAction Stop
        return $true
    }
    catch {
        return $false
    }
}

function Get-LatestTokenValue {
    param([string]$Content)

    # Search from the end so we prefer the newest token occurrence.
    $patterns = @(
        '[?&]token=(?<value>[^&#\s"<>]+)',
        '"token"\s*:\s*"(?<value>[^"\\]+(?:\\.[^"\\]*)*)"',
        'token\s*[:=]\s*"(?<value>[^"\\]+(?:\\.[^"\\]*)*)"',
        'token\s*[:=]\s*(?<value>[A-Za-z0-9%._\-+/=]{10,})'
    )

    $bestMatch = $null
    $bestIndex = -1

    foreach ($pattern in $patterns) {
        $tokenMatches = [regex]::Matches(
            $Content,
            $pattern,
            [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
        )

        foreach ($match in $tokenMatches) {
            if ($match.Success -and -not [string]::IsNullOrWhiteSpace($match.Groups['value'].Value)) {
                if ($match.Index -gt $bestIndex) {
                    $bestIndex = $match.Index
                    $bestMatch = $match.Groups['value'].Value
                }
            }
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($bestMatch)) {
        $normalizedToken = [System.Text.RegularExpressions.Regex]::Unescape($bestMatch)

        # URL query tokens are usually percent-encoded; decode when it looks encoded.
        if ($normalizedToken -match '%[0-9A-Fa-f]{2}') {
            try {
                $normalizedToken = [Uri]::UnescapeDataString($normalizedToken)
            }
            catch {
                # Keep original token if decoding fails.
            }
        }

        return $normalizedToken
    }

    return $null
}

Write-Banner

$cacheDirectory = Join-Path $env:LOCALAPPDATA "PlatformProcess\Cache"
$sourcePath = Join-Path $cacheDirectory "data_1"
$tempPath = $null

if (-not (Test-Path -LiteralPath $sourcePath)) {
    Write-Host "data_1 was not found." -ForegroundColor Red
    Write-Host "Checked path: $sourcePath" -ForegroundColor Yellow
    return
}

try {
    $tempPath = Join-Path $cacheDirectory ("data_1.copy.{0}.tmp" -f [guid]::NewGuid().ToString('N'))
    Copy-Item -LiteralPath $sourcePath -Destination $tempPath -Force

    Write-Host "Copied data_1 to a temporary file." -ForegroundColor Green
    Write-Host "Reading temporary file and scanning from the end..." -ForegroundColor Cyan

    # Read bytes first to tolerate files that are not strictly text.
    $bytes = [System.IO.File]::ReadAllBytes($tempPath)
    $content = [System.Text.Encoding]::UTF8.GetString($bytes)

    $token = Get-LatestTokenValue -Content $content
    if ([string]::IsNullOrWhiteSpace($token)) {
        Write-Host "No token value was found in data_1." -ForegroundColor Red
        return
    }

    Write-Host ""
    Write-Host "Latest token value:" -ForegroundColor White
    Write-Host $token -ForegroundColor Cyan
    Write-Host ""

    if (Copy-ToClipboard -Text $token) {
        Write-Host "Token copied to clipboard." -ForegroundColor Green
    }
    else {
        Write-Host "Could not copy token to clipboard. Copy it manually from above." -ForegroundColor Yellow
    }
}
catch {
    Write-Host "Token extraction failed." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
}
finally {
    if (-not [string]::IsNullOrWhiteSpace($tempPath) -and (Test-Path -LiteralPath $tempPath)) {
        Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        Write-Host "Temporary copy deleted." -ForegroundColor DarkGray
    }
}

Write-Host ""
