# checks i128_test.smelt's output against Python's integers
import sys
M = 1 << 128
def w(v):            # two's complement wrap to 128 bits
    v %= M
    return v - M if v >= (1 << 127) else v
def tdiv(a, b):
    q = abs(a) // abs(b)
    return q if (a < 0) == (b < 0) else -q
def tmod(a, b):
    r = abs(a) % abs(b)
    return -r if a < 0 else r
def fits(v, bits, signed):
    return -(1 << (bits - 1)) <= v < (1 << (bits - 1)) if signed else 0 <= v < (1 << bits)
def wrap(v, bits, signed):
    v &= (1 << bits) - 1
    return v - (1 << bits) if signed and v >> (bits - 1) else v
bad = 0
for n, line in enumerate(sys.stdin, 1):
    f = line.split()
    if not f: continue
    if f[0] == 'shift':
        a, s = int(f[1]), int(f[2])
        want = [str(w(a << s)), str(a >> s)]
        got = f[3:5]
    elif f[0] == 'fit':
        a, bits = int(f[1]), int(f[2])
        want = [str(fits(a, bits, True)).lower(), str(fits(a, bits, False)).lower(), str(wrap(a, bits, True)), str(wrap(a, bits, False))]
        got = f[3:7]
    elif f[0] == 'neg':
        continue
    else:
        a, b = int(f[0]), int(f[1])
        want = [str(w(a + b)), str(w(a - b)), str(w(a * b))]
        want += [str(w(tdiv(a, b))), str(tmod(a, b))] if b else ['-', '-']
        want += [str(a & b), str(a | b), str(a ^ b), str((a > b) - (a < b))]
        got = f[2:11]
    if got != want:
        bad += 1
        if bad <= 5: print('line', n, line.strip(), '\n  want', want)
print('mismatches:', bad)
