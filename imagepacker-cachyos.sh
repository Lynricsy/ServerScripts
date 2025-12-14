#!/bin/bash
set -e  # 遇到错误立即退出
set -u  # 使用未定义变量时退出
set -o pipefail  # 管道命令失败时退出

# CachyOS (基于 Arch Linux) 定制镜像构建脚本
# 创建时间: 2025-12-13 +08:00
# 创建者: Mare Ashley Pecker (mare@sent.com)
# 基础镜像: fastly.mirror.pkgbuild.com/images/latest/Arch-Linux-x86_64-cloudimg.qcow2
# 说明: 在 Arch Linux 云镜像基础上安装 CachyOS 仓库和内核

# 日志函数
log_info() {
    echo -e "\033[1;36m[INFO]\033[0m $1"
}

log_success() {
    echo -e "\033[1;32m[SUCCESS]\033[0m $1"
}

log_error() {
    echo -e "\033[1;31m[ERROR]\033[0m $1"
}

log_step() {
    echo -e "\033[1;35m[STEP]\033[0m $1"
}

# 临时目录路径
TEMP_DIR="/root/.ImageMakerTemp"

# 清理函数
cleanup() {
    if [ -d "${TEMP_DIR}" ]; then
        echo ""
        log_info "🧹 正在清理临时目录..."
        rm -rf "${TEMP_DIR}"
        log_success "🧹 临时目录清理完成！"
    fi
}

# 设置退出时自动清理（无论成功还是失败）
trap cleanup EXIT

echo "================================================"
log_info "🎉 开始构建 CachyOS 定制镜像 🎉"
echo "================================================"
echo ""

log_step "📥 正在下载 Arch Linux Cloud 基础镜像..."
wget https://fastly.mirror.pkgbuild.com/images/latest/Arch-Linux-x86_64-cloudimg.qcow2
log_success "📥 镜像下载完成！"
DOWNLOAD_SIZE=$(du -h Arch-Linux-x86_64-cloudimg.qcow2 | cut -f1)
log_info "💾 下载后镜像体积: ${DOWNLOAD_SIZE}"
echo ""

log_step "📐 扩展镜像磁盘空间（Arch 云镜像默认太小）..."
# Arch Linux 云镜像默认只有约 2GB，安装 CachyOS 和软件包需要更多空间
qemu-img resize Arch-Linux-x86_64-cloudimg.qcow2 +6G
log_success "📐 镜像已扩展 6GB！"
echo ""

log_step "📐 扩展镜像内部文件系统..."
# 创建目标镜像文件（virt-resize 需要预先存在的目标文件）
qemu-img create -f qcow2 -o preallocation=off Arch-Linux-x86_64-cloudimg-resized.qcow2 8G
virt-resize --expand /dev/sda3 Arch-Linux-x86_64-cloudimg.qcow2 Arch-Linux-x86_64-cloudimg-resized.qcow2
rm Arch-Linux-x86_64-cloudimg.qcow2
mv Arch-Linux-x86_64-cloudimg-resized.qcow2 Arch-Linux-x86_64-cloudimg.qcow2
log_success "📐 文件系统扩展完成！"
echo ""

log_step "🛠️ 开始定制镜像（这可能需要一些时间）..."
log_info "  🌍 配置时区为 Asia/Hong_Kong"
log_info "  🌐 配置 Locale 为 zh_CN.UTF-8"
log_info "  ⚙️  配置 GRUB 启动器"
log_info "  🚀 安装 CachyOS 仓库和优化包"
log_info "  🐧 安装 CachyOS 优化内核"
log_info "  📦 安装系统软件包"
log_info "  🌐 配置网络优化（BBR + fq_pie）"
log_info "  🐳 安装 Docker 及相关组件"
log_info "  💻 配置 Zsh + Powerlevel10k + 现代化CLI工具"
log_info "  📝 配置 Git 全局设置"
log_info "  🔑 配置 SSH 公钥认证"
log_info "  🧹 清理缓存和日志文件"
echo ""

# 注意：在 virt-customize 环境中，需要显式设置 HOME=/root 来确保
# Zsh 和 Zim Framework 等工具正确安装到 /root 目录
virt-customize -a Arch-Linux-x86_64-cloudimg.qcow2 \
  --smp 2 --memsize 2048 --verbose \
  --timezone "Asia/Hong_Kong" \
  --append-line "/etc/default/grub:# disables OS prober to avoid loopback detection which breaks booting" \
  --append-line "/etc/default/grub:GRUB_DISABLE_OS_PROBER=true" \
  --run-command "mkdir -p /dev && ln -snf /proc/self/fd /dev/fd && ln -snf /proc/self/fd/0 /dev/stdin && ln -snf /proc/self/fd/1 /dev/stdout && ln -snf /proc/self/fd/2 /dev/stderr" \
  --run-command "grub-mkconfig -o /boot/grub/grub.cfg || true" \
  --run-command "systemctl enable serial-getty@ttyS1.service" \
  --run-command "sed -i 's/^disable_root: true/disable_root: false/' /etc/cloud/cloud.cfg" \
  --run-command "sed -i 's/^\\([ ]*\\)name: arch$/\\1name: root/' /etc/cloud/cloud.cfg" \
  --run-command "sed -i 's/lock_passwd: True/lock_passwd: false/' /etc/cloud/cloud.cfg" \
  --run-command "pacman-key --init" \
  --run-command "pacman-key --populate archlinux" \
  --run-command "cat > /etc/pacman.d/mirrorlist <<'MIRROREOF'
# Hong Kong mirrors
Server = https://mirror.xtom.com.hk/archlinux/\$repo/os/\$arch
Server = https://mirror-hk.koddos.net/archlinux/\$repo/os/\$arch
MIRROREOF" \
  --run-command "pacman -Syu --noconfirm" \
  --run-command "sed -i 's/^#zh_CN.UTF-8 UTF-8/zh_CN.UTF-8 UTF-8/' /etc/locale.gen" \
  --run-command "sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen" \
  --run-command "locale-gen" \
  --run-command "echo 'LANG=zh_CN.UTF-8' > /etc/locale.conf" \
  --run-command "pacman -S --noconfirm --needed gawk" \
  --run-command "pacman-key --recv-keys F3B607488DB35A47 --keyserver keyserver.ubuntu.com" \
  --run-command "pacman-key --lsign-key F3B607488DB35A47" \
  --run-command "pacman -U --noconfirm 'https://mirror.cachyos.org/repo/x86_64/cachyos/cachyos-keyring-20240331-1-any.pkg.tar.zst' 'https://mirror.cachyos.org/repo/x86_64/cachyos/cachyos-mirrorlist-22-1-any.pkg.tar.zst' 'https://mirror.cachyos.org/repo/x86_64/cachyos/cachyos-v3-mirrorlist-22-1-any.pkg.tar.zst' 'https://mirror.cachyos.org/repo/x86_64/cachyos/cachyos-v4-mirrorlist-22-1-any.pkg.tar.zst'" \
  --run-command "cat > /etc/pacman.d/cachyos-mirrorlist <<'MIRROREOF'
# CachyOS mirrors (x86_64)
Server = https://mirror.funami.tech/cachy/repo/\$arch/\$repo
Server = https://cdn77.cachyos.org/repo/\$arch/\$repo
Server = https://mirror.cachyos.org/repo/\$arch/\$repo
MIRROREOF" \
  --run-command "cat > /etc/pacman.d/cachyos-v4-mirrorlist <<'MIRROREOF'
# CachyOS v4 mirrors (x86_64_v4)
Server = https://mirror.funami.tech/cachy/repo/x86_64_v4/\$repo
Server = https://cdn77.cachyos.org/repo/x86_64_v4/\$repo
Server = https://mirror.cachyos.org/repo/x86_64_v4/\$repo
MIRROREOF" \
  --run-command "sed -i 's/^Architecture = .*/Architecture = x86_64 x86_64_v4/' /etc/pacman.conf" \
  --run-command "sed -i '/^\\[core\\]/i # CachyOS Repositories (x86-64-v4 optimized)\\n[cachyos-v4]\\nInclude = /etc/pacman.d/cachyos-v4-mirrorlist\\n\\n[cachyos-core-v4]\\nInclude = /etc/pacman.d/cachyos-v4-mirrorlist\\n\\n[cachyos-extra-v4]\\nInclude = /etc/pacman.d/cachyos-v4-mirrorlist\\n\\n[cachyos]\\nInclude = /etc/pacman.d/cachyos-mirrorlist\\n' /etc/pacman.conf" \
  --run-command "printf '\\n# Arch Linux CN Repository\\n[archlinuxcn]\\nServer = https://mirror.xtom.com.hk/archlinuxcn/\$arch\\n' >> /etc/pacman.conf" \
  --run-command "pacman -Syyu --noconfirm" \
  --run-command "if [ -f /etc/pacman.conf.pacnew ]; then cp /etc/pacman.conf /etc/pacman.conf.backup && mv /etc/pacman.conf.pacnew /etc/pacman.conf && sed -i 's/^Architecture = .*/Architecture = x86_64 x86_64_v4/' /etc/pacman.conf && sed -i '/^\\[core\\]/i # CachyOS Repositories (x86-64-v4 optimized)\\n[cachyos-v4]\\nInclude = /etc/pacman.d/cachyos-v4-mirrorlist\\n\\n[cachyos-core-v4]\\nInclude = /etc/pacman.d/cachyos-v4-mirrorlist\\n\\n[cachyos-extra-v4]\\nInclude = /etc/pacman.d/cachyos-v4-mirrorlist\\n\\n[cachyos]\\nInclude = /etc/pacman.d/cachyos-mirrorlist\\n' /etc/pacman.conf && printf '\\n# Arch Linux CN Repository\\n[archlinuxcn]\\nServer = https://mirror.xtom.com.hk/archlinuxcn/\$arch\\n' >> /etc/pacman.conf && pacman -Sy; fi" \
  --run-command "pacman -S --noconfirm --needed archlinuxcn-keyring" \
  --run-command "pacman -R --noconfirm linux linux-headers || true" \
  --run-command "pacman -S --noconfirm --needed linux-cachyos linux-cachyos-headers" \
  --run-command "pacman -S --noconfirm --needed cachyos-settings scx-scheds" \
  --run-command "grub-mkconfig -o /boot/grub/grub.cfg" \
  --run-command "pacman -S --noconfirm --needed sudo qemu-guest-agent spice-vdagent bash-completion unzip wget curl axel net-tools iputils iproute2 nano most screen less vim bzip2 lldpd mtr htop bind zstd lsof p7zip git tree zsh fastfetch gnupg eza bat fd ripgrep btop micro" \
  --run-command "mkdir -p /etc/sysctl.d" \
  --run-command "printf 'tcp_bbr\\nsch_fq_pie\\n' > /etc/modules-load.d/network-tuning.conf" \
  --run-command "echo 'net.core.default_qdisc=fq_pie' > /etc/sysctl.d/99-network-optimization.conf" \
  --run-command "echo 'net.ipv4.tcp_congestion_control=bbr' >> /etc/sysctl.d/99-network-optimization.conf" \
  --run-command "sysctl -p /etc/sysctl.d/99-network-optimization.conf || true" \
  --run-command "pacman -S --noconfirm --needed docker docker-compose docker-buildx" \
  --run-command "systemctl enable docker.service" \
  --run-command "usermod -aG docker root" \
  --run-command "mkdir -p /etc/docker" \
  --run-command "cat > /etc/docker/daemon.json <<'EOF'
{
  \"log-driver\": \"json-file\",
  \"log-opts\": {
    \"max-size\": \"10m\",
    \"max-file\": \"3\"
  },
  \"storage-driver\": \"overlay2\",
  \"default-address-pools\": [
    {
      \"base\": \"172.18.0.0/16\",
      \"size\": 24
    }
  ]
}
EOF" \
  --run-command "HOME=/root ZIM_HOME=/root/.zim curl -fsSL https://raw.githubusercontent.com/zimfw/install/master/install.zsh | HOME=/root ZIM_HOME=/root/.zim zsh -f" \
  --run-command "grep -qx 'zmodule romkatv/powerlevel10k --use degit' /root/.zimrc || echo 'zmodule romkatv/powerlevel10k --use degit' >> /root/.zimrc" \
  --run-command "chmod +x /root/.zim/zimfw.zsh" \
  --run-command "HOME=/root ZIM_HOME=/root/.zim zsh -f /root/.zim/zimfw.zsh install" \
  --run-command "touch /root/.zshrc" \
  --run-command "grep -qx 'cat /etc/motd' /root/.zshrc || sed -i '1i cat /etc/motd' /root/.zshrc" \
  --run-command "grep -qx 'fastfetch' /root/.zshrc || sed -i '/^cat \\/etc\\/motd$/a fastfetch' /root/.zshrc" \
  --run-command "cat > /tmp/p10k_instant_block <<'P10K_EOF'
# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r \"\${XDG_CACHE_HOME:-\$HOME/.cache}/p10k-instant-prompt-\${(%):-%n}.zsh\" ]]; then
  source \"\${XDG_CACHE_HOME:-\$HOME/.cache}/p10k-instant-prompt-\${(%):-%n}.zsh\"
fi
P10K_EOF" \
  --run-command "grep -q 'p10k-instant-prompt' /root/.zshrc || sed -i '/^fastfetch$/r /tmp/p10k_instant_block' /root/.zshrc" \
  --run-command "rm -f /tmp/p10k_instant_block" \
  --run-command "grep -q 'source ~/.p10k.zsh' /root/.zshrc || printf '\\n# To customize prompt, run \\x60p10k configure\\x60 or edit ~/.p10k.zsh.\\n[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh\\n' >> /root/.zshrc" \
  --run-command "grep -q 'p10k finalize' /root/.zshrc || echo '(( ! \${+functions[p10k]} )) || p10k finalize' >> /root/.zshrc" \
  --run-command "cat >> /root/.zshrc <<'ALIAS_EOF'

# Modern CLI tools aliases
alias ls='eza --icons --group-directories-first'
alias ll='eza --icons --group-directories-first -lh'
alias la='eza --icons --group-directories-first -lah'
alias lt='eza --icons --group-directories-first --tree'
alias cat='bat --paging=never --style=plain'
alias catp='bat --paging=always'
alias find='fd'
alias mo='micro'
alias grep='rg'
alias top='btop'
ALIAS_EOF" \
  --run-command "touch /root/.hushlogin" \
  --run-command "curl -fsSL https://raw.githubusercontent.com/Lynricsy/ServerScripts/refs/heads/master/motd -o /etc/motd && chmod 644 /etc/motd" \
  --run-command "curl -fsSL https://raw.githubusercontent.com/Lynricsy/ServerScripts/refs/heads/master/p10k.zsh -o /root/.p10k.zsh && chmod 644 /root/.p10k.zsh" \
  --run-command "HOME=/root git config --global user.name 'Lynricsy'" \
  --run-command "HOME=/root git config --global user.email 'im@ling.plus'" \
  --run-command "HOME=/root git config --global init.defaultBranch main" \
  --run-command "HOME=/root git config --global color.ui auto" \
  --run-command "HOME=/root git config --global core.editor nano" \
  --run-command "HOME=/root git config --global diff.algorithm histogram" \
  --run-command "HOME=/root git config --global merge.conflictstyle diff3" \
  --run-command "HOME=/root git config --global pull.rebase false" \
  --run-command "HOME=/root git config --global alias.st status" \
  --run-command "HOME=/root git config --global alias.co checkout" \
  --run-command "HOME=/root git config --global alias.br branch" \
  --run-command "HOME=/root git config --global alias.ci commit" \
  --run-command "HOME=/root git config --global alias.unstage 'reset HEAD --'" \
  --run-command "HOME=/root git config --global alias.last 'log -1 HEAD'" \
  --run-command "HOME=/root git config --global alias.lg 'log --graph --pretty=format:%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset --abbrev-commit'" \
  --run-command "HOME=/root git config --global alias.contributors 'shortlog -sn'" \
  --run-command "mkdir -p /root/.ssh && chmod 700 /root/.ssh" \
  --run-command "chown -R root:root /root/.ssh" \
  --run-command "rm -rf /var/cache/pacman/pkg/* /var/lib/pacman/sync/*" \
  --append-line "/etc/systemd/timesyncd.conf:NTP=time.apple.com time.windows.com" \
  --delete "/var/log/*.log" \
  --delete "/var/cache/pacman/pkg/*" \
  --run-command "truncate -s 0 /etc/machine-id || true" \
  --run-command "cloud-init clean --logs" \
  --run-command "command -v gpgconf >/dev/null 2>&1 && gpgconf --kill all || true"

log_success "🛠️ 镜像定制完成！"
CUSTOMIZE_SIZE=$(du -h Arch-Linux-x86_64-cloudimg.qcow2 | cut -f1)
log_info "💾 定制后镜像体积: ${CUSTOMIZE_SIZE}"
echo ""

log_step "🗜️ 正在压缩镜像以减小体积..."
log_info "  创建临时目录: ${TEMP_DIR}"
mkdir -p "${TEMP_DIR}"
TMPDIR="${TEMP_DIR}" virt-sparsify --compress Arch-Linux-x86_64-cloudimg.qcow2 CachyOS-NEXT.qcow2
log_success "🗜️ 镜像压缩完成！"
FINAL_SIZE=$(du -h CachyOS-NEXT.qcow2 | cut -f1)
log_info "💾 压缩后镜像体积: ${FINAL_SIZE}"
echo ""

echo "================================================"
log_success "✅ CachyOS 镜像构建全部完成！✨"
log_info "📁 输出文件: CachyOS-NEXT.qcow2"
echo ""
log_info "📊 体积变化统计："
log_info "  📥 初始下载: ${DOWNLOAD_SIZE}"
log_info "  🛠️  定制后: ${CUSTOMIZE_SIZE}"
log_info "  🗜️  最终压缩: ${FINAL_SIZE}"
log_info "🎯 镜像已优化并ready to use！"
echo ""
log_info "🚀 CachyOS 特性："
log_info "  🐧 CachyOS 优化内核 (linux-cachyos)"
log_info "  📦 x86-64-v4 优化包仓库 (AVX-512)"
log_info "  ⚡ 性能提升 5%-20%"
log_info "  🔧 包含 scx-scheds 调度器"
echo "================================================"
