function Ping-SsasDatabase {
    <#
        .SYNOPSIS
        Checks that the database exists on the specified SQL Server SSAS instance

        .DESCRIPTION
        Checks that the database exists on the specified SQL Server SSAS instance

		Written by (c) Dr. John Tunnicliffe, 2019 https://github.com/DrJohnT/PublishDacPac
		This PowerShell script is released under the MIT license http://www.opensource.org/licenses/MIT
    #>
    [OutputType([Boolean])]
    [CmdletBinding()]
    param
    (
        [String] [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        $ServerName,

        [String] [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        $DatabaseName
    )

    try {
		# request a list of databases on the SSAS server. If the server does not exist, it will return an empty string
        $returnResult = Invoke-ASCmd -Server $ServerName -ConnectionTimeout 1 -Query "<Discover xmlns='urn:schemas-microsoft-com:xml-analysis'><RequestType>DBSCHEMA_CATALOGS</RequestType><Restrictions /><Properties /></Discover>";

        if ([string]::IsNullOrEmpty($returnResult)) {
			return $false;
		} else {
            $returnXml = New-Object -TypeName System.Xml.XmlDocument;
            $returnXml.LoadXml($returnResult);

            [System.Xml.XmlNamespaceManager] $nsmgr = $returnXml.NameTable;
            $nsmgr.AddNamespace('xmlAnalysis', 	'urn:schemas-microsoft-com:xml-analysis');
            $nsmgr.AddNamespace('rootNS', 		'urn:schemas-microsoft-com:xml-analysis:rowset');

            $rows = $returnXML.SelectNodes("//xmlAnalysis:DiscoverResponse/xmlAnalysis:return/rootNS:root/rootNS:row/rootNS:DATABASE_ID", $nsmgr) ;
            foreach ($row in $rows) {
               $FoundDb = $row.InnerText;
               if ($FoundDb -eq  $DatabaseName) {
                    return $true;
               }
            }
            return $false;
        }
    }
    catch {
        Write-Warning "Error $_";
        return $false;
    }
}