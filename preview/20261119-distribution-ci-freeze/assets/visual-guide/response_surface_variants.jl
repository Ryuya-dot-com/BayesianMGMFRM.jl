using BayesianMGMFRM, CairoMakie

function response_surface_comparison_board(data)
    category = first(data).category
    columns = min(3, length(data))
    rows = cld(length(data), columns)
    figure = Figure(size = (460columns + 100, 440rows), fontsize = 20)
    for (index, surface) in enumerate(data)
        active = join(["θ$d" for d in 1:2 if surface.active_dimensions[d]], ", ")
        axis = Axis3(figure[cld(index, columns), mod1(index, columns)];
            title = "$(surface.item) · $(surface.rater)\nActive: $active",
            xlabel = "θ₁", ylabel = "θ₂", zlabel = "P(rating = $category)",
            xticks = range(first(surface.x), last(surface.x); length = 3),
            yticks = range(first(surface.y), last(surface.y); length = 3), zticks = [0, 0.5, 1],
            azimuth = 1.275pi, elevation = pi / 7,
            protrusions = (75, 35, 55, 65), yticklabelpad = 12, zticklabelpad = 8,
            limits = (first(surface.x), last(surface.x), first(surface.y), last(surface.y), 0, 1))
        surface!(axis, surface.x, surface.y, surface.mean;
            colormap = :viridis, colorrange = (0, 1), shading = NoShading)
    end
    Colorbar(figure[1:rows, columns + 1]; colormap = :viridis,
        limits = (0, 1), ticks = [0, 0.5, 1], label = "Posterior mean probability")
    return figure
end

"""
    response_surface_variants(fit; items, raters, category,
        x = range(-2, 2; length = 21), y = range(-2, 2; length = 21),
        interval = 0.90, annotation_io = stdout)

Compare a single rating category in a two-ability MGMFRM fit, using every saved
joint draw. The item board fixes the first supplied rater; the rater board fixes
the first supplied item. List labels in the desired panel order. Both boards
use the same ability grid, viewing angle and probability scale (0–1).

Returns editable `items` and `raters` Figures, `item_data`, `rater_data` and
external `item_note`/`rater_note` text. Data include pointwise interval endpoints;
the images show posterior means only, not uncertainty or tests of differences.
Notes are printed outside the images by default; use a writable IO to save them.
This is a downloadable example, not a new package plotting API.
"""
function response_surface_variants(fit::MGMFRMFit; items, raters, category,
    x = range(-2, 2; length = 21), y = range(-2, 2; length = 21),
    interval = 0.90, annotation_io = stdout)
    annotation_io isa IO && iswritable(annotation_io) ||
        throw(ArgumentError("annotation_io must be a writable IO stream"))
    category isa Integer && !(category isa Bool) ||
        throw(ArgumentError("category must be one integer rating category"))
    item_labels, rater_labels = collect(items), collect(raters)
    for (name, labels) in (("items", item_labels), ("raters", rater_labels))
        !isempty(labels) && length(unique(string.(labels))) == length(labels) ||
            throw(ArgumentError("$name must be nonempty and contain unique labels"))
    end
    options = (; dimensions = (1, 2), x, y, category, interval)
    item_data = [BayesianMGMFRM.item_response_surface(fit;
        item, rater = first(rater_labels), options...) for item in item_labels]
    # The common reference panel is the same numerical object in both boards.
    rater_data = [first(item_data); [BayesianMGMFRM.item_response_surface(fit;
        item = first(item_labels), rater, options...) for rater in rater_labels[2:end]]]


    reference = first(item_data)
    common = "Rating $category; all $(reference.n_draws) retained joint draws. " *
        "Ability axes: $(join(reference.dimension_labels, ", ")); no additional fixed abilities. " *
        "Grid: $(first(reference.x)) to $(last(reference.x)) ($(length(reference.x)) points) × " *
        "$(first(reference.y)) to $(last(reference.y)) ($(length(reference.y)) points). " *
        "Height and color show posterior mean probability on the same 0–1 scale in every panel. " *
        "An inactive Q dimension is flat by construction. Display ranges do not establish data support. " *
        "Images omit uncertainty; numerical data retain $(100interval)% pointwise credible intervals " *
        "for each conditional probability, not intervals for future ratings or between-panel differences. " *
        "$(reference.diagnostic)"
    item_note = "Item Comparison at Rater $(first(rater_labels))\n\nNote. " *
        "Items: $(join(item_labels, ", ")). Rater $(first(rater_labels)) is fixed. " * common *
        " Item differences can reflect difficulty, category steps, loadings and Q, not difficulty alone."
    rater_note = "Rater Comparison at Item $(first(item_labels))\n\nNote. " *
        "Raters: $(join(rater_labels, ", ")). Item $(first(item_labels)) is fixed. " * common *
        " Rater differences reflect severity and consistency; these panels do not establish bias or rater quality."
    item_figure, rater_figure = response_surface_comparison_board(item_data), response_surface_comparison_board(rater_data)
    println(annotation_io, item_note, "\n\n", rater_note)
    return (; items = item_figure, raters = rater_figure, item_data, rater_data, item_note, rater_note)
end
