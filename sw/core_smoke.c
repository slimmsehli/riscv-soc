#include <stdint.h>

static volatile uint32_t *const tohost = (uint32_t *)0x10000000u;

int main(void)
{
    volatile uint32_t data[8];
    uint32_t sum = 0;

    for (uint32_t i = 0; i < 8; ++i) {
        data[i] = (i + 3u) * 7u;
        sum += data[i];
    }

    /* Exercise a load, store, branch, call/return, and stack use. */
    if (sum != 364u || data[3] != 42u)
        *tohost = 0xdead0001u;
    else
        *tohost = 0x600d600du;

    for (;;)
        __asm__ volatile ("" ::: "memory");
}
