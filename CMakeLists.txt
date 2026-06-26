cmake_minimum_required(VERSION 3.24)

if(CMAKE_GENERATOR MATCHES "Visual Studio")
  set(CMAKE_SUPPRESS_REGENERATION ON)
endif()

if(APPLE AND NOT DEFINED CMAKE_OSX_DEPLOYMENT_TARGET)
  set(CMAKE_OSX_DEPLOYMENT_TARGET "13.0" CACHE STRING "Minimum macOS deployment target")
endif()

project(EltenLauncher LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

option(ELTEN_COMPRESS_EMBEDDED_RUBY_ZSTD "Compress embedded Ruby payloads with ZSTD" ON)

include("${CMAKE_SOURCE_DIR}/cmake/EltenRubyRuntime.cmake")

set(ELTEN_RELEASE_BASE "${CMAKE_SOURCE_DIR}/build/release")

if(MSVC)
  set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
endif()

if(ELTEN_COMPRESS_EMBEDDED_RUBY_ZSTD)
  set(ELTEN_EMBEDDED_COMPRESSION "zstd")
  set(ELTEN_EMBEDDED_ZSTD_DEFINE 1)
else()
  set(ELTEN_EMBEDDED_COMPRESSION "none")
  set(ELTEN_EMBEDDED_ZSTD_DEFINE 0)
endif()

file(GLOB_RECURSE ELTEN_RB_SOURCES CONFIGURE_DEPENDS
  "${CMAKE_SOURCE_DIR}/src/*.rb"
)
list(APPEND ELTEN_RB_SOURCES "${CMAKE_SOURCE_DIR}/elten.rb")
list(FILTER ELTEN_RB_SOURCES EXCLUDE REGEX "/bin/")
list(FILTER ELTEN_RB_SOURCES EXCLUDE REGEX "/build/")
list(FILTER ELTEN_RB_SOURCES EXCLUDE REGEX "/CMakeFiles/")

set(ELTEN_GENERATED_DIR "${CMAKE_BINARY_DIR}/generated")
set(ELTEN_EMBEDDED_CPP "${ELTEN_GENERATED_DIR}/embedded_assets.cpp")
set(ELTEN_STAMP_PAYLOAD_FILE "${ELTEN_GENERATED_DIR}/ruby_payload.bin")
set(ELTEN_BUILD_ID "" CACHE STRING "Override generated Elten build id")
set(ELTEN_BUILD_INFO_HEADER "${ELTEN_GENERATED_DIR}/build_info.h")
set(ELTEN_BUILD_INFO_GENERATOR "${CMAKE_SOURCE_DIR}/cmake/generate_build_info_header.cmake")
set(ELTEN_BUILD_ID_FILE "${CMAKE_BINARY_DIR}/build-id")
set_source_files_properties("${ELTEN_BUILD_INFO_HEADER}" PROPERTIES GENERATED TRUE)
set(ELTEN_PRIVATE_DIR "${CMAKE_SOURCE_DIR}/private" CACHE PATH "Directory containing private, non-redistributable build inputs")
set(ELTEN_STAMP_PRIVATE_KEY_FILE "${ELTEN_PRIVATE_DIR}/stamp_key.hex" CACHE FILEPATH "Private plaintext stamp key used by launcher get_stamp signing")
set(ELTEN_STAMP_SECRET_HEADER "${ELTEN_GENERATED_DIR}/stamp_secret.h")
set(ELTEN_STAMP_SECRET_GENERATOR "${CMAKE_SOURCE_DIR}/cmake/generate_stamp_secret_header.cmake")
get_filename_component(ELTEN_STAMP_PRIVATE_KEY_DIR "${ELTEN_STAMP_PRIVATE_KEY_FILE}" DIRECTORY)
# Reconfigure if the private key appears or disappears after the first configure.
file(GLOB ELTEN_STAMP_PRIVATE_KEY_DIR_CONTENTS CONFIGURE_DEPENDS
  "${ELTEN_STAMP_PRIVATE_KEY_DIR}/*"
)

if(EXISTS "${ELTEN_STAMP_PRIVATE_KEY_FILE}")
  set(ELTEN_STAMP_SIGNATURE_AVAILABLE TRUE)
  set(ELTEN_STAMP_SIGNATURE_AVAILABLE_DEFINE 1)
  set(ELTEN_FORCE_DEVELOPER_MODE_DEFINE 0)
  message(STATUS "Elten launcher stamp signing enabled from ${ELTEN_STAMP_PRIVATE_KEY_FILE}")
  add_custom_command(
    OUTPUT "${ELTEN_STAMP_SECRET_HEADER}"
    COMMAND "${CMAKE_COMMAND}"
            "-DSTAMP_KEY_FILE=${ELTEN_STAMP_PRIVATE_KEY_FILE}"
            "-DSTAMP_SECRET_HEADER=${ELTEN_STAMP_SECRET_HEADER}"
            "-DSTAMP_PAYLOAD_FILE=${ELTEN_STAMP_PAYLOAD_FILE}"
            -P "${ELTEN_STAMP_SECRET_GENERATOR}"
    DEPENDS
            "${ELTEN_STAMP_PRIVATE_KEY_FILE}"
            "${ELTEN_STAMP_PAYLOAD_FILE}"
            "${ELTEN_STAMP_SECRET_GENERATOR}"
    COMMENT "Generating launcher stamp secret header"
    VERBATIM
  )
  add_custom_target(EltenStampSecretHeader DEPENDS "${ELTEN_STAMP_SECRET_HEADER}")
else()
  set(ELTEN_STAMP_SIGNATURE_AVAILABLE FALSE)
  set(ELTEN_STAMP_SIGNATURE_AVAILABLE_DEFINE 0)
  set(ELTEN_FORCE_DEVELOPER_MODE_DEFINE 1)
  message(WARNING "Launcher stamp key not found at ${ELTEN_STAMP_PRIVATE_KEY_FILE}. Building without get_stamp signing and forcing developer mode.")
endif()

add_custom_target(EltenBuildInfoHeader
  COMMAND "${CMAKE_COMMAND}"
          "-DSOURCE_DIR=${CMAKE_SOURCE_DIR}"
          "-DBUILD_INFO_HEADER=${ELTEN_BUILD_INFO_HEADER}"
          "-DBUILD_ID_FILE=${ELTEN_BUILD_ID_FILE}"
          "-DMANUAL_BUILD_ID=${ELTEN_BUILD_ID}"
          -P "${ELTEN_BUILD_INFO_GENERATOR}"
  BYPRODUCTS "${ELTEN_BUILD_INFO_HEADER}" "${ELTEN_BUILD_ID_FILE}"
  DEPENDS "${ELTEN_BUILD_INFO_GENERATOR}"
  COMMENT "Generating Elten build info header"
  VERBATIM
)

function(elten_configure_build_info_target target)
  target_include_directories(${target} PRIVATE
    "${ELTEN_GENERATED_DIR}"
  )
  target_sources(${target} PRIVATE
    "${ELTEN_BUILD_INFO_HEADER}"
  )
  add_dependencies(${target} EltenBuildInfoHeader)
endfunction()

function(elten_configure_stamp_target target)
  target_compile_definitions(${target} PRIVATE
    ELTEN_STAMP_SIGNATURE_AVAILABLE=${ELTEN_STAMP_SIGNATURE_AVAILABLE_DEFINE}
    ELTEN_FORCE_DEVELOPER_MODE=${ELTEN_FORCE_DEVELOPER_MODE_DEFINE}
  )
  if(ELTEN_STAMP_SIGNATURE_AVAILABLE)
    target_include_directories(${target} PRIVATE
      "${ELTEN_GENERATED_DIR}"
    )
    target_sources(${target} PRIVATE
      "${ELTEN_STAMP_SECRET_HEADER}"
    )
    add_dependencies(${target} EltenStampSecretHeader)
  endif()
endfunction()

set(ELTEN_ASSET_GENERATOR_SOURCE "${CMAKE_SOURCE_DIR}/launcher/tools/generate_assets.cpp")
set(ELTEN_ASSET_GENERATOR_BLAKE3_HEADER "${CMAKE_SOURCE_DIR}/launcher/src/blake3.hpp")

add_executable(EltenAssetGenerator
  "${ELTEN_ASSET_GENERATOR_SOURCE}"
  "launcher/src/blake3.hpp"
)

set(ELTEN_ASSET_GENERATOR_COMMAND "$<TARGET_FILE:EltenAssetGenerator>")
set(ELTEN_ASSET_GENERATOR_DEPENDS
  EltenAssetGenerator
  "$<TARGET_FILE:EltenAssetGenerator>"
  "${ELTEN_ASSET_GENERATOR_SOURCE}"
  "${ELTEN_ASSET_GENERATOR_BLAKE3_HEADER}"
)

target_include_directories(EltenAssetGenerator PRIVATE
  "${CMAKE_SOURCE_DIR}/launcher/src"
)

if(MSVC)
  target_compile_definitions(EltenAssetGenerator PRIVATE
    NOMINMAX
    WIN32_LEAN_AND_MEAN
  )
endif()

if(APPLE)
  set(ELTEN_LAUNCHER_PLATFORM "osx")
  set(ELTEN_LAUNCHER_ARCH "arm64")
  set(ELTEN_LAUNCHER_OUTPUT_NAME "elten")
  set(ELTEN_RUNTIME_ARCH_DIR "osx")
  elten_configure_ruby_runtime(PLATFORM osx ARCH "${ELTEN_LAUNCHER_ARCH}")
  set(ELTEN_PACKAGE_ROOT "${ELTEN_RELEASE_BASE}/osx")
  set(ELTEN_RUNTIME_DIR "${ELTEN_PACKAGE_ROOT}/bin/${ELTEN_RUNTIME_ARCH_DIR}")
  set(ELTEN_ZSTD_LIBRARY "${ELTEN_RUNTIME_DIR}/libzstd.dylib" CACHE FILEPATH "libzstd dylib used by macOS asset compression" FORCE)
  set(ELTEN_DIST_OSX_DIR "${CMAKE_SOURCE_DIR}/dist/osx")
  set(ELTEN_MACOS_BUNDLE_SCRIPT "${CMAKE_SOURCE_DIR}/cmake/macos_bundle.cmake")

  set(ELTEN_DEFAULT_MACOS_APP_IDENTITY "Developer ID Application")
  if(DEFINED ENV{ELTEN_MACOS_APP_IDENTITY})
    set(ELTEN_DEFAULT_MACOS_APP_IDENTITY "$ENV{ELTEN_MACOS_APP_IDENTITY}")
  elseif(DEFINED ENV{MACOS_APP_IDENTITY})
    set(ELTEN_DEFAULT_MACOS_APP_IDENTITY "$ENV{MACOS_APP_IDENTITY}")
  endif()

  set(ELTEN_DEFAULT_MACOS_INSTALLER_IDENTITY "Developer ID Installer")
  if(DEFINED ENV{ELTEN_MACOS_INSTALLER_IDENTITY})
    set(ELTEN_DEFAULT_MACOS_INSTALLER_IDENTITY "$ENV{ELTEN_MACOS_INSTALLER_IDENTITY}")
  elseif(DEFINED ENV{MACOS_INSTALLER_IDENTITY})
    set(ELTEN_DEFAULT_MACOS_INSTALLER_IDENTITY "$ENV{MACOS_INSTALLER_IDENTITY}")
  endif()

  set(ELTEN_DEFAULT_NOTARY_PROFILE "notary")
  if(DEFINED ENV{ELTEN_NOTARY_PROFILE})
    set(ELTEN_DEFAULT_NOTARY_PROFILE "$ENV{ELTEN_NOTARY_PROFILE}")
  elseif(DEFINED ENV{NOTARY_PROFILE})
    set(ELTEN_DEFAULT_NOTARY_PROFILE "$ENV{NOTARY_PROFILE}")
  endif()

  set(ELTEN_DEFAULT_MACOS_ENTITLEMENTS "${CMAKE_SOURCE_DIR}/tools/macos-entitlements.plist")
  if(DEFINED ENV{ELTEN_MACOS_ENTITLEMENTS})
    set(ELTEN_DEFAULT_MACOS_ENTITLEMENTS "$ENV{ELTEN_MACOS_ENTITLEMENTS}")
  elseif(DEFINED ENV{MACOS_ENTITLEMENTS})
    set(ELTEN_DEFAULT_MACOS_ENTITLEMENTS "$ENV{MACOS_ENTITLEMENTS}")
  endif()

  option(ELTEN_MACOS_SIGN "Sign and notarize macOS runtime, app and package artifacts" OFF)
  set(ELTEN_MACOS_APP_IDENTITY "${ELTEN_DEFAULT_MACOS_APP_IDENTITY}" CACHE STRING "Developer ID Application identity")
  set(ELTEN_MACOS_INSTALLER_IDENTITY "${ELTEN_DEFAULT_MACOS_INSTALLER_IDENTITY}" CACHE STRING "Developer ID Installer identity")
  set(ELTEN_NOTARY_PROFILE "${ELTEN_DEFAULT_NOTARY_PROFILE}" CACHE STRING "notarytool keychain profile")
  set(ELTEN_NOTARY_APPLE_ID "$ENV{ELTEN_NOTARY_APPLE_ID}" CACHE STRING "Apple ID for notarytool")
  set(ELTEN_NOTARY_PASSWORD "$ENV{ELTEN_NOTARY_PASSWORD}" CACHE STRING "App-specific notary password")
  set(ELTEN_NOTARY_TEAM_ID "$ENV{ELTEN_NOTARY_TEAM_ID}" CACHE STRING "Apple Team ID for notarytool")
  set(ELTEN_MACOS_ENTITLEMENTS "${ELTEN_DEFAULT_MACOS_ENTITLEMENTS}" CACHE FILEPATH "macOS signing entitlements")

  set(ELTEN_MACOS_SCRIPT_ARGS
    "-DSIGN=${ELTEN_MACOS_SIGN}"
    "-DAPP_IDENTITY=${ELTEN_MACOS_APP_IDENTITY}"
    "-DINSTALLER_IDENTITY=${ELTEN_MACOS_INSTALLER_IDENTITY}"
    "-DNOTARY_PROFILE=${ELTEN_NOTARY_PROFILE}"
    "-DNOTARY_APPLE_ID=${ELTEN_NOTARY_APPLE_ID}"
    "-DNOTARY_PASSWORD=${ELTEN_NOTARY_PASSWORD}"
    "-DNOTARY_TEAM_ID=${ELTEN_NOTARY_TEAM_ID}"
    "-DENTITLEMENTS=${ELTEN_MACOS_ENTITLEMENTS}"
  )

  set(ELTEN_MACOS_SIGN_CONFIG "${ELTEN_GENERATED_DIR}/macos-sign-config.txt")
  file(MAKE_DIRECTORY "${ELTEN_GENERATED_DIR}")
  file(WRITE "${ELTEN_MACOS_SIGN_CONFIG}"
    "sign=${ELTEN_MACOS_SIGN}\n"
    "app_identity=${ELTEN_MACOS_APP_IDENTITY}\n"
    "installer_identity=${ELTEN_MACOS_INSTALLER_IDENTITY}\n"
    "notary_profile=${ELTEN_NOTARY_PROFILE}\n"
    "entitlements=${ELTEN_MACOS_ENTITLEMENTS}\n"
  )

  file(GLOB_RECURSE ELTEN_MACOS_RUNTIME_INPUTS CONFIGURE_DEPENDS
    "${CMAKE_SOURCE_DIR}/bin/osx/*"
    "${CMAKE_SOURCE_DIR}/resources/*"
    "${CMAKE_SOURCE_DIR}/locale/*"
    "${CMAKE_SOURCE_DIR}/audio/*"
  )

  set(ELTEN_RUNTIME_FINALIZED_STAMP "${ELTEN_GENERATED_DIR}/macos-runtime-finalized.stamp")
  add_custom_command(
    OUTPUT "${ELTEN_RUNTIME_FINALIZED_STAMP}"
    COMMAND "${CMAKE_COMMAND}" -E rm -rf "${ELTEN_PACKAGE_ROOT}"
    COMMAND "${CMAKE_COMMAND}" -E make_directory "${ELTEN_GENERATED_DIR}" "${ELTEN_PACKAGE_ROOT}" "${ELTEN_RUNTIME_DIR}" "${ELTEN_DIST_OSX_DIR}"
    COMMAND "${CMAKE_COMMAND}" -E copy_directory "${CMAKE_SOURCE_DIR}/bin/osx" "${ELTEN_PACKAGE_ROOT}/bin/osx"
    COMMAND "${CMAKE_COMMAND}" -E chdir "${CMAKE_BINARY_DIR}" "${ELTEN_ASSET_GENERATOR_COMMAND}"
            "--root" "${CMAKE_SOURCE_DIR}"
            "--package-root" "${ELTEN_PACKAGE_ROOT}"
            "--ruby-root" "${ELTEN_RUBY_ROOT}"
            "--gem-lockfile" "${ELTEN_RUBY_GEM_LOCKFILE}"
            "--arch" "${ELTEN_LAUNCHER_ARCH}"
            "--platform" "${ELTEN_LAUNCHER_PLATFORM}"
            "--native-output" "${ELTEN_RUNTIME_DIR}"
            "--compression" "${ELTEN_EMBEDDED_COMPRESSION}"
            "--zstd-library" "${ELTEN_ZSTD_LIBRARY}"
            "--prepare-only"
    COMMAND "${CMAKE_COMMAND}"
            ${ELTEN_MACOS_SCRIPT_ARGS}
            "-DMODE=FINALIZE_RUNTIME"
            "-DRUNTIME_DIR=${ELTEN_RUNTIME_DIR}"
            "-DDIST_DIR=${ELTEN_DIST_OSX_DIR}"
            -P "${ELTEN_MACOS_BUNDLE_SCRIPT}"
    COMMAND "${CMAKE_COMMAND}" -E touch "${ELTEN_RUNTIME_FINALIZED_STAMP}"
    DEPENDS
            ${ELTEN_ASSET_GENERATOR_DEPENDS}
            "${ELTEN_RUBY_RUNTIME_STAMP}"
            ${ELTEN_MACOS_RUNTIME_INPUTS}
            "${ELTEN_MACOS_SIGN_CONFIG}"
            "${ELTEN_MACOS_BUNDLE_SCRIPT}"
    COMMENT "Preparing macOS runtime in build/release/osx"
    VERBATIM
  )

  add_custom_target(EltenRuntimeFinalized DEPENDS "${ELTEN_RUNTIME_FINALIZED_STAMP}")

  add_custom_command(
    OUTPUT "${ELTEN_EMBEDDED_CPP}" "${ELTEN_STAMP_PAYLOAD_FILE}"
    COMMAND "${CMAKE_COMMAND}" -E make_directory "${ELTEN_GENERATED_DIR}" "${ELTEN_RUNTIME_DIR}"
    COMMAND "${CMAKE_COMMAND}" -E chdir "${CMAKE_BINARY_DIR}" "${ELTEN_ASSET_GENERATOR_COMMAND}"
            "--root" "${CMAKE_SOURCE_DIR}"
            "--package-root" "${ELTEN_PACKAGE_ROOT}"
            "--ruby-root" "${ELTEN_RUBY_ROOT}"
            "--gem-lockfile" "${ELTEN_RUBY_GEM_LOCKFILE}"
            "--arch" "${ELTEN_LAUNCHER_ARCH}"
            "--platform" "${ELTEN_LAUNCHER_PLATFORM}"
            "--native-output" "${ELTEN_RUNTIME_DIR}"
            "--compression" "${ELTEN_EMBEDDED_COMPRESSION}"
            "--zstd-library" "${ELTEN_ZSTD_LIBRARY}"
            "--no-copy-runtime-assets"
            "--out" "${ELTEN_EMBEDDED_CPP}"
            "--stamp-payload-out" "${ELTEN_STAMP_PAYLOAD_FILE}"
    DEPENDS
            ${ELTEN_ASSET_GENERATOR_DEPENDS}
            "${ELTEN_RUNTIME_FINALIZED_STAMP}"
            "${ELTEN_RUBY_RUNTIME_STAMP}"
            ${ELTEN_RB_SOURCES}
            "${CMAKE_SOURCE_DIR}/filelist"
    COMMENT "Preparing launcher assets for bin/${ELTEN_RUNTIME_ARCH_DIR}"
    VERBATIM
  )
  add_custom_target(EltenEmbeddedAssets DEPENDS "${ELTEN_EMBEDDED_CPP}" "${ELTEN_STAMP_PAYLOAD_FILE}")
  if(TARGET EltenStampSecretHeader)
    add_dependencies(EltenStampSecretHeader EltenEmbeddedAssets)
  endif()

  add_executable(EltenLauncher
    "launcher/src/launcher.cpp"
    "launcher/src/platform_osx.cpp"
    "launcher/src/platform.h"
    "launcher/src/embedded_assets.hpp"
    "launcher/src/blake3.hpp"
    "launcher/src/sha256.hpp"
    "launcher/src/stamp.cpp"
    "launcher/src/stamp.hpp"
    "${ELTEN_EMBEDDED_CPP}"
  )

  target_compile_definitions(EltenLauncher PRIVATE
    ELTEN_LAUNCHER_ARCH="${ELTEN_LAUNCHER_ARCH}"
    ELTEN_RUNTIME_DIR_NAME="${ELTEN_RUNTIME_ARCH_DIR}"
    ELTEN_RUBY_ROOT_NAME="ruby"
    ELTEN_RUBY_API_VERSION="${ELTEN_RUNTIME_RUBY_API_VERSION}"
    ELTEN_EMBEDDED_ZSTD=${ELTEN_EMBEDDED_ZSTD_DEFINE}
  )
  elten_configure_build_info_target(EltenLauncher)
  elten_configure_stamp_target(EltenLauncher)

  target_include_directories(EltenLauncher PRIVATE
    "${CMAKE_SOURCE_DIR}/launcher/src"
    "${ELTEN_RUBY_INCLUDE_DIR}"
    "${ELTEN_RUBY_PLATFORM_INCLUDE_DIR}"
  )

  find_library(COREFOUNDATION_FRAMEWORK CoreFoundation REQUIRED)
  find_library(IOKIT_FRAMEWORK IOKit REQUIRED)

  target_link_libraries(EltenLauncher PRIVATE
    "${ELTEN_RUBY_LIBRARY}"
    "${COREFOUNDATION_FRAMEWORK}"
    "${IOKIT_FRAMEWORK}"
    dl
    objc
    pthread
  )

  set_target_properties(EltenLauncher PROPERTIES
    ENABLE_EXPORTS ON
    OUTPUT_NAME "${ELTEN_LAUNCHER_OUTPUT_NAME}"
    RUNTIME_OUTPUT_DIRECTORY "${ELTEN_PACKAGE_ROOT}"
    BUILD_RPATH "@executable_path/bin/osx;@executable_path/../Resources/bin/osx"
    INSTALL_RPATH "@executable_path/bin/osx;@executable_path/../Resources/bin/osx"
  )

  add_dependencies(EltenLauncher EltenRubyRuntime)

  add_custom_target(EltenApp
    COMMAND "${CMAKE_COMMAND}"
            ${ELTEN_MACOS_SCRIPT_ARGS}
            "-DMODE=CREATE_APP"
            "-DRELEASE_ROOT=${ELTEN_PACKAGE_ROOT}"
            "-DRUNTIME_DIR=${ELTEN_RUNTIME_DIR}"
            "-DDIST_DIR=${ELTEN_DIST_OSX_DIR}"
            -P "${ELTEN_MACOS_BUNDLE_SCRIPT}"
    DEPENDS
            EltenLauncher
            "${ELTEN_RUNTIME_FINALIZED_STAMP}"
    COMMENT "Creating dist/osx/Elten.app"
    VERBATIM
  )

  add_custom_target(EltenPkg
    COMMAND "${CMAKE_COMMAND}"
            ${ELTEN_MACOS_SCRIPT_ARGS}
            "-DMODE=CREATE_PKG"
            "-DDIST_DIR=${ELTEN_DIST_OSX_DIR}"
            -P "${ELTEN_MACOS_BUNDLE_SCRIPT}"
    DEPENDS EltenApp
    COMMENT "Creating dist/osx/Elten.pkg"
    VERBATIM
  )
else()
  set(ELTEN_GENERATOR_PLATFORM "${CMAKE_VS_PLATFORM_NAME}")
  if(ELTEN_GENERATOR_PLATFORM STREQUAL "")
    set(ELTEN_GENERATOR_PLATFORM "${CMAKE_GENERATOR_PLATFORM}")
  endif()

  if(ELTEN_GENERATOR_PLATFORM MATCHES "ARM64")
    set(ELTEN_LAUNCHER_ARCH "arm64")
    set(ELTEN_LAUNCHER_OUTPUT_NAME "elten-arm64")
  elseif(ELTEN_GENERATOR_PLATFORM MATCHES "Win32|x86")
    set(ELTEN_LAUNCHER_ARCH "x86")
    set(ELTEN_LAUNCHER_OUTPUT_NAME "elten-x86")
  elseif(ELTEN_GENERATOR_PLATFORM MATCHES "x64|AMD64")
    set(ELTEN_LAUNCHER_ARCH "x64")
    set(ELTEN_LAUNCHER_OUTPUT_NAME "elten-x64")
  elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "^(ARM64|AARCH64|aarch64)$")
    set(ELTEN_LAUNCHER_ARCH "arm64")
    set(ELTEN_LAUNCHER_OUTPUT_NAME "elten-arm64")
  elseif(CMAKE_SIZEOF_VOID_P EQUAL 8)
    set(ELTEN_LAUNCHER_ARCH "x64")
    set(ELTEN_LAUNCHER_OUTPUT_NAME "elten-x64")
  else()
    set(ELTEN_LAUNCHER_ARCH "x86")
    set(ELTEN_LAUNCHER_OUTPUT_NAME "elten-x86")
  endif()

  elten_configure_ruby_runtime(PLATFORM windows ARCH "${ELTEN_LAUNCHER_ARCH}")
  set(ELTEN_RUNTIME_ARCH_DIR "windows-${ELTEN_LAUNCHER_ARCH}")

  set(ELTEN_PACKAGE_ROOT "${ELTEN_RELEASE_BASE}/windows")
  set(ELTEN_RUNTIME_DIR "${ELTEN_PACKAGE_ROOT}/bin/${ELTEN_RUNTIME_ARCH_DIR}")
  set(ELTEN_DIST_WINDOWS_DIR "${CMAKE_SOURCE_DIR}/dist/windows")
  set(ELTEN_WINDOWS_BUNDLE_SCRIPT "${CMAKE_SOURCE_DIR}/cmake/windows_bundle.cmake")
  set(ELTEN_WINDOWS_INSTALLER_SCRIPT "${CMAKE_SOURCE_DIR}/launcher/installer/inst_elten.iss")

  option(ELTEN_WINDOWS_SIGN "Sign Windows launcher and installer artifacts" OFF)
  set(ELTEN_WINDOWS_SIGNTOOL "" CACHE FILEPATH "signtool.exe used for Windows signing")
  set(ELTEN_WINDOWS_TIMESTAMP_URL "http://time.certum.pl" CACHE STRING "RFC 3161 timestamp URL used for Windows signing")
  set(ELTEN_WINDOWS_SCRIPT_ARGS
    "-DSIGN=${ELTEN_WINDOWS_SIGN}"
    "-DSIGNTOOL=${ELTEN_WINDOWS_SIGNTOOL}"
    "-DTIMESTAMP_URL=${ELTEN_WINDOWS_TIMESTAMP_URL}"
  )

  set(ELTEN_WINDOWS_BIN_COPY_COMMANDS
    COMMAND "${CMAKE_COMMAND}" -E make_directory "${ELTEN_PACKAGE_ROOT}"
    COMMAND "${CMAKE_COMMAND}" -E make_directory "${ELTEN_PACKAGE_ROOT}/bin"
  )
  foreach(elten_base_arch_dir windows-x86 windows-x64 windows-arm64)
    if(EXISTS "${CMAKE_SOURCE_DIR}/bin/${elten_base_arch_dir}")
      list(APPEND ELTEN_WINDOWS_BIN_COPY_COMMANDS
        COMMAND "${CMAKE_COMMAND}" -E copy_directory "${CMAKE_SOURCE_DIR}/bin/${elten_base_arch_dir}" "${ELTEN_PACKAGE_ROOT}/bin/${elten_base_arch_dir}"
      )
    endif()
  endforeach()

  file(GLOB_RECURSE ELTEN_WINDOWS_BASE_RUNTIME_INPUTS CONFIGURE_DEPENDS
    "${CMAKE_SOURCE_DIR}/bin/windows-x86/*"
    "${CMAKE_SOURCE_DIR}/bin/windows-x64/*"
    "${CMAKE_SOURCE_DIR}/bin/windows-arm64/*"
    "${CMAKE_SOURCE_DIR}/resources/*"
    "${CMAKE_SOURCE_DIR}/locale/*"
    "${CMAKE_SOURCE_DIR}/audio/*"
    "${CMAKE_SOURCE_DIR}/nvda/*"
  )
  set(ELTEN_LEGACY_DATA_FILES
    langs.dat
    locations.dat
    locale.dat
    eltencredpub.pem
    eltenpub.pem
  )
  set(ELTEN_LEGACY_DATA_CLEANUP)
  foreach(elten_legacy_data_file IN LISTS ELTEN_LEGACY_DATA_FILES)
    list(APPEND ELTEN_LEGACY_DATA_CLEANUP "${ELTEN_PACKAGE_ROOT}/data/${elten_legacy_data_file}")
  endforeach()

  add_custom_command(
    OUTPUT "${ELTEN_EMBEDDED_CPP}" "${ELTEN_STAMP_PAYLOAD_FILE}"
    COMMAND "${CMAKE_COMMAND}" -E make_directory "${ELTEN_GENERATED_DIR}" "${ELTEN_RUNTIME_DIR}"
    COMMAND "${CMAKE_COMMAND}" -E rm -rf "${ELTEN_PACKAGE_ROOT}/audio" "${ELTEN_PACKAGE_ROOT}/resources"
    COMMAND "${CMAKE_COMMAND}" -E rm -f ${ELTEN_LEGACY_DATA_CLEANUP}
    ${ELTEN_WINDOWS_BIN_COPY_COMMANDS}
    COMMAND "${CMAKE_COMMAND}" -E chdir "${CMAKE_BINARY_DIR}" "${ELTEN_ASSET_GENERATOR_COMMAND}"
            "--root" "${CMAKE_SOURCE_DIR}"
            "--package-root" "${ELTEN_PACKAGE_ROOT}"
            "--ruby-root" "${ELTEN_RUBY_ROOT}"
            "--gem-lockfile" "${ELTEN_RUBY_GEM_LOCKFILE}"
            "--arch" "${ELTEN_LAUNCHER_ARCH}"
            "--platform" "windows"
            "--runtime-output" "${ELTEN_RUNTIME_DIR}"
            "--native-output" "${ELTEN_RUNTIME_DIR}"
            "--compression" "${ELTEN_EMBEDDED_COMPRESSION}"
            "--zstd-library" "${ELTEN_RUNTIME_DIR}/libzstd.dll"
            "--out" "${ELTEN_EMBEDDED_CPP}"
            "--stamp-payload-out" "${ELTEN_STAMP_PAYLOAD_FILE}"
    DEPENDS
            ${ELTEN_ASSET_GENERATOR_DEPENDS}
            "${ELTEN_RUBY_RUNTIME_STAMP}"
            ${ELTEN_RB_SOURCES}
            ${ELTEN_WINDOWS_BASE_RUNTIME_INPUTS}
            "${CMAKE_SOURCE_DIR}/filelist"
    COMMENT "Preparing launcher assets for bin/${ELTEN_RUNTIME_ARCH_DIR}"
    VERBATIM
  )
  add_custom_target(EltenEmbeddedAssets DEPENDS "${ELTEN_EMBEDDED_CPP}" "${ELTEN_STAMP_PAYLOAD_FILE}")
  if(TARGET EltenStampSecretHeader)
    add_dependencies(EltenStampSecretHeader EltenEmbeddedAssets)
  endif()

  add_executable(EltenLauncher WIN32
    "launcher/src/launcher.cpp"
    "launcher/src/platform_windows.cpp"
    "launcher/src/platform.h"
    "launcher/src/embedded_assets.hpp"
    "launcher/src/blake3.hpp"
    "launcher/src/sha256.hpp"
    "launcher/src/stamp.cpp"
    "launcher/src/stamp.hpp"
    "${ELTEN_EMBEDDED_CPP}"
  )

  target_compile_definitions(EltenLauncher PRIVATE
    ELTEN_LAUNCHER_ARCH="${ELTEN_LAUNCHER_ARCH}"
    ELTEN_RUNTIME_DIR_NAME="${ELTEN_RUNTIME_ARCH_DIR}"
    ELTEN_RUBY_ROOT_NAME="ruby"
    ELTEN_RUBY_DLL_NAME="${ELTEN_RUBY_DLL}"
    ELTEN_RUBY_API_VERSION="${ELTEN_RUNTIME_RUBY_API_VERSION}"
    ELTEN_EMBEDDED_ZSTD=${ELTEN_EMBEDDED_ZSTD_DEFINE}
    NOMINMAX
    WIN32_LEAN_AND_MEAN
  )
  elten_configure_build_info_target(EltenLauncher)
  elten_configure_stamp_target(EltenLauncher)

  target_include_directories(EltenLauncher PRIVATE
    "${CMAKE_SOURCE_DIR}/launcher/src"
  )

  target_link_libraries(EltenLauncher PRIVATE
    advapi32
    shell32
    user32
  )

  if(ELTEN_LAUNCHER_ARCH STREQUAL "x86")
    add_executable(EltenLauncherFacade WIN32 EXCLUDE_FROM_ALL
      "launcher/src/launcher_facade_windows.cpp"
    )
    target_compile_definitions(EltenLauncherFacade PRIVATE
      NOMINMAX
      WIN32_LEAN_AND_MEAN
    )
    target_link_libraries(EltenLauncherFacade PRIVATE
      shell32
      user32
    )
    set_target_properties(EltenLauncherFacade PROPERTIES
      OUTPUT_NAME "elten"
      RUNTIME_OUTPUT_DIRECTORY "${ELTEN_PACKAGE_ROOT}"
    )
    if(MSVC)
      target_compile_options(EltenLauncherFacade PRIVATE /bigobj)
    endif()
  endif()

  if(MSVC)
    target_compile_options(EltenLauncher PRIVATE /bigobj)
  endif()

  set_target_properties(EltenLauncher PROPERTIES
    OUTPUT_NAME "${ELTEN_LAUNCHER_OUTPUT_NAME}"
    RUNTIME_OUTPUT_DIRECTORY "${ELTEN_PACKAGE_ROOT}"
  )

  add_dependencies(EltenLauncher EltenRubyRuntime)

  add_custom_target(EltenApp
    COMMAND "${CMAKE_COMMAND}"
            ${ELTEN_WINDOWS_SCRIPT_ARGS}
            "-DMODE=CREATE_DIST"
            "-DRELEASE_ROOT=${ELTEN_PACKAGE_ROOT}"
            "-DDIST_DIR=${ELTEN_DIST_WINDOWS_DIR}"
            "-DINSTALLER_SCRIPT=${ELTEN_WINDOWS_INSTALLER_SCRIPT}"
            -P "${ELTEN_WINDOWS_BUNDLE_SCRIPT}"
    DEPENDS EltenLauncher
    COMMENT "Creating dist/windows/Elten"
    VERBATIM
  )

  add_custom_target(EltenPkg
    COMMAND "${CMAKE_COMMAND}"
            ${ELTEN_WINDOWS_SCRIPT_ARGS}
            "-DMODE=CREATE_INSTALLER"
            "-DRELEASE_ROOT=${ELTEN_PACKAGE_ROOT}"
            "-DDIST_DIR=${ELTEN_DIST_WINDOWS_DIR}"
            "-DINSTALLER_SCRIPT=${ELTEN_WINDOWS_INSTALLER_SCRIPT}"
            -P "${ELTEN_WINDOWS_BUNDLE_SCRIPT}"
    DEPENDS EltenApp
    COMMENT "Creating dist/windows/EltenSetup.exe"
    VERBATIM
  )
endif()

foreach(config DEBUG RELEASE RELWITHDEBINFO MINSIZEREL)
  set_target_properties(EltenLauncher PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY_${config} "${ELTEN_PACKAGE_ROOT}"
  )
  if(TARGET EltenLauncherFacade)
    set_target_properties(EltenLauncherFacade PROPERTIES
      RUNTIME_OUTPUT_DIRECTORY_${config} "${ELTEN_PACKAGE_ROOT}"
    )
  endif()
endforeach()
