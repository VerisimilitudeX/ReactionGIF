# ReactionGIF backend proxy

A tiny Express server that holds your OpenAI, Tenor, and Giphy keys so they never
ship inside the iOS app. Deploy it, then set `AppConfig.backendBaseURL` in the app
to its URL — the app will route everything through it and carry **no** keys.

## Run locally

```bash
cd Backend
npm install
cp .env.example .env   # then fill in your keys
npm start              # http://localhost:3000
```

## Deploy (any Node 18+ host)

Works as-is on Railway, Render, Fly.io, Heroku, etc. Set the environment
variables from `.env.example` in the host's dashboard and use `npm start` as the
start command. Then in the iOS app:

```swift
// Secrets.swift
static let backendBaseURL = "https://your-deployment-url"
```

## Endpoints

| Method | Path       | Body / query                          | Returns                                        |
|--------|------------|---------------------------------------|------------------------------------------------|
| GET    | `/`        | —                                     | `{ ok: true }`                                 |
| POST   | `/suggest` | `{ imageBase64, vibe, safeMode }`     | `{ read_back, options: [...] }`                |
| GET    | `/search`  | `?q=...&safe=true|false`              | `[{ provider, gif, preview, title }]`          |
| POST   | `/report`  | `{ gif }`                             | `{ ok: true }` (logs the URL)                  |

For production you'll likely want to add rate limiting and restrict CORS/origins.
