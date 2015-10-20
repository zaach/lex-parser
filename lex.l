
NAME                                    [a-zA-Z_](?:[a-zA-Z0-9_-]*[a-zA-Z0-9_])?
BR                                      \r\n|\n|\r

%s indented trail rules
%x code start_condition options conditions action path

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
<rules>\s+{BR}+                         /* empty */
<rules>\s+                              this.begin('indented');
<rules>"%%"                             this.begin('code'); return '%%';
<rules>[a-zA-Z0-9_]+                    return 'CHARACTER_LIT';

<options>{NAME}                         yy.options[yytext] = true;
<options>{BR}+                          this.popState();
<options>\s+{BR}+                       this.popState();
<options>\s+                            /* empty */

<start_condition>{NAME}                 return 'START_COND';
<start_condition>{BR}+                  this.popState();
<start_condition>\s+{BR}+               this.popState();
<start_condition>\s+                    /* empty */

<trail>\s*{BR}+                         this.begin('rules');

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

{BR}+                                   /* empty */
\s+                                     /* empty */
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
"\\".                                   yytext = yytext.replace(/^\\/g, ''); return 'ESCAPE_CHAR';
"$"                                     return '$';
"."                                     return '.';
"%options"                              if (!yy.options) { yy.options = {}; } this.begin('options'); return false;
"%s"                                    this.begin('start_condition'); return 'START_INC';
"%x"                                    this.begin('start_condition'); return 'START_EXC';
<INITIAL,trail,code>"%include"          this.pushState('path'); return 'INCLUDE';
<INITIAL,rules,trail,code>"%"{NAME}[^\r\n]+                       
                                        %{ 
                                            /* ignore unrecognized decl */
                                            console.warn('ignoring unsupported lexer option: ', yytext, ' @ ' + JSON.stringify(yylloc) + 'while lexing in ' + this.topState() + ' state:', this._input, ' /////// ', this.matched);
                                        %}
"%%"                                    this.begin('rules'); return '%%';
"{"\d+(","\s?\d+|",")?"}"               return 'RANGE_REGEX';
"{"{NAME}"}"                            return 'NAME_BRACE';
"{"                                     return '{';
"}"                                     return '}';
.                                       throw new Error("unsupported input character: " + yytext + " @ " + JSON.stringify(yylloc)); /* b0rk on bad characters */
<*><<EOF>>                              return 'EOF';


// in the trailing CODE block, only accept these `%include` macros when they appear at the start of a line
// and make sure the rest of lexer regexes account for this one so it'll match that way only:
<code>[^\r\n]*(\r|\n)+                  return 'CODE';
<code>[^\r\n]+                          return 'CODE';      // the bit of CODE just before EOF...


<path>[\r\n]                            this.popState(); this.unput(yytext);
<path>"'"[^\r\n]+"'"                    yytext = yytext.substr(1, yyleng - 2); this.popState(); return 'PATH';
<path>\"[^\r\n]+\"                      yytext = yytext.substr(1, yyleng - 2); this.popState(); return 'PATH';
<path>\s+                               // skip whitespace in the line
<path>[^\s\r\n]+                        this.popState(); return 'PATH';

<*>.                    %{ 
                                            /* ignore unrecognized decl */
                                            console.warn('ignoring unsupported lexer input: ', yytext, ' @ ' + JSON.stringify(yylloc) + 'while lexing in ' + this.topState() + ' state:', this._input, ' /////// ', this.matched);
                                        %}

%%

