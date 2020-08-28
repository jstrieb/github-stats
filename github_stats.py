#!/usr/bin/python3

import json
import hashlib
import os
import time

from typing import Dict, List, Optional, Set, Tuple

import requests


###############################################################################
# Main Classes
###############################################################################

class Queries(object):
    """
    Class with functions to query the GitHub GraphQL (v4) API and the REST (v3)
    API. Also includes functions to dynamically generate GraphQL queries.
    """
    def __init__(self, username: str, access_token: str):
        self.username = username
        self.access_token = access_token
        self.session = requests.Session()

    def query(self, generated_query: str) -> Dict:
        """
        Make a request to the GraphQL API using the authentication token from
        the environment
        :param generated_query: string query to be sent to the API
        :return: decoded GraphQL JSON output
        """
        headers = {
            "Authorization": f"Bearer {self.access_token}",
        }
        r = self.session.post("https://api.github.com/graphql", headers=headers,
                              json={"query": generated_query})
        return r.json()

    def query_rest(self, path: str, params: Optional[Dict] = None) -> Dict:
        """
        Make a request to the REST API
        :param path: API path to query
        :param params: Query parameters to be passed to the API
        :return: deserialized REST JSON output
        """
        while True:
            headers = {
                "Authorization": f"token {self.access_token}",
            }
            if params is None:
                params = dict()
            if path.startswith("/"):
                path = path[1:]
            r = self.session.get(f"https://api.github.com/{path}",
                                 headers=headers, params=tuple(params.items()))
            if r.status_code == 202:
                # print(f"{path} returned 202. Retrying...")
                print(f"A path returned 202. Retrying...")
                time.sleep(1)
                continue
            return r.json()

    @staticmethod
    def repos_overview(contrib_cursor: Optional[str] = None,
                       owned_cursor: Optional[str] = None) -> str:
        """
        :return: GraphQL query with overview of user repositories
        """
        return f"""{{
  viewer {{
    name
    repositories(
        first: 100,
        orderBy: {{
            field: UPDATED_AT,
            direction: DESC
        }},
        after: {"null" if owned_cursor is None else '"'+ owned_cursor +'"'}
    ) {{
      pageInfo {{
        hasNextPage
        endCursor
      }}
      nodes {{
        nameWithOwner
        stargazers {{
          totalCount
        }}
        forkCount
        languages(first: 10, orderBy: {{field: SIZE, direction: DESC}}) {{
          edges {{
            size
            node {{
              name
              color
            }}
          }}
        }}
      }}
    }}
    repositoriesContributedTo(
        first: 100,
        includeUserRepositories: false,
        orderBy: {{
            field: UPDATED_AT,
            direction: DESC
        }},
        contributionTypes: [
            COMMIT,
            PULL_REQUEST,
            REPOSITORY,
            PULL_REQUEST_REVIEW
        ]
        after: {"null" if contrib_cursor is None else '"'+ contrib_cursor +'"'}
    ) {{
      pageInfo {{
        hasNextPage
        endCursor
      }}
      nodes {{
        nameWithOwner
        stargazers {{
          totalCount
        }}
        forkCount
        languages(first: 10, orderBy: {{field: SIZE, direction: DESC}}) {{
          edges {{
            size
            node {{
              name
              color
            }}
          }}
        }}
      }}
    }}
  }}
}}
"""

    @staticmethod
    def contrib_years() -> str:
        """
        :return: GraphQL query to get all years the user has been a contributor
        """
        return """
query {
  viewer {
    contributionsCollection {
      contributionYears
    }
  }
}
"""

    @staticmethod
    def contribs_by_year(year: str) -> str:
        """
        :param year: year to query for
        :return: portion of a GraphQL query with desired info for a given year
        """
        return f"""
    year{year}: contributionsCollection(
        from: "{year}-01-01T00:00:00Z",
        to: "{int(year) + 1}-01-01T00:00:00Z"
    ) {{
      contributionCalendar {{
        totalContributions
      }}
    }}
"""

    @classmethod
    def all_contribs(cls, years: List[str]) -> str:
        """
        :param years: list of years to get contributions for
        :return: query to retrieve contribution information for all user years
        """
        by_years = "\n".join(map(cls.contribs_by_year, years))
        return f"""
query {{
  viewer {{
    {by_years}
  }}
}}
"""


class Stats(object):
    """
    Retrieve and store statistics about GitHub usage.
    """
    def __init__(self, username: str, access_token: str,
                 exclude_repos: Optional[Set] = None):
        self.username = username
        self._exclude_repos = set() if exclude_repos is None else exclude_repos
        self.queries = Queries(username, access_token)

        self._name = None
        self._stargazers = None
        self._forks = None
        self._total_contributions = None
        self._languages = None
        self._repos = None
        self._lines_changed = None
        self._views = None

    def __str__(self) -> str:
        """
        :return: summary of all available statistics
        """
        formatted_languages = "\n  - ".join(
            [f"{k}: {v:0.4f}%" for k, v in self.languages_proportional.items()]
        )
        return f"""Name: {self.name}
Stargazers: {self.stargazers:,}
Forks: {self.forks:,}
All-time contributions: {self.total_contributions:,}
Repositories with contributions: {len(self.repos)}
Lines of code added: {self.lines_changed[0]:,}
Lines of code deleted: {self.lines_changed[1]:,}
Lines of code changed: {self.lines_changed[0] + self.lines_changed[1]:,}
Project page views: {self.views:,}
Languages:
  - {formatted_languages}"""

    def get_stats(self) -> None:
        """
        Get lots of summary statistics using one big query. Sets many attributes
        """
        self._stargazers = 0
        self._forks = 0
        self._languages = dict()
        self._repos = set()

        next_owned = None
        next_contrib = None
        while True:
            raw_results = self.queries.query(
                Queries.repos_overview(owned_cursor=next_owned,
                                       contrib_cursor=next_contrib)
            )

            self._name = (raw_results
                          .get("data", {})
                          .get("viewer", {})
                          .get("name", "No Name"))

            contrib_repos = (raw_results
                             .get("data", {})
                             .get("viewer", {})
                             .get("repositoriesContributedTo", {}))
            owned_repos = (raw_results
                           .get("data", {})
                           .get("viewer", {})
                           .get("repositories", {}))
            repos = (contrib_repos.get("nodes", [])
                     + owned_repos.get("nodes", []))

            for repo in repos:
                name = repo.get("nameWithOwner")
                if name in self._repos:
                    continue
                self._repos.add(name)
                self._stargazers += repo.get("stargazers").get("totalCount", 0)
                self._forks += repo.get("forkCount", 0)

                if name in self._exclude_repos:
                    continue
                for lang in repo.get("languages", {}).get("edges", []):
                    name = lang.get("node", {}).get("name", "Other")
                    if name in self.languages:
                        self.languages[name]["size"] += lang.get("size", 0)
                        self.languages[name]["occurrences"] += 1
                    else:
                        self.languages[name] = {
                            "size": lang.get("size", 0),
                            "occurrences": 1,
                            "color": lang.get("node", {}).get("color")
                        }

            if owned_repos.get("pageInfo", {}).get("hasNextPage", False) or \
                    contrib_repos.get("pageInfo", {}).get("hasNextPage", False):
                next_owned = (owned_repos
                              .get("pageInfo", {})
                              .get("endCursor", next_owned))
                next_contrib = (contrib_repos
                                .get("pageInfo", {})
                                .get("endCursor", next_contrib))
            else:
                break

        # TODO: Improve languages to scale by number of contributions to
        #       specific filetypes
        langs_total = sum([v.get("size", 0) for v in self._languages.values()])
        for k, v in self._languages.items():
            v["prop"] = 100 * (v.get("size", 0) / langs_total)

    @property
    def name(self) -> str:
        """
        :return: GitHub user's name (e.g., Jacob Strieb)
        """
        if self._name is not None:
            return self._name
        self.get_stats()
        assert(self._name is not None)
        return self._name

    @property
    def stargazers(self) -> int:
        """
        :return: total number of stargazers on user's repos
        """
        if self._stargazers is not None:
            return self._stargazers
        self.get_stats()
        assert(self._stargazers is not None)
        return self._stargazers

    @property
    def forks(self) -> int:
        """
        :return: total number of forks on user's repos
        """
        if self._forks is not None:
            return self._forks
        self.get_stats()
        assert(self._forks is not None)
        return self._forks

    @property
    def languages(self) -> Dict:
        """
        :return: summary of languages used by the user
        """
        if self._languages is not None:
            return self._languages
        self.get_stats()
        assert(self._languages is not None)
        return self._languages

    @property
    def languages_proportional(self) -> Dict:
        """
        :return: summary of languages used by the user, with proportional usage
        """
        if self._languages is None:
            self.get_stats()
            assert(self._languages is not None)

        return {k: v.get("prop", 0) for (k, v) in self._languages.items()}

    @property
    def repos(self) -> List[str]:
        """
        :return: list of names of user's repos
        """
        if self._repos is not None:
            return self._repos
        self.get_stats()
        assert(self._repos is not None)
        return self._repos

    @property
    def total_contributions(self) -> int:
        """
        :return: count of user's total contributions as defined by GitHub
        """
        if self._total_contributions is not None:
            return self._total_contributions

        self._total_contributions = 0
        years = self.queries.query(Queries.contrib_years()) \
            .get("data", {}) \
            .get("viewer", {}) \
            .get("contributionsCollection", {}) \
            .get("contributionYears", [])
        by_year = self.queries.query(Queries.all_contribs(years)) \
            .get("data", {}) \
            .get("viewer", {}).values()
        for year in by_year:
            self._total_contributions += year \
                .get("contributionCalendar", {}) \
                .get("totalContributions", 0)
        return self._total_contributions

    @property
    def lines_changed(self) -> Tuple[int, int]:
        """
        :return: count of total lines added, removed, or modified by the user
        """
        if self._lines_changed is not None:
            return self._lines_changed
        additions = 0
        deletions = 0
        for repo in self.repos:
            r = self.queries.query_rest(f"/repos/{repo}/stats/contributors")
            for author_obj in r:
                author = author_obj.get("author", {}).get("login", "")
                if author != self.username:
                    continue

                for week in author_obj.get("weeks", []):
                    additions += week.get("a", 0)
                    deletions += week.get("d", 0)
            time.sleep(0.5)

        self._lines_changed = (additions, deletions)
        return self._lines_changed

    @property
    def views(self) -> int:
        """
        Note: only returns views for the last 14 days (as-per GitHub API)
        :return: total number of page views the user's projects have received
        """
        if self._views is not None:
            return self._views

        total = 0
        for repo in self.repos:
            r = self.queries.query_rest(f"/repos/{repo}/traffic/views")
            for view in r.get("views", []):
                total += view.get("count", 0)
            time.sleep(0.5)

        self._views = total
        return total


###############################################################################
# Main Function
###############################################################################

def main() -> None:
    """
    Used mostly for testing; this module is not usually run standalone
    """
    access_token = os.getenv("ACCESS_TOKEN")
    user = os.getenv("GITHUB_ACTOR")
    s = Stats(user, access_token)
    print(s.views)


if __name__ == "__main__":
    main()
