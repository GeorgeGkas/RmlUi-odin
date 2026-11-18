#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>

#if defined(_WIN32)
#define ABI_EXPORT __declspec(dllexport)
#else
#define ABI_EXPORT __attribute__((visibility("default")))
#endif

typedef struct Abi_String {
	const char* data;
	size_t size;
} Abi_String;

typedef void (*Abi_Callback)(Abi_String value, void* user_data);

ABI_EXPORT bool abi_check(Abi_String value, const char* expected, size_t expected_size)
{
	if (value.data == NULL || value.size != expected_size)
		return false;
	return memcmp(value.data, expected, expected_size) == 0;
}

ABI_EXPORT Abi_String abi_echo(Abi_String value)
{
	return value;
}

ABI_EXPORT void abi_call(Abi_Callback callback, void* user_data)
{
	Abi_String value;
	value.data = "from-c";
	value.size = 6;
	callback(value, user_data);
}
