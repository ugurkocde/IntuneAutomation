export interface ScriptParameter {
  name: string;
  type: string;
  mandatory: boolean;
  default?: string;
  switch: boolean;
}

export interface ScriptMeta {
  id: string;
  title: string;
  synopsis: string;
  description: string;
  category: string;
  categoryLabel: string;
  tags: string[];
  permissions: string[];
  minRole: string;
  platform: string;
  author: string;
  version: string;
  lastUpdate: string;
  schedule: string;
  execution: string;
  output: string;
  remediationType: string;
  pairScript: string;
  parameters: ScriptParameter[];
  examples: string[];
  notes: string;
  path: string;
  rawUrl: string;
  githubUrl: string;
}

export interface ScriptIndex {
  repository: string;
  branch: string;
  generated: string;
  count: number;
  categories: string[];
  scripts: ScriptMeta[];
}
