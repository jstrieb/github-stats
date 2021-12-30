#!/usr/bin/python3

from os import getenv, environ
from typing import Optional

from src.db.db import GitRepoStatsDB


class EnvironmentVariables:

    def __init__(self,
                 username: str,
                 access_token: str,
                 exclude_repos: Optional[str] = getenv("EXCLUDED"),
                 exclude_langs: Optional[str] = getenv("EXCLUDED_LANGS"),
                 ignore_forked_repos: str = getenv("EXCLUDE_FORKED_REPOS"),
                 repo_views: Optional[str] = getenv("REPO_VIEWS"),
                 repo_last_viewed: Optional[str] = getenv("LAST_VIEWED"),
                 repo_first_viewed: Optional[str] = getenv("FIRST_VIEWED"),
                 maintain_repo_view_count: str = getenv("SAVE_REPO_VIEWS"),
                 repo_clones: Optional[str] = getenv("REPO_CLONES"),
                 repo_last_cloned: Optional[str] = getenv("LAST_CLONED"),
                 repo_first_cloned: Optional[str] = getenv("FIRST_CLONED"),
                 maintain_repo_clone_count: str = getenv("SAVE_REPO_CLONES"),
                 more_collabs: Optional[str] = getenv("MORE_COLLABS")):
        self.__db = GitRepoStatsDB()

        self.username = username
        self.access_token = access_token

        if exclude_repos is None:
            self.exclude_repos = set()
        else:
            self.exclude_repos = (
                {x.strip() for x in exclude_repos.split(",")}
            )

        if exclude_repos is None:
            self.exclude_langs = set()
        else:
            self.exclude_langs = (
                {x.strip() for x in exclude_langs.split(",")}
            )

        self.ignore_forked_repos = (
                not not ignore_forked_repos
                and ignore_forked_repos.strip().lower() != "false"
        )

        self.maintain_repo_view_count = (
                not maintain_repo_view_count
                or maintain_repo_view_count.strip().lower() == "true"
        )

        if self.maintain_repo_view_count:
            self.repo_views = int(repo_views) if repo_views else self.__db.views

            if repo_last_viewed:
                self.repo_last_viewed = repo_last_viewed
            else:
                self.repo_last_viewed = self.__db.views_to_date

            if repo_first_viewed:
                self.repo_first_viewed = repo_first_viewed
            else:
                self.repo_first_viewed = self.__db.views_from_date
        else:
            self.repo_views = 0
            self.__db.set_views_count(self.repo_views)
            self.repo_last_viewed = "0000-00-00"
            self.repo_first_viewed = "0000-00-00"
            self.__db.set_views_from_date(self.repo_first_viewed)
            self.__db.set_views_to_date(self.repo_last_viewed)

        self.maintain_repo_clone_count = (
                not maintain_repo_clone_count
                or maintain_repo_clone_count.strip().lower() == "true"
        )

        if self.maintain_repo_clone_count:
            self.repo_clones = int(repo_clones) if repo_clones else self.__db.clones

            if repo_last_cloned:
                self.repo_last_cloned = repo_last_cloned
            else:
                self.repo_last_cloned = self.__db.clones_to_date

            if repo_first_cloned:
                self.repo_first_cloned = repo_first_cloned
            else:
                self.repo_first_cloned = self.__db.clones_from_date
        else:
            self.repo_clones = 0
            self.__db.set_clones_count(self.repo_clones)
            self.repo_last_cloned = "0000-00-00"
            self.repo_first_cloned = "0000-00-00"
            self.__db.set_clones_from_date(self.repo_first_cloned)
            self.__db.set_clones_to_date(self.repo_last_cloned)

        self.more_collabs = int(more_collabs) if more_collabs else 0

    def set_views(self, views: any) -> None:
        self.repo_views += int(views)
        environ["REPO_VIEWS"] = str(self.repo_views)
        self.__db.set_views_count(self.repo_views)

    def set_last_viewed(self, new_last_viewed_date: str) -> None:
        self.repo_last_viewed = new_last_viewed_date
        environ["LAST_VIEWED"] = self.repo_last_viewed
        self.__db.set_views_to_date(self.repo_last_viewed)

    def set_first_viewed(self, new_first_viewed_date: str) -> None:
        self.repo_first_viewed = new_first_viewed_date
        environ["FIRST_VIEWED"] = self.repo_first_viewed
        self.__db.set_views_from_date(self.repo_first_viewed)

    def set_clones(self, clones: any) -> None:
        self.repo_clones += int(clones)
        environ["REPO_CLONES"] = str(self.repo_clones)
        self.__db.set_clones_count(self.repo_clones)

    def set_last_cloned(self, new_last_cloned_date: str) -> None:
        self.repo_last_cloned = new_last_cloned_date
        environ["LAST_CLONED"] = self.repo_last_cloned
        self.__db.set_clones_to_date(self.repo_last_cloned)

    def set_first_cloned(self, new_first_cloned_date: str) -> None:
        self.repo_first_cloned = new_first_cloned_date
        environ["FIRST_CLONED"] = self.repo_first_cloned
        self.__db.set_clones_from_date(self.repo_first_cloned)
