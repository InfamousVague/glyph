/* voicefx: see voicefx.h. */
#include "voicefx.h"

#include <math.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>

/* The mode, the gain and DeepFilterNet's state are set on one thread and read on WebRTC's. C11 atomics where the
 * compiler has them; MSVC's C compiler (Windows) has them only behind an experimental switch, so there plain volatile
 * stands in: aligned 32- and 64-bit loads and stores are whole on x64 and arm64, and nothing here needs more. */
#if defined(_MSC_VER) && !defined(__clang__)
#define VFX_ATOMIC volatile
#define vfx_load(p) (*(p))
#define vfx_store(p, v) (*(p) = (v))
#else
#include <stdatomic.h>
#define VFX_ATOMIC _Atomic
#define vfx_load(p) atomic_load(p)
#define vfx_store(p, v) atomic_store(p, v)
#endif

#include "rnnoise.h"

#ifdef VOICEFX_WITH_DEEPFILTER
/* libDF's C API (DeepFilterNet, MIT/Apache-2.0), linked in where built (native/voicefx/deepfilter). */
typedef struct DFState DFState;
extern DFState *df_create(const char *path, float atten_lim, const char *log_level);
extern size_t df_get_frame_length(DFState *st);
extern float df_process_frame(DFState *st, float *input, float *output);
extern void df_free(DFState *st);
#endif

#define BLOCK 480 /* 10 ms at 48 kHz: RNNoise's frame, and DeepFilterNet's hop. */
#define MOST 1920 /* The longest block taken: 10 ms at 192 kHz. */

struct VoiceFx {
  VFX_ATOMIC int mode;
  VFX_ATOMIC float gain;
  DenoiseState *rnnoise;
#ifdef VOICEFX_WITH_DEEPFILTER
  DFState *VFX_ATOMIC df;
#endif
  float at48[BLOCK];
  float out48[BLOCK];
  /* Live voice changing (voicefx_live): what the microphone said, at 16 kHz, for the app to take and have changed;
   * and the changed voice the app gave back, at 48 kHz, played into the call in its place. Each is a ring with one
   * writer and one reader, so neither waits on the other. */
  VFX_ATOMIC int live;
  int16_t *heard; /* RING16 samples at 16 kHz */
  VFX_ATOMIC long heardIn, heardOut;
  float *give;    /* RING48 samples at 48 kHz */
  VFX_ATOMIC long giveIn, giveOut;
  float down[BLOCK];
};

#define RING16 (16000 * 20) /* twenty seconds of what was said, waiting to be taken */
#define RING48 (48000 * 30) /* thirty seconds of the changed voice, waiting to be played */

VoiceFx *voicefx_create(void) {
  VoiceFx *fx = calloc(1, sizeof(VoiceFx));
  if (!fx) return NULL;
  vfx_store(&fx->mode, VOICEFX_OFF);
  vfx_store(&fx->gain, 1.0f);
  fx->rnnoise = rnnoise_create(NULL);
  fx->heard = calloc(RING16, sizeof(int16_t));
  fx->give = calloc(RING48, sizeof(float));
  if (!fx->heard || !fx->give) {
    free(fx->heard);
    free(fx->give);
    if (fx->rnnoise) rnnoise_destroy(fx->rnnoise);
    free(fx);
    return NULL;
  }
  return fx;
}

void voicefx_destroy(VoiceFx *fx) {
  if (!fx) return;
  if (fx->rnnoise) rnnoise_destroy(fx->rnnoise);
  free(fx->heard);
  free(fx->give);
#ifdef VOICEFX_WITH_DEEPFILTER
  DFState *df = vfx_load(&fx->df);
  vfx_store(&fx->df, NULL);
  if (df) df_free(df);
#endif
  free(fx);
}

int voicefx_modes(VoiceFx *fx) {
  int bits = 0;
  if (fx && fx->rnnoise) bits |= 1 << VOICEFX_RNNOISE;
#ifdef VOICEFX_WITH_DEEPFILTER
  if (fx && vfx_load(&fx->df)) bits |= 1 << VOICEFX_DEEPFILTER;
#endif
  return bits;
}

int voicefx_deepfilter_model(VoiceFx *fx, const char *path) {
#ifdef VOICEFX_WITH_DEEPFILTER
  if (!fx || !path) return 0;
  if (vfx_load(&fx->df)) return 1;
  /* No limit on how far noise is brought down (100 dB); its frame is 480 at 48 kHz or it is not used. */
  DFState *df = df_create(path, 100.0f, NULL);
  if (!df) return 0;
  if (df_get_frame_length(df) != BLOCK) {
    df_free(df);
    return 0;
  }
  vfx_store(&fx->df, df);
  return 1;
#else
  (void)fx;
  (void)path;
  return 0;
#endif
}

void voicefx_configure(VoiceFx *fx, int mode, float gain) {
  if (!fx) return;
  if (gain < 0) gain = 0;
  if (gain > 2) gain = 2;
  vfx_store(&fx->mode, mode);
  vfx_store(&fx->gain, gain);
}

/* Linear resampling between a block of [n] and one of [m] samples: the same 10 ms either way. */
static void resample(const float *in, int n, float *out, int m) {
  if (n == m) {
    memcpy(out, in, sizeof(float) * (size_t)n);
    return;
  }
  for (int i = 0; i < m; i++) {
    float at = (float)i * (float)(n - 1) / (float)(m - 1 > 0 ? m - 1 : 1);
    int a = (int)at;
    int b = a + 1 < n ? a + 1 : n - 1;
    float f = at - (float)a;
    out[i] = in[a] * (1 - f) + in[b] * f;
  }
}

/* Over full scale, rounded off rather than clipped: the top tenth of the range is bent toward its end. */
static float limit(float x) {
  const float top = 32767.0f, knee = 29490.0f; /* 90% */
  float a = fabsf(x);
  if (a <= knee) return x;
  float over = (a - knee) / (top - knee);
  float bent = knee + (top - knee) * (over / (1.0f + over));
  return x < 0 ? -bent : bent;
}

void voicefx_process(VoiceFx *fx, float *samples, int frames, int rate) {
  if (!fx || !samples || frames <= 0 || frames > MOST) return;
  int mode = vfx_load(&fx->mode);
  float gain = vfx_load(&fx->gain);
  /* A block that is not 10 ms is not denoised (neither network could take it); the gain still applies. */
  int tenMs = rate > 0 && frames * 100 == rate;
#ifdef VOICEFX_WITH_DEEPFILTER
  DFState *df = vfx_load(&fx->df);
#endif
  if (tenMs && mode == VOICEFX_RNNOISE && fx->rnnoise) {
    resample(samples, frames, fx->at48, BLOCK);
    rnnoise_process_frame(fx->rnnoise, fx->out48, fx->at48); /* On the 16-bit scale, as it is given. */
    resample(fx->out48, BLOCK, samples, frames);
  }
#ifdef VOICEFX_WITH_DEEPFILTER
  else if (tenMs && mode == VOICEFX_DEEPFILTER && df) {
    resample(samples, frames, fx->at48, BLOCK);
    for (int i = 0; i < BLOCK; i++) fx->at48[i] /= 32768.0f; /* DeepFilterNet takes -1 to 1. */
    df_process_frame(df, fx->at48, fx->out48);
    for (int i = 0; i < BLOCK; i++) fx->out48[i] *= 32768.0f;
    resample(fx->out48, BLOCK, samples, frames);
  }
#endif
  if (gain != 1.0f) {
    for (int i = 0; i < frames; i++) samples[i] = limit(samples[i] * gain);
  }
  if (vfx_load(&fx->live) && tenMs) {
    /* What was said, cleaned and at its loudness, kept at 16 kHz for the app (every third sample of 48 kHz, after a
     * three-tap average so nothing above 8 kHz folds back). */
    resample(samples, frames, fx->at48, BLOCK);
    long in = vfx_load(&fx->heardIn), out = vfx_load(&fx->heardOut);
    for (int i = 0; i + 2 < BLOCK; i += 3) {
      if (in - out >= RING16) break; /* nobody is taking it: what is newest waits for room */
      float v = (fx->at48[i] + fx->at48[i + 1] + fx->at48[i + 2]) / 3.0f;
      fx->heard[in % RING16] = (int16_t)(v > 32767 ? 32767 : v < -32768 ? -32768 : v);
      in++;
    }
    vfx_store(&fx->heardIn, in);
    /* And in its place, the changed voice where some has come back; silence where none has. */
    long gin = vfx_load(&fx->giveIn), gout = vfx_load(&fx->giveOut);
    for (int i = 0; i < BLOCK; i++) {
      if (gout < gin) {
        fx->out48[i] = fx->give[gout % RING48];
        gout++;
      } else {
        fx->out48[i] = 0;
      }
    }
    vfx_store(&fx->giveOut, gout);
    resample(fx->out48, BLOCK, samples, frames);
  }
}

void voicefx_live(VoiceFx *fx, int on) {
  if (!fx) return;
  vfx_store(&fx->live, on ? 1 : 0);
  /* Begun or ended, nothing old is said or played. */
  vfx_store(&fx->heardOut, vfx_load(&fx->heardIn));
  vfx_store(&fx->giveIn, vfx_load(&fx->giveOut));
}

int voicefx_take(VoiceFx *fx, int16_t *out, int most) {
  if (!fx || !out || most <= 0) return 0;
  long in = vfx_load(&fx->heardIn), at = vfx_load(&fx->heardOut);
  int n = 0;
  while (at < in && n < most) out[n++] = fx->heard[at++ % RING16];
  vfx_store(&fx->heardOut, at);
  return n;
}

void voicefx_feed(VoiceFx *fx, const int16_t *pcm, int n, int rate) {
  if (!fx || !pcm || n <= 0 || rate <= 0) return;
  long in = vfx_load(&fx->giveIn), out = vfx_load(&fx->giveOut);
  /* To 48 kHz, linearly: for each sample at 48 kHz, where it falls in what was given. */
  long m = (long)n * 48000 / rate;
  for (long j = 0; j < m; j++) {
    if (in - out >= RING48) break; /* thirty seconds behind already: the rest is dropped */
    double at = (double)j * rate / 48000.0;
    int a = (int)at;
    int b = a + 1 < n ? a + 1 : n - 1;
    float f = (float)(at - a);
    fx->give[in % RING48] = pcm[a] * (1 - f) + pcm[b] * f;
    in++;
  }
  vfx_store(&fx->giveIn, in);
}

int voicefx_queued_ms(VoiceFx *fx) {
  if (!fx) return 0;
  return (int)((vfx_load(&fx->giveIn) - vfx_load(&fx->giveOut)) / 48);
}
