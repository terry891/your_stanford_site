#!/usr/bin/env python3
"""Render templates/ into WWW/ using the answers stored in site.conf."""

import html
import re
import shlex
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
TEMPLATES = ROOT / "templates"
OUT = ROOT / "WWW"
CONF = ROOT / "site.conf"

RE_INCLUDE = re.compile(r"\{\{>\s*([\w.\-/]+)\s*\}\}")
RE_IF = re.compile(r"\{\{#IF\s+(\w+)\s*\}\}(.*?)\{\{/IF\}\}", re.S)
RE_VAR = re.compile(r"\{\{(\w+)\}\}")


def load_conf(path=CONF):
    if not path.exists():
        sys.exit(f"error: {path.name} not found. Run ./setup.sh first.")
    conf = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, raw = line.partition("=")
        try:
            parts = shlex.split(raw)
        except ValueError:
            parts = [raw]
        conf[key.strip()] = parts[0] if parts else ""
    return conf


def derive(conf):
    sunet = conf.get("SUNETID", "").strip()
    if not sunet:
        sys.exit("error: SUNETID is missing from site.conf")

    name = conf.get("NAME") or sunet
    conf["NAME"] = name
    conf.setdefault("EMAIL", f"{sunet}@stanford.edu")
    conf["SITE_URL"] = f"https://web.stanford.edu/~{sunet}/"

    if not conf.get("INITIALS"):
        words = [w for w in re.split(r"[\s\-]+", name) if w]
        conf["INITIALS"] = "".join(w[0] for w in words[:2]).upper() or sunet[:2].upper()

    conf.setdefault("ROLE", "Student at Stanford University")
    conf.setdefault("BIO", "A short sentence about what you study and what you care about.")
    conf.setdefault("STATUS", "Open to research and internships")

    photo = conf.get("PHOTO_FILE", "").strip()
    has_photo = bool(photo) and (TEMPLATES / "img" / photo).is_file()
    conf["HAS_PHOTO"] = "1" if has_photo else ""
    conf["NO_PHOTO"] = "" if has_photo else "1"
    return conf


def render(text, conf, depth=0):
    if depth > 5:
        sys.exit("error: template includes are nested too deeply")

    def include(match):
        part = TEMPLATES / match.group(1)
        if not part.is_file():
            sys.exit(f"error: missing partial {match.group(1)}")
        return render(part.read_text(encoding="utf-8"), conf, depth + 1)

    text = RE_INCLUDE.sub(include, text)
    text = RE_IF.sub(lambda m: m.group(2) if conf.get(m.group(1), "") else "", text)
    text = RE_VAR.sub(lambda m: html.escape(conf.get(m.group(1), ""), quote=True), text)
    return re.sub(r"\n[ \t]*\n[ \t]*\n+", "\n\n", text)


def main():
    conf = derive(load_conf())

    # index.html links to #anchors directly; other pages route through it.
    pages = sorted(p for p in TEMPLATES.glob("*.html") if not p.name.startswith("_"))
    if not pages:
        sys.exit("error: no page templates found")

    OUT.mkdir(exist_ok=True)
    wanted = {p.name for p in pages}
    for stale in OUT.glob("*.html"):
        if stale.name not in wanted:
            stale.unlink()

    for page in pages:
        conf["HOME"] = "" if page.name == "index.html" else "index.html"
        (OUT / page.name).write_text(render(page.read_text(encoding="utf-8"), conf), encoding="utf-8")

    # Stanford's Apache lists any directory without an index file, and `Options
    # -Indexes` in .htaccess is rejected there, so every asset folder gets a stub.
    stub = '<!doctype html><meta http-equiv="refresh" content="0;url=../">\n'
    for sub in ("css", "js", "img"):
        src, dst = TEMPLATES / sub, OUT / sub
        if not src.is_dir():
            continue
        shutil.rmtree(dst, ignore_errors=True)
        shutil.copytree(src, dst, ignore=shutil.ignore_patterns(".*"))
        (dst / "index.html").write_text(stub, encoding="utf-8")

    files = sum(1 for _ in OUT.rglob("*") if _.is_file())
    print(f"Built {len(pages)} pages and {files - len(pages)} assets into WWW/")
    print(f"Site URL after deploy: {conf['SITE_URL']}")


if __name__ == "__main__":
    main()
