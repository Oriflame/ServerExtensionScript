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

if (!(test-path C:\logs)) {mkdir C:\logs }

$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Definition)
$currentScriptFolder = [System.IO.Path]::GetDirectoryName($MyInvocation.MyCommand.Definition)
$logFile = "c:\logs\$scriptName.txt"
"Current folder $currentScriptFolder" | Out-File $logFile

try
{    
    "Enabling Samba" | Out-File $logFile -Append
    netsh advfirewall firewall set rule group="File and Printer Sharing" new enable=Yes 

    $sasDecoded = [System.Text.Encoding]::ASCII.GetString([System.Convert]::FromBase64String($SAS))

    "Server environment: $serverEnv" | Out-File $logFile -Append
    "Server region: $serverRegion" | Out-File $logFile -Append
    "Server role: $serverRole" | Out-File $logFile -Append
    "SAS token: $sasDecoded" | Out-File $logFile -Append
    
    #download install script

}
catch
{
	"An error ocurred: $_" | Out-File $logFile -Append
}