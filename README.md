# GitHub Stats Visualization

Generate visualizations of GitHub user and repository statistics using GitHub
Actions.

## Background

When someone views a profile on GitHub, it is often because they are curious
about a user's open source projects and contributions. Unfortunately, that
user's stars, forks, and pinned repositories to not necessarily reflect the
contributions they make to private repositories. The data likewise does not
present a complete picture of the user's total contributions beyond the current
year.

This project aims to collect a variety of profile and repository statistics
using the GitHub API. It then generates images that can be displayed in
repository READMEs, or in a user's [Profile
README](https://docs.github.com/en/github/setting-up-and-managing-your-github-profile/managing-your-profile-readme)

# Installation

<details>

<summary>

Click here to view installation instructions

</summary>

<!-- TODO -->
TODO

</details>

## Notes

- Must use a personal access token, not the default GitHub Actions token
- Personal access token must have permissions: `read:user` and `repo`

# Examples

- Stats overview

  ![](https://github.com/jstrieb/github-stats/blob/master/generated/overview.svg)

- Languages overview

  ![](https://github.com/jstrieb/github-stats/blob/master/generated/languages.svg)

<details>

<summary>

Click here to see additional examples

</summary>

- More to come later

</details>

# Related Projects

- Inspired by a desire to improve upon
  [anuraghazra/github-readme-stats](https://github.com/anuraghazra/github-readme-stats)
