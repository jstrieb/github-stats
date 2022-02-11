#!/usr/bin/python3

from asyncio import run, gather
from aiohttp import ClientSession
from os import mkdir, getenv
from os.path import isdir
from re import sub

from src.env_vars import EnvironmentVariables
from src.github_repo_stats import GitHubRepoStats

OUTPUT_DIR = "generated"  # directory for storing generated images
TEMPLATE_PATH = "src/templates/"
OVERVIEW_FILE_NAME = "overview.svg"
LANGUAGES_FILE_NAME = "languages.svg"


###############################################################################
# Helper Functions
###############################################################################

def generate_output_folder() -> None:
    """
    Create the output folder if it does not already exist
    """
    if not isdir(OUTPUT_DIR):
        mkdir(OUTPUT_DIR)

###############################################################################
# GenerateImages class
###############################################################################


class GenerateImages:

    def __init__(self):
        access_token = getenv("ACCESS_TOKEN")
        user = getenv("GITHUB_ACTOR")

        if not access_token:
            raise Exception("A personal access token is required to proceed!")

        if not user:
            raise RuntimeError("Environment variable GITHUB_ACTOR must be set")

        self.__environment = EnvironmentVariables(username=user,
                                                  access_token=access_token)
        self.__stats = None

        run(self.start())

    async def start(self) -> None:
        """
        Main function: generate all badges
        """
        async with ClientSession() as session:
            self.__stats = GitHubRepoStats(environment_vars=self.__environment,
                                           session=session)
            await gather(self.generate_languages(),
                         self.generate_overview())

    async def generate_overview(self) -> None:
        """
        Generate an SVG badge with summary statistics
        """
        with open("{}{}".format(TEMPLATE_PATH,
                                OVERVIEW_FILE_NAME), "r") as f:
            output = f.read()

        name = (await self.__stats.name) + "'" \
            if (await self.__stats.name)[-1] == "s" \
            else (await self.__stats.name) + "'s"
        output = sub("{{ name }}",
                     name,
                     output)

        views = f"{await self.__stats.views:,}"
        output = sub("{{ views }}",
                     views,
                     output)

        clones = f"{await self.__stats.clones:,}"
        output = sub("{{ clones }}",
                     clones,
                     output)

        stars = f"{await self.__stats.stargazers:,}"
        output = sub("{{ stars }}",
                     stars,
                     output)

        forks = f"{await self.__stats.forks:,}"
        output = sub("{{ forks }}",
                     forks,
                     output)

        contributions = f"{await self.__stats.total_contributions:,}"
        output = sub("{{ contributions }}",
                     contributions,
                     output)

        changed = (await self.__stats.lines_changed)[0] + \
                  (await self.__stats.lines_changed)[1]
        output = sub("{{ lines_changed }}",
                     f"{changed:,}",
                     output)

        avg_contribution_percent = await self.__stats.avg_contribution_percent
        output = sub("{{ avg_contribution_percent }}",
                     avg_contribution_percent,
                     output)

        repos = f"{len(await self.__stats.repos):,}"
        output = sub("{{ repos }}",
                     repos,
                     output)

        collaborators = f"{await self.__stats.collaborators:,}"
        output = sub("{{ collaborators }}",
                     collaborators,
                     output)

        contributors = f"{max(len(await self.__stats.contributors) - 1, 0):,}"
        output = sub("{{ contributors }}",
                     contributors,
                     output)

        views_from = (await self.__stats.views_from_date)
        output = sub("{{ views_from_date }}",
                     f"Repository views (since {views_from})",
                     output)

        clones_from = (await self.__stats.clones_from_date)
        output = sub("{{ clones_from_date }}",
                     f"Repository clones (since {clones_from})",
                     output)

        issues = f"{await self.__stats.issues:,}"
        output = sub("{{ issues }}",
                     issues,
                     output)

        pull_requests = f"{await self.__stats.pull_requests:,}"
        output = sub("{{ pull_requests }}",
                     pull_requests,
                     output)

        generate_output_folder()
        with open("{}/{}".format(OUTPUT_DIR,
                                 OVERVIEW_FILE_NAME), "w") as f:
            f.write(output)

    async def generate_languages(self) -> None:
        """
        Generate an SVG badge with summary languages used
        """
        with open("{}{}".format(TEMPLATE_PATH,
                                LANGUAGES_FILE_NAME), "r") as f:
            output = f.read()

        progress = ""
        lang_list = ""
        sorted_languages = sorted((await self.__stats.languages).items(),
                                  reverse=True,
                                  key=lambda t: t[1].get("size"))
        delay_between = 150

        for i, (lang, data) in enumerate(sorted_languages):
            color = data.get("color")
            color = color if color is not None else "#000000"
            progress += (f'<span style="background-color: {color};'
                         f'width: {data.get("prop", 0):0.5f}%;" '
                         f'class="progress-item"></span>')
            lang_list += f"""
            <li style="animation-delay: {i * delay_between}ms;">
                    <svg xmlns="http://www.w3.org/2000/svg"
                         class="octicon"
                         style="fill:{color};"
                         viewBox="0 0 16 16"
                         version="1.1"
                         width="16"
                         height="16">
                            <path fill-rule="evenodd"
                                  d="M8 4a4 4 0 100 8 4 4 0 000-8z">
                            </path>
                    </svg>
                    <span class="lang">
                        {lang}
                    </span>
                    <span class="percent">
                        {data.get("prop", 0):0.3f}%
                    </span>
            </li>"""

        output = sub(r"{{ progress }}",
                     progress,
                     output)

        output = sub(r"{{ lang_list }}",
                     lang_list,
                     output)

        generate_output_folder()
        with open("{}/{}".format(OUTPUT_DIR,
                                 LANGUAGES_FILE_NAME), "w") as f:
            f.write(output)
