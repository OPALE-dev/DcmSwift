// A C interface to the vendored OpenJPH HTJ2K encoder, for Swift.

#include "copenjph.h"

#include <cstdarg>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <stdexcept>
#include <string>

#include "ojph_arch.h"
#include "ojph_codestream.h"
#include "ojph_file.h"
#include "ojph_mem.h"
#include "ojph_message.h"
#include "ojph_params.h"

namespace {

// OpenJPH reports errors through a process-wide handler that must throw.
// This one keeps the formatted message in the exception instead of printing.
class throwing_error : public ojph::message_error {
public:
    void operator()(int error_code, const char *file_name, int line_num, const char *fmt, ...) override {
        char message[512];
        va_list args;
        va_start(args, fmt);
        vsnprintf(message, sizeof message, fmt, args);
        va_end(args);
        (void)file_name;
        (void)line_num;
        char full[600];
        snprintf(full, sizeof full, "OpenJPH error 0x%08X: %s", error_code, message);
        throw std::runtime_error(full);
    }
};

throwing_error error_handler;
std::once_flag configured;

void configure() {
    std::call_once(configured, [] {
        ojph::configure_error(&error_handler);
        ojph::set_info_stream(nullptr);
        ojph::set_warning_stream(nullptr);
    });
}

void report(char *error, size_t error_size, const char *message) {
    if (error != nullptr && error_size > 0) {
        snprintf(error, error_size, "%s", message);
    }
}

} // namespace

extern "C" int copenjph_encode(const int32_t *samples, const copenjph_parameters *p,
                               uint8_t **output, size_t *output_size, char *error, size_t error_size) {
    configure();
    *output = nullptr;
    *output_size = 0;
    if (samples == nullptr || p == nullptr || p->width == 0 || p->height == 0 || p->components == 0 ||
        p->bit_depth == 0 || p->bit_depth > 16) {
        report(error, error_size, "invalid HTJ2K encoding parameters");
        return -1;
    }
    try {
        ojph::codestream codestream;
        ojph::param_siz siz = codestream.access_siz();
        siz.set_image_extent(ojph::point(p->width, p->height));
        siz.set_num_components(p->components);
        for (uint32_t c = 0; c < p->components; ++c) {
            siz.set_component(c, ojph::point(1, 1), p->bit_depth, p->is_signed != 0);
        }
        siz.set_image_offset(ojph::point(0, 0));
        siz.set_tile_size(ojph::size(p->width, p->height));
        siz.set_tile_offset(ojph::point(0, 0));

        ojph::param_cod cod = codestream.access_cod();
        cod.set_num_decomposition(p->decompositions);
        cod.set_block_dims(64, 64);
        cod.set_progression_order(p->progression_order);
        cod.set_color_transform(p->components == 3 && p->color_transform != 0);
        cod.set_reversible(p->reversible != 0);
        if (p->reversible == 0) {
            codestream.access_qcd().set_irrev_quant(p->quantization_step);
        }
        if (p->tlm_markers != 0) {
            codestream.set_tilepart_divisions(true, false);
            codestream.request_tlm_marker(true);
        }
        codestream.set_planar(false);

        ojph::mem_outfile file;
        file.open();
        codestream.write_headers(&file);

        const size_t plane = static_cast<size_t>(p->width) * p->height;
        ojph::ui32 component = 0;
        ojph::line_buf *line = codestream.exchange(nullptr, component);
        for (uint32_t y = 0; y < p->height; ++y) {
            for (uint32_t c = 0; c < p->components; ++c) {
                const int32_t *source = samples + component * plane + static_cast<size_t>(y) * p->width;
                if (line->flags & ojph::line_buf::LFT_INTEGER) {
                    if (line->flags & ojph::line_buf::LFT_64BIT) {
                        for (uint32_t x = 0; x < p->width; ++x) line->i64[x] = source[x];
                    } else {
                        for (uint32_t x = 0; x < p->width; ++x) line->i32[x] = source[x];
                    }
                } else {
                    for (uint32_t x = 0; x < p->width; ++x) line->f32[x] = static_cast<float>(source[x]);
                }
                line = codestream.exchange(line, component);
            }
        }
        codestream.flush();

        const size_t size = static_cast<size_t>(file.tell());
        uint8_t *buffer = static_cast<uint8_t *>(malloc(size > 0 ? size : 1));
        if (buffer == nullptr) {
            codestream.close();
            report(error, error_size, "out of memory");
            return -1;
        }
        memcpy(buffer, file.get_data(), size);
        codestream.close();
        *output = buffer;
        *output_size = size;
        return 0;
    } catch (const std::exception &exception) {
        report(error, error_size, exception.what());
    } catch (...) {
        report(error, error_size, "OpenJPH failed");
    }
    return -1;
}

extern "C" void copenjph_free(uint8_t *buffer) {
    free(buffer);
}
