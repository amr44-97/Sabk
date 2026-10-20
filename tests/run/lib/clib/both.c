// built as libsabk_both.a and libsabk_both.so (with -DSHARED): the program
// links the static one, and #run opens the shared one
#include <math.h>

int sabk_both_add(int a, int b) { return a + b; }

const char *sabk_both_kind(void) {
#ifdef SHARED
  return "shared";
#else
  return "static";
#endif
}

// needs libm, which a static archive doesn't bring along
double sabk_both_hypot(double a, double b) { return sqrt(a * a + b * b); }

int sabk_both_counter = 41;
