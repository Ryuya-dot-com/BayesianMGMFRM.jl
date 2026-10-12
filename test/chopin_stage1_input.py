"""Source-independent parser regression checks; no PDF download or fitting."""
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
import chopin_stage1_input as C


def fixture():
    header = "".join(label.ljust(30) for label in C.JUDGES)
    raw = "14 17 19 21 21 s 18 16 17 20 21 21 18 21 18 16 15 18,41"
    corrected = "15,31 17,00 19,00 21,00 21,00 0,00 18,00 16,00 17,00 20,00 21,00 21,00 18,00 21,00 18,00 16,00 15,31"
    return ("scores in the 1st stage\n" + header + "\n"
            "1 Hoi Leong   Cheong   punktacja " + raw + "\n"
            "                       p. kor. " + corrected + "\n\f"
            "2 Chun        Lam U    punktacja " + raw + "\n"
            "                       p. kor. " + corrected + "\n\f")


class InputChecks(unittest.TestCase):
    def test_names_ids_pages_and_recusals(self):
        people, judges, cells = C.parse_layout(fixture())
        self.assertEqual((people[0]["given_name_source"], people[1]["surname_source"]), ("Hoi Leong", "Lam U"))
        self.assertEqual(people[1]["source_page"], 2)
        self.assertEqual(judges[14]["source_label"], "K. Popowa-Zydroń")
        self.assertEqual([j["source_column"] for j in judges], list(range(1, 18)))
        self.assertEqual(len({c["observation_id"] for c in cells}), 34)
        self.assertEqual(cells[0]["score"], 14)
        self.assertEqual(cells[0]["corrected_score"], 15.31)
        self.assertEqual(cells[0]["raw_text_line"], 3)
        self.assertEqual(cells[0]["corrected_text_line"], 4)
        self.assertEqual(cells[5]["raw_token"], "s")
        self.assertIsNone(cells[5]["score"])
        self.assertIsNone(cells[5]["corrected_score"])
        self.assertEqual(cells[5]["corrected_token"], "0,00")
        self.assertEqual(cells[5]["missing_reason"], "recusal_rules_XII_XIII")

    def test_invalid_sources_fail_closed(self):
        text = fixture()
        mutations = {
            "duplicate contestant": text.replace("2 Chun", "1 Chun"),
            "ambiguous name": text.replace("Hoi Leong   Cheong", "Hoi Leong Cheong"),
            "missing header": text.replace("Garrick Ohlsson", "UNKNOWN"),
            "swapped columns": text.replace("Garrick Ohlsson", "@H@").replace("John Allison", "Garrick Ohlsson").replace("@H@", "John Allison"),
            "wrong raw width": text.replace("14 17 19", "14 17", 1),
            "zero score": text.replace("14 17 19", "0 17 19", 1),
            "decimal score": text.replace("14 17 19", "14,00 17 19", 1),
            "out of scale": text.replace("14 17 19", "26 17 19", 1),
            "recusal not zero": text.replace("0,00", "1,00", 1),
            "wrong correction": text.replace("15,31", "15,40", 1),
            "wrong mean": text.replace("18,41", "19,41", 1),
            "mixed stages": text + "scores in the 2nd stage\n",
            "truncated final row": text[:text.rfind("p. kor.")],
            "orphan correction": text + "p. kor. 0,00\n",
        }
        for label, mutated in mutations.items():
            with self.subTest(label=label), self.assertRaises(ValueError):
                C.parse_layout(mutated)

    def test_preserved_source_and_output(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            pdf = root / "wrong.pdf"
            pdf.write_bytes(b"unreviewed source")
            with self.assertRaisesRegex(ValueError, "unreviewed source"):
                C.build(pdf, pdf, root / "new")
            self.assertFalse((root / "new").exists())
            with self.assertRaisesRegex(ValueError, "already exists"):
                C.build(pdf, pdf, root)
            self.assertEqual(pdf.read_bytes(), b"unreviewed source")


if __name__ == "__main__":
    unittest.main()
