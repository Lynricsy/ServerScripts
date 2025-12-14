# CachyOS 定制镜像构建 - HashiCorp Packer 混合版本
# 创建时间: 2025-12-14
# 创建者: Mare Ashley Pecker (mare@sent.com)
# 说明: 使用 Packer QEMU builder 启动 VM 进行配置，最后用 virt-customize 清理

packer {
  required_plugins {
    qemu = {
      version = ">= 1.1.0"
      source  = "github.com/hashicorp/qemu"
    }
  }
}

# ============================================================
# 变量定义
# ============================================================
variable "output_directory" {
  type        = string
  default     = "output"
  description = "输出目录"
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

variable "disk_size" {
  type        = string
  default     = "8G"
  description = "磁盘大小"
}

variable "timezone" {
  type        = string
  default     = "Asia/Hong_Kong"
  description = "时区"
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

variable "ssh_password" {
  type        = string
  default     = "packer"
  description = "临时 SSH 密码"
  sensitive   = true
}

# ============================================================
# 本地变量
# ============================================================
locals {
  base_image_url    = "https://fastly.mirror.pkgbuild.com/images/latest/Arch-Linux-x86_64-cloudimg.qcow2"
  base_image_sha256 = "file:https://fastly.mirror.pkgbuild.com/images/latest/Arch-Linux-x86_64-cloudimg.qcow2.SHA256"
  base_image_name   = "Arch-Linux-x86_64-cloudimg.qcow2"
  output_name       = "CachyOS-NEXT.qcow2"
  scripts_dir       = "${path.root}/../scripts"

  # cloud-init 配置
  cloud_init_meta = <<-EOF
    instance-id: packer-cachyos
    local-hostname: cachyos-build
  EOF

  cloud_init_user = <<-EOF
    #cloud-config
    users:
      - name: root
        lock_passwd: false
        hashed_passwd: $6$rounds=4096$packer$xxxxxxxxxxxxxxxxxxxxxxxxx
        shell: /bin/bash
        ssh_authorized_keys: []
      - name: packer
        sudo: ALL=(ALL) NOPASSWD:ALL
        lock_passwd: false
        plain_text_passwd: ${var.ssh_password}
        shell: /bin/bash
    ssh_pwauth: true
    disable_root: false
    chpasswd:
      expire: false
      users:
        - name: root
          password: ${var.ssh_password}
          type: text
        - name: packer
          password: ${var.ssh_password}
          type: text
    runcmd:
      - systemctl enable sshd
      - systemctl start sshd
  EOF
}

# ============================================================
# QEMU Builder
# ============================================================
source "qemu" "cachyos" {
  # 基础镜像
  iso_url      = local.base_image_url
  iso_checksum = local.base_image_sha256
  disk_image   = true

  # 输出配置
  output_directory = var.output_directory
  vm_name          = local.output_name

  # 磁盘配置
  format           = "qcow2"
  disk_size        = var.disk_size
  disk_compression = true
  skip_resize_disk = false

  # VM 资源
  memory      = var.memory
  cpus        = var.cpus
  accelerator = "kvm"
  headless    = true

  # QEMU 参数
  qemuargs = [
    ["-cpu", "host"],
    ["-machine", "type=q35,accel=kvm"],
    ["-smbios", "type=1,serial=ds=nocloud"],
  ]

  # cloud-init 通过 CD-ROM 注入
  cd_content = {
    "meta-data" = local.cloud_init_meta
    "user-data" = local.cloud_init_user
  }
  cd_label = "cidata"

  # SSH 配置
  ssh_username         = "packer"
  ssh_password         = var.ssh_password
  ssh_timeout          = "30m"
  ssh_handshake_attempts = 100

  # 关机命令
  shutdown_command = "sudo shutdown -P now"
}

# ============================================================
# 构建流程
# ============================================================
build {
  name    = "cachyos"
  sources = ["source.qemu.cachyos"]

  # ----------------------------------------------------------
  # 1. 等待系统就绪
  # ----------------------------------------------------------
  provisioner "shell" {
    inline = [
      "echo '⏳ 等待 cloud-init 完成...'",
      "sudo cloud-init status --wait || true",
      "echo '✅ 系统已就绪'"
    ]
  }

  # ----------------------------------------------------------
  # 2. 配置时区和 Locale
  # ----------------------------------------------------------
  provisioner "shell" {
    inline = [
      "echo '🌍 配置时区和语言环境...'",
      "sudo ln -sf /usr/share/zoneinfo/${var.timezone} /etc/localtime",
      "sudo hwclock --systohc",
      "sudo sed -i 's/^#zh_CN.UTF-8 UTF-8/zh_CN.UTF-8 UTF-8/' /etc/locale.gen",
      "sudo sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen",
      "sudo locale-gen",
      "echo 'LANG=${var.locale}' | sudo tee /etc/locale.conf"
    ]
  }

  # ----------------------------------------------------------
  # 3. 配置 GRUB
  # ----------------------------------------------------------
  provisioner "shell" {
    inline = [
      "echo '⚙️ 配置 GRUB...'",
      "echo '# disables OS prober to avoid loopback detection' | sudo tee -a /etc/default/grub",
      "echo 'GRUB_DISABLE_OS_PROBER=true' | sudo tee -a /etc/default/grub",
      "sudo systemctl enable serial-getty@ttyS1.service || true"
    ]
  }

  # ----------------------------------------------------------
  # 4. 初始化 Pacman
  # ----------------------------------------------------------
  provisioner "shell" {
    inline = [
      "echo '🔑 初始化 Pacman...'",
      "sudo pacman-key --init",
      "sudo pacman-key --populate archlinux"
    ]
  }

  # ----------------------------------------------------------
  # 5. 配置镜像源
  # ----------------------------------------------------------
  provisioner "shell" {
    inline = [
      "echo '🌐 配置镜像源...'",
      "cat <<'EOF' | sudo tee /etc/pacman.d/mirrorlist",
      "# Hong Kong mirrors",
      "Server = https://mirror.xtom.com.hk/archlinux/$repo/os/$arch",
      "Server = https://mirror-hk.koddos.net/archlinux/$repo/os/$arch",
      "EOF",
      "sudo pacman -Syu --noconfirm"
    ]
  }

  # ----------------------------------------------------------
  # 6. 安装 CachyOS 仓库
  # ----------------------------------------------------------
  provisioner "shell" {
    inline = [
      "echo '🚀 安装 CachyOS 仓库...'",
      "sudo pacman -S --noconfirm --needed gawk",
      "sudo pacman-key --recv-keys F3B607488DB35A47 --keyserver keyserver.ubuntu.com",
      "sudo pacman-key --lsign-key F3B607488DB35A47",
      "sudo pacman -U --noconfirm 'https://mirror.cachyos.org/repo/x86_64/cachyos/cachyos-keyring-20240331-1-any.pkg.tar.zst' 'https://mirror.cachyos.org/repo/x86_64/cachyos/cachyos-mirrorlist-22-1-any.pkg.tar.zst' 'https://mirror.cachyos.org/repo/x86_64/cachyos/cachyos-v3-mirrorlist-22-1-any.pkg.tar.zst' 'https://mirror.cachyos.org/repo/x86_64/cachyos/cachyos-v4-mirrorlist-22-1-any.pkg.tar.zst'"
    ]
  }

  # ----------------------------------------------------------
  # 7. 配置 CachyOS 镜像列表
  # ----------------------------------------------------------
  provisioner "shell" {
    inline = [
      "cat <<'EOF' | sudo tee /etc/pacman.d/cachyos-mirrorlist",
      "# CachyOS mirrors (x86_64)",
      "Server = https://mirror.funami.tech/cachy/repo/$arch/$repo",
      "Server = https://cdn77.cachyos.org/repo/$arch/$repo",
      "Server = https://mirror.cachyos.org/repo/$arch/$repo",
      "EOF",
      "",
      "cat <<'EOF' | sudo tee /etc/pacman.d/cachyos-v4-mirrorlist",
      "# CachyOS v4 mirrors (x86_64_v4)",
      "Server = https://mirror.funami.tech/cachy/repo/x86_64_v4/$repo",
      "Server = https://cdn77.cachyos.org/repo/x86_64_v4/$repo",
      "Server = https://mirror.cachyos.org/repo/x86_64_v4/$repo",
      "EOF"
    ]
  }

  # ----------------------------------------------------------
  # 8. 配置 pacman.conf
  # ----------------------------------------------------------
  provisioner "shell" {
    inline = [
      "echo '📦 配置 pacman.conf...'",
      "sudo sed -i 's/^Architecture = .*/Architecture = x86_64 x86_64_v4/' /etc/pacman.conf",
      "sudo sed -i '/^\\[core\\]/i # CachyOS Repositories (x86-64-v4 optimized)\\n[cachyos-v4]\\nInclude = /etc/pacman.d/cachyos-v4-mirrorlist\\n\\n[cachyos-core-v4]\\nInclude = /etc/pacman.d/cachyos-v4-mirrorlist\\n\\n[cachyos-extra-v4]\\nInclude = /etc/pacman.d/cachyos-v4-mirrorlist\\n\\n[cachyos]\\nInclude = /etc/pacman.d/cachyos-mirrorlist\\n' /etc/pacman.conf",
      "echo '' | sudo tee -a /etc/pacman.conf",
      "echo '# Arch Linux CN Repository' | sudo tee -a /etc/pacman.conf",
      "echo '[archlinuxcn]' | sudo tee -a /etc/pacman.conf",
      "echo 'Server = https://mirror.xtom.com.hk/archlinuxcn/$arch' | sudo tee -a /etc/pacman.conf",
      "sudo pacman -Syyu --noconfirm"
    ]
  }

  # ----------------------------------------------------------
  # 9. 处理 pacman.conf.pacnew (如果存在)
  # ----------------------------------------------------------
  provisioner "shell" {
    inline = [
      "if [ -f /etc/pacman.conf.pacnew ]; then",
      "  echo '🔧 处理 pacman.conf.pacnew...'",
      "  sudo cp /etc/pacman.conf /etc/pacman.conf.backup",
      "  sudo mv /etc/pacman.conf.pacnew /etc/pacman.conf",
      "  sudo sed -i 's/^Architecture = .*/Architecture = x86_64 x86_64_v4/' /etc/pacman.conf",
      "  sudo sed -i '/^\\[core\\]/i # CachyOS Repositories (x86-64-v4 optimized)\\n[cachyos-v4]\\nInclude = /etc/pacman.d/cachyos-v4-mirrorlist\\n\\n[cachyos-core-v4]\\nInclude = /etc/pacman.d/cachyos-v4-mirrorlist\\n\\n[cachyos-extra-v4]\\nInclude = /etc/pacman.d/cachyos-v4-mirrorlist\\n\\n[cachyos]\\nInclude = /etc/pacman.d/cachyos-mirrorlist\\n' /etc/pacman.conf",
      "  echo '' | sudo tee -a /etc/pacman.conf",
      "  echo '# Arch Linux CN Repository' | sudo tee -a /etc/pacman.conf",
      "  echo '[archlinuxcn]' | sudo tee -a /etc/pacman.conf",
      "  echo 'Server = https://mirror.xtom.com.hk/archlinuxcn/$arch' | sudo tee -a /etc/pacman.conf",
      "  sudo pacman -Sy",
      "fi"
    ]
  }

  # ----------------------------------------------------------
  # 10. 安装 archlinuxcn-keyring
  # ----------------------------------------------------------
  provisioner "shell" {
    inline = [
      "sudo pacman -S --noconfirm --needed archlinuxcn-keyring"
    ]
  }

  # ----------------------------------------------------------
  # 11. 替换为 CachyOS 内核
  # ----------------------------------------------------------
  provisioner "shell" {
    inline = [
      "echo '🐧 安装 CachyOS 内核...'",
      "sudo pacman -R --noconfirm linux linux-headers || true",
      "sudo pacman -S --noconfirm --needed linux-cachyos linux-cachyos-headers",
      "sudo pacman -S --noconfirm --needed cachyos-settings scx-scheds",
      "sudo grub-mkconfig -o /boot/grub/grub.cfg || true"
    ]
  }

  # ----------------------------------------------------------
  # 12. 安装软件包
  # ----------------------------------------------------------
  provisioner "shell" {
    inline = [
      "echo '📦 安装软件包...'",
      "sudo pacman -S --noconfirm --needed sudo qemu-guest-agent spice-vdagent bash-completion unzip wget curl axel net-tools iputils iproute2 nano most screen less vim bzip2 lldpd mtr htop bind zstd lsof p7zip git tree zsh fastfetch gnupg eza bat fd ripgrep btop micro docker docker-compose docker-buildx cloud-init"
    ]
  }

  # ----------------------------------------------------------
  # 13. 配置 cloud-init 兼容性
  # ----------------------------------------------------------
  # 注意: datasource_list 配置针对 Proxmox/私有云环境优化
  # 如果要部署到 AWS/GCP/Azure 等公有云，需要删除或修改 99-proxmox.cfg
  provisioner "shell" {
    inline = [
      "echo '☁️ 配置 cloud-init...'",
      "sudo rm -f /etc/cloud/cloud-init.disabled || true",
      "sudo install -d -m 0755 /etc/cloud/cloud.cfg.d",
      "cat <<'EOF' | sudo tee /etc/cloud/cloud.cfg.d/99-proxmox.cfg",
      "# Proxmox / NoCloud / ConfigDrive 兼容性增强",
      "# 注意: 此配置针对 Proxmox/私有云环境，公有云部署需删除此文件",
      "datasource_list: [ NoCloud, ConfigDrive, None ]",
      "EOF",
      "sudo systemctl enable cloud-init-local.service cloud-init.service cloud-config.service cloud-final.service cloud-init.target || true",
      "sudo systemctl enable systemd-networkd.service systemd-resolved.service || true",
      "sudo systemctl enable sshd.service || true"
    ]
  }

  # ----------------------------------------------------------
  # 14. 配置 DHCP fallback (最低优先级)
  # ----------------------------------------------------------
  # 使用 zz- 前缀确保最低优先级，只在 cloud-init 网络配置失败时生效
  # cloud-init 通常生成 10-cloud-init-xxx.network，优先级更高
  provisioner "shell" {
    inline = [
      "sudo install -d -m 0755 /etc/systemd/network",
      "cat <<'EOF' | sudo tee /etc/systemd/network/zz-fallback-dhcp.network",
      "# Fallback DHCP 配置 - 最低优先级",
      "# 仅在 cloud-init 网络配置失败或不存在时生效",
      "[Match]",
      "Name=en* eth* ens* enp* eno*",
      "",
      "[Network]",
      "DHCP=yes",
      "EOF"
    ]
  }

  # ----------------------------------------------------------
  # 15. 上传并执行通用配置脚本
  # ----------------------------------------------------------
  provisioner "file" {
    source      = "${local.scripts_dir}/common-provision.sh"
    destination = "/tmp/common-provision.sh"
  }

  provisioner "shell" {
    environment_vars = [
      "HOME=/root",
      "GIT_USER_NAME=${var.git_user_name}",
      "GIT_USER_EMAIL=${var.git_user_email}"
    ]
    inline = [
      "chmod +x /tmp/common-provision.sh",
      "sudo -E /tmp/common-provision.sh",
      "rm -f /tmp/common-provision.sh"
    ]
  }

  # ----------------------------------------------------------
  # 16. 配置 NTP
  # ----------------------------------------------------------
  provisioner "shell" {
    inline = [
      "echo 'NTP=time.apple.com time.windows.com' | sudo tee -a /etc/systemd/timesyncd.conf"
    ]
  }

  # ----------------------------------------------------------
  # 17. 运行时清理 (在 VM 内可以做的)
  # ----------------------------------------------------------
  provisioner "shell" {
    inline = [
      "echo '🧹 运行时清理...'",
      "sudo rm -rf /var/cache/pacman/pkg/* /var/lib/pacman/sync/*",
      "sudo rm -f /var/log/*.log",
      "yes | sudo pacman -Scc || true",
      "sync"
    ]
  }

  # ----------------------------------------------------------
  # 18. 使用 virt-customize 进行最终清理
  # ----------------------------------------------------------
  post-processor "shell-local" {
    inline = [
      "echo '🧹 执行最终清理 (virt-customize)...'",
      "chmod +x ${local.scripts_dir}/final-cleanup.sh",
      "${local.scripts_dir}/final-cleanup.sh ${var.output_directory}/${local.output_name}"
    ]
  }

  # ----------------------------------------------------------
  # 19. 压缩镜像
  # ----------------------------------------------------------
  post-processor "shell-local" {
    inline = [
      "echo '🗜️ 压缩镜像...'",
      "qemu-img convert -c -O qcow2 ${var.output_directory}/${local.output_name} ${var.output_directory}/${local.output_name}.compressed",
      "mv ${var.output_directory}/${local.output_name}.compressed ${var.output_directory}/${local.output_name}",
      "echo ''",
      "echo '================================================'",
      "echo '✅ CachyOS 镜像构建完成！'",
      "echo '📁 输出文件: ${var.output_directory}/${local.output_name}'",
      "du -h ${var.output_directory}/${local.output_name}",
      "echo ''",
      "echo '🚀 CachyOS 特性：'",
      "echo '  🐧 CachyOS 优化内核 (linux-cachyos)'",
      "echo '  📦 x86-64-v4 优化包仓库 (AVX-512)'",
      "echo '  ⚡ 性能提升 5%-20%'",
      "echo '  🔧 包含 scx-scheds 调度器'",
      "echo '================================================'"
    ]
  }
}
