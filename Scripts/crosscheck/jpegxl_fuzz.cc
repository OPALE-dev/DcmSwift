// Deterministic byte mutations of JPEG XL codestreams, decoded by the vendored
// libjxl (see jpegxl_fuzz.sh).
//   jpegxl_fuzz seeds OUTDIR                   writes the seeds
//   jpegxl_fuzz SEEDFILE FIRST COUNT KEY WORKDIR
//       decodes cases FIRST..FIRST+COUNT-1; KEY 0 decodes the seed itself
//   jpegxl_fuzz SEEDFILE CASE 0 KEY WORKDIR    only writes case CASE to WORKDIR/current.j2c
// Prints "begin N" before and "end N decoded|refused" after each case, the
// protocol of openjpeg_fuzz.py. The first two bytes (the signature) are kept.

#include <jxl/decode.h>
#include <jxl/encode.h>
#include <unistd.h>

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>

static unsigned long long rng;
static unsigned long long next_random() {
  rng ^= rng << 13;
  rng ^= rng >> 7;
  rng ^= rng << 17;
  return rng;
}

static int sample(unsigned x, unsigned y, unsigned bits) {
  unsigned v = x * 37u + y * 11u + ((x / 3 + y / 5) & 1) * 900u + ((x * 2654435761u ^ y * 40503u) >> 7);
  return static_cast<int>(v & ((1u << bits) - 1));
}

static void write_seed(const char* dir, const char* name, unsigned w, unsigned h, unsigned bits, float distance,
                       int effort) {
  JxlEncoder* enc = JxlEncoderCreate(nullptr);
  JxlBasicInfo info;
  JxlEncoderInitBasicInfo(&info);
  info.xsize = w;
  info.ysize = h;
  info.bits_per_sample = bits;
  info.num_color_channels = 1;
  info.uses_original_profile = distance == 0 ? JXL_TRUE : JXL_FALSE;
  JxlEncoderSetBasicInfo(enc, &info);
  JxlColorEncoding color;
  JxlColorEncodingSetToSRGB(&color, JXL_TRUE);
  JxlEncoderSetColorEncoding(enc, &color);
  JxlEncoderFrameSettings* settings = JxlEncoderFrameSettingsCreate(enc, nullptr);
  JxlEncoderSetFrameDistance(settings, distance);
  if (distance == 0) JxlEncoderSetFrameLossless(settings, JXL_TRUE);
  JxlEncoderFrameSettingsSetOption(settings, JXL_ENC_FRAME_SETTING_EFFORT, effort);
  std::vector<uint16_t> pixels(w * h);
  for (unsigned y = 0; y < h; ++y)
    for (unsigned x = 0; x < w; ++x) pixels[y * w + x] = static_cast<uint16_t>(sample(x, y, bits));
  JxlPixelFormat format = {1, JXL_TYPE_UINT16, JXL_NATIVE_ENDIAN, 0};
  if (JxlEncoderAddImageFrame(settings, &format, pixels.data(), pixels.size() * 2) != JXL_ENC_SUCCESS) {
    fprintf(stderr, "%s: cannot encode\n", name);
    exit(1);
  }
  JxlEncoderCloseInput(enc);
  std::vector<uint8_t> out(1 << 16);
  uint8_t* next = out.data();
  size_t avail = out.size();
  while (JxlEncoderProcessOutput(enc, &next, &avail) == JXL_ENC_NEED_MORE_OUTPUT) {
    size_t used = next - out.data();
    out.resize(out.size() * 2);
    next = out.data() + used;
    avail = out.size() - used;
  }
  out.resize(next - out.data());
  JxlEncoderDestroy(enc);
  char path[1024];
  snprintf(path, sizeof path, "%s/%s", dir, name);
  FILE* f = fopen(path, "wb");
  fwrite(out.data(), 1, out.size(), f);
  fclose(f);
}

// Returns true when the whole image decoded. Images over 4 megapixels are
// refused before any pixel buffer is allocated.
static bool decode(const std::vector<uint8_t>& data) {
  JxlDecoder* dec = JxlDecoderCreate(nullptr);
  bool decoded = false;
  std::vector<uint8_t> pixels;
  JxlPixelFormat format = {1, JXL_TYPE_UINT16, JXL_NATIVE_ENDIAN, 0};
  JxlDecoderSubscribeEvents(dec, JXL_DEC_BASIC_INFO | JXL_DEC_FULL_IMAGE);
  JxlDecoderSetInput(dec, data.data(), data.size());
  JxlDecoderCloseInput(dec);
  for (;;) {
    JxlDecoderStatus status = JxlDecoderProcessInput(dec);
    if (status == JXL_DEC_BASIC_INFO) {
      JxlBasicInfo info;
      if (JxlDecoderGetBasicInfo(dec, &info) != JXL_DEC_SUCCESS) break;
      if (static_cast<uint64_t>(info.xsize) * info.ysize > (1u << 22)) break;
      format.num_channels = info.num_color_channels + (info.alpha_bits ? 1 : 0);
    } else if (status == JXL_DEC_NEED_IMAGE_OUT_BUFFER) {
      size_t size = 0;
      if (JxlDecoderImageOutBufferSize(dec, &format, &size) != JXL_DEC_SUCCESS || size > (64u << 20)) break;
      pixels.resize(size);
      if (JxlDecoderSetImageOutBuffer(dec, &format, pixels.data(), size) != JXL_DEC_SUCCESS) break;
    } else if (status == JXL_DEC_FULL_IMAGE) {
      decoded = true;
    } else if (status == JXL_DEC_SUCCESS) {
      break;
    } else {
      decoded = false;
      break;
    }
  }
  JxlDecoderDestroy(dec);
  return decoded;
}

static void mutate(std::vector<uint8_t>& b, unsigned long long key, unsigned long long c) {
  rng = (key * 0x9E3779B97F4A7C15ULL) ^ (c + 1) * 0xD1B54A32D192ED03ULL;
  if (!rng) rng = 1;
  next_random();
  next_random();
  int count = 1 + static_cast<int>(next_random() % 8 == 0 ? next_random() % 16 : next_random() % 4);
  size_t len = b.size() - 2;
  for (int m = 0; m < count; ++m) {
    size_t p = 2 + next_random() % len;
    switch (next_random() % 5) {
      case 0: b[p] = static_cast<uint8_t>(next_random()); break;
      case 1: b[p] ^= static_cast<uint8_t>(1u << (next_random() % 8)); break;
      case 2: b[p] = 0xFF; break;
      case 3: b[p] = 0x00; break;
      default: {
        size_t run = 1 + next_random() % 16, q = 2 + next_random() % len;
        for (size_t k = 0; k < run && p + k < b.size() && q + k < b.size(); ++k) b[p + k] = b[q + k];
      }
    }
  }
}

int main(int argc, char** argv) {
  if (argc == 3 && strcmp(argv[1], "seeds") == 0) {
    write_seed(argv[2], "jxl-lossless-8.jxl", 64, 48, 8, 0, 3);
    write_seed(argv[2], "jxl-lossless-16.jxl", 40, 36, 16, 0, 7);
    write_seed(argv[2], "jxl-lossy-8.jxl", 72, 64, 8, 1.0f, 7);
    write_seed(argv[2], "jxl-lossy-12.jxl", 48, 40, 12, 2.5f, 3);
    return 0;
  }
  if (argc < 6) return 2;
  FILE* f = fopen(argv[1], "rb");
  if (!f) return 2;
  std::vector<uint8_t> seed;
  int ch;
  while ((ch = fgetc(f)) != EOF) seed.push_back(static_cast<uint8_t>(ch));
  fclose(f);
  unsigned long first = strtoul(argv[2], nullptr, 10), count = strtoul(argv[3], nullptr, 10);
  unsigned long long key = strtoull(argv[4], nullptr, 10);
  char path[1024];
  snprintf(path, sizeof path, "%s/current.j2c", argv[5]);
  for (unsigned long c = first; c < first + (count ? count : 1); ++c) {
    std::vector<uint8_t> b = seed;
    if (key) mutate(b, key, c);
    f = fopen(path, "wb");
    fwrite(b.data(), 1, b.size(), f);
    fclose(f);
    if (!count) return 0;
    printf("begin %lu\n", c);
    fflush(stdout);
    alarm(20);
    bool ok = decode(b);
    printf("end %lu %s\n", c, ok ? "decoded" : "refused");
    fflush(stdout);
  }
  return 0;
}
