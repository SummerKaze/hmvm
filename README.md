# hmvm - HarmonyOS Version Manager

基于 [nvm](https://github.com/nvm-sh/nvm) 架构魔改的鸿蒙开发环境版本管理工具，用于管理 HarmonyOS command-line-tools 多版本切换。

## 功能特性

- **多版本管理**：安装、切换、卸载不同版本的 HarmonyOS command-line-tools
- **本地导入**：从现有 command-line-tools 目录导入（`--from`）
- **环境变量**：自动设置 `DEVECO_NODE_HOME`、`DEVECO_SDK_HOME`、`PATH`
- **项目配置**：支持 `.hmvmrc` 指定项目所需版本
- **别名**：支持 `default`、`stable` 等别名

## 安装

### 从本地仓库安装

```bash
cd /path/to/hmvm
./install.sh
```

安装脚本会检测当前目录下的 `hmvm.sh`，并配置到 `~/.hmvm`（或 `$HMVM_DIR`）。

### 从 GitHub 安装（需先发布到 GitHub）

```bash
curl -o- https://raw.githubusercontent.com/hmvm/hmvm/main/install.sh | bash
# 或
wget -qO- https://raw.githubusercontent.com/hmvm/hmvm/main/install.sh | bash
```

## 使用

### 从现有环境导入

若你已有鸿蒙 command-line-tools（如 DevEco Studio 自带的），可导入到 hmvm 管理：

```bash
hmvm install 6.1.0.609 --from /Users/h1007/command-line-tools
# 使用 --link 可创建符号链接，安装更快（不复制文件）
hmvm install 6.1.0.609 --from /Users/h1007/command-line-tools --link
```

### 切换版本

```bash
hmvm use 6.1.0.609
hmvm use default
```

### 项目内使用 .hmvmrc

在项目根目录创建 `.hmvmrc`，写入版本号：

```
6.1.0.609
```

进入项目后执行 `hmvm use`（无参数）即可自动切换。

也可在切换时保存到 `.hmvmrc`：

```bash
hmvm use 6.1.0.609 --save
```

### 常用命令

| 命令 | 说明 |
|------|------|
| `hmvm install <version> --from <path> [--link]` | 从本地路径安装（--link 为符号链接） |
| `hmvm use [<version>] [--save]` | 切换版本（或读取 .hmvmrc） |
| `hmvm ls` | 列出已安装版本 |
| `hmvm ls-remote` | 列出可安装版本（需配置 versions.json） |
| `hmvm current` | 显示当前版本 |
| `hmvm uninstall <version>` | 卸载版本 |
| `hmvm alias <name> [<version>]` | 设置/查看别名 |
| `hmvm which [command]` | 显示命令路径（默认 ohpm） |

## 目录结构

```
$HMVM_DIR/                    # 默认 ~/.hmvm
├── hmvm.sh                   # 主脚本
├── install.sh                # 安装脚本
├── bash_completion           # 自动补全
├── versions.json             # 远程版本配置（可选）
├── versions/
│   └── clt/                  # command-line-tools
│       ├── v6.1.0.609/
│       └── v6.0.0.xxx/
└── alias/                    # 版本别名
```

## 环境变量

- `HMVM_DIR`：hmvm 安装目录，默认 `~/.hmvm`
- `DEVECO_NODE_HOME`：由 `hmvm use` 设置，指向当前版本的 `tool/node`
- `DEVECO_SDK_HOME`：由 `hmvm use` 设置，指向当前版本的 `sdk`

## 迁移现有配置

若你已在 `~/.zshrc` 中配置：

```bash
export PATH=~/command-line-tools/bin:$PATH
```

可改为：

```bash
# 由 install.sh 自动添加
export HMVM_DIR="$HOME/.hmvm"
[ -s "$HMVM_DIR/hmvm.sh" ] && . "$HMVM_DIR/hmvm.sh"
```

然后执行：

```bash
hmvm install 6.1.0.609 --from ~/command-line-tools
hmvm use 6.1.0.609
hmvm alias default 6.1.0.609
```

## 技术说明

- 纯 Shell 实现，POSIX 兼容，支持 bash、zsh
- 参考 nvm 的 PATH 管理逻辑
- 鸿蒙 command-line-tools 依赖 `DEVECO_NODE_HOME`、`DEVECO_SDK_HOME`，hmvm 在 `use` 时自动设置

## License

MIT
