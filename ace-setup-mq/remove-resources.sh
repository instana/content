#!/bin/bash
# Functions
printUsage() {
    echo -e "\033[1;33mThis script will delete the specified objects:\033[0m"
    echo "1. Check user running this script has authority to execute MQSC commands"
    echo "2. Delete the specified listener"
    echo "3. Delete the specified  channel"
    echo "4. Delete the specified topic"
    echo "Usage: $0 -q QMGR_NAME -u AUTH_USER -b MQ_BIN_PATH -l LISTENER_NAME -c CHANNEL_NAME -t TOPIC_NAME"
    echo "Example: $0 -q QM1 -b /opt/mqm/bin -l LS2 -c INSTANA.ACE.SVRCONN -t INSTANA.ACE.BROKER.TOPIC"
}

# 1. Check the current user has authority to execute MQSC commands
checkUserAuthority() {
    if groups | grep -q '\bmqm\b'; then
        echo -e "\033[1;32mINFO:The user launches the script belongs to mqm group\033[0m"
    else
        echo -e "\033[1;31mERROR:The user launches the script doesn't belong to mqm group, please use an authorized user to execute MQSC commands\033[0m"
        exit 1
    fi
}

# 2. delete objects
deleteListener() {
    if [ -n "$LISTENER_NAME" ]; then 
        echo "stop and delete listener"
        echo "stop LISTENER($LISTENER_NAME) IGNSTATE(YES)"  | runmqsc "$QMGR_NAME"
        echo "delete LISTENER($LISTENER_NAME) IGNSTATE(YES)" | runmqsc "$QMGR_NAME"
    fi
    
}
deleteChannel() {
    if [ -n "$CHANNEL_NAME" ]; then 
        echo "delete channel object"
        echo "delete channel($CHANNEL_NAME) IGNSTATE(NO)" | runmqsc "$QMGR_NAME"
    fi
}
deleteTopic() {
    if [ -n "$TOPIC_NAME" ]; then 
        echo "delete topic object"
        echo "delete topic($TOPIC_NAME) AUTHREC(YES)"  | runmqsc "$QMGR_NAME"
    fi
}


# Init
# Check the parameters
while getopts "q:u:b:l:c:t:" arg; do
    case ${arg} in
        q)
          QMGR_NAME=${OPTARG}
          ;;
        b)
          MQ_BIN_PATH=${OPTARG}
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
echo "INFO: setup mq environment to accept mqsc command"
. $MQ_BIN_PATH/setmqenv -s


printUsage
checkUserAuthority
deleteListener
deleteChannel
deleteTopic