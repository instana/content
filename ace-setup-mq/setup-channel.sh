#!/bin/bash
#Functions
# 0: print usage
printUsage(){
    echo -e "\033[1;33mThis script will try to cover following things:\033[0m"
    echo "1. Check user running this script has authority to execute MQSC commands"
    echo "2. Check the available listener ports and define a new one if there is no available"
    echo "3. Define a channel and set authrec for it with the specified user"
    echo "4. Check the connectivity of the channel with specified user"
    echo "5. Define a topic or use existing topic object for topic string '$SYS/Broker' and set authrec for it"
    echo "6. List the useful info you can use to set in configuration.yaml for plugin.ace"
    echo -e "\033[1;31mNote: this script will cover most cases, but sometimes if you fail to create the mq objects, please contact IBM Instana support or contact IBM MQ support team for help. \033[0m"
    echo -e "\033[1;33mUsage: $0 -q <QMGR_NAME> -d <MQ_BIN_PATH> -u <AUTH_USER>\033[0m"
    echo -e "\033[1;33mExample $0 -q QM1 -d /opt/mqm/bin -u root\033[0m"
}

# 1. Check the current user has authority to execute MQSC commands
preCheck(){
    if groups | grep -q '\bmqm\b'; then
        echo -e "\033[1;32mINFO:The user who launches the script belongs to mqm group\033[0m"
    else
        echo -e "\033[1;31mERROR:The user launches the script doesn't belong to mqm group, please use an authorized user to execute MQSC commands\033[0m"
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
# 2. Set correct authority for $AUTH_USER to access QMGR.
setQmgrAuth(){
    echo -e "\033[1;33mINFO: set authority for user $AUTH_USER to access QMGR.\033[0m"
    RESULT=$(echo "setmqaut -m $QMGR_NAME -t qmgr -p $AUTH_USER +connect +inq")
    if [[ "$RESULT" != *"completed successfully"* ]]; then
       echo -e "\033[1;31mERROR: failed to set the authority for user $AUTH_USER to $QMGR_NAME\033[0m"
       echo -e "\033[1;31m$RESULT\033[0m"
       exit 1
    else
        echo "dmpmqaut -m $QMGR_NAME -t qmgr"
    fi
}
# 3. Print out all available listener ports
getListenerPort(){
    listener_ports=$(echo "dis LISTENER(*) PORT" | runmqsc "$QMGR_NAME" |  grep -oP 'PORT\(\K\d+')
    if [ -n "$listener_ports" ]; then
       while read -r port; do
            if checkPort $port; then
                AVAILABLE_PORTS+=" $port"
                echo -e "\033[1;32mINFO: Port $port is open and accepting connections.\033[0m"
            else
                echo -e "\033[1;33mWARNING: Port $port is not open or not accepting connections.\033[0m"
            fi
        done <<< "$listener_ports"
    else
        echo "Create a listener as there is no listener port found"
        echo "DEFINE LISTENER($LISTENER_NAME) TRPTYPE(TCP) PORT($LISTENER_PORT)" | runmqsc "$QMGR_NAME"
        echo "START LISTENER($LISTENER_NAME) IGNSTATE(NO)" | runmqsc "$QMGR_NAME" 
        if checkPort $LISTENER_PORT; then
            AVAILABLE_PORTS+=" $LISTENER_PORT"
            echo -e "\033[1;32mINFO: Port $LISTENER_PORT is open and accepting connections.\033[0m"
        else
            echo -e "\033[1;31mERROR: Port $LISTENER_PORT is not open or not accepting connections. Please check and fix.\033[0m" 
            exit 1
        fi
    fi
}

checkPort() {
    local port="$1"
    nc -zv localhost "$port" >/dev/null 2>&1
}

# 4. Create channel and topic, set authrec for them.
prepChannelAndTopic(){
    CHECK_CHANNEL=$(echo "DISPLAY CHANNEL($CHANNEL_NAME)" | runmqsc "$QMGR_NAME")
    if [[ "$CHECK_CHANNEL" != *"not found"* ]]; then 
        echo -e "\033[1;31mERROR:The channel exists, please try another CHANNEL_NAME or delete the existing channel and rerun the script. \033[0m"
        echo -e "\033[1;31mT$CHECK_CHANNEL\033[0m"
        exit 1
    fi
    # Execute the MQSC commands
    echo "$MQSC_CHECK_CHANNEL" | runmqsc "$QMGR_NAME"

    # Verify the user authority of channel connection
    OUTPUT=$(echo "dis chlauth($CHANNEL_NAME) MATCH(RUNCHECK) CLNTUSER('$AUTH_USER') ADDRESS('0.0.0.0')" | runmqsc "$QMGR_NAME")
    EXPECTED_OUTPUT="AMQ9783I: Channel will run using MCAUSER('$AUTH_USER')."                     

    if [[ "$OUTPUT" == *"$EXPECTED_OUTPUT"* ]]; then
        echo -e "\033[1;32mINFO:The channel authority is set successfully with output:\033[0m"
        echo -e "\033[1;32m$EXPECTED_OUTPUT\033[0m"
        EXISTING_TOPIC=$(echo "dis TOPIC(*) WHERE(TOPICSTR EQ '$TOPIC_STR')" | runmqsc "$QMGR_NAME")
        # Create a topic if it doesn't exist
        if [[ $EXISTING_TOPIC == *"not found"* ]]; then
            echo "Topic object with TOPICSTR '$TOPIC_STR' not found. Creating a new one..."
            echo "DEFINE TOPIC($TOPIC_NAME) TOPICSTR('$TOPIC_STR')" | runmqsc "$QMGR_NAME"
        else
            echo -e "\033[1;32mINFO:Topic object with TOPICSTR '$TOPIC_STR' already exists.\033[0m"
            TOPIC_NAME=$(echo "$EXISTING_TOPIC" | sed -n '/TOPIC(\*/d; s/^.*TOPIC(\([^)]*\)).*$/\1/p')
        fi
        # Set authrec for the topic
        echo "SET AUTHREC profile($TOPIC_NAME) objtype(topic) PRINCIPAL('$AUTH_USER') AUTHADD(ALL)"
        echo "Set authrec for the topic $TOPIC_NAME"
        # Verify the authrec exists
        EXISTING_AUTHREC=$(echo "DIS AUTHREC PROFILE($TOPIC_NAME) OBJTYPE(TOPIC)" | runmqsc "$QMGR_NAME")
        # Print the result 
        if [[ $EXISTING_AUTHREC == *"not found"* ]]; then
            echo -e "\033[1;31mERROR:AUTHREC for topic '$TOPIC_NAME' does not exist.Please check the commands execution result\033[0m"
            echo "$EXISTING_AUTHREC"
            exit 1
        else
            echo -e "\033[1;32mINFO:AUTHREC for topic '$TOPIC_NAME' exists.\033[0m"
        fi
    else
        echo -e "\033[1;31mERROR:The channel authority is failed to set. Check the blocking AUTHREC and fix it.\033[0m"
        echo -e "$OUTPUT"
        exit 1
    fi
}

# 5. Print out useful info you need in setting configuration.yaml
printConnInfo(){
    echo -e "\033[1;32mHint: Please set the configuration.yaml for ACE sensor with following info:\033[0m"
    echo -e "\033[1;32m queuemanagerName:  $QMGR_NAME\033[0m"
    echo -e "\033[1;32m mqport:           $AVAILABLE_PORTS\033[0m"
    echo -e "\033[1;32m channel:           $CHANNEL_NAME\033[0m"
    echo -e "\033[1;32m mqUsername:        $AUTH_USER\033[0m"
    echo -e "\033[1;32mThis tool only covers basic info, for other info, like user password and SSL related info, please check manually and set properly.\033[0m"
    echo -e  "\033[1;33mINFO: If you want to revert the authority and clean up the objects created,  please make sure you have downloaded the remove-resources.sh script and run like following: \033[0m"
    echo "./remove-resources.sh -q $QMGR_NAME -d $MQ_BIN_PATH -u $AUTH_USER -l $LISTENER_NAME -c $CHANNEL_NAME -t $TOPIC_NAME"
}


# 0: Init
# Define the variables 
CHANNEL_NAME='INSTANA.ACE.SVRCONN'
TOPIC_NAME='INSTANA.ACE.BROKER.TOPIC'
TOPIC_STR='$SYS/Broker'
LISTENER_NAME='INSTANA.ACE.LS'
LISTENER_PORT='2121'
AVAILABLE_PORTS=''
# Check the parameters
while getopts ":q:d:u:" opt; do
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

# Define the MQSC commands fro channel creating
read -r -d '' MQSC_CHECK_CHANNEL << EOF
DEFINE CHANNEL($CHANNEL_NAME) CHLTYPE(SVRCONN) TRPTYPE(TCP) MCAUSER('$AUTH_USER')
SET CHLAUTH($CHANNEL_NAME) TYPE(BLOCKUSER) USERLIST('nobody') DESCR('Block all users except authorized users')
SET AUTHREC profile($CHANNEL_NAME) objtype(channel) PRINCIPAL('$AUTH_USER') AUTHADD(ALL)
REFRESH SECURITY
EOF

printUsage
preCheck
setQmgrAuth
getListenerPort
prepChannelAndTopic
printConnInfo
