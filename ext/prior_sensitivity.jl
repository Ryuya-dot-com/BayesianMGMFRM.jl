function plot_prior_sensitivity(result; kind=:interval, annotation_io=stdout,
        size=nothing, bandwidth=nothing, points=256)
    data=B.prior_sensitivity_plot_data(result;bandwidth,points)
    return _render_prior_sensitivity(result,data;kind,annotation_io,size)
end

function _render_prior_sensitivity(result,data;kind=:interval,annotation_io=stdout,size=nothing)
    kind in (:interval,:ridge) || throw(ArgumentError("kind must be :interval or :ridge"))
    offset=_annotation_offset(annotation_io)
    n=length(result.ledger)
    panels=length(data.panels)
    fig=Figure(;size=something(size,(1000,panels*(100+55n)+120offset)),fontsize=15)
    for (i,panel) in enumerate(data.panels)
        desc=panel.descriptor
        labels=[c.prior_id*(c.status===:descriptive ? "" : " [$(c.status)]")*
            (c.marker in (:fixed,:degenerate) ? " [$(c.marker)]" : "") for c in panel.curves]
        positions=collect(n:-1:1)
        xlabel=desc.support===:positive ? "Positive model coordinate" :
            desc.operation===:paired_difference ? "Difference in model coordinates" : "Model coordinate"
        heading=desc.label*(desc.dimension_label===nothing ? "" : " — $(desc.dimension_label)")
        ax=Axis(fig[i+offset,1];title=heading,xlabel,yticks=(positions,labels),
            xgridvisible=false,ygridvisible=false,topspinevisible=false,rightspinevisible=false)
        heights=[maximum(c.density) for c in panel.curves if c.marker===:density]
        peak=isempty(heights) ? 1.0 : maximum(heights)
        for (j,c) in enumerate(panel.curves)
            c.marker===:unavailable && continue
            y=positions[j]
            color=c.status===:warning ? :darkorange3 : :steelblue4
            if kind===:ridge && c.marker===:density
                band!(ax,panel.x,fill(Float64(y),length(panel.x)),y .+ 0.65 .* c.density ./ peak;color=(color,.30))
                lines!(ax,panel.x,y .+ 0.65 .* c.density ./ peak;color,linewidth=1.5)
            end
            c.marker===:fixed || rangebars!(ax,[y],[c.lower],[c.upper];direction=:x,color,whiskerwidth=7,linewidth=2)
            scatter!(ax,[c.median],[y];marker=c.marker===:fixed ? :diamond : :circle,color,markersize=9)
        end
        ref=first(e.evaluation for e in result.ledger if e.evaluation!==nothing).rows[i]
        ref.cutoff===nothing || vlines!(ax,[ref.cutoff];color=:gray40,linestyle=:dash,linewidth=1)
        ylims!(ax,.55,n+(kind===:ridge ? .85 : .5))
    end
    interval="$(round(100result.interval_probability;digits=2))% equal-tailed credible intervals"
    warnings=count(e->e.status===:warning,result.ledger)
    unavailable=count(e->e.evaluation===nothing,result.ledger)
    caption="Dots are medians; bars are $interval. Diamonds are structural constants, not posterior uncertainty. "*
        "Orange rows retain sampling, MCSE or declared precision warnings ($warnings variants); $unavailable unavailable variants remain in the roster. "*
        "Dashed vertical lines, when present, are declared cutoffs. Each panel uses a shared horizontal scale across priors. "*
        "Within-fit contrasts use paired draws; across-prior summary changes do not pair draws. "*
        "The numerical result preserves chain metadata, mean/quantile MCSE and pointwise MCSE decision screens. "*
        "An available MCSE or a stable screen does not establish convergence, calibration or practical equivalence."
    if kind===:ridge
        bandwidths=join(["$(p.descriptor.label): $(p.bandwidth) ($(p.density_coordinate) units)" for p in data.panels],"; ")
        caption*=" Gaussian KDE bandwidths: $bandwidths. Positive coordinates use log-KDE with the inverse Jacobian. "*
            "Curves share a density-height scale within each panel; heights across panels are not comparable. "*
            "The display spans pooled transformed draws plus four bandwidths on either side. Density overlap is not a test."
    end
    caption*=" Dataset: $(result.dataset_id). Saved-result engineering comparison; scientific acceptance is not established."
    return _figure_text!(fig,"Prior sensitivity: $(kind===:ridge ? "posterior densities" : "posterior intervals")",caption;
        annotation_io,bottom_row=panels+2)
end

function save_prior_sensitivity_bundle(directory,result;bandwidth=nothing,points=256)
    (ispath(directory)||islink(directory)) && throw(ArgumentError("destination already exists"))
    data=B.prior_sensitivity_plot_data(result;bandwidth,points)
    mkpath(dirname(abspath(directory)))
    # Use the report bundle's external-note renderer, file hashing and JSON writer.
    mktempdir(dirname(abspath(directory))) do stage
        B.save_prior_sensitivity(joinpath(stage,"result.jls"),result)
        B._write_json_record(joinpath(stage,"result.json"),result)
        B._write_json_record(joinpath(stage,"plot-data.json"),data)
        for kind in (:interval,:ridge)
            io=IOBuffer()
            fig=_render_prior_sensitivity(result,data;kind,annotation_io=io)
            write(joinpath(stage,"$kind-note.txt"),String(take!(io)))
            for suffix in ("pdf","svg","png")
                save(joinpath(stage,"$kind.$suffix"),fig)
            end
        end
        files=Dict(name=>B._fit_report_figure_file_hash(read(joinpath(stage,name))).value for name in B._PRIOR_SENSITIVITY_FILES)
        B._write_json_record(joinpath(stage,"manifest.json"),(;schema="bayesianmgmfrm.prior_sensitivity_bundle.v1",
            result_hash=result.content_hash,files))
        B.load_prior_sensitivity_bundle(stage)
        mv(stage,directory)
    end
    return directory
end
