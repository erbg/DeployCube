function Assert-NativeDeployCube {
    param([Parameter(Mandatory = $true)][string]$RepositoryRoot)

    if ($PSVersionTable.PSEdition -ne 'Core' -or $PSVersionTable.PSVersion.Major -ne 7) {
        throw 'DeployCube integration must execute in PowerShell 7 Core.'
    }

    $modulePath = (Resolve-Path (Join-Path $RepositoryRoot 'DeployCube/DeployCube.psm1')).Path
    foreach ($name in @('Publish-Cube', 'Unpublish-Cube')) {
        $command = Get-Command -Name $name -ErrorAction Stop
        $expectedSource = (Resolve-Path (Join-Path $RepositoryRoot "DeployCube/public/$name.ps1")).Path
        if ($command.CommandType -ne 'Function' -or
            -not $command.Module -or
            -not [string]::Equals($command.Module.Path, $modulePath, [StringComparison]::OrdinalIgnoreCase) -or
            -not [string]::Equals($command.ScriptBlock.File, $expectedSource, [StringComparison]::OrdinalIgnoreCase)) {
            throw "$name is not the in-process DeployCube function from '$expectedSource'."
        }
    }
}
