---
layout: mypost
title: "[Zer0pts2020]Can you guess it?"
categories: [ctf_wp]
---

1.ctf之国庆专辑哈哈哈哈哈，这道题一开始进去的界面是一个框框，一开始以为是一个sql注入，但点击source竟然给了源码，二话不说开始审计吧

```
<?php
include 'config.php'; // FLAG is defined in config.php

if (preg_match('/config\.php\/*$/i', $_SERVER['PHP_SELF'])) {
  exit("I don't know what you are thinking, but I won't let you read it :)");
}

if (isset($_GET['source'])) {
  highlight_file(basename($_SERVER['PHP_SELF']));
  exit();
}

$secret = bin2hex(random_bytes(64));
if (isset($_POST['guess'])) {
  $guess = (string) $_POST['guess'];
  if (hash_equals($secret, $guess)) {
    $message = 'Congratulations! The flag is: ' . FLAG;
  } else {
    $message = 'Wrong.';
  }
}
?>
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <title>Can you guess it?</title>
  </head>
  <body>
    <h1>Can you guess it?</h1>
    <p>If your guess is correct, I'll give you the flag.</p>
    <p><a href="?source">Source</a></p>
    <hr>
<?php if (isset($message)) { ?>
    <p><?= $message ?></p>
<?php } ?>
    <form action="index.php" method="POST">
      <input type="text" name="guess">
      <input type="submit">
    </form>
  </body>
</html>
```

2.下面具体说一下这段代码都干了什么

```
1.源码一开始有个正则匹配，主要就是不能检测到config.php/（这个/属于可有可没有，因为正则表达式后面有一个*，这个代表的意思是0个到无穷个，也就是说有无穷个/也是可以的），这个倒是好绕过，后面随便加个东西就行
2.然后检测是否用source这个get传参，如果有的话就截取最后的这个文件
tip：这里大家可以先了解一下$_SERVER['PHP_SELF']东西还有basename（）这个函数，简单解释一下就是$_SERVER['PHP_SELF']这个会返回与网站根目录相对的路径，然后basename（）这个函数的话会输出$_SERVER['PHP_SELF']这个路径的最末尾的文件
3.$secret变量的话，就是获取了一个随机的数字，而且数字很复杂，很大，没有规律，这个用到的是和操作系统一样获取随机数的方法，所以这这一步肯定是安全的，然后就是guess（也就是页面中那个框框），它让我们输入一个和这个$secret变量一模一样的数字，而且用到了hash_equals这个东西来比较，不是平时用的===（这个我知道是为了防止时序攻击，所以这个是真的安全，若有漏洞就是0day，所以这个肯定也是没法绕过的）
```

3.okok大概解释了一遍这个源码的流程，总而言之，肯定不能靠下面那个guess去获得flag，因为这样写真的是最安全的写法，但大家有没有想过，如果这个题的预期解是靠guess的话，那上面为什么要大费周章的去写那样的代码呢，所以这个突破点肯定是上面的那些代码，然后再仔细分析一遍

4.这个一开始进去的页面应该是一个index.php,然后经过 highlight\_file(basename($\_SERVER\['PHP\_SELF'\]));这个之后会获得index.php，然后会将index.php的源码显示出来，那我们可不可以把config.php里面的东西给展示一下呢？然后我也是胡乱测试一下啊，发现一个神奇的事情，就是在访问/index.php/config.php的时候，服务器也会默认我们访问的是index.php，所以source这个参数还是可以用的，然后搭了一个本地靶场，测试的时候发现虽然服务器也会默认我们访问的是index.php，但是SERVER\['PHP\_SELF'\]这个东西竟然还是/index.php/config.php，这就找到突破点了，应该就是这两个地方起冲突了，导致我们有机会，那么我就写了第一个payload

```
http://2db62442-ccea-4f10-afca-1fcc59c0b854.node4.buuoj.cn:81/index.php/config.php/?source
```

然后它就提示

![](image-20231003222658253-1024x130.png)

这很正常啊，我理解，因为这里有个正则欸，检测到了config.php/，所以肯定不行，然后现在问题就很明显了，要找到一个字符，既能绕过正则匹配（这个正则就是个纸老虎，只要不以config.php/结尾就行），也能让这个basename（）函数正常的匹配到config.php

5.比如下面这个payload，肯定可以绕过正则，但是报错了，这也很正常，因为basename（）匹配到的是1

```
http://2db62442-ccea-4f10-afca-1fcc59c0b854.node4.buuoj.cn:81/index.php/config.php/1?source
```

![](image-20231003223141761-1024x128.png)

然后就去搜这个basename有没有啥办法可以绕过啊，结果搜到了php官方其实已经给过这个bug

![](image-20231003223450097-1024x537.png)

```
With the default locale setting "C", basename() drops non-ASCII-chars at the beginning of a filename.
在使用默认语言环境设置时，basename() 会删除文件名开头的非 ASCII 字符
```

然后github也有师傅给出了找这个字符的脚本

```
<?php
highlight_file(__FILE__);
$filename = 'index.php';
for($i=0; $i<255; $i++){
    $filename = $filename.'/'.chr($i);
    if(basename($filename) === "index.php"){
        echo $i.'<br>';
    }
    $filename = 'index.php';
}
?>
```

![](屏幕截图-2023-10-03-223738-1024x509.png)

6.然后就很简单了，随便加一个里面的字符就行（ascii值为47、128-255的字符均可以绕过basename()），下面是最终payload

```
http://2db62442-ccea-4f10-afca-1fcc59c0b854.node4.buuoj.cn:81/index.php/config.php/%ff?source
```

![](image-20231003223936555-1024x94.png)