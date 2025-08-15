#!/bin/sh

# OpenWrt fdisk 精确扩容脚本
# 功能：将根分区扩容至设备最大扇区（不判断是否已接近）
# 运行环境：initramfs 或 recovery（根分区未挂载）

# 获取根设备和分区号
ROOTDEV=$(mount | grep ' / ' | awk '{print $1}' | sed -r 's/p?[0-9]+$//')
PARTNUM=$(echo $(basename $(mount | grep ' / ' | awk '{print $1}')) | sed -E 's/.*p?([0-9]+)$/\1/')

if [ -z "$ROOTDEV" ]; then
    echo "错误：无法检测根设备（/dev/mmcblk0 或 /dev/sda）"
    exit 1
fi

if [ -z "$PARTNUM" ]; then
    echo "错误：无法检测根分区号"
    exit 1
fi

ROOTPART="${ROOTDEV}p${PARTNUM}"

echo "检测到根设备: $ROOTDEV"
echo "根分区: $ROOTPART"

# 检查设备是否存在
if [ ! -b "$ROOTDEV" ]; then
    echo "错误：设备 $ROOTDEV 不存在或不是块设备"
    exit 1
fi

# 获取设备参数
SECTOR_SIZE=$(blockdev --getss "$ROOTDEV")
DEV_SECTORS=$(blockdev --getsize "$ROOTDEV")  # 总扇区数
START_SECTOR=$(fdisk -l "$ROOTDEV" 2>/dev/null | grep "$ROOTPART " | awk '{print $2}')

if [ -z "$START_SECTOR" ]; then
    echo "错误：无法获取分区 $ROOTPART 的起始扇区"
    exit 1
fi

# 设置结束扇区为：设备总扇区数 - 1（最后一个可用扇区）
END_SECTOR=$((DEV_SECTORS - 1))

echo "起始扇区: $START_SECTOR"
echo "结束扇区: $END_SECTOR (设备末尾)"
echo "总可用空间: $(( (END_SECTOR - START_SECTOR + 1) * SECTOR_SIZE / 1024 / 1024 )) MiB"

# ========================
# 使用 fdisk 删除并重建分区
# ========================

echo "警告：即将删除并重建分区 $PARTNUM，起始扇区不变，结束扇区设为 $END_SECTOR"
echo "继续？(y/N)"
read -r CONFIRM
[ "$CONFIRM" != "y" ] && exit 1

cat << EOF | fdisk "$ROOTDEV"
d               # 删除分区
$PARTNUM        # 分区号
n               # 新建分区
p               # 主分区
$PARTNUM        # 分区号
$START_SECTOR   # 起始扇区（保持不变）
$END_SECTOR     # 结束扇区（精确到最后一个扇区）
w               # 写入分区表
EOF

echo "✅ 分区表已更新：分区 $ROOTPART 已扩容至扇区 $END_SECTOR"

# 通知内核重读分区表
partprobe "$ROOTDEV" 2>/dev/null || blockdev --rereadpt "$ROOTDEV"
sleep 2

# 检查新分区是否存在
if [ ! -b "$ROOTPART" ]; then
    echo "错误：分区 $ROOTPART 创建失败，请检查设备状态"
    exit 1
fi

# 调整文件系统大小
if command -v resize2fs >/dev/null; then
    echo "🔄 正在调整 ext4 文件系统大小: resize2fs $ROOTPART"
    resize2fs "$ROOTPART"
    echo "✅ 文件系统已扩展至最大容量"
else
    echo "⚠️ 未安装 resize2fs，请运行：opkg install e2fsprogs"
fi

echo "--------------------------------------------------"
echo "🎉 扩容完成！请重启系统以确保稳定运行。"
echo "--------------------------------------------------"