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

# Both tools are required, not optional. Without ldd nothing is bundled, and
# without patchelf the objects keep the RUNPATH the Ruby build gave them - an
# absolute path into the build tree. glibc then ignores the launcher's DT_RPATH
# for them, so on any machine but the build host libruby and the extensions
# fail with "cannot open shared object file" for libcrypt, libssl, libffi and
# the like. A warning in the build log is too easy to miss for a release that
# only works on the machine that built it, so refuse to go on instead.
find_program(LDD_EXECUTABLE ldd)
if(NOT LDD_EXECUTABLE)
  message(FATAL_ERROR "ldd was not found; it is required to bundle the runtime's shared libraries")
endif()
find_program(PATCHELF_EXECUTABLE patchelf)
if(NOT PATCHELF_EXECUTABLE)
  message(FATAL_ERROR
    "patchelf was not found; it is required so the packaged runtime finds its "
    "bundled libraries instead of looking for them on the build host's paths. "
    "Install patchelf from your distribution and build again.")
endif()

# True when the file starts with the ELF magic. The globs below also match
# things that only look like libraries by name, which are not ours to patch.
function(elten_is_elf path out_var)
  file(READ "${path}" magic LIMIT 4 HEX)
  if(magic STREQUAL "7f454c46")
    set(${out_var} TRUE PARENT_SCOPE)
  else()
    set(${out_var} FALSE PARENT_SCOPE)
  endif()
endfunction()

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

# Sonames the package already carries, stored in bin under exactly these names so
# that everything in the process - including the audio server's libsndfile, which
# searches LD_LIBRARY_PATH before its own RUNPATH - resolves to our copy. Copying
# the host's file in beside ours would put a second, differently versioned library
# under a name only one of the two can hold, so those are skipped below.
#
# Renaming our sonames to something private was tried and reverted: measured in a
# Debian container, it guarantees the distribution loads its own copy alongside
# ours, and two versions of libopus in one process segfault inside
# opus_encoder_create. One copy shared by everyone is what works.
set(COLLIDING_SONAMES
  "libogg.so.0"
  "libopus.so.0"
  "libvorbis.so.0"
  "libvorbisenc.so.2"
  "libspeexdsp.so.1"
  "libzstd.so.1"
  "liblzma.so.5"
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

    # We ship this one ourselves and rename it below so that nothing outside the
    # package can pick it up. Copying the host's versioned file in beside ours
    # would undo that in the same run: the runtime directory is on
    # LD_LIBRARY_PATH, so the system's libsndfile would find a file answering to
    # the colliding name right here and go back to mixing the build host's
    # codecs into the machine's audio stack.
    if(soname IN_LIST COLLIDING_SONAMES)
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

# Point every object at the runtime root, so it finds the copies above.
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
# Extensions are stored under their require path, so they can sit any number of
# levels below the root (enc/, digest/, json/ext/...) while the shared libraries
# stay in the root itself. Each object therefore gets $ORIGIN plus the exact
# relative path back up to the root; a fixed $ORIGIN/.. stops one level short
# for json/ext/parser.so and anything else nested deeper.
#
# Re-glob: the copies made above are new files that need the same treatment,
# since they depend on each other (libssl on libcrypto, brotli on brotlicommon).
# The pattern has to reach past ".so": those copies are named after their soname,
# so they end in ".so.3" and the like. Missed here, a bundled libssl carries no
# RUNPATH and looks for its libcrypto in system directories - pairing our copy of
# one with the host's copy of the other, which is the mismatch this file exists
# to prevent.
file(GLOB_RECURSE patch_targets "${RUNTIME_DIR}/*.so*")

set(patched 0)
set(runtime_objects "")
foreach(object ${patch_targets})
  elten_is_elf("${object}" is_elf)
  if(NOT is_elf)
    continue()
  endif()
  list(APPEND runtime_objects "${object}")

  get_filename_component(object_dir "${object}" DIRECTORY)
  file(RELATIVE_PATH relative_dir "${RUNTIME_DIR}" "${object_dir}")
  set(rpath "$ORIGIN")
  if(NOT relative_dir STREQUAL "")
    string(REGEX REPLACE "[^/]+" ".." up_to_root "${relative_dir}")
    string(APPEND rpath ":$ORIGIN/${up_to_root}")
  endif()

  execute_process(
    COMMAND "${PATCHELF_EXECUTABLE}" --set-rpath "${rpath}" "${object}"
    RESULT_VARIABLE patch_result
    ERROR_VARIABLE patch_error
  )
  if(NOT patch_result EQUAL 0)
    message(FATAL_ERROR "Cannot set RUNPATH on ${object}: ${patch_error}")
  endif()
  math(EXPR patched "${patched} + 1")
endforeach()
message(STATUS "Set RUNPATH on ${patched} runtime objects")

# Check the result the way the user's loader will see it: every library an
# object asks for must either be one of the C runtime libraries excluded above,
# which every system has, or be present in the runtime root under the name the
# loader looks for. Anything else is a "cannot open shared object file" waiting
# on a machine that happens not to have it - for instance when ldd could not
# inspect a cross-built object, or when a soname from COLLIDING_SONAMES is not
# actually shipped in bin/ for this architecture.
set(provided_sonames "")
foreach(object ${runtime_objects})
  execute_process(
    COMMAND "${PATCHELF_EXECUTABLE}" --print-soname "${object}"
    OUTPUT_VARIABLE object_soname
    OUTPUT_STRIP_TRAILING_WHITESPACE
    RESULT_VARIABLE soname_result
    ERROR_QUIET
  )
  if(soname_result EQUAL 0 AND NOT object_soname STREQUAL "")
    list(APPEND provided_sonames "${object_soname}")
  endif()
endforeach()

set(unresolved "")
foreach(object ${runtime_objects})
  execute_process(
    COMMAND "${PATCHELF_EXECUTABLE}" --print-needed "${object}"
    OUTPUT_VARIABLE needed_output
    RESULT_VARIABLE needed_result
    ERROR_VARIABLE needed_error
  )
  if(NOT needed_result EQUAL 0)
    message(FATAL_ERROR "Cannot read the dependencies of ${object}: ${needed_error}")
  endif()
  string(REPLACE "\n" ";" needed_list "${needed_output}")
  foreach(needed ${needed_list})
    if(needed STREQUAL "")
      continue()
    endif()
    set(excluded FALSE)
    foreach(pattern ${EXCLUDED_PATTERNS})
      if(needed MATCHES "${pattern}")
        set(excluded TRUE)
        break()
      endif()
    endforeach()
    if(excluded OR EXISTS "${RUNTIME_DIR}/${needed}" OR needed IN_LIST provided_sonames)
      continue()
    endif()
    file(RELATIVE_PATH relative_object "${RUNTIME_DIR}" "${object}")
    list(APPEND unresolved "${relative_object} needs ${needed}")
  endforeach()
endforeach()

if(unresolved)
  list(JOIN unresolved "\n  " unresolved_text)
  message(FATAL_ERROR
    "The packaged runtime depends on libraries it does not ship:\n  ${unresolved_text}\n"
    "Build on a host where ldd can inspect these objects (a matching architecture "
    "or a working cross-loader), or add the missing libraries to bin/ for this "
    "architecture.")
endif()
message(STATUS "Verified the dependencies of ${patched} runtime objects")
