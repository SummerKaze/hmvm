# HarmonyOS Version Manager (hmvm)
# 基于 nvm 架构魔改，管理鸿蒙 command-line-tools 多版本
# POSIX 兼容，支持 sh, dash, bash, ksh, zsh
# 使用方式：在 shell profile 中 source 此文件
#
# shellcheck disable=SC2039,SC2016,SC2001,SC3043
{ # this ensures the entire script is downloaded #

HMVM_SCRIPT_SOURCE="$_"
HMVM_VERSION="1.2.2"

# =============================================================================
# 工具函数（移植自 nvm）
# =============================================================================

hmvm_is_zsh() {
  [ -n "${ZSH_VERSION-}" ]
}

hmvm_echo() {
  command printf %s\\n "$*" 2>/dev/null
}

hmvm_err() {
  >&2 hmvm_echo "$@"
}

hmvm_grep() {
  GREP_OPTIONS='' command grep "$@"
}

hmvm_has() {
  type "${1-}" >/dev/null 2>&1
}

hmvm_cd() {
  \cd "$@"
}

hmvm_download() {
  if hmvm_has "curl"; then
    curl -q --fail -L -sS "$@"
  elif hmvm_has "wget"; then
    wget -q --show-progress -O - "$@"
  else
    hmvm_err 'hmvm needs curl or wget to proceed.'
    return 1
  fi
}

hmvm_download_file() {
  if hmvm_has "curl"; then
    curl -q --fail -L -sS -o "$1" "$2"
  elif hmvm_has "wget"; then
    wget -q --show-progress -O "$1" "$2"
  else
    hmvm_err 'hmvm needs curl or wget to proceed.'
    return 1
  fi
}

# 获取 HMVM 安装目录
hmvm_default_install_dir() {
  [ -z "${XDG_CONFIG_HOME-}" ] && printf %s "${HOME}/.hmvm" || printf %s "${XDG_CONFIG_HOME}/hmvm"
}

hmvm_install_dir() {
  if [ -n "${HMVM_DIR-}" ]; then
    printf %s "${HMVM_DIR}"
  else
    hmvm_default_install_dir
  fi
}

# Shims 目录：存放绕过 SDK 工具链问题的包装脚本
hmvm_shims_dir() {
  printf %s "$(hmvm_install_dir)/shims"
}

# 创建 diff shim，绕过 OpenHarmony SDK toolchains 中不符合 GNU 规范的 diff。
# SDK 自带的 toolchains/diff 不支持 --version/-v 等标准参数，会导致
# autoconf/cmake 等构建工具的 configure 检测报 "illegal option" 错误。
hmvm_ensure_diff_shim() {
  local SHIMS SHIM_FILE
  SHIMS="$(hmvm_shims_dir)"
  command mkdir -p "${SHIMS}" 2>/dev/null || return 0
  SHIM_FILE="${SHIMS}/diff"
  # shim 已存在且包含标记则跳过（幂等，避免重复写入）
  if [ -x "${SHIM_FILE}" ] && command grep -q 'hmvm shim' "${SHIM_FILE}" 2>/dev/null; then
    return 0
  fi
  # 依次尝试已知系统路径，找到第一个可用的原生 diff 并转发调用
  command cat > "${SHIM_FILE}" << 'HMVM_SHIM_EOF'
#!/bin/sh
# hmvm shim: bypass OpenHarmony SDK non-GNU diff
# OpenHarmony SDK toolchains/diff 不符合 GNU 规范（不支持 --version 等参数），
# 会导致 autoconf/cmake 等构建工具的 configure 检测失败。
# 此脚本将 diff 调用路由到系统原生 diff 实现。
for _d in /opt/homebrew/bin /usr/bin /usr/local/bin /bin /usr/gnu/bin; do
  if [ -x "${_d}/diff" ]; then
    exec "${_d}/diff" "$@"
  fi
done
>&2 printf 'hmvm: cannot find system diff. Please install GNU diff (e.g. brew install diffutils).\n'
exit 1
HMVM_SHIM_EOF
  command chmod +x "${SHIM_FILE}" 2>/dev/null || true
}

# 版本目录：$HMVM_DIR/versions/clt/vX.X.X
hmvm_version_dir() {
  printf %s "$(hmvm_install_dir)/versions/clt"
}

hmvm_version_path() {
  local VERSION
  VERSION="${1-}"
  if [ -z "${VERSION}" ]; then
    hmvm_err 'hmvm_version_path: version is required'
    return 1
  fi
  # 统一添加 v 前缀
  case "${VERSION}" in
    v*) ;;
    *) VERSION="v${VERSION}" ;;
  esac
  printf %s "$(hmvm_version_dir)/${VERSION}"
}

hmvm_ensure_version_prefix() {
  local VERSION
  VERSION="${1-}"
  case "${VERSION}" in
    v*) printf %s "${VERSION}" ;;
    *) printf %s "v${VERSION}" ;;
  esac
}

# 从 PATH 中移除 hmvm 路径并添加新路径
hmvm_strip_path() {
  local PATH_VAR
  PATH_VAR="${1-}"
  local SUBPATH
  SUBPATH="${2-}"
  local HMVM_PATH
  HMVM_PATH="$(hmvm_install_dir)"

  if [ -z "${PATH_VAR}" ]; then
    return
  fi
  command printf %s "${PATH_VAR}" | command awk -v RS=: -v ORS=: -v hmvm_dir="${HMVM_PATH}" -v subpath="${SUBPATH}" '
    index($0, hmvm_dir) == 1 {
      path = substr($0, length(hmvm_dir) + 1)
      if (path ~ "^(/versions/[^/]*)?/[^/]*" subpath ".*$") { next }
    }
    { printf "%s%s", sep, $0; sep=RS }'
}

hmvm_change_path() {
  if [ -z "${1-}" ]; then
    hmvm_echo "${3-}${2-}"
  elif ! hmvm_echo "${1-}" | hmvm_grep -q "$(hmvm_install_dir)/[^/]*${2-}" \
    && ! hmvm_echo "${1-}" | hmvm_grep -q "$(hmvm_install_dir)/versions/[^/]*/[^/]*${2-}"; then
    hmvm_echo "${3-}${2-}:${1-}"
  else
    hmvm_echo "${1-}" | command sed \
      -e "s#$(hmvm_install_dir)/[^/]*${2-}[^:]*#${3-}${2-}#" \
      -e "s#$(hmvm_install_dir)/versions/[^/]*/[^/]*${2-}[^:]*#${3-}${2-}#"
  fi
}

# 检查版本是否已安装（软链接存在即视为已安装；否则检查 version.txt 或 bin/ohpm）
hmvm_is_version_installed() {
  local VERSION_PATH
  VERSION_PATH="$(hmvm_version_path "${1-}" 2>/dev/null)"
  if [ -z "${VERSION_PATH}" ]; then
    return 1
  fi
  # --link 安装的版本：符号链接存在即视为已安装
  if [ -L "${VERSION_PATH}" ]; then
    return 0
  fi
  if [ -f "${VERSION_PATH}/version.txt" ] || [ -f "${VERSION_PATH}/bin/ohpm" ]; then
    return 0
  fi
  return 1
}

# 别名路径
hmvm_alias_path() {
  printf %s "$(hmvm_install_dir)/alias"
}

# 解析别名
hmvm_resolve_alias() {
  local ALIAS
  ALIAS="${1-}"
  if [ -z "${ALIAS}" ]; then
    return 1
  fi
  local ALIAS_PATH
  ALIAS_PATH="$(hmvm_alias_path)/${ALIAS}"
  if [ -f "${ALIAS_PATH}" ]; then
    command cat "${ALIAS_PATH}"
    return 0
  fi
  return 1
}

# 解析版本号（支持别名、版本号）
hmvm_version() {
  local PROVIDED
  PROVIDED="${1-}"
  if [ -z "${PROVIDED}" ]; then
    hmvm_ls_current
    return
  fi
  case "${PROVIDED}" in
    current)
      hmvm_ls_current
      return
      ;;
  esac
  local RESOLVED
  if RESOLVED="$(hmvm_resolve_alias "${PROVIDED}" 2>/dev/null)"; then
    hmvm_echo "${RESOLVED}"
    return 0
  fi
  hmvm_echo "$(hmvm_ensure_version_prefix "${PROVIDED}")"
}

# 获取当前激活的版本
# 优先读取 hmvm use 写入的 $HMVM_CURRENT 环境变量，
# 回退到 PATH 中 ohpm 路径推断（兼容未通过 hmvm use 激活的情况）
hmvm_ls_current() {
  # 快速路径：hmvm use 已设置环境变量，直接返回
  if [ -n "${HMVM_CURRENT-}" ]; then
    hmvm_echo "${HMVM_CURRENT}"
    return 0
  fi
  # 回退：通过 PATH 中 ohpm 路径推断（可能受 CHASE_LINKS 影响，仅作兜底）
  local OHPM_PATH
  OHPM_PATH="$(command which ohpm 2>/dev/null)" || true
  if [ -z "${OHPM_PATH}" ]; then
    hmvm_echo "none"
    return
  fi
  local HMVM_PATH
  HMVM_PATH="$(hmvm_install_dir)"
  if hmvm_echo "${OHPM_PATH}" | hmvm_grep -q "${HMVM_PATH}/versions/clt/"; then
    local VERSION_DIR
    VERSION_DIR="$(hmvm_echo "${OHPM_PATH}" | command sed "s|${HMVM_PATH}/versions/clt/||" | command cut -d/ -f1)"
    hmvm_echo "${VERSION_DIR}"
    return 0
  fi
  hmvm_echo "none"
}

# 软链接版本的旁路元数据文件路径（存储在版本目录同级，不在软链接内部）
hmvm_symlink_meta_path() {
  local VER="${1-}"
  printf '%s' "$(hmvm_version_dir)/.meta_${VER}.txt"
}

# 从目录结构中推断版本信息并写入旁路元数据文件（用于软链接安装的版本）
hmvm_detect_and_save_meta() {
  local VERSION VPATH META_FILE
  VERSION="${1-}"
  VPATH="${2-}"
  META_FILE="$(hmvm_symlink_meta_path "${VERSION}")"

  local codelinter_ver ohpm_ver hstack_ver hvigor_ver api_ver _v
  codelinter_ver="-"; ohpm_ver="-"; hstack_ver="-"; hvigor_ver="-"; api_ver="-"

  # 优先从目录内的 version.txt 读取（兼容多种字段命名风格）
  if [ -f "${VPATH}/version.txt" ]; then
    _v="$(command grep -iE "^codelinter[[:space:]]*:" "${VPATH}/version.txt" 2>/dev/null \
      | command sed 's/.*:[[:space:]]*//' | command tr -d '\n\r')"
    [ -n "${_v}" ] && codelinter_ver="${_v}"

    _v="$(command grep -iE "^ohpm[[:space:]]*:" "${VPATH}/version.txt" 2>/dev/null \
      | command sed 's/.*:[[:space:]]*//' | command tr -d '\n\r')"
    [ -n "${_v}" ] && ohpm_ver="${_v}"

    _v="$(command grep -iE "^hstack[[:space:]]*:" "${VPATH}/version.txt" 2>/dev/null \
      | command sed 's/.*:[[:space:]]*//' | command tr -d '\n\r')"
    [ -n "${_v}" ] && hstack_ver="${_v}"

    _v="$(command grep -iE "^hvigor[[:space:]]*:" "${VPATH}/version.txt" 2>/dev/null \
      | command sed 's/.*:[[:space:]]*//' | command tr -d '\n\r')"
    [ -n "${_v}" ] && hvigor_ver="${_v}"

    _v="$(command grep -iE "^apiVersion[[:space:]]*:" "${VPATH}/version.txt" 2>/dev/null \
      | command sed 's/.*:[[:space:]]*//' | command tr -d '\n\r')"
    [ -n "${_v}" ] && api_ver="${_v}"
  fi

  # 从 hvigor/package.json 补充 hvigor 版本
  if [ "${hvigor_ver}" = "-" ] && [ -f "${VPATH}/hvigor/package.json" ]; then
    _v="$(command grep -oE '"version"[[:space:]]*:[[:space:]]*"[^"]*"' \
      "${VPATH}/hvigor/package.json" 2>/dev/null \
      | head -1 | command sed 's/.*:[[:space:]]*"\(.*\)"/\1/')"
    [ -n "${_v}" ] && hvigor_ver="${_v}"
  fi

  # 从 ohpm/package.json 补充 ohpm 版本
  if [ "${ohpm_ver}" = "-" ] && [ -f "${VPATH}/ohpm/package.json" ]; then
    _v="$(command grep -oE '"version"[[:space:]]*:[[:space:]]*"[^"]*"' \
      "${VPATH}/ohpm/package.json" 2>/dev/null \
      | head -1 | command sed 's/.*:[[:space:]]*"\(.*\)"/\1/')"
    [ -n "${_v}" ] && ohpm_ver="${_v}"
  fi

  # 从 SDK 目录结构推断 API 版本（取最大数字子目录）
  if [ "${api_ver}" = "-" ]; then
    local _sdk
    for _sdk in "${VPATH}/sdk/default/openharmony" "${VPATH}/sdk/openharmony" "${VPATH}/sdk"; do
      if [ -d "${_sdk}" ]; then
        _v="$(command ls -1 "${_sdk}" 2>/dev/null \
          | command grep -E '^[0-9]+$' | command sort -n | tail -1)"
        if [ -n "${_v}" ]; then api_ver="${_v}"; break; fi
      fi
    done
  fi

  # 写入标准化元数据（与 version.txt 字段格式保持一致）
  command mkdir -p "$(hmvm_version_dir)" 2>/dev/null || true
  printf 'codelinter   : %s\nohpm         : %s\nhstack       : %s\nhvigor       : %s\napiVersion   : %s\n' \
    "${codelinter_ver}" "${ohpm_ver}" "${hstack_ver}" "${hvigor_ver}" "${api_ver}" \
    > "${META_FILE}" 2>/dev/null || true
}

# 从 version.txt 中读取指定字段值，始终返回 0
# 软链接版本优先读取旁路元数据文件，缺失时懒加载生成
hmvm_parse_version_field() {
  local vpath field val version_file
  vpath="${1-}"
  field="${2-}"
  version_file="${vpath}/version.txt"

  # 软链接安装的版本：使用 hmvm 管理的旁路元数据（避免软链接目标格式不兼容）
  if [ -L "${vpath}" ]; then
    local meta_file
    meta_file="$(hmvm_symlink_meta_path "$(basename "${vpath}")")"
    # 元数据文件不存在时懒加载生成（兼容已安装的旧版本）
    if [ ! -f "${meta_file}" ]; then
      hmvm_detect_and_save_meta "$(basename "${vpath}")" "${vpath}" 2>/dev/null || true
    fi
    [ -f "${meta_file}" ] && version_file="${meta_file}"
  fi

  if [ ! -f "${version_file}" ]; then
    printf '%s' "-"
    return 0
  fi
  val="$(command grep -E "^${field}[[:space:]]*:" "${version_file}" 2>/dev/null \
    | command sed 's/.*:[[:space:]]*//' | command tr -d '\n\r')"
  if [ -n "${val}" ]; then
    printf '%s' "${val}"
  else
    printf '%s' "-"
  fi
  return 0
}

# 列出已安装版本（fvm 风格表格）
# 列: Version | codelinter | ohpm | hstack | hvigor | API | Global | Local
hmvm_ls() {
  local VERSION_DIR VERSIONS CURRENT GLOBAL_VERSION DIR_SIZE
  local HDR_SEP MID_SEP BOT_SEP
  local VER ver_str vpath FIRST
  local codelinter_ver ohpm_ver hstack_ver hvigor_ver api_ver global_mark local_mark

  VERSION_DIR="$(hmvm_version_dir)"
  if [ ! -d "${VERSION_DIR}" ]; then
    return 0
  fi

  VERSIONS="$(command ls -1 "${VERSION_DIR}" 2>/dev/null | command sort -V)"
  if [ -z "${VERSIONS}" ]; then
    return 0
  fi

  # Global: 读取 default 别名文件（持久值，不随 hmvm use 变化）
  GLOBAL_VERSION=""
  local _default_ver
  _default_ver="$(hmvm_resolve_alias "default" 2>/dev/null)" || true
  [ -n "${_default_ver}" ] && GLOBAL_VERSION="$(hmvm_ensure_version_prefix "${_default_ver}")"

  # Local: 当前 shell 激活的版本（随 hmvm use 变化）
  CURRENT="$(hmvm_ls_current)"

  DIR_SIZE=""
  if hmvm_has du; then
    DIR_SIZE="$(command du -sh "${VERSION_DIR}" 2>/dev/null | command awk '{print $1}')"
  fi

  hmvm_echo "Cache directory:  $(hmvm_install_dir)/versions/clt"
  [ -n "${DIR_SIZE}" ] && hmvm_echo "Directory Size: ${DIR_SIZE}"
  hmvm_echo ""

  # 列宽（内容宽度）: Version=11 codelinter=10 ohpm=5 hstack=6 hvigor=6 API=3 Global=6 Local=5
  # 分隔线宽 = 内容宽 + 2（两侧空格）
  HDR_SEP="┌─────────────┬────────────┬───────┬────────┬────────┬─────┬────────┬───────┐"
  MID_SEP="├─────────────┼────────────┼───────┼────────┼────────┼─────┼────────┼───────┤"
  BOT_SEP="└─────────────┴────────────┴───────┴────────┴────────┴─────┴────────┴───────┘"

  printf '%s\n' "${HDR_SEP}"
  printf '│ %-11s │ %-10s │ %-5s │ %-6s │ %-6s │ %-3s │ %-6s │ %-5s │\n' \
    "Version" "codelinter" "ohpm" "hstack" "hvigor" "API" "Global" "Local"
  printf '%s\n' "${MID_SEP}"

  FIRST=1
  while IFS= read -r VER; do
    if [ -z "${VER}" ]; then continue; fi

    if [ "${FIRST}" = "0" ]; then
      printf '%s\n' "${MID_SEP}"
    fi
    FIRST=0

    ver_str="${VER#v}"
    vpath="${VERSION_DIR}/${VER}"

    codelinter_ver="$(hmvm_parse_version_field "${vpath}" "codelinter")"
    ohpm_ver="$(hmvm_parse_version_field "${vpath}" "ohpm")"
    hstack_ver="$(hmvm_parse_version_field "${vpath}" "hstack")"
    hvigor_ver="$(hmvm_parse_version_field "${vpath}" "hvigor")"
    api_ver="$(hmvm_parse_version_field "${vpath}" "apiVersion")"

    global_mark=""
    if [ -n "${GLOBAL_VERSION}" ] && \
       ([ "${GLOBAL_VERSION}" = "${VER}" ] || [ "${GLOBAL_VERSION}" = "${ver_str}" ]); then
      global_mark="●"
    fi
    local_mark=""
    if [ "${CURRENT}" = "${VER}" ] || [ "${CURRENT}" = "${ver_str}" ]; then
      local_mark="●"
    fi

    printf '│ %-11s │ %-10s │ %-5s │ %-6s │ %-6s │ %-3s │ %-6s │ %-5s │\n' \
      "${ver_str}" "${codelinter_ver}" "${ohpm_ver}" "${hstack_ver}" "${hvigor_ver}" \
      "${api_ver}" "${global_mark}" "${local_mark}"
  done <<< "${VERSIONS}"

  printf '%s\n' "${BOT_SEP}"
}

# 切换版本
hmvm_use() {
  local VERSION
  VERSION="$(hmvm_version "${1-}")"
  if [ -z "${VERSION}" ] || [ "${VERSION}" = "none" ] || [ "${VERSION}" = "N/A" ]; then
    hmvm_err "hmvm: version '${1-}' not found."
    return 1
  fi

  if ! hmvm_is_version_installed "${VERSION}"; then
    hmvm_err "hmvm: version '${VERSION}' is not installed."
    hmvm_err "Run 'hmvm install ${VERSION} --from <path>' to install it."
    return 1
  fi

  local VERSION_PATH
  VERSION_PATH="$(hmvm_version_path "${VERSION}")"

  # --- PATH 管理：通过 hmvm_change_path 替换旧版本路径，避免多次切换后路径堆积 ---

  # 1. 主 bin 目录（ohpm / hvigorw 启动器 / codelinter / hstack 等）
  PATH="$(hmvm_change_path "${PATH}" "/bin" "${VERSION_PATH}")"

  # 2. Node.js 运行时：hvigor/bin/hvigorw 通过 NODE_HOME 或 PATH 中的 node 执行
  #    使用 hmvm_change_path 替换旧版本路径（而非直接 prepend 导致路径堆积）
  if [ -d "${VERSION_PATH}/tool/node/bin" ]; then
    PATH="$(hmvm_change_path "${PATH}" "/tool/node/bin" "${VERSION_PATH}")"
  fi

  # 3. HDC 调试工具（hdc 命令，用于连接鸿蒙真机/模拟器）
  local HDC_TOOLCHAIN="${VERSION_PATH}/sdk/default/openharmony/toolchains"
  if [ -d "${HDC_TOOLCHAIN}" ]; then
    PATH="$(hmvm_change_path "${PATH}" "/sdk/default/openharmony/toolchains" "${VERSION_PATH}")"
    export HDC_SDK_PATH="${HDC_TOOLCHAIN}"
    # macOS Launch Services 同步，使 GUI 进程（如 DevEco Studio）也能读取
    if hmvm_has launchctl; then
      launchctl setenv HDC_SDK_PATH "${HDC_SDK_PATH}" 2>/dev/null || true
    fi
  fi

  # 4. diff shim：SDK toolchains/diff 不符合 GNU 规范，会导致 autoconf/cmake 等
  #    构建工具的 configure 脚本检测失败。在 shims 目录放置包装脚本并确保其
  #    位于 toolchains 之前，使系统原生 diff 优先被调用。
  local SHIMS_DIR
  SHIMS_DIR="$(hmvm_shims_dir)"
  hmvm_ensure_diff_shim 2>/dev/null || true
  if ! hmvm_echo "${PATH}" | hmvm_grep -q "${SHIMS_DIR}"; then
    PATH="${SHIMS_DIR}:${PATH}"
  fi

  export PATH

  # --- 环境变量 ---
  export DEVECO_NODE_HOME="${VERSION_PATH}/tool/node"
  # NODE_HOME 供 hvigor/bin/hvigorw 直接识别（与 DEVECO_NODE_HOME 保持同步）
  export NODE_HOME="${VERSION_PATH}/tool/node"
  export DEVECO_SDK_HOME="${VERSION_PATH}/sdk"
  export HMVM_BIN="${VERSION_PATH}/bin"
  # 记录当前激活版本，供 hmvm current / hmvm list 直接读取，
  # 避免依赖 which ohpm 路径推断（CHASE_LINKS 等选项会跟随软链接导致误判）
  export HMVM_CURRENT="${VERSION}"

  # --- 清空命令哈希缓存，确保 shell 从新 PATH 重新查找命令 ---
  \hash -r 2>/dev/null || true
  # zsh 额外调用 rehash（hash -r 在部分 zsh 版本中不完全生效）
  if hmvm_is_zsh; then
    builtin rehash 2>/dev/null || true
  fi

  hmvm_echo "Now using HarmonyOS command-line-tools ${VERSION}"
  return 0
}

# 从本地路径安装
hmvm_install_from_path() {
  local VERSION
  VERSION="${1-}"
  local FROM_PATH
  FROM_PATH="${2-}"
  local USE_LINK
  USE_LINK="${3:-0}"

  if [ -z "${VERSION}" ] || [ -z "${FROM_PATH}" ]; then
    hmvm_err "hmvm install: version and --from path are required."
    return 1
  fi

  VERSION="$(hmvm_ensure_version_prefix "${VERSION}")"

  if [ ! -d "${FROM_PATH}" ]; then
    hmvm_err "hmvm: path '${FROM_PATH}' does not exist."
    return 1
  fi

  if [ ! -f "${FROM_PATH}/version.txt" ] && [ ! -f "${FROM_PATH}/bin/ohpm" ]; then
    hmvm_err "hmvm: path '${FROM_PATH}' does not appear to be a valid command-line-tools directory."
    return 1
  fi

  local VERSION_PATH
  VERSION_PATH="$(hmvm_version_path "${VERSION}")"

  if hmvm_is_version_installed "${VERSION}"; then
    hmvm_err "${VERSION} is already installed."
    hmvm_use "${VERSION}"
    return $?
  fi

  command mkdir -p "$(hmvm_version_dir)"
  if [ "${USE_LINK}" = "1" ]; then
    hmvm_echo "Linking HarmonyOS command-line-tools ${VERSION} from ${FROM_PATH}..."
    # 转为绝对路径但不跟随符号链接（避免 zsh CHASE_LINKS 将软链接路径解析成目标物理路径）
    local FROM_ABS
    case "${FROM_PATH}" in
      /*) FROM_ABS="${FROM_PATH}" ;;
      *)  FROM_ABS="$(pwd)/${FROM_PATH}" ;;
    esac
    # 验证路径有效性（[ -f ] 会自动跟随符号链接到目标，此处行为正确）
    if [ ! -f "${FROM_ABS}/version.txt" ] && [ ! -f "${FROM_ABS}/bin/ohpm" ]; then
      hmvm_err "hmvm: path '${FROM_ABS}' is not a valid command-line-tools directory."
      return 1
    fi
    if command ln -sf "${FROM_ABS}" "${VERSION_PATH}"; then
      hmvm_echo "Linked HarmonyOS command-line-tools ${VERSION} successfully."
      # 生成旁路元数据，保证 hmvm list 能显示版本信息
      hmvm_detect_and_save_meta "${VERSION}" "${VERSION_PATH}" 2>/dev/null || true
      hmvm_use "${VERSION}"
      return $?
    else
      hmvm_err "Failed to link from ${FROM_PATH} to ${VERSION_PATH}"
      command rm -f "${VERSION_PATH}" 2>/dev/null || true
      return 1
    fi
  else
    hmvm_echo "Installing HarmonyOS command-line-tools ${VERSION} from ${FROM_PATH}..."
    if command cp -R "${FROM_PATH}" "${VERSION_PATH}"; then
      hmvm_echo "Installed HarmonyOS command-line-tools ${VERSION} successfully."
      hmvm_use "${VERSION}"
      return $?
    else
      hmvm_err "Failed to copy from ${FROM_PATH} to ${VERSION_PATH}"
      command rm -rf "${VERSION_PATH}" 2>/dev/null || true
      return 1
    fi
  fi
}

# 卸载版本
hmvm_uninstall() {
  local VERSION
  VERSION="$(hmvm_version "${1-}")"
  if [ -z "${VERSION}" ]; then
    hmvm_err "hmvm uninstall: version is required."
    return 1
  fi

  VERSION="$(hmvm_ensure_version_prefix "${VERSION}")"

  if ! hmvm_is_version_installed "${VERSION}"; then
    hmvm_err "hmvm: version '${VERSION}' is not installed."
    return 1
  fi

  local CURRENT
  CURRENT="$(hmvm_ls_current)"
  if [ "${CURRENT}" = "${VERSION}" ]; then
    hmvm_err "hmvm: Cannot uninstall currently-active version, ${VERSION}."
    hmvm_err "Run 'hmvm use <other-version>' first."
    return 1
  fi

  local VERSION_PATH
  VERSION_PATH="$(hmvm_version_path "${VERSION}")"
  hmvm_echo "Uninstalling HarmonyOS command-line-tools ${VERSION}..."
  if [ -L "${VERSION_PATH}" ]; then
    # 软链接安装的版本：只删除符号链接本身，绝不递归删除链接目标目录
    command rm -f "${VERSION_PATH}"
  else
    command rm -rf "${VERSION_PATH}"
  fi
  # 清理软链接版本的旁路元数据文件
  local META_FILE
  META_FILE="$(hmvm_symlink_meta_path "${VERSION}")"
  [ -f "${META_FILE}" ] && command rm -f "${META_FILE}" 2>/dev/null || true
  hmvm_echo "Uninstalled ${VERSION}."
  return 0
}

# 设置别名
hmvm_alias() {
  local ALIAS
  ALIAS="${1-}"
  local TARGET
  TARGET="${2-}"

  local ALIAS_DIR
  ALIAS_DIR="$(hmvm_alias_path)"
  command mkdir -p "${ALIAS_DIR}"

  if [ -z "${TARGET}" ]; then
    if [ -z "${ALIAS}" ]; then
      # 列出所有别名
      for f in "${ALIAS_DIR}"/*; do
        [ -f "$f" ] && hmvm_echo "$(basename "$f") -> $(cat "$f")"
      done
      return 0
    fi
    # 删除别名
    if [ -f "${ALIAS_DIR}/${ALIAS}" ]; then
      command rm -f "${ALIAS_DIR}/${ALIAS}"
      hmvm_echo "Deleted alias ${ALIAS}"
    else
      hmvm_err "Alias ${ALIAS} does not exist."
      return 1
    fi
    return 0
  fi

  local RESOLVED
  RESOLVED="$(hmvm_version "${TARGET}")"
  if ! hmvm_is_version_installed "${RESOLVED}"; then
    hmvm_err "hmvm: version '${TARGET}' is not installed."
    return 1
  fi

  RESOLVED="$(hmvm_ensure_version_prefix "${RESOLVED}")"
  printf %s "${RESOLVED}" > "${ALIAS_DIR}/${ALIAS}"
  hmvm_echo "${ALIAS} -> ${RESOLVED}"
  return 0
}

# 查找 .hmvmrc
hmvm_find_hmvmrc() {
  local DIR
  DIR="$(pwd)"
  while [ -n "${DIR}" ] && [ "${DIR}" != "/" ]; do
    if [ -f "${DIR}/.hmvmrc" ]; then
      hmvm_echo "${DIR}/.hmvmrc"
      return 0
    fi
    DIR="$(dirname "${DIR}")"
  done
  return 1
}

# 显示 which 路径
hmvm_which() {
  local CMD
  CMD="${1:-ohpm}"
  local BIN_PATH
  BIN_PATH="$(command which "${CMD}" 2>/dev/null)" || true
  if [ -n "${BIN_PATH}" ]; then
    hmvm_echo "${BIN_PATH}"
  else
    hmvm_err "hmvm: ${CMD} not found in PATH"
    return 1
  fi
}

# 列出远程版本（从 versions.json 读取）
hmvm_ls_remote() {
  local VERSIONS_JSON
  VERSIONS_JSON="$(hmvm_install_dir)/versions.json"
  if [ -f "${VERSIONS_JSON}" ]; then
    local PLATFORM
    PLATFORM="$(hmvm_get_platform)"
    local VERSIONS
    if hmvm_has jq; then
      VERSIONS="$(command jq -r ".\"${PLATFORM}\"[]?.version // empty" "${VERSIONS_JSON}" 2>/dev/null | command sort -V -r)"
    else
      VERSIONS="$(command grep -oE '"version"[[:space:]]*:[[:space:]]*"[^"]*"' "${VERSIONS_JSON}" 2>/dev/null | command sed 's/.*"\([^"]*\)"$/\1/' | command sort -V -r)"
    fi
    if [ -n "${VERSIONS}" ]; then
      hmvm_echo "${VERSIONS}"
      return 0
    fi
  fi
  hmvm_echo "No remote versions configured. Use 'hmvm install <version> --from <path>' to install from local."
  return 0
}

hmvm_get_platform() {
  local ARCH
  ARCH="$(uname -m)"
  case "$(uname -s)" in
    Darwin)
      if [ "${ARCH}" = "arm64" ]; then
        hmvm_echo "mac-arm64"
      else
        hmvm_echo "mac-x64"
      fi
      ;;
    Linux)
      hmvm_echo "linux"
      ;;
    MINGW*|MSYS*)
      hmvm_echo "windows"
      ;;
    *)
      hmvm_echo "unknown"
      ;;
  esac
}

# 帮助信息
hmvm_print_help() {
  hmvm_echo "HarmonyOS Version Manager (hmvm)"
  hmvm_echo ""
  hmvm_echo "Usage:"
  hmvm_echo "  hmvm install <version> --from <path> [--link]  Install from local path"
  hmvm_echo "  hmvm global [<version>]               Set/show global default version"
  hmvm_echo "  hmvm use [<version>] [--save]         Switch to version (or read .hmvmrc)"
  hmvm_echo "  hmvm ls [list]                        List installed versions"
  hmvm_echo "  hmvm ls-remote                        List available versions"
  hmvm_echo "  hmvm current                          Show current version"
  hmvm_echo "  hmvm uninstall <version>              Uninstall version"
  hmvm_echo "  hmvm alias <name> [<version>]         Set/remove alias"
  hmvm_echo "  hmvm which [command]                  Show path to command (default: ohpm)"
  hmvm_echo ""
}

# =============================================================================
# 主入口
# =============================================================================

hmvm() {
  local COMMAND
  COMMAND="${1-}"
  shift || true

  case "${COMMAND}" in
    -V|--version)
      hmvm_echo "${HMVM_VERSION}"
      ;;
    ""|help)
      hmvm_print_help
      ;;
    install)
      local VERSION
      local FROM_PATH
      local USE_LINK
      VERSION=""
      FROM_PATH=""
      USE_LINK="0"
      while [ $# -gt 0 ]; do
        case "$1" in
          --from)
            shift
            FROM_PATH="${1-}"
            shift
            ;;
          --link)
            USE_LINK="1"
            shift
            ;;
          *)
            if [ -z "${VERSION}" ]; then
              VERSION="$1"
            fi
            shift
            ;;
        esac
      done
      if [ -n "${FROM_PATH}" ]; then
        hmvm_install_from_path "${VERSION}" "${FROM_PATH}" "${USE_LINK}"
      else
        hmvm_err "hmvm install: use 'hmvm install <version> --from <path>' to install from local."
        hmvm_err "  Example: hmvm install 6.1.0.609 --from /Users/h1007/command-line-tools"
        return 1
      fi
      ;;
    use)
      local SAVE_HMVMRC
      SAVE_HMVMRC=0
      local USE_VERSION
      USE_VERSION=""
      while [ $# -gt 0 ]; do
        case "$1" in
          --save|-w)
            SAVE_HMVMRC=1
            shift
            ;;
          *)
            USE_VERSION="$1"
            shift
            break
            ;;
        esac
      done
      if [ -z "${USE_VERSION}" ]; then
        local HMVMRC
        if HMVMRC="$(hmvm_find_hmvmrc 2>/dev/null)"; then
          local VERSION
          VERSION="$(command cat "${HMVMRC}")"
          hmvm_use "${VERSION}"
          return $?
        fi
        hmvm_err "hmvm use: version is required."
        return 1
      fi
      if hmvm_use "${USE_VERSION}"; then
        if [ "${SAVE_HMVMRC}" = "1" ]; then
          local VERSION
          VERSION="$(hmvm_version "${USE_VERSION}")"
          printf %s "${VERSION}" > .hmvmrc
          hmvm_echo "Saved ${VERSION} to .hmvmrc"
        fi
        return 0
      else
        return $?
      fi
      ;;
    ls|list)
      hmvm_ls
      ;;
    ls-remote)
      hmvm_ls_remote
      ;;
    current)
      hmvm_ls_current
      ;;
    uninstall)
      if [ $# -lt 1 ]; then
        hmvm_err "hmvm uninstall: version is required."
        return 1
      fi
      hmvm_uninstall "$1"
      ;;
    alias)
      hmvm_alias "$1" "$2"
      ;;
    global)
      if [ $# -lt 1 ]; then
        # 无参数：显示当前 global 版本
        local GLOBAL
        GLOBAL="$(hmvm_resolve_alias "default" 2>/dev/null)" || true
        if [ -n "${GLOBAL}" ]; then
          hmvm_echo "${GLOBAL}"
        else
          hmvm_echo "No global version set. Use 'hmvm global <version>' to set one."
        fi
        return 0
      fi
      # 有参数：设置 default 别名并立即激活
      if hmvm_alias "default" "$1"; then
        hmvm_use "$1"
        return $?
      fi
      return 1
      ;;
    which)
      hmvm_which "$1"
      ;;
    *)
      hmvm_err "hmvm: unknown command '${COMMAND}'"
      hmvm_print_help
      return 1
      ;;
  esac
}

# 自动 use default（如果设置了 default 别名）
hmvm_use_default_if_present() {
  local DEFAULT
  DEFAULT="$(hmvm_resolve_alias "default" 2>/dev/null)" || true
  if [ -n "${DEFAULT}" ] && hmvm_is_version_installed "${DEFAULT}"; then
    hmvm_use "${DEFAULT}" 2>/dev/null || true
  fi
}

# source 时自动激活 global 版本（新建终端生效）
hmvm_use_default_if_present

} # this ensures the entire script is downloaded #
