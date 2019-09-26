[CmdletBinding()]
param
(
    [Parameter(Mandatory=$true)] [string]$groupName,
    [Parameter(Mandatory=$true)] [string] $credB64json
)

#region CONSTANTS
    $logDir = "C:\logs\ARM"
    if (!(test-path $logDir)) { mkdir $logDir | Out-Null }

    $scriptName = ([System.IO.FileInfo]$MyInvocation.MyCommand.Definition).BaseName    
    $logFile = "$logDir\$scriptName.txt"
#endregion

#region Logging
function LogToFile( [string] $text )
{
    $msg = "$(Get-Date -Format s): $text" 
    Write-Output $msg
    $msg | Out-File $logFile -Append
}
#endregion

function RegisterPSModules()
{
    LogToFile( "RegisterPSModules")
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
    Install-Module AzureAD -Force     
}

function Add-ToAadGroup( [string] $groupName, [string] $computerName, [pscredential] $credential ) 
{    
    LogToFile( "Connect-AzureAD as $($credential.UserName)")       

    Connect-AzureAD -Credential $credential | Out-Null

    $aadGroup = (Get-AzureADGroup -SearchString $groupName | Select-Object -First 1)
    if ( !$aadGroup ) { throw "Group [$groupName] does not exist in Azure AD" }
    
    $aadComputerPrincipal = (Get-AzureADServicePrincipal -SearchString $computerName)
    if ( !$aadComputerPrincipal ) { throw "Server Principal [$computerName] does not exist in Azure AD - check MSI (Managed service identity) is ON" }

    foreach( $principal in $aadComputerPrincipal.ObjectId ) {
        LogToFile( "Adding machine principal $computerName[$principal] to $groupName[$($aadGroup.objectid)] ... ")       
        Add-AzureADGroupMember -ObjectId $aadGroup.objectid -RefObjectId $principal    
    }
    LogToFile( "... OK")
}

##### Main #####

try {
    LogToFile( "[$scriptName] Started: ... ")
    #LogToFile( "Par: $credB64json")
    
    $techAccount = [System.Text.Encoding]::ASCII.GetString([System.Convert]::FromBase64String($credB64json)) | 
                        ConvertFrom-Json
    
    if ( !$techAccount.User -or !$techAccount.Password )
    {
        throw "Missing mandatory credential parameters"
    }

    RegisterPSModules    

    $credential = New-Object System.Management.Automation.PSCredential($techAccount.User, (ConvertTo-SecureString -String $techAccount.Password -AsPlainText -Force))
    Add-ToAadGroup -groupName $groupName -computerName $env:ComputerName -credential $credential        

    LogToFile( "[$scriptName] Done")    
}
catch {
    LogToFile( "[$scriptName] Error: $_")
}
