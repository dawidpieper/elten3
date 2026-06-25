#include "stamp.hpp"

#ifndef ELTEN_STAMP_SIGNATURE_AVAILABLE
#define ELTEN_STAMP_SIGNATURE_AVAILABLE 0
#endif

#if ELTEN_STAMP_SIGNATURE_AVAILABLE
#include "stamp_secret.h"
#ifndef SECR
#error "stamp_secret.h must define SECR"
#endif
#endif

#if defined(_WIN32)
#include <windows.h>
#elif defined(__APPLE__)
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <mach/mach.h>
#endif

#include <array>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <ctime>
#include <stdexcept>
#include <string>
#include <vector>

namespace EltenLauncher {
namespace {

StampRubyApi g_api;

class StampError : public std::runtime_error {
public:
  using std::runtime_error::runtime_error;
};

class StampArgumentError : public StampError {
public:
  using StampError::StampError;
};

uint32_t RotateRight(uint32_t value, uint32_t bits) {
  return (value >> bits) | (value << (32 - bits));
}

std::array<uint8_t, 32> Sha256(const uint8_t *data, std::size_t size) {
  static const uint32_t k[64] = {
      0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
      0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
      0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
      0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
      0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
      0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
      0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
      0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
  };

  std::array<uint32_t, 8> h = {
      0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
      0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
  };

  std::vector<uint8_t> message(data, data + size);
  uint64_t bitSize = static_cast<uint64_t>(size) * 8;
  message.push_back(0x80);
  while ((message.size() % 64) != 56) message.push_back(0);
  for (int shift = 56; shift >= 0; shift -= 8) message.push_back(static_cast<uint8_t>((bitSize >> shift) & 0xff));

  for (std::size_t offset = 0; offset < message.size(); offset += 64) {
    uint32_t w[64] = {};
    for (int i = 0; i < 16; ++i) {
      std::size_t j = offset + static_cast<std::size_t>(i) * 4;
      w[i] = (static_cast<uint32_t>(message[j]) << 24) |
             (static_cast<uint32_t>(message[j + 1]) << 16) |
             (static_cast<uint32_t>(message[j + 2]) << 8) |
             static_cast<uint32_t>(message[j + 3]);
    }
    for (int i = 16; i < 64; ++i) {
      uint32_t s0 = RotateRight(w[i - 15], 7) ^ RotateRight(w[i - 15], 18) ^ (w[i - 15] >> 3);
      uint32_t s1 = RotateRight(w[i - 2], 17) ^ RotateRight(w[i - 2], 19) ^ (w[i - 2] >> 10);
      w[i] = w[i - 16] + s0 + w[i - 7] + s1;
    }

    uint32_t a = h[0], b = h[1], c = h[2], d = h[3];
    uint32_t e = h[4], f = h[5], g = h[6], hh = h[7];
    for (int i = 0; i < 64; ++i) {
      uint32_t s1 = RotateRight(e, 6) ^ RotateRight(e, 11) ^ RotateRight(e, 25);
      uint32_t ch = (e & f) ^ ((~e) & g);
      uint32_t temp1 = hh + s1 + ch + k[i] + w[i];
      uint32_t s0 = RotateRight(a, 2) ^ RotateRight(a, 13) ^ RotateRight(a, 22);
      uint32_t maj = (a & b) ^ (a & c) ^ (b & c);
      uint32_t temp2 = s0 + maj;
      hh = g;
      g = f;
      f = e;
      e = d + temp1;
      d = c;
      c = b;
      b = a;
      a = temp1 + temp2;
    }

    h[0] += a; h[1] += b; h[2] += c; h[3] += d;
    h[4] += e; h[5] += f; h[6] += g; h[7] += hh;
  }

  std::array<uint8_t, 32> digest = {};
  for (std::size_t i = 0; i < h.size(); ++i) {
    digest[i * 4] = static_cast<uint8_t>((h[i] >> 24) & 0xff);
    digest[i * 4 + 1] = static_cast<uint8_t>((h[i] >> 16) & 0xff);
    digest[i * 4 + 2] = static_cast<uint8_t>((h[i] >> 8) & 0xff);
    digest[i * 4 + 3] = static_cast<uint8_t>(h[i] & 0xff);
  }
  return digest;
}

std::string Hex(const uint8_t *data, std::size_t size) {
  static const char digits[] = "0123456789abcdef";
  std::string out;
  out.reserve(size * 2);
  for (std::size_t i = 0; i < size; ++i) {
    out.push_back(digits[data[i] >> 4]);
    out.push_back(digits[data[i] & 0x0f]);
  }
  return out;
}

std::string Sha256Hex(const std::string &value) {
  auto digest = Sha256(reinterpret_cast<const uint8_t *>(value.data()), value.size());
  return Hex(digest.data(), digest.size());
}

std::string Sha256Hex(const std::array<uint8_t, 32> &value) {
  auto digest = Sha256(value.data(), value.size());
  return Hex(digest.data(), digest.size());
}

std::array<uint8_t, 32> StampSecretKey() {
#if ELTEN_STAMP_SIGNATURE_AVAILABLE
  const char source[] = SECR;
  char key[32] = {};
  genkey(source, key);
  std::array<uint8_t, 32> out = {};
  for (std::size_t i = 0; i < out.size(); ++i) out[i] = static_cast<uint8_t>(key[i]);
  return out;
#else
  throw StampError("get_stamp signing is unavailable in this build");
#endif
}

std::string HmacSha256Hex(const std::string &message, const std::array<uint8_t, 32> &key) {
  std::array<uint8_t, 64> inner = {};
  std::array<uint8_t, 64> outer = {};
  for (std::size_t i = 0; i < inner.size(); ++i) {
    uint8_t byte = i < key.size() ? key[i] : 0;
    inner[i] = byte ^ 0x36;
    outer[i] = byte ^ 0x5c;
  }

  std::vector<uint8_t> innerData(inner.begin(), inner.end());
  innerData.insert(innerData.end(), message.begin(), message.end());
  auto innerDigest = Sha256(innerData.data(), innerData.size());

  std::vector<uint8_t> outerData(outer.begin(), outer.end());
  outerData.insert(outerData.end(), innerDigest.begin(), innerDigest.end());
  auto digest = Sha256(outerData.data(), outerData.size());
  return Hex(digest.data(), digest.size());
}

bool AppendNamedBytes(std::string &target, const char *name, const std::string &bytes) {
  if (bytes.empty()) return false;
  target += name;
  target += ":";
  target += std::to_string(bytes.size());
  target += ":";
  target.append(bytes.data(), bytes.size());
  target += "\n";
  return true;
}

#if defined(_WIN32)
std::string WideToUtf8(const std::wstring &value) {
  if (value.empty()) return "";
  int size = WideCharToMultiByte(CP_UTF8, 0, value.data(), static_cast<int>(value.size()), nullptr, 0, nullptr, nullptr);
  if (size <= 0) return "";
  std::string result(static_cast<std::size_t>(size), '\0');
  WideCharToMultiByte(CP_UTF8, 0, value.data(), static_cast<int>(value.size()), result.data(), size, nullptr, nullptr);
  return result;
}

std::string ReadRegistryString(HKEY root, const wchar_t *path, const wchar_t *name) {
  HKEY key = nullptr;
  if (RegOpenKeyExW(root, path, 0, KEY_READ | KEY_WOW64_64KEY, &key) != ERROR_SUCCESS) return "";
  DWORD type = 0;
  DWORD bytes = 0;
  LONG status = RegQueryValueExW(key, name, nullptr, &type, nullptr, &bytes);
  if (status != ERROR_SUCCESS || (type != REG_SZ && type != REG_EXPAND_SZ) || bytes < sizeof(wchar_t)) {
    RegCloseKey(key);
    return "";
  }
  std::wstring value(bytes / sizeof(wchar_t), L'\0');
  status = RegQueryValueExW(key, name, nullptr, &type, reinterpret_cast<LPBYTE>(value.data()), &bytes);
  RegCloseKey(key);
  if (status != ERROR_SUCCESS) return "";
  while (!value.empty() && value.back() == L'\0') value.pop_back();
  return WideToUtf8(value);
}

std::string RawSmbiosFirmware() {
  constexpr DWORD kRawSmbiosProvider = 0x52534d42;
  DWORD size = GetSystemFirmwareTable(kRawSmbiosProvider, 0, nullptr, 0);
  if (size == 0) return "";
  std::vector<uint8_t> buffer(size);
  DWORD read = GetSystemFirmwareTable(kRawSmbiosProvider, 0, buffer.data(), size);
  if (read == 0) return "";
  if (read < buffer.size()) buffer.resize(read);
  return std::string(reinterpret_cast<const char *>(buffer.data()), buffer.size());
}
#endif

#if defined(__APPLE__)
std::string CfStringToUtf8(CFStringRef value) {
  if (value == nullptr) return "";
  CFIndex length = CFStringGetLength(value);
  CFIndex maxSize = CFStringGetMaximumSizeForEncoding(length, kCFStringEncodingUTF8) + 1;
  if (maxSize <= 1) return "";
  std::vector<char> buffer(static_cast<std::size_t>(maxSize), '\0');
  if (!CFStringGetCString(value, buffer.data(), maxSize, kCFStringEncodingUTF8)) return "";
  return buffer.data();
}

std::string PlatformProperty(const char *name) {
  io_service_t service = IOServiceGetMatchingService(MACH_PORT_NULL, IOServiceMatching("IOPlatformExpertDevice"));
  if (service == IO_OBJECT_NULL) return "";
  CFStringRef key = CFStringCreateWithCString(kCFAllocatorDefault, name, kCFStringEncodingASCII);
  if (key == nullptr) {
    IOObjectRelease(service);
    return "";
  }
  CFTypeRef property = IORegistryEntryCreateCFProperty(service, key, kCFAllocatorDefault, 0);
  CFRelease(key);
  IOObjectRelease(service);
  if (property == nullptr) return "";
  std::string value;
  if (CFGetTypeID(property) == CFStringGetTypeID()) value = CfStringToUtf8(static_cast<CFStringRef>(property));
  CFRelease(property);
  return value;
}
#endif

std::string HardwareId() {
#if defined(_WIN32)
  std::string material = "windows-hwid-v2\n";
  bool hasMaterial = false;
  hasMaterial |= AppendNamedBytes(material, "machine-guid",
                                  ReadRegistryString(HKEY_LOCAL_MACHINE, L"SOFTWARE\\Microsoft\\Cryptography", L"MachineGuid"));
  hasMaterial |= AppendNamedBytes(material, "smbios", RawSmbiosFirmware());
  if (!hasMaterial) throw StampError("cannot build Windows hardware id");
  return Sha256Hex(material);
#elif defined(__APPLE__)
  std::string material = "osx-hwid-v2\n";
  bool hasMaterial = false;
  hasMaterial |= AppendNamedBytes(material, "platform-uuid", PlatformProperty("IOPlatformUUID"));
  hasMaterial |= AppendNamedBytes(material, "platform-serial", PlatformProperty("IOPlatformSerialNumber"));
  if (!hasMaterial) throw StampError("cannot build macOS hardware id");
  return Sha256Hex(material);
#else
  return Sha256Hex("unknown");
#endif
}

RubyValue RubyString(const std::string &value) {
  StampRubyApi::str_new_t factory = g_api.utf8_str_new != nullptr ? g_api.utf8_str_new : g_api.str_new;
  return factory(value.data(), static_cast<long>(value.size()));
}

RubyValue RubyBytes(const std::string &value) {
  return g_api.str_new(value.data(), static_cast<long>(value.size()));
}

std::string RubyStringBytes(RubyValue value) {
  if (g_api.obj_is_kind_of(value, g_api.c_string) == 0) throw StampArgumentError("get_stamp expects a String");
  RubyValue lengthValue = g_api.funcallv(value, g_api.intern("bytesize"), 0, nullptr);
  long length = g_api.num2long(lengthValue);
  if (length < 0) throw StampError("negative Ruby string size");
  char *ptr = g_api.string_value_ptr(&value);
  return std::string(ptr, static_cast<std::size_t>(length));
}

RubyValue ELTEN_RUBY_CALL GetStamp(RubyValue, RubyValue materialValue) {
  try {
    WaitForRuntimeFileIntegrity();
    std::string material = RubyStringBytes(materialValue);
    long long timestamp = static_cast<long long>(std::time(nullptr));
    std::string timestampBytes = std::to_string(timestamp);
    std::string hwid = HardwareId();
    auto key = StampSecretKey();
    std::string keySha256 = Sha256Hex(key);
    std::string signedBytes = material;
    signedBytes += timestampBytes;
    signedBytes += hwid;
    signedBytes += keySha256;
    std::string hmac = HmacSha256Hex(signedBytes, key);

    RubyValue result = g_api.hash_new();
    g_api.hash_aset(result, RubyString("string"), RubyBytes(material));
    g_api.hash_aset(result, RubyString("timestamp"), g_api.ll2inum(timestamp));
    g_api.hash_aset(result, RubyString("hwid"), RubyString(hwid));
    g_api.hash_aset(result, RubyString("key_sha256"), RubyString(keySha256));
    g_api.hash_aset(result, RubyString("hmac"), RubyString(hmac));
    return result;
  } catch (const StampArgumentError &error) {
    g_api.raise(g_api.e_arg_error != 0 ? g_api.e_arg_error : g_api.e_runtime_error, "%s", error.what());
  } catch (const std::exception &error) {
    g_api.raise(g_api.e_runtime_error, "%s", error.what());
  } catch (...) {
    g_api.raise(g_api.e_runtime_error, "%s", "unknown get_stamp error");
  }
  return 0;
}

} // namespace

void RegisterStampFunction(const StampRubyApi &api) {
#if !ELTEN_STAMP_SIGNATURE_AVAILABLE
  (void)api;
  throw std::runtime_error("get_stamp signing is unavailable because the launcher was built without a private key");
#else
  g_api = api;
  if (g_api.utf8_str_new == nullptr) g_api.utf8_str_new = g_api.str_new;
  if (g_api.define_global_function == nullptr || g_api.hash_new == nullptr || g_api.str_new == nullptr ||
      g_api.hash_aset == nullptr || g_api.raise == nullptr || g_api.obj_is_kind_of == nullptr ||
      g_api.string_value_ptr == nullptr || g_api.intern == nullptr || g_api.funcallv == nullptr ||
      g_api.num2long == nullptr || g_api.ll2inum == nullptr || g_api.c_string == 0 ||
      g_api.e_runtime_error == 0) {
    throw std::runtime_error("Incomplete Ruby API for get_stamp");
  }
  g_api.define_global_function("get_stamp", GetStamp, 1);
#endif
}

} // namespace EltenLauncher
