// Shared helpers for the par2cmdline fuzz harnesses.
//
// Every harness drives the real tool through its public entry point,
// par2::run() (include/par2/cli.h), on files staged in a fresh private
// directory under $TMPDIR, which is removed again after each input so no
// state survives between inputs.
//
// The custom mutator only *helps* the fuzzer: PAR2 packets carry an MD5 over
// their body and PAR1 volumes an MD5 "control hash" over the file, so almost
// every random mutation is discarded by the loaders before any parsing
// happens.  After libFuzzer mutates an input, the mutator recomputes those
// hashes so that mutated packets reach the packet parsers.  The fuzz target
// itself never rewrites its input: whatever bytes it is given are written to
// disk verbatim and par2 validates them as usual.
#ifndef PAR2_FUZZ_COMMON_H
#define PAR2_FUZZ_COMMON_H

#include <par2/cli.h>

#include "libpar2internal.h"  // MD5Context (the library's own MD5)

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <sstream>
#include <string>
#include <vector>

#include <unistd.h>

extern "C" size_t LLVMFuzzerMutate(uint8_t *data, size_t size, size_t max_size);

namespace par2fuzz {
using par2::MD5Context;
using par2::MD5Hash;

// A fresh private scratch directory, removed with everything in it on scope exit.
struct ScratchDir {
  std::string path;
  ScratchDir() {
    const char *t = getenv("TMPDIR");
    std::string tmpl = std::string(t && *t ? t : "/tmp") + "/par2fuzz-XXXXXX";
    std::vector<char> buf(tmpl.begin(), tmpl.end());
    buf.push_back('\0');
    if (!mkdtemp(buf.data())) { perror("mkdtemp"); abort(); }
    path = buf.data();
  }
  ~ScratchDir() {
    std::error_code ec;
    std::filesystem::remove_all(path, ec);
  }
  std::string file(const char *name) const { return path + "/" + name; }
};

inline void write_file(const std::string &p, const uint8_t *d, size_t n) {
  FILE *f = fopen(p.c_str(), "wb");
  if (!f) { perror("fopen"); abort(); }
  if (n && fwrite(d, 1, n, f) != n) { perror("fwrite"); abort(); }
  fclose(f);
}

inline par2::Result run(std::vector<std::string> args) {
  std::vector<const char *> argv;
  for (auto &a : args) argv.push_back(a.c_str());
  argv.push_back(nullptr);
  std::ostringstream sout, serr;
  return par2::run((int)args.size(), argv.data(), sout, serr);
}

inline uint64_t le64(const uint8_t *p) {
  uint64_t v = 0;
  for (int i = 7; i >= 0; i--) v = (v << 8) | p[i];
  return v;
}

// Recompute the MD5 of every well-formed PAR2 packet in buf[0..n).
// Packet header: magic[8] "PAR2\0PKT", length u64, hash[16], setid[16], type[16];
// the hash covers everything from setid to the end of the packet.
inline void fix_par2_hashes(uint8_t *buf, size_t n) {
  static const uint8_t magic[8] = {'P', 'A', 'R', '2', 0, 'P', 'K', 'T'};
  for (size_t off = 0; off + 64 <= n; ) {
    if (memcmp(buf + off, magic, 8) != 0) { off++; continue; }
    uint64_t len = le64(buf + off + 8);
    if (len < 64 || (len & 3) || len > n - off) { off++; continue; }
    MD5Context ctx;
    ctx.Update(buf + off + 32, (size_t)len - 32);
    MD5Hash h;
    ctx.Final(h);
    memcpy(buf + off + 16, h.hash, 16);
    off += (size_t)len;
  }
}

// Recompute the PAR1 control hash: MD5 over [0x20, end) stored at 0x10.
inline void fix_par1_hash(uint8_t *buf, size_t n) {
  static const uint8_t magic[8] = {'P', 'A', 'R', 0, 0, 0, 0, 0};
  if (n < 0x60 || memcmp(buf, magic, 8) != 0) return;
  MD5Context ctx;
  ctx.Update(buf + 0x20, n - 0x20);
  MD5Hash h;
  ctx.Final(h);
  memcpy(buf + 0x10, h.hash, 16);
}

}  // namespace par2fuzz

#endif
