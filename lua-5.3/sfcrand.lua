--[[
sfcrand.lua (mainline Lua version)
SFC64 random number generator implementation for Lua 5.3 and 5.4.
The algorithm was developed by Chris Doty-Humphrey.

State function notes:
state:random(...) - Functions like Lua 5.3/5.4 math.random().
tostring(state) - Converts a state to a string that can be reloaded with sfcrand.fromstring().
- The strings produced by this function cannot be loaded by the LuaJIT version of sfcrand.

Library functions notes:
sfcrand.fromstring(str) - Loads a state from a state string created by tostring.
- This function cannot load state strings produced by the LuaJIT version of sfcrand.

(c) 2024 tertu
Few rights reserved.
This software shall be used for Good, not Evil.
]]--

-- Returns the next output as an integer.
local function sfc64_next_bits(state)
    local b, c, ctr = state[2], state[3], state[4]
    local result = state[1] + b + ctr
    state[1] = b ~ (b >> 11)
    state[2] = c * 9
    state[3] = result + ((c << 24) | (c >> 40))
    state[4] = ctr + 1
    return result
end

local tointeger = math.tointeger

-- Reseeds a random number generator. Up to 3 integer seeds are permitted.
local DEFAULT_SEEDS = {1, 11001100, 606084}

local function sfc64_seed(state, err_level, ...)
    err_level = err_level+1
    local provided_seeds = {...}
    for i=1,3 do
        local provided_seed = provided_seeds[i]
        if provided_seeds[i] == nil then
            provided_seeds[i] = DEFAULT_SEEDS[i]
        else
            local as_int = tointeger(provided_seeds[i])
            if as_int == nil then
                error("could not convert seed "..i.." to integer", err_level)
            end
        end
    end
    -- Seeds are inserted in reverse order.
    state[1] = provided_seeds[3]
    state[2] = provided_seeds[2]
    state[3] = provided_seeds[1]
    state.ctr = 1
    -- 20 is the canonical number of mixing steps to do per Doty-Humphrey.
    for i = 1, 20 do
        sfc64_next_bits(state)
    end
end

-- Implements an interface similar to math.random.
local min_int = math.mininteger
local max_int = math.maxinteger
local ult = math.ult
local function sfc64_lua_random(state, err_level, arg1, arg2)
    local min = 1
    local max
    err_level = err_level + 1

    if arg2 ~= nil then
        arg2 = tointeger(arg2)
        if arg2 == nil then
            error("second argument can't be converted to integer", arg2)
        end
        max = arg2
    else
        if arg1 == nil then
            -- random(): return a float on the interval [0,1).
            return (sfc64_next_bits(state) >> 11) * 0x1.0p-53
        elseif arg1 == 0 then
            -- random(0): return an integer consisting of random bits.
            return sfc64_next_bits(state)
        end
    end

    arg1 = tointeger(arg1)
    if arg1 == nil then
        error("first argument can't be converted to integer", arg2)
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
    elseif min == min_int and max == max_int then
        return sfc64_next_bits(state)
    end

    local range = max - min
    if range == 0 then
        return min
    end

    -- Code for calculating an unbiased number in a range, treating it as unsigned.

    -- Count leading zeroes.
    local clz_range = range
    local zero_count = 0

    if clz_range & 0xFFFFFFFF00000000 == 0 then clz_range = clz_range << 32; zero_count = zero_count + 32 end
    if clz_range & 0xFFFF000000000000 == 0 then clz_range = clz_range << 16; zero_count = zero_count + 16 end
    if clz_range & 0xFF00000000000000 == 0 then clz_range = clz_range << 8; zero_count = zero_count + 8 end
    if clz_range & 0xF000000000000000 == 0 then clz_range = clz_range << 4; zero_count = zero_count + 4 end
    if clz_range & 0xC000000000000000 == 0 then clz_range = clz_range << 2; zero_count = zero_count + 2 end
    if clz_range & 0x8000000000000000 == 0 then zero_count = zero_count + 1 end

    local mask = -1 >> zero_count

    local result
    -- INLINED GENERATOR --
    local a, b, c, ctr = state[1], state[2], state[3], state[4]

    repeat
        result = a + b + ctr
        a = b ~ (b >> 11)
        b = c * 9
        c = result + ((c << 24) | (c >> 40))
        ctr = ctr + 1
        result = result & mask
    until result == range or ult(result, range)

    state[1], state[2], state[3], state[4] = a, b, c, ctr

    return min + candidate
end

local state_format_string = "<I2i8i8i8i8d"

local mt

local function sfc64_create()
    return setmetatable({0,0,0,0}, mt)
end

local sqrt = math.sqrt
local log = math.log
mt = {
    __tostring = function(self)
        local saved_spare_normal = self.spare_normal
        if saved_spare_normal == nil then
            -- Set it to nan. This will signal that it should be nil at load time.
            saved_spare_normal = 0/0
        end
        return string.pack(state_format_string, 2, self[1], self[2], self[3], self[4],
        saved_spare_normal)
     end,
    -- If self == other, all functions called on either state will produce the same output.
    __eq = function(self, other)
        return type(other) == "table"
            and getmetatable(other) == mt
            and self[1] == other[1]
            and self[2] == other[2]
            and self[3] == other[3]
            and self[4] == other[4]
            and self.spare_normal == other.spare_normal
    end,
    __index = {
        -- Functions with less overhead.
        next = function(self)
            -- INLINED GENERATOR --
            local b, c, ctr = self[2], self[3], self[4]
            local result = self[1] + b + ctr
            self[1] = b ~ (b >> 11)
            self[2] = c * 9
            self[3] = result + ((c << 24) | (c >> 40))
            self[4] = ctr + 1
            return (result >> 11) * 0x1.0p-53
        end,
        next_int = function(self)
            -- INLINED GENERATOR --
            local b, c, ctr = self[2], self[3], self[4]
            local result = self[1] + b + ctr
            self[1] = b ~ (b >> 11)
            self[2] = c * 9
            self[3] = result + ((c << 24) | (c >> 40))
            self[4] = ctr + 1
            return result
        end,
        -- Generate normally-distributed numbers using the Marsaglia polar algorithm.
        next_normal = function(self)
            local spare_normal = self.spare_normal
            if spare_normal then
                self.spare_normal = nil
                return spare_normal
            end
            -- INLINED GENERATOR --
            local a, b, c, ctr = self[1], self[2], self[3], self[4]
            local samples = {}
            local val, result
            repeat
                val = 0.0
                for i=1,2 do
                    result = a + b + ctr
                    a = b ~ (b >> 11)
                    b = c * 9
                    c = result + ((c << 24) | (c >> 40))
                    ctr = ctr + 1
                    result = (result >> 11) * 0x2.0p-53 - 1.0
                    val = val + result * result
                    samples[i] = result
                end
            until val < 1 and val > 0
            val = sqrt(-2 * log(val) / val)
            self.spare_normal = result * val
            self[1], self[2], self[3], self[4] = a, b, c, ctr
            return samples[1] * val
        end,
        -- The standard math.random* interface.
        random = function(self, arg1, arg2) return sfc64_lua_random(self, 2, arg1, arg2) end,
        seed = function(self, ...) return sfc64_seed(self, 2, ...) end,
    }
}

local global_generator = sfc64_create()
global_generator:seed(math.random(0),math.random(0),math.random(0))
local state_next = mt.__index.next
local state_next_normal = mt.__index.next_normal
local sfcrand = {
    new = function(...)
        local state = sfc64_create()
        sfc64_seed(state, 2, ...)
        return state
    end,
    fromstring = function(str)
        local results = {string.unpack(state_format_string, str)}
        local num_results = #results
        if num_results < 6 then
            error("invalid state", 2)
        end
        local version = results[1]
        if version == nil or version < 1 or version > 2 then
            error("invalid version",2)
        end
        if (version == 1 and num_results ~= 6) or (version == 2 and num_results ~= 7) then
            error("invalid state", 2)
        end

        -- Decode the saved spare normal. If this is a version 1 state, next_normal() wasn't
        -- available and this should always be nil.
        local saved_spare_normal = nil
        if version == 2 then
            saved_spare_normal = results[6]
            if saved_spare_normal ~= saved_spare_normal then
                -- This means the saved spare_normal is a nan, which is the encoding for nil.
                saved_spare_normal = nil
            end
        end

        return setmetatable({results[2], results[3], results[4], results[5],
            spare_normal=saved_spare_normal},mt)
    end,
    -- Convenience functions that call methods of the "global" generator.
    next = function() return state_next(global_generator) end,
    next_int = function() return sfc64_next_bits(global_generator) end,
    next_normal = function() return state_next_normal(global_generator) end,
    random = function(arg1, arg2) return global_generator:random(arg1, arg2) end,
    randomseed = function(...) return global_generator:seed(...) end,
}

setmetatable(sfcrand, {
    __call = function(self, ...) return sfcrand.new(...) end
})

return sfcrand