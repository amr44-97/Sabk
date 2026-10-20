# Sabk projects

Oct 20, 2026 · @amr

Programs to write in Sabk, growing in size, to learn what the language
does well and where it hurts, and to write software that isn't a
compiler. Each project names the books or guides to work from, what it
exercises in Sabk, and what to watch for. The last section maps the open
questions in Sabk-decisions.md and Sabk-language-plan.md to the projects
likely to settle them.

## Checklist

- [ ] **1.** Advent of Code, days 1–15 of a past year
- [ ] **2.** Unix tools: `wc`, `head`, `uniq`, `grep`, `sort`, `tr`, `diff`
- [ ] **3.** *The Practice of Programming*: Markov chain, CSV, regex (then a Thompson NFA)
- [ ] **4.** Image formats: QOI, then PNG with your own inflate
- [ ] **5.** JSON: a parser, then any struct to and from JSON
- [ ] **6.** Allocators: arena, pool, free list, a debug allocator
- [ ] **7.** A ray tracer
- [ ] **8.** A game of your own design, with raylib
- [ ] **9.** A CHIP-8 emulator
- [ ] **10.** A shell
- [ ] **11.** A text editor
- [ ] **12.** An HTTP/1.1 file server
- [ ] **13.** A Redis clone
- [ ] **14.** A key-value storage engine
- [ ] **15.** A capstone: Git, a SQL database, a Game Boy emulator, or a 3D renderer

## How to work

- **The projects live outside the compiler repo**, in
  `../sabk-projects/<name>`, built with `../Sabk/sabk`. One script builds
  them all: after a language change, it's a second test suite made of
  real programs.
- **A friction log**, one file with dated entries: what you wrote, what
  you expected, what happened, the workaround. Each is tagged *bug*,
  *missing std*, *design* or *good*. The good ones say what not to break.
- **Write the obvious code first**, not code shaped around the gaps. The
  friction is the data.
- **Bugs are fixed right away**, with a test. **Missing std is added** when
  a project needs it. **Design changes wait** until the same friction
  shows up in a second project, and are decided between projects, so the
  language doesn't bend around one program.

## Phase 1: everyday code (small)

**1. Advent of Code**, any past year, days 1–15.

- Read: the puzzles (adventofcode.com).
- Exercises: `split`, `cut`, `parse_int`, `Map`, `[..]T`, grids. Quick
  feedback on how everyday code feels.
- Watch for: changing grid cells inside a loop (by-pointer loops,
  deferred), and `map_find` giving a pointer or `null` where a `?T` might
  be expected.

**2. Unix tools**: `wc`, `head`, `uniq`, `grep` (fixed strings), `sort`,
`tr`, then `diff` (longest common subsequence).

- Read: *Software Tools* (Kernighan & Plauger), which is this project.
- Exercises: `fn main() -> Error`, `or_return`, logged failures, `args()`.
- Watch for: std/io can't read stdin yet (only `read_file`), so streaming
  input comes in here.

## Phase 2: data, bytes and formats (small to medium)

**3. *The Practice of Programming*** (Kernighan & Pike): the Markov chain
generator (ch. 3), the CSV library (ch. 4), the regex matcher (ch. 9).

- The book writes the Markov program in C, C++, Java, Awk and Perl, so
  Sabk can be compared with each of them.
- Then grow the regex into a Thompson NFA: Russ Cox, *Regular Expression
  Matching Can Be Simple And Fast* (swtch.com/~rsc/regexp).

**4. Image formats**: a QOI encoder and decoder (the spec is one page,
qoiformat.org), then a PNG decoder with your own inflate.

- Read: RFC 1951 (DEFLATE), the PNG spec, and Mark Adler's `puff.c` (in
  zlib's `contrib/puff`), a readable inflate.
- Exercises: bit operations, slices of bytes, error enums for malformed
  files.
- Watch for: how often only-lossless conversions make you write `as`.
  Zig's explicitness was a reason to leave it, so log this honestly.

**5. JSON**: a parser into a tagged enum, then printing and loading any
struct through `type_info` and `#insert #run`.

- Read: RFC 8259; Nicolas Seriot's *Parsing JSON is a Minefield*, and his
  JSONTestSuite (github.com/nst/JSONTestSuite) to test against.
- Exercises: tagged enums, patterns, reflection.
- Watch for: this is where layer 1's notes (`port: i64 @json("port")`)
  earn their place.

**6. Allocators**: an arena, a pool, a free list, and a debug allocator
that wraps `context.allocator` and reports leaks and double frees.

- Read: Ginger Bill's *Memory Allocation Strategies* series
  (gingerbill.org).
- Exercises: the `Allocator` interface and the context. The debug
  allocator is on the design review's "not done" list, so it can go into
  std.
- Watch for: wanting `#caller_location` (where a leak came from) and Jai's
  `,,` (one call with another allocator).

## Phase 3: math, graphics, simulation (medium)

**7. A ray tracer**, written to a PPM file.

- Read: *Ray Tracing in One Weekend* (Peter Shirley, free at
  raytracing.github.io), or *The Ray Tracer Challenge* (Jamis Buck),
  which is test-driven and doesn't assume a language.
- Exercises: operator overloading on a `Vec3`, floats.
- Gaps: there's no std/math (start with `extern fn sqrt` and
  `link_library("m")`) and no std/random (a PCG generator,
  pcg-random.org). Rendering rows in parallel, later, is where threads get
  designed.

**8. A game of your own design, with raylib**: Game of Life or particles
first, then the game.

- Read: *Game Programming Patterns* (Robert Nystrom, free online); *The
  Nature of Code* (Daniel Shiffman) for motion and physics; raylib's
  cheatsheet.
- Exercises: binding a real C library with `extern fn`, structs passed by
  value to C, a frame loop that frees the temp allocator each frame.

**9. A CHIP-8 emulator**, and later (big) a Game Boy.

- Read: Tobias Langhoff's *Guide to making a CHIP-8 emulator*, Cowgod's
  technical reference, Timendus's chip8-test-suite; for the Game Boy, Pan
  Docs (gbdev.io/pandocs) and Blargg's test ROMs.
- Exercises: `switch` with ranges on opcodes, wrapping `u8`/`u16` math,
  bit fields by hand (Sabk has none). It draws through project 8's raylib
  bindings.

## Phase 4: the operating system (medium)

**10. A shell**: running commands, then pipes, redirection, `cd`, simple
job control.

- Read: Stephen Brennan's *Write a Shell in C* (brennan.io); *The Linux
  Programming Interface* (Michael Kerrisk), chapters 24–28 (processes and
  exec), 34 (job control) and 44 (pipes).
- Exercises: `fork`, `execvp`, `pipe` and `dup2` through `extern fn`;
  string views made into NUL-terminated `char**`.
- Watch for: C's `int` and `pid_t`, the deferred `c_int` question.

**11. A text editor**: the kilo tutorial, then a gap buffer or a piece
table instead of its rows, and undo.

- Read: *Build Your Own Text Editor* (viewsourcecode.org/snaptoken/kilo);
  Craig Finseth's *The Craft of Text Editing* (free online); Charles
  Crowley's paper *Data Structures for Text Sequences*.
- Exercises: `termios` (a C struct whose layout must match exactly),
  `ioctl` (variadic), escape sequences.
- Gap: std/str needs UTF-8 here, since the cursor moves by characters,
  not bytes.

## Phase 5: servers and storage (large)

**12. An HTTP/1.1 file server**: one connection at a time, then an event
loop with `poll` or `epoll`.

- Read: *Beej's Guide to Network Programming* (free); RFC 9112; for
  depth, Stevens's *UNIX Network Programming, vol. 1*.
- Exercises: sockets from C, an arena per request: the context's design in
  a program that runs for a long time. std/net starts here.

**13. A Redis clone**: hash tables that resize gradually, an AVL tree for
sorted sets, a timer heap for expiry, a thread pool.

- Read: *Build Your Own Redis with C/C++* (James Smith,
  build-your-own.org), written in C-style C++, so it translates directly.
- The hard part: each thread needs its own `Context`, the main design
  problem of std/thread.

**14. A key-value storage engine**: Bitcask first (a log and a hash
index), then an LSM tree or a B+tree.

- Read: the Bitcask paper (Sheehy & Smith, 2010); *Designing
  Data-Intensive Applications*, ch. 3 (Kleppmann); *Database Internals*
  (Alex Petrov); the CMU 15-445 lectures (Andy Pavlo, free); cstack's
  *Let's Build a Simple Database* for a SQLite-shaped version.
- Exercises: file formats with exact layouts (no `#align` or packed yet),
  checksums, crash safety; `#assert(sizeof(Header) == 16)` from layer 1.

## Phase 6: one capstone (large)

**15.** One of:

- **A Git** that reads and writes real repositories: *Write yourself a
  Git!* (wyag.thb.lt), *Building Git* (James Coglan). zlib through C,
  SHA-1 by hand.
- **A small SQL database** on top of project 14.
- **The Game Boy emulator** from project 9, up to a real cartridge.
- **A 3D software renderer**: *Computer Graphics from Scratch* (Gabriel
  Gambetta), Dmitry Sokolov's tinyrenderer.

## Which project is likely to settle which open question

| Open question | Projects |
|---|---|
| By-pointer loops | 1, 7, 9 |
| `null`, `?T` and `or_else` | 1, 5, 13 |
| Assigning to parameters | all: log each time you want to |
| Jai's `,,` | 6, 8, 12 |
| `c_int` and C types | 10, 11, 12 |
| UTF-8 | 2, 11 |
| Threads, and a `Context` per thread | 7, 13 |
| Layer 1 (notes, `#caller_location`, `#assert`) | 5, 6, 14 |
| Layer 3 (a `@test` runner) | the first project that wants tests |
| `#align`, packed structs | 4, 14 |
| `Error` keeping payloads | 4, 5, 14 |

Layer 1 gets built when project 5 or 6 asks for it, with a real program
to judge it against, rather than next in the plan's order.
