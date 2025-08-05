---
layout: mypost
title: "Windows 逆向-RVA 转 FOA"
categories: [Windows 逆向]
---

这里直接上代码了，再顺便做个实验验证一下

这个是main函数里面的内容，懒得改上个实验那些代码了，也说明了，做个附加小实验

```C
#include <iostream>
#include "PeFuction.h"

int main()
{
	char* FilePath = (char*)"D:/PETool 1.0.0.5.exe";  //打开的PE文件绝对路径
	char* SavePath = (char*)"D:/FakeNotePad.exe"; //保存的路径

	char* FileBufferPoint = ReadPeFile(FilePath);
	char* ImageBufferPoint = CopyFileBufferToImageBuffer(FileBufferPoint);
	char* NewBufferPoint = CopyImageBufferToNewBuffer(ImageBufferPoint);
	int flag = MemeryToFile(NewBufferPoint , SavePath);
	if (flag) {
		printf("全部成功，程序已在对应路径生成\n");
	}
	else {
		printf("失败，再检查检查\n");
	}
	printf("再加一个小实验，将RVA转化为FOA\n");
	int FileAddress = ImageAddressToFileAddress(FileBufferPoint ,0x00401010);
	if (FileAddress == 0) {
		printf("出错啦，请再检查一下\n");
	}
	else {
		printf("0x%08X\n" , FileAddress);
	}
	free(FileBufferPoint);
	free(ImageBufferPoint);
	free(NewBufferPoint);
	return 0;
}
```

然后函数功能的实现写在了那个PeFuction.c里面，不懂的看上篇文章，然后记得加头文件哈

```C
int ImageAddressToFileAddress(char* FileBufferPoint, int ImageAddress) {
	//ImageAddressToFileAddress：将ImageBuffer里面的节地址转换为对应的FileBuffer的节地址
	//参数说明：
	//FileBufferPoint：指向FileBuffer的首地址
	//ImageAddress：传入ImageBuffer里面的节地址
	//返回值说明：
	//转换成功返回节地址，地址不在节内或在空白区则返回0
	_IMAGE_DOS_HEADER* _image_dos_header = NULL;
	_IMAGE_FILE_HEADER* _image_file_header = NULL;
	_IMAGE_OPTIONAL_HEADER* _image_optional_header = NULL;
	_IMAGE_SECTION_HEADER* _image_section_header = NULL;

	_image_dos_header = (_IMAGE_DOS_HEADER*)FileBufferPoint;
	//下面这个别忘记了还有一个PE标记的大小，为4个字节
	_image_file_header = (_IMAGE_FILE_HEADER*)(FileBufferPoint + _image_dos_header->e_lfanew + sizeof(PE));
	_image_optional_header = (_IMAGE_OPTIONAL_HEADER*)((char*)_image_file_header + 20);
	_image_section_header = (_IMAGE_SECTION_HEADER*)((char*)_image_optional_header + _image_file_header->SizeOfOptionalHeader);

	int flag = 0;
	if (_image_section_header->VirtualAddress > ImageAddress - _image_optional_header->ImageBase) {
		return 0;
	}
	for (int i = 0; i < _image_file_header->NumberOfSections; i++) {
		if (ImageAddress - _image_optional_header->ImageBase >= _image_section_header->VirtualAddress && ImageAddress - _image_optional_header->ImageBase < _image_section_header->VirtualAddress + _image_section_header->Misc.VirtualSize) {
			flag = 1;
			break;
		}
		else {
			_image_section_header++;
		}
	}
	if (flag == 0) {
		return 0;
	}
	int TempAddress = ImageAddress - _image_optional_header->ImageBase - _image_section_header->VirtualAddress;
	return _image_section_header->PointerToRawData + TempAddress;
}
```

然后做个小实验，就拿.text段来举例

![](Screenshot_6.png)

然后在代码中将参数传成0x00401010，看结果

![](Screenshot_7-1024x498.png)

然后分别用二进制编辑器查看在硬盘上的exe和在内存中的exe

![](Screenshot_5-1024x693.png)

![此图片的alt属性为空；文件名为Screenshot_1-2-1024x564.png](image-52.png)

那可能有人就会说了，这不管文件还是内存对齐都是1000h啊，那我找一个对齐不一样的，就拿我们都在用Everything.exe来看

![](Screenshot_1-3-1024x449.png)

![](Screenshot_2-2-1024x481.png)

![](Screenshot_3-1024x279.png)

![](Screenshot_4-1024x439.png)

OKK了这个代码肯定是没有问题的，那演示就到这里了哈