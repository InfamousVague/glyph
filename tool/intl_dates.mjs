// What a browser's own `Intl.DateTimeFormat` writes for every form the app writes a date in, in the languages
// lib/main_dates.dart asks the phone about: test/core/fixtures/intl_dates.json, which
// test/core/phone_dates_test.dart holds lib/core/locale_dates.dart to when it writes from the phone's own words
// (test/core/fixtures/phone_dates.json).
//
//   node tool/intl_dates.mjs
//
// This is Node's V8 and Node's ICU, not a phone's WebView: the same code that reads the options and makes the
// skeleton, over whatever CLDR this Node carries (the file says which). Each form's options are the page's own, as
// test/core/fixtures/locale_dates.json recorded them from the WebView, and the four moments are that file's.
import { readFileSync, writeFileSync } from 'node:fs';

const here = new URL('..', import.meta.url);
const page = JSON.parse(readFileSync(new URL('test/core/fixtures/locale_dates.json', here), 'utf8'));
const source = readFileSync(new URL('lib/main_dates.dart', here), 'utf8');
const list = source.slice(source.indexOf('datesLookedAt = ['), source.indexOf('];', source.indexOf('datesLookedAt = [')));
const locales = [...list.matchAll(/'([A-Za-z]{2,3}(?:-[A-Za-z0-9]+)*)'/g)].map((found) => found[1]);
const forms = page.locales['en-US'];
const moments = page.dates.map((key) => {
  const [y, m, d, h, mi, s] = key.split('-').map(Number);
  return new Date(y, m, d, h, mi, s);
});

const out = { node: process.version, icu: process.versions.icu, cldr: process.versions.cldr, dates: page.dates, locales: {} };
for (const tag of locales) {
  const own = new Intl.DateTimeFormat(tag).resolvedOptions();
  // A language that keeps a calendar with months of its own is written by the app in the Gregorian one: the
  // comparison is with the same, and `calendar` says what the browser would really have used.
  const carried = own.calendar === 'gregory' || own.calendar === 'buddhist';
  const asked = carried ? tag : `${tag}-u-ca-gregory`;
  const sets = {};
  for (const [form, { options }] of Object.entries(forms)) {
    const format = new Intl.DateTimeFormat(asked, options);
    sets[form] = { parts: moments.map((at) => format.formatToParts(at).map((part) => [part.type, part.value])), text: moments.map((at) => format.format(at)) };
  }
  out.locales[tag] = { calendar: own.calendar, numberingSystem: own.numberingSystem, forms: sets };
}
writeFileSync(new URL('test/core/fixtures/intl_dates.json', here), `${JSON.stringify(out)}\n`);
console.log(`${locales.length} languages, ${Object.keys(forms).length} forms, ICU ${out.icu} (CLDR ${out.cldr})`);
