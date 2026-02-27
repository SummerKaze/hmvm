#!/usr/bin/env bash
# HarmonyOS Version Manager (hmvm) 安装脚本
# 用法: curl -fsSL https://raw.githubusercontent.com/.../install.sh | bash
#   或: wget -qO- https://raw.githubusercontent.com/.../install.sh | bash

{ # this ensures the entire script is downloaded #

hmvm_has() {
  type "$1" > /dev/null 2>&1
}

hmvm_echo() {
  command printf %s\\n "$*" 2>/dev/null
}

hmvm_grep() {
  GREP_OPTIONS='' command grep "$@"
}

hmvm_default_install_dir() {
  [ -z "${XDG_CONFIG_HOME-}" ] && printf %s "${HOME}/.hmvm" || printf %s "${XDG_CONFIG_HOME}/hmvm"
}

hmvm_install_dir() {
  if [ -n "${HMVM_DIR}" ]; then
    printf %s "${HMVM_DIR}"
  else
    hmvm_default_install_dir
  fi
}

# 根据用户默认 shell ($SHELL) 检测 profile，而非当前运行 install 的 shell
hmvm_detect_profile() {
  if [ "${PROFILE-}" = '/dev/null' ]; then
    return
  fi

  if [ -n "${PROFILE}" ] && [ -f "${PROFILE}" ]; then
    hmvm_echo "${PROFILE}"
    return
  fi

  local DETECTED_PROFILE
  DETECTED_PROFILE=''

  # 优先根据 $SHELL 判断用户默认 shell（避免 bash ./install.sh 时误写 .bash_profile）
  case "${SHELL-}" in
    *zsh*)
      if [ -f "${ZDOTDIR:-${HOME}}/.zshrc" ]; then
        DETECTED_PROFILE="${ZDOTDIR:-${HOME}}/.zshrc"
      elif [ -f "${ZDOTDIR:-${HOME}}/.zprofile" ]; then
        DETECTED_PROFILE="${ZDOTDIR:-${HOME}}/.zprofile"
      fi
      ;;
    *bash*)
      if [ -f "${HOME}/.bashrc" ]; then
        DETECTED_PROFILE="${HOME}/.bashrc"
      elif [ -f "${HOME}/.bash_profile" ]; then
        DETECTED_PROFILE="${HOME}/.bash_profile"
      fi
      ;;
    *)
      # 回退：按存在性优先选择 zshrc > bashrc > zprofile > bash_profile
      for EACH_PROFILE in ".zshrc" ".bashrc" ".zprofile" ".bash_profile" ".profile"; do
        if [ -f "${ZDOTDIR:-${HOME}}/${EACH_PROFILE}" ]; then
          DETECTED_PROFILE="${ZDOTDIR:-${HOME}}/${EACH_PROFILE}"
          break
        elif [ -f "${HOME}/${EACH_PROFILE}" ]; then
          DETECTED_PROFILE="${HOME}/${EACH_PROFILE}"
          break
        fi
      done
      ;;
  esac

  if [ -n "${DETECTED_PROFILE}" ]; then
    hmvm_echo "${DETECTED_PROFILE}"
  fi
}

hmvm_do_install() {
  if [ -n "${HMVM_DIR-}" ] && ! [ -d "${HMVM_DIR}" ]; then
    if [ -e "${HMVM_DIR}" ]; then
      hmvm_echo >&2 "File \"${HMVM_DIR}\" has the same name as installation directory."
      exit 1
    fi
    if [ "${HMVM_DIR}" = "$(hmvm_default_install_dir)" ]; then
      mkdir -p "${HMVM_DIR}"
    else
      hmvm_echo >&2 "You have \$HMVM_DIR set to \"${HMVM_DIR}\", but that directory does not exist."
      exit 1
    fi
  fi

  if ! hmvm_has git && ! hmvm_has curl && ! hmvm_has wget; then
    hmvm_echo >&2 'You need git, curl, or wget to install hmvm'
    exit 1
  fi

  local INSTALL_DIR
  INSTALL_DIR="$(hmvm_install_dir)"

  # 若从本地 hmvm 目录运行 install.sh，直接使用当前目录
  local SCRIPT_DIR
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
  if [ -f "${SCRIPT_DIR}/hmvm.sh" ] && [ "${SCRIPT_DIR}" != "$(hmvm_default_install_dir)" ]; then
    if [ -z "${HMVM_DIR-}" ]; then
      hmvm_echo "=> Installing from local directory: ${SCRIPT_DIR}"
      INSTALL_DIR="${SCRIPT_DIR}"
      export HMVM_DIR="${INSTALL_DIR}"
    fi
  fi

  local HMVM_REPO
  HMVM_REPO="${HMVM_INSTALL_GITHUB_REPO:-SummerKaze/hmvm}"

  if [ -f "${INSTALL_DIR}/hmvm.sh" ]; then
    hmvm_echo "=> hmvm is already installed in ${INSTALL_DIR}"
  elif [ -d "${INSTALL_DIR}/.git" ]; then
    hmvm_echo "=> hmvm is already installed in ${INSTALL_DIR}, trying to update using git"
    command printf '\r=> '
    if command git -C "${INSTALL_DIR}" fetch origin 2>/dev/null; then
      if command git -C "${INSTALL_DIR}" pull origin main 2>/dev/null || command git -C "${INSTALL_DIR}" pull origin master 2>/dev/null; then
        hmvm_echo "=> hmvm has been updated"
      fi
    else
      hmvm_echo >&2 "Failed to update hmvm. Run 'cd ${INSTALL_DIR} && git pull' manually."
    fi
  else
    hmvm_echo "=> Downloading hmvm to ${INSTALL_DIR}"
    command printf '\r=> '
    if hmvm_has git; then
      if command git clone "https://github.com/${HMVM_REPO}.git" "${INSTALL_DIR}" 2>/dev/null; then
        :
      else
        hmvm_echo >&2 "Failed to clone hmvm repo. Please check your network or install manually."
        exit 1
      fi
    else
      mkdir -p "${INSTALL_DIR}"
      if hmvm_has curl; then
        if ! curl -fsSL "https://raw.githubusercontent.com/${HMVM_REPO}/main/hmvm.sh" -o "${INSTALL_DIR}/hmvm.sh"; then
          hmvm_echo >&2 "Failed to download hmvm.sh. You can install manually from GitHub."
          exit 1
        fi
        curl -fsSL "https://raw.githubusercontent.com/${HMVM_REPO}/main/versions.json" -o "${INSTALL_DIR}/versions.json" 2>/dev/null || true
      elif hmvm_has wget; then
        if ! wget -q "https://raw.githubusercontent.com/${HMVM_REPO}/main/hmvm.sh" -O "${INSTALL_DIR}/hmvm.sh"; then
          hmvm_echo >&2 "Failed to download hmvm.sh. You can install manually from GitHub."
          exit 1
        fi
      fi
    fi
  fi

  hmvm_echo ""

  local NVM_PROFILE
  NVM_PROFILE="$(hmvm_detect_profile)"
  local PROFILE_INSTALL_DIR
  PROFILE_INSTALL_DIR="$(hmvm_echo "${INSTALL_DIR}" | command sed "s:^${HOME}:\$HOME:")"

  SOURCE_STR="\\nexport HMVM_DIR=\"${PROFILE_INSTALL_DIR}\"\\n[ -s \"\$HMVM_DIR/hmvm.sh\" ] && \\. \"\$HMVM_DIR/hmvm.sh\"  # This loads hmvm\\n[ -s \"\$HMVM_DIR/bash_completion\" ] && \\. \"\$HMVM_DIR/bash_completion\"  # This loads hmvm bash_completion\\n"

  if [ -z "${NVM_PROFILE-}" ]; then
    hmvm_echo "=> Profile not found. Tried ~/.bashrc, ~/.bash_profile, ~/.zprofile, ~/.zshrc, and ~/.profile."
    hmvm_echo "=> Create one of them and run this script again"
    hmvm_echo "   OR"
    hmvm_echo "=> Append the following lines to the correct file yourself:"
    command printf "${SOURCE_STR}"
    hmvm_echo ""
  else
    if ! command grep -qc '/hmvm.sh' "$NVM_PROFILE"; then
      hmvm_echo "=> Appending hmvm source string to ${NVM_PROFILE}"
      command printf "${SOURCE_STR}" >> "$NVM_PROFILE"
    else
      hmvm_echo "=> hmvm source string already in ${NVM_PROFILE}"
    fi
  fi

  hmvm_echo ""
  hmvm_echo "=> Close and reopen your terminal to start using hmvm or run the following to use it now:"
  command printf "${SOURCE_STR}"
  hmvm_echo ""
  hmvm_echo "=> To install HarmonyOS command-line-tools from your existing installation:"
  hmvm_echo "   hmvm install 6.1.0 --from /path/to/command-line-tools"
  hmvm_echo ""
}

hmvm_do_install

} # this ensures the entire script is downloaded #
