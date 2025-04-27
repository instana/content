#!/bin/bash
#Functions
# 0: print usage
printUsage(){
    echo "Description: "
    echo "This script will try to cover following things:"
    echo "1. Check user running this script has authority to execute MQSC commands"
    echo "2. Check the available listener ports and define a new one if there is no available"
    echo "3. Define a channel and set authrec for it with the specified user."
    echo "4. Check the connectivity of the channel with specified user"
    echo "5. Define a topic or use existing topic object for topic string '$SYS/Broker' and set authrec for it"
    echo "6. List the useful info you can use to set in configuration.yaml for plugin.ace and plugin.ibmmq"
    echo -e "\033[1;33mNote: this script will cover most cases, but sometimes if you fail to create the mq objects, please contact IBM Instana support or contact IBM MQ support team for help. \033[0m"
    echo ""
    echo "Usage: $0 -q <QMGR_NAME> -d <MQ_BIN_PATH> -u <AUTH_USER>  [-c CHANNEL_NAME] [-m]"
    echo "Example: "
    echo "      $0 -q QM1 -d /opt/mqm/bin -u root -c INSTANA.SVRCONN -m" 
    echo "      $0 -q QM1 -d /opt/mqm/bin -u root -m" 
    echo "      $0 -q QM1 -d /opt/mqm/bin -u root -c INSTANA.SVRCONN" 
    echo "      $0 -q QM1 -d /opt/mqm/bin -u root"
    echo ""
    echo "Arguments:"
    echo "  -q  <QMGR_NAME>     Required. Specify the queuemanager name to execute the script with"
    echo "  -d  <MQ_BIN_PATH>   Required. Specify the mq bin path"
    echo "  -u  <AUTH_USER>     Required. Specify the user to give authority for mq/ace monitoring"
    echo "  -c  <CHANNEL_NAME>  Optional. Specify the channel to be created. If not specify, the default channel INSTANA.SVRCONN will be used."  
    echo "  -m                  Optional. Set up MQ channel for MQ sensor only. If not set, both channel and topic will be created to support both mq sensor and ace sensor."
}

# 1. Check the current user has authority to execute MQSC commands
preCheck(){
    # Check user authority
    if groups | tr ' ' '\n' | grep -q '^mqm$'; then
        echo "INFO: The user launched the script belongs to mqm group"
    else
        echo -e "\033[1;31mERROR: The user launched the script doesn't belong to mqm group, please use an authorized user to execute MQSC commands\033[0m"
        exit 1
    fi

    # check mq bin path 
    echo "INFO: Check the MQ_BIN_PATH exists and file setmqenv exists"
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

# check permission
check_permission() {
  local permission=$1
  permissions=$(dspmqaut -m $QMGR_NAME -t qmgr -p $AUTH_USER)
  if echo "$permissions" | grep -q "$permission"; then
    return 0  # the permission exists
  else
    return 1  # the permission doesn't exist
  fi
}

# 2. Set correct authority for $AUTH_USER to access QMGR.
setQmgrAuth(){
    echo "INFO: Check authority for user $AUTH_USER to access QMGR."
    PERMS=("connect" "inq")
    for PERM in "${PERMS[@]}"; do
        if ! check_permission $PERM; then
            setmqaut -m $QMGR_NAME -t qmgr -p $AUTH_USER +$PERM >/dev/null 2>&1
            PERMISSIONS_NEW+=("$PERM")
        fi
    done 
    if [ ${#PERMISSIONS_NEW[@]} -ne 0 ]; then
        echo "INFO: Newly added permissions for user $AUTH_USER on QMGR $QMGR_NAME: ${PERMISSIONS_NEW[*]}"
    else
        echo "INFO: No new permissions were added for user $AUTH_USER on QMGR $QMGR_NAME"
    fi
}

# 3. Print out all available listener ports
getListenerPort(){
    listener_ports=$(echo "dis LISTENER(*) PORT" | runmqsc "$QMGR_NAME" | awk '/PORT/ {gsub("[^0-9]", "", $NF); print $NF}')
    if [ -n "$listener_ports" ]; then
       while read -r port; do
            if checkPort $port; then
                AVAILABLE_PORTS+=" $port"
            fi
        done <<< "$listener_ports"
    fi
    if [ -n "$AVAILABLE_PORTS" ]; then
        echo "INFO: Found available ports: $AVAILABLE_PORTS"
    else
        echo "Create a listener as there is no listener port found"
        echo "DEFINE LISTENER($LISTENER_NAME) TRPTYPE(TCP) PORT($LISTENER_PORT)" | runmqsc "$QMGR_NAME" >/dev/null 2>&1
        echo "START LISTENER($LISTENER_NAME) IGNSTATE(NO)" | runmqsc "$QMGR_NAME" >/dev/null 2>&1
        LISTENER_NEW=$LISTENER_NAME
        if checkPort $LISTENER_PORT; then
            AVAILABLE_PORTS+=" $LISTENER_PORT"
        else
            echo -e "\033[1;31mERROR: Port $LISTENER_PORT is not open or not accepting connections. Please check and fix.\033[0m" 
            exit 1
        fi
    fi
}

checkPort() {
    local port="$1"
    local os_type
    os_type=$(uname -s)

    if [ -z "$port" ] || [ "$port" -eq 0 ]; then
        return 1
    fi

    if [[ "$os_type" == "Linux" ]]; then
        if command -v nc >/dev/null 2>&1; then
            nc -zv localhost "$port" >/dev/null 2>&1
            return $?
        else
            echo "[INFO] 'nc' command not found. Falling back to 'netstat'."
        fi
    else
        if command -v telnet >/dev/null 2>&1; then
            (echo quit | telnet localhost "$port") >/dev/null 2>&1
            return $?
        else
            echo "[INFO] 'telnet' command not found. Falling back to 'netstat'."
        fi
    fi

    # common fallback to netstat for both Linux and AIX
    netstat -an 2>/dev/null | awk -v port="$port" '
        $0 ~ /LISTEN/ && (
            ($4 ~ ":" port "$") ||   # Linux style: 0.0.0.0:22
            ($4 ~ "\\." port "$")     # AIX style: *.22 or 127.0.0.1.8050
        )
    ' >/dev/null 2>&1
    return $?
}

# 4. Create channel and topic, set authrec for them.
prepChannelAndTopic(){
    CHECK_CHANNEL=$(echo "DISPLAY CHANNEL($CHANNEL_NAME)" | runmqsc "$QMGR_NAME")
    if [[ "$CHECK_CHANNEL" != *"not found"* ]]; then 
        echo "$CHECK_CHANNEL"
        echo -e "\033[1;31mERROR: The channel $CHANNEL_NAME already exists, please use a different name or delete the existing channel and rerun the script. \033[0m"

        if [[ ${#PERMISSIONS_NEW[@]} -ne 0  ||  -n "$LISTENER_NEW" ]]; then
            echo -e "\033[1;31mNOTE: Following objects/permissions are changed or created, please revert them manually or use script revert-mq.sh to clean up before rerunning: \033[0m"
            if [ ${#PERMISSIONS_NEW[@]} -ne 0 ]; then
                echo "Permissions added on QMGR $QMGR_NAME for user $AUTH_USER: ${PERMISSIONS_NEW[*]}"
            fi
            if [ -n "$LISTENER_NEW" ]; then
                echo "Listener new created: $LISTENER_NEW"
            fi
        fi
        exit 1
    fi
    # Execute the MQSC commands
    echo "$MQSC_CHECK_CHANNEL" | runmqsc "$QMGR_NAME"

    # Verify the user authority of channel connection
    OUTPUT=$(echo "dis chlauth($CHANNEL_NAME) MATCH(RUNCHECK) CLNTUSER('$AUTH_USER') ADDRESS('0.0.0.0')" | runmqsc "$QMGR_NAME")
    EXPECTED_OUTPUT="AMQ9783I: Channel will run using MCAUSER('$AUTH_USER')."                     

    if [[ "$OUTPUT" == *"$EXPECTED_OUTPUT"* ]]; then
        echo "INFO: The channel authority is set successfully with output: $EXPECTED_OUTPUT"
        if [ "${TYPE}" != "mq" ]; then
            EXISTING_TOPIC=$(echo "dis TOPIC(*) WHERE(TOPICSTR EQ '$TOPIC_STR')" | runmqsc "$QMGR_NAME")
            # Create a topic if it doesn't exist
            if [[ $EXISTING_TOPIC == *"not found"* ]]; then
                echo "INFO: Topic object with TOPICSTR '$TOPIC_STR' not found. Creating a new one..."
                echo "DEFINE TOPIC($TOPIC_NAME) TOPICSTR('$TOPIC_STR')" | runmqsc "$QMGR_NAME"
                TOPIC_NEW=$TOPIC_NAME
            else
                echo "INFO: Topic object with TOPICSTR '$TOPIC_STR' already exists."
                TOPIC_NAME=$(echo "$EXISTING_TOPIC" | sed -n '/TOPIC(\*/d; s/^.*TOPIC(\([^)]*\)).*$/\1/p')
            fi
            # Set authrec for the topic
            echo "$MQSC_SET_AUTH_4_TOPIC" | runmqsc "$QMGR_NAME"
            echo "INFO: Set authrec for the topic $TOPIC_NAME"
            # Verify the authrec exists
            EXISTING_AUTHREC=$(echo "DIS AUTHREC PROFILE($TOPIC_NAME) OBJTYPE(TOPIC) PRINCIPAL('$AUTH_USER')" | runmqsc "$QMGR_NAME")
            # Print the result 
            if [[ $EXISTING_AUTHREC == *"not found"* ]]; then
                echo -e "\033[1;31mERROR: AUTHREC for topic '$TOPIC_NAME' does not exist. Please fix the issue according to the commands execution result. \033[0m"
                echo "$EXISTING_AUTHREC"
                exit 1
            else
                echo "INFO: AUTHREC for topic '$TOPIC_NAME' exists."
            fi
        fi
    else
        echo -e "\033[1;31mERROR: The channel authority is failed to set. Fix it by removing the blocking AUTHREC and then rerun the script.\033[0m"
        echo -e "$OUTPUT"
        echo -e "\033[1;31mNOTE: Following objects/permissions are changed or created, please revert them manually or use script revert-mq.sh to clean up before rerunning: \033[0m"
        if [ ${#PERMISSIONS_NEW[@]} -ne 0 ]; then
            echo "Permissions added on QMGR: $QMGR_NAME for user:  $AUTH_USER: ${PERMISSIONS_NEW[*]}"
        fi
        if [ -n "$LISTENER_NEW" ]; then
            echo "Listener new created: $LISTENER_NEW"
        fi
        CHANNEL_AUTHREC_NEW=$(echo "DIS AUTHREC PROFILE($CHANNEL_NAME) OBJTYPE(CHANNEL) PRINCIPAL('$AUTH_USER')")
        CHLAUTH_NEW=$(echo "DIS CHLAUTH($CHANNEL_NAME) TYPE(BLOCKUSER)")
        echo "Channel new created: $CHANNEL_NAME"
        echo "AUTHREC new added for channel $CHANNEL_NAME:"
        echo "$CHANNEL_AUTHREC_NEW"
        echo "CHLAUTH new added for channel $CHANNEL_NAME:"
        echo "$CHLAUTH_NEW"
        exit 1           
    fi
}

# 5. Print out useful info you need in setting configuration.yaml
printConnInfo(){

    echo -e "\033[1;32mINFO: You have prepared the MQ objects for Instana monitoring well. Following Objects and Permissions are new added:\033[0m"
    if [ ${#PERMISSIONS_NEW[@]} -ne 0 ]; then
        echo  -e "\033[1;32mPermissions added on QMGR $QMGR_NAME for user $AUTH_USER: \033[0m"
        echo "${PERMISSIONS_NEW[*]}"
    fi
    if [ -n "$LISTENER_NEW" ]; then
        echo -e "\033[1;32mListener new created: \033[0m"
        echo "$LISTENER_NEW"
    fi
    echo -e "\033[1;32mChannel new created:  \033[0m"           
    echo "$CHANNEL_NAME"
    echo -e "\033[1;32mAUTHREC and CHLAUTH new added for channel $CHANNEL_NAME:\033[0m"
    echo "CHLAUTH($CHANNEL_NAME) TYPE(BLOCKUSER) USERLIST('nobody') DESCR('Block all users except authorized users')"
    echo "AUTHREC profile($CHANNEL_NAME) objtype(channel) PRINCIPAL('$AUTH_USER') AUTHADD(ALL)"
    if [ "${TYPE}" != "mq" ]; then
        if [ -n "$TOPIC_NEW" ]; then
            echo -e "\033[1;32mTopic new created:           $TOPIC_NEW\033[0m"
        fi
        echo  -e "\033[1;32mAUTHREC new added for topic $TOPIC_NAME:\033[0m"
        echo "AUTHREC profile($TOPIC_NAME) objtype(topic) PRINCIPAL('$AUTH_USER') AUTHADD(ALL)"
        echo ""

        echo -e "\033[1;32mYou can set the configuration.yaml for ACE sensor with following info:\033[0m"
        echo "queuemanagerName:   $QMGR_NAME"
        echo "mqport:            $AVAILABLE_PORTS (choose one)"
        echo "channel:            $CHANNEL_NAME"
        echo "mqUsername:         $AUTH_USER"
        echo ""
    fi

    echo -e "\033[1;32mYou can set the configuration.yaml for MQ sensor with following info:\033[0m"
    echo "QUEUE_MANAGER_NAME_1: $QMGR_NAME"
    echo "port:                 $AVAILABLE_PORTS (choose one)"
    echo "channel:              $CHANNEL_NAME"
    echo "username:             $AUTH_USER"
    echo ""

    echo -e "\033[1;32mThis tool only covers basic info, for other info, like user password and SSL related info, please check manually and set properly.\033[0m"
    echo -e  "\033[1;33mINFO: To revert the permissions added and objects created, download the revert-mq.sh script and run like following: \033[0m"
    local opt_p=''
    local opt_l=''
    local opt_t=''
    if [ ${#PERMISSIONS_NEW[@]} -ne 0 ]; then
        opt_p="-p '${PERMISSIONS_NEW[*]}'"
    fi
    if [ -n "$LISTENER_NEW" ]; then
        opt_l="-l $LISTENER_NEW"
    fi
    if [ -n "$TOPIC_NEW" ]; then
        opt_t="-t $TOPIC_NEW"
    fi
    echo "./revert-mq.sh -q $QMGR_NAME -d $MQ_BIN_PATH -u $AUTH_USER $opt_p $opt_l -c $CHANNEL_NAME $opt_t"
}


# 0: Init
# Define the variables 
CHANNEL_NAME='INSTANA.SVRCONN'
TOPIC_NAME='INSTANA.ACE.BROKER.TOPIC'
TOPIC_STR='$SYS/Broker'
LISTENER_NAME='INSTANA.LST'
LISTENER_PORT='2121'
AVAILABLE_PORTS=''
PERMISSIONS_NEW=()
LISTENER_NEW=''
TOPIC_NEW=''
TYPE="ace"

# Check the parameters
while getopts ":q:d:u:c:m" opt; do
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
        c)
          CHANNEL_NAME=${OPTARG}
          ;;
        m)
          TYPE="mq"
          ;;
        ?)
          printUsage
          exit 1
          ;;
    esac
done
shift $(($OPTIND - 1))

if [[ -z "$QMGR_NAME" || -z "$MQ_BIN_PATH" || -z "$AUTH_USER" ]]; then
    echo -e "\033[1;31mERROR: These arguments are required, but seems they are not set correctly.\033[0m"
    echo "-q <QMGR_NAME> -d <MQ_BIN_PATH> -u <AUTH_USER>"
    echo ""
    printUsage
    exit 1
fi
if [ -z "$CHANNEL_NAME" ]; then
    CHANNEL_NAME='INSTANA.SVRCONN'
fi

# Define the MQSC commands for channel creating
read -r -d '' MQSC_CHECK_CHANNEL << EOF
DEFINE CHANNEL($CHANNEL_NAME) CHLTYPE(SVRCONN) TRPTYPE(TCP) MCAUSER('$AUTH_USER')
SET CHLAUTH($CHANNEL_NAME) TYPE(BLOCKUSER) USERLIST('nobody') DESCR('Block all users except authorized users')
SET AUTHREC profile($CHANNEL_NAME) objtype(channel) PRINCIPAL('$AUTH_USER') AUTHADD(ALL)
REFRESH SECURITY
EOF

read -r -d '' MQSC_SET_AUTH_4_TOPIC << EOF
SET AUTHREC profile($TOPIC_NAME) objtype(topic) PRINCIPAL('$AUTH_USER') AUTHADD(ALL)
REFRESH SECURITY
EOF

printUsage
preCheck
setQmgrAuth
getListenerPort
prepChannelAndTopic
printConnInfo
