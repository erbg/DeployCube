#
# Module manifest for module 'DeployCube'
#
# Generated by: Dr. John Tunnicliffe
#
# Generated on: 04/01/2021
#

@{

# Script module or binary module file associated with this manifest.
RootModule = 'DeployCube.psm1'

# Version number of this module.
ModuleVersion = '1.2.0'

# ID used to uniquely identify this module
GUID = 'de85c41f-a8ab-41b3-90ec-2cb7d1bc1cb3'

# Author of this module
Author = 'Dr. John Tunnicliffe'

# Company or vendor of this module
CompanyName = 'Decision Analytics'

# Copyright statement for this module
Copyright = '(c) 2019-2021 Dr. John Tunnicliffe. All rights reserved.'

# Description of the functionality provided by this module
Description = 'Provides utilities to help you deploy your Analysis Services cube to Azure or your on-premise servers.  Supports both Tabular and Multidimensional projects.  Full documentation can be found on the [project site](https://github.com/DrJohnT/DeployCube)'

# Minimum version of the Windows PowerShell engine required by this module
PowerShellVersion = '5.0'

# Functions to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no functions to export.
FunctionsToExport = @(
    'Find-AnalysisServicesDeploymentExeLocations',
    'Get-AnalysisServicesDeploymentExePath',
    'Get-CubeDatabaseCompatibilityLevel',
    'Get-ModuleByName',
    'Get-ServerMode',
    'Get-SqlAsPath',
    'Get-SqlConnectionString',
    'Get-SsasProcessingMessages',
    'Invoke-ExternalCommand',
    'Invoke-ProcessTabularCubeDatabase',
    'Ping-SsasDatabase',
    'Ping-SsasServer',
    'Publish-Cube',
    'Select-AnalysisServicesDeploymentExeVersion',
    'Unpublish-Cube',
    'Update-AnalysisServicesConfig',
    'Update-TabularCubeDataSource'
)

# Cmdlets to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no cmdlets to export.
CmdletsToExport = @()

# Variables to export from this module
VariablesToExport = @()

# Aliases to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no aliases to export.
AliasesToExport = @(
    'Deploy-Cube',
    'Drop-Cube'
)

# Private data to pass to the module specified in RootModule/ModuleToProcess. This may also contain a PSData hashtable with additional module metadata used by PowerShell.
PrivateData = @{

    PSData = @{

        # Tags applied to this module. These help with module discovery in online galleries.
        Tags = @("SSST","deployment","tabular","deploy","multidimenstional","SQL","database","sqlserver","Profile","Azure","DevOps","powershell","pipeline","release")

        # A URL to the license for this module.
        LicenseUri = 'https://raw.githubusercontent.com/DrJohnT/DeployCube/master/DeployCube/LICENSE'

        # A URL to the main website for this project.
        ProjectUri = 'https://github.com/DrJohnT/DeployCube'

        # A URL to an icon representing this module.
        # IconUri = ''

        # ReleaseNotes of this module
        ReleaseNotes = 'https://github.com/DrJohnT/DeployCube/releases/tag/1.0.0'

    } # End of PSData hashtable

} # End of PrivateData hashtable

# HelpInfo URI of this module
HelpInfoURI = 'https://github.com/DrJohnT/DeployCube'

}

