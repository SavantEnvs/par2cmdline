// Linked only into the -standalone reproducers: they run one input and never
// call the custom mutator, but its reference to LLVMFuzzerMutate (provided by
// libFuzzer) still has to resolve.
#include <cstddef>
#include <cstdint>
#include <cstdlib>
extern "C" size_t LLVMFuzzerMutate(uint8_t *, size_t, size_t) { abort(); }
