# promptlibrary — Feature Ideas

## 1. Automated Accessibility Testing (jest-axe)
The a11y attributes are now in place but there's no automated regression testing. Add jest-axe to PromptCard, Nav, and page component tests to catch future a11y regressions.

## 2. Keyboard Shortcut for Copy (Ctrl+C style)
Add a keyboard shortcut (e.g., pressing 'c' when focused on the prompt body) to copy the prompt text. Would streamline the workflow for power users who navigate with keyboard.

## 3. Prompt Fork/Remix
Allow users to "fork" an existing public prompt into their own collection as a new prompt, preserving attribution to the original. The data model already supports this (just a new prompt with a `source` reference).

## DONE
- ~~Copy-to-Clipboard Toast Feedback~~ — Completed run 115. Inline "Copied!" button state change with checkmark icon, 2s timeout.
- ~~Prompt Edit Page~~ — Completed run 120. Full edit page with version-aware body editing, PATCH API for tags/sampleOutput, author-only edit button.
- ~~Automated Accessibility Testing (jest-axe)~~ — Completed run 125. 14 axe tests across all 4 components + fixed real StarRating readonly a11y bug.
