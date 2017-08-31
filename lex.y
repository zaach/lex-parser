
%start lex

/* Jison lexer file format grammar */

%nonassoc '/' '/!'

%left '*' '+' '?' RANGE_REGEX


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
            yyerror(`Maybe you did not correctly separate the lexer sections with a '%%' on an otherwise empty line? The lexer spec file should have this structure:

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
    : definition definitions
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
    | '{' action_body '}'
        { yy.actionInclude.push($action_body); $$ = null; }
    | '{' action_body error
        {
            yyerror("Seems you did not correctly bracket the lexer preparatory action block in curly braces: '{ ... }'.\n\n  Offending action body:\n" + prettyPrintRange(yylexer, @error, @action_body));
        }
    | ACTION
        { yy.actionInclude.push($ACTION); $$ = null; }
    | include_macro_code
        { yy.actionInclude.push($include_macro_code); $$ = null; }
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
            yyerror("Seems you made a mistake while specifying one of the lexer rules inside the start condition <" + $start_conditions.join(',') + "> { rules... } block.\n\n  Erroneous area:\n" + prettyPrintRange(yylexer, yylexer.mergeLocationInfo(##start_conditions, ##4), @start_conditions));
        }
    | start_conditions '{' error
        {
            yyerror("Seems you did not correctly bracket a lexer rules set inside the start condition <" + $start_conditions.join(',') + "> { rules... } as a terminating curly brace '}' could not be found.\n\n  Erroneous area:\n" + prettyPrintRange(yylexer, @error, @start_conditions));
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
        { $$ = [$regex, $action]; }
    | regex error
        {
            $$ = [$regex, $error];
            yyerror("lexer rule regex action code declaration error?\n\n  Erroneous area:\n" + prettyPrintRange(yylexer, @error, @regex));
        }
    ;

action
    : '{' action_body '}'
        { $$ = $action_body; }
    | '{' action_body error
        {
            yyerror("Seems you did not correctly bracket a lexer rule action block in curly braces: '{ ... }'.\n\n  Offending action body:\n" + prettyPrintRange(yylexer, @error, @1));
        }
    | unbracketed_action_body
        { $$ = $unbracketed_action_body; }
    | include_macro_code
        { $$ = $include_macro_code; }
    ;

unbracketed_action_body
    : ACTION
    | unbracketed_action_body ACTION
        { $$ = $unbracketed_action_body + '\n' + $ACTION; }
    ;

action_body
    : action_comments_body
        { $$ = $action_comments_body; }
    | action_body '{' action_body '}' action_comments_body
        { $$ = $1 + $2 + $3 + $4 + $5; }
    | action_body '{' action_body error
        {
            yyerror("Seems you did not correctly match curly braces '{ ... }' in a lexer rule action block.\n\n  Offending action body part:\n" + prettyPrintRange(yylexer, @error, @action_body1));
        }
    ;

action_comments_body
    : ε
        { $$ = ''; }
    | action_comments_body ACTION_BODY
        { $$ = $action_comments_body + $ACTION_BODY; }
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
    : nonempty_regex_list
    | ε
        { $$ = ''; }
    ;

nonempty_regex_list
    : regex_concat '|' regex_list
        { $$ = $1 + '|' + $3; }
    | '|' regex_list
        { $$ = '|' + $2; }
    | regex_concat
    ;

regex_concat
    : regex_concat regex_base
        { $$ = $1 + $2; }
    | regex_base
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
    : regex_set_atom regex_set
        { $$ = $regex_set_atom + $regex_set; }
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
            yyerror(`internal error: option "${$option}" value assignment failure.

  Erroneous area:
` + prettyPrintRange(yylexer, @error, @option));
        }
    | error
        {
            // TODO ...
            yyerror("expected a valid option name (with optional value assignment).\n\n  Erroneous area:\n" + prettyPrintRange(yylexer, @error));
        }
    ;

extra_lexer_module_code
    : optional_module_code_chunk
        { $$ = $optional_module_code_chunk; }
    | optional_module_code_chunk include_macro_code extra_lexer_module_code
        { $$ = $optional_module_code_chunk + $include_macro_code + $extra_lexer_module_code; }
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
            yyerror("%include MUST be followed by a valid file path.\n\n  Erroneous path:\n" + prettyPrintRange(yylexer, @error));
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
            yyerror("module code declaration error?\n\n  Erroneous area:\n" + prettyPrintRange(yylexer, @error));
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

// pretty-print the erroneous section of the input, with line numbers and everything...
function prettyPrintRange(lexer, loc, context_loc) {
    var error_size = loc.last_line - loc.first_line;
    const CONTEXT = 3;
    var input = lexer.matched;
    var lines = input.split('\n');
    var show_context = (error_size < 5 || context_loc);
    var l0 = (!show_context ? loc.first_line : context_loc ? context_loc.first_line : loc.first_line - CONTEXT);
    var l1 = loc.last_line;
    var lineno_display_width = (1 + Math.log10(l1 | 1) | 0);
    var ws_prefix = new Array(lineno_display_width).join(' ');
    var rv = lines.slice(l0 - 1, l1 + 1).map(function injectLineNumber(line, index) {
        var lno = index + l0;
        var lno_pfx = (ws_prefix + lno).substr(-lineno_display_width);
        line = lno_pfx + ': ' + line;
        if (show_context) {
            var errpfx = (new Array(lineno_display_width + 1)).join('^');
            if (lno === loc.first_line) {
                var offset = loc.first_column + 2;
                var len = (lno === loc.last_line ? loc.last_column : line.length) - loc.first_column + 1;
                var lead = (new Array(offset)).join(' ');
                var mark = (new Array(len)).join('^');
                line += '\n' + errpfx + lead + mark;
            } else if (lno === loc.last_line) {
                var offset = 2 + 1;
                var len = loc.last_column + 1;
                var lead = (new Array(offset)).join(' ');
                var mark = (new Array(len)).join('^');
                line += '\n' + errpfx + lead + mark;
            } else if (lno > loc.first_line && lno < loc.last_line) {
                var offset = 2 + 1;
                var len = line.length + 1;
                var lead = (new Array(offset)).join(' ');
                var mark = (new Array(len)).join('^');
                line += '\n' + errpfx + lead + mark;
            }
        }
        line = line.replace(/\t/g, ' ');
        return line;
    });
    return rv.join('\n');
}


parser.warn = function p_warn() {
    console.warn.apply(console, arguments);
};

parser.log = function p_log() {
    console.log.apply(console, arguments);
};

