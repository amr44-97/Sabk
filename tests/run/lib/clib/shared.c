// built as libsabk_shared.so only: the program finds it at run time
// through the loader's path (`sabk --run` sets it)
int sabk_shared_triple(int x) { return 3 * x; }
