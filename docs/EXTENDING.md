# Extending the Template

This document explains how to use this template as a submodule in your organization-specific repository.

## Architecture

```
your-org-ai-agent/                    # Your private repo
├── .gitmodules
├── template/                         # Submodule → ado-ai-agent-template
│   ├── pipelines/
│   ├── scripts/
│   └── systems/_default/
├── systems/                          # Your organization's systems
│   ├── your-system-1/
│   ├── your-system-2/
│   └── _override/                    # Override default settings
├── skills/                           # Your organization's skills
│   └── your-custom-skill/
├── certs/                            # Your certificates
├── config.yml                        # Organization-wide config
└── azure-pipelines.yml               # Points to template/pipelines/
```

## Setup

### 1. Create your organization repository

```bash
mkdir your-org-ai-agent
cd your-org-ai-agent
git init
```

### 2. Add the template as a submodule

```bash
git submodule add https://github.com/your-org/ado-ai-agent-template.git template
git submodule update --init --recursive
```

### 3. Create organization config

Create `config.yml` in your repo root:

```yaml
# Organization-specific configuration
organization: your-azure-devops-org
project: your-project

# Override default settings
defaults:
  quality_gates:
    coverage_min: 80
```

### 4. Create your pipeline

Create `azure-pipelines.yml` that extends the template:

```yaml
# Reference the template pipeline
trigger: none

resources:
  repositories:
    - repository: self

extends:
  template: template/pipelines/ai-agent.yml
  parameters:
    organization: $(AZURE_DEVOPS_ORG)
    project: $(System.TeamProject)
    systemsPath: systems
    skillsPath: skills
```

## Adding Organization-Specific Systems

Create a new system in `systems/your-system/`:

```
systems/your-system/
├── config.yml          # Quality gates and detection rules
├── context.md          # System-specific AI context
└── skills/             # System-specific skills (optional)
```

### Example config.yml

```yaml
name: your-system
description: Your system description

detection:
  tags:
    - "your-system"
  area_path:
    - "YourProject\\YourArea"

quality_gates:
  build:
    command: "npm run build"
  test:
    command: "npm test"
  lint:
    command: "npm run lint"
```

## Adding Organization-Specific Skills

Create skills in `skills/your-skill/SKILL.md`:

```markdown
---
name: your-skill
description: When to use this skill
---

# Your Skill

Instructions for the AI agent...
```

## File Resolution Order

Scripts look for files in this order:
1. `./systems/{system}/` - Organization-specific system
2. `./systems/_override/` - Organization overrides for defaults
3. `./template/systems/_default/` - Template defaults

This allows you to:
- Add new systems without modifying the template
- Override default behavior when needed
- Inherit all generic functionality automatically

## Updating the Template

To pull updates from the template:

```bash
cd template
git fetch origin
git checkout main
git pull
cd ..
git add template
git commit -m "chore: update template submodule"
```

## Best Practices

1. **Never modify files inside `template/`** - Make changes in your org repo
2. **Use override patterns** - Put overrides in `systems/_override/`
3. **Keep skills generic** - If a skill could benefit others, consider contributing it upstream
4. **Document your systems** - Add good context.md files for AI understanding
