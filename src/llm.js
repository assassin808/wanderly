/**
 * Provider-neutral client contract for Wanderly.
 *
 * The browser should call an application-owned /api/ai proxy. The proxy owns
 * provider credentials and can route to OpenAI, Anthropic, Google, Azure,
 * Ollama, or an OpenAI-compatible deployment.
 */
export async function askRefinementQuestions({ idea, answers = [], signal } = {}) {
  if (!idea?.body && !idea?.title) throw new Error('An idea is required');
  const response = await fetch('/api/ai', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    signal,
    body: JSON.stringify({ mode: 'ask_questions', idea, answers })
  });
  if (!response.ok) throw new Error(`AI request failed (${response.status})`);
  return response.json();
}

export async function draftArtifact({ idea, answers = [], format = 'abstract', signal } = {}) {
  const response = await fetch('/api/ai', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    signal,
    body: JSON.stringify({ mode: 'draft_artifact', format, idea, answers })
  });
  if (!response.ok) throw new Error(`AI request failed (${response.status})`);
  return response.json();
}
