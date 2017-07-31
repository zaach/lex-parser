
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
            yyerror("Maybe you did not correctly separate the lexer sections with a '%%' on an otherwise empty line? The lexer spec file should have this structure:  definitions  %%  rules  [%%  extra_module_code]");
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
            var l = $action_body.split('\n');
            var ab = l.slice(0, 10).join('\n');
            yyerror("Seems you did not correctly bracket the lexer 'preparatory' action block in curly braces: '{ ... }'. Offending action body:\n" + ab);
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
    | start_conditions '{' rule_block error
        {
            if ($start_conditions) {
                $rule_block.forEach(function (d) {
                    d.unshift($start_conditions);
                });
            }
            yyerror("Seems you did not correctly bracket a lexer rule set inside the start condition <" + $start_conditions.join(',') + "> { rules... } as a terminating curly brace '}' could not be found.", $rule_block);
        }
    ;

rule_block
    : rule_block rule
        { $$ = $rules; $$.push($rule); }
    | ε
        { $$ = []; }
    ;

rule
    : regex action
        { $$ = [$regex, $action]; }
    ;

action
    : '{' action_body '}'
        { $$ = $action_body; }
    | '{' action_body error
        {
            var l = $action_body.split('\n');
            var ab = l.slice(0, 10).join('\n');
            yyerror("Seems you did not correctly bracket a lexer rule action block in curly braces: '{ ... }'. Offending action body:\n" + ab);
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
            var l = $action_body2.split('\n');
            var ab = l.slice(0, 10).join('\n');
            yyerror("Seems you did not correctly match curly braces '{ ... }' in a lexer rule action block. Offending action body part:\n" + ab);
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
            var l = $name_list;
            var ab = l.slice(0, 10).join(',').replace(/[\s\r\n]/g, ' ');
            yyerror("Seems you did not correctly terminate the start condition set <" + ab + ",???> with a terminating '>'");
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
              console.warn('easy-keyword-rule FAIL on eval: ', ex);

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
            var l = $regex_list;
            var ab = l.replace(/[\s\r\n]/g, ' ').substring(0, 32);
            yyerror("Seems you did not correctly bracket a lex rule regex part in '(...)' braces. Unterminated regex part: (" + ab, $regex_list);
        }
    | SPECIAL_GROUP regex_list error
        {
            var l = $regex_list;
            var ab = l.replace(/[\s\r\n]/g, ' ').substring(0, 32);
            yyerror("Seems you did not correctly bracket a lex rule regex part in '(...)' braces. Unterminated regex part: " + $SPECIAL_GROUP + ab, $regex_list);
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
            var l = $regex_set;
            var ab = l.replace(/[\s\r\n]/g, ' ').substring(0, 32);
            yyerror("Seems you did not correctly bracket a lex rule regex set in '[...]' brackets. Unterminated regex set: " + $REGEX_SET_START + ab, $regex_set);
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
            //console.log("name expansion for: ", { name: $name_expansion, redux: $name_expansion.replace(/[{}]/g, ''), output: $$ });
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
        { $$ = prepareString($STRING_LIT.substr(1, $STRING_LIT.length - 2)); }
    | CHARACTER_LIT
    ;

options
    : OPTIONS option_list OPTIONS_END
    ;

option_list
    : option option_list
    | option
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
            yyerror("%include MUST be followed by a valid file path");
        }
    ;

module_code_chunk
    : CODE
        { $$ = $CODE; }
    | module_code_chunk CODE
        { $$ = $module_code_chunk + $CODE; }
    ;

optional_module_code_chunk
    : module_code_chunk
        { $$ = $module_code_chunk; }
    | ε
        { $$ = ''; }
    ;

%%

var XRegExp = require('xregexp');       // for helping out the `%options xregexp` in the lexer

function encodeRE (s) {
    return s.replace(/([.*+?^${}()|\[\]\/\\])/g, '\\$1').replace(/\\\\u([a-fA-F0-9]{4})/g, '\\u$1');
}

function prepareString (s) {
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

