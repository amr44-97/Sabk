# Smelt memory traps

Oct 17, 2026

Places where Smelt code compiles but reads memory that was reused, freed or
moved. Every example below was run against the compiler at commit
`a6793d5`; the output shown is what it printed. Each trap says what Smelt
does about it today and what's planned.

They come from three choices Smelt shares with C, Zig, Odin and Jai:
temporary memory lives on the stack, a slice or pointer is a bare view with
no lifetime in its type, and nothing follows a view into the functions it's
passed to. Go escapes this with a garbage collector, Rust with lifetimes in
the types.

| # | Trap | Today | Planned |
|---|------|-------|---------|
| 1 | A slice literal stored from a loop | warning | error (option 3, scopes) |
| 2 | A slice literal kept by a call in a loop | warning | error (option 3, calls) |
| 3 | A view of a block's array used after the block | warning | error (option 3, scopes) |
| 4 | A callee keeps the function's memory in the caller's | warning | error (option 3, calls) |
| 5 | An `Any` kept past its block | warning | error (option 3) |
| 6 | Heap memory freed while views of it remain | `--sanitize` | not planned |
| 7 | Memory moved by growing or removing | `--sanitize` | not planned |
| 8 | Copying a struct that owns memory | warning, `--sanitize` | not planned |
| 9 | Writing to a string literal | warning, crashes | error (section 6) |
| 10 | Writing through a view changes text others hold | compiles | error (section 6) |
| 11 | An array passed as a slice is shared, not copied | compiles (section 11) | by design |
| 12 | Growing a sequence while looping over it | warning, `--sanitize` | maybe a check (see Smelt-decisions.md) |
| 13 | Growing a by-value copy of a growable array | warning, `--sanitize` | error, if parameters become immutable (deferred) |
| 14 | Indexing past a pointer to one value | `--sanitize` | not planned (Jai and C allow it) |

Since 2026-10-19 the compiler warns about the traps a function's own code
shows (Checker::check_traps, tests/warnings/memory_traps.smelt), and
`--sanitize` builds with AddressSanitizer, with the temp allocator and
arenas poisoning what they take back; see docs/reference.md, Memory
traps. The outputs below are from before.

Already errors today, for comparison: returning `&local` or a slice of a
local array, returning a slice literal, storing either in a global or
through a pointer parameter (`out.* = .[7, 7]`), and taking the address
of a `for (x in ...)` loop variable.

## Lifetimes the compiler knows (option 3 covers these)

### 1. A slice literal stored from a loop

A slice literal has one hidden array per place it's written, and each
evaluation fills that same array. Every slice taken from it in a loop is a
view of the same memory.

```
let saved: [3][]i64;
for (i in 0..3) saved[i] = .[i, i];
println("% % %", saved[0], saved[1], saved[2]);
// [2, 2] [2, 2] [2, 2]
```

The memory is valid, so this is wrong values rather than a crash.
Avoid it: `clone_slice(.[i, i])` for a copy each time, or keep arrays,
which are values: `let saved: [3][2]i64;`.

### 2. A slice literal kept by a call in a loop

The same as 1, through a function that stores what it's given. It's the
common shape, since containers are where things get kept.

```
let pairs: [..][]i64;
for (i in 0..3) array_add(&pairs, .[i, i]);
println("%", pairs);
// [[2, 2], [2, 2], [2, 2]]
```

Map keys and values the same way: `map_put(&m, .[a, b], 1)` in a loop.
Avoid it: `clone_slice`, or keep arrays, which are values:
`[..][2]i64` with `array_add(&pairs, .[i, i])` stores a copy each time.
(That compiles since pointer indexing changed: `items.ptr[0..n]` is now `n`
arrays when the elements are arrays.)

### 3. A view of a block's array used after the block

A local array lives until the end of its block (in the generated C too), so
a view of it that's used after the `}` reads memory the next block reuses.
In a loop body, every pass ends the array's life.

```
let s: []i64;
{ let a = i64.[1, 2]; s = a[..]; }
{ let b = i64.[8, 9]; }
println("%", s);
// [140732513300256, 2]

let pairs: [..][]i64;
for (i in 0..3) {
    let pair = i64.[i, i];
    array_add(&pairs, pair[..]);
}
println("%", pairs);
// [[94182847992880, 3], [94182847992880, 3], [94182847992880, 3]]
```

This one is undefined behaviour, not just wrong values. After section 11,
the loop is written `array_add(&pairs, pair)`, with no `[..]` to hint that
a view is taken (see 11).

### 4. A callee keeps the function's memory in the caller's

Storing a function's own memory through a pointer parameter is an error
today, but not when another function does the storing.

```
fn add(out: *[..][]i64) { array_add(out, .[7, 7]); }
fn junk() { let big: [64]i64; for (i in 0..64) big[i] = 99; }

let pairs: [..][]i64;
add(&pairs);
junk();
println("%", pairs.items);
// [[99, 0]]

fn add_direct(out: *[]i64) { out.* = .[7, 7]; }       // an error today
```

### 5. An `Any` kept past its block

A value converted to `Any` is a pointer to a copy that lives until the end
of the block the conversion is in. Keeping the `Any` longer keeps a pointer
to memory that's gone.

```
let saved: [..]Any;
for (i in 0..3) {
    let v: i64 = i * 10;
    array_add(&saved, v);
}
for (a in saved) print("% ", a);
// 140722025245152 140722025245152 140722025245152
```

## Lifetimes only the program knows (not planned)

These need the compiler to know who owns heap memory and when it's freed,
which means ownership in the types (Rust) or a garbage collector (Go). The
standard library documents each one where it applies.

### 6. Heap memory freed while views of it remain

Strings and slices are views, so anything cut from a string dies with it.

```
// a view into memory freed by the defer
fn first_word(text: string) -> string {
    let copy = copy_string(text);
    defer free(copy.ptr);
    let word, _, _ = cut(copy, " ");
    return word;
}
println("%", first_word("hello world"));   // after another allocation
// XXXXX

// split's parts point into the line
let line = copy_string("a,b,c");
let parts = split(line, ",");
free(line.ptr);
println("%", parts);
// ["X", "X", "X"]

// the temp allocator, freed all at once
let s = tformat("x = %", 5);
free_all(context.temp_allocator);
let t = tformat("y = %", 77777);
println("%", s);
// y = 7

// an arena's memory, after the arena is destroyed
let kept: string;
{
    let arena = arena_init();
    defer arena_destroy(&arena);
    with_allocator(arena_allocator(&arena)) { kept = copy_string("from the arena"); }
}
println("%", kept);
// (garbage)

// a builder's text after builder_free
let b = make_builder();
builder_append(&b, "hi");
let text = builder_string(&b);
builder_free(&b);
println("%", text);
// XX
```

Avoid it: copy what has to outlive its owner (`copy_string`,
`clone_slice`), and free in the same place that allocated, with `defer`.

### 7. Memory moved by growing or removing

Growing a `[..]T`, a Map or a Builder can move its memory, and removing from a
Map moves its last entry into the hole. Pointers and views taken before
then point at the old place.

```
let xs: [..]i64;
array_add(&xs, 1);
let first = &xs[0];
for (i in 0..100) array_add(&xs, i);   // may move the elements
first.* = 42;                          // writes the old memory, if they moved

let s = builder_string(&b);
builder_append(&b, more);              // s may now point at freed memory

let a = map_find(&m, "a");
map_remove(&m, "a");                   // the last entry moves into a's slot
println("%", a.*);
// 2   (b's value)
```

In these runs `first` and `s` happened to still work, because the memory
grew in place. They're undefined all the same.

Avoid it: keep an index, not a pointer (`xs[0]`), and take
`map_find`'s pointer again after changing the map.

### 8. Copying a struct that owns memory

A `[..]T`, Map or Builder holds a pointer to its elements. Copying it
copies the pointer, not the elements, so both copies own the same memory.

```
let xs: [..]i64;
array_add(&xs, 1);
let ys = xs;                            // the same elements, two owners
for (i in 0..100) array_add(&ys, i);    // ys moves; xs points at freed memory
array_free(&xs);
array_free(&ys);
// free(): double free detected in tcache 2
```

Avoid it: pass `*[..]T`, not `[..]T`, to anything that changes it, and
copy the elements (`array_of(xs)`) for a real copy.

## Kept by section 6: strings stay writable (Jai's choice)

Writing to a literal is documented in docs/reference.md (Strings). In
`#run` code it doesn't crash: the write goes through and stays.

### 9. Writing to a string literal

```
let s = "hello";
s[0] = 'J';
// segmentation fault (exit 139): literals are in read-only memory
```

### 10. Writing through a view changes text others hold

```
let parts = split(line, ",");
parts[0][0] = 'X';                     // also rewrites `line`
```

## Since section 11

### 11. An array passed as a slice is shared, not copied

Arrays are values, but an array variable where a slice is expected becomes
a view of itself, as in C and Jai. Writes through the slice change the
array.

```
fn zero(xs: []i64) { for (i in 0..xs.len) xs[i] = 0; }

let a: [3]i64 = .[1, 2, 3];
zero(a);                 // a is now [0, 0, 0]
let view: []i64 = a;     // a view of a
let b = a;               // a copy: changing b leaves a alone
```

This is the intended meaning; it's here because nothing at the call shows
it, where today `zero(&a)` or `zero(a[..])` does. It's also what makes
trap 3 easy to write.

## Found while comparing with Jai

### 12. Growing a sequence while looping over it

A `for` loop reads its sequence once (the generated C copies `xs` before
the first pass). If the body grows the array, the elements move and the
loop keeps reading the old, freed block.

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

A loop by pointer (`for (&e in xs)`, deferred) would make this worse:
writes through `e` would land in the freed block. Avoid it: collect what
to add in a second array and append after the loop.

### 13. Growing a by-value copy of a growable array

A `[..]T` passed by value is a copy of its fields. Adding to the copy can
move the elements and free the block the caller's array still points at.

```
fn add_one(xs: [..]i64) { array_add(&xs, 99); }   // meant xs: *[..]i64

let xs: [..]i64;
for (i in 0..8) array_add(&xs, i);     // full: capacity 8
let blocker: [..]i64;
array_add(&blocker, 1);                // so xs can't grow in place
add_one(xs);                           // grows the copy, frees the old block
let other: [..]i64;
for (i in 0..8) array_add(&other, 7);  // reuses the freed block
println("%", xs);
// [7, 7, 7, 7, 7, 7, 7, 7]
```

Immutable parameters (deferred) would make `&xs` on a parameter an error.
Avoid it: pass `*[..]T` to anything that changes the array.

### 14. Indexing past a pointer to one value

Any `*T` can be indexed, so a pointer to a single value can be read and
written past.

```
fn bump(count: *i64) { count[1] += 1; }   // meant count.* += 1
let a: i64 = 10;
let b: i64 = 20;
bump(&a);
println("% %", a, b);
// 10 21
```

C and Jai allow the same. Zig and Odin give "many values" its own pointer
type (`[*]T`, `[^]T`) so that indexing a `*T` is an error; Smelt chose
Jai's single pointer type.
