#pragma once

#include <array>
#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

namespace EltenLauncher {

inline uint32_t Sha256RotateRight(uint32_t value, uint32_t bits) {
  return (value >> bits) | (value << (32 - bits));
}

inline std::array<uint8_t, 32> Sha256Digest(const uint8_t *data, std::size_t size) {
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

  std::vector<uint8_t> message;
  if (size > 0) message.assign(data, data + size);
  uint64_t bitSize = static_cast<uint64_t>(size) * 8;
  message.push_back(0x80);
  while ((message.size() % 64) != 56) message.push_back(0);
  for (int shift = 56; shift >= 0; shift -= 8) {
    message.push_back(static_cast<uint8_t>((bitSize >> shift) & 0xff));
  }

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
      uint32_t s0 = Sha256RotateRight(w[i - 15], 7) ^ Sha256RotateRight(w[i - 15], 18) ^ (w[i - 15] >> 3);
      uint32_t s1 = Sha256RotateRight(w[i - 2], 17) ^ Sha256RotateRight(w[i - 2], 19) ^ (w[i - 2] >> 10);
      w[i] = w[i - 16] + s0 + w[i - 7] + s1;
    }

    uint32_t a = h[0], b = h[1], c = h[2], d = h[3];
    uint32_t e = h[4], f = h[5], g = h[6], hh = h[7];
    for (int i = 0; i < 64; ++i) {
      uint32_t s1 = Sha256RotateRight(e, 6) ^ Sha256RotateRight(e, 11) ^ Sha256RotateRight(e, 25);
      uint32_t ch = (e & f) ^ ((~e) & g);
      uint32_t temp1 = hh + s1 + ch + k[i] + w[i];
      uint32_t s0 = Sha256RotateRight(a, 2) ^ Sha256RotateRight(a, 13) ^ Sha256RotateRight(a, 22);
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

inline std::string Hex(const uint8_t *data, std::size_t size) {
  static const char digits[] = "0123456789abcdef";
  std::string out;
  out.reserve(size * 2);
  for (std::size_t i = 0; i < size; ++i) {
    out.push_back(digits[data[i] >> 4]);
    out.push_back(digits[data[i] & 0x0f]);
  }
  return out;
}

inline std::string Sha256Hex(const unsigned char *data, std::size_t size) {
  auto digest = Sha256Digest(reinterpret_cast<const uint8_t *>(data), size);
  return Hex(digest.data(), digest.size());
}

inline std::string Sha256Hex(const std::vector<unsigned char> &bytes) {
  return Sha256Hex(bytes.data(), bytes.size());
}

inline std::array<uint8_t, 32> HmacSha256Digest(const uint8_t *key, std::size_t key_size, const uint8_t *data, std::size_t size) {
  constexpr std::size_t block_size = 64;
  std::array<uint8_t, block_size> normalized_key = {};
  if (key_size > block_size) {
    auto digest = Sha256Digest(key, key_size);
    for (std::size_t i = 0; i < digest.size(); ++i) normalized_key[i] = digest[i];
  } else if (key_size > 0) {
    for (std::size_t i = 0; i < key_size; ++i) normalized_key[i] = key[i];
  }

  std::vector<uint8_t> inner;
  inner.reserve(block_size + size);
  for (std::size_t i = 0; i < block_size; ++i) inner.push_back(normalized_key[i] ^ 0x36);
  if (size > 0) inner.insert(inner.end(), data, data + size);
  auto inner_digest = Sha256Digest(inner.data(), inner.size());

  std::vector<uint8_t> outer;
  outer.reserve(block_size + inner_digest.size());
  for (std::size_t i = 0; i < block_size; ++i) outer.push_back(normalized_key[i] ^ 0x5c);
  outer.insert(outer.end(), inner_digest.begin(), inner_digest.end());
  return Sha256Digest(outer.data(), outer.size());
}

inline std::array<uint8_t, 32> HmacSha256Digest(const std::vector<unsigned char> &key, const std::vector<unsigned char> &data) {
  return HmacSha256Digest(reinterpret_cast<const uint8_t *>(key.data()), key.size(),
                          reinterpret_cast<const uint8_t *>(data.data()), data.size());
}

} // namespace EltenLauncher
