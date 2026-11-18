// Constellation-figure table parser (data/bsc5_constellations.txt format): `NAME N s1 s2 ...` lines.
// Reaches parse_line(), the code changed by upstream's fix for #91 (stack buffer overflow).
#include "core.h"

#include <stddef.h>
#include <stdint.h>

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
    struct Constell *table = NULL;
    unsigned int num = 0;

    // generate_constell_table() documents `false` for malformed data; it rejects size == 0 itself.
    if (!generate_constell_table(data, size, &table, &num))
    {
        return -1;
    }

    free_constells(table, num);
    return 0;
}
