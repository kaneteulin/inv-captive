@echo off
setlocal EnableExtensions
rem 이 파일은 plugins\InvCaptive 안에 있으므로 두 단계 위가 서버 폴더
cd /d "%~dp0..\.."
if not exist "server.properties" if not exist "paper.jar" goto :notserver
title InvCaptive 월드 초기화

rem ---------------------------------------------------------------
rem  월드 + InvCaptive 시드 + 공유 인벤토리를 backup 폴더로 옮겨서 초기화
rem  다음 서버 실행 때 새 월드와 새 시드가 자동으로 만들어진다.
rem ---------------------------------------------------------------

set "LEVEL=world"
if exist "server.properties" (
    for /f "usebackq tokens=1,* delims==" %%A in ("server.properties") do (
        if /i "%%A"=="level-name" set "LEVEL=%%B"
    )
)
set "DATA=plugins\InvCaptive"

rem 서버가 실행 중이면 마인크래프트가 session.lock 을 잠그고 있어 쓰기가 실패한다
if exist "%LEVEL%\session.lock" (
    2>nul ( (call ) 9>>"%LEVEL%\session.lock" ) || goto :running
)

echo.
echo 아래 항목을 backup 폴더로 옮긴 뒤 삭제합니다.
echo   - 월드             : %LEVEL%
echo   - 해금 블록 시드   : %DATA%\config.yml
echo   - 공유 인벤토리    : %DATA%\inventory.yml
echo.
echo 다음 서버 실행 때 새 월드와 새 시드가 만들어집니다.
echo.
choice /c YN /m "계속하시겠습니까"
if errorlevel 2 goto :cancel

for /f %%T in ('powershell -NoProfile -Command "Get-Date -Format yyyy-MM-dd_HHmmss"') do set "TS=%%T"
set "DEST=backup\reset_%TS%"
mkdir "%DEST%\%DATA%" || goto :fail

rem 월드를 가장 먼저 옮긴다. 실패하면 아무것도 바꾸지 않고 중단
if exist "%LEVEL%" (
    move "%LEVEL%" "%DEST%\%LEVEL%" >nul 2>&1 || goto :movefail
)
for %%W in ("%LEVEL%_nether" "%LEVEL%_the_end") do (
    if exist "%%~W" move "%%~W" "%DEST%\%%~W" >nul
)

if exist "%DATA%\config.yml" (
    for /f "tokens=2" %%S in ('findstr /b "seed:" "%DATA%\config.yml"') do echo 이전 시드: %%S
    move "%DATA%\config.yml" "%DEST%\%DATA%\config.yml" >nul
)
if exist "%DATA%\inventory.yml" (
    move "%DATA%\inventory.yml" "%DEST%\%DATA%\inventory.yml" >nul
)

echo.
echo 초기화 완료. 백업 위치: %CD%\%DEST%
echo 서버를 켠 뒤 /invcaptive 로 인벤토리 잠금을 시작하세요.
goto :end

:running
echo.
echo [경고] 서버가 실행 중입니다.
echo        서버를 먼저 종료한 뒤 다시 실행하세요. 아무것도 변경하지 않았습니다.
goto :fail

:movefail
rd "%DEST%\%DATA%" 2>nul
rd "%DEST%\plugins" 2>nul
rd "%DEST%" 2>nul
echo.
echo [오류] 월드 폴더를 옮길 수 없습니다.
echo        서버나 다른 프로그램이 월드 파일을 사용 중인지 확인하세요. 아무것도 변경하지 않았습니다.
goto :fail

:notserver
echo.
echo [오류] 서버 폴더를 찾을 수 없습니다: %CD%
echo        이 파일은 .server\plugins\InvCaptive 폴더 안에 있어야 합니다.
goto :fail

:cancel
echo 취소했습니다. 아무것도 변경하지 않았습니다.
goto :end

:fail
echo.
pause
exit /b 1

:end
echo.
pause
exit /b 0