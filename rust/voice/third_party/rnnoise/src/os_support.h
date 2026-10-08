/* Not part of the RNNoise 0.2 release tarball, which omits it although
   vec.h (portable path) and vec_neon.h (ARM) include it. Vommet's minimal
   stand-in for Opus's os_support.h, covering what RNNoise uses. */
#ifndef OS_SUPPORT_H
#define OS_SUPPORT_H

#include <string.h>

#define OPUS_COPY(dst, src, n) (memcpy((dst), (src), (n) * sizeof(*(dst))))
#define OPUS_MOVE(dst, src, n) (memmove((dst), (src), (n) * sizeof(*(dst))))
#define OPUS_CLEAR(dst, n) (memset((dst), 0, (n) * sizeof(*(dst))))

#endif
