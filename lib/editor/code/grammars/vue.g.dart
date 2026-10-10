// Written by tool/code_grammars.mjs from @codemirror/lang-vue 0.1.3: do not edit by hand.
//
// The grammar's tables as Lezer ships them (MIT, Marijn Haverbeke and others), and the class
// src/app/editor/glyphHighlight.ts gives each node's tags.
// ignore_for_file: lines_longer_than_80_chars, constant_identifier_names, non_constant_identifier_names
import '../lezer/lr.dart';

/// The grammar's tokens, by the names its tokenizers know them by (@codemirror/lang-vue 0.1.3. `parser.terms.js`).
abstract final class VueTerms {

}

/// @codemirror/lang-vue 0.1.3.
final LRParserSpec vueSpec = LRParserSpec(
  states: '%pOVOWOOObQPOOOpOSO\'#C_OOOO\'#Cp\'#CpQVOWOOQxQPOOO!TQQOOQ!YQPOOOOOO,58y,58yO!_OSO,58yOOOO-E6n-E6nO!dQQO\'#CqQ{QPOOO!iQPOOQ{QPOOO!qQPOOOOOO1G.e1G.eOOQO,59],59]OOQO-E6o-E6oO!yOpO\'#CiO#RO`O\'#CiQOQPOOO#ZO#tO\'#CmO#fO!bO\'#CmOOQO,59T,59TO#qOpO,59TO#vO`O,59TOOOO\'#Cr\'#CrO#{O#tO,59XOOQO,59X,59XOOOO\'#Cs\'#CsO\$WO!bO,59XOOQO1G.o1G.oOOOO-E6p-E6pOOQO1G.s1G.sOOOO-E6q-E6q',
  stateData: '\$g~OjOS~OQROUROkQO~OWTOXUOZUO`VO~OSXOTWO~OXUO[]OlZO~OY^O~O[_O~OT`O~OYaO~OmcOodO~OmfOogO~O^iOnhO~O_jOphO~ObkOqkOrmO~OcnOsnOtmO~OnpO~OppO~ObkOqkOrrO~OcnOsnOtrO~OWX`~',
  goto: '!^hPPPiPPPPPPPPPmPPPpPPsy!Q!WTROSRe]Re_QSORYSS[T^Rb[QlfRqlQogRso',
  nodeNames: '⚠ Content Text Interpolation InterpolationContent }} Entity Attribute VueAttributeName : Identifier @ Is ScriptAttributeValue AttributeScript AttributeScript AttributeName AttributeValue Entity Entity',
  maxTerm: 36,
  context: null,
  skippedNodes: [0],
  repeatNodeCount: 4,
  tokenData: '\'y~RdXY!aYZ!a]^!apq!ars!rwx!w}!O!|!O!P#t!Q![#y![!]\$s!_!`%g!b!c%l!c!}#y#R#S#y#T#j#y#j#k%q#k#o#y%W;\'S#y;\'S;:j\$m<%lO#y~!fSj~XY!aYZ!a]^!apq!a~!wOm~~!|Oo~!b#RX`!b}!O!|!Q![!|![!]!|!c!}!|#R#S!|#T#o!|%W;\'S!|;\'S;:j#n<%lO!|!b#qP;=`<%l!|~#yOl~%W\$QXY#t`!b}!O!|!Q![#y![!]!|!c!}#y#R#S#y#T#o#y%W;\'S#y;\'S;:j\$m<%lO#y%W\$pP;=`<%l#y~\$zXX~`!b}!O!|!Q![!|![!]!|!c!}!|#R#S!|#T#o!|%W;\'S!|;\'S;:j#n<%lO!|~%lO[~~%qOZ~%W%xXY#t`!b}!O&e!Q![#y![!]!|!c!}#y#R#S#y#T#o#y%W;\'S#y;\'S;:j\$m<%lO#y!b&jX`!b}!O!|!Q![!|![!]!|!c!}\'V#R#S!|#T#o\'V%W;\'S!|;\'S;:j#n<%lO!|!b\'^XW!b`!b}!O!|!Q![!|![!]!|!c!}\'V#R#S!|#T#o\'V%W;\'S!|;\'S;:j#n<%lO!|',
  tokenizers: [TokenizerSpec.group(6), TokenizerSpec.group(7), TokenizerSpec.local('b~RP#q#rU~XP#q#r[~aOT~~', 17, 4), TokenizerSpec.local('!k~RQvwX#o#p!_~^TU~Opmq!]m!^;\'Sm;\'S;=`!X<%lOm~pUOpmq!]m!]!^!S!^;\'Sm;\'S;=`!X<%lOm~!XOU~~![P;=`<%lm~!bP#o#p!e~!jOk~~', 72, 2), TokenizerSpec.local('[~RPwxU~ZOp~~', 11, 15), TokenizerSpec.local('[~RPrsU~ZOn~~', 11, 14), TokenizerSpec.local('!e~RQvwXwx!_~^Tc~Opmq!]m!^;\'Sm;\'S;=`!X<%lOm~pUOpmq!]m!]!^!S!^;\'Sm;\'S;=`!X<%lOm~!XOc~~![P;=`<%lm~!dOt~~', 66, 35), TokenizerSpec.local('!e~RQrsXvw^~^Or~~cTb~Oprq!]r!^;\'Sr;\'S;=`!^<%lOr~uUOprq!]r!]!^!X!^;\'Sr;\'S;=`!^<%lOr~!^Ob~~!aP;=`<%lr~', 66, 33)],
  topRules: {'Content': (0, 1), 'Attribute': (1, 7)},
  dialects: {},
  dynamicPrecedences: {},
  specialized: [
    
  ],
  tokenPrec: 157,
  rules: {
    2: [StyleRule('', 2)],
    5: [StyleRule('codePunctuation', 2)],
    6: [StyleRule('codeString', 2)],
    8: [StyleRule('codeKeyword', 2)],
    9: [StyleRule('codePunctuation', 2)],
    10: [StyleRule('', 2)],
    11: [StyleRule('codePunctuation', 2)],
    12: [StyleRule('codePunctuation', 2)],
    13: [StyleRule('codeProperty', 2)],
    16: [StyleRule('codeProperty', 2)],
    17: [StyleRule('codeProperty', 2)],
    18: [StyleRule('codeString', 2)],
    19: [StyleRule('codeString', 2)],
  },
);
