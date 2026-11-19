module ReviewJSON

import JSON3

export json_value_for_key, required_value, json_string

function json_value_for_key(text::AbstractString, key::AbstractString)
    object = JSON3.read(text)
    object isa JSON3.Object || error("expected JSON object")
    # Historical review readers select the first occurrence of a duplicate key.
    for (name, value) in pairs(object)
        String(name) == key && return JSON3.write(value)
    end
    return nothing
end

function required_value(text::AbstractString, key::AbstractString)
    value = json_value_for_key(text, key)
    value === nothing && error("JSON field `$key` not found")
    return value
end

function json_string(text::AbstractString, key::AbstractString)
    return JSON3.read(required_value(text, key), String)
end

end
