[CmdletBinding()]
param
(
    [Parameter(Mandatory=$true)] [string]$setupB64json
)

#region CONSTANTS
    $startupDir = "C:\~init"
    $logDir     = "C:\logs\ARM"
    $separator  = "~" * 50
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

function DownloadStartupPackage( $remotePackage, $targetDir)
{
    LogToFile "Startup Package ... " 
    
    $tempzip = "D:\startup.zip"
    $u = [uri]$remotePackage
    LogToFile "Download Startup Package $($u.Scheme)://$($u.Host)$($u.AbsolutePath) ..." 
    (New-Object System.Net.WebClient).DownloadFile( $remotePackage, $tempzip )

    LogToFile "Unziping Startup Package to [$targetDir] ... "  
    Expand-Archive -LiteralPath $tempzip -DestinationPath $targetDir

    $startup = Join-Path $targetDir "startup.ps1"
    if ( Test-Path( $startup ) )
    {
        LogToFile "Exec [$startup] ... "
        LogToFile $separator
        &$startup >> $logFile
        LogToFile $separator
    }

    LogToFile "Startup Done" 
}

function InstallChocoPackages ( $chocoPackages )
{
    LogToFile "Choco install ..."
    LogToFile $separator

    $chocoout = Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
    LogToFile "$chocoout" 

    LogToFile $separator
    LogToFile "Done (Choco)" 

    LogToFile "Choco packages ..." 
    foreach( $p in $chocoPackages )
    {
        LogToFile "choco install -y $p - Execution:"
        LogToFile $separator
        &choco install -y ($p -split " ") >> $logFile
        LogToFile $separator
        LogToFile "choco [$p] - Finished"
    }

    LogToFile "Choco Done" 
}



#start
    LogToFile "Current folder $currentScriptFolder" 

try
{

#region Decode Parameter
    $setupJson = [System.Text.Encoding]::ASCII.GetString([System.Convert]::FromBase64String($setupB64json))
    $setup = @{}
    (ConvertFrom-Json $setupJson).psobject.properties | %{ $setup[$_.Name] = $_.Value }
#endregion (decode)

#enable samba    
    LogToFile "Enabling Samba" 
    netsh advfirewall firewall set rule group="File and Printer Sharing" new enable=Yes

#enable execution    
    LogToFile "Enabling Execution Policy" 
    Set-ExecutionPolicy Unrestricted -Scope Process -Force       #Bypass -Scope Process -Force 

#exec choco
    if ( $setup.ChocoPackages )
    {
        InstallChocoPackages $setup.ChocoPackages
    }
    
#exec startup    
    if ( $setup.StartupPackage )
    {
        DownloadStartupPackage $setup.StartupPackage $startupDir
    }

#done    
    LogToFile "Done" 
}
catch
{
	LogToFile "An error ocurred: $_" 
}
