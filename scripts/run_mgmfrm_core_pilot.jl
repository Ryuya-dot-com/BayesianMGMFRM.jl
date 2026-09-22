module MGMFRMCorePilot

# One declared core candidate. Loading this module never fits a model.
import BayesianMGMFRM as B
using JSON3, Random, SHA, Statistics, LinearAlgebra
include(joinpath(@__DIR__, "mfrm_validation_preparation.jl"))
const V = MFRMValidationPreparation
const REPO = dirname(@__DIR__)
const Q = Bool[1 0; 1 0; 0 1; 0 1; 0 1]
const PERSONS = sort(["P$i" for i in 1:50])
const PROBS = (0.025, 0.05, 0.5, 0.95, 0.975)
const CRITERIA = (;chains=4, rhat=1.01, ess=400., ebfmi=0.3, allow_treedepth_hits=false)
const CONTROLS = (;chains=4, warmup=1000, ndraws=1000, step_size=0.03,
    target_accept=0.9, max_depth=12, metric=:diagonal, ad_backend=:ForwardDiff,
    init_jitter=0.1, split_chains=true, rhat_threshold=1.01, ess_threshold=400., progress=false)
digest(path) = bytes2hex(sha256(read(path)))
readjson(path) = JSON3.read(read(path, String))
function writejson(path, value)
    ispath(path) && error("Existing evidence must not be overwritten: $path")
    B._write_json_record(path, value)
end

prior() = B.Experimental.GeneralizedPrior(;person_sd=1., rater_sd=1., item_sd=1.,
    log_discrimination_sd=.5, log_consistency_sd=.5, step_sd=1.)

function observation_data(observed)
    observed.candidate_id == "independent_2d_raw_primary_01" || error("Wrong candidate")
    observed.category_levels == collect(1:4) || error("Wrong category declaration")
    rows = observed.observations
    data = B.FacetData((;person=String[r.person for r in rows], item=String[r.item for r in rows],
        rater=String[r.rater for r in rows], score=Int[r.score for r in rows]);
        person=:person, item=:item, rater=:rater, score=:score, category_levels=1:4)
    data.n == 1250 && data.person_levels == PERSONS && data.item_levels == ["I$i" for i in 1:5] &&
        data.rater_levels == ["R$r" for r in 1:5] || error("Wrong candidate geometry or label order")
    length(Set(zip(data.person,data.item,data.rater))) == 1250 || error("Repeated or missing design cells")
    return data
end

function specification(observed; require_all_categories::Bool=true)
    data = observation_data(observed)
    !require_all_categories || Set(data.score)==Set(1:4) ||
        error("This pilot requires the declared all-category prototype; preserve and reject other inputs")
    return B.mfrm_spec(data;family=:mgmfrm, dimensions=2, thresholds=:partial_credit,
        discrimination=:none, q_matrix=Q)
end

target(spec) = B._mgmfrm_guarded_local_fit_logdensity(spec;prior=B._source_fixture_prior(prior()))

function focal_draws(design, raw; batch_size=256)
    size(raw,2) == 128 || error("Wrong raw dimension")
    size(raw,1)>0 || throw(ArgumentError("At least one draw is required"))
    batch_size isa Integer && !(batch_size isa Bool) && batch_size>0 ||
        throw(ArgumentError("batch_size must be a positive integer"))
    design.spec.q_matrix == Q && design.spec.data.person_levels == PERSONS || error("Wrong coordinate labels")
    names, roles, kinds, columns = String[], Symbol[], Symbol[], Vector{Float64}[]
    function add(name, values;role=:primary,kind=:parameter)
        push!(names,name); push!(columns,Float64.(values)); push!(roles,role); push!(kinds,kind)
    end
    severity=hcat(raw[:,101:104],-sum(raw[:,101:104];dims=2))
    ell=hcat(raw[:,115:118],-sum(raw[:,115:118];dims=2))
    for i in 1:5
        add("b[I$i]",raw[:,104+i])
        add("a[I$i]",exp.(raw[:,109+i]))
        add("severity[R$i]",severity[:,i])
        add("gamma[R$i]",exp.(ell[:,i]))
        free=raw[:,(117+2i):(118+2i)]
        for (h,values) in enumerate((free[:,1],free[:,2],-vec(sum(free;dims=2))))
            add("step[I$i,h=$h]",values)
        end
    end
    for a in 1:4, b in a+1:5
        add("severity[R$a]-severity[R$b]",severity[:,a]-severity[:,b])
        add("log_gamma[R$a]-log_gamma[R$b]",ell[:,a]-ell[:,b])
        if findfirst(Q[a,:]) == findfirst(Q[b,:])
            add("b[I$a]-b[I$b]",raw[:,104+a]-raw[:,104+b])
        end
    end
    p1=findfirst(==("P1"),PERSONS);p2=findfirst(==("P2"),PERSONS)
    for d in 1:2
        add("theta[P1,D$d]-theta[P2,D$d]",raw[:,2(p1-1)+d]-raw[:,2(p2-1)+d];role=:secondary)
    end
    # Bound the temporary draws-by-observations-by-categories array; retain every draw.
    panel_means=Matrix{Float64}(undef,size(raw,1),8)
    dimension_rows=[findall(n->Q[design.spec.data.item[n],d],1:design.spec.data.n) for d in 1:2]
    for first_draw in 1:batch_size:size(raw,1)
        selected=first_draw:min(first_draw+batch_size-1,size(raw,1))
        direct=reduce(vcat,[permutedims(B._mgmfrm_source_constrained_params_from_unconstrained(design,vec(row)))
            for row in eachrow(@view raw[selected,:])])
        probabilities=B._mgmfrm_predictive_probabilities_direct(design,direct)
        for d in 1:2, k in 1:4
            panel_means[selected,4(d-1)+k]=vec(mean(probabilities[:,dimension_rows[d],k];dims=2))
        end
    end
    for d in 1:2, k in 1:4
        add("mean_Pr[Y=$k,D$d,existing_panel]",panel_means[:,4(d-1)+k];kind=:probability)
    end
    return (;names,roles,kinds,draws=hcat(columns...))
end

finite(x) = x isa Real && isfinite(x)
function precision_rows(focal;chains=4)
    mcse=B.posterior_mcse(focal.draws;chains,parameter_names=focal.names,probabilities=PROBS)
    return map(eachindex(focal.names)) do i
        values=focal.draws[:,i]; m=mcse[i]; sd=std(values)
        qs=Dict(r.probability=>r for r in m.quantiles)
        available=m.mcse_status===:available && finite(m.mean_mcse) && finite(sd) && sd>0
        mean_ok=available && (focal.kinds[i]===:probability ? m.mean_mcse<=.01 : m.mean_mcse/sd<=.05)
        endpoint_ok=all(((.05,.95),(.025,.975))) do (lo,hi)
            width=qs[hi].estimate-qs[lo].estimate
            finite(width) && width>0 && all(p->finite(qs[p].mcse) && qs[p].mcse/width<=.05,(lo,hi))
        end
        qualified=mean_ok && (focal.kinds[i]===:probability || endpoint_ok)
        (;parameter=focal.names[i],role=focal.roles[i],kind=focal.kinds[i],estimate=mean(values),
            posterior_sd=sd,mcse=m,mean_precision_passed=mean_ok,endpoint_precision_passed=endpoint_ok,
            local_precision_passed=qualified)
    end
end

function qualify(fit, focal)
    extra=B._candidate_mcmc_diagnostic_rows(focal.draws,focal.names,4;
        split_chains=true,rhat_threshold=1.01,ess_threshold=400.)
    surface=fit.diagnostic_surface
    complete=length(fit.sampler_stats)==4000 && all(fit.sampler_stats) do r
        r.numerical_error isa Bool && r.n_steps isa Integer && r.n_steps>0 &&
            r.tree_depth isa Integer && r.tree_depth>0 && finite(r.hamiltonian_energy)
    end
    return V.qualify_diagnostics((;raw=surface.parameter_rows,model=surface.direct_parameter_rows,focal=extra),
        surface.sampler_rows;criteria=CRITERIA,telemetry_complete=complete)
end

function checked_contract(path)
    c=readjson(path)
    planned=String.(c.planned_backends)
    valid=(c.maximum_fits==2 && planned==["advancedhmc","cmdstan"]) ||
        (c.maximum_fits==1 && planned==["cmdstan"] && hasproperty(c,:reuse_pilot))
    c.candidate_id=="independent_2d_raw_primary_01" && valid || error("Wrong pilot contract")
    for (name,hash) in pairs(c.source_sha256)
        digest(joinpath(REPO,String(name)))==hash || error("Source changed: $name")
    end
    digest(c.observed_path)==c.observed_sha256 || error("Pilot data changed")
    spec=specification(readjson(c.observed_path))
    return c,spec
end

function preflight(contract_path, output)
    c,spec=checked_contract(contract_path); t=target(spec)
    check=B.cmdstan_backend_check(;include_paths=true,require_ready=true)
    rng=MersenneTwister(c.seeds.cmdstan)
    seeds=B._cmdstan_chain_seeds(rng,4)
    initials=[B._advancedhmc_initial(zeros(128),rng,.1) for _ in 1:4]
    focal=focal_draws(t.design,zeros(2,128))
    @assert length(focal.names)==69 && count(==(:primary),focal.roles)==67
    # Exercise the package's actual detached command helper without a sampler.
    B._cmdstan_run(Cmd(["/bin/sleep","0.2"]),:sampling;show_output=false)
    writejson(output,(;contract_sha256=digest(contract_path),julia_version=string(VERSION),
        environment=B._evidence_project_hashes(;include_paths=true),cmdstan=check,
        controls=CONTROLS,criteria=CRITERIA,initial=zeros(128),cmdstan_chain_seeds=seeds,
        cmdstan_chain_initials=initials,raw_names=t.blueprint.parameter_names,
        focal=[(;parameter=focal.names[i],role=focal.roles[i],kind=focal.kinds[i]) for i in eachindex(focal.names)],
        target_identity=B._cache_hash((;data=readjson(c.observed_path),prior=B._source_fixture_prior_values(t.prior))),
        prior=B._source_fixture_prior_values(t.prior),stan_data=B._cmdstan_mgmfrm_data(t),
        initial_logdensity=B.LogDensityProblems.logdensity(t,zeros(128)),
        detached_command_helper_checked=true,new_sampler_runs=0,scientific_acceptance=false))
end

function fit_one(contract_path, backend, directory)
    backend in (:advancedhmc,:cmdstan) || error("Unplanned backend")
    c,spec=checked_contract(contract_path)
    String(backend) in c.planned_backends || error("Backend is outside the frozen fit roster")
    preparation=readjson(c.preflight_path)
    preparation.contract_sha256==digest(contract_path) || error("Wrong preflight contract")
    preparation.julia_version==string(VERSION) || error("Julia version changed")
    preparation.environment==JSON3.read(JSON3.write(B._evidence_project_hashes(;include_paths=true))) || error("Project environment changed")
    writejson(joinpath(directory,"started.json"),(;backend,contract_sha256=digest(contract_path),pid=getpid()))
    extra=backend===:cmdstan ? (;cmdstan_path=String(preparation.cmdstan.cmdstan_root),
        cmdstan_cache_dir=joinpath(directory,"compile")) : (;)
    started=time()
    try
        fit=B.Experimental.fit(spec;prior=prior(),backend,init=zeros(128),
            seed=Int(getproperty(c.seeds,backend)),CONTROLS...,extra...)
        @assert fit.chain_ids==repeat(1:4;inner=1000)
        @assert length(fit.sampler_controls.warmup_diagnostics)==4
        @assert all(r->r.coverage===:recorded && r.observed_iterations==1000,fit.sampler_controls.warmup_diagnostics)
        if backend===:cmdstan
            @assert collect(fit.sampler_controls.rng.chain_seeds)==preparation.cmdstan_chain_seeds
        end
        cache=joinpath(directory,"fit.jls")
        B.save_fit_cache(cache,fit)
        restored=B.load_fit_cache(cache)
        @assert isequal(fit.draws,restored.draws) && isequal(fit.sampler_stats,restored.sampler_stats)
        @assert isequal(B.diagnostics(fit),B.diagnostics(restored))
        focal=focal_draws(restored.design,restored.draws)
        rows=precision_rows(focal);qualification=qualify(restored,focal)
        primary_precision=all(r->r.role===:secondary || r.local_precision_passed,rows)
        writejson(joinpath(directory,"result.json"),(;status=:completed,backend,seconds=time()-started,
            contract_sha256=digest(contract_path),cache_sha256=digest(cache),qualification,primary_precision,
            computationally_qualified=qualification.qualified && primary_precision,rows,
            diagnostics=B.diagnostics(restored),controls=restored.sampler_controls,
            prediction_scope=:same_panel_diagnostic_not_cross_validation,scientific_acceptance=false))
    catch error
        writejson(joinpath(directory,"failure.json"),(;status=:fit_or_scoring_failed,backend,
            elapsed_seconds=time()-started,error=sprint(showerror,error)))
        rethrow()
    end
end

function main(args)
    BLAS.set_num_threads(1)
    if length(args)==3 && args[1]=="preflight"
        preflight(args[2],args[3])
    elseif length(args)==4 && args[1]=="fit"
        fit_one(args[2],Symbol(args[3]),args[4])
    else
        error("Use preflight CONTRACT OUTPUT or fit CONTRACT BACKEND JOB_DIRECTORY")
    end
end

end

if abspath(PROGRAM_FILE)==@__FILE__
    MGMFRMCorePilot.main(ARGS)
end
