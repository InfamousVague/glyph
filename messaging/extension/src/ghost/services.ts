// The cookie-login services the app reaches through a sidecar (messaging/lib/inbox/account_helper.dart's
// HelperService). The extension captures a signed-in browser's cookies for each and syncs them; the app signs in
// with them. Adding a service here (and in account_helper.dart) is all it takes — the rest of the extension iterates
// this list, so "any sidecar service" is covered without further code.
//
// `needed` are the cookies a service cannot sign in without: the extension treats a site as "signed in and ready to
// sync" once all of them are present. The app re-filters what it keeps per service (cookiesOf), so capturing the
// whole site's cookies is fine. LinkedIn was here and is gone, as from the app (Matt, 2026-11-21: "linked in keeps
// automatically signing our sessions out remove the plugin"): LinkedIn ended the session whenever it was used elsewhere.

export interface Service {
  /** The network id in the app ("messenger"), which the synced entry is filed under. */
  id: string;
  name: string;
  /** The cookie domains to read (a leading dot matches subdomains). Messenger spans two. */
  domains: string[];
  /** The cookies that must be present for a sign-in; the capture is "ready" once they all are. */
  needed: string[];
  /** Where the person signs in, opened from the popup. */
  signInUrl: string;
}

export const SERVICES: Service[] = [
  {
    id: 'messenger',
    name: 'Messenger',
    domains: ['.messenger.com', '.facebook.com'],
    needed: ['xs', 'c_user', 'datr'],
    signInUrl: 'https://www.messenger.com/',
  },
  {
    id: 'instagram',
    name: 'Instagram',
    domains: ['.instagram.com'],
    needed: ['sessionid', 'csrftoken', 'ds_user_id'],
    signInUrl: 'https://www.instagram.com/direct/inbox/',
  },
];

export const serviceById = (id: string): Service | undefined => SERVICES.find((s) => s.id === id);
