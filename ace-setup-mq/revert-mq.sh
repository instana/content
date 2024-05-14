#!/bin/bash
# Functions
printUsage() {
    echo -e "\033[1;33mThis script will delete the specified objects:\033[0m"
    echo "1. Check user running this script has authority to execute MQSC commands"
    echo "2. Remove the qmgr authority(connect+inq) for the specified user"
    echo "3. Delete the specified listener/channel/topic"
    echo -e "\033[1;33m Usage: $0 -q <QMGR_NAME> -d <MQ_BIN_PATH> [-u AUTH_USER] [-l LISTENER_NAME] [-c CHANNEL_NAME] [-t TOPIC_NAME]\033[0m"
    echo -e "\033[1;33m Example: $0 -q QM1 -d /opt/mqm/bin -u root -l INSTANA.ACE.LST -c INSTANA.ACE.SVRCONN -t INSTANA.ACE.BROKER.TOPIC\033[0m"
}

# 1. Check the current user has authority to execute MQSC commands
preCheck() {
    # Check user authority
    echo "Check if current user has the authority to execute MQSC commands"
    if groups | tr ' ' '\n' | grep -q '^mqm$'; then
        echo -e "\033[1;32mINFO: The user launched the script belongs to mqm group\033[0m"
    else
        echo -e "\033[1;31mERROR: The user launched the script doesn't belong to mqm group, please use an authorized user to execute MQSC commands\033[0m"
        exit 1
    fi

    # check mq bin path 
    echo "Check the MQ_BIN_PATH exists and file setmqenv exists"
    if [ ! -d "$MQ_BIN_PATH" ] || [ ! -f "$MQ_BIN_PATH/setmqenv" ]; then
        echo -e "\033[1;31mERROR: The path $MQ_BIN_PATH or the file $MQ_BIN_PATH/setmqenv does not exist or both don't exist.\033[0m"
        exit 1
    else
        echo -e "\033[1;32mINFO: The $MQ_BIN_PATH and related file setmqenv exist.\033[0m"
    fi    

    # Setup mq environment to accept mqsc command. 
    echo -e "\033[1;33mINFO: Setup mq environment to accept mqsc command\033[0m"
    . $MQ_BIN_PATH/setmqenv -s 
    if [ $? -eq 0 ]; then
       echo -e "\033[1;32mINFO: The environment has been set successfully. \033[0m"
    else
       echo -e "\033[1;31mERROR: Failed to set the environment\033[0m"
       exit 1
    fi
}
# 2. remove authority to qmgr for specified user
removeQmgrAuth(){
    echo  -e "\033[1;33mINFO: Remove connect/inq authority to qmgr $QMGR_NAME for user $AUTH_USER listener object\033[0m"
    AUTH_RECORDS=$(dmpmqaut -m $QMGR_NAME -t qmgr -p $AUTH_USER 2>&1)
    echo "The user $AUTH_USER has following authority before removing: $AUTH_RECORDS"
    if [[ "$AUTH_RECORDS" == *"No matching authority records."* ]]; then 
            echo -e "\033[1;32mINFO: No matching authority records for $AUTH_USER\033[0m"
    else
        setmqaut -m $QMGR_NAME -t qmgr -p $AUTH_USER -connect -inq
        if [ $? -eq 0 ]; then
            echo -e "\033[1;32mINFO: The authority has been removed succesfully for user $AUTH_USER\033[0m"
            echo "The user $AUTH_USER has following authority after removing:"
        else
            echo -e "\033[1;31mERROR: Failed to remove the authority for user $AUTH_USER to $QMGR_NAME, please remove it manually\033[0m"
            echo "$(dmpmqaut -m $QMGR_NAME -t qmgr -p $AUTH_USER 2>&1)" 
        fi
   fi
   
}

# 3. delete objects
deleteObjects() {
    # delete listener
    if [ -n "$LISTENER_NAME" ]; then 
        echo  -e "\033[1;33mINFO: Delete listener object\033[0m"
        listener=$(echo "dis LISTENER($LISTENER_NAME)" | runmqsc "$QMGR_NAME" 2>&1)
        if [[ "$listener" == *"not found"* ]]; then
            echo -e "\033[1;32mINFO: Nothing to delete as the $LISTENER_NAME is not found\033[0m"
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
        echo -e "\033[1;32mINFO: Nothing to delete as the listener name is empty\033[0m"
    fi

    # delete channel
    if [ -n "$CHANNEL_NAME" ]; then 
        echo  -e "\033[1;33mINFO: Delete channel object\033[0m"
        channel=$(echo "dis CHANNEL($CHANNEL_NAME)" | runmqsc "$QMGR_NAME" 2>&1)
        if [[ "$channel" == *"not found"* ]]; then
            echo -e "\033[1;32mINFO: Nothing to delete as the $CHANNEL_NAME is not found\033[0m"
        else
            echo "delete CHANNEL($CHANNEL_NAME) IGNSTATE(YES)" | runmqsc "$QMGR_NAME"
            if [ $? -eq 0 ]; then
                echo  -e "\033[1;32mINFO: Channel $CHANNEL_NAME has been deleted successfully.\033[0m"
            else
                echo -e "\033[1;31mERROR: Failed to delete channel $CHANNEL_NAME, please remove it manually\033[0m"
                echo "dis CHANNEL($CHANNEL_NAME)" | runmqsc "$QMGR_NAME"
            fi
        fi
    else 
        echo -e "\033[1;32mINFO: Nothing to delete as the channel name is empty\033[0m"
    fi
    # delete topic
    if [ -n "$TOPIC_NAME" ]; then 
        echo  -e "\033[1;33mINFO: Delete topic object\033[0m"
        topic=$(echo "dis TOPIC($TOPIC_NAME)" | runmqsc "$QMGR_NAME" 2>&1)
        if [[ "$topic" == *"not found"* ]]; then
            echo -e "\033[1;32mINFO: Nothing to delete as the $TOPIC_NAME is not found\033[0m"
        else
            echo "delete TOPIC($TOPIC_NAME) AUTHREC(YES)" | runmqsc "$QMGR_NAME"
            if [ $? -eq 0 ]; then
                echo  -e "\033[1;32mINFO: Topic object $TOPIC_NAME has been deleted successfully.\033[0m"
            else
                echo -e "\033[1;31mERROR: Failed to delete topic object $TOPIC_NAME, please remove it manually\033[0m"
                echo "dis TOPIC($CHANNEL_NAME)" | runmqsc "$QMGR_NAME"
            fi
        fi
    else 
        echo -e "\033[1;32mINFO: Nothing to delete as the topic name is empty\033[0m"
    fi
}

# Init
# Check the parameters
while getopts ":q:d:u:l:c:t:" opt; do
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
    printUsage
    exit 1
fi

# Call functions
printUsage
preCheck
removeQmgrAuth
deleteObjects
