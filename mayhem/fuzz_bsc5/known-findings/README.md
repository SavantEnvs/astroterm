# fuzz_bsc5: unvalidated header and entry values

`fuzz_bsc5.c` passes the input to `parse_entries` and `generate_star_table` unfiltered, so Mayhem
reports the defects below.

- Header star count (`STARN`, int32 at byte 8) sizes `malloc(num_entries * sizeof(struct Entry))` in
  `parse_entries` (src/parse_BSC5.c:64) before any entry is read: a 29-byte input asks for gigabytes
  (`libFuzzer: out-of-memory`). The `num_entries * sizeof` product is also unchecked, and `abs(INT_MIN)` is
  undefined. If the data is shorter than the header claims, `parse_entries` returns false.
- `generate_star_table` (src/core.c:29) casts each entry's `XNO` float to int: NaN or out-of-range values are
  undefined behaviour (UBSan: "-nan is outside the range of representable values of type 'int'").
- Its glyph tables have 10 entries but the index comes from `map_float_to_int_range` over -1.46..7.96, so
  an entry magnitude outside that range reads out of bounds (UBSan: "index 288 out of bounds for type
  'const char[10]'", src/core.c:56; reproduced by libFuzzer within seconds).

Fix: validate `STARN` against the data length and magnitudes against the mapped range.

Upstream feeds this parser only the catalog it embeds at build time (`data/bsc5`), so the defects need a
substituted catalog; they are not reachable from the command line.
