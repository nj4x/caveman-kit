// caveman-kit bench — the six single-turn task prompts (ADR 0008 decision 2).
// Ids are stable: they name result files, so renaming one orphans its cells.
// Each prompt is self-contained; the single-turn harness runs with no repo.
'use strict';

module.exports = [
  {
    id: 'explain-race',
    prompt: 'How do you debug a race condition in a multithreaded service that only fails under load?',
  },
  {
    id: 'review-snippet',
    prompt: [
      'Review this JavaScript function and point out the bugs:',
      '',
      '```js',
      'async function loadUsers(ids) {',
      '  const users = [];',
      '  ids.forEach(async id => {',
      '    const res = await fetch(`/api/users/${id}`);',
      '    users.push(await res.json());',
      '  });',
      '  return users;',
      '}',
      '```',
    ].join('\n'),
  },
  {
    id: 'git-rebase-merge',
    prompt: 'When should I use git rebase instead of git merge on a shared feature branch?',
  },
  {
    id: 'error-explain',
    prompt: 'My Python script fails with "RecursionError: maximum recursion depth exceeded while calling a Python object" when parsing a deeply nested JSON file. What is going on and how do I fix it?',
  },
  {
    id: 'write-function',
    prompt: 'Write a Python function that merges overlapping intervals in a list of (start, end) tuples, and explain its time complexity.',
  },
  {
    id: 'design-cache',
    prompt: 'I need to add caching in front of a slow REST API that returns user profiles. Which invalidation strategy should I use, and what are the trade-offs?',
  },
];
