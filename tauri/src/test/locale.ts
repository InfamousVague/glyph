import { vi } from 'vitest';

/**
 * `run` as a device set to `locale` would run it: every `Intl.DateTimeFormat` made with no locale of its own is made
 * with this one. The page asks the device's language that way everywhere it writes a date (core/stamp.ts,
 * core/template.ts), and a test cannot change the language the process started in.
 */
export function inLocale<T>(locale: string, run: () => T): T {
  const Real = Intl.DateTimeFormat;
  const spy = vi.spyOn(Intl, 'DateTimeFormat').mockImplementation(function made(asked?: string | string[], options?: Intl.DateTimeFormatOptions) {
    return new Real(asked ?? locale, options);
  } as unknown as typeof Intl.DateTimeFormat);
  try {
    return run();
  } finally {
    spy.mockRestore();
  }
}
