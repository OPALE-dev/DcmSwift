/*
 * Runs the vendored OpenJPEG on the geometries and forged codestreams of
 * DcmSwiftVendoredCodecTests, for AddressSanitizer: see openjpeg_asan.sh.
 *
 *   openjpeg_asan CASE WORKDIR
 *
 * CASE is one of the names printed by `openjpeg_asan list`. Each case runs in
 * its own process, so that a memory error in one does not hide the others.
 * Exit status 0 means the case ran to its end, whatever OpenJPEG decided.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "openjpeg.h"

static void quiet(const char *message, void *data)
{
    (void)message;
    (void)data;
}

static void silence(opj_codec_t *codec)
{
    opj_set_info_handler(codec, quiet, NULL);
    opj_set_warning_handler(codec, quiet, NULL);
    opj_set_error_handler(codec, quiet, NULL);
}

/* Decodes a file; returns 1 when OpenJPEG decoded it, 0 when it refused it. */
static int decode_file(const char *path)
{
    opj_dparameters_t parameters;
    opj_image_t *image = NULL;
    opj_stream_t *stream = opj_stream_create_default_file_stream(path, OPJ_TRUE);
    opj_codec_t *codec = opj_create_decompress(OPJ_CODEC_J2K);
    int decoded = 0;
    if (!stream || !codec) {
        fprintf(stderr, "cannot create the decoder\n");
        exit(2);
    }
    silence(codec);
    opj_set_default_decoder_parameters(&parameters);
    if (opj_setup_decoder(codec, &parameters) && opj_read_header(stream, codec, &image)
            && opj_decode(codec, stream, image) && opj_end_decompress(codec, stream)) {
        decoded = 1;
    }
    if (image) {
        opj_image_destroy(image);
    }
    opj_destroy_codec(codec);
    opj_stream_destroy(stream);
    return decoded;
}

/* --- Reversible encoding of tiled images (opj_dwt_encode_and_deinterleave_v) */

static int sample(OPJ_UINT32 x, OPJ_UINT32 y)
{
    return (int)((x * 7 + y * 13) & 0xFF);
}

static int encode_tiled(const char *workdir, OPJ_UINT32 w, OPJ_UINT32 h, int tdx, int tdy, int resolutions)
{
    char path[1024];
    opj_cparameters_t parameters;
    opj_image_cmptparm_t component;
    opj_image_t *image;
    opj_codec_t *codec;
    opj_stream_t *stream;
    opj_image_t *decoded = NULL;
    opj_dparameters_t dparameters;
    OPJ_UINT32 x, y, wrong = 0;

    snprintf(path, sizeof path, "%s/tiled-%ux%u.j2k", workdir, w, h);
    memset(&component, 0, sizeof component);
    component.dx = component.dy = 1;
    component.w = w;
    component.h = h;
    component.prec = 8;
    image = opj_image_create(1, &component, OPJ_CLRSPC_GRAY);
    image->x1 = w;
    image->y1 = h;
    for (y = 0; y < h; ++y) {
        for (x = 0; x < w; ++x) {
            image->comps[0].data[y * w + x] = sample(x, y);
        }
    }
    opj_set_default_encoder_parameters(&parameters);
    parameters.tcp_numlayers = 1;
    parameters.cp_disto_alloc = 1;
    parameters.numresolution = resolutions;
    parameters.tile_size_on = OPJ_TRUE;
    parameters.cp_tdx = tdx;
    parameters.cp_tdy = tdy;
    parameters.irreversible = 0;
    codec = opj_create_compress(OPJ_CODEC_J2K);
    silence(codec);
    stream = opj_stream_create_default_file_stream(path, OPJ_FALSE);
    if (!opj_setup_encoder(codec, &parameters, image) || !opj_start_compress(codec, image, stream)
            || !opj_encode(codec, stream) || !opj_end_compress(codec, stream)) {
        fprintf(stderr, "%ux%u: cannot encode\n", w, h);
        return 1;
    }
    opj_stream_destroy(stream);
    opj_destroy_codec(codec);
    opj_image_destroy(image);

    stream = opj_stream_create_default_file_stream(path, OPJ_TRUE);
    codec = opj_create_decompress(OPJ_CODEC_J2K);
    silence(codec);
    opj_set_default_decoder_parameters(&dparameters);
    if (!opj_setup_decoder(codec, &dparameters) || !opj_read_header(stream, codec, &decoded)
            || !opj_decode(codec, stream, decoded) || !opj_end_decompress(codec, stream)) {
        fprintf(stderr, "%ux%u: cannot decode\n", w, h);
        return 1;
    }
    for (y = 0; y < h; ++y) {
        for (x = 0; x < w; ++x) {
            wrong += decoded->comps[0].data[y * w + x] != sample(x, y);
        }
    }
    opj_image_destroy(decoded);
    opj_destroy_codec(codec);
    opj_stream_destroy(stream);
    remove(path);
    if (wrong) {
        fprintf(stderr, "%ux%u: %u samples differ\n", w, h, wrong);
        return 1;
    }
    return 0;
}

/* --- Forged tile-parts (opj_j2k_read_sot, opj_j2k_read_sod) */

typedef struct {
    unsigned char index;
    unsigned char count;
    long length; /* Psot, or -1 for the actual length */
    int data;    /* bytes of packet data, all zero */
} tile_part_t;

static size_t put16(unsigned char *p, unsigned v)
{
    p[0] = (unsigned char)(v >> 8);
    p[1] = (unsigned char)v;
    return 2;
}

static size_t put32(unsigned char *p, unsigned long v)
{
    put16(p, (unsigned)(v >> 16) & 0xFFFF);
    put16(p + 2, (unsigned)v & 0xFFFF);
    return 4;
}

/* The codestream of DcmSwiftVendoredCodecTests.codestream(_:tlm:keeping:). */
static size_t forge(unsigned char *b, const tile_part_t *parts, int count, const long *tlm, int tlm_count,
                    long keeping)
{
    size_t n = 0;
    int i;
    const unsigned long siz[8] = {4, 4, 0, 0, 4, 4, 0, 0};
    b[n++] = 0xFF; b[n++] = 0x4F; b[n++] = 0xFF; b[n++] = 0x51;
    n += put16(b + n, 41);
    n += put16(b + n, 0);
    for (i = 0; i < 8; ++i) {
        n += put32(b + n, siz[i]);
    }
    n += put16(b + n, 1);
    b[n++] = 7; b[n++] = 1; b[n++] = 1;
    b[n++] = 0xFF; b[n++] = 0x52;
    n += put16(b + n, 12);
    { const unsigned char cod[] = {0, 0, 0, 1, 0, 0, 4, 4, 0, 1}; memcpy(b + n, cod, sizeof cod); n += sizeof cod; }
    b[n++] = 0xFF; b[n++] = 0x5C;
    n += put16(b + n, 4);
    b[n++] = 0x20; b[n++] = 0x40;
    if (tlm) {
        b[n++] = 0xFF; b[n++] = 0x55;
        n += put16(b + n, (unsigned)(4 + 5 * tlm_count));
        b[n++] = 0; b[n++] = 0x50;
        for (i = 0; i < tlm_count; ++i) {
            b[n++] = 0;
            n += put32(b + n, (unsigned long)tlm[i]);
        }
    }
    for (i = 0; i < count; ++i) {
        b[n++] = 0xFF; b[n++] = 0x90;
        n += put16(b + n, 10);
        n += put16(b + n, 0);
        n += put32(b + n, (unsigned long)(parts[i].length < 0 ? 14 + parts[i].data : parts[i].length));
        b[n++] = parts[i].index; b[n++] = parts[i].count; b[n++] = 0xFF; b[n++] = 0x93;
        memset(b + n, 0, (size_t)parts[i].data);
        n += (size_t)parts[i].data;
    }
    b[n++] = 0xFF; b[n++] = 0xD9;
    return keeping >= 0 && (size_t)keeping < n ? (size_t)keeping : n;
}

static int decode_forged(const char *workdir, const char *name, const tile_part_t *parts, int count,
                         const long *tlm, int tlm_count, long keeping)
{
    unsigned char bytes[1024];
    char path[1024];
    size_t length = forge(bytes, parts, count, tlm, tlm_count, keeping);
    FILE *file;
    snprintf(path, sizeof path, "%s/forged-%s.j2k", workdir, name);
    file = fopen(path, "wb");
    fwrite(bytes, 1, length, file);
    fclose(file);
    printf("%s: %s\n", name, decode_file(path) ? "decoded" : "refused");
    remove(path);
    return 0;
}

#define TP(i, c, l, d) { (unsigned char)(i), (unsigned char)(c), (l), (d) }

int main(int argc, char **argv)
{
    const char *which = argc > 1 ? argv[1] : "list";
    const char *workdir = argc > 2 ? argv[2] : ".";
    static const char *names[] = {
        "encode-empty-resolution", "encode-controls", "control", "control-tlm", "tlm-overrun",
        "tlm-overrun-four", "psot-beyond-end", "psot-beyond-end-last", "psot-below-14", "psot-12",
        "psot-0", "psot-0-before-another", "psot-shorter", "truncated-sot", "truncated-after-sod",
        "truncated-psot-0", "repeated", "out-of-order", "tpsot-at-tnsot", "more-than-tlm",
        "tlm-beyond-end", "tlm-zero", NULL
    };
    int i;
    if (strcmp(which, "list") == 0) {
        for (i = 0; names[i]; ++i) {
            puts(names[i]);
        }
        return 0;
    }
    if (strcmp(which, "encode-empty-resolution") == 0) {
        return encode_tiled(workdir, 1, 6, 4, 5, 3) | encode_tiled(workdir, 33, 37, 32, 36, 5);
    }
    if (strcmp(which, "encode-controls") == 0) {
        return encode_tiled(workdir, 8, 8, 4, 4, 3) | encode_tiled(workdir, 17, 16, 16, 16, 5);
    }
    {
        const tile_part_t one[] = {TP(0, 1, -1, 1)};
        const tile_part_t unknown2[] = {TP(0, 0, -1, 1), TP(1, 0, -1, 1)};
        const tile_part_t unknown4[] = {TP(0, 0, -1, 1), TP(1, 0, -1, 1), TP(2, 0, -1, 1), TP(3, 0, -1, 1)};
        const long tlm1[] = {15}, tlm2[] = {15, 15}, tlm_big[] = {0x7FFF0000L}, tlm0[] = {0, 0};
        if (strcmp(which, "control") == 0) return decode_forged(workdir, which, one, 1, NULL, 0, -1);
        if (strcmp(which, "control-tlm") == 0) return decode_forged(workdir, which, one, 1, tlm1, 1, -1);
        if (strcmp(which, "tlm-overrun") == 0) return decode_forged(workdir, which, unknown2, 2, tlm1, 1, -1);
        if (strcmp(which, "tlm-overrun-four") == 0) return decode_forged(workdir, which, unknown4, 4, tlm2, 2, -1);
        if (strcmp(which, "psot-beyond-end") == 0) {
            const tile_part_t p[] = {TP(0, 1, 4000, 1)};
            return decode_forged(workdir, which, p, 1, NULL, 0, -1);
        }
        if (strcmp(which, "psot-beyond-end-last") == 0) {
            const tile_part_t p[] = {TP(0, 1, 0x7FFFFFF0L, 1)};
            return decode_forged(workdir, which, p, 1, NULL, 0, -1);
        }
        if (strcmp(which, "psot-below-14") == 0) {
            const tile_part_t p[] = {TP(0, 1, 13, 1)};
            return decode_forged(workdir, which, p, 1, NULL, 0, -1);
        }
        if (strcmp(which, "psot-12") == 0) {
            const tile_part_t p[] = {TP(0, 1, 12, 1)};
            return decode_forged(workdir, which, p, 1, NULL, 0, -1);
        }
        if (strcmp(which, "psot-0") == 0) {
            const tile_part_t p[] = {TP(0, 1, 0, 1)};
            return decode_forged(workdir, which, p, 1, NULL, 0, -1);
        }
        if (strcmp(which, "psot-0-before-another") == 0) {
            const tile_part_t p[] = {TP(0, 2, 0, 1), TP(1, 2, -1, 1)};
            return decode_forged(workdir, which, p, 2, NULL, 0, -1);
        }
        if (strcmp(which, "psot-shorter") == 0) {
            const tile_part_t p[] = {TP(0, 1, 14, 4)};
            return decode_forged(workdir, which, p, 1, NULL, 0, -1);
        }
        if (strcmp(which, "truncated-sot") == 0) return decode_forged(workdir, which, one, 1, NULL, 0, 64);
        if (strcmp(which, "truncated-after-sod") == 0) {
            const tile_part_t p[] = {TP(0, 1, -1, 4)};
            return decode_forged(workdir, which, p, 1, NULL, 0, 76);
        }
        if (strcmp(which, "truncated-psot-0") == 0) {
            const tile_part_t p[] = {TP(0, 1, 0, 3)};
            return decode_forged(workdir, which, p, 1, NULL, 0, 75);
        }
        if (strcmp(which, "repeated") == 0) {
            const tile_part_t p[] = {TP(0, 2, -1, 1), TP(0, 2, -1, 1)};
            return decode_forged(workdir, which, p, 2, NULL, 0, -1);
        }
        if (strcmp(which, "out-of-order") == 0) {
            const tile_part_t p[] = {TP(1, 2, -1, 1), TP(0, 2, -1, 1)};
            return decode_forged(workdir, which, p, 2, NULL, 0, -1);
        }
        if (strcmp(which, "tpsot-at-tnsot") == 0) {
            const tile_part_t p[] = {TP(0, 1, -1, 1), TP(1, 1, -1, 1)};
            return decode_forged(workdir, which, p, 2, NULL, 0, -1);
        }
        if (strcmp(which, "more-than-tlm") == 0) {
            const tile_part_t p[] = {TP(0, 2, -1, 1), TP(1, 2, -1, 1)};
            return decode_forged(workdir, which, p, 2, tlm1, 1, -1);
        }
        if (strcmp(which, "tlm-beyond-end") == 0) return decode_forged(workdir, which, one, 1, tlm_big, 1, -1);
        if (strcmp(which, "tlm-zero") == 0) return decode_forged(workdir, which, unknown2, 2, tlm0, 2, -1);
    }
    fprintf(stderr, "unknown case %s\n", which);
    return 2;
}
