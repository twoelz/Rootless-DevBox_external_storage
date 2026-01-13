# Rootless-DevBox（带特定/外部 nix 缓存文件夹）

一个无需 sudo 或 root 权限即可在无根环境下自动安装 Devbox 的简单解决方案。原始版本：https://github.com/nebstudio/Rootless-DevBox

**Fork 信息:**
来自 https://github.com/twoelz 的此 fork 添加了多项增强功能，以支持外部存储安装并改善整体安装体验。主要添加内容包括：

**主要功能：**
1. **自定义 Nix 存储位置**：交互式提示在外部存储（例如 42 school 的 `/sgoinfre`）上安装 Nix 存储，而不是硬编码的 `~/.nix`
2. **智能缓存符号链接**：仅将缓存符号链接到外部存储，将关键数据库保留在本地
3. **多 Shell 支持**：配置 bash、zsh 和 fish shell（原始版本仅支持 bash）
4. **中国网络镜像**：为中国大陆用户提供可选的 SJTU/清华镜像
5. **自动 chroot 功能**：shell 启动时可选自动进入 nix-chroot
6. **增强的卸载程序**：检测自定义安装位置并安全删除所有组件

以下是符号链接方法的详细描述：

在自定义位置（例如外部存储）安装 Nix 时，安装程序会为 Nix 缓存目录创建符号链接：

~/.cache/nix → <自定义位置>/cache/nix

**为什么只有缓存（不包括数据/数据库）：**

- 缓存目录：大（GB 级别），可重新生成，清除安全 → 进入外部存储
- 数据目录：小（MB 级别），包含关键 SQLite 数据库 → 保持本地以确保可靠性和性能

**优势：**

- 节省空间：Nix 的下载缓存（存储之外最大的消费者）位于外部存储
- 一致性：全局 Nix 命令和 nix-chroot 都使用相同的缓存，防止重复
- 隔离：只有 Nix 缓存被重定向；其他应用程序继续正常使用 ~/.cache
- 可靠性：关键数据库保留在快速可靠的本地存储中（~/.local/share/nix）
- Nix 兼容：Nix 存储本身（~/.nix 或自定义位置）保持为真实目录（不是符号链接）

**行为：**

- 默认安装（~/.nix）：不创建符号链接，使用标准 XDG 位置
- 自定义安装：创建缓存符号链接，备份任何现有的 ~/.cache/nix 目录
- 数据库/状态保留在 ~/.local/share/nix 中以确保安全

这种方法避免了设置会影响整个系统所有应用程序的全局 XDG_CACHE_HOME 和 XDG_DATA_HOME 变量。

**Shell 配置：**
安装程序向您的 shell dotfiles（bash/zsh/fish）添加配置。此配置：
- 将 `~/.local/bin` 和 `~/.nix-profile/bin` 添加到 PATH（用于运行 devbox/nix 命令）
- 引用 Nix 自己的环境设置
- 不全局设置 XDG 变量（缓存重定向使用符号链接代替）

[![GitHub License](https://img.shields.io/github/license/nebstudio/Rootless-DevBox)](https://github.com/nebstudio/Rootless-DevBox/blob/main/LICENSE)
[![GitHub Stars](https://img.shields.io/github/stars/nebstudio/Rootless-DevBox?style=social)](https://github.com/nebstudio/Rootless-DevBox/stargazers)
[![GitHub Issues](https://img.shields.io/github/issues/nebstudio/Rootless-DevBox)](https://github.com/nebstudio/Rootless-DevBox/issues)

## 项目简介

Rootless-DevBox 让用户可以在没有 root 权限的环境（如共享主机、学校机房、公司受限环境等）下安装和使用 [Devbox](https://github.com/jetify-com/devbox)。它利用 [nix-user-chroot](https://github.com/nix-community/nix-user-chroot) 创建一个容器化环境，使 Nix 和 Devbox 能在用户空间运行，无需提升权限。

## 特性

- 🛡️ **无需 Root**：无需 sudo 或 root 权限即可安装和使用 Devbox
- 🔄 **隔离环境**：在独立环境中运行包，不影响系统
- 🚀 **一键安装**：一条脚本自动完成全部安装
- 💻 **跨平台**：支持多种 Linux 发行版和架构
- 🔒 **安全**：只修改用户目录，不动系统文件
- 🌏 **中国网络友好**：脚本可自动检测并配置清华大学 Nix 镜像源，适用于中国大陆或受网络阻断的环境

> **说明：**  
> 虽然脚本尽可能地防止网络阻断，自动添加了清华 Nix 镜像源，但部分依赖（如 GitHub 相关资源）仍可能因网络限制无法访问。建议在中国大陆等受限环境下，**临时配置代理**，以确保脚本和 Devbox 能够顺利下载安装和运行。

## 快速开始

> **注意：**  
> 安装脚本是**交互式**的，会在多个步骤提示你输入。这是为了让你在安装过程中有选择权，确保你了解每一步，并能根据实际环境灵活调整。  
> 不要因为提示较多而感到困扰——这是为了最大兼容性和用户自主权，尤其适用于多样或受限的 Linux 环境。

在终端中运行以下命令：

```bash
# 下载安装脚本
curl -o rootless-devbox-installer.sh https://raw.githubusercontent.com/nebstudio/Rootless-DevBox/main/install.sh

# 赋予执行权限
chmod +x rootless-devbox-installer.sh

# 运行安装脚本
./rootless-devbox-installer.sh
```

## 工作原理

Rootless-DevBox 主要分三步：

1. **安装 nix-user-chroot**：下载并配置用户空间 chroot 工具
2. **创建 Nix 环境**：在用户目录下搭建 Nix 容器环境
3. **安装 Devbox**：在该环境中安装 Devbox，无需 root

安装完成后，使用 `nix-chroot` 命令进入开发环境，Devbox 即可用。

## 使用方法

### 进入 Nix 环境

安装后，运行：

```bash
nix-chroot
```

你会看到命令提示符变为：

```
(nix-chroot) user@hostname:~$
```

### 使用 Devbox

在 nix-chroot 环境内可直接使用 Devbox：

```bash
# 查看帮助
devbox help

# 初始化新项目
devbox init

# 添加包
devbox add nodejs python

# 启动开发环境 shell
devbox shell
```

### 退出环境

```bash
exit
```

## 系统要求

- Linux 操作系统
- Bash shell
- 可用网络
- 无需 root 权限

## 支持的架构

- x86_64
- aarch64/arm64
- armv7
- i686/i386

## 常见问题

**Q: 运行 nix-chroot 提示找不到命令？**  
A: 请确保 `~/.local/bin` 已加入 PATH。可执行 `source ~/.bashrc` 或重启终端。

**Q: 下载 nix-user-chroot 失败？**  
A: 检查网络。如果仍有问题，可手动从 [releases 页面](https://github.com/nix-community/nix-user-chroot/releases) 下载对应二进制文件。

**Q: Nix 环境内无法安装包？**  
A: 可能是磁盘配额或空间不足。用 `df -h ~` 检查空间。

如需更多帮助，请[提交 issue](https://github.com/nebstudio/Rootless-DevBox/issues)。

## 卸载

有两种方式卸载 Rootless-DevBox：

### 方式一：使用卸载脚本

我们提供了卸载脚本：

```bash
# 下载卸载脚本
curl -o rootless-devbox-uninstaller.sh https://raw.githubusercontent.com/nebstudio/Rootless-DevBox/main/uninstall.sh

# 赋予执行权限
chmod +x rootless-devbox-uninstaller.sh

# 运行卸载脚本
./rootless-devbox-uninstaller.sh
```

### 方式二：手动卸载（推荐）

1. **删除已安装的二进制文件**：
   ```bash
   rm -f ~/.local/bin/devbox
   rm -f ~/.local/bin/nix-chroot
   rm -f ~/.local/bin/nix-user-chroot
   ```

2. **清理 Nix 目录**（可选，会删除所有 Nix 包）：
   ```bash
   rm -rf ~/.nix
   ```

3. **⚠️ 重要：编辑你的 shell 配置文件**（如 `~/.bashrc`、`~/.zshrc` 等）：

   - 删除 PATH 修改行：
     ```bash
     export PATH="$HOME/.local/bin:$PATH" # Added by Rootless-DevBox
     ```
   - 删除 PS1 提示符块：
     ```bash
     # Rootless-DevBox nix-chroot environment indicator
     if [ "$NIX_CHROOT" = "1" ]; then
       PS1="(nix-chroot) \[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ "
     fi
     ```

   编辑后，执行：
   ```bash
   source ~/.bashrc
   ```

> **注意**：虽然卸载脚本会尝试自动修改配置文件，但**建议手动检查并删除相关行**，以避免误删其他环境变量。

卸载后，建议重启终端以确保所有更改生效。

## 贡献

欢迎贡献！请提交 Pull Request。

1. Fork 本仓库
2. 创建分支：`git checkout -b feature/your-feature`
3. 提交更改：`git commit -m 'Add your feature'`
4. 推送分支：`git push origin feature/your-feature`
5. 提交 Pull Request

## 鸣谢

本项目离不开以下优秀项目：

- [nix-user-chroot](https://github.com/nix-community/nix-user-chroot)
- [Devbox](https://github.com/jetify-com/devbox)
- [Nix](https://nixos.org/)

## 许可证

本项目采用 MIT 协议，详见 [LICENSE](LICENSE)。

## 安全说明

Rootless-DevBox 只会修改你的用户主目录文件，不需要也不会使用 root 权限。即使在受限环境下也很安全。

---

⭐ 如果你觉得本项目有帮助，欢迎在 GitHub 上点个 Star！⭐

由 [nebstudio](https://github.com/nebstudio) ❤️ 制作