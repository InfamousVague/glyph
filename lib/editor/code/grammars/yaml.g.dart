// Written by tool/code_grammars.mjs from @lezer/yaml 1.0.4: do not edit by hand.
//
// The grammar's tables as Lezer ships them (MIT, Marijn Haverbeke and others), and the class
// src/app/editor/glyphHighlight.ts gives each node's tags.
// ignore_for_file: lines_longer_than_80_chars, constant_identifier_names, non_constant_identifier_names
import '../lezer/lr.dart';

/// The grammar's tokens, by the names its tokenizers know them by (@lezer/yaml 1.0.4. `parser.terms.js`).
abstract final class YamlTerms {
  static const int blockEnd = 63;
  static const int eof = 64;
  static const int DirectiveEnd = 1;
  static const int DocEnd = 2;
  static const int sequenceStartMark = 3;
  static const int sequenceContinueMark = 4;
  static const int explicitMapStartMark = 5;
  static const int explicitMapContinueMark = 6;
  static const int flowMapMark = 7;
  static const int mapStartMark = 65;
  static const int mapContinueMark = 66;
  static const int Literal = 8;
  static const int QuotedLiteral = 9;
  static const int Anchor = 10;
  static const int Alias = 11;
  static const int Tag = 12;
  static const int BlockLiteralContent = 13;
  static const int BracketL = 19;
  static const int FlowSequence = 20;
  static const int Colon = 29;
  static const int BraceL = 33;
  static const int FlowMapping = 34;
  static const int BlockLiteralHeader = 47;
}

/// @lezer/yaml 1.0.4.
final LRParserSpec yamlSpec = LRParserSpec(
  states: '5lQ!ZQgOOO#PQfO\'#CpO#uQfO\'#DOOOQR\'#Dv\'#DvO\$qQgO\'#DRO%gQdO\'#DUO%nQgO\'#DUO&ROaO\'#D[OOQR\'#Du\'#DuO&{QgO\'#D^O\'rQgO\'#D`OOQR\'#Dt\'#DtO(iOqO\'#DbOOQP\'#Dj\'#DjO(zQaO\'#CmO)YQgO\'#CmOOQP\'#Cm\'#CmQ)jQaOOQ)uQgOOQ]QgOOO*PQdO\'#CrO*nQdO\'#CtOOQO\'#Dw\'#DwO+]Q`O\'#CxO+hQdO\'#CwO+rQ`O\'#CwOOQO\'#Cv\'#CvO+wQdO\'#CvOOQO\'#Cq\'#CqO,UQ`O,59[O,^QfO,59[OOQR,59[,59[OOQO\'#Cx\'#CxO,eQ`O\'#DPO,pQdO\'#DPOOQO\'#Dx\'#DxO,zQdO\'#DxO-XQ`O,59jO-aQfO,59jOOQR,59j,59jOOQR\'#DS\'#DSO-hQcO,59mO-sQgO\'#DVO.TQ`O\'#DVO.YQcO,59pOOQR\'#DX\'#DXO#|QfO\'#DWO.hQcO\'#DWOOQR,59v,59vO.yOWO,59vO/OOaO,59vO/WOaO,59vO/cQgO\'#D_OOQR,59x,59xO0VQgO\'#DaOOQR,59z,59zOOQP,59|,59|O0yOaO,59|O1ROaO,59|O1aOqO,59|OOQP-E7h-E7hO1oQgO,59XOOQP,59X,59XO2PQaO\'#DeO2_QgO\'#DeO2oQgO\'#DkOOQP\'#Dk\'#DkQ)jQaOOO3PQdO\'#CsOOQO,59^,59^O3kQdO\'#CuOOQO,59`,59`OOQO,59c,59cO4VQdO,59cO4aQdO\'#CzO4kQ`O\'#CzOOQO,59b,59bOOQU,5:Q,5:QOOQR1G.v1G.vO4pQ`O1G.vOOQU-E7d-E7dO4xQdO,59kOOQO,59k,59kO5SQdO\'#DQO5^Q`O\'#DQOOQO,5:d,5:dOOQU,5:R,5:ROOQR1G/U1G/UO5cQ`O1G/UOOQU-E7e-E7eO5kQgO\'#DhO5xQcO1G/XOOQR1G/X1G/XOOQR,59q,59qO6TQgO,59qO6eQdO\'#DiO6lQgO\'#DiO7PQcO1G/[OOQR1G/[1G/[OOQR,59r,59rO#|QfO,59rOOQR1G/b1G/bO7_OWO1G/bO7dOaO1G/bOOQR,59y,59yOOQR,59{,59{OOQP1G/h1G/hO7lOaO1G/hO7tOaO1G/hO8POaO1G/hOOQP1G.s1G.sO8_QgO,5:POOQP,5:P,5:POOQP,5:V,5:VOOQP-E7i-E7iOOQO,59_,59_OOQO,59a,59aOOQO1G.}1G.}OOQO,59f,59fO8oQdO,59fOOQR7+\$b7+\$bP,XQ`O\'#DfOOQO1G/V1G/VOOQO,59l,59lO8yQdO,59lOOQR7+\$p7+\$pP9TQ`O\'#DgOOQR\'#DT\'#DTOOQR,5:S,5:SOOQR-E7f-E7fOOQR7+\$s7+\$sOOQR1G/]1G/]O9YQgO\'#DYO9jQ`O\'#DYOOQR,5:T,5:TO#|QfO\'#DZO9oQcO\'#DZOOQR-E7g-E7gOOQR7+\$v7+\$vOOQR1G/^1G/^OOQR7+\$|7+\$|O:QOWO7+\$|OOQP7+%S7+%SO:VOaO7+%SO:_OaO7+%SOOQP1G/k1G/kOOQO1G/Q1G/QOOQO1G/W1G/WOOQR,59t,59tO:jQgO,59tOOQR,59u,59uO#|QfO,59uOOQR<<Hh<<HhOOQP<<Hn<<HnO:zOaO<<HnOOQR1G/`1G/`OOQR1G/a1G/aOOQPAN>YAN>Y',
  stateData: ';S~O!fOS!gOS^OS~OP_OQbORSOTUOWROXROYYOZZO[XOcPOqQO!PVO!V[O!cTO~O`cO~P]OVkOWROXROYeOZfO[dOcPOmhOqQO~OboO~P!bOVtOWROXROYeOZfO[dOcPOmrOqQO~OpwO~P#WORSOTUOWROXROYYOZZO[XOcPOqQO!PVO!cTO~OSvP!avP!bvP~P#|OWROXROYeOZfO[dOcPOqQO~OmzO~P%OOm!OOUzP!azP!bzP!dzP~P#|O^!SO!b!QO!f!TO!g!RO~ORSOTUOWROXROcPOqQO!PVO!cTO~OY!UOP!QXQ!QX!V!QX!`!QXS!QX!a!QX!b!QXU!QXm!QX!d!QX~P&aO[!WOP!SXQ!SX!V!SX!`!SXS!SX!a!SX!b!SXU!SXm!SX!d!SX~P&aO^!ZO!W![O!b!YO!f!]O!g!YO~OP!_O!V[OQaX!`aX~OPaXQaX!VaX!`aX~P#|OP!bOQ!cO!V[O~OP_O!V[O~P#|OWROXROY!fOcPOqQObfXmfXofXpfX~OWROXRO[!hOcPOqQObhXmhXohXphX~ObeXmlXoeX~ObkXokX~P%OOm!kO~Om!lObnPonP~P%OOb!pOo!oO~Ob!pO~P!bOm!sOosXpsX~OosXpsX~P%OOm!uOotPptP~P%OOo!xOp!yO~Op!yO~P#WOS!|O!a#OO!b#OO~OUyX!ayX!byX!dyX~P#|Om#QO~OU#SO!a#UO!b#UO!d#RO~Om#WOUzX!azX!bzX!dzX~O]#XO~O!b#XO!g#YO~O^#ZO!b#XO!g#YO~OP!RXQ!RX!V!RX!`!RXS!RX!a!RX!b!RXU!RXm!RX!d!RX~P&aOP!TXQ!TX!V!TX!`!TXS!TX!a!TX!b!TXU!TXm!TX!d!TX~P&aO!b#^O!g#^O~O^#_O!b#^O!f#`O!g#^O~O^#_O!W#aO!b#^O!g#^O~OPaaQaa!Vaa!`aa~P#|OP#cO!V[OQ!XX!`!XX~OP!XXQ!XX!V!XX!`!XX~P#|OP_O!V[OQ!_X!`!_X~P#|OWROXROcPOqQObgXmgXogXpgX~OWROXROcPOqQObiXmiXoiXpiX~Obkaoka~P%OObnXonX~P%OOm#kO~Ob#lOo!oO~Oosapsa~P%OOotXptX~P%OOm#pO~Oo!xOp#qO~OSwP!awP!bwP~P#|OS!|O!a#vO!b#vO~OUya!aya!bya!dya~P#|Om#xO~P%OOm#{OU}P!a}P!b}P!d}P~P#|OU#SO!a\$OO!b\$OO!d#RO~O]\$QO~O!b\$QO!g\$RO~O!b\$SO!g\$SO~O^\$TO!b\$SO!g\$SO~O^\$TO!b\$SO!f\$UO!g\$SO~OP!XaQ!Xa!V!Xa!`!Xa~P#|Obnaona~P%OOotapta~P%OOo!xO~OU|X!a|X!b|X!d|X~P#|Om\$ZO~Om\$]OU}X!a}X!b}X!d}X~O]\$^O~O!b\$_O!g\$_O~O^\$`O!b\$_O!g\$_O~OU|a!a|a!b|a!d|a~P#|O!b\$cO!g\$cO~O',
  goto: ',]!mPPPPPPPPPPPPPPPPP!nPP!v#v#|\$`#|\$c\$f\$j\$nP%VPPP!v%Y%^%a%{&O%a&R&U&X&_&b%aP&e&{&e\'O\'RPP\']\'a\'g\'m\'s\'y(XPPPPPPPP(_)e*X+c,VUaObcR#e!c!{ROPQSTUXY_bcdehknrtvz!O!U!W!_!b!c!f!h!k!l!s!u!|#Q#R#S#W#c#k#p#x#{\$Z\$]QmPR!qnqfPQThknrtv!k!l!s!u#R#k#pR!gdR!ieTlPnTjPnSiPnSqQvQ{TQ!mkQ!trQ!vtR#y#RR!nkTsQvR!wt!RWOSUXY_bcz!O!U!W!_!b!c!|#Q#S#W#c#x#{\$Z\$]RySR#t!|R|TR|UQ!PUR#|#SR#z#RR#z#SyZOSU_bcz!O!_!b!c!|#Q#S#W#c#x#{\$Z\$]R!VXR!XYa]O^abc!a!c!eT!da!eQnPR!rnQvQR!{vQ!}yR#u!}Q#T|R#}#TW^Obc!cS!^^!aT!aa!eQ!eaR#f!eW`Obc!cQxSS}U#SQ!`_Q#PzQ#V!OQ#b!_Q#d!bQ#s!|Q#w#QQ\$P#WQ\$V#cQ\$Y#xQ\$[#{Q\$a\$ZR\$b\$]xZOSU_bcz!O!_!b!c!|#Q#S#W#c#x#{\$Z\$]Q!VXQ!XYQ#[!UR#]!W!QWOSUXY_bcz!O!U!W!_!b!c!|#Q#S#W#c#x#{\$Z\$]pfPQThknrtv!k!l!s!u#R#k#pQ!gdQ!ieQ#g!fR#h!hSgPn^pQTkrtv#RQ!jhQ#i!kQ#j!lQ#n!sQ#o!uQ\$W#kR\$X#pQuQR!zv',
  nodeNames: '⚠ DirectiveEnd DocEnd - - ? ? ? Literal QuotedLiteral Anchor Alias Tag BlockLiteralContent Comment Stream BOM Document ] [ FlowSequence Item Tagged Anchored Anchored Tagged FlowMapping Pair Key : Pair , } { FlowMapping Pair Pair BlockSequence Item Item BlockMapping Pair Pair Key Pair Pair BlockLiteral BlockLiteralHeader Tagged Anchored Anchored Tagged Directive DirectiveName DirectiveContent Document',
  maxTerm: 74,
  context: 'indentation',
  skippedNodes: [0],
  repeatNodeCount: 6,
  tokenData: '-Y~RnOX#PXY\$QYZ\$]Z]#P]^\$]^p#Ppq\$Qqs#Pst\$btu#Puv\$yv|#P|}&e}![#P![!]\'O!]!`#P!`!a\'i!a!}#P!}#O*g#O#P#P#P#Q+Q#Q#o#P#o#p+k#p#q\'i#q#r,U#r;\'S#P;\'S;=`#z<%l?HT#P?HT?HU,o?HUO#PQ#UU!WQOY#PZp#Ppq#hq;\'S#P;\'S;=`#z<%lO#PQ#kTOY#PZs#Pt;\'S#P;\'S;=`#z<%lO#PQ#}P;=`<%l#P~\$VQ!f~XY\$Qpq\$Q~\$bO!g~~\$gS^~OY\$bZ;\'S\$b;\'S;=`\$s<%lO\$b~\$vP;=`<%l\$bR%OX!WQOX%kXY#PZ]%k]^#P^p%kpq#hq;\'S%k;\'S;=`&_<%lO%kR%rX!WQ!VPOX%kXY#PZ]%k]^#P^p%kpq#hq;\'S%k;\'S;=`&_<%lO%kR&bP;=`<%l%kR&lUoP!WQOY#PZp#Ppq#hq;\'S#P;\'S;=`#z<%lO#PR\'VUmP!WQOY#PZp#Ppq#hq;\'S#P;\'S;=`#z<%lO#PR\'p[!PP!WQOY#PZp#Ppq#hq{#P{|(f|}#P}!O(f!O!R#P!R![)p![;\'S#P;\'S;=`#z<%lO#PR(mW!PP!WQOY#PZp#Ppq#hq!R#P!R![)V![;\'S#P;\'S;=`#z<%lO#PR)^U!PP!WQOY#PZp#Ppq#hq;\'S#P;\'S;=`#z<%lO#PR)wY!PP!WQOY#PZp#Ppq#hq{#P{|)V|}#P}!O)V!O;\'S#P;\'S;=`#z<%lO#PR*nUcP!WQOY#PZp#Ppq#hq;\'S#P;\'S;=`#z<%lO#PR+XUbP!WQOY#PZp#Ppq#hq;\'S#P;\'S;=`#z<%lO#PR+rUqP!WQOY#PZp#Ppq#hq;\'S#P;\'S;=`#z<%lO#PR,]UpP!WQOY#PZp#Ppq#hq;\'S#P;\'S;=`#z<%lO#PR,vU`P!WQOY#PZp#Ppq#hq;\'S#P;\'S;=`#z<%lO#P',
  tokenizers: [TokenizerSpec.external('newlines'), TokenizerSpec.external('blockMark'), TokenizerSpec.external('literals'), TokenizerSpec.external('blockLiteral'), TokenizerSpec.group(0), TokenizerSpec.group(1)],
  topRules: {'Stream': (0, 15)},
  dialects: {},
  dynamicPrecedences: {},
  specialized: [
    
  ],
  tokenPrec: 0,
  rules: {
    1: [StyleRule('codeMeta', 2)],
    2: [StyleRule('codeMeta', 2)],
    3: [StyleRule('codePunctuation', 2)],
    4: [StyleRule('codePunctuation', 2)],
    5: [StyleRule('codePunctuation', 2)],
    6: [StyleRule('codePunctuation', 2)],
    7: [StyleRule('codePunctuation', 2)],
    8: [StyleRule('codeProperty', 2, ['Key']), StyleRule('', 2)],
    9: [StyleRule('codeProperty', 2, ['Key']), StyleRule('codeString', 2)],
    10: [StyleRule('codeInfo', 2)],
    11: [StyleRule('codeInfo', 2)],
    12: [StyleRule('codeType', 2)],
    13: [StyleRule('', 2)],
    14: [StyleRule('codeComment', 2)],
    18: [StyleRule('codePunctuation', 2)],
    19: [StyleRule('codePunctuation', 2)],
    29: [StyleRule('codePunctuation', 2)],
    31: [StyleRule('codePunctuation', 2)],
    32: [StyleRule('codePunctuation', 2)],
    33: [StyleRule('codePunctuation', 2)],
    47: [StyleRule('codeString', 2)],
    53: [StyleRule('codeKeyword', 2)],
    54: [StyleRule('codeProperty', 2)],
  },
);
