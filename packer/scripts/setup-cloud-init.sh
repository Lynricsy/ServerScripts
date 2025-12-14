#!/bin/bash
# CachyOS cloud-init 配置脚本
# 功能：配置 cloud-init 兼容性（针对 Proxmox/私有云环境）
# 创建者: Mare Ashley Pecker

set -euo pipefail

echo '☁️ 配置 cloud-init...'

# 移除禁用标记
sudo rm -f /etc/cloud/cloud-init.disabled || true

# 创建配置目录
sudo install -d -m 0755 /etc/cloud/cloud.cfg.d

# 创建 Proxmox 兼容配置
cat <<'EOF' | sudo tee /etc/cloud/cloud.cfg.d/99-proxmox.cfg
# Proxmox / NoCloud / ConfigDrive 兼容性增强
# 注意: 此配置针对 Proxmox/私有云环境，公有云部署需删除此文件
datasource_list: [ NoCloud, ConfigDrive, None ]
EOF

# 智能检测并启用 cloud-init 服务
echo '🔧 智能检测并启用 cloud-init 服务...'

declare -a services=(
  'cloud-init-local.service'
  'cloud-init.service'
  'cloud-init-main.service'
  'cloud-config.service'
  'cloud-final.service'
  'cloud-init.target'
)

enabled_count=0
skipped_count=0

for svc in "${services[@]}"; do
  # 检查服务单元文件是否存在
  if systemctl list-unit-files "$svc" 2>/dev/null | grep -q "^$svc"; then
    if sudo systemctl enable "$svc" 2>/dev/null; then
      echo "  ✅ 已启用: ${svc%.service}"
      ((enabled_count++)) || true
    else
      echo "  ⚠️  启用失败: ${svc%.service}"
    fi
  else
    echo "  ⏭️  跳过（不存在）: ${svc%.service}"
    ((skipped_count++)) || true
  fi
done

echo ""
echo "📊 服务启用统计："
echo "  ✅ 成功启用: $enabled_count 个"
echo "  ⏭️  跳过服务: $skipped_count 个"

# 验证至少启用了核心服务
if [[ $enabled_count -lt 3 ]]; then
  echo ""
  echo "⚠️  警告: 只启用了 $enabled_count 个服务，可能不足以保证 cloud-init 正常工作"
  echo "  建议检查系统中是否正确安装了 cloud-init 包"
fi

# 验证 cloud-init 可用性
echo ""
echo '🔍 验证 cloud-init 可用性...'
if command -v cloud-init &>/dev/null; then
  # 显示版本信息
  version=$(cloud-init --version 2>&1 | head -n1)
  echo "  ℹ️  版本: $version"

  # 验证配置文件语法
  if cloud-init schema --system &>/dev/null; then
    echo "  ✅ 配置文件语法正确"
  else
    echo "  ⚠️  配置文件可能存在问题，但不影响继续构建"
  fi

  # 列出已启用的服务
  echo "  📋 已启用的 cloud-init 服务:"
  systemctl list-unit-files 'cloud-*' 2>/dev/null | \
    grep -E 'enabled|static' | \
    awk '{print "    - " $1 " (" $2 ")"}' || echo "    (无)"

  echo "  ✅ cloud-init 可用性验证通过"
else
  echo "  ❌ 错误: cloud-init 命令不可用"
  echo "  请确保已安装 cloud-init 包"
  exit 1
fi

# 启用网络服务
echo ""
echo '🌐 启用网络相关服务...'
sudo systemctl enable systemd-networkd.service systemd-resolved.service || true
sudo systemctl enable sshd.service || true
echo "  ✅ 网络服务配置完成"
