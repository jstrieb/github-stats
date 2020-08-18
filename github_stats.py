#!/usr/bin/python3

import os

from typing import Dict, List, Optional

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
    def repos_overview(after: Optional[str] = None) -> str:
        return f"""{{
  viewer {{
    repositoriesContributedTo(
        first: 100, 
        includeUserRepositories: true, 
        orderBy: {{
            field: UPDATED_AT, 
            direction: DESC
        }}, 
        contributionTypes: COMMIT, 
        after: {"null" if after is None else '"' + after + '"'}
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
    year{year}: contributionsCollection(from: "{year}-01-01T00:00:00Z", to: "{year + 1}-01-01T00:00:00Z") {{
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
    def __init__(self, access_token: str):
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
Total contributions: {self.total_contributions:,}
Languages: 
  - {formatted_languages}"""

    def get_stats(self):
        self._stargazers = 0
        self._forks = 0
        self._languages = dict()
        self._repos = set()

        next_page = None
        langs = dict()
        while True:
            repos = self.queries.query(Queries.repos_overview(next_page)) \
                .get("data", {}) \
                .get("viewer", {}) \
                .get("repositoriesContributedTo", {})

            for repo in repos.get("nodes", []):
                self._repos.add(repo.get("nameWithOwner"))
                self._stargazers += repo.get("stargazers").get("totalCount", 0)
                self._forks += repo.get("forkCount", 0)
                for lang in repo.get("languages", {}).get("edges", []):
                    name = lang.get("node", {}).get("name", "Other")
                    langs[name] = langs.get(name, 0) + lang.get("size", 0)

            if repos.get("pageInfo", {}).get("hasNextPage", False):
                next_page = repos.get("pageInfo", {}).get("endCursor")
            else:
                break

        # TODO: Improve languages to scale by number of contributions to
        #       specific filetypes
        langs_total = sum(langs.values())
        self._languages = {l: 100 * (s / langs_total) for l, s in langs.items()}

    @property
    def stargazers(self):
        if self._stargazers is not None:
            return self._stargazers
        self.get_stats()
        return self._stargazers

    @property
    def forks(self):
        if self._forks is not None:
            return self._forks
        self.get_stats()
        return self._forks

    @property
    def languages(self):
        if self._languages is not None:
            return self._languages
        self.get_stats()
        return self._languages

    @property
    def repos(self):
        if self._repos is not None:
            return self._repos
        self.get_stats()
        return self._repos

    @property
    def total_contributions(self):
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
    s = Stats(access_token)
    print(s)


if __name__ == "__main__":
    main()
