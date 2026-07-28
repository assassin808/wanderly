const CONFIG_KEY = 'wanderly-llm-config-v1';

export const PROVIDERS = {
  openai: { label: 'OpenAI', model: 'gpt-4o-mini', baseUrl: 'https://api.openai.com/v1/chat/completions' },
  claude: { label: 'Claude', model: 'claude-3-5-sonnet-latest', baseUrl: 'https://api.anthropic.com/v1/messages' },
  gemini: { label: 'Gemini', model: 'gemini-2.0-flash', baseUrl: 'https://generativelanguage.googleapis.com/v1beta/models' },
  openrouter: { label: 'OpenRouter', model: 'openai/gpt-4o-mini', baseUrl: 'https://openrouter.ai/api/v1/chat/completions' }
};

export function getLLMConfig() {
  try { return JSON.parse(localStorage.getItem(CONFIG_KEY) || 'null'); } catch { return null; }
}

export function saveLLMConfig(config) {
  const provider = PROVIDERS[config.provider] ? config.provider : 'openai';
  const next = { provider, model: config.model || PROVIDERS[provider].model, apiKey: config.apiKey || '', baseUrl: config.baseUrl || PROVIDERS[provider].baseUrl };
  localStorage.setItem(CONFIG_KEY, JSON.stringify(next));
  return next;
}

function headersFor(provider, apiKey) {
  if (provider === 'claude') return { 'content-type': 'application/json', 'x-api-key': apiKey, 'anthropic-version': '2023-06-01', 'anthropic-dangerous-direct-browser-access': 'true' };
  return { 'content-type': 'application/json', authorization: `Bearer ${apiKey}` };
}

async function complete({ config, system, user, signal }) {
  if (!config?.apiKey) throw new Error('请先在 AI 设置中填写 API Key');
  const provider = config.provider;
  let url = config.baseUrl || PROVIDERS[provider].baseUrl;
  let body;
  if (provider === 'gemini') {
    url = `${url}/${encodeURIComponent(config.model)}:generateContent?key=${encodeURIComponent(config.apiKey)}`;
    body = { systemInstruction: { parts: [{ text: system }] }, contents: [{ role: 'user', parts: [{ text: user }] }] };
  } else if (provider === 'claude') {
    body = { model: config.model, max_tokens: 700, system, messages: [{ role: 'user', content: user }] };
  } else {
    body = { model: config.model, temperature: 0.4, messages: [{ role: 'system', content: system }, { role: 'user', content: user }] };
  }
  const response = await fetch(url, { method: 'POST', headers: headersFor(provider, config.apiKey), body: JSON.stringify(body), signal });
  if (!response.ok) throw new Error(`AI 请求失败 (${response.status})`);
  const json = await response.json();
  if (provider === 'gemini') return json.candidates?.[0]?.content?.parts?.[0]?.text || '';
  if (provider === 'claude') return json.content?.[0]?.text || '';
  return json.choices?.[0]?.message?.content || '';
}

export async function askRefinementQuestions({ idea, answers = [], signal } = {}) {
  const config = getLLMConfig();
  const text = await complete({ config, signal,
    system: '你是 Wanderly 的温和追问者。只问问题，不替用户定义想法。返回严格 JSON：{"questions":["..."]}，最多 3 个问题。问题要具体、异步可回答，帮助补齐对象、问题、约束或最小实验。',
    user: JSON.stringify({ idea, answers })
  });
  const cleaned = text.replace(/^```json\s*|\s*```$/g, '').trim();
  try { return JSON.parse(cleaned); } catch { return { questions: [text] }; }
}

export async function draftArtifact({ idea, answers = [], format = 'abstract', signal } = {}) {
  const config = getLLMConfig();
  const text = await complete({ config, signal,
    system: `把用户的想法整理为 ${format === 'proposal' ? 'Proposal' : 'Abstract'}。保留不确定性，不要编造事实。返回纯文本。`,
    user: JSON.stringify({ idea, answers })
  });
  return { text };
}
