# fuzz_names: unvalidated lines in `generate_name_table`

`generate_name_table` trusts its input, so two kinds of malformed line crash it (both reproduce within
seconds with libFuzzer):

- A line with no comma (`no-comma.txt`): `strtok(NULL, ",\n")` returns NULL and `strlen(name)` dereferences
  it (UBSan: "null pointer passed as argument 1", src/core.c:196). The same happens for `5,` and `,`.
- A catalog number outside `1..num_stars` (`catalog-number-out-of-range.txt`, also `0,x`):
  `table_index = catalog_number - 1` is used unchecked in `(*name_table_out)[table_index] = ...`
  (src/core.c:200), an out-of-bounds write.

Fix: check `name != NULL` and `0 < catalog_number <= num_stars` per line.

## Why the harness rejects them

`include/core.h` documents the function as parsing "data from bsc5_names.txt" where "stars with catalog
number `n` are mapped to index `n-1`" of the `num_stars`-entry table. `mayhem/harnesses/fuzz_names.c` therefore
returns `-1` for input that is not `catalog_number,name` lines with `1 <= catalog_number <= num_stars`, using the
library's own 32-byte line splitting, and fuzzes everything the format allows.

The check also keeps the target's replay healthy: Mayhem keeps the inputs its own coverage tracking finds,
including ones that reach the `-1` branch, in the target's server-side `testsuite.tar`, and replays all of it
in the regression step and the libFuzzer smoke test. With the check removed (round 1 of this port), run #2 of
this target ended `Failed to run ... regression-testing to completion` with 0 edges and the smoke test event
"libFuzzer target failed to fuzz for 5 iterations".

## Reproducing

```
clang -fsanitize=address,undefined -fno-sanitize-recover=all -g -D_GNU_SOURCE -DFUZZ_NAMES_NO_PRECONDITION_CHECK \
    -Iinclude -Idata -Ibuild "$STANDALONE_FUZZ_MAIN" mayhem/harnesses/fuzz_names.c build/liblib_astroterm.a -lm \
    $(pkg-config --libs ncursesw) -o fuzz_names-nocheck
./fuzz_names-nocheck mayhem/fuzz_names/known-findings/no-comma.txt
```

Upstream feeds this parser only its own embedded `data/bsc5_names.txt`, so the defects need a modified build or a
library user who passes their own table; they are not reachable from the command line.
