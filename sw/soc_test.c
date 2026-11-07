#include <stdint.h>

#define UART_BASE 0x10000000u
#define DMA_BASE  0x10001000u
#define I2C_BASE  0x10002000u
#define GPIO_BASE 0x10004000u
#define SPI_BASE  0x10005000u
#define SIM_DONE  0x10003000u
#define REG32(a) (*(volatile uint32_t *)(a))

static volatile uint32_t *const uart = (volatile uint32_t *)UART_BASE;
static volatile uint32_t *const dma = (volatile uint32_t *)DMA_BASE;
static volatile uint32_t *const i2c = (volatile uint32_t *)I2C_BASE;
static volatile uint32_t *const gpio = (volatile uint32_t *)GPIO_BASE;
static volatile uint32_t *const spi = (volatile uint32_t *)SPI_BASE;

static void uart_putc(uint8_t byte)
{
    while (uart[1] & 1u) { }
    uart[0] = byte;
}

static void uart_puts(const char *s)
{
    while (*s) uart_putc((uint8_t)*s++);
}

static int dma_test(void)
{
    volatile uint8_t *const src = (volatile uint8_t *)0x00001001u;
    volatile uint8_t *const dst = (volatile uint8_t *)0x00001103u;
    for (uint32_t i = 0; i < 13; ++i) src[i] = (uint8_t)(0x31u + i * 7u);
    for (uint32_t i = 0; i < 13; ++i) dst[i] = 0;
    dma[0] = (uint32_t)src;
    dma[1] = (uint32_t)dst;
    dma[2] = 13;
    dma[3] = 1;
    while (dma[3] & 1u) { }
    if (!(dma[3] & 2u) || (dma[3] & 4u)) return 0;
    for (uint32_t i = 0; i < 13; ++i)
        if (dst[i] != (uint8_t)(0x31u + i * 7u)) return 0;
    return 1;
}

static int i2c_command(uint32_t command)
{
    i2c[1] = command;
    while (i2c[1] & 1u) { }
    return (i2c[1] & 2u) && !(i2c[1] & 4u);
}

static int i2c_test(void)
{
    i2c[2] = 8;
    if (!i2c_command(1)) return 0;
    i2c[0] = 0x5a;
    if (!i2c_command(4)) return 0;
    if (!i2c_command(2)) return 0;
    if (!i2c_command(1)) return 0;
    if (!i2c_command(8)) return 0; /* NACK final read byte */
    if ((i2c[0] & 0xffu) != 0xa5u) return 0;
    if (!i2c_command(2)) return 0;
    return 1;
}

int main(void)
{
    uart[2] = 3;
    uart[3] = 16;
    uart_puts("SOC:UART\n");
    gpio[1] = 0xa55au;
    gpio[2] = 0xffffu;
    if (gpio[0] != 0x5aa5u || gpio[1] != 0xa55au) {
        uart_puts("SOC:GPIO_FAIL\n");
        REG32(SIM_DONE) = 0xdead0004u;
        for (;;) { }
    }
    spi[2] = 2;
    spi[3] = 1; /* mode 0, chip select 0 */
    spi[0] = 0x3c;
    spi[1] = 1;
    while (spi[1] & 1u) { }
    if (!(spi[1] & 2u) || spi[0] != 0xa6u) {
        uart_puts("SOC:SPI_FAIL\n");
        REG32(SIM_DONE) = 0xdead0005u;
        for (;;) { }
    }
    if (!dma_test()) {
        uart_puts("SOC:DMA_FAIL\n");
        REG32(SIM_DONE) = 0xdead0002u;
        for (;;) { }
    }
    if (!i2c_test()) {
        uart_puts("SOC:I2C_FAIL\n");
        REG32(SIM_DONE) = 0xdead0003u;
        for (;;) { }
    }
    uart_puts("SOC:PASS\n");
    REG32(SIM_DONE) = 0x600d600du;
    for (;;) { }
}
