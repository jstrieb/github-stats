#!/usr/bin/python3

from asyncio import run, gather
from aiohttp import ClientSession
from os import mkdir, getenv
from os.path import isdir
from re import sub

from src.env_vars import EnvironmentVariables
from src.github_repo_stats import GitHubRepoStats

OUTPUT_DIR = "generated_images"  # directory for storing generated images


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
        with open("src/templates/overviewLightMode.svg", "r") as f:
            output_light_mode = f.read()
        with open("src/templates/overviewDarkMode.svg", "r") as f:
            output_dark_mode = f.read()

        name = (await self.__stats.name) + "'" \
            if (await self.__stats.name)[-1] == "s" \
            else (await self.__stats.name) + "'s"
        output_light_mode = sub("{{ name }}",
                                name,
                                output_light_mode)
        output_dark_mode = sub("{{ name }}",
                               name,
                               output_dark_mode)

        views = f"{await self.__stats.views:,}"
        output_light_mode = sub("{{ views }}",
                                views,
                                output_light_mode)
        output_dark_mode = sub("{{ views }}",
                               views,
                               output_dark_mode)

        clones = f"{await self.__stats.clones:,}"
        output_light_mode = sub("{{ clones }}",
                                clones,
                                output_light_mode)
        output_dark_mode = sub("{{ clones }}",
                               clones,
                               output_dark_mode)

        stars = f"{await self.__stats.stargazers:,}"
        output_light_mode = sub("{{ stars }}",
                                stars,
                                output_light_mode)
        output_dark_mode = sub("{{ stars }}",
                               stars,
                               output_dark_mode)

        forks = f"{await self.__stats.forks:,}"
        output_light_mode = sub("{{ forks }}",
                                forks,
                                output_light_mode)
        output_dark_mode = sub("{{ forks }}",
                               forks,
                               output_dark_mode)

        contributions = f"{await self.__stats.total_contributions:,}"
        output_light_mode = sub("{{ contributions }}",
                                contributions,
                                output_light_mode)

        output_dark_mode = sub("{{ contributions }}",
                               contributions,
                               output_dark_mode)

        changed = (await self.__stats.lines_changed)[0] + \
                  (await self.__stats.lines_changed)[1]
        output_light_mode = sub("{{ lines_changed }}",
                                f"{changed:,}",
                                output_light_mode)
        output_dark_mode = sub("{{ lines_changed }}",
                               f"{changed:,}",
                               output_dark_mode)

        avg_contribution_percent = await self.__stats.avg_contribution_percent
        output_light_mode = sub("{{ avg_contribution_percent }}",
                                avg_contribution_percent,
                                output_light_mode)
        output_dark_mode = sub("{{ avg_contribution_percent }}",
                               avg_contribution_percent,
                               output_dark_mode)

        repos = f"{len(await self.__stats.repos):,}"
        output_light_mode = sub("{{ repos }}",
                                repos,
                                output_light_mode)
        output_dark_mode = sub("{{ repos }}",
                               repos,
                               output_dark_mode)

        collaborators = f"{await self.__stats.collaborators:,}"
        output_light_mode = sub("{{ collaborators }}",
                                collaborators,
                                output_light_mode)
        output_dark_mode = sub("{{ collaborators }}",
                               collaborators,
                               output_dark_mode)

        contributors = f"{len(await self.__stats.contributors) - 1:,}"
        output_light_mode = sub("{{ contributors }}",
                                contributors,
                                output_light_mode)
        output_dark_mode = sub("{{ contributors }}",
                               contributors,
                               output_dark_mode)

        views_from = (await self.__stats.views_from_date)
        output_light_mode = sub("{{ views_from_date }}",
                                f"Repository views (as of {views_from})",
                                output_light_mode)
        output_dark_mode = sub("{{ views_from_date }}",
                               f"Repository views (as of {views_from})",
                               output_dark_mode)

        clones_from = (await self.__stats.clones_from_date)
        output_light_mode = sub("{{ clones_from_date }}",
                                f"Repository clones (as of {clones_from})",
                                output_light_mode)
        output_dark_mode = sub("{{ clones_from_date }}",
                               f"Repository clones (as of {clones_from})",
                               output_dark_mode)

        issues = f"{await self.__stats.issues:,}"
        output_light_mode = sub("{{ issues }}",
                                issues,
                                output_light_mode)
        output_dark_mode = sub("{{ issues }}",
                               issues,
                               output_dark_mode)

        pull_requests = f"{await self.__stats.pull_requests:,}"
        output_light_mode = sub("{{ pull_requests }}",
                                pull_requests,
                                output_light_mode)
        output_dark_mode = sub("{{ pull_requests }}",
                               pull_requests,
                               output_dark_mode)

        generate_output_folder()
        with open("{}/overviewLightMode.svg".format(OUTPUT_DIR), "w") as f:
            f.write(output_light_mode)
        with open("{}/overviewDarkMode.svg".format(OUTPUT_DIR), "w") as f:
            f.write(output_dark_mode)

    async def generate_languages(self) -> None:
        """
        Generate an SVG badge with summary languages used
        """
        with open("src/templates/languagesLightMode.svg", "r") as f:
            output_light_mode = f.read()
        with open("src/templates/languagesDarkMode.svg", "r") as f:
            output_dark_mode = f.read()

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

        output_light_mode = sub(r"{{ progress }}",
                                progress,
                                output_light_mode)
        output_dark_mode = sub(r"{{ progress }}",
                               progress,
                               output_dark_mode)

        output_light_mode = sub(r"{{ lang_list }}",
                                lang_list,
                                output_light_mode)
        output_dark_mode = sub(r"{{ lang_list }}",
                               lang_list,
                               output_dark_mode)

        generate_output_folder()
        with open("{}/languagesLightMode.svg".format(OUTPUT_DIR), "w") as f:
            f.write(output_light_mode)
        with open("{}/languagesDarkMode.svg".format(OUTPUT_DIR), "w") as f:
            f.write(output_dark_mode)
