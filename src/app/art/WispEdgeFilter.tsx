import {
  WISP_EDGE_ABOVE,
  WISP_EDGE_BAND,
  WISP_EDGE_BENT_ID,
  WISP_EDGE_DRIFT_ID,
  WISP_EDGE_FILTER_ID,
  WISP_EDGE_FOOT_BAND,
  WISP_EDGE_FOOT_BENT_ID,
  WISP_EDGE_FOOT_DRIFT_ID,
  WISP_EDGE_FOOT_NEAR_ID,
  WISP_EDGE_FOOT_NOISE_ID,
  WISP_EDGE_FOOT_SOFT_ID,
  WISP_EDGE_FOOT_STRIP_ID,
  WISP_EDGE_NEAR_ID,
  WISP_EDGE_NOISE_ID,
  WISP_EDGE_REACH,
  WISP_EDGE_SOFT,
  WISP_EDGE_SOFT_ID,
  WISP_EDGE_STRIP_ID,
} from './wispEdge.ts';

/**
 * The wisp edge's filter (art/wispEdge.ts), drawn once for the whole app.
 *
 * The band is made inside the filter and opaque everywhere (black, a white
 * strip over the top, its lower edge blurred soft): it decides where the noise
 * bends the picture, exactly neutral grey elsewhere so nothing below the band
 * moves at all, and where a blurred copy lies over it. The noise is made
 * opaque too, since the displacement reads colour unpremultiplied and a
 * see-through value would shift the whole view. The strip is only a lip at
 * the top with a long soft edge below it, so the bend is strongest at the
 * header's edge and fades as content comes down from it; the hook moves the
 * strip down under a header, and while a view sits scrolled slides the noise
 * and breathes its frequency, so the smoke drifts (art/wispEdge.ts). The bend
 * and the blur are only computed over the band's reach (their subregions,
 * which the hook sizes with the strip): below it the view is the source
 * itself, so a drifting frame costs the band, not the page. The smoke keeps
 * the view's own colours (a green tint was tried and undone), and it stays
 * with the letters: the blur is kept inside a slightly widened copy of the
 * bent view, so it softens the strokes and reaches a couple of pixels past
 * them but never spreads into the empty paper under the header's edge, where
 * a blurred first line read as a glow along the edge (measured at up to 110
 * of 255 in the gap before the text; Matt: "too transparent").
 *
 * The foot is the same band again at the view's bottom edge, for words scrolling off the end, with its own noise and
 * its own subregions placed by the hook (`placeFoot`); parked far below and computed over nothing while a view has
 * no foot, so a page that doesn't ask for one pays for a few empty primitives and nothing else.
 */
export function WispEdgeFilter() {
  return (
    <svg width="0" height="0" style={{ position: 'absolute' }} aria-hidden="true" focusable="false">
      <filter id={WISP_EDGE_FILTER_ID} filterUnits="userSpaceOnUse" x="-40" y="-40" width="4000" height="60000" colorInterpolationFilters="sRGB">
        <feTurbulence id={WISP_EDGE_NOISE_ID} type="fractalNoise" baseFrequency="0.018 0.06" numOctaves="2" seed="3" x="-40" y="-40" width="4000" height={40 + WISP_EDGE_REACH} result="rawNoise" />
        {/* Slid down as it drifts: the gap that opens is above the view, where nothing is drawn. */}
        <feOffset id={WISP_EDGE_DRIFT_ID} in="rawNoise" dx="0" dy="0" result="slid" />
        <feColorMatrix in="slid" type="matrix" values="1 0 0 0 0  0 1 0 0 0  0 0 1 0 0  0 0 0 0 1" result="noise" />
        <feFlood floodColor="#000" result="black" />
        <feFlood id={WISP_EDGE_STRIP_ID} floodColor="#fff" x="-40" y={-WISP_EDGE_ABOVE} width="4000" height={WISP_EDGE_ABOVE + WISP_EDGE_BAND} result="strip" />
        <feMerge result="stripOnBlack">
          <feMergeNode in="black" />
          <feMergeNode in="strip" />
        </feMerge>
        <feGaussianBlur in="stripOnBlack" stdDeviation={`0 ${WISP_EDGE_SOFT}`} result="band" />
        <feComposite in="noise" in2="band" operator="arithmetic" k1="1" k2="0" k3="-0.5" k4="0.5" result="field" />
        <feDisplacementMap id={WISP_EDGE_BENT_ID} in="SourceGraphic" in2="field" scale="36" xChannelSelector="R" yChannelSelector="G" x="-40" y="-40" width="4000" height={40 + WISP_EDGE_REACH} result="bent" />
        <feGaussianBlur id={WISP_EDGE_SOFT_ID} in="bent" stdDeviation="3.4" x="-40" y="-40" width="4000" height={40 + WISP_EDGE_REACH} result="soft" />
        {/* The bent strokes widened a little: where the blur is allowed to be, so it never glows into empty space. */}
        <feMorphology id={WISP_EDGE_NEAR_ID} in="bent" operator="dilate" radius="2.5" x="-40" y="-40" width="4000" height={40 + WISP_EDGE_REACH} result="near" />
        <feComposite in="soft" in2="near" operator="in" result="softNear" />
        <feColorMatrix in="band" type="luminanceToAlpha" result="bandAlpha" />
        <feComposite in="softNear" in2="bandAlpha" operator="in" result="smoke" />

        {/* The foot: the same again at the view's bottom edge, its strip rising from below it. */}
        <feTurbulence id={WISP_EDGE_FOOT_NOISE_ID} type="fractalNoise" baseFrequency="0.018 0.06" numOctaves="2" seed="3" x="-40" y={1e6} width="4000" height={0} result="rawFootNoise" />
        <feOffset id={WISP_EDGE_FOOT_DRIFT_ID} in="rawFootNoise" dx="0" dy="0" result="footSlid" />
        <feColorMatrix in="footSlid" type="matrix" values="1 0 0 0 0  0 1 0 0 0  0 0 1 0 0  0 0 0 0 1" result="footNoise" />
        <feFlood id={WISP_EDGE_FOOT_STRIP_ID} floodColor="#fff" x="-40" y={1e6} width="4000" height={WISP_EDGE_ABOVE + WISP_EDGE_FOOT_BAND} result="footStrip" />
        <feMerge result="footOnBlack">
          <feMergeNode in="black" />
          <feMergeNode in="footStrip" />
        </feMerge>
        <feGaussianBlur in="footOnBlack" stdDeviation={`0 ${WISP_EDGE_SOFT}`} result="footBand" />
        <feComposite in="footNoise" in2="footBand" operator="arithmetic" k1="1" k2="0" k3="-0.5" k4="0.5" result="footField" />
        <feDisplacementMap id={WISP_EDGE_FOOT_BENT_ID} in="SourceGraphic" in2="footField" scale="36" xChannelSelector="R" yChannelSelector="G" x="-40" y={1e6} width="4000" height={0} result="footBent" />
        <feGaussianBlur id={WISP_EDGE_FOOT_SOFT_ID} in="footBent" stdDeviation="3.4" x="-40" y={1e6} width="4000" height={0} result="footSoft" />
        <feMorphology id={WISP_EDGE_FOOT_NEAR_ID} in="footBent" operator="dilate" radius="2.5" x="-40" y={1e6} width="4000" height={0} result="footNear" />
        <feComposite in="footSoft" in2="footNear" operator="in" result="footSoftNear" />
        <feColorMatrix in="footBand" type="luminanceToAlpha" result="footAlpha" />
        <feComposite in="footSoftNear" in2="footAlpha" operator="in" result="footSmoke" />

        {/* The view itself where neither band is, each band's bent view in its own, and the smoke over both. */}
        <feComposite in="SourceGraphic" in2="bandAlpha" operator="out" result="restTop" />
        <feComposite in="restTop" in2="footAlpha" operator="out" result="rest" />
        <feComposite in="bent" in2="bandAlpha" operator="in" result="bentIn" />
        <feComposite in="footBent" in2="footAlpha" operator="in" result="footBentIn" />
        <feMerge>
          <feMergeNode in="rest" />
          <feMergeNode in="bentIn" />
          <feMergeNode in="smoke" />
          <feMergeNode in="footBentIn" />
          <feMergeNode in="footSmoke" />
        </feMerge>
      </filter>
    </svg>
  );
}
