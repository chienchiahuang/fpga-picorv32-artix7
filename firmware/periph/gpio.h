#ifndef PERIPH_GPIO_H
#define PERIPH_GPIO_H

#include <stdint.h>

#define GPIO_BASE  0x10000000
#define GPIO_DATA  (*(volatile uint32_t *)(GPIO_BASE + 0x00))

#endif
