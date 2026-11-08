# Shared finite-point fixtures; not a prior generator or recovery experiment.
function static_fixture(;K=4,shared=false,predictors=true,sparse=false,repeated=false,eta=(2.,.5))
    criteria=[(;criterion=c,levels=1:K,direction=:higher_is_more,
        threshold_group=shared ? "common" : c) for c in ("a","b")]
    rows=[(;observation_id="$p-$t-$o-$r-$c",person="p$p",task="t$t",rater="r$r",
        response_id="$p-$t-$o",rating_event_id="$p-$t-$o-$r",criterion=c,
        score=mod(p+t+r+o+(c=="b"),K)+1,
        intercept=1.,contrast=(p==t ? -1. : 1.))
        for p in 1:3 for t in 1:2 for o in 1:(repeated ? 2 : 1) for r in 1:3 for c in ("a","b")]
    sparse && (rows=rows[[i%5 != 0 for i in eachindex(rows)]])
    reverse!(rows)
    prior=(;task_sd=.8,rater_sd=(.4,.6),step_sd=shared ? (.5,) : (.5,.7),
        response_log_sd_mean=(log(.3),log(.5)),response_log_sd_sd=(.4,.6),
        beta_sd=predictors ? (.9,.5) : (),person_lkj_eta=eta[1],response_lkj_eta=eta[2])
    return S.Target(rows;criteria,prior,predictor_columns=predictors ? (:intercept,:contrast) : ())
end

function static_points(t)
    z=S.initial(t)
    a=.17sin.(1:L.dimension(t));a[t.blocks.log_response_sd].=log.([.2,.7])
    b=copy(a);b[t.blocks.correlation].=[-2.5,2.5]
    c=copy(a);c[t.blocks.beta].=0;c[t.blocks.response_white].=0
    d=copy(a);d[t.blocks.task].=repeat([800.,-800.],t.sizes[2])
    return [z,a,b,c,d]
end
