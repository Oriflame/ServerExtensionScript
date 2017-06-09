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

if (!(test-path C:\logs)) {mkdir C:\logs }

$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Definition)
$currentScriptFolder = [System.IO.Path]::GetDirectoryName($MyInvocation.MyCommand.Definition)
$logFile = "c:\logs\$scriptName.txt"
"Current folder $currentScriptFolder" | Out-File $logFile
Add-Type -AssemblyName System.IO.Compression.FileSystem

try
{    
    "Enabling Samba" | Out-File $logFile -Append
    netsh advfirewall firewall set rule group="File and Printer Sharing" new enable=Yes 

    $sasDecoded = [System.Text.Encoding]::ASCII.GetString([System.Convert]::FromBase64String($SAS))

    "Server environment: $serverEnv" | Out-File $logFile -Append
    "Server region: $serverRegion" | Out-File $logFile -Append
    "Server role: $serverRole" | Out-File $logFile -Append
    "SAS token: $sasDecoded" | Out-File $logFile -Append
    
    #------------------------------------------------------------------
    if (!(test-path C:\OSEL)) {mkdir C:\OSEL }
    "save aprameters as config file c:\OSEL\config.json" | Out-File $logFile -Append
    @{env=$serverEnv;region=$serverRegion;role=$serverRole;SAS=$SAS} | ConvertTo-Json | Out-File "c:\OSEL\config.json"
    #------------------------------------------------------------------
    "download website" | Out-File $logFile -Append
    if (!(test-path C:\TEMP\website)) {mkdir C:\TEMP\website }
    $installFileUrl = "https://oriflamestorage.blob.core.windows.net/onlineassets/$serverEnv/Website.zip" + $sasDecoded    
    (New-Object System.Net.WebClient).DownloadFile($installFileUrl, 'c:\TEMP\Website.zip')    
    "unzip website to C:\temp\website\" | Out-File $logFile -Append
    Unzip "c:\TEMP\Website.zip" "C:\temp\website\"
    #------------------------------------------------------------------
    "download index" | Out-File $logFile -Append
    if (!(test-path C:\TEMP\index)) {mkdir C:\TEMP\index }
    $installFileUrl = "https://oriflamestorage.blob.core.windows.net/onlineassets/$serverEnv/index.zip" + $sasDecoded    
    (New-Object System.Net.WebClient).DownloadFile($installFileUrl, 'c:\TEMP\index.zip')    
    "unzip website to C:\temp\index\" | Out-File $logFile -Append
    Unzip "c:\TEMP\index.zip" "C:\temp\index\"
    #------------------------------------------------------------------
    "download OSEL" | Out-File $logFile -Append    
    $installFileUrl = "https://oriflamestorage.blob.core.windows.net/onlineassets/$serverEnv/OSEL.ZIP" + $sasDecoded    
    (New-Object System.Net.WebClient).DownloadFile($installFileUrl, 'c:\OSEL\OSEL.ZIP')    
    "unzip OSEL" | Out-File $logFile -Append
    Unzip "c:\OSEL\OSEL.zip" "C:\"    
    "run OSEL init-server.ps1" | Out-File $logFile -Append    
    Set-Location c:\OSEL\StandAloneScripts\ServerSetup\
    Get-Process C:\OSEL\StandAloneScripts\ServerSetup\init-server.ps1     

}
catch
{
	"An error ocurred: $_" | Out-File $logFile -Append
}
