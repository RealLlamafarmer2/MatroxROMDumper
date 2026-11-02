@echo off
rem Build MGAROM.COM on Windows using WSL (needs binutils installed in WSL:
rem   sudo apt install binutils)
cd /d "%~dp0"
wsl sh ./build.sh
