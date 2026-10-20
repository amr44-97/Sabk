# Sabk section 8: how to build it

Oct 20, 2026 · @amr

This is the working guide for the rest of section 8 of
Sabk-language-plan.md (C interop, and types as constants). The plan says
*what* and *why*. This file says *how*: which files and functions to
change, in what order, what to test, and how to check the work. It's
written so that each step can be done in one session, without
re-deriving anything.

Step 1 is done (commit 965c228): `const X = T;`, `$T: type`, and `==` on
types anywhere. Step 2 is done: C types in the prelude. Steps 3 to 7 are
below.

## Before you start

### Read first

1. Sabk-language-plan.md, section 8, all of it. It holds the decisions
   and the syntax. Don't change a decision; if the code makes one look
   wrong, stop and ask the user.
2. This file: the general rules, then the step you're on.
3. The step's open points (below), which the user decides. **Ask about
   them before writing code for that step.** Give your recommendation
   first, as the plan does.

### How the user works

- One step at a time. After each step: report what was built, what was
  checked, and anything surprising, then wait for the user before the
  next step.
- Follow Jai where the plan doesn't say otherwise. Keep things simple
  and explicit. Never propose `try`, a `?` operator, or hidden
  allocation.
- Error messages teach: they say what's wrong *and* show the fix in
  Sabk's own syntax (look at any `fail(p, ...)` or `error(c, ...)` in the
  compiler for the tone). Messages are lowercase and use backticks for
  code.
- Commit only when the user says so, on `main`. Match the existing
  commit messages (`git log -5`): a title line, then what changed, then
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` (or the
  attribution line your session gives).
- Keep the code like the code around it: the same comment density, the
  same short comments that say *why*, the same naming.

### The compiler in one page

The compiler is written in Sabk and compiles itself. `make` builds
`build/stage0` from `bootstrap/sabk.c` (the seed: the C the compiler
writes for itself), and stage0 builds `./sabk` from `src/`. The pipeline:

| Phase | File | What to look for |
|---|---|---|
| tokens | `src/token.sabk`, `src/lexer.sabk` | keywords (`Pair.{ "type", TokenKind.Type }`) |
| syntax | `src/parser.sabk`, `src/ast.sabk` | `fn_decl`, `const_decl`, `aggregate` (structs), `type_` (types), `at_directive(p, "name")`, the top-level declaration switch (`case .Fn: decl = fn_decl(p);`); node kinds are the `NodeKind` enum in ast.sabk |
| names | `src/resolve.sabk` | `resolve_program`, `collect_decl`, `declare_or_overload`, `lookup`, `resolve_type`, `names_type`, `expr_to_type`, `name_type_constants`, `resolve_stmt`, `resolve_expr` |
| types | `src/check.sabk`, `src/expressions.sabk`, `src/statements.sabk`, `src/generics.sabk`, `src/types.sabk` | `decl_type`, `check_signature`, `type_from_node`, `layout`, `coerce`, `value_of_decl`, `can_cast`, `check_stmt`; `struct Type` and `fn_type` in types.sabk |
| compile time | `src/lower.sabk`, `src/vm.sabk`, `src/vm_ffi.c` | the VM that runs `#run`: `vm_dlsym`, `host_function`, `call_native`, `building()` (the build options) |
| C output | `src/codegen.sabk` | `c_type`, `define_type`, `fn_signature`, `emit_fn_prototype`, `is_extern_decl`, the call code (`let is_extern = fun != null && is_extern_decl(fun);`) |
| driver | `src/main.sabk` | `compile_c`: the C compiler's command line |
| prelude | `src/prelude.sabk`, `src/module.sabk` | names every program has; `prelude_text` fills in `@OS@` and `@ARCH@` while the compiler is built |

Line numbers drift, so find things with `grep -n`. The reference is
`docs/reference.md`; README.md's "What it has" lists the features.

Today, `extern` does everything C: in the parser, `Fn` and `Let` nodes
carry `is_extern`; an `extern fn` without a body is a C function, and
with a body it's callable from C. Everything that differs for C (no
context parameter, the C name, the VM finding the symbol) keys off
`is_extern`. The steps below reuse that flag rather than adding a
parallel one: `#foreign` and `#c_call` both set `is_extern = true`, and
step 4 removes the keyword.

### Checking your work (every step, before reporting)

Run all of these, and report each result:

```
make                    # builds ./sabk
make test               # golden tests: tests/run.sh
make unit               # i128 unit tests
make bootstrap          # ./sabk builds itself twice: the same C
```

Then the two AddressSanitizer passes. `tests/run.sh` always uses
`./sabk`, so make a copy that takes the compiler and the run flags from
the environment (in your scratchpad, not the repo):

```
sed -e 's|\./sabk --run|$SABK --run $RUNFLAGS|; s|\./sabk |$SABK |g' \
    -e 's|^cd "$(dirname "$0")/.." \|\| exit 1|cd /home/amr/user-space-code/projects/Sabk \|\| exit 1|' \
    tests/run.sh > $SCRATCH/run_env.sh && chmod +x $SCRATCH/run_env.sh

SABK=./sabk RUNFLAGS=--sanitize $SCRATCH/run_env.sh run/     # programs built with ASan
./sabk --sanitize --std std src/main.sabk -o build/sabk_asan
SABK=build/sabk_asan $SCRATCH/run_env.sh                      # the compiler built with ASan
```

Then probe the feature with small programs of your own, in the
scratchpad: the happy path, and also generics, imports (plain and `as`),
macros, `#scope_file`, top-level `#if`, `#run`, and wrong programs. Run
the wrong ones through `build/sabk_asan` too. These passes have found
real bugs that `make test` missed.

Last, refresh the seed and check the fixed point again:

```
make seed && make && make bootstrap    # must end with "and the seed is up to date"
```

### When a step changes syntax the compiler itself uses

The seed builds stage0, and stage0 compiles `src/` and `std/`. So std
and the compiler can only use new syntax once the seed understands it.
Do it in two rounds:

1. Make the compiler accept **both** the old and the new form. Build,
   test, then `make seed`.
2. Move `src/`, `std/`, the prelude and `tests/` to the new form, and make
   the old form an error that shows the new one. Build, test, `make
   seed` again.

Step 1 did exactly this for `Type` → `type` (see its commit).

### Tests

- `tests/run/x.sabk`: compiled and run; `x.expected` is its output and
  exit code. Helper modules go in `tests/run/lib/`.
- `tests/errors/x.sabk`: must fail; `x.expected` is the messages. A
  syntax error stops the compiler, so each parse error needs its own
  file (`parse_*.sabk`); errors from later phases can share one file.
- `tests/parser`, `tests/resolve`, `tests/types`: dumps.
- Write the test, run `tests/run.sh --update <name>` to record it, then
  **read the .expected file** to make sure it's right. When a change
  alters existing outputs, look at each diff (`tests/run.sh <name>`)
  before accepting it with `--update`.

### When a step is done

1. Docs: docs/reference.md where the feature belongs, the grammar at
   the top of "Declarations" if syntax changed, and README.md's "What it
   has" if users would care.
2. The plan: tick the checklist item at the top of
   Sabk-language-plan.md (or say what's left), and add
   `### Built, step N (date): ...` with `#### Edge cases met building it
   (to review)` at the end of section 8, numbered, as step 1 has. Write
   down every decision you had to make that the plan didn't cover.
3. All the checks above, then report to the user.

## Step 2: C types in the prelude

**Goal:** `int`, `long`, `char`, `size_t` and the rest are names every
program has, as aliases of Sabk's types (plan section 8, "C types", has
the table).

**Open points to ask about first:** none. One change from the plan's
wording to mention when reporting: the plan says the per-target types
are "chosen by `#if`", but a top-level `#if` in the prelude isn't
decided (the prelude isn't in `r.modules`, which `resolve_program`'s
`#if` loop walks). The prelude already gets its target another way:
`prelude_text()` in `src/module.sabk` replaces `@OS@` and `@ARCH@` while
the compiler is built. Do the same for `long`. Update the plan's bullet to say so.

**Changes:**

1. `src/prelude.sabk`, after the target section (`const POINTER_SIZE =
   ...`), add a section in the prelude's style:

   ```
   // ---- C's types, for C interop: aliases of Sabk's own, which std and
   // Sabk code keep using. long is the one that differs by target.
   const char = u8;      const uchar = u8;     const schar = i8;
   const short = i16;    const ushort = u16;
   const int = i32;      const uint = u32;
   const long = @C_LONG@;   const ulong = @C_ULONG@;
   const longlong = i64; const ulonglong = u64;
   const float = f32;    const double = f64;
   const size_t = usize; const ssize_t = isize;
   const ptrdiff_t = isize; const intptr_t = isize; const uintptr_t = usize;
   ```

   (One declaration per line if that's how the prelude is written.)
2. `src/module.sabk`, `prelude_text()`: also replace `@C_LONG@` and
   `@C_ULONG@`: `i32`/`u32` when `OS == .Windows` or `POINTER_SIZE == 4`,
   else `i64`/`u64`. Put that rule in one small function (say
   `c_long_bits() -> isize`, 32 or 64) so the C check below uses it too.
3. `src/codegen.sabk`: right after `append_string(&source, C_PRELUDE);`,
   append C checks that the C compiler agrees, one per type whose size
   could differ:

   ```
   _Static_assert(sizeof(int) == 4, "Sabk's int is i32, but this C compiler's int isn't 4 bytes");
   ```

   for `short` (2), `int` (4), `long` (from `c_long_bits()`), `long long`
   (8), `float` (4), `double` (8), `size_t` (pointer size). Always emit
   them: it's simpler than tracking which the program uses, and costs
   nothing. Say in the plan that this replaced "each C type the program
   uses".

**Pitfalls:**

- The compiler has locals called `double` (src/formats.sabk) and `float`
  (src/lexer.sabk), and a test has `fn double(...)`
  (tests/errors/run_local.sabk). Locals and a module's own names win over
  the prelude's, so these should keep working. Check that they do (the
  bootstrap compiles both files), and add a run test where a program
  declares its own `int`.
- `char` etc. are identifiers, not keywords: don't add them to the lexer.
- Aliases print as their type: an error about a `long` says `i64`.
  That's expected; mention it in the edge cases.

**Tests:** `tests/run/c_types.sabk`: the sizes (`sizeof(long)`, ...);
mixing (`let a: int = 5; let b: i32 = a;`); a C call with C types
(`fn abs(x: int) -> int` declared the current way, `extern fn`); a
program's own `float` shadowing the prelude's. `tests/errors/c_types.sabk`:
`let n: int = xs.len;` (the narrowing error), to show what users will
see.

**Docs:** reference.md, the "C interop details" list (search for it),
with the table; README "What it has", the C interop bullet.

## Step 3: `#library`, `#system_library` and `#foreign`

**Goal:** the syntax in plan section 8, "Libraries and foreign
declarations": a library is a constant, `#foreign lib ["c_name"]` after
a signature or a top-level `let`, linking follows use, and `#run` opens
the library.

**Decided Oct 20, 2026** (these replace the open points below where they
differ): Jai's spelling, `#library "vendor/libraylib"` and
`#system_library "libm"` (the file's name with its prefix, no
extension); `,link_always` now (`#system_library,link_always "libGL"`:
linked even if nothing uses it); `#foreign` with no library for the
program's own C; and no rule for one C name declared twice: every foreign
declaration gets its own C name, bound to the symbol with a GNU asm label
(`__asm__("strlen")`, `"_strlen"` on macOS). A shared library gets no
rpath (as in Jai); `sabk --run` sets `LD_LIBRARY_PATH` for it; and std/build
gets `add_library_dir(dir)`: `-L<dir>` when linking, and `LD_LIBRARY_PATH`
for `--run` (build steps run after checking, so compile-time `#run` code
doesn't search it). Done before step 3: the built-in types and C's names
are reserved (`reserved_type` in resolve.sabk).

**Open points as first asked** (recommendations in brackets):

1. Finding a library: `#library "vendor/raylib"` looks for
   `vendor/libraylib.a`, then `vendor/libraylib.so` (`.dylib` on macOS),
   relative to the file; the program links the static one if there is
   one, `#run` opens the shared one; a path with an extension names the
   file exactly. [Recommended, as in the plan.]
2. A function from the program's own C (a file added with `add_c_file`,
   or the runtime: `sabk_arg` in std/os, `vmffi_*` in the compiler) has
   no library. [Recommend `#foreign` with no library for these:
   `fn sabk_arg(i: isize) -> *u8 #foreign;`, "linked another way".]
3. The same C name declared twice (two modules, or two Sabk names):
   [one function if the signatures match, an error if they don't].

**Changes:**

1. AST (`src/ast.sabk`): a declaration kind `Library(path: Token, system:
   bool)`. On `Fn` and `Let`, add defaulted fields at the end:
   `foreign: *Node = null` (the library's name, an `Identifier` node, or
   null) and `link_name: string = ""` (the C name; empty means the Sabk
   name). Update the `--ast` dump (`old_shape` in ast.sabk) so the parser
   tests show them.
2. Parser:
   - `const_decl`: if the value is `#library "..."` or `#system_library
     "..."`, return `new_node(name, .Library(path, system))`. These
     directives arrive as a `#` token then an identifier: see how
     `at_directive` is used.
   - `fn_decl`, in the directive loop (`#format`, `#nodiscard`, ...): a
     `#foreign` directive with an optional library name and an optional
     string. It sets `is_extern = true` (that's what gives the C calling
     convention today), and the function must have no body (error: "a
     `#foreign` function is C's, so it has no body; for a function C
     calls, use `#c_call`" once step 4 exists, or a plain message for
     now). It allows `...` (variadic), as `extern` does: find the "only
     `extern` functions can be variadic" check and let `#foreign` pass
     it. The directive comes after the signature, so the variadic check
     has to happen after the directives are read.
   - A top-level `let name: T #foreign lib;`: `Let` with `is_extern =
     true`, no value allowed (as `extern let`).
3. Resolver:
   - `Library` is a top-level declaration: add it wherever `TypeAlias`
     is listed as a declaration kind (`ensure_resolved`, the
     `case .Fn, .Struct, .Enum, .TypeAlias, .Let, .Const:` lists).
   - Resolve `foreign` with `lookup`; it must be a `Library` declaration
     (error otherwise: "`x` isn't a library: declare one with `const x =
     #system_library "x";`"). Set its `decl`.
   - Overloading: `declare_or_overload` reports "`%` is an `extern`
     function, and C has one function per name" (around
     `is_extern_fn`). A `#foreign` function with a `link_name` may join an
     overload set: its C name is separate. Keep the error for plain
     `extern` and for `#foreign` without a link name, whose Sabk name is
     the C name.
4. Checker: `Library` declarations have no type; `decl_type` should give
   them `c.types.error` quietly, and using one as a value is an error
   ("`raylib` is a library: use it in `#foreign raylib`").
5. C output (`src/codegen.sabk`):
   - The C name: wherever a C function's or variable's name is written
     (`global_name` for extern declarations; `fn_signature`; the call
     code; `extern let` uses), use `link_name` when it isn't empty.
   - Linking from use: the codegen walks what's reachable (`find_reachable`,
     `g.reachable`). For each reachable `#foreign` declaration with a
     library, add the library to the build options once (they're
     `running_vm.c.build`, reached through `building()` in vm.sabk; the
     `libraries` list is `-l<name>`). A `#system_library "m"` becomes
     `-lm`. A `#library` file needs a new list on `BuildOptions` (say
     `library_files`), passed to the C compiler as a path in `compile_c`
     (src/main.sabk), plus `-Wl,-rpath,<its absolute directory>` for a
     shared one so the program finds it when it runs.
6. VM (`src/vm.sabk`, `src/vm_ffi.c`):
   - Add `vmffi_dlopen(path) -> *void` and `vmffi_dlsym_in(handle, name)
     -> *void` to vm_ffi.c (with `dlerror()` text for messages), declared
     like `vmffi_dlsym` in vm.sabk.
   - Where a native function's address is found (`f.address =
     vm_dlsym(f.name)`, and the `extern let` case in
     `vm_global_storage`): look the symbol up by its C name, in the
     declaration's library when it has one. Open each library once (a
     map from the library declaration to its handle). For a system
     library, `dlopen("lib<name>.so")`; if that fails, an error naming
     the library and dlerror's text. A static-only `#library` can't be
     opened: error "`#run` can't call `f`: library `vendor/raylib` is a
     static archive (libraylib.a), which only the program links".

**Tests:** `tests/run/foreign.sabk`: libc and libm functions through
`#foreign` (`strlen`, `sin` and `sinf` as two overloads of `sin`), a
renamed one (`fn string_length(s: *u8) -> size_t #foreign libc
"strlen";`), a C variable (`let environ: **char #foreign libc;`), a
`#run` call into libm. A `#library` test: put a small C file in
`tests/run/lib/`, and have a build step in the test compile it into a
`.a` or `.so` first (`run_command(.["cc", ...])` from std/process, at
the top of the build script; look at tests that use
`tests/run/lib/build_helper.c` for how C files are handled today).
Error tests: `#foreign` on a function with a body, a library name that
isn't a library, a library used as a value, an overload of a `#foreign`
function without a C name.

**Docs:** reference.md: a "C interop" section (or grow "C interop
details") with libraries, `#foreign`, linking, and what `#run` can call.
The build-scripts section's `link_library` stays, as the way for
everything else.

## Step 4: `#c_call` and C function types; `extern` goes

**Goal:** plan section 8, "`#c_call`": a function C calls, a C function
pointer type, calling through it without a context. Then std and the
compiler move off `extern`, and the keyword goes.

**Open points to ask about first:** none beyond step 3's, but confirm
the migration plan (two rounds, below) before starting.

**Changes:**

1. Parser:
   - `fn_decl` directive loop: `#c_call` sets `is_extern = true`
     (today's meaning of an `extern fn` with a body). It needs a body.
   - `type_`, the `case .Fn:` branch: after the result, accept
     `#c_call`; add `c_call: bool = false` to `TypeFn` in ast.sabk.
2. Types (`src/types.sabk`): add `is_c_call: bool` to `struct Type` (for
   `.Fn`), and a parameter to `fn_type` that's part of what makes two
   function types the same (the loop comparing `params`, `ret`,
   `is_variadic`). Printing a type (find where `.Fn` types get their
   name, `fn(...)`) adds ` #c_call`.
3. Checker:
   - `type_from_node`, the `.TypeFn` case: pass `c_call` to `fn_type`.
   - A C function's value: `value_of_decl` in src/expressions.sabk has
     `case .Fn{is_extern, is_macro}:` returning `c.types.rawptr` for an
     extern function. Make it return the function's own type marked
     `#c_call` instead (build it from the declaration's signature, with
     `is_c_call = true`).
   - `coerce` (expressions.sabk) has the error "% is an `extern`
     function, which uses the C calling convention, so it can't be used
     as a %". Keep it for converting a C function to a Sabk function
     type, reworded for `#foreign`/`#c_call`. A `#c_call` value converts
     to a `#c_call` function type of the same signature, and a Sabk one
     never converts to a `#c_call` type or back without `as`.
   - `can_cast` (src/generics.sabk): `*void` casts to and from any
     function type today; keep that (the plan: `as` is trusted). The one
     new error: casting a function the compiler can see is C's (a
     `#foreign` or `#c_call` declaration, by name) to a Sabk function
     type.
   - Code that passed an extern function where `*void` was expected
     (`qsort(..., compare)`) now gets a `#c_call` function type. Decide
     with the user whether a `#c_call` function still converts to `*void`
     implicitly (recommend yes: C APIs take `void *` callbacks), and add
     it to `coerce` if so.
4. C output:
   - `c_type`, `case .Fn:` writes `typedef ret (*fn__N)(Context*, ...)`.
     For `is_c_call`, leave out the context parameter.
   - The call code: `let is_extern = fun != null && is_extern_decl(fun);`
     decides whether the context is passed. Make it also true when the
     callee's type is `is_c_call` (a call through a pointer, `fun ==
     null`).
5. Lowering and the VM:
   - src/lower.sabk: `let c_call = fun != null && fun.kind is
     .Fn{is_extern: true};` likewise also true when the callee's type is
     `is_c_call`.
   - In the VM, a Sabk function value is a `*VmFunction` (see
     `(slot(frame, call.fn_slot) as **VmFunction).*` in vm.sabk), but a
     `#c_call` value is a C address: a C function's, or the libffi
     closure the VM makes for a `#c_call` function with a body (look for
     `closure_code`). A call through a `#c_call` type must call that
     address with libffi, the way `call_native` calls a native
     function's `address`. Find how a call site gets its `cif`, and build
     one for the function type.
6. Migration, in two rounds (see "When a step changes syntax"):
   1. With `extern` still accepted: build, test, `make seed`.
   2. Move every `extern` in `src/`, `std/`, `src/prelude.sabk` and the
      tests (`grep -n 'extern' src/*.sabk std/*.sabk tests/*/*.sabk`,
      about 94 declarations): `extern fn f(...);` becomes `fn f(...)
      #foreign libc;` (or `#foreign` with no library for the runtime's
      and the compiler's own C, if the user chose that in step 3);
      `extern fn f(...) { ... }` becomes `fn f(...) #c_call { ... }`;
      `extern let` becomes `let ... #foreign libc;`. Declare `const libc
      = #system_library "c";` once where it's needed (the prelude is the
      natural place, so every module has it; ask the user). Then make
      `extern` an error: "`extern` is gone: a C function is `fn f() #foreign
      libc;`, and a function C calls is `fn f() #c_call { ... }`". Keep
      `extern` a keyword for that message, or turn it into an ordinary
      name and catch it in the top-level declaration switch, as `pub`
      and `import` are (look at how the parser reports `pub`).
   3. Update every message in the compiler that says `extern` (`grep -n
      'extern' src/*.sabk`), and rename `is_extern` only if it stays
      readable; it can keep its name, with a comment that it means "C's
      calling convention".

**Tests:** `tests/run/c_call.sabk`: `qsort` with a `#c_call` comparator;
a `const Compare = fn(*void, *void) -> int #c_call;` field in a struct;
`dlsym(null, "puts") as fn(*char) -> int #c_call` called (link `dl`
if needed); a Sabk function passed through `*void` and cast back (the
round trip the plan keeps); the same calls under `#run`. Error tests: a
`#c_call` function assigned to a Sabk function type; a Sabk function
assigned to a `#c_call` type; `extern` (the new message).

**Docs:** reference.md: "Calling convention" and "Context" (both say
`extern` today: search for them), the grammar, the C interop section.
README's example and "What it has".

## Step 5: `#packed` and `#align`

**Goal:** `struct EpollEvent #packed { ... }` and `struct Vec4
#align(16) { ... }` (plan section 8, "Layout").

**Open points to ask about first:** `#align` on fields too, or only
structs [recommend structs only for now]; `#align` smaller than the
natural alignment [recommend an error: C can't lower it either].

**Changes:**

1. Parser, `aggregate`: between the name (and type parameters) and `{`,
   accept `#packed` and `#align(expr)` in any order. Add `packed: bool =
   false, align: *Node = null` to `Struct` in ast.sabk.
2. Resolver: resolve the `align` expression like any constant.
3. Checker, `layout` in src/check.sabk (the `case .Struct` loop that
   sets `f.offset = align_up(size, f.ty.align)`): for a packed struct,
   offsets don't round up and the struct's `align` is 1; for `#align(n)`,
   the struct's `align` is `n` and its size rounds up to it. `n` must be
   a constant power of two, at least the natural alignment. The
   declaration is `t.decl`. `check_struct` is where other struct errors
   are reported.
4. C output, `define_type` in src/codegen.sabk: write `}
   __attribute__((packed));` or `} __attribute__((aligned(N)));` (Sabk
   already needs GNU C). Also emit `_Static_assert(sizeof(struct X) ==
   <Sabk's size>, "...")` for these structs, so the C compiler confirms
   the layout Sabk computed.
5. The VM uses `t.size` and `f.offset`, so it follows on its own. Check
   with a `#run` test that reads a packed field.

**Tests:** run test: `sizeof` and field values of a packed struct (`u8`
then `u32`: size 5), an aligned one, both under `#run`, and the
`epoll_event` layout. Errors: `#align(3)`, `#align(1)` on a struct that
needs 8, `#align(x)` with a variable.

## Step 6: `is` on types

**Goal:** plan section 8, "Comparing types": `T is []$E`, `T is *$P`, `T
is Map($K, $V)`, `T is Map`, `T is enum` (also `struct`, `union`, `fn`),
with the bindings visible in that branch. After it, `T == Map` (any
instance) becomes an error that suggests `T is Map`.

**Open points to ask about first:** whether `T == Map` becomes an error
now or keeps working for a while [recommend an error with the hint: the
plan says `==` always means the same type]; whether `is` on types works
in a plain `if` as well as `#if` [recommend both, as `==`].

This is the largest step. Do it in two parts, each tested:

1. **No bindings:** `T is Map` (any instance) and `T is enum/struct/
   union/fn`.
   - Parser: `is` is parsed in conditions today with a pattern on its
     right (`x is .Number(n)`, `err is IoError(e)`). Find where `.Is` is
     built. Allow `struct`, `enum`, `union` and `fn` (keywords) as the
     pattern.
   - Resolver: in `resolve_expr`, when an `Is` node's left side
     `names_type` (as `resolve_type_compare` does for `==`), turn it
     into a new node kind, say `TypeIs(subject: *Node, pattern: *Node,
     kind: ...)`, resolving the pattern as a type with
     `r.any_instance_ok` set (see `resolve_type_compare` and
     `resolve_type_args`).
   - Checker: next to the `.TypeCompare` case in src/expressions.sabk
     (which uses `any_instance` and `of_template`), a `.TypeIs` case
     giving a constant bool.
   - Then make `T == Map` without its types an error: "`Map` without its
     types is any `Map`: write `T is Map`".
2. **With `$` bindings:** `T is []$E`.
   - The pattern is a type that contains `$E`: the parser's `type_`
     already reads `$E` as `TypeParam`.
   - Resolver: declare each `$E` in a new scope for the branch: for a
     plain `if`, the way `is` bindings are scoped (`resolve_test` pushes
     a scope); for `#if`, push one around the taken branch (the
     `.StaticIf` case in `resolve_stmt`).
   - Checker: match the subject type against the pattern structurally
     (pointer to pointer, slice to slice, a generic struct's arguments
     to the pattern's), binding each `$E` to the part it meets. Generic
     functions already bind `$T` from argument types; read how
     src/generics.sabk does it (`given: Map(*Node, *Type)`) and reuse
     that matcher if it fits.
   - In generic code, `T` is only known per instance: the comparison
     and its bindings are decided when the instance is checked, as
     `TypeCompare` is.

**Tests:** run tests for each shape, in `#if` and plain `if`, in
generic functions; the bindings used in the branch (`let e: E;`). Errors:
a binding used outside its branch; `T is 4`; `T == Map`.

## Step 7: layer 1 metaprogramming, `#assert` first

**Goal:** plan section 3, "Layer 1". Start with `#assert(condition,
"message")`, which C interop needs to check bindings' layouts
(`#assert(sizeof(Termios) == 60, "...")`). The other layer-1 features
(`$` value parameters, `#where`, `#caller_location`, notes, `#embed`) each
get a short discussion with the user first: the plan has their design,
but not their details.

**Open points to ask about first:** `#assert` with no message (recommend
allowed: the message is then the condition's text, as `assert` in
std/os does).

**Changes for `#assert`:**

1. AST: `StaticAssert(cond: *Node, message: *Node)`.
2. Parser: at the top level (the declaration switch) and as a statement
   (`stmt`): `#assert` `(` expr [ `,` string ] `)` `;`.
3. Resolver: `resolve_expr` on both parts. At the top level it's
   collected like a `#run` build step (it declares nothing: see how
   `.Run` gets `n.owner = m` in `collect_decls`).
4. Checker: the condition must be a constant `bool` (`cval`), as an
   `#if` condition must (find the message `#if` gives when the condition
   isn't known); if it's false, an error at the `#assert` with the
   message. Check top-level ones once everything is declared (where
   `check_program` walks the modules), and statement ones in
   `check_stmt`, which runs per generic instance, so `#assert(sizeof(T)
   <= 8)` in a generic function checks each instance.
5. C output and the VM: nothing (an `#assert` leaves no code). Make sure
   `emit_stmt` and lower's `stmt` ignore it (their `default:` does).

**Tests:** run test with passing ones (top level, in a function, in a
generic); error tests: a false one (with and without a message), a
condition not known while compiling, one that fails for one instance
only.

## Where things stand

| Step | What | State |
|---|---|---|
| 1 | `const` names types, `type`, `==` on types | done, 965c228 |
| 2 | C types in the prelude | done, 02fe18b; reserved names b48ab84 |
| 3 | `#library`, `#system_library`, `#foreign` | done, 47596a4 |
| 4 | `#c_call`, C function types; `extern` goes | done, 71adc59 |
| 5 | `#packed`, `#align` | done, 177aaed |
| 6 | `is` on types | done (uncommitted) |
| 7 | layer 1, `#assert` first | next |

Update this table as steps land.
