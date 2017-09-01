
%start lex

/* Jison lexer file format grammar */

%nonassoc '/' '/!'

%left '*' '+' '?' RANGE_REGEX
%left '|'
%left '('


%%

lex
    : init definitions rules_and_epilogue EOF
        {
          $$ = $rules_and_epilogue;
          $$.macros = $definitions.macros;
          $$.startConditions = $definitions.startConditions;
          $$.unknownDecls = $definitions.unknownDecls;

          // if there are any options, add them all, otherwise set options to NULL:
          // can't check for 'empty object' by `if (yy.options) ...` so we do it this way:
          for (var k in yy.options) {
            $$.options = yy.options;
            break;
          }

          if (yy.actionInclude) {
            var asrc = yy.actionInclude.join('\n\n');
            // Only a non-empty action code chunk should actually make it through:
            if (asrc.trim() !== '') {
              $$.actionInclude = asrc;
            }
          }

          delete yy.options;
          delete yy.actionInclude;
          return $$;
        }
    | init definitions error EOF
        {
            yyerror(rmCommonWS`
                Maybe you did not correctly separate the lexer sections with a '%%'
                on an otherwise empty line?
                The lexer spec file should have this structure:

                        definitions
                        %%
                        rules
                        %%                  // <-- optional!
                        extra_module_code   // <-- optional!

                  Erroneous code:
                ` + prettyPrintRange(yylexer, @error));
        }
    ;

rules_and_epilogue
    : '%%' rules '%%' extra_lexer_module_code
      {
        if ($extra_lexer_module_code && $extra_lexer_module_code.trim() !== '') {
          $$ = { rules: $rules, moduleInclude: $extra_lexer_module_code };
        } else {
          $$ = { rules: $rules };
        }
      }
    | '%%' rules
      /* Note: an empty rules set is allowed when you are setting up an `%options custom_lexer` */
      {
        $$ = { rules: $rules };
      }
    | ε
      /* Note: an empty rules set is allowed when you are setting up an `%options custom_lexer` */
      {
        $$ = { rules: [] };
      }
    ;

// because JISON doesn't support mid-rule actions,
// we set up `yy` using this empty rule at the start:
init
    : ε
        {
            yy.actionInclude = [];
            if (!yy.options) yy.options = {};
        }
    ;

definitions
    : definitions definition
        {
          $$ = $definitions;
          if ($definition != null) {
            if ('length' in $definition) {
              $$.macros[$definition[0]] = $definition[1];
            } else if ($definition.type === 'names') {
              for (var name in $definition.names) {
                $$.startConditions[name] = $definition.names[name];
              }
            } else if ($definition.type === 'unknown') {
              $$.unknownDecls.push($definition.body);
            }
          }
        }
    | ε
        {
          $$ = {
            macros: {},           // { hash table }
            startConditions: {},  // { hash table }
            unknownDecls: []      // [ array of [key,value] pairs }
          };
        }
    ;

definition
    : NAME regex
        { $$ = [$NAME, $regex]; }
    | START_INC names_inclusive
        { $$ = $names_inclusive; }
    | START_EXC names_exclusive
        { $$ = $names_exclusive; }
    | action
        { yy.actionInclude.push($action); $$ = null; }
    | options
        { $$ = null; }
    | UNKNOWN_DECL
        { $$ = {type: 'unknown', body: $1}; }
    ;

names_inclusive
    : START_COND
        { $$ = {type: 'names', names: {}}; $$.names[$START_COND] = 0; }
    | names_inclusive START_COND
        { $$ = $names_inclusive; $$.names[$START_COND] = 0; }
    ;

names_exclusive
    : START_COND
        { $$ = {type: 'names', names: {}}; $$.names[$START_COND] = 1; }
    | names_exclusive START_COND
        { $$ = $names_exclusive; $$.names[$START_COND] = 1; }
    ;

rules
    : rules rules_collective
        { $$ = $rules.concat($rules_collective); }
    | ε
        { $$ = []; }
    ;

rules_collective
    : start_conditions rule
        {
            if ($start_conditions) {
                $rule.unshift($start_conditions);
            }
            $$ = [$rule];
        }
    | start_conditions '{' rule_block '}'
        {
            if ($start_conditions) {
                $rule_block.forEach(function (d) {
                    d.unshift($start_conditions);
                });
            }
            $$ = $rule_block;
        }
    | start_conditions '{' error '}'
        {
            yyerror(rmCommonWS`
                Seems you made a mistake while specifying one of the lexer rules inside
                the start condition
                   <${$start_conditions.join(',')}> { rules... }
                block.

                  Erroneous area:
                ` + prettyPrintRange(yylexer, yylexer.mergeLocationInfo(##start_conditions, ##4), @start_conditions));
        }
    | start_conditions '{' error
        {
            yyerror(rmCommonWS`
                Seems you did not correctly bracket a lexer rules set inside
                the start condition
                  <${$start_conditions.join(',')}> { rules... }
                as a terminating curly brace '}' could not be found.

                  Erroneous area:
                ` + prettyPrintRange(yylexer, @error, @start_conditions));
        }
    ;

rule_block
    : rule_block rule
        { $$ = $rule_block; $$.push($rule); }
    | ε
        { $$ = []; }
    ;

rule
    : regex action
        {
            $$ = [$regex, $action]; 
        }
    | regex error
        {
            $$ = [$regex, $error];
            console.log('############# DUMP:', {
                yysp,
                yyrulelength,
                yyvstack,
                yystack,
                yysstack,
                error: $error,
                text: yytext
            });
            yyerror("lexer rule regex action code declaration error?\n\n  Erroneous area:\n" + prettyPrintRange(yylexer, @error, @regex));
        }
    ;

action
    : ACTION_START action_body BRACKET_MISSING
        {
            yyerror("Missing curly braces: seems you did not correctly bracket a lexer rule action block in curly braces: '{ ... }'.\n\n  Offending action body:\n" + prettyPrintRange(yylexer, @BRACKET_MISSING, @1));
        }
    | ACTION_START action_body BRACKET_SURPLUS
        {
            yyerror("Too many curly braces: seems you did not correctly bracket a lexer rule action block in curly braces: '{ ... }'.\n\n  Offending action body:\n" + prettyPrintRange(yylexer, @BRACKET_SURPLUS, @1));
        }
    | ACTION_START action_body ACTION_END 
        {
            if (0) {
                $$ = 'XXX' + $action_body + 'YYY';
            } else {
                var s = $action_body.trim();
                // remove outermost set of braces UNLESS there's 
                // a curly brace in there anywhere: in that case
                // we should leave it up to the sophisticated
                // code analyzer to simplify the code!
                //
                // This is a very rough check as it ill also look
                // inside code comments, which should not have
                // any influence.
                //
                // Nevertheless: this is a *safe* transform!
                if (s[0] === '{' && s.indexOf('}') === s.length - 1) {
                    $$ = s.substring(1, s.length - 1).trim();
                } else {
                    $$ = s;
                }
            }
        }
    ;

action_body
    : action_body ACTION
        { $$ = $action_body + '\n\n' + $ACTION + '\n\n'; }
    | action_body ACTION_BODY
        { $$ = $action_body + $ACTION_BODY; }
    | action_body ACTION_BODY_C_COMMENT
        { $$ = $action_body + $ACTION_BODY_C_COMMENT; }
    | action_body ACTION_BODY_CPP_COMMENT
        { $$ = $action_body + $ACTION_BODY_CPP_COMMENT; }
    | action_body ACTION_BODY_WHITESPACE
        { $$ = $action_body + $ACTION_BODY_WHITESPACE; }
    | action_body include_macro_code
        { $$ = $action_body + '\n\n' + $include_macro_code + '\n\n'; }
    | action_body INCLUDE_PLACEMENT_ERROR
        { 
            yyerror("" +
            "    You may place the '%include' instruction only at the start/front of" +
            "    a line. " +
"" +
            "    It's use is not permitted at this position:" +
            "" + prettyPrintRange(yylexer, @INCLUDE_PLACEMENT_ERROR, @action_body));
        }
    | action_body error
        {
            yyerror("Seems you did not correctly match curly braces '{ ... }' in a lexer rule action block.\n\n  Offending action body part:\n" + prettyPrintRange(yylexer, @error, @action_body));
        }
    | ε
        { $$ = ''; }
    ;

start_conditions
    : '<' name_list '>'
        { $$ = $name_list; }
    | '<' name_list error
        {
            yyerror("Seems you did not correctly terminate the start condition set <" + $name_list.join(',') + ",???> with a terminating '>'\n\n  Erroneous area:\n" + prettyPrintRange(yylexer, @error, @1));
        }
    | '<' '*' '>'
        { $$ = ['*']; }
    | ε
    ;

name_list
    : NAME
        { $$ = [$NAME]; }
    | name_list ',' NAME
        { $$ = $name_list; $$.push($NAME); }
    ;

regex
    : nonempty_regex_list[re]
        {
          // Detect if the regex ends with a pure (Unicode) word;
          // we *do* consider escaped characters which are 'alphanumeric'
          // to be equivalent to their non-escaped version, hence these are
          // all valid 'words' for the 'easy keyword rules' option:
          //
          // - hello_kitty
          // - γεια_σου_γατούλα
          // - \u03B3\u03B5\u03B9\u03B1_\u03C3\u03BF\u03C5_\u03B3\u03B1\u03C4\u03BF\u03CD\u03BB\u03B1
          //
          // http://stackoverflow.com/questions/7885096/how-do-i-decode-a-string-with-escaped-unicode#12869914
          //
          // As we only check the *tail*, we also accept these as
          // 'easy keywords':
          //
          // - %options
          // - %foo-bar
          // - +++a:b:c1
          //
          // Note the dash in that last example: there the code will consider
          // `bar` to be the keyword, which is fine with us as we're only
          // interested in the trailing boundary and patching that one for
          // the `easy_keyword_rules` option.
          $$ = $re;
          if (yy.options.easy_keyword_rules) {
            // We need to 'protect' `eval` here as keywords are allowed
            // to contain double-quotes and other leading cruft.
            // `eval` *does* gobble some escapes (such as `\b`) but
            // we protect against that through a simple replace regex:
            // we're not interested in the special escapes' exact value
            // anyway.
            // It will also catch escaped escapes (`\\`), which are not
            // word characters either, so no need to worry about
            // `eval(str)` 'correctly' converting convoluted constructs
            // like '\\\\\\\\\\b' in here.
            $$ = $$
            .replace(/\\\\/g, '.')
            .replace(/"/g, '.')
            .replace(/\\c[A-Z]/g, '.')
            .replace(/\\[^xu0-9]/g, '.');

            try {
              // Convert Unicode escapes and other escapes to their literal characters
              // BEFORE we go and check whether this item is subject to the
              // `easy_keyword_rules` option.
              $$ = eval('"' + $$ + '"');
            }
            catch (ex) {
              this.warn('easy-keyword-rule FAIL on eval: ', ex);

              // make the next keyword test fail:
              $$ = '.';
            }
            // a 'keyword' starts with an alphanumeric character,
            // followed by zero or more alphanumerics or digits:
            var re = new XRegExp('\\w[\\w\\d]*$');
            if (XRegExp.match($$, re)) {
              $$ = $re + "\\b";
            } else {
              $$ = $re;
            }
          }
        }
    ;

regex_list
    : regex_list '|' regex_concat 
        { $$ = $1 + '|' + $3; }
    | regex_list '|' 
        { $$ = $1 + '|'; }
    | regex_concat
        { $$ = $1; }
    | ε
        { $$ = ''; }
    ;

nonempty_regex_list
    : nonempty_regex_list '|' regex_concat 
        { $$ = $1 + '|' + $3; }
    | nonempty_regex_list '|'  
        { $$ = $1 + '|'; }
    | '|' regex_concat 
        { $$ = '|' + $2; }
    | regex_concat
        { $$ = $1; }
    ;

regex_concat
    : regex_concat regex_base
        { $$ = $1 + $2; }
    | regex_base
        { $$ = $1; }
    ;

regex_base
    : '(' regex_list ')'
        { $$ = '(' + $regex_list + ')'; }
    | SPECIAL_GROUP regex_list ')'
        { $$ = $SPECIAL_GROUP + $regex_list + ')'; }
    | '(' regex_list error
        {
            yyerror("Seems you did not correctly bracket a lex rule regex part in '(...)' braces.\n\n  Unterminated regex part:\n" + prettyPrintRange(yylexer, @error, @1));
        }
    | SPECIAL_GROUP regex_list error
        {
            yyerror("Seems you did not correctly bracket a lex rule regex part in '(...)' braces.\n\n  Unterminated regex part:\n" + prettyPrintRange(yylexer, @error, @SPECIAL_GROUP));
        }
    | regex_base '+'
        { $$ = $regex_base + '+'; }
    | regex_base '*'
        { $$ = $regex_base + '*'; }
    | regex_base '?'
        { $$ = $regex_base + '?'; }
    | '/' regex_base
        { $$ = '(?=' + $regex_base + ')'; }
    | '/!' regex_base
        { $$ = '(?!' + $regex_base + ')'; }
    | name_expansion
    | regex_base range_regex
        { $$ = $1 + $2; }
    | any_group_regex
    | '.'
        { $$ = '.'; }
    | '^'
        { $$ = '^'; }
    | '$'
        { $$ = '$'; }
    | string
    | escape_char
    ;

name_expansion
    : NAME_BRACE
    ;

any_group_regex
    : REGEX_SET_START regex_set REGEX_SET_END
        { $$ = $REGEX_SET_START + $regex_set + $REGEX_SET_END; }
    | REGEX_SET_START regex_set error
        {
            yyerror("Seems you did not correctly bracket a lex rule regex set in '[...]' brackets.\n\n  Unterminated regex set:\n" + prettyPrintRange(yylexer, @error, @REGEX_SET_START));
        }
    ;

regex_set
    : regex_set regex_set_atom
        { $$ = $regex_set + $regex_set_atom; }
    | regex_set_atom
    ;

regex_set_atom
    : REGEX_SET
    | name_expansion
        {
            if (XRegExp._getUnicodeProperty($name_expansion.replace(/[{}]/g, ''))
                && $name_expansion.toUpperCase() !== $name_expansion
            ) {
                // treat this as part of an XRegExp `\p{...}` Unicode 'General Category' Property cf. http://unicode.org/reports/tr18/#Categories
                $$ = $name_expansion;
            } else {
                $$ = $name_expansion;
            }
            //this.log("name expansion for: ", { name: $name_expansion, redux: $name_expansion.replace(/[{}]/g, ''), output: $$ });
        }
    ;

escape_char
    : ESCAPE_CHAR
        { $$ = $ESCAPE_CHAR; }
    ;

range_regex
    : RANGE_REGEX
        { $$ = $RANGE_REGEX; }
    ;

string
    : STRING_LIT
        { $$ = prepareString($STRING_LIT); }
    | CHARACTER_LIT
    ;

options
    : OPTIONS option_list OPTIONS_END
        { $$ = null; }
    ;

option_list
    : option option_list
        { $$ = null; }
    | option
        { $$ = null; }
    ;

option
    : NAME[option]
        { yy.options[$option] = true; }
    | NAME[option] '=' OPTION_STRING_VALUE[value]
        { yy.options[$option] = $value; }
    | NAME[option] '=' OPTION_VALUE[value]
        { yy.options[$option] = parseValue($value); }
    | NAME[option] '=' NAME[value]
        { yy.options[$option] = parseValue($value); }
    | NAME[option] '=' error
        {
            // TODO ...
            yyerror(rmCommonWS`
                internal error: option "${$option}" value assignment failure.

                  Erroneous area:
                ` + prettyPrintRange(yylexer, @error, @option));
        }
    | error
        {
            // TODO ...
            yyerror(rmCommonWS`
                expected a valid option name (with optional value assignment).

                  Erroneous area:
                ` + prettyPrintRange(yylexer, @error));
        }
    ;

extra_lexer_module_code
    : optional_module_code_chunk
        { $$ = $optional_module_code_chunk; }
    | extra_lexer_module_code include_macro_code optional_module_code_chunk
        { $$ = $extra_lexer_module_code + $include_macro_code + $optional_module_code_chunk; }
    ;

include_macro_code
    : INCLUDE PATH
        {
            var fs = require('fs');
            var fileContent = fs.readFileSync($PATH, { encoding: 'utf-8' });
            // And no, we don't support nested '%include':
            $$ = '\n// Included by Jison: ' + $PATH + ':\n\n' + fileContent + '\n\n// End Of Include by Jison: ' + $PATH + '\n\n';
        }
    | INCLUDE error
        {
            yyerror(rmCommonWS`
                %include MUST be followed by a valid file path.

                  Erroneous path:
                ` + prettyPrintRange(yylexer, @error, @INCLUDE));
        }
    ;

module_code_chunk
    : CODE
        { $$ = $CODE; }
    | module_code_chunk CODE
        { $$ = $module_code_chunk + $CODE; }
    | error
        {
            // TODO ...
            yyerror(rmCommonWS`
                module code declaration error?

                  Erroneous area:
                ` + prettyPrintRange(yylexer, @error));
        }
    ;

optional_module_code_chunk
    : module_code_chunk
        { $$ = $module_code_chunk; }
    | ε
        { $$ = ''; }
    ;

%%

var XRegExp = require('@gerhobbelt/xregexp');       // for helping out the `%options xregexp` in the lexer

function encodeRE(s) {
    return s.replace(/([.*+?^${}()|\[\]\/\\])/g, '\\$1').replace(/\\\\u([a-fA-F0-9]{4})/g, '\\u$1');
}

function prepareString(s) {
    // unescape slashes
    s = s.replace(/\\\\/g, "\\");
    s = encodeRE(s);
    return s;
}

// convert string value to number or boolean value, when possible
// (and when this is more or less obviously the intent)
// otherwise produce the string itself as value.
function parseValue(v) {
    if (v === 'false') {
        return false;
    }
    if (v === 'true') {
        return true;
    }
    // http://stackoverflow.com/questions/175739/is-there-a-built-in-way-in-javascript-to-check-if-a-string-is-a-valid-number
    // Note that the `v` check ensures that we do not convert `undefined`, `null` and `''` (empty string!)
    if (v && !isNaN(v)) {
        var rv = +v;
        if (isFinite(rv)) {
            return rv;
        }
    }
    return v;
}

// tagged template string helper which removes the indentation common to all
// non-empty lines: that indentation was added as part of the source code
// formatting of this lexer spec file and must be removed to produce what
// we were aiming for.
//
// Each template string starts with an optional empty line, which should be
// removed entirely, followed by a first line of error reporting content text,
// which should not be indented at all, i.e. the indentation of the first
// non-empty line should be treated as the 'common' indentation and thus
// should also be removed from all subsequent lines in the same template string.
//
// See also: https://developer.mozilla.org/en/docs/Web/JavaScript/Reference/Template_literals
function rmCommonWS(strings, ...values) {
    // as `strings[]` is an array of strings, each potentially consisting
    // of multiple lines, followed by one(1) value, we have to split each
    // individual string into lines to keep that bit of information intact.
    var src = strings.map(function splitIntoLines(s) {
        return s.split('\n');
    });
    // fetch the first line of content which is expected to exhibit the common indent:
    // that would be the SECOND line of input, always, as the FIRST line won't
    // have any indentation at all!
    var s0 = '';
    for (var i = 0, len = src.length; i < len; i++) {
        if (src[i].length > 1) {
            s0 = src[i][1];
            break;
        }
    }
    var indent = s0.replace(/^(\s+)[^\s]*.*$/, '$1');
    // we assume clean code style, hence no random mix of tabs and spaces, so every
    // line MUST have the same indent style as all others, so `length` of indent
    // should suffice, but the way we coded this is stricter checking when we apply
    // a find-and-replace regex instead:
    var indent_re = new RegExp('^' + indent);

    // process template string partials now:
    for (var i = 0, len = src.length; i < len; i++) {
        // start-of-lines always end up at index 1 and above (for each template string partial):
        for (var j = 1, linecnt = src[i].length; j < linecnt; j++) {
            src[i][j] = src[i][j].replace(indent_re, '');
        }
    }

    // now merge everything to construct the template result:
    var rv = [];
    for (var i = 0, len = src.length, klen = values.length; i < len; i++) {
        rv.push(src[i].join('\n'));
        // all but the last partial are followed by a template value:
        if (i < klen) {
            rv.push(values[i]);
        }
    }
    var sv = rv.join('');
    return sv;
}

// pretty-print the erroneous section of the input, with line numbers and everything...
function prettyPrintRange(lexer, loc, context_loc, context_loc2) {
    var error_size = loc.last_line - loc.first_line;
    const CONTEXT = 3;
    const CONTEXT_TAIL = 1;
    var input = lexer.matched + lexer._input;
    var lines = input.split('\n');
    var show_context = (error_size < 5 || context_loc);
    var l0 = Math.max(1, (!show_context ? loc.first_line : context_loc ? context_loc.first_line : loc.first_line - CONTEXT));
    var l1 = Math.max(1, (!show_context ? loc.last_line : context_loc2 ? context_loc2.last_line : loc.last_line + CONTEXT_TAIL));
    var lineno_display_width = (1 + Math.log10(l1 | 1) | 0);
    var ws_prefix = new Array(lineno_display_width).join(' ');
    var rv = lines.slice(l0 - 1, l1 + 1).map(function injectLineNumber(line, index) {
        var lno = index + l0;
        var lno_pfx = (ws_prefix + lno).substr(-lineno_display_width);
        var rv = lno_pfx + ': ' + line;
        if (show_context) {
            var errpfx = (new Array(lineno_display_width + 1)).join('^');
            if (lno === loc.first_line) {
                var offset = loc.first_column + 2;
                var len = Math.max(2, (lno === loc.last_line ? loc.last_column : line.length) - loc.first_column + 1);
                var lead = (new Array(offset)).join('.');
                var mark = (new Array(len)).join('^');
                rv += '\n' + errpfx + lead + mark + offset + '/D' + len + '/' + lno + '/' + loc.last_line + '/' + loc.last_column + '/' + line.length + '/' + loc.first_column;
            } else if (lno === loc.last_line) {
                var offset = 2 + 1;
                var len = Math.max(2, loc.last_column + 1);
                var lead = (new Array(offset)).join('.');
                var mark = (new Array(len)).join('^');
                rv += '\n' + errpfx + lead + mark + offset + '/E' + len;
            } else if (lno > loc.first_line && lno < loc.last_line) {
                var offset = 2 + 1;
                var len = Math.max(2, line.length + 1);
                var lead = (new Array(offset)).join('.');
                var mark = (new Array(len)).join('^');
                rv += '\n' + errpfx + lead + mark + offset + '/F' + len;
            }
        }
        rv = rv.replace(/\t/g, ' ');
        return rv;
    });
    return rv.join('\n');
}


parser.warn = function p_warn() {
    console.warn.apply(console, arguments);
};

parser.log = function p_log() {
    console.log.apply(console, arguments);
};

parser.pre_parse = function p_lex() {
    console.log('pre_parse:', arguments);
};

parser.yy.pre_parse = function p_lex() {
    console.log('pre_parse YY:', arguments);
};

parser.yy.post_lex = function p_lex() {
    console.log('post_lex:', arguments);
};

