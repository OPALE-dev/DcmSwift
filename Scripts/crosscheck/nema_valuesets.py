"""Compare DcmSwift's PS3.16 terminology with NEMA's FHIR value sets.

  nema_valuesets.py dicom-terminology-2026d.json VALUESET_DIR

VALUESET_DIR holds the ValueSet-dicom-cid-<cid>-<keyword>.json files that
NEMA publishes for the current edition at
https://dicom.nema.org/medical/dicom/resources/valuesets/fhir/json/, each the
transitive closure of a Context Group. For every group, compares the
version, and the (Coding Scheme Designator, Code Value) pairs with included
groups resolved, and the Code Meanings. SNOMED-RT identifiers
(http://snomed.info/srt), an alternative column of the PS3.16 tables, are
left out, and so are codes NEMA does not export: those with a Coding
Scheme Version, and those of the UNS scheme. Codes listed with several
meanings, synonyms or errors of PS3.16, are reported but not counted.
Exits 1 on any difference.
"""
import glob, json, os, sys

SYSTEMS = {
    "http://snomed.info/sct": "SCT",
    "http://dicom.nema.org/resources/ontology/DCM": "DCM",
    "http://loinc.org": "LN",
    "http://ncit.nci.nih.gov": "NCIt",
    "http://www.nlm.nih.gov/research/umls": "UMLS",
    "http://unitsofmeasure.org": "UCUM",
    "http://www.radlex.org": "RADLEX",
    "urn:iso:std:iso:11073:10101": "MDC",
    "http://arxiv.org/abs/1612.07003": "IBSI",
    "http://sig.biostr.washington.edu/projects/fm/AboutFM.html": "FMA",
    "doi:10.1016/S0735-1097(99)00126-6": "NCDR",  # also used for BARI
    "http://www.nlm.nih.gov/mesh/meshhome.html": "MSH",
    "http://braininfo.rprc.washington.edu/aboutBrainInfo.aspx#NeuroNames": "NEU",
    "http://pubchem.ncbi.nlm.nih.gov": "PUBCHEM_CID",
    "http://www.nlm.nih.gov/research/umls/rxnorm": "RXNORM",
    "http://hl7.org/fhir/sid/icd-10": "I10",
    "http://hl7.org/fhir/sid/ndc": "NDC",
    "http://www.itis.gov": "ITIS_TSN",
}


def main(path, folder):
    data = json.load(open(path, encoding="utf-8"))
    groups = {group["cid"]: group for group in data["contextGroups"]}

    def closure(cid, seen):
        """Every code of the group and its included groups, with all the
        meanings PS3.16 gives it there: one code may have a different
        meaning in each group, or even twice in one group."""
        if cid in seen or cid not in groups:
            return {}
        seen.add(cid)
        result = {}
        for scheme, value, meaning, *version in groups[cid]["codes"]:
            if version:
                versioned.add((scheme, value))
            result.setdefault((scheme, value), set()).add(meaning)
        for included in groups[cid].get("includes", []):
            for key, meanings in closure(included, seen).items():
                result.setdefault(key, set()).update(meanings)
        return result

    differences, compared, unknown_systems = [], 0, set()
    # NEMA's FHIR value sets leave out codes that carry a Coding Scheme
    # Version, and the codes of schemes they give no system, such as UNS.
    versioned = set()
    unexported_schemes = {"UNS"}
    for file in sorted(glob.glob(os.path.join(folder, "ValueSet-dicom-cid-*.json"))):
        valueset = json.load(open(file, encoding="utf-8"))
        cid = int(valueset["id"].split("-")[2])
        group = groups.get(cid)
        if group is None:
            differences.append(f"CID {cid}: missing from DcmSwift")
            continue
        theirs = {}
        for include in valueset.get("compose", {}).get("include", []):
            system = include.get("system")
            if system == "http://snomed.info/srt" or system is None:
                continue
            scheme = SYSTEMS.get(system)
            if scheme is None:
                unknown_systems.add(system)
                continue
            for concept in include.get("concept", []):
                display = concept.get("display", "").replace("\u200b", "")
                theirs[(scheme, concept["code"])] = display
        mine = closure(cid, set())
        # NEMA gives BARI and NCDR codes the same system.
        for key in [key for key in theirs if key[0] == "NCDR" and key not in mine and ("BARI", key[1]) in mine]:
            theirs[("BARI", key[1])] = theirs.pop(key)
        compared += 1
        if group.get("version") != valueset.get("version"):
            differences.append(f"CID {cid}: version {group.get('version')} != {valueset.get('version')}")
        only_mine = {key for key in set(mine) - set(theirs) - versioned if key[0] not in unexported_schemes}
        only_theirs = set(theirs) - set(mine)
        if only_mine or only_theirs:
            differences.append(f"CID {cid}: {len(only_mine)} DcmSwift only {sorted(only_mine)[:3]}, "
                               f"{len(only_theirs)} NEMA only {sorted(only_theirs)[:3]}")
        for key in set(mine) & set(theirs):
            if theirs[key] not in mine[key]:
                differences.append(f"CID {cid}: {key} meaning {sorted(mine[key])!r} has no {theirs[key]!r}")
    for line in differences:
        print(line)
    duplicates = []
    for cid, group in sorted(groups.items()):
        seen = {}
        for scheme, value, meaning, *_ in group["codes"]:
            if (scheme, value) in seen and seen[(scheme, value)] != meaning:
                duplicates.append(f"CID {cid}: ({scheme}, {value}) is both {seen[(scheme, value)]!r} and {meaning!r}")
            seen.setdefault((scheme, value), meaning)
    for line in duplicates:
        print("PS3.16 gives several meanings (synonyms or errors):", line)
    if unknown_systems:
        print("unmapped systems:", sorted(unknown_systems))
    print(f"{len(versioned)} codes with a Coding Scheme Version, which NEMA's FHIR value sets leave out")
    print(f"{compared} context groups compared with NEMA's value sets, {len(differences)} differences")
    return 1 if differences or unknown_systems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1], sys.argv[2]))
