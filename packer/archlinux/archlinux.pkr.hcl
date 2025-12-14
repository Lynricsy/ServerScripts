# Arch Linux 定制镜像构建 - HashiCorp Packer 版本
# 创建时间: 2025-12-14 +08:00
# 创建者: Mare Ashley Pecker (mare@sent.com)
# 基础镜像: fastly.mirror.pkgbuild.com/images/latest/Arch-Linux-x86_64-cloudimg.qcow2

packer {
  required_plugins {
    qemu = {
      version = ">= 1.0.0"
      source  = "github.com/hashicorp/qemu"
    }
  }
}

# 变量定义
variable "output_directory" {
  type        = string
  default     = "output-archlinux"
  description = "输出目录"
}

variable "disk_size" {
  type        = string
  default     = "6G"
  description = "磁盘大小"
}

variable "memory" {
  type        = number
  default     = 2048
  description = "内存大小 (MB)"
}

variable "cpus" {
  type        = number
  default     = 2
  description = "CPU 核心数"
}

variable "timezone" {
  type        = string
  default     = "Asia/Hong_Kong"
  description = "时区设置"
}

variable "locale" {
  type        = string
  default     = "zh_CN.UTF-8"
  description = "语言环境"
}

variable "git_user_name" {
  type        = string
  default     = "Lynricsy"
  description = "Git 用户名"
}

variable "git_user_email" {
  type        = string
  default     = "im@ling.plus"
  description = "Git 邮箱"
}

# 本地变量
locals {
  base_image_url  = "https://fastly.mirror.pkgbuild.com/images/latest/Arch-Linux-x86_64-cloudimg.qcow2"
  output_filename = "Arch-Linux-NEXT.qcow2"
}

# 数据源：下载基础镜像
source "qemu" "archlinux" {
  iso_url          = local.base_image_url
  iso_checksum     = "none"
  disk_image       = true

  output_directory = var.output_directory
  vm_name          = local.output_filename

  format           = "qcow2"
  disk_size        = var.disk_size
  disk_compression = true

  memory           = var.memory
  cpus             = var.cpus

  accelerator      = "kvm"
  headless         = true

  # SSH 配置 (cloud-init 默认用户)
  ssh_username     = "arch"
  ssh_timeout      = "40m"

  # QEMU 参数
  qemuargs = [
    ["-cpu", "host"],
    ["-machine", "type=q35,accel=kvm"],
  ]

  shutdown_command = "sudo shutdown -P now"
}

# 构建定义
build {
  name    = "archlinux"
  sources = ["source.qemu.archlinux"]

  # 等待 cloud-init 完成
  provisioner "shell" {
    inline = [
      "cloud-init status --wait || true",
      "sudo -i"
    ]
  }

  # 配置时区
  provisioner "shell" {
    inline = [
      "sudo ln -sf /usr/share/zoneinfo/${var.timezone} /etc/localtime",
      "sudo hwclock --systohc"
    ]
  }

  # 配置 GRUB
  provisioner "shell" {
    inline = [
      "echo '# disables OS prober to avoid loopback detection which breaks booting' | sudo tee -a /etc/default/grub",
      "echo 'GRUB_DISABLE_OS_PROBER=true' | sudo tee -a /etc/default/grub",
      "sudo grub-mkconfig -o /boot/grub/grub.cfg || true",
      "sudo systemctl enable serial-getty@ttyS1.service"
    ]
  }

  # 初始化 pacman 密钥
  provisioner "shell" {
    inline = [
      "sudo pacman-key --init",
      "sudo pacman-key --populate archlinux"
    ]
  }

  # 配置镜像源
  provisioner "shell" {
    inline = [
      "cat <<'MIRROREOF' | sudo tee /etc/pacman.d/mirrorlist",
      "# Hong Kong mirrors",
      "Server = https://mirror.xtom.com.hk/archlinux/$repo/os/$arch",
      "Server = https://mirror-hk.koddos.net/archlinux/$repo/os/$arch",
      "MIRROREOF"
    ]
  }

  # 添加 archlinuxcn 仓库
  provisioner "shell" {
    inline = [
      "echo '' | sudo tee -a /etc/pacman.conf",
      "echo '# Arch Linux CN Repository' | sudo tee -a /etc/pacman.conf",
      "echo '[archlinuxcn]' | sudo tee -a /etc/pacman.conf",
      "echo 'Server = https://mirror.xtom.com.hk/archlinuxcn/$arch' | sudo tee -a /etc/pacman.conf",
      "sudo pacman -Syu --noconfirm",
      "sudo pacman -S --noconfirm --needed archlinuxcn-keyring"
    ]
  }

  # 配置 Locale
  provisioner "shell" {
    inline = [
      "sudo sed -i 's/^#zh_CN.UTF-8 UTF-8/zh_CN.UTF-8 UTF-8/' /etc/locale.gen",
      "sudo sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen",
      "sudo locale-gen",
      "echo 'LANG=${var.locale}' | sudo tee /etc/locale.conf"
    ]
  }

  # 安装基础软件包
  provisioner "shell" {
    inline = [
      "sudo pacman -S --noconfirm --needed sudo qemu-guest-agent spice-vdagent bash-completion unzip wget curl axel net-tools iputils iproute2 nano most screen less vim bzip2 lldpd mtr htop bind zstd lsof p7zip git tree zsh fastfetch gnupg eza bat fd ripgrep btop micro"
    ]
  }

  # 配置网络优化 (BBR + fq_pie)
  provisioner "shell" {
    inline = [
      "sudo mkdir -p /etc/sysctl.d",
      "echo -e 'tcp_bbr\\nsch_fq_pie' | sudo tee /etc/modules-load.d/network-tuning.conf",
      "echo 'net.core.default_qdisc=fq_pie' | sudo tee /etc/sysctl.d/99-network-optimization.conf",
      "echo 'net.ipv4.tcp_congestion_control=bbr' | sudo tee -a /etc/sysctl.d/99-network-optimization.conf",
      "sudo sysctl -p /etc/sysctl.d/99-network-optimization.conf || true"
    ]
  }

  # 安装 Docker
  provisioner "shell" {
    inline = [
      "sudo pacman -S --noconfirm --needed docker docker-compose docker-buildx",
      "sudo systemctl enable docker.service",
      "sudo usermod -aG docker root",
      "sudo mkdir -p /etc/docker"
    ]
  }

  # 配置 Docker daemon
  provisioner "file" {
    content = jsonencode({
      "log-driver" = "json-file"
      "log-opts" = {
        "max-size" = "10m"
        "max-file" = "3"
      }
      "storage-driver" = "overlay2"
      "default-address-pools" = [
        {
          "base" = "172.18.0.0/16"
          "size" = 24
        }
      ]
    })
    destination = "/tmp/daemon.json"
  }

  provisioner "shell" {
    inline = [
      "sudo mv /tmp/daemon.json /etc/docker/daemon.json"
    ]
  }

  # 安装 Zim Framework 和 Powerlevel10k
  provisioner "shell" {
    inline = [
      "sudo HOME=/root ZIM_HOME=/root/.zim curl -fsSL https://raw.githubusercontent.com/zimfw/install/master/install.zsh | sudo HOME=/root ZIM_HOME=/root/.zim zsh -f",
      "sudo grep -qx 'zmodule romkatv/powerlevel10k --use degit' /root/.zimrc || echo 'zmodule romkatv/powerlevel10k --use degit' | sudo tee -a /root/.zimrc",
      "sudo chmod +x /root/.zim/zimfw.zsh",
      "sudo HOME=/root ZIM_HOME=/root/.zim zsh -f /root/.zim/zimfw.zsh install"
    ]
  }

  # 配置 .zshrc
  provisioner "shell" {
    inline = [
      "sudo touch /root/.zshrc",
      "sudo grep -qx 'cat /etc/motd' /root/.zshrc || sudo sed -i '1i cat /etc/motd' /root/.zshrc",
      "sudo grep -qx 'fastfetch' /root/.zshrc || sudo sed -i '/^cat \\/etc\\/motd$/a fastfetch' /root/.zshrc"
    ]
  }

  # 配置 Powerlevel10k instant prompt
  provisioner "shell" {
    inline = [
      "cat <<'P10K_EOF' | sudo tee /tmp/p10k_instant_block",
      "# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.",
      "# Initialization code that may require console input (password prompts, [y/n]",
      "# confirmations, etc.) must go above this block; everything else may go below.",
      "if [[ -r \"$${XDG_CACHE_HOME:-$$HOME/.cache}/p10k-instant-prompt-$${(%):-%n}.zsh\" ]]; then",
      "  source \"$${XDG_CACHE_HOME:-$$HOME/.cache}/p10k-instant-prompt-$${(%):-%n}.zsh\"",
      "fi",
      "P10K_EOF",
      "sudo grep -q 'p10k-instant-prompt' /root/.zshrc || sudo sed -i '/^fastfetch$/r /tmp/p10k_instant_block' /root/.zshrc",
      "sudo rm -f /tmp/p10k_instant_block",
      "sudo grep -q 'source ~/.p10k.zsh' /root/.zshrc || echo -e '\\n# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.\\n[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh' | sudo tee -a /root/.zshrc",
      "sudo grep -q 'p10k finalize' /root/.zshrc || echo '(( ! $${+functions[p10k]} )) || p10k finalize' | sudo tee -a /root/.zshrc"
    ]
  }

  # 配置 CLI 别名
  provisioner "shell" {
    inline = [
      "cat <<'ALIAS_EOF' | sudo tee -a /root/.zshrc",
      "",
      "# Modern CLI tools aliases",
      "alias ls='eza --icons --group-directories-first'",
      "alias ll='eza --icons --group-directories-first -lh'",
      "alias la='eza --icons --group-directories-first -lah'",
      "alias lt='eza --icons --group-directories-first --tree'",
      "alias cat='bat --paging=never --style=plain'",
      "alias catp='bat --paging=always'",
      "alias find='fd'",
      "alias mo='micro'",
      "alias grep='rg'",
      "alias top='btop'",
      "ALIAS_EOF"
    ]
  }

  # 下载 motd 和 p10k 配置
  provisioner "shell" {
    inline = [
      "sudo touch /root/.hushlogin",
      "sudo curl -fsSL https://raw.githubusercontent.com/Lynricsy/ServerScripts/refs/heads/master/motd -o /etc/motd && sudo chmod 644 /etc/motd",
      "sudo curl -fsSL https://raw.githubusercontent.com/Lynricsy/ServerScripts/refs/heads/master/p10k.zsh -o /root/.p10k.zsh && sudo chmod 644 /root/.p10k.zsh"
    ]
  }

  # 配置 Git
  provisioner "shell" {
    inline = [
      "sudo HOME=/root git config --global user.name '${var.git_user_name}'",
      "sudo HOME=/root git config --global user.email '${var.git_user_email}'",
      "sudo HOME=/root git config --global init.defaultBranch main",
      "sudo HOME=/root git config --global color.ui auto",
      "sudo HOME=/root git config --global core.editor nano",
      "sudo HOME=/root git config --global diff.algorithm histogram",
      "sudo HOME=/root git config --global merge.conflictstyle diff3",
      "sudo HOME=/root git config --global pull.rebase false",
      "sudo HOME=/root git config --global alias.st status",
      "sudo HOME=/root git config --global alias.co checkout",
      "sudo HOME=/root git config --global alias.br branch",
      "sudo HOME=/root git config --global alias.ci commit",
      "sudo HOME=/root git config --global alias.unstage 'reset HEAD --'",
      "sudo HOME=/root git config --global alias.last 'log -1 HEAD'",
      "sudo HOME=/root git config --global alias.lg \"log --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit\"",
      "sudo HOME=/root git config --global alias.contributors 'shortlog -sn'"
    ]
  }

  # 配置 SSH
  provisioner "shell" {
    inline = [
      "sudo mkdir -p /root/.ssh && sudo chmod 700 /root/.ssh",
      "sudo chown -R root:root /root/.ssh"
    ]
  }

  # 配置 NTP
  provisioner "shell" {
    inline = [
      "echo 'NTP=time.apple.com time.windows.com' | sudo tee -a /etc/systemd/timesyncd.conf"
    ]
  }

  # 清理
  provisioner "shell" {
    inline = [
      "yes | sudo pacman -Scc",
      "sudo rm -f /var/log/*.log",
      "sudo rm -rf /var/cache/pacman/pkg/*",
      "sudo truncate -s 0 /etc/machine-id || true",
      "sudo rm -f /var/lib/dbus/machine-id || true"
    ]
  }

  # 压缩输出镜像
  post-processor "shell-local" {
    inline = [
      "echo '🗜️ 正在压缩镜像...'",
      "qemu-img convert -c -O qcow2 ${var.output_directory}/${local.output_filename} ${var.output_directory}/${local.output_filename}.compressed",
      "mv ${var.output_directory}/${local.output_filename}.compressed ${var.output_directory}/${local.output_filename}",
      "echo '✅ Arch Linux 镜像构建完成！'",
      "echo '📁 输出文件: ${var.output_directory}/${local.output_filename}'",
      "du -h ${var.output_directory}/${local.output_filename}"
    ]
  }
}
