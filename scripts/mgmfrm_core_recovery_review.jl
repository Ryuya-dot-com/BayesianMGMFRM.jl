module MGMFRMCoreRecoveryReview

import BayesianMGMFRM as B
using Statistics, LinearAlgebra
include(joinpath(@__DIR__,"mgmfrm_core_location_conditional.jl"))
const C=MGMFRMCoreLocationConditional

"""Parameter-only recovery quantities for the declared dense pure-Q candidate.

Keeps the original 59 facet/contrast quantities and 100 person coordinates,
then adds 12 location quantities, 100 centered persons and two named contrasts.
No posterior predictive array is constructed for this parameter-only review.
"""
function quantities(target,raw::AbstractMatrix{<:Real})
    spec=target.design.spec;data=spec.data
    spec.family===:mgmfrm && spec.dimensions==2 &&
        spec.q_matrix==Bool[1 0;1 0;0 1;0 1;0 1] &&
        data.person_levels==sort(["P$i" for i in 1:50]) &&
        data.item_levels==["I$i" for i in 1:5] && data.rater_levels==["R$i" for i in 1:5] ||
        throw(ArgumentError("Only the declared dense 50/5/5 pure-Q candidate is supported"))
    size(raw,1)>0 && size(raw,2)==128 && all(x->!(x isa Bool) && isfinite(x),raw) ||
        throw(ArgumentError("Finite nonempty draws with 128 raw coordinates required"))
    roster=NamedTuple[];columns=Vector{Float64}[]
    function add(name,values,block;dimension=nothing)
        push!(roster,(;parameter=name,block,dimension));push!(columns,Float64.(values))
    end
    severity=hcat(raw[:,101:104],-sum(raw[:,101:104];dims=2))
    ell=hcat(raw[:,115:118],-sum(raw[:,115:118];dims=2))
    for i in 1:5
        add("b[I$i]",raw[:,104+i],:item)
        add("a[I$i]",exp.(raw[:,109+i]),:loading;dimension=i<=2 ? 1 : 2)
        add("severity[R$i]",severity[:,i],:severity)
        add("gamma[R$i]",exp.(ell[:,i]),:consistency)
        free=raw[:,(117+2i):(118+2i)]
        for (h,values) in enumerate((free[:,1],free[:,2],-vec(sum(free;dims=2))))
            add("step[I$i,h=$h]",values,:step)
        end
    end
    for a in 1:4,b in a+1:5
        add("severity[R$a]-severity[R$b]",severity[:,a]-severity[:,b],:severity_contrast)
        add("log_gamma[R$a]-log_gamma[R$b]",ell[:,a]-ell[:,b],:log_consistency_contrast)
        if (a<=2)==(b<=2)
            add("b[I$a]-b[I$b]",raw[:,104+a]-raw[:,104+b],:item_contrast;dimension=a<=2 ? 1 : 2)
        end
    end
    for j in 1:100
        add(target.blueprint.parameter_names[j],raw[:,j],:person;dimension=mod1(j,2))
    end
    means=hcat([vec(mean(raw[:,d:2:100];dims=2)) for d in 1:2]...)
    for d in 1:2
        add("person_mean[dim=$d]",means[:,d],:person_mean;dimension=d)
    end
    for i in 1:5
        d=i<=2 ? 1 : 2;weighted=exp.(raw[:,109+i]).*means[:,d]
        add("loading_weighted_person_mean[I$i]",weighted,:weighted_person_mean;dimension=d)
        add("item_minus_loading_weighted_person_mean[I$i]",raw[:,104+i]-weighted,:relative_item;dimension=d)
    end
    for (p,id) in enumerate(data.person_levels),d in 1:2
        add("centered_person[$id,dim=$d]",raw[:,2(p-1)+d]-means[:,d],:centered_person;dimension=d)
    end
    p1=findfirst(==("P1"),data.person_levels);p2=findfirst(==("P2"),data.person_levels)
    for d in 1:2
        add("theta[P1,D$d]-theta[P2,D$d]",raw[:,2(p1-1)+d]-raw[:,2(p2-1)+d],:person_contrast;dimension=d)
    end
    return (;names=getproperty.(roster,:parameter),roster,draws=hcat(columns...))
end

"""Equal-tailed interval recovery and MCMC precision; no acceptance decision."""
function review(q,truth;chains=4)
    q.names==truth.names && size(truth.draws,1)==1 || throw(ArgumentError("Aligned one-row truth required"))
    precision=B.posterior_mcse(q.draws;chains,parameter_names=q.names,probabilities=(.025,.05,.5,.95,.975))
    finite(x)=x isa Real && isfinite(x) && x>=0
    rows=map(eachindex(q.names)) do j
        x=q.draws[:,j];t=truth.draws[1,j];m=precision[j];sd=std(x)
        qs=Dict(r.probability=>r for r in m.quantiles)
        intervals=map(((.9,.05,.95),(.95,.025,.975))) do (level,lo,hi)
            lower,upper=qs[lo],qs[hi];width=upper.estimate-lower.estimate
            available=width>0 && finite(lower.mcse) && finite(upper.mcse)
            (;level,lower=lower.estimate,upper=upper.estimate,width,
                covered=lower.estimate<=t<=upper.estimate,lower_mcse=lower.mcse,upper_mcse=upper.mcse,
                maximum_endpoint_mcse_over_width=available ? max(lower.mcse,upper.mcse)/width : missing,
                boundary_sensitivity=available ? min(abs(t-lower.estimate)-2lower.mcse,
                    abs(t-upper.estimate)-2upper.mcse)<=0 : missing)
        end
        local_precision=finite(m.mean_mcse) && sd>0 && m.mean_mcse/sd<=.05 &&
            all(r->finite(r.maximum_endpoint_mcse_over_width) && r.maximum_endpoint_mcse_over_width<=.05,intervals)
        (;q.roster[j]...,truth=t,estimate=mean(x),error=mean(x)-t,posterior_sd=sd,
            precision=m,intervals,local_precision_passed=local_precision)
    end
    return (;rows,n_chains=chains,draws_per_chain=size(q.draws,1)÷chains)
end

"""Summaries within a panel. The panel, not its 50 persons, is a repetition.
The average signed error of centered persons, severities and steps is zero by construction.
"""
function panel_rows(rows)
    keys=unique((r.block,r.dimension) for r in rows)
    return map(keys) do (block,dimension)
        selected=filter(r->(r.block,r.dimension)==(block,dimension),rows)
        errors=getproperty.(selected,:error);truth=getproperty.(selected,:truth)
        estimates=getproperty.(selected,:estimate)
        slope=block===:centered_person ? dot(truth,estimates)/sum(abs2,truth) : missing
        intervals=map((.9,.95)) do level
            xs=[only(filter(x->x.level==level,r.intervals)) for r in selected]
            available=filter(x->x.boundary_sensitivity isa Bool,xs)
            (;level,coverage=mean(getproperty.(xs,:covered)),mean_width=mean(getproperty.(xs,:width)),
                boundary_mcse_available=length(available),
                near_endpoint_fraction=isempty(available) ? missing : mean(x.boundary_sensitivity for x in available))
        end
        (;block,dimension,n_parameters=length(selected),mean_signed_error=mean(errors),
            signed_error_structurally_zero=block in (:centered_person,:severity,:step),mse=mean(abs2,errors),
            rmse=sqrt(mean(abs2,errors)),mae=mean(abs,errors),truth_regression_slope=slope,intervals)
    end
end

"""First-order MCSE of panel MSE/RMSE, retaining within-draw person covariance.
Not a bias bound; interval-width precision is checked at individual endpoints.
"""
function person_error_mcse(q,truth;chains=4)
    rows=NamedTuple[]
    for block in (:person,:centered_person),d in 1:2
        indices=findall(r->r.block===block && r.dimension==d,q.roster)
        x=q.draws[:,indices];center=vec(mean(x;dims=1));errors=center-vec(truth.draws[:,indices])
        mse=mean(abs2,errors);influence=2 .* (x .- permutedims(center))*errors/length(indices)
        m=only(B.posterior_mcse(reshape(influence,:,1);chains,
            parameter_names=["panel_mse_influence[$block,D$d]"],probabilities=()))
        push!(rows,(;block,dimension=d,mse,rmse=sqrt(mse),mse_mcse=m.mean_mcse,
            rmse_mcse=mse>0 ? m.mean_mcse/(2sqrt(mse)) : missing,
            interpretation="First-order MCMC approximation, not replication MCSE or a bias bound"))
    end
    return rows
end

function location_moments(target,raw)
    output=zeros(size(raw,1),8)
    for row in axes(raw,1)
        x=raw[row,:];theta=Matrix(reshape(x[1:100],2,50)')
        A=Float64.(target.design.spec.q_matrix).*exp.(x[110:114])
        c=C.location_conditional(theta,A,x[105:109];person_sd=target.prior.person_sd,item_sd=target.prior.item_sd)
        output[row,:]=[c.observed_mean;c.conditional_mean;diag(c.covariance);c.standardized_residual]
    end
    mu,m,v,z=output[:,1:2],output[:,3:4],output[:,5:6],output[:,7:8]
    values=hcat(mu-m,mu.^2-(v+m.^2),z,z.^2 .- 1,z[:,1].*z[:,2])
    names=["mean_difference_D1","mean_difference_D2","second_moment_difference_D1",
        "second_moment_difference_D2","z_D1","z_D2","z_squared_minus_one_D1",
        "z_squared_minus_one_D2","z_product_D1_D2"]
    return (;values,names,conditional_output=output)
end

end
