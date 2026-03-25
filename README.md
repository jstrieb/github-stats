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
- Total lines of code modified may be inflated – it counts changes to files like
  `package.json` that may impact the line count in surprising ways
- Only repositories with commit contributions are counted, so if you only open
  an issue on a repo, it will not show up in the statistics
  - Repos you created and own may not be counted if you never commit to them, or
    if the committer email is not connected to your GitHub account


# Installation

TODO


# Support the Project

If this project is useful to you, please support it!

- Star the repository (and follow me on GitHub for more)
- Share and upvote on sites like Twitter, Reddit, and Hacker News
- Report any bugs, glitches, or errors that you find

These things motivate me to keep sharing what I build, and they provide
validation that my work is appreciated! They also help me improve the project.
Thanks in advance!

If you are insistent on spending money to show your support, I encourage you to
instead make a generous donation to one of the following organizations. By
advocating for Internet freedoms, organizations like these help me to feel
comfortable releasing work publicly on the Web.

- [Electronic Frontier Foundation](https://supporters.eff.org/donate/)
- [Signal Foundation](https://signal.org/donate/)
- [Mozilla](https://donate.mozilla.org/en-US/)
- [The Internet Archive](https://archive.org/donate/index.php)


## Project Status

This project is actively maintained, but not actively developed. In other words,
I will fix bugs, but will rarely continue adding features (if at all). If there
are no recent commits, it means that everything has been running smoothly!

If you want to contribute to the project, please open an issue to discuss first.
Pull requests that are not discussed with me ahead of time may be ignored. It's
nothing personal, I'm just busy, and reviewing others' code is not my idea of
fun.

Even if something were to happen to me, and I could not continue to work on the
project, it will continue to work as long as the GitHub API endpoints it uses
remain active and unchanged.


# Related Projects

- Inspired by a desire to improve upon
  [anuraghazra/github-readme-stats](https://github.com/anuraghazra/github-readme-stats)
- Uses [GitHub Octicons](https://primer.style/octicons/) to precisely match the
  GitHub UI
