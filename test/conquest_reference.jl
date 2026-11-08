using Test, BayesianMGMFRM, JSON3, LinearAlgebra, SHA

# The preceding bridge test supplies deterministic table/result-file helpers.
# These complete bundles are artificial; the parameter/design bytes are retained
# ConQuest outputs, not a recreation of the original executed datasets.
const CONQUEST_REFERENCE_RECORDS = NamedTuple[]
const CONQUEST_REFERENCE_ERRORS = NamedTuple[]
@testset "ConQuest point-coordinate alignment" begin
    fixture = joinpath(@__DIR__, "fixtures", "conquest_5_47_5")
    expectations = JSON3.read(read(joinpath(fixture, "expectations.json"), String))
    table = _bridge_test_semantic_table()
    data = FacetData(table; person=:person, rater=:rater, item=:item, score=:score)
    for (name, regime) in (("rsm", :rating_scale), ("pcm", :partial_credit))
        spec = mfrm_spec(data; thresholds=regime)
        design = getdesign(spec)
        expected = getproperty(expectations.models, Symbol(name))
        parameter_path = joinpath(fixture, name * "_parameters.txt")
        matrix_path = joinpath(fixture, name * "_designmatrix.csv")
        @test bytes2hex(sha256(read(parameter_path))) == expected.files.parameters
        @test bytes2hex(sha256(read(matrix_path))) == expected.files.designmatrix
        matrix = _bridge_test_design_matrix(matrix_path).matrix
        free = [r.value for r in load_conquest_parameter_export(parameter_path)]
        source_offsets = reshape(matrix * free, 3, 12)
        bundle = conquest_bridge_bundle(spec; title="Reference gauge fixture " * name)
        mktempdir() do directory
            save_external_bridge_bundle(directory, bundle)
            _bridge_test_populate_semantic_results(directory, bundle, spec,
                read(parameter_path, String), read(matrix_path, String))
            kwargs = (; expected_bundle_id=bundle.bundle_id,
                software_version="5.47.5", executable_sha256=repeat("a",64),
                executed_at_utc="2026-07-21T12:56:07Z")
            mapped = BayesianMGMFRM.load_conquest_reference_parameters(directory, design; kwargs...)
            source = load_conquest_semantic_parameters(directory, spec; kwargs...)
            @test isequal(mapped.source, source)
            @test mapped.source.content_hash == artifact_content_hash(source)
            @test mapped.content_hash == artifact_content_hash(mapped)
            @test !source.destination_gauge_aligned
            @test mapped.destination_gauge_aligned
            @test mapped.conditional_prediction_coordinates_ready
            @test !mapped.destination_parameter_vector_ready
            @test !mapped.person_estimates_available
            @test !mapped.uncertainty_transformed
            @test !mapped.prior_equivalence_established
            @test !mapped.anchor_candidate_ready
            @test !mapped.convergence_validated
            @test !mapped.numerical_comparison_allowed
            @test !mapped.software_equivalence_claimed
            @test mapped.rater_values[1] == mapped.item_values[1] == 0.0
            @test mapped.destination_gauge.rater_reference == first(data.rater_levels)
            @test mapped.destination_gauge.item_reference == first(data.item_levels)
            @test mapped.threshold_values == source.threshold_values
            @test mapped.ability_shift ≈ (name == "rsm" ? 1.11884 : 0.93482) atol=1e-12
            @test length(mapped.parameter_rows) == source.n_semantic_rows
            @test all(r -> r.value == r.source_value - r.reference_value, mapped.parameter_rows)
            for block in (:rater_values, :item_values)
                original = getproperty(source, block); aligned = getproperty(mapped, block)
                @test [a-b for a in aligned, b in aligned] ≈ [a-b for a in original, b in original]
            end
            @test Set(keys(design.blocks)) == Set((:person,:rater,:item,:thresholds))
            params = zeros(length(design.parameter_names))
            params[design.blocks[:rater]] .= mapped.rater_values[2:end]
            params[design.blocks[:item]] .= mapped.item_values[2:end]
            params[design.blocks[:thresholds]] .= regime === :rating_scale ?
                [first(mapped.threshold_values)] : [first(s) for s in mapped.threshold_values]
            max_logit_error = max_probability_error = max_loglikelihood_error = 0.0
            for theta in (-1000.0, -8.0, -1.0, 0.0, 0.6, 8.0, 1000.0)
                params[design.blocks[:person]] .= theta + mapped.ability_shift
                values = linear_predictor_values(design, params)
                expected_ll = zeros(data.n)
                for row in 1:data.n
                    gin = (data.item[row]-1)*3 + data.rater[row]
                    eta = source_offsets[:,gin] + [0.0,theta,2theta]
                    normalizer = maximum(eta) + log(sum(exp.(eta .- maximum(eta))))
                    logp = eta .- normalizer
                    native = values[(3row-2):(3row)]
                    native_eta = [v.eta for v in native]
                    native_p = exp.([v.log_probability for v in native])
                    @test native_eta ≈ eta atol=1e-11 rtol=0
                    @test native_p ≈ exp.(logp) atol=1e-12 rtol=0
                    @test sum(native_p) ≈ 1.0 atol=1e-12
                    expected_ll[row] = logp[data.category[row]]
                    max_logit_error = max(max_logit_error, maximum(abs.(native_eta-eta)))
                    max_probability_error = max(max_probability_error, maximum(abs.(native_p-exp.(logp))))
                end
                native_ll = pointwise_loglikelihood(design,params)
                @test native_ll ≈ expected_ll atol=1e-11 rtol=0
                max_loglikelihood_error = max(max_loglikelihood_error,maximum(abs.(native_ll-expected_ll)))
            end
            params[design.blocks[:person]] .= 0.0 # deliberately omit ability shift
            unshifted = linear_predictor_values(design,params)
            eta = source_offsets[:,1]
            p = exp.(eta .- maximum(eta)); p ./= sum(p)
            omitted_shift_error = maximum(abs.(exp.([v.log_probability for v in unshifted[1:3]])-p))
            @test omitted_shift_error > 0.15
            # The first-reference free-coordinate map is not a unit-Jacobian map.
            # Source free coordinates exclude the last level; destination excludes first.
            for n in (3,4)
                contrast = vcat(Matrix{Float64}(I,n-1,n-1), -ones(1,n-1))
                transform = contrast[2:end,:] .- contrast[1:1,:]
                @test abs(det(transform)) ≈ n
            end
            @test_throws ArgumentError BayesianMGMFRM.load_conquest_reference_parameters(
                directory,spec; kwargs..., software_version="5.47.6")
            @test_throws ArgumentError BayesianMGMFRM.load_conquest_reference_parameters(
                directory,spec; kwargs...,expected_bundle_id="sha256:" * repeat("0",64))
            opposite = mfrm_spec(data; thresholds=regime === :rating_scale ? :partial_credit : :rating_scale)
            @test_throws ArgumentError BayesianMGMFRM.load_conquest_reference_parameters(directory,opposite;kwargs...)
            binary_data = FacetData(merge(table,(;score=min.(table.score,1)));
                person=:person,rater=:rater,item=:item,score=:score)
            binary_spec = mfrm_spec(binary_data;thresholds=regime)
            @test_throws ArgumentError BayesianMGMFRM.load_conquest_reference_parameters(directory,binary_spec;kwargs...)
            anchored = mfrm_spec(data;thresholds=regime,anchors=[(;
                block=:rater,level=first(data.rater_levels),value=0.0,type=:hard)])
            @test_throws ArgumentError BayesianMGMFRM.load_conquest_reference_parameters(directory,anchored;kwargs...)
            push!(CONQUEST_REFERENCE_RECORDS, mapped)
            push!(CONQUEST_REFERENCE_ERRORS, (;model=name, max_logit_error,
                max_probability_error,max_loglikelihood_error,omitted_shift_error,
                parameter_export_sha256=expected.files.parameters,
                design_matrix_sha256=expected.files.designmatrix))
            # The new loader reuses exact input binding; changed output comments fail.
            path = joinpath(directory,"results","conquest_parameters.txt")
            write(path,replace(read(path,String),"raterid R000001"=>"raterid WRONG01"))
            @test_throws ArgumentError BayesianMGMFRM.load_conquest_reference_parameters(directory,spec;kwargs...)
        end
    end
end
