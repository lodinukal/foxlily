#include <stdlib.h>

void *(*zstbMallocPtr)(size_t size) = NULL;
void *(*zstbReallocPtr)(void *ptr, size_t size) = NULL;
void (*zstbFreePtr)(void *ptr) = NULL;

#define STBI_MALLOC(size) zstbMallocPtr(size)
#define STBI_REALLOC(ptr, size) zstbReallocPtr(ptr, size)
#define STBI_FREE(ptr) zstbFreePtr(ptr)

#define STB_IMAGE_IMPLEMENTATION
#include "stb_image.h"

#define STBIR_MALLOC(size, context) zstbMallocPtr(size)
#define STBIR_FREE(ptr, context) zstbFreePtr(ptr)

#define STB_IMAGE_RESIZE_IMPLEMENTATION
#include "stb_image_resize2.h"

#define STBIW_MALLOC(size) zstbMallocPtr(size)
#define STBIW_REALLOC(ptr, size) zstbReallocPtr(ptr, size)
#define STBIW_FREE(ptr) zstbFreePtr(ptr)

#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "stb_image_write.h"

#define STB_RECT_PACK_IMPLEMENTATION
#include "stb_rect_pack.h"

#define STBTT_malloc(size, user_data) zstbMallocPtr(size)
#define STBTT_free(ptr, user_data) zstbFreePtr(ptr)

#define STB_TRUETYPE_IMPLEMENTATION
#include "stb_truetype.h"