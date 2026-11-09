[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Tabular', 'Multidimensional')]
    [string]$Mode,

    [Parameter(Mandatory = $true)]
    [ValidateSet('7.4.22', '7.5.13')]
    [string]$ExpectedPowerShellVersion,

    [Parameter(Mandatory = $true)]
    [string]$LogDirectory,

    [Parameter(Mandatory = $true)]
    [string]$SourceReportPath,

    [ValidateSet('2022')]
    [string]$SsasVersion = '2022'
)

$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null
$LogDirectory = (Resolve-Path -LiteralPath $LogDirectory).Path
$reportPath = Join-Path $LogDirectory 'powershell7-integration-report.json'
$processingDirectoryName = if ($Mode -eq 'Tabular') { 'tabular-processing' } else { 'processing' }
$processingReportName = if ($Mode -eq 'Tabular') { 'tabular-processing-report.json' } else { 'processing-report.json' }
$processingDirectory = Join-Path $LogDirectory $processingDirectoryName
$processingReportPath = Join-Path $processingDirectory $processingReportName
$report = [ordered]@{
    Outcome = 'Failed'
    FailureClass = 'Infrastructure or installation problem'
    Error = $null
    RunUrl = "https://github.com/$env:GITHUB_REPOSITORY/actions/runs/$env:GITHUB_RUN_ID"
    ExecutionClassification = 'Unknown'
    PowerShell = $null
    DotNetRuntime = $null
    SqlServerModule = $null
    InvokeASCmd = $null
    AmoAssemblies = @()
    Ssas = $null
    DeploymentUtility = $null
    Authentication = $null
    Deployment = 'Not tested'
    Processing = 'Not tested'
    QueryVerification = 'Not tested'
    Cleanup = 'Not tested'
    ProcessingReportPath = $processingReportPath
}
$failureStage = 'PowerShell runtime validation'
$processingReport = $null
$server = $null

function Get-LoadedAmoAssemblies {
    @(
        [AppDomain]::CurrentDomain.GetAssemblies() |
            Where-Object { $_.GetName().Name -like 'Microsoft.AnalysisServices*' } |
            ForEach-Object {
                [pscustomobject]@{
                    Name = $_.GetName().Name
                    Version = $_.GetName().Version.ToString()
                    Location = $_.Location
                }
            } |
            Sort-Object Name, Version -Unique
    )
}

function Get-IntegrationFailureClass {
    param(
        [string]$Stage,
        [string]$Message,
        $TestReport
    )
    if ($Stage -eq 'PowerShell runtime validation') { return 'PowerShell 7 compatibility failure' }
    if ($Stage -eq 'DeployCube module import') {
        if ($Message -match '(?i)not found|could not be loaded|no module') { return 'Missing dependency' }
        return 'PowerShell 7 compatibility failure'
    }
    if ($Stage -eq 'SqlServer module import' -and $Message -match '(?i)Invoke-ASCmd|not found|could not be loaded|no module|not recognized') {
        return 'Missing dependency'
    }
    if ($Stage -eq 'SqlServer module installation' -and
        $Message -match '(?i)no match was found|unable to find|not found|does not exist') {
        return 'Missing dependency'
    }
    if ($Stage -eq 'SqlServer module installation') { return 'Infrastructure or installation problem' }
    if ($Stage -eq 'SqlServer module import') { return 'PowerShell 7 compatibility failure' }
    if ($Stage -eq 'SSAS authentication and connectivity' -and $Message -match '(?i)access.?denied|unauthori[sz]ed|login failed|credentials|authentication') {
        return 'Authentication problem'
    }
    if ($Stage -eq 'SSAS authentication and connectivity') { return 'Infrastructure or installation problem' }
    if ($Stage -eq 'Deployment Utility discovery') { return 'Deployment Utility problem' }
    if ($TestReport -and $TestReport.FailureCategory -match '(?i)deploy|utility') {
        return 'Deployment Utility problem'
    }
    if ($TestReport -and $TestReport.FailureCategory -match '(?i)auth|permission|login|connectivity') {
        return 'Authentication problem'
    }
    if ($Stage -eq 'DeployCube integration') { return 'SSAS processing failure' }
    return 'Infrastructure or installation problem'
}

try {
    $actualVersion = $PSVersionTable.PSVersion.ToString()
    $report.PowerShell = [pscustomobject]@{
        Version = $actualVersion
        Edition = $PSVersionTable.PSEdition
        ProcessPath = (Get-Process -Id $PID).Path
        NativePowerShell7Process = ($PSVersionTable.PSEdition -eq 'Core' -and
            $PSVersionTable.PSVersion.Major -eq 7)
    }
    $report.DotNetRuntime = [System.Runtime.InteropServices.RuntimeInformation]::FrameworkDescription
    if (-not $report.PowerShell.NativePowerShell7Process -or $actualVersion -ne $ExpectedPowerShellVersion) {
        throw "Expected native PowerShell $ExpectedPowerShellVersion (Core); found $actualVersion ($($PSVersionTable.PSEdition))."
    }

    $failureStage = 'DeployCube module import'
    $repositoryRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
    Import-Module (Join-Path $repositoryRoot 'DeployCube\DeployCube.psd1') -Force -ErrorAction Stop
    $failureStage = 'SqlServer module installation'
    if (-not (Get-Module -ListAvailable -Name SqlServer)) {
        Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction Stop
        Install-Module -Name SqlServer -Force -Scope CurrentUser -ErrorAction Stop
    }
    $failureStage = 'SqlServer module import'
    Import-Module SqlServer -ErrorAction Stop
    $asCmd = Get-Command -Name Invoke-ASCmd -ErrorAction Stop
    $availableSqlServerModule = Get-Module -ListAvailable -Name SqlServer |
        Sort-Object Version -Descending | Select-Object -First 1
    $sqlModule = Get-Module -Name SqlServer | Select-Object -First 1
    if (-not $sqlModule) {
        $sqlModule = Get-Module | Where-Object { $_.Name -eq $asCmd.ModuleName } |
            Select-Object -First 1
    }
    $compatibilityModule = (
        $sqlModule.Name -like 'tmp_*' -or
        $sqlModule.Path -match '(?i)WindowsPowerShellCompatibility|tmp_' -or
        $asCmd.ModuleName -like 'tmp_*' -or
        ($asCmd.Definition -match '(?i)Invoke-Command' -and $asCmd.Definition -match '(?i)Session') -or
        ($availableSqlServerModule.CompatiblePSEditions -and
            'Core' -notin $availableSqlServerModule.CompatiblePSEditions)
    )
    $report.SqlServerModule = [pscustomobject]@{
        Name = $availableSqlServerModule.Name
        Version = $availableSqlServerModule.Version.ToString()
        LoadedModuleName = $sqlModule.Name
        ModuleType = [string]$sqlModule.ModuleType
        Path = $availableSqlServerModule.Path
        LoadedModulePath = $sqlModule.Path
        CompatiblePSEditions = @($availableSqlServerModule.CompatiblePSEditions)
        ExecutionMechanism = if ($compatibilityModule) {
            'Windows PowerShell compatibility mechanism indicated'
        } else {
            'Loaded in the current PowerShell 7 process'
        }
    }
    $report.InvokeASCmd = [pscustomobject]@{
        Name = $asCmd.Name
        CommandType = [string]$asCmd.CommandType
        ModuleName = $asCmd.ModuleName
    }
    $report.ExecutionClassification = if ($compatibilityModule) {
        'PowerShell 7 using compatibility mechanisms'
    } else {
        'Native PowerShell 7'
    }

    $failureStage = 'Deployment Utility discovery'
    $utilityInventory = @(& (Join-Path $PSScriptRoot 'Get-DeploymentToolInventory.ps1') |
        Where-Object { $_.ProductMajorVersion -eq 22 })
    if ($utilityInventory.Count -ne 1) {
        throw "Expected one SSMS 22 Deployment Utility; found $($utilityInventory.Count)."
    }
    $selectedUtilityPath = Get-AnalysisServicesDeploymentExePath -Version 22
    if (-not [System.StringComparer]::OrdinalIgnoreCase.Equals(
            $utilityInventory[0].Path, $selectedUtilityPath)) {
        throw 'DeployCube utility selection did not match the SSMS 22 executable inventory.'
    }
    $report.DeploymentUtility = $utilityInventory[0]

    $failureStage = 'SSAS authentication and connectivity'
    $server = New-Object Microsoft.AnalysisServices.Server
    $server.Connect('localhost\DCUBE')
    $report.Ssas = [pscustomobject]@{
        Version = $server.Version.ToString()
        Mode = [string]$server.ServerMode
        Edition = [string]$server.Edition
    }
    $report.AmoAssemblies = Get-LoadedAmoAssemblies
    $report.Authentication = [pscustomobject]@{
        Mechanism = 'Windows integrated authentication'
        Identity = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    }
    $server.Disconnect()
    $server = $null

    $failureStage = 'DeployCube integration'
    New-Item -ItemType Directory -Path $processingDirectory -Force | Out-Null
    $processingScript = if ($Mode -eq 'Tabular') {
        Join-Path $PSScriptRoot 'Invoke-SsasTabularProcessing.ps1'
    } else {
        Join-Path $PSScriptRoot 'Invoke-SsasProcessingCompatibility.ps1'
    }
    $scriptArguments = @{
        LogDirectory = $processingDirectory
        SourceReportPath = $SourceReportPath
        SsasVersion = $SsasVersion
    }
    if ($Mode -eq 'Tabular') { $scriptArguments.PhaseH2 = $true }
    & $processingScript @scriptArguments

    if (Test-Path -LiteralPath $processingReportPath) {
        $processingReport = Get-Content -LiteralPath $processingReportPath -Raw | ConvertFrom-Json
    }
    if (-not $processingReport) {
        throw "The $Mode processing script did not create its result report."
    }

    $report.Deployment = if ($processingReport.PublishCube -eq 'Passed') { 'Passed' } else { 'Failed' }
    $report.Processing = if ($processingReport.Processing -eq 'Passed') { 'Passed' } else { 'Failed' }
    $report.QueryVerification = if (
        ($Mode -eq 'Tabular' -and $processingReport.DaxOutcome -eq 'Passed' -and
            [double]$processingReport.DaxResult -eq 10) -or
        ($Mode -eq 'Multidimensional' -and $processingReport.MdxOutcome -eq 'Passed' -and
            [double]$processingReport.MdxResult -eq 10)
    ) { 'Passed' } else { 'Failed' }
    $report.Cleanup = [string]$processingReport.Cleanup
    if ($Mode -eq 'Tabular') {
        $databaseVerified = [bool]$processingReport.TabularMetadata.DatabaseExists
        $report.AmoAssemblies = Get-LoadedAmoAssemblies
    } else {
        $databaseVerified = [bool]$processingReport.DatabaseExistsAfterPublish
    }
    if ($processingReport.Outcome -ne 'Passed' -or
        $report.Deployment -ne 'Passed' -or
        -not $databaseVerified -or
        $report.Processing -ne 'Passed' -or
        $report.QueryVerification -ne 'Passed' -or
        $report.Cleanup -ne 'Passed') {
        $report.FailureClass = Get-IntegrationFailureClass -Stage $failureStage `
            -Message ([string]$processingReport.Error) -TestReport $processingReport
        throw "SSAS $Mode deployment, processing, query verification and cleanup did not all pass."
    }
    $report.Outcome = 'Passed'
    $report.FailureClass = $null
}
catch {
    $report.Error = $_.Exception.ToString()
    if ($report.FailureClass -eq 'Infrastructure or installation problem') {
        $report.FailureClass = Get-IntegrationFailureClass -Stage $failureStage `
            -Message $report.Error -TestReport $processingReport
    }
}
finally {
    if ($server -and $server.Connected) { $server.Disconnect() }
    if (-not $processingReport -and (Test-Path -LiteralPath $processingReportPath)) {
        $processingReport = Get-Content -LiteralPath $processingReportPath -Raw | ConvertFrom-Json
    }
    if ($processingReport) {
        $report.Deployment = if ($processingReport.PublishCube -eq 'Passed') { 'Passed' } else { 'Failed' }
        $report.Processing = if ($processingReport.Processing -eq 'Passed') { 'Passed' } else { 'Failed' }
        $report.Cleanup = [string]$processingReport.Cleanup
        if ($Mode -eq 'Tabular') {
            $report.QueryVerification = if ($processingReport.DaxOutcome -eq 'Passed' -and
                [double]$processingReport.DaxResult -eq 10) { 'Passed' } else { 'Failed' }
        } else {
            $report.QueryVerification = if ($processingReport.MdxOutcome -eq 'Passed' -and
                [double]$processingReport.MdxResult -eq 10) { 'Passed' } else { 'Failed' }
        }
        if ($report.Outcome -ne 'Passed') {
            $report.FailureClass = Get-IntegrationFailureClass -Stage $failureStage `
                -Message ([string]$processingReport.Error) -TestReport $processingReport
        }
    }
    $report | ConvertTo-Json -Depth 14 |
        Set-Content -LiteralPath $reportPath -Encoding UTF8
}

if ($report.Outcome -ne 'Passed') {
    throw "PowerShell 7 SSAS integration failed: $($report.FailureClass). See '$reportPath'. $($report.Error)"
}
