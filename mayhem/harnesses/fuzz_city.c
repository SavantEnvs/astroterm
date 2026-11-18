// `--city <name>` lookup: get_city() normalizes the user-supplied name and searches the embedded
// city table.
#include "city.h"

#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
    // A command-line argument is a NUL-terminated string without embedded NULs.
    char *name = malloc(size + 1);
    if (name == NULL)
    {
        return -1;
    }
    memcpy(name, data, size);
    name[size] = '\0';

    CityData *city = get_city(name);
    if (city != NULL)
    {
        free_city(city);
    }

    free(name);
    return 0;
}
