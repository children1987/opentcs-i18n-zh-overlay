#!/usr/bin/env bash
# install.sh — openTCS 中文语言包安装脚本
# 用法: ./install.sh <opentcs安装目录>
#
# 原理：将 i18n-overlay/ 目录加入 classpath 最前面，
# Java ResourceBundle 会优先加载 overlay 中的 _zh.properties 文件。
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# ─── 参数检查 ─────────────────────────────────────────
if [ $# -ne 1 ]; then
    echo "用法: $0 <opentcs-安装目录>"
    echo "示例: $0 /opt/opentcs-7.3.0"
    exit 1
fi

OTCS_DIR="$(realpath "$1")"
if [ ! -d "$OTCS_DIR" ]; then
    error "目录不存在: $OTCS_DIR"
    exit 1
fi

# ─── 查找本脚本所在的项目根目录 ─────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
OVERLAY_SRC="$PROJECT_ROOT/i18n-overlay"

if [ ! -d "$OVERLAY_SRC" ]; then
    error "找不到 i18n-overlay/ 目录"
    error "请确认你在项目根目录的 scripts/ 中运行此脚本"
    exit 1
fi

# 检查 openTCS 目录结构
HAS_BIN=false; HAS_LIB=false; HAS_CONFIG=false
[ -d "$OTCS_DIR/bin" ] && HAS_BIN=true
[ -d "$OTCS_DIR/lib" ] && HAS_LIB=true
[ -d "$OTCS_DIR/config" ] && HAS_CONFIG=true

if ! $HAS_BIN && ! $HAS_LIB; then
    error "$OTCS_DIR 不像是 openTCS 安装目录（缺少 bin/ 或 lib/）"
    error "请确认解压后的 openTCS 目录结构正确"
    exit 1
fi

# ─── Step 1: 备份 ──────────────────────────────────────
BACKUP_DIR="$OTCS_DIR/.i18n-zh-backup-$(date +%Y%m%d_%H%M%S)"
info "创建备份: $BACKUP_DIR"
mkdir -p "$BACKUP_DIR"

# 备份启动脚本
if $HAS_BIN; then
    for f in "$OTCS_DIR/bin/"*; do
        [ -f "$f" ] && cp "$f" "$BACKUP_DIR/"
    done
fi

# 备份配置文件
if $HAS_CONFIG; then
    cp -r "$OTCS_DIR/config" "$BACKUP_DIR/" 2>/dev/null || true
fi
info "备份完成 ($BACKUP_DIR)"

# ─── Step 2: 复制翻译文件 ──────────────────────────────
OVERLAY_DST="$OTCS_DIR/i18n-overlay"
info "复制中文翻译文件..."
if [ -d "$OVERLAY_DST" ]; then
    warn "目标已存在 i18n-overlay/，将被覆盖"
    rm -rf "$OVERLAY_DST"
fi
cp -r "$OVERLAY_SRC" "$OVERLAY_DST"
FILE_COUNT=$(find "$OVERLAY_DST" -type f | wc -l)
info "已复制 $FILE_COUNT 个文件到 $OVERLAY_DST"

# ─── Step 3: 补丁启动脚本 —— classpath 注入 ────────────
if $HAS_BIN; then
    info "修改启动脚本，注入 overlay classpath..."

    patch_script() {
        local script="$1"
        local name
        name="$(basename "$script")"

        # 跳过非启动脚本和已经打过补丁的
        if ! echo "$name" | grep -qE '^(start|run)'; then
            return
        fi
        if grep -q 'i18n-overlay' "$script" 2>/dev/null; then
            info "  $name — 已打过补丁，跳过"
            return
        fi

        local patched=false

        # 策略1: OPENTCS_CP + OPENTCS_LIBDIR 变量拼接 (openTCS 4.x/5.x 风格)
        #   export OPENTCS_CP="${OPENTCS_LIBDIR}/*"
        #   → 改为在前面加 overlay
        if grep -q 'OPENTCS_CP=' "$script" 2>/dev/null; then
            if grep -q 'OPENTCS_CP=.*OPENTCS_LIBDIR' "$script" 2>/dev/null; then
                # 在第一个 OPENTCS_CP 定义行前插入 overlay
                sed -i '/^export OPENTCS_CP=.*OPENTCS_LIBDIR/{
                    i\export OPENTCS_CP="${OPENTCS_BASE}/i18n-overlay"
                }' "$script"
                patched=true
            fi
        fi

        # 策略2: Gradle Application Plugin 风格 (7.x)
        #   CLASSPATH=$APP_HOME/lib/xxx.jar:$APP_HOME/lib/yyy.jar
        if ! $patched && grep -q '^CLASSPATH=' "$script" 2>/dev/null; then
            sed -i 's|^CLASSPATH="\?\(.*\)|CLASSPATH="$APP_HOME/i18n-overlay:\1|' "$script"
            patched=true
        fi

        # 策略3: 直接在 java/eval 行前插入 CLASSPATH
        if ! $patched; then
            # 在 java 命令或 eval 命令前插入 export
            if grep -qE '(^\s*\$JAVA|^\s*eval|\-classpath|\-cp)' "$script" 2>/dev/null; then
                # 在第一个 exec/eval/java 行前插入
                sed -i '/^[^#]*\(exec\|eval\|\$JAVA\|\$JAVACMD\)/{
                    i\# === openTCS i18n-zh overlay ===
                    i\CLASSPATH="$APP_HOME/i18n-overlay${CLASSPATH:+:$CLASSPATH}"
                    i\export CLASSPATH
                }' "$script"
                patched=true
            fi
        fi

        if $patched; then
            info "  $name ✓"
        else
            warn "  $name — 无法识别脚本格式，请手动将 i18n-overlay/ 加入 classpath"
        fi
    }

    for script in "$OTCS_DIR/bin/"*; do
        [ -f "$script" ] && patch_script "$script"
    done
fi

# ─── Step 4: 配置 locale=zh ────────────────────────────
if $HAS_CONFIG; then
    info "配置语言为中文..."

    declare -A LOCALE_KEYS=(
        ["opentcs-kernelcontrolcenter"]="kernelcontrolcenter"
        ["opentcs-modeleditor"]="modeleditor"
        ["opentcs-operationsdesk"]="operationsdesk"
    )

    for prefix in "${!LOCALE_KEYS[@]}"; do
        key="${LOCALE_KEYS[$prefix]}"
        config_file="$OTCS_DIR/config/${prefix}.properties"
        defaults_file="$OTCS_DIR/config/${prefix}-defaults-custom.properties"

        # 优先在 custom 文件设置
        for cf in "$defaults_file" "$config_file"; do
            if [ -f "$cf" ]; then
                if grep -q "^${key}\.locale=" "$cf" 2>/dev/null; then
                    sed -i "s/^${key}\.locale=.*/${key}.locale=zh/" "$cf"
                else
                    echo "${key}.locale=zh" >> "$cf"
                fi
                info "  $(basename "$cf") → ${key}.locale=zh"
                break
            fi
        done
    done
else
    warn "config/ 目录不存在，请手动设置各应用 locale=zh"
fi

# ─── 完成 ──────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════"
echo "  openTCS 中文语言包安装完成！"
echo "═══════════════════════════════════════════"
echo ""
echo "启动方式（与官方完全相同）："
[ -f "$OTCS_DIR/bin/startKernel" ]            && echo "  $OTCS_DIR/bin/startKernel"
[ -f "$OTCS_DIR/bin/startKernel.sh" ]         && echo "  $OTCS_DIR/bin/startKernel.sh"
[ -f "$OTCS_DIR/bin/startKernelControlCenter" ]    && echo "  $OTCS_DIR/bin/startKernelControlCenter"
[ -f "$OTCS_DIR/bin/startKernelControlCenter.sh" ] && echo "  $OTCS_DIR/bin/startKernelControlCenter.sh"
[ -f "$OTCS_DIR/bin/startModelEditor" ]       && echo "  $OTCS_DIR/bin/startModelEditor"
[ -f "$OTCS_DIR/bin/startModelEditor.sh" ]    && echo "  $OTCS_DIR/bin/startModelEditor.sh"
[ -f "$OTCS_DIR/bin/startOperationsDesk" ]    && echo "  $OTCS_DIR/bin/startOperationsDesk"
[ -f "$OTCS_DIR/bin/startOperationsDesk.sh" ] && echo "  $OTCS_DIR/bin/startOperationsDesk.sh"
echo ""
echo "如需恢复原始状态，备份在: $BACKUP_DIR"
