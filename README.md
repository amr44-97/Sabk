# Sabk

Sabk is a small systems programming language in the spirit of C, with ideas
from Jai, Odin and Zig. It compiles to C.

```
#import "std/fmt";
#import "std/io";
#import "std/mem";
#import "std/str";

struct List($T) {
    items: []T;
    count: isize;
}

fn push(list: *List($T), item: T) {
    if (list.count == list.items.len) {
        let bigger = new([]T, list.items.len * 2 + 4);
        copy_memory(bigger.ptr, list.items.ptr, list.count * sizeof(T));
        list.items = bigger;
    }
    list.items[list.count] = item;
    list.count++;
}

// a macro: the block after the call runs with a different allocator
fn with_arena(body: Code) #expand {
    let arena = arena_init();
    defer arena_destroy(&arena);
    with_allocator(arena_allocator(&arena)) {
        #insert body;
    }
}

fn main() {
    with_arena() {
        let squares: List(i64);              // memory comes from the arena
        for (i in 0..10) push(&squares, i * i);

        let b = make_builder();
        for (n in squares.items[..squares.count]) {
            builder_print(&b, "% ", n);      // std/fmt: any values, formatted
        }
        println(builder_string(&b));
    }                                         // the arena is freed here
}
```

```
$ ./sabk --run example.sabk
0 1 4 9 16 25 36 49 64 81
```

## What it has

- **C's model:** structs, pointers, manual memory and no hidden control flow.
  It also keeps C's syntax, except that declarations start with a keyword
  and put the type after the name (`let x: i32`, `fn f(a: i32) -> i32`).
- **File modules**, as in Jai. A plain `#import "std/io";` brings in the
  module's names, and `io.println` stays available; `#load` makes one
  module of several files, and `#scope_file` / `#scope_module` keep
  helpers private (there's no `pub`).
- **An implicit context**, as in Jai and Odin: every function receives the
  current allocator, and a block can switch it for everything it calls.
  There are arenas, a temp allocator, and an allocator interface you can
  write your own allocators against.
- **Macros**, as in Jai: `#expand` functions with `Code` parameters,
  `#insert`, and backticks to reach into the caller. Expansion is hygienic.
- **Generics**, as in Jai: `$T` type parameters on functions and structs.
  Each set of types gets one instance, and `--stats` shows what that costs.
  A compile-time `#if` lets generic code do something different for some
  types (`#if (T == string)`).
- **Safety where it's cheap:**
  - returning (or storing away) memory that's gone when the function
    returns, like `&local` or a slice literal, is a compile error
  - array and slice bounds checks
  - integer overflow that wraps instead of undefined behaviour, and
    division by zero that panics with the location
  - a defined, left-to-right evaluation order
  - conditions must be `bool`
  - only lossless implicit conversions
- **Compile-time execution**, as in Jai: `const TABLE = #run make_table();`
  runs ordinary code while compiling (in a bytecode interpreter that can
  also call C) and puts the result in the program. `#insert #run gen();`
  compiles the source text that code returns, and a top-level
  `#run configure();` is a build script: it links libraries, adds C files
  and sets the output, in Sabk.
- **Tagged enums**, like Rust's: `enum Expr { Number(i64), Binary(op: Op,
  lhs: *Expr, rhs: *Expr), Nil }`, taken apart with `switch` (`case
  .Binary{op, lhs, rhs}:`) or `if (e is .Number(n))`. A `switch` on an enum
  must handle every variant, and `Option($T)`/`Result($T, $E)` are ordinary
  generic enums.
- **Several results**, as in Odin and Go: `fn divide(a: i64, b: i64) ->
  (i64, i64)`, `let q, r = divide(a, b);`, `a, b = b, a;`. Functions that
  can fail return their value and whether it worked, a `bool` or an error
  enum (`let text, err = read_file(path);`), and `or_return` and `or_else`
  pass the failure on or replace it: `let n = parse_int(s) or_return;`,
  `get_env("HOME") or_else "/"`. Every error enum converts to the built-in
  `Error`, so `fn main() -> Error` can pass on any failure, and prints it
  as `error: IoError.NotFound`.
- **Patterns**: ranges in cases (`case 'a'..='z':`), patterns inside
  patterns that follow pointers (`case .Negate(.Number(n)):`), guards
  (`case .Number(n) if (n > 0):`), and an exhaustiveness check that shows
  a value no case handles. `switch`, `if` and labeled blocks give values
  (`let w = parse_int(s) or_else w: { log(...); break w = 1; };`), and
  labeled switches run state machines (`continue state = .Next;`).
- **Compile-time reflection:** `#run` code reads `type_info(T)` and writes
  code that `#insert` compiles, even once per generic instance. std/reflect
  uses it for `values_equal` and `hash_value` on any type, so maps take
  struct keys as they are.
- **Printing any value:** `println("% at %", name, point)` formats structs,
  enums, slices and tagged enums from runtime type information
  (`type_info(T)`, `Any`), which programs can use too. Options go in braces:
  `%{>8.2}`, `%{08x}`, and format strings are checked against their values
  while compiling.
- **Strings as views**, as in Jai: `string` is text laid out like `[]u8`,
  with `==` by content and `switch` on strings; memory comes from
  allocators, and `tformat` makes throwaway text in the temp allocator.
- **Literals typed by their context:** `let p: Point = .{ .x = 1 };`,
  `draw(.Red)`, `case .Spades:`.
- **Growable arrays built in**, as in Jai: `[..]T` indexes, slices and
  loops like a slice and passes as one; std/array grows it
  (`array_add(&xs, x)`), and nothing allocates without a call.
- **`defer`**, slicing (`s[a..b]`), array and slice literals (`.[1, 2]`), untyped
  constants, and C interop through
  `extern fn`.

The full language reference is [docs/reference.md](docs/reference.md).
It starts with a section for C programmers, and covers
[strings, bytes and builders](docs/reference.md#strings-bytes-and-builders),
[handling errors](docs/reference.md#handling-errors) and
[memory, with the traps the compiler doesn't catch](docs/reference.md#memory-and-ownership).

## Building

The compiler is written in Sabk and builds itself. The first build starts
from `bootstrap/sabk.c`, the C it writes for itself (for Linux x86-64),
so all it needs is a C compiler with GNU C's extensions (`cc` by default,
or set `$CC`) and libffi. It's developed on Linux.

```
make            builds ./sabk: build/stage0 from the seed, which builds it
make test       runs the test suite
make bootstrap  ./sabk builds itself twice; both must write the same C
make seed       refreshes bootstrap/sabk.c (after changing the compiler)
make clean      removes build/ and ./sabk
```

## Using it

```
./sabk main.sabk            build an executable named `main`
./sabk main.sabk -o app     ... named `app`
./sabk --run main.sabk      build and run it
./sabk --run main.sabk -- a b   ... with arguments
./sabk --release main.sabk  build optimized
./sabk --emit-c main.sabk   print the generated C
./sabk --check main.sabk    only check for errors
./sabk --stats ...           also print phase times and generic instances
```

The standard library lives in [`std/`](std): `io`, `fmt` (formatting any
value), `mem`, `str`, `os`, `array` (growing `[..]T`), `map` (a generic
hash map), `logging`, `reflect` (equality and hashing for any type),
`checked` (arithmetic that reports overflow), `build` (for build scripts),
`sorting`, `path`, `fs`, `process` and `time`. Each file starts with a
summary of what it offers.

## Project layout

```
src/                  the compiler, in Sabk (the table below)
std/                  the standard library, in Sabk
bootstrap/sabk.c     the compiler's own C: the seed of its first build
tests/                golden-file tests: lexer, parser, resolve, types,
                      errors, warnings, and run (programs that are compiled
                      and run); tests/run.sh runs them
docs/reference.md     the language reference
Sabk-*.md            design notes: decisions, the review, the memory
                      traps, and the plan for the language's next steps
```

| File | What's in it |
|---|---|
| `src/main.sabk` | the command line |
| `src/source.sabk` | source files, and messages that point into them |
| `src/token.sabk` | token kinds, keywords, and their names in dumps |
| `src/lexer.sabk` | text to tokens; number values |
| `src/ast.sabk` | the syntax tree's nodes, and the `--ast` dump |
| `src/parser.sabk` | tokens to a syntax tree |
| `src/module.sabk` | modules, and the prelude (`src/prelude.sabk`, baked in by `#run`) |
| `src/resolve.sabk` | loading imports, linking names, expanding macros |
| `src/const.sabk` | compile-time values: 128-bit integers, floats, bools |
| `src/types.sabk` | types, interned |
| `src/check.sabk` | the type checker: declarations, types, layout, reporting |
| `src/statements.sabk` | statements, and several results |
| `src/patterns.sabk` | patterns, `switch`, `is`, and which values cases cover |
| `src/expressions.sabk` | conversions and expressions |
| `src/generics.sabk` | instances, indexing, literals, casts |
| `src/comptime.sabk` | `#run`, `#insert` and `#if` conditions, type info, defaults |
| `src/formats.sabk` | checking `#format` calls |
| `src/memory.sabk` | memory that escapes a function, and the memory traps |
| `src/lower.sabk` | checked code to the VM's bytecode |
| `src/vm.sabk` | the VM: running bytecode, calling C, baking `#run` results |
| `src/vm_ffi.c` | libffi and dlsym, whose types differ between platforms |
| `src/codegen.sabk` | the checked program as C |
| `src/runtime_start.c`, `src/runtime_new.c` | the runtime's C, pieces of every program's C (baked in by `#run`) |

## History

The first compiler was written in C++ (`../the-compiler`, archived now).
This one is a port of it, and a redesign inside: what users see (programs'
output, error messages, the command line) stayed the same. Until the
language moved on (`#import` and regions, Oct 20, 2026), a script diffed
the dumps against the C++ compiler's on every file; it's in git history.
Where the two differ inside:


- Tokens are views of the file's text with a line and column, and hold no
  values: `integer_value` and `float_value` read them when they're needed.
- A lexing error returns to the caller instead of exiting. A syntax error
  still stops the compiler, as before.
- A node is a token, its source text where messages quote it, and a
  tagged enum `NodeKind` whose variants name their parts (`.If{cond,
  then, else_}`), instead of one struct with `lhs`, `rhs`, `extra`, `list`
  and flags. `--ast` still prints the old layout, mapping the parts back,
  which is what the parser tests check.
- Copying and walking a tree go through `NodeKind`'s type information (a
  variant's `*Node` and `[]*Node` parts are its children), so a new kind
  of node needs no code there.
- A macro's labels get its color like its names do: the C++ resolver left
  them uncolored, so a macro's `outer:` clashed with its caller's
  (tests/resolve/macro_labels.sabk).
- Constants are 128-bit (`I128`, two 64-bit halves) where the C++ used
  `__int128`.
- A tagged enum's value made by the checker is a `VariantValue` node.
- The VM's failures aren't exceptions: the first one is kept in the `Vm`,
  and every step returns false up to `vm_evaluate`, which reports it.
  Lowering stops emitting once it has failed.
- `--emit-c` writes the same C as the C++ compiler, but for float
  constants: the C++ one printed them from `long double` with 21 digits,
  this one prints the 17 that read back as the same `f64`.
- Float constants are `f64`, not `long double`: `1e400` reads as `inf`
  (the C++ lexer kept `1e+400`). A literal out of `f64`'s range should be
  an error, once there's a parser to report it.

## Status

Sabk is young and experimental. It works end to end, and the test suite
compiles and runs real programs, but the language and standard library will
still change (Sabk-language-plan.md says how). Debuggers work in Sabk
terms: the C maps back to Sabk files and lines, so gdb breakpoints,
backtraces and stepping show Sabk source.

## License

[MIT](LICENSE)
