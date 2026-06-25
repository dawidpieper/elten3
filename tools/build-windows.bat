@echo off
setlocal EnableExtensions

set "ROOT=%~dp0.."
set "BUILD_PKG=0"
set "SIGN=0"
set "SIGN_CMAKE=OFF"
set "SIGNTOOL="
set "TIMESTAMP_URL=http://time.certum.pl"
set "BUILD_ID="
set "EXTRA_CMAKE_ARGS="

:parse_args
if "%~1"=="" goto args_done
set "ARG=%~1"
if /I "%~1"=="--pkg" (
  set "BUILD_PKG=1"
  shift
  goto parse_args
)
if /I "%~1"=="--sign" (
  set "SIGN=1"
  set "SIGN_CMAKE=ON"
  shift
  goto parse_args
)
if /I "%~1"=="--signtool" (
  set "SIGNTOOL=%~2"
  shift
  shift
  goto parse_args
)
if /I "%ARG:~0,11%"=="--signtool=" (
  set "SIGNTOOL=%ARG%"
  set "SIGNTOOL=%SIGNTOOL:~11%"
  shift
  goto parse_args
)
if /I "%~1"=="--timestamp-url" (
  set "TIMESTAMP_URL=%~2"
  shift
  shift
  goto parse_args
)
if /I "%ARG:~0,16%"=="--timestamp-url=" (
  set "TIMESTAMP_URL=%ARG%"
  set "TIMESTAMP_URL=%TIMESTAMP_URL:~16%"
  shift
  goto parse_args
)
if /I "%~1"=="--build-id" (
  set "BUILD_ID=%~2"
  shift
  shift
  goto parse_args
)
if /I "%ARG:~0,11%"=="--build-id=" (
  set "BUILD_ID=%ARG%"
  set "BUILD_ID=%BUILD_ID:~11%"
  shift
  goto parse_args
)
set "EXTRA_CMAKE_ARGS=%EXTRA_CMAKE_ARGS% %~1"
shift
goto parse_args

:args_done
pushd "%ROOT%" >nul || exit /b 1

call :find_cmake
if errorlevel 1 (
  echo CMake with generator "Visual Studio 18 2026" not found. Install or update the Visual Studio 2026 CMake component.
  popd >nul
  exit /b 1
)
echo CMake: %CMAKE_EXE%

echo Build options: pkg=%BUILD_PKG% sign=%SIGN%
if not "%BUILD_ID%"=="" echo Build ID: %BUILD_ID%
if "%SIGN%"=="1" (
  if not "%SIGNTOOL%"=="" echo SignTool: %SIGNTOOL%
  echo Timestamp URL: %TIMESTAMP_URL%
)

echo Configuring Elten launcher x64...
"%CMAKE_EXE%" --preset windows-x64 -DELTEN_BUILD_ID="%BUILD_ID%" -DELTEN_WINDOWS_SIGN=%SIGN_CMAKE% -DELTEN_WINDOWS_SIGNTOOL="%SIGNTOOL%" -DELTEN_WINDOWS_TIMESTAMP_URL="%TIMESTAMP_URL%" %EXTRA_CMAKE_ARGS%
if errorlevel 1 goto fail

echo Configuring Elten launcher x86...
"%CMAKE_EXE%" --preset windows-x86 -DELTEN_BUILD_ID="%BUILD_ID%" -DELTEN_WINDOWS_SIGN=%SIGN_CMAKE% -DELTEN_WINDOWS_SIGNTOOL="%SIGNTOOL%" -DELTEN_WINDOWS_TIMESTAMP_URL="%TIMESTAMP_URL%" %EXTRA_CMAKE_ARGS%
if errorlevel 1 goto fail

echo Configuring Elten launcher arm64...
"%CMAKE_EXE%" --preset windows-arm64 -DELTEN_BUILD_ID="%BUILD_ID%" -DELTEN_WINDOWS_SIGN=%SIGN_CMAKE% -DELTEN_WINDOWS_SIGNTOOL="%SIGNTOOL%" -DELTEN_WINDOWS_TIMESTAMP_URL="%TIMESTAMP_URL%" %EXTRA_CMAKE_ARGS%
if errorlevel 1 goto fail

echo Building Elten launcher x64...
"%CMAKE_EXE%" --build --preset windows-x64-release --target EltenLauncher
if errorlevel 1 goto fail

echo Building Elten launcher x86...
"%CMAKE_EXE%" --build --preset windows-x86-release --target EltenLauncher
if errorlevel 1 goto fail

echo Building Elten launcher facade...
"%CMAKE_EXE%" --build --preset windows-x86-release --target EltenLauncherFacade
if errorlevel 1 goto fail

echo Building Elten launcher arm64...
"%CMAKE_EXE%" --build --preset windows-arm64-release --target EltenLauncher
if errorlevel 1 goto fail

if "%BUILD_PKG%"=="1" (
  echo Creating Windows installer...
  "%CMAKE_EXE%" --build --preset windows-x64-release --target EltenPkg
  if errorlevel 1 goto fail
) else if "%SIGN%"=="1" (
  echo Creating signed Windows distribution...
  "%CMAKE_EXE%" --build --preset windows-x64-release --target EltenApp
  if errorlevel 1 goto fail
)

echo Built Windows launchers.
if "%BUILD_PKG%"=="1" echo Built "%ROOT%\dist\windows\EltenSetup.exe"
popd >nul
exit /b 0

:fail
set "RESULT=%ERRORLEVEL%"
popd >nul
exit /b %RESULT%

:find_cmake
call "%~dp0find-cmake-2026.bat"
exit /b %ERRORLEVEL%
