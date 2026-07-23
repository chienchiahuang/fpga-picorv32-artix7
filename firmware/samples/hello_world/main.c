#include "periph/gpio.h"
#include "periph/uart.h"
#include "periph/util.h"

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
