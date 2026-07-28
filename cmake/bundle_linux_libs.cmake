cmake_minimum_required(VERSION 3.24)

# Copies the shared libraries that the packaged Ruby runtime pulls in from the
# build host into the runtime directory, so the release does not depend on the
# target machine happening to have compatible versions.
#
# Why this is needed at all: on Windows the same job is done by RubyInstaller's
# ruby_builtin_dlls, which the asset generator copies wholesale. Linux gems link
# against system libraries instead of shipping their own, so nothing sits next to
# the extensions to copy - and without this step a build made on, say, Arch
# expects OpenSSL 3 and libxcrypt on the user's machine. Where it is missing, the
# openssl extension simply fails to load and Elten cannot reach the server at all.
#
# The launcher is linked with an inherited DT_RPATH pointing here, which is what
# makes the copies findable - see the comment on that in CMakeLists.txt.

# Runs BETWEEN the two asset-generator passes: after the --prepare-only pass has
# copied the gem extensions into RUNTIME_DIR (and BASS has been copied in beside
# them), but before the --no-copy-runtime-assets pass records a digest of every
# runtime file. It must stay in that window: the launcher verifies those digests
# at startup, so patchelf rewriting the files after the embed pass would turn
# into "integrity check failed: modified package file" on the user's machine,
# while doing it before the embed pass means the digests match what ships.
#
# Everything to touch is therefore already in RUNTIME_DIR; nothing is read from
# the Ruby build tree here.
if(NOT DEFINED RUNTIME_DIR OR NOT IS_DIRECTORY "${RUNTIME_DIR}")
  message(FATAL_ERROR "RUNTIME_DIR is required and must exist: ${RUNTIME_DIR}")
endif()

find_program(LDD_EXECUTABLE ldd)
if(NOT LDD_EXECUTABLE)
  message(WARNING "ldd was not found; skipping runtime library bundling")
  return()
endif()

# Never bundle these. They are the C runtime and its companions: the loader
# itself cannot be replaced from inside the process, and shipping a libc that
# disagrees with the host's loader breaks far more than it fixes. Every system
# that can run the binary at all already has them.
set(EXCLUDED_PATTERNS
  "^ld-linux"
  "^libc\\.so"
  "^libm\\.so"
  "^libdl\\.so"
  "^libpthread\\.so"
  "^librt\\.so"
  "^libutil\\.so"
  "^libnsl\\.so"
  "^libresolv\\.so"
  # libstdc++/libgcc are deliberately left out too: the launcher is compiled
  # against the build host's version, and mixing a bundled one with libraries
  # the host loads later is a known source of hard-to-read crashes. If releases
  # ever need to run on distributions older than the build host, the right fix
  # is building on an older baseline rather than shipping these.
  "^libstdc\\+\\+\\.so"
  "^libgcc_s\\.so"
)

# Everything already staged in the package: the gem extensions the prepare-only
# pass copied here, plus BASS and libruby copied in beside them.
file(GLOB_RECURSE runtime_objects "${RUNTIME_DIR}/*.so")
set(copied 0)
set(seen "")

foreach(object ${runtime_objects})
  execute_process(
    COMMAND "${LDD_EXECUTABLE}" "${object}"
    OUTPUT_VARIABLE ldd_output
    ERROR_QUIET
    RESULT_VARIABLE ldd_result
  )
  if(NOT ldd_result EQUAL 0)
    continue()
  endif()

  string(REPLACE "\n" ";" ldd_lines "${ldd_output}")
  foreach(line ${ldd_lines})
    # "	libssl.so.3 => /usr/lib/libssl.so.3 (0x00007f...)"
    if(NOT line MATCHES "^[ \t]*([^ \t]+) => (/[^ ]+)")
      continue()
    endif()
    set(soname "${CMAKE_MATCH_1}")
    set(resolved "${CMAKE_MATCH_2}")

    # Already part of the package - that includes everything copied by an
    # earlier pass, so re-running is a no-op.
    string(FIND "${resolved}" "${RUNTIME_DIR}" inside)
    if(inside EQUAL 0)
      continue()
    endif()

    set(excluded FALSE)
    foreach(pattern ${EXCLUDED_PATTERNS})
      if(soname MATCHES "${pattern}")
        set(excluded TRUE)
        break()
      endif()
    endforeach()
    if(excluded)
      continue()
    endif()

    if(soname IN_LIST seen)
      continue()
    endif()
    list(APPEND seen "${soname}")

    # ldd reports the soname on the left and whatever it resolved to on the
    # right, which is usually a symlink; copy the real file but keep the soname
    # as the file name, because that is what the dependent objects ask for.
    get_filename_component(real_path "${resolved}" REALPATH)
    if(NOT EXISTS "${real_path}")
      continue()
    endif()
    file(COPY_FILE "${real_path}" "${RUNTIME_DIR}/${soname}" ONLY_IF_DIFFERENT RESULT copy_result)
    if(copy_result)
      message(WARNING "Cannot bundle ${soname} from ${real_path}: ${copy_result}")
      continue()
    endif()
    math(EXPR copied "${copied} + 1")
  endforeach()
endforeach()

list(LENGTH seen seen_count)
message(STATUS "Bundled ${copied} host libraries into ${RUNTIME_DIR} (${seen_count} distinct sonames)")

# Point every object at the directory it sits in, so it finds the copies above.
#
# This has to be done here, with patchelf, rather than through LDFLAGS while
# Ruby is built: $ORIGIN cannot survive that route intact, and it is mangled
# differently by each sub-build - make expands $O as a variable and leaves
# "RIGIN", mkmf drops it altogether. patchelf writes the string into the ELF
# directly, with no shell in between.
#
# And it has to be on the objects themselves rather than only on the launcher:
# glibc ignores an inherited DT_RPATH for any object carrying its own
# DT_RUNPATH, and everything the Ruby build produces carries one.
#
# $ORIGIN/.. is included for extensions that live a level down (enc/, json/...)
# while the shared libraries stay in the runtime root.
find_program(PATCHELF_EXECUTABLE patchelf)
if(NOT PATCHELF_EXECUTABLE)
  message(WARNING
    "patchelf was not found; the packaged runtime will keep looking for its "
    "libraries in system directories instead of the bundled copies")
  return()
endif()

# Re-glob: the copies made above are new files that need the same treatment,
# since they depend on each other (libssl on libcrypto, brotli on brotlicommon).
file(GLOB_RECURSE patch_targets "${RUNTIME_DIR}/*.so")

set(patched 0)
foreach(object ${patch_targets})
  execute_process(
    COMMAND "${PATCHELF_EXECUTABLE}" --set-rpath "$ORIGIN:$ORIGIN/.." "${object}"
    RESULT_VARIABLE patch_result
    ERROR_VARIABLE patch_error
  )
  if(patch_result EQUAL 0)
    math(EXPR patched "${patched} + 1")
  else()
    message(WARNING "Cannot set RUNPATH on ${object}: ${patch_error}")
  endif()
endforeach()
message(STATUS "Set RUNPATH on ${patched} runtime objects")
