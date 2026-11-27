# Independent Gaussian mean squares supply finite-sample pivots for a complete
# person × facet design. No fitted variance is substituted into their sampling law.
function balanced_moments(t,d)
    length(t.record.facets)==1 || return nothing
    P=length(t.components[1].levels);R=length(t.components[2].levels)
    d.N==P*R || return nothing
    pi=t.components[1].index;ri=t.components[2].index
    Y=reshape(d.y,d.N,d.C);pm=zeros(P,d.C);rm=zeros(R,d.C)
    for i in 1:d.N
        pm[pi[i],:]+=Y[i,:]/R;rm[ri[i],:]+=Y[i,:]/P
    end
    grand=mean(Y;dims=1);E=Y-pm[pi,:]-rm[ri,:].+grand
    pc=pm.-grand;Dscale=Diagonal(d.scales)
    (;persons=P,replications=R,person_df=P-1,residual_df=(P-1)*(R-1),
        person_ms=vec(Dscale*(R/(P-1)*(pc'pc))*Dscale),
        residual_ms=vec(Dscale*(E'E/((P-1)*(R-1)))*Dscale))
end
function check_balanced_moments(r)
    hasproperty(r,:balanced_moments) || return nothing
    m=r.balanced_moments;m===nothing && return nothing
    C=length(r.scores)
    length(r.facets)==1 && length(r.components)==3 &&
        m.persons isa Integer && m.replications isa Integer && m.persons>=2 && m.replications>=2 &&
        m.persons*m.replications==r.n_observations && m.person_df==m.persons-1 &&
        m.residual_df==(m.persons-1)*(m.replications-1) || throw(ArgumentError("invalid balanced-design degrees of freedom"))
    for x in (m.person_ms,m.residual_ms)
        length(x)==C*C && all(isfinite,x) || throw(ArgumentError("invalid mean-square matrix"))
        V=reshape(collect(x),C,C)
        isapprox(V,V';rtol=1e-10,atol=1e-12) && eigmin(Symmetric(V))>=-1e-10*max(1.,opnorm(V)) ||
            throw(ArgumentError("mean-square matrices must be symmetric positive semidefinite"))
    end
    m
end
function exact_design_intervals(r,w,n,values,interval)
    m=check_balanced_moments(r)
    m===nothing && throw(ArgumentError("exact intervals require stored mean squares from a complete balanced one-facet design"))
    C=length(w);p=dot(w,reshape(collect(m.person_ms),C,C)*w)
    e=dot(w,reshape(collect(m.residual_ms),C,C)*w)
    stats=NamedTuple[(;estimate=v,se=missing,lower=missing,upper=missing,status=:not_supported_by_exact) for v in values]
    if !(isfinite(p)&&isfinite(e)&&p>=0&&e>0)
        for j in (1,3);stats[j]=merge(stats[j],(;status=:degenerate_mean_squares));end
        return stats
    end
    lo,hi=A.interval_bounds(interval);F=D.FDist(m.person_df,m.residual_df)
    bounds=(p/e/D.quantile(F,hi),p/e/D.quantile(F,lo))
    if all(isfinite,bounds) && bounds[2]>=1
        transform(lambda)=1/(1+m.replications/(Float64(n)*(lambda-1)))
        stats[1]=merge(stats[1],(;lower=transform(max(1.,bounds[1])),upper=transform(bounds[2]),status=:exact_f))
    else
        stats[1]=merge(stats[1],(;status=all(isfinite,bounds) ? :empty_confidence_set : :numeric_range))
    end
    chi=D.Chisq(m.residual_df)
    bounds_sem=sqrt.((m.residual_df*e/Float64(n)/D.quantile(chi,hi),m.residual_df*e/Float64(n)/D.quantile(chi,lo)))
    if all(isfinite,bounds_sem)
        stats[3]=merge(stats[3],(;lower=bounds_sem[1],upper=bounds_sem[2],status=:exact_chisq))
    else
        stats[3]=merge(stats[3],(;status=:numeric_range))
    end
    stats
end
