# Deploying the TinyNotch landing page

One static folder (`index.html`). No build step, no dependencies — it runs on any static host.
Deploy it to two or three hosts as mirrors; if one goes down, the others keep serving.

## GitHub Pages
1. Push this folder into your repo (e.g. `Zyrqon/tinynotch`) — either the repo root or a `docs/` folder.
2. Repo → Settings → Pages → Source: "Deploy from a branch", branch `main`, folder `/ (root)` or `/docs`.
3. Live at `https://Zyrqon.github.io/tinynotch/` in a minute or two.

## Vercel
1. vercel.com → Add New → Project → Import `Zyrqon/tinynotch`.
2. Framework Preset: **Other**. Build command: *(empty)*. Output directory: the folder containing `index.html` (or `.` if in root).
3. Deploy. Add the same repo again as a second Vercel project only if you want an independent mirror.

## Netlify
1. app.netlify.com → Add new site → Import an existing project (or drag-and-drop the folder onto the deploy screen).
2. No build command, publish directory = folder with `index.html`.

## Cloudflare Pages
1. dash.cloudflare.com → Workers & Pages → Create → Pages → Connect to Git → pick the repo.
2. Framework preset: **None**. Build command: *(empty)*. Output directory: folder with `index.html`.

## Custom domain (optional)
Point a subdomain like `tinynotch.bot-ix.ru` at Vercel and another (e.g. `tinynotch.pages.dev` alias) at Cloudflare — two independent mirrors with one repo as the source of truth.
