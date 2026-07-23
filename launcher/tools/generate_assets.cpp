#include <algorithm>
#include <array>
#include <cctype>
#include <cerrno>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <cstdio>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <iterator>
#include <limits>
#include <map>
#include <random>
#include <set>
#include <sstream>
#include <stdexcept>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

#ifdef _WIN32
#ifndef NOMINMAX
#define NOMINMAX
#endif
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#else
#include <dlfcn.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>
#endif

#include "../src/blake3.hpp"

namespace fs = std::filesystem;

namespace {

struct Options {
  fs::path root;
  fs::path packageRoot;
  fs::path rubyRoot;
  fs::path gemLockfile;
  std::string arch = "arm64";
  std::string platform = "osx";
  fs::path runtimeOutput;
  fs::path nativeOutput;
  fs::path output;
  fs::path stampPayloadOutput;
  std::string compression = "zstd";
  fs::path zstdLibrary;
  bool copyRuntimeAssets = true;
  bool prepareOnly = false;
};

struct RubyEntry {
  fs::path path;
  std::string key;
  std::vector<std::string> aliases;
};

struct IntegrityPayloadEntry {
  std::string name;
  std::string dataName;
  std::size_t size = 0;
  std::string macName;
  std::uint32_t nonce = 0;
};

struct IntegrityFileEntry {
  std::string path;
  std::size_t size = 0;
  std::string macName;
  std::uint32_t nonce = 0;
};

struct ResourceEntry {
  std::string name;
  std::vector<unsigned char> data;
};

struct GeneratedResourceEntry {
  std::string name;
  std::string dataName;
  std::size_t storedSize = 0;
  std::size_t rawSize = 0;
};

struct ZstdApi {
  using compress_bound_t = std::size_t (*)(std::size_t);
  using compress_t = std::size_t (*)(void *, std::size_t, const void *, std::size_t, int);
  using is_error_t = unsigned (*)(std::size_t);
  using get_error_name_t = const char *(*)(std::size_t);

#ifdef _WIN32
  HMODULE handle = nullptr;
#else
  void *handle = nullptr;
#endif
  compress_bound_t compressBound = nullptr;
  compress_t compress = nullptr;
  is_error_t isError = nullptr;
  get_error_name_t getErrorName = nullptr;
};

std::string Slash(const fs::path &path) {
  return path.generic_string();
}

std::string Slash(std::string value) {
  std::replace(value.begin(), value.end(), '\\', '/');
  return value;
}

std::string Lower(std::string value) {
  std::transform(value.begin(), value.end(), value.begin(), [](unsigned char ch) {
    return static_cast<char>(std::tolower(ch));
  });
  return value;
}

bool EndsWith(std::string_view value, std::string_view suffix) {
  return value.size() >= suffix.size() &&
         std::equal(suffix.rbegin(), suffix.rend(), value.rbegin());
}

std::string RemoveExtension(std::string value) {
  std::string lower = Lower(value);
  for (std::string_view ext : {".rb", ".bundle", ".so", ".dylib"}) {
    if (EndsWith(lower, ext)) return value.substr(0, value.size() - ext.size());
  }
  return value;
}

std::string Relative(const fs::path &path, const fs::path &base) {
  std::error_code ec;
  fs::path rel = fs::relative(path, base, ec);
  if (!ec) return Slash(rel);

  std::string full = Slash(fs::absolute(path));
  std::string root = Slash(fs::absolute(base));
  if (Lower(full).rfind(Lower(root) + "/", 0) == 0) return full.substr(root.size() + 1);
  return full;
}

std::string WeaklyCanonicalSlash(const fs::path &path) {
  std::error_code ec;
  fs::path canonical = fs::weakly_canonical(path, ec);
  return Slash(ec ? fs::absolute(path) : canonical);
}

bool IsWindows(const Options &options) {
  return Lower(options.platform) == "windows";
}

bool IsMacOS(const Options &options) {
  return Lower(options.platform) == "osx";
}

std::string RuntimeDirectoryName(const Options &options) {
  if (IsWindows(options)) return "windows-" + options.arch;
  return options.platform;
}

fs::path RuntimePackageRoot(const Options &options) {
  return options.packageRoot / "bin" / RuntimeDirectoryName(options);
}

std::string RuntimePackagePathLabel(const Options &options) {
  return "bin/" + RuntimeDirectoryName(options);
}

std::vector<unsigned char> ReadFile(const fs::path &path) {
  std::ifstream file(path, std::ios::binary);
  if (!file) throw std::runtime_error("Cannot read " + Slash(path));
  return std::vector<unsigned char>(std::istreambuf_iterator<char>(file), std::istreambuf_iterator<char>());
}

void ReplaceAll(std::string &text, const std::string &from, const std::string &to) {
  if (from.empty()) return;

  std::size_t pos = 0;
  while ((pos = text.find(from, pos)) != std::string::npos) {
    text.replace(pos, from.size(), to);
    pos += to.size();
  }
}

std::vector<unsigned char> SanitizeRubyPayload(const Options &options, const fs::path &path,
                                               const std::vector<unsigned char> &bytes) {
  if (Lower(path.extension().generic_string()) != ".rb") return bytes;

  std::string text(reinterpret_cast<const char *>(bytes.data()), bytes.size());
  std::vector<std::pair<std::string, std::string>> replacements = {
    {Slash(fs::absolute(options.rubyRoot)), "__ELTEN_RUBY_ROOT__"},
    {WeaklyCanonicalSlash(options.rubyRoot), "__ELTEN_RUBY_ROOT__"},
    {Slash(fs::absolute(options.root)), "__ELTEN_BUILD_ROOT__"},
    {WeaklyCanonicalSlash(options.root), "__ELTEN_BUILD_ROOT__"},
    {Slash(fs::absolute(options.packageRoot)), "__ELTEN_PACKAGE_ROOT__"},
    {WeaklyCanonicalSlash(options.packageRoot), "__ELTEN_PACKAGE_ROOT__"}
  };

  for (const auto &replacement : replacements) {
    ReplaceAll(text, replacement.first, replacement.second);
    std::string native = replacement.first;
    std::replace(native.begin(), native.end(), '/', '\\');
    ReplaceAll(text, native, replacement.second);
  }

  return std::vector<unsigned char>(text.begin(), text.end());
}

void EnsureDirectory(const fs::path &path, const char *context) {
  if (path.empty()) return;

  std::error_code ec;
  if (fs::is_directory(path, ec)) return;

  ec.clear();
  fs::create_directories(path, ec);
  if (ec) {
    std::error_code checkEc;
    if (fs::is_directory(path, checkEc)) return;
    throw std::runtime_error(std::string("Cannot create directory for ") + context + ": " +
                             Slash(path) + " (" + ec.message() + ")");
  }

  ec.clear();
  if (!fs::is_directory(path, ec)) {
    throw std::runtime_error(std::string("Path exists but is not a directory for ") + context + ": " +
                             Slash(path));
  }
}

void WriteFile(const fs::path &path, const std::string &content) {
  EnsureDirectory(path.parent_path(), "generated output");
  std::ofstream file(path, std::ios::binary);
  if (!file) throw std::runtime_error("Cannot write " + Slash(path));
  file.write(content.data(), static_cast<std::streamsize>(content.size()));
}

void WriteBytes(const fs::path &path, const std::vector<unsigned char> &content) {
  EnsureDirectory(path.parent_path(), "generated output");
  std::ofstream file(path, std::ios::binary);
  if (!file) throw std::runtime_error("Cannot write " + Slash(path));
  file.write(reinterpret_cast<const char *>(content.data()), static_cast<std::streamsize>(content.size()));
}

bool FileEqualsBytes(const fs::path &path, const std::vector<unsigned char> &content) {
  std::error_code ec;
  if (!fs::is_regular_file(path, ec)) return false;
  std::uintmax_t size = fs::file_size(path, ec);
  if (ec || size != content.size()) return false;
  return ReadFile(path) == content;
}

bool WriteBytesIfChanged(const fs::path &path, const std::vector<unsigned char> &content) {
  if (FileEqualsBytes(path, content)) return false;
  WriteBytes(path, content);
  return true;
}

void AddKey(std::vector<std::string> &keys, std::string key) {
  key = Slash(key);
  while (!key.empty() && key.front() == '/') key.erase(key.begin());
  if (key.empty() || key.back() == '/') return;
  keys.push_back(key);
  std::string lower = Lower(key);
  if (EndsWith(lower, ".rb") || EndsWith(lower, ".bundle") || EndsWith(lower, ".so")) {
    keys.push_back(RemoveExtension(key));
  }
}

std::vector<std::string> Split(const std::string &value, char separator = '/') {
  std::vector<std::string> parts;
  std::string current;
  for (char ch : value) {
    if (ch == separator) {
      parts.push_back(current);
      current.clear();
    } else {
      current.push_back(ch);
    }
  }
  parts.push_back(current);
  return parts;
}

std::string JoinParts(const std::vector<std::string> &parts, std::size_t first) {
  std::string result;
  for (std::size_t index = first; index < parts.size(); ++index) {
    if (parts[index].empty()) continue;
    if (!result.empty()) result += "/";
    result += parts[index];
  }
  return result;
}

bool VersionPart(const std::string &part) {
  int dots = 0;
  bool digit = false;
  for (char ch : part) {
    if (ch == '.') {
      ++dots;
    } else if (std::isdigit(static_cast<unsigned char>(ch))) {
      digit = true;
    } else {
      return false;
    }
  }
  return digit && dots >= 1;
}

bool NativeArchPart(const std::string &part) {
  std::string lower = Lower(part);
  return lower.find("darwin") != std::string::npos ||
         lower.find("mingw") != std::string::npos ||
         lower.find("ucrt") != std::string::npos;
}

bool SkippedDirectory(const fs::path &path) {
  std::string name = Lower(path.filename().generic_string());
  return name == ".git" || name == ".yardoc" || name == "cache" ||
         name == "doc" || name == "ri" || name == ".bundle" ||
         EndsWith(name, ".dsym");
}

std::vector<fs::path> RecursiveFiles(const fs::path &root, const std::set<std::string> &extensions,
                                     bool skipKnownDirectories = true) {
  std::vector<fs::path> files;
  if (!fs::exists(root)) return files;

  fs::recursive_directory_iterator it(root), end;
  while (it != end) {
    const fs::path path = it->path();
    if (it->is_directory()) {
      if (skipKnownDirectories && SkippedDirectory(path)) it.disable_recursion_pending();
    } else if (it->is_regular_file()) {
      std::string ext = Lower(path.extension().generic_string());
      if (extensions.count(ext) > 0) files.push_back(path);
    }
    ++it;
  }
  std::sort(files.begin(), files.end(), [](const fs::path &a, const fs::path &b) {
    return Lower(Slash(a)) < Lower(Slash(b));
  });
  return files;
}

std::vector<fs::path> RecursiveRegularFiles(const fs::path &root) {
  std::vector<fs::path> files;
  if (!fs::exists(root)) return files;

  std::error_code ec;
  fs::recursive_directory_iterator it(root, ec), end;
  while (!ec && it != end) {
    const fs::path path = it->path();
    if (it->is_directory(ec)) {
      if (!ec && SkippedDirectory(path)) it.disable_recursion_pending();
    } else if (it->is_regular_file(ec)) {
      files.push_back(path);
    }
    it.increment(ec);
  }
  std::sort(files.begin(), files.end(), [](const fs::path &a, const fs::path &b) {
    return Lower(Slash(a)) < Lower(Slash(b));
  });
  return files;
}

std::string ResourceNameFromRoot(const fs::path &path, const fs::path &root) {
  return Relative(path, root);
}

std::string LocaleResourceName(const fs::path &path, const fs::path &root) {
  fs::path relative = fs::relative(path, root);
  std::vector<std::string> parts;
  for (const fs::path &part : relative) {
    std::string value = part.generic_string();
    if (Lower(value) == "lc_messages") value = "LC_MESSAGES";
    parts.push_back(value);
  }
  std::ostringstream name;
  for (std::size_t i = 0; i < parts.size(); ++i) {
    if (i > 0) name << "/";
    name << parts[i];
  }
  return name.str();
}

std::vector<ResourceEntry> EmbeddedResourceEntries(const Options &options) {
  std::vector<ResourceEntry> entries;
  fs::path resourcesRoot = options.root / "resources";
  fs::path localeRoot = options.root / "locale";
  std::error_code ec;

  if (fs::is_directory(resourcesRoot, ec)) {
    for (const fs::path &path : RecursiveRegularFiles(resourcesRoot)) {
      std::string extension = Lower(path.extension().generic_string());
      if (extension != ".json" && extension != ".pem") continue;
      entries.push_back({ResourceNameFromRoot(path, resourcesRoot), ReadFile(path)});
    }
  }

  const std::string tlsCaResourceName = "ssl/cert.pem";
  fs::path tlsCaPath = options.rubyRoot / "ssl" / "cert.pem";
  std::vector<unsigned char> tlsCaData = ReadFile(tlsCaPath);
  if (tlsCaData.empty()) {
    throw std::runtime_error("Ruby OpenSSL CA bundle is empty: " + Slash(tlsCaPath));
  }
  auto tlsCaCollision = std::find_if(entries.begin(), entries.end(), [&](const ResourceEntry &entry) {
    return Lower(entry.name) == Lower(tlsCaResourceName);
  });
  if (tlsCaCollision != entries.end()) {
    throw std::runtime_error("Embedded resource name is reserved for the Ruby OpenSSL CA bundle: " +
                             tlsCaResourceName);
  }
  entries.push_back({tlsCaResourceName, std::move(tlsCaData)});

  ec.clear();
  if (fs::is_directory(localeRoot, ec)) {
    for (const fs::path &path : RecursiveRegularFiles(localeRoot)) {
      std::string extension = Lower(path.extension().generic_string());
      if (extension != ".mo" && extension != ".md") continue;
      entries.push_back({"locale/" + LocaleResourceName(path, localeRoot), ReadFile(path)});
    }
  }

  std::sort(entries.begin(), entries.end(), [](const ResourceEntry &a, const ResourceEntry &b) {
    return Lower(a.name) < Lower(b.name);
  });
  entries.erase(std::unique(entries.begin(), entries.end(), [](const ResourceEntry &a, const ResourceEntry &b) {
    return Lower(a.name) == Lower(b.name);
  }), entries.end());
  return entries;
}

std::vector<fs::path> AppRubySources(const Options &options) {
  std::vector<fs::path> files;
  fs::path elten = options.root / "elten.rb";
  if (fs::is_regular_file(elten)) files.push_back(elten);
  auto src = RecursiveFiles(options.root / "src", {".rb"}, false);
  files.insert(files.end(), src.begin(), src.end());
  std::sort(files.begin(), files.end(), [&](const fs::path &a, const fs::path &b) {
    return Lower(Relative(a, options.root)) < Lower(Relative(b, options.root));
  });
  files.erase(std::unique(files.begin(), files.end()), files.end());
  return files;
}

std::vector<fs::path> RubyLibRubySources(const Options &options) {
  fs::path rubyRoot = options.rubyRoot / "lib" / "ruby";
  std::vector<fs::path> all = RecursiveFiles(rubyRoot, {".rb"});
  std::set<std::string> bundledGems;
  fs::path lockfile = options.gemLockfile.empty() ? options.root / "Gemfile.lock" : options.gemLockfile;
  if (fs::is_regular_file(lockfile)) {
    std::ifstream input(lockfile);
    std::string line;
    bool inSpecs = false;
    while (std::getline(input, line)) {
      if (line == "  specs:") {
        inSpecs = true;
        continue;
      }
      if (inSpecs && !line.empty() && line[0] != ' ') break;
      if (!inSpecs || line.rfind("    ", 0) != 0) continue;
      std::string spec = line.substr(4);
      std::size_t version = spec.find(" (");
      if (version == std::string::npos) continue;
      bundledGems.insert(Lower(spec.substr(0, version)));
    }
  }

  auto gemNameFromDirectory = [](const std::string &dir) {
    for (std::size_t pos = dir.size(); pos > 0;) {
      pos = dir.rfind('-', pos - 1);
      if (pos == std::string::npos) break;
      if (pos + 1 < dir.size() && std::isdigit(static_cast<unsigned char>(dir[pos + 1])) &&
          dir.find('.', pos + 1) != std::string::npos) {
        return Lower(dir.substr(0, pos));
      }
    }
    return Lower(dir);
  };

  std::vector<fs::path> files;
  for (const fs::path &path : all) {
    std::string tail = Relative(path, rubyRoot);
    std::vector<std::string> parts = Split(tail);
    if (parts.empty()) continue;
    if (parts[0] == "gems") {
      if (parts.size() < 5 || parts[2] != "gems") continue;
      std::string gemName = gemNameFromDirectory(parts[3]);
      if (bundledGems.find(gemName) == bundledGems.end()) continue;
      if (parts[4] != "lib") continue;
    }
    files.push_back(path);
  }
  return files;
}

std::vector<std::string> RubyLibKeys(const Options &options, const fs::path &path) {
  std::vector<std::string> keys;
  std::string tail = Relative(path, options.rubyRoot / "lib" / "ruby");
  std::vector<std::string> parts = Split(tail);

  if (parts.size() >= 4 && parts[0] == "gems") {
    auto lib = std::find(parts.begin(), parts.end(), "lib");
    if (lib != parts.end()) AddKey(keys, JoinParts(parts, static_cast<std::size_t>(lib - parts.begin()) + 1));
  } else if (parts.size() >= 2 && VersionPart(parts[0])) {
    AddKey(keys, JoinParts(parts, NativeArchPart(parts[1]) ? 2 : 1));
  } else if ((parts[0] == "site_ruby" || parts[0] == "vendor_ruby") && parts.size() >= 3) {
    for (std::size_t index = 1; index < parts.size(); ++index) {
      if (!VersionPart(parts[index])) continue;
      std::size_t next = index + 1;
      if (next < parts.size() && NativeArchPart(parts[next])) ++next;
      AddKey(keys, JoinParts(parts, next));
      break;
    }
  }

  AddKey(keys, Relative(path, options.root));

  std::vector<std::string> uniqueKeys;
  std::set<std::string> seenKeys;
  for (const std::string &key : keys) {
    if (seenKeys.insert(Lower(key)).second) uniqueKeys.push_back(key);
  }
  return uniqueKeys;
}

std::vector<RubyEntry> EmbeddedRubyEntries(const Options &options) {
  std::vector<RubyEntry> entries;
  for (const fs::path &path : AppRubySources(options)) {
    entries.push_back({path, Relative(path, options.root), {}});
  }
  for (const fs::path &path : RubyLibRubySources(options)) {
    std::vector<std::string> keys = RubyLibKeys(options, path);
    if (keys.empty()) keys.push_back(Relative(path, options.root));
    std::string key = keys.front();
    keys.erase(keys.begin());
    entries.push_back({path, key, keys});
  }
  return entries;
}

std::vector<std::string> NativeKeys(const Options &options, const fs::path &path) {
  std::vector<std::string> keys;
  std::string tail = Relative(path, options.rubyRoot / "lib" / "ruby");
  std::vector<std::string> parts = Split(tail);

  if (parts.size() >= 3 && VersionPart(parts[0]) && NativeArchPart(parts[1])) {
    AddKey(keys, JoinParts(parts, 2));
  } else if (parts.size() >= 6 && parts[0] == "gems" && parts[2] == "gems") {
    auto lib = std::find(parts.begin(), parts.end(), "lib");
    if (lib != parts.end()) AddKey(keys, JoinParts(parts, static_cast<std::size_t>(lib - parts.begin()) + 1));
  } else if (parts.size() >= 7 && parts[0] == "gems" && parts[2] == "extensions") {
    AddKey(keys, JoinParts(parts, 6));
  }

  AddKey(keys, path.filename().generic_string());

  std::vector<std::string> uniqueKeys;
  std::set<std::string> seenKeys;
  for (const std::string &key : keys) {
    if (seenKeys.insert(Lower(key)).second) uniqueKeys.push_back(key);
  }
  return uniqueKeys;
}

void CopyIfChanged(const fs::path &source, const fs::path &destination) {
  EnsureDirectory(destination.parent_path(), "native extension copy");
  std::error_code ec;
  if (fs::is_regular_file(destination, ec) && fs::file_size(source, ec) == fs::file_size(destination, ec)) {
    return;
  }
  fs::copy_file(source, destination, fs::copy_options::overwrite_existing);
}

bool SameFileContent(const fs::path &left, const fs::path &right) {
  std::error_code ec;
  if (!fs::is_regular_file(left, ec) || !fs::is_regular_file(right, ec)) return false;
  if (fs::file_size(left, ec) != fs::file_size(right, ec)) return false;

  std::ifstream l(left, std::ios::binary);
  std::ifstream r(right, std::ios::binary);
  if (!l || !r) return false;

  std::array<char, 64 * 1024> lb{};
  std::array<char, 64 * 1024> rb{};
  do {
    l.read(lb.data(), static_cast<std::streamsize>(lb.size()));
    r.read(rb.data(), static_cast<std::streamsize>(rb.size()));
    if (l.gcount() != r.gcount()) return false;
    if (std::memcmp(lb.data(), rb.data(), static_cast<std::size_t>(l.gcount())) != 0) return false;
  } while (l && r);

  return l.eof() && r.eof();
}

bool WindowsAssemblyManifestReferencesFile(const fs::path &manifest, const fs::path &file) {
  std::error_code ec;
  if (!fs::is_regular_file(manifest, ec)) return false;

  std::vector<unsigned char> bytes = ReadFile(manifest);
  std::string text(reinterpret_cast<const char *>(bytes.data()), bytes.size());
  std::string fileName = file.filename().generic_string();
  std::string quoted = "file name=\"" + fileName + "\"";
  std::string singleQuoted = "file name='" + fileName + "'";
  return text.find(quoted) != std::string::npos || text.find(singleQuoted) != std::string::npos;
}

bool WindowsNativeDllRequiredByLocalAssemblyManifest(const fs::path &dll) {
  std::error_code ec;
  fs::path dir = dll.parent_path();
  if (!fs::is_directory(dir, ec)) return false;

  for (const fs::directory_entry &entry : fs::directory_iterator(dir, ec)) {
    if (ec || !entry.is_regular_file(ec)) continue;
    if (Lower(entry.path().extension().generic_string()) != ".manifest") continue;
    if (WindowsAssemblyManifestReferencesFile(entry.path(), dll)) return true;
  }
  return false;
}

bool CopyWindowsSupportDllIfNeeded(const fs::path &source, const fs::path &destination, bool overwriteExisting) {
  std::string extension = Lower(source.extension().generic_string());
  if (extension != ".dll") return false;

  std::error_code ec;
  fs::path builtinCopy = destination.parent_path() / "ruby_builtin_dlls" / destination.filename();
  if (SameFileContent(source, builtinCopy)) {
    if (SameFileContent(destination, builtinCopy)) fs::remove(destination, ec);
    return false;
  }

  if (!overwriteExisting && fs::exists(destination, ec)) return false;
  bool same = SameFileContent(source, destination);
  if (same) return false;

  CopyIfChanged(source, destination);
  return true;
}

int CopyWindowsSupportDllDirectory(const fs::path &sourceDir, const fs::path &destinationDir, bool recursive) {
  std::error_code ec;
  if (!fs::is_directory(sourceDir, ec)) return 0;

  int copied = 0;
  std::vector<fs::path> sources = recursive ? RecursiveRegularFiles(sourceDir) : std::vector<fs::path>{};
  if (!recursive) {
    for (const fs::directory_entry &entry : fs::directory_iterator(sourceDir, ec)) {
      if (ec || !entry.is_regular_file(ec)) continue;
      sources.push_back(entry.path());
    }
  }

  for (const fs::path &source : sources) {
    fs::path destination = destinationDir / source.filename();
    if (CopyWindowsSupportDllIfNeeded(source, destination, false)) ++copied;
  }
  return copied;
}

struct WindowsPeSection {
  std::uint32_t virtualAddress = 0;
  std::uint32_t virtualSize = 0;
  std::uint32_t rawPointer = 0;
  std::uint32_t rawSize = 0;
};

bool RangeAvailable(const std::vector<unsigned char> &bytes, std::size_t offset, std::size_t size) {
  return offset <= bytes.size() && size <= bytes.size() - offset;
}

std::uint16_t ReadU16LE(const std::vector<unsigned char> &bytes, std::size_t offset) {
  return static_cast<std::uint16_t>(bytes[offset]) |
         static_cast<std::uint16_t>(bytes[offset + 1] << 8);
}

std::uint32_t ReadU32LE(const std::vector<unsigned char> &bytes, std::size_t offset) {
  return static_cast<std::uint32_t>(bytes[offset]) |
         (static_cast<std::uint32_t>(bytes[offset + 1]) << 8) |
         (static_cast<std::uint32_t>(bytes[offset + 2]) << 16) |
         (static_cast<std::uint32_t>(bytes[offset + 3]) << 24);
}

bool PeRvaToOffset(const std::vector<unsigned char> &bytes, const std::vector<WindowsPeSection> &sections,
                   std::uint32_t rva, std::size_t &offset) {
  for (const WindowsPeSection &section : sections) {
    std::uint32_t span = std::max(section.virtualSize, section.rawSize);
    if (span == 0 || rva < section.virtualAddress || rva - section.virtualAddress >= span) continue;

    std::uint64_t fileOffset = static_cast<std::uint64_t>(section.rawPointer) +
                               static_cast<std::uint64_t>(rva - section.virtualAddress);
    if (fileOffset > static_cast<std::uint64_t>(std::numeric_limits<std::size_t>::max())) return false;
    offset = static_cast<std::size_t>(fileOffset);
    return offset < bytes.size();
  }

  if (rva < bytes.size()) {
    offset = static_cast<std::size_t>(rva);
    return true;
  }
  return false;
}

std::string ReadPeCString(const std::vector<unsigned char> &bytes, std::size_t offset) {
  std::string value;
  while (offset < bytes.size() && bytes[offset] != 0 && value.size() < 512) {
    value.push_back(static_cast<char>(bytes[offset++]));
  }
  return offset < bytes.size() && bytes[offset] == 0 ? value : std::string();
}

bool WindowsPortableExecutablePath(const fs::path &path) {
  std::string extension = Lower(path.extension().generic_string());
  return extension == ".exe" || extension == ".dll" || extension == ".so" ||
         extension == ".pyd" || extension == ".bundle";
}

std::vector<std::string> ReadWindowsPeImportedDlls(const fs::path &path) {
  std::vector<std::string> imports;
  if (!WindowsPortableExecutablePath(path)) return imports;

  std::vector<unsigned char> bytes;
  try {
    bytes = ReadFile(path);
  } catch (...) {
    return imports;
  }

  if (!RangeAvailable(bytes, 0, 0x40) || bytes[0] != 'M' || bytes[1] != 'Z') return imports;
  std::uint32_t peOffset32 = ReadU32LE(bytes, 0x3c);
  std::size_t peOffset = static_cast<std::size_t>(peOffset32);
  if (!RangeAvailable(bytes, peOffset, 24)) return imports;
  if (std::memcmp(bytes.data() + peOffset, "PE\0\0", 4) != 0) return imports;

  std::uint16_t sectionCount = ReadU16LE(bytes, peOffset + 6);
  std::uint16_t optionalHeaderSize = ReadU16LE(bytes, peOffset + 20);
  std::size_t optionalOffset = peOffset + 24;
  if (!RangeAvailable(bytes, optionalOffset, optionalHeaderSize)) return imports;

  std::uint16_t magic = ReadU16LE(bytes, optionalOffset);
  std::size_t dataDirectoryOffset = 0;
  if (magic == 0x10b) {
    dataDirectoryOffset = optionalOffset + 96;
  } else if (magic == 0x20b) {
    dataDirectoryOffset = optionalOffset + 112;
  } else {
    return imports;
  }

  if (!RangeAvailable(bytes, dataDirectoryOffset, 16)) return imports;
  std::uint32_t importRva = ReadU32LE(bytes, dataDirectoryOffset + 8);
  if (importRva == 0) return imports;

  std::size_t sectionOffset = optionalOffset + optionalHeaderSize;
  std::vector<WindowsPeSection> sections;
  sections.reserve(sectionCount);
  for (std::uint16_t index = 0; index < sectionCount; ++index) {
    std::size_t offset = sectionOffset + static_cast<std::size_t>(index) * 40;
    if (!RangeAvailable(bytes, offset, 40)) break;
    WindowsPeSection section;
    section.virtualSize = ReadU32LE(bytes, offset + 8);
    section.virtualAddress = ReadU32LE(bytes, offset + 12);
    section.rawSize = ReadU32LE(bytes, offset + 16);
    section.rawPointer = ReadU32LE(bytes, offset + 20);
    sections.push_back(section);
  }

  std::size_t descriptorOffset = 0;
  if (!PeRvaToOffset(bytes, sections, importRva, descriptorOffset)) return imports;

  for (std::size_t index = 0; index < 8192; ++index) {
    std::size_t offset = descriptorOffset + index * 20;
    if (!RangeAvailable(bytes, offset, 20)) break;

    std::uint32_t originalFirstThunk = ReadU32LE(bytes, offset);
    std::uint32_t timeDateStamp = ReadU32LE(bytes, offset + 4);
    std::uint32_t forwarderChain = ReadU32LE(bytes, offset + 8);
    std::uint32_t nameRva = ReadU32LE(bytes, offset + 12);
    std::uint32_t firstThunk = ReadU32LE(bytes, offset + 16);
    if (originalFirstThunk == 0 && timeDateStamp == 0 && forwarderChain == 0 &&
        nameRva == 0 && firstThunk == 0) {
      break;
    }
    if (nameRva == 0) continue;

    std::size_t nameOffset = 0;
    if (!PeRvaToOffset(bytes, sections, nameRva, nameOffset)) continue;
    std::string name = Lower(ReadPeCString(bytes, nameOffset));
    if (!name.empty()) imports.push_back(name);
  }

  std::sort(imports.begin(), imports.end());
  imports.erase(std::unique(imports.begin(), imports.end()), imports.end());
  return imports;
}

bool WindowsSystemDllName(const std::string &name) {
  std::string lower = Lower(name);
  if (lower.rfind("api-ms-win-", 0) == 0 || lower.rfind("ext-ms-win-", 0) == 0) return true;
  if (lower.rfind("vcruntime", 0) == 0 || lower.rfind("msvcp", 0) == 0) return true;

  static const std::set<std::string> systemDlls = {
    "advapi32.dll", "bcrypt.dll", "cabinet.dll", "comctl32.dll", "comdlg32.dll",
    "crypt32.dll", "dnsapi.dll", "gdi32.dll", "imagehlp.dll", "iphlpapi.dll",
    "kernel32.dll", "msvcrt.dll", "ncrypt.dll", "netapi32.dll", "ntdll.dll",
    "ole32.dll", "oleaut32.dll", "psapi.dll", "rpcrt4.dll", "secur32.dll",
    "setupapi.dll", "shell32.dll", "shlwapi.dll", "user32.dll", "userenv.dll",
    "version.dll", "winhttp.dll", "wininet.dll", "winmm.dll", "ws2_32.dll",
    "wtsapi32.dll", "ucrtbase.dll"
  };
  return systemDlls.count(lower) > 0;
}

std::vector<fs::path> WindowsMsysDllSearchDirectories(const Options &options) {
  std::vector<fs::path> dirs;
  auto add = [&](const fs::path &relative) {
    fs::path directory = options.rubyRoot / relative;
    std::error_code ec;
    if (fs::is_directory(directory, ec)) dirs.push_back(directory);
  };

  std::string arch = Lower(options.arch);
  if (arch == "x86") {
    add(fs::path("msys64") / "mingw32" / "bin");
    add(fs::path("msys32") / "mingw32" / "bin");
  } else if (arch == "x64") {
    add(fs::path("msys64") / "ucrt64" / "bin");
    add(fs::path("msys64") / "mingw64" / "bin");
    add(fs::path("msys64") / "clang64" / "bin");
  } else if (arch == "arm64" || arch == "aarch64" || arch == "arm") {
    add(fs::path("msys64") / "clangarm64" / "bin");
    add(fs::path("msys32") / "clangarm64" / "bin");
  } else {
    for (const fs::path &relative : {
             fs::path("msys64") / "ucrt64" / "bin",
             fs::path("msys64") / "mingw64" / "bin",
             fs::path("msys64") / "mingw32" / "bin",
             fs::path("msys64") / "clang64" / "bin",
             fs::path("msys64") / "clangarm64" / "bin",
             fs::path("msys32") / "ucrt64" / "bin",
             fs::path("msys32") / "mingw64" / "bin",
             fs::path("msys32") / "mingw32" / "bin",
             fs::path("msys32") / "clang64" / "bin",
             fs::path("msys32") / "clangarm64" / "bin",
         }) {
      add(relative);
    }
  }
  return dirs;
}

std::map<std::string, fs::path> WindowsMsysDllSourceMap(const Options &options) {
  std::map<std::string, fs::path> sources;
  for (const fs::path &directory : WindowsMsysDllSearchDirectories(options)) {
    std::error_code ec;
    for (const fs::directory_entry &entry : fs::directory_iterator(directory, ec)) {
      if (ec || !entry.is_regular_file(ec)) continue;
      if (Lower(entry.path().extension().generic_string()) != ".dll") continue;
      sources.emplace(Lower(entry.path().filename().generic_string()), entry.path());
    }
  }
  return sources;
}

bool FindFileCaseInsensitive(const fs::path &directory, const std::string &filename, fs::path &found) {
  if (directory.empty()) return false;

  std::error_code ec;
  fs::path direct = directory / filename;
  if (fs::is_regular_file(direct, ec)) {
    found = direct;
    return true;
  }

  if (!fs::is_directory(directory, ec)) return false;
  std::string wanted = Lower(filename);
  for (const fs::directory_entry &entry : fs::directory_iterator(directory, ec)) {
    if (ec || !entry.is_regular_file(ec)) continue;
    if (Lower(entry.path().filename().generic_string()) == wanted) {
      found = entry.path();
      return true;
    }
  }
  return false;
}

bool WindowsPackagedDllPath(const Options &options, const fs::path &importer,
                            const std::string &dllName, fs::path &found) {
  fs::path runtimeRoot = RuntimePackageRoot(options);
  std::vector<fs::path> directories = {
    importer.parent_path(),
    runtimeRoot,
    runtimeRoot / "ruby_builtin_dlls"
  };
  if (!options.nativeOutput.empty()) directories.push_back(options.nativeOutput);

  std::set<std::string> seen;
  for (const fs::path &directory : directories) {
    std::string key = Lower(Slash(directory));
    if (key.empty() || !seen.insert(key).second) continue;
    if (FindFileCaseInsensitive(directory, dllName, found)) return true;
  }
  return false;
}

void ResolveWindowsMsysSupportDllDependencies(const Options &options) {
  if (!IsWindows(options) || options.runtimeOutput.empty() || !options.copyRuntimeAssets) return;

  std::map<std::string, fs::path> sources = WindowsMsysDllSourceMap(options);
  if (sources.empty()) return;

  fs::path runtimeRoot = RuntimePackageRoot(options);
  std::vector<fs::path> pending;
  std::set<std::string> queued;
  std::set<std::string> required;
  int copied = 0;
  int removed = 0;

  auto queue = [&](const fs::path &path) {
    std::error_code ec;
    if (!fs::is_regular_file(path, ec) || !WindowsPortableExecutablePath(path)) return;
    std::string key = Lower(WeaklyCanonicalSlash(path));
    if (queued.insert(key).second) pending.push_back(path);
  };

  for (const fs::path &path : RecursiveRegularFiles(runtimeRoot)) queue(path);
  std::error_code equivalentEc;
  bool nativeIsRuntime = !options.nativeOutput.empty() && fs::equivalent(options.nativeOutput, runtimeRoot, equivalentEc);
  if (!options.nativeOutput.empty() && (equivalentEc || !nativeIsRuntime)) {
    for (const fs::path &path : RecursiveRegularFiles(options.nativeOutput)) queue(path);
  }

  auto requireDll = [&](const std::string &dllName, const fs::path &importer) {
    std::string lower = Lower(dllName);
    if (WindowsSystemDllName(lower)) return;

    fs::path packaged;
    if (WindowsPackagedDllPath(options, importer, lower, packaged)) {
      queue(packaged);
      if (sources.count(lower) > 0) required.insert(lower);
      return;
    }

    auto source = sources.find(lower);
    if (source == sources.end()) return;
    required.insert(lower);
    fs::path destination = runtimeRoot / source->second.filename();
    if (CopyWindowsSupportDllIfNeeded(source->second, destination, false)) ++copied;
    queue(destination);
  };

  if (options.compression == "zstd") {
    if (!options.zstdLibrary.empty() && fs::is_regular_file(options.zstdLibrary)) {
      std::string name = Lower(options.zstdLibrary.filename().generic_string());
      required.insert(name);
      fs::path destination = runtimeRoot / options.zstdLibrary.filename();
      if (CopyWindowsSupportDllIfNeeded(options.zstdLibrary, destination, false)) ++copied;
      queue(destination);
    } else {
      requireDll("libzstd.dll", runtimeRoot / "elten.exe");
    }
  }

  for (std::size_t index = 0; index < pending.size(); ++index) {
    for (const std::string &dllName : ReadWindowsPeImportedDlls(pending[index])) {
      requireDll(dllName, pending[index]);
    }
  }

  for (const auto &item : sources) {
    if (required.count(item.first) > 0) continue;

    fs::path rootCopy;
    if (!FindFileCaseInsensitive(runtimeRoot, item.first, rootCopy)) continue;
    if (!SameFileContent(rootCopy, item.second)) continue;

    std::error_code ec;
    fs::remove(rootCopy, ec);
    if (ec) {
      throw std::runtime_error("Cannot remove unused Windows MSYS support DLL: " +
                               Slash(rootCopy) + " (" + ec.message() + ")");
    }
    ++removed;
  }

  if (copied > 0 || removed > 0) {
    std::cerr << "Resolved Windows MSYS support DLL dependencies in " << RuntimePackagePathLabel(options)
              << " (" << copied << " added, " << removed << " removed).\n";
  }
}

bool RelativePathStartsWith(const fs::path &relative, const std::string &part) {
  auto it = relative.begin();
  if (it == relative.end()) return false;
  return Lower(it->generic_string()) == Lower(part);
}

void RemoveDuplicateWindowsRuntimeRootBuiltinDlls(const Options &options) {
  if (!IsWindows(options) || !options.copyRuntimeAssets) return;

  std::error_code ec;
  fs::path builtins = options.runtimeOutput / "ruby_builtin_dlls";
  if (!fs::is_directory(builtins, ec)) return;

  for (const fs::directory_entry &entry : fs::directory_iterator(builtins, ec)) {
    if (ec || !entry.is_regular_file(ec)) continue;
    if (Lower(entry.path().extension().generic_string()) != ".dll") continue;

    fs::path rootCopy = options.runtimeOutput / entry.path().filename();
    if (!SameFileContent(entry.path(), rootCopy)) continue;

    fs::remove(rootCopy, ec);
    if (ec) {
      throw std::runtime_error("Cannot remove duplicate runtime root builtin DLL: " +
                               Slash(rootCopy) + " (" + ec.message() + ")");
    }
  }
}

bool WindowsDllDirectoryHasRootConflicts(const fs::path &sourceDir, const fs::path &runtimeRoot) {
  std::error_code ec;
  if (!fs::is_directory(sourceDir, ec)) return false;

  for (const fs::directory_entry &entry : fs::directory_iterator(sourceDir, ec)) {
    if (ec || !entry.is_regular_file(ec)) continue;
    if (Lower(entry.path().extension().generic_string()) != ".dll") continue;

    fs::path rootCopy = runtimeRoot / entry.path().filename();
    if (fs::is_regular_file(rootCopy, ec) && !SameFileContent(entry.path(), rootCopy)) {
      return true;
    }
  }
  return false;
}

void CopyWindowsRuntimeFiles(const Options &options) {
  if (!IsWindows(options) || options.runtimeOutput.empty() || !options.copyRuntimeAssets) return;

  EnsureDirectory(options.runtimeOutput, "Windows Ruby runtime output");
  fs::path rubyBin = options.rubyRoot / "bin";
  if (!fs::is_directory(rubyBin)) {
    throw std::runtime_error("Ruby bin directory not found: " + Slash(rubyBin));
  }

  int copied = 0;
  for (const fs::path &source : RecursiveRegularFiles(rubyBin)) {
    std::string extension = Lower(source.extension().generic_string());
    if (extension != ".dll" && extension != ".manifest") continue;

    fs::path relative = fs::relative(source, rubyBin);
    fs::path destination = options.runtimeOutput / relative;
    std::error_code ec;
    bool same = SameFileContent(source, destination);
    if (!same) {
      CopyIfChanged(source, destination);
      ++copied;
    }
  }

  int supportCopied = 0;
  fs::path builtinDlls = rubyBin / "ruby_builtin_dlls";
  if (WindowsDllDirectoryHasRootConflicts(builtinDlls, options.runtimeOutput)) {
    std::cerr << "Keeping runtime root DLLs that conflict with ruby_builtin_dlls.\n";
  }

  supportCopied += CopyWindowsSupportDllDirectory(options.rubyRoot / "lib" / "ruby", options.runtimeOutput, true);

  RemoveDuplicateWindowsRuntimeRootBuiltinDlls(options);

  std::cerr << "Prepared Ruby runtime in " << RuntimePackagePathLabel(options)
            << " (" << copied << " updated, " << supportCopied << " Ruby support DLLs added).\n";
}

void RemoveStaleNativeFileDirectory(const fs::path &path, const fs::path &nativeRoot) {
  if (path.empty()) return;

  std::error_code ec;
  if (!fs::is_regular_file(path, ec)) return;

  fs::path rel = fs::relative(path, nativeRoot, ec);
  if (ec || rel.empty() || rel.generic_string().find("..") == 0) return;

  fs::remove(path, ec);
  if (ec) {
    throw std::runtime_error("Cannot remove stale native extension file blocking a directory: " +
                             Slash(path) + " (" + ec.message() + ")");
  }
}

void RemoveStaleExtensionlessNativeAlias(const fs::path &destination, const fs::path &nativeRoot) {
  std::string extension = Lower(destination.extension().generic_string());
  if (extension != ".bundle" && extension != ".so") return;

  fs::path stalePath = destination;
  stalePath.replace_extension();
  if (stalePath == destination || stalePath.filename().empty()) return;

  std::error_code ec;
  if (!fs::is_regular_file(stalePath, ec)) return;

  fs::path rel = fs::relative(stalePath, nativeRoot, ec);
  if (ec || rel.empty() || rel.generic_string().find("..") == 0) return;

  fs::remove(stalePath, ec);
  if (ec) {
    throw std::runtime_error("Cannot remove stale extensionless native extension alias: " +
                             Slash(stalePath) + " (" + ec.message() + ")");
  }
}

void RemoveDuplicateWindowsNativeCompanionDlls(const Options &options) {
  if (!IsWindows(options) || !options.copyRuntimeAssets) return;
  if (fs::equivalent(options.nativeOutput, RuntimePackageRoot(options))) return;

  std::error_code ec;
  if (!fs::is_directory(options.nativeOutput, ec)) return;

  for (const fs::path &path : RecursiveRegularFiles(options.nativeOutput)) {
    if (Lower(path.extension().generic_string()) != ".dll") continue;

    fs::path rootCopy = RuntimePackageRoot(options) / path.filename();
    if (!SameFileContent(path, rootCopy)) continue;
    if (WindowsNativeDllRequiredByLocalAssemblyManifest(path)) continue;

    fs::path rel = fs::relative(path, options.nativeOutput, ec);
    if (ec || rel.empty() || rel.generic_string().find("..") == 0) continue;

    fs::remove(path, ec);
    if (ec) {
      throw std::runtime_error("Cannot remove stale native companion DLL: " +
                               Slash(path) + " (" + ec.message() + ")");
    }
  }
}

void RemoveDuplicateWindowsRuntimeRootNativeDlls(const Options &options) {
  if (!IsWindows(options) || !options.copyRuntimeAssets) return;
  if (fs::equivalent(options.nativeOutput, RuntimePackageRoot(options))) return;

  std::error_code ec;
  if (!fs::is_directory(options.nativeOutput, ec)) return;

  for (const fs::path &path : RecursiveRegularFiles(options.nativeOutput)) {
    if (Lower(path.extension().generic_string()) != ".dll") continue;
    if (!WindowsNativeDllRequiredByLocalAssemblyManifest(path)) continue;

    fs::path rootCopy = RuntimePackageRoot(options) / path.filename();
    if (!SameFileContent(path, rootCopy)) continue;

    fs::remove(rootCopy, ec);
    if (ec) {
      throw std::runtime_error("Cannot remove duplicate runtime root native DLL: " +
                               Slash(rootCopy) + " (" + ec.message() + ")");
    }
  }
}

void CopyNativeCompanions(const Options &options, const fs::path &source, const fs::path &destination) {
  std::error_code ec;
  fs::path sourceDir = source.parent_path();
  if (!fs::is_directory(sourceDir, ec)) return;

  for (const fs::directory_entry &entry : fs::directory_iterator(sourceDir, ec)) {
    if (ec || !entry.is_regular_file(ec)) continue;
    std::string extension = Lower(entry.path().extension().generic_string());
    if (IsMacOS(options)) {
      if (extension != ".dylib") continue;
      CopyIfChanged(entry.path(), destination.parent_path() / entry.path().filename());
    } else if (IsWindows(options)) {
      if (extension == ".dll") {
        fs::path localManifest = source.parent_path() / (source.filename().generic_string() + "-assembly.manifest");
        if (WindowsAssemblyManifestReferencesFile(localManifest, entry.path())) {
          CopyIfChanged(entry.path(), destination.parent_path() / entry.path().filename());
          continue;
        }

        fs::path rootCopy = RuntimePackageRoot(options) / entry.path().filename();
        fs::path builtinCopy = RuntimePackageRoot(options) / "ruby_builtin_dlls" / entry.path().filename();
        if (SameFileContent(entry.path(), builtinCopy)) {
          if (SameFileContent(rootCopy, builtinCopy)) fs::remove(rootCopy, ec);
        } else if (!fs::is_regular_file(rootCopy, ec)) {
          CopyIfChanged(entry.path(), rootCopy);
        } else if (!SameFileContent(entry.path(), rootCopy)) {
          CopyIfChanged(entry.path(), destination.parent_path() / entry.path().filename());
        }
      } else if (extension == ".manifest") {
        CopyIfChanged(entry.path(), destination.parent_path() / entry.path().filename());
      }
    }
  }
}

int RemoveStaleNativeExtensions(const Options &options,
                                const std::set<std::string> &expectedFiles) {
  if (!options.copyRuntimeAssets) return 0;

  int removed = 0;
  for (const fs::path &path : RecursiveFiles(options.nativeOutput, {".bundle", ".so"})) {
    if (expectedFiles.count(Lower(WeaklyCanonicalSlash(path))) > 0) continue;

    std::error_code ec;
    fs::remove(path, ec);
    if (ec) {
      throw std::runtime_error("Cannot remove stale native extension: " +
                               Slash(path) + " (" + ec.message() + ")");
    }
    ++removed;
  }
  return removed;
}

std::map<std::string, std::string> PrepareNativeFiles(const Options &options) {
  EnsureDirectory(options.nativeOutput, "native extension output");

  std::map<std::string, std::string> map;
  std::set<std::string> expectedFiles;
  std::vector<fs::path> files = RecursiveFiles(options.rubyRoot / "lib", {".bundle", ".so"});
  for (const fs::path &source : files) {
    if (Lower(Slash(source)).find(".dsym/") != std::string::npos) continue;
    std::vector<std::string> keys = NativeKeys(options, source);
    std::string primary = keys.empty() ? source.filename().generic_string() : keys.front();
    for (const std::string &key : keys) {
      if (EndsWith(Lower(key), ".bundle") || EndsWith(Lower(key), ".so")) {
        primary = key;
        break;
      }
    }
    fs::path destination = options.nativeOutput / fs::path(primary);
    if (options.copyRuntimeAssets) {
      RemoveStaleNativeFileDirectory(destination.parent_path(), options.nativeOutput);
      CopyIfChanged(source, destination);
      expectedFiles.insert(Lower(WeaklyCanonicalSlash(destination)));
      fs::path staleFlatAlias = options.nativeOutput / source.filename();
      if (staleFlatAlias != destination && SameFileContent(source, staleFlatAlias)) {
        std::error_code removeEc;
        fs::remove(staleFlatAlias, removeEc);
        if (removeEc) {
          throw std::runtime_error("Cannot remove stale flattened native extension alias: " +
                                   Slash(staleFlatAlias) + " (" + removeEc.message() + ")");
        }
      }
      RemoveStaleExtensionlessNativeAlias(destination, options.nativeOutput);
      CopyNativeCompanions(options, source, destination);
    }
    std::error_code destinationEc;
    if (!fs::is_regular_file(destination, destinationEc)) {
      throw std::runtime_error("Prepared native extension is missing: " + Slash(destination));
    }
    std::string relativeDestination = Relative(destination, options.packageRoot);
    for (const std::string &key : keys) map.emplace(Lower(key), relativeDestination);
  }
  int staleRemoved = RemoveStaleNativeExtensions(options, expectedFiles);
  if (staleRemoved > 0) {
    std::cerr << "Removed " << staleRemoved << " stale native extension"
              << (staleRemoved == 1 ? "" : "s") << ".\n";
  }
  RemoveDuplicateWindowsNativeCompanionDlls(options);
  RemoveDuplicateWindowsRuntimeRootNativeDlls(options);
  return map;
}

std::string CppString(const std::string &value) {
  std::string result;
  for (unsigned char ch : value) {
    switch (ch) {
      case '\\': result += "\\\\"; break;
      case '"': result += "\\\""; break;
      case '\n': result += "\\n"; break;
      case '\r': result += "\\r"; break;
      case '\t': result += "\\t"; break;
      default:
        if (ch < 0x20 || ch >= 0x7f) {
          char buffer[5];
          std::snprintf(buffer, sizeof(buffer), "\\x%02X", ch);
          result += buffer;
        } else {
          result.push_back(static_cast<char>(ch));
        }
    }
  }
  return result;
}

void WriteByteArray(std::ostringstream &out, const std::string &name, const std::vector<unsigned char> &bytes) {
  out << "static const unsigned char " << name << "[] = {\n";
  if (bytes.empty()) {
    out << "  0x00,\n";
  } else {
    for (std::size_t index = 0; index < bytes.size(); index += 24) {
      out << "  ";
      std::size_t end = std::min(index + 24, bytes.size());
      for (std::size_t i = index; i < end; ++i) {
        char buffer[8];
        std::snprintf(buffer, sizeof(buffer), "0x%02X", bytes[i]);
        out << buffer << ", ";
      }
      out << "\n";
    }
  }
  out << "};\n";
}

std::vector<unsigned char> RandomBytes(std::size_t size) {
  static std::random_device rd;
  std::vector<unsigned char> bytes(size);
  for (std::size_t offset = 0; offset < bytes.size();) {
    unsigned int value = rd();
    for (int i = 0; i < 4 && offset < bytes.size(); ++i) {
      bytes[offset++] = static_cast<unsigned char>((value >> (i * 8)) & 0xff);
    }
  }
  return bytes;
}

std::uint32_t RandomU32() {
  std::vector<unsigned char> bytes = RandomBytes(4);
  return static_cast<std::uint32_t>(bytes[0]) |
         (static_cast<std::uint32_t>(bytes[1]) << 8) |
         (static_cast<std::uint32_t>(bytes[2]) << 16) |
         (static_cast<std::uint32_t>(bytes[3]) << 24);
}

std::vector<std::vector<unsigned char>> IntegrityKeyShards(const std::vector<unsigned char> &key) {
  std::vector<std::vector<unsigned char>> shards;
  for (int i = 0; i < 7; ++i) shards.push_back(RandomBytes(32));

  std::vector<unsigned char> final(32, 0);
  for (std::size_t i = 0; i < final.size(); ++i) {
    unsigned char value = key[i];
    for (const std::vector<unsigned char> &shard : shards) value ^= shard[i];
    final[i] = value;
  }
  shards.push_back(final);
  return shards;
}

void AppendCString(std::vector<unsigned char> &message, const std::string &value) {
  message.insert(message.end(), value.begin(), value.end());
  message.push_back(0);
}

void AppendU32LE(std::vector<unsigned char> &message, std::uint32_t value) {
  for (int shift = 0; shift < 32; shift += 8) {
    message.push_back(static_cast<unsigned char>((value >> shift) & 0xff));
  }
}

void AppendU64LE(std::vector<unsigned char> &message, std::uint64_t value) {
  for (int shift = 0; shift < 64; shift += 8) {
    message.push_back(static_cast<unsigned char>((value >> shift) & 0xff));
  }
}

std::size_t AppendBlobRange(std::vector<unsigned char> &blob, const std::vector<unsigned char> &payload) {
  std::size_t offset = blob.size();
  blob.insert(blob.end(), payload.begin(), payload.end());
  return offset;
}

std::array<std::uint8_t, 32> PayloadMac(const std::vector<unsigned char> &key, const std::string &domain,
                                        const std::string &name, const std::vector<unsigned char> &payload,
                                        std::uint32_t nonce, bool includePayload) {
  std::vector<unsigned char> message;
  message.reserve(96 + (includePayload ? payload.size() : 0));
  AppendCString(message, domain);
  AppendCString(message, name);
  AppendU32LE(message, nonce);
  AppendU64LE(message, static_cast<std::uint64_t>(payload.size()));
  if (includePayload) message.insert(message.end(), payload.begin(), payload.end());
  return EltenLauncher::Blake3KeyedDigest(key, message);
}

std::vector<unsigned char> MaskedNamedPayloadMac(const std::vector<unsigned char> &key, const std::string &macDomain,
                                                 const std::string &maskDomain, const std::string &name,
                                                 const std::vector<unsigned char> &payload, std::uint32_t nonce) {
  auto mac = PayloadMac(key, macDomain, name, payload, nonce, true);
  auto mask = PayloadMac(key, maskDomain, name, payload, nonce, false);
  std::vector<unsigned char> masked(32, 0);
  for (std::size_t i = 0; i < masked.size(); ++i) masked[i] = static_cast<unsigned char>(mac[i] ^ mask[i]);
  return masked;
}

std::vector<unsigned char> MaskedPayloadMac(const std::vector<unsigned char> &key, const std::string &name,
                                            const std::vector<unsigned char> &payload, std::uint32_t nonce) {
  return MaskedNamedPayloadMac(key, "EltenEmbeddedPayload:v1", "EltenEmbeddedPayloadMask:v1", name, payload, nonce);
}

std::vector<unsigned char> MaskedExternalFileMac(const std::vector<unsigned char> &key, const std::string &name,
                                                 const std::vector<unsigned char> &payload, std::uint32_t nonce) {
  return MaskedNamedPayloadMac(key, "EltenExternalFile:v1", "EltenExternalFileMask:v1", name, payload, nonce);
}

template <typename T>
T ZstdSymbol(
#ifdef _WIN32
    HMODULE handle,
#else
    void *handle,
#endif
    const char *name) {
#ifdef _WIN32
  auto symbol = reinterpret_cast<void *>(GetProcAddress(handle, name));
#else
  void *symbol = dlsym(handle, name);
#endif
  if (symbol == nullptr) throw std::runtime_error(std::string("ZSTD export not found: ") + name);
  return reinterpret_cast<T>(symbol);
}

ZstdApi LoadZstd(const Options &options) {
  std::vector<std::string> candidates;
  if (!options.zstdLibrary.empty()) candidates.push_back(Slash(options.zstdLibrary));
  if (IsWindows(options)) {
    candidates.push_back(Slash(RuntimePackageRoot(options) / "libzstd.dll"));
    candidates.push_back("libzstd.dll");
  } else {
    candidates.push_back(Slash(RuntimePackageRoot(options) / "libzstd.dylib"));
    candidates.push_back("libzstd.dylib");
  }

  ZstdApi api;
  std::string errors;
  for (const std::string &candidate : candidates) {
#ifdef _WIN32
    api.handle = LoadLibraryW(fs::path(candidate).wstring().c_str());
    if (api.handle != nullptr) break;
    errors += "  ";
    errors += candidate;
    errors += ": Windows error ";
    errors += std::to_string(GetLastError());
    errors += "\n";
#else
    dlerror();
    api.handle = dlopen(candidate.c_str(), RTLD_NOW | RTLD_LOCAL);
    if (api.handle != nullptr) break;
    const char *error = dlerror();
    errors += "  ";
    errors += candidate;
    errors += ": ";
    errors += error == nullptr ? "unknown dlopen error" : error;
    errors += "\n";
#endif
  }
  if (api.handle == nullptr) {
    throw std::runtime_error("Cannot load ZSTD library for asset compression:\n" + errors);
  }
  api.compressBound = ZstdSymbol<ZstdApi::compress_bound_t>(api.handle, "ZSTD_compressBound");
  api.compress = ZstdSymbol<ZstdApi::compress_t>(api.handle, "ZSTD_compress");
  api.isError = ZstdSymbol<ZstdApi::is_error_t>(api.handle, "ZSTD_isError");
  api.getErrorName = ZstdSymbol<ZstdApi::get_error_name_t>(api.handle, "ZSTD_getErrorName");
  return api;
}

std::vector<unsigned char> StoredPayload(const Options &options, const ZstdApi *zstd, const std::vector<unsigned char> &bytes) {
  if (options.compression != "zstd") return bytes;
  std::vector<unsigned char> output(zstd->compressBound(bytes.size()));
  std::size_t result = zstd->compress(output.data(), output.size(), bytes.data(), bytes.size(), 3);
  if (zstd->isError(result) != 0) {
    const char *name = zstd->getErrorName(result);
    throw std::runtime_error(std::string("ZSTD compression failed: ") + (name == nullptr ? "unknown" : name));
  }
  output.resize(result);
  return output;
}

void AppendBytes(std::vector<unsigned char> &target, const std::vector<unsigned char> &source) {
  target.insert(target.end(), source.begin(), source.end());
}

void AppendStringBytes(std::vector<unsigned char> &target, const std::string &source) {
  target.insert(target.end(), source.begin(), source.end());
}

void AppendU16LE(std::vector<unsigned char> &target, std::uint16_t value) {
  target.push_back(static_cast<unsigned char>(value & 0xff));
  target.push_back(static_cast<unsigned char>((value >> 8) & 0xff));
}

void AppendU32BE(std::vector<unsigned char> &target, std::uint32_t value) {
  for (int shift = 24; shift >= 0; shift -= 8) target.push_back(static_cast<unsigned char>((value >> shift) & 0xff));
}

std::uint32_t Adler32(const std::vector<unsigned char> &bytes) {
  constexpr std::uint32_t mod = 65521;
  std::uint32_t a = 1;
  std::uint32_t b = 0;
  for (unsigned char byte : bytes) {
    a = (a + byte) % mod;
    b = (b + a) % mod;
  }
  return (b << 16) | a;
}

std::vector<unsigned char> ZlibStoredDeflate(const std::vector<unsigned char> &bytes) {
  std::vector<unsigned char> output;
  output.reserve(bytes.size() + bytes.size() / 65535 * 5 + 11);
  output.push_back(0x78);
  output.push_back(0x01);

  std::size_t offset = 0;
  do {
    std::size_t chunk = std::min<std::size_t>(65535, bytes.size() - offset);
    bool final = offset + chunk >= bytes.size();
    output.push_back(final ? 0x01 : 0x00);
    AppendU16LE(output, static_cast<std::uint16_t>(chunk));
    AppendU16LE(output, static_cast<std::uint16_t>(~static_cast<std::uint16_t>(chunk)));
    output.insert(output.end(), bytes.begin() + static_cast<std::ptrdiff_t>(offset),
                  bytes.begin() + static_cast<std::ptrdiff_t>(offset + chunk));
    offset += chunk;
  } while (offset < bytes.size());

  AppendU32BE(output, Adler32(bytes));
  return output;
}

std::vector<fs::path> DefaultSoundThemeSources(const Options &options) {
  std::vector<fs::path> sources;
  fs::path root = options.root / "audio";
  std::error_code ec;
  if (!fs::is_directory(root, ec)) return sources;

  for (const fs::directory_entry &entry : fs::directory_iterator(root, ec)) {
    if (ec || !entry.is_regular_file(ec)) continue;
    if (Lower(entry.path().extension().generic_string()) != ".ogg") continue;
    sources.push_back(entry.path());
  }
  std::sort(sources.begin(), sources.end(), [](const fs::path &a, const fs::path &b) {
    return Lower(a.filename().generic_string()) < Lower(b.filename().generic_string());
  });
  return sources;
}

void BuildDefaultSoundThemePackage(const Options &options) {
  std::vector<fs::path> sources = DefaultSoundThemeSources(options);
  if (sources.empty()) throw std::runtime_error("No default sound theme sources found in " + Slash(options.root / "audio"));

  std::vector<unsigned char> records;
  for (const fs::path &source : sources) {
    std::string name = source.stem().generic_string();
    if (name.empty() || name.size() > 255) throw std::runtime_error("Invalid sound name " + Slash(source));
    std::vector<unsigned char> content = ReadFile(source);
    if (content.size() > std::numeric_limits<std::uint32_t>::max()) {
      throw std::runtime_error("Sound file too large: " + Slash(source));
    }
    records.push_back(static_cast<unsigned char>(name.size()));
    AppendStringBytes(records, name);
    AppendU32LE(records, static_cast<std::uint32_t>(content.size()));
    AppendBytes(records, content);
  }

  std::vector<unsigned char> compressed = ZlibStoredDeflate(records);
  if (compressed.size() > std::numeric_limits<std::uint32_t>::max()) {
    throw std::runtime_error("Default sound theme package is too large");
  }

  std::vector<unsigned char> package;
  AppendStringBytes(package, "EltenSoundThemePackageFileCMPSMC");
  AppendU64LE(package, 0);
  package.push_back(0);
  AppendU32LE(package, static_cast<std::uint32_t>(compressed.size()));
  AppendBytes(package, compressed);

  fs::path output = options.packageRoot / "data" / "audio.elsnd";
  if (WriteBytesIfChanged(output, package)) {
    std::cerr << "Built default sound theme " << Slash(output) << " from " << sources.size() << " audio files.\n";
  } else {
    std::cerr << "Default sound theme already up to date: " << Slash(output) << "\n";
  }
}

struct ZipEntry {
  std::string name;
  std::vector<unsigned char> data;
  std::uint32_t crc = 0;
  std::uint32_t localOffset = 0;
};

bool PathHasPart(const fs::path &path, const std::string &part) {
  std::string expected = Lower(part);
  for (const fs::path &item : path) {
    if (Lower(item.generic_string()) == expected) return true;
  }
  return false;
}

std::uint32_t Crc32(const std::vector<unsigned char> &bytes) {
  std::uint32_t crc = 0xffffffffu;
  for (unsigned char byte : bytes) {
    crc ^= byte;
    for (int bit = 0; bit < 8; ++bit) {
      crc = (crc >> 1) ^ (0xedb88320u & (0u - (crc & 1u)));
    }
  }
  return crc ^ 0xffffffffu;
}

void AppendZipFileHeader(std::vector<unsigned char> &zip, ZipEntry &entry) {
  if (entry.name.size() > std::numeric_limits<std::uint16_t>::max()) {
    throw std::runtime_error("NVDA addon entry name is too long: " + entry.name);
  }
  if (entry.data.size() > std::numeric_limits<std::uint32_t>::max()) {
    throw std::runtime_error("NVDA addon entry is too large: " + entry.name);
  }
  if (zip.size() > std::numeric_limits<std::uint32_t>::max()) {
    throw std::runtime_error("NVDA addon zip is too large");
  }

  entry.localOffset = static_cast<std::uint32_t>(zip.size());
  entry.crc = Crc32(entry.data);
  AppendU32LE(zip, 0x04034b50u);
  AppendU16LE(zip, 20);
  AppendU16LE(zip, 0);
  AppendU16LE(zip, 0);
  AppendU16LE(zip, 0);
  AppendU16LE(zip, 33);
  AppendU32LE(zip, entry.crc);
  AppendU32LE(zip, static_cast<std::uint32_t>(entry.data.size()));
  AppendU32LE(zip, static_cast<std::uint32_t>(entry.data.size()));
  AppendU16LE(zip, static_cast<std::uint16_t>(entry.name.size()));
  AppendU16LE(zip, 0);
  AppendStringBytes(zip, entry.name);
  AppendBytes(zip, entry.data);
}

void AppendZipCentralDirectoryEntry(std::vector<unsigned char> &zip, const ZipEntry &entry) {
  AppendU32LE(zip, 0x02014b50u);
  AppendU16LE(zip, 20);
  AppendU16LE(zip, 20);
  AppendU16LE(zip, 0);
  AppendU16LE(zip, 0);
  AppendU16LE(zip, 0);
  AppendU16LE(zip, 33);
  AppendU32LE(zip, entry.crc);
  AppendU32LE(zip, static_cast<std::uint32_t>(entry.data.size()));
  AppendU32LE(zip, static_cast<std::uint32_t>(entry.data.size()));
  AppendU16LE(zip, static_cast<std::uint16_t>(entry.name.size()));
  AppendU16LE(zip, 0);
  AppendU16LE(zip, 0);
  AppendU16LE(zip, 0);
  AppendU16LE(zip, 0);
  AppendU32LE(zip, 0);
  AppendU32LE(zip, entry.localOffset);
  AppendStringBytes(zip, entry.name);
}

std::vector<ZipEntry> NvdaAddonEntries(const Options &options) {
  fs::path root = options.root / "nvda" / "elten";
  if (!fs::is_directory(root)) {
    throw std::runtime_error("No NVDA addon source directory found at " + Slash(root));
  }

  std::vector<ZipEntry> entries;
  for (const fs::path &path : RecursiveRegularFiles(root)) {
    std::string extension = Lower(path.extension().generic_string());
    if (extension == ".pyc" || PathHasPart(path, "__pycache__")) continue;
    std::string name = Relative(path, root);
    if (name.empty()) continue;
    entries.push_back({name, ReadFile(path), 0, 0});
  }
  std::sort(entries.begin(), entries.end(), [](const ZipEntry &a, const ZipEntry &b) {
    return Lower(a.name) < Lower(b.name);
  });
  if (entries.empty()) throw std::runtime_error("No NVDA addon files found in " + Slash(root));
  return entries;
}

void BuildNvdaAddonPackage(const Options &options) {
  if (!IsWindows(options)) return;

  std::vector<ZipEntry> entries = NvdaAddonEntries(options);
  std::vector<unsigned char> zip;
  for (ZipEntry &entry : entries) AppendZipFileHeader(zip, entry);

  if (zip.size() > std::numeric_limits<std::uint32_t>::max()) {
    throw std::runtime_error("NVDA addon zip is too large");
  }
  std::uint32_t centralOffset = static_cast<std::uint32_t>(zip.size());
  for (const ZipEntry &entry : entries) AppendZipCentralDirectoryEntry(zip, entry);
  std::uint32_t centralSize = static_cast<std::uint32_t>(zip.size() - centralOffset);
  if (entries.size() > std::numeric_limits<std::uint16_t>::max()) {
    throw std::runtime_error("NVDA addon has too many files");
  }

  AppendU32LE(zip, 0x06054b50u);
  AppendU16LE(zip, 0);
  AppendU16LE(zip, 0);
  AppendU16LE(zip, static_cast<std::uint16_t>(entries.size()));
  AppendU16LE(zip, static_cast<std::uint16_t>(entries.size()));
  AppendU32LE(zip, centralSize);
  AppendU32LE(zip, centralOffset);
  AppendU16LE(zip, 0);

  fs::path output = options.packageRoot / "data" / "elten.nvda-addon";
  if (WriteBytesIfChanged(output, zip)) {
    std::cerr << "Built NVDA addon " << Slash(output) << " from " << entries.size() << " files.\n";
  } else {
    std::cerr << "NVDA addon already up to date: " << Slash(output) << "\n";
  }
}

std::string GeneratedIncludes(const Options &options) {
  std::ostringstream out;
  out << "#include \"embedded_assets.hpp\"\n";
  out << "#include \"blake3.hpp\"\n";
  out << "#include <algorithm>\n#include <array>\n#include <cerrno>\n#include <condition_variable>\n#include <cstddef>\n#include <cstdint>\n#include <cstring>\n#include <filesystem>\n#include <fstream>\n#include <iterator>\n#include <limits>\n#include <mutex>\n#include <stdexcept>\n#include <string>\n#include <system_error>\n#include <thread>\n#include <utility>\n#include <vector>\n";
  if (IsWindows(options)) {
    out << "#ifndef NOMINMAX\n#define NOMINMAX\n#endif\n";
    out << "#ifndef WIN32_LEAN_AND_MEAN\n#define WIN32_LEAN_AND_MEAN\n#endif\n";
    out << "#include <windows.h>\n";
  } else {
    out << "#include <dlfcn.h>\n#include <fcntl.h>\n#include <mach-o/dyld.h>\n#include <sys/stat.h>\n#include <unistd.h>\n";
  }
  out << "\n";
  return out.str();
}

void WriteIntegritySupport(std::ostringstream &out, const std::vector<std::vector<unsigned char>> &keyShards,
                           const Options &options) {
  out << "struct EmbeddedPayloadIntegrity {\n";
  out << "  const char *name;\n";
  out << "  const unsigned char *data;\n";
  out << "  std::size_t size;\n";
  out << "  const unsigned char *masked_mac;\n";
  out << "  std::uint32_t nonce;\n";
  out << "};\n\n";
  for (std::size_t index = 0; index < keyShards.size(); ++index) {
    WriteByteArray(out, "integrity_key_part_" + std::to_string(index), keyShards[index]);
  }
  out << "\n";
  out << "std::array<std::uint8_t, 32> EmbeddedIntegrityKey() {\n";
  out << "  std::array<std::uint8_t, 32> key = {};\n";
  out << "  for (std::size_t i = 0; i < key.size(); ++i) {\n";
  out << "    key[i] = static_cast<std::uint8_t>(\n";
  out << "      integrity_key_part_0[i] ^ integrity_key_part_1[i] ^ integrity_key_part_2[i] ^ integrity_key_part_3[i] ^\n";
  out << "      integrity_key_part_4[i] ^ integrity_key_part_5[i] ^ integrity_key_part_6[i] ^ integrity_key_part_7[i]);\n";
  out << "  }\n";
  out << "  return key;\n";
  out << "}\n\n";
  out << "void AppendCString(std::vector<unsigned char> &message, const char *value) {\n";
  out << "  if (value != nullptr) {\n";
  out << "    while (*value != '\\0') message.push_back(static_cast<unsigned char>(*value++));\n";
  out << "  }\n";
  out << "  message.push_back(0);\n";
  out << "}\n\n";
  out << "void AppendU32LE(std::vector<unsigned char> &message, std::uint32_t value) {\n";
  out << "  for (int shift = 0; shift < 32; shift += 8) message.push_back(static_cast<unsigned char>((value >> shift) & 0xff));\n";
  out << "}\n\n";
  out << "void AppendU64LE(std::vector<unsigned char> &message, std::uint64_t value) {\n";
  out << "  for (int shift = 0; shift < 64; shift += 8) message.push_back(static_cast<unsigned char>((value >> shift) & 0xff));\n";
  out << "}\n\n";
  out << "std::array<std::uint8_t, 32> PayloadMacData(const std::array<std::uint8_t, 32> &key, const char *domain,\n";
  out << "                                           const char *name, const unsigned char *data, std::size_t size,\n";
  out << "                                           std::uint32_t nonce, bool include_payload) {\n";
  out << "  std::vector<unsigned char> message;\n";
  out << "  message.reserve(96 + size);\n";
  out << "  AppendCString(message, domain);\n";
  out << "  AppendCString(message, name);\n";
  out << "  AppendU32LE(message, nonce);\n";
  out << "  AppendU64LE(message, static_cast<std::uint64_t>(size));\n";
  out << "  if (include_payload && size > 0) message.insert(message.end(), data, data + size);\n";
  out << "  return EltenLauncher::Blake3KeyedDigest(key.data(), key.size(), message.data(), message.size());\n";
  out << "}\n\n";
  out << "struct ExternalFileIntegrity {\n";
  out << "  const char *path;\n";
  out << "  std::size_t size;\n";
  out << "  const unsigned char *masked_mac;\n";
  out << "  std::uint32_t nonce;\n";
  out << "};\n\n";
  if (IsWindows(options)) {
    out << "struct LockedExternalFile {\n";
    out << "  HANDLE handle = INVALID_HANDLE_VALUE;\n";
    out << "  LockedExternalFile() = default;\n";
    out << "  explicit LockedExternalFile(HANDLE value) : handle(value) {}\n";
    out << "  ~LockedExternalFile() { if (handle != INVALID_HANDLE_VALUE) CloseHandle(handle); }\n";
    out << "  LockedExternalFile(const LockedExternalFile &) = delete;\n";
    out << "  LockedExternalFile &operator=(const LockedExternalFile &) = delete;\n";
    out << "  LockedExternalFile(LockedExternalFile &&other) noexcept : handle(other.handle) { other.handle = INVALID_HANDLE_VALUE; }\n";
    out << "  LockedExternalFile &operator=(LockedExternalFile &&other) noexcept {\n";
    out << "    if (this != &other) {\n";
    out << "      if (handle != INVALID_HANDLE_VALUE) CloseHandle(handle);\n";
    out << "      handle = other.handle;\n";
    out << "      other.handle = INVALID_HANDLE_VALUE;\n";
    out << "    }\n";
    out << "    return *this;\n";
    out << "  }\n";
    out << "};\n\n";
    out << "std::vector<LockedExternalFile> g_locked_external_files;\n\n";
    out << "bool ReadLockedFileBytes(const std::filesystem::path &path, std::vector<unsigned char> &bytes, LockedExternalFile &locked) {\n";
    out << "  HANDLE handle = CreateFileW(path.wstring().c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING,\n";
    out << "                              FILE_ATTRIBUTE_NORMAL | FILE_FLAG_SEQUENTIAL_SCAN, nullptr);\n";
    out << "  if (handle == INVALID_HANDLE_VALUE) return false;\n";
    out << "  LockedExternalFile guard(handle);\n";
    out << "  LARGE_INTEGER file_size;\n";
    out << "  if (!GetFileSizeEx(handle, &file_size) || file_size.QuadPart < 0) return false;\n";
    out << "  unsigned long long raw_size = static_cast<unsigned long long>(file_size.QuadPart);\n";
    out << "  if (raw_size > static_cast<unsigned long long>(std::numeric_limits<std::size_t>::max())) return false;\n";
    out << "  bytes.resize(static_cast<std::size_t>(raw_size));\n";
    out << "  std::size_t offset = 0;\n";
    out << "  while (offset < bytes.size()) {\n";
    out << "    std::size_t remaining = bytes.size() - offset;\n";
    out << "    DWORD request = remaining > static_cast<std::size_t>(std::numeric_limits<DWORD>::max()) ?\n";
    out << "                    std::numeric_limits<DWORD>::max() : static_cast<DWORD>(remaining);\n";
    out << "    DWORD read = 0;\n";
    out << "    if (!ReadFile(handle, bytes.data() + offset, request, &read, nullptr) || read == 0) return false;\n";
    out << "    offset += read;\n";
    out << "  }\n";
    out << "  locked = std::move(guard);\n";
    out << "  return true;\n";
    out << "}\n\n";
  } else {
    out << "struct LockedExternalFile {\n";
    out << "  int fd = -1;\n";
    out << "  LockedExternalFile() = default;\n";
    out << "  explicit LockedExternalFile(int value) : fd(value) {}\n";
    out << "  ~LockedExternalFile() { if (fd >= 0) close(fd); }\n";
    out << "  LockedExternalFile(const LockedExternalFile &) = delete;\n";
    out << "  LockedExternalFile &operator=(const LockedExternalFile &) = delete;\n";
    out << "  LockedExternalFile(LockedExternalFile &&other) noexcept : fd(other.fd) { other.fd = -1; }\n";
    out << "  LockedExternalFile &operator=(LockedExternalFile &&other) noexcept {\n";
    out << "    if (this != &other) {\n";
    out << "      if (fd >= 0) close(fd);\n";
    out << "      fd = other.fd;\n";
    out << "      other.fd = -1;\n";
    out << "    }\n";
    out << "    return *this;\n";
    out << "  }\n";
    out << "};\n\n";
    out << "std::vector<LockedExternalFile> g_locked_external_files;\n\n";
    out << "bool ReadLockedFileBytes(const std::filesystem::path &path, std::vector<unsigned char> &bytes, LockedExternalFile &locked) {\n";
    out << "  int fd = open(path.c_str(), O_RDONLY | O_CLOEXEC);\n";
    out << "  if (fd < 0) return false;\n";
    out << "  LockedExternalFile guard(fd);\n";
    out << "  struct stat st;\n";
    out << "  if (fstat(fd, &st) != 0 || !S_ISREG(st.st_mode) || st.st_size < 0) return false;\n";
    out << "  bytes.resize(static_cast<std::size_t>(st.st_size));\n";
    out << "  std::size_t offset = 0;\n";
    out << "  while (offset < bytes.size()) {\n";
    out << "    std::size_t remaining = bytes.size() - offset;\n";
    out << "    std::size_t request = remaining > static_cast<std::size_t>(std::numeric_limits<ssize_t>::max()) ?\n";
    out << "                          static_cast<std::size_t>(std::numeric_limits<ssize_t>::max()) : remaining;\n";
    out << "    ssize_t read_size = read(fd, bytes.data() + offset, request);\n";
    out << "    if (read_size < 0) {\n";
    out << "      if (errno == EINTR) continue;\n";
    out << "      return false;\n";
    out << "    }\n";
    out << "    if (read_size == 0) return false;\n";
    out << "    offset += static_cast<std::size_t>(read_size);\n";
    out << "  }\n";
    out << "  locked = std::move(guard);\n";
    out << "  return true;\n";
    out << "}\n\n";
  }
  out << "bool VerifyEmbeddedPayloads(const EmbeddedPayloadIntegrity *items, std::size_t count, std::string &error) {\n";
  out << "  std::array<std::uint8_t, 32> key = EmbeddedIntegrityKey();\n";
  out << "  for (std::size_t i = 0; i < count; ++i) {\n";
  out << "    std::array<std::uint8_t, 32> actual = PayloadMacData(key, \"EltenEmbeddedPayload:v1\", items[i].name, items[i].data, items[i].size, items[i].nonce, true);\n";
  out << "    std::array<std::uint8_t, 32> mask = PayloadMacData(key, \"EltenEmbeddedPayloadMask:v1\", items[i].name, items[i].data, items[i].size, items[i].nonce, false);\n";
  out << "    bool valid = true;\n";
  out << "    for (std::size_t j = 0; j < actual.size(); ++j) {\n";
  out << "      if (static_cast<std::uint8_t>(items[i].masked_mac[j] ^ mask[j]) != actual[j]) valid = false;\n";
  out << "    }\n";
  out << "    if (!valid) {\n";
  out << "      error = std::string(\"modified embedded payload: \") + items[i].name;\n";
  out << "      return false;\n";
  out << "    }\n";
  out << "  }\n";
  out << "  return true;\n";
  out << "}\n\n";
  out << "bool VerifyExternalFiles(const std::string &root, const ExternalFileIntegrity *items, std::size_t count, std::string &error) {\n";
  out << "  std::array<std::uint8_t, 32> key = EmbeddedIntegrityKey();\n";
  out << "  std::filesystem::path root_path = std::filesystem::u8path(root);\n";
  out << "  std::vector<LockedExternalFile> locked_files;\n";
  out << "  locked_files.reserve(count);\n";
  out << "  for (std::size_t i = 0; i < count; ++i) {\n";
  out << "    std::filesystem::path path = root_path / std::filesystem::path(items[i].path);\n";
  out << "    std::vector<unsigned char> bytes;\n";
  out << "    LockedExternalFile locked;\n";
  out << "    if (!ReadLockedFileBytes(path, bytes, locked)) {\n";
  out << "      error = std::string(\"cannot read package file: \") + items[i].path;\n";
  out << "      return false;\n";
  out << "    }\n";
  out << "    if (bytes.size() != items[i].size) {\n";
  out << "      error = std::string(\"modified package file: \") + items[i].path;\n";
  out << "      return false;\n";
  out << "    }\n";
  out << "    std::array<std::uint8_t, 32> actual = PayloadMacData(key, \"EltenExternalFile:v1\", items[i].path, bytes.data(), bytes.size(), items[i].nonce, true);\n";
  out << "    std::array<std::uint8_t, 32> mask = PayloadMacData(key, \"EltenExternalFileMask:v1\", items[i].path, bytes.data(), bytes.size(), items[i].nonce, false);\n";
  out << "    bool valid = true;\n";
  out << "    for (std::size_t j = 0; j < actual.size(); ++j) {\n";
  out << "      if (static_cast<std::uint8_t>(items[i].masked_mac[j] ^ mask[j]) != actual[j]) valid = false;\n";
  out << "    }\n";
  out << "    if (!valid) {\n";
  out << "      error = std::string(\"modified package file: \") + items[i].path;\n";
  out << "      return false;\n";
  out << "    }\n";
    out << "    locked_files.push_back(std::move(locked));\n";
  out << "  }\n";
  out << "  g_locked_external_files = std::move(locked_files);\n";
  out << "  return true;\n";
  out << "}\n\n";
  out << "std::mutex g_runtime_file_integrity_mutex;\n";
  out << "std::condition_variable g_runtime_file_integrity_cv;\n";
  out << "bool g_runtime_file_integrity_started = false;\n";
  out << "bool g_runtime_file_integrity_done = false;\n";
  out << "bool g_runtime_file_integrity_ok = false;\n";
  out << "std::string g_runtime_file_integrity_error;\n\n";
}

Options Parse(int argc, char **argv) {
  Options options;
  for (int i = 1; i < argc; ++i) {
    std::string key = argv[i];
    auto value = [&]() -> std::string {
      if (i + 1 >= argc) throw std::runtime_error("Missing value for " + key);
      return argv[++i];
    };
    if (key == "--root") options.root = fs::absolute(value());
    else if (key == "--package-root") options.packageRoot = fs::absolute(value());
    else if (key == "--ruby-root") options.rubyRoot = fs::absolute(value());
    else if (key == "--gem-lockfile") options.gemLockfile = fs::absolute(value());
    else if (key == "--arch") options.arch = value();
    else if (key == "--platform") options.platform = value();
    else if (key == "--runtime-output") options.runtimeOutput = fs::absolute(value());
    else if (key == "--native-output" || key == "--so-output") options.nativeOutput = fs::absolute(value());
    else if (key == "--compression") options.compression = Lower(value());
    else if (key == "--zstd-library") options.zstdLibrary = fs::absolute(value());
    else if (key == "--out") options.output = fs::absolute(value());
    else if (key == "--stamp-payload-out") options.stampPayloadOutput = fs::absolute(value());
    else if (key == "--no-copy-runtime-assets") options.copyRuntimeAssets = false;
    else if (key == "--prepare-only") options.prepareOnly = true;
    else throw std::runtime_error("Unknown option " + key);
  }
  if (options.root.empty()) throw std::runtime_error("missing --root");
  if (options.packageRoot.empty()) options.packageRoot = options.root;
  if (options.rubyRoot.empty()) throw std::runtime_error("missing --ruby-root");
  if (options.nativeOutput.empty()) throw std::runtime_error("missing --native-output");
  if (options.output.empty() && !options.prepareOnly) throw std::runtime_error("missing --out");
  if (!IsWindows(options) && !IsMacOS(options)) {
    throw std::runtime_error("unsupported --platform " + options.platform);
  }
  if (IsWindows(options) && options.runtimeOutput.empty()) {
    throw std::runtime_error("missing --runtime-output for Windows");
  }
  if (options.compression != "none" && options.compression != "zstd") {
    throw std::runtime_error("unsupported --compression " + options.compression);
  }
  return options;
}

std::string GeneratedZstdCode(const Options &options) {
  if (options.compression != "zstd") {
    return R"CPP(
std::vector<unsigned char> DecodePayload(const unsigned char *data, std::size_t stored_size, std::size_t) {
  return std::vector<unsigned char>(data, data + stored_size);
}
)CPP";
  }

  if (IsWindows(options)) {
    return R"CPP(
struct ZstdApi {
  using decompress_t = std::size_t(__cdecl *)(void *, std::size_t, const void *, std::size_t);
  using is_error_t = unsigned(__cdecl *)(std::size_t);
  using get_error_name_t = const char *(__cdecl *)(std::size_t);
  HMODULE dll = nullptr;
  decompress_t decompress = nullptr;
  is_error_t is_error = nullptr;
  get_error_name_t get_error_name = nullptr;
};

template <typename T>
T RequiredZstdProc(HMODULE dll, const char *name) {
  auto proc = reinterpret_cast<T>(GetProcAddress(dll, name));
  if (proc == nullptr) throw std::runtime_error(std::string("ZSTD export not found: ") + name);
  return proc;
}

const ZstdApi &GetZstdApi() {
  static ZstdApi api = [] {
    ZstdApi value;
    value.dll = LoadLibraryW(L"libzstd.dll");
    if (value.dll == nullptr) throw std::runtime_error("Cannot load libzstd.dll for embedded Ruby payloads");
    value.decompress = RequiredZstdProc<ZstdApi::decompress_t>(value.dll, "ZSTD_decompress");
    value.is_error = RequiredZstdProc<ZstdApi::is_error_t>(value.dll, "ZSTD_isError");
    value.get_error_name = RequiredZstdProc<ZstdApi::get_error_name_t>(value.dll, "ZSTD_getErrorName");
    return value;
  }();
  return api;
}

std::vector<unsigned char> DecodePayload(const unsigned char *data, std::size_t stored_size, std::size_t raw_size) {
  const ZstdApi &zstd = GetZstdApi();
  std::vector<unsigned char> output(raw_size == 0 ? 1 : raw_size);
  std::size_t result = zstd.decompress(output.data(), raw_size, data, stored_size);
  if (zstd.is_error(result) != 0 || result != raw_size) {
    const char *name = zstd.is_error(result) != 0 ? zstd.get_error_name(result) : "wrong decompressed size";
    throw std::runtime_error(std::string("ZSTD decompression failed: ") + (name == nullptr ? "unknown" : name));
  }
  output.resize(raw_size);
  return output;
}
)CPP";
  }

  return R"CPP(
struct ZstdApi {
  using decompress_t = std::size_t (*)(void *, std::size_t, const void *, std::size_t);
  using is_error_t = unsigned (*)(std::size_t);
  using get_error_name_t = const char *(*)(std::size_t);
  void *dll = nullptr;
  decompress_t decompress = nullptr;
  is_error_t is_error = nullptr;
  get_error_name_t get_error_name = nullptr;
};

template <typename T>
T RequiredZstdProc(void *dll, const char *name) {
  auto proc = reinterpret_cast<T>(dlsym(dll, name));
  if (proc == nullptr) throw std::runtime_error(std::string("ZSTD export not found: ") + name);
  return proc;
}

std::string ExecutableDirectory() {
  uint32_t size = 0;
  _NSGetExecutablePath(nullptr, &size);
  std::vector<char> buffer(size + 1, '\0');
  if (_NSGetExecutablePath(buffer.data(), &size) != 0) return "";

  std::error_code ec;
  std::filesystem::path executable = std::filesystem::weakly_canonical(buffer.data(), ec);
  if (ec) {
    ec.clear();
    executable = std::filesystem::absolute(buffer.data(), ec);
  }
  if (ec) executable = std::filesystem::path(buffer.data());
  return executable.parent_path().generic_string();
}

std::vector<std::string> ZstdCandidates() {
  std::vector<std::string> candidates;
  std::string executable_dir = ExecutableDirectory();
  if (!executable_dir.empty()) {
    std::filesystem::path dir(executable_dir);
    candidates.push_back((dir / ".." / "Resources" / "bin" / "osx" / "libzstd.dylib").lexically_normal().generic_string());
    candidates.push_back((dir / "bin" / "osx" / "libzstd.dylib").lexically_normal().generic_string());
  }
  candidates.push_back("@executable_path/../Resources/bin/osx/libzstd.dylib");
  candidates.push_back("@executable_path/bin/osx/libzstd.dylib");
  candidates.push_back("libzstd.dylib");
  candidates.push_back("./bin/osx/libzstd.dylib");
  return candidates;
}

const ZstdApi &GetZstdApi() {
  static ZstdApi api = [] {
    ZstdApi value;
    std::string errors;
    for (const std::string &candidate : ZstdCandidates()) {
      dlerror();
      value.dll = dlopen(candidate.c_str(), RTLD_NOW | RTLD_LOCAL);
      if (value.dll != nullptr) break;
      const char *error = dlerror();
      errors += "  ";
      errors += candidate;
      errors += ": ";
      errors += error == nullptr ? "unknown dlopen error" : error;
      errors += "\n";
    }
    if (value.dll == nullptr) {
      throw std::runtime_error("Cannot load libzstd.dylib for embedded Ruby payloads:\n" + errors);
    }
    value.decompress = RequiredZstdProc<ZstdApi::decompress_t>(value.dll, "ZSTD_decompress");
    value.is_error = RequiredZstdProc<ZstdApi::is_error_t>(value.dll, "ZSTD_isError");
    value.get_error_name = RequiredZstdProc<ZstdApi::get_error_name_t>(value.dll, "ZSTD_getErrorName");
    return value;
  }();
  return api;
}

std::vector<unsigned char> DecodePayload(const unsigned char *data, std::size_t stored_size, std::size_t raw_size) {
  const ZstdApi &zstd = GetZstdApi();
  std::vector<unsigned char> output(raw_size == 0 ? 1 : raw_size);
  std::size_t result = zstd.decompress(output.data(), raw_size, data, stored_size);
  if (zstd.is_error(result) != 0 || result != raw_size) {
    const char *name = zstd.is_error(result) != 0 ? zstd.get_error_name(result) : "wrong decompressed size";
    throw std::runtime_error(std::string("ZSTD decompression failed: ") + (name == nullptr ? "unknown" : name));
  }
  output.resize(raw_size);
  return output;
}
)CPP";
}

std::string Generate(const Options &options) {
  CopyWindowsRuntimeFiles(options);
  std::map<std::string, std::string> nativeMap = PrepareNativeFiles(options);
  ResolveWindowsMsysSupportDllDependencies(options);
  BuildDefaultSoundThemePackage(options);
  BuildNvdaAddonPackage(options);

  ZstdApi zstd;
  ZstdApi *zstdPtr = nullptr;
  if (options.compression == "zstd") {
    zstd = LoadZstd(options);
    zstdPtr = &zstd;
  }

  std::vector<RubyEntry> rbEntries = EmbeddedRubyEntries(options);
  std::vector<unsigned char> integrityKey = RandomBytes(32);
  std::vector<std::vector<unsigned char>> integrityKeyShards = IntegrityKeyShards(integrityKey);

  std::ostringstream out;
  out << GeneratedIncludes(options);
  out << "#ifndef ELTEN_EMBEDDED_ZSTD\n#define ELTEN_EMBEDDED_ZSTD 0\n#endif\n";
  if (options.compression == "zstd") {
    out << "#if ELTEN_EMBEDDED_ZSTD != 1\n#error embedded assets were generated with ZSTD compression, but ELTEN_EMBEDDED_ZSTD is disabled\n#endif\n";
  } else {
    out << "#if ELTEN_EMBEDDED_ZSTD != 0\n#error embedded assets were generated without compression, but ELTEN_EMBEDDED_ZSTD is enabled\n#endif\n";
  }
  out << "\nnamespace {\nusing EltenLauncher::EmbeddedRubyApi;\nusing EltenLauncher::RuntimeFileIntegrityFailureHandler;\nusing EltenLauncher::RubyValue;\n\n";
  out << "RubyValue NewText(const EmbeddedRubyApi &api, const char *value) {\n";
  out << "  const long size = static_cast<long>(std::strlen(value));\n";
  out << "  return api.utf8_str_new != nullptr ? api.utf8_str_new(value, size) : api.str_new(value, size);\n";
  out << "}\n\n";
  out << "void KeepRubyObject(const EmbeddedRubyApi &api, RubyValue object) {\n";
  out << "  if (api.gc_register_mark_object != nullptr) api.gc_register_mark_object(object);\n";
  out << "}\n\n";
  out << GeneratedZstdCode(options) << "\n";
  out << "RubyValue NewBinary(const EmbeddedRubyApi &api, const unsigned char *data, std::size_t stored_size, std::size_t raw_size) {\n";
  out << "  std::vector<unsigned char> payload = DecodePayload(data, stored_size, raw_size);\n";
  out << "  return api.str_new(reinterpret_cast<const char *>(payload.data()), static_cast<long>(payload.size()));\n";
  out << "}\n\n";
  out << "RubyValue NewRangeArray(const EmbeddedRubyApi &api, std::size_t offset, std::size_t size) {\n";
  out << "  RubyValue range = api.ary_new();\n";
  out << "  KeepRubyObject(api, range);\n";
  out << "  api.ary_push(range, api.ll2inum(static_cast<long long>(offset)));\n";
  out << "  api.ary_push(range, api.ll2inum(static_cast<long long>(size)));\n";
  out << "  return range;\n";
  out << "}\n\n";
  out << "void AddRubyFile(const EmbeddedRubyApi &api, RubyValue files, RubyValue names,\n";
  out << "                 const char *key, const char *display,\n";
  out << "                 std::size_t offset, std::size_t raw_size,\n";
  out << "                 const char *const *aliases, std::size_t alias_count) {\n";
  out << "  RubyValue entry = api.ary_new();\n";
  out << "  RubyValue names_entry = api.ary_new();\n";
  out << "  KeepRubyObject(api, entry);\n";
  out << "  KeepRubyObject(api, names_entry);\n";
  out << "  RubyValue display_value = NewText(api, display);\n";
  out << "  RubyValue offset_value = api.ll2inum(static_cast<long long>(offset));\n";
  out << "  RubyValue size_value = api.ll2inum(static_cast<long long>(raw_size));\n";
  out << "  RubyValue key_value = NewText(api, key);\n";
  out << "  KeepRubyObject(api, display_value);\n";
  out << "  KeepRubyObject(api, key_value);\n";
  out << "  api.ary_push(entry, display_value);\n";
  out << "  api.ary_push(entry, offset_value);\n";
  out << "  api.ary_push(entry, size_value);\n";
  out << "  api.ary_push(names_entry, key_value);\n";
  out << "  api.hash_aset(files, key_value, entry);\n";
  out << "  api.hash_aset(names, key_value, names_entry);\n";
  out << "  for (std::size_t i = 0; i < alias_count; ++i) {\n";
  out << "    RubyValue alias_value = NewText(api, aliases[i]);\n";
  out << "    KeepRubyObject(api, alias_value);\n";
  out << "    api.ary_push(names_entry, alias_value);\n";
  out << "    api.hash_aset(files, alias_value, entry);\n";
  out << "    api.hash_aset(names, alias_value, names_entry);\n";
  out << "  }\n";
  out << "}\n\n";
  out << "const char *ReadManifestCString(const unsigned char *data, std::size_t size, std::size_t &offset) {\n";
  out << "  if (offset >= size) throw std::runtime_error(\"embedded Ruby manifest is truncated\");\n";
  out << "  const char *start = reinterpret_cast<const char *>(data + offset);\n";
  out << "  while (offset < size && data[offset] != 0) ++offset;\n";
  out << "  if (offset >= size) throw std::runtime_error(\"embedded Ruby manifest string is unterminated\");\n";
  out << "  ++offset;\n";
  out << "  return start;\n";
  out << "}\n\n";
  out << "std::uint64_t ReadManifestU64(const unsigned char *data, std::size_t size, std::size_t &offset) {\n";
  out << "  if (size - offset < 8) throw std::runtime_error(\"embedded Ruby manifest integer is truncated\");\n";
  out << "  std::uint64_t value = 0;\n";
  out << "  for (int shift = 0; shift < 64; shift += 8) value |= static_cast<std::uint64_t>(data[offset++]) << shift;\n";
  out << "  return value;\n";
  out << "}\n\n";
  out << "RubyValue RegisterRubyManifest(const EmbeddedRubyApi &api, RubyValue files, RubyValue names,\n";
  out << "                               const unsigned char *data, std::size_t size) {\n";
  out << "  std::size_t offset = 0;\n";
  out << "  const char *magic = ReadManifestCString(data, size, offset);\n";
  out << "  if (std::strcmp(magic, \"EltenRubyBlobManifest:v1\") != 0) throw std::runtime_error(\"embedded Ruby manifest has invalid magic\");\n";
  out << "  std::uint64_t count = ReadManifestU64(data, size, offset);\n";
  out << "  for (std::uint64_t item = 0; item < count; ++item) {\n";
  out << "    const char *kind = ReadManifestCString(data, size, offset);\n";
  out << "    if (std::strcmp(kind, \"rb\") != 0) throw std::runtime_error(\"embedded Ruby manifest expected rb entry\");\n";
  out << "    const char *key = ReadManifestCString(data, size, offset);\n";
  out << "    const char *display = ReadManifestCString(data, size, offset);\n";
  out << "    std::uint64_t body_offset = ReadManifestU64(data, size, offset);\n";
  out << "    std::uint64_t body_size = ReadManifestU64(data, size, offset);\n";
  out << "    std::uint64_t alias_count = ReadManifestU64(data, size, offset);\n";
  out << "    if (alias_count > static_cast<std::uint64_t>(std::numeric_limits<std::size_t>::max())) {\n";
  out << "      throw std::runtime_error(\"embedded Ruby manifest alias count is too large\");\n";
  out << "    }\n";
  out << "    std::vector<const char *> aliases;\n";
  out << "    aliases.reserve(static_cast<std::size_t>(alias_count));\n";
  out << "    for (std::uint64_t alias_index = 0; alias_index < alias_count; ++alias_index) {\n";
  out << "      aliases.push_back(ReadManifestCString(data, size, offset));\n";
  out << "    }\n";
  out << "    AddRubyFile(api, files, names, key, display, static_cast<std::size_t>(body_offset),\n";
  out << "                static_cast<std::size_t>(body_size), aliases.data(), aliases.size());\n";
  out << "  }\n";
  out << "  const char *kind = ReadManifestCString(data, size, offset);\n";
  out << "  if (std::strcmp(kind, \"filelist\") != 0) throw std::runtime_error(\"embedded Ruby manifest expected filelist entry\");\n";
  out << "  std::uint64_t filelist_offset = ReadManifestU64(data, size, offset);\n";
  out << "  std::uint64_t filelist_size = ReadManifestU64(data, size, offset);\n";
  out << "  return filelist_size == 0 ? 0 : NewRangeArray(api, static_cast<std::size_t>(filelist_offset), static_cast<std::size_t>(filelist_size));\n";
  out << "}\n\n";
  out << "void AddNativeExtension(const EmbeddedRubyApi &api, RubyValue extensions, const char *key, const char *path) {\n";
  out << "  RubyValue key_value = NewText(api, key);\n";
  out << "  RubyValue path_value = NewText(api, path);\n";
  out << "  KeepRubyObject(api, key_value);\n";
  out << "  KeepRubyObject(api, path_value);\n";
  out << "  api.hash_aset(extensions, key_value, path_value);\n";
  out << "}\n\n";
  out << "void AddEmbeddedResource(const EmbeddedRubyApi &api, RubyValue resources, const char *key,\n";
  out << "                         const unsigned char *data, std::size_t stored_size, std::size_t raw_size) {\n";
  out << "  RubyValue key_value = NewText(api, key);\n";
  out << "  RubyValue value = NewBinary(api, data, stored_size, raw_size);\n";
  out << "  KeepRubyObject(api, key_value);\n";
  out << "  KeepRubyObject(api, value);\n";
  out << "  api.hash_aset(resources, key_value, value);\n";
  out << "}\n\n";
  WriteIntegritySupport(out, integrityKeyShards, options);

  std::vector<IntegrityPayloadEntry> integrityPayloads;
  std::vector<GeneratedResourceEntry> generatedResources;
  std::vector<unsigned char> rubyBlob;
  std::vector<unsigned char> rubyManifest;
  AppendCString(rubyManifest, "EltenRubyBlobManifest:v1");
  AppendU64LE(rubyManifest, static_cast<std::uint64_t>(rbEntries.size()));
  for (const RubyEntry &entry : rbEntries) {
    std::vector<unsigned char> data = SanitizeRubyPayload(options, entry.path, ReadFile(entry.path));
    std::size_t offset = AppendBlobRange(rubyBlob, data);
    std::vector<std::string> aliases;
    for (const std::string &alias : entry.aliases) {
      if (Lower(alias) != Lower(entry.key)) aliases.push_back(Lower(alias));
    }
    std::sort(aliases.begin(), aliases.end());
    aliases.erase(std::unique(aliases.begin(), aliases.end()), aliases.end());

    AppendCString(rubyManifest, "rb");
    AppendCString(rubyManifest, Lower(entry.key));
    AppendCString(rubyManifest, entry.key);
    AppendU64LE(rubyManifest, static_cast<std::uint64_t>(offset));
    AppendU64LE(rubyManifest, static_cast<std::uint64_t>(data.size()));
    AppendU64LE(rubyManifest, static_cast<std::uint64_t>(aliases.size()));
    for (const std::string &alias : aliases) AppendCString(rubyManifest, alias);
  }

  std::vector<unsigned char> filelist;
  std::size_t filelistOffset = 0;
  std::size_t filelistSize = 0;
  fs::path filelistPath = options.root / "filelist";
  if (fs::is_regular_file(filelistPath)) {
    filelist = ReadFile(filelistPath);
    filelistOffset = AppendBlobRange(rubyBlob, filelist);
    filelistSize = filelist.size();
  }
  AppendCString(rubyManifest, "filelist");
  AppendU64LE(rubyManifest, static_cast<std::uint64_t>(filelistOffset));
  AppendU64LE(rubyManifest, static_cast<std::uint64_t>(filelistSize));

  std::vector<unsigned char> rubyBlobStored = StoredPayload(options, zstdPtr, rubyBlob);
  if (!options.stampPayloadOutput.empty()) WriteBytes(options.stampPayloadOutput, rubyBlobStored);
  std::uint32_t rubyBlobNonce = RandomU32();
  WriteByteArray(out, "ruby_blob_data", rubyBlobStored);
  WriteByteArray(out, "ruby_blob_mac", MaskedPayloadMac(integrityKey, "ruby-blob", rubyBlobStored, rubyBlobNonce));
  integrityPayloads.push_back({"ruby-blob", "ruby_blob_data", rubyBlobStored.size(), "ruby_blob_mac", rubyBlobNonce});

  std::uint32_t rubyManifestNonce = RandomU32();
  WriteByteArray(out, "ruby_manifest_data", rubyManifest);
  WriteByteArray(out, "ruby_manifest_mac", MaskedPayloadMac(integrityKey, "ruby-manifest", rubyManifest, rubyManifestNonce));
  integrityPayloads.push_back({"ruby-manifest", "ruby_manifest_data", rubyManifest.size(), "ruby_manifest_mac", rubyManifestNonce});

  int resourceIndex = 0;
  for (const ResourceEntry &resource : EmbeddedResourceEntries(options)) {
    std::vector<unsigned char> stored = StoredPayload(options, zstdPtr, resource.data);
    std::string dataName = "resource_data_" + std::to_string(resourceIndex++);
    std::string macName = dataName + "_mac";
    std::uint32_t nonce = RandomU32();
    WriteByteArray(out, dataName, stored);
    WriteByteArray(out, macName, MaskedPayloadMac(integrityKey, "resource:" + resource.name, stored, nonce));
    integrityPayloads.push_back({"resource:" + resource.name, dataName, stored.size(), macName, nonce});
    generatedResources.push_back({resource.name, dataName, stored.size(), resource.data.size()});
  }

  std::vector<IntegrityFileEntry> externalIntegrity;
  int externalIndex = 0;
  for (const fs::path &path : RecursiveRegularFiles(RuntimePackageRoot(options))) {
    std::vector<unsigned char> filePayload = ReadFile(path);
    std::string fileName = Relative(path, options.packageRoot);
    std::string fileMacName = "external_mac_" + std::to_string(externalIndex++);
    std::uint32_t fileNonce = RandomU32();
    WriteByteArray(out, fileMacName, MaskedExternalFileMac(integrityKey, fileName, filePayload, fileNonce));
    externalIntegrity.push_back({fileName, filePayload.size(), fileMacName, fileNonce});
  }

  out << "static const EmbeddedPayloadIntegrity embedded_integrity[] = {\n";
  if (integrityPayloads.empty()) {
    out << "  {nullptr, nullptr, 0, nullptr, 0},\n";
  } else {
    for (const IntegrityPayloadEntry &entry : integrityPayloads) {
      out << "  {\"" << CppString(entry.name) << "\", " << entry.dataName << ", "
          << entry.size << ", " << entry.macName << ", " << entry.nonce << "u},\n";
    }
  }
  out << "};\n";
  out << "static const std::size_t embedded_integrity_count = " << integrityPayloads.size() << ";\n\n";

  out << "static const ExternalFileIntegrity external_integrity[] = {\n";
  if (externalIntegrity.empty()) {
    out << "  {nullptr, 0, nullptr, 0},\n";
  } else {
    for (const IntegrityFileEntry &entry : externalIntegrity) {
      out << "  {\"" << CppString(entry.path) << "\", " << entry.size << ", "
          << entry.macName << ", " << entry.nonce << "u},\n";
    }
  }
  out << "};\n";
  out << "static const std::size_t external_integrity_count = " << externalIntegrity.size() << ";\n\n";
  out << "void RunRuntimeFileIntegrityCheck(std::string root, RuntimeFileIntegrityFailureHandler failure_handler) {\n";
  out << "  std::string error;\n";
  out << "  bool ok = VerifyExternalFiles(root, external_integrity, external_integrity_count, error);\n";
  out << "  {\n";
  out << "    std::lock_guard<std::mutex> lock(g_runtime_file_integrity_mutex);\n";
  out << "    g_runtime_file_integrity_done = true;\n";
  out << "    g_runtime_file_integrity_ok = ok;\n";
  out << "    g_runtime_file_integrity_error = error;\n";
  out << "  }\n";
  out << "  g_runtime_file_integrity_cv.notify_all();\n";
  out << "  if (!ok && failure_handler != nullptr) {\n";
  out << "    failure_handler(std::string(\"Elten launcher integrity check failed: \") + error);\n";
  out << "  }\n";
  out << "}\n\n";
  out << "}\n\nnamespace EltenLauncher {\n";
  out << "bool VerifyEmbeddedPayloadIntegrity(const std::string &root, std::string &error) {\n";
  out << "  (void)root;\n";
  out << "  return VerifyEmbeddedPayloads(embedded_integrity, embedded_integrity_count, error);\n";
  out << "}\n\n";
  out << "std::size_t EmbeddedRubyPayloadSize() {\n";
  out << "  return sizeof(ruby_blob_data);\n";
  out << "}\n\n";
  out << "std::uint8_t EmbeddedRubyPayloadByte(std::size_t index) {\n";
  out << "  return static_cast<std::uint8_t>(ruby_blob_data[index % sizeof(ruby_blob_data)]);\n";
  out << "}\n\n";
  out << "void StartRuntimeFileIntegrityCheck(const std::string &root, RuntimeFileIntegrityFailureHandler failure_handler) {\n";
  out << "  {\n";
  out << "    std::lock_guard<std::mutex> lock(g_runtime_file_integrity_mutex);\n";
  out << "    if (g_runtime_file_integrity_started) return;\n";
  out << "    g_runtime_file_integrity_started = true;\n";
  out << "  }\n";
  out << "  std::thread(RunRuntimeFileIntegrityCheck, root, failure_handler).detach();\n";
  out << "}\n\n";
  out << "void WaitForRuntimeFileIntegrity() {\n";
  out << "  std::unique_lock<std::mutex> lock(g_runtime_file_integrity_mutex);\n";
  out << "  if (!g_runtime_file_integrity_started) throw std::runtime_error(\"Runtime file integrity check was not started\");\n";
  out << "  g_runtime_file_integrity_cv.wait(lock, [] { return g_runtime_file_integrity_done; });\n";
  out << "  if (!g_runtime_file_integrity_ok) {\n";
  out << "    throw std::runtime_error(std::string(\"Elten launcher integrity check failed: \") + g_runtime_file_integrity_error);\n";
  out << "  }\n";
  out << "}\n\n";
  out << "void RegisterEmbeddedAssets(const EmbeddedRubyApi &api) {\n";
  out << "  RubyValue files = api.hash_new();\n";
  out << "  RubyValue names = api.hash_new();\n";
  out << "  RubyValue extensions = api.hash_new();\n";
  out << "  RubyValue resources = api.hash_new();\n";
  out << "  KeepRubyObject(api, files);\n";
  out << "  KeepRubyObject(api, names);\n";
  out << "  KeepRubyObject(api, extensions);\n";
  out << "  KeepRubyObject(api, resources);\n";
  out << "  api.gv_set(\"$ELTEN_EMBEDDED_RB\", files);\n";
  out << "  api.gv_set(\"$ELTEN_EMBEDDED_RB_NAMES\", names);\n";
  out << "  api.gv_set(\"$ELTEN_EMBEDDED_SO\", extensions);\n";
  out << "  api.gv_set(\"$ELTEN_EMBEDDED_RESOURCES\", resources);\n";
  out << "  RubyValue ruby_blob = NewBinary(api, ruby_blob_data, " << rubyBlobStored.size() << ", " << rubyBlob.size() << ");\n";
  out << "  KeepRubyObject(api, ruby_blob);\n";
  out << "  api.gv_set(\"$ELTEN_EMBEDDED_RB_BLOB\", ruby_blob);\n";
  out << "  RubyValue filelist_range = RegisterRubyManifest(api, files, names, ruby_manifest_data, sizeof(ruby_manifest_data));\n";
  out << "  if (filelist_range != 0) {\n";
  out << "  api.gv_set(\"$ELTEN_EMBEDDED_FILELIST_RANGE\", filelist_range);\n";
  out << "  }\n";
  for (const auto &item : nativeMap) {
    out << "  AddNativeExtension(api, extensions, \"" << CppString(item.first) << "\", \""
        << CppString(item.second) << "\");\n";
  }
  for (const GeneratedResourceEntry &resource : generatedResources) {
    out << "  AddEmbeddedResource(api, resources, \"" << CppString(resource.name) << "\", "
        << resource.dataName << ", " << resource.storedSize << ", " << resource.rawSize << ");\n";
  }
  out << "}\n}\n";

  std::cerr << "Prepared launcher assets for " << RuntimePackagePathLabel(options)
            << ": embedded " << rbEntries.size() << " Ruby files, mapped "
            << nativeMap.size() << " native extension names, embedded "
            << generatedResources.size() << " resources"
            << " (compression: " << options.compression << ").\n";
  return out.str();
}

} // namespace

int main(int argc, char **argv) {
  try {
    Options options = Parse(argc, argv);
    if (options.prepareOnly) {
      CopyWindowsRuntimeFiles(options);
      PrepareNativeFiles(options);
      ResolveWindowsMsysSupportDllDependencies(options);
      BuildDefaultSoundThemePackage(options);
      BuildNvdaAddonPackage(options);
      return 0;
    }
    WriteFile(options.output, Generate(options));
    return 0;
  } catch (const std::exception &error) {
    std::cerr << "generate_assets: " << error.what() << "\n";
    return 1;
  }
}
