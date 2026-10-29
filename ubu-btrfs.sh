#!/bin/bash
# ============================================================
#  Btrfs サブボリューム移行スクリプト（統合版）
#  実行環境: ライブUSB環境のターミナル
#  構成A: EFI + btrfs の2パーティション構成
#  構成B: EFI + ext4(/boot) + btrfs の3パーティション構成
#  EFI（UEFI）/ BIOS（Legacy）両対応
#  使い方  : sudo bash ubu-btrfs.sh
# ============================================================

set -euo pipefail

RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }
step()  { echo -e "\n${CYAN}=== $* ===${NC}"; }

[[ $EUID -ne 0 ]] && error "sudo で実行してください"

# ============================================================
# 環境検出
# ============================================================
step "環境を自動検出"

if [[ -d /sys/firmware/efi ]]; then
    BOOT_MODE="EFI"
else
    BOOT_MODE="BIOS"
fi
info "起動モード: $BOOT_MODE"

# Btrfsパーティション検出
BTRFS_PART=$(lsblk -lnpo NAME,FSTYPE | awk '$2=="btrfs"{print $1}' | head -1)
[[ -n "$BTRFS_PART" ]] || error "Btrfsパーティションが見つかりませんでした"

# ディスク本体
DISK=$(lsblk -lnpo PKNAME "$BTRFS_PART" | head -1)
[[ -n "$DISK" ]] || DISK=$(echo "$BTRFS_PART" | sed 's/p\?[0-9]*$//')
DISK="/dev/${DISK##*/}"

# EFI / BIOS ブートパーティション検出
EFI_PART=""
BIOS_BOOT_PART=""

if [[ "$BOOT_MODE" == "EFI" ]]; then
    EFI_PART=$(lsblk -lnpo NAME,PARTTYPE | \
        awk 'tolower($2) == "c12a7328-f81f-11d2-ba4b-00a0c93ec93b" {print $1}' | head -1)
    if [[ -z "$EFI_PART" ]]; then
        EFI_PART=$(lsblk -lnpo NAME,FSTYPE | awk '$2=="vfat"{print $1}' | head -1)
    fi
    [[ -n "$EFI_PART" ]] || error "EFIパーティションが見つかりませんでした"
else
    BIOS_BOOT_PART=$(lsblk -lnpo NAME,PARTTYPE | \
        awk 'tolower($2) == "21686148-6449-6e6f-744e-656564454649" {print $1}' | head -1)
    if [[ -z "$BIOS_BOOT_PART" ]]; then
        warn "BIOS Bootパーティションが見つかりません（MBRディスクでは正常）"
    else
        info "BIOS Bootパーティション: $BIOS_BOOT_PART"
    fi
fi

# ============================================================
# /boot 独立パーティション検出
# EFI・btrfs 以外の ext2/3/4 → /boot 独立パーティションと判断
# ============================================================
BOOT_PART=""
BOOT_FS=""

for part in $(lsblk -lnpo NAME,FSTYPE "$DISK" | awk '$2 ~ /^ext[234]$/ {print $1}'); do
    [[ "$part" == "$EFI_PART" ]] && continue
    [[ "$part" == "$BTRFS_PART" ]] && continue
    BOOT_PART="$part"
    BOOT_FS=$(lsblk -lnpo FSTYPE "$BOOT_PART" | head -1)
    break
done

if [[ -n "$BOOT_PART" ]]; then
    LAYOUT="3partition"
    info "構成B: 3パーティション構成（EFI + /boot独立 + btrfs）"
    info "独立 /boot パーティション: $BOOT_PART ($BOOT_FS)"
else
    LAYOUT="2partition"
    info "構成A: 2パーティション構成（EFI + btrfs）"
fi

# 結果表示
echo ""
echo "  検出結果:"
echo "  ┌──────────────────────────────────────────┐"
printf "  │  起動モード          : %-21s│\n" "$BOOT_MODE"
printf "  │  構成                : %-21s│\n" "$LAYOUT"
printf "  │  Btrfsパーティション : %-21s│\n" "$BTRFS_PART"
if [[ "$BOOT_MODE" == "EFI" ]]; then
    printf "  │  EFIパーティション   : %-21s│\n" "$EFI_PART"
else
    printf "  │  BIOS Boot           : %-21s│\n" "${BIOS_BOOT_PART:-（なし / MBR）}"
fi
printf "  │  /boot パーティション: %-21s│\n" "${BOOT_PART:-（なし / btrfs内）}"
printf "  │  ディスク            : %-21s│\n" "$DISK"
echo "  └──────────────────────────────────────────┘"
echo ""

info "ディスク構成（参考）:"
lsblk -o NAME,SIZE,FSTYPE,PARTTYPE,MOUNTPOINT "$DISK"
echo ""

warn "上記の検出結果で続行しますか？ [yes/N]"
read -r answer
[[ "$answer" == "yes" ]] || { info "中止しました。"; exit 0; }

# ============================================================
# Step 1: マウント
# ============================================================
step "Step 1: Btrfsパーティションをマウント"

info "既存マウントを解除"
for mp in $(findmnt -rno TARGET --source "$BTRFS_PART" 2>/dev/null | sort -r); do
    [[ "$mp" == "/" ]] && continue
    info "  解除: $mp"
    umount "$mp" 2>/dev/null || umount -l "$mp" 2>/dev/null || true
done
if [[ -n "${EFI_PART:-}" ]]; then
    for mp in $(findmnt -rno TARGET --source "$EFI_PART" 2>/dev/null | sort -r); do
        [[ "$mp" == "/" ]] && continue
        info "  解除 (EFI): $mp"
        umount "$mp" 2>/dev/null || umount -l "$mp" 2>/dev/null || true
    done
fi
if [[ -n "$BOOT_PART" ]]; then
    for mp in $(findmnt -rno TARGET --source "$BOOT_PART" 2>/dev/null | sort -r); do
        [[ "$mp" == "/" ]] && continue
        info "  解除 (/boot): $mp"
        umount "$mp" 2>/dev/null || umount -l "$mp" 2>/dev/null || true
    done
fi

mkdir -p /mnt
mount "$BTRFS_PART" /mnt

# 二重実行チェック
if btrfs subvolume list /mnt 2>/dev/null | grep -qE '\s@$|\s@home$'; then
    error "サブボリューム @ または @home がすでに存在します。移行済みの可能性があります。"
fi

# ============================================================
# Step 2: サブボリューム作成・データ移動
# ============================================================
step "Step 2: サブボリューム作成・データ移動"
cd /mnt

info "スナップショット @ を作成"
btrfs subvolume snapshot . @

# 3パーティション構成: @/boot/ は空のマウントポイントにする
# 2パーティション構成: @/boot/ はそのまま残す（btrfs内にカーネルが必要）
if [[ "$LAYOUT" == "3partition" ]]; then
    if [[ -d /mnt/@/boot ]]; then
        info "/boot 独立構成のため @/boot/ を空のマウントポイントとして準備"
        find /mnt/@/boot -mindepth 1 -delete
    fi
fi

info "サブボリューム @home を作成"
btrfs subvolume create @home

if [[ -d /mnt/home ]] && compgen -G "/mnt/home/*" > /dev/null 2>&1; then
    info "home/* を @home/ へコピー"
    cp -a /mnt/home/. /mnt/@home/
else
    warn "home/ が空またはありません。スキップします。"
fi

info "フラットなルートデータを削除"
for entry in /mnt/*; do
    name=$(basename "$entry")
    [[ "$name" == "@" || "$name" == "@home" ]] && continue
    if mountpoint -q "$entry" 2>/dev/null; then
        info "  アンマウント: $entry"
        umount -R "$entry" 2>/dev/null || umount -l "$entry" 2>/dev/null || true
    fi
    rm -rf "$entry"
    info "  削除: $entry"
done

# ============================================================
# Step 3: fstab 書き換え
# ============================================================
step "Step 3: fstab を更新"
FSTAB="/mnt/@/etc/fstab"
[[ -f "$FSTAB" ]] || error "fstab が見つかりません: $FSTAB"

UUID=$(blkid -s UUID -o value "$BTRFS_PART")
[[ -n "$UUID" ]] || error "UUIDの取得に失敗しました"
info "Btrfs UUID: $UUID"

BOOT_UUID=""
if [[ "$LAYOUT" == "3partition" ]]; then
    BOOT_UUID=$(blkid -s UUID -o value "$BOOT_PART")
    [[ -n "$BOOT_UUID" ]] || error "/boot UUID の取得に失敗しました"
    info "/boot UUID: $BOOT_UUID"
fi

cp "$FSTAB" "${FSTAB}.bak"
info "バックアップ: ${FSTAB}.bak"

python3 - "$FSTAB" "$UUID" "$BOOT_UUID" "${BOOT_FS:-}" << 'PYEOF'
import sys, re

fstab_path = sys.argv[1]
uuid        = sys.argv[2]
boot_uuid   = sys.argv[3]
boot_fs     = sys.argv[4]

with open(fstab_path) as f:
    lines = f.readlines()

new_lines = []
has_home  = False
has_boot  = False

for line in lines:
    stripped = line.strip()
    if stripped.startswith("#") or stripped == "":
        new_lines.append(line)
        continue
    cols = stripped.split()
    if len(cols) < 4:
        new_lines.append(line)
        continue

    mountpoint = cols[1]
    fstype     = cols[2]

    if fstype == "btrfs" and mountpoint == "/":
        opts = re.sub(r'subvol=[^,\s]+,?', '', cols[3]).strip(',')
        opts = (opts + ',subvol=@') if opts else 'defaults,subvol=@'
        new_lines.append(f"UUID={uuid} / btrfs {opts} 0 0\n")
    elif fstype == "btrfs" and mountpoint == "/home":
        opts = re.sub(r'subvol=[^,\s]+,?', '', cols[3]).strip(',')
        opts = (opts + ',subvol=@home') if opts else 'defaults,subvol=@home'
        new_lines.append(f"UUID={uuid} /home btrfs {opts} 0 0\n")
        has_home = True
    elif mountpoint == "/boot" and boot_uuid:
        new_lines.append(f"UUID={boot_uuid} /boot {boot_fs} defaults 0 2\n")
        has_boot = True
    else:
        new_lines.append(line)

if not has_home:
    new_lines.append(f"UUID={uuid} /home btrfs defaults,subvol=@home 0 0\n")
if boot_uuid and not has_boot:
    new_lines.append(f"UUID={boot_uuid} /boot {boot_fs} defaults 0 2\n")

with open(fstab_path, 'w') as f:
    f.writelines(new_lines)
PYEOF

info "更新後の fstab:"
cat "$FSTAB"

# ============================================================
# Step 4: chroot して GRUB 更新
# ============================================================
step "Step 4: chroot して GRUB を更新"

mkdir -p /mnt2
mount -t btrfs -o subvol=@ "$BTRFS_PART" /mnt2
info "subvol=@ で /mnt2 に再マウント完了"

mkdir -p /mnt2/boot/grub

# 3パーティション構成: chroot前に /boot をマウント
if [[ "$LAYOUT" == "3partition" ]]; then
    info "/boot ($BOOT_PART) を /mnt2/boot にマウント"
    mkdir -p /mnt2/boot
    mount "$BOOT_PART" /mnt2/boot
    info "  /mnt2/boot の内容:"
    ls /mnt2/boot/ || true
fi

mount --rbind /dev  /mnt2/dev  && mount --make-rslave /mnt2/dev
mount --rbind /proc /mnt2/proc && mount --make-rslave /mnt2/proc
mount --rbind /sys  /mnt2/sys  && mount --make-rslave /mnt2/sys
mount --rbind /run  /mnt2/run  && mount --make-rslave /mnt2/run

if [[ "$BOOT_MODE" == "EFI" ]]; then
    mount --bind /sys/firmware/efi/efivars /mnt2/sys/firmware/efi/efivars 2>/dev/null || \
        warn "efivars のバインドに失敗しました"
    mkdir -p /mnt2/boot/efi
    mount "$EFI_PART" /mnt2/boot/efi
    chroot /mnt2 /bin/bash -e << CHROOT
echo '[chroot] /boot の内容:'
ls /boot/ || true
echo '[chroot] grub-install (EFI) ...'
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=ubuntu --recheck
echo '[chroot] grub-mkconfig ...'
grub-mkconfig -o /boot/grub/grub.cfg
echo '[chroot] subvol 指定確認:'
grep -i subvol /boot/grub/grub.cfg | head -5 || echo '（subvol 指定なし）'
echo '[chroot] 完了'
CHROOT
else
    chroot /mnt2 /bin/bash -e << CHROOT
echo '[chroot] /boot の内容:'
ls /boot/ || true
echo '[chroot] grub-install (BIOS) ...'
grub-install --target=i386-pc --recheck $DISK
echo '[chroot] grub-mkconfig ...'
grub-mkconfig -o /boot/grub/grub.cfg
echo '[chroot] subvol 指定確認:'
grep -i subvol /boot/grub/grub.cfg | head -5 || echo '（subvol 指定なし）'
echo '[chroot] 完了'
CHROOT
fi

# ============================================================
# Step 5: アンマウント
# ============================================================
step "Step 5: アンマウント"
umount -R /mnt2 2>/dev/null || true
umount -R /mnt  2>/dev/null || true

echo ""
echo -e "${GREEN}======================================================"
echo "  移行が完了しました！"
echo "  構成: $LAYOUT"
echo "  再起動後に以下で確認してください："
echo "    sudo btrfs subvolume list /"
if [[ "$LAYOUT" == "3partition" ]]; then
echo "    findmnt -T /boot"
fi
echo -e "======================================================${NC}"
echo ""
warn "再起動しますか？ [yes/N]"
read -r reboot_answer
[[ "$reboot_answer" == "yes" ]] && reboot || info "手動で再起動してください: sudo reboot"