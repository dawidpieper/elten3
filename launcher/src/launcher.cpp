#include "embedded_assets.hpp"
#include "build_info.h"
#include "platform.h"
#include "stamp.hpp"

#if defined(_WIN32)
#include <windows.h>
#endif

#include <algorithm>
#include <chrono>
#include <cctype>
#include <cstdio>
#include <cstdlib>
#include <ctime>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

#ifndef ELTEN_FORCE_DEVELOPER_MODE
#define ELTEN_FORCE_DEVELOPER_MODE 0
#endif

#ifndef ELTEN_BUILD_ID
#define ELTEN_BUILD_ID ""
#endif

#ifndef ELTEN_BUILD_DATE
#define ELTEN_BUILD_DATE 0
#endif

namespace fs = std::filesystem;

namespace EltenLauncher {
namespace {

LauncherDiagnostics g_diagnostics;
const auto g_trace_start = std::chrono::steady_clock::now();

std::string ToLower(std::string value) {
  std::transform(value.begin(), value.end(), value.begin(), [](unsigned char ch) {
    return static_cast<char>(std::tolower(ch));
  });
  return value;
}

std::string RubyQuote(const std::string &value) {
  std::string result = "\"";
  for (unsigned char c : value) {
    switch (c) {
      case '\\': result += "\\\\"; break;
      case '"': result += "\\\""; break;
      case '\n': result += "\\n"; break;
      case '\r': result += "\\r"; break;
      case '\t': result += "\\t"; break;
      default:
        if (c < 0x20 || c >= 0x7f) {
          char buffer[5];
          std::snprintf(buffer, sizeof(buffer), "\\x%02X", c);
          result += buffer;
        } else {
          result.push_back(static_cast<char>(c));
        }
        break;
    }
  }
  result += "\"";
  return result;
}

std::string RubyQuote(const char *value) {
  return RubyQuote(std::string(value == nullptr ? "" : value));
}

std::string RubyQuote(const fs::path &path) {
  return RubyQuote(PlatformPathToUtf8(path));
}

std::string RubyNullablePath(const fs::path &path) {
  return path.empty() ? "nil" : RubyQuote(path);
}

std::string RubyArgvArray(const std::vector<std::string> &args) {
  std::string result = "[";
  for (std::size_t i = 1; i < args.size(); ++i) {
    if (i > 1) result += ", ";
    result += RubyQuote(args[i]);
  }
  result += "]";
  return result;
}

std::string RuntimeDirForRuby() {
  return std::string("bin/") + ELTEN_RUNTIME_DIR_NAME;
}

bool IsOptionName(const std::string &arg, const char *name) {
  std::string value = ToLower(arg);
  std::string option = ToLower(name);
  return value == "/" + option || value == "-" + option || value == "--" + option;
}

bool IsDeveloperModeSwitch(const std::string &arg) {
  return IsOptionName(arg, "developer") || IsOptionName(arg, "dev");
}

bool HasDeveloperModeSwitch(const std::vector<std::string> &args) {
  for (std::size_t i = 1; i < args.size(); ++i) {
    if (IsDeveloperModeSwitch(args[i])) return true;
  }
  return false;
}

bool LauncherDeveloperMode(const std::vector<std::string> &args) {
#if ELTEN_FORCE_DEVELOPER_MODE
  (void)args;
  return true;
#else
  return HasDeveloperModeSwitch(args);
#endif
}

void EnsureDeveloperModeArgument(std::vector<std::string> &args, bool developerMode) {
  if (!developerMode || HasDeveloperModeSwitch(args)) return;
  if (args.empty()) args.push_back("elten");
  args.push_back("--developer");
}

bool StartsWithOptionAssignment(const std::string &arg, const char *name, std::string &value) {
  std::string lower = ToLower(arg);
  std::string option = ToLower(name);
  for (const std::string &prefix : {"/", "-", "--"}) {
    std::string full = prefix + option;
    if (lower.size() <= full.size()) continue;
    if (lower.compare(0, full.size(), full) != 0) continue;
    char separator = lower[full.size()];
    if (separator != '=' && separator != ':') continue;
    value = arg.substr(full.size() + 1);
    return true;
  }
  return false;
}

fs::path NormalizeDiagnosticPath(const fs::path &root, const std::string &value, const char *option) {
  if (value.empty()) throw std::runtime_error(std::string(option) + " requires a path");
  fs::path path = PlatformPathFromUtf8(value);
  if (path.is_relative()) path = root / path;
  return fs::absolute(path);
}

bool TryReadDiagnosticOption(const fs::path &root, const std::vector<std::string> &args, std::size_t &index,
                             const char *name, fs::path &target) {
  std::string assigned;
  if (StartsWithOptionAssignment(args[index], name, assigned)) {
    target = NormalizeDiagnosticPath(root, assigned, name);
    return true;
  }
  if (!IsOptionName(args[index], name)) return false;
  if (index + 1 >= args.size()) throw std::runtime_error(std::string(name) + " requires a path");
  ++index;
  target = NormalizeDiagnosticPath(root, args[index], name);
  return true;
}

LauncherDiagnostics ParseLauncherDiagnostics(const fs::path &root, const std::vector<std::string> &args) {
  LauncherDiagnostics diagnostics;
  for (std::size_t i = 1; i < args.size(); ++i) {
    if (TryReadDiagnosticOption(root, args, i, "launcher-log", diagnostics.logPath)) continue;
    if (TryReadDiagnosticOption(root, args, i, "launcher-trace", diagnostics.tracePath)) continue;
    if (TryReadDiagnosticOption(root, args, i, "launcher-bootstrap", diagnostics.bootstrapPath)) continue;
  }
  return diagnostics;
}

void EnsureParentDirectory(const fs::path &path) {
  fs::path parent = path.parent_path();
  if (!parent.empty()) fs::create_directories(parent);
}

std::string Timestamp() {
  std::time_t now = std::time(nullptr);
  char buffer[64] = {};
#if defined(_WIN32)
  std::tm tm = {};
  localtime_s(&tm, &now);
  std::strftime(buffer, sizeof(buffer), "%Y-%m-%d %H:%M:%S", &tm);
#else
  std::tm tm = {};
  localtime_r(&now, &tm);
  std::strftime(buffer, sizeof(buffer), "%Y-%m-%d %H:%M:%S", &tm);
#endif
  return buffer;
}

void WriteFile(const fs::path &path, const std::string &content) {
  if (path.empty()) return;
  EnsureParentDirectory(path);
  std::ofstream file(path, std::ios::binary);
  if (!file) return;
  file.write(content.data(), static_cast<std::streamsize>(content.size()));
}

void WriteFatalLog(const std::string &message) {
  if (g_diagnostics.logPath.empty()) return;
  EnsureParentDirectory(g_diagnostics.logPath);
  std::ofstream file(g_diagnostics.logPath, std::ios::binary | std::ios::app);
  if (!file) return;
  file << Timestamp() << "\n" << message << "\n";
}

void WriteTraceLog(const std::string &message) {
  if (g_diagnostics.tracePath.empty()) return;
  EnsureParentDirectory(g_diagnostics.tracePath);
  std::ofstream file(g_diagnostics.tracePath, std::ios::binary | std::ios::app);
  if (!file) return;
  double elapsed_ms = std::chrono::duration<double, std::milli>(
      std::chrono::steady_clock::now() - g_trace_start).count();
  file << Timestamp() << " +" << std::fixed << std::setprecision(2) << elapsed_ms << "ms " << message << "\n";
}

void FatalRuntimeFileIntegrityFailure(const std::string &message) {
  try {
    WriteFatalLog(message);
    PlatformSuspendOtherThreadsForFatalError();
    PlatformShowFatal(message);
  } catch (...) {
  }
  std::_Exit(1);
}

std::string RubyExceptionMessage(RubyApi &ruby) {
  if (ruby.rb_errinfo != nullptr) {
    RubyValue error = ruby.rb_errinfo();
    std::ostringstream stream;
    stream << "Ruby evaluation failed; rb_errinfo=0x" << std::hex << error;
    if (error != 0 && error != 8 && ruby.rb_intern != nullptr && ruby.rb_funcallv != nullptr && ruby.rb_string_value_cstr != nullptr) {
      RubyValue full = ruby.rb_funcallv(error, ruby.rb_intern("full_message"), 0, nullptr);
      char *full_cstr = ruby.rb_string_value_cstr(&full);
      if (full_cstr != nullptr && full_cstr[0] != '\0') return full_cstr;
    }
    if (error != 0 && error != 8 && ruby.rb_obj_as_string != nullptr && ruby.rb_string_value_cstr != nullptr) {
      RubyValue text = ruby.rb_obj_as_string(error);
      char *cstr = ruby.rb_string_value_cstr(&text);
      if (cstr != nullptr && cstr[0] != '\0') return cstr;
    }
    return stream.str();
  }
  return "Ruby evaluation failed without rb_errinfo";
}

bool RubyExceptionIsSystemExit(RubyApi &ruby) {
  if (ruby.rb_eval_string_protect == nullptr || ruby.rb_string_value_cstr == nullptr) return false;
  int state = 0;
  RubyValue result = ruby.rb_eval_string_protect(
      "begin\n"
      "  e = $!\n"
      "  e.is_a?(SystemExit) ? '1' : '0'\n"
      "rescue Exception\n"
      "  '0'\n"
      "end\n",
      &state);
  if (state != 0) return false;
  char *text = ruby.rb_string_value_cstr(&result);
  return text != nullptr && text[0] == '1' && text[1] == '\0';
}

void VerifyYJITEnabled(RubyApi &ruby) {
  if (!PlatformSupportsYJIT()) return;
  if (ruby.rb_eval_string_protect == nullptr || ruby.rb_string_value_cstr == nullptr) {
    throw std::runtime_error("YJIT is supported by this platform, but Ruby verification API is unavailable");
  }

  int state = 0;
  RubyValue result = ruby.rb_eval_string_protect(
      "begin\n"
      "  defined?(RubyVM::YJIT) && RubyVM::YJIT.respond_to?(:enabled?) && RubyVM::YJIT.enabled? ? '1' : '0'\n"
      "rescue Exception\n"
      "  '0'\n"
      "end\n",
      &state);
  if (state != 0) {
    WriteFatalLog(RubyExceptionMessage(ruby));
    throw std::runtime_error("YJIT startup verification failed");
  }

  char *text = ruby.rb_string_value_cstr(&result);
  if (text == nullptr || text[0] != '1' || text[1] != '\0') {
    throw std::runtime_error("YJIT is supported by this platform, but Ruby did not enable it");
  }
}

void WriteRubyExceptionLog(RubyApi &ruby, const std::string &message = std::string()) {
  if (g_diagnostics.logPath.empty()) return;
  EnsureParentDirectory(g_diagnostics.logPath);
  WriteFatalLog(message.empty() ? RubyExceptionMessage(ruby) : message);

  std::string script;
  script += "begin\n";
  script += "  e = $!\n";
  script += "  File.open(" + RubyQuote(g_diagnostics.logPath) + ", 'ab') do |file|\n";
  script += "    file.write(Time.now.to_s)\n";
  script += "    file.write(\"\\n\")\n";
  script += "    if e\n";
  script += "      file.write(e.class.name)\n";
  script += "      file.write(': ')\n";
  script += "      file.write(e.message.to_s)\n";
  script += "      file.write(\"\\n\")\n";
  script += "      file.write(Array(e.backtrace).join(\"\\n\"))\n";
  script += "    else\n";
  script += "      file.write('Ruby evaluation failed without $!')\n";
  script += "    end\n";
  script += "    file.write(\"\\n\")\n";
  script += "    file.flush\n";
  script += "  end\n";
  script += "rescue Exception\n";
  script += "end\n";
  int ignored = 0;
  ruby.rb_eval_string_protect(script.c_str(), &ignored);
}

void RequireEncodingDatabase(RubyApi &ruby, const fs::path &runtimeDir) {
  if (!PlatformRequiresEarlyEncodingDatabase()) return;
  std::string nativeExt = PlatformNativeExtension();
  fs::path encdb = runtimeDir / "enc" / ("encdb" + nativeExt);
  fs::path transdb = runtimeDir / "enc" / "trans" / ("transdb" + nativeExt);
  if (!fs::exists(encdb)) return;

  std::string nativeRoot = "./" + RuntimeDirForRuby() + "/";
  std::string script;
  script += "begin\n";
  script += "  require " + RubyQuote(nativeRoot + "enc/encdb" + nativeExt) + "\n";
  if (fs::exists(transdb)) script += "  require " + RubyQuote(nativeRoot + "enc/trans/transdb" + nativeExt) + "\n";
  script += "rescue Exception\n";
  script += "  raise\n";
  script += "end\n";

  int state = 0;
  WriteTraceLog("before RequireEncodingDatabase");
  ruby.rb_eval_string_protect(script.c_str(), &state);
  WriteTraceLog("after RequireEncodingDatabase state=" + std::to_string(state));
  if (state != 0) WriteRubyExceptionLog(ruby);
}

std::string BootstrapRuby(const fs::path &root, const fs::path &runtimeRoot, const std::vector<std::string> &args) {
  std::string runtimeDir = PlatformPathToUtf8(runtimeRoot);
  std::string runtimeSourceDir = RuntimeDirForRuby();
  std::string nativeExt = PlatformNativeExtension();
  std::string script;
  script += "begin\n";
  script += "ENV['ELTEN_ROOT'] = " + RubyQuote(root) + "\n";
  script += "ENV['ELTEN_LAUNCHER_ARCH'] = " + RubyQuote(std::string(ELTEN_LAUNCHER_ARCH)) + "\n";
  script += "ENV['ELTEN_LAUNCHER_PLATFORM'] = " + RubyQuote(PlatformName()) + "\n";
  script += "ENV['ELTEN_LAUNCHER_YJIT_SUPPORTED'] = " + RubyQuote(PlatformSupportsYJIT() ? "1" : "0") + "\n";
  script += "ENV['ELTEN_LAUNCHER_RUNTIME_DIR'] = " + RubyQuote(runtimeDir) + "\n";
  script += "ENV['ELTEN_LAUNCHER_RUNTIME_SOURCE_DIR'] = " + RubyQuote(runtimeSourceDir) + "\n";
  script += "ENV['ELTEN_LAUNCHER_NATIVE_EXT'] = " + RubyQuote(nativeExt) + "\n";
  script += "ENV['ELTEN_RUBY_API_VERSION'] = " + RubyQuote(std::string(ELTEN_RUBY_API_VERSION)) + "\n";
  script += "ENV['ELTEN_RUBY_ROOT'] = " + RubyQuote(runtimeDir) + "\n";
  script += "ENV['GEM_HOME'] = File.join(" + RubyQuote(runtimeDir) + ", 'lib', 'ruby', 'gems', " + RubyQuote(std::string(ELTEN_RUBY_API_VERSION)) + ")\n";
  script += "ENV['GEM_PATH'] = ENV['GEM_HOME']\n";
  script += "ELTEN_LAUNCHER_ARGV = " + RubyArgvArray(args) + ".map { |arg| arg.dup.force_encoding('UTF-8') }\n";
  script += "ELTEN_LAUNCHER_BUILD_ID = " + RubyQuote(std::string(ELTEN_BUILD_ID)) + "\n";
  script += "ELTEN_LAUNCHER_BUILD_DATE = " + std::to_string(static_cast<long long>(ELTEN_BUILD_DATE)) + "\n";
  script += "ELTEN_LAUNCHER_LOG_PATH = " + RubyNullablePath(g_diagnostics.logPath) + "\n";
  script += "ELTEN_LAUNCHER_TRACE_PATH = " + RubyNullablePath(g_diagnostics.tracePath) + "\n";
  script += "$VERBOSE = nil if ENV['ELTEN_LAUNCHER_SILENCE_WARNINGS'] != '0'\n";
  script += R"RUBY(
module EltenEmbedded
  ROOT = File.expand_path(ENV['ELTEN_ROOT'])
  ARCH = ENV['ELTEN_LAUNCHER_ARCH']
  PLATFORM = ENV['ELTEN_LAUNCHER_PLATFORM']
  RUNTIME_DIR = ENV['ELTEN_LAUNCHER_RUNTIME_DIR']
  RUNTIME_SOURCE_DIR = ENV['ELTEN_LAUNCHER_RUNTIME_SOURCE_DIR']
  RUNTIME_API_VERSION = ENV['ELTEN_RUBY_API_VERSION']
  NATIVE_EXT = ENV['ELTEN_LAUNCHER_NATIVE_EXT']
  RUBY_ROOT = File.expand_path(ENV['ELTEN_RUBY_ROOT'])
  BUILD_ROOT_MARKER = '__ELTEN_BUILD_ROOT__'
  RUBY_ROOT_MARKER = '__ELTEN_RUBY_ROOT__'
  NATIVE_PREREQUIRES = {
    'json/ext/generator' => ['json/ext/generator/state']
  }
  NATIVE_POSTREQUIRES = {
    'strscan' => ['strscan/strscan']
  }
  WINDOWS_SKIPPED_REQUIRES = {
    'rubygems/defaults/operating_system' => true
  }

  class << self
    def embedded_blob_slice(offset, size)
      blob = $ELTEN_EMBEDDED_RB_BLOB
      return nil if blob == nil
      blob.byteslice(offset, size) || ''.b
    end

    def embedded_range_slice(range)
      return nil unless range.respond_to?(:[])
      embedded_blob_slice(range[0], range[1])
    end

    def filelist_lines
      embedded = embedded_range_slice($ELTEN_EMBEDDED_FILELIST_RANGE)
      (embedded || File.binread(File.join(ROOT, 'filelist'))).lines
    end

    def absolute_path?(value)
      value.start_with?('/') || value =~ /\A[A-Za-z]:\// || value.start_with?('//')
    end

    def normalize(path)
      value = path.to_s.tr('\\', '/')
      if absolute_path?(value)
        value = File.expand_path(value).tr('\\', '/')
        root = ROOT.tr('\\', '/')
        value = value[(root.size + 1)..-1] if value.downcase.start_with?(root.downcase + '/')
      end
      value.sub!(/\A\.\//, '')
      value.downcase
    end

    def load_path_relative(path)
      value = File.expand_path(path).tr('\\', '/')
      root = ROOT.tr('\\', '/')
      return nil unless value.downcase.start_with?(root.downcase + '/')
      value[(root.size + 1)..-1].downcase
    end

    def direct_candidate_names(path, extension)
      raw = normalize(path)
      names = [raw]
      names << raw + extension if File.extname(raw) == ''
      if extension == NATIVE_EXT
        names << raw.sub(/\.(so|bundle)\z/i, extension) if raw =~ /\.(so|bundle)\z/i
      end
      names.compact.uniq
    end

    def load_path_candidate_names(path, extension)
      raw = normalize(path)
      return [] if absolute_path?(raw)
      names = []
      $LOAD_PATH.each do |load_path|
        rel = load_path_relative(File.join(load_path, raw))
        next if rel == nil
        names << rel
        names << rel + extension if File.extname(rel) == ''
        names << rel.sub(/\.(so|bundle)\z/i, extension) if extension == NATIVE_EXT && rel =~ /\.(so|bundle)\z/i
      end
      names.compact.uniq
    end

    def candidate_names(path, extension)
      (direct_candidate_names(path, extension) + load_path_candidate_names(path, extension)).uniq
    end

    def lookup_key(hash, name)
      return name if hash.key?(name)
      utf8 = name.dup.force_encoding('UTF-8')
      return utf8 if hash.key?(utf8)
      binary = name.b
      return binary if hash.key?(binary)
      nil
    end

    def resolve_rb_from_candidates(names)
      names.each do |name|
        key = lookup_key($ELTEN_EMBEDDED_RB, name)
        return key if key != nil
      end
      nil
    end

    def resolve_so_from_candidates(names)
      names.each do |name|
        key = lookup_key($ELTEN_EMBEDDED_SO, name)
        mapped = key == nil ? nil : $ELTEN_EMBEDDED_SO[key]
        next if mapped == nil
        absolute = mapped_native_path(mapped)
        return [native_feature_name(absolute), absolute] if File.file?(absolute)
      end
      nil
    end

    def resolve_rb(path)
      resolved = resolve_rb_from_candidates(direct_candidate_names(path, '.rb'))
      return resolved if resolved != nil
      resolve_rb_from_candidates(load_path_candidate_names(path, '.rb'))
    end

    def embedded_rb_path(path)
      lookup_key($ELTEN_EMBEDDED_RB, normalize(path))
    end

    def mapped_native_path(mapped_path)
      value = mapped_path.to_s.tr('\\', '/')
      source = RUNTIME_SOURCE_DIR.to_s.tr('\\', '/')
      if source != '' && value.downcase.start_with?(source.downcase + '/')
        return File.join(RUNTIME_DIR, value[(source.size + 1)..-1]).tr('\\', '/')
      end
      File.join(ROOT, mapped_path).tr('\\', '/')
    end

    def native_feature_name(mapped_path)
      value = mapped_path.to_s.tr('\\', '/')
      value = File.expand_path(value).tr('\\', '/') if absolute_path?(value)
      root = File.expand_path(RUNTIME_DIR).tr('\\', '/')
      prefix = root + '/'
      return value[prefix.size..-1] if value.downcase.start_with?(prefix.downcase)
      value
    end

    def resolve_so_entry(path)
      resolved = resolve_so_from_candidates(direct_candidate_names(path, NATIVE_EXT))
      return resolved if resolved != nil
      resolve_so_from_candidates(load_path_candidate_names(path, NATIVE_EXT))
    end

    def resolve_so(path)
      entry = resolve_so_entry(path)
      entry && entry[1]
    end

    def same_feature_path?(left, right)
      left_name = normalize(left.to_s).sub(/\.rb\z/i, '')
      right_name = normalize(right.to_s).sub(/\.rb\z/i, '')
      left_name == right_name || left_name.end_with?("/#{right_name}") || right_name.end_with?("/#{left_name}")
    end

    def materialize_autoload_constant(parent, const_name, kind)
      return false unless parent.is_a?(Module)
      return false unless parent.autoload?(const_name)
      parent.send(:remove_const, const_name)
      parent.const_set(const_name, kind == 'module' ? Module.new : Class.new)
      true
    rescue Exception
      false
    end

    def prepare_autoload_constants_for_eval(file, code)
      code.scan(/^\s*(class|module)\s+((?:[A-Z]\w*::)*[A-Z]\w*)/).each do |kind, path|
        parts = path.split('::')
        next if parts.empty?

        parent = Object
        parts[0...-1].each do |part|
          name = part.to_sym
          if parent.autoload?(name)
            parent = nil
            break
          elsif parent.const_defined?(name, false)
            parent = parent.const_get(name, false)
          else
            parent = nil
            break
          end
        rescue Exception
          parent = nil
          break
        end

        next unless parent.is_a?(Module)
        const_name = parts[-1].to_sym
        target = parent.autoload?(const_name)
        next if target == nil
        next unless same_feature_path?(target, file)

        materialize_autoload_constant(parent, const_name, kind)
      end
    end

    def require_native_prerequisites(path)
      raw = normalize(path).sub(/\.(so|bundle)\z/i, '')
      Array(NATIVE_PREREQUIRES[raw]).each { |feature| require(feature) }
    end

    def native_postrequires(path)
      raw = normalize(path).sub(/\.(so|bundle)\z/i, '')
      Array(NATIVE_POSTREQUIRES[raw])
    end

    def load_rb(name, wrap = false)
      entry = $ELTEN_EMBEDDED_RB[name]
      return false if entry == nil
      file = entry[0].to_s.tr('\\', '/')
      code = materialize_rb_body(entry).dup
      code.force_encoding('UTF-8')
      prepare_autoload_constants_for_eval(file, code) unless wrap
      wrap ? Module.new.module_eval(code, file, 1) : TOPLEVEL_BINDING.eval(code, file, 1)
      true
    end

    def materialize_rb_body(entry)
      cached = entry[3]
      return cached if cached != nil
      body = embedded_blob_slice(entry[1], entry[2])
      raise "embedded Ruby payload missing for #{entry[0]}" if body == nil
      entry[3] = body
    end

    def rb_names_for(name)
      names = lookup_key($ELTEN_EMBEDDED_RB_NAMES, name)
      names == nil ? [name] : $ELTEN_EMBEDDED_RB_NAMES[names]
    end

    def read_rb(name)
      key = resolve_rb(name)
      return nil if key == nil
      entry = $ELTEN_EMBEDDED_RB[key]
      return nil if entry == nil
      code = materialize_rb_body(entry).dup
      code.force_encoding('UTF-8')
      code
    end

    def loaded_feature_names(feature)
      raw = normalize(feature).sub(/\.rb\z/i, '')
      [raw, "#{raw}.rb"].uniq
    end

    def loaded_feature_index
      if @loaded_feature_index == nil || @loaded_feature_index_size != $LOADED_FEATURES.size
        @loaded_feature_index = {}
        $LOADED_FEATURES.each { |name| @loaded_feature_index[name] = true }
        @loaded_feature_index_size = $LOADED_FEATURES.size
      end
      @loaded_feature_index
    end

    def feature_loaded?(name)
      loaded_feature_index.key?(name)
    end

    def append_loaded_feature(name)
      return if feature_loaded?(name)
      $LOADED_FEATURES << name
      @loaded_feature_index[name] = true
      @loaded_feature_index_size = $LOADED_FEATURES.size
    end

    def remove_loaded_feature(name)
      $LOADED_FEATURES.delete(name)
      @loaded_feature_index.delete(name) if @loaded_feature_index != nil
      @loaded_feature_index_size = $LOADED_FEATURES.size
    end

    def skipped_require_name(path)
      raw = normalize(path).sub(/\.rb\z/i, '')
      return nil unless PLATFORM == 'windows'
      WINDOWS_SKIPPED_REQUIRES[raw] ? raw : nil
    end

    def require_skipped(path)
      raw = skipped_require_name(path)
      return nil if raw == nil
      return false if loaded_feature_names(raw).any? { |name| feature_loaded?(name) }
      mark_loaded_feature(raw)
      true
    end

    def loaded_rb?(feature)
      rb_names_for(feature).any? do |name|
        loaded_feature_names(name).any? { |loaded| feature_loaded?(loaded) }
      end
    end

    def loading_rb?(feature)
      @rb_loading ||= {}
      rb_names_for(feature).any? { |name| @rb_loading[name] }
    end

    def mark_rb_loading(feature)
      @rb_loading ||= {}
      rb_names_for(feature).each { |name| @rb_loading[name] = true }
    end

    def unmark_rb_loading(feature)
      return if @rb_loading == nil
      rb_names_for(feature).each { |name| @rb_loading.delete(name) }
    end

    def mark_rb_loaded(feature)
      rb_names_for(feature).each do |name|
        loaded_feature_names(name).each { |loaded| append_loaded_feature(loaded) }
      end
    end

    def unmark_rb_loaded(feature)
      rb_names_for(feature).each do |name|
        loaded_feature_names(name).each { |loaded| remove_loaded_feature(loaded) }
      end
    end

    def require_rb(path)
      rb = resolve_rb(path)
      return nil if rb == nil
      return false if loaded_rb?(rb)
      return false if loading_rb?(rb)
      mark_rb_loading(rb)
      begin
        load_rb(rb)
        patch_runtime_config! if rb.to_s == 'rbconfig.rb' || rb.to_s.end_with?('/rbconfig.rb')
        mark_rb_loaded(rb)
      rescue Exception
        unmark_rb_loaded(rb)
        raise
      ensure
        unmark_rb_loading(rb)
      end
      true
    end

    def patch_runtime_config!
      return unless defined?(::RbConfig)
      [::RbConfig::CONFIG, (::RbConfig::MAKEFILE_CONFIG if ::RbConfig.const_defined?(:MAKEFILE_CONFIG, false))].compact.each do |config|
        config.each do |_key, value|
          next unless value.is_a?(String)
          value.gsub!(RUBY_ROOT_MARKER, RUBY_ROOT)
          value.gsub!(BUILD_ROOT_MARKER, ROOT)
        end
      end
    rescue Exception
    end

    def mark_loaded_feature(feature)
      loaded_feature_names(feature).each { |name| append_loaded_feature(name) }
    end

    def unmark_loaded_feature(feature)
      loaded_feature_names(feature).each { |name| remove_loaded_feature(name) }
    end

    def prepare_native_postrequires(path)
      native_postrequires(path).each do |feature|
        rb = resolve_rb(feature)
        mark_rb_loaded(rb) if rb != nil
      end
    end

    def clear_native_postrequire_marks(path)
      native_postrequires(path).each do |feature|
        rb = resolve_rb(feature)
        rb == nil ? unmark_loaded_feature(feature) : unmark_rb_loaded(rb)
      end
    end

    def load_native_postrequires(path)
      native_postrequires(path).each do |feature|
        rb = resolve_rb(feature)
        next if rb == nil
        unmark_rb_loaded(rb)
        next if loaded_rb?(rb)
        load_rb(rb)
        mark_rb_loaded(rb)
      end
    end
  end

end

class << IO
  alias __elten_launcher_original_read read
  alias __elten_launcher_original_binread binread

  def read(path, *args, **kwargs)
    if args.empty? && kwargs.empty?
      embedded = EltenEmbedded.read_rb(path)
      return embedded if embedded != nil
    end
    __elten_launcher_original_read(path, *args, **kwargs)
  end

  def binread(path, *args, **kwargs)
    if args.empty? && kwargs.empty?
      embedded = EltenEmbedded.read_rb(path)
      if embedded != nil
        embedded.force_encoding(Encoding::BINARY)
        return embedded
      end
    end
    __elten_launcher_original_binread(path, *args, **kwargs)
  end
end

module Kernel
  alias __elten_launcher_original_require require
  alias __elten_launcher_original_load load
  alias __elten_launcher_original_require_relative require_relative

  def require(path)
    if path.to_s == 'bundler/setup'
      EltenEmbedded.append_loaded_feature('bundler/setup')
      return true
    end
    skipped = EltenEmbedded.require_skipped(path)
    return skipped if skipped != nil
    loaded = EltenEmbedded.require_rb(path)
    return loaded if loaded != nil
    EltenEmbedded.require_native_prerequisites(path)
    if (so_entry = EltenEmbedded.resolve_so_entry(path))
      so_feature = so_entry[0]
      EltenEmbedded.prepare_native_postrequires(path)
      begin
        loaded = __elten_launcher_original_require(so_feature)
      rescue Exception
        EltenEmbedded.clear_native_postrequire_marks(path)
        raise
      end
      EltenEmbedded.load_native_postrequires(path)
      return loaded
    end
    __elten_launcher_original_require(path)
  end

  def require_relative(path)
    loc = caller_locations(1, 1)[0]
    base = loc && loc.path
    if base != nil && (embedded_base = EltenEmbedded.embedded_rb_path(base))
      target = File.join(File.dirname(embedded_base), path.to_s)
      loaded = EltenEmbedded.require_rb(target)
      return loaded if loaded != nil
      return require(target)
    end
    base = Dir.pwd if base == nil
    require(File.expand_path(path, File.dirname(base)))
  end

  def load(path, wrap = false)
    if (rb = EltenEmbedded.resolve_rb(path))
      loaded = EltenEmbedded.load_rb(rb, wrap)
      EltenEmbedded.patch_runtime_config! if rb.to_s == 'rbconfig.rb' || rb.to_s.end_with?('/rbconfig.rb')
      return loaded
    end
    __elten_launcher_original_load(path, wrap)
  end
end

Dir.chdir(EltenEmbedded::ROOT)
native_root = EltenEmbedded::RUNTIME_DIR
runtime_load_paths = [
  native_root,
  'src',
  '.'
]
$LOAD_PATH.replace(runtime_load_paths.select { |path| path == '.' || path == 'src' || File.directory?(path) })

require 'rubygems/version'
require 'rubygems/target_rbconfig'
module Gem
  def self.target_rbconfig
    @target_rbconfig || Gem::TargetRbConfig.for_running_ruby
  end

  def self.platforms
    @platforms ||= []
    @platforms = [Gem::Platform::RUBY, Gem::Platform.local] if @platforms.empty? && defined?(Gem::Platform)
    @platforms
  end

  def self.platforms=(platforms)
    @platforms = platforms
  end
end
require 'rubygems/platform'
require 'rubygems/requirement'

module Fiddle
  WINDOWS = (EltenEmbedded::PLATFORM == 'windows') unless const_defined?(:WINDOWS, false)
end

begin
  require File.join(native_root, 'enc', 'encdb' + EltenEmbedded::NATIVE_EXT)
  require File.join(native_root, 'enc', 'trans', 'transdb' + EltenEmbedded::NATIVE_EXT)
rescue LoadError
end

def __elten_launcher_trace(message)
  path = ::ELTEN_LAUNCHER_TRACE_PATH
  return if path == nil
  File.open(path, 'ab') { |file| file.write(Time.now.to_s + ' ' + message + "\n") }
rescue Exception
end

__elten_launcher_trace('before elten.rb')
ARGV.replace(::ELTEN_LAUNCHER_ARGV.map(&:dup))

def __elten_launcher_apply_build_info
  Object.const_set(:Elten, Module.new) unless defined?(::Elten)
  ::Elten.__send__(:remove_const, :BuildID) if ::Elten.const_defined?(:BuildID, false)
  ::Elten.const_set(:BuildID, ::ELTEN_LAUNCHER_BUILD_ID) if ::ELTEN_LAUNCHER_BUILD_ID.to_s != ''
  ::Elten.__send__(:remove_const, :BuildDate) if ::Elten.const_defined?(:BuildDate, false)
  ::Elten.const_set(:BuildDate, ::ELTEN_LAUNCHER_BUILD_DATE.to_i) if ::ELTEN_LAUNCHER_BUILD_DATE.to_i > 0
end

__elten_launcher_apply_build_info
EltenEmbedded.load_rb('elten.rb')
__elten_launcher_apply_build_info
__elten_launcher_trace('after elten.rb')
rescue Exception => e
  begin
    path = ::ELTEN_LAUNCHER_LOG_PATH
    raise if path == nil
    File.open(path, 'ab') do |file|
      file.write(Time.now.to_s)
      file.write("\n")
      file.write(e.class.name)
      file.write(": ")
      file.write(e.message.to_s)
      file.write("\n")
      file.write(Array(e.backtrace).join("\n"))
      file.write("\n")
      file.flush
    end
  rescue Exception
  end
  raise
end
)RUBY";
  return script;
}

int RunLauncher(int argc, char **argv) {
  fs::path root = PlatformApplicationRoot();
  std::vector<std::string> args = PlatformCommandLineArguments(argc, argv);
  g_diagnostics = ParseLauncherDiagnostics(root, args);

  fs::path runtimeDir = root / "bin" / ELTEN_RUNTIME_DIR_NAME;
  fs::path fallbackRubyRoot = root / ELTEN_RUBY_ROOT_NAME;
  bool developerMode = LauncherDeveloperMode(args);
  EnsureDeveloperModeArgument(args, developerMode);

  fs::current_path(root);
#if ELTEN_FORCE_DEVELOPER_MODE
  WriteTraceLog("developer mode forced by build configuration");
#endif
  std::string integrityError;
  WriteTraceLog("before VerifyEmbeddedPayloadIntegrity");
  if (!VerifyEmbeddedPayloadIntegrity(PlatformPathToUtf8(root), integrityError)) {
    throw std::runtime_error("Elten launcher integrity check failed: " + integrityError);
  }
  WriteTraceLog("after VerifyEmbeddedPayloadIntegrity");
  WriteTraceLog("before StartRuntimeFileIntegrityCheck");
  StartRuntimeFileIntegrityCheck(PlatformPathToUtf8(root), FatalRuntimeFileIntegrityFailure);
  WriteTraceLog("after StartRuntimeFileIntegrityCheck");
  PlatformConfigureEnvironment(root, runtimeDir, fallbackRubyRoot);

  WriteTraceLog("before PlatformLoadRuby");
  RubyApi ruby = PlatformLoadRuby(runtimeDir, fallbackRubyRoot);
  WriteTraceLog("after PlatformLoadRuby");
  std::vector<std::string> rubyArgs = {"elten", "--disable-gems", "-e", ""};
  if (PlatformSupportsYJIT()) {
    rubyArgs.insert(rubyArgs.begin() + 1, "--yjit");
    WriteTraceLog("YJIT requested");
  }
  std::vector<char *> rubyArgv;
  rubyArgv.reserve(rubyArgs.size());
  for (std::string &arg : rubyArgs) rubyArgv.push_back(arg.data());
  int rubyArgc = static_cast<int>(rubyArgv.size());
  char **rubyArgvData = rubyArgv.data();

  WriteTraceLog("before ruby_sysinit");
  ruby.ruby_sysinit(&rubyArgc, &rubyArgvData);
  WriteTraceLog("after ruby_sysinit");
  rubyArgc = static_cast<int>(rubyArgv.size());
  rubyArgvData = rubyArgv.data();

  void *stackAnchor = nullptr;
  if (ruby.ruby_init_stack != nullptr) ruby.ruby_init_stack(&stackAnchor);
  WriteTraceLog("before ruby_init");
  ruby.ruby_init();
  WriteTraceLog("after ruby_init");
  WriteTraceLog("before ruby_options");
  if (ruby.ruby_options != nullptr) {
    ruby.ruby_options(rubyArgc, rubyArgvData);
  } else if (ruby.ruby_init_loadpath != nullptr) {
    ruby.ruby_init_loadpath();
  }
  WriteTraceLog("after ruby_options");
  WriteTraceLog("before VerifyYJITEnabled");
  VerifyYJITEnabled(ruby);
  WriteTraceLog("after VerifyYJITEnabled");

  RequireEncodingDatabase(ruby, runtimeDir);
  WriteTraceLog("before RegisterEmbeddedAssets");
  RegisterEmbeddedAssets(PlatformEmbeddedApi(ruby));
  WriteTraceLog("after RegisterEmbeddedAssets");
  if (developerMode) {
    WriteTraceLog("skipping RegisterStampFunction in developer mode");
  } else {
    WriteTraceLog("before RegisterStampFunction");
    RegisterStampFunction(PlatformStampApi(ruby));
    WriteTraceLog("after RegisterStampFunction");
  }
  ruby.ruby_script("elten");

  std::string bootstrap = BootstrapRuby(root, runtimeDir, args);
  WriteFile(g_diagnostics.bootstrapPath, bootstrap);
  int state = 0;
  WriteTraceLog("before rb_eval_string_protect");
  ruby.rb_eval_string_protect(bootstrap.c_str(), &state);
  WriteTraceLog("after rb_eval_string_protect state=" + std::to_string(state));
  if (state != 0) {
    std::string errorMessage = RubyExceptionMessage(ruby);
    if (RubyExceptionIsSystemExit(ruby)) {
      WriteTraceLog("Ruby evaluation ended with SystemExit");
    } else {
      WriteRubyExceptionLog(ruby, errorMessage);
      PlatformShowFatal(errorMessage);
    }
  }
  int cleanup = ruby.ruby_cleanup(state);
  WriteTraceLog("after ruby_cleanup cleanup=" + std::to_string(cleanup));
  return cleanup == 0 ? state : cleanup;
}

} // namespace

int LauncherMain(int argc, char **argv) {
  try {
    return RunLauncher(argc, argv);
  } catch (const std::exception &error) {
    WriteFatalLog(error.what());
    PlatformShowFatal(error.what());
    return 1;
  } catch (...) {
    WriteFatalLog("Unknown launcher error");
    PlatformShowFatal("Unknown launcher error");
    return 1;
  }
}

} // namespace EltenLauncher

#if defined(_WIN32)
int WINAPI wWinMain(HINSTANCE, HINSTANCE, PWSTR, int) {
  return EltenLauncher::LauncherMain(0, nullptr);
}
#else
int main(int argc, char **argv) {
  return EltenLauncher::LauncherMain(argc, argv);
}
#endif
