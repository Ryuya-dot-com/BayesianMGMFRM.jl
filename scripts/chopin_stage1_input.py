"""Import the pinned 2025 Chopin stage-1 table; no downloading or model fitting.

Requires Poppler's pdftotext. This is a source-specific adapter: a revised PDF
requires a new review, not bypassing the digest or silently guessing its layout.
"""
import argparse
from collections import Counter
from fractions import Fraction
import hashlib
import json
from pathlib import Path
import re
import subprocess

SCORES_SHA256 = "a3dcd4b8986e194148acba37590e5cf985986769db063e8ba6ea2a9708a1ad41"
RULES_SHA256 = "f902d833294308a41af05cee85b388cca3f5126901f4e44dd8e93e5553bb6e0e"
SOURCE_URLS = {
    "scores": "https://storage.nifc.pl/web_files/_plik/file_manager_pmp/files/475810_Chopin_Competition_2025_scores.pdf",
    "rules": "https://storage.nifc.pl/web_files/_plik/file_manager/files/813353_Rules_Jury_last_02.10.ENG.pdf",
}
# Exact printed labels in left-to-right order, including the abbreviation.
JUDGES = (
    "Garrick Ohlsson", "John Allison", "Yulianna Avdeeva", "Michel Beroff",
    "Sa Chen", "Dang Thai Son", "Akiko Ebi", "Nelson Goerner",
    "Krzysztof Jabłoński", "Kevin Kenner", "Momo Kodama", "Robert McDonald",
    "Piotr Paleczny", "Ewa Pobłocka", "K. Popowa-Zydroń", "John Rink",
    "Wojciech Świtała",
)


def require(condition, message):
    if not condition:
        raise ValueError(message)


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def checked_source(path, expected):
    require(digest(path) == expected, f"unreviewed source digest: {path}")


def decimal(token):
    require(re.fullmatch(r"\d{1,2},\d{2}", token), f"invalid decimal token: {token}")
    return Fraction(int(token.replace(",", "")), 100)


def parse_layout(text):
    pages = text.split("\f")
    require("scores in the 1st stage" in pages[0], "missing stage-1 title")
    require(not re.search(r"scores in the (2nd|3rd|final) stage", text), "mixed stages")
    header = pages[0].split("punktacja", 1)[0].splitlines()
    judges = []
    for column, label in enumerate(JUDGES, 1):
        hits = [(n, line.index(label) + 1) for n, line in enumerate(header, 1) if label in line]
        require(len(hits) == 1, f"ambiguous/missing judge header: {label}")
        line, offset = hits[0]
        judges.append(dict(judge_id=f"J{column:02}", source_label=label,
                           source_column=column, header_page=1,
                           header_text_line=line, header_text_column=offset))
    require([j["header_text_column"] for j in judges] ==
            sorted(j["header_text_column"] for j in judges), "judge columns changed order")
    performances, cells, seen = [], [], set()
    pending = None
    for page, content in enumerate(pages, 1):
        for line_number, line in enumerate(content.splitlines(), 1):
            if "punktacja" in line:
                require(pending is None, "missing corrected row")
                label, values = line.split("punktacja")
                names = re.split(r"\s{2,}", label.strip())
                require(len(names) == 2, f"ambiguous name columns: {label}")
                match = re.fullmatch(r"(\d+) (.+)", names[0])
                require(match is not None, f"invalid contestant label: {label}")
                number, given = int(match[1]), match[2]
                require(number not in seen, f"duplicate contestant: {number}")
                seen.add(number)
                tokens = values.split()
                require(len(tokens) == 18, "expected 17 raw cells and corrected mean")
                raw = []
                for token in tokens[:17]:
                    require(token.lower() == "s" or
                            (re.fullmatch(r"\d{1,2}", token) and 1 <= int(token) <= 25),
                            f"invalid raw score: {token}")
                    raw.append(None if token.lower() == "s" else int(token))
                decimal(tokens[-1])
                pending = dict(contestant_id=f"C{number:03}", source_number=number,
                    performance_id=f"2025-S1-C{number:03}", given_name_source=given,
                    surname_source=names[1], source_label=given + " " + names[1],
                    source_page=page, raw_text_line=line_number,
                    corrected_mean_token=tokens[-1])
            elif "p. kor." in line:
                require(pending is not None, "corrected row without raw row")
                require(page == pending["source_page"], "raw/corrected rows span pages")
                corrected = line.split("p. kor.")[1].split()
                require(len(corrected) == 17, "expected 17 corrected cells")
                observed = [v for v in raw if v is not None]
                require(observed, "performance has no observed scores")
                mean = Fraction(sum(observed), len(observed))
                displayed = []
                for judge, token, value, correction in zip(judges, tokens, raw, corrected):
                    actual = decimal(correction)
                    expected = 0 if value is None else max(mean-3, min(value, mean+3))
                    require(abs(actual-expected) <= Fraction(1, 200), "corrected cell fails rule XIII.7")
                    require((actual == 0) == (value is None), "recusal placeholder mismatch")
                    if value is not None:
                        displayed.append(actual)
                    cells.append(dict(
                        observation_id=pending["performance_id"] + "-" + judge["judge_id"],
                        performance_id=pending["performance_id"], judge_id=judge["judge_id"],
                        score=value, raw_token=token,
                        missing_reason="recusal_rules_XII_XIII" if value is None else None,
                        corrected_token=correction,
                        corrected_score=None if value is None else float(actual),
                        source_page=page, raw_text_line=pending["raw_text_line"],
                        corrected_text_line=line_number, source_column=judge["source_column"]))
                # Up to 0.005 from rounding cells, plus 0.005 from rounding their mean.
                require(abs(sum(displayed)/len(displayed)-decimal(pending["corrected_mean_token"]))
                        <= Fraction(1, 100), "corrected mean fails display-rounding check")
                performances.append(pending)
                pending = None
    require(pending is None, "missing final corrected row")
    return performances, judges, cells


def build(scores, rules, output):
    output = Path(output)
    require(not output.exists(), "output directory already exists")
    checked_source(scores, SCORES_SHA256)
    checked_source(rules, RULES_SHA256)
    result = subprocess.run(["pdftotext", "-f", "1", "-l", "3", "-layout", "-enc", "UTF-8",
                             str(Path(scores).resolve()), "-"], check=True, capture_output=True)
    text = result.stdout.decode("utf-8")
    performances, judges, cells = parse_layout(text)
    require([r["source_number"] for r in performances] == list(range(1, 85)), "expected contestants 1:84 in source order")
    require(Counter(r["source_page"] for r in performances) == {1: 36, 2: 41, 3: 7}, "unexpected page layout")
    ratings = [dict(observation_id=c["observation_id"], person=c["performance_id"],
                    rater=c["judge_id"], item="stage1_overall", score=c["score"])
               for c in cells if c["score"] is not None]
    require(len(cells) == 1428 and len(ratings) == 1395, "unexpected rating/recusal counts")
    counts = Counter(r["score"] for r in ratings)
    require(sorted(counts) == list(range(8, 26)), "unexpected observed category support")
    output.mkdir(parents=True)
    (output / "stage1-layout.txt").write_bytes(result.stdout)
    for name, payload in (("performances.json", performances), ("judges.json", judges),
                          ("cells.json", cells), ("ratings.json", ratings)):
        (output / name).write_text(json.dumps(payload, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
    manifest = dict(schema="bayesianmgmfrm.chopin_stage1_input.v1", empirical=True,
        source_scores_sha256=SCORES_SHA256, source_rules_sha256=RULES_SHA256,
        source_urls=SOURCE_URLS, source_pages=[1, 2, 3],
        adapter_sha256=digest(__file__),
        extraction="pdftotext -f 1 -l 3 -layout -enc UTF-8; text positions are 1-based within each PDF page",
        pdftotext_version=subprocess.run(["pdftotext", "-v"], capture_output=True, check=True).stderr.decode().splitlines()[0],
        category_levels=list(range(1, 26)), category_direction="higher_is_better",
        category_counts={k: counts[k] for k in range(1, 26)}, unobserved_categories=list(range(1, 8)),
        performances=84, judges=17, cells=1428, observed_ratings=1395, recusals=33,
        judge_counts=[dict(judge_id=j["judge_id"], observed=sum(r["rater"] == j["judge_id"] for r in ratings)) for j in judges],
        observation_order="source contestant number, then source judge column; numbers are not ranks",
        missingness="S is a rule-based recusal; corrected 0,00 is preserved as a token, never a score",
        model_input="ratings.json contains only raw integer scores; corrected values are comparison metadata",
        scope="Stage-1 conditional description only; no posterior fit, cross-stage linking or new-entity prediction",
        files={p.name: digest(p) for p in sorted(output.iterdir())})
    (output / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
    return manifest


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scores", type=Path, required=True)
    parser.add_argument("--rules", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = build(args.scores, args.rules, args.output)
    print(json.dumps({k: result[k] for k in ("performances", "judges", "observed_ratings", "recusals")}))
