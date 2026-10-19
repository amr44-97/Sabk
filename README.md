# Smelt, in Smelt

The Smelt compiler rewritten in Smelt, to replace the C++ one in
`../the-compiler`, which builds it until it can build itself.

It's a redesign as well as a port: the inside (tokens, the syntax tree,
the dumps) may change, while what users see stays the same: programs'
output, error messages, and the command line. `#run` keeps the bytecode VM.

Done so far: the lexer (`smelt --tokens file`) and the parser (`smelt --ast
file`).

```
make            build build/smelt with ../the-compiler/smelt (SMELT=...)
make test       the golden tests in tests/
make compare    --tokens and --ast on every .smelt file in ../the-compiler,
                against the C++ compiler's
```

## Layout

| File | What's in it |
|---|---|
| `src/main.smelt` | the command line |
| `src/source.smelt` | source files, and messages that point into them |
| `src/token.smelt` | token kinds, keywords, and their names in dumps |
| `src/lexer.smelt` | text to tokens; number values |
| `src/ast.smelt` | the syntax tree's nodes, and the `--ast` dump |
| `src/parser.smelt` | tokens to a syntax tree |

## Differences from the C++ compiler

- Tokens are views of the file's text with a line and column, and hold no
  values: `integer_value` and `float_value` read them when they're needed.
- A lexing error returns to the caller instead of exiting. A syntax error
  still stops the compiler, as before.
- A node is a token, its source text where messages quote it, and a
  tagged enum `NodeKind` whose variants name their parts (`.If{cond,
  then, else_}`), instead of one struct with `lhs`, `rhs`, `extra`, `list`
  and flags. `--ast` still prints the old layout, mapping the parts back,
  so the two parsers can be compared.
- Float constants are `f64`, not `long double`: `1e400` reads as `inf`
  (the C++ lexer kept `1e+400`). A literal out of `f64`'s range should be
  an error, once there's a parser to report it.
