#pragma once

#include "embedded_assets.hpp"

#include <cstdint>

namespace EltenLauncher {

struct StampRubyApi {
  using cfunc_1_t = RubyValue(ELTEN_RUBY_CALL *)(RubyValue, RubyValue);

  using define_global_function_t = void(ELTEN_RUBY_CALL *)(const char *, cfunc_1_t, int);
  using hash_new_t = RubyValue(ELTEN_RUBY_CALL *)();
  using str_new_t = RubyValue(ELTEN_RUBY_CALL *)(const char *, long);
  using hash_aset_t = RubyValue(ELTEN_RUBY_CALL *)(RubyValue, RubyValue, RubyValue);
  using raise_t = void(ELTEN_RUBY_CALL *)(RubyValue, const char *, ...);
  using obj_is_kind_of_t = RubyValue(ELTEN_RUBY_CALL *)(RubyValue, RubyValue);
  using string_value_ptr_t = char *(ELTEN_RUBY_CALL *)(RubyValue *);
  using intern_t = uintptr_t(ELTEN_RUBY_CALL *)(const char *);
  using funcallv_t = RubyValue(ELTEN_RUBY_CALL *)(RubyValue, uintptr_t, int, const RubyValue *);
  using num2long_t = long(ELTEN_RUBY_CALL *)(RubyValue);
  using ll2inum_t = RubyValue(ELTEN_RUBY_CALL *)(long long);

  define_global_function_t define_global_function = nullptr;
  hash_new_t hash_new = nullptr;
  str_new_t str_new = nullptr;
  str_new_t utf8_str_new = nullptr;
  hash_aset_t hash_aset = nullptr;
  raise_t raise = nullptr;
  obj_is_kind_of_t obj_is_kind_of = nullptr;
  string_value_ptr_t string_value_ptr = nullptr;
  intern_t intern = nullptr;
  funcallv_t funcallv = nullptr;
  num2long_t num2long = nullptr;
  ll2inum_t ll2inum = nullptr;
  RubyValue c_string = 0;
  RubyValue e_arg_error = 0;
  RubyValue e_runtime_error = 0;
};

void RegisterStampFunction(const StampRubyApi &api);

} // namespace EltenLauncher
