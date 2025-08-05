---
layout: mypost
title: "Windows 逆向-PE"
categories: [Windows 逆向]
---

## 前言

终于开了 PE 了，学好这个之后就可以写一个 PE 的小工具，这回笔记基本上就把 PE 的整体给说完了，作业的话打算之后专门出一篇文章说 PE 这方面的代码吧

![](image-38-1024x478.png)

## 学习过程

### 分节和对齐

#### 分节

这个可以和结构体对齐那一块做个类比，PE 文件在硬盘和内存中都是分节存储的，把数据分成一段一段的，那为啥要分节呢，第一个原因就是可以节省内存空间，就是海东老师说的那个开小号的例子，第二个原因就是节省硬盘空间，文件在内存中段与段之间的空隙很大；而文件在硬盘上段与段之间的空隙比较小，即节省了硬盘空间

tip：

我们要知道这里的文件运行时所在内存和我们说的内存条不是一个概念，任何一个 exe 文件在 32 位计算机上运行时都有自己独立的 4GB（232，即寻址范围最大是 4GB）虚拟内存----其中有 2GB 是供应用程序使用的，另外 2GB 是操作系统用的  
我们可以想象成凡是运行后的程序虚拟上会有这样的 4GB 内存结构，但是实际上程序的数据都要经过操作系统帮我们管理按照特定的方式存到真实的内存条中

#### 对齐

硬盘对齐内存对齐粒度不相等

![](image-21-1024x896.png)

- 优点：节省了硬盘空间

- 缺点：减低了硬盘、内存之间数据相互传输的读写速度，因为内存和硬盘的对齐粒度不同，需要换算，定位查找就需要花费一定的时间

硬盘对齐内存对齐粒度相等

![](image-22-1024x858.png)

- 优点：由于对齐粒度一样了，当把文件从硬盘装入到内存中时可以省去很多运算，只需要确定好首地址

- 缺点：浪费了一定的硬盘空间

### PE 文件的结构

![](image-23-1024x918.png)

#### DOS 头

```
struct _IMAGE_DOS_HEADER {
    0x00 WORD e_magic;  *
    0x02 WORD e_cblp;
    0x04 WORD e_cp;
    0x06 WORD e_crlc;
    0x08 WORD e_cparhdr;
    0x0a WORD e_minalloc;
    0x0c WORD e_maxalloc;
    0x0e WORD e_ss;
    0x10 WORD e_sp;
    0x12 WORD e_csum;
    0x14 WORD e_ip;
    0x16 WORD e_cs;
    0x18 WORD e_lfarlc;
    0x1a WORD e_ovno;
    0x1c WORD e_res[4];
    0x24 WORD e_oemid;
    0x26 WORD e_oeminfo;
    0x28 WORD e_res2[10];
    0x3c DWORD e_lfanew;  *
};
```

这里主要就记两个，一个是**e_magic**，用于判断是否为可执行文件，即如果显示`4D 5A`，说明该文件是一个可执行文件：.sys/.dll/.exe 等；另一个是**e_lfanew**，相对于文件首地址的偏移，用于定位 PE 文件，即此 PE 文件真正的 PE 结构开始的地址，值是不确定的，DOS 头结尾到真正 PE 开始地址之间有空隙，不同的编译器会往里塞一些不同的数据，大小和内容都是不同的，取决于编译器，而且程序也不会使用到这块空间。但对于我们来说其实就是一些垃圾数据，想往里放什么就放什么，且大小是不确定的，但是我们也可以在这做手脚，既然装入内存中了，就有了分配的内存地址，那么就可以想办法让程序去访问这个地址中的数据，所以即使程序自身运行时不会使用这块空间，但是我们可以想办法访问（想想函数指针那里）

#### PE 标记

即 e_Ifanew 指向的地址，就是一个 PE 的标记或者叫签名

```
DWORD Signature;
```

所以一个可执行文件应该满足"MZ"标记和"PE"标记，如果这两点不满足可能被修改过，或者就不是一个可执行文件

#### 标准 PE 头

```
struct _IMAGE_FILE_HEADER {
    0x00 WORD Machine;  *
    0x02 WORD NumberOfSections;  *
    0x04 DWORD TimeDateStamp;  *
    0x08 DWORD PointerToSymbolTable;
    0x0c DWORD NumberOfSymbols;
    0x10 WORD SizeOfOptionalHeader;  *
    0x12 WORD Characteristics;  *
};
```

- Machine：支持的 CPU 型号，如果是 0x0 表示能在任何处理器上执行；如果是 0x14C 表示能在 386 及后续处理器上执行

- NumberOfSections：文件中存在的节的总数：如果要新增节或者合并节，就要修改这个值。大小表示不包括 DOS 头、NT 头、节表，此文件分为几个节（例如.text、.idata 等）

- TimeDateStamp：时间戳，文件的创建时间（和操作系统的创建时间无关），编译器填写的，时间戳的使用案例：比如现在要给一个.exe 文件加壳，有些加壳软件不光要提供给它.exe 文件，还需要其对应的.map 文件，这个文件中记录了此.exe 文件中的所有的函数的名字、地址、参数等信息，即 exe 文件中所有函数的描述。这两个文件编译器编译时一起生成，那么 map 和 exe 的时间戳就是一致的，如果现在这个.exe 文件需要反复修改，那么 exe 文件的时间戳就会变，但是 map 的时间戳没有更新，导致 exe 和 map 不同步，如果加壳子还是按照 map 中的记录信息去加壳，就可能出现错误。所以很多加壳软件在加壳之前会检查 exe 和 map 文件的时间戳是否一致

- SizeOfOptionalHeader：可选 PE 头的大小，32 位 PE 文件默认**E0h**，64 位 PE 文件默认为**F0h**（大小可以自定义）

- Characteristics：16 位的每个位都表示不同的特征，可执行文件值一般都是 0x010F，即读完后 16 位二进制数中从低到高第 1、2、3、4、9 位上的值为 1，其他位为 0，下面是每一位的 1 含义

![](image-24.png)

#### 可选 PE 头

```
struct _IMAGE_OPTIONAL_HEADER {
    0x00 WORD Magic; *
    0x02 BYTE MajorLinkerVersion;
    0x03 BYTE MinorLinkerVersion;
    0x04 DWORD SizeOfCode; *
    0x08 DWORD SizeOfInitializedData; *
    0x0c DWORD SizeOfUninitializedData; *
    0x10 DWORD AddressOfEntryPoint; *
    0x14 DWORD BaseOfCode; *
    0x18 DWORD BaseOfData; *
    0x1c DWORD ImageBase; *
    0x20 DWORD SectionAlignment; *
    0x24 DWORD FileAlignment; *
    0x28 WORD MajorOperatingSystemVersion;
    0x2a WORD MinorOperatingSystemVersion;
    0x2c WORD MajorImageVersion;
    0x2e WORD MinorImageVersion;
    0x30 WORD MajorSubsystemVersion;
    0x32 WORD MinorSubsystemVersion;
    0x34 DWORD Win32VersionValue;
    0x38 DWORD SizeOfImage; *
    0x3c DWORD SizeOfHeaders; *
    0x40 DWORD CheckSum; *
    0x44 WORD Subsystem;
    0x46 WORD DllCharacteristics;
    0x48 DWORD SizeOfStackReserve; *
    0x4c DWORD SizeOfStackCommit; *
    0x50 DWORD SizeOfHeapReserve; *
    0x54 DWORD SizeOfHeapCommit; *
    0x58 DWORD LoaderFlags;
    0x5c DWORD NumberOfRvaAndSizes; *(后面深入的重点，现在不讲)
    0x60 _IMAGE_DATA_DIRECTORY DataDirectory[16];
};
```

- Magic：说明文件类型，如果值为 0x010B，表示是 32 位下的 PE 文件；如果值为 0x020B，表示是 64 位下的 PE 文件

- SizeOfCode：所有代码节大小的和，必须是 FileAlignment 的整数倍

比如文件只有一个代码节，大小为 100h 字节，如果文件对齐粒度是 200h，那么会补 0 填充够 200h 字节，所以会显示 200h（编译器填的）；若文件有两个代码节，两个都是 10 字节，这个值应为 400h。但是计算机发展到现在已经不使用这个值了，改了也没事，删除程序也可以正常运行，但是现在之所以保留下来是因为向下兼容，以前的软件程序发布已经遵循了这个格式，如果现在修改了，那全世界以前发布的.exe 等文件都需要删除这几位

- SizeOfInitializedData：已初始化数据大小的和，必须是 FileAlignment 的整数倍，编译器填的，目前计算机已经不使用这个值了，删掉也可以，保留下来只是为了向下兼容

- SizeOfUninitializedData：未初始化数据大小的和，必须是 FileAlignment 的整数倍，编译器填的，目前计算机已经不使用这个值了，删掉也可以，保留下来只是为了向下兼容

- AddressOfEntryPoint：程序入口点 OEP（程序真正执行的起始地址），这个值是偏移量，而不是真正运行在内存中的程序入口地址。需要再加上加载到内存的基址（imagebase），才是程序运行在内存中（4GB 虚拟内存）的程序入口。这个值不是确定的

注意：程序入口在默认情况下一般都在.code 代码节当中，且 OEP 不是只能在.code 代码节开始的位置，可以从此节当中的任何合理位置开始，也可以在其他节（如.text 等）的任意合理位置开始。OEP 可以人为修改，但是最后一定要让.exe 文件能运行起来

注意：程序入口不能理解为 C 语言的 main 函数，那只是我们写的代码的执行入口，因为在 main 函数被调用前还做了很多事情，所以 OEP 一定是.exe 双击开始运行时程序开始的那个地址，可以用 OD 打开看一下，如下

内存中的程序入口地址：使用 OD 打开文件（完全模拟文件运行时加载到内存中的状态，不是硬盘上的状态）。所以 OD 打开一个可执行文件后，会在程序入口地址处设置断点，让程序停下来，这里就是文件在内存中真正的入口点。即文件装入到 4GB 虚拟内存中的起始基地址 +相对于文件首地址的偏移的程序入口地址，即 imagebase + AddressOfEntryPoint

![](image-25-1024x651.png)

- BaseOfCode：顾名思义，就是指着代码开始的基址，但这个是可以改的，

不要和程序入口混为一谈，不是代码一有，程序就要执行，程序入口可以设定到任何地方，只是在没有修改过 PE 结构的情况下程序入口一般都在.code 代码节当中的某一个位置。如果要自己修改，比如修改到数据中，最后一定要能让程序能运行起来，不能胡改，不然没有意义

- BaseOfData：就是数据开始的基址，这个也可以改

- ImageBase：内存镜像基址：我们知道每一个.exe 程序都有属于自己的 4GB 虚拟内存，这个值就是当程序运行装入到自己的虚拟 4GB 内存中后的文件的起始位置。imagebase 一般都是 0x00400000，不能超过 0x80000000，因为我们写的程序的数据只能在内存的 2GB 用户区中，不能占用 2GB 系统区

这一块的话，现在可以这么理解，一个 exe 的 PE 文件是由一堆 PE 文件组成的，exe 本身是一个 PE 文件，满足 PE 结构，但是 exe 中可能还用到了很多 dll，每一个 dll 也是一个 PE 文件，也满足 PE 结构，这些 dll 有自己的功能和作用，拼凑到一个 exe 文件中，exe 文件就有了完整的功能。所以相当于很多 PE 文件在一个 PE 文件中。又称 exe 文件有很多模块构成，每一个.dll 都是一个模块。  
那么为什么从 400000 开始也就理解了吧，就是和前面的文件对齐，内存对齐的道理都是一样的，每一个 dll 文件开始都是从 imagebase 的倍数开始的，还有一个原因就是内存保护

```
因为内存保护！我们前面学过，free一个动态分配内存的指针后，一定要将指针 = NULL，那么指针等于NULL后，这个指针指向的地址就是0x0，那么如果此时访问此指针指向的数据，或者向后偏移一定大小的范围内的数据，编译器会立马报错。所以4GB内存中开始空出来一些内存空间就是为了内存保护的
```

![](image-26-1024x970.png)

但是在 64 位上会出现这样的情况

![](35ff65d9c1c1d16fe688ebdf36d01d58-1024x554.png)

那个 1400 是硬盘上的，但是加载到内存里面就是那个 7ff 什么什么的，xp 默认一直是 1000

![](image-30-1024x951.png)

![](8ABBBDDBF399DFF099A45FD092C2C520.png)

- SectionAlignment：内存对齐，可执行文件运行时装入 4GB 虚拟内存中的对齐粒度，一般为 0x1000 字节

- FileAlignment：文件对齐，可执行文件在硬盘的对齐粒度，一般为 0x200 字节，还有的是 0x1000 字节，和内存对齐粒度相等

- SizeOfImage：内存中整个 PE 文件的映射尺寸：即文件运行时装入 4GB 虚拟内存后的整个文件数据大小（要考虑内存对齐）。可以比实际的值大（比如文件对齐为 0x200，内存对齐为 0x1000 时），但必须是 SectionAlignment 的整数倍

- SizeOfHeaders：所有头+节表按照文件对齐后的大小：即 DOS 头 + 垃圾数据 + PE 签名 + 标准 PE 头 + 可选 PE 头 + 节表，按照文件对齐后的大小。必须是 FileAlignment 的整数倍，否则加载会出错

举例：假如一个可执行文件的所有头和节表加起来大小为 0x1800 字节，但是第一个节表开始位置应该是 0x2000，因为要满足文件对齐粒度 0x1000

![](image-27.png)

剩下的就不太重要了，直接给个图片

![](image-28-1024x366.png)

#### 节表

- 节表是表，肯定不止一个数。一个 PE 文件有多少个节，就有多少个节表！每一个节表的大小是确定的，40 字节，如何确定有多少个节：可以通过标准 PE 头中的 NumberOfsections 字段的值来确定；确定了有多少个节，就确定了有多少一个节表，一个节表记录管理一个节的信息。一个 PE 文件从哪里开始是节表（硬盘上的地址）：DOS 头大小 + 垃圾空位 + PE 签名大小 + 标准 PE 头大小 + 可选 PE 头大小(需要查)；我们知道 DOS 头大小固定为 64 字节；PE 签名大小为 4 字节；标准 PE 头大小固定为 20 字节；可选 PE 头大小可以通过标准 PE 头中的 SizeOfOptionalHeader 字段的值来确定

```
所以：e_lfanew + 4 + 20 + SizeOfOptionalHeader = 节表开始地址
```

如果文件运行装载到内存中节表在 4GB 内存中的地址要加上 imagebase 的值，才是节表真正在内存中的起始地址

- 然后看一下它的结构

```
#define IMAGE_SIZEOF_SHORT_NAME 8 //宏定义
typedef struct _IMAGE_SECTION_HEADER{
    BYTE Name[IMAGE_SIZEOF_SHORT_NAME]; *   //每一个节都可以取一个名字，最大长度为8字节
    union{
    	DWORD   PhysicalAddress;
        DWORD   VirtualSize;
    }Misc; *                           //Misc就是此联合体类型的变量
    DWORD VirtualAddress; *
    DWORD SizeOfRawData; *
    DWORD PointerToRawData; *
    DWORD PointerToRelocations;
    DWORD PointerToLinenumbers;
    WORD NumberOfRelocations;
    WORD NumberOfLinenumbers;
    DWORD Characteristics; *
} IMAGE_SECTION_HEADER, *PIMAGE_SECTION_HEADER;
```

一个节对应一个节表，即一个节表由一个结构体类型的节表记录信息。节表数据紧接着可选 PE 头数据后面，节表中会循环上述的结构，因为一个节就对应一个结构，且这些数据都是挨着顺序存放的

![](image-31-765x1024.png)

![](image-32-1024x483.png)

- Name\[IMAGE_SIZEOF_SHORT_NAME\]：8 个字节，一般情况下是以"\\0"结尾的 ASCII 码来表示节的名称，名字可以自定义（一般是编译器加的）。我们知道数组元素是从最后一个元素倒着入栈的，所以从低地址往高地址分别是从数组的第一个元素到最后一个元素

- Misc：表示该节装入内存时在对齐前的真实尺寸：联合体类型变量，大小为 4 字节。该值改了对程序的运行没有影响，如果一个程序没被修改过，那这个值就是准确的，如果被其他的软件加工过，就可能变的不准确，但不影响程序运行

为什么定义成联合体，因为有些编译器或者软件喜欢用 PhysicalAddress 这个变量名表示，有些又喜欢用 VirtualSize 这个变量名表示，那么为了两个都可以使用，而且共用一个内存不占用多余的内存，就使用联合体，想使用 PhysicalAddress 就用 Misc.PhysicalAddress；想使用 VirtualSize 就用 Misc.VirtualSize

![](image-33-466x1024.png)

- VirtualAddress:此节在内存中的偏移起始地址：所以加上 imagebase 才是 exe 文件运行时，此节在 4GB 内存中的地址，大小为 4 字节

![](image-34-459x1024.png)

- SizeOfRawData：此节在文件中对齐后的尺寸：4 字节。即文件在硬盘上时，文件对齐后此节的大小

![](image-35.png)

- PointerToRawData：此节文件对齐后在文件中的偏移地址：即表示文件在硬盘上时，经过文件对齐后，此节相对于文件起始地址的偏移量，一定是文件对齐的整数倍。4 字节

![](image-36-332x1024.png)

- Characteristics：节的属性，同样的，4 字节（32 位），每一位都表示此节的一个属性。我们一般关注的属性是是否可读、可写、可执行

![](image-37-1024x366.png)

举个例子

如果分析出来名为.text 的节的 characteristics 字段值为 0x60000020：因为 0x60000020 即第 31 位为 1、第 30 位为 1、第 6 位为 1，根据上面的分析：表示此.text 节的属性是可读、可执行、包含可执行代码，上面表中的那些值其实就是告诉你哪个位置上应该是 1

### 可执行文件的读取到装入内存过程

![](image-29-1024x678.png)

1.文件数据读到 FileBuffer，这个也就是上篇文章做的作业，

FileBuffer：通过 winhex 或者十六进制编译器打开一个存储在硬盘上的可执行文件，打开后显示的数据就是文件在硬盘上的状态。此过程只是将文件在硬盘上时的数据原封不动的复制一份到内存（FileBuffer）中，我们称这块内存叫 FileBuffer，通过软件显示出来。此时文件的格式还不具备 windows 运行格式  
2.将文件装载到 ImageBuffer

将文件从 FileBuffer 装入 ImageBuffer，即将文件对齐拉伸成内存对齐，这个过程就是将文件装入自己的 4GB 虚拟内存中，此过程称为 PE loader。此时文件的格式基本满足 windows 运行格式。我们称将文件拉伸装载到的内存为 imageBuffer，即内存镜像（拉伸的细节后面学习），

此时文件在 4GB 虚拟内存中的起始地址，就是 imagebase，一般为 0x00400000，接着就可以通过 imagebase + addressofentrypoint 找到文件装载到内存后真正的程序入口地址；或者用 imagebase 加上一些偏移地址值就可以得到文件其他内容在运行时装入 4GB 内存后的地址

3.操作系统将虚拟地址转化成物理地址

上面的两个 FileBuffer 和 ImageBuffer 提到的所有地址，其实都是虚拟地址，我们学过操作系统知道，操作系统最后还要将这些虚拟地址转换为物理地址，才是真正的装入到真实内存中。这个过程操作系统帮我们做了不需要手动做，所以现在先了解到上面两个过程即可，就是文件在硬盘上时的数据格式，复制一份到 FileBuffer 中显示出来；运行时文件经过 PE Loader 将文件拉伸，装载到 ImageBuffer 中

所以 ImageBuffer 中的文件格式虽然满足了 windows 运行格式，但是此时这个文件还没有执行！！即还没有分配 CPU，后面操作系统还要做很多事情，才能让 imageBuffer 中的文件真正装入实际内存中，执行起来！在 imageBuffer 中其实是一个 4GB 虚拟内存，装入 imagebuffer 时有一个文件被拉伸的过程，此时已经无限接近于可被执行的格式了，但是还没有执行