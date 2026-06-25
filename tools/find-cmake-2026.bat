@echo off
setlocal EnableExtensions

set "REQUIRED_GENERATOR=Visual Studio 18 2026"
set "SELECTED_CMAKE="

for %%I in (
  "C:\Program Files\Microsoft Visual Studio\18\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"
  "C:\Program Files\Microsoft Visual Studio\18\Professional\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"
  "C:\Program Files\Microsoft Visual Studio\18\Enterprise\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"
  "C:\Program Files\Microsoft Visual Studio\18\BuildTools\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"
  "C:\Program Files\Microsoft Visual Studio\18\Preview\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"
  "C:\Program Files\Microsoft Visual Studio\2026\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"
  "C:\Program Files\Microsoft Visual Studio\2026\Professional\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"
  "C:\Program Files\Microsoft Visual Studio\2026\Enterprise\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"
  "C:\Program Files\Microsoft Visual Studio\2026\BuildTools\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"
  "C:\Program Files\Microsoft Visual Studio\2026\Preview\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"
  "C:\Program Files\CMake\bin\cmake.exe"
) do (
  call :try_cmake "%%~I"
  if not errorlevel 1 goto found
)

where cmake.exe >nul 2>nul
if not errorlevel 1 (
  for /f "delims=" %%I in ('where cmake.exe') do (
    call :try_cmake "%%I"
    if not errorlevel 1 goto found
  )
)

echo No CMake with generator "%REQUIRED_GENERATOR%" found.
exit /b 1

:try_cmake
if "%~1"=="" exit /b 1
if not exist "%~1" exit /b 1
"%~1" --help 2>nul | findstr /C:"%REQUIRED_GENERATOR%" >nul
if errorlevel 1 exit /b 1
set "SELECTED_CMAKE=%~1"
exit /b 0

:found
endlocal & set "CMAKE_EXE=%SELECTED_CMAKE%"
exit /b 0
