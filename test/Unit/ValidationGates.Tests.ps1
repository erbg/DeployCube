BeforeAll {
    $script:testRoot = Split-Path $PSScriptRoot -Parent
    . (Join-Path $script:testRoot 'Assert-ValidationResult.ps1')
    . (Join-Path $script:testRoot 'Assert-ReleaseEnvironment.ps1')
    $script:buildScript = Join-Path $script:testRoot 'Build-ReleasePackage.ps1'
}

Describe 'Mandatory validation result gate' {
    BeforeEach {
        $script:result = [pscustomobject]@{
            Result = 'Passed'
            PassedCount = 1
            FailedCount = 0
            FailedBlocksCount = 0
            FailedContainersCount = 0
            CodeCoverage = [pscustomobject]@{ CommandsAnalyzedCount = 400; CommandsExecutedCount = 300 }
        }
    }

    It 'accepts exactly 75 percent command coverage' {
        { Assert-ValidationResult $script:result -CodeCoverage } | Should -Not -Throw
    }

    It 'rejects coverage just below 75 percent without rounding up' {
        $script:result.CodeCoverage.CommandsExecutedCount = 299
        { Assert-ValidationResult $script:result -CodeCoverage } | Should -Throw '*below 75%*'
    }

    It 'rejects missing coverage' {
        $script:result.CodeCoverage = $null
        { Assert-ValidationResult $script:result -CodeCoverage } | Should -Throw '*Coverage is missing*'
    }

    It 'rejects an empty coverage denominator' {
        $script:result.CodeCoverage.CommandsAnalyzedCount = 0
        { Assert-ValidationResult $script:result -CodeCoverage } | Should -Throw '*no analyzed commands*'
    }

    It 'rejects failed, undiscovered, and broken tests: <Property>' -ForEach @(
        @{ Property = 'Result'; Value = 'Failed' }
        @{ Property = 'PassedCount'; Value = 0 }
        @{ Property = 'FailedCount'; Value = 1 }
        @{ Property = 'FailedBlocksCount'; Value = 1 }
        @{ Property = 'FailedContainersCount'; Value = 1 }
    ) {
        $script:result.$Property = $Value
        { Assert-ValidationResult $script:result } | Should -Throw '*Validation failed*'
    }
}

Describe 'Protected release environment gate' {
    BeforeEach {
        $script:environment = [pscustomobject]@{
            name = 'psgallery'
            protection_rules = @([pscustomobject]@{
                type = 'required_reviewers'
                reviewers = @([pscustomobject]@{ type = 'User' })
            })
            deployment_branch_policy = [pscustomobject]@{ custom_branch_policies = $true }
        }
    }

    It 'accepts an explicitly protected environment' {
        { Assert-ReleaseEnvironment $script:environment } | Should -Not -Throw
    }

    It 'rejects an unprotected or automatically created environment' {
        $script:environment.protection_rules = @()
        { Assert-ReleaseEnvironment $script:environment } | Should -Throw '*require reviewer approval*'
    }

    It 'rejects a reviewer rule with no reviewers' {
        $script:environment.protection_rules[0].reviewers = @()
        { Assert-ReleaseEnvironment $script:environment } | Should -Throw '*require reviewer approval*'
    }

    It 'rejects a reviewer rule with missing reviewers' {
        $script:environment.protection_rules[0].reviewers = $null
        { Assert-ReleaseEnvironment $script:environment } | Should -Throw '*require reviewer approval*'
    }

    It 'rejects the wrong environment' {
        $script:environment.name = 'other'
        { Assert-ReleaseEnvironment $script:environment } | Should -Throw '*psgallery environment*'
    }

    It 'rejects an unrestricted deployment policy' {
        $script:environment.deployment_branch_policy = $null
        { Assert-ReleaseEnvironment $script:environment } | Should -Throw '*custom deployment tag rules*'
    }
}

Describe 'Non-publishing release package validation' {
    BeforeEach {
        $script:outputPath = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $script:version = (Import-PowerShellDataFile (Join-Path (Split-Path $script:testRoot -Parent) 'DeployCube/DeployCube.psd1')).ModuleVersion
        Mock Register-PSRepository {}
        Mock Get-PSRepository { [pscustomobject]@{ Name = $Name } }
        Mock Unregister-PSRepository {}
        Mock Publish-Module { throw 'Simulated packaging failure' }
    }

    It 'rejects mismatched and malformed release tags before building: <Tag>' -ForEach @(
        @{ Tag = 'v0.0.0' }
        @{ Tag = '1.2.6' }
        @{ Tag = 'vv1.2.6' }
        @{ Tag = 'V1.2.6' }
        @{ Tag = 'v1.2.6-extra' }
    ) {
        { & $script:buildScript -Tag $Tag -OutputPath $script:outputPath } | Should -Throw '*must exactly match*'
        Should -Invoke Publish-Module -Times 0 -Exactly
    }

    It 'surfaces packaging failures and unregisters the temporary repository' {
        { & $script:buildScript -Tag "v$script:version" -OutputPath $script:outputPath } |
            Should -Throw '*Simulated packaging failure*'
        Should -Invoke Unregister-PSRepository -Times 1 -Exactly
        Should -Invoke Publish-Module -Times 1 -Exactly -ParameterFilter {
            $Repository -like 'DeployCubeBuild-*' -and -not $NuGetApiKey
        }
    }

    It 'rejects a successful command that did not produce a package' {
        Mock Publish-Module {}
        { & $script:buildScript -OutputPath $script:outputPath } | Should -Throw '*expected versioned NuGet package*'
    }

    It 'builds only against the temporary filesystem repository and checks package contents' {
        Mock Publish-Module {
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            $version = (Import-PowerShellDataFile (Join-Path $Path 'DeployCube.psd1')).ModuleVersion
            [IO.Compression.ZipFile]::CreateFromDirectory($Path, (Join-Path (Split-Path $Path -Parent) "feed/DeployCube.$version.nupkg"))
        }
        { & $script:buildScript -Tag "v$script:version" -OutputPath $script:outputPath } | Should -Not -Throw
        Should -Invoke Register-PSRepository -Times 1 -Exactly -ParameterFilter {
            $SourceLocation -eq (Join-Path $script:outputPath 'feed') -and $PublishLocation -eq $SourceLocation
        }
        Test-Path (Join-Path $script:outputPath 'DeployCube/DeployCube.psd1') | Should -BeTrue
    }

    It 'rejects missing module files in a package' {
        Mock Publish-Module {
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            $empty = Join-Path $TestDrive 'empty'
            New-Item -ItemType Directory -Path $empty -Force | Out-Null
            $version = (Import-PowerShellDataFile (Join-Path $Path 'DeployCube.psd1')).ModuleVersion
            [IO.Compression.ZipFile]::CreateFromDirectory($empty, (Join-Path (Split-Path $Path -Parent) "feed/DeployCube.$version.nupkg"))
        }
        { & $script:buildScript -OutputPath $script:outputPath } | Should -Throw '*Package is missing*'
    }

    It 'accepts Windows .NET Framework ZIP entry separators' {
        Mock Publish-Module {
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            $version = (Import-PowerShellDataFile (Join-Path $Path 'DeployCube.psd1')).ModuleVersion
            $package = Join-Path (Split-Path $Path -Parent) "feed/DeployCube.$version.nupkg"
            $archive = [IO.Compression.ZipFile]::Open($package, [IO.Compression.ZipArchiveMode]::Create)
            try {
                foreach ($name in @('DeployCube.psd1', 'DeployCube.psm1', 'public\Publish-Cube.ps1')) {
                    $null = $archive.CreateEntry($name)
                }
            } finally { $archive.Dispose() }
        }
        { & $script:buildScript -OutputPath $script:outputPath } | Should -Not -Throw
    }
}

Describe 'Workflow release and integration boundaries' {
    BeforeAll {
        $workflows = Join-Path (Split-Path $script:testRoot -Parent) '.github/workflows'
        $script:ci = Get-Content (Join-Path $workflows 'ci.yml') -Raw
        $script:release = Get-Content (Join-Path $workflows 'release.yml') -Raw
        $script:workflows = $workflows
        $script:ssas = Get-Content (Join-Path $workflows 'ssas-compatibility.yml') -Raw
        $script:entry = Get-Content (Join-Path $workflows 'powershell7-ssas-integration.yml') -Raw

        function Assert-IntegrationTriggers {
            param([string]$Content, [string[]]$Allowed)
            $onBlock = [regex]::Match($Content, '(?ms)^on:[ \t]*\r?\n(.*?)(?=^[^\s#]|\z)')
            if (-not $onBlock.Success) { throw 'Expected a block-style workflow on section.' }
            $events = @([regex]::Matches($onBlock.Groups[1].Value, '(?m)^  ([a-z_]+):') |
                ForEach-Object { $_.Groups[1].Value })
            if ((($events | Sort-Object) -join ',') -cne (($Allowed | Sort-Object) -join ',')) {
                throw "Unexpected integration workflow triggers: $($events -join ', '); expected $($Allowed -join ', ')."
            }

        }

        function Assert-PowerShell7Entry {
            param([string]$Content)
            Assert-IntegrationTriggers -Content $Content -Allowed @('workflow_dispatch')
            foreach ($inputName in @('powershell_version', 'ssas_mode')) {
                $inputBlock = [regex]::Match($Content, "(?ms)^      ${inputName}:\r?\n(.*?)(?=^      [a-z_]+:|^[^\s#]|\z)")
                if (-not $inputBlock.Success -or $inputBlock.Groups[1].Value -notmatch '(?m)^        type: choice\r?$') {
                    throw "Expected choice input $inputName."
                }
                $options = @([regex]::Matches($inputBlock.Groups[1].Value, '(?m)^          - [''"]?([^''"\r\n]+)[''"]?\r?$') |
                    ForEach-Object { $_.Groups[1].Value })
                $expectedOptions = if ($inputName -eq 'powershell_version') { @('7.4.22', '7.5.13') } else { @('Tabular', 'Multidimensional') }
                if ((($options | Sort-Object) -join ',') -cne (($expectedOptions | Sort-Object) -join ',')) {
                    throw "Unexpected options for $inputName."
                }
            }
            $jobs = [regex]::Match($Content, '(?ms)^jobs:[ \t]*\r?\n(.*)\z').Groups[1].Value
            $jobNames = @([regex]::Matches($jobs, '(?m)^  ([a-zA-Z0-9_-]+):') |
                ForEach-Object { $_.Groups[1].Value })
            if ($jobNames.Count -ne 1 -or $jobNames[0] -cne 'integration') {
                throw 'Expected exactly one integration job.'
            }
            $targets = @([regex]::Matches($jobs, '(?m)^    uses:[ \t]*(.*?)[ \t]*\r?$') |
                ForEach-Object { $_.Groups[1].Value })
            if ($targets.Count -ne 1 -or $targets[0] -cne './.github/workflows/ssas-compatibility.yml') {
                throw 'Unexpected reusable SSAS workflow target.'
            }
            $arguments = @{}
            foreach ($argumentMatch in [regex]::Matches($jobs, '(?m)^      ([a-zA-Z0-9_-]+):[ \t]*(.*?)[ \t]*\r?$')) {
                if ($arguments.ContainsKey($argumentMatch.Groups[1].Value)) { throw 'Duplicate reusable workflow argument.' }
                $arguments[$argumentMatch.Groups[1].Value] = $argumentMatch.Groups[2].Value
            }
            $expected = @{
                scope = 'phase-i-powershell7'
                powershell7_version = '${{ inputs.powershell_version }}'
                powershell7_mode = '${{ inputs.ssas_mode }}'
                media_urls_json = "'{`"2022`":`"https://download.microsoft.com/download/3/8/d/38de7036-2433-4207-8eae-06e247e17b25/SQLServer2022-x64-ENU-Dev.iso`"}'"
            }
            if ($arguments.Count -ne $expected.Count) { throw 'Unexpected reusable workflow arguments.' }
            foreach ($key in $expected.Keys) {
                if (-not $arguments.ContainsKey($key) -or $arguments[$key] -cne $expected[$key]) {
                    throw "Unexpected reusable workflow argument: $key."
                }
            }
        }
    }

    It 'keeps SSMS manual-only and narrowly permits the reusable SSAS workflow' {
        Assert-IntegrationTriggers -Content (Get-Content (Join-Path $script:workflows 'ssms-compatibility.yml') -Raw) `
            -Allowed @('workflow_dispatch')
        Assert-IntegrationTriggers -Content $script:ssas -Allowed @('workflow_call', 'workflow_dispatch')
        Assert-PowerShell7Entry -Content $script:entry
        $guard = "    if: `${{ github.event_name == 'workflow_dispatch' && (github.workflow == 'SSAS compatibility' || (github.workflow == 'Experimental PowerShell 7 SSAS integration' && inputs.scope == 'phase-i-powershell7' && (inputs.powershell7_version == '7.4.22' || inputs.powershell7_version == '7.5.13') && (inputs.powershell7_mode == 'Tabular' || inputs.powershell7_mode == 'Multidimensional'))) }}"
        $script:ssas | Should -Match ('(?m)^  ssas-compatibility:\r?\n    name:[^\r\n]*\r?\n' + [regex]::Escape($guard) + '\r?$')
    }

    It 'rejects automatic and unintended reusable integration triggers' {
        foreach ($workflowFile in @('ssms-compatibility.yml', 'ssas-compatibility.yml', 'powershell7-ssas-integration.yml')) {
            $original = Get-Content (Join-Path $script:workflows $workflowFile) -Raw
            foreach ($triggerName in @('push: [master]', 'pull_request:', 'schedule:', 'workflow_run:')) {
                $content = $original -replace '(?m)^on:', "on:`n  $triggerName"
                $allowed = if ($workflowFile -eq 'ssas-compatibility.yml') {
                    @('workflow_call', 'workflow_dispatch')
                } else { @('workflow_dispatch') }
                { Assert-IntegrationTriggers -Content $content -Allowed $allowed } | Should -Throw '*Unexpected integration workflow triggers*'
            }
            if ($workflowFile -ne 'ssas-compatibility.yml') {
                $content = $original -replace '(?m)^on:', "on:`n  workflow_call:"
                { Assert-IntegrationTriggers -Content $content -Allowed @('workflow_dispatch') } |
                    Should -Throw '*Unexpected integration workflow triggers*'
            }
        }
    }

    It 'rejects altered reusable workflow targets, scopes and arguments' {
        foreach ($mutation in @(
            @{ Old = './.github/workflows/ssas-compatibility.yml'; New = './.github/workflows/ci.yml' }
            @{ Old = 'scope: phase-i-powershell7'; New = 'scope: full-matrix' }
            @{ Old = 'powershell7_version: ${{ inputs.powershell_version }}'; New = 'powershell7_version: 7.6.0' }
            @{ Old = 'powershell7_mode: ${{ inputs.ssas_mode }}'; New = 'powershell7_mode: Tabular' }
            @{ Old = "- '7.5.13'"; New = "- '7.6.0'" }
            @{ Old = '- Multidimensional'; New = '- OtherMode' }
            @{ Old = 'scope: phase-i-powershell7'; New = "scope: phase-i-powershell7`n      extra: true" }
            @{ Old = 'scope: phase-i-powershell7'; New = "scope: phase-i-powershell7`n      extra-option: true" }
            @{ Old = '  integration:'; New = "  other-job:`n    runs-on: windows-2022`n  integration:" }
        )) {
            $altered = $script:entry.Replace($mutation.Old, $mutation.New)
            if ($altered -ceq $script:entry) { throw 'Mutation did not alter the workflow.' }
            $rejected = $false
            try { Assert-PowerShell7Entry -Content $altered }
            catch { $rejected = $true }
            if (-not $rejected) { throw "Workflow mutation was accepted: $($mutation.Old)." }
        }
    }

    It 'has no other workflow calling the reusable SSAS workflow' {
        $callers = @(Get-ChildItem -LiteralPath $script:workflows -File | Where-Object {
            $_.Extension -in @('.yml', '.yaml') -and
            (Get-Content -LiteralPath $_.FullName -Raw) -match '(?im)^[ \t]*uses:[ \t]*[^\r\n]*ssas-compatibility\.ya?ml'
        })
        $callers.Count | Should -Be 1
        $callers[0].Name | Should -Be 'powershell7-ssas-integration.yml'
    }

    It 'uses the shared mandatory CI gate before publication' {
        $script:release | Should -Match 'uses: \./\.github/workflows/ci.yml'
        $script:release | Should -Match 'release_tag: \$\{\{ github.ref_name \}\}'
        $script:release | Should -Match '(?s)publish:\s+needs: \[validate, release-policy\]\s+if: \$\{\{ success\(\)'
        $script:release | Should -Match 'Assert-ReleaseEnvironment -Environment'
        $script:release | Should -Match 'environment: psgallery'
        $script:release | Should -Match 'name: release-package'
        $script:release | Should -Not -Match 'secrets: inherit|continue-on-error:'
    }

    It 'exposes publication credentials only in the publishing step' {
        $script:ci | Should -Not -Match 'secrets\.|PSGALLERY_API_KEY'
        $script:release | Should -Match '(?s)name: Publish module to PSGallery\s+env:\s+PSGALLERY_API_KEY:'
        @([regex]::Matches($script:release, 'secrets\.PSGALLERY_API_KEY')).Count | Should -Be 1
    }

    It 'does not schedule infrastructure or bypass failing validation' {
        $script:ci | Should -Not -Match 'self-hosted|Install-Ssas|Install-Ssms|Invoke-SsasCompatibility|continue-on-error:'
        $script:ci | Should -Match 'shell: powershell'
        $script:ci | Should -Match 'PSVersion.Minor -ne 1'
        $script:ci | Should -Match 'Invoke-DeployCubeTests.ps1 -Type Analyzer -CI'
        $script:ci | Should -Match 'Invoke-DeployCubeTests.ps1 -Type Unit -CodeCoverage -CI'
    }
}

Describe 'PowerShell 7 SSAS integration safety' {
    BeforeAll {
        $script:repositoryRoot = Split-Path $script:testRoot -Parent
        . (Join-Path $script:testRoot 'infrastructure/Assert-NativeDeployCube.ps1')
        . (Join-Path $script:testRoot 'infrastructure/SsasProcessingEvidence.ps1')
    }

    It 'requires DeployCube functions from the current PowerShell 7 process' {
        if ($PSVersionTable.PSEdition -eq 'Core') {
            Import-Module (Join-Path $script:repositoryRoot 'DeployCube/DeployCube.psd1') `
                -Force -SkipEditionCheck -ErrorAction Stop
            { Assert-NativeDeployCube -RepositoryRoot $script:repositoryRoot } | Should -Not -Throw
        }
        else {
            { Assert-NativeDeployCube -RepositoryRoot $script:repositoryRoot } | Should -Throw '*PowerShell 7 Core*'
        }
    }

    It 'rejects a shadowed or proxied DeployCube function' {
        if ($PSVersionTable.PSEdition -eq 'Core') {
            Mock Get-Command {
                [pscustomobject]@{ CommandType = 'Function'; Module = $null; ScriptBlock = {} }
            } -ParameterFilter { $Name -eq 'Publish-Cube' }
            { Assert-NativeDeployCube -RepositoryRoot $script:repositoryRoot } |
                Should -Throw '*not the in-process DeployCube function*'
        }
    }

    It 'wires both processing modes to native execution and owned-only fallback cleanup' {
        $runner = Get-Content (Join-Path $script:testRoot 'infrastructure/Invoke-SsasPowerShell7Integration.ps1') -Raw
        $runner | Should -Match 'NativeDeployCube = \$true'
        foreach ($scriptName in @('Invoke-SsasTabularProcessing.ps1', 'Invoke-SsasProcessingCompatibility.ps1')) {
            $content = Get-Content (Join-Path $script:testRoot "infrastructure/$scriptName") -Raw
            $content | Should -Match 'Assert-NativeDeployCube -RepositoryRoot'
            $content | Should -Match 'Get-OwnedSsasDatabaseNames -OwnedNames \$report\.OwnedDatabases -AllowedNames'
            $content | Should -Match '\[switch\]\$CleanupOnly'
        }
    }

    It 'only selects recorded, allowed databases for either cleanup mode' {
        $allowed = @('Good', 'InvalidSource', 'MissingTable')
        @(Get-OwnedSsasDatabaseNames -OwnedNames @('Good') -AllowedNames $allowed) | Should -Be @('Good')
        @(Get-OwnedSsasDatabaseNames -OwnedNames @() -AllowedNames $allowed).Count | Should -Be 0
        { Get-OwnedSsasDatabaseNames -OwnedNames @('Good', 'Unowned') -AllowedNames $allowed } |
            Should -Throw '*Unexpected cleanup database*'
    }
}
