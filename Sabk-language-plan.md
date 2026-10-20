# Sabk language plan

Oct 19, 2026 · @amr

The language changes decided while self-hosting the compiler. They're
built in the new compiler (`../Sabk`), not in the C++ one, which only
gets fixes from now on. The new compiler is compiled by the C++ one until
it can compile itself, so its own source and std keep today's syntax until
then: the new parser accepts the new forms first, and std and the compiler
switch to them at the bootstrap.

## Checklist

- [x] **Formatting:** letter directives (`%s %q %w %x %X %b %o %e %f %c`), `%{}` before a letter, errors that teach (section 1)
- [x] **Modules:** `#import`, `#load`, and `#scope_export` / `#scope_module` / `#scope_file` instead of `pub` (section 2); `pub` and `import` are ordinary names now
- [ ] **Metaprogramming, layer 1:** `$` value parameters, `#assert`, `#where`, `#caller_location`, notes (`@name`), `#embed` (section 3)
- [ ] **Metaprogramming, layer 2:** `#code` values and syntax trees in std/compiler (section 3)
- [ ] **Metaprogramming, layer 3:** a build script that sees every declaration as it's checked (section 3)
- [ ] **Types as values:** `#insert` in struct and enum bodies, value parameters on structs (section 3)
- [x] **Tagged enums:** `!is`, checked variant access `x.Variant`, narrowing (section 4)
- [x] **Error enums:** `enum IoError: Error { ... }`; plain enums go back to being plain (section 5)
- [x] **Result defaults and taking results:** `-> (i64, ParseError = .None)`, results taken from the left, a call's first value in an expression (section 5)
- [x] **Logged failures:** std's I/O, path and process functions log why; `context.log_level` (section 5)
- [x] **Parse failures logged** as warnings (section 5)
- [ ] **`or_return .Replacement`** (section 5): deferred Oct 20, 2026 ("not solving a real problem" yet); the open points are in section 5
- [x] **`--strict` and `--werror`:** dropped failures and unchecked values as opt-in warnings (section 5)
- [ ] **Debug failure traces** through `or_return` (section 5)
- [ ] **Function overloading:** Jai's model, functions and operators (`operator +`, `#symmetric`) (section 7)
- [x] **Optional parentheses** in `if`/`while`/`for`/`switch` and declared results; a block without them (section 6)
- [x] **Smaller additions:** named variant construction, `for (x, i in xs)`, `let a, b: T;`, keywords as field names, null checks, wrapping into `?T` (section 6)

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

Nothing breaks: no Sabk format uses `%` followed by a letter today (the
ones that do are C `printf` formats, which `#format` doesn't check).
A `[]u8` still prints as numbers by default; `%s` is the explicit "as
text" where it's printed, as `as string` is elsewhere.

**Errors.** The format is known at compile time, so a mistake is
underlined in the string, explained, and fixed:

```
[error]: `%d` isn't a directive: Sabk's `%` prints a number as it is at [main.sabk:4:14]
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

**`#load "file.sabk";`** makes one module of several files, as in Jai:
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
// std/str.sabk
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
where it comes from: "`is_space` is private to std/str.sabk
(`#scope_file` at line 120)".

### Edge cases met building them (built Oct 20, 2026; to review)

1. **While code moved over, a file that wrote `pub` kept the rule from
   before** (what isn't `pub` is private), and a file without `pub` got
   the new one. Once std, the compiler and the tests had moved, the old
   rule went, and `pub` and `import` became ordinary names; written the
   old way, they get errors that show the new way ("Sabk has no `pub`:
   ...", "an import is written `#import "std/io";`").
2. **A `#load`-ed file is parsed as a file of its own** (for messages and
   `#line`, which name it), and its declarations, imports and `#load`s
   are spliced into the module's list in place of the `#load`, as
   `#insert` does. Their owner is the module, so C names and `--types`
   treat them as one module.
3. **Each file starts exported**: the module's declarations are walked
   in order, keeping a current region per file, so a `#scope_file`
   before a `#load` doesn't cover the loaded file, and one at the end of
   a loaded file doesn't leak back.
4. **`#scope_file` names live in their file's own scope**, looked up
   before the module's, so two files can each have their own `PI`; one
   that clashes with a name the module has for all its files is an error.
   A name a sibling file keeps to itself is "unknown", with a hint:
   "`circle.sabk` has one, but it's private to that file".
5. **Paths**: a `#load` and the imports in a loaded file are relative to
   the file they're written in, not to the module's main file.
6. **A file is either imported or loaded**, by one module, once; each
   way round is an error (`#load` of an imported module, an import of a
   loaded file), and the second report ("can't find module") is left out.
7. **`--resolve` dumps** name the loaded file a declaration is in, not
   the module's main file.

#### Moving the code over (Oct 20, 2026; to review)

8. **Every file with `pub` was reorganized the Jai way** (the user's
   choice, for std, the compiler and the tests alike): its leading
   comment and `#import`s, then what was `pub`, then one `#scope_file`
   and the rest. Each part keeps the original order; a section comment
   (`// ---- numbers`) is repeated in each part that has declarations
   from that section; a declaration keeps the comment right above it. A
   script did it, checking that no line was lost. Files without `pub`
   (programs, most tests) only got `#import`, so their lines didn't move.
9. **The compiler's own lookups by name** (`main`, the prelude's
   helpers like `default_context`) missed `#scope_file` names, which live
   in the file's scope: they go through `module_decl` now, so a program
   can put `fn main()` under `#scope_file` too.
10. **The script only saw declarations at column 0**: `pub` and `import`
    inside a top-level `#if` and inside an `#insert` string were fixed by
    hand. An `#import` or `#load` inside a top-level `#if`, or in code
    made by `#insert`, is an error: what a module is made of doesn't
    depend on a condition.
11. **The tests' goldens** changed in their line numbers (the
    reorganized libraries, std and the prelude), which a script checked
    by comparing them with the locations taken out; the rest were the
    messages that name `pub` or `import`.
12. **`make compare` was retired**: the archived C++ compiler can't parse
    `#import` or files without `pub`, so it can't follow the language
    any more.

## 3. Metaprogramming

Jai's kind, in layers that build on what Sabk has (`#run`, `#insert`,
`#expand` macros with `Code`, `type_info`, `#if`, build scripts).

### Layer 1

```
struct Matrix($rows: isize, $cols: isize) { cells: [rows * cols]f32; }   // value parameters
fn sum(xs: []$T) -> T #where(is_numeric(T)) { ... }
#assert(sizeof(Header) == 16, "Header is 16 bytes in the file format");
fn log(message: string, at: Location = #caller_location) { ... }
struct Config { port: i64 @json("port"); }
fn parses_numbers() @test { ... }
const PRELUDE = #embed("prelude.sabk");
```

- **`$` value parameters**, on functions and structs: an instance per constant value, as `$T` gives one per type.
- **`#assert(condition, message)`**, at the top level, in functions, and in instances.
- **`#where(condition)`** after a generic signature, checked at the call before an instance is made: "`sum` needs `is_numeric(T)`, but T is `string` here". It's the first half of Jai's `#modify` (accept or reject); `#modify` can also change T, which Sabk needs less, since an `i64` parameter already takes narrower integers. A block that changes T can come later if real code needs it.
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

fn to_json(out: *[..]u8, value: $T) {
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
// panic: assertion failed: total == expected (total is 41, expected is 42) at main.sabk:9:5

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

Sabk does it Jai's way: generic structs (`struct List($T)`), `$T: Type`,
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

## 5. Errors

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

### Failing: an error enum for the caller, the reason for the log

Revised Oct 19, 2026 (evening). Results (`E!T`, `!T`) are dropped: two
ways to fail were one too many. A function that can fail returns several
results, the failure last, as today. From Jai: the function that fails
**logs why**, so the caller gets a value it can act on, and the details
(the path, the line, the bad text) aren't lost.

```
enum ConfigError: Error { CantRead(IoError), NoEquals(line: isize), BadNumber(line: isize) }

fn load_config(path: string) -> (Config, ConfigError = .None) {
    let config: Config;
    let text = read_file(path) or_return .CantRead;   // read_file logged why
    defer free(text.ptr);
    ...
        if (!found) {
            log(.Error, "%:%: expected key = value, found '%'", path, i + 1, line);
            return config, .NoEquals(i + 1);
        }
    ...
    return config;                                    // the failure takes its default: None
}
```

- **Both types are written** in the signature; nothing is inferred. The
  failure is a `bool`, an error enum or `Error`. Use an error enum when
  the caller may want to tell the failures apart.
- **The reason goes to the log**: the function that fails calls
  `log(.Error, ...)`, std's functions included (`read_file` logs
  `error: can't read app.cfg: no such file`). Passing a failure on doesn't
  log again: one failure, one message.
- **A caller that expects a failure quiets it** for a block:
  `context.logger = silent_logger();` (Jai's `,,` would do it for one
  call, later).
- **A minimum level**: `context.log_level` (`.Debug` by default: all of
  them); the default logger skips messages below it. Set for a block like
  the logger.
- Converting to `Error` drops a payload (below), but the log line kept the
  details.

### Result defaults

As in Jai, a result can have a default, and `return` leaves out the
results at the end that have one:

```
fn parse_int(s: string) -> (i64, ParseError = .None) {
    if (s.len == 0) return 0, .Empty;
    ...
    return value;                       // the failure: its default
}

fn find_user(name: string) -> (*User = null, LookupError = .None) {
    if (!loaded) return null, .NotLoaded;   // a failure is written in full
    ...
}

fn main() -> Error = .None {            // may end without a return
    ...
}
```

- `return` gives values from the left; only results with defaults can be
  left out. Without defaults, every return gives every value, as today.
- **`or_return`** fills the function's other results with their defaults
  (zeros, or field defaults, where there's none), so a function says what
  it returns on failure (`-> (isize = -1, ...)`).
- **Falling off the end** is allowed when every result has a default.
  This replaces the special case for `-> Error`: write `-> Error = .None`.
- Nothing is implied: a failure's default is written, never assumed, so
  giving a function a failure doesn't silently turn its old `return x;`s
  into successes.

### Taking the results

As in Jai, results are taken from the left, and what isn't taken is
dropped, silently:

```
let n, used, err = parse_prefix(s);   // all three
let n, used = parse_prefix(s);        // the failure is dropped
let n = parse_prefix(s);              // just the number
let _, _, err = parse_prefix(s);      // `_` to reach a later one
total += parse_int(s);                // in an expression: its first value
parse_int(s);                         // a statement: all dropped
```

- A call with several results used in an expression (an operand, an
  argument, `let x =`) is its first value. Today that's an error.
- **`#nodiscard`** (Jai's `#must`) on a function makes dropping its
  failure an error, wherever it's dropped. `_` still counts as taking it.
- The failure was logged where it happened, so a dropped one still shows
  in the log, with where and when.

### Edge cases met building defaults and taking results (built Oct 19, 2026; to review)

1. **`return f();` can't be counted before it's checked**: a call may
   give several values. A written value is filled from defaults before
   checking (`return x;`, `return;`, `return a, b;`); a call is checked
   first, and when it gives one value the rest come from defaults then.

   ```
   fn passed_on(c: u8) -> (i64, ParseError = .None) {
       return square(c);              // square gives one value: + None
   }
   ```

2. **A default is copied, as written, for each place that uses it**
   (every `return` that leaves it out, and the function's end), and each
   copy is checked there; `or_return` uses the checked original. So a
   default is worked out where it's used, and it can use the parameters,
   with their values at that point:

   ```
   fn or_name(s: string) -> (string = s, bool = true) {
       if (s.len == 0) return "empty", false;
   }                                  // the end: s, true
   ```

3. **A wrong default is reported once**, at the default: the copies the
   returns take are marked as already failed.

   ```
   fn wrong_type() -> (i64, ParseError = 5) {   // one error here
       return 1;                                // and none here
   }
   ```

4. **`.None {` after results without parentheses** would read as a
   variant's fields (`.Let{ ... }`): the default is read like a condition
   without parentheses, so the `{` is the body's.

   ```
   fn digits(s: string) -> i64, ParseError = .None { ... }
   ```

5. **A void result left out of the type** takes its default with it, and
   a `return` that writes a void value for it drops that value first:

   ```
   fn run_twice(f: fn() -> ($T, IoError)) -> (T, IoError = .None) {
       ...
       return r;                      // T = void: r goes, the IoError is None
   }
   ```

6. **A call's first value in an expression**: the checker turns the call
   node, in place, into a `FirstValue` node holding a copy of the call
   (`._0` in C; offset 0 in the VM). `#run parse_int("3")` gives 3.
   Several values written out (`let x = 1, 2;`) are still an error, and
   so is `let u, v = divide(7, 2) + 1;` (one value for two names).

7. **`#nodiscard` counts partial takes as dropping**: `let n = f();`,
   `let a, b = three();`, `x, y = three();` and `f() + 1` are errors for a
   `#nodiscard` f; `_` still takes a value.

8. **`-> Error` without a default can't fall off its end any more** (the
   special case is gone); the error suggests `-> Error = .None`. A hint
   about defaults is given only for several results or a failure type
   (`-> i32` with `return;` gets none).

9. **The bootstrap**: std couldn't use `= .None` until the seed knew
   it, so the feature landed first, then the seed, then std.

### Edge cases met building logged failures (built Oct 20, 2026; to review)

1. **The bootstrap**, again: std is compiled with the seed's built-in
   prelude, so `context.log_level` went into the prelude and the seed
   first, and std used it after.
2. **The compiler silences std's logs** (`context.logger =
   silent_logger();` at the top of its `main`): it reports its own
   failures in its own words, and some of std's are normal for it
   (`path_real` on a path that isn't there yet).
3. **`IoError.Other` covers every errno without its own variant**, and its
   text, "input/output error", was wrong for most of them (`rmdir` on a
   full directory). The log uses C's `strerror` for it instead:
   `can't remove the directory x: Directory not empty`.
4. **A log line can hold something that changes every run** (a temp
   dir's random name): the test captures the lines
   (`capture_logger`) and prints them with the name taken out.
5. **`log` skips a message below `context.log_level` before formatting
   it**, so a skipped `.Debug` costs a comparison.
6. **The parse functions log at `.Warning`** (decided Oct 20, 2026), not
   `.Error`: `total += parse_int(s)` adding 0 shows in the log
   (`warning: "oops" isn't an integer`), and a fallback on purpose
   (`parse_int(arg) or_else 8080`) is quieted with
   `context.log_level = .Error`.

### Handling one

```
let text = read_file(path) or_return;             // pass it on (as an Error, if that's the result type)
let text = read_file(path) or_else "";            // a fallback
let text = read_file(path) or_return .CantRead;   // wrap it: the IoError goes inside CantRead
let text, err = read_file(path);                  // both
if err != .None { ... }

let config, err = load_config(path);
switch err {
case .None:
case .CantRead(.NotFound):  config = Config.{};   // no file: the defaults
default:                    exit(1);              // the log already said why
}
```

- `or_return .Variant` puts the failure inside the variant when the
  variant holds its type, and replaces it otherwise.
- **Deferred** (Oct 20, 2026): not solving a real problem yet. Open
  points for when it's picked up: `read_file(p) or_return .len` already
  means the value's `.len` (the replacement would need `(... or_return).len`
  for a field); whether `or_return .BadLine(i)` builds a variant from
  other values; and the error for a variant holding another type.

### Warnings: `--strict` and `--werror`

The default is Jai's: no warning for a dropped failure. For the strict:

- **`--strict`** adds two warnings:
  - a dropped failure, showing the handling (`let text, err = ...`,
    `or_return`, `_ =`);
  - a value used where its failure was never checked:
    `let n, err = parse_int(s); total += n;` with `err` unread.
- **`--werror`** makes the build fail when there are warnings.
- A build script sets them with `set_strict(true)` and `set_werror(true)`;
  either one turns them on. Flags change diagnostics, never meaning, and
  apply to the program's own modules.
- Not decided: in debug builds, a dropped failure that isn't `None`
  logging `debug: dropped ParseError.Invalid at main.sabk:12`.

#### Edge cases met building them (built Oct 20, 2026; to review)

1. **Build scripts run at the end of checking**, so a script's
   `set_strict(true)` comes after the code is checked. The strict
   warnings are a pass after checking: dropped failures are noted while
   checking (Checker.dropped_failures) and given after, with the "used
   before its failure is looked at" pass (src/strict.sabk). Both kinds
   are sorted by module and place, so they read in the source's order.
2. **`--werror` doesn't turn each warning into an error.** The warnings
   are printed as warnings while checking, before a script's
   `set_werror(true)` is known, so the build fails at the end with one
   line: `[error]: 1 warning, and the build script's set_werror(true)
   makes warnings errors` (or `--werror`).
3. **Only error enums and `Error` count as failures**, not a `bool`:
   `let key, value = cut(line, "=");` is fine.
4. **"Used before it's looked at" goes by the order of the source**, not
   by every path: `err` read anywhere before `x` counts, even on another
   branch. Assigning to `err` makes it a failure to look at again:

   ```
   let z, err3 = parse_int("8");
   err3 = .None;                 // written, not read
   total += z;                   // warns
   ```

5. **"The program's own code" is by path**: a module under the std
   directory, or the prelude, is skipped. So std isn't shown to be clean,
   only left out.
6. **The compiler's own source had five**, all fair: four cleanups that
   drop failures on purpose (now `_ = delete_file(...)`) and one value
   used before its failure was read (now read first). It's clean under
   `--strict --werror`.
7. **The flags add up**: the command line or a script turns them on;
   there's no `--no-strict` (yet).
8. **The bootstrap**, again: the VM's build functions went into the seed
   before std/build used them.

### Stacking, and what `Error` keeps

Errors stack by wrapping, not by deeper inheritance: a variant holds the
cause (`CantRead(IoError)` above), and `or_return .CantRead` puts it
there. `%w` prints the whole stack:
`AppError.Config(ConfigError.BadLine(line = 12))`.

Converting to `Error` is lossy: an `Error` is one 64-bit number (32 bits
for the enum, 32 for the variant), so a payload has no room and is
dropped:

```
fn start() -> Error = .None {
    let cfg = load_config("app.cfg") or_return;   // ConfigError.BadLine(12) becomes an Error
}
// error: ConfigError.BadLine                      (the 12 is gone; `is ConfigError(e)` still works)
```

Ways to keep the details: the log line written where it failed; an
app-level error enum wraps its causes
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
  from IoError.NotFound at config.sabk:12:30, in load_config
  passed on at main.sabk:5:21, in main
```

## 6. Smaller additions

From writing the compiler in Sabk:

- **Named variant construction**: `.Let{ .declared = t, .uninit = true }`, the rest defaulted, in struct-literal syntax (today a variant is built positionally: `.Let(null, null, false, false, false)`).
- **`for (x, i in xs)`**: the element and its index.
- **`let a, b, c: *Node;`**: several names of one type, zeroed (today names declared together can't have types).
- **Keywords as field names**, after `.`, in field lists and in `.name =`: a compiler wants `type`, `else` and `default`.
- **Null checks** in checked builds: `file:line: panic: null pointer`, under the same setting as bounds checks (today it's a bare segfault, exit 139).
- **A message fix**: `K.Let{ ... }` suggests `K.Let.{ ... }`, which then fails with "`Let` is not a struct type".

### Optional parentheses

Decided Oct 19, 2026. The parentheses around a condition become
optional; without them, the body must be a block, so the condition can't
run into it (`if done -count;`):

```
if err != .None { return config, .CantRead(err); }   // no parentheses: a block
if (err != .None) return config, .CantRead(err);     // parentheses: any statement, as today
while i < n { i += 1; }
for x, i in xs { ... }
switch key { case "port": ... }
fn parse_int(s: string) -> i64, ParseError = .None { ... }   // results, in a declaration
```

- For `if`, `while`, `for` and `switch`, and for a declaration's results
  (its `{` ends them). A function type keeps its parentheses:
  `fn(i64) -> (i64, bool)`, since a comma there could start the next
  parameter.
- A condition that starts with `(` but goes on (`if (a + b) * 2 > c`)
  needs the block.
- Sabk's syntax makes this safe where C's wouldn't be: literals start with
  `.{` or `T.{` (Rust's `if x == S { }` problem can't happen), and
  dereferencing is postfix `p.*` (C's `if (p) *q = 1;` can't be misread).
- Existing code stays valid. Calls, `sizeof(T)` and the like keep their
  parentheses.

#### Edge cases met while building it (built Oct 19, 2026; to review)

1. **A `(` that only starts the condition.** The parser looks past the
   matching `)`: if an operator, `.`, `[`, `as`, `is`, `!is` or
   `or_return` follows, the condition goes on and takes a block.

   ```
   if (a + b) * 2 > c { ... }      // one condition, no parentheses: a block
   if (a > b) println("no");       // the `(` is the whole condition: any statement
   if (s) is .Dot { ... }          // goes on: `is`
   ```

2. **A body that starts with `(`.** A `(` right after the `)` starts the
   body, never a call of what's in parentheses. Found in the compiler's
   own code (src/vm.sabk) when it compiled itself; the tests had passed.

   ```
   if (k == .F32) (p as *f32).* = v as f32;   // the body is `(p as *f32).* = ...`
   if (get_handler) (x);                       // also a body, not a call of `get_handler`
   ```

3. **A `{` after a name, in a condition without parentheses, is the
   body's** (Rust's rule). Three places would otherwise read it as part
   of the condition:

   ```
   if x { ... }                  // C's literal `x{ ... }`: an error with a hint before
   if s !is .Circle { ... }      // the field pattern `.Circle{ r }`
   if v == K.Let { ... }         // the variant literal `K.Let{ .declared = t }`
   ```

   Inside parentheses, call arguments and blocks, literals work as usual:

   ```
   if at_origin(Point.{ .x = 0, .y = 0 }) { ... }
   if p.x == Point.{ .x = 1, .y = 5 }.x { ... }   // `T.{` is always a literal
   ```

   The same holds in a `for` header without parentheses (`for x in xs {`)
   and after `switch` (`switch s {`); the cases' own patterns
   (`case .Circle{r}:`) are inside the braces and unaffected.

4. **The error shows how the condition was read**, since that's what
   confuses:

   ```
   if done -count;
   [error]: `{` after the condition `done -count`: without parentheses, `if`'s body is a block

   for x in xs total += x;
   [error]: `{` after the loop header: without parentheses, `for`'s body is a block
   ```

5. **Left with their parentheses**: the `if` that gives a value
   (`if (c) a else b`: without them, `if c a else b` has no edge between
   `c` and `a`), `#if`, a `case` guard (`case .N(n) if (n > 0):`), and a
   function type's results (`fn(i64) -> (i64, bool)`).

6. **`do ... while`** takes either form: `while i > 0;` ends at the `;`.

## 7. Function overloading

Added Oct 19, 2026, at the user's request, and decided the same day:
Jai's model, for functions and for operators.

Several functions can share a name when their parameter lists differ, as
in Jai: `print_value(x: i64)`, `print_value(s: string)`,
`print_value(p: Point)`. A call picks the one its arguments fit:

```
fn area(c: Circle) -> f64 { ... }
fn area(r: Rect) -> f64 { ... }
fn area(shapes: []Shape) -> f64 { ... }

area(c);                     // the Circle one
area(.{ .w = 2, .h = 3 });   // error: `.{ }` fits both `Circle` and `Rect`; write the type
```

**The set.** Every function of that name in scope is a candidate: the
module's own, and those of its plain imports (`#import` without a name),
which is how std can add an overload of a user's function and the
reverse. A qualified call (`io.print`) only sees that module's. Macros
(`#expand`) and functions don't mix under one name.

**Picking one.** For each candidate whose parameter count fits (counting
defaults and a `..` parameter), each argument is ranked against its
parameter:
1. the same type;
2. an untyped constant that fits (`5` for an `i32`), or a literal that
   takes its type from the parameter (`.Red`, `.{...}`, `.[...]`);
3. an implicit conversion (`i32` to `i64`, `[N]T` to `[]T`, a value to
   `?T`, to `Any`);
4. a generic parameter (`$T`).
The best candidate is better or equal on every argument and better on at
least one. No best one is an error that lists the ones that fit equally,
with what each argument would become; none at all lists every candidate
and says which argument doesn't fit each. Rank 2 makes `f(5)` pick
`f(x: i64)` over `f(x: f64)` only by the default type of `5` (isize, then
i64): an untyped constant that fits several ranks them by its default
type first.

**Not overloaded:**
- the result type: two functions that differ only in what they return are
  an error at the second;
- a function used as a value: `let f = area;` with several `area`s is an
  error; `let f: fn(Circle) -> f64 = area;` picks one, as generic
  functions are picked today.

**In C** an overloaded function's name gets its parameter types, as
generic instances do: `area__Circle`, `area__Rect`, `area__slice__Shape`.

**With the rest of the plan:** `#where` (layer 1) removes a candidate
whose condition is false, so overloads can split on what a type can do;
`#caller_location` and notes work per function; error messages name the
candidate by its signature, not only its name.

Decided, as in Jai:
- **Across modules**: the candidates are the module's own and its plain
  imports' (above).
- **A concrete candidate beats a generic one** silently, by rank 4.

### Built, step 1 (Oct 20, 2026): within a module

Overloads in one module (and the files it `#load`s); across plain imports,
generic candidates and operators come next.

#### Edge cases met building it (to review)

1. **A set lives in a scope, never in a tree**: the resolver keeps
   functions of one name in an `Overloads` node, and the checker puts the
   one a call picks on the callee, so everything after (codegen, the VM)
   sees an ordinary function.
2. **The arguments are checked once, to rank the candidates**, and not
   again when the call is checked; `.{...}`, `.Red` and `.[...]` wait,
   and fit by shape: `.{...}` any struct or union, `.Red` a type with
   that variant, `.[...]` an array, slice or `[..]T`.
3. **An integer constant prefers `isize`, then `i64`**, then the other
   types it fits (ranks 2, 3, 4), so `f(5)` with `f(i32)`, `f(i64)` and
   `f(f64)` picks the `i64` one rather than being ambiguous.
4. **Visibility is by the call's own place**: its file's module sees its
   own candidates and others' exported ones (a generic instance's or a
   `#load`-ed file's code included).
5. **`..xs` only goes whole to a `..T` parameter, the last**; other extra
   arguments each go as a `T`.
6. **Two candidates with the same parameters are an error at the
   second**, checked before any call picks; one that differs only in its
   result says so.
7. **`extern` functions can't share a name** (C has one per name), and an
   `#expand` function can't either.
8. **A memory trap the compiler didn't catch**: the first version built
   the set as `.Overloads(.[prev, n])`, keeping a slice of a temporary
   array literal in a heap node; the names went missing and the compiler
   crashed. The escape check doesn't follow a value through a variant
   constructor into `new_node`. Worth a look for the trap warnings.
9. **Found on the way**: `println("%", 20.0)` printed `2e+01` (the
   shortest form that reads back); numbers of an ordinary size are now
   written out (fixed separately, 3fa281a).

### Built, step 2 (Oct 20, 2026): across plain imports

#### Edge cases met building it (to review)

1. **Your functions join the imports' instead of hiding them**: before,
   your `print()` hid std's `print`; now they're one set, and `print()`
   still calls yours since std's needs a format. Your types and
   constants still hide imported names, and a function in one import
   with a struct in another is still ambiguous where it's used.
2. **Yours hides an imported one with the same parameters** ("your names
   win" where it matters); two imports with the same parameters are
   ambiguous only at a call, with a hint to name the module.
3. **`extern` functions never join a set**: a test declared its own
   `extern fn printf` next to std/io's, and as a set C's `...` didn't fit;
   yours hides theirs, as before.
4. **The merged set is made once per module and name**, so every use of
   the name sees the same one.

### Operators

```
fn operator +(a: Vec2, b: Vec2) -> Vec2 { return .{ .x = a.x + b.x, .y = a.y + b.y }; }
fn operator *(v: Vec2, k: f64) -> Vec2 #symmetric { return .{ .x = v.x * k, .y = v.y * k }; }
fn operator [](m: *Matrix, i: isize) -> f64 { ... }
fn operator []=(m: *Matrix, i: isize, value: f64) { ... }

let c = a + b;
let d = 2.0 * c;              // #symmetric: (v: Vec2, k: f64) taken either way round
a += b;                       // from operator +
```

- **The operators**: `+ - * / % & | ^ << >> == !=`, and `[]` (reading)
  and `[]=` (writing). An operator is an overloaded function named
  `operator +`, picked the same way.
- **`+` gives `+=`**, and so on for the others.
- **`#symmetric`** on a two-parameter operator also accepts its arguments
  the other way round (`k * v`).
- **Not overloadable**: `=`, `&&`, `||`, `!`, `.`, `as`, `is`, `new`.
  At least one parameter must be a struct, enum or union: `+` on `i64`
  can't change.
- In C an operator is a function: `operator_add__Vec2__Vec2`.
- Advice (Jai's too): keep them for math. `v + w` that allocates or fails
  hides what `vec_add(v, w)` would show.

## 8. How it lands

1. **Port the checker** (done), matching the C++ on existing programs, but built for this plan: a job queue; instances keyed by constant values as well as types; `Option` and error enums as rules of the type system; flow facts for narrowing; notes kept on declarations and fields.
2. **Port the C backend and the VM** (done).
3. **Bootstrap** (done): the compiler compiles itself; std and the compiler move to the new syntax.
4. **Build the features**, each with tests, in about this order: formatting; error enums, logged failures, result defaults, taking results, `%w`, `--strict` and `--werror`; `!is`, checked access and narrowing; `#import`, `#load` and the scopes; function overloading and operators (section 7); optional parentheses; layer 1; layer 2; types as values; layer 3; the smaller additions. A feature can start as soon as the phase it needs exists in the new compiler.

## 9. Long term

- **Compile time** is fine for now and stays as it is. Later: better generated C, the choice of C compiler, or our own IR or x64 backend.
- **Inline assembly**: passed to the C compiler's `__asm__` (cheap, GCC syntax, per CPU), or Jai's `#asm` with the compiler choosing registers (needs our own backend). `#run` can't run either.
- **`Error` keeping payloads** (section 5).
- **A `#modify`-style block** that can change T, if `#where` isn't enough.
- **Functions that return a `Type`.**
- **`io :: #import "std/io"` and module parameters.**
- **`#import` inside a top-level `#if`** (today an error).

Still deferred, outside this plan (see Sabk-decisions.md and the review's
checklist): C types (`c_int`, ...), Jai's `,,` syntax, assigning to
parameters, by-pointer loops, writable `.len`/`.ptr`, UTF-8 and the
math, random and thread modules.
