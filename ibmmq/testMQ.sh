#!/bin/bash

if [ "x$JAVA_HOME" = "x" ]
then
    echo "Please set JAVA_HOME"
    exit 1  
fi 

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")

$JAVA_HOME/bin/java -jar ${SCRIPT_DIR}/testMQ.jar $@