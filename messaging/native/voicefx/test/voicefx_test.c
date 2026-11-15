/* voicefx on the computer it is built on: cc this with the sources (native/voicefx/test/run.sh). */
#include <math.h>
#include <stdio.h>
#include <stdlib.h>

#include "voicefx.h"

static int failed = 0;
#define CHECK(c, ...) do { if (!(c)) { failed++; printf("FAIL: "); printf(__VA_ARGS__); printf("\n"); } else { printf("ok: "); printf(__VA_ARGS__); printf("\n"); } } while (0)

static float noise(void) { return ((float)rand() / (float)RAND_MAX * 2 - 1); }

/* The energy of white noise left after [blocks] blocks at [rate], the first second let settle. */
static double noiseLeft(VoiceFx *fx, int rate, int blocks) {
  int n = rate / 100;
  float buf[1920];
  double in = 0, out = 0;
  for (int b = 0; b < blocks; b++) {
    for (int i = 0; i < n; i++) buf[i] = noise() * 3000.0f;
    double e = 0;
    for (int i = 0; i < n; i++) e += buf[i] * buf[i];
    voicefx_process(fx, buf, n, rate);
    if (b < 100) continue;
    in += e;
    for (int i = 0; i < n; i++) out += buf[i] * buf[i];
  }
  return out / in;
}

int main(void) {
  srand(7);
  VoiceFx *fx = voicefx_create();
  CHECK(fx != NULL, "made");
  CHECK(voicefx_modes(fx) & (1 << VOICEFX_RNNOISE), "runs RNNoise");

  voicefx_configure(fx, VOICEFX_OFF, 1.0f);
  double off = noiseLeft(fx, 48000, 300);
  CHECK(fabs(off - 1.0) < 1e-6, "off leaves the sound as it is (%.4f)", off);

  voicefx_configure(fx, VOICEFX_RNNOISE, 1.0f);
  double rn = noiseLeft(fx, 48000, 300);
  CHECK(rn < 0.1, "RNNoise takes steady noise down by more than 10 dB at 48 kHz (%.1f dB)", 10 * log10(rn));
  double rn16 = noiseLeft(fx, 16000, 300);
  CHECK(rn16 < 0.2, "and at 16 kHz, resampled (%.1f dB)", 10 * log10(rn16));

  /* Gain: 2x, and nothing past full scale. */
  voicefx_configure(fx, VOICEFX_OFF, 2.0f);
  float b[480];
  for (int i = 0; i < 480; i++) b[i] = 1000.0f * sinf(i * 0.1f);
  voicefx_process(fx, b, 480, 48000);
  CHECK(fabsf(b[16] - 2000.0f * sinf(1.6f)) < 0.5f, "200%% doubles a quiet signal (%.1f)", b[16]);
  float most = 0;
  for (int i = 0; i < 480; i++) b[i] = 30000.0f * sinf(i * 0.1f);
  voicefx_process(fx, b, 480, 48000);
  for (int i = 0; i < 480; i++) most = fmaxf(most, fabsf(b[i]));
  CHECK(most <= 32767.0f && most > 30000.0f, "a loud one is rounded off under full scale (%.0f)", most);

  voicefx_configure(fx, VOICEFX_OFF, 5.0f);
  for (int i = 0; i < 480; i++) b[i] = 100.0f;
  voicefx_process(fx, b, 480, 48000);
  CHECK(fabsf(b[0] - 200.0f) < 0.01f, "gain is held to 200%% (%.1f)", b[0]);

  /* A block that is not 10 ms: not denoised, gain still applied. */
  voicefx_configure(fx, VOICEFX_RNNOISE, 1.5f);
  float odd[256];
  for (int i = 0; i < 256; i++) odd[i] = 100.0f;
  voicefx_process(fx, odd, 256, 48000);
  CHECK(fabsf(odd[10] - 150.0f) < 0.01f, "a 256-sample block passes with gain alone (%.1f)", odd[10]);

  CHECK(voicefx_deepfilter_model(fx, "/nonexistent") == 0 || (voicefx_modes(fx) & (1 << VOICEFX_DEEPFILTER)), "no model, no DeepFilterNet");
  voicefx_destroy(fx);
  printf(failed ? "%d FAILED\n" : "all passed\n", failed);
  return failed ? 1 : 0;
}
