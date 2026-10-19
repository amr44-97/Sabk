#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

typedef int8_t i8;
typedef int16_t i16;
typedef int32_t i32;
typedef int64_t i64;
typedef ptrdiff_t isize;
typedef uint8_t u8;
typedef uint16_t u16;
typedef uint32_t u32;
typedef uint64_t u64;
typedef size_t usize;
typedef float f32;
typedef double f64;
typedef void *rawptr;
/* void as a value (a variable, field or parameter): no bytes, as GNU C
   gives an empty struct; C's own void only spells a function's result */
typedef struct {} smelt_void;

/* runtime: the libc functions it needs, spelled the way our code declares
   them (`extern fn memset(p: *void, value: i32, n: usize) -> *void;`),
   since every declaration of a function in one C file must agree */
rawptr memset(rawptr, i32, usize);
_Noreturn void abort(void);
i32 dprintf(i32, u8 *, ...);
i32 fflush(rawptr);

/* the program's arguments, for std/os's args() */
static int rt_argc;
static char **rt_argv;
i32 smelt_arg_count(void) { return rt_argc; }
u8 *smelt_arg(i32 i) { return (u8 *)rt_argv[i]; }

/* errno, for std/io's errors; without <errno.h>, whose names (errno,
   ENOENT, ...) would take names from the program */
#if defined(__APPLE__)
int *__error(void);
i32 smelt_errno(void) { return *__error(); }
#else
int *__errno_location(void);
i32 smelt_errno(void) { return *__errno_location(); }
#endif

/* AddressSanitizer, when the program is built with it (--sanitize): what
   the temp allocator and arenas take back is poisoned, so using it is
   reported as a use of freed memory is. Leaks aren't reported unless
   ASAN_OPTIONS=detect_leaks=1: a program may leave its memory to the OS. */
#if defined(__SANITIZE_ADDRESS__)
#define RT_ASAN 1
#elif defined(__has_feature)
#if __has_feature(address_sanitizer)
#define RT_ASAN 1
#endif
#endif
#ifdef RT_ASAN
void __asan_poison_memory_region(void const volatile *, usize);
void __asan_unpoison_memory_region(void const volatile *, usize);
const char *__asan_default_options(void) { return "detect_leaks=0"; }
void smelt_poison(rawptr p, isize n) { __asan_poison_memory_region(p, (usize)n); }
void smelt_unpoison(rawptr p, isize n) { __asan_unpoison_memory_region(p, (usize)n); }
#else
void smelt_poison(rawptr p, isize n) { (void)p; (void)n; }
void smelt_unpoison(rawptr p, isize n) { (void)p; (void)n; }
#endif

/* two strings' contents */
static inline bool rt_bytes_equal(const u8 *a, isize a_len, const u8 *b,
                                  isize b_len) {
  if (a_len != b_len)
    return 0;
  for (isize i = 0; i < a_len; i++)
    if (a[i] != b[i])
      return 0;
  return 1;
}

/* a failure enum's value as an Error: which enum (id), and which variant;
   each enum's 0 is Error's 0 */
static inline u64 rt_error(u64 id, u64 v) { return v ? id << 32 | (u32)v : 0; }

static inline _Noreturn void rt_panic(const char *where, const char *msg) {
  fflush(NULL); /* keep what the program printed before dying */
  dprintf(2, (u8 *)"%s: panic: %s\n", where, msg);
  abort();
}

static inline isize rt_index(isize i, isize len, const char *where) {
  if ((usize)i >= (usize)len) { /* a negative i is huge as a usize */
    fflush(NULL);
    dprintf(2, (u8 *)"%s: panic: index %td is out of bounds for length %td\n",
            where, i, len);
    abort();
  }
  return i;
}

static inline void rt_slice_check(isize lo, isize hi, isize len,
                                  const char *where) {
  if (0 <= lo && lo <= hi && hi <= len)
    return;
  fflush(NULL);
  if (lo > hi)
    dprintf(2, (u8 *)"%s: panic: slice [%td..%td] starts after it ends\n",
            where, lo, hi);
  else
    dprintf(2, (u8 *)"%s: panic: slice [%td..%td] is out of bounds for "
            "length %td\n", where, lo, hi, len);
  abort();
}
