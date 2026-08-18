#!/bin/bash
set -euo pipefail

MIRROR_URL="https://mirrors.aliyun.com"

# 检查是否以 root 权限运行
if [ "$(id -u)" != "0" ]; then
   echo "此脚本需要以 root 权限运行，请使用 sudo 或切换到 root 用户"
   exit 1
fi

# 检测发行版及版本代号
if [ -f /etc/os-release ]; then
    . /etc/os-release
    DISTRO=${ID,,}
    CODENAME=${VERSION_CODENAME:-}
elif command -v lsb_release >/dev/null 2>&1; then
    DISTRO=$(lsb_release -i -s | tr '[:upper:]' '[:lower:]')
    CODENAME=$(lsb_release -cs)
else
    echo "无法检测发行版和版本代号"
    exit 1
fi

if [ -z "$DISTRO" ] || [ -z "$CODENAME" ]; then
    echo "发行版或版本代号为空，检测失败"
    exit 1
fi

echo "检测到发行版: $DISTRO, 版本代号: $CODENAME"

# 备份 APT 配置
BACKUP_DIR="/etc/apt/backup.$(date +%F_%H-%M-%S)"
echo "创建备份目录: $BACKUP_DIR"
mkdir -p "$BACKUP_DIR"

shopt -s nullglob
SOURCE_PATHS=(
    /etc/apt/sources.list
    /etc/apt/sources.list.d/*.list
    /etc/apt/sources.list.d/*.sources
)
shopt -u nullglob

if [ ${#SOURCE_PATHS[@]} -eq 0 ]; then
    echo "备份失败：未找到任何 APT 源配置文件"
    exit 1
fi

for f in "${SOURCE_PATHS[@]}"; do
    dest="$BACKUP_DIR/${f#/}"
    mkdir -p -- "${dest%/*}"
    cp -a -- "$f" "$dest"
done

echo "APT 配置已备份到 $BACKUP_DIR"


# 检测版本，并替换为阿里云镜像源

# 清空旧的传统 sources.list，避免与 DEB822 双重生效
disable_legacy_sources_list() {
    if [ -s /etc/apt/sources.list ] && grep -qE '^\s*deb ' /etc/apt/sources.list; then
        echo "检测到旧 sources.list 仍有生效配置，已注释禁用（备份中保留原件）"
        sed -i 's/^\(\s*deb\s\)/#\1/' /etc/apt/sources.list
    fi
}

if [[ "$DISTRO" == "ubuntu" ]]; then
    if [ -f /etc/apt/sources.list.d/ubuntu.sources ]; then
    	echo "检测到 DEB822 配置，正在替换为阿里云镜像源..."
        # 使用 DEB822 格式的 sources.list.d
		disable_legacy_sources_list
        cat > /etc/apt/sources.list.d/ubuntu.sources <<EOF
Types: deb
URIs: $MIRROR_URL/ubuntu
Suites: $CODENAME $CODENAME-updates $CODENAME-backports
Components: main universe restricted multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg

Types: deb
URIs: $MIRROR_URL/ubuntu
Suites: $CODENAME-security
Components: main universe restricted multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
EOF
    else
        echo "检测到传统 sources.list，正在替换为阿里云镜像源..."
        # 使用传统的 sources.list
	    cat > /etc/apt/sources.list <<EOF
# === Binary Packages ===
deb $MIRROR_URL/ubuntu/ $CODENAME main restricted universe multiverse
deb $MIRROR_URL/ubuntu/ $CODENAME-security main restricted universe multiverse
deb $MIRROR_URL/ubuntu/ $CODENAME-updates main restricted universe multiverse
# deb $MIRROR_URL/ubuntu/ $CODENAME-proposed main restricted universe multiverse
deb $MIRROR_URL/ubuntu/ $CODENAME-backports main restricted universe multiverse
# === Source Packages ===
# deb-src $MIRROR_URL/ubuntu/ $CODENAME main restricted universe multiverse
# deb-src $MIRROR_URL/ubuntu/ $CODENAME-security main restricted universe multiverse
# deb-src $MIRROR_URL/ubuntu/ $CODENAME-updates main restricted universe multiverse
# deb-src $MIRROR_URL/ubuntu/ $CODENAME-proposed main restricted universe multiverse
# deb-src $MIRROR_URL/ubuntu/ $CODENAME-backports main restricted universe multiverse
EOF
    fi

elif [[ "$DISTRO" == "debian" ]]; then
    if [ -f /etc/apt/sources.list.d/debian.sources ]; then
        echo "检测到 DEB822 配置，正在替换为阿里云镜像源..."
        # 使用 DEB822 格式的 sources.list.d
		disable_legacy_sources_list
        cat > /etc/apt/sources.list.d/debian.sources <<EOF  
Types: deb
URIs: ${MIRROR_URL}/debian
Suites: $CODENAME $CODENAME-updates $CODENAME-backports
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

Types: deb
URIs: ${MIRROR_URL}/debian-security
Suites: $CODENAME-security
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF
    else
        echo "检测到传统 sources.list，正在替换为阿里云镜像源..."
        # 使用传统的 sources.list
	    cat > /etc/apt/sources.list <<EOF
# === Binary Packages ===
deb $MIRROR_URL/debian/ $CODENAME main contrib non-free non-free-firmware
deb $MIRROR_URL/debian-security/ $CODENAME-security main
deb $MIRROR_URL/debian/ $CODENAME-updates main contrib non-free non-free-firmware
deb $MIRROR_URL/debian/ $CODENAME-backports main contrib non-free non-free-firmware
# === Source Packages ===
# deb-src $MIRROR_URL/debian/ $CODENAME main contrib non-free non-free-firmware
# deb-src $MIRROR_URL/debian-security/ $CODENAME-security main
# deb-src $MIRROR_URL/debian/ $CODENAME-updates contrib non-free non-free-firmware
# deb-src $MIRROR_URL/debian/ $CODENAME-backports main contrib non-free non-free-firmware
EOF
    fi
else
    echo "不支持的发行版: $DISTRO"
    exit 1
fi

# 更新软件包索引
echo "更新软件包索引..."
if !apt-get update; then
    echo "apt update 执行失败，请检查网络或 sources.list 是否正确"
    exit 1
fi

echo "原始配置已备份至：$BACKUP_DIR"
echo "更新完成，你可以运行 'apt-get upgrade' 来升级现有软件包"

echo "阿里云镜像源配置完成"
echo "注意：源代码包（deb-src）已被注释，如需启用，请编辑当前系统使用的软件源配置文件"