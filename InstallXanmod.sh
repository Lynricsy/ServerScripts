#!/bin/bash
set -o pipefail

# XanMod内核安装脚本

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

readonly XANMOD_KEY_URL="https://dl.xanmod.org/archive.key"
readonly XANMOD_KEYRING="/etc/apt/keyrings/xanmod-archive-keyring.gpg"
readonly XANMOD_SOURCE_LIST="/etc/apt/sources.list.d/xanmod-release.list"
readonly XANMOD_REPOSITORY_URL="http://deb.xanmod.org"
readonly XANMOD_REPOSITORY_COMPONENTS="main non-free"
readonly XANMOD_KERNEL_PACKAGE="linux-xanmod-x64v3"

# 日志函数
log_info() {
  echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
  echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
  echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
  echo -e "${PURPLE}[STEP]${NC} $1"
}

# 获取 Debian/Ubuntu 发行版代号
get_distribution_codename() {
  local codename=""

  if [[ -r /etc/os-release ]]; then
      # shellcheck disable=SC1091
      . /etc/os-release
      codename="${VERSION_CODENAME:-${UBUNTU_CODENAME:-}}"
  fi

  if [[ -z "$codename" ]] && command -v lsb_release >/dev/null 2>&1; then
      codename="$(lsb_release -sc 2>/dev/null || true)"
  fi

  if [[ -z "$codename" ]]; then
      log_error "无法识别发行版代号，不能配置XanMod软件源！"
      exit 1
  fi

  printf '%s\n' "$codename"
}

# 检查是否为root用户
check_root() {
  if [[ $EUID -ne 0 ]]; then
      log_error "此脚本需要root权限运行！"
      exit 1
  fi
}

# 主要安装函数
install_xanmod() {
  log_info "开始安装XanMod内核..."
  echo -e "${CYAN}================================${NC}"
  echo -e "${CYAN}    XanMod内核安装脚本 🚀    ${NC}"
  echo -e "${CYAN}================================${NC}"
  
  # 步骤1: 更新包列表并安装依赖
  log_step "更新包列表并安装必要依赖..."
  if apt update -y && apt install -y ca-certificates wget gnupg; then
      log_success "依赖安装完成！"
  else
      log_error "依赖安装失败！"
      exit 1
  fi
  
  # 步骤2: 添加XanMod GPG密钥
  log_step "添加XanMod GPG密钥..."
  if install -d -m 0755 "$(dirname "$XANMOD_KEYRING")" \
      && wget -qO - "$XANMOD_KEY_URL" | gpg --dearmor --yes -o "$XANMOD_KEYRING" \
      && chmod 0644 "$XANMOD_KEYRING"; then
      log_success "GPG密钥添加成功！"
  else
      log_error "GPG密钥添加失败！"
      exit 1
  fi
  
  # 步骤3: 添加XanMod软件源
  log_step "添加XanMod软件源..."
  distribution_codename="$(get_distribution_codename)"
  if echo "deb [signed-by=${XANMOD_KEYRING}] ${XANMOD_REPOSITORY_URL} ${distribution_codename} ${XANMOD_REPOSITORY_COMPONENTS}" | tee "$XANMOD_SOURCE_LIST" > /dev/null; then
      log_success "软件源添加成功！"
      log_info "已配置XanMod软件源代号: ${distribution_codename}"
      log_info "已启用XanMod软件源组件: ${XANMOD_REPOSITORY_COMPONENTS}"
  else
      log_error "软件源添加失败！"
      exit 1
  fi
  
  # 步骤4: 更新包列表
  log_step "更新包列表..."
  if apt update -y; then
      log_success "包列表更新完成！"
  else
      log_error "包列表更新失败！"
      exit 1
  fi
  
  # 步骤5: 安装XanMod内核
  log_step "安装XanMod内核（x64v3版本）..."
  if apt install -y "$XANMOD_KERNEL_PACKAGE"; then
      log_success "XanMod内核安装完成！"
  else
      log_error "XanMod内核安装失败！"
      exit 1
  fi
  
  # 步骤6: 配置网络优化参数
  log_step "配置网络优化参数..."
  cat > /etc/sysctl.conf << 'EOF'

net.core.default_qdisc=fq_pie

net.ipv4.tcp_congestion_control=bbr

EOF
  
  if [[ $? -eq 0 ]]; then
      log_success "网络优化参数配置完成！"
      log_info "已配置BBR拥塞控制和FQ_PIE队列调度算法"
      
      # 步骤7: 应用sysctl配置
      log_step "应用sysctl配置..."
      if sysctl -p; then
          log_success "sysctl配置已应用！"
      else
          log_warning "sysctl配置应用失败，但重启后会自动加载"
      fi
  else
      log_error "网络优化参数配置失败！"
      exit 1
  fi
  
  echo -e "${CYAN}================================${NC}"
  log_success "所有安装步骤完成！🎉"
  echo -e "${CYAN}================================${NC}"
}

# 询问是否重启
ask_reboot() {
  echo ""
  log_warning "需要重启系统以使新内核生效！"
  log_info "网络优化参数已经应用，重启后会继续生效"
  echo -e "${YELLOW}是否现在重启系统？(y/N): ${NC}\c"
  read -r response
  
  case $response in
      [yY]|[yY][eE][sS])
          log_info "正在重启系统..."
          sleep 2
          reboot
          ;;
      *)
          log_info "已取消重启。请稍后手动重启系统以使新内核生效。"
          log_info "重启后可以使用以下命令检查："
          echo -e "  ${CYAN}uname -r${NC}                    # 检查内核版本"
          echo -e "  ${CYAN}sysctl net.ipv4.tcp_congestion_control${NC}  # 检查BBR状态"
          echo -e "  ${CYAN}sysctl net.core.default_qdisc${NC}           # 检查队列调度算法"
          ;;
  esac
}

# 主程序
main() {
  check_root
  install_xanmod
  ask_reboot
}

# 执行主程序
main "$@"
