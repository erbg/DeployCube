[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$OutputDirectory,
    [Parameter(Mandatory = $true)][ValidateSet('Before', 'After')][string]$Phase,
    [string]$InstallerTempDirectory
)

$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$OutputDirectory = (Resolve-Path -LiteralPath $OutputDirectory).Path
. (Join-Path $PSScriptRoot 'Copy-SsmsSetupLogs.ps1')
$startPath = Join-Path $OutputDirectory 'installation-start.txt'
$errors = [System.Collections.Generic.List[string]]::new()
if ($Phase -eq 'Before') {
    [datetime]::UtcNow.ToString('o') | Set-Content -LiteralPath $startPath -Encoding ASCII
}

$inventory = [ordered]@{
    CollectedAtUtc = [datetime]::UtcNow.ToString('o')
    Phase = $Phase
    Temp = $env:TEMP
    Tmp = $env:TMP
    RunnerTemp = $env:RUNNER_TEMP
    InstallerTempDirectory = $InstallerTempDirectory
    OperatingSystem = [Environment]::OSVersion.VersionString
    Is64BitOperatingSystem = [Environment]::Is64BitOperatingSystem
    Identity = $null
    IsAdministrator = $null
    SystemDriveFreeBytes = $null
    RunnerTempAccess = $null
    VswherePath = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
    VswhereExitCode = $null
    VisualStudioInstances = $null
    InstallerProcesses = @()
    Errors = $errors
}
try {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $inventory.Identity = $identity.Name
    $inventory.IsAdministrator = ([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
    $inventory.SystemDriveFreeBytes = ([System.IO.DriveInfo]::new($env:SystemDrive + '\')).AvailableFreeSpace
    $inventory.RunnerTempAccess = @(Get-Acl -LiteralPath $env:RUNNER_TEMP -ErrorAction Stop |
        Select-Object -ExpandProperty Access | Select-Object IdentityReference, FileSystemRights, AccessControlType, IsInherited)
}
catch { $errors.Add("Installer prerequisites: $($_.Exception.Message)") }
try {
    if (Test-Path -LiteralPath $inventory.VswherePath -PathType Leaf) {
        $instances = & $inventory.VswherePath -all -prerelease -products '*' -format json -utf8
        $inventory.VswhereExitCode = $LASTEXITCODE
        if ($LASTEXITCODE -ne 0) { throw "vswhere failed with exit code $LASTEXITCODE." }
        $inventory.VisualStudioInstances = @($instances | ConvertFrom-Json -ErrorAction Stop)
    }
    else {
        $inventory.VisualStudioInstances = 'vswhere not installed'
    }
}
catch { $errors.Add("Visual Studio inventory: $($_.Exception.Message)") }
try {
    $inventory.InstallerProcesses = @(Get-Process -ErrorAction Stop |
        Where-Object { $_.ProcessName -match '(?i)^(vs_.*|setup|msiexec)$' } |
        Select-Object ProcessName, Id, Path)
}
catch { $errors.Add("Installer processes: $($_.Exception.Message)") }

if ($Phase -eq 'After') {
    $since = [datetime]::UtcNow.AddHours(-1)
    try {
        if (-not (Test-Path -LiteralPath $startPath -PathType Leaf)) {
            throw 'Installation start marker is missing; cannot select logs from this attempt.'
        }
        $since = [datetime]::Parse((Get-Content -LiteralPath $startPath -Raw).Trim()).ToUniversalTime().AddMinutes(-5)
    }
    catch { $errors.Add("Installation start marker: $($_.Exception.Message)") }
    $roots = @(
        @{ Name = 'installer-temp'; Path = $InstallerTempDirectory; Recurse = $true }
        @{ Name = 'user-temp'; Path = $env:TEMP; Recurse = $false }
        @{ Name = 'user-tmp'; Path = $env:TMP; Recurse = $false }
        @{ Name = 'runner-temp'; Path = $env:RUNNER_TEMP; Recurse = $false }
        @{ Name = 'windows-temp'; Path = (Join-Path $env:SystemRoot 'Temp'); Recurse = $false }
        @{ Name = 'program-data'; Path = (Join-Path $env:ProgramData 'Microsoft/VisualStudio/Setup'); Recurse = $true }
        @{ Name = 'local-app-data'; Path = (Join-Path $env:LOCALAPPDATA 'Microsoft/VisualStudio/Setup'); Recurse = $true }
        @{ Name = 'installer-logs'; Path = (Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/Logs'); Recurse = $true }
    )
    $copied = @()
    foreach ($root in $roots) {
        try {
            if (-not [string]::IsNullOrWhiteSpace($root.Path)) {
                $copied += @(Copy-SsmsSetupLogs -Roots @($root.Path) `
                    -Destination (Join-Path $OutputDirectory "setup-logs/$($root.Name)") `
                    -SinceUtc $since -Recurse:$root.Recurse)
            }
        }
        catch { $errors.Add("Setup logs $($root.Name): $($_.Exception.Message)") }
    }
    $copied | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $OutputDirectory 'setup-log-inventory.json') -Encoding UTF8

    $channels = @('Application', 'System', 'Microsoft-VisualStudio-Setup/Operational')
    try {
        $channels += @(Get-WinEvent -ListLog '*VisualStudio*' -ErrorAction Stop | Select-Object -ExpandProperty LogName)
    }
    catch {
        if ($_.FullyQualifiedErrorId -notmatch 'NoMatchingLogsFound') {
            $errors.Add("Visual Studio event log discovery: $($_.Exception.Message)")
        }
    }
    foreach ($channel in @($channels | Select-Object -Unique)) {
        try {
            $log = Get-WinEvent -ListLog $channel -ErrorAction Stop
            if (-not $log.IsEnabled) { continue }
            $events = @(Get-WinEvent -FilterHashtable @{ LogName = $channel; StartTime = $since.ToLocalTime() } -MaxEvents 2000 -ErrorAction Stop |
                Where-Object {
                    $_.ProviderName -match '(?i)visual.?studio|\.NET Runtime|Application Error|Windows Error Reporting|MsiInstaller|Service Control Manager' -or
                    $_.Message -match '(?i)vs_setup|visual studio installer|ssms'
                } |
                Select-Object TimeCreated, ProviderName, Id, LevelDisplayName, Message)
            $filename = $channel.Replace('/', '-')
            $events | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $OutputDirectory "events-$filename.json") -Encoding UTF8
        }
        catch {
            if ($_.FullyQualifiedErrorId -notmatch 'NoMatchingEventsFound|NoMatchingLogsFound') {
                $errors.Add("Event log ${channel}: $($_.Exception.Message)")
            }
        }
    }
}
$inventory | ConvertTo-Json -Depth 12 |
    Set-Content -LiteralPath (Join-Path $OutputDirectory "visual-studio-$Phase.json") -Encoding UTF8
if ($errors.Count -gt 0) {
    throw "SSMS installer diagnostic collection had $($errors.Count) error(s); see visual-studio-$Phase.json."
}
