using BayesianMGMFRM

"""
Prepare the bundled artificial 165-event example without fitting.
The example defaults to its historical reference prior. Pass `prior=:steps`
or `prior=:combined` to inspect the documented alternatives; none is a
generally recommended empirical prior.
Choose `controls` and four distinct `chain_seeds` before calling this function.
Then call `Experimental.ThreeIndicator.fit(plan; directory=...)` explicitly.
"""
function prepare_three_indicator_example(;controls,chain_seeds,prior=:reference)
    T=BayesianMGMFRM.Experimental.ThreeIndicator
    input=joinpath(@__DIR__,"data","three_indicator_165.json")
    checksum="af7aa24174eb601443c017543adb59b01d9109668db5c799568cc032db31e1ba"
    focal=(;panel_label="fixed complete artificial event panel",
        events=collect(1:165),weights=fill(1/165,165),
        speaker_pairs=[(;label="same_cell",left=1,right=2),
            (;label="different_cells",left=1,right=3)],
        listener_pairs=[(;label="pair_1_2_JPN_at_zero",left=1,right=2,l1=2,time=0.),
            (;label="pair_1_3_CHN_at_half",left=1,right=3,l1=3,time=.5)])
    T.prepare(input;expected_sha256=checksum,prior,controls,chain_seeds,focal)
end
