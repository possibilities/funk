# Funk agent guidance

Funk is the sole owner of AI-stack installation. Keep desktop applications,
command-line agents, globally managed skills, and the personal Art Hack skills
on the single `libexec/install-ai-tools` path. Do not add an installer to
`~/code/arthack` or create another installation or synchronization path.

Treat `~/code/arthack` as the source of truth for the `funk` and `hack` skills.
The Funk installer must refresh their complete installed trees, including
`agents/openai.yaml`, in the shared `~/.agents/skills` directory discovered by
Codex Desktop and in every other configured agent skill location.

After changing Funk's AI tooling, skill installation, or the Art Hack skill
source/manifest integration, run the complete Funk AI installer:

```sh
libexec/install-ai-tools
```

Then compare every installed `funk` and `hack` manifest with its corresponding
Art Hack source manifest. Do not substitute a manual copy or a second helper
for this full-stack convergence check.
