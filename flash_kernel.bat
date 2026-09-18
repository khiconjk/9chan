@echo off
setlocal enabledelayedexpansion
title SAMSUNG GALAXY S9 (STARLTE) - KERNEL FLASH TOOL
color 0B

:: 0. Chuyen ve thu muc chua script
cd /d "%~dp0"

:: 1. Tim adb.exe tren he thong
set "ADB=adb"
where adb >nul 2>nul
if %errorlevel% neq 0 (
    if exist "%~dp0adb.exe" (
        set "ADB=%~dp0adb.exe"
    ) else if exist "%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe" (
        set "ADB=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe"
    ) else if exist "%USERPROFILE%\AppData\Local\Android\Sdk\platform-tools\adb.exe" (
        set "ADB=%USERPROFILE%\AppData\Local\Android\Sdk\platform-tools\adb.exe"
    ) else (
        color 0C
        echo ================================================================
        echo [LOI] Khong tim thay adb.exe tren he thong!
        echo Vui long cai dat Platform-Tools hoac copy file adb.exe vao
        echo cung thu muc voi script nay.
        echo ================================================================
        pause
        exit /b 1
    )
)

:MENU
cls
color 0B
echo ================================================================
echo          SAMSUNG S9 (STARLTE) - TWRP KERNEL FLASHER
echo ================================================================
echo.

:: 2. Tu dong quet file zip trong thu muc hien tai
set "ZIP_KSU="
set "ZIP_VANILLA="

for %%F in (*KSUN*.zip *ksu*.zip *ghost-uptime-ksu*.zip) do (
    if not defined ZIP_KSU if exist "%%F" set "ZIP_KSU=%%F"
)

for %%F in (*VANILLA*.zip *vanilla*.zip) do (
    if not defined ZIP_VANILLA if exist "%%F" set "ZIP_VANILLA=%%F"
)

echo [DANH SACH BAN BUILD PHAT HIEN TRONG THU MUC]:
if defined ZIP_KSU (
    echo   [+] KSU+SuSFS : !ZIP_KSU!
) else (
    echo   [-] KSU+SuSFS : Chua tim thay file zip KSU trong thu muc!
)

if defined ZIP_VANILLA (
    echo   [+] VANILLA   : !ZIP_VANILLA!
) else (
    echo   [-] VANILLA   : Chua tim thay file zip VANILLA trong thu muc!
)

echo.
echo ================================================================
echo   [1] Flash ban KSU + SuSFS (KernelSU-Next + SuSFS + Always-On)
echo   [2] Flash ban VANILLA (Pure Non-Root + Ghost Uptime + Always-On)
echo   [3] Kiem tra ket noi thiet bi (ADB Status)
echo   [4] Khoi dong lai vao TWRP Recovery
echo   [5] Khoi dong lai vao He dieu hanh (Android OS)
echo   [0] Thoat
echo ================================================================
echo.

set "CHOICE="
set /p CHOICE="Nhap lua chon cua ban (0-5): "

if "%CHOICE:~0,1%"=="1" goto FLASH_KSU
if "%CHOICE:~0,1%"=="2" goto FLASH_VANILLA
if "%CHOICE:~0,1%"=="3" goto CHECK_DEVICE
if "%CHOICE:~0,1%"=="4" goto REBOOT_RECOVERY
if "%CHOICE:~0,1%"=="5" goto REBOOT_SYSTEM
if "%CHOICE:~0,1%"=="0" goto EXIT_SCRIPT
echo Lua chon khong hop le, vui long thu lai!
ping -n 3 127.0.0.1 >nul
goto MENU

:FLASH_KSU
if not defined ZIP_KSU (
    color 0C
    echo.
    echo [LOI] Khong tim thay file zip KSU trong thu muc!
    echo Vui long dam bao file zip co chu "ksu" hoac "KSUN" trong ten.
    pause
    goto MENU
)
set "TARGET_ZIP=!ZIP_KSU!"
set "TARGET_TYPE=KSU_SUSFS"
goto DO_FLASH

:FLASH_VANILLA
if not defined ZIP_VANILLA (
    color 0C
    echo.
    echo [LOI] Khong tim thay file zip VANILLA trong thu muc!
    echo Vui long dam bao file zip co chu "VANILLA" trong ten.
    pause
    goto MENU
)
set "TARGET_ZIP=!ZIP_VANILLA!"
set "TARGET_TYPE=VANILLA"
goto DO_FLASH

:DO_FLASH
cls
color 0E
echo ================================================================
echo   TIEN HANH FLASH: !TARGET_ZIP!
echo ================================================================
echo.

:: Kiem tra va dua thiet bi ve TWRP Recovery
call :ENSURE_RECOVERY
if !errorlevel! neq 0 (
    pause
    goto MENU
)

echo.
echo [1/3] Dang nap file !TARGET_ZIP! vao dien thoai (/tmp/kernel_flash.zip)...
"%ADB%" push "!TARGET_ZIP!" /tmp/kernel_flash.zip
if !errorlevel! neq 0 (
    color 0C
    echo [LOI] Nap file qua ADB that bai! Kiem tra lai ket noi cap USB.
    pause
    goto MENU
)

echo.
echo [2/3] Dang cai dat Kernel qua TWRP CLI...
"%ADB%" shell twrp install /tmp/kernel_flash.zip
if !errorlevel! neq 0 (
    color 0C
    echo [LOI] Qua trinh cai dat TWRP tra ve ma loi!
    pause
    goto MENU
)

echo.
echo [3/3] Dang don dep file tam tren thiet bi...
"%ADB%" shell rm -f /tmp/kernel_flash.zip

color 0A
echo.
echo ================================================================
echo [THANH CONG] Da flash xong ban !TARGET_TYPE! vao Samsung S9!
echo ================================================================
echo.
set "ANS=Y"
set /p ANS="Ban co muon khoi dong lai may vao Android OS ngay khong? (Y/n): "
if /i "!ANS!"=="Y" (
    echo Dang khoi dong lai vao Android...
    "%ADB%" reboot
    echo Hoan tat. Chuc ban trai nghiem muot ma!
) else if "!ANS!"=="" (
    echo Dang khoi dong lai vao Android...
    "%ADB%" reboot
    echo Hoan tat. Chuc ban trai nghiem muot ma!
) else (
    echo Thiet bi van dang o che do TWRP.
)
pause
goto MENU

:ENSURE_RECOVERY
echo [*] Dang kiem tra trang thai ket noi ADB...
set "DEV_STATE=NONE"

for /f "tokens=1,2" %%A in ('"%ADB%" devices') do (
    if "%%B"=="device" set "DEV_STATE=device"
    if "%%B"=="recovery" set "DEV_STATE=recovery"
)

if "!DEV_STATE!"=="NONE" (
    color 0C
    echo.
    echo [LOI] Khong tim thay thiet bi nao ket noi qua ADB!
    echo Vui long kiem tra:
    echo  1. Cap USB da cam chac chan.
    echo  2. Neu may dang o Android: Da bat USB Debugging.
    echo  3. Neu may dang o TWRP: TWRP da nap xong giao dien.
    exit /b 1
)

if "!DEV_STATE!"=="device" (
    echo [*] Thiet bi dang o Android OS. Dang tu dong chuyen vao TWRP Recovery...
    "%ADB%" reboot recovery
    echo [*] Dang doi thiet bi vao TWRP Recovery (vui long cho trong giay lat)...
    set /a WAIT_COUNT=0
    :WAIT_REC_LOOP
    ping -n 3 127.0.0.1 >nul
    set /a WAIT_COUNT+=2
    set "CURRENT_STATE=NONE"
    for /f "tokens=1,2" %%A in ('"%ADB%" devices') do (
        if "%%B"=="recovery" set "CURRENT_STATE=recovery"
    )
    if "!CURRENT_STATE!"=="recovery" (
        echo [*] Thiet bi da vao TWRP Recovery thanh cong!
        ping -n 2 127.0.0.1 >nul
        exit /b 0
    )
    if !WAIT_COUNT! geq 60 (
        color 0C
        echo [LOI] Qua thoi gian cho thiet bi vao TWRP Recovery!
        exit /b 1
    )
    goto WAIT_REC_LOOP
)

if "!DEV_STATE!"=="recovery" (
    echo [*] Thiet bi da o san trong TWRP Recovery!
    exit /b 0
)

exit /b 0

:CHECK_DEVICE
cls
echo ================================================================
echo               KIEM TRA KET NOI THIET BI
echo ================================================================
echo.
"%ADB%" devices -l
echo.
pause
goto MENU

:REBOOT_RECOVERY
cls
echo [*] Dang khoi dong lai vao TWRP Recovery...
"%ADB%" reboot recovery
echo Da gui lenh reboot recovery!
pause
goto MENU

:REBOOT_SYSTEM
cls
echo [*] Dang khoi dong lai vao Android OS...
"%ADB%" reboot
echo Da gui lenh reboot system!
pause
goto MENU

:EXIT_SCRIPT
cls
echo Tam biet!
exit /b 0
