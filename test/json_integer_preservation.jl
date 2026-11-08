module JSONIntegerPreservationChecks
using Test, BayesianMGMFRM
const B=BayesianMGMFRM

# Copying a token into new storage must not query source alias identities.
struct TokenBytes{T} <: AbstractVector{UInt8}
    bytes::T
end
Base.size(x::TokenBytes)=size(x.bytes)
Base.IndexStyle(::Type{<:TokenBytes})=IndexLinear()
Base.getindex(x::TokenBytes,i::Int)=x.bytes[i]
Base.dataids(::TokenBytes)=error("unnecessary source alias query")

function checks()
    @testset "JSON integer identities and mixed arrays" begin
        for token in ("18446744073709551615", "-0.0", "true", "null", "\"日本語😀\"", "{\"x\":[1,2,3]}")
            bytes=TokenBytes(codeunits("xx"*token*"yy"))
            raw=B.JSON3.RawValue(bytes,3,ncodeunits(token))
            got=B.JSON3.StructTypes.construct(B._ExactJSONValue,raw).value
            @test isequal(got,B.JSON3.read(token,B._ExactJSONValue).value)
        end
        mktempdir() do dir
            path=joinpath(dir,"values.json")
            values=Any[typemin(Int64),typemax(Int64),UInt64(typemax(Int64))+1,
                UInt64(0xc9c209ecb5532375),typemax(UInt64),big(typemax(UInt64))+1,
                big(typemin(Int64))-1,9_007_199_254_740_993]
            for value in values
                payload=Dict("id"=>value,"mixed"=>Any[.5,value,-0.0],
                    "nested"=>Dict("ids"=>Any[value,value]),"text"=>string(value))
                B._write_json_record(path,payload)
                got=B._read_json_dict(path,"integer regression")
                @test got["id"] isa Integer && got["id"]==value
                @test got["mixed"][2] isa Integer && got["mixed"][2]==value
                @test got["mixed"][1]===.5 && isequal(got["mixed"][3],-0.0)
                @test all(x->x isa Integer && x==value,got["nested"]["ids"])
                @test got["text"]==string(value)
                @test B._cache_stable_string(B._json_hash_value(payload))==
                    B._cache_stable_string(B._json_hash_value(got))
            end
            write(path,"""{"text":"escaped \\\"18446744073709551615\\\"","日本語":true,"null":null,"empty":[],"object":{},"floats":[1.0,1e0,-0.0,-0e0,1.25e-4],"negative":-12}""")
            got=B._read_json_dict(path,"literal regression")
            @test got["text"]=="escaped \"18446744073709551615\""
            @test got["日本語"]===true && got["null"]===nothing
            @test isempty(got["empty"]) && isempty(got["object"])
            @test isequal(got["floats"],Any[1.0,1.0,-0.0,-0.0,.000125])
            @test got["negative"]===-12
            for invalid in ("{", "{\"x\":}", "{\"x\":tru}", "{\"x\":NaN}")
                write(path,invalid)
                @test_throws Exception B._read_json_dict(path,"invalid JSON")
            end
            write(path,"[1,2]")
            @test_throws ArgumentError B._read_json_dict(path,"non-object")
        end
    end
end
end
