from setuptools_scm import get_version

version = get_version(
    root=".",
    relative_to=__file__,
    version_scheme="no-guess-dev"
)

print("Repository Version from git:", version)
