#include <stdint.h>

#define GPIO_BASE  0x10000000
#define UART_BASE  0x20000000

#define GPIO_DATA  (*(volatile uint32_t *)(GPIO_BASE + 0x00))

#define UART_TX    (*(volatile uint32_t *)(UART_BASE + 0x00))
#define UART_RX    (*(volatile uint32_t *)(UART_BASE + 0x04))
#define UART_STAT  (*(volatile uint32_t *)(UART_BASE + 0x08))

static void delay(volatile int n)
{
	while (n-- > 0)
		;
}

static void uart_putc(char c)
{
	while (UART_STAT & 1)
		;
	UART_TX = (uint32_t)c;
}

static void uart_puts(const char *s)
{
	while (*s)
		uart_putc(*s++);
}

static void uart_puthex(uint32_t v)
{
	static const char hex[] = "0123456789abcdef";
	for (int i = 28; i >= 0; i -= 4)
		uart_putc(hex[(v >> i) & 0xf]);
}

void main(void)
{
	uart_puts("\r\n--- PicoRV32 SoC on Arty A7 ---\r\n");
	uart_puts("Hello, RISC-V!\r\n");

	uint32_t count = 0;
	while (1) {
		GPIO_DATA = count & 0xf;
		uart_puts("tick ");
		uart_puthex(count);
		uart_puts("\r\n");
		count++;
		delay(2500000);
	}
}
