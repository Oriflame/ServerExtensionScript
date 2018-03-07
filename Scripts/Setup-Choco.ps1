[CmdletBinding()]
param
(
    [Parameter(Mandatory=$true)] [string]$setupB64json
)

#region CONSTANTS
    $logDir = "C:\logs\ARM"
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

#start
    LogToFile "Current folder $currentScriptFolder" 

try
{

#region Decode Parameter
    $setupJson = [System.Text.Encoding]::ASCII.GetString([System.Convert]::FromBase64String($setupB64json))
    $setup = @{
    }
    (ConvertFrom-Json $setupJson).psobject.properties | %{ $setup[$_.Name] = $_.Value }
#endregion (decode)

#enable samba    
    LogToFile "Enabling Samba" 
    netsh advfirewall firewall set rule group="File and Printer Sharing" new enable=Yes

#exec nuget
    LogToFile "Choco install ..."
    
    Set-ExecutionPolicy Bypass -Scope Process -Force 
    $chocoout = Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
    LogToFile "$chocoout" 

    LogToFile "Done (Choco)" 

    LogToFile "Choco packages ..." 
    if ( $setup.Packages )
    {
        foreach( $p in $setup.Packages )
        {
            LogToFile "choco install -y $p - Execution:"
            LogToFile "~"*50
            &choco install -y $p >> $logFile
            LogToFile "~"*50
            LogToFile "choco [$p] - Finished"
        }
    }
    LogToFile "Done (Packages)" 

#done    
    LogToFile "Done" 
}
catch
{
	LogToFile "An error ocurred: $_" 
}
