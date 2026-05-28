# Generate Release Notes

Generate a draft of `RELEASE_NOTES.md` from commits since the last git tag, then let the user review and edit before writing the file.

## Steps

1. Find the latest git tag:
   ```
   git describe --tags --abbrev=0
   ```

2. Get all commits since that tag (excluding merge commits):
   ```
   git log <tag>..HEAD --oneline --no-merges
   ```

3. Analyze the commit messages and translate them into user-friendly bullet points:
   - Write for a non-technical end user, not a developer
   - Focus on **what changed for the user**, not how it was implemented
   - Skip or fold in: test changes, CI fixes, dependency bumps, code cleanup
   - Combine closely related commits into one bullet
   - Avoid git jargon ("refactor", "fix merge conflict", "bump", "chore")
   - Keep each bullet to one line

4. Show the draft to the user in this format and ask if they want to edit anything:
   ```
   - First user-visible change
   - Second user-visible change
   ```
   Do NOT include a heading — the heading is added automatically by the release pipeline.

5. After the user approves (or provides edits), write the final content to `RELEASE_NOTES.md`.
   Overwrite whatever was there before.

6. Remind the user to commit `RELEASE_NOTES.md` alongside the VERSION bump.
