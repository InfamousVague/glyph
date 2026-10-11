#version 460 core

// A wisp's noise, drawn once as a picture: red and green of `feTurbulence` (the arithmetic of shaders/wisp_bend.frag,
// line for line), each as twelve bits packed across an opaque pixel the way the lattice's table packs its own.
//
// The noise does not know what scrolls under it. It changes when the smoke drifts, which is at most thirty-five
// times a second and only while a page is scrolled; the strip is drawn on every frame. So the sixteen readings of
// the table and the arithmetic round them are done here, at half the screen's pixels each way and only when the
// noise has moved, and the pass that draws the strip (shaders/wisp_smoke.frag) reads this picture instead: four
// pixels of it, weighed by where the point lies between them. The noise turns over a few times in a hundred
// pixels, so half the screen's pixels hold all of it; twelve bits and not eight, because a throw rounded to a
// two-hundred-and-fifty-fifth of its scale would jitter where each pixel is read from by an eighth of a pixel, at
// random, and a stroke's edge would come out rough.

#include <flutter/runtime_effect.glsl>

precision highp float;

// The drawn rectangle's corner in the view's own pixels: a fragment is at uOrigin + FlutterFragCoord().
uniform vec2 uOrigin;
// `baseFrequency`, per pixel.
uniform vec2 uFrequency;
// `feOffset` on the noise: the drift's slide.
uniform vec2 uSlide;
// The turbulence's own subregion: left, top, right, bottom. Slid out of it, the noise is black.
uniform vec4 uNoiseRect;

uniform sampler2D uTable;

out vec4 fragColor;

// The gradient the lattice gives a cell for a channel: twelve bits an axis, packed in an opaque texel.
vec2 wispGradient(float channel, vec2 cell) {
  vec2 at = mod(cell, 256.0);
  vec2 uv = vec2((channel * 256.0 + at.x + 0.5) / 512.0, (at.y + 0.5) / 256.0);
  vec3 t = floor(texture(uTable, uv).rgb * 255.0 + 0.5);
  float high = floor(t.g / 16.0);
  float low = t.g - high * 16.0;
  return vec2(t.r * 16.0 + high, low * 256.0 + t.b) / 4095.0 * 2.0 - 1.0;
}

// `noise2` of the specification: one octave at the noise's own coordinates.
float wispNoise(float channel, vec2 v) {
  vec2 cell = floor(v);
  vec2 r = v - cell;
  vec2 s = r * r * (3.0 - 2.0 * r);
  float u = dot(r, wispGradient(channel, cell));
  float w = dot(r - vec2(1.0, 0.0), wispGradient(channel, cell + vec2(1.0, 0.0)));
  float a = mix(u, w, s.x);
  u = dot(r - vec2(0.0, 1.0), wispGradient(channel, cell + vec2(0.0, 1.0)));
  w = dot(r - vec2(1.0, 1.0), wispGradient(channel, cell + vec2(1.0, 1.0)));
  float b = mix(u, w, s.x);
  return mix(a, b, s.y);
}

// Red and green of `fractalNoise` with two octaves, as colours from 0 to 1.
vec2 wispField(vec2 point) {
  vec2 v = point * uFrequency;
  vec2 sum = vec2(wispNoise(0.0, v), wispNoise(1.0, v));
  v *= 2.0;
  sum += 0.5 * vec2(wispNoise(0.0, v), wispNoise(1.0, v));
  return clamp(sum * 0.5 + 0.5, 0.0, 1.0);
}

void main() {
  vec2 p = uOrigin + FlutterFragCoord().xy;
  // Chromium works the noise out half a pixel on from the pixel's own middle.
  vec2 q = p - uSlide;
  vec2 noise = vec2(0.0);
  if (q.x >= uNoiseRect.x && q.y >= uNoiseRect.y && q.x < uNoiseRect.z && q.y < uNoiseRect.w) {
    noise = wispField(q + vec2(0.5));
  }
  // Twelve bits an axis: red has the high eight of the first, green its low four and the high four of the second,
  // blue the second's low eight.
  vec2 n = floor(noise * 4095.0 + 0.5);
  float xHigh = floor(n.x / 16.0);
  float yHigh = floor(n.y / 256.0);
  fragColor = vec4(xHigh / 255.0, ((n.x - xHigh * 16.0) * 16.0 + yHigh) / 255.0, (n.y - yHigh * 256.0) / 255.0, 1.0);
}
