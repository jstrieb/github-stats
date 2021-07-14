###############################################################################
# Scripts' location
###############################################################################

# If jstrieb's github-stats repository files have been copied directly to your
#   own repository in the base directory, set the 'import_path' variable below
#   to a null value (default: import_path = "").

# On the contrary, if said files have been enclosed in one or many directories,
#   specify these directories following the structure below:

#   Example: single folder enclosing:
#       path = "main_folder"

#   Example: multiple folder enclosing:
#       path = "main_folder/sub_folder"

import_path = ""

# Note: the '/' character at the end of each path is optional.

###############################################################################
# Output
###############################################################################

# Output directory location (default: export_path = ""):
export_path = ""

# Output files enclosing directory: (default: enclosing_folder = "generated"):
enclosing_directory = "generated"

###############################################################################
# Card customization
###############################################################################

# Excluded languages (item list) #

# Example:
#   excluded_languages = [
#       "language_1",
#       "language_2"
#       ]

excluded_languages = [
    ]

# Excluded repositories (collection) #

# Example:
#   excluded_repositories = [
#       "author/repository_1",
#       "author/repository_2"
#       ]

excluded_repositories = [
    ]

# Exclude forked repositories (boolean) #

# Example:
#   exclude_forked_repositories = True or False

exclude_forked_repositories = False
