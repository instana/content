#!/bin/bash
# Functions
printUsage() {
    echo -e "\033[1;33mThis script will delete the specified objects:\033[0m"
    echo "1. Check user running this script has authority to execute MQSC commands"
    echo "2. Remove the qmgr authority(connect+inq) for the specified user"
    echo "3. Delete the specified listener/channel/topic"
    echo -e "\033[1;33m Usage: $0 -q <QMGR_NAME> -d <MQ_BIN_PATH> [-u AUTH_USER] [-l LISTENER_NAME] [-c CHANNEL_NAME] [-t TOPIC_NAME]\033[0m"
    echo -e "\033[1;33m Example: $0 -q QM1 -d /opt/mqm/bin -u root -l LS2 -c INSTANA.ACE.SVRCONN -t INSTANA.ACE.BROKER.TOPIC\033[0m"
}

# 1. Check the current user has authority to execute MQSC commands
preCheck() {
    echo "Check if current user has the authority to execute MQSC commands"
    if groups | grep -q '\bmqm\b'; then
        echo -e "\033[1;32mINFO:The user launches the script belongs to mqm group\033[0m"
    else
        echo -e "\033[1;31mERROR:The user who launches the script doesn't belong to mqm group, please use an authorized user to execute MQSC commands\033[0m"
        exit 1
    fi

    echo "Check the MQ_BIN_PATH exists and file setmqenv exists"
    if [ ! -d "$MQ_BIN_PATH" ] || [ ! -f "$MQ_BIN_PATH/setmqenv" ]; then
        echo -e "\033[1;31mERROR: the path $MQ_BIN_PATH or the file $MQ_BIN_PATH/setmqenv does not exist or both don't exist.\033[0m"
        exit 1
    else
        echo -e "\033[1;32mINFO: the $MQ_BIN_PATH and related file setmqenv exist.\033[0m"
    fi    
}
# 2. remove authority to qmgr for specified user
removeQmgrAuth(){
    echo  -e "\033[1;33mINFO: Remove connect/inq authority to qmgr $QMGR_NAME for user $AUTH_USER listener object033[0m"
    setmqaut -m $QMGR_NAME -t qmgr -p $AUTH_USER -connect -inq
}

# 3. delete objects
deleteObjects() {
    if [ -n "$LISTENER_NAME" ]; then 
        echo  -e "\033[1;33mINFO: delete listener object033[0m"
        echo "stop LISTENER($LISTENER_NAME) IGNSTATE(NO)"  | runmqsc "$QMGR_NAME"
        echo "delete LISTENER($LISTENER_NAME) IGNSTATE(NO)" | runmqsc "$QMGR_NAME"
    else 
        echo -e "\033[1;32mINFO: nothing to delete as the listener name $LISTENER_NAME is empty\033[0m"
    fi

    if [ -n "$CHANNEL_NAME" ]; then 
        echo  -e "\033[1;33mINFO: delete channel object033[0m"
        echo "delete channel($CHANNEL_NAME) IGNSTATE(YES)" | runmqsc "$QMGR_NAME"
    else 
        echo -e "\033[1;32mINFO: nothing to delete as the channel name $CHANNEL_NAME is empty\033[0m"
    fi
    if [ -n "$TOPIC_NAME" ]; then 
        echo  -e "\033[1;33mINFO: delete topic object033[0m"
        echo "delete topic($TOPIC_NAME) AUTHREC(YES)"  | runmqsc "$QMGR_NAME"
    else 
        echo -e "\033[1;32mINFO: nothing to delete as the topic name $TOPIC_NAME is empty\033[0m"
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

# Setup mq environment to accept mqsc command. 
echo -e "\033[1;33mINFO: setup mq environment to accept mqsc command\033[0m"
. $MQ_BIN_PATH/setmqenv -s

# Call functions
printUsage
preCheck
removeQmgrAuth
deleteObjects
