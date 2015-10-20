%start lex

/* Jison lexer file format grammar */

%nonassoc '/' '/!'

%left '*' '+' '?' RANGE_REGEX

%%

lex
    : definitions '%%' rules epilogue
        {
          $$ = { rules: $rules };
          if ($definitions[0]) $$.macros = $definitions[0];
          if ($definitions[1]) $$.startConditions = $definitions[1];
          if ($epilogue && $epilogue.trim() !== '') $$.moduleInclude = $epilogue;
          if (yy.options) $$.options = yy.options;
          if (yy.actionInclude) $$.actionInclude = yy.actionInclude;
          delete yy.options;
          delete yy.actionInclude;
          return $$;
        }
    ;

epilogue
    : EOF
      { $$ = null; }
    | '%%' extra_lexer_module_code EOF
      { $$ = $extra_lexer_module_code; }
    ;

definitions
    : definition definitions
        {
          $$ = $definitions;
          if ('length' in $definition) {
            $$[0] = $$[0] || {};
            $$[0][$definition[0]] = $definition[1];
          } else {
            $$[1] = $$[1] || {};
            for (var name in $definition) {
              $$[1][name] = $definition[name];
            }
          }
        }
    | ACTION definitions
        { yy.actionInclude += $ACTION; $$ = $definitions; }
    | include_macro_code definitions
        { yy.actionInclude += $include_macro_code; $$ = $definitions; }
    |
        { yy.actionInclude = ''; $$ = [null, null]; }
    ;

definition
    : NAME regex
        { $$ = [$NAME, $regex]; }
    | START_INC names_inclusive
        { $$ = $names_inclusive; }
    | START_EXC names_exclusive
        { $$ = $names_exclusive; }
    ;

names_inclusive
    : START_COND
        { $$ = {}; $$[$START_COND] = 0; }
    | names_inclusive START_COND
        { $$ = $names_inclusive; $$[$START_COND] = 0; }
    ;

names_exclusive
    : START_COND
        { $$ = {}; $$[$START_COND] = 1; }
    | names_exclusive START_COND
        { $$ = $names_exclusive; $$[$START_COND] = 1; }
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
    | ACTION
        { $$ = $ACTION; }
    | include_macro_code
        { $$ = $include_macro_code; }
    ;

action_body
    :
        { $$ = ''; }
    | action_comments_body
        { $$ = $action_comments_body; }
    | action_body '{' action_body '}' action_comments_body
        { $$ = $1 + $2 + $3 + $4 + $5; }
    | action_body '{' action_body '}'
        { $$ = $1 + $2 + $3 + $4; }
    ;

action_comments_body
    : ACTION_BODY
        { $$ = $ACTION_BODY; }
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
    : regex_list
        {
          $$ = $regex_list;
          if (yy.options && yy.options.easy_keyword_rules && $$.match(/[\w\d]$/) && !$$.match(/\\(r|f|n|t|v|s|b|c[A-Z]|x[0-9A-F]{2}|u[a-fA-F0-9]{4}|[0-7]{1,3})$/)) {
              $$ += "\\b";
          }
        }
    ;

regex_list
    : regex_list '|' regex_concat
        { $$ = $1 + '|' + $3; }
    | regex_list '|'
        { $$ = $1 + '|'; }
    | regex_concat
    |
        { $$ = ''; }
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
    : ANY_GROUP_REGEX
        { $$ = $ANY_GROUP_REGEX; }
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
    | /* nil */
        { $$ = ''; }
    ;

%%

function encodeRE (s) {
    return s.replace(/([.*+?^${}()|[\]\/\\])/g, '\\$1').replace(/\\\\u([a-fA-F0-9]{4})/g, '\\u$1');
}

function prepareString (s) {
    // unescape slashes
    s = s.replace(/\\\\/g, "\\");
    s = encodeRE(s);
    return s;
};

