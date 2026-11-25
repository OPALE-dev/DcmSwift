/* Writes the seed codestreams of openjpeg_fuzz.sh: HTJ2K by the vendored
 * OpenJPH, JPEG 2000 Part 1 by the vendored OpenJPEG.
 *   openjpeg_fuzz_seeds OUTDIR
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "copenjph.h"
#include "openjpeg.h"

static int sample(unsigned x, unsigned y, unsigned c, unsigned bits)
{
    /* A textured image: gradients, a checker and noise, so every pass is used. */
    unsigned v = x * 37u + y * 11u + c * 101u + ((x / 3 + y / 5) & 1) * 900u + ((x * 2654435761u ^ y * 40503u) >> 7);
    return (int)(v & ((1u << bits) - 1));
}

static void write_file(const char *dir, const char *name, const unsigned char *b, size_t n)
{
    char path[1024];
    FILE *f;
    snprintf(path, sizeof path, "%s/%s", dir, name);
    f = fopen(path, "wb");
    fwrite(b, 1, n, f);
    fclose(f);
    printf("%s %zu bytes\n", name, n);
}

static void ht(const char *dir, const char *name, unsigned w, unsigned h, unsigned comps, unsigned bits,
               int reversible, int mct, unsigned levels)
{
    int32_t *s = malloc(sizeof(int32_t) * w * h * comps);
    copenjph_parameters p;
    uint8_t *out = NULL;
    size_t n = 0;
    char err[256];
    unsigned x, y, c;
    for (c = 0; c < comps; ++c)
        for (y = 0; y < h; ++y)
            for (x = 0; x < w; ++x) s[(c * h + y) * w + x] = sample(x, y, c, bits);
    memset(&p, 0, sizeof p);
    p.width = w; p.height = h; p.components = comps; p.bit_depth = bits; p.is_signed = 0;
    p.reversible = reversible; p.quantization_step = 0.01f; p.color_transform = mct;
    p.decompositions = levels; p.progression_order = "LRCP"; p.tlm_markers = 0;
    if (copenjph_encode(s, &p, &out, &n, err, sizeof err) != 0) { fprintf(stderr, "%s: %s\n", name, err); exit(1); }
    write_file(dir, name, out, n);
    copenjph_free(out);
    free(s);
}

static void part1(const char *dir, const char *name, unsigned w, unsigned h, unsigned comps, unsigned bits,
                  int irreversible, int mode, int cblk)
{
    char path[1024];
    opj_image_cmptparm_t cp[3];
    opj_cparameters_t p;
    opj_image_t *im;
    opj_codec_t *codec;
    opj_stream_t *st;
    unsigned x, y, c;
    memset(cp, 0, sizeof cp);
    for (c = 0; c < comps; ++c) { cp[c].dx = cp[c].dy = 1; cp[c].w = w; cp[c].h = h; cp[c].prec = bits; }
    im = opj_image_create(comps, cp, comps == 3 ? OPJ_CLRSPC_SRGB : OPJ_CLRSPC_GRAY);
    im->x1 = w; im->y1 = h;
    for (c = 0; c < comps; ++c)
        for (y = 0; y < h; ++y)
            for (x = 0; x < w; ++x) im->comps[c].data[y * w + x] = sample(x, y, c, bits);
    opj_set_default_encoder_parameters(&p);
    p.tcp_numlayers = 3; p.tcp_rates[0] = 20; p.tcp_rates[1] = 8; p.tcp_rates[2] = 0; p.cp_disto_alloc = 1;
    p.numresolution = 4; p.irreversible = irreversible; p.mode = mode;
    p.cblockw_init = cblk; p.cblockh_init = cblk; p.tcp_mct = comps == 3;
    snprintf(path, sizeof path, "%s/%s", dir, name);
    codec = opj_create_compress(OPJ_CODEC_J2K);
    st = opj_stream_create_default_file_stream(path, OPJ_FALSE);
    if (!opj_setup_encoder(codec, &p, im) || !opj_start_compress(codec, im, st) || !opj_encode(codec, st)
            || !opj_end_compress(codec, st)) { fprintf(stderr, "%s: cannot encode\n", name); exit(1); }
    opj_stream_destroy(st);
    opj_destroy_codec(codec);
    opj_image_destroy(im);
    printf("%s\n", name);
}

int main(int argc, char **argv)
{
    const char *d = argv[1];
    ht(d, "ht-rev-8.j2c", 64, 64, 1, 8, 1, 0, 3);
    ht(d, "ht-rev-16.j2c", 96, 80, 1, 16, 1, 0, 4);
    ht(d, "ht-irr-12.j2c", 64, 64, 1, 12, 0, 0, 3);
    ht(d, "ht-rgb-8.j2c", 48, 48, 3, 8, 1, 1, 2);
    /* One code-block, no decomposition: headers for forged packets. */
    ht(d, "one-8.j2c", 16, 16, 1, 8, 1, 0, 0);
    ht(d, "one-16.j2c", 13, 9, 1, 16, 1, 0, 0);
    ht(d, "one-8-h10.j2c", 16, 10, 1, 8, 1, 0, 0);
    ht(d, "one-12-h11.j2c", 7, 11, 1, 12, 1, 0, 0);
    /* mode: 1 BYPASS, 2 RESET, 4 RESTART, 8 VSC, 16 ERTERM, 32 SEGMARK */
    part1(d, "j2k-rev-8.j2c", 64, 64, 1, 8, 0, 0, 16);
    part1(d, "j2k-rev-16-modes.j2c", 80, 64, 1, 16, 0, 1 | 2 | 4 | 8 | 16 | 32, 16);
    part1(d, "j2k-irr-12.j2c", 64, 64, 1, 12, 1, 0, 32);
    part1(d, "j2k-rgb-bypass.j2c", 48, 48, 3, 8, 0, 1 | 4, 16);
    return 0;
}
