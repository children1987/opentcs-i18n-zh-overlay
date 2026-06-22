@echo off
REM uninstall.bat — 恢复 openTCS 到安装中文语言包之前的状态 (Windows)
setlocal enabledelayedexpansion

if "%~1"=="" (
    echo 用法: %~nx0 ^<opentcs-7.3.0-bin目录^>
    exit /b 1
)

set "OTCS_ROOT=%~f1"
if not exist "!OTCS_ROOT!\" (
    echo [ERROR] 目录不存在: !OTCS_ROOT!
    exit /b 1
)

REM 查找最新备份
set "BACKUP="
for /f "delims=" %%D in ('dir /b /ad /o-n "!OTCS_ROOT!\.i18n-zh-backup-*" 2^>nul') do (
    if not defined BACKUP set "BACKUP=%%D"
)

if not defined BACKUP (
    echo [ERROR] 未找到备份目录 ^(.i18n-zh-backup-*^)
    echo 请手动移除各子应用中的 i18n-overlay\ 并还原启动脚本
    exit /b 1
)

set "BACKUP_DIR=!OTCS_ROOT!\!BACKUP!"
echo [INFO] 使用备份: !BACKUP!

set APPS=opentcs-kernel opentcs-kernelcontrolcenter opentcs-modeleditor opentcs-operationsdesk

for %%A in (%APPS%) do (
    set "app_dir=!OTCS_ROOT!\%%A"
    if exist "!app_dir!\" (

        REM 恢复启动脚本
        if exist "!BACKUP_DIR!\%%A\bin\" (
            xcopy /e /q /y "!BACKUP_DIR!\%%A\bin\*" "!app_dir!\bin\" >nul 2>&1
            echo [INFO] 恢复: %%A\bin\
        )

        REM 恢复配置
        if exist "!BACKUP_DIR!\%%A\config\" (
            xcopy /e /q /y "!BACKUP_DIR!\%%A\config\*" "!app_dir!\config\" >nul 2>&1
            echo [INFO] 恢复: %%A\config\
        )

        REM 移除 overlay
        if exist "!app_dir!\i18n-overlay\" (
            rmdir /s /q "!app_dir!\i18n-overlay"
            echo [INFO] 移除: %%A\i18n-overlay\
        )
    )
)

echo [INFO] 恢复完成！备份保留在: !BACKUP_DIR!
