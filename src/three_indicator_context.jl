# Call only after the input and focal definitions have been validated.
function _listener_support(data, focal)
    rows=NamedTuple[]
    for pair in focal.listener_pairs, side in (:left,:right)
        r=pair[side]
        positions=[data.within_time[n] for n in 1:data.N if data.rater[n]==r && data.l1[n]==pair.l1]
        count=length(positions)
        lower,upper=isempty(positions) ? (nothing,nothing) : extrema(positions)
        push!(rows,(;contrast=String(pair.label),side,listener=r,
            listener_label=String(data.labels.rater[r]),l1=pair.l1,time=pair.time,
            observations=count,lower,upper,status=_support_status(count,lower,upper,pair.time)))
    end
    rows
end
_support_status(n,lo,hi,t) = n==0 ? :unobserved_context :
    lo<=t<=hi ? :within_observed_range : :outside_observed_range

function _support_warnings(rows)
    warnings=String[]
    for r in rows
        if Symbol(r.status)===:unobserved_context
            push!(warnings,"Listener contrast $(r.contrast), $(r.side) listener $(r.listener_label): no observations for L1 $(r.l1); position support is unobserved.")
        elseif Symbol(r.status)===:outside_observed_range
            push!(warnings,"Listener contrast $(r.contrast), $(r.side) listener $(r.listener_label): position $(r.time) is outside the observed L1 $(r.l1) range [$(r.lower), $(r.upper)]; this is linear-trend extrapolation.")
        end
    end
    warnings
end
_support_view(rows) = (;status=:recorded,scope=:listener_l1_position_range,
    rows=[(;contrast=String(r.contrast),side=Symbol(r.side),listener=r.listener,
        listener_label=String(r.listener_label),l1=r.l1,time=r.time,
        observations=r.observations,lower=r.lower,upper=r.upper,status=Symbol(r.status)) for r in rows])

function _check_listener_support(x)
    rows=x.listener_support
    _require(rows isa AbstractVector && length(rows)==2length(x.focal_definitions.listener_pairs),
        "incomplete listener position support")
    for (i,pair) in enumerate(x.focal_definitions.listener_pairs), (j,side) in enumerate((:left,:right))
        r=rows[2i-2+j]
        _fields(r,(:contrast,:side,:listener,:listener_label,:l1,:time,:observations,:lower,:upper,:status))
        _require(r.contrast==pair.label && r.side==String(side) &&
            _integer(r.listener) && r.listener==pair[side] &&
            r.listener_label==x.labels.rater[r.listener] &&
            _integer(r.l1) && r.l1==pair.l1 && _finite(r.time) && r.time==pair.time,
            "listener position support and focal context differ")
        _require(_integer(r.observations) && 0<=r.observations<=length(x.labels.event),
            "invalid listener support count")
        _require(r.observations==0 ? r.lower===nothing && r.upper===nothing :
            _finite(r.lower) && _finite(r.upper) && r.lower<=r.upper &&
            (r.observations!=1 || r.lower==r.upper),"invalid observed position range")
        _require(r.status==String(_support_status(r.observations,r.lower,r.upper,r.time)),
            "listener position support status differs")
    end
    rows
end
