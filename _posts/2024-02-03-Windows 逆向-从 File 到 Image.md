---
layout: mypost
title: "Windows 逆向-从 File 到 Image"
categories: [Windows 逆向]
---

## 前言

这节课就是主要明白三点吧，第一是把 File 复制到 Image 的流程，哪里需要复制，从哪复制，复制多少，以及在哪粘贴，粘贴到哪，第二个就是明白 SizeOfRawData 不一定大于 Misc.VirtualSize，第三个就是将 RVA 的值转换成 FOA

## 课堂

### 文件执行的过程

1.一个硬盘上的文件读入到虚拟内存中（FileBuffer），是原封不动的将硬盘上的文件数据复制一份放到虚拟内存中  
2.接着如果文件要运行，需要先将 FileBuffer 中的文件数据"拉伸"，重载到每一个可执行文件的 4GB 虚拟内存中！此时称文件印象或者内存印象，即 ImageBuffer  
但是 ImageBuffer 就是文件运行时真正在内存中状态吗？或者说文件在 ImageBuffer 中就是表示文件被执行了吗？不！！！！！！  
3.在 ImageBuffer 中的文件数据由于按照一定的规则被"拉伸"，只是已经无线接近于可被 windows 执行的文件格式了！但是此时还不代表文件已经被执行了，因为此时文件也只是处在 4GB 的虚拟内存中，如果文件被执行操作系统还需要做一些事情，将文件真正的装入内存中，等待 CPU 的分配执行  
所以不要理解为 ImageBuffer 中的状态就是文件正在被执行，后面操作系统还要做很多事情才能让 ImageBuffer 中的文件真正执行起来的

### 误区

SizeOfRawData 不一定大于 Misc.VirtualSize，大家可能会觉得前者是对齐后的结果，而后者是没对齐的结果，所以前者就一定大于后者，但是 SizeOfRawData 表示此节在硬盘上经过文件对齐后的大小，而 Misc.VirtualSize 表示此节在内存中没有对齐的大小，要分清主语，那问题又来了，这个节难道在 File 中和 Image 中不是一个东西吗？这就引出未初始化变量这个东西了，下面用海东老师的例子说明：

```
我们写C语言的时候知道如果你定义一个数组已经初始化，比如int arr[1000] = {0};，此时编译成.exe文件存放在硬盘上时，这1000个int类型的0肯定会存放在某一个节中，并且分配1000个0的空间，这个空间大小是多少，最后重载到ImageBuffer时还是多少，即Misc.VirtualSize不管文件在硬盘上还是内存中的值都是一致的。所以，SizeOfRawData一般都是大于等于Misc.VirtualSize的

但是如果我们定义成int arr[1000];，表示数据还未初始化，并且如果程序中没有使用过或初始化过这块内存空间，那么我们平时看汇编会发现其实编译器还没有做任何事情，这就只是告诉编译器需要预留出1000个int宽度大小的内存空间。所以如果某一个节中存在已经被定义过但还未初始化的数据，那么文件在硬盘上不会显式的留出空间，即SizeOfRawData中不会算上未初始化数据的空间；但是此节的Misc.VirtualSize为加载到内存中时节的未对齐的大小，那么这个值就需要算上给未初始化留出来空间后的整个节的大小，故在内存中的节本身的总大小可能会大于硬盘中的此节文件对齐后的大小，而且这个空间按照海东老师说的话这个未初始化变量应该是放在整个节的末尾的，这个我暂时还不知道咋去验证
```

### File 复制到 Image 的流程

![](image-39-1024x824.png)

- 先在硬盘上找一个可执行文件，将文件的数据复制到内存中，即 FileBuffer 中（前面的练习做过很多次了）

- 根据 SizeOfImage 的大小，再使用 malloc 开辟一块 ImageBuffer，用 0x00 初始化 ImageBuffer（SizeOfImage 即为文件加载到 4GB 虚拟内存的大小）

- 因为所有头和节表经过文件对齐后的这段数据经过 PE loader 加载到 ImageBuffer 是不会变的，所以直接可以将所有头和节表经过文件对齐后的这块数据从 FileBuffer 中复制到 ImageBuffer 中

- 接着就是复制所有节的数据：需要使用循环，先复制第一个节的内容。通过第一个节对应节表中的 PointerToRawData 的值确定第一个节的起始地址；再通过 SizeOfRawData 的值得到从起始地址开始需要复制多少字节的数据到 ImageBuffer 中；再接着将这些数据复制到 ImageBuffer 中的哪个位置呢？就需要通过此节对应的节表中的 VirtualAddress 决定将数据从 ImageBuffer 中的哪个地址开始赋值，由于是相对地址，所以还需要知道 ImageBase，但是！！我们是用 C 语言模拟 PE 的加载过程，此时 ImageBuffer 的首地址是由 malloc 申请的，不是真正的 ImageBase！（只有当文件真正执行时，操作系统把文件拉伸装入虚拟内存时，才是 ImageBase）所以 malloc 申请的首地址 + VirtualAddress 就是最终将第一节数据复制到 ImageBuffer 中的起始地址。后面的节的数据以此类推从 FileBuffer 复制到 ImageBuffer 中

```
为什么选择SizeOfRawData，不选择Misc.VirtualSize来确定需要复制的节的大小？因为上面说过，Misc.VirtualSize的值由于节中有未初始化的数据且未使用而计算出预留的空间装入内存后的总大小的值可能会很大，如果这个值大到已经包含了后面一个节的数据，那么按照这个值将FileBuffer中的数据复制到ImageBuffer中很可能会把下一个节的数据也复制过去，所以直接用SizeOfRawData就可以了，如果如海东老师所说这个未初始化变量会编译器计算后加在节的末尾，那么就能解释的通，要不然就不能直接复制File中的节的内存
```

### RVA 转换为 FOA

比如一个文件加载到 4GB 内存中的某一个数据地址为 0x501234，那么怎么算出这个内存地址对应到文件在硬盘上时的地址是多少，即怎么去算出文件偏移地址

- 先算出此内存地址相对于文件在内存中的起始地址的偏移量

- 接着通过这个偏移量循环和每一个节的 VirtualAddress 做比较，当此偏移量大于某一个节的 VirtualAddress 并且小于此 VirtualAddress + Misc.VirtualSize，就说明这个内存地址就在这个节中

- 再用此偏移量 - 此节的 VirtualAddress 得到这个内存地址相对于所在节的偏移量

- 接着找内存地址所在节的 PointerToRawData，通过 PointerToRawData + 内存地址相对于所在节的偏移量来得到此内存地址在硬盘上时相对于文件的偏移量

具体的步骤就是下面这个图片里面的内容

![](image-40-1024x606.png)

## 作业

这个在之后一篇文章一块说了

1.从硬盘加载到 File（这个之前有篇文章做过）

2.PE 解释器

3.从 File 到 Image

4.从 Image 到 File 再到硬盘