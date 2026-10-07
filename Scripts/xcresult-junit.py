#!/usr/bin/env python3
"""Convert an Xcode result bundle into a JUnit XML report for GitLab CI.

Usage: xcresult-junit.py <bundle.xcresult> <report.xml>

Reads the test tree from `xcrun xcresulttool get test-results tests`
(Xcode 16+) and writes one <testcase> per Test Case node, preserving
failures and skips. Only the Python standard library is used so the script
runs with the interpreter bundled with Xcode.
"""

import json
import subprocess
import sys
import xml.etree.ElementTree as ET


def test_tree(bundle):
    output = subprocess.run(
        ["xcrun", "xcresulttool", "get", "test-results", "tests", "--path", bundle],
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    return json.loads(output)


def collect_cases(node, suite, cases):
    node_type = node.get("nodeType")
    if node_type == "Test Suite":
        suite = node.get("name", suite)
    if node_type == "Test Case":
        messages = [
            child.get("name", "")
            for child in node.get("children", [])
            if child.get("nodeType") == "Failure Message"
        ]
        cases.append((suite, node, messages))
        return
    for child in node.get("children", []):
        collect_cases(child, suite, cases)


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    bundle, report = sys.argv[1], sys.argv[2]

    cases = []
    for node in test_tree(bundle).get("testNodes", []):
        collect_cases(node, "", cases)
    if not cases:
        sys.exit(f"No test cases found in {bundle}")

    root = ET.Element("testsuites")
    suite_element = ET.SubElement(root, "testsuite", name="iOS Simulator")
    failures = skipped = 0
    total_time = 0.0
    for suite, node, messages in cases:
        duration = float(node.get("durationInSeconds") or 0)
        total_time += duration
        case = ET.SubElement(
            suite_element,
            "testcase",
            classname=suite,
            name=node.get("name", "").removesuffix("()"),
            time=f"{duration:.6f}",
        )
        result = node.get("result")
        if result == "Failed":
            failures += 1
            failure = ET.SubElement(
                case, "failure", message=messages[0] if messages else "Failed"
            )
            failure.text = "\n".join(messages)
        elif result == "Skipped":
            skipped += 1
            ET.SubElement(case, "skipped", message="\n".join(messages))

    suite_element.set("tests", str(len(cases)))
    suite_element.set("failures", str(failures))
    suite_element.set("skipped", str(skipped))
    suite_element.set("errors", "0")
    suite_element.set("time", f"{total_time:.6f}")
    ET.ElementTree(root).write(report, encoding="UTF-8", xml_declaration=True)
    print(f"{report}: {len(cases)} tests, {failures} failures, {skipped} skipped")


if __name__ == "__main__":
    main()
