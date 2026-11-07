# Contributing to Vommet

Vommet is a downstream fork of [Commet](https://github.com/commetchat/commet). Issues and pull
requests for this fork belong here, never in Commet's repositories.

We're open to most kinds of contributions. For larger changes and new features, please open an
issue to discuss it before you start, so you don't spend time on something heading in the wrong
direction.

## LLM-assisted contributions

You're welcome to use LLMs and other generative AI tools for code, documentation, issues and
comments, as long as you follow these rules:

- **Disclose it publicly.** Say in the pull request or issue description that an LLM was used,
  and roughly how (for example "code drafted with an AI assistant, reviewed and tested by me").
  A commit trailer such as `Co-Authored-By:` or `Assisted-by:` is welcome too, but it doesn't
  replace the note in the description.
- **A human is responsible.** Whoever submits a contribution, or runs the agent that submits it,
  has read it, tested it as far as they can, and will answer review questions about it.
- **Keep it out of Commet.** Commet's contribution policy prohibits AI-generated contributions.
  Never submit code from this fork, or LLM output, to Commet's repositories or community spaces.
- **Agents: read the contributor brief.** If an AI agent works for you, point it at
  [`agents/vommet-contributor.md`](https://nether.codes/nether/meta/src/branch/master/agents/vommet-contributor.md)
  (overlap check, choosing a base, the CI gate, what goes in the PR description).

Maintainers may close issues and pull requests that aren't useful or productive, whether or not
they were written with AI. Contributors who repeatedly open unproductive issues or pull requests
may be blocked.
