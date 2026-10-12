"""Opt-in Stan data/build bridge; include four_facet_shared_target.jl first."""
module FourFacetSharedStan
import ..FourFacetSharedTarget as F
import BayesianMGMFRM as B
using SHA
export stan_data, compile_stan

const STAN_SOURCE = joinpath(@__DIR__, "stan", "four_facet_shared_task.stan")

function stan_data(target::F.SharedTaskTarget)
    F.target_record(target) # Check the owned input and derived layout before export.
    P,T,R,C,K = target.sizes
    data = target.input_spec.data
    return (; P,T,R,C,K,N=data.n, person=copy(data.person), task=copy(target.task),
        rater=copy(data.rater), criterion=copy(data.item), response=copy(data.optional[:response_id]),
        y=copy(data.category), criterion_dim=copy(target.dimension),
        prior_scale=collect(values(target.prior)))
end

function compile_stan(directory)
    check = B.cmdstan_backend_check(;require_ready=true,include_paths=true)
    all(isempty(get(ENV,name,"")) for name in ("MAKEFILES","MAKEFLAGS","GNUMAKEFLAGS")) ||
        throw(ArgumentError("inherited make options are not supported"))
    make = B._cmdstan_configured_program("MAKE",("make","gmake"))
    make === nothing && throw(ArgumentError("make is unavailable"))
    ispath(directory) && throw(ArgumentError("select a new empty compile directory"))
    mkdir(directory)
    stem = abspath(joinpath(directory,"four_facet_shared_task"))
    cp(STAN_SOURCE,stem*".stan")
    # One compiler job; keep compiler-specific headers out of the shared CmdStan tree.
    B._cmdstan_run(Cmd(`$make -j1 -f makefile PRECOMPILED_HEADERS=false $stem`;
        dir=check.cmdstan_root),:model_compile)
    return (;path=stem,sha256=B._cmdstan_executable_sha256(stem,:model_compile),
        source_sha256=bytes2hex(sha256(read(STAN_SOURCE))),version=check.cmdstan_version)
end
end
