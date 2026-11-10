-- SHA-256 y HMAC-SHA256 en Lua 5.4 puro (FiveM no expone HMAC al servidor Lua).
-- Verificado con los vectores de FIPS 180-2 y RFC 4231 en tests/web_spec.lua.
OSSecurity.Crypto = {}

local K = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
}
local MASK = 0xffffffff

local function rotr(x, n) return ((x >> n) | (x << (32 - n))) & MASK end

local function digest(message)
    local h0, h1, h2, h3 = 0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a
    local h4, h5, h6, h7 = 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
    local length = #message
    message = message .. '\128' .. string.rep('\0', (55 - length) % 64) .. string.pack('>I8', length * 8)
    local w = {}
    for chunk = 1, #message, 64 do
        for i = 1, 16 do w[i] = string.unpack('>I4', message, chunk + (i - 1) * 4) end
        for i = 17, 64 do
            local a, b = w[i - 15], w[i - 2]
            local s0 = rotr(a, 7) ~ rotr(a, 18) ~ (a >> 3)
            local s1 = rotr(b, 17) ~ rotr(b, 19) ~ (b >> 10)
            w[i] = (w[i - 16] + s0 + w[i - 7] + s1) & MASK
        end
        local a, b, c, d, e, f, g, h = h0, h1, h2, h3, h4, h5, h6, h7
        for i = 1, 64 do
            local S1 = rotr(e, 6) ~ rotr(e, 11) ~ rotr(e, 25)
            local ch = (e & f) ~ (~e & g)
            local t1 = (h + S1 + ch + K[i] + w[i]) & MASK
            local S0 = rotr(a, 2) ~ rotr(a, 13) ~ rotr(a, 22)
            local maj = (a & b) ~ (a & c) ~ (b & c)
            local t2 = (S0 + maj) & MASK
            h, g, f, e, d, c, b, a = g, f, e, (d + t1) & MASK, c, b, a, (t1 + t2) & MASK
        end
        h0, h1, h2, h3 = (h0 + a) & MASK, (h1 + b) & MASK, (h2 + c) & MASK, (h3 + d) & MASK
        h4, h5, h6, h7 = (h4 + e) & MASK, (h5 + f) & MASK, (h6 + g) & MASK, (h7 + h) & MASK
    end
    return string.pack('>I4I4I4I4I4I4I4I4', h0, h1, h2, h3, h4, h5, h6, h7)
end

local function hex(bytes) return (bytes:gsub('.', function(c) return ('%02x'):format(c:byte()) end)) end

function OSSecurity.Crypto.sha256(message) return hex(digest(message)) end

function OSSecurity.Crypto.hmac(key, message)
    if #key > 64 then key = digest(key) end
    key = key .. string.rep('\0', 64 - #key)
    local inner = key:gsub('.', function(c) return string.char(c:byte() ~ 0x36) end)
    local outer = key:gsub('.', function(c) return string.char(c:byte() ~ 0x5c) end)
    return hex(digest(outer .. digest(inner .. message)))
end

-- Comparacion sin salida temprana (firmas recibidas).
function OSSecurity.Crypto.equal(a, b)
    if type(a) ~= 'string' or type(b) ~= 'string' or #a ~= #b then return false end
    local diff = 0
    for i = 1, #a do diff = diff | (a:byte(i) ~ b:byte(i)) end
    return diff == 0
end
