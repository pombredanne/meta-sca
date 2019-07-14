inherit sca-conv-to-export
inherit sca-datamodel
inherit sca-global
inherit sca-helper
inherit sca-license-filter

def do_sca_conv_pylint(d):
    import os
    import re
    
    package_name = d.getVar("PN")
    buildpath = d.getVar("SCA_SOURCES_DIR")

    pattern = r"^(?P<file>.*):(?P<line>\d+):\s+\[(?P<raw_severity>\w+)\((?P<raw_severity_id>.*)\).*\]\s+(?P<message>.*)"

    severity_map = {
        "F" : "error",
        "E" : "error",
        "W" : "warning",
        "R" : "info",
        "C" : "info"
    }

    if os.path.exists(d.getVar("SCA_RAW_RESULT_FILE")):
        with open(d.getVar("SCA_RAW_RESULT_FILE"), "r") as f:
            for m in re.finditer(pattern, f.read(), re.MULTILINE):
                try:
                    g = sca_get_model_class(d,
                                            PackageName=package_name,
                                            Tool="pylint",
                                            BuildPath=buildpath,
                                            File=m.group("file"),
                                            Line=m.group("line"),
                                            Message=m.group("message"),
                                            ID=m.group("raw_severity_id"),
                                            Severity=severity_map[m.group("raw_severity")[0]])
                    if g.Severity in sca_allowed_warning_level(d):
                        sca_add_model_class(d, g)
                except Exception as exp:
                    bb.warn(str(exp))

    return sca_save_model_to_string(d)

python do_sca_pylint_core() {
    import os
    import subprocess
    d.setVar("SCA_EXTRA_SUPPRESS", d.getVar("SCA_PYLINT_EXTRA_SUPPRESS"))
    d.setVar("SCA_EXTRA_FATAL", d.getVar("SCA_PYLINT_EXTRA_FATAL"))
    d.setVar("SCA_SUPRESS_FILE", os.path.join(d.getVar("STAGING_DATADIR_NATIVE", True), "pylint-{}-suppress".format(d.getVar("SCA_MODE"))))
    d.setVar("SCA_FATAL_FILE", os.path.join(d.getVar("STAGING_DATADIR_NATIVE", True), "pylint-{}-fatal".format(d.getVar("SCA_MODE"))))

    _suppress = get_suppress_entries(d)

    _args = ["python3", "-m", "pylint"]
    _args += ["--output-format=parseable"]
    _args += ["--score=no"]
    if any(_suppress):
        _args += ["--disable={}".format(",".join(_suppress))]
    _args += ["--rcfile={}/pylint.rc".format(d.getVar("T"))]
    _args += get_files_by_extention_or_shebang(d, d.getVar("SCA_SOURCES_DIR"), d.getVar("SCA_PYTHON_SHEBANG"), [".py"])
    if d.getVar("SCA_PYLINT_EXTRA"):
        _args += d.getVar("SCA_PYLINT_EXTRA").split(" ")
    _args += ["-j", d.getVar("BB_NUMBER_THREADS")]

    ## Run
    cur_dir = os.getcwd()
    os.chdir(d.getVar("SCA_SOURCES_DIR", True))
    cmd_output = ""
    tmp_result = os.path.join(d.getVar("T", True), "sca_raw_pylint.txt")
    d.setVar("SCA_RAW_RESULT_FILE", tmp_result)

    ## Patch a pylint.rc-file with all the library paths
    with open(os.path.join(d.getVar("T"), "pylint.rc"), "w") as f:
        f.write("[MASTER]\n")
        f.write('init-hook="import sys;[sys.path.insert(0, a) for a in \'{}\'.split(\':\')]'.format(d.getVar("SCA_PYLINT_LIBATH")) + '"')

    _files = get_files_by_extention_or_shebang(d, d.getVar("SCA_SOURCES_DIR"), d.getVar("SCA_PYTHON_SHEBANG"), ".py",
                                               sca_filter_files(d, d.getVar("SCA_SOURCES_DIR"), clean_split(d, "SCA_FILE_FILTER_EXTRA")))

    if any(_files):
        try:
            cmd_output = subprocess.check_output(_args, universal_newlines=True, stderr=subprocess.STDOUT)
        except subprocess.CalledProcessError as e:
            cmd_output = e.stdout or ""
    with open(tmp_result, "w") as o:
        o.write(cmd_output)
    os.chdir(cur_dir)
    
    ## Create data model
    d.setVar("SCA_DATAMODEL_STORAGE", "{}/pylint.dm".format(d.getVar("T")))
    dm_output = do_sca_conv_pylint(d)
    with open(d.getVar("SCA_DATAMODEL_STORAGE"), "w") as o:
        o.write(dm_output)

    sca_task_aftermath(d, "pylint", get_fatal_entries(d))
}

## addtask do_static_code_analysis_pylint before do_install after do_compile

DEPENDS += "${SCA_STD_PYTHON_INTERPRETER}-pylint-native"
