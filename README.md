# odin-rure

[Odin](http://odin-lang.org/) bindings for the [rust regex](https://github.com/rust-lang/regex) [C API](https://github.com/rust-lang/regex/tree/master/regex-capi).

"rure is a C API to Rust's regex library, which guarantees linear time searching using finite automata. In exchange, it
must give up some common regex features such as backreferences and arbitrary lookaround. It does however include
capturing groups, lazy matching, Unicode support and word boundary assertions. Its matching semantics generally
correspond to Perl's, or "leftmost first." Namely, the match locations reported correspond to the first match that
would be found by a backtracking engine."

## Why?

Rust regex is one of the [fastest regex libraries](https://github.com/rust-leipzig/regex-performance/blob/master/results_20221012.png) judging by many independent benchmarks.
Compared to the new Odin [text/regex](https://pkg.odin-lang.org/core/text/regex/) package it was 15x faster for a
particular use case. The API is small, easy to use and easy to create bindings for. Additionally it's easy to (re)build
the static libraries with the Rust `cargo` tooling, something that is often not true of larger `CMAKE` projects, even
with tools like `vcpkg`.

## Version

Prebuilt static `rure` libraries are built against Rust regex version:

| odin-rure tag | rure-capi version | prebuilt rust regex lib version |
|---------------|-------------------|---------------------------------|
| 2026-06       | 0.2.5             | 1.12.4                          |
| 2025-12       | 0.2.4             | 1.12.2                          |
| 2025-03       | 0.2.2             | 1.11.1                          |


## API structure

- symbols named `rure_something` in the C API are presented as `rure.something` in the bindings
- `struct` types are capitalized (e.g. `rure_options` -> `rure.Options`)
- Odin `bit_set`s are used where a number is passed as a flag (e.g. `rure.Compile_Flags`)
- default parameters maybe provided where valid `NULL` (`nil`) parameters can be used in the C API (e.g. `rure.Options`,
  `rure.Error` parameters)
- most `rure` types are opaque structures (empty `struct`s hiding implementation details) - used via pointers

`rure.HAYSTACK_TEXT_P` and `rure.PATTERN_TEXT_P` are two distinct Odin types for `const uint8_t*`. Patterns must be
`UTF-8` in `rure` whilst haystacks (searched text) can be ascii or `UTF-8` (even other text encodings but you might not
match items properly). Rust regex is [clear that `UTF-8` is the only supported format for unicode](https://github.com/rust-lang/regex/tree/master/regex-capi#text-encoding) - you must translate
other unicode formats such as `UTF-16` or `UTF-32`.

## Automated binding generation (the odin code)

The final `rure.odin` file is now generated from [odin-c-bindgen](https://github.com/karl-zylinski/odin-c-bindgen/).

The input C source header file is [inputs/rure.h](./inputs/rure.h) and any custom code / foreign imports are in
[inputs/prelude.odin](./inputs/prelude.odin). Assuming `bindgen.exe` is in your `PATH` just run the following to update
`rure.odin`:

> bindgen .


## Building the `rure` library (maybe optional)

- The static library `rure.lib` for Windows is shipped with the bindings in `./lib`
- The static library `librure.a` for Linux is shipped with the bindings in `./lib`
- standard rust tooling can (re)build the library on any platform if the prebuilt libraries are not suitable
	- `git clone https://github.com/rust-lang/regex.git`
	- `cd regex/regex-capi`
	- `cargo build --release`
	- See artifacts in `../target/release`, e.g. `rure.lib` on Windows and `librure.a` on Linux
	- Copy artifacts to `./lib`

#### Windows: match the C runtime (important)

A plain `cargo build --release` links `rure.lib` against the **dynamic** C runtime — you can see
`/defaultlib:msvcrt` in the `--print=native-static-libs` output below. Odin's Windows backend, however,
links the **static** CRT (`/defaultlib:libcmt`; see Odin `src/linker.cpp`). MSVC requires every object in
one link to use the same CRT — mixing static (`libcmt`) and dynamic (`msvcrt`) yields `LNK4098` and two
separate copies of the CRT (two heaps, two sets of `errno`/locale/stdio state) in a single executable,
which is unsupported and can corrupt state passed across the boundary.

Build `rure` with the static CRT so it also uses `libcmt`, matching the Odin host:

```
# in regex/regex-capi
RUSTFLAGS="-C target-feature=+crt-static" cargo build --release
```

This flips the internal directive from `/defaultlib:msvcrt` to `/defaultlib:libcmt`. After changing it,
re-run `--print=native-static-libs` (see below) and update the `foreign import` list in
`inputs/prelude.odin` — `legacy_stdio_definitions.lib` is an `msvcrt` shim and typically drops out.

#### Optional: build for performance

Rust LTO is safe to ship (unlike MSVC `/GL`, `rustc` emits real native COFF, so any MSVC-family linker —
`link.exe`, `lld-link`, `rad-link` — consumes the `.lib`). The `regex` stack is many crates
(`regex` → `regex-automata`, `aho-corasick`, `memchr`), so cross-crate inlining is a real win:

```
# in regex/regex-capi (combine with +crt-static above)
RUSTFLAGS="-C target-feature=+crt-static -C target-cpu=x86-64-v3" \
CARGO_PROFILE_RELEASE_LTO=fat \
CARGO_PROFILE_RELEASE_CODEGEN_UNITS=1 \
cargo build --release
```

- `lto=fat` + `codegen-units=1` — max optimization / cross-crate inlining. Slower build, but the lib is prebuilt and shipped.
- `target-cpu=x86-64-v3` — AVX2/BMI baseline codegen (matches this project's AVX2 stance; drops pre-2013 CPUs). Use the named level, **not** `native`, for a redistributable prebuilt lib.
- Note: `regex`/`memchr`/`aho-corasick` already do **runtime** SIMD feature detection, so the search hot paths use AVX2 at runtime regardless of `target-cpu`; this flag mainly helps autovectorize the rest.

On Windows there is a `just` shortcut that wraps all of the above (CRT match + LTO + `codegen-units=1` + the
AVX2 baseline), passing the flags via `cargo --config` so it is shell-agnostic:

```
just build_rure ../regex/regex-capi      # builds rure.lib with the right flags
just rure_native_libs ../regex/regex-capi # re-print the native static libs to link
```

#### Linux: no `+crt-static`

The CRT-match step is **Windows-only**. Linux has no static/dynamic CRT split to mismatch — Odin and
`librure.a` both link the system **glibc dynamically** (the `-lgcc_s -lutil -lrt -lpthread -lm -ldl -lc`
deps shown below are the normal dynamic glibc artifacts, and both sides already share the one system
glibc). Do **not** pass `+crt-static` on the default `x86_64-unknown-linux-gnu` target: it tries to
statically link glibc, which breaks `dlopen`/NSS at runtime (`getaddrinfo`, user/host lookups) and buys
nothing here. (A truly static Linux lib would mean switching the target to `x86_64-unknown-linux-musl`,
not `+crt-static` — and then Odin would need musl too, so it is not worth it.)

The performance flags still apply; just drop `+crt-static`:

```
# in regex/regex-capi
RUSTFLAGS="-C target-cpu=x86-64-v3" \
CARGO_PROFILE_RELEASE_LTO=fat \
CARGO_PROFILE_RELEASE_CODEGEN_UNITS=1 \
cargo build --release
# artifact: ../target/release/librure.a -> copy to ./lib
```

The `just build_rure` / `just rure_native_libs` recipes share the same names on Linux (`just` dispatches on
the host OS), so the same commands work — they use the Linux flag set automatically:

```
just build_rure ../regex/regex-capi
just rure_native_libs ../regex/regex-capi
```

### Static library dependencies

When building the rust regex C API we can check extra static libraries that must be linked. These are included in the
Odin `foreign` definition for `rure`. You will get errors if they cannot be found on the system.

Windows:

	regex/regex-capi ❯ cargo rustc -q -- --print=native-static-libs
	note: Link against the following native artifacts when linking against this static library. The order and any
	      duplication can be significant on some platforms.

	note: native-static-libs: legacy_stdio_definitions.lib kernel32.lib advapi32.lib ntdll.lib userenv.lib ws2_32.lib kernel32.lib /defaultlib:msvcrt

Linux using `librure.a`:

	-lgcc_s -lutil -lrt -lpthread -lm -ldl -lc
