# HarmonyOS Version Manager (hmvm)
# 基于 nvm 架构魔改，管理鸿蒙 command-line-tools 多版本
# POSIX 兼容，支持 sh, dash, bash, ksh, zsh
# 使用方式：在 shell profile 中 source 此文件
#
# shellcheck disable=SC2039,SC2016,SC2001,SC3043
{ # this ensures the entire script is downloaded #

HMVM_SCRIPT_SOURCE="$_"

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

# 检查版本是否已安装（存在 version.txt 或 bin/ohpm）
hmvm_is_version_installed() {
  local VERSION_PATH
  VERSION_PATH="$(hmvm_version_path "${1-}" 2>/dev/null)"
  if [ -z "${VERSION_PATH}" ]; then
    return 1
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
hmvm_ls_current() {
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

# 列出已安装版本
hmvm_ls() {
  local VERSION_DIR
  VERSION_DIR="$(hmvm_version_dir)"
  if [ ! -d "${VERSION_DIR}" ]; then
    return 0
  fi
  local VERSIONS
  VERSIONS="$(command ls -1 "${VERSION_DIR}" 2>/dev/null | command sed 's/^v//')"
  if [ -z "${VERSIONS}" ]; then
    return 0
  fi
  hmvm_echo "${VERSIONS}"
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

  # 设置 PATH：bin 目录 + tool/node/bin
  PATH="$(hmvm_change_path "${PATH}" "/bin" "${VERSION_PATH}")"
  if [ -d "${VERSION_PATH}/tool/node/bin" ]; then
    PATH="${VERSION_PATH}/tool/node/bin:${PATH}"
  fi
  export PATH

  export DEVECO_NODE_HOME="${VERSION_PATH}/tool/node"
  export DEVECO_SDK_HOME="${VERSION_PATH}/sdk"
  export HMVM_BIN="${VERSION_PATH}/bin"

  \hash -r 2>/dev/null || true

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
    if command ln -sf "$(command cd "${FROM_PATH}" && pwd)" "${VERSION_PATH}"; then
      hmvm_echo "Linked HarmonyOS command-line-tools ${VERSION} successfully."
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
  command rm -rf "${VERSION_PATH}"
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

} # this ensures the entire script is downloaded #
