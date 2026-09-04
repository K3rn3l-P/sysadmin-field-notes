@echo off
title Change Port Number RDP By K3rn3l
cls
setlocal ENABLEEXTENSIONS
setlocal ENABLEDELAYEDEXPANSION

color

cls

net session > nul 2>&1
if %errorlevel% NEQ 0 (
	echo set uac = createobject^("shell.application"^) > "%temp%\getadmin.vbs"
	echo uac.shellexecute "%~dpnx0", "", "", "runas", 1 >> "%temp%\getadmin.vbs"
	"%temp%\getadmin.vbs"
	exit
)

set /p portaRDP="Which RDP port do you want to use: "
reg add "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" /v "PortNumber" /t REG_DWORD /d !portaRDP! /f
net stop TermService
if !errorlevel! EQU 0 (
	net start TermService
	cls
	color 02
	echo DONE
) else (
	cls
	color 0c
	echo ERROR
)
pause>nul
goto end

:end
exit
