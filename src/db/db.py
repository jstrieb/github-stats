#!/usr/bin/python3

from json import load, dumps

###############################################################################
# GitRepoStatsDB class
###############################################################################


class GitRepoStatsDB:

    def __init__(self):
        self.__db = None

        self.views = None
        self.views_start = None
        self.views_end = None

        self.clones = None
        self.clones_start = None
        self.clones_end = None

        try:
            with open("src/db/db.json", "r") as db:
                self.__db = load(db)
        except FileNotFoundError:
            with open("../src/db/db.json", "r") as db:
                self.__db = load(db)

        self.views = int(self.__db['views']['count'])
        self.views_from_date = self.__db['views']['from']
        self.views_to_date = self.__db['views']['to']

        self.clones = int(self.__db['clones']['count'])
        self.clones_from_date = self.__db['clones']['from']
        self.clones_to_date = self.__db['clones']['to']

    def __update_db(self) -> None:
        try:
            with open("src/db/db.json", "w") as db:
                db.write(dumps(self.__db, indent=2))
        except FileNotFoundError:
            with open("../src/db/db.json", "w") as db:
                db.write(dumps(self.__db, indent=2))

    def set_views_count(self, count: any) -> None:
        self.views = int(count)
        self.__db['views']['count'] = str(self.views)
        self.__update_db()

    def set_views_from_date(self, date: str) -> None:
        self.views_from_date = date
        self.__db['views']['from'] = self.views_from_date
        self.__update_db()

    def set_views_to_date(self, date: str) -> None:
        self.views_to_date = date
        self.__db['views']['to'] = self.views_to_date
        self.__update_db()

    def set_clones_count(self, count: any) -> None:
        self.clones = int(count)
        self.__db['clones']['count'] = str(self.clones)
        self.__update_db()

    def set_clones_from_date(self, date: str) -> None:
        self.clones_from_date = date
        self.__db['clones']['from'] = self.clones_from_date
        self.__update_db()

    def set_clones_to_date(self, date: str) -> None:
        self.clones_to_date = date
        self.__db['clones']['to'] = self.clones_to_date
        self.__update_db()
