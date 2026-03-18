# DeadSecFramework Editor

`DeadSecFramework-Editor.ps1` is the PowerShell editor UI for Questions, Stories, and Man Pages.

## Run
From repo root:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\DeadSecFramework-Editor.ps1
```

## Data Paths Used
- Questions: `quiz-data\questions\*.json`
- Stories: `quiz-data\stories\*.json`
- Man Pages: `quiz-data\man-pages\*.txt`

## Notes
- `Template` buttons create starter JSON structures for question/story files.
- `Add Beacon` inserts a beacon template into `on_correct` JSON for a story step.
