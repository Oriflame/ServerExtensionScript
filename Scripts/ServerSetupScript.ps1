[CmdletBinding()]
param
(
    [Parameter(Mandatory=$true)] [string]$serverEnv,
    [Parameter(Mandatory=$true)] [string]$octopusEnv,
    [Parameter(Mandatory=$true)] [string]$serverRegion,
    [Parameter(Mandatory=$true)] [string]$serverRole,

    [Parameter(Mandatory=$true)] [string]$setupB64json
)

#region CONSTANTS
    $logDir = "C:\logs"
    $oselDir = "c:\OSEL"
    $setupScript = "$oselDir\StandAloneScripts\ServerSetup\init-server.ps1"
    $rootStgContainer = "https://oriflamestorage.blob.core.windows.net/onlineassets"
    $oselRes = "osel.zip"
    $cfgJson = "config.json"
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

#start
    LogToFile "Current folder $currentScriptFolder" 
    Add-Type -AssemblyName System.IO.Compression.FileSystem

try
{

#region Decode Parameter
    $setupJson = [System.Text.Encoding]::ASCII.GetString([System.Convert]::FromBase64String($setupB64json))
    $setup = @{}
    (ConvertFrom-Json $setupJson).psobject.properties | Foreach { $setup[$_.Name] = $_.Value }

    $setup.env=$serverEnv #.Replace("_", " ")
    $setup.serverEnv=$setup.env
    $setup.octopusEnv=$octopusEnv #.Replace("_", " ")
    $setup.region=$serverRegion;
    $setup.role=$serverRole #.Replace("_NA_", "")
    $setup.SAS=[System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($setup.SASToken))

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
    $url = "$rootStgContainer/$($setup.env)/$oselRes"
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
