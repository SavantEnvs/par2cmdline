// Fuzz target: `par2 repair` of an untrusted PAR 1.0 volume AND an untrusted
// data file.
//
// Input layout: u32 little-endian N, then N bytes of the PAR1 volume (written
// as f.par, which selects the PAR1 path), then the rest is a data file passed
// on the command line as an extra file to scan. (N is clamped to the bytes
// available.)  Par1Repairer::Process loads the volume (LoadRecoveryFile),
// verifies the source files (VerifySourceFiles / VerifyDataFile, MD5 16k and
// full-file hashes), scans the extra file for misnamed sources
// (VerifyExtraFiles), and when the volume carries recovery data builds the
// Reed-Solomon matrix, reconstructs the missing files, writes and renames the
// target files and re-verifies them — all inside the private scratch directory.
#include "par2_fuzz_common.h"

static size_t split(const uint8_t *data, size_t size) {
  if (size < 4) return 0;
  size_t n = (size_t)data[0] | (size_t)data[1] << 8 | (size_t)data[2] << 16 |
             (size_t)data[3] << 24;
  return n > size - 4 ? size - 4 : n;
}

extern "C" size_t LLVMFuzzerCustomMutator(uint8_t *data, size_t size,
                                          size_t max_size, unsigned int seed) {
  (void)seed;
  size = LLVMFuzzerMutate(data, size, max_size);
  size_t n = split(data, size);
  if (size >= 4) par2fuzz::fix_par1_hash(data + 4, n);
  return size;
}

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
  size_t n = split(data, size);
  par2fuzz::ScratchDir dir;
  std::string p = dir.file("f.par");
  std::string d = dir.file("d.dat");
  par2fuzz::write_file(p, data + (size < 4 ? size : 4), n);
  size_t off = size < 4 ? size : 4 + n;
  par2fuzz::write_file(d, data + off, size - off);
  par2fuzz::run({"par2", "repair", "-qq", "-B", dir.path, p, d});
  return 0;
}
