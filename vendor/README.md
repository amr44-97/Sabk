# vendor

Third-party code the build uses, kept as released.

- `qbe/`: [QBE](https://c9x.me/compile/) 1.3, the compiler backend
  `--qbe` writes its IL for (src/backend_qbe.sabk). From
  https://c9x.me/compile/release/qbe-1.3.tar.xz (sha256
  `d587905d620dc5e1d2bfa7c2cc642b9b837aa89a3188c6e37b53d756cf66e320`),
  unchanged. MIT license: `qbe/LICENSE`. `make` builds it into
  `build/qbe`, outside its own directory.
