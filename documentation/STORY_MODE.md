# Story Mode: Creation + Usage

Story Mode is a linear scenario system loaded from JSON files in `quiz-data\stories\`.

## Story File Location
Place story files in:
- `quiz-data\stories\*.json`

## Story JSON Format
```json
{
  "id": "string",
  "name": "string",
  "description": "string",
  "steps": [
    {
      "question": "string or [\"line1\", \"line2\"]",
      "answer": "exact command",
      "alternate_answers": ["exact alt 1", "exact alt 2"],
      "on_correct": {
        "messages": ["message line 1"],
        "beacon_add": [],
        "beacon_update": [],
        "beacon_remove": []
      },
      "on_incorrect": {
        "messages": ["optional failure message"],
        "beacon_add": [],
        "beacon_update": [],
        "beacon_remove": []
      }
    }
  ]
}
```

## Behavior Rules
- Steps are linear.
- Story mode requires correct answer to progress.
- Answer matching is case-sensitive (with app normalization rules).
