#!/usr/bin/env bash
#
# ubu-ntfs.sh - NTFS マウントスクリプト（Windows 11 高速スタートアップ対応）
#
# Windows 11 では「高速スタートアップ (Fast Startup)」や休止状態の影響で、
# NTFS ボリュームに「休止済み/hibernated」フラグが残り、ntfs-3g が
#   Windows is hibernated, refused to mount.
# というエラーで読み書きマウントを拒否することがあります。
# このスクリプトはその状態を検出し、安全にマウントします。
#
#  インストール方法（GitHub から）:
#    1) curl -fsSL -o /tmp/ubu-ntfs.sh \
#       https://raw.githubusercontent.com/hirogura/scripts/main/ubu-ntfs.sh
#    2) sudo mkdir -p /opt/ubu-ntfs
#       sudo install -m 0755 /tmp/ubu-ntfs.sh /opt/ubu-ntfs/ubu-ntfs.sh
#    ワンライナー（/opt/ubu-ntfs/ へ設置して利用）:
#       curl -fsSL https://raw.githubusercontent.com/hirogura/scripts/main/ubu-ntfs.sh \
#         | sudo tee /opt/ubu-ntfs/ubu-ntfs.sh >/dev/null
#       sudo chmod 0755 /opt/ubu-ntfs/ubu-ntfs.sh
#
#  使い方（root で実行）:
#     sudo /opt/ubu-ntfs/ubu-ntfs.sh                      すべての NTFS パーティションを検出してマウント
#     sudo /opt/ubu-ntfs/ubu-ntfs.sh /dev/vdb3            指定したパーティションだけマウント
#     sudo /opt/ubu-ntfs/ubu-ntfs.sh -r /dev/vdb3         読み取り専用でマウント（休止中でも安全）
#     sudo /opt/ubu-ntfs/ubu-ntfs.sh -k /dev/vdb3         休止/unclean フラグを処理して読み書きマウント
#                                                         ※Windows の休止状態イメージ(未保存データ)は破棄されます
#     sudo /opt/ubu-ntfs/ubu-ntfs.sh -u                   このスクリプトでマウントした物を全てアンマウント
#
#  環境変数:
#     NTFS_MOUNT_BASE   マウント先ベースディレクトリ（既定: /mnt）
#
set -euo pipefail

readonly SCRIPT_NAME="ubu-ntfs.sh"
MOUNT_BASE="${NTFS_MOUNT_BASE:-/mnt}"
READ_ONLY=""
REMOVE_HIBER=""
ACTION="mount"
declare -a REQUESTED_DEVICES=()

usage() {
    cat <<EOF
使い方: sudo $0 [オプション] [DEVICE ...]

  DEVICE 指定なしの場合は lsblk で見つかった NTFS パーティション全てを対象にします。

オプション:
  -h, --help                  このヘルプを表示
  -r, --ro                    読み取り専用でマウント（休止中/未クリーンでも安全）
  -k, --fix                   休止状態(unclean)フラグを処理して読み書きマウント
                              ※休止: remove_hiberfile / unclean: ntfsfix
                              ※Windowsの休止状態イメージ等は破棄されます（未保存データ注意）
  -u, --umount                このスクリプトでマウントしたボリュームを全てアンマウント

マウント先:  \$MOUNT_BASE/win_<ラベル>  （ラベル無しは win_<デバイス名>）
           例: /mnt/win_Local Disk, /mnt/win_vdb3
EOF
    exit 0
}

is_root() {
    [[ "$(id -u)" -eq 0 ]]
}

log() {
    printf '[%s] %s\n' "$SCRIPT_NAME" "$*"
}

err() {
    printf '[%s] ERROR: %s\n' "$SCRIPT_NAME" "$*" >&2
}

warn() {
    printf '[%s] WARN: %s\n' "$SCRIPT_NAME" "$*" >&2
}

require_cmds() {
    local missing=() c
    for c in lsblk mount umount ntfs-3g ntfs-3g.probe; do
        if ! command -v "$c" >/dev/null 2>&1; then
            missing+=("$c")
        fi
    done
    if ((${#missing[@]})); then
        err "必要なツールがありません: ${missing[*]}"
        err "インストール例（Debian/Ubuntu）: sudo apt-get install ntfs-3g util-linux"
        err "                        (RHEL系)   : sudo dnf install ntfs-3g util-linux"
        err "                        (Arch/Manjaro): sudo pacman -S ntfs-3g util-linux"
        exit 1
    fi
}

sanitize_name() {
    # マウントディレクトリ名に使えない文字を _ に置換
    printf '%s' "$1" | tr -cs '[:alnum:]_-\xc0-\xff' '_'
}

ls_ntfs_parts() {
    # NAME FSTYPE LABEL の順で空白区切りで出力（注: LABEL に空白は入らない前提）
    lsblk -rno NAME,FSTYPE,LABEL 2>/dev/null | awk '$2=="ntfs" {print $1 "\t" $3}'
}

resolve_mountpoint() {
    local name="$1" label="$2"
    local base="${label:-$name}"
    base="win_$(sanitize_name "$base")"
    printf '%s/%s' "$MOUNT_BASE" "$base"
}

is_mounted() {
    mountpoint -q "$1" 2>/dev/null
}

try_mount() {
    # $1 = ntfs-3g オプション文字列, $2 = デバイス, $3 = マウント先
    ntfs-3g -o "$1" "$2" "$3"
}

mount_one() {
    # $1 = デバイス, $2 = ラベル
    local dev="$1" label="$2" mnt rc=0 opts="" base_opts="uid=0,gid=0,umask=022"
    mnt="$(resolve_mountpoint "$(basename "$dev")" "$label")"

    if is_mounted "$mnt"; then
        log "$dev は既に $mnt にマウント済みです。"
        return 0
    fi

    if ! [[ -b "$dev" ]]; then
        err "$dev はブロックデバイスではありません。スキップします。"
        return 1
    fi

    if [[ -n "$READ_ONLY" ]]; then
        log "マウントしています(ro): $dev -> $mnt"
        if try_mount "ro,${base_opts}" "$dev" "$mnt"; then
            log "OK: $mnt"
            return 0
        fi
        err "$dev のマウントに失敗しました。"
        return 1
    fi

    ntfs-3g.probe --readwrite "$dev" >/dev/null 2>&1 || rc=$?

    case "$rc" in
        0)
            opts="rw,${base_opts}"
            ;;
        13)
            # 13 = unclean (Windows キャッシュに未保存データ / dirty フラグ)
            if [[ -n "$REMOVE_HIBER" ]]; then
                if ! command -v ntfsfix >/dev/null 2>&1; then
                    err "ntfsfix が見つかりません。インストールしてから再実行してください。"
                    return 1
                fi
                warn "$dev は unclean 状態です。ntfsfix でクリーンアップしてから読み書きマウントします。"
                if ! ntfsfix "$dev"; then
                    warn "$dev の ntfsfix に失敗しました。読み取り専用でマウントします。"
                    opts="ro,${base_opts}"
                else
                    opts="rw,${base_opts}"
                fi
            else
                warn "$dev は unclean (未クリーン) 状態のため、読み取り専用でマウントします。"
                warn "読み書きで使うには: sudo $0 -k $dev  (ntfsfix 実行後にマウント)"
                opts="ro,${base_opts}"
            fi
            ;;
        14)
            # 14 = hibernated (Windows 休止状態 / 高速スタートアップ)
            if [[ -n "$REMOVE_HIBER" ]]; then
                warn "$dev は休止状態です。remove_hiberfile を試します。"
                opts="rw,remove_hiberfile,${base_opts}"
            else
                warn "$dev は Windows の休止状態(高速スタートアップ)のため、読み取り専用でマウントします。"
                warn "読み書きで使うには: sudo $0 -k $dev"
                opts="ro,${base_opts}"
            fi
            ;;
        *)
            # それ以外(1=NTFSではない, 12=破損, ...)
            err "$dev の検査に失敗しました (ntfs-3g.probe rc=$rc)。読み取り専用で試します。"
            opts="ro,${base_opts}"
            ;;
    esac

    mkdir -p "$mnt"
    log "マウントしています: $dev -> $mnt"
    if try_mount "$opts" "$dev" "$mnt"; then
        log "OK: $mnt"
        return 0
    fi

    # 休止状態ボリュームは remove_hiberfile 後に unclean も検出されることがある
    if [[ -n "$REMOVE_HIBER" ]] && (( rc == 14 )); then
        if command -v ntfsfix >/dev/null 2>&1; then
            warn "$dev は休止状態に加えて unclean 状態の可能性があります。ntfsfix を実行します。"
            if ntfsfix "$dev" && try_mount "rw,remove_hiberfile,${base_opts}" "$dev" "$mnt"; then
                log "OK: $mnt"
                return 0
            fi
        fi
    fi

    err "$dev のマウントに失敗しました。"
    rmdir "$mnt" 2>/dev/null || true
    return 1
}

umount_one() {
    local dev="$1" label="$2" mnt
    mnt="$(resolve_mountpoint "$(basename "$dev")" "$label")"
    if is_mounted "$mnt"; then
        log "アンマウントしています: $mnt"
        umount "$mnt"
        rmdir "$mnt" 2>/dev/null || true
    fi
}

do_mount() {
    local dev label failures=0

    if ((${#REQUESTED_DEVICES[@]})); then
        local d p
        for d in "${REQUESTED_DEVICES[@]}"; do
            if [[ -b "$d" ]]; then
                label="$(lsblk -rno LABEL "$d" 2>/dev/null | head -n1 || true)"
                mount_one "$d" "$label" || failures=$((failures + 1))
            else
                err "$d は存在しないブロックデバイスです。"
                failures=$((failures + 1))
            fi
        done
        return "$failures"
    fi

    while IFS=$'\t' read -r dev label; do
        [[ -n "$dev" ]] || continue
        mount_one "/dev/$dev" "$label" || failures=$((failures + 1))
    done < <(ls_ntfs_parts)

    return "$failures"
}

do_umount() {
    # 対象は $MOUNT_BASE/win_* のみ（誤って他を外さない）
    local d
    for d in "$MOUNT_BASE"/win_*; do
        [[ -e "$d" ]] || continue
        if is_mounted "$d"; then
            log "アンマウントしています: $d"
            umount "$d"
            rmdir "$d" 2>/dev/null || true
        fi
    done
}

parse_args() {
    local arg
    for arg in "$@"; do
        case "$arg" in
            -h|--help) usage ;;
            -r|--ro) READ_ONLY=1 ;;
            -k|--fix|--remove-hiberfile) REMOVE_HIBER=1 ;;
            -u|--umount) ACTION="umount" ;;
            -*) err "不明なオプション: $arg"; usage ;;
            *) REQUESTED_DEVICES+=("$arg") ;;
        esac
    done
}

main() {
    parse_args "$@"
    if ! is_root; then
        err "root 権限で実行してください（sudo を使う）。"
        exit 1
    fi
    require_cmds

    case "$ACTION" in
        mount)
            do_mount
            ;;
        umount)
            do_umount
            ;;
    esac

    log "現在マウントされている NTFS ボリューム:"
    findmnt -rno TARGET,SOURCE,FSTYPE -t ntfs3,ntfs,fuseblk 2>/dev/null || true
}

main "$@"