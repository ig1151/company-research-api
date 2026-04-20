import { tavilySearch } from './search';
import { claudeResearch } from './claude';

export interface CompanyResearchResult {
  company: string;
  domain?: string;
  summary: string;
  industry: string;
  founded?: string;
  headquarters?: string;
  size?: string;
  key_people: Array<{ name: string; role: string }>;
  products: string[];
  recent_news: Array<{ title: string; url: string; summary: string }>;
  tech_stack: string[];
  competitors: string[];
  strengths: string[];
  weaknesses: string[];
  sources: string[];
  latency_ms: number;
  timestamp: string;
}

export async function researchCompany(company: string, focus?: string): Promise<CompanyResearchResult> {
  const start = Date.now();

  const focusNote = focus ? ` Focus on: ${focus}.` : '';

  // Run searches in parallel
  const [generalResults, newsResults, peopleResults] = await Promise.all([
    tavilySearch(`${company} company overview products industry`, 5),
    tavilySearch(`${company} company news 2024 2025`, 3),
    tavilySearch(`${company} CEO founder leadership team key people`, 3),
  ]);

  const allContent = [
    ...generalResults.map(r => `${r.title}: ${r.content}`),
    ...newsResults.map(r => `${r.title}: ${r.content}`),
    ...peopleResults.map(r => `${r.title}: ${r.content}`),
  ].join('\n\n').slice(0, 12000);

  const sources = [...new Set([
    ...generalResults.map(r => r.url),
    ...newsResults.map(r => r.url),
  ])].slice(0, 8);

  const prompt = `You are a business intelligence analyst. Research ${company} based on the following web content.${focusNote}

Return ONLY a valid JSON object with exactly these fields:
{
  "summary": "2-3 sentence company overview",
  "industry": "primary industry",
  "founded": "year founded or null",
  "headquarters": "city, country or null",
  "size": "employee count range or null",
  "key_people": [{"name": "string", "role": "string"}],
  "products": ["product or service name"],
  "recent_news": [{"title": "string", "url": "string", "summary": "one sentence"}],
  "tech_stack": ["technology name"],
  "competitors": ["competitor name"],
  "strengths": ["strength"],
  "weaknesses": ["weakness"]
}

Rules:
- key_people: up to 5 people
- products: up to 8 items
- recent_news: up to 3 items
- tech_stack: up to 8 items
- competitors: up to 6 items
- strengths: up to 5 items
- weaknesses: up to 4 items
- Return only JSON, no markdown

Web content:
${allContent}`;

  const raw = await claudeResearch(prompt);

  let parsed: Partial<CompanyResearchResult> = {};
  try {
    parsed = JSON.parse(raw.replace(/```json|```/g, '').trim());
  } catch {
    parsed = { summary: raw.slice(0, 300) };
  }

  // Extract domain from search results
  const domain = generalResults[0]?.url
    ? new URL(generalResults[0].url).hostname.replace('www.', '')
    : undefined;

  return {
    company,
    domain,
    summary: parsed.summary ?? `${company} is a company.`,
    industry: parsed.industry ?? 'unknown',
    founded: parsed.founded,
    headquarters: parsed.headquarters,
    size: parsed.size,
    key_people: parsed.key_people ?? [],
    products: parsed.products ?? [],
    recent_news: (parsed.recent_news ?? []).map((n: { title: string; url?: string; summary: string }, i: number) => ({
      ...n,
      url: n.url ?? newsResults[i]?.url ?? '',
    })),
    tech_stack: parsed.tech_stack ?? [],
    competitors: parsed.competitors ?? [],
    strengths: parsed.strengths ?? [],
    weaknesses: parsed.weaknesses ?? [],
    sources,
    latency_ms: Date.now() - start,
    timestamp: new Date().toISOString(),
  };
}
