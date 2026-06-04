# PlantUML Skill for OpenCode

Natural language → PlantUML diagrams → SVG/PNG/PDF. An [OpenCode](https://github.com/voidzero-dev/opencode) skill that generates OMG-UML compliant diagrams from plain English descriptions.

## Features

- **6+ diagram types**: Sequence, Class, Activity, Use Case, Component, State, and more
- **Natural language input**: Describe what you want — the skill picks the right diagram type
- **OMG-UML strict style**: Pure black-and-white, no decorative icons, standard UML notation
- **Multiple render backends**: PlantUML public server → Docker → local JAR (auto-fallback)
- **Text-based stereotypes**: `«interface»` and `«abstract»` instead of circle-with-letter icons
- **Zero color**: Monochrome output suitable for academic papers, RFCs, and technical docs

## Prerequisites

At least one of:

| Method | Requirement |
|---|---|
| Docker | `docker pull plantuml/plantuml:latest` |
| Java | JRE 8+ with `plantuml.jar` |
| Internet | (public server fallback — limited reliability) |

Docker is recommended and used by default.

## Installation

```bash
git clone https://github.com/samonysh/plantuml-skill.git
cp -r plantuml-skill/.opencode/skills/plantuml ~/.config/opencode/skills/
```

Or link it as a project-local skill:

```bash
ln -s $(pwd)/plantuml-skill/.opencode/skills/plantuml .opencode/skills/plantuml
```

## Quick Start

Once the skill is installed, trigger it with natural language in OpenCode:

```
> Draw a sequence diagram showing OAuth2 login flow between User, Client, and Auth Server

> Create a class diagram for an e-commerce order domain model

> Generate an activity diagram for a refund approval workflow with swimlanes
```

The skill will:
1. Parse your requirements and select the appropriate diagram type
2. Generate PlantUML source code with OMG-UML monochrome styling
3. Render it to SVG (PNG and PDF also supported)
4. Display the result inline

### Manual rendering

You can also render `.puml` files directly:

```bash
bash scripts/generate-plantuml.sh input.puml output_dir --format svg
```

Options: `--format svg|png|pdf|txt` (default: `svg`)

## Supported Diagram Types

| Type | Best for | Example trigger |
|---|---|---|
| **Sequence** | API flows, request/response, handshakes | "A sends X to B, then B responds with Y" |
| **Class** | Domain models, entity relationships | "Customer has many Orders, Order has Items" |
| **Activity** | Workflows, pipelines, approval chains | "If payment valid, ship order; else reject" |
| **Use Case** | System actors, roles, permissions | "Admin can manage users, Editor can publish" |
| **Component** | Microservices, system architecture | "API Gateway routes to User and Order services" |
| **State** | Lifecycles, state machines | "Ticket goes from New → Assigned → Resolved" |
| Deployment | Infrastructure, cloud topology | (by description) |
| Gantt | Timelines, project plans | (by description) |
| Mind Map | Hierarchies, brainstorming | (by description) |

## Style Standard

All generated diagrams follow **OMG-UML strict black-and-white** conventions:

```
skinparam style strictuml
skinparam monochrome true
skinparam backgroundColor white
skinparam defaultFontName Helvetica
skinparam shadowing false
skinparam classAttributeIconSize 0
```

Key rules:
- **No circle stereotype icons** — `«interface»` / `«abstract»` rendered as text, not Ⓒ/Ⓘ/Ⓐ circles
- **No color** — only `#000000` and `#FFFFFF`
- **No 3D shadows**
- **No attribute visibility circles** (●/◐/○) — uses `+`/`-`/`#` text markers
- **Standard UML notation** — stick figures, dashed dependencies, dotted lifelines

## Examples

### Sequence Diagram — OAuth2 Authorization Code Flow

![OAuth2 Sequence](examples/01_sequence_oauth2.svg)

### Class Diagram — Order Domain Model

![Order Domain](examples/02_class_order_domain.svg)

### Activity Diagram — Refund Approval Workflow

![Refund Workflow](examples/03_activity_refund.svg)

### Use Case Diagram — CMS System

![CMS Use Case](examples/04_usecase_cms.svg)

### Component Diagram — Microservice Architecture

![Microservices](examples/05_component_microservices.svg)

### State Diagram — Support Ticket Lifecycle

![Ticket States](examples/06_state_ticket.svg)

All example source files (`.puml`) are in the [`examples/`](examples/) directory. You can regenerate them with:

```bash
bash scripts/generate-plantuml.sh examples/01_sequence_oauth2.puml examples --format svg
```

## Project Structure

```
plantuml-skill/
├── .opencode/
│   └── skills/
│       └── plantuml/
│           ├── skill.md                    # Skill definition & instructions
│           ├── scripts/
│           │   └── generate-plantuml.sh    # Render script (3 backends)
│           └── references/                 # (extensible)
├── examples/
│   ├── 01_sequence_oauth2.puml / .svg
│   ├── 02_class_order_domain.puml / .svg
│   ├── 03_activity_refund.puml / .svg
│   ├── 04_usecase_cms.puml / .svg
│   ├── 05_component_microservices.puml / .svg
│   └── 06_state_ticket.puml / .svg
├── .gitignore
└── README.md
```

## Render Script

`scripts/generate-plantuml.sh` tries three backends in order:

1. **PlantUML public server** (`https://www.plantuml.com/plantuml`) — requires internet
2. **Docker** (`plantuml/plantuml:latest`) — requires Docker
3. **Local JAR** (`plantuml.jar`) — requires Java and the JAR in PATH

```bash
# SVG (default)
bash generate-plantuml.sh diagram.puml ./output

# PNG
bash generate-plantuml.sh diagram.puml ./output --format png

# ASCII art (no rendering needed — txt format skips image generation)
bash generate-plantuml.sh diagram.puml ./output --format txt
```

## License

MIT
