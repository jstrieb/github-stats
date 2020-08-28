# GitHub Stats Visualization

Generate visualizations of GitHub user and repository statistics using GitHub
Actions.

This project is currently a work-in-progress; there will always be more
interesting stats to display.

## Background

When someone views a profile on GitHub, it is often because they are curious
about a user's open source projects and contributions. Unfortunately, that
user's stars, forks, and pinned repositories do not necessarily reflect the
contributions they make to private repositories. The data likewise does not
present a complete picture of the user's total contributions beyond the current
year.

This project aims to collect a variety of profile and repository statistics
using the GitHub API. It then generates images that can be displayed in
repository READMEs, or in a user's [Profile
README](https://docs.github.com/en/github/setting-up-and-managing-your-github-profile/managing-your-profile-readme).

Since the project runs on GitHub Actions, no server is required to regularly
regenerate the images with updated statistics. Likewise, since the user runs
the analysis code themselves via GitHub Actions, they can use their GitHub
access token to collect statistics on private repositories that an external
service would be unable to access.

# Installation

<details>

<summary> Click here to view installation instructions </summary>

<!-- TODO: Add details and screenshots -->

1. Create a personal access token (not the default GitHub Actions token) using
   the instructions
   [here](https://docs.github.com/en/github/authenticating-to-github/creating-a-personal-access-token).
   Personal access token must have permissions: `read:user` and `repo`
2. Fork the repository
3. Add a GitHub secret with the personal access token
4. Star this repo if you like it!

</details>

# Examples

- Stats overview

  ![](https://github.com/jstrieb/github-stats/blob/master/generated/overview.svg)

- Languages overview

  ![](https://github.com/jstrieb/github-stats/blob/master/generated/languages.svg)

# Related Projects

- Inspired by a desire to improve upon
  [anuraghazra/github-readme-stats](https://github.com/anuraghazra/github-readme-stats)
