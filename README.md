# openTCS 中文语言包 (i18n-zh Overlay)

[![License: CC BY 4.0](https://img.shields.io/badge/License-CC%20BY%204.0-blue.svg)](https://creativecommons.org/licenses/by/4.0/)

**无需编译、无需修改源码、零依赖**的 openTCS 中文界面方案。

基于 Java 标准 `ResourceBundle` 的 classpath 优先加载机制，将中文翻译作为独立资源注入官方 openTCS binary distribution，实现中文界面。

## 原理

openTCS 使用 Java 标准 `ResourceBundle` 进行国际化。`ResourceBundle.getBundle()` 按 classpath 顺序查找资源文件：

1. 先在 classpath 前面的路径找 `Bundle_zh.properties`
2. 找不到才 fallback 到 JAR 内的 `Bundle.properties`（英文）

本项目的 `i18n-overlay/` 目录精确复制了 openTCS 的 i18n 资源包路径结构。只要把这个目录加到 classpath **最前面**，Java 就会优先加载我们的中文翻译，其余所有资源仍从官方 JAR 加载。

> 参考：[openTCS User's Guide - Application language](https://opentcs.org/docs/7/users-guide.html#_application_language)

## 快速开始

### 1. 下载官方 openTCS

从 [openTCS 官方下载页](https://www.opentcs.org/en/download.html) 下载 `opentcs-7.3.0-bin.zip` 并解压。

### 2. 应用中文语言包

```bash
# 克隆本项目
git clone https://github.com/children1987/opentcs-i18n-zh.git
cd opentcs-i18n-zh

# 运行安装脚本
./scripts/install.sh /path/to/opentcs-7.3.0
```

安装脚本会自动：
- 将 `i18n-overlay/` 复制到 openTCS 目录
- 修改所有启动脚本（`startKernel.sh`、`startModelEditor.sh` 等），在最前面注入 classpath
- 设置各应用配置文件的 `locale=zh`

### 3. 启动

照常使用官方启动脚本，界面即为中文：

```bash
cd /path/to/opentcs-7.3.0/bin
./startKernel.sh
./startKernelControlCenter.sh
./startModelEditor.sh
./startOperationsDesk.sh
```

## 覆盖的应用模块

| 模块 | 翻译文件数 |
|------|-----------|
| Kernel Control Center | 1 |
| Model Editor (建模模式) | 12 |
| Operations Desk (操作模式) | 19 |
| Plant Overview Base | 1 |
| Common | 1 |
| Loopback 通信适配器 | 2 |
| **合计** | **44** |

## 许可

翻译内容采用 [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) 许可（与 openTCS 官方资源文件许可一致）。

## 与上游兼容性

本语言包目标版本为 openTCS 7.3.0。翻译文件仅包含翻译键值，不包含 Java 代码。通常同一大版本（7.x）内的翻译文件前后兼容，仅当上游增删 i18n key 时需要更新对应文件。
