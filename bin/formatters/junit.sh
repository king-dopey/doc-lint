#!/usr/bin/env node
/**
 * doc-lint JUnit XML formatter
 * Reads intermediate format from stdin and produces JUnit XML output.
 * Intermediate format: file:line:col:rule:severity:message
 */

const fs = require('fs');

// ---- Helper: XML-escape a string ----------------------------------------------
function xmlEscape(s) {
  const amp = '&' + 'amp;';
  const lt = '&' + 'lt;';
  const gt = '&' + 'gt;';
  const quot = '&' + 'quot;';
  return s
    .replace(/&/g, amp)
    .replace(/</g, lt)
    .replace(/>/g, gt)
    .replace(/"/g, quot);
}

const input = fs.readFileSync(0, 'utf8');
const lines = input.trim().split('\n').filter(l => l.trim());

// First pass: count tests and failures per file
const fileTests = {};
const fileFailures = {};

for (const line of lines) {
  const parts = line.split(':');
  if (parts.length < 6) continue;
  
  const file = parts[0];
  if (!fileTests[file]) {
    fileTests[file] = 0;
    fileFailures[file] = 0;
  }
  fileTests[file]++;
  fileFailures[file]++;
}

// Second pass: generate testsuites with XML escaping
const printedFiles = {};
let output = '<?xml version="1.0" encoding="UTF-8"?>\n';
output += '<testsuites name="doc-lint" tests="' + (lines.length) + '" failures="' + (lines.length) + '" errors="0">\n';

for (const line of lines) {
  const parts = line.split(':');
  if (parts.length < 6) continue;
  
  const file = parts[0];
  const lineNum = parseInt(parts[1], 10) || 0;
  const col = parseInt(parts[2], 10) || 0;
  const rule = parts[3];
  const severity = parts[4];
  const message = parts.slice(5).join(':');
  
  if (!printedFiles[file]) {
    output += '  <testsuite name="' + xmlEscape(file) + '" tests="' + fileTests[file] + '" failures="' + fileFailures[file] + '">\n';
    printedFiles[file] = true;
  }
  
  output += '    <testcase name="' + xmlEscape(rule) + ' at line ' + lineNum + '">\n';
  output += '      <failure message="' + xmlEscape(message) + '" type="' + xmlEscape(severity) + '">\n';
  output += '        File: ' + xmlEscape(file) + '\n';
  output += '        Line: ' + lineNum + '\n';
  output += '        Column: ' + col + '\n';
  output += '        Rule: ' + xmlEscape(rule) + '\n';
  output += '        Severity: ' + xmlEscape(severity) + '\n';
  output += '        Message: ' + xmlEscape(message) + '\n';
  output += '      </failure>\n';
  output += '    </testcase>\n';
}

output += '  </testsuite>\n';
output += '</testsuites>\n';

process.stdout.write(output);
