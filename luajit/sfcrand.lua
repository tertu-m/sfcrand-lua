--[[
sfcrand.lua (LuaJIT version)
SFC64 random number generator implementation for LuaJIT
Uses an FFI representation of the state for performance.
The algorithm was developed by Chris Doty-Humphrey.

State function notes:
state:random(...) - Functions like Lua 5.1 math.random(), except for the following differences:
- random(n) and random(n, m) will raise an error if math.abs(n) or math.abs(m) > 2^53.
tostring(state) - Converts a state to a string that can be reloaded with sfcrand.fromstring().
- The strings produced by this function cannot be loaded by the mainline Lua version of sfcrand.

Library function notes:
sfcrand.fromstring(str) - Loads a state from a state string created by tostring.
- This function cannot load state strings produced by the mainline Lua version of sfcrand.

(c) 2024 tertu
Few rights reserved.
This software shall be used for Good, not Evil.
]]--

local bit = require "bit"
local ffi = require "ffi"

ffi.cdef [[
    typedef struct sfc64_state { uint64_t a; uint64_t b; uint64_t c; uint64_t ctr; } sfc64_state_t;
]]

-- Functions, types, and constants that will be useful later.
local rshift = bit.rshift
local uint64_ct = ffi.typeof "uint64_t"
local int64_ct = ffi.typeof "int64_t"
local LARGEST_EXACT_INTEGER = 2^53

-- Returns the next output as a uint64_t in cdata form.
local function sfc64_next_bits(state)
    local result = state.a + state.b + state.ctr
    state.ctr = state.ctr + 1
    state.a = bit.bxor(state.b, rshift(state.b, 11))
    state.b = state.c + bit.lshift(state.c, 3)
    state.c = result + bit.rol(state.c, 24)
    return result
end

-- Returns if the given Lua number is an integer.
local function lnum_is_integer(num)
    num = tonumber(num)
    if num == nil then
        return false
    elseif math.floor(num) ~= num then
        -- This will catch most non-integers.
        -- It will also catch nan because nan ~= nan.
        return false
    elseif math.abs(num) == math.huge then
        return false
    end

    return true
end

-- Reseeds a random number generator. Up to 3 Lua integer seeds are permitted.
-- Negative seeds work but will be converted mod 2^64.
local DEFAULT_SEEDS = {1, 11001100, 606084}

local function sfc64_seed(state, err_level, ...)
    err_level = err_level+1
    local provided_seeds = {...}
    for i=1,3 do
        if provided_seeds[i] == nil then
            provided_seeds[i] = DEFAULT_SEEDS[i]
        elseif not lnum_is_integer(provided_seeds[i]) then
            error("seed "..i.." is not an integer", err_level)
        end
    end
    -- Seeds are inserted in reverse order.
    state.a = provided_seeds[3]
    state.b = provided_seeds[2]
    state.c = provided_seeds[1]
    state.ctr = 1
    -- 20 is the canonical number of mixing steps to do per Doty-Humphrey.
    for i = 1, 20 do
        sfc64_next_bits(state)
    end
end

local function sfc64_next_double(state)
    return tonumber(rshift(sfc64_next_bits(state), 11)) * 0x1.0p-53
end

-- Return an unbiased random uint64_t on the interval [0, range).
-- Will divide by 0 if range is 0, but this library will never call it with a range of 0.
-- Technique derived from the Java standard library by way of M. E. O'Neill.
local function sfc64_next_range(state, range)
    -- We need uint64_t semantics to work on range.
    range = uint64_ct(range)
    local candidate, adjusted
    local neg_range = -range

    repeat
        candidate = sfc64_next_bits(state)
        adjusted = candidate % range
    until candidate - adjusted <= neg_range

    return adjusted
end

-- Implements an interface similar to math.random.
-- This function might return a cdata or a Lua number depending on the code path.
-- Make sure to call tonumber() on its output.

local function sfc64_lua_random(state, err_level, arg1, arg2)
    local min = 1
    local max
    err_level = err_level + 1

    if arg2 ~= nil then
        if not lnum_is_integer(arg2) then
            error("second argument must be an integer", err_level)
        elseif math.abs(arg2) > LARGEST_EXACT_INTEGER then
            error("second argument cannot be represented as an exact integer", err_level)
        end
        max = arg2
    elseif arg1 == nil then
        -- random(): return a float on the interval [0,1).
        return sfc64_next_double(state)
    end

    if not lnum_is_integer(arg1) then
        error("first argument must be an integer", err_level)
    elseif math.abs(arg1) > LARGEST_EXACT_INTEGER then
        error("first argument cannot be represented as an exact integer", err_level)
    end

    if max then
        -- random(n, m): return an integer on the interval [n,m].
        min = arg1
    else
        -- random(n): return an integer on the interval [1, arg1].
        max = arg1
    end

    if min > max then
        error("interval is empty", err_level)
    end

    -- The spread between max and min might be too large to fit in a Lua number exactly,
    -- so convert max to an int64_t first. It will be positive and 2^54 or less, so it will always
    -- fit in a uint64_t.
    local range = int64_ct(max) - min
    if range == 0 then
        return min
    end

    -- min can be negative, so the result has to be coerced back to an int64_t.
    return min + int64_ct(sfc64_next_range(state, range + 1))
end

-- Convert a state into its string representation.
-- The first number is a version field.
local function sfc64_tostring(state)
    local out_tab = {
        tostring(uint64_ct(1)),
        tostring(state.a),tostring(state.b),tostring(state.c),tostring(state.ctr)
    }
    return table.concat(out_tab, ",")
end

local sfc_generator

-- Reconstitute a state from a string representation.
-- Some lenience is given.
local function sfc64_fromstring(str, err_level)
    err_level = err_level + 1
    local matches = string.match("(%d)*ULL,(%d)*ULL,(%d)*ULL,(%d)*ULL,(%d)*ULL", str)
    if #matches ~= 5 then
        error("invalid state", err_level)
    end
    if uint64_ct(matches[1]) ~= 1 then
        error("invalid version", err_level)
    end
    return sfc_generator(
        uint64_ct(matches[2]),
        uint64_ct(matches[3]),
        uint64_ct(matches[4]),
        uint64_ct(matches[5])
    )
end

local mt = {
    __tostring = function(self) return sfc64_tostring(self) end,
    __index = {
        next_raw = function(self) return sfc64_next_bits(self) end,
        -- An efficient function when you just want a number from [0,1).
        next = function(self) return sfc64_next_double(self) end,
        -- The standard math.random* interface.
        random = function(self, arg1, arg2) return tonumber(sfc64_lua_random(self, 2, arg1, arg2)) end,
        seed = function(self, ...) return sfc64_seed(self, 2, ...) end,
    }
}
sfc_generator = ffi.metatype("sfc64_state_t", mt)

local global_generator = sfc_generator()
-- LuaJIT sometimes provides math.random with a random seed.
-- If it doesn't, it's probably not worse than using no seed.
local global_generator_seeds = {}
for i=1, 3 do
    global_generator_seeds[i] = math.random(-LARGEST_EXACT_INTEGER,LARGEST_EXACT_INTEGER)
end
global_generator:seed(unpack(global_generator_seeds))
global_generator_seeds = nil

local sfcrand = {
    new = function(...)
        local state = sfc_generator()
        sfc64_seed(state, 2, ...)
        return state
    end,
    fromstring = function(str)
        -- Stash it in a local so that error levels work as we would like.
        local state = sfc64_fromstring(str, 2)
        return state
    end,
    -- Convenience functions that call methods of the "global" generator.
    next = function() return global_generator:next() end,
    next_raw = function() return global_generator:next_raw() end,
    random = function(arg1, arg2) return global_generator:random(arg1, arg2) end,
    randomseed = function(...) return global_generator:seed(...) end,
}

setmetatable(sfcrand, {
    __call = function(self, ...) return sfcrand.new(...) end
})

return sfcrand