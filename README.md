# your_stanford_site

A personal website for `https://web.stanford.edu/~yoursunetid/`, from nothing to
live in about two minutes. Answer seven questions, get an animated single-page
site, and publish it with one command.

Every Stanford student, faculty, and staff member with a full-service SUNet ID
already has this hosting. Most people never use it.

![built with nothing but HTML, CSS and vanilla JS](https://img.shields.io/badge/dependencies-none-8C1515)

## Quick start

```bash
git clone https://github.com/terry891/your_stanford_site.git
cd your_stanford_site
./launch_it.sh
```

One command does everything. The first run asks for your SUNet ID, name, links,
and photo, then for your password and one Duo code, then publishes. It finishes
by offering to remember the login.

**Every run after that is just `./launch_it.sh`** — it rebuilds and republishes,
asking nothing.

Your site is at `https://web.stanford.edu/~yoursunetid/`.

Requirements: `bash`, `python3`, `ssh`, `curl`. All standard on macOS and Linux;
on Windows use WSL. [Pillow](https://pypi.org/project/pillow/) is optional — it
crops your photo to a square, and the site falls back to a monogram without it.

## What you get

A single scrolling page with a pinned three-beat intro, animated counters, a
horizontal project rail, a marquee, and light/dark themes — plus a filterable
project archive and a print-to-PDF CV page.

The animations use CSS [scroll-driven timelines](https://developer.mozilla.org/en-US/docs/Web/CSS/animation-timeline)
where available and degrade in three steps: JavaScript off still gives you the
full content, `prefers-reduced-motion` turns the motion off, and older browsers
get an IntersectionObserver fallback.

## Editing

| I want to change | Edit |
| --- | --- |
| Name, links, photo, email | `./launch_it.sh --edit`, or `site.conf` then `--rebuild` |
| Section text, projects, CV | `templates/*.html` |
| Colours, spacing, type | `templates/css/style.css` — the `:root` block at the top |
| Nav, footer, social icons | `templates/_header.html`, `templates/_footer.html` |

`./launch_it.sh --rebuild` renders `templates/` into `WWW/` without publishing.
Never edit `WWW/` — it is generated and overwritten. Preview with
`cd WWW && python3 -m http.server 8000`.

Templates support `{{VAR}}`, `{{#IF VAR}}…{{/IF}}`, and `{{> partial.html}}`.
Add a page by dropping `something.html` into `templates/`; files starting with
`_` are partials.

## Publishing

`./launch_it.sh` connects to `cardinal.stanford.edu`, repairs the AFS permissions
that make Stanford serve your files, uploads `WWW/`, and checks the live URL.

```
./launch_it.sh              build and publish
./launch_it.sh --edit       re-answer the questions
./launch_it.sh --rebuild    build only, publish nothing
./launch_it.sh --status     what is remembered, and where
./launch_it.sh --forget     erase all of it
./launch_it.sh --logout     close the session, keep what is saved
./launch_it.sh --delete     wipe the server copy first
./launch_it.sh --fix-only   repair permissions, upload nothing
./launch_it.sh --help       everything else
```

### What gets remembered

After the first successful publish it offers to remember your login, so later
runs ask for nothing. It tries hardest first and tells you which one you got:

1. **A login key.** Replaces the password *and* the Duo code. Stanford's
   `cardinal` normally refuses this, because sshd cannot read `~/.ssh` on AFS
   before you hold a token — so the script tests the key immediately and, if it
   does not work, deletes it from the server again rather than leaving it there.
2. **Your password in the OS keyring** (libsecret on Linux, Keychain on macOS),
   encrypted at rest. Later runs then ask only for a Duo code.
3. **Nothing at all** — just the authenticated SSH socket in `~/.ssh/cm/`
   (mode 0700), which lasts `--keep`, 8 hours by default.

**No password is ever written to a file.** `site.conf` holds only your answers,
and `--status` will show you exactly what is stored where.

**A Duo code cannot be remembered, by anyone.** A second factor you could replay
from disk would not be a second factor. Unless the login key works, expect one
Duo prompt per session.

`duossh.py` exists only because Duo redisplays its entire menu after sending an
SMS, which looks like a failure. It hides the menu and asks one question:
`Enter SMS passcode:`.

## Worth knowing about Stanford AFS hosting

- **5 GB quota.** Check with `fs listquota ~` while logged into `cardinal`.
- **Renew annually.** AFS volumes are locked, archived, and eventually deleted
  if you do not renew. Stanford is also sunsetting AFS for web hosting, so treat
  this as a good home for a few years, not forever.
- **403 means permissions, 404 means no such user.** `./launch_it.sh --fix-only`
  handles the first.
- **Use `web.stanford.edu/~sunetid`, not `sunetid.web.stanford.edu`.** The
  second is two labels deep and Stanford's wildcard certificate does not cover
  it, so HTTPS fails there.
- **Directory listings cannot be turned off** via `.htaccess` — `Options` is not
  overridable and setting it returns a 500. `build.py` writes a redirect stub
  into each asset folder instead.
- Static files, JavaScript, CSS, fonts, canvas, and video all work; this is
  plain Apache. Server-side code (CGI, PHP) needs a separate opt-in and runs on
  long-EOL interpreters. Stanford requires [WCAG 2.0 A and AA](https://uit.stanford.edu/guide/webstandards)
  for university web content, which is why this template keeps real text, focus
  styles, and no-JS fallbacks.

## Layout

```
launch_it.sh      the only command you run: ask, build, remember, publish
build.py          templates/ + site.conf -> WWW/
duossh.py         the clean Duo prompt
templates/        edit these
site.conf         your answers, no secrets (gitignored)
WWW/              generated (gitignored)
```

## License

MIT. Use it, fork it, share it with the person down the hall.
