# Invalid Markdown Document

This document contains multiple lint violations for testing purposes.

## Missing blank line before heading
This line should have a blank line before the next heading.
### Another heading without proper spacing

This line is way too long and violates the MD013 rule because it exceeds the maximum line length of 120 characters that is configured in the default markdownlint configuration file for this project which should trigger a warning.

<div>This is inline HTML which violates MD033</div>

*Emphasis as heading* which violates MD036

- List with inconsistent markers
* Mixed markers here
- Back to dash

Trailing spaces   

Multiple blank lines below:



The above had multiple blank lines which violates MD012.

```
Code block without language specified violates MD040
```
