#!/usr/bin/env node
/**
 * doc-lint SARIF formatter
 * Reads intermediate format from stdin and produces SARIF v2.1.0 output.
 * Intermediate format: file:line:col:rule:severity:message
 * 
 * SARIF specification: https://docs.oasis-open.org/sarif/sarif/v2.1.0/sarif-v2.1.0.html
 */
const fs = require('fs');

const results = [];
const rules = new Map();

const input = fs.readFileSync(0, 'utf8');
const lines = input.trim().split('\n');

for (const line of lines) {
  if (!line.trim()) continue;
  
  // Parse intermediate format: file:line:col:rule:severity:message
  const parts = line.split(':');
  if (parts.length < 6) continue;
  
  const file = parts[0];
  const lineNum = parseInt(parts[1], 10) || 1;
  const col = parseInt(parts[2], 10) || 1;
  const rule = parts[3];
  const severity = parts[4].toLowerCase();
  const message = parts.slice(5).join(':');
  
  // Map severity to SARIF level
  let level = 'warning';
  if (severity === 'error' || severity === 'fail') {
    level = 'error';
  } else if (severity === 'note' || severity === 'info') {
    level = 'note';
  }
  
  // Track unique rules
  if (!rules.has(rule)) {
    rules.set(rule, {
      id: rule,
      shortDescription: {
        text: rule
      }
    });
  }
  
  results.push({
    ruleId: rule,
    level: level,
    message: {
      text: message
    },
    locations: [
      {
        physicalLocation: {
          artifactLocation: {
            uri: file,
            uriBaseId: '%SRCROOT%'
          },
          region: {
            startLine: lineNum,
            startColumn: col
          }
        }
      }
    ]
  });
}

const sarif = {
  $schema: 'https://raw.githubusercontent.com/oasis-tcs/sarif-spec/master/Schemata/sarif-schema-2.1.0.json',
  version: '2.1.0',
  runs: [
    {
      tool: {
        driver: {
          name: 'doc-lint',
          informationUri: 'https://github.com/king-dopey/docs-linting',
          rules: Array.from(rules.values())
        }
      },
      results: results
    }
  ]
};

console.log(JSON.stringify(sarif, null, 2));
