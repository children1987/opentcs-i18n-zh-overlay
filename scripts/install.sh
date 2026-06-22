#!/usr/bin/env bash
# install.sh — openTCS 中文语言包安装脚本
# 用法: ./install.sh <opentcs-7.3.0-bin目录>
#
# openTCS 7.x binary 结构（每个应用独立子目录，启动脚本在子应用根目录）：\n#   opentcs-7.3.0-bin/\n#   ├── opentcs-kernel/\n#   │   ├── startKernel     ← 脚本在根目录，不在 bin/\n#   │   ├── bin/            ← 仅 splash 图片\n#   │   ├── lib/*.jar\n#   │   └── config/\n#   ├── opentcs-kernelcontrolcenter/\n#   │   ├── startKernelControlCenter\n#   │   ├── bin/  lib/  config/\n#   ├── opentcs-modeleditor/\n#   │   ├── startModelEditor\n#   │   ├── bin/  lib/  config/\n#   └── opentcs-operationsdesk/\n#       ├── startOperationsDesk\n#       ├── bin/  lib/  config/
#
# 原理：将 i18n-overlay/ 复制到每个应用的目录下，
# 并在 classpath 最前面注入该路径，Java ResourceBundle
# 优先加载 overlay 中的 _zh.properties。
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# ─── 参数检查 ─────────────────────────────────────────
if [ $# -ne 1 ]; then
    echo "用法: $0 <opentcs-7.3.0-bin目录>"
    echo "示例: $0 /opt/opentcs-7.3.0-bin"
    exit 1
fi

OTCS_ROOT="$(realpath "$1")"
if [ ! -d "$OTCS_ROOT" ]; then
    error "目录不存在: $OTCS_ROOT"
    exit 1
fi

# ─── 项目路径 ─────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
OVERLAY_SRC="$PROJECT_ROOT/i18n-overlay"

if [ ! -d "$OVERLAY_SRC" ]; then
    error "找不到 i18n-overlay/ 目录"
    error "请在项目根目录的 scripts/ 中运行此脚本"
    exit 1
fi

# ─── 检测 openTCS 子应用 ──────────────────────────────
# 子应用目录 → locale 配置 key 的映射
declare -A APP_KEYS=(
    ["opentcs-kernelcontrolcenter"]="kernelcontrolcenter"
    ["opentcs-modeleditor"]="modeleditor"
    ["opentcs-operationsdesk"]="operationsdesk"
)
# kernel 不需要 UI locale，但仍需 overlay（共享 i18n 资源可能被其他模块引用）
ALL_APPS=("opentcs-kernel" "opentcs-kernelcontrolcenter" "opentcs-modeleditor" "opentcs-operationsdesk")

FOUND_APPS=()
for app in "${ALL_APPS[@]}"; do
    if [ -d "$OTCS_ROOT/$app" ]; then
        FOUND_APPS+=("$app")
    fi
done

if [ ${#FOUND_APPS[@]} -eq 0 ]; then
    error "未找到任何 openTCS 子应用目录"
    error "请确认 $OTCS_ROOT 是解压后的 openTCS-7.3.0-bin 目录"
    exit 1
fi

info "检测到 ${#FOUND_APPS[@]} 个子应用: ${FOUND_APPS[*]}"

# ─── Step 1: 备份 ──────────────────────────────────────
BACKUP_DIR="$OTCS_ROOT/.i18n-zh-backup-$(date +%Y%m%d_%H%M%S)"
info "创建备份: $BACKUP_DIR"
mkdir -p "$BACKUP_DIR"

for app in "${FOUND_APPS[@]}"; do
    app_dir="$OTCS_ROOT/$app"
    # 备份启动脚本（在子应用根目录，不在 bin/）
    mkdir -p "$BACKUP_DIR/$app"
    for s in "$app_dir"/start*; do
        [ -f "$s" ] && cp -a "$s" "$BACKUP_DIR/$app/"
    done
    # 备份配置
    if [ -d "$app_dir/config" ]; then
        mkdir -p "$BACKUP_DIR/$app"
        cp -r "$app_dir/config" "$BACKUP_DIR/$app/" 2>/dev/null || true
    fi
done
info "备份完成 ($BACKUP_DIR)"

# ─── Step 2: 复制 overlay 到每个子应用 ──────────────────
info "复制中文翻译文件到各子应用..."
for app in "${FOUND_APPS[@]}"; do
    app_dir="$OTCS_ROOT/$app"
    overlay_dst="$app_dir/i18n-overlay"

    if [ -d "$overlay_dst" ]; then
        rm -rf "$overlay_dst"
    fi
    cp -r "$OVERLAY_SRC" "$overlay_dst"
    file_count=$(find "$overlay_dst" -type f | wc -l)
    info "  $app/ — $file_count 个文件"
done

# ─── Step 3: Patch 各子应用的启动脚本 ───────────────────
info "修改启动脚本，注入 overlay classpath..."

patch_script() {
    local script="$1"
    local name
    name="$(basename "$script")"

    # 跳过非启动脚本
    if ! echo "$name" | grep -qE '^(start|run)'; then
        return
    fi

    # 如果文件已修改过，警告用户重新解压
    if grep -q 'i18n-overlay' "$script" 2>/dev/null; then
        warn "    $name — 文件已被之前的安装修改"
        warn "           请从 opentcs-7.3.0-bin.zip 重新解压原始文件，再运行 install.sh"
        return
    fi

    # 判断脚本类型：shebang (#!/) → shell 脚本，否则 → batch 脚本
    if head -1 "$script" 2>/dev/null | grep -q '^#!/'; then
        # ─── Shell 脚本 (.sh) ───────────────────────────────
        # 原始: export OPENTCS_CP="${OPENTCS_LIBDIR}/*"
        # 修改为: export OPENTCS_CP="${OPENTCS_BASE}/i18n-overlay:${OPENTCS_LIBDIR}/*"
        # 第二行 ${OPENTCS_CP}:... 不变，自动继承 overlay 路径
        sed -i 's|export OPENTCS_CP="${OPENTCS_LIBDIR}/\*"|export OPENTCS_CP="${OPENTCS_BASE}/i18n-overlay:${OPENTCS_LIBDIR}/*"|' "$script"
    else
        # ─── Windows 批处理 (.bat) ─────────────────────────
        # 原始: set OPENTCS_CP=%OPENTCS_LIBDIR%\*;
        # 修改为: set OPENTCS_CP=%OPENTCS_BASE%\i18n-overlay;%OPENTCS_LIBDIR%\*;
        # 第二行 %OPENTCS_CP%;... 不变，自动继承 overlay 路径
        sed -i 's|set OPENTCS_CP=%OPENTCS_LIBDIR%\\\*;|set OPENTCS_CP=%OPENTCS_BASE%\\i18n-overlay;%OPENTCS_LIBDIR%\\*;|' "$script"
    fi

    if grep -q 'i18n-overlay' "$script" 2>/dev/null; then
        info "    $name ✓"
    else
        warn "    $name — 无法识别脚本格式，请手动将 i18n-overlay/ 加入 classpath"
    fi
}

for app in "${FOUND_APPS[@]}"; do
    app_dir="$OTCS_ROOT/$app"
    info "  $app/"
    # 脚本在子应用根目录：startKernel, startOperationsDesk 等
    for script in "$app_dir"/start*; do
        [ -f "$script" ] && [ ! -L "$script" ] && patch_script "$script"
    done
done

# ─── Step 4: 配置 locale=zh ────────────────────────────
info "配置语言为中文..."

for app in "${FOUND_APPS[@]}"; do
    key="${APP_KEYS[$app]:-}"
    if [ -z "$key" ]; then
        # kernel 不需要 locale 配置
        continue
    fi

    config_dir="$OTCS_ROOT/$app/config"
    if [ ! -d "$config_dir" ]; then
        warn "  $app — config/ 目录不存在，跳过"
        continue
    fi

    # 优先在 -defaults-custom.properties 中设置，其次在 .properties
    defaults_custom="$config_dir/${app}-defaults-custom.properties"
    app_props="$config_dir/${app}.properties"

    for cf in "$defaults_custom" "$app_props"; do
        if [ -f "$cf" ]; then
            if grep -q "^${key}\.locale=" "$cf" 2>/dev/null; then
                # 替换已有行，同时清理尾随空白
                sed -i "s/^${key}\.locale[[:space:]]*=.*/${key}.locale=zh/" "$cf"
            else
                printf '%s\n' "${key}.locale=zh" >> "$cf"
            fi
            info "  $(basename "$cf") → ${key}.locale=zh"
            break
        fi
    done
done

# ─── 完成 ──────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════"
echo "  openTCS 中文语言包安装完成！"
echo "═══════════════════════════════════════════"
echo ""
echo "启动方式（与官方完全相同）："
for app in "${FOUND_APPS[@]}"; do
    app_dir="$OTCS_ROOT/$app"
    for s in "$app_dir"/start*; do
        [ -f "$s" ] && echo "  $s"
    done
done
echo ""
echo "如需恢复，运行: $PROJECT_ROOT/scripts/uninstall.sh $OTCS_ROOT"
echo "备份位于: $BACKUP_DIR"
