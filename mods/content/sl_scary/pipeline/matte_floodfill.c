/*
 * matte_floodfill.c — plain-C background removal for flat-cel-shaded
 * sprites generated on a solid #FFFFFF canvas.
 *
 * This is a real flood fill from every border pixel (not a 4-corner seed
 * approximation like the old `convert -draw "matte 0,0 floodfill" ...`
 * bash pipeline), so it does not depend on the background being simply
 * connected to exactly the four corners. It also does not touch the RGB
 * channels or blend fractional alpha into the image's own colours the way
 * a resize-after-matte pipeline can: run this AFTER upscale_filter, at
 * final resolution, never before (see upscale_filter.c's header comment
 * and ai_agent_docs/skills/seirin-character-art/references/sprite-spec.md).
 *
 * "Halftone" alpha bug this replaces: the previous ImageMagick pipeline
 * produced visible dither/noise patterns in what should have been either
 * fully-opaque or fully-transparent regions, most likely from (a) lossy
 * WebP alpha compression re-quantizing a channel that should have been
 * flat 0/255 blocks, and (b) `-fuzz` floodfill leaving a fuzzy band of
 * partial-alpha pixels along every line-art edge instead of a clean binary
 * cut with a 1-pixel antialiased rim. This tool:
 *   1. Flood-fills strictly BACKGROUND pixels (near-white, connected to the
 *      canvas border) to alpha=0. Uses 6-connectivity in RGB distance, not
 *      a percentage "fuzz" blend, so the result is a clean binary mask.
 *   2. Leaves every non-background pixel at alpha=255 — flat cel art has
 *      no interior soft edges to preserve (unlike Splash's translucent
 *      body, which must go through the white/black triangulation route
 *      instead of this tool).
 *   3. Applies a single 1-pixel antialiasing feather only exactly on the
 *      boundary between the two regions, so cut edges are not jagged, but
 *      nothing deep inside either region is touched — no dithering, no
 *      halftone pattern possible because the interior is never touched.
 *
 * Usage:
 *   matte_floodfill <in.png> <out.png> [white_threshold=14] [feather=1]
 *     white_threshold: max per-channel distance from #FFFFFF to still
 *       count as "background" (0-255). Anti-aliased edge pixels from the
 *       generator are within this band; solid character colours never are
 *       for flat cel art with saturated palettes.
 *     feather: 0 or 1. 1 adds a single soft antialiased ring on the cut
 *       edge (recommended); 0 produces a hard binary matte.
 *
 * Build: gcc -O2 -o matte_floodfill matte_floodfill.c -lm
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

#define STB_IMAGE_IMPLEMENTATION
#include "stb_image.h"
#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "stb_image_write.h"

static inline int is_near_white(const unsigned char *p, int threshold) {
    int dr = 255 - p[0];
    int dg = 255 - p[1];
    int db = 255 - p[2];
    return dr <= threshold && dg <= threshold && db <= threshold;
}

int main(int argc, char **argv) {
    if (argc < 3) {
        fprintf(stderr, "usage: %s <in.png> <out.png> [white_threshold=14] [feather=1]\n", argv[0]);
        return 1;
    }
    const char *in_path = argv[1];
    const char *out_path = argv[2];
    int threshold = argc > 3 ? atoi(argv[3]) : 14;
    int feather = argc > 4 ? atoi(argv[4]) : 1;

    int w, h, channels;
    unsigned char *img = stbi_load(in_path, &w, &h, &channels, 4);
    if (!img) {
        fprintf(stderr, "failed to load %s\n", in_path);
        return 1;
    }

    /* candidate: 1 = near-white pixel (potential background) */
    unsigned char *candidate = malloc((size_t)w * h);
    unsigned char *is_bg = calloc((size_t)w * h, 1);
    for (size_t i = 0; i < (size_t)w * h; i++) {
        candidate[i] = is_near_white(img + i * 4, threshold) ? 1 : 0;
    }

    /* BFS flood fill from every border pixel that is a near-white
     * candidate, over 4-connectivity, marking reached pixels as background. */
    int *stack = malloc(sizeof(int) * (size_t)w * h);
    long sp = 0;

    for (int x = 0; x < w; x++) {
        for (int y = 0; y < h; y += (h > 1 ? h - 1 : 1)) {
            size_t idx = (size_t)y * w + x;
            if (candidate[idx] && !is_bg[idx]) {
                is_bg[idx] = 1;
                stack[sp++] = (int)idx;
            }
            if (h == 1) break;
        }
    }
    for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x += (w > 1 ? w - 1 : 1)) {
            size_t idx = (size_t)y * w + x;
            if (candidate[idx] && !is_bg[idx]) {
                is_bg[idx] = 1;
                stack[sp++] = (int)idx;
            }
            if (w == 1) break;
        }
    }

    while (sp > 0) {
        int idx = stack[--sp];
        int x = idx % w;
        int y = idx / w;
        int nbrs[4][2] = { {x-1,y}, {x+1,y}, {x,y-1}, {x,y+1} };
        for (int k = 0; k < 4; k++) {
            int nx = nbrs[k][0], ny = nbrs[k][1];
            if (nx < 0 || nx >= w || ny < 0 || ny >= h) continue;
            size_t nidx = (size_t)ny * w + nx;
            if (candidate[nidx] && !is_bg[nidx]) {
                is_bg[nidx] = 1;
                stack[sp++] = (int)nidx;
            }
        }
    }
    free(stack);
    free(candidate);

    /* Write alpha: 0 for background, 255 for figure. */
    for (size_t i = 0; i < (size_t)w * h; i++) {
        img[i * 4 + 3] = is_bg[i] ? 0 : 255;
    }

    if (feather) {
        /* Single antialiasing ring: for every opaque pixel adjacent to a
         * background pixel, set alpha to the fraction of its 3x3
         * neighbourhood that is NOT background — smooths the binary cut
         * without touching anything more than one pixel from the border,
         * so no dithering pattern can appear deeper in either region. */
        unsigned char *alpha_out = malloc((size_t)w * h);
        for (size_t i = 0; i < (size_t)w * h; i++) alpha_out[i] = img[i * 4 + 3];

        for (int y = 0; y < h; y++) {
            for (int x = 0; x < w; x++) {
                size_t idx = (size_t)y * w + x;
                if (is_bg[idx]) continue; /* only feather the figure side */
                int touches_bg = 0;
                for (int dy = -1; dy <= 1 && !touches_bg; dy++) {
                    for (int dx = -1; dx <= 1; dx++) {
                        if (dx == 0 && dy == 0) continue;
                        int nx = x + dx, ny = y + dy;
                        if (nx < 0 || nx >= w || ny < 0 || ny >= h) continue;
                        if (is_bg[(size_t)ny * w + nx]) { touches_bg = 1; break; }
                    }
                }
                if (!touches_bg) continue;
                int opaque_count = 0, total = 0;
                for (int dy = -1; dy <= 1; dy++) {
                    for (int dx = -1; dx <= 1; dx++) {
                        int nx = x + dx, ny = y + dy;
                        if (nx < 0 || nx >= w || ny < 0 || ny >= h) continue;
                        total++;
                        if (!is_bg[(size_t)ny * w + nx]) opaque_count++;
                    }
                }
                alpha_out[idx] = (unsigned char)(255.0 * opaque_count / total + 0.5);
            }
        }
        for (size_t i = 0; i < (size_t)w * h; i++) img[i * 4 + 3] = alpha_out[i];
        free(alpha_out);
    }

    free(is_bg);

    stbi_write_png(out_path, w, h, 4, img, w * 4);
    fprintf(stderr, "matte_floodfill: %dx%d, threshold=%d, feather=%d -> %s\n",
            w, h, threshold, feather, out_path);

    stbi_image_free(img);
    return 0;
}
