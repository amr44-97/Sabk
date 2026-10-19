# Smelt language plan

Oct 19, 2026 · @amr

The language changes decided while self-hosting the compiler. They're
built in the new compiler (`../Smelt`), not in the C++ one, which only
gets fixes from now on. The new compiler is compiled by the C++ one until
it can compile itself, so its own source and std keep today's syntax until
then: the new parser accepts the new forms first, and std and the compiler
switch to them at the bootstrap.

## Checklist

- [x] **Formatting:** letter directives (`%s %q %w %x %X %b %o %e %f %c`), `%{}` before a letter, errors that teach (section 1)
- [ ] **Modules:** `#import`, `#load`, and `#scope_export` / `#scope_module` / `#scope_file` instead of `pub` (section 2)
- [ ] **Metaprogramming, layer 1:** `$` value parameters, `#assert`, `#where`, `#caller_location`, notes (`@name`), `#embed` (section 3)
- [ ] **Metaprogramming, layer 2:** `#code` values and syntax trees in std/compiler (section 3)
- [ ] **Metaprogramming, layer 3:** a build script that sees every declaration as it's checked (section 3)
- [ ] **Types as values:** `#insert` in struct and enum bodies, value parameters on structs (section 3)
- [ ] **Tagged enums:** ~~`!is`~~ (done), checked variant access `x.Variant`, narrowing (section 4)
- [ ] **Error enums:** `enum IoError: Error { ... }`; plain enums go back to being plain (section 5)
- [ ] **Results:** `E!T`, `E!void`, `!T` (inferred failure), wrapping, destructuring, `or_return .Replacement` (section 5)
- [ ] **Dropped failures:** a warning that shows the handling; levels from flags and build options (section 5)
- [ ] **Debug failure traces** through `or_return` (section 5)
- [ ] **Smaller additions:** named variant construction, ~~`for (x, i in xs)`~~, ~~`let a, b: T;`~~, ~~keywords as field names~~ (done), null checks, wrapping into `?T` (section 6)

## 1. Formatting

Formats keep `%` (code made as text for `#insert` is full of braces, which
`{}` placeholders would make you double). A letter after `%` is a
directive:

| Directive | Prints |
|---|---|
| `%` | any value, the way it prints by default |
| `%s` | text: `string`, `[]u8`, `[N]u8`, `[..]u8`, or a C string (`*u8`, up to its 0) |
| `%q` | text in quotes, escaped: `"a\n"` (handy for making code) |
| `%w` | an error, with its enum: `IoError.NotFound`, `ConfigError.BadLine(line = 12)` |
| `%x %X` | an integer in hex: `ff`, `FF` |
| `%b %o` | an integer in binary, octal |
| `%e %f` | a float in scientific, fixed notation |
| `%c` | a `u8` as its character |
| `%{...}` | options, as today: `%{8}` width, `%{<8}` left, `%{.2}` precision, `%{08x}` zeros and hex |
| `%{}` | a value with a letter right after it: `%{}px` |
| `%%` | a percent sign |

Nothing breaks: no Smelt format uses `%` followed by a letter today (the
ones that do are C `printf` formats, which `#format` doesn't check).
A `[]u8` still prints as numbers by default; `%s` is the explicit "as
text" where it's printed, as `as string` is elsewhere.

**Errors.** The format is known at compile time, so a mistake is
underlined in the string, explained, and fixed:

```
[error]: `%d` isn't a directive: Smelt's `%` prints a number as it is at [main.smelt:4:14]
     4 |     println("%d items", count);
       |              ^^
[note]: write: println("% items", count)
[note]: the directives: ...the table above...
```

- A directive that doesn't suit its value: "`%s` prints text, but `count` is an `i64`; for a number write `%`, or `%x` for hex".
- C's habits, translated: `%5.2f` → `%{5.2f}`, `%-10s` → `%{<10s}`, `%08x` → `%{08x}`, `%d` / `%u` / `%lld` / `%zu` → `%`.
- A letter meant as text: "`%p` isn't a directive; for a value followed by `px`, write `%{}px`".
- An unknown directive shows the table; the counts keep today's messages.
- A format only known at run time can't be checked: it prints `%(bad format p)`, as today.

## 2. Modules and visibility

**`#import`** replaces `import`: `#import "std/io";` and
`#import "std/io" as io;`. (Jai writes the second as
`io :: #import "std/io";`, which allows module parameters; that's for
later, if module parameters come.)

**`#load "file.smelt";`** makes one module of several files, as in Jai:
the loaded file's declarations join this module, and the files see each
other's module-private names. A file is loaded once; its path is relative
to the file that loads it.

**Regions instead of `pub`.** Everything is public unless a directive says
otherwise, as in Jai and C (where `static` is the exception). A directive
applies to every declaration after it, until the next one:

- `#scope_export` — visible to whoever imports the module (the default at the top of a file)
- `#scope_module` — visible to the files of this module, not to importers
- `#scope_file` — visible in this file only

```
// std/str.smelt
#import "std/mem";

fn equal(a: string, b: string) -> bool { ... }           // exported
fn starts_with(s: string, prefix: string) -> bool { ... }

#scope_module                                              // std/str's own files
fn utf8_width(c: u8) -> isize { ... }

#scope_file                                                // this file only
fn is_space(c: u8) -> bool { ... }
```

Top-level order doesn't matter, so a file puts its API first and its
helpers after one `#scope_file`: std's 170 `pub`s become about one line
per file. A declaration's visibility isn't written on it, so errors say
where it comes from: "`is_space` is private to std/str.smelt
(`#scope_file` at line 120)".

## 3. Metaprogramming

Jai's kind, in layers that build on what Smelt has (`#run`, `#insert`,
`#expand` macros with `Code`, `type_info`, `#if`, build scripts).

### Layer 1

```
struct Matrix($rows: isize, $cols: isize) { cells: [rows * cols]f32; }   // value parameters
fn sum(xs: []$T) -> T #where(is_numeric(T)) { ... }
#assert(sizeof(Header) == 16, "Header is 16 bytes in the file format");
fn log(message: string, at: Location = #caller_location) { ... }
struct Config { port: i64 @json("port"); }
fn parses_numbers() @test { ... }
const PRELUDE = #embed("prelude.smelt");
```

- **`$` value parameters**, on functions and structs: an instance per constant value, as `$T` gives one per type.
- **`#assert(condition, message)`**, at the top level, in functions, and in instances.
- **`#where(condition)`** after a generic signature, checked at the call before an instance is made: "`sum` needs `is_numeric(T)`, but T is `string` here". It's the first half of Jai's `#modify` (accept or reject); `#modify` can also change T, which Smelt needs less, since an `i64` parameter already takes narrower integers. A block that changes T can come later if real code needs it.
- **`#caller_location`** as a default argument: where the call is.
- **Notes**, `@name` and `@name(args)`, after the declaration (where `#nodiscard` goes on a function, after the type on a field). The compiler stores them and never interprets them: a field's notes are in its `type_info`, a declaration's in what layer 3 sees. Go's struct tags and Rust's attributes are the everyday versions.
- **`#embed("file")`**: the file's contents as a constant string, the path relative to this source file. (Jai's `#load` is something else: section 2.)

A generator reading notes, with layer 1 and today's `#insert #run`:

```
struct Config {
    port: i64 @json("port");
    debug_level: i64 @json("debug");
    cache: Map(string, string) @json_skip;
}

pub fn to_json(out: *[..]u8, value: $T) {
    #insert #run json_code(type_info(T));   // reads the fields and their notes
}

to_json(&buf, Config.{ .port = 8080, .debug_level = 2 });   // {"port": 8080, "debug": 2}
```

### Layer 2: code as data

- **`#code { ... }` / `#code expr`** make a `Code` value anywhere at compile time; `#insert` puts one into the program.
- **std/compiler** turns a `Code` value into a syntax tree to read or change, and back: `code_tree(c)`, `as_code(tree)`, `code_text(c)`, and builders (`binary(op, a, b)`, `number_code(k)`, `replace_name(c, "i", k)`, `append_code(&block, c)`).
- Inside `#code`, **`#insert x`** splices code and **`#run x`** splices a value computed now.
- Names in `#code` mean what they mean where the `#code` is written, the hygiene macros get, so generated code can't capture the caller's variables (which code made from strings can).

```
assert(total == expected);
// panic: assertion failed: total == expected (total is 41, expected is 42) at main.smelt:9:5

fn assert_code(c: Code) -> Code {
    let tree = code_tree(c);
    if (tree.kind is .Binary{op, lhs, rhs} && is_comparison(op)) {
        let l, r = as_code(lhs), as_code(rhs);
        return #code {
            let left = #insert l;                  // each side runs once
            let right = #insert r;
            if (!(#insert binary(op, #code left, #code right)))
                panic(tformat("assertion failed: % (% is %, % is %)", #run code_text(c),
                              #run code_text(l), left, #run code_text(r), right));
        };
    }
    return #code { if (!(#insert c)) panic(tformat("assertion failed: %", #run code_text(c))); };
}

unroll(4) { sum += a[i] * b[i]; }                 // four statements, i = 0, 1, 2, 3

fn unroll($times: isize, body: Code) #expand {
    #insert #run repeat(body, times);
}
fn repeat(body: Code, times: isize) -> Code {
    let block = #code {};
    for (k in 0..times)
        append_code(&block, replace_name(body, "i", number_code(k)));
    return block;
}
```

### Layer 3: whole-program metaprograms

A build script can follow the compiler as it checks the program, and add
code in response:

```
fn parses_numbers() @test { assert((parse_int("42") or_else 0) == 42); }

#run build();
fn build() {
    let tests: [..]string;
    for (msg in compiler_messages()) {
        switch (msg) {
        case .Checked{decl}: if (has_note(decl, "test")) array_add(&tests, decl.name);
        case .AllChecked:    add_code(test_main(tests));   // a main that runs each one
        }
    }
}
```

Test runners, serializers, registries and bindings come from this. Names
that code made later will declare may need declaring up front (Jai's
`#placeholder`).

### Types as values

Smelt does it Jai's way: generic structs (`struct List($T)`), `$T: Type`,
`type_info(T)`, plus:

- **`#insert` inside struct and enum bodies** (today: "expected a field name, found `#`").
- **Value parameters on structs** (layer 1).

```
struct SoA($T) {
    #insert #run soa_fields(type_info(T));        // one [..] per field of T
}
fn soa_fields(t: *TypeInfo) -> string {
    let out: [..]u8;
    for (f in t.fields) print_to(&out, "%: [..]%;\n", f.name, f.info.name);
    return out as string;
}
struct Particle { pos: Vec3; vel: Vec3; mass: f32; }
let ps: SoA(Particle);              // { pos: [..]Vec3; vel: [..]Vec3; mass: [..]f32; }

enum FieldOf($T) { #insert #run variant_names(type_info(T)); }
let which: FieldOf(Particle) = .mass;
```

Functions that return a `Type` (`fn uint_for($bits: isize) -> Type`) may
come later. Zig's `@Type` (a type built from a description) stays out:
`#insert` already builds types.

**What it asks of the compiler:** `#run`, `#insert` and checking
interleave, so the new checker is a job queue, where a declaration waits
for what it needs (Jai's design; the C++ checker does it ad hoc with
`ensure_resolved`, `ensure_body_checked` and deferred bodies).

## 4. Tagged enums: `!is`, checked access, narrowing

`is` keeps its bindings inside the `if` that tests it. (Bindings that
outlive a failed match were rejected: their scope would be invisible, and
a later `let` with the same name would clash.) Instead:

- **`!is`**: `if (n.kind !is .Switch) return;`
- **Checked access, `x.Variant`**: the variant's value, and a place you can assign to. When `x` is another variant it panics, like an index out of range, under the same setting as bounds checks.
- **Narrowing** removes that check where the compiler knows the variant: after `if (x is .V)`, or after `if (x !is .V) return;`. Only for locals and parameters that aren't assigned in between and whose address isn't taken; through a pointer the check stays.

```
if (n.kind !is .Switch) return;
let s = n.kind.Switch;              // a plain let: normal scope, normal name rules
resolve_expr(r, s.value);
n.kind.Switch.continued = true;

for (d in decls) {
    if (d.kind !is .Fn) continue;
    let f = d.kind.Fn;
    ...
}

let o = find(xs, 7);                // a ?isize
if (o !is .Some) return -1;
return o.Some;                      // no check: narrowed
```

## 5. Errors and results

### Error enums

```
enum IoError: Error { NotFound, PermissionDenied, IsDirectory }
enum ConfigError: Error { BadLine(line: isize), UnknownKey(key: string), CantRead(IoError) }
```

1. **`: Error` makes an error enum.** An integer type after `:` still sets a plain enum's representation, as in C23's `enum E : uint8_t`; an enum has one or the other. Plain enums go back to being plain: no special `None`, no conversion to `Error`, no `or_return`. (Today any enum with a 0 variant counts, so `Color.Green` and `AllocatorMode.Free` pass as `Error`s.)
2. **`None` comes from `Error`.** Every error enum has `None` at 0 without writing it, and its variants start at 1, so a zeroed `IoError` means "no failure". Writing `None` yourself is an error.
3. **Child to parent is implicit:** an `IoError` converts to `Error` (the enum and the variant; a payload is dropped).
4. **Parent to child is a checked match**, never implicit: `if (err is IoError(e))`, `case IoError(e):`.
5. **One level.** `enum FileError: IoError` isn't allowed: an enum is a closed set, so a child with more variants couldn't convert to its parent. `Error` is the one open type, which is why it holds any child.
6. Variant values fit in 32 bits, and an error enum doesn't choose its integer type (at first).
7. Tagged error enums carry data, as `ConfigError` does above.

### Results: `E!T`

`E!T` is the prelude's `Result(E, T)`, `enum Result($E, $T) { Ok(T), Err(E) }`,
written with the value last, as `?T` is `Option(T)` and every type
constructor is a prefix (`?T`, `*T`, `[]T`).

```
fn read_file(path: string, a: Allocator = context.allocator) -> IoError!string {
    ...
    if (file == null) return last_io_error();     // a failure: Err
    ...
    return data[..len] as string;                 // a value: Ok
}

fn write_file(path: string, data: string) -> IoError!void {
    ...
    if (written != size) return last_io_error();
}                                                 // the end: success

fn parse_prefix(s: string) -> ParseError!(i64, isize)    // several values

fn load_config(path: string) -> !Config {         // the failure type is inferred
    let text = read_file(path) or_return;         // IoError
    let port = parse_int(text) or_return;         // ParseError
    return .{ .port = port };
}                                                 // two error enums: Error!Config

fn main() -> !void {
    ...
}
```

- **`E!void`**: nothing, or a failure. Reaching the end of the function is success.
- **`!T` infers the failure type**: the one error enum the body fails with, or `Error` when it fails with several. It must be written for recursive functions ("`walk`'s failure type depends on itself; write it, like `IoError!void`"), function types and `extern` functions, and a body that never fails makes the `!` an error. Messages name the inferred type ("found `Error!Config` (`load_config`'s failure type is inferred from its body)"). std writes its failure types: its signatures are documentation.
- **E can be any type**; error enums are the normal case, and the ones that convert to `Error`. A quick tool can return `string!Config`.
- **Wrapping**: a value becomes `Ok`, a failure `Err`; when T and E are the same type, write `.Ok(x)` or `.Err(x)`. The same goes for `?T` (`let o: ?i64 = 5;` is `.Some(5)`). Not for other tagged enums: the variant's name is the point there.
- **Zero** is `Ok` holding a zero value.
- **Several values with a failure** (`ParseError!(i64, isize)`) need tuples to be storable in a `Result`: a small extension.
- **`fn main() -> !void`**: a failure is printed (`error: %w`) and the exit code is 1.
- **Tuples keep their meaning**: `(T, U)` is always both. A partial result and a failure are `(Config, ?ConfigError)`. `or_return` on `(T, E)` tuples stays while std moves to results, then gets decided.

### Handling one

```
let text = read_file(path) or_return;             // pass it on (as an Error, if that's the result type)
let text = read_file(path) or_else "";            // a fallback
let text = read_file(path) or_return .CantRead;   // replace it: the IoError goes inside CantRead
let text, err = read_file(path);                  // both sides: the value (zero if it failed),
if (err != .None) { ... }                         //   the failure (None if it didn't)
let err = write_file(path, data);                 // E!void: only the failure

let r = load_config(path);
if (r is .Err(e)) {
    eprintln("can't load %: %w", path, e);
    return;
}
let cfg = r.Ok;                                   // narrowed: no check

switch (load_config(path)) {
case .Ok(c):                       run(c);
case .Err(.CantRead(.NotFound)):   use_defaults();     // nested patterns see the whole stack
case .Err(e):                      eprintln("%w", e);
}
```

- `or_return .Variant` puts the failure inside the variant when the variant holds its type, and replaces it otherwise.
- Destructuring works when the failure type has `None` (error enums and `Error`); others use `is`, `switch` or `or_else`.

### Dropped failures

Not everything has to be a language rule: the default is a warning,
`#nodiscard` makes it an error, and flags and build options set the level
for the lenient or the strict, as `--bounds-checks` does for checks.

```
[warning]: this drops `read_file`'s result, and with it the failure (IoError) at [main.smelt:9:5]
     9 |     read_file(path);
       |     ^
[note]: handle it:   let text, err = read_file(path);
        pass it on:  read_file(path) or_return;
        drop it:     _ = read_file(path);
```

- **`#nodiscard`** on a function makes the same message an error. `_ =` still counts as receiving it: it's explicit.
- **Levels**: `--dropped-failures ignore|warn|error` on the command line, `set_dropped_failures(.Error)` in a build script; the command line wins.
- Flags change diagnostics, never meaning, and apply to the program's own modules; std stays clean under `error`. The same scheme can later cover the other warnings (`--warnings error`).

### Stacking, and what `Error` keeps

Errors stack by wrapping, not by deeper inheritance: a variant holds the
cause (`CantRead(IoError)` above), and `or_return .CantRead` puts it
there. `%w` prints the whole stack:
`AppError.Config(ConfigError.BadLine(line = 12))`.

Converting to `Error` is lossy: an `Error` is one 64-bit number (32 bits
for the enum, 32 for the variant), so a payload has no room and is
dropped:

```
fn start() -> Error!void {
    let cfg = load_config("app.cfg") or_return;   // ConfigError.BadLine(12) becomes an Error
}
// error: ConfigError.BadLine                      (the 12 is gone; `is ConfigError(e)` still works)
```

Ways to keep the details: inference keeps the specific type when there's
only one; an app-level error enum wraps its causes
(`enum AppError: Error { Config(ConfigError), Io(IoError) }`); debug
traces record them. Lossy stays for now, **to be reconsidered after the
compiler is finished** (the options: room for a small payload inside
`Error`, or the failure's text captured into the context when it becomes
an `Error`, like C's `errno`).

A string payload is a view, so it must outlive the function returning it:
`return .UnknownKey(key)` with `key` pointing into a buffer a `defer`
frees is trap 6. Copy it (`copy_string`, or `tformat` for short-lived
ones).

### Debug failure traces

In debug builds, each `or_return` that passes a failure on records where
and what, and `main`'s report prints the record:

```
error: ConfigError.CantRead
  from IoError.NotFound at config.smelt:12:30, in load_config
  passed on at main.smelt:5:21, in main
```

## 6. Smaller additions

From writing the compiler in Smelt:

- **Named variant construction**: `.Let{ .declared = t, .uninit = true }`, the rest defaulted, in struct-literal syntax (today a variant is built positionally: `.Let(null, null, false, false, false)`).
- **`for (x, i in xs)`**: the element and its index.
- **`let a, b, c: *Node;`**: several names of one type, zeroed (today names declared together can't have types).
- **Keywords as field names**, after `.`, in field lists and in `.name =`: a compiler wants `type`, `else` and `default`.
- **Null checks** in checked builds: `file:line: panic: null pointer`, under the same setting as bounds checks (today it's a bare segfault, exit 139).
- **A message fix**: `K.Let{ ... }` suggests `K.Let.{ ... }`, which then fails with "`Let` is not a struct type".

## 7. How it lands

1. **Port the checker** (next), matching the C++ on existing programs, but built for this plan: a job queue; instances keyed by constant values as well as types; `Option`, `Result` and error enums as rules of the type system; flow facts for narrowing; notes kept on declarations and fields.
2. **Port the C backend and the VM.**
3. **Bootstrap**: the compiler compiles itself; std and the compiler move to the new syntax.
4. **Build the features**, each with tests, in about this order: formatting; error enums, results, wrapping, destructuring, `%w` and the dropped-failure warning; `!is`, checked access and narrowing; `#import`, `#load` and the scopes; layer 1; layer 2; types as values; layer 3; the smaller additions. A feature can start as soon as the phase it needs exists in the new compiler.

## 8. Long term

- **Compile time** is fine for now and stays as it is. Later: better generated C, the choice of C compiler, or our own IR or x64 backend.
- **Inline assembly**: passed to the C compiler's `__asm__` (cheap, GCC syntax, per CPU), or Jai's `#asm` with the compiler choosing registers (needs our own backend). `#run` can't run either.
- **`Error` keeping payloads** (section 5).
- **A `#modify`-style block** that can change T, if `#where` isn't enough.
- **Functions that return a `Type`.**
- **`io :: #import "std/io"` and module parameters.**
- **`#import` inside a top-level `#if`** (today an error).

Still deferred, outside this plan (see Smelt-decisions.md and the review's
checklist): C types (`c_int`, ...), Jai's `,,` syntax, assigning to
parameters, by-pointer loops, writable `.len`/`.ptr`, UTF-8 and the
math, random and thread modules.
