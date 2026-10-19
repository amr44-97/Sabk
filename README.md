# Smelt, in Smelt

The Smelt compiler rewritten in Smelt, to replace the C++ one in
`../the-compiler`, which builds it until it can build itself.

It's a redesign as well as a port: the inside (tokens, the syntax tree,
the dumps) may change, while what users see stays the same: programs'
output, error messages, and the command line. `#run` keeps the bytecode VM.

Done so far: the lexer (`smelt --tokens file`), the parser (`smelt --ast
file`), the resolver (`smelt --resolve file`), which loads the imports,
links names to their declarations and expands macros, and the type checker
(`smelt --types file`), with its escaping-memory errors and memory-trap
warnings, and the VM that runs `#run` code while compiling. What's left is
the C backend and the driver around it.
`std` is a link to `../the-compiler/std` for now.

```
make            build build/smelt with ../the-compiler/smelt (SMELT=...)
make test       the golden tests in tests/
make compare    --tokens, --ast, --resolve and --types on every .smelt
                file in ../the-compiler, against the C++ compiler's
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
| `src/module.smelt` | modules, and the prelude (`src/prelude.smelt`, baked in by `#run`) |
| `src/resolve.smelt` | loading imports, linking names, expanding macros |
| `src/const.smelt` | compile-time values: 128-bit integers, floats, bools |
| `src/types.smelt` | types, interned |
| `src/check.smelt` | the type checker: declarations, types, layout, reporting |
| `src/statements.smelt` | statements, and several results |
| `src/patterns.smelt` | patterns, `switch`, `is`, and which values cases cover |
| `src/expressions.smelt` | conversions and expressions |
| `src/generics.smelt` | instances, indexing, literals, casts |
| `src/comptime.smelt` | `#run`, `#insert` and `#if` conditions, type info, defaults |
| `src/formats.smelt` | checking `#format` calls |
| `src/memory.smelt` | memory that escapes a function, and the memory traps |
| `src/lower.smelt` | checked code to the VM's bytecode |
| `src/vm.smelt` | the VM: running bytecode, calling C, baking `#run` results |
| `src/vm_ffi.c` | libffi and dlsym, whose types differ between platforms |

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
- Copying and walking a tree go through `NodeKind`'s type information (a
  variant's `*Node` and `[]*Node` parts are its children), so a new kind
  of node needs no code there.
- A macro's labels get its color like its names do: the C++ resolver left
  them uncolored, so a macro's `outer:` clashed with its caller's
  (tests/resolve/macro_labels.smelt).
- Constants are 128-bit (`I128`, two 64-bit halves) where the C++ used
  `__int128`.
- A tagged enum's value made by the checker is a `VariantValue` node.
- The VM's failures aren't exceptions: the first one is kept in the `Vm`,
  and every step returns false up to `vm_evaluate`, which reports it.
  Lowering stops emitting once it has failed.
- `make compare` matches the C++ compiler on every file, in all four
  modes. tests/errors holds the C++ error tests, run with `--types`, but
  for the 3 that need the C backend.
- Float constants are `f64`, not `long double`: `1e400` reads as `inf`
  (the C++ lexer kept `1e+400`). A literal out of `f64`'s range should be
  an error, once there's a parser to report it.
