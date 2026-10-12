# Saved simulation example: no new sampling or scientific replication.
module PriorSensitivityExample
using BayesianMGMFRM, Serialization, SHA, JSON3
const B=BayesianMGMFRM
function run_saved_example(repository, output)
    study=joinpath(repository,"results/workflows/20261004-foundation-fixed-facet-assessment-01")
    # Select the first planned block in panel R1 before reading its results.
    ids=["B01-R1-025","B01-R1-050","B01-R1-100"]
    labels=["Loading prior SD = 0.25","Loading prior SD = 0.50","Loading prior SD = 1.00"]
    fits=Pair[];sources=NamedTuple[]
    for (id,label) in zip(ids,labels)
        path=joinpath(study,"attempts",id,"samples.jls")
        record=deserialize(path) # Local trusted records only.
        println("Validating saved fit ",id);flush(stdout)
        fit=B.Experimental.NormalizedMGMFRMFit(record;expected_identity=record.target_identity)
        push!(fits,label=>fit)
        push!(sources,(;id,path=relpath(path,repository),sha256=bytes2hex(open(sha256,path)),
            sample_content_hash=record.content_hash,target_identity=record.target_identity))
    end
    spec=last(first(fits)).record.spec
    dimension=spec.dimension_labels[1]
    estimands=["Item I1 loading"=>"item_dimension_discrimination[item=I1,$dimension]",
        "Ability P1 minus P2"=>("person[P1,$dimension]","person[P2,$dimension]"),
        "Severity R1 minus R2"=>("rater[R1]","rater[R2]")]
    println("Summarizing saved draws");flush(stdout)
    result=B.prior_sensitivity(fits;planned_prior_ids=labels,estimands,
        dataset_id="foundation-fixed-facet/B01-R1",
        observation_ids=["B01-R1-rating-$i" for i in 1:spec.data.n],interval=.90,
        cutoffs=Dict("Ability P1 minus P2"=>0.,"Severity R1 minus R2"=>0.))
    mkpath(output)
    B.save_prior_sensitivity(joinpath(output,"result.jls"),result)
    open(joinpath(output,"sources.json"),"w") do io
        JSON3.pretty(io,(;sources,selection=:first_planned_block_panel_R1,
        original_assessment=(;planned_fits=192,completed_fits=192,qualified_fits=184),
        new_fits=0,new_replications=0,scientific_acceptance=false))
    end
    return result
end
end
