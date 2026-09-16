# omalexia site

Three static pages, no build step: `index.html` (the announcement, now in
beta), `research.html` (the speech research and the numbers), and
`changelog.html` (what changed, and when). The only external requests are
Google Fonts (Atkinson Hyperlegible Next, JetBrains Mono); everything else is
inline. Copy the folder anywhere that serves static files.

SEO lives in each page's `<head>` (canonical URL, Open Graph and Twitter
card tags, JSON-LD, favicon) plus `robots.txt`, `sitemap.xml` and the share
image `og.png` (1200x630, rebuilt from the og-card design when the tagline
changes). When adding a page: give it a canonical link and OG tags, and add
it to `sitemap.xml`.

The pages practise what they preach: a plain, distinct typeface at 19 px with
1.6 line height and a ~62-character measure, a paper (off-white) theme and a
night theme, a Calm mode (lower contrast, more space, no motion), text size
controls, and a Read-aloud button that uses the browser's own speech, which
on Linux goes through Speech Dispatcher, i.e. the Omalexia voice.

## Hosting: GitHub Pages, omalexia.org

This is set up. `.github/workflows/pages.yml` publishes this folder to GitHub
Pages on every push to `main` that touches `site/`. The Pages source is
"GitHub Actions" and the custom domain is `omalexia.org` (Settings → Pages).

To make omalexia.org resolve, set these records at the domain's DNS provider:

```
omalexia.org.      A       185.199.108.153
omalexia.org.      A       185.199.109.153
omalexia.org.      A       185.199.110.153
omalexia.org.      A       185.199.111.153
www.omalexia.org.  CNAME   thefreshoffice.github.io.
```

Once the records propagate, tick "Enforce HTTPS" in Settings → Pages; GitHub
issues the certificate automatically. Without the domain, the site is at
https://thefreshoffice.github.io/omalexia/.

### omalexia.com

One GitHub Pages site carries one custom domain, so omalexia.com is served
by a second, tiny repository, `thefreshoffice/omalexia.com`: a single page
that redirects (path-preserving) to https://omalexia.org/ and tells search
engines not to index it. Its DNS at TransIP is the same shape as the .org:
four GitHub Pages A records on the apex and a `www` CNAME to
`thefreshoffice.github.io.`.

### Alternatives

**Cloudflare Pages / Netlify (free).** Point the project at this repo with
build command empty and output directory `site`.

**Your own server.** Any static server works; for nginx:

```nginx
server {
    listen 443 ssl http2;
    server_name omalexia.org;
    root /var/www/omalexia;
    index index.html;
    add_header Cache-Control "public, max-age=600";
}
```

Deploy with `rsync -av --delete site/ server:/var/www/omalexia/`.

## Editing

The shared design lives in each page's `<style>` block: tokens at the top
(paper and night palettes, type scale, measure), copy in `<main>`, and the
small script at the bottom (theme, calm mode, text size, read aloud, copy
command). The three pages share the same header, tokens and script; when you
change those in `index.html`, mirror the change in the other two. Keep every
page self-contained.
