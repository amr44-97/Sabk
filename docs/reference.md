# Sabk language reference

Sabk is a C-like language with file modules, an implicit allocator context,
macros and generics.
Declarations start with a keyword (`fn`, `let`, `const`, `struct`, ...) and
put the type after the name, so the grammar is context-free: the parser never
needs to know whether an identifier names a type. Every file can be parsed on
its own, and all name resolution happens after parsing.

**Contents**

- [Example](#example) and [Coming from C](#coming-from-c): a first look
- [Files and modules](#files-and-modules), [Declarations](#declarations),
  [Types](#types), [Statements](#statements), [Expressions](#expressions)
- [Context](#context): the allocator every function gets
- [Name resolution](#name-resolution), [Type checking](#type-checking)
- [Strings, bytes and builders](#strings-bytes-and-builders): `string`,
  `[]u8`, `[N]u8`, `[..]u8` and `Builder`, and when to use which
- [Tagged enums](#tagged-enums), [Patterns](#patterns): `switch`, `is`,
  `if` and labeled blocks as values
- [Several results](#several-results), [Handling errors](#handling-errors)
- [Memory and ownership](#memory-and-ownership), with the
  [traps](#memory-traps) the compiler doesn't catch
- [Printing and type information](#printing-and-type-information)
- [Compiling and running](#compiling-and-running)
- [Generics](#generics), [Compile-time `#if`](#compile-time-if),
  [Compile-time execution](#compile-time-execution),
  [Compile-time reflection](#compile-time-reflection), [Macros](#macros)
- [Standard library](#standard-library), [Lexical notes](#lexical-notes)

Notation: `{ x }` is zero or more, `[ x ]` is optional, `|` separates
alternatives, and quoted text is a literal token. Upper-case names are tokens
from the lexer.

```
IDENT  NUMBER  FLOAT  STRING  CHAR
```

## Example

```
#import "std/fmt";
#import "std/io";
#import "std/mem";
#import "std/str" as strings;

struct Vec2 {
    x: f32;
    y: f32;
}

enum Color: u8 { Red, Green, Blue = 10 }

type Callback = fn(i32) -> bool;

const MAX: i32 = 64;

extern fn printf(fmt: *u8, ...) -> i32;

fn main() -> i32 {
    let arena = arena_init(4096);         // from std/mem, no prefix needed
    defer arena_destroy(&arena);
    context.allocator = arena_allocator(&arena);

    let v = new(Vec2);                    // allocated with context.allocator
    v.x = 1.5;

    let nums = i32.[1, 2, 3, 4];
    let total: i64 = 0;
    for (i in 0..4) {
        total += nums[i] as i64;
    }

    let b = strings.make_builder();       // `as strings`: always qualified
    strings.builder_append(&b, "total = ");
    builder_print(&b, "%", total);         // std/fmt, imported plainly
    println(strings.builder_string(&b));

    if (total > 5 && v.x != 0.0) {
        io.print("big\n");                // the qualified form works too
    } else {
        printf("small\n");
    }
    return 0;
}
```

```
$ ./sabk --run example.sabk          # build and run; see Compiling and running
```

## Coming from C

Most C code reads the same in Sabk. These are the differences that
matter day to day, each with its section:

| C | Sabk | |
|---|---|---|
| `int x = 5;` | `let x: i32 = 5;` or `let x = 5;` (an `isize`) | [Declarations](#declarations) |
| `int f(int a)` | `fn f(a: i32) -> i32` | [Declarations](#declarations) |
| `*p`, `p->x` | `p.*`, `p.x` (`.` follows pointers) | [Types](#types) |
| `#include`, headers | `#import "std/io";`, one file is a module (or `#load` makes one of several) | [Files and modules](#files-and-modules) |
| `char *` text, NUL at the end | `string`: a pointer and a length | [Strings](#strings-bytes-and-builders) |
| `T *p, size_t n` | `[]T`: a slice, a pointer and a length | [Types](#types) |
| `malloc`, `free` | `new(T)`, `alloc`, `free`, through an allocator | [Context](#context) |
| `goto cleanup;` | `defer free(p);` | [Statements](#statements) |
| `case 1: ... break;` | no fallthrough: a case ends at the next `case` | [Statements](#statements) |
| `if (x)` on an int | `if (x != 0)`: conditions are `bool` | [Type checking](#type-checking) |
| `-1` for "not found" | several results: `let n, err = parse_int(s);` | [Handling errors](#handling-errors) |
| macros in `#define` | `#expand` functions, `#run`, `#insert` | [Macros](#macros) |

And what C leaves open, Sabk decides:

- **No silent narrowing.** `let b: u8 = n;` with `n: i64` is an error;
  write `n as u8`. See [implicit conversions](#type-checking).
- **Overflow wraps** (signed too), and **integer division by zero panics**
  with the file and line. Array and slice indexes are **bounds-checked**.
- **Evaluation is left to right**, everywhere. `f(a(), b())` calls `a`
  first.
- **Mixing a bit operator with another operator needs parentheses**:
  `a & MASK == 0` is an error that shows how C would read it.
- **Assignment is a statement**: `if (x = 5)` doesn't compile.
- **Everything starts at zero** (or its type's defaults) unless you write
  `= ---`.
- **Returning a pointer to a local, or a slice literal, is an error.** What
  the compiler can't see is listed under [memory traps](#memory-traps).

## Files and modules

```
file        = { top_decl } EOF ;
top_decl    = import_decl
            | "#load" STRING ";"          // this file's module takes in that file
            | scope_dir                   // who sees what follows
            | decl
            | "#insert" expr ";"          // declarations made by code
            | "#run" expr ";" ;           // a build step
import_decl = "#import" STRING [ "as" IDENT ] ";" ;
scope_dir   = "#scope_export" | "#scope_module" | "#scope_file" ;
```

- Each file is a module. Imports work like Jai's:

  | Import | What you get |
  |---|---|
  | `#import "std/io";` | the module's exported names directly, `println("hi")`, and also the qualified form, `io.println("hi")` |
  | `#import "std/io" as out;` | only the qualified form, `out.println("hi")` |

  - The qualified name is the last path segment. If that isn't a valid
    identifier (`my-lib`), a plain import gives only the bare names.
  - **Your names win:** your own top-level declarations take priority over
    imported names.
  - **Clashes are reported where they're used.** A name that two plain imports
    both provide is an error only where you use it bare. The error suggests
    the qualified forms (`left.shared` or `right.shared`).
  - **Imports don't pass through:** importing `std/str` doesn't give you the
    names `str` itself imports.
- **`#load "file.sabk";` makes one module of several files**, as in Jai.
  The loaded file's declarations, imports and `#load`s join the module:
  its files see each other's names, `#scope_module` ones included, and
  importers see one module.

  ```
  // lib/shapes.sabk                    // lib/shapes/circle.sabk
  #load "shapes/circle";                fn circle(r: f64) -> Shape { ... }
  #load "shapes/square";                #scope_module
                                        fn circle_area(r: f64) -> f64 { ... }
  fn describe(s: Shape) -> string {     #scope_file
      ... circle_area(r) ...            const PI = 3.14159;
  }
  #scope_module
  enum Shape { ... }
  ```

  - The path is relative to the file the `#load` is in, and so are the
    imports a loaded file writes.
  - Each file starts exported; its own `#scope_` directives cover its own
    declarations.
  - A file is loaded once, by one module, and is either loaded or
    imported, not both.
- Source files end in `.sabk`, and the extension is optional in imports:
  `#import "util";` loads `util.sabk`.
- `std/...` paths resolve to the standard library directory (`std` next to
  the compiler, or `--std <dir>`). Every other path is relative to the
  importing file.
- Each file is loaded once, however many times it's imported. Circular
  imports are allowed.
- Members of a module are reached with `.` (`mem.Allocator`, `io.print(...)`),
  the same syntax as struct members. The resolver tells them apart.
- **Who sees a declaration** is set by regions, as in Jai: a directive
  covers every declaration after it, up to the next one. A file starts
  exported.

  ```
  fn greet(name: string) -> string { ... }      // exported: importers see it

  #scope_file                                   // this file only
  fn join_words(a: string, b: string) -> string { ... }

  #scope_export                                 // exported again
  struct Point { x: i64; y: i64; }

  #scope_module                                 // this module's files only
  const SECRET = 7;
  ```

  - `#scope_export`: whoever imports the module (the default at the top).
  - `#scope_module`: the module's own files, not importers.
  - `#scope_file`: this file only. Two files of a module can each have
    their own `#scope_file` name (`PI` in both), but not one the module
    has for all its files.
  - Naming a private one says where it's made private: "`hidden` is
    private to file `lib/regions.sabk`", with a note at the `#scope_file`.
  - There's no `pub`: `pub` and `import` are ordinary names.
- Top-level order doesn't matter: a declaration can be used before it appears
  in the file.

## Declarations

```
decl        = fn_decl
            | struct_decl
            | union_decl
            | enum_decl
            | type_decl
            | const_decl
            | let_decl
            | "extern" "let" IDENT ":" type ";"     // a variable C defines
            | top_if ;

top_if      = "#if" "(" expr ")" "{" { decl } "}"     // see Compile-time #if
              [ "else" ( top_if | "{" { decl } "}" ) ] ;

fn_decl     = [ "extern" ] "fn" IDENT "(" [ params ] ")"
              [ "->" ( results | type { "," type } ) ] // -> i64, bool
              { fn_directive }                       // in any order
              [ "#expand" ] ( block | ";" ) ;        // #expand: a macro
fn_directive = "#format"                             // its format is checked
             | "#nodiscard"                          // its result must be used
             | "#no_bounds_check" ;                  // its indexing isn't checked
params      = param { "," param } [ "," "..." ]
            | "..." ;
results     = result | "(" result { "," result } ")" ; // several: (i64, bool)
result      = type [ "=" expr ] ;                    // a default: ParseError = .None
param       = IDENT ":" type [ "=" expr ]
            | IDENT ":" ".." type                     // any number: a []type
            | "$" IDENT ":" "Type" ;                  // takes a type: generics

struct_decl = "struct" IDENT [ type_params ] "{" { field } "}" ;
union_decl  = "union"  IDENT [ type_params ] "{" { field } "}" ;
type_params = "(" "$" IDENT { "," "$" IDENT } ")" ;   // generic: List($T)
field       = IDENT ":" type [ "=" expr ] ";" ;

enum_decl   = "enum" IDENT [ type_params ] [ ":" type ]
              "{" [ variant { "," variant } [ "," ] ] "}" ;
variant     = IDENT [ "(" payload ")" ] [ "=" expr ] ;
payload     = type                                // Number(i64)
            | IDENT ":" type [ "=" expr ] { "," IDENT ":" type [ "=" expr ] } ;
                                                  // Binary(op: Op, lhs: *Expr)

type_decl   = "type" IDENT "=" type ";" ;

const_decl  = "const" IDENT [ ":" type ] "=" expr ";" ;
let_decl    = let_binding ";" ;
let_binding = "let" IDENT [ ":" type ] [ "=" expr ]
            | "let" IDENT ":" type "=" "---"           // a local, left uninitialized
            | "let" IDENT { "," IDENT } "=" values     // let q, r = divide(a, b)
            | "let" IDENT { "," IDENT } ":" type ;    // let a, b: i32; in a function
values      = expr { "," expr } ;
```

- A function with no `-> type` returns `void`. One with `-> (A, B)`
  returns several values; see [Several results](#several-results).
- `struct`, `union` and `enum` don't take a trailing `;` after `}`.
- A `let` needs a type, an initializer, or both: `let x: i32;`, `let x = 5;`,
  `let x: i64 = 5;`. A `let` with no initializer starts as its type's
  defaults (see field defaults below), and as zeros when there are none.
- **`= ---` leaves a local uninitialized**, as in Jai and Odin: `let buf:
  [65536]u8 = ---;` skips the zeroing and the field defaults, for a buffer
  that's written before it's read. Reading it first is reading whatever
  was there. It needs a type, and only a local can be `---`: a global starts
  as its defaults at no cost, and a field default, a constant or an
  assignment can't be one. In `#run` code its bytes are `0xAA`, so a read
  before the write shows up while compiling, as in Zig.
- A default value on a parameter (`= expr`) is evaluated at the call site. It
  may use `context`, which is how library functions default to the context
  allocator.
- `extern fn name(...);` with no body declares a C function. `extern fn` with a
  body defines a function with the C ABI. Only `extern` functions may be
  variadic (`...`). See [Context](#context) for how `extern` changes calling.
- `extern let name: T;` at the top level declares a variable C defines,
  such as `stdout`, `environ` or a library's globals, under its C name. It
  needs its type, which must match C's (as with `extern fn`, that's yours to
  get right), and can't have a value. The program reads and writes C's
  variable. `#run` code uses the compiler's own copy of it, which must exist
  in the compiler (`stdout` does; a library the compiler doesn't link
  doesn't).
- **Field defaults** (`= expr`) apply wherever a value of the struct is
  made without saying what it is:

  ```
  struct Spec { width: i32 = 8; precision: i32 = -1; }

  let a: Spec;                 // {width = 8, precision = -1}
  let p = new(Spec);           // the same, allocated
  let xs = new([]Spec, 10);    // each element
  let arr: [4]Spec;            // each element
  Outer.{ .name = "x" }        // a Spec field it leaves out
  let g: Spec;                 // a global too
  Spec.{ .width = 2 }          // a literal: the fields it leaves out
  ```

  This goes all the way in: a struct whose field is a `Spec`, or an array
  of them, gets them too. A type with no defaults in it (numbers,
  pointers, most structs) starts as zeros, at no cost. A tagged enum starts
  as its first variant, holding that variant's defaults. A default is
  evaluated each time a value is made, and a global's must be constants.
  Memory that comes from an allocator rather than the language (`alloc`,
  a growing `[..]T`, C) is raw bytes: zeros, not defaults.
- **A union** is C's: its fields share the same memory, and it's as big as
  its largest field. Nothing records which field holds the value, so it
  prints as `Bits{...}`, has no `==`, and can't come out of `#run`. A
  [tagged enum](#tagged-enums) is the safe kind: it knows which variant it
  holds.

  ```
  union Bits { f: f32; u: u32; }
  let b = Bits.{ .f = 1.0 };
  println("%", b.u);              // 1065353216: the float's bits
  ```

- **`type Name = T;`** is another name for `T`, as C's `typedef` is: the
  two are the same type and mix freely. `type Handler = fn(i64) -> i64;`
- **Functions are values.** A function's name is a value of its function
  type, which can be stored, passed and called; `null` is no function.
  There are no closures: a function sees its parameters and globals, so
  a callback that needs data takes a `*void` (or a generic) for it:

  ```
  fn apply(h: fn(i64) -> i64, x: i64) -> i64 { return h(x); }
  apply(twice, 4);                // fn twice(x: i64) -> i64
  ```

- **`const`** is a value known at compile time: a number, a string, an
  array or struct literal of those, or what `#run` computed. A top-level
  `let` is a global variable, which starts as its initializer (also known
  at compile time) and can change.

## Types

```
type        = "*" type                                  // pointer
            | "[" expr "]" type                         // array of N
            | "[" "]" type                              // slice (pointer + length)
            | "[" ".." "]" type                         // growable array
            | "fn" "(" [ type { "," type } ] ")" [ "->" results ]
            | "?" type                                  // Option(T): a value or None
            | "$" IDENT                                 // declares T (generics)
            | IDENT [ "." IDENT ] [ "(" type { "," type } ")" ] ;
                                       // i32, Vec2, mem.Allocator, List(i32)
```

Types read left to right: `*[4]u8` is a pointer to an array of 4 `u8`, and
`[4]*u8` is an array of 4 pointers.

**The untyped pointer is `*void`**, C's `void *`, as in Jai: any pointer
converts to it on its own, and it converts back with `as`. It doesn't say
what it points at, so it can't be indexed or moved, and `p.*` is only a
`void`: cast it first (`p as *u8` to count in bytes).

**Pointers.** `&x` is the address of `x`, and `p.*` is what `p` points at
(`p.x` follows the pointer to a field on its own). `p[i]` is the i-th value
from `p`, and `p[0..n]` a slice of `n` of them, whatever `p` points at. For
a `*[4]u8` that's the i-th array, as in C, so the array's own elements are
`p.*[i]`:

```
fn fill(buffer: *[24]u8) {
    for (i in 0..buffer.len) buffer.*[i] = ' ';  // .len follows the pointer
}
let rows = alloc(3 * sizeof([4]f32)) as *[4]f32;
rows[1] = .[5, 6, 7, 8];                        // the second row
rows.*[1] = 2;                                  // element 1 of the first
```

This way `p[i]` means the same for every `T` in generic code: std/array's
`xs.ptr[xs.len]` is the next element even when the elements are arrays.
The one exception is a pointer to a growable array: where `*[..]T` is
written out, `p[i]` and `p[lo..hi]` are errors that suggest `p.*[i]`,
since stepping over whole growable arrays is never what's meant there (see
below).
C's `*p` isn't a dereference; a `*` before an expression only spells a
pointer type, where a type argument goes (`make(*Node)`).

**Growable arrays.** `[..]T` is an array that grows. Its elements are
allocated, and it's laid out as `{ptr, len, cap, allocator}`, four fields
that can all be read and set. It indexes, slices and loops like a slice
(`xs[i]` is bounds-checked against `xs.len`), and goes wherever a `[]T` is
expected as a view of its elements. The functions that grow it are in
std/array:

```
let names: [..]string;           // zero: empty, nothing allocated yet
array_add(&names, "ada");        // grows with context.allocator
let xs = array_of(.[3, 1, 2]);   // a copy of the literal, allocated
sort(xs);                        // fn sort(items: []$T): a view
for (x in xs) print("% ", x);
xs.len = 0;                      // empty, keeping the memory
array_free(&xs);
```

Nothing allocates without a call: a literal can't be a growable array
(`let xs: [..]i64 = .[1, 2];` is an error, and `array_of` copies one), and
neither can a constant. Copying one copies its four fields, so both copies
share the elements. A function that adds to one takes `*[..]T`, and reaches
the elements through it as `xs.*[i]`; `xs[i]` on a `*[..]T` is an error
that says so, since it would step over whole arrays. It stays pointer
indexing in a generic instance (a `*T` whose `T` is a `[..]U`) and on an
array's `.ptr`, which point into arrays of them, and
`(xs + i).*` steps the pointer anywhere. Growing can move the elements, so
pointers into them are only good until the next add; see
[traps](#memory-traps) 7, 8, 12 and 13.

Primitive types are **not keywords**. They are ordinary identifiers that the
resolver finds in a built-in scope:

```
i8 i16 i32 i64 isize   u8 u16 u32 u64 usize   f32 f64   bool   void
string
```

That way `i32` and `mem.Allocator` parse the same way, and adding a primitive
never touches the lexer or parser.

**`void` is a type with no bytes and one value, `.{}`.** It's what a
function returns when it returns nothing, and it goes wherever a type
goes: a variable, a field, a parameter, or what a generic's `T` stands
for. `sizeof(void)` is 0, and a void field takes no space:

```
struct Tagged($T) { id: i32; value: T; }
let t = Tagged(void).{ .id = 7 };   // 4 bytes: the value takes none
t.value = .{};                      // void's one value
let w = flush();                    // a void call's result: a void value
fn finish() { return flush(); }     // returned where void is returned
```

- `.{}` is void's value wherever a `void` is expected, as `.{ ... }`
  builds a struct. A void result is left out of a function's type (see
  [Several results](#several-results)), and `Map(string, void)` is a set
  whose values take no bytes.
- Through a `*void`, `p.*` is a void: it reads nothing, which is what
  `*T` with `T = void` needs in generic code.
- A constant can't be `void` (there's nothing to name), and neither can a C
  function's parameter, since C has none. Arrays, slices and growable
  arrays of `void` are errors: there's nothing for them to hold.
- Printing a call that returns void is an error, since it's almost always
  a mistake; a `void` value printed (in generic code, say) shows `void`.
- `*void` is the untyped pointer (see Pointers), and `new(void)` has
  nothing to allocate.

## Statements

```
block       = "{" { stmt } "}" ;

stmt        = block
            | let_decl
            | const_decl
            | if_stmt
            | while_stmt
            | do_stmt
            | for_stmt
            | switch_stmt
            | "return" [ values ] ";"                      // return q, r;
            | "break" [ IDENT [ "=" expr ] ] ";"         // = a block's or switch's value
            | "continue" [ IDENT [ "=" expr ] ] ";"      // = a switch's next value
            | IDENT ":" ( while_stmt | do_stmt | for_stmt | switch_stmt | block )
            | "defer" stmt
            | "`" ( let_decl | const_decl | "defer" stmt   // macros only
                  | "return" [ expr ] ";" )
            | "#insert" IDENT ";"                          // macros only
            | "#insert" expr ";"           // statements made by code (not IDENT)
            | "#if" "(" expr ")" stmt [ "else" stmt ]      // compile-time if (top level: top_if)
            | "_" "=" expr ";"                             // drops a value on purpose
            | simple_stmt ";"
            | call block ;               // a macro call with a trailing block

simple_stmt = expr [ assign_op expr | "++" | "--" ]
            | expr { "," expr } "=" values ;             // a, b = b, a
assign_op   = "=" | "+=" | "-=" | "*=" | "/=" | "%="
            | "&=" | "|=" | "^=" | "<<=" | ">>=" ;

if_stmt     = "if" body [ "else" stmt ] ;
while_stmt  = "while" body ;
body        = "(" expr ")" stmt                      // parentheses: any statement
            | expr block ;                           // none: a block
do_stmt     = "do" stmt "while" expr ";" ;

for_stmt    = "for" "(" header ")" stmt
            | "for" header block ;
header      = IDENT [ "," IDENT ] "in" expr [ ".." expr ]
            | [ let_binding | simple_stmt ] ";" [ expr ] ";" [ simple_stmt ] ;

switch_stmt = "switch" expr "{" { case_clause } "}" ;
case_clause = "case" pattern { "," pattern } [ guard ] ":" { stmt }
            | "default" ":" { stmt } ;
guard       = "if" "(" expr ")" ;                    // case .Number(n) if (n > 0):
pattern     = expr                                   // a value
            | expr ".." expr | expr "..=" expr       // a range: ..= includes the end
            | variant "(" item ")"                   // a variant's value
            | variant "{" field { "," field } "}" ;  // its fields
variant     = "." IDENT | IDENT { "." IDENT } ;
field       = IDENT ":" item | [ "&" ] IDENT ;       // field: item, or bound to its name
item        = [ "&" ] IDENT                          // a name for it (`_`: none)
            | pattern ;                              // or what it must match
```

- **Parentheses around a condition are optional.** With them, as in C,
  the body can be any statement: `if (err != .None) return err;`. Without
  them, the body is a block, so the condition can't run into it:
  `if err != .None { return err; }`. The same goes for `while` and `for`
  (`for x, i in xs { ... }`); `switch x { ... }` always has its braces.
  - A `(` holds the whole condition only when the condition ends at its
    `)`: `if (a + b) * 2 > c { ... }` is a condition without parentheses,
    so it takes a block.
  - In a condition without parentheses, a `{` after a name is the body's:
    `if p == origin {`. A literal there is written `Point.{ ... }`, as
    everywhere; C's `Point{ ... }` isn't one.
  - A declaration's results don't need them either:
    `fn divmod(a: i64, b: i64) -> i64, i64 { ... }`. A function type keeps
    them, `fn(i64) -> (i64, bool)`, since a comma there could start the
    next parameter.
  - The `if` that gives a value, `if (c) a else b`, keeps its parentheses.
- **Assignment, `++` and `--` are statements, not expressions.** `if (x = 5)`
  is a syntax error, and `a = b = c` isn't allowed.
- **There's no `goto` and no `static`.** `defer` covers what `goto cleanup`
  was used for, and `goto` interacts badly with `defer`. File-private is
  already the default, which covers C's top-level `static`.
- `for` has two forms. `for (i in a..b)` counts from `a` up to but not
  including `b`. `for (x in xs)` iterates over the elements of an array,
  slice, growable array or string (its bytes, as `u8`s), and `for (x, i
  in xs)` gives each one's index too, an `isize`. The C three-clause form
  also works. The parser tells them apart by looking for `IDENT "in"` (or
  `IDENT "," IDENT "in"`) right after `(`.

  ```
  for (i in 0..xs.len) total += xs[i];     // i: isize, 0 up to xs.len - 1
  for (x in xs) total += x;                // x: a copy of each element
  for (x, i in xs) println("% %", i, x);   // ... and its index: 0, 1, ...
  for (c in "abc") print("% ", c);         // 97 98 99
  for (let i = 10; i > 0; i -= 2) { ... }  // C's form
  ```

  - The loop variable of `for (x in xs)` is a copy, and can't be assigned
    or have its address taken; nor can the index. To change the elements,
    use the index: `for (x, i in xs) xs[i] = x * 2;`. A range takes one
    name: `for (i in a..b)` already counts.
  - `xs` is read once, before the first pass. Adding to a growable array
    while looping over it is a [trap](#memory-traps) (12).
- **`switch` has no implicit fallthrough.** A case runs until the next `case`
  or `default`. One case can match several values: `case 1, 2, 3:`. `break`
  inside a `switch` leaves the switch. See [Patterns](#patterns) for what a
  case can match, and for `switch` as an expression.
- **Labels.** `outer: for (...)` names a loop (or a switch, or a block), so
  `break outer;` and `continue outer;` reach it from inside nested loops.
  Leaving runs the defers of the scopes left, as an unlabeled `break` does.
  A labeled block, `done: { ... }`, is left with `break done;`; one used as
  an expression gives a value (see
  [Labeled blocks](#labeled-blocks-and-switches-give-values)).

  ```
  search: for (row in 0..rows) {
      for (col in 0..cols) {
          if (grid[row][col] == target) { found = true; break search; }
          if (grid[row][col] < 0) continue search;   // the next row
      }
  }
  ```

  - An unlabeled `break` leaves the innermost loop or switch, and an
    unlabeled `continue` goes on with the innermost loop. A labeled block
    is only left by its name.
  - Two labels around each other can't have the same name, and a `break`
    or `continue` to a name that isn't around it is an error.
  - `continue` goes to a loop, or runs a labeled switch again with a new
    value (`continue state = .Next;`, see [Labeled switches](#labeled-switches)).
    A block can't be continued.
- **A `switch` on an enum must handle every variant**, or have a `default`.
  See [Tagged enums](#tagged-enums).
- **`defer stmt` runs `stmt` when the enclosing block exits**, by any
  path: its end, `return`, `break`, `continue` or `or_return`. Defers run
  in reverse order, and a loop body's defers run at the end of each pass:

  ```
  fn copy(from: string, to: string) -> IoError {
      let data = read_file(from) or_return;
      defer free(data.ptr);                 // runs on every return below
      return write_file(to, data);
  }

  for (i in 0..3) {
      defer println("end of pass %", i);    // after each pass, continue too
      if (i == 1) continue;
      println("pass %", i);
  }
  ```

  A defer's statement can't `return`, `break` or `continue` out of it, or
  use `or_return`. It sees the variables as they are when it runs, not as
  they were when the `defer` was reached.

## Expressions

Lowest to highest precedence. Binary operators are left-associative.

**Evaluation is left to right**, everywhere: a call's arguments (then its
defaults), an operator's operands, a struct literal's values in the order
they're written, what's indexed before the index, and an assignment's
target before its value. So `pair(f(), g())` calls `f` first, `x + bump(&x)`
reads `x` before `bump` changes it, and `xs[i] = next(&i)` assigns to the
element `i` named before the call. Assigning several targets at once (`a,
b = ...`) works out every value first, then assigns the targets in order. The compiled program and `#run` code
agree; C alone would leave much of this open.

| Level | Operators                          | Notes                       |
|-------|------------------------------------|-----------------------------|
| 1     | `or_else`                          | right to left; see [Several results](#several-results) |
| 2     | `\|\|`                             |                             |
| 3     | `&&`                               |                             |
| 4     | `\|`                               | bit operators and shifts: parentheses next to a different operator |
| 5     | `^`                                |                             |
| 6     | `&`                                |                             |
| 7     | `==` `!=` `<` `>` `<=` `>=` `is` `!is` | non-associative; `is` and `!is` take a pattern |
| 8     | `<<` `>>`                          |                             |
| 9     | `+` `-`                            |                             |
| 10    | `*` `/` `%`                        |                             |
| 11    | `as`                               | `expr as type`              |
| 12    | `-` `!` `~` `&` (prefix)           | negate, not, bit-not, address-of |
| 13    | `f(...)` `a[i]` `a.b` `p.*` `T.{...}` `T.[...]` `or_return` | postfix |

```
expr        = or_expr [ "or_else" expr ] ;
or_expr     = and_expr { "||" and_expr } ;
and_expr    = bitor_expr { "&&" bitor_expr } ;
bitor_expr  = xor_expr { "|" xor_expr } ;
xor_expr    = bitand_expr { "^" bitand_expr } ;
bitand_expr = cmp_expr { "&" cmp_expr } ;
cmp_expr    = shift_expr [ cmp_op shift_expr | "is" pattern ] ;
cmp_op      = "==" | "!=" | "<" | ">" | "<=" | ">=" ;
shift_expr  = add_expr { ( "<<" | ">>" ) add_expr } ;
add_expr    = mul_expr { ( "+" | "-" ) mul_expr } ;
mul_expr    = cast_expr { ( "*" | "/" | "%" ) cast_expr } ;
cast_expr   = unary { "as" type } ;
unary       = ( "-" | "!" | "~" | "&" ) unary
            | "*" unary                 // a pointer type: make(*Node)
            | postfix ;
postfix     = primary { "(" [ args ] ")"
                      | "[" expr "]"
                      | "[" [ expr ] ".." [ expr ] "]"     // slice
                      | "." IDENT
                      | "." "*"                     // p.*: what p points at
                      | "or_return"
                      | "." struct_init             // Point.{ ... }
                      | "." array_init } ;          // i64.[1, 2]: the element type
args        = arg { "," arg } [ "," ] ;
arg         = expr | ".." expr ;                  // ..xs: a slice for a `..` param

primary     = NUMBER | FLOAT | STRING | CHAR
            | "true" | "false" | "null"
            | IDENT
            | "context"
            | "`" IDENT                                 // macros only
            | "." struct_init                            // .{ ... }, typed by context
            | "." array_init                             // .[1, 2], by context or elements
            | "." IDENT                                 // .Red, typed by context
            | "#insert" IDENT                           // macros only
            | "#insert" unary              // an expression made by code (not IDENT)
            | ( "#text" | "#location" ) "(" IDENT ")"   // macros only
            | "#run" unary                              // runs while compiling
            | "(" expr ")"
            | "switch" expr "{" { value_case } "}"
            | IDENT ":" "switch" expr "{" { labeled_case } "}"
            | IDENT ":" block                           // break IDENT = value; gives it
            | "if" "(" expr ")" expr "else" expr        // one of two values
            | "sizeof" "(" ( type | expr ) ")"        // expr: its type's size, unevaluated
            | "type_info" "(" ( type | expr ) ")"       // a *TypeInfo; expr: its type's, unevaluated
            | "new" "(" type [ "," expr [ "," expr ] ] ")"
            | "new" "(" literal [ "," expr ] ")"        // new(Point.{ .x = 1 })
            | ( "[" | "fn" ) type ;                     // a type argument

value_case  = "case" pattern { "," pattern } ":" expr ";"
            | "default" ":" expr ";" ;
labeled_case = ( "case" pattern { "," pattern } | "default" ) ":"
               ( expr ";" | { stmt } ) ;              // stmts end in break IDENT = value;
struct_init = "{" [ init { "," init } [ "," ] ] "}" ;
array_init  = "[" [ expr { "," expr } [ "," ] ] "]" ;
init        = "." IDENT "=" expr                        // designated: .x = 1
            | expr ;                                    // positional
```

- **The order is C's, and where C surprises, it's an error.** A bit
  operator or shift (`&` `|` `^` `<<` `>>`) next to a different operator
  needs parentheses, so `a & MASK == 0`, `x >> 8 * k`, `1 << n + 1` and
  `a & b | c` are errors that show how C would read them:

  ```
  `&` next to `==` needs parentheses: C reads `a & MASK == 0` as `a & (MASK == 0)`
  ```

  No C habit changes meaning: what compiles means what it means in C. A
  chain of one operator (`a | b | c`), prefix operators (`~a & b`) and `as`
  need nothing, and `&&` and `||` mix freely. The rule is checked after
  parsing, one error per expression.
- The pattern after `is` binds tighter than comparisons, so
  `e is .Some(x) && x > 0` ends the pattern at `&&`, and `e is A | B` is an
  error rather than a pattern for either. A `case` pattern can use any
  operator but `&&` and `||`: `case READ | WRITE:` matches that value.
- Comparisons don't chain: `a < b < c` is a syntax error.
- `as` binds tighter than every binary operator and looser than prefix
  operators: `-x as i64` is `(-x) as i64`, and `a + b as i64` is
  `a + (b as i64)`. The type after `as` ends where the type grammar ends, so
  `p as *u8 * 2` reads as `(p as *u8) * 2`.
- `sizeof` and `new` are keywords with their own syntax, written like calls:
  `sizeof(T)`, `new(T)`. `sizeof(T)` is an untyped integer constant, so it
  fits any integer type, such as C's `size_t` (`usize`) in `memset(p, 0,
  sizeof(T))`; `let n = sizeof(T);` is an `isize`.
- `..` only appears in slices and in the range form of `for`. It isn't a
  general operator.
- **A leading dot takes the type from where it's used; a type before the
  dot names it.** `.{ ... }` is a struct or union literal, `.[ ... ]` an
  array or slice literal (below), and `.Red` an enum value, whose type is
  the one their context expects; `Point.{ .x = 1 }`, `i64.[1, 2]` and
  `Color.Red` write the type out:

  ```
  let p: Point = .{ .x = 1, .y = 2 };     // a declared type
  p = .{ 3, 4 };                          // the left side of `=`
  draw(.Red);                             // a parameter's type
  array_add(&points, .{ .x = 5 });        // a generic one: T comes from &points
  return .{};                             // the return type
  switch (suit) { case .Spades: ... }     // the switch's type
  if (c == .Green) ...                    // the other side of == or !=
  ```

  A struct field's type, an array or slice element's type, and a default
  parameter value's type count too, so they nest:
  `.{ .at = .{ .x = 1 }, .color = .Red }`. Where nothing says what the type
  is (`let p = .{...};`), it's an error: write the type out. In a call to a
  generic function, the other arguments decide `T` first, and then `.{...}`
  is checked against that.
- **Array and slice literals** are written `.[ ... ]`. The context decides
  what one is, as it does for `.{ ... }`; with no context, the elements
  decide, and it's an array:

  ```
  let a: [3]i32 = .[1, 2, 3];    // the declared type: an array
  sum(.[1, 2, 3]);               // fn sum(xs: []i64): a slice
  let xs = .[1, 2, 3];           // [3]isize
  let fs = .[1, 2.5];            // [2]f64: they agree as in 1 + 2.5
  let ps = .[Point.{ .x = 1 }, .{ .y = 2 }]; // the typed one types the .{ }
  let grid = .[.[1, 2], .[3, 4]]; // [2][2]isize
  let e: []i32 = .[];            // empty: only with a context
  ```

  - **Without a context**, the elements agree the way the two sides of `+`
    do: typed values decide, untyped constants follow them, and default
    (`isize`, `f64`, `string`) when nothing else decides. `.{ ... }` and
    `.Red` elements take the type the others agreed on. Elements that don't
    agree (`.[1, "x"]`), rows of different lengths (`.[.[1, 2], .[3]]`: give it
    a type of slices, `[][]isize`), and a literal with nothing to go by
    (`.[]`, `.[.{ .x = 1 }]`) are errors.
  - **In a generic call**, the other arguments decide `T` first and the
    literal is checked against that: `array_add(&xs, .[1, 2])` with
    `xs: [..][]i32` makes a `[]i32`. When nothing else decides,
    the literal does: `largest(.[3, 9, 4])` has `T = isize`.
  - **`T.[ ... ]` names the element type**, and the count comes from the
    elements: `i32.[1, 2, 3]` is a `[3]i32`. Since the prefix is the
    element type, `[2]i64.[.[1, 2], .[3, 4]]` is a `[2][2]i64`, an array of
    `[2]i64`s; one that starts with `*` or `fn` goes in parentheses:
    `(*Node).[a, b]`. There's no named slice literal: a slice takes its
    type from its context (`let s: []i32 = .[1, 2];`).
  - **An array literal fills the whole array.** `let a: [5]i32 = .[1, 2,
    3];` is an error, where C would make the rest zero. Write every
    element, or declare the array (its elements start as zero) and assign
    the ones that aren't.
  - `[` in an expression is always a type, as in `make_list([]u8)`, so a
    literal can be indexed as it is: `.[x, y][i]`.
  - **A slice literal**, `.[ ... ]` where a slice is expected, is a slice
    of an unnamed array holding the elements. In a function the elements live until it returns, wherever in
    it the literal is (an inner block or a loop: each evaluation fills the
    same array). At the top level (`const DAYS: []string = .["mon", "tue"];`)
    they live for the whole program. To keep one past its function, copy
    it: `return clone_slice(.[1, 2, 3]);` (std/mem).
- **An array goes where a slice is expected**, as a view of it, the way a C
  array becomes a pointer: `zero(a)` for `fn zero(xs: []i64)` writes `a`'s
  elements, and `let view: []i64 = a;` is a view, not a copy (`let b = a;`
  still copies). The element types must be the same. A temporary array
  (`sum(three())`, for `fn three() -> [3]i64`) is copied into memory that
  lives until the function returns, like a slice literal's elements. A
  constant array is stored once, so `print_all(DAYS)` and `DAYS[1..]` view
  the same elements.
- **Memory that outlives its function** is an error. A function's own
  memory is its locals (and so `&local`, and slices of local arrays), its
  slice literals, and the copies made for `Any`; the compiler follows them
  through locals and into structs, and reports when one is returned, stored
  in a global, or stored through a pointer or slice parameter (memory the
  caller owns):

  ```
  fn make() -> []i32 { return .[1, 2]; }          // error: gone once `make` returns
  fn view() -> []i64 { let a: [2]i64 = .[1, 2]; return a; } // error: a view of `a`
  fn point() -> *Point { let p: Point; return &p; } // error
  fn fill(out: *Record) { out.tags = .["x"]; }       // error: stored where `out` points
  ```

  The check is conservative rather than complete: it doesn't follow values
  into other functions, which is fine (passing a slice literal to a function
  is how they're used), and it can't see everything a pointer was made
  from.
- **Slicing.** `x[lo..hi]` is a `[]T` view of elements `lo` up to (not
  including) `hi`, without copying.
  - Both bounds are optional: `x[lo..]`, `x[..hi]`, `x[..]`.
  - `x` can be an array (a variable or a constant, not a temporary), a
    slice, or a pointer `*T`. A pointer has no length, so it needs `hi`:
    `p[0..n]` turns a pointer and a length into a slice. For a pointer to
    an array that's `n` arrays; `p.*[lo..hi]` slices the array itself.
  - Bounds are checked: at compile time when they're constants, otherwise at
    run time, which panics. For a raw pointer only `lo <= hi` can be checked.
- An enum value is a member access: `Color.Red`.
- A struct literal can't mix positional and designated fields (checked after
  parsing).

## Context

Every non-`extern` function receives a hidden pointer to the caller's
`Context` as its first argument. The `context` keyword refers to it. It's
how a function knows where to allocate, where to log and what to do on a
panic, without those being parameters of every function.

```
struct Context {
    allocator: Allocator;        // where new(), alloc() and std allocate
    temp_allocator: Allocator;   // an arena for short-lived memory
    logger: Logger;              // where std/logging's log() goes
    panic_handler: PanicHandler; // what panic and assert call
}
```

**Changing it is scoped.** Assigning to a field of `context` gives the
current block its own copy of the context, and everything it calls sees
the change. The caller's context comes back when the block exits:

```
fn load_level(path: string) {
    let arena = arena_init();
    defer arena_destroy(&arena);
    context.allocator = arena_allocator(&arena);   // this block and its callees
    let level = parse_level(path);                 // allocates from the arena
    ...
}                                                  // the caller's allocator is back

with_allocator(arena_allocator(&arena)) { ... }    // std/mem: the same, for a block
with_temp_allocator() { let s = format("%", x); }  // ... with the temp allocator
```

**Allocating.**
- `new(T)` allocates a `T` with `context.allocator` and returns `*T`.
  `new(T, a)` uses the allocator `a` instead. The `T` starts as a new
  variable would: its type's defaults, zeros elsewhere.
- `new(Point.{ .x = 1 })` allocates a copy of a value written as a literal,
  and `new(.{ .x = 1 })` does where the type is known
  (`let p: *Point = new(.{ .x = 1 });`). An allocator can follow, as with
  `new(T, a)`.
- `new([]T, n)` allocates a slice of `n` elements, each as a new variable
  would start, and `new([]T, n, a)` uses `a`. A length of 0 gives an empty
  slice without allocating.
- `new` panics when the allocator runs out of memory. std/mem's
  `alloc(size)` returns null instead.
- Memory is given back with the allocator it came from: `free(p)` for a
  pointer, `free(s.ptr)` or `delete(s)` for a slice or string. These take
  the allocator last, defaulting to `context.allocator`, so memory from
  another one is freed with it: `free(p, arena_allocator(&arena))`. A
  growable array, `Map` or `Builder` records its allocator, and
  `array_free(&xs)`, `map_free(&m)`, `builder_free(&b)` and `delete(x)`
  free with that one. See [Memory and ownership](#memory-and-ownership).
- Most of the standard library's allocating functions take the allocator
  last, with a default parameter, for example
  `fn copy_string(s: string, a: Allocator = context.allocator) -> string`.
  The exceptions are the ones that end in `..` values or grow a
  container: `format` and `builder_print` use `context.allocator`,
  `tformat` the temp allocator, and `array_add`, `map_put` and
  `builder_append` the container's own. To send `format` elsewhere, wrap
  it: `with_allocator(a) { s = format(...); }`.

**The temp allocator.** `context.temp_allocator` is an arena for memory
that only has to live a little while: text to print, a scratch array.
Nothing in it is freed on its own, and nothing is freed one piece at a
time. Free everything in it at a good moment, such as once per frame or
per request, with `free_all(context.temp_allocator)`:

```
for (request in requests) {
    let reply = tformat("hello, %", request.name);   // std/fmt: in the temp allocator
    send(reply);
    free_all(context.temp_allocator);                // every temp allocation, at once
}
```

**Arenas** (std/mem) work the same way for memory you want to free
together: `arena_init()`, `arena_allocator(&arena)`, `arena_reset(&arena)`
to reuse it, `arena_destroy(&arena)` to give it back.

**`context.logger`** is where `log(level, fmt, args)` (std/logging)
sends a formatted message: by default stderr, as `warning: message`. A
library logs instead of printing, so its caller decides where messages
go: `capture_logger(&lines)` keeps copies in a `[..]string`, and
`silent_logger()` drops them. A `Logger` is a procedure,
`fn(*void, LogLevel, string)`, and its `data`; `LogLevel` is `.Debug`,
`.Info`, `.Warning` or `.Error`. The message is only valid during the
call.

**`context.log_level`** is the lowest level `log` passes on: `.Debug`
(all of them) by default. Below it, a message isn't even formatted.

```
{
    context.log_level = .Warning;   // this block: warnings and errors only
    log(.Info, "% items", n);       // skipped
}
```

**`context.panic_handler`** is what std/os's `panic` and `assert` call,
with what failed (`"panic"` or `"assertion failed"`), the message and the
location. By default it prints `file:line:col: panic: message` and
aborts. A test can set its own to report the failure its way. A handler
shouldn't return; if it does, the program aborts after it, because the
code after a panic can't go on. The runtime's own checks (bounds,
division by zero, a switch with no case) abort directly.

**`extern` functions** use the plain C calling convention with no hidden
parameter. Inside an `extern fn` that has a body (a function C code calls
back into), `context` starts as the default context.

**The allocator interface**, declared in the prelude, for writing your
own:

```
enum AllocatorMode { Alloc, Free, Resize, FreeAll }

// (data, mode, size, alignment, old_memory, old_size) -> memory
type AllocatorProc = fn(*void, AllocatorMode, isize, isize, *void, isize) -> *void;

struct Allocator { procedure: AllocatorProc; data: *void; }
```

| Mode      | Returns                                                         |
|-----------|-----------------------------------------------------------------|
| `Alloc`   | `size` bytes of zeroed memory, aligned to `alignment` (a power of two) |
| `Free`    | null, after freeing `old_memory`                                |
| `Resize`  | `size` bytes holding the first `min(size, old_size)` bytes of `old_memory`, the rest zeroed; frees `old_memory` |
| `FreeAll` | null, after freeing everything the allocator handed out (if it can) |

Running out of memory returns null. The default `context.allocator` is C's
heap (`calloc`, `realloc`, `free`), and it ignores alignments above 16; it
can't `FreeAll`. Both default allocators are written in the language
itself, in the prelude.

## Name resolution

After parsing, every name is linked to its declaration. These rules are
checked at that point, and every violation is reported, not just the first.

**Scopes**, innermost first:

1. Block scopes inside a function. Every `{ }`, and every `if`, loop or
   `defer` body, opens one. A `for` header's variables are scoped to the
   loop.
2. The function's parameters. The body shares this scope, so
   `fn f(a: i32) { let a = 1; }` is a redeclaration.
3. The module: its top-level declarations and import names.
4. The exported names of the module's plain imports. A name more than one
   of them provides is ambiguous.
5. The prelude's exported names.
6. The built-in types (`i32`, `u8`, ..., `string`).

**Declarations:**

- Top-level names can be used anywhere in the module, before or after their
  declaration.
- Locals can only be used after their declaration. A `let`'s initializer is
  resolved before the new name exists, so in `let x = x + 1;` the `x` on the
  right refers to an outer `x`.
- Declaring the same name twice in one scope is an error. An inner block may
  shadow an outer name.
- Parameter defaults see the module scope, but not the other parameters,
  because they're evaluated at the call site.
- An enum variant's value can refer to the variants before it:
  `enum E { A, B = A + 1 }`. Everywhere else a variant is written
  `E.A`.

**Modules:**

- `mod.name` only reaches exported declarations (not under a
  `#scope_module` or `#scope_file`). Import names are never exported, so
  importing `a` doesn't give your importers access to `a`.

**Types, values and modules are separate kinds of names:**

- A type can't be used as a value (`let x = i32;`), and a value can't be
  used as a type (`let x: some_fn;`).
- A type name may appear in an expression in only two places: before `.`
  (`Color.Red`) and before a struct literal (`Vec2.{...}`).
- A module name may only appear before `.`.

**Control flow:**

- `break` must be inside a loop or `switch` (or name a labeled block
  around it), and `continue` inside a loop (or name a labeled switch).
- `break name = value;` goes only to a block or switch that gives a value,
  and such a one must be left with a value. The errors say which:

  ```
  for (i in 0..3) {
      let h = inner: { break; };   // error: `break` here would leave `inner`, which gives
  }                                //   a value: give it with `break inner = value;`, or
                                   //   label the loop or switch to leave it by name
  outer: for (i in 0..3) {
      break outer = 1;             // error: `outer` doesn't give a value; leave it with `break outer;`
  }
  named: { continue named; }       // error: `named` is a block: `continue` goes back to a
                                   //   loop or a switch statement
  let k = v: { break v; };         // error: `v` gives a value: `break v = value;`
  ```

- `return`, `break` and `continue` can't jump out of a `defer`.
- `context` can only be used inside functions and in parameter defaults. It
  isn't available in global initializers.

**Struct literals:**

- A struct literal can't mix `.field = value` with positional values.
- A struct literal can't set the same field twice.

**Left to the type checker:**

- member access on values (`v.x`)
- members of type aliases
- checking struct literal field names against the struct

## Type checking

**Prelude.** `Allocator`, `AllocatorMode`, `AllocatorProc` and `Context` are
declared in a built-in prelude module (`src/prelude.sabk`) that every file can see.
Only its exported declarations are visible; the rest, after its
`#scope_file`, is the runtime's implementation. A module's own declarations shadow it.

**Untyped constants.** Literals and constants without a type have no fixed
type until they're used, as in Go and Odin:

- `5` fits any integer type it's assigned to, or any float type.
  `let b: u8 = 300;` is an error.
- `1.5` fits any float type.
- A string literal is a `string`, or a `*u8` where one is expected (for C
  functions). Its bytes are `"..." as []u8`.
- `null` fits any pointer, `*void`, function or slice.
- `const N = 4;` stays untyped, so `N` works as any integer type.
  `const N: u8 = 4;` is a `u8`.
- Without a type, `let` picks a default: `isize` for integers, `f64` for
  floats, `string` for strings. `let p = null;` is an error. `isize` is
  also the type of `.len`, so counts and lengths mix without casts:
  `let seen = 0; seen += xs.len;`.
- Constant expressions are folded at compile time. Overflow and division by
  zero are errors.
- A char literal (`'a'`, `'\n'`, `'\x41'`) is a `u8` constant.

**Implicit conversions.** Only these happen without `as`:

| From                 | To                                              |
|----------------------|-------------------------------------------------|
| an integer           | a wider integer of the same signedness          |
| an unsigned integer  | a wider signed integer                          |
| `f32`                | `f64`                                           |
| any pointer          | `*void`                                        |
| `*[N]T`, `[N]T`      | `[]T`: a view of the array                      |
| `[..]T`              | `[]T`: a view of its elements                   |
| `usize`, `isize`     | `u64`, `i64`                                    |
| a failure enum (a plain enum with a variant equal to 0) | `Error`: which enum and which variant (see [Handling errors](#handling-errors)) |

`usize` and `isize` are distinct from `u64` and `i64`. They convert to them
implicitly, since a pointer-sized integer fits in 64 bits on every target,
but converting the other way needs `as`.

`isize` and `usize` don't convert to each other without `as`. Lengths are
`isize`, and unsigned types are for bit work and C: C's `size_t` is `usize`,
so a length passed to C takes a cast, `memcpy(dst, src, s.len as usize)`.

**Casts (`x as T`)** also allow:
- numbers to numbers (integer casts wrap, like C)
- integers to and from enums
- `bool` to an integer
- between pointer types, `*void` and functions
- pointers to and from `usize` or `isize`
- `string` and `[]u8` to each other: the same memory, as text or as bytes
- `[..]u8` to `string`: a view of its elements, as text

**Operators:**
- `+ - * /` need numbers of one type.
- `% & | ^` need integers.
- `<< >>` take any integer shift amount, and the result has the left
  operand's type.
- `== !=` work on numbers, bools, enums, pointers and strings (by
  content). Structs, arrays, slices, `[]u8` and tagged enums have no `==`:
  compare their fields, or use std/reflect's `values_equal(a, b)`, which
  works on any type. A tagged enum's variant compares with `e.tag == .Nil`
  or `e is .Nil`.
- `< > <= >=` work on numbers, enums and pointers.
- `&& || !` need `bool`.
- **Pointer arithmetic** counts in what the pointer points at, as `p[i]`
  does, so `p + n` is `&p[n]`:
  - `p + n`, `n + p` and `p - n` take any integer and give a pointer of
    `p`'s type; `p += n`, `p -= n`, `p++` and `p--` move `p` the same way.
  - `q - p` is how many values lie between two pointers of the same type,
    an `isize`.
  - Adding two pointers, or subtracting a pointer from a number, is an
    error. A `*void` doesn't move: cast it to `*u8` to count in bytes.
  - Nothing checks where the pointer ends up: past the memory it points
    into is C's undefined behaviour. A slice (`p[0..n]`) is checked.

**Conditions** in `if`, `while`, `do` and `for` must be `bool`.

**Members:**
- `p.x` follows a pointer automatically.
- Arrays and slices have `.len`, an `isize`. A length is signed, so
  `for (let i = xs.len - 1; i >= 0; i--)` stops after 0, and doesn't run
  for an empty slice.
- Arrays and slices have `.ptr`, a `*T` to the first element. An array's
  is `&a[0]`, so like `&` it needs the array in memory: not a constant
  or a temporary. Through a pointer, `p.ptr` on a `*[N]T` is `p` as a
  `*T`, for C functions and `p[i]` over the elements.

**Assignment.** You can assign to variables, parameters, fields, indexed
elements and `p.*`. You can't assign to constants, `for (x in ...)` loop
variables, `.len` or `.ptr` of an array or slice (a growable array's can
be set), or temporaries. `&x` needs something assignable.

**Functions:**
- A function that returns a value must return on every path. An infinite
  loop with no `break` counts.
- Calls check argument count and types.
- A call can be a statement on its own, and its results are dropped,
  unless the function is `#nodiscard` (see
  [Handling errors](#handling-errors)). Any other expression as a
  statement (`x + 1;`) is an error, unless it's dropped with `_ = x + 1;`.
- Arguments that fill a C variadic `...` get their default types, except
  that string literals are passed as `*u8` and an untyped integer constant
  that fits is an `i32`, C's `int`: `printf("%d", 5)`. Other values pass with
  their own type, so an `isize` needs `%td` (or `%ld`).

**Top level:**
- Top-level constants and global initializers must be known at compile time:
  scalars, string literals, `null`, function names, or array and struct
  literals made of those.
- A struct can't contain itself except through a pointer.
- Struct layout follows C: fields in order, each aligned to its size.

**Switch.** A `switch` works on integers, enums, tagged enums and strings.
Case values must be constants and can't repeat or overlap. Without a
`default`:
- a switch on an enum must handle every variant; the error lists the ones
  it's missing. Variants with the same value count once. With patterns
  inside variants, or guards, the error shows a value no case handles
  (see [Every value handled](#patterns)).
- such a switch counts as returning when every case returns, so a function
  ending in it needs no `return` after it
- a value that isn't one of the variants (made with `as`) panics at run
  time instead of running no case
- a switch on an integer or a string can leave values out, as in C; as an
  expression it needs a `default`, since it must give a value

## Strings, bytes and builders

Text and bytes come in five shapes. They're all bytes in memory; what
differs is who owns the memory and whether it can grow.

| Type | What it is | Owns its memory | Grows | Prints as | `==` |
|---|---|---|---|---|---|
| `string` | text: a pointer and a length | no, a view | no | its text, `hi` | by content |
| `[]u8` | bytes: a pointer and a length | no, a view | no | numbers, `[104, 105]` | none |
| `[N]u8` | `N` bytes, stored in place | yes, it's a value | no | numbers | none |
| `[..]u8` | bytes that grow: `{ptr, len, cap, allocator}` | yes, its elements | `array_add`, `append_string`, `print_to` | numbers | none |
| `Builder` | text that grows: a `[..]u8` inside | yes | `builder_append`, `builder_print` | (use `builder_string`) | none |

**Which to use:**
- Take and return **`string`** for text: names, lines, messages, paths.
  It's what literals are, what std's text functions take, and what
  `read_file` returns.
- Use **`[]u8`** for data that isn't text: a file's raw bytes, a buffer
  for C, a hash's input.
- Use **`[N]u8`** for a fixed buffer on the stack, with no allocation:
  `let buf: [256]u8 = ---;`.
- Use **`Builder`** to build text a piece at a time, then hand out
  `builder_string(&b)`.
- Use **`[..]u8`** to collect bytes that aren't text.

```
let name = "ada";                          // a string literal: lives forever
let line = copy_string(name);              // a string you own (context.allocator)
defer free(line.ptr);

let b: Builder;                            // zero: ready to use
defer builder_free(&b);
builder_append(&b, "hello, ");
builder_print(&b, "% (% chars)", name, name.len);   // std/fmt: formatted
println(builder_string(&b));               // hello, ada (3 chars)

let buf: [64]u8 = ---;
let n = copy_bytes(buf[..], "abc" as []u8);         // bytes into the buffer
println(buf[..n] as string);               // abc

let raw: [..]u8;
append_string(&raw, "hi");                 // std/str: text onto bytes
println("% %", raw as string, raw);        // hi [104, 105]
print_to(&raw, " %", 42);                  // std/fmt: formatted, as builder_print
println(raw as string);                    // hi 42
```

### `string`

`string` is text: a pointer and a length, laid out exactly like `[]u8`,
but a type of its own. A string literal is one.

```
let s = "hello";                 // a string
if (s == "hello") { ... }        // == and != compare the contents
let first = s[0];                // a u8: indexing is by byte
let part = s[1..3];              // "el": part of a string is a string
for (c in s) { ... }             // each byte
println("%", s.len);             // 5: bytes, an isize

switch (word) {                  // switch on strings: cases are literals
case "fn":  return .Fn;          // or constants, compared by content
case "let", "const": return .Let;
default:    return .Name;        // no default needed, but usually wanted
}
```

- `.len` counts bytes, and `s[i]` is the i-th byte, bounds-checked. Text
  is usually UTF-8, so a byte isn't always a character.
- Strings aren't NUL-terminated, and can hold NUL bytes. A C function that
  wants a `char *` takes a literal as it is (`printf("hi\n")`); any other
  string needs a copy with a NUL at the end, `to_cstring(s)`, and a
  `char *` from C becomes a string view with `from_cstring(p)`.
- Only `==` and `!=` compare strings: order them with
  `compare_strings(a, b)` (std/str), or sort with `string_less`.
- A string literal can span lines, and its newlines are part of it.
  Escapes: `\n` `\t` `\r` `\0` `\\` `\'` `\"` and `\xNN`.

**A string is a view**, as in Jai: it doesn't own its memory, and nothing
frees it on its own. Whoever made it does:

| Made by | Lives until | Freed with |
|---|---|---|
| a literal, `"hi"` | the program ends | nothing |
| `copy_string`, `format`, `join`, `read_file` | you free it | `free(s.ptr)` or `delete(s)` |
| `tformat` | the temp allocator is freed | `free_all(context.temp_allocator)` |
| `builder_string(&b)` | the builder grows or is freed | `builder_free(&b)` |
| slicing, `trim`, `cut`, `split`'s parts | what it's a view of is freed | nothing: free the original |
| `from_cstring(p)` | C frees `p` | C's rules |

So `trim(line)` costs nothing, and the result dies with `line` (see
[trap 6](#memory-traps)).

**Strings are writable**, like any view, as in Jai: `s[0] = 'J'` writes to
the bytes it points at. Two consequences:

- **Writing to a string literal is a bug the compiler doesn't catch.** A
  literal's bytes are read-only, but a `string` doesn't say where its bytes
  are, so the write compiles:

  ```
  let s = "hello";
  s[0] = 'J';                      // compiles
  ```

  In the program, literals are in read-only memory, so the write crashes:
  a segmentation fault (exit code 139), as in C. In `#run` code it doesn't
  crash, which hides the bug: the write goes through and stays, so the
  next time that code runs, its literal holds the changed bytes.
- **Writing through a view changes the text every other view shows**,
  since they share the bytes: `parts[0][0] = 'X'` after
  `let parts = split(line, ",");` changes `line` too.

To change text, write to memory you own: a copy (`let c =
copy_string("hello"); c[0] = 'J';`), a `Builder`, or a `[N]u8` buffer.

### Bytes and text

Text and bytes are the same memory seen two ways, and converting costs
nothing, but neither way happens on its own, as in Jai: `bytes as string`
reads bytes as text, and `s as []u8` treats text as bytes (`"abc" as []u8`
for a literal). So a function's types say which one it works with, and
every place that turns one into the other shows it.

```
fn checksum(data: []u8) -> u32 { ... }

checksum(text as []u8);              // text as bytes
let shown = data[0..4] as string;    // bytes as text
let word = buf[..n] as string;       // a [N]u8 buffer: through a slice
let built = raw as string;           // a [..]u8: a view of its elements
```

- An array of bytes reads as text through a slice: `buf[..n] as string`.
  A growable one converts directly, `raw as string`, a view of its
  elements like the `[]u8` it passes as.
- A `string` prints as text and a `[]u8` as numbers.
- `==` compares strings by content; two `[]u8` have no `==`, and bytes
  with text compare as text: `b as string == "abc"`.

The compiler says how to convert when one is used for the other:

```
takes_bytes(text);     // error: expected `[]u8`, found `string`; the same memory
                       //   converts with `text as []u8`
takes_text(buf);       // error: expected `string`, found `[5]u8`; view it as text
                       //   with `buf[..] as string`
let same = b == "abc"; // error: `==` doesn't compare bytes with text; compare them
                       //   as text: `b as string`
let o = text < "b";    // error: `<` needs numbers, enums or pointers, found `string`;
                       //   order strings with compare_strings(a, b) from std/str
```

### `Builder`

A `Builder` (std/str) is text built a piece at a time. Its bytes are a
growable `[..]u8`, so it owns them, and a zero one is ready to use: it
grows with `context.allocator`, or with the allocator `make_builder(a)`
was given.

```
fn describe(names: []string) -> string {   // a new string: the caller frees it
    let b: Builder;
    for (i in 0..names.len) {
        if (i > 0) builder_append(&b, ", ");
        builder_print(&b, "%. %", i + 1, names[i]);
    }
    return builder_string(&b);             // the builder's memory, handed over
}

let text = describe(.["ada", "alan"]);     // 1. ada, 2. alan
defer free(text.ptr);
```

| Function | Does |
|---|---|
| `make_builder(a)` | an empty builder that grows with `a` |
| `builder_append(&b, s)` | adds a string |
| `builder_append_char(&b, c)` | adds one byte |
| `builder_print(&b, fmt, ..)` | adds formatted values (std/fmt), as `print` writes them |
| `builder_string(&b)` | a view of the text so far |
| `builder_clear(&b)` | empties it, keeping the memory |
| `builder_free(&b)` | frees the memory, and empties it |

- `builder_string(&b)` is a view, valid until the builder next grows or is
  freed. To keep the text after freeing the builder, copy it:
  `copy_string(builder_string(&b))`. Or don't free the builder, and free
  the text later with `free(text.ptr)`: it's the same memory.
- Copying a `Builder` copies its fields, so both copies share the bytes
  ([trap 8](#memory-traps)): pass a `*Builder` to functions that add to
  it.
- `format(fmt, ..)` (std/fmt) is a builder in one call: a new string from
  `context.allocator`. `tformat` does the same in the temp allocator.

### std/str

std/str has the usual operations, mostly returning views of their input:
`equal`, `starts_with`, `ends_with`, `index_of`, `index_of_char`
(`-1` when missing), `contains`, `trim`, `cut(s, sep)` (the text before
and after the first `sep`, and whether there was one), `split(s, sep)`
(views, in a new slice), `join(parts, sep)` (a new string),
`copy_string`, `to_cstring` and `from_cstring` for C, `format_int` and
`format_uint` (into a buffer, no allocation), and `parse_int`,
`parse_uint`, `parse_float`, `parse_bool`, which fail with a
`ParseError` (see [Handling errors](#handling-errors)).

## Tagged enums

An enum whose variants hold values is a tagged enum (a sum type, like
Rust's enums or OCaml's variants). A value is one of the variants, together
with what that variant holds:

```
enum Expr {
    Number(i64),                             // holds one value
    Binary(op: Op, lhs: *Expr, rhs: *Expr),  // holds fields
    Negate(*Expr),
    Nil,                                     // holds nothing
}

let a = Expr.Number(42);
let b: Expr = .Binary(.Add, &x, &y);         // fields in order
let c: Expr = .Nil;
```

**Making a value:** `Expr.Number(42)`, or `.Number(42)` where an `Expr` is
expected. The arguments fill a variant's fields in order; fields with a
default (`Rect(w: f64, h: f64 = 1)`) can be left off the end. A variant that
holds nothing is just `Expr.Nil`.

A variant with fields can also be made like a struct, its fields by name
(or in order) in braces right after it, the rest defaulted:

```
let r = Shape.Rect{ .w = 2 };                // h: its default, 1
let e: Expr = .Binary{ .op = .Add, .lhs = &x, .rhs = &y };
```

The braces follow the variant without a dot (`T.{ ... }` is a struct's), and
only a variant with fields takes them: `Expr.Number{ 1 }` is an error that
says to write `Expr.Number(1)`.

**Getting the value out** is what `switch` (or `is`, see
[Patterns](#patterns)) does. A case names a variant and a binding for what
it holds, or for its fields:

```
fn eval(e: *Expr) -> i64 {
    switch (e.*) {
    case .Number(n): return n;               // n: i64, a copy
    case .Binary(b): return apply(b.op, eval(b.lhs), eval(b.rhs));
    case .Negate(inner): return -eval(inner);
    case .Nil: return 0;
    }                                        // every variant: no return needed
}

switch (e.*) {
case .Number(&n): n.* += 1;                  // &n: a pointer into the value
case .Binary{op, lhs, rhs}: ...              // the fields, by name
case .Call{callee: f, &args}: ...            // field: name, or & for a pointer
default:
}
```

- A binding is a copy of the variant's value: an `i64` for `Number`, a
  struct with fields `op`, `lhs` and `rhs` for `Binary`.
- `&n` binds a pointer instead, to change the value in place. The switch's
  operand must then be a variable (or `p.*`, `xs[i]`, ...).
- A case that binds names one variant. Cases without a binding can name
  several: `case .Binary, .Negate:`.
- The rules for every `switch` on an enum apply: without `default`, every
  variant must be handled.

**The tag.** `e.tag` is which variant `e` is, as a plain enum (called `Expr.Tag`
in messages)
with the same variant names, so `if (e.tag == .Nil)` and `switch (e.tag)`
work. It's read-only: change the variant by assigning a whole new value.

**`e.Variant`** takes a variant's value out: `o.Some`, `e.Number`, or for
one with fields their struct, `e.Binary.op`. It's a place: `p.Number += 1`
through a pointer, `n.kind.Switch.continued = true`. When `e` is another
variant it panics, `file:line:col: panic: the value isn't .Number`, like
an index out of bounds, and under the same setting as bounds checks; in
`#run` code it's a compile error.

```
if (n.kind !is .Switch) return;
let s = n.kind.Switch;                       // checked
```

**Narrowing** drops the check where the compiler knows the variant:

```
if (o is .Some) println("%", o.Some);        // no check: it's .Some here
if (e is .Number && e.Number > 9) { ... }    // and on the right of &&
if (s !is .Rect) return 0;
return s.Rect.w * s.Rect.h;                  // no check after leaving
```

The compiler knows it after `if (x is .V)` (in the body, and on the right
of `&&`), and after `if (x !is .V)` whose body leaves (`return`, `break`,
`continue`). Only for a local, a parameter, or a field of one reached
without a pointer, and only when the function never assigns it or takes
its address, so nothing can change it in between; through a pointer the
check stays.

**Generic tagged enums** take type parameters like generic structs:

```
enum Result($T, $E) { Ok(T), Err(E) }
enum Pair($A, $B) { Both(A, B), Neither }

fn first(r: Result($T, $E), fallback: T) -> T { ... }  // T and E are inferred
```

`Result.Err(e)` alone doesn't say which `Result` it is, so write `.Err(e)`
where the type is known (a variable's type, a parameter, a `return`).

**`?T`, an optional value.** The prelude declares

```
enum Option($T) { None, Some(T) }
```

and `?T` is short for it: `?i64` is `Option(i64)`, and messages write it
`?i64`. `None` comes first, so a new one (a `let`, a struct field, a
zeroed allocation) is empty. `or_else` takes its value, or a fallback for
`None`, and `is` matches it:

```
fn find(items: []isize, x: isize) -> ?isize {
    for (item, i in items) if (item == x) return i;   // .Some(i)
    return .None;
}

let at = find(xs, 4) or_else -1;               // the index, or -1
if (find(xs, 4) is .Some(i)) println("at %", i);

struct Config { port: ?isize; }                // not set until it's .Some
let port = cfg.port or_else 8080;
```

- **A value wraps itself**: where a `?T` is expected, a value that fits `T`
  becomes `.Some(value)`: `let o: ?i64 = 5;`, `return i;`, `f(.{ .x = 1 })`
  for a `?Point` parameter. `null` doesn't wrap (it could mean either):
  write `.None`, or `.Some(null)` for a null pointer inside.
- A missing value isn't a failure, so `or_return` doesn't take a `?T`.
  Failures are bools and enums (see [Handling errors](#handling-errors)).
- Pointers don't need it: a `*T` can already be null, and `or_else` takes
  a pointer too (below). `?*T` is allowed, but rarely what you want.
- `?T` is always the prelude's `Option`, even in a module that declares
  its own `Option`. A generic parameter can take one: `fn f(o: ?$T)`.

**Layout.** A tagged enum is a C struct of the tag (`i32` unless the enum
says `: u8` etc.) and a union of the variants' values, so it's as big as
the tag plus its largest variant. A new one (`let e: Expr;`) is its first
variant, holding that variant's defaults, or zeros.

## Patterns

A `case` (and `is`, below) matches a **pattern**:

| Pattern | Matches |
|---|---|
| `5`, `'x'`, `.Red`, `"fn"`, `MAX` | that value (a constant) |
| `'a'..='z'` | a range, both ends included |
| `0..32` | a range, the end left out (as `..` is everywhere) |
| `.Number(n)` | a tagged enum's variant, naming what it holds |
| `.Binary{op, lhs: left, &rhs}` | a variant, naming its fields: `op` as `op`, `lhs` as `left`, a pointer to `rhs` |
| `.Number(0)`, `.Binary{op: .Mul, lhs: .Number(_)}` | a variant whose value or fields match patterns of their own |
| `.Number(_)`, `.Binary{op: _}` | `_` names nothing: anything matches |

Ranges are for integers and characters. Cases can't repeat or overlap, and
a `switch` on an enum without `default` must handle every variant.

**Patterns inside patterns.** Where a name for a variant's value or field
can go, a pattern can too, so a case can look down several levels. A
pattern for a pointer field matches what it points at, as `p.x` follows a
pointer, and a null pointer matches nothing:

```
fn simplify(e: *Expr) -> Expr {
    switch (e.*) {
    case .Binary{op: .Mul, lhs: .Number(0)}:      return .Number(0);
    case .Binary{op: .Add, lhs, rhs: .Number(0)}: return lhs.*;
    case .Negate(.Negate(inner)):                 return inner.*;
    case .Number(n) if (n > MAX):                 return .Number(MAX);
    default:                                      return e.*;
    }
}
```

**Guards.** `case .Number(n) if (n > MAX):` matches only when the guard,
a `bool`, is true; the guard sees the pattern's names. A case that doesn't
match goes on to the next one, so cases with guards or inner patterns are
tried in order. A guarded case doesn't count toward handling every value.

**Every value handled.** With inner patterns and guards, the compiler
checks the switch with Maranget's algorithm (as OCaml and Rust do), and
its error shows a value no case handles, such as `.Negate(.Negate(_))`.
It also reports a case that can't be reached, because the cases before it
already match everything it does.
A value that slips through anyway (a null pointer inside it, or a value
made with `as`) panics when no `default` takes it.

```
enum Expr { Number(i64), Binary(op: Op, lhs: *Expr, rhs: *Expr), Negate(*Expr), Nil }

let a = switch (e) {
case .Number(_): 1;
case .Binary(_): 2;
case .Negate(.Number(_)), .Negate(.Binary(_)), .Negate(.Nil): 3;
case .Nil: 4;
};     // error: this switch doesn't handle `.Negate(.Negate(_))` of `Expr`;
       //   add a case for it, or a `default`

let b = switch (e) {
case .Number(n) if (n > 0): 1;      // a guard can fail, so it covers nothing
case .Binary(_), .Negate(_), .Nil: 2;
};     // error: this switch doesn't handle `.Number(_)` of `Expr`; ...

switch (e) {
case .Number(_): ...
case .Number(0): ...   // error: this case can't be reached: the cases before it
default: ...           //   already match everything it does
}
```

The other mistakes a pattern can have:

```
case .Number(n) if (k):       // error: a guard needs a `bool`, found `i64`
case .Binary{op: .Sub}:       // error: enum `Op` has no variant `Sub`
case .Binary{nope: .Mul}:     // error: `.Binary` has no field `nope`
case .Circle{r}:              // error: `.Circle` holds a `f64`, which has no fields;
                              //   name it with `.Circle(x)`
case .Red..=.Green:           // error: a range in a pattern needs integers (or characters)
case 5..5:                    // error: this range is empty; `..` leaves its end out,
                              //   `..=` includes it
case 1..=10: ... case 8..=12: // error: this case overlaps an earlier one
case "a": ... case "a":       // error: duplicate case "a"
case name:                    // error: a case of a string switch must be a string
                              //   known at compile time
```

```
switch (c) {
case 'a'..='z', 'A'..='Z', '_': return lex_name();
case '0'..='9':                 return lex_number();
case ' ', '\t', '\n':           skip();
default:                        fail();
}
```

**`is`** matches one pattern, and is `true` or `false`:

```
if (e is .Number(n) && n > 100) { ... n ... }    // n exists where it matched
if (tok is .Name{text} && text == "fn") { ... }
while (it is .Some(node)) { ...; it = node.next; }
if (c is 'a'..='z') { ... }
let empty = list is .Nil;                        // no names: anywhere
```

A pattern after `is` can name what it matches only in an `if`'s or
`while`'s condition, joined to the rest with `&&`, so the names exist
exactly where the match succeeded: the rest of the condition and the body
(not the `else`).

```
let a = s is .Circle(r);           // error: `is` can only name a variant's value in an
                                   //   `if` or `while` condition (joined with `&&`),
                                   //   where it's known to match
if (s is .Circle(r) || n > 0) {}   // error: the same: with ||, r might not exist
let b = s is .Circle(_);           // fine: names nothing
```

**`!is`** is the opposite, `!(e is pattern)`, for leaving early:

```
if (n.kind !is .Switch) return;
if (o !is .Some) return -1;
if (c !is 'a'..='z' && c != '_') { ... }
```

Its pattern can't name anything: where `!is` is true, the value isn't
that variant.

```
if (e !is .Number(n)) return;      // error: `!is` can't name a variant's value: where it's
                                   //   true, the value isn't that variant
```

### `switch` as an expression

In a value's place, each case gives a value instead of running statements:

```
let precedence = switch (op) {
case .Or:        1;
case .And:       2;
case .Add, .Sub: 4;
case .Mul, .Div: 5;
};
let k = switch (word) { case "fn": 1; case "let", "const": 2; default: 0; };
```

It must give a value for everything: an enum's every variant, or a
`default`. The cases' values have the type the context wants, or the first
case's.

```
let p = switch (n) { case 1: 10; };   // error: a switch expression needs a `default`:
                                      //   there's no case for every `i32`
let q = switch (w) { case "a": 1; case "b": "two"; default: 0; };
                                      // error: expected `isize`, found `untyped string`
return switch (e) { case .A: g(); 1; case .B: 2; };
     // error: a switch expression's case is one value; to run statements first, label
     //   the switch (`s: switch (...)`) and give the value with `break s = value;`
```

### Labeled switches

A switch can have a label too. `break name;` leaves it, and `continue name = value;` runs it again with a new value, so a state
machine needs no loop around it (as in Zig):

```
state: switch (State.Start) {
case .Start:
    if (at_end()) continue state = .Done;
    continue state = .Word;
case .Word:
    take_word();
    continue state = .Start;
case .Done:
    break state;
}
```

The switch works on a copy of its value, which `continue` replaces, so its
cases can't bind with `&`.

```
state: switch (n) {
case 0: continue state;            // error: `continue state` runs the switch again, so
                                   //   it needs the next value: `continue state = value;`
case 1: continue state = 2;        // fine
default:
}
outer: for (i in 0..3) {
    continue outer = 1;            // error: `outer` is a loop: only a labeled switch
}                                  //   takes a value with `continue`
```

### `if` as an expression

In a value's place, `if (c) a else b` is one of
two values, and only the chosen one is evaluated. The `else` is required.
The values have the type the context wants; without one, an untyped value
follows a typed one (`if (c) x else 0` with `x: u8` is a `u8`), and two
that don't agree are an error. `is` in the condition binds names for the
first value:

```
let sign = if (x < 0) -1 else 1;
let radius = if (shape is .Circle(r)) r else 0.0;
const BITS = if (POINTER_SIZE == 8) 64 else 32;  // a constant: it folds
```

```
let a = if (x) 1 else 2;           // error: an `if` needs a `bool` condition, found `i64`
let b = if (x > 0) 1 else "one";   // error: the `if`'s two values don't agree: `isize`
                                   //   and `string`; give the result a type, or convert
                                   //   one with `as`
return if (x) 1;                   // error: expected `else` and a second value: an `if`
                                   //   that gives a value needs both
```

At the start of a statement, `if` is always an `if` statement, as in C.

### Labeled blocks and switches give values

A labeled block used as an expression runs its statements, and `break name = value;` leaves it with
its value. A labeled switch expression's case can be statements the same
way, and a single value still works:

```
let size = sz: switch (shape) {
case .Circle(r): 3.14159 * r * r;
case .Rect{w, h}:
    if (w < 0 || h < 0) println("negative rect: % x %", w, h);
    break sz = w * h;
case .Dot: 0;
};

let workers = parse_int(text) or_else w: {
    println("bad worker count '%', using 1", text);
    break w = 1;
};
```

- The values have the type the context wants, or the first one's.
- A block or case of statements that can reach its end without
  `break name = value;` is an error, as is a plain `break` or `continue`
  directly inside it: that would leave without a value.
- `return`, and `break` or `continue` to a label outside, still work from
  inside, and defers run as the block is left.
- An unlabeled switch expression's cases stay one value each. A value case
  that starts with `if` is an `if` statement in a labeled switch; give
  that value with `break name = if (...) a else b;`.

```
let c = blk: {                     // error: this block can reach its end without giving
    if (x > 0) break blk = 1;      //   a value; end it with `break blk = value;`
};
let d = only: { return 5; };       // error: this block never gives a value: no
                                   //   `break only = value;` in it
let g = sw: switch (e) {
case .A: 1;
case .B: println("b");             // error: this returns nothing, so it can't be the
};                                 //   case's value; to run it first, end the case
                                   //   with `break sw = value;`
let h = m: { if (x > 0) break m = 1; break m = "two"; };
                                   // error: expected `isize`, found `untyped string`
```

The rules for `break` to a block are under
[Name resolution](#name-resolution).

## Several results

A function can return several values: their types go in parentheses, and
`return` gives the values separated by commas.

```
fn divide(a: i64, b: i64) -> (i64, i64) {
    return a / b, a % b;
}

let q, r = divide(17, 5);          // 3 and 2
let _, rest = divide(17, 5);       // `_` drops a value
let x, y = 0, 1;                   // several expressions
q, r = r, q;                       // several targets: a swap
```

- `return` gives one value per result, from the left; results at the end
  that have a default can be left out (below). `return g();` passes on
  the results of a function that has the same ones.
- `let a, b = ...` declares a name per value, typed by its value. The
  values are one call with that many results, or that many expressions.
  To give names a type instead, `let a, b, c: *Node;` (in a function)
  declares each with it, starting as its zero, or its defaults; values and
  a type together are declared one name at a time.
- `a, b = ...` assigns the same way, with `=` only. Every value is worked
  out before any target is assigned, which is what makes `a, b = b, a` a
  swap. A result converts to its target's type as a single value would
  (`u8` to `i64`), except to `Any`.
- `_` takes a value and drops it, in `let` and in assignments; `_ = f();`
  drops all of a call's results (see `#nodiscard` in
  [Handling errors](#handling-errors)).
- **A void result is left out.** `-> (void, IoError)` is the same
  signature as `-> IoError`, so a generic `fn() -> ($T, IoError)` takes a
  function returning just `IoError`, with `T = void`:

  ```
  fn retry(times: i32, f: fn() -> ($T, IoError)) -> (T, IoError) {
      let result, err = f();         // with T = void, `result` is void
      for (i in 1..times) {
          if (err == .None) break;
          result, err = f();
      }
      return result, err;            // ... and left out of the return
  }

  let text = retry(3, load_text) or_return;   // T = string
  retry(3, flush_cache) or_return;            // flush_cache returns IoError
  ```

  A `let` or an assignment can still name the void: a name the callee's
  type spells as void, or a target of type void, takes nothing.
  `return` leaves out `.{}` and plain void values (names, fields, `p.*`);
  a void call isn't left out, since it has to run: call it before the
  `return`.
- **Results are taken from the left**, as in Jai, and what isn't taken is
  dropped:

  ```
  fn parse_prefix(s: string) -> (i64, isize, ParseError)

  let n, used, err = parse_prefix(s);   // all three
  let n, used = parse_prefix(s);        // the failure is dropped
  let n = parse_prefix(s);              // just the number
  let _, _, err = parse_prefix(s);      // `_` to reach a later one
  total += parse_int(s);                // in an expression: its first value
  parse_int(s);                         // a statement: all dropped
  ```

  A call with several results used as one value (an operand, an
  argument, `let x =`) is its first value. A `#nodiscard` function's
  results can't be dropped this way (see
  [Handling errors](#handling-errors)). `a, b` written out is still two
  values: `let x = 1, 2;` is an error.
- **A result can have a default**, as in Jai: `return` can leave out the
  results at the end that have one, and a function whose results all
  have one may reach its end without a `return`, which returns them.

  ```
  fn parse_digit(c: u8) -> (i64, ParseError = .None) {
      if (c < '0' || c > '9') return 0, .Invalid;   // a failure, written in full
      return (c - '0') as i64;                       // the failure: its default
  }

  fn find(xs: []$T, x: T) -> (isize = -1, bool = false) {
      for v, i in xs {
          if (v == x) return i, true;
      }
  }                                                  // the end: -1, false
  ```

  - Only results at the end can be left out, since values go from the
    left: in `-> (*User = null, LookupError = .None)`, a failure is
    `return null, .NotLoaded;`.
  - `or_return` fills the function's other results with their defaults
    (`-> (isize = -1, ParseError = .None)` returns -1 with the failure).
  - A default is worked out where it's used, so it can use the
    parameters: `-> (string = s, bool = true)`.
  - `return g();` where g gives one value takes the rest from defaults.
  - A function type can't have them (`fn() -> (i64, bool)`), nor can an
    `extern` or `#expand` function.
- In C the results are a struct, which `return` makes and the caller takes
  apart, so several results cost what returning a struct does. An `extern`
  function (C returns one value) and an `#expand` function return one value
  at most. Function types can have several: `fn(string) -> (i64, bool)`.

A function that can fail returns its failure as its last result; see
[Handling errors](#handling-errors).

## Handling errors

Two kinds of things go wrong, and Sabk handles them differently:

- **Failures** are what a correct program expects to happen sometimes: a
  file that isn't there, a number that doesn't parse, a key that isn't in
  a map. The function returns the failure as a value, and its caller
  decides what to do.
- **Bugs** are what shouldn't happen: an index out of range, a broken
  invariant, a null where there can't be one. The program stops, with
  the file and line: `panic`, `assert`, and the runtime's checks.

There are no exceptions, and nothing is thrown or caught: a failure is an
ordinary value, and everything that can fail says so in its type.

### Failure values

A function that can fail returns what it made and, last, whether it
worked. That last value is

- a **`bool`**, `true` when it worked, when there's only one way to fail:
  `get_env` (it isn't set), `map_get` (the key isn't there); or
- an **error enum**, `enum IoError: Error { NotFound, ... }`, whose
  variants say what went wrong. Its `None`, 0, means it worked: it comes
  from `Error`, so it's there without writing it.

| Function | Fails with |
|---|---|
| `read_file`, `write_file`, `append_file`, `delete_file` (std/io) | `IoError`: `.None`, `.NotFound`, `.PermissionDenied`, `.IsDirectory`, `.NotDirectory`, `.AlreadyExists`, `.NoSpace`, `.Other` |
| `parse_int`, `parse_uint`, `parse_float`, `parse_bool` (std/str) | `ParseError`: `.None`, `.Empty`, `.Invalid`, `.OutOfRange` |
| `get_env` (std/os), `map_get`, `static_map_get` (std/map), `cut` (std/str) | `bool` |

**std logs why it failed**, as Jai's modules do: a std function that
fails calls `log(.Error, ...)` with the details, and returns the failure
for its caller to act on. One failure, one message: passing it on with
`or_return` doesn't log it again.

```
let text, err = read_file("app.cfg");
// stderr: error: can't read app.cfg: no such file or directory
```

The functions that log: `read_file`, `write_file`, `append_file`,
`delete_file` (std/io), `make_dir`, `remove_dir`, `make_temp_dir`,
`current_dir` (std/fs), `path_absolute`, `path_real` (std/path),
`run_command` and `run_shell` (std/process). The parse functions
(`parse_int`, `parse_uint`, `parse_float`, `parse_bool`) log theirs as
warnings, `warning: "12x" isn't an integer`, since a fallback on purpose
(`parse_int(arg) or_else 8080`) is common: `context.log_level = .Error`
quiets them for a block. Your own I/O code can do
the same with `log_io_error(err, "read", path)`, which logs and gives
`err` back. A caller that expects a failure quiets it for a block:

```
let config: Config;
let err: ConfigError;
{
    context.logger = silent_logger();   // a missing file is normal here
    config, err = load_config("app.cfg");
}
```

**Checking by hand** is a comparison:

```
let text, err = read_file(path);
if (err != .None) {
    println("using the defaults (%)", err);   // `%` alone prints NotFound
    return;
}
defer free(text.ptr);
```

When a std function fails, its other results are zeros (an empty string
with a null pointer, 0, null), so freeing them is harmless, but don't use
them for anything else. `cut` is the exception: when the separator isn't
there, it gives back all of `s` and `""`.

**A function that returns only a failure** leaves the void out:
`write_file(path, data)` returns just an `IoError` (see
[Several results](#several-results)).

### `or_return`: pass the failure on

```
fn copy_file(from: string, to: string) -> IoError = .None {
    let data = read_file(from) or_return;    // an error: return it
    defer free(data.ptr);
    write_file(to, data) or_return;          // only a failure: no value
}                                            // the end: None

fn average(texts: []string) -> (i64, bool) {
    let total = sum_numbers(texts) or_return;  // a bool: returns false
    return total / texts.len as i64, true;
}
```

- **`f() or_return`** is f's values without the last. When the last says
  f failed, the function it's in returns right away: that value as its
  last result, and its other results their defaults, or as `let x: T;`
  starts them (zeros, or field defaults) where they have none. Defers
  run, as for `return`.
- The function's last result must have the failure's type, or be
  `Error`: a `ParseError` passes on from a function returning a
  `ParseError` or an `Error`, a `bool` from one returning a `bool`. A
  different type is an error; return `Error` (below), or turn one failure
  into the other by hand.
- It works on a function that returns only the failure, too:
  `write_file(path, data) or_return;`.
- It binds like a call: `parse_int(s) or_return + 1`.
- Inside a block passed to a macro (`with_allocator(a) { ... }`) it
  returns from the function that wrote the block, running the macro's
  defers on the way, as `return` does there. It can't be used in an
  `#expand` function's own body (it would return from the function using
  the macro), in a `defer`, or in a `#run` expression.

### `or_else`: a fallback instead

```
let home = get_env("HOME") or_else "/";
let port = parse_int(arg) or_else 8080;
let n = parse_int(a) or_else parse_int(b) or_else 0;   // tries a, then b

let workers = parse_int(text) or_else w: {   // run code first: a labeled block
    log(.Warning, "bad worker count '%', using 1", text);
    break w = 1;
};
```

- **`f() or_else fallback`** is f's value, or `fallback` when f failed. f
  returns exactly two values: the value and the failure.
- It also takes one value that may be missing: a `?T` gives its value, or
  `fallback` for `None`; a pointer gives itself, or `fallback` for null:
  `let node = map_find(&nodes, key) or_else &fallback;`.
- `fallback` is only evaluated when it's needed. It can be another
  `or_else`.
- The result has the value's type, and `fallback` must fit it. So
  `read_file(p) or_else null` is a `string` (empty, with a null pointer, on
  a failure), and going into a `?string` it would be `.Some("")`, never
  `.None`: that's an error, since `null` is a null pointer, not an
  Option's None. For `.None` on a failure, take the failure and check it.
- It binds more loosely than any other operator, so a sum needs
  parentheses: `(parse_int(s) or_else 0) + 1`.
- The fallback block can `return` instead of giving a value, which is how
  a failure of one type becomes a failure of another (below).

### `Error`: one type for every failure

`or_return` passes a failure on to a function whose last result has the
same type. **`Error`** (in the prelude) is the type every failure enum
converts to, so a function returning `Error` can pass on failures of any
enum, without knowing which ones its callees use, and `main` can too:

```
fn main() -> Error = .None {
    let content = read_file("src/main.sabk") or_return;          // an IoError becomes an Error
    defer free(content.ptr);
    let jobs = parse_int(get_env("JOBS") or_else "1") or_return;   // so does a ParseError
    ...
}                                     // the end: its default, success
```

```
$ ./sabk --run main.sabk
error: IoError.NotFound
$ echo $?
1
```

A function that mixes failures of different enums, its own included:

```
enum ConfigError: Error { BadLine, UnknownKey }

fn load_config(path: string) -> (Config, Error) {
    let config: Config;
    let text = read_file(path) or_return;                  // IoError -> Error
    defer free(text.ptr);
    for (line in split(text, "\n", context.temp_allocator)) {
        let key, value, found = cut(line, "=");
        if (!found) return config, ConfigError.BadLine;    // its own enum -> Error
        switch (trim(key)) {
        case "port": config.port = parse_int(trim(value)) or_return;   // ParseError -> Error
        default:     return config, ConfigError.UnknownKey;
        }
    }
    return config, .None;
}
```

**Handling one.** An `Error` compares with a failure enum's variant,
written with its enum's name; `%` prints it the same way:

```
let config, err = load_config("app.conf");
if (err == IoError.NotFound) {
    config = default_config();               // a missing file is fine
} else if (err != .None) {
    println("can't load app.conf: %", err);  // can't load app.conf: ParseError.Invalid
    return err;
}

let what = switch (err) {
case .None:                "fine";
case IoError.NotFound:     "no such file";
case ConfigError.BadLine:  "a line without =";
default:                   "something else";  // an Error can be any enum's
};
```

- **What converts.** An error enum (`enum IoError: Error { ... }`)
  converts to `Error` implicitly: at `or_return`, `return`, an
  assignment, an argument, a comparison, or `as Error`. Its `None` is
  `Error.None`. A tagged error enum converts by its variant, its payload
  dropped. A plain enum doesn't, and neither does a `bool`, since it
  doesn't say what failed.
- **Back is a checked match.** `let e: IoError = err;` is an error;
  `err is IoError(e)` is true when `err` came from an `IoError`, and gives
  it back. `case` takes the same pattern, and the pattern inside matches
  the variant:

  ```
  if (err is IoError(io)) println("io: %w", io);
  switch (err) {
  case IoError(.NotFound): use_defaults();
  case ParseError(p):      println("bad number: %w", p);
  default:                 return err;
  }
  ```

  `Error.None` is no enum's: it matches none of these. `error_enum(err)`
  is the `*TypeInfo` of the enum it came from (null for `None`), and
  `error_value(err)` its variant's value.
- **Precise enums stay.** std's functions return `IoError` and
  `ParseError`, so a caller that handles every case still gets an
  exhaustive `switch`. `Error` is for code that combines them.
- **`fn main() -> Error = .None`.** When it returns a failure, the program prints
  `error: IoError.NotFound` (the enum and the variant) to stderr and exits
  with 1. That happens after `main` has returned, so its defers have run.
- **`-> Error = .None` may fall off its end**, which means success, as
  any function whose results all have defaults can (see
  [Several results](#several-results)). Without the default, it needs its
  `return`.
- **Underneath** an `Error` is one 64-bit integer: a number the compiler
  gives each enum that becomes one, and the variant's value. It has no
  order and isn't a number (`<` and `+` are errors), a statement `switch`
  on one can leave values out, and a `switch` expression needs a
  `default`. The numbers can differ between builds, so don't store one in
  a file.
- A module that declares its own `Error` hides the prelude's, as for any
  prelude name.

```
let back: IoError = err;   // error: expected `IoError`, found `Error`; an `Error` turns
                           //   back into `IoError` through a check: `if (err is IoError(e))`
if (err == .NotFound) {}   // error: `.NotFound` doesn't say which enum it's from; an `Error`
                           //   compares with a failure enum's variant written in full,
                           //   like `IoError.NotFound`
let home = get_env("HOME") or_return;   // in a `-> Error` function
                           // error: `or_return` can't pass a `bool` on as an `Error`: a
                           //   `bool` doesn't say what failed; check it with `if`, or
                           //   give a fallback with `or_else`
```

### Your own failures

A function that can fail in several ways declares an error enum for them,
`enum ConfigError: Error { ... }`. Its `None` comes from `Error`: writing
it is an error. Its callers can switch on it exhaustively, and it passes
on as an `Error` too. A plain enum isn't a failure: `or_return` and
`or_else` don't take one, and it doesn't become an `Error`. To turn
another enum's failure into one of your own instead, convert by hand:

```
enum ConfigError: Error { CantRead, BadLine, BadNumber }

fn load_config(path: string) -> (Config, ConfigError) {
    let config: Config;
    let text = read_file(path) or_else r: {             // an IoError ...
        log(.Warning, "can't read %", path);
        return config, .CantRead;                       // ... becomes a ConfigError
    };
    defer free(text.ptr);
    for (line in split(text, "\n", context.temp_allocator)) {
        let key, value, found = cut(line, "=");
        if (!found) return config, .BadLine;
        let n, err = parse_int(trim(value));
        if (err != .None) return config, .BadNumber;   // the same, with a check
        ...
    }
    return config, .None;
}
```

```
fn returns_other() -> (i64, ConfigError) {
    let n = parse_int(s) or_return;   // error: `or_return` returns `ParseError` from
}                                     //   `returns_other`, but `returns_other`'s last
                                      //   result is `ConfigError`; to pass failures of
                                      //   any type on, make its last result `Error`
```

**Details about a failure** (which line, which file) don't fit in a plain
enum. Log them where the failure is found (`log(.Warning, ...)`, through
`context.logger`, so the caller decides where they go), or return them as
another result before the failure: `-> (Config, i64, ConfigError)` for
the line number. A tagged error enum carries them as a value
(`enum ConfigError: Error { BadNumber(line: i64), ... }`): `or_return`
and `or_else` take it (it failed unless it's `.None`), and `%w` prints it
whole, `ConfigError.BadNumber(line = 12)`. As an `Error` it keeps only
which variant it was.

**Dropping a failure is legal**, as in C: `write_file(path, data);`
ignores the `IoError`, and `let data, _ = read_file(path);` names that it
does. Dropping one by accident is the most common mistake with failure
values, so a function whose result must be looked at says `#nodiscard`
(Jai's `#must`, C's `[[nodiscard]]`):

```
fn save(path: string, data: string) -> SaveError #nodiscard { ... }

save(path, data);            // error: `save` is `#nodiscard`, and this drops its
                             //   `SaveError`; use it, or drop it on purpose with
                             //   `_ = save(...);`
let err = save(path, data);  // fine: used
save(path, data) or_return;  // fine: passed on
_ = save(path, data);        // fine: dropped on purpose
```

- `_ = expr;` drops any value, or all of a call's results, and says so.
  It works for any expression, not only `#nodiscard` calls.
- `#nodiscard` goes after the result type, with the other directives in
  any order (`-> i64 #nodiscard #no_bounds_check`). A macro can have it
  too; a function that returns nothing can't.
- It's checked where a call is a statement on its own, `defer` included,
  and where only some of its results are taken: `let n = counts();`,
  `let a, b = three();` and `counts() + 1` drop the rest.
  A call through a function value (`let f = save; f();`) isn't checked,
  since the value's type doesn't say.

**`--strict`** (or `set_strict(true)` in a build script, std/build) adds
two warnings, for code that wants every failure handled; without it,
dropping is Jai's: silent, and the failure is in the log.

```
parse_int(s);                    // warning: this drops `parse_int`'s failure (`ParseError`)
let n = parse_int(s);            // warning: this takes 1 of `parse_int`'s 2 results, dropping its failure
total += parse_int(s);           // the same
let x, err = parse_int(s);
total += x;                      // warning: `x` is used before `err`, the failure that
                                 //   came with it, is looked at
let y, err2 = parse_int(s);
if (err2 != .None) return;
total += y;                      // fine: err2 was looked at first
_ = parse_int(s);                // fine: dropped on purpose
```

- Only failures of an error enum or `Error` count, not a `bool`
  (`let key, value = cut(line, "=");` is fine).
- The second warning goes by the order of the source, not by every path
  through it: `err` read anywhere before `x` counts. Assigning to `err`
  (`err = g();`) makes it a failure to look at again.
- Only the program's own code is warned about, not std's.
- **`--werror`** (or `set_werror(true)`) makes the build fail when there
  are warnings, these or any other: they're printed as warnings, then
  `[error]: 2 warnings, and --werror makes warnings errors`.
- The command line and a build script add up: either one turns them on.

### Bugs: `panic` and `assert`

`panic(message)` and `assert(condition)` (std/os) stop the program with
the location:

```
assert(i < xs.len);             // file.sabk:6:12: assertion failed: i < xs.len
panic(tformat("no user %", name));   // file.sabk:9:5: panic: no user ada
```

- Both call `context.panic_handler`, which by default prints the message
  and aborts (exit code 134). A test can set its own handler (see
  [Context](#context)).
- The runtime's own checks stop the program the same way:

  ```
  xs[3]      // file.sabk:6:20: panic: index 3 is out of bounds for length 3
  a / 0      // file.sabk:7:9: panic: division by zero
  ```

  as does a `switch` with no case for its value (a value made with `as`,
  or a null pointer inside a pattern), and `new` when memory runs out.
- In `#run` code, a panic, a failed assert or a failed check is a compile
  error, with the calls that led there.

**Which to use.** Return a failure when the caller can do something about
it: bad input, a missing file, a full disk. Panic when it's the program's
own mistake, which no caller should have to check for.

### What the compiler checks

```
fn returns_nothing() { let x = get() or_return; }   // fn get() -> (i64, Fail)
     // error: `or_return` returns `Fail` from `returns_nothing`, but `returns_nothing`
     //   doesn't return anything; to pass failures of any type on, make it `Error`
let y = count() or_return;    // fn count() -> (i64, i64)
     // error: `or_return` needs the last value to say whether it failed: a `bool`
     //   (false: it failed) or an enum (anything but its 0: it failed); found `i64`
let z = no_zero() or_return;  // enum NoZero { A = 1, B = 2 }
     // error: `or_return` treats `NoZero`'s 0 as success, but `NoZero` has no variant
     //   equal to 0; add one first, like `None`
let a = three() or_else 0;    // fn three() -> (i64, i64, bool)
     // error: `or_else` needs a value and whether it's valid: two values, like
     //   `get_env("HOME") or_else "/"`; `three` gives 3 values
let c = get() or_else "text";
     // error: expected `i64`, found `untyped string`
defer get() or_return;
     // error: can't `or_return` from inside a `defer`
```

## Memory and ownership

Sabk manages memory as C does: nothing is freed on its own, and nothing
is allocated without a call. Every value is one of three kinds:

| Kind | Types | Copying it |
|---|---|---|
| **values** | numbers, `bool`, enums, structs, unions, arrays `[N]T`, tagged enums | copies everything: the copy is independent |
| **views** | pointers `*T`, slices `[]T`, `string`, `Any` | copies the pointer: both see the same memory, which neither owns |
| **owners** | `[..]T`, `Builder`, `Map` | copies the pointer to what it allocated: both copies own the same memory |

A struct is a value, but one with a view or owner in it copies that
field the same way: a `Config` with a `name: string` shares the name's
bytes with its copies.

**How long memory lives:**

| Memory | Lives until |
|---|---|
| a local variable, and a local array | the end of its block (`}`) |
| a slice literal's elements, and an array passed as a temporary slice | the function returns |
| the copy made for an `Any` | the end of the block the conversion is in |
| globals, constants, string literals | the program ends |
| memory from an allocator (`new`, `alloc`, `copy_string`, `format`, ...) | it's freed |
| memory from the temp allocator (`tformat`, ...) | `free_all(context.temp_allocator)` |
| memory from an arena | `arena_reset` or `arena_destroy` |

**Freeing.** Free memory with the allocator it came from, and free it where
it was allocated, with `defer` right after:

```
let p = new(Node);            defer free(p);
let s = copy_string(text);    defer free(s.ptr);       // or delete(s)
let xs: [..]i64;              defer array_free(&xs);   // or delete(xs)
let m: Map(string, i64);      defer map_free(&m);
let b: Builder;               defer builder_free(&b);
let a = arena_init();         defer arena_destroy(&a); // everything from it at once
```

`delete(x)` (std/mem) frees what any string, slice, growable array, `Map`
or `Builder` holds. A function that returns allocated memory says so in
its comment, and its caller frees it: `read_file`'s text, `format`'s
string, `split`'s slice (not the parts, which are views of the input).

**What the compiler catches.** A function's own memory can't leave it:
returning it, storing it in a global, or storing it through a pointer or
slice parameter is an error. It follows values through locals, into
structs and through several results:

```
fn make() -> []i32 { return .[1, 2]; }
     // error: this returns memory that's gone once `make` returns
     // note: this slice literal's elements only live until `make` returns; to keep
     //   them, allocate a copy: `clone_slice(...)` (std/mem)
fn point() -> *Point { let p: Point; return &p; }
     // note: `p` is a local, which only lives until `point` returns; to keep the
     //   value, allocate it: `new(T)` or `new(value)`
fn view() -> []i64 { let a: [3]i64 = .[1, 2, 3]; return a; }
     // note: `a` is a local array, used as a slice here, which only lives until
     //   `view` returns; to keep its elements, copy them: `clone_slice(...)` (std/mem)
fn fill(out: *Record) { out.tags = .["x"]; }
     // error: this stores memory that's gone once `fill` returns into what the
     //   parameter `out` points at, which outlives it
fn keep_it() { saved = .[4, 5]; }
     // error: this stores memory that's gone once `keep_it` returns into the global `saved`
fn as_any() -> Any { let n = 5; return n; }
     // note: the copy of this value made for an `Any` only lives until `as_any` returns
```

The check doesn't follow values into other functions, or know when heap
memory is freed; the traps below are what it misses.

**Finding the rest.** C's AddressSanitizer catches most of them while the
program runs, and reports them with Sabk's files and lines. Turn it on
with a build step:

```
#import "std/build";
#run add_c_flags("-fsanitize=address");
```

```
==64251==ERROR: AddressSanitizer: stack-use-after-scope on address 0x7b104a9f00d0
READ of size 8 at 0x7b104a9f00d0 thread T0
    ...
    #8 0x55c04287f025 in main__main /home/ada/main.sabk:12
```

### Memory traps

These compile, and read memory that was reused, freed or moved, or give
wrong values without a crash. They come from three choices Sabk shares
with C, Zig, Odin and Jai: temporary memory lives on the stack, a slice or
pointer is a bare view with no lifetime in its type, and nothing follows a
view into the functions it's passed to. (Go avoids them with a garbage
collector, Rust with lifetimes in its types.) Every output below is what
the program printed.

The compiler warns about the ones a function's own code shows (the
**Caught** column): a warning says what the memory is and how long it
lives, and doesn't stop the build. The rest only show while the program
runs: build it with **`--sanitize`** (AddressSanitizer), and a use of freed
or reused memory stops it with a report at the Sabk line that used it and
the one that freed it. That covers the temp allocator and arenas too:
memory they take back is poisoned until they hand it out again.

| # | Trap | Caught | Avoid it |
|---|---|---|---|
| 1 | A slice literal stored from a loop | warning | `clone_slice`, or arrays |
| 2 | A slice literal kept by a call in a loop | warning | `clone_slice`, or arrays |
| 3 | A view of a block's array used after the block | warning | keep the array, or copy |
| 4 | A function's memory kept by a function it calls | warning | `clone_slice` |
| 5 | An `Any` kept past its block | warning | keep the values, not `Any`s |
| 6 | Heap memory freed while views of it remain | `--sanitize` | copy what must outlive it |
| 7 | Memory moved by growing or removing | `--sanitize` | indexes, not pointers |
| 8 | Copying an owner (`[..]T`, `Map`, `Builder`) | warning, `--sanitize` | pass a pointer |
| 9 | Writing to a string literal | warning | write to a copy |
| 10 | Writing through a view changes text others hold | by design | write to a copy |
| 11 | An array passed as a slice is shared, not copied | by design | copy it first |
| 12 | Growing a growable array while looping over it | warning, `--sanitize` | add after the loop |
| 13 | Growing a by-value copy of a growable array | warning, `--sanitize` | pass `*[..]T` |
| 14 | Indexing past a pointer to one value | `--sanitize` | `p.*`, not `p[1]` |

What the warnings look at, so you know what they miss:

- **1-5:** memory that dies with a block, a loop's pass or the function
  (a slice literal whose values change from pass to pass, `&local`, a view
  of a local array, the copy made for an `Any`) stored in a variable that
  outlives it, or given to a call that also gets a pointer to outer
  memory able to hold it: `array_add(&pairs, .[i, i])` warns, but
  `array_append(&xs, .[i, i])` doesn't, since a `[..]i64` copies the
  elements. A `..Any` pack isn't kept, so `print_to(&buf, "%", x)` is fine.
- **8:** `let ys = xs;` of a `[..]T` (or a struct holding one by value),
  then one grown (`&ys` given to a call) while the other's used after.
- **9:** a write into a local that only ever holds a string literal.
- **12:** `&xs` given to a call inside `for (x in xs)`.
- **13:** `&xs` given to a call, where `xs` is a by-value `[..]T` parameter.

They follow one function's code and don't look inside the functions it
calls, so they miss some traps (`--sanitize` finds those when they
happen), and a call that copies what it's given can still be warned
about if its pointer could hold the value.
`--sanitize` needs a C compiler with AddressSanitizer (gcc or clang); it
doesn't apply to `#run` code.

**1. A slice literal stored from a loop.** A slice literal has one hidden
array per place it's written, and each evaluation fills that same array.
Every slice taken from it in a loop is a view of the same memory:

```
let saved: [3][]i64;
for (i in 0..3) saved[i] = .[i, i];
println("% % %", saved[0], saved[1], saved[2]);
// [2, 2] [2, 2] [2, 2]
```

The memory is valid until the function returns, so this is wrong values
rather than a crash. Avoid it with `clone_slice(.[i, i])` for a copy each
time, or keep arrays, which are values: `let saved: [3][2]i64;`.

**2. A slice literal kept by a call in a loop.** The same as 1, through a
function that stores what it's given, which is the common shape, since
containers are where things get kept:

```
let pairs: [..][]i64;
for (i in 0..3) array_add(&pairs, .[i, i]);
println("%", pairs);
// [[2, 2], [2, 2], [2, 2]]
```

Map keys and values the same way: `map_put(&m, .[a, b], 1)` in a loop.
Avoid it with `clone_slice`, or keep arrays: a `[..][2]i64` stores a copy
each time.

**3. A view of a block's array used after the block.** A local array
lives until the end of its block, so a view of it that's used after the
`}` reads memory the next block reuses. In a loop body, every pass ends
the array's life:

```
let s: []i64;
{ let a = i64.[1, 2]; s = a[..]; }  // a view of a
{ let b = i64.[8, 9]; }             // reuses a's memory
println("%", s);
// [8, 9]

let pairs: [..][]i64;
for (i in 0..3) {
    let pair = i64.[i, i];
    array_add(&pairs, pair);        // a view of pair, which ends with the pass
}
println("%", pairs);
// [[94248041362240, 3], [94248041362240, 3], [94248041362240, 3]]
```

This one is undefined behaviour, not just wrong values. Avoid it by
declaring the array where it lives long enough, or storing copies.

**4. A function's memory kept by a function it calls.** Storing a
function's own memory through a pointer parameter is an error, but not
when another function does the storing:

```
fn add(out: *[..][]i64) { array_add(out, .[7, 7]); }   // compiles
fn junk() { let big: [64]i64; for (i in 0..64) big[i] = 99; }

let pairs: [..][]i64;
add(&pairs);
junk();
println("%", pairs);
// [[99, 0]]

fn add_direct(out: *[]i64) { out.* = .[7, 7]; }       // an error, as above
```

**5. An `Any` kept past its block.** A value converted to `Any` is a
pointer to a copy that lives until the end of the block the conversion is
in:

```
let saved: [..]Any;
for (i in 0..3) {
    let v: i64 = i * 10;
    array_add(&saved, v);           // a pointer to a copy of v
}
for (a in saved) print("% ", a);
// 140724746429408 140724746429408 140724746429408
```

`Any` is for passing values to a call (`print`'s arguments), not for
keeping them.

**6. Heap memory freed while views of it remain.** Strings and slices
are views, so anything cut from a string dies with it:

```
fn first_word(text: string) -> string {
    let copy = copy_string(text);
    defer free(copy.ptr);
    let word, _, _ = cut(copy, " ");
    return word;                    // a view into memory the defer frees
}
let w = first_word("hello world");
let other = copy_string("XXXXXXXXXXX");     // reuses the freed memory
println("%", w);
// XXXXX

let line = copy_string("a,b,c");
let parts = split(line, ",");       // views into line
free(line.ptr);
// parts: ["X", "X", "X"], once something else is allocated there

let s = tformat("x = %", 5);
free_all(context.temp_allocator);
let t = tformat("y = %", 77777);
println("%", s);
// y = 7

let b = make_builder();
builder_append(&b, "hi");
let text = builder_string(&b);      // a view of b's bytes
builder_free(&b);
// text: "XX", once something else is allocated there
```

An arena's memory after `arena_destroy` is the same. Avoid it: copy what
has to outlive its owner (`copy_string`, `clone_slice`), and free in the
same place that allocated, with `defer`, after the last use.

**7. Memory moved by growing or removing.** Growing a `[..]T`, a `Map`
or a `Builder` can move its memory, and removing from a `Map` moves its
last entry into the hole. Pointers and views taken before then point at
the old place:

```
let xs: [..]i64;
array_add(&xs, 1);
let first = &xs[0];
for (i in 0..100) array_add(&xs, i);   // may move the elements
first.* = 42;                          // writes the old memory, if they moved

let s = builder_string(&b);
builder_append(&b, more);              // s may now point at freed memory

let m: Map(string, i64);
map_put(&m, "a", 1);
map_put(&m, "b", 2);
let a = map_find(&m, "a");
map_remove(&m, "a");                   // b's entry moves into a's slot
println("%", a.*);
// 2
```

Avoid it: keep an index, not a pointer (`xs[0]`), and take `map_find`'s
pointer again after changing the map.

**8. Copying an owner.** A `[..]T`, `Map` or `Builder` holds a pointer to
its elements. Copying it copies the pointer, not the elements, so both
copies own the same memory:

```
let xs: [..]i64;
array_add(&xs, 1);
let ys = xs;                            // the same elements, two owners
for (i in 0..100) array_add(&ys, i);    // ys moves; xs points at freed memory
array_free(&xs);
array_free(&ys);
// free(): double free detected in tcache 2
```

Avoid it: pass `*[..]T` (or `*Map`, `*Builder`) to anything that changes
it, and copy the elements (`array_of(xs)`) for a real copy.

**9. Writing to a string literal.** It compiles and crashes:

```
let s = "hello";
s[0] = 'J';
// segmentation fault (exit 139): literals are in read-only memory
```

In `#run` code it doesn't crash, and the change stays. See
[Strings](#string).

**10. Writing through a view changes text others hold:**

```
let line = copy_string("ab,cd");
let parts = split(line, ",");
parts[0][0] = 'X';
println("%", line);
// Xb,cd
```

**11. An array passed as a slice is shared, not copied.** Arrays are
values, but an array where a slice is expected becomes a view of itself,
as in C and Jai, so writes through the slice change the array:

```
fn zero(xs: []i64) { for (i in 0..xs.len) xs[i] = 0; }

let a: [3]i64 = .[1, 2, 3];
let b = a;               // a copy: changing b leaves a alone
zero(a);                 // a view of a
println("% %", a, b);
// [0, 0, 0] [1, 2, 3]
```

This is intended, but nothing at the call shows it. It's also what makes
trap 3 easy to write.

**12. Growing a growable array while looping over it.** A `for` loop
reads its sequence once. If the body grows the array, the elements move
and the loop keeps reading the old, freed block:

```
let xs: [..]i64;
for (i in 0..8) array_add(&xs, i);     // full: capacity 8
let blocker: [..]i64;
array_add(&blocker, 1);                // so xs can't grow in place
let n = 0;
for (x in xs) {
    if (n == 0) array_add(&xs, 100);   // grows: the elements move
    let other: [..]i64;
    if (n == 0) for (i in 0..8) array_add(&other, -1);   // reuses the old block
    print("% ", x);
    n += 1;
}
// 0 -1 -1 -1 -1 -1 -1 -1
```

Avoid it: collect what to add in a second array, and append after the
loop.

**13. Growing a by-value copy of a growable array.** A `[..]T` passed by
value is a copy of its fields (trap 8). Adding to the copy can move the
elements and free the block the caller's array still points at:

```
fn add_one(xs: [..]i64) { array_add(&xs, 99); }   // meant xs: *[..]i64

let xs: [..]i64;
for (i in 0..8) array_add(&xs, i);     // full: capacity 8
let blocker: [..]i64;
array_add(&blocker, 1);                // so xs can't grow in place
add_one(xs);                           // grows the copy, frees xs's block
let other: [..]i64;
for (i in 0..8) array_add(&other, 7);  // reuses the freed block
println("%", xs);
// [7, 7, 7, 7, 7, 7, 7, 7]
```

Avoid it: pass `*[..]T` to anything that adds to the array. A function
that only reads it takes a `[]T`.

**14. Indexing past a pointer to one value.** Any `*T` can be indexed
(see [Pointers](#types)), so a pointer to a single value can be read and
written past:

```
fn bump(count: *i64) { count[1] += 1; }   // meant count.* += 1
let a: i64 = 10;
let b: i64 = 20;
bump(&a);
println("% %", a, b);
// 10 21
```

C and Jai allow the same. Use `p.*` for the value a pointer points at,
and `p[i]` only for a pointer into an array.

## Printing and type information

`print` and `println` (std/io) take a format and any number of values of
any type:

```
println("% is % years old", name, age);
println("%", person);          // {name = "ada", age = 36, home = null}
println("%", shape);           // Rect(w = 3, h = 4)
let s = format("(%, %)", x, y); // std/fmt: a new string
```

**The format.** `%` is the next value and `%%` a percent sign. With no
values the text is printed as it is, so `print(s)` is safe for any `s`. A
`%` without a value left shows as `%(missing)`, and values left over are
shown at the end as `%(extra: ...)`.

**Directives.** A letter after the `%` says how to show the value:

| Directive | Prints |
|---|---|
| `%` | any value, the way it prints by default |
| `%s` | text: `string`, `[]u8`, `[N]u8`, `[..]u8`, or a C string (`*u8`, up to its 0) |
| `%q` | text in quotes, escaped: `"a\n"` (handy for making code) |
| `%w` | an error or enum value with its enum: `IoError.NotFound`, `Color.Red` |
| `%x %X` | an integer in hex: `ff`, `FF` |
| `%b %o` | an integer in binary, octal |
| `%e %f` | a float in scientific, fixed notation |
| `%c` | a `u8` as its character |
| `%{...}` | options, below: `%{8}` width, `%{<8}` left, `%{.2}` precision, `%{08x}` zeros and hex |
| `%{}` | a value with a letter right after it: `%{}px` |
| `%%` | a percent sign |

```
let bytes = "hi" as []u8;
println("% %s %q", bytes, bytes, "a\n");   // [104, 105] hi "a\n"
println("%x %c %w %{}px", 255, 'A', Color.Red, 12);  // ff A Color.Red 12px
```

A `[]u8` still prints as numbers by default; `%s` is the explicit "as
text" where it's printed, as `as string` is elsewhere.

**Options** go in braces after the `%`, with a directive's letter as the
kind:

```
%{[align][+][0][width][.precision][kind]}

println("%{8}|%{<8}|%{^8}", 42, "ab", "mid");   //       42|ab      |  mid
println("%{08.3} %x %{+} %c %{<6s}|", 3.14159, 255, 7, 'A', "ab");
                                       // 0003.142 ff +7 A ab    |
```

- **align:** `<` left, `>` right, `^` centered in the width. Numbers go
  right by default, everything else left.
- **`+`:** a sign on positive numbers too.
- **`0`:** pad numbers with zeros, after the sign: `-0042`.
- **width:** at least this many characters (UTF-8 characters, not bytes).
- **.precision:** for floats, digits after the point (`%{.2}` is `3.14`);
  for strings, at most this many characters.
- **kind:** a directive's letter. `x` `X` `b` `o` print an integer in
  hex, upper-case hex, binary or octal (a negative one as `-ff`); `e` and
  `f` a float in scientific or fixed notation (6 digits unless a precision
  says otherwise; integers convert); `c` a `u8` as the character it is;
  `s` and `q` text, `w` an error or enum value with its enum.

Width applies to the whole value; precision and kind also reach the numbers
inside it, so `%{.1}` on a `Point` prints `{x = 1.0, y = 2.2}`. A spec that
doesn't parse prints as `%(bad format {spec})`, and a letter that isn't a
directive as `%(bad format p)`; either still uses up its value.
std/fmt's `FormatSpec`, `parse_format_spec` and `append_formatted` do the
same from code.

**How values look** (without options):
- integers in decimal (a `u8` is a number too: `'x'` prints `120`), `true`
  and `false`, floats in the shortest form that reads back as the same
  value (`0.1`, `1e+20`)
- a `string` as its text; inside an array, struct or enum it's quoted, with
  escapes: `"ada"`. A `[]u8` is bytes, and prints as numbers: `[104, 105]`
- pointers, `*void` and functions as an address, `0x7ffc5e1c`, or `null`.
  Pointers aren't followed.
- arrays and slices as `.[1, 2, 3]`; structs as `{x = 1, y = 2}`
- enums by variant name, `Red`, or `Color(7)` for a value that's no variant;
  an `Error` as its enum and variant, `IoError.NotFound`, or `None`
- tagged enums as `Number(42)`, `Rect(w = 3, h = 4)` (fields it declared),
  `At({x = 1, y = 2})` (a struct it holds) or `Dot`
- unions as `Bits{...}`, since which field holds the value isn't known

**Checked while compiling.** When the format is a literal or a constant
and the values are written out at the call, the compiler checks them
together: as many values as `%`s, every directive a directive, every
`%{spec}` valid, and each kind suiting its value (`%x` on a string is an
error). Errors point at the `%` in the string, and a directive that isn't
one comes with the call written right:

```
println("% and %", 1);       // error: this `%` has no value
println("%x", "text");       // error: `%x` prints an integer, but `"text"` is a `string`; for text write `%s`
println("%d items", count);  // error: `%d` isn't a directive: Sabk's `%` prints a number as it is
                             //   note: write: println("% items", count)
                             //   note: the directives: ...
println("%5.2f", width);     // error: ... Sabk's options go in braces: `%{5.2f}`
println("%px", left);        // error: `%p` isn't a directive; for a value followed by `px`, write `%{}px`
```

C's spellings are translated: `%d`, `%u`, `%lld`, `%zu` are `%`; `%5.2f` is
`%{5.2f}`, `%-10s` is `%{<10s}`, `%08x` is `%{08x}`, `%E` is `%e`.

A call with no values isn't checked, since it prints its text as is
(`println("100%")`), and neither are formats only known at run time or
values passed on with `..args`; those show mistakes in the output instead,
as `%(missing)`, `%(extra: ...)` or `%(bad format {...})`.

Any function can ask for this by ending in a format and its values and
saying `#format`:

```
fn log(level: string, fmt: string, args: ..Any) #format {
    print("[%] ", level);
    println(fmt, ..args);
}

log("info", "% %", 1);       // error: this `%` has no value
```

The formatter is ordinary Sabk code in `std/fmt`, built on the next three
features.

**`..` parameters.** A function's last parameter can take any number of
arguments: `fn sum(xs: ..i32)` is called as `sum()`, `sum(1, 2, 3)`, and
inside it `xs` is a `[]i32`. To pass a slice you already have, write `..xs`:
`sum(..numbers)`, or a wrapper passing its own on, `println(fmt, ..args)`.

**`Any`** (in the prelude) is a value of any type: a pointer to it and its
type information.

```
struct Any { value: *void; info: *TypeInfo; }
```

Any value converts to `Any` where an `Any` is expected, so `args: ..Any`
takes values of any type. The pointer is to a copy of the value, which
lives until the end of the block the conversion is in. Untyped constants get
their default type (`5` is an `isize`, `null` a `*void`).

**`type_info(T)`** is a `*TypeInfo` describing `T` (`type_info(value)`
describes the value's type, which isn't evaluated, as with `sizeof`), the same data `Any`
carries. There's one per type, so two can be compared with `==`
(`info == type_info(u8)`).

```
enum TypeKind { Void, Bool, Int, Float, Rawptr, Pointer, Array, Slice,
                    String, Function, Struct, Union, Enum, TaggedEnum }

struct TypeInfo {
    kind: TypeKind;
    name: string;             // like []u8 or List(i32)
    size: isize;
    align: isize;
    is_signed: bool;          // Int
    elem: *TypeInfo;          // Pointer, Array, Slice, String: what it
                              // holds; Enum, TaggedEnum: the tag's integer
    count: isize;             // Array: its length
    fields: []TypeField;      // Struct, Union; TaggedEnum: tag and payload
    variants: []TypeVariant;  // Enum, TaggedEnum
}

struct TypeField { name: string; info: *TypeInfo; offset: isize; }
struct TypeVariant { name: string; value: i64; payload: *TypeInfo; }
```

So code can walk any type's fields:

```
for (f in type_info(Person).fields)
    println("% at offset %: %", f.name, f.offset, f.info.name);
```

Type information exists at compile time too: `#run` code can print and
inspect types the same way, and produces the same text.

## Compiling and running

```
./sabk prog.sabk            build an executable named `prog`
./sabk prog.sabk -o out     ... named `out`
./sabk --run prog.sabk      build, run, and exit with the program's exit code
./sabk --release prog.sabk  build optimized (-O2), without debug info
./sabk --sanitize prog.sabk build with AddressSanitizer (see Memory traps)
./sabk --bounds-checks off prog.sabk   no index or slice checks (on, off, always)
./sabk --run prog.sabk -- a b   run it with the arguments a and b
./sabk --emit-c prog.sabk   print the generated C (--lines: with #line)
./sabk --check prog.sabk    only check for errors
./sabk --strict prog.sabk   also warn about failures dropped and values used
                            before their failure is looked at (see Handling errors)
./sabk --werror prog.sabk   warnings fail the build
./sabk --stats ...         also print phase times and generic instances
```

The compiler writes one C11 file for the whole program and builds it with
`$CC` (default `cc`), in a temporary directory of its own.

**Only what's used is compiled.** The whole program is type-checked,
including the parts nothing calls, so mistakes show up where they're
written. But the C holds only what's reachable from `main`: the functions
it calls or uses as values (through variables, struct field defaults,
default arguments, generic instances), the globals it uses, and every
`extern fn` with a body, since C may call those. Importing a module costs
nothing for the functions you don't use, and code that only `#run` uses
isn't in the program at all. `--stats` shows how many functions were
written out.

**Debugging.** The C has `#line` directives mapping each line back to the
Sabk that made it, so gdb, lldb and sanitizers speak Sabk: `break
main.sabk:12` stops there, a backtrace shows Sabk files and lines, and
stepping walks the Sabk source. Code from a macro maps to the macro's own
lines; code made by `#insert` maps to the `#insert`. Variables have their
Sabk names (globals and functions get their module's prefix, as in
`main__count`). `--emit-c` leaves the directives out, since there you're
reading the C itself; `--emit-c --lines` keeps them.

**Builds.** A normal build keeps debug info (`-g`) and isn't optimized, so
a debugger shows the program as written. `--release` builds with `-O2` and
has the linker drop any code and data that's still unused
(`-ffunction-sections -fdata-sections -Wl,--gc-sections`, for GNU and LLVM
linkers). Bounds checks and the other safety checks stay in both.

**Entry point.** The root file must have `fn main()`, `fn main() -> i32`
(its exit status) or `fn main() -> Error` (a failure is printed, as
`error: IoError.NotFound`, and the status is 1; see
[Handling errors](#handling-errors)).
The program's arguments come from `args()` (std/os): its path, then the
arguments, as views of C's `argv`. With `--run`, what follows `--` on
sabk's command line is passed to the program. While compiling (`#run`
code, build scripts), `args()` returns the program's name and those same
arguments, so a build script can take options.

**Runtime behaviour:**
- Signed integer overflow wraps. It isn't undefined behaviour, because the C
  is compiled with `-fwrapv`. That includes the minimum divided by -1 (and
  `% -1` is 0), which C itself would trap on.
- Integer division (and `%`) by zero prints `file:line:col: panic: division
  by zero` and aborts, as `#run` code reports it as a compile error.
  Dividing by a constant other than 0 and -1 costs nothing extra. Float
  division by zero gives an infinity or NaN, as in C.
- Small integer types wrap at their own size: a `u8` sum wraps at 256.
- Indexing an array or slice is bounds-checked. An out-of-range index prints
  `file:line:col: panic: ...` and aborts. Indexing a raw pointer isn't
  checked against a length.
- **Null pointers.** Following a null pointer (`p.*`, `p.x`, `p[i]`)
  panics with `file:line:col: panic: null pointer`, under the same setting
  as the bounds checks.
- **Turning the checks off.** `#no_bounds_check` after a function's
  signature, like Jai's `#no_abc`, drops its index, slice and null checks (a
  generic's instances too):

  ```
  fn dot(a: []f32, b: []f32) -> f32 #no_bounds_check {
      let total: f32 = 0;
      for (i in 0..a.len) total += a[i] * b[i];   // b[i] isn't checked
      return total;
  }
  ```

  The build decides the rest, with `--bounds-checks` or std/build's
  `set_bounds_checks`: `On` (the default) checks everything except those
  functions, `Off` checks nothing, and `Always` checks them too, to find a
  bug one hides. It covers indexing, slicing and null pointers: division by zero is
  checked either way, and `#run` code keeps its checks. A macro can't be
  `#no_bounds_check`, since its code runs in its caller and is checked as
  the caller is, and neither can an `extern fn` without a body.
- `new` panics if the allocator returns `null`. What it returns starts as a
  new variable would: its type's defaults, or zeros.
- Writing to a string literal's bytes isn't checked: the program crashes
  with a segmentation fault, and `#run` code keeps the write (see
  [Strings](#string)).

**The default context** allocates with `calloc`, `realloc` and `free`. It
supports `Alloc`, `Free` and `Resize`.

**Calling convention.** Normal functions receive the context as a hidden
first parameter. `extern` functions use the plain C calling convention:

- An `extern fn` declared without a body is a C function to call.
- An `extern fn` with a body can be called from C. Inside it, `context`
  starts as the default context.
- Used as a value, an `extern fn` is a `*void` (a C function pointer, for
  callbacks such as `qsort`). It can't become one of our `fn(...)` types,
  because those expect the hidden context parameter.

**C interop details:**
- Struct layout matches C, so structs can be passed to C as they are.
- `f32` arguments to C variadic functions are passed as `f64`, as C requires.

## Generics

Generic functions and structs work like Jai's: `$T` declares a type
parameter, plain `T` uses it.

```
fn max(a: $T, b: T) -> T {               // T is decided by the arguments
    if (a > b) return a;
    return b;
}

struct List($T) {                         // a generic struct
    items: []T;
    count: isize;
}

fn push(list: *List($T), item: T) { ... }

fn make_list($T: Type) -> List(T) {      // a type passed as an argument
    return List(T).{ .items = new([]T, 4) };
}

let xs = make_list(i32);
push(&xs, max(3, 7));
```

**Declaring type parameters:**
- In a function, every `$T` in a parameter's type declares `T` for the whole
  function: its parameters, its return type and its body.
- `$T` can sit anywhere inside a type: `[]$T`, `*List($T)`,
  `fn($A) -> $B`.
- A `$T: Type` parameter takes a type as its argument: `make_list(i32)`.
  Any type can be passed this way, including `*u8`, `[]u8`, `List(f32)` and
  `fn(i32) -> bool`.
- A struct or union declares its type parameters after its name:
  `struct Pair($A, $B)`. It's then used with its types, `Pair(i32, u8)`,
  including inside generic code (`List(T)`), and its literals are written
  `List(i32).{ ... }`.

**Inference.** The type parameters of a call are worked out by matching
each argument's type against its parameter's type: `[]$T` against `[]f32`
gives `T = f32`, and `*[N]f32` and `[N]f32` work too. Arguments typed `T` must agree the
way the two sides of `+` do:
- `max(x, 1)` and `max(1, x)` with `x: u8` both give `T = u8`.
- `max(3, 7)` gives `isize`, the default for untyped constants.
- An `i32` and a `u64` argument is an error.
- A type found inside another type decides alone, since nothing converts
  it: for `array_add(xs: *[..]$T, item: T)` with `xs: [..]i32`,
  `&xs` gives `T = i32`, and the item must convert to `i32`. An `i8` item
  widens; an `isize` one is an error.
- When nothing decides `T` (`deref(5)` for `p: *$T`), it's an error.

**The context can decide too.** When the arguments don't say what `T` is,
the type the call's context expects does, matched against the return type
(except `Any`, which every value converts to, so `println("%", max(1, 2))`
uses `T = isize`):

```
let xs: List(i32) = make_list();          // T = i32, from the declared type
let names: List(string) = make_list(16);  // 16 is the capacity
let n: i64 = parse(text);                 // fn parse($T: Type, s: string) -> T
let small: u8 = max(1, 2);                // untyped arguments: the context, u8
```

- **Leaving out a `$T: Type` argument.** You can leave it out when the
  context decides, as `make_list()` and `make_list(16)` do. It counts as left
  out when what's in its place isn't a type and the call has room for that,
  so `make_list(16)` passes 16 as the capacity.
- **The arguments still come first.** With `a: i32`,
  `let w: i64 = max(a, 3);` uses `T = i32` and widens the result. The
  context only fills in what the arguments don't decide; for untyped
  constants it does decide, which is why `max(1, 2)` above is a `u8`.

**Generic struct literals** can leave out their types, too. The field values
decide them, and so does the context when it expects an instance of that
struct:

```
let b = Box.{ .value = 1.5 };             // Box(f64)
let p = Pair.{ 1, "two" };                // Pair(i32, string)
let small: Box(u8) = Box.{ .value = 7 };  // the context decides the untyped 7
let bag = Bag.{ .items = .[1, 2] };       // T from the field's type, []T: isize
```

`Box.{}` with nothing to go by is an error: write the types, `Box(i32).{}`.

**Instances:**
- Each distinct set of types gets one **instance**: a copy of the function
  or struct, compiled for those types, such as `max__i32` or `List__u8` in
  the C. Using the same types again reuses the same instance.
- The body is type-checked separately for each instance, as in Jai, Zig and
  Odin. An error inside generic code points into it, with a note saying
  which instance and where it was used:
  `in max with T = Vec2, used here`.
- Names in a generic body are resolved once, when it's declared, so a
  misspelled name is reported even if the function is never used. Type
  errors only show up when it's instantiated.
- A generic function that would need an endless series of instances (one
  that calls itself with `*T`) stops at 64 levels with an error.

**Compile time.** Each instance costs our compiler about 0.1 ms, plus the
C compiler's time for its code. `--stats` shows the phase times and every
instance. A program with 600 instances spent 72 ms in our compiler and
800 ms in gcc.

**Restrictions in this version:**
- **A generic instance's default parameter values are checked when a call
  uses them,** since a default may only make sense for some types.
  In `fn fill(xs: []$T, value: T = 0)`, the `0` only fits number types, so
  a call on a `[]string` passes its own `value`, and the default is never
  checked for `string`. An ordinary function's defaults are checked with its
  declaration.
- A generic function used as a value needs a function type to pick its
  instance: `sort_by(items, less_than)` or
  `let f: fn(f64) -> f64 = twice;` work, and `let f = twice;` doesn't.
  A generic function with a `$T: Type` parameter can't be a value at all.
- No generic `extern` or `#expand` functions.
- No `$N` for array lengths.

## Compile-time `#if`

`#if` picks between two pieces of code while compiling, so only the branch
taken is type-checked and compiled. In generic code that lets each instance
do what makes sense for its types:

```
fn hash_key(key: $T) -> u64 {
    #if (T == string)
        return hash_string(key);        // only checked when T is string
    else #if (T == f32 || T == f64) {
        if (key == 0) return 0;
        return hash_bytes(&key, sizeof(T));
    } else
        return hash_bytes(&key, sizeof(T));
}
```

**The condition** must be a `bool` known at compile time:
- type comparisons: `T == string`, `T != *u8`, `T == List(i32)`; a
  generic struct without its types matches any instance: `T == Map` is
  true for every `Map(K, V)`
- constants and `sizeof`: `sizeof(T) == 8`, `DEBUG`
- any of these combined with `&&`, `||` and `!`

A condition that's only known at run time is an error: use a plain `if`.

**Checking:**
- Names are resolved in both branches, so a misspelling in the branch that
  isn't taken is still reported. The exception is a branch that inserts
  code made by `#run`: then the condition is decided first, and only the
  branch taken is resolved, so only its `#run` runs.
- Type checking and code generation see only the branch taken.
- The missing-return check follows the branch taken too.
- Each branch is its own scope, like an `if` body.
- `#if` works in any function, generic or not.

**At the top level**, `#if` picks declarations: those in the branch taken
are part of the module, as if written there, and the others aren't. This
is where platform code goes, with the target constants every module sees:

```
#if (OS == .Windows) {
    extern fn Sleep(ms: u32);
    struct Stat { size: i64; mode: u16; }
} else {
    extern fn usleep(us: u32) -> i32;
    struct Stat { dev: u64; ino: u64; mode: u32; size: i64; }
}

fn sleep_ms(ms: u32) {
    #if (OS == .Windows) Sleep(ms);      // Sleep exists only on Windows,
    else usleep(ms * 1000);              // which is fine in the branch not taken
}
```

- **The targets:** `OS` is an `OperatingSystem` (`.Linux`, `.MacOS`,
  `.Windows`, `.FreeBSD`, `.Other`), `ARCH` an `Architecture` (`.X64`,
  `.Arm64`, `.X86`, `.Arm32`, `.RiscV64`, `.Other`), and `POINTER_SIZE` is
  `sizeof(*void)`. The target is the machine compiling the program, which
  `#run` code runs on too.
- **Branches** are `{ }` blocks of declarations, chained with
  `else #if (...)`, and can hold another `#if`, `#insert` and `#run`, but
  not `import`: import outside, and use the module in the branch.
- **The condition** is decided once every module is loaded, so it can use
  constants from anywhere, including the module's own (`const LEVEL = 2;`).
- **Names in a branch not taken** are still checked, so a typo is an error
  on every platform. Code that isn't taken can name what any branch
  declares, but code that is taken can't use a declaration that isn't part
  of the program: it's an error that points at the `#if`.

## Compile-time execution

`#run expr` runs `expr` while compiling, and its value becomes part of the
program as if it had been written there as a literal:

```
fn primes(count: i32) -> []i32 { ... }      // any ordinary function

const PRIMES = #run primes(100);            // a table computed once
let lookup: [#run table_size()]u8;          // an array length
#if (#run cpu_has_feature()) { ... }        // a compile-time condition
#run println("compiling...");               // run for what it does
```

**What can run.** Almost any code: loops, recursion, `defer`, macros,
generics, structs, slices, `new` and the allocators, the standard library,
and C functions such as `printf` or `qsort` (through libffi, including C
calling back into an `extern fn` with a body). Values are laid out in memory
exactly as in the compiled program, so integer arithmetic, wrapping and
struct layout give the same results at compile time as at run time.

**What comes out.** The value is turned back into literals:
- integers, floats, `bool` and enums become constants (so they work as array
  lengths and in `#if`)
- a `string` becomes a string literal (and so does a `[]u8`)
- arrays, slices and structs become literals of their elements and fields,
  so a slice's elements are copied into the program
- a tagged enum becomes the variant it holds, with that variant's value
- pointers, `*void`, functions and unions can't come out: an address means
  nothing once the program runs. This is checked before anything runs, and
  applies to fields and elements too.
- a growable array can't come out either, since the program couldn't grow
  memory the compiler allocated; return a slice of it. So a `Map` can't,
  and std/map's `static_map` makes one that can:

  ```
  const KEYWORDS = #run static_map(.[
      Pair.{ "if", Token.If },
      Pair.{ "else", Token.Else },
  ]);
  let kind = static_map_get(KEYWORDS, word) or_else Token.Name;
  ```

A `#run` whose expression is already constant (`#run 4 * 1024`) runs
nothing. A `#run` of something that returns nothing must be a statement,
`#run f();`; it runs for its effects and leaves no code behind.

**What it can see:**
- functions, constants and global variables, but not local variables or
  parameters: they only exist when the program runs
- its own copy of the global variables, starting from their initial values.
  What `#run` code does to a global doesn't change the program's copy.
- a context like the program's default one: the heap and a temp allocator.
  Memory it allocates lives until the compiler exits.
- the compiler's standard output is redirected to standard error while
  `#run` code runs, so `--emit-c` output stays clean.

**Failures are compile errors.** An out-of-bounds index, a null
dereference, division by zero, `panic` (which calls `abort()`) or `exit()`
stops the `#run`, and the error shows where it happened and the calls that
led there. So do recursion over 100,000 calls deep and running over a
billion steps (an endless loop). A function can't `#run` itself while it's
being checked.

**How it works.** The checked syntax tree is compiled to a bytecode for a
small interpreter (`src/vm.sabk`), function by function as they're first
called. A `#run` runs as soon as the checker reaches it, so the functions it
calls are checked first, wherever they are. After an error has been
reported, later `#run`s are skipped, since the code they'd run may be
broken.

### Inserting code made at compile time

`#insert` followed by a string known at compile time compiles that string
as code, in place of the `#insert`. The string usually comes from `#run`:

```
fn getters(names: []string) -> string { ... }  // builds source text

#insert #run getters(.["x", "y"]);             // top level: declarations

fn main() {
    let total = 0;
    #insert #run unrolled(4);               // statements
    let n = #insert #run expr_text();       // an expression
    #insert "let made = 42;";               // a string works too
    #insert (CODE);                         // or a constant holding one
}
```

**Where it goes:**
- At the top level the text is declarations. They join the module, and the
  rest of the program can use them, because top-level `#insert`s run before
  function bodies are resolved. They can't `import`.
- In a function the text is statements. They aren't a new scope: what they
  declare is visible after the `#insert`. Where only one statement fits
  (an `if` body), they're a block.
- In an expression the text is one expression.
- Generated code can `#insert` more code.
- `#insert name` (an identifier) is still a macro's `Code` parameter. To
  insert a constant string, parenthesize it: `#insert (CODE)`.

**Names.** The code is resolved where the `#insert` is, as if it were
written there. Inside a macro it belongs to the macro, with the same
hygiene as the macro's own code: a backtick reaches the caller.

**Errors** in generated code point into that code, at a path like
`main.sabk:12:5 #insert:1:9` (line 1, column 9 of the code the `#insert`
at 12:5 made), with a note at the `#insert`. So do panics at run time.

**Order.** The code an `#insert` runs is checked and run while names are
still being resolved, so the functions it needs are resolved and checked
first, wherever they are. It can't use locals or parameters, and it can't
use the declaration the `#insert` is part of (a struct can't build its own
field's default from itself).

**In generic functions** the code is made once for each instance, with
the type parameters known, so it can differ for each `T`. See
[Compile-time reflection](#compile-time-reflection).

**Not yet supported:**
- `#insert` of a string in a generic struct, or reaching a generic
  function's body through a macro
- carrying pointers across: a value like a linked list must be flattened
  into arrays first

### Build scripts

A `#run` at the top level, as a declaration of its own, is a build step:

```
#import "std/build";

#run configure();

fn configure() {
    set_output("bin/game");           // the executable's path
    link_library("m");                // -lm
    add_c_file("vendor/stb_image.c"); // compiled and linked along
    add_c_flags("-march=native");     // passed to the C compiler
    if (is_release())
        println("a release build");
}
```

- **When:** once the whole program has checked without errors, before any
  C is written. Steps run in order: the modules as they're loaded (the main
  file first), and in each, top to bottom. If one fails, the build stops
  with the error.
- **Anywhere:** a library module can have its own step, so it links what it
  needs (`#run link_library("m");`) and programs using it don't have to.
- **What they can do:** anything `#run` code can (print, read and write
  files, call C), plus std/build's functions:
  - `set_output(path)`: the executable's path
  - `set_release(on)`, `is_release()`: whether this is a `--release` build
  - `set_bounds_checks(.On | .Off | .Always)`: index and slice checks (see
    "Turning the checks off" in [Compiling and running](#compiling-and-running))
  - `set_strict(on)`, `set_werror(on)`: the strict warnings, and
    warnings failing the build, as `--strict` and `--werror` (see
    [Handling errors](#handling-errors)); either the script or the command
    line turns them on
  - `add_c_flags(flags)`: passed to the C compiler as written
  - `link_library(name)`: `-l<name>`; each library once
  - `add_c_file(path)`: a C file compiled and linked with the program
- **Paths** are relative to the directory of the program's main file.
- **The command line wins:** `-o` overrides `set_output`, `--bounds-checks`
  overrides `set_bounds_checks`, and a script can't turn `--release` off (it
  sees it through `is_release()`).
- std/build's functions are the compiler's, so they only exist while
  compiling: calling one from code the program runs is a compile error.
- A build step's value, if it has one, is dropped.

## Compile-time reflection

`type_info(T)` works in `#run` code too, so code can be written from a
type's description and compiled with `#insert`. This is how Sabk does what
other languages do with `derive` or code generators, in ordinary Sabk.

At the top level it makes declarations:

```
// fn set_Point_x(p: *Point, value: i32) { p.x = value; } and so on
fn make_setters(t: *TypeInfo) -> string {
    let b = make_builder();
    for (f in t.fields)
        builder_print(&b, "fn set_%_%(p: *%, value: %) { p.% = value; }\n",
                      t.name, f.name, t.name, f.info.name, f.name);
    return builder_string(&b);
}

#insert #run make_setters(type_info(Point));
```

**In a generic function** the body is made once for each `T`:

```
fn values_equal(a: $T, b: T) -> bool {
    #insert #run equal_code(type_info(T));
}
// for struct Point { x: i32; y: i32; }:  return a.x == b.x && a.y == b.y;
```

A generic function whose body has an `#insert` of a string is resolved
for each instance instead of once, when the instance is made. So its
names are checked per instance too, and an error in the generated code
says which instance it's in. A function only `#run` uses (like
`equal_code`) isn't in the compiled program.

**std/reflect** is written this way:
- `values_equal(a, b)` compares any two values of a type: field by field,
  element by element, strings by their text, tagged enums by variant and
  value. Pointers compare as addresses; they aren't followed.
- `hash_value(v)` hashes any value consistently with `values_equal`.
- Unions can't be compared or hashed, since which field holds the value
  isn't known; trying is a compile error.

`std/map` uses them for its keys, so any type works as a key, including
structs with string fields.

**Writing a generator:**
- The text is resolved where the `#insert` is, so it can use the
  function's parameters and anything the module sees.
- `t.name` is a type as it's written (`string`, `List(i32)`), so it can go
  into generated code. A tagged enum variant's struct of fields
  (`Shape.Rect`) is the exception; reach it through the enum.
- A generator can `panic` to stop with a message: it becomes a compile
  error at the `#insert`.

## Macros

A function marked `#expand` is a macro. A call to it is replaced by a copy of
its body, inlined at the call site, as in Jai:

```
fn with_allocator(alloc: Allocator, body: Code) #expand {
    context.allocator = alloc;
    #insert body;
}

with_allocator(arena) {        // the block fills the last Code parameter
    let p = new(Thing);        // allocated from `arena`
}
```

**Calls** look like function calls. `name(args) { ... }` passes the block as
the last argument, which must be a `Code` parameter. The parentheses are
required, even when empty: `name { ... }` is an error.

**Parameters:**
- A **typed parameter** works like a function parameter. Its argument is
  evaluated once, in order, before the body runs, and bound to a local the
  macro owns.
- A **`Code` parameter** receives the caller's code unevaluated: an
  expression, or a block.
  - `#insert name` puts a copy of it in the body, as a statement or inside
    an expression. Each insertion is a separate copy.
  - `#text(name)` is its source text as a string.
  - `#location(name)` is `"file:line:col"` of where it was written.
  - Passing a `Code` parameter on to another macro passes the code itself.
  - A `Code` parameter can't have a default value.

**Hygiene.** The macro's names and the caller's names never capture each
other:
- Names in the macro body resolve where the macro is *defined*. A macro's
  `let tmp` can't clash with the caller's `tmp`. A macro can call private
  functions of its own module, even when it's expanded in another module.
- Inserted `Code` resolves where it was *written*: the caller's names, plus
  anything the macro declares for the caller with a backtick.
- A backtick reaches the caller deliberately:

  | In the macro             | Means                                              |
  |--------------------------|----------------------------------------------------|
  | `` `name ``              | the caller's `name`; it can be read and assigned   |
  | `` `let x = ...; ``      | declares `x` for the caller, after the call or in inserted code |
  | `` `defer stmt; ``       | runs `stmt` when the caller's block ends           |
  | `` `return value; ``     | returns from the caller                            |
  | `return value;`          | returns from the macro: the call's value           |

**Return values.** A macro with `-> T` can be used as an expression. Every
path through it must `return` a value.

**Restrictions on backtick declarations:**
- `` `let `` and `` `defer `` only work in macros without a return value.
- `` `defer `` must be at the top level of the macro body.

**Loops and `defer`:**
- A `break` or `continue` in inserted code binds to the innermost loop where
  the code was inserted. That's what makes iteration macros work:

  ```
  fn each(list: *List, body: Code) #expand {
      for (i in 0..list.count) {
          `let it = list.items[i];
          #insert body;
      }
  }
  each(&numbers) { if (it < 0) break; total += it; }
  ```

- The macro's own code can't `break` or `continue` out of the macro.
- `defer` inside a macro runs when the macro's body ends.
- **`return` and `or_return` in inserted code** return from the function
  the code was written in, as they would without the macro, and the
  macro's defers run on the way out. So a block can leave early from
  inside `with_allocator(a) { ... }` and the allocator is still put back:

  ```
  fn around(body: Code) #expand {
      println("enter");
      defer println("leave");
      #insert body;
  }

  fn first_positive(xs: []i64) -> i64 {
      around() {
          for (x in xs) if (x > 0) return x;   // prints "leave", then returns
      }
      return -1;
  }
  ```

  The macro's own body can't use `or_return`, since it would return from
  the function using the macro without saying so at the call.

**Checking:**
- A macro body is checked each time it's expanded, not where it's declared.
- An error inside a macro points into the macro, with notes showing the
  calls that expanded it.
- Expansions nested more than 64 deep are an error, which catches a macro
  that expands itself forever.
- A macro is not a value: it can only be called.

**Generated C:**
- A macro used as a statement is written out in place.
- A macro used as a value becomes a GNU C statement expression `({ ... })`,
  which gcc and clang support.

**Not yet supported:**
- polymorphic (`$T`) parameters

## Standard library

The standard library lives in `std/` and is imported with `#import "std/name";`.
Its names are chosen to be distinct across the whole library, so a plain
import of every module never clashes. Each file starts with a summary of what
it offers.

| Module    | What it has |
|-----------|-------------|
| `std/io`  | `print`, `println`, `eprint`, `eprintln`, formatted (`print("x = %", x)`, `print("%{.2}", f)`); C's `printf`; `read_file`, `write_file`, `append_file`, `delete_file`, `file_exists`, which fail with an `IoError`, and `io_error_message`; `last_io_error()`, what errno says after a C call fails |
| `std/fmt` | `format(fmt, ..args)` (a new string), `tformat` (in the temp allocator), `builder_print(&b, fmt, ..args)`, `print_to(&buf, fmt, ..args)` (onto a `[..]u8`), `format_into(&b, fmt, args)`, `append_value(&b, value)`: any value as text; `%{...}` options, and `FormatSpec`, `parse_format_spec`, `append_formatted` |
| `std/mem` | `alloc`, `free`, `resize`, `free_all` on any allocator; `delete(x)`, which frees what a string, slice, growable array, `Map` or `Builder` holds; `with_allocator(a) { }`, `with_temp_allocator() { }`; `copy_bytes`, `copy_slice`, `clone_slice`, `set_bytes`, `copy_memory`, `zero_memory`; `Arena` with `arena_init`, `arena_allocator`, `arena_alloc`, `arena_reset`, `arena_destroy` |
| `std/str` | `equal`, `compare_strings`, `string_less`, `starts_with`, `ends_with`, `index_of`, `index_of_char`, `contains`, `trim`, `split`, `join`, `cut`, `copy_string`; `to_cstring`, `from_cstring`; `format_int`, `format_uint`; `parse_int`, `parse_uint`, `parse_float`, `parse_bool`, which fail with a `ParseError`; `Builder`, text on a growable `[..]u8` (a zero one is ready to use), with `make_builder`, `builder_append`, `builder_append_char` (formatted values go in with std/fmt's `builder_print`), `builder_string`, `builder_clear`, `builder_free`; `append_string(&buf, s)`, text onto a `[..]u8` |
| `std/os`  | `args`, `exit`, `abort`, `get_env` (and whether it's set); the `panic` and `assert` macros, which report the source location through `context.panic_handler` |
| `std/path` | paths taken apart as views, `path_dir`, `path_base`, `path_stem`, `path_ext`, `path_is_absolute`; and made, allocated: `path_join`, `path_normalize` (on the text alone), `path_absolute` and `path_real` (links followed; the file has to exist), which fail with an `IoError`. POSIX paths |
| `std/fs` | directories: `is_dir`, `make_dir`, `remove_dir`, `make_temp_dir(prefix)` (in `$TMPDIR` or `/tmp`), `current_dir`, failing with an `IoError` (files are std/io's). POSIX |
| `std/process` | `run_command(args)` (no shell; the program is looked up in `$PATH`) and `run_shell(command)` (`/bin/sh -c`), which wait for it and give an `Exit` (`code`, and `signal` when one ended it) and a `ProcessError` (`NotFound`, `CantStart`); `shell_quote`. POSIX |
| `std/time` | `now_ns()` (a monotonic clock, for measuring), `unix_time_ns()` (the wall clock), `sleep_ms(ms)`. POSIX |
| `std/logging` | `log(level, fmt, args)` through `context.logger`, skipping levels below `context.log_level`; `capture_logger(&lines)`, `silent_logger()` |
| `std/array` | for growable arrays, `[..]T`: `array_of(items)` (an allocated copy), `array_add`, `array_add_new` (a pointer to a new last element, to fill in place), `array_append`, `array_pop`, `array_insert`, `array_remove`, `array_remove_unordered`, `array_find(xs, item)` (its index or -1, on any `[]T`) and `array_remove_value` (the first equal one), comparing as std/reflect's `values_equal`, `array_reserve`, `array_clear`, `array_free` |
| `std/map` | `Map($K, $V)`, a hash map whose `entries`, a growable array, holds its entries in insertion order, for keys of any type; a zero one is ready to use; `make_map` (to pick the allocator or the hashing), `map_put`, `map_find` (a pointer, or null), `map_get` (a copy, and whether it's there), `map_has`, `map_remove`, `map_clear`, `map_free`; `StaticMap($K, $V)`, a read-only map that `#run` can bake into the program, made by `static_map(pairs)` from `Pair`s and read with `static_map_get` and `static_map_has`; `hash_bytes`, `hash_string`, `hash_key`, `keys_equal` |
| `std/build` | for build scripts (top-level `#run`): `set_output`, `set_release`, `is_release`, `set_bounds_checks`, `add_c_flags`, `link_library`, `add_c_file` |
| `std/checked` | 64-bit arithmetic that reports overflow instead of wrapping: `add_i64`, `sub_i64`, `mul_i64`, `div_i64`, `rem_i64`, `neg_i64`, `shl_i64` and their `u64` versions, each giving the result and whether it fits; `fits_signed(v, bits)`, `fits_unsigned(v, bits)`; `I64_MIN`, `I64_MAX`, `U64_MAX` |
| `std/reflect` | `values_equal(a, b)` and `hash_value(v)` for values of any type, made per type by compile-time reflection; `hash_memory`, `combine_hashes` |
| `std/sorting` | `sort`, `sort_by(items, less)`, `is_sorted`, `is_sorted_by`, `binary_search`, `reverse` for slices of any type; introsort, O(n log n) on any input, not stable |

A few things to know:
- **Module names don't repeat function names,** so that a plain import never
  hides a function: the sort module is `std/sorting`, which makes `sort(xs)`
  the function and `sorting.sort(xs)` its qualified form.
- **A zero `Map` is ready to use.** `let m: Map(string, i32);` hashes and
  compares its keys with std/reflect's `hash_value` and `values_equal`, so
  keys of any type work, and grows with `context.allocator` from its first
  `map_put`. `make_map` is for another allocator or another hash and
  equality.
- **A map known while compiling is a `StaticMap`**, made by `#run`
  (`const KEYWORDS = #run static_map(.[Pair.{ "if", Token.If }, ...]);`).
  It's two slices, so it goes into the program as data, with no allocation
  and nothing to run at startup. It's read-only, and always uses
  `hash_key` and `keys_equal`. Where a later key repeats an earlier one, the
  later value wins.
- **`delete(x)` frees what a value holds**, whatever it is: a string's or
  slice's elements (from `context.allocator`, or the allocator given), a
  growable array's elements, a `Map`'s or `Builder`'s memory. It takes a
  copy, so the variable still points at the freed memory; `array_free`,
  `map_free` and `builder_free` take a pointer and also empty it. Anything
  else is a compile error: a pointer from `alloc` or `new` is freed with
  `free(p)`.
- **A zero growable array is ready to use.** `let xs: [..]i32;` grows with
  `context.allocator`, or with the allocator its `allocator` field was
  given, from its first add. Growing can move the elements, so pointers and
  slices into them are only valid until it next grows.
- **Functions that can fail return what they made, then whether it
  worked**: a `bool`, or an error enum whose `None` (0) means it did:
  `let data, err = read_file(path);`, `let n = parse_int(s) or_return;`,
  `get_env("HOME") or_else "/"`. Code that combines several returns
  `Error`, which every error enum converts to. See
  [Handling errors](#handling-errors).
- **Text is `string`, bytes are `[]u8`.** std takes and returns `string`
  for text, including `read_file`. Strings aren't NUL-terminated, and can
  hold NUL bytes, which `print` writes too. See
  [Strings, bytes and builders](#strings-bytes-and-builders).
- **Who frees what:** a function that allocates says so, and usually
  takes the allocator last (`format` and `tformat` don't: see
  [Context](#context)); what it returns is the caller's to free. Views it returns
  (`trim`, `cut`, `split`'s parts, `builder_string`, `map_find`) live as
  long as what they view. See [Memory and ownership](#memory-and-ownership).
- **Output order:** stdout goes through C's buffered stdio, so `print` and
  `printf` output stay in order. stderr isn't buffered.
- **Declaring libc functions:** std declares the C functions it uses with our
  spellings (`*u8` for `char *`, `*void` for `void *`). Every declaration of
  a function ends up in one C file, so if your program declares one of the
  same functions, it has to use the same types.

## Lexical notes

- `//` line comments and `/* */` block comments (no nesting).
- Integer literals: `42`, `0xFF`. Float literals: `3.14`, `1e10`, `2.5E-3`.
- Char literals `'a'` and string literals `"..."`, with the escapes `\n`
  `\t` `\r` `\0` `\\` `\'` `\"` and `\xNN` (two hex digits). A string
  can span lines; its newlines are part of it.
- Keywords: `fn return let const type struct enum union extern as
  if else for in while do switch case default break continue defer sizeof
  type_info is new context or_else or_return true false null`.
  A keyword can still be a field's name, where a field's name goes: in a
  struct's or variant's fields (`type: i32`), after `.` (`t.type`), in
  `.type = 1`, and in a pattern's `type: x`. It can't name a variable, so
  the pattern shorthand `.Let{type}` is an error: write `.Let{type: t}`.
- Directives: `#expand`, `#format`, `#nodiscard`, `#no_bounds_check`, `#insert`, `#text`,
  `#location`, `#if`, `#run`. A backtick (`` ` ``)
  marks a caller's name in a macro.
- `$` declares a type parameter (`$T`), `...` is a C function's variadic
  parameters, `..` a range, a slice or a `..` parameter, and `---` leaves a
  local uninitialized.
- Names that aren't keywords but are always there: the built-in types
  (`i32`, `string`, ...), `Type` and `Code` (for generics and macros), and
  the prelude's `Any`, `TypeInfo`, `Error`, `Option`, `Allocator`, `Context`
  and the target constants `OS`, `ARCH` and `POINTER_SIZE`.
- The lexer also produces `:=`, `::`, `~=` and `@`, which the grammar
  doesn't use yet.
