<#
This script helps locate the Convene History URL for the game "Wuthering Waves".
It searches various locations on your system to find the game installation directory
and then looks for the log files containing the Convene History URL.
If the URL is found, it copies it to your clipboard for easy access.

Note: If the script is unable to locate the URL automatically, it will prompt you
to manually enter the game installation path.

Disclaimer: This script may not work correctly if the game has been modified by
third-party tools or mods. If you encounter any issues, please join our Discord
server for assistance: https://discord.gg/DFKG4nqUD4
#>

Add-Type -AssemblyName System.Web

# Define registry paths to search
$registryPaths = @(
    "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
)

# Attempt to find the game installation path automatically
Write-Host "`n`nAttempting to locate the game installation directory..." -ForegroundColor Yellow
$gamePath = $null
$gachaLogPathExists = $false

# Search registry entries for game installation path
foreach ($regPath in $registryPaths) {
    try {
        $installedEntry = Get-ItemProperty -Path $regPath | Where-Object { $_.DisplayName -like "*wuthering*" }
        if ($installedEntry) {
            $gamePath = $installedEntry.InstallPath
            if (Test-Path ($gamePath + '\Client\Saved\Logs\Client.log')) {
                $gachaLogPathExists = $true
                break
            }
        }
    }
    catch {
        # Continue searching other registry paths
    }
}

# Search MUI cache for game installation path
if (!$gachaLogPathExists) {
    $muiCachePath = "Registry::HKEY_CURRENT_USER\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\MuiCache"
    $filteredEntries = (Get-ItemProperty -Path $muiCachePath).PSObject.Properties | Where-Object { $_.Value -like "*wuthering*" } | Where-Object { $_.Name -like "*client-win64-shipping.exe*" }
    if ($filteredEntries.Count -ne 0) {
        $gamePath = ($filteredEntries[0].Name -split '\\client\\')[0]
        if (Test-Path ($gamePath + '\Client\Saved\Logs\Client.log')) {
            $gachaLogPathExists = $true
        }
    }
}

# Search firewall rules for game installation path
if (!$gachaLogPathExists) {
    $firewallPath = "Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy\FirewallRules"
    $filteredEntries = (Get-ItemProperty -Path $firewallPath).PSObject.Properties | Where-Object { $_.Value -like "*wuthering*" } | Where-Object { $_.Name -like "*client-win64-shipping*" }
    if ($filteredEntries.Count -ne 0) {
        $gamePath = (($filteredEntries[0].Value -split 'App=')[1] -split '\\client\\')[0]
        if (Test-Path ($gamePath + '\Client\Saved\Logs\Client.log')) {
            $gachaLogPathExists = $true
        }
    }
}

# Search common installation paths
if (!$gachaLogPathExists) {
    $diskLetters = (Get-PSDrive).Name -match '^[a-z]$'
    foreach ($diskLetter in $diskLetters) {
        $commonPaths = @(
            "$diskLetter`:\Wuthering Waves Game",
            "$diskLetter`:\Wuthering Waves\Wuthering Waves Game",
            "$diskLetter`:\Program Files\Epic Games\WutheringWavesj3oFh\Wuthering Waves Game",
            "$diskLetter`:\SteamLibrary\steamapps\common\Wuthering Waves"
        )

        foreach ($path in $commonPaths) {
            if (Test-Path ($path + '\Client\Saved\Logs\Client.log')) {
                $gamePath = $path
                $gachaLogPathExists = $true
                break
            }
        }

        if ($gachaLogPathExists) {
            break
        }
    }
}

# Prompt user for manual input if game installation path not found
while (!$gachaLogPathExists) {
    Write-Host "Game installation directory not found or log files missing. Please enter the game installation path or join our Discord server for assistance: https://discord.gg/DFKG4nqUD4"
    Write-Host "Common installation paths:" -ForegroundColor Yellow
    Write-Host "  C:\Wuthering Waves"
    Write-Host "  C:\Wuthering Waves\Wuthering Waves Game"
    Write-Host "  C:\Program Files\Epic Games\WutheringWavesj3oFh"
    $manualPath = Read-Host "Path"

    if ($manualPath) {
        $gamePath = $manualPath
        if (Test-Path ($gamePath + '\Client\Saved\Logs\Client.log')) {
            $gachaLogPathExists = $true
        }
        else {
            Write-Host "Could not find log files in the specified path. Please try again or join our Discord server for assistance." -ForegroundColor Red
        }
    }
    else {
        Write-Host "Invalid path entered. Please try again or join our Discord server for assistance." -ForegroundColor Red
    }
}

# Define log file paths
$gachaLogPath = $gamePath + '\Client\Saved\Logs\Client.log'

# Search for Convene History URL in log files
$gachaUrlEntry = $null

if (Test-Path $gachaLogPath) {
    $gachaUrlEntry = Get-Content $gachaLogPath | Select-String -Pattern "https://aki-gm-resources-oversea\.aki-game\.(net|com)" | Select-Object -Last 1
}

# Determine which URL to use and copy to clipboard
if ($gachaUrlEntry) {
    if ($gachaUrlEntry) {
        $urlToCopy = $gachaUrlEntry -replace '.*?(https://aki-gm-resources-oversea\.aki-game\.(net|com)[^"]*).*', '$1'
    }

    if ([string]::IsNullOrWhiteSpace($urlToCopy)) {
        Write-Host "`nConvene History URL not found in the log files. Please ensure that Convene History is open in game" -ForegroundColor Red
    }
    else {
        Write-Host "`nThe Convene History URL was found inside the game's log file:"
        Write-Host "$gachaLogPath" -ForegroundColor Cyan

        Write-Host "`nConvene History URL:"
        Write-Host "$urlToCopy" -ForegroundColor Cyan
        Set-Clipboard $urlToCopy
        Write-Host "`nURL copied to clipboard. You can now paste it into https://trackmypulls.com/en/wuwa/tracker/import and click the 'Import' button." -ForegroundColor Green
    }
}
else {
    Write-Host "`nConvene History URL not found in the log files. Please ensure that Convene History is open in game." -ForegroundColor Red
}

Write-Host "`n"
