# Mox web

Static pages served on GitHub Pages at <https://giamsoo23.github.io/Mox/>.
No framework, no build step, no dependencies.

| Path | What it is |
|---|---|
| `pair/` | **The pairing page.** The desktop's QR code points here. It reads the pairing link from the URL fragment ([PROTOCOL.md §8](../shared/PROTOCOL.md)) and offers the next step: on Android, install Mox and/or open it through an `intent://` hand-off |
| `pair/pairing.js` | The link parser. Pure functions, used by the page and the tests |
| `index.html` | A small landing page |

Privacy: the pairing data stays in the fragment, which browsers don't send
to servers. A strict Content-Security-Policy allows only the page's own
script and styles, and there are no analytics or third-party requests.

## Test

```bash
cd web && npm test     # node --test, runs pairing.js against shared/fixtures/pairing/
```

Preview locally (ES modules need http, not file://):

```bash
cd web && python3 -m http.server 8000
# open http://localhost:8000/pair/#v=1&...  (copy a link from shared/fixtures/pairing/valid/)
```

CI runs the tests on every PR that touches `web/` or the pairing fixtures,
and deploys to GitHub Pages on every push to `main`.
