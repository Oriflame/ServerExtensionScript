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
        return $secret.Value | ConvertFrom-Json
    }
}

# back compatibility

function SelectMostMatchingOnly( $dict, $key, $suffix )
{
    $bestkey = "$key-$suffix" #shared pattern
    LogToFile "Key=$key, Sfx=$suffix, Best=$bestkey"
    LogToFile "Dict=$dict"
    
    LogToFile "Looking for [$bestkey]"
    if ( $dict.Contains($bestkey) ) 
    {
        LogToFile "Specific key found [$bestkey]: $($dict[$bestkey])"
        LogToFile "Replacing value [$key]: $($dict[$key])"
        $dict[$key] = $dict[$bestkey]
    } else {
        LogToFile "Common key used [$key]:  $($dict[$key])"
    }

    #remove all 
    $toremove = $dict.Keys | ?{ $_ -like "$key-*" }
    $toremove | %{ 
            LogToFile "Removing [$_]"
            $dict.Remove($_) 
        }
}


function Set-v10_Environment( $serverSetup )
{
    SelectMostMatchingOnly $serverSetup "BlobStorage" $serverSetup.serverRole

    LogToFile "Setup config: $($serverSetup | Out-String)" 

    if ( !$setup.serverEnv -or !$setup.SASToken )
    {
        throw "Mandatory parameters 'serverEnv' or 'SASToken' are not provided."
    }

    $rootStgContainer = "https://oriflamestorage.blob.core.windows.net/onlineassets"
    $cfgJson = "config.json"

    LogToFile "saving parameters as config file $oselDir\$cfgJson" 
    $serverSetup | 
        ConvertTo-Json | 
        Out-File "$oselDir\$cfgJson"

    $serverSetup.RootStgContainer =  $rootStgContainer    
}


function Set-v20_Environment( $serverSetup )
{
    if ( !$serverSetup.VaultName -or !$serverSetup.SecretName -or !$serverSetup.ServerEnv )
    {
        throw "Mandatory parameters: ['VaultName', 'ServerEnv'] are not provided."
    }

    $armcontainer = Get-ARMContainer -vaultName $serverSetup.VaultName -secretName $serverSetup.SecretName
    if ( !$armcontainer )
    {
        throw "SAS token not found - check [$($serverSetup.VaultName) >> $($serverSetup.SecretName)] for apropriate secret."
    }

    $serverSetup.RootStgContainer = $armcontainer.Uri
    $serverSetup.SasToken = $armcontainer.SAS 
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

#enable samba    
    # LogToFile "Enabling Samba" 
    # netsh advfirewall firewall set rule group="File and Printer Sharing" new enable=Yes

#download resource storage
    if (!(test-path $oselDir)) {mkdir $oselDir }

# file version
    switch ( $setup.Version )
    {
        "1.0" { #version with secures in serversetup (expected config.json) 
            $setup.octopusEnv=$octopusEnv 
            $setup.serverRole=$serverRole.ToLower()
            $setup.octopusRole=$octopusRole
            Set-v10_Environment $setup
         }
        "2.0" { #version with keyvault
            Set-v20_Environment $setup
         }
        default { 
            throw "Unknown Server Setup version: [$($setup.Version)] "
        } 
    }


#enable samba    
    # LogToFile "Enabling Samba" 
    # netsh advfirewall firewall set rule group="File and Printer Sharing" new enable=Yes


#download resource storage
    $url = ($setup.RootStgContainer, $setup.serverEnv, $oselRes) -join "/"
    $oselZip = "$oselDir\$oselRes"
    LogToFile "downloading OSEL: $url ($([bool]$setup.SasToken) >> $oselZip" 
    (New-Object System.Net.WebClient).DownloadFile("$url$($setup.SASToken)", $oselZip )

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
