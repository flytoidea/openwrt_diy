#!/bin/bash
# 适配 h68k-tv 子型号的打包脚本，对齐 Flippy 原版逻辑
# 依赖：openwrt_packit 仓库环境、public_funcs 函数库

# ===================== 1. 环境初始化 =====================
echo "========================= begin mk_rk3568_h68k-tv.sh ====================="
# 加载全局配置和公共函数
source ./make.env || { echo "ERROR: 找不到 make.env 文件"; exit 1; }
source ./public_funcs || { echo "ERROR: 找不到 public_funcs 文件"; exit 1; }
# 初始化工作目录（临时目录、输出目录）
init_work_env

# ===================== 2. 网络加速配置 =====================
# 沿用原版 H68K 的网络优化参数，可根据自己需求调整
SW_FLOWOFFLOAD=0
HW_FLOWOFFLOAD=0
SFE_FLOW=1
export SW_FLOWOFFLOAD HW_FLOWOFFLOAD SFE_FLOW

# ===================== 3. 硬件核心定义（关键修改） =====================
PLATFORM=rockchip
SOC=rk3568
# 核心：你的子型号名称
BOARD=h68k-tv
# 接收脚本运行参数（如版本后缀）
SUBVER=$1
# 内核分支限制，和原版 H68K 一致
KERNEL_TAGS="rk35xx"
KERNEL_BRANCHES="bsp:rk35xx:>=:5.10 mainline:all:>=:6.1"

# ===================== 4. 内核包路径配置 =====================
MODULES_TGZ=${KERNEL_PKG_HOME}/modules-${KERNEL_VERSION}.tar.gz
BOOT_TGZ=${KERNEL_PKG_HOME}/boot-${KERNEL_VERSION}.tar.gz
DTBS_TGZ=${KERNEL_PKG_HOME}/dtb-rockchip-${KERNEL_VERSION}.tar.gz
# 检查内核包是否存在，缺失则退出
check_file ${MODULES_TGZ}
check_file ${BOOT_TGZ}
check_file ${DTBS_TGZ}

# ===================== 5. RootFS 配置 =====================
# 自动查找当前目录下的 OpenWrt rootfs 包
OPWRT_ROOTFS_GZ=$(get_openwrt_rootfs_archive ${PWD})
check_file ${OPWRT_ROOTFS_GZ}
echo "Use OpenWrt RootFS: ${OPWRT_ROOTFS_GZ}"

# ===================== 6. 输出固件命名 =====================
TGT_IMG="${WORK_DIR}/openwrt_${SOC}_${BOARD}_${OPENWRT_VER}_k${KERNEL_VERSION}${SUBVER}.img"

# ===================== 7. 硬件适配文件路径（对齐原版） =====================
# 沿用原版 H68K 的适配文件，可替换为自己的定制文件
CPUSTAT_SCRIPT="${PWD}/files/cpustat"
DAEMON_JSON="${PWD}/files/rk3568/h68k/daemon.json"
BAL_CONFIG="${PWD}/files/rk3568/h68k/balance_irq"
WIRELESS_CONFIG="${PWD}/files/rk3568/h68k/wireless"
NETWORK_SERVICE_PATCH="${PWD}/files/rk3568/h68k/network.patch"
BOARD_HOME="${PWD}/files/rk3568/h68k/board.d"
BOARD_MODULES_HOME="${PWD}/files/rk3568/h68k/modules.d"
BOOTFILES_HOME="${PWD}/files/bootfiles/rockchip/rk3568/h68k"
BOOTLOADER_IMG="${PWD}/files/rk3568/h68k/bootloader.bin"
FIRSTRUN_SCRIPT="${PWD}/files/first_run.sh"
BANNER="${PWD}/files/banner"

# ===================== 8. 自定义 DTB 替换（核心步骤） =====================
# 定义你的 DTB 路径：放在仓库 files/rk3568/h68k-tv/dtb 目录下
CUSTOM_DTB="${PWD}/files/rk3568/h68k-tv/dtb/rk3568-hlink-h68k-tv.dtb"
# 检查自定义 DTB 是否存在
check_file ${CUSTOM_DTB}

# ===================== 9. 镜像分区与文件系统配置 =====================
# 分区大小沿用原版 H68K 配置，可根据自己存储调整
SKIP_MB=16
BOOT_MB=256
ROOTFS_MB=960
SIZE=$((SKIP_MB + BOOT_MB + ROOTFS_MB + 1))
# 创建空镜像
create_image "${TGT_IMG}" "${SIZE}"
# 创建 GPT 分区表（boot: ext4, rootfs: btrfs）
create_partition "${TGT_DEV}" "gpt" "${SKIP_MB}" "${BOOT_MB}" "ext4" "0" "-1" "btrfs"
# 格式化分区并挂载
make_filesystem "${TGT_DEV}" "B" "ext4" "EMMC_BOOT" "R" "btrfs" "EMMC_ROOTFS1"
mount_fs "${TGT_DEV}p1" "${TGT_BOOT}" "ext4"
mount_fs "${TGT_DEV}p2" "${TGT_ROOT}" "btrfs" "compress=zstd:${ZSTD_LEVEL}"
# 创建 btrfs etc 子卷
btrfs subvolume create "${TGT_ROOT}/etc"

# ===================== 10. 解压 RootFS 和内核文件 =====================
extract_rootfs_files
# 解压内核 boot 包和 dtb 包到临时 boot 目录
extract_rockchip_boot_files

# ===================== 11. 覆盖为自定义 DTB（关键） =====================
echo "开始替换自定义 DTB: rk3568-hlink-h68k-tv.dtb"
OFFICIAL_DTB_PATH="${TGT_BOOT}/dtb/rockchip/rk3568-hlink-h68k-tv.dtb"
# 创建 dtb 目录（防止不存在）
mkdir -p $(dirname ${OFFICIAL_DTB_PATH})
# 强制覆盖
cp -f ${CUSTOM_DTB} ${OFFICIAL_DTB_PATH}
echo "自定义 DTB 替换完成: ${OFFICIAL_DTB_PATH}"

# ===================== 12. 修改 armbianEnv.txt（关键） =====================
echo "修改 armbianEnv.txt 配置，指定自定义 DTB"
cd ${TGT_BOOT}
# 删除原有 fdtfile 配置
sed -i '/fdtfile=/d' armbianEnv.txt
# 写入你的 DTB 路径
echo "fdtfile=rockchip/rk3568-hlink-h68k-tv.dtb" >> armbianEnv.txt
# 补全根分区配置（和原版一致）
sed -i '/rootdev=/d' armbianEnv.txt
sed -i '/rootfstype=/d' armbianEnv.txt
sed -i '/rootflags=/d' armbianEnv.txt
echo "rootdev=UUID=${ROOTFS_UUID}" >> armbianEnv.txt
echo "rootfstype=btrfs" >> armbianEnv.txt
echo "rootflags=compress=zstd:${ZSTD_LEVEL}" >> armbianEnv.txt
cd -

# ===================== 13. 系统定制（对齐原版） =====================
copy_supplement_files
adjust_docker_config
adjust_openssh_config
adjust_turboacc_config
write_banner
write_first_run_script
create_fstab_config
apply_network_patch

# ===================== 14. 清理与输出固件 =====================
umount_fs "${TGT_BOOT}"
umount_fs "${TGT_ROOT}"
clean_work_env
# 移动固件到输出目录
mv ${TGT_IMG} ${OUTPUT_DIR}/
sync
echo "========================= end mk_rk3568_h68k-tv.sh ====================="
echo "固件生成完成: ${OUTPUT_DIR}/$(basename ${TGT_IMG})"