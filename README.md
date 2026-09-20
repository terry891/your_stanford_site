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
./setup.sh      # asks for your SUNet ID, name, links, photo
./deploy.sh     # asks for your password + one Duo code, then publishes
```

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
| Name, links, photo, email | `./setup.sh` again, or `site.conf` then `./setup.sh --rebuild` |
| Section text, projects, CV | `templates/*.html` |
| Colours, spacing, type | `templates/css/style.css` — the `:root` block at the top |
| Nav, footer, social icons | `templates/_header.html`, `templates/_footer.html` |

`./setup.sh --rebuild` renders `templates/` into `WWW/`. Never edit `WWW/` — it
is generated and overwritten. Preview with `cd WWW && python3 -m http.server 8000`.

Templates support `{{VAR}}`, `{{#IF VAR}}…{{/IF}}`, and `{{> partial.html}}`.
Add a page by dropping `something.html` into `templates/`; files starting with
`_` are partials.

## Publishing

`./deploy.sh` connects to `cardinal.stanford.edu`, repairs the AFS permissions
that make Stanford serve your files, uploads `WWW/`, and checks the live URL.

```
./deploy.sh              publish
./deploy.sh --status     is a session still open?
./deploy.sh --logout     close it now
./deploy.sh --delete     wipe the server copy first
./deploy.sh --fix-only   repair permissions, upload nothing
./deploy.sh --help       everything else
```

**Your password is never stored.** The first deploy asks for it once; SSH then
keeps an authenticated socket in `~/.ssh/cm/` (mode 0700) for 8 hours, so later
deploys prompt for nothing. `--keep 30m` or `--logout` shortens that. Stanford's
`cardinal` host does not accept SSH keys, so a Duo prompt on the first run of
the day is unavoidable.

`duossh.py` exists only because Duo redisplays its entire menu after sending an
SMS, which looks like a failure. It hides the menu and asks one question:
`Enter SMS passcode:`.

## Worth knowing about Stanford AFS hosting

- **5 GB quota.** Check with `fs listquota ~` while logged into `cardinal`.
- **Renew annually.** AFS volumes are locked, archived, and eventually deleted
  if you do not renew. Stanford is also sunsetting AFS for web hosting, so treat
  this as a good home for a few years, not forever.
- **403 means permissions, 404 means no such user.** `./deploy.sh --fix-only`
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
setup.sh          asks the questions, writes site.conf, builds
build.py          templates/ + site.conf -> WWW/
deploy.sh         AFS permissions, upload, verify
duossh.py         the clean Duo prompt
templates/        edit these
site.conf         your answers (gitignored)
WWW/              generated (gitignored)
```

## License

MIT. Use it, fork it, share it with the person down the hall.
