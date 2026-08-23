# Contributing

提交改动前请先运行：

```bash
./scripts/check-release.sh
```

贡献应遵守以下约束：

- Android 端脚本保持兼容 `/system/bin/sh`，不用 `eval`，也不 `source` 外部配置；
- 所有进入 root shell 的用户输入必须先经过严格白名单；
- 不扩大内核写入字段和设备匹配范围，除非同时提供明确的安全论证；
- `name`、`phys`、`uniq` 是指针，不得写入驱动原有缓冲；
- KPM 结构偏移变更必须列出验证过的内核版本和结构布局证据；
- 不提交设备镜像、日志、诊断报告、工具链、二进制产物或第三方源码快照；
- 不提交与 HIDHide 模块无关的硬件、应用、服务或产品资料。

Pull Request 应说明行为变化、失败模式、测试设备范围和恢复方法。
