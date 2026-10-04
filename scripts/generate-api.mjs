import fs from 'node:fs/promises';
import {createHash} from 'node:crypto';
import openapiTS, {astToString} from 'openapi-typescript';
import YAML from 'yaml';
import {generateDart} from './dart-codegen.mjs';
const input = new URL('../openapi/pawday-m4.1.yaml',import.meta.url);
const source = (await fs.readFile(input,'utf8')).replaceAll('\r\n','\n');
const types = astToString(await openapiTS(input));
const target = new URL('../packages/api-client/src/generated/schema.ts',import.meta.url);
const output = `// Generated from pawday-m4.1.yaml; SHA256 ${createHash('sha256').update(source).digest('hex')}\n${types}`;
const dartTarget = new URL('../consumer-app/flutter/lib/api/generated/dto.dart',import.meta.url);
const dartOutput = generateDart(YAML.parse(source.toString()),createHash('sha256').update(source).digest('hex'));
if(process.argv.includes('--check')) {
  if(await fs.readFile(target,'utf8')!==output) throw new Error('Generated API types drifted. Run pnpm generate.');
  if(await fs.readFile(dartTarget,'utf8')!==dartOutput) throw new Error('Generated Dart DTO/client routes drifted. Run pnpm generate.');
  console.log('OpenAPI regeneration consistency PASS');
} else { await fs.mkdir(new URL('.',target),{recursive:true});await fs.writeFile(target,output);await fs.mkdir(new URL('.',dartTarget),{recursive:true});await fs.writeFile(dartTarget,dartOutput); }
