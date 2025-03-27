---
layout: mypost
title: "Shiro's buggy classloader"
categories: [Java安全]
---

## 前言

在尝试将 Shiro 与 CC 链结合进一步扩大危害的时候，编写完 EXP 执行就会报下面这样的错误-->

```
Caused by: java.lang.ClassNotFoundException: Unable to load ObjectStreamClass [[Lorg.apache.commons.collections.Transformer;: static final long serialVersionUID = -4803604734341277543L;]:
```

网上很多文章给出的解释是：Class.forName 支持加载数组，而 ClassLoader.loadClass 不支持加载数组，可事实真的如此吗？这个解释是不准确的，珍爱生命，少读二手文章哈哈。

## 准备工作

1.可以先看一下这一篇文章-->[Shiro 反序列化漏洞]()。

2.IDEA 调试 Tomcat，将 Jar 包导入 IDEA、将对应的源码导入 IDEA 即可。

## 调试

调试分了四步，依次展示了用 cache 加载，本地存储库加载，非 Java 自身的数组加载，Java 自身的数组加载。

1.报错原因已经知道了：Shiro 框架中 ClassResolvingObjectInputStream 类重写了 resolveClass 方法，方法中的`ClassUtils.forName(osc.getName());`这一行代码没能成功的加载到 Transformer 类。

跟到 ClassUtils 的 forName 函数里面（这就是进入到 Tomcat 中了，准备工作要做好）

![alt text](1.png)

ClassUtils 类自己写了一个 forName 函数，它的注解如下-->

![alt text](2.png)

跟进去`THREAD_CL_ACCESSOR.loadClass(fqcn)`，其中调用 loadClass 函数（这和`Class.forname()`是很像的，且 loadClass 函数内部逻辑都是双亲委派）如下-->

![alt text](3.png)

此时的 cl 是一个叫`ParallelWebappClassLoader`的类加载器，放在平时这里会是`Launcher$AppClassLoader`，由于是 Tomcat 运行的，所以这里会是 Tomcat 自己实现的一个类加载器。继续进入 loadClass，会调用`WebappClassLoaderBase.loadClass()`-->

![alt text](4.png)

继续调用另一个重载的 loadClass-->

![alt text](5.png)

这个方法它首先会先尝试从本地 cache 中加载类，找不到就会去本地存储库中查找，最后从父加载器 URLClassLoader 中加载，一步一步调调看。第一次在 cache 中找，显然没有找到-->

![alt text](6.png)

第二次在 cache 中成功找到了，如下

![alt text](7.png)

这是因为 Tomcat 启动时就已经加载过这个类，cache 也分很多，要分开找，接着就是一路 return 到下图位置

![alt text](8.png)

至此能成功加载`java.util.HashMap`类了

2.接下来轮到这个类`org.apache.commons.collections.keyvalue.TiedMapEntry`了-->

![alt text](9.png)

前面和`java.util.HashMap`一样，会调用`WebappClassLoaderBase.loadClass()`函数，一开始也是先去在 cache 中找，显然是找不到的，Tomcat 初始化怎么可能去加载一个 commons-collections 包的类？之后就去本地存储库中找，由于之前手动在 Maven 中添加了一个 commons-collections 依赖，所以成功找到了-->

![alt text](10.png)

接着就是一路 return，至此能成功加载`org.apache.commons.collections.keyvalue.TiedMapEntry`类了。

3.很快就到了主角`org.apache.commons.collections.Transformer`类了，`[L`是一个 JVM 的标记，说明实际上这是一个数组，即 Transformer[]-->

![alt text](11.png)

和前面的一样，会调用`WebappClassLoaderBase.loadClass()`函数，一开始也是先去在 cache 中找，肯定也是找不到的，接着去本地存储库中找-->

![alt text](12.png)

这里跟进去看一下这个 findClass 方法的逻辑，看看它是怎么实现能去本地存储库中加载类的-->

![alt text](13.png)

可以看到是去拼接路径，这点和 URLClassLoader 中的 findClass 方法是很像的，但这样一个路径`/[Lorg/apache/commons/collections/Transformer;.class`显然是不存在的，所以肯定是找不到的。

接着就去父加载器 URLClassLoader 中加载-->

![alt text](14.png)

网上很多文章到这里就 End 了，个人猜他们是这么想的：认为这个`Class.forName()`里面调用到 loadClass 函数，而 loadClass 函数会调用到 findClass 函数，而 findClass 函数内部逻辑还是会去拼接路径，所以肯定是找不到的。但是事实并非如此，继续跟进下去到 forname0 函数-->

![alt text](15.png)

强制步入后会调用到下面这里 👇

![alt text](16.png)

可以发现数组特征被消除了，那么按理来说这下可以成功加载了，但是并没有，继续跟一下，熟悉的双亲委派-->

![alt text](17.png)

之后调用到了 URLClassLoader 的 findClass 方法-->

![alt text](18.png)

发现还是找不到，但路径没有错，其实这里原因出在 Tomcat 和 JDK 的 Classpath 是不公⽤且不同的这里，Tomcat 启动时，不会⽤ JDK 的 Classpath，举个例子-->

```
Tomcat的Classpath：/Tomcat/
JDK的Classpath：/JDK/

Tomcat启动时用的是/Tomcat/这个基地址，那么findClass方法中拼接的路径就是/Tomcat/org/apache/commons/collections/Transformer.class，而Transformer.class实际上是在/JDK/org/apache/commons/collections/Transformer.class，所以是找不到的。
```

然后就是没找到，一路 return 到开始的`THREAD_CL_ACCESSOR.loadClass(fqcn);`，接着去`CLASS_CL_ACCESSOR.loadClass(fqcn);`-->

![alt text](19.png)

一模一样的流程重新走了一遍，又一路 return 到`CLASS_CL_ACCESSOR.loadClass(fqcn);`，接着去`SYSTEM_CL_ACCESSOR.loadClass(fqcn);`如下-->

![alt text](20.png)

此时`cl`的值为`ClassLoader$AppClassLoader`，如下 👇

![alt text](21.png)

直接调用到了这里-->

![alt text](22.png)

相当于这次不走 cache 和本地存储库，直接调用`Class.forname()`，上面已经分析过了是不可以 ❌ 的。

最后抛出错误如下-->

4.是可以加载 Java 原生类的数组，如下-->

![alt text](23.png)

这个最后是被成功加载的，也很好理解，沿着上面的例子继续分析一下-->

```
Java原生类无论在Tomcat的Classpath还是JDK的Classpath中都是存在的
在Tomcat中：/Tomcat/java/lang/Object.class
在JDK中：/JDK/java/lang/Object.class
即使Tomcat启动时用的是/Tomcat/这个基地址，也会歪打正着的找到Object.class
```

总结：真正导致报错的原因是，开发人员原本可以用`ParallelWebappClassLoader`这个类加载器（管理 Web 应用中的类和资源的加载）去加载，它肯定是最全的，可以加载到上述所有情况的类，但是可能因为某些特殊原因，去选择全部使用本地加载。本地加载分三步，cache、本地存储库、父加载器（原生的 Class.forname），但是**非 Java 自身的数组**完美的避开了这三次加载，最终导致报错。

## 结语

蛮神奇的，Java 自身的数组歪打正着的被成功加载，Tomcat 歪打正着的给 Shiro 反序列化漏洞做了一次防御。

参考自：

[Pwn a CTF Platform with Java JRMP Gadget](https://blog.orange.tw/posts/2018-03-pwn-ctf-platform-with-java-jrmp-gadget/)

[Exploiting JVM deserialization vulns despite a broken class loader](https://bling.kapsi.fi/blog/jvm-deserialization-broken-classldr.html)