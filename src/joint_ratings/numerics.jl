module Numerics
import BayesianMGMFRM as B

function _zero_sum(v)
    out = zeros(typeof(zero(eltype(v)) + 0.0), length(v)+1)
    tail = zero(eltype(out))
    for j in length(v):-1:1
        value = v[j]/sqrt(j*(j+1))
        out[j+1] = tail-j*value
        tail += value
    end
    out[1] = tail
    return out
end

function checked_count(value, name; minimum=1)
    value isa Integer && !(value isa Bool) && minimum <= value <= typemax(Int) ||
        throw(ArgumentError("$name must be an integer >= $minimum"))
    return Int(value)
end

function marginal_pcm(location::Real,sd::Real,steps::AbstractVector;atol,maxevals)
    isfinite(location) && isfinite(sd) && sd>0 && length(steps)>=1 && all(isfinite,steps) ||
        throw(ArgumentError("invalid marginal PCM coordinates"))
    atol isa Real && !(atol isa Bool) && isfinite(atol) && 1e-12<=atol<1 ||
        throw(ArgumentError("quadrature atol must be in [1e-12,1)"))
    limit=checked_count(maxevals,"quadrature maxevals")
    H=length(steps);prefix=[0.;cumsum(steps)]
    all(isfinite,prefix) || throw(ArgumentError("unrepresentable cumulative steps"))
    # Splitting at all line crossings helps resolve narrow category peaks.
    knots=Float64[-9,0,9]
    for i in 0:H-1,j in i+1:H
        crossing=((prefix[j+1]-prefix[i+1])/(j-i)-location)/sd
        isfinite(crossing) && -9<crossing<9 && push!(knots,crossing)
    end
    sort!(unique!(knots));evaluations=Ref(0)
    integrand=z->begin
        evaluations[]+=1
        evaluations[]>limit && throw(ArgumentError("quadrature evaluation budget exhausted"))
        p=B._ld1_pcm_probabilities(location+sd*z,steps)
        [p;cumsum(p)[1:end-1]].*(exp(-z^2/2)/sqrt(2pi))
    end
    # Use the declared quadrature dependency without requiring a sampling backend.
    values,error=B.QuadGK.quadgk(integrand,knots...;
        atol=Float64(atol)/2,rtol=0.0,maxevals=limit,norm=v->maximum(abs,v))
    tail=2B.Distributions.ccdf(B.Distributions.Normal(),9.0)
    estimated_error=error+tail
    isfinite(estimated_error) && estimated_error<=atol && all(isfinite,values) &&
        all(v->-atol<=v<=1+atol,values) && abs(sum(values[1:H+1])-1)<=atol ||
        throw(ArgumentError("marginal probability quadrature tolerance not met"))
    return (;values,estimated_error,evaluations=evaluations[],tail_bound=tail,
        method=:adaptive_gauss_kronrod_with_normal_tail_bound)
end
end
