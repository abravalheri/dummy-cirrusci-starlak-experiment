load("cirrus", environ="env")
load("github.com/abravalheri/cirrus-starlak-helpers/lib.star@98bef52",
     "task", "container", "script", "use_deep_clone", "cache", "powershell",
     "windows_container")

VERSIONS = {
    "nuget": "v5.10.0",
    "git": "2.32.0.2",
    "python": "3.8"
}

def main():
    print("CIRRUS_PR", environ.get("CIRRUS_PR"))
    print("CIRRUS_REPO_CLONE_TOKEN exists", "CIRRUS_REPO_CLONE_TOKEN" in environ)
    print("CIRRUS_REPO_FULL_NAME", environ.get("CIRRUS_REPO_FULL_NAME"))
    print("CIRRUS_CHANGE_IN_REPO", environ.get("CIRRUS_CHANGE_IN_REPO"))
    print("CIRRUS_WORKING_DIR", environ.get("CIRRUS_WORKING_DIR"))
    tasks = [
        use_deep_clone(linux_task(), before="test_script"),
        use_deep_clone(windows_task(), before="install_script")
    ]
    return dict(
        execution(tasks).items(),
        p1_pipe=pipeline(),
        other_pipe=other_pipe()
    )

def execution(tasks):
    """Experiment to see if Cirrus allow arbitrary keys for tasks"""
    return {_task_key(t, i): t for i, t in enumerate(tasks)}


def _task_key(desc, default_name):
    name = desc.get('name', str(default_name))
    if not name.endswith('task'):
        return name + ' task'
    return name


def pipeline():
    return {
        "name": "Example Pipeline",
        "steps": [
            {"image": "python:3.7-buster",
             "1_script": """python -c 'import sys; print("step 1", sys.version)'"""},
            {"image": "python:3.8-buster",
             "2_script": """python -c 'import sys; print("step 2", sys.version)'"""},
        ]
    }


def other_pipe():
    return {
        "name": "Example Pipeline",
        "steps": [
            {"image": "python:3.6-buster",
             "1_script": """python -c 'import sys; print("other step 1", sys.version)'"""},
            {"image": "python:3.9-buster",
             "2_script": """python -c 'import sys; print("other step 2", sys.version)'"""},
        ]
    }


def linux_task():
    return task(
        name="Linux - Debian (buster)",
        instance=container("python:%s-buster" % VERSIONS["python"]),
        instructions=[
            script(
                "install",
                "apt-get install -y git",
                "python -m pip install -U pip setuptools setuptools-scm"
            ),
            _test_script(),
        ]
    )


def windows_task():
    return task(
        name="Windows (windowsservercore: 2019)",
        instance=windows_container("python:%s-windowsservercore" % VERSIONS["python"], 2019),
        env=_windows_env(),
        instructions=[
            _install_windows_tools()
        ] + _windows_workarounds() + [
            script(
                "install",
                "python -m ensurepip",
                "python -m pip install -U --user pip certifi setuptools setuptools-scm"
            ),
            _test_script()
        ]
    )


def _test_script():
    return script(
        "test",
        "git config --global user.email 'ci@cirrus'",
        "git config --global user.name 'CI Automation'",
        "python simple-test.py"
    )


def _install_windows_tools():
    nuget_url = "https://dist.nuget.org/win-x86-commandline/%s/nuget.exe" % VERSIONS["nuget"]

    spec = cache(name="tools", folder=r"C:\tools")
    tools_cache = spec["tools_cache"]
    tools_cache.update(powershell("fingerprint", "echo %%CIRRUS_OS%% - nuget %(nuget)s - git %(git)s" % VERSIONS))
    tools_cache.update(
        powershell(
            "populate",
            r"(mkdir 'C:\tools')",
            r"Invoke-WebRequest -OutFile 'C:\tools\nuget.exe' '%s'" % nuget_url,
            r"nuget install GitForWindows -Version %s -NonInteractive -OutputDirectory 'C:\tools'" % VERSIONS["git"],
        )
    )

    return spec


def _windows_env():
    return {
        "PYTHON_HOME": r"C:\Python",
        "PYTHON_APPDATA": r"%%APPDATA%%\Python\Python%s" % VERSIONS["python"],
        "GIT_HOME": r"C:\tools\GitForWindows.%s\tools" % VERSIONS["git"],
        "HOME": "%USERPROFILE%",
        "USERNAME": "ContainerAdministrator",
        "PATH": r"%HOME%\.local\bin\;"
                + r"%PYTHON_APPDATA%\Scripts\;"
                + r"%PYTHON_HOME%\;"
                + r"%PYTHON_HOME%\Scripts\;"
                + r"C:\tools\;"
                + r"%GIT_HOME%\cmd\;"
                + r"%GIT_HOME%\usr\bin\;"
                + r"%PATH%",
        "PIP_TRUSTED_HOST": "pypi.org pypi.python.org files.pythonhosted.org",
        "PIP_CONFIG_FILE": r"%AppData%\pip\pip.ini",
    }

def _windows_workarounds():
    return [
        script(
            "long_paths_workaround",
            # Activate long file paths to avoid some errors
            "git config --system core.longpaths true",
            r"REG ADD HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\FileSystem /v LongPathsEnabled /t REG_DWORD /d 1 /f",
        ),
        script(
            "encoding_workaround",
            # Set Windows encoding to UTF-8
            r'REG ADD "HKEY_CURRENT_USER\Software\Microsoft\Command Processor" /v Autorun /t REG_SZ /d "@chcp 65001>nul" /f'
        )
    ]
