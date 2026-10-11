#version 460 core

// A wisp read off what is already drawn behind it, where the engine can filter its own backdrop with a program
// (Impeller: `ImageFilter.shader`). MEASURING ONLY so far (GHOST_PERF_SMOKE=backdrop): the bend of
// shaders/wisp_smoke.frag and the view's fade, with no picture of the view taken and none made small for the soft
// half, which is not drawn at all here; the fade is to the page's paper, the backdrop having no clear in it. It is
// here to say what a strip costs a frame when nothing is drawn twice, before the look is brought to it.

#include <flutter/runtime_effect.glsl>

precision highp float;

// Set by the engine: the size of the backdrop, in its own pixels.
uniform vec2 uSize;
// The view's corner on the screen, in logical pixels, and the screen's pixels to one of them.
uniform vec2 uViewAt;
uniform float uRatio;
uniform vec4 uFieldRect;
uniform vec2 uFieldSize;
uniform vec2 uFrequency;
uniform vec2 uSlide;
uniform vec4 uNoiseRect;
uniform vec4 uBand;
uniform vec2 uBandOn;
uniform float uBend;
uniform vec4 uFade;
// The page's paper, which the view fades to.
uniform vec4 uPaper;
// Measuring only: 1 draws the strip plain red (is the filter drawn at all), 2 reads the backdrop a hundred times
// more for nothing (does the screen's own frame pay for the filter), 3 draws the band in red and the noise in
// green and blue, 4 the pixel's place in the view as the program has it (a stripe every hundred pixels down in
// red and across in green) and the bend in blue.
uniform float uProbe;

// Set by the engine: what is drawn so far.
uniform sampler2D uBackdrop;
uniform sampler2D uField;

out vec4 fragColor;

// The noise at one pixel of its picture (shaders/wisp_field.frag): twelve bits an axis, unpacked.
vec2 wispFieldPixel(vec2 pixel) {
  vec2 uv = (clamp(pixel, vec2(0.0), uFieldSize - vec2(1.0)) + vec2(0.5)) / uFieldSize;
  vec3 t = floor(texture(uField, uv).rgb * 255.0 + 0.5);
  float high = floor(t.g / 16.0);
  float low = t.g - high * 16.0;
  return vec2(t.r * 16.0 + high, low * 256.0 + t.b) / 4095.0;
}

// The noise at a point of its own space: the four pixels of its picture round the point, weighed by where it lies
// between them. Unpacked first and weighed after; the engine's own reading between pixels would weigh the packed
// bytes, which mean nothing apart.
vec2 wispField(vec2 v) {
  vec2 at = (v - uFieldRect.xy) / uFieldRect.zw * uFieldSize - vec2(0.5);
  vec2 corner = floor(at);
  vec2 f = at - corner;
  vec2 upper = mix(wispFieldPixel(corner), wispFieldPixel(corner + vec2(1.0, 0.0)), f.x);
  vec2 lower = mix(wispFieldPixel(corner + vec2(0.0, 1.0)), wispFieldPixel(corner + vec2(1.0, 1.0)), f.x);
  return mix(upper, lower, f.y);
}

// The normal distribution's running total: what a step looks like after `feGaussianBlur`.
float wispRamp(float x) {
  float t = 1.0 / (1.0 + 0.3275911 * abs(x) * 0.70710678);
  float y = 1.0 - (((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t - 0.284496736) * t + 0.254829592) * t * exp(-0.5 * x * x);
  return 0.5 * (1.0 + sign(x) * y);
}

// The band at a point, 0 to 1: the white strips on black, blurred along their axis.
float wispBand(vec2 p) {
  float along = mix(p.y, p.x, uBand.w);
  float sigma = max(uBand.z, 0.0001);
  float band = uBandOn.x * wispRamp((uBand.x - along) / sigma) + uBandOn.y * wispRamp((along - uBand.y) / sigma);
  return clamp(band, 0.0, 1.0);
}

// A `linear-gradient` mask along the axis: transparent, black, black, transparent at the four stops.
float wispFade(vec2 p) {
  float along = mix(p.y, p.x, uBand.w);
  float rise = uFade.y > uFade.x ? clamp((along - uFade.x) / (uFade.y - uFade.x), 0.0, 1.0) : step(uFade.x, along);
  float fall = uFade.w > uFade.z ? clamp((uFade.w - along) / (uFade.w - uFade.z), 0.0, 1.0) : 1.0 - step(uFade.w, along);
  return rise * fall;
}

void main() {
  vec2 px = FlutterFragCoord().xy;
  vec2 p = px / uRatio - uViewAt;
  float band = wispBand(p);
  vec2 q = p - uSlide;
  vec2 noise = vec2(0.5);
  if (q.x >= uNoiseRect.x && q.y >= uNoiseRect.y && q.x < uNoiseRect.z && q.y < uNoiseRect.w) {
    noise = wispField((q + vec2(0.5)) * uFrequency);
  }
  vec4 rest = texture(uBackdrop, px / uSize);
  vec4 bent = texture(uBackdrop, (px + uBend * band * (noise - vec2(0.5)) * uRatio) / uSize);
  fragColor = mix(uPaper, mix(rest, bent, band), wispFade(p));
  if (uProbe > 3.5) {
    fragColor = vec4(fract(p.y / 100.0), fract(p.x / 100.0), uBend / 48.0, 1.0);
  } else if (uProbe > 2.5) {
    fragColor = vec4(band, noise.x, noise.y, 1.0);
  } else if (uProbe > 1.5) {
    vec4 sum = vec4(0.0);
    for (int i = 0; i < 100; i++) {
      sum += texture(uBackdrop, (px + vec2(float(i) * 3.0, float(i))) / uSize);
    }
    fragColor += sum * 0.00001;
  } else if (uProbe > 0.5) {
    fragColor = vec4(1.0, 0.0, 0.0, 1.0);
  }
}
