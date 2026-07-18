#!/usr/bin/env julia

module PublicLanguageGate

export DEVELOPER_DOCUMENTATION_PAGES,
    PUBLIC_DOCUMENTATION_PAGES,
    assert_public_language,
    assert_rendered_public_language,
    assert_runtime_public_language,
    assert_runtime_public_report_language,
    check_public_language,
    check_rendered_public_language,
    navigation_violations,
    public_language_violations,
    public_surface_paths,
    release_workflow_violations,
    rendered_language_violations,
    rendered_public_surface_paths,
    runtime_language_violations,
    runtime_public_report_language_violations

const PUBLIC_DOCUMENTATION_PAGES = (
    "index.md",
    "data-validation.md",
    "model-equations.md",
    "bayesian-workflow.md",
    "fitting.md",
    "examples.md",
    "scope.md",
    "api.md",
    "api-data-design.md",
    "api-fitting-artifacts.md",
    "api-workflow-diagnostics.md",
    "api-validation-evidence.md",
)

const DEVELOPER_DOCUMENTATION_PAGES = (
    "development-changelog.md",
    "development-fitting-notes.md",
    "development-home-ledger.md",
    "development-readme-ledger.md",
    "development-workflow-notes.md",
    "roadmap.md",
    "registration.md",
    "mgmfrm-research-roadmap.md",
    "v0.1.1-implementation-checklist.md",
)

const PUBLIC_ROOT_FILES = (
    "README.md",
    "NEWS.md",
)

const ABSOLUTE_LOCAL_PATH_PATTERN =
    r"(?:file://|(?<![A-Za-z0-9:/])/(?:Users|home|tmp|private/(?:tmp|var/folders)|var/(?:folders|tmp)|workspace|workspaces|Volumes|mnt)(?:/|\b)|(?<![A-Za-z0-9])[A-Za-z]:[\\/]+|\\\\[^\\/\s]+[\\/]+[^\\/\s]+)"

const PRIVATE_IDENTIFIER_PATTERN =
    r"(?<![\p{L}\p{N}_])_+[\p{L}][\p{L}\p{N}_!]*"

const MAINTENANCE_TOKEN_PATTERN =
    r"(?i)\b(?:source[\s_-]?fixture[A-Za-z0-9_]*|fixture[\s_-]?only|fixture[\s_-]?provenance|promotion[\s_-]?candidate|guarded[\s_-]?local[\s_-]?entrypoint|guarded[\s_-]?local[\s_-]?fit|experimental_public|next[\s_-]?gate|blocked[\s_-]?option|supported[\s_-]?surface|candidate[\s_-]?gates|caveat[\s_-]?docs[\s_-]?artifact|internal[\s_-]?target[\s_-]?constructor|internal[\s_-]?sampler[\s_-]?diagnostic[\s_-]?constructor|publication[\s_-]?or[\s_-]?registration[\s_-]?action|manual[\s_-]?publication[\s_-]?or[\s_-]?registration[\s_-]?by[\s_-]?user[\s_-]?only|manuscript[\s_-]?claims[\s_-]?allowed|public[\s_-]?claim[\s_-]?allowed|package[\s_-]?default[\s_-]?change)\b"

const LANGUAGE_RULES = (
    (;
        id = :absolute_local_path,
        pattern = ABSOLUTE_LOCAL_PATH_PATTERN,
        guidance = "replace machine-specific paths with repository-relative links",
    ),
    (;
        id = :private_identifier,
        pattern = PRIVATE_IDENTIFIER_PATTERN,
        guidance = "replace private implementation identifiers with a public concept",
    ),
    (;
        id = :developer_artifact_path,
        pattern = r"(?:test/fixtures/|scripts/generate_|artifacts/(?:uto_style|publication_grade))[^\s<]*",
        guidance = "describe the public evidence or workflow without its developer path",
    ),
    (;
        id = :internal_status_token,
        pattern = MAINTENANCE_TOKEN_PATTERN,
        guidance = "use a reader-facing status label and keep the machine token in developer artifacts",
    ),
    (;
        id = :maintainer_process_wording,
        pattern = r"(?i)\b(?:development[\s_-]+ledgers?|registry[\s_-]+maintenance|release[\s_-]+control|worktree[\s_-]+checking|release[\s_-]+handoff|CI[\s_-]+rendering)\b",
        guidance = "describe the user-visible result and keep release-process wording in maintainer documentation",
    ),
    (;
        id = :stale_registration_state,
        pattern = r"(?i)\b(?:until\s+the\s+package\s+is\s+registered\s+in\s+julia\s+general|after\s+general\s+registration)\b",
        guidance = "describe the package's current registered installation path",
    ),
    (;
        id = :pre_registration_wording,
        pattern = r"(?i)\bpre[\s-]+registration\b",
        guidance = "use release verification or registry-update wording",
    ),
    (;
        id = :promotion_candidate_wording,
        pattern = r"(?i)\bpromotion[\s-]+candidate\b",
        guidance = "use experimental candidate or private validation candidate",
    ),
    (;
        id = :manual_public_scope_wording,
        pattern = r"(?i)\bmanual\s+public[\s-]+scope\b",
        guidance = "use independent scope review",
    ),
    (;
        id = :local_only_wording,
        pattern = r"(?i)\b(?:manual[\s-]+)?local[\s-]+only\b",
        guidance = "state the actual experimental or non-public scope",
    ),
    (;
        id = :maintainer_workflow_wording,
        pattern = r"(?i)(?:\brelease_gate_check\b|\brelease_scope_summary\b|\bcase_study_provenance_manifest\b|\bevidence_artifact_schema_policy\b|\bGeneral\s+AutoMerge\b|\bRegistrator\b|@JuliaRegistrator|\bregistration\s+handoff\b|\bfixture[\s-]+SHA\b|--read-local-artifacts|\bmethod[\s-]+wiring\b|\blocal\s+runner\b|\bimplementation\s+checklist\b|\bexecution\s+prompt\s+pack\b|\bcurrent\s+branch\s+status\b)",
        guidance = "keep registry, evidence-ledger, and implementation workflow wording in maintainer documentation",
    ),
)

const SOURCE_ONLY_RULES = (
    (;
        id = :internal_audience_wording,
        pattern = r"(?i)\binternal(?![\s_-]+consistency\b)(?:[\s-]+only)?\b",
        guidance = "describe the user-visible behavior and keep maintainer context outside public files",
    ),
)

const RUNTIME_ONLY_RULES = (
    (;
        id = :runtime_internal_wording,
        pattern = r"(?i)\binternal(?![\s_-]+consistency\b)(?:[\s_-]+[A-Za-z0-9_-]+)*\b",
        guidance = "replace maintainer-facing wording with a reader-facing description",
    ),
    (;
        id = :runtime_maintenance_field,
        pattern = MAINTENANCE_TOKEN_PATTERN,
        guidance = "remove release-control and repository-maintenance fields from public output",
    ),
    (;
        id = :runtime_repository_path,
        pattern = r"(?:test/fixtures/|scripts/generate_|artifacts/publication_grade)[^\s\"<]*",
        guidance = "omit repository-maintenance paths from public output",
    ),
    (;
        id = :runtime_absolute_path,
        pattern = ABSOLUTE_LOCAL_PATH_PATTERN,
        guidance = "omit machine-specific paths from public output",
    ),
)

const RUNTIME_PUBLIC_REPORT_USER_VALUE_FIELDS = Set((
    :category,
    :category_levels,
    :cell,
    :column_levels,
    :contrast,
    :dimension_label,
    :dimension_labels,
    :direct_parameter_names,
    :facet,
    :focal_level,
    :group,
    :item,
    :label,
    :level,
    :model,
    :models,
    :optional_facets,
    :parameter,
    :parameter_name,
    :parameter_names,
    :person,
    :rater,
    :reference_level,
    :row_levels,
    :step_path,
    :term,
    :threshold_path,
))

function _runtime_public_report_user_value_field(field::Symbol)
    field in RUNTIME_PUBLIC_REPORT_USER_VALUE_FIELDS && return true
    name = lowercase(String(field))
    return endswith(name, "_label") || endswith(name, "_labels") ||
        endswith(name, "_level") || endswith(name, "_levels")
end

const RENDERED_ONLY_RULES = (
    (;
        id = :rendered_private_identifier,
        pattern = r"<code[^>]*>_[A-Za-z][A-Za-z0-9_!]*</code>",
        guidance = "replace private implementation identifiers in public docstrings",
    ),
    (;
        id = :rendered_developer_artifact_path,
        pattern = r"(?:test/fixtures/|scripts/generate_)[^<\" ]*",
        guidance = "remove repository-maintenance paths from rendered documentation",
    ),
    (;
        id = :rendered_developer_page,
        pattern = r"(?:Registration Handoff|MGMFRM Research Roadmap|v0\.1\.1 Implementation Checklist)",
        guidance = "exclude maintainer pages from the Documenter build",
    ),
)

function _line_number_at(text::AbstractString, offset::Int)
    offset == firstindex(text) && return 1
    prefix = SubString(text, firstindex(text), prevind(text, offset))
    return count(==('\n'), prefix) + 1
end

function _line_at(text::AbstractString, offset::Int)
    preceding_newline = findprev(==('\n'), text, offset)
    following_newline = findnext(==('\n'), text, offset)
    start = preceding_newline === nothing ? firstindex(text) :
        nextind(text, preceding_newline)
    stop = following_newline === nothing ? lastindex(text) :
        prevind(text, following_newline)
    stop < start && return ""
    return String(SubString(text, start, stop))
end

function _markdown_italic_placeholder(text::AbstractString, offset::Int)
    line = strip(_line_at(text, offset))
    return occursin(r"^_[^_\n]+_$", line) ||
        occursin(r"^__[^\n]+__$", line)
end

function _language_rule_hits(text::AbstractString, rules)
    hits = NamedTuple[]
    seen = Set{Tuple{Symbol,Int}}()
    for rule in rules
        for matched in eachmatch(rule.pattern, text)
            if rule.id in (
                    :private_identifier,
                    :runtime_private_identifier,
                    :rendered_private_identifier) &&
                    _markdown_italic_placeholder(text, matched.offset)
                continue
            end
            line = _line_number_at(text, matched.offset)
            key = (rule.id, line)
            key in seen && continue
            push!(seen, key)
            excerpt = replace(strip(String(matched.match)), r"\s+" => " ")
            isempty(excerpt) && (excerpt = strip(_line_at(text, matched.offset)))
            length(excerpt) > 160 &&
                (excerpt = string(first(excerpt, 157), "..."))
            push!(hits, (;
                rule = rule.id,
                line,
                excerpt,
                guidance = rule.guidance,
            ))
        end
    end
    return hits
end

function public_surface_paths(root::AbstractString)
    normalized_root = abspath(normpath(root))
    paths = String[]
    append!(paths, joinpath.(Ref(normalized_root), PUBLIC_ROOT_FILES))
    examples_root = joinpath(normalized_root, "examples")
    isdir(examples_root) || error("public examples directory does not exist")
    example_paths = String[]
    for (directory, _, files) in walkdir(examples_root), file in sort(files)
        splitext(file)[2] == ".jl" || continue
        push!(example_paths, joinpath(directory, file))
    end
    sort!(example_paths)
    isempty(example_paths) && error("public examples directory contains no Julia examples")
    append!(paths, example_paths)
    append!(paths, [joinpath(normalized_root, "docs", "src", page)
                    for page in PUBLIC_DOCUMENTATION_PAGES])
    missing = filter(!isfile, paths)
    isempty(missing) || error(
        "public language policy references missing file(s): " *
        join(relpath.(missing, Ref(normalized_root)), ", "))
    return paths
end

function rendered_public_surface_paths(root::AbstractString)
    normalized_root = abspath(normpath(root))
    build_root = joinpath(normalized_root, "docs", "build")
    isdir(build_root) || error(
        "rendered documentation does not exist at $(relpath(build_root, normalized_root)); build docs first")
    paths = [page == "index.md" ?
        joinpath(build_root, "index.html") :
        joinpath(build_root, splitext(page)[1], "index.html")
        for page in PUBLIC_DOCUMENTATION_PAGES]
    missing = filter(!isfile, paths)
    isempty(missing) || error(
        "rendered public documentation is missing file(s): " *
        join(relpath.(missing, Ref(normalized_root)), ", "))
    return paths
end

function public_language_violations(root::AbstractString;
        paths::AbstractVector{<:AbstractString} = public_surface_paths(root))
    normalized_root = abspath(normpath(root))
    violations = NamedTuple[]
    for path in sort!(abspath.(normpath.(String.(paths))))
        isfile(path) || error("public language input does not exist: $path")
        text = read(path, String)
        for hit in _language_rule_hits(text,
                (LANGUAGE_RULES..., SOURCE_ONLY_RULES...))
            push!(violations, (;
                rule = hit.rule,
                path = relpath(path, normalized_root),
                line = hit.line,
                excerpt = hit.excerpt,
                guidance = hit.guidance,
            ))
        end
    end
    return violations
end

function runtime_language_violations(outputs)
    violations = NamedTuple[]
    for output in outputs
        output isa Pair ||
            throw(ArgumentError("runtime public-language inputs must be label => text pairs"))
        surface = String(first(output))
        text = String(last(output))
        for hit in _language_rule_hits(text,
                (LANGUAGE_RULES..., RUNTIME_ONLY_RULES...))
            push!(violations, (;
                rule = hit.rule,
                surface,
                path = surface,
                line = hit.line,
                excerpt = hit.excerpt,
                guidance = hit.guidance,
            ))
        end
    end
    return violations
end

_runtime_public_report_user_scalar(value) =
    value === missing || value === nothing || value isa Symbol ||
    value isa AbstractString || value isa Bool || value isa Number

function _runtime_public_report_language_violations!(violations,
        surface::String,
        value,
        path::Tuple = ();
        preserve_user_text::Bool = false)
    if value isa NamedTuple
        for field in keys(value)
            child_surface = string(surface, ":", join((path..., field), "."))
            append!(violations, runtime_language_violations([
                child_surface * ":field" => String(field),
            ]))
            _runtime_public_report_language_violations!(violations,
                surface,
                getproperty(value, field),
                (path..., field);
                preserve_user_text =
                    _runtime_public_report_user_value_field(field))
        end
    elseif value isa AbstractDict
        for (key, item) in value
            field = key isa Symbol ? key : Symbol(string(key))
            child_surface = string(surface, ":", join((path..., field), "."))
            append!(violations, runtime_language_violations([
                child_surface * ":field" => String(field),
            ]))
            _runtime_public_report_language_violations!(violations,
                surface,
                item,
                (path..., field);
                preserve_user_text =
                    _runtime_public_report_user_value_field(field))
        end
    elseif value isa Tuple || value isa AbstractArray
        for item in value
            _runtime_public_report_language_violations!(violations,
                surface, item, path;
                preserve_user_text = preserve_user_text &&
                    _runtime_public_report_user_scalar(item))
        end
    elseif (value isa Symbol || value isa AbstractString) && !preserve_user_text
        child_surface = isempty(path) ? surface :
            string(surface, ":", join(path, "."))
        append!(violations, runtime_language_violations([
            child_surface => String(value),
        ]))
    end
    return violations
end

function runtime_public_report_language_violations(outputs)
    violations = NamedTuple[]
    for output in outputs
        output isa Pair || throw(ArgumentError(
            "runtime public-report inputs must be label => report pairs"))
        report = last(output)
        (report isa NamedTuple || report isa AbstractDict) ||
            throw(ArgumentError(
                "runtime public-report inputs must contain structured reports"))
        _runtime_public_report_language_violations!(violations,
            String(first(output)), report)
    end
    return violations
end

_mask_rendered_fragment(fragment::AbstractString) =
    replace(String(fragment), r"[^\r\n]" => " ")

function _rendered_visible_text(text::AbstractString)
    masked = replace(String(text),
        r"(?is)<!--.*?-->" => _mask_rendered_fragment,
        r"(?is)<(?:script|style|template)\b[^>]*>.*?</(?:script|style|template)\s*>" =>
            _mask_rendered_fragment)
    return replace(masked,
        r"(?s)<[^>]*>" => _mask_rendered_fragment)
end

function rendered_language_violations(root::AbstractString;
        paths::AbstractVector{<:AbstractString} = rendered_public_surface_paths(root))
    normalized_root = abspath(normpath(root))
    violations = NamedTuple[]
    for path in sort!(abspath.(normpath.(String.(paths))))
        isfile(path) || error("rendered public language input does not exist: $path")
        text = read(path, String)
        visible_text = _rendered_visible_text(text)
        hits = (_language_rule_hits(visible_text,
                    (LANGUAGE_RULES..., RENDERED_ONLY_RULES[2:end]...))...,
            _language_rule_hits(text, (RENDERED_ONLY_RULES[1],))...)
        for hit in hits
            push!(violations, (;
                rule = hit.rule,
                path = relpath(path, normalized_root),
                line = hit.line,
                excerpt = "rendered HTML contains a restricted public-language pattern",
                guidance = hit.guidance,
            ))
        end
    end
    return violations
end

function _published_documentation_pages(make_text::AbstractString)
    return Set(match.captures[1]
        for match in eachmatch(r"=>\s*\"([^\"]+\.md)\"", make_text))
end

function navigation_violations(root::AbstractString)
    normalized_root = abspath(normpath(root))
    make_path = joinpath(normalized_root, "docs", "make.jl")
    isfile(make_path) || error("Documenter entrypoint does not exist: $make_path")
    make_text = read(make_path, String)
    published = _published_documentation_pages(make_text)
    declared = Set(PUBLIC_DOCUMENTATION_PAGES)
    violations = NamedTuple[]
    if !occursin(r"\bpagesonly\s*=\s*true\b", make_text)
        push!(violations, (;
            rule = :documenter_builds_unlisted_pages,
            path = relpath(make_path, normalized_root),
            line = 0,
            excerpt = "pagesonly = true is missing",
            guidance = "set pagesonly = true so repository-only Markdown is not rendered",
        ))
    end
    if !occursin(r"\bcheckdocs\s*=\s*:exports\b", make_text)
        push!(violations, (;
            rule = :documenter_checkdocs_scope,
            path = relpath(make_path, normalized_root),
            line = 0,
            excerpt = "checkdocs = :exports is missing",
            guidance = "check every exported public docstring while allowing repository-only helpers",
        ))
    end
    for page in sort!(collect(setdiff(published, declared)))
        push!(violations, (;
            rule = page in DEVELOPER_DOCUMENTATION_PAGES ?
                :developer_page_published : :unscanned_public_page,
            path = relpath(make_path, normalized_root),
            line = 0,
            excerpt = page,
            guidance = page in DEVELOPER_DOCUMENTATION_PAGES ?
                "keep developer guidance in the repository but outside public Documenter navigation" :
                "add the new public page to PUBLIC_DOCUMENTATION_PAGES",
        ))
    end
    for page in sort!(collect(setdiff(declared, published)))
        push!(violations, (;
            rule = :declared_page_not_published,
            path = relpath(make_path, normalized_root),
            line = 0,
            excerpt = page,
            guidance = "publish the declared public page or remove it from the policy",
        ))
    end
    return violations
end

function _workflow_run_blocks(workflow_text::AbstractString)
    lines = split(String(workflow_text), '\n'; keepempty = true)
    blocks = String[]
    index = 1
    while index <= length(lines)
        line = lines[index]
        matched = match(r"^(\s*)run:\s*(.*)$", line)
        if matched === nothing
            index += 1
            continue
        end
        base_indent = length(matched.captures[1])
        tail = strip(matched.captures[2])
        if startswith(tail, "|") || startswith(tail, ">")
            command_lines = String[]
            index += 1
            while index <= length(lines)
                child = lines[index]
                stripped = strip(child)
                child_indent = length(child) - length(lstrip(child))
                if !isempty(stripped) && child_indent <= base_indent
                    break
                end
                if !isempty(stripped) && !startswith(stripped, "#")
                    push!(command_lines, stripped)
                end
                index += 1
            end
            push!(blocks, join(command_lines, "\n"))
            continue
        end
        !isempty(tail) && !startswith(tail, "#") && push!(blocks, tail)
        index += 1
    end
    return blocks
end

function release_workflow_violations(root::AbstractString)
    normalized_root = abspath(normpath(root))
    workflow_path = joinpath(normalized_root, ".github", "workflows", "CI.yml")
    isfile(workflow_path) || error("CI workflow does not exist: $workflow_path")
    workflow_text = read(workflow_path, String)
    release_gate_path = joinpath(normalized_root, "scripts",
        "pre_registration_gate.jl")
    isfile(release_gate_path) ||
        error("release-verification gate does not exist: $release_gate_path")
    release_gate_text = read(release_gate_path, String)
    release_gate_code = join((line for line in
        split(release_gate_text, '\n'; keepempty = true)
        if !startswith(strip(line), "#")), "\n")
    workflow_run_text = join(_workflow_run_blocks(workflow_text), "\n")
    violations = NamedTuple[]
    if occursin(r"(?m)^[^#\n]*--skip-public-(?:language|wording)",
            workflow_run_text)
        push!(violations, (;
            rule = :ci_skips_public_language,
            path = relpath(workflow_path, normalized_root),
            line = 0,
            excerpt = "an active CI run block skips the public-language gate",
            guidance = "run the source-level public-language gate in CI without a skip flag",
        ))
    end
    active_release_gate = occursin(
        r"(?m)^\s*julia(?:\s|$)[^#\n]*\bscripts/pre_registration_gate\.jl\b",
        workflow_run_text)
    if !active_release_gate
        push!(violations, (;
            rule = :ci_missing_release_verification_gate,
            path = relpath(workflow_path, normalized_root),
            line = 0,
            excerpt = "no active CI run command invokes scripts/pre_registration_gate.jl",
            guidance = "invoke the release-verification script from an active CI run block",
        ))
    end
    if !occursin(
            r"(?m)^\s*julia(?:\s|$)[^#\n]*\bscripts/public_language_gate\.jl\b[^#\n]*--rendered",
            workflow_run_text)
        push!(violations, (;
            rule = :ci_missing_rendered_language_gate,
            path = relpath(workflow_path, normalized_root),
            line = 0,
            excerpt = "rendered public-language command is missing",
            guidance = "scan rendered Documenter HTML after the documentation build",
        ))
    end
    runtime_function_present = occursin(
        r"function\s+runtime_public_language_check\s*\(\)[\s\S]*?runtime_public_language_gate\.jl[\s\S]*?\bend\b",
        release_gate_code)
    runtime_step_present = occursin(
        r"step\(\"Runtime public language gate\",\s*runtime_public_language_check\)",
        release_gate_code)
    if !(runtime_function_present && runtime_step_present)
        push!(violations, (;
            rule = :release_gate_missing_runtime_language_gate,
            path = relpath(release_gate_path, normalized_root),
            line = 0,
            excerpt = "runtime public-language command is missing",
            guidance = "run the deterministic runtime public-language gate during release verification",
        ))
    end
    example_capture_present =
        occursin(r"function\s+run_public_examples\s*\(\)", release_gate_code) &&
        occursin("capture_cmd(", release_gate_code) &&
        occursin("_preserve_captured_example_output", release_gate_code) &&
        occursin("captured.stderr", release_gate_code) &&
        occursin("captured.passed", release_gate_code) &&
        occursin("runtime_language_violations(outputs)", release_gate_code)
    example_step_present = occursin(
        r"step\(\"Public examples\",\s*run_public_examples\)",
        release_gate_code)
    if !(example_capture_present && example_step_present)
        push!(violations, (;
            rule = :release_gate_missing_example_runtime_scan,
            path = relpath(release_gate_path, normalized_root),
            line = 0,
            excerpt = "captured public-example output scanning is missing",
            guidance = "capture every public example's stdout/stderr and scan it before release",
        ))
    end
    return violations
end

function check_public_language(root::AbstractString)
    language = public_language_violations(root)
    navigation = navigation_violations(root)
    workflow = release_workflow_violations(root)
    violations = (language..., navigation..., workflow...)
    return (;
        schema = "bayesianmgmfrm.public_language_gate.v1",
        passed = isempty(violations),
        n_public_files = length(public_surface_paths(root)),
        n_language_violations = length(language),
        n_navigation_violations = length(navigation),
        n_workflow_violations = length(workflow),
        violations,
    )
end

function check_rendered_public_language(root::AbstractString)
    normalized_root = abspath(normpath(root))
    build_root = joinpath(normalized_root, "docs", "build")
    expected_paths = rendered_public_surface_paths(normalized_root)
    expected = Set(abspath.(expected_paths))
    actual = Set{String}()
    for (directory, _, files) in walkdir(build_root)
        "index.html" in files || continue
        push!(actual, abspath(joinpath(directory, "index.html")))
    end
    violations = rendered_language_violations(normalized_root; paths = expected_paths)
    for path in sort!(collect(setdiff(actual, expected)))
        push!(violations, (;
            rule = :unlisted_page_rendered,
            path = relpath(path, normalized_root),
            line = 0,
            excerpt = "Documenter rendered a page outside the declared public navigation",
            guidance = "keep pagesonly = true and publish only declared public pages",
        ))
    end
    return (;
        schema = "bayesianmgmfrm.rendered_public_language_gate.v1",
        passed = isempty(violations),
        n_rendered_public_files = length(expected_paths),
        n_rendered_violations = length(violations),
        violations,
    )
end

function _format_violation(violation)
    location = violation.line > 0 ?
        "$(violation.path):$(violation.line)" : violation.path
    return "[$(violation.rule)] $location: $(violation.excerpt)\n" *
        "  guidance: $(violation.guidance)"
end

function assert_public_language(root::AbstractString)
    result = check_public_language(root)
    result.passed || error(
        "public language gate found $(length(result.violations)) violation(s):\n" *
        join(_format_violation.(result.violations), "\n"))
    return result
end

function assert_rendered_public_language(root::AbstractString)
    result = check_rendered_public_language(root)
    result.passed || error(
        "rendered public language gate found $(length(result.violations)) violation(s):\n" *
        join(_format_violation.(result.violations), "\n"))
    return result
end

function assert_runtime_public_language(outputs)
    violations = runtime_language_violations(outputs)
    isempty(violations) || error(
        "runtime public language gate found $(length(violations)) violation(s):\n" *
        join(_format_violation.(violations), "\n"))
    return (;
        schema = "bayesianmgmfrm.runtime_public_language_gate.v1",
        passed = true,
        n_surfaces = length(outputs),
        n_violations = 0,
        violations,
    )
end

function assert_runtime_public_report_language(outputs)
    violations = runtime_public_report_language_violations(outputs)
    isempty(violations) || error(
        "runtime public-report language gate found $(length(violations)) violation(s):\n" *
        join(_format_violation.(violations), "\n"))
    return (;
        schema = "bayesianmgmfrm.runtime_public_report_language_gate.v1",
        passed = true,
        n_surfaces = length(outputs),
        n_violations = 0,
        violations,
    )
end

function main()
    root = abspath(normpath(joinpath(@__DIR__, "..")))
    result = assert_public_language(root)
    println("Public language gate passed for $(result.n_public_files) files.")
    if "--rendered" in ARGS
        rendered = assert_rendered_public_language(root)
        println("Rendered public language gate passed for " *
            "$(rendered.n_rendered_public_files) HTML files.")
    end
    return nothing
end

end

if abspath(PROGRAM_FILE) == @__FILE__
    PublicLanguageGate.main()
end
