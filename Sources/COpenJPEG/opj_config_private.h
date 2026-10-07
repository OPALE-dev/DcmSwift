/* Hand-written equivalent of OpenJPEG's opj_config_private.h.cmake.in for
 * SwiftPM, valid on Apple platforms and Linux (glibc). */
#define OPJ_PACKAGE_VERSION "2.5.4"
#define OPJ_HAVE_FSEEKO 1
#define OPJ_HAVE_POSIX_MEMALIGN

#if !defined(_POSIX_C_SOURCE) && !defined(__APPLE__)
/* Get declarations of fseeko, ftello, posix_memalign. */
#define _POSIX_C_SOURCE 200112L
#endif

#if defined(__BIG_ENDIAN__) || (defined(__BYTE_ORDER__) && __BYTE_ORDER__ == __ORDER_BIG_ENDIAN__)
#define OPJ_BIG_ENDIAN
#endif
