#!/bin/bash
# 一键构建脚本 - 使用 HashiCorp Packer 构建定制镜像
# 创建时间: 2025-12-14
# 创建者: Mare Ashley Pecker (mare@sent.com)
# 说明: 支持构建 CachyOS、Arch Linux、openSUSE Tumbleweed 镜像

set -e

# ============================================================
# 颜色定义
# ============================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ============================================================
# 日志函数
# ============================================================
log_info() {
    echo -e "${CYAN}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_step() {
    echo -e "${PURPLE}[STEP]${NC} $1"
}

# ============================================================
# 脚本目录
# ============================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="${SCRIPT_DIR}/output"
FORCE_BUILD=false

# ============================================================
# 使用帮助
# ============================================================
show_help() {
    cat << EOF
🐱 Mare's Image Packer - 一键构建定制镜像

使用方法:
    $0 [选项] <发行版...>

发行版:
    cachyos     构建 CachyOS 镜像 (基于 Arch + 优化内核)
    archlinux   构建 Arch Linux 镜像
    opensuse    构建 openSUSE Tumbleweed 镜像
    all         构建所有发行版

选项:
    -h, --help          显示此帮助信息
    -o, --output DIR    指定输出目录 (默认: ./output)
    -p, --parallel      并行构建多个发行版
    -v, --validate      仅验证配置，不执行构建
    -c, --clean         清理输出目录 (可指定发行版，如 -c cachyos)
    -f, --force         强制覆盖已存在的输出目录
    --init              安装依赖并初始化 Packer 插件

示例:
    $0 cachyos              # 构建 CachyOS 镜像
    $0 archlinux opensuse   # 构建 Arch Linux 和 openSUSE 镜像
    $0 -p all               # 并行构建所有镜像
    $0 --init               # 安装依赖并初始化 Packer 插件
    $0 -v all               # 验证所有配置
    $0 -c                   # 清理所有输出目录
    $0 -c cachyos           # 只清理 CachyOS 输出目录
    $0 -f cachyos           # 强制覆盖已存在的输出目录

EOF
}

# ============================================================
# 检查依赖
# ============================================================
check_dependencies() {
    log_step "检查依赖..."

    local missing=()

    # 检查 packer
    if ! command -v packer &> /dev/null; then
        missing+=("packer")
    fi

    # 检查 qemu-img
    if ! command -v qemu-img &> /dev/null; then
        missing+=("qemu-img (qemu-utils)")
    fi

    # 检查 virt-customize
    if ! command -v virt-customize &> /dev/null; then
        missing+=("virt-customize (libguestfs-tools)")
    fi

    # 检查 KVM 支持
    if [ ! -e /dev/kvm ]; then
        log_warning "/dev/kvm 不存在，可能无法使用 KVM 加速"
    fi

    if [ ${#missing[@]} -gt 0 ]; then
        log_error "缺少以下依赖:"
        for dep in "${missing[@]}"; do
            echo "  - $dep"
        done
        echo ""
        log_info "请安装缺少的依赖后重试"
        log_info "Arch/CachyOS: pacman -S packer qemu-base libguestfs"
        log_info "Debian/Ubuntu: $0 --init (自动安装)"
        log_info "openSUSE: zypper install packer qemu-tools guestfs-tools"
        exit 1
    fi

    log_success "依赖检查通过 ✓"
}

# ============================================================
# 安装依赖 (支持多发行版)
# ============================================================
install_dependencies() {
    log_step "安装依赖..."

    # 检测发行版
    local distro=""
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        distro="$ID"
    fi

    case "$distro" in
        debian|ubuntu)
            log_info "检测到 Debian/Ubuntu 系统"
            install_dependencies_debian
            ;;
        arch|cachyos|endeavouros|manjaro)
            log_info "检测到 Arch 系列系统"
            install_dependencies_arch
            ;;
        opensuse*|suse)
            log_info "检测到 openSUSE 系统"
            install_dependencies_opensuse
            ;;
        fedora|rhel|centos|rocky|almalinux)
            log_info "检测到 RHEL 系列系统"
            install_dependencies_rhel
            ;;
        *)
            log_error "不支持的发行版: $distro"
            log_info "请手动安装: packer, qemu-utils/qemu-img, libguestfs-tools/guestfs-tools"
            exit 1
            ;;
    esac

    log_success "依赖安装完成 ✓"
}

# Debian/Ubuntu 安装
install_dependencies_debian() {
    # 检查是否需要安装 Packer
    if ! command -v packer &> /dev/null; then
        log_info "从 HashiCorp 官方源安装 Packer..."

        # 添加 HashiCorp GPG key
        if [ ! -f /usr/share/keyrings/hashicorp-archive-keyring.gpg ]; then
            curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
        fi

        # 获取 codename，如果是 testing/sid 则使用 bookworm
        local codename
        codename=$(lsb_release -cs 2>/dev/null || echo "bookworm")
        # 检查 codename 是否在 HashiCorp 支持列表中
        case "$codename" in
            bullseye|bookworm|jammy|focal|noble)
                # 支持的版本
                ;;
            *)
                # 不支持的版本，回退到 bookworm
                log_warning "Codename '$codename' 可能不被 HashiCorp 支持，使用 bookworm"
                codename="bookworm"
                ;;
        esac

        # 添加仓库
        echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $codename main" | \
            sudo tee /etc/apt/sources.list.d/hashicorp.list

        sudo apt update
    fi

    # 安装所有依赖
    sudo apt install -y packer qemu-utils libguestfs-tools
}

# Arch 系列安装
install_dependencies_arch() {
    sudo pacman -Syu --noconfirm
    sudo pacman -S --noconfirm --needed packer qemu-base libguestfs
}

# openSUSE 安装
install_dependencies_opensuse() {
    sudo zypper --non-interactive refresh
    sudo zypper --non-interactive install packer qemu-tools guestfs-tools
}

# RHEL 系列安装
install_dependencies_rhel() {
    # 添加 HashiCorp 仓库
    if ! command -v packer &> /dev/null; then
        log_info "从 HashiCorp 官方源安装 Packer..."
        sudo yum install -y yum-utils
        sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo
    fi

    sudo yum install -y packer qemu-img libguestfs-tools
}

# ============================================================
# 初始化 Packer 插件
# ============================================================
init_packer() {
    log_step "初始化 Packer 插件..."

    local dirs=("cachyos" "archlinux" "opensuse")

    for dir in "${dirs[@]}"; do
        if [ -d "${SCRIPT_DIR}/${dir}" ]; then
            log_info "初始化 ${dir}..."
            (cd "${SCRIPT_DIR}/${dir}" && packer init .)
        fi
    done

    log_success "Packer 插件初始化完成 ✓"
}

# ============================================================
# 验证配置
# ============================================================
validate_config() {
    local distro="$1"
    local distro_dir="${SCRIPT_DIR}/${distro}"

    if [ ! -d "$distro_dir" ]; then
        log_error "发行版目录不存在: $distro_dir"
        return 1
    fi

    log_info "验证 ${distro} 配置..."
    (cd "$distro_dir" && packer validate .)

    if [ $? -eq 0 ]; then
        log_success "${distro} 配置验证通过 ✓"
        return 0
    else
        log_error "${distro} 配置验证失败"
        return 1
    fi
}

# ============================================================
# 构建镜像
# ============================================================
build_image() {
    local distro="$1"
    local distro_dir="${SCRIPT_DIR}/${distro}"
    local output_subdir="${OUTPUT_DIR}/${distro}"

    if [ ! -d "$distro_dir" ]; then
        log_error "发行版目录不存在: $distro_dir"
        return 1
    fi

    log_step "开始构建 ${distro} 镜像..."
    echo ""

    # 创建输出目录
    mkdir -p "$output_subdir"

    # 构建 packer 命令参数
    local packer_args=(-var "output_directory=${output_subdir}")
    if $FORCE_BUILD; then
        packer_args+=(-force)
    fi

    # 执行构建
    (cd "$distro_dir" && packer build "${packer_args[@]}" .)

    if [ $? -eq 0 ]; then
        echo ""
        log_success "${distro} 镜像构建完成 ✓"
        return 0
    else
        echo ""
        log_error "${distro} 镜像构建失败"
        return 1
    fi
}

# ============================================================
# 并行构建
# ============================================================
build_parallel() {
    local distros=("$@")
    local pids=()
    local results=()

    log_step "并行构建 ${#distros[@]} 个发行版..."

    for distro in "${distros[@]}"; do
        build_image "$distro" &
        pids+=($!)
    done

    # 等待所有构建完成
    local i=0
    for pid in "${pids[@]}"; do
        wait $pid
        results+=($?)
        i=$((i + 1))
    done

    # 汇总结果
    echo ""
    echo "================================================"
    log_info "构建结果汇总:"
    local all_success=true
    for i in "${!distros[@]}"; do
        if [ "${results[$i]}" -eq 0 ]; then
            echo -e "  ${GREEN}✓${NC} ${distros[$i]}"
        else
            echo -e "  ${RED}✗${NC} ${distros[$i]}"
            all_success=false
        fi
    done
    echo "================================================"

    if $all_success; then
        return 0
    else
        return 1
    fi
}

# ============================================================
# 清理输出目录
# ============================================================
clean_output() {
    local distros=("$@")

    log_step "清理输出目录..."

    # 如果指定了发行版，只清理对应的子目录
    if [ ${#distros[@]} -gt 0 ]; then
        for distro in "${distros[@]}"; do
            local distro_output="${OUTPUT_DIR}/${distro}"
            if [ -d "$distro_output" ]; then
                rm -rf "$distro_output"
                log_success "已清理: $distro_output"
            else
                log_info "目录不存在，跳过: $distro_output"
            fi
        done
    else
        # 清理整个输出目录
        if [ -d "$OUTPUT_DIR" ]; then
            rm -rf "$OUTPUT_DIR"
            log_success "输出目录已清理: $OUTPUT_DIR"
        else
            log_info "输出目录不存在，无需清理"
        fi
    fi
}

# ============================================================
# 主函数
# ============================================================
main() {
    local distros=()
    local parallel=false
    local validate_only=false
    local do_init=false
    local do_clean=false

    # 解析参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -o|--output)
                OUTPUT_DIR="$2"
                shift 2
                ;;
            -p|--parallel)
                parallel=true
                shift
                ;;
            -v|--validate)
                validate_only=true
                shift
                ;;
            -c|--clean)
                do_clean=true
                shift
                ;;
            -f|--force)
                FORCE_BUILD=true
                shift
                ;;
            --init)
                do_init=true
                shift
                ;;
            all)
                distros=("cachyos" "archlinux" "opensuse")
                shift
                ;;
            cachyos|archlinux|opensuse)
                distros+=("$1")
                shift
                ;;
            *)
                log_error "未知参数: $1"
                show_help
                exit 1
                ;;
        esac
    done

    # 显示 banner
    echo ""
    echo -e "${PURPLE}╔═══════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║${NC}    🐱 ${CYAN}Mare's Image Packer${NC}                     ${PURPLE}║${NC}"
    echo -e "${PURPLE}║${NC}    ${YELLOW}HashiCorp Packer + virt-customize${NC}         ${PURPLE}║${NC}"
    echo -e "${PURPLE}╚═══════════════════════════════════════════════╝${NC}"
    echo ""

    # 执行清理
    if $do_clean; then
        clean_output "${distros[@]}"
        exit 0
    fi

    # 执行初始化 (安装依赖 + 初始化插件)
    if $do_init; then
        install_dependencies
        check_dependencies
        init_packer
        exit 0
    fi

    # 检查依赖
    check_dependencies

    # 确保有发行版参数
    if [ ${#distros[@]} -eq 0 ]; then
        log_error "请指定要构建的发行版"
        echo ""
        show_help
        exit 1
    fi

    # 验证模式
    if $validate_only; then
        local all_valid=true
        for distro in "${distros[@]}"; do
            validate_config "$distro" || all_valid=false
        done
        if $all_valid; then
            log_success "所有配置验证通过 ✓"
            exit 0
        else
            exit 1
        fi
    fi

    # 确保脚本可执行
    chmod +x "${SCRIPT_DIR}/scripts/common-provision.sh" 2>/dev/null || true
    chmod +x "${SCRIPT_DIR}/scripts/final-cleanup.sh" 2>/dev/null || true

    # 构建镜像
    if $parallel && [ ${#distros[@]} -gt 1 ]; then
        build_parallel "${distros[@]}"
    else
        local all_success=true
        for distro in "${distros[@]}"; do
            build_image "$distro" || all_success=false
        done

        echo ""
        echo "================================================"
        if $all_success; then
            log_success "所有镜像构建完成 ✓"
            log_info "输出目录: $OUTPUT_DIR"
        else
            log_error "部分镜像构建失败"
        fi
        echo "================================================"
    fi
}

# 执行主函数
main "$@"
