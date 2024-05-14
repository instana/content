# Testing the IBM MQ test JAR file

The purpose of the IBM MQ test JAR file is to test whether IBM MQ is configured and can be connected. You can select any of the following connection modes:

1. Local binding mode: Provide the `IBM MQ lib` path parameter. You can run the IBM MQ test JAR file on the same server where the IBM MQ runs.

2. Client binding mode: Provide the channel name and channel port to use the IBM MQ connection. If the security is enabled for the IBM MQ channel, then you need a username and password to log in to the channel. By using client binding mode, you can run the IBM MQ test JAR file on another server or on the same server where the IBM MQ runs. 
With this mode, you need to provide the channel name and channel port to try the IBM MQ connection. If the IBM MQ channel is security enabled, username and password is also needed. If you try this mode, you can run this jar on other server or the same server that the IBM MQ is running. 

## Usage

You can get the whole usge with the command:
java -jar ./testMQ.jar 

The output is like:
If you want to try local binding. The usage is: 
    java -jar ./testMQ.jar -m <qmgr-name> -a <lib-path> [-q <queueName>]

If you want to try client binding. The usage is:
    java -jar ./testMQ.jar -h <host> -p <port> -c <channel> [-u <user>] [-z <password>] [-q <queueName>] [-k <keystore>] [-w <keystore-password>] -s [<ciph-suite>]

Here are the examples:

1. Local binding mode:
java -jar ./testMQ.jar -m qmName -a /opt/mqm/java/lib64 -q SYSTEM.ADMIN.ACCOUNTING.QUEUE

2. Client binding mode:
java -jar ./testMQ.jar -m qmName -h 1.2.3.4 -p 1801 -c SYSTEM.AUTO.SVRCONN -u root -z dummyPwd -q AAA
