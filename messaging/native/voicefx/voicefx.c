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
#define SHIFT 4096 /* The pitch shifter's line: a power of two, more than its window. */
#define WINDOW 1920 /* Its window, 40 ms at 48 kHz: half of it is how far behind the voice is. */
#define COMB 512

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
  /* The voice effect (voicefx_effect), and what it keeps from block to block, touched only on WebRTC's thread. */
  VFX_ATOMIC int effect;
  int effectWas;
  float shift[SHIFT];   /* the pitch shifter's delay line, at 48 kHz */
  int shiftAt;
  double shiftPhase;
  float comb[COMB];     /* the robot's ringing echo */
  int combAt;
  double ring;          /* the robot's carrier, 0 to 1 */
  float bq[2][4];       /* the radio's two filters' state: x1, x2, y1, y2 */
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

static float limit(float x);

/* --- voice effects ------------------------------------------------------------------------------------------------ */

/* The pitch moved by [ratio] (2 an octave up, 0.5 one down), as a tape read faster or slower: two taps on a delay line
 * a half window apart, each faded in and out as it sweeps, so the jump where a tap wraps is never heard. */
static void pitch_shift(VoiceFx *fx, float *s, int n, double ratio) {
  const double step = (1.0 - ratio) / WINDOW;
  for (int i = 0; i < n; i++) {
    fx->shift[fx->shiftAt & (SHIFT - 1)] = s[i];
    double out = 0;
    for (int tap = 0; tap < 2; tap++) {
      double p = fx->shiftPhase + tap * 0.5;
      p -= floor(p);
      double delay = 1.0 + p * WINDOW;
      double at = (double)fx->shiftAt - delay;
      long a = (long)floor(at);
      float f = (float)(at - (double)a);
      float x = fx->shift[a & (SHIFT - 1)] * (1 - f) + fx->shift[(a + 1) & (SHIFT - 1)] * f;
      double gain = 0.5 - 0.5 * cos(2.0 * 3.14159265358979 * p);
      out += x * gain;
    }
    s[i] = (float)out;
    fx->shiftAt++;
    fx->shiftPhase += step;
    fx->shiftPhase -= floor(fx->shiftPhase);
  }
}

/* A second-order filter (RBJ's cookbook) on [s], its state in [z]. */
static void biquad(float *s, int n, float *z, double b0, double b1, double b2, double a1, double a2) {
  for (int i = 0; i < n; i++) {
    double x = s[i];
    double y = b0 * x + b1 * z[0] + b2 * z[1] - a1 * z[2] - a2 * z[3];
    z[1] = z[0];
    z[0] = (float)x;
    z[3] = z[2];
    z[2] = (float)y;
    s[i] = (float)y;
  }
}

static void pass(float *s, int n, float *z, double hz, int high) {
  const double w = 2.0 * 3.14159265358979 * hz / 48000.0, q = 0.8;
  const double c = cos(w), alpha = sin(w) / (2 * q), a0 = 1 + alpha;
  if (high) {
    biquad(s, n, z, (1 + c) / 2 / a0, -(1 + c) / a0, (1 + c) / 2 / a0, -2 * c / a0, (1 - alpha) / a0);
  } else {
    biquad(s, n, z, (1 - c) / 2 / a0, (1 - c) / a0, (1 - c) / 2 / a0, -2 * c / a0, (1 - alpha) / a0);
  }
}

/* Driven: soft saturation on the 16-bit scale, [drive] times into it. */
static void drive(float *s, int n, float amount) {
  for (int i = 0; i < n; i++) {
    float x = s[i] / 32768.0f * amount;
    s[i] = 32768.0f * 0.85f * (x / (1.0f + fabsf(x)));
  }
}

static void effect(VoiceFx *fx, int which, float *s, int n) {
  if (which != fx->effectWas) {
    /* A new effect starts from quiet: nothing of the last one's lines is heard. */
    memset(fx->shift, 0, sizeof fx->shift);
    memset(fx->comb, 0, sizeof fx->comb);
    memset(fx->bq, 0, sizeof fx->bq);
    fx->shiftPhase = 0;
    fx->ring = 0;
    fx->effectWas = which;
  }
  switch (which) {
    case VOICEFX_EFFECT_DEEPER: pitch_shift(fx, s, n, 0.79); break;
    case VOICEFX_EFFECT_HIGHER: pitch_shift(fx, s, n, 1.33); break;
    case VOICEFX_EFFECT_CHIPMUNK: pitch_shift(fx, s, n, 1.85); break;
    case VOICEFX_EFFECT_MONSTER:
      pitch_shift(fx, s, n, 0.6);
      drive(s, n, 2.2f);
      break;
    case VOICEFX_EFFECT_ROBOT:
      for (int i = 0; i < n; i++) {
        /* Ring modulated at 55 Hz, half and half with the voice, then a 7 ms echo that rings. */
        float carrier = (float)sin(2.0 * 3.14159265358979 * fx->ring);
        fx->ring += 55.0 / 48000.0;
        fx->ring -= floor(fx->ring);
        float x = s[i] * (0.45f + 0.55f * carrier);
        int back = (fx->combAt - 336) & (COMB - 1);
        float y = x + fx->comb[back] * 0.55f;
        fx->comb[fx->combAt & (COMB - 1)] = y;
        fx->combAt++;
        s[i] = limit(y * 0.8f);
      }
      break;
    case VOICEFX_EFFECT_RADIO:
      pass(s, n, fx->bq[0], 400, 1);
      pass(s, n, fx->bq[1], 2800, 0);
      drive(s, n, 3.0f);
      break;
    default: break;
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
  int which = vfx_load(&fx->effect);
  if (which > 0 && which < VOICEFX_EFFECT_COUNT && tenMs && !vfx_load(&fx->live)) {
    resample(samples, frames, fx->at48, BLOCK);
    effect(fx, which, fx->at48, BLOCK);
    resample(fx->at48, BLOCK, samples, frames);
  } else if (which != fx->effectWas) {
    fx->effectWas = -1; /* begun afresh when it is next on */
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

void voicefx_effect(VoiceFx *fx, int effect) {
  if (!fx) return;
  if (effect < 0 || effect >= VOICEFX_EFFECT_COUNT) effect = VOICEFX_EFFECT_NONE;
  vfx_store(&fx->effect, effect);
}
