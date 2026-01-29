# Azure DevOps AI Agent Automation

> **Template Repository** - Fork and customize for your organization

Automated AI agent triggered by Azure DevOps work items that implements solutions via OpenCode against GitHub Enterprise.

> **Built in 4 days** with Claude Opus 4.5 as AI development partner | **65% complete** (44/68 features) | **88 commits**

## Getting Started with This Template

### Option A: Fork and Customize
1. Fork or clone this repository
2. Search and replace these placeholders:
   - `your-org` → Your Azure DevOps organization name
   - `your-project` → Your Azure DevOps project name
3. Configure your test work item ID in `CLAUDE.md`
4. Follow the [Setup Guide](docs/SETUP.md)

### Option B: Use as Submodule (Recommended for Organizations)
Use this template as a submodule to keep generic and organization-specific code separate:

```bash
# Create your organization repo
mkdir my-org-ai-agent && cd my-org-ai-agent
git init

# Add template as submodule
git submodule add https://github.com/your-org/ado-ai-agent-template.git template

# Copy and customize the example pipeline
cp template/examples/azure-pipelines.yml azure-pipelines.yml
# Edit azure-pipelines.yml:
# - Change 'my-org-webhook' to your webhook connection name
# - Change 'myorg/opencode-custom' to your docker image

# Create your organization-specific systems and skills
mkdir -p systems skills
```

See [Extending Guide](docs/EXTENDING.md) for detailed submodule setup.

## Key Insight: The Right Tools Matter

> **We attempted to build this solution using GitHub Copilot (GPT-5.2) but were unsuccessful.** The agentic workflow required for this project—iterative debugging, complex pipeline syntax, cross-system integration—exceeded Copilot's capabilities.
>
> **The solution was built with Claude Opus 4.5**, which provided the autonomous problem-solving needed for rapid development.
>
> **The lesson:** While GitHub Copilot works well for code completion and simple tasks, **we currently lack enterprise-approved tools for true AI agentic development**. This project demonstrates both the potential and the gap.

| Aspect | Tool Used | Why |
|--------|-----------|-----|
| **Building this solution** | Claude Opus 4.5 | Agentic capability, complex reasoning, iterative debugging |
| **Running the AI agent** | GitHub Copilot (GPT-5.2) | Enterprise compliance, approved for production use |

## Security & Compliance

> **Information Security:** This solution uses **GitHub Enterprise Copilot** for AI capabilities. All data is handled within the organization's existing GitHub Enterprise agreement and infrastructure. No data is sent to external AI services.

| Aspect | Implementation |
|--------|----------------|
| AI Model | GitHub Copilot (Enterprise) |
| Authentication | `COPILOT_GITHUB_TOKEN` via GitHub Enterprise |
| Data Handling | All code and work item data stays within enterprise |
| Audit Trail | Full traceability in Azure DevOps and pipeline logs |
| Access Control | Agent can only create PRs, never merge |

### Current License

> **Note:** The solution currently uses **a dedicated GitHub Copilot license** for AI capabilities. For production deployment, a dedicated service account with Copilot license should be provisioned.

## Quick Start

1. **Setup** - Follow the [Setup Guide](docs/SETUP.md) to configure tokens and pipeline variables
2. **Create work item** - Add a Bug or User Story with clear description
3. **Tag it** - Add the `ai-ready` tag
4. **Review** - AI posts analysis as a comment
5. **Approve** - Add `ai-approved` tag to start implementation
6. **Merge** - Review and merge the created PR

## Three Operating Modes

The AI agent operates in three distinct modes:

### 1. Analyze Mode (`ai-ready` tag)

```
Developer adds "ai-ready" tag
         ↓
Pipeline fetches work item context + attachments
         ↓
AI analyzes using vision model (gpt-4.1)
         ↓
Posts implementation proposal as comment
```

### 2. Implement Mode (`ai-approved` tag)

```
Developer adds "ai-approved" tag
         ↓
Creates feature branch (ai/{workItemId})
         ↓
AI implements solution
         ↓
Runs quality gates (build, test, lint)
         ↓
Creates Pull Request
```

### 3. Command Mode (`@ai` mention)

```
Developer writes "@ai <question>" in comment
         ↓
AI reads context + question
         ↓
Posts response as new comment
```

**Example commands:**
```
@ai what files need changes?
@ai suggest test cases for this feature
@ai explain the current implementation
```

## Attachment Support

The AI can analyze attachments on work items using the vision model:

| Type | Extensions | Use Case |
|------|------------|----------|
| Images | PNG, JPG, GIF | Screenshots, UI mockups, error messages |
| PDF | .pdf | Specifications, design documents |
| Word | .docx | Requirements documents |
| Excel | .xlsx | Data specifications, test matrices |
| Text | .txt, .md | Notes, logs |

Inline images embedded in work item HTML fields are also extracted and analyzed.

## Tags

| Tag | Purpose | Added By |
|-----|---------|----------|
| `ai-ready` | Triggers analysis | Developer |
| `ai-working` | Processing in progress | Pipeline |
| `ai-approved` | Triggers implementation | Developer |
| `ai-failed` | Error occurred | Pipeline |

## Pipeline Architecture

The pipeline is designed to work in two modes:

### Standalone Mode (GitHub Template Users)
Use `pipelines/ai-agent.yml` directly. Customize via pipeline variables:
- `DOCKER_IMAGE` - Override the default OpenCode docker image

### Submodule Mode (Organizations)
Create your own `azure-pipelines.yml` that includes stages from the template:

```yaml
# Your org's azure-pipelines.yml
resources:
  webhooks:
    - webhook: WorkItemEvent
      connection: your-org-webhook  # Your unique webhook name

trigger: none

variables:
  DOCKER_IMAGE: 'your-org/opencode-custom'

stages:
  - template: template/pipelines/stages/process.yml
    parameters:
      webhookPayload: ${{ parameters.WorkItemEvent }}
  - template: template/pipelines/stages/analyze.yml
    parameters:
      dockerImage: $(DOCKER_IMAGE)
  - template: template/pipelines/stages/implement.yml
    parameters:
      dockerImage: $(DOCKER_IMAGE)
  - template: template/pipelines/stages/command.yml
    parameters:
      dockerImage: $(DOCKER_IMAGE)
  - template: template/pipelines/stages/skip.yml
```

See `examples/azure-pipelines.yml` for a complete example.

**Why this pattern?**
- Webhook connection names are globally unique per Azure DevOps org
- Each org can use their own docker image
- Template updates auto-propagate (just update submodule)
- No duplicated pipeline logic

## System Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        AZURE DEVOPS                             │
│  Work Item ──▶ Webhook ──▶ Pipeline                            │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      AZURE PIPELINE                             │
│  Process ──▶ Analyze/Implement/Command ──▶ Update Work Item    │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    GITHUB ENTERPRISE                            │
│  Feature Branch ──▶ Code Changes ──▶ Pull Request              │
└─────────────────────────────────────────────────────────────────┘
```

## Documentation

| Document | Description |
|----------|-------------|
| [Usage Guide](docs/USAGE.md) | How to use the AI agent (start here) |
| [Setup Guide](docs/SETUP.md) | Installation and configuration |
| [DoD Guide](docs/DOD-GUIDE.md) | Creating Definition of Done configs |
| [Pipeline Guide](docs/azure-pipelines-ghe.md) | Technical setup for OpenCode in pipelines |
| [Features](docs/FEATURES.md) | Feature list with implementation status |
| [Timeline](docs/TIMELINE.md) | Project development history |
| [Presentation Brief](docs/PRESENTATION-BRIEF.md) | Management presentation material |
| [System Config Plan](docs/SYSTEM-CONFIG-PLAN.md) | Roadmap for system-specific configurations |
| [PRD](PRD.md) | Product requirements and architecture |

## Project Structure

```
├── pipelines/
│   ├── ai-agent.yml              # Main standalone pipeline
│   ├── stages/                   # Reusable stage templates
│   │   ├── process.yml           # Webhook processing
│   │   ├── analyze.yml           # Analysis stage
│   │   ├── implement.yml         # Implementation stage
│   │   ├── command.yml           # Command stage
│   │   └── skip.yml              # Skip/no-action stage
│   └── templates/                # Job templates (used by stages)
│       ├── analyze.yml
│       ├── implement.yml
│       └── command.yml
├── examples/
│   └── azure-pipelines.yml       # Example for org customization
├── scripts/
│   ├── get-workitem-context.sh   # Fetch work item details + attachments
│   ├── build-prompt.sh           # Build prompts for OpenCode
│   ├── update-workitem.sh        # Update comments/tags/reactions
│   ├── resolve-system-config.sh  # Determine system configuration
│   └── send-teams-notification.sh
├── systems/
│   └── _default/
│       ├── config.yml            # Quality gates configuration
│       ├── context.md            # AI system context
│       ├── prompts/              # Mode-specific prompts
│       └── skills/               # 15 reusable prompt templates
└── docs/
    ├── USAGE.md                  # User guide
    ├── SETUP.md                  # Setup guide
    └── ...
```

## Requirements

- Azure DevOps with Pipelines
- GitHub Enterprise with Copilot license
- OpenCode CLI (runs via Docker)
- `COPILOT_GITHUB_TOKEN` - GitHub Enterprise Copilot token

## Status

| Category | Implemented | Planned |
|----------|-------------|---------|
| Core Pipeline | 12 | 4 |
| User Experience | 13 | 2 |
| Configuration | 3 | 10 |
| Security | 5 | 2 |
| Observability | 3 | 4 |
| Documentation | 8 | 2 |
| **Total** | **44** | **24** |

**Progress: 65% complete** - See [Features](docs/FEATURES.md) for details.

## Roadmap

### Next Phase
- [ ] Teams notifications on completion/error
- [ ] System-specific configurations per repository
- [ ] Token usage and cost tracking
- [ ] Performance metrics dashboard

### Future Vision
- Automatic triage of suitable work items
- Multi-repository support
- Self-improving based on PR review feedback

See [System Config Plan](docs/SYSTEM-CONFIG-PLAN.md) for detailed roadmap.

## Pilot Program

**Recommended:** Deploy to one team for 1 month

| Success Metric | Target |
|----------------|--------|
| Time from work item to PR | < 30 minutes |
| Developer time saved/week | > 5 hours |
| PR first-time approval rate | > 80% |

### Next Steps
1. Provision dedicated GitHub Copilot license
2. Configure webhooks for pilot team's project
3. Train developers on workflow (30 min session)
4. Monitor and collect metrics
