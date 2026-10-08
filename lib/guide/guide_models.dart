/// What the walkthrough's model page needs of the phone's language models: whether one is here, a download as it
/// comes, what went wrong with the last, and a way to start one. The seam between lib/guide and lib/ai, which is
/// another piece's and still moving: of `useModels()` (src/app/core/ai.ts) only what `guide/pages/Model.tsx` reads.
///
/// **To plug in:** an adapter over lib/ai/backend.dart's `ModelsController`, whose fields are these one for one
/// ([GuideModels.present] is `models.any((m) => m.id == id && m.present)`, [GuideModels.download] its `download`,
/// [GuideModels.problem] its `problem`, [GuideModels.fetch] its `fetch`), with [GuideModels.offered] true where
/// `aiBackend.available` and the phone is not an iPhone. Whoever makes the controller calls its `refresh`, as the
/// hook did when it mounted. Until then the page is given [NoGuideModels], which is the web page in a browser: the
/// rows set the preference, and nothing is said of downloads.
library;

import 'package:flutter/foundation.dart';

/// A download in flight (`Download`).
@immutable
class GuideDownload {
  const GuideDownload({required this.id, required this.received, required this.total});
  final String id;
  final int received;
  final int total;
}

/// The models on this phone, as the model page reads them.
abstract class GuideModels implements Listenable {
  /// Whether a model can be fetched here at all: the app with its engine, and not an iPhone (`isTauri() && !isIOS`).
  /// False, the page says nothing of downloads.
  bool get offered;

  /// Whether model [id] is on the phone.
  bool present(String id);

  /// The download in flight, if one is.
  GuideDownload? get download;

  /// Why the last download failed, in the engine's words.
  String? get problem;

  /// Downloads model [id]. A second call while one is coming is not a second download.
  void fetch(String id);
}

/// No engine to ask: a build without one, or a phone that runs no model.
class NoGuideModels extends ChangeNotifier implements GuideModels {
  @override
  bool get offered => false;

  @override
  bool present(String id) => false;

  @override
  GuideDownload? get download => null;

  @override
  String? get problem => null;

  @override
  void fetch(String id) {}
}
