#!/usr/bin/python3

import json
import os

from typing import Dict

import requests


###############################################################################
# GitHub API GraphQL Query Generators
###############################################################################

def owned_overview_query() -> str:
    """
    :return: GitHub GraphQL API query with the star count, fork count, and languages used for the repositories owned by the user
    """
    return """
query RepositoryStatsOwned {
  viewer {
    repositories(ownerAffiliations: OWNER, first: 100, orderBy: {field: STARGAZERS, direction: DESC}, isFork: false) {
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

    owned_repo_data = query(owned_overview_query()).get("data", {})
    repos = owned_repo_data.get("viewer", {}).get("repositories", {})
    for repo in repos.get("nodes", []):
        stargazers += repo.get("stargazers").get("totalCount", 0)
        forks += repo.get("forkCount", 0)
        for lang in repo.get("languages", {}).get("edges", []):
            name = lang.get("node", {}).get("name", "Other")
            langs[name] = langs.get(name, 0) + lang.get("size", 0)

    langs_total = sum(langs.values())
    langs_proportional = {l: 100 * (s / langs_total) for l, s in langs.items()}

    return {
        "stargazers": stargazers,
        "forks": forks,
        "languages": langs_proportional,
    }


###############################################################################
# Main Function
###############################################################################

def main() -> None:
    print(json.dumps(get_stats(), indent=2))


if __name__ == "__main__":
    main()
