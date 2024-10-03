---
title: "[0CTF 2016]piapiapia"
date: "2023-09-03"
categories: 
  - "ctf_wp"
---

（这题太多没见过的知识点，受益颇深吧）

1.首先上来是一个登陆框，我自己先是测试，以为是道sql注入，甚至用sqlmap试了一下，然后抓包，f12，之后感觉这不是sql注入，然后在sqlmap跑的同时用disreash也跑了一下，但是线程一开高就被封ip了，然后就只能线程放少一点，然后我先用的是那个备份文件的字典，真就是靠直觉，但最终花了10分钟跑完了，也屁也没跑出来，然后不会了，就上网看了一下wp，震惊我，他一开始也是找的备份文件，但是用御剑跑的，现在我严重怀疑buuctf有点问题，同样的一个文件，用不同的工具跑，竟然结果不一样，那个备份文件是www.zip，之前做题也遇到过（这个题应该给点提示啊啊啊啊，时间好长时间都花费在这上面了）

2.然后下载下来是一整套网站的源码，然后我是放到seay里面了，毕竟工具还是很好使滴

![](images/Screenshot_22-1024x448.png)

先快捷审计了一下，其实它这个问题就是应该出现在这个profile.php里面有个文件包含的函数，然后打开那个config.php，里面有一个flag的参数，但是后面没有flag的值，练了这么多题，这个应该是个假的文件，目的就是为了告诉你flag在这个真的文件里面，这下目的就明确了，就只需要想办法把config.php这个东西放到这个函数里面，然后就能读到一个base64加密的值，解密后就是flag的值了，然后还注意到这里有个反序列化函数，然后就找序列化函数，在update.php里面找到了，是用post接受的值，然后序列化，但是呢到这个profile.php之前会经过一些过滤，这个时候有个疑问，别人都是在进行序列化之前进行一个过滤，这题怎么是序列化完了进行一个过滤，带着疑问继续往下看

3.观察这个，之前做过一道类似的，就是我记得如果提前加；}之后，那么反序列化就会提前结束，我把nickname的值改为s:3:"abc";s:5:"photo";s:10:"config.php";}这样之后的s:5:"photo";s:39:"upload/47bce5c74f589f4867dbd57e9ca9f808";}应该就会被逃逸了，但是这么做存在一个问题，就是这个时候它记录的数字（就是s：后面的数字），其实是记录的你在nickname写的字符的数量，那么在反序列化的时候，也会反序列化相同的字符，就是说这个config.php弄了半天还是到了nickname中，我们得想办法让它到photo中，然后这题我就是真的没思路了，知道怎么做，但做不出来，然后白嫖wp

4.它很聪明，就是用那个过滤的时候那个函数，诶呀，我之前当时还觉得那里奇怪（别人都是在进行序列化之前进行一个过滤，这题怎么是序列化完了进行一个过滤），但这么看感觉这道题出的好死，就感觉必须这么才能出flag，就是举个例子，原先有12个字符，两个两个为一组，但是如果把这两个一组换成4个为一组（就是两个膨胀成四个），那么就会将3组字符给挤出去，这个题就是用hacker换where就能挤出一个字符的空间，然后要挤34个空间（:}s:5:"photo";s:10:"config.php";}），然后就能到了photo里面，这个是真的想不到，然后还对nickname有长度限制，这个直接抓包改为nickname\[\]（这个就是很常见的一种绕过正则匹配的办法）就好

```
传入:
s:8:"nickname";a:1:{i:0;s:204:"34*where";}s:5:"photo";s:10:"config.php";}

此时34*where";}s:5:"photo";s:10:"config.php";}都作为nickname存在

正则替换:
s:8:"nickname";a:1:{i:0;s:204:"34*hacker";}s:5:"photo";s:10:"config.php";}

因为s只有204个字符,所以读取第34个hacker之后就停止,34个字符";}s:5:"photo";s:10:"config.php";}不再包含在nickname内
```

然后payload就是

```
wherewherewherewherewherewherewherewherewherewherewherewherewherewherewherewherewherewherewherewherewherewherewherewherewherewherewherewherewherewherewherewherewherewhere";}s:5:"photo";s:10:"config.php";}
```

剩下的就是bp抓包改参数就行，然后查看源码就会出现base64加密之后的东西，啊真的坐牢

![](images/Screenshot_23-1024x513.png)

![](images/Screenshot_24-1024x540.png)

Finish!!!