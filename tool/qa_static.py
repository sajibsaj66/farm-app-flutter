from pathlib import Path
import sys

lib = Path("lib")
files = {p.relative_to(lib).as_posix(): p.read_text(encoding="utf-8") for p in sorted(lib.rglob("*.dart"))}
src = "\n".join(files.values())
checks = {
    "Flutter app entry point": "void main() async" in files.get("main.dart", ""),
    "MVC layout (models/views/controllers)": all(any(f.startswith(d + "/") for f in files) for d in ("models", "views", "controllers")),
    "Local persistence via SharedPreferences": "SharedPreferences.getInstance()" in src and "setString" in src,
    "CRUD create action": "Future<void> add(" in src,
    "CRUD update action": "Future<void> update(" in src,
    "CRUD delete action": "Future<void> remove(" in src,
    "Demo reset action": "Future<void> reset(" in src,
    "Search control": "onChanged: controller.setQuery" in src,
    "Filter controls": "ChoiceChip" in src,
    "Form validation": "formKey.currentState!.validate()" in src,
    "CSV export": "CSV export" in src and "SelectableText(csv" in src,
    "Settings and notification screens": "class SettingsPage" in src and "class NotificationsPage" in src,
    "Responsive navigation": "NavigationRail" in src and "NavigationBar" in src,
    "Views do not touch storage directly": not any("shared_preferences" in body for f, body in files.items() if f.startswith("views/")),
    "No placeholder TODO markers": "TODO" not in src,
}
failed = []
for label, ok in checks.items():
    print(f"[{'PASS' if ok else 'FAIL'}] {label}")
    if not ok: failed.append(label)
print(f"\nResult: {len(checks)-len(failed)}/{len(checks)} static checks passed.")
sys.exit(1 if failed else 0)
