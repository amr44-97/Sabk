// The VM's way to C (vm.sabk): libffi and dlsym. Their types and macros
// (ffi_cif, FFI_DEFAULT_ABI, RTLD_DEFAULT) differ between platforms, so
// they stay on this side; the VM sees opaque pointers.

#define _GNU_SOURCE
#include <dlfcn.h>
#include <ffi.h>
#include <stdlib.h>

// a function or variable the compiler itself can reach, or null
void *vmffi_dlsym(const char *name) { return dlsym(RTLD_DEFAULT, name); }

// a library opened for #run (a #library's or #system_library's shared
// object), or null; then vmffi_dlerror() says why
void *vmffi_dlopen(const char *path) { return dlopen(path, RTLD_NOW | RTLD_GLOBAL); }
void *vmffi_dlsym_in(void *library, const char *name) { return dlsym(library, name); }
const char *vmffi_dlerror(void) {
  const char *e = dlerror();
  return e ? e : "unknown error";
}

// the libffi type of a VM kind (vm.sabk's VmKind, in its order); -1: void
void *vmffi_type(int kind) {
  switch (kind) {
  case 0: return &ffi_type_sint8;
  case 1: return &ffi_type_sint16;
  case 2: return &ffi_type_sint32;
  case 3: return &ffi_type_sint64;
  case 4: return &ffi_type_uint8;
  case 5: return &ffi_type_uint16;
  case 6: return &ffi_type_uint32;
  case 7: return &ffi_type_uint64;
  case 8: return &ffi_type_float;
  case 9: return &ffi_type_double;
  case 10: return &ffi_type_uint8; // bool
  case -1: return &ffi_type_void;
  default: return &ffi_type_pointer;
  }
}

// A call interface for `count` arguments of the libffi types in `types`
// (which must outlive it), returning `ret`; `fixed` is the number of fixed
// parameters of a variadic function, or -1. Null if libffi can't make one.
void *vmffi_cif(int fixed, int count, void **types, void *ret) {
  ffi_cif *cif = malloc(sizeof *cif);
  ffi_status status =
      fixed < 0 ? ffi_prep_cif(cif, FFI_DEFAULT_ABI, (unsigned)count, ret,
                               (ffi_type **)types)
                : ffi_prep_cif_var(cif, FFI_DEFAULT_ABI, (unsigned)fixed,
                                   (unsigned)count, ret, (ffi_type **)types);
  if (status != FFI_OK) {
    free(cif);
    return NULL;
  }
  return cif;
}

void vmffi_call(void *cif, void *fn, void *ret, void **args) {
  ffi_call(cif, FFI_FN(fn), ret, args);
}

// A C function pointer, of the interface `cif`, that calls
// entry(cif, ret, args, data); null if libffi can't make one
void *vmffi_closure(void *cif, void (*entry)(ffi_cif *, void *, void **, void *),
                    void *data) {
  void *code = NULL;
  ffi_closure *closure = ffi_closure_alloc(sizeof(ffi_closure), &code);
  if (!closure || ffi_prep_closure_loc(closure, cif, entry, data, code) != FFI_OK)
    return NULL;
  return code;
}
