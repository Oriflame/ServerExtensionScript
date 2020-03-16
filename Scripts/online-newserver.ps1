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

function SimpleLog( [string] $text )
{
    $date = Get-Date -Format s
    "$($date): $text" | Out-File $logFile -Append
}

function Get-Token($resource, $identity)
{
    $authpar = @{ Uri = "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01" 
                  Body = @{resource="$resource"}
                  Headers = @{Metadata="true"}
                }
    if ( $identity ) { $authpar.Body["mi_res_id"] = $identity }
    $meta = Invoke-RestMethod @authpar
    $meta.access_token
}

function Get-ServerSetup($b64json)
{
    try {    
        $setupJson = [System.Text.Encoding]::ASCII.GetString([System.Convert]::FromBase64String($b64json))
        SimpleLog "B64 decode: $setupJson" 
        $setup = @{}
        (ConvertFrom-Json $setupJson).psobject.properties | %{ $setup[$_.Name] = $_.Value }
        return $setup
    }
    catch {
        SimpleLog "B64 decode [$b64json] ERROR:`n$_" 
    }
}

function SetIdentity($setup)
{
	if ( $setup.IdentityResID ) { return }	
	$metadataurl = "http://169.254.169.254/metadata/instance/compute?api-version=2019-06-04"
    $meta = Invoke-RestMethod -Uri $metadataurl -Headers @{ Metadata="true" }

    $rgidentity = "resourceGroups/ArmCommon/providers/Microsoft.ManagedIdentity/userAssignedIdentities/onl-arm-identity"	
	$setup.IdentityResID = @("/subscriptions", $meta.SubscriptionID, $rgidentity) -join "/"
}


#start
SimpleLog "Working folder: $currentScriptFolder" 

try
{
#region Decode Parameter
    $setup = Get-ServerSetup -b64json $setupB64json
	SetIdentity $setup
	SimpleLog "Identity: $($setup.IdentityResID)"
#endregion (decode)

#download script files 
    $token = Get-Token $setup.StorageAccount $setup.IdentityResID
    $headers = @{ Authorization="Bearer $token" 
                "x-ms-version"="2019-02-02" }

    foreach( $file in $setup.Files + $setup.BootStrap )
    {        
        $local = join-path $currentScriptFolder -ChildPath (split-path $file -leaf)
        $remote   = @($setup.StorageAccount, $setup.Container, $file) -join "/"
        SimpleLog "Downloading: $remote >> $local" 
        Invoke-WebRequest -Uri $remote -Method GET -Headers $headers -OutFile $local    
    }

#exec bootstrap PS    
    $localPS = join-path $currentScriptFolder -ChildPath (split-path $setup.BootStrap -leaf)
    SimpleLog "Starting bootstrap PS: $localPS" 
    &$localPS >> $logFile

#done    
    SimpleLog "Bootstrap PS finished" 

}
catch
{
	SimpleLog "An error ocurred: $_" 
}
