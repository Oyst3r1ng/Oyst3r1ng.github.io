---
layout: mypost
title: "Windows 逆向-PE"
categories: [Windows 逆向]
---

## 前言

终于开了PE了，学好这个之后就可以写一个PE的小工具，这回笔记基本上就把PE的整体给说完了，作业的话打算之后专门出一篇文章说PE这方面的代码吧

![](images/image-38-1024x478.png)

## 学习过程

### 分节和对齐

#### 分节

这个可以和结构体对齐那一块做个类比，PE文件在硬盘和内存中都是分节存储的，把数据分成一段一段的，那为啥要分节呢，第一个原因就是可以节省内存空间，就是海东老师说的那个开小号的例子，第二个原因就是节省硬盘空间，文件在内存中段与段之间的空隙很大；而文件在硬盘上段与段之间的空隙比较小，即节省了硬盘空间

tip：

我们要知道这里的文件运行时所在内存和我们说的内存条不是一个概念，任何一个exe文件在32位计算机上运行时都有自己独立的4GB（232，即寻址范围最大是4GB）虚拟内存----其中有2GB是供应用程序使用的，另外2GB是操作系统用的  
我们可以想象成凡是运行后的程序虚拟上会有这样的4GB内存结构，但是实际上程序的数据都要经过操作系统帮我们管理按照特定的方式存到真实的内存条中

#### 对齐

硬盘对齐内存对齐粒度不相等

![](images/image-21-1024x896.png)

- 优点：节省了硬盘空间

- 缺点：减低了硬盘、内存之间数据相互传输的读写速度，因为内存和硬盘的对齐粒度不同，需要换算，定位查找就需要花费一定的时间

硬盘对齐内存对齐粒度相等

![](images/image-22-1024x858.png)

- 优点：由于对齐粒度一样了，当把文件从硬盘装入到内存中时可以省去很多运算，只需要确定好首地址

- 缺点：浪费了一定的硬盘空间

### PE文件的结构

![](images/image-23-1024x918.png)

#### DOS头

```C
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

这里主要就记两个，一个是**e\_magic**，用于判断是否为可执行文件，即如果显示`4D 5A`，说明该文件是一个可执行文件：.sys/.dll/.exe等；另一个是**e\_lfanew**，相对于文件首地址的偏移，用于定位PE文件，即此PE文件真正的PE结构开始的地址，值是不确定的，DOS头结尾到真正PE开始地址之间有空隙，不同的编译器会往里塞一些不同的数据，大小和内容都是不同的，取决于编译器，而且程序也不会使用到这块空间。但对于我们来说其实就是一些垃圾数据，想往里放什么就放什么，且大小是不确定的，但是我们也可以在这做手脚，既然装入内存中了，就有了分配的内存地址，那么就可以想办法让程序去访问这个地址中的数据，所以即使程序自身运行时不会使用这块空间，但是我们可以想办法访问（想想函数指针那里）

#### PE标记

即e\_Ifanew指向的地址，就是一个PE的标记或者叫签名

```
DWORD Signature;
```

所以一个可执行文件应该满足"MZ"标记和"PE"标记，如果这两点不满足可能被修改过，或者就不是一个可执行文件

#### 标准PE头

```C
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

- Machine：支持的CPU型号，如果是0x0表示能在任何处理器上执行；如果是0x14C表示能在386及后续处理器上执行

- NumberOfSections：文件中存在的节的总数：如果要新增节或者合并节，就要修改这个值。大小表示不包括DOS头、NT头、节表，此文件分为几个节（例如.text、.idata等）

- TimeDateStamp：时间戳，文件的创建时间（和操作系统的创建时间无关），编译器填写的，时间戳的使用案例：比如现在要给一个.exe文件加壳，有些加壳软件不光要提供给它.exe文件，还需要其对应的.map文件，这个文件中记录了此.exe文件中的所有的函数的名字、地址、参数等信息，即exe文件中所有函数的描述。这两个文件编译器编译时一起生成，那么map和exe的时间戳就是一致的，如果现在这个.exe文件需要反复修改，那么exe文件的时间戳就会变，但是map的时间戳没有更新，导致exe和map不同步，如果加壳子还是按照map中的记录信息去加壳，就可能出现错误。所以很多加壳软件在加壳之前会检查exe和map文件的时间戳是否一致

- SizeOfOptionalHeader：可选PE头的大小，32位PE文件默认**E0h**，64位PE文件默认为**F0h**（大小可以自定义）

- Characteristics：16位的每个位都表示不同的特征，可执行文件值一般都是0x010F，即读完后16位二进制数中从低到高第1、2、3、4、9位上的值为1，其他位为0，下面是每一位的1含义

![](images/image-24.png)

#### 可选PE头

```C
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

- Magic：说明文件类型，如果值为0x010B，表示是32位下的PE文件；如果值为0x020B，表示是64位下的PE文件

- SizeOfCode：所有代码节大小的和，必须是FileAlignment的整数倍

比如文件只有一个代码节，大小为100h字节，如果文件对齐粒度是200h，那么会补0填充够200h字节，所以会显示200h（编译器填的）；若文件有两个代码节，两个都是10字节，这个值应为400h。但是计算机发展到现在已经不使用这个值了，改了也没事，删除程序也可以正常运行，但是现在之所以保留下来是因为向下兼容，以前的软件程序发布已经遵循了这个格式，如果现在修改了，那全世界以前发布的.exe等文件都需要删除这几位

- SizeOfInitializedData：已初始化数据大小的和，必须是FileAlignment的整数倍，编译器填的，目前计算机已经不使用这个值了，删掉也可以，保留下来只是为了向下兼容

- SizeOfUninitializedData：未初始化数据大小的和，必须是FileAlignment的整数倍，编译器填的，目前计算机已经不使用这个值了，删掉也可以，保留下来只是为了向下兼容

- AddressOfEntryPoint：程序入口点OEP（程序真正执行的起始地址），这个值是偏移量，而不是真正运行在内存中的程序入口地址。需要再加上加载到内存的基址（imagebase），才是程序运行在内存中（4GB虚拟内存）的程序入口。这个值不是确定的

注意：程序入口在默认情况下一般都在.code代码节当中，且OEP不是只能在.code代码节开始的位置，可以从此节当中的任何合理位置开始，也可以在其他节（如.text等）的任意合理位置开始。OEP可以人为修改，但是最后一定要让.exe文件能运行起来

注意：程序入口不能理解为C语言的main函数，那只是我们写的代码的执行入口，因为在main函数被调用前还做了很多事情，所以OEP一定是.exe双击开始运行时程序开始的那个地址，可以用OD打开看一下，如下

内存中的程序入口地址：使用OD打开文件（完全模拟文件运行时加载到内存中的状态，不是硬盘上的状态）。所以OD打开一个可执行文件后，会在程序入口地址处设置断点，让程序停下来，这里就是文件在内存中真正的入口点。即文件装入到4GB虚拟内存中的起始基地址 +相对于文件首地址的偏移的程序入口地址，即imagebase + AddressOfEntryPoint

![](images/image-25-1024x651.png)

- BaseOfCode：顾名思义，就是指着代码开始的基址，但这个是可以改的，

不要和程序入口混为一谈，不是代码一有，程序就要执行，程序入口可以设定到任何地方，只是在没有修改过PE结构的情况下程序入口一般都在.code代码节当中的某一个位置。如果要自己修改，比如修改到数据中，最后一定要能让程序能运行起来，不能胡改，不然没有意义

- BaseOfData：就是数据开始的基址，这个也可以改

- ImageBase：内存镜像基址：我们知道每一个.exe程序都有属于自己的4GB虚拟内存，这个值就是当程序运行装入到自己的虚拟4GB内存中后的文件的起始位置。imagebase一般都是0x00400000，不能超过0x80000000，因为我们写的程序的数据只能在内存的2GB用户区中，不能占用2GB系统区

这一块的话，现在可以这么理解，一个exe的PE文件是由一堆PE文件组成的，exe本身是一个PE文件，满足PE结构，但是exe中可能还用到了很多dll，每一个dll也是一个PE文件，也满足PE结构，这些dll有自己的功能和作用，拼凑到一个exe文件中，exe文件就有了完整的功能。所以相当于很多PE文件在一个PE文件中。又称exe文件有很多模块构成，每一个.dll都是一个模块。  
那么为什么从400000开始也就理解了吧，就是和前面的文件对齐，内存对齐的道理都是一样的，每一个dll文件开始都是从imagebase的倍数开始的，还有一个原因就是内存保护

```
因为内存保护！我们前面学过，free一个动态分配内存的指针后，一定要将指针 = NULL，那么指针等于NULL后，这个指针指向的地址就是0x0，那么如果此时访问此指针指向的数据，或者向后偏移一定大小的范围内的数据，编译器会立马报错。所以4GB内存中开始空出来一些内存空间就是为了内存保护的
```

![](images/image-26-1024x970.png)

但是在64位上会出现这样的情况

![](images/35ff65d9c1c1d16fe688ebdf36d01d58-1024x554.png)

那个1400是硬盘上的，但是加载到内存里面就是那个7ff什么什么的，xp默认一直是1000

![](images/image-30-1024x951.png)

![](images/8ABBBDDBF399DFF099A45FD092C2C520.png)

- SectionAlignment：内存对齐，可执行文件运行时装入4GB虚拟内存中的对齐粒度，一般为0x1000字节

- FileAlignment：文件对齐，可执行文件在硬盘的对齐粒度，一般为0x200字节，还有的是0x1000字节，和内存对齐粒度相等

- SizeOfImage：内存中整个PE文件的映射尺寸：即文件运行时装入4GB虚拟内存后的整个文件数据大小（要考虑内存对齐）。可以比实际的值大（比如文件对齐为0x200，内存对齐为0x1000时），但必须是SectionAlignment的整数倍

- SizeOfHeaders：所有头+节表按照文件对齐后的大小：即DOS头 + 垃圾数据 + PE签名 + 标准PE头 + 可选PE头 + 节表，按照文件对齐后的大小。必须是FileAlignment的整数倍，否则加载会出错

举例：假如一个可执行文件的所有头和节表加起来大小为0x1800字节，但是第一个节表开始位置应该是0x2000，因为要满足文件对齐粒度0x1000

![](images/image-27.png)

剩下的就不太重要了，直接给个图片

![](images/image-28-1024x366.png)

#### 节表

- 节表是表，肯定不止一个数。一个PE文件有多少个节，就有多少个节表！每一个节表的大小是确定的，40字节，如何确定有多少个节：可以通过标准PE头中的NumberOfsections字段的值来确定；确定了有多少个节，就确定了有多少一个节表，一个节表记录管理一个节的信息。一个PE文件从哪里开始是节表（硬盘上的地址）：DOS头大小 + 垃圾空位 + PE签名大小 + 标准PE头大小 + 可选PE头大小(需要查)；我们知道DOS头大小固定为64字节；PE签名大小为4字节；标准PE头大小固定为20字节；可选PE头大小可以通过标准PE头中的SizeOfOptionalHeader字段的值来确定

```
所以：e_lfanew + 4 + 20 + SizeOfOptionalHeader = 节表开始地址
```

如果文件运行装载到内存中节表在4GB内存中的地址要加上imagebase的值，才是节表真正在内存中的起始地址

- 然后看一下它的结构

```C
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

一个节对应一个节表，即一个节表由一个结构体类型的节表记录信息。节表数据紧接着可选PE头数据后面，节表中会循环上述的结构，因为一个节就对应一个结构，且这些数据都是挨着顺序存放的

![](images/image-31-765x1024.png)

![](images/image-32-1024x483.png)

- Name\[IMAGE\_SIZEOF\_SHORT\_NAME\]：8个字节，一般情况下是以"\\0"结尾的ASCII码来表示节的名称，名字可以自定义（一般是编译器加的）。我们知道数组元素是从最后一个元素倒着入栈的，所以从低地址往高地址分别是从数组的第一个元素到最后一个元素

- Misc：表示该节装入内存时在对齐前的真实尺寸：联合体类型变量，大小为4字节。该值改了对程序的运行没有影响，如果一个程序没被修改过，那这个值就是准确的，如果被其他的软件加工过，就可能变的不准确，但不影响程序运行

为什么定义成联合体，因为有些编译器或者软件喜欢用PhysicalAddress这个变量名表示，有些又喜欢用VirtualSize这个变量名表示，那么为了两个都可以使用，而且共用一个内存不占用多余的内存，就使用联合体，想使用PhysicalAddress就用Misc.PhysicalAddress；想使用VirtualSize就用Misc.VirtualSize

![](images/image-33-466x1024.png)

- VirtualAddress:此节在内存中的偏移起始地址：所以加上imagebase才是exe文件运行时，此节在4GB内存中的地址，大小为4字节

![](images/image-34-459x1024.png)

- SizeOfRawData：此节在文件中对齐后的尺寸：4字节。即文件在硬盘上时，文件对齐后此节的大小

![](images/image-35.png)

- PointerToRawData：此节文件对齐后在文件中的偏移地址：即表示文件在硬盘上时，经过文件对齐后，此节相对于文件起始地址的偏移量，一定是文件对齐的整数倍。4字节

![](images/image-36-332x1024.png)

- Characteristics：节的属性，同样的，4字节（32位），每一位都表示此节的一个属性。我们一般关注的属性是是否可读、可写、可执行

![](images/image-37-1024x366.png)

举个例子

如果分析出来名为.text的节的characteristics字段值为0x60000020：因为0x60000020即第31位为1、第30位为1、第6位为1，根据上面的分析：表示此.text节的属性是可读、可执行、包含可执行代码，上面表中的那些值其实就是告诉你哪个位置上应该是1

### 可执行文件的读取到装入内存过程

![](images/image-29-1024x678.png)

1.文件数据读到FileBuffer，这个也就是上篇文章做的作业，

FileBuffer：通过winhex或者十六进制编译器打开一个存储在硬盘上的可执行文件，打开后显示的数据就是文件在硬盘上的状态。此过程只是将文件在硬盘上时的数据原封不动的复制一份到内存（FileBuffer）中，我们称这块内存叫FileBuffer，通过软件显示出来。此时文件的格式还不具备windows运行格式  
2.将文件装载到ImageBuffer

将文件从FileBuffer装入ImageBuffer，即将文件对齐拉伸成内存对齐，这个过程就是将文件装入自己的4GB虚拟内存中，此过程称为PE loader。此时文件的格式基本满足windows运行格式。我们称将文件拉伸装载到的内存为imageBuffer，即内存镜像（拉伸的细节后面学习），

此时文件在4GB虚拟内存中的起始地址，就是imagebase，一般为0x00400000，接着就可以通过imagebase + addressofentrypoint找到文件装载到内存后真正的程序入口地址；或者用imagebase加上一些偏移地址值就可以得到文件其他内容在运行时装入4GB内存后的地址

3.操作系统将虚拟地址转化成物理地址

上面的两个FileBuffer和ImageBuffer提到的所有地址，其实都是虚拟地址，我们学过操作系统知道，操作系统最后还要将这些虚拟地址转换为物理地址，才是真正的装入到真实内存中。这个过程操作系统帮我们做了不需要手动做，所以现在先了解到上面两个过程即可，就是文件在硬盘上时的数据格式，复制一份到FileBuffer中显示出来；运行时文件经过PE Loader将文件拉伸，装载到ImageBuffer中

所以ImageBuffer中的文件格式虽然满足了windows运行格式，但是此时这个文件还没有执行！！即还没有分配CPU，后面操作系统还要做很多事情，才能让imageBuffer中的文件真正装入实际内存中，执行起来！在imageBuffer中其实是一个4GB虚拟内存，装入imagebuffer时有一个文件被拉伸的过程，此时已经无限接近于可被执行的格式了，但是还没有执行