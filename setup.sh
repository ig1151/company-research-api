#!/bin/bash
set -e

echo "🚀 Setting up Company Research API..."

mkdir -p src/routes src/research

cat > package.json << 'ENDPACKAGE'
{
  "name": "company-research-api",
  "version": "1.0.0",
  "description": "AI-powered company research API — returns summary, key people, recent news, tech stack and competitive intelligence in one call.",
  "main": "dist/index.js",
  "scripts": {
    "build": "tsc",
    "dev": "ts-node-dev --respawn --transpile-only src/index.ts",
    "start": "node dist/index.js"
  },
  "dependencies": {
    "axios": "^1.6.0",
    "cheerio": "^1.0.0",
    "compression": "^1.7.4",
    "cors": "^2.8.5",
    "dotenv": "^16.0.0",
    "express": "^4.18.2",
    "express-rate-limit": "^7.1.5",
    "helmet": "^7.1.0",
    "joi": "^17.11.0"
  },
  "devDependencies": {
    "@types/compression": "^1.7.5",
    "@types/cors": "^2.8.17",
    "@types/express": "^4.17.21",
    "@types/node": "^20.10.0",
    "ts-node-dev": "^2.0.0",
    "typescript": "^5.3.2"
  }
}
ENDPACKAGE

cat > tsconfig.json << 'ENDTSCONFIG'
{
  "compilerOptions": {
    "target": "ES2020",
    "module": "commonjs",
    "lib": ["ES2020"],
    "outDir": "./dist",
    "rootDir": "./src",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "resolveJsonModule": true
  },
  "include": ["src/**/*"],
  "exclude": ["node_modules", "dist"]
}
ENDTSCONFIG

cat > render.yaml << 'ENDRENDER'
services:
  - type: web
    name: company-research-api
    env: node
    buildCommand: npm install && npm run build
    startCommand: node dist/index.js
    healthCheckPath: /v1/health
    envVars:
      - key: NODE_ENV
        value: production
      - key: PORT
        value: 10000
      - key: ANTHROPIC_API_KEY
        sync: false
      - key: TAVILY_API_KEY
        sync: false
ENDRENDER

cat > .gitignore << 'ENDGITIGNORE'
node_modules/
dist/
.env
*.log
ENDGITIGNORE

cat > src/logger.ts << 'ENDLOGGER'
export const logger = {
  info: (obj: unknown, msg?: string) =>
    console.log(JSON.stringify({ level: 'info', ...(typeof obj === 'object' ? obj : { data: obj }), msg })),
  warn: (obj: unknown, msg?: string) =>
    console.warn(JSON.stringify({ level: 'warn', ...(typeof obj === 'object' ? obj : { data: obj }), msg })),
  error: (obj: unknown, msg?: string) =>
    console.error(JSON.stringify({ level: 'error', ...(typeof obj === 'object' ? obj : { data: obj }), msg })),
};
ENDLOGGER

cat > src/research/search.ts << 'ENDSEARCH'
import axios from 'axios';

export async function tavilySearch(query: string, maxResults = 5): Promise<Array<{ title: string; url: string; content: string }>> {
  const apiKey = process.env.TAVILY_API_KEY;
  if (!apiKey) throw new Error('TAVILY_API_KEY not set');

  const res = await axios.post(
    'https://api.tavily.com/search',
    { query, max_results: maxResults, search_depth: 'basic', include_raw_content: false },
    {
      headers: { 'Authorization': `Bearer ${apiKey}`, 'Content-Type': 'application/json' },
      timeout: 15000,
    }
  );

  return (res.data.results ?? []).map((r: { title: string; url: string; content?: string }) => ({
    title: r.title,
    url: r.url,
    content: r.content ?? '',
  }));
}
ENDSEARCH

cat > src/research/claude.ts << 'ENDCLAUDE'
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
ENDCLAUDE

cat > src/research/runner.ts << 'ENDRUNNER'
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
ENDRUNNER

cat > src/routes/research.ts << 'ENDRESEARCH'
import { Router, Request, Response } from 'express';
import Joi from 'joi';
import { researchCompany } from '../research/runner';
import { logger } from '../logger';

const router = Router();

const schema = Joi.object({
  company: Joi.string().min(1).max(200).required(),
  focus: Joi.string().max(200).optional(),
});

router.post('/research/company', async (req: Request, res: Response) => {
  const { error, value } = schema.validate(req.body);
  if (error) {
    res.status(400).json({ error: 'Validation failed', details: error.details[0].message });
    return;
  }

  logger.info({ company: value.company }, 'Company research started');

  try {
    const result = await researchCompany(value.company, value.focus);
    logger.info({ company: value.company, latency_ms: result.latency_ms }, 'Company research complete');
    res.json(result);
  } catch (err) {
    const message = err instanceof Error ? err.message : 'Research failed';
    logger.error({ company: value.company, err }, 'Research failed');
    res.status(500).json({ error: 'Research failed', details: message });
  }
});

export default router;
ENDRESEARCH

cat > src/routes/docs.ts << 'ENDDOCS'
import { Router, Request, Response } from 'express';
const router = Router();

router.get('/', (_req: Request, res: Response) => {
  res.send(`<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1.0"/>
  <title>Company Research API</title>
  <style>
    body { font-family: system-ui, sans-serif; max-width: 860px; margin: 40px auto; padding: 0 20px; background: #0f0f0f; color: #e0e0e0; }
    h1 { color: #7c3aed; } h2 { color: #a78bfa; border-bottom: 1px solid #333; padding-bottom: 8px; }
    pre { background: #1a1a1a; padding: 16px; border-radius: 8px; overflow-x: auto; font-size: 13px; }
    code { color: #c084fc; }
    .badge { display: inline-block; padding: 2px 10px; border-radius: 12px; font-size: 12px; margin-right: 8px; color: white; }
    .post { background: #7c3aed; } .get { background: #065f46; }
    table { width: 100%; border-collapse: collapse; } td, th { padding: 8px 12px; border: 1px solid #333; text-align: left; }
    th { background: #1a1a1a; }
  </style>
</head>
<body>
  <h1>Company Research API</h1>
  <p>AI-powered company research — summary, key people, recent news, tech stack and competitive intelligence in one call.</p>
  <h2>Endpoints</h2>
  <table>
    <tr><th>Method</th><th>Path</th><th>Description</th></tr>
    <tr><td><span class="badge post">POST</span></td><td>/v1/research/company</td><td>Research any company</td></tr>
    <tr><td><span class="badge get">GET</span></td><td>/v1/health</td><td>Health check</td></tr>
  </table>
  <h2>Example</h2>
  <pre>POST /v1/research/company
{
  "company": "Stripe",
  "focus": "payments and competitive landscape"
}</pre>
  <p><a href="/openapi.json" style="color:#a78bfa">OpenAPI JSON</a></p>
</body>
</html>`);
});

export default router;
ENDDOCS

cat > src/routes/openapi.ts << 'ENDOPENAPI'
import { Router, Request, Response } from 'express';
const router = Router();

router.get('/', (_req: Request, res: Response) => {
  res.json({
    openapi: '3.0.0',
    info: {
      title: 'Company Research API',
      version: '1.0.0',
      description: 'AI-powered company research — summary, key people, recent news, tech stack and competitive intelligence in one call.',
    },
    servers: [{ url: 'https://company-research-api.onrender.com' }],
    paths: {
      '/v1/research/company': {
        post: {
          summary: 'Research any company',
          requestBody: {
            required: true,
            content: {
              'application/json': {
                schema: {
                  type: 'object',
                  required: ['company'],
                  properties: {
                    company: { type: 'string' },
                    focus: { type: 'string' },
                  },
                },
              },
            },
          },
          responses: { '200': { description: 'Company research result' } },
        },
      },
      '/v1/health': {
        get: { summary: 'Health check', responses: { '200': { description: 'OK' } } },
      },
    },
  });
});

export default router;
ENDOPENAPI

cat > src/index.ts << 'ENDINDEX'
import 'dotenv/config';
import express from 'express';
import helmet from 'helmet';
import cors from 'cors';
import compression from 'compression';
import rateLimit from 'express-rate-limit';
import { logger } from './logger';
import researchRouter from './routes/research';
import docsRouter from './routes/docs';
import openapiRouter from './routes/openapi';

const app = express();
const PORT = process.env.PORT || 3000;

app.use(helmet());
app.use(cors());
app.use(compression());
app.use(express.json());
app.use(rateLimit({ windowMs: 60_000, max: 30, standardHeaders: true, legacyHeaders: false }));

app.get('/', (_req, res) => {
  res.json({
    service: 'company-research-api',
    version: '1.0.0',
    description: 'AI-powered company research API.',
    status: 'ok',
    docs: '/docs',
    health: '/v1/health',
    endpoints: {
      research_company: 'POST /v1/research/company',
    },
  });
});

app.get('/v1/health', (_req, res) => {
  res.json({ status: 'ok', service: 'company-research-api', timestamp: new Date().toISOString() });
});

app.use('/v1', researchRouter);
app.use('/docs', docsRouter);
app.use('/openapi.json', openapiRouter);

app.use((req, res) => {
  res.status(404).json({ error: 'Not found', path: req.path });
});

app.listen(PORT, () => {
  logger.info({ port: PORT }, 'Company Research API running');
});
ENDINDEX

echo "✅ All files created!"
echo "Next: npm install && npm run dev"