#include <stddef.h>
#include <stdlib.h>

#undef malloc
void *rpl_malloc(size_t n);

#if __has_include("config.h")
#include "config.h"
#endif