# omalexia site

One static page, `index.html`, no build step. The only external requests are
Google Fonts (Atkinson Hyperlegible Next, JetBrains Mono); everything else is
inline. Copy the file anywhere that serves static files.

The page practises what it preaches: a plain, distinct typeface at 19 px with
1.6 line height and a ~62-character measure, a paper (off-white) theme and a
night theme, a Calm mode (lower contrast, more space, no motion), text size
controls, and a Read-aloud button that uses the browser's own speech — which
on Linux goes through Speech Dispatcher, i.e. the Omalexia voice.

## Hosting

**GitHub Pages (free).** GitHub Pages serves from a repository root or a
`docs/` folder, not from `omalexia/site/`. Two options:

1. A small workflow that publishes this folder:

    ```yaml
    # .github/workflows/site.yml
    name: site
    on: { push: { branches: [main], paths: ['omalexia/site/**'] } }
    permissions: { pages: write, id-token: write, contents: read }
    jobs:
      deploy:
        runs-on: ubuntu-latest
        environment: github-pages
        steps:
          - uses: actions/checkout@v4
          - uses: actions/upload-pages-artifact@v3
            with: { path: omalexia/site }
          - id: deploy
            uses: actions/deploy-pages@v4
    ```
   Then Settings → Pages → Source: GitHub Actions. Add a `CNAME` file here
   for a custom domain (e.g. `omalexia.husense.io`).

2. Or a separate `husense/omalexia.dev`-style repo with `index.html` at its root.

**Cloudflare Pages / Netlify (free).** Point the project at this repo with
build command empty and output directory `omalexia/site`.

**A Husense server.** Any static server works; for nginx:

```nginx
server {
    listen 443 ssl http2;
    server_name omalexia.husense.io;
    root /var/www/omalexia;
    index index.html;
    add_header Cache-Control "public, max-age=600";
}
```

Deploy with `rsync -av --delete omalexia/site/ server:/var/www/omalexia/`.

## Editing

Everything is in `index.html`: tokens at the top of the `<style>` block
(paper and night palettes, type scale, measure), copy in `<main>`, and the
small script at the bottom (theme, calm mode, text size, read aloud, copy
command). Keep the page self-contained.
