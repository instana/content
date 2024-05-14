# Declaration

The following scripts help you to prepare the IBM MQ objects for ACE monitoring. You can modify these scripts on demand for different environments. As an assistant tool, no official support to these scripts are provided.

# Supported OS

- Ubuntu 20.04
- RHEL 9.4
- AIX 7.2 
# Instructions for running the `prep-mq.sh` script
## Descriptions
 
The script `prep-mq.sh` creates resources and sets authority correctly in QMGR for the ACE sensor. 
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
3. Go to the directory, and run the script.
    ```sh
    ./prep-mq.sh -q <QMGR_NAME>  -d <MQ_BIN_PATH> -u <AUTH_USER>
    ```
    {: codeblock}
# Instructions for running the revert-mq.sh script

## Descriptions

The `revert-mq.sh` script reverts the authority granted with the `prep-revert.sh` script and deletes the objects created in QMGR for the ACE sensor. 
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
3. Go to the directory, and execute the script.
    ```sh
    ./revert-mq.sh -q <QMGR_NAME> -d <MQ_BIN_PATH> [-u AUTH_USER] [-l LISTENER_NAME]  [-c CHANNEL_NAME]  [-t TOPIC_NAME]
    ```
    {: codeblock}




