# lex-parser

A parser for lexical grammars used by [jison](http://jison.org) and jison-lex.

## install

    npm install lex-parser

## build

To build the parser yourself, clone the git repo then run:

    make prep
    
to install required packages and then run:

    make
    
to run the unit tests.

This will generate `lex-parser.js`.


## usage

    var lexParser = require("lex-parser");

    // parse a lexical grammar and return JSON
    lexParser.parse("%% ... ");


## example

The parser can parse its own lexical grammar, shown below:

```

ASCII_LETTER                            [a-zA-z]
// \p{Alphabetic} already includes [a-zA-z], hence we don't need to merge with {UNICODE_LETTER}:
UNICODE_LETTER                          [\p{Alphabetic}]
ALPHA                                   [{UNICODE_LETTER}_]
DIGIT                                   [\p{Number}]
WHITESPACE                              [\s\r\n\p{Separator}]

NAME                                    [{ALPHA}](?:[{ALPHA}{DIGIT}-]*[{ALPHA}{DIGIT}])?
ID                                      [{ALPHA}][{ALPHA}{DIGIT}]*
BR                                      \r\n|\n|\r
// WhiteSpace MUST NOT match CR/LF and the regex `\s` DOES, so we cannot use that one directly. 
// Instead we define the {WS} macro here:
WS                                      [^\S\r\n]


%s indented trail rules macro
%x code start_condition options conditions action path set


// Off Topic
// ---------
//
// Do not specify the xregexp option as we want the XRegExp \p{...} regex macros converted to 
// native regexes and used as such:
//
// %options xregexp

%options easy_keyword_rules
%options ranges

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
<rules>{WS}+{BR}+                       /* empty */
<rules>\s+                              this.begin('indented');
<rules>"%%"                             this.begin('code'); return '%%';
<rules>[^\s\r\n<>\[\](){}.*+?:!=|%\/\\^$,\'\";]+
                                        %{
                                            // accept any non-regex, non-lex, non-string-delim,
                                            // non-escape-starter, non-space character as-is
                                            return 'CHARACTER_LIT';
                                        %}
<options>{NAME}                         return 'NAME';
<options>"="                            return '=';
<options>\"("\\\\"|'\"'|[^"])*\"        yytext = yytext.substr(1, yytext.length - 2); return 'OPTION_VALUE';
<options>"'"("\\\\"|"\'"|[^'])*"'"      yytext = yytext.substr(1, yytext.length - 2); return 'OPTION_VALUE';
<options>[^\s\r\n]+                     return 'OPTION_VALUE';
<options>{BR}+                          this.popState(); return 'OPTIONS_END';
<options>{WS}+                          /* skip whitespace */

<start_condition>{ID}                   return 'START_COND';
<start_condition>{BR}+                  this.popState();
<start_condition>{WS}+                  /* empty */

<trail>{WS}*{BR}+                       this.begin('rules');

<indented>"{"                           yy.depth = 0; this.begin('action'); return '{';
<indented>"%{"(.|{BR})*?"%}"            this.begin('trail'); yytext = yytext.substr(2, yytext.length - 4); return 'ACTION';
"%{"(.|{BR})*?"%}"                      yytext = yytext.substr(2, yytext.length - 4); return 'ACTION';
<indented>"%include"                    %{
                                            // This is an include instruction in place of an action:
                                            // thanks to the `<indented>.+` rule immediately below we need to semi-duplicate
                                            // the `%include` token recognition here vs. the almost-identical rule for the same
                                            // further below.
                                            // There's no real harm as we need to do something special in this case anyway:
                                            // push 2 (two!) conditions.
                                            //
                                            // (Anecdotal: to find that we needed to place this almost-copy here to make the test grammar
                                            // parse correctly took several hours as the debug facilities were - and are - too meager to
                                            // quickly diagnose the problem while we hadn't. So the code got littered with debug prints
                                            // and finally it hit me what the *F* went wrong, after which I saw I needed to add *this* rule!)

                                            // first push the 'trail' condition which will be the follow-up after we're done parsing the path parameter...
                                            this.pushState('trail');
                                            // then push the immediate need: the 'path' condition.
                                            this.pushState('path');
                                            return 'INCLUDE';
                                        %}
<indented>.+                            this.begin('rules'); return 'ACTION';

"/*"(.|\n|\r)*?"*/"                     /* ignore */
"//".*                                  /* ignore */

<INITIAL>{ID}                           this.pushState('macro'); return 'NAME';
<macro>{BR}+                            this.popState('macro');

// Accept any non-regex-special character as a direct literal without the need to put quotes around it:
<macro>[^\s\r\n<>\[\](){}.*+?:!=|%\/\\^$,'""]+
                                        %{
                                            // accept any non-regex, non-lex, non-string-delim,
                                            // non-escape-starter, non-space character as-is
                                            return 'CHARACTER_LIT';
                                        %}

{BR}+                                   /* empty */
\s+                                     /* empty */

\"("\\\\"|'\"'|[^"])*\"                 yytext = yytext.replace(/\\"/g,'"'); return 'STRING_LIT';
"'"("\\\\"|"\'"|[^'])*"'"               yytext = yytext.replace(/\\'/g,"'"); return 'STRING_LIT';
"["                                     this.pushState('set'); return 'REGEX_SET_START';
"|"                                     return '|';
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
"/!"                                    return '/!';                    // treated as `(?!atom)`
"/"                                     return '/';                     // treated as `(?=atom)`
"\\"([0-7]{1,3}|[rfntvsSbBwWdD\\*+()${}|[\]\/.^?]|"c"[A-Z]|"x"[0-9A-F]{2}|"u"[a-fA-F0-9]{4})
                                        return 'ESCAPE_CHAR';
"\\".                                   yytext = yytext.replace(/^\\/g, ''); return 'ESCAPE_CHAR';
"$"                                     return '$';
"."                                     return '.';
"%options"                              this.begin('options'); return 'OPTIONS';
"%s"                                    this.begin('start_condition'); return 'START_INC';
"%x"                                    this.begin('start_condition'); return 'START_EXC';
<INITIAL,trail,code>"%include"          this.pushState('path'); return 'INCLUDE';
<INITIAL,rules,trail,code>"%"{NAME}[^\r\n]+
                                        %{
                                            /* ignore unrecognized decl */
                                            console.warn('ignoring unsupported lexer option: ', yytext + ' while lexing in ' + this.topState() + ' state:', this._input, ' /////// ', this.matched);
                                            return 'UNKNOWN_DECL';
                                        %}
"%%"                                    this.begin('rules'); return '%%';
"{"\d+(","\s?\d+|",")?"}"               return 'RANGE_REGEX';
"{"{ID}"}"                              return 'NAME_BRACE';
<set,options>"{"{ID}"}"                 return 'NAME_BRACE';
"{"                                     return '{';
"}"                                     return '}';

.                                       throw new Error("unsupported input character: " + yytext + " @ " + JSON.stringify(yylloc)); /* b0rk on bad characters */

<*><<EOF>>                              return 'EOF';


<set>(?:"\\\\"|"\\]"|[^\]{])+           return 'REGEX_SET';
<set>"{"                                return 'REGEX_SET';
<set>"]"                                this.popState('set'); return 'REGEX_SET_END';


// in the trailing CODE block, only accept these `%include` macros when they appear at the start of a line
// and make sure the rest of lexer regexes account for this one so it'll match that way only:
<code>[^\r\n]*(\r|\n)+                  return 'CODE';
<code>[^\r\n]+                          return 'CODE';      // the bit of CODE just before EOF...


<path>{BR}                              this.popState(); this.unput(yytext);
<path>"'"[^\r\n]+"'"                    yytext = yytext.substr(1, yyleng - 2); this.popState(); return 'PATH';
<path>'"'[^\r\n]+'"'                    yytext = yytext.substr(1, yyleng - 2); this.popState(); return 'PATH';
<path>{WS}+                             // skip whitespace in the line
<path>[^\s\r\n]+                        this.popState(); return 'PATH';

<*>.                                    %{
                                            /* ignore unrecognized decl */
                                            console.warn('ignoring unsupported lexer input: ', yytext, ' @ ' + JSON.stringify(yylloc) + 'while lexing in ' + this.topState() + ' state:', this._input, ' /////// ', this.matched);
                                        %}

%%
```


## license

MIT
