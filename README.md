# [GitHub Stats Visualization](https://github.com/jstrieb/github-stats)

<!--
https://github.community/t/support-theme-context-for-images-in-light-vs-dark-mode/147981/84
-->
Generate visualizations of GitHub user and repository statistics with GitHub
Actions. Visualizations can include data from private repositories, and from
repositories you have contributed to, but do not own.

Generated images automatically switch between GitHub light theme and GitHub
dark theme.

<div align="center">
<a href="https://github.com/jstrieb/github-stats">
<img src="https://github.com/jstrieb/github-stats/blob/generated/overview.svg#gh-dark-mode-only" />
<img src="https://github.com/jstrieb/github-stats/blob/generated/languages.svg#gh-dark-mode-only" />
<img src="https://github.com/jstrieb/github-stats/blob/generated/overview.svg#gh-light-mode-only" />
<img src="https://github.com/jstrieb/github-stats/blob/generated/languages.svg#gh-light-mode-only" />
</a>
</div>

## Background

When someone views a GitHub profile, it is often because they are curious about
the user's open-source contributions. Unfortunately, that user's stars, forks,
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
<details>

<summary>The GitHub statistics API returns inaccurate results in some situations</summary>

Total lines of code modified may be too high or too low
  - GitHub counts changes to files like `package-lock.json` that may inflate the
    line count in surprising ways
  - On the other hand, GitHub refuses to count lines of code for repositories
    with more than 10,000 commits, so contributions to those will not be
    reflected in the data at all
  - [The GitHub API endpoint for computing contributor statistics no longer
    works reliably](https://github.com/orgs/community/discussions/192970), so we
    fall back on computing the statistics ourselves by cloning each repository
    locally and tallying lines changed with the `git` CLI
    - Our computed totals likely under-count relative to GitHub's, since theirs
      correctly attribute authorship for contributions to pull requests with
      several authors that end up squashed and merged by just one author
    - They also correctly attribute commits we may miss if they are made with
      old email addresses no longer connected to the account
</details>

<details>

<summary>Repository view count statistics often seem too low, and many referring sites
  are not captured</summary>

If you lack permissions to access the view count for a repository, it will
    be tallied as zero views – this is common for external repositories where
    your only contribution is making a pull request
</details>

<details>

<summary>Only repositories with commit contributions are counted, so if you only open
  an issue on a repo, it will not show up in the statistics</summary>

Repos you created and own may not be counted if you never commit to them, or
    if the committer email is not connected to your GitHub account
</details>


If the calculated numbers seem strange, run the CLI locally and dump JSON output
to determine which repositories are skewing the statistics in unexpected ways.
See [below](#analyzing-the-data) for tips.


## Installation

There are 3 ways to choose. No matter which way, you need to set the `ACCESS_TOKEN`.


<details>
<summary><strong>If you don’t want to have extra code to generate images in your 
warehouse, and there is no need to build with the latest code on the master branch.
</strong></summary>
You can use the following code in your repository to run automatically. It will
  download the latest precompiled version of github-stats to generate images.


```yml
name: Generate Stats Images By Download

on:
  push:
    branches: 
      - master
  schedule:
    - cron: "5 0 * * *"
  workflow_dispatch:

permissions:
  contents: write

defaults:
  run:
    shell: bash -euxo pipefail {0}

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v6

    - name: Downloads latest github-stats
      run: |
        mkdir -p zig-out/bin
        curl --location --output 'zig-out/bin/github-stats' 'https://github.com/jstrieb/github-stats/releases/latest/download/github-stats_x86_64-linux'
        sudo chmod +x zig-out/bin/github-stats

    - name: Checkout history branch
      run: |
        git config --global user.name "jstrieb/github-stats"
        git config --global user.email "github-stats[bot]@jstrieb.github.io"
        # Push generated files to the generated branch
        git pull
        git checkout generated || git checkout -b generated

    - name: Generate images
      run: |
        ./zig-out/bin/github-stats
      env:
        ACCESS_TOKEN: ${{ secrets.ACCESS_TOKEN }}
        EXCLUDE_REPOS: ${{ secrets.EXCLUDE_REPOS }}
        EXCLUDE_LANGS: ${{ secrets.EXCLUDE_LANGS }}
        EXCLUDE_PRIVATE: "false"
        DEBUG: "false"
        # TODO: Remove this when they get their API working again
        # https://github.com/orgs/community/discussions/192970
        MAX_RETRIES: 5

    - name: Commit to the repo
      run: |
        git add .
        # Force the build to succeed, even if no files were changed
        git commit -m 'Update generated files' || true
        git push --set-upstream origin generated
```
</details>

<details>
<summary><strong>You don’t want to add build code to your repository, but you
  want to use the latest code to generate images.
</strong></summary>
You can use the following code in your repository to run automatically. 
  It will clone the latest code from the master branch to build github-stats
  and generate images.


```yml
name: Generate Stats Images By Clone And Build

on:
  push:
    branches:
      - master
  schedule:
    - cron: "5 0 * * *"
  workflow_dispatch:

permissions:
  contents: write

defaults:
  run:
    shell: bash -euxo pipefail {0}

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
        with:
          fetch-depth: 0

      - uses: mlugg/setup-zig@d1434d08867e3ee9daa34448df10607b98908d29
        with:
          version: 0.15.2

      - name: Clone and build github-stats
        run: |
          git clone --depth=1 --branch master https://github.com/jstrieb/github-stats.git
          cd github-stats
          zig build --release
          cp zig-out/bin/github-stats ../github-stats-bin

      - name: Checkout history branch
        run: |
          git config --global user.name "jstrieb/github-stats"
          git config --global user.email "github-stats[bot]@jstrieb.github.io"
          git fetch origin generated:generated || true
          git checkout generated || git checkout --orphan generated

      - name: Generate images
        run: |
          ./github-stats-bin
        env:
          ACCESS_TOKEN: ${{ secrets.ACCESS_TOKEN }}
          EXCLUDE_REPOS: ${{ secrets.EXCLUDE_REPOS }}
          EXCLUDE_LANGS: ${{ secrets.EXCLUDE_LANGS }}
          EXCLUDE_PRIVATE: "false"
          DEBUG: "false"
          MAX_RETRIES: "5"

      - name: Commit to the repo
        run: |
          git add .
          git commit -m 'Update generated files' || true
          git push --set-upstream origin generated
```
</details>

<details open>
<summary><strong>To make your own statistics images: make a copy of this repository, make a
GitHub API token, add the token to the repository, run the Actions workflow,
and retrieve the images.</strong></summary>

##### 1. Create a Personal Access Token
First, create a **classic** GitHub personal access token.
Go to:
- https://github.com/settings/tokens
Then:
1. Click **Generate new token**
2. Select **Generate new token (classic)**
3. Set the expiration to **No expiration**
4. Enable these permissions:
   - read:user
   - user:email
   - repo

#### Why these permissions are needed

- read:user and repo are used to read user and repository metadata
- user:email is used to correctly match commits

> Save your token somewhere safe. You will not be able to see it again.

##### 2. Create Your Own Copy of This Repository

Use this template:

- https://github.com/jstrieb/github-stats/generate

Or:

1. Click "Use this template"
2. Create a new repository

##### 3. Add the Token as a Repository Secret
Go to:
Settings → Secrets and variables → Actions → New repository secret
Create:
Name: `ACCESS_TOKEN` 
Value: your token


##### 4. Optional Configuration

- Exclude repositories
Create secret: `EXCLUDE_REPOS`  
Example: repo1,repo2,user/*

- Exclude languages
Create secret:`EXCLUDE_LANGS`  
Example: Html,CSS

##### 5. Run the Workflow
Go to:
Actions → Generate Stats Images
Click:
Run workflow

##### 6. Find Generated Images
Check branch: generated  
Files:  
- overview.svg
- languages.svg

##### 7. Add to README

Replace [USERNAME]:

```md
![](https://github.com/[USERNAME]/github-stats/blob/generated/overview.svg#gh-dark-mode-only)
![](https://github.com/[USERNAME]/github-stats/blob/generated/overview.svg#gh-light-mode-only)
![](https://github.com/[USERNAME]/github-stats/blob/generated/languages.svg#gh-dark-mode-only)
![](https://github.com/[USERNAME]/github-stats/blob/generated/languages.svg#gh-light-mode-only)
```

</details>


## Analyzing the Data

Using the `github-stats` CLI (available on the
[releases](https://github.com/jstrieb/github-stats/releases/latest) page) to
run locally, you can dump raw statistics data to a JSON file using the
`--json-output-file` command-line argument. 

``` bash
# Instructions for Linux. Change the filename at the end of the URL for macOS.
sudo curl \
    --location \
    --output '/usr/local/bin/github-stats' \
    'https://github.com/jstrieb/github-stats/releases/latest/download/github-stats_x86_64-linux'
sudo chmod +x /usr/local/bin/github-stats

github-stats --version

github-stats --access-token [YOUR API KEY] --json-output-file stats.json --debug
```

Then, you can import the JSON file into your programming language of choice and
start analyzing. My preference is to use [`jq`](https://github.com/jqlang/jq)
from the command line. The examples below assume the JSON file is stored in
`stats.json`.


### List All

List all repositories, sorted with most-viewed at the bottom.

``` bash
jq '.repositories | sort_by(.views) | del(.[].languages)' stats.json
```

In that command, replace `.views` with any other field name (such as
`.lines_changed` or `.stars`) to sort by that field instead. The command
removes the languages field (using `del()`) because it can clutter the output,
making it hard to read.


### List Languages

List all languages, sorted with most-used at the bottom.

``` bash
jq --raw-output '
  [.repositories[].languages[]] 
    | group_by(.name) 
    | sort_by([.[].size] | add) 
    | .[] 
    | "\(.[0].name): \([.[].size] | add)"
' stats.json
```


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
