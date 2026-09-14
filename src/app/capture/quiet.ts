/**
 * "Stop when I go quiet": a recording that has heard someone speak saves
 * itself once they have been quiet for a few seconds.
 *
 * Two kinds of evidence of speech. The microphone's level, against a noise
 * floor that follows the room (quickly down, slowly up, so a fan does not
 * count as talking and a raised voice does not become the floor); and words
 * arriving from the recogniser, which lag speech by a second or two and so
 * only ever make the wait longer, never shorter. Nothing stops before the
 * first word: opening the recorder and thinking is not the end of a note.
 */
export class QuietWatch {
  private floor = 0.01;
  private lastVoice: number | null = null;
  /** Words have come back at least once: before that, nothing stops. */
  private spoke = false;

  constructor(readonly quietMs: number) {}

  /** A microphone level (RMS, 0 to 1) at `now` ms. */
  level(rms: number, now: number): void {
    this.floor = rms < this.floor ? this.floor * 0.8 + rms * 0.2 : this.floor * 0.995 + rms * 0.005;
    if (rms > Math.max(0.02, this.floor * 3)) this.lastVoice = now;
  }

  /** Words came back from the recogniser at `now`. */
  words(now: number): void {
    this.spoke = true;
    this.lastVoice = Math.max(this.lastVoice ?? 0, now);
  }

  /** Whether the recording should stop now. */
  due(now: number): boolean {
    return this.spoke && this.lastVoice !== null && now - this.lastVoice >= this.quietMs;
  }

  /** How long until it stops, for a countdown; null when nothing has been said. */
  remaining(now: number): number | null {
    return !this.spoke || this.lastVoice === null ? null : Math.max(0, this.quietMs - (now - this.lastVoice));
  }
}
