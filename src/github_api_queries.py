#!/usr/bin/python3

from asyncio import Semaphore, sleep
from requests import post, get
from aiohttp import ClientSession
from typing import Dict, Optional, List


class GitHubApiQueries(object):
    """
    Class with functions to query the GitHub GraphQL (v4) API and the REST (v3)
    API. Also includes functions to dynamically generate GraphQL queries.
    """

    __GITHUB_API_URL = "https://api.github.com/"
    __GRAPHQL_PATH = "graphql"
    __REST_QUERY_LIMIT = 60
    __ASYNCIO_SLEEP_TIME = 2
    __DEFAULT_MAX_CONNECTIONS = 10

    def __init__(self,
                 username: str,
                 access_token: str,
                 session: ClientSession,
                 max_connections: int = __DEFAULT_MAX_CONNECTIONS):
        self.username = username
        self.access_token = access_token
        self.session = session
        self.semaphore = Semaphore(max_connections)
        self.headers = {
            "Authorization": f"Bearer {self.access_token}",
        }

    async def query(self, generated_query: str) -> Dict:
        """
        Make a request to the GraphQL API using the authentication token from
        the environment
        :param generated_query: string query to be sent to the API
        :return: decoded GraphQL JSON output
        """
        try:
            async with self.semaphore:
                r_async = await self.session.post(
                    self.__GITHUB_API_URL + self.__GRAPHQL_PATH,
                    headers=self.headers,
                    json={"query": generated_query},
                )
            result = await r_async.json()

            if result is not None:
                return result
        except:
            print("aiohttp failed for GraphQL query")

            # Fall back on non-async requests
            async with self.semaphore:
                r_requests = post(
                    self.__GITHUB_API_URL + self.__GRAPHQL_PATH,
                    headers=self.headers,
                    json={"query": generated_query},
                )
                result = r_requests.json()

                if result is not None:
                    return result
        return dict()

    async def query_rest(self,
                         path: str,
                         params: Optional[Dict] = None) -> Dict:
        """
        Make a request to the REST API
        :param path: API path to query
        :param params: Query parameters to be passed to the API
        :return: deserialized REST JSON output
        """
        for i in range(self.__REST_QUERY_LIMIT):
            if params is None:
                params = dict()
            if path.startswith("/"):
                path = path[1:]

            try:
                async with self.semaphore:
                    r_async = await self.session.get(
                        self.__GITHUB_API_URL + path,
                        headers=self.headers,
                        params=tuple(params.items()),
                    )

                if r_async.status == 202:
                    print(f"A path returned 202. Retrying...")
                    await sleep(self.__ASYNCIO_SLEEP_TIME)
                    continue

                result = await r_async.json()

                if result is not None:
                    return result
            except:
                print("aiohttp failed for REST query attempt #" + str(i + 1))

                # Fall back on non-async requests
                async with self.semaphore:
                    r_requests = get(
                        self.__GITHUB_API_URL + path,
                        headers=self.headers,
                        params=tuple(params.items()),
                    )

                    if r_requests.status_code == 202:
                        print(f"A path returned 202. Retrying...")
                        await sleep(self.__ASYNCIO_SLEEP_TIME)
                        continue
                    elif r_requests.status_code == 200:
                        return r_requests.json()

        print("Too many 202s. Data for this repository will be incomplete.")
        return dict()

    @staticmethod
    def repos_overview(contrib_cursor: Optional[str] = None,
                       owned_cursor: Optional[str] = None) -> str:
        """
        :return: GraphQL queries with overview of user repositories
        """
        return f"""
            {{
                viewer {{
                    login,
                    name,
                    repositories(
                    first: 100,
                    orderBy: {{
                        field: UPDATED_AT,
                        direction: DESC
                    }},
                    isFork: false,
                    after: {
                        "null" if owned_cursor is None 
                        else '"' + owned_cursor + '"'
                    }) {{
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
                            languages(first: 10, orderBy: {{
                                field: SIZE, 
                                direction: DESC
                            }}) {{
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
                    after: {
                    "null" if contrib_cursor is None 
                    else '"' + contrib_cursor + '"'}) {{
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
                            languages(first: 10, orderBy: {{
                                field: SIZE, 
                                direction: DESC
                            }}) {{
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
            }}"""

    @staticmethod
    def contributions_all_years() -> str:
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
            }"""

    @staticmethod
    def contributions_by_year(year: str) -> str:
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
            }}"""

    @classmethod
    def all_contributions(cls, years: List[str]) -> str:
        """
        :param years: list of years to get contributions for
        :return: query to retrieve contribution information for all user years
        """
        by_years = "\n".join(map(cls.contributions_by_year, years))
        return f"""
            query {{
                viewer {{
                    {by_years}
                }}
            }}"""
