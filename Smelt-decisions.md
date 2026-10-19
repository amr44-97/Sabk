# Smelt decisions

Decisions taken while working through Smelt-design-review.md, and the ones
deliberately left for later. Newest at the bottom of each list.

## Decided

- **Pointers to arrays (option 3, Jai's model).** `p[i]` and `p[lo..hi]` on
  any `*T` mean the i-th `T`, including `*[N]T` (the i-th array). Indexing,
  slicing and `for` stop looking through `*[N]T`; `.len`, `p.x` and
  `&arr` as a `[]T` stay. Fixes `List([2]i64)` and generic `*T` code.
- **Dereference is postfix `.*`**, as in Jai and Zig: `p.*`, `p.*[i]`.
- **`.ptr` on fixed arrays.** `a.ptr` is `&a[0]`; needs a place (not a
  temporary, not a constant); the escape check treats it as `&a`.
- **Writable fields on growable arrays only.** `[..]T`'s `.ptr`, `.len`,
  `.cap` and `.allocator` can be assigned; slice and string fields stay
  read-only (slicing does that job, with a bounds check).
- **Turning bounds checks off.** A function directive
  (`#no_bounds_check`, like Jai's `#no_abc`) and a build option with
  Off / On / Always. Covers index and slice checks only, not division by
  zero. `#run` code in the VM keeps its checks.
- **Built-in growable arrays `[..]T`** replace `List(T)`: `{ptr, len, cap,
  allocator}`, functions in std, converts to `[]T` (a view of the heap, not
  of the frame). Initial values come from `array_of(.[1, 2, 3])` (or
  `array_of(items, allocator)`), a call that visibly allocates; a literal
  can't initialize a `[..]T` directly. Rejected: starting on the literal's
  storage, and letting the declaration allocate. Building an element in
  place (`array_add_new`) was left out at first, to keep it simple, and
  added 2026-10-19 with `array_find` and `array_remove_value`.
- **`---` skips zeroing**, for local variables only (not globals, not
  struct field defaults). The VM's rule (zeros or a fill pattern) is open.
- **Literal syntax, Jai's rule:** a dot takes the type from the context,
  a type before the dot names it.
  - `.[1, 2, 3]` for arrays and slices; `[` in an expression always starts
    a type.
  - `i64.[1, 2, 3]` names the element type; the count comes from the
    elements. `[2]i64.[...]` is an array of `[2]i64`. Element types that
    start with `*` or `fn` need parentheses: `(*Node).[a, b]`. No named
    slice literal: a slice takes its type from its context.
  - With no context, `.[...]` is typed by its elements (section 11's rule).
  - Fewer elements than the array holds is an error.
  - `Point{ ... }` becomes `Point.{ ... }`; field names keep the dot:
    `.{ .x = 1 }`.
- **Strings stay Jai's writable view (section 6).** No read-only `string`,
  and no owned or growable string type: an owned `string` would need
  ownership machinery (Rust's moves and destructors, or Swift's reference
  counting) to stop two copies owning one buffer, and Jai and Odin both
  do without one. Text is built in a `Builder`, now a `[..]u8` inside.
  Writing to a literal stays unchecked: the program crashes, `#run`
  keeps the write. Both are documented in docs/reference.md (Strings).
- **Bytes and text convert only with `as`, both ways, as in Jai**
  (2026-10-18): `b as string`, `s as []u8`, `"abc" as []u8`. Nothing
  converts on its own (`[]u8`, `[N]u8` and `*[N]u8` used to become
  `string`, and a literal a `[]u8`), and `==` doesn't mix bytes with
  text. Explicit for now, to avoid more traps; the errors show the cast.

## Deferred

- **By-pointer loops** (`for (&e in xs)`, `e: *T`). Too many traps to
  settle now:
  - Growing a sequence inside its own loop: the loop reads the sequence
    once, so it keeps reading the old block. This already happens with
    the by-value form (`list_push(&xs, ...)` inside `for (x in
    xs.items)` printed `0 -1 -1 ...`). A possible check: refuse `&xs`, or
    `&` of anything containing it, inside a loop over `xs`.
  - Indexing a loop pointer: over an array of arrays, `e[j]` is the j-th
    row after `e`, unchecked. A possible check: indexing a loop pointer
    is an error (`e.*[j]`).
  - Pointers that outlive the loop or the sequence (traps 3 and 7).
  - What can be looped by pointer: assignable elements only (not
    constants, temporaries, ranges, or read-only strings).
- **Assigning to parameters.** Options: (a) C, every parameter a mutable
  copy (today); (b) Odin, all immutable, big ones passed by pointer;
  (c) Jai, immutable above 8 bytes; (d) all immutable, always copies.
  b and c pass by reference behind your back, which aliases (Zig issue
  #5973) and, for c, makes assignability depend on a generic `T`'s size.
  Recommended: d, which also catches pushing onto a by-value copy of a
  growable array; needs `let x = x;` shadowing of a parameter, which Smelt
  refuses today.
