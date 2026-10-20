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

Configure the public repository's **`release` environment** before publishing:

1. Open Settings > Environments > New environment, name it `release`, and configure it.
2. Under Deployment branches and tags, choose Selected branches and tags. Add two Branch rules, exactly `dev` and `main`.
3. To approve each release yourself, enable Required reviewers, select your account and save. Leave Prevent self-review unchecked if you will approve runs you trigger. With this option enabled, Development and Stable releases both wait for approval after validation; ordinary build checks remain automatic.
4. Under Environment secrets, add **`SPARKLE_PRIVATE_KEY`** with the matching base64-encoded private signing seed. Keep a separate secure backup. The private key is not part of the repository.
5. If you previously stored the same key as a repository secret, remove that repository-level copy once the environment copy is in place, so other jobs cannot obtain it through repository scope.

The release job targets this environment and waits for any configured protection rules before accessing its secrets. Configure the environment explicitly; the workflow declaration alone does not create protection rules. Missing signing credentials stop publication.

No Apple Developer ID certificate is configured. Builds are ad-hoc signed and are not notarized. Initial downloaded installations may require approval through macOS Privacy & Security. Automatic updates are separately authenticated by Sparkle's Ed25519 archive signatures; they do not require the user to disable signature verification.

For a separate distribution with its own trust key, `swift scripts/create-update-key.swift` creates a private seed in the ignored `.private` directory and the matching public configuration. It refuses to overwrite existing keys. Do not use it to rotate an existing distribution's key casually.

The Sparkle dependency is pinned to version 2.10.0. `scripts/bootstrap-sparkle.sh` verifies the official archive's SHA-256 before extracting the framework and signing tools. The downloaded dependency stays out of Git.

## Local release build

```sh
scripts/build-release.sh development 42
```

Without a signing secret this produces a local ZIP, not a publishable update feed. In CI, the script signs the archive, verifies that signature against the public key embedded in the built app, and generates the matching feed. The publication script runs only inside GitHub Actions.

## In-app updates

The update control appears in the toolbar only when an update is available or a download is in progress or ready to install. It opens a popover with the current update state. **Markdown Viewer → Check for Updates…**, and the equivalent Settings button, open a Software Update window with checking progress and results, even when no document is open. Known updates and pending downloads are shown without repeating the check. Settings controls the release channel and automatic checks on launch.

After **Download Update**, the toolbar and popover show download progress. Writing remains available during download and verification. After verification the update waits at **Ready to install**, with editing still available. Only **Install and Restart** begins the restart: editing pauses briefly while a durable recovery snapshot captures the latest buffers. If saving fails, installation stops.

The snapshot stores each open document's current text, original file URL, window frame, view mode, split, editor selection and scroll positions. Untitled documents and Scratch Pad text are included. The app does not save unsaved text over the original files to perform an update. On relaunch, it restores the windows and buffers; unavailable original files are restored as untitled documents. Editor undo history is not serialized across the restart.

Recovery data is stored locally in Application Support with owner-only permissions. It is removed after successful restoration. A failed installation restores document edited flags and removes the pending update snapshot. An unreadable recovery file is retained rather than discarded.

## Validation

```sh
python3 -m unittest discover -s tests -p 'test_*.py'
scripts/test-swift.sh
```

`tests/update_server.py` is a local signed-update fixture for Debug builds, including unavailable, error, cancelled-download and invalid-signature scenarios. Release builds ignore the test-server command-line option.
