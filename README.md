# lex-parser

A parser for lexical grammars used by [jison](http://jison.org) and jison-lex.

## install

    npm install lex-parser

## build

To build the parser yourself, clone the git repo then run:

    make

This will generate `lex-parser.js`.

## usage

    var lexParser = require("lex-parser");

    // parse a lexical grammar and return JSON
    lexParser.parse("%% ... ");

## example

The parser can parse its own lexical grammar, shown below:

    NAME                                    [a-zA-Z_][a-zA-Z0-9_-]*
    BR                                      \r\n|\n|\r

    %s indented trail rules
    %x code start_condition options conditions action

    %%

    <action>"/*"(.|\n|\r)*?"*/"             return 'ACTION_BODY';
    <action>"//".*                          return 'ACTION_BODY';
    <action>"/"[^ /]*?['"{}'][^ ]*?"/"      return 'ACTION_BODY'; // regexp with braces or quotes (and no spaces)
    <action>\"("\\\\"|'\"'|[^"])*\"         return 'ACTION_BODY';
    <action>"'"("\\\\"|"\'"|[^'])*"'"       return 'ACTION_BODY';
    <action>[/"'][^{}/"']+                  return 'ACTION_BODY';
    <action>[^{}/"']+                       return 'ACTION_BODY';
    <action>"{"                             yy.depth++; return '{';
    <action>"}"                             if (yy.depth == 0) { this.begin('trail'); } else { yy.depth--; } return '}';

    <conditions>{NAME}                      return 'NAME';
    <conditions>">"                         this.popState(); return '>';
    <conditions>","                         return ',';
    <conditions>"*"                         return '*';

    <rules>{BR}+                            /* empty */
    <rules>\s+{BR}+                         /* empty */
    <rules>\s+                              this.begin('indented');
    <rules>"%%"                             this.begin('code'); return '%%';
    <rules>[a-zA-Z0-9_]+                    return 'CHARACTER_LIT';

    <options>{NAME}                         yy.options[yytext] = true;
    <options>{BR}+                          this.begin('INITIAL');
    <options>\s+{BR}+                       this.begin('INITIAL');
    <options>\s+                            /* empty */

    <start_condition>{NAME}                 return 'START_COND';
    <start_condition>{BR}+                  this.begin('INITIAL');
    <start_condition>\s+{BR}+               this.begin('INITIAL');
    <start_condition>\s+                    /* empty */

    <trail>\s*{BR}+                         this.begin('rules');

    <indented>"{"                           yy.depth = 0; this.begin('action'); return '{';
    <indented>"%{"(.|{BR})*?"%}"            this.begin('trail'); yytext = yytext.substr(2, yytext.length - 4); return 'ACTION';
    "%{"(.|{BR})*?"%}"                      yytext = yytext.substr(2, yytext.length - 4); return 'ACTION';
    <indented>.+                            this.begin('rules'); return 'ACTION';

    "/*"(.|\n|\r)*?"*/"                     /* empty */
    "//".*                                  /* empty */

    {BR}+                                   /* ignore */
    \s+                                     /* ignore */
    {NAME}                                  return 'NAME';
    \"("\\\\"|'\"'|[^"])*\"                 yytext = yytext.replace(/\\"/g,'"'); return 'STRING_LIT';
    "'"("\\\\"|"\'"|[^'])*"'"               yytext = yytext.replace(/\\'/g,"'"); return 'STRING_LIT';
    "|"                                     return '|';
    "["("\\\\"|"\]"|[^\]])*"]"              return 'ANY_GROUP_REGEX';
    "(?:"                                   return 'SPECIAL_GROUP';
    "(?="                                   return 'SPECIAL_GROUP';
    "(?!"                                   return 'SPECIAL_GROUP';
    "("                                     return '(';
    ")"                                     return ')';
    "+"                                     return '+';
    "*"                                     return '*';
    "?"                                     return '?';
    "^"                                     return '^';
    ","                                     return ',';
    "<<EOF>>"                               return '$';
    "<"                                     this.begin('conditions'); return '<';
    "/!"                                    return '/!';
    "/"                                     return '/';
    "\\"([0-7]{1,3}|[rfntvsSbBwWdD\\*+()${}|[\]\/.^?]|"c"[A-Z]|"x"[0-9A-F]{2}|"u"[a-fA-F0-9]{4})
                                            return 'ESCAPE_CHAR';
    "\\".                                   yytext = yytext.replace(/^\\/g,''); return 'ESCAPE_CHAR';
    "$"                                     return '$';
    "."                                     return '.';
    "%options"                              yy.options = {}; this.begin('options');
    "%s"                                    this.begin('start_condition'); return 'START_INC';
    "%x"                                    this.begin('start_condition'); return 'START_EXC';
    "%%"                                    this.begin('rules'); return '%%';
    "{"\d+(","\s?\d+|",")?"}"               return 'RANGE_REGEX';
    "{"{NAME}"}"                            return 'NAME_BRACE';
    "{"                                     return '{';
    "}"                                     return '}';
    .                                       throw new Error("unsupported input character: " + yytext); /* b0rk on bad characters */
    <*><<EOF>>                              return 'EOF';

    <code>(.|{BR})+                         return 'CODE';

    %%

## license

MIT
