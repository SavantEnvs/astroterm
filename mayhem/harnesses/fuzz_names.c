// Star-name table parser (data/bsc5_names.txt format): `catalog_number,name` lines.
#include "core.h"

#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

// Number of stars in the Yale Bright Star Catalog; main() passes the parsed entry count here.
#define NUM_STARS 9110

// Same line-buffer size and line splitting as generate_name_table (src/core.c).
#define LINE_BUF 32

// Precondition from include/core.h: generate_name_table "parses data from bsc5_names.txt" and "stars with
// catalog number `n` are mapped to index `n-1`" of the `num_stars`-entry table, so every non-empty line must
// be `catalog_number,name` with 1 <= catalog_number <= num_stars. Input outside that format is rejected with
// -1. The library does not check it (known-findings/README.md; build with -DFUZZ_NAMES_NO_PRECONDITION_CHECK
// to reproduce).
static int input_follows_format(const uint8_t *data, size_t size)
{
    size_t offset = 0;
    while (offset < size)
    {
        char buffer[LINE_BUF];
        size_t i = 0;
        while (offset + i < size && data[offset + i] != '\n' && i < LINE_BUF - 1)
        {
            buffer[i] = (char)data[offset + i];
            i++;
        }
        buffer[i] = '\0';
        offset += i + 1;

        if (buffer[0] == '\0')
        {
            continue;
        }

        char *number = strtok(buffer, ",");
        if (number == NULL)
        {
            return 0;
        }
        char *end = NULL;
        long catalog_number = strtol(number, &end, 10);
        if (end == number || catalog_number < 1 || catalog_number > NUM_STARS)
        {
            return 0;
        }
        if (strtok(NULL, ",\n") == NULL)
        {
            return 0;
        }
    }
    return 1;
}

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
#ifndef FUZZ_NAMES_NO_PRECONDITION_CHECK
    if (!input_follows_format(data, size))
    {
        return -1;
    }
#endif

    struct StarName *table = NULL;
    if (!generate_name_table(data, size, &table, NUM_STARS))
    {
        return -1;
    }

    free_star_names(table, NUM_STARS);
    return 0;
}
