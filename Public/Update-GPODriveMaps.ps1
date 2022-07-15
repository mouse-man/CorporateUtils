#requires -modules ActiveDirectory
<#
.SYNOPSIS
This script can go through a GPO Drives.xml file and update groups and their associated SID based on a group lookup table.

.DESCRIPTION
This script can go through a GPO Drives.xml file and update groups and their associated SID based on a group lookup table.
As this version will look up the SID in Active Directory, it requires the Active Directory PowerShell module installed.
It will store the output as a valid XML file in the same directory as it was read from, with a name that is suffixed with
-Remediated-Date-Time, i.e. c:\Temp\Drives-Remediated-15072022-024254.xml

.PARAMETER XMLFile
File path for a copy of the drives.xml file that will be used to run this against 

.PARAMETER MappingFile
File path for a mapping file. This needs to be in the following format:
SrcGroupName,GGroupName

.PARAMETER TargetDomain
Target Domain name

.NOTES
GPO XML Read code credit to https://x86x64.wordpress.com/2014/03/10/powershell-process-gpo-xml-files/

.EXAMPLE
Update-GPODriveMaps -XMLFile c:\Temp\Drives.xml -MappingFile c:\Temp\Mappingfile.csv -TargetDomain Contoso

#>
Param(
    [parameter(Mandatory=$true,Position=0)]
    [string]$XMLFile,
    [parameter(Mandatory=$true,Position=1)]
    [string]$MappingFile,
    [parameter(Mandatory=$true,Position=1)]
    [string]$TargetDomain
)
# You need to set the path to an XML file taken from the GPO:
[xml]$mappings = Get-Content $XMLFile
# Get the matching file contents
$GrpList = Import-Csv -Path $MappingFile
# Initialise the counter
$i = 0
#Seperate the data that we want to update
$m = $mappings | Select-XML -XPath "//Drive" | ForEach-Object {$_.node.InnerXML}
foreach($map in $m)
{
    # We have two tags <Properties> and <Filters>, lets separate them for further processing
    $tags = $map -split "<Filters>"
    # There is also one possible discrepancy with empty filters tag that is written in a shortened XML notation: <Filters />. And we need to deal with it.
    if ($tags[1])
    {
        if ($tags.Length -gt 1)
        {
            $tags[1] = "<Filters>" + $tags[1]
            $Filters = [xml]$tags[1]
        }
    }
    else
    {
        $tags[0] = $tags[0] -split "<Filters />"
        $FilStr = "<Filters></Filters>"
        $Filters = [xml]$FilStr
    }
    # Extracting Filterings:
    $FilterGroups= $Filters.SelectNodes("Filters/FilterGroup")
    foreach ($Group in $FilterGroups) { 
        #$Group.name
        #$Group.sid
        try{
        $GrpNum = [System.Array]::FindIndex($GrpList.srcgroupname,[Predicate[string]]{$args[0] -eq $($Group.name -split '\\')[1]})
        }
        catch{$i++;Continue}
        if($GrpNum -and ($GrpNum -ne -1)){
            $NewSid = (Get-ADGroup -identity $($GrpList.GGroupName[$GrpNum])).sid.value
            #Since the $group.name object has \, need to use \\ as matching string, but is used literally for the string to replace it with
            $mappings.Drives.Drive.Filters.FilterGroup[$i].Name = [string]$($FilterGroups.name -replace "$($group.name -replace '\\','\\')","$TargetDomain\$($GrpList.GGroupName[$GrpNum])")
            $mappings.Drives.Drive.Filters.FilterGroup[$i].sid = $NewSid
        }
        $i++
    }
}
$RemediatedPath = "$(Split-Path $XMLFile -Parent)\$(((Split-Path $XMLFile -leaf) -split '\.')[-2])-Remediated-$(get-date -format "ddMMyyyy-hhmmss").xml"
$mappings.Save($RemediatedPath)
