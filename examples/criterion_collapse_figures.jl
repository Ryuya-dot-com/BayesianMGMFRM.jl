module CriterionCollapseFiguresExample
using BayesianMGMFRM,CairoMakie
const C=BayesianMGMFRM.Experimental.CriterionCollapse
"""Render saved computed reports; no native draws, fitting or prediction RNG."""
function main(args=ARGS)
    length(args)==5 || error("Usage: criterion_collapse_figures.jl OUTPUT CLASS_REPORT CLASS_SHA256 CATEGORY_REPORT CATEGORY_SHA256")
    out=args[1];ispath(out) && error("Preserve existing output: $out")
    classes=C.load_report(args[2];expected_sha256=args[3])
    categories=C.load_report(args[4];expected_sha256=args[5])
    classes.target_identity==categories.target_identity &&
        classes.source_sample_content_hash==categories.source_sample_content_hash ||
        error("Class and category reports must refer to the same target and fitted samples.")
    mkpath(out)
    cp(args[2],joinpath(out,"class-report.json"))
    cp(args[4],joinpath(out,"category-report.json"))
    open(joinpath(out,"sources.txt"),"w") do io
        println(io,"Target identity: ",classes.target_identity)
        println(io,"Source sample content hash: ",classes.source_sample_content_hash)
        println(io,"Class-report SHA-256: ",args[3])
        println(io,"Category-report SHA-256: ",args[5])
        println(io,"Figures use stored computed means, MCSE and warnings. No estimation or diagnostic recomputation.")
    end
    function render(name,draw)
        note=IOBuffer();figure=draw(note)
        save(joinpath(out,name*".png"),figure)
        save(joinpath(out,name*".svg"),figure)
        write(joinpath(out,name*".txt"),String(take!(note)))
        figure
    end
    render("classes",io->C.plot_classes(classes;annotation_io=io))
    for (j,rater) in enumerate(classes.labels.rater)
        # Filenames use indices so arbitrary user labels cannot become paths.
        render("rater-$j-categories",io->C.plot_categories(categories;rater,annotation_io=io))
    end
    println("Saved class and category figures with their full notes and source reports to ",out)
    nothing
end
end
abspath(PROGRAM_FILE)==abspath(@__FILE__) && CriterionCollapseFiguresExample.main()
