[CmdletBinding()]
param
(
    [Parameter(Mandatory=$true)] [string]$serverEnv,
    [Parameter(Mandatory=$true)] [string]$octopusEnv,
    [Parameter(Mandatory=$true)] [string]$serverRegion,
    [Parameter(Mandatory=$true)] [string]$serverRole,
    [Parameter(Mandatory=$true)] [string]$SAS,
    [Parameter(Mandatory=$true)] [string]$redisCache,
#    [Parameter(Mandatory=$true)] [string]$serviceBus,
    [Parameter(Mandatory=$true)] [string]$blobStorage
)

#region CONSTANTS
    $logDir = "C:\logs"
    $oselDir = "c:\OSEL"
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

function InstallFeatures()
{
	LogToFile "Prerequisite: IIS-ASPNET45";
	dism /online /enable-feature /all /featurename:IIS-ASPNET45 /NoRestart

	LogToFile "Prerequisite: NetFx4ServerFeatures";
	dism /online /get-featureinfo /featurename:NetFx4ServerFeatures
	LogToFile "Prerequisite: NetFx3ServerFeatures";
	dism /online /enable-feature /featurename:NetFx3ServerFeatures
	LogToFile "Prerequisite: NetFx3";
	dism /online /enable-feature /featurename:NetFx3

	$features = @(	"Web-ASP",
					"Web-CGI",
					"Web-ISAPI-Ext",
					"Web-ISAPI-Filter",
					"Web-Includes",
					"Web-HTTP-Errors",
					"Web-Common-HTTP",
					"Web-Performance",
					"Web-Basic-Auth",
					"Web-Http-Tracing",
					"Web-Stat-Compression",
					"Web-Http-Logging",
					"WAS",
					"Web-Dyn-Compression",
					"Web-Client-Auth",
					"Web-IP-Security",
					"Web-Url-Auth",
					"Web-Http-Redirect",
					"Web-Request-Monitor",
					"Web-Net-Ext45",
					"Web-Asp-Net45"
				)

	foreach( $f in $features )
	{
		LogToFile "Web Feature: $f ... ";
		 Get-WindowsFeature -Name $f | Where-Object InstallState -ne Installed | Install-WindowsFeature		
	}
}



#start
    LogToFile "Current folder $currentScriptFolder" 
    Add-Type -AssemblyName System.IO.Compression.FileSystem

try
{
#enable samba    
    # LogToFile "Enabling Samba" 
    # netsh advfirewall firewall set rule group="File and Printer Sharing" new enable=Yes

    $redisDecoded = [System.Text.Encoding]::ASCII.GetString([System.Convert]::FromBase64String($redisCache))
#    $svcbusDecoded = [System.Text.Encoding]::ASCII.GetString([System.Convert]::FromBase64String($serviceBus))
    $blobstgDecoded = [System.Text.Encoding]::ASCII.GetString([System.Convert]::FromBase64String($blobStorage))
    $sasDecoded = [System.Text.Encoding]::ASCII.GetString([System.Convert]::FromBase64String($SAS))
    $serverEnv = $serverEnv.Replace("_", " ")
    $octopusEnv = $octopusEnv.Replace("_", " ")
    $serverRole = $serverRole.Replace("_NA_", "")


    LogToFile "Server environment: $serverEnv" 
    LogToFile "Octopus environment: $octopusEnv" 
    LogToFile "Server region: $serverRegion" 
    LogToFile "Server role: $serverRole" 
    LogToFile "SAS token: $sasDecoded" 
    LogToFile "Redis Cache connection string: $redisDecoded" 
#    LogToFile "Service Bus connection string: $svcbusDecoded" 
    LogToFile "BLOB Storage connection string: $blobstgDecoded" 

#deploy mandatory features
    #InstallFeatures

#persist parameters in the Osel Dir
    if (!(test-path $oselDir)) {mkdir $oselDir }
    LogToFile "saving parameters as config file $oselDir\$cfgJson" 
    @{ env=$serverEnv;
       octopusEnv=$octopusEnv;
       region=$serverRegion;
       role=$serverRole;
       SAS=$SAS;
       RedisCache=$redisDecoded;
#       ServiceBus=$svcbusDecoded;
       BLOBStorage=$blobstgDecoded     
        } | 
        ConvertTo-Json | 
        Out-File "$oselDir\$cfgJson"

#download resource storage
    $url = "$rootStgContainer/$serverEnv/$oselRes"
    LogToFile "downloading OSEL: $url" 
    (New-Object System.Net.WebClient).DownloadFile("$url$sasDecoded", "$oselDir\$oselRes")

#unzip
    LogToFile "unziping OSEL to [$oselDir]"   
    [System.IO.Compression.ZipFile]::ExtractToDirectory("$oselDir\$oselRes", $oselDir)

#exec init-server    
    LogToFile "starting OSEL => .\init-server.ps1 -step new-server" 
    Set-Location "$oselDir\StandAloneScripts\ServerSetup\"
    .\init-server.ps1 -step new-server >> $logFile

#done    
    LogToFile "OSEL init-server finished" 
}
catch
{
	LogToFile "An error ocurred: $_" 
}
