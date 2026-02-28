# HarmonyOS Version Manager (hmvm) Windows Installation Script
# 用法：
#   一键安装：irm https://raw.githubusercontent.com/SummerKaze/hmvm/main/install.ps1 | iex
#   本地安装：git clone https://github.com/SummerKaze/hmvm.git $HOME\.hmvm
#             . "$HOME\.hmvm\install.ps1"

#Requires -Version 5.1

function hmvm_echo   { param([string]$Msg) Write-Host $Msg }
function hmvm_err    { param([string]$Msg) Write-Host $Msg -ForegroundColor Red }
function hmvm_warn   { param([string]$Msg) Write-Host $Msg -ForegroundColor Yellow }
function hmvm_success{ param([string]$Msg) Write-Host $Msg -ForegroundColor Green }

# =============================================================================
# 确定安装目录
# =============================================================================

function hmvm_default_install_dir {
    return Join-Path $HOME ".hmvm"
}

function hmvm_get_install_dir {
    if ($env:HMVM_DIR -and (Test-Path $env:HMVM_DIR)) {
        return $env:HMVM_DIR
    }
    if ($env:HMVM_DIR -and -not (Test-Path $env:HMVM_DIR)) {
        hmvm_err "=> You have `$env:HMVM_DIR set to '$env:HMVM_DIR', but that directory does not exist."
        exit 1
    }
    return hmvm_default_install_dir
}

# =============================================================================
# 检测 PowerShell profile 路径
# =============================================================================

function hmvm_detect_profile {
    # 优先 CurrentUserCurrentHost，其次 CurrentUserAllHosts
    if ($PROFILE.CurrentUserCurrentHost) { return $PROFILE.CurrentUserCurrentHost }
    if ($PROFILE.CurrentUserAllHosts)    { return $PROFILE.CurrentUserAllHosts }
    return $PROFILE
}

# =============================================================================
# 主安装逻辑
# =============================================================================

function hmvm_do_install {

    $installDir = hmvm_get_install_dir
    $hmvmRepo   = if ($env:HMVM_INSTALL_GITHUB_REPO) { $env:HMVM_INSTALL_GITHUB_REPO } else { "SummerKaze/hmvm" }
    $rawBase    = "https://raw.githubusercontent.com/$hmvmRepo/main"

    # ------------------------------------------------------------------
    # 检测是否从本地已有仓库运行（当前目录包含 hmvm.ps1）
    # ------------------------------------------------------------------
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path 2>$null
    if (-not $scriptDir) {
        $scriptDir = $PSScriptRoot
    }

    if ($scriptDir -and (Test-Path (Join-Path $scriptDir "hmvm.ps1")) -and
        $scriptDir -ne (hmvm_default_install_dir)) {
        if (-not $env:HMVM_DIR) {
            hmvm_echo "=> Installing from local directory: $scriptDir"
            $installDir    = $scriptDir
            $env:HMVM_DIR  = $installDir
        }
    }

    # ------------------------------------------------------------------
    # 安装 hmvm 文件
    # ------------------------------------------------------------------
    if (Test-Path (Join-Path $installDir "hmvm.ps1")) {
        hmvm_echo "=> hmvm is already installed in $installDir"
    } elseif (Test-Path (Join-Path $installDir ".git")) {
        hmvm_echo "=> hmvm is already installed in $installDir, trying to update using git"
        try {
            Push-Location $installDir
            git fetch origin 2>$null
            git pull origin main 2>$null
            hmvm_success "=> hmvm has been updated"
        } catch {
            hmvm_warn "=> Failed to update hmvm. Run 'cd $installDir; git pull' manually."
        } finally {
            Pop-Location
        }
    } else {
        hmvm_echo "=> Downloading hmvm to $installDir"

        # 优先使用 git clone
        if (Get-Command git -ErrorAction SilentlyContinue) {
            try {
                git clone "https://github.com/$hmvmRepo.git" $installDir 2>$null
                if ($LASTEXITCODE -ne 0) { throw "git clone failed" }
                hmvm_success "=> Cloned hmvm repository"
            } catch {
                hmvm_err "=> git clone failed. Falling back to direct download..."
                hmvm_download_files $installDir $rawBase
            }
        } else {
            hmvm_download_files $installDir $rawBase
        }
    }

    # ------------------------------------------------------------------
    # 写入 PowerShell profile
    # ------------------------------------------------------------------
    hmvm_echo ""
    $profilePath = hmvm_detect_profile

    # 将安装目录替换为 $HOME 相对路径（方便跨机器）
    $profileInstallDir = $installDir -replace [regex]::Escape($HOME), '$HOME'
    $profileInstallDir = $profileInstallDir -replace '\\', '\'  # normalize

    $sourceLines = @(
        "",
        "# hmvm - HarmonyOS Version Manager",
        "`$env:HMVM_DIR = `"$profileInstallDir`"",
        ". `"`$env:HMVM_DIR\hmvm.ps1`"  # This loads hmvm",
        ""
    )
    $sourceStr = $sourceLines -join "`n"

    if (-not $profilePath) {
        hmvm_warn "=> PowerShell profile not found."
        hmvm_echo "=> Append the following lines to your `$PROFILE manually:"
        hmvm_echo $sourceStr
    } else {
        # 确保 profile 目录存在
        $profileDir = Split-Path $profilePath -Parent
        if (-not (Test-Path $profileDir)) {
            New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
        }

        # 检查是否已写入
        $alreadyAdded = $false
        if (Test-Path $profilePath) {
            $existing = Get-Content $profilePath -Raw -ErrorAction SilentlyContinue
            if ($existing -and $existing -match 'hmvm\.ps1') { $alreadyAdded = $true }
        }

        if ($alreadyAdded) {
            hmvm_echo "=> hmvm source string already in $profilePath"
        } else {
            hmvm_echo "=> Appending hmvm source string to $profilePath"
            Add-Content -Path $profilePath -Value $sourceStr -Encoding UTF8
        }
    }

    # ------------------------------------------------------------------
    # 完成提示
    # ------------------------------------------------------------------
    hmvm_echo ""
    hmvm_success "=> hmvm installation complete!"
    hmvm_echo ""
    hmvm_echo "=> Close and reopen your terminal to start using hmvm, or run:"
    hmvm_echo "      . `$PROFILE"
    hmvm_echo ""
    hmvm_echo "=> To install HarmonyOS command-line-tools from your existing installation:"
    hmvm_echo "      hmvm install 6.1.0 --from C:\path\to\command-line-tools"
    hmvm_echo "      hmvm global 6.1.0"
    hmvm_echo ""
}

function hmvm_download_files {
    param([string]$InstallDir, [string]$RawBase)

    if (-not (Test-Path $InstallDir)) {
        New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    }

    $files = @("hmvm.ps1", "hmvm.sh", "install.sh", "bash_completion", "versions.json")

    foreach ($file in $files) {
        $url  = "$RawBase/$file"
        $dest = Join-Path $InstallDir $file
        try {
            Invoke-WebRequest -Uri $url -OutFile $dest -ErrorAction Stop
            hmvm_echo "   Downloaded $file"
        } catch {
            if ($file -in @("hmvm.ps1", "hmvm.sh")) {
                hmvm_err "=> Failed to download $file from $url"
                exit 1
            }
            # 非关键文件下载失败忽略
        }
    }
}

hmvm_do_install
