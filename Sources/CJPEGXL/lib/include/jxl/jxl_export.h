/* Static-library export definitions for DcmSwift's vendored libjxl. */
#ifndef JXL_EXPORT_H
#define JXL_EXPORT_H

#define JXL_EXPORT
#define JXL_NO_EXPORT
#define JXL_DEPRECATED __attribute__((deprecated))
#define JXL_DEPRECATED_EXPORT JXL_EXPORT JXL_DEPRECATED
#define JXL_DEPRECATED_NO_EXPORT JXL_NO_EXPORT JXL_DEPRECATED

#endif
