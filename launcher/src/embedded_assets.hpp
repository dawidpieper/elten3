#pragma once

#include <cstddef>
#include <cstdint>
#include <string>

#ifndef ELTEN_RUBY_CALL
#if defined(_WIN32)
#define ELTEN_RUBY_CALL __cdecl
#else
#define ELTEN_RUBY_CALL
#endif
#endif

namespace EltenLauncher {
using RubyValue = uintptr_t;
using RuntimeFileIntegrityFailureHandler = void (*)(const std::string &message);

struct EmbeddedRubyApi {
  using hash_new_t = RubyValue(ELTEN_RUBY_CALL *)();
  using ary_new_t = RubyValue(ELTEN_RUBY_CALL *)();
  using str_new_t = RubyValue(ELTEN_RUBY_CALL *)(const char *, long);
  using ary_push_t = RubyValue(ELTEN_RUBY_CALL *)(RubyValue, RubyValue);
  using hash_aset_t = RubyValue(ELTEN_RUBY_CALL *)(RubyValue, RubyValue, RubyValue);
  using ll2inum_t = RubyValue(ELTEN_RUBY_CALL *)(long long);
  using gv_set_t = void(ELTEN_RUBY_CALL *)(const char *, RubyValue);
  using gc_register_mark_object_t = void(ELTEN_RUBY_CALL *)(RubyValue);

  hash_new_t hash_new = nullptr;
  ary_new_t ary_new = nullptr;
  str_new_t str_new = nullptr;
  str_new_t utf8_str_new = nullptr;
  ary_push_t ary_push = nullptr;
  hash_aset_t hash_aset = nullptr;
  ll2inum_t ll2inum = nullptr;
  gv_set_t gv_set = nullptr;
  gc_register_mark_object_t gc_register_mark_object = nullptr;
};

void RegisterEmbeddedAssets(const EmbeddedRubyApi &api);
bool VerifyEmbeddedPayloadIntegrity(const std::string &root, std::string &error);
void StartRuntimeFileIntegrityCheck(const std::string &root, RuntimeFileIntegrityFailureHandler failure_handler);
void WaitForRuntimeFileIntegrity();
std::size_t EmbeddedRubyPayloadSize();
std::uint8_t EmbeddedRubyPayloadByte(std::size_t index);
}
