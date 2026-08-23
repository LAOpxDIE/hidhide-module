# 架构说明

## 注册阶段重写

Linux 输入驱动在调用 `input_register_device()` 前已经填好 `input_dev`。HIDHide 在这一点
执行前置回调，确认设备满足目标条件，然后修改：

- `id.bustype`
- `id.vendor`
- `id.product`
- `id.version`
- `name`
- `phys`
- `uniq`

因此 evdev、Android InputReader 和 `/proc/bus/input/devices` 看到的是修改后的身份。
模块不修改触摸坐标、按键、时序或报告数据。

## 两种实现

KPM 版本通过 KernelPatch `hook_wrap1` 安装 inline hook。它运行时解析
`input_register_device`，但为了不依赖目标内核头文件，直接使用 arm64
`struct input_dev` 头部的已知偏移。这是主要兼容性风险。

传统 LKM 版本使用内核 kprobe，并通过目标内核头文件访问结构字段。它避免了硬编码字段
偏移，但引入精确内核源码、配置和 `vermagic` 依赖。

## 字符串生命周期

输入设备注册后会长期保存 `name` 和 `phys` 指针。不能让这些指针指向可能在卸载时释放的
模块静态数据。两个实现都会为每次成功重写分配不可变副本，并让其存活至设备重启。
这是有意的小额、有限内存保留，用来避免卸载后的悬空指针。

## 启动顺序

`post-fs-data.sh` 尽早加载钩子。若兼容引擎尚未就绪，`service.sh` 会在服务阶段重试。
对于钩子安装前已经枚举的 USB 多点触摸设备，服务脚本会通过 USB `authorized` 节点触发
一次重新枚举，再由钩子处理。
