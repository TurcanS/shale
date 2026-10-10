"""Runs core/search.js (the launcher's matching) in node, outside QML."""
import json
from pathlib import Path
import shutil
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
SEARCH = (ROOT / "core/search.js").read_text().replace(".pragma library", "", 1)
# Scores a raw app the way the launcher does after preparing it once.
SEARCH += "\nfunction appScore(app, term) { return scoreApp(prepare(app), fold(term).trim()); }"

APPS = [
    {"name": "Code - OSS", "genericName": "Text Editor", "comment": "Code Editing. Redefined.", "keywords": ["vscode"],
     "id": "code-oss", "startupClass": "code-oss", "command": ["code-oss", "%F"]},
    {"name": "Virtual Machine Manager", "genericName": "", "comment": "Manage virtual machines",
     "keywords": ["virtualization", "libvirt", "vm", "vmm", "qemu", "xen", "lxc", "kvm"], "id": "virt-manager", "startupClass": "", "command": ["virt-manager"]},
    {"name": "LibreOffice Calc", "genericName": "Spreadsheet", "comment": "Perform calculations, analyze information and manage lists in spreadsheets.",
     "keywords": ["Accounting", "Stats", "OpenDocument Spreadsheet", "Chart", "Microsoft Excel", "ods", "xls", "xlsx"], "id": "libreoffice-calc", "startupClass": "", "command": ["libreoffice", "--calc", "%U"]},
    {"name": "LibreOffice Impress", "genericName": "Presentation", "comment": "Create and edit presentations for slideshows, meeting and Web pages.",
     "keywords": ["Slideshow", "Slides", "odp", "ppt", "pptx"], "id": "libreoffice-impress", "startupClass": "", "command": ["libreoffice", "--impress", "%U"]},
    {"name": "LibreOffice Base", "genericName": "Database Development", "comment": "Manage databases, create queries and reports to track and manage your information.",
     "keywords": ["Data", "SQL", "Query", "Report"], "id": "libreoffice-base", "startupClass": "", "command": ["libreoffice", "--base", "%U"]},
    {"name": "Firefox", "genericName": "Web Browser", "comment": "Browse the World Wide Web", "keywords": ["Internet", "WWW", "Browser", "Web", "Explorer"],
     "id": "firefox", "startupClass": "firefox", "command": ["/usr/lib/firefox/firefox", "%u"]},
    {"name": "Neovim", "genericName": "Text Editor", "comment": "Edit text files", "keywords": ["Text", "editor"], "id": "nvim", "startupClass": "", "command": ["nvim", "%F"]},
    {"name": "Paramètres", "genericName": "", "comment": "", "keywords": [], "id": "org.gnome.Settings", "startupClass": "", "command": ["env", "LANG=fr_FR.UTF-8", "gnome-control-center"]},
    {"name": "Spotify", "genericName": "Music Player", "comment": "", "keywords": [], "id": "com.spotify.Client", "startupClass": "", "command": ["/usr/bin/flatpak", "run", "--branch=stable", "--arch=x86_64", "com.spotify.Client"]},
    {"name": "Obsidian", "genericName": "", "comment": "", "keywords": [], "id": "md.obsidian.Obsidian", "startupClass": "",
     "command": ["flatpak", "run", "md.obsidian.Obsidian"]},
]


@unittest.skipUnless(shutil.which("node"), "node is not installed")
class SearchTests(unittest.TestCase):
    def js(self, expression):
        script = SEARCH + "\nprocess.stdout.write(JSON.stringify(" + expression + "));"
        return json.loads(subprocess.run(["node", "-e", script], capture_output=True, text=True, check=True).stdout)

    def ranked(self, term):
        scores = self.js(f"{json.dumps(APPS)}.map(app => [app.name, appScore(app, {json.dumps(term)})])")
        return [name for name, score in sorted(scores, key=lambda item: -item[1]) if score > 0]

    def test_keywords_ids_and_commands_find_apps(self):
        self.assertEqual(self.ranked("vscode")[0], "Code - OSS")
        self.assertEqual(self.ranked("qemu"), ["Virtual Machine Manager"])
        self.assertEqual(self.ranked("xls")[0], "LibreOffice Calc")
        self.assertEqual(self.ranked("nvim")[0], "Neovim")
        self.assertEqual(self.ranked("gnome-control")[0], "Paramètres")
        self.assertEqual(self.ranked("spotify.client")[0], "Spotify")

    def test_flatpak_apps_are_named_by_their_id_not_by_flatpak(self):
        self.assertEqual(self.js('commandName(["/usr/bin/flatpak", "run", "--branch=stable", "com.spotify.Client"])'), "com.spotify.Client")
        self.assertEqual(self.ranked("flat"), [])

    def test_names_win_and_noise_is_dropped(self):
        self.assertEqual(self.ranked("fire"), ["Firefox"])
        self.assertEqual(self.ranked("code")[0], "Code - OSS")
        self.assertEqual(self.ranked("ffx"), ["Firefox"])
        self.assertNotIn("LibreOffice Base", self.ranked("vscode"))
        self.assertEqual(self.ranked("zzzz"), [])

    def test_descriptions_match_on_word_starts_only(self):
        self.assertIn("LibreOffice Calc", self.ranked("spreadsheet"))
        self.assertNotIn("LibreOffice Calc", self.ranked("readsheet"))

    def test_accents_are_ignored(self):
        self.assertEqual(self.ranked("parametres"), ["Paramètres"])
        self.assertEqual(self.js('fold("Ångström Ünïcode")'), "angstrom unicode")

    def test_usage_has_diminishing_returns(self):
        boosts = self.js("[0, 1, 20, 1000].map(usageBoost)")
        self.assertEqual(boosts[0], 0)
        self.assertLess(boosts[3], 400)
        self.assertGreater(boosts[3], boosts[2])

    def test_addresses_open_and_file_like_names_search(self):
        cases = {"github.com": True, "https://node.js": True, "localhost:3000": True, "192.168.1.1": True, "www.example": True,
                 "example.com/path": True, "www.999.md": True, "node.js": False, "vue.js": False, "python3.12": False,
                 "setup.py": False, "README.md": False, "script.pl": False, "logo.ai": False, "Makefile.in": False,
                 "hello world": False, "rust": False, "": False}
        results = self.js(f"{json.dumps(list(cases))}.map(isAddress)")
        self.assertEqual(dict(zip(cases, results)), cases)

    def test_local_addresses_open_over_http(self):
        urls = {"localhost?debug=1": "http://localhost?debug=1", "localhost:3000/app": "http://localhost:3000/app",
                "192.168.1.1#admin": "http://192.168.1.1#admin", "github.com": "https://github.com",
                "https://example.com": "https://example.com", "http://localhost": "http://localhost"}
        results = self.js(f"{json.dumps(list(urls))}.map(addressUrl)")
        self.assertEqual(dict(zip(urls, results)), urls)


if __name__ == "__main__":
    unittest.main()
