# Development and Stable releases

The public distribution repository is [`sw-aka/markdown-viewer`](https://github.com/sw-aka/markdown-viewer).

## Branch flow

- Integrate development work into `dev`.
- Every push to `dev`, including a merged pull request, validates the app and publishes a **Development** prerelease.
- Promote `dev` to `main` only when a Stable release is intended.
- Every push to `main` validates and publishes a **Stable** release, marked latest on GitHub.
- Pull requests validate changes without publishing or receiving the signing secret.
- The workflow never merges branches. Require pull requests and restrict direct pushes to `main` in repository rules if you want GitHub to enforce promotion reviews.

The initial public checkout contains only `dev`. Create and promote to `main` when you are ready for the first Stable release, then make `main` the default branch on GitHub. There is no automatic promotion.

## Versions

`RELEASE_SERIES` holds the numeric `major.minor` series. The workflow appends its monotonically increasing run number. For example, run 42 in series `0.1` produces:

| Branch | Display version | Tag | GitHub status |
| :--- | :--- | :--- | :--- |
| `dev` | `0.1.42` | `dev-0.1.42` | Development prerelease |
| `main` | `0.1.42` | `v0.1.42` | Stable release |

The build channel is also embedded in the app and shown in Settings. Both the bundle version and Sparkle feed use the same numeric version. Development users receive newer Development or Stable releases; Stable users receive only newer Stable releases. Switching channels never downgrades the app.

Each release contains a universal `arm64` + `x86_64` application ZIP and its `appcast.xml`. Failed validation or signature verification prevents publication. Existing releases and their assets are never overwritten. If a publication failed after the release was created, inspect the existing release before deciding how to recover it; do not replay it blindly.

## One-time GitHub setup

The committed `Config/UpdateSigning.xcconfig` contains the public Ed25519 verification key. **Do not replace it when creating builds.** Existing installations trust that key.

Configure an Actions repository secret named **`SPARKLE_PRIVATE_KEY`** with the matching base64-encoded private signing seed. Keep a secure backup of that seed. The private key is not part of the public repository. The release job fails explicitly until this secret is present.

No Apple Developer ID certificate is configured. Builds are ad-hoc signed and are not notarized. Initial downloaded installations may require approval through macOS Privacy & Security. Automatic updates are separately authenticated by Sparkle's Ed25519 archive signatures; they do not require the user to disable signature verification.

For a separate distribution with its own trust key, `swift scripts/create-update-key.swift` creates a private seed in the ignored `.private` directory and the matching public configuration. It refuses to overwrite existing keys. Do not use it to rotate an existing distribution's key casually.

The Sparkle dependency is pinned to version 2.10.0. `scripts/bootstrap-sparkle.sh` verifies the official archive's SHA-256 before extracting the framework and signing tools. The downloaded dependency stays out of Git.

## Local release build

```sh
scripts/build-release.sh development 42
```

Without a signing secret this produces a local ZIP, not a publishable update feed. In CI, the script signs the archive, verifies that signature against the public key embedded in the built app, and generates the matching feed. The publication script runs only inside GitHub Actions.

## In-app updates

The toolbar's circled up arrow opens a popover. If an update is already known, opening the popover shows that release without repeating the check. Otherwise it checks GitHub releases and shows the result. Settings controls the release channel and automatic checks on launch.

After **Update Now**, the toolbar and popover show download progress. Writing remains available during download and verification. Before installation, editing pauses briefly while a durable recovery snapshot is saved. If saving fails, installation stops.

The snapshot stores each open document's current text, original file URL, window frame, view mode, split, editor selection and scroll positions. Untitled documents and Scratch Pad text are included. The app does not save unsaved text over the original files to perform an update. On relaunch, it restores the windows and buffers; unavailable original files are restored as untitled documents. Editor undo history is not serialized across the restart.

Recovery data is stored locally in Application Support with owner-only permissions. It is removed after successful restoration. A failed installation restores document edited flags and removes the pending update snapshot. An unreadable recovery file is retained rather than discarded.

## Validation

```sh
python3 -m unittest discover -s tests -p 'test_*.py'
scripts/test-swift.sh
```

`tests/update_server.py` is a local signed-update fixture for Debug builds, including unavailable, error, cancelled-download and invalid-signature scenarios. Release builds ignore the test-server command-line option.
