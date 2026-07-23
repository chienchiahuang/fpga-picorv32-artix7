#include "periph/uart.h"

/* Minimal UART bootloader. Linked at 0x0 via boot.ld, so this runs first
 * after every reset. It either loads a new program over UART into the user
 * region at USER_BASE (see ../linker.ld), or -- if no load request shows up
 * within the timeout -- jumps straight into whatever program is already
 * sitting there.
 *
 * Host-side protocol (see scripts/uart-load.py):
 *   host  -> board : 'L'                      (repeated until acked)
 *   board -> host  : 'K'                      (ack, ready for length)
 *   host  -> board : 4 bytes, length (little-endian u32)
 *   host  -> board : `length` raw bytes        (the program image)
 *   host  -> board : 1 byte, checksum (sum of those bytes, mod 256)
 *   board -> host  : 'K' (loaded, about to jump) or
 *                    'E' (bad length/checksum -- back to waiting, host may
 *                    just retry without another reset)
 */

#define SYNC_BYTE 'L'
#define ACK_BYTE  'K'
#define ERR_BYTE  'E'

#define USER_BASE     0x00000800u
#define USER_MAX_SIZE 14336u

/* No hardware timer on this SoC -- this just polls UART_STAT in a tight
 * loop. Measured on real hardware: this loop runs at ~3.84M iterations/sec
 * (300,000,000 iterations took 78.11s), so this targets ~15s -- comfortably
 * longer than scripts/uart-load.py's 8s sync-spam window, without being a
 * frustrating wait when you just want the existing firmware to boot. */
#define SYNC_TIMEOUT 60000000u

static int wait_for_sync(void)
{
	for (uint32_t i = 0; i < SYNC_TIMEOUT; i++) {
		if (uart_rx_valid() && uart_getc() == SYNC_BYTE)
			return 1;
	}
	return 0;
}

static void jump_to_user(void)
{
	void (*entry)(void) = (void (*)(void))(uintptr_t)USER_BASE;
	entry();
}

void main(void)
{
	uart_puts("\r\n--- UART bootloader ---\r\n");
	uart_puts("send 'L' now to load new firmware, else booting in ~15s...\r\n");

	while (wait_for_sync()) {
		uart_putc(ACK_BYTE);

		uint32_t length = 0;
		for (int i = 0; i < 4; i++)
			length |= (uint32_t)(uint8_t)uart_getc() << (8 * i);

		if (length > USER_MAX_SIZE) {
			uart_putc(ERR_BYTE);
			continue;
		}

		/* GCC's -Warray-bounds misfires on indexing through a raw
		 * absolute-address pointer like this (it assumes a 0-sized
		 * object at a small constant address); this loop is exactly
		 * as bounds-checked as it looks (length <= USER_MAX_SIZE). */
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Warray-bounds"
		volatile uint8_t *dst = (volatile uint8_t *)USER_BASE;
		uint8_t checksum = 0;
		for (uint32_t i = 0; i < length; i++) {
			uint8_t b = (uint8_t)uart_getc();
			dst[i] = b;
			checksum = (uint8_t)(checksum + b);
		}
#pragma GCC diagnostic pop

		if ((uint8_t)uart_getc() != checksum) {
			uart_putc(ERR_BYTE);
			continue;
		}

		uart_putc(ACK_BYTE);
		jump_to_user();
	}

	uart_puts("--- no load request, booting existing firmware ---\r\n");
	jump_to_user();
}
