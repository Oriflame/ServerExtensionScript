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

function Set-OriInitScriptProperty($name, $value)
{
	$path = "HKLM:\SOFTWARE\Oriflame\InitScript"

	LogToFile "Registry Set: $name >> $value"
	if (-not (Test-Path -Path $path))
	{
		New-Item -Path (Split-Path -Path $path) -Name (Split-Path -Path $path -Leaf) -Force | Out-Null
	}

	Set-ItemProperty -Path $path -Name $name -Value $value -ErrorAction Stop;
}

function Set-MetadataToRegistry($meta, $tags, $serversetup)
{
    Set-OriInitScriptProperty "vmAzureId"  $meta.resourceId
    Set-OriInitScriptProperty "vmTags"    ($tags | ConvertTo-Json)

    if ( $serverSetup.IdentityResID )
    {
        Set-OriInitScriptProperty "vmIdentity"    $serverSetup.IdentityResID
    }
    if ( $serverSetup.vaultname )
    {
        Set-OriInitScriptProperty "vaultname"     (($serverSetup.vaultname -replace 'https://') -split '\.')[0]
    }
    if ( $setup.UrlRoot )
    {
        Set-OriInitScriptProperty "UrlRoot"       $setup.UrlRoot
    }
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

function Invoke-WebhookJson( $url, $body )
{
    $jsbody = ConvertTo-Json $body
    LogToFile "POST $url >> `n$jsbody"
    $r = Invoke-RestMethod -Method POST -URI $url -Body $jsbody -Headers @{ 'Content-Type'='application/json' }
    LogToFile "Response: $($r | Out-String)"
}

function Invoke-WebhookAzure( $token, $data )
{
    Invoke-WebhookJson "https://s2events.azure-automation.net/webhooks?token=$token" $data
}


function Add-ToAadGroup( [string] $groupName, [string] $computerName, [pscredential] $credential ) 
{    
    LogToFile( "Connect-AzureAD as $($credential.UserName)")       

    Connect-AzureAD -Credential $credential | Out-Null

    $aadGroup = (Get-AzureADGroup -SearchString $groupName | Select-Object -First 1)
    if ( !$aadGroup ) { throw "Group [$groupName] does not exist in Azure AD" }
    
    $aadComputerPrincipal = (Get-AzureADServicePrincipal -SearchString $computerName)
    if ( !$aadComputerPrincipal ) { throw "Server Principal [$computerName] does not exist in Azure AD - check MSI (Managed service identity) is ON" }
    
    foreach( $principal in $aadComputerPrincipal.ObjectId ) {
        LogToFile( "Adding machine principal $computerName[$principal] to $groupName[$($aadGroup.objectid)] ... ")       
        Add-AzureADGroupMember -ObjectId $aadGroup.objectid -RefObjectId $principal    
    }

    LogToFile( "... OK")
}

function Invoke-AadScript([string] $secretUrl, [string] $identity )
{
    $secretUri = "$($secretUrl)?api-version=2016-10-01"
    LogToFile "AAD System based on $identity`: $secretUri"
    $token = Get-Token -resource "https://vault.azure.net" -identity $identity

    
    $s = Invoke-RestMethod -Uri $secretUri -Headers @{Authorization="Bearer $token"}
    # LogToFile "Value: $($s.Value)"
    $cmd = $s.Value -split ' '

    $groupName    = $cmd[$cmd.IndexOf("-groupName")  +1].Trim('"')
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

    try 
    {
        $credential = New-Object System.Management.Automation.PSCredential($techAccount.User, (ConvertTo-SecureString -String $techAccount.Password -AsPlainText -Force))
        Add-ToAadGroup -groupName $groupName -computerName $env:ComputerName -credential $credential                    
    }
    catch {
        LogToFile "IGNORED Add to AAD error: $_"        
    }
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

#OSEL directory
    if ( test-path $oselDir ) { Remove-Item -Recurse -Force $oselDir | Out-Null }
    mkdir $oselDir

#enable samba    
    # LogToFile "Enabling Samba" 
    # netsh advfirewall firewall set rule group="File and Printer Sharing" new enable=Yes

#get Metadata
    $metadataurl = "http://169.254.169.254/metadata/instance/compute?api-version=2019-06-04"
    $meta = Invoke-RestMethod -Uri $metadataurl -Headers @{ Metadata="true" }
    $tags = @{}
    $meta.tagslist | %{ $tags[$_.name] = $_.value }
    LogToFile "Tags: $($tags | ConvertTo-Json)"

    $setup.IdentityResID = @("/subscriptions", $meta.SubscriptionID, $rgidentity) -join "/"
    $setup.UrlRoot=@($setup.StorageAccount, $setup.Container, $tags.serverEnv.ToUpper()) -join "/"

    Set-MetadataToRegistry $meta $tags $setup

#ensure systemidentity membership
    Invoke-AadScript -secretUrl "$($setup.VaultName)secrets/$($setup.VaultSecretAAD)" -identity $setup.IdentityResID

#aad membership
    LogToFile "AAD registration"
    Invoke-WebhookAzure "TY80xVcP%2fU%2fVeitKM%2bhOhKsHzny2%2bFjyu82pAvEKG%2bI%3d" @{ computername=$env:COMPUTERNAME }

#download resource storage
    $url = ($setup.UrlRoot, $oselRes) -join "/"
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
