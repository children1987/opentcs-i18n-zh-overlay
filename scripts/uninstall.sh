#!/usr/bin/env bash
# uninstall.sh — 恢复 openTCS 到安装中文语言包之前的状态
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

OTCS_ROOT="${1:-}"
if [ -z "$OTCS_ROOT" ]; then
    echo "用法: $0 <opentcs-7.3.0-bin目录>"
    exit 1
fi
OTCS_ROOT="$(realpath "$OTCS_ROOT")"

# 查找最新备份
BACKUPS=($(ls -dt "$OTCS_ROOT"/.i18n-zh-backup-* 2>/dev/null || true))
if [ ${#BACKUPS[@]} -eq 0 ]; then
    error "未找到备份目录 (.i18n-zh-backup-*)"
    error "请手动移除各子应用中的 i18n-overlay/ 并还原启动脚本"
    exit 1
fi

BACKUP="${BACKUPS[0]}"
info "使用备份: $BACKUP"

# 子应用列表
ALL_APPS=("opentcs-kernel" "opentcs-kernelcontrolcenter" "opentcs-modeleditor" "opentcs-operationsdesk")

for app in "${ALL_APPS[@]}"; do
    app_dir="$OTCS_ROOT/$app"
    [ -d "$app_dir" ] || continue

    # 恢复启动脚本（在子应用根目录）
    for f in "$BACKUP/$app"/start*; do
        [ -f "$f" ] || continue
        base="$(basename "$f")"
        cp "$f" "$app_dir/$base"
        info "恢复: $app/$base"
    done

    # 恢复配置
    if [ -d "$BACKUP/$app/config" ] && [ -d "$app_dir/config" ]; then
        cp -r "$BACKUP/$app/config"/* "$app_dir/config/" 2>/dev/null || true
        info "恢复: $app/config/"
    fi

    # 移除 overlay
    if [ -d "$app_dir/i18n-overlay" ]; then
        rm -rf "$app_dir/i18n-overlay"
        info "移除: $app/i18n-overlay/"
    fi
done

# 清理备份（可选）
# rm -rf "$BACKUP"
info "恢复完成！备份保留在: $BACKUP"
