if (!(test-path C:\logs)) {mkdir C:\logs }

$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Definition)
$currentScriptFolder = [System.IO.Path]::GetDirectoryName($MyInvocation.MyCommand.Definition)
$logFile = "c:\logs\$scriptName.txt"
"Current folder $currentScriptFolder" | Out-File $logFile

try
{
    #"Enabling Samba" | Out-File $logFile -Append
    #netsh advfirewall firewall set rule group="File and Printer Sharing" new enable=Yes 

    #download install script

}
catch
{
	"An error ocurred: $_" | Out-File $logFile -Append
}