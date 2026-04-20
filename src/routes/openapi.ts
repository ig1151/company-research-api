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
