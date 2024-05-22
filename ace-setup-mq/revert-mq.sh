#!/bin/bash
# Functions
printUsage() {
    echo "Description:"
    echo "This script will delete the specified objects/permissions:"
    echo "1. Remove the qmgr authority(connect+inq) for the specified user"
    echo "2. Delete the specified listener/channel/topic"
    echo ""
    echo "Usage: $0 -q <QMGR_NAME> -d <MQ_BIN_PATH> [-u AUTH_USER] [-p QMGR_AUTH_REMOVE]  [-l LISTENER_NAME] [-c CHANNEL_NAME] [-t TOPIC_NAME]"
    echo "Example: "
    echo "      $0 -q QM1 -d /opt/mqm/bin -u root  -l INSTANA.LST -c INSTANA.SVRCONN -t INSTANA.ACE.BROKER.TOPIC"
    echo "      $0 -q QM1 -d /opt/mqm/bin -u root  -p 'connect'       -c INSTANA.SVRCONN -t INSTANA.ACE.BROKER.TOPIC" 
    echo "      $0 -q QM1 -d /opt/mqm/bin -u root  -p 'connect inq'   -l INSTANA.LST -c INSTANA.SVRCONN"
    echo "      $0 -q QM1 -d /opt/mqm/bin -c INSTANA.SVRCONN"
    echo ""
    echo "Arguments:"
    echo "  -q  <QMGR_NAME>             Required. Specify the queuemanager name to execute the script with"
    echo "  -d  <MQ_BIN_PATH>           Required. Specify the mq bin path"
    echo "  -u  <AUTH_USER>             Optional. Specify the user to remove authority from the specified QMGR. The authorities are defined with -p,  but if not specify, connect&inq will be removed by default "
    echo "  -p  <QMGR_AUTH_REMOVE>      Optional. Specify the authorities to be removed from the QMGR. "
    echo "  -l  <LISTENER_NAME>         Opitonal. Specify the listener to be deleted."
    echo "  -c  <CHANNEL_NAME>          Optional. Specify the channel to be deleted. The related authrec and chlauth will also be removed for this channel."
    echo "  -t  <TOPIC_NAME>            Opitonal. Specify the topic to be deleted. The related authrec will be removed for this topic."
}

# 1. Check the current user has authority to execute MQSC commands
preCheck() {
    # Check user authority
    echo "Check if current user has the authority to execute MQSC commands"
    if groups | tr ' ' '\n' | grep -q '^mqm$'; then
        echo "INFO: The user launched the script belongs to mqm group"
    else
        echo -e "\033[1;31mERROR: The user launched the script doesn't belong to mqm group, please use an authorized user to execute MQSC commands\033[0m"
        exit 1
    fi

    # check mq bin path 
    echo "INFO:Check the MQ_BIN_PATH exists and file setmqenv exists"
    if [ ! -d "$MQ_BIN_PATH" ] || [ ! -f "$MQ_BIN_PATH/setmqenv" ]; then
        echo -e "\033[1;31mERROR: The path $MQ_BIN_PATH or the file $MQ_BIN_PATH/setmqenv does not exist or both don't exist.\033[0m"
        exit 1
    else
        echo "INFO: The $MQ_BIN_PATH and related file setmqenv exist."
    fi    

    # Setup mq environment to accept mqsc command. 
    echo "INFO: Setup mq command environment to accept mqsc command"
    . $MQ_BIN_PATH/setmqenv -s 
    if [ $? -eq 0 ]; then
       echo "INFO: The mq command environment has been set successfully."
    else
       echo -e "\033[1;31mERROR: Failed to set the environment\033[0m"
       exit 1
    fi
}
# 2. remove authority to qmgr for specified user
removeQmgrAuth(){
    echo  "INFO: Remove specified authority to qmgr $QMGR_NAME for user $AUTH_USER"
    if [ -n '$QMGR_AUTH_REM' ]; then 
        for PERMISSION in $QMGR_AUTH_REM; do
            setmqaut -m $QMGR_NAME -t qmgr -p $AUTH_USER -$PERMISSION
            if [ $? -eq 0 ]; then
                echo -e "\033[1;32mINFO: The authority '$PERMISSION' has been removed succesfully for user $AUTH_USER\033[0m"
            else
                echo -e "\033[1;31mERROR: Failed to remove the authority '$PERMISSION' for user $AUTH_USER to $QMGR_NAME, please remove it manually\033[0m"
                dspmqaut -m $QMGR_NAME -t qmgr -p $AUTH_USER  
            fi
        done
    fi  
}

# 3. delete objects
deleteObjects() {
    # delete listener
    echo  "INFO: Delete listener object"
    if [ -n "$LISTENER_NAME" ]; then 
        listener=$(echo "dis LISTENER($LISTENER_NAME)" | runmqsc "$QMGR_NAME")
        if [[ "$listener" == *"not found"* ]]; then
            echo "INFO: Nothing to delete as the $LISTENER_NAME is not found"
        else
            echo "stop LISTENER($LISTENER_NAME) IGNSTATE(NO)"  | runmqsc "$QMGR_NAME"
            if [ $? -eq 0 ]; then
                echo "delete LISTENER($LISTENER_NAME) IGNSTATE(NO)" | runmqsc "$QMGR_NAME"
                if [ $? -eq 0 ]; then
                    echo  -e "\033[1;32mINFO: Listenter $LISTENER_NAME has been deleted successfully.\033[0m"
                else
                    echo -e "\033[1;31mERROR: Failed to delete listenter $LISTENER_NAME, please remove it manually\033[0m"
                    echo "dis LISTENER($LISTENER_NAME)" | runmqsc "$QMGR_NAME"
                fi
            else
                echo -e "\033[1;31mERROR: Failed to stop listenter $LISTENER_NAME, please chekc and remove it manually\033[0m"
            fi 
        fi       
    else 
        echo "INFO: Nothing to delete as the listener name is empty"
    fi

    # delete channel
    echo  "INFO: Delete channel object and related authrec"
    if [ -n "$CHANNEL_NAME" ]; then 
        channel=$(echo "dis CHANNEL($CHANNEL_NAME)" | runmqsc "$QMGR_NAME")
        if [[ "$channel" == *"not found"* ]]; then
            echo "INFO: Nothing to delete as the channel $CHANNEL_NAME is not found"
        else
            echo "$MQSC_DEL_CHANNEL" | runmqsc "$QMGR_NAME"
            channel=$(echo "dis CHANNEL($CHANNEL_NAME)" | runmqsc "$QMGR_NAME")
            authrec=$(echo "dis AUTHREC profile($CHANNEL_NAME) objtype(channel) PRINCIPAL('$AUTH_USER')" | runmqsc "$QMGR_NAME")
            chlauth=$(echo "dis CHLAUTH($CHANNEL_NAME) TYPE(BLOCKUSER)"| runmqsc "$QMGR_NAME")
            if [[  "$channel" == *"not found"* && "$authrec" == *"Not found"* && "$chlauth" == *"not found"* ]]; then
                echo  -e "\033[1;32mINFO: Channel $CHANNEL_NAME and relate authrec have been deleted successfully.\033[0m"
            else
                echo -e "\033[1;31mERROR: Failed to delete channel $CHANNEL_NAME or related authrec, please remove them manually\033[0m"
                echo "$MQSC_DIS_CHANNEL" | runmqsc "$QMGR_NAME"
            fi
        fi
    else 
        echo "INFO: Nothing to delete as the channel name is empty"
    fi

    # delete topic
    echo  "INFO: Delete topic object"
    if [ -n "$TOPIC_NAME" ]; then 
        topic=$(echo "dis TOPIC($TOPIC_NAME)" | runmqsc "$QMGR_NAME")
        if [[ "$topic" == *"not found"* ]]; then
            echo "INFO: Nothing to delete as the $TOPIC_NAME is not found"
        else
            echo "$MQSC_DEL_TOPIC" | runmqsc "$QMGR_NAME"
            if [ $? -eq 0 ]; then
                echo  -e "\033[1;32mINFO: Topic $TOPIC_NAME and related authrec have been deleted successfully.\033[0m"
            else
                echo -e "\033[1;31mERROR: Failed to delete topic object $TOPIC_NAME or the related authrec, please remove them manually\033[0m"
                echo "dis TOPIC($TOPIC_NAME)" | runmqsc "$QMGR_NAME"
                echo "dis AUTHREC profile($TOPIC_NAME) objtype(TOPIC) PRINCIPAL('$AUTH_USER')"| runmqsc "$QMGR_NAME" 
            fi
          
        fi
    else 
        echo "INFO: Nothing to delete as the topic name is empty"
    fi
}

# Init
# Check the parameters
while getopts ":q:d:u:p:l:c:t:" opt; do
    case ${opt} in
        q)
          QMGR_NAME=${OPTARG}
          ;;
        d)
          MQ_BIN_PATH=${OPTARG}
          ;;
        u)
          AUTH_USER=${OPTARG}
          ;;
        p)
          QMGR_AUTH_REM=${OPTARG}
          ;;
        l)
          LISTENER_NAME=${OPTARG}
          ;;
        c)
          CHANNEL_NAME=${OPTARG}
          ;;
        t)
          TOPIC_NAME=${OPTARG}
          ;;
        ?)
          printUsage
          exit 1
          ;;
    esac
done
shift $(($OPTIND - 1))

if [[ -z "$QMGR_NAME" || -z "$MQ_BIN_PATH" ]]; then
    echo -e "\033[1;31mERROR: These arguments are required, but seems they are not set correctly\033[0m"
    echo "QMGR_NAME: $QMGR_NAME"
    echo "MQ_BIN_PATH: $MQ_BIN_PATH"
    echo ""
    printUsage
    exit 1
fi
if [[ -n "$AUTH_USER"  && -z "$QMGR_AUTH_REM" ]]; then
    QMGR_AUTH_REM="connect inq"
elif [[ -z "$AUTH_USER"  && -n "$QMGR_AUTH_REM" ]]; then
    echo -e "\033[1;31mERROR: The argument -u should be set if you set -p \033[0m"
    echo ""
    printUsage
    exit 1
fi

# Define the MQSC commands for channel removing
read -r -d '' MQSC_DEL_CHANNEL << EOF
DELETE CHANNEL($CHANNEL_NAME) IGNSTATE(YES)
SET CHLAUTH($CHANNEL_NAME) TYPE(BLOCKUSER) USERLIST('nobody') ACTION(REMOVE)
DELETE AUTHREC profile($CHANNEL_NAME) objtype(channel) PRINCIPAL('$AUTH_USER') 
REFRESH SECURITY
EOF

# Define the MQSC commands for channel displaying
read -r -d '' MQSC_DIS_CHANNEL << EOF
dis CHANNEL($CHANNEL_NAME)
dis CHLAUTH($CHANNEL_NAME) TYPE(BLOCKUSER)
dis AUTHREC profile($CHANNEL_NAME) objtype(channel) PRINCIPAL('$AUTH_USER') 
EOF

# Define the MQSC commands for topic removing
read -r -d '' MQSC_DEL_TOPIC<< EOF
DELETE TOPIC($TOPIC_NAME) AUTHREC(YES)
DELETE AUTHREC profile($TOPIC_NAME) objtype(topic) PRINCIPAL('$AUTH_USER') 
REFRESH SECURITY
EOF

# Call functions
printUsage
preCheck
removeQmgrAuth
deleteObjects
