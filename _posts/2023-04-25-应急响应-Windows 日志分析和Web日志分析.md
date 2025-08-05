---
layout: mypost
title: "应急响应-Windows 日志分析和Web日志分析"
categories: [应急溯源]
---

## Windows日志分析

- 打开方式：在cmd窗口去输入**eventvwr.msc**

Windows系统日志是记录系统中硬件、软件和系统问题的信息，同时还可以监视系统中发生的事件，用户可以通过它来检查错误发生的原因，或者去寻找受到攻击时攻击者留下的痕迹

Windows主要有以下三类日志记录系统事件：应用程序日志、系统日志和安全日志

- 应用程序日志位置：  
    C:\\Windows\\System32\\winevt\\Logs\\System.evtx

- 系统日志位置：  
    C:\\Windows\\System32\\winevt\\Logs\\Application.evtx

- 安全日志位置：  
    C:\\Windows\\System32\\winevt\\Logs\\Security.evtx

![](image-45-1024x549.png)

### 应用程序日志

包含由应用程序或系统程序记录的事件，主要记录程序运行方面的事件，例如数据库程序可以在应用程序日志中记录文件错误，程序开发人员可以自行决定监视哪些事件，如果某个应用程序出现崩溃情况，那么我们可以从程序事件日志中找到相应的记录，也许会有助于问题的解决

默认位置: `%SystemRoot%\System32\Winevt\Logs\Application.evtx`

### 系统日志

记录操作系统组件产生的事件，主要包括驱动程序、系统组件和应用软件的崩溃以及数据丢失错误等，系统日志中记录的时间类型由Windows NT/2000操作系统预先定义

默认位置: `%SystemRoot%\System32\Winevt\Logs\System.evtx`

### 安全日志

主要记录系统的安全信息，包括成功的登录、退出，不成功的登录，系统文件的创建、删除、更改，需要指明的是安全日志只有系统管理员才可以访问，这也体现了在大型系统中安全的重要性。

默认位置: `%SystemRoot%`\\System32\\winevt\\Logs\\Security.evtx

系统和应用程序日志存储着故障排除信息，对于系统管理员更为有用，而安全日志记录着事件审计信息，包括用户验证（登录、远程访问等）和特定用户在认证后对系统做了什么，对于调查人员而言，更有帮助，然后就是注意一个**审核策略**，如果这个没有配的话，日志就不会去记录一些本该记录的日志

### 审核策略

打开这里

![](image-46-1024x678.png)

然后点击如下部分

![](image-47-1024x647.png)

一般的话就设置成下图这样

![](image-48.png)

### 事件ID对应的具体事件

Windows 的日志以事件 id 来标识具体发生的动作行为，可通过这个网站查询具体 id 对应的操作

[Windows Security Log Encyclopedia (ultimatewindowssecurity.com)](https://www.ultimatewindowssecurity.com/securitylog/encyclopedia/default.aspx?i=j)

```
1102   清理审计日志   

4624   账号成功登录   

4625   账号登录失败   

4720   创建用户   

4726   删除用户   

4732   将成员添加到启用安全的本地组中   

4733   将成员从启用安全的本地组中移除   
```

### 事件日志中的事件级别

![](image-49-1024x425.png)

### 登录类型

这个来分析一下是不是有人3389等机器了还是就是本地键盘登的这种......

![](image-50-1024x411.png)

### 关于日志覆盖的问题

Windows系统内置三个核心日志文件:System、Security、Application，默认大小均为20480kB也就是20MB，记录数据超过20MB时会覆盖过期的日志文件，其他的应用程序以及服务日志默认大小均为1MB，超过这个大小一样的处理方法

而这个也不是绝对的，是可以去更改的，给公司的话就尽量的选择第二种，然后应用

![](image-51.png)

### 日志分析工具---logparser

到这个网站去下载就好---[Download Log Parser 2.2 from Official Microsoft Download Center](https://www.microsoft.com/en-us/download/details.aspx?id=24659)，我把这个无污染的安装包放到工具箱里面了，客户现场需要的话，现场给他拷贝一下，不过一般都是把人家事件拷出来一份然后放到本地去分析

然后添加一个环境变量，正常安装好就是这个样子，它是个图形化界面，下面给几个在真实情况中很必须用到的几条命令

![](image-52-1024x547.png)

使用方法：一般都是分析这个安全日志，所以我们这里用安全日志来演示，首先就是先在事件查看器中把这个安全日志导到任意一个目录，这里就导到C盘的根目录了，并把它命名为Security.evtx

![](image-53.png)

然后使用语法就行了，实质上还是用了数据库的查询语法

- **查看结构**

```
LogParser.exe -i:EVT -o:DATAGRID "SELECT * FROM c:\Security.evtx"
```

![](image-54-1024x579.png)

- **登录成功的所有事件**

```
LogParser.exe -i:EVT -o:DATAGRID "SELECT * FROM c:\Security.evtx where EventID=4624"
```

![](image-55-1024x124.png)

我上面策略配置那块就没有配，所以没有也很正常

- **指定登录时间范围的事件**

```
LogParser.exe -i:EVT -o:DATAGRID "SELECT * FROM c:\Security.evtx where TimeGenerated>'2024-06-01 23:32:23' and TimeGenerated<'2024-06-09 23:34:00' and EventID=4624"
```

![](image-56-1024x160.png)

- **提取登录成功的用户名和IP**

```
LogParser.exe -i:EVT -o:DATAGRID "SELECT EXTRACT_TOKEN(Message,13,' ') as EventType,TimeGenerated as LoginTime,EXTRACT_TOKEN(Strings,5,'|') as Username,EXTRACT_TOKEN(Message,38,' ') as Loginip FROM c:\Security.evtx where EventID=4624"
```

这个的话就是可以用来查横向移动的，得到电脑主机名后，就可以ping这个主机名，看看这个IP是哪里的

- **登录失败的所有事件**

```
LogParser.exe -i:EVT -o:DATAGRID "SELECT * FROM c:\Security.evtx where EventID=4625"
```

- **提取登录失败用户名进行聚合统计**

```
LogParser.exe -i:EVT "SELECT EXTRACT_TOKEN(Message,13,' ') as EventType,EXTRACT_TOKEN(Message,19,' ') as user,count(EXTRACT_TOKEN(Message,19,' ')) as Times,EXTRACT_TOKEN(Message,39,' ') as Loginip FROM c:\Security.evtx where EventID=4625 GROUP BY Message"
```

- **系统历史开关机记录**

```
LogParser.exe -i:EVT -o:DATAGRID "SELECT TimeGenerated,EventID,Message FROM c:\System.evtx where EventID=6005 or EventID=6006"
```

### 日志被删除办法&怎么隐藏日志

[【Windows】日志删除恢复 | CN-SEC 中文网](https://cn-sec.com/archives/296575.html)

## Web日志分析

从web应用日志中，可以分析出攻击者在什么时间，使用哪个IP，访问了哪个网站，IIS日志通常存放在%SyatemDrive%\\inetpub\\logs\\LogFiles目录，日志文件由时间命名，下面这个不是我的服务器，不太方便给看

![](image-58.png)

### 工具

![](image-57-1024x704.png)

这是一种，或者去github上去找这种专门去可以分析日志的工具，到了客户现场把它所有的日志先导出来，然后放本地工具上做个可视化，而且还有搜索什么的功能还是蛮方便的