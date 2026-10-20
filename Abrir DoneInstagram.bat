@echo off
rem =========================================================
rem  Abre o DoneInstagram no navegador, sem o RStudio.
rem  Basta dar dois cliques neste arquivo.
rem  Para encerrar o app, feche esta janela preta.
rem =========================================================
title DoneInstagram
cd /d "%~dp0"

rem --- Procura o R instalado no computador ---
set "RSCRIPT="
where Rscript >nul 2>nul && set "RSCRIPT=Rscript"
if not defined RSCRIPT (
  for /d %%D in ("%ProgramFiles%\R\R-*") do if exist "%%D\bin\Rscript.exe" set "RSCRIPT=%%D\bin\Rscript.exe"
)
if not defined RSCRIPT (
  for /d %%D in ("%LOCALAPPDATA%\Programs\R\R-*") do if exist "%%D\bin\Rscript.exe" set "RSCRIPT=%%D\bin\Rscript.exe"
)
if not defined RSCRIPT (
  echo.
  echo  Nao encontrei o R neste computador.
  echo  Instale o R em https://cran.r-project.org e tente de novo.
  echo.
  pause
  exit /b 1
)

echo.
echo  Abrindo o DoneInstagram no navegador...
echo  Para encerrar o app, feche esta janela.
echo.
"%RSCRIPT%" -e "shiny::runApp('.', launch.browser = TRUE)"

rem Se o app parar com erro, mantem a janela aberta para ler a mensagem
if errorlevel 1 (
  echo.
  echo  O app foi encerrado com erro. Leia a mensagem acima.
  pause
)
