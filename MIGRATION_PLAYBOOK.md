# Foswiki-to-GitHub migration playbook

This playbook migrates the `AgricultureSummit` Foswiki web to:

- Main repository: <https://github.com/opengeospatial/AgricultureSummit2017>
- GitHub Wiki: <https://github.com/opengeospatial/AgricultureSummit2017/wiki>
- Attachment branch: `wiki-docs` in the main repository

The workflow is deliberately split into local generation, human review, and
three separately gated publications. Every publisher is a dry-run unless
`--push` is supplied.

## 1. Safety and source-of-truth rules

1. `Source2026/` is the immutable latest-TML archive after migration.
2. The GitHub Wiki becomes the live editable documentation after cutover.
3. `wiki-docs` contains non-image attachments and is never merged into `main`.
4. Wiki images live in `AgricultureSummit2017.wiki.git` under `images/`.
5. Every current `.txt` topic is migrated unless it is in `EXCLUDE_TOPICS`.
   Default Foswiki pages and RCS `,v` history are not migrated.
6. Do not rerun the wiki publisher after post-cutover manual edits without
   first cloning and reviewing the live wiki. `--replace-existing` means what
   it says.

As inspected on 2026-09-18, the remote `main` branch contains only
`.gitignore`, the wiki `master` branch contains only GitHub's default
`Home.md`, and `wiki-docs` does not exist. The scripts re-check remote state;
they do not rely on this snapshot.

## 2. Prerequisites

Required commands:

- Bash, Git, Python 3, `tar`, `file`, `iconv`, `shasum`, `curl`
- GNU `timeout`; on macOS install GNU coreutils (`gtimeout` is detected)
- Docker running, unless a local Pandoc 3.8 is selected

The default converter uses the pinned container `pandoc/latex:3.8`. To use a
local executable instead:

```bash
PANDOC_MODE=local PANDOC_BIN=/path/to/pandoc \
  ./scripts/run-local-migration.sh
```

Authenticate Git HTTPS pushes before publication. One supported setup is:

```bash
gh auth login
gh auth setup-git
```

The scripts never store credentials.

## 3. Review the per-web configuration

All web-specific values are in `migration.conf`. For this pilot, verify:

- Export: `../AgricultureSummit2017-20260917.tgz`
- Source web: `AgricultureSummit`
- Target slug: `opengeospatial/AgricultureSummit2017`
- Default Foswiki/TWiki infrastructure names in `EXCLUDE_TOPICS`, including
  compatibility names used by different wiki versions

Topic discovery is automatic: `EachWikiPage.txt` becomes
`EachWikiPage.md`. The one naming exception is `WebHome.txt`, which becomes
GitHub Wiki's required landing page, `Home.md`. Add an exclusion only after
confirming that a discovered topic should not migrate.

Run the fast tool tests:

```bash
./scripts/test-migration-tools.sh
```

## 4. Inventory the export without writing

```bash
./scripts/prepare-source.sh
```

Expected Agriculture Summit inventory:

- 8 automatically discovered, non-excluded TML topics
- 8 non-image files for `wiki-docs`
- 1 wiki image

The command also rejects unsafe archive paths, an absent `WebHome.txt`, wiki
filename collisions, and topic names GitHub Wiki cannot represent.

## 5. Generate the local migration candidate

Start Docker, then run:

```bash
# ./scripts/run-local-migration.sh
```

This is equivalent to:

```bash
./scripts/prepare-source.sh --apply
./scripts/convert-twiki2md.sh
./scripts/validate-migration.sh
```

For this web, `prepare-source.sh` runs `scripts/local-fixes-REPO_NAME.sh` on the staged source
before recording checksums. Running `./scripts/local-fixes-REPO_NAME.sh` directly also refreshes
`manifests/source.sha256`.

Outputs:

```text
Source2026/             discovered non-default TML source (committed to main)
manifests/              committed checksums and attachment inventory
build/wiki-docs/        ignored non-image branch staging
build/wiki-images/      ignored extracted image staging
build/wiki/             ignored GitHub Wiki staging
```

If the archive or exclusion list intentionally changed, review the differences and
then permit replacement:

```bash
./scripts/run-local-migration.sh --replace-source
```

Never use `--replace-source` merely to bypass an unexplained difference.

## 6. Review the generated candidate

At minimum, inspect all eight Markdown files in `build/wiki/` and verify:

- `Home.md` is the OGC Agriculture Summit landing page.
- All seven agenda links resolve to generated pages.
- `images/WebHome/Field01.jpg` renders on `Home.md`.
- `AgSummitIntro.md` links to `AgSummitIntro.mp4` without the source's stray
  leading space.
- Agenda bylines retain Markdown emphasis through the underscore guard and do
  not acquire bogus WikiWord links (for example, `Group_` remains plain text).
- `AgSummitScience.md` contains the automatically recovered PDF link even
  though its TML body omitted it.
- The historical “Register for Summit” link is preserved, removed, or labeled
  as historical by an explicit editorial decision.
- No default Foswiki pages were generated.

The local validator enforces page counts, checksums, local links, attachment
coverage, agreement between `%META:FILEATTACHMENT` records and exported files,
and absence of residual Foswiki macros. Visual/editorial review is still
required because mechanical validity cannot establish meaning.

The source/attachment portion can be checked independently before Pandoc is
available:

```bash
./scripts/validate-migration.sh --source-only
```

`manifests/source.sha256` describes the committed `Source2026` files.

## 7. Stage `main` through a review branch

Dry-run the clone-and-stage operation:

```bash
./scripts/publish-main.sh
```

Publish the configured review branch:

```bash
./scripts/publish-main.sh --push
```

The script prints the GitHub comparison URL for
`migration/foswiki-2026 -> main`. Review and merge that pull request before
publishing the attachment branch and wiki. The script never pushes directly
to `main`.

Confirm after merge:

```bash
git ls-remote --heads \
  https://github.com/opengeospatial/AgricultureSummit2017.git main
```

## 8. Create the orphan attachment branch

Dry-run:

```bash
./scripts/seed-wiki-docs-branch.sh
```

Publish:

```bash
./scripts/seed-wiki-docs-branch.sh --push
```

The first commit contains the eight binary attachments, `README.md`,
`SHA256SUMS`, and a migration marker. The branch has no shared history with
`main`.

If a marked branch already exists and an intentional restage is needed:

```bash
./scripts/seed-wiki-docs-branch.sh --replace-existing
./scripts/seed-wiki-docs-branch.sh --replace-existing --push
```

An existing branch without the matching migration marker is always refused.

## 9. Publish the GitHub Wiki

The remote wiki is already initialized with GitHub's one-page seed. Dry-run:

```bash
./scripts/stage-for-wiki.sh
```

Publish the reviewed candidate:

```bash
./scripts/stage-for-wiki.sh --push
```

The seed state is recognized automatically. A subsequent differing restage
requires explicit replacement:

```bash
./scripts/stage-for-wiki.sh --replace-existing
./scripts/stage-for-wiki.sh --replace-existing --push
```

## 10. Validate the public result

After both publications:

```bash
./scripts/validate-migration.sh --remote
```

Then perform a logged-out browser review of:

- <https://github.com/opengeospatial/AgricultureSummit2017>
- <https://github.com/opengeospatial/AgricultureSummit2017/wiki>
- Every page, image, PDF, presentation, and video

The remote check confirms the branch exists, each raw attachment responds,
and all expected GitHub Wiki page URLs are public.

## 11. Cutover

Only after validation:

1. Add a migration notice to the old Foswiki `WebHome` pointing to the GitHub
   Wiki.
2. Make the old web read-only if the Foswiki administration permits it.
3. Tag the main repository, for example `foswiki-import-2026-09-17`.
4. Record the pull request, main commit, `wiki-docs` commit, and wiki commit in
   the migration ticket.
5. Stop using the conversion publisher for routine wiki editing.

## 12. Rollback

- Before merge: close the main import pull request.
- Before cutover: revert the wiki import commit in a clone of the wiki and
  push `master`.
- For `wiki-docs`: prefer reverting or replacing its marked import commit over
  deleting the branch once any public page has linked to it.
- Do not remove the legacy Foswiki content until the GitHub result has passed
  validation and an agreed retention period.

## 13. Reusing the kit for another Foswiki web

1. Copy this repository skeleton without `Source2026`, `manifests`, or
   `build`.
2. Edit only `migration.conf` first: source web, archive, target repositories,
   branch names, home topic, and default-topic exclusion list.
3. Run the inventory dry-run and reconcile every automatically discovered
   topic and attachment. Add web-specific exclusions only when justified.
4. Run the local candidate pipeline and add web-specific regression checks
   when its structure exposes a new conversion case.
5. Keep improvements generic in `scripts/`; keep web decisions in
   `migration.conf` and the playbook's review notes.
