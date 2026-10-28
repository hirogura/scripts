@echo off
chcp 932 >nul
title パスワード無期限化

rem --- 管理者権限で再起動 ---
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

echo ===== 現在の状況: net user user =====
net user user
echo.

set "ans="
set /p ans=パスワードを無期限にしますか？ [Enterで実行 / 何か入力して Enter で中止]: 
if not "%ans%"=="" (
    echo 中止しました。
    pause
    exit /b
)

echo.
echo 実行中...
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-LocalUser | ForEach-Object { Set-LocalUser -Name $_.Name -PasswordNeverExpires $true }"
echo.

echo ===== 変更後の状況: net user user =====
net user user
echo.
pause
