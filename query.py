#!/usr/bin/python3

import json
import os

import requests


def gql_counts_owned():
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

def gql_counts_contrib():
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

def gql_gazers_contrib(after=""):
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

def gql_gazers_owned(after=""):
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

def query(query_gen):
    access_token = os.getenv("ACCESS_TOKEN")
    headers = {
        "Authorization": f"Bearer {access_token}",
    }
    generated_query = query_gen()
    r = requests.post("https://api.github.com/graphql", headers=headers,
            json={"query": generated_query})
    return r.json()


def main():
    print(json.dumps(query(gql_counts_owned), indent=2))


if __name__ == "__main__":
    main()
