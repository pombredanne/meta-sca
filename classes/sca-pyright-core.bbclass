## SPDX-License-Identifier: BSD-2-Clause
## Copyright (c) 2019, Konrad Weihmann

## Add ids to suppress on a recipe level
SCA_PYRIGHT_EXTRA_SUPPRESS ?= ""
## Add ids to lead to a fatal on a recipe level
SCA_PYRIGHT_EXTRA_FATAL ?= ""

_SCA_PYRIGHT_AVAILABLE_CHECKS = "\
                                strictListInference \
                                strictDictionaryInference \
                                strictParameterNoneValue \
                                reportUnusedImport \
                                reportUnusedClass \
                                reportUnusedFunction \
                                reportUnusedVariable \
                                reportOptionalSubscript \
                                reportOptionalMemberAccess \
                                reportOptionalCall \
                                reportOptionalIterable \
                                reportOptionalContextManager \
                                reportOptionalOperand \
                                reportUntypedFunctionDecorator \
                                reportUntypedClassDecorator \
                                reportUntypedBaseClass \
                                reportUntypedNamedTuple \
                                reportPrivateUsage \
                                reportConstantRedefinition \
                                reportIncompatibleMethodOverride \
                                reportInvalidStringEscapeSequence \
                                reportCallInDefaultInitializer \
                                reportUnnecessaryIsInstance \
                                reportUnnecessaryCast \
                                reportAssertAlwaysTrue \
                            "
SCA_PYRIGHT_ENABLED_CHECKS ?= "\
                                strictListInference \
                                strictDictionaryInference \
                                strictParameterNoneValue \
                                reportUnusedImport \
                                reportUnusedClass \
                                reportUnusedFunction \
                                reportUnusedVariable \
                                reportOptionalSubscript \
                                reportOptionalMemberAccess \
                                reportOptionalCall \
                                reportOptionalIterable \
                                reportOptionalContextManager \
                                reportOptionalOperand \
                                reportUntypedFunctionDecorator \
                                reportUntypedClassDecorator \
                                reportUntypedBaseClass \
                                reportUntypedNamedTuple \
                                reportPrivateUsage \
                                reportConstantRedefinition \
                                reportIncompatibleMethodOverride \
                                reportInvalidStringEscapeSequence \
                                reportCallInDefaultInitializer \
                                reportUnnecessaryIsInstance \
                                reportUnnecessaryCast \
                                reportAssertAlwaysTrue \
                            "

SCA_RAW_RESULT_FILE[pyright] = "json"

inherit sca-conv-to-export
inherit sca-datamodel
inherit sca-global
inherit sca-helper
inherit sca-license-filter
inherit sca-suppress

inherit python3native

def do_sca_conv_pyright(d):
    import os
    import json
    import hashlib
    
    package_name = d.getVar("PN")
    buildpath = d.getVar("SCA_SOURCES_DIR")

    _findings = []
    _suppress = sca_suppress_init(d)

    _severity_map = {
        "error": "error",
        "warning": "warning"
    }

    if os.path.exists(sca_raw_result_file(d, "pyright")):
        try:
            with open(sca_raw_result_file(d, "pyright"), "r") as f:
                content = json.load(f)
                for m in content["diagnostics"]:
                    try:
                        g = sca_get_model_class(d,
                                                PackageName=package_name,
                                                Tool="pyright",
                                                BuildPath=buildpath,
                                                File=m["file"],
                                                Line=str(m["range"]["start"]["line"] + 1),
                                                Message=m["message"],
                                                ID=hashlib.md5(str.encode(m["message"])).hexdigest(),
                                                Severity=_severity_map[m["severity"]])
                        if _suppress.Suppressed(g):
                            continue
                        if g.Scope not in clean_split(d, "SCA_SCOPE_FILTER"):
                            continue
                        if g.Severity in sca_allowed_warning_level(d):
                            _findings.append(g)
                    except Exception as exp:
                        bb.warn(str(exp))
        except Exception as e:
            pass

    sca_add_model_class_list(d, _findings)
    return sca_save_model_to_string(d)

def sca_create_pyright_config(d, excludes, includes):
    res = {
        "include" : includes,
        "excludes": excludes,
        "pythonPlatform": "Linux",
    }
    _all = clean_split(d, "_SCA_PYRIGHT_AVAILABLE_CHECKS")
    _enabled = clean_split(d, "SCA_PYRIGHT_ENABLED_CHECKS")
    for i in [x for x in _all if x not in _enabled]:
        res[i] = False
    for i in _enabled:
        res[i] = True
    return res

def sca_chunckify_input(_in, n):
    for i in range(0, len(_in), n):
        yield _in[i:i + n]

python do_sca_pyright_core() {
    import os
    import subprocess
    import json

    d.setVar("SCA_EXTRA_SUPPRESS", d.getVar("SCA_PYRIGHT_EXTRA_SUPPRESS"))
    d.setVar("SCA_EXTRA_FATAL", d.getVar("SCA_PYRIGHT_EXTRA_FATAL"))
    d.setVar("SCA_SUPRESS_FILE", os.path.join(d.getVar("STAGING_DATADIR_NATIVE", True), "pyright-{}-suppress".format(d.getVar("SCA_MODE"))))
    d.setVar("SCA_FATAL_FILE", os.path.join(d.getVar("STAGING_DATADIR_NATIVE", True), "pyright-{}-fatal".format(d.getVar("SCA_MODE"))))

    _config_path = os.path.join(d.getVar("T"), "pyright.config")

    _args = ["pyright"]
    _args += ["--outputjson"]
    _args += ["-p", _config_path]

    ## Run
    cmd_output = {}

    _includes = [   d.getVar("SCA_SOURCES_DIR") + "/*",    
                    d.getVar("SCA_SOURCES_DIR") + "/**/*",
                    os.path.join(d.getVar("STAGING_DIR"), d.getVar("libdir").lstrip("/"), d.getVar("PYTHON_DIR")) + "/*",
                    os.path.join(d.getVar("STAGING_DIR"), d.getVar("libdir").lstrip("/"), d.getVar("PYTHON_DIR")) + "/**/*",
                    os.path.join(d.getVar("STAGING_DIR"), d.getVar("PYTHON_SITEPACKAGES_DIR").lstrip("/")) + "/*",
                    os.path.join(d.getVar("STAGING_DIR"), d.getVar("PYTHON_SITEPACKAGES_DIR").lstrip("/")) + "/**/*"
                ]
    _excludes = sca_filter_files(d, d.getVar("SCA_SOURCES_DIR"), clean_split(d, "SCA_FILE_FILTER_EXTRA"))

    _files = get_files_by_extention_or_shebang(d, d.getVar("SCA_SOURCES_DIR"), d.getVar("SCA_PYTHON_SHEBANG"), ".py", _excludes)

    if any(_files):
        with open(_config_path, "w") as o:
            json.dump(sca_create_pyright_config(d, _excludes, _includes), o)
        ## output from the command is somehow limited to ARG_MAX (~128k)
        ## which makes it impossible to run on an larger set of files
        ## therefore we split the set into chunks
        ## and put the results back together afterwards
        ## (and keep our fingers crossed that 5 files don't produce more than 128k of output)
        os.environ["PYTHONPATH"] = ":".join([
                                        d.getVar("SCA_SOURCES_DIR"),
                                        os.path.join(d.getVar("STAGING_DIR"), d.getVar("libdir").lstrip("/"), d.getVar("PYTHON_DIR")),    
                                        os.path.join(d.getVar("STAGING_DIR"), d.getVar("PYTHON_SITEPACKAGES_DIR").lstrip("/"))
                                    ])
        for f in sca_chunckify_input(_files, 5):
            try:
                _tmp = subprocess.check_output(_args + f, universal_newlines=True, stderr=subprocess.STDOUT)
            except subprocess.CalledProcessError as e:
                _tmp = e.stdout or ""
            if not _tmp.strip().endswith("}"):
                _tmp = _tmp[:_tmp.rfind("}") + 1]
            try:
                if not cmd_output or "diagnostics" not in cmd_output:
                    cmd_output = json.loads(_tmp)
                else:
                    cmd_output["diagnostics"] += json.loads(_tmp)["diagnostics"]
            except Exception as e:
                pass
    with open(sca_raw_result_file(d, "pyright"), "w") as o:
        json.dump(cmd_output, o)
}

python do_sca_pyright_core_report() {
    import os
    ## Create data model
    d.setVar("SCA_DATAMODEL_STORAGE", "{}/pyright.dm".format(d.getVar("T")))
    dm_output = do_sca_conv_pyright(d)
    with open(d.getVar("SCA_DATAMODEL_STORAGE"), "w") as o:
        o.write(dm_output)

    sca_task_aftermath(d, "pyright", get_fatal_entries(d))
}

DEPENDS += "pyright-native"
