function escape_json_string(value::AbstractString)
    io = IOBuffer()
    for char in value
        if char == '"'
            print(io, "\\\"")
        elseif char == '\\'
            print(io, "\\\\")
        elseif char == '\n'
            print(io, "\\n")
        elseif char == '\r'
            print(io, "\\r")
        elseif char == '\t'
            print(io, "\\t")
        elseif char < ' '
            print(io, "\\u", lpad(string(Int(char), base = 16), 4, '0'))
        else
            print(io, char)
        end
    end
    return String(take!(io))
end

function normalize_error_message(message::AbstractString)
    canonical = replace(String(message), "\r\n" => "\n", '\r' => '\n')
    lines = split(canonical, '\n'; keepempty = true)
    filter!(line -> !occursin(r"^\s*@\s+.*\.jl:\d+\s*$", line), lines)
    return join(lines, '\n')
end

portable_error_message(err) = normalize_error_message(sprint(showerror, err))

function write_indent(io, indent)
    print(io, repeat(" ", indent))
end

function write_json(io, value, indent::Int = 0)
    if value === nothing || ismissing(value)
        print(io, "null")
    elseif value isa Bool
        print(io, value ? "true" : "false")
    elseif value isa Integer
        print(io, value)
    elseif value isa AbstractFloat
        print(io, isfinite(value) ? string(value) : "null")
    elseif value isa Symbol
        print(io, '"', escape_json_string(String(value)), '"')
    elseif value isa AbstractString
        print(io, '"', escape_json_string(value), '"')
    elseif value isa NamedTuple
        items = collect(pairs(value))
        print(io, "{")
        if !isempty(items)
            println(io)
            for (index, pair) in enumerate(items)
                write_indent(io, indent + 2)
                print(io, '"', escape_json_string(String(pair.first)), "\": ")
                write_json(io, pair.second, indent + 2)
                index < length(items) && print(io, ",")
                println(io)
            end
            write_indent(io, indent)
        end
        print(io, "}")
    elseif value isa AbstractDict
        dict_keys = sort(collect(Base.keys(value)); by = string)
        print(io, "{")
        if !isempty(dict_keys)
            println(io)
            for (index, key) in enumerate(dict_keys)
                write_indent(io, indent + 2)
                print(io, '"', escape_json_string(String(key)), "\": ")
                write_json(io, value[key], indent + 2)
                index < length(dict_keys) && print(io, ",")
                println(io)
            end
            write_indent(io, indent)
        end
        print(io, "}")
    elseif value isa AbstractArray || value isa Tuple
        values = collect(value)
        print(io, "[")
        if !isempty(values)
            println(io)
            for index in eachindex(values)
                write_indent(io, indent + 2)
                write_json(io, values[index], indent + 2)
                index < length(values) && print(io, ",")
                println(io)
            end
            write_indent(io, indent)
        end
        print(io, "]")
    else
        error("cannot encode value of type $(typeof(value)) as JSON")
    end
    return nothing
end

function write_canonical_json(io, value)
    if value === nothing || ismissing(value)
        print(io, "null")
    elseif value isa Bool
        print(io, value ? "true" : "false")
    elseif value isa Integer
        print(io, value)
    elseif value isa AbstractFloat
        if !isfinite(value)
            print(io, "null")
        elseif isinteger(value)
            print(io, trunc(BigInt, value))
        else
            print(io, value == 0 ? "0" : string(value))
        end
    elseif value isa Symbol
        print(io, '"', escape_json_string(String(value)), '"')
    elseif value isa AbstractString
        print(io, '"', escape_json_string(value), '"')
    elseif value isa NamedTuple || value isa AbstractDict
        items = sort!(collect(pairs(value)); by = pair -> String(pair.first))
        print(io, "{")
        for (index, pair) in enumerate(items)
            index > 1 && print(io, ",")
            print(io, '"', escape_json_string(String(pair.first)), "\":")
            write_canonical_json(io, pair.second)
        end
        print(io, "}")
    elseif value isa AbstractArray || value isa Tuple
        print(io, "[")
        for (index, element) in enumerate(value)
            index > 1 && print(io, ",")
            write_canonical_json(io, element)
        end
        print(io, "]")
    else
        error("cannot canonically encode value of type $(typeof(value)) as JSON")
    end
    return nothing
end

function write_artifact(path::AbstractString, artifact)
    mkpath(dirname(path))
    open(path, "w") do io
        write_json(io, artifact)
        println(io)
    end
    return path
end
