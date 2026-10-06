<p align="center" style="padding-top:20px"><img src="commet/assets/images/app_icon/source/vommet.svg" width="160" alt="Vommet logo: a face with gold star eyes throwing up a rainbow"></p>

<h1 align="center">Vommet</h1>
<p align="center"><strong>Commet, but with added slop™.</strong></p>
<p align="center"><em>A downstream, LLM-assisted fork of the <a href="https://github.com/commetchat/commet">Commet</a> Matrix client.</em></p>

**This is a fork. It is not Commet, and the Commet maintainers are not responsible for it.**

Vommet exists to iterate quickly on the papercuts that keep people on Discord and off
Matrix. Compatibility with the [Nether voice bridges](https://nether.codes/dark/nether-voicebridge)
is a priority. "Vommet" is a codename and will change before anything resembling a 1.0.

## Please read before filing anything

- **Most code here was written with the help of an LLM.** Commet's
  [contribution policy](https://github.com/commetchat/commet/blob/main/CONTRIBUTING.md)
  prohibits that, which we respect: nothing from this fork is ever submitted upstream,
  and we don't post LLM output in their spaces. If that policy matters to you, this fork
  is not for you — use Commet.
- **Bugs in this fork belong here**, in [this repo's issue tracker](https://nether.codes/robocub/vommet/issues),
  never in Commet's. If you are not sure whether a bug is ours or upstream's, file it here first.
- **This is a soft fork.** Our changes are a patch stack on top of Commet's `main`; the
  overwhelming majority of the code is theirs. Consider [donating to Commet](https://commet.chat/donate).

## What's different so far

In `main`:

- Its own identity: app id `im.nether.chat` (installs side by side with Commet), name and icons.
- Third-party requests (GIF search, sticker import) go through our own proxy,
  [vommet-proxy](https://nether.codes/robocub/vommet-proxy), never through Commet's servers.
- Update checks are off (Commet's update feed describes Commet, not us), and Android uses
  UnifiedPush only (no Firebase).

On the [`testing`](https://nether.codes/robocub/vommet/src/branch/testing) branch, waiting for hands-on testing:

- **Telegram sticker and custom-emoji import** — paste a `t.me/addstickers/…` link; animated
  Telegram stickers are converted to animated WebP by the proxy ([#2](https://nether.codes/robocub/vommet/issues/2)).
- **Picture mosaics** — several pictures posted together show as one Telegram-style grid
  ([#11](https://nether.codes/robocub/vommet/issues/11)).
- **Room banners** for ordinary rooms, not just spaces ([#6](https://nether.codes/robocub/vommet/issues/6)).
- **Search when adding existing rooms to a space** ([#10](https://nether.codes/robocub/vommet/issues/10)).
- **"Copy selection"** in the desktop message menu ([#9](https://nether.codes/robocub/vommet/issues/9)).
- **The Vommet name and logo** everywhere in the app.
- **Builds:** signed Android APKs and a Flatpak for testers.

## Plans

- **Voice isolation on par with Discord** — RNNoise-based noise suppression on desktop
  first ([#3](https://nether.codes/robocub/vommet/issues/3)).
- **Screen share with sound** on Linux and Windows ([#4](https://nether.codes/robocub/vommet/issues/4)).
- **Join voice calls in ordinary text rooms**, like Discord ([#8](https://nether.codes/robocub/vommet/issues/8)).
- **Sliding sync** for faster startup on big accounts ([#5](https://nether.codes/robocub/vommet/issues/5)).
- **Fix random startup crashes on Arch Linux** ([#7](https://nether.codes/robocub/vommet/issues/7)).
- **Copying part of a message on mobile** ([#9](https://nether.codes/robocub/vommet/issues/9)).
- **Easier installs:** a Flatpak repository with updates, and Windows builds.

Ideas and complaints welcome on the [issue tracker](https://nether.codes/robocub/vommet/issues).
The full list of differences from Commet is in [VOMMET_CHANGES.md](VOMMET_CHANGES.md).

## License

The app logo (`commet/assets/images/app_icon/source/vommet.svg`) is adapted from the
🤮 and 🤩 emoji of [Twemoji](https://github.com/jdecked/twemoji) 17.0.3, © Twitter, Inc.
and other contributors, licensed [CC-BY 4.0](https://creativecommons.org/licenses/by/4.0/).
Changes: star eyes from 🤩, a new open mouth, rainbow liquid with a splash, face shading.

AGPL-3.0, same as Commet. Copyright for the original code remains with the Commet authors; see
[LICENSE](LICENSE). Changes made in this fork are marked in git history.

---

<details><summary><b>Upstream README (Commet)</b> — kept for reference; links below point at Commet, not at this fork</summary>

<p align="center" style="padding-top:20px">
<img src="https://raw.githubusercontent.com/commetchat/.github/refs/heads/main/assets/banner.png">

<p align="center">
    <a href="https://commet.chat/donate"><img alt="Donate" src="https://img.shields.io/badge/donate-534cdd?style=for-the-badge"></a>
    <a href="https://commet.chat/install"><img alt="Download" src="https://img.shields.io/github/downloads/commetchat/commet/total?style=for-the-badge&color=534cdd"></a>
    <a href="https://matrix.to/#/#commet:matrix.org"><img alt="Matrix" src="https://img.shields.io/matrix/commet%3Amatrix.org?logo=matrix&style=for-the-badge&color=534cdd"></a>
    <a href="https://fosstodon.org/@commetchat"><img alt="Mastodon" src="https://img.shields.io/mastodon/follow/109894490854601533?domain=https%3A%2F%2Ffosstodon.org&style=for-the-badge&logo=mastodon&color=534cdd&logoColor=white"></a>
    <a href="https://bsky.app/profile/commet.chat"><img alt="Bluesky" src="https://img.shields.io/badge/follow-@commet.chat-whitesmoke?style=for-the-badge&logo=bluesky&logoColor=white&color=534cdd"></a>
</p>

### Your space to connect
We are building a client for [Matrix](https://matrix.org) focused on providing a feature rich experience while maintaining a simple interface. The goal is to build a secure, privacy respecting app without compromising on the features you have come to expect from a modern chat client.


<p align="center" style="padding-top:20px">
<img src="https://raw.githubusercontent.com/commetchat/.github/main/assets/banner_demo.png">

# Features
- Supports **Windows**, **Linux**, and **Android** (MacOS and iOS planned in future)
- End to End Encryption
- Custom Emoji + Stickers
- GIF Search
- Threads
- Encrypted Room Search
- Multiple Accounts
- Spaces
- Emoji verification & cross signing
- Push Notifications
- URL Preview
  

<details><summary><b>PGP Public Key to verify executables</b></summary>

```
-----BEGIN PGP PUBLIC KEY BLOCK-----

xiYEaVcZBRudW9w7efKKX9fRmwwQ8VSGeBDxPR/L1ZiorA99Ja93y80cQ29tbWV0
IDxjb250YWN0QGNvbW1ldC5jaGF0PsKCBBMbCAAuBQJpVxkFFiEEdJSx+k46noJT
sEiwnYIftF7A4aoCGwECHgEBCwEVARYBJwIZAQAKCRCdgh+0XsDhqiE1sVz/Q146
a/XQm2yeA+QJ4KuD+YY7j1zUl8gNZGJtl4LfvzMlEgrl9Tt8r6FP35mlRhKl+XSG
GwMpXUeHJwxvCM4mBGlXGQUbia8Ea3sb8PNFMjxgTF+gjCOBou6vMn8dCux6QEqs
fSDCwCcEGBsIAJMFAmlXGQUCGwIWIQR0lLH6TjqeglOwSLCdgh+0XsDhqnIgBBkb
CAAdBQJpVxkFFiEExdz0cdzyrZo8ihAhUfYeLD/fY80ACgkQUfYeLD/fY812w6BM
9avvCNSTmyogmsYLBpUb5XxaSe+3J6WhwBHyblaodZ2dlJg+npi1qRnMxvz+jTyQ
ctgmD24jtS2EbXlkCQkACgkQnYIftF7A4aqUviQ+fo2mEwweefVoqGuu2Tx/04B2
RY6FOKYsZL4qnEEO8lW7MoLXhVev8QHxmA6TQae8KZKbh8MXdCHW/cA3ZwjOOARp
VxkFEgorBgEEAZdVAQUBAQdAQatH56zW5TzNugWIsK1UGACqdQ/FCFcG/KT5LDiW
TDwDAQgHwnQEGBsIACAFAmlXGQUCGwwWIQR0lLH6TjqeglOwSLCdgh+0XsDhqgAK
CRCdgh+0XsDhqg1ipzJFtQCftqPRNvYPq96xFw3SAAE3CpAfHi+gwOk3BM7FmMxV
COa2WMfqY9EZxYWMwsbF6wZMdI2w3TLbo68MCc4zBGlXGQUWCSsGAQQB2kcPAQEH
QKcpVnktGVrHWHShUhp2Xb/nX6bQfy57gCe8zQ4Kzp0fwnQEGBsIACAFAmlXGQUC
GyAWIQR0lLH6TjqeglOwSLCdgh+0XsDhqgAKCRCdgh+0XsDhqkolM/gHzXSWM9t5
menzfZtegZnLPZ+n/zufzXdidzGa1K88juIrgoUjGZYJXnPHOJKm8qBXbLBscDkc
SHrEquc3Cw==
=wnah
-----END PGP PUBLIC KEY BLOCK-----
```
</details>

# Translation
Help translate to your language on [Weblate](https://hosted.weblate.org/projects/commetchat/commet/)

<a href="https://hosted.weblate.org/engage/commetchat/">
<img src="https://hosted.weblate.org/widget/commetchat/commet/multi-auto.svg" alt="Translation status" />
</a>

# Development
To build, you require [Flutter](https://flutter.dev), currently v3.41.9 

This repo currently has a monorepo structure, containing two flutter projects: Commet and Tiamat. Commet is the main client, and Tiamat is a sort of wrapper around Material with some extra goodies, which is used to maintain a consistent style across the app. Tiamat may eventually be moved to its own repo, but for now it is maintained here for ease of development.
## Building

### 1. [Install Flutter](https://docs.flutter.dev/get-started/install)

### 2. Install Libraries
Commet requires some additional libraries to be built 
```bash
sudo apt-get install -y cmake clang ninja-build rustup libgtk-3-dev libmpv-dev mpv ffmpeg libmimalloc-dev libwebkit2gtk-4.1-dev keybinder-3.0
```

### 3. Fetch Dependencies
You will need to change directory in to the project, then fetch dependencies
```bash
cd commet
flutter pub get
```

### 4. Code Generation
We make use of procedural code generation in some parts of the project. As a rule, generated code will not be checked in to git, and will need to be generated before building.

To run code generation, run the script within the `commet` directory:
`dart run scripts/codegen.dart`

### 5. Building
When building, there are some additional command line arguments that must be used to configure the build.

**Required**
| **Argument** | **Valid Values**                                                          | **Description**                                                                                              |
|--------------|---------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------|
| PLATFORM    | 'desktop', 'mobile', 'linux', 'windows', 'macos', 'android', 'ios', 'web' | Defines which platform to build for                                                                          |
| BUILD_MODE   | 'release', 'debug'                                                        | When building with 'debug' flag, additional debug information will be shown                                  |

**Optional**
| **Argument** | **Valid Values**                                                          | **Description**                                                                                              |
|--------------|---------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------|
| GIT_HASH     | *                                                                         | Supply the current git hash when building to show in info screen                                             |
| VERSION_TAG  | *                                                                         | Supply the current build version, to display app version                                                     |
| BUILD_DETAIL | *                                                                         | Can provide additional detail about the current build, for example if it was being built for Flatpak or Snap |

**Example:**

```bash
cd commet
flutter run --dart-define BUILD_MODE=debug --dart-define PLATFORM=linux
```

</details>

<p align="center">Made with ❤️ by Nether for Krayton</p>
