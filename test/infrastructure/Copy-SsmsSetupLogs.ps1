function Copy-SsmsSetupLogs {
    param(
        [Parameter(Mandatory = $true)][string[]]$Roots,
        [Parameter(Mandatory = $true)][string]$Destination,
        [Parameter(Mandatory = $true)][datetime]$SinceUtc,
        [switch]$Recurse
    )

    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    $files = @()
    $seen = @{}
    foreach ($root in $Roots) {
        if ([string]::IsNullOrWhiteSpace($root) -or -not (Test-Path -LiteralPath $root -PathType Container)) {
            continue
        }
        $rootPath = (Resolve-Path -LiteralPath $root).Path
        $label = 'root-{0:D2}' -f ($files.Count + 1)
        $copied = @()
        foreach ($file in @(Get-ChildItem -LiteralPath $rootPath -File -Recurse:$Recurse -ErrorAction Stop |
            Where-Object {
                $_.LastWriteTimeUtc -ge $SinceUtc -and
                $_.Name -match '(?i)^(dd_.*|vs_.*|ssms_.*|.*precheck.*|.*bootstrapper.*|.*setup.*)\.(log|txt|json)$'
            })) {
            if ($seen.ContainsKey($file.FullName)) { continue }
            $seen[$file.FullName] = $true
            $relative = $file.FullName.Substring($rootPath.TrimEnd('\', '/').Length).TrimStart('\', '/')
            $target = Join-Path (Join-Path $Destination $label) $relative
            New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
            Copy-Item -LiteralPath $file.FullName -Destination $target -Force -ErrorAction Stop
            $copied += [pscustomobject]@{ Source = $file.FullName; Artifact = $target; LastWriteTimeUtc = $file.LastWriteTimeUtc }
        }
        $files += [pscustomobject]@{ Root = $rootPath; Files = $copied }
    }
    return $files
}
