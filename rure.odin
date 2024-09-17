package rure

import "core:c"


when ODIN_OS == .Windows {
	// regex\regex-capi ❯ cargo rustc -q -- --print=native-static-libs
	// note: Link against the following native artifacts when linking against this static library. The order and any
	//       duplication can be significant on some platforms.
	//
	// note: native-static-libs: legacy_stdio_definitions.lib kernel32.lib advapi32.lib ntdll.lib userenv.lib ws2_32.lib kernel32.lib /defaultlib:msvcrt
	foreign import rure {"lib/rure.lib", "system:legacy_stdio_definitions.lib", "system:advapi32.lib", "system:ntdll.lib", "system:userenv.lib", "system:ws2_32.lib"} // rure.lib is shipped with these bindings. See also -print-linker-flags, -extra-linker-flags, @extra_linker_flags

} else when ODIN_OS == .Linux || ODIN_OS == .FreeBSD || ODIN_OS == .OpenBSD || ODIN_OS == .Darwin || ODIN_OS == .NetBSD {
	// cargo rustc -q -- --print=native-static-libs
	// note: Link against the following native artifacts when linking against this static library. The order and any
	// duplication can be significant on some platforms.
	//
	// note: native-static-libs: -lgcc_s -lutil -lrt -lpthread -lm -ldl -lc
	when !#exists("lib/librure.a") {
		#panic(
			"Cannot find compiled rure library ./lib/librure.a. 'cargo build -- release' rust regex project (see README.md). " +
			"Note will statically link against -lgcc_s -lutil -lrt -lpthread -lm -ldl -lc"
		)
	}
	foreign import rure {"lib/librure.a", "system:gcc_s", "system:util", "system:rt", "system:pthread", "system:m", "system:dl", "system:c"}
} else {
	#panic("TODO: Unknown or Untested OS.")
}


// Haystack text bytes pointer (text that is searched for regex matches) should be ascii or utf8 (*not* a cstring).
// Other text encodings are not supported - though it will not error, matching will not find what you want
//
// Use `haystack_ref` to reference an Odin string as `HAYSTACK_TEXT_P`
HAYSTACK_TEXT_P :: distinct [^]c.uint8_t

// Reference an Odin string as a haystack
haystack_ref :: proc(s: string) -> HAYSTACK_TEXT_P {
	return HAYSTACK_TEXT_P(raw_data(s))
}

// Pattern text bytes pointer (text containing the regex pattern) *must be valid utf-8*
//
// Use `pattern_ref` to reference an Odin string as `PATTERN_TEXT_P`
PATTERN_TEXT_P :: distinct [^]c.uint8_t

// Reference an Odin string as a pattern
pattern_ref :: proc(s: string) -> PATTERN_TEXT_P {
	return PATTERN_TEXT_P(raw_data(s))
}

/*
 * rure is the type of a compiled regular expression.
 *
 * An rure can be safely used from multiple threads simultaneously.
 */
Rure :: struct {} // opaque type

/*
 * rure_set is the type of a set of compiled regular expressions.
 *
 * A rure can be safely used from multiple threads simultaneously.
 */
Set :: struct {}

/*
 * rure_options is the set of non-flag configuration options for compiling
 * a regular expression. Currently, only two options are available: setting
 * the size limit of the compiled program and setting the size limit of the
 * cache of states that the DFA uses while searching.
 *
 * For most uses, the default settings will work fine, and NULL can be passed
 * wherever a *rure_options is expected.
*/
Options :: struct {}

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

/*
 * rure_match corresponds to the location of a single match in a haystack.
 */
Match :: struct {
	/* The start position. */
	start: c.size_t,
	/* The end position. */
	end:   c.size_t,
}

/*
 * rure_captures represents storage for sub-capture locations of a match.
 *
 * Computing the capture groups of a match can carry a significant performance
 * penalty, so their use in the API is optional.
 *
 * An rure_captures value can be reused in multiple calls to rure_find_captures,
 * so long as it is used with the compiled regular expression that created
 * it.
 *
 * An rure_captures value may outlive its corresponding rure and can be freed
 * independently.
 *
 * It is not safe to use from multiple threads simultaneously.
 */
Captures :: struct {}

/*
 * rure_iter is an iterator over successive non-overlapping matches in a
 * particular haystack.
 *
 * An rure_iter value may not outlive its corresponding rure and should be freed
 * before its corresponding rure is freed.
 *
 * It is not safe to use from multiple threads simultaneously.
 */
Iter :: struct {}

/*
 * rure_iter_capture_names is an iterator over the list of capture group names
 * in this particular rure.
 *
 * An rure_iter_capture_names value may not outlive its corresponding rure,
 * and should be freed before its corresponding rure is freed.
 *
 * It is not safe to use from multiple threads simultaneously.
 */
Iter_capture_names :: struct {}

/*
 * rure_error is an error that caused compilation to fail.
 *
 * Most errors are syntax errors but an error can be returned if the compiled
 * regular expression would be too big.
 *
 * Whenever a function accepts an *rure_error, it is safe to pass NULL. (But
 * you will not get access to the error if one occurred.)
 *
 * It is not safe to use from multiple threads simultaneously.
 */
Error :: struct {}


@(default_calling_convention = "c", link_prefix = "rure_")
foreign rure {

	/*
	 * rure_compile_must compiles the given pattern into a regular expression. If
	 * compilation fails for any reason, an error message is printed to stderr and
	 * the process is aborted.
	 *
	 * The pattern given should be in UTF-8. For convenience, this accepts a C
	 * string, which means the pattern cannot usefully contain NUL. If your pattern
	 * may contain NUL, consider using a regular expression escape sequence, or
	 * just use rure_compile.
	 *
	 * This uses RURE_DEFAULT_FLAGS.
	 *
	 * The compiled expression returned may be used from multiple threads
	 * simultaneously.
	 */
	compile_must :: proc(pattern: cstring) -> ^Rure ---

	/*
	 * rure_compile compiles the given pattern into a regular expression. The
	 * pattern must be valid UTF-8 and the length corresponds to the number of
	 * bytes in the pattern.
	 *
	 * flags is a bitfield. Valid values are constants declared with prefix
	 * RURE_FLAG_.
	 *
	 * options contains non-flag configuration settings. If it's NULL, default
	 * settings are used. options may be freed immediately after a call to
	 * rure_compile.
	 *
	 * error is set if there was a problem compiling the pattern (including if the
	 * pattern is not valid UTF-8). If error is NULL, then no error information
	 * is returned. In all cases, if an error occurs, NULL is returned.
	 *
	 * The compiled expression returned may be used from multiple threads
	 * simultaneously.
	 */
	compile :: proc(pattern: PATTERN_TEXT_P, length: c.size_t, flags: Compile_Flags, options: ^Options = nil, error: ^Error = nil) -> ^Rure ---

	/*
	 * rure_free frees the given compiled regular expression.
	 *
	 * This must be called at most once for any rure.
	 */
	free :: proc(re: ^Rure) ---

	/*
	 * rure_is_match returns true if and only if re matches anywhere in haystack.
	 *
	 * haystack may contain arbitrary bytes, but ASCII compatible text is more
	 * useful. UTF-8 is even more useful. Other text encodings aren't supported.
	 * length should be the number of bytes in haystack.
	 *
	 * start is the position at which to start searching. Note that setting the
	 * start position is distinct from incrementing the pointer, since the regex
	 * engine may look at bytes before the start position to determine match
	 * information. For example, if the start position is greater than 0, then the
	 * \A ("begin text") anchor can never match.
	 *
	 * rure_is_match should be preferred to rure_find since it may be faster.
	 *
	 * N.B. The performance of this search is not impacted by the presence of
	 * capturing groups in your regular expression.
	 */
	is_match :: proc(re: ^Rure, haystack: HAYSTACK_TEXT_P, length: c.size_t, start: c.size_t) -> bool ---

	/*
	 * rure_find returns true if and only if re matches anywhere in haystack.
	 * If a match is found, then its start and end offsets (in bytes) are set
	 * on the match pointer given.
	 *
	 * haystack may contain arbitrary bytes, but ASCII compatible text is more
	 * useful. UTF-8 is even more useful. Other text encodings aren't supported.
	 * length should be the number of bytes in haystack.
	 *
	 * start is the position at which to start searching. Note that setting the
	 * start position is distinct from incrementing the pointer, since the regex
	 * engine may look at bytes before the start position to determine match
	 * information. For example, if the start position is greater than 0, then the
	 * \A ("begin text") anchor can never match.
	 *
	 * rure_find should be preferred to rure_find_captures since it may be faster.
	 *
	 * N.B. The performance of this search is not impacted by the presence of
	 * capturing groups in your regular expression.
	 */
	find :: proc(re: ^Rure, haystack: HAYSTACK_TEXT_P, length: c.size_t, start: c.size_t, match: ^Match) -> bool ---

	/*
	 * rure_find_captures returns true if and only if re matches anywhere in
	 * haystack. If a match is found, then all of its capture locations are stored
	 * in the captures pointer given.
	 *
	 * haystack may contain arbitrary bytes, but ASCII compatible text is more
	 * useful. UTF-8 is even more useful. Other text encodings aren't supported.
	 * length should be the number of bytes in haystack.
	 *
	 * start is the position at which to start searching. Note that setting the
	 * start position is distinct from incrementing the pointer, since the regex
	 * engine may look at bytes before the start position to determine match
	 * information. For example, if the start position is greater than 0, then the
	 * \A ("begin text") anchor can never match.
	 *
	 * Only use this function if you specifically need access to capture locations.
	 * It is not necessary to use this function just because your regular
	 * expression contains capturing groups.
	 *
	 * Capture locations can be accessed using the rure_captures_* functions.
	 *
	 * N.B. The performance of this search can be impacted by the number of
	 * capturing groups. If you're using this function, it may be beneficial to
	 * use non-capturing groups (e.g., `(?:re)`) where possible.
	 */
	find_captures :: proc(re: ^Rure, haystack: HAYSTACK_TEXT_P, length: c.size_t, start: c.size_t, captures: ^Captures) -> bool ---

	/*
	 * rure_shortest_match returns true if and only if re matches anywhere in
	 * haystack. If a match is found, then its end location is stored in the
	 * pointer given. The end location is the place at which the regex engine
	 * determined that a match exists, but may occur before the end of the proper
	 * leftmost-first match.
	 *
	 * haystack may contain arbitrary bytes, but ASCII compatible text is more
	 * useful. UTF-8 is even more useful. Other text encodings aren't supported.
	 * length should be the number of bytes in haystack.
	 *
	 * start is the position at which to start searching. Note that setting the
	 * start position is distinct from incrementing the pointer, since the regex
	 * engine may look at bytes before the start position to determine match
	 * information. For example, if the start position is greater than 0, then the
	 * \A ("begin text") anchor can never match.
	 *
	 * rure_shortest_match should be preferred to rure_find since it may be faster.
	 *
	 * N.B. The performance of this search is not impacted by the presence of
	 * capturing groups in your regular expression.
	 */
	shortest_match :: proc(re: ^Rure, haystack: HAYSTACK_TEXT_P, length: c.size_t, start: c.size_t, end: ^c.size_t) -> bool ---

	/*
	 * rure_capture_name_index returns the capture index for the name given. If
	 * no such named capturing group exists in re, then -1 is returned.
	 *
	 * The capture index may be used with rure_captures_at.
	 *
	 * This function never returns 0 since the first capture group always
	 * corresponds to the entire match and is always unnamed.
	 */
	capture_name_index :: proc(re: ^Rure, name: cstring) -> c.uint32_t ---

	/*
	 * rure_iter_capture_names_new creates a new capture_names iterator.
	 *
	 * An iterator will report all successive capture group names of re.
	 */
	iter_capture_names_new :: proc(re: ^Rure) -> ^Iter_capture_names ---

	/*
	 * rure_iter_capture_names_free frees the iterator given.
	 *
	 * It must be called at most once.
	 */
	iter_capture_names_free :: proc(it: ^Iter_capture_names) ---

	/*
	 * rure_iter_capture_names_next advances the iterator and returns true
	 * if and only if another capture group name exists.
	 *
	 * The value of the capture group name is written to the provided pointer.
	 */
	iter_capture_names_next :: proc(it: ^Iter_capture_names, name: ^cstring) -> bool ---

	/*
	 * rure_iter_new creates a new iterator.
	 *
	 * An iterator will report all successive non-overlapping matches of re.
	 * When calling iterator functions, the same haystack and length must be
	 * supplied to all invocations. (Strict pointer equality is, however, not
	 * required.)
	 */
	iter_new :: proc(re: ^Rure) -> ^Iter ---

	/*
	 * rure_iter_free frees the iterator given.
	 *
	 * It must be called at most once.
	 */
	iter_free :: proc(it: ^Iter) ---

	/*
	 * rure_iter_next advances the iterator and returns true if and only if a
	 * match was found. If a match is found, then the match pointer is set with the
	 * start and end location of the match, in bytes.
	 *
	 * If no match is found, then subsequent calls will return false indefinitely.
	 *
	 * haystack may contain arbitrary bytes, but ASCII compatible text is more
	 * useful. UTF-8 is even more useful. Other text encodings aren't supported.
	 * length should be the number of bytes in haystack. The given haystack must
	 * be logically equivalent to all other haystacks given to this iterator.
	 *
	 * rure_iter_next should be preferred to rure_iter_next_captures since it may
	 * be faster.
	 *
	 * N.B. The performance of this search is not impacted by the presence of
	 * capturing groups in your regular expression.
	 */
	iter_next :: proc(it: ^Iter, haystack: HAYSTACK_TEXT_P, length: c.size_t, match: ^Match) -> bool ---

	/*
	 * rure_iter_next_captures advances the iterator and returns true if and only if a
	 * match was found. If a match is found, then all of its capture locations are
	 * stored in the captures pointer given.
	 *
	 * If no match is found, then subsequent calls will return false indefinitely.
	 *
	 * haystack may contain arbitrary bytes, but ASCII compatible text is more
	 * useful. UTF-8 is even more useful. Other text encodings aren't supported.
	 * length should be the number of bytes in haystack. The given haystack must
	 * be logically equivalent to all other haystacks given to this iterator.
	 *
	 * Only use this function if you specifically need access to capture locations.
	 * It is not necessary to use this function just because your regular
	 * expression contains capturing groups.
	 *
	 * Capture locations can be accessed using the rure_captures_* functions.
	 *
	 * N.B. The performance of this search can be impacted by the number of
	 * capturing groups. If you're using this function, it may be beneficial to
	 * use non-capturing groups (e.g., `(?:re)`) where possible.
	 */
	iter_next_captures :: proc(it: ^Iter, haystack: HAYSTACK_TEXT_P, length: c.size_t, captures: ^Captures) -> bool ---

	/*
	 * rure_captures_new allocates storage for all capturing groups in re.
	 *
	 * An rure_captures value may be reused on subsequent calls to
	 * rure_find_captures or rure_iter_next_captures.
	 *
	 * An rure_captures value may be freed independently of re, although any
	 * particular rure_captures should be used only with the re given here.
	 *
	 * It is not safe to use an rure_captures value from multiple threads
	 * simultaneously.
	 */
	captures_new :: proc(re: ^Rure) -> ^Captures ---

	/*
	 * rure_captures_free frees the given captures.
	 *
	 * This must be called at most once.
	 */
	captures_free :: proc(captures: ^Captures) ---

	/*
	 * rure_captures_at returns true if and only if the capturing group at the
	 * index given was part of a match. If so, the given match pointer is populated
	 * with the start and end location (in bytes) of the capturing group.
	 *
	 * If no capture group with the index i exists, then false is
	 * returned. (A capturing group exists if and only if i is less than
	 * rure_captures_len(captures).)
	 *
	 * Note that index 0 corresponds to the full match.
	 */
	captures_at :: proc(captures: ^Captures, i: c.size_t, match: ^Match) -> bool ---

	/*
	 * rure_captures_len returns the number of capturing groups in the given
	 * captures.
	 */
	captures_len :: proc(captures: ^Captures) -> c.size_t ---

	/*
	 * rure_options_new allocates space for options.
	 *
	 * Options may be freed immediately after a call to rure_compile, but otherwise
	 * may be freely used in multiple calls to rure_compile.
	 *
	 * It is not safe to set options from multiple threads simultaneously. It is
	 * safe to call rure_compile from multiple threads simultaneously using the
	 * same options pointer.
	 */
	options_new :: proc() -> ^Options ---

	/*
	 * rure_options_free frees the given options.
	 *
	 * This must be called at most once.
	 */
	options_free :: proc(options: ^Options) ---

	/*
	 * rure_options_size_limit sets the approximate size limit of the compiled
	 * regular expression.
	 *
	 * This size limit roughly corresponds to the number of bytes occupied by a
	 * single compiled program. If the program would exceed this number, then a
	 * compilation error will be returned from rure_compile.
	 */
	options_size_limit :: proc(options: ^Options, limit: c.size_t) ---

	/*
	 * rure_options_dfa_size_limit sets the approximate size of the cache used by
	 * the DFA during search.
	 *
	 * This roughly corresponds to the number of bytes that the DFA will use while
	 * searching.
	 *
	 * Note that this is a *per thread* limit. There is no way to set a global
	 * limit. In particular, if a regular expression is used from multiple threads
	 * simultaneously, then each thread may use up to the number of bytes
	 * specified here.
	 */
	options_dfa_size_limit :: proc(options: ^Options, limit: c.size_t) ---

	/*
	 * rure_compile_set compiles the given list of patterns into a single regular
	 * expression which can be matched in a linear-scan. Each pattern in patterns
	 * must be valid UTF-8 and the length of each pattern in patterns corresponds
	 * to a byte length in patterns_lengths.
	 *
	 * The number of patterns to compile is specified by patterns_count. patterns
	 * must contain at least this many entries.
	 *
	 * flags is a bitfield. Valid values are constants declared with prefix
	 * RURE_FLAG_.
	 *
	 * options contains non-flag configuration settings. If it's NULL, default
	 * settings are used. options may be freed immediately after a call to
	 * rure_compile.
	 *
	 * error is set if there was a problem compiling the pattern.
	 *
	 * The compiled expression set returned may be used from multiple threads.
	 */
	compile_set :: proc(patterns: [^]PATTERN_TEXT_P, patterns_lengths: [^]c.size_t, patterns_count: c.size_t, flags: Compile_Flags, options: ^Options = nil, error: ^Error = nil) -> ^Set ---

	/*
	 * rure_set_free frees the given compiled regular expression set.
	 *
	 * This must be called at most once for any rure_set.
	 */
	set_free :: proc(re: ^Set) ---

	/*
	 * rure_is_match returns true if and only if any regexes within the set
	 * match anywhere in the haystack. Once a match has been located, the
	 * matching engine will quit immediately.
	 *
	 * haystack may contain arbitrary bytes, but ASCII compatible text is more
	 * useful. UTF-8 is even more useful. Other text encodings aren't supported.
	 * length should be the number of bytes in haystack.
	 *
	 * start is the position at which to start searching. Note that setting the
	 * start position is distinct from incrementing the pointer, since the regex
	 * engine may look at bytes before the start position to determine match
	 * information. For example, if the start position is greater than 0, then the
	 * \A ("begin text") anchor can never match.
	 */
	set_is_match :: proc(re: ^Set, haystack: HAYSTACK_TEXT_P, length: c.size_t, start: c.size_t) -> bool ---

	/*
	 * rure_set_matches compares each regex in the set against the haystack and
	 * modifies matches with the match result of each pattern. Match results are
	 * ordered in the same way as the rure_set was compiled. For example,
	 * index 0 of matches corresponds to the first pattern passed to
	 * `rure_compile_set`.
	 *
	 * haystack may contain arbitrary bytes, but ASCII compatible text is more
	 * useful. UTF-8 is even more useful. Other text encodings aren't supported.
	 * length should be the number of bytes in haystack.
	 *
	 * start is the position at which to start searching. Note that setting the
	 * start position is distinct from incrementing the pointer, since the regex
	 * engine may look at bytes before the start position to determine match
	 * information. For example, if the start position is greater than 0, then the
	 * \A ("begin text") anchor can never match.
	 *
	 * matches must be greater than or equal to the number of patterns the
	 * rure_set was compiled with.
	 *
	 * Only use this function if you specifically need to know which regexes
	 * matched within the set. To determine if any of the regexes matched without
	 * caring which, use rure_set_is_match.
	 */
	set_matches :: proc(re: ^Set, haystack: HAYSTACK_TEXT_P, length: c.size_t, start: c.size_t, matches: [^]c.bool) -> bool ---

	/*
	 * rure_set_len returns the number of patterns rure_set was compiled with.
	 */
	set_len :: proc(re: ^Set) -> c.size_t ---

	/*
	 * rure_error_new allocates space for an error.
	 *
	 * If error information is desired, then rure_error_new should be called
	 * to create an rure_error pointer, and that pointer can be passed to
	 * rure_compile. If an error occurred, then rure_compile will return NULL and
	 * the error pointer will be set. A message can then be extracted.
	 *
	 * It is not safe to use errors from multiple threads simultaneously. An error
	 * value may be reused on subsequent calls to rure_compile.
	 */
	error_new :: proc() -> ^Error ---

	/*
	 * rure_error_free frees the error given.
	 *
	 * This must be called at most once.
	 */
	error_free :: proc(err: ^Error) ---

	/*
	 * rure_error_message returns a NUL terminated string that describes the error
	 * message.
	 *
	 * The pointer returned must not be freed. Instead, it will be freed when
	 * rure_error_free is called. If err is used in subsequent calls to
	 * rure_compile, then this pointer may change or become invalid.
	 */
	error_message :: proc(err: ^Error) -> cstring ---

	/*
	 * rure_escape_must returns a NUL terminated string where all meta characters
	 * have been escaped. If escaping fails for any reason, an error message is
	 * printed to stderr and the process is aborted.
	 *
	 * The pattern given should be in UTF-8. For convenience, this accepts a C
	 * string, which means the pattern cannot contain a NUL byte. These correspond
	 * to the only two failure conditions of this function. That is, if the caller
	 * guarantees that the given pattern is valid UTF-8 and does not contain a
	 * NUL byte, then this is guaranteed to succeed (modulo out-of-memory errors).
	 *
	 * The pointer returned must not be freed directly. Instead, it should be freed
	 * by calling rure_cstring_free.
	 */
	escape_must :: proc(pattern: cstring) -> cstring ---

	/*
	 * rure_cstring_free frees the string given.
	 *
	 * This must be called at most once per string.
	 */
	cstring_free :: proc(s: cstring) ---
}
