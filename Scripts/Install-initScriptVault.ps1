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
    $logDir = "C:\logs"
    $oselDir = "c:\OSEL"
    $setupScript = "$oselDir\StandAloneScripts\ServerSetup\init-server.ps1"
    $rootStgContainer = "https://oriflamestorage.blob.core.windows.net/onlineassets"
    $oselRes = "osel.zip"
    $cfgJson = "config.json"

    $schedulerTaskLog   = "$logDir\Vault.Task.txt"
    $vaultScheduledTask = "LocalVaultSetup"
    $vaultURLTarget     = "http://*.vault.azure.net/"
        # UserName contains azure KV name e.g. "onlinetestarmvault" (used as dynamic vault in next step)
        # Password contains azure App_ID
    #dynamic vault
        #username = $aadClientId 
        #password = $aadClientSecret 

#endregion


#logging preparation
    if (!(test-path $logDir)) { mkdir $logDirs | Out-Null }

    $scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Definition)
    $currentScriptFolder = [System.IO.Path]::GetDirectoryName($MyInvocation.MyCommand.Definition)
    $logFile = "$logDir\$scriptName.txt"

function LogToFile( [string] $text )
{
    $date = Get-Date -Format s
    "$($date): $text" | Out-File $logFile -Append
}

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


function RegisterPSModules()
{
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
    Install-Module CredentialManager -Force     
}

function RegisterLocalVaultKey( $localTargetUrl, $vaultName, $aadClientId, $aadClientSecret, $persist = "LocalMachine" )
{
    if ( !$localTargetUrl -or !$vaultName -or !$aadClientId -or !$aadClientSecret )
    {
        LogToFile "All Valut parameters are mandatory - NO Vault modification performed";    
        return;
    }


    # tmp ps1 generator ... iniline command is not sufficient, scheduled task has limit for TR length
    $tmpps = Join-Path $env:temp "$([guid]::NewGuid().ToString()).ps1"
@"
      "Executed: `$(Get-Date)" >> $schedulerTaskLog
      try {
        `$sp = ConvertTo-SecureString `"dummy`" -AsPlainText -Force    
        New-StoredCredential -Target `"$localTargetUrl`" -UserName `"$vaultName`" -SecurePassword `$sp -Persist $persist >> $schedulerTaskLog 
        `$sp = ConvertTo-SecureString `"$aadClientSecret`" -AsPlainText -Force        
        New-StoredCredential -Target `"$vaultName`" -UserName `"$aadClientId`" -SecurePassword `$sp -Persist $persist >> $schedulerTaskLog 
      } catch {
        `$_.Exception.Message >> $schedulerTaskLog   
      } finally {
         Remove-Item `$MyInvocation.MyCommand.Definition -Force >> $schedulerTaskLog
      }
"@ >> $tmpps

    $tr = "powershell.exe -File $tmpps"

    $callParams = @("/Create", 
                    "/TN", $vaultScheduledTask, 
                    "/SC", "once", 
                    "/ST", "23:59", 
                    "/TR", ($tr -replace '"', '\"'), 
                    "/F", #force creation
		            "/Z", #marks for deletion after its final run
		            "/V1",
                    "/RU", "System" 	#run under the system account
		            )
    
    LogToFile "Scheduling $tr [$callParams] ... (its log file: $schedulerTaskLog)"
    & schtasks $callParams
    LogToFile "Executing $tr ... ";
    & schtasks /run /tn $vaultScheduledTask
}

function UpdateVault( $setup )
{
    RegisterPSModules

    $vaultName = $setup.Vault_Name;
    # if ( $vaultName ) { $setup.Vault_Name = '~~ xxx ~~'  }

    $aadClientId = $setup.Vault_aadClientId;
    if ( $aadClientId ) { $setup.Vault_aadClientId = '~~ xxx ~~'  }

    $aadClientSecret = $setup.Vault_aadClientSecret;
    if ( $aadClientSecret ) { $setup.Vault_aadClientSecret = '~~ xxx ~~'  }

    RegisterLocalVaultKey $vaultURLTarget $vaultName $aadClientId $aadClientSecret
}



#start
    LogToFile "Current folder $currentScriptFolder" 
    Add-Type -AssemblyName System.IO.Compression.FileSystem

try
{

#region Decode Parameter
    $setupJson = [System.Text.Encoding]::ASCII.GetString([System.Convert]::FromBase64String($setupB64json))
    $setup = @{}
    (ConvertFrom-Json $setupJson).psobject.properties | Foreach { $setup[$_.Name] = $_.Value }

    #$setup.env=$serverEnv 
    $setup.serverEnv=$serverEnv.ToUpper()
    $setup.octopusEnv=$octopusEnv 
    $setup.serverRole=$serverRole.ToLower()
    $setup.octopusRole=$octopusRole 

    #select valid BlobStorage
    SelectMostMatchingOnly $setup "BlobStorage" $serverRole

    # credentials save
    UpdateVault $setup

    LogToFile "Setup config: $($setup | Out-String)" 

    #check mandatory parameters
    if ( !$setup.serverEnv -or !$setup.SASToken )
    {
        throw "Mandatory parameters 'serverEnv' or 'SASToken' are not provided."
    }

#endregion



#enable samba    
    # LogToFile "Enabling Samba" 
    # netsh advfirewall firewall set rule group="File and Printer Sharing" new enable=Yes

#persist parameters in the Osel Dir
    if (!(test-path $oselDir)) {mkdir $oselDir }
    LogToFile "saving parameters as config file $oselDir\$cfgJson" 
    $setup | 
        ConvertTo-Json | 
        Out-File "$oselDir\$cfgJson"

#download resource storage
    $url = "$rootStgContainer/$($setup.serverEnv)/$oselRes"
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