#include <stdlib.h>

extern void *(*zstbMallocPtr)(size_t size);
extern void (*zstbFreePtr)(void *ptr);

#define MSDF_malloc(size) zstbMallocPtr(size)
#define MSDF_free(ptr) zstbFreePtr(ptr)

#define MSDF_IMPLEMENTATION
#include "msdf.h"
