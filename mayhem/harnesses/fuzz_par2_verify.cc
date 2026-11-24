// Fuzz target: `par2 verify` of an untrusted .par2 recovery file.
// Reaches Par2Repairer::LoadPacketsFromFile and every packet loader (main,
// file description, IFSC verification, recovery slice, creator, unicode
// filename), CheckPacketConsistency, the source-file list and the
// verification hash table.
#include "par2_fuzz_common.h"

extern "C" size_t LLVMFuzzerCustomMutator(uint8_t *data, size_t size,
                                          size_t max_size, unsigned int seed) {
  (void)seed;
  size = LLVMFuzzerMutate(data, size, max_size);
  par2fuzz::fix_par2_hashes(data, size);
  return size;
}

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
  par2fuzz::ScratchDir dir;
  std::string f = dir.file("f.par2");
  par2fuzz::write_file(f, data, size);
  par2fuzz::run({"par2", "verify", "-qq", "-t1", "-m16", "-B", dir.path, f});
  return 0;
}
