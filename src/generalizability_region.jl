function anova_moments(t,d)
    levels=length.(getproperty.(t.components,:levels));K=length(levels)
    complete=if isempty(t.record.nesting)
        d.N==prod(length(unique(t.record.table[c])) for c in (t.record.person,values(t.record.facets)...))
    else
        d.N==levels[1]*levels[3]
    end
    complete || return nothing
    Y=reshape(d.y,d.N,d.C);grand=mean(Y;dims=1);projections=Matrix{Float64}[];df=Int[]
    for (j,b) in enumerate(t.components)
        sizes=zeros(Int,levels[j])
        for i in b.index;sizes[i]+=1;end
        all(==(first(sizes)),sizes) || return nothing
        means=zeros(levels[j],d.C)
        for i in 1:d.N;means[b.index[i],:]+=Y[i,:]/sizes[b.index[i]];end
        H=means[b.index,:].-grand;degrees=levels[j]-1
        for k in 1:j-1
            if issubset(t.components[k].factors,b.factors)
                H-=projections[k];degrees-=df[k]
            end
        end
        degrees>0 || return nothing
        push!(projections,H);push!(df,degrees)
    end
    scale=Diagonal(d.scales)
    (;levels,df,mean_squares=[vec(scale*(H'H/n)*scale) for (H,n) in zip(projections,df)])
end
function check_anova_moments(r)
    hasproperty(r,:anova_moments) || return nothing
    m=r.anova_moments;m===nothing && return nothing
    K=length(r.components);C=length(r.scores)
    length(m.levels)==length(m.df)==length(m.mean_squares)==K &&
        all(n->n isa Integer && n>=2,m.levels) && all(n->n isa Integer && n>0,m.df) &&
        last(m.levels)==r.n_observations && sum(m.df)==r.n_observations-1 || throw(ArgumentError("invalid ANOVA dimensions or degrees of freedom"))
    for (j,b) in enumerate(r.components)
        m.df[j]==m.levels[j]-1-sum((m.df[k] for k in 1:j-1 if issubset(r.components[k].factors,b.factors));init=0) ||
            throw(ArgumentError("ANOVA degrees of freedom disagree with component nesting"))
        x=m.mean_squares[j]
        length(x)==C*C && all(isfinite,x) || throw(ArgumentError("invalid ANOVA mean square"))
        V=reshape(collect(x),C,C)
        isapprox(V,V';rtol=1e-10,atol=1e-12) && eigmin(Symmetric(V))>=-1e-10*max(1.,opnorm(V)) ||
            throw(ArgumentError("ANOVA mean squares must be symmetric positive semidefinite"))
    end
    m
end

# A bounded polytope with at most seven components: enumerate every full-rank
# active set. The structural matrix is integer-valued, so nonzero determinants
# have magnitude >= 1. No stochastic or iterative optimizer is needed.
function region_vertices(B,lo,hi)
    K=length(lo);C=vcat(B,-B,-Matrix{Float64}(I,K,K));rhs=[hi;-lo;zeros(K)]
    vertices=Vector{Float64}[];indices=collect(1:K);worst=0.
    tolerance=512eps(Float64)*max(1.,maximum(hi))
    while true
        # A positive-width mean square cannot be at both of its bounds.
        if !any(i->i<=K && i+K in indices,indices)
            F=lu(C[indices,:];check=false)
            if abs(prod(diag(F.U)))>.5
                x=F\rhs[indices]
                if all(isfinite,x) && maximum(C*x-rhs)<=tolerance
                    x=max.(x,0.)
                    residual=max(0.,maximum(C*x-rhs))
                    if residual<=tolerance
                        push!(vertices,x);worst=max(worst,residual)
                    end
                end
            end
        end
        j=K
        while j>=1 && indices[j]==3K-K+j;j-=1;end
        j==0 && break
        indices[j]+=1
        for k in j+1:K;indices[k]=indices[k-1]+1;end
    end
    (;vertices=isempty(vertices) ? zeros(K,0) : reduce(hcat,vertices),max_residual=worst,tolerance)
end
function mean_square_region(r,w,interval)
    m=check_anova_moments(r)
    m===nothing && throw(ArgumentError("mean_square_region requires stored ANOVA mean squares from a complete balanced crossed or nested design"))
    A.interval_bounds(interval);C=length(r.scores);K=length(r.components)
    length(w)==C && all(isfinite,w) && any(!iszero,w) || throw(ArgumentError("invalid composite weights"))
    ms=[dot(w,reshape(collect(x),C,C)*w) for x in m.mean_squares]
    empty=(;vertices=zeros(K,0),status=:degenerate_mean_squares,tail=NaN,scale=NaN,max_residual=NaN)
    all(x->isfinite(x)&&x>0,ms) || return empty
    scale=maximum(ms);tail=-expm1(log(interval)/K)/2
    lo=[(v/scale)*df/D.cquantile(D.Chisq(df),tail) for (v,df) in zip(ms,m.df)]
    hi=[(v/scale)*df/D.quantile(D.Chisq(df),tail) for (v,df) in zip(ms,m.df)]
    all(isfinite,[lo;hi]) && all(hi.>lo) && minimum(lo)>512eps(Float64)*max(1.,maximum(hi)) ||
        return merge(empty,(;status=:numeric_resolution,tail,scale))
    B=Float64[issubset(a.factors,b.factors) for a in r.components,b in r.components]
    result=region_vertices(B,lo,hi)
    units=r.n_observations./collect(m.levels)
    vertices=(result.vertices.*scale)./units
    status=isempty(vertices) ? :empty_confidence_set : all(isfinite,vertices) ? :mean_square_region : :numeric_range
    (;vertices,status,tail,scale,max_residual=result.max_residual)
end
function region_design_intervals(region,components,counts,values)
    unavailable(status)=NamedTuple[(;estimate=v,se=missing,lower=missing,upper=missing,status) for v in values]
    region.status===:mean_square_region || return unavailable(region.status)
    V=region.vertices;K=size(V,1);u=vec(V[1,:]);relative=zeros(size(V,2));absolute=zeros(size(V,2))
    for k in 2:K
        ff=Symbol.(components[k].factors)
        divisor=prod(Float64(counts[f]) for f in ff if f!==:person)
        v=vec(V[k,:])./divisor;absolute+=v
        :person in ff && (relative+=v)
    end
    all(isfinite,[u;relative;absolute]) && minimum(relative)>0 && minimum(absolute)>0 || return unavailable(:numeric_range)
    targets=(u./(u+relative),u./(u+absolute),sqrt.(relative),sqrt.(absolute),u,absolute)
    NamedTuple[(;estimate=values[j],se=missing,lower=minimum(x),upper=maximum(x),status=:mean_square_region) for (j,x) in enumerate(targets)]
end
