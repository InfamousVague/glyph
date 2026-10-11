/// JSON: @lezer/json's grammar (json.g.dart), which has no code of its own.
library;

import '../lezer/lr.dart';
import 'json.g.dart';

/// @lezer/json's `parser`.
final LRParser jsonParser = LRParser.deserialize(jsonSpec);
