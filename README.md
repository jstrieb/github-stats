# [GitHub Stats Visualization](https://github.com/jstrieb/github-stats)

<!--
https://github.community/t/support-theme-context-for-images-in-light-vs-dark-mode/147981/84
-->

<div align="center">
<a href="https://github.com/jstrieb/github-stats">
<img src="https://github.com/jstrieb/github-stats/blob/generated/overview.svg#gh-dark-mode-only" />
<img src="https://github.com/jstrieb/github-stats/blob/generated/languages.svg#gh-dark-mode-only" />
<img src="https://github.com/jstrieb/github-stats/blob/generated/overview.svg#gh-light-mode-only" />
<img src="https://github.com/jstrieb/github-stats/blob/generated/languages.svg#gh-light-mode-only" />
</a>
</div>

Generate visualizations of GitHub user and repository statistics with GitHub
Actions. Visualizations can include data from private repositories, and from
repositories you have contributed to, but do not own.

Generated images automatically switch between GitHub light theme and GitHub
dark theme.


## Background

When someone views a GitHub profile, it is often because they are curious about
the user's open source contributions. Unfortunately, that user's stars, forks,
and pinned repositories do not necessarily reflect the contributions they make
to private repositories. The data likewise does not present a complete picture
of the user's total contributions beyond the current year.

This project aims to collect a variety of profile and repository statistics
using the GitHub API. It then generates images that can be displayed in
repository READMEs, or in a user's [Profile
README](https://docs.github.com/en/github/setting-up-and-managing-your-github-profile/managing-your-profile-readme).
It also dumps all statistics to a JSON file that can be used for further data
analysis.

Since this project runs on GitHub Actions, no server is required to regularly
regenerate the images with updated statistics. Likewise, since the user runs the
analysis code themselves via GitHub Actions, they can use their GitHub access
token to collect statistics on private repositories that an external service
would be unable to access.


## Disclaimer

The GitHub statistics API returns inaccurate results in some situations:

- Repository view count statistics often seem too low, and many referring sites
  are not captured
  - If you lack permissions to access the view count for a repository, it will
    be tallied as zero views – this is common for external repositories where
    your only contribution is making a pull request
- Total lines of code modified may be inflated – GitHub counts changes to files like
  `package-lock.json` that may impact the line count in surprising ways
  - On the other hand, GitHub refuses to count lines of code for repositories
    with more than 10,000 commits, so contributions to those will not be
    reflected in the data at all
- Only repositories with commit contributions are counted, so if you only open
  an issue on a repo, it will not show up in the statistics
  - Repos you created and own may not be counted if you never commit to them, or
    if the committer email is not connected to your GitHub account
- [The GitHub API endpoint for computing contributor statistics no longer works
  reliably](https://github.com/orgs/community/discussions/192970), so we compute
  the statistics ourselves by cloning each repository locally and tallying lines
  changed with the `git` CLI
  - Our computed totals likely under-count relative to GitHub's, since theirs
    correctly attribute authorship for contributions to pull requests with
    several authors that end up squashed and merged by just one author

If the calculated numbers seem strange, run the CLI locally and dump JSON output
to determine which repositories are skewing the statistics in unexpected ways.
See [below](#analyzing-the-data) for tips.


## Installation

To make your own statistics images: make a copy of this repository, make a
GitHub API token, add the token to the repository, run the Actions workflow,
and retrieve the images.

1. [Make a "**classic**" personal access token with `read:user` and `repo`
   permissions.](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens)
   1. [Navigate to the personal access tokens (classic)
      page.](https://github.com/settings/tokens) Open that link in a new tab,
      or proceed with the steps below.
      1. Click your avatar in the top right corner, then "Settings" on the menu
         that drops down.
      1. Click "Developer settings" from the menu on the left.
      1. Click "Personal access tokens", then "Tokens (classic)" from the menu
         on the left.
   1. Click "Generate new token" in the top right, then "Generate new token
      (classic)" in the menu that drops down.
   1. Set the expiration date to "none" (unless you want to periodically
      regenerate this key).
   1. Check `repo` and `read:user` permissions.
   1. Click the green "Generate token" button at the bottom.
   1. **Copy the token and save it somewhere.** If you lose it, you will not be
      able to access it again, and will have to regenerate a new one. I keep
      mine saved along with the GitHub entry in my password manager.
   1. Some users report that it can take some time for the personal access
      token to take effect. For more information, see
      [#30](https://github.com/jstrieb/github-stats/issues/30).
1. Create a copy of this repository by clicking
   [here](https://github.com/jstrieb/github-stats/generate).
   - Equivalently, click the big, green "Use this template" button at the top
     left of the page, then click "Create a new repository."
   - Note: this is **not** the same as forking a copy because it copies
     everything fresh, without the huge commit history.
1. Create a new repository secret named `GITHUB_TOKEN` with your personal
   access token from the first step.
   1. [Go to the "New secret" page for your copy of this repository by clicking
      this link.](../../settings/secrets/actions/new)
      - If the link doesn't work, try clicking it from your copy of this
        repository.
      - Alternatively, go to the page manually.
        1. Click "Settings" for your copy of this repository.
        1. Click "Secrets and variables" on the left, then "Actions" from the
           menu that drops down.
        1. Click the green "New repository secret" button on the "Actions
           secrets and variables" page.
   1. Name your secret `GITHUB_TOKEN`.
   1. Paste your personal access token from step 1 into the large "Secret" text
      box.
1. (Optional) Make other secrets for more configuration.
   - To exclude some repositories from the aggregate statistics, add them
     (separated by commas) to a secret called `EXCLUDE_REPOS`.
   - To exclude some languages from the aggregate statistics, add them
     (separated by commas) to a secret called `EXCLUDE_LANGS`.
   - These can also be set directly in [the Actions
     workflow](.github/workflows/main.yml), but you should set them as secrets
     if you want to keep the repository names or languages private.
   - Other configuration options can be set as environment variables or command
     line arguments by directly editing [the Actions
     workflow](.github/workflows/main.yml).
1. Go to the [Actions
   page](../../actions?query=workflow%3A"Generate+Stats+Images") and click "Run
   Workflow" on the right side of the screen to generate images for the first
   time.
   - They automatically regenerate every 24 hours, but they can be manually
     regenerated by running the workflow this way.
1. Take a look at the images that have been created on the [`generated`
   branch](tree/generated/).
   - The [`overview.svg`](tree/generated/overview.svg) file.
   - The [`languages.svg`](tree/generated/languages.svg) file.
1. To add the statistics to your GitHub profile README, copy and paste the
   following lines of code into your markdown content. 
   - Replace `[USERNAME]` in the links below with your own username.
   ``` markdown
   ![](https://github.com/[USERNAME]/github-stats/blob/generated/overview.svg#gh-dark-mode-only)
   ![](https://github.com/[USERNAME]/github-stats/blob/generated/overview.svg#gh-light-mode-only)
   ![](https://github.com/[USERNAME]/github-stats/blob/generated/languages.svg#gh-dark-mode-only)
   ![](https://github.com/[USERNAME]/github-stats/blob/generated/languages.svg#gh-light-mode-only)
   [Created by `jstrieb/github-stats`.](https://github.com/jstrieb/github-stats)
   ```
1. Star this repo if you like it!


## Analyzing the Data

Using the `github-stats` CLI (available on the
[releases](https://github.com/jstrieb/github-stats/releases/latest) page) to
run locally, you can dump raw statistics data to a JSON file using the
`--json-output-file` command line argument. Then, you can import the JSON file
into your programming language of choice and start analyzing. 

My preference is to use [`jq`](https://github.com/jqlang/jq) from the command
line. The command line examples below assume the JSON file is stored in
`stats.json`.


### List all

List all repositories, sorted with most-viewed at the bottom. 

``` bash
jq '.repositories | sort_by(.views) | del(.[].languages)' stats.json
```

In that command, replace `.views` with any other field name (such as
`.lines_changed` or `.stars`) to sort by that field instead. The command
removes the languages field (using `del()`) because it can clutter the output,
making it hard to read.


## Support the Project

If this project is useful to you, please support it!

- Star the repository (and follow me on GitHub for more)
- Share and upvote on sites like Twitter, Reddit, and Hacker News
- Report any bugs, glitches, or errors that you find
- [Check out my other projects](https://jstrieb.github.io/projects/)

These things motivate me to keep sharing what I build, and they provide
validation that my work is appreciated! They also help me improve the project.
Thanks in advance!

If you are insistent on spending money to show your support, I encourage you to
instead make a generous donation to one of the following organizations.

- [Electronic Frontier Foundation](https://supporters.eff.org/donate/)
- [Signal Foundation](https://signal.org/donate/)
- [Mozilla](https://donate.mozilla.org/en-US/)
- [The Internet Archive](https://archive.org/donate/index.php)


## Project Status

This project is actively maintained, but not actively developed. In other
words, I will fix bugs, but will rarely add features (if at all). If there are
no recent commits, it means that everything has been running smoothly!

GitHub's APIs often have unexpected errors, downtime, and strange,
intermittent, undocumented behavior. Issues generating statistics images often
resolve themselves within a day or two, without any changes to this code or
repository.

If you want to contribute to the project, please open an issue and discuss
first. Pull requests that are not discussed with me ahead of time may be
ignored. It's nothing personal, I'm just busy, and reviewing others' code is
nowhere near as fun as working on other projects.

Even if something were to happen to me, and I could not continue to work on the
project, it will continue to work as long as the GitHub API endpoints it uses
remain active and unchanged.


## Related Projects

- Inspired by a desire to improve upon
  [anuraghazra/github-readme-stats](https://github.com/anuraghazra/github-readme-stats)
- Uses [GitHub Octicons](https://primer.style/octicons/) to precisely match the
  GitHub UI
