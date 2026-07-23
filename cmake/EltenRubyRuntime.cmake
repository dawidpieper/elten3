set(ELTEN_RUBY_VERSION "4.0.6" CACHE STRING "Ruby version used by launcher builds")
if(WIN32 AND CMAKE_CACHEFILE_DIR)
  set(ELTEN_RUBY_DEFAULT_BUILD_ROOT "${CMAKE_CACHEFILE_DIR}/ruby")
else()
  set(ELTEN_RUBY_DEFAULT_BUILD_ROOT "${CMAKE_BINARY_DIR}/ruby")
endif()
set(ELTEN_RUBY_BUILD_ROOT "${ELTEN_RUBY_DEFAULT_BUILD_ROOT}" CACHE PATH "Build-local Ruby runtime root")
if(WIN32 AND ELTEN_RUBY_BUILD_ROOT MATCHES "^//")
  set(ELTEN_RUBY_BUILD_ROOT "${ELTEN_RUBY_DEFAULT_BUILD_ROOT}" CACHE PATH "Build-local Ruby runtime root" FORCE)
endif()
option(ELTEN_RUBY_INSTALL_GEMS "Install Gemfile gems into the build-local Ruby runtime" ON)

set(ELTEN_RUBY_INSTALLER_REVISION "1" CACHE STRING "RubyInstaller release revision")
set(ELTEN_RUBY_INSTALLER_BASE_URL "https://github.com/oneclick/rubyinstaller2/releases/download" CACHE STRING "RubyInstaller release base URL")
set(ELTEN_7ZIP_URL "https://www.7-zip.org/a/7zr.exe" CACHE STRING "Standalone 7-Zip extractor URL used by Windows launcher builds")
set(ELTEN_7ZIP_EXTRA_URL "https://www.7-zip.org/a/7z2601-extra.7z" CACHE STRING "7-Zip extra tools archive URL used by Windows launcher builds")
set(ELTEN_RUBY_OSX_PLATFORM_INCLUDE "arm64-darwin25" CACHE STRING "macOS Ruby platform include directory")
set(ELTEN_OSX_RUBY_CONFIGURE_OPTIONS "--enable-yjit" CACHE STRING "Configure options passed to ruby-install for macOS Ruby builds")
set(ELTEN_WINDOWS_X64_RUBY_VERSION "${ELTEN_RUBY_VERSION}" CACHE STRING "Ruby version used by Windows x64 launcher builds")
set(ELTEN_WINDOWS_X86_RUBY_VERSION "3.4.10" CACHE STRING "Ruby version used by Windows x86 launcher builds")
set(ELTEN_WINDOWS_ARM64_RUBY_VERSION "${ELTEN_RUBY_VERSION}" CACHE STRING "Ruby version used by Windows arm64 launcher builds")
set(ELTEN_OSX_ARM64_RUBY_VERSION "${ELTEN_RUBY_VERSION}" CACHE STRING "Ruby version used by macOS arm64 launcher builds")
set(ELTEN_MSYS2_BASE_URL "https://github.com/msys2/msys2-installer/releases/download/nightly-x86_64/msys2-base-x86_64-latest.tar.xz" CACHE STRING "MSYS2 base archive URL used by Windows launcher builds")
set(ELTEN_WINDOWS_X64_MSYS2_PACKAGES "base-devel mingw-w64-ucrt-x86_64-gcc mingw-w64-ucrt-x86_64-make mingw-w64-ucrt-x86_64-pkgconf mingw-w64-ucrt-x86_64-sqlite3" CACHE STRING "MSYS2 packages installed for Windows x64 native gem builds")
set(ELTEN_WINDOWS_X86_MSYS2_PACKAGES "base-devel mingw-w64-i686-gcc mingw-w64-i686-make mingw-w64-i686-pkgconf mingw-w64-i686-sqlite3" CACHE STRING "MSYS2 packages installed for Windows x86 native gem builds")
set(ELTEN_WINDOWS_ARM64_MSYS2_PACKAGES "base-devel mingw-w64-clang-aarch64-gcc mingw-w64-clang-aarch64-make mingw-w64-clang-aarch64-pkgconf mingw-w64-clang-aarch64-sqlite3" CACHE STRING "MSYS2 packages installed for Windows arm64 native gem builds")

function(elten_ruby_version_parts version out_major out_minor out_api out_dll_abi)
  string(REGEX MATCH "^([0-9]+)\\.([0-9]+)" version_match "${version}")
  if(NOT version_match)
    message(FATAL_ERROR "Ruby version must look like major.minor.patch: ${version}")
  endif()
  set(${out_major} "${CMAKE_MATCH_1}" PARENT_SCOPE)
  set(${out_minor} "${CMAKE_MATCH_2}" PARENT_SCOPE)
  set(${out_api} "${CMAKE_MATCH_1}.${CMAKE_MATCH_2}.0" PARENT_SCOPE)
  set(${out_dll_abi} "${CMAKE_MATCH_1}${CMAKE_MATCH_2}0" PARENT_SCOPE)
endfunction()

function(elten_configure_ruby_runtime)
  set(options)
  set(oneValueArgs PLATFORM ARCH)
  set(multiValueArgs)
  cmake_parse_arguments(ARG "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

  if(NOT ARG_PLATFORM OR NOT ARG_ARCH)
    message(FATAL_ERROR "elten_configure_ruby_runtime requires PLATFORM and ARCH")
  endif()

  set(runtime_id "${ARG_PLATFORM}-${ARG_ARCH}")
  set(runtime_root "${ELTEN_RUBY_BUILD_ROOT}/${runtime_id}")
  get_filename_component(runtime_build_root "${ELTEN_RUBY_BUILD_ROOT}" DIRECTORY)
  set(runtime_bundle_root "${runtime_build_root}/ruby-bundle-${runtime_id}")
  set(runtime_gem_lockfile "${runtime_bundle_root}/Gemfile.lock")
  set(runtime_byproducts
    "${runtime_bundle_root}/Gemfile"
    "${runtime_gem_lockfile}"
    "${runtime_root}/ssl/cert.pem"
  )
  if(ARG_PLATFORM STREQUAL "windows")
    list(APPEND runtime_byproducts
      "${runtime_bundle_root}/patchs/mini_portile_msys_path_patch.rb"
    )
  endif()
  set(runtime_stamp "${runtime_root}/elten-ruby-runtime.stamp")
  set(install_gems OFF)
  if(ELTEN_RUBY_INSTALL_GEMS)
    set(install_gems ON)
  endif()

  set(runtime_version "${ELTEN_RUBY_VERSION}")
  if(ARG_PLATFORM STREQUAL "windows")
    string(TOUPPER "${ARG_ARCH}" arch_upper)
    set(version_var "ELTEN_WINDOWS_${arch_upper}_RUBY_VERSION")
    set(runtime_version "${${version_var}}")
  elseif(ARG_PLATFORM STREQUAL "osx" AND ARG_ARCH STREQUAL "arm64")
    set(runtime_version "${ELTEN_OSX_ARM64_RUBY_VERSION}")
  endif()
  elten_ruby_version_parts("${runtime_version}" runtime_major runtime_minor runtime_api runtime_dll_abi)

  set(script_args
    "-DPLATFORM=${ARG_PLATFORM}"
    "-DARCH=${ARG_ARCH}"
    "-DRUBY_VERSION=${runtime_version}"
    "-DRUBY_API_VERSION=${runtime_api}"
    "-DRUNTIME_ROOT=${runtime_root}"
    "-DRUNTIME_STAMP=${runtime_stamp}"
    "-DBUNDLE_ROOT=${runtime_bundle_root}"
    "-DPROJECT_ROOT=${CMAKE_SOURCE_DIR}"
    "-DINSTALL_GEMS=${install_gems}"
  )

  if(ARG_PLATFORM STREQUAL "windows")
    if(ARG_ARCH STREQUAL "x64")
      set(installer_arch "x64")
      set(default_dll "x64-ucrt-ruby${runtime_dll_abi}.dll")
    elseif(ARG_ARCH STREQUAL "x86")
      set(installer_arch "x86")
      if(runtime_major GREATER_EQUAL 4)
        set(default_dll "i386-ucrt-ruby${runtime_dll_abi}.dll")
      else()
        set(default_dll "msvcrt-ruby${runtime_dll_abi}.dll")
      endif()
    elseif(ARG_ARCH STREQUAL "arm64")
      set(installer_arch "arm")
      set(default_dll "aarch64-ucrt-ruby${runtime_dll_abi}.dll")
    else()
      message(FATAL_ERROR "Unsupported Windows Ruby arch: ${ARG_ARCH}")
    endif()

    set(installer_version "${runtime_version}-${ELTEN_RUBY_INSTALLER_REVISION}")
    set(default_url "${ELTEN_RUBY_INSTALLER_BASE_URL}/RubyInstaller-${installer_version}/rubyinstaller-${installer_version}-${installer_arch}.7z")

    set(url_var "ELTEN_WINDOWS_${arch_upper}_RUBY_URL")
    set(dll_var "ELTEN_WINDOWS_${arch_upper}_RUBY_DLL")
    set(${url_var} "${default_url}" CACHE STRING "RubyInstaller URL for Windows ${ARG_ARCH}")
    set(${dll_var} "${default_dll}" CACHE STRING "Ruby DLL name for Windows ${ARG_ARCH}" FORCE)

    list(APPEND script_args
      "-DWINDOWS_RUBY_URL=${${url_var}}"
      "-DMSYS2_URL=${ELTEN_MSYS2_BASE_URL}"
      "-DSEVEN_ZIP_URL=${ELTEN_7ZIP_URL}"
      "-DSEVEN_ZIP_EXTRA_URL=${ELTEN_7ZIP_EXTRA_URL}"
      "-DNOKOGIRI_MSYS_PATCH=${CMAKE_SOURCE_DIR}/patchs/mini_portile_msys_path_patch.rb"
    )
    if(ARG_ARCH STREQUAL "x64")
      list(APPEND script_args "-DMSYS2_PACKAGES=${ELTEN_WINDOWS_X64_MSYS2_PACKAGES}")
    elseif(ARG_ARCH STREQUAL "x86")
      list(APPEND script_args "-DMSYS2_PACKAGES=${ELTEN_WINDOWS_X86_MSYS2_PACKAGES}")
    elseif(ARG_ARCH STREQUAL "arm64")
      list(APPEND script_args "-DMSYS2_PACKAGES=${ELTEN_WINDOWS_ARM64_MSYS2_PACKAGES}")
    endif()
    set(ruby_exe "${runtime_root}/bin/ruby.exe")
    set(ruby_library "${runtime_root}/bin/${${dll_var}}")
    set(ruby_dll "${${dll_var}}")
  elseif(ARG_PLATFORM STREQUAL "osx")
    list(APPEND script_args
      "-DOSX_PLATFORM_INCLUDE=${ELTEN_RUBY_OSX_PLATFORM_INCLUDE}"
      "-DOSX_RUBY_CONFIGURE_OPTIONS=${ELTEN_OSX_RUBY_CONFIGURE_OPTIONS}"
    )
    set(ruby_exe "${runtime_root}/bin/ruby")
    set(ruby_library "${runtime_root}/lib/libruby.${runtime_major}.${runtime_minor}-static.a")
    set(ruby_dll "")
  else()
    message(FATAL_ERROR "Unsupported Ruby runtime platform: ${ARG_PLATFORM}")
  endif()

  add_custom_command(
    OUTPUT "${runtime_stamp}"
    COMMAND "${CMAKE_COMMAND}" ${script_args} -P "${CMAKE_SOURCE_DIR}/cmake/prepare_ruby_runtime.cmake"
    BYPRODUCTS
      ${runtime_byproducts}
    DEPENDS
      "${CMAKE_SOURCE_DIR}/cmake/prepare_ruby_runtime.cmake"
      "${CMAKE_SOURCE_DIR}/patchs/mini_portile_msys_path_patch.rb"
      "${CMAKE_SOURCE_DIR}/Gemfile"
    COMMENT "Preparing Ruby ${runtime_version} runtime for ${runtime_id}"
    VERBATIM
  )

  add_custom_target(EltenRubyRuntime
    COMMAND "${CMAKE_COMMAND}" -E echo "Ruby runtime ready: ${runtime_id}"
    DEPENDS "${runtime_stamp}"
    VERBATIM
  )

  set(ELTEN_RUBY_ROOT "${runtime_root}" PARENT_SCOPE)
  set(ELTEN_RUBY_RUNTIME_STAMP "${runtime_stamp}" PARENT_SCOPE)
  set(ELTEN_RUBY_GEM_LOCKFILE "${runtime_gem_lockfile}" PARENT_SCOPE)
  set(ELTEN_RUBY_EXECUTABLE "${ruby_exe}" PARENT_SCOPE)
  set(ELTEN_RUBY_LIBRARY "${ruby_library}" PARENT_SCOPE)
  set(ELTEN_RUBY_DLL "${ruby_dll}" PARENT_SCOPE)
  set(ELTEN_RUNTIME_RUBY_API_VERSION "${runtime_api}" PARENT_SCOPE)
  set(ELTEN_RUBY_INCLUDE_DIR "${runtime_root}/include/ruby-${runtime_api}" PARENT_SCOPE)
  set(ELTEN_RUBY_PLATFORM_INCLUDE_DIR "${runtime_root}/include/ruby-${runtime_api}/${ELTEN_RUBY_OSX_PLATFORM_INCLUDE}" PARENT_SCOPE)
endfunction()
