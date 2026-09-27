#!/usr/bin/env node
/**
 * doc-lint — JSON Schema validation via ajv.
 * Usage: json-schema-check.js <data.json> <schema.json>
 * Exit 0 = valid, 1 = invalid (errors printed), 2 = usage error.
 */
const fs = require('fs');
const Ajv = require('ajv');

const [dataPath, schemaPath] = process.argv.slice(2);
if (!dataPath || !schemaPath) {
  console.error('usage: json-schema-check.js <data.json> <schema.json>');
  process.exit(2);
}

let data, schema;
try {
  data = JSON.parse(fs.readFileSync(dataPath, 'utf8'));
} catch (e) {
  console.error(`[json-schema] cannot parse data ${dataPath}: ${e.message}`);
  process.exit(1);
}
try {
  schema = JSON.parse(fs.readFileSync(schemaPath, 'utf8'));
} catch (e) {
  console.error(`[json-schema] cannot parse schema ${schemaPath}: ${e.message}`);
  process.exit(2);
}

// Ajv strict mode off to tolerate common doc schemas; full draft-2020 support.
const ajv = new Ajv({ strict: false, allErrors: true });
const validate = ajv.compile(schema);
const ok = validate(data);

if (!ok) {
  console.error(`[json-schema] ${dataPath} INVALID:`);
  for (const err of validate.errors) {
    console.error(`  - ${err.instancePath || '/'}: ${err.message}`);
  }
  process.exit(1);
}
console.log(`[json-schema] ${dataPath} VALID`);
process.exit(0);
