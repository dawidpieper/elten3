#pragma once

#include "embedded_assets.hpp"
#include "stamp.hpp"

#include <filesystem>
#include <string>
#include <vector>

namespace EltenLauncher {

struct LauncherDiagnostics {
  std::filesystem::path logPath;
  std::filesystem::path tracePath;
  std::filesystem::path bootstrapPath;
};

struct RubyApi {
  void *library = nullptr;

  using ruby_sysinit_t = void(ELTEN_RUBY_CALL *)(int *, char ***);
  using ruby_init_stack_t = void(ELTEN_RUBY_CALL *)(void *);
  using ruby_init_t = void(ELTEN_RUBY_CALL *)();
  using ruby_init_loadpath_t = void(ELTEN_RUBY_CALL *)();
  using ruby_options_t = void *(ELTEN_RUBY_CALL *)(int, char **);
  using ruby_script_t = void(ELTEN_RUBY_CALL *)(const char *);
  using rb_eval_string_protect_t = RubyValue(ELTEN_RUBY_CALL *)(const char *, int *);
  using ruby_cleanup_t = int(ELTEN_RUBY_CALL *)(int);
  using rb_errinfo_t = RubyValue(ELTEN_RUBY_CALL *)();
  using rb_intern_t = uintptr_t(ELTEN_RUBY_CALL *)(const char *);
  using rb_funcallv_t = RubyValue(ELTEN_RUBY_CALL *)(RubyValue, uintptr_t, int, const RubyValue *);
  using rb_obj_as_string_t = RubyValue(ELTEN_RUBY_CALL *)(RubyValue);
  using rb_string_value_cstr_t = char *(ELTEN_RUBY_CALL *)(RubyValue *);

  ruby_sysinit_t ruby_sysinit = nullptr;
  ruby_init_stack_t ruby_init_stack = nullptr;
  ruby_init_t ruby_init = nullptr;
  ruby_init_loadpath_t ruby_init_loadpath = nullptr;
  ruby_options_t ruby_options = nullptr;
  ruby_script_t ruby_script = nullptr;
  rb_eval_string_protect_t rb_eval_string_protect = nullptr;
  ruby_cleanup_t ruby_cleanup = nullptr;
  rb_errinfo_t rb_errinfo = nullptr;
  rb_intern_t rb_intern = nullptr;
  rb_funcallv_t rb_funcallv = nullptr;
  rb_obj_as_string_t rb_obj_as_string = nullptr;
  rb_string_value_cstr_t rb_string_value_cstr = nullptr;
};

std::filesystem::path PlatformApplicationRoot();
std::string PlatformName();
std::string PlatformNativeExtension();
std::filesystem::path PlatformPathFromUtf8(const std::string &value);
std::string PlatformPathToUtf8(const std::filesystem::path &path);
std::vector<std::string> PlatformCommandLineArguments(int argc, char **argv);
void PlatformConfigureEnvironment(const std::filesystem::path &root,
                                  const std::filesystem::path &runtimeDir,
                                  const std::filesystem::path &fallbackRubyRoot);
bool PlatformRequiresEarlyEncodingDatabase();
bool PlatformSupportsYJIT();
RubyApi PlatformLoadRuby(const std::filesystem::path &runtimeDir,
                         const std::filesystem::path &fallbackRubyRoot);
EmbeddedRubyApi PlatformEmbeddedApi(const RubyApi &ruby);
StampRubyApi PlatformStampApi(const RubyApi &ruby);
void PlatformSuspendOtherThreadsForFatalError();
void PlatformShowFatal(const std::string &message);

} // namespace EltenLauncher
