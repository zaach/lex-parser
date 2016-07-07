%start lex

/* Jison lexer file format grammar */

%nonassoc '/' '/!'

%left '*' '+' '?' RANGE_REGEX

%%

lex
    : init definitions '%%' rules_and_epilogue
        {
          $$ = $rules_and_epilogue;
          if ($definitions[0]) $$.macros = $definitions[0];
          if ($definitions[1]) $$.startConditions = $definitions[1];
          if ($definitions[2]) $$.unknownDecls = $definitions[2];
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
    ;

/* 
 * WARNING: when you want to refactor this rule, you'll get into a world of hurt 
 * as then the grammar won't be LALR(1) any longer! The shite start to happen
 * as soon as you take away the EOF in here and move it to the top grammar rule
 * where it really belongs. Other refactorings of this rule to reduce the code
 * duplication in these action blocks leads to the same effect, thanks to the
 * different refactored rules then fighting it out in reduce/reduce conflicts
 * thanks to the epsilon rules everywhere in there. You have been warned...
 */ 
rules_and_epilogue
    : EOF         
      /* an empty rules set is allowed when you are setting up an `%options custom_lexer` */ 
      {
        $$ = { rules: [] };
      }
    | '%%' extra_lexer_module_code EOF
      {
        if ($extra_lexer_module_code && $extra_lexer_module_code.trim() !== '') {
          $$ = { rules: [], moduleInclude: $extra_lexer_module_code };
        } else {
          $$ = { rules: [] };
        }
      }
    | rules '%%' extra_lexer_module_code EOF
      {
        if ($extra_lexer_module_code && $extra_lexer_module_code.trim() !== '') {
          $$ = { rules: $rules, moduleInclude: $extra_lexer_module_code };
        } else {
          $$ = { rules: $rules };
        }
      }
    | rules EOF
      {
        $$ = { rules: $rules };
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
              $$[0] = $$[0] || {};
              $$[0][$definition[0]] = $definition[1];
            } else if ($definition.type === 'names') {
              $$[1] = $$[1] || {};
              for (var name in $definition.names) {
                $$[1][name] = $definition.names[name];
              }
            } else if ($definition.type === 'unknown') {
              $$[2] = $$[2] || [];
              $$[2].push($definition.body);
            }
          }
        }
    | ε
        { $$ = [null, null]; }
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
    : rules rule
        { $$ = $rules; $$.push($rule); }
    | rule
        { $$ = [$rule]; }
    ;

rule
    : start_conditions regex action
        { $$ = $start_conditions ? [$start_conditions, $regex, $action] : [$regex, $action]; }
    ;

action
    : '{' action_body '}'
        { $$ = $action_body; }
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
    | '<' '*' '>'
        { $$ = ['*']; }
    |
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
            try {
              // We need to 'protect' JSON.parse here as keywords are allowed
              // to contain double-quotes and other leading cruft.
              // JSON.parse *does* gobble some escapes (such as `\b`) but
              // we protect against that through a simple replace regex: 
              // we're not interested in the special escapes' exact value 
              // anyway.
              // It will also catch escaped escapes (`\\`), which are not 
              // word characters either, so no need to worry about 
              // `JSON.parse()` 'correctly' converting convoluted constructs
              // like '\\\\\\\\\\b' in here.
              $$ = $$
              .replace(/"/g, '.' /* '\\"' */)
              .replace(/\\c[A-Z]/g, '.')
              .replace(/\\[^xu0-9]/g, '.');

              $$ = JSON.parse('"' + $$ + '"');
              // a 'keyword' starts with an alphanumeric character, 
              // followed by zero or more alphanumerics or digits:
              if ($$.match(/\w[\w\d]*$/u)) {
                $$ = $re + "\\b";
              } else {
                $$ = $re;
              }
            } catch (ex) {
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
    : regex_list '|' regex_concat
        { $$ = $1 + '|' + $3; }
    | regex_list '|'
        { $$ = $1 + '|'; }
    | BUGGER '|' nonempty_regex_list
        { $$ = '|' + $2; }
    | BUGGER '|' 
        { $$ = '|'; }
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
            if (XRegExp.isUnicodeSlug($name_expansion.replace(/[{}]/g, '')) 
                && $name_expansion.toUpperCase() !== $name_expansion
            ) {
                // treat this as part of an XRegExp `\p{...}` Unicode slug:
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
    | NAME[option] '=' OPTION_VALUE[value]
        { yy.options[$option] = $value; }
    | NAME[option] '=' NAME[value]
        { yy.options[$option] = $value; }
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
            console.error("%include MUST be followed by a valid file path");
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

var XRegExp = require('xregexp');

function encodeRE (s) {
    return s.replace(/([.*+?^${}()|\[\]\/\\])/g, '\\$1').replace(/\\\\u([a-fA-F0-9]{4})/g, '\\u$1');
}

function prepareString (s) {
    // unescape slashes
    s = s.replace(/\\\\/g, "\\");
    s = encodeRE(s);
    return s;
};
