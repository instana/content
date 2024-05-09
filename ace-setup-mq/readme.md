# Instructions for setup-channel.sh
## Descriptions 
The script `setup-channel.sh` is used to create resources and set authority properly in QMGR for ACE sensor. 
## Usage
1. Download the script `setup-channel.sh`
2. Set it executable `chmod +x setup-channel.sh`
3. Go to the directory and execute the script
```sh
    ./setup-channel.sh <QMGR_NAME>  <MQ_BIN_PATH>  <AUTH_USER>
```
**Note:** the user to execute the script should be a member of mqm group. It is different than $AUTH_USER in the script.
# Instructions for remove-resources.sh
## Descriptions
The script `remove-resources.sh` is used to revert the authority granted with script `setup-channel.sh` and delete the objects created in QMGR for ACE sensor. 
## Usage
1. Download the script `remove-resources.sh`
2. Set it executable `chmod +x remove-resources.sh`
3. Go to the directory and execute the script
```sh
    ./remove-resources.sh -q <QMGR_NAME> -d <MQ_BIN_PATH> [-u AUTH_USER] [-l LISTENER_NAME]  [-c CHANNEL_NAME]  [-t TOPIC_NAME]
```
**Note:** the user to execute the script should be a member of mqm group. It is different than $AUTH_USER in the script.
   




