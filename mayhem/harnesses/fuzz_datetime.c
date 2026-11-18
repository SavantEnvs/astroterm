// `--datetime <yyyy-mm-ddThh:mm:ss>`: parse the string the way main() does, convert it to a Julian
// date, and compute where the planets and the Moon are at that instant.
#include "astro.h"
#include "core.h"
#include "core_position.h"
#include "data/keplerian_elements.h"

#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
    // A command-line argument is a NUL-terminated string without embedded NULs.
    char *text = malloc(size + 1);
    if (text == NULL)
    {
        return -1;
    }
    memcpy(text, data, size);
    text[size] = '\0';

    // main() leaves this uninitialised; zeroing it keeps each input's result a function of that input.
    struct tm datetime;
    memset(&datetime, 0, sizeof(datetime));

    bool parsed = string_to_time(text, &datetime);
    free(text);
    if (!parsed)
    {
        return -1;
    }

    double julian_date = datetime_to_julian_date(&datetime);

    struct Planet *planets = NULL;
    struct Moon moon;
    if (generate_planet_table(&planets, planet_elements, planet_rates, planet_extras) &&
        generate_moon_object(&moon, &moon_elements, &moon_rates))
    {
        const double latitude = 0.6; // radians, an arbitrary mid-latitude observer
        const double longitude = -1.3;
        update_planet_positions(planets, julian_date, latitude, longitude);
        update_moon_position(&moon, julian_date, latitude, longitude);
        update_moon_phase(&moon, julian_date, latitude);

        int year, month, day;
        julian_to_gregorian(julian_date, &year, &month, &day);
        (void)moon_age_to_phase(calc_moon_age(julian_date));
        (void)julian_date_to_datetime(julian_date);
    }

    free_planets(planets, NUM_PLANETS);
    return 0;
}
