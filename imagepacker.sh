#!/bin/bash
set -e  # 遇到错误立即退出
set -u  # 使用未定义变量时退出
set -o pipefail  # 管道命令失败时退出

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
log_info "🎉 开始构建 Debian 定制镜像 🎉"
echo "================================================"
echo ""

log_step "📥 正在下载 Debian 13 基础镜像..."
wget https://cloud.debian.org/images/cloud/trixie/latest/debian-13-generic-amd64.qcow2
log_success "📥 镜像下载完成！"
DOWNLOAD_SIZE=$(du -h debian-13-generic-amd64.qcow2 | cut -f1)
log_info "💾 下载后镜像体积: ${DOWNLOAD_SIZE}"
echo ""

log_step "🛠️ 开始定制镜像（这可能需要一些时间）..."
log_info "  🌍 配置时区为 Asia/Hong_Kong"
log_info "  ⚙️  配置 GRUB 启动器"
log_info "  📦 安装系统软件包"
log_info "  🚀 安装 Xanmod 高性能内核"
log_info "  🌐 配置网络优化（BBR + fq_pie）"
log_info "  🐳 安装 Docker 及相关组件"
log_info "  💻 配置 Zsh + Powerlevel10k + 现代化CLI工具"
log_info "  📝 配置 Git 全局设置"
log_info "  🧹 清理缓存和日志文件"
echo ""

virt-customize -a debian-13-generic-amd64.qcow2 \
  --smp 2 --verbose \
  --timezone "Asia/Hong_Kong" \
  --append-line "/etc/default/grub:# disables OS prober to avoid loopback detection which breaks booting" \
  --append-line "/etc/default/grub:GRUB_DISABLE_OS_PROBER=true" \
  --run-command "update-grub" \
  --run-command "systemctl enable serial-getty@ttyS1.service" \
  --run-command "sed -i 's|Types: deb deb-src|Types: deb|g' /etc/apt/sources.list.d/debian.sources" \
  --run-command "sed -i 's|generate_mirrorlists: true|generate_mirrorlists: false|g' /etc/cloud/cloud.cfg.d/01_debian_cloud.cfg" \
  --update --install "sudo,qemu-guest-agent,spice-vdagent,bash-completion,unzip,wget,curl,axel,net-tools,iputils-ping,iputils-arping,iputils-tracepath,nano,most,screen,less,vim,bzip2,lldpd,mtr-tiny,htop,dnsutils,zstd,lsof,p7zip-full,git,tree,zsh,fastfetch,gnupg,eza,bat,fd-find,ripgrep,btop" \
  --run-command "wget -qO - https://gitlab.com/afrd.gpg | gpg --dearmor -o /usr/share/keyrings/xanmod-archive-keyring.gpg --yes" \
  --run-command "echo 'deb [signed-by=/usr/share/keyrings/xanmod-archive-keyring.gpg] http://deb.xanmod.org releases main' > /etc/apt/sources.list.d/xanmod-release.list" \
  --run-command "apt-get update -y" \
  --run-command "apt-get install -y linux-xanmod-x64v3" \
  --run-command "echo 'net.core.default_qdisc=fq_pie' > /etc/sysctl.conf" \
  --run-command "echo 'net.ipv4.tcp_congestion_control=bbr' >> /etc/sysctl.conf" \
  --run-command "install -m 0755 -d /etc/apt/keyrings" \
  --run-command "curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc" \
  --run-command "chmod a+r /etc/apt/keyrings/docker.asc" \
  --run-command "echo \"deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian trixie stable\" > /etc/apt/sources.list.d/docker.list" \
  --run-command "apt-get update -y" \
  --run-command "apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin" \
  --run-command "systemctl enable docker.service" \
  --run-command "systemctl enable containerd.service" \
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
  --run-command "export HOME=/root && curl -fsSL https://raw.githubusercontent.com/zimfw/install/master/install.zsh | zsh" \
  --run-command "grep -qx 'zmodule romkatv/powerlevel10k --use degit' /root/.zimrc || echo 'zmodule romkatv/powerlevel10k --use degit' >> /root/.zimrc" \
  --run-command "export HOME=/root && export ZIM_HOME=/root/.zim && zsh -c 'source /root/.zim/zimfw.zsh init -q && zimfw install'" \
  --run-command "touch /root/.zshrc" \
  --run-command "grep -qx 'cat /etc/motd' /root/.zshrc || sed -i '1i cat /etc/motd' /root/.zshrc" \
  --run-command "grep -qx 'fastfetch' /root/.zshrc || sed -i '/^cat \\/etc\\/motd$/a fastfetch' /root/.zshrc" \
  --run-command $'cat > /tmp/p10k_instant_block <<\'EOF\'
# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi
EOF' \
  --run-command "grep -q 'p10k-instant-prompt' /root/.zshrc || sed -i '/^fastfetch$/r /tmp/p10k_instant_block' /root/.zshrc" \
  --run-command "rm -f /tmp/p10k_instant_block" \
  --run-command 'grep -q "source ~/.p10k.zsh" /root/.zshrc || printf "\n# To customize prompt, run \`p10k configure\` or edit ~/.p10k.zsh.\n[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh\n" >> /root/.zshrc' \
  --run-command "grep -q 'p10k finalize' /root/.zshrc || echo '(( ! \${+functions[p10k]} )) || p10k finalize' >> /root/.zshrc" \
  --run-command $'cat >> /root/.zshrc << \'ALIAS_EOF\'

# Modern CLI tools aliases
alias ls=\'eza --icons --group-directories-first\'
alias ll=\'eza --icons --group-directories-first -lh\'
alias la=\'eza --icons --group-directories-first -lah\'
alias lt=\'eza --icons --group-directories-first --tree\'
alias cat=\'bat --paging=never --style=plain\'
alias catp=\'bat --paging=always\'
alias find=\'fd\'
alias grep=\'rg\'
alias top=\'btop\'
ALIAS_EOF' \
  --run-command "touch /root/.hushlogin" \
  --run-command "curl -fsSL https://raw.githubusercontent.com/Lynricsy/ServerScripts/refs/heads/master/motd -o /etc/motd && chmod 644 /etc/motd" \
  --run-command "curl -fsSL https://raw.githubusercontent.com/Lynricsy/ServerScripts/refs/heads/master/p10k.zsh -o /root/.p10k.zsh && chmod 644 /root/.p10k.zsh" \
  --run-command "export HOME=/root && git config --global user.name 'Lynricsy' && git config --global user.email 'im@ling.plus' && git config --global init.defaultBranch main && git config --global color.ui auto && git config --global core.editor nano && git config --global diff.algorithm histogram && git config --global merge.conflictstyle diff3 && git config --global pull.rebase false && git config --global alias.st status && git config --global alias.co checkout && git config --global alias.br branch && git config --global alias.ci commit && git config --global alias.unstage 'reset HEAD --' && git config --global alias.last 'log -1 HEAD' && git config --global alias.lg \"log --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit\" && git config --global alias.contributors 'shortlog -sn'" \
  --run-command "apt-get -y autoremove --purge && apt-get -y clean" \
  --append-line "/etc/systemd/timesyncd.conf:NTP=time.apple.com time.windows.com" \
  --delete "/var/log/*.log" \
  --delete "/var/lib/apt/lists/*" \
  --delete "/var/cache/apt/*" \
  --run-command "rm -f /etc/machine-id"

log_success "🛠️ 镜像定制完成！"
CUSTOMIZE_SIZE=$(du -h debian-13-generic-amd64.qcow2 | cut -f1)
log_info "💾 定制后镜像体积: ${CUSTOMIZE_SIZE}"
echo ""

log_step "🗜️ 正在压缩镜像以减小体积..."
log_info "  创建临时目录: ${TEMP_DIR}"
mkdir -p "${TEMP_DIR}"
TMPDIR="${TEMP_DIR}" virt-sparsify --compress debian-13-generic-amd64.qcow2 debian-13-generic-amd64-NEXT.qcow2
log_success "🗜️ 镜像压缩完成！"
FINAL_SIZE=$(du -h debian-13-generic-amd64-NEXT.qcow2 | cut -f1)
log_info "💾 压缩后镜像体积: ${FINAL_SIZE}"
echo ""

echo "================================================"
log_success "✅ 镜像构建全部完成！✨"
log_info "📁 输出文件: debian-13-generic-amd64-NEXT.qcow2"
echo ""
log_info "📊 体积变化统计："
log_info "  📥 初始下载: ${DOWNLOAD_SIZE}"
log_info "  🛠️  定制后: ${CUSTOMIZE_SIZE}"
log_info "  🗜️  最终压缩: ${FINAL_SIZE}"
log_info "🎯 镜像已优化并ready to use！"
echo "================================================"
