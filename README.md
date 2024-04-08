# `sfcrand`: SFC64 random number generators for Lua
This is a set of implementations of the SFC64 non-cryptographic pseudorandom number generator as Lua libraries.

SFC64 was originally developed by Chris Doty-Humphrey as part of the PractRand PRNG testing suite and is available as an option in NumPy. It has been rigorously statistically tested.

## Versions
Two versions are provided:
* the LuaJIT version, which runs on LuaJIT 2.1 or later.
* the mainline Lua version, which runs on Lua 5.3 and 5.4.

Neither version needs any external dependencies.

Both versions expect that Lua floating numbers are of type `double`, and the mainline Lua version expects that integers are 64 bits. The LuaJIT version requires support for 64-bit bitwise operations on FFI types, and as such will not work on LuaJIT 2.0.5 or earlier.

The two versions behave slightly differently to account for differences in their environment and standard library. For example, `sfcrand.random(0)` returns an integer in the mainline version and raises an error in the LuaJIT version.

## Usage
The library should be loaded using `local sfcrand = require "sfcrand"`. If you do not do this, the shared RNG will not work properly.

### Library-level functions
|Syntax|Function|Version availability|
|------|--------|--------------------|
|`sfcrand.new([x, [y, [z]]])`, `sfcrand([x, [y, [z]]])`|Creates a new random state with an optional integer seed.|Both*|
|`sfcrand.fromstring(str)`|Loads a random state from a string created by `tostring(state)`.|Both*|
|`sfcrand.next()`|Gets the next floating point output on the interval [0,1) from the shared RNG.|Both|
|`sfcrand.next_int()`|Gets the next 64-bit integer output from the shared RNG.|Mainline|
|`sfcrand.next_normal()`|Get a normally-distributed floating point value from the shared RNG.|Mainline**|
|`sfcrand.next_raw()`|Get the next output from the shared RNG as a `uint64_t` cdata.|LuaJIT|
|`sfcrand.random([n,[m]])`|Acts similarly to `math.random`. Works on the shared RNG.|Both*|
|`sfcrand.randomseed([x, [y, [z]])`|Reseeds the shared RNG with the given integer seeds.|Both*|

### State-level functions
|Syntax|Function|Version support|
|------|--------|--------------------|
|`state:next()`|Gets the next floating point output on the interval [0,1) from the state.|Both|
|`state:next_int()`|Gets the next 64-bit integer output from the state.|Mainline|
|`state:next_normal()`|Get the next normally-distributed floating point value from the state.|Mainline**|
|`state:next_raw()`|Get the next output from the state as a `uint64_t` cdata.|LuaJIT|
|`state:random([n[,m]])`|Acts similarly to `math.random`.|Both*|
|`state:seed([x[,y[,z]])`|Reseeds the shared RNG with the given integer seeds.|Both*|
|`tostring(state)`|Converts a state into a string representation that can be loaded with `sfcrand.fromstring`.|Both*|

The `==` operator is implemented on states. Two states are equal if their internal states are equivalent. This does take into account the spare normal that the mainline version generates.

*This function is available in both the mainline and LuaJIT versions, but behaves differently in each. See the source for more details.
**I plan to implement `next_normal()` in the LuaJIT version as well, but have not sone so yet.

## Performance
On an M1 MacBook Air, the LuaJIT version performs faster than LuaJIT's `math.random`. The mainline Lua version on the same machine is slower than Lua 5.4's `math.random`.