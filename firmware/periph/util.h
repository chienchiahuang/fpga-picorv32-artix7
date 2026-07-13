#ifndef DRIVERS_UTIL_H
#define DRIVERS_UTIL_H

static inline void delay(volatile int n)
{
	while (n-- > 0)
		;
}

#endif
