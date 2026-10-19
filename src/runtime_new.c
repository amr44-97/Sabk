
/* the context the prelude's default_context() runs in, before there is one */
static prelude__Context rt_boot_context;

static inline rawptr rt_new(prelude__Context *ctx, prelude__Allocator a,
                            isize size, isize align, const char *where) {
  if (size == 0)
    size = 1; /* every allocation gets its own address */
  rawptr p = a.procedure(ctx, a.data, 0 /* Alloc */, size, align, NULL, 0);
  if (!p)
    rt_panic(where, "out of memory");
  return memset(p, 0, (usize)size);
}
