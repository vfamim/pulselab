@echo off
title PulseLab - LLM Council Deliberation
python "%~dp0scripts\council.py" %*
if errorlevel 1 pause
