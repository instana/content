# PowerShell script to revert MQ configuration
# Converted from revert-mq.sh

[CmdletBinding()]
param (
    [Parameter(Mandatory=$true)]
    [string]$QmgrName,
    
    [Parameter(Mandatory=$true)]
    [string]$MqBinPath,
    
    [Parameter(Mandatory=$false)]
    [string]$AuthUser,
    
    [Parameter(Mandatory=$false)]
    [string]$QmgrAuthRemove,
    
    [Parameter(Mandatory=$false)]
    [string]$ListenerName,
    
    [Parameter(Mandatory=$false)]
    [string]$ChannelName,
    
    [Parameter(Mandatory=$false)]
    [string]$TopicName
)

# Functions
function Show-Usage {
    Write-Host "Description:"
    Write-Host "This script will delete the specified objects/permissions:"
    Write-Host "1. Remove the qmgr authority(connect+inq) for the specified user"
    Write-Host "2. Delete the specified listener/channel/topic"
    Write-Host ""
    Write-Host "Usage: .\$(Split-Path -Leaf $PSCommandPath) -QmgrName <QMGR_NAME> -MqBinPath <MQ_BIN_PATH> [-AuthUser AUTH_USER] [-QmgrAuthRemove QMGR_AUTH_REMOVE] [-ListenerName LISTENER_NAME] [-ChannelName CHANNEL_NAME] [-TopicName TOPIC_NAME]"
    Write-Host "Example: "
    Write-Host "      .\$(Split-Path -Leaf $PSCommandPath) -QmgrName QM1 -MqBinPath 'C:\Program Files\IBM\MQ\bin' -AuthUser Administrator -ListenerName INSTANA.LST -ChannelName INSTANA.SVRCONN -TopicName INSTANA.ACE.BROKER.TOPIC"
    Write-Host "      .\$(Split-Path -Leaf $PSCommandPath) -QmgrName QM1 -MqBinPath 'C:\Program Files\IBM\MQ\bin' -AuthUser Administrator -QmgrAuthRemove 'connect' -ChannelName INSTANA.SVRCONN -TopicName INSTANA.ACE.BROKER.TOPIC"
    Write-Host "      .\$(Split-Path -Leaf $PSCommandPath) -QmgrName QM1 -MqBinPath 'C:\Program Files\IBM\MQ\bin' -AuthUser Administrator -QmgrAuthRemove 'connect inq' -ListenerName INSTANA.LST -ChannelName INSTANA.SVRCONN"
    Write-Host "      .\$(Split-Path -Leaf $PSCommandPath) -QmgrName QM1 -MqBinPath 'C:\Program Files\IBM\MQ\bin' -ChannelName INSTANA.SVRCONN"
    Write-Host ""
    Write-Host "Arguments:"
    Write-Host "  -QmgrName <QMGR_NAME>             Required. Specify the queuemanager name to execute the script with"
    Write-Host "  -MqBinPath <MQ_BIN_PATH>          Required. Specify the mq bin path"
    Write-Host "  -AuthUser <AUTH_USER>             Optional. Specify the user to remove authority from the specified QMGR. The authorities are defined with -QmgrAuthRemove, but if not specified, connect&inq will be removed by default"
    Write-Host "  -QmgrAuthRemove <QMGR_AUTH_REMOVE> Optional. Specify the authorities to be removed from the QMGR."
    Write-Host "  -ListenerName <LISTENER_NAME>     Optional. Specify the listener to be deleted."
    Write-Host "  -ChannelName <CHANNEL_NAME>       Optional. Specify the channel to be deleted. The related authrec and chlauth will also be removed for this channel."
    Write-Host "  -TopicName <TOPIC_NAME>           Optional. Specify the topic to be deleted. The related authrec will be removed for this topic."
}

# 1. Check the current user has authority to execute MQSC commands
function Test-Prerequisites {
    # Check user authority
    Write-Host "Check if current user has the authority to execute MQSC commands"
    
    # Check if the user is an administrator
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    
    # Check if the user is part of the mqm group
    $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    $userGroups = (New-Object System.Security.Principal.WindowsPrincipal([System.Security.Principal.WindowsIdentity]::GetCurrent())).Identity.Groups
    
    # Get the SID of the mqm group and check if the current user is a member
    $mqmGroupFound = $false
    foreach ($group in $userGroups) {
        try {
            $groupName = (New-Object System.Security.Principal.SecurityIdentifier($group.Value)).Translate([System.Security.Principal.NTAccount]).Value
            if ($groupName -match "mqm") {
                $mqmGroupFound = $true
                break
            }
        } catch {
            # Skip groups that can't be translated
            continue
        }
    }
    
    if ($isAdmin) {
        Write-Host "INFO: The user launched the script is an administrator"
    } elseif ($mqmGroupFound) {
        Write-Host "INFO: The user launched the script belongs to mqm group"
    } else {
        Write-Host "ERROR: The user launched the script is neither an administrator nor belongs to mqm group, please use an authorized user to execute MQSC commands" -ForegroundColor Red
        exit 1
    }

    # Check MQ bin path
    Write-Host "INFO: Check the MqBinPath exists and file setmqenv.cmd exists"
    if (-not (Test-Path -Path $MqBinPath) -or -not (Test-Path -Path "$MqBinPath\setmqenv.cmd")) {
        Write-Host "ERROR: The path $MqBinPath or the file $MqBinPath\setmqenv.cmd does not exist or both don't exist." -ForegroundColor Red
        exit 1
    } else {
        Write-Host "INFO: The $MqBinPath and related file setmqenv.cmd exist."
    }

    # Setup MQ environment to accept MQSC commands
    Write-Host "INFO: Setup mq command environment to accept mqsc command"
    try {
        & "$MqBinPath\setmqenv.cmd" -s
        Write-Host "INFO: The mq command environment has been set successfully."
    } catch {
        Write-Host "ERROR: Failed to set the environment" -ForegroundColor Red
        exit 1
    }
}

# 2. Remove authority to qmgr for specified user
function Remove-QmgrAuth {
    Write-Host "INFO: Remove specified authority to qmgr $QmgrName for user $AuthUser"
    if ($QmgrAuthRemove -ne $null -and $QmgrAuthRemove -ne '') {
        foreach ($permission in $QmgrAuthRemove.Split()) {
            $result = & "$MqBinPath\setmqaut" -m $QmgrName -t qmgr -p $AuthUser "-$permission"
            if ($LASTEXITCODE -eq 0) {
                Write-Host "INFO: The authority '$permission' has been removed successfully for user $AuthUser" -ForegroundColor Green
            } else {
                Write-Host "ERROR: Failed to remove the authority '$permission' for user $AuthUser to $QmgrName, please remove it manually" -ForegroundColor Red
                & "$MqBinPath\dspmqaut" -m $QmgrName -t qmgr -p $AuthUser
            }
        }
    }
}

# 3. Delete objects
function Remove-MqObjects {
    # Delete listener
    Write-Host "INFO: Delete listener object"
    if ($ListenerName) {
        $listener = "dis LISTENER($ListenerName)" | & "$MqBinPath\runmqsc" $QmgrName
        if ($listener -match "not found") {
            Write-Host "INFO: Nothing to delete as the $ListenerName is not found"
        } else {
            $stopResult = "stop LISTENER($ListenerName) IGNSTATE(NO)" | & "$MqBinPath\runmqsc" $QmgrName
            if ($LASTEXITCODE -eq 0) {
                $deleteResult = "delete LISTENER($ListenerName) IGNSTATE(NO)" | & "$MqBinPath\runmqsc" $QmgrName
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "INFO: Listener $ListenerName has been deleted successfully." -ForegroundColor Green
                } else {
                    Write-Host "ERROR: Failed to delete listener $ListenerName, please remove it manually" -ForegroundColor Red
                    "dis LISTENER($ListenerName)" | & "$MqBinPath\runmqsc" $QmgrName
                }
            } else {
                Write-Host "ERROR: Failed to stop listener $ListenerName, please check and remove it manually" -ForegroundColor Red
            }
        }
    } else {
        Write-Host "INFO: Nothing to delete as the listener name is empty"
    }

    # Delete channel
    Write-Host "INFO: Delete channel object and related authrec"
    if ($ChannelName) {
        $channel = "dis CHANNEL($ChannelName)" | & "$MqBinPath\runmqsc" $QmgrName
        if ($channel -match "not found") {
            Write-Host "INFO: Nothing to delete as the channel $ChannelName is not found"
        } else {
            $mqscDelChannel = @"
DELETE CHANNEL($ChannelName) IGNSTATE(YES)
SET CHLAUTH($ChannelName) TYPE(BLOCKUSER) USERLIST('nobody') ACTION(REMOVE)
DELETE AUTHREC profile($ChannelName) objtype(channel) PRINCIPAL('$AuthUser')
REFRESH SECURITY
"@
            $mqscDelChannel | & "$MqBinPath\runmqsc" $QmgrName
            
            $channel = "dis CHANNEL($ChannelName)" | & "$MqBinPath\runmqsc" $QmgrName
            $authrec = "dis AUTHREC profile($ChannelName) objtype(channel) PRINCIPAL('$AuthUser')" | & "$MqBinPath\runmqsc" $QmgrName
            $chlauth = "dis CHLAUTH($ChannelName) TYPE(BLOCKUSER)" | & "$MqBinPath\runmqsc" $QmgrName
            
            if (($channel -match "not found") -and ($authrec -match "Not found") -and ($chlauth -match "not found")) {
                Write-Host "INFO: Channel $ChannelName and related authrec have been deleted successfully." -ForegroundColor Green
            } else {
                Write-Host "ERROR: Failed to delete channel $ChannelName or related authrec, please remove them manually" -ForegroundColor Red
                $mqscDisChannel = @"
dis CHANNEL($ChannelName)
dis CHLAUTH($ChannelName) TYPE(BLOCKUSER)
dis AUTHREC profile($ChannelName) objtype(channel) PRINCIPAL('$AuthUser')
"@
                $mqscDisChannel | & "$MqBinPath\runmqsc" $QmgrName
            }
        }
    } else {
        Write-Host "INFO: Nothing to delete as the channel name is empty"
    }

    # Delete topic
    Write-Host "INFO: Delete topic object"
    if ($TopicName) {
        $topic = "dis TOPIC($TopicName)" | & "$MqBinPath\runmqsc" $QmgrName
        if ($topic -match "not found") {
            Write-Host "INFO: Nothing to delete as the $TopicName is not found"
        } else {
            $mqscDelTopic = @"
DELETE TOPIC($TopicName) AUTHREC(YES)
DELETE AUTHREC profile($TopicName) objtype(topic) PRINCIPAL('$AuthUser')
REFRESH SECURITY
"@
            $result = $mqscDelTopic | & "$MqBinPath\runmqsc" $QmgrName
            if ($LASTEXITCODE -eq 0) {
                Write-Host "INFO: Topic $TopicName and related authrec have been deleted successfully." -ForegroundColor Green
            } else {
                Write-Host "ERROR: Failed to delete topic object $TopicName or the related authrec, please remove them manually" -ForegroundColor Red
                "dis TOPIC($TopicName)" | & "$MqBinPath\runmqsc" $QmgrName
                "dis AUTHREC profile($TopicName) objtype(TOPIC) PRINCIPAL('$AuthUser')" | & "$MqBinPath\runmqsc" $QmgrName
            }
        }
    } else {
        Write-Host "INFO: Nothing to delete as the topic name is empty"
    }
}

# Main script

# Parameter validation
if (-not $QmgrName -or -not $MqBinPath) {
    Write-Host "ERROR: These arguments are required, but seems they are not set correctly" -ForegroundColor Red
    Write-Host "QmgrName: $QmgrName"
    Write-Host "MqBinPath: $MqBinPath"
    Write-Host ""
    Show-Usage
    exit 1
}

if ($AuthUser -and -not $QmgrAuthRemove) {
    $QmgrAuthRemove = "connect inq"
} elseif (-not $AuthUser -and $QmgrAuthRemove) {
    Write-Host "ERROR: The argument -AuthUser should be set if you set -QmgrAuthRemove" -ForegroundColor Red
    Write-Host ""
    Show-Usage
    exit 1
}

# Call functions
Show-Usage
Test-Prerequisites
if ($AuthUser) {
    Remove-QmgrAuth
}
Remove-MqObjects

# Made with Bob
