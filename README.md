# HIDHide Module

HIDHide 是一个面向 Android root 环境的外部 HID 设备身份伪装模块。它在
`input_register_device()` 注册阶段匹配外部 HID 输入设备，并重写其输入层身份。
当前内置匹配策略聚焦 USB 多点触摸 HID，可使 Android 将目标设备按内置 I²C 输入设备处理。

仓库只包含 HIDHide 模块本身，不包含外设实现、控制端、设备固件或测试设备数据。

## 功能

- KPM 实现：通过 KernelPatch inline hook 工作，不受 Linux `vermagic` 约束。
- 传统 LKM 实现：使用 kprobe，必须针对设备正在运行的内核精确编译。
- 自动模式：当前匹配 `BUS_USB + BTN_TOUCH + ABS_MT_SLOT`，后续可扩展其他 HID 类型。
- 指定模式：仅匹配配置的 VID/PID。
- KernelSU WebUI：查看设备、修改目标身份并生成诊断报告。
- 启动恢复：处理模块加载前已经完成枚举的外接触摸设备。

## 重要限制

这是高风险内核代码，不承诺跨设备、跨内核或跨 KernelPatch 版本通用。

KPM 实现依赖 arm64 上 `struct input_dev` 头部字段布局。它虽然没有标准 LKM 的
`vermagic` 限制，但仍存在 ABI 和 OEM 内核布局兼容性要求。未经验证的设备可能加载失败，
严重时可能崩溃或无法启动。请先准备可恢复的启动镜像，并在测试设备上验证。

本项目用于兼容性研究和自有设备测试。不得用它规避平台规则、安全控制或第三方服务条款。

## 目录

```text
.
├── kpm/                  # KernelPatch Module 源码与 Makefile
├── webroot/              # KernelSU WebUI
├── docs/                 # 安装和架构说明
├── scripts/              # 发布前自检
├── hidhide.c             # 传统 kprobe LKM
├── load.sh               # KPM/LKM 加载器
├── service.sh            # 启动恢复与诊断
├── collect.sh            # 诊断报告生成器
└── pack.sh               # 生成可安装 ZIP
```

## 构建 KPM

要求：

- arm64 bare-metal GNU 工具链，前缀为 `aarch64-none-elf-`
- [KernelPatch](https://github.com/bmax121/KernelPatch) 源码
- GNU Make

```bash
git clone https://github.com/bmax121/KernelPatch.git KernelPatch
make -C kpm \
  KP_DIR=../KernelPatch \
  TARGET_COMPILE=/path/to/aarch64-none-elf-
```

产物为 `kpm/hidhide.kpm`。发布构建应固定并记录 KernelPatch 提交，不要直接依赖
不断变化的默认分支。

## 构建传统 LKM

```bash
make KDIR=/path/to/exact-kernel-source \
  ARCH=arm64 \
  CROSS_COMPILE=aarch64-linux-gnu-
```

`KDIR` 必须与目标设备的 `uname -r` 和内核配置完全匹配。

## 打包

先生成 KPM 或 LKM，再执行：

```bash
./pack.sh
```

输出位于 `dist/HIDHide-KSU.zip`，同时生成 SHA-256 文件。多内核 LKM 包使用：

```bash
./pack.sh --multi
```

安装与验证步骤见 [docs/INSTALL.md](docs/INSTALL.md)。

## 发布前检查

```bash
./scripts/check-release.sh
```

该检查会拒绝归档、日志、编译产物、设备镜像、绝对路径和常见密钥材料。

## 许可证

本项目采用 [GPL-2.0-only](LICENSE)。KernelPatch 是独立的上游项目，请遵守其许可证。
