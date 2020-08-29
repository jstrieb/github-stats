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
   Personal access token must have permissions: `read:user` and `repo`. Copy
   the access token when it is generated – if you lose it, you will have to
   regenerate the token.
2. Fork the repository.
3. Go to the "Settings" tab of the fork and go to the "Secrets" page (bottom
   left). Create a new secret with the name `ACCESS_TOKEN` and paste the copied
   personal access token as the value.
4. Go to the "Actions" tab of the fork and hit the big green button to enable
   Actions.
5. Commit a small change to the repo (for example remove a newline from the end
   of the README) to force it to regenerate the stats images.
6. Check out the images that have been created in the `generated` folder.
5. Star this repo if you like it!

</details>

# Examples

- Stats overview

  ![](https://github.com/jstrieb/github-stats/blob/master/generated/overview.svg)

- Languages overview

  ![](https://github.com/jstrieb/github-stats/blob/master/generated/languages.svg)

# Related Projects

- Inspired by a desire to improve upon
  [anuraghazra/github-readme-stats](https://github.com/anuraghazra/github-readme-stats)
- Makes use of [GitHub Octicons](https://primer.style/octicons/) to precisely
  match the GitHub UI
