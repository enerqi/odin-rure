when ODIN_OS == .Windows {
	// regex\regex-capi ❯ cargo rustc -q -- --print=native-static-libs
	// note: Link against the following native artifacts when linking against this static library. The order and any
	//       duplication can be significant on some platforms.
	//
	// note: native-static-libs: legacy_stdio_definitions.lib kernel32.lib advapi32.lib ntdll.lib userenv.lib ws2_32.lib kernel32.lib /defaultlib:msvcrt
	foreign import lib {"lib/rure.lib", "system:legacy_stdio_definitions.lib", "system:advapi32.lib", "system:ntdll.lib", "system:userenv.lib", "system:ws2_32.lib"} // rure.lib is shipped with these bindings. See also -print-linker-flags, -extra-linker-flags, @extra_linker_flags

} else when ODIN_OS ==
	.Linux || ODIN_OS == .FreeBSD || ODIN_OS == .OpenBSD || ODIN_OS == .Darwin || ODIN_OS == .NetBSD {
	// cargo rustc -q -- --print=native-static-libs
	// note: Link against the following native artifacts when linking against this static library. The order and any
	// duplication can be significant on some platforms.
	//
	// note: native-static-libs: -lgcc_s -lutil -lrt -lpthread -lm -ldl -lc
	when !#exists("lib/librure.a") {
		#panic(
			"Cannot find compiled rure library ./lib/librure.a. 'cargo build -- release' rust regex project (see README.md). " +
			"Note will statically link against -lgcc_s -lutil -lrt -lpthread -lm -ldl -lc",
		)
	}
	foreign import lib {"lib/librure.a", "system:gcc_s", "system:util", "system:rt", "system:pthread", "system:m", "system:dl", "system:c"}
} else {
	#panic("TODO: Unknown or Untested OS.")
}

/*
 * The flags listed below can be used in rure_compile to set the default
 * flags. All flags can otherwise be toggled in the expression itself using
 * standard syntax, e.g., `(?i)` turns case insensitive matching on and `(?-i)`
 * disables it.
 */
Compile_Flag :: enum c.uint32_t {
	/* The case insensitive (i) flag. */
	FLAG_CASEI      = 0, // first bit, bit 0  (1 << 0)
	/* The multi-line matching (m) flag. (^ and $ match new line boundaries.) */
	FLAG_MULTI      = 1,
	/* The any character (s) flag. (. matches new line.) */
	FLAG_DOTNL      = 2,
	/* The greedy swap (U) flag. (e.g., + is ungreedy and +? is greedy.) */
	FLAG_SWAP_GREED = 3,
	/* The ignore whitespace (x) flag. */
	FLAG_SPACE      = 4,
	/* The Unicode (u) flag. */
	FLAG_UNICODE    = 5,
}
Compile_Flags :: bit_set[Compile_Flag;c.uint32_t]

DEFAULT_FLAGS :: Compile_Flags{.FLAG_UNICODE}

// Haystack text bytes pointer (text that is searched for regex matches) should be ascii or utf8 (*not* a cstring).
// Other text encodings are not supported - though it will not error, matching will not find what you want
//
// Use `haystack_ref` to reference an Odin string as `HAYSTACK_TEXT_P`
HAYSTACK_TEXT_P :: distinct [^]c.uint8_t

// Reference an Odin string as a haystack
haystack_ref :: #force_inline proc(s: string) -> HAYSTACK_TEXT_P {
	return HAYSTACK_TEXT_P(raw_data(s))
}

// Pattern text bytes pointer (text containing the regex pattern) *must be valid utf-8*
//
// Use `pattern_ref` to reference an Odin string as `PATTERN_TEXT_P`
PATTERN_TEXT_P :: distinct [^]c.uint8_t

// Reference an Odin string as a pattern
pattern_ref :: #force_inline proc(s: string) -> PATTERN_TEXT_P {
	return PATTERN_TEXT_P(raw_data(s))
}
