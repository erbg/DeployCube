BeforeAll {
    . (Join-Path $PSScriptRoot '../infrastructure/Copy-SsmsSetupLogs.ps1')
    $script:workflow = Get-Content (Join-Path $PSScriptRoot '../../.github/workflows/ssas-compatibility.yml') -Raw
}

Describe 'SSMS installer diagnostic collection' {
    BeforeEach {
        $script:root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $script:destination = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $script:root 'nested') -Force | Out-Null
        foreach ($name in @('dd_setup_123.log', 'dd_bootstrapper_123.log', 'dd_precheck_123.log', 'unrelated.txt')) {
            Set-Content -LiteralPath (Join-Path $script:root $name) -Value $name
        }
        Set-Content -LiteralPath (Join-Path $script:root 'nested/dd_setup_nested.log') -Value 'nested'
        Set-Content -LiteralPath (Join-Path $script:root 'dd_setup_old.log') -Value 'old'
        (Get-Item -LiteralPath (Join-Path $script:root 'dd_setup_old.log')).LastWriteTimeUtc = [datetime]::UtcNow.AddDays(-1)
    }

    It 'captures recent setup, bootstrapper and precheck logs without unrelated or stale files' {
        $result = @(Copy-SsmsSetupLogs -Roots @($script:root) -Destination $script:destination `
            -SinceUtc ([datetime]::UtcNow.AddHours(-1)))
        $names = @($result[0].Files | ForEach-Object { Split-Path -Leaf $_.Source })
        $names.Count | Should -Be 3
        $names | Should -Contain 'dd_setup_123.log'
        $names | Should -Contain 'dd_bootstrapper_123.log'
        $names | Should -Contain 'dd_precheck_123.log'
        Test-Path -LiteralPath $result[0].Files[0].Artifact | Should -BeTrue
    }

    It 'includes nested setup logs only for recursive roots and handles missing roots' {
        $result = @(Copy-SsmsSetupLogs -Roots @((Join-Path $TestDrive 'missing'), $script:root) `
            -Destination $script:destination -SinceUtc ([datetime]::UtcNow.AddHours(-1)) -Recurse)
        $names = @($result[0].Files | ForEach-Object { Split-Path -Leaf $_.Source })
        $names | Should -Contain 'dd_setup_nested.log'
        $names | Should -Not -Contain 'dd_setup_old.log'
    }

    It 'surfaces file-copy failures instead of claiming complete diagnostics' {
        Mock Copy-Item { throw 'Simulated access failure' }
        { Copy-SsmsSetupLogs -Roots @($script:root) -Destination $script:destination `
            -SinceUtc ([datetime]::UtcNow.AddHours(-1)) } | Should -Throw '*Simulated access failure*'
    }

    It 'uses the existing short installer temp path and captures diagnostics after failure' {
        $script:workflow | Should -Match "(?s)name: Install SSMS.*?phase-i-powershell7.*?Join-Path \`$env:RUNNER_TEMP"
        $script:workflow | Should -Match "(?s)name: Capture Visual Studio installer diagnostics\s+if: always\(\) && inputs.scope == 'phase-i-powershell7' && steps.install-ssms.outcome != 'skipped'"
        $script:workflow | Should -Match '(?s)name: Install SSMS.*?finally.*?phase-i-powershell7.*?Copy-Item'
        $script:workflow | Should -Match '(?s)name: Upload SQL setup logs, reports and test results\s+if: always\(\)'
    }
}
