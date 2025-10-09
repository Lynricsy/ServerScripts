#!/bin/bash

# 一键添加2G Swap脚本

set -e  # 遇到错误立即退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 打印带颜色的消息
print_info() {
  echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
  echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
  echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
  echo -e "${RED}[ERROR]${NC} $1"
}

# 检查是否为root用户
check_root() {
  if [[ $EUID -ne 0 ]]; then
      print_error "此脚本需要root权限运行，请使用 sudo 执行"
      exit 1
  fi
}

# 检查当前swap状态
check_current_swap() {
  print_info "检查当前swap状态..."
  
  current_swap=$(free -h | grep -i swap | awk '{print $2}')
  if [[ "$current_swap" != "0B" ]]; then
      print_warning "检测到已存在swap: $current_swap"
      echo -n "是否继续添加新的swap文件? (y/N): "
      read -r response
      if [[ ! "$response" =~ ^[Yy]$ ]]; then
          print_info "操作已取消"
          exit 0
      fi
  else
      print_success "当前无swap，可以安全添加"
  fi
}

# 检查磁盘空间
check_disk_space() {
  print_info "检查磁盘空间..."
  
  # 获取根目录可用空间(GB)
  available_space=$(df / | tail -1 | awk '{print $4}')
  available_gb=$((available_space / 1024 / 1024))
  
  if [[ $available_gb -lt 3 ]]; then
      print_error "磁盘空间不足！需要至少3GB空间，当前可用: ${available_gb}GB"
      exit 1
  fi
  
  print_success "磁盘空间充足: ${available_gb}GB 可用"
}

# 创建swap文件
create_swap_file() {
  print_info "创建2GB swap文件..."
  
  # 使用fallocate快速创建文件（如果支持）
  if command -v fallocate >/dev/null 2>&1; then
      fallocate -l 2G /swapfile
  else
      # 备用方案：使用dd命令
      dd if=/dev/zero of=/swapfile bs=1M count=2048 status=progress
  fi
  
  print_success "Swap文件创建完成"
}

# 设置swap文件权限和格式
setup_swap_file() {
  print_info "设置swap文件权限和格式..."
  
  # 设置正确的权限（仅root可读写）
  chmod 600 /swapfile
  
  # 格式化为swap格式
  mkswap /swapfile
  
  print_success "Swap文件设置完成"
}

# 启用swap
enable_swap() {
  print_info "启用swap..."
  
  # 立即启用swap
  swapon /swapfile
  
  print_success "Swap已启用"
}

# 添加到fstab实现开机自动挂载
add_to_fstab() {
  print_info "添加到/etc/fstab实现开机自动挂载..."
  
  # 检查是否已经存在相同条目
  if ! grep -q "/swapfile" /etc/fstab; then
      echo "/swapfile none swap sw 0 0" >> /etc/fstab
      print_success "已添加到/etc/fstab"
  else
      print_warning "/etc/fstab中已存在swap条目"
  fi
}

# 优化swap设置
optimize_swap() {
  print_info "优化swap设置..."
  
  # 设置swappiness值（推荐10，减少对swap的依赖）
  echo "vm.swappiness=10" >> /etc/sysctl.conf
  sysctl vm.swappiness=10
  
  # 设置vfs_cache_pressure（推荐50）
  echo "vm.vfs_cache_pressure=50" >> /etc/sysctl.conf
  sysctl vm.vfs_cache_pressure=50
  
  print_success "Swap优化完成"
}

# 显示最终状态
show_final_status() {
  print_info "最终swap状态:"
  echo "----------------------------------------"
  free -h
  echo "----------------------------------------"
  swapon --show
  echo "----------------------------------------"
  print_success "2GB Swap添加完成！🎉"
}

# 主函数
main() {
  echo "========================================"
  echo "    一键添加2G Swap脚本"
  echo "========================================"
  
  check_root
  check_current_swap
  check_disk_space
  create_swap_file
  setup_swap_file
  enable_swap
  add_to_fstab
  optimize_swap
  show_final_status
  
  print_success "所有操作完成！系统重启后swap将自动挂载 ✨"
}

# 执行主函数
main "$@"
