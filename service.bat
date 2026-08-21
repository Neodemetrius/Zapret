@echo off
chcp 1251 > nul
set "LOCAL_VERSION=1.10.1A"

:: ==================== ПУТИ ОБРАЩЕНИЯ ====================
set "BIN_PATH=%~dp0bin\"
set "LISTS_PATH=%~dp0lists\"
set "WINWS_PATH=%~dp0winws\"
Set "CONFIG_PATH=%~dp0config\"
Set "UTILS_PATH=%~dp0utils\"

:: ==================== ВНЕШНИЕ КОМАНДЫ ====================
if "%~1"=="status_zapret" (
    call :test_service zapret soft
    call :tcp_enable
    exit /b
)

if "%~1"=="check_updates" (
    if defined NO_UPDATE_CHECK exit /b

    if exist "%UTILS_PATH%\check_updates.enabled" (
        if not "%~2"=="soft" (
            start /b service check_updates soft
        ) else (
            call :service_check_updates soft
        )
    )

    exit /b
)

if "%~1"=="load_game_filter" (
    call :game_switch_status
    exit /b
)

if "%~1"=="load_user_lists" (
    call :load_user_lists
    exit /b
)

:: ==================== ПРОВЕРКА ПРАВ АДМИНИСТРАТОРА ====================
if "%1"=="admin" (
    echo Запуск от имени администратора
    
    :: Проверка необходимых системных команд
    echo Проверка системных утилит...
    call :check_command chcp
    call :check_command find
    call :check_command findstr
    call :check_command netsh
    call :check_command sc
    call :check_command reg
    call :check_command tasklist
    call :check_command taskkill
    
    echo Все необходимые утилиты найдены
    echo Запуск...
    cls
) else (
    call :check_extracted
    call :check_command powershell
	
    echo Запрос прав администратора...
    powershell -NoProfile -Command "Start-Process 'cmd.exe' -ArgumentList '/c \"\"%~f0\" admin\"' -Verb RunAs"
    exit
)

:: ==================== ГЛАВНОЕ МЕНЮ ====================
setlocal EnableDelayedExpansion
:menu
cls
call :ipset_switch_status
call :game_switch_status
call :check_updates_switch_status
call :get_strategy_name

set "menu_choice=null"

echo.
echo   Менеджер службы ZAPRET v!LOCAL_VERSION!
echo   ----------------------------------------
echo.
echo   :: Быстрый статус
echo.  !CurrentStrategy!
echo   :: Служба
echo      1. Установить службу
echo      2. Удалить службу
echo      3. Проверить статус
echo.
echo   :: Настройки
echo      4. Игровой фильтр         [!GameFilterStatus!]
echo      5. Фильтр айпи        [!IPsetStatus!]
echo      6. Проверка авто обновлений   [!CheckUpdatesStatus!]
echo      7. Замена фейка стратегии
echo.
echo   :: Обновления
echo      8. Обновить список айпи
echo      9. Обновить файл хост
echo      10. Проверить обновления
echo.
echo   :: Инструменты
echo      11. Запустить диагностику
echo      12. Запустить тестирование
echo.
echo   ----------------------------------------
echo      0. Выход
echo.

set /p menu_choice=   Введите параметр (0-11): 

if "%menu_choice%"=="1" goto service_install
if "%menu_choice%"=="2" goto service_remove
if "%menu_choice%"=="3" goto service_status
if "%menu_choice%"=="4" goto game_switch
if "%menu_choice%"=="5" goto ipset_switch
if "%menu_choice%"=="6" goto check_updates_switch
if "%menu_choice%"=="7" goto replace_fakes
if "%menu_choice%"=="8" goto ipset_update
if "%menu_choice%"=="9" goto hosts_update
if "%menu_choice%"=="10" goto service_check_updates
if "%menu_choice%"=="11" goto service_diagnostics
if "%menu_choice%"=="12" goto run_tests
if "%menu_choice%"=="0" exit /b
goto menu

:: ==================== ПРОСМОТР СТРАТЕГИИ ==================
:get_strategy_name
set "CurrentStrategy="
for /f "tokens=2*" %%A in ('reg query "HKLM\System\CurrentControlSet\Services\zapret" /v zapret 2^>nul') do set "CurrentStrategy=Стратегия: %%B"
exit /b

:: ==================== УСТАНОВКА СЛУЖБЫ ====================
:service_install
cls

:: Поиск файлов *bat в папке config, за исключением файлов, которые начинаются с "service"
echo Выберите один из вариантов:
set "count=0"

for /f "delims=" %%F in ('powershell -NoProfile -Command "Get-ChildItem -LiteralPath '!CONFIG_PATH!' -Filter '*.bat' | Where-Object { $_.Name -notlike 'service*' } | Sort-Object { [Regex]::Replace($_.Name, '(\d+)', { $args[0].Value.PadLeft(8, '0') }) } | ForEach-Object { $_.FullName }"') do (
    set /a count+=1
    echo !count!. %%~nF
    set "file!count!=%%F"
)

echo   0. Выйти
echo.

:: Выбор файла
set "choice="
set /p "choice=Индекс файла (номер): "
if "!choice!"=="" (
    echo Выбор пуст, выход...
    pause
    goto menu
)

set "selectedFile=!file%choice%!"
if not defined selectedFile (
    echo Неверный индекс, выход...
    pause
    goto menu
)

:: Вызов функции разбора аргументов и создания службы
call :parse_arguments
goto create_service

:: Создание службы
:create_service
call :tcp_enable

set ARGS=%args%
call set "ARGS=%%ARGS:EXCL_MARK=^!%%"
echo Итоговые аргументы: !ARGS!
set SRVCNAME=zapret

net stop %SRVCNAME% >nul 2>&1
sc delete %SRVCNAME% >nul 2>&1
sc create %SRVCNAME% binPath= "\"%WINWS_PATH%winws.exe\" !ARGS!" DisplayName= "zapret" start= auto
sc description %SRVCNAME% "Zapret DPI bypass software"
sc start %SRVCNAME%
for %%F in ("!file%choice%!") do (
    set "filename=%%~nF"
)
reg add "HKLM\System\CurrentControlSet\Services\zapret" /v zapret /t REG_SZ /d "!filename!" /f

pause
goto menu

:: ==================== ПАРСИНГ АРГУМЕНТОВ ====================
:parse_arguments
set "args_with_value=sni host altorder"
set "args="
set "capture=0"
set "mergeargs=0"
set QUOTE="

for /f "tokens=*" %%a in ('type "!selectedFile!"') do (
    set "line=%%a"
    call set "line=%%line:^!=EXCL_MARK%%"

    echo !line! | findstr /i "winws.exe" >nul
    if not errorlevel 1 (
        set "capture=1"
    )

    if !capture!==1 (
        if not defined args (
            set "line=!line:*winws.exe"=!"
        )

        set "temp_args="
        for %%i in (!line!) do (
            set "arg=%%i"

            if not "!arg!"=="^" (
                if "!arg:~0,2!" EQU "--" if not !mergeargs!==0 (
                    set "mergeargs=0"
                )

                if "!arg:~0,1!" EQU "!QUOTE!" (
                    set "arg=!arg:~1,-1!"

                    echo !arg! | findstr ":" >nul
                    if !errorlevel!==0 (
                        set "arg=\!QUOTE!!arg!\!QUOTE!"
                    ) else if "!arg:~0,1!"=="@" (
                        set "arg=\!QUOTE!@%~dp0!arg:~1!\!QUOTE!"
                    ) else if "!arg:~0,5!"=="%%BIN%%" (
                        set "arg=\!QUOTE!!BIN_PATH!!arg:~5!\!QUOTE!"
                    ) else if "!arg:~0,7!"=="%%LISTS%%" (
                        set "arg=\!QUOTE!!LISTS_PATH!!arg:~7!\!QUOTE!"
                    ) else (
                        set "arg=\!QUOTE!%~dp0!arg!\!QUOTE!"
                    )
                ) else if "!arg:~0,12!" EQU "%%GameFilter%%" (
                    set "arg=%GameFilter%"
                ) else if "!arg:~0,15!" EQU "%%GameFilterTCP%%" (
                    set "arg=%GameFilterTCP%"
                ) else if "!arg:~0,15!" EQU "%%GameFilterUDP%%" (
                    set "arg=%GameFilterUDP%"
                )

                if !mergeargs!==1 (
                    set "temp_args=!temp_args!,!arg!"
                ) else if !mergeargs!==3 (
                    set "temp_args=!temp_args!=!arg!"
                    set "mergeargs=1"
                ) else (
                    set "temp_args=!temp_args! !arg!"
                )

                if "!arg:~0,2!" EQU "--" (
                    set "mergeargs=2"
                ) else if !mergeargs! GEQ 1 (
                    if !mergeargs!==2 set "mergeargs=1"

                    for %%x in (!args_with_value!) do (
                        if /i "%%x"=="!arg!" (
                            set "mergeargs=3"
                        )
                    )
                )
            )
        )

        if not "!temp_args!"=="" (
            set "args=!args! !temp_args!"
        )
    )
)
exit /b

:: ==================== СТАТУС СЛУЖБЫ ====================
:service_status
cls

sc query "zapret" >nul 2>&1
if !errorlevel!==0 (
    for /f "tokens=2*" %%A in ('reg query "HKLM\System\CurrentControlSet\Services\zapret" /v zapret 2^>nul') do echo Установлена стратегия: "%%B"
)

call :test_service zapret
call :test_service WinDivert

if not exist "%WINWS_PATH%\*.sys" (
    call :PrintRed "Файл WinDivert64.sys НЕ найден."
)
echo:

tasklist /FI "IMAGENAME eq winws.exe" | find /I "winws.exe" > nul
if !errorlevel!==0 (
    call :PrintGreen "Обход (winws.exe) ЗАПУЩЕН."
) else (
    call :PrintRed "Обход (winws.exe) НЕ ЗАПУЩЕН."
)

pause
goto menu

:test_service
set "ServiceName=%~1"
set "ServiceStatus="

sc query "%ServiceName%" | findstr /i "RUNNING" > nul
if "!errorlevel!"=="0" (
    set "ServiceStatus=RUNNING"
) else (
    sc query "%ServiceName%" | findstr /i "STOP_PENDING" > nul
    if "!errorlevel!"=="0" (
        set "ServiceStatus=STOP_PENDING"
    ) else (
        set "ServiceStatus=STOPPED"
    )
)

if "%ServiceStatus%"=="RUNNING" (
    if "%~2"=="soft" (
        echo "%ServiceName%" УЖЕ ЗАПУЩЕНА как служба. Используйте "service.bat" и выберите "Удалить службу" сначала, если хотите запустить обычный бат файл.
        pause
        exit /b
    ) else (
        call :PrintGreen "Служба "%ServiceName%" ЗАПУЩЕНА."
    )
) else if "%ServiceStatus%"=="STOP_PENDING" (
    call :PrintYellow "!ServiceName! находится в состоянии ОСТАНОВКИ, это может быть вызвано конфликтом с другим обходом. Запустите диагностику для исправления конфликтов"
) else if not "%~2"=="soft" (
    call :PrintRed "Служба "%ServiceName%" НЕ ЗАПУЩЕНА."
)

exit /b

:: ==================== УДАЛЕНИЕ СЛУЖБЫ ====================
:service_remove
cls

:: Удаление службы zapret
set SRVCNAME=zapret
sc query "!SRVCNAME!" >nul 2>&1
if "!errorlevel!"=="0" (
    net stop %SRVCNAME%
    sc delete %SRVCNAME%
) else (
    echo Служба "%SRVCNAME%" не установлена.
)

tasklist /FI "IMAGENAME eq winws.exe" | find /I "winws.exe" > nul
if "!errorlevel!"=="0" (
    taskkill /IM winws.exe /F > nul
)

sc query "WinDivert" >nul 2>&1
if "!errorlevel!"=="0" (
    net stop "WinDivert"

    sc query "WinDivert" >nul 2>&1
    if "!errorlevel!"=="0" (
        sc delete "WinDivert"
    )
)
net stop "WinDivert14" >nul 2>&1
sc delete "WinDivert14" >nul 2>&1

pause
goto menu

::==================== ДИАГНОСТИКА ====================
:service_diagnostics
cls

:: Base Filtering Engine
sc query BFE | findstr /I "RUNNING" > nul
if !errorlevel!==0 (
    call :PrintGreen "Проверка Службы базовой фильтрации пройдена"
) else (
    call :PrintRed "[X]  Служба базовой фильтрации не запущена. Она необходима для работы"
)
echo:

:: Proxy check
set "proxyEnabled=0"
set "proxyServer="

for /f "tokens=2*" %%A in ('reg query "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyEnable 2^>nul ^| findstr /i "ProxyEnable"') do (
    if "%%B"=="0x1" set "proxyEnabled=1"
)

if !proxyEnabled!==1 (
    for /f "tokens=2*" %%A in ('reg query "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyServer 2^>nul ^| findstr /i "ProxyServer"') do (
        set "proxyServer=%%B"
    )
    
    call :PrintYellow "[?] Системный прокси включен: !proxyServer!"
    call :PrintYellow "Убедитесь, что он корректно настроен, или отключите его, если не используете прокси"
) else (
    call :PrintGreen "Проверка прокси пройдена"
)
echo:

:: TCP timestamps check
netsh interface tcp show global | findstr /i "timestamps" | findstr /i "enabled" > nul
if !errorlevel!==0 (
    call :PrintGreen "Проверка TCP-меток времени пройдена"
) else (
    call :PrintYellow "[?] TCP-метки времени отключены. Включение меток времени......"
    netsh interface tcp set global timestamps=enabled > nul 2>&1
    if !errorlevel!==0 (
        call :PrintGreen "TCP-метки времени успешно включены"
    ) else (
        call :PrintRed "[X]  Не удалось включить TCP-метки времени"
    )
)
echo:

:: AdguardSvc.exe
tasklist /FI "IMAGENAME eq AdguardSvc.exe" | find /I "AdguardSvc.exe" > nul
if !errorlevel!==0 (
    call :PrintRed "[X] Обнаружен процесс Adguard. Adguard может вызывать проблемы с Discord"
    call :PrintRed "https://github.com/Flowseal/zapret-discord-youtube/issues/417"
) else (
    call :PrintGreen "Проверка Adguard пройдена"
)
echo:

:: Killer
sc query | findstr /I "Killer" > nul
if !errorlevel!==0 (
    call :PrintRed "[X] Обнаружена служба Killer. Killer конфликтует с zapret"
    call :PrintRed "https://github.com/Flowseal/zapret-discord-youtube/issues/2512#issuecomment-2821119513"
) else (
    call :PrintGreen "Проверка Killer пройдена"
)
echo:

:: Intel Connectivity Network Service
sc query | findstr /I "Intel" | findstr /I "Connectivity" | findstr /I "Network" > nul
if !errorlevel!==0 (
    call :PrintRed "[X] Обнаружена служба подключения Intel. Она конфликтует с zapret"
    call :PrintRed "https://github.com/ValdikSS/GoodbyeDPI/issues/541#issuecomment-2661670982"
) else (
    call :PrintGreen "Проверка подключения Intel пройдена"
)
echo:

:: Check Point
set "checkpointFound=0"
sc query | findstr /I "TracSrvWrapper" > nul
if !errorlevel!==0 (
    set "checkpointFound=1"
)

sc query | findstr /I "EPWD" > nul
if !errorlevel!==0 (
    set "checkpointFound=1"
)

if !checkpointFound!==1 (
    call :PrintRed "[X] Обнаружена служба Check Point. Check Point конфликтует с zapret"
    call :PrintRed "Попробуйте удалить Check Point"
) else (
    call :PrintGreen "Проверка Check Point пройдена"
)
echo:

:: SmartByte
sc query | findstr /I "SmartByte" > nul
if !errorlevel!==0 (
    call :PrintRed "[X] Обнаружена служба SmartByte. SmartByte конфликтует с zapret"
    call :PrintRed "Попробуйте удалить или отключить SmartByte через services.msc"
) else (
    call :PrintGreen "Проверка SmartByte пройдена"
)
echo:

:: Файл WinDivert64.sys
if not exist "%WINWS_PATH%\*.sys" (
    call :PrintRed "Файл WinDivert64.sys НЕ найден."
    echo:
)

:: VPN
set "VPN_SERVICES="
sc query | findstr /I "VPN" > nul
if !errorlevel!==0 (
    for /f "tokens=2 delims=:" %%A in ('sc query ^| findstr /I "VPN"') do (
        if not defined VPN_SERVICES (
            set "VPN_SERVICES=!VPN_SERVICES!%%A"
        ) else (
            set "VPN_SERVICES=!VPN_SERVICES!,%%A"
        )
    )
    call :PrintYellow "[?] Обнаружены VPN-службы: !VPN_SERVICES!"
    call :PrintYellow "Некоторые VPN могут конфликтовать с zapret. Убедитесь, что все VPN отключены"
) else (
    call :PrintGreen "Проверка VPN пройдена"
)
echo:

:: DNS
set "dohfound=0"
for /f "delims=" %%a in ('powershell -NoProfile -Command "Get-ChildItem -Recurse -Path 'HKLM:System\CurrentControlSet\Services\Dnscache\InterfaceSpecificParameters\' | Get-ItemProperty | Where-Object { $_.DohFlags -gt 0 } | Measure-Object | Select-Object -ExpandProperty Count"') do (
    if %%a gtr 0 (
        set "dohfound=1"
    )
)
if !dohfound!==0 (
    call :PrintYellow "[?] Убедитесь, что вы настроили безопасный DNS в браузере с использованием стороннего DNS-провайдера,"
    call :PrintYellow "Если вы используете Windows 11, вы можете настроить зашифрованный DNS в Параметрах, чтобы скрыть это предупреждение"
) else (
    call :PrintGreen "Проверка безопасного DNS пройдена"
)
echo:

:: Проверка файла hosts
set "hostsFile=%SystemRoot%\System32\drivers\etc\hosts"
if exist "%hostsFile%" (
    set "yt_found=0"
    >nul 2>&1 findstr /I "youtube.com" "%hostsFile%" && set "yt_found=1"
    >nul 2>&1 findstr /I "youtu.be" "%hostsFile%" && set "yt_found=1"
    if !yt_found!==1 (
        call :PrintYellow "[?] Ваш файл hosts содержит записи для youtube.com или youtu.be. Это может вызвать проблемы с доступом к YouTube"
    )
)

:: Конфликтующий WinDivert
tasklist /FI "IMAGENAME eq winws.exe" | find /I "winws.exe" > nul
set "winws_running=!errorlevel!"

sc query "WinDivert" | findstr /I "RUNNING STOP_PENDING" > nul
set "windivert_running=!errorlevel!"

if !winws_running! neq 0 if !windivert_running!==0 (
    call :PrintYellow "[?] winws.exe не запущен, но служба WinDivert активна. Попытка удалить WinDivert..."
    
    net stop "WinDivert" >nul 2>&1
    sc delete "WinDivert" >nul 2>&1
    sc query "WinDivert" >nul 2>&1
    if !errorlevel!==0 (
        call :PrintRed "[X] Не удалось удалить WinDivert. Проверка конфликтующих служб..."
        
        set "conflicting_services=GoodbyeDPI"
        set "found_conflict=0"
        
        for %%s in (!conflicting_services!) do (
            sc query "%%s" >nul 2>&1
            if !errorlevel!==0 (
                call :PrintYellow "[?] Найдена конфликтующая служба: %%s. Остановка и удаление..."
                net stop "%%s" >nul 2>&1
                sc delete "%%s" >nul 2>&1
                if !errorlevel!==0 (
                    call :PrintGreen "Служба успешно удалена: %%s"
                ) else (
                    call :PrintRed "[X] Не удалось удалить службу: %%s"
                )
                set "found_conflict=1"
            )
        )
        
        if !found_conflict!==0 (
            call :PrintRed "[X] Конфликтующие службы не найдены. Проверьте вручную, не использует ли другой обход WinDivert."
        ) else (
            call :PrintYellow "[?] Повторная попытка удалить WinDivert..."

            net stop "WinDivert" >nul 2>&1
            sc delete "WinDivert" >nul 2>&1
            sc query "WinDivert" >nul 2>&1
            if !errorlevel! neq 0 (
                call :PrintGreen "WinDivert успешно удален после удаления конфликтующих служб"
            ) else (
                call :PrintRed "[X] WinDivert все еще не может быть удален. Проверьте вручную, не использует ли другой обход WinDivert."
            )
        )
    ) else (
        call :PrintGreen "WinDivert успешно удален"
    )
    
    echo:
)

:: Конфликтующие обходы
set "conflicting_services=GoodbyeDPI discordfix_zapret winws1 winws2"
set "found_any_conflict=0"
set "found_conflicts="

for %%s in (!conflicting_services!) do (
    sc query "%%s" >nul 2>&1
    if !errorlevel!==0 (
        if "!found_conflicts!"=="" (
            set "found_conflicts=%%s"
        ) else (
            set "found_conflicts=!found_conflicts! %%s"
        )
        set "found_any_conflict=1"
    )
)

if !found_any_conflict!==1 (
    call :PrintRed "[X] Обнаружены конфликтующие службы обхода: !found_conflicts!"
    
    set "CHOICE="
    set /p "CHOICE=Вы хотите удалить эти конфликтующие службы? (Y/N) (по умолчанию: N) "
    if "!CHOICE!"=="" set "CHOICE=N"
    if "!CHOICE!"=="y" set "CHOICE=Y"
    
    if /i "!CHOICE!"=="Y" (
        for %%s in (!found_conflicts!) do (
            call :PrintYellow "Остановка и удаление службы: %%s"
            net stop "%%s" >nul 2>&1
            sc delete "%%s" >nul 2>&1
            if !errorlevel!==0 (
                call :PrintGreen "Служба успешно удалена: %%s"
            ) else (
                call :PrintRed "[X] Не удалось удалить службу: %%s"
            )
        )

        net stop "WinDivert" >nul 2>&1
        sc delete "WinDivert" >nul 2>&1
        net stop "WinDivert14" >nul 2>&1
        sc delete "WinDivert14" >nul 2>&1
    )
    
    echo:
)

:: Очистка кэша Discord
set "CHOICE="
set /p "CHOICE=Вы хотите очистить кэш Discord (Stable, PTB, Canary, Development)? (Y/N) (по умолчанию: Y) "
if "!CHOICE!"=="" set "CHOICE=Y"
if "!CHOICE!"=="y" set "CHOICE=Y"

if /i "!CHOICE!"=="Y" (
    set "discordFound=0"
    if exist "%APPDATA%\discord\" (
        set "discordFound=1"
        call :clear_discord_cache "Discord.exe" "Discord" "%APPDATA%\discord"
    )
    if exist "%APPDATA%\discordptb\" (
        set "discordFound=1"
        call :clear_discord_cache "DiscordPTB.exe" "Discord PTB" "%APPDATA%\discordptb"
    )
    if exist "%APPDATA%\discordcanary\" (
        set "discordFound=1"
        call :clear_discord_cache "DiscordCanary.exe" "Discord Canary" "%APPDATA%\discordcanary"
    )
    if exist "%APPDATA%\discorddevelopment\" (
        set "discordFound=1"
        call :clear_discord_cache "DiscordDevelopment.exe" "Discord Development" "%APPDATA%\discorddevelopment"
    )
    if !discordFound! equ 0 call :PrintRed "Установки Discord не найдены"
    set "discordFound="
)
echo:

pause
goto menu

:: ==================== СЛУЖЕБНЫЕ ФУНКЦИИ ====================
:: Статус автопроверки обновлений
:check_updates_switch_status
set "checkUpdatesFlag=%UTILS_PATH%\check_updates.enabled"
if exist "%checkUpdatesFlag%" (
    set "CheckUpdatesStatus=Включено"
) else (
    set "CheckUpdatesStatus=Выключено"
)
exit /b

:check_updates_switch
cls

if not exist "%checkUpdatesFlag%" (
    echo Включение проверки обновлений...
    echo ENABLED > "%checkUpdatesFlag%"
) else (
    echo Выключение проверки обновлений...
    del /f /q "%checkUpdatesFlag%"
)
pause
goto menu

::Замена фейка
:replace_fakes
cls

set "fake_count=0"
set "fake_type="
set "fake_number="
set "discord_hash="
set "game_hash="
set "current_discord_fake=(не найдено)"
set "current_game_fake=(не найдено)"

if not exist "%BIN_PATH%" (
    echo Ошибка: папка bin не найдена.
    pause
    goto menu
)

pushd "%BIN_PATH%"
for /f "tokens=1,2,3 delims=|" %%A in ('powershell -NoProfile -Command "foreach ($item in @(@{Name='ACTIVE_DISCORD_UDP.bin'; Label='ACTIVE_DISCORD'},@{Name='ACTIVE_GAME_UDP.bin'; Label='ACTIVE_GAME'})) { if (Test-Path -LiteralPath $item.Name) { Write-Output ($item.Label + [char]124 + $item.Label + [char]124 + (Get-FileHash -LiteralPath $item.Name -Algorithm SHA256).Hash) } }; $files = @(Get-ChildItem -LiteralPath . -File -Filter '*.bin'); foreach ($file in $files) { if ($file.BaseName -notlike 'ACTIVE_*') { Write-Output ('FAKE' + [char]124 + $file.BaseName + [char]124 + (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash) } }"') do (
    if "%%A"=="ACTIVE_DISCORD" (
        set "discord_hash=%%C"
    ) else if "%%A"=="ACTIVE_GAME" (
        set "game_hash=%%C"
    ) else if "%%A"=="FAKE" (
        set /a fake_count+=1
        set "fake_file!fake_count!=%BIN_PATH%%%B.bin"
        set "fake_name!fake_count!=%%B"
        set "fake_hash!fake_count!=%%C"
    )
)
popd

if !fake_count! EQU 0 (
    echo В папке bin не найдено файлов .bin.
    pause
    goto menu
)

for /l %%N in (1,1,!fake_count!) do (
    if defined discord_hash if /i "!fake_hash%%N!"=="!discord_hash!" set "current_discord_fake=!fake_name%%N!"
    if defined game_hash if /i "!fake_hash%%N!"=="!game_hash!" set "current_game_fake=!fake_name%%N!"
)

:replace_fakes_prompt
echo.
echo Выберите тип фейка для замены:
echo.
echo   1. Discord UDP     (текущий: !current_discord_fake!)
echo   2. GameFilter UDP  (текущий: !current_game_fake!)
echo.
echo   0. Назад в меню
echo.
set "fake_type="
set /p "fake_type=Введите номер типа (1/2/0): "
if "!fake_type!"=="0" goto menu
if not "!fake_type!"=="1" if not "!fake_type!"=="2" (
    echo Неверный выбор. Попробуйте снова.
    pause
    cls
    goto replace_fakes_prompt
)

:select_fake_file
cls
echo.
echo Выбран тип: 
if "!fake_type!"=="1" echo   Discord UDP (текущий: !current_discord_fake!)
if "!fake_type!"=="2" echo   GameFilter UDP (текущий: !current_game_fake!)
echo.
echo Доступные файлы фейков:
echo.
for /l %%N in (1,1,!fake_count!) do echo   %%N. !fake_name%%N!
echo.
echo   0. Назад к выбору типа
echo.
set "fake_number="
set /p "fake_number=Введите номер файла фейка: "
if "!fake_number!"=="0" (
    cls
    goto replace_fakes_prompt
)

set "source_file="
for /l %%N in (1,1,!fake_count!) do if "%%N"=="!fake_number!" set "source_file=!fake_file%%N!"
if not defined source_file (
    echo Неверный номер файла фейка.
    pause
    cls
    goto select_fake_file
)

if "!fake_type!"=="1" (
    set "active_file=%BIN_PATH%ACTIVE_DISCORD_UDP.bin"
) else if "!fake_type!"=="2" (
    set "active_file=%BIN_PATH%ACTIVE_GAME_UDP.bin"
)

del /f /q "!active_file!" >nul 2>&1
copy /y "!source_file!" "!active_file!" >nul
if errorlevel 1 (
    echo Не удалось заменить активный файл фейка.
) else (
    echo Активный файл фейка успешно заменён.
    for /l %%N in (1,1,!fake_count!) do if "%%N"=="!fake_number!" (
        if "!fake_type!"=="1" set "current_discord_fake=!fake_name%%N!"
        if "!fake_type!"=="2" set "current_game_fake=!fake_name%%N!"
    )
)
pause
cls
goto select_fake_file

:: Игровые фильтры
:game_switch_status

set "gameFlagFile=%UTILS_PATH%\game_filter.enabled"

if not exist "%gameFlagFile%" (
    set "GameFilterStatus=Выключен"
    set "GameFilter=12"
    set "GameFilterTCP=12"
    set "GameFilterUDP=12"
    exit /b
)

set "GameFilterMode="
for /f "usebackq delims=" %%A in ("%gameFlagFile%") do (
    if not defined GameFilterMode set "GameFilterMode=%%A"
)

if /i "%GameFilterMode%"=="all" (
    set "GameFilterStatus=Включен (TCP и UDP)"
    set "GameFilter=1024-65535"
    set "GameFilterTCP=1024-65535"
    set "GameFilterUDP=1024-65535"
) else if /i "%GameFilterMode%"=="tcp" (
    set "GameFilterStatus=Включен (TCP)"
    set "GameFilter=1024-65535"
    set "GameFilterTCP=1024-65535"
    set "GameFilterUDP=12"
) else if /i "%GameFilterMode%"=="udp" (
    set "GameFilterStatus=Включен (UDP)"
    set "GameFilter=1024-65535"
    set "GameFilterTCP=12"
    set "GameFilterUDP=1024-65535"
) else if /i "%GameFilterMode%"=="fortnite" (
    set "GameFilterStatus=Включен (Fortnite)"
    set "GameFilter=1024-65535"
    set "GameFilterTCP=1024-65535"
    set "GameFilterUDP=1024-22221,22223-65535"
)
exit /b

:game_switch
cls

echo Выберите режим игрового фильтра:
echo   0. Выключен
echo   1. TCP и UDP (общий)
echo   2. Только TCP (общий)
echo   3. Только UDP (общий)
echo   4. Fortnite (TCP и UDP)
echo.
set "GameFilterChoice=0"
set /p "GameFilterChoice=Введите параметр (0-4, По умолчанию: 0): "
if "%GameFilterChoice%"=="" set "GameFilterChoice=0"

if "%GameFilterChoice%"=="0" (
    if exist "%gameFlagFile%" (
        del /f /q "%gameFlagFile%"
    ) else (
        goto menu
    )
) else if "%GameFilterChoice%"=="1" (
    echo all>"%gameFlagFile%"
) else if "%GameFilterChoice%"=="2" (
    echo tcp>"%gameFlagFile%"
) else if "%GameFilterChoice%"=="3" (
    echo udp>"%gameFlagFile%"
) else if "%GameFilterChoice%"=="4" (
    echo fortnite>"%gameFlagFile%"
) else (
    echo Неверный параметр, выход...
    pause
    goto menu
)

call :PrintYellow "Переустановите службу или перезапустите стратегию для применения изменений"
pause
goto menu

:: Обновление списка айпи
:ipset_update
cls
set "listFile=%LISTS_PATH%\ipset-all.txt"
set "url=https://raw.githubusercontent.com/Neodemetrius/Zapret/refs/heads/main/.assets/ipset-allupd.txt"

echo Загрузка списка айпи...
if exist "%SystemRoot%\System32\curl.exe" (
    curl --version | find "libcurl/7"
    if !errorlevel!==0 (
        curl --ssl-no-revoke -L -o "%listFile%" "%url%"
    ) else (
        curl --ssl-revoke-best-effort -L -o "%listFile%" "%url%"
    )
) else (
    powershell -NoProfile -Command ^
        "$url = '%url%';" ^
        "$out = '%listFile%';" ^
        "$dir = Split-Path -Parent $out;" ^
        "if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null };" ^
        "Write-Host 'Скачивание...' -NoNewline;" ^
        "$res = Invoke-WebRequest -Uri $url -TimeoutSec 10 -UseBasicParsing;" ^
        "if ($res.StatusCode -eq 200) { $res.Content | Out-File -FilePath $out -Encoding UTF8; Write-Host ' OK' -ForegroundColor Green } else { Write-Host ' ОШИБКА' -ForegroundColor Red; exit 1 }"
)

if "!errorlevel!"=="0" (
    echo - Cписок айпи обновлен
) else (
    echo - Ошибка при обновлении списка айпи
)

pause
goto menu

:: Фильтр айпи
:ipset_switch_status

set "listFile=%LISTS_PATH%\ipset-all.txt"
for /f %%i in ('type "%listFile%" 2^>nul ^| find /c /v ""') do set "lineCount=%%i"

if !lineCount!==0 (
    set "IPsetStatus=Любой"
) else (
    findstr /R "^203\.0\.113\.113/32$" "%listFile%" >nul
    if !errorlevel!==0 (
        set "IPsetStatus=Нет"
    ) else (
        set "IPsetStatus=Загружен"
    )
)
exit /b


:ipset_switch
cls

set "listFile=%LISTS_PATH%\ipset-all.txt"
set "backupFile=%listFile%.backup"

if "%IPsetStatus%"=="Загружен" (
    echo Смена на режим Нет...
    
    if not exist "%backupFile%" (
        ren "%listFile%" "ipset-all.txt.backup"
    ) else (
        del /f /q "%backupFile%"
        ren "%listFile%" "ipset-all.txt.backup"
    )
    
    >"%listFile%" (
        echo 203.0.113.113/32
    )
    
) else if "%IPsetStatus%"=="Нет" (
    echo Смена на режим Любой...
    
    >"%listFile%" (
        rem Creating empty file
    )
    
) else if "%IPsetStatus%"=="Любой" (
    echo Смена на режим Загружен...
    
    if exist "%backupFile%" (
        del /f /q "%listFile%"
        ren "%backupFile%" "ipset-all.txt"
    ) else (
        echo Ошибка: нет резервной копии для восстановления. Сначала обновите список в меню
        pause
        goto menu
    )
    
)

pause
goto menu
:: Проверка обновлений
:service_check_updates
cls

:: Установка текущей версии и URL-адресов
set "GITHUB_VERSION_URL=https://raw.githubusercontent.com/Neodemetrius/Zapret/refs/heads/main/.assets/version"
set "GITHUB_RELEASE_URL=https://github.com/Neodemetrius/Zapret/releases/tag/"
set "GITHUB_DOWNLOAD_URL=https://github.com/Neodemetrius/Zapret/releases/latest"

:: Получение последней версии с GitHub
for /f "delims=" %%A in ('powershell -NoProfile -Command "(Invoke-WebRequest -Uri \"%GITHUB_VERSION_URL%\" -Headers @{\"Cache-Control\"=\"no-cache\"} -UseBasicParsing -TimeoutSec 5).Content.Trim()" 2^>nul') do set "GITHUB_VERSION=%%A"

:: Обработка ошибок
if not defined GITHUB_VERSION (
    echo Внимание: не удалось получить информацию о последней версии. Это предупреждение не влияет на работу zapret
    timeout /T 9
    if "%1"=="soft" exit 
    goto menu
)

:: Сравнение версий
if "%LOCAL_VERSION%"=="%GITHUB_VERSION%" (
    echo Установлена последняя версия: %LOCAL_VERSION%
    
    if "%1"=="soft" exit 
    pause
    goto menu
) 

echo Доступна новая версия: %GITHUB_VERSION%
echo Страница выпуска: %GITHUB_RELEASE_URL%%GITHUB_VERSION%

echo Открываю страницу загрузки...
start "" "%GITHUB_DOWNLOAD_URL%"


if "%1"=="soft" exit 
pause
goto menu

:: Обновления файла host
:hosts_update
cls

set "hostsFile=%SystemRoot%\System32\drivers\etc\hosts"
set "hostsUrl=https://raw.githubusercontent.com/Neodemetrius/Zapret/refs/heads/main/.assets/hosts"
set "tempFile=%TEMP%\zapret_hosts.txt"
set "needsUpdate=0"

echo Проверка файла hosts...

if exist "%SystemRoot%\System32\curl.exe" (
    curl -L -s -o "%tempFile%" "%hostsUrl%"
) else (
    powershell -NoProfile -Command ^
        "$url = '%hostsUrl%';" ^
        "$out = '%tempFile%';" ^
        "$res = Invoke-WebRequest -Uri $url -TimeoutSec 10 -UseBasicParsing;" ^
        "if ($res.StatusCode -eq 200) { $res.Content | Out-File -FilePath $out -Encoding UTF8 } else { exit 1 }"
)

if not exist "%tempFile%" (
    call :PrintRed "Не удалось загрузить файл hosts из репозитория"
    call :PrintYellow "Скопируйте файл hosts вручную по адресу %hostsUrl%"
    pause
    goto menu
)

set "firstLine="
set "lastLine="
for /f "usebackq delims=" %%a in ("%tempFile%") do (
    if not defined firstLine (
        set "firstLine=%%a"
    )
    set "lastLine=%%a"
)

findstr /C:"!firstLine!" "%hostsFile%" >nul 2>&1
if !errorlevel! neq 0 (
    echo Первая строка из репозитория не найдена в файле hosts
    set "needsUpdate=1"
)

findstr /C:"!lastLine!" "%hostsFile%" >nul 2>&1
if !errorlevel! neq 0 (
    echo Последняя строка из репозитория не найдена в файле hosts
    set "needsUpdate=1"
)

if "%needsUpdate%"=="1" (
    echo:
    call :PrintYellow "Файл hosts требует обновления"
    call :PrintYellow "Пожалуйста, вручную скопируйте содержимое из загруженного файла в ваш файл hosts"
    
    start notepad "%tempFile%"
    explorer /select,"%hostsFile%"
) else (
    call :PrintGreen "Файл hosts актуален"
    if exist "%tempFile%" del /f /q "%tempFile%"
)

echo:
pause
goto menu

:: Загрузка пользовательских списков
:load_user_lists

if not exist "%LISTS_PATH%ipset-exclude-user.txt" (
    echo 203.0.113.113/32>"%LISTS_PATH%ipset-exclude-user.txt"
)
if not exist "%LISTS_PATH%list-general-user.txt" (
    echo # Never leave this file empty>"%LISTS_PATH%list-general-user.txt"
    echo domain.example.abc>>"%LISTS_PATH%list-general-user.txt"
)
if not exist "%LISTS_PATH%list-exclude-user.txt" (
    echo domain.example.abc>"%LISTS_PATH%list-exclude-user.txt"
)

exit /b

:: Включение TCP
:tcp_enable
netsh interface tcp show global | findstr /i "timestamps" | findstr /i "enabled" > nul || netsh interface tcp set global timestamps=enabled > nul 2>&1
exit /b

:: Тесты 
:run_tests
cls

powershell -NoProfile -Command "if ($PSVersionTable -and $PSVersionTable.PSVersion -and $PSVersionTable.PSVersion.Major -ge 3) { exit 0 } else { exit 1 }" >nul 2>&1
if %errorLevel% neq 0 (
    echo Требуется PowerShell 3.0 или новее.
    echo Пожалуйста обновите PowerShell и перезапустите скрипт.
    echo.
    pause
    goto menu
)

echo Запуск тестов конфигурации в окне PowerShell...
echo.
start "" powershell -NoProfile -ExecutionPolicy Bypass -File "%UTILS_PATH%\test zapret.ps1"
pause
goto menu

:: Очистка кэша Discord
:clear_discord_cache
setlocal EnableDelayedExpansion
set "discordProcess=%~1"
set "discordName=%~2"
set "discordCacheDir=%~3"

tasklist /FI "IMAGENAME eq !discordProcess!" 2>nul | findstr /I /C:"!discordProcess!" >nul
if !errorlevel! equ 0 (
    echo !discordName! запущен, закрываем...
    taskkill /IM "!discordProcess!" /F >nul 2>&1
    if !errorlevel! equ 0 (
        call :PrintGreen "!discordName! успешно закрыт"
    ) else (
        call :PrintRed "Не удалось закрыть !discordName!"
    )
)

if exist "!discordCacheDir!\" (
    for %%d in ("Cache" "Code Cache" "GPUCache") do (
        set "dirPath=!discordCacheDir!\%%~d"
        if exist "!dirPath!\" (
            rd /s /q "!dirPath!" >nul 2>&1
            if exist "!dirPath!\" (
                call :PrintRed "Не удалось удалить !dirPath!"
            ) else (
                call :PrintGreen "Успешно удалено !dirPath!"
            )
        ) else (
            call :PrintRed "!dirPath! не существует"
        )
    )
)

endlocal
exit /b

:: Цветные обозначение
:PrintGreen
powershell -NoProfile -Command "Write-Host \"%~1\" -ForegroundColor Green"
exit /b

:PrintRed
powershell -NoProfile -Command "Write-Host \"%~1\" -ForegroundColor Red"
exit /b

:PrintYellow
powershell -NoProfile -Command "Write-Host \"%~1\" -ForegroundColor Yellow"
exit /b

:: Проверка распаковки архива
:check_extracted
if not exist "%BIN_PATH%" (
    echo [ОШИБКА] Zapret должен быть извлечен из архива!
    echo Папка 'bin' не найдена в %~dp0
    echo:
    echo Решение:
    echo 1. Извлеките ВСЕ файлы из архива zapret
    echo 2. Убедитесь, что папка 'bin' существует в той же папке, что и service.bat
    echo 3. Запустите service.bat снова
    echo:
    pause
    exit 1
)

:: Проверка наличия winws.exe
if not exist "%WINWS_PATH%\winws.exe" (
    echo [ОШИБКА] Файл winws.exe не найден в папке winws
    echo Убедитесь, что архив полностью извлечен
    echo:
    pause
    exit 1
)
exit /b 0

:: Проверка наличия системной команды
:check_command
where %1 >nul 2>&1
if %errorLevel% neq 0 (
    echo [ОШИБКА] Команда "%1" не найдена в PATH
    echo:
    echo Возможные причины:
    echo 1. Повреждена переменная окружения PATH
    echo 2. Системные файлы Windows повреждены
    echo 3. Антивирус заблокировал доступ к системным утилитам
    echo:
    echo Решения:
    echo - Восстановите системные файлы: sfc /scannow
    echo - Проверьте антивирусные исключения
    echo - Переустановите Windows при серьезных повреждениях
    echo:
    pause
    exit /b
)
exit /b