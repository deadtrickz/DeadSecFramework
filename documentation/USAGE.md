# DeadSec Framework Usage

## Main Runner
Run from repo root:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\DeadSecFramework.ps1
```

## Core Flow
1. Select one or more sections (or `0 - All (except 99)`).
2. Set `Question Count`.
3. Click `Start Quiz`.
4. Enter command and press Enter (or click `Send`).

## Story Mode
1. Check `Story Mode`.
2. Select story from dropdown.
3. Click `Start Quiz`.

Story files are loaded from:
- `quiz-data\stories\*.json`

## Data Locations
- Questions: `quiz-data\questions\*.json`
- Stories: `quiz-data\stories\*.json`
- Man Pages: `quiz-data\man-pages\*.txt`
- Variables: `quiz-data\variables.json`
- Sections: `quiz-data\sections.json`
