# Repo optimisations for faster delivery

The factory never merges by itself. An approved PR is marked ready, labelled
`factory:approved`, and then merged however the target repo already works.
How quickly approved work lands is therefore up to the repo's own settings.
These are the settings worth considering, roughly in order, with what each
one costs.

## 1. Require CI before merging

Use a branch ruleset (or branch protection) on the default branch that
requires a pull request and your CI status checks.

- **Gain:** nothing reaches the default branch without green CI, whoever or
  whatever merges it. This is what makes the later steps safe.
- **Cost:** none worth mentioning, if CI is reasonably fast.

## 2. Auto-merge approved factory PRs once CI passes

Turn on **Allow auto-merge** in the repo settings, then add a small workflow
that enables auto-merge when the factory approves a PR:

```yaml
# .github/workflows/factory-auto-merge.yml
on:
  pull_request:
    types: [labeled]
jobs:
  auto-merge:
    if: >-
      github.event.label.name == 'factory:approved' &&
      github.event.sender.login == vars.FACTORY_ACCOUNT
    runs-on: ubuntu-latest
    steps:
      - run: gh pr merge --auto --squash "$PR"
        env:
          PR: ${{ github.event.pull_request.html_url }}
          GH_TOKEN: ${{ secrets.FACTORY_MERGE_TOKEN }}
```

- **Gain:** approved work merges as soon as CI is green, with no one
  watching.
- **Cost:** the factory's approval becomes the last check before the default
  branch. Only do this once its approvals have earned your trust. The board
  and the self-audit's run history help you judge that.
- **Check who applied the label.** Anyone with triage access can add a label.
  The `sender` condition makes the workflow act only on labels applied by the
  account the factory runs as, set in the `FACTORY_ACCOUNT` repo variable.
- **Use a token that triggers workflows.** Merges made with the default
  `GITHUB_TOKEN` don't start other workflows. A release workflow that runs on
  pushes to the default branch, such as semantic-release, would silently skip
  factory merges. Use a GitHub App token or a fine-grained token instead.

## 3. Ask for human review only where it matters

GitHub never lets a PR's author approve their own PR. The factory opens PRs
as the account it runs as, so any required approval has to come from someone
else.

- **Required approvals = 1 or more:** every factory PR waits for a person.
  This is the safest setting and the slowest, because a human is back in the
  loop for everything.
- **Required approvals = 0, plus code owners:** list the risky paths
  (authentication, migrations, payments, CI) in `CODEOWNERS`, and require
  code owner review. With rulesets, you can set required approvals to 0 and
  still require code owner review, so only PRs touching those paths wait for
  a person.
- **Dismiss stale approvals when new commits are pushed**, so a human
  approval always covers the code that actually merges.

## 4. Merge queue, if you run several jobs in parallel

With several factory jobs landing at once, each PR may pass CI against a base
that has since moved. A merge queue re-tests each PR on top of the latest
default branch before merging it, where your plan and repo support it.

- **Gain:** no broken default branch from PRs that each passed on their own.
- **Cost:** extra CI runs, and a little more latency per merge.

Without a merge queue, **Require branches to be up to date** gives the same
safety, but each PR has to be updated and re-tested by hand, or by automation,
whenever another merges first.

## 5. Housekeeping

- **Squash merging only**, with the PR title as the default commit message,
  so each factory PR becomes one commit in your commit convention.
- **Automatically delete head branches** after merge, so factory branches
  don't pile up.
