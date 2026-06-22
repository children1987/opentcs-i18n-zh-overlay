@echo off
REM install.bat — openTCS 中文语言包安装脚本 (Windows)
REM 用法: install.bat <opentcs-7.3.0-bin目录>
REM
REM openTCS 7.x Windows binary 结构（每个应用独立子目录）：
REM   opentcs-7.3.0-bin\
REM   ├── opentcs-kernel\
REM   │   ├── bin\startKernel.bat
REM   │   ├── lib\*.jar
REM   │   └── config\
REM   ├── opentcs-kernelcontrolcenter\
REM   │   ├── bin\startKernelControlCenter.bat
REM   │   ├── lib\*.jar
REM   │   └── config\
REM   ├── opentcs-modeleditor\
REM   │   ├── bin\startModelEditor.bat
REM   │   ├── lib\*.jar
REM   │   └── config\
REM   └── opentcs-operationsdesk\
REM       ├── bin\startOperationsDesk.bat
REM       ├── lib\*.jar
REM       └── config\
setlocal enabledelayedexpansion

if "%~1"=="" (
    echo 用法: %~nx0 ^<opentcs-7.3.0-bin目录^>
    echo 示例: %~nx0 C:\opentcs-7.3.0-bin
    exit /b 1
)

set "OTCS_ROOT=%~f1"
if not exist "!OTCS_ROOT!\" (
    echo [ERROR] 目录不存在: !OTCS_ROOT!
    exit /b 1
)

REM ─── 项目路径 ─────────────────────────────────────────
set "SCRIPT_DIR=%~dp0"
set "PROJECT_ROOT=!SCRIPT_DIR!.."
set "OVERLAY_SRC=!PROJECT_ROOT!\i18n-overlay"

if not exist "!OVERLAY_SRC!\" (
    echo [ERROR] 找不到 i18n-overlay\ 目录
    echo 请在项目根目录的 scripts\ 中运行此脚本
    exit /b 1
)

REM ─── 检测子应用 ──────────────────────────────────────
set "FOUND="
for %%A in (opentcs-kernel opentcs-kernelcontrolcenter opentcs-modeleditor opentcs-operationsdesk) do (
    if exist "!OTCS_ROOT!\%%A\" (
        if defined FOUND (set "FOUND=!FOUND! %%A") else (set "FOUND=%%A")
    )
)

if not defined FOUND (
    echo [ERROR] 未找到任何 openTCS 子应用目录
    echo 请确认 !OTCS_ROOT! 是解压后的 opentcs-7.3.0-bin 目录
    exit /b 1
)

echo [INFO] 检测到子应用: !FOUND!

REM ─── Step 1: 备份 ──────────────────────────────────────
set "TS=%date:~0,4%%date:~5,2%%date:~8,2%_%time:~0,2%%time:~3,2%%time:~6,2%"
set "TS=!TS: =0!"
set "BACKUP_DIR=!OTCS_ROOT!\.i18n-zh-backup-!TS!"
echo [INFO] 创建备份: !BACKUP_DIR!
mkdir "!BACKUP_DIR!" 2>nul

for %%A in (!FOUND!) do (
    if exist "!OTCS_ROOT!\%%A\bin\" (
        mkdir "!BACKUP_DIR!\%%A\bin" 2>nul
        xcopy /q /y "!OTCS_ROOT!\%%A\bin\*" "!BACKUP_DIR!\%%A\bin\" >nul 2>&1
    )
    if exist "!OTCS_ROOT!\%%A\config\" (
        mkdir "!BACKUP_DIR!\%%A\config" 2>nul
        xcopy /e /q /y "!OTCS_ROOT!\%%A\config\*" "!BACKUP_DIR!\%%A\config\" >nul 2>&1
    )
)
echo [INFO] 备份完成

REM ─── Step 2: 复制 overlay ──────────────────────────────
echo [INFO] 复制中文翻译文件...
for %%A in (!FOUND!) do (
    set "OVERLAY_DST=!OTCS_ROOT!\%%A\i18n-overlay"
    if exist "!OVERLAY_DST!\" rmdir /s /q "!OVERLAY_DST!"
    xcopy /e /q /i "!OVERLAY_SRC!" "!OVERLAY_DST!" >nul
    echo   %%A\ — 完成
)

REM ─── Step 3: Patch 启动脚本 ────────────────────────────
echo [INFO] 修改启动脚本...

for %%A in (!FOUND!) do (
    set "BIN_DIR=!OTCS_ROOT!\%%A\bin"
    if exist "!BIN_DIR!\" (
        echo   %%A\bin\
        for %%F in ("!BIN_DIR!\start*.bat") do (
            call :patch_bat "%%F"
        )
        REM Also handle .cmd files if any
        for %%F in ("!BIN_DIR!\start*.cmd") do (
            call :patch_bat "%%F"
        )
    )
)

REM ─── Step 4: 配置 locale=zh ────────────────────────────
echo [INFO] 配置语言为中文...
if exist "!OTCS_ROOT!\opentcs-kernelcontrolcenter\config\" (
    call :set_locale "!OTCS_ROOT!\opentcs-kernelcontrolcenter" "kernelcontrolcenter"
)
if exist "!OTCS_ROOT!\opentcs-modeleditor\config\" (
    call :set_locale "!OTCS_ROOT!\opentcs-modeleditor" "modeleditor"
)
if exist "!OTCS_ROOT!\opentcs-operationsdesk\config\" (
    call :set_locale "!OTCS_ROOT!\opentcs-operationsdesk" "operationsdesk"
)

REM ─── 完成 ──────────────────────────────────────────────
echo.
echo ═══════════════════════════════════════════
echo   openTCS 中文语言包安装完成！
echo ═══════════════════════════════════════════
echo.
echo 启动方式（与官方完全相同）：
for %%A in (!FOUND!) do (
    for %%F in ("!OTCS_ROOT!\%%A\bin\start*.bat") do (
        echo   %%F
    )
)
echo.
echo 如需恢复，运行: !PROJECT_ROOT!\scripts\uninstall.bat !OTCS_ROOT!
echo 备份位于: !BACKUP_DIR!
exit /b 0

REM ═══════════════════════════════════════════════════════
REM 子过程: patch Windows bat 启动脚本
REM ═══════════════════════════════════════════════════════
:patch_bat
set "script=%~1"
set "name=%~nx1"

REM 检查是否已打过补丁
findstr /c:"i18n-overlay" "!script!" >nul 2>&1
if !errorlevel! equ 0 (
    echo     !name! — 已打过补丁，跳过
    exit /b
)

REM 检查文件是否存在
if not exist "!script!" exit /b

REM 策略1: CLASSPATH= 变量定义 (Gradle Application Plugin 新风格)
findstr /r "^set CLASSPATH=" "!script!" >nul 2>&1
if !errorlevel! equ 0 (
    REM 在匹配行前插入 overlay classpath
    set "tmpfile=!script!.tmp"
    set "inserted=0"
    (
        for /f "usebackq delims=" %%L in ("!script!") do (
            set "line=%%L"
            if "!inserted!"=="0" (
                echo !line! | findstr /r "^set CLASSPATH=" >nul
                if !errorlevel! equ 0 (
                    echo REM === openTCS i18n-zh overlay ===
                    echo set CLASSPATH=%%APP_HOME%%\i18n-overlay;%%CLASSPATH%%
                    set "inserted=1"
                )
            )
            echo %%L
        )
    ) > "!tmpfile!"
    move /y "!tmpfile!" "!script!" >nul
    echo     !name! — 已修改
    exit /b
)

REM 策略2: 查找 classpath 相关行或 java 命令
findstr /r "CLASSPATH\|classpath\|java\|javaw" "!script!" >nul 2>&1
if !errorlevel! equ 0 (
    set "tmpfile=!script!.tmp"
    set "inserted=0"
    (
        for /f "usebackq delims=" %%L in ("!script!") do (
            set "line=%%L"
            if "!inserted!"=="0" (
                echo !line! | findstr /r "set.*CLASSPATH\|CLASSPATH=" >nul
                if !errorlevel! equ 0 (
                    echo REM === openTCS i18n-zh overlay ===
                    echo set CLASSPATH=%%APP_HOME%%\i18n-overlay;%%CLASSPATH%%
                    set "inserted=1"
                )
            )
            echo %%L
        )
    ) > "!tmpfile!"
    move /y "!tmpfile!" "!script!" >nul
    echo     !name! — 已修改
    exit /b
)

echo     !name! — 无法识别格式，请手动加入 classpath
exit /b

REM ═══════════════════════════════════════════════════════
REM 子过程: 设置 locale=zh
REM ═══════════════════════════════════════════════════════
:set_locale
set "app_dir=%~1"
set "locale_key=%~2"
set "app_name=%~nx1"

REM 优先修改 -defaults-custom.properties，其次 .properties
set "custom_file=!app_dir!\config\!app_name!-defaults-custom.properties"
set "prop_file=!app_dir!\config\!app_name!.properties"

for %%F in ("!custom_file!" "!prop_file!") do (
    if exist %%F (
        findstr /r "^!locale_key!\.locale=" %%F >nul 2>&1
        if !errorlevel! equ 0 (
            REM 替换已有行
            set "tmp=%%F.tmp"
            (
                for /f "usebackq delims=" %%L in (%%F) do (
                    set "line=%%L"
                    echo !line! | findstr /r "^!locale_key!\.locale=" >nul
                    if !errorlevel! equ 0 (
                        echo !locale_key!.locale=zh
                    ) else (
                        echo %%L
                    )
                )
            ) > "!tmp!"
            move /y "!tmp!" %%F >nul
        ) else (
            echo !locale_key!.locale=zh >> %%F
        )
        echo   %%~nxF —^> !locale_key!.locale=zh
        exit /b
    )
)
echo   !app_name! — config 文件不存在，跳过
exit /b
