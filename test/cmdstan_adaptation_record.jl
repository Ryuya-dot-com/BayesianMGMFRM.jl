module CmdStanAdaptationRecordChecks
using Test, Random, LinearAlgebra, JSON3, BayesianMGMFRM
include("../scripts/mgmfrm_adaptation_record.jl")
const A = MGMFRMAdaptationRecord
const B = BayesianMGMFRM

function synthetic_csv(path,warmup;stepsize=.12345678901234567)
    open(path,"w") do io
        println(io,"# Synthetic parser fixture; not a CmdStan fit")
        println(io,"lp__,accept_stat__,stepsize__,treedepth__,n_leapfrog__,divergent__,energy__,beta.1,beta.2")
        for i in 1:warmup
            println(io,"-5,0.8,$(i/10),2,3,0,6,0.1,0.2")
        end
        # Deliberately rounded comments must NOT be used as the exact metric.
        println(io,"# Adaptation terminated\n# Step size = 0.123457")
        println(io,"# Diagonal elements of inverse mass matrix:\n# 1.23457, 2.34568")
        for i in 1:3
            println(io,"-4,0.9,$stepsize,2,3,0,5,0.2,0.3")
        end
    end
end

@testset "CmdStan adaptation parser and unavailable history without fits" begin
    mktempdir() do dir
        csv,metric_path = joinpath.(dir,("chain.csv","metric.json"))
        for warmup in (0,2), metric in ("diag_e","dense_e","unit_e")
            synthetic_csv(csv,warmup)
            inverse = metric=="dense_e" ? [[2.,.3],[.3,3.]] :
                metric=="unit_e" ? [1.,1.] : [1.2345678901234567,2.3456789012345678]
            native = (;stepsize=.12345678901234567,metric_type=metric,inv_metric=inverse)
            B._write_json_record(metric_path,native)
            record = A.cmdstan_record(csv,metric_path,2,1,3,warmup,metric)
            @test length(record.rows)==warmup+3
            @test getproperty.(record.rows,:phase)==[fill(:warmup,warmup);fill(:retained,3)]
            @test all(r->ismissing(r.metric_used)&&ismissing(r.metric_after),record.rows[1:warmup])
            @test all(r->r.metric_used==r.metric_after==1,record.rows[warmup+1:end])
            @test all(r->ismissing(r.log_density)&&ismissing(r.hamiltonian_energy_error),record.rows)
            @test record.metric_history===:not_recorded
            @test record.retained_kernel.adapted==(warmup>0)
            @test record.retained_kernel.step_size==native.stepsize
            expected = warmup==0 ? (metric=="dense_e" ? Matrix{Float64}(I,2,2) : ones(2)) :
                metric=="dense_e" ? [2. .3;.3 3.] : inverse
            @test record.metrics[1].inverse_mass_matrix==expected
            @test record.stan_parameter_names==["beta.1","beta.2"]
        end
        synthetic_csv(csv,2)
        for native in ((;stepsize=.2,metric_type="diag_e",inv_metric=[1.,1.]),
                (;stepsize=.12345678901234567,metric_type="unit_e",inv_metric=[1.,1.]),
                (;stepsize=.12345678901234567,metric_type="diag_e",inv_metric=[1.]),
                (;stepsize=.12345678901234567,metric_type="diag_e",inv_metric=[1.,-1.]))
            B._write_json_record(metric_path,native)
            @test_throws ArgumentError A.cmdstan_record(csv,metric_path,2,1,3,2,"diag_e")
        end
        native=(;stepsize=.12345678901234567,metric_type="dense_e",
            inv_metric=[[2.,.3],[nextfloat(.3),3.]])
        B._write_json_record(metric_path,native)
        rounded=A.cmdstan_record(csv,metric_path,2,1,3,2,"dense_e")
        @test rounded.metrics[1].inverse_mass_matrix==[2. .3;nextfloat(.3) 3.]
        @test rounded.metrics[1].symmetry_error==nextfloat(.3)-.3
        for inverse in ([[1.,2.]],[[1.,2.],[0.,1.]],[[1.,.2],[.1,1.]],[[1.,2.],[2.,1.]])
            B._write_json_record(metric_path,(;stepsize=.12345678901234567,
                metric_type="dense_e",inv_metric=inverse))
            @test_throws ArgumentError A.cmdstan_record(csv,metric_path,2,1,3,2,"dense_e")
        end
        B._write_json_record(metric_path,(;stepsize=.12345678901234567,
            metric_type="diag_e",inv_metric=[1.,1.]))
        source=read(csv,String)
        for changed in (replace(source,"# Adaptation terminated"=>""),
                replace(source,"# Adaptation terminated"=>"# Adaptation terminated\n# Adaptation terminated"),
                replace(source,"beta.1,beta.2"=>"beta.2,beta.1"))
            write(csv,changed)
            @test_throws ArgumentError A.cmdstan_record(csv,metric_path,2,1,3,2,"diag_e")
        end
        write(csv,source)
        @test_throws B.CmdStanError A.cmdstan_record(csv,metric_path,2,1,4,2,"diag_e")
        @test_throws B.CmdStanError A.cmdstan_record(csv,metric_path,2,1,3,1,"diag_e")
    end
end

@testset "CmdStan observer preserves failed output before temporary cleanup" begin
    if Sys.iswindows()
        @test_skip false # This subprocess fixture uses the POSIX shell.
    else
    mktempdir() do dir
        executable=joinpath(dir,"fake-cmdstan")
        # A deliberately failing subprocess writes partial files. This tests
        # lifecycle/retention only and is never counted as a native fit.
        write(executable,raw"""#!/bin/sh
output_section=0
for arg in "$@"; do
    case "$arg" in
        output) output_section=1 ;;
        file=*) if [ "$output_section" = 1 ]; then out="${arg#file=}"; fi ;;
    esac
done
printf 'partial CSV\n' > "$out"
printf '{' > "${out%.csv}_metric.json"
exit 1
""")
        chmod(executable,0o700)
        output=joinpath(dir,"attempt");mkdir(output)
        record=Dict{Symbol,Any}(:chains=>Dict{Symbol,Any}[],:status=>:started)
        observer=event->A.observe_cmdstan!(record,output,event)
        function run(observer)
            B._cmdstan_sample_chains(executable,(;x=[1]),zeros(2),MersenneTwister(924302),
                x->-sum(abs2,x),(args...)->error("parser must not run after failure");
                expected_sha256=A.digest(executable),ndraws=3,warmup=2,chains=1,
                step_size=.03,target_accept=.8,max_depth=3,metric="diag_e",init_jitter=.1,
                progress=false,record_warmup=true,_sampling_observer=observer)
        end
        @test_throws B.CmdStanError run(observer)
        @test read(joinpath(output,"chain-1.csv"),String)=="partial CSV\n"
        @test read(joinpath(output,"chain-1_metric.json"),String)=="{"
        @test only(record[:chains])[:completed]===false
        @test only(record[:chains])[:csv].sha256==A.digest(joinpath(output,"chain-1.csv"))
        @test !isfile(only(record[:chains])[:command][findfirst(startswith("init="),only(record[:chains])[:command])][6:end])
        @test "save_metric=1" in only(record[:chains])[:command]
        @test JSON3.read(read(joinpath(output,"init-1.json"),String)).beta==only(record[:chains])[:initial_raw]
        @test_throws ArgumentError run(:invalid)
    end
    end
end
end
