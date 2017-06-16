[CmdletBinding()]
param
(	
)

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

try
{    
    LogToFile "Enabling Samba" $logFile
    netsh advfirewall firewall set rule group="File and Printer Sharing" new enable=Yes 
    
    LogToFile "installing WinServer features" $logFile
    dism /online /get-featureinfo /featurename:NetFx4ServerFeatures
    dism /online /enable-feature /all /featurename:IIS-ASPNET45 /NoRestart
    dism /online /enable-feature /featurename:NetFx3ServerFeatures

    $features = @("Web-ASP","Web-CGI","Web-ISAPI-Ext","Web-ISAPI-Filter",
        "Web-Includes","Web-HTTP-Errors","Web-Common-HTTP",
        "Web-Performance","Web-Basic-Auth","Web-Http-Tracing",
        "Web-Stat-Compression","Web-Http-Logging","WAS",
        "Web-Dyn-Compression","Web-Client-Auth","Web-IP-Security",
        "Web-Url-Auth","Web-Http-Redirect","Web-Request-Monitor",
        "Web-Net-Ext45","Web-Asp-Net45" )

    foreach ($f in $features)
    {
        Get-WindowsFeature -Name $f | Where InstallState -ne Installed | Install-WindowsFeature	    
    }
    LogToFile "WinServer features installed" $logFile
    LogToFile "Starting sysprep" $logFile
    Start-Process -FilePath C:\Windows\System32\Sysprep\Sysprep.exe -ArgumentList '/generalize /oobe /shutdown /quiet'
    LogToFile "Started sysprep" $logFile

}
catch
{
	LogToFile "An error ocurred: $_" $logFile
}
