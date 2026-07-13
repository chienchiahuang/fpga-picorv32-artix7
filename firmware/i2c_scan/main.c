#include "periph/i2c.h"
#include "periph/uart.h"

/* I2C bus scanner: sends START + address(write) + STOP to every 7-bit
 * address and reports which ones ACK. Useful for confirming the bus is
 * wired/powered/pulled-up correctly before chasing a specific device's
 * address strapping. */

static int probe(uint8_t addr7)
{
	I2C_TXDATA = (uint32_t)(addr7 << 1) | 0;
	I2C_CTRL   = I2C_CMD_START | I2C_CMD_WR | I2C_CMD_STOP;
	i2c_wait_idle();
	return !(I2C_STATUS & I2C_STATUS_ACK_ERROR);
}

void main(void)
{
	uart_puts("\r\n--- I2C bus scanner ---\r\n");

	int found = 0;
	/* 0x00-0x07 and 0x78-0x7F are reserved by the I2C spec; skip them. */
	for (uint32_t addr = 0x08; addr <= 0x77; addr++) {
		if (probe((uint8_t)addr)) {
			uart_puts("ACK at address 0x");
			uart_puthex(addr);
			uart_puts("\r\n");
			found = 1;
		}
	}

	if (!found)
		uart_puts("no devices found -- check power, SDA/SCL wiring, and pull-ups\r\n");

	uart_puts("--- scan complete ---\r\n");
	while (1)
		;
}
