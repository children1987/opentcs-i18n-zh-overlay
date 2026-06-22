#!/usr/bin/env bash
# uninstall.sh — 恢复 openTCS 到安装中文语言包之前的状态
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

OTCS_DIR="${1:-}"
if [ -z "$OTCS_DIR" ]; then
    echo "用法: $0 <opentcs-安装目录>"
    exit 1
fi
OTCS_DIR="$(realpath "$OTCS_DIR")"

# 查找备份
BACKUPS=($(ls -dt "$OTCS_DIR"/.i18n-zh-backup-* 2>/dev/null || true))
if [ ${#BACKUPS[@]} -eq 0 ]; then
    error "未找到备份目录 (.i18n-zh-backup-*)"
    error "请手动移除 $OTCS_DIR/i18n-overlay/ 并还原启动脚本"
    exit 1
fi

BACKUP="${BACKUPS[0]}"
info "使用备份: $BACKUP"

# 恢复启动脚本
if ls "$BACKUP"/*.sh >/dev/null 2>&1 || ls "$BACKUP"/*.bat >/dev/null 2>&1 || ls "$BACKUP"/start* >/dev/null 2>&1; then
    for f in "$BACKUP"/*; do
        base="$(basename "$f")"
        if [ -d "$OTCS_DIR/bin" ]; then
            cp "$f" "$OTCS_DIR/bin/$base"
            info "恢复: bin/$base"
        fi
    done
fi

# 恢复配置
if [ -d "$BACKUP/config" ] && [ -d "$OTCS_DIR/config" ]; then
    cp -r "$BACKUP/config"/* "$OTCS_DIR/config/" 2>/dev/null || true
    info "恢复: config/"
fi

# 移除 overlay
if [ -d "$OTCS_DIR/i18n-overlay" ]; then
    rm -rf "$OTCS_DIR/i18n-overlay"
    info "移除: i18n-overlay/"
fi

info "恢复完成！"
