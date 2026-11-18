when ODIN_OS == .Windows {
	foreign import lib {
		"lib/windows/rmlui_capi.lib",
	}
} else when ODIN_OS == .Linux {
	foreign import lib {
		"../bin/linux/librmlui_capi.so",
	}
} else when ODIN_OS == .Darwin {
	foreign import lib {
		"../bin/darwin/librmlui_capi.dylib",
	}
}
