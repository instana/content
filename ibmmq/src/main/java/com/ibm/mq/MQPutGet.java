package com.ibm.mq;

import com.ibm.mq.constants.CMQC;
import com.ibm.mq.constants.CMQCFC;
import com.ibm.mq.constants.MQConstants;
import com.ibm.mq.headers.pcf.PCFMessage;
import com.ibm.mq.headers.pcf.PCFMessageAgent;

import javax.net.ssl.KeyManagerFactory;
import javax.net.ssl.SSLContext;
import javax.net.ssl.SSLSocketFactory;
import javax.net.ssl.TrustManagerFactory;
import java.io.BufferedReader;
import java.io.File;
import java.io.FileInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.lang.reflect.Field;
import java.security.GeneralSecurityException;
import java.security.KeyStore;
import java.security.SecureRandom;
import java.util.Hashtable;

public class MQPutGet {
    private static final String ALL_QUEUES_WILDCARD = "*";

    private static void usage() {
        System.out.println("==================================================================================");
        System.out.println("If you want to try local binding. The usage is: ");
        System.out.println("    java -jar ./testMQ.jar -m <qmgr-name> -a <lib-path> [-q <queueName>]");
        System.out.println("");
        System.out.println("If you want to try client binding. The usage is:");
        System.out.println("    java -jar ./testMQ.jar -m <qmgr-name> -h <host> -p <port> -c <channel> [-u <user>] [-z <password>] " + "[-q <queueName>] [-k <keystore>] [-w <keystore-password>] -s [<ciph-suite>]");
        System.out.println("==================================================================================");
    }

    public static boolean isEmpty(CharSequence cs) {
        return cs == null || cs.length() == 0;
    }

    private static boolean isNotBlank(CharSequence cs) {
        return !isEmpty(cs);
    }

    private static boolean isIbmJre() {
        String javaHome = System.getProperty("java.home");
        String javaPath = javaHome + File.separator + "bin" + File.separator + "java";
        String javaVendor = null;

        String[] command = {javaPath, "-XshowSettings:properties", "-version"};
        try {
            Process process = new ProcessBuilder(command).start();

            BufferedReader reader = new BufferedReader(new InputStreamReader(process.getErrorStream()));
            String line;
            while ((line = reader.readLine()) != null) {
                if (line.trim().contains("java.vendor =")) {
                    String[] arr = line.split("=");
                    if (arr.length == 2) {
                        javaVendor = arr[1].trim();
                    }
                }
            }

            if (javaVendor != null && javaVendor.equalsIgnoreCase("ibm")) {
                return true;
            }

        } catch (IOException e) {
            e.printStackTrace();
        }

        return false;
    }

    private static void addMqLibPath(String s) {
        System.out.println("Add library path " + s);

        try {
            // This enables the java.library.path to be modified at runtime
            // From a Sun engineer at http://forums.sun.com/thread.jspa?threadID=707176
            Field field = ClassLoader.class.getDeclaredField("usr_paths");
            field.setAccessible(true);
            String[] paths = (String[]) field.get(null);
            for (String path : paths) {
                if (s.equals(path)) {
                    return;
                }
            }

            String[] tmp = new String[paths.length + 1];
            System.arraycopy(paths, 0, tmp, 0, paths.length);
            tmp[paths.length] = s;
            field.set(null, tmp);
        } catch (IllegalAccessException | NoSuchFieldException e) {
            System.out.println("Cannot add library path: " + e.getMessage());
            System.out.println("Cannot add library path. Stacktrace: " + e);
        }

        System.setProperty("java.library.path", System.getProperty("java.library.path") + File.pathSeparator + s);
    }


    private static SSLContext getSSLContext(String keystoreFile, String keystorePassword) throws GeneralSecurityException, IOException {
        KeyStore keystore = KeyStore.getInstance(KeyStore.getDefaultType());
        try (InputStream in = new FileInputStream(keystoreFile)) {
            keystore.load(in, keystorePassword.toCharArray());
        }
        KeyManagerFactory keyManagerFactory = KeyManagerFactory.getInstance(KeyManagerFactory.getDefaultAlgorithm());
        keyManagerFactory.init(keystore, keystorePassword.toCharArray());

        TrustManagerFactory trustManagerFactory = TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm());
        trustManagerFactory.init(keystore);

        SSLContext sslContext = SSLContext.getInstance("TLS");
        sslContext.init(keyManagerFactory.getKeyManagers(), trustManagerFactory.getTrustManagers(), new SecureRandom());

        return sslContext;
    }

    private static Hashtable<String, Object> getProps(String channel, String host, Integer port, String username, String password, String keystore, String keystorePassword, String cipherSuite) throws MQException, GeneralSecurityException, IOException {
        Hashtable<String, Object> queueManagerProps = new Hashtable<>();
        if (isNotBlank(channel)) {
            queueManagerProps.put(CMQC.CHANNEL_PROPERTY, channel);
        }
        if (isNotBlank(host)) {
            queueManagerProps.put(CMQC.HOST_NAME_PROPERTY, host);
        }
        if (port != null) {
            queueManagerProps.put(CMQC.PORT_PROPERTY, port);
        }
        if (isNotBlank(username)) {
            queueManagerProps.put(CMQC.USER_ID_PROPERTY, username);
        }
        if (isNotBlank(password)) {
            queueManagerProps.put(CMQC.PASSWORD_PROPERTY, password);
        }

        if (isNotBlank(keystore) && isNotBlank(keystorePassword) && isNotBlank(cipherSuite)) {
            SSLContext sslContext = getSSLContext(keystore, keystorePassword);
            SSLSocketFactory sf = sslContext.getSocketFactory();
            queueManagerProps.put(MQConstants.SSL_SOCKET_FACTORY_PROPERTY, sf);

            queueManagerProps.put(MQConstants.SSL_CIPHER_SUITE_PROPERTY, cipherSuite);
            queueManagerProps.put(CMQC.TRANSPORT_PROPERTY, CMQC.TRANSPORT_MQSERIES_CLIENT);
        }

        return queueManagerProps;
    }

    public static void main(String[] args) {
        if (args.length == 0 || args[0].equalsIgnoreCase("-help")) {
            usage();
            System.exit(0);
        }

        String libPath = null;
        String qmgr = null;
        String host = null;
        String port = null;
        String channel = null;
        String user = null;
        String password = null;
        String queueName = null;
        String keystore = null;
        String keystorePassword = null;
        String cipherSuite = null;

        char c = ' ';

        for (int i = 0; i < args.length; i++) {
            if (args[i].startsWith("-")) {
                c = args[i].charAt(1);

                switch (c) {
                    case 'a':
                        libPath = args[++i];
                        break;
                    case 'm':
                        qmgr = args[++i];
                        break;
                    case 'h':
                        host = args[++i];
                        break;
                    case 'p':
                        port = args[++i];
                        break;
                    case 'c':
                        channel = args[++i];
                        break;
                    case 'u':
                        user = args[++i];
                        break;
                    case 'z':
                        password = args[++i];
                        break;
                    case 'q':
                        queueName = args[++i];
                        break;
                    case 's':
                        cipherSuite = args[++i];
                        break;
                    case 'k':
                        keystore = args[++i];
                        break;
                    case 'w':
                        keystorePassword = args[++i];
                        break;
                }
            }
        }


        boolean localBinding = false;
        if (qmgr != null && libPath != null) {
            localBinding = true;
        } else if (qmgr != null && host != null && port != null && channel != null) {
            localBinding = false;
        } else {
            usage();
            System.exit(0);
        }

        if (!isIbmJre()) {
            System.setProperty("com.ibm.mq.cfg.useIBMCipherMappings", "false");
        }

        try {
            MQQueueManager qm;

            System.out.println("==================================================================================");

            if (localBinding) {
                System.out.println("Connect to Queue Manager " + qmgr + " with local binding mode.");
                addMqLibPath(libPath);
                qm = new MQQueueManager(qmgr);
            } else {
                System.out.println("Connect to Queue Manager " + qmgr + " with client binding mode.");
                qm = new MQQueueManager(qmgr, getProps(channel, host, Integer.parseInt(port), user, password, keystore, keystorePassword, cipherSuite));
            }

            PCFMessageAgent agent = new PCFMessageAgent(qm);

            PCFMessage getQueuesRequest = new PCFMessage(CMQCFC.MQCMD_INQUIRE_Q);
            if (queueName != null) {
                getQueuesRequest.addParameter(CMQC.MQCA_Q_NAME, queueName);
            } else {
                getQueuesRequest.addParameter(CMQC.MQCA_Q_NAME, ALL_QUEUES_WILDCARD);
            }
            getQueuesRequest.addParameter(CMQC.MQIA_Q_TYPE, CMQC.MQQT_LOCAL);

            PCFMessage[] queues = agent.send(getQueuesRequest);
            for (PCFMessage queueInfo : queues) {
                String tmpQueueName = queueInfo.getStringParameterValue(CMQC.MQCA_Q_NAME);
                int queueDepthInt = queueInfo.getIntParameterValue(CMQC.MQIA_CURRENT_Q_DEPTH);
                System.out.println("Queue name: " + tmpQueueName + ", current depth: " + queueDepthInt);
            }

            qm.disconnect();
        } catch (Exception e) {
            e.printStackTrace();
        }
    }
}
