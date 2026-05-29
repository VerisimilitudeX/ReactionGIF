// ReactionGIF backend proxy.
//
// Holds the API keys server-side so they never ship inside the iOS app.
// Endpoints:
//   POST /suggest  { imageBase64, vibe, safeMode } -> { read_back, options[] }
//   GET  /search?q=...&safe=true|false             -> [{ provider, gif, preview, title }]
//   POST /report   { gif }                          -> { ok: true }   (logs only)
//   GET  /                                          -> health check
//
// Requires Node 18+ (uses the built-in global fetch).

const express = require("express");

const app = express();
app.use(express.json({ limit: "12mb" }));

const OPENAI_API_KEY = process.env.OPENAI_API_KEY;
const TENOR_API_KEY = process.env.TENOR_API_KEY;
const GIPHY_API_KEY = process.env.GIPHY_API_KEY;
const OPENAI_MODEL = process.env.OPENAI_MODEL || "gpt-4o";
const TENOR_CLIENT_KEY = process.env.TENOR_CLIENT_KEY || "reactiongif_ios";
const RESULT_LIMIT = Number(process.env.RESULT_LIMIT || 10);

const VIBE_HINTS = {
  auto: "Read the room and pick whatever energy fits best.",
  wholesome: "Keep it warm, supportive, and feel-good.",
  unhinged: "Go chaotic, absurd, and over-the-top brainrot energy.",
  deadpan: "Be dry, sarcastic, and deadpan.",
  hype: "Be loud, celebratory, hype-man energy.",
  petty: "Be petty, shady, side-eye energy.",
};

app.get("/", (_req, res) => res.json({ ok: true, service: "reactiongif" }));

app.post("/suggest", async (req, res) => {
  try {
    const { imageBase64, vibe = "auto", safeMode = false } = req.body || {};
    if (!imageBase64) return res.status(400).json({ error: "imageBase64 is required" });
    if (!OPENAI_API_KEY) return res.status(500).json({ error: "OPENAI_API_KEY not configured" });

    const vibeHint = VIBE_HINTS[vibe] || VIBE_HINTS.auto;
    const safetyLine = safeMode
      ? "Keep everything strictly clean and family-friendly (G-rated)."
      : "Keep it PG-13: edgy is fine, nothing hateful, explicit, or cruel.";

    const systemPrompt = [
      "You are a Gen-Z humor expert who picks the perfect, well-timed reaction",
      "GIF/meme to drop into a group chat. You'll see a screenshot of a",
      "conversation. Work out the most recent message and the overall vibe, then",
      "decide what reaction would be the funniest and best-timed to send next.",
      "",
      `Desired energy for this one: ${vibeHint}`,
      safetyLine,
      "",
      "Respond ONLY with strict JSON in exactly this shape:",
      '{ "read_back": "<one short sentence>", "options": [',
      '  {"label": "<2-4 word name>", "search_query": "<1-4 word GIF search>", "why": "<one short sentence>"},',
      '  {"label": "...", "search_query": "...", "why": "..."} ] }',
      "",
      "Always return exactly 2 options that are meaningfully different.",
    ].join("\n");

    const response = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${OPENAI_API_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: OPENAI_MODEL,
        response_format: { type: "json_object" },
        messages: [
          { role: "system", content: systemPrompt },
          {
            role: "user",
            content: [
              { type: "text", text: "Here is the conversation. Pick the 2 best reactions to send next." },
              { type: "image_url", image_url: { url: `data:image/jpeg;base64,${imageBase64}` } },
            ],
          },
        ],
      }),
    });

    if (!response.ok) {
      const text = await response.text();
      return res.status(502).json({ error: `OpenAI: ${text}` });
    }

    const data = await response.json();
    const content = data?.choices?.[0]?.message?.content;
    if (!content) return res.status(502).json({ error: "Empty response from OpenAI" });

    return res.json(JSON.parse(content));
  } catch (err) {
    return res.status(500).json({ error: String(err) });
  }
});

app.get("/search", async (req, res) => {
  try {
    const query = String(req.query.q || "").trim();
    const safe = String(req.query.safe || "false") === "true";
    if (!query) return res.status(400).json({ error: "q is required" });

    const [tenor, giphy] = await Promise.all([
      searchTenor(query, safe),
      searchGiphy(query, safe),
    ]);

    // Interleave for variety across providers.
    const merged = [];
    const max = Math.max(tenor.length, giphy.length);
    for (let i = 0; i < max; i++) {
      if (i < tenor.length) merged.push(tenor[i]);
      if (i < giphy.length) merged.push(giphy[i]);
    }
    return res.json(merged);
  } catch (err) {
    return res.status(500).json({ error: String(err) });
  }
});

app.post("/report", (req, res) => {
  const gif = req.body?.gif;
  if (gif) console.log("[report] %s", gif);
  return res.json({ ok: true });
});

async function searchTenor(query, safe) {
  if (!TENOR_API_KEY) return [];
  const url = new URL("https://tenor.googleapis.com/v2/search");
  url.search = new URLSearchParams({
    q: query,
    key: TENOR_API_KEY,
    client_key: TENOR_CLIENT_KEY,
    limit: String(RESULT_LIMIT),
    media_filter: "gif,tinygif",
    contentfilter: safe ? "high" : "medium",
  }).toString();

  const resp = await fetch(url);
  if (!resp.ok) return [];
  const data = await resp.json();
  return (data.results || [])
    .map((item) => {
      const gif = item?.media_formats?.gif?.url;
      if (!gif) return null;
      return {
        provider: "Tenor",
        gif,
        preview: item?.media_formats?.tinygif?.url || null,
        title: item?.content_description || query,
      };
    })
    .filter(Boolean);
}

async function searchGiphy(query, safe) {
  if (!GIPHY_API_KEY) return [];
  const url = new URL("https://api.giphy.com/v1/gifs/search");
  url.search = new URLSearchParams({
    api_key: GIPHY_API_KEY,
    q: query,
    limit: String(RESULT_LIMIT),
    rating: safe ? "g" : "pg-13",
    bundle: "messaging_non_clips",
  }).toString();

  const resp = await fetch(url);
  if (!resp.ok) return [];
  const data = await resp.json();
  return (data.data || [])
    .map((item) => {
      const gif = item?.images?.original?.url;
      if (!gif) return null;
      return {
        provider: "Giphy",
        gif,
        preview: item?.images?.fixed_width_small?.url || null,
        title: item?.title || query,
      };
    })
    .filter(Boolean);
}

const port = process.env.PORT || 3000;
app.listen(port, () => console.log(`ReactionGIF backend listening on :${port}`));
