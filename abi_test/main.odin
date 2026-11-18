package abi_test

import "core:fmt"
import "core:os"

when ODIN_OS == .Windows {
	foreign import abi "abi.lib"
} else when ODIN_OS == .Darwin {
	foreign import abi "libabi.dylib"
} else {
	foreign import abi "libabi.so"
}

Callback :: proc "c" (value: string, user_data: rawptr)

@(link_prefix = "")
foreign abi {
	@(link_name = "abi_check")
	abi_check :: proc(value: string, expected: cstring, expected_size: uint) -> bool ---

	@(link_name = "abi_echo")
	abi_echo :: proc(value: string) -> string ---

	@(link_name = "abi_call")
	abi_call :: proc(callback: Callback, user_data: rawptr) ---
}

main :: proc() {
	param_ok := abi_check("hello", "hello", 5)
	echoed := abi_echo("world")
	return_ok := echoed == "world"

	got: string
	abi_call(proc "c" (value: string, user_data: rawptr) {
		(^string)(user_data)^ = value
	}, &got)
	callback_ok := got == "from-c"

	fmt.println("param", param_ok, "return", return_ok, "callback", callback_ok)
	fmt.println("echoed", echoed, "callback_value", got)
	if !(param_ok && return_ok && callback_ok) {
		os.exit(1)
	}
}
