/// WebAssembly's text format: the grammar of @codemirror/lang-wast (wast.g.dart), which has no code of its own.
library;

import '../lezer/lr.dart';
import 'wast.g.dart';

/// `wastLanguage.parser`.
final LRParser wastParser = LRParser.deserialize(wastSpec);
