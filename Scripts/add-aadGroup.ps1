[CmdletBinding()]
param
(
    [Parameter(Mandatory=$true)] [string]$groupName,
    [Parameter(Mandatory=$true)] [string] $credB64json
    # [Parameter(Mandatory=$true)] [string]$techName,
    # [Parameter(Mandatory=$true)] [string]$techPassword
)

#region CONSTANTS
    $scriptName = ([System.IO.FileInfo]$MyInvocation.MyCommand.Definition).BaseName
    $logFile = "C:\logs\$scriptName.txt"
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
    
    $aadComputerPrincipal = (Get-AzureADServicePrincipal -SearchString $computerName | Select-Object -First 1)
    if ( !$aadComputerPrincipal ) { throw "Server Principal [$computerName] does not exist in Azure AD - check MSI (Managed service identity) is ON" }

    $parAdd = @{
        ObjectId    = $aadGroup.objectid 
        RefObjectId = $aadComputerPrincipal.objectid
    }       
    LogToFile( "Adding machine $computerName[$($parAdd.RefObjectId)] to $groupName[$($parAdd.ObjectId)] ... ")       
    Add-AzureADGroupMember @parAdd
    LogToFile( "... OK")
}

##### Main #####

try {
    LogToFile( "[$scriptName] Started: ... ")
    LogToFile( "Par: $credB64json")
    
    $techAccount = [System.Text.Encoding]::ASCII.GetString([System.Convert]::FromBase64String($credB64json)) | 
                        ConvertFrom-Json
    
    if ( !$techAccount.User -or !$techAccount.Password )
    {
        throw "Missing mandatory credentials parameters"
    }

    RegisterPSModules    

    $credential = New-Object System.Management.Automation.PSCredential($techAccount.User, (ConvertTo-SecureString -String $techAccount.Password -AsPlainText -Force))
    Add-ToAadGroup -groupName $groupName -computerName $env:ComputerName -credential $credential        

    LogToFile( "[$scriptName] Done")    
}
catch {
    LogToFile( "[$scriptName] Error: $_")
}
