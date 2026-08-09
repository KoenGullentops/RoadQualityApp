# Vendoring `fitsdk.bundle.js`

This is Garmin's official FIT JavaScript SDK (`@garmin/fitsdk` on npm),
bundled into a single non-module script so it works from a plain
`file://` open (ES module `<script type="module">` imports are blocked by
CORS when loaded from disk in Chromium-based browsers).

To rebuild after a version bump:

```sh
npm install @garmin/fitsdk esbuild --no-save --prefix /tmp/fitsdk-build
cat > /tmp/fitsdk-build/entry.js <<'EOF'
import { Decoder, Stream, Profile, Utils } from '@garmin/fitsdk';
window.FitSDK = { Decoder, Stream, Profile, Utils };
EOF
/tmp/fitsdk-build/node_modules/.bin/esbuild /tmp/fitsdk-build/entry.js \
  --bundle --minify --format=iife \
  --outfile=docs/vendor/fitsdk/fitsdk.bundle.js
```

Exposes a single global, `window.FitSDK`, with `Decoder`, `Stream`,
`Profile`, and `Utils` (same API as documented in the package's own
README on npm).
