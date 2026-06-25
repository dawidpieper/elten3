#include "platform.h"

#include <windows.h>
#include <shellapi.h>
#include <tlhelp32.h>

#include <filesystem>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

namespace fs = std::filesystem;

namespace EltenLauncher {
namespace {

std::wstring Utf8ToWide(const std::string &value) {
  if (value.empty()) return L"";
  int size = MultiByteToWideChar(CP_UTF8, 0, value.data(), static_cast<int>(value.size()), nullptr, 0);
  std::wstring result(size, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, value.data(), static_cast<int>(value.size()), result.data(), size);
  return result;
}

std::string WideToUtf8(const std::wstring &value) {
  if (value.empty()) return "";
  int size = WideCharToMultiByte(CP_UTF8, 0, value.data(), static_cast<int>(value.size()), nullptr, 0, nullptr, nullptr);
  std::string result(size, '\0');
  WideCharToMultiByte(CP_UTF8, 0, value.data(), static_cast<int>(value.size()), result.data(), size, nullptr, nullptr);
  return result;
}

fs::path ExecutablePath() {
  std::wstring buffer(MAX_PATH, L'\0');
  DWORD length = 0;
  while (true) {
    length = GetModuleFileNameW(nullptr, buffer.data(), static_cast<DWORD>(buffer.size()));
    if (length == 0) throw std::runtime_error("GetModuleFileNameW failed");
    if (length < buffer.size() - 1) {
      buffer.resize(length);
      return fs::path(buffer);
    }
    buffer.resize(buffer.size() * 2);
  }
}

bool SameName(const fs::path &path, const wchar_t *name) {
  return _wcsicmp(path.filename().c_str(), name) == 0;
}

void AppendPathEnvironment(const std::vector<fs::path> &paths) {
  std::wstring current;
  DWORD needed = GetEnvironmentVariableW(L"PATH", nullptr, 0);
  if (needed > 0) {
    current.resize(needed - 1);
    GetEnvironmentVariableW(L"PATH", current.data(), needed);
  }

  std::wstring merged;
  for (const auto &path : paths) {
    if (!fs::exists(path)) continue;
    if (!merged.empty()) merged += L";";
    merged += path.wstring();
  }
  if (!current.empty()) {
    if (!merged.empty()) merged += L";";
    merged += current;
  }
  SetEnvironmentVariableW(L"PATH", merged.c_str());
}

void AddDllDirectoryCompat(const fs::path &path) {
  if (!fs::exists(path)) return;
  HMODULE kernel32 = GetModuleHandleW(L"kernel32.dll");
  using add_dll_directory_t = DLL_DIRECTORY_COOKIE(WINAPI *)(PCWSTR);
  auto add_dll_directory = reinterpret_cast<add_dll_directory_t>(GetProcAddress(kernel32, "AddDllDirectory"));
  if (add_dll_directory != nullptr) add_dll_directory(path.c_str());
}

std::string Win32ErrorMessage(DWORD code) {
  if (code == 0) return "unknown error";

  LPWSTR buffer = nullptr;
  DWORD size = FormatMessageW(FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM |
                                  FORMAT_MESSAGE_IGNORE_INSERTS,
                              nullptr, code, 0, reinterpret_cast<LPWSTR>(&buffer), 0, nullptr);
  std::wstring message = size == 0 || buffer == nullptr ? L"" : std::wstring(buffer, size);
  if (buffer != nullptr) LocalFree(buffer);
  while (!message.empty() && (message.back() == L'\r' || message.back() == L'\n' ||
                              message.back() == L' ' || message.back() == L'\t')) {
    message.pop_back();
  }
  if (message.empty()) {
    std::ostringstream fallback;
    fallback << "Win32 error " << code;
    return fallback.str();
  }
  return WideToUtf8(message);
}

void ConfigureDllSearch(const fs::path &runtimeDir, const fs::path &fallbackRubyRoot) {
  fs::path runtimeBuiltins = runtimeDir / L"ruby_builtin_dlls";
  fs::path legacyBin = runtimeDir.parent_path();
  fs::path root = legacyBin.parent_path();
  fs::path fallbackRubyBin = fallbackRubyRoot / L"bin";
  fs::path fallbackRubyBuiltins = fallbackRubyBin / L"ruby_builtin_dlls";
  AppendPathEnvironment({runtimeDir, runtimeBuiltins, legacyBin, root, fallbackRubyBin, fallbackRubyBuiltins});

  AddDllDirectoryCompat(runtimeDir);
  AddDllDirectoryCompat(runtimeBuiltins);
  AddDllDirectoryCompat(legacyBin);
  AddDllDirectoryCompat(root);
  AddDllDirectoryCompat(fallbackRubyBin);
  AddDllDirectoryCompat(fallbackRubyBuiltins);
  SetDllDirectoryW(runtimeDir.c_str());
}

template <typename T>
T RequiredProc(HMODULE dll, const char *name) {
  auto proc = reinterpret_cast<T>(GetProcAddress(dll, name));
  if (proc == nullptr) {
    std::ostringstream stream;
    stream << "Ruby export not found: " << name;
    throw std::runtime_error(stream.str());
  }
  return proc;
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
  if (const wchar_t *env = _wgetenv(L"ELTEN_ROOT")) {
    if (*env != L'\0') return fs::absolute(fs::path(env));
  }

  fs::path dir = ExecutablePath().parent_path();
  if ((SameName(dir, L"windows-x86") || SameName(dir, L"windows-x64") ||
       SameName(dir, L"windows-arm64") || SameName(dir, L"x86") ||
       SameName(dir, L"x64") || SameName(dir, L"arm64")) &&
      SameName(dir.parent_path(), L"bin")) {
    return dir.parent_path().parent_path();
  }
  return dir;
}

std::string PlatformName() {
  return "windows";
}

std::string PlatformNativeExtension() {
  return ".so";
}

fs::path PlatformPathFromUtf8(const std::string &value) {
  return fs::path(Utf8ToWide(value));
}

std::string PlatformPathToUtf8(const fs::path &path) {
  return WideToUtf8(path.wstring());
}

std::vector<std::string> PlatformCommandLineArguments(int, char **) {
  int argc = 0;
  LPWSTR *argvw = CommandLineToArgvW(GetCommandLineW(), &argc);
  std::vector<std::string> args;
  if (argvw == nullptr) return args;
  args.reserve(argc);
  for (int i = 0; i < argc; ++i) args.push_back(WideToUtf8(argvw[i]));
  LocalFree(argvw);
  return args;
}

void PlatformConfigureEnvironment(const fs::path &root, const fs::path &runtimeDir, const fs::path &fallbackRubyRoot) {
  SetEnvironmentVariableW(L"ELTEN_ROOT", root.c_str());
  SetEnvironmentVariableW(L"ELTEN_LAUNCHER_EXECUTABLE_PATH", ExecutablePath().c_str());
  SetEnvironmentVariableW(L"ELTEN_LAUNCHER_PLATFORM", L"windows");
  SetEnvironmentVariableW(L"ELTEN_LAUNCHER_ARCH", Utf8ToWide(ELTEN_LAUNCHER_ARCH).c_str());
  SetEnvironmentVariableW(L"ELTEN_RUBY_ROOT", runtimeDir.c_str());
  std::wstring gemDir = (runtimeDir / L"lib" / L"ruby" / L"gems" / Utf8ToWide(ELTEN_RUBY_API_VERSION)).wstring();
  SetEnvironmentVariableW(L"GEM_HOME", gemDir.c_str());
  SetEnvironmentVariableW(L"GEM_PATH", gemDir.c_str());
  ConfigureDllSearch(runtimeDir, fallbackRubyRoot);
}

bool PlatformRequiresEarlyEncodingDatabase() {
  return true;
}

bool PlatformSupportsYJIT() {
  return false;
}

RubyApi PlatformLoadRuby(const fs::path &runtimeDir, const fs::path &fallbackRubyRoot) {
  std::vector<fs::path> candidates = {
      runtimeDir / Utf8ToWide(ELTEN_RUBY_DLL_NAME),
      fallbackRubyRoot / L"bin" / Utf8ToWide(ELTEN_RUBY_DLL_NAME),
  };
  fs::path dllPath;
  HMODULE dll = nullptr;
  std::ostringstream errors;
  for (const auto &candidate : candidates) {
    if (!fs::exists(candidate)) {
      errors << "  " << PlatformPathToUtf8(candidate) << ": file not found\n";
      continue;
    }
    dllPath = candidate;
    dll = LoadLibraryW(dllPath.c_str());
    if (dll != nullptr) break;
    DWORD error = GetLastError();
    errors << "  " << PlatformPathToUtf8(candidate) << ": " << Win32ErrorMessage(error)
           << " (" << error << ")\n";
  }
  if (dll == nullptr) {
    throw std::runtime_error("Cannot load Ruby DLL:\n" + errors.str());
  }

  RubyApi api;
  api.library = dll;
  api.ruby_sysinit = RequiredProc<RubyApi::ruby_sysinit_t>(dll, "ruby_sysinit");
  api.ruby_init_stack = reinterpret_cast<RubyApi::ruby_init_stack_t>(GetProcAddress(dll, "ruby_init_stack"));
  api.ruby_init = RequiredProc<RubyApi::ruby_init_t>(dll, "ruby_init");
  api.ruby_init_loadpath = RequiredProc<RubyApi::ruby_init_loadpath_t>(dll, "ruby_init_loadpath");
  api.ruby_options = reinterpret_cast<RubyApi::ruby_options_t>(GetProcAddress(dll, "ruby_options"));
  api.ruby_script = RequiredProc<RubyApi::ruby_script_t>(dll, "ruby_script");
  api.rb_eval_string_protect = RequiredProc<RubyApi::rb_eval_string_protect_t>(dll, "rb_eval_string_protect");
  api.ruby_cleanup = RequiredProc<RubyApi::ruby_cleanup_t>(dll, "ruby_cleanup");
  api.rb_errinfo = reinterpret_cast<RubyApi::rb_errinfo_t>(GetProcAddress(dll, "rb_errinfo"));
  api.rb_intern = reinterpret_cast<RubyApi::rb_intern_t>(GetProcAddress(dll, "rb_intern"));
  api.rb_funcallv = reinterpret_cast<RubyApi::rb_funcallv_t>(GetProcAddress(dll, "rb_funcallv"));
  api.rb_obj_as_string = reinterpret_cast<RubyApi::rb_obj_as_string_t>(GetProcAddress(dll, "rb_obj_as_string"));
  api.rb_string_value_cstr = reinterpret_cast<RubyApi::rb_string_value_cstr_t>(GetProcAddress(dll, "rb_string_value_cstr"));
  return api;
}

EmbeddedRubyApi PlatformEmbeddedApi(const RubyApi &ruby) {
  HMODULE dll = static_cast<HMODULE>(ruby.library);
  EmbeddedRubyApi api;
  api.hash_new = RequiredProc<EmbeddedRubyApi::hash_new_t>(dll, "rb_hash_new");
  api.ary_new = RequiredProc<EmbeddedRubyApi::ary_new_t>(dll, "rb_ary_new");
  api.str_new = RequiredProc<EmbeddedRubyApi::str_new_t>(dll, "rb_str_new");
  api.utf8_str_new = reinterpret_cast<EmbeddedRubyApi::str_new_t>(GetProcAddress(dll, "rb_utf8_str_new"));
  api.ary_push = RequiredProc<EmbeddedRubyApi::ary_push_t>(dll, "rb_ary_push");
  api.hash_aset = RequiredProc<EmbeddedRubyApi::hash_aset_t>(dll, "rb_hash_aset");
  api.ll2inum = RequiredProc<EmbeddedRubyApi::ll2inum_t>(dll, "rb_ll2inum");
  api.gv_set = RequiredProc<EmbeddedRubyApi::gv_set_t>(dll, "rb_gv_set");
  api.gc_register_mark_object = reinterpret_cast<EmbeddedRubyApi::gc_register_mark_object_t>(
      GetProcAddress(dll, "rb_gc_register_mark_object"));
  return api;
}

StampRubyApi PlatformStampApi(const RubyApi &ruby) {
  HMODULE dll = static_cast<HMODULE>(ruby.library);
  StampRubyApi api;
  api.define_global_function = RequiredProc<StampRubyApi::define_global_function_t>(dll, "rb_define_global_function");
  api.hash_new = RequiredProc<StampRubyApi::hash_new_t>(dll, "rb_hash_new");
  api.str_new = RequiredProc<StampRubyApi::str_new_t>(dll, "rb_str_new");
  api.utf8_str_new = reinterpret_cast<StampRubyApi::str_new_t>(GetProcAddress(dll, "rb_utf8_str_new"));
  api.hash_aset = RequiredProc<StampRubyApi::hash_aset_t>(dll, "rb_hash_aset");
  api.raise = RequiredProc<StampRubyApi::raise_t>(dll, "rb_raise");
  api.obj_is_kind_of = RequiredProc<StampRubyApi::obj_is_kind_of_t>(dll, "rb_obj_is_kind_of");
  api.string_value_ptr = RequiredProc<StampRubyApi::string_value_ptr_t>(dll, "rb_string_value_ptr");
  api.intern = RequiredProc<StampRubyApi::intern_t>(dll, "rb_intern");
  api.funcallv = RequiredProc<StampRubyApi::funcallv_t>(dll, "rb_funcallv");
  api.num2long = RequiredProc<StampRubyApi::num2long_t>(dll, "rb_num2long");
  api.ll2inum = RequiredProc<StampRubyApi::ll2inum_t>(dll, "rb_ll2inum");
  api.c_string = EvalRubyExpression(ruby, "String");
  api.e_arg_error = EvalRubyExpression(ruby, "ArgumentError");
  api.e_runtime_error = EvalRubyExpression(ruby, "RuntimeError");
  return api;
}

void PlatformShowFatal(const std::string &message) {
  MessageBoxW(nullptr, Utf8ToWide(message).c_str(), L"Elten", MB_ICONERROR | MB_OK);
}

void PlatformSuspendOtherThreadsForFatalError() {
  DWORD processId = GetCurrentProcessId();
  DWORD currentThreadId = GetCurrentThreadId();
  HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPTHREAD, 0);
  if (snapshot == INVALID_HANDLE_VALUE) return;

  THREADENTRY32 entry = {};
  entry.dwSize = sizeof(entry);
  if (Thread32First(snapshot, &entry)) {
    do {
      if (entry.th32OwnerProcessID != processId || entry.th32ThreadID == currentThreadId) continue;
      HANDLE thread = OpenThread(THREAD_SUSPEND_RESUME, FALSE, entry.th32ThreadID);
      if (thread == nullptr) continue;
      SuspendThread(thread);
      CloseHandle(thread);
    } while (Thread32Next(snapshot, &entry));
  }

  CloseHandle(snapshot);
}

} // namespace EltenLauncher
