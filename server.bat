@echo off
rem InvCaptive for Paper 26.3 - launcher for server.ps1
rem Written 2026-11-20 by kaneteulin. Licensed under the GNU GPL version 3, see LICENSE.md.
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0server.ps1"
pause
