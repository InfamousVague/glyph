/// Vue: the grammar of @codemirror/lang-vue (vue.g.dart), which has no code of its own. It reads two things of a
/// page that is otherwise HTML's: its text, for `{{ … }}`, and an attribute that starts `@`, `:` or `v-`.
library;

import '../lezer/lr.dart';
import 'vue.g.dart';

/// The grammar at its first top rule, `Content`: a stretch of a page's text.
final LRParser vueTextParser = LRParser.deserialize(vueSpec);

/// `baseParser.configure({top: 'Attribute'})`: one attribute.
final LRParser vueAttributeParser = vueTextParser.configure(top: 'Attribute');
