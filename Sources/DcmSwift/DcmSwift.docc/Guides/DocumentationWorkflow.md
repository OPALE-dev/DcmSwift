# Documentation Workflow

Keep the repository, DocC, and the Pages sites consistent by editing source
documentation rather than generated HTML.

## Sources of truth

- Public API reference belongs in `///` comments beside the Swift declaration.
- Conceptual guides and qualification documents belong in `DcmSwift.docc`.
- Every executable target has a short `README.md` for repository browsers and a
  complete article under `DcmSwift.docc/Commands`.
- Command option names and defaults come from the executable's `--help` output.
- Generated HTML belongs below `.build` or in the CI `public` artifact and is
  never committed.

Use ordinary Markdown links for paths that must also work on GitHub and
GitLab. Use DocC `<doc:ArticleName>` links for catalog navigation and double
backticks only when linking to API symbols.

## Preview and validation

Preview the primary documentation while editing:

```sh
Scripts/documentation/preview.sh
```

Build the static site with warnings treated as errors:

```sh
Scripts/documentation/build.sh .build/documentation DcmSwift
```

The second argument is the hosting base path. Omit it for a site served at the
domain root.

## Publishing

GitLab CI and GitHub Actions both invoke `build.sh`; only their deployment
steps and hosting base paths differ. Merge requests and pull requests build the
site without publishing it. The default branch publishes it through Pages.
