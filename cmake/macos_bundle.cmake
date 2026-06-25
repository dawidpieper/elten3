cmake_minimum_required(VERSION 3.24)

if(NOT DEFINED MODE)
  message(FATAL_ERROR "MODE is required")
endif()

foreach(optional_name
    APP_IDENTITY
    INSTALLER_IDENTITY
    NOTARY_PROFILE
    NOTARY_APPLE_ID
    NOTARY_PASSWORD
    NOTARY_TEAM_ID
    ENTITLEMENTS
    DIST_DIR
    RELEASE_ROOT
    RUNTIME_DIR)
  if(NOT DEFINED ${optional_name})
    set(${optional_name} "")
  endif()
endforeach()

function(require_value name)
  if(NOT DEFINED ${name} OR "${${name}}" STREQUAL "")
    message(FATAL_ERROR "${name} is required")
  endif()
endfunction()

function(require_program out name)
  string(MAKE_C_IDENTIFIER "${out}" out_key)
  set(program_var "ELTEN_MACOS_${out_key}_PROGRAM")
  find_program(${program_var} NAMES "${name}")
  if(NOT DEFINED ${program_var} OR "${${program_var}}" STREQUAL "" OR "${${program_var}}" MATCHES "-NOTFOUND$")
    message(FATAL_ERROR "${name} not found")
  endif()
  get_filename_component(program_name "${${program_var}}" NAME)
  if(NOT program_name STREQUAL "${name}")
    message(FATAL_ERROR "Expected ${name}, got ${${program_var}}")
  endif()
  set(${out} "${${program_var}}" PARENT_SCOPE)
endfunction()

function(run_checked)
  execute_process(
    COMMAND ${ARGV}
    RESULT_VARIABLE result
    OUTPUT_VARIABLE stdout
    ERROR_VARIABLE stderr
  )
  if(NOT result EQUAL 0)
    string(REPLACE ";" " " command_line "${ARGV}")
    message(FATAL_ERROR "Command failed (${result}): ${command_line}\n${stdout}\n${stderr}")
  endif()
  if(NOT stdout STREQUAL "")
    string(STRIP "${stdout}" stdout)
    if(NOT stdout STREQUAL "")
      message(STATUS "${stdout}")
    endif()
  endif()
endfunction()

function(run_checked_streamed)
  execute_process(
    COMMAND ${ARGV}
    RESULT_VARIABLE result
    OUTPUT_VARIABLE stdout
    ERROR_VARIABLE stderr
    ECHO_OUTPUT_VARIABLE
    ECHO_ERROR_VARIABLE
  )
  if(NOT result EQUAL 0)
    string(REPLACE ";" " " command_line "${ARGV}")
    message(FATAL_ERROR "Command failed (${result}): ${command_line}\n${stdout}\n${stderr}")
  endif()
endfunction()

function(run_optional)
  execute_process(
    COMMAND ${ARGV}
    RESULT_VARIABLE result
    OUTPUT_QUIET
    ERROR_QUIET
  )
endfunction()

function(copy_tree source destination)
  if(NOT EXISTS "${source}")
    message(FATAL_ERROR "Missing source tree: ${source}")
  endif()
  file(REMOVE_RECURSE "${destination}")
  get_filename_component(parent "${destination}" DIRECTORY)
  file(MAKE_DIRECTORY "${parent}")
  file(COPY "${source}/" DESTINATION "${destination}")
endfunction()

function(is_macho_file path out)
  if("${path}" MATCHES "^@")
    set(${out} FALSE PARENT_SCOPE)
    return()
  endif()
  if(NOT "${path}" MATCHES "^/" OR NOT EXISTS "${path}" OR IS_DIRECTORY "${path}")
    set(${out} FALSE PARENT_SCOPE)
    return()
  endif()

  file(READ "${path}" magic OFFSET 0 LIMIT 4 HEX)
  string(TOUPPER "${magic}" magic)
  if(magic STREQUAL "FEEDFACE" OR
     magic STREQUAL "CEFAEDFE" OR
     magic STREQUAL "FEEDFACF" OR
     magic STREQUAL "CFFAEDFE" OR
     magic STREQUAL "CAFEBABE" OR
     magic STREQUAL "BEBAFECA" OR
     magic STREQUAL "CAFEBABF" OR
     magic STREQUAL "BFBAFECA")
    set(${out} TRUE PARENT_SCOPE)
  else()
    set(${out} FALSE PARENT_SCOPE)
  endif()
endfunction()

function(macho_files root out)
  set(result)
  if(EXISTS "${root}")
    set(candidate_file "${CMAKE_CURRENT_BINARY_DIR}/elten-macho-candidates.txt")
    execute_process(
      COMMAND "${FIND_TOOL}" "${root}" -type f "(" -perm -111 -o -name "*.dylib" -o -name "*.bundle" -o -name "*.so" ")" -print
      RESULT_VARIABLE find_result
      OUTPUT_FILE "${candidate_file}"
      ERROR_VARIABLE find_error
    )
    if(NOT find_result EQUAL 0)
      message(FATAL_ERROR "find failed for ${root}: ${find_error}")
    endif()
    file(STRINGS "${candidate_file}" candidates ENCODING UTF-8)
    file(REMOVE "${candidate_file}")
    foreach(candidate IN LISTS candidates)
      if(candidate STREQUAL "")
        continue()
      endif()
      is_macho_file("${candidate}" is_macho)
      if(is_macho)
        list(APPEND result "${candidate}")
      endif()
    endforeach()
  endif()
  list(SORT result)
  set(${out} ${result} PARENT_SCOPE)
endfunction()

function(otool_dependencies path out)
  if("${path}" MATCHES "^@" OR NOT "${path}" MATCHES "^/" OR NOT EXISTS "${path}" OR IS_DIRECTORY "${path}")
    set(${out} "" PARENT_SCOPE)
    return()
  endif()
  execute_process(
    COMMAND "${OTOOL_TOOL}" -L "${path}"
    RESULT_VARIABLE result
    OUTPUT_VARIABLE output
    ERROR_VARIABLE error
  )
  if(NOT result EQUAL 0)
    message(FATAL_ERROR "otool failed for ${path}: ${error}")
  endif()
  string(REPLACE "\r\n" "\n" output "${output}")
  string(REPLACE "\n" ";" lines "${output}")
  set(deps)
  list(LENGTH lines line_count)
  if(line_count GREATER 1)
    math(EXPR last_index "${line_count} - 1")
    foreach(index RANGE 1 ${last_index})
      list(GET lines ${index} line)
      string(STRIP "${line}" line)
      if(line STREQUAL "")
        continue()
      endif()
      string(REGEX MATCH "^[^ \t]+" dependency "${line}")
      if(NOT dependency STREQUAL "")
        list(APPEND deps "${dependency}")
      endif()
    endforeach()
  endif()
  set(${out} ${deps} PARENT_SCOPE)
endfunction()

function(dylib_id path out)
  if("${path}" MATCHES "^@" OR NOT "${path}" MATCHES "^/" OR NOT EXISTS "${path}" OR IS_DIRECTORY "${path}")
    set(${out} "" PARENT_SCOPE)
    return()
  endif()
  execute_process(
    COMMAND "${OTOOL_TOOL}" -D "${path}"
    RESULT_VARIABLE result
    OUTPUT_VARIABLE output
    ERROR_QUIET
  )
  if(NOT result EQUAL 0)
    set(${out} "" PARENT_SCOPE)
    return()
  endif()
  string(REPLACE "\r\n" "\n" output "${output}")
  string(REPLACE "\n" ";" lines "${output}")
  list(LENGTH lines line_count)
  if(line_count GREATER 1)
    list(GET lines 1 id_line)
    string(STRIP "${id_line}" id_line)
    string(REGEX MATCH "^[^ \t]+" id "${id_line}")
    set(${out} "${id}" PARENT_SCOPE)
  else()
    set(${out} "" PARENT_SCOPE)
  endif()
endfunction()

function(dependency_is_rewritable_dylib dependency out)
  if(dependency MATCHES "^@" OR
     dependency MATCHES "^/System/Library/" OR
     dependency MATCHES "^/usr/lib/")
    set(${out} FALSE PARENT_SCOPE)
    return()
  endif()
  if(dependency MATCHES "^/.+\\.dylib$")
    set(${out} TRUE PARENT_SCOPE)
  else()
    set(${out} FALSE PARENT_SCOPE)
  endif()
endfunction()

function(dependency_is_runtime_rpath_dylib dependency out)
  if(dependency MATCHES "^@rpath/.+\\.dylib$")
    set(${out} TRUE PARENT_SCOPE)
  else()
    set(${out} FALSE PARENT_SCOPE)
  endif()
endfunction()

function(loader_relative_to_runtime_file consumer runtime_dir target_name out)
  get_filename_component(consumer_dir "${consumer}" DIRECTORY)
  file(RELATIVE_PATH relative_target "${consumer_dir}" "${runtime_dir}/${target_name}")
  if(relative_target STREQUAL "")
    set(relative_target "${target_name}")
  endif()
  set(${out} "${relative_target}" PARENT_SCOPE)
endfunction()

function(bundle_dependency_dylib dependency runtime_dir out_changed)
  if("${dependency}" MATCHES "^@" OR NOT "${dependency}" MATCHES "^/")
    set(${out_changed} FALSE PARENT_SCOPE)
    return()
  endif()

  get_filename_component(target_name "${dependency}" NAME)
  set(target_path "${runtime_dir}/${target_name}")
  set(changed FALSE)
  if(NOT dependency STREQUAL target_path AND NOT EXISTS "${target_path}")
    message(STATUS "Bundling dylib dependency: ${dependency} -> ${target_path}")
    file(COPY_FILE "${dependency}" "${target_path}")
    run_optional("${CHMOD_TOOL}" 755 "${target_path}")
    set(changed TRUE)
  endif()
  set(${out_changed} ${changed} PARENT_SCOPE)
endfunction()

function(rewrite_dependency_for_consumer consumer dependency runtime_dir out_changed)
  is_macho_file("${consumer}" is_macho)
  if(NOT is_macho)
    set(${out_changed} FALSE PARENT_SCOPE)
    return()
  endif()

  get_filename_component(target_name "${dependency}" NAME)
  loader_relative_to_runtime_file("${consumer}" "${runtime_dir}" "${target_name}" relative_target)
  set(new_dependency "@loader_path/${relative_target}")
  message(STATUS "Rewriting dependency in ${consumer}: ${dependency} -> ${new_dependency}")
  run_optional("${CHMOD_TOOL}" u+w "${consumer}")
  run_checked("${INSTALL_NAME_TOOL}" -change "${dependency}" "${new_dependency}" "${consumer}")
  set(${out_changed} TRUE PARENT_SCOPE)
endfunction()

function(normalize_macos_dylib_ids runtime_dir)
  if(NOT EXISTS "${runtime_dir}")
    return()
  endif()
  file(GLOB_RECURSE dylibs LIST_DIRECTORIES false "${runtime_dir}/*.dylib")
  list(SORT dylibs)
  foreach(dylib_path IN LISTS dylibs)
    is_macho_file("${dylib_path}" is_macho)
    if(NOT is_macho)
      continue()
    endif()
    dylib_id("${dylib_path}" current_id)
    dependency_is_rewritable_dylib("${current_id}" rewritable)
    if(rewritable)
      get_filename_component(target_name "${dylib_path}" NAME)
      set(new_id "@rpath/${target_name}")
      message(STATUS "Rewriting dylib id in ${dylib_path}: ${current_id} -> ${new_id}")
      run_optional("${CHMOD_TOOL}" u+w "${dylib_path}")
      run_checked("${INSTALL_NAME_TOOL}" -id "${new_id}" "${dylib_path}")
    endif()
  endforeach()
endfunction()

function(verify_no_external_macos_dylib_dependencies runtime_dir scan_root)
  macho_files("${scan_root}" files)
  set(bad)
  foreach(macho_file IN LISTS files)
    set(self_id "")
    if(macho_file MATCHES "\\.dylib$")
      dylib_id("${macho_file}" self_id)
    endif()
    otool_dependencies("${macho_file}" deps)
    foreach(dependency IN LISTS deps)
      if(dependency STREQUAL self_id OR dependency STREQUAL macho_file)
        continue()
      endif()
      dependency_is_rewritable_dylib("${dependency}" rewritable)
      if(rewritable)
        list(APPEND bad "${macho_file} -> ${dependency}")
      endif()
      dependency_is_runtime_rpath_dylib("${dependency}" runtime_rpath)
      if(runtime_rpath)
        get_filename_component(target_name "${dependency}" NAME)
        if(NOT EXISTS "${runtime_dir}/${target_name}")
          list(APPEND bad "${macho_file} -> unresolved ${dependency}")
        endif()
      endif()
    endforeach()
  endforeach()

  if(bad)
    list(SORT bad)
    list(REMOVE_DUPLICATES bad)
    file(MAKE_DIRECTORY "${DIST_DIR}")
    set(report "${DIST_DIR}/dylib-unresolved.txt")
    string(REPLACE ";" "\n" report_text "${bad}")
    file(WRITE "${report}" "${report_text}\n")
    message(FATAL_ERROR "Unresolved dylib dependencies remain. Full report: ${report}")
  endif()
  file(REMOVE "${DIST_DIR}/dylib-unresolved.txt")
  message(STATUS "External dylib dependencies verified for ${runtime_dir}.")
endfunction()

function(rewrite_macos_dylib_dependencies runtime_dir scan_root)
  if(NOT EXISTS "${runtime_dir}")
    return()
  endif()
  message(STATUS "Bundling and rewriting external dylib dependencies in ${runtime_dir}...")
  foreach(pass RANGE 1 32)
    message(STATUS "Dylib dependency rewrite pass ${pass}...")
    set(changed FALSE)
    set(change_count 0)
    macho_files("${scan_root}" files)
    list(LENGTH files file_count)
    foreach(macho_file IN LISTS files)
      set(self_id "")
      if(macho_file MATCHES "\\.dylib$")
        dylib_id("${macho_file}" self_id)
      endif()
      otool_dependencies("${macho_file}" deps)
      foreach(dependency IN LISTS deps)
        if(dependency STREQUAL self_id OR dependency STREQUAL macho_file)
          continue()
        endif()

        dependency_is_rewritable_dylib("${dependency}" rewritable)
        dependency_is_runtime_rpath_dylib("${dependency}" runtime_rpath)
        get_filename_component(target_name "${dependency}" NAME)
        set(dependency_target "${runtime_dir}/${target_name}")

        if(rewritable)
          if(EXISTS "${dependency}")
            bundle_dependency_dylib("${dependency}" "${runtime_dir}" bundled)
            if(bundled)
              set(changed TRUE)
              math(EXPR change_count "${change_count} + 1")
            endif()
          elseif(NOT EXISTS "${dependency_target}")
            message(FATAL_ERROR "Missing external dylib dependency for ${macho_file}: ${dependency}")
          endif()

          if(EXISTS "${dependency_target}")
            rewrite_dependency_for_consumer("${macho_file}" "${dependency}" "${runtime_dir}" rewritten)
            if(rewritten)
              set(changed TRUE)
              math(EXPR change_count "${change_count} + 1")
            endif()
          endif()
        elseif(runtime_rpath)
          if(EXISTS "${dependency_target}")
            rewrite_dependency_for_consumer("${macho_file}" "${dependency}" "${runtime_dir}" rewritten)
            if(rewritten)
              set(changed TRUE)
              math(EXPR change_count "${change_count} + 1")
            endif()
          endif()
        endif()
      endforeach()
    endforeach()
    message(STATUS "Dylib dependency rewrite pass ${pass}: ${file_count} Mach-O files, ${change_count} changes.")
    if(NOT changed)
      break()
    endif()
  endforeach()

  normalize_macos_dylib_ids("${runtime_dir}")
  verify_no_external_macos_dylib_dependencies("${runtime_dir}" "${scan_root}")
endfunction()

function(strip_macos_metadata root label)
  if(NOT EXISTS "${root}")
    return()
  endif()
  message(STATUS "Clearing extended attributes and ACLs for ${label} in ${root}...")
  if(XATTR_TOOL)
    run_optional("${XATTR_TOOL}" -cr "${root}")
  endif()
  run_optional("${CHMOD_TOOL}" -RN "${root}")
endfunction()

function(normalize_macho_permissions root label)
  if(NOT EXISTS "${root}")
    return()
  endif()
  message(STATUS "Normalizing executable permissions for ${label} in ${root}...")
  file(GLOB_RECURSE entries LIST_DIRECTORIES true "${root}/*")
  foreach(entry IN LISTS entries)
    if(IS_DIRECTORY "${entry}")
      run_optional("${CHMOD_TOOL}" 755 "${entry}")
    endif()
  endforeach()
  macho_files("${root}" files)
  foreach(path IN LISTS files)
    run_optional("${CHMOD_TOOL}" 755 "${path}")
  endforeach()
endfunction()

function(normalize_app_bundle_permissions app_dir)
  if(NOT EXISTS "${app_dir}")
    return()
  endif()
  message(STATUS "Normalizing app bundle permissions in ${app_dir}...")
  file(GLOB_RECURSE entries LIST_DIRECTORIES true "${app_dir}/*")
  foreach(entry IN LISTS entries)
    if(IS_DIRECTORY "${entry}")
      run_optional("${CHMOD_TOOL}" 755 "${entry}")
    else()
      run_optional("${CHMOD_TOOL}" 644 "${entry}")
    endif()
  endforeach()
  normalize_macho_permissions("${app_dir}" "app bundle Mach-O files")
  if(EXISTS "${app_dir}/Contents/MacOS/elten")
    run_optional("${CHMOD_TOOL}" 755 "${app_dir}/Contents/MacOS/elten")
  endif()
endfunction()

function(codesign_target target use_entitlements)
  if(NOT SIGN)
    return()
  endif()
  set(args --force --timestamp --options runtime)
  if(use_entitlements AND NOT "${ENTITLEMENTS}" STREQUAL "")
    list(APPEND args --entitlements "${ENTITLEMENTS}")
  endif()
  list(APPEND args --sign "${APP_IDENTITY}" "${target}")
  run_checked("${CODESIGN_TOOL}" ${args})
endfunction()

function(codesign_macho_tree root label use_entitlements)
  if(NOT SIGN OR NOT EXISTS "${root}")
    return()
  endif()
  message(STATUS "Signing ${label} in ${root} with secure timestamps...")
  macho_files("${root}" files)
  list(SORT files ORDER DESCENDING)
  foreach(path IN LISTS files)
    message(STATUS "Signing ${path}")
    codesign_target("${path}" "${use_entitlements}")
  endforeach()
endfunction()

function(verify_macho_tree_signatures root label)
  if(NOT SIGN OR NOT EXISTS "${root}")
    return()
  endif()
  message(STATUS "Verifying signatures for ${label} in ${root}...")
  macho_files("${root}" files)
  foreach(path IN LISTS files)
    run_checked("${CODESIGN_TOOL}" --verify --strict "${path}")
  endforeach()
endfunction()

function(sign_app_bundle app_dir)
  if(NOT SIGN)
    return()
  endif()
  message(STATUS "Signing ${app_dir}...")
  verify_macho_tree_signatures("${app_dir}/Contents/Resources/bin/osx" "runtime dylibs and native extensions")
  codesign_macho_tree("${app_dir}/Contents/Frameworks" "frameworks" FALSE)
  codesign_macho_tree("${app_dir}/Contents/MacOS" "launcher executable" TRUE)
  message(STATUS "Signing app bundle with timestamp...")
  codesign_target("${app_dir}" TRUE)
  run_checked("${CODESIGN_TOOL}" --verify --strict --verbose=2 "${app_dir}")
  message(STATUS "App bundle signed.")
endfunction()

function(notary_submit artifact)
  if(NOT SIGN)
    return()
  endif()
  if(NOT "${NOTARY_PROFILE}" STREQUAL "")
    execute_process(
      COMMAND "${XCRUN_TOOL}" notarytool history --keychain-profile "${NOTARY_PROFILE}"
      RESULT_VARIABLE profile_result
      OUTPUT_QUIET
      ERROR_QUIET
    )
    if(profile_result EQUAL 0)
      run_checked_streamed("${XCRUN_TOOL}" notarytool submit "${artifact}" --keychain-profile "${NOTARY_PROFILE}" --wait)
      return()
    endif()
    if("${NOTARY_APPLE_ID}" STREQUAL "" OR "${NOTARY_PASSWORD}" STREQUAL "" OR "${NOTARY_TEAM_ID}" STREQUAL "")
      message(FATAL_ERROR "Notary profile '${NOTARY_PROFILE}' is not configured and Apple ID credentials are incomplete")
    endif()
  endif()
  run_checked_streamed("${XCRUN_TOOL}" notarytool submit "${artifact}" --apple-id "${NOTARY_APPLE_ID}" --password "${NOTARY_PASSWORD}" --team-id "${NOTARY_TEAM_ID}" --wait)
endfunction()

function(notarize_app_bundle app_dir)
  if(NOT SIGN)
    return()
  endif()
  set(zip_path "${DIST_DIR}/Elten.app.zip")
  message(STATUS "Preparing ${zip_path} for notarization...")
  file(REMOVE "${zip_path}")
  run_checked("${DITTO_TOOL}" -c -k --keepParent "${app_dir}" "${zip_path}")
  message(STATUS "Notarizing ${zip_path}...")
  notary_submit("${zip_path}")
  message(STATUS "Stapling ${app_dir}...")
  run_checked("${XCRUN_TOOL}" stapler staple "${app_dir}")
  run_checked("${XCRUN_TOOL}" stapler validate "${app_dir}")
endfunction()

function(write_info_plist plist_path)
  file(WRITE "${plist_path}" [=[<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>pl</string>
  <key>CFBundleExecutable</key>
  <string>elten</string>
  <key>CFBundleIdentifier</key>
  <string>link.elten.elten</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>Elten</string>
  <key>CFBundleDisplayName</key>
  <string>Elten</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>3.0</string>
  <key>CFBundleVersion</key>
  <string>3.0</string>
  <key>LSMinimumSystemVersion</key>
  <string>26.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSMicrophoneUsageDescription</key>
  <string>Elten uses the microphone for voice recording and conferences.</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
]=])
endfunction()

function(write_component_plist plist_path)
  file(WRITE "${plist_path}" [=[<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<array>
  <dict>
    <key>BundleHasStrictIdentifier</key>
    <true/>
    <key>BundleIsRelocatable</key>
    <false/>
    <key>BundleIsVersionChecked</key>
    <false/>
    <key>BundleOverwriteAction</key>
    <string>upgrade</string>
    <key>RootRelativeBundlePath</key>
    <string>Applications/Elten.app</string>
  </dict>
</array>
</plist>
]=])
endfunction()

function(create_app_bundle)
  require_value(RELEASE_ROOT)
  require_value(RUNTIME_DIR)
  require_value(DIST_DIR)
  set(app_dir "${DIST_DIR}/Elten.app")
  set(contents_dir "${app_dir}/Contents")
  set(macos_dir "${contents_dir}/MacOS")
  set(resources_dir "${contents_dir}/Resources")

  if(NOT EXISTS "${RELEASE_ROOT}/elten")
    message(FATAL_ERROR "Missing launcher executable: ${RELEASE_ROOT}/elten")
  endif()

  message(STATUS "Creating ${app_dir}...")
  file(REMOVE_RECURSE "${app_dir}")
  file(MAKE_DIRECTORY "${macos_dir}" "${resources_dir}/bin")
  file(COPY_FILE "${RELEASE_ROOT}/elten" "${macos_dir}/elten")
  run_optional("${CHMOD_TOOL}" 755 "${macos_dir}/elten")
  copy_tree("${RUNTIME_DIR}" "${resources_dir}/bin/osx")
  normalize_macho_permissions("${resources_dir}/bin/osx" "runtime dylibs and native extensions")
  copy_tree("${RELEASE_ROOT}/data" "${resources_dir}/data")
  write_info_plist("${contents_dir}/Info.plist")
  file(WRITE "${contents_dir}/PkgInfo" "APPL????")
  strip_macos_metadata("${app_dir}" "app bundle")
  normalize_app_bundle_permissions("${app_dir}")
  sign_app_bundle("${app_dir}")
  notarize_app_bundle("${app_dir}")
  message(STATUS "Built ${app_dir}")
endfunction()

function(sign_pkg unsigned_pkg signed_pkg)
  message(STATUS "Signing package ${signed_pkg}...")
  run_checked("${PRODUCTSIGN_TOOL}" --sign "${INSTALLER_IDENTITY}" "${unsigned_pkg}" "${signed_pkg}")
  run_checked("${PKGUTIL_TOOL}" --check-signature "${signed_pkg}")
endfunction()

function(notarize_pkg pkg_path)
  if(NOT SIGN)
    return()
  endif()
  message(STATUS "Notarizing ${pkg_path}...")
  notary_submit("${pkg_path}")
  message(STATUS "Stapling ${pkg_path}...")
  run_checked("${XCRUN_TOOL}" stapler staple "${pkg_path}")
  run_checked("${XCRUN_TOOL}" stapler validate "${pkg_path}")
endfunction()

function(create_pkg)
  require_value(DIST_DIR)
  set(app_dir "${DIST_DIR}/Elten.app")
  set(pkg_path "${DIST_DIR}/Elten.pkg")
  set(unsigned_pkg_path "${DIST_DIR}/Elten.unsigned.pkg")
  set(component_plist "${DIST_DIR}/Elten.component.plist")
  set(pkg_root "${DIST_DIR}/pkgroot")

  if(NOT EXISTS "${app_dir}")
    message(FATAL_ERROR "Missing app bundle: ${app_dir}")
  endif()

  message(STATUS "Creating ${pkg_path}...")
  file(REMOVE "${pkg_path}" "${unsigned_pkg_path}" "${component_plist}")
  file(REMOVE_RECURSE "${pkg_root}")
  file(MAKE_DIRECTORY "${pkg_root}/Applications")
  file(COPY "${app_dir}" DESTINATION "${pkg_root}/Applications")
  write_component_plist("${component_plist}")

  if(SIGN)
    run_checked(
      "${PKGBUILD_TOOL}"
      --root "${pkg_root}"
      --component-plist "${component_plist}"
      --install-location "/"
      --identifier "link.elten.elten"
      --version "3.0"
      "${unsigned_pkg_path}"
    )
    sign_pkg("${unsigned_pkg_path}" "${pkg_path}")
    file(REMOVE "${unsigned_pkg_path}")
  else()
    run_checked(
      "${PKGBUILD_TOOL}"
      --root "${pkg_root}"
      --component-plist "${component_plist}"
      --install-location "/"
      --identifier "link.elten.elten"
      --version "3.0"
      "${pkg_path}"
    )
  endif()
  file(REMOVE "${component_plist}")
  file(REMOVE_RECURSE "${pkg_root}")
  run_checked("${PKGUTIL_TOOL}" --payload-files "${pkg_path}")
  notarize_pkg("${pkg_path}")
  message(STATUS "Built ${pkg_path}")
endfunction()

string(TOUPPER "${MODE}" MODE_UPPER)
if(DEFINED SIGN AND ("${SIGN}" STREQUAL "ON" OR "${SIGN}" STREQUAL "1" OR "${SIGN}" STREQUAL "TRUE"))
  set(SIGN TRUE)
else()
  set(SIGN FALSE)
endif()

require_program(FIND_TOOL find)
require_program(OTOOL_TOOL otool)
require_program(INSTALL_NAME_TOOL install_name_tool)
require_program(CHMOD_TOOL chmod)
find_program(XATTR_TOOL xattr)

if(SIGN)
  require_program(CODESIGN_TOOL codesign)
  require_value(APP_IDENTITY)
  if(DEFINED ENTITLEMENTS AND NOT "${ENTITLEMENTS}" STREQUAL "" AND NOT EXISTS "${ENTITLEMENTS}")
    message(FATAL_ERROR "Entitlements file not found: ${ENTITLEMENTS}")
  endif()
endif()

if(MODE_UPPER STREQUAL "FINALIZE_RUNTIME")
  require_value(RUNTIME_DIR)
  require_value(DIST_DIR)
  rewrite_macos_dylib_dependencies("${RUNTIME_DIR}" "${RUNTIME_DIR}")
  strip_macos_metadata("${RUNTIME_DIR}" "release runtime")
  normalize_macho_permissions("${RUNTIME_DIR}" "runtime dylibs and native extensions")
  if(SIGN)
    codesign_macho_tree("${RUNTIME_DIR}" "release runtime dylibs and native extensions" FALSE)
  endif()
elseif(MODE_UPPER STREQUAL "CREATE_APP")
  if(SIGN)
    require_program(XCRUN_TOOL xcrun)
    require_program(DITTO_TOOL ditto)
  endif()
  create_app_bundle()
elseif(MODE_UPPER STREQUAL "CREATE_PKG")
  require_program(PKGBUILD_TOOL pkgbuild)
  require_program(PKGUTIL_TOOL pkgutil)
  if(SIGN)
    require_program(PRODUCTSIGN_TOOL productsign)
    require_program(XCRUN_TOOL xcrun)
    require_value(INSTALLER_IDENTITY)
  endif()
  create_pkg()
else()
  message(FATAL_ERROR "Unsupported MODE: ${MODE}")
endif()
