#!/usr/bin/python3

from os import getenv, environ
from typing import Optional
from datetime import datetime

from src.db.db import GitRepoStatsDB

###############################################################################
# EnvironmentVariables class - uses GitRepoStatsDB class as second resort
###############################################################################


class EnvironmentVariables:

    __DATE_FORMAT = '%Y-%m-%d'

    def __init__(self,
                 username: str,
                 access_token: str,
                 exclude_repos: Optional[str] = getenv("EXCLUDED"),
                 exclude_langs: Optional[str] = getenv("EXCLUDED_LANGS"),
                 ignore_forked_repos: str = getenv("EXCLUDE_FORKED_REPOS"),
                 repo_views: Optional[str] = getenv("REPO_VIEWS"),
                 repo_last_viewed: Optional[str] = getenv("LAST_VIEWED"),
                 repo_first_viewed: Optional[str] = getenv("FIRST_VIEWED"),
                 store_repo_view_count: str = getenv("STORE_REPO_VIEWS"),
                 repo_clones: Optional[str] = getenv("REPO_CLONES"),
                 repo_last_cloned: Optional[str] = getenv("LAST_CLONED"),
                 repo_first_cloned: Optional[str] = getenv("FIRST_CLONED"),
                 store_repo_clone_count: str = getenv("STORE_REPO_CLONES"),
                 more_collabs: Optional[str] = getenv("MORE_COLLABS"),
                 manually_added_repos: Optional[str] = getenv("MORE_REPOS"),
                 only_included_repos: Optional[str] = getenv("ONLY_INCLUDED")):
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
                and ignore_forked_repos.strip().lower() == "true"
        )

        self.store_repo_view_count = (
                not store_repo_view_count
                or store_repo_view_count.strip().lower() != "false"
        )

        if self.store_repo_view_count:
            try:
                if repo_views:
                    self.repo_views = int(repo_views)
                    self.__db.set_views_count(self.repo_views)
                else:
                    self.repo_views = self.__db.views
            except ValueError:
                self.repo_views = self.__db.views

            if repo_last_viewed:
                try:
                    if repo_last_viewed == datetime\
                            .strptime(repo_last_viewed, self.__DATE_FORMAT)\
                            .strftime(self.__DATE_FORMAT):
                        self.repo_last_viewed = repo_last_viewed
                except ValueError:
                    self.repo_last_viewed = self.__db.views_to_date
            else:
                self.repo_last_viewed = self.__db.views_to_date

            if repo_first_viewed:
                try:
                    if repo_first_viewed == datetime\
                            .strptime(repo_first_viewed, self.__DATE_FORMAT)\
                            .strftime(self.__DATE_FORMAT):
                        self.repo_first_viewed = repo_first_viewed
                except ValueError:
                    self.repo_first_viewed = self.__db.views_from_date
            else:
                self.repo_first_viewed = self.__db.views_from_date

        else:
            self.repo_views = 0
            self.__db.set_views_count(self.repo_views)
            self.repo_last_viewed = "0000-00-00"
            self.repo_first_viewed = "0000-00-00"
            self.__db.set_views_from_date(self.repo_first_viewed)
            self.__db.set_views_to_date(self.repo_last_viewed)

        self.store_repo_clone_count = (
                not store_repo_clone_count
                or store_repo_clone_count.strip().lower() != "false"
        )

        if self.store_repo_clone_count:
            try:
                if repo_clones:
                    self.repo_clones = int(repo_clones)
                    self.__db.set_clones_count(self.repo_clones)
                else:
                    self.repo_clones = self.__db.clones
            except ValueError:
                self.repo_clones = self.__db.clones

            if repo_last_cloned:
                try:
                    if repo_last_cloned == datetime\
                            .strptime(repo_last_cloned, self.__DATE_FORMAT)\
                            .strftime(self.__DATE_FORMAT):
                        self.repo_last_cloned = repo_last_cloned
                except ValueError:
                    self.repo_last_cloned = self.__db.clones_to_date
            else:
                self.repo_last_cloned = self.__db.clones_to_date

            if repo_first_cloned:
                try:
                    if repo_first_cloned == datetime\
                            .strptime(repo_first_cloned, self.__DATE_FORMAT)\
                            .strftime(self.__DATE_FORMAT):
                        self.repo_first_cloned = repo_first_cloned
                except ValueError:
                    self.repo_first_cloned = self.__db.clones_from_date
            else:
                self.repo_first_cloned = self.__db.clones_from_date
        else:
            self.repo_clones = 0
            self.__db.set_clones_count(self.repo_clones)
            self.repo_last_cloned = "0000-00-00"
            self.repo_first_cloned = "0000-00-00"
            self.__db.set_clones_from_date(self.repo_first_cloned)
            self.__db.set_clones_to_date(self.repo_last_cloned)

        try:
            self.more_collabs = int(more_collabs) if more_collabs else 0
        except ValueError:
            self.more_collabs = 0

        if manually_added_repos is None:
            self.manually_added_repos = set()
        else:
            self.manually_added_repos = (
                {x.strip() for x in manually_added_repos.split(",")}
            )

        if only_included_repos is None or only_included_repos == "":
            self.only_included_repos = set()
        else:
            self.only_included_repos = (
                {x.strip() for x in only_included_repos.split(",")}
            )

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
