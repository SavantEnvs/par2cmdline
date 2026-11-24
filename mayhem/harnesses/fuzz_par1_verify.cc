// Fuzz target: `par2 verify` of an untrusted PAR 1.0 volume (.par).
// The .par extension selects the PAR1 path (CommandLine -> par1repair ->
// Par1Repairer::Process), reaching Par1Repairer::LoadRecoveryFile (file header,
// file-entry list, UTF-16 names) and the source-file verification.
#include "par2_fuzz_common.h"

extern "C" size_t LLVMFuzzerCustomMutator(uint8_t *data, size_t size,
                                          size_t max_size, unsigned int seed) {
  (void)seed;
  size = LLVMFuzzerMutate(data, size, max_size);
  par2fuzz::fix_par1_hash(data, size);
  return size;
}

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
  par2fuzz::ScratchDir dir;
  std::string f = dir.file("f.par");
  par2fuzz::write_file(f, data, size);
  par2fuzz::run({"par2", "verify", "-qq", "-B", dir.path, f});
  return 0;
}
