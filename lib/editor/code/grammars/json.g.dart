// Written by tool/code_grammars.mjs from @lezer/json 1.0.3: do not edit by hand.
//
// The grammar's tables as Lezer ships them (MIT, Marijn Haverbeke and others), and the class
// src/app/editor/glyphHighlight.ts gives each node's tags.
// ignore_for_file: lines_longer_than_80_chars, constant_identifier_names, non_constant_identifier_names
import '../lezer/lr.dart';

/// The grammar's tokens, by the names its tokenizers know them by (@lezer/json 1.0.3. `parser.terms.js`).
abstract final class JsonTerms {

}

/// @lezer/json 1.0.3.
final LRParserSpec jsonSpec = LRParserSpec(
  states: '\$bOVQPOOOOQO\'#Cb\'#CbOnQPO\'#CeOvQPO\'#ClOOQO\'#Cr\'#CrQOQPOOOOQO\'#Cg\'#CgO}QPO\'#CfO!SQPO\'#CtOOQO,59P,59PO![QPO,59PO!aQPO\'#CuOOQO,59W,59WO!iQPO,59WOVQPO,59QOqQPO\'#CmO!nQPO,59`OOQO1G.k1G.kOVQPO\'#CnO!vQPO,59aOOQO1G.r1G.rOOQO1G.l1G.lOOQO,59X,59XOOQO-E6k-E6kOOQO,59Y,59YOOQO-E6l-E6l',
  stateData: '#O~OeOS~OQSORSOSSOTSOWQO_ROgPO~OVXOgUO~O^[O~PVO[^O~O]_OVhX~OVaO~O]bO^iX~O^dO~O]_OVha~O]bO^ia~O',
  goto: '!kjPPPPPPkPPkqwPPPPk{!RPPP!XP!e!hXSOR^bQWQRf_TVQ_Q`WRg`QcZRicQTOQZRQe^RhbRYQR]R',
  nodeNames: '⚠ JsonText True False Null Number String } { Object Property PropertyName : , ] [ Array',
  maxTerm: 25,
  context: null,
  skippedNodes: [0],
  repeatNodeCount: 2,
  tokenData: '(|~RaXY!WYZ!W]^!Wpq!Wrs!]|}\$u}!O\$z!Q!R%T!R![&c![!]&t!}#O&y#P#Q\'O#Y#Z\'T#b#c\'r#h#i(Z#o#p(r#q#r(w~!]Oe~~!`Wpq!]qr!]rs!xs#O!]#O#P!}#P;\'S!];\'S;=`\$o<%lO!]~!}Og~~#QXrs!]!P!Q!]#O#P!]#U#V!]#Y#Z!]#b#c!]#f#g!]#h#i!]#i#j#m~#pR!Q![#y!c!i#y#T#Z#y~#|R!Q![\$V!c!i\$V#T#Z\$V~\$YR!Q![\$c!c!i\$c#T#Z\$c~\$fR!Q![!]!c!i!]#T#Z!]~\$rP;=`<%l!]~\$zO]~~\$}Q!Q!R%T!R![&c~%YRT~!O!P%c!g!h%w#X#Y%w~%fP!Q![%i~%nRT~!Q![%i!g!h%w#X#Y%w~%zR{|&T}!O&T!Q![&Z~&WP!Q![&Z~&`PT~!Q![&Z~&hST~!O!P%c!Q![&c!g!h%w#X#Y%w~&yO[~~\'OO_~~\'TO^~~\'WP#T#U\'Z~\'^P#`#a\'a~\'dP#g#h\'g~\'jP#X#Y\'m~\'rOR~~\'uP#i#j\'x~\'{P#`#a(O~(RP#`#a(U~(ZOS~~(^P#f#g(a~(dP#i#j(g~(jP#X#Y(m~(rOQ~~(wOW~~(|OV~',
  tokenizers: [TokenizerSpec.group(0)],
  topRules: {'JsonText': (0, 1)},
  dialects: {},
  dynamicPrecedences: {},
  specialized: [
    
  ],
  tokenPrec: 0,
  rules: {
    2: [StyleRule('codeLiteral', 2)],
    3: [StyleRule('codeLiteral', 2)],
    4: [StyleRule('codeLiteral', 2)],
    5: [StyleRule('codeLiteral', 2)],
    6: [StyleRule('codeString', 2)],
    7: [StyleRule('codePunctuation', 2)],
    8: [StyleRule('codePunctuation', 2)],
    11: [StyleRule('codeProperty', 2)],
    12: [StyleRule('codePunctuation', 2)],
    13: [StyleRule('codePunctuation', 2)],
    14: [StyleRule('codePunctuation', 2)],
    15: [StyleRule('codePunctuation', 2)],
  },
);
