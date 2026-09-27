#!/usr/bin/env node
/**
 * doc-lint JSON formatter
 * Reads intermediate format from stdin and produces JSON output.
 * Intermediate format: file:line:col:rule:severity:message
 */
const fs = require('fs');

const results = {};
let currentFile = null;

const input = fs.readFileSync(0, 'utf8');
const lines = input.trim().split('\n');

for (const line of lines) {
  if (!line.trim()) continue;
  
  // Parse intermediate format: file:line:col:rule:severity:message
  const parts = line.split(':');
  if (parts.length < 6) continue;
  
  const file = parts[0];
  const lineNum = parseInt(parts[1], 10) || 0;
  const col = parseInt(parts[2], 10) || 0;
  const rule = parts[3];
  const severity = parts[4];
  const message = parts.slice(5).join(':');
  
  if (!results[file]) {
    results[file] = {
      path: file,
      results: []
    };
  }
  
  results[file].results.push({
    line: lineNum,
    column: col,
    rule: rule,
    severity: severity,
    message: message
  });
}

const output = {
  files: Object.values(results)
};

console.log(JSON.stringify(output, null, 2));
