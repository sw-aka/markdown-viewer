# Development

The native app lives in `MarkdownViewer/Sources`. Its WebKit renderer is in `renderer/src`, with generated output committed under `MarkdownViewer/Resources/Renderer`.

`project.yml` defines the Xcode project. Run `xcodegen generate` after adding Swift files or editing the specification, and include the regenerated project in the same change.

## Local checks

```sh
cd renderer
npm ci
npm test
npm run build
cd ..
xcodebuild -project MarkdownViewer.xcodeproj -scheme MarkdownViewer \
  -configuration Debug -derivedDataPath build/DerivedData build
```

Node.js 26 or later is required for renderer development. The app requires macOS 26 or later.

## Branches

Work is integrated into `dev`. Promotion to `main` is a separate, explicit release decision.

- Updates to `dev` produce **Development** prereleases.
- Updates to `main` produce **Stable** releases.
- Pull requests run validation without publishing a release.

Release and update configuration is described in [RELEASING.md](RELEASING.md).
