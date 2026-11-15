#!/usr/bin/env python3
"""EN: Export the bilingual app notice for review. TH: ส่งออกร่างประกาศสองภาษาสำหรับตรวจทาน"""

from pathlib import Path
import re


APP_ROOT = Path(__file__).resolve().parents[1]  # EN: Resolve the app root from this script. TH: หา root ของแอปจากตำแหน่งสคริปต์
SOURCE = APP_ROOT / "lib" / "legal" / "privacy_policy_draft.dart"  # EN: Read the notice used by Flutter. TH: อ่านประกาศที่ Flutter ใช้จริง
OUTPUT = APP_ROOT / "docs" / "PRIVACY_NOTICE_DRAFT.md"  # EN: Write the review copy under app docs. TH: เขียนสำเนาสำหรับตรวจทานใน docs ของแอป
POLICY_NAMES = (
    ("Thai", "privacyPolicyTextTh"),  # EN: Map the Thai heading to its Dart constant. TH: ผูกหัวข้อภาษาไทยกับค่าคงที่ Dart
    ("English", "privacyPolicyTextEn"),  # EN: Map the English heading to its Dart constant. TH: ผูกหัวข้อภาษาอังกฤษกับค่าคงที่ Dart
)


def extract_policy(source: str, name: str) -> str:
    """EN: Extract a Dart notice verbatim. TH: ดึงข้อความประกาศจาก Dart โดยคงถ้อยคำเดิม"""
    pattern = rf"const\s+{re.escape(name)}\s*=\s*'''(.*?)''';"  # EN: Match only the named triple-quoted constant. TH: จับคู่เฉพาะค่าคงที่สามอัญประกาศที่ระบุ
    match = re.search(pattern, source, flags=re.DOTALL)  # EN: Include newlines inside the notice. TH: รวมขึ้นบรรทัดใหม่ภายในประกาศ
    if match is None:
        # EN: Stop instead of publishing an empty or mismatched notice. TH: หยุดแทนการสร้างประกาศว่างหรือผิดฉบับ
        raise ValueError(f"Could not find Dart policy constant: {name}")
    return match.group(1).strip()  # EN: Remove only surrounding blank lines. TH: ตัดเฉพาะบรรทัดว่างรอบข้อความ


def main() -> None:
    """EN: Build the Markdown review copy. TH: สร้างสำเนา Markdown สำหรับตรวจทาน"""
    source = SOURCE.read_text(encoding="utf-8")  # EN: Read Unicode Thai and English source. TH: อ่านต้นฉบับภาษาไทยและอังกฤษแบบ Unicode
    sections = [
        f"## {language}\n\n{extract_policy(source, name)}"  # EN: Put each notice under its language heading. TH: วางประกาศแต่ละภาษาใต้หัวข้อ
        for language, name in POLICY_NAMES
    ]
    document = (
        "# doz — Privacy Notice Draft\n\n"  # EN: Label the export as a draft. TH: ระบุว่าไฟล์ส่งออกเป็นฉบับร่าง
        "> Generated from `lib/legal/privacy_policy_draft.dart`; "
        "edit the source constants, then rerun this script to refresh this copy.\n\n"  # EN: Point reviewers to the source of truth. TH: บอกผู้ตรวจว่าต้นฉบับอยู่ที่ใด
        + "\n\n---\n\n".join(sections)
        + "\n"  # EN: End the Markdown file with one newline. TH: ปิดท้ายไฟล์ Markdown ด้วยขึ้นบรรทัดใหม่
    )
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)  # EN: Ensure the review directory exists. TH: สร้างโฟลเดอร์สำหรับตรวจทานหากยังไม่มี
    OUTPUT.write_text(document, encoding="utf-8")  # EN: Save the exact bilingual export. TH: บันทึกข้อความส่งออกสองภาษา
    print(f"Wrote {OUTPUT}")  # EN: Report only the output path. TH: แสดงเฉพาะพาธไฟล์ผลลัพธ์


if __name__ == "__main__":
    main()
