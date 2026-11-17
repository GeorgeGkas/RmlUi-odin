#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>

typedef struct Abi_String {
	const char* data;
	size_t size;
} Abi_String;

typedef void (*Abi_Callback)(Abi_String value, void* user_data);

__declspec(dllexport) bool abi_check(Abi_String value, const char* expected, size_t expected_size)
{
	if (value.data == NULL || value.size != expected_size)
		return false;
	return memcmp(value.data, expected, expected_size) == 0;
}

__declspec(dllexport) Abi_String abi_echo(Abi_String value)
{
	return value;
}

__declspec(dllexport) void abi_call(Abi_Callback callback, void* user_data)
{
	Abi_String value;
	value.data = "from-c";
	value.size = 6;
	callback(value, user_data);
}
