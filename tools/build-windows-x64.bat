@echo off
setlocal

set "ROOT=%~dp0.."
set "BUILD_ID="
set "EXTRA_CMAKE_ARGS="

:parse_args
if "%~1"=="" goto args_done
set "ARG=%~1"
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

echo Configuring Elten launcher windows-x64...
"%CMAKE_EXE%" --preset windows-x64 -DELTEN_BUILD_ID="%BUILD_ID%" %EXTRA_CMAKE_ARGS%
if errorlevel 1 (
  popd >nul
  exit /b 1
)

echo Building Elten launcher windows-x64...
"%CMAKE_EXE%" --build --preset windows-x64-release
set "RESULT=%ERRORLEVEL%"
if "%RESULT%"=="0" echo Built "%ROOT%\build\release\windows\elten-x64.exe"

popd >nul
exit /b %RESULT%

:find_cmake
call "%~dp0find-cmake-2026.bat"
exit /b %ERRORLEVEL%
