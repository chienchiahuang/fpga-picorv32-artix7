#ifndef PERIPH_UART_H
#define PERIPH_UART_H

#include <stdint.h>

#define UART_BASE  0x20000000

#define UART_TX    (*(volatile uint32_t *)(UART_BASE + 0x00))
#define UART_RX    (*(volatile uint32_t *)(UART_BASE + 0x04))
#define UART_STAT  (*(volatile uint32_t *)(UART_BASE + 0x08))

static inline void uart_putc(char c)
{
	while (UART_STAT & 1)
		;
	UART_TX = (uint32_t)c;
}

static inline void uart_puts(const char *s)
{
	while (*s)
		uart_putc(*s++);
}

static inline int uart_rx_valid(void)
{
	return (UART_STAT & 0x2) != 0;
}

static inline char uart_getc(void)
{
	while (!uart_rx_valid())
		;
	return (char)UART_RX;
}

static inline void uart_puthex(uint32_t v)
{
	static const char hex[] = "0123456789abcdef";
	for (int i = 28; i >= 0; i -= 4)
		uart_putc(hex[(v >> i) & 0xf]);
}

#endif
