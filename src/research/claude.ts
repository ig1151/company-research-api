import axios from 'axios';

const ANTHROPIC_API = 'https://api.anthropic.com/v1/messages';

export async function claudeResearch(prompt: string): Promise<string> {
  const apiKey = process.env.ANTHROPIC_API_KEY;
  if (!apiKey) throw new Error('ANTHROPIC_API_KEY not set');

  const res = await axios.post(
    ANTHROPIC_API,
    {
      model: 'claude-sonnet-4-20250514',
      max_tokens: 1500,
      messages: [{ role: 'user', content: prompt }],
    },
    {
      headers: {
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
        'content-type': 'application/json',
      },
      timeout: 30000,
    }
  );

  return res.data.content[0]?.text ?? '';
}
