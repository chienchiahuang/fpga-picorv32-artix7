#ifndef DRIVERS_OPT3001_H
#define DRIVERS_OPT3001_H

#include "periph/i2c.h"

/* TI OPT3001 ambient light sensor. 7-bit address is set by the sensor's
 * ADDR pin: GND=0x44, VDD=0x45, SDA=0x46, SCL=0x47. Most breakout boards
 * tie ADDR to GND. */
#define OPT3001_ADDR 0x44

#define OPT3001_REG_RESULT          0x00
#define OPT3001_REG_CONFIG          0x01
#define OPT3001_REG_MANUFACTURER_ID 0x7E
#define OPT3001_REG_DEVICE_ID       0x7F

#define OPT3001_MANUFACTURER_ID 0x5449 /* "TI" */
#define OPT3001_DEVICE_ID       0x3001

/* RN=auto-range, CT=800ms, M=continuous conversion, rest default. */
#define OPT3001_CONFIG_CONTINUOUS 0xCC10

static inline int opt3001_read_reg(uint8_t reg, uint16_t *value)
{
	uint8_t rbuf[2];
	if (!i2c_write_read(OPT3001_ADDR, &reg, 1, rbuf, 2))
		return 0;
	*value = ((uint16_t)rbuf[0] << 8) | rbuf[1];
	return 1;
}

static inline int opt3001_write_reg(uint8_t reg, uint16_t value)
{
	uint8_t wbuf[3] = { reg, (uint8_t)(value >> 8), (uint8_t)value };
	return i2c_write(OPT3001_ADDR, wbuf, 3);
}

/* Reads manufacturer/device ID -- confirms the sensor is present and
 * responding before relying on it. */
static inline int opt3001_identify(uint16_t *mfr_id, uint16_t *dev_id)
{
	return opt3001_read_reg(OPT3001_REG_MANUFACTURER_ID, mfr_id) &&
	       opt3001_read_reg(OPT3001_REG_DEVICE_ID, dev_id);
}

static inline int opt3001_start_continuous(void)
{
	return opt3001_write_reg(OPT3001_REG_CONFIG, OPT3001_CONFIG_CONTINUOUS);
}

/* Reads the latest conversion result as lux*100 (centilux), exact -- pure
 * shift of the datasheet's lux = 0.01 * 2^exponent * mantissa formula. */
static inline int opt3001_read_centilux(uint32_t *centilux)
{
	uint16_t raw;
	if (!opt3001_read_reg(OPT3001_REG_RESULT, &raw))
		return 0;
	uint32_t exponent = (raw >> 12) & 0xF;
	uint32_t mantissa = raw & 0x0FFF;
	*centilux = mantissa << exponent;
	return 1;
}

#endif
