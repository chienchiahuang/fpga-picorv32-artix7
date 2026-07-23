#ifndef PERIPH_I2C_H
#define PERIPH_I2C_H

#include <stdint.h>

#define I2C_BASE   0x30000000

#define I2C_CTRL   (*(volatile uint32_t *)(I2C_BASE + 0x00))
#define I2C_TXDATA (*(volatile uint32_t *)(I2C_BASE + 0x04))
#define I2C_RXDATA (*(volatile uint32_t *)(I2C_BASE + 0x08))
#define I2C_STATUS (*(volatile uint32_t *)(I2C_BASE + 0x0C))

#define I2C_CMD_START 0x01
#define I2C_CMD_STOP  0x02
#define I2C_CMD_WR    0x04
#define I2C_CMD_RD    0x08
#define I2C_CMD_NACK  0x10

#define I2C_STATUS_BUSY      0x01
#define I2C_STATUS_ACK_ERROR 0x02

static inline void i2c_wait_idle(void)
{
	while (I2C_STATUS & I2C_STATUS_BUSY)
		;
}

/* Write `len` bytes to a 7-bit address, START..STOP. Returns 0 if any byte
 * (including the address) got NACKed. */
static inline int i2c_write(uint8_t addr7, const uint8_t *buf, int len)
{
	I2C_TXDATA = (uint32_t)(addr7 << 1) | 0;
	I2C_CTRL   = I2C_CMD_START | I2C_CMD_WR;
	i2c_wait_idle();
	if (I2C_STATUS & I2C_STATUS_ACK_ERROR) {
		I2C_CTRL = I2C_CMD_STOP;
		i2c_wait_idle();
		return 0;
	}

	for (int i = 0; i < len; i++) {
		int last = (i == len - 1);
		I2C_TXDATA = buf[i];
		I2C_CTRL   = I2C_CMD_WR | (last ? I2C_CMD_STOP : 0);
		i2c_wait_idle();
		if (I2C_STATUS & I2C_STATUS_ACK_ERROR) {
			if (!last) {
				I2C_CTRL = I2C_CMD_STOP;
				i2c_wait_idle();
			}
			return 0;
		}
	}
	return 1;
}

/* Write `wlen` bytes (no STOP), then a repeated START and read `rlen` bytes
 * (STOP after the last). This is the standard "set register pointer, then
 * read it back" idiom used by most I2C sensor/EEPROM register maps. */
static inline int i2c_write_read(uint8_t addr7,
                                  const uint8_t *wbuf, int wlen,
                                  uint8_t *rbuf, int rlen)
{
	I2C_TXDATA = (uint32_t)(addr7 << 1) | 0;
	I2C_CTRL   = I2C_CMD_START | I2C_CMD_WR;
	i2c_wait_idle();
	if (I2C_STATUS & I2C_STATUS_ACK_ERROR) {
		I2C_CTRL = I2C_CMD_STOP;
		i2c_wait_idle();
		return 0;
	}

	for (int i = 0; i < wlen; i++) {
		I2C_TXDATA = wbuf[i];
		I2C_CTRL   = I2C_CMD_WR;
		i2c_wait_idle();
		if (I2C_STATUS & I2C_STATUS_ACK_ERROR) {
			I2C_CTRL = I2C_CMD_STOP;
			i2c_wait_idle();
			return 0;
		}
	}

	I2C_TXDATA = (uint32_t)(addr7 << 1) | 1;
	I2C_CTRL   = I2C_CMD_START | I2C_CMD_WR;
	i2c_wait_idle();
	if (I2C_STATUS & I2C_STATUS_ACK_ERROR) {
		I2C_CTRL = I2C_CMD_STOP;
		i2c_wait_idle();
		return 0;
	}

	for (int i = 0; i < rlen; i++) {
		int last = (i == rlen - 1);
		I2C_CTRL = I2C_CMD_RD | (last ? (I2C_CMD_NACK | I2C_CMD_STOP) : 0);
		i2c_wait_idle();
		rbuf[i] = (uint8_t)I2C_RXDATA;
	}
	return 1;
}

#endif
