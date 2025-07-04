#
# PowerShell script to prepare IBM MQ for Instana monitoring
#

# Define the parameters
param (
    [Parameter(Mandatory=$true)]
    [string]$QmgrName,
    
    [Parameter(Mandatory=$true)]
    [string]$MqBinPath,
    
    [Parameter(Mandatory=$true)]
    [string]$AuthUser,
    
    [Parameter(Mandatory=$false)]
    [string]$ChannelName = 'INSTANA.SVRCONN',
    
    [Parameter(Mandatory=$false)]
    [switch]$MqOnly
)

# Define the variables
$TopicName = 'INSTANA.ACE.BROKER.TOPIC'
$TopicStr = '$SYS/Broker'
$ListenerName = 'INSTANA.LST'
$ListenerPort = '2121'
$script:AvailablePorts = @()
$script:PermissionsNew = @()
$script:ListenerNew = ''
$script:TopicNew = ''
$Type = if ($MqOnly) { "mq" } else { "ace" }

# Helper function to run MQSC commands
function Invoke-MqscCommand {
    param (
        [string]$QueueManager,
        [string]$Command
    )
    
    $tempFile = [System.IO.Path]::GetTempFileName()
    $Command | Out-File -FilePath $tempFile -Encoding ASCII
    $result = Get-Content -Path $tempFile | & runmqsc $QueueManager
    Remove-Item -Path $tempFile
    return $result
}

# Functions
# 0: print usage
function Print-Usage {
    Write-Host "Description: "
    Write-Host "This script will try to cover following things:"
    Write-Host "1. Check user running this script has authority to execute MQSC commands"
    Write-Host "2. Check the available listener ports and define a new one if there is no available"
    Write-Host "3. Define a channel and set authrec for it with the specified user."
    Write-Host "4. Check the connectivity of the channel with specified user"
    Write-Host "5. Define a topic or use existing topic object for topic string '$SYS/Broker' and set authrec for it"
    Write-Host "6. List the useful info you can use to set in configuration.yaml for plugin.ace and plugin.ibmmq"
    Write-Host -ForegroundColor Yellow "Note: this script will cover most cases, but sometimes if you fail to create the mq objects, please contact IBM Instana support or contact IBM MQ support team for help."
    Write-Host ""
    Write-Host "Usage: .\$(Split-Path -Leaf $PSCommandPath) -QmgrName <QMGR_NAME> -MqBinPath <MQ_BIN_PATH> -AuthUser <AUTH_USER> [-ChannelName <CHANNEL_NAME>] [-MqOnly]"
    Write-Host "Example: "
    Write-Host "      .\$(Split-Path -Leaf $PSCommandPath) -QmgrName QM1 -MqBinPath 'C:\Program Files\IBM\MQ\bin' -AuthUser Administrator -ChannelName INSTANA.SVRCONN -MqOnly"
    Write-Host "      .\$(Split-Path -Leaf $PSCommandPath) -QmgrName QM1 -MqBinPath 'C:\Program Files\IBM\MQ\bin' -AuthUser Administrator -MqOnly"
    Write-Host "      .\$(Split-Path -Leaf $PSCommandPath) -QmgrName QM1 -MqBinPath 'C:\Program Files\IBM\MQ\bin' -AuthUser Administrator -ChannelName INSTANA.SVRCONN"
    Write-Host "      .\$(Split-Path -Leaf $PSCommandPath) -QmgrName QM1 -MqBinPath 'C:\Program Files\IBM\MQ\bin' -AuthUser Administrator"
    Write-Host ""
    Write-Host "Arguments:"
    Write-Host "  -QmgrName <QMGR_NAME>     Required. Specify the queuemanager name to execute the script with"
    Write-Host "  -MqBinPath <MQ_BIN_PATH>  Required. Specify the mq bin path"
    Write-Host "  -AuthUser <AUTH_USER>     Required. Specify the user to give authority for mq/ace monitoring"
    Write-Host "  -ChannelName <CHANNEL_NAME>  Optional. Specify the channel to be created. If not specify, the default channel INSTANA.SVRCONN will be used."
    Write-Host "  -MqOnly                   Optional. Set up MQ channel for MQ sensor only. If not set, both channel and topic will be created to support both mq sensor and ace sensor."
}

# 1. Check the current user has authority to execute MQSC commands
function Pre-Check {
    # Check user authority - in Windows, check if user is in MQM group or is Administrator
    $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    
    if ($isAdmin) {
        Write-Host "INFO: The user launched the script has Administrator privileges"
    }
    else {
        $groups = (New-Object System.Security.Principal.WindowsPrincipal([System.Security.Principal.WindowsIdentity]::GetCurrent())).Groups
        $mqmGroup = $groups | Where-Object { $_.Value -match "-S-1-5-.*-mqm$" }
        
        if ($mqmGroup) {
            Write-Host "INFO: The user launched the script belongs to mqm group"
        }
        else {
            Write-Host -ForegroundColor Red "ERROR: The user launched the script doesn't have Administrator privileges or belong to mqm group, please use an authorized user to execute MQSC commands"
            exit 1
        }
    }

    # check mq bin path 
    Write-Host "INFO: Check the MQ_BIN_PATH exists and file setmqenv.cmd exists"
    if (-not (Test-Path -Path $MqBinPath) -or -not (Test-Path -Path "$MqBinPath\setmqenv.cmd")) {
        Write-Host -ForegroundColor Red "ERROR: The path $MqBinPath or the file $MqBinPath\setmqenv.cmd does not exist or both don't exist."
        exit 1
    }
    else {
        Write-Host "INFO: The $MqBinPath and related file setmqenv.cmd exist."
    }

    # Setup mq environment to accept mqsc command
    Write-Host "INFO: Setup mq command environment to accept mqsc command"
    try {
        & "$MqBinPath\setmqenv.cmd" -s
        Write-Host "INFO: The mq command environment has been set successfully."
    }
    catch {
        Write-Host -ForegroundColor Red "ERROR: Failed to set the environment"
        Write-Host -ForegroundColor Red $_.Exception.Message
        exit 1
    }
}

# Check permission
function Check-Permission {
    param (
        [string]$permission
    )
    
    $permissions = & dspmqaut -m $QmgrName -t qmgr -p $AuthUser
    if ($permissions -match $permission) {
        return $true  # the permission exists
    }
    else {
        return $false  # the permission doesn't exist
    }
}

# 2. Set correct authority for $AuthUser to access QMGR
function Set-QmgrAuth {
    Write-Host "INFO: Check authority for user $AuthUser to access QMGR."
    $perms = @("connect", "inq")
    $script:PermissionsNew = @()
    
    foreach ($perm in $perms) {
        if (-not (Check-Permission $perm)) {
            & setmqaut -m $QmgrName -t qmgr -p $AuthUser +$perm | Out-Null
            $script:PermissionsNew += $perm
        }
    }
    
    if ($script:PermissionsNew.Count -ne 0) {
        Write-Host ("INFO: Newly added permissions for user {0} on QMGR {1}{2} {3}" -f $AuthUser, $QmgrName, [char]58, ($script:PermissionsNew -join ' '))
    }
    else {
        Write-Host "INFO: No new permissions were added for user $AuthUser on QMGR $QmgrName"
    }
}

# 3. Print out all available listener ports
function Get-ListenerPort {
    $listenerOutput = Invoke-MqscCommand -QueueManager $QmgrName -Command "dis LISTENER(*) PORT"
    $listenerPorts = $listenerOutput | Select-String -Pattern "PORT\((\d+)\)" -AllMatches | 
                    ForEach-Object { $_.Matches } | ForEach-Object { $_.Groups[1].Value }
    
    $script:AvailablePorts = @()
    
    if ($listenerPorts) {
        foreach ($port in $listenerPorts) {
            if (Test-Port $port) {
                $script:AvailablePorts += $port
            }
        }
    }
    
    if ($script:AvailablePorts.Count -gt 0) {
        Write-Host "INFO: Found available ports: $($script:AvailablePorts -join ' ')"
    }
    else {
        Write-Host "Create a listener as there is no listener port found"
        Invoke-MqscCommand -QueueManager $QmgrName -Command "DEFINE LISTENER($ListenerName) TRPTYPE(TCP) PORT($ListenerPort)" | Out-Null
        Invoke-MqscCommand -QueueManager $QmgrName -Command "START LISTENER($ListenerName) IGNSTATE(NO)" | Out-Null
        $script:ListenerNew = $ListenerName
        
        if (Test-Port $ListenerPort) {
            $script:AvailablePorts += $ListenerPort
        }
        else {
            Write-Host -ForegroundColor Red "ERROR: Port $ListenerPort is not open or not accepting connections. Please check and fix."
            exit 1
        }
    }
}

function Test-Port {
    param (
        [string]$port
    )
    
    if ([string]::IsNullOrEmpty($port) -or $port -eq "0") {
        return $false
    }
    
    try {
        $tcpClient = New-Object System.Net.Sockets.TcpClient
        $connectionResult = $tcpClient.BeginConnect("localhost", $port, $null, $null)
        $waitResult = $connectionResult.AsyncWaitHandle.WaitOne(1000, $false)
        
        if ($waitResult) {
            $tcpClient.EndConnect($connectionResult)
            $tcpClient.Close()
            return $true
        }
        else {
            $tcpClient.Close()
            return $false
        }
    }
    catch {
        return $false
    }
}

# 4. Create channel and topic, set authrec for them
function Prep-ChannelAndTopic {
    $checkChannel = (Invoke-MqscCommand -QueueManager $QmgrName -Command "DISPLAY CHANNEL($ChannelName)") -join "`n"
    
    if ($checkChannel -notmatch "not found") {
        Write-Host $checkChannel
        Write-Host -ForegroundColor Red "ERROR: The channel $ChannelName already exists, please use a different name or delete the existing channel and rerun the script."
        
        if ($script:PermissionsNew.Count -ne 0 -or $script:ListenerNew) {
            Write-Host -ForegroundColor Red "NOTE: Following objects/permissions are changed or created, please revert them manually or use script revert-mq.ps1 to clean up before rerunning:"
            
            if ($script:PermissionsNew.Count -ne 0) {
                Write-Host ("Permissions added on QMGR {0} for user {1}{2} {3}" -f $QmgrName, $AuthUser, [char]58, ($script:PermissionsNew -join ' '))
            }
            
            if ($script:ListenerNew) {
                Write-Host "Listener new created: $script:ListenerNew"
            }
        }
        exit 1
    }
    
    # Execute the MQSC commands
    $mqscCheckChannel = @"
DEFINE CHANNEL($ChannelName) CHLTYPE(SVRCONN) TRPTYPE(TCP) MCAUSER('$AuthUser')
SET CHLAUTH($ChannelName) TYPE(BLOCKUSER) USERLIST('nobody') DESCR('Block all users except authorized users')
SET AUTHREC profile($ChannelName) objtype(channel) PRINCIPAL('$AuthUser') AUTHADD(ALL)
REFRESH SECURITY
"@
    
    Invoke-MqscCommand -QueueManager $QmgrName -Command $mqscCheckChannel | Out-Null
    
    # Verify the user authority of channel connection
    $output = Invoke-MqscCommand -QueueManager $QmgrName -Command "dis chlauth($ChannelName) MATCH(RUNCHECK) CLNTUSER('$AuthUser') ADDRESS('0.0.0.0')"
    $expectedOutput = "AMQ9783I: Channel will run using MCAUSER('$AuthUser')."
    
    if ($output -match [regex]::Escape($expectedOutput)) {
        Write-Host "INFO: The channel authority is set successfully with output: $expectedOutput"
        
        if ($Type -ne "mq") {
            $existingTopic = Invoke-MqscCommand -QueueManager $QmgrName -Command "dis TOPIC(*) WHERE(TOPICSTR EQ '$TopicStr')"
            
            # Create a topic if it doesn't exist
            if ($existingTopic -match "not found") {
                Write-Host "INFO: Topic object with TOPICSTR '$TopicStr' not found. Creating a new one..."
                Invoke-MqscCommand -QueueManager $QmgrName -Command "DEFINE TOPIC($TopicName) TOPICSTR('$TopicStr')" | Out-Null
                $script:TopicNew = $TopicName
            }
            else {
                Write-Host "INFO: Topic object with TOPICSTR '$TopicStr' already exists."
                $topicNameMatch = [regex]::Match($existingTopic, "TOPIC\(([^)]*)\)")
                if ($topicNameMatch.Success) {
                    $TopicName = $topicNameMatch.Groups[1].Value
                }
            }
            
            # Set authrec for the topic
            $mqscSetAuth4Topic = @"
SET AUTHREC profile($TopicName) objtype(topic) PRINCIPAL('$AuthUser') AUTHADD(ALL)
REFRESH SECURITY
"@
            Invoke-MqscCommand -QueueManager $QmgrName -Command $mqscSetAuth4Topic | Out-Null
            Write-Host "INFO: Set authrec for the topic $TopicName"
            
            # Verify the authrec exists
            $existingAuthrec = Invoke-MqscCommand -QueueManager $QmgrName -Command "DIS AUTHREC PROFILE($TopicName) OBJTYPE(TOPIC) PRINCIPAL('$AuthUser')"
            
            # Print the result
            if ($existingAuthrec -match "not found") {
                Write-Host -ForegroundColor Red "ERROR: AUTHREC for topic '$TopicName' does not exist. Please fix the issue according to the commands execution result."
                Write-Host $existingAuthrec
                exit 1
            }
            else {
                Write-Host "INFO: AUTHREC for topic '$TopicName' exists."
            }
        }
    }
    else {
        Write-Host -ForegroundColor Red "ERROR: The channel authority is failed to set. Fix it by removing the blocking AUTHREC and then rerun the script."
        Write-Host $output
        Write-Host -ForegroundColor Red "NOTE: Following objects/permissions are changed or created, please revert them manually or use script revert-mq.ps1 to clean up before rerunning:"
        
        if ($script:PermissionsNew.Count -ne 0) {
            Write-Host ("Permissions added on QMGR{0} {1} for user{2} {3}{4} {5}" -f [char]58, $QmgrName, [char]58, $AuthUser, [char]58, ($script:PermissionsNew -join ' '))
        }
        
        if ($script:ListenerNew) {
            Write-Host "Listener new created: $script:ListenerNew"
        }
        
        $channelAuthrecNew = "DIS AUTHREC PROFILE($ChannelName) OBJTYPE(CHANNEL) PRINCIPAL('$AuthUser')"
        $chlauthNew = "DIS CHLAUTH($ChannelName) TYPE(BLOCKUSER)"
        Write-Host "Channel new created: $ChannelName"
        Write-Host ("AUTHREC new added for channel {0}{1}" -f $ChannelName, [char]58)
        Write-Host $channelAuthrecNew
        Write-Host ("CHLAUTH new added for channel {0}{1}" -f $ChannelName, [char]58)
        Write-Host $chlauthNew
        exit 1
    }
}

# 5. Print out useful info you need in setting configuration.yaml
function Print-ConnInfo {
    Write-Host -ForegroundColor Green "INFO: You have prepared the MQ objects for Instana monitoring well. Following Objects and Permissions are new added:"
    
    if ($script:PermissionsNew.Count -ne 0) {
        Write-Host -ForegroundColor Green ("Permissions added on QMGR {0} for user {1}{2}" -f $QmgrName, $AuthUser, [char]58)
        Write-Host "$($script:PermissionsNew -join ' ')"
    }
    
    if ($script:ListenerNew) {
        Write-Host -ForegroundColor Green "Listener new created:"
        Write-Host "$script:ListenerNew"
    }
    
    Write-Host -ForegroundColor Green "Channel new created:"
    Write-Host "$ChannelName"
    Write-Host -ForegroundColor Green ("AUTHREC and CHLAUTH new added for channel {0}{1}" -f $ChannelName, [char]58)
    Write-Host "CHLAUTH($ChannelName) TYPE(BLOCKUSER) USERLIST('nobody') DESCR('Block all users except authorized users')"
    Write-Host "AUTHREC profile($ChannelName) objtype(channel) PRINCIPAL('$AuthUser') AUTHADD(ALL)"
    
    if ($Type -ne "mq") {
        if ($script:TopicNew) {
            Write-Host -ForegroundColor Green "Topic new created:           $script:TopicNew"
        }
        
        Write-Host -ForegroundColor Green ("AUTHREC new added for topic {0}{1}" -f $TopicName, [char]58)
        Write-Host "AUTHREC profile($TopicName) objtype(topic) PRINCIPAL('$AuthUser') AUTHADD(ALL)"
        Write-Host ""
        
        Write-Host -ForegroundColor Green "You can set the configuration.yaml for ACE sensor with following info:"
        Write-Host "queuemanagerName:   $QmgrName"
        Write-Host "mqport:            $($script:AvailablePorts -join ' ') (choose one)"
        Write-Host "channel:            $ChannelName"
        Write-Host "mqUsername:         $AuthUser"
        Write-Host ""
    }
    
    Write-Host -ForegroundColor Green "You can set the configuration.yaml for MQ sensor with following info:"
    Write-Host "QUEUE_MANAGER_NAME_1: $QmgrName"
    Write-Host "port:                 $($script:AvailablePorts -join ' ') (choose one)"
    Write-Host "channel:              $ChannelName"
    Write-Host "username:             $AuthUser"
    Write-Host ""
    
    Write-Host -ForegroundColor Green "This tool only covers basic info, for other info, like user password and SSL related info, please check manually and set properly."
    Write-Host -ForegroundColor Yellow "INFO: To revert the permissions added and objects created, download the revert-mq.ps1 script and run like following:"
    
    $optP = ""
    $optL = ""
    $optT = ""
    
    if ($script:PermissionsNew.Count -ne 0) {
        $optP = "-Permissions '$($script:PermissionsNew -join ' ')'"
    }
    
    if ($script:ListenerNew) {
        $optL = "-ListenerName $script:ListenerNew"
    }
    
    if ($script:TopicNew) {
        $optT = "-TopicName $script:TopicNew"
    }
    
    Write-Host ".\revert-mq.ps1 -QmgrName $QmgrName -MqBinPath '$MqBinPath' -AuthUser $AuthUser $optP $optL -ChannelName $ChannelName $optT"
}

# Check if required parameters are provided
if ([string]::IsNullOrEmpty($QmgrName) -or [string]::IsNullOrEmpty($MqBinPath) -or [string]::IsNullOrEmpty($AuthUser)) {
    Write-Host -ForegroundColor Red "ERROR: These arguments are required, but seems they are not set correctly."
    Write-Host "-QmgrName <QMGR_NAME> -MqBinPath <MQ_BIN_PATH> -AuthUser <AUTH_USER>"
    Write-Host ""
    Print-Usage
    exit 1
}

# Execute the functions
Print-Usage
Pre-Check
Set-QmgrAuth
Get-ListenerPort
Prep-ChannelAndTopic
Print-ConnInfo

# Made with Bob
