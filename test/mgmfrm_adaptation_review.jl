module MGMFRMAdaptationReviewChecks
using Test, LinearAlgebra, BayesianMGMFRM
include("../scripts/mgmfrm_adaptation_review.jl")
const R = MGMFRMAdaptationReview
const A = R.A
const B = BayesianMGMFRM
include("fixtures/reporting_fit.jl")

# Entirely deterministic reporting fixtures; no posterior simulation or NUTS.
function fixture(dir; backend=:advancedhmc, metric=:diagonal, warmup=3, coordinates=:raw)
    old = reporting_fit(:mgmfrm;backend,warmup,chains=2)
    controls = merge(old.sampler_controls,(;metric,sampling_coordinates=coordinates))
    stats = backend===:advancedhmc ? old.sampler_stats : NamedTuple[
        merge(s,(;is_accept=missing,hamiltonian_energy_error=missing,
            max_hamiltonian_energy_error=missing,nom_step_size=s.step_size,stan_lp=-44.))
        for s in old.sampler_stats]
    fit = B.MGMFRMFit((k===:sampler_controls ? controls : k===:sampler_stats ? stats : getfield(old,k)
        for k in fieldnames(B.MGMFRMFit))...)
    base = B._mgmfrm_guarded_local_fit_logdensity(fit.design;prior=fit.prior)
    p = size(fit.draws,2)
    B.save_fit_cache(joinpath(dir,"fit.jls"),fit)
    reference(name) = (;path=name,sha256=A.digest(joinpath(dir,name)))
    record = Dict{Symbol,Any}(:schema=>"bayesianmgmfrm.adaptation_record.v1",:status=>:complete,
        :backend=>backend,:coordinates=>A.coordinate_record(base,coordinates),
        :controls=>controls,:model=>B.model_manifest(fit.design),
        :data_signature=>string(fit.design.spec.validation.data_signature),
        :prior=>B._prior_cache_record(fit.prior),:fit_cache=>reference("fit.jls"),
        :environment=>(;purpose="synthetic reporting fixture, never an actual fit",recorder_sha256="historical"),
        :unavailable=>backend===:cmdstan ? [:warmup_metric_history,:energy_errors] : [:warmup_positions],
        :chains=>Dict{Symbol,Any}[])
    for c in 1:2
        raw = [.01sin(j) for j in 1:p]
        rows = NamedTuple[merge(B._advancedhmc_stat_row((;is_adapt=true,log_density=i==2 ? NaN : -10.,
            numerical_error=i==1,tree_depth=i==3 ? 2 : 1,step_size=i/10,
            hamiltonian_energy_error=0.,acceptance_rate=.8),c,i),
            (;phase=:warmup,metric_used=i<=2 ? 1 : 2,metric_after=i<2 ? 1 : 2)) for i in 1:warmup]
        changes = warmup>0 && metric!==:unit
        matrix = metric===:dense ? Matrix{Float64}(I,p,p) : ones(p)
        metrics = [(;after_iteration=0,inverse_mass_matrix=matrix)]
        changes && push!(metrics,(;after_iteration=2,inverse_mass_matrix=2matrix))
        !changes && (rows=NamedTuple[merge(r,(;metric_used=1,metric_after=1)) for r in rows])
        id = length(metrics)
        append!(rows,[merge(s,(;iteration=s.iteration+warmup,phase=:retained,metric_used=id,metric_after=id))
            for s in stats if s.chain==c])
        chain = Dict{Symbol,Any}(:chain=>c,:completed=>true,:initial_raw=>raw,
            :initial_sampling=>coordinates===:raw ? raw : B._mgmfrm_location_from_raw(B._MGMFRMLocationLogDensity(base),raw),
            :rows=>rows,:metrics=>metrics,:retained_kernel=>(;metric_id=id,step_size=.1,adapted=warmup>0))
        if backend===:cmdstan
            csv,met = joinpath(dir,"chain-$c.csv"),joinpath(dir,"chain-$(c)_metric.json")
            open(csv,"w") do io
                println(io,"# Synthetic format fixture; not a native run")
                println(io,join(vcat(["lp__","accept_stat__","stepsize__","treedepth__","n_leapfrog__","divergent__","energy__"],
                    ["beta.$j" for j in 1:p]),','))
                for r in rows[1:warmup]
                    println(io,join(vcat([r.log_density,r.acceptance_rate,r.step_size,r.tree_depth,r.n_steps,Int(r.numerical_error),r.hamiltonian_energy],raw),','))
                end
                println(io,"# Adaptation terminated")
                for i in findall(==(c),fit.chain_ids)
                    s = stats[i]
                    println(io,join(vcat([s.stan_lp,s.acceptance_rate,s.step_size,s.tree_depth,s.n_steps,Int(s.numerical_error),s.hamiltonian_energy],fit.draws[i,:]),','))
                end
            end
            native_metric = B._cmdstan_metric(metric)
            B._write_json_record(met,(;metric_type=native_metric,stepsize=.1,inv_metric=matrix))
            B._write_json_record(joinpath(dir,"init-$c.json"),(;beta=raw))
            merge!(chain,Dict(pairs(A.cmdstan_record(csv,met,p,c,4,warmup,native_metric))))
            merge!(chain,Dict(:csv=>reference(basename(csv)),:metric_json=>reference(basename(met)),
                :initial_file=>reference("init-$c.json"),:warmup=>warmup,:ndraws=>4,:metric=>native_metric,
                :seed=>c,:executable_sha256=>"synthetic"))
        end
        push!(record[:chains],chain)
    end
    if backend===:cmdstan
        B._write_json_record(joinpath(dir,"data.json"),B._cmdstan_mgmfrm_data(base))
        record[:cmdstan_data]=reference("data.json")
        controls=merge(controls,(;rng=(;chain_seeds=(1,2)),cmdstan_executable_sha256="synthetic"))
        fit=B.MGMFRMFit((k===:sampler_controls ? controls : getfield(fit,k) for k in fieldnames(B.MGMFRMFit))...)
        B.save_fit_cache(joinpath(dir,"native-fit.jls"),fit)
        record[:controls]=controls;record[:fit_cache]=reference("native-fit.jls")
    end
    A.write_record(dir,record)
    return R.readjson(joinpath(dir,"adaptation.json"))
end

@testset "Adaptation review without fits" begin
    telemetry=R.values_summary([Dict("x"=>v) for v in (nothing,"NaN","Inf","-Inf",2.)],"x")
    @test (telemetry.available,telemetry.missing,telemetry.nonfinite,telemetry.mean)==(4,1,3,2.)
    @test_throws ArgumentError R.values_summary([Dict("x"=>"invalid")],"x")
    for backend in (:advancedhmc,:cmdstan), metric in (:unit,:diagonal,:dense), warmup in (0,3)
        coordinates = backend===:advancedhmc ? :orthogonal_person_mean_item_offset : :raw
        mktempdir() do dir
            fixture(dir;backend,metric,warmup,coordinates)
            before = A.digest(joinpath(dir,"adaptation.json"))
            result = R.review(dir)
            @test result.integrity=="checked"
            @test result.coordinates["sampling"]==string(coordinates)
            @test result.environment["recorder_sha256"]=="historical"
            @test result.window.tail_iterations==(warmup==0 ? 0 : 1)
            for c in result.chains
                @test c.warmup.iterations==warmup
                @test c.warmup.numerical_errors==(warmup==0 ? 0 : 1)
                @test c.warmup.density.nonfinite==(warmup==0 ? 0 : 1)
                @test c.late_warmup.first_iteration==(warmup==0 ? nothing : 3)
                @test c.late_warmup.max_depth_hits==(warmup==0 ? 0 : 1)
                @test c.retained.step_size.mean==.1
                @test c.metric.updates== (backend===:cmdstan ? nothing : warmup==0 || metric===:unit ? 0 : 1)
                @test c.retained.energy_error.missing==(backend===:cmdstan ? 4 : 0)
            end
            @test A.digest(joinpath(dir,"adaptation.json"))==before
            @test R.review(dir;tail_fraction=1).chains[1].late_warmup.iterations==warmup
        end
    end
    mktempdir() do dir
        record = fixture(dir)
        mutations = [r->r["status"]="failed", r->r["status"]="started",
            r->r["fit_cache"]["sha256"]="wrong", r->r["prior"]["person_sd"]=99.,
            r->reverse!(r["coordinates"]["sampling_names"]), r->reverse!(r["chains"]),
            r->r["chains"][1]["rows"][1]["iteration"]=2,
            r->r["chains"][1]["rows"][2]["metric_used"]=2,
            r->r["chains"][1]["metrics"][2]["after_iteration"]=3,
            r->r["chains"][1]["metrics"][2]["inverse_mass_matrix"][1]=-1.,
            r->r["chains"][1]["rows"][4]["acceptance_rate"]=.99,
            r->r["chains"][1]["rows"][1]["numerical_error"]=false,
            r->r["chains"][1]["retained_kernel"]["step_size"]=.2,
            r->r["chains"][1]["initial_sampling"][1]=99.]
        for mutate in mutations
            changed=deepcopy(record);mutate(changed);A.write_record(dir,changed)
            @test_throws ArgumentError R.review(dir)
        end
        A.write_record(dir,record)
        for fraction in (0.,-1.,NaN,Inf,1.1)
            @test_throws ArgumentError R.review(dir;tail_fraction=fraction)
        end
    end
    mktempdir() do dir
        record = fixture(dir;backend=:cmdstan)
        for mutate in [r->r["chains"][1]["csv"]["sha256"]="wrong",
                r->r["chains"][1]["rows"][1]["metric_used"]=1,
                r->r["chains"][1]["seed"]=99,
                r->r["cmdstan_data"]["sha256"]="wrong"]
            changed=deepcopy(record);mutate(changed);A.write_record(dir,changed)
            @test_throws ArgumentError R.review(dir)
        end
        # A changed CSV with an updated hash still cannot be paired with old draws.
        csv=joinpath(dir,record["chains"][1]["csv"]["path"])
        lines=readlines(csv)
        i=findfirst(==("# Adaptation terminated"),lines)+1
        cells=split(lines[i],',');cells[8]=string(parse(Float64,cells[8])+.1)
        lines[i]=join(cells,',');write(csv,join(lines,'\n')*"\n")
        record["chains"][1]["csv"]["sha256"]=A.digest(csv)
        A.write_record(dir,record)
        @test_throws ArgumentError R.review(dir)
    end
end
end
