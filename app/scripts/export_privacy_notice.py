#!/usr/bin/env python3
"""Export the in-app bilingual privacy draft for review outside the app."""

from pathlib import Path
import re


APP_ROOT = Path(__file__).resolve().parents[1]
SOURCE = APP_ROOT / "lib" / "legal" / "privacy_policy_draft.dart"
OUTPUT = APP_ROOT / "docs" / "PRIVACY_NOTICE_DRAFT.md"
POLICY_NAMES = (
    ("Thai", "privacyPolicyTextTh"),
    ("English", "privacyPolicyTextEn"),
)


def extract_policy(source: str, name: str) -> str:
    """Read one Dart triple-quoted constant without changing its wording."""
    pattern = rf"const\s+{re.escape(name)}\s*=\s*'''(.*?)''';"
    match = re.search(pattern, source, flags=re.DOTALL)
    if match is None:
        raise ValueError(f"Could not find Dart policy constant: {name}")
    return match.group(1).strip()


def main() -> None:
    source = SOURCE.read_text(encoding="utf-8")
    sections = [
        f"## {language}\n\n{extract_policy(source, name)}"
        for language, name in POLICY_NAMES
    ]
    document = (
        "# doz — Privacy Notice Draft\n\n"
        "> Generated from `lib/legal/privacy_policy_draft.dart`; "
        "edit the source constants, then rerun this script to refresh this copy.\n\n"
        + "\n\n---\n\n".join(sections)
        + "\n"
    )
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(document, encoding="utf-8")
    print(f"Wrote {OUTPUT}")


if __name__ == "__main__":
    main()
