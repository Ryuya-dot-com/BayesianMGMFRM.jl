# Included inside AdditiveFacets; the package's lifecycle verbs dispatch below.
const FIT_SCHEMA = "bayesianmgmfrm.additive_facet_fit.v1"
const REPORT_SCHEMA = "bayesianmgmfrm.additive_facet_report.v1"

struct Fit
    record::NamedTuple
end

B._check_source_fixture_raw_vector(t::Target,q::AbstractVector)=_check(t,q)

function checked(f::Fit;full=false)
    r=f.record
    keys(r)==(:schema,:target,:target_identity,:run,:producer,:content_hash) &&
        r.schema==FIT_SCHEMA || throw(ArgumentError("unsupported additive fit record"))
    body=(;r.schema,r.target,r.target_identity,r.run,r.producer)
    B._cache_hash(body)==r.content_hash && B._cache_hash(r.target)==r.target_identity ||
        throw(ArgumentError("additive fit content/target checksum mismatch"))
    t=restore(r.target)
    t.allocation.identified || throw(ArgumentError("stored additive fit design is rank deficient"))
    if full
        B._check_generalized_sample_run(t,r.run)
        length(r.run.warmup_stats)==r.run.controls.chains*r.run.controls.warmup ||
            throw(ArgumentError("incomplete additive warmup telemetry"))
        B._warmup_diagnostic_rows(r.run.warmup_stats,r.run.controls,r.run.backend)
    end
    t
end

function fit(target::Target;ndraws::Int,warmup::Int,chains::Int,seed,
        target_accept=.9,max_depth=10,step_size=.03,init_jitter=.1,metric=:diagonal,
        progress=false,chain_execution=:serial,max_parallel_chains=chains)
    t=restore(record(target))
    t.allocation.identified || throw(ArgumentError(
        "additive facet design has rank $(t.allocation.rank)/$(t.dimension); inspect design_summary"))
    seed isa Integer && !(seed isa Bool) && 0<=seed<=typemax(Int) ||
        throw(ArgumentError("seed must be a nonnegative integer representable as Int"))
    run=B._run_generalized_candidate_advancedhmc(t,zeros(t.dimension);ndraws,warmup,chains,
        seed=Int(seed),target_accept,max_depth,step_size,init_jitter,metric,progress,
        chain_execution,max_parallel_chains,ad_backend=:analytic,record_warmup=true)
    target_record=record(t)
    producer=(;julia=string(VERSION),package=string(Base.pkgversion(B)),
        advancedhmc=string(Base.pkgversion(B.AdvancedHMC)),
        diagnostic_tools=string(Base.pkgversion(B.MCMCDiagnosticTools)))
    body=(;schema=FIT_SCHEMA,target=target_record,target_identity=B._cache_hash(target_record),run,producer)
    f=Fit(merge(body,(;content_hash=B._cache_hash(body))))
    checked(f;full=true)
    f
end

function model_draws(t,raw)
    labels=names(t,:model);values=Matrix{Float64}(undef,size(raw,1),length(labels))
    for (i,q) in enumerate(eachrow(raw))
        v=coordinates(t,q)
        values[i,:]=[v.person;reduce(vcat,(v.facets[b.name] for b in t.facets);init=Float64[]);
            vec(permutedims(v.steps))]
    end
    fixed=Set{String}();offset=length(t.people)
    for b in t.facets
        length(b.levels)==1 && push!(fixed,labels[offset+1])
        offset+=length(b.levels)
    end
    length(t.categories)==2 && union!(fixed,labels[offset+1:end])
    (;names=labels,values,fixed)
end

function selected(t,run;scale=:model,parameters=nothing)
    scale in (:raw,:model) || throw(ArgumentError("scale must be :raw or :model"))
    m=scale===:model ? model_draws(t,run.draws) :
        (;names=names(t,:raw),values=run.draws,fixed=Set{String}())
    chosen=parameters===nothing ? m.names : collect(parameters)
    !isempty(chosen) && allunique(chosen) && all(n->n in m.names,chosen) ||
        throw(ArgumentError("select distinct parameter_names from the requested scale"))
    ix=[only(findall(==(n),m.names)) for n in chosen]
    (;names=chosen,values=m.values[:,ix],fixed=m.fixed)
end

function diagnostics(f::Fit)
    t=checked(f);run=f.record.run;m=model_draws(t,run.draws)
    diagnose(x,n;space,fixed=Set{String}())=B._candidate_mcmc_diagnostic_rows(x,n,run.controls.chains;
        parameter_space=space,structurally_fixed_parameters=fixed,
        split_chains=run.split_chains_requested,rhat_threshold=run.checked.rhat_threshold,
        ess_threshold=run.checked.ess_threshold)
    (;raw=diagnose(run.draws,names(t,:raw);space=:white),
      model=diagnose(m.values,m.names;space=:model,fixed=m.fixed),sampler=deepcopy(run.sampler_rows),
      warmup=B._warmup_diagnostic_rows(run.warmup_stats,run.controls,run.backend),
      thresholds=(;run.checked...,minimum_chains=4),scientific_acceptance=false)
end

function qualify(f::Fit;max_rhat=1.01,min_ess=400.,min_bfmi=.30)
    thresholds=B._check_diagnostic_thresholds(max_rhat,min_ess)
    min_ess isa Bool && throw(ArgumentError("min_ess must be a finite positive number"))
    min_bfmi isa Real && !(min_bfmi isa Bool) && isfinite(min_bfmi) && min_bfmi>0 ||
        throw(ArgumentError("min_bfmi must be a finite positive number"))
    B._qualify_experimental_diagnostics(diagnostics(f),f.record.run,thresholds,Float64(min_bfmi))
end

function interval_bounds(interval)
    interval isa Real && !(interval isa Bool) && isfinite(interval) && 0<interval<1 ||
        throw(ArgumentError("interval must be in (0,1)"))
    lo=(1-Float64(interval))/2
    lo,1-lo
end

function summary(f::Fit;scale=:model,parameters=nothing,interval=.95)
    t=checked(f);m=selected(t,f.record.run;scale,parameters);lo,hi=interval_bounds(interval)
    rows=B._posterior_summary_rows(m.values,m.names;lower=lo,upper=hi,intervals=(interval,),
        reference=0.,rope=nothing,rope_probability_threshold=.95)
    (;scale,unit=scale===:model ? :unit_logit : :white_standard_normal,interval,
      rows=[(;r.parameter,r.mean,r.sd,r.median,r.lower,r.upper,
          structurally_fixed=r.parameter in m.fixed) for r in rows],
      source_sample_content_hash=f.record.content_hash,scientific_acceptance=false)
end

function mcse(f::Fit;scale=:model,parameters=nothing,probabilities=(.025,.5,.975))
    t=checked(f);m=selected(t,f.record.run;scale,parameters)
    B._posterior_mcse_rows(m.values,m.names,f.record.run.controls.chains;probabilities,
        parameter_space=scale,structurally_fixed_parameters=m.fixed)
end

function contrast(f::Fit;left,right,interval=.95,rope=nothing)
    left!=right || throw(ArgumentError("choose distinct named parameters"))
    t=checked(f);m=selected(t,f.record.run;parameters=[left,right])
    result=B.posterior_contrast(m.values[:,1],m.values[:,2];
        chains=f.record.run.controls.chains,interval,rope)
    (;left,right,unit=:unit_logit,result,source_sample_content_hash=f.record.content_hash,
      qualification=qualify(f),conditioning=:joint_posterior_same_draws,scientific_acceptance=false)
end

function prediction_target(t,data)
    data===nothing && return t
    # Reconstruct with the ORIGINAL panel and prior; never recenter a subset.
    n=length(B._column(data,t.columns.person))
    table=Dict{Symbol,Vector}()
    for col in keys(t.table)
        table[col]=col==t.columns.score ? fill(first(t.categories),n) : collect(B._column(data,col))
        B._check_length!(n,table[col],col)
    end
    perf,assessment=t.columns.performance,t.columns.assessment
    if perf!==nothing
        links=Dict(zip(t.table[perf],t.table[t.columns.person]))
        all(i->!haskey(links,table[perf][i]) || links[table[perf][i]]==table[t.columns.person][i],1:n) ||
            throw(ArgumentError("prediction changes the person of a stored performance ID"))
        if assessment!==nothing
            links=Dict(zip(t.table[assessment],t.table[perf]))
            all(i->!haskey(links,table[assessment][i]) || links[table[assessment][i]]==table[perf][i],1:n) ||
                throw(ArgumentError("prediction changes the performance of a stored assessment ID"))
        end
    end
    r=record(t)
    model(table;r.columns...,category_levels=r.category_levels,steps=r.steps,
        levels=r.levels,prior_sd=r.prior_sd)
end

function predict(f::Fit;data=nothing,rows=nothing,interval=.95)
    t=checked(f);p=prediction_target(t,data);m=model_draws(t,f.record.run.draws)
    ix=rows===nothing ? collect(eachindex(p.person)) : collect(rows)
    !isempty(ix) && all(i->i isa Integer && !(i isa Bool) && 1<=i<=length(p.person),ix) ||
        throw(ArgumentError("rows must select existing prediction rows"))
    lo,hi=interval_bounds(interval);K=length(t.categories);S=size(m.values,1)
    means=zeros(length(ix),K);lower=similar(means);upper=similar(means);precision=NamedTuple[]
    offsets=cumsum([length(t.people);[length(b.levels) for b in t.facets]])
    a=zeros(S,K)
    for (j,n) in enumerate(ix)
        for s in 1:S
            eta=m.values[s,p.person[n]]
            for (b,off) in zip(p.facets,offsets)
                eta-=m.values[s,off+b.index[n]]
            end
            a[s,1]=0.
            for k in 2:K
                a[s,k]=a[s,k-1]+eta-m.values[s,last(offsets)+(p.group[n]-1)*(K-1)+k-1]
            end
            z=B._logsumexp(view(a,s,:));a[s,:].=exp.(view(a,s,:).-z)
        end
        means[j,:]=vec(mean(a;dims=1))
        for k in 1:K;lower[j,k]=quantile(view(a,:,k),lo);upper[j,k]=quantile(view(a,:,k),hi);end
        append!(precision,[(;row=Int(n),category=p.categories[k],r...) for (k,r) in enumerate(
            B._posterior_mcse_rows(a,["category[$k]" for k in t.categories],f.record.run.controls.chains;
                probabilities=(lo,hi),parameter_space=:category_probability))])
    end
    (;rows=Int.(ix),category_levels=copy(p.categories),mean=means,lower,upper,interval,mcse=precision,
      selected_columns=Dict(col=>copy(values[ix]) for (col,values) in p.table if col!=p.columns.score),
      conditioning=:known_finite_panel_levels,interval_target=:posterior_category_probability,
      observation_prediction=:posterior_mean_probabilities,qualification=qualify(f),
      source_sample_content_hash=f.record.content_hash,scientific_acceptance=false)
end

# JSON reports retain typed label encodings; they do not reconstruct native fits.
label_encoding(x)=(;kind=x isa Symbol ? :symbol : x isa AbstractString ? :string :
    x isa Integer ? :integer : :float,
    value=string(x),julia_type=string(typeof(x)))
function report(f::Fit;scale=:model,parameters=nothing,interval=.95)
    t=checked(f);lo,hi=interval_bounds(interval)
    (;schema=REPORT_SCHEMA,api=contract(t),summary=summary(f;scale,parameters,interval),
      mcse=mcse(f;scale,parameters,probabilities=(lo,.5,hi)),qualification=qualify(f),
      controls=deepcopy(f.record.run.controls),producer=f.record.producer,
      source_sample_content_hash=f.record.content_hash,target_identity=f.record.target_identity,
      input_labels=Dict(col=>label_encoding.(values) for (col,values) in t.table),
      warnings=design(t).warnings,scientific_acceptance=false)
end

function save_result(path,f::Fit)
    checked(f;full=true);B._save_serialized_record(path,f;overwrite=false)
end
function load_result(f::Fit)
    checked(f;full=true);f
end
function save_computed(path,rep)
    (ispath(path) || islink(path)) && throw(ArgumentError("report already exists: $path"))
    mkpath(dirname(path))
    mktemp(dirname(path)) do temporary,io
        B.JSON3.write(io,B.Experimental.JointRatings.W.jsonsafe(rep));close(io)
        hardlink(temporary,path)
    end
    rep
end
