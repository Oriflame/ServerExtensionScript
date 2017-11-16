[CmdletBinding()]
param
(
    [Parameter(Mandatory=$false)] [string]$serverRole,
    [Parameter(Mandatory=$true)]  [string]$serverEnv,
    [Parameter(Mandatory=$false)] [string]$octopusEnv,
    [Parameter(Mandatory=$false)] [string]$octopusRole,

    [Parameter(Mandatory=$true)] [string]$setupB64json
)

#region CONSTANTS
    $logDir = "C:\logs\ARM"
    $oselDir = "c:\OSEL"
    $setupScript = "$oselDir\StandAloneScripts\ServerSetup\init-server.ps1"
    #$rootStgContainer = "https://oriflamestorage.blob.core.windows.net/onlineassets"
    $oselRes = "osel.zip"
    #$cfgJson = "config.json"
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

function Get-ARMContainer( $vaultName, $secretName )
{
    # get OAuth token
	$authpar = @{ Uri     = "http://localhost:50342/oauth2/token" 
                  Body    = @{resource="https://vault.azure.net"}
                  Headers = @{Metadata="true"}
                }
    $token = (Invoke-RestMethod @authpar).access_token
    LogToFile "Token $([bool]$token)"

    # get Vault Secret
    
    $kvpar = @{
        uri = "https://$vaultName.vault.azure.net/secrets/$($secretName)?api-version=2016-10-01"	   
        Headers = @{Authorization="Bearer $token"} 						      
    }
    
    $secret = (Invoke-RestMethod @kvpar)
    LogToFile "Secret '$secretName' ... $([bool]$secret)"
    if ( $secret )
    {
        return $secret.Value
    }
}



#start
    LogToFile "Current folder $currentScriptFolder" 
    Add-Type -AssemblyName System.IO.Compression.FileSystem

try
{

#region Decode Parameter
    $setupJson = [System.Text.Encoding]::ASCII.GetString([System.Convert]::FromBase64String($setupB64json))
    $setup = @{
        ServerEnv=$serverEnv.ToUpper()
    }
    (ConvertFrom-Json $setupJson).psobject.properties | %{ $setup[$_.Name] = $_.Value }
#endregion (decode)

#region obtain secrets    
    if ( !$setup.VaultName -or !$setup.SecretName -or !$setup.ServerEnv )
    {
        throw "Mandatory parameters: ['VaultName', 'ServerEnv'] are not provided."
    }

    $armcontainer = Get-ARMContainer -vaultName $setup.VaultName -secretName $setup.SecretName
    if ( !$armcontainer )
    {
        throw "SAS token not found - check [$($setup.VaultName) >> $($setup.SecretName)] for apropriate secret."
    }

    $setup.RootStgContainer = $armcontainer.Uri
    $setup.SasToken = $armcontainer.SAS
#endregion (secrets)  


#enable samba    
    # LogToFile "Enabling Samba" 
    # netsh advfirewall firewall set rule group="File and Printer Sharing" new enable=Yes

#download resource storage
    $url = "$($setup.RootStgContainer)/$($setup.serverEnv)/$oselRes"
    LogToFile "downloading OSEL: $url" 
    (New-Object System.Net.WebClient).DownloadFile("$url$($setup.SASToken)", "$oselDir\$oselRes")

#unzip
    LogToFile "unziping OSEL to [$oselDir]"   
    [System.IO.Compression.ZipFile]::ExtractToDirectory("$oselDir\$oselRes", $oselDir)

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
