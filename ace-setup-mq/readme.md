# Instructions for setup-channel.sh
## Descriptions 
The script `setup-channel.sh` is used to create resources and set authority properly in QMGR for ACE sensor. 
## Usage
1. Download the script remove-resources.sh 
2. Set it executable
3. Go to the directory and execute the script
```sh
    ./setup-channel.sh <QMGR_NAME>  <MQ_BIN_PATH>  <AUTH_USER>
```
# Instructions for remove-resources.sh
## Descriptions
The script `remove-resources.sh` is used to revert the authority granted with script `setup-channel.sh` and delete the objects created in QMGR for ACE sensor. 
## Usage
1. Download the script remove-resources.sh 
2. Set it executable
3. Go to the directory and execute the script
```sh
    ./remove-resources.sh -q <QMGR_NAME> -d <MQ_BIN_PATH> [-u AUTH_USER] [-l LISTENER_NAME]  [-c CHANNEL_NAME]  [-t TOPIC_NAME]
```
   




