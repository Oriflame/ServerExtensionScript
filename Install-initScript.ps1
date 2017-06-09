[CmdletBinding()]
param
(
	[Parameter(Mandatory=$true)]
	[string]$serverEnv,

    [Parameter(Mandatory=$true)]
	[string]$serverRegion,

    [Parameter(Mandatory=$true)]
	[string]$serverRole,

	[Parameter(Mandatory=$true)]
	[string]$SAS	
)

function Unzip
{
    param([string]$zipfile, [string]$outpath)

    [System.IO.Compression.ZipFile]::ExtractToDirectory($zipfile, $outpath)
}
function LogToFile
{
    param([string]$text, [string]$logFile)
    $date = Get-Date -Format s
    "$date : $text" | Out-File $logFile -Append
}

if (!(test-path C:\logs)) {mkdir C:\logs }

$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Definition)
$currentScriptFolder = [System.IO.Path]::GetDirectoryName($MyInvocation.MyCommand.Definition)
$logFile = "c:\logs\$scriptName.txt"

LogToFile "Current folder $currentScriptFolder" $logFile
Add-Type -AssemblyName System.IO.Compression.FileSystem

try
{    
    LogToFile "Enabling Samba" $logFile
    netsh advfirewall firewall set rule group="File and Printer Sharing" new enable=Yes 

    $sasDecoded = [System.Text.Encoding]::ASCII.GetString([System.Convert]::FromBase64String($SAS))

    LogToFile "Server environment: $serverEnv" $logFile
    LogToFile "Server region: $serverRegion" $logFile
    LogToFile "Server role: $serverRole" $logFile
    LogToFile "SAS token: $sasDecoded" $logFile
    
    #------------------------------------------------------------------
    if (!(test-path C:\OSEL)) {mkdir C:\OSEL }
    LogToFile "saveing aprameters as config file c:\OSEL\config.json" $logFile
    @{env=$serverEnv;region=$serverRegion;role=$serverRole;SAS=$SAS} | ConvertTo-Json | Out-File "c:\OSEL\config.json"
    #------------------------------------------------------------------
    LogToFile "downloading website" $logFile
    if (!(test-path C:\TEMP\website)) {mkdir C:\TEMP\website }
    $installFileUrl = "https://oriflamestorage.blob.core.windows.net/onlineassets/$serverEnv/Website.zip" + $sasDecoded    
    (New-Object System.Net.WebClient).DownloadFile($installFileUrl, 'c:\TEMP\Website.zip')    
    LogToFile "unziping website to C:\temp\website\" $logFile
    Unzip "c:\TEMP\Website.zip" "C:\temp\website\"
    #------------------------------------------------------------------
    LogToFile "downloading index" $logFile
    if (!(test-path C:\TEMP\index)) {mkdir C:\TEMP\index }
    $installFileUrl = "https://oriflamestorage.blob.core.windows.net/onlineassets/$serverEnv/index.zip" + $sasDecoded    
    (New-Object System.Net.WebClient).DownloadFile($installFileUrl, 'c:\TEMP\index.zip')    
    LogToFile "unziping index to C:\temp\index\" $logFile
    Unzip "c:\TEMP\index.zip" "C:\temp\index\"
    #------------------------------------------------------------------
    LogToFile "downloading OSEL" $logFile    
    $installFileUrl = "https://oriflamestorage.blob.core.windows.net/onlineassets/$serverEnv/OSEL.ZIP" + $sasDecoded    
    (New-Object System.Net.WebClient).DownloadFile($installFileUrl, 'c:\OSEL\OSEL.ZIP')    
    LogToFile "unziping OSEL" $logFile
    Unzip "c:\OSEL\OSEL.zip" "C:\"    
    LogToFile "runing OSEL init-server.ps1" $logFile    
    Set-Location c:\OSEL\StandAloneScripts\ServerSetup\
    Get-Process C:\OSEL\StandAloneScripts\ServerSetup\init-server.ps1     
    LogToFile "OSEL init finished" $logFile
}
catch
{
	LogToFile "An error ocurred: $_" $logFile
}
