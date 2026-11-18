// Yale Bright Star Catalog (BSC5) binary parser, then the star table built from its entries —
// the same sequence main() runs on the embedded catalog.
#include "core.h"
#include "parse_BSC5.h"

#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
    struct Entry *entries = NULL;
    unsigned int num_stars = 0;

    // parse_entries() takes a non-const pointer but only reads from it.
    if (!parse_entries((uint8_t *)data, size, &entries, &num_stars))
    {
        return -1;
    }

    // main() passes a name table with one (possibly NULL) label per star.
    struct StarName *names = calloc(num_stars ? num_stars : 1, sizeof(struct StarName));
    struct Star *stars = NULL;
    int *num_by_mag = NULL;

    if (names != NULL && generate_star_table(&stars, entries, names, num_stars))
    {
        star_numbers_by_magnitude(&num_by_mag, stars, num_stars);
    }

    free(num_by_mag);
    free_stars(stars, num_stars);
    free(names);
    free(entries);
    return 0;
}
