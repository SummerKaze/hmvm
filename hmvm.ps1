# HarmonyOS Version Manager (hmvm) for Windows
# PowerShell 5.1+ compatible, no admin rights required
# 使用方式：在 PowerShell profile 中 dot-source 此文件
#
# In your $PROFILE add:
#   $env:HMVM_DIR = "$HOME\.hmvm"
#   . "$env:HMVM_DIR\hmvm.ps1"  # This loads hmvm

$script:HMVM_VERSION = "1.2.1"

# =============================================================================
# 路径/目录辅助函数
# =============================================================================

function hmvm_install_dir {
    if ($env:HMVM_DIR) { return $env:HMVM_DIR }
    return Join-Path $HOME ".hmvm"
}

function hmvm_version_dir {
    return Join-Path (hmvm_install_dir) "versions\clt"
}

function hmvm_version_path {
    param([string]$Version)
    if ($Version -notmatch '^v') { $Version = "v$Version" }
    return Join-Path (hmvm_version_dir) $Version
}

function hmvm_ensure_version_prefix {
    param([string]$Version)
    if (-not $Version) { return $Version }
    if ($Version -notmatch '^v') { return "v$Version" }
    return $Version
}

function hmvm_alias_path {
    return Join-Path (hmvm_install_dir) "alias"
}

# =============================================================================
# 别名函数
# =============================================================================

function hmvm_resolve_alias {
    param([string]$AliasName)
    if (-not $AliasName) { return $null }
    $aliasFile = Join-Path (hmvm_alias_path) $AliasName
    if (Test-Path $aliasFile -PathType Leaf) {
        return (Get-Content $aliasFile -Raw -ErrorAction SilentlyContinue).Trim()
    }
    return $null
}

# =============================================================================
# 版本检测函数
# =============================================================================

function hmvm_is_version_installed {
    param([string]$Version)
    if (-not $Version) { return $false }
    $vpath = hmvm_version_path $Version
    # Junction (ReparsePoint) 或普通目录均视为已安装
    return (Test-Path $vpath -PathType Container)
}

function hmvm_ls_current {
    # 快速路径：hmvm use 已设置环境变量
    if ($env:HMVM_CURRENT) { return $env:HMVM_CURRENT }
    # 回退：从 PATH 中推断
    $hmvmDir = hmvm_install_dir
    foreach ($p in ($env:PATH -split ';')) {
        $prefix = "$hmvmDir\versions\clt\"
        if ($p.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            $relative = $p.Substring($prefix.Length)
            $ver = ($relative -split '[\\\/]') | Select-Object -First 1
            if ($ver) { return $ver }
        }
    }
    return "none"
}

function hmvm_resolve_version {
    param([string]$Provided)
    if (-not $Provided) { return hmvm_ls_current }
    if ($Provided -eq "current") { return hmvm_ls_current }
    $resolved = hmvm_resolve_alias $Provided
    if ($resolved) { return hmvm_ensure_version_prefix $resolved }
    return hmvm_ensure_version_prefix $Provided
}

# =============================================================================
# PATH 管理（替换旧版本路径，避免多次切换后路径堆积）
# =============================================================================

function hmvm_strip_hmvm_paths {
    param([string]$PathStr)
    $hmvmDir = hmvm_install_dir
    $prefix  = "$hmvmDir\versions\"
    return ($PathStr -split ';') | Where-Object {
        $_ -ne '' -and
        -not $_.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)
    }
}

# =============================================================================
# 旁路元数据（Junction 安装版本的版本信息）
# =============================================================================

function hmvm_junction_meta_path {
    param([string]$VerName)
    return Join-Path (hmvm_version_dir) ".meta_$VerName.txt"
}

function hmvm_detect_and_save_meta {
    param([string]$VerName, [string]$Vpath)
    $cl = "-"; $ohpm = "-"; $hs = "-"; $hv = "-"; $api = "-"

    # 优先从 version.txt 读取
    $vtxt = Join-Path $Vpath "version.txt"
    if (Test-Path $vtxt) {
        $lines = Get-Content $vtxt -ErrorAction SilentlyContinue
        foreach ($line in $lines) {
            if ($line -match '^codelinter\s*:\s*(.+)$') { $cl   = $Matches[1].Trim() }
            if ($line -match '^ohpm\s*:\s*(.+)$')       { $ohpm = $Matches[1].Trim() }
            if ($line -match '^hstack\s*:\s*(.+)$')     { $hs   = $Matches[1].Trim() }
            if ($line -match '^hvigor\s*:\s*(.+)$')     { $hv   = $Matches[1].Trim() }
            if ($line -match '^apiVersion\s*:\s*(.+)$') { $api  = $Matches[1].Trim() }
        }
    }

    # 从 hvigor\package.json 补充 hvigor 版本
    if ($hv -eq "-") {
        $pkg = Join-Path $Vpath "hvigor\package.json"
        if (Test-Path $pkg) {
            $j = Get-Content $pkg -Raw -ErrorAction SilentlyContinue
            if ($j -match '"version"\s*:\s*"([^"]+)"') { $hv = $Matches[1] }
        }
    }

    # 从 ohpm\package.json 补充 ohpm 版本
    if ($ohpm -eq "-") {
        $pkg = Join-Path $Vpath "ohpm\package.json"
        if (Test-Path $pkg) {
            $j = Get-Content $pkg -Raw -ErrorAction SilentlyContinue
            if ($j -match '"version"\s*:\s*"([^"]+)"') { $ohpm = $Matches[1] }
        }
    }

    # 从 SDK 目录结构推断 API 版本（取最大数字子目录）
    if ($api -eq "-") {
        foreach ($sdkBase in @("$Vpath\sdk\default\openharmony", "$Vpath\sdk\openharmony", "$Vpath\sdk")) {
            if (Test-Path $sdkBase) {
                $nums = Get-ChildItem $sdkBase -Directory -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -match '^\d+$' } |
                    Sort-Object { [int]$_.Name }
                if ($nums) { $api = ($nums | Select-Object -Last 1).Name; break }
            }
        }
    }

    # 写入标准化元数据
    $metaFile = hmvm_junction_meta_path $VerName
    $content  = "codelinter   : $cl`nohpm         : $ohpm`nhstack       : $hs`nhvigor       : $hv`napiVersion   : $api`n"
    [System.IO.File]::WriteAllText($metaFile, $content) | Out-Null
}

function hmvm_parse_version_field {
    param([string]$Vpath, [string]$Field)
    $versionFile = Join-Path $Vpath "version.txt"

    # Junction 安装的版本：使用旁路元数据文件
    $item = Get-Item $Vpath -Force -ErrorAction SilentlyContinue
    if ($item -and $item.LinkType -eq 'Junction') {
        $metaFile = hmvm_junction_meta_path (Split-Path $Vpath -Leaf)
        # 元数据不存在时懒加载生成
        if (-not (Test-Path $metaFile)) {
            hmvm_detect_and_save_meta (Split-Path $Vpath -Leaf) $Vpath
        }
        if (Test-Path $metaFile) { $versionFile = $metaFile }
    }

    if (-not (Test-Path $versionFile)) { return "-" }

    $lines = Get-Content $versionFile -ErrorAction SilentlyContinue
    foreach ($line in $lines) {
        if ($line -match "^$Field\s*:\s*(.+)$") { return $Matches[1].Trim() }
    }
    return "-"
}

# =============================================================================
# 列出已安装版本（fvm 风格 Unicode 表格）
# 列: Version | codelinter | ohpm | hstack | hvigor | API | Global | Local
# =============================================================================

function hmvm_ls {
    $versionDir = hmvm_version_dir
    if (-not (Test-Path $versionDir)) { return }

    $versions = Get-ChildItem $versionDir -Directory -ErrorAction SilentlyContinue |
        Sort-Object Name | Select-Object -ExpandProperty Name
    if (-not $versions) { return }

    # 计算目录大小
    try {
        $bytes = (Get-ChildItem $versionDir -Recurse -File -ErrorAction SilentlyContinue |
            Measure-Object -Property Length -Sum).Sum
        $sizeStr = if ($bytes -ge 1GB)     { "{0:F1} GB" -f ($bytes / 1GB) }
                   elseif ($bytes -ge 1MB) { "{0:F0} MB" -f ($bytes / 1MB) }
                   else                    { "{0:F0} KB" -f ($bytes / 1KB) }
    } catch { $sizeStr = "?" }

    # Global: 读取 default 别名文件（不随 hmvm use 变化）
    $globalVersion = ""
    $defAlias = hmvm_resolve_alias "default"
    if ($defAlias) { $globalVersion = hmvm_ensure_version_prefix $defAlias }

    # Local: 当前 shell 激活的版本（随 hmvm use 变化）
    $current = hmvm_ls_current

    Write-Host "Cache directory:  $versionDir"
    Write-Host "Directory Size: $sizeStr"
    Write-Host ""

    $hdr = "┌─────────────┬────────────┬───────┬────────┬────────┬─────┬────────┬───────┐"
    $mid = "├─────────────┼────────────┼───────┼────────┼────────┼─────┼────────┼───────┤"
    $bot = "└─────────────┴────────────┴───────┴────────┴────────┴─────┴────────┴───────┘"

    Write-Host $hdr
    Write-Host ("│ {0,-11} │ {1,-10} │ {2,-5} │ {3,-6} │ {4,-6} │ {5,-3} │ {6,-6} │ {7,-5} │" -f
        "Version", "codelinter", "ohpm", "hstack", "hvigor", "API", "Global", "Local")
    Write-Host $mid

    $first = $true
    foreach ($ver in $versions) {
        if (-not $first) { Write-Host $mid }
        $first = $false

        $verStr = $ver -replace '^v', ''
        $vpath  = Join-Path $versionDir $ver
        $cl     = hmvm_parse_version_field $vpath "codelinter"
        $ohpm   = hmvm_parse_version_field $vpath "ohpm"
        $hs     = hmvm_parse_version_field $vpath "hstack"
        $hv     = hmvm_parse_version_field $vpath "hvigor"
        $api    = hmvm_parse_version_field $vpath "apiVersion"

        $gmark = if ($globalVersion -and ($globalVersion -eq $ver -or $globalVersion -eq $verStr)) { "●" } else { "" }
        $lmark = if ($current -eq $ver -or $current -eq $verStr) { "●" } else { "" }

        Write-Host ("│ {0,-11} │ {1,-10} │ {2,-5} │ {3,-6} │ {4,-6} │ {5,-3} │ {6,-6} │ {7,-5} │" -f
            $verStr, $cl, $ohpm, $hs, $hv, $api, $gmark, $lmark)
    }
    Write-Host $bot
}

# =============================================================================
# 切换版本
# =============================================================================

function hmvm_use {
    param([string]$Version)

    $Version = hmvm_resolve_version $Version
    if (-not $Version -or $Version -eq "none" -or $Version -eq "N/A") {
        Write-Error "hmvm: version not found."
        return
    }

    if (-not (hmvm_is_version_installed $Version)) {
        Write-Error "hmvm: version '$Version' is not installed."
        Write-Error "Run 'hmvm install $Version --from <path>' to install it."
        return
    }

    $vpath = hmvm_version_path $Version

    # 移除旧版本路径，避免多次切换后 PATH 堆积
    $cleanParts = @(hmvm_strip_hmvm_paths $env:PATH)
    $prepend    = [System.Collections.Generic.List[string]]::new()

    # 1. 主 bin 目录（ohpm.cmd / hvigorw.cmd / codelinter.cmd 等）
    if (Test-Path "$vpath\bin") { $prepend.Add("$vpath\bin") }

    # 2. Node.js 运行时（Windows 下 node.exe 直接在 tool\node\，无 bin 子目录）
    if (Test-Path "$vpath\tool\node") { $prepend.Add("$vpath\tool\node") }

    # 3. HDC 调试工具
    $hdc = "$vpath\sdk\default\openharmony\toolchains"
    if (Test-Path $hdc) {
        $prepend.Add($hdc)
        $env:HDC_SDK_PATH = $hdc
    }

    $allParts    = ($prepend + $cleanParts) | Where-Object { $_ -ne '' }
    $env:PATH             = $allParts -join ';'
    $env:DEVECO_NODE_HOME = "$vpath\tool\node"
    $env:NODE_HOME        = "$vpath\tool\node"
    $env:DEVECO_SDK_HOME  = "$vpath\sdk"
    $env:HMVM_BIN         = "$vpath\bin"
    $env:HMVM_CURRENT     = $Version

    Write-Host "Now using HarmonyOS command-line-tools $Version"
}

# =============================================================================
# 安装版本
# =============================================================================

function hmvm_install_from_path {
    param([string]$Version, [string]$FromPath, [bool]$UseJunction = $false)

    if (-not $Version -or -not $FromPath) {
        Write-Error "hmvm install: version and --from path are required."
        return
    }

    $Version = hmvm_ensure_version_prefix $Version

    if (-not (Test-Path $FromPath)) {
        Write-Error "hmvm: path '$FromPath' does not exist."
        return
    }

    $valid = (Test-Path (Join-Path $FromPath "version.txt")) -or
             (Test-Path (Join-Path $FromPath "bin\ohpm.cmd")) -or
             (Test-Path (Join-Path $FromPath "bin\ohpm"))
    if (-not $valid) {
        Write-Error "hmvm: path '$FromPath' does not appear to be a valid command-line-tools directory."
        return
    }

    if (hmvm_is_version_installed $Version) {
        Write-Host "$Version is already installed."
        hmvm_use $Version
        return
    }

    $vdir = hmvm_version_dir
    if (-not (Test-Path $vdir)) { New-Item -ItemType Directory -Path $vdir -Force | Out-Null }

    $vpath   = hmvm_version_path $Version
    $absFrom = (Resolve-Path $FromPath).Path

    if ($UseJunction) {
        Write-Host "Linking HarmonyOS command-line-tools $Version from $absFrom..."
        try {
            # 优先使用 New-Item (PS 5.1+)，失败则回退到 cmd mklink /j
            try {
                New-Item -ItemType Junction -Path $vpath -Target $absFrom -ErrorAction Stop | Out-Null
            } catch {
                # 回退：cmd /c mklink /j（无需 Developer Mode，仅需同一卷）
                cmd /c mklink /j "`"$vpath`"" "`"$absFrom`"" | Out-Null
                if ($LASTEXITCODE -ne 0) { throw "mklink /j failed" }
            }
            # 生成旁路元数据，保证 hmvm list 能显示版本信息
            hmvm_detect_and_save_meta $Version $vpath
            Write-Host "Linked HarmonyOS command-line-tools $Version successfully."
            hmvm_use $Version
        } catch {
            Write-Error "Failed to link '$absFrom' -> '$vpath': $_"
            if (Test-Path $vpath) {
                $item = Get-Item $vpath -Force -ErrorAction SilentlyContinue
                if ($item -and $item.LinkType -eq 'Junction') { $item.Delete() }
                else { Remove-Item $vpath -Force -ErrorAction SilentlyContinue }
            }
        }
    } else {
        Write-Host "Installing HarmonyOS command-line-tools $Version from $absFrom..."
        try {
            Copy-Item -Recurse -Path $absFrom -Destination $vpath -ErrorAction Stop
            Write-Host "Installed HarmonyOS command-line-tools $Version successfully."
            hmvm_use $Version
        } catch {
            Write-Error "Failed to copy '$absFrom' -> '$vpath': $_"
            if (Test-Path $vpath) { Remove-Item $vpath -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }
}

# =============================================================================
# 卸载版本
# =============================================================================

function hmvm_uninstall {
    param([string]$Version)
    $Version = hmvm_ensure_version_prefix $Version

    if (-not (hmvm_is_version_installed $Version)) {
        Write-Error "hmvm: version '$Version' is not installed."
        return
    }

    $current = hmvm_ls_current
    if ($current -eq $Version -or $current -eq ($Version -replace '^v', '')) {
        Write-Error "hmvm: Cannot uninstall currently-active version, $Version."
        Write-Error "Run 'hmvm use <other-version>' first."
        return
    }

    $vpath = hmvm_version_path $Version
    Write-Host "Uninstalling HarmonyOS command-line-tools $Version..."

    $item = Get-Item $vpath -Force -ErrorAction SilentlyContinue
    if ($item -and $item.LinkType -eq 'Junction') {
        # Junction：只删除链接本身，不影响目标目录
        $item.Delete()
    } else {
        Remove-Item $vpath -Recurse -Force -ErrorAction Stop
    }

    # 清理旁路元数据文件
    $metaFile = hmvm_junction_meta_path $Version
    if (Test-Path $metaFile) { Remove-Item $metaFile -Force -ErrorAction SilentlyContinue }

    Write-Host "Uninstalled $Version."
}

# =============================================================================
# 别名管理
# =============================================================================

function hmvm_alias_cmd {
    param([string]$AliasName, [string]$Target)
    $aliasDir = hmvm_alias_path
    if (-not (Test-Path $aliasDir)) { New-Item -ItemType Directory -Path $aliasDir -Force | Out-Null }

    if (-not $Target) {
        if (-not $AliasName) {
            # 列出所有别名
            Get-ChildItem $aliasDir -File -ErrorAction SilentlyContinue | ForEach-Object {
                $v = (Get-Content $_.FullName -Raw -ErrorAction SilentlyContinue).Trim()
                Write-Host "$($_.Name) -> $v"
            }
            return
        }
        # 删除别名
        $aliasFile = Join-Path $aliasDir $AliasName
        if (Test-Path $aliasFile) {
            Remove-Item $aliasFile -Force
            Write-Host "Deleted alias $AliasName"
        } else {
            Write-Error "Alias $AliasName does not exist."
        }
        return
    }

    $resolved = hmvm_resolve_version $Target
    if (-not (hmvm_is_version_installed $resolved)) {
        Write-Error "hmvm: version '$Target' is not installed."
        return
    }
    $resolved = hmvm_ensure_version_prefix $resolved
    [System.IO.File]::WriteAllText((Join-Path $aliasDir $AliasName), $resolved)
    Write-Host "$AliasName -> $resolved"
}

# =============================================================================
# .hmvmrc 查找
# =============================================================================

function hmvm_find_hmvmrc {
    $dir  = (Get-Location).Path
    $prev = $null
    while ($dir -and $dir -ne $prev) {
        $rc = Join-Path $dir ".hmvmrc"
        if (Test-Path $rc -PathType Leaf) { return $rc }
        $prev = $dir
        $dir  = Split-Path $dir -Parent
    }
    return $null
}

# =============================================================================
# 远程版本列表
# =============================================================================

function hmvm_ls_remote {
    $versionsJson = Join-Path (hmvm_install_dir) "versions.json"
    if (Test-Path $versionsJson) {
        try {
            $data = Get-Content $versionsJson -Raw | ConvertFrom-Json
            $vers = $data.windows | ForEach-Object { $_.version } |
                Where-Object { $_ } | Sort-Object -Descending
            if ($vers) { $vers | ForEach-Object { Write-Host $_ }; return }
        } catch {}
    }
    Write-Host "No remote versions configured. Use 'hmvm install <version> --from <path>' to install from local."
}

# =============================================================================
# which 命令
# =============================================================================

function hmvm_which_cmd {
    param([string]$Cmd = "ohpm")
    $found = Get-Command $Cmd -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
    if ($found) { Write-Host $found }
    else { Write-Error "hmvm: $Cmd not found in PATH" }
}

# =============================================================================
# 帮助信息
# =============================================================================

function hmvm_print_help {
    Write-Host "HarmonyOS Version Manager (hmvm) for Windows"
    Write-Host ""
    Write-Host "Usage:"
    Write-Host "  hmvm install <version> --from <path> [--link]  Install from local path"
    Write-Host "  hmvm global [<version>]               Set/show global default version"
    Write-Host "  hmvm use [<version>] [--save]         Switch to version (or read .hmvmrc)"
    Write-Host "  hmvm ls [list]                        List installed versions"
    Write-Host "  hmvm ls-remote                        List available versions"
    Write-Host "  hmvm current                          Show current version"
    Write-Host "  hmvm uninstall <version>              Uninstall version"
    Write-Host "  hmvm alias <name> [<version>]         Set/remove alias"
    Write-Host "  hmvm which [command]                  Show path to command (default: ohpm)"
    Write-Host ""
    Write-Host "Notes:"
    Write-Host "  --link creates an NTFS Junction (no admin rights required)"
    Write-Host "  Default install dir: `$HOME\.hmvm"
    Write-Host "  Override with: `$env:HMVM_DIR = 'D:\hmvm'"
    Write-Host ""
}

# =============================================================================
# 主入口
# 使用 $args 而非 param() 以避免 PowerShell 将 --from / --link 误作具名参数
# =============================================================================

function hmvm {
    $cmd  = if ($args.Count -gt 0) { [string]$args[0] } else { "" }
    $rest = if ($args.Count -gt 1) { @($args[1..($args.Count - 1)]) } else { @() }

    switch ($cmd) {
        { $_ -in @("-V", "--version") } {
            Write-Host $script:HMVM_VERSION
        }

        { $_ -in @("", "help") } {
            hmvm_print_help
        }

        "install" {
            $version = ""; $fromPath = ""; $useJunction = $false
            $i = 0
            while ($i -lt $rest.Count) {
                switch ($rest[$i]) {
                    "--from" { $i++; if ($i -lt $rest.Count) { $fromPath = $rest[$i] } }
                    "--link" { $useJunction = $true }
                    default  { if (-not $version) { $version = $rest[$i] } }
                }
                $i++
            }
            if ($fromPath) {
                hmvm_install_from_path $version $fromPath $useJunction
            } else {
                Write-Error "hmvm install: use 'hmvm install <version> --from <path>' to install from local."
                Write-Error "  Example: hmvm install 6.1.0 --from C:\tools\command-line-tools"
            }
        }

        "use" {
            $saveRc = $false; $useVersion = ""
            foreach ($a in $rest) {
                if ($a -in @("--save", "-w")) { $saveRc = $true }
                elseif (-not $useVersion)     { $useVersion = $a }
            }
            if (-not $useVersion) {
                $rc = hmvm_find_hmvmrc
                if ($rc) {
                    hmvm_use ((Get-Content $rc -Raw).Trim())
                    return
                }
                Write-Error "hmvm use: version is required."
                return
            }
            hmvm_use $useVersion
            if ($saveRc) {
                $resolved = hmvm_resolve_version $useVersion
                [System.IO.File]::WriteAllText((Join-Path (Get-Location) ".hmvmrc"), $resolved)
                Write-Host "Saved $resolved to .hmvmrc"
            }
        }

        "global" {
            if ($rest.Count -lt 1) {
                $g = hmvm_resolve_alias "default"
                if ($g) { Write-Host $g }
                else    { Write-Host "No global version set. Use 'hmvm global <version>' to set one." }
            } else {
                hmvm_alias_cmd "default" $rest[0]
                hmvm_use $rest[0]
            }
        }

        { $_ -in @("ls", "list") } { hmvm_ls }

        "ls-remote" { hmvm_ls_remote }

        "current" { Write-Host (hmvm_ls_current) }

        "uninstall" {
            if ($rest.Count -lt 1) { Write-Error "hmvm uninstall: version is required."; return }
            hmvm_uninstall $rest[0]
        }

        "alias" {
            $aName   = if ($rest.Count -gt 0) { $rest[0] } else { "" }
            $aTarget = if ($rest.Count -gt 1) { $rest[1] } else { "" }
            hmvm_alias_cmd $aName $aTarget
        }

        "which" {
            hmvm_which_cmd (if ($rest.Count -gt 0) { $rest[0] } else { "ohpm" })
        }

        default {
            Write-Error "hmvm: unknown command '$cmd'"
            hmvm_print_help
        }
    }
}

# =============================================================================
# source 时自动激活 global 版本（新建终端生效）
# =============================================================================

$_hmvmDefault = hmvm_resolve_alias "default"
if ($_hmvmDefault) {
    $_hmvmDefaultVer = hmvm_ensure_version_prefix $_hmvmDefault
    if (hmvm_is_version_installed $_hmvmDefaultVer) {
        hmvm_use $_hmvmDefaultVer *>$null
    }
    Remove-Variable _hmvmDefaultVer -ErrorAction SilentlyContinue
}
Remove-Variable _hmvmDefault -ErrorAction SilentlyContinue
