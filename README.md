# HandyShellScripts
A curated collection of handy Shell scripts for daily productivity and powerful terminal automation.

## 为什么要用 Shell？
Shell 是操作系统中的“命令解释器”，它负责接收用户输入的命令并将其传递给操作系统内核执行。Shell 既可以交互式使用（输入命令、实时反馈），也可以通过脚本自动化批量操作。

## 常见 Shell 类型
- **Bash**（Linux/Unix 默认，最流行）
- **sh**（最基础的 Bourne Shell，兼容性好）
- **PowerShell**（Windows 默认，支持对象和丰富脚本功能）
- Zsh（功能强大，支持自动补全和插件，macOS 新版默认）

## Terminal、TTY、Shell、Kernel 的区别
- **Terminal（终端）**：用户与计算机交互的窗口，可以是物理设备（老式终端机）或软件（如 Windows Terminal、iTerm2、GNOME Terminal）。
- **TTY（Teletype）**：最早指电传打字机，后来泛指“终端设备”，在 Linux 下 `/dev/tty*` 代表不同的虚拟终端。
- **Shell**：命令解释器，运行在终端里，负责解析和执行用户输入的命令。
- **Kernel（内核）**：操作系统的核心，负责管理硬件资源和系统调用，Shell 通过内核完成实际操作。

简而言之：
- 用户在 **Terminal** 输入命令
- **TTY** 是底层的终端接口
- **Shell** 解释命令
- **Kernel** 执行命令


---


**今天又用到了什么shell命令**

# Linux Bash

who
whoami
systemctl
curl 
chmod 
ps 
tree 
ls
grep
grep -A 10 -B 2 ">>> cuda environment variables >>>" ~/.bashrc
source 
echo 


# Windows Powershell
dir
ls
Get-ChildItem


# windows cmd