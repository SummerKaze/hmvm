# hmvm - HarmonyOS Version Manager

> 中文 | [English](README_EN.md)

基于 [nvm](https://github.com/nvm-sh/nvm) 架构魔改的鸿蒙开发环境版本管理工具，用于管理 HarmonyOS command-line-tools 多版本切换。

## 功能特性

- **多版本管理**：安装、切换、卸载不同版本的 HarmonyOS command-line-tools
- **两种安装模式**：完整复制（`--from`）或符号链接（`--link`，零拷贝）
- **版本信息表格**：`hmvm list` 展示 codelinter / ohpm / hstack / hvigor / API 版本
- **环境变量自动设置**：`hmvm use` 自动设置 `DEVECO_NODE_HOME`、`DEVECO_SDK_HOME`、`HMVM_CURRENT`
- **项目配置**：支持 `.hmvmrc` 指定项目所需版本
- **别名**：支持 `default` 等别名，新建 shell 自动激活
- **跨平台**：支持 macOS / Linux（bash/zsh）和 Windows（PowerShell 5.1+）

## 安装

### macOS / Linux

#### 从本地仓库安装

```bash
git clone https://github.com/SummerKaze/hmvm.git ~/.hmvm
cd ~/.hmvm
./install.sh
```

安装脚本会将 source 指令写入 shell profile（`~/.zshrc` 或 `~/.bashrc`），重启终端或 `source ~/.zshrc` 后生效。

#### 从 GitHub 安装

```bash
curl -o- https://raw.githubusercontent.com/SummerKaze/hmvm/main/install.sh | bash
# 或
wget -qO- https://raw.githubusercontent.com/SummerKaze/hmvm/main/install.sh | bash
```

### Windows（PowerShell 5.1+）

**一键安装（无需管理员权限）：**

```powershell
irm https://raw.githubusercontent.com/SummerKaze/hmvm/main/install.ps1 | iex
```

**或从本地仓库安装：**

```powershell
git clone https://github.com/SummerKaze/hmvm.git $HOME\.hmvm
. "$HOME\.hmvm\install.ps1"
```

安装脚本会将加载指令写入 PowerShell profile（`$PROFILE`），重启终端或执行 `. $PROFILE` 后生效。

> **Windows 提示**：`--link` 选项在 Windows 上使用 **NTFS Junction**（目录联接），无需管理员权限，效果与 macOS/Linux 的符号链接相同。卸载时只删除联接本身，原始目录不受影响。

## 使用

### 安装 command-line-tools 版本

> **⚠️ 在线下载暂不支持**（TODO：华为账号登录鉴权，后续计划支持）。  
> 目前请通过以下两种本地安装方式导入已有的 command-line-tools 目录。

#### 方式一：完整复制安装

将指定目录的 command-line-tools **完整复制**到 hmvm 管理目录，安全独立但占用额外磁盘空间。

```
$ hmvm install 6.1.0 --from /path/to/command-line-tools
Installing HarmonyOS command-line-tools v6.1.0 from /path/to/command-line-tools...
Installed HarmonyOS command-line-tools v6.1.0 successfully.
Now using HarmonyOS command-line-tools v6.1.0
```

#### 方式二：符号链接安装（推荐，零拷贝）

直接创建符号链接，**不复制文件**，安装瞬间完成，适合已有 DevEco Studio 或独立 command-line-tools 的场景。

```
$ hmvm install 6.0.2 --from /path/to/command-line-tools_6.0.2 --link
Linking HarmonyOS command-line-tools v6.0.2 from /path/to/command-line-tools_6.0.2...
Linked HarmonyOS command-line-tools v6.0.2 successfully.
Now using HarmonyOS command-line-tools v6.0.2
```

> 卸载符号链接版本时（`hmvm uninstall`）只删除链接本身，不影响原始目录。

### 查看已安装版本

```
$ hmvm ls          
Cache directory:  /Users/h1007/GitHub/hmvm/versions/clt
Directory Size: 6.1G

┌─────────────┬────────────┬───────┬────────┬────────┬─────┬────────┬───────┐
│ Version     │ codelinter │ ohpm  │ hstack │ hvigor │ API │ Global │ Local │
├─────────────┼────────────┼───────┼────────┼────────┼─────┼────────┼───────┤
│ 6.0.2       │ 6.0.240    │ 6.0.1 │ 5.1.0  │ 6.22.3 │ 22  │        │ ●     │
├─────────────┼────────────┼───────┼────────┼────────┼─────┼────────┼───────┤
│ 6.1.0       │ 6.0.240    │ 6.1.1 │ 5.1.0  │ 6.23.2 │ 23  │ ●      │       │
└─────────────┴────────────┴───────┴────────┴────────┴─────┴────────┴───────┘
```

- **Global `●`**：`hmvm global` 设置的全局默认版本（新建终端自动激活）
- **Local `●`**：当前 shell 中 `hmvm use` 激活的版本

### 切换版本

```bash
hmvm use 6.1.0             # 激活指定版本（当前 shell 生效）
hmvm use default           # 激活 default 别名对应的版本
hmvm use                   # 读取当前目录 .hmvmrc 自动切换
hmvm use 6.1.0 --save      # 激活并写入 .hmvmrc（项目级固定版本）
hmvm current               # 查看当前激活的版本
```

切换后工具链版本立即生效：

```
$ hmvm use 6.0.2
Now using HarmonyOS command-line-tools v6.0.2
$ hvigorw --version
6.22.3

$ hmvm use 6.1.0
Now using HarmonyOS command-line-tools v6.1.0
$ hvigorw --version
6.23.2
```

### 设置全局默认版本（新建 shell 自动激活）

```
$ hmvm global 6.1.0
default -> v6.1.0
Now using HarmonyOS command-line-tools v6.1.0
```

设置后每次新建终端会静默激活该版本，无需手动 `hmvm use`。查看当前 global 版本：

```
$ hmvm global
v6.1.0
```

### 项目内使用 .hmvmrc

在项目根目录创建 `.hmvmrc`，写入版本号：

```
6.1.0
```

进入项目后执行 `hmvm use`（无参数）即可按 `.hmvmrc` 自动切换：

```bash
cd ~/my-harmony-project
hmvm use
# Now using HarmonyOS command-line-tools v6.1.0
```

### 卸载版本

```bash
hmvm uninstall 6.0.2
```

> 符号链接安装的版本：只删除链接，原始 command-line-tools 目录不受影响。

### 完整命令列表

| 命令 | 说明 |
|------|------|
| `hmvm -V` / `hmvm --version` | 显示 hmvm 版本号 |
| `hmvm install <version> --from <path>` | 从本地路径复制安装 |
| `hmvm install <version> --from <path> --link` | 从本地路径符号链接安装（零拷贝） |
| `hmvm global [<version>]` | 设置或查看全局默认版本（新建 shell 自动激活） |
| `hmvm use [<version>] [--save]` | 切换版本（当前 shell 生效，无参数读取 .hmvmrc） |
| `hmvm list` / `hmvm ls` | 列出已安装版本（表格形式） |
| `hmvm current` | 显示当前激活版本 |
| `hmvm uninstall <version>` | 卸载版本 |
| `hmvm alias <name> [<version>]` | 设置 / 查看 / 删除别名 |
| `hmvm which [command]` | 显示命令路径（默认 ohpm） |
| `hmvm ls-remote` | 列出可用远程版本（需配置 versions.json） |

## 目录结构

**macOS / Linux** 默认路径 `~/.hmvm`，**Windows** 默认路径 `$HOME\.hmvm`：

```
$HMVM_DIR/
├── hmvm.sh                       # macOS/Linux 主脚本（source 到 shell profile）
├── hmvm.ps1                      # Windows 主脚本（dot-source 到 $PROFILE）
├── install.sh                    # macOS/Linux 安装脚本
├── install.ps1                   # Windows 安装脚本
├── bash_completion               # macOS/Linux 自动补全
├── versions.json                 # 远程版本配置（可选）
├── versions/
│   └── clt/                      # command-line-tools 版本目录
│       ├── v6.1.0/               # 完整复制安装的版本
│       ├── v6.0.2 -> /path/...   # 符号链接安装的版本（macOS/Linux）
│       ├── v6.0.2                # NTFS Junction 安装的版本（Windows）
│       └── .meta_v6.0.2.txt      # 符号链接/Junction 版本的旁路元数据（自动生成）
└── alias/                        # 版本别名
    └── default                   # 默认版本
```

## 环境变量

| 变量 | 说明 |
|------|------|
| `HMVM_DIR` | hmvm 安装目录，默认 `~/.hmvm` |
| `HMVM_CURRENT` | 当前激活的版本号（由 `hmvm use` 写入） |
| `DEVECO_NODE_HOME` | 当前版本的 `tool/node` 路径 |
| `NODE_HOME` | 同 `DEVECO_NODE_HOME`，供 `hvigor/bin/hvigorw` 识别 |
| `DEVECO_SDK_HOME` | 当前版本的 `sdk` 路径 |
| `HDC_SDK_PATH` | HDC 调试工具链路径（`sdk/default/openharmony/toolchains`） |
| `HMVM_BIN` | 当前版本的 `bin` 目录路径 |

## 迁移现有配置

若已在 `~/.zshrc` 中手动配置 command-line-tools 路径：

```bash
# 旧配置
export PATH=~/command-line-tools/bin:$PATH
export DEVECO_NODE_HOME=~/command-line-tools/tool/node
```

可替换为 hmvm 管理（install.sh 安装后自动添加 source 指令）：

```bash
# 用 --link 导入，无需复制文件
hmvm install 6.1.0 --from ~/command-line-tools --link
hmvm global 6.1.0   # 设置全局默认版本，新建 shell 自动激活
```

## 技术说明

- **macOS / Linux**：纯 Shell 实现，POSIX 兼容，支持 bash、zsh
- **Windows**：PowerShell 5.1+ 实现，与 Shell 版功能对齐；`--link` 使用 NTFS Junction（无需管理员权限）
- PATH 管理逻辑参考 nvm；版本表格展示参考 fvm
- 符号链接 / Junction 版本通过旁路元数据文件（`.meta_v*.txt`）存储版本信息，`hmvm list` 懒加载生成
- `hmvm use` 写入 `$HMVM_CURRENT` 环境变量，`hmvm current` 直接读取，避免路径推断失效问题

## TODO

- [ ] 在线下载安装（华为账号登录鉴权，后续计划支持）

## License

MIT
