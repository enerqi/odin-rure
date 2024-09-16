# odin-rure

[Odin](http://odin-lang.org/) bindings for the [rust regex](https://github.com/rust-lang/regex) [C API](https://github.com/rust-lang/regex/tree/master/regex-capi).

	"rure is a C API to Rust's regex library, which guarantees linear time searching using finite automata. In
	exchange, it must give up some common regex features such as backreferences and arbitrary lookaround. It does
	however include capturing groups, lazy matching, Unicode support and word boundary assertions. Its matching
	semantics generally correspond to Perl's, or "leftmost first." Namely, the match locations reported correspond to
	the first match that would be found by a backtracking engine."

## version

- `rure = "0.2.2"` which provides the C interface to Rust `regex = 1.*`

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

## Building the `rure` library (optional on Windows)

- The static library `rure.lib` for Windows is shipped with the bindings in `./lib`
- standard rust tooling can build the library on any platform
	- `git clone https://github.com/rust-lang/regex.git`
	- `cd regex/regex-capi`
	- `cargo build --release`
	- See artifacts in `../target/release`, e.g. `rure.lib` on Windows and `librure.a` on Linux

## native static library dependencies

When building the rust regex C API we can check extra static libraries that must be linked. These are included in the
Odin `foreign` definition for `rure`. You will get errors if they cannot be found on the system.

Windows:

	regex/regex-capi ❯ cargo rustc -q -- --print=native-static-libs
	note: Link against the following native artifacts when linking against this static library. The order and any
	      duplication can be significant on some platforms.

	note: native-static-libs: legacy_stdio_definitions.lib kernel32.lib advapi32.lib ntdll.lib userenv.lib ws2_32.lib kernel32.lib /defaultlib:msvcrt

Linux using `librure.a`:

	-lutil -ldl -lpthread -lgcc_s -lc -lm -lrt -lutil -lrure
