// rure examples based on the C test within the regex-capi project code
package rure_example

import "core:c"
import "core:c/libc"
import "core:log"
import "core:mem"
import "core:os"
import "core:strings"
import "core:time"

import rure ".."

test_is_match :: proc() -> bool {
	haystack := "snowman: \xE2\x98\x83"
	re := rure.compile_must("\\p{So}$")
	defer rure.free(re)

	passed := true
	matched := rure.is_match(re, rure.haystack_ref(haystack), len(haystack), 0)
	if !matched {
		log.debug("[test_is_match] expected match, but got no match\n")
		passed = false
	}
	return passed
}

test_shortest_match :: proc() -> bool {
	haystack := "aaaaa"
	re := rure.compile_must("a+")
	defer rure.free(re)

	end: c.size_t = 0
	matched := rure.shortest_match(re, rure.haystack_ref(haystack), len(haystack), 0, &end)
	passed := true
	if !matched {
		log.debug("[test_shortest_match] expected match, but got no match\n")
		passed = false
	}
	expect_end: c.size_t = 1
	if end != expect_end {
		log.debugf("[test_shortest_match] expected match end location %v but got %v\n", expect_end, end)
		passed = false
	}
	return passed
}

test_find :: proc() -> bool {
	haystack := "snowman: \xE2\x98\x83"
	re := rure.compile_must("\\p{So}$")
	defer rure.free(re)

	match: rure.Match = {}
	matched := rure.find(re, rure.haystack_ref(haystack), len(haystack), 0, &match)

	passed := true
	if !matched {
		log.debugf("[test_find] expected match, but got no match\n")
		passed = false
	}
	expect_start: c.size_t = 9
	expect_end: c.size_t = 12
	if match.start != expect_start || match.end != expect_end {
		log.debugf(
			"[test_find] expected match at (%v, %v), but got match at (%v, %v)\n",
			expect_start,
			expect_end,
			match.start,
			match.end,
		)
		passed = false
	}
	return passed
}

test_captures :: proc() -> bool {

	haystack := "snowman: \xE2\x98\x83"

	re := rure.compile_must(".(.*(?P<snowman>\\p{So}))$")
	defer rure.free(re)
	match: rure.Match = {}
	caps := rure.captures_new(re)
	defer rure.captures_free(caps)

	matched := rure.find_captures(re, rure.haystack_ref(haystack), len(haystack), 0, caps)

	passed := true
	if !matched {
		log.debug("[test_captures] expected match, but got no match\n")
		passed = false
	}

	expect_captures_len: c.size_t = 3
	captures_len := rure.captures_len(caps)
	if captures_len != expect_captures_len {
		log.debugf(
			"[test_captures] expected capture group length to be %v, but got %v\n",
			expect_captures_len,
			captures_len,
		)
		passed = false
	}

	expect_capture_index: c.uint32_t = 2
	capture_index := rure.capture_name_index(re, "snowman")
	if capture_index != expect_capture_index {
		log.debugf(
			"[test_captures] expected capture index %d for name 'snowman', but got %d\n",
			expect_capture_index,
			capture_index,
		)
		passed = false
	}

	expect_start: c.size_t = 9
	expect_end: c.size_t = 12
	rure.captures_at(caps, 2, &match)
	if match.start != expect_start || match.end != expect_end {
		log.debugf(
			"[test_captures] expected capture 2 match at (%v, %v), but got match at (%v, %v)\n",
			expect_start,
			expect_end,
			match.start,
			match.end,
		)
		passed = false
	}

	return passed
}

/*
 * This tests whether we can set the flags correctly. In this case, we disable
 * all flags, which includes disabling Unicode mode. When we disable Unicode
 * mode, we can match arbitrary possibly invalid UTF-8 bytes, such as \xFF.
 * (When Unicode mode is enabled, \xFF won't match .)
 */
test_flags :: proc() -> bool {
	passed := true
	pattern := "."
	haystack := "\xFF"

	re := rure.compile(rure.pattern_ref(pattern), len(pattern), {}, nil, nil)
	assert(re != nil)
	defer rure.free(re)

	matched := rure.is_match(re, rure.haystack_ref(haystack), len(haystack), 0)
	if !matched {
		log.debug("[test_flags] expected match, but got no match\n")
		passed = false
	}
	return passed
}

test_compile_error :: proc() -> bool {
	passed := true
	err := rure.error_new()
	defer rure.error_free(err)

	re := rure.compile(rure.pattern_ref("("), 1, {}, nil, err)
	if re != nil {
		log.debug("[test_compile_error] expected NULL regex pointer, but got non-NULL pointer\n")
		passed = false
		rure.free(re)
	}

	msg := rure.error_message(err)
	if strings.index(string(msg), "unclosed group") == -1 {
		log.debugf(
			"[test_compile_error] expected an 'unclosed parenthesis' error message, but got this instead: '%v'\n",
			msg,
		)
		passed = false
	}
	return passed
}


test_func :: #type proc() -> bool

run_test :: proc(test: test_func, name: string, passed: ^bool) {
	if (!test()) {
		passed^ = false
		log.error("FAILED:", name)
	} else {
		log.info("PASSED:", name)
	}
}

main :: proc() {
	start_time := time.now()

	logger := log.create_console_logger()
	defer log.destroy_console_logger(logger)
	context.logger = logger
	defer {
		run_time := time.since(start_time)
		log.info("program duration: ", run_time)
	}

	tracking_allocator: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking_allocator, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking_allocator)
	context.allocator = mem.tracking_allocator(&tracking_allocator)
	defer if len(tracking_allocator.allocation_map) > 0 || len(tracking_allocator.bad_free_array) > 0 {
		for _, v in tracking_allocator.allocation_map {
			log.errorf("Memory Leak:\t%v", v)
		}
		for bad_free in tracking_allocator.bad_free_array {
			log.errorf("%v allocation %p was freed badly\n", bad_free.location, bad_free.memory)
		}
	}

	passed := true
	run_test(test_is_match, "test_is_match", &passed)
	run_test(test_shortest_match, "test_shortest_match", &passed)
	run_test(test_find, "test_find", &passed)
	run_test(test_captures, "test_captures", &passed)
	run_test(test_flags, "test_flags", &passed)
	run_test(test_compile_error, "test_compile_error", &passed)

	if !passed {
		os.exit(1)
	}
}
