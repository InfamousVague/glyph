import 'forward_secrecy.dart' show FsStore;

/// In a browser (kept_files.dart): no files, and so no ledger, which a browser has no direct route to compare anyway.
FsStore? ledgerFiles() => null;
