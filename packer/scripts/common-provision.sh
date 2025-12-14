#!/bin/bash
# 通用配置脚本 - 由 Packer provisioner 调用
# 创建时间: 2025-12-14
# 创建者: Mare Ashley Pecker (mare@sent.com)
# 说明: 此脚本在 VM 内部通过 SSH 执行，环境变量由 Packer 传入

set -e

# ============================================================
# 日志函数
# ============================================================
log_info() {
    echo -e "\033[1;36m[INFO]\033[0m $1"
}

log_success() {
    echo -e "\033[1;32m[SUCCESS]\033[0m $1"
}

log_step() {
    echo -e "\033[1;35m[STEP]\033[0m $1"
}

# ============================================================
# 网络优化配置 (BBR + fq_pie)
# ============================================================
configure_network_optimization() {
    log_step "🌐 配置网络优化 (BBR + fq_pie)..."

    sudo mkdir -p /etc/sysctl.d /etc/modules-load.d

    # 配置内核模块自动加载（首次启动时生效）
    echo -e "tcp_bbr\nsch_fq_pie" | sudo tee /etc/modules-load.d/network-tuning.conf > /dev/null

    # sysctl 配置（首次启动时生效）
    cat <<'EOF' | sudo tee /etc/sysctl.d/99-network-optimization.conf > /dev/null
net.core.default_qdisc=fq_pie
net.ipv4.tcp_congestion_control=bbr
EOF

    # 尝试立即应用（构建环境中可能失败，这是正常的）
    # 配置文件会在镜像首次启动时自动生效
    if sudo modprobe tcp_bbr 2>/dev/null && sudo modprobe sch_fq_pie 2>/dev/null; then
        sudo sysctl -p /etc/sysctl.d/99-network-optimization.conf 2>/dev/null || true
        log_success "🌐 网络优化配置完成（已立即生效）"
    else
        log_success "🌐 网络优化配置完成（将在首次启动时生效）"
    fi
}

# ============================================================
# Docker 配置
# ============================================================
configure_docker() {
    log_step "🐳 配置 Docker..."

    sudo mkdir -p /etc/docker
    cat <<'EOF' | sudo tee /etc/docker/daemon.json > /dev/null
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "storage-driver": "overlay2",
  "default-address-pools": [
    {
      "base": "172.18.0.0/16",
      "size": 24
    }
  ]
}
EOF

    sudo systemctl enable docker.service || true
    sudo usermod -aG docker root || true
    log_success "🐳 Docker 配置完成"
}

# ============================================================
# Zsh + Zim + Powerlevel10k 配置
# ============================================================
configure_zsh() {
    log_step "💻 配置 Zsh + Zim + Powerlevel10k..."

    # 安装 Zim Framework
    export HOME=/root
    export ZIM_HOME=/root/.zim
    curl -fsSL https://raw.githubusercontent.com/zimfw/install/master/install.zsh | zsh -f || true

    # 添加 Powerlevel10k 模块
    grep -qx 'zmodule romkatv/powerlevel10k --use degit' /root/.zimrc 2>/dev/null || \
        echo 'zmodule romkatv/powerlevel10k --use degit' >> /root/.zimrc

    # 安装模块
    chmod +x /root/.zim/zimfw.zsh 2>/dev/null || true
    zsh -f /root/.zim/zimfw.zsh install 2>/dev/null || true

    # 备份原有 .zshrc (Zim 生成的)
    local zim_zshrc=""
    if [ -f /root/.zshrc ]; then
        zim_zshrc=$(cat /root/.zshrc)
    fi

    # 重新构建 .zshrc，确保顺序正确
    # 顺序: motd -> fastfetch -> p10k instant prompt -> Zim 原有内容 -> p10k source -> aliases
    cat > /root/.zshrc <<'ZSHRC_HEADER'
# 显示 MOTD 和系统信息 (在 p10k instant prompt 之前，因为这些是静态输出)
[[ -f /etc/motd ]] && cat /etc/motd
command -v fastfetch &>/dev/null && fastfetch

# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

ZSHRC_HEADER

    # 追加 Zim 原有内容 (排除我们要自己管理的部分)
    if [ -n "$zim_zshrc" ]; then
        echo "$zim_zshrc" | grep -v 'p10k-instant-prompt' | grep -v 'source.*p10k.zsh' >> /root/.zshrc
    fi

    # 添加 p10k source (在文件末尾)
    cat >> /root/.zshrc <<'ZSHRC_FOOTER'

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

# Finalize p10k
(( ! ${+functions[p10k]} )) || p10k finalize
ZSHRC_FOOTER

    log_success "💻 Zsh 配置完成"
}

# ============================================================
# CLI 别名配置
# ============================================================
configure_aliases() {
    log_step "⚡ 配置 CLI 别名..."

    # 检测命令名称 (不同发行版可能不同)
    local bat_cmd="bat"
    local fd_cmd="fd"

    command -v batcat >/dev/null 2>&1 && bat_cmd="batcat"
    command -v fdfind >/dev/null 2>&1 && fd_cmd="fdfind"

    cat >> /root/.zshrc <<ALIAS_EOF

# Modern CLI tools aliases
alias ls='eza --icons --group-directories-first'
alias ll='eza --icons --group-directories-first -lh'
alias la='eza --icons --group-directories-first -lah'
alias lt='eza --icons --group-directories-first --tree'
alias cat='${bat_cmd} --paging=never --style=plain'
alias catp='${bat_cmd} --paging=always'
alias bat='${bat_cmd}'
alias find='${fd_cmd}'
alias mo='micro'
alias grep='rg'
alias top='btop'
ALIAS_EOF

    log_success "⚡ CLI 别名配置完成"
}

# ============================================================
# 下载配置文件
# ============================================================
download_configs() {
    log_step "📥 下载配置文件..."

    # 创建 hushlogin
    touch /root/.hushlogin

    # 下载 motd
    curl -fsSL https://raw.githubusercontent.com/Lynricsy/ServerScripts/refs/heads/master/motd -o /etc/motd
    chmod 644 /etc/motd

    # 下载 p10k 配置
    curl -fsSL https://raw.githubusercontent.com/Lynricsy/ServerScripts/refs/heads/master/p10k.zsh -o /root/.p10k.zsh
    chmod 644 /root/.p10k.zsh

    log_success "📥 配置文件下载完成"
}

# ============================================================
# Git 全局配置
# ============================================================
configure_git() {
    log_step "📝 配置 Git..."

    local git_name="${GIT_USER_NAME:-Lynricsy}"
    local git_email="${GIT_USER_EMAIL:-im@ling.plus}"

    git config --global user.name "$git_name"
    git config --global user.email "$git_email"
    git config --global init.defaultBranch main
    git config --global color.ui auto
    git config --global core.editor nano
    git config --global diff.algorithm histogram
    git config --global merge.conflictstyle diff3
    git config --global pull.rebase false

    # 别名
    git config --global alias.st status
    git config --global alias.co checkout
    git config --global alias.br branch
    git config --global alias.ci commit
    git config --global alias.unstage 'reset HEAD --'
    git config --global alias.last 'log -1 HEAD'
    git config --global alias.lg "log --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit"
    git config --global alias.contributors 'shortlog -sn'

    log_success "📝 Git 配置完成"
}

# ============================================================
# SSH 配置
# ============================================================
configure_ssh() {
    log_step "🔑 配置 SSH..."

    mkdir -p /root/.ssh
    chmod 700 /root/.ssh
    chown -R root:root /root/.ssh

    log_success "🔑 SSH 配置完成"
}

# ============================================================
# NTP 配置
# ============================================================
configure_ntp() {
    log_step "🕐 配置 NTP..."

    if [ -f /etc/systemd/timesyncd.conf ]; then
        grep -q '^NTP=' /etc/systemd/timesyncd.conf || \
            echo 'NTP=time.apple.com time.windows.com' >> /etc/systemd/timesyncd.conf
    fi

    log_success "🕐 NTP 配置完成"
}

# ============================================================
# 主函数
# ============================================================
main() {
    echo "================================================"
    log_info "🚀 开始通用配置..."
    echo "================================================"

    configure_network_optimization
    configure_docker
    configure_zsh
    configure_aliases
    download_configs
    configure_git
    configure_ssh
    configure_ntp

    echo "================================================"
    log_success "✅ 通用配置完成！"
    echo "================================================"
}

# 如果直接运行此脚本，执行 main
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
