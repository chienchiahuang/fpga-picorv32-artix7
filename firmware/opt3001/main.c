#include "periph/uart.h"
#include "periph/util.h"
#include "drivers/opt3001.h"

/* This SoC has no hardware multiply/divide (rv32i only) and firmware links
 * -nostdlib (no libgcc), so plain '/' and '%' on runtime values would fail
 * to link (__divsi3/__umodsi3 undefined). Everything below sticks to
 * shifts, subtraction and compares. */

static uint32_t divmod100(uint32_t n, uint32_t *rem)
{
	uint32_t d = 100, bit = 1, q = 0;

	while (n >= d && !(d & 0x80000000)) {
		d <<= 1;
		bit <<= 1;
	}
	while (bit) {
		if (n >= d) {
			n -= d;
			q |= bit;
		}
		d >>= 1;
		bit >>= 1;
	}
	if (rem)
		*rem = n;
	return q;
}

/* Splits v (assumed 0..99) into its tens and ones digit. */
static void split2(uint32_t v, uint32_t *tens, uint32_t *ones)
{
	uint32_t t = 0;
	while (v >= 10) {
		v -= 10;
		t++;
	}
	*tens = t;
	*ones = v;
}

static void uart_put2digits(uint32_t v)
{
	uint32_t tens, ones;
	split2(v, &tens, &ones);
	uart_putc((char)('0' + tens));
	uart_putc((char)('0' + ones));
}

static void uart_putdec(uint32_t v)
{
	uint32_t groups[5]; /* max uint32 ~4.3e9 -> 5 groups of 2 digits */
	int n = 0;

	if (v == 0) {
		uart_putc('0');
		return;
	}
	while (v > 0) {
		uint32_t rem;
		v = divmod100(v, &rem);
		groups[n++] = rem;
	}

	n--;
	if (groups[n] >= 10) {
		uart_put2digits(groups[n]);
	} else {
		uart_putc((char)('0' + groups[n]));
	}
	while (n > 0) {
		n--;
		uart_put2digits(groups[n]);
	}
}

static void print_lux(uint32_t centilux)
{
	uint32_t whole, frac;

	whole = divmod100(centilux, &frac);

	uart_puts("lux = ");
	uart_putdec(whole);
	uart_putc('.');
	uart_put2digits(frac);
	uart_puts("\r\n");
}

void main(void)
{
	uart_puts("\r\n--- OPT3001 ambient light sensor demo ---\r\n");

	uint16_t mfr_id = 0, dev_id = 0;
	if (!opt3001_identify(&mfr_id, &dev_id)) {
		uart_puts("ERROR: no ACK from OPT3001 -- check wiring/address/pull-ups\r\n");
		while (1)
			;
	}

	uart_puts("manufacturer ID = 0x");
	uart_puthex(mfr_id);
	uart_puts(" (expect 0x00005449 = \"TI\")\r\n");
	uart_puts("device ID       = 0x");
	uart_puthex(dev_id);
	uart_puts(" (expect 0x00003001)\r\n");

	if (!opt3001_start_continuous()) {
		uart_puts("ERROR: failed to configure OPT3001\r\n");
		while (1)
			;
	}

	uart_puts("configured for continuous conversion, 800ms\r\n\r\n");

	while (1) {
		delay(85000000); /* rough busy-wait, comfortably longer than the 800ms conversion time */

		uint32_t centilux;
		if (!opt3001_read_centilux(&centilux)) {
			uart_puts("ERROR: read failed\r\n");
			continue;
		}
		print_lux(centilux);
	}
}
