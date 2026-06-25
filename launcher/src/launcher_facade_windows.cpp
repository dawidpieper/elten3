#include <windows.h>
#include <shellapi.h>

#include <cwctype>
#include <filesystem>
#include <sstream>
#include <string>
#include <vector>

namespace fs = std::filesystem;

namespace {

enum class NativeArch {
  X86,
  X64,
  Arm64
};

std::wstring ExecutablePath() {
  std::wstring buffer(MAX_PATH, L'\0');
  DWORD length = 0;
  while (true) {
    length = GetModuleFileNameW(nullptr, buffer.data(), static_cast<DWORD>(buffer.size()));
    if (length == 0) return L"";
    if (length < buffer.size() - 1) {
      buffer.resize(length);
      return buffer;
    }
    buffer.resize(buffer.size() * 2);
  }
}

NativeArch DetectNativeArch() {
  HMODULE kernel32 = GetModuleHandleW(L"kernel32.dll");
  using is_wow64_process2_t = BOOL(WINAPI *)(HANDLE, USHORT *, USHORT *);
  auto is_wow64_process2 = reinterpret_cast<is_wow64_process2_t>(GetProcAddress(kernel32, "IsWow64Process2"));
  if (is_wow64_process2 != nullptr) {
    USHORT processMachine = 0;
    USHORT nativeMachine = 0;
    if (is_wow64_process2(GetCurrentProcess(), &processMachine, &nativeMachine)) {
      if (nativeMachine == IMAGE_FILE_MACHINE_ARM64) return NativeArch::Arm64;
      if (nativeMachine == IMAGE_FILE_MACHINE_AMD64) return NativeArch::X64;
      return NativeArch::X86;
    }
  }

#if defined(_M_ARM64)
  return NativeArch::Arm64;
#elif defined(_WIN64)
  return NativeArch::X64;
#else
  using is_wow64_process_t = BOOL(WINAPI *)(HANDLE, PBOOL);
  auto is_wow64_process = reinterpret_cast<is_wow64_process_t>(GetProcAddress(kernel32, "IsWow64Process"));
  BOOL wow64 = FALSE;
  if (is_wow64_process != nullptr && is_wow64_process(GetCurrentProcess(), &wow64) && wow64) {
    return NativeArch::X64;
  }
  return NativeArch::X86;
#endif
}

std::wstring QuoteCommandLineArgument(const std::wstring &arg) {
  if (arg.empty()) return L"\"\"";
  bool needsQuotes = false;
  for (wchar_t ch : arg) {
    if (iswspace(ch) || ch == L'"') {
      needsQuotes = true;
      break;
    }
  }
  if (!needsQuotes) return arg;

  std::wstring quoted = L"\"";
  std::size_t backslashes = 0;
  for (wchar_t ch : arg) {
    if (ch == L'\\') {
      ++backslashes;
    } else if (ch == L'"') {
      quoted.append(backslashes * 2 + 1, L'\\');
      quoted.push_back(ch);
      backslashes = 0;
    } else {
      quoted.append(backslashes, L'\\');
      quoted.push_back(ch);
      backslashes = 0;
    }
  }
  quoted.append(backslashes * 2, L'\\');
  quoted.push_back(L'"');
  return quoted;
}

std::vector<std::wstring> CandidateExecutables(NativeArch arch) {
  if (arch == NativeArch::Arm64) {
    return {L"elten-arm64.exe", L"elten-x64.exe", L"elten-x86.exe"};
  }
  if (arch == NativeArch::X64) {
    return {L"elten-x64.exe", L"elten-x86.exe"};
  }
  return {L"elten-x86.exe"};
}

fs::path ResolveTarget(const fs::path &root, std::wstring &tried) {
  for (const std::wstring &name : CandidateExecutables(DetectNativeArch())) {
    fs::path candidate = root / name;
    if (!tried.empty()) tried += L"\n";
    tried += candidate.wstring();
    if (fs::exists(candidate)) return candidate;
  }
  return {};
}

std::wstring BuildCommandLine(const fs::path &target) {
  int argc = 0;
  LPWSTR *argv = CommandLineToArgvW(GetCommandLineW(), &argc);
  std::wstring commandLine = QuoteCommandLineArgument(target.wstring());
  if (argv != nullptr) {
    for (int i = 1; i < argc; ++i) {
      commandLine.push_back(L' ');
      commandLine += QuoteCommandLineArgument(argv[i]);
    }
    LocalFree(argv);
  }
  return commandLine;
}

void ShowError(const std::wstring &message) {
  MessageBoxW(nullptr, message.c_str(), L"Elten", MB_ICONERROR | MB_OK);
}

} // namespace

int WINAPI wWinMain(HINSTANCE, HINSTANCE, PWSTR, int) {
  fs::path executablePath = ExecutablePath();
  fs::path root = executablePath.empty() ? fs::current_path() : executablePath.parent_path();

  std::wstring tried;
  fs::path target = ResolveTarget(root, tried);
  if (target.empty()) {
    ShowError(L"Cannot find a compatible Elten executable.\n\nTried:\n" + tried);
    return 1;
  }

  std::wstring commandLine = BuildCommandLine(target);
  std::vector<wchar_t> mutableCommand(commandLine.begin(), commandLine.end());
  mutableCommand.push_back(L'\0');

  STARTUPINFOW startup = {};
  startup.cb = sizeof(startup);
  PROCESS_INFORMATION process = {};
  BOOL created = CreateProcessW(target.c_str(), mutableCommand.data(), nullptr, nullptr, FALSE, 0, nullptr,
                                root.c_str(), &startup, &process);
  if (!created) {
    std::wstringstream stream;
    stream << L"Cannot start " << target.wstring() << L".\n\nWin32 error: " << GetLastError();
    ShowError(stream.str());
    return 1;
  }

  CloseHandle(process.hThread);
  CloseHandle(process.hProcess);
  return 0;
}
