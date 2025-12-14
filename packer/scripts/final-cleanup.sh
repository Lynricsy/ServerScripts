#!/bin/bash
# 最终清理脚本 - 使用 virt-customize 在镜像上执行
# 创建时间: 2025-12-14
# 创建者: Mare Ashley Pecker (mare@sent.com)
# 说明: 此脚本在宿主机上通过 virt-customize 执行，处理那些在运行系统中不便操作的任务

set -e

IMAGE_PATH="$1"

if [ -z "$IMAGE_PATH" ]; then
    echo "Usage: $0 <image-path>"
    exit 1
fi

if [ ! -f "$IMAGE_PATH" ]; then
    echo "Error: Image file not found: $IMAGE_PATH"
    exit 1
fi

echo "🧹 开始最终清理: $IMAGE_PATH"

# 使用 virt-customize 进行最终清理
# 这些操作在离线状态下执行更安全
virt-customize -a "$IMAGE_PATH" \
    --run-command "rm -rf /var/cache/pacman/pkg/* /var/lib/pacman/sync/* 2>/dev/null || true" \
    --run-command "rm -rf /var/cache/zypp/* 2>/dev/null || true" \
    --run-command "rm -rf /var/cache/apt/* /var/lib/apt/lists/* 2>/dev/null || true" \
    --run-command "rm -f /var/log/*.log /var/log/**/*.log 2>/dev/null || true" \
    --run-command "truncate -s 0 /etc/machine-id" \
    --run-command "rm -f /var/lib/dbus/machine-id 2>/dev/null || true" \
    --run-command "cloud-init clean --logs 2>/dev/null || true" \
    --run-command "command -v gpgconf >/dev/null 2>&1 && gpgconf --kill all || true" \
    --run-command "rm -rf /tmp/* /var/tmp/* 2>/dev/null || true" \
    --run-command "rm -f /root/.bash_history /home/*/.bash_history 2>/dev/null || true" \
    --run-command "sync"

echo "✅ 最终清理完成"
