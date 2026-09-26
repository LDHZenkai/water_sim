@echo off
cd /d "%~dp0"
start "" godot.exe --path game --rendering-method forward_plus -- --quality=high
