#include "platform.h"

#include <dlfcn.h>
#include <limits.h>
#include <spawn.h>
#include <sys/wait.h>
#include <unistd.h>

#include <cerrno>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <ctime>
#include <filesystem>
#include <fstream>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

extern char **environ;

namespace fs = std::filesystem;

namespace EltenLauncher {
namespace {

fs::path ExecutablePath() {
  // readlink() does not report truncation: when the target does not fit it just
  // fills the buffer and returns its size, silently yielding a cut-off path.
  // The kernel renders /proc/self/exe into a PAGE_SIZE buffer, so this can only
  // bite where PAGE_SIZE > PATH_MAX - notably arm64 kernels built with 64K pages,
  // one of our target architectures (a longer path fails with ENAMETOOLONG
  // instead, which the length check below catches). Grow until it fits, the way
  // the Windows launcher loops on GetModuleFileNameW and macOS asks
  // _NSGetExecutablePath for the exact size first.
  std::vector<char> buffer(PATH_MAX + 1, '\0');
  while (true) {
    ssize_t length = readlink("/proc/self/exe", buffer.data(), buffer.size());
    if (length <= 0) throw std::runtime_error("readlink(/proc/self/exe) failed");
    if (static_cast<std::size_t>(length) < buffer.size()) {
      buffer[static_cast<std::size_t>(length)] = '\0';
      break;
    }
    if (buffer.size() >= (static_cast<std::size_t>(1) << 20)) {
      throw std::runtime_error("/proc/self/exe target is unreasonably long");
    }
    buffer.assign(buffer.size() * 2, '\0');
  }
  std::error_code ec;
  fs::path path = fs::weakly_canonical(buffer.data(), ec);
  return ec ? fs::absolute(buffer.data()) : path;
}

void PrependPathList(const char *key, const fs::path &entry) {
  std::string value = entry.generic_string();
  if (const char *current = std::getenv(key)) {
    if (*current != '\0') {
      std::string existing(current);
      if (existing == value || existing.rfind(value + ":", 0) == 0 ||
          existing.find(":" + value + ":") != std::string::npos ||
          (existing.size() > value.size() &&
           existing.compare(existing.size() - value.size() - 1, std::string::npos, ":" + value) == 0)) {
        return;
      }
      value += ":";
      value += existing;
    }
  }
  setenv(key, value.c_str(), 1);
}

template <typename T>
T RequiredSym(void *library, const char *name) {
  void *symbol = dlsym(library, name);
  if (symbol == nullptr) {
    std::ostringstream stream;
    stream << "Ruby export not found: " << name;
    throw std::runtime_error(stream.str());
  }
  return reinterpret_cast<T>(symbol);
}

template <typename T>
T OptionalSym(void *library, const char *name) {
  return reinterpret_cast<T>(dlsym(library, name));
}

std::string FatalTimestamp() {
  std::time_t now = std::time(nullptr);
  std::tm parts = {};
  localtime_r(&now, &parts);
  char buffer[64] = {};
  std::strftime(buffer, sizeof(buffer), "%Y-%m-%d %H:%M:%S", &parts);
  return buffer;
}

fs::path FatalLogPath() {
  // Same base as EltenSystemHelpers.appdata_dir, so this lands next to elten.log.
  fs::path base;
  if (const char *xdg = std::getenv("XDG_DATA_HOME")) {
    if (*xdg != '\0') base = fs::path(xdg);
  }
  if (base.empty()) {
    const char *home = std::getenv("HOME");
    if (home == nullptr || *home == '\0') return {};
    base = fs::path(home) / ".local" / "share";
  }
  return base / "elten" / "launcher-fatal.log";
}

// The desktop entry runs with Terminal=false and --launcher-log is opt-in, so
// stderr goes nowhere for a menu launch. Always leave a copy on disk, otherwise
// a failure with no dialog available is completely silent.
void WriteFatalFallbackLog(const std::string &message) {
  try {
    fs::path path = FatalLogPath();
    if (path.empty()) return;
    std::error_code ec;
    fs::create_directories(path.parent_path(), ec);
    if (ec) return;
    std::ofstream file(path, std::ios::binary | std::ios::app);
    if (!file) return;
    file << FatalTimestamp() << "\n" << message << "\n";
  } catch (...) {
  }
}

// Runs a dialog helper to completion; returns false only when the helper is not
// installed, so the caller can fall through to the next one.
//
// Prefer posix_spawn over fork() + exec() here. The fatal path also runs on the
// runtime-integrity thread while Ruby threads are live, and POSIX only allows
// async-signal-safe calls between fork() and exec() in a multithreaded process -
// so building the argv there (a std::string concatenation, hence malloc) is
// formally out of contract. glibc does make its own malloc fork-safe, which is
// why the fork() version did not hang in practice, but posix_spawn sidesteps the
// whole class: no pthread_atfork handlers from anything else loaded in-process,
// and no dependency on the allocator being fork-hardened. Every argument is
// therefore built here, in the parent.
bool RunFatalDialog(std::vector<std::string> args) {
  if (args.empty()) return false;
  std::vector<char *> argv;
  argv.reserve(args.size() + 1);
  for (std::string &arg : args) argv.push_back(arg.data());
  argv.push_back(nullptr);

  pid_t pid = 0;
  if (posix_spawnp(&pid, argv[0], nullptr, nullptr, argv.data(), environ) != 0) return false;
  int status = 0;
  while (waitpid(pid, &status, 0) < 0) {
    // The helper did start, so treat an unreapable child as shown rather than
    // opening a second dialog on top of it.
    if (errno != EINTR) return true;
  }
  // Some C libraries report a failed exec as exit status 127 instead of failing
  // posix_spawnp itself; both mean "helper not installed".
  return !(WIFEXITED(status) && WEXITSTATUS(status) == 127);
}

RubyValue EvalRubyExpression(const RubyApi &ruby, const char *expression) {
  int state = 0;
  RubyValue value = ruby.rb_eval_string_protect(expression, &state);
  if (state != 0) {
    throw std::runtime_error(std::string("Cannot resolve Ruby expression for get_stamp: ") + expression);
  }
  return value;
}

} // namespace

fs::path PlatformApplicationRoot() {
  if (const char *env = std::getenv("ELTEN_ROOT")) {
    if (*env != '\0') return fs::absolute(env);
  }

  fs::path dir = ExecutablePath().parent_path();
  if ((dir.filename() == "linux-x64" || dir.filename() == "linux-arm64") &&
      dir.parent_path().filename() == "bin") {
    return dir.parent_path().parent_path();
  }
  return dir;
}

std::string PlatformName() {
  return "linux";
}

std::string PlatformNativeExtension() {
  return ".so";
}

fs::path PlatformPathFromUtf8(const std::string &value) {
  return fs::path(value);
}

std::string PlatformPathToUtf8(const fs::path &path) {
  return path.generic_string();
}

std::vector<std::string> PlatformCommandLineArguments(int argc, char **argv) {
  std::vector<std::string> args;
  args.reserve(argc > 0 ? static_cast<std::size_t>(argc) : 0);
  for (int i = 0; i < argc; ++i) args.emplace_back(argv[i] == nullptr ? "" : argv[i]);
  return args;
}

void PlatformConfigureEnvironment(const fs::path &root, const fs::path &runtimeDir, const fs::path &fallbackRubyRoot) {
  setenv("ELTEN_ROOT", root.c_str(), 1);
  setenv("ELTEN_LAUNCHER_EXECUTABLE_PATH", ExecutablePath().c_str(), 1);
  setenv("ELTEN_LAUNCHER_PLATFORM", "linux", 1);
  setenv("ELTEN_LAUNCHER_ARCH", ELTEN_LAUNCHER_ARCH, 1);
  setenv("ELTEN_RUBY_ROOT", runtimeDir.c_str(), 1);
  std::string gemDir = (runtimeDir / "lib" / "ruby" / "gems" / ELTEN_RUBY_API_VERSION).generic_string();
  setenv("GEM_HOME", gemDir.c_str(), 1);
  setenv("GEM_PATH", gemDir.c_str(), 1);

  // NB: this reaches child processes only. glibc's loader builds its search path
  // once at process start, so setenv() here does NOT affect dlopen() in this
  // process (verified: after setenv, dlopen by soname still fails while an
  // absolute path resolves). That is fine, because everything loaded in-process
  // is opened by absolute path - libruby in PlatformLoadRuby below, and the BASS
  // family via EltenRuntimePaths/EltenSystemHelpers, which additionally preloads
  // inter-library dependencies with RTLD_GLOBAL. Making it apply in-process would
  // mean re-exec'ing ourselves, the way elten.rb's configure_linux_ld! does when
  // Elten runs from source.
  PrependPathList("LD_LIBRARY_PATH", runtimeDir);
  fs::path fallbackLib = fallbackRubyRoot / "lib";
  if (fs::exists(fallbackLib)) PrependPathList("LD_LIBRARY_PATH", fallbackLib);
}

bool PlatformRequiresEarlyEncodingDatabase() {
  // Like macOS, and unlike RubyInstaller on Windows: our Ruby is built from
  // source and already has its encodings registered by the time ruby_init()
  // returns, so requiring enc/encdb here would only load it a second time and
  // spray "already initialized constant Encoding::..." over stderr (the
  // bootstrap script still requires it, guarded, for the transcoding tables).
  return false;
}

bool PlatformSupportsYJIT() {
  // Like macOS: the runtime is built with --enable-yjit, so the launcher passes
  // --yjit and VerifyYJITEnabled holds the build to it. Windows stays false
  // because RubyInstaller does not ship YJIT.
  return true;
}

RubyApi PlatformLoadRuby(const fs::path &runtimeDir, const fs::path &fallbackRubyRoot) {
  std::vector<fs::path> candidates = {
      runtimeDir / ELTEN_RUBY_DLL_NAME,
      fallbackRubyRoot / "lib" / ELTEN_RUBY_DLL_NAME,
  };
  void *library = nullptr;
  std::ostringstream errors;
  for (const auto &candidate : candidates) {
    if (!fs::exists(candidate)) {
      errors << "  " << PlatformPathToUtf8(candidate) << ": file not found\n";
      continue;
    }
    // RTLD_GLOBAL: native gem extensions leave Ruby symbols undefined and
    // resolve them from the process-global namespace at dlopen time.
    library = dlopen(candidate.c_str(), RTLD_NOW | RTLD_GLOBAL);
    if (library != nullptr) break;
    const char *message = dlerror();
    errors << "  " << PlatformPathToUtf8(candidate) << ": " << (message == nullptr ? "dlopen failed" : message)
           << "\n";
  }
  if (library == nullptr) {
    throw std::runtime_error("Cannot load Ruby shared library:\n" + errors.str());
  }

  RubyApi api;
  api.library = library;
  api.ruby_sysinit = RequiredSym<RubyApi::ruby_sysinit_t>(library, "ruby_sysinit");
  api.ruby_init_stack = OptionalSym<RubyApi::ruby_init_stack_t>(library, "ruby_init_stack");
  api.ruby_init = RequiredSym<RubyApi::ruby_init_t>(library, "ruby_init");
  api.ruby_init_loadpath = RequiredSym<RubyApi::ruby_init_loadpath_t>(library, "ruby_init_loadpath");
  api.ruby_options = OptionalSym<RubyApi::ruby_options_t>(library, "ruby_options");
  api.ruby_script = RequiredSym<RubyApi::ruby_script_t>(library, "ruby_script");
  api.rb_eval_string_protect = RequiredSym<RubyApi::rb_eval_string_protect_t>(library, "rb_eval_string_protect");
  api.ruby_cleanup = RequiredSym<RubyApi::ruby_cleanup_t>(library, "ruby_cleanup");
  api.rb_errinfo = OptionalSym<RubyApi::rb_errinfo_t>(library, "rb_errinfo");
  api.rb_intern = OptionalSym<RubyApi::rb_intern_t>(library, "rb_intern");
  api.rb_funcallv = OptionalSym<RubyApi::rb_funcallv_t>(library, "rb_funcallv");
  api.rb_obj_as_string = OptionalSym<RubyApi::rb_obj_as_string_t>(library, "rb_obj_as_string");
  api.rb_string_value_cstr = OptionalSym<RubyApi::rb_string_value_cstr_t>(library, "rb_string_value_cstr");
  return api;
}

EmbeddedRubyApi PlatformEmbeddedApi(const RubyApi &ruby) {
  void *library = ruby.library;
  EmbeddedRubyApi api;
  api.hash_new = RequiredSym<EmbeddedRubyApi::hash_new_t>(library, "rb_hash_new");
  api.ary_new = RequiredSym<EmbeddedRubyApi::ary_new_t>(library, "rb_ary_new");
  api.str_new = RequiredSym<EmbeddedRubyApi::str_new_t>(library, "rb_str_new");
  api.utf8_str_new = OptionalSym<EmbeddedRubyApi::str_new_t>(library, "rb_utf8_str_new");
  api.ary_push = RequiredSym<EmbeddedRubyApi::ary_push_t>(library, "rb_ary_push");
  api.hash_aset = RequiredSym<EmbeddedRubyApi::hash_aset_t>(library, "rb_hash_aset");
  api.ll2inum = RequiredSym<EmbeddedRubyApi::ll2inum_t>(library, "rb_ll2inum");
  api.gv_set = RequiredSym<EmbeddedRubyApi::gv_set_t>(library, "rb_gv_set");
  api.gc_register_mark_object = OptionalSym<EmbeddedRubyApi::gc_register_mark_object_t>(
      library, "rb_gc_register_mark_object");
  return api;
}

StampRubyApi PlatformStampApi(const RubyApi &ruby) {
  void *library = ruby.library;
  StampRubyApi api;
  api.define_global_function = RequiredSym<StampRubyApi::define_global_function_t>(library, "rb_define_global_function");
  api.hash_new = RequiredSym<StampRubyApi::hash_new_t>(library, "rb_hash_new");
  api.str_new = RequiredSym<StampRubyApi::str_new_t>(library, "rb_str_new");
  api.utf8_str_new = OptionalSym<StampRubyApi::str_new_t>(library, "rb_utf8_str_new");
  api.hash_aset = RequiredSym<StampRubyApi::hash_aset_t>(library, "rb_hash_aset");
  api.raise = RequiredSym<StampRubyApi::raise_t>(library, "rb_raise");
  api.obj_is_kind_of = RequiredSym<StampRubyApi::obj_is_kind_of_t>(library, "rb_obj_is_kind_of");
  api.string_value_ptr = RequiredSym<StampRubyApi::string_value_ptr_t>(library, "rb_string_value_ptr");
  api.intern = RequiredSym<StampRubyApi::intern_t>(library, "rb_intern");
  api.funcallv = RequiredSym<StampRubyApi::funcallv_t>(library, "rb_funcallv");
  api.num2long = RequiredSym<StampRubyApi::num2long_t>(library, "rb_num2long");
  api.ll2inum = RequiredSym<StampRubyApi::ll2inum_t>(library, "rb_ll2inum");
  api.c_string = EvalRubyExpression(ruby, "String");
  api.e_arg_error = EvalRubyExpression(ruby, "ArgumentError");
  api.e_runtime_error = EvalRubyExpression(ruby, "RuntimeError");
  return api;
}

void PlatformShowFatal(const std::string &message) {
  std::fprintf(stderr, "Elten: %s\n", message.c_str());
  WriteFatalFallbackLog(message);

  // zenity draws a GTK dialog that AT-SPI screen readers announce, and it is a
  // package dependency - but unlike MessageBoxW / CFUserNotificationDisplayAlert
  // it is still an external binary, so keep xmessage as a last resort. Arguments
  // are passed as separate argv entries, so the message never reaches a shell.
  // xmessage takes its text positionally and has no title bar of its own, hence
  // the prefix - which also stops a message starting with '-' from being parsed
  // as an option.
  if (RunFatalDialog({"zenity", "--error", "--title=Elten", "--text=" + message, "--no-wrap"})) return;
  RunFatalDialog({"xmessage", "-center", "Elten: " + message});
}

void PlatformSuspendOtherThreadsForFatalError() {
  // Linux has no public API to suspend arbitrary threads of the current
  // process (macOS uses thread_suspend, Windows SuspendThread). The fatal
  // path only reports and exits, so this is a no-op here.
}

} // namespace EltenLauncher
