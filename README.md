# Wanderly

> A quiet place for unfinished ideas.

Wanderly helps you capture a thought before it disappears, then lets an AI ask a few useful questions when you have time. An idea can slowly move from a fragment to an **Abstract** or a **Proposal**. Dreaming is intentionally secondary: it connects distant fragments into new combinations without turning the product into another productivity dashboard.

## Product principles

- Capture must take seconds.
- The AI asks, it does not write over the user's thinking.
- Questions should expose missing context, not create busywork.
- An idea can stay ambiguous until the user is ready.
- Local-first by default; no API key belongs in the browser.

## Current MVP

- Dashboard with a low-friction capture box
- Idea garden with seed / growing / bloom states
- Wandering fragments and one-click promotion to an Idea
- Dreaming space for connecting fragments
- Local persistence with `localStorage`
- User-input escaping to prevent HTML injection

Open `index.html` directly to try the UI. The current UI uses seeded local data and is intentionally dependency-free.

## AI integration direction

The product should use an application-owned `/api/ai` proxy, not call model providers directly from the browser. The proxy can route to OpenAI, Anthropic, Google, Azure OpenAI, Ollama, or any OpenAI-compatible endpoint.

The client contract is deliberately small:

```json
{
  "mode": "ask_questions",
  "idea": { "title": "...", "body": "...", "stage": "seed" },
  "answers": []
}
```

The response should return 1–3 questions plus an optional stage recommendation. See `src/llm.js` for the provider-neutral contract and `CLAUDE.md` for the refinement skill draft.

## Contributing

Start with a small issue. Good contributions include better question quality, import/export, a local model adapter, accessibility fixes, and experiments for Dreaming. Please read [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT. See [LICENSE](LICENSE).
