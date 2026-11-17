package rmlui

import "base:runtime"
import "core:mem"

// Copies an owned C string into allocator-backed Odin memory and frees the C string.
owned_to_string :: proc(s: Owned_String, allocator := context.allocator) -> (result: string) {
	if s.data == nil || s.size == 0 {
		owned_string_free(s)
		return ""
	}
	buffer := make([]u8, s.size, allocator)
	mem.copy(&buffer[0], rawptr(s.data), int(s.size))
	owned_string_free(s)
	return string(buffer)
}

// Store this in user_data when a "c" callback needs Odin's implicit context
// (allocator, logger, and so on). A "c" procedure has no context of its own, and
// assigning context inside another procedure does not affect the caller, so the
// callback restores it directly:
//
//   context = (cast(^Callback_Context)user_data).ctx
Callback_Context :: struct {
	ctx: runtime.Context,
}
