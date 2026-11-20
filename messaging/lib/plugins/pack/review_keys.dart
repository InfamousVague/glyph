/// The trust this build ships with for the Marketplace (Matt, 2026-11-20: "I'd like to be able to verify them for the
/// store through a review process"): whose approvals it believes, and the withdrawals and retirements it carries itself.
library;

/// The review keys this build trusts: base64 of each 33-byte compressed P-256 public key whose approvals a store pack
/// must carry (lib/plugins/pack/review.dart). Matt's hub key, and any other device's he reviews from. Changing this list
/// is an app release: an approval by a key that is not here does not verify, at install or at any later load.
// Empty until Matt gives his key, copied from Settings › Admin › Plugin review › This device's review key on the device
// he reviews from and read back to him: never one the relay gave (a whois, the hub), which would make the relay the
// source of the trust. Until then this build trusts no reviewer, and nothing from other developers installs.
const List<String> marketReviewKeys = [];

/// Withdrawals this build carries itself (PackRevocation.toJson() maps), merged at load with what the relay says, each
/// verified as any other: a relay that withholds them can't keep a withdrawn plugin running on a new build.
const List<Map<String, Object>> shippedRevocations = [];

/// Review keys retired by their own signature (PackRetirement.toJson() maps), merged the same way.
const List<Map<String, Object>> shippedRetirements = [];
