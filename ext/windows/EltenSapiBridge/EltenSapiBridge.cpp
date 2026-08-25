// A part of Elten - EltenLink / Elten Network desktop client.
// Copyright (C) 2014-2026 Dawid Pieper
// Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.
// Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for details.
//
// This small x86/x64 host exposes SAPI5 over IPC. It lets an Elten process use voices whose architecture cannot be loaded in that process.

#include <windows.h>
#include <sapi.h>
#include <wrl/client.h>

#include <cstdint>
#include <string>
#include <utility>
#include <vector>

#define ELTEN_SAPI_BRIDGE_MAGIC 0xACEDFEEDu
#define ELTEN_SAPI_BRIDGE_VERSION 1u
#define ELTEN_SAPI_BRIDGE_MAX_FRAME_SIZE 0xFFFFFFu
#define ELTEN_SAPI_BRIDGE_MAX_SAPI_STRING_CHARS (1024u * 1024u)
#define ELTEN_SAPI_BRIDGE_HELLO_TIMEOUT_MS 3000

using Microsoft::WRL::ComPtr;

namespace {

enum class Command : std::uint8_t {
  Hello = 1,
  SetVoice = 2,
  SetOutput = 3,
  SetRate = 4,
  SetVolume = 5,
  Speak = 6,
  Pause = 7,
  Resume = 8,
  Stop = 9,
  Status = 10,
  Quit = 11,
  ListVoices = 12,
};

bool ReadAll(HANDLE handle, void* data, std::uint32_t size) {
  auto* bytes = static_cast<unsigned char*>(data);
  while (size > 0) {
    DWORD read = 0;
    if (!ReadFile(handle, bytes, size, &read, nullptr) || read == 0) return false;
    bytes += read;
    size -= read;
  }
  return true;
}

bool ReadAllUntil(HANDLE handle, void* data, std::uint32_t size, ULONGLONG deadline) {
  auto* bytes = static_cast<unsigned char*>(data);
  while (size > 0) {
    DWORD available = 0;
    if (!PeekNamedPipe(handle, nullptr, 0, nullptr, &available, nullptr)) return false;
    if (available == 0) {
      if (GetTickCount64() >= deadline) return false;
      Sleep(2);
      continue;
    }
    const DWORD chunk = available < size ? available : size;
    DWORD read = 0;
    if (!ReadFile(handle, bytes, chunk, &read, nullptr) || read == 0) return false;
    bytes += read;
    size -= read;
  }
  return true;
}

bool WriteAll(HANDLE handle, const void* data, std::uint32_t size) {
  const auto* bytes = static_cast<const unsigned char*>(data);
  while (size > 0) {
    DWORD written = 0;
    if (!WriteFile(handle, bytes, size, &written, nullptr) || written == 0) return false;
    bytes += written;
    size -= written;
  }
  return true;
}

std::uint32_t ReadU32(const unsigned char* data) {
  return static_cast<std::uint32_t>(data[0]) |
         (static_cast<std::uint32_t>(data[1]) << 8) |
         (static_cast<std::uint32_t>(data[2]) << 16) |
         (static_cast<std::uint32_t>(data[3]) << 24);
}

std::uint32_t ReadU24(const unsigned char* data) {
  return static_cast<std::uint32_t>(data[0]) |
         (static_cast<std::uint32_t>(data[1]) << 8) |
         (static_cast<std::uint32_t>(data[2]) << 16);
}

void AppendU32(std::vector<unsigned char>& out, std::uint32_t value) {
  out.push_back(static_cast<unsigned char>(value));
  out.push_back(static_cast<unsigned char>(value >> 8));
  out.push_back(static_cast<unsigned char>(value >> 16));
  out.push_back(static_cast<unsigned char>(value >> 24));
}

void AppendU24(std::vector<unsigned char>& out, std::uint32_t value) {
  out.push_back(static_cast<unsigned char>(value));
  out.push_back(static_cast<unsigned char>(value >> 8));
  out.push_back(static_cast<unsigned char>(value >> 16));
}

class Reader {
 public:
  explicit Reader(const std::vector<unsigned char>& data) : data_(data) {}

  bool U32(std::uint32_t& value) {
    if (offset_ + 4 > data_.size()) return false;
    value = ReadU32(data_.data() + offset_);
    offset_ += 4;
    return true;
  }

  bool String(std::string& value) {
    std::uint32_t size = 0;
    if (!U32(size) || size > data_.size() - offset_) return false;
    value.assign(reinterpret_cast<const char*>(data_.data() + offset_), size);
    offset_ += size;
    return true;
  }

  bool Done() const { return offset_ == data_.size(); }

 private:
  const std::vector<unsigned char>& data_;
  std::size_t offset_ = 0;
};

void AppendString(std::vector<unsigned char>& out, const std::string& value) {
  AppendU32(out, static_cast<std::uint32_t>(value.size()));
  out.insert(out.end(), value.begin(), value.end());
}

std::wstring WideFromUtf8(const std::string& value) {
  if (value.empty()) return {};
  const int size = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(),
                                       static_cast<int>(value.size()), nullptr, 0);
  if (size <= 0) return {};
  std::wstring result(static_cast<std::size_t>(size), L'\0');
  if (MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(),
                          static_cast<int>(value.size()), result.data(), size) != size) {
    return {};
  }
  return result;
}

std::string Utf8FromWide(const std::wstring& value) {
  if (value.empty()) return {};
  const int length = static_cast<int>(value.size());
  const int size = WideCharToMultiByte(CP_UTF8, 0, value.data(), length, nullptr, 0, nullptr, nullptr);
  if (size <= 0) return {};
  std::string result(static_cast<std::size_t>(size), '\0');
  WideCharToMultiByte(CP_UTF8, 0, value.data(), length, result.data(), size, nullptr, nullptr);
  return result;
}

bool CopySapiString(const wchar_t* value, std::wstring& result) {
  if (value == nullptr) {
    result.clear();
    return true;
  }
  std::size_t size = 0;
  while (size < ELTEN_SAPI_BRIDGE_MAX_SAPI_STRING_CHARS && value[size] != L'\0') ++size;
  if (size == ELTEN_SAPI_BRIDGE_MAX_SAPI_STRING_CHARS) return false;
  result.assign(value, size);
  return true;
}

std::wstring TokenId(ISpObjectToken* token) {
  LPWSTR value = nullptr;
  if (token == nullptr || FAILED(token->GetId(&value)) || value == nullptr) return {};
  std::wstring result;
  CopySapiString(value, result);
  CoTaskMemFree(value);
  return result;
}

std::wstring DataKeyString(ISpDataKey* key, const wchar_t* name) {
  LPWSTR value = nullptr;
  if (key == nullptr || FAILED(key->GetStringValue(name, &value)) || value == nullptr) return {};
  std::wstring result;
  CopySapiString(value, result);
  CoTaskMemFree(value);
  return result;
}

std::wstring TokenAttribute(ISpObjectToken* token, const wchar_t* name) {
  ComPtr<ISpDataKey> attributes;
  if (token == nullptr || FAILED(token->OpenKey(L"Attributes", &attributes))) return {};
  return DataKeyString(attributes.Get(), name);
}

HRESULT Enumerate(const wchar_t* category_id, ComPtr<IEnumSpObjectTokens>& tokens) {
  ComPtr<ISpObjectTokenCategory> category;
  HRESULT result = CoCreateInstance(CLSID_SpObjectTokenCategory, nullptr, CLSCTX_INPROC_SERVER,
                                    IID_PPV_ARGS(&category));
  if (FAILED(result)) return result;
  result = category->SetId(category_id, FALSE);
  if (FAILED(result)) return result;
  return category->EnumTokens(nullptr, nullptr, &tokens);
}

HRESULT FindToken(const wchar_t* category_id, const std::wstring& id,
                  ComPtr<ISpObjectToken>& found) {
  ComPtr<IEnumSpObjectTokens> tokens;
  HRESULT result = Enumerate(category_id, tokens);
  if (FAILED(result)) return result;
  for (;;) {
    ComPtr<ISpObjectToken> token;
    ULONG fetched = 0;
    result = tokens->Next(1, &token, &fetched);
    if (result == S_FALSE || fetched == 0) break;
    if (FAILED(result)) return result;
    const std::wstring token_id = TokenId(token.Get());
    if (token_id.size() == id.size() &&
        CompareStringOrdinal(token_id.data(), static_cast<int>(token_id.size()), id.data(),
                             static_cast<int>(id.size()), TRUE) == CSTR_EQUAL) {
      found = token;
      return S_OK;
    }
  }
  return HRESULT_FROM_WIN32(ERROR_NOT_FOUND);
}

class SapiBridge {
 public:
  HRESULT Initialize() {
    HRESULT result = CoCreateInstance(CLSID_SpVoice, nullptr, CLSCTX_INPROC_SERVER,
                                      IID_PPV_ARGS(&voice_));
    if (SUCCEEDED(result)) {
      voice_->SetPriority(SPVPRI_NORMAL);
      NegotiateAudioFormat();
    }
    return result;
  }

  HRESULT SetVoice(const std::string& id) {
    if (id.find('\0') != std::string::npos) return E_INVALIDARG;
    const std::wstring wide = WideFromUtf8(id);
    if (!id.empty() && wide.empty()) return E_INVALIDARG;
    ComPtr<ISpObjectToken> token;
    HRESULT result = FindToken(SPCAT_VOICES, wide, token);
    if (FAILED(result)) return result;
    result = voice_->SetVoice(token.Get());
    if (FAILED(result)) return result;
    NegotiateAudioFormat();
    USHORT volume = 100;
    result = voice_->GetVolume(&volume);
    if (FAILED(result)) return result;
    result = voice_->SetVolume(0);
    if (FAILED(result)) return result;
    result = voice_->Speak(L"a", SPF_IS_NOT_XML, nullptr);
    const HRESULT restore = voice_->SetVolume(volume);
    return FAILED(result) ? result : restore;
  }

  HRESULT SetOutput(const std::string& id) {
    HRESULT result = S_OK;
    if (id.empty()) {
      result = voice_->SetOutput(nullptr, FALSE);
    } else {
      if (id.find('\0') != std::string::npos) return E_INVALIDARG;
      const std::wstring wide = WideFromUtf8(id);
      if (wide.empty()) return E_INVALIDARG;
      ComPtr<ISpObjectToken> token;
      result = FindToken(SPCAT_AUDIOOUT, wide, token);
      if (SUCCEEDED(result)) result = voice_->SetOutput(token.Get(), TRUE);
    }
    if (SUCCEEDED(result)) NegotiateAudioFormat();
    return result;
  }

  HRESULT SetRate(std::uint32_t value) {
    return voice_->SetRate(static_cast<long>(static_cast<std::int32_t>(value)));
  }

  HRESULT SetVolume(std::uint32_t value) {
    if (value > 100) return E_INVALIDARG;
    return voice_->SetVolume(static_cast<USHORT>(value));
  }

  HRESULT Speak(std::uint32_t flags, const std::string& text) {
    if (text.find('\0') != std::string::npos) return E_INVALIDARG;
    const std::wstring wide = WideFromUtf8(text);
    if (!text.empty() && wide.empty()) return E_INVALIDARG;
    return voice_->Speak(wide.c_str(), static_cast<SPEAKFLAGS>(flags), nullptr);
  }

  HRESULT Pause() { return voice_->Pause(); }
  HRESULT Resume() { return voice_->Resume(); }

  HRESULT Stop() {
    return voice_->Speak(L"", static_cast<SPEAKFLAGS>(SPF_ASYNC | SPF_PURGEBEFORESPEAK |
                                                      SPF_IS_NOT_XML), nullptr);
  }

  HRESULT Status(std::vector<unsigned char>& out) {
    SPVOICESTATUS status{};
    LPWSTR bookmark = nullptr;
    HRESULT result = voice_->GetStatus(&status, &bookmark);
    if (FAILED(result)) return result;
    AppendU32(out, status.dwRunningState == SPRS_IS_SPEAKING ? 1u : 0u);
    std::wstring bookmark_value;
    if (!CopySapiString(bookmark, bookmark_value)) result = E_INVALIDARG;
    AppendString(out, Utf8FromWide(bookmark_value));
    CoTaskMemFree(bookmark);
    return result;
  }

  HRESULT ListVoices(std::vector<unsigned char>& out) {
    struct VoiceInfo {
      std::wstring id;
      std::wstring name;
      std::wstring language;
      std::wstring age;
      std::wstring gender;
      std::wstring vendor;
    };

    ComPtr<IEnumSpObjectTokens> tokens;
    HRESULT result = Enumerate(SPCAT_VOICES, tokens);
    if (FAILED(result)) return result;
    std::vector<VoiceInfo> voices;
    for (;;) {
      ComPtr<ISpObjectToken> token;
      ULONG fetched = 0;
      result = tokens->Next(1, &token, &fetched);
      if (result == S_FALSE || fetched == 0) break;
      if (FAILED(result)) return result;
      VoiceInfo info;
      info.id = TokenId(token.Get());
      if (info.id.empty()) continue;
      info.name = DataKeyString(token.Get(), nullptr);
      info.language = TokenAttribute(token.Get(), L"Language");
      info.age = TokenAttribute(token.Get(), L"Age");
      info.gender = TokenAttribute(token.Get(), L"Gender");
      info.vendor = TokenAttribute(token.Get(), L"Vendor");
      voices.push_back(std::move(info));
    }

    AppendU32(out, static_cast<std::uint32_t>(voices.size()));
    for (const VoiceInfo& info : voices) {
      AppendString(out, Utf8FromWide(info.id));
      AppendString(out, Utf8FromWide(info.name));
      AppendString(out, Utf8FromWide(info.language));
      AppendString(out, Utf8FromWide(info.age));
      AppendString(out, Utf8FromWide(info.gender));
      AppendString(out, Utf8FromWide(info.vendor));
    }
    return S_OK;
  }

 private:
  void NegotiateAudioFormat() {
    ComPtr<ISpStreamFormat> stream;
    if (SUCCEEDED(voice_->GetOutputStream(&stream))) voice_->SetOutput(stream.Get(), TRUE);
  }

  ComPtr<ISpVoice> voice_;
};

bool SendResponse(HANDLE output, std::uint8_t command, HRESULT status,
                  const std::vector<unsigned char>& body = {}) {
  if (body.size() > ELTEN_SAPI_BRIDGE_MAX_FRAME_SIZE - 4u) return false;
  std::vector<unsigned char> header;
  header.reserve(8);
  AppendU32(header, ELTEN_SAPI_BRIDGE_MAGIC);
  header.push_back(static_cast<unsigned char>((ELTEN_SAPI_BRIDGE_VERSION << 4) | command));
  AppendU24(header, static_cast<std::uint32_t>(body.size() + 4));
  const std::uint32_t raw_status = static_cast<std::uint32_t>(status);
  unsigned char status_bytes[4] = {
      static_cast<unsigned char>(raw_status), static_cast<unsigned char>(raw_status >> 8),
      static_cast<unsigned char>(raw_status >> 16), static_cast<unsigned char>(raw_status >> 24)};
  return WriteAll(output, header.data(), static_cast<std::uint32_t>(header.size())) &&
         WriteAll(output, status_bytes, 4) &&
         (body.empty() || WriteAll(output, body.data(), static_cast<std::uint32_t>(body.size())));
}

}  // namespace

int main() {
  HANDLE input = GetStdHandle(STD_INPUT_HANDLE);
  HANDLE output = GetStdHandle(STD_OUTPUT_HANDLE);
  if (input == INVALID_HANDLE_VALUE || output == INVALID_HANDLE_VALUE) return 1;

  const HRESULT com = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  if (FAILED(com)) return 2;
  SapiBridge bridge;
  if (FAILED(bridge.Initialize())) {
    CoUninitialize();
    return 3;
  }

  bool running = true;
  bool hello_received = false;
  while (running) {
    const ULONGLONG hello_deadline =
        hello_received ? 0 : GetTickCount64() + ELTEN_SAPI_BRIDGE_HELLO_TIMEOUT_MS;
    unsigned char header[8];
    if (!(hello_received ? ReadAll(input, header, sizeof(header))
                         : ReadAllUntil(input, header, sizeof(header), hello_deadline))) {
      break;
    }
    const std::uint32_t magic = ReadU32(header);
    const std::uint8_t version = header[4] >> 4;
    const std::uint8_t command_value = header[4] & 0x0F;
    const std::uint32_t size = ReadU24(header + 5);
    if (magic != ELTEN_SAPI_BRIDGE_MAGIC || version != ELTEN_SAPI_BRIDGE_VERSION ||
        size > ELTEN_SAPI_BRIDGE_MAX_FRAME_SIZE) {
      break;
    }
    if (!hello_received && command_value != static_cast<std::uint8_t>(Command::Hello)) break;

    std::vector<unsigned char> payload(size);
    if (size > 0 &&
        !(hello_received ? ReadAll(input, payload.data(), size)
                         : ReadAllUntil(input, payload.data(), size, hello_deadline))) {
      break;
    }
    Reader reader(payload);
    std::vector<unsigned char> response;
    HRESULT result = S_OK;

    try {
      switch (static_cast<Command>(command_value)) {
        case Command::Hello:
          if (!reader.Done()) result = E_INVALIDARG;
          if (SUCCEEDED(result)) AppendU32(response, static_cast<std::uint32_t>(sizeof(void*) * 8));
          break;
        case Command::SetVoice: {
          std::string id;
          result = reader.String(id) && reader.Done() ? bridge.SetVoice(id) : E_INVALIDARG;
          break;
        }
        case Command::SetOutput: {
          std::string id;
          result = reader.String(id) && reader.Done() ? bridge.SetOutput(id) : E_INVALIDARG;
          break;
        }
        case Command::SetRate: {
          std::uint32_t value = 0;
          result = reader.U32(value) && reader.Done() ? bridge.SetRate(value) : E_INVALIDARG;
          break;
        }
        case Command::SetVolume: {
          std::uint32_t value = 0;
          result = reader.U32(value) && reader.Done() ? bridge.SetVolume(value) : E_INVALIDARG;
          break;
        }
        case Command::Speak: {
          std::uint32_t flags = 0;
          std::string text;
          result = reader.U32(flags) && reader.String(text) && reader.Done()
                       ? bridge.Speak(flags, text)
                       : E_INVALIDARG;
          break;
        }
        case Command::Pause:
          result = reader.Done() ? bridge.Pause() : E_INVALIDARG;
          break;
        case Command::Resume:
          result = reader.Done() ? bridge.Resume() : E_INVALIDARG;
          break;
        case Command::Stop:
          result = reader.Done() ? bridge.Stop() : E_INVALIDARG;
          break;
        case Command::Status:
          result = reader.Done() ? bridge.Status(response) : E_INVALIDARG;
          break;
        case Command::ListVoices:
          result = reader.Done() ? bridge.ListVoices(response) : E_INVALIDARG;
          break;
        case Command::Quit:
          result = reader.Done() ? S_OK : E_INVALIDARG;
          running = false;
          break;
        default:
          result = E_NOTIMPL;
          break;
      }
    } catch (...) {
      result = E_FAIL;
      response.clear();
    }

    if (!SendResponse(output, command_value, result, response)) break;
    if (!hello_received) {
      if (SUCCEEDED(result)) {
        hello_received = true;
      } else {
        break;
      }
    }
  }

  CoUninitialize();
  return 0;
}
