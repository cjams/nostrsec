// ANTLR4 grammar for the nostr protocol
grammar nostr;

//
// EVENT parser rules
//
nostr_client_event: LEFT_BRACKET
                    '"EVENT"' COMMA
                    event_json
                    RIGHT_BRACKET;

nostr_server_event: LEFT_BRACKET
                    '"EVENT"' COMMA
                    DOUBLE_QUOTE subscription_id DOUBLE_QUOTE COMMA
                    event_json
                    RIGHT_BRACKET;

event_json: LEFT_BRACE
            id COMMA
            pubkey COMMA
            created_at COMMA
            kind COMMA
            tags COMMA
            content COMMA
            sig
            RIGHT_BRACE;

id: '"id":' hex64_string;
pubkey: '"pubkey":' hex64_string;
created_at: '"created_at":' number;
kind: '"kind":' number;
content: '"content":' utf8_string;
sig: '"sig":' hex128_string;

tags: '"tags":' tag_array;
tag_array: (LEFT_BRACKET RIGHT_BRACKET) | (LEFT_BRACKET tag (COMMA tag)* RIGHT_BRACKET);
tag: LEFT_BRACKET (e_tag | p_tag | a_tag | generic_tag) RIGHT_BRACKET;

// THOUGHT: embed existing structures into rules for generic strings to
// try and fool parsing. We want to impose structure where we can (recursive issues)
e_tag: '"e"' COMMA hex64_string (COMMA relay_url)?;
p_tag: '"p"' COMMA hex64_string (COMMA relay_url)?;
a_tag: '"a"' COMMA DOUBLE_QUOTE
                   number COLON
                   hex_chars {len($hex_chars.text) == 64}? COLON
                   utf8_chars*
                   DOUBLE_QUOTE (COMMA relay_url)?;
generic_tag: ((DOUBLE_QUOTE ascii_chars DOUBLE_QUOTE) | ascii_string)
             (COMMA (ascii_string | utf8_string))*;
relay_url: 'wss:';

// Subscription ID is non-empty and has at most 64 chars
subscription_id: ({len($text) <= 64}? utf8_chars)+;

//
// REQ parser rules
//
nostr_req: LEFT_BRACKET
           '"REQ"' COMMA
           DOUBLE_QUOTE subscription_id DOUBLE_QUOTE COMMA
           filter_json (COMMA filter_json)*
           RIGHT_BRACKET;

// Sooo for this..nip-01 says for REQ filters *emphasis mine* "..., it *can*
// have the following attributes", which to me means all 7! == 5040
// permutations are valid from a parsing perspective.
//
// Obviously writing all the permutations out as alternatives is not
// gonna happen, so instead we use actions, attributes, and semantic predicates
// to implement the permutation validation using a python set. Chapter 15
// of the Definitive ANTLR4 Reference is useful to help understand
// this strange syntax.
filter_json
locals [attr_set = set(), duplicates = False] :
LEFT_BRACE
// Match zero or one filter_attr, or...
(filter_attr? |
// ... match one filter_attr followed by one or more filter_attr's
// preceded by a comma.
// Unconditionally add the first filter_attr to the set. lhs is the label
// we assign to this filter_attr so we can reference it
// in the code enclosed in {}.
(lhs=filter_attr {$attr_set.add($lhs.text.split(':')[0])}

// Match ', filter_attr' at least once (+).
(COMMA rhs=filter_attr

// Everything in {} is python code that ANTLR places into the parser. Since this
// block is enclosed by the + operator, it gets executed on each iteration of
// the match. We check if rhs_attr is in the $attr_set already; if so, there is a
// duplicate, else we add to the set. Since the filter_attr rule only has 7
// alternatives, this limits the possible number of attrs to 7. They can
// appear in any order at most once. The zero or one case is captured in the
// first alternative above. Both alternatives as a whole give us all 7!
// permuations.
{
rhs_attr = $rhs.text.split(':')[0]
if rhs_attr in $attr_set:
    $duplicates = True
    print(f"ERROR: filter_json: duplicate attribute found: {rhs_attr}")
else:
    $attr_set.add($rhs.text.split(':')[0])
})+
// The semantic predicate in {...}? means the preceding (..)+
// matches only if ... is True (i.e. there are no duplicate attrs).
{$duplicates == False}?
))
RIGHT_BRACE;

filter_attr: ids | authors | kinds | tag_filter | since | until | limit;
ids: '"ids":' LEFT_BRACKET hex64_string (COMMA hex64_string)* RIGHT_BRACKET;
authors: '"authors":' LEFT_BRACKET hex64_string (COMMA hex64_string)* RIGHT_BRACKET;
kinds: '"kinds":' LEFT_BRACKET number (COMMA number)* RIGHT_BRACKET;
since: '"since":' number;
until: '"until":' number;
limit: '"limit":' number;

// TODO finish with more filters
tag_filter: (e_tag_filter | p_tag_filter);
e_tag_filter: '"#e":' LEFT_BRACKET hex64_string (COMMA hex64_string)* RIGHT_BRACKET;
p_tag_filter: '"#p":' LEFT_BRACKET hex64_string (COMMA hex64_string)* RIGHT_BRACKET;

//
// CLOSE parser rule
//
nostr_close: LEFT_BRACKET
             '"CLOSE"' COMMA
             DOUBLE_QUOTE subscription_id DOUBLE_QUOTE
             RIGHT_BRACKET;

//
// OK parser rule
//
nostr_ok: LEFT_BRACKET
          '"OK"' COMMA
          hex64_string COMMA
          TRUE_FALSE COMMA
          (DOUBLE_QUOTE DOUBLE_QUOTE | utf8_message)
          RIGHT_BRACKET
          {($TRUE_FALSE.text == 'true' or len($utf8_message.text) > 2)}?;

//
// EOSE parser rule
//
nostr_eose: LEFT_BRACKET
            '"EOSE"' COMMA
            DOUBLE_QUOTE subscription_id DOUBLE_QUOTE
            RIGHT_BRACKET;

//
// CLOSED parser rule
//
nostr_closed: LEFT_BRACKET
              '"CLOSED"' COMMA
              DOUBLE_QUOTE subscription_id DOUBLE_QUOTE COMMA
              utf8_message
              RIGHT_BRACKET;

//
// NOTICE parser rule
//
nostr_notice: LEFT_BRACKET
              '"NOTICE"' COMMA
              utf8_string
              RIGHT_BRACKET;

//
// Helper rules
//
number: DEC_DIGIT+ { ((not $text.startswith("0")) or len($text) == 1) }?;

hex_chars: (DEC_DIGIT | LOWER_HEX_DIGIT)+;
hex_string: DOUBLE_QUOTE hex_chars DOUBLE_QUOTE;
hex64_string: DOUBLE_QUOTE hex_chars DOUBLE_QUOTE {len($text) == 64 + 2}?;
hex128_string: DOUBLE_QUOTE hex_chars DOUBLE_QUOTE {len($text) == 128 + 2}?;

ascii_chars: LEFT_BRACKET |
             RIGHT_BRACKET |
             LEFT_BRACE |
             RIGHT_BRACE |
             COMMA |
             COLON |
             DEC_DIGIT |
             LOWER_HEX_DIGIT |
             TAG_FILTER
             TRUE_FALSE |
             ESC_CHARS |
             ASCII_NOT_ESCAPED;
ascii_string: DOUBLE_QUOTE ascii_chars* DOUBLE_QUOTE;

utf8_chars: ascii_chars | UTF8_NOT_ESCAPED;
utf8_string: DOUBLE_QUOTE utf8_chars* DOUBLE_QUOTE;


// Message format for OK and CLOSED messages has extra
// validation on top of utf8_strings.
utf8_message: utf8_string
{(
$text[1:].startswith("duplicate:") or
$text[1:].startswith("pow:") or
$text[1:].startswith("blocked:") or
$text[1:].startswith("rate-limited:") or
$text[1:].startswith("invalid:") or
$text[1:].startswith("error:")
)}?;

//
// Lexer rules
//
DOUBLE_QUOTE: '"';
LEFT_BRACKET: '[';
RIGHT_BRACKET: ']';
LEFT_BRACE: '{';
RIGHT_BRACE: '}';
COMMA: ',';
COLON: ':';
DEC_DIGIT: [0-9];
LOWER_HEX_DIGIT: DEC_DIGIT | [a-f];
TAG_FILTER: '"#' [a-zA-Z] '":';
TRUE_FALSE: 'true' | 'false';
ESC_CHARS: '\\' [btnfr"\\];
ASCII_NOT_ESCAPED:
  [\u{000000}-\u{000007}] | // escape 0x08, 0x09, 0x0a -> \b, \t, \n
  [\u{00000b}-\u{00000b}] | // escape 0x0c, 0x0d -> \f, \r
  [\u{00000e}-\u{000021}] | // escape 0x22 -> "
  [\u{000023}-\u{00005b}] | // escape 0x5c -> \
  [\u{00005d}-\u{00007f}];
UTF8_NOT_ESCAPED: ASCII_NOT_ESCAPED | [\u{000080}-\u{10ffff}];



//// Some stale example but useful to keep around as reference
//// for now

//tag_filter
//locals [valid_tags = True] :
//TAG_FILTER LEFT_BRACKET tvl+=tag_value (COMMA tvl+=tag_value)* RIGHT_BRACKET
//{
//filter = $TAG_FILTER.text[1:]
//if filter.startswith("#e") or filter.startswith("#p"):
//    for tv_ctx in $ctx.tvl:
//        if tv_ctx.utf8_string() is not None:
//            print(f"Tag value parsed as utf-8")
//            $valid_tags = False
//            break
//        else:
//            if len(tv_ctx.hex_string().getText().strip('"')) != 64:
//                $valid_tags = False
//                break
//}
//{$valid_tags}?;

//tag
//locals [valid_tag = True]:
//LEFT_BRACKET tvl+=tag_value (COMMA tvl+=tag_value)* RIGHT_BRACKET
//{
//name = None
//name_ctx = $ctx.tvl[0]
//
//if name_ctx.hex_string() is not None:
//    name = name_ctx.hex_string().getText().strip('"')
//else:
//    name = name_ctx.utf8_string().getText().strip('"')
//
//print(f"Found tag name {name}")
//
//if name == "e" or name == "p":
//    value_ctx = $ctx.tvl[1]
//    if value_ctx.hex_string() is None:
//        valid_tag = False
//    else:
//        value = value_ctx.hex_string().getText().strip('"')
//        if len(value) != 64:
//            valid_tag = False
//};
