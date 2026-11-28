# persistence_and_summaries.jl -- Markdown/bundle/dossier persistence, native fit cache, and posterior summaries/MCSE.

function _fit_report_markdown_hash_record(markdown::AbstractString)
    return (;
        algorithm = :sha256,
        value = bytes2hex(sha256(IOBuffer(String(markdown)))),
        scope = :fit_report_markdown,
        canonicalization = :raw_markdown_string,
        n_canonical_bytes = sizeof(markdown),
    )
end

function _markdown_plain_value(value)
    value === missing && return ""
    value === nothing && return ""
    value isa Symbol && return String(value)
    value isa AbstractString && return String(value)
    value isa Bool && return string(value)
    value isa Number && return string(value)
    json_value = _json_export_value(value)
    if json_value isa AbstractString
        return String(json_value)
    end
    return JSON3.write(json_value)
end

function _markdown_cell(value; max_cell_chars::Int = 96)
    text = replace(_markdown_plain_value(value), '\n' => " ")
    text = replace(text, '\r' => " ")
    text = replace(text, "|" => "\\|")
    if max_cell_chars > 0 && lastindex(text) > max_cell_chars
        return string(first(text, max_cell_chars), "...")
    end
    return text
end

# Shared display order: identifiers, sampler coverage, estimates and uncertainty.
# JSON object key order is not a column schema; unlisted fields sort by name.
const _MARKDOWN_COLUMN_ORDER = (
    :model, :family, :section, :parameter, :parameter_space, :block, :facet,
    :person, :item, :rater, :dimension, :dimension_label, :level, :category,
    :contrast, :term, :group,
    :phase, :backend, :sampler, :chain, :expected_iterations, :observed_iterations,
    :coverage, :n_divergences, :n_max_treedepth, :n_nonfinite_logdensity, :n_nonfinite_proposals,
    :estimate, :mean, :sd, :median, :lower, :upper, :lower_probability,
    :upper_probability, :rhat, :rank_normalized_rhat, :ess, :bulk_ess, :tail_ess,
    :status, :flag,
)

function _markdown_row_fields(rows, max_rows::Int)
    fields = Symbol[]
    seen = Set{Symbol}()
    for row in Iterators.take(rows, max_rows)
        for field in _report_keys(row)
            field in seen && continue
            push!(fields, field)
            push!(seen, field)
        end
    end
    return sort!(fields; by = field -> (
        something(findfirst(==(field), _MARKDOWN_COLUMN_ORDER),
            length(_MARKDOWN_COLUMN_ORDER) + 1), String(field)))
end

const _PUBLIC_MARKDOWN_HIDDEN_FIELDS = Set((
    :blocked_option,
    :blocker,
    :caveat_docs_artifact,
    :experimental_public,
    :fixture_provenance,
    :guarded_local_fit,
    :internal_sampler_diagnostic_constructor,
    :internal_target_constructor,
    :manuscript_claims_allowed,
    :next_gate,
    :package_default_change,
    :publication_or_registration_action,
    :public_claim_allowed,
    :supported_surface,
))

const _PUBLIC_MARKDOWN_STRUCTURED_FIELDS = Set((
    :step_path,
    :threshold_path,
))

function _public_markdown_field_allowed(field::Symbol, path::Tuple = ())
    _public_fit_report_projection_field_allowed(field, path) || return false
    # Keep the finite-panel diagnostic preview readable; JSON/tables retain
    # the complete diagnostic method and chain metadata.
    path === (:diagnostics, :location_rows) && return field in
        (:parameter, :dimension_label, :rank_normalized_rhat, :bulk_ess, :tail_ess, :flag)
    field in _PUBLIC_MARKDOWN_HIDDEN_FIELDS && return false
    name = String(field)
    startswith(name, "internal_") && return false
    occursin("fixture", name) && return false
    occursin("next_gate", name) && return false
    endswith(name, "_path") && field ∉ _PUBLIC_MARKDOWN_STRUCTURED_FIELDS &&
        return false
    return true
end

_public_markdown_scalar(value) =
    value === missing || value === nothing || value isa Symbol ||
    value isa AbstractString || value isa Bool || value isa Number

function _public_markdown_value(value, field::Symbol, path::Tuple)
    if _public_fit_report_user_value_field(field) ||
            field in _PUBLIC_MARKDOWN_STRUCTURED_FIELDS
        projected = _public_fit_report_project_value(value;
            preserve_user_text = _public_fit_report_user_value_field(field),
            path = (path..., field))
        projected === _PUBLIC_FIT_REPORT_OMITTED &&
            return "Implementation detail omitted."
        return _markdown_plain_value(projected)
    end
    _public_markdown_scalar(value) || return "See the structured report."
    text = _public_fit_report_sanitized_text(_markdown_plain_value(value))
    text === _PUBLIC_FIT_REPORT_OMITTED &&
        return "Implementation detail omitted."
    if occursin(r"(?:^|[^A-Za-z0-9])_[A-Za-z][A-Za-z0-9_!]*", text)
        return "Implementation detail omitted."
    end
    if occursin(r"(?:file://|/(?:Users|home|tmp)/|/private/tmp/|[A-Za-z]:[\\/]+Users[\\/]+)", text)
        return "Environment path omitted."
    end
    if occursin(r"(?:test/fixtures/|scripts/generate_)", text)
        return "Repository detail omitted."
    end
    if occursin(r"\b(?:blocked_option|supported_surface|next_gate|internal_target_constructor|internal_sampler_diagnostic_constructor|manual_publication_or_registration_by_user_only)\b",
            text)
        return "Implementation detail omitted."
    end
    return text
end

function _public_markdown_effective_field(row, field::Symbol)
    field === :value || return field
    semantic_field = _report_symbol_value(
        _report_lookup(row, :field, _FIT_REPORT_LOOKUP_MISSING))
    return semantic_field isa Symbol ? semantic_field : field
end

function _public_markdown_displayable(value, field::Symbol)
    return _public_markdown_scalar(value) ||
        field in _PUBLIC_MARKDOWN_STRUCTURED_FIELDS ||
        _public_fit_report_user_value_field(field)
end

function _public_markdown_fields(rows, fields, path::Tuple)
    row_vector = collect(rows)
    return [field for field in fields
            if _public_markdown_field_allowed(field, path) &&
            all(row -> begin
                    effective_field = _public_markdown_effective_field(row, field)
                    _public_markdown_displayable(
                        _report_lookup(row, field, missing), effective_field)
                end, row_vector)]
end

function _write_markdown_table(io::IO, rows;
        fields = nothing,
        max_rows::Int = 6,
        max_cell_chars::Int = 96,
        public_view::Bool = false,
        path::Tuple = ())
    row_vector = collect(rows)
    display_rows = collect(Iterators.take(row_vector, max_rows))
    resolved_fields = fields === nothing ?
        _markdown_row_fields(display_rows, max(1, length(display_rows))) :
        collect(fields)
    public_view &&
        (resolved_fields = _public_markdown_fields(
            display_rows, resolved_fields, path))
    if isempty(resolved_fields)
        println(io, "*No rows to preview.*")
        return
    end
    header_cells = [String(field) for field in resolved_fields]
    println(io, "| ", join(header_cells, " | "), " |")
    println(io, "| ", join(fill("---", length(resolved_fields)), " | "), " |")
    for row in display_rows
        cells = [
            _markdown_cell(public_view ?
                _public_markdown_value(
                    _report_lookup(row, field, missing),
                    _public_markdown_effective_field(row, field),
                    path) :
                _report_lookup(row, field, missing);
                max_cell_chars = max_cell_chars)
            for field in resolved_fields
        ]
        println(io, "| ", join(cells, " | "), " |")
    end
    if length(row_vector) > length(display_rows)
        println(io)
        println(io, "*", length(row_vector) - length(display_rows),
            " additional row(s) omitted.*")
    end
    return
end

function _fit_report_metadata_rows(report)
    fields = (:schema, :object, :created_at, :family, :thresholds,
        :dimensions, :dimension_labels, :estimation_status, :status,
        :report_status)
    rows = NamedTuple[]
    for field in fields
        value = _report_lookup(report, field, _FIT_REPORT_LOOKUP_MISSING)
        value === _FIT_REPORT_LOOKUP_MISSING && continue
        push!(rows, (; field, value = _report_symbol_value(value)))
    end
    metadata = _report_lookup(report, :metadata, nothing)
    for field in (:model_label, :backend_label, :scale_convention, :target_identity,
            :source_sample_schema, :source_sample_content_hash)
        value = _report_lookup(metadata, field, _FIT_REPORT_LOOKUP_MISSING)
        value === _FIT_REPORT_LOOKUP_MISSING && continue
        push!(rows, (; field, value = _report_symbol_value(value)))
    end
    return rows
end

function _fit_report_warning_rows(report)
    rows = NamedTuple[]
    for section_name in _FIT_REPORT_SECTION_ORDER
        section = _report_lookup(report, section_name,
            _FIT_REPORT_LOOKUP_MISSING)
        section === _FIT_REPORT_LOOKUP_MISSING && continue
        warning_rows = _report_lookup(section, :warning_rows,
            _FIT_REPORT_LOOKUP_MISSING)
        warning_rows isa AbstractVector || continue
        for row in warning_rows
            push!(rows, (;
                section = section_name,
                code = _report_symbol_value(
                    _report_lookup(row, :code, missing)),
                severity = _report_symbol_value(
                    _report_lookup(row, :severity, :warning)),
                n_coordinates = _report_lookup(
                    row, :n_coordinates, missing),
                n_affected_rows = _report_lookup(
                    row,
                    :n_affected_rows,
                    _report_lookup(row, :n_coordinates, missing),
                ),
                message = _report_lookup(row, :message, missing),
                action = _report_symbol_value(
                    _report_lookup(row, :action, missing)),
            ))
        end
    end
    return rows
end

"""
    fit_report_markdown(report; title = "BayesianMGMFRM fit report",
        max_rows = 6, include_empty = false)

Render a portable Markdown review draft from a `fit_report` payload. The output
includes report metadata, a prominent warning summary when a section supplies
warning rows, section status/row counts, and table previews for each tabular
row field. `report` may be the in-memory `NamedTuple` returned by
[`fit_report`](@ref) or a JSON-loaded payload from [`load_fit_report`](@ref).
Table columns use the same display order in both forms: identifiers, sampler
coverage, estimates and uncertainty first, followed by other columns by name.
Empty row fields remain visible in the section summary but their table previews
are omitted by default; set `include_empty = true` to render an explicit
zero-row preview. JSON, table, and bundle exports retain empty row fields
regardless of this Markdown presentation choice.
"""
function fit_report_markdown(report;
        title::AbstractString = "BayesianMGMFRM fit report",
        max_rows::Integer = 6,
        include_empty::Bool = false)
    max_rows >= 0 ||
        throw(ArgumentError("max_rows must be non-negative"))
    _check_fit_report_payload(report)
    io = IOBuffer()
    println(io, "# ", title)
    println(io)
    report_schema = _report_lookup(report, :schema, missing)
    println(io, "Generated from `", report_schema, "`.")
    println(io)
    report_hash = _fit_report_content_hash_record(report)
    println(io, "- Report content hash: `", report_hash.value, "`")
    println(io, "- Markdown preview rows per table: ", max_rows)
    println(io)
    println(io, "## Report Metadata")
    println(io)
    _write_markdown_table(io, _fit_report_metadata_rows(report);
        fields = (:field, :value),
        max_rows = typemax(Int),
        max_cell_chars = 160,
        public_view = true,
        path = (:metadata_table,))
    println(io)
    interpretation = _report_lookup(report, :interpretation, nothing)
    if interpretation !== nothing
        println(io, _public_markdown_value(interpretation, :interpretation, ()))
        println(io)
    end
    warning_rows = _fit_report_warning_rows(report)
    if !isempty(warning_rows)
        println(io, "## Warnings")
        println(io)
        _write_markdown_table(io, warning_rows;
            fields = (:section, :code, :severity, :n_affected_rows, :message,
                :action),
            max_rows = typemax(Int),
            max_cell_chars = 240,
            public_view = true,
            path = (:warning_summary,))
        println(io)
    end
    println(io, "## Section Summary")
    println(io)
    _write_markdown_table(io, fit_report_sections(report);
        fields = (:section, :status, :n_rows),
        max_rows = typemax(Int),
        max_cell_chars = 160,
        public_view = true,
        path = (:section_summary,))
    println(io)
    println(io, "## Table Previews")
    sections = fit_report_sections(report)
    wrote_preview = false
    for section in sections
        content = fit_report_section(report, section.section)
        # Do not capture a potentially large embedded artifact in a generator.
        notes = Tuple{Symbol,Any}[]
        for field in (:interpretation, :reason, :message)
            value = _report_lookup(content, field, nothing)
            value === nothing || push!(notes, (field, value))
        end
        if !isempty(notes)
            wrote_preview = true
            println(io, "\n### ", String(section.section), "\n")
            for (field, value) in notes
                println(io, _public_markdown_value(value, field, (section.section,)), "\n")
            end
        end
        for row_field in section.row_fields
            rows = fit_report_rows(report, section.section; row_field)
            if isempty(rows) && !include_empty
                continue
            end
            wrote_preview = true
            println(io)
            println(io, "### ", String(section.section), " / ", String(row_field))
            println(io)
            println(io, "- Rows: ", length(rows))
            println(io, "- Preview rows: ", min(length(rows), Int(max_rows)))
            println(io)
            _write_markdown_table(io, rows;
                max_rows = Int(max_rows),
                max_cell_chars = 120,
                public_view = true,
                path = (section.section, row_field))
        end
    end
    if !wrote_preview
        println(io)
        println(io, "*No tabular report rows are available.*")
    end
    return String(take!(io))
end

function _fit_report_markdown_export_record(path::AbstractString,
        report,
        markdown::AbstractString;
        label = nothing,
        title::AbstractString,
        max_rows::Integer,
        include_empty::Bool)
    location = _is_public_fit_report(report) ? NamedTuple() : (;
        source_path = String(path),
    )
    return merge((;
        schema = "bayesianmgmfrm.fit_report_markdown_export.v1",
        object = :fit_report_markdown_export,
        created_at = string(now()),
        label = label === nothing ? missing : label,
    ), location, (;
        report_schema = _report_lookup(report, :schema, missing),
        report_object = _report_symbol_value(_report_lookup(report, :object, missing)),
        report_content_hash = _fit_report_content_hash_record(report),
        markdown_content_hash = _fit_report_markdown_hash_record(markdown),
        format = :markdown,
        title = String(title),
        max_rows = Int(max_rows),
        include_empty,
        n_bytes = sizeof(markdown),
    ))
end

"""
    save_fit_report_markdown(path, report; overwrite = false,
        title = "BayesianMGMFRM fit report", max_rows = 6,
        include_empty = false, label = nothing, require_complete = false)
    save_fit_report_markdown(path, fit; overwrite = false,
        title = "BayesianMGMFRM fit report", max_rows = 6,
        include_empty = false, label = nothing, require_complete = false,
        kwargs...)

Write a Markdown review draft for a `fit_report` payload and return an export
record with report and Markdown content hashes. Passing a fit object first
builds `fit_report(fit; kwargs...)`. Set `require_complete = true` to reject
captured section errors before writing.
"""
function save_fit_report_markdown(path::AbstractString,
        report;
        overwrite::Bool = false,
        title::AbstractString = "BayesianMGMFRM fit report",
        max_rows::Integer = 6,
        include_empty::Bool = false,
        label = nothing,
        require_complete::Bool = false)
    require_complete &&
        _require_complete_fit_report(report, :save_fit_report_markdown)
    isfile(path) && !overwrite &&
        throw(ArgumentError("fit report markdown already exists at $path; pass overwrite = true to replace it"))
    markdown = fit_report_markdown(report;
        title,
        max_rows,
        include_empty)
    mkpath(dirname(path))
    open(path, "w") do io
        write(io, markdown)
    end
    return _fit_report_markdown_export_record(path, report, markdown;
        label,
        title,
        max_rows,
        include_empty)
end

function save_fit_report_markdown(path::AbstractString,
        fit::_ModelComparisonFit;
        overwrite::Bool = false,
        title::AbstractString = "BayesianMGMFRM fit report",
        max_rows::Integer = 6,
        include_empty::Bool = false,
        label = nothing,
        require_complete::Bool = false,
        kwargs...)
    report = fit_report(fit; require_complete, kwargs...)
    return save_fit_report_markdown(path, report;
        overwrite,
        title,
        max_rows,
        include_empty,
        label,
        require_complete)
end

function _check_fit_report_bundle_directory(directory::AbstractString;
        overwrite::Bool)
    if ispath(directory) && !isdir(directory)
        throw(ArgumentError("fit report bundle path exists and is not a directory: $directory"))
    end
    if isdir(directory) && !overwrite && !isempty(readdir(directory))
        throw(ArgumentError("fit report bundle directory is not empty at $directory; pass overwrite = true to replace export files"))
    end
    return true
end

function _fit_report_bundle_hash_record(payload)
    return _fit_report_table_hash_record(payload;
        scope = :fit_report_bundle_export_without_hash_metadata)
end

function _fit_report_bundle_file_rows(report_export, table_manifest,
        markdown_export)
    return [
        (;
            role = :report_json,
            path = "fit_report.json",
            schema = report_export.schema,
            object = report_export.object,
            content_hash = report_export.json_content_hash,
        ),
        (;
            role = :table_manifest,
            path = "tables/manifest.json",
            schema = table_manifest.schema,
            object = table_manifest.object,
            content_hash = table_manifest.content_hash,
            n_tables = table_manifest.n_tables,
            n_rows = table_manifest.n_rows,
        ),
        (;
            role = :markdown,
            path = "fit_report.md",
            schema = markdown_export.schema,
            object = markdown_export.object,
            content_hash = markdown_export.markdown_content_hash,
            n_bytes = markdown_export.n_bytes,
        ),
    ]
end

function _fit_report_bundle_manifest(directory::AbstractString,
        report_export,
        table_manifest,
        markdown_export;
        label = nothing,
        figure_bundle = nothing)
    public_report = report_export.report_schema == _FIT_REPORT_PUBLIC_SCHEMA
    location = public_report ? NamedTuple() : (;
        source_path = String(directory),
    )
    payload = merge((;
        schema = figure_bundle === nothing ? "bayesianmgmfrm.fit_report_bundle_export.v1" :
            "bayesianmgmfrm.fit_report_bundle_export.v2",
        object = :fit_report_bundle_export,
        created_at = string(now()),
        label = label === nothing ? missing : label,
    ), location, (;
        report_schema = report_export.report_schema,
        report_object = report_export.report_object,
        report_content_hash = report_export.report_content_hash,
        formats = figure_bundle === nothing ? (:json_report, :json_tables, :markdown) :
            (:json_report, :json_tables, :markdown, :pdf_figures, :svg_figures, :json_figure_data),
        report_filename = "fit_report.json",
        table_directory = "tables",
        markdown_filename = "fit_report.md",
        manifest_filename = "manifest.json",
        n_tables = table_manifest.n_tables,
        n_rows = table_manifest.n_rows,
        files = _fit_report_bundle_file_rows(report_export, table_manifest,
            markdown_export),
    ))
    figure_bundle === nothing || (payload = merge(payload, (; figures = figure_bundle.rows)))
    return merge(payload, (;
        content_hash = _fit_report_bundle_hash_record(payload),
    ))
end

"""
    save_fit_report_bundle(directory, report; overwrite = false,
        label = nothing, title = "BayesianMGMFRM fit report",
        max_rows = 6, include_empty = false, require_complete = false)
    save_fit_report_bundle(directory, fit; overwrite = false,
        label = nothing, title = "BayesianMGMFRM fit report",
        max_rows = 6, include_empty = false, require_complete = false,
        figures = nothing, seed = nothing, kwargs...)

Write a portable fit-report bundle directory containing a JSON report export,
JSON table files, a Markdown review draft, and a bundle `manifest.json` with
the nested content hashes. `report` may be the in-memory [`fit_report`](@ref)
payload or a JSON-loaded payload from [`load_fit_report`](@ref). Passing a fit
object first builds `fit_report(fit; kwargs...)`. Set `require_complete = true`
to reject captured section errors before creating the bundle directory.

With CairoMakie loaded, pass a fit and select optional figures, for example
`figures = (posterior = (block = :rater,), predictive = (;))`. Supported keys
are `posterior`, `diagnostics`, `predictive`, and stable-MFRM-only `wright`
and `pathway`.
Each value is a NamedTuple of that plot's selection/size options. The bundle
adds PDF/SVG figures, their captions in Markdown, and JSON numerical inputs.
No fitting occurs. Summary-only reports cannot supply figures: reload the
saved fit with [`load_fit_cache`](@ref).

Set shared `posterior_lower`/`posterior_upper` central bounds (default
0.025/0.975), `predictive_interval` (0.9), and `ndraws` or `draw_indices` on
this call, not inside plot options. Posterior, Wright and both axes of Pathway
figures use those posterior bounds and all retained draws; predictive figures consume the report's exact replicated
category-summary rows. `seed` defaults to 1 for figure bundles and controls
local posterior/prior predictive RNGs; custom `rng`/`prior_predictive_rng`
keywords are rejected there. Other report-only calls retain their RNG behavior.
Figure bundles keep the plotting diagnostic settings: stable defaults or the
stored generalized settings. Conflicting report diagnostic overrides are rejected.

Saved fixed-coefficient multidimensional MFRM fits support posterior,
diagnostics and predictive figures with their stored diagnostic settings.
They additionally accept `prior` and `prior_predictive` figure keys when
`include_prior_predictive = true`. Set `prior_predictive_ndraws` (default 100)
and `prior_interval` (default 0.95) on the bundle call. Prior figures use the
report's exact prior summaries; no second simulation occurs during rendering.
Their plots use model coordinates in unit logits; `seed` defaults to 1 for
both figure and report-only bundles. These saved-result outputs remain
estimated with `BayesianMGMFRM.Experimental.fit`.

All optional figures render before destination exports are written. A figure
bundle uses manifest schema v2, with hashes for every PDF, SVG and JSON input;
report and table schemas are unchanged. Figure-free bundles retain v1. Current
readers accept both; older readers reject v2 rather than silently skipping its
figure checks. As with ordinary bundles, `overwrite = true` replaces export
files, without deleting unrelated files. Only manifest-listed files are verified.

"""
function save_fit_report_bundle(directory::AbstractString, report;
        overwrite::Bool = false, label = nothing,
        title::AbstractString = "BayesianMGMFRM fit report", max_rows::Integer = 6,
        include_empty::Bool = false, require_complete::Bool = false, figures = nothing, seed = nothing)
    figures === nothing || throw(ArgumentError(
        "figure bundles require a fitted object; use load_fit_cache to recover the fit, then save_fit_report_bundle(directory, fit; figures=...)"))
    seed === nothing || throw(ArgumentError("seed requires a fitted object and figures"))
    return _save_fit_report_bundle(directory, report;
        overwrite, label, title, max_rows, include_empty, require_complete)
end

function _save_fit_report_bundle(directory::AbstractString,
        report;
        overwrite::Bool = false,
        label = nothing,
        title::AbstractString = "BayesianMGMFRM fit report",
        max_rows::Integer = 6,
        include_empty::Bool = false,
        require_complete::Bool = false,
        figure_bundle = nothing)
    max_rows >= 0 ||
        throw(ArgumentError("max_rows must be non-negative"))
    _check_fit_report_payload(report)
    require_complete &&
        _require_complete_fit_report(report, :save_fit_report_bundle)
    _check_fit_report_bundle_directory(directory; overwrite)
    mkpath(directory)
    report_path = joinpath(directory, "fit_report.json")
    table_directory = joinpath(directory, "tables")
    markdown_path = joinpath(directory, "fit_report.md")
    report_export = save_fit_report(report_path, report;
        overwrite = true,
        label,
        require_complete)
    table_manifest = save_fit_report_tables(table_directory, report;
        overwrite = true,
        label,
        require_complete)
    markdown_export = save_fit_report_markdown(markdown_path, report;
        overwrite = true,
        title,
        max_rows,
        include_empty,
        label,
        require_complete)
    if figure_bundle !== nothing
        mkpath(joinpath(directory, "figures"))
        for row in figure_bundle.rows, file in row.files
            cp(joinpath(figure_bundle.directory, file.path), joinpath(directory, file.path); force = true)
        end
        markdown = read(markdown_path, String) * figure_bundle.markdown
        write(markdown_path, markdown)
        markdown_export = _fit_report_markdown_export_record(markdown_path, report, markdown;
            label, title, max_rows, include_empty)
    end
    manifest = _fit_report_bundle_manifest(directory, report_export,
        table_manifest, markdown_export;
        label, figure_bundle)
    _write_json_record(joinpath(directory, "manifest.json"), manifest)
    return manifest
end

function save_fit_report_bundle(directory::AbstractString,
        fit::_ModelComparisonFit;
        overwrite::Bool = false,
        label = nothing,
        title::AbstractString = "BayesianMGMFRM fit report",
        max_rows::Integer = 6,
        include_empty::Bool = false,
        require_complete::Bool = false,
        figures = nothing,
        seed = nothing,
        kwargs...)
    if figures !== nothing
        return _save_fit_report_figure_bundle(directory, fit, figures;
            seed = seed === nothing ? 1 : seed,
            report_kwargs = (; kwargs...), overwrite, label, title, max_rows,
            include_empty, require_complete)
    end
    seed === nothing || throw(ArgumentError("seed requires figures; use rng for a report-only bundle"))
    report = fit_report(fit; require_complete, kwargs...)
    return save_fit_report_bundle(directory, report;
        overwrite,
        label,
        title,
        max_rows,
        include_empty,
        require_complete)
end

function _fit_report_bundle_manifest_path(directory::AbstractString)
    return joinpath(directory, "manifest.json")
end

struct _ExactJSONValue
    value::Any
end

JSON3.StructTypes.StructType(::Type{_ExactJSONValue}) = JSON3.RawType()
function JSON3.StructTypes.construct(::Type{_ExactJSONValue}, raw::JSON3.RawValue)
    # A fresh buffer cannot alias; avoid hashing the whole source String for each token.
    token = strip(String(UInt8[raw.bytes[i] for i in raw.pos:(raw.pos + raw.len - 1)]))
    value = if startswith(token, "{")
        Dict{String,Any}(k => v.value for (k, v) in JSON3.read(token, Dict{String,_ExactJSONValue}))
    elseif startswith(token, "[")
        Any[v.value for v in JSON3.read(token, Vector{_ExactJSONValue})]
    elseif occursin(r"^-?[0-9]+$", token)
        signed = tryparse(Int64, token)
        unsigned = signed === nothing ? tryparse(UInt64, token) : nothing
        signed !== nothing ? signed : unsigned !== nothing ? unsigned : parse(BigInt, token)
    else
        # Float64 preserves decimal/exponent tokens, including signed zero;
        # strings, booleans and null retain JSON3's ordinary validation.
        JSON3.read(token; numbertype = Float64)
    end
    return _ExactJSONValue(value)
end

function _read_json_dict(path::AbstractString, label::AbstractString)
    isfile(path) ||
        throw(ArgumentError("$label does not exist at $path"))
    source = read(path, String)
    # JSON3's inferred numbers fall back to Float64 beyond Int64. Parse integer
    # tokens exactly so UInt64 data signatures and mixed arrays keep their bits.
    value = JSON3.read(source, _ExactJSONValue).value
    value isa AbstractDict ||
        throw(ArgumentError("$label at $path does not contain a JSON object"))
    return value
end

function _check_fit_report_hash_record(record, field::Symbol, context::AbstractString;
        expected_scope = nothing,
        expected_canonicalization = nothing)
    hash_record = _report_lookup(record, field, _FIT_REPORT_LOOKUP_MISSING)
    (hash_record isa NamedTuple || hash_record isa AbstractDict) ||
        throw(ArgumentError("$context does not contain $(String(field))"))
    algorithm = _report_symbol_value(_report_lookup(hash_record, :algorithm,
        _FIT_REPORT_LOOKUP_MISSING))
    algorithm === :sha256 ||
        throw(ArgumentError("$context has an unsupported $(String(field)) algorithm"))
    value = _report_lookup(hash_record, :value, _FIT_REPORT_LOOKUP_MISSING)
    value isa AbstractString && occursin(r"^[0-9a-f]{64}$", value) ||
        throw(ArgumentError("$context has an invalid $(String(field)) value"))
    n_canonical_bytes = _report_lookup(hash_record, :n_canonical_bytes,
        _FIT_REPORT_LOOKUP_MISSING)
    n_canonical_bytes isa Integer && !(n_canonical_bytes isa Bool) &&
        n_canonical_bytes >= 0 ||
        throw(ArgumentError(
            "$context has an invalid $(String(field)) canonical byte count"))
    if expected_scope !== nothing
        scope = _report_symbol_value(_report_lookup(hash_record, :scope,
            _FIT_REPORT_LOOKUP_MISSING))
        scope === expected_scope ||
            throw(ArgumentError("$context has an unsupported $(String(field)) scope"))
    end
    if expected_canonicalization !== nothing
        canonicalization = _report_symbol_value(_report_lookup(hash_record,
            :canonicalization, _FIT_REPORT_LOOKUP_MISSING))
        canonicalization === expected_canonicalization ||
            throw(ArgumentError("$context has an unsupported $(String(field)) canonicalization"))
    end
    return hash_record
end

function _fit_report_hash_record_matches_actual(record,
        field::Symbol,
        actual,
        context::AbstractString;
        expected_scope = nothing,
        expected_canonicalization = nothing)
    expected = _check_fit_report_hash_record(record, field, context;
        expected_scope,
        expected_canonicalization)
    expected_value = _report_lookup(expected, :value, _FIT_REPORT_LOOKUP_MISSING)
    actual_value = _report_lookup(actual, :value, _FIT_REPORT_LOOKUP_MISSING)
    isequal(expected_value, actual_value) ||
        throw(ArgumentError("$context $(String(field)) content hash mismatch"))
    expected_bytes = _report_lookup(expected, :n_canonical_bytes,
        _FIT_REPORT_LOOKUP_MISSING)
    actual_bytes = _report_lookup(actual, :n_canonical_bytes,
        _FIT_REPORT_LOOKUP_MISSING)
    isequal(expected_bytes, actual_bytes) ||
        throw(ArgumentError("$context $(String(field)) canonical byte count mismatch"))
    return expected
end

function _fit_report_hash_value(record, field::Symbol, context::AbstractString;
        expected_scope = nothing,
        expected_canonicalization = nothing)
    hash_record = _check_fit_report_hash_record(record, field, context;
        expected_scope,
        expected_canonicalization)
    value = _report_lookup(hash_record, :value, _FIT_REPORT_LOOKUP_MISSING)
    return value
end

function _fit_report_bundle_file_record(manifest, role::Symbol,
        context::AbstractString)
    files = _report_lookup(manifest, :files, _FIT_REPORT_LOOKUP_MISSING)
    files isa AbstractVector ||
        throw(ArgumentError("$context does not contain bundle file rows"))
    for file in files
        file_role = _report_symbol_value(_report_lookup(file, :role, missing))
        file_role === role && return file
    end
    throw(ArgumentError("$context does not contain a $(String(role)) file row"))
end

function _fit_report_bundle_file_path(directory::AbstractString, file_record,
        context::AbstractString)
    path = _report_lookup(file_record, :path, _FIT_REPORT_LOOKUP_MISSING)
    path isa AbstractString ||
        throw(ArgumentError("$context file row does not contain a path"))
    if isabspath(path) || occursin('\\', path) || occursin("\0", path)
        throw(ArgumentError("$context file row contains an unsafe path: $path"))
    end
    parts = split(path, '/')
    if isempty(parts) || any(part -> isempty(part) || part == "." || part == "..", parts)
        throw(ArgumentError("$context file row contains an unsafe path: $path"))
    end
    return joinpath(directory, parts...)
end

function _check_fit_report_bundle_manifest(manifest, path)
    manifest isa AbstractDict ||
        throw(ArgumentError("fit report bundle manifest at $path does not contain a JSON object"))
    get(manifest, "schema", nothing) in
        ("bayesianmgmfrm.fit_report_bundle_export.v1", "bayesianmgmfrm.fit_report_bundle_export.v2") ||
        throw(ArgumentError("fit report bundle manifest at $path has an unsupported schema"))
    _report_symbol_value(get(manifest, "object", nothing)) ===
        :fit_report_bundle_export ||
        throw(ArgumentError("fit report bundle manifest at $path has an unsupported object"))
    _fit_report_hash_value(manifest, :content_hash,
        "fit report bundle manifest at $path";
        expected_scope = :fit_report_bundle_export_without_hash_metadata,
        expected_canonicalization = :cache_stable_string)
    report_hash_scope = _fit_report_content_hash_scope(
        _report_lookup(manifest, :report_schema, missing))
    _fit_report_hash_value(manifest, :report_content_hash,
        "fit report bundle manifest at $path";
        expected_scope = report_hash_scope,
        expected_canonicalization = :cache_stable_string)
    for (role, scope, canonicalization) in (
        (:report_json, :json_report_without_hash_metadata, nothing),
        (:table_manifest, :fit_report_table_export_without_hash_metadata,
            :cache_stable_string),
        (:markdown, :fit_report_markdown, :raw_markdown_string),
    )
        file_record = _fit_report_bundle_file_record(manifest, role,
            "fit report bundle manifest at $path")
        if role === :report_json
            canonicalization = _fit_report_export_canonicalization(
                _report_lookup(file_record, :schema, nothing))
        end
        _fit_report_hash_value(file_record, :content_hash,
            "fit report bundle $(String(role)) row at $path";
            expected_scope = scope,
            expected_canonicalization = canonicalization)
    end
    _check_fit_report_figure_entries(manifest, dirname(path); verify_hash = false)
    return manifest
end

function _verify_fit_report_bundle_manifest(manifest,
        directory::AbstractString,
        manifest_path::AbstractString)
    _fit_report_hash_record_matches_actual(manifest, :content_hash,
        _fit_report_bundle_hash_record(manifest),
        "fit report bundle manifest at $manifest_path";
        expected_scope = :fit_report_bundle_export_without_hash_metadata,
        expected_canonicalization = :cache_stable_string)

    report_file = _fit_report_bundle_file_record(manifest, :report_json,
        "fit report bundle manifest at $manifest_path")
    report_path = _fit_report_bundle_file_path(directory, report_file,
        "fit report bundle manifest at $manifest_path")
    report_record = load_fit_report(report_path;
        verify_hash = true,
        return_record = true)
    isequal(_report_lookup(report_file, :schema, nothing), report_record["schema"]) ||
        throw(ArgumentError("fit report bundle report_json row at $manifest_path has an inconsistent schema"))
    canonicalization = _fit_report_export_canonicalization(report_record["schema"])
    actual_report_json_hash = _check_fit_report_hash_record(report_record,
        :json_content_hash, "fit report export at $report_path";
        expected_scope = :json_report_without_hash_metadata,
        expected_canonicalization = canonicalization)
    _fit_report_hash_record_matches_actual(report_file, :content_hash,
        actual_report_json_hash,
        "fit report bundle report_json row at $manifest_path";
        expected_scope = :json_report_without_hash_metadata,
        expected_canonicalization = canonicalization)
    report_hash_scope = _fit_report_content_hash_scope(
        _report_lookup(manifest, :report_schema, missing))
    actual_report_hash = _check_fit_report_hash_record(report_record,
        :report_content_hash, "fit report export at $report_path";
        expected_scope = report_hash_scope,
        expected_canonicalization = :cache_stable_string)
    _fit_report_hash_record_matches_actual(manifest, :report_content_hash,
        actual_report_hash, "fit report bundle manifest at $manifest_path";
        expected_scope = report_hash_scope,
        expected_canonicalization = :cache_stable_string)

    table_file = _fit_report_bundle_file_record(manifest, :table_manifest,
        "fit report bundle manifest at $manifest_path")
    table_path = _fit_report_bundle_file_path(directory, table_file,
        "fit report bundle manifest at $manifest_path")
    expected_table_path = _fit_report_table_export_manifest_path(dirname(table_path))
    isequal(table_path, expected_table_path) ||
        throw(ArgumentError("fit report bundle table manifest path must resolve to $expected_table_path"))
    table_manifest = load_fit_report_tables(dirname(table_path);
        verify_hash = true,
        return_manifest = true)
    actual_table_hash = _check_fit_report_hash_record(table_manifest,
        :content_hash,
        "fit report table manifest at $table_path";
        expected_scope = :fit_report_table_export_without_hash_metadata,
        expected_canonicalization = :cache_stable_string)
    _fit_report_hash_record_matches_actual(table_file, :content_hash,
        actual_table_hash,
        "fit report bundle table_manifest row at $manifest_path";
        expected_scope = :fit_report_table_export_without_hash_metadata,
        expected_canonicalization = :cache_stable_string)

    markdown_file = _fit_report_bundle_file_record(manifest, :markdown,
        "fit report bundle manifest at $manifest_path")
    markdown_path = _fit_report_bundle_file_path(directory, markdown_file,
        "fit report bundle manifest at $manifest_path")
    isfile(markdown_path) ||
        throw(ArgumentError("fit report markdown file does not exist at $markdown_path"))
    _fit_report_hash_record_matches_actual(markdown_file, :content_hash,
        _fit_report_markdown_hash_record(read(markdown_path, String)),
        "fit report bundle markdown row at $manifest_path";
        expected_scope = :fit_report_markdown,
        expected_canonicalization = :raw_markdown_string)
    _check_fit_report_figure_entries(manifest, directory; verify_hash = true)
    return manifest
end

function _fit_report_bundle_report_path(directory::AbstractString, manifest,
        manifest_path::AbstractString)
    report_file = _fit_report_bundle_file_record(manifest, :report_json,
        "fit report bundle manifest at $manifest_path")
    return _fit_report_bundle_file_path(directory, report_file,
        "fit report bundle manifest at $manifest_path")
end

"""
    load_fit_report_bundle(directory; verify_hash = true,
        return_manifest = false, require_complete = false)

Load a fit-report bundle written by [`save_fit_report_bundle`](@ref). By
default this verifies the bundle manifest hash, JSON report export hash, table
manifest and table-file hashes, and Markdown content hash before returning the
loaded `fit_report` payload. Set `return_manifest = true` to inspect the
bundle manifest instead. Set `require_complete = true` to reject a report
containing captured section errors.
For v2 figure bundles, verification also checks every declared PDF, SVG and
numerical-input JSON file. CairoMakie and a saved fit are not needed to read or
verify a bundle. The returned value remains the report (or manifest), not a
fitted object or reconstructed chain. `verify_hash = false` skips byte checks;
version, figure inventory and safe-path checks still apply.

"""
function load_fit_report_bundle(directory::AbstractString;
        verify_hash::Bool = true,
        return_manifest::Bool = false,
        require_complete::Bool = false)
    isdir(directory) ||
        throw(ArgumentError("fit report bundle directory does not exist at $directory"))
    manifest_path = _fit_report_bundle_manifest_path(directory)
    manifest = _read_json_dict(manifest_path, "fit report bundle manifest")
    manifest = _check_fit_report_bundle_manifest(manifest, manifest_path)
    verify_hash &&
        _verify_fit_report_bundle_manifest(manifest, directory, manifest_path)
    report_path = _fit_report_bundle_report_path(directory, manifest,
        manifest_path)
    if return_manifest
        require_complete && load_fit_report(report_path;
            verify_hash,
            require_complete = true)
        return manifest
    end
    return load_fit_report(report_path; verify_hash, require_complete)
end

const _FIT_REPORT_DOSSIER_TOP_LEVEL_FIELDS = Set((
    :schema,
    :object,
    :created_at,
    :label,
    :report_policy,
    :report_status,
    :complete,
    :n_reports,
    :n_incomplete_reports,
    :n_error_sections,
    :models,
    :n_report_rows,
    :n_section_rows,
    :n_comparison_rows,
    :n_sensitivity_rows,
    :n_evidence_rows,
    :report_rows,
    :section_rows,
    :comparison_rows,
    :sensitivity_rows,
    :evidence_rows,
    :reports,
))

const _FIT_REPORT_DOSSIER_HASH_FIELDS = Set((
    :report_content_hash,
    :content_hash,
    :dossier_content_hash,
    :json_content_hash,
    :markdown_content_hash,
))

function _fit_report_dossier_output_field_allowed(field::Symbol, path::Tuple)
    isempty(path) && return field in _FIT_REPORT_DOSSIER_TOP_LEVEL_FIELDS
    path == (:report_policy,) &&
        return field in (:include_reports, :rendering_scope, :require_complete)
    if last(path) in _FIT_REPORT_DOSSIER_HASH_FIELDS
        return field in (
            :algorithm, :value, :scope, :canonicalization,
            :n_canonical_bytes,
        )
    end
    return _public_fit_report_projection_field_allowed(field, path)
end

function _assert_fit_report_dossier_value(value, path::Tuple = ();
        preserve_user_text::Bool = false)
    if (value isa NamedTuple || value isa AbstractDict) && path == (:reports,)
        _check_fit_report_payload(value)
        _is_public_fit_report(value) ||
            throw(ArgumentError(
                "fit_report_dossier embedded reports must use the public schema"))
        return value
    elseif value isa NamedTuple
        for field in keys(value)
            _fit_report_dossier_output_field_allowed(field, path) ||
                throw(ArgumentError(
                    "fit_report_dossier contains a repository-maintenance field"))
            _assert_fit_report_dossier_value(getproperty(value, field),
                (path..., field);
                preserve_user_text =
                    _public_fit_report_user_value_field(field))
        end
    elseif value isa AbstractDict
        for (key, item) in value
            field = _report_key_symbol(key)
            _fit_report_dossier_output_field_allowed(field, path) ||
                throw(ArgumentError(
                    "fit_report_dossier contains a repository-maintenance field"))
            _assert_fit_report_dossier_value(item, (path..., field);
                preserve_user_text =
                    _public_fit_report_user_value_field(field))
        end
    elseif value isa Tuple || value isa AbstractArray
        for item in value
            _assert_fit_report_dossier_value(item, path;
                preserve_user_text =
                    _public_fit_report_child_preserves_user_text(
                        item, preserve_user_text))
        end
    elseif (value isa Symbol || value isa AbstractString) && !preserve_user_text
        _assert_public_fit_report_value(value;
            preserve_user_text = false)
    end
    return value
end

function _check_fit_report_dossier_compatibility_payload(dossier)
    (dossier isa NamedTuple || dossier isa AbstractDict) ||
        throw(ArgumentError("expected a fit_report_dossier payload as a NamedTuple or Dict"))
    schema = _report_lookup(dossier, :schema, _FIT_REPORT_LOOKUP_MISSING)
    schema == "bayesianmgmfrm.fit_report_dossier.v1" ||
        throw(ArgumentError("expected a bayesianmgmfrm.fit_report_dossier.v1 payload"))
    object = _report_symbol_value(_report_lookup(dossier, :object, missing))
    object === :fit_report_dossier ||
        throw(ArgumentError("invalid fit_report_dossier object label"))
    return dossier
end

function _check_fit_report_dossier_payload(dossier)
    _check_fit_report_dossier_compatibility_payload(dossier)
    _assert_fit_report_dossier_value(dossier)
    _fit_report_dossier_health(dossier)
    return dossier
end

function _fit_report_dossier_health(dossier)
    _check_fit_report_dossier_compatibility_payload(dossier)
    rows = _report_lookup(dossier, :report_rows, _FIT_REPORT_LOOKUP_MISSING)
    (rows isa Tuple || rows isa AbstractVector) ||
        throw(ArgumentError("fit report dossier does not contain report_rows"))
    n_incomplete_reports = 0
    n_error_sections = 0
    for row in rows
        row_errors = _report_lookup(row, :n_error_sections, 0)
        row_errors isa Integer && !(row_errors isa Bool) && row_errors >= 0 ||
            throw(ArgumentError(
                "fit report dossier report row has invalid n_error_sections"))
        row_status = _report_lookup(row, :report_status,
            _FIT_REPORT_LOOKUP_MISSING)
        row_complete = _report_lookup(row, :report_complete,
            _FIT_REPORT_LOOKUP_MISSING)
        derived_complete = row_errors == 0
        if row_status !== _FIT_REPORT_LOOKUP_MISSING
            _report_symbol_value(row_status) ===
                (derived_complete ? :complete : :incomplete) ||
                throw(ArgumentError(
                    "fit report dossier report_status is inconsistent with its section errors"))
        end
        if row_complete !== _FIT_REPORT_LOOKUP_MISSING
            row_complete isa Bool ||
                throw(ArgumentError(
                    "fit report dossier report_complete must be Boolean"))
            row_complete == derived_complete ||
                throw(ArgumentError(
                    "fit report dossier report_complete is inconsistent with its section errors"))
        end
        n_error_sections += row_errors
        n_incomplete_reports += !derived_complete
    end
    complete = n_incomplete_reports == 0
    for (field, expected) in (
            (:report_status, complete ? :complete : :incomplete),
            (:complete, complete),
            (:n_incomplete_reports, n_incomplete_reports),
            (:n_error_sections, n_error_sections))
        recorded = _report_lookup(dossier, field, _FIT_REPORT_LOOKUP_MISSING)
        recorded === _FIT_REPORT_LOOKUP_MISSING && continue
        normalized = field === :report_status ?
            _report_symbol_value(recorded) : recorded
        isequal(normalized, expected) ||
            throw(ArgumentError(
                "fit report dossier field $field is inconsistent with its report rows"))
    end
    return (;
        status = complete ? :complete : :incomplete,
        complete,
        n_reports = length(rows),
        n_incomplete_reports,
        n_error_sections,
    )
end

function _require_complete_fit_report_dossier(dossier, caller::Symbol)
    health = _fit_report_dossier_health(dossier)
    health.complete && return health
    throw(ArgumentError(
        "$(String(caller)) requires a complete fit report dossier; " *
        "n_incomplete_reports=$(health.n_incomplete_reports), " *
        "n_error_sections=$(health.n_error_sections)",
    ))
end

function _fit_report_dossier_public_projection(value, path::Tuple = ();
        preserve_user_text::Bool = false)
    if (value isa NamedTuple || value isa AbstractDict) && path == (:reports,)
        return _json_export_value(fit_report_public(value))
    elseif value isa NamedTuple
        pairs = Pair{Symbol,Any}[]
        for field in keys(value)
            _fit_report_dossier_output_field_allowed(field, path) || continue
            projected = _fit_report_dossier_public_projection(
                getproperty(value, field),
                (path..., field);
                preserve_user_text = _public_fit_report_user_value_field(field),
            )
            projected === _PUBLIC_FIT_REPORT_OMITTED && continue
            push!(pairs, field => projected)
        end
        return (; pairs...)
    elseif value isa AbstractDict
        projected = Dict{String,Any}()
        for (key, item) in value
            field = _report_key_symbol(key)
            _fit_report_dossier_output_field_allowed(field, path) || continue
            projected_item = _fit_report_dossier_public_projection(
                item,
                (path..., field);
                preserve_user_text = _public_fit_report_user_value_field(field),
            )
            projected_item === _PUBLIC_FIT_REPORT_OMITTED && continue
            projected[String(field)] = projected_item
        end
        return projected
    elseif value isa Tuple || value isa AbstractArray
        projected = Any[]
        for item in value
            projected_item = _fit_report_dossier_public_projection(
                item,
                path;
                preserve_user_text =
                    _public_fit_report_child_preserves_user_text(
                        item, preserve_user_text),
            )
            push!(projected, projected_item === _PUBLIC_FIT_REPORT_OMITTED ?
                missing : projected_item)
        end
        return value isa Tuple ? Tuple(projected) : projected
    end
    return _public_fit_report_project_value(value;
        preserve_user_text,
        path)
end

function _fit_report_dossier_loaded_projection(dossier)
    _check_fit_report_dossier_compatibility_payload(dossier)
    projected = _fit_report_dossier_public_projection(dossier)
    projected isa AbstractDict ||
        throw(ArgumentError("expected a JSON-loaded fit_report_dossier payload"))
    reports = get(projected, "reports", nothing)
    projected_policy = get(projected, "report_policy", Dict{String,Any}())
    recorded_require_complete = get(projected_policy,
        "require_complete", false)
    projected["report_policy"] = Dict{String,Any}(
        "include_reports" => reports !== nothing,
        "rendering_scope" => "review_dossier",
        "require_complete" => recorded_require_complete,
    )
    return _check_fit_report_dossier_payload(projected)
end

function _fit_report_dossier_rows(rows, field::Symbol)
    rows === nothing && return Any[]
    row_vector = rows isa Tuple ? Any[rows...] :
        rows isa AbstractVector ? Any[rows...] :
        throw(ArgumentError("$(String(field)) must be a vector or tuple of row objects"))
    for row in row_vector
        (row isa NamedTuple || row isa AbstractDict) ||
            throw(ArgumentError("$(String(field)) rows must be NamedTuple or Dict values"))
    end
    return row_vector
end

function _fit_report_dossier_pairs(reports::Tuple)
    !isempty(reports) ||
        throw(ArgumentError("fit_report_dossier requires at least one report"))
    labels = String[]
    payloads = Any[]
    for report in reports
        push!(labels, string(report.first))
        push!(payloads, _check_fit_report_payload(report.second))
    end
    _compare_model_names(labels, length(labels))
    return labels, payloads
end

function _fit_report_dossier_named_reports(reports::Tuple, names)
    !isempty(reports) ||
        throw(ArgumentError("fit_report_dossier requires at least one report"))
    labels = _compare_model_names(names, length(reports))
    payloads = Any[_check_fit_report_payload(report) for report in reports]
    return labels, payloads
end

function _fit_report_dossier_diagnostic_flag(report)
    diagnostics_section = _report_lookup(report, :diagnostics, _FIT_REPORT_LOOKUP_MISSING)
    diagnostics_section === _FIT_REPORT_LOOKUP_MISSING && return missing
    summary = _report_lookup(diagnostics_section, :summary, _FIT_REPORT_LOOKUP_MISSING)
    summary === _FIT_REPORT_LOOKUP_MISSING && return missing
    return _report_symbol_value(_report_lookup(summary, :flag, missing))
end

function _fit_report_dossier_report_and_section_rows(
        labels::AbstractVector{<:AbstractString},
        reports::AbstractVector)
    report_rows = NamedTuple[]
    section_rows = NamedTuple[]
    for (label, report) in zip(labels, reports)
        sections = fit_report_sections(report)
        health = fit_report_health(report)
        report_hash = _fit_report_content_hash_record(report)
        estimation_status_value = _report_lookup(
            report, :estimation_status, _FIT_REPORT_LOOKUP_MISSING)
        estimation_status_value === _FIT_REPORT_LOOKUP_MISSING &&
            (estimation_status_value = _report_lookup(report, :status, missing))
        n_error_sections = health.n_error_sections
        n_computed_sections = count(row -> row.status === :computed, sections)
        n_not_requested_sections = count(row -> row.status === :not_requested, sections)
        n_rows = sum(row.n_rows for row in sections)
        push!(report_rows, (;
            model = String(label),
            report_schema = _report_lookup(report, :schema, missing),
            report_object = _report_symbol_value(_report_lookup(report, :object, missing)),
            report_created_at = _report_lookup(report, :created_at, missing),
            family = _report_symbol_value(_report_lookup(report, :family, missing)),
            thresholds = _report_symbol_value(_report_lookup(report, :thresholds, missing)),
            dimensions = _report_lookup(report, :dimensions, missing),
            estimation_status =
                _report_symbol_value(estimation_status_value),
            report_status = health.status,
            report_complete = health.complete,
            diagnostic_flag = _fit_report_dossier_diagnostic_flag(report),
            n_sections = length(sections),
            n_computed_sections,
            n_not_requested_sections,
            n_error_sections,
            n_rows,
            report_content_hash = report_hash,
        ))
        for section in sections
            push!(section_rows, (;
                model = String(label),
                section = section.section,
                status = section.status,
                row_fields = copy(section.row_fields),
                n_rows = section.n_rows,
            ))
        end
    end
    return report_rows, section_rows
end

"""
    fit_report_dossier(reports::Pair...; comparison_rows = (),
        sensitivity_rows = (), evidence_rows = (), include_reports = false,
        require_complete = false, label = nothing)
    fit_report_dossier(report1, report2, ...; names = nothing, kwargs...)

Build a reader-facing review dossier from one or more [`fit_report`](@ref)
payloads. Inputs are normalized through [`fit_report_public`](@ref), including
reports embedded with `include_reports = true`. Supplied comparison,
sensitivity, and evidence rows are projected through the same field-aware
language boundary, and the portable dossier retains only reader-facing fields.
Each dossier records aggregate report health. Set `require_complete = true` to
reject any input report containing a captured section error.
"""
function fit_report_dossier(reports::Pair...;
        comparison_rows = (),
        sensitivity_rows = (),
        evidence_rows = (),
        include_reports::Bool = false,
        require_complete::Bool = false,
        label = nothing)
    labels, payloads = _fit_report_dossier_pairs(reports)
    return _fit_report_dossier(labels, payloads;
        comparison_rows,
        sensitivity_rows,
        evidence_rows,
        include_reports,
        require_complete,
        label)
end

function fit_report_dossier(
        first,
        rest...;
        names = nothing,
        comparison_rows = (),
        sensitivity_rows = (),
        evidence_rows = (),
        include_reports::Bool = false,
        require_complete::Bool = false,
        label = nothing)
    labels, payloads = _fit_report_dossier_named_reports((first, rest...), names)
    return _fit_report_dossier(labels, payloads;
        comparison_rows,
        sensitivity_rows,
        evidence_rows,
        include_reports,
        require_complete,
        label)
end

function fit_report_dossier(; kwargs...)
    throw(ArgumentError("fit_report_dossier requires at least one report"))
end

function _fit_report_dossier(labels::AbstractVector{<:AbstractString},
        reports::AbstractVector;
        comparison_rows,
        sensitivity_rows,
        evidence_rows,
        include_reports::Bool,
        require_complete::Bool,
        label)
    reader_reports = Any[fit_report_public(report) for report in reports]
    if require_complete
        for report in reader_reports
            _require_complete_fit_report(report, :fit_report_dossier)
        end
    end
    report_rows, section_rows =
        _fit_report_dossier_report_and_section_rows(labels, reader_reports)
    n_incomplete_reports = count(row -> !row.report_complete, report_rows)
    n_error_sections = sum(row.n_error_sections for row in report_rows)
    complete = n_incomplete_reports == 0
    checked_comparison_rows = _public_fit_report_project_value(
        _fit_report_dossier_rows(comparison_rows, :comparison_rows);
        path = (:comparison_rows,))
    checked_sensitivity_rows = _public_fit_report_project_value(
        _fit_report_dossier_rows(sensitivity_rows, :sensitivity_rows);
        path = (:sensitivity_rows,))
    checked_evidence_rows = _public_fit_report_project_value(
        _fit_report_dossier_rows(evidence_rows, :evidence_rows);
        path = (:evidence_rows,))
    dossier = (;
        schema = "bayesianmgmfrm.fit_report_dossier.v1",
        object = :fit_report_dossier,
        created_at = string(now()),
        label = label === nothing ? missing : label,
        report_policy = (;
            include_reports,
            rendering_scope = :review_dossier,
            require_complete,
        ),
        report_status = complete ? :complete : :incomplete,
        complete,
        n_reports = length(reader_reports),
        n_incomplete_reports,
        n_error_sections,
        models = Tuple(labels),
        n_report_rows = length(report_rows),
        n_section_rows = length(section_rows),
        n_comparison_rows = length(checked_comparison_rows),
        n_sensitivity_rows = length(checked_sensitivity_rows),
        n_evidence_rows = length(checked_evidence_rows),
        report_rows,
        section_rows,
        comparison_rows = checked_comparison_rows,
        sensitivity_rows = checked_sensitivity_rows,
        evidence_rows = checked_evidence_rows,
        reports = include_reports ? Tuple(reader_reports) : nothing,
    )
    return _check_fit_report_dossier_payload(dossier)
end

function _fit_report_dossier_metadata_rows(dossier)
    fields = (:schema, :object, :created_at, :label, :report_status,
        :complete, :n_reports, :n_incomplete_reports, :n_error_sections,
        :n_report_rows, :n_section_rows, :n_comparison_rows,
        :n_sensitivity_rows, :n_evidence_rows)
    rows = NamedTuple[]
    for field in fields
        value = _report_lookup(dossier, field, _FIT_REPORT_LOOKUP_MISSING)
        value === _FIT_REPORT_LOOKUP_MISSING && continue
        push!(rows, (; field, value = _report_symbol_value(value)))
    end
    return rows
end

function _fit_report_dossier_row_vector(dossier, field::Symbol)
    rows = _report_lookup(dossier, field, _FIT_REPORT_LOOKUP_MISSING)
    rows isa AbstractVector || return Any[]
    return rows
end

function _write_fit_report_dossier_markdown_section(io::IO,
        title::AbstractString,
        rows,
        field::Symbol;
        max_rows::Int,
        include_empty::Bool)
    if isempty(rows) && !include_empty
        return false
    end
    println(io)
    println(io, "## ", title)
    println(io)
    println(io, "- Rows: ", length(rows))
    println(io, "- Preview rows: ", min(length(rows), max_rows))
    println(io)
    _write_markdown_table(io, rows;
        max_rows,
        max_cell_chars = 120,
        public_view = true,
        path = (field,))
    return true
end

"""
    fit_report_dossier_markdown(dossier;
        title = "BayesianMGMFRM fit report dossier", max_rows = 6,
        include_empty = false)

Render a portable Markdown review dossier from a [`fit_report_dossier`](@ref)
payload. The output includes dossier metadata, per-report summaries, per-section
summaries, and previews of supplied comparison, sensitivity, and evidence rows.
Tables use the same column display order as [`fit_report_markdown`](@ref).
"""
function fit_report_dossier_markdown(dossier;
        title::AbstractString = "BayesianMGMFRM fit report dossier",
        max_rows::Integer = 6,
        include_empty::Bool = false)
    max_rows >= 0 ||
        throw(ArgumentError("max_rows must be non-negative"))
    _check_fit_report_dossier_payload(dossier)
    io = IOBuffer()
    println(io, "# ", title)
    println(io)
    println(io, "Generated from `bayesianmgmfrm.fit_report_dossier.v1`.")
    println(io)
    dossier_hash = _artifact_content_hash_record(dossier)
    println(io, "- Dossier content hash: `", dossier_hash.value, "`")
    println(io, "- Markdown preview rows per table: ", max_rows)
    println(io, "- Interpret results within the documented model scope.")
    println(io)
    println(io, "## Dossier Metadata")
    println(io)
    _write_markdown_table(io, _fit_report_dossier_metadata_rows(dossier);
        fields = (:field, :value),
        max_rows = typemax(Int),
        max_cell_chars = 160,
        public_view = true,
        path = (:dossier_metadata,))
    _write_fit_report_dossier_markdown_section(io,
        "Report Summary",
        _fit_report_dossier_row_vector(dossier, :report_rows),
        :report_rows;
        max_rows = Int(max_rows),
        include_empty = true)
    _write_fit_report_dossier_markdown_section(io,
        "Section Summary",
        _fit_report_dossier_row_vector(dossier, :section_rows),
        :section_rows;
        max_rows = Int(max_rows),
        include_empty = true)
    wrote_optional = false
    for (title, field) in (
            ("Comparison Rows", :comparison_rows),
            ("Sensitivity Rows", :sensitivity_rows),
            ("Evidence Rows", :evidence_rows))
        wrote_optional |= _write_fit_report_dossier_markdown_section(io,
            title,
            _fit_report_dossier_row_vector(dossier, field),
            field;
            max_rows = Int(max_rows),
            include_empty)
    end
    if !wrote_optional && include_empty
        println(io)
        println(io, "*No comparison, sensitivity, or evidence rows are available.*")
    end
    return String(take!(io))
end

function _fit_report_dossier_json_hash_record(payload)
    hash_payload = _json_hash_value(_artifact_hash_payload(payload))
    canonical = _cache_stable_string(hash_payload)
    return (;
        algorithm = :sha256,
        value = bytes2hex(sha256(IOBuffer(canonical))),
        scope = :fit_report_dossier_json_without_hash_metadata,
        canonicalization = :cache_stable_string,
        n_canonical_bytes = sizeof(canonical),
    )
end

function _fit_report_dossier_markdown_hash_record(markdown::AbstractString)
    return (;
        algorithm = :sha256,
        value = bytes2hex(sha256(IOBuffer(String(markdown)))),
        scope = :fit_report_dossier_markdown,
        canonicalization = :raw_markdown_string,
        n_canonical_bytes = sizeof(markdown),
    )
end

function _fit_report_dossier_export_record(path::AbstractString,
        dossier;
        label = nothing)
    _check_fit_report_dossier_payload(dossier)
    json_dossier = _json_export_value(dossier)
    return (;
        schema = "bayesianmgmfrm.fit_report_dossier_export.v1",
        object = :fit_report_dossier_export,
        created_at = string(now()),
        label = label === nothing ? missing : label,
        serialization = (;
            format = :json,
            writer = :JSON3,
            portability = :cross_tool_json_payload,
            missing_values = :json_null,
            nonfinite_numbers = :string,
        ),
        dossier_schema = _report_lookup(dossier, :schema, missing),
        dossier_object = _report_symbol_value(_report_lookup(dossier, :object, missing)),
        dossier_content_hash = _artifact_content_hash_record(dossier),
        json_content_hash = _fit_report_dossier_json_hash_record(json_dossier),
        dossier = json_dossier,
    )
end

"""
    save_fit_report_dossier(path, dossier; overwrite = false, label = nothing,
        require_complete = false)

Write a [`fit_report_dossier`](@ref) to a JSON export record. The export stores
both the dossier content hash and a JSON-payload hash so
[`load_fit_report_dossier`](@ref) can verify the saved payload. Set
`require_complete = true` to reject a dossier containing any report-section
error before writing.
"""
function save_fit_report_dossier(path::AbstractString,
        dossier;
        overwrite::Bool = false,
        label = nothing,
        require_complete::Bool = false)
    require_complete && _require_complete_fit_report_dossier(
        dossier, :save_fit_report_dossier)
    isfile(path) && !overwrite &&
        throw(ArgumentError("fit report dossier export already exists at $path; pass overwrite = true to replace it"))
    record = _fit_report_dossier_export_record(path, dossier; label)
    mkpath(dirname(path))
    _write_json_record(path, record)
    return record
end

function _check_fit_report_dossier_export_record(record, path)
    record isa AbstractDict ||
        throw(ArgumentError("fit report dossier export at $path does not contain a JSON object"))
    get(record, "schema", nothing) ==
        "bayesianmgmfrm.fit_report_dossier_export.v1" ||
        throw(ArgumentError("fit report dossier export at $path has an unsupported schema"))
    get(record, "object", nothing) == "fit_report_dossier_export" ||
        throw(ArgumentError("fit report dossier export at $path has an unsupported object"))
    get(record, "dossier", nothing) isa AbstractDict ||
        throw(ArgumentError("fit report dossier export at $path does not contain a dossier object"))
    dossier = _check_fit_report_dossier_compatibility_payload(record["dossier"])
    isequal(get(record, "dossier_schema", nothing),
        _report_lookup(dossier, :schema, missing)) ||
        throw(ArgumentError("fit report dossier export at $path has inconsistent dossier schemas"))
    isequal(get(record, "dossier_object", nothing),
        _report_lookup(dossier, :object, missing)) ||
        throw(ArgumentError("fit report dossier export at $path has inconsistent dossier objects"))
    _check_fit_report_hash_record(record, :dossier_content_hash,
        "fit report dossier export at $path";
        expected_scope = :artifact_without_hash_metadata,
        expected_canonicalization = :cache_stable_string)
    _check_fit_report_hash_record(record, :json_content_hash,
        "fit report dossier export at $path";
        expected_scope = :fit_report_dossier_json_without_hash_metadata,
        expected_canonicalization = :cache_stable_string)
    return record
end

function _verify_fit_report_dossier_export_record(record, path)
    _fit_report_hash_record_matches_actual(record, :json_content_hash,
        _fit_report_dossier_json_hash_record(record["dossier"]),
        "fit report dossier export at $path";
        expected_scope = :fit_report_dossier_json_without_hash_metadata,
        expected_canonicalization = :cache_stable_string)
    return record
end

"""
    load_fit_report_dossier(path; verify_hash = true, return_record = false,
        require_complete = false)

Load a JSON fit-report dossier export written by
[`save_fit_report_dossier`](@ref). Hash metadata is checked, the JSON payload is
verified by default, and the loaded dossier payload is projected to the current
reader-facing shape before it is returned as ordinary `Dict{String,Any}` /
`Vector{Any}` data. This projection also accepts v0.1.0 dossier exports,
removes their stored source path and implementation-only fields, and converts
embedded full reports to the public report schema. Set `return_record = true`
to return a current export record containing that projected dossier; both
content hashes then describe the projected payload.
"""
function load_fit_report_dossier(path::AbstractString;
        verify_hash::Bool = true,
        return_record::Bool = false,
        require_complete::Bool = false)
    record = _read_json_dict(path, "fit report dossier export")
    record = _check_fit_report_dossier_export_record(record, path)
    verify_hash && _verify_fit_report_dossier_export_record(record, path)
    dossier = _fit_report_dossier_loaded_projection(record["dossier"])
    require_complete && _require_complete_fit_report_dossier(
        dossier, :load_fit_report_dossier)
    current_record = _json_export_value(_fit_report_dossier_export_record(
        path,
        dossier;
        label = get(record, "label", nothing),
    ))
    created_at = _public_fit_report_project_value(
        get(record, "created_at", missing))
    created_at === _PUBLIC_FIT_REPORT_OMITTED ||
        (current_record["created_at"] = created_at)
    return return_record ? current_record : dossier
end

function _fit_report_dossier_markdown_export_record(path::AbstractString,
        dossier,
        markdown::AbstractString;
        label = nothing,
        title::AbstractString,
        max_rows::Integer,
        include_empty::Bool)
    return (;
        schema = "bayesianmgmfrm.fit_report_dossier_markdown_export.v1",
        object = :fit_report_dossier_markdown_export,
        created_at = string(now()),
        label = label === nothing ? missing : label,
        dossier_schema = _report_lookup(dossier, :schema, missing),
        dossier_object = _report_symbol_value(_report_lookup(dossier, :object, missing)),
        dossier_content_hash = _artifact_content_hash_record(dossier),
        markdown_content_hash = _fit_report_dossier_markdown_hash_record(markdown),
        format = :markdown,
        title = String(title),
        max_rows = Int(max_rows),
        include_empty,
        n_bytes = sizeof(markdown),
    )
end

"""
    save_fit_report_dossier_markdown(path, dossier; overwrite = false,
        title = "BayesianMGMFRM fit report dossier", max_rows = 6,
        include_empty = false, label = nothing, require_complete = false)

Write a Markdown review draft for a [`fit_report_dossier`](@ref) payload and
return an export record with dossier and Markdown content hashes. Set
`require_complete = true` to reject an incomplete dossier before writing.
"""
function save_fit_report_dossier_markdown(path::AbstractString,
        dossier;
        overwrite::Bool = false,
        title::AbstractString = "BayesianMGMFRM fit report dossier",
        max_rows::Integer = 6,
        include_empty::Bool = false,
        label = nothing,
        require_complete::Bool = false)
    require_complete && _require_complete_fit_report_dossier(
        dossier, :save_fit_report_dossier_markdown)
    isfile(path) && !overwrite &&
        throw(ArgumentError("fit report dossier markdown already exists at $path; pass overwrite = true to replace it"))
    markdown = fit_report_dossier_markdown(dossier;
        title,
        max_rows,
        include_empty)
    mkpath(dirname(path))
    open(path, "w") do io
        write(io, markdown)
    end
    return _fit_report_dossier_markdown_export_record(path, dossier, markdown;
        label,
        title,
        max_rows,
        include_empty)
end

function _fit_report_table_export_manifest_path(directory::AbstractString)
    return joinpath(directory, "manifest.json")
end

function _fit_report_table_manifest_rows(manifest, context::AbstractString)
    rows = _report_lookup(manifest, :tables, _FIT_REPORT_LOOKUP_MISSING)
    rows isa AbstractVector ||
        throw(ArgumentError("$context does not contain table rows"))
    return rows
end

function _fit_report_table_manifest_filename(row, context::AbstractString)
    filename = _report_lookup(row, :filename, _FIT_REPORT_LOOKUP_MISSING)
    filename isa AbstractString ||
        throw(ArgumentError("$context table row does not contain a filename"))
    if isempty(filename) || isabspath(filename) || occursin("/", filename) ||
            occursin("\\", filename) || occursin("\0", filename) ||
            filename == "." || filename == ".."
        throw(ArgumentError("$context table row contains an unsafe filename: $filename"))
    end
    return filename
end

function _check_fit_report_table_manifest(manifest, path)
    manifest isa AbstractDict ||
        throw(ArgumentError("fit report table manifest at $path does not contain a JSON object"))
    get(manifest, "schema", nothing) ==
        "bayesianmgmfrm.fit_report_table_export.v1" ||
        throw(ArgumentError("fit report table manifest at $path has an unsupported schema"))
    _report_symbol_value(get(manifest, "object", nothing)) ===
        :fit_report_table_export ||
        throw(ArgumentError("fit report table manifest at $path has an unsupported object"))
    _fit_report_hash_value(manifest, :content_hash,
        "fit report table manifest at $path";
        expected_scope = :fit_report_table_export_without_hash_metadata,
        expected_canonicalization = :cache_stable_string)
    rows = _fit_report_table_manifest_rows(manifest,
        "fit report table manifest at $path")
    n_tables = _report_lookup(manifest, :n_tables, _FIT_REPORT_LOOKUP_MISSING)
    n_tables isa Integer && n_tables == length(rows) ||
        throw(ArgumentError("fit report table manifest at $path has inconsistent n_tables"))
    seen = Set{String}()
    for row in rows
        filename = _fit_report_table_manifest_filename(row,
            "fit report table manifest at $path")
        filename in seen &&
            throw(ArgumentError("fit report table manifest at $path contains duplicate filename $filename"))
        _fit_report_hash_value(row, :content_hash,
            "fit report table manifest row at $path";
            expected_scope = :fit_report_table_without_hash_metadata,
            expected_canonicalization = :cache_stable_string)
        push!(seen, filename)
    end
    return manifest
end

function _check_fit_report_table_record(record, path)
    record isa AbstractDict ||
        throw(ArgumentError("fit report table at $path does not contain a JSON object"))
    get(record, "schema", nothing) == "bayesianmgmfrm.fit_report_table.v1" ||
        throw(ArgumentError("fit report table at $path has an unsupported schema"))
    _report_symbol_value(get(record, "object", nothing)) === :fit_report_table ||
        throw(ArgumentError("fit report table at $path has an unsupported object"))
    section = _report_symbol_value(_report_lookup(record, :section,
        _FIT_REPORT_LOOKUP_MISSING))
    section isa Symbol ||
        throw(ArgumentError("fit report table at $path does not contain a section"))
    row_field = _report_symbol_value(_report_lookup(record, :row_field,
        _FIT_REPORT_LOOKUP_MISSING))
    row_field isa Symbol ||
        throw(ArgumentError("fit report table at $path does not contain a row_field"))
    rows = _report_lookup(record, :rows, _FIT_REPORT_LOOKUP_MISSING)
    rows isa AbstractVector ||
        throw(ArgumentError("fit report table at $path does not contain rows"))
    n_rows = _report_lookup(record, :n_rows, _FIT_REPORT_LOOKUP_MISSING)
    n_rows isa Integer && n_rows == length(rows) ||
        throw(ArgumentError("fit report table at $path has inconsistent n_rows"))
    _fit_report_hash_value(record, :content_hash,
        "fit report table at $path";
        expected_scope = :fit_report_table_without_hash_metadata,
        expected_canonicalization = :cache_stable_string)
    return record
end

function _verify_fit_report_table_record(record, path)
    _fit_report_hash_record_matches_actual(record, :content_hash,
        _fit_report_table_hash_record(record;
            scope = :fit_report_table_without_hash_metadata),
        "fit report table at $path";
        expected_scope = :fit_report_table_without_hash_metadata,
        expected_canonicalization = :cache_stable_string)
    return record
end

function _verify_fit_report_table_manifest(manifest, path)
    _fit_report_hash_record_matches_actual(manifest, :content_hash,
        _fit_report_table_hash_record(manifest;
            scope = :fit_report_table_export_without_hash_metadata),
        "fit report table manifest at $path";
        expected_scope = :fit_report_table_export_without_hash_metadata,
        expected_canonicalization = :cache_stable_string)
    return manifest
end

function _fit_report_table_matches_manifest_row(record, row,
        table_path::AbstractString,
        manifest_path::AbstractString)
    for field in (:section, :row_field)
        expected = _report_symbol_value(_report_lookup(row, field,
            _FIT_REPORT_LOOKUP_MISSING))
        actual = _report_symbol_value(_report_lookup(record, field,
            _FIT_REPORT_LOOKUP_MISSING))
        expected === actual ||
            throw(ArgumentError("fit report table $table_path does not match $(String(field)) in manifest $manifest_path"))
    end
    expected_rows = _report_lookup(row, :n_rows, _FIT_REPORT_LOOKUP_MISSING)
    actual_rows = _report_lookup(record, :n_rows, _FIT_REPORT_LOOKUP_MISSING)
    expected_rows isa Integer && actual_rows isa Integer &&
        expected_rows == actual_rows ||
        throw(ArgumentError("fit report table $table_path does not match n_rows in manifest $manifest_path"))
    actual_hash = _check_fit_report_hash_record(record, :content_hash,
        "fit report table at $table_path";
        expected_scope = :fit_report_table_without_hash_metadata,
        expected_canonicalization = :cache_stable_string)
    _fit_report_hash_record_matches_actual(row, :content_hash, actual_hash,
        "fit report table manifest row at $manifest_path";
        expected_scope = :fit_report_table_without_hash_metadata,
        expected_canonicalization = :cache_stable_string)
    return true
end

function _load_fit_report_table_records(directory::AbstractString, manifest,
        manifest_path::AbstractString;
        verify_hash::Bool)
    records = Any[]
    total_rows = 0
    for row in _fit_report_table_manifest_rows(manifest,
            "fit report table manifest at $manifest_path")
        filename = _fit_report_table_manifest_filename(row,
            "fit report table manifest at $manifest_path")
        table_path = joinpath(directory, filename)
        record = _read_json_dict(table_path, "fit report table")
        record = _check_fit_report_table_record(record, table_path)
        _fit_report_table_matches_manifest_row(record, row, table_path,
            manifest_path)
        verify_hash && _verify_fit_report_table_record(record, table_path)
        total_rows += _report_lookup(record, :n_rows, 0)
        push!(records, record)
    end
    expected_total_rows = _report_lookup(manifest, :n_rows,
        _FIT_REPORT_LOOKUP_MISSING)
    expected_total_rows isa Integer && expected_total_rows == total_rows ||
        throw(ArgumentError("fit report table manifest at $manifest_path has inconsistent n_rows"))
    return records
end

"""
    load_fit_report_tables(directory; verify_hash = true,
        return_manifest = false)

Load a fit-report table export written by [`save_fit_report_tables`](@ref).
By default this verifies the table manifest hash and each table file hash, then
returns a vector of JSON-loaded table records. Set `return_manifest = true` to
inspect the export manifest instead.
"""
function load_fit_report_tables(directory::AbstractString;
        verify_hash::Bool = true,
        return_manifest::Bool = false)
    isdir(directory) ||
        throw(ArgumentError("fit report table export directory does not exist at $directory"))
    manifest_path = _fit_report_table_export_manifest_path(directory)
    manifest = _read_json_dict(manifest_path, "fit report table manifest")
    manifest = _check_fit_report_table_manifest(manifest, manifest_path)
    verify_hash && _verify_fit_report_table_manifest(manifest, manifest_path)
    records = if verify_hash || !return_manifest
        _load_fit_report_table_records(directory, manifest, manifest_path;
            verify_hash)
    else
        nothing
    end
    return_manifest && return manifest
    return records
end

function _cache_stable_write(io::IO, value)
    if value isa NamedTuple
        print(io, "NamedTuple(")
        first_field = true
        for name in keys(value)
            first_field || print(io, ",")
            first_field = false
            print(io, String(name), "=")
            _cache_stable_write(io, getproperty(value, name))
        end
        print(io, ")")
    elseif value isa AbstractDict
        print(io, "Dict(")
        pairs = collect(value)
        sort!(pairs; by = pair -> _cache_stable_string(first(pair)))
        for (index, pair) in enumerate(pairs)
            index == 1 || print(io, ",")
            _cache_stable_write(io, first(pair))
            print(io, "=>")
            _cache_stable_write(io, last(pair))
        end
        print(io, ")")
    elseif value isa Tuple
        print(io, "(")
        for index in eachindex(value)
            index == firstindex(value) || print(io, ",")
            _cache_stable_write(io, value[index])
        end
        print(io, ")")
    elseif value isa AbstractArray
        print(io, "Array(size=")
        _cache_stable_write(io, size(value))
        print(io, ",values=[")
        values = collect(value)
        for index in eachindex(values)
            index == firstindex(values) || print(io, ",")
            _cache_stable_write(io, values[index])
        end
        print(io, "])")
    elseif value isa Symbol
        print(io, ":", String(value))
    elseif value isa AbstractString
        show(io, value)
    elseif value === missing
        print(io, "missing")
    elseif value === nothing
        print(io, "nothing")
    elseif value isa Bool || value isa Number
        show(io, value)
    else
        show(io, value)
    end
    return nothing
end

function _cache_stable_string(value)
    io = IOBuffer()
    _cache_stable_write(io, value)
    return String(take!(io))
end

function _cache_hash(value)
    # Keep canonical bytes unchanged; CodeUnits hashing is quadratic on Julia 1.12.5.
    return bytes2hex(sha256(IOBuffer(_cache_stable_string(value))))
end

const _ARTIFACT_HASH_METADATA_FIELDS = (:content_hash, :archive_manifest)

function _artifact_hash_payload(value)
    if value isa NamedTuple
        names = Symbol[]
        values = Any[]
        for name in keys(value)
            name in _ARTIFACT_HASH_METADATA_FIELDS && continue
            push!(names, name)
            push!(values, _artifact_hash_payload(getproperty(value, name)))
        end
        return NamedTuple{Tuple(names)}(Tuple(values))
    elseif value isa AbstractDict
        out = Dict{Any,Any}()
        for (key, item) in value
            (key === :content_hash || key === :archive_manifest ||
                key == "content_hash" || key == "archive_manifest") && continue
            out[key] = _artifact_hash_payload(item)
        end
        return out
    elseif value isa Tuple
        return map(_artifact_hash_payload, value)
    elseif value isa AbstractArray
        return map(_artifact_hash_payload, value)
    end
    return value
end

"""
    artifact_content_hash(artifact)

Return a stable SHA-256 content hash for an exported fit artifact or report
bundle. The hash is computed from the package's cache-stable representation
after recursively removing `content_hash` and `archive_manifest` metadata
fields, so the value can be stored with an export and recomputed later for
verification.
"""
function artifact_content_hash(artifact)
    return _cache_hash(_artifact_hash_payload(artifact))
end

function _artifact_content_hash_record(artifact)
    payload = _artifact_hash_payload(artifact)
    canonical = _cache_stable_string(payload)
    return (;
        algorithm = :sha256,
        value = bytes2hex(sha256(IOBuffer(canonical))),
        scope = :artifact_without_hash_metadata,
        canonicalization = :cache_stable_string,
        n_canonical_bytes = sizeof(canonical),
    )
end

function _public_fit_artifact_projection(artifact, fit::_ModelComparisonFit)
    projected = _public_fit_report_project_value(
        _artifact_hash_payload(artifact),
    )
    public_payload = merge(projected, (;
        schema = "bayesianmgmfrm.fit_artifact_public.v1",
        object = :fit_artifact,
        family = fit.design.spec.family,
        stability = fit isa MFRMFit ? :stable : :experimental,
        model_manifest = model_manifest(fit.design; view = :public),
        fit_metadata = fit_metadata(fit; view = :public),
    ))
    return merge(public_payload, (;
        content_hash = _artifact_content_hash_record(public_payload),
    ))
end

function _artifact_summary(artifact)
    return (;
        schema = _nt_get(artifact, :schema, missing),
        object = _nt_get(artifact, :object, missing),
        family = _nt_get(artifact, :family, missing),
        scope = _nt_get(artifact, :scope, missing),
        status = _nt_get(artifact, :status, missing),
        created_at = _nt_get(artifact, :created_at, missing),
    )
end

function _manifest_archive_summary(artifact)
    manifest = _nt_get(artifact, :manifest, nothing)
    manifest isa NamedTuple || return nothing
    fit_record = _nt_get(manifest, :fit, NamedTuple())
    diagnostics = _nt_get(manifest, :diagnostics, NamedTuple())
    return (;
        schema = _nt_get(manifest, :schema, missing),
        object = _nt_get(manifest, :object, missing),
        family = _nt_get(manifest, :family, _nt_get(fit_record, :family, missing)),
        scope = _nt_get(manifest, :scope, _nt_get(fit_record, :scope, missing)),
        data_signature =
            _nt_get(_nt_get(manifest, :validation, NamedTuple()), :data_signature,
                _nt_get(fit_record, :data_signature, missing)),
        n_draws = _nt_get(fit_record, :n_draws, missing),
        n_chains = _nt_get(fit_record, :n_chains, missing),
        backend = _nt_get(fit_record, :backend, missing),
        sampler = _nt_get(fit_record, :sampler, missing),
        diagnostic_flag = _nt_get(diagnostics, :flag,
            _nt_get(_nt_get(_nt_get(artifact, :diagnostics, NamedTuple()), :summary, NamedTuple()),
                :flag, missing)),
    )
end

"""
    fit_archive_manifest(artifact; label = nothing, source_path = nothing)
    fit_archive_manifest(fit; kwargs...)

Return a compact long-term archive manifest for a fit artifact. The manifest
records the artifact schema, an embedded SHA-256 content hash, selected
fit/diagnostic metadata, and optional archive labels or source paths. Passing a
fit object first builds its `fit_artifact` with the supplied artifact keywords.
"""
function fit_archive_manifest(artifact::NamedTuple;
        label = nothing,
        source_path = nothing)
    hash_record = _artifact_content_hash_record(artifact)
    return (;
        schema = "bayesianmgmfrm.fit_archive_manifest.v1",
        object = :fit_archive_manifest,
        created_at = string(now()),
        label = label === nothing ? missing : label,
        source_path = source_path === nothing ? missing : String(source_path),
        content_hash = hash_record,
        artifact = _artifact_summary(artifact),
        manifest = _manifest_archive_summary(artifact),
        reproducibility = _nt_get(artifact, :reproducibility, missing),
        archive_policy = (;
            intended_use = :long_term_export_manifest,
            includes_draws =
                _nt_get(_nt_get(artifact, :reproducibility, NamedTuple()),
                    :artifact_policy, NamedTuple()),
            cache_portability = :manifest_and_tables_preferred_cross_version,
        ),
    )
end

function _with_archive_metadata(artifact::NamedTuple;
        label = nothing,
        source_path = nothing)
    archive = fit_archive_manifest(artifact; label, source_path)
    return merge(artifact, (;
        content_hash = archive.content_hash,
        archive_manifest = archive,
    ))
end

function fit_archive_manifest(fit;
        label = nothing,
        source_path = nothing,
        artifact = nothing,
        include_draws::Bool = false,
        include_log_posterior::Bool = include_draws,
        include_sampler_stats::Bool = false,
        include_environment::Bool = true,
        include_packages::Bool = false,
        split_chains::Bool = true,
        rhat_threshold::Real = 1.01,
        ess_threshold::Real = 400)
    fit_artifact_value = artifact === nothing ?
        fit_artifact(fit;
            include_draws,
            include_log_posterior,
            include_sampler_stats,
            include_environment,
            include_packages,
            split_chains,
            rhat_threshold,
            ess_threshold) :
        artifact
    return fit_archive_manifest(fit_artifact_value; label, source_path)
end

function _reproduction_artifact_policy_value(policy, field::Symbol)
    value = _report_lookup(policy, field, _FIT_REPORT_LOOKUP_MISSING)
    value !== _FIT_REPORT_LOOKUP_MISSING[] && return _report_symbol_value(value)
    return missing
end

function _fit_reproduction_optional_property_hash(fit, property::Symbol)
    hasproperty(fit, property) || return missing
    return _cache_hash(getproperty(fit, property))
end

function _fit_reproduction_identity(fit::_ModelComparisonFit)
    metadata = fit_metadata(fit)
    return (;
        fit_type = Symbol(nameof(typeof(fit))),
        data_signature = _report_lookup(metadata, :data_signature, missing),
        family = _report_symbol_value(_report_lookup(metadata, :family, missing)),
        dimensions = _report_lookup(metadata, :dimensions, missing),
        discrimination =
            _report_symbol_value(_report_lookup(metadata, :discrimination, missing)),
        thresholds = _report_symbol_value(_report_lookup(metadata, :thresholds, missing)),
        estimation_status =
            _report_symbol_value(_report_lookup(metadata, :estimation_status, missing)),
        density_space =
            _report_symbol_value(_report_lookup(metadata, :density_space, missing)),
        n_parameters = _report_lookup(metadata, :n_parameters, missing),
        n_direct_parameters = _report_lookup(metadata, :n_direct_parameters, missing),
        n_draws = _report_lookup(metadata, :n_draws, missing),
        n_chains = _report_lookup(metadata, :n_chains, missing),
        draws_per_chain = _report_lookup(metadata, :draws_per_chain, missing),
        backend = _report_symbol_value(_report_lookup(metadata, :backend, missing)),
        sampler = _report_symbol_value(_report_lookup(metadata, :sampler, missing)),
        warmup = _report_lookup(metadata, :warmup, missing),
        step_size = _report_lookup(metadata, :step_size, missing),
        raw_parameter_names = _report_lookup(metadata, :raw_parameter_names, missing),
        direct_parameter_names =
            _report_lookup(metadata, :direct_parameter_names, missing),
        draws_hash = _cache_hash(fit.draws),
        log_posterior_hash = _cache_hash(fit.log_posterior),
        direct_draws_hash =
            _fit_reproduction_optional_property_hash(fit, :direct_draws),
        direct_loglikelihood_hash =
            _fit_reproduction_optional_property_hash(fit, :direct_loglikelihood),
        direct_pointwise_loglikelihood_hash =
            _fit_reproduction_optional_property_hash(
                fit, :direct_pointwise_loglikelihood),
    )
end

function _check_fit_reproduction_cache_matches_fit(cache_record::NamedTuple,
        fit::_ModelComparisonFit,
        context::AbstractString)
    cache_fit = _nt_get(cache_record, :fit, nothing)
    cache_fit isa _ModelComparisonFit ||
        throw(ArgumentError("$context does not contain a fitted cache object"))
    cache_identity = _fit_reproduction_identity(cache_fit)
    fit_identity = _fit_reproduction_identity(fit)
    isequal(cache_identity, fit_identity) ||
        throw(ArgumentError(
            "fit cache record at $context does not match the fit supplied to " *
            "fit_reproduction_manifest",
        ))
    return nothing
end

function _fit_reproduction_full_rerun_path(artifact, archive_manifest)
    reproducibility =
        _report_lookup(artifact, :reproducibility, NamedTuple())
    artifact_policy =
        _report_lookup(reproducibility, :artifact_policy, NamedTuple())
    rng_record = _report_lookup(reproducibility, :rng, NamedTuple())
    replayable = _report_lookup(reproducibility, :replayable_rng, false)
    manifest_summary = _report_lookup(archive_manifest, :manifest, NamedTuple())
    content_hash = _report_lookup(archive_manifest, :content_hash, missing)
    return (;
        path = :full_rerun,
        status = replayable === true ? :ready : :not_replayable,
        evidence = :fit_artifact,
        artifact_schema = _report_lookup(artifact, :schema, missing),
        artifact_object = _report_symbol_value(_report_lookup(artifact, :object, missing)),
        content_hash,
        archive_manifest_schema = _report_lookup(archive_manifest, :schema, missing),
        replayable_rng = replayable === true,
        rng_algorithm = _report_symbol_value(_report_lookup(rng_record, :algorithm, missing)),
        rng_seed = _report_lookup(rng_record, :seed, missing),
        data_signature = _report_lookup(manifest_summary, :data_signature, missing),
        n_draws = _report_lookup(manifest_summary, :n_draws, missing),
        n_chains = _report_lookup(manifest_summary, :n_chains, missing),
        backend = _report_symbol_value(_report_lookup(manifest_summary, :backend, missing)),
        sampler = _report_symbol_value(_report_lookup(manifest_summary, :sampler, missing)),
        diagnostic_flag =
            _report_symbol_value(_report_lookup(manifest_summary, :diagnostic_flag, missing)),
        draws = _reproduction_artifact_policy_value(artifact_policy, :draws),
        raw_draws = _reproduction_artifact_policy_value(artifact_policy, :raw_draws),
        direct_draws = _reproduction_artifact_policy_value(artifact_policy, :direct_draws),
        log_posterior =
            _reproduction_artifact_policy_value(artifact_policy, :log_posterior),
        sampler_stats =
            _reproduction_artifact_policy_value(artifact_policy, :sampler_stats),
        environment =
            _reproduction_artifact_policy_value(artifact_policy, :environment),
        package_status =
            _reproduction_artifact_policy_value(artifact_policy, :package_status),
    )
end

function _fit_reproduction_cache_path(cache_record,
        cache_path,
        verify_cache_hash::Bool,
        fit::_ModelComparisonFit)
    cache_record === nothing && return (;
        path = :fast_cached_draws,
        status = :not_provided,
        evidence = :fit_cache,
        source_path = cache_path === nothing ? missing : String(cache_path),
        cache_key = missing,
        content_hash = missing,
        serialization = missing,
        n_draws = missing,
        backend = missing,
        sampler = missing,
    )
    cache_record isa NamedTuple ||
        throw(ArgumentError("cache_record must be a fit-cache NamedTuple returned by save_fit_cache, load_fit_cache(...; return_record = true), or cached_fit(...; return_record = true)"))
    context = cache_path === nothing ? "provided fit cache record" : String(cache_path)
    _check_fit_cache_record(cache_record, context)
    verify_cache_hash && _verify_fit_cache_record(cache_record, context)
    _check_fit_reproduction_cache_matches_fit(cache_record, fit, context)
    source_path = cache_path === nothing ?
        _nt_get(_nt_get(cache_record, :archive_manifest, NamedTuple()),
            :source_path, missing) :
        String(cache_path)
    artifact_summary =
        _manifest_archive_summary(_nt_get(cache_record, :artifact, NamedTuple()))
    return (;
        path = :fast_cached_draws,
        status = :ready,
        evidence = :fit_cache,
        source_path,
        cache_schema = _nt_get(cache_record, :schema, missing),
        cache_object = _nt_get(cache_record, :object, missing),
        cache_key = _nt_get(cache_record, :cache_key, missing),
        content_hash = _nt_get(cache_record, :artifact_content_hash, missing),
        archive_manifest_schema =
            _nt_get(_nt_get(cache_record, :archive_manifest, NamedTuple()),
                :schema, missing),
        serialization = _nt_get(cache_record, :serialization, missing),
        n_draws = _nt_get(artifact_summary, :n_draws, missing),
        n_chains = _nt_get(artifact_summary, :n_chains, missing),
        backend = _nt_get(artifact_summary, :backend, missing),
        sampler = _nt_get(artifact_summary, :sampler, missing),
        diagnostic_flag = _nt_get(artifact_summary, :diagnostic_flag, missing),
    )
end

function _fit_reproduction_report_bundle_path(report_bundle_manifest,
        report_bundle_path)
    report_bundle_manifest === nothing && return (;
        path = :review_bundle,
        status = :not_provided,
        evidence = :fit_report_bundle,
        source_path = report_bundle_path === nothing ? missing : String(report_bundle_path),
        content_hash = missing,
        n_tables = missing,
        n_rows = missing,
    )
    return (;
        path = :review_bundle,
        status = :ready,
        evidence = :fit_report_bundle,
        source_path = report_bundle_path === nothing ? missing : String(report_bundle_path),
        bundle_schema = _report_lookup(report_bundle_manifest, :schema, missing),
        bundle_object =
            _report_symbol_value(_report_lookup(report_bundle_manifest, :object, missing)),
        content_hash = _report_lookup(report_bundle_manifest, :content_hash, missing),
        n_tables = _report_lookup(report_bundle_manifest, :n_tables, missing),
        n_rows = _report_lookup(report_bundle_manifest, :n_rows, missing),
    )
end

function _fit_reproduction_missing_required_paths(paths)
    missing_paths = Symbol[]
    for path in paths
        _report_lookup(path, :status, missing) === :ready && continue
        push!(missing_paths, _report_lookup(path, :path, :unknown))
    end
    return Tuple(missing_paths)
end

function _fit_reproduction_manifest_payload(fit;
        label,
        artifact,
        source_path,
        cache_record,
        cache_path,
        report_bundle_manifest,
        report_bundle_path,
        verify_cache_hash::Bool,
        include_draws::Bool,
        include_log_posterior::Bool,
        include_sampler_stats::Bool,
        include_environment::Bool,
        include_packages::Bool,
        split_chains::Bool,
        rhat_threshold::Real,
        ess_threshold::Real)
    fit_artifact_value = artifact === nothing ?
        fit_artifact(fit;
            include_draws,
            include_log_posterior,
            include_sampler_stats,
            include_environment,
            include_packages,
            split_chains,
            rhat_threshold,
            ess_threshold) :
        artifact
    archive_manifest = fit_archive_manifest(fit_artifact_value;
        label = label === nothing ? :fit_reproduction_full_rerun : label,
        source_path)
    full_rerun = _fit_reproduction_full_rerun_path(
        fit_artifact_value, archive_manifest)
    fast_cached_draws = _fit_reproduction_cache_path(
        cache_record, cache_path, verify_cache_hash, fit)
    review_bundle = _fit_reproduction_report_bundle_path(
        report_bundle_manifest, report_bundle_path)
    missing_required_paths =
        _fit_reproduction_missing_required_paths((full_rerun, fast_cached_draws))
    status = isempty(missing_required_paths) ? :ready : :incomplete
    return (;
        schema = "bayesianmgmfrm.fit_reproduction_manifest.v1",
        object = :fit_reproduction_manifest,
        created_at = string(now()),
        label = label === nothing ? missing : label,
        status,
        family = _report_symbol_value(_report_lookup(fit_metadata(fit), :family, missing)),
        required_paths = (:full_rerun, :fast_cached_draws),
        optional_paths = (:review_bundle,),
        missing_required_paths,
        n_ready_required_paths = 2 - length(missing_required_paths),
        publication_or_registration_action = false,
        manuscript_claims_allowed = false,
        next_gate = :manual_publication_or_registration_by_user_only,
        full_rerun,
        fast_cached_draws,
        review_bundle,
        archive_manifest,
    )
end

"""
    fit_reproduction_manifest(fit; view = :full, cache_record = nothing, cache_path = nothing,
        report_bundle_manifest = nothing, report_bundle_path = nothing,
        artifact = nothing, verify_cache_hash = true, kwargs...)

Build a machine-readable reproduction manifest for a fitted object. The
manifest treats full rerun evidence and fast cached-draw evidence as separate
required paths: full rerun is ready only when the fit artifact records a
replayable RNG seed and sampler controls, while fast cached draws are ready only
when a hash-verified fit-cache record is supplied. Optional fit-report bundle
metadata can be attached for review exports. The compatibility default
`view = :full` retains complete compatibility metadata. Use
`view = :public` for a reader-facing projection without machine-local paths or
maintainer workflow fields.
"""
function fit_reproduction_manifest(fit::_ModelComparisonFit;
        view::Symbol = :full,
        label = nothing,
        artifact = nothing,
        source_path = nothing,
        cache_record = nothing,
        cache_path = nothing,
        report_bundle_manifest = nothing,
        report_bundle_path = nothing,
        verify_cache_hash::Bool = true,
        include_draws::Bool = false,
        include_log_posterior::Bool = include_draws,
        include_sampler_stats::Bool = false,
        include_environment::Bool = true,
        include_packages::Bool = false,
        split_chains::Bool = true,
        rhat_threshold::Real = 1.01,
        ess_threshold::Real = 400)
    view in (:full, :public) ||
        throw(ArgumentError("view must be :full or :public"))
    payload = _fit_reproduction_manifest_payload(fit;
        label,
        artifact,
        source_path,
        cache_record,
        cache_path,
        report_bundle_manifest,
        report_bundle_path,
        verify_cache_hash,
        include_draws,
        include_log_posterior,
        include_sampler_stats,
        include_environment,
        include_packages,
        split_chains,
        rhat_threshold,
        ess_threshold)
    result = merge(payload, (;
        content_hash = _artifact_content_hash_record(payload),
    ))
    view === :full && return result
    projected = _public_fit_report_project_value(payload)
    public_payload = merge((;
        schema = "bayesianmgmfrm.fit_reproduction_manifest_public.v1",
        object = :fit_reproduction_manifest,
    ), projected)
    return merge(public_payload, (;
        content_hash = _artifact_content_hash_record(public_payload),
    ))
end

function _prior_cache_record(prior::MFRMPrior)
    return (;
        prior_contract = :mfrm_independent_normal,
        person_sd = prior.person_sd,
        rater_sd = prior.rater_sd,
        item_sd = prior.item_sd,
        step_sd = prior.step_sd,
    )
end

function _prior_cache_record(prior::_SourceFixturePrior)
    return (;
        prior_contract = :source_fixture_raw_coordinate_normal,
        person_sd = prior.person_sd,
        rater_sd = prior.rater_sd,
        item_sd = prior.item_sd,
        log_discrimination_sd = prior.log_discrimination_sd,
        log_consistency_sd = prior.log_consistency_sd,
        step_sd = prior.step_sd,
    )
end

function _require_cache_replayable_rng(rng_control::NamedTuple)
    _nt_get(rng_control, :replayable, false) === true ||
        throw(ArgumentError(
            "fit cache keys require a replayable RNG seed; pass seed = <integer> " *
            "or use fit/save_fit_cache manually for unseeded exploratory fits",
        ))
    return nothing
end

function _fit_cache_controls(backend::Symbol,
        ndraws::Int,
        warmup::Int,
        chains::Int,
        step_size::Real,
        rng_control::NamedTuple,
        initial::Vector{Float64};
        target_accept::Real,
        max_depth::Int,
        max_energy_error::Real,
        metric::Symbol,
        ad_backend::Symbol,
        init_jitter::Real)
    step_size = _check_fit_controls(ndraws, warmup, chains, step_size)
    if backend in (:advancedhmc, :turing)
        target_accept, max_energy_error, init_jitter =
            _check_nuts_controls(target_accept, max_depth, max_energy_error, init_jitter)
    end
    initialization = (;
        n_parameters = length(initial),
        hash = _cache_hash(initial),
    )
    if backend === :julia
        return (;
            backend,
            sampler = :random_walk_metropolis,
            ndraws,
            warmup,
            chains,
            step_size = Float64(step_size),
            rng = rng_control,
            initialization,
            init_jitter = 0.0,
        )
    elseif backend === :advancedhmc
        gradient_backend = _gradient_backend_kind(ad_backend)
        return (;
            backend,
            sampler = :nuts,
            ndraws,
            warmup,
            chains,
            step_size = Float64(step_size),
            target_accept = Float64(target_accept),
            max_depth,
            max_energy_error = Float64(max_energy_error),
            metric,
            ad_backend,
            gradient_backend,
            rng = rng_control,
            initialization,
            init_jitter = Float64(init_jitter),
        )
    elseif backend === :turing
        _check_turing_ad_backend(ad_backend)
        _turing_metric_type(metric)
        return (;
            backend,
            sampler = :nuts,
            ndraws,
            warmup,
            chains,
            step_size = Float64(step_size),
            target_accept = Float64(target_accept),
            max_depth,
            max_energy_error = Float64(max_energy_error),
            metric,
            ad_backend,
            gradient_backend = :ad,
            rng = rng_control,
            initialization,
            init_jitter = Float64(init_jitter),
            turing_model = :mfrm_logdensity_flat_parameter_model,
            chain_type = :raw_transitions,
            nadapts = warmup,
            discard_initial = _turing_discard_initial(warmup),
        )
    end
    throw(ArgumentError("backend must be :julia, :advancedhmc, or :turing"))
end

_fit_cache_default_prior(::FacetDesign, experimental::Bool) =
    experimental ? nothing : MFRMPrior()

function _fit_cache_prior(design::FacetDesign, prior, experimental::Bool)
    if experimental
        design.spec.family === :gmfrm && return _experimental_gmfrm_prior(prior)
        design.spec.family === :mgmfrm && return _guarded_mgmfrm_prior(prior)
        throw(ArgumentError(
            "fit caches currently support only family = :gmfrm or :mgmfrm"))
    end
    prior isa MFRMPrior ||
        throw(ArgumentError("non-fit caches require an MFRMPrior"))
    return prior
end

function _fit_cache_initial(design::FacetDesign, init, prior, experimental::Bool)
    if experimental
        design.spec.family === :gmfrm && return _experimental_gmfrm_initial(
            _gmfrm_promotion_candidate_logdensity(design; prior),
            init,
        )
        design.spec.family === :mgmfrm && return _guarded_mgmfrm_initial(
            _mgmfrm_guarded_local_fit_logdensity(design; prior),
            init,
        )
        throw(ArgumentError(
            "fit caches currently support only family = :gmfrm or :mgmfrm"))
    end
    return _fit_initial_params(design, init)
end

function _fit_cache_design(spec::FacetSpec, experimental::Bool)
    _reject_mfrm_fixed_q_fit(spec, "fit cache request")
    if experimental
        _check_guarded_generalized_spec(
            spec,
            "fit cache request",
        )
        return getdesign(spec; preview = true)
    end
    return getdesign(spec)
end

function _fit_cache_request(design::FacetDesign;
        experimental::Bool = false,
        prior = _fit_cache_default_prior(design, experimental),
        backend::Symbol = :julia,
        ndraws::Int = 1000,
        warmup::Int = 1000,
        chains::Int = 1,
        step_size::Real = 0.05,
        init = nothing,
        rng::AbstractRNG = Random.default_rng(),
        seed = nothing,
        target_accept::Real = 0.8,
        max_depth::Int = 10,
        max_energy_error::Real = 1000.0,
        metric::Symbol = :diagonal,
        ad_backend::Symbol = :ForwardDiff,
        init_jitter::Real = 0.0,
        sampling_coordinates::Symbol = :raw,
        progress::Union{Bool,SamplingProgress} = false,
        chain_execution::Symbol = :serial,
        max_parallel_chains::Int = chains)
    _check_sampling_progress(progress, backend)
    _check_chain_execution(chain_execution, max_parallel_chains, backend; allow_auto = true)
    _require_canonical_design(design, "fit cache request")
    _reject_mfrm_fixed_q_fit(design.spec, "fit cache request")
    _check_mgmfrm_sampling_coordinates(design.spec, sampling_coordinates, backend, experimental)
    experimental && backend !== :advancedhmc &&
        throw(ArgumentError(
            "fit caches currently support only backend = :advancedhmc"))
    checked_prior = _fit_cache_prior(design, prior, experimental)
    initial = _fit_cache_initial(design, init, checked_prior, experimental)
    _, rng_control = _fit_rng(rng, seed)
    _require_cache_replayable_rng(rng_control)
    controls = _fit_cache_controls(backend, ndraws, warmup, chains, step_size,
        rng_control, initial;
        target_accept,
        max_depth,
        max_energy_error,
        metric,
        ad_backend,
        init_jitter)
    eff_chain_exec = _resolve_chain_execution(chain_execution, chains, max_parallel_chains, backend)
    eff_chain_exec === :serial || (controls = merge(controls,
        (; chain_execution=:threads, rng_partition=:chain_seed_v1)))
    # Omit the default coordinate tag to preserve existing request bytes and keys.
    sampling_coordinates === :raw || (controls = merge(controls, (; sampling_coordinates)))
    return (;
        schema = "bayesianmgmfrm.fit_request.v2",
        julia_version = string(VERSION),
        data_signature = design.spec.validation.data_signature,
        manifest = isempty(design.spec.anchors) ? model_manifest(design) : (;
            schema = "bayesianmgmfrm.anchor_fit_cache_identity.v1",
            design_identity = design_identity(design),
        ),
        experimental,
        parameter_space = experimental ? :raw_unconstrained : :direct_identified,
        diagnostic_contract = _mcmc_diagnostic_contract_record(),
        prior = _prior_cache_record(checked_prior),
        controls,
    )
end

"""
    fit_cache_key(spec_or_design; kwargs...)

Return the deterministic cache key used by [`cached_fit`](@ref). The key hashes
the data/spec/design manifest, prior scales, backend-specific sampler controls,
RNG seed metadata, Julia version, initial-parameter hash, and versioned MCMC
diagnostic contract. The `progress`
keyword is accepted for API symmetry with [`fit`](@ref) but is not included in
the key because it does not affect posterior draws. Cache keys require
`seed = <integer>` so automatic cache reuse is tied to a replayable fit request.
Anchored designs use the canonical semantic design identity, so reordering
otherwise identical anchor declarations does not change the key.
Numeric sampler controls use the same bounds as [`fit`](@ref) and are checked
before cache lookup.
For independent MGMFRM, `sampling_coordinates` also distinguishes
the optional `:orthogonal_person_mean_item_offset` computation. Omitting it or
passing `:raw` retains the existing default key and model/prior identity.
"""
function fit_cache_key(design::FacetDesign; kwargs...)
    norm_kw = _normalize_stan_nuts_kwargs(kwargs; caller = "fit_cache_key", emit_info = false)
    return _cache_hash(_fit_cache_request(design; norm_kw...))
end

function fit_cache_key(spec::FacetSpec; experimental::Bool = false, kwargs...)
    return fit_cache_key(
        _fit_cache_design(spec, experimental);
        experimental,
        kwargs...,
    )
end

function _fit_cache_record(fit::_ModelComparisonFit;
        cache_key,
        artifact,
        source_path = nothing)
    archive_manifest = fit_archive_manifest(artifact;
        label = :fit_cache_artifact,
        source_path)
    return (;
        schema = "bayesianmgmfrm.fit_cache.v1",
        object = :fit_cache,
        created_at = string(now()),
        serialization = (;
            format = :julia_serialization,
            julia_version = string(VERSION),
            portability = :same_julia_major_minor_recommended,
        ),
        cache_key = cache_key === nothing ? missing : String(cache_key),
        artifact_content_hash = archive_manifest.content_hash,
        archive_manifest,
        fit,
        artifact,
    )
end

function _fit_cache_artifact(fit;
        artifact_include_draws::Bool,
        artifact_include_log_posterior::Bool,
        artifact_include_sampler_stats::Bool,
        artifact_include_environment::Bool,
        artifact_include_packages::Bool,
        artifact_split_chains::Bool,
        artifact_rhat_threshold::Real,
        artifact_ess_threshold::Real)
    return fit_artifact(fit;
        include_draws = artifact_include_draws,
        include_log_posterior = artifact_include_log_posterior,
        include_sampler_stats = artifact_include_sampler_stats,
        include_environment = artifact_include_environment,
        include_packages = artifact_include_packages,
        split_chains = artifact_split_chains,
        rhat_threshold = artifact_rhat_threshold,
        ess_threshold = artifact_ess_threshold)
end

"""
    save_fit_cache(path, fit;
                   cache_key = nothing, overwrite = false,
                   artifact = nothing, ...)

Serialize a fitted object and a reproducibility artifact to `path` using
Julia's standard `Serialization` format. This is intended as an RDS-like cache
for avoiding recomputation in the same Julia analysis environment. The cache
contains the full fitted object; artifact draw duplication is omitted by default
unless requested with the `artifact_include_*` keywords.
Fixed-coefficient multidimensional MFRM results use the v2 cache format and
require an artifact that agrees with their canonical sample. Existing MFRM,
GMFRM and MGMFRM caches retain v1.
Explicit correlated MGMFRM results use a separate
`correlated_mgmfrm_fit_cache.v1` schema with mandatory sample/artifact agreement.

The record is written to a temporary file in the destination directory before
publication. A failed write leaves any existing cache intact. With
`overwrite = false`, a destination created during serialization is also preserved.
With `overwrite = true`, the completed file replaces the destination path
(including a symbolic link itself).
"""
function save_fit_cache(path::AbstractString,
        fit::_ModelComparisonFit; kwargs...)
    return _save_fit_cache(path, fit; kwargs...)
end

function _save_fit_cache(path::AbstractString,
        fit;
        cache_key = nothing,
        overwrite::Bool = false,
        artifact = nothing,
        artifact_include_draws::Bool = false,
        artifact_include_log_posterior::Bool = artifact_include_draws,
        artifact_include_sampler_stats::Bool = false,
        artifact_include_environment::Bool = false,
        artifact_include_packages::Bool = false,
        artifact_split_chains::Bool = true,
        artifact_rhat_threshold::Real = 1.01,
        artifact_ess_threshold::Real = 400)
    (ispath(path) || islink(path)) && !overwrite &&
        throw(ArgumentError("fit cache already exists at $path; pass overwrite = true to replace it"))
    _fit_warmup_diagnostics(fit)
    cache_artifact = artifact === nothing ?
        _fit_cache_artifact(fit;
            artifact_include_draws,
            artifact_include_log_posterior,
            artifact_include_sampler_stats,
            artifact_include_environment,
            artifact_include_packages,
            artifact_split_chains,
            artifact_rhat_threshold,
            artifact_ess_threshold) :
        artifact
    record = _fit_cache_record(fit;
        cache_key,
        artifact = cache_artifact,
        source_path = path)
    return _save_serialized_record(path, record; overwrite)
end

# Shared atomic publication for trusted, same-environment Julia records.
# Nested metadata layouts should not generate a separate compiled writer.
Base.@nospecializeinfer function _save_serialized_record(path::AbstractString,
        @nospecialize(record); overwrite::Bool = false)
    (ispath(path) || islink(path)) && !overwrite &&
        throw(ArgumentError("a record already exists at $path; pass overwrite = true to replace it"))
    mkpath(dirname(path))
    mktemp(dirname(path)) do temporary, io
        serialize(io, record)
        close(io)
        if overwrite
            # Julia 1.10's rename helper falls back to copy/remove on failure.
            # Use the native operation so a failed replacement preserves the cache.
            err = ccall(:jl_fs_rename, Int32, (Cstring, Cstring), temporary, path)
            err < 0 && Base.uv_error("rename($(repr(temporary)), $(repr(path)))", err)
        else
            hardlink(temporary, path)
        end
    end
    return record
end

Base.@nospecializeinfer function _check_fit_cache_record(@nospecialize(record), path)
    record isa NamedTuple ||
        throw(ArgumentError("fit cache at $path does not contain a NamedTuple record"))
    canonical_mfrm = isequal(_nt_get(record, :schema, nothing), "bayesianmgmfrm.fit_cache.v2")
    if canonical_mfrm
        _check_mfrm_fixed_q_cache_record(record, path)
    elseif _nt_get(record, :schema, nothing) in ("bayesianmgmfrm.correlated_mgmfrm_fit_cache.v1",
            "bayesianmgmfrm.normalized_mgmfrm_fit_cache.v1")
        _check_mgmfrm_correlated_2d_cache_record(record, path)
    else
        _nt_get(record, :schema, nothing) == "bayesianmgmfrm.fit_cache.v1" ||
        throw(ArgumentError("fit cache at $path has an unsupported schema"))
        _nt_get(record, :fit, nothing) isa _ModelComparisonFit ||
            throw(ArgumentError(
                "fit cache at $path does not contain an MFRMFit, GMFRMFit, or MGMFRMFit"))
    end
    _nt_get(record, :object, nothing) === :fit_cache ||
        throw(ArgumentError("fit cache at $path has an unsupported object"))
    _nt_get(record, :artifact, nothing) isa NamedTuple ||
        throw(ArgumentError("fit cache at $path does not contain a fit artifact"))
    _cache_hash_value(record, :artifact_content_hash,
        "fit cache at $path")
    archive = _nt_get(record, :archive_manifest, nothing)
    archive isa NamedTuple ||
        throw(ArgumentError("fit cache at $path does not contain an archive manifest"))
    _cache_hash_value(archive, :content_hash,
        "fit cache archive manifest at $path")
    _check_optional_cache_hash_value(record.artifact, :content_hash,
        "fit cache artifact at $path")
    artifact_archive = _nt_get(record.artifact, :archive_manifest, nothing)
    if artifact_archive !== nothing
        artifact_archive isa NamedTuple ||
            throw(ArgumentError("fit cache artifact at $path has an invalid archive manifest"))
        _cache_hash_value(artifact_archive, :content_hash,
            "fit cache artifact archive manifest at $path")
    end
    return record
end

function _cache_hash_value(record::NamedTuple,
        field::Symbol,
        context::AbstractString;
        expected_scope::Symbol = :artifact_without_hash_metadata,
        expected_canonicalization::Symbol = :cache_stable_string)
    hash_record = _nt_get(record, field, nothing)
    hash_record isa NamedTuple ||
        throw(ArgumentError("$context does not contain $(String(field))"))
    _nt_get(hash_record, :algorithm, nothing) === :sha256 ||
        throw(ArgumentError("$context has an unsupported $(String(field)) algorithm"))
    value = _nt_get(hash_record, :value, nothing)
    value isa AbstractString && occursin(r"^[0-9a-f]{64}$", value) ||
        throw(ArgumentError("$context has an invalid $(String(field)) value"))
    _nt_get(hash_record, :scope, nothing) === expected_scope ||
        throw(ArgumentError("$context has an unsupported $(String(field)) scope"))
    _nt_get(hash_record, :canonicalization, nothing) === expected_canonicalization ||
        throw(ArgumentError("$context has an unsupported $(String(field)) canonicalization"))
    return value
end

function _check_optional_cache_hash_value(record::NamedTuple,
        field::Symbol,
        context::AbstractString)
    _nt_get(record, field, nothing) === nothing && return nothing
    _cache_hash_value(record, field, context)
    return nothing
end

function _fit_cache_summary_rows_equal(actual, expected)
    actual isa AbstractVector && length(actual) == length(expected) || return false
    return all(zip(actual, expected)) do (a, b)
        a isa NamedTuple && keys(a) == keys(b) || return false
        isequal(a, b) && return true
        # Old summaries used a floating-point complement instead of a tie count.
        # Accept that exact formula only; never rewrite the archived row.
        if all(k -> hasproperty(b, k), (:probability_positive, :probability_negative, :probability_equal)) &&
                isequal(a.probability_equal, 1 - b.probability_positive - b.probability_negative)
            a = merge(a, (; probability_equal = b.probability_equal))
            isequal(a, b) && return true
        end
        moments = (; mean = nothing, sd = nothing)
        isequal(Base.structdiff(a, moments), Base.structdiff(b, moments)) || return false
        # Recomputed reductions need not be bitwise identical. Scale by spread
        # as well as location so cancellation near a zero mean remains covered.
        all(x -> x isa Float64 && isfinite(x), (a.mean, a.sd, b.mean, b.sd)) || return false
        a.sd >= 0 && b.sd >= 0 && b.n_draws > 1 || return false
        budget = 8.0 * b.n_draws * eps(Float64)
        0 < budget < 1 || return false
        tolerance = budget * max(abs(b.mean), b.sd)
        isfinite(tolerance) || return false
        return abs(a.mean - b.mean) <= tolerance && abs(a.sd - b.sd) <= tolerance
    end
end

const _CACHE_DIAG_ROW_FLOATS = (
    :rhat, :ess, :rank_normalized_rhat, :bulk_rank_normalized_rhat,
    :folded_rank_normalized_rhat, :bulk_ess, :tail_ess,
    :max_rhat, :min_ess, :max_rank_normalized_rhat, :min_bulk_ess, :min_tail_ess,
)
const _CACHE_DIAG_SUMMARY_FLOATS = (
    :max_rhat, :min_ess, :max_rank_normalized_rhat, :min_bulk_ess, :min_tail_ess,
)
const _CACHE_NESTED_METRIC_SUMMARIES = (
    :raw_diagnostic_metrics, :direct_diagnostic_metrics, :combined_diagnostic_metrics,
)

function _fit_cache_float_close(a, b, n_draws::Int)
    isequal(a, b) && return true
    a isa Float64 && b isa Float64 && isfinite(a) && isfinite(b) && n_draws > 1 || return false
    budget = 8.0 * n_draws * eps(Float64)
    0 < budget < 1 || return false
    tol = budget * max(abs(b), 1.0)
    return isfinite(tol) && abs(a - b) <= tol
end

function _fit_cache_diag_summary_equal(a, b, n_draws::Int)
    isequal(a, b) && return true
    a isa NamedTuple && b isa NamedTuple && keys(a) == keys(b) || return false
    float_keys = [k for k in _CACHE_DIAG_SUMMARY_FLOATS if hasproperty(b, k)]
    nested_keys = [k for k in _CACHE_NESTED_METRIC_SUMMARIES if hasproperty(b, k)]
    mask = (; (k => nothing for k in (float_keys..., nested_keys...))...)
    isequal(Base.structdiff(a, mask), Base.structdiff(b, mask)) || return false
    all(k -> _fit_cache_float_close(getfield(a, k), getfield(b, k), n_draws), float_keys) || return false
    return all(k -> _fit_cache_diag_summary_equal(getfield(a, k), getfield(b, k), n_draws), nested_keys)
end

function _fit_cache_diag_rows_equal(actual, expected, n_draws::Int)
    isequal(actual, expected) && return true
    actual isa AbstractVector && expected isa AbstractVector && length(actual) == length(expected) || return false
    return all(zip(actual, expected)) do (a, b)
        isequal(a, b) && return true
        a isa NamedTuple && b isa NamedTuple && keys(a) == keys(b) || return false
        mask = (; (k => nothing for k in _CACHE_DIAG_ROW_FLOATS if hasproperty(b, k))...)
        isequal(Base.structdiff(a, mask), Base.structdiff(b, mask)) || return false
        all(k -> _fit_cache_float_close(getfield(a, k), getfield(b, k), n_draws), keys(mask))
    end
end

function _fit_cache_diagnostics_equal(a, b)
    isequal(a, b) && return true
    a isa NamedTuple && b isa NamedTuple && keys(a) == keys(b) || return false
    s_b = _nt_get(b, :summary, nothing)
    n_draws = s_b isa NamedTuple ? Int(_nt_get(s_b, :total_draws, 0)) : 0
    n_draws > 1 || return false
    return all(keys(b)) do k
        va, vb = getfield(a, k), getfield(b, k)
        if k in (:summary, :raw_summary, :direct_summary, :model_summary,
                 :raw_metrics, :direct_metrics, :combined_metrics, :metric_fields, :location_summary)
            _fit_cache_diag_summary_equal(va, vb, n_draws)
        elseif k in (:rows, :raw_rows, :direct_rows, :model_rows,
                     :parameter_rows, :direct_parameter_rows, :model_parameter_rows,
                     :block_rows, :direct_block_rows, :location_rows)
            _fit_cache_diag_rows_equal(va, vb, n_draws)
        else
            isequal(va, vb)
        end
    end
end

function _fit_cache_manifest_equal(a, b, n_draws::Int)
    isequal(a, b) && return true
    a isa NamedTuple && b isa NamedTuple && keys(a) == keys(b) && hasproperty(b, :diagnostics) || return false
    isequal(Base.structdiff(a, (; diagnostics = nothing)), Base.structdiff(b, (; diagnostics = nothing))) || return false
    return _fit_cache_diag_summary_equal(a.diagnostics, b.diagnostics, n_draws)
end

function _fit_cache_artifact_equal(actual::NamedTuple, expected::NamedTuple)
    keys(actual) == keys(expected) || return false
    diag_exp = _nt_get(expected, :diagnostics, nothing)
    s_exp = diag_exp isa NamedTuple ? _nt_get(diag_exp, :summary, nothing) : nothing
    n_draws = s_exp isa NamedTuple ? Int(_nt_get(s_exp, :total_draws, 0)) : 0
    return all(keys(expected)) do key
        if key in (:posterior_summary, :direct_posterior_summary)
            _fit_cache_summary_rows_equal(actual[key], expected[key])
        elseif key === :diagnostics
            _fit_cache_diagnostics_equal(actual[key], expected[key])
        elseif key === :manifest && n_draws > 1
            _fit_cache_manifest_equal(actual[key], expected[key], n_draws)
        else
            isequal(actual[key], expected[key])
        end
    end
end

function _verify_fit_cache_record(record::NamedTuple, path::AbstractString)
    expected = _cache_hash_value(record, :artifact_content_hash,
        "fit cache at $path")
    actual = artifact_content_hash(record.artifact)
    isequal(expected, actual) ||
        throw(ArgumentError("fit cache artifact content hash mismatch for $path"))
    embedded_hash = _nt_get(record.artifact, :content_hash, nothing)
    if embedded_hash isa NamedTuple
        embedded = _cache_hash_value(record.artifact, :content_hash,
            "fit cache artifact at $path")
        isequal(embedded, actual) ||
            throw(ArgumentError("fit cache embedded artifact hash mismatch for $path"))
    end
    archive = _nt_get(record, :archive_manifest, nothing)
    archive isa NamedTuple ||
        throw(ArgumentError("fit cache at $path does not contain an archive manifest"))
    archive_hash = _cache_hash_value(archive, :content_hash,
        "fit cache archive manifest at $path")
    isequal(archive_hash, actual) ||
        throw(ArgumentError("fit cache archive manifest hash mismatch for $path"))
    artifact_archive = _nt_get(record.artifact, :archive_manifest, nothing)
    if artifact_archive isa NamedTuple
        artifact_archive_hash = _cache_hash_value(artifact_archive,
            :content_hash, "fit cache artifact archive manifest at $path")
        isequal(artifact_archive_hash, actual) ||
            throw(ArgumentError("fit cache artifact archive manifest hash mismatch for $path"))
    end
    return record
end

"""
    load_fit_cache(path; expected_cache_key = nothing, verify_hash = true,
                   return_record = false)

Load a serialized fit cache. By default the cached fit object is returned. Set
`return_record = true` to inspect the cache metadata and artifact. When
`expected_cache_key` is supplied, loading fails unless the stored key matches.
By default loading also verifies the stored artifact content hash and archive
manifest hashes, while cache/hash metadata shape is always checked. Set
`verify_hash = false` to inspect an older or exploratory cache record with an
artifact payload hash mismatch.
For fixed-coefficient multidimensional MFRM v2 caches, sample integrity,
artifact agreement and archive hashes are always verified, including when
`verify_hash = false` is supplied. Loading does not run a sampler or regenerate
the saved environment metadata.
Explicit correlated MGMFRM caches likewise always verify their sample,
artifact and archive integrity, even with `verify_hash = false`.
Recorded-fit readers allow roundoff-sized differences in recomputed summary
means/SDs and the exact historical complement formula for `probability_equal`.
New summaries count ties directly. Saved payload hashes, other summary fields
and metadata remain exact; loading never rewrites the stored summaries.
"""
function load_fit_cache(path::AbstractString;
        expected_cache_key = nothing,
        verify_hash::Bool = true,
        return_record::Bool = false)
    isfile(path) ||
        throw(ArgumentError("fit cache does not exist at $path"))
    record = open(path, "r") do io
        deserialize(io)
    end
    record = _check_fit_cache_record(record, path)
    _fit_warmup_diagnostics(record.fit)
    if expected_cache_key !== nothing && !isequal(record.cache_key, String(expected_cache_key))
        throw(ArgumentError("fit cache key mismatch for $path"))
    end
    (verify_hash || record.schema in ("bayesianmgmfrm.fit_cache.v2",
        "bayesianmgmfrm.correlated_mgmfrm_fit_cache.v1",
        "bayesianmgmfrm.normalized_mgmfrm_fit_cache.v1")) &&
        _verify_fit_cache_record(record, path)
    return return_record ? record : record.fit
end

function _check_cache_path(cache_path)
    cache_path === nothing &&
        throw(ArgumentError("cache_path is required"))
    return String(cache_path)
end

"""
    cached_fit(spec_or_design; cache_path, refresh = false, return_record = false,
               kwargs...)

Fit with an RDS-like serialized cache. Automatic cache keys require
`seed = <integer>` so cache reuse is tied to replayable posterior draws. If
`cache_path` exists and its cache key matches the current data/spec/design,
prior, sampler controls, seed, Julia version, and initialization hash, the
cached fit is returned without recomputation. If the file is absent, or
`refresh = true`, the model is fit and the result is saved. A key mismatch
raises an error rather than silently reusing stale draws.
Without `refresh = true`, a cache created while fitting is also preserved
and saving raises an error.
An exception or interruption during fitting propagates without publishing a
partial fit. A failed `refresh = true` fit leaves the previous cache intact.
"""
function cached_fit(design::FacetDesign;
        cache_path = nothing,
        refresh::Bool = false,
        return_record::Bool = false,
        experimental::Bool = false,
        prior = _fit_cache_default_prior(design, experimental),
        backend::Symbol = :julia,
        ndraws::Int = 1000,
        warmup::Int = 1000,
        chains::Int = 1,
        step_size::Real = 0.05,
        init = nothing,
        rng::AbstractRNG = Random.default_rng(),
        seed = nothing,
        target_accept::Union{Nothing,Real} = nothing,
        adapt_delta::Union{Nothing,Real} = nothing,
        max_depth::Union{Nothing,Int} = nothing,
        max_treedepth::Union{Nothing,Int} = nothing,
        max_energy_error::Real = 1000.0,
        metric::Symbol = :diagonal,
        ad_backend::Symbol = :ForwardDiff,
        init_jitter::Real = 0.0,
        sampling_coordinates::Symbol = :raw,
        progress::Union{Bool,SamplingProgress} = false,
        chain_execution::Symbol = :serial,
        max_parallel_chains::Int = chains,
        artifact_include_draws::Bool = false,
        artifact_include_log_posterior::Bool = artifact_include_draws,
        artifact_include_sampler_stats::Bool = false,
        artifact_include_environment::Bool = false,
        artifact_include_packages::Bool = false,
        artifact_split_chains::Bool = true,
        artifact_rhat_threshold::Real = 1.01,
        artifact_ess_threshold::Real = 400)
    ta_resolved, md_resolved = _resolve_stan_nuts_aliases(;
        target_accept, adapt_delta, default_target_accept = 0.8,
        max_depth, max_treedepth, default_max_depth = 10,
        caller = "cached_fit", backend)
    target_accept = ta_resolved
    max_depth = md_resolved
    path = _check_cache_path(cache_path)
    checked_prior = _fit_cache_prior(design, prior, experimental)
    key = fit_cache_key(design;
        experimental,
        prior = checked_prior,
        backend,
        ndraws,
        warmup,
        chains,
        step_size,
        init,
        rng,
        seed,
        target_accept,
        max_depth,
        max_energy_error,
        metric,
        ad_backend,
        init_jitter,
        sampling_coordinates,
        progress, chain_execution, max_parallel_chains)
    if isfile(path) && !refresh
        record = load_fit_cache(path; expected_cache_key = key, return_record = true)
        return return_record ? record : record.fit
    end
    fit_result = if experimental
        fit(design.spec;
            experimental = true,
            prior = checked_prior,
            backend,
            ndraws,
            warmup,
            chains,
            step_size,
            init,
            rng,
            seed,
            target_accept,
            max_depth,
            max_energy_error,
            metric,
            ad_backend,
            init_jitter,
            sampling_coordinates,
            progress, chain_execution, max_parallel_chains)
    else
        fit(design;
            prior = checked_prior,
            backend,
            ndraws,
            warmup,
            chains,
            step_size,
            init,
            rng,
            seed,
            target_accept,
            max_depth,
            max_energy_error,
            metric,
            ad_backend,
            init_jitter,
            progress, chain_execution, max_parallel_chains)
    end
    record = save_fit_cache(path, fit_result;
        cache_key = key,
        overwrite = refresh,
        artifact_include_draws,
        artifact_include_log_posterior,
        artifact_include_sampler_stats,
        artifact_include_environment,
        artifact_include_packages,
        artifact_split_chains,
        artifact_rhat_threshold,
        artifact_ess_threshold)
    return return_record ? record : fit_result
end

function cached_fit(spec::FacetSpec; experimental::Bool = false, kwargs...)
    return cached_fit(
        _fit_cache_design(spec, experimental);
        experimental,
        kwargs...,
    )
end

function _column_mean(xs::AbstractVector{<:Real})
    isempty(xs) && return NaN
    return sum(Float64, xs) / length(xs)
end

function _column_sd(xs::AbstractVector{<:Real}, mean::Float64)
    n = length(xs)
    n <= 1 && return NaN
    ss = 0.0
    for x in xs
        d = Float64(x) - mean
        ss += d * d
    end
    return sqrt(ss / (n - 1))
end

function _quantile_sorted(sorted::Vector{Float64}, p::Real)
    0 <= p <= 1 || throw(ArgumentError("quantile probabilities must be in [0, 1]"))
    n = length(sorted)
    n == 0 && return NaN
    n == 1 && return sorted[1]
    pos = 1 + (n - 1) * Float64(p)
    lo = floor(Int, pos)
    hi = ceil(Int, pos)
    lo == hi && return sorted[lo]
    w = pos - lo
    return (1 - w) * sorted[lo] + w * sorted[hi]
end

function _check_posterior_summary_bounds(lower::Real, upper::Real)
    0 <= lower < 0.5 || throw(ArgumentError("lower must be in [0, 0.5)"))
    0.5 < upper <= 1 || throw(ArgumentError("upper must be in (0.5, 1]"))
    return Float64(lower), Float64(upper)
end

function _posterior_interval_probabilities(intervals::Nothing)
    return Float64[]
end

function _posterior_interval_probabilities(intervals::Real)
    isfinite(intervals) && 0 < intervals < 1 ||
        throw(ArgumentError("interval probabilities must be finite and in (0, 1)"))
    return [Float64(intervals)]
end

function _posterior_interval_probabilities(intervals)
    probabilities = Float64[]
    for interval in intervals
        isfinite(interval) && 0 < interval < 1 ||
            throw(ArgumentError("interval probabilities must be finite and in (0, 1)"))
        push!(probabilities, Float64(interval))
    end
    return probabilities
end

function _posterior_interval_rows(sorted::Vector{Float64},
        probabilities::AbstractVector{Float64})
    rows = NamedTuple[]
    for probability in probabilities
        lower_probability = (1 - probability) / 2
        upper_probability = 1 - lower_probability
        lower = _quantile_sorted(sorted, lower_probability)
        upper = _quantile_sorted(sorted, upper_probability)
        push!(rows, (;
            probability,
            lower,
            upper,
            lower_probability,
            upper_probability,
            width = upper - lower,
        ))
    end
    return Tuple(rows)
end

function _posterior_direction_summary(values::AbstractVector{Float64},
        reference::Float64)
    n = length(values)
    positive = count(>(reference), values) / n
    negative = count(<(reference), values) / n
    equal = count(==(reference), values) / n
    direction = positive == negative ? :undetermined :
        (positive > negative ? :positive : :negative)
    return (;
        reference,
        probability_positive = positive,
        probability_negative = negative,
        probability_equal = equal,
        probability_of_direction = max(positive, negative),
        direction,
    )
end

function _posterior_rope_bounds(rope::Nothing)
    return nothing
end

function _posterior_rope_bounds(rope::Real)
    isfinite(rope) && rope >= 0 ||
        throw(ArgumentError("rope must be nothing, a finite non-negative radius, or a finite two-value interval"))
    radius = Float64(rope)
    return (-radius, radius)
end

function _posterior_rope_bounds(rope::Pair)
    return _posterior_rope_bounds((rope.first, rope.second))
end

function _posterior_rope_bounds(rope)
    length(rope) == 2 ||
        throw(ArgumentError("rope interval must contain exactly two values"))
    lower, upper = Float64(rope[1]), Float64(rope[2])
    isfinite(lower) && isfinite(upper) && lower <= upper ||
        throw(ArgumentError("rope interval must be finite with lower <= upper"))
    return (lower, upper)
end

function _posterior_rope_summary(values::AbstractVector{Float64},
        rope_bounds,
        rope_probability_threshold::Float64)
    rope_bounds === nothing && return (;
        rope_lower = nothing,
        rope_upper = nothing,
        probability_in_rope = nothing,
        probability_below_rope = nothing,
        probability_above_rope = nothing,
        practical_equivalence = :not_requested,
    )

    lower, upper = rope_bounds
    n = length(values)
    in_rope = count(value -> lower <= value <= upper, values) / n
    below_rope = count(<(lower), values) / n
    above_rope = count(>(upper), values) / n
    practical_equivalence =
        in_rope >= rope_probability_threshold ? :inside_rope :
        max(below_rope, above_rope) >= rope_probability_threshold ? :outside_rope :
        :mixed
    return (;
        rope_lower = lower,
        rope_upper = upper,
        probability_in_rope = in_rope,
        probability_below_rope = below_rope,
        probability_above_rope = above_rope,
        practical_equivalence,
    )
end

function _posterior_summary_rows(draws::AbstractMatrix{<:Real},
        parameter_names;
        lower::Real,
        upper::Real,
        intervals,
        reference::Real,
        rope,
        rope_probability_threshold::Real)
    lower_probability, upper_probability =
        _check_posterior_summary_bounds(lower, upper)
    interval_probabilities = _posterior_interval_probabilities(intervals)
    isfinite(reference) ||
        throw(ArgumentError("reference must be finite"))
    isfinite(rope_probability_threshold) && 0 < rope_probability_threshold <= 1 ||
        throw(ArgumentError("rope_probability_threshold must be finite and in (0, 1]"))
    reference_value = Float64(reference)
    rope_bounds = _posterior_rope_bounds(rope)
    checked_rope_probability_threshold = Float64(rope_probability_threshold)
    size(draws, 2) == length(parameter_names) ||
        throw(ArgumentError("parameter name count does not match draw columns"))
    rows = NamedTuple[]
    for j in axes(draws, 2)
        vals = Float64.(draws[:, j])
        sorted = sort(vals)
        # Preserve a point mass exactly when summation would round its mean.
        constant = !isempty(sorted) && first(sorted) == last(sorted)
        m = constant ? first(sorted) : _column_mean(vals)
        push!(rows, (;
            parameter = parameter_names[j],
            mean = m,
            sd = _column_sd(vals, m),
            median = _quantile_sorted(sorted, 0.5),
            lower = _quantile_sorted(sorted, lower_probability),
            upper = _quantile_sorted(sorted, upper_probability),
            lower_probability,
            upper_probability,
            intervals = _posterior_interval_rows(sorted, interval_probabilities),
            _posterior_direction_summary(vals, reference_value)...,
            _posterior_rope_summary(
                vals,
                rope_bounds,
                checked_rope_probability_threshold,
            )...,
            rope_probability_threshold =
                rope_bounds === nothing ? nothing : checked_rope_probability_threshold,
            n_draws = length(vals),
        ))
    end
    return rows
end

function _posterior_summary_row_schema(rows;
        family::Symbol,
        scope::Symbol,
        parameter_space::Symbol,
        summary_function::Symbol,
        parameter_names,
        blocks,
        layout)
    row_fields = isempty(rows) ? Symbol[] : collect(propertynames(first(rows)))
    return (;
        schema = "bayesianmgmfrm.posterior_summary_row_schema.v1",
        family,
        scope,
        parameter_space,
        summary_function,
        source_layout_schema = layout.schema,
        source_layout_scope = layout.scope,
        source_layout_status = layout.status,
        density_space = layout.density_space,
        parameterization = layout.parameterization,
        n_parameters = length(parameter_names),
        parameter_names = copy(parameter_names),
        blocks = copy(blocks),
        row_fields = Tuple(row_fields),
    )
end

"""
    posterior_summary(fit; lower = 0.025, upper = 0.975,
        intervals = (0.66, 0.9, 0.95), reference = 0.0,
        rope = nothing, rope_probability_threshold = 0.95)

Summarize posterior draws for each parameter. Rows retain the legacy
`lower`/`upper` interval columns and also include central credible intervals,
probability of direction relative to `reference`, and optional ROPE/practical
equivalence probabilities. Pass `rope = r` for a symmetric `[-r, r]` ROPE or
`rope = (lower, upper)` for an explicit interval.
`probability_equal` is the fraction of retained draws exactly equal to `reference`;
a zero count is not evidence against a point-null hypothesis.

For `GMFRMFit`, `MGMFRMFit`, `Experimental.NormalizedMGMFRMFit` and
`Experimental.CorrelatedMGMFRMFit`, use `scale=:model` for positive,
constraint-restored model parameters, or `scale=:raw` for computation coordinates.
Omitting `scale` preserves the historical raw-coordinate summary. The qualified
`direct_posterior_summary` remains available with its original meaning.

For these same result types, `estimand=:adjacent_logit_slope` summarizes
`D*c_r*a_id` from each joint draw (D=1 for scalar GMFRM; D=1.7 for MGMFRM).
It returns fitted item × rater × dimension rows, including structural Q zeros
and fixed slopes. These are conditional adjacent-category log-odds changes per
one ability unit, not cumulative-event odds, reliability or standardized effects.
Other ability components are held fixed. Matching units does not align constructs
or priors across models. This estimand rejects `scale=:raw`; `scale=:model` is
optional. Use the same `estimand` in `posterior_mcse` for simulation precision.
No samples are refitted, rescaled or reordered. Inspect whole-fit diagnostics.
The separate Correlated3D record/report API is outside this selector's scope.
"""
function posterior_summary(fit::MFRMFit;
        lower::Real = 0.025,
        upper::Real = 0.975,
        intervals = (0.66, 0.9, 0.95),
        reference::Real = 0.0,
        rope = nothing,
        rope_probability_threshold::Real = 0.95)
    return _posterior_summary_rows(
        fit.draws,
        fit.design.parameter_names;
        lower,
        upper,
        intervals,
        reference,
        rope,
        rope_probability_threshold,
    )
end

function posterior_summary(fit::GMFRMFit;
        scale=nothing, estimand::Symbol=:parameters,
        lower::Real = 0.025,
        upper::Real = 0.975,
        intervals = (0.66, 0.9, 0.95),
        reference::Real = 0.0,
        rope = nothing,
        rope_probability_threshold::Real = 0.95)
    selected = _generalized_summary_selection(scale, estimand)
    selected === :adjacent_logit_slope && return _generalized_slope_rows(fit;
        lower, upper, intervals, reference, rope, rope_probability_threshold)
    selected === :direct_constrained && return direct_posterior_summary(fit;
        lower, upper, intervals, reference, rope, rope_probability_threshold)
    return _posterior_summary_rows(
        fit.draws,
        fit.diagnostic_surface.raw_parameter_names;
        lower,
        upper,
        intervals,
        reference,
        rope,
        rope_probability_threshold,
    )
end

"""
    BayesianMGMFRM.direct_posterior_summary(fit; lower = 0.025, upper = 0.975,
        intervals = (0.66, 0.9, 0.95), reference = 0.0,
        rope = nothing, rope_probability_threshold = 0.95)

Summarize stored model-scale draws from a `GMFRMFit` or
`MGMFRMFit`. Call this qualified function for transformed parameters such as
positive item discrimination and rater consistency. `posterior_summary(fit)`
summarizes their raw computational coordinates instead.
The shared spelling `posterior_summary(fit; scale=:model)` returns the same rows.

Return a vector of named-tuple rows with parameter names, means, medians,
standard deviations, central credible intervals, probability of direction
relative to `reference`, and optional ROPE probabilities. `lower` and `upper` are quantile probabilities;
`intervals` contains central interval masses. Set `rope = r` for `[-r, r]` or
`rope = (lower, upper)` for explicit bounds.

Rows cover the stored direct coordinates. The fixed first and reconstructed
final category-step rows are additionally displayed by
`BayesianMGMFRM.plot_posterior(fit; scale = :model)`. This summary uses the
existing fit and preserves its scope and fitted prior.

```julia
rows = BayesianMGMFRM.direct_posterior_summary(fit_result)
```
"""
function direct_posterior_summary(fit::GMFRMFit;
        lower::Real = 0.025,
        upper::Real = 0.975,
        intervals = (0.66, 0.9, 0.95),
        reference::Real = 0.0,
        rope = nothing,
        rope_probability_threshold::Real = 0.95)
    return _posterior_summary_rows(
        fit.direct_draws,
        fit.diagnostic_surface.direct_parameter_names;
        lower,
        upper,
        intervals,
        reference,
        rope,
        rope_probability_threshold,
    )
end

function posterior_summary(fit::MGMFRMFit;
        scale=nothing, estimand::Symbol=:parameters,
        lower::Real = 0.025,
        upper::Real = 0.975,
        intervals = (0.66, 0.9, 0.95),
        reference::Real = 0.0,
        rope = nothing,
        rope_probability_threshold::Real = 0.95)
    selected = _generalized_summary_selection(scale, estimand)
    selected === :adjacent_logit_slope && return _generalized_slope_rows(fit;
        lower, upper, intervals, reference, rope, rope_probability_threshold)
    selected === :direct_constrained && return direct_posterior_summary(fit;
        lower, upper, intervals, reference, rope, rope_probability_threshold)
    return _posterior_summary_rows(
        fit.draws,
        fit.diagnostic_surface.raw_parameter_names;
        lower,
        upper,
        intervals,
        reference,
        rope,
        rope_probability_threshold,
    )
end

function direct_posterior_summary(fit::MGMFRMFit;
        lower::Real = 0.025,
        upper::Real = 0.975,
        intervals = (0.66, 0.9, 0.95),
        reference::Real = 0.0,
        rope = nothing,
        rope_probability_threshold::Real = 0.95)
    return _posterior_summary_rows(
        fit.direct_draws,
        fit.diagnostic_surface.direct_parameter_names;
        lower,
        upper,
        intervals,
        reference,
        rope,
        rope_probability_threshold,
    )
end

function _posterior_mcse_value(samples, kind)
    value = try
        # Match the diagnostic lag range; the dependency's 250-lag default can
        # truncate a still-positive autocorrelation sequence and understate MCSE.
        MCMCDiagnosticTools.mcse(samples; kind, split_chains = 2,
            maxlag = div(size(samples, 1), 2) - 4)
    catch err
        # The SD asymptotic variance can round below zero for balanced
        # two-point draws. Preserve unavailable precision instead of reporting
        # zero or discarding the separately estimable mean/quantile MCSE.
        kind === Statistics.std && err isa DomainError || rethrow()
        return missing
    end
    if ismissing(value)
        return missing
    end
    converted = Float64(value)
    return isfinite(converted) && converted >= 0 ? converted : missing
end

function _posterior_mcse_rows(draws::AbstractMatrix{<:Real},
        parameter_names,
        chains::Integer;
        probabilities = (0.025, 0.5, 0.975),
        parameter_space::Symbol,
        structurally_fixed_parameters = Set{String}())
    checked_chains = Int(chains)
    checked_chains >= 1 || throw(ArgumentError("chains must be positive"))
    names = String.(collect(parameter_names))
    size(draws, 2) == length(names) || throw(ArgumentError(
        "parameter name count does not match draw columns",
    ))
    checked_probabilities = _posterior_interval_probabilities(probabilities)
    values = _draw_matrix_to_chain_array(draws, checked_chains)
    draws_per_chain = size(values, 1)
    total_draws = size(draws, 1)
    rows = NamedTuple[]
    for parameter_index in axes(values, 3)
        parameter = names[parameter_index]
        samples = @view values[:, :, parameter_index]
        flat_samples = vec(samples)
        sorted = sort(Float64.(flat_samples))
        structurally_fixed = parameter in structurally_fixed_parameters
        finite_draws = all(isfinite, flat_samples)
        degenerate_draws = finite_draws && allequal(flat_samples)
        status = !finite_draws ? :nonfinite_draws :
            structurally_fixed && degenerate_draws ? :structurally_fixed :
            structurally_fixed ? :fixed_parameter_varied :
            checked_chains < 2 ? :insufficient_chains :
            draws_per_chain < 10 ? :insufficient_draws :
            degenerate_draws ? :degenerate_draws : :available
        mean_mcse = status === :structurally_fixed ? 0.0 :
            status === :available ?
                _posterior_mcse_value(samples, Statistics.mean) : missing
        sd_mcse = status === :structurally_fixed ? 0.0 :
            status === :available ?
                _posterior_mcse_value(samples, Statistics.std) : missing
        quantile_rows = Tuple((;
            probability,
            estimate = _quantile_sorted(sorted, probability),
            mcse = status === :structurally_fixed ? 0.0 :
                status === :available ? _posterior_mcse_value(
                    samples,
                    Base.Fix2(Statistics.quantile, probability),
                ) : missing,
        ) for probability in checked_probabilities)
        all_mcse_available = !ismissing(mean_mcse) && !ismissing(sd_mcse) &&
            all(row -> !ismissing(row.mcse), quantile_rows)
        mcse_status = status === :available && !all_mcse_available ?
            :mcse_unavailable : status
        push!(rows, (;
            parameter,
            parameter_space,
            mean_mcse,
            sd_mcse,
            quantiles = quantile_rows,
            n_chains = checked_chains,
            draws_per_chain,
            total_draws,
            mcse_status,
            mcse_method =
                :mcmcdiagnostictools_ess_asymptotic_variance,
            split_chains = 2,
            minimum_draws_per_chain = 10,
            convergence_review_required =
                mcse_status !== :structurally_fixed,
            precision_threshold_applied = false,
            precision_decision = :not_applied,
        ))
    end
    return rows
end

function _posterior_mcse_generalized_input(
        fit::Union{GMFRMFit,MGMFRMFit},
        parameter_space::Symbol)
    selected = parameter_space === :auto ?
        :direct_constrained : parameter_space
    if selected === :raw_unconstrained
        return (;
            draws = fit.draws,
            parameter_names = fit.diagnostic_surface.raw_parameter_names,
            parameter_space = selected,
            structurally_fixed_parameters = Set{String}(),
        )
    elseif selected === :direct_constrained
        fixed = Set(String(row.parameter)
            for row in fit.diagnostic_surface.direct_parameter_rows
            if hasproperty(row, :quality_gate_applicable) &&
                !row.quality_gate_applicable)
        return (;
            draws = fit.direct_draws,
            parameter_names = fit.diagnostic_surface.direct_parameter_names,
            parameter_space = selected,
            structurally_fixed_parameters = fixed,
        )
    end
    throw(ArgumentError(
        "generalized posterior_mcse parameter_space must be :auto, " *
        ":raw_unconstrained, or :direct_constrained",
    ))
end

"""
    posterior_mcse(fit; probabilities = (0.025, 0.5, 0.975),
                   parameter_space = :auto)
    posterior_mcse(draws; chains, parameter_names,
                   probabilities = (0.025, 0.5, 0.975),
                   parameter_space = :user_defined_estimand)

Estimate Monte Carlo standard errors for posterior means, standard deviations,
and requested quantiles. Fit-based calls use identified parameters for scalar MFRM
fits and direct constrained parameters for generalized and fixed-coefficient
multidimensional MFRM fits by default; pass
`parameter_space = :raw_unconstrained` to inspect generalized sampling
coordinates or multidimensional MFRM free coordinates.

For fixed-coefficient multidimensional MFRM (independent or correlated, with
either rater prior), the default reconstructs the last rater and item steps,
retains fixed coefficients, and reports rho rather than Fisher z. Direct rows
include block, dimension label, fixed/derived status and their actual
`parameter_space`: `:unit_logit`, `:dimensionless` or `:correlation`.
Free-coordinate rows use `:unit_logit` and, for correlated fits, `:fisher_z`.
These labels describe units, not likelihood identification. Saved records and
chain/iteration ordering are validated before computing MCSE.

The matrix method supports derived estimands: arrange rows in contiguous chain
blocks, transform each draw to the quantities of interest, and supply one name
per column. MCSE measures simulation precision only. Every non-fixed row keeps
`convergence_review_required = true`, and no universal precision threshold or
scientific decision is applied. Calls with fewer than two chains or fewer than
10 retained draws per chain return typed unavailable rows instead of presenting
short-chain MCSE as usable evidence.
Numerically undefined standard-deviation MCSE is reported as `missing` with
`:mcse_unavailable`; separately available mean and quantile MCSE are retained.
Autocorrelation estimation considers all available split-chain lags, using the
initial-positive/monotone-sequence stopping rule rather than a fixed 250-lag cap.
MCSE remains a precision estimate conditional on adequate sampling; it does not
make a nonconverged chain valid.

For scalar/fixed-Q GMFRM/MGMFRM and normalized/correlated-2D MGMFRM results,
`estimand=:adjacent_logit_slope` computes the same joint-draw quantities as
`posterior_summary(fit; estimand=:adjacent_logit_slope)`. Use the default
`parameter_space=:auto` or `:adjacent_logit_slope`. This retains stored chain
order and estimates mean, SD and requested endpoint MCSE separately; constant
estimated traces are not declared structurally fixed. Correlated3D is separate.
"""
function posterior_mcse(fit::MFRMFit;
        probabilities = (0.025, 0.5, 0.975),
        parameter_space::Symbol = :auto)
    selected = parameter_space === :auto ? :identified : parameter_space
    selected === :identified || throw(ArgumentError(
        "MFRM posterior_mcse parameter_space must be :auto or :identified",
    ))
    return _posterior_mcse_rows(
        fit.draws,
        fit.design.parameter_names,
        length(fit.chain_acceptance_rate);
        probabilities,
        parameter_space = selected,
    )
end

function posterior_mcse(fit::Union{GMFRMFit,MGMFRMFit};
        probabilities = (0.025, 0.5, 0.975),
        estimand::Symbol = :parameters,
        parameter_space::Symbol = :auto)
    selected = _generalized_summary_selection(nothing, estimand; parameter_space)
    selected === :adjacent_logit_slope && return _generalized_slope_rows(fit; operation=:mcse, probabilities)
    input = _posterior_mcse_generalized_input(fit, parameter_space)
    return _posterior_mcse_rows(
        input.draws,
        input.parameter_names,
        length(fit.chain_acceptance_rate);
        probabilities,
        parameter_space = input.parameter_space,
        structurally_fixed_parameters =
            input.structurally_fixed_parameters,
    )
end

function posterior_mcse(draws::AbstractMatrix{<:Real};
        chains::Integer,
        parameter_names = ["estimand_$index" for index in axes(draws, 2)],
        probabilities = (0.025, 0.5, 0.975),
        parameter_space::Symbol = :user_defined_estimand)
    return _posterior_mcse_rows(
        draws,
        parameter_names,
        chains;
        probabilities,
        parameter_space,
    )
end
