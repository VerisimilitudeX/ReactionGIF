# ReactionGIF

An iOS app that finds the perfect, well-timed reaction GIF for a group chat.

Screenshot a conversation → the app reads it with OpenAI's vision model, figures
out what would land, then searches **both Tenor and Giphy** and shows you **two**
reactions you can send in one tap.

## Features

- **Reads the room.** The AI understands the conversation, not just keywords.
- **Vibe selector.** Auto / Wholesome / Unhinged / Deadpan / Hype / Petty steer
  the humor (`Models/Vibe.swift`).
- **Two picks, with shuffle.** Cycle to alternatives instantly — no extra API calls.
- **Copy / share** any GIF straight into iMessage, WhatsApp, etc.
- **Paste from clipboard** for one-tap input.
- **Recents** strip to re-grab a go-to GIF.
- **Safe Mode** forces G-rated results; **Report** permanently hides a GIF.
- **Backend mode** keeps all API keys off-device (see `Backend/`).

## How it works

1. **Capture** – Pick a screenshot, take a photo, or paste from the clipboard
   (`ContentView`, `Views/ImagePicker.swift`).
2. **Read** – The image goes to OpenAI's vision model, which returns a short
   read-back plus two distinct "bits", each with a GIF search query and a reason
   it lands (`OpenAIService` → `ReactionSuggestion`).
3. **Search** – Each query is run against Tenor and Giphy in parallel and merged
   (`GifProviders` → `GifCandidate`).
4. **Show** – Each bit becomes a shuffleable `ReactionCard` with share / copy /
   report (`ReactionEngine`, `GifCardView`, `AnimatedGIFView`).

## Setup

Requires Xcode 16+ (the project uses a file-system–synchronized group, so new
files in `ReactionGIF/` are picked up automatically).

### Recommended: backend mode (no keys in the app)

1. Deploy the proxy in `Backend/` (see `Backend/README.md`).
2. Set `AppConfig.backendBaseURL` in `ReactionGIF/Secrets.swift` to its URL.
3. Open `ReactionGIF.xcodeproj`, set your signing team, run.

### Quick start: direct mode (development only)

1. Open `ReactionGIF.xcodeproj`.
2. Get free API keys: [OpenAI](https://platform.openai.com/api-keys),
   [Tenor](https://developers.google.com/tenor/guides/quickstart),
   [Giphy](https://developers.giphy.com/dashboard/).
3. Paste them into `ReactionGIF/Secrets.swift` (leave `backendBaseURL` empty).
4. Set your signing team and run.

## Project layout

```
ReactionGIF/
  ReactionGIFApp.swift        App entry point
  ContentView.swift           Main screen: capture → vibe → results → recents
  Secrets.swift               Keys, backend URL, model + content config
  PrivacyInfo.xcprivacy       Privacy manifest
  Models/
    ReactionSuggestion.swift  Structured AI output
    GifCandidate.swift        A single GIF from a provider
    ReactionCard.swift        A shuffleable on-screen reaction
    Vibe.swift                Humor presets
  Services/
    OpenAIService.swift       Vision call (direct or via backend)
    GifProviders.swift        Tenor + Giphy search (direct or via backend)
    ReactionEngine.swift      Orchestration + shuffle + report
    ReportStore.swift         Remembers reported GIFs
    RecentsStore.swift        Recent reactions
    GifActions.swift          Clipboard copy + haptics
  Views/
    ImagePicker.swift         Library + camera pickers
    AnimatedGIFView.swift     GIF playback via ImageIO
    GifCardView.swift         Result card: share/copy/shuffle/report
    PrivacyDisclosureView.swift  First-run data disclosure
Backend/                      Node/Express key-holding proxy
PRIVACY.md                    Privacy policy (host it, link in-app)
LISTING.md                    App Store listing copy
```

## App Store submission checklist

Done in this repo:

- [x] 1024×1024 app icon, no alpha — `Assets.xcassets/AppIcon.appiconset/AppIcon.png`
- [x] Camera + photo-library usage strings
- [x] Privacy manifest (`PrivacyInfo.xcprivacy`) + first-run disclosure (`PrivacyDisclosureView`)
- [x] Export-compliance flag (`ITSAppUsesNonExemptEncryption = NO`)
- [x] UGC safeguards (Guideline 1.2): content filtering, Safe Mode, **Report this GIF**
- [x] Keys-off-device option via `Backend/` proxy (Guideline-friendly + secure)
- [x] Privacy policy text (`PRIVACY.md`) and listing copy (`LISTING.md`)
- [x] Auto-generated launch screen

Up to you (account-specific, can't be done from code):

- [ ] Deploy `Backend/` and set `backendBaseURL`
- [ ] Host `PRIVACY.md` and set `AppConfig.privacyPolicyURL` + the App Store Connect field
- [ ] Set bundle ID + signing team (placeholder `com.reactiongif.app`)
- [ ] App Store Connect listing + screenshots (6.7" + 6.5") + age-rating questionnaire
