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
    $rgidentity = "resourceGroups/ArmCommon/providers/Microsoft.ManagedIdentity/userAssignedIdentities/onl-arm-identity"
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

function Get-ServerSetup($b64json)
{
    try {    
        $setupJson = [System.Text.Encoding]::ASCII.GetString([System.Convert]::FromBase64String($b64json))
        LogToFile "B64 decode: $setupJson" 
        $setup = @{}
        (ConvertFrom-Json $setupJson).psobject.properties | %{ $setup[$_.Name] = $_.Value }
        return $setup
    }
    catch {
        LogToFile "B64 decode [$b64json]`nERROR: $_" 
    }

    # fallback
    $setup = @{ 
        Version = '3.0'
        StorageAccount = "https://oriflamestorage.blob.core.windows.net"
        Container = "onlineassets"
        # temprary usage before the manage identity will be referenced by OSEL
        VaultName = "https://onlinetestarmvault.vault.azure.net/"                                       
        VaultSecretAAD="add-aadGroup"
    }      
}

function Add-ToAadGroup( [string] $groupName, [string] $computerName, [pscredential] $credential ) 
{    
    LogToFile( "Connect-AzureAD as $($credential.UserName)")       

    Connect-AzureAD -Credential $credential | Out-Null

    $aadGroup = (Get-AzureADGroup -SearchString $groupName | Select-Object -First 1)
    if ( !$aadGroup ) { throw "Group [$groupName] does not exist in Azure AD" }
    
    $aadComputerPrincipal = (Get-AzureADServicePrincipal -SearchString $computerName | Select-Object -First 1)
    if ( !$aadComputerPrincipal ) { throw "Server Principal [$computerName] does not exist in Azure AD - check MSI (Managed service identity) is ON" }

    $parAdd = @{
        ObjectId    = $aadGroup.objectid 
        RefObjectId = $aadComputerPrincipal.objectid
    }       
    LogToFile( "Adding machine $computerName[$($parAdd.RefObjectId)] to $groupName[$($parAdd.ObjectId)] ... ")       
    Add-AzureADGroupMember @parAdd
    LogToFile( "... OK")
}

function Invoke-aadScript
{
    param(
        [string] $vault,
        [string] $secret,
        [string] $identity
    )

    $secretUri = "$($vault)secrets/$($secret)?api-version=2016-10-01"
    LogToFile "AAD System based on $identity`: $secretUri"
    $token = Get-Token -resource "https://vault.azure.net" -identity $identity

    
    $s = Invoke-RestMethod -Uri $secretUri -Headers @{Authorization="Bearer $token"}
    # LogToFile "Value: $($s.Value)"
    $cmd = $s.Value -split ' '

    $groupName = $cmd[$cmd.IndexOf("-groupName")+1].Trim('"')
    $credB64json  = $cmd[$cmd.IndexOf("-credB64json")+1]    
    $techAccount = [System.Text.Encoding]::ASCII.GetString([System.Convert]::FromBase64String($credB64json)) | 
                        ConvertFrom-Json
    if ( !$techAccount.User -or !$techAccount.Password )
    {
        throw "Missing mandatory credential parameters"
    }                        

    # LogToFile( "RegisterPSModules")
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
    Install-Module AzureAD -Force     

    $credential = New-Object System.Management.Automation.PSCredential($techAccount.User, (ConvertTo-SecureString -String $techAccount.Password -AsPlainText -Force))
    Add-ToAadGroup -groupName $groupName -computerName $env:ComputerName -credential $credential        
} 


#start
    LogToFile "Current folder $currentScriptFolder" 
    Add-Type -AssemblyName System.IO.Compression.FileSystem

try
{

#region Decode Parameter
    $setup = Get-ServerSetup -b64json $setupB64json

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
    LogToFile "Metadata: $($meta.tagsList | Out-String)"
    $setup.ServerEnv=($meta.tagslist | ?{ $_.name -eq 'ServerEnv' }).value.ToUpper()
    $setup.IdentityResID = @("/subscriptions", $meta.SubscriptionID, $rgidentity) -join "/"

#ensure systemidentity membership
    Invoke-aadScript -vault $setup.VaultName -secret $setup.VaultSecretAAD -identity $setup.IdentityResID

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
