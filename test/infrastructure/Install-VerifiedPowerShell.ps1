[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('7.4.22', '7.5.13')]
    [string]$Version
)

$ErrorActionPreference = 'Stop'
$expectedHashes = @{
    '7.4.22' = '5f89f51860a1a3b07937945663afd7cbd44387361ff9985f5758939cb9bd6359'
    '7.5.13' = '120b8f0b04f3b3f6e8c351ddbe568bf596cdca15eeb2ecb7e724060051a36d65'
}
$archiveName = "PowerShell-$Version-win-x64.zip"
$archivePath = Join-Path $env:RUNNER_TEMP $archiveName
$downloadUri = "https://github.com/PowerShell/PowerShell/releases/download/v$Version/$archiveName"
Invoke-WebRequest -Uri $downloadUri -OutFile $archivePath -ErrorAction Stop

$actualHash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actualHash -ne $expectedHashes[$Version]) {
    throw "PowerShell $Version archive SHA-256 mismatch: $actualHash"
}

$installPath = Join-Path $env:RUNNER_TEMP "pwsh-$Version"
New-Item -ItemType Directory -Path $installPath -Force | Out-Null
Expand-Archive -LiteralPath $archivePath -DestinationPath $installPath -Force
$executable = Join-Path $installPath 'pwsh.exe'
$actualVersion = & $executable -NoLogo -NoProfile -Command '$PSVersionTable.PSVersion.ToString()'
if ($LASTEXITCODE -ne 0 -or $actualVersion -ne $Version) {
    throw "Expected PowerShell $Version; found '$actualVersion'."
}

"POWERSHELL_EXE=$executable" | Add-Content -LiteralPath $env:GITHUB_ENV
Write-Host "Verified PowerShell $actualVersion ($actualHash)"
