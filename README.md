# DeadSecFramework

DeadSecFramework is a PowerShell-based training tool for FUN only.

## Disclaimer
**Important**: This repository is not intended for any malicious use. It is a tool designed to help you learn and practice commands through interactive quizzes. Everything is simulated and should be safe. All information in this repository is derived from publicly available sources, including man pages, help text, and open-source documentation. This project does not promote hacking or unauthorized activities in any form. Any use of this tool/repository for unethical or illegal purposes is strongly discouraged and in no way condoned.

**Make no mistake**: the commands and tools are, mostly, real and should only be used with legal authority. Using any commands simulated by this tool, outside of this tool, could come with severe legal consequence.

## Repository Layout
- `DeadSecFramework.ps1` - main tool
- `DeadSecFramework-Editor.ps1` - editor for questions/stories/man pages
- `quiz-data/sections.json` - section catalog
- `quiz-data/variables.json` - variable pools
- `quiz-data/questions/*.json` - quiz questions
- `quiz-data/stories/*.json` - story mode files
- `quiz-data/man-pages/*.txt` - man/help text content
- `documentation/` - project documentaion; should be in the wiki
- `notes/` - note files generated for questions/stories

## Run
From repo root:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\DeadSecFramework.ps1
```

Editor:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\DeadSecFramework-Editor.ps1
```

## Notes
- Story files are loaded from `quiz-data\stories`.
- Question files are loaded from `quiz-data\questions`.
- Man pages are loaded from `quiz-data\man-pages`.
