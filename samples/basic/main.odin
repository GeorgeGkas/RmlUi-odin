package main

import "core:fmt"
import rmlui "../../rmlui"
import rmlui_backend "../../rmlui_backend"

app: struct {
	items:   [2]i32,
	counter: i32,
} = {items = {3, 9}, counter = 1}

int_definition: ^rmlui.Data_Type_Definition
callback_context: rmlui.Callback_Context
model_handle: rmlui.Data_Model_Handle

int_get :: proc "c" (_: rawptr, ptr: rawptr, out_value: ^rmlui.Variant) -> bool {
	rmlui.variant_set_int(out_value, (cast(^i32)ptr)^)
	return true
}

int_set :: proc "c" (_: rawptr, ptr: rawptr, value: ^rmlui.Variant) -> bool {
	out: i32
	if !rmlui.variant_get_int(value, &out) {
		return false
	}
	(cast(^i32)ptr)^ = out
	return true
}

items_size :: proc "c" (_: rawptr, _: rawptr) -> i32 {
	return 2
}

items_child :: proc "c" (_: rawptr, ptr: rawptr, index: i32) -> rmlui.Data_Variable {
	if index < 0 || index >= 2 {
		return {}
	}
	items := cast(^[2]i32)ptr
	return {definition = int_definition, ptr = &items[index]}
}

Listener_Box :: struct {
	listener:    ^rmlui.Event_Listener,
	app_context: ^rmlui.Callback_Context,
	index:       i32,
}

listener_slots: [8]Listener_Box
listener_used: [8]bool

acquire_listener :: proc(app_context: ^rmlui.Callback_Context) -> ^Listener_Box {
	for &used, index in listener_used {
		if !used {
			used = true
			box := &listener_slots[index]
			box^ = {}
			box.app_context = app_context
			box.index = i32(index)
			return box
		}
	}
	return nil
}

destroy_listener :: proc "c" (user_data: rawptr, _: ^rmlui.Element) {
	box := cast(^Listener_Box)user_data
	listener := box.listener
	box.listener = nil
	if listener != nil {
		rmlui.event_listener_destroy(listener)
	}
	if box.index >= 0 && box.index < len(listener_used) {
		listener_used[box.index] = false
	}
}

on_click :: proc "c" (user_data: rawptr, _: ^rmlui.Event) {
	box := cast(^Listener_Box)user_data
	context = box.app_context.ctx
	fmt.println("event listener")
}

on_increment :: proc "c" (user_data: rawptr, _: ^rmlui.Event) {
	box := cast(^Listener_Box)user_data
	context = box.app_context.ctx
	app.counter += 1
	rmlui.data_model_handle_dirty_variable(model_handle, "counter")
	fmt.println("onclick, counter =", app.counter)
}

instance_onclick :: proc "c" (user_data: rawptr, value: string, _: ^rmlui.Element) -> ^rmlui.Event_Listener {
	app_context := cast(^rmlui.Callback_Context)user_data
	context = app_context.ctx
	fmt.println("onclick attribute:", value)
	box := acquire_listener(app_context)
	if box == nil {
		return nil
	}
	callbacks := rmlui.Event_Listener_Callbacks {
		process_event = on_increment,
		on_detach = destroy_listener,
	}
	box.listener = rmlui.event_listener_create(&callbacks, box)
	return box.listener
}

key_down :: proc "c" (_: rawptr, _: ^rmlui.Context, key: rmlui.Key_Identifier, _: i32, _: f32, _: bool) -> bool {
	if key == .F8 {
		rmlui.debugger_set_visible(!rmlui.debugger_is_visible())
	}
	return true
}

main :: proc() {
	if !rmlui_backend.backend_initialize("RmlUi Odin", 1024, 768, true) {
		fmt.eprintln("Failed to open the backend window.")
		return
	}
	defer rmlui_backend.backend_shutdown()

	rmlui.set_system_interface(rmlui_backend.backend_get_system_interface())
	rmlui.set_render_interface(rmlui_backend.backend_get_render_interface())
	if !rmlui.initialise() {
		fmt.eprintln("Failed to initialise RmlUi.")
		return
	}
	defer rmlui.shutdown()

	if !rmlui.load_font_face("deps/RmlUi/Samples/assets/LatoLatin-Regular.ttf") {
		fmt.eprintln("Failed to load deps/RmlUi/Samples/assets/LatoLatin-Regular.ttf. Run this from the package root.")
		return
	}

	ctx := rmlui.create_context("main", {1024, 768})
	if ctx == nil {
		fmt.eprintln("Failed to create a context.")
		return
	}

	if !rmlui.debugger_initialise(ctx) {
		fmt.eprintln("Failed to initialise the debugger.")
		rmlui.remove_context("main")
		return
	}

	callback_context.ctx = context
	listener_instancer := rmlui.event_listener_instancer_create(instance_onclick, &callback_context)
	rmlui.register_event_listener_instancer(listener_instancer)
	defer {
		rmlui.register_event_listener_instancer(nil)
		rmlui.event_listener_instancer_destroy(listener_instancer)
	}

	model := rmlui.context_create_data_model(ctx, "game", false)
	model_handle = rmlui.data_model_get_handle(model)
	if !rmlui.data_model_constructor_is_valid(model) || !rmlui.data_model_bind_int(model, "counter", &app.counter) {
		fmt.eprintln("Failed to bind the counter.")
		rmlui.remove_context("main")
		return
	}

	int_callbacks := rmlui.Data_Type_Definition_Callbacks {
		get = int_get,
		set = int_set,
	}
	int_definition = rmlui.data_type_definition_create(.SCALAR, &int_callbacks, nil)
	defer rmlui.data_type_definition_destroy(int_definition)

	array_callbacks := rmlui.Data_Type_Definition_Callbacks {
		size = items_size,
		child_by_index = items_child,
	}
	array_definition := rmlui.data_type_definition_create(.ARRAY, &array_callbacks, nil)
	defer rmlui.data_type_definition_destroy(array_definition)
	defer rmlui.remove_context("main")
	if !rmlui.data_model_bind_custom(model, "items", array_definition, &app.items) {
		fmt.eprintln("Failed to bind the item list.")
		return
	}

	document_rml := `
		<rml>
		<head>
			<style>
				body { font-family: LatoLatin; font-size: 22dp; width: 100%; height: 100%; background: #1d1f24; color: #f2f2f2; padding: 32px; }
				button { font-size: 18dp; padding: 8px 16px; }
			</style>
		</head>
		<body data-model="game">
			<h1>Count: {{ counter }}</h1>
			<p>Items: {{ items[0] }}, {{ items[1] }}</p>
			<button id="inc" onclick="increment">Increment</button>
			<p>Press F8 to toggle the debugger.</p>
		</body>
		</rml>
	`
	document := rmlui.context_load_document_from_memory(ctx, document_rml)
	if document == nil {
		fmt.eprintln("Failed to load the document.")
		return
	}
	rmlui.document_show(document)

	click_box := acquire_listener(&callback_context)
	if click_box == nil {
		fmt.eprintln("Failed to allocate a click listener.")
		return
	}
	click_callbacks := rmlui.Event_Listener_Callbacks {
		process_event = on_click,
		on_detach = destroy_listener,
	}
	click_box.listener = rmlui.event_listener_create(&click_callbacks, click_box)
	button := rmlui.element_get_element_by_id(rmlui.document_as_element(document), "inc")
	if button != nil {
		rmlui.element_add_event_listener(button, "click", click_box.listener)
	} else {
		destroy_listener(click_box, nil)
	}

	fmt.println("Odin sample running. Close the window to exit.")
	for {
		if !rmlui_backend.backend_process_events(ctx, key_down, nil) {
			break
		}
		rmlui.context_update(ctx)
		rmlui_backend.backend_begin_frame()
		rmlui.context_render(ctx)
		rmlui_backend.backend_present_frame()
	}
}
