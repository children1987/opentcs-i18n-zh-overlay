@echo off
chcp 65001 >nul 2>&1
REM uninstall.bat - restore openTCS to pre-i18n-zh state (Windows)
setlocal enabledelayedexpansion

if "%~1"=="" (
    echo Usage: %~nx0 ^<opentcs-7.3.0-bin-dir^>
    exit /b 1
)

set "OTCS_ROOT=%~f1"
if not exist "!OTCS_ROOT!\" (
    echo [ERROR] Directory not found: !OTCS_ROOT!
    exit /b 1
)

REM Find latest backup
set "BACKUP="
for /f "delims=" %%D in ('dir /b /ad /o-n "!OTCS_ROOT!\.i18n-zh-backup-*" 2^>nul') do (
    if not defined BACKUP set "BACKUP=%%D"
)

if not defined BACKUP (
    echo [ERROR] No backup found (.i18n-zh-backup-*)
    echo Please remove i18n-overlay\ manually and restore startup scripts
    exit /b 1
)

set "BACKUP_DIR=!OTCS_ROOT!\!BACKUP!"
echo [INFO] Using backup: !BACKUP!

set APPS=opentcs-kernel opentcs-kernelcontrolcenter opentcs-modeleditor opentcs-operationsdesk

for %%A in (%APPS%) do (
    set "app_dir=!OTCS_ROOT!\%%A"
    if exist "!app_dir!\" (

        REM Restore startup scripts
        if exist "!BACKUP_DIR!\%%A\bin\" (
            xcopy /e /q /y "!BACKUP_DIR!\%%A\bin\*" "!app_dir!\bin\" >nul 2>&1
            echo [INFO] Restored: %%A\bin\
        )

        REM Restore config
        if exist "!BACKUP_DIR!\%%A\config\" (
            xcopy /e /q /y "!BACKUP_DIR!\%%A\config\*" "!app_dir!\config\" >nul 2>&1
            echo [INFO] Restored: %%A\config\
        )

        REM Remove overlay
        if exist "!app_dir!\i18n-overlay\" (
            rmdir /s /q "!app_dir!\i18n-overlay"
            echo [INFO] Removed: %%A\i18n-overlay\
        )
    )
)

echo [INFO] Uninstall complete. Backup kept at: !BACKUP_DIR!
