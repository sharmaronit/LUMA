<#
.SYNOPSIS
  Luma TV debloater - disables bloatware, ads and telemetry on Android TV,
  Google TV, Xiaomi PatchWall and Fire TV devices over ADB. Fully reversible.

.EXAMPLE
  .\debloat.ps1 -Ip 192.168.1.50 -DryRun
  .\debloat.ps1 -Ip 192.168.1.50
  .\debloat.ps1 -Aggressive -SetLauncher -DisableStockLauncher -Compile
  .\debloat.ps1 -Restore .\backups\MIBOX4-20261111-153000.actions
#>
[CmdletBinding()]
param(
    [string]$Ip,
    [string]$AdbPath = 'adb',
    [ValidateSet('auto', 'google-tv', 'android-tv-stock', 'xiaomi-patchwall', 'fire-tv')]
    [string]$Device = 'auto',
    [switch]$Aggressive,
    [switch]$Uninstall,
    [switch]$DryRun,
    [switch]$SetLauncher,
    [switch]$DisableStockLauncher,
    [switch]$FastAnimations,
    [switch]$Compile,
    [switch]$Reboot,
    [string]$Restore,
    [string]$LumaPackage = 'app.luma.tvlauncher',
    [string]$LumaActivity = 'app.luma.tvlauncher.MainActivity',
    [switch]$Yes
)

$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ListDir = Join-Path $ScriptDir 'lists'
$BackupDir = Join-Path $ScriptDir 'backups'

$script:AdbArgs = @()

function Write-Status([string]$Tag, [string]$Message) {
    $color = switch ($Tag) {
        'OK' { 'Green' } 'FAIL' { 'Red' } 'SKIP' { 'DarkGray' } 'DRY' { 'Cyan' } 'WARN' { 'Yellow' } default { 'White' }
    }
    Write-Host ('[{0,-4}] ' -f $Tag) -ForegroundColor $color -NoNewline
    Write-Host $Message
}

function Invoke-Adb {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
    $all = @($script:AdbArgs) + @($Arguments)
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $out = & $AdbPath @all 2>&1 | ForEach-Object { "$_".TrimEnd("`r") }
    } finally {
        $ErrorActionPreference = $prev
    }
    return (@($out) -join "`n").Trim()
}

function Invoke-Shell([string]$Command) { return Invoke-Adb 'shell' $Command }

function Test-Failure([string]$Output) {
    return ($Output -match '(?i)(failure|exception|error|not allowed|cannot|unknown package)')
}

function Read-PackageList([string[]]$Files) {
    $entries = @()
    foreach ($f in $Files) {
        $path = Join-Path $ListDir $f
        if (-not (Test-Path $path)) { continue }
        foreach ($line in Get-Content $path) {
            $t = $line.Trim()
            if ($t -eq '' -or $t.StartsWith('#')) { continue }
            $parts = $t.Split('|', 3)
            if ($parts.Count -lt 2) { continue }
            $desc = if ($parts.Count -ge 3) { $parts[2].Trim() } else { '' }
            $entries += [pscustomobject]@{ Tier = $parts[0].Trim(); Package = $parts[1].Trim(); Desc = $desc; Source = $f }
        }
    }
    return $entries
}

function Get-InstalledPackages {
    $raw = Invoke-Shell 'pm list packages'
    $set = @{}
    foreach ($l in $raw -split "`n") {
        if ($l -match '^package:(.+)$') { $set[$Matches[1].Trim()] = $true }
    }
    return $set
}

function Connect-Device {
    if (-not (Get-Command $AdbPath -ErrorAction SilentlyContinue)) {
        throw "adb not found. Install Android platform-tools and add it to PATH, or pass -AdbPath C:\path\to\adb.exe"
    }
    if (-not $Ip -and -not $Yes) {
        $usb = @((Invoke-Adb 'devices') -split "`n" | Where-Object { $_ -match "`tdevice$" })
        if ($usb.Count -eq 0) {
            $Ip = (Read-Host 'Enter your TV IP address (Settings > Network on the TV)').Trim()
            if (-not $Ip) { throw 'No TV IP address given.' }
            $script:Ip = $Ip
        }
    }
    if ($Ip) {
        $target = if ($Ip -match ':') { $Ip } else { "${Ip}:5555" }
        Write-Status 'INFO' "Connecting to $target (accept the prompt on the TV if one appears)..."
        Write-Status 'INFO' (Invoke-Adb 'connect' $target)
        $script:AdbArgs = @('-s', $target)
    }
    $devices = @((Invoke-Adb 'devices') -split "`n" | Where-Object { $_ -match "`tdevice$" })
    if ($devices.Count -eq 0) { throw 'No authorised device found. Enable Developer options > USB/Network debugging on the TV.' }
    if (-not $Ip -and $devices.Count -gt 1) { throw 'More than one device connected. Pass -Ip to choose one.' }
}

# ---------------------------------------------------------------- restore
function Invoke-Restore([string]$File) {
    if (-not (Test-Path $File)) { throw "Backup file not found: $File" }
    Write-Status 'INFO' "Restoring from $File"
    foreach ($line in Get-Content $File) {
        $parts = $line.Trim().Split(' ')
        if ($parts.Count -lt 2) { continue }
        $action = $parts[0]; $pkg = $parts[1]
        if ($action -eq 'disabled') { $out = Invoke-Shell "pm enable $pkg" }
        elseif ($action -eq 'uninstalled') { $out = Invoke-Shell "cmd package install-existing $pkg" }
        else { continue }
        if (Test-Failure $out) { Write-Status 'FAIL' "$pkg  ($out)" } else { Write-Status 'OK' "restored $pkg" }
    }
}

# ---------------------------------------------------------------- main
Connect-Device

if ($Restore) { Invoke-Restore $Restore; exit 0 }

$manufacturer = Invoke-Shell 'getprop ro.product.manufacturer'
$model = Invoke-Shell 'getprop ro.product.model'
$sdk = Invoke-Shell 'getprop ro.build.version.sdk'
Write-Status 'INFO' "Device: $manufacturer $model (SDK $sdk)"

$installed = Get-InstalledPackages
if ($installed.Count -eq 0) { throw 'Could not read the package list from the device.' }

# Luma can be installed as a release, .profile or .debug build
$LumaBase = $LumaPackage
if (-not $PSBoundParameters.ContainsKey('LumaPackage') -and -not $installed.ContainsKey($LumaPackage)) {
    foreach ($v in "$LumaBase.profile", "$LumaBase.debug") {
        if ($installed.ContainsKey($v)) { $LumaPackage = $v; break }
    }
}
Write-Status 'INFO' ('Luma: ' + $(if ($installed.ContainsKey($LumaPackage)) { $LumaPackage } else { 'not installed' }))

$profiles = @()
if ($Device -eq 'auto') {
    if ($installed.ContainsKey('com.amazon.tv.launcher')) { $profiles += 'fire-tv' }
    if ($installed.ContainsKey('com.google.android.apps.tv.launcherx')) { $profiles += 'google-tv' }
    if ($installed.ContainsKey('com.mitv.tvhome') -or $installed.ContainsKey('com.mitv.tvhome.atv')) { $profiles += 'xiaomi-patchwall' }
    if ($installed.ContainsKey('com.google.android.tvlauncher') -or $installed.ContainsKey('com.google.android.leanbacklauncher') -or $profiles.Count -eq 0) { $profiles += 'android-tv-stock' }
} else {
    $profiles += $Device
}
Write-Status 'INFO' ("Profiles: common, " + ($profiles -join ', '))

$entries = Read-PackageList (@('common.txt') + ($profiles | ForEach-Object { "$_.txt" }))
$never = @{}
foreach ($v in $LumaPackage, $LumaBase, "$LumaBase.profile", "$LumaBase.debug") { $never[$v] = $true }
$entries | Where-Object { $_.Tier -eq 'never' } | ForEach-Object { $never[$_.Package] = $true }

$tiers = @('safe')
if ($Aggressive) { $tiers += 'aggressive' }
if ($DisableStockLauncher) {
    if (-not $installed.ContainsKey($LumaPackage)) {
        Write-Status 'WARN' "Luma ($LumaPackage) is not installed - refusing to disable the stock launcher."
    } else { $tiers += 'launcher' }
}

$seen = @{}
$targets = @()
foreach ($e in $entries) {
    if ($tiers -notcontains $e.Tier) { continue }
    if ($never.ContainsKey($e.Package) -or $seen.ContainsKey($e.Package)) { continue }
    $seen[$e.Package] = $true
    if ($installed.ContainsKey($e.Package)) { $targets += $e }
}

if ($targets.Count -eq 0) {
    Write-Status 'INFO' 'Nothing to remove for the selected tiers.'
} else {
    Write-Host ''
    Write-Status 'INFO' ("{0} package(s) will be {1}:" -f $targets.Count, $(if ($Uninstall) { 'uninstalled for user 0' } else { 'disabled' }))
    $targets | ForEach-Object { Write-Host ("        {0,-11} {1,-55} {2}" -f $_.Tier, $_.Package, $_.Desc) }
    Write-Host ''
}

if ($DryRun) {
    if ($SetLauncher) { Write-Status 'DRY' "would set home activity to $LumaPackage/$LumaActivity" }
    if ($FastAnimations) { Write-Status 'DRY' 'would set animation scales to 0.5' }
    if ($Compile) { Write-Status 'DRY' "would compile $LumaPackage with -m speed" }
    Write-Status 'DRY' 'Dry run only - no changes made.'
    exit 0
}

if (-not $Yes -and $targets.Count -gt 0) {
    $answer = Read-Host 'Continue? [y/N]'
    if ($answer -notmatch '^(y|yes)$') { Write-Status 'INFO' 'Aborted.'; exit 1 }
}

# backup
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
$safeModel = ($model -replace '[^A-Za-z0-9_-]', '_')
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$snapshot = Join-Path $BackupDir "$safeModel-$stamp.snapshot.txt"
$actions = Join-Path $BackupDir "$safeModel-$stamp.actions"
@(
    "# $manufacturer $model SDK $sdk  $stamp",
    '# --- disabled before run ---',
    (Invoke-Shell 'pm list packages -d'),
    '# --- all packages (incl. uninstalled for user) ---',
    (Invoke-Shell 'pm list packages -u')
) | Set-Content -Encoding utf8 $snapshot
New-Item -ItemType File -Force -Path $actions | Out-Null
Write-Status 'OK' "Backup saved: $snapshot"

$done = 0; $failed = 0
foreach ($t in $targets) {
    if ($Uninstall) {
        $out = Invoke-Shell "pm uninstall -k --user 0 $($t.Package)"
        $ok = ($out -match 'Success')
        $verb = 'uninstalled'
    } else {
        $out = Invoke-Shell "pm disable-user --user 0 $($t.Package)"
        $ok = ($out -match 'disabled') -and -not (Test-Failure $out)
        $verb = 'disabled'
    }
    if ($ok) {
        [System.IO.File]::AppendAllText($actions, "$verb $($t.Package)`n", (New-Object System.Text.UTF8Encoding $false))
        Write-Status 'OK' "$verb $($t.Package)"
        $done++
    } else {
        $hint = if (-not $Uninstall) { '  (try -Uninstall for this device)' } else { '' }
        Write-Status 'FAIL' "$($t.Package): $out$hint"
        $failed++
    }
}

if ($SetLauncher) {
    if (-not $installed.ContainsKey($LumaPackage)) {
        Write-Status 'WARN' "Luma ($LumaPackage) is not installed - skipping -SetLauncher."
    } else {
        $out = Invoke-Shell "cmd package set-home-activity $LumaPackage/$LumaActivity"
        if (Test-Failure $out) { Write-Status 'FAIL' "set-home-activity: $out  (use -DisableStockLauncher instead)" }
        else { Write-Status 'OK' 'Luma set as home app' }
    }
}

if ($FastAnimations) {
    foreach ($k in 'window_animation_scale', 'transition_animation_scale', 'animator_duration_scale') {
        Invoke-Shell "settings put global $k 0.5" | Out-Null
    }
    Write-Status 'OK' 'Animation scales set to 0.5 (restore with 1.0 in Developer options)'
}

if ($Compile) {
    if ($installed.ContainsKey($LumaPackage)) {
        Write-Status 'INFO' "Compiling $LumaPackage (can take a minute)..."
        $out = Invoke-Shell "cmd package compile -m speed -f $LumaPackage"
        if ($out -match 'Success') { Write-Status 'OK' 'Luma compiled for speed' } else { Write-Status 'FAIL' "compile: $out" }
    } else { Write-Status 'WARN' "Luma ($LumaPackage) not installed - skipping -Compile." }
}

Write-Host ''
Write-Status 'INFO' "Done: $done changed, $failed failed."
Write-Status 'INFO' "Undo any time:  .\debloat.ps1 -Restore `"$actions`""

if ($Reboot) { Write-Status 'INFO' 'Rebooting...'; Invoke-Adb 'reboot' | Out-Null }
else { Write-Status 'INFO' 'Reboot the TV to free the memory those apps were using.' }
