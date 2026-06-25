#pragma once

#include <algorithm>
#include <array>
#include <cstddef>
#include <cstdint>
#include <vector>

namespace EltenLauncher {

inline uint32_t Blake3RotateRight(uint32_t value, uint32_t bits) {
  return (value >> bits) | (value << (32 - bits));
}

inline uint32_t Blake3Load32(const uint8_t *bytes) {
  return static_cast<uint32_t>(bytes[0]) |
         (static_cast<uint32_t>(bytes[1]) << 8) |
         (static_cast<uint32_t>(bytes[2]) << 16) |
         (static_cast<uint32_t>(bytes[3]) << 24);
}

inline void Blake3Store32(uint8_t *bytes, uint32_t value) {
  bytes[0] = static_cast<uint8_t>(value & 0xff);
  bytes[1] = static_cast<uint8_t>((value >> 8) & 0xff);
  bytes[2] = static_cast<uint8_t>((value >> 16) & 0xff);
  bytes[3] = static_cast<uint8_t>((value >> 24) & 0xff);
}

inline std::array<uint32_t, 16> Blake3BlockWords(const uint8_t *data, std::size_t size) {
  std::array<uint8_t, 64> block = {};
  for (std::size_t i = 0; i < size; ++i) block[i] = data[i];
  std::array<uint32_t, 16> words = {};
  for (std::size_t i = 0; i < words.size(); ++i) words[i] = Blake3Load32(block.data() + i * 4);
  return words;
}

inline void Blake3G(std::array<uint32_t, 16> &state, std::size_t a, std::size_t b, std::size_t c, std::size_t d,
                    uint32_t mx, uint32_t my) {
  state[a] = state[a] + state[b] + mx;
  state[d] = Blake3RotateRight(state[d] ^ state[a], 16);
  state[c] = state[c] + state[d];
  state[b] = Blake3RotateRight(state[b] ^ state[c], 12);
  state[a] = state[a] + state[b] + my;
  state[d] = Blake3RotateRight(state[d] ^ state[a], 8);
  state[c] = state[c] + state[d];
  state[b] = Blake3RotateRight(state[b] ^ state[c], 7);
}

inline std::array<uint32_t, 16> Blake3Compress(const std::array<uint32_t, 8> &cv,
                                               const std::array<uint32_t, 16> &block_words,
                                               uint64_t counter, uint32_t block_len, uint32_t flags) {
  static const std::array<uint32_t, 8> iv = {
      0x6A09E667, 0xBB67AE85, 0x3C6EF372, 0xA54FF53A,
      0x510E527F, 0x9B05688C, 0x1F83D9AB, 0x5BE0CD19,
  };
  static const std::array<std::size_t, 16> permutation = {
      2, 6, 3, 10, 7, 0, 4, 13, 1, 11, 12, 5, 9, 14, 15, 8,
  };

  std::array<uint32_t, 16> state = {
      cv[0], cv[1], cv[2], cv[3], cv[4], cv[5], cv[6], cv[7],
      iv[0], iv[1], iv[2], iv[3],
      static_cast<uint32_t>(counter),
      static_cast<uint32_t>(counter >> 32),
      block_len,
      flags,
  };
  std::array<uint32_t, 16> words = block_words;

  for (int round = 0; round < 7; ++round) {
    Blake3G(state, 0, 4, 8, 12, words[0], words[1]);
    Blake3G(state, 1, 5, 9, 13, words[2], words[3]);
    Blake3G(state, 2, 6, 10, 14, words[4], words[5]);
    Blake3G(state, 3, 7, 11, 15, words[6], words[7]);
    Blake3G(state, 0, 5, 10, 15, words[8], words[9]);
    Blake3G(state, 1, 6, 11, 12, words[10], words[11]);
    Blake3G(state, 2, 7, 8, 13, words[12], words[13]);
    Blake3G(state, 3, 4, 9, 14, words[14], words[15]);

    std::array<uint32_t, 16> permuted = {};
    for (std::size_t i = 0; i < words.size(); ++i) permuted[i] = words[permutation[i]];
    words = permuted;
  }

  std::array<uint32_t, 16> output = {};
  for (std::size_t i = 0; i < 8; ++i) {
    output[i] = state[i] ^ state[i + 8];
    output[i + 8] = state[i + 8] ^ cv[i];
  }
  return output;
}

inline std::array<uint32_t, 8> Blake3FirstWords(const std::array<uint32_t, 16> &words) {
  std::array<uint32_t, 8> out = {};
  for (std::size_t i = 0; i < out.size(); ++i) out[i] = words[i];
  return out;
}

inline std::array<uint8_t, 32> Blake3WordsToBytes(const std::array<uint32_t, 8> &words) {
  std::array<uint8_t, 32> out = {};
  for (std::size_t i = 0; i < words.size(); ++i) Blake3Store32(out.data() + i * 4, words[i]);
  return out;
}

inline std::array<uint32_t, 8> Blake3KeyWords(const uint8_t *key, std::size_t key_size) {
  static const std::array<uint32_t, 8> iv = {
      0x6A09E667, 0xBB67AE85, 0x3C6EF372, 0xA54FF53A,
      0x510E527F, 0x9B05688C, 0x1F83D9AB, 0x5BE0CD19,
  };
  if (key == nullptr || key_size == 0) return iv;

  std::array<uint8_t, 32> normalized = {};
  std::size_t copy_size = std::min<std::size_t>(normalized.size(), key_size);
  for (std::size_t i = 0; i < copy_size; ++i) normalized[i] = key[i];

  std::array<uint32_t, 8> words = {};
  for (std::size_t i = 0; i < words.size(); ++i) words[i] = Blake3Load32(normalized.data() + i * 4);
  return words;
}

inline std::array<uint32_t, 8> Blake3ChunkOutput(const std::array<uint32_t, 8> &key_words,
                                                 const uint8_t *data, std::size_t size,
                                                 uint64_t chunk_counter, uint32_t flags, bool root) {
  constexpr std::size_t block_len = 64;
  constexpr uint32_t chunk_start = 1u;
  constexpr uint32_t chunk_end = 2u;
  constexpr uint32_t root_flag = 8u;

  std::array<uint32_t, 8> cv = key_words;
  std::size_t offset = 0;
  while (offset + block_len < size) {
    uint32_t block_flags = flags;
    if (offset == 0) block_flags |= chunk_start;
    cv = Blake3FirstWords(Blake3Compress(cv, Blake3BlockWords(data + offset, block_len),
                                         chunk_counter, static_cast<uint32_t>(block_len), block_flags));
    offset += block_len;
  }

  std::size_t remaining = size - offset;
  uint32_t block_flags = flags | chunk_end;
  if (offset == 0) block_flags |= chunk_start;
  if (root) block_flags |= root_flag;
  const uint8_t *final_data = remaining == 0 ? reinterpret_cast<const uint8_t *>("") : data + offset;
  return Blake3FirstWords(Blake3Compress(cv, Blake3BlockWords(final_data, remaining),
                                         chunk_counter, static_cast<uint32_t>(remaining), block_flags));
}

inline std::size_t Blake3LargestPowerOfTwoLessThan(std::size_t value) {
  std::size_t power = 1;
  while ((power << 1) < value) power <<= 1;
  return power;
}

inline std::array<uint32_t, 8> Blake3ParentOutput(const std::array<uint32_t, 8> &left,
                                                  const std::array<uint32_t, 8> &right,
                                                  const std::array<uint32_t, 8> &key_words,
                                                  uint32_t flags, bool root) {
  constexpr uint32_t parent = 4u;
  constexpr uint32_t root_flag = 8u;
  std::array<uint32_t, 16> block_words = {};
  for (std::size_t i = 0; i < 8; ++i) {
    block_words[i] = left[i];
    block_words[i + 8] = right[i];
  }
  return Blake3FirstWords(Blake3Compress(key_words, block_words, 0, 64, flags | parent | (root ? root_flag : 0)));
}

inline std::array<uint32_t, 8> Blake3SubtreeCv(const std::array<uint32_t, 8> &key_words,
                                               const uint8_t *data, std::size_t size,
                                               uint64_t chunk_counter, uint32_t flags) {
  constexpr std::size_t chunk_len = 1024;
  std::size_t chunks = (size + chunk_len - 1) / chunk_len;
  if (chunks <= 1) return Blake3ChunkOutput(key_words, data, size, chunk_counter, flags, false);

  std::size_t left_chunks = Blake3LargestPowerOfTwoLessThan(chunks);
  std::size_t left_size = left_chunks * chunk_len;
  auto left = Blake3SubtreeCv(key_words, data, left_size, chunk_counter, flags);
  auto right = Blake3SubtreeCv(key_words, data + left_size, size - left_size, chunk_counter + left_chunks, flags);
  return Blake3ParentOutput(left, right, key_words, flags, false);
}

inline std::array<uint8_t, 32> Blake3Digest(const uint8_t *data, std::size_t size) {
  constexpr std::size_t chunk_len = 1024;
  auto key_words = Blake3KeyWords(nullptr, 0);
  std::size_t chunks = (size + chunk_len - 1) / chunk_len;
  if (chunks <= 1) return Blake3WordsToBytes(Blake3ChunkOutput(key_words, data, size, 0, 0, true));

  std::size_t left_chunks = Blake3LargestPowerOfTwoLessThan(chunks);
  std::size_t left_size = left_chunks * chunk_len;
  auto left = Blake3SubtreeCv(key_words, data, left_size, 0, 0);
  auto right = Blake3SubtreeCv(key_words, data + left_size, size - left_size, left_chunks, 0);
  return Blake3WordsToBytes(Blake3ParentOutput(left, right, key_words, 0, true));
}

inline std::array<uint8_t, 32> Blake3KeyedDigest(const uint8_t *key, std::size_t key_size,
                                                const uint8_t *data, std::size_t size) {
  constexpr std::size_t chunk_len = 1024;
  constexpr uint32_t keyed_hash = 16u;
  auto key_words = Blake3KeyWords(key, key_size);
  std::size_t chunks = (size + chunk_len - 1) / chunk_len;
  if (chunks <= 1) return Blake3WordsToBytes(Blake3ChunkOutput(key_words, data, size, 0, keyed_hash, true));

  std::size_t left_chunks = Blake3LargestPowerOfTwoLessThan(chunks);
  std::size_t left_size = left_chunks * chunk_len;
  auto left = Blake3SubtreeCv(key_words, data, left_size, 0, keyed_hash);
  auto right = Blake3SubtreeCv(key_words, data + left_size, size - left_size, left_chunks, keyed_hash);
  return Blake3WordsToBytes(Blake3ParentOutput(left, right, key_words, keyed_hash, true));
}

inline std::array<uint8_t, 32> Blake3KeyedDigest(const std::vector<unsigned char> &key,
                                                const std::vector<unsigned char> &data) {
  return Blake3KeyedDigest(reinterpret_cast<const uint8_t *>(key.data()), key.size(),
                           reinterpret_cast<const uint8_t *>(data.data()), data.size());
}

} // namespace EltenLauncher
