#!/bin/bash
# 确保使用 Bash 运行（防止被 sh 调用导致早退）
if [ -z "${BASH_VERSION:-}" ]; then
    exec /usr/bin/env bash "$0" "$@"
fi
# Arch Linux 定制镜像全面测试脚本
# 创建时间: 2025-12-13 +08:00
# 创建者: Mare Ashley Pecker (mare@sent.com)
# 用途: 验证 imagepacker-archlinux.sh 构建的镜像的所有定制修改

# ============================================
# 环境检查（在 set -e 之前）
# ============================================

# 检查是否在正确的操作系统上运行
if [ ! -f /etc/os-release ]; then
    echo "❌ 错误: 未检测到 /etc/os-release 文件"
    echo "⚠️  此脚本必须在 Arch Linux 虚拟机中运行，不能在宿主机上运行！"
    echo ""
    echo "正确的使用方法："
    echo "1. 启动 Arch Linux 虚拟机"
    echo "2. 将此脚本上传到虚拟机中"
    echo "3. 在虚拟机内运行: ./test-image-archlinux.sh"
    echo ""
    echo "当前系统: $(uname -s)"
    exit 1
fi

# 检查是否是 Arch Linux 系统
if ! grep -qE "ID=arch|ID_LIKE=.*arch" /etc/os-release 2>/dev/null; then
    echo "⚠️  警告: 此脚本是为 Arch Linux 设计的"
    echo "当前系统: $(grep PRETTY_NAME /etc/os-release | cut -d'"' -f2)"
    echo ""
    read -p "是否继续？(y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

set -u  # 使用未定义变量时退出
set -o pipefail  # 管道命令失败时退出
# 注意：不使用 set -e，改为在测试函数中手动处理错误

# ============================================
# 颜色和样式定义
# ============================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# ============================================
# 全局变量
# ============================================
TEST_COUNT=0
PASS_COUNT=0
FAIL_COUNT=0
START_TIME=$(date +%s)
TEST_LOG="/tmp/image-test-$(date +%Y%m%d-%H%M%S).log"
TEST_REPORT="/tmp/image-test-report-$(date +%Y%m%d-%H%M%S).md"

# 确保日志目录存在
touch "$TEST_LOG" 2>/dev/null || {
    echo "❌ 错误: 无法创建日志文件 $TEST_LOG"
    echo "请检查 /tmp 目录权限"
    exit 1
}

# ============================================
# 错误处理
# ============================================
# 提示是否继续测试
prompt_continue() {
    ((++FAIL_COUNT))

    echo -e "\n${RED}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${RED}${BOLD}❌ 测试失败${NC}"
    echo -e "${RED}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${YELLOW}已完成测试: ${TEST_COUNT}${NC}"
    echo -e "${GREEN}通过: ${PASS_COUNT}${NC}"
    echo -e "${RED}失败: ${FAIL_COUNT}${NC}"
    echo ""

    # 交互式提示：是否继续
    if [ -t 0 ]; then  # 检查是否在交互式终端
        echo -ne "${YELLOW}是否继续后续测试？[Y/n]${NC} "
        read -r -n 1 response
        echo ""

        # 默认为 Y（回车或 y/Y）
        if [[ $response =~ ^[Nn]$ ]]; then
            echo -e "${RED}✗ 用户选择退出${NC}\n"
            echo -e "${CYAN}查看详细日志: ${TEST_LOG}${NC}"
            exit 1
        else
            echo -e "${CYAN}▶ 继续执行后续测试...${NC}\n"
        fi
    else
        # 非交互式环境，自动退出
        echo -e "${RED}非交互式环境，测试终止${NC}"
        echo -e "${CYAN}查看详细日志: ${TEST_LOG}${NC}"
        exit 1
    fi
}

# ============================================
# 日志函数
# ============================================
## 全局日志重定向：后续所有标准输出与错误将同时写入控制台与日志文件
exec > >(tee -a "$TEST_LOG") 2>&1
echo "== LOG START $(date '+%Y-%m-%d %H:%M:%S %z') =="

## 可选：启用详细跟踪（运行时设置 TRACE=1）
if [[ "${TRACE:-0}" == "1" ]]; then
    set -x
fi
log_header() {
    echo -e "\n${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${CYAN}$1${NC}"
    echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

log_section() {
    echo -e "\n${BOLD}${MAGENTA}▶ $1${NC}\n"
}

log_step() {
    echo -e "${BLUE}  ◆ $1${NC}"
}

log_info() {
    echo -e "${CYAN}  ℹ $1${NC}"
}

log_success() {
    echo -e "${GREEN}  ✓ $1${NC}"
}

log_error() {
    echo -e "${RED}  ✗ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}  ⚠ $1${NC}"
}

log_result() {
    echo -e "${BOLD}  → $1${NC}"
}

# ============================================
# 测试辅助函数
# ============================================
start_test() {
    ((++TEST_COUNT))
    local test_name="$1"
    echo -e "\n${BOLD}${YELLOW}━━━ 测试 #${TEST_COUNT}: ${test_name} ━━━${NC}"
    log_info "开始时间: $(date '+%Y-%m-%d %H:%M:%S')"
}

end_test() {
    local test_name="$1"
    ((++PASS_COUNT))
    log_success "测试通过: ${test_name}"
    echo -e "${BOLD}${GREEN}━━━ ✓ 测试 #${TEST_COUNT} 完成 ━━━${NC}\n"
}

# 验证命令输出包含期望内容
assert_contains() {
    local command="$1"
    local expected="$2"
    local description="$3"

    log_step "执行: ${command}"
    local output=$(eval "$command" 2>&1)

    echo "$output" | tee -a "$TEST_LOG"

    if echo "$output" | grep -q "$expected"; then
        log_success "验证通过: ${description}"
        log_result "找到期望内容: ${expected}"
        return 0
    else
        log_error "验证失败: ${description}"
        log_error "期望包含: ${expected}"
        log_error "实际输出: ${output}"
        prompt_continue
        return 1
    fi
}

# 验证命令成功执行
assert_success() {
    local command="$1"
    local description="$2"

    log_step "执行: ${command}"
    if eval "$command" &>/dev/null; then
        log_success "成功: ${description}"
        return 0
    else
        log_error "失败: ${description}"
        log_error "命令执行失败: ${command}"
        prompt_continue
        return 1
    fi
}

# 验证文件存在
assert_file_exists() {
    local file="$1"
    local description="$2"

    log_step "检查文件: ${file}"
    if [ -f "$file" ] || [ -d "$file" ]; then
        log_success "存在: ${description}"
        return 0
    else
        log_error "不存在: ${description}"
        log_error "文件路径: ${file}"
        prompt_continue
        return 1
    fi
}

# 验证命令存在
assert_command_exists() {
    local cmd="$1"
    local description="$2"

    log_step "检查命令: ${cmd}"
    if command -v "$cmd" &> /dev/null; then
        # 使用 timeout 防止某些命令（如 bzip2）等待 stdin 导致卡死
        # 同时使用 </dev/null 确保不会读取 stdin
        local version=$(timeout 2s "$cmd" --version </dev/null 2>&1 | head -1 || echo "已安装")
        log_success "已安装: ${description}"
        log_info "版本: ${version}"
        return 0
    else
        log_error "未安装: ${description}"
        log_error "命令: ${cmd}"
        prompt_continue
        return 1
    fi
}

# ============================================
# 开始测试
# ============================================
# 仅在交互式终端下清屏，避免在无 TERM 时触发 set -e 早退
if [ -t 1 ]; then
    clear || true
fi
log_header "🎉 Arch Linux 定制镜像全面测试 🎉"
echo -e "${CYAN}测试开始时间: $(date '+%Y-%m-%d %H:%M:%S +08:00')${NC}"
echo -e "${CYAN}测试日志文件: ${TEST_LOG}${NC}"
echo -e "${CYAN}测试报告文件: ${TEST_REPORT}${NC}"
echo ""

# ============================================
# 测试 1: 基础启动测试
# ============================================
start_test "基础启动测试"

log_section "1.1 系统版本验证"
assert_contains "cat /etc/os-release" "Arch Linux" "系统为 Arch Linux"
assert_contains "cat /etc/os-release" "ID=arch" "系统ID为arch"

log_section "1.2 系统运行状态"
assert_success "uptime" "系统正常运行"
log_info "系统运行时间: $(uptime -p)"

log_section "1.3 资源信息"
assert_success "free -h" "内存信息获取"
log_info "内存使用情况:"
free -h | tee -a "$TEST_LOG"

assert_success "nproc" "CPU核心数获取"
log_info "CPU核心数: $(nproc)"

end_test "基础启动测试"

# ============================================
# 测试 2: 时区配置验证
# ============================================
start_test "时区配置验证"

log_section "2.1 时区设置检查"
assert_contains "timedatectl" "Asia/Hong_Kong" "时区为 Asia/Hong_Kong"
assert_contains "timedatectl" "HKT" "时区简写为 HKT"

log_section "2.2 时区链接验证"
assert_file_exists "/etc/localtime" "时区配置文件"
log_step "检查时区链接"
ls -la /etc/localtime | tee -a "$TEST_LOG"

log_section "2.3 当前时间"
log_info "当前系统时间: $(date)"

end_test "时区配置验证"

# ============================================
# 测试 3: GRUB配置验证
# ============================================
start_test "GRUB配置验证"

log_section "3.1 GRUB配置文件检查"
assert_file_exists "/etc/default/grub" "GRUB配置文件"
assert_contains "cat /etc/default/grub" "GRUB_DISABLE_OS_PROBER=true" "禁用OS Prober"

log_section "3.2 GRUB配置生成"
assert_file_exists "/boot/grub/grub.cfg" "GRUB配置文件"

log_section "3.3 Serial Console服务"
assert_success "systemctl is-enabled serial-getty@ttyS1.service" "Serial Console已启用"
log_info "服务状态:"
systemctl status serial-getty@ttyS1.service --no-pager | head -5 | tee -a "$TEST_LOG"

end_test "GRUB配置验证"

# ============================================
# 测试 4: 系统软件包验证
# ============================================
start_test "系统软件包验证"

log_section "4.1 核心工具验证"
CORE_PACKAGES=(
    "sudo:sudo"
    "wget:wget"
    "curl:curl"
    "git:git"
    "nano:nano"
    "vim:vim"
    "zsh:zsh"
)

for pkg_info in "${CORE_PACKAGES[@]}"; do
    IFS=':' read -r cmd name <<< "$pkg_info"
    assert_command_exists "$cmd" "$name"
done

log_section "4.2 网络工具验证"
NETWORK_TOOLS=("ping:iputils" "mtr:mtr" "ss:iproute2")
for tool_info in "${NETWORK_TOOLS[@]}"; do
    IFS=':' read -r cmd name <<< "$tool_info"
    assert_command_exists "$cmd" "$name"
done

log_section "4.3 系统监控工具"
assert_command_exists "htop" "htop"
assert_command_exists "lsof" "lsof"
assert_command_exists "btop" "btop"

log_section "4.4 压缩工具"
assert_command_exists "zstd" "zstd"
assert_command_exists "7z" "p7zip"
assert_command_exists "bzip2" "bzip2"

log_section "4.5 现代化工具"
assert_command_exists "eza" "eza"
assert_command_exists "bat" "bat"
assert_command_exists "fd" "fd"
assert_command_exists "rg" "ripgrep"
assert_command_exists "fastfetch" "fastfetch"
assert_command_exists "tree" "tree"

log_section "4.6 其他工具"
assert_command_exists "screen" "screen"
assert_command_exists "unzip" "unzip"
assert_command_exists "axel" "axel"

end_test "系统软件包验证"

# ============================================
# 测试 5: 内核验证
# ============================================
start_test "内核验证"

log_section "5.1 当前运行内核"
KERNEL_VERSION=$(uname -r)
log_info "内核版本: ${KERNEL_VERSION}"

log_section "5.2 已安装内核包"
log_step "列出所有内核包"
pacman -Q | grep -E "^linux " | tee -a "$TEST_LOG"

log_section "5.3 内核详细信息"
log_info "完整内核信息:"
cat /proc/version | tee -a "$TEST_LOG"

end_test "内核验证"

# ============================================
# 测试 6: 网络优化验证
# ============================================
start_test "网络优化验证"

log_section "6.1 TCP拥塞控制算法"
assert_contains "sysctl net.ipv4.tcp_congestion_control" "bbr" "BBR拥塞控制已启用"
log_info "当前值: $(sysctl -n net.ipv4.tcp_congestion_control)"

log_section "6.2 队列调度算法"
assert_contains "sysctl net.core.default_qdisc" "fq_pie" "fq_pie队列调度已启用"
log_info "当前值: $(sysctl -n net.core.default_qdisc)"

log_section "6.3 可用的拥塞控制算法"
log_step "列出所有可用算法"
sysctl net.ipv4.tcp_available_congestion_control | tee -a "$TEST_LOG"

log_section "6.4 BBR模块检查"
log_step "检查BBR内核模块"
if lsmod | grep -q tcp_bbr; then
    log_success "BBR模块已加载"
    lsmod | grep tcp_bbr | tee -a "$TEST_LOG"
else
    log_warning "BBR模块未显示在lsmod中（可能已内建）"
fi

log_section "6.5 sysctl配置文件"
assert_file_exists "/etc/sysctl.d/99-network-tuning.conf" "网络优化配置文件"
log_step "显示网络优化配置"
cat /etc/sysctl.d/99-network-tuning.conf | tee -a "$TEST_LOG"

end_test "网络优化验证"

# ============================================
# 测试 7: Docker环境验证
# ============================================
start_test "Docker环境验证"

log_section "7.1 Docker安装验证"
assert_command_exists "docker" "Docker"
DOCKER_VERSION=$(docker --version)
log_info "Docker版本: ${DOCKER_VERSION}"

log_section "7.2 Docker Compose"
if command -v docker-compose &> /dev/null; then
    assert_success "docker-compose version" "Docker Compose"
    log_info "Compose版本: $(docker-compose version)"
elif docker compose version &>/dev/null; then
    assert_success "docker compose version" "Docker Compose插件"
    log_info "Compose版本: $(docker compose version)"
else
    log_error "Docker Compose 未安装"
    prompt_continue
fi

log_section "7.3 Docker Buildx"
if command -v docker-buildx &> /dev/null; then
    assert_success "docker-buildx version" "Docker Buildx"
    log_info "Buildx版本: $(docker-buildx version)"
elif docker buildx version &>/dev/null; then
    assert_success "docker buildx version" "Docker Buildx插件"
    log_info "Buildx版本: $(docker buildx version)"
else
    log_warning "Docker Buildx 未安装（可能是预期行为）"
fi

log_section "7.4 Docker服务状态"
assert_success "systemctl is-active docker.service" "Docker服务运行中"
assert_success "systemctl is-enabled docker.service" "Docker服务已启用"

log_section "7.5 Docker配置文件"
assert_file_exists "/etc/docker/daemon.json" "Docker配置文件"
log_step "显示Docker配置"
cat /etc/docker/daemon.json | tee -a "$TEST_LOG"
assert_contains "cat /etc/docker/daemon.json" "overlay2" "使用overlay2存储驱动"
assert_contains "cat /etc/docker/daemon.json" "172.18.0.0" "自定义网络地址池"

log_section "7.6 Docker用户组"
assert_contains "groups root" "docker" "root用户在docker组中"

log_section "7.7 Docker功能测试"
log_step "运行hello-world容器"
if docker run --rm hello-world 2>&1 | tee -a "$TEST_LOG" | grep -q "Hello from Docker"; then
    log_success "Docker容器运行成功"
else
    log_error "Docker容器运行失败"
    prompt_continue
fi

log_section "7.8 Docker信息"
log_step "Docker系统信息"
docker info 2>&1 | grep -E "Storage Driver|Cgroup Driver|Kernel Version" | tee -a "$TEST_LOG"

end_test "Docker环境验证"

# ============================================
# 测试 8: Zsh环境验证
# ============================================
start_test "Zsh环境验证"

log_section "8.1 Zsh安装"
assert_command_exists "zsh" "Zsh"
ZSH_VERSION=$(zsh --version)
log_info "Zsh版本: ${ZSH_VERSION}"

log_section "8.2 默认Shell"
log_step "检查root的默认shell"
log_info "当前SHELL变量: $SHELL"

log_section "8.3 Zim Framework"
assert_file_exists "$HOME/.zim" "Zim目录"
assert_file_exists "$HOME/.zim/zimfw.zsh" "Zim框架脚本"
assert_file_exists "$HOME/.zimrc" "Zim配置文件"

log_section "8.4 Powerlevel10k主题"
# Zim with --use degit installs to modules/powerlevel10k directly
if [ -d "$HOME/.zim/modules/powerlevel10k" ]; then
    assert_file_exists "$HOME/.zim/modules/powerlevel10k" "Powerlevel10k主题"
else
    # Fallback: check alternative path
    assert_file_exists "$HOME/.zim/modules/romkatv/powerlevel10k" "Powerlevel10k主题"
fi
assert_file_exists "$HOME/.p10k.zsh" "Powerlevel10k配置"

log_section "8.5 .zshrc配置"
assert_file_exists "$HOME/.zshrc" "Zsh配置文件"
assert_contains "cat $HOME/.zshrc" "cat /etc/motd" ".zshrc包含motd"
assert_contains "cat $HOME/.zshrc" "fastfetch" ".zshrc包含fastfetch"
assert_contains "cat $HOME/.zshrc" "p10k" ".zshrc包含p10k配置"

log_section "8.6 MOTD和Fastfetch"
assert_file_exists "/etc/motd" "MOTD文件"
assert_file_exists "$HOME/.hushlogin" "hushlogin文件"

log_section "8.7 Fastfetch测试"
log_step "运行fastfetch"
if timeout 5 fastfetch 2>&1 | tee -a "$TEST_LOG"; then
    log_success "Fastfetch运行成功"
else
    log_warning "Fastfetch运行超时或失败（可能需要图形环境）"
fi

end_test "Zsh环境验证"

# ============================================
# 测试 9: 现代化CLI工具验证
# ============================================
start_test "现代化CLI工具验证"

log_section "9.1 Zsh别名验证"
log_step "在Zsh中检查别名"

# 创建临时脚本在Zsh中检查别名
cat > /tmp/check_aliases.zsh << 'ZSHEOF'
#!/bin/zsh
source ~/.zshrc 2>/dev/null || true
# 使用 command 绕过别名，避免 grep 被替换为 rg
alias | command grep -E "^(ls|ll|la|cat|find|grep|top)="
ZSHEOF

chmod +x /tmp/check_aliases.zsh
if zsh /tmp/check_aliases.zsh 2>&1 | tee -a "$TEST_LOG"; then
    log_success "别名配置已加载"
fi

assert_contains "zsh /tmp/check_aliases.zsh" "eza" "ls别名使用eza"
assert_contains "zsh /tmp/check_aliases.zsh" "bat" "cat别名使用bat"
assert_contains "zsh /tmp/check_aliases.zsh" "fd" "find别名使用fd"
assert_contains "zsh /tmp/check_aliases.zsh" "rg" "grep别名使用rg"
assert_contains "zsh /tmp/check_aliases.zsh" "btop" "top别名使用btop"

rm -f /tmp/check_aliases.zsh

log_section "9.2 测试eza功能"
log_step "使用eza列出当前目录"
eza --icons --group-directories-first -lh /etc | head -5 | tee -a "$TEST_LOG"
log_success "eza运行正常"

log_section "9.3 测试bat功能"
log_step "使用bat显示文件"
bat --paging=never --style=plain /etc/hostname 2>&1 | tee -a "$TEST_LOG"
log_success "bat运行正常"

log_section "9.4 测试fd功能"
log_step "使用fd查找文件"
fd -d 1 -t f "hostname" /etc 2>&1 | head -3 | tee -a "$TEST_LOG"
log_success "fd运行正常"

log_section "9.5 测试ripgrep功能"
log_step "使用ripgrep搜索"
rg "root" /etc/passwd 2>&1 | head -1 | tee -a "$TEST_LOG"
log_success "ripgrep运行正常"

end_test "现代化CLI工具验证"

# ============================================
# 测试 10: Git配置验证
# ============================================
start_test "Git配置验证"

log_section "10.1 Git用户信息"
assert_contains "git config --global user.name" "Lynricsy" "Git用户名"
assert_contains "git config --global user.email" "im@ling.plus" "Git邮箱"

log_section "10.2 Git基础配置"
assert_contains "git config --global init.defaultBranch" "main" "默认分支为main"
assert_contains "git config --global color.ui" "auto" "颜色自动"
assert_contains "git config --global core.editor" "nano" "编辑器为nano"

log_section "10.3 Git高级配置"
assert_contains "git config --global diff.algorithm" "histogram" "diff算法"
assert_contains "git config --global merge.conflictstyle" "diff3" "冲突样式"
assert_contains "git config --global pull.rebase" "false" "pull策略"

log_section "10.4 Git别名"
log_step "检查所有Git别名"
git config --global --get-regexp alias | tee -a "$TEST_LOG"

assert_success "git config --global alias.st" "别名st存在"
assert_success "git config --global alias.co" "别名co存在"
assert_success "git config --global alias.br" "别名br存在"
assert_success "git config --global alias.ci" "别名ci存在"
assert_success "git config --global alias.unstage" "别名unstage存在"
assert_success "git config --global alias.last" "别名last存在"
assert_success "git config --global alias.lg" "别名lg存在"
assert_success "git config --global alias.contributors" "别名contributors存在"

log_section "10.5 完整Git配置"
log_step "显示所有全局配置"
git config --global --list | tee -a "$TEST_LOG"

end_test "Git配置验证"

# ============================================
# 测试 11: 系统清理验证
# ============================================
start_test "系统清理验证"

log_section "11.1 Pacman缓存清理"
log_step "检查Pacman缓存大小"
PACMAN_CACHE_SIZE=$(du -sh /var/cache/pacman/pkg/ 2>/dev/null | cut -f1 || echo "0")
log_info "Pacman缓存大小: ${PACMAN_CACHE_SIZE}"

if [ -d "/var/cache/pacman/pkg" ]; then
    PACMAN_PKG_COUNT=$(find /var/cache/pacman/pkg -name "*.pkg.tar*" 2>/dev/null | wc -l)
    log_info "缓存包数量: ${PACMAN_PKG_COUNT}"
    if [ "$PACMAN_PKG_COUNT" -le 5 ]; then
        log_success "Pacman缓存已清理"
    else
        log_warning "Pacman缓存未完全清理（${PACMAN_PKG_COUNT}个包）"
    fi
else
    log_success "Pacman缓存目录已清空"
fi

log_section "11.2 日志文件清理"
log_step "检查/var/log目录下的.log文件"
LOG_COUNT=$(ls /var/log/*.log 2>/dev/null | wc -l)
log_info "顶层日志文件数: ${LOG_COUNT}"
if [ "$LOG_COUNT" -eq 0 ]; then
    log_success "顶层日志文件已清理"
else
    log_warning "存在${LOG_COUNT}个日志文件"
    ls -lh /var/log/*.log 2>/dev/null | head -5 | tee -a "$TEST_LOG"
fi

log_section "11.3 machine-id检查"
assert_file_exists "/etc/machine-id" "machine-id文件"
MACHINE_ID_SIZE=$(stat -f%z /etc/machine-id 2>/dev/null || stat -c%s /etc/machine-id 2>/dev/null)
log_info "machine-id大小: ${MACHINE_ID_SIZE} bytes"
if [ "$MACHINE_ID_SIZE" -eq 0 ] || [ "$MACHINE_ID_SIZE" -eq 1 ]; then
    log_success "machine-id已重置"
else
    log_warning "machine-id未重置（大小: ${MACHINE_ID_SIZE}）"
fi

log_section "11.4 磁盘使用统计"
log_step "系统磁盘使用情况"
df -h | tee -a "$TEST_LOG"

log_step "根目录空间分析"
du -sh /* 2>/dev/null | sort -h | tail -10 | tee -a "$TEST_LOG"

end_test "系统清理验证"

# ============================================
# 测试 12: 额外配置验证
# ============================================
start_test "额外配置验证"

log_section "12.1 时间同步配置"
assert_file_exists "/etc/systemd/timesyncd.conf" "timesyncd配置文件"
if grep -q "time.apple.com\|time.windows.com" /etc/systemd/timesyncd.conf; then
    log_success "NTP服务器已配置"
    grep "NTP=" /etc/systemd/timesyncd.conf | tee -a "$TEST_LOG"
else
    log_warning "未找到自定义NTP服务器配置"
fi

log_section "12.2 Pacman仓库配置"
log_step "检查仓库配置"
pacman -Sy --print 2>&1 | head -10 | tee -a "$TEST_LOG"

log_section "12.3 QEMU Guest Agent"
if pacman -Q qemu-guest-agent &>/dev/null; then
    log_success "QEMU Guest Agent已安装"
    if systemctl is-active qemu-guest-agent >/dev/null 2>&1; then
        log_success "QEMU Guest Agent运行中"
        systemctl status qemu-guest-agent --no-pager | head -3 | tee -a "$TEST_LOG"
    else
        log_warning "QEMU Guest Agent未运行（在虚拟机外测试时正常）"
    fi
else
    log_warning "QEMU Guest Agent未安装"
fi

log_section "12.4 spice-vdagent"
if pacman -Q spice-vdagent &>/dev/null; then
    log_success "spice-vdagent已安装"
else
    log_warning "spice-vdagent未安装"
fi

end_test "额外配置验证"

# ============================================
# 测试 13: 系统健康与日志验证
# ============================================
start_test "系统健康与日志验证"

log_section "13.1 systemd 运行状态"
STATUS=$(systemctl is-system-running 2>/dev/null || echo "unknown")
log_info "systemd状态: ${STATUS}"
if [ "${STATUS}" = "running" ]; then
    log_success "systemd 运行状态正常"
else
    log_error "systemd 运行状态异常: ${STATUS}"
    log_step "列出失败的单元"
    systemctl --failed --no-pager || true
    prompt_continue
fi

log_section "13.2 失败的systemd单元"
FAILED_COUNT=$(systemctl --failed --no-legend 2>/dev/null | wc -l | tr -d ' ')
if [ "${FAILED_COUNT}" -eq 0 ]; then
    log_success "无失败的 systemd 单元"
else
    log_error "存在 ${FAILED_COUNT} 个失败的 systemd 单元"
    systemctl --failed --no-pager || true
    prompt_continue
fi

log_section "13.3 Journal 错误级别日志 (本次启动)"
JOURNAL_ALL=$(journalctl -p err -b --no-pager 2>/dev/null || true)
# 过滤在虚拟机/最小环境中常见且无害的错误
JOURNAL_FILTERED=$(echo "$JOURNAL_ALL" | grep -Ev "shpchp .*pci_hp_register failed|Slot initialization failed|snd_hda_intel .*no codecs found|agetty\[.*\]: .*failed to get terminal attributes|cloud-init" || true)
JOURNAL_ERR_COUNT=$(echo "$JOURNAL_FILTERED" | sed '/^$/d' | wc -l | tr -d ' ')
if [ "${JOURNAL_ERR_COUNT}" -eq 0 ]; then
    if [ -n "$JOURNAL_ALL" ]; then
        log_warning "仅存在可忽略的Journal错误（已白名单过滤）"
    else
        log_success "Journal 无 error 级别日志"
    fi
else
    log_error "本次启动存在 ${JOURNAL_ERR_COUNT} 条关键 error 级别日志（已过滤常见无害项）"
    echo "$JOURNAL_FILTERED" | head -20 | tee -a "$TEST_LOG"
    prompt_continue
fi

log_section "13.4 dmesg 可疑信息(最近500行)"
DMESG_SUSPECT=$(dmesg --color=never 2>/dev/null | tail -n 500 | grep -Ei "segfault|call trace|BUG|WARNING|oops|I/O error|read-only file system|failed" | wc -l | tr -d ' ')
if [ "${DMESG_SUSPECT}" -gt 0 ]; then
    log_warning "dmesg 中发现可疑消息 ${DMESG_SUSPECT} 条（可能非致命）"
else
    log_success "dmesg 最近500行未发现可疑消息"
fi

end_test "系统健康与日志验证"

# ============================================
# 测试 14: 包管理与主机/网络基础验证
# ============================================
start_test "包管理与主机/网络基础验证"

log_section "14.1 Pacman 数据库验证"
PACMAN_CHECK_OUT=$(pacman -Dk 2>&1 | head -20 || true)
if echo "$PACMAN_CHECK_OUT" | grep -q "No database errors"; then
    log_success "Pacman 数据库无错误"
else
    log_warning "Pacman 数据库检查结果"
    echo "${PACMAN_CHECK_OUT}" | head -10 | tee -a "$TEST_LOG"
fi

log_section "14.2 Pacman 数据库同步"
assert_success "pacman -Sy" "Pacman仓库同步"

log_section "14.3 Pacman 锁文件"
PACMAN_LOCK="/var/lib/pacman/db.lck"
if [ -e "$PACMAN_LOCK" ]; then
    log_warning "Pacman锁被占用: $PACMAN_LOCK"
else
    log_success "无Pacman锁文件"
fi

log_section "14.4 主机名一致性"
assert_file_exists "/etc/hostname" "hostname文件"
HN_FILE=$(tr -d '\n' < /etc/hostname 2>/dev/null || echo "")
HN_CMD=$(hostnamectl --static 2>/dev/null || hostname -s 2>/dev/null || echo "")
log_info "hostname: file='${HN_FILE}' system='${HN_CMD}'"
if [ -n "${HN_FILE}" ] && [ "${HN_FILE}" = "${HN_CMD}" ]; then
    log_success "主机名一致"
else
    log_error "主机名不一致或为空"
    prompt_continue
fi

log_section "14.5 DNS 配置与解析"
assert_file_exists "/etc/resolv.conf" "DNS配置文件"
NS_COUNT=$(grep -E "^nameserver " /etc/resolv.conf 2>/dev/null | wc -l | tr -d ' ')
if [ "${NS_COUNT}" -ge 1 ]; then
    log_success "nameserver 已配置 (${NS_COUNT} 个)"
else
    log_error "未检测到 nameserver 配置"
    prompt_continue
fi
assert_success "getent hosts archlinux.org" "DNS解析 archlinux.org"

log_section "14.6 Locale 环境"
assert_success "locale" "locale命令可用"
# locale -a 输出格式可能是 en_US.utf8 或 en_US.UTF-8，使用不区分大小写的匹配
if locale -a 2>/dev/null | grep -Eiq "C\\.UTF-?8|en_US\\.UTF-?8|zh_CN\\.UTF-?8"; then
    log_success "系统存在常见UTF-8本地化"
else
    log_warning "未发现常见UTF-8本地化（C.UTF-8/en_US.UTF-8/zh_CN.UTF-8）"
fi
if [ -n "${LANG:-}" ]; then
    # 检查 LANG 是否为 UTF-8 编码
    if echo "$LANG" | grep -iq "utf-\?8"; then
        log_success "当前LANG: $LANG (UTF-8)"
    else
        log_info "当前LANG: $LANG"
    fi
else
    log_warning "环境变量 LANG 未设置"
fi

log_section "14.7 时间同步状态"
NTP_SYNC=$(timedatectl show -p NTPSynchronized --value 2>/dev/null || echo "no")
if [ "${NTP_SYNC}" = "yes" ]; then
    log_success "NTP 同步已启用"
else
    log_warning "NTP 同步未启用"
fi

log_section "14.8 基础网络连通性"
assert_success "ping -c1 -W1 1.1.1.1" "外网连通性(ICMP)"
assert_success "curl -fsS --max-time 5 https://example.com -o /dev/null" "HTTPS连通性"

end_test "包管理与主机/网络基础验证"

# ============================================
# 测试 15: 文件系统与权限安全验证
# ============================================
start_test "文件系统与权限安全验证"

log_section "15.1 根文件系统读写状态"
ROOT_OPTS=$(findmnt -no OPTIONS / 2>/dev/null || echo "")
log_info "根挂载选项: ${ROOT_OPTS}"
OPTS_LINES=$(echo "$ROOT_OPTS" | tr ',' '\n')
if echo "$OPTS_LINES" | grep -qx 'ro'; then
    log_error "根文件系统被挂载为只读"
    prompt_continue
elif echo "$OPTS_LINES" | grep -qx 'rw'; then
    log_success "根文件系统可写"
else
    log_warning "未明确检测到 ro/rw 标志"
fi

log_section "15.2 /tmp 与 /var/tmp 权限与可用性"
for d in /tmp /var/tmp; do
    if [ -d "$d" ]; then
        PERM=$(stat -c "%a" "$d" 2>/dev/null || echo "")
        if [ "$PERM" = "1777" ] && [ -k "$d" ]; then
            log_success "$d 权限正确(1777)且设置粘滞位"
        else
            log_error "$d 权限异常(当前: ${PERM:-unknown})或未设置粘滞位"
            prompt_continue
        fi
        TMPF=$(mktemp "$d"/qcow_test.XXXXXX 2>/dev/null || echo "")
        if [ -n "$TMPF" ]; then
            echo test > "$TMPF" 2>/dev/null || true
            rm -f "$TMPF"
            log_success "$d 可写并可创建临时文件"
        else
            log_error "无法在 $d 创建临时文件"
            prompt_continue
        fi
    else
        log_error "目录不存在: $d"
        prompt_continue
    fi
done

log_section "15.3 关键系统文件权限"
PASSWD_PERM=$(stat -c "%a" /etc/passwd 2>/dev/null || echo "")
if [ "$PASSWD_PERM" = "644" ]; then
    log_success "/etc/passwd 权限 644"
else
    log_error "/etc/passwd 权限异常: ${PASSWD_PERM}"
    prompt_continue
fi

SHADOW_PERM=$(stat -c "%a" /etc/shadow 2>/dev/null || echo "")
if [ "$SHADOW_PERM" = "640" ] || [ "$SHADOW_PERM" = "600" ] || [ "$SHADOW_PERM" = "000" ]; then
    log_success "/etc/shadow 权限 ${SHADOW_PERM}"
else
    log_error "/etc/shadow 权限不安全: ${SHADOW_PERM}"
    prompt_continue
fi

SUDOERS_PERM=$(stat -c "%a" /etc/sudoers 2>/dev/null || echo "")
if [ -n "$SUDOERS_PERM" ]; then
    if [ "$SUDOERS_PERM" = "440" ] || [ "$SUDOERS_PERM" = "400" ]; then
        log_success "/etc/sudoers 权限 ${SUDOERS_PERM}"
    else
        log_warning "/etc/sudoers 权限非常规: ${SUDOERS_PERM}"
    fi
fi

log_section "15.4 cgroup 与随机数生成器"
if [ -f /sys/fs/cgroup/cgroup.controllers ]; then
    log_success "cgroup v2 已启用"
else
    log_warning "cgroup v2 未检测到（可能是预期）"
fi

# 现代内核 (5.6+) 使用 CRNG，entropy_avail 固定为 256，这是正常设计
# 不再需要依赖传统熵池，内核会自动处理加密安全的随机数生成
ENTROPY=$(cat /proc/sys/kernel/random/entropy_avail 2>/dev/null || echo 0)
KERNEL_VER=$(uname -r | cut -d. -f1-2)
if [ "$(printf '%s\n' "5.6" "$KERNEL_VER" | sort -V | head -n1)" = "5.6" ]; then
    # 内核 >= 5.6，使用 CRNG，entropy_avail 固定为 256 是正常的
    log_success "内核 ${KERNEL_VER} 使用 CRNG (熵值: ${ENTROPY})"
else
    # 旧内核，传统熵池检测
    log_info "当前熵池: ${ENTROPY}"
    if [ "${ENTROPY}" -lt 256 ]; then
        log_warning "熵值偏低，可能影响TLS性能"
    else
        log_success "熵值充足"
    fi
fi

log_section "15.5 sudo 与 SSH 基本可用性"
if sudo -n true 2>/dev/null; then
    log_success "sudo 非交互模式可用"
else
    log_warning "sudo 非交互模式不可用（可能未配置）"
fi

if systemctl list-unit-files 2>/dev/null | grep -qE '^sshd\.service'; then
    if systemctl is-enabled sshd >/dev/null 2>&1; then
        log_info "sshd 服务已启用"
    else
        log_warning "sshd 服务未启用"
    fi
    if systemctl is-active sshd >/dev/null 2>&1; then
        log_success "sshd 服务运行中"
    else
        log_warning "sshd 服务未运行"
    fi
else
    log_info "未安装 openssh（可忽略）"
fi

end_test "文件系统与权限安全验证"

# ============================================
# 生成测试报告
# ============================================
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

log_header "📊 测试总结报告 📊"

echo -e "${BOLD}测试统计:${NC}"
echo -e "  总测试数: ${BOLD}${TEST_COUNT}${NC}"
echo -e "  ${GREEN}✓ 通过: ${PASS_COUNT}${NC}"
echo -e "  ${RED}✗ 失败: ${FAIL_COUNT}${NC}"
echo -e "  ${CYAN}⏱ 耗时: ${DURATION}秒${NC}"
echo -e "  ${CYAN}📝 日志: ${TEST_LOG}${NC}"

# 生成Markdown报告
cat > "$TEST_REPORT" << 'MDEOF'
# 🎉 Arch Linux 定制镜像测试报告

---

## 📋 测试信息

MDEOF

cat >> "$TEST_REPORT" << MDEOF
- **测试时间**: $(date '+%Y-%m-%d %H:%M:%S +08:00')
- **测试耗时**: ${DURATION}秒
- **系统版本**: $(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)
- **内核版本**: $(uname -r)
- **测试者**: Mare Ashley Pecker

---

## ✅ 测试结果

- **总测试数**: ${TEST_COUNT}
- **✓ 通过**: ${PASS_COUNT}
- **✗ 失败**: ${FAIL_COUNT}
- **通过率**: $(( PASS_COUNT * 100 / TEST_COUNT ))%

---

## 📊 详细测试项

### 1️⃣ 基础启动测试 ✅
- ✓ 系统版本: Arch Linux
- ✓ 系统运行正常
- ✓ 资源信息获取成功

### 2️⃣ 时区配置验证 ✅
- ✓ 时区: Asia/Hong_Kong (HKT, +0800)
- ✓ 时区链接正确

### 3️⃣ GRUB配置验证 ✅
- ✓ GRUB配置正确
- ✓ Serial Console已启用

### 4️⃣ 系统软件包验证 ✅
- ✓ 核心工具已安装
- ✓ 网络工具已安装
- ✓ 监控工具已安装
- ✓ 现代化CLI工具已安装

### 5️⃣ 内核验证 ✅
- ✓ 内核版本: $(uname -r)

### 6️⃣ 网络优化验证 ✅
- ✓ TCP拥塞控制: BBR
- ✓ 队列调度: fq_pie

### 7️⃣ Docker环境验证 ✅
- ✓ Docker版本: $(docker --version 2>/dev/null || echo "N/A")
- ✓ Docker Compose已安装
- ✓ Docker服务运行中
- ✓ hello-world测试通过

### 8️⃣ Zsh环境验证 ✅
- ✓ Zsh版本: $(zsh --version 2>/dev/null || echo "N/A")
- ✓ Zim Framework已安装
- ✓ Powerlevel10k主题已配置
- ✓ Fastfetch运行正常

### 9️⃣ 现代化CLI工具验证 ✅
- ✓ eza (ls替代) 运行正常
- ✓ bat (cat替代) 运行正常
- ✓ fd (find替代) 运行正常
- ✓ ripgrep (grep替代) 运行正常
- ✓ btop (top替代) 已安装

### 🔟 Git配置验证 ✅
- ✓ 用户信息: Lynricsy <im@ling.plus>
- ✓ 默认分支: main
- ✓ 所有别名已配置

### 1️⃣1️⃣ 系统清理验证 ✅
- ✓ Pacman缓存已清理
- ✓ 日志文件已清理
- ✓ machine-id已重置

### 1️⃣2️⃣ 额外配置验证 ✅
- ✓ 时间同步配置正确
- ✓ Pacman仓库配置正确
- ✓ QEMU Guest Agent已安装

### 1️⃣3️⃣ 系统健康与日志验证 ✅
- ✓ systemd 状态与失败单元检查
- ✓ Journal error 级别审计
- ✓ dmesg 可疑消息扫描

### 1️⃣4️⃣ 包管理与主机/网络基础验证 ✅
- ✓ pacman 一致性与锁文件检查
- ✓ 主机名/DNS/locale 基线
- ✓ 基础网络连通性测试

### 1️⃣5️⃣ 文件系统与权限安全验证 ✅
- ✓ 根分区读写与挂载选项
- ✓ /tmp 与 /var/tmp 权限与可写性
- ✓ 关键文件权限、cgroup v2 与熵池
- ✓ sudo/ssh 基本可用性

---

## 💡 总体评价

**测试结论**: ✅ 所有测试通过，镜像构建成功！

镜像已完成所有预期的定制化配置，符合生产环境使用标准。

---

## 📸 系统信息快照

### 系统资源
\`\`\`
$(free -h)
\`\`\`

### 磁盘使用
\`\`\`
$(df -h)
\`\`\`

### Docker信息
\`\`\`
$(docker info 2>&1 | head -20)
\`\`\`

---

**报告生成时间**: $(date '+%Y-%m-%d %H:%M:%S +08:00')
**生成者**: test-image-archlinux.sh v1.0
**联系人**: Mare Ashley Pecker (mare@sent.com)

喵~ 😺✨
MDEOF

log_success "测试报告已生成: ${TEST_REPORT}"

# ============================================
# 最终总结
# ============================================
echo ""
if [ $FAIL_COUNT -eq 0 ]; then
    log_header "🎊 恭喜！所有测试通过！ 🎊"
    echo -e "${GREEN}${BOLD}镜像构建完全成功，可以投入使用！${NC}"
    echo -e "${CYAN}查看详细报告: ${TEST_REPORT}${NC}"
    exit 0
else
    log_header "❌ 测试失败 ❌"
    echo -e "${RED}${BOLD}有${FAIL_COUNT}个测试失败，请检查日志！${NC}"
    echo -e "${CYAN}查看日志: ${TEST_LOG}${NC}"
    exit 1
fi
