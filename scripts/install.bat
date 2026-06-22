@echo off
chcp 65001 >nul 2>&1
REM install.bat - openTCS Chinese language pack installer (Windows)
REM Usage: install.bat <opentcs-7.3.0-bin-dir>
REM
REM openTCS 7.x structure (startup scripts at sub-app root, not bin\):
REM   opentcs-7.3.0-bin\
REM   +-- opentcs-kernel\
REM   |   +-- startKernel.bat
REM   |   +-- startKernel.sh
REM   |   +-- lib\  config\  bin\(splash only)
REM   +-- opentcs-kernelcontrolcenter\
REM   |   +-- startKernelControlCenter.bat
REM   |   +-- lib\  config\  bin\
REM   +-- opentcs-modeleditor\
REM   |   +-- startModelEditor.bat
REM   |   +-- lib\  config\  bin\
REM   +-- opentcs-operationsdesk\
REM       +-- startOperationsDesk.bat
REM       +-- lib\  config\  bin\
setlocal enabledelayedexpansion

if "%~1"=="" (
    echo Usage: %~nx0 ^<opentcs-7.3.0-bin-dir^>
    echo Example: %~nx0 C:\opentcs-7.3.0-bin
    exit /b 1
)

set "OTCS_ROOT=%~f1"
if not exist "!OTCS_ROOT!\" (
    echo [ERROR] Directory not found: !OTCS_ROOT!
    exit /b 1
)

REM ---- project paths ----
set "SCRIPT_DIR=%~dp0"
set "PROJECT_ROOT=!SCRIPT_DIR!.."
set "OVERLAY_SRC=!PROJECT_ROOT!\i18n-overlay"

if not exist "!OVERLAY_SRC!\" (
    echo [ERROR] i18n-overlay\ not found
    echo Please run this script from the scripts\ directory
    exit /b 1
)

REM ---- detect sub-applications ----
set "FOUND="
for %%A in (opentcs-kernel opentcs-kernelcontrolcenter opentcs-modeleditor opentcs-operationsdesk) do (
    if exist "!OTCS_ROOT!\%%A\" (
        if defined FOUND (set "FOUND=!FOUND! %%A") else (set "FOUND=%%A")
    )
)

if not defined FOUND (
    echo [ERROR] No openTCS sub-application directories found
    echo Make sure !OTCS_ROOT! is the extracted opentcs-7.3.0-bin directory
    exit /b 1
)

echo [INFO] Found sub-apps: !FOUND!

REM ==== Step 1: Backup ====================================
set "TS=%date:~0,4%%date:~5,2%%date:~8,2%_%time:~0,2%%time:~3,2%%time:~6,2%"
set "TS=!TS: =0!"
set "BACKUP_DIR=!OTCS_ROOT!\.i18n-zh-backup-!TS!"
echo [INFO] Creating backup: !BACKUP_DIR!
mkdir "!BACKUP_DIR!" 2>nul

for %%A in (!FOUND!) do (
    set "APP_DIR=!OTCS_ROOT!\%%A"
    mkdir "!BACKUP_DIR!\%%A" 2>nul
    REM backup startup scripts at sub-app root
    for %%F in ("!APP_DIR!\start*.bat" "!APP_DIR!\start*.sh") do (
        if exist %%F copy /y %%F "!BACKUP_DIR!\%%A\" >nul 2>&1
    )
    REM backup config
    if exist "!APP_DIR!\config\" (
        mkdir "!BACKUP_DIR!\%%A\config" 2>nul
        xcopy /e /q /y "!APP_DIR!\config\*" "!BACKUP_DIR!\%%A\config\" >nul 2>&1
    )
)
echo [INFO] Backup complete

REM ==== Step 2: Copy i18n-overlay =========================
echo [INFO] Copying translation files...
for %%A in (!FOUND!) do (
    set "OVERLAY_DST=!OTCS_ROOT!\%%A\i18n-overlay"
    if exist "!OVERLAY_DST!\" rmdir /s /q "!OVERLAY_DST!"
    xcopy /e /q /i "!OVERLAY_SRC!" "!OVERLAY_DST!" >nul
    echo   %%A\ - done
)

REM ==== Step 3: Patch startup scripts =====================
echo [INFO] Patching startup scripts...

for %%A in (!FOUND!) do (
    set "APP_DIR=!OTCS_ROOT!\%%A"
    echo   %%A\
    REM Scripts are at sub-app root, not in bin\
    for %%F in ("!APP_DIR!\start*.bat") do (
        call :patch_bat "%%F"
    )
    for %%F in ("!APP_DIR!\start*.cmd") do (
        call :patch_bat "%%F"
    )
    REM Also patch .sh scripts for WSL / Git Bash users
    for %%F in ("!APP_DIR!\start*.sh") do (
        call :patch_sh "%%F"
    )
)

REM ==== Step 4: Set locale=zh =============================
echo [INFO] Setting locale to zh...
if exist "!OTCS_ROOT!\opentcs-kernelcontrolcenter\config\" (
    call :set_locale "!OTCS_ROOT!\opentcs-kernelcontrolcenter" "kernelcontrolcenter"
)
if exist "!OTCS_ROOT!\opentcs-modeleditor\config\" (
    call :set_locale "!OTCS_ROOT!\opentcs-modeleditor" "modeleditor"
)
if exist "!OTCS_ROOT!\opentcs-operationsdesk\config\" (
    call :set_locale "!OTCS_ROOT!\opentcs-operationsdesk" "operationsdesk"
)

REM ==== Done ==============================================
echo.
echo ===========================================
echo   openTCS Chinese language pack installed!
echo ===========================================
echo.
echo Start as usual:
for %%A in (!FOUND!) do (
    for %%F in ("!OTCS_ROOT!\%%A\start*.bat") do (
        echo   %%F
    )
)
echo.
echo To uninstall: !PROJECT_ROOT!\scripts\uninstall.bat !OTCS_ROOT!
echo Backup saved to: !BACKUP_DIR!
exit /b 0


REM ========================================================
REM Subroutine: patch Windows bat startup script
REM openTCS 7.x bat format:
REM   set OPENTCS_CP=%OPENTCS_LIBDIR%\*;
REM   set OPENTCS_CP=%OPENTCS_CP%;...
REM We MODIFY the first line to prepend overlay BEFORE the lib dir:
REM   set OPENTCS_CP=%OPENTCS_BASE%\i18n-overlay;%OPENTCS_LIBDIR%\*;
REM (can't insert a new line because the next "set OPENTCS_CP="
REM  without %OPENTCS_CP% reference would overwrite it)
REM ========================================================
:patch_bat
set "script=%~1"
set "name=%~nx1"

if not exist "!script!" exit /b

findstr /c:"i18n-overlay" "!script!" >nul 2>&1
if !errorlevel! equ 0 (
    echo     !name! - already patched, skipping
    exit /b
)

REM Modify the first "set OPENTCS_CP=" line to prepend overlay
findstr /c:"set OPENTCS_CP=" "!script!" >nul 2>&1
if !errorlevel! equ 0 (
    set "tmpfile=!script!.tmp"
    set "done=0"
    (
        for /f "usebackq delims=" %%L in ("!script!") do (
            set "line=%%L"
            if "!done!"=="0" (
                echo !line! | findstr /c:"set OPENTCS_CP=" >nul
                if !errorlevel! equ 0 (
                    REM Replace the first OPENTCS_CP line: prepend overlay path
                    REM Output literal: set OPENTCS_CP=%OPENTCS_BASE%\i18n-overlay;%OPENTCS_LIBDIR%\*;
                    echo set OPENTCS_CP=%%OPENTCS_BASE%%\i18n-overlay;%%OPENTCS_LIBDIR%%\*;
                    set "done=1"
                ) else (
                    echo !line!
                )
            ) else (
                echo !line!
            )
        )
    ) > "!tmpfile!"
    move /y "!tmpfile!" "!script!" >nul
    echo     !name! - patched
    exit /b
)

echo     !name! - unknown format, please add i18n-overlay to classpath manually
exit /b


REM ========================================================
REM Subroutine: patch shell startup script (for WSL/Git Bash)
REM ========================================================
:patch_sh
set "script=%~1"
set "name=%~nx1"

if not exist "!script!" exit /b

grep -q "i18n-overlay" "!script!" 2>nul
if !errorlevel! equ 0 (
    echo     !name! - already patched
    exit /b
)

REM Check if sed is available (Git Bash / WSL)
where sed >nul 2>&1
if !errorlevel! neq 0 exit /b

sed -i '/^set OPENTCS_CP=%OPENTCS_LIBDIR%/i\
# === openTCS i18n-zh overlay ===\
set OPENTCS_CP=%OPENTCS_BASE%/i18n-overlay;\
' "!script!" 2>nul
if !errorlevel! equ 0 (
    echo     !name! - patched
) else (
    echo     !name! - sed failed, skipping
)
exit /b


REM ========================================================
REM Subroutine: set locale=zh in config file
REM ========================================================
:set_locale
set "app_dir=%~1"
set "locale_key=%~2"
set "app_name=%~nx1"

set "custom_file=!app_dir!\config\!app_name!-defaults-custom.properties"
set "prop_file=!app_dir!\config\!app_name!.properties"

for %%F in ("!custom_file!" "!prop_file!") do (
    if exist %%F (
        findstr /c:"!locale_key!.locale=" %%F >nul 2>&1
        if !errorlevel! equ 0 (
            set "tmp=%%F.tmp"
            (
                for /f "usebackq delims=" %%L in (%%F) do (
                    set "line=%%L"
                    echo !line! | findstr /c:"!locale_key!.locale=" >nul
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
        echo   %%~nxF -^> !locale_key!.locale=zh
        exit /b
    )
)
echo   !app_name! - config file not found, skipping
exit /b
