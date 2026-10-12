module MGMFRMNormalizedLocation

# Compatibility entry points for existing research callers; the package owns the implementation.
using BayesianMGMFRM
const B = BayesianMGMFRM
const LocationTarget = B._MGMFRMNormalizedLocationLogDensity
const to_raw = B._mgmfrm_location_to_raw
const from_raw = B._mgmfrm_location_from_raw

function sample(raw::B._MGMFRMNormalizedPriorLogDensity;
        init=B.initial_params(raw), kwargs...)
    return B._mgmfrm_normalized_prior_sample(raw, init;
        sampling_coordinates=:orthogonal_person_mean_item_offset, kwargs...)
end

end
