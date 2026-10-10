/// Java: @lezer/java's grammar (java.g.dart), which has no code of its own.
library;

import '../lezer/lr.dart';
import 'java.g.dart';

/// @lezer/java's `parser`.
final LRParser javaParser = LRParser.deserialize(javaSpec);
