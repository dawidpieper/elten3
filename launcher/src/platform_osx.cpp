#include "platform.h"

#include <ruby.h>
#include <CoreFoundation/CoreFoundation.h>

#ifdef snprintf
#undef snprintf
#endif

#ifdef vsnprintf
#undef vsnprintf
#endif

#include <mach-o/dyld.h>
#include <mach/mach.h>
#include <mach/thread_act.h>
#include <pthread.h>
#include <unistd.h>

#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <stdexcept>
#include <string>
#include <vector>

namespace fs = std::filesystem;

namespace EltenLauncher {
namespace {

fs::path ExecutablePath() {
  uint32_t size = 0;
  _NSGetExecutablePath(nullptr, &size);
  std::vector<char> buffer(size + 1, '\0');
  if (_NSGetExecutablePath(buffer.data(), &size) != 0) {
    throw std::runtime_error("_NSGetExecutablePath failed");
  }
  std::error_code ec;
  fs::path path = fs::weakly_canonical(buffer.data(), ec);
  return ec ? fs::absolute(buffer.data()) : path;
}

void StampDefineGlobalFunction(const char *name, StampRubyApi::cfunc_1_t func, int arity) {
  if (arity != 1) rb_raise(rb_eArgError, "unsupported get_stamp arity");
  using RubyMethod1 = VALUE (*)(VALUE, VALUE);
  RubyMethod1 method = reinterpret_cast<RubyMethod1>(func);
#if defined(__clang__)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#endif
  rb_define_global_function(name, method, 1);
#if defined(__clang__)
#pragma clang diagnostic pop
#endif
}

RubyValue StampObjIsKindOf(RubyValue value, RubyValue klass) {
  return static_cast<RubyValue>(rb_obj_is_kind_of(static_cast<VALUE>(value), static_cast<VALUE>(klass)));
}

char *StampStringValuePtr(RubyValue *value) {
  VALUE rubyValue = static_cast<VALUE>(*value);
  char *ptr = rb_string_value_ptr(&rubyValue);
  *value = static_cast<RubyValue>(rubyValue);
  return ptr;
}

RubyValue StampFuncallv(RubyValue receiver, uintptr_t methodId, int argc, const RubyValue *argv) {
  std::vector<VALUE> rubyArgs;
  const VALUE *rubyArgv = nullptr;
  if (argc > 0) {
    rubyArgs.reserve(static_cast<std::size_t>(argc));
    for (int i = 0; i < argc; ++i) rubyArgs.push_back(static_cast<VALUE>(argv[i]));
    rubyArgv = rubyArgs.data();
  }
  return static_cast<RubyValue>(
      rb_funcallv(static_cast<VALUE>(receiver), static_cast<ID>(methodId), argc, rubyArgv));
}

long StampNum2Long(RubyValue value) {
  return NUM2LONG(static_cast<VALUE>(value));
}

RubyValue StampLl2Inum(long long value) {
  return static_cast<RubyValue>(LL2NUM(value));
}

} // namespace

fs::path PlatformApplicationRoot() {
  if (const char *env = std::getenv("ELTEN_ROOT")) {
    if (*env != '\0') return fs::absolute(env);
  }

  fs::path dir = ExecutablePath().parent_path();
  if (dir.filename() == "MacOS" && dir.parent_path().filename() == "Contents") {
    fs::path resources = dir.parent_path() / "Resources";
    if (fs::exists(resources)) return resources;
  }
  return dir;
}

std::string PlatformName() {
  return "osx";
}

std::string PlatformNativeExtension() {
  return ".bundle";
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

void PlatformConfigureEnvironment(const fs::path &root, const fs::path &runtimeDir, const fs::path &) {
  setenv("ELTEN_ROOT", root.c_str(), 1);
  setenv("ELTEN_LAUNCHER_EXECUTABLE_PATH", ExecutablePath().c_str(), 1);
  setenv("ELTEN_LAUNCHER_PLATFORM", "osx", 1);
  setenv("ELTEN_LAUNCHER_ARCH", ELTEN_LAUNCHER_ARCH, 1);
  setenv("ELTEN_RUBY_ROOT", runtimeDir.c_str(), 1);
  std::string gemDir = (runtimeDir / "lib" / "ruby" / "gems" / ELTEN_RUBY_API_VERSION).generic_string();
  setenv("GEM_HOME", gemDir.c_str(), 1);
  setenv("GEM_PATH", gemDir.c_str(), 1);

  std::string runtime = runtimeDir.generic_string();
  std::string dyld = runtime;
  if (const char *current = std::getenv("DYLD_LIBRARY_PATH")) {
    if (*current != '\0') dyld += std::string(":") + current;
  }
  setenv("DYLD_LIBRARY_PATH", dyld.c_str(), 1);
  setenv("DYLD_FALLBACK_LIBRARY_PATH", dyld.c_str(), 1);
}

bool PlatformRequiresEarlyEncodingDatabase() {
  return false;
}

bool PlatformSupportsYJIT() {
  return true;
}

RubyApi PlatformLoadRuby(const fs::path &, const fs::path &) {
  RubyApi api;
  api.ruby_sysinit = reinterpret_cast<RubyApi::ruby_sysinit_t>(ruby_sysinit);
  api.ruby_init_stack = reinterpret_cast<RubyApi::ruby_init_stack_t>(ruby_init_stack);
  api.ruby_init = reinterpret_cast<RubyApi::ruby_init_t>(ruby_init);
  api.ruby_init_loadpath = reinterpret_cast<RubyApi::ruby_init_loadpath_t>(ruby_init_loadpath);
  api.ruby_options = reinterpret_cast<RubyApi::ruby_options_t>(ruby_options);
  api.ruby_script = reinterpret_cast<RubyApi::ruby_script_t>(ruby_script);
  api.rb_eval_string_protect = reinterpret_cast<RubyApi::rb_eval_string_protect_t>(rb_eval_string_protect);
  api.ruby_cleanup = reinterpret_cast<RubyApi::ruby_cleanup_t>(ruby_cleanup);
  api.rb_errinfo = reinterpret_cast<RubyApi::rb_errinfo_t>(rb_errinfo);
  api.rb_intern = reinterpret_cast<RubyApi::rb_intern_t>(rb_intern);
  api.rb_funcallv = reinterpret_cast<RubyApi::rb_funcallv_t>(rb_funcallv);
  api.rb_obj_as_string = reinterpret_cast<RubyApi::rb_obj_as_string_t>(rb_obj_as_string);
  api.rb_string_value_cstr = reinterpret_cast<RubyApi::rb_string_value_cstr_t>(rb_string_value_cstr);
  return api;
}

EmbeddedRubyApi PlatformEmbeddedApi(const RubyApi &) {
  EmbeddedRubyApi api;
  api.hash_new = reinterpret_cast<EmbeddedRubyApi::hash_new_t>(rb_hash_new);
  api.ary_new = reinterpret_cast<EmbeddedRubyApi::ary_new_t>(rb_ary_new);
  api.str_new = reinterpret_cast<EmbeddedRubyApi::str_new_t>(rb_str_new);
  api.utf8_str_new = reinterpret_cast<EmbeddedRubyApi::str_new_t>(rb_utf8_str_new);
  api.ary_push = reinterpret_cast<EmbeddedRubyApi::ary_push_t>(rb_ary_push);
  api.hash_aset = reinterpret_cast<EmbeddedRubyApi::hash_aset_t>(rb_hash_aset);
  api.ll2inum = reinterpret_cast<EmbeddedRubyApi::ll2inum_t>(rb_ll2inum);
  api.gv_set = reinterpret_cast<EmbeddedRubyApi::gv_set_t>(rb_gv_set);
  api.gc_register_mark_object = reinterpret_cast<EmbeddedRubyApi::gc_register_mark_object_t>(rb_gc_register_mark_object);
  return api;
}

StampRubyApi PlatformStampApi(const RubyApi &) {
  StampRubyApi api;
  api.define_global_function = StampDefineGlobalFunction;
  api.hash_new = reinterpret_cast<StampRubyApi::hash_new_t>(rb_hash_new);
  api.str_new = reinterpret_cast<StampRubyApi::str_new_t>(rb_str_new);
  api.utf8_str_new = reinterpret_cast<StampRubyApi::str_new_t>(rb_utf8_str_new);
  api.hash_aset = reinterpret_cast<StampRubyApi::hash_aset_t>(rb_hash_aset);
  api.raise = reinterpret_cast<StampRubyApi::raise_t>(rb_raise);
  api.obj_is_kind_of = StampObjIsKindOf;
  api.string_value_ptr = StampStringValuePtr;
  api.intern = reinterpret_cast<StampRubyApi::intern_t>(rb_intern);
  api.funcallv = StampFuncallv;
  api.num2long = StampNum2Long;
  api.ll2inum = StampLl2Inum;
  api.c_string = static_cast<RubyValue>(rb_cString);
  api.e_arg_error = static_cast<RubyValue>(rb_eArgError);
  api.e_runtime_error = static_cast<RubyValue>(rb_eRuntimeError);
  return api;
}

void PlatformShowFatal(const std::string &message) {
  std::fprintf(stderr, "Elten: %s\n", message.c_str());
  CFStringRef title = CFSTR("Elten");
  CFStringRef text = CFStringCreateWithCString(kCFAllocatorDefault, message.c_str(), kCFStringEncodingUTF8);
  if (text != nullptr) {
    CFUserNotificationDisplayAlert(
      0,
      kCFUserNotificationStopAlertLevel,
      nullptr,
      nullptr,
      nullptr,
      title,
      text,
      CFSTR("OK"),
      nullptr,
      nullptr,
      nullptr
    );
    CFRelease(text);
  }
}

void PlatformSuspendOtherThreadsForFatalError() {
  thread_act_array_t threads = nullptr;
  mach_msg_type_number_t threadCount = 0;
  task_t task = mach_task_self();
  if (task_threads(task, &threads, &threadCount) != KERN_SUCCESS) return;

  thread_t currentThread = mach_thread_self();
  thread_t pthreadCurrentThread = pthread_mach_thread_np(pthread_self());
  for (mach_msg_type_number_t i = 0; i < threadCount; ++i) {
    if (threads[i] != currentThread && threads[i] != pthreadCurrentThread) thread_suspend(threads[i]);
    mach_port_deallocate(task, threads[i]);
  }
  mach_port_deallocate(task, currentThread);
  vm_deallocate(task, reinterpret_cast<vm_address_t>(threads), threadCount * sizeof(thread_t));
}

} // namespace EltenLauncher
