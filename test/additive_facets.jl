using Test, BayesianMGMFRM, LinearAlgebra, ForwardDiff, Serialization, Statistics
import LogDensityProblems as L
const AF=BayesianMGMFRM.AdditiveFacets

# All labels are arbitrary. None are the semantic names used in earlier examples.
function additive_fixture(F;K=3,owner=:named,m=2)
    keys=Tuple(Symbol("effect_",j) for j in 1:F)
    columns=Tuple(Symbol("input_",j) for j in 1:F)
    rows=collect(Iterators.product(1:3,ntuple(_->1:m,F)...))[:]
    table=Dict{Symbol,Vector}(:actor=>[r[1] for r in rows],
        :answer=>[mod(i-1,K)+2 for i in eachindex(rows)])
    for (j,c) in enumerate(columns);table[c]=[r[j+1] for r in rows];end
    facets=NamedTuple{keys}(columns)
    prior=(;person=.8,facets=NamedTuple{keys}(ntuple(j->m==1 ? 0. : .3+.07j,F)),step=K==2 ? 0. : .6)
    step=owner===:global || F==0 ? :global : last(keys)
    options=(;person=:actor,score=:answer,facets,steps=step,prior_sd=prior,category_levels=2:K+1)
    table,options
end

# Direct dense coefficient construction, separate from sparse rank and implicit
# coordinate/gradient routines. No production helper or stan_data is used.
function additive_reference(t)
    n=length(t.person);K=length(t.categories);P=length(t.people)
    H(m)= [i<=j ? 1/sqrt(j*(j+1)) : i==j+1 ? -j/sqrt(j*(j+1)) : 0.
           for i in 1:m,j in 1:m-1]
    C=zeros(n*(K-1),t.dimension)
    for row in 1:n, k in 1:K-1
        i=(row-1)*(K-1)+k; C[i,t.person[row]]=t.person_sd
        for b in t.facets
            C[i,b.raw].=-b.scale.*H(length(b.levels))[b.index[row],:]
        end
        C[i,t.steps[t.group[row]]].=-t.step_scale.*H(K-1)[k,:]
    end
    C
end
function additive_reference_density(t,C,q)
    logits=C*q;lp=-dot(q,q)/2-length(q)*log(2pi)/2;K=length(t.categories)
    for n in eachindex(t.person)
        a=vcat(zero(eltype(q)),cumsum(logits[(n-1)*(K-1)+1:n*(K-1)]))
        m=maximum(a);lp+=a[t.category[n]]-m-log(sum(exp.(a.-m)))
    end
    lp
end

const ADDITIVE_NATIVE_CASES=Any[]
const ADDITIVE_ERRORS=Float64[]
@testset "Generic additive facets" begin
    for (F,K,owner,m) in ((0,2,:global,2),(1,4,:global,3),(4,3,:named,2),
                         (5,3,:named,2),(6,3,:named,2),(6,2,:named,2),(2,3,:named,1))
        table,opts=additive_fixture(F;K,owner,m);t=mfrm_spec(table;opts...)
        @test getdesign(t)===t
        @test design_summary(t).n_facets==F+1
        @test validate_design(t).identified
        @test t.dimension==3+F*(m-1)+(owner===:global || F==0 ? 1 : m)*(K-2)
        @test length(parameter_names(t))==t.dimension
        @test contract(t).fit_available
        @test_throws UndefKeywordError fit(t)
        C=additive_reference(t)
        @test rank(C)==validate_design(t).rank
        qs=[zeros(t.dimension),[.17sin(i) for i in 1:t.dimension],
            [.4cos(i/2) for i in 1:t.dimension]]
        for q in qs
            lp,g=logdensity_and_gradient(t,q);ref=additive_reference_density(t,C,q)
            rg=ForwardDiff.gradient(x->additive_reference_density(t,C,x),q)
            push!(ADDITIVE_ERRORS,max(abs(lp-ref),maximum(abs.(g-rg))))
            @test lp≈ref atol=1e-9 rtol=0
            @test g≈rg atol=1e-9 rtol=0
            @test g≈ForwardDiff.gradient(x->L.logdensity(t,x),q) atol=1e-9 rtol=0
            @test lp≈logprior(t,q)+sum(pointwise_loglikelihood(t,q)) atol=1e-9
            v=coordinates(t,q);probs=predictive_probabilities(t,q)
            @test all(isfinite,probs) && all(probs.>0)
            @test vec(sum(probs;dims=2))≈ones(length(t.person)) atol=1e-14
            for b in t.facets;@test abs(sum(v.facets[b.name]))<1e-14;end
            @test maximum(abs.(sum(v.steps;dims=2)))<1e-14
            K==2 && @test all(iszero,v.steps)
        end
        # Input mutation must not alter the compiled target.
        original=copy(t.table[:answer]);table[:answer][1]=last(t.categories)
        @test t.table[:answer]==original && t.table[:answer] != table[:answer]
        rec=contract(t).record;restored=AF.restore(rec)
        @test parameter_names(restored)==parameter_names(t)
        @test isequal(contract(restored).record,rec)
        @test L.logdensity(restored,qs[2])==L.logdensity(t,qs[2])
        push!(ADDITIVE_NATIVE_CASES,(;F,K,owner,m,t,qs,C))
    end

    table,opts=additive_fixture(6);t=mfrm_spec(table;opts...);q=collect(range(-.3,.4;length=t.dimension))
    # Rename every facet key and every input column, including the step owner.
    newkeys=(:alpha,:banana,:cobalt,:delta,:ember,:foxtrot)
    newcols=(:a,:b,:c,:d,:e,:f)
    newtable=Dict{Symbol,Vector}(:who=>copy(table[:actor]),:value=>copy(table[:answer]))
    for (a,b) in zip(newcols,values(opts.facets));newtable[a]=copy(table[b]);end
    nt=mfrm_spec(newtable;person=:who,score=:value,facets=NamedTuple{newkeys}(newcols),
        steps=:foxtrot,prior_sd=(;person=opts.prior_sd.person,facets=NamedTuple{newkeys}(values(opts.prior_sd.facets)),step=.6),category_levels=2:4)
    @test predictive_probabilities(nt,q)==predictive_probabilities(t,q)
    @test logdensity_and_gradient(nt,q)==logdensity_and_gradient(t,q)
    @test all(x->x in contract(nt).facet_names,newkeys)

    # Reorder declarations and transport the complete white vector by named blocks.
    ks=reverse(keys(opts.facets));fs=NamedTuple{ks}(reverse(values(opts.facets)))
    rt=mfrm_spec(table;merge(opts,(;facets=fs))...)
    rq=copy(q)
    for b in rt.facets;old=only(filter(x->x.name==b.name,t.facets));rq[b.raw]=q[old.raw];end
    @test L.logdensity(rt,rq)≈L.logdensity(t,q) atol=1e-12
    @test predictive_probabilities(rt,rq)≈predictive_probabilities(t,q) atol=1e-14

    # Changing roster order transports the joint prior, including step-group order.
    lev=(;person=reverse(t.people),facets=(;(b.name=>reverse(b.levels) for b in t.facets)...))
    lt=mfrm_spec(table;opts...,levels=lev);v=coordinates(t,q);lq=zeros(t.dimension)
    lq[1:3]=reverse(v.person)./t.person_sd
    for b in lt.facets
        x=reverse(v.facets[b.name]);h=[AF.N._zero_sum([i==j ? 1. : 0. for i in eachindex(b.raw)]) for j in eachindex(b.raw)]
        lq[b.raw]=hcat(h...)'*x./b.scale
    end
    for (i,r) in enumerate(lt.steps);lq[r]=q[t.steps[end-i+1]];end
    @test L.logdensity(lt,lq)≈L.logdensity(t,q) atol=1e-12
    @test predictive_probabilities(lt,lq)≈predictive_probabilities(t,q) atol=1e-14

    # A new named facet can be syntactically valid and structurally aliased.
    conf=copy(table);conf[:extra]=copy(table[:input_1])
    cf=merge(opts.facets,(;extra=:extra));cp=merge(opts.prior_sd,(;facets=merge(opts.prior_sd.facets,(;extra=.5))))
    ct=mfrm_spec(conf;merge(opts,(;facets=cf,prior_sd=cp))...)
    @test !validate_design(ct).identified
    @test validate_design(ct).rank==rank(additive_reference(ct))
    @test !isempty(validate_design(ct).dependent_reference_columns)
    @test_throws ArgumentError fit(ct;ndraws=10,warmup=10,chains=2,seed=1)
    @test length(prior_draw(ct;seed=17))==ct.dimension
    # A training subset keeps an absent declared level, not a recentered panel.
    keep=findall(==(1),table[:input_1]);sub=Dict(k=>x[keep] for (k,x) in table)
    levels=(;person=t.people,facets=(;(b.name=>b.levels for b in t.facets)...))
    st=mfrm_spec(sub;opts...,levels)
    @test !validate_design(st).identified
    @test st.dimension==t.dimension
    @test !isempty(validate_design(st).missing_levels)
    @test validate_design(st).rank==rank(additive_reference(st))

    for seed in (1,2,19)
        @test prior_draw(t;seed)==prior_draw(t;seed)
        a=simulate(t;seed);b=simulate(t;seed,q=a.truth)
        @test a.simulated==b.simulated
        @test a.truth==prior_draw(t;seed)
        @test keys(a.simulated)==keys(t.table)
        @test all(x->x in t.categories,a.simulated[:answer])
    end
    pp=prior_predictive_check(t;ndraws=3,seed=55)
    @test vec(sum(pp.replicated_counts;dims=2))==fill(length(t.person),3)
    draws=hcat([prior_draw(t;seed=i) for i in 1:2000]...)
    @test maximum(abs.(vec(mean(draws;dims=2))))<.1
    @test maximum(abs.(vec(std(draws;dims=2)).-1))<.1

    # Group IDs survive simulation and native mathematical-design restoration.
    grouped=copy(table);grouped[:clip]=["clip-$(table[:actor][i])-$(table[:input_1][i])" for i in eachindex(t.person)]
    grouped[:event]=["e-$i" for i in eachindex(t.person)]
    gt=mfrm_spec(grouped;opts...,performance=:clip,assessment=:event)
    @test design_summary(gt).grouping.repeated_performances>0
    @test simulate(gt;seed=19).simulated[:clip]==grouped[:clip]
    @test AF.restore(contract(gt).record).table==gt.table

    bad=copy(grouped);bad[:clip]=fill("same",length(t.person))
    @test_throws ArgumentError mfrm_spec(bad;opts...,performance=:clip,assessment=:event)
    dup=Dict(k=>vcat(v,v[1]) for (k,v) in table)
    @test_throws ArgumentError mfrm_spec(dup;opts...)
    @test_throws ArgumentError mfrm_spec(table;merge(opts,(;steps=:unknown))...)
    @test_throws ArgumentError mfrm_spec(table;merge(opts,(;facets=merge(opts.facets,(;also=:input_1))))...)
    @test_throws ArgumentError mfrm_spec(table;merge(opts,(;prior_sd=merge(opts.prior_sd,(;facets=(;wrong=.5)))))...)
    @test_throws MethodError mfrm_spec(table;opts...,anchors=[1])
    @test_throws MethodError mfrm_spec(table;opts...,dimensions=2)
    @test_throws MethodError mfrm_spec(table;opts...,criterion=:input_1)
    @test_throws ArgumentError mfrm_spec(table;merge(opts,(;category_levels=[2,4]))...)
    @test_throws ArgumentError mfrm_spec(table;merge(opts,(;prior_sd=merge(opts.prior_sd,(;person=Inf))))...)
    @test_throws ArgumentError prior_draw(t;seed=true)
    @test_throws ArgumentError prior_predictive_check(t;ndraws=0)
    @test_throws ArgumentError predictive_probabilities(t,fill(NaN,t.dimension))
    @test L.logdensity(t,fill(Inf,t.dimension)) == -Inf
    @test all(isnan,last(logdensity_and_gradient(t,fill(Inf,t.dimension))))
    @test_throws DimensionMismatch L.logdensity(t,q[1:end-1])
    # The old FacetData dispatch remains selected, with its original prior/constraints.
    d=FacetData((;p=[1,1,2,2],r=[1,2,1,2],i=[1,2,2,1],y=[0,1,2,1]);person=:p,rater=:r,item=:i,score=:y,category_levels=0:2)
    @test mfrm_spec(d) isa BayesianMGMFRM.FacetSpec
    @test getdesign(mfrm_spec(d)).identification[:rater]===:reference_first

    # Match the preserved 4-person / 3-task / 3-rater / 2-criterion / 2-occasion
    # structural fixture through entirely user-selected keys and column names.
    for extra in (false,true)
        sizes=extra ? (3,3,2,2,2) : (3,3,2,2)
        F=length(sizes);ks=Tuple(Symbol("label_",j) for j in 1:F)
        cs=Tuple(Symbol("col_",j) for j in 1:F)
        rows=collect(Iterators.product(1:4,(1:m for m in sizes)...))[:]
        data=Dict{Symbol,Vector}(:p=>[r[1] for r in rows],:y=>[mod(i,3) for i in eachindex(rows)])
        for j in 1:F;data[cs[j]]=[r[j+1] for r in rows];end
        spec=mfrm_spec(data;person=:p,score=:y,facets=NamedTuple{ks}(cs),steps=ks[3],category_levels=0:2,
            prior_sd=(;person=.8,facets=NamedTuple{ks}(ntuple(_->.5,F)),step=.6))
        @test length(rows)==(extra ? 288 : 144)
        @test validate_design(spec).rank==spec.dimension==(extra ? 13 : 12)
        C=additive_reference(spec)
        @test rank(C)==spec.dimension
        qs=[zeros(spec.dimension),[.17sin(i) for i in 1:spec.dimension],[.4cos(i/2) for i in 1:spec.dimension]]
        for q in qs
            lp,g=logdensity_and_gradient(spec,q)
            @test lp≈additive_reference_density(spec,C,q) atol=1e-9 rtol=0
            @test g≈ForwardDiff.gradient(x->additive_reference_density(spec,C,x),q) atol=1e-9 rtol=0
        end
        push!(ADDITIVE_NATIVE_CASES,(;F,K=3,owner=:named,m=0,t=spec,qs,C))
    end
end
