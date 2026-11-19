module ReviewJSONChecks

using Test, JSON3
include("../scripts/review_json.jl")
include("../scripts/local_json.jl")
using .ReviewJSON

@testset "Review JSON readers accept writer output and preserve field policy" begin
    for value in ("", "評定者😀", "quotes: \" and slash: \\",
                  String(collect(Char(0):Char(31))))
        io = IOBuffer()
        write_json(io, (; label=value))
        document = String(take!(io))
        @test json_string(document, "label") == value
    end
    document = raw"{\"before\":\"日本語\",\"l\u0061bel\":\"\uD83D\uDE00\",\"nested\":{\"ok\":true},\"empty\":null}"
    @test json_string(document, "label") == "😀"
    @test JSON3.read(required_value(document, "nested"))[:ok] === true
    @test json_value_for_key(document, "absent") === nothing
    @test required_value(document, "empty") == "null"
    @test json_value_for_key(raw"{\"key\":1,\"key\":2}", "key") == "1"
    @test_throws Exception required_value(document, "absent")
    @test_throws Exception json_string(document, "empty")
    @test_throws Exception json_string(raw"{\"label\":true}", "label")
    for malformed in ("[]", "null", "{", raw"{\"label\":\"\uZZZZ\"}")
        @test_throws Exception json_value_for_key(malformed, "label")
    end
end

end
