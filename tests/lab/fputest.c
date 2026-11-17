/* FPUTest: float to unsigned conversions as the compiler emits them for
 * -m68040 -m68881 (OpenTTD's widget aspect ratios: uint(y * |ratio|)), with
 * the numbers they should give, to tell a code generation fault from an FPU
 * emulation fault in a lab.
 *   FPUTest
 * MIT, Copyright (c) 2026 AmiCradle Team. */
#include <stdio.h>
#include <math.h>

typedef unsigned int uint;

__attribute__((noinline)) uint conv_mul(uint y, float a) { return (uint)(y * fabsf(a)); }
__attribute__((noinline)) uint conv_div(uint x, float a) { return (uint)(x / fabsf(a)); }
__attribute__((noinline)) uint conv(float v) { return (uint)v; }
__attribute__((noinline)) int conv_signed(float v) { return (int)v; }
__attribute__((noinline)) float ratio(int x, int y) { return (float)x / (float)y; }

int main(void)
{
    static const struct { uint y; float a; uint expect; } mul[] = {
        { 14, 11.f / 14.f, 11 }, { 12, 8.f / 12.f, 8 }, { 24, 1.0f, 24 }, { 100, 0.5f, 50 }, { 3000000000u, 1.0f, 3000000000u },
    };
    static const struct { float v; uint expect; } plain[] = {
        { 0.f, 0 }, { 1.f, 1 }, { 12.9f, 12 }, { 2147483520.f, 2147483520u }, { 3000000000.f, 3000000000u },
    };
    int bad = 0;
    unsigned i;
    float r = ratio(11, 14);
    printf("ratio(11,14) = %d/1000000 (expect 785714)\n", conv_signed(r * 1000000.f));
    for (i = 0; i < sizeof(mul) / sizeof(mul[0]); i++) {
        uint got = conv_mul(mul[i].y, mul[i].a);
        printf("uint(%u * |%d/1000|) = %u, expect %u%s\n", mul[i].y, conv_signed(mul[i].a * 1000.f), got, mul[i].expect, got == mul[i].expect ? "" : "  WRONG");
        bad += got != mul[i].expect;
    }
    for (i = 0; i < sizeof(plain) / sizeof(plain[0]); i++) {
        uint got = conv(plain[i].v);
        printf("uint(%d.%d) = %u, expect %u%s\n", conv_signed(plain[i].v), conv_signed((plain[i].v - conv_signed(plain[i].v)) * 10.f), got, plain[i].expect, got == plain[i].expect ? "" : "  WRONG");
        bad += got != plain[i].expect;
    }
    printf("uint(14 / |11/14|) = %u, expect 17\n", conv_div(14, r));
    printf("%d wrong\n", bad);
    return bad ? 10 : 0;
}
