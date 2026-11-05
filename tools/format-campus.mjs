import ts from '../backend/node_modules/typescript/lib/typescript.js';
import {readdir,readFile,writeFile} from 'node:fs/promises';
import {resolve} from 'node:path';
const root=resolve(import.meta.dirname,'..');
const files=(await readdir(resolve(root,'backend/src'))).filter(n=>n.endsWith('.ts')).map(n=>resolve(root,'backend/src',n));
for(const name of ['server.ts','local.ts','migrate.ts','seed.ts','test/campus.test.ts'])files.push(resolve(root,'backend',name));
for(const file of files){const source=ts.createSourceFile(file,await readFile(file,'utf8'),ts.ScriptTarget.Latest,true,ts.ScriptKind.TS);if(source.parseDiagnostics.length)throw Error('Syntax errors: '+file);await writeFile(file,ts.createPrinter({newLine:ts.NewLineKind.LineFeed}).printFile(source));}
console.log(`Formatted ${files.length} Smart Campus TypeScript files.`);
