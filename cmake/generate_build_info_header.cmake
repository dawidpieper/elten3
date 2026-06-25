if(NOT DEFINED SOURCE_DIR OR SOURCE_DIR STREQUAL "")
  message(FATAL_ERROR "SOURCE_DIR is required")
endif()
if(NOT DEFINED BUILD_INFO_HEADER OR BUILD_INFO_HEADER STREQUAL "")
  message(FATAL_ERROR "BUILD_INFO_HEADER is required")
endif()
if(NOT DEFINED BUILD_ID_FILE OR BUILD_ID_FILE STREQUAL "")
  message(FATAL_ERROR "BUILD_ID_FILE is required")
endif()

set(build_id "${MANUAL_BUILD_ID}")
string(STRIP "${build_id}" build_id)

if(build_id STREQUAL "")
  set(git_dir "${SOURCE_DIR}/.git")
  if(IS_DIRECTORY "${git_dir}")
    find_program(GIT_EXECUTABLE git)
  endif()
  if(GIT_EXECUTABLE)
    execute_process(
      COMMAND "${GIT_EXECUTABLE}" "--git-dir=${git_dir}" rev-parse --verify HEAD
      RESULT_VARIABLE git_result
      OUTPUT_VARIABLE git_output
      ERROR_QUIET
      OUTPUT_STRIP_TRAILING_WHITESPACE
    )
    if(git_result EQUAL 0 AND NOT git_output STREQUAL "")
      set(build_id "${git_output}")
    endif()
  endif()
endif()

if(build_id STREQUAL "")
  string(RANDOM LENGTH 16 ALPHABET "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789" random_suffix)
  set(build_id "UNKNOWN_${random_suffix}")
endif()

string(REGEX REPLACE "[\r\n\t]" "_" build_id "${build_id}")
string(TIMESTAMP build_date "%s")
string(REPLACE "\\" "\\\\" escaped_build_id "${build_id}")
string(REPLACE "\"" "\\\"" escaped_build_id "${escaped_build_id}")

get_filename_component(build_info_dir "${BUILD_INFO_HEADER}" DIRECTORY)
file(MAKE_DIRECTORY "${build_info_dir}")
file(WRITE "${BUILD_INFO_HEADER}" "#pragma once\n\n")
file(APPEND "${BUILD_INFO_HEADER}" "#define ELTEN_BUILD_ID \"${escaped_build_id}\"\n")
file(APPEND "${BUILD_INFO_HEADER}" "#define ELTEN_BUILD_DATE ${build_date}\n")

get_filename_component(build_id_dir "${BUILD_ID_FILE}" DIRECTORY)
file(MAKE_DIRECTORY "${build_id_dir}")
file(WRITE "${BUILD_ID_FILE}" "${build_id}\n")

message(STATUS "Elten build id: ${build_id}")
message(STATUS "Elten build date: ${build_date}")
