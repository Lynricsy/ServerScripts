#!/bin/bash
# Cloud-init 本地测试脚本
# 用于快速验证镜像的 cloud-init 功能，无需转移到 PVE

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${CYAN}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 默认配置
IMAGE_FILE="${1:-CachyOS-NEXT.qcow2}"
TEST_USER="cloudtest"
TEST_PASSWORD="testpass123"
SSH_PORT="2222"
MEMORY="2048"

# 检查镜像文件
if [ ! -f "$IMAGE_FILE" ]; then
    log_error "镜像文件不存在: $IMAGE_FILE"
    echo "用法: $0 [镜像文件路径]"
    exit 1
fi

log_info "🧪 Cloud-init 本地测试工具"
echo "========================================"
log_info "测试镜像: $IMAGE_FILE"
log_info "测试用户: $TEST_USER"
log_info "测试密码: $TEST_PASSWORD"
log_info "SSH 端口: $SSH_PORT (本地转发)"
echo ""

# 创建临时目录
CIDATA_DIR=$(mktemp -d)
CIDATA_ISO=$(mktemp --suffix=.iso)
trap "rm -rf $CIDATA_DIR $CIDATA_ISO" EXIT

log_info "📝 创建 cloud-init 配置..."

# meta-data
cat > "$CIDATA_DIR/meta-data" << 'EOF'
instance-id: test-instance-local
local-hostname: cloudinit-test
EOF

# user-data
cat > "$CIDATA_DIR/user-data" << EOF
#cloud-config
users:
  - name: $TEST_USER
    sudo: ALL=(ALL) NOPASSWD:ALL
    groups: [wheel]
    shell: /bin/bash
    lock_passwd: false
chpasswd:
  list: |
    $TEST_USER:$TEST_PASSWORD
  expire: false
ssh_pwauth: true
disable_root: false
EOF

log_info "💿 生成 cloud-init ISO..."
genisoimage -output "$CIDATA_ISO" -volid cidata -joliet -rock \
    "$CIDATA_DIR/meta-data" "$CIDATA_DIR/user-data" 2>/dev/null

log_success "ISO 创建完成: $CIDATA_ISO"
echo ""

# 创建临时测试镜像（不修改原镜像）
TEST_IMAGE=$(mktemp --suffix=.qcow2)
trap "rm -rf $CIDATA_DIR $CIDATA_ISO $TEST_IMAGE" EXIT

log_info "📀 创建测试用镜像副本（基于原镜像的 overlay）..."
qemu-img create -f qcow2 -b "$(realpath "$IMAGE_FILE")" -F qcow2 "$TEST_IMAGE"

echo ""
echo "========================================"
log_success "🚀 启动 QEMU 虚拟机测试"
echo "========================================"
echo ""
log_info "📌 登录信息:"
echo "   用户名: $TEST_USER"
echo "   密码: $TEST_PASSWORD"
echo ""
log_info "📌 SSH 测试 (另开终端执行):"
echo "   ssh -o StrictHostKeyChecking=no -p $SSH_PORT $TEST_USER@localhost"
echo ""
log_info "📌 退出虚拟机:"
echo "   输入 'poweroff' 或按 Ctrl+A 然后按 X"
echo ""
log_warn "⏳ 等待 cloud-init 完成配置（约 30-60 秒）..."
echo "========================================"
echo ""

# 启动 QEMU
qemu-system-x86_64 \
    -enable-kvm \
    -m "$MEMORY" \
    -cpu host \
    -smp 2 \
    -drive file="$TEST_IMAGE",format=qcow2,if=virtio \
    -drive file="$CIDATA_ISO",format=raw,if=virtio \
    -netdev user,id=net0,hostfwd=tcp::${SSH_PORT}-:22 \
    -device virtio-net-pci,netdev=net0 \
    -nographic \
    -serial mon:stdio

echo ""
log_success "✅ 测试完成！"
