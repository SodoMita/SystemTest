/*
 * downscale_filter.c — Mitchell/Hermite downscale for sprite sheets.
 * Adapted from the Seirin project's upscale_filter.c (pure C, no deps).
 *
 * Order of operations (matches Seirin spec):
 *   1. Resample opaque source at full resolution (Mitchell or Hermite kernel).
 *   2. Unsharp mask on the downscaled result (sharpens the 16x16 output).
 *   3. Saturation lift.
 *   Alpha/background removal is a SEPARATE step (matte_floodfill) run on
 *   this program's output at final 16x16 resolution.
 *
 * Mitchell kernel: B=1/3, C=1/3 (recommended general-purpose).
 * Hermite kernel: B=0, C=0 (spline, sharper, less ringing).
 *
 * Usage:
 *   downscale_filter <in.png> <out.png> <target_w> <target_h> \
 *     [kernel=mitchell|hermite] [sharpen=0.6] [saturation=1.06]
 *
 * Build: gcc -O2 -o downscale_filter downscale_filter.c -lm
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#define STB_IMAGE_IMPLEMENTATION
#include "stb_image.h"
#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "stb_image_write.h"

typedef struct { float r, g, b, a; } Pixel;
static inline float clampf(float v, float lo, float hi) {
    return v < lo ? lo : (v > hi ? hi : v);
}

/* Mitchell-Netravali kernel: B=1/3, C=1/3 */
static float mitchell_kernel(float x) {
    x = fabsf(x);
    if (x < 1.0f) {
        return (16.0f + x*x * (21.0f * x - 36.0f)) / 18.0f;
    } else if (x < 2.0f) {
        return (32.0f + x * (-60.0f + x * (36.0f - 7.0f * x))) / 18.0f;
    }
    return 0.0f;
}

/* Hermite spline kernel: B=0, C=0 */
static float hermite_kernel(float x) {
    x = fabsf(x);
    if (x < 1.0f) {
        float x2 = x*x, x3 = x2*x;
        return 2.0f*x3 - 3.0f*x2 + 1.0f;
    }
    return 0.0f;
}

typedef float (*KernelFn)(float);

static inline Pixel fetch(const unsigned char *src, int w, int h, int x, int y) {
    if (x < 0) x = 0; if (x >= w) x = w - 1;
    if (y < 0) y = 0; if (y >= h) y = h - 1;
    const unsigned char *p = src + ((size_t)y * w + x) * 4;
    Pixel px = { p[0]/255.0f, p[1]/255.0f, p[2]/255.0f, p[3]/255.0f };
    return px;
}

static Pixel sample_resample(const unsigned char *src, int sw, int sh,
                             float u, float v, KernelFn kernel, int support) {
    float sx = u * sw;
    float sy = v * sh;
    int ix = (int)floorf(sx);
    int iy = (int)floorf(sy);
    float tx = sx - ix;
    float ty = sy - iy;

    Pixel result = {0, 0, 0, 0};
    float total_w = 0.0f;
    for (int j = -support + 1; j <= support; j++) {
        float wy = kernel(j - ty);
        for (int i = -support + 1; i <= support; i++) {
            float wx = kernel(i - tx);
            float w = wx * wy;
            Pixel s = fetch(src, sw, sh, ix + i, iy + j);
            result.r += s.r * w;
            result.g += s.g * w;
            result.b += s.b * w;
            result.a += s.a * w;
            total_w += w;
        }
    }
    if (total_w > 0.0001f) {
        result.r /= total_w;
        result.g /= total_w;
        result.b /= total_w;
        result.a /= total_w;
    }
    result.r = clampf(result.r, 0, 1);
    result.g = clampf(result.g, 0, 1);
    result.b = clampf(result.b, 0, 1);
    result.a = clampf(result.a, 0, 1);
    return result;
}

int main(int argc, char **argv) {
    if (argc < 5) {
        fprintf(stderr, "usage: %s <in.png> <out.png> <tw> <th> [kernel=mitchell|hermite] [sharpen=0.6] [saturation=1.06]\n", argv[0]);
        return 1;
    }
    const char *in_path = argv[1];
    const char *out_path = argv[2];
    int tw = atoi(argv[3]);
    int th = atoi(argv[4]);
    const char *kernel_name = (argc > 5) ? argv[5] : "mitchell";
    float sharpen = (argc > 6) ? (float)atof(argv[6]) : 0.6f;
    float saturation = (argc > 7) ? (float)atof(argv[7]) : 1.06f;

    KernelFn kernel;
    int support;
    if (strcmp(kernel_name, "hermite") == 0) {
        kernel = hermite_kernel;
        support = 2;
    } else {
        kernel = mitchell_kernel;
        support = 2;
    }

    int sw, sh, channels;
    unsigned char *src = stbi_load(in_path, &sw, &sh, &channels, 4);
    if (!src) { fprintf(stderr, "failed to load %s\n", in_path); return 1; }

    unsigned char *dst = malloc((size_t)tw * th * 4);
    if (!dst) { fprintf(stderr, "oom\n"); return 1; }

    /* Pass 1: resample */
    for (int y = 0; y < th; y++) {
        float v = (y + 0.5f) / th;
        for (int x = 0; x < tw; x++) {
            float u = (x + 0.5f) / tw;
            Pixel p = sample_resample(src, sw, sh, u, v, kernel, support);
            unsigned char *o = dst + ((size_t)y * tw + x) * 4;
            o[0] = (unsigned char)(p.r * 255.0f + 0.5f);
            o[1] = (unsigned char)(p.g * 255.0f + 0.5f);
            o[2] = (unsigned char)(p.b * 255.0f + 0.5f);
            o[3] = (unsigned char)(p.a * 255.0f + 0.5f);
        }
    }
    stbi_image_free(src);

    /* Pass 2: unsharp mask (3x3 box blur, subtract, scale, add back). RGB only. */
    if (sharpen > 0.0001f) {
        unsigned char *sharpened = malloc((size_t)tw * th * 4);
        for (int y = 0; y < th; y++) {
            for (int x = 0; x < tw; x++) {
                float sum[3] = {0,0,0};
                int n = 0;
                for (int dy = -1; dy <= 1; dy++) {
                    int yy = y + dy; if (yy < 0) yy = 0; if (yy >= th) yy = th - 1;
                    for (int dx = -1; dx <= 1; dx++) {
                        int xx = x + dx; if (xx < 0) xx = 0; if (xx >= tw) xx = tw - 1;
                        unsigned char *p = dst + ((size_t)yy * tw + xx) * 4;
                        sum[0] += p[0]; sum[1] += p[1]; sum[2] += p[2];
                        n++;
                    }
                }
                unsigned char *center = dst + ((size_t)y * tw + x) * 4;
                unsigned char *out = sharpened + ((size_t)y * tw + x) * 4;
                for (int c = 0; c < 3; c++) {
                    float blur = sum[c] / n;
                    float cv = center[c];
                    float v = cv + (cv - blur) * sharpen;
                    out[c] = (unsigned char)clampf(v, 0, 255);
                }
                out[3] = center[3];
            }
        }
        free(dst);
        dst = sharpened;
    }

    /* Pass 3: luma-preserving saturation lift */
    if (fabsf(saturation - 1.0f) > 0.0001f) {
        for (size_t i = 0; i < (size_t)tw * th; i++) {
            unsigned char *p = dst + i * 4;
            float r = p[0], g = p[1], b = p[2];
            float luma = 0.299f*r + 0.587f*g + 0.114f*b;
            p[0] = (unsigned char)clampf(luma + (r - luma) * saturation, 0, 255);
            p[1] = (unsigned char)clampf(luma + (g - luma) * saturation, 0, 255);
            p[2] = (unsigned char)clampf(luma + (b - luma) * saturation, 0, 255);
        }
    }

    stbi_write_png(out_path, tw, th, 4, dst, tw * 4);
    fprintf(stderr, "downscale_filter: %dx%d -> %dx%d (kernel=%s sharpen=%.2f sat=%.2f) -> %s\n",
            sw, sh, tw, th, kernel_name, sharpen, saturation, out_path);
    free(dst);
    return 0;
}
