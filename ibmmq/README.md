# IBM MQ connection test tool

The purpose of the IBM MQ connection test tool is to test whether IBM MQ is configured and can be connected. You can select either of the following connection modes:

1. Local binding mode: Provide the `IBM MQ lib` path parameter. You can run the IBM MQ test tool on the same server where the IBM MQ runs.

2. Client binding mode: Provide the channel name and channel port to use the IBM MQ connection. If the security is enabled for the IBM MQ channel, then you need a username and password to log in to the channel. By using client binding mode, you can run the IBM MQ test tool on another server or on the same server where the IBM MQ runs. 

## Usage of the IBM MQ connection test tool

- You need to export the `JAVA_HOME` environment variable before you use the IBM MQ connection test tool.

- You can obtain the usage with the command: 

  ```
  ./testMQ.sh -help 
  ```
  {: codeblock}

- To use the IBM MQ connection test tool in the local binding mode, run the following sample command: 

  ```
  ./testMQ.sh -m <qmgr-name> -a <lib-path> [-q <queueName>]
  ```
  {: codeblock}

For example, ./testMQ.sh -m qmName -a /opt/mqm/java/lib64 -q SYSTEM.ADMIN.ACCOUNTING.QUEUE

- To use the IBM MQ connection test tool in the client binding mode, run the following sample command: 

  ```
  ./testMQ.sh -m <qmgr-name> -h <host> -p <port> -c <channel> [-u <user>] [-z <password>] [-q <queueName>] [-k <keystore>] [-w <keystore-password>] -s [<ciph-suite>]
  ```
  {: codeblock}

For example, ./testMQ.sh -m qmName -h 1.2.3.4 -p 1801 -c SYSTEM.AUTO.SVRCONN -u root -z dummyPwd -q AAA

## Rebuild the IBM MQ connection test JAR file

If you need to update the `./testMQ.jar` file, you can modify the source code in the `src` directory, and run the following command to trigger the rebuild:

```
mvn clean package
```
{: codeblock}

The new `testMQ-1.0-SNAPSHOT.jar` file is generated in the `target` directory. You can replace the `testMQ.jar` file with the `./target/testMQ-1.0-SNAPSHOT.jar` file and use the IBM MQ connection test tool `./testMQ.sh` with the new `testMQ.jar`file.