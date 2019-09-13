[CmdletBinding()]
param
(
    [Parameter(Mandatory=$true)] [string]$setupB64json
)

#region CONSTANTS
    $logDir = "C:\logs\ARM"
    $oselDir = "c:\OSEL"
    $setupScript = "$oselDir\StandAloneScripts\ServerSetup\init-server.ps1"
    $oselRes = "osel.zip"
#endregion


#logging preparation
    if (!(test-path $logDir)) { mkdir $logDir | Out-Null }

    $scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Definition)
    $currentScriptFolder = [System.IO.Path]::GetDirectoryName($MyInvocation.MyCommand.Definition)
    $logFile = "$logDir\$scriptName.txt"

function LogToFile( [string] $text )
{
    $date = Get-Date -Format s
    "$($date): $text" | Out-File $logFile -Append
}

function Get-Token($resource, $identity)
{
    $authpar = @{ Uri = "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01" 
                  Body = @{resource="$resource"}
                  Headers = @{Metadata="true"}
                }
    if ( $identity ) { $authpar.Body["mi_res_id"] = $identity }
    $meta = Invoke-RestMethod @authpar
    $meta.access_token
}

#start
    LogToFile "Current folder $currentScriptFolder" 
    Add-Type -AssemblyName System.IO.Compression.FileSystem

try
{

#region Decode Parameter
    $setupJson = [System.Text.Encoding]::ASCII.GetString([System.Convert]::FromBase64String($setupB64json))
    $setup = @{
        # ServerEnv=$serverEnv.ToUpper()
        StorageAccount = "https://oriflamestorage.blob.core.windows.net"
        Container = "onlineassets"
        IdentityResID = "/subscriptions/bf92e86b-7b0b-4d78-8785-c104ce8ffaf4/resourceGroups/ArmCommon/providers/Microsoft.ManagedIdentity/userAssignedIdentities/onl-arm-identity"
    }
    (ConvertFrom-Json $setupJson).psobject.properties | %{ $setup[$_.Name] = $_.Value }
#endregion (decode)

#enable samba    
    # LogToFile "Enabling Samba" 
    # netsh advfirewall firewall set rule group="File and Printer Sharing" new enable=Yes

#download resource storage
    if (!(test-path $oselDir)) {mkdir $oselDir }

#enable samba    
    # LogToFile "Enabling Samba" 
    # netsh advfirewall firewall set rule group="File and Printer Sharing" new enable=Yes

#get Metadata
    $metadataurl = "http://169.254.169.254/metadata/instance/compute?api-version=2019-06-04"
    $meta = Invoke-RestMethod -Uri $metadataurl -Headers @{ Metadata="true" }
    $setup.ServerEnv=($meta.tagslist | ?{ $_.name -eq 'ServerEnv' }).value.ToUpper()

#download resource storage
    $url = ($setup.StorageAccount, $setup.Container, $setup.serverEnv, $oselRes) -join "/"
    $oselZip = "$oselDir\$oselRes"
    LogToFile "downloading OSEL: $url >> $oselZip" 

    $token = Get-Token $setup.StorageAccount $setup.IdentityResID
    $headers = @{Authorization="Bearer $token" 
                 "x-ms-version"="2019-02-02"}
    Invoke-WebRequest -Uri $url -Method GET -Headers $headers -OutFile $oselZip

#unzip
    LogToFile "unziping OSEL to [$oselDir]"   
    [System.IO.Compression.ZipFile]::ExtractToDirectory($oselZip, $oselDir)

#exec init-server    
    LogToFile "starting OSEL => .\$(Split-Path $setupScript -Leaf) -step new-server" 
    Set-Location (Split-Path $setupScript -Parent)
    &$setupScript -step new-server >> $logFile

#done    
    LogToFile "OSEL init-server finished" 
}
catch
{
	LogToFile "An error ocurred: $_" 
}
