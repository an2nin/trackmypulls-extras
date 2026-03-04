<#
.SYNOPSIS
Extracts the latest Arknights Endfield gacha URL from HGWebview.log for TrackMyPulls import.

.DESCRIPTION
Reads the Endfield webview log, finds the latest character history URL, and optionally attaches
the latest weapon token as u8_token_weapon. The resulting URL is copied to clipboard.

.PARAMETER LogPath
Path to HGWebview.log. Defaults to the standard Windows location, or a Heroic path on Linux.

.PARAMETER HostName
Expected webview host. Keep default unless the game host changes.

.PARAMETER SkipValidation
Skips the lightweight API reachability check.

.EXAMPLE
powershell -ExecutionPolicy Bypass -File .\endfield.ps1

.EXAMPLE
powershell -ExecutionPolicy Bypass -File .\endfield.ps1 -SkipValidation
#>
[CmdletBinding()]
param(
    [string]$LogPath,
    [string]$HostName = "ef-webview.gryphline.com",
    [switch]$SkipValidation
)

$ErrorActionPreference = "Stop"

try {
    # Needed for ParseQueryString on both Windows PowerShell and PowerShell 7.
    Add-Type -AssemblyName System.Web
}
catch {
    Write-Host "Failed to load System.Web assembly. Cannot parse query parameters." -ForegroundColor Red
    return
}

function Write-Banner {
    # Friendly output header for terminal users.
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Endfield Record URL Helper" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
}

function Get-DefaultLogPath {
    if ($IsLinux) {
        $linuxUser = $env:USERNAME
        if ([string]::IsNullOrWhiteSpace($linuxUser)) {
            $linuxUser = $env:USER
        }
        if ([string]::IsNullOrWhiteSpace($linuxUser)) {
            $linuxUser = "steamuser"
        }

        return "$env:HOME/Games/Heroic/Prefixes/default/Arknights Endfield/drive_c/users/$linuxUser/AppData/LocalLow/Gryphline/Endfield/sdklogs/HGWebview.log"
    }

    return "$env:USERPROFILE\AppData\LocalLow\Gryphline\Endfield\sdklogs\HGWebview.log"
}

function Resolve-LogPath {
    param([string]$Path)

    # Keep prompting until a valid file exists or user opts out.
    $resolvedPath = $Path
    while (-not (Test-Path -LiteralPath $resolvedPath)) {
        Write-Host "Log file not found." -ForegroundColor Red
        Write-Host "Checked path: $resolvedPath" -ForegroundColor Yellow
        Write-Host "Enter a different HGWebview.log path, or press Enter to exit." -ForegroundColor Yellow
        $manualPath = Read-Host "Path"

        if ([string]::IsNullOrWhiteSpace($manualPath)) {
            return $null
        }

        $resolvedPath = $manualPath.Trim('"')
    }

    return $resolvedPath
}

function Copy-ToClipboard {
    param([string]$Text)

    function Try-ExternalClipboardCopy {
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
            # External clipboard tools return non-zero on failure (for example missing display/session).
            return (($null -eq $LASTEXITCODE) -or ($LASTEXITCODE -eq 0))
        }
        catch {
            return $false
        }
    }

    if ($IsLinux) {
        # Do not use Set-Clipboard on Linux: in Wayland it can silently no-op.
        if (Try-ExternalClipboardCopy -CommandName "wl-copy" -Arguments @()) {
            return $true
        }

        if (Try-ExternalClipboardCopy -CommandName "xclip" -Arguments @("-selection", "clipboard")) {
            return $true
        }

        if (Try-ExternalClipboardCopy -CommandName "xsel" -Arguments @("--clipboard", "--input")) {
            return $true
        }

        return $false
    }

    if ($IsMacOS) {
        if (Try-ExternalClipboardCopy -CommandName "pbcopy" -Arguments @()) {
            return $true
        }
    }

    if ($IsWindows) {
        if (Try-ExternalClipboardCopy -CommandName "clip" -Arguments @()) {
            return $true
        }
    }

    try {
        Set-Clipboard -Value $Text -ErrorAction Stop
        return $true
    }
    catch {
        return $false
    }
}

function Read-LogContent {
    param([string]$Path)

    # Read once as raw text so regex can scan the full file efficiently.
    Write-Host "Log detected." -ForegroundColor Green
    Write-Host "Reading data..." -ForegroundColor Cyan
    Write-Host ""
    return Get-Content -LiteralPath $Path -Raw
}

function Get-LatestUrl {
    param(
        [string]$Content,
        [string]$Domain,
        [string]$Path
    )

    # Escape user-supplied pieces to avoid accidental regex meta behavior.
    $escapedDomain = [regex]::Escape($Domain)
    $escapedPath = [regex]::Escape($Path)
    # Match URL until common delimiters used in logs.
    $pattern = "https://$escapedDomain$escapedPath[^\s`"'<>\]]+"
    $matches = [regex]::Matches($Content, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

    if ($matches.Count -lt 1) {
        return $null
    }

    return $matches[$matches.Count - 1].Value
}

function Get-QueryParam {
    param(
        [string]$Url,
        [string]$Name
    )

    try {
        # Parse via Uri + query parser to handle encoded values safely.
        $uri = [Uri]$Url
        $query = [System.Web.HttpUtility]::ParseQueryString($uri.Query)
        return $query[$Name]
    }
    catch {
        return $null
    }
}

function Build-TrackerUrl {
    param(
        [string]$CharacterUrl,
        [string]$WeaponUrl
    )

    $charUri = [Uri]$CharacterUrl
    $builder = [System.UriBuilder]::new($charUri)
    $query = [System.Web.HttpUtility]::ParseQueryString($builder.Query)

    # Validate params required by the TrackMyPulls URL validator.
    $charToken = $query["u8_token"]
    if ([string]::IsNullOrWhiteSpace($charToken)) {
        throw "Character URL is missing required parameter: u8_token."
    }

    $serverId = $query["server"]
    if ([string]::IsNullOrWhiteSpace($serverId)) {
        throw "Character URL is missing required parameter: server."
    }

    $poolId = $query["pool_id"]
    if ([string]::IsNullOrWhiteSpace($poolId)) {
        throw "Character URL is missing required parameter: pool_id."
    }

    $lang = $query["lang"]
    if ([string]::IsNullOrWhiteSpace($lang)) {
        throw "Character URL is missing required parameter: lang."
    }

    $weaponToken = $null
    if (-not [string]::IsNullOrWhiteSpace($WeaponUrl)) {
        # Weapon token is optional but improves weapon banner import coverage.
        $weaponToken = Get-QueryParam -Url $WeaponUrl -Name "u8_token"
        if (-not [string]::IsNullOrWhiteSpace($weaponToken)) {
            $query["u8_token_weapon"] = $weaponToken
        }
    }

    $builder.Query = $query.ToString()

    return [PSCustomObject]@{
        Url         = $builder.Uri.AbsoluteUri
        ApiHost     = $charUri.Host
        Character   = $charToken
        Weapon      = $weaponToken
        ServerId    = $serverId
        HasWeapon   = -not [string]::IsNullOrWhiteSpace($weaponToken)
    }
}

function Test-ApiUrl {
    param(
        [string]$ApiHost,
        [string]$Token,
        [string]$ServerId
    )

    # Build an API URL to quickly verify token/server look usable.
    $apiBuilder = [System.UriBuilder]::new("https", $ApiHost)
    $apiBuilder.Path = "/api/record/char"

    $apiQuery = [System.Web.HttpUtility]::ParseQueryString("")
    $apiQuery["lang"] = "en-us"
    $apiQuery["pool_type"] = "E_CharacterGachaPoolType_Beginner"
    $apiQuery["token"] = $Token
    $apiQuery["server_id"] = $ServerId
    $apiBuilder.Query = $apiQuery.ToString()

    try {
        $response = Invoke-RestMethod -Uri $apiBuilder.Uri.AbsoluteUri -Method Get -TimeoutSec 10
        if ($null -ne $response -and $response.code -eq 0) {
            Write-Host "Validation: success (code 0)." -ForegroundColor Green
            return
        }

        $code = if ($null -ne $response) { $response.code } else { "unknown" }
        Write-Host "Validation: API responded with code $code." -ForegroundColor Yellow
    }
    catch {
        Write-Host "Validation skipped due to request failure. URL may still be usable." -ForegroundColor Yellow
    }
}

Write-Banner

$effectiveLogPath = $LogPath
if ([string]::IsNullOrWhiteSpace($effectiveLogPath)) {
    $effectiveLogPath = Get-DefaultLogPath
}

# Resolve path first so users can recover from custom install setups.
$resolvedLogPath = Resolve-LogPath -Path $effectiveLogPath
if ($null -eq $resolvedLogPath) {
    Write-Host "No valid log path provided. Exiting." -ForegroundColor Yellow
    return
}

$content = Read-LogContent -Path $resolvedLogPath
# Pull the latest entries for each banner type from the same log snapshot.
$characterUrl = Get-LatestUrl -Content $content -Domain $HostName -Path "/page/gacha_char"
$weaponUrl = Get-LatestUrl -Content $content -Domain $HostName -Path "/page/gacha_weapon"

if ([string]::IsNullOrWhiteSpace($characterUrl)) {
    Write-Host "Character gacha URL not found in log." -ForegroundColor Red
    Write-Host ""
    Write-Host "Quick checklist:" -ForegroundColor Yellow
    Write-Host "1. Launch the game." -ForegroundColor Yellow
    Write-Host "2. Open Headerhunting details from a character banner." -ForegroundColor Yellow
    Write-Host "3. Run this script again." -ForegroundColor Yellow
    return
}

try {
    $result = Build-TrackerUrl -CharacterUrl $characterUrl -WeaponUrl $weaponUrl
}
catch {
    Write-Host "Could not build TrackMyPulls URL." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    return
}

if (-not $SkipValidation) {
    # Validation is non-blocking; failures only warn and do not abort output.
    Write-Host "Running quick API check..." -ForegroundColor Cyan
    Test-ApiUrl -ApiHost $result.ApiHost -Token $result.Character -ServerId $result.ServerId
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Extraction complete" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Source log:" -ForegroundColor White
Write-Host $resolvedLogPath -ForegroundColor Gray
Write-Host ""
Write-Host "TrackMyPulls URL:" -ForegroundColor White
Write-Host $result.Url -ForegroundColor White
Write-Host ""

if (-not $result.HasWeapon) {
    Write-Host "Weapon token not found. Import still works, but weapon banner may need a rerun after opening weapon history once." -ForegroundColor Yellow
    Write-Host ""
}

if (Copy-ToClipboard -Text $result.Url) {
    Write-Host "URL copied to clipboard. Paste it into https://trackmypulls.com/en/endfield/tracker/import and click Import." -ForegroundColor Green
}
else {
    if ($IsLinux) {
        Write-Host "Could not copy to clipboard. Install one of: wl-clipboard (wl-copy), xclip, or xsel; then rerun this script." -ForegroundColor Yellow
    }
    else {
        Write-Host "Could not copy to clipboard. Copy the URL manually from above." -ForegroundColor Yellow
    }
}

Write-Host ""
