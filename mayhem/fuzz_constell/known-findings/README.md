# fuzz_constell: unbounded allocation from the segment count

`oom-num-segments.txt` (`Ori 1000000000 1 2`): `parse_line` (src/core.c:268) calls
`malloc(num_segments * 2 * sizeof(int))` with the `atoi` of an input token, so a single line asks for 8 GB
(`libFuzzer: out-of-memory (malloc(8000000000))` with `./fuzz_constell -runs=1 oom-num-segments.txt`).
The count is checked only after the allocation. Fix: reject a `num_segments` larger than the number of
remaining tokens on the line before allocating. The input is embedded data in the shipped program, so this
is a robustness bug, not a reachable remote one. Kept out of `testsuite/` because seeds are replayed every run.
