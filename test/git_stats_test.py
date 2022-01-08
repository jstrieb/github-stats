#!/usr/bin/python3

"""
Prints GitHub repository statistics to console for testing
"""

from asyncio import run, set_event_loop_policy, WindowsSelectorEventLoopPolicy
from aiohttp import ClientSession
from os import getenv

from src.github_repo_stats import GitHubRepoStats
from src.env_vars import EnvironmentVariables

# REQUIRED
ACCESS_TOKEN = getenv("ACCESS_TOKEN")  # or manually enter ACCESS_TOKEN string
GITHUB_ACTOR = getenv("GITHUB_ACTOR")  # or manually enter "<GitHub Username>"

# OPTIONAL
EXCLUDED_REPOS = getenv("EXCLUDED")  # or enter: "<repo>,<repo>,...,<repo>"
EXCLUDED_LANGS = getenv("EXCLUDED_LANGS")  # or enter: "<lang>,...,<lang>"
EXCLUDE_FORKED_REPOS = getenv("EXCLUDE_FORKED_REPOS")  # or enter: "<bool>"
REPO_VIEWS = getenv("REPO_VIEWS")  # or enter: "<int>"
LAST_VIEWED = getenv("LAST_VIEWED")  # or enter: "YYYY-MM-DD"
FIRST_VIEWED = getenv("FIRST_VIEWED")  # or enter: "YYYY-MM-DD"
MAINTAIN_REPO_VIEWS = getenv("SAVE_REPO_VIEWS")  # or enter: "<bool>"
REPO_CLONES = getenv("REPO_CLONES")  # or enter: "<int>"
LAST_CLONED = getenv("LAST_CLONED")  # or enter: "YYYY-MM-DD"
FIRST_CLONED = getenv("FIRST_CLONED")  # or enter: "YYYY-MM-DD"
MAINTAIN_REPO_CLONES = getenv("SAVE_REPO_CLONES")  # or enter: "<bool>"
MORE_COLLABS = getenv("MORE_COLLABS")  # or enter: "<int>"
MORE_REPOS = getenv("MORE_REPOS")  # or enter: "<repo>,<repo>,...,<repo>"


async def main() -> None:
    """
    Used for testing
    """
    if not (ACCESS_TOKEN and GITHUB_ACTOR):
        raise RuntimeError(
            "ACCESS_TOKEN and GITHUB_ACTOR environment variables can't be None"
        )

    async with ClientSession() as session:
        stats = GitHubRepoStats(
            environment_vars=EnvironmentVariables(
                username=GITHUB_ACTOR,
                access_token=ACCESS_TOKEN,
                exclude_repos=EXCLUDED_REPOS,
                exclude_langs=EXCLUDED_LANGS,
                ignore_forked_repos=EXCLUDE_FORKED_REPOS,
                repo_views=REPO_VIEWS,
                repo_last_viewed=LAST_VIEWED,
                repo_first_viewed=FIRST_VIEWED,
                maintain_repo_view_count=MAINTAIN_REPO_VIEWS,
                repo_clones=REPO_CLONES,
                repo_last_cloned=LAST_CLONED,
                repo_first_cloned=FIRST_CLONED,
                maintain_repo_clone_count=MAINTAIN_REPO_CLONES,
                more_collabs=MORE_COLLABS,
                manually_added_repos=MORE_REPOS),
            session=session)
        print(await stats.to_str())


if __name__ == "__main__":
    set_event_loop_policy(WindowsSelectorEventLoopPolicy())
    run(main())
