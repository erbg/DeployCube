[![PowerShell Gallery Version](https://img.shields.io/powershellgallery/v/DeployCube.svg)](https://www.powershellgallery.com/packages/DeployCube)
[![CI](https://github.com/erbg/DeployCube/actions/workflows/ci.yml/badge.svg)](https://github.com/erbg/DeployCube/actions/workflows/ci.yml)
### DeployCube

# Deploy a SSAS Tabular or Multidimensional cube using the Analysis Services Deployment Utility

## Overview

**Publish-Cube** allows you to deploy a tabular or multidimensional cube to an Analysis Services instance either on-premise or in Azure.  Behind the scenes it uses the
[Analysis Services Deployment Utility](https://learn.microsoft.com/en-us/analysis-services/deployment/deploy-model-solutions-with-the-deployment-utility)
in silent mode.
**Publish-Cube** simplifies the use of [Analysis Services Deployment Utility](https://learn.microsoft.com/en-us/analysis-services/deployment/deploy-model-solutions-with-the-deployment-utility)
by automatically updating the various config files that the Deployment Utility uses to deploy the cube.

When you perform a **build** of a Visual Studio cube project, it creates an **AsDatabase** file which defines the entire model such as dimensions, attributes and measures associated with the cube.
**Publish-Cube** can be used in CI scenarios as part of the pipeline so that you can populate the cube with data and run tests against the cube using DAX or MDX as part of the pipeline.

To automate the build and deployment of a tabular cube in Azure DevOps, you can use MSBuild to create AsDatabase from your Visual Studio solution.  You can then add a PowerShell task which uses **Publish-Cube** to invoke [Analysis Services Deployment Utility](https://learn.microsoft.com/en-us/analysis-services/deployment/deploy-model-solutions-with-the-deployment-utility) to deploy each AsDatabase.
For Multidimensional models you will have to use DevEnv.com (Visual Studio) to generate the AsDatabase file.

**Publish-Cube** can also be used to automate the deployment of cubes as part of a server deployment using tools such as [Octopus Deploy](https://octopus.com/) or [Azure DevOps Release Manager](https://dev.azure.com/).

## Installation

Install from the PowerShell Gallery in Windows PowerShell, without requiring an elevated session:

~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ powershell
Install-Module -Name DeployCube -Scope CurrentUser -Repository PSGallery
Import-Module DeployCube
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

## Pre-requisites

Use Windows with **Windows PowerShell 5.1**, the automatically validated CI target.
The manifest retains its minimum PowerShell version of 5.0; this is not evidence
of current testing on 5.0. PowerShell 7/Linux checks are supplemental and do not
establish support for Windows-only deployment tooling or OLE DB.

The following prerequisites need to be installed for **Publish-Cube** to work properly.

~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ powershell
Microsoft.AnalysisServices.Deployment.exe
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Microsoft.AnalysisServices.Deployment.exe is known as the [Analysis Services Deployment Utility](https://learn.microsoft.com/en-us/analysis-services/deployment/deploy-model-solutions-with-the-deployment-utility), which is installed with [SQL Server Management Studio](https://learn.microsoft.com/en-us/ssms/install/install) (SSMS). Install SSMS separately on the deployment machine; installing DeployCube does not install this executable.

The module also uses the Microsoft SQL Server PowerShell module **SqlServer**.
Commands that need it call `Get-ModuleByName`, which installs it from the Gallery
for the current user if absent, then imports it. It is not a manifest
`RequiredModules` dependency and no version is pinned. For offline or controlled
deployments, preinstall and validate an approved version; automatic installation
requires Gallery access and can select a newer, untested version. The mocked CI
suite does not establish compatibility with every SqlServer release.

Custom install directories for Microsoft.AnalysisServices.Deployment.exe are now supported.  Please set the environment variable CustomAsDwInstallLocation prior to running any functions.

### Admin privileges required for deployment

In order to successfully deploy a tabular cube, the process running **Publish-Cube** needs to run under a service account that has admin privileges on your target Azure Analysis Services or SSAS instance.  If you wish to use a specific Windows account, all of the relevant functions have UserID / Password parameters.

## Getting Started

Full documentation for all the functions in this module are provided below.  Here's a quick start guide.

~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ powershell
Publish-Cube -AsDatabasePath "C:\Dev\YourCube\bin\Debug\YourCube.asdatabase" -Server "YourCubeServer"
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Where -AsDatabasePath is the path to your tabular or multidimensional model, and -Server is the name of the target server (including instance and port if required).  The above is the minimum set of parameters that can be used with **Publish-Cube**.

Normally, the database will be named the same as your AsDatabase file (i.e. YourCube in the example above).  However, by adding the -CubeDatabase parameter, you can change the name of your deployed cube to be anything you like.

~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ powershell
Publish-Cube -AsDatabasePath "C:\Dev\YourCube\bin\Debug\YourCube.asdatabase" -Server "YourCubeServer" -CubeDatabase "YourNewCubeName"
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

As part of the deployment you can specify a processing option.  Valid `Publish-Cube -ProcessingOption` values are: `Full`, `Default` and `DoNotProcess`.  However, it is strongly recommended that you use the default `DoNotProcess` option as the connection to your source database may not be correct and need adjustment post-deployment.

~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ powershell
Publish-Cube -AsDatabasePath "C:\Dev\YourCube\bin\Debug\YourCube.asdatabase" -Server "YourCubeServer" -ProcessingOption "DoNotProcess"
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Finally, if multiple versions of the Analysis Services Deployment Utility (Microsoft.AnalysisServices.Deployment.exe) are installed on your build agent, you can specify which version should be used with the -PreferredVersion option.

~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ powershell
Publish-Cube -AsDatabasePath "C:\Dev\YourCube\bin\Debug\YourCube.asdatabase" -Server "YourCubeServer" -PreferredVersion latest
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

## List of commands

The following is a list of commands provided by this module once you have installed the package (see *Installation* above)

| **Function**             | **Description**                                                             |
|--------------------------|-----------------------------------------------------------------------------|
| [Find-AnalysisServicesDeploymentExeLocations](https://github.com/erbg/DeployCube/blob/master/docs/Find-AnalysisServicesDeploymentExeLocations.md) | Lists all locations of Microsoft.AnalysisServices.Deployment.exe on the host |
| [Get-AnalysisServicesDeploymentExePath](https://github.com/erbg/DeployCube/blob/master/docs/Get-AnalysisServicesDeploymentExePath.md) | Returns the path of a specific version of Microsoft.AnalysisServices.Deployment.exe |
| [Get-CubeDatabaseCompatibilityLevel](https://github.com/erbg/DeployCube/blob/master/docs/Get-CubeDatabaseCompatibilityLevel.md) | Returns the CompatibilityLevel of a deployed cube database |
| [Get-ServerMode](https://github.com/erbg/DeployCube/blob/master/docs/Get-ServerMode.md) | Returns the mode of the server: Tabular or Multidimensional |
| [Get-SqlAsPath](https://github.com/erbg/DeployCube/blob/master/docs/Get-SqlAsPath.md) | Returns the path to a specific cube database SQLSERVER:\SQLAS\YourServer\DEFAULT\Databases\YourCubeDatabase |
| [Get-ModuleByName](https://github.com/erbg/DeployCube/blob/master/docs/Get-ModuleByName.md) | Loads the named PowerShell module, installing it if required |
| [Get-SqlConnectionString](https://github.com/erbg/DeployCube/blob/master/docs/Get-SqlConnectionString.md) | Helper function to create valid SQL Server database connection strings |
| [Get-SsasProcessingMessages](https://github.com/erbg/DeployCube/blob/master/docs/Get-SsasProcessingMessages.md) | Examines the XML returned by the Invoke-AsCmd function to find errors.  Writes error message if errors are found |
| [Invoke-ProcessTabularCubeDatabase](https://github.com/erbg/DeployCube/blob/master/docs/Invoke-ProcessTabularCubeDatabase.md) | Processes an SSAS database on a SQL Server SSAS instance |
| [Invoke-ExternalCommand](https://github.com/erbg/DeployCube/blob/master/docs/Invoke-ExternalCommand.md) | Helper function to run command-line programs |
| [Ping-SsasDatabase](https://github.com/erbg/DeployCube/blob/master/docs/Ping-SsasDatabase.md) | Returns true if the specified SSAS database exists on the server |
| [Ping-SsasServer](https://github.com/erbg/DeployCube/blob/master/docs/Ping-SsasServer.md) | Returns true if the specified SSAS server exists |
| [Publish-Cube](https://github.com/erbg/DeployCube/blob/master/docs/Publish-Cube.md) | Publish-Cube deploys a tabular or multidimensional cube to a SQL Server Analysis Services instance |
| [Select-AnalysisServicesDeploymentExeVersion](https://github.com/erbg/DeployCube/blob/master/docs/Select-AnalysisServicesDeploymentExeVersion.md) | Finds a specific version of the Microsoft.AnalysisServices.Deployment.exe if more than one present on the host |
| [Unpublish-Cube](https://github.com/erbg/DeployCube/blob/master/docs/Unpublish-Cube.md) | Drops a Tabular or Multidimensional cube from the specified server |
| [Update-AnalysisServicesConfig](https://github.com/erbg/DeployCube/blob/master/docs/Update-AnalysisServicesConfig.md) | Updates the various config files (listed below) which are needed to deploy the cube |
| [Update-TabularCubeDataSource](https://github.com/erbg/DeployCube/blob/master/docs/Update-TabularCubeDataSource.md) | Updates the cube's connection to the source SQL database. |

## Azure DevOps Agent

For CI scenarios, **Publish-Cube** has been packaged as an extension for Azure Pipelines available from the marketplace here: [Deployment tools for SSAS Tabular Cube Models](https://marketplace.visualstudio.com/items?itemName=DrJohnExtensions.DeployTabularModel)

## Example Tabular Model

An example tabular model is provided as a Visual Studio solution alongside a SQL database which acts as the cubes source.  The
DACPAC is provided in the .\example folder.  You can use this to test that deployments work correctly.  Note that the SSDT Visual Studio solution is configured to deploy to SQL Server 2016.  Open the Visual Studio solution and change the target version and rebuild the solution if you have a different version of SQL Server installed. This legacy example is separate from the fixtures used for the compatibility results below.

## Validated compatibility

The [compatibility-testing guide](docs/COMPATIBILITY_TESTING.md#verified-compatibility-evidence)
records the exact server builds, Deployment Utility file versions, fixtures and
successful manual workflow runs. SSMS versions identify the installation source,
not the SSAS server version or model compatibility level.

| SSAS Developer server | SSMS / Deployment Utility | Tabular | Multidimensional |
|---|---|---|---|
| 2019 | 22 / 22.1.17.0 | Deployment and full processing: level 1500 | Deployment and full processing: level 1100 |
| 2022 | 20 / 20.0.3.0; 21 / 21.0.52.0 | Deployment only: level 1500; processing not tested with these utilities | Not tested with these utilities |
| 2022 | 22 / 22.1.17.0 | Deployment and full processing: level 1500 | Deployment and full processing: level 1100 |
| 2025 | 22 / 22.1.17.0 | Deployment: level 1500; deployment and full processing: level 1700 | Deployment and full processing: level 1100 |

Processing checks verified isolated SQL source access and a numeric result of 10
using DAX (Tabular) or MDX (Multidimensional), expected failure cases, and cleanup.
SSMS 20/21/22 installation and utility discovery/selection were also tested
separately. These experimental results apply only to the recorded configurations,
not every server edition, update, model level or deployment option. Other
combinations remain unverified; selecting a utility does not prove deployment
or processing compatibility.

## Contributing and validation

Pull requests and pushes to `master` run syntax checks, PSScriptAnalyzer, infrastructure-free
Pester tests, command coverage (minimum 75%), and a local-only package build on Windows
PowerShell 5.1. The build validates the module manifest and inspects a package
created in a temporary filesystem repository; ordinary CI does not publish to
the PowerShell Gallery. Test dependencies are pinned to Pester 5.7.1 and
PSScriptAnalyzer 1.24.0. See [the testing guide](test/README.md) for local commands, coverage scope,
release gates, and required environment protection.

Real SSMS/SSAS compatibility tests remain manual-only on GitHub-hosted Windows runners;
see [compatibility testing](docs/COMPATIBILITY_TESTING.md).

## Issue Reporting

If you are facing problems in making this PowerShell module work, please report any
problems on [DeployCube GitHub Project
Page](https://github.com/erbg/DeployCube/issues).

## Acknowledgements

DeployCube was originally created by [DrJohnT](https://github.com/DrJohnT).
Special thanks to John for developing the project and making it available to the open-source community.
The project continues to be maintained and developed, and contributions, bug reports, and pull requests are welcome.
