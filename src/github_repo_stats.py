#!/usr/bin/python3

from typing import Dict, Optional, Set, Tuple, Any, cast
from aiohttp import ClientSession
from datetime import date, timedelta

from src.env_vars import EnvironmentVariables
from src.github_api_queries import GitHubApiQueries

###############################################################################
# GitHubRepoStats class
###############################################################################


class GitHubRepoStats(object):
    """
    Retrieve and store statistics about GitHub usage.
    """

    __DATE_FORMAT = '%Y-%m-%d'

    def __init__(self,
                 environment_vars: EnvironmentVariables,
                 session: ClientSession):
        self.environment_vars: EnvironmentVariables = environment_vars
        self.queries = GitHubApiQueries(
            username=self.environment_vars.username,
            access_token=self.environment_vars.access_token,
            session=session)

        self._name: Optional[str] = None
        self._stargazers: Optional[int] = None
        self._forks: Optional[int] = None
        self._total_contributions: Optional[int] = None
        self._languages: Optional[Dict[str, Any]] = None
        self._repos: Optional[Set[str]] = None
        self._users_lines_changed: Optional[Tuple[int, int]] = None
        self._total_lines_changed: Optional[Tuple[int, int]] = None
        self._contributions_percentage: Optional[str] = None
        self._avg_percent: Optional[str] = None
        self._views: Optional[int] = None
        self._clones: Optional[int] = None
        self._collaborators: Optional[int] = None
        self._contributors: Optional[Set[str]] = None
        self._views_from_date: Optional[str] = None
        self._clones_from_date: Optional[str] = None
        self._pull_requests: Optional[int] = None
        self._issues: Optional[int] = None
        self._empty_repos: Optional[Set[str]] = None

    async def to_str(self) -> str:
        """
        :return: summary of all available statistics
        """
        languages = await self.languages_proportional
        formatted_languages = "\n\t\t\t- ".join(
            [f"{k}: {v:0.4f}%" for k, v in languages.items()]
        )

        users_lines_changed = await self.lines_changed
        total_lines_changed = self._total_lines_changed

        if users_lines_changed[0] > 0:
            prcnt_added = users_lines_changed[0] / total_lines_changed[0] * 100
        else:
            prcnt_added = 0.0

        if users_lines_changed[1] > 0:
            prcnt_dltd = users_lines_changed[1] / total_lines_changed[1] * 100
        else:
            prcnt_dltd = 0.0
        ttl_prcnt = await self.contributions_percentage
        avg_prcnt = await self.avg_contribution_percent

        contribs = max(len(await self.contributors) - 1, 0)

        return f"""GitHub Repository Statistics:
        Stargazers: {await self.stargazers:,}
        Forks: {await self.forks:,}
        Pull requests: {await self.pull_requests:,}
        Issues: {await self.issues:,}
        All-time contributions: {await self.total_contributions:,}
        Repositories with contributions: {len(await self.repos):,}
        Lines of code added: {users_lines_changed[0]:,}
        Lines of code deleted: {users_lines_changed[1]:,}
        Lines of code changed: {sum(users_lines_changed):,}
        Percentage of total code line additions: {prcnt_added:0.2f}%
        Percentage of total code line deletions: {prcnt_dltd:0.2f}%
        Percentage of code change contributions: {ttl_prcnt}
        Avg. % of code change contributions: {avg_prcnt}
        Project page views: {await self.views:,}
        Project page views from date: {await self.views_from_date}
        Project repository clones: {await self.clones:,}
        Project repository clones from date: {await self.clones_from_date}
        Project repository collaborators: {await self.collaborators:,}
        Project repository contributors: {contribs:,}
        Languages:\n\t\t\t- {formatted_languages}"""

    async def is_repo_name_invalid(self, repo_name) -> bool:
        """
        Determines a repo name invalid if:
            - repo is already scraped and the name is in the list
            - repo name is not included in and only_include_repos is being used
            - repo name is included in exclude_repos
        :param repo_name: the name of the repo in owner/name format
        :return: True if repo is not to be included in self._repos
        """
        return repo_name in self._repos \
            or len(self.environment_vars.only_included_repos) > 0 \
            and repo_name not in self.environment_vars.only_included_repos \
            or repo_name in self.environment_vars.exclude_repos

    async def is_repo_type_excluded(self, repo_data) -> bool:
        """
        Determines a repo type excluded if:
            - repo is a fork and forked repos are not being included
            - repo is archived and archived repos are being excluded
            - repo is private and private repos are being excluded
            - repo is public and public repos are being excluded
        :param repo_data: repo data returned from API fetch
        :return: True if repo type is not to be included in self._repos
        """
        return not self.environment_vars.include_forked_repos \
            and (repo_data.get("isFork")
                 or repo_data.get("fork")) \
            or self.environment_vars.exclude_archive_repos \
            and (repo_data.get("isArchived")
                 or repo_data.get("archived")) \
            or self.environment_vars.exclude_private_repos \
            and (repo_data.get("isPrivate")
                 or repo_data.get("private")) \
            or self.environment_vars.exclude_public_repos \
            and (not repo_data.get("isPrivate")
                 or not repo_data.get("private"))

    async def get_stats(self) -> None:
        """
        Get lots of summary stats using one big query. Sets many attributes
        """
        self._stargazers = 0
        self._forks = 0
        self._languages = dict()
        self._repos = set()
        self._empty_repos = set()

        next_owned = None
        next_contrib = None

        while True:
            raw_results = await self.queries.query(
                GitHubApiQueries.repos_overview(owned_cursor=next_owned,
                                                contrib_cursor=next_contrib)
            )
            raw_results = raw_results if raw_results is not None else {}

            self._name = raw_results\
                .get("data", {})\
                .get("viewer", {})\
                .get("name", None)

            if self._name is None:
                self._name = (raw_results
                              .get("data", {})
                              .get("viewer", {})
                              .get("login", "No Name"))

            contrib_repos = (raw_results
                             .get("data", {})
                             .get("viewer", {})
                             .get("repositoriesContributedTo", {}))

            owned_repos = (raw_results
                           .get("data", {})
                           .get("viewer", {})
                           .get("repositories", {}))

            repos = owned_repos.get("nodes", [])
            if not self.environment_vars.exclude_contrib_repos:
                repos += contrib_repos.get("nodes", [])

            for repo in repos:
                if not repo or await self.is_repo_type_excluded(repo):
                    continue

                name = repo.get("nameWithOwner")
                if await self.is_repo_name_invalid(name):
                    continue
                self._repos.add(name)

                self._stargazers += repo.get("stargazers").get("totalCount", 0)
                self._forks += repo.get("forkCount", 0)

                if repo.get("isEmpty"):
                    self._empty_repos.add(name)
                    continue

                for lang in repo.get("languages", {}).get("edges", []):
                    name = lang.get("node", {}).get("name", "Other")
                    languages = await self.languages

                    if name in self.environment_vars.exclude_langs:
                        continue

                    if name in languages:
                        languages[name]["size"] += lang.get("size", 0)
                        languages[name]["occurrences"] += 1
                    else:
                        languages[name] = {
                            "size": lang.get("size", 0),
                            "occurrences": 1,
                            "color": lang.get("node", {}).get("color"),
                        }

            is_cur_owned = owned_repos\
                .get("pageInfo", {})\
                .get("hasNextPage", False)
            is_cur_contrib = contrib_repos\
                .get("pageInfo", {})\
                .get("hasNextPage", False)

            if is_cur_owned or is_cur_contrib:
                next_owned = owned_repos\
                    .get("pageInfo", {})\
                    .get("endCursor", next_owned)
                next_contrib = contrib_repos\
                    .get("pageInfo", {})\
                    .get("endCursor", next_contrib)
            else:
                break

        if not self.environment_vars.exclude_contrib_repos:
            env_repos = self.environment_vars.manually_added_repos
            lang_cols = self.queries.get_language_colors()

            for repo in env_repos:
                if await self.is_repo_name_invalid(repo):
                    continue
                self._repos.add(repo)

                repo_stats = await self.queries.query_rest(f"/repos/{repo}")
                if await self.is_repo_type_excluded(repo_stats):
                    continue

                self._stargazers += repo_stats.get("stargazers_count", 0)
                self._forks += repo_stats.get("forks", 0)

                if repo_stats.get("size") == 0:
                    self._empty_repos.add(repo)
                    continue

                if repo_stats.get("language"):
                    langs = await self.queries.\
                        query_rest(f"/repos/{repo}/languages")

                    for lang, size in langs.items():
                        languages = await self.languages

                        if lang in self.environment_vars.exclude_langs:
                            continue

                        if lang in languages:
                            languages[lang]["size"] += size
                            languages[lang]["occurrences"] += 1
                        else:
                            languages[lang] = {
                                "size": size,
                                "occurrences": 1,
                                "color": lang_cols.get(lang).get("color")
                            }

        # TODO: Improve languages to scale by number of contributions to
        #       specific filetypes
        langs_total = sum([v.get("size", 0) for v in self._languages.values()])
        for k, v in self._languages.items():
            v["prop"] = 100 * (v.get("size", 0) / langs_total)

    @property
    async def name(self) -> str:
        """
        :return: GitHub user's name
        """
        if self._name is not None:
            return self._name
        await self.get_stats()
        assert self._name is not None
        return self._name

    @property
    async def stargazers(self) -> int:
        """
        :return: total number of stargazers on user's repos
        """
        if self._stargazers is not None:
            return self._stargazers
        await self.get_stats()
        assert self._stargazers is not None
        return self._stargazers

    @property
    async def forks(self) -> int:
        """
        :return: total number of forks on user's repos
        """
        if self._forks is not None:
            return self._forks
        await self.get_stats()
        assert self._forks is not None
        return self._forks

    @property
    async def languages(self) -> Dict:
        """
        :return: summary of languages used by the user
        """
        if self._languages is not None:
            return self._languages
        await self.get_stats()
        assert self._languages is not None
        return self._languages

    @property
    async def languages_proportional(self) -> Dict:
        """
        :return: summary of languages used by the user, with proportional usage
        """
        if self._languages is None:
            await self.get_stats()
            assert self._languages is not None
        return {k: v.get("prop", 0) for (k, v) in self._languages.items()}

    @property
    async def repos(self) -> Set[str]:
        """
        :return: list of names of user's repos
        """
        if self._repos is not None:
            return self._repos
        await self.get_stats()
        assert self._repos is not None
        return self._repos

    @property
    async def total_contributions(self) -> int:
        """
        :return: count of user's total contributions as defined by GitHub
        """
        if self._total_contributions is not None:
            return self._total_contributions
        self._total_contributions = 0

        years = ((await self.queries.query(GitHubApiQueries
                                           .contributions_all_years()))
                 .get("data", {})
                 .get("viewer", {})
                 .get("contributionsCollection", {})
                 .get("contributionYears", []))

        by_year = ((await self.queries.query(GitHubApiQueries
                                             .all_contributions(years)))
                   .get("data", {})
                   .get("viewer", {})
                   .values())

        for year in by_year:
            self._total_contributions += year\
                .get("contributionCalendar", {})\
                .get("totalContributions", 0)
        return cast(int, self._total_contributions)

    @property
    async def lines_changed(self) -> Tuple[int, int]:
        """
        Fetches total lines added and deleted for user and repository total
        Calculates total and average line changes for user
        Calculates total contributors
        :return: count of total lines added, removed, or modified by the user
        """
        if self._users_lines_changed is not None:
            return self._users_lines_changed
        contributor_set = set()
        total_additions = 0
        total_deletions = 0
        additions = 0
        deletions = 0
        total_percentage = 0

        for repo in await self.repos:
            if repo in self._empty_repos:
                continue
            repo_total_changes = 0
            author_total_changes = 0

            r = await self.queries\
                .query_rest(f"/repos/{repo}/stats/contributors")

            for author_obj in r:
                # Handle malformed response from API by skipping this repo
                if not isinstance(author_obj, dict) or not isinstance(
                        author_obj.get("author", {}), dict
                ):
                    continue
                author = author_obj.get("author", {}).get("login", "")
                contributor_set.add(author)

                if author != self.environment_vars.username:
                    for week in author_obj.get("weeks", []):
                        total_additions += week.get("a", 0)
                        total_deletions += week.get("d", 0)
                        repo_total_changes += week.get("a", 0)
                        repo_total_changes += week.get("d", 0)
                else:
                    for week in author_obj.get("weeks", []):
                        additions += week.get("a", 0)
                        deletions += week.get("d", 0)
                        author_total_changes += week.get("a", 0)
                        author_total_changes += week.get("d", 0)

            repo_total_changes += author_total_changes
            if author_total_changes > 0:
                total_percentage += author_total_changes / repo_total_changes
        if total_percentage > 0:
            total_percentage /= len(self._repos) - len(self._empty_repos)
        else:
            total_percentage = 0.0
        self._avg_percent = f"{total_percentage * 100:0.2f}%"

        total_additions += additions
        total_deletions += deletions
        self._users_lines_changed = (additions, deletions)
        self._total_lines_changed = (total_additions, total_deletions)

        if sum(self._users_lines_changed) > 0:
            ttl_changes = sum(self._total_lines_changed)
            user_changes = sum(self._users_lines_changed)
            percent_contribs = user_changes / ttl_changes * 100
        else:
            percent_contribs = 0.0
        self._contributions_percentage = f"{percent_contribs:0.2f}%"

        self._contributors = contributor_set

        return self._users_lines_changed

    @property
    async def contributions_percentage(self) -> str:
        """
        :return: str representing the percentage of user's repo contributions
        """
        if self._contributions_percentage is not None:
            return self._contributions_percentage
        await self.lines_changed
        assert self._contributions_percentage is not None
        return self._contributions_percentage

    @property
    async def avg_contribution_percent(self) -> str:
        """
        :return: str representing the avg percent of user's repo contributions
        """
        if self._avg_percent is not None:
            return self._avg_percent
        await self.lines_changed
        assert self._avg_percent is not None
        return self._avg_percent

    @property
    async def views(self) -> int:
        """
        Note: API returns a user's repository view data for the last 14 days.
        This counts views as of the initial date this code is first run in repo
        :return: view count of user's repositories as of a given (first) date
        """
        if self._views is not None:
            return self._views

        last_viewed = self.environment_vars.repo_last_viewed
        today = date.today().strftime(self.__DATE_FORMAT)
        yesterday = (date.today() - timedelta(1)).strftime(self.__DATE_FORMAT)
        dates = {last_viewed, yesterday}

        today_view_count = 0
        for repo in await self.repos:
            r = await self.queries.query_rest(f"/repos/{repo}/traffic/views")

            for view in r.get("views", []):
                if view.get("timestamp")[:10] == today:
                    today_view_count += view.get("count", 0)
                elif view.get("timestamp")[:10] > last_viewed:
                    self.environment_vars.set_views(view.get("count", 0))
                    dates.add(view.get("timestamp")[:10])

        if last_viewed == "0000-00-00":
            dates.remove(last_viewed)

        if self.environment_vars.store_repo_view_count:
            self.environment_vars.set_last_viewed(yesterday)

            if self.environment_vars.repo_first_viewed == "0000-00-00":
                self.environment_vars.repo_first_viewed = min(dates)
            self.environment_vars. \
                set_first_viewed(self.environment_vars.repo_first_viewed)
            self._views_from_date = self.environment_vars.repo_first_viewed
        else:
            self._views_from_date = min(dates)

        self._views = self.environment_vars.repo_views + today_view_count
        return self._views

    @property
    async def views_from_date(self) -> str:
        """
        :return: the first date included in the repo view count
        """
        if self._views_from_date is not None:
            return self._views_from_date
        await self.views
        assert self._views_from_date is not None
        return self._views_from_date

    @property
    async def clones(self) -> int:
        """
        Note: API returns a user's repository clone data for the last 14 days.
        This counts clones as of the initial date the code is first run in repo
        :return: clone count of user's repositories as of a given (first) date
        """
        if self._clones is not None:
            return self._clones

        last_cloned = self.environment_vars.repo_last_cloned
        today = date.today().strftime(self.__DATE_FORMAT)
        yesterday = (date.today() - timedelta(1)).strftime(self.__DATE_FORMAT)
        dates = {last_cloned, yesterday}

        today_clone_count = 0
        for repo in await self.repos:
            r = await self.queries.query_rest(f"/repos/{repo}/traffic/clones")

            for clone in r.get("clones", []):
                if clone.get("timestamp")[:10] == today:
                    today_clone_count += clone.get("count", 0)
                elif clone.get("timestamp")[:10] > last_cloned:
                    self.environment_vars.set_clones(clone.get("count", 0))
                    dates.add(clone.get("timestamp")[:10])

        if last_cloned == "0000-00-00":
            dates.remove(last_cloned)

        if self.environment_vars.store_repo_clone_count:
            self.environment_vars.set_last_cloned(yesterday)

            if self.environment_vars.repo_first_cloned == "0000-00-00":
                self.environment_vars.repo_first_cloned = min(dates)
            self.environment_vars.\
                set_first_cloned(self.environment_vars.repo_first_cloned)
            self._clones_from_date = self.environment_vars.repo_first_cloned
        else:
            self._clones_from_date = min(dates)

        self._clones = self.environment_vars.repo_clones + today_clone_count
        return self._clones

    @property
    async def clones_from_date(self) -> str:
        """
        :return: the first date included in the repo clone count
        """
        if self._clones_from_date is not None:
            return self._clones_from_date
        await self.clones
        assert self._clones_from_date is not None
        return self._clones_from_date

    @property
    async def collaborators(self) -> int:
        """
        :return: count of total collaborators to user's repositories
        """
        if self._collaborators is not None:
            return self._collaborators

        collaborator_set = set()

        for repo in await self.repos:
            r = await self.queries\
                .query_rest(f"/repos/{repo}/collaborators")

            for obj in r:
                if isinstance(obj, dict):
                    collaborator_set.add(obj.get("login"))

        collabs = max(0, len(collaborator_set
                             .union(await self.contributors)) - 1)
        self._collaborators = self.environment_vars.more_collabs + collabs
        return self._collaborators

    @property
    async def contributors(self) -> Set:
        """
        :return: count of total contributors to user's repositories
        """
        if self._contributors is not None:
            return self._contributors
        await self.lines_changed
        assert self._contributors is not None
        return self._contributors

    @property
    async def pull_requests(self) -> int:
        """
        :return: count of pull requests in repositories
        """
        if self._pull_requests is not None:
            return self._pull_requests

        self._pull_requests = 0

        for repo in await self.repos:
            r = await self.queries\
                .query_rest(f"/repos/{repo}/pulls?state=all")

            for obj in r:
                if isinstance(obj, dict):
                    self._pull_requests += 1
        return self._pull_requests

    @property
    async def issues(self) -> int:
        """
        :return: count of issues in repositories
        """
        if self._issues is not None:
            return self._issues

        self._issues = 0

        for repo in await self.repos:
            r = await self.queries\
                .query_rest(f"/repos/{repo}/issues?state=all")

            for obj in r:
                if isinstance(obj, dict):
                    try:
                        if obj.get("html_url").split("/")[-2] == "issues":
                            self._issues += 1
                    except AttributeError:
                        continue
        return self._issues
