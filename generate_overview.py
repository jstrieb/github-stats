#!/usr/bin/python3

import re
import os

from github_stats import Stats


################################################################################
# Main Function
################################################################################

def main():
    access_token = os.getenv("ACCESS_TOKEN")
    s = Stats("jstrieb", access_token)

    with open("templates/overview.svg", "r") as f:
        output = f.read()

    output = re.sub(r"{{ stars }}", f"{s.stargazers:,}", output)
    output = re.sub(r"{{ forks }}", f"{s.forks:,}", output)
    output = re.sub(r"{{ contributions }}", f"{s.total_contributions:,}", output)
    changed = s.lines_changed[0] + s.lines_changed[1]
    output = re.sub(r"{{ lines_changed }}", f"{changed:,}", output)
    output = re.sub(r"{{ views }}", f"{s.views:,}", output)
    output = re.sub(r"{{ repos }}", f"{len(s.repos):,}", output)

    if not os.path.isdir("generated"):
        os.mkdir("generated")
    with open("generated/overview.svg", "w") as f:
        f.write(output)


if __name__ == "__main__":
    main()
