/* Deterministic mutation of the packet data of a codestream, decoded by the
 * vendored OpenJPEG (see openjpeg_fuzz.sh).
 *   openjpeg_fuzz SEEDFILE FIRST COUNT KEY WORKDIR [forge]
 *       runs cases FIRST..FIRST+COUNT-1
 *   openjpeg_fuzz SEEDFILE CASE 0 KEY WORKDIR [forge]
 *       only writes case CASE to WORKDIR/current.j2c
 * Without "forge", main and tile-part headers are kept and only bytes between
 * SOD and the end of each tile-part change; KEY 0 decodes the seed itself.
 * With "forge", SEEDFILE is a one-code-block HTJ2K codestream whose headers
 * are kept, and each case writes a new packet: random zero bit-planes, 1 to 6
 * coding passes, random cleanup and refinement segments with a valid Scup.
 * Prints "begin N" before and "end N decoded|refused" after each case.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include "openjpeg.h"

typedef struct { size_t start, end; } range_t;

static unsigned long long rng;
static unsigned long long next(void)
{
    rng ^= rng << 13; rng ^= rng >> 7; rng ^= rng << 17;
    return rng;
}

static void quiet(const char *m, void *d) { (void)m; (void)d; }

static int find_ranges(const unsigned char *b, size_t n, range_t *r, int max)
{
    size_t i = 2;
    int k = 0;
    /* Skip main-header segments up to the first SOT. */
    while (i + 4 <= n && !(b[i] == 0xFF && b[i + 1] == 0x90)) {
        i += 2 + ((size_t)b[i + 2] << 8 | b[i + 3]);
    }
    while (i + 12 <= n && b[i] == 0xFF && b[i + 1] == 0x90 && k < max) {
        size_t psot = (size_t)b[i + 6] << 24 | (size_t)b[i + 7] << 16 | (size_t)b[i + 8] << 8 | b[i + 9];
        size_t end = psot ? i + psot : n - 2;
        size_t j = i + 12;
        while (j + 4 <= end && !(b[j] == 0xFF && b[j + 1] == 0x93)) {
            j += 2 + ((size_t)b[j + 2] << 8 | b[j + 3]);
        }
        if (j + 2 < end) {
            r[k].start = j + 2;
            r[k].end = end;
            ++k;
        }
        i = end;
    }
    return k;
}

static void mutate(unsigned char *b, const range_t *r, int nr, unsigned long long key, unsigned long long c)
{
    int m, count;
    rng = (key * 0x9E3779B97F4A7C15ULL) ^ (c + 1) * 0xD1B54A32D192ED03ULL;
    if (!rng) rng = 1;
    next(); next();
    count = 1 + (int)(next() % 8 == 0 ? next() % 16 : next() % 4);
    for (m = 0; m < count; ++m) {
        const range_t *g = &r[next() % (unsigned)nr];
        size_t len = g->end - g->start;
        size_t p = g->start + next() % len;
        switch (next() % 6) {
        case 0: b[p] = (unsigned char)next(); break;
        case 1: b[p] ^= (unsigned char)(1u << (next() % 8)); break;
        case 2: b[p] = 0xFF; break;
        case 3: b[p] = 0x00; break;
        case 4: { /* overwrite a short run */
            size_t k, run = 1 + next() % 8;
            unsigned char v = (unsigned char)next();
            for (k = 0; k < run && p + k < g->end; ++k) b[p + k] = v;
            break;
        }
        default: { /* copy a run from elsewhere in the same tile-part */
            size_t k, run = 1 + next() % 32, q = g->start + next() % len;
            for (k = 0; k < run && p + k < g->end && q + k < g->end; ++k) b[p + k] = b[q + k];
            break;
        }
        }
    }
}


/* --- Forged HT packets: one code-block, 1 to 6 passes, random segments. */
typedef struct { unsigned char *b; size_t n; int bit; unsigned char cur; } bits_t;
static void putbit(bits_t *w, int v)
{
    int width = (w->n > 0 && w->b[w->n - 1] == 0xFF) ? 7 : 8;
    w->cur = (unsigned char)(w->cur << 1 | (v & 1));
    if (++w->bit == width) { w->b[w->n++] = w->cur; w->cur = 0; w->bit = 0; }
}
static void putbits(bits_t *w, unsigned v, int n) { while (n--) putbit(w, (int)(v >> n) & 1); }
static void flushbits(bits_t *w)
{
    int width = (w->n > 0 && w->b[w->n - 1] == 0xFF) ? 7 : 8;
    if (w->bit) { w->cur = (unsigned char)(w->cur << (width - w->bit)); w->b[w->n++] = w->cur; w->cur = 0; w->bit = 0; }
    if (w->n > 0 && w->b[w->n - 1] == 0xFF) w->b[w->n++] = 0;
}
static int floorlog2(unsigned v) { int l = 0; while (v >>= 1) ++l; return l; }

/* Returns the length of the forged codestream written to out. */
static size_t forge(const unsigned char *seed, size_t n, unsigned char *out, unsigned long long key,
                    unsigned long long c)
{
    size_t sot = 0, sod = 0, k, m;
    unsigned numbps, zero, passes, lcup, lref, lblock = 3, inc = 0;
    unsigned char pkt[64];
    bits_t w = {pkt, 0, 0, 0};
    for (k = 2; k + 1 < n; ++k) {
        if (!sot && seed[k] == 0xFF && seed[k + 1] == 0x90) sot = k;
        if (sot && seed[k] == 0xFF && seed[k + 1] == 0x93) { sod = k + 2; break; }
    }
    /* QCD SPqcd: exponent in the top five bits; one guard bit here. */
    for (k = 2; k + 5 < sot; ++k) if (seed[k] == 0xFF && seed[k + 1] == 0x5C) break;
    numbps = (unsigned)(seed[k + 5] >> 3) + (unsigned)(seed[k + 4] >> 5) - 1;
    rng = (key * 0x9E3779B97F4A7C15ULL) ^ (c + 1) * 0xD1B54A32D192ED03ULL;
    if (!rng) rng = 1;
    next(); next();
    zero = (unsigned)(next() % (numbps + 1));
    m = next() % 16;
    passes = m < 2 ? 1 : m < 6 ? 2 : m < 14 ? 3 : 4 + (unsigned)(next() % 3);
    lcup = 2 + (unsigned)(next() % 80);
    lref = passes > 1 ? (unsigned)(next() % 48) : 0;
    while (lcup >> (lblock + inc) || (passes > 1 && lref >> (lblock + inc + floorlog2(passes - 1)))) ++inc;
    putbit(&w, 1);                                   /* packet present */
    putbit(&w, 1);                                   /* code-block included */
    for (k = 0; k < zero; ++k) putbit(&w, 0);        /* zero bit-planes */
    putbit(&w, 1);
    if (passes == 1) putbits(&w, 0, 1);              /* number of passes */
    else if (passes == 2) putbits(&w, 2, 2);
    else putbits(&w, 0xC | (passes - 3), 4);
    for (k = 0; k < inc; ++k) putbit(&w, 1);         /* Lblock increment */
    putbit(&w, 0);
    putbits(&w, lcup, (int)(lblock + inc));
    if (passes > 1) putbits(&w, lref, (int)(lblock + inc) + floorlog2(passes - 1));
    flushbits(&w);
    memcpy(out, seed, sod);
    m = sod;
    memcpy(out + m, pkt, w.n); m += w.n;
    for (k = 0; k < lcup + lref; ++k) out[m + k] = (unsigned char)next();
    {   /* Scup, the MEL and VLC length, in the last two bytes of the cleanup segment. */
        unsigned scup = 2 + (unsigned)(next() % (lcup - 1));
        if (scup > 4079) scup = 4079;
        out[m + lcup - 1] = (unsigned char)(scup >> 4);
        out[m + lcup - 2] = (unsigned char)((out[m + lcup - 2] & 0xF0) | (scup & 0xF));
    }
    m += lcup + lref;
    k = m - sot;                                     /* Psot */
    out[sot + 6] = (unsigned char)(k >> 24); out[sot + 7] = (unsigned char)(k >> 16);
    out[sot + 8] = (unsigned char)(k >> 8); out[sot + 9] = (unsigned char)k;
    out[m++] = 0xFF; out[m++] = 0xD9;
    return m;
}

static int decode(const char *path)
{
    opj_dparameters_t dp;
    opj_image_t *im = NULL;
    opj_stream_t *st = opj_stream_create_default_file_stream(path, OPJ_TRUE);
    opj_codec_t *codec = opj_create_decompress(OPJ_CODEC_J2K);
    int ok = 0;
    opj_set_info_handler(codec, quiet, NULL);
    opj_set_warning_handler(codec, quiet, NULL);
    opj_set_error_handler(codec, quiet, NULL);
    opj_set_default_decoder_parameters(&dp);
    if (opj_setup_decoder(codec, &dp) && opj_read_header(st, codec, &im) && opj_decode(codec, st, im)
            && opj_end_decompress(codec, st)) ok = 1;
    if (im) opj_image_destroy(im);
    opj_destroy_codec(codec);
    opj_stream_destroy(st);
    return ok;
}

int main(int argc, char **argv)
{
    FILE *f = fopen(argv[1], "rb");
    unsigned long first = strtoul(argv[2], NULL, 10), count = strtoul(argv[3], NULL, 10), c;
    unsigned long long key = strtoull(argv[4], NULL, 10);
    char path[1024];
    unsigned char *seed, *b;
    size_t n;
    range_t r[64];
    int nr;
    fseek(f, 0, SEEK_END); n = (size_t)ftell(f); fseek(f, 0, SEEK_SET);
    seed = malloc(n); b = malloc(n + 4096);
    if (fread(seed, 1, n, f) != n) return 2;
    fclose(f);
    nr = find_ranges(seed, n, r, 64);
    if (nr == 0) { fprintf(stderr, "no packet data found\n"); return 2; }
    snprintf(path, sizeof path, "%s/current.j2c", argv[5]);
    for (c = first; c < first + (count ? count : 1); ++c) {
        size_t len = n;
        if (argc > 6) {
            len = forge(seed, n, b, key, c);
        } else {
            memcpy(b, seed, n);
            if (key) mutate(b, r, nr, key, c); /* key 0: the seed itself */
        }
        f = fopen(path, "wb"); fwrite(b, 1, len, f); fclose(f);
        if (!count) return 0;
        printf("begin %lu\n", c); fflush(stdout);
        alarm(20);
        printf("end %lu %s\n", c, decode(path) ? "decoded" : "refused"); fflush(stdout);
    }
    return 0;
}
