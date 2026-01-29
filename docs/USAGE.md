# User Guide - AI Agent

This guide explains how to use the AI agent to analyze and implement Azure DevOps work items.

## Overview

The AI agent works by monitoring tags on work items. When you add specific tags, automated pipelines are triggered that analyze or implement solutions.

```
You add "ai-ready" tag
         ↓
AI analyzes → Posts proposal as comment
         ↓
You review and add "ai-approved" tag
         ↓
AI implements → Creates PR
         ↓
You review and merge PR
```

---

## Quick Start

### Step 1: Prepare work item

Create or open a Bug or User Story with:
- **Clear title** - Describe the problem or feature
- **Description** - Details about what needs to be done
- **Acceptance Criteria** - What's required to be complete
- **Attachments** (optional) - Screenshots, diagrams, etc.

### Step 2: Request analysis

Add the `ai-ready` tag to the work item.

**What happens:**
1. Pipeline triggers automatically
2. The `ai-working` tag is added (prevents duplicate runs)
3. AI analyzes the work item and attachments
4. Analysis is posted as a comment
5. The `ai-ready` tag is removed

### Step 3: Review analysis

Read the AI's analysis comment. It contains:
- Summary of the problem/feature
- Implementation proposal
- Files that need changes
- Potential risks

### Step 4: Approve implementation

If the analysis looks good, add the `ai-approved` tag.

**What happens:**
1. Pipeline triggers automatically
2. Feature branch is created (`ai/{workItemId}`)
3. AI implements the solution
4. Quality gates run (build, test, lint)
5. Pull Request is created
6. PR link is posted as a comment

### Step 5: Review and merge

Review the Pull Request in GitHub. If everything looks good, merge.

---

## Tags

| Tag | Purpose | Added by |
|-----|---------|----------|
| `ai-ready` | Request analysis | You |
| `ai-working` | Processing in progress | Pipeline |
| `ai-approved` | Request implementation | You |
| `ai-failed` | Error occurred | Pipeline |

### Tag rules

- **Don't add `ai-ready` and `ai-approved` at the same time** - Run analysis first
- **Never remove `ai-working`** - It's removed automatically when the pipeline completes
- **If `ai-failed` appears** - Read the error comment, fix the problem, remove the tag and try again

---

## Commands with @ai

You can ask questions or give instructions by writing comments with `@ai`:

```
@ai what needs to change to fix this?
@ai suggest test cases
@ai which files are affected?
@ai summarize this bug
```

**What happens:**
1. Pipeline triggers from the comment
2. AI reads the work item context and your question
3. Response is posted as a new comment

### Tips for @ai commands

- Be specific about what you want to know
- Reference specific parts of the code if possible
- Use for research before requesting implementation

---

## Attachments

The AI can analyze attachments attached to the work item:

| File type | Supported |
|-----------|-----------|
| Images (PNG, JPG, GIF) | Yes |
| PDF documents | Yes |
| Word documents (.docx) | Yes |
| Excel files (.xlsx) | Yes |
| Text files | Yes |

### Tips for attachments

- **Screenshots**: Mark relevant areas
- **Diagrams**: Use clear labels
- **Documents**: Structure with headings

---

## Error Handling

### If `ai-failed` tag appears

1. Open the work item
2. Read the latest AI comment - it contains the error message and link to pipeline logs
3. Common causes:
   - Build errors in the code
   - Failing tests
   - Unclear requirements
4. Fix the problem
5. Remove the `ai-failed` tag
6. Add `ai-ready` or `ai-approved` again

### Common problems

| Problem | Solution |
|---------|----------|
| No comment appears | Check that the pipeline was triggered (see Pipeline runs) |
| "ai-working" doesn't disappear | Pipeline may have crashed - check logs |
| PR not created | Quality gates failed - read the error comment |
| Wrong repo or branch | Check work item connection to correct repo |

---

## Best Practices

### Write clear work items

**Good:**
> **Title:** Login button doesn't work on mobile
>
> **Description:** When users tap the login button on mobile devices (iOS Safari) nothing happens. Desktop works.
>
> **Acceptance Criteria:**
> - Login button should work on iOS Safari
> - Should work on Android Chrome
> - Existing desktop functionality should not be affected

**Bad:**
> **Title:** Fix login
>
> **Description:** It doesn't work

### Always review AI's code

- AI can make mistakes
- Verify the solution matches requirements
- Run manual tests in addition to automated ones

### Use the analysis step

- Always add `ai-ready` first
- Review the analysis before approving
- Ask follow-up questions with `@ai` if something is unclear

---

## Comment Updates (Idempotent)

When you re-run analysis on the same work item, the AI **updates its existing comment** instead of creating a new one. This keeps the work item clean and avoids comment spam.

### How it works

1. AI comments are marked with a hidden `[AI-ANALYSIS]` marker
2. When the pipeline runs, it checks for an existing comment with this marker
3. If found, the existing comment is **updated** with new content
4. If not found, a new comment is created

### Benefits

- **Clean history**: Only one AI analysis comment per work item
- **Always current**: Re-running shows the latest analysis
- **No duplicates**: Multiple runs don't create multiple comments

### When updates happen

| Scenario | Result |
|----------|--------|
| First `ai-ready` run | New comment created |
| Second `ai-ready` run | Existing comment updated |
| `ai-approved` run | New implementation comment (different marker) |
| `@ai` command | New response comment |

---

## Support

- **Pipeline logs**: Click the link in the error comment
- **Teams notifications**: Errors are sent to Teams (if configured)
- **Documentation**: See [Setup Guide](SETUP.md) and [DoD Guide](DOD-GUIDE.md)
