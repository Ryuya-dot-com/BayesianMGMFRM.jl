# Separate process: saved primitive arithmetic plus all native evaluation configurations.
using BayesianMGMFRM, Test, Serialization
include("../examples/saved_recovery_replications.jl")
directory=only(ARGS)
@testset "Fresh-process recovery replication replay" begin
    files=vcat(["replay.jls"],["native-replay-$i.jls" for i in 1:11])
    @test all(isfile(joinpath(directory,f)) for f in files)
    for file in files
        input=deserialize(joinpath(directory,file))
        actual=saved_recovery_replications(input.paths;input.args...)
        @test isequal(actual,input.expected)
        @test BayesianMGMFRM._prediction_check_seal(actual,"bayesianmgmfrm.recovery_replications.v1")===nothing
    end
end
