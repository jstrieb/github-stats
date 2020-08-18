#!/usr/bin/python3
import json
import os

from typing import Dict, List, Optional, Set

import requests


###############################################################################
# Main Classes
###############################################################################

class Queries(object):
    def __init__(self, access_token: str):
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

    @staticmethod
    def repos_overview(contrib_cursor: Optional[str] = None,
                       owned_cursor: Optional[str] = None) -> str:
        return f"""{{
  viewer {{
    repositories(
        first: 100, 
        orderBy: {{
            field: UPDATED_AT, 
            direction: DESC
        }}, 
        after: {"null" if owned_cursor is None else '"' + owned_cursor + '"'}
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
        after: {"null" if contrib_cursor is None else '"' + contrib_cursor + '"'}
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
        by_years = "\n".join(map(cls.contribs_by_year, years))
        return f"""
query {{
  viewer {{
    {by_years}
  }}
}}
"""


class Stats(object):
    def __init__(self, access_token: str, exclude_repos: Optional[Set] = None):
        self._exclude_repos = set() if exclude_repos is None else exclude_repos
        self.queries = Queries(access_token)

        self._stargazers = None
        self._forks = None
        self._total_contributions = None
        self._languages = None
        self._repos = None

    def __str__(self) -> str:
        formatted_languages = "\n  - ".join(
            [f"{l}: {v:0.2f}%" for l, v in self.languages.items()]
        )
        return f"""Stargazers: {self.stargazers:,}
Forks: {self.forks:,}
All-time contributions: {self.total_contributions:,}
Repositories with contributions: {len(self.repos)}
Languages:
  - {formatted_languages}"""

    def get_stats(self) -> None:
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
            contrib_repos = (raw_results
                             .get("data", {})
                             .get("viewer", {})
                             .get("repositoriesContributedTo", {}))
            owned_repos = (raw_results
                           .get("data", {})
                           .get("viewer", {})
                           .get("repositories", {}))
            repos = contrib_repos.get("nodes", []) + owned_repos.get("nodes", [])

            for repo in repos:
                name = repo.get("nameWithOwner")
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
                            "color": lang.get("color")
                        }

            if (owned_repos.get("pageInfo", {}).get("hasNextPage", False)
                or contrib_repos.get("pageInfo", {}).get("hasNextPage", False)):
                next_owned = owned_repos.get("pageInfo", {}).get("endCursor")
                next_contrib = contrib_repos.get("pageInfo", {}).get("endCursor")
            else:
                break

    @property
    def stargazers(self) -> int:
        if self._stargazers is not None:
            return self._stargazers
        self.get_stats()
        return self._stargazers

    @property
    def forks(self) -> int:
        if self._forks is not None:
            return self._forks
        self.get_stats()
        return self._forks

    @property
    def languages(self) -> Dict:
        if self._languages is not None:
            return self._languages
        self.get_stats()

        # TODO: Improve languages to scale by number of contributions to
        #       specific filetypes
        langs_total = sum([v.get("size", 0) for v in self._languages.values()])
        langs = {
            l: 100 * (s.get("size", 0) / langs_total)
            for l, s in self._languages.items()
        }
        return langs

    @property
    def repos(self) -> List[str]:
        if self._repos is not None:
            return self._repos
        self.get_stats()
        return self._repos

    @property
    def total_contributions(self) -> int:
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


###############################################################################
# Main Function
###############################################################################

def main() -> None:
    access_token = os.getenv("ACCESS_TOKEN")
    s = Stats(access_token, exclude_repos={"Genrep-Software/style-guides"})
    print(s)


if __name__ == "__main__":
    main()
