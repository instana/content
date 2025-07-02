# Declaration

The following scripts help you to prepare the IBM MQ objects for ACE/MQ monitoring. You can modify these scripts on demand for different environments. As an assistant tool, no official support to these scripts are provided.

# Supported OS

- Ubuntu 20.04
- RHEL 9.4
- AIX 7.2 
- Windows

# `prep-mq.sh` script

## Description
 
The script `prep-mq.sh` creates resources and sets authority correctly in QMGR for the ACE/MQ sensor. 
* Run the script with a user who belongs to `mqm` group and on the machine that hosts the queue manager.
* `AUTH_USER` in the script is the user that you want to grant authority. The user needn't be a privileged user.
 
## Usage

To run the `prep-mq.sh` script, complete the following steps:

1. Download the `prep-mq.sh` script. 
2. Make the script executable:
    ```
    chmod +x prep-mq.sh
    ```
    {: codeblock}
3. Go to the directory, and run the script:
    ```sh
    ./prep-mq.sh -q <QMGR_NAME>  -d <MQ_BIN_PATH> -u <AUTH_USER>  [-c CHANNEL_NAME] [-m]
    ```
    {: codeblock}
    
# `revert-mq.sh` script

## Description

The `revert-mq.sh` script reverts the authority granted with the `prep-revert.sh` script and deletes the objects created in QMGR for the ACE/MQ sensor. 
* Run the script with a user who belongs to `mqm `group and on the machine which hosts the queue manager.
* `AUTH_USER` in the script is the user that you used in the `prep-mq.sh` script.
 
## Usage

To run the `revert-mq.sh` script, complete the following steps:

1. Download the `revert-mq.sh` script.
2. Make the script executable:
    ```
    chmod +x revert-mq.sh
    ```
    {: codeblock}
3. Go to the directory, and run the script:
    ```sh
    ./revert-mq.sh -q <QMGR_NAME> -d <MQ_BIN_PATH> [-u AUTH_USER] [-p QMGR_AUTH_REMOVE] [-l LISTENER_NAME]  [-c CHANNEL_NAME]  [-t TOPIC_NAME]
    ```
    {: codeblock}

# `prep-mq.ps1` script (Windows)

## Description

The script `prep-mq.ps1` creates resources and sets authority correctly in QMGR for the ACE/MQ sensor on Windows environments.
* Run the script with a user who belongs to the `mqm` group or has Administrator privileges, and on the machine that hosts the queue manager.
* `AuthUser` in the script is the user that you want to grant authority. The user needn't be a privileged user.

## Usage

To run the `prep-mq.ps1` script, complete the following steps:

1. Download the `prep-mq.ps1` script.
2. Open PowerShell with appropriate permissions.
3. Navigate to the directory containing the script, and run:
    ```powershell
    .\prep-mq.ps1 -QmgrName <QMGR_NAME> -MqBinPath <MQ_BIN_PATH> -AuthUser <AUTH_USER> [-ChannelName <CHANNEL_NAME>] [-MqOnly]
    ```

### Examples:
```powershell
.\prep-mq.ps1 -QmgrName QM1 -MqBinPath 'C:\Program Files\IBM\MQ\bin' -AuthUser Administrator -ChannelName INSTANA.SVRCONN -MqOnly
.\prep-mq.ps1 -QmgrName QM1 -MqBinPath 'C:\Program Files\IBM\MQ\bin' -AuthUser Administrator -MqOnly
.\prep-mq.ps1 -QmgrName QM1 -MqBinPath 'C:\Program Files\IBM\MQ\bin' -AuthUser Administrator -ChannelName INSTANA.SVRCONN
.\prep-mq.ps1 -QmgrName QM1 -MqBinPath 'C:\Program Files\IBM\MQ\bin' -AuthUser Administrator
```

### Parameters:
- `-QmgrName <QMGR_NAME>`: Required. Specify the queue manager name to execute the script with.
- `-MqBinPath <MQ_BIN_PATH>`: Required. Specify the MQ bin path.
- `-AuthUser <AUTH_USER>`: Required. Specify the user to give authority for MQ/ACE monitoring.
- `-ChannelName <CHANNEL_NAME>`: Optional. Specify the channel to be created. If not specified, the default channel INSTANA.SVRCONN will be used.
- `-MqOnly`: Optional. Set up MQ channel for MQ sensor only. If not set, both channel and topic will be created to support both MQ sensor and ACE sensor.

# `revert-mq.ps1` script (Windows)

## Description

The `revert-mq.ps1` script reverts the authority granted with the `prep-mq.ps1` script and deletes the objects created in QMGR for the ACE/MQ sensor on Windows environments.
* Run the script with a user who belongs to the `mqm` group or has Administrator privileges, and on the machine that hosts the queue manager.
* `AuthUser` in the script is the user that you used in the `prep-mq.ps1` script.

## Usage

To run the `revert-mq.ps1` script, complete the following steps:

1. Download the `revert-mq.ps1` script.
2. Open PowerShell with appropriate permissions.
3. Navigate to the directory containing the script, and run:
    ```powershell
    .\revert-mq.ps1 -QmgrName <QMGR_NAME> -MqBinPath <MQ_BIN_PATH> [-AuthUser <AUTH_USER>] [-QmgrAuthRemove <QMGR_AUTH_REMOVE>] [-ListenerName <LISTENER_NAME>] [-ChannelName <CHANNEL_NAME>] [-TopicName <TOPIC_NAME>]
    ```

### Examples:
```powershell
.\revert-mq.ps1 -QmgrName QM1 -MqBinPath 'C:\Program Files\IBM\MQ\bin' -AuthUser Administrator -ListenerName INSTANA.LST -ChannelName INSTANA.SVRCONN -TopicName INSTANA.ACE.BROKER.TOPIC
.\revert-mq.ps1 -QmgrName QM1 -MqBinPath 'C:\Program Files\IBM\MQ\bin' -AuthUser Administrator -QmgrAuthRemove 'connect' -ChannelName INSTANA.SVRCONN -TopicName INSTANA.ACE.BROKER.TOPIC
.\revert-mq.ps1 -QmgrName QM1 -MqBinPath 'C:\Program Files\IBM\MQ\bin' -AuthUser Administrator -QmgrAuthRemove 'connect inq' -ListenerName INSTANA.LST -ChannelName INSTANA.SVRCONN
.\revert-mq.ps1 -QmgrName QM1 -MqBinPath 'C:\Program Files\IBM\MQ\bin' -ChannelName INSTANA.SVRCONN
```

### Parameters:
- `-QmgrName <QMGR_NAME>`: Required. Specify the queue manager name to execute the script with.
- `-MqBinPath <MQ_BIN_PATH>`: Required. Specify the MQ bin path.
- `-AuthUser <AUTH_USER>`: Optional. Specify the user to remove authority from the specified QMGR. If specified without `-QmgrAuthRemove`, 'connect inq' permissions will be removed by default.
- `-QmgrAuthRemove <QMGR_AUTH_REMOVE>`: Optional. Specify the authorities to be removed from the QMGR.
- `-ListenerName <LISTENER_NAME>`: Optional. Specify the listener to be deleted.
- `-ChannelName <CHANNEL_NAME>`: Optional. Specify the channel to be deleted. The related authrec and chlauth will also be removed for this channel.
- `-TopicName <TOPIC_NAME>`: Optional. Specify the topic to be deleted. The related authrec will be removed for this topic.

// Made with Bob
