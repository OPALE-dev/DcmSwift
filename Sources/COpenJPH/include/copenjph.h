/* A C interface to the vendored OpenJPH HTJ2K encoder, for Swift. */
#ifndef COPENJPH_H
#define COPENJPH_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    uint32_t width;
    uint32_t height;
    uint32_t components;
    /** Bits per sample, 1 to 16 here. */
    uint32_t bit_depth;
    int is_signed;
    /** 1 for the reversible 5/3 path, 0 for the irreversible 9/7 path. */
    int reversible;
    /** Base quantization step of the irreversible path. */
    float quantization_step;
    /** 1 to apply the multiple-component transform to three components. */
    int color_transform;
    uint32_t decompositions;
    /** "LRCP", "RLCP", "RPCL", "PCRL", or "CPRL". */
    const char *progression_order;
    /** 1 to write TLM markers with tile-parts at resolutions. */
    int tlm_markers;
} copenjph_parameters;

/**
 * Encodes `samples`, one plane per component of `width * height` values,
 * as an HTJ2K codestream. On success returns 0 and a malloc'ed buffer in
 * `output` that the caller releases with `copenjph_free`; on failure returns
 * -1 and writes a message to `error`.
 */
int copenjph_encode(const int32_t *samples, const copenjph_parameters *parameters,
                    uint8_t **output, size_t *output_size, char *error, size_t error_size);

void copenjph_free(uint8_t *buffer);

#ifdef __cplusplus
}
#endif

#endif
