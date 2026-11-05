import {randomBytes} from 'node:crypto';
import {mkdir,writeFile} from 'node:fs/promises';
import {resolve} from 'node:path';
const root=resolve(import.meta.dirname,'..');
const secret=()=>randomBytes(32).toString('base64url');
const owner=secret(),runtime=secret(),password=secret(),pin=String(100000+randomBytes(4).readUInt32BE()%900000),device=secret();
const env=`DEPLOY_ENV=campus-local
POSTGRES_PASSWORD=${owner}
RUNTIME_DATABASE_PASSWORD=${runtime}
DATABASE_URL=postgresql://smartcampus_app:${runtime}@db:5432/smartcampus
MIGRATION_DATABASE_URL=postgresql://schema_owner:${owner}@db:5432/smartcampus
CARD_HMAC_SECRET=${secret()}
MOCK_CALLBACK_SECRET=${secret()}
SEED_PASSWORD=${password}
SEED_PIN=${pin}
SEED_DEVICE_TOKEN=${device}
APP_DOMAIN=localhost
PUBLIC_ORIGIN=http://localhost:8080
`;
await mkdir(resolve(root,'.work'),{recursive:true});
await writeFile(resolve(root,'deploy/.env'),env,{flag:'wx',mode:0o600});
await writeFile(resolve(root,'.work/compose-access.txt'),`LOCAL COMPOSE ONLY\nURL: http://localhost:8080\nAccounts: admin, student, student2, lecturer, parking, canteen @campus.test\nFixture password: ${password}\nFixture wallet PIN: ${pin}\nRFID device token: ${device}\nDo not commit or share this file.\n`,{flag:'wx',mode:0o600});
console.log('Created deploy/.env and .work/compose-access.txt. Existing secrets are never overwritten.');
