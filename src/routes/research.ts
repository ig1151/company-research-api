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
