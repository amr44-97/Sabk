# Sabk design review

Oct 17, 2026 · @amr

Sabk's shape is right: C's simplicity, Odin's context, Jai's metaprogramming and OCaml's sum types, compiled through C. Where it goes wrong, it either stops short of its own ideas or quietly changes what C code means. One rule catches most of the second kind: when Sabk fixes a C trap, the old spelling should fail to compile, not mean something new.

## Change checklist

One task per change, in section order. The changes decided since (Oct 19, for the self-hosted compiler) are in Sabk-language-plan.md.

- [x] **1.** Make `.len` signed and `isize` the default integer.
- [x] **2.** Add nested patterns that follow pointers, and `if` guards on cases; check exhaustiveness with Maranget's algorithm. (Also `_` to name nothing, and unreachable cases reported.)
- [x] **3.** Allow tagged enums as failure values, mark failure enums `#error`, and let `or_return` wrap a failure into the one variant that holds its type. **Decided 2026-10-18: keep the error system as it is** (a `bool` or an enum, `or_return`, `or_else`); no `#error`, no conversion between specific enums. **2026-10-19: a built-in `Error`** (prelude), which every failure enum widens to (enum id + variant in a u64), so `or_return` crosses enums and `fn main() -> Error` prints `error: IoError.NotFound` and exits 1; only `-> Error` may fall off its end; bools don't widen; no payload, no location trace. Research: reports/Sabk error propagation problems.md. Later: better unions and union ergonomics in general (not error unions).
- [x] **3.** Keep dropped results legal; add `#nodiscard` for functions and `#error` enums, with `_ =` to drop on purpose. (Functions and macros only, since there's no `#error`; `_ = expr;` drops any value.)
- [x] **4.** Add `if` expressions, labeled blocks and `break label = value`. (Labeled switch expressions take cases of statements too.)
- [x] **5.** Keep C's order for arithmetic, and make a bit or shift operator next to a different operator an error without parentheses.
- [x] **6.** Decided 2026-10-18: keep Jai's writable `string`, with no owned string type. The literal crash is documented (docs/reference.md, Strings), and `Builder` is built on `[..]u8`.
- [x] **8.** (0feda5f) Add top-level `#if` and the target constants `OS`, `ARCH` and `POINTER_SIZE`.
- [x] **9.** (74b68e9) Add a logger and a panic handler to `Context`.
- [ ] **10.** Make a zero `Map` usable, add a generic `delete`, and drop the type-suffixed families; plan math, time, file system, random, threads, processes and UTF-8.
  - [x] A zero `Map` is ready to use: std/reflect's hash and equality, `context.allocator`.
  - [x] `delete(x)` in std/mem for strings, slices, `[..]T`, `Map` and `Builder`; anything else is a compile error. It needed `#if (T == Map)` (any instance of a generic struct), and a fix: an `#insert #run` in an `#if` branch that isn't taken no longer runs.
  - [x] `print_int`, `_uint`, `_float`, `_bool`, `_char` and `builder_append_int`, `_uint`, `_float`, `_bool` are gone: `print("%", x)`, `print("%{.2}", f)`, `builder_print(&b, "%", x)`. Kept: `builder_append_char` (one byte) and `format_int`/`format_uint` (into a buffer, no allocation).
  - [ ] Plan the missing modules: math, time, file system and paths, random, threads and atomics, processes, UTF-8. **Deferred** by the user (2026-10-18): "keep the utf8 and the missing modules for later". Proposed order when it's picked up: UTF-8 in std/str, std/math, std/fs, std/time, std/random, std/process, std/thread (last: each thread needs its own Context). **2026-10-19, for the compiler's rewrite in Sabk:** std/path, std/fs (directories), std/process and std/time are in, POSIX only. Left: UTF-8, math, random, threads.
- [x] **11.** (built as Jai's `.[...]`, ddb032f) Use `[...]` for array and slice literals, with element inference and arrays passing as slices; keep `.{...}` for structs and unions.
- [x] **12.** (0160dde, 0c698c8, 448ce6a) Make `void` a real zero-size type, and replace `rawptr` with `*void`.
- [x] **Option:** put `None` first, add `?T` as shorthand, and let `or_else` take an `Option` or a pointer. (2026-10-19: `pub enum Option($T) { None, Some(T) }` in the prelude; `?T` always names it, also in expressions like `type_info(?i64)`, and types print as `?i64`; `or_else` takes a `?T` or a pointer; `or_return` on a `?T` is an error that points to `or_else`.)
- [ ] **Smaller issues:** the misleading-indentation error, the slice-literal note, `= ---`, and what `return` does in macro blocks. (`= ---` is done; the slice-literal note is traps 1 and 2 in the reference; `return` and `or_return` in macro blocks are documented under Macros. Left: the misleading-indentation error.)
- [x] **Doc inconsistencies:** fix the five listed. (2026-10-18, with a docs pass: Coming from C, Strings/bytes/Builder, Handling errors, Memory and the 14 traps.)
- [x] **`[..]T` ergonomics:** make growable arrays easier to use.
  - [x] `buf as string` on a `[..]u8`, a view of its bytes as text (in `can_cast`; both backends' `convert` view it). The type error passing a `[..]u8` as a `string` suggests `raw as string`.
  - [x] Appending text to a `[..]u8` without `as []u8`, and formatting into one: `append_string(&buf, s)` in std/str and `print_to(&buf, fmt, ..args)` in std/fmt (a `#format` function, so its format is checked; it formats through a `Builder` sharing the bytes).
  - [x] A `[..]u8` still prints as numbers, so text that should print as text stays in a `Builder` (or is printed through `builder_string`). **Decided 2026-10-19: keep it as is.** A `[..]u8` is bytes and prints as numbers, like `[]u8`; `buf as string` prints it as text. `Builder` stays, and prints as a struct.
  - [x] Common helpers: building an element in place (`array_add_new`, left out when `[..]T` was built), and finding or removing an element by value. `array_add_new(&xs) -> *T` (the element starts with its fields' defaults), `array_find(xs: []$T, item) -> isize` (-1 when missing) and `array_remove_value(&xs, item) -> bool` (the first equal one, order kept), comparing with std/reflect's `values_equal`.
  - [x] Reaching the elements through a `*[..]T` takes `xs.*[i]`, all over std/array. Weigh making `xs[i]` on a `*[..]T` index the elements (it's never meant as pointer arithmetic) against keeping `p[i]` the same for every `*T`. **Decided 2026-10-19: neither; `p[i]` and `p[lo..hi]` on a `*[..]T` are errors** that suggest `p.*[i]` (and `(p + i).*` for the pointer arithmetic), so the C spelling fails instead of changing meaning. Not in generic instances, where a `*T` may point into an array of `[..]U`, nor on `.ptr` (`Checker::indexes_growable_pointer`).
- [x] **Warnings for the memory traps** (Sabk-memory-traps.md): find a way to catch them, through reference counting or something else. **Done 2026-10-19:** warnings for traps 1-5, 8, 9, 12 and 13 (`Checker::check_traps`, one function at a time, through blocks and loops), and `--sanitize` (ASan) for the rest at run time, with the temp allocator and arenas poisoning what they take back (`sabk_poison`/`sabk_unpoison` in the C runtime). Not done: the debug allocator, reference counting, generation checks, and the `#run` literal-store error. The options that were weighed:
  - **Sanitizers, the cheapest.** A debug option that builds with `-fsanitize=address`. It already works through `add_c_flags("-fsanitize=address")`: trap 8 reports `heap-use-after-free` at the Sabk line that read the freed memory and at the `array_add` that freed it, because the C carries `#line`. It only sees `malloc` and `free`, so the temp allocator and arenas would have to poison their memory with ASan's API to be covered.
  - **A debug allocator.** It wraps any allocator, reports leaks and double or invalid frees, and fills freed memory with a pattern so a use after free shows. Std only, no compiler change.
  - **Reference counting, in debug builds.** Count the copies sharing a `[..]T`, `Builder` or `Map` block, and report freeing or growing it while another copy still uses it (traps 8 and 13). The compiler has to emit the counting at every copy, and views aren't covered (traps 6 and 7) unless they're counted too, which is Swift's cost on every slice.
  - **Generation checks.** Each allocation gets a generation number, views carry it, and an access through a stale view panics (traps 6 and 7). Views get bigger in debug builds, which changes their layout for C.
  - **Compiler checks for the patterns it can see.** Growing a sequence inside a loop over it (trap 12), growing a by-value parameter (trap 13; immutable parameters, deferred, would catch it), and writing through a string that came from a literal (trap 9).
  - **`#run`:** make a store into a literal's memory fail as a compile error, so `#run` matches the program instead of keeping the write.

Section 7 needs no change: a plain `break` already leaves the switch.

## What's right

These decisions serve the goals you named, and I'd keep them as they are:

- **Keyword-first declarations, types after names, primitives as plain identifiers.** Every file parses alone, and the parser never needs to know what a name means. C's typedefs never allowed that.
- **Modules.** A plain import gives bare names plus the qualified form, clashes are errors only where they're used, and top-level order doesn't matter. No headers, no include guards, and none of Zig's `@import` boilerplate.
- **The context.** Scoped assignment, allocators as default parameters and a temp arena remove Zig's allocator threading without hiding where memory comes from.
- **C's traps removed, C's feel kept.** Left-to-right evaluation, assignment as a statement, no fallthrough, defined overflow and a division-by-zero panic. Bounds checks, string `==` by content, checked format strings and the escape check for locals.
- **Sum types done properly.** Named variant fields, exhaustiveness errors that list what's missing, `&` bindings, `is` with bindings in conditions, switch expressions and labeled-switch state machines.
- **Jai's metaprogramming, not Zig's.** `#run` runs ordinary code, C included. `#insert`, hygienic `#expand` macros and compile-time `type_info` turn derive-style generation into plain Sabk, as std/reflect shows.
- **The C backend.** `#line` mapping makes gdb, lldb and sanitizers speak Sabk, unused code never reaches C, and build scripts live in the language.
- **Failures are ordinary values.** No error unions in signatures and nothing forces a `try`; `or_return` and `or_else` read left to right at the end of the call.

## What to change

Sections 1 to 10 are in order of how much they matter for the goals you described. Sections 11 and 12 were decided in discussion afterwards.

### 1. Numbers: signed lengths and one default integer

An untyped integer `let` is an `i32`, `.len` is a `usize`, and a `usize` never meets a signed type without `as`. That combination is where Zig's cast noise comes from, and Sabk has all three parts:

**Before** (current design):

```
fn average(xs: []i64) -> i64 {
    let total: i64 = 0;
    for (x in xs) total += x;
    return total / xs.len as i64;              // usize won't mix with i64
}

fn print_reversed(xs: []string) {
    for (let i = xs.len - 1; i >= 0; i -= 1)   // usize: i >= 0 is always true,
        println("%", xs[i]);                   // so the loop ends in a bounds panic
}

let seen = 0;                                  // i32
seen += xs.len as i32;                         // a cast, and it wraps past 2^31
```

**After** (suggested):

```
fn average(xs: []i64) -> i64 {
    let total: i64 = 0;
    for (x in xs) total += x;
    return total / xs.len;                     // isize widens to i64 on its own
}

fn print_reversed(xs: []string) {
    for (let i = xs.len - 1; i >= 0; i -= 1)   // isize: stops after 0, and an empty
        println("%", xs[i]);                   // slice starts at -1 and never enters
}

let seen = 0;                                  // isize
seen += xs.len;
```

Make `.len` signed, and make the same type the default for untyped integers. Go and Odin both do this with `int`, a pointer-sized signed integer; in Sabk that's `isize`. Overflow wraps silently, so an `i32` default also turns large counts negative without a panic.

Unsigned types stay for bit work and C interop.

### 2. Patterns: nesting and guards

The syntax is OCaml's, but not yet the power. A variant's fields can only be bound or renamed, never matched, so anything that looks one level down needs `is` inside an `if`, or a second switch. Here is an AST simplifier both ways.

**Before** (current design):

```
fn simplify(e: *Expr) -> Expr {
    switch (*e) {
    case .Binary{op, lhs, rhs}:
        if (op == .Mul && *lhs is .Number(n) && n == 0) return .Number(0);
        if (op == .Add && *rhs is .Number(n) && n == 0) return *lhs;
        return *e;
    case .Negate(inner):
        if (*inner is .Negate(inner2)) return *inner2;
        return *e;
    case .Number(n):
        if (n > MAX) return .Number(MAX);
        return *e;
    default:
        return *e;
    }
}
```

**After** (suggested):

```
fn simplify(e: *Expr) -> Expr {
    switch (*e) {
    case .Binary{op: .Mul, lhs: .Number(0)}:      return .Number(0);
    case .Binary{op: .Add, lhs, rhs: .Number(0)}: return *lhs;
    case .Negate(.Negate(inner)):                 return *inner;
    case .Number(n) if (n > MAX):                 return .Number(MAX);
    default:                                      return *e;
    }
}
```

Two additions get there:

- **Nested patterns.** Wherever a binding name can go, allow a pattern. Patterns follow pointers on their own, as `p.x` does, so a `*Expr` field matches `.Number(0)` directly. A bare name still binds; constants are matched as literals, `.Variant` or qualified names.
- **Guards.** `case .Number(n) if (n < 0):`, with the pattern's names in scope. A guarded case doesn't count toward exhaustiveness.

The exhaustiveness check then needs Maranget's usefulness algorithm, which OCaml and Rust both use. `is` already acts as a guard in `if` and `while`; this brings the same to `switch`.

How the check works, from Luc Maranget's "Warnings for pattern matching" (2007): a row of patterns is *useful* if some value matches it and no earlier row. A switch is exhaustive when a lone `_` isn't useful after all its cases, and case *i* is unreachable when it isn't useful after cases 1 to *i*−1.

```
useful(P, q):                          // P: earlier rows, q: the row being tested
    if P has no rows:     return true
    if q has no columns:  return false
    if q[0] is a variant c:
        return useful(specialize(P, c), specialize(q, c))
    // q[0] is a wildcard
    cs = the variants named in P's first column
    if cs is every variant of the enum:
        return any(useful(specialize(P, c), specialize(q, c)) for c in cs)
    return useful(default(P), q without its first column)

specialize(rows, c): keep rows whose first pattern is c or _, replacing it
                     with c's sub-patterns (or that many _)
default(rows):       keep rows whose first pattern is _, minus that column
```

Returning the missing value instead of `true` gives the error its example, such as `.Negate(.Negate(_))`. Guarded cases are left out of the exhaustiveness check. Integers and strings never form a complete set, and integer ranges need splitting into intervals.

### 3. Errors: tagged enums as failures, declared, with one conversion

Three things leave error handling behind the rest of the language:

- **Any enum whose 0 means success is a failure value**, as far as the compiler can tell. `next_token() -> (Token, TokenKind)` accepts `or_return` and bails on every kind but the first.
- **Failures can't change type**, so every function that combines `read_file` and `parse_int` converts by hand. Those `if` blocks are Sabk's version of the noise you disliked in Zig.
- **Only plain enums are described as failure values**, so an error can't say which line or which key.

The parts already exist, so the fixes are small. A tagged enum whose first variant holds nothing works as a failure value. Mark failure enums in your directive style, so only they and `bool` work with `or_return`.

**Before** (current design):

```
enum ConfigError { None, CantRead, BadLine, UnknownKey, BadNumber }

fn load_config(path: string) -> (Config, ConfigError) {
    let text, err = read_file(path);
    if (err != .None) {
        println("can't read %: %", path, io_error_message(err));
        return .{}, .CantRead;                   // the IoError itself is lost
    }
    defer free(text.ptr);
    return parse_config(text);
}

// in parse_config
let n, perr = parse_int(value);
if (perr != .None) {
    println("`%` isn't a number: %", value, perr);
    return config, .BadNumber;
}

println("failed: %", err);                       // failed: BadNumber
write_file(path, data);                          // a failure vanishes
let tok = next_token() or_return;                // compiles: bails on every TokenKind but the first
```

**After** (suggested):

```
enum ConfigError #error {
    None,
    CantRead(IoError),
    BadLine(i64),
    UnknownKey(line: i64, key: string),
    BadNumber(line: i64, cause: ParseError),
}

fn load_config(path: string) -> (Config, ConfigError) {
    let text = read_file(path) or_return;        // an IoError becomes .CantRead
    defer free(text.ptr);
    return parse_config(text);
}

// in parse_config: no printing, the caller decides
let n, perr = parse_int(value);
if (perr != .None) return .{}, .BadNumber(line, perr);

pub fn trim(s: string) -> string #nodiscard { ... }   // the author opts in, like #format

println("failed: %", err);                       // failed: BadNumber(line = 3, cause = InvalidDigit)
write_file(path, data);                          // allowed: the failure is ignored, as in C
printf("hi\n");                                  // allowed, as in C
trim(s);                                         // error: trim is #nodiscard, and this line does nothing
_ = trim(s);                                     // dropped on purpose
let tok = next_token() or_return;                // error: TokenKind isn't an #error enum
```

The `or_return` in `load_config` is the one conversion: it wraps a failure into the only variant that holds its type, as Rust's `?` does through `From`. `BadNumber` holds a line as well as the cause, so it's built by hand. Printing needs no extra code, since tagged enums already print their fields.

Decided: any result can be dropped, failures included, as in C. A dropped failure is simply ignored and the program continues. A panic there would be hidden control flow, and many drops are deliberate, such as deleting a file that may not exist.

A function opts out with `#nodiscard`, placed like `#format`; it's the same idea as C23's `[[nodiscard]]`. Dropping its result is an error, and `_ =` drops it on purpose.

`#nodiscard` can also go on an `#error` enum, as C23 allows `[[nodiscard]]` on a type: `enum AllocError #error #nodiscard { None, OutOfMemory }` makes every function returning it must-use. C only warns, and GCC's older `warn_unused_result` ignores even a `(void)` cast, so `_ =` must always work.

A function that only reports failure can also be written `-> (void, IoError)`, so its signature has the same shape as every other failable one; see section 12.

Use it where dropping the result is always a bug: pure functions such as `trim` and `parse_int`, and allocating ones such as `copy_string` and `format`. `trim(s);` alone does nothing, since strings are views.

When a failure must stop the program, say so at the call: `assert(write_file(path, data) == .None);`. A build flag that panics on dropped failures can help when hunting a bug, as sanitizers do, without changing what the language means.

The separate error spec came before this reference. Where they differ, keep the reference's `or_else` precedence and named payload fields, use `#error` instead of `error enum`, and replace the spec's must-use rule with `#nodiscard` on functions.

### 4. Expressions: `if` and labeled blocks with values

Sabk has no conditional expression: no `?:` and no `if` expression, so choosing between two values takes a mutable variable and an `if` statement. Switch-expression cases are single expressions too, so a case that needs a statement first can't give a value.

Both fixes reuse syntax you already have:

**Before** (current design):

```
let sign = 1;
if (x < 0) sign = -1;

let size: f64;
switch (shape) {
case .Circle(r): size = 3.14159 * r * r;
case .Rect{w, h}:
    if (w < 0 || h < 0) println("negative rect: % x %", w, h);
    size = w * h;
}

let workers, err = parse_int(text);
if (err != .None) {
    println("bad worker count '%', using 1", text);
    workers = 1;
}
```

**After** (suggested):

```
let sign = if (x < 0) -1 else 1;

let size = s: switch (shape) {
case .Circle(r): 3.14159 * r * r;
case .Rect{w, h}:
    if (w < 0 || h < 0) println("negative rect: % x %", w, h);
    break s = w * h;
};

let workers = parse_int(text) or_else w: {
    println("bad worker count '%', using 1", text);
    break w = 1;
};
```

`break label = value;` mirrors the `continue label = value;` that labeled switches already have. Labels already exist on loops and switches, so allowing them on blocks is the only other grammar change. On a labeled switch expression, the same `break` lets a case run statements before giving its value.

### 5. Precedence: make mixing an error, not a new meaning

The Go table fixes `a & MASK == 0`, but it also changes correct C that a C programmer will write without thinking:

| Expression | C reads it as | Sabk reads it as |
| --- | --- | --- |
| `x >> 8 * k` | `x >> (8 * k)` | `(x >> 8) * k` |
| `n + align - 1 & ~(align - 1)` | `(n + align - 1) & ~(align - 1)` | `n + align - (1 & ~(align - 1))` |
| `a \| b + c` | `a \| (b + c)` | `(a \| b) + c` |
| `1 << n + 1` | `1 << (n + 1)` | `(1 << n) + 1` |

Keep C's order for arithmetic, and make a bit or shift operator next to a different operator a compile error without parentheses. A chain of one operator, like `a | b | c`, stays legal. No C habit changes meaning silently, and `a & MASK == 0` gets an error that says what to write.

**Before** (current design):

```
fn get_byte(word: u64, k: u64) -> u64 {
    return word >> 8 * k & 0xFF;               // compiles as ((word >> 8) * k) & 0xFF
}

fn align_up(n: usize, align: usize) -> usize {
    return n + align - 1 & ~(align - 1);       // compiles as n + align - (1 & ~(align - 1))
}
```

**After** (suggested):

```
fn get_byte(word: u64, k: u64) -> u64 {
    // `word >> 8 * k & 0xFF` is an error: parenthesize `>>` next to `*` and `&`
    return (word >> (8 * k)) & 0xFF;
}

fn align_up(n: usize, align: usize) -> usize {
    // `n + align - 1 & ~(align - 1)` is an error: parenthesize `&` next to `-`
    return (n + align - 1) & ~(align - 1);
}

let all = a | b | c;                           // one operator, chained: still fine
```

### 6. Strings: read-only views

Writable strings keep the C string trap you wanted gone: `s[0] = 'J'` compiles for any string and crashes when it came from a literal. Since `split`, `trim` and slicing all return views, a write through one also changes text that other code is holding.

Make `string` read-only and keep `[]u8` as the writable form, as Go does. The conversions are already right: bytes become text on their own, and `s as []u8` is explicit, so the one risky step is visible where it happens. The compiler can reject `as []u8` on a literal outright.

**Before** (current design):

```
let s = "hello";
s[0] = 'J';                              // compiles, then crashes: literals are read-only memory

let parts = split(line, ",");
parts[0][0] = 'X';                       // also rewrites `line`, which every part points into
```

**After** (suggested):

```
let s = "hello";
s[0] = 'J';                              // error: a string is read-only
let lit = "hello" as []u8;               // error: a literal's bytes can't become writable

let buf = copy_string("hello") as []u8;  // your own memory, as bytes
buf[0] = 'J';                            // fine
let text: string = buf;                  // bytes become text on their own: "Jello"

let parts = split(line, ",");
parts[0][0] = 'X';                       // error: read-only, so `line` can't change behind your back
```

### 7. `break` inside `switch`: keep C's meaning

Decided: a plain `break` in a case leaves the switch, as in C, and leaving the loop takes the loop's label. That keeps C code meaning what it meant, which is the rule this review argues for.

Without fallthrough, a plain `break` is only needed to end a case early. The trap that remains, expecting it to leave the loop, is one C programmers already know.

**Before** (a `break` meant to stop the loop):

```
for (cmd in commands) {
    switch (cmd) {
    case "quit": break;                  // leaves the switch; the loop keeps going
    case "save": save();
    default:     run(cmd);
    }
}
```

**After** (decided: plain `break` for the switch, the label for the loop):

```
loop: for (cmd in commands) {
    switch (cmd) {
    case "quit": break loop;             // the label: leaves the loop
    case "skip":
        if (dry_run) break;              // plain break: leaves the switch, as in C
        skip_next();
    case "save": save();
    default:     run(cmd);
    }
}
```

### 8. Platform code: top-level `#if` and target constants

Platform code is the one job C's preprocessor does well, and Sabk has no replacement yet. `#if` works only inside functions, there are no constants for the target OS or architecture, and both branches are name-resolved. A struct whose layout differs by platform, or a call that only exists on Windows, has nowhere to go but `#insert #run`.

Add `#if` at the top level and built-in target constants such as `OS`, `ARCH` and `POINTER_SIZE`. Keep the typo check by letting untaken branches see names declared in any branch, while taken code only sees the branch that was taken.

**Before** (current design):

```
// no top-level #if and no target constants, so platform declarations
// come from a string built at compile time
fn stat_decl() -> string {
    if (host_is_windows())               // a #run helper you write, calling C
        return "struct Stat { size: i64; mode: u16; }";
    return "struct Stat { dev: u64; ino: u64; mode: u32; size: i64; }";
}
#insert #run stat_decl();
```

**After** (suggested):

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

### 9. Context: a logger and a panic handler

Allocators are only part of what Jai and Odin put in the context. With a logger and a panic handler there too, library code reports problems the way its caller chose, instead of calling `println` itself. std's `panic` and `assert` would call the handler rather than abort directly, so tests can turn panics into failures without changing the code they test.

**Before** (current design):

```
fn parse_config(text: string) -> (Config, ConfigError) {
    ...
    println("`%` isn't a number", value);       // the library prints; callers can't stop it
    ...
}

assert(count > 0);                              // a failure aborts the whole test run
```

**After** (suggested):

```
fn parse_config(text: string) -> (Config, ConfigError) {
    ...
    log(.Warning, "`%` isn't a number", value); // goes wherever context.logger sends it
    ...
}

fn test_bad_port() {
    let logs: List(string);
    context.logger = capture_logger(&logs);     // scoped, like context.allocator
    context.panic_handler = fail_test;          // assert and panic call this instead of aborting
    let _, err = parse_config("port = 90x\n");
    assert(err is .BadNumber && logs.items.len == 1);
}
```

### 10. Standard library: traps and gaps

The standard library is where you said C lets you down, so its traps matter as much as the language's:

- **A zero `Map` panics on insert**, one of Go's best-known traps. `map_put` knows `K` at compile time, so it can fall back to std/reflect's hash and equality, and a zero `Map` can be ready to use like a zero `List`.
- **Freeing differs by type**: `free(s.ptr)`, `list_free`, `map_free`, `builder_free`. One generic `delete(x)` for strings, slices, lists and maps, as Odin has, is easy with `#if`.
- **Type-suffixed families** such as `print_int` and `builder_append_int`, `_uint`, `_float` and `_bool` are C habits that `Any`, `#format` and generics make unnecessary.
- **Missing modules** a C replacement needs early: math, time, file system and paths, random numbers, threads and atomics, and processes. UTF-8 too: `for (c in s)` gives bytes, and std/str can't walk characters.

**Before** (current design):

```
let counts: Map(string, i64);
map_put(&counts, "a", 1);                // panics: a zero Map can't hash its keys

free(name.ptr);                          // plus list_free, map_free, builder_free
list_free(&xs);

builder_append_int(&b, n);               // one function per type
builder_append_float(&b, x);

for (c in "héllo") count += 1;           // 6: bytes, not characters
```

**After** (suggested):

```
let counts: Map(string, i64);
map_put(&counts, "a", 1);                // works: hash and equality come from std/reflect

delete(name);                            // one call for strings, slices, lists, maps, builders
delete(xs);

builder_print(&b, "% %", n, x);          // already in std/fmt: any type, one call

each_rune("héllo") { count += 1; }       // 5: a macro that decodes UTF-8
```

### 11. Literals: square brackets for arrays and slices

Decided: `[...]` is the literal for arrays and slices, and `.{...}` is only for structs and unions. Brackets mean sequences and braces mean records, so a reader can tell `[1, 2]` from a `Vec2` at a glance.

1. With a type from context, such as a declared type, a parameter or a return type, the literal takes it, as `.{...}` does today.
2. With no context, the elements decide. They must agree the way the two sides of `+` do, the rule generics already use for `T`, and the literal is an array. An array is a value, so it has no lifetime limit and no loop aliasing.
3. `[]T{...}` and `[N]T{...}` stay for writing the type out.
4. An array variable or constant goes where a slice is expected, the way a C array decays to a pointer. Today only `*[N]T` converts.

`[` at the start of an expression now begins either a literal or a type, such as `[4]i32{...}` or `[]u8` passed as a type argument. The parser tells them apart without looking up any names:

- **A literal:** a comma inside, or `[]` followed by something that can't start a type.
- **An array type:** `[e]` followed by something that can start a type.

The only misreads are indexing a one-element literal and `[x] * y`, which is a type error either way.

**Before** (current design):

```
const DAYS = []string{"mon", "tue"};
for (s in []string{"abc", "def"}) ...
for (s in .{"abc", "def"}) ...               // error: nothing says the type
let grid: [2][3]i32 = .{ .{1, 2, 3}, .{4, 5, 6} };
let p: Point = .{ .x = 1, .y = 2 };
```

**After** (decided):

```
const DAYS = ["mon", "tue"];
for (s in ["abc", "def"]) ...
let grid = [[1, 2, 3], [4, 5, 6]];           // [2][3]isize: the elements decide
let mix = [1, 2.5];                          // [2]f64: they agree as in 1 + 2.5
let bad = [1, "x"];                          // error: the elements don't agree
let empty: []i32 = [];                       // the context decides
sum([1, 2, 3]);                              // []i32 from sum's parameter
print_all(DAYS);                             // an array goes where a slice is expected
let p: Point = .{ .x = 1, .y = 2 };          // structs keep .{}
```

**The one-element case:**

```
let grid: [2][3]i32;              // why the rule exists: `[2][3]` starts an array type

let first = [x][0];               // error: read as the start of an array type
let first = ([x])[0];             // parentheses make it a literal, then index it
let first = [x, y][0];            // a comma makes it a literal: fine
```

The error should say how to fix it: "`[x][0]` is read as an array type; to index a one-element literal, write `([x])[0]`."

### 12. `void`: a real zero-size type, and `*void` for untyped pointers

Decided: `void` becomes a real type with zero size and one value, `.{}`, allowed anywhere a type is. `*void` replaces `rawptr`, as in Jai, so C's `void *` reads the same in Sabk.

1. `sizeof(void)` is 0, and a `void` field, parameter or element takes no space.
2. A void result can be left out of a `return`, a `let` and type matching. So `-> (void, IoError)` and `-> IoError` are the same signature, just as `fn f()` and `fn f() -> void` already are. Using the void form for errors is optional.
3. `*void` keeps `rawptr`'s rules: any pointer converts to it, it converts back with `as`, and it can't be dereferenced or indexed. Zig keeps the two apart, with `*anyopaque` as its untyped pointer; one spelling is simpler, at the cost of this one exception.
4. The C backend drops void fields, parameters and results, since standard C has no zero-size types.

Rename `rawptr` everywhere the reference uses it: the implicit-conversion and cast tables, `null`'s rule, the prelude's `AllocatorProc`, `Allocator` and `Any`, std/mem's signatures, and `TypeKind.Rawptr`.

**Before** (current design):

```
pub type AllocatorProc = fn(rawptr, AllocatorMode, usize, usize, rawptr, usize) -> rawptr;
extern fn memcpy(dst: rawptr, src: rawptr, n: usize) -> rawptr;

fn copy_file(from: string, to: string) -> IoError { ... }

let seen: Map(string, bool);                 // a set, paying for a bool per entry
map_put(&seen, "apple", true);
```

**After** (decided):

```
pub type AllocatorProc = fn(*void, AllocatorMode, usize, usize, *void, usize) -> *void;
extern fn memcpy(dst: *void, src: *void, n: usize) -> *void;   // reads like C's void *

fn copy_file(from: string, to: string) -> (void, IoError) { ... }   // the same as -> IoError

let seen: Map(string, void);                 // a set: the values take no bytes
map_put(&seen, "apple", .{});                // .{} is void's only value

fn retry(times: i32, f: fn() -> ($T, IoError)) -> (T, IoError) {
    let result, err = f();
    for (i in 1..times) {
        if (err == .None) break;
        result, err = f();
    }
    return result, err;
}

let text = retry(3, load_text) or_return;    // T = string
retry(3, flush_cache) or_return;             // flush_cache returns IoError, so T = void
```

## Smaller issues

- **Optional braces.** The parentheses earn their place, since they keep `Vec2{...}` unambiguous in conditions. Make GCC's misleading-indentation warning an error, so a brace-less body can't hide a second statement, as in Apple's `goto fail`.
- **Slice literals in loops share one array.** A loop that runs `list_push(&pairs, []i32{i, i})` stores views of the same array, so every element ends up as the last pair. The escape check can't see into `list_push`, so this needs a prominent line in the reference, next to `clone_slice`.
- **No way to skip initialization.** Defaults everywhere are right, but a large buffer should be able to opt out, as `---` does in Jai and Odin.
- **`make_list(16)`** is legal because 16 isn't a type, so the type argument quietly drops out. It reads as a capacity only if you already know the signature.
- **Control flow in macro blocks.** Say what `return` and `or_return` do inside a block passed to a macro. Returning from the caller is the only answer that keeps `with_allocator(a) { ... }` usable.

**Before** (current design):

```
if (err != .None)
    log_error(err);
    return err;                          // runs every time: the indentation lies

for (i in 0..3) list_push(&pairs, []i64{i, i});    // three views of one array, all {2, 2}

let buf: [65536]u8;                      // zeroed on every call

with_allocator(arena) {
    let cfg = load_config(path) or_return;   // returns from where? the reference doesn't say
}
```

**After** (suggested):

```
if (err != .None)
    log_error(err);
    return err;                          // error: indented as the if's body, but outside it

for (i in 0..3) list_push(&pairs, clone_slice([]i64{i, i}));   // each pair its own copy

let buf: [65536]u8 = ---;                // left uninitialized on purpose

with_allocator(arena) {
    let cfg = load_config(path) or_return;   // returns from the function that wrote this block
}
```

## Doc inconsistencies

- `sizeof` and `new` are keywords "until the language has generics", but generics exist and already take types such as `*u8` as arguments.
- Type checking lists `==` for numbers, bools, enums and pointers, while Strings says it also compares strings.
- The expression grammar has no `switch` expression, and `cmp_expr` takes only `add_expr`, so `is` has no pattern operand.
- Lexical notes say `$` isn't used by the grammar, but generics use it.
- In Context, the scoped-assignment rule sits after the allocator mode table, under the text about running out of memory.

## Trade-offs I'd keep

These go against what Rust or Zig would do, and they still fit Sabk:

- **Mutable `let` and compile-time `const`.** Nothing marks a runtime local as fixed, which is C's default too. Revisit it after the bigger items.
- **Nullable pointers, with `Option` for values.** Zig's non-null `*T` and `?*T` work because Zig has no implicit zero values: every field is set or marked `undefined`. Sabk zero-initializes everything, and a zeroed pointer is null; Jai and Odin make the same trade. Keep nullable pointers, and make `Option` lighter to use, as shown below.
- **No overloading and no methods.** Generics with `#if` cover static dispatch, and prefixed names are the C way.
- **Ignoring results.** Any result can be dropped, failures included, unless the function says `#nodiscard` (section 3). (Oct 19: a dropped failure will be a warning by default, with levels from flags; see Sabk-language-plan.md, section 5.)
- **Wrapping arithmetic.** It's predictable and cheap, std/checked covers code that must catch overflow, and with a signed `isize` default it rarely bites.
- **Generics checked per instance.** There's no trait system to learn, as in Jai and Zig, and a `#run panic(...)` under `#if` gives a readable error for an unsupported type.

For `Option`: `?T` becomes sugar for `Option(T)`, `None` comes first so a new one is empty, and `or_else` accepts an `Option` or a pointer. `?*T` isn't needed, since a `*T` can already be null.

**Before** (current design):

```
enum Option($T) { Some(T), None }            // `let o: Option(i64);` starts as .Some(0)

let port: i64 = 8080;
if (find_port(cfg) is .Some(p)) port = p;    // find_port returns Option(i64)

let node = map_find(&nodes, key);            // a pointer, or null
if (node == null) node = &fallback;
```

**After** (suggested):

```
enum Option($T) { None, Some(T) }            // a new Option is .None

let port = find_port(cfg) or_else 8080;      // find_port returns ?i64, sugar for Option(i64)
let node = map_find(&nodes, key) or_else &fallback;   // null takes the fallback

if (find_port(cfg) is .Some(p)) use_port(p); // matching works as before
```
