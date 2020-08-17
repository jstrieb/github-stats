#!/usr/bin/python3

import json
import os
from builtins import bytes

from typing import Dict, List

import requests


###############################################################################
# GitHub API GraphQL Query Generators
###############################################################################

def owned_overview_query(after: str = "") -> str:
    """
    :return: GitHub GraphQL API query with the star count, fork count, and languages used for the repositories owned by the user
    """
    return f"""
query RepositoryStatsOwned {{
  viewer {{
    repositories(ownerAffiliations: OWNER, first: 100, orderBy: {{field: STARGAZERS, direction: DESC}}, isFork: false{f', after: "{after}"' if after else ""}) {{
      nodes {{
        nameWithOwner
        stargazers {{
          totalCount
        }}
        forkCount
        languages(first: 10) {{
          nodes {{
            id
          }}
          edges {{
            size
            node {{
              name
              color
            }}
          }}
        }}
      }}
      pageInfo {{
        hasNextPage
        endCursor
      }}
    }}
  }}
}}"""


def contrib_overview_query() -> str:
    """
    :return: GitHub GraphQL API query with the star count, fork count, and languages used for the repositories the user has contributed to
    """
    return """
query RepositoryStatsContrib {
  viewer {
    repositoriesContributedTo(contributionTypes: [COMMIT, PULL_REQUEST, REPOSITORY], first: 100, orderBy: {field: STARGAZERS, direction: DESC}) {
      nodes {
        nameWithOwner
        stargazers {
          totalCount
        }
        forkCount
        languages(first: 10) {
          nodes {
            id
          }
          edges {
            size
            node {
              name
              color
            }
          }
        }
      }
    }
  }
}"""


def owned_stargazers(after: str = "") -> str:
    """
    NOTE: Nested f-strings are a little tricky
    :param after: key used for pagination, if necessary
    :return: GitHub GraphQL API query with repositories of stargazers on repositories the user owns
    """
    return f"""
query StargazersOwned {{
  viewer {{
    repositories(ownerAffiliations: OWNER, first: 100, orderBy: {{field: STARGAZERS, direction: DESC}}, isFork: false) {{
      nodes {{
        nameWithOwner
        stargazers(first: 100{f', after: "{after}"' if after else ""}) {{
          pageInfo {{
            hasNextPage
            endCursor
          }}
          nodes {{
            repositories(isFork: false, first: 10, orderBy: {{field: STARGAZERS, direction: DESC}}) {{
              nodes {{
                nameWithOwner
                stargazers {{
                  totalCount
                }}
              }}
            }}
          }}
        }}
      }}
    }}
  }}
}}
"""


def contrib_stargazers(after: str = "") -> str:
    """
    NOTE: Nested f-strings are a little tricky
    :param after: key used for pagination, if necessary
    :return: GitHub GraphQL API query with repositories of stargazers on repositories the user has contributed to
    """
    return f"""
query StargazersOwned {{
  viewer {{
    repositoriesContributedTo(contributionTypes: [COMMIT, PULL_REQUEST, REPOSITORY], first: 100, orderBy: {{field: STARGAZERS, direction: DESC}}) {{
      nodes {{
        nameWithOwner
        stargazers(first: 100{f', after: "{after}"' if after else ""}) {{
          pageInfo {{
            hasNextPage
            endCursor
          }}
          nodes {{
            repositories(isFork: false, first: 10, orderBy: {{field: STARGAZERS, direction: DESC}}) {{
              nodes {{
                nameWithOwner
                stargazers {{
                  totalCount
                }}
              }}
            }}
          }}
        }}
      }}
    }}
  }}
}}
"""


def contrib_years() -> str:
    """
    TODO
    :return:
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


def contribs_by_year(year: str) -> str:
    """
    TODO
    :param year:
    :return:
    """
    return f"""
    year{year}: contributionsCollection(from: "{year}-01-01T00:00:00Z", to: "{year + 1}-01-01T00:00:00Z") {{
      contributionCalendar {{
        totalContributions
      }}
    }}
"""


def all_contribs(years: List[str]) -> str:
    """
    TODO
    :param years:
    :return:
    """
    by_years = "\n".join(map(contribs_by_year, years))
    return f"""
query {{
  viewer {{
    {by_years}
  }}
}}
"""


###############################################################################
# Helper Functions
###############################################################################

def query(generated_query: str) -> Dict:
    """
    Make a request to the GraphQL API using the authentication token from the
    environment
    :param generated_query: string query to be sent to the API
    :return: decoded GraphQL JSON output
    """
    access_token = os.getenv("ACCESS_TOKEN")
    headers = {
        "Authorization": f"Bearer {access_token}",
    }
    r = requests.post("https://api.github.com/graphql", headers=headers,
                      json={"query": generated_query})
    return r.json()


def get_stats() -> Dict:
    """
    Print summary statistics about forks, stars, and languages
    """
    stargazers = 0
    forks = 0
    langs = dict()
    repo_names = set()

    # TODO: Move to separate function
    after = ""
    while True:
        repos = query(owned_overview_query(after)) \
            .get("data", {}) \
            .get("viewer", {}) \
            .get("repositories", {})

        for repo in repos.get("nodes", []):
            repo_names.add(repo.get("nameWithOwner"))
            stargazers += repo.get("stargazers").get("totalCount", 0)
            forks += repo.get("forkCount", 0)
            for lang in repo.get("languages", {}).get("edges", []):
                name = lang.get("node", {}).get("name", "Other")
                langs[name] = langs.get(name, 0) + lang.get("size", 0)

        if repos.get("pageInfo", {}).get("hasNextPage", False):
            after = repos.get("pageInfo", {}).get("endCursor")
        else:
            break

    # TODO: Improve languages to scale by number of contributions to specific
    #       filetypes
    langs_total = sum(langs.values())
    langs_proportional = {l: 100 * (s / langs_total) for l, s in langs.items()}

    total_contribs = 0
    years = query(contrib_years())\
        .get("data", {})\
        .get("viewer", {})\
        .get("contributionsCollection", {})\
        .get("contributionYears", [])
    by_year = query(all_contribs(years))\
        .get("data", {})\
        .get("viewer", {}).values()
    for year in by_year:
        total_contribs += year\
            .get("contributionCalendar", {})\
            .get("totalContributions", 0)

    return {
        "stargazers": stargazers,
        "forks": forks,
        "total_contributions": total_contribs,
        "owned_repos": len(repo_names),
        "languages": langs_proportional,
    }


###############################################################################
# Main Function
###############################################################################

def main() -> None:
    print(json.dumps(get_stats(), indent=2))


if __name__ == "__main__":
    main()
