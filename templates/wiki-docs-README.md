# Wiki document attachments

This orphan branch contains non-image binary attachments referenced by the
GitHub Wiki for [`{{REPO_SLUG}}`](https://github.com/{{REPO_SLUG}}/wiki).

Files retain the original Foswiki topic-folder layout. Their checksums are in
`SHA256SUMS`. Images live in the GitHub Wiki repository instead of this branch.

Wiki pages link to files using URLs of this form:

```text
https://raw.githubusercontent.com/{{REPO_SLUG}}/{{ATTACHMENT_BRANCH}}/{Topic}/{filename}
```

This branch has no shared history with `main`. Do not merge it into `main`.

After the migration, preserve existing paths so historical wiki links remain
stable. New non-image attachments may be added in the matching topic folder.
